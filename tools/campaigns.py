#!/usr/bin/env python3
"""Parse the three `.CAM` campaign files — single player's whole structure.

`RES/*.CAM` is the only place on the disc that says what single-player mode
is. Each line is one stage: which level's art, which scheme's layout, and how
many rovers, ghosts and AI bombermen to put on it, at what speed. `BM95.EXE`
loads them by scanning for `*.cam` (the pattern is at 0x45805F) and reports
"Total of %u campaigns loaded", so the count is not fixed at three — a copy of
the disc with a fourth would get a fourth campaign, and this tool reads
whatever is there.

The file states its own field order in a header comment, which is quoted here
because it is the whole specification:

    0. campaign name        4. rover speed          8. AI difficulty (unused)
    1. levelno              5. number of ghosts
    2. scheme to use        6. ghost speed
    3. number of rovers     7. number of AIs

    -C,<name>,<level>,<scheme>,<rovers>,<rspeed>,<ghosts>,<gspeed>,<ais>,<diff>

Speeds are VALUELST's own unit — hundredths of a pixel per frame, so 150 is
1.5 px/frame — which is why a ghost at 150 and a rover at 500 are not a typo.

WHAT THIS CHECKS, beyond parsing. A campaign that names a scheme the disc does
not ship, or a level number outside 0..10, is a stage the port would fail on
at the moment a player reached it, which is the worst time to find out. Both
are resolved here against `SCHEMES/` and the eleven levels, at build time.

    tools/campaigns.py              parse all, report, write JSON
    tools/campaigns.py --check      parse only, write nothing
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

LEVEL_COUNT = 11

# MESSAGES.TXT 150-160, in order — the level a stage's `levelno` selects.
LEVEL_NAMES = [
    "Green Acres", "Classic Green Acres", "The Hockey Rink", "Ancient Egypt",
    "The Coal Mine", "The Beach", "Aliens", "Haunted House",
    "Under the Ocean", "Deep Forest Green", "Inner City Trash",
]

FIELDS = ["name", "level", "scheme", "rovers", "rover_speed",
          "ghosts", "ghost_speed", "ais", "difficulty"]


class ParseError(Exception):
    pass


def parse(text: str, label: str = "<text>") -> dict:
    """One campaign: a list of stages, in play order."""
    stages: list[dict] = []

    for lineno, raw in enumerate(text.splitlines(), start=1):
        line = raw.replace("\x1a", "")
        head, _, _comment = line.partition(";")
        head = head.strip()
        if not head:
            continue
        if not head.startswith("-C"):
            raise ParseError(f"line {lineno}: expected -C, got {raw.strip()!r}")

        f = [p.strip() for p in head.split(",")]
        # -C plus nine fields. The name may not contain a comma; none on the
        # disc does, and allowing one would make the field count ambiguous.
        if len(f) != 10:
            raise ParseError(f"line {lineno}: -C wants 9 fields, got {len(f) - 1}")

        stage = {"name": f[1]}
        try:
            stage["level"] = int(f[2])
            stage["scheme"] = f[3].upper()
            stage["rovers"] = int(f[4])
            stage["rover_speed"] = int(f[5])
            stage["ghosts"] = int(f[6])
            stage["ghost_speed"] = int(f[7])
            stage["ais"] = int(f[8])
            stage["difficulty"] = int(f[9])
        except ValueError as exc:
            raise ParseError(f"line {lineno}: {exc}") from None

        if not 0 <= stage["level"] < LEVEL_COUNT:
            raise ParseError(f"line {lineno}: level {stage['level']} is outside "
                             f"0..{LEVEL_COUNT - 1}")
        # A stage with nothing on it can never be won, so it is a data error
        # rather than a quiet oddity.
        if stage["rovers"] + stage["ghosts"] + stage["ais"] == 0:
            raise ParseError(f"line {lineno}: stage {stage['name']!r} has no "
                             "opponents at all")
        stage["level_name"] = LEVEL_NAMES[stage["level"]]
        stages.append(stage)

    if not stages:
        raise ParseError("no -C stages")
    return {"label": label, "stages": stages}


def main(argv: list[str]) -> int:
    root = Path(__file__).resolve().parent.parent

    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--data", type=Path, default=root / "original-game")
    ap.add_argument("--check", action="store_true", help="parse only, write nothing")
    args = ap.parse_args(argv)

    res_dir = args.data / "RES"
    files = sorted(res_dir.glob("*.CAM"))
    if not files:
        print(f"campaigns: no .CAM files in {res_dir}", file=sys.stderr)
        return 2

    have_schemes = {p.stem.upper()
                    for p in (args.data / "SCHEMES").glob("*.SCH")}

    campaigns: dict[str, dict] = {}
    problems = 0
    for src in files:
        stem = src.stem.upper()
        try:
            campaigns[stem] = parse(src.read_text(encoding="latin-1"), stem)
        except ParseError as exc:
            print(f"campaigns: {src.name}: {exc}", file=sys.stderr)
            problems += 1
            continue

        stages = campaigns[stem]["stages"]
        missing = sorted({s["scheme"] for s in stages} - have_schemes)
        if missing:
            print(f"campaigns: {src.name}: names schemes the disc does not "
                  f"ship: {', '.join(missing)}", file=sys.stderr)
            problems += 1

        levels = sorted({s["level"] for s in stages})
        rovers = sum(s["rovers"] for s in stages)
        ghosts = sum(s["ghosts"] for s in stages)
        ais = sum(s["ais"] for s in stages)
        print(f"campaigns: {stem:<9} {len(stages):>2} stages  "
              f"levels {levels}  {rovers} rovers, {ghosts} ghosts, {ais} AIs")

    if problems:
        return 1

    total = sum(len(c["stages"]) for c in campaigns.values())
    used = sorted({s["scheme"] for c in campaigns.values() for s in c["stages"]})
    print(f"\ncampaigns: {len(campaigns)} campaigns, {total} stages, "
          f"{len(used)} distinct schemes used of {len(have_schemes)} on the disc")

    if args.check:
        return 0

    out_dir = root / "tools" / "out"
    out_dir.mkdir(parents=True, exist_ok=True)
    dest = out_dir / "campaigns.json"
    dest.write_text(json.dumps(campaigns, indent=1), encoding="utf-8")
    print(f"campaigns: wrote {dest.relative_to(root)}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
