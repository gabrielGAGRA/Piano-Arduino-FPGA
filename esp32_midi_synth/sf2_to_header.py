#!/usr/bin/env python3
"""
sf2_to_header.py - Converte um arquivo SoundFont (.sf2) para um header C (piano_sf2.h)
compatível com TinySoundFont (tsf.h) no ESP32-S3.

Uso:
    python sf2_to_header.py caminho/para/piano.sf2 [-o piano_sf2.h]
    python sf2_to_header.py --generate-minimal [-o piano_sf2.h]
"""

import argparse
import math
import os
import struct
import sys


def build_minimal_piano_sf2() -> bytes:
    """
    Constrói um arquivo SoundFont 2.01 (.sf2) mínimo e válido em memória,
    contendo uma forma de onda com harmônicos de piano (fundamental + 2º, 3º e 4º harmônicos)
    em 44100 Hz para permitir compilação e teste imediato do firmware ESP32-S3.
    """
    sample_rate = 44100
    freq = 440.0  # A4 (Nota MIDI 69)
    # 100 períodos exatos de 440 Hz (~10022 amostras) para loop perfeito
    num_samples = int(round(sample_rate * 100 / freq))
    samples = []
    for i in range(num_samples):
        t = i / sample_rate
        # Síntese aditiva básica com timbre rico em harmônicos
        val = (
            0.65 * math.sin(2.0 * math.pi * freq * t)
            + 0.20 * math.sin(2.0 * math.pi * (2.0 * freq) * t)
            + 0.10 * math.sin(2.0 * math.pi * (3.0 * freq) * t)
            + 0.05 * math.sin(2.0 * math.pi * (4.0 * freq) * t)
        )
        pcm = max(-32767, min(32767, int(val * 30000)))
        samples.append(pcm)

    # 46 amostras de zero no final conforme especificação SF2
    samples.extend([0] * 46)
    smpl_data = struct.pack(f"<{len(samples)}h", *samples)

    def chunk(fourcc: bytes, data: bytes) -> bytes:
        pad = b"\x00" if (len(data) % 2 == 1) else b""
        return fourcc + struct.pack("<I", len(data)) + data + pad

    def list_chunk(list_type: bytes, children: bytes) -> bytes:
        return chunk(b"LIST", list_type + children)

    # 1. INFO-list
    ifil = chunk(b"ifil", struct.pack("<HH", 2, 1))
    isng = chunk(b"isng", b"EMU8000\x00")
    inam = chunk(b"INAM", b"Minimal ESP32 Piano\x00")
    info_list = list_chunk(b"INFO", ifil + isng + inam)

    # 2. sdta-list
    sdta_list = list_chunk(b"sdta", chunk(b"smpl", smpl_data))

    # 3. pdta-list (9 subchunks obrigatórios do formato SF2)
    # phdr: 2 registros de 38 bytes (Preset 0 + EOP)
    phdr_data = struct.pack("<20sHHHIII", b"Grand Piano\x00", 0, 0, 0, 0, 0, 0)
    phdr_data += struct.pack("<20sHHHIII", b"EOP\x00", 0, 0, 1, 0, 0, 0)

    # pbag: 2 registros de 4 bytes
    pbag_data = struct.pack("<HH", 0, 0) + struct.pack("<HH", 1, 0)

    # pmod: 1 registro terminal de 10 bytes
    pmod_data = struct.pack("<HHhHH", 0, 0, 0, 0, 0)

    # pgen: 2 registros de 4 bytes (Operador 41 = instrument 0 + terminal)
    pgen_data = struct.pack("<HH", 41, 0) + struct.pack("<HH", 0, 0)

    # inst: 2 registros de 22 bytes (Instrument 0 + EOI)
    inst_data = struct.pack("<20sH", b"Piano Inst\x00", 0)
    inst_data += struct.pack("<20sH", b"EOI\x00", 1)

    # ibag: 2 registros de 4 bytes
    ibag_data = struct.pack("<HH", 0, 0) + struct.pack("<HH", 4, 0)

    # imod: 1 registro terminal de 10 bytes
    imod_data = struct.pack("<HHhHH", 0, 0, 0, 0, 0)

    # igen: operadores para envelope + sampleModes(54=1 loop) + releaseVolEnv(38) + sampleID(53=0)
    igen_data = (
        struct.pack("<Hh", 38, 1200)   # releaseVolEnv (~2.0s de release suave)
        + struct.pack("<Hh", 36, 1200) # decayVolEnv
        + struct.pack("<Hh", 54, 1)    # sampleModes = 1 (loop contínuo)
        + struct.pack("<HH", 53, 0)    # sampleID = 0
        + struct.pack("<HH", 0, 0)     # terminal
    )

    # shdr: 2 registros de 46 bytes (Sample 0 + EOS)
    shdr_data = struct.pack(
        "<20sIIIIIBbHH",
        b"PianoA4\x00",
        0,
        num_samples,
        0,
        num_samples,
        sample_rate,
        69,  # originalPitch = 69 (A4)
        0,   # pitchCorrection
        0,
        1,   # monoSample
    )
    shdr_data += struct.pack(
        "<20sIIIIIBbHH", b"EOS\x00", 0, 0, 0, 0, 0, 0, 0, 0, 0
    )

    pdta_children = (
        chunk(b"phdr", phdr_data)
        + chunk(b"pbag", pbag_data)
        + chunk(b"pmod", pmod_data)
        + chunk(b"pgen", pgen_data)
        + chunk(b"inst", inst_data)
        + chunk(b"ibag", ibag_data)
        + chunk(b"imod", imod_data)
        + chunk(b"igen", igen_data)
        + chunk(b"shdr", shdr_data)
    )
    pdta_list = list_chunk(b"pdta", pdta_children)

    riff_body = b"sfbk" + info_list + sdta_list + pdta_list
    return chunk(b"RIFF", riff_body)


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
        help="Caminho para o arquivo .sf2 de entrada (ou omita com --generate-minimal).",
    )
    parser.add_argument(
        "-o",
        "--output",
        default=os.path.join(os.path.dirname(os.path.abspath(__file__)), "piano_sf2.h"),
        help="Caminho do header C de saída (padrão: piano_sf2.h).",
    )
    parser.add_argument(
        "--generate-minimal",
        action="store_true",
        help="Gera um SoundFont (.sf2) sintético mínimo funcional de piano.",
    )

    args = parser.parse_args()

    if args.generate_minimal or not args.input_sf2:
        if not args.generate_minimal and not args.input_sf2:
            print(
                "[INFO] Nenhum arquivo .sf2 informado; gerando SoundFont mínimo funcional (--generate-minimal)."
            )
        sf2_bytes = build_minimal_piano_sf2()
        source_desc = "Minimal Built-in Piano SF2 (44100 Hz)"
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
