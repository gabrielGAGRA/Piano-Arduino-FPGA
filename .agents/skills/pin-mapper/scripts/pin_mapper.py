import argparse
import csv
import re
import sys
from pathlib import Path

CSV_PATH = Path(__file__).resolve().parent.parent / "resources" / "de0_cv_pins.csv"


def load_pins():
    db = {}
    with open(CSV_PATH, "r", encoding="utf-8") as f:
        reader = csv.reader(f)
        next(reader, None)  # header
        for row in reader:
            if len(row) >= 2:
                sig, pin = row[0].strip(), row[1].strip()
                db[sig] = pin
                db[sig.lower()] = pin

                # Automatically expand common alias formats
                m_hex = re.match(r"^HEX(\d)(\d)$", sig)
                if m_hex:
                    d, s = m_hex.group(1), m_hex.group(2)
                    db[f"hex{d}[{s}]"] = pin
                    db[f"HEX{d}[{s}]"] = pin

                m_sw = re.match(r"^SW(\d+)$", sig)
                if m_sw:
                    idx = m_sw.group(1)
                    db[f"sw[{idx}]"] = pin
                    db[f"SW[{idx}]"] = pin

                m_key = re.match(r"^KEY(\d+)$", sig)
                if m_key:
                    idx = m_key.group(1)
                    db[f"key[{idx}]"] = pin
                    db[f"KEY[{idx}]"] = pin

                m_led = re.match(r"^LEDR(\d+)$", sig)
                if m_led:
                    idx = m_led.group(1)
                    db[f"ledr[{idx}]"] = pin
                    db[f"LEDR[{idx}]"] = pin

                m_gpio = re.match(r"^GPIO_(\d)_D(\d+)$", sig)
                if m_gpio:
                    g, idx = m_gpio.group(1), m_gpio.group(2)
                    db[f"gpio_{g}[{idx}]"] = pin
                    db[f"GPIO_{g}[{idx}]"] = pin

    # Generic clock aliases
    if "CLOCK_50" in db:
        clk_pin = db["CLOCK_50"]
        db["clock"] = clk_pin
        db["clk"] = clk_pin

    return db


def parse_top_ports(verilog_path):
    code = Path(verilog_path).read_text(encoding="utf-8", errors="replace")
    code = re.sub(r"//.*", "", code)
    code = re.sub(r"/\*.*?\*/", "", code, flags=re.DOTALL)

    mod_match = re.search(r"\bmodule\s+\w+\s*(?:#\s*\([^)]*\))?\s*\((.*?)\)\s*;", code, re.DOTALL)
    if not mod_match:
        return []

    port_pattern = re.compile(
        r"\b(input|output|inout)\b\s*(?:(?:wire|reg)\s*)?(?:\[\s*(\d+)\s*:\s*(\d+)\s*\])?\s*(\w+)"
    )

    nodes = []
    for match in port_pattern.finditer(mod_match.group(1)):
        msb, lsb, name = match.group(2), match.group(3), match.group(4)
        if msb is not None and lsb is not None:
            start, end = min(int(msb), int(lsb)), max(int(msb), int(lsb))
            for i in range(start, end + 1):
                nodes.append(f"{name}[{i}]")
        else:
            nodes.append(name)
    return nodes


def main():
    parser = argparse.ArgumentParser(description="Output plain-text FPGA pin column sorted alphabetically")
    parser.add_argument("-t", "--top", help="Path to top-level Verilog file")
    parser.add_argument("-n", "--nodes", nargs="*", help="List of node names")
    parser.add_argument("-m", "--map", help="Mapping overrides (e.g. 'trigger=GPIO_1_D1,echo=GPIO_1_D3')")

    args = parser.parse_args()
    pins_db = load_pins()

    overrides = {}
    if args.map:
        for pair in args.map.split(","):
            if "=" in pair:
                k, v = pair.split("=", 1)
                overrides[k.strip().lower()] = v.strip()

    nodes = []
    if args.top:
        nodes = parse_top_ports(args.top)
    elif args.nodes:
        nodes = args.nodes
    elif not sys.stdin.isatty():
        nodes = [line.strip() for line in sys.stdin if line.strip()]
    else:
        print("Usage: python pin_mapper.py --top <top.v> [--map 'k=v,...']", file=sys.stderr)
        sys.exit(1)

    # Sort alphabetically (matching Quartus Pin Planner order)
    nodes.sort(key=lambda x: x.lower())

    for node in nodes:
        key = node.lower()
        if key in overrides:
            target = overrides[key]
            pin = pins_db.get(target, pins_db.get(target.lower(), target))
        else:
            pin = pins_db.get(key, pins_db.get(node, "PIN_UNASSIGNED"))
        print(pin)


if __name__ == "__main__":
    main()
