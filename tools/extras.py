#!/usr/bin/env python3
"""Parse the original's RES/EXTRA*.RES level-specials files.

Each level that has arrows, conveyors, trampolines or warp gates ships an
EXTRA<n>.RES naming them at exact coordinates. Levels without one have no
specials — except level 7, whose regenerating tiles come from VALUELST
resource 347 rather than from an EXTRA file.

Grammar, as observed across all five files:

    -A,<NSEW>,<x>,<y>               arrow, pushing bombs in that direction
    -C,<NSEW>,<x>,<y>               conveyor cell, carrying in that direction
    -T,<x>,<y>                      trampoline at a fixed cell
    -T,H,H                          trampoline placed at random
    -W,<kind>,<gate>,<x>,<y>,<to>   warp gate <gate> at (x,y), exiting at <to>

Coordinates may be negative, and a negative wraps from the right or bottom
edge, per the comment on VALUELST resource 600:

    (negative numbers wrap around from the right edge/bottom edge of the screen)

so x = -3 on a 15-wide field is column 12, and y = -3 on an 11-tall field is
row 8. This is verified by cross-checking EXTRA4's four warp gates against
fpc_atomic's description of them as a counter-clockwise ring: resolved, they
are the four corners of a rectangle and the ring runs top-left -> bottom-left
-> bottom-right -> top-right.

Emits:
    scripts/core/extras.gd      generated GDScript, consumed by the port
    tools/out/extras.json       same data for the C oracle and Python models

Neither is committed; see tools/valuelist.py's docstring for why.

Usage:
    tools/extras.py [--data DIR] [--check]
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

FIELD_W = 15
FIELD_H = 11

# Which EXTRA file belongs to which level. Levels absent from this map have no
# specials file at all.
LEVELS = {
    2: "EXTRA2.RES",    # The Hockey Rink   — 12 arrows (and 250ms ice, res 452)
    3: "EXTRA3.RES",    # Ancient Egypt     — 44 arrows
    4: "EXTRA4.RES",    # The Coal Mine     — 4 warp gates
    9: "EXTRA9.RES",    # Deep Forest Green — 8 trampolines, 4 of them random
    10: "EXTRA10.RES",  # Inner City Trash  — 32 conveyor cells
}

HEADINGS = {"N": "up", "S": "down", "E": "right", "W": "left"}


class ParseError(Exception):
    pass


def wrap_x(value: int) -> int:
    return value + FIELD_W if value < 0 else value


def wrap_y(value: int) -> int:
    return value + FIELD_H if value < 0 else value


def _check_cell(x: int, y: int, lineno: int) -> None:
    if not (0 <= x < FIELD_W and 0 <= y < FIELD_H):
        raise ParseError(f"line {lineno}: cell ({x}, {y}) is off the field")


def parse(text: str) -> dict:
    """Return {arrows, conveyors, tramps, random_tramps, warps} for one file."""
    arrows: list[dict] = []
    conveyors: list[dict] = []
    tramps: list[dict] = []
    random_tramps = 0
    warps: list[dict] = []

    for lineno, raw in enumerate(text.splitlines(), start=1):
        line = raw.replace("\x1a", "")
        head, _, _comment = line.partition(";")
        head = head.strip()
        if not head:
            continue
        if not head.startswith("-"):
            raise ParseError(f"line {lineno}: expected a -X directive, got {raw.strip()!r}")

        parts = [p.strip() for p in head.split(",")]
        kind = parts[0].upper()

        if kind in ("-A", "-C"):
            if len(parts) != 4:
                raise ParseError(f"line {lineno}: {kind} wants 3 fields, got {len(parts) - 1}")
            heading = parts[1].upper()
            if heading not in HEADINGS:
                raise ParseError(f"line {lineno}: unknown heading {parts[1]!r}")
            x, y = wrap_x(int(parts[2])), wrap_y(int(parts[3]))
            _check_cell(x, y, lineno)
            entry = {"x": x, "y": y, "dir": HEADINGS[heading]}
            (arrows if kind == "-A" else conveyors).append(entry)

        elif kind == "-T":
            if len(parts) != 3:
                raise ParseError(f"line {lineno}: -T wants 2 fields, got {len(parts) - 1}")
            # 'H,H' means "place this one at random", which is how the level
            # reaches 8 trampolines from 4 authored positions.
            if parts[1].upper() == "H" and parts[2].upper() == "H":
                random_tramps += 1
            else:
                x, y = wrap_x(int(parts[1])), wrap_y(int(parts[2]))
                _check_cell(x, y, lineno)
                tramps.append({"x": x, "y": y})

        elif kind == "-W":
            if len(parts) != 6:
                raise ParseError(f"line {lineno}: -W wants 5 fields, got {len(parts) - 1}")
            # parts[1] is a kind/enable flag; every gate in the shipped data
            # uses 1. Carried through rather than dropped, so that a value we
            # have never seen cannot be silently ignored.
            x, y = wrap_x(int(parts[3])), wrap_y(int(parts[4]))
            _check_cell(x, y, lineno)
            warps.append({
                "kind": int(parts[1]),
                "gate": int(parts[2]),
                "x": x,
                "y": y,
                "to": int(parts[5]),
            })

        else:
            raise ParseError(f"line {lineno}: unknown directive {kind!r}")

    # A warp ring that does not close would strand a player, so prove it closes
    # rather than trusting it: every gate reachable, exactly once, from gate 0.
    if warps:
        by_gate = {w["gate"]: w for w in warps}
        if sorted(by_gate) != list(range(len(warps))):
            raise ParseError(f"warp gates are not numbered 0..{len(warps) - 1}: {sorted(by_gate)}")
        seen, gate = [], 0
        while gate not in seen:
            seen.append(gate)
            if warps[gate]["to"] not in by_gate:
                raise ParseError(f"gate {gate} exits to unknown gate {warps[gate]['to']}")
            gate = by_gate[gate]["to"]
        if len(seen) != len(warps):
            raise ParseError(f"warp ring does not visit every gate: {seen}")

    return {
        "arrows": arrows,
        "conveyors": conveyors,
        "tramps": tramps,
        "random_tramps": random_tramps,
        "warps": warps,
    }


def emit_gdscript(levels: dict[int, dict]) -> str:
    lines = [
        "# GENERATED FILE — do not edit.",
        "#",
        "# Produced by tools/extras.py from the original's RES/EXTRA*.RES.",
        "# Regenerate with:  tools/extras.py",
        "#",
        "# Coordinates are already resolved: the source files use negative",
        "# values to wrap from the right/bottom edge, and that is applied here",
        "# so nothing downstream has to know about it.",
        "#",
        "# Levels missing from LEVELS have no specials file. Level 7's",
        "# regenerating tiles are not here — they come from VALUELST resource",
        "# 347 (interval) and 695 (clear radius) instead.",
        "",
        "class_name Extras",
        "",
        "const LEVELS := {",
    ]

    for level in sorted(levels):
        data = levels[level]
        lines.append(f"\t{level}: {{")
        for key in ("arrows", "conveyors", "tramps"):
            items = data[key]
            if not items:
                lines.append(f'\t\t"{key}": [],')
                continue
            lines.append(f'\t\t"{key}": [')
            for item in items:
                if "dir" in item:
                    lines.append(
                        f'\t\t\t{{"x": {item["x"]}, "y": {item["y"]}, '
                        f'"dir": "{item["dir"]}"}},'
                    )
                else:
                    lines.append(f'\t\t\t{{"x": {item["x"]}, "y": {item["y"]}}},')
            lines.append("\t\t],")
        lines.append(f'\t\t"random_tramps": {data["random_tramps"]},')
        if not data["warps"]:
            lines.append('\t\t"warps": [],')
        else:
            lines.append('\t\t"warps": [')
            for w in data["warps"]:
                lines.append(
                    f'\t\t\t{{"gate": {w["gate"]}, "x": {w["x"]}, "y": {w["y"]}, '
                    f'"to": {w["to"]}, "kind": {w["kind"]}}},'
                )
            lines.append("\t\t],")
        lines.append("\t},")

    lines += [
        "}",
        "",
        "",
        "## Specials for a level, or an empty set for the levels that have none.",
        "static func of_level(level: int) -> Dictionary:",
        "\tif LEVELS.has(level):",
        "\t\treturn LEVELS[level]",
        "\treturn {",
        '\t\t"arrows": [], "conveyors": [], "tramps": [],',
        '\t\t"random_tramps": 0, "warps": [],',
        "\t}",
        "",
    ]
    return "\n".join(lines)


def main(argv: list[str]) -> int:
    root = Path(__file__).resolve().parent.parent

    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--data", type=Path, default=root / "original-game")
    ap.add_argument("--check", action="store_true", help="parse only, write nothing")
    args = ap.parse_args(argv)

    levels: dict[int, dict] = {}
    for level, name in sorted(LEVELS.items()):
        src = args.data / "RES" / name
        if not src.is_file():
            print(f"extras: not found: {src}", file=sys.stderr)
            return 2
        try:
            levels[level] = parse(src.read_text(encoding="latin-1"))
        except ParseError as exc:
            print(f"extras: {name}: {exc}", file=sys.stderr)
            return 1
        d = levels[level]
        print(
            f"extras: level {level:>2} {name:<12} "
            f"{len(d['arrows']):>2} arrows, {len(d['conveyors']):>2} conveyors, "
            f"{len(d['tramps'])}+{d['random_tramps']} tramps, "
            f"{len(d['warps'])} warps"
        )

    if args.check:
        return 0

    gd = root / "godot-project" / "scripts" / "core" / "extras.gd"
    gd.parent.mkdir(parents=True, exist_ok=True)
    gd.write_text(emit_gdscript(levels), encoding="utf-8")
    print(f"extras: wrote {gd.relative_to(root)}")

    out = root / "tools" / "out"
    out.mkdir(parents=True, exist_ok=True)
    js = out / "extras.json"
    js.write_text(json.dumps({str(k): v for k, v in sorted(levels.items())}, indent=1),
                  encoding="utf-8")
    print(f"extras: wrote {js.relative_to(root)}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
