"""
Pré-processador de arquivos MIDI (.mid) para memórias ROM de 30 bits x 1024 palavras
do Piano FPGA (Modo Aprendizado e Modo Demonstração).

Formato de cada palavra de 30 bits (em binário ASCII, 1024 linhas por arquivo):
  - bits [29:22] (8 bits): PAUSA após a nota em ticks de 8 ms (0..255)
  - bits [21:14] (8 bits): DURACAO da nota (incluindo extensão de pedal sustain) em ticks de 8 ms (1..255)
  - bits [13:7]  (7 bits): VELOCITY MIDI (1..127)
  - bits [6:0]   (7 bits): NOTA_MIDI (24..107, ou 0 para fim_musica)
"""

import argparse
import os
import shutil
import struct
from typing import Dict, List, Optional, Tuple

TICK_SECONDS = 0.008
ROM_DEPTH = 1024
MAX_NOTES = ROM_DEPTH - 1  # Reserva pelo menos o último endereço (1023) com 30'd0 (fim_musica)
CHORD_WINDOW_S = 0.024     # Janela de 24 ms para agrupar acordes simultâneos

ROM_FILES = [
]


def _read_varlen(data: bytes, idx: int) -> Tuple[int, int]:
    """Lê um inteiro Variable-Length Quantity (VLQ) do padrão Standard MIDI File."""
    val = 0
    while True:
        b = data[idx]
        idx += 1
        val = (val << 7) | (b & 0x7F)
        if not (b & 0x80):
            break
    return val, idx


def parse_smf_events(midi_path: str) -> List[Dict]:
    """
    Faz o parse binário nativo de um arquivo Standard MIDI File (.mid) e retorna
    uma lista ordenada cronologicamente de eventos com tempo absoluto em segundos (`time_s`).
    """
    with open(midi_path, "rb") as f:
        data = f.read()

    if data[:4] != b"MThd":
        raise ValueError(f"Arquivo MIDI inválido (cabeçalho MThd ausente): {midi_path}")

    hdr_len = struct.unpack(">I", data[4:8])[0]
    fmt, ntrks, division = struct.unpack(">HHH", data[8:14])
    if division & 0x8000:
        raise ValueError("Divisão SMPTE não suportada; esperado ticks_per_beat.")
    ticks_per_beat = division

    pos = 8 + hdr_len
    raw_events: List[Tuple[int, int, Dict]] = []
    seq_counter = 0

    for _trk in range(ntrks):
        if pos >= len(data):
            break
        chunk_id = data[pos : pos + 4]
        chunk_len = struct.unpack(">I", data[pos + 4 : pos + 8])[0]
        trk_data = data[pos + 8 : pos + 8 + chunk_len]
        pos += 8 + chunk_len

        if chunk_id != b"MTrk":
            continue

        idx = 0
        abs_tick = 0
        running_status = 0

        while idx < len(trk_data):
            delta, idx = _read_varlen(trk_data, idx)
            abs_tick += delta

            status = trk_data[idx]
            if status >= 0x80:
                idx += 1
                if status < 0xF0:
                    running_status = status
            else:
                status = running_status

            if status == 0xFF:
                meta_type = trk_data[idx]
                idx += 1
                mlen, idx = _read_varlen(trk_data, idx)
                mdata = trk_data[idx : idx + mlen]
                idx += mlen
                if meta_type == 0x51 and len(mdata) == 3:
                    tempo_us = (mdata[0] << 16) | (mdata[1] << 8) | mdata[2]
                    raw_events.append((abs_tick, seq_counter, {"type": "tempo", "tempo_us": tempo_us}))
                    seq_counter += 1
            elif status in (0xF0, 0xF7):
                slen, idx = _read_varlen(trk_data, idx)
                idx += slen
            else:
                high = status & 0xF0
                ch = status & 0x0F
                if high in (0xC0, 0xD0):
                    idx += 1
                else:
                    p1 = trk_data[idx]
                    p2 = trk_data[idx + 1]
                    idx += 2
                    if high == 0x90 and p2 > 0:
                        raw_events.append(
                            (abs_tick, seq_counter, {"type": "note_on", "ch": ch, "note": p1, "vel": p2})
                        )
                        seq_counter += 1
                    elif high == 0x80 or (high == 0x90 and p2 == 0):
                        raw_events.append(
                            (abs_tick, seq_counter, {"type": "note_off", "ch": ch, "note": p1, "vel": p2})
                        )
                        seq_counter += 1
                    elif high == 0xB0 and p1 == 64:
                        raw_events.append(
                            (abs_tick, seq_counter, {"type": "cc64", "ch": ch, "value": p2})
                        )
                        seq_counter += 1

    raw_events.sort(key=lambda item: (item[0], item[1]))

    # Converte ticks acumulados em segundos integrando mudanças de andamento (Set Tempo)
    tempo_us = 500_000  # 120 BPM padrão inicial
    last_tick = 0
    current_time_s = 0.0
    timed_events: List[Dict] = []

    for tick, _seq, ev in raw_events:
        delta_ticks = tick - last_tick
        if delta_ticks > 0:
            current_time_s += (delta_ticks * (tempo_us / 1_000_000.0)) / ticks_per_beat
            last_tick = tick
        if ev["type"] == "tempo":
            tempo_us = ev["tempo_us"]
        else:
            ev_copy = dict(ev)
            ev_copy["time_s"] = current_time_s
            timed_events.append(ev_copy)

    return timed_events


def clamp_midi_note(note: int) -> int:
    """Transpõe a nota por oitavas caso esteja fora da faixa suportada (24..107)."""
    while note < 24:
        note += 12
    while note > 107:
        note -= 12
    return note


def extract_sustained_notes(timed_events: List[Dict]) -> List[Dict]:
    """
    Associa cada Note On ao seu Note Off e aplica a lógica física do pedal de sustain
    (Control Change 64 >= 64): se uma tecla é solta com o pedal pressionado, a nota
    continua soando até o instante em que o pedal é solto.
    """
    pedal_down = False
    active_keys: Dict[Tuple[int, int], List[Dict]] = {}
    sustained_notes: List[Dict] = []
    completed_notes: List[Dict] = []

    for ev in timed_events:
        t = ev["time_s"]
        etype = ev["type"]

        if etype == "cc64":
            new_pedal = ev["value"] >= 64
            if pedal_down and not new_pedal:
                # Pedal foi solto: encerra todas as notas retidas pelo sustain
                for nobj in sustained_notes:
                    nobj["t_end_effective"] = max(nobj["t_key_off"], t)
                    completed_notes.append(nobj)
                sustained_notes.clear()
            pedal_down = new_pedal

        elif etype == "note_on":
            key = (ev["ch"], ev["note"])
            # Se a mesma tecla já estava retida no pedal, encerra a anterior no novo ataque
            still_sustained = []
            for nobj in sustained_notes:
                if (nobj["ch"], nobj["note"]) == key:
                    nobj["t_end_effective"] = max(nobj["t_key_off"], t)
                    completed_notes.append(nobj)
                else:
                    still_sustained.append(nobj)
            sustained_notes = still_sustained

            active_keys.setdefault(key, []).append(
                {
                    "ch": ev["ch"],
                    "note": ev["note"],
                    "vel": ev["vel"],
                    "t_start": t,
                    "t_key_off": t,
                    "t_end_effective": t,
                }
            )

        elif etype == "note_off":
            key = (ev["ch"], ev["note"])
            stack = active_keys.get(key)
            if stack:
                nobj = stack.pop(0)
                nobj["t_key_off"] = t
                if pedal_down:
                    sustained_notes.append(nobj)
                else:
                    nobj["t_end_effective"] = t
                    completed_notes.append(nobj)

    # Fecha eventuais notas residuais no final do arquivo
    last_t = timed_events[-1]["time_s"] if timed_events else 0.0
    for stack in active_keys.values():
        for nobj in stack:
            nobj["t_key_off"] = max(nobj["t_start"] + TICK_SECONDS, last_t)
            nobj["t_end_effective"] = nobj["t_key_off"]
            completed_notes.append(nobj)
    for nobj in sustained_notes:
        nobj["t_end_effective"] = max(nobj["t_key_off"], last_t)
        completed_notes.append(nobj)

    completed_notes.sort(key=lambda n: (n["t_start"], n["note"]))
    return completed_notes


def select_monophonic_melody(notes: List[Dict], max_notes: int = MAX_NOTES) -> List[Dict]:
    """
    Agrupa notas quase simultâneas (dentro de CHORD_WINDOW_S = 24 ms) como acordes e
    seleciona a nota mais aguda de cada ataque como voz principal da melodia.
    """
    if not notes:
        return []

    melody: List[Dict] = []
    cluster: List[Dict] = [notes[0]]

    for n in notes[1:]:
        if (n["t_start"] - cluster[0]["t_start"]) < CHORD_WINDOW_S:
            cluster.append(n)
        else:
            best = max(cluster, key=lambda item: (item["note"], item["vel"]))
            melody.append(best)
            if len(melody) >= max_notes:
                cluster = []
                break
            cluster = [n]

    if cluster and len(melody) < max_notes:
        best = max(cluster, key=lambda item: (item["note"], item["vel"]))
        melody.append(best)

    return melody[:max_notes]


def encode_rom_word(pausa_ticks: int, dur_ticks: int, velocity: int, note_midi: int) -> str:
    """Formata uma palavra de 30 bits `{pausa[7:0], duracao[7:0], velocity[6:0], nota[6:0]}` em binário."""
    pausa_clamped = max(0, min(255, int(pausa_ticks)))
    dur_clamped = max(1, min(255, int(dur_ticks)))
    vel_clamped = max(1, min(127, int(velocity)))
    note_clamped = max(0, min(127, int(note_midi)))
    return f"{pausa_clamped:08b}{dur_clamped:08b}{vel_clamped:07b}{note_clamped:07b}"


def convert_midi_to_rom_lines(midi_path: str) -> List[str]:
    """Converte um arquivo `.mid` nas 1024 linhas binárias de 30 bits para `$readmemb`."""
    timed_events = parse_smf_events(midi_path)
    sustained_notes = extract_sustained_notes(timed_events)
    melody = select_monophonic_melody(sustained_notes, max_notes=MAX_NOTES)

    lines: List[str] = []
    for i, n in enumerate(melody):
        t_start = n["t_start"]
        raw_sustain_dur = max(TICK_SECONDS, n["t_end_effective"] - t_start)

        if i + 1 < len(melody):
            delta_t = max(TICK_SECONDS, melody[i + 1]["t_start"] - t_start)
            dur_s = min(raw_sustain_dur, delta_t)
            pausa_s = max(0.0, delta_t - dur_s)
        else:
            dur_s = raw_sustain_dur
            pausa_s = 0.0

        dur_ticks = max(1, min(255, int(round(dur_s / TICK_SECONDS))))
        pausa_ticks = max(0, min(255, int(round(pausa_s / TICK_SECONDS))))
        vel = max(1, min(127, n["vel"]))
        note_midi = clamp_midi_note(n["note"])

        lines.append(encode_rom_word(pausa_ticks, dur_ticks, vel, note_midi))

    while len(lines) < ROM_DEPTH:
        lines.append("0" * 30)

    return lines[:ROM_DEPTH]


def generate_scale_rom_lines() -> List[str]:
    """Gera uma escala Dó Maior (C4..B4) de 30 bits para `Do_Re_Mi_Fa.txt`."""
    scale_notes = [60, 62, 64, 65, 67, 69, 71]
    lines = [encode_rom_word(pausa_ticks=5, dur_ticks=40, velocity=100, note_midi=n) for n in scale_notes]
    while len(lines) < ROM_DEPTH:
        lines.append("0" * 30)
    return lines


def write_rom_file(path: str, lines: List[str]) -> None:
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    with open(path, "w", encoding="ascii", newline="\n") as f:
        for line in lines:
            f.write(line + "\n")


def main() -> None:
    parser = argparse.ArgumentParser(description="Converte arquivo MIDI (.mid) para ROM de 30 bits do FPGA.")
    parser.add_argument(
        "--midi",
        default="music/debussy-clair-de-lune.mid",
        help="Caminho do arquivo MIDI de entrada (padrão: music/debussy-clair-de-lune.mid)",
    )
    parser.add_argument(
        "--out-dir",
        default="music",
        help="Diretório de saída das memórias ROM (padrão: music)",
    )
    args = parser.parse_args()

    clair_lines = convert_midi_to_rom_lines(args.midi)
    clair_path = os.path.join(args.out_dir, "Clair_de_Lune.txt")
    write_rom_file(clair_path, clair_lines)

    scale_lines = generate_scale_rom_lines()
    for fname in ROM_FILES:
        fpath = os.path.join(args.out_dir, fname)
        if fname == "Clair_de_Lune.txt":
            continue
        elif fname == "Do_Re_Mi_Fa.txt":
            write_rom_file(fpath, scale_lines)
        elif not os.path.exists(fpath):
            write_rom_file(fpath, clair_lines)

    active_count = sum(1 for ln in clair_lines if int(ln[-7:], 2) != 0)
    print(f"[OK] Gerado {clair_path} com {active_count} notas melódicas (com sustain CC64) e {ROM_DEPTH} linhas de 30 bits.")


if __name__ == "__main__":
    main()
