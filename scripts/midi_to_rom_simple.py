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
from typing import Dict, List, Optional

from scripts.midi_to_rom import (
    MAX_NOTES,
    TICK_SECONDS,
    clamp_midi_note,
    encode_rom_word,
    encode_rom_word_hex,
    extract_sustained_notes,
    optimize_transposition_for_7_keys,
    parse_smf_events,
    words_to_midi,
    write_rom_file,
)

OVERLAP_EPS_S = 0.004       # Tolerância de 4 ms (< 1 tick) para bordas encostadas
SILENCE_SWITCH_S = 1.0      # Mínimo de silêncio (s) para trocar para canal mais grave
MIN_SWITCH_DURATION_S = 2.0 # Mínimo de duração (s) no outro canal para validar a troca
MIN_SWITCH_NOTES = 2        # Mínimo de notas no outro canal para validar a troca


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
) -> List[str]:
    """Converte um `.mid` para linhas de 30 bits usando seleção pela nota mais aguda sem overlaps."""
    timed_events = parse_smf_events(midi_path, ignore_drums=True)
    sustained_notes = extract_sustained_notes(timed_events)
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
    args = parser.parse_args()

    out_base: str = args.name or os.path.splitext(os.path.basename(args.midi))[0]
    lines = convert_midi_simple(args.midi, transpose=not args.no_transpose, as_hex=False)

    out_txt = os.path.join(args.out_dir, f"{out_base}.txt")
    out_mid = os.path.join(args.out_dir, ".mid", f"{out_base}_melodia.mid")

    write_rom_file(out_txt, lines)
    words_to_midi(lines, out_mid)

    active_notes = len(lines) - 1
    print(f"[OK] Gerado {out_txt} ({active_notes} notas) e prévia em {out_mid}")


if __name__ == "__main__":
    main()
