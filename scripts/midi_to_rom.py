"""
Pré-processador de arquivos MIDI (.mid) para memórias ROM de 30 bits x 1024 palavras
do Piano FPGA (Modo Aprendizado e Modo Demonstração).

Formato de cada palavra de 30 bits (em binário ASCII ou hex, 1024 linhas por arquivo):
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
MAX_NOTES = ROM_DEPTH - 1  # Reserva pelo menos o último endereço com 30'd0 (fim_musica)
CHORD_WINDOW_S = 0.024     # Janela de 24 ms para agrupar acordes simultâneos
MIN_PLAYABLE_IOI_S = 0.095 # Limite mínimo para evitar notas que se atropelam no ritmo pop


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

                # Filtro de canais: ignora percussão e restringe a canais permitidos
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


def filter_pop_melody(
    notes: List[Dict],
    min_ioi_s: float = MIN_PLAYABLE_IOI_S,
    max_notes: int = MAX_NOTES,
) -> List[Dict]:
    """
    Filtra notas de acompanhamento/baixo e notas sobrepostas para extrair
    apenas a melodia principal tocável em estilo pop:
    1. Agrupa acordes simultâneos (24 ms) e escolhe a nota mais aguda.
    2. Descarta notas de contratempo que iniciam sob sustentação de nota melódica mais aguda (held-note masking).
    3. Descarta notas no registro grave de baixo (< 50 quando o registro melódico é superior).
    4. Anti-atropelo rítmico: quando notas se atropelam (< min_ioi_s), mantém a nota estrutural mais longa/forte.
    """
    if not notes:
        return []

    # 1. Agrupamento em acordes simultâneos e extração de skyline
    clusters: List[List[Dict]] = []
    for n in notes:
        if clusters and (n["t_start"] - clusters[-1][0]["t_start"]) < CHORD_WINDOW_S:
            clusters[-1].append(n)
        else:
            clusters.append([n])

    skyline = [max(c, key=lambda x: (x["note"], x["vel"])) for c in clusters]

    # Mediana do skyline superior para detectar registro melódico vs baixo
    pitches = sorted([n["note"] for n in skyline])
    median_pitch = pitches[len(pitches) // 2] if pitches else 60

    # 2 e 3. Held-note masking + Filtro de linha de baixo
    filtered: List[Dict] = []
    active_high: Optional[Dict] = None

    for n in skyline:
        # Mascaramento por nota sustentada
        if active_high is not None and n["t_start"] < (active_high["t_end_effective"] - 0.025):
            if n["note"] < active_high["note"]:
                continue

        # Filtro de baixo em pausas da melodia
        if median_pitch >= 58:
            if n["note"] < 50 or (median_pitch - n["note"]) > 16:
                continue

        filtered.append(dict(n))
        active_high = n

    # 4. Anti-atropelo rítmico (Playable IOI)
    cleaned: List[Dict] = []
    for n in filtered:
        if not cleaned:
            cleaned.append(n)
            continue

        prev = cleaned[-1]
        dt = n["t_start"] - prev["t_start"]

        if dt < min_ioi_s:
            # Notas muito próximas: escolhe a nota mais longa ou de maior velocity
            prev_dur = prev["t_end_effective"] - prev["t_start"]
            cur_dur = n["t_end_effective"] - n["t_start"]
            if (cur_dur * n["vel"]) > (prev_dur * prev["vel"]):
                cleaned[-1] = n
        else:
            cleaned.append(n)

        if len(cleaned) >= max_notes:
            break

    return cleaned[:max_notes]


def stabilize_pop_octaves(melody: List[Dict]) -> List[Dict]:
    """
    Estabiliza as oitavas da melodia por seção (Viterbi com histerese):
    1. Transposição ótima (-6..+6 semitons) minimizando trocas de oitava (C..B) e favorecendo notas naturais.
    2. Programação dinâmica mantendo a nota musical exata (pitch % 12) e penalizando trocas rápidas
       de oitava em sequências curtas (< 6 notas), evitando saltos constantes de oitava.
    """
    if not melody:
        return melody

    # 1. Transposição ótima consciente de oitava
    best_shift = 0
    best_score = -1e9

    for shift in range(-6, 7):
        shifted_pitches = [n["note"] + shift for n in melody]
        nats = sum(1 for p in shifted_pitches if (p % 12) in (0, 2, 4, 5, 7, 9, 11))
        oct_crossings = sum(
            1 for i in range(len(shifted_pitches) - 1)
            if (shifted_pitches[i] // 12) != (shifted_pitches[i + 1] // 12)
        )
        # Score ponderado: prioriza reduzir trocas de oitava mantendo boa tocabilidade
        score = (nats * 1.0) - (oct_crossings * 2.5)
        if score > best_score:
            best_score = score
            best_shift = shift

    # Transpõe por oitavas inteiras para centrar na Oitava 4 (60..71)
    shifted_notes = [n["note"] + best_shift for n in melody]
    mean_pitch = sum(shifted_notes) / len(shifted_notes)
    octave_shift = 0
    while (mean_pitch + octave_shift) < 60:
        octave_shift += 12
    while (mean_pitch + octave_shift) > 71:
        octave_shift -= 12
    total_shift = best_shift + octave_shift

    pre_transposed = []
    for n in melody:
        nc = dict(n)
        nc["note"] = clamp_midi_note(n["note"] + total_shift)
        pre_transposed.append(nc)

    # 2. Viterbi com Histerese de Oitava
    K = 6  # Mínimo de notas na mesma oitava antes de tolerar mudança confortável
    octaves = [3, 4, 5, 6, 7]
    INF = 1e18

    dp = {(o, r): INF for o in octaves for r in range(1, K + 1)}
    parent: Dict[Tuple[int, int, int], Tuple[int, int]] = {}

    p0 = pre_transposed[0]["note"]
    pc0 = p0 % 12
    for o in octaves:
        cand_p = o * 12 + pc0
        dp[(o, 1)] = (abs(cand_p - p0) / 12.0) * 1.5

    for i in range(1, len(pre_transposed)):
        p = pre_transposed[i]["note"]
        pc = p % 12
        new_dp = {(o, r): INF for o in octaves for r in range(1, K + 1)}

        for o_prev in octaves:
            for r_prev in range(1, K + 1):
                cost_prev = dp[(o_prev, r_prev)]
                if cost_prev >= INF:
                    continue
                for o_cur in octaves:
                    p_cur = o_cur * 12 + pc
                    c_emit = (abs(p_cur - p) / 12.0) * 1.2 + (abs(o_cur - 5) * 0.15)
                    if o_cur == o_prev:
                        r_cur = min(K, r_prev + 1)
                        c_trans = 0.0
                    else:
                        r_cur = 1
                        short_run_penalty = 8.0 if r_prev < K else 0.0
                        c_trans = 3.5 + short_run_penalty + abs(o_cur - o_prev) * 1.0

                    total = cost_prev + c_emit + c_trans
                    if total < new_dp[(o_cur, r_cur)]:
                        new_dp[(o_cur, r_cur)] = total
                        parent[(i, o_cur, r_cur)] = (o_prev, r_prev)
        dp = new_dp

    best_state = min(dp, key=lambda k: dp[k])
    path_oct = [0] * len(pre_transposed)
    cur_o, cur_r = best_state
    for i in range(len(pre_transposed) - 1, -1, -1):
        path_oct[i] = cur_o
        if i > 0:
            cur_o, cur_r = parent[(i, cur_o, cur_r)]

    stabilized_melody: List[Dict] = []
    for i, n in enumerate(pre_transposed):
        nc = dict(n)
        nc["note"] = clamp_midi_note(path_oct[i] * 12 + (n["note"] % 12))
        stabilized_melody.append(nc)

    return stabilized_melody


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


SONG_CATALOG = [
    "Axel_F",                  # 0
    "Bad_Romance",             # 1
    "Beat_It",                 # 2
    "Careless_Whisper",        # 3
    "Clair_de_Lune",           # 4
    "Clocks",                  # 5
    "Do_Re_Mi_Fa",             # 6
    "Epitafio",                # 7
    "Fukashigi_No_Carte",      # 8
    "Fur_Elise",               # 9
    "Golden",                  # 10
    "Golden_Wind",             # 11
    "Harry_Potter",            # 12
    "Head_Over_Heels",         # 13
    "Hey_Jude",                # 14
    "Homem_Aranha_1900",       # 15
    "Imperial_March",          # 16
    "Interestelar",            # 17
    "Jump_Up_Super_Star",      # 18
    "Korobeiniki",             # 19
    "Lugar_Ao_Sol",            # 20
    "Magnetic",                # 21
    "Mario",                   # 22
    "Minecraft_Sweden",        # 23
    "Moonlight_Sonata_3mvt",   # 24
    "Morning_Flower",          # 25
    "Never_Gonna_Give_You_Up", # 26
    "New_Donk_City",           # 27
    "Numb",                    # 28
    "Pink_Panther",            # 29
    "Radio_Ga_Ga",             # 30
    "Sadness_And_Sorrow",      # 31
    "Super_Idol",              # 32
    "Susanne",                 # 33
    "Sweet_Child_O_Mine",      # 34
    "Take_On_Me",              # 35
    "Trem_Das_Onze",           # 36
    "Undertale_Megalovania",   # 37
    "We_Are_Number_One",       # 38
    "When_Love_Takes_Over",    # 39
    "Wii_Sports",              # 40
    "Zelda_Lost_Woods",        # 41
]

# Configuração com parâmetro classical obrigatório para cada música
SONG_CONFIG: Dict[str, Dict] = {
    "Clair_de_Lune": {
        "files": ["Clair_de_Lune.mid", "debussy-clair-de-lune.mid"],
        "channels": [0],
        "classical": True,
    },
    "Jump_Up_Super_Star": {
        "files": [
            "Super Mario Odyssey - Jump Up Super Star.mid.mid",
            "Super Mario Odyssey - Jump Up Super Star.mid",
            "Jump_Up_Super_Star.mid",
        ],
        "classical": False,
    },
    "New_Donk_City": {
        "files": [
            "[COMPLETE] New Donk City (Super Mario Odyssey).mid",
            "New Donk City.mid",
            "New_Donk_City.mid",
        ],
        "channels": [2],
        "classical": False,
    },
    "Wii_Sports": {
        "files": [
            "Wii Sports Title Screen.mid",
            "Wii_Sports.mid",
        ],
        "exclude_channels": [0, 7, 9, 11, 12],
        "classical": False,
    },
}


def extract_melody_words(
    midi_path: str,
    classical: bool,
    as_hex: bool = True,
    allowed_channels: Optional[List[int]] = None,
    exclude_channels: Optional[List[int]] = None,
) -> List[str]:
    """Extrai as palavras codificadas da melodia respeitando o modo classical (pop vs clássico)."""
    if classical is None:
        raise ValueError("O parâmetro 'classical' é obrigatório (True ou False).")

    timed_events = parse_smf_events(
        midi_path,
        allowed_channels=allowed_channels,
        exclude_channels=exclude_channels,
        ignore_drums=True,
    )
    sustained_notes = extract_sustained_notes(timed_events)

    if classical:
        # Modo clássico: não remove notas, preserva skyline puro e afinação
        melody = select_monophonic_melody(sustained_notes, max_notes=MAX_NOTES)
        melody = optimize_transposition_for_7_keys(melody)
    else:
        # Modo pop: extração da voz principal, remoção de acompanhamento/baixo, anti-atropelo e estabilização de oitavas
        melody = filter_pop_melody(sustained_notes, min_ioi_s=MIN_PLAYABLE_IOI_S, max_notes=MAX_NOTES)
        melody = stabilize_pop_octaves(melody)

    words: List[str] = []
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
            words.append(encode_rom_word_hex(pausa_ticks, dur_ticks, vel, note_midi))
        else:
            words.append(encode_rom_word(pausa_ticks, dur_ticks, vel, note_midi))

    return words


def generate_scale_words(as_hex: bool = True) -> List[str]:
    """Gera palavras da escala Dó Maior (C4..B4) sem padding."""
    scale_notes = [60, 62, 64, 65, 67, 69, 71]
    if as_hex:
        return [encode_rom_word_hex(pausa_ticks=5, dur_ticks=40, velocity=100, note_midi=n) for n in scale_notes]
    return [encode_rom_word(pausa_ticks=5, dur_ticks=40, velocity=100, note_midi=n) for n in scale_notes]


def build_mega_rom(
    music_dir: str = "music",
    verilog_out_dir: str = ".",
    addr_width: int = 14,
) -> Tuple[str, str]:
    """
    Constrói a Mega-ROM contígua `music/partituras.hex` e gera o módulo
    Verilog `tabela_offsets_partituras.v`.
    """
    sentinel_hex = "00000000"
    rom_words: List[str] = [sentinel_hex]  # Endereço 0 é sentinela para slots vazios
    offsets: Dict[int, int] = {}

    sub_mid_dir = os.path.join(music_dir, ".mid")

    for idx, song_name in enumerate(SONG_CATALOG):
        song_words: List[str] = []
        cfg = SONG_CONFIG.get(song_name, {})
        allowed_channels = cfg.get("channels", None)
        exclude_channels = cfg.get("exclude_channels", None)
        classical = cfg.get("classical", None)

        file_names = cfg.get("files", [f"{song_name}.mid", f"{song_name.lower()}.mid"])
        midi_candidates = []
        for fn in file_names:
            midi_candidates.append(os.path.join(music_dir, fn))
            midi_candidates.append(os.path.join(sub_mid_dir, fn))
            midi_candidates.append(os.path.join(sub_mid_dir, "original", fn))
            midi_candidates.append(os.path.join(sub_mid_dir, "1-canal", fn))

        found_midi = next((c for c in midi_candidates if os.path.exists(c)), None)

        if found_midi:
            if classical is None:
                raise ValueError(
                    f"Música '{song_name}' encontrada em {found_midi}, mas o parâmetro 'classical' não foi definido!"
                )
            song_words = extract_melody_words(
                found_midi,
                classical=classical,
                as_hex=True,
                allowed_channels=allowed_channels,
                exclude_channels=exclude_channels,
            )
        elif song_name == "Do_Re_Mi_Fa":
            song_words = generate_scale_words(as_hex=True)

        if song_words:
            start_addr = len(rom_words)
            offsets[idx] = start_addr
            rom_words.extend(song_words)
            rom_words.append(sentinel_hex)
        else:
            offsets[idx] = 0

    hex_path = os.path.join(music_dir, "partituras.hex")
    with open(hex_path, "w", encoding="ascii", newline="\n") as f:
        for w in rom_words:
            f.write(f"{w}\n")

    verilog_path = os.path.join(verilog_out_dir, "tabela_offsets_partituras.v")
    lines_v = [
        "// Descricao: Tabela combinacional de offsets de partituras para a Mega-ROM.",
        f"// Funcionamento: Mapeia o indice da musica (0..{len(SONG_CATALOG)-1}) no endereco base dentro da Mega-ROM.",
        "",
        "`timescale 1ns / 1ps",
        "`default_nettype none",
        "",
        "module tabela_offsets_partituras #(",
        f"  parameter AddrWidth = {addr_width}",
        ")(",
        "  input  wire [5:0]           musica_id,",
        "  output reg  [AddrWidth-1:0] base_addr",
        ");",
        "",
        "  always @* begin",
        "    base_addr = {AddrWidth{1'b0}};",
        "    case (musica_id)",
    ]

    for idx, song_name in enumerate(SONG_CATALOG):
        base_addr = offsets.get(idx, 0)
        lines_v.append(f"      6'd{idx}: base_addr = {addr_width}'d{base_addr}; // {song_name}")

    lines_v.extend([
        "      default: base_addr = {AddrWidth{1'b0}};",
        "    endcase",
        "  end",
        "",
        "endmodule",
        "",
        "`default_nettype wire",
        "",
    ])

    with open(verilog_path, "w", encoding="ascii", newline="\n") as f:
        f.write("\n".join(lines_v))

    return hex_path, verilog_path


def convert_midi_to_rom_lines(
    midi_path: str,
    classical: bool,
    allowed_channels: Optional[List[int]] = None,
    exclude_channels: Optional[List[int]] = None,
    as_hex: bool = False,
) -> List[str]:
    """Converte um arquivo `.mid` nas linhas (binário ou hex) de 30 bits com sentinela."""
    words = extract_melody_words(
        midi_path,
        classical=classical,
        as_hex=as_hex,
        allowed_channels=allowed_channels,
        exclude_channels=exclude_channels,
    )
    sentinel = "00000000" if as_hex else ("0" * 30)
    return words + [sentinel]


def generate_scale_rom_lines(as_hex: bool = False) -> List[str]:
    """Gera uma escala Dó Maior (C4..B4) de 30 bits para `Do_Re_Mi_Fa.txt` com sentinela."""
    scale_words = generate_scale_words(as_hex=as_hex)
    sentinel = "00000000" if as_hex else ("0" * 30)
    return scale_words + [sentinel]


def write_rom_file(path: str, lines: List[str]) -> None:
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    with open(path, "w", encoding="ascii", newline="\n") as f:
        for line in lines:
            f.write(line + "\n")


def words_to_midi(words: List[str], out_mid_path: str) -> None:
    """Exporta uma lista de palavras de 30 bits de volta para um arquivo Standard MIDI File (.mid) tocável."""
    events = bytearray()
    events += b'\x00\xFF\x51\x03\x0F\x42\x40'

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
    events += b'\xFF\x2F\x00'

    header = struct.pack('>4sIHHH', b'MThd', 6, 0, 1, 125)
    track = struct.pack('>4sI', b'MTrk', len(events)) + events

    os.makedirs(os.path.dirname(os.path.abspath(out_mid_path)), exist_ok=True)
    with open(out_mid_path, 'wb') as f:
        f.write(header + track)


def rom_file_to_midi(txt_path: str, out_mid_path: Optional[str] = None) -> str:
    """Lê um arquivo .txt de ROM (binário de 30 bits ou hex) e converte de volta para um arquivo .mid tocável."""
    if out_mid_path is None:
        base, _ = os.path.splitext(txt_path)
        out_mid_path = f"{base}_reconvertido.mid"

    with open(txt_path, "r", encoding="ascii") as f:
        lines = [line.strip() for line in f if line.strip()]

    words_to_midi(lines, out_mid_path)
    return out_mid_path


def main() -> None:
    parser = argparse.ArgumentParser(description="Converte arquivo MIDI (.mid) para ROM de 30 bits do FPGA e vice-versa.")
    parser.add_argument(
        "--midi",
        default=None,
        help="Caminho de arquivo MIDI de entrada específico (opcional)",
    )
    parser.add_argument(
        "--classical",
        type=lambda v: str(v).lower() in ("true", "1", "yes"),
        default=None,
        help="Obrigatório se --midi for usado: especifica se o arquivo é clássico (True) ou pop/tocável (False)",
    )
    parser.add_argument(
        "--from-txt",
        default=None,
        help="Caminho de arquivo .txt da ROM para converter de volta em arquivo .mid",
    )
    parser.add_argument(
        "--out-mid",
        default=None,
        help="Caminho do arquivo .mid de saída ao usar --from-txt (opcional)",
    )
    parser.add_argument(
        "--out-dir",
        default="music",
        help="Diretório de saída das memórias ROM (padrão: music)",
    )
    args = parser.parse_args()

    if args.from_txt is not None:
        mid_file = rom_file_to_midi(args.from_txt, args.out_mid)
        print(f"[OK] Convertido ROM '{args.from_txt}' de volta para MIDI: '{mid_file}'")
        return

    if args.midi is not None:
        if args.classical is None:
            parser.error("O parâmetro --classical (true ou false) é OBRIGATÓRIO ao especificar --midi!")
        print(f"Convertendo arquivo específico: {args.midi} (classical={args.classical})")
        lines = convert_midi_to_rom_lines(args.midi, classical=args.classical, as_hex=False)
        out_base = os.path.splitext(os.path.basename(args.midi))[0]
        out_txt = os.path.join(args.out_dir, f"{out_base}.txt")
        write_rom_file(out_txt, lines)
        out_mid = os.path.join(args.out_dir, ".mid", f"{out_base}_melodia.mid")
        words_to_midi(lines, out_mid)
        print(f"[OK] Gerado {out_txt} e {out_mid}")
        return

    sub_mid_dir = os.path.join(args.out_dir, ".mid")

    scale_bin = generate_scale_rom_lines(as_hex=False)
    write_rom_file(os.path.join(args.out_dir, "Do_Re_Mi_Fa.txt"), scale_bin)
    words_to_midi(scale_bin, os.path.join(sub_mid_dir, "Do_Re_Mi_Fa_escala.mid"))

    converted_individual = []

    for song_name in SONG_CATALOG:
        cfg = SONG_CONFIG.get(song_name, {})
        allowed_channels = cfg.get("channels", None)
        exclude_channels = cfg.get("exclude_channels", None)
        classical = cfg.get("classical", None)

        file_names = cfg.get("files", [f"{song_name}.mid", f"{song_name.lower()}.mid"])
        midi_candidates = []
        for fn in file_names:
            midi_candidates.append(os.path.join(args.out_dir, fn))
            midi_candidates.append(os.path.join(sub_mid_dir, fn))
            midi_candidates.append(os.path.join(sub_mid_dir, "original", fn))
            midi_candidates.append(os.path.join(sub_mid_dir, "1-canal", fn))

        found_midi = next((c for c in midi_candidates if os.path.exists(c)), None)
        if found_midi:
            if classical is None:
                raise ValueError(
                    f"Configuração da música '{song_name}' não define o parâmetro obrigatório 'classical'!"
                )
            lines_bin = convert_midi_to_rom_lines(
                found_midi,
                classical=classical,
                allowed_channels=allowed_channels,
                exclude_channels=exclude_channels,
                as_hex=False,
            )
            out_txt = os.path.join(args.out_dir, f"{song_name}.txt")
            write_rom_file(out_txt, lines_bin)
            active_cnt = sum(1 for ln in lines_bin if int(ln[-7:], 2) != 0)
            converted_individual.append((out_txt, active_cnt))

            out_mid = os.path.join(sub_mid_dir, f"{song_name}_melodia.mid")
            words_to_midi(lines_bin, out_mid)

    hex_path, verilog_path = build_mega_rom(music_dir=args.out_dir, verilog_out_dir=".")

    print(f"[OK] Gerados {len(converted_individual)} arquivos individuais .txt em '{args.out_dir}':")
    for path, cnt in converted_individual:
        print(f"  - {os.path.basename(path)} ({cnt} notas ativas)")
    print(f"[OK] Gerado Mega-ROM: {hex_path} e tabela de offsets: {verilog_path}")


if __name__ == "__main__":
    main()
