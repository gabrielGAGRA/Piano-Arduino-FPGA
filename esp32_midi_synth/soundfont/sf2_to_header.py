#!/usr/bin/env python3
"""
sf2_to_header.py - Converte um arquivo SoundFont (.sf2) para um header C (piano_sf2.h)
compatível com TinySoundFont (tsf.h) no ESP32-S3.

Uso:
    python sf2_to_header.py caminho/para/piano.sf2 [-o piano_sf2.h]
"""

import argparse
from array import array
import math
import os
import struct
import sys
from typing import Dict, List, Optional, Tuple


SF_SAMPLE_MONO = 1
SF_SAMPLE_RIGHT = 2
SF_SAMPLE_LEFT = 4
GEN_PAN = 17
GEN_SAMPLE_ID = 53
SF2_SAMPLE_PAD_FRAMES = 46


def _parse_riff_chunks(buf: bytes, start: int, end: int) -> List[Tuple[bytes, bytes]]:
    """Lê subchunks RIFF sequenciais em [start, end)."""
    chunks: List[Tuple[bytes, bytes]] = []
    pos = start
    while pos + 8 <= end:
        cid = buf[pos : pos + 4]
        clen = struct.unpack_from("<I", buf, pos + 4)[0]
        payload = buf[pos + 8 : pos + 8 + clen]
        chunks.append((cid, payload))
        pos += 8 + clen + (clen & 1)
    return chunks


def _pack_riff_chunk(cid: bytes, payload: bytes) -> bytes:
    """Empacota um chunk RIFF com padding par."""
    pad = b"\x00" if (len(payload) & 1) else b""
    return cid + struct.pack("<I", len(payload)) + payload + pad


def _pack_list_chunk(list_type: bytes, subchunks: List[Tuple[bytes, bytes]]) -> bytes:
    """Empacota um bloco LIST RIFF."""
    body = list_type + b"".join(_pack_riff_chunk(cid, pay) for cid, pay in subchunks)
    return _pack_riff_chunk(b"LIST", body)


def _resample_windowed_sinc(samples: array, src_rate: int, dst_rate: int) -> array:
    """Reamostra array('h') com filtro anti-aliasing sinc janelado (Blackman)."""
    if src_rate == dst_rate or len(samples) <= 1:
        return samples

    ratio = dst_rate / float(src_rate)
    dst_len = max(1, int(round(len(samples) * ratio)))
    out = array("h", [0]) * dst_len

    half_taps = 6
    cutoff = 0.90 * min(1.0, ratio)
    inv_ratio = 1.0 / ratio
    two_pi = 2.0 * math.pi
    four_pi = 4.0 * math.pi
    n_src = len(samples)
    sin = math.sin
    cos = math.cos
    pi = math.pi

    for i in range(dst_len):
        center = i * inv_ratio
        j0 = int(math.floor(center)) - half_taps + 1
        j1 = j0 + (2 * half_taps)
        acc = 0.0
        wsum = 0.0
        for j in range(j0, j1):
            if 0 <= j < n_src:
                dx = center - j
                if abs(dx) < 1e-9:
                    sinc_v = cutoff
                else:
                    px = pi * dx * cutoff
                    sinc_v = sin(px) / (pi * dx)
                u = (dx + half_taps) / (2.0 * half_taps)
                win = 0.42 - 0.50 * cos(two_pi * u) + 0.08 * cos(four_pi * u)
                w = sinc_v * win
                acc += samples[j] * w
                wsum += w
        val = int(round(acc / wsum)) if wsum > 1e-9 else 0
        if val > 32767:
            val = 32767
        elif val < -32768:
            val = -32768
        out[i] = val
    return out


def convert_sf2(
    sf2_bytes: bytes,
    to_mono: bool = False,
    target_sample_rate: Optional[int] = None,
) -> bytes:
    """Converte um SoundFont2 (.sf2) 16-bit PCM para mono e/ou nova taxa de amostragem."""
    if not to_mono and target_sample_rate is None:
        return sf2_bytes

    if len(sf2_bytes) < 12 or sf2_bytes[:4] != b"RIFF" or sf2_bytes[8:12] != b"sfbk":
        raise ValueError("Arquivo não possui cabeçalho RIFF/sfbk válido.")

    top_chunks = _parse_riff_chunks(sf2_bytes, 12, len(sf2_bytes))
    info_chunk: Optional[Tuple[bytes, bytes]] = None
    sdta_subchunks: List[Tuple[bytes, bytes]] = []
    pdta_subchunks: Dict[bytes, bytes] = {}

    for cid, pay in top_chunks:
        if cid != b"LIST" or len(pay) < 4:
            continue
        ltype = pay[:4]
        subs = _parse_riff_chunks(pay, 4, len(pay))
        if ltype == b"INFO":
            info_chunk = (ltype, pay[4:])
        elif ltype == b"sdta":
            sdta_subchunks = subs
        elif ltype == b"pdta":
            pdta_subchunks = {scid: spay for scid, spay in subs}

    smpl_bytes = next((p for cid, p in sdta_subchunks if cid == b"smpl"), None)
    if smpl_bytes is None:
        raise ValueError("Chunk 'smpl' não encontrado no SF2.")

    pcm_all = array("h")
    pcm_all.frombytes(smpl_bytes[: len(smpl_bytes) - (len(smpl_bytes) % 2)])
    if sys.byteorder != "little":
        pcm_all.byteswap()

    shdr_raw = pdta_subchunks[b"shdr"]
    n_shdr = len(shdr_raw) // 46
    if n_shdr < 2:
        raise ValueError("Tabela 'shdr' inválida.")

    shdr_recs = []
    for i in range(n_shdr - 1):
        rec = struct.unpack_from("<20sIIIIIBbHH", shdr_raw, i * 46)
        shdr_recs.append(list(rec))
    eos_rec = shdr_raw[(n_shdr - 1) * 46 : n_shdr * 46]

    # 1. Decide quais amostras manter e converte L+R -> Mono
    kept_indices: List[int] = []
    dropped_right = set()
    old_to_new_idx: Dict[int, int] = {}

    for i, rec in enumerate(shdr_recs):
        stype = rec[9]
        if to_mono and stype == SF_SAMPLE_RIGHT:
            dropped_right.add(i)
            continue
        old_to_new_idx[i] = len(kept_indices)
        kept_indices.append(i)

    new_pcm = array("h")
    new_shdr_bytes = bytearray()

    for new_i, old_i in enumerate(kept_indices):
        name, d_start, d_end, d_sloop, d_eloop, sr, pitch, corr, link, stype = shdr_recs[old_i]
        seg = array("h", pcm_all[d_start:d_end])

        if to_mono and stype == SF_SAMPLE_LEFT and 0 <= link < len(shdr_recs):
            r_rec = shdr_recs[link]
            r_seg = pcm_all[r_rec[1] : r_rec[2]]
            n_mix = min(len(seg), len(r_seg))
            for k in range(n_mix):
                seg[k] = (seg[k] + r_seg[k]) >> 1
            seg = seg[:n_mix]
            stype = SF_SAMPLE_MONO
            link = 0
        elif to_mono:
            stype = SF_SAMPLE_MONO
            link = 0
        else:
            link = old_to_new_idx.get(link, 0)

        rel_sloop = max(0, min(d_sloop - d_start, len(seg)))
        rel_eloop = max(rel_sloop, min(d_eloop - d_start, len(seg)))

        if target_sample_rate is not None and sr != target_sample_rate and len(seg) > 1:
            scale = target_sample_rate / float(sr)
            seg = _resample_windowed_sinc(seg, sr, target_sample_rate)
            rel_sloop = max(0, min(int(round(rel_sloop * scale)), len(seg)))
            rel_eloop = max(rel_sloop, min(int(round(rel_eloop * scale)), len(seg)))
            sr = target_sample_rate

        new_start = len(new_pcm)
        new_pcm.extend(seg)
        new_end = len(new_pcm)
        new_pcm.extend([0] * SF2_SAMPLE_PAD_FRAMES)

        new_shdr_bytes.extend(
            struct.pack(
                "<20sIIIIIBbHH",
                name,
                new_start,
                new_end,
                new_start + rel_sloop,
                new_start + rel_eloop,
                sr,
                pitch,
                corr,
                link,
                stype,
            )
        )

    new_shdr_bytes.extend(eos_rec)

    # 2. Atualiza inst/ibag/imod/igen removendo zonas do canal Right e ajustando GenSampleID/Pan
    inst_raw = pdta_subchunks[b"inst"]
    ibag_raw = pdta_subchunks[b"ibag"]
    imod_raw = pdta_subchunks[b"imod"]
    igen_raw = pdta_subchunks[b"igen"]

    n_inst = len(inst_raw) // 22
    n_ibag = len(ibag_raw) // 4

    new_inst_bytes = bytearray()
    new_ibag_bytes = bytearray()
    new_imod_bytes = bytearray()
    new_igen_bytes = bytearray()

    cur_ibag = 0
    cur_igen = 0
    cur_imod = 0

    for ii in range(n_inst - 1):
        iname, bag_start = struct.unpack_from("<20sH", inst_raw, ii * 22)
        _, bag_end = struct.unpack_from("<20sH", inst_raw, (ii + 1) * 22)
        new_inst_bytes.extend(struct.pack("<20sH", iname, cur_ibag))

        for bi in range(bag_start, bag_end):
            g_start, m_start = struct.unpack_from("<HH", ibag_raw, bi * 4)
            g_end, m_end = struct.unpack_from("<HH", ibag_raw, (bi + 1) * 4)

            gens = [
                list(struct.unpack_from("<Hh", igen_raw, gi * 4))
                for gi in range(g_start, g_end)
            ]

            # Verifica se esta zona aponta para uma amostra Right descartada
            drop_zone = False
            for idx_g, (oper, amt) in enumerate(gens):
                if oper == GEN_SAMPLE_ID:
                    sid = amt & 0xFFFF
                    if sid in dropped_right:
                        drop_zone = True
                    else:
                        gens[idx_g][1] = old_to_new_idx[sid]
                elif to_mono and oper == GEN_PAN:
                    gens[idx_g][1] = 0

            if drop_zone:
                continue

            new_ibag_bytes.extend(struct.pack("<HH", cur_igen, cur_imod))
            for oper, amt in gens:
                new_igen_bytes.extend(struct.pack("<Hh", oper, amt))
                cur_igen += 1
            for mi in range(m_start, m_end):
                new_imod_bytes.extend(imod_raw[mi * 10 : (mi + 1) * 10])
                cur_imod += 1
            cur_ibag += 1

    # Terminais de inst, ibag, imod, igen
    new_inst_bytes.extend(struct.pack("<20sH", b"EOI\x00".ljust(20, b"\x00"), cur_ibag))
    new_ibag_bytes.extend(struct.pack("<HH", cur_igen, cur_imod))
    new_imod_bytes.extend(imod_raw[-10:])
    new_igen_bytes.extend(igen_raw[-4:])

    if sys.byteorder != "little":
        new_pcm.byteswap()
    new_smpl_bytes = new_pcm.tobytes()

    pdta_order = [
        (b"phdr", pdta_subchunks[b"phdr"]),
        (b"pbag", pdta_subchunks[b"pbag"]),
        (b"pmod", pdta_subchunks[b"pmod"]),
        (b"pgen", pdta_subchunks[b"pgen"]),
        (b"inst", bytes(new_inst_bytes)),
        (b"ibag", bytes(new_ibag_bytes)),
        (b"imod", bytes(new_imod_bytes)),
        (b"igen", bytes(new_igen_bytes)),
        (b"shdr", bytes(new_shdr_bytes)),
    ]

    body = b"sfbk"
    if info_chunk is not None:
        body += _pack_riff_chunk(b"LIST", info_chunk[0] + info_chunk[1])
    body += _pack_list_chunk(b"sdta", [(b"smpl", new_smpl_bytes)])
    body += _pack_list_chunk(b"pdta", pdta_order)

    return b"RIFF" + struct.pack("<I", len(body)) + body

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
    parser.add_argument(
        "--mono",
        action="store_true",
        help="Converte pares estéreo (L+R) para mono antes de gerar o header.",
    )
    parser.add_argument(
        "--sample-rate",
        type=int,
        default=None,
        help="Reamostra o áudio interno do SF2 para a taxa alvo em Hz (ex: 24000).",
    )
    parser.add_argument(
        "--save-sf2",
        default=None,
        help="Salva o arquivo .sf2 convertido no caminho especificado.",
    )
    parser.add_argument(
        "--max-bytes",
        type=int,
        default=15200000,
        help="Limite máximo em bytes para o SF2 final (padrão: 15200000).",
    )

    args = parser.parse_args()

    if not args.input_sf2:
        print("[ERRO] Nenhum arquivo .sf2 informado.", file=sys.stderr)
        return 1

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

    if args.mono or args.sample_rate is not None:
        print(f"[INFO] Convertendo '{source_desc}' (mono={args.mono}, sample_rate={args.sample_rate})...")
        sf2_bytes = convert_sf2(sf2_bytes, to_mono=args.mono, target_sample_rate=args.sample_rate)
        flags = []
        if args.mono:
            flags.append("mono")
        if args.sample_rate is not None:
            flags.append(f"{args.sample_rate}Hz")
        source_desc = f"{source_desc} ({', '.join(flags)})"

    if args.max_bytes > 0 and len(sf2_bytes) > args.max_bytes:
        print(
            f"[ERRO] SF2 convertido ({len(sf2_bytes)} bytes) excede o limite de {args.max_bytes} bytes.",
            file=sys.stderr,
        )
        return 1

    if args.save_sf2:
        with open(args.save_sf2, "wb") as f:
            f.write(sf2_bytes)
        print(f"[OK] SF2 convertido salvo em: {args.save_sf2} ({len(sf2_bytes)} bytes)")

    write_c_header(sf2_bytes, args.output, source_desc)
    print(f"[OK] Header gerado com sucesso: {args.output} ({len(sf2_bytes)} bytes)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
