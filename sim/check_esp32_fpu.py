#!/usr/bin/env python3
"""
Auditoria de FPU Single-Precision (ESP32-S3) para esp32_midi_synth.ino e tsf.h.

Compila o firmware real com o compilador Xtensa do ESP32-S3
(xtensa-esp32s3-elf-g++) usando -Wdouble-promotion -Werror=double-promotion
e inspeciona a tabela de simbolos ELF via xtensa-esp32s3-elf-nm para garantir
ausencia total de aritmetica double em software (__adddf3, __muldf3, pow, log, etc.).
"""

import glob
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
from typing import List, Optional, Tuple


BANNED_DOUBLE_SYMBOLS = {
    "__adddf3",
    "__subdf3",
    "__muldf3",
    "__divdf3",
    "__negdf2",
    "__extendsfdf2",
    "__truncdfsf2",
    "__fixdfsi",
    "__fixunsdfsi",
    "__fixdfdi",
    "__floatsidf",
    "__floatunsidf",
    "__floatdidf",
    "__eqdf2",
    "__nedf2",
    "__gtdf2",
    "__gedf2",
    "__ltdf2",
    "__ledf2",
    "__unorddf2",
    "pow",
    "log",
    "log10",
    "exp",
    "tan",
    "sin",
    "cos",
    "sqrt",
    "atan",
    "atan2",
    "fmod",
    "floor",
    "ceil",
    "fabs",
    "tsf_timecents2Secsd",
}


def find_xtensa_tools() -> Tuple[Optional[str], Optional[str]]:
  gpp = shutil.which("xtensa-esp32s3-elf-g++")
  nm = shutil.which("xtensa-esp32s3-elf-nm")
  if gpp and nm:
    return gpp, nm

  local_appdata = os.environ.get("LOCALAPPDATA", "")
  user_profile = os.environ.get("USERPROFILE", "")
  search_roots = []
  if local_appdata:
    search_roots.append(Path(local_appdata) / "Arduino15" / "packages" / "esp32")
  if user_profile:
    search_roots.append(
        Path(user_profile) / "AppData" / "Local" / "Arduino15" / "packages" / "esp32"
    )
    search_roots.append(Path(user_profile) / ".platformio" / "packages")

  for root in search_roots:
    if not root.exists():
      continue
    matches = sorted(
        glob.glob(str(root / "**" / "xtensa-esp32s3-elf-g++.exe"), recursive=True)
    )
    if not matches:
      matches = sorted(
          glob.glob(str(root / "**" / "xtensa-esp32s3-elf-g++"), recursive=True)
      )
    if matches:
      gpp_path = Path(matches[-1])
      nm_path = gpp_path.with_name(
          gpp_path.name.replace("g++", "nm")
      )
      if nm_path.exists():
        return str(gpp_path), str(nm_path)

  return None, None


def run_fpu_audit(repo_root: Path) -> int:
  gpp, nm = find_xtensa_tools()
  if not gpp or not nm:
    print(
        "[ERRO] Compilador xtensa-esp32s3-elf-g++ nao encontrado na maquina.",
        file=sys.stderr,
    )
    return 1

  print(f"[INFO] Usando compilador Xtensa: {gpp}")
  print(f"[INFO] Usando inspetor ELF nm : {nm}")

  ino_path = repo_root / "esp32_midi_synth" / "esp32_midi_synth.ino"
  mock_dir = repo_root / "sim" / "arduino_mock"
  synth_dir = repo_root / "esp32_midi_synth"

  if not ino_path.exists():
    print(f"[ERRO] Arquivo nao encontrado: {ino_path}", file=sys.stderr)
    return 1

  with tempfile.TemporaryDirectory(prefix="esp32_fpu_audit_") as tmp_dir:
    tmp_path = Path(tmp_dir)
    tu_cpp = tmp_path / "fpu_audit_tu.cpp"
    obj_strict = tmp_path / "fpu_audit_strict.o"
    obj_esp32 = tmp_path / "fpu_audit_esp32.o"

    # Inclui diretamente o .ino real e referencia setup/loop para impedir
    # eliminacao de codigo morto nas tasks estaticas.
    tu_cpp.write_text(
        '#include "esp32_midi_synth.ino"\n'
        'extern "C" void fpu_audit_entry() {\n'
        "  setup();\n"
        "  loop();\n"
        "  sim_step_audio_block();\n"
        "}\n",
        encoding="utf-8",
    )

    # Passo 1 e 2: Compilacao estrita para arquitetura Xtensa ESP32-S3 SEM
    # -fsingle-precision-constant e COM -Werror=double-promotion para capturar
    # qualquer literal double implicito (ex: 1.0, 20.0, 32767.0) e gerar o ELF.
    cmd_esp32 = [
        gpp,
        "-pipe",
        "-x",
        "c++",
        "-std=gnu++17",
        "-O2",
        "-g0",
        "-Wall",
        "-Wextra",
        "-mfix-esp32-psram-cache-issue",
        "-mlongcalls",
        "-mtext-section-literals",
        "-Wdouble-promotion",
        "-Werror=double-promotion",
        "-fno-exceptions",
        "-fno-rtti",
        f"-I{mock_dir}",
        f"-I{synth_dir}",
        "-c",
        str(tu_cpp),
        "-o",
        str(obj_esp32),
    ]

    print(
        "[1/2] Compilando esp32_midi_synth.ino + tsf.h + piano_sf2.h "
        "(-Werror=double-promotion)..."
    )
    res_esp32 = subprocess.run(cmd_esp32, capture_output=True, text=True)
    if res_esp32.returncode != 0:
      print("[FALHA] O compilador Xtensa detectou promocao para double (64-bit) ou erro:")
      print(res_esp32.stderr or res_esp32.stdout)
      return 1
    print("      OK: Zero promocoes para double e objeto ELF Xtensa gerado.")

    # Passo 2: Inspecao da tabela de simbolos via xtensa-esp32s3-elf-nm
    print("[2/2] Auditando simbolos do objeto ELF com xtensa-esp32s3-elf-nm...")
    res_nm = subprocess.run([nm, str(obj_esp32)], capture_output=True, text=True)
    if res_nm.returncode != 0:
      print("[FALHA] Erro ao executar xtensa-esp32s3-elf-nm:")
      print(res_nm.stderr)
      return 1

    violations: List[str] = []
    float_math_symbols: List[str] = []
    for line in res_nm.stdout.splitlines():
      parts = line.strip().split()
      if not parts:
        continue
      sym = parts[-1]
      sym_type = parts[-2] if len(parts) >= 2 else "?"

      if sym in BANNED_DOUBLE_SYMBOLS or re.match(r"^__.*df[23]?$", sym):
        violations.append(f"{sym} (tipo {sym_type})")
      elif sym in {"powf", "expf", "logf", "log10f", "tanf", "sqrtf"}:
        float_math_symbols.append(sym)

    if violations:
      print("[FALHA] Simbolos de ponto flutuante de 64 bits (double) encontrados no ELF:")
      for v in violations:
        print(f"  - {v}")
      return 1

    print(
        "      OK: Nenhum simbolo double (*df*, pow, log, log10, tan, sqrt) "
        "encontrado!"
    )
    print(
        f"      Funcoes matematicas single-precision referenciadas: "
        f"{sorted(set(float_math_symbols))}"
    )

  print("[SUCESSO] Auditoria de FPU Xtensa ESP32-S3 concluida com 0 erros.")
  return 0


if __name__ == "__main__":
  root = Path(__file__).resolve().parent.parent
  sys.exit(run_fpu_audit(root))
