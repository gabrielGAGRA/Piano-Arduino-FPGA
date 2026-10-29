"""
VCD Waveform Trace Analysis Tool

Parses IEEE 1364 Value Change Dump (VCD) files and prints structured,
cycle-accurate signal tables, event logs, ASCII waveforms, and anomaly
diagnostics optimized for reasoning and self-correction.
"""

import sys
import os
import re
import argparse

def parse_time_arg(val_str, timescale_num, timescale_unit):
    """Parses a time string like '100ns', '2us', or '500' into integer simulator time units."""
    if not val_str:
        return None
    val_str = val_str.strip().lower()
    m = re.match(r'^([0-9.]+)\s*([a-z]*)$', val_str)
    if not m:
        try:
            return int(val_str)
        except ValueError:
            return None
    num = float(m.group(1))
    unit = m.group(2)
    if not unit:
        return int(num)

    unit_scales = {
        's': 1.0,
        'ms': 1e-3,
        'us': 1e-6,
        'ns': 1e-9,
        'ps': 1e-12,
        'fs': 1e-15
    }

    base_scale = unit_scales.get(timescale_unit, 1e-9) * timescale_num
    target_scale = unit_scales.get(unit, 1e-9)
    # Convert target time in seconds to ticks
    time_sec = num * target_scale
    ticks = int(round(time_sec / base_scale))
    return ticks

def format_time(ticks, timescale_num, timescale_unit):
    """Formats simulator ticks into human-readable string with units."""
    scaled = ticks * timescale_num
    return f"{scaled:g}{timescale_unit}"

class VCDParser:
    def __init__(self, filename):
        self.filename = filename
        self.timescale_num = 1
        self.timescale_unit = 'ns'
        self.id_to_var = {} # id -> {'name': str, 'full_name': str, 'size': int, 'type': str}
        self.var_to_id = {} # full_name -> id, name -> id
        self.timestamps = [] # list of ticks
        self.changes = {} # tick -> {id: value}
        self.all_ids = set()

    def parse(self):
        if not os.path.exists(self.filename):
            raise FileNotFoundError(f"VCD file not found: {self.filename}")

        with open(self.filename, 'r', errors='ignore') as f:
            scope_stack = []
            in_header = True
            current_time = 0

            for line in f:
                line = line.strip()
                if not line:
                    continue

                if in_header:
                    if line.startswith('$timescale'):
                        tokens = line.split()
                        ts_str = ""
                        if len(tokens) >= 2 and tokens[1] != '$end':
                            ts_str = tokens[1]
                        elif len(tokens) >= 3 and tokens[2] != '$end':
                            ts_str = tokens[1] + tokens[2]
                        m = re.search(r'([0-9]+)\s*([a-zA-Z]+)', ts_str)
                        if m:
                            self.timescale_num = int(m.group(1))
                            self.timescale_unit = m.group(2).lower()
                    elif line.startswith('$scope'):
                        parts = line.split()
                        if len(parts) >= 3:
                            scope_stack.append(parts[2])
                    elif line.startswith('$upscope'):
                        if scope_stack:
                            scope_stack.pop()
                    elif line.startswith('$var'):
                        parts = line.split()
                        if len(parts) >= 5:
                            var_type = parts[1]
                            var_size = int(parts[2])
                            var_id = parts[3]
                            var_name = parts[4]
                            full_name = ".".join(scope_stack + [var_name])
                            info = {
                                'name': var_name,
                                'full_name': full_name,
                                'size': var_size,
                                'type': var_type,
                                'id': var_id
                            }
                            self.id_to_var[var_id] = info
                            self.all_ids.add(var_id)
                            self.var_to_id[full_name] = var_id
                            if var_name not in self.var_to_id:
                                self.var_to_id[var_name] = var_id
                    elif line.startswith('$enddefinitions'):
                        in_header = False
                        self.changes[0] = {}
                    continue

                # Body parsing
                if line.startswith('#'):
                    try:
                        current_time = int(line[1:])
                        if current_time not in self.changes:
                            self.changes[current_time] = {}
                            self.timestamps.append(current_time)
                    except ValueError:
                        pass
                elif line.startswith(('0', '1', 'x', 'X', 'z', 'Z')):
                    # Scalar change: <val><id>
                    val = line[0].lower()
                    var_id = line[1:].strip()
                    if var_id in self.id_to_var:
                        self.changes[current_time][var_id] = val
                elif line.startswith(('b', 'B', 'r', 'R')):
                    # Vector change: b<val> <id>
                    parts = line[1:].split()
                    if len(parts) == 2:
                        val = parts[0].lower()
                        var_id = parts[1]
                        if var_id in self.id_to_var:
                            self.changes[current_time][var_id] = val
                elif line.startswith('$dumpvars'):
                    pass
                elif line.startswith('$end'):
                    pass

        if not self.timestamps and self.changes:
            self.timestamps = sorted(self.changes.keys())
        else:
            self.timestamps = sorted(list(set(self.timestamps)))

    def resolve_signal_id(self, sig_name):
        """Resolves a signal name, full name, or wildcard to var_id."""
        sig_name = sig_name.strip()
        if sig_name in self.var_to_id:
            return self.var_to_id[sig_name]
        matches = []
        for full_name, vid in self.var_to_id.items():
            if full_name.lower() == sig_name.lower() or full_name.endswith('.' + sig_name):
                matches.append(vid)
        if matches:
            return matches[0]
        return None

def format_val(val_str, size=1, radix='hex'):
    """Formats raw VCD value strings into clean readable strings."""
    if val_str is None:
        return "?"
    if 'x' in val_str:
        return "x" if size == 1 else f"x[{val_str}]"
    if 'z' in val_str:
        return "z" if size == 1 else f"z[{val_str}]"

    if size == 1:
        return val_str

    try:
        num = int(val_str, 2)
        if radix == 'hex':
            hex_chars = (size + 3) // 4
            return f"0x{num:0{hex_chars}X}"
        elif radix == 'dec':
            return str(num)
        elif radix == 'bin':
            return f"{num:0{size}b}"
    except ValueError:
        pass
    return val_str

def generate_trace_table(vcd, sig_ids, clock_id=None, start_tick=None, end_tick=None, max_cycles=50, radix='hex', changes_only=False):
    """Builds a cycle-by-cycle tabular trace or event table for LLM analysis."""
    timeline_ticks = vcd.timestamps
    if not timeline_ticks:
        return "No simulation time events found in VCD."

    if start_tick is not None:
        timeline_ticks = [t for t in timeline_ticks if t >= start_tick]
    if end_tick is not None:
        timeline_ticks = [t for t in timeline_ticks if t <= end_tick]

    current_state = {vid: 'x' for vid in sig_ids}
    if clock_id and clock_id not in sig_ids:
        current_state[clock_id] = 'x'

    tick_states = {}
    clock_edges = []

    all_ticks_sorted = sorted(vcd.changes.keys())
    for t in all_ticks_sorted:
        for vid, val in vcd.changes[t].items():
            if vid in current_state:
                old_val = current_state[vid]
                current_state[vid] = val
                if vid == clock_id and old_val != val:
                    if old_val == '0' and val == '1':
                        clock_edges.append((t, 'pos'))
                    elif old_val == '1' and val == '0':
                        clock_edges.append((t, 'neg'))
        if t in timeline_ticks:
            tick_states[t] = dict(current_state)

    lines = []
    headers = ["Cycle", f"Time({vcd.timescale_unit})"] + [vcd.id_to_var[vid]['name'] for vid in sig_ids]

    if clock_id and not changes_only:
        sampled_rows = []
        cycle_idx = 0
        prev_row_vals = None

        for t, edge in clock_edges:
            if start_tick is not None and t < start_tick:
                continue
            if end_tick is not None and t > end_tick:
                break
            if edge != 'pos':
                continue

            state_at_t = tick_states.get(t, {})
            row_vals = []
            for vid in sig_ids:
                val = format_val(state_at_t.get(vid, '?'), vcd.id_to_var[vid]['size'], radix)
                row_vals.append(val)

            delta_mark = ""
            if prev_row_vals is not None:
                changed = [vcd.id_to_var[vid]['name'] for i, vid in enumerate(sig_ids) if row_vals[i] != prev_row_vals[i]]
                if changed:
                    delta_mark = " *"
            prev_row_vals = row_vals

            time_str = f"{t * vcd.timescale_num:g}"
            sampled_rows.append([str(cycle_idx) + delta_mark, time_str] + row_vals)
            cycle_idx += 1
            if max_cycles and cycle_idx >= max_cycles:
                break

        if not sampled_rows:
            return "No clock active edges detected in the selected time window."

        lines.append(f"### Cycle-Accurate Trace Table (Sampled on posedge `{vcd.id_to_var[clock_id]['name']}`)")
        lines.append(f"*Note: Asterisk (*) in Cycle column marks signals changing in that cycle.*")
        col_widths = [len(h) for h in headers]
        for r in sampled_rows:
            for i, val in enumerate(r):
                col_widths[i] = max(col_widths[i], len(val))

        header_str = "| " + " | ".join(headers[i].ljust(col_widths[i]) for i in range(len(headers))) + " |"
        sep_str = "|-" + "-|-".join("-" * col_widths[i] for i in range(len(headers))) + "-|"
        lines.append(header_str)
        lines.append(sep_str)
        for r in sampled_rows:
            row_str = "| " + " | ".join(r[i].ljust(col_widths[i]) for i in range(len(r))) + " |"
            lines.append(row_str)

        if max_cycles and len(clock_edges) > max_cycles:
            lines.append(f"\n*(Showing first {max_cycles} cycles. Use --max-cycles 0 for all or --start/--end to narrow window)*")

    else:
        headers = [f"Time({vcd.timescale_unit})", "Signal", "Old -> New Value"]
        event_rows = []
        prev_vals = {vid: 'x' for vid in sig_ids}

        for t in timeline_ticks:
            chg = vcd.changes.get(t, {})
            for vid in sig_ids:
                if vid in chg:
                    old_v = format_val(prev_vals[vid], vcd.id_to_var[vid]['size'], radix)
                    new_v = format_val(chg[vid], vcd.id_to_var[vid]['size'], radix)
                    if old_v != new_v:
                        time_str = f"{t * vcd.timescale_num:g}"
                        event_rows.append([time_str, vcd.id_to_var[vid]['name'], f"{old_v} -> {new_v}"])
                    prev_vals[vid] = chg[vid]
            if max_cycles and len(event_rows) >= max_cycles:
                break

        lines.append("### Signal Event Log (Transitions Only)")
        if not event_rows:
            lines.append("No value transitions detected for selected signals.")
        else:
            col_widths = [len(h) for h in headers]
            for r in event_rows:
                for i, val in enumerate(r):
                    col_widths[i] = max(col_widths[i], len(val))
            lines.append("| " + " | ".join(headers[i].ljust(col_widths[i]) for i in range(len(headers))) + " |")
            lines.append("|-" + "-|-".join("-" * col_widths[i] for i in range(len(headers))) + "-|")
            for r in event_rows:
                lines.append("| " + " | ".join(r[i].ljust(col_widths[i]) for i in range(len(r))) + " |")

    return "\n".join(lines)

def generate_ascii_waveforms(vcd, sig_ids, start_tick=None, end_tick=None, width=50):
    """Generates a compact ASCII waveform for 1-bit flags."""
    lines = ["### ASCII Waveform Tracks"]
    ticks = vcd.timestamps
    if not ticks:
        return ""
    t_min = ticks[0] if start_tick is None else start_tick
    t_max = ticks[-1] if end_tick is None else end_tick
    duration = t_max - t_min
    if duration <= 0:
        return "Duration too short for ASCII waveform."

    step = duration / width
    for vid in sig_ids:
        var = vcd.id_to_var[vid]
        if var['size'] != 1:
            continue

        wave_chars = []
        for i in range(width):
            sample_time = t_min + int(i * step)
            val = 'x'
            for t in sorted(vcd.changes.keys()):
                if t > sample_time:
                    break
                if vid in vcd.changes[t]:
                    val = vcd.changes[t][vid]
            if val == '1':
                wave_chars.append('‾')
            elif val == '0':
                wave_chars.append('_')
            else:
                wave_chars.append('x')
        track = "".join(wave_chars)
        lines.append(f"{var['name'].ljust(16)}: {track}")

    lines.append(f"Time scale: {format_time(t_min, vcd.timescale_num, vcd.timescale_unit)} to {format_time(t_max, vcd.timescale_num, vcd.timescale_unit)}")
    return "\n".join(lines)

def detect_anomalies(vcd, sig_ids, start_tick=None, end_tick=None):
    """Scans for 'x' or 'z' states and reports active warnings."""
    anomalies = []
    for vid in sig_ids:
        var = vcd.id_to_var[vid]
        x_times = []
        z_times = []
        for t in sorted(vcd.changes.keys()):
            if start_tick is not None and t < start_tick:
                continue
            if end_tick is not None and t > end_tick:
                break
            if vid in vcd.changes[t]:
                v = vcd.changes[t][vid]
                if 'x' in v:
                    x_times.append(t)
                if 'z' in v:
                    z_times.append(t)

        if x_times:
            t_first = format_time(x_times[0], vcd.timescale_num, vcd.timescale_unit)
            t_last = format_time(x_times[-1], vcd.timescale_num, vcd.timescale_unit)
            anomalies.append(f"- **UNKNOWN ('x') on `{var['name']}`**: present between {t_first} and {t_last} ({len(x_times)} events).")
        if z_times:
            t_first = format_time(z_times[0], vcd.timescale_num, vcd.timescale_unit)
            t_last = format_time(z_times[-1], vcd.timescale_num, vcd.timescale_unit)
            anomalies.append(f"- **HIGH-IMPEDANCE ('z') on `{var['name']}`**: present between {t_first} and {t_last}.")

    if not anomalies:
        return "✓ No 'x' or 'z' anomalies detected on selected signals."
    return "### Signal Diagnostic Anomalies Detected:\n" + "\n".join(anomalies)

def main():
    parser = argparse.ArgumentParser(description="LLM-Optimized VCD Waveform Trace Analysis Tool")
    parser.add_argument("vcd_file", help="Path to the .vcd file to analyze")
    parser.add_argument("--signals", "-s", help="Comma-separated list of signals to trace (e.g. clock,reset,state,saida)")
    parser.add_argument("--clock", "-c", help="Clock signal name for synchronous edge sampling (e.g. clock, clk)")
    parser.add_argument("--start", help="Start time (e.g. 0, 40ns, 1us)")
    parser.add_argument("--end", help="End time (e.g. 500ns, 2us)")
    parser.add_argument("--max-cycles", "-n", type=int, default=50, help="Maximum number of cycles or rows to display (default: 50, 0 for unlimited)")
    parser.add_argument("--radix", choices=['hex', 'dec', 'bin'], default='hex', help="Number base for multi-bit buses (default: hex)")
    parser.add_argument("--events", action="store_true", help="Display signal change event log instead of clock table")
    parser.add_argument("--ascii", action="store_true", help="Include ASCII waveform tracks for 1-bit flags")
    parser.add_argument("--list-signals", action="store_true", help="List all available signals in the VCD and exit")

    args = parser.parse_args()

    vcd = VCDParser(args.vcd_file)
    try:
        vcd.parse()
    except Exception as e:
        print(f"Error parsing VCD file '{args.vcd_file}': {e}", file=sys.stderr)
        sys.exit(1)

    if args.list_signals:
        print(f"Available signals in '{args.vcd_file}':")
        for vid, info in sorted(vcd.id_to_var.items(), key=lambda x: x[1]['full_name']):
            print(f"  {info['full_name']} ({info['type']} [{info['size']}-bit])")
        sys.exit(0)

    start_tick = parse_time_arg(args.start, vcd.timescale_num, vcd.timescale_unit)
    end_tick = parse_time_arg(args.end, vcd.timescale_num, vcd.timescale_unit)

    sig_ids = []
    if args.signals:
        for s in args.signals.split(','):
            vid = vcd.resolve_signal_id(s)
            if vid:
                if vid not in sig_ids:
                    sig_ids.append(vid)
            else:
                print(f"Warning: Signal '{s}' not found in VCD file.", file=sys.stderr)
    else:
        top_sigs = list(vcd.id_to_var.keys())[:12]
        sig_ids = top_sigs

    if not sig_ids:
        print("No valid signals selected. Use --list-signals to see available signals.", file=sys.stderr)
        sys.exit(1)

    clock_id = None
    if args.clock:
        clock_id = vcd.resolve_signal_id(args.clock)
    elif not args.events:
        for candidate in ['clock', 'clk', 'clock_in', 'clk_in', 'dut.clock']:
            cid = vcd.resolve_signal_id(candidate)
            if cid and vcd.id_to_var[cid]['size'] == 1:
                clock_id = cid
                break

    # 1. Anomaly Report
    print(detect_anomalies(vcd, sig_ids, start_tick, end_tick))
    print()

    # 2. Main Trace Table / Event Log
    print(generate_trace_table(
        vcd,
        sig_ids,
        clock_id=clock_id,
        start_tick=start_tick,
        end_tick=end_tick,
        max_cycles=args.max_cycles,
        radix=args.radix,
        changes_only=args.events
    ))

    # 3. Optional ASCII waveform
    if args.ascii:
        print()
        print(generate_ascii_waveforms(vcd, sig_ids, start_tick, end_tick))

if __name__ == "__main__":
    main()
