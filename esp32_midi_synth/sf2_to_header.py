#!/usr/bin/env python3
"""
sf2_to_header.py - Converte um arquivo SoundFont (.sf2) para um header C (piano_sf2.h)
compatível com TinySoundFont (tsf.h) no ESP32-S3.

Uso:
    python sf2_to_header.py caminho/para/piano.sf2 [-o piano_sf2.h]
"""

import argparse
import math
import os
import struct
import sys

def write_c_header(sf2_bytes: bytes, output_path: str, source_desc: str) -> None:
    """Gera o arquivo header C contendo g_piano_sf2[]."""
    lines = [
        "/*",
        f" * Arquivo gerado automaticamente por sf2_to_header.py",
        f" * Fonte: {source_desc}",
        f" * Tamanho: {len(sf2_bytes)} bytes",
        " */",
        "#ifndef PIANO_SF2_H",
        "#define PIANO_SF2_H",
        "",
        "#include <stdint.h>",
        "#ifdef ARDUINO",
        "#include <pgmspace.h>",
        "#else",
        "#define PROGMEM",
        "#endif",
        "",
        f"const unsigned int g_piano_sf2_len = {len(sf2_bytes)}U;",
        "const unsigned char g_piano_sf2[] PROGMEM = {",
    ]

    row_size = 16
    for i in range(0, len(sf2_bytes), row_size):
        chunk = sf2_bytes[i : i + row_size]
        hex_str = ", ".join(f"0x{b:02X}" for b in chunk)
        comma = "," if (i + row_size < len(sf2_bytes)) else ""
        lines.append(f"    {hex_str}{comma}")

    lines.extend([
        "};",
        "",
        "#endif // PIANO_SF2_H",
        "",
    ])

    with open(output_path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines))


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Converte um arquivo SoundFont (.sf2) para piano_sf2.h."
    )
    parser.add_argument(
        "input_sf2",
        nargs="?",
        help="Caminho para o arquivo .sf2 de entrada.",
    )
    parser.add_argument(
        "-o",
        "--output",
        default=os.path.join(os.path.dirname(os.path.abspath(__file__)), "piano_sf2.h"),
        help="Caminho do header C de saída (padrão: piano_sf2.h).",
    )

    args = parser.parse_args()

    if not args.input_sf2:
        print(
            "[INFO] Nenhum arquivo .sf2 informado"
        )
    else:
        if not os.path.isfile(args.input_sf2):
            print(f"[ERRO] Arquivo não encontrado: {args.input_sf2}", file=sys.stderr)
            return 1
        with open(args.input_sf2, "rb") as f:
            sf2_bytes = f.read()
        if len(sf2_bytes) < 12 or sf2_bytes[:4] != b"RIFF" or sf2_bytes[8:12] != b"sfbk":
            print(
                f"[ERRO] O arquivo '{args.input_sf2}' não possui cabeçalho RIFF/sfbk válido de SoundFont 2.",
                file=sys.stderr,
            )
            return 1
        source_desc = os.path.basename(args.input_sf2)

    write_c_header(sf2_bytes, args.output, source_desc)
    print(f"[OK] Header gerado com sucesso: {args.output} ({len(sf2_bytes)} bytes)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
