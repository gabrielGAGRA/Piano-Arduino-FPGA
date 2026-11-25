"""
Versão simples do conversor de MIDI (.mid) para ROM de 30 bits do Piano FPGA.

Regras de seleção:
- Mantém estritamente uma nota por vez (monofônico), escolhendo o canal pela nota mais aguda.
- Se houver qualquer overlap entre notas (de oitavas ou canais diferentes), mantém a mais aguda
  e descarta a outra.
- Só troca de canal para um canal mais grave se o canal atual ficar em silêncio por mais de
  1.0 segundo e o outro canal tiver pelo menos 2.0 segundos e 2 notas válidas nessa janela
  antes de voltar a um canal mais agudo; se um canal mais agudo voltar a tocar, retorna na hora.
"""

import argparse
import os
import struct
from typing import Dict, List, Optional, Tuple

TICK_SECONDS = 0.008
ROM_DEPTH = 1024
MAX_NOTES = ROM_DEPTH - 1  # Reserva pelo menos o último endereço com 30'd0 (fim_musica)

OVERLAP_EPS_S = 0.004       # Tolerância de 4 ms (< 1 tick) para bordas encostadas
SILENCE_SWITCH_S = 1.0      # Mínimo de silêncio (s) para trocar para canal mais grave
MIN_SWITCH_DURATION_S = 2.0 # Mínimo de duração (s) no outro canal para validar a troca
MIN_SWITCH_NOTES = 2        # Mínimo de notas no outro canal para validar a troca


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


def parse_smf_events(
    midi_path: str,
    allowed_channels: Optional[List[int]] = None,
    exclude_channels: Optional[List[int]] = None,
    ignore_drums: bool = True,
) -> List[Dict]:
    """
    Faz o parse binário nativo de um arquivo Standard MIDI File (.mid) e retorna
    uma lista ordenada cronologicamente de eventos com tempo absoluto em segundos (`time_s`).
    Ignora canais de percussão (ch=9) por padrão e filtra canais se especificado.
    """
    with open(midi_path, "rb") as f:
        data = f.read()

    if data[:4] != b"MThd":
        raise ValueError(f"Arquivo MIDI inválido (cabeçalho MThd ausente): {midi_path}")

    hdr_len = struct.unpack(">I", data[4:8])[0]
    _fmt, ntrks, division = struct.unpack(">HHH", data[8:14])
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

                if ignore_drums and ch == 9:
                    idx += 1 if high in (0xC0, 0xD0) else 2
                    continue
                if exclude_channels is not None and ch in exclude_channels:
                    idx += 1 if high in (0xC0, 0xD0) else 2
                    continue
                if allowed_channels is not None and ch not in allowed_channels:
                    idx += 1 if high in (0xC0, 0xD0) else 2
                    continue

                if high in (0xC0, 0xD0):
                    idx += 1
                else:
                    p1 = trk_data[idx]
                    p2 = trk_data[idx + 1]
                    idx += 2
                    if high == 0x90:
                        if p2 == 0:
                            raw_events.append(
                                (abs_tick, seq_counter, {"type": "note_off", "ch": ch, "note": p1, "vel": 0})
                            )
                        else:
                            raw_events.append(
                                (abs_tick, seq_counter, {"type": "note_on", "ch": ch, "note": p1, "vel": p2})
                            )
                        seq_counter += 1
                    elif high == 0x80:
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

    tempo_us = 500_000
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
    (Control Change 64 >= 64).
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
                for nobj in sustained_notes:
                    nobj["t_end_effective"] = max(nobj["t_key_off"], t)
                    completed_notes.append(nobj)
                sustained_notes.clear()
            pedal_down = new_pedal

        elif etype == "note_on":
            key = (ev["ch"], ev["note"])
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


def optimize_transposition_for_7_keys(melody: List[Dict]) -> List[Dict]:
    """Transposição clássica direta mantendo contorno sem alterações."""
    if not melody:
        return melody

    pitches = [n["note"] for n in melody]
    best_shift = 0
    best_nat_count = -1
    for shift in range(-6, 7):
        nats = sum(1 for p in pitches if ((p + shift) % 12) in (0, 2, 4, 5, 7, 9, 11))
        if nats > best_nat_count:
            best_nat_count = nats
            best_shift = shift

    shifted = [p + best_shift for p in pitches]
    mean_pitch = sum(shifted) / len(shifted)
    octave_shift = 0
    while (mean_pitch + octave_shift) < 60:
        octave_shift += 12
    while (mean_pitch + octave_shift) > 71:
        octave_shift -= 12

    total_shift = best_shift + octave_shift
    optimized_melody = []
    for n in melody:
        n_copy = dict(n)
        n_copy["note"] = clamp_midi_note(n["note"] + total_shift)
        optimized_melody.append(n_copy)

    return optimized_melody


def encode_rom_word(pausa_ticks: int, dur_ticks: int, velocity: int, note_midi: int) -> str:
    """Formata uma palavra de 30 bits `{pausa[7:0], duracao[7:0], velocity[6:0], nota[6:0]}` em binário."""
    pausa_clamped = max(0, min(255, int(pausa_ticks)))
    dur_clamped = max(1, min(255, int(dur_ticks)))
    vel_clamped = max(1, min(127, int(velocity)))
    note_clamped = max(0, min(127, int(note_midi)))
    return f"{pausa_clamped:08b}{dur_clamped:08b}{vel_clamped:07b}{note_clamped:07b}"


def encode_rom_word_hex(pausa_ticks: int, dur_ticks: int, velocity: int, note_midi: int) -> str:
    """Formata uma palavra de 30 bits `{pausa[7:0], duracao[7:0], velocity[6:0], nota[6:0]}` em hexadecimal (8 dígitos)."""
    pausa_clamped = max(0, min(255, int(pausa_ticks)))
    dur_clamped = max(1, min(255, int(dur_ticks)))
    vel_clamped = max(1, min(127, int(velocity)))
    note_clamped = max(0, min(127, int(note_midi)))
    val = (pausa_clamped << 22) | (dur_clamped << 14) | (vel_clamped << 7) | note_clamped
    return f"{val:08x}"


def write_rom_file(path: str, lines: List[str]) -> None:
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    with open(path, "w", encoding="ascii", newline="\n") as f:
        for line in lines:
            f.write(line + "\n")


def words_to_midi(words: List[str], out_mid_path: str) -> None:
    """Exporta uma lista de palavras de 30 bits de volta para um arquivo Standard MIDI File (.mid) tocável."""
    events = bytearray()
    events += b"\x00\xFF\x51\x03\x0F\x42\x40"

    def write_vlq(delta: int) -> None:
        buf = bytearray()
        buf.append(delta & 0x7F)
        delta >>= 7
        while delta > 0:
            buf.append((delta & 0x7F) | 0x80)
            delta >>= 7
        events.extend(reversed(buf))

    pending_delta = 0
    for w in words:
        val = int(w, 16) if len(w) == 8 else int(w, 2)
        note = val & 0x7F
        if note == 0:
            break
        vel = (val >> 7) & 0x7F
        dur = (val >> 14) & 0xFF
        pausa = (val >> 22) & 0xFF

        write_vlq(pending_delta)
        events.extend(bytes([0x90, note, vel]))

        write_vlq(dur)
        events.extend(bytes([0x80, note, 0]))

        pending_delta = pausa

    write_vlq(pending_delta)
    events += b"\xFF\x2F\x00"

    header = struct.pack(">4sIHHH", b"MThd", 6, 0, 1, 125)
    track = struct.pack(">4sI", b"MTrk", len(events)) + events

    os.makedirs(os.path.dirname(os.path.abspath(out_mid_path)), exist_ok=True)
    with open(out_mid_path, "wb") as f:
        f.write(header + track)


def _channel_skyline(notes: List[Dict], overlap_eps: float) -> List[Dict]:
    """Remove overlaps internos de um único canal mantendo sempre a nota mais aguda."""
    prioritized = sorted(notes, key=lambda n: (-n["note"], -n["vel"], n["t_start"]))
    accepted: List[Dict] = []
    for cand in prioritized:
        c_start = cand["t_start"]
        c_end = max(c_start + TICK_SECONDS, cand["t_end_effective"])
        has_overlap = any(
            c_start < (max(acc["t_start"] + TICK_SECONDS, acc["t_end_effective"]) - overlap_eps)
            and c_end > (acc["t_start"] + overlap_eps)
            for acc in accepted
        )
        if not has_overlap:
            accepted.append(dict(cand))
    accepted.sort(key=lambda n: (n["t_start"], n["note"]))
    return accepted


def _has_overlap(a: Dict, b: Dict, overlap_eps: float) -> bool:
    a_end = max(a["t_start"] + TICK_SECONDS, a["t_end_effective"])
    b_end = max(b["t_start"] + TICK_SECONDS, b["t_end_effective"])
    return a["t_start"] < (b_end - overlap_eps) and a_end > (b["t_start"] + overlap_eps)


def select_highest_no_overlap(
    notes: List[Dict],
    max_notes: int = MAX_NOTES,
    overlap_eps: float = OVERLAP_EPS_S,
    silence_threshold_s: float = SILENCE_SWITCH_S,
    min_switch_duration_s: float = MIN_SWITCH_DURATION_S,
    min_switch_notes: int = MIN_SWITCH_NOTES,
) -> List[Dict]:
    """
    Seleciona uma voz monofônica sem overlaps priorizando o canal com a nota mais aguda
    e aplicando histerese de >1s de silêncio + mínimo de 2s e 2 notas no outro canal
    antes de descer a um canal mais grave.
    """
    if not notes:
        return []

    by_ch: Dict[int, List[Dict]] = {}
    for n in notes:
        by_ch.setdefault(n["ch"], []).append(n)

    ch_lists: Dict[int, List[Dict]] = {
        ch: _channel_skyline(ch_notes, overlap_eps) for ch, ch_notes in by_ch.items()
    }
    idx: Dict[int, int] = {ch: 0 for ch in ch_lists}

    def peek(ch: int) -> Optional[Dict]:
        i = idx[ch]
        lst = ch_lists[ch]
        return lst[i] if i < len(lst) else None

    def advance_past(ch: int, t_limit: float) -> None:
        lst = ch_lists[ch]
        while idx[ch] < len(lst) and lst[idx[ch]]["t_start"] < t_limit - overlap_eps:
            idx[ch] += 1

    # Escolhe nota inicial mais aguda entre as primeiras disponíveis
    first_cands = [peek(ch) for ch in ch_lists if peek(ch) is not None]
    if not first_cands:
        return []
    earliest_t = min(c["t_start"] for c in first_cands)
    # Considera notas que começam junto ou em overlap com a mais cedo
    first_pool = [
        c for c in first_cands
        if c["t_start"] <= earliest_t + overlap_eps
        or any(_has_overlap(c, o, overlap_eps) for o in first_cands if o["t_start"] <= earliest_t + overlap_eps)
    ]
    first_note = max(first_pool, key=lambda n: (n["note"], n["vel"], -n["t_start"]))

    selected: List[Dict] = [dict(first_note)]
    active_ch = first_note["ch"]
    idx[active_ch] += 1

    while len(selected) < max_notes:
        last = selected[-1]
        last_end = max(last["t_start"] + TICK_SECONDS, last["t_end_effective"])

        # Avança outros canais apenas além de notas já ultrapassadas sem overlap
        for ch in list(ch_lists.keys()):
            if ch != active_ch:
                while idx[ch] < len(ch_lists[ch]):
                    cand = ch_lists[ch][idx[ch]]
                    if cand["t_start"] < last["t_start"] - overlap_eps:
                        idx[ch] += 1
                    elif _has_overlap(cand, last, overlap_eps) and cand["note"] <= last["note"]:
                        idx[ch] += 1
                    else:
                        break

        # 1. Verifica se algum outro canal interrompe com nota mais aguda em overlap com `last`
        interrupt_cands = []
        for ch in ch_lists:
            if ch == active_ch:
                continue
            c = peek(ch)
            if c is not None and _has_overlap(c, last, overlap_eps) and c["note"] > last["note"]:
                interrupt_cands.append(c)

        if interrupt_cands:
            best = max(interrupt_cands, key=lambda n: (n["note"], n["vel"], -n["t_start"]))
            selected[-1] = dict(best)
            active_ch = best["ch"]
            idx[active_ch] += 1
            continue

        # 2. Próxima nota do canal ativo
        next_act = peek(active_ch)
        next_act_t = next_act["t_start"] if next_act is not None else float("inf")

        # 3. Durante o silêncio de active_ch [last_end, next_act_t], verifica se outro canal
        #    tem nota mais aguda que last["note"] (sobe/volta na hora)
        higher_cands = []
        for ch in ch_lists:
            if ch == active_ch:
                continue
            c = peek(ch)
            if c is not None and c["t_start"] < next_act_t - overlap_eps and c["note"] > last["note"]:
                if not _has_overlap(c, last, overlap_eps):
                    higher_cands.append(c)

        if higher_cands:
            # Pega a que chega mais cedo (em empate, a mais aguda)
            best = min(higher_cands, key=lambda n: (n["t_start"], -n["note"], -n["vel"]))
            # Se tiver overlap com a volta do canal ativo e for mais grave que ela, descarta
            if next_act is not None and _has_overlap(best, next_act, overlap_eps) and next_act["note"] >= best["note"]:
                idx[best["ch"]] += 1
                continue
            selected.append(dict(best))
            active_ch = best["ch"]
            idx[active_ch] += 1
            continue

        # 4. Troca para canal mais grave só se silêncio > 1.0s E >= 2.0s E >= 2 notas válidas na janela
        #    (antes de voltar para active_ch ou qualquer canal mais agudo)
        silence_dur = next_act_t - last_end
        if silence_dur > silence_threshold_s:
            best_lower_ch = None
            best_lower_score = None
            for ch in ch_lists:
                if ch == active_ch:
                    continue
                # Encontra a primeira nota em outro canal que seja mais aguda que as do candidato
                # ou que o último pitch do canal ativo, limitando a janela antes de subir de novo
                valid_in_gap = []
                j = idx[ch]
                while j < len(ch_lists[ch]):
                    cn = ch_lists[ch][j]
                    if cn["t_start"] >= next_act_t - overlap_eps:
                        break
                    if cn["t_start"] >= last_end - overlap_eps and not _has_overlap(cn, last, overlap_eps):
                        if next_act is not None and _has_overlap(cn, next_act, overlap_eps) and next_act["note"] >= cn["note"]:
                            j += 1
                            continue
                        valid_in_gap.append(cn)
                    j += 1

                if len(valid_in_gap) >= min_switch_notes:
                    gap_span = (
                        max(valid_in_gap[-1]["t_start"] + TICK_SECONDS, valid_in_gap[-1]["t_end_effective"])
                        - valid_in_gap[0]["t_start"]
                    )
                    if gap_span >= min_switch_duration_s - overlap_eps:
                        score = (max(n["note"] for n in valid_in_gap), -valid_in_gap[0]["t_start"])
                        if best_lower_score is None or score > best_lower_score:
                            best_lower_score = score
                            best_lower_ch = ch

            if best_lower_ch is not None:
                active_ch = best_lower_ch
                advance_past(active_ch, last_end)
                nxt = peek(active_ch)
                if nxt is not None and not _has_overlap(nxt, last, overlap_eps):
                    selected.append(dict(nxt))
                    idx[active_ch] += 1
                    continue

        # 5. Caso contrário, permanece no canal ativo e avança para sua próxima nota
        if next_act is None:
            break

        # Verifica se na volta de next_act existe nota simultânea/overlap ainda mais aguda em outro canal
        sim_cands = [next_act]
        for ch in ch_lists:
            if ch == active_ch:
                continue
            c = peek(ch)
            while c is not None and c["t_start"] < next_act["t_start"] - overlap_eps and not _has_overlap(c, next_act, overlap_eps):
                idx[ch] += 1
                c = peek(ch)
            if c is not None and _has_overlap(c, next_act, overlap_eps):
                sim_cands.append(c)

        best_next = max(sim_cands, key=lambda n: (n["note"], n["vel"], -n["t_start"]))
        selected.append(dict(best_next))
        active_ch = best_next["ch"]
        idx[active_ch] += 1

    return selected[:max_notes]


def convert_midi_simple(
    midi_path: str,
    transpose: bool = True,
    as_hex: bool = False,
    direct: bool = False,
) -> List[str]:
    """Converte um `.mid` para linhas de 30 bits. Com `direct=True`, faz conversão direta sem algoritmo de seleção."""
    timed_events = parse_smf_events(midi_path, ignore_drums=True)
    sustained_notes = extract_sustained_notes(timed_events)
    if direct:
        melody = sustained_notes[:MAX_NOTES]
    else:
        melody = select_highest_no_overlap(sustained_notes, max_notes=MAX_NOTES)

    if transpose and melody:
        melody = optimize_transposition_for_7_keys(melody)

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

        if as_hex:
            lines.append(encode_rom_word_hex(pausa_ticks, dur_ticks, vel, note_midi))
        else:
            lines.append(encode_rom_word(pausa_ticks, dur_ticks, vel, note_midi))

    sentinel = "00000000" if as_hex else ("0" * 30)
    lines.append(sentinel)
    return lines


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Conversor simples MIDI -> ROM (canal mais agudo, histerese de 1s + 2s no outro canal)."
    )
    parser.add_argument("midi", help="Caminho do arquivo MIDI (.mid) de entrada")
    parser.add_argument(
        "--out-dir",
        default="music",
        help="Diretório de saída para o .txt (padrão: music)",
    )
    parser.add_argument(
        "--name",
        default=None,
        help="Nome base dos arquivos gerados (padrão: nome do arquivo MIDI)",
    )
    parser.add_argument(
        "--no-transpose",
        action="store_true",
        help="Não transpõe a melodia para otimizar teclas naturais/Oitava 4",
    )
    parser.add_argument(
        "--direct",
        "--direto",
        action="store_true",
        help="Conversão direta MIDI -> ROM sem algoritmo de seleção (ideal para músicas só de piano)",
    )
    args = parser.parse_args()

    out_base: str = args.name or os.path.splitext(os.path.basename(args.midi))[0]
    lines = convert_midi_simple(
        args.midi,
        transpose=not args.no_transpose,
        as_hex=False,
        direct=args.direct,
    )

    out_txt = os.path.join(args.out_dir, f"{out_base}.txt")
    out_mid = os.path.join(args.out_dir, ".mid", f"{out_base}_melodia.mid")

    write_rom_file(out_txt, lines)
    words_to_midi(lines, out_mid)

    active_notes = len(lines) - 1
    print(f"[OK] Gerado {out_txt} ({active_notes} notas) e prévia em {out_mid}")


if __name__ == "__main__":
    main()
