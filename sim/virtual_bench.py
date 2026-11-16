#!/usr/bin/env python3
"""
Bancada Virtual Interativa: FPGA Cyclone V (DE0-CV) + ESP32-S3 MIDI Synth.

Interface grafica leve em Tkinter com audio PCM 44.1 kHz 16-bit estereo em
tempo real via WinMM (waveOutOpen/waveOutWrite) conectado diretamente ao motor
ciclo-exato C++ (sim/cosim_engine.dll):
  - Displays de 7 segmentos HEX5..HEX0 renderizados a partir dos pinos da FPGA
  - 7 LEDs vermelhos com brilho modulado pelo PWM real da FPGA + LEDs de status
  - 7 teclas do piano (Do..Si / atalhos A..J) + modo Travar Teclas (Acordes)
  - Chave Sustenido (W), Modo (M), Musica (N), Oitava +/- (E/Q), Intensidade (I),
    Combo de Volume (Modo + Intensidade) e Reset (R)
  - Monitor em tempo real do ESP32-S3 (Vozes TSF, VU Meter L/R, pacotes UART MIDI)
"""

import argparse
import ctypes
from pathlib import Path
import sys
import time
from typing import List, Optional

from run_cosim_tests import build_cosim_binaries


SONG_NAMES = [
    "00: Axel F",
    "01: Bad Romance",
    "02: Beat It",
    "03: Careless Whisper",
    "04: Clair de Lune",
    "05: Clocks",
    "06: Do Re Mi Fa",
    "07: Epitafio",
    "08: Fukashigi No Carte",
    "09: Fur Elise",
    "10: Golden",
    "11: Golden Wind",
    "12: Harry Potter",
    "13: Head Over Heels",
    "14: Hey Jude",
    "15: Homem Aranha 1900",
    "16: Imperial March",
    "17: Interestelar",
    "18: Jump Up Super Star",
    "19: Korobeiniki (Tetris)",
    "20: Lugar Ao Sol",
    "21: Magnetic",
    "22: Super Mario Bros",
    "23: Minecraft (Sweden)",
    "24: Moonlight Sonata 3mvt",
    "25: Morning Flower",
    "26: Never Gonna Give You Up",
    "27: New Donk City",
    "28: Numb",
    "29: Pink Panther",
    "30: Radio Ga Ga",
    "31: Sadness And Sorrow",
    "32: Super Idol",
    "33: Susanne",
    "34: Sweet Child O' Mine",
    "35: Take On Me",
    "36: Trem Das Onze",
    "37: Undertale (Megalovania)",
    "38: We Are Number One",
    "39: When Love Takes Over",
    "40: Wii Sports",
    "41: Zelda (Lost Woods)",
    "42: [RAM] Gravacao do Usuario",
]

MODE_NAMES = {
    0: "Modo 0: Livre",
    1: "Modo 1: Aprendizado (ROM)",
    2: "Modo 2: Gravacao (RAM)",
    3: "Modo 3: Demonstracao (Auto)",
}

NOTE_NAMES = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]


class CoSimBenchStatus(ctypes.Structure):
  _fields_ = [
      ("hex5_modo", ctypes.c_uint8),
      ("hex4_oitava", ctypes.c_uint8),
      ("hex3_musica_dezena", ctypes.c_uint8),
      ("hex2_musica_unidade", ctypes.c_uint8),
      ("hex1_nota", ctypes.c_uint8),
      ("hex0_sustenido", ctypes.c_uint8),
      ("led_vermelho_pwm", ctypes.c_uint8 * 7),
      ("led_sustenido", ctypes.c_uint8),
      ("led_oitava_up", ctypes.c_uint8),
      ("led_oitava_down", ctypes.c_uint8),
      ("servo_controle", ctypes.c_uint8),
      ("modo_ativo", ctypes.c_uint8),
      ("oitava_atual", ctypes.c_uint8),
      ("sustenido_atual", ctypes.c_uint8),
      ("sel_musica", ctypes.c_uint8),
      ("volume_state", ctypes.c_uint8),
      ("mostra_vol", ctypes.c_uint8),
      ("endereco_partitura", ctypes.c_uint16),
      ("tsf_active_voices", ctypes.c_int32),
      ("tsf_sustained_voices", ctypes.c_int32),
      ("peak_l", ctypes.c_int32),
      ("peak_r", ctypes.c_int32),
      ("last_midi_status", ctypes.c_uint8),
      ("last_midi_data1", ctypes.c_uint8),
      ("last_midi_data2", ctypes.c_uint8),
      ("midi_note_on_count", ctypes.c_uint32),
      ("midi_note_off_count", ctypes.c_uint32),
      ("uart_bytes_count", ctypes.c_uint32),
      ("overlap_violations", ctypes.c_uint32),
      ("stuck_note_alert", ctypes.c_uint8),
      ("metro_posicao", ctypes.c_uint8),
      ("led_brightness_state", ctypes.c_uint8),
  ]


# Estruturas WinMM WaveOut (44.1 kHz 16-bit Estereo)
class WAVEFORMATEX(ctypes.Structure):
  _fields_ = [
      ("wFormatTag", ctypes.c_uint16),
      ("nChannels", ctypes.c_uint16),
      ("nSamplesPerSec", ctypes.c_uint32),
      ("nAvgBytesPerSec", ctypes.c_uint32),
      ("nBlockAlign", ctypes.c_uint16),
      ("wBitsPerSample", ctypes.c_uint16),
      ("cbSize", ctypes.c_uint16),
  ]


class WAVEHDR(ctypes.Structure):
  _fields_ = [
      ("lpData", ctypes.c_char_p),
      ("dwBufferLength", ctypes.c_uint32),
      ("dwBytesRecorded", ctypes.c_uint32),
      ("dwUser", ctypes.c_size_t),
      ("dwFlags", ctypes.c_uint32),
      ("dwLoops", ctypes.c_uint32),
      ("lpNext", ctypes.c_void_p),
      ("reserved", ctypes.c_size_t),
  ]


WAVE_FORMAT_PCM = 1
WAVE_MAPPER = 0xFFFFFFFF
WHDR_DONE = 0x00000001
WHDR_PREPARED = 0x00000002


class WinMMAudioStream:
  """Streaming PCM 44.1 kHz 16-bit Estereo de baixa latencia via winmm.dll."""

  def __init__(self, sample_rate: int = 44100, num_buffers: int = 12):
    self.available = False
    self.hwaveout = ctypes.c_void_p(0)
    self.num_buffers = num_buffers
    self.headers: List[WAVEHDR] = []
    self.buffers: List[ctypes.Array] = []
    self.buf_idx = 0

    if sys.platform != "win32":
      return

    try:
      self.winmm = ctypes.windll.winmm
      wfx = WAVEFORMATEX()
      wfx.wFormatTag = WAVE_FORMAT_PCM
      wfx.nChannels = 2
      wfx.nSamplesPerSec = sample_rate
      wfx.wBitsPerSample = 16
      wfx.nBlockAlign = 4
      wfx.nAvgBytesPerSec = sample_rate * 4
      wfx.cbSize = 0

      res = self.winmm.waveOutOpen(
          ctypes.byref(self.hwaveout),
          WAVE_MAPPER,
          ctypes.byref(wfx),
          0,
          0,
          0,
      )
      if res == 0 and self.hwaveout.value:
        self.available = True
        # Cada slot comporta ate 8 blocos de 256 frames (2048 frames = 8192 bytes)
        for _ in range(self.num_buffers):
          buf = (ctypes.c_char * 8192)()
          hdr = WAVEHDR()
          hdr.lpData = ctypes.cast(buf, ctypes.c_char_p)
          hdr.dwBufferLength = 8192
          hdr.dwFlags = 0
          self.winmm.waveOutPrepareHeader(
              self.hwaveout, ctypes.byref(hdr), ctypes.sizeof(WAVEHDR)
          )
          hdr.dwFlags |= WHDR_DONE
          self.buffers.append(buf)
          self.headers.append(hdr)
    except Exception:
      self.available = False

  def in_flight_buffers(self) -> int:
    if not self.available:
      return 0
    return sum(1 for hdr in self.headers if not (hdr.dwFlags & WHDR_DONE))

  def write_pcm(self, pcm_array: ctypes.Array, num_bytes: int) -> bool:
    if not self.available or num_bytes <= 0 or num_bytes > 8192:
      return False
    hdr = self.headers[self.buf_idx]
    if not (hdr.dwFlags & WHDR_DONE):
      # Se todos os buffers estiverem ocupados, avanca sem bloquear a GUI
      return False
    buf = self.buffers[self.buf_idx]
    ctypes.memmove(buf, pcm_array, num_bytes)
    hdr.dwBufferLength = num_bytes
    self.winmm.waveOutWrite(
        self.hwaveout, ctypes.byref(hdr), ctypes.sizeof(WAVEHDR)
    )
    self.buf_idx = (self.buf_idx + 1) % self.num_buffers
    return True

  def close(self) -> None:
    if not self.available:
      return
    try:
      self.winmm.waveOutReset(self.hwaveout)
      for hdr in self.headers:
        if hdr.dwFlags & WHDR_PREPARED:
          self.winmm.waveOutUnprepareHeader(
              self.hwaveout, ctypes.byref(hdr), ctypes.sizeof(WAVEHDR)
          )
      self.winmm.waveOutClose(self.hwaveout)
    except Exception:
      pass
    self.available = False


def midi_note_label(note: int) -> str:
  if note <= 0 or note > 127:
    return "---"
  name = NOTE_NAMES[note % 12]
  octave = (note // 12) - 1
  return f"{name}{octave} (#{note})"


def load_cosim_dll(repo_root: Path) -> ctypes.CDLL:
  if not build_cosim_binaries(repo_root):
    raise RuntimeError("Falha ao compilar sim/cosim_engine.dll")
  dll_path = repo_root / "sim" / "cosim_engine.dll"
  dll = ctypes.CDLL(str(dll_path))

  dll.cosim_init.argtypes = [ctypes.c_int, ctypes.c_char_p]
  dll.cosim_init.restype = ctypes.c_int

  dll.cosim_set_inputs.argtypes = [
      ctypes.c_uint8,
      ctypes.c_uint8,
      ctypes.c_uint8,
      ctypes.c_uint8,
      ctypes.c_uint8,
      ctypes.c_uint8,
      ctypes.c_uint8,
      ctypes.c_uint8,
  ]
  dll.cosim_set_inputs.restype = None

  dll.cosim_step_audio_blocks.argtypes = [
      ctypes.c_int,
      ctypes.POINTER(ctypes.c_int16),
      ctypes.POINTER(CoSimBenchStatus),
  ]
  dll.cosim_step_audio_blocks.restype = ctypes.c_int
  return dll


def run_self_test(repo_root: Path) -> int:
  print("[SELF-TEST] Validando Bancada Virtual (DLL + Audio WinMM + Displays HEX)...")
  dll = load_cosim_dll(repo_root)
  rom_path = str(repo_root / "music" / "partituras.hex").encode("utf-8")
  dll.cosim_init(0, rom_path)

  audio = WinMMAudioStream()
  blocks_per_step = 3
  pcm_buf = (ctypes.c_int16 * (256 * 2 * blocks_per_step))()
  status = CoSimBenchStatus()

  # Passo 1: Estado inicial no Modo 0 (Livre), Oitava 4
  dll.cosim_set_inputs(0, 0, 1, 1, 1, 1, 1, 1)
  dll.cosim_step_audio_blocks(blocks_per_step, pcm_buf, ctypes.byref(status))
  assert status.modo_ativo == 0, f"Modo inicial inesperado: {status.modo_ativo}"
  assert status.oitava_atual == 4, f"Oitava inicial inesperada: {status.oitava_atual}"
  assert status.hex5_modo == 0x40, f"HEX5 esperado 0x40 ('0'), obtido {status.hex5_modo:#x}"
  assert status.hex4_oitava == 0x19, f"HEX4 esperado 0x19 ('4'), obtido {status.hex4_oitava:#x}"

  # Passo 2: Toca tecla Do4 (gpio_keys = 0x01)
  dll.cosim_set_inputs(0x01, 0, 1, 1, 1, 1, 1, 1)
  dll.cosim_step_audio_blocks(blocks_per_step, pcm_buf, ctypes.byref(status))
  audio.write_pcm(pcm_buf, ctypes.sizeof(pcm_buf))
  assert status.tsf_sustained_voices > 0, "Voz de Do4 nao ativou na bancada virtual"
  assert status.peak_l > 100 and status.peak_r > 100, "Pico de audio zerado ao tocar Do4"
  assert status.hex1_nota == 0x46, f"HEX1 esperado 0x46 ('C'), obtido {status.hex1_nota:#x}"

  # Passo 3: Solta tecla Do4 e verifica desligamento e ausencia de nota presa
  dll.cosim_set_inputs(0x00, 0, 1, 1, 1, 1, 1, 1)
  dll.cosim_step_audio_blocks(blocks_per_step, pcm_buf, ctypes.byref(status))
  assert status.tsf_sustained_voices == 0, "Voz continuou sustentada apos soltar tecla"
  assert status.stuck_note_alert == 0, "Alerta de nota presa disparou indevidamente"
  assert status.overlap_violations == 0, "Violacao de sobreposicao MIDI detectada"

  # Passo 4: Testa Combo de Volume (Modo + Intensidade) e retorno dos displays HEX apos 1s
  dll.cosim_set_inputs(0x00, 0, 0, 1, 1, 1, 1, 1)
  dll.cosim_step_audio_blocks(2, pcm_buf, ctypes.byref(status))
  dll.cosim_set_inputs(0x00, 0, 0, 1, 0, 1, 1, 1)
  dll.cosim_step_audio_blocks(2, pcm_buf, ctypes.byref(status))
  dll.cosim_set_inputs(0x00, 0, 0, 1, 1, 1, 1, 1)
  dll.cosim_step_audio_blocks(2, pcm_buf, ctypes.byref(status))
  dll.cosim_set_inputs(0x00, 0, 1, 1, 1, 1, 1, 1)
  dll.cosim_step_audio_blocks(2, pcm_buf, ctypes.byref(status))
  assert status.modo_ativo == 0, "Combo de volume alterou o modo indevidamente"
  assert status.volume_state == 1 and status.mostra_vol == 1, "Combo nao ativou 75%"
  assert status.hex4_oitava == 0x78 and status.hex3_musica_dezena == 0x12, "HEX nao exibiu 75P"

  # Avanca ~1s (~180 blocos de 5.8ms) e verifica que mostra_vol expira e HEX volta ao normal
  for _ in range(60):
    dll.cosim_step_audio_blocks(blocks_per_step, pcm_buf, ctypes.byref(status))
  assert status.mostra_vol == 0 and status.hex4_oitava == 0x19, "HEX4 nao voltou para oitava 4 apos 1s"

  audio.close()
  print("[SELF-TEST] Validando loop interativo Tkinter (launch_gui auto_test)...")
  launch_gui(repo_root, full_50mhz=False, auto_test_gui=True)
  print("[SELF-TEST] OK: Bancada Virtual validada com sucesso!")
  return 0


def launch_gui(
    repo_root: Path, full_50mhz: bool = False, auto_test_gui: bool = False
) -> int:
  import tkinter as tk
  from tkinter import ttk

  dll = load_cosim_dll(repo_root)
  rom_path = str(repo_root / "music" / "partituras.hex").encode("utf-8")
  dll.cosim_init(1 if full_50mhz else 0, rom_path)

  audio = WinMMAudioStream()

  root = tk.Tk()
  root.title("Bancada Virtual DE0-CV (Cyclone V) + ESP32-S3 MIDI Synth")
  root.configure(bg="#181a1f")
  root.resizable(False, False)

  # Estado de entradas da placa
  held_keys_mouse = [False] * 7
  held_keys_kb = [False] * 7
  latch_keys = [False] * 7
  latch_mode_var = tk.BooleanVar(value=False)
  sustenido_var = tk.BooleanVar(value=False)
  hold_modo_var = tk.BooleanVar(value=False)

  # Fila de pulsos momentaneos em botoes de controle (quantizados em steps de ~17ms)
  pulse_counters = {
      "modo": 0,
      "musica": 0,
      "intensidade": 0,
      "oit_up": 0,
      "oit_down": 0,
      "reset": 0,
      "combo_vol": 0,
  }

  # ==========================================================================
  # 1. Painel Superior: Displays de 7 Segmentos (HEX5..HEX0) e LEDs da FPGA
  # ==========================================================================
  top_frame = tk.Frame(root, bg="#21252b", bd=2, relief=tk.RIDGE, padx=12, pady=10)
  top_frame.pack(fill=tk.X, padx=12, pady=(12, 6))

  title_lbl = tk.Label(
      top_frame,
      text="PAINEL FPGA DE0-CV ( SINAIS REAIS DO VPIANO_TOP )",
      fg="#61afef",
      bg="#21252b",
      font=("Consolas", 11, "bold"),
  )
  title_lbl.pack(anchor="w", pady=(0, 6))

  hex_row = tk.Frame(top_frame, bg="#21252b")
  hex_row.pack(fill=tk.X)

  hex_labels = [
      ("HEX5 (Modo/Vol)", 5),
      ("HEX4 (Oitava)", 4),
      ("HEX3 (Dezena)", 3),
      ("HEX2 (Unidade)", 2),
      ("HEX1 (Nota)", 1),
      ("HEX0 (Sust #)", 0),
  ]
  hex_canvases = []
  hex_seg_items = []

  # Coordenadas dos 7 segmentos (a..g) em um canvas 56x82
  seg_coords = [
      (12, 8, 44, 14),   # a (topo)
      (42, 12, 48, 40),  # b (dir sup)
      (42, 44, 48, 72),  # c (dir inf)
      (12, 70, 44, 76),  # d (base)
      (8, 44, 14, 72),   # e (esq inf)
      (8, 12, 14, 40),   # f (esq sup)
      (12, 39, 44, 45),  # g (meio)
  ]

  for label_txt, _ in hex_labels:
    col = tk.Frame(hex_row, bg="#21252b", padx=6)
    col.pack(side=tk.LEFT)
    tk.Label(
        col, text=label_txt, fg="#abb2bf", bg="#21252b", font=("Consolas", 8)
    ).pack()
    cv = tk.Canvas(
        col, width=56, height=84, bg="#111317", highlightthickness=1, highlightbackground="#3e4451"
    )
    cv.pack(pady=3)
    items = []
    for x1, y1, x2, y2 in seg_coords:
      it = cv.create_rectangle(x1, y1, x2, y2, fill="#282c34", outline="")
      items.append(it)
    hex_canvases.append(cv)
    hex_seg_items.append(items)

  # Painel lateral de LEDs de status e Info de Modo/Musica
  status_col = tk.Frame(hex_row, bg="#21252b", padx=16)
  status_col.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)

  mode_info_var = tk.StringVar(value="Modo 0: Livre")
  song_info_var = tk.StringVar(value="00: Axel F")
  detail_info_var = tk.StringVar(value="Oitava: 4 | Volume: 100% | Endereco: 0")

  tk.Label(
      status_col,
      textvariable=mode_info_var,
      fg="#98c379",
      bg="#21252b",
      font=("Consolas", 11, "bold"),
      anchor="w",
  ).pack(fill=tk.X)
  tk.Label(
      status_col,
      textvariable=song_info_var,
      fg="#e5c07b",
      bg="#21252b",
      font=("Consolas", 10, "bold"),
      anchor="w",
  ).pack(fill=tk.X, pady=2)
  tk.Label(
      status_col,
      textvariable=detail_info_var,
      fg="#abb2bf",
      bg="#21252b",
      font=("Consolas", 9),
      anchor="w",
  ).pack(fill=tk.X)

  aux_led_frame = tk.Frame(status_col, bg="#21252b", pady=6)
  aux_led_frame.pack(anchor="w")

  def make_indicator(parent, text):
    fr = tk.Frame(parent, bg="#21252b", padx=6)
    fr.pack(side=tk.LEFT)
    cv = tk.Canvas(
        fr, width=18, height=18, bg="#21252b", highlightthickness=0
    )
    cv.pack(side=tk.LEFT)
    oval = cv.create_oval(2, 2, 16, 16, fill="#2c313a", outline="#4b5263")
    tk.Label(
        fr, text=text, fg="#abb2bf", bg="#21252b", font=("Consolas", 8)
    ).pack(side=tk.LEFT, padx=3)
    return cv, oval

  cv_led_sust, oval_led_sust = make_indicator(aux_led_frame, "LED Sustenido")
  cv_led_down, oval_led_down = make_indicator(aux_led_frame, "LED Oitava -")
  cv_led_up, oval_led_up = make_indicator(aux_led_frame, "LED Oitava +")
  cv_servo, oval_servo = make_indicator(aux_led_frame, "Servo Metronomo")

  # ==========================================================================
  # 2. Painel de Botoes de Controle da Placa (Modo, Musica, Oitava, Volume)
  # ==========================================================================
  ctrl_frame = tk.Frame(root, bg="#21252b", bd=2, relief=tk.RIDGE, padx=12, pady=8)
  ctrl_frame.pack(fill=tk.X, padx=12, pady=6)

  def trigger_pulse(name: str, duration_steps: int = 2):
    pulse_counters[name] = duration_steps

  btn_style = {
      "bg": "#323842",
      "fg": "#ffffff",
      "activebackground": "#4b5263",
      "activeforeground": "#ffffff",
      "font": ("Consolas", 9, "bold"),
      "padx": 10,
      "pady": 4,
      "bd": 1,
  }

  tk.Button(
      ctrl_frame,
      text="Modo [M]",
      command=lambda: trigger_pulse("modo", 2),
      **btn_style,
  ).pack(side=tk.LEFT, padx=4)

  tk.Button(
      ctrl_frame,
      text="Musica + [N]",
      command=lambda: trigger_pulse("musica", 2),
      **btn_style,
  ).pack(side=tk.LEFT, padx=4)

  tk.Button(
      ctrl_frame,
      text="Oitava - [Q]",
      command=lambda: trigger_pulse("oit_down", 2),
      **btn_style,
  ).pack(side=tk.LEFT, padx=4)

  tk.Button(
      ctrl_frame,
      text="Oitava + [E]",
      command=lambda: trigger_pulse("oit_up", 2),
      **btn_style,
  ).pack(side=tk.LEFT, padx=4)

  tk.Button(
      ctrl_frame,
      text="Brilho LED [I]",
      command=lambda: trigger_pulse("intensidade", 2),
      **btn_style,
  ).pack(side=tk.LEFT, padx=4)

  tk.Button(
      ctrl_frame,
      text="Combo Volume (Modo+Int) [V]",
      bg="#3b4c66",
      fg="#61afef",
      activebackground="#4d6488",
      font=("Consolas", 9, "bold"),
      padx=10,
      pady=4,
      command=lambda: trigger_pulse("combo_vol", 5),
  ).pack(side=tk.LEFT, padx=6)

  tk.Checkbutton(
      ctrl_frame,
      text="Chave Sustenido (#) [W]",
      variable=sustenido_var,
      bg="#21252b",
      fg="#e5c07b",
      selectcolor="#181a1f",
      activebackground="#21252b",
      font=("Consolas", 9, "bold"),
  ).pack(side=tk.LEFT, padx=8)

  tk.Checkbutton(
      ctrl_frame,
      text="Travar Teclas (Acorde)",
      variable=latch_mode_var,
      bg="#21252b",
      fg="#98c379",
      selectcolor="#181a1f",
      activebackground="#21252b",
      font=("Consolas", 9, "bold"),
  ).pack(side=tk.LEFT, padx=8)

  tk.Button(
      ctrl_frame,
      text="Reset [R]",
      bg="#5c2b29",
      fg="#ff7b72",
      font=("Consolas", 9, "bold"),
      padx=8,
      pady=4,
      command=lambda: trigger_pulse("reset", 2),
  ).pack(side=tk.RIGHT, padx=4)

  # ==========================================================================
  # 3. Teclado do Piano (7 Teclas Do..Si + 7 LEDs Vermelhos PWM da Partitura)
  # ==========================================================================
  piano_frame = tk.Frame(root, bg="#181a1f", padx=12, pady=6)
  piano_frame.pack(fill=tk.X)

  key_defs = [
      (0, "DO (C)", "A"),
      (1, "RE (D)", "S"),
      (2, "MI (E)", "D"),
      (3, "FA (F)", "F"),
      (4, "SOL (G)", "G"),
      (5, "LA (A)", "H"),
      (6, "SI (B)", "J"),
  ]

  led_canvases = []
  led_ovals = []
  key_buttons = []

  for idx, note_title, shortcut in key_defs:
    col = tk.Frame(piano_frame, bg="#181a1f", padx=6)
    col.pack(side=tk.LEFT, expand=True)

    # LED vermelho da tecla (LEDR0..LEDR6 com brilho PWM da FPGA)
    tk.Label(
        col,
        text=f"LEDR{idx}",
        fg="#abb2bf",
        bg="#181a1f",
        font=("Consolas", 8),
    ).pack()
    lcv = tk.Canvas(
        col, width=28, height=28, bg="#181a1f", highlightthickness=0
    )
    lcv.pack(pady=(2, 6))
    loval = lcv.create_oval(3, 3, 25, 25, fill="#331111", outline="#5c2222", width=2)
    led_canvases.append(lcv)
    led_ovals.append(loval)

    # Botao da tecla do piano
    btn = tk.Canvas(
        col,
        width=92,
        height=155,
        bg="#f0f2f5",
        highlightthickness=2,
        highlightbackground="#3e4451",
        cursor="hand2",
    )
    btn.pack()
    btn.create_text(
        46, 35, text=note_title, fill="#181a1f", font=("Consolas", 12, "bold")
    )
    btn.create_text(
        46, 125, text=f"[{shortcut}]", fill="#5c6370", font=("Consolas", 11, "bold")
    )

    def on_press( _ev, k=idx):
      if latch_mode_var.get():
        latch_keys[k] = not latch_keys[k]
      else:
        held_keys_mouse[k] = True

    def on_release(_ev, k=idx):
      held_keys_mouse[k] = False

    def on_right_click(_ev, k=idx):
      latch_keys[k] = not latch_keys[k]

    btn.bind("<ButtonPress-1>", on_press)
    btn.bind("<ButtonRelease-1>", on_release)
    btn.bind("<ButtonPress-3>", on_right_click)
    key_buttons.append(btn)

  # ==========================================================================
  # 4. Monitor em Tempo Real do ESP32-S3 (TinySoundFont + UART MIDI + VU Meter)
  # ==========================================================================
  esp_frame = tk.Frame(root, bg="#21252b", bd=2, relief=tk.RIDGE, padx=12, pady=8)
  esp_frame.pack(fill=tk.X, padx=12, pady=(6, 12))

  esp_top = tk.Frame(esp_frame, bg="#21252b")
  esp_top.pack(fill=tk.X)

  tk.Label(
      esp_top,
      text="MONITOR ESP32-S3 (UART1 115200 8N1 -> TinySoundFont -> I2S 44.1 kHz)",
      fg="#c678dd",
      bg="#21252b",
      font=("Consolas", 10, "bold"),
  ).pack(side=tk.LEFT)

  audio_status_txt = (
      "Audio Tempo Real: ATIVO (WinMM 44.1 kHz)"
      if audio.available
      else "Audio Tempo Real: INDISPONIVEL"
  )
  tk.Label(
      esp_top,
      text=audio_status_txt,
      fg="#98c379" if audio.available else "#e06c75",
      bg="#21252b",
      font=("Consolas", 9, "bold"),
  ).pack(side=tk.RIGHT)

  stuck_alert_var = tk.StringVar(value="STATUS VOZES: OK (0 Presas)")
  stuck_alert_lbl = tk.Label(
      esp_top,
      textvariable=stuck_alert_var,
      fg="#98c379",
      bg="#1e222a",
      font=("Consolas", 9, "bold"),
      padx=8,
      pady=1,
  )
  stuck_alert_lbl.pack(side=tk.RIGHT, padx=10)

  esp_info_var = tk.StringVar(
      value="Vozes TSF: 0/12 (Sustentadas: 0) | Ultimo MIDI: --- | UART Bytes: 0"
  )
  tk.Label(
      esp_frame,
      textvariable=esp_info_var,
      fg="#dcdfe4",
      bg="#21252b",
      font=("Consolas", 10),
      anchor="w",
  ).pack(fill=tk.X, pady=4)

  vu_frame = tk.Frame(esp_frame, bg="#21252b")
  vu_frame.pack(fill=tk.X)
  tk.Label(
      vu_frame, text="Nivel PCM L/R:", fg="#abb2bf", bg="#21252b", font=("Consolas", 9)
  ).pack(side=tk.LEFT)
  vu_canvas = tk.Canvas(
      vu_frame, width=520, height=18, bg="#111317", highlightthickness=1, highlightbackground="#3e4451"
  )
  vu_canvas.pack(side=tk.LEFT, padx=8)
  vu_bar_l = vu_canvas.create_rectangle(2, 2, 2, 8, fill="#98c379", outline="")
  vu_bar_r = vu_canvas.create_rectangle(2, 10, 2, 16, fill="#61afef", outline="")

  # Bindings de teclado do PC (com filtro anti-autorepeat do SO)
  kb_map = {"a": 0, "s": 1, "d": 2, "f": 3, "g": 4, "h": 5, "j": 6}
  pressed_kb_raw = set()

  def on_key_down(event):
    ch = event.keysym.lower()
    if ch in pressed_kb_raw:
      return
    pressed_kb_raw.add(ch)
    if ch in kb_map:
      held_keys_kb[kb_map[ch]] = True
    elif ch == "w":
      sustenido_var.set(not sustenido_var.get())
    elif ch == "m":
      trigger_pulse("modo", 2)
    elif ch == "n":
      trigger_pulse("musica", 2)
    elif ch == "q":
      trigger_pulse("oit_down", 2)
    elif ch == "e":
      trigger_pulse("oit_up", 2)
    elif ch == "i":
      trigger_pulse("intensidade", 2)
    elif ch == "v":
      trigger_pulse("combo_vol", 5)
    elif ch == "r":
      trigger_pulse("reset", 2)

  def on_key_up(event):
    ch = event.keysym.lower()
    pressed_kb_raw.discard(ch)
    if ch in kb_map:
      held_keys_kb[kb_map[ch]] = False

  root.bind("<KeyPress>", on_key_down)
  root.bind("<KeyRelease>", on_key_up)

  # Buffers de simulacao (ate 8 blocos de 256 frames por tick para ajuste dinamico de tempo real)
  max_blocks_per_tick = 8
  pcm_buf = (ctypes.c_int16 * (256 * 2 * max_blocks_per_tick))()
  bench_status = CoSimBenchStatus()
  last_tick_time = [time.perf_counter()]
  frac_blocks_accum = [0.0]

  # Pre-carrega 2 buffers iniciais no WinMM para evitar underrun no primeiro frame
  if audio.available:
    dll.cosim_set_inputs(0, 0, 1, 1, 1, 1, 1, 1)
    for _ in range(2):
      dll.cosim_step_audio_blocks(3, pcm_buf, ctypes.byref(bench_status))
      audio.write_pcm(pcm_buf, 3 * 256 * 4)

  def update_hex_canvas(idx: int, mask7: int):
    items = hex_seg_items[idx]
    for bit in range(7):
      # Displays da DE0-CV sao ativos em nivel baixo (0 = aceso, 1 = apagado)
      on = ((mask7 >> bit) & 1) == 0
      hex_canvases[idx].itemconfig(
          items[bit], fill="#ff3b30" if on else "#23272e"
      )

  def simulation_tick():
    now = time.perf_counter()
    dt = max(0.005, min(0.045, now - last_tick_time[0]))
    last_tick_time[0] = now

    # Calcula quantos blocos de 256 frames (5.805 ms) sintetizar para acompanhar 1:1 o relogio real
    exact_blocks = (dt * 44100.0 / 256.0) + frac_blocks_accum[0]
    blocks_to_run = int(exact_blocks)
    frac_blocks_accum[0] = exact_blocks - blocks_to_run

    # Mantem cushion estavel de 3..5 buffers no driver WinMM sem underrun nem acumulo de latencia
    if audio.available:
      inflight = audio.in_flight_buffers()
      if inflight < 2:
        blocks_to_run = max(blocks_to_run, 4)
      elif inflight > 6:
        blocks_to_run = min(blocks_to_run, 2)

    blocks_to_run = max(2, min(max_blocks_per_tick, blocks_to_run))

    # Monta mascara das 7 teclas
    keys_mask = 0
    for i in range(7):
      active = held_keys_mouse[i] or held_keys_kb[i] or latch_keys[i]
      if active:
        keys_mask |= 1 << i
      key_buttons[i].configure(bg="#61afef" if active else "#f0f2f5")

    # Processa botoes de controle e combo de volume
    modo_n = 1
    mus_n = 1
    int_n = 1
    up_n = 1
    dn_n = 1
    rst_n = 1

    if pulse_counters["combo_vol"] > 0:
      c = pulse_counters["combo_vol"]
      # Passos 5..2: segura modo; passos 4..3: pulsa intensidade; passo 1: solta modo
      if c >= 2:
        modo_n = 0
      if c in (4, 3):
        int_n = 0
      pulse_counters["combo_vol"] -= 1
    else:
      if pulse_counters["modo"] > 0:
        modo_n = 0
        pulse_counters["modo"] -= 1
      if pulse_counters["musica"] > 0:
        mus_n = 0
        pulse_counters["musica"] -= 1
      if pulse_counters["intensidade"] > 0:
        int_n = 0
        pulse_counters["intensidade"] -= 1
      if pulse_counters["oit_up"] > 0:
        up_n = 0
        pulse_counters["oit_up"] -= 1
      if pulse_counters["oit_down"] > 0:
        dn_n = 0
        pulse_counters["oit_down"] -= 1
      if pulse_counters["reset"] > 0:
        rst_n = 0
        pulse_counters["reset"] -= 1

    dll.cosim_set_inputs(
        keys_mask,
        1 if sustenido_var.get() else 0,
        modo_n,
        mus_n,
        int_n,
        up_n,
        dn_n,
        rst_n,
    )

    dll.cosim_step_audio_blocks(
        blocks_to_run, pcm_buf, ctypes.byref(bench_status)
    )
    audio.write_pcm(pcm_buf, blocks_to_run * 256 * 4)

    # Atualiza os 6 displays de 7 segmentos
    update_hex_canvas(0, bench_status.hex5_modo)
    update_hex_canvas(1, bench_status.hex4_oitava)
    update_hex_canvas(2, bench_status.hex3_musica_dezena)
    update_hex_canvas(3, bench_status.hex2_musica_unidade)
    update_hex_canvas(4, bench_status.hex1_nota)
    update_hex_canvas(5, bench_status.hex0_sustenido)

    # Atualiza os 7 LEDs vermelhos com brilho proporcional ao PWM real da FPGA
    for i in range(7):
      pwm_val = int(bench_status.led_vermelho_pwm[i])
      r_channel = max(0x33, min(255, pwm_val))
      g_channel = 0x11 if pwm_val < 32 else int(pwm_val * 0.15)
      color = f"#{r_channel:02x}{g_channel:02x}11"
      led_canvases[i].itemconfig(led_ovals[i], fill=color)

    # Atualiza LEDs auxiliares
    cv_led_sust.itemconfig(
        oval_led_sust, fill="#e5c07b" if bench_status.led_sustenido else "#2c313a"
    )
    cv_led_down.itemconfig(
        oval_led_down, fill="#e06c75" if bench_status.led_oitava_down else "#2c313a"
    )
    cv_led_up.itemconfig(
        oval_led_up, fill="#e06c75" if bench_status.led_oitava_up else "#2c313a"
    )
    cv_servo.itemconfig(
        oval_servo, fill="#61afef" if bench_status.servo_controle else "#2c313a"
    )

    # Atualiza alerta visual de nota presa
    if bench_status.stuck_note_alert or bench_status.overlap_violations > 0:
      stuck_alert_var.set(
          f"ALERTA: NOTA PRESA / OVERLAP ({bench_status.overlap_violations})!"
      )
      stuck_alert_lbl.configure(fg="#ffffff", bg="#e06c75")
    else:
      stuck_alert_var.set("STATUS VOZES: OK (0 Presas)")
      stuck_alert_lbl.configure(fg="#98c379", bg="#1e222a")

    # Atualiza textos informativos
    m_idx = int(bench_status.modo_ativo)
    s_idx = int(bench_status.sel_musica)
    vol_map = {0: "100%", 1: "75%", 2: "50%"}
    led_br_map = {0: "100%", 1: "80%", 2: "53%", 3: "27%", 4: "0%"}
    mode_info_var.set(MODE_NAMES.get(m_idx, f"Modo {m_idx}"))
    song_info_var.set(
        SONG_NAMES[s_idx] if 0 <= s_idx < len(SONG_NAMES) else f"Musica {s_idx}"
    )
    detail_info_var.set(
        f"Oitava: {bench_status.oitava_atual} | "
        f"Sust: {'ON' if bench_status.sustenido_atual else 'OFF'} | "
        f"Vol: {vol_map.get(int(bench_status.volume_state), '100%')} | "
        f"LED: {led_br_map.get(int(bench_status.led_brightness_state), '100%')} | "
        f"End: {bench_status.endereco_partitura}"
    )

    st_byte = int(bench_status.last_midi_status)
    d1 = int(bench_status.last_midi_data1)
    d2 = int(bench_status.last_midi_data2)
    midi_cmd_str = "NoteOn" if (st_byte & 0xF0) == 0x90 and d2 > 0 else "NoteOff"
    esp_info_var.set(
        f"Vozes TSF: {bench_status.tsf_active_voices}/12 "
        f"(Sustentadas: {bench_status.tsf_sustained_voices}) | "
        f"Ultimo MIDI: {midi_cmd_str} {midi_note_label(d1)} vel={d2} "
        f"[{st_byte:02X} {d1:02X} {d2:02X}] | "
        f"On/Off: {bench_status.midi_note_on_count}/{bench_status.midi_note_off_count}"
    )

    width_l = min(516, int((bench_status.peak_l / 32768.0) * 516))
    width_r = min(516, int((bench_status.peak_r / 32768.0) * 516))
    vu_canvas.coords(vu_bar_l, 2, 2, 2 + width_l, 8)
    vu_canvas.coords(vu_bar_r, 2, 10, 2 + width_r, 16)

    root.after(12, simulation_tick)

  def on_close():
    audio.close()
    root.destroy()

  if auto_test_gui:
    def finish_auto_test():
      assert bench_status.midi_note_on_count >= 1, "GUI nao disparou Note On!"
      assert bench_status.midi_note_off_count >= 1, "GUI nao disparou Note Off!"
      assert bench_status.oitava_atual == 5, f"Oitava esperada 5, obtida {bench_status.oitava_atual}!"
      assert bench_status.stuck_note_alert == 0, "Alerta de nota presa no GUI!"
      assert bench_status.overlap_violations == 0, "Overlap MIDI no GUI!"
      assert "OK (0 Presas)" in stuck_alert_var.get(), "Widget de alerta invalido!"
      on_close()

    root.after(60, lambda: on_press(None, 0))
    root.after(220, lambda: on_release(None, 0))
    root.after(300, lambda: trigger_pulse("oit_up", 2))
    root.after(480, finish_auto_test)

  root.protocol("WM_DELETE_WINDOW", on_close)
  root.after(15, simulation_tick)
  root.mainloop()
  return 0


def main() -> int:
  parser = argparse.ArgumentParser(
      description="Bancada Virtual Interativa FPGA DE0-CV + ESP32-S3 MIDI Synth."
  )
  parser.add_argument(
      "--self-test",
      action="store_true",
      help="Executa autoteste headless da DLL, audio e displays sem abrir janela.",
  )
  parser.add_argument(
      "--full-50mhz",
      action="store_true",
      help="Executa na escala 1:1 de 50 MHz.",
  )
  args = parser.parse_args()
  repo_root = Path(__file__).resolve().parent.parent

  if args.self_test:
    return run_self_test(repo_root)
  return launch_gui(repo_root, full_50mhz=args.full_50mhz)


if __name__ == "__main__":
  sys.exit(main())
