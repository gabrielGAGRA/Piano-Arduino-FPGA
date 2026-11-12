#!/usr/bin/env python3
"""
Orquestrador Completo da Suite de Co-Simulacao FPGA Cyclone V + ESP32-S3.

Executa em sequencia:
  1. Auditoria de FPU Single-Precision no compilador real Xtensa ESP32-S3
     (sim/check_esp32_fpu.py).
  2. Compilacao nativa C++17 do motor unificado (sim/cosim_engine.exe e
     sim/cosim_engine.dll).
  3. Verificacao Lockstep Ciclo-a-Ciclo (5.000 ciclos) entre Vpiano_top (C++) e
     os 28 arquivos Verilog (.v) reais simulados no ModelSim (vlog/vsim).
  4. Suite de 9 Cenarios de Estresse e Invariantes Ponta-a-Ponta
     (FPGA -> UART 8N1 -> ESP32 -> TinySoundFont -> PCM .wav).
  5. Testbench Verilog de integracao (piano_top_tb.v) no ModelSim.
  6. Quality Gate de Linting RTL (scripts/lint_verilog.py).
"""

import argparse
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
from typing import List, Optional


RTL_SOURCES = [
    "piano_top.v",
    "fluxo_dados.v",
    "unidade_controle.v",
    "painel_display_leds.v",
    "metronomo.v",
    "metronomo_fd.v",
    "metronomo_uc.v",
    "controle_servo_8.v",
    "gerenciador_midi_tx.v",
    "tx_serial_8N1.v",
    "tx_serial_8N1_fd.v",
    "tx_serial_8N1_uc.v",
    "codificador_midi.v",
    "decodificador_midi.v",
    "decodificador_cifra.v",
    "display_sustenido.v",
    "hexa7seg.v",
    "led_oitava.v",
    "guarda_oitava.v",
    "logica_notas_prioridade.v",
    "gerador_pwm.v",
    "debounce.v",
    "edge_detector.v",
    "contador_m.v",
    "deslocador_n.v",
    "sincronizador.v",
    "sync_ram.v",
    "sync_rom.v",
    "tabela_offsets_partituras.v",
]


def find_vcvars64() -> Optional[Path]:
  candidates = [
      Path(
          r"C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat"
      ),
      Path(
          r"C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars64.bat"
      ),
      Path(
          r"C:\Program Files (x86)\Microsoft Visual Studio\2019\BuildTools\VC\Auxiliary\Build\vcvars64.bat"
      ),
  ]
  for c in candidates:
    if c.exists():
      return c
  return None


def build_cosim_binaries(repo_root: Path, force_rebuild: bool = False) -> bool:
  sim_dir = repo_root / "sim"
  exe_path = sim_dir / "cosim_engine.exe"
  dll_path = sim_dir / "cosim_engine.dll"
  cpp_path = sim_dir / "cosim_main.cpp"
  hal_path = sim_dir / "esp32_sim_hal.h"
  vtop_path = sim_dir / "Vpiano_top.h"
  ino_path = repo_root / "esp32_midi_synth" / "esp32_midi_synth.ino"
  tsf_path = repo_root / "esp32_midi_synth" / "tsf.h"

  if not force_rebuild and exe_path.exists() and dll_path.exists():
    bin_mtime = min(exe_path.stat().st_mtime, dll_path.stat().st_mtime)
    src_mtime = max(
        p.stat().st_mtime
        for p in [cpp_path, hal_path, vtop_path, ino_path, tsf_path]
    )
    if bin_mtime >= src_mtime:
      return True

  vcvars = find_vcvars64()
  if vcvars is not None:
    print(f"[BUILD] Compilando motor C++ com MSVC ({vcvars.parent.parent.parent.parent.name})...")
    mock_inc = sim_dir / "arduino_mock"
    synth_inc = repo_root / "esp32_midi_synth"

    with tempfile.TemporaryDirectory(prefix="cosim_build_") as tmp_dir:
      bat_file = Path(tmp_dir) / "build_cosim.bat"
      obj_exe = Path(tmp_dir) / "cosim_exe.obj"
      obj_dll = Path(tmp_dir) / "cosim_dll.obj"
      bat_content = (
          f'@echo off\r\n'
          f'call "{vcvars}" >nul\r\n'
          f'if errorlevel 1 exit /b 1\r\n'
          f'cl /nologo /O2 /EHsc /std:c++17 /W3 /wd4996 /wd4244 '
          f'/I"{mock_inc}" /I"{synth_inc}" /I"{sim_dir}" '
          f'"{cpp_path}" /Fe:"{exe_path}" /Fo:"{obj_exe}"\r\n'
          f'if errorlevel 1 exit /b 1\r\n'
          f'cl /nologo /O2 /LD /EHsc /std:c++17 /W3 /wd4996 /wd4244 '
          f'/I"{mock_inc}" /I"{synth_inc}" /I"{sim_dir}" '
          f'"{cpp_path}" /Fe:"{dll_path}" /Fo:"{obj_dll}"\r\n'
          f'if errorlevel 1 exit /b 1\r\n'
      )
      bat_file.write_text(bat_content, encoding="utf-8")
      res = subprocess.run(
          ["cmd.exe", "/c", str(bat_file)],
          cwd=str(repo_root),
          capture_output=True,
          text=True,
      )
      if res.returncode != 0:
        print("[ERRO] Falha na compilacao MSVC:", file=sys.stderr)
        print(res.stdout, file=sys.stderr)
        print(res.stderr, file=sys.stderr)
        return False
      print(f"        OK: {exe_path.name} e {dll_path.name} gerados.")
      return True

  gpp = shutil.which("g++")
  if gpp:
    print(f"[BUILD] Compilando motor C++ com g++ ({gpp})...")
    mock_inc = sim_dir / "arduino_mock"
    synth_inc = repo_root / "esp32_midi_synth"
    cmd_exe = [
        gpp,
        "-O2",
        "-std=c++17",
        f"-I{mock_inc}",
        f"-I{synth_inc}",
        f"-I{sim_dir}",
        str(cpp_path),
        "-o",
        str(exe_path),
    ]
    res = subprocess.run(cmd_exe, cwd=str(repo_root), capture_output=True, text=True)
    if res.returncode != 0:
      print(res.stderr, file=sys.stderr)
      return False
    cmd_dll = [
        gpp,
        "-O2",
        "-shared",
        "-std=c++17",
        f"-I{mock_inc}",
        f"-I{synth_inc}",
        f"-I{sim_dir}",
        str(cpp_path),
        "-o",
        str(dll_path),
    ]
    res_dll = subprocess.run(cmd_dll, cwd=str(repo_root), capture_output=True, text=True)
    return res_dll.returncode == 0

  print("[ERRO] Nenhum compilador C++ host (MSVC ou g++) encontrado.", file=sys.stderr)
  return False


def run_modelsim_lockstep_verification(repo_root: Path, exe_path: Path) -> bool:
  vlib = shutil.which("vlib")
  vlog = shutil.which("vlog")
  vsim = shutil.which("vsim")
  if not (vlib and vlog and vsim):
    print("[AVISO] ModelSim nao encontrado no PATH; pulando lockstep RTL.")
    return True

  print("[LOCKSTEP] Verificando equivalencia ciclo-a-ciclo: Vpiano_top (C++) vs ModelSim (.v)...")
  with tempfile.TemporaryDirectory(prefix="cosim_lockstep_") as tmp_dir:
    tmp_path = Path(tmp_dir)
    cpp_trace = tmp_path / "cpp_trace.txt"
    vsim_trace = tmp_path / "vsim_trace.txt"
    tb_lockstep = tmp_path / "lockstep_tb.v"
    work_dir = tmp_path / "work"

    # 1. Gera trace de 5.000 ciclos pelo Vpiano_top C++
    res_cpp = subprocess.run(
        [
            str(exe_path),
            "--lockstep-dump",
            str(cpp_trace),
            "--rom",
            str(repo_root / "music" / "partituras.hex"),
        ],
        cwd=str(repo_root),
        capture_output=True,
        text=True,
    )
    if res_cpp.returncode != 0 or not cpp_trace.exists():
      print("[ERRO] Falha ao gerar trace C++ de lockstep:", file=sys.stderr)
      print(res_cpp.stderr, file=sys.stderr)
      return False

    vsim_trace_posix = str(vsim_trace).replace("\\", "/")

    # 2. Gera testbench Verilog com a mesma sequencia exata de estimulos por ciclo
    tb_code = f"""`timescale 1ns / 1ps
module lockstep_tb;
  reg        clk;
  reg        reset_n;
  reg  [6:0] gpio_keys;
  reg        btn_modo_n;
  reg        btn_musica_n;
  reg        btn_intensidade_n;
  reg        btn_oitava_up_n;
  reg        btn_oitava_down_n;
  reg        btn_sustenido;

  wire       saida_serial;
  wire       servo_controle;
  wire [6:0] led_vermelho;
  wire       led_sustenido;
  wire       led_oitava_up;
  wire       led_oitava_down;
  wire [6:0] hex5_modo;
  wire [6:0] hex4_oitava;
  wire [6:0] hex3_musica_dezena;
  wire [6:0] hex2_musica_unidade;
  wire [6:0] hex1_nota;
  wire [6:0] hex0_sustenido;

  piano_top #(
    .DebounceTecla   (4),
    .DebounceControle(4),
    .ClockDivUart    (2),
    .CiclosTick8ms   (60)
  ) dut (
    .clk                (clk),
    .reset_n            (reset_n),
    .gpio_keys          (gpio_keys),
    .btn_modo_n         (btn_modo_n),
    .btn_musica_n       (btn_musica_n),
    .btn_intensidade_n  (btn_intensidade_n),
    .btn_oitava_up_n    (btn_oitava_up_n),
    .btn_oitava_down_n  (btn_oitava_down_n),
    .btn_sustenido      (btn_sustenido),
    .saida_serial       (saida_serial),
    .servo_controle     (servo_controle),
    .led_vermelho       (led_vermelho),
    .led_sustenido      (led_sustenido),
    .led_oitava_up      (led_oitava_up),
    .led_oitava_down    (led_oitava_down),
    .hex5_modo          (hex5_modo),
    .hex4_oitava        (hex4_oitava),
    .hex3_musica_dezena (hex3_musica_dezena),
    .hex2_musica_unidade(hex2_musica_unidade),
    .hex1_nota          (hex1_nota),
    .hex0_sustenido     (hex0_sustenido)
  );

  integer fd;
  integer cyc;

  initial begin
    fd = $fopen("{vsim_trace_posix}", "w");
    clk = 1'b0;
    reset_n = 1'b0;
    gpio_keys = 7'd0;
    btn_modo_n = 1'b1;
    btn_musica_n = 1'b1;
    btn_intensidade_n = 1'b1;
    btn_oitava_up_n = 1'b1;
    btn_oitava_down_n = 1'b1;
    btn_sustenido = 1'b0;
    #1;

    for (cyc = 0; cyc < 5000; cyc = cyc + 1) begin
      clk = 1'b0;
      if (cyc == 4) reset_n = 1'b1;
      if (cyc == 20) gpio_keys = 7'h01;
      if (cyc == 150) gpio_keys = 7'h05;
      if (cyc == 240) gpio_keys = 7'h01;
      if (cyc == 300) btn_sustenido = 1'b1;
      if (cyc == 420) btn_oitava_up_n = 1'b0;
      if (cyc == 432) btn_oitava_up_n = 1'b1;
      if (cyc == 540) btn_oitava_down_n = 1'b0;
      if (cyc == 552) btn_oitava_down_n = 1'b1;
      if (cyc == 600) gpio_keys = 7'h00;
      if (cyc == 750) btn_intensidade_n = 1'b0;
      if (cyc == 762) btn_intensidade_n = 1'b1;
      if (cyc == 900) btn_sustenido = 1'b0;
      if (cyc == 950) btn_modo_n = 1'b0;
      if (cyc == 970) btn_intensidade_n = 1'b0;
      if (cyc == 985) btn_intensidade_n = 1'b1;
      if (cyc == 1000) btn_modo_n = 1'b1;
      if (cyc >= 1050 && cyc < 1130) btn_musica_n = ((cyc % 20) < 10) ? 1'b0 : 1'b1;
      if (cyc == 1130) btn_musica_n = 1'b1;
      if (cyc == 1160) btn_modo_n = 1'b0;
      if (cyc == 1170) btn_modo_n = 1'b1;
      if (cyc == 1190) gpio_keys = 7'h01;
      if (cyc == 1215) gpio_keys = 7'h00;
      if (cyc == 1235) gpio_keys = 7'h10;
      if (cyc == 1265) gpio_keys = 7'h00;
      if (cyc == 1300) btn_modo_n = 1'b0;
      if (cyc == 1310) btn_modo_n = 1'b1;
      if (cyc == 1350) gpio_keys = 7'h01;
      if (cyc == 1550) gpio_keys = 7'h00;
      if (cyc == 1900) btn_modo_n = 1'b0;
      if (cyc == 1910) btn_modo_n = 1'b1;
      if (cyc == 1950) gpio_keys = 7'h01;
      if (cyc == 1965) gpio_keys = 7'h00;
      #10;

      clk = 1'b1;
      #10;
      $fwrite(fd, "%0d %0d %02x %0d %0d %0d %0d %0d %0d | %0d %0d %02x %0d %0d %0d %02x %02x %02x %02x %02x %02x\\n",
        reset_n, gpio_keys, btn_modo_n, btn_musica_n, btn_intensidade_n,
        btn_oitava_up_n, btn_oitava_down_n, btn_sustenido, cyc,
        saida_serial, servo_controle, led_vermelho, led_sustenido,
        led_oitava_up, led_oitava_down, hex5_modo, hex4_oitava,
        hex3_musica_dezena, hex2_musica_unidade, hex1_nota, hex0_sustenido);
    end

    $fclose(fd);
    $finish;
  end
endmodule
"""
    tb_lockstep.write_text(tb_code, encoding="utf-8")

    subprocess.run([vlib, str(work_dir)], cwd=str(repo_root), capture_output=True, check=True)
    vlog_cmd = [vlog, "-work", str(work_dir), str(tb_lockstep)] + RTL_SOURCES
    res_vlog = subprocess.run(vlog_cmd, cwd=str(repo_root), capture_output=True, text=True)
    if res_vlog.returncode != 0:
      print("[ERRO] Falha ao compilar RTL no ModelSim:", file=sys.stderr)
      print(res_vlog.stdout, file=sys.stderr)
      return False

    res_vsim = subprocess.run(
        [
            vsim,
            "-c",
            "-logfile",
            "nul",
            "-work",
            str(work_dir),
            "lockstep_tb",
            "-do",
            "run -all; quit -f",
        ],
        cwd=str(repo_root),
        capture_output=True,
        text=True,
    )
    if res_vsim.returncode != 0 or not vsim_trace.exists():
      print("[ERRO] Falha ao executar lockstep_tb no ModelSim:", file=sys.stderr)
      print(res_vsim.stdout, file=sys.stderr)
      return False

    cpp_lines = cpp_trace.read_text(encoding="utf-8").splitlines()
    vsim_lines = vsim_trace.read_text(encoding="utf-8").splitlines()

    if len(cpp_lines) != len(vsim_lines):
      print(
          f"[FALHA] Contagem de linhas divergente: C++={len(cpp_lines)} vs ModelSim={len(vsim_lines)}",
          file=sys.stderr,
      )
      return False

    mismatches = 0
    for idx, (c_line, v_line) in enumerate(zip(cpp_lines, vsim_lines)):
      if c_line.strip() != v_line.strip():
        if mismatches < 5:
          print(f"  [DIVERGENCIA no ciclo {idx}]:")
          print(f"    C++     : {c_line}")
          print(f"    ModelSim: {v_line}")
        mismatches += 1

    if mismatches > 0:
      print(f"[FALHA] {mismatches} ciclo(s) divergiram entre Vpiano_top e ModelSim!", file=sys.stderr)
      return False

    print(f"           OK: {len(cpp_lines)} ciclos comparados com 0 divergencias bit-a-bit!")
    return True


def run_modelsim_piano_top_tb(repo_root: Path) -> bool:
  vlib = shutil.which("vlib")
  vlog = shutil.which("vlog")
  vsim = shutil.which("vsim")
  if not (vlib and vlog and vsim):
    print("[AVISO] ModelSim nao encontrado no PATH; pulando piano_top_tb.v.")
    return True

  print("[MODELSIM] Executando testbench Verilog piano_top_tb.v...")
  with tempfile.TemporaryDirectory(prefix="msim_piano_tb_") as tmp_dir:
    work_dir = Path(tmp_dir) / "work"
    subprocess.run([vlib, str(work_dir)], cwd=str(repo_root), capture_output=True, check=True)
    vlog_cmd = [vlog, "-work", str(work_dir), "piano_top_tb.v"] + RTL_SOURCES
    res_vlog = subprocess.run(vlog_cmd, cwd=str(repo_root), capture_output=True, text=True)
    if res_vlog.returncode != 0:
      print(res_vlog.stdout, file=sys.stderr)
      return False

    res_vsim = subprocess.run(
        [
            vsim,
            "-c",
            "-logfile",
            "nul",
            "-work",
            str(work_dir),
            "piano_top_tb",
            "-do",
            "run -all; quit -f",
        ],
        cwd=str(repo_root),
        capture_output=True,
        text=True,
    )
    if "TODOS OS TESTES PASSARAM!" not in res_vsim.stdout:
      print("[FALHA] piano_top_tb.v falhou no ModelSim:", file=sys.stderr)
      print(res_vsim.stdout, file=sys.stderr)
      return False

    print("           OK: piano_top_tb.v passou com 0 erros no ModelSim.")
    return True


def main() -> int:
  parser = argparse.ArgumentParser(
      description="Executa toda a suite de co-simulacao FPGA + ESP32-S3."
  )
  parser.add_argument(
      "--full-50mhz",
      action="store_true",
      help="Executa tambem na escala 1:1 de 50 MHz (ClockDivUart=434, CiclosTick8ms=400000).",
  )
  parser.add_argument(
      "--skip-fpu-audit",
      action="store_true",
      help="Pula a auditoria no compilador Xtensa ESP32-S3.",
  )
  parser.add_argument(
      "--rebuild",
      action="store_true",
      help="Forca recompilacao dos binarios C++ de co-simulacao.",
  )
  args = parser.parse_args()

  repo_root = Path(__file__).resolve().parent.parent

  # 1. Auditoria FPU Xtensa ESP32-S3
  if not args.skip_fpu_audit:
    res_fpu = subprocess.run(
        [sys.executable, str(repo_root / "sim" / "check_esp32_fpu.py")],
        cwd=str(repo_root),
    )
    if res_fpu.returncode != 0:
      return 1
    print()

  # 2. Compila motor C++ (cosim_engine.exe + cosim_engine.dll)
  if not build_cosim_binaries(repo_root, force_rebuild=args.rebuild):
    return 1
  print()

  exe_path = repo_root / "sim" / "cosim_engine.exe"

  # 3. Verificacao Lockstep Ciclo-a-Ciclo (C++ Vpiano_top vs ModelSim RTL)
  if not run_modelsim_lockstep_verification(repo_root, exe_path):
    return 1
  print()

  # 4. Suite Automatizada de Co-Simulacao (FPGA -> UART -> ESP32 -> Audio PCM)
  wav_out = repo_root / "sim" / "cosim_output.wav"
  suite_cmd = [
      str(exe_path),
      "--suite",
      "--wav",
      str(wav_out),
      "--rom",
      str(repo_root / "music" / "partituras.hex"),
  ]
  if args.full_50mhz:
    suite_cmd.append("--full-50mhz")

  res_suite = subprocess.run(suite_cmd, cwd=str(repo_root))
  if res_suite.returncode != 0:
    return 1
  print()

  # 5. Testbench Verilog piano_top_tb.v no ModelSim
  if not run_modelsim_piano_top_tb(repo_root):
    return 1
  print()

  # 6. Linter Verilog-2001
  print("[LINT] Executando scripts/lint_verilog.py...")
  res_lint = subprocess.run(
      [sys.executable, str(repo_root / "scripts" / "lint_verilog.py")],
      cwd=str(repo_root),
  )
  if res_lint.returncode != 0:
    return 1

  print("\n[SUCESSO TOTAL] Todas as verificacoes de hardware, firmware e audio passaram!")
  return 0


if __name__ == "__main__":
  sys.exit(main())
