#!/usr/bin/env python3
"""
Co-simulador de Audio do Piano FPGA para o Alto-Falante do Notebook.

Executa a simulacao Verilog do `piano_top.v` via Icarus Verilog no WSL,
captura a saida serial UART 8N1 emitida pela FPGA simulada,
decodifica os pacotes MIDI 1.0 (24 bits) gerados pelo hardware,
sintetiza o audio real de piano em 44.1 kHz (WAV de 16 bits)
e reproduz imediatamente no alto-falante principal do Windows (WASAPI / winsound).
"""

import argparse
import math
import os
import re
import struct
import subprocess
import sys
import wave
import winsound

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

NOTE_NAMES = ["Do", "Do#", "Re", "Re#", "Mi", "Fa", "Fa#", "Sol", "Sol#", "La", "La#", "Si"]


def midi_to_str(note_num: int) -> str:
    if note_num < 0 or note_num > 127:
        return f"Note {note_num}"
    octave = (note_num // 12) - 1
    name = NOTE_NAMES[note_num % 12]
    return f"{name}{octave} (MIDI {note_num})"


def compile_verilog_if_needed(project_dir: str):
    vvp_path = os.path.join(project_dir, "sim_audio.vvp")
    wsl_dir = project_dir.replace("\\", "/").replace("C:", "/mnt/c")

    if not os.path.exists(vvp_path):
        print("[*] Compilando circuitos Verilog no Icarus Verilog...", flush=True)
        compile_cmd = (
            f"cd '{wsl_dir}' && "
            "iverilog -o sim_audio.vvp -g2001 sim_audio_player_tb.v piano_top.v fluxo_dados.v "
            "unidade_controle.v mux_musicas.v sync_rom.v sync_ram.v decodificador_cifra.v "
            "display_sustenido.v led_oitava.v guarda_oitava.v codificador_midi.v decodificador_midi.v "
            "gerenciador_midi_tx.v tx_serial_8N1.v tx_serial_8N1_fd.v tx_serial_8N1_uc.v "
            "deslocador_n.v contador_m.v debounce.v edge_detector.v gerador_pwm.v hexa7seg.v "
            "metronomo.v metronomo_fd.v metronomo_uc.v controle_servo_8.v sincronizador.v "
            "logica_notas_prioridade.v"
        )
        res = subprocess.run(["wsl", "bash", "-c", compile_cmd], capture_output=True, text=True)
        if res.returncode != 0:
            print(f"[ERRO] Falha na compilacao Icarus Verilog:\n{res.stderr}", flush=True)
            sys.exit(1)
        print("[OK] Compilacao concluida.", flush=True)


def synthesize_piano_wave(events, output_wav="saida_fpga_clair_de_lune.wav", sample_rate=44100):
    """
    Sintetiza as notas MIDI emitidas pela FPGA em um arquivo WAV de alta fidelidade
    usando modelo de cordas com harmonicos e envelope percussivo de piano acústico.
    """
    # Pareia Note On com Note Off para obter tempo de inicio e duracao de cada nota
    active_notes = {}
    note_segments = []

    for sim_time_ms, status, note, vel in events:
        t_s = sim_time_ms / 1000.0
        if status == 0x90 and vel > 0:
            if note in active_notes:
                t_on, v_on = active_notes.pop(note)
                note_segments.append((note, v_on, t_on, max(0.1, t_s - t_on)))
            active_notes[note] = (t_s, vel)
        elif status == 0x80 or (status == 0x90 and vel == 0):
            if note in active_notes:
                t_on, v_on = active_notes.pop(note)
                note_segments.append((note, v_on, t_on, max(0.1, t_s - t_on)))

    # Fecha eventuais notas que ficaram abertas no final
    max_t = max([ms / 1000.0 for ms, _, _, _ in events] + [1.0])
    for note, (t_on, v_on) in active_notes.items():
        note_segments.append((note, v_on, t_on, max(0.5, (max_t + 1.0) - t_on)))

    if not note_segments:
        print("[!] Nenhuma nota musical encontrada para sintetizar.", flush=True)
        return False

    total_duration = max(t_on + dur for _, _, t_on, dur in note_segments) + 1.5
    total_samples = int(total_duration * sample_rate)
    buffer = [0.0] * total_samples

    print(f"[*] Sintetizando {len(note_segments)} notas da FPGA ({total_duration:.1f}s de audio)...", flush=True)

    # Sintese de piano com harmonicos e decaimento exponencial
    for note, vel, t_on, dur in note_segments:
        freq = 440.0 * (2.0 ** ((note - 69) / 12.0))
        start_idx = int(t_on * sample_rate)
        # Permite cauda natural de sustentacao (release tail) de ate 1.0s apos o note-off
        note_samples = int((dur + 0.8) * sample_rate)
        end_idx = min(total_samples, start_idx + note_samples)

        amplitude = (vel / 127.0) * 0.4
        decay_rate = 2.8 / max(0.4, dur)

        for i in range(start_idx, end_idx):
            t = (i - start_idx) / sample_rate
            # Ataque percussivo rapido (rampa de 3ms)
            attack = min(1.0, t / 0.003)
            env = attack * math.exp(-decay_rate * t)

            # Harmonicos fundamentais do piano (1x, 2x, 3x, 4x)
            sample = (
                math.sin(2 * math.pi * freq * t)
                + 0.50 * math.sin(4 * math.pi * freq * t)
                + 0.25 * math.sin(6 * math.pi * freq * t)
                + 0.12 * math.sin(8 * math.pi * freq * t)
            ) * env * amplitude

            buffer[i] += sample

    # Normalizacao para 16 bits sem clipping
    max_amp = max(max(abs(x) for x in buffer), 0.001)
    scale = 28000.0 / max_amp
    int_samples = [int(x * scale) for x in buffer]

    with wave.open(output_wav, "w") as f:
        f.setnchannels(1)  # Mono
        f.setsampwidth(2)  # 16 bits
        f.setframerate(sample_rate)
        f.writeframes(struct.pack("<" + "h" * len(int_samples), *int_samples))

    print(f"[OK] Arquivo de audio gerado com sucesso: {output_wav}", flush=True)
    return True


def main():
    parser = argparse.ArgumentParser(description="Co-simulacao do Piano FPGA no Alto-falante.")
    parser.add_argument("--limit", type=int, default=20, help="Limite de notas a reproduzir (padrao: 20)")
    args = parser.parse_args()

    project_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    compile_verilog_if_needed(project_dir)

    wsl_dir = project_dir.replace("\\", "/").replace("C:", "/mnt/c")

    print("=" * 65, flush=True)
    print("    PIANO FPGA -> ALTO-FALANTE DO NOTEBOOK (CO-SIMULACAO)    ", flush=True)
    print("=" * 65, flush=True)
    print("[*] Executando simulacao RTL da FPGA (piano_top.v) no WSL...", flush=True)

    sim_cmd = f"cd '{wsl_dir}' && vvp sim_audio.vvp"
    try:
        proc = subprocess.Popen(
            ["wsl", "bash", "-c", sim_cmd],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            bufsize=1,
        )
    except Exception as e:
        print(f"[ERRO] Falha ao executar simulacao no WSL: {e}", flush=True)
        return

    events = []
    note_on_count = 0
    re_event = re.compile(r"^MIDI_EVENT:(\d+):([0-9a-fA-F]+):(\d+):(\d+)")

    print("-" * 65, flush=True)
    print("[>] Capturando saida serial da FPGA em tempo real:", flush=True)

    for line in proc.stdout:
        line = line.strip()
        if line == "MIDI_END":
            break

        m = re_event.match(line)
        if not m:
            continue

        sim_time_ms = int(m.group(1))
        status = int(m.group(2), 16)
        note = int(m.group(3))
        vel = int(m.group(4))

        events.append((sim_time_ms, status, note, vel))

        sec = sim_time_ms // 1000
        msec = sim_time_ms % 1000
        time_str = f"{sec//60:02d}:{sec%60:02d}.{msec:03d}"
        note_str = midi_to_str(note)

        if status == 0x90 and vel > 0:
            note_on_count += 1
            bar = "#" * (vel // 8)
            print(f"[{time_str}] > Note ON  : {note_str:<18} | Vel: {vel:3d}  {bar}", flush=True)
        elif status == 0x80 or (status == 0x90 and vel == 0):
            print(f"[{time_str}] . Note OFF : {note_str}", flush=True)

        if args.limit > 0 and note_on_count >= args.limit:
            break

    proc.terminate()
    print("-" * 65, flush=True)
    print(f"[OK] Total de {note_on_count} notas capturadas da linha serial da FPGA.", flush=True)

    wav_file = os.path.join(project_dir, "saida_fpga_clair_de_lune.wav")
    if synthesize_piano_wave(events, output_wav=wav_file):
        print("\n[♫] TOCANDO AGORA NO SEU ALTO-FALANTE (Windows Master Audio)...", flush=True)
        print("    (Pressione Ctrl+C para parar)", flush=True)
        try:
            winsound.PlaySound(wav_file, winsound.SND_FILENAME)
            print("[OK] Reproducao concluida com sucesso!", flush=True)
        except Exception as e:
            print(f"[!] Erro ao tocar via winsound: {e}. Abrindo com o player padrao...", flush=True)
            os.startfile(wav_file)


if __name__ == "__main__":
    main()
