#!/usr/bin/env python3
"""Parse the 67 `.SCH` scheme files — the maps — into structured data.

A scheme is the original's level layout: a 15x11 grid of solid/brick/blank,
ten player starts with team assignments, a brick density, and a thirteen-entry
powerup table saying what each player is born with and what the field may
spawn. `SCHEMES/*.SCH` is where every arena in the game comes from, and the
port reads them at runtime through `scripts/core/scheme.gd`.

WHY A PYTHON PARSER TOO, when GDScript already has one. Three reasons, and the
third is the one that matters:

  * `pack_assets.py` copies the 67 files into the pack VERBATIM, so a browser
    build has them. Verbatim means unvalidated: a scheme that the GDScript
    parser will reject at runtime ships anyway, and fails in front of a player.
    This parses them at build time instead.
  * The two parsers are an independent check on each other. They were written
    from the same grammar but not from each other, so a disagreement is a bug
    in one of them, and `--compare` finds it.
  * Nothing outside the game could see the maps. `--ascii` prints them, and
    `tools/out/schemes.json` is a table anything can read.

GRAMMAR, as observed across all 67 files. Every file has exactly one -V, one
-N, one -B, eleven -R, ten -S and thirteen -P — 737, 670 and 871 lines across
the set, which is 67x11, 67x10 and 67x13 exactly.

    -V,<n>                          version; 2 across the whole disc
    -N,<text>                       the scheme's display name
    -B,<0..100>                     brick density, per cent
    -R,<y>,<15 chars>               a row: '#' solid, ':' brick, '.' blank
    -S,<player>,<x>,<y>[,<team>]    a start; team is absent in free-for-alls
    -P,<id>,<born>,<ovr?>,<ovr>,<forbid>,<comment>

    ; text                          comment
    0x1A                            DOS end-of-file, present in some files

The density and the grid do not contradict each other: `-B` is what the level
editor filled the grid WITH, and the ':' cells are the result. The game re-rolls
nothing at load, so the grid is authoritative and -B is provenance.

    tools/schemes.py                parse all 67, report, write JSON
    tools/schemes.py --ascii BASIC  print one map
    tools/schemes.py --check        parse only, write nothing
    tools/schemes.py --compare      also run the GDScript parser and diff
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path

FIELD_W = 15
FIELD_H = 11
PLAYER_COUNT = 10
POWERUP_COUNT = 13

SOLID, BRICK, BLANK = "solid", "brick", "blank"
CELLS = {"#": SOLID, ":": BRICK, ".": BLANK}
# The inverse, for re-encoding a row of words back to the file's own
# characters. Used by the "grid" field below and by to_ascii() — NOT by
# `[0]` (the word's first letter), which collides: "brick" and "blank" both
# start with 'b', so a grid serialized that way cannot tell them apart. That
# collision was real and silent until the two-parser check
# (compare_with_godot(), and godot-project/tests/dump_schemes.gd on the other
# side) was built and it was noticed the comparison couldn't catch a
# brick/blank swap either — the same bug, one cause, two symptoms.
CHAR_OF = {word: ch for ch, word in CELLS.items()}

TEAM_UNSET = -1

# The powerup table's thirteen entries, in file order. The names are the ones
# the -P comments use, which are also the ones MESSAGES.TXT 300-312 use.
POWERUP_NAMES = [
    "bomb", "flame", "disease", "kick", "speed", "punch", "grab",
    "spooger", "goldflame", "trigger", "jelly", "superbad", "random",
]


class ParseError(Exception):
    pass


def parse(text: str, label: str = "<text>") -> dict:
    """One scheme, fully validated. Raises ParseError with a line number."""
    version = 0
    name = ""
    density = -1
    rows: dict[int, list[str]] = {}
    starts: dict[int, dict] = {}
    powerups: dict[int, dict] = {}

    for lineno, raw in enumerate(text.splitlines(), start=1):
        line = raw.replace("\x1a", "")
        head, _, _comment = line.partition(";")
        head = head.strip()
        if not head:
            continue
        if not head.startswith("-"):
            raise ParseError(f"line {lineno}: expected a -X directive, got {raw.strip()!r}")

        kind, _, rest = head.partition(",")
        kind = kind.strip().upper()

        if kind == "-V":
            version = int(rest.strip())

        elif kind == "-N":
            # The name may contain commas and parentheses — "Just the BASIC
            # SET! (10)" — so it is the whole remainder, not a field.
            name = rest.strip()

        elif kind == "-B":
            density = int(rest.strip())
            if not 0 <= density <= 100:
                raise ParseError(f"line {lineno}: -B density {density} is outside 0..100")

        elif kind == "-R":
            index, _, cells = rest.partition(",")
            y = int(index.strip())
            if not 0 <= y < FIELD_H:
                raise ParseError(f"line {lineno}: -R row {y} is outside 0..{FIELD_H - 1}")
            if y in rows:
                raise ParseError(f"line {lineno}: -R row {y} defined twice")
            # Trailing whitespace only — a row is exactly FIELD_W cells.
            cells = cells.rstrip()
            if len(cells) != FIELD_W:
                raise ParseError(f"line {lineno}: -R row {y} is {len(cells)} "
                                 f"characters, expected {FIELD_W}")
            for x, ch in enumerate(cells):
                if ch not in CELLS:
                    raise ParseError(f"line {lineno}: -R row {y} column {x}: "
                                     f"unknown cell character {ch!r}")
            rows[y] = [CELLS[ch] for ch in cells]

        elif kind == "-S":
            f = [p.strip() for p in rest.split(",")]
            if len(f) not in (3, 4):
                raise ParseError(f"line {lineno}: -S wants 3 or 4 fields, got {len(f)}")
            player = int(f[0])
            if not 0 <= player < PLAYER_COUNT:
                raise ParseError(f"line {lineno}: -S player {player} is outside "
                                 f"0..{PLAYER_COUNT - 1}")
            if player in starts:
                raise ParseError(f"line {lineno}: -S player {player} defined twice")
            x, y = int(f[1]), int(f[2])
            if not (0 <= x < FIELD_W and 0 <= y < FIELD_H):
                raise ParseError(f"line {lineno}: -S player {player} start "
                                 f"({x}, {y}) is off the field")
            team = TEAM_UNSET
            if len(f) == 4:
                team = int(f[3])
                if team not in (0, 1):
                    raise ParseError(f"line {lineno}: -S player {player} team "
                                     f"{team} is neither 0 nor 1")
            starts[player] = {"x": x, "y": y, "team": team}

        elif kind == "-P":
            f = [p.strip() for p in rest.split(",")]
            if len(f) < 5:
                raise ParseError(f"line {lineno}: -P wants 5 numeric fields and a "
                                 f"comment, got {len(f)}")
            which = int(f[0])
            if not 0 <= which < POWERUP_COUNT:
                raise ParseError(f"line {lineno}: -P powerup {which} is outside "
                                 f"0..{POWERUP_COUNT - 1}")
            if which in powerups:
                raise ParseError(f"line {lineno}: -P powerup {which} defined twice")
            powerups[which] = {
                "name": POWERUP_NAMES[which],
                # How many of it every player starts the round holding.
                "born_with": int(f[1]),
                # When set, the field spawns exactly `override` of them
                # instead of the count the density would give.
                "has_override": int(f[2]) != 0,
                "override": int(f[3]),
                # When set, it never appears at all.
                "forbidden": int(f[4]) != 0,
                "comment": ",".join(f[5:]).strip(),
            }

        else:
            raise ParseError(f"line {lineno}: unknown directive {kind!r}")

    if version == 0:
        raise ParseError("no -V directive")
    if not name:
        raise ParseError("no -N directive")
    if density < 0:
        raise ParseError("no -B directive")
    for y in range(FIELD_H):
        if y not in rows:
            raise ParseError(f"missing -R row {y}")
    for p in range(PLAYER_COUNT):
        if p not in starts:
            raise ParseError(f"missing -S player {p}")
    for p in range(POWERUP_COUNT):
        if p not in powerups:
            raise ParseError(f"missing -P powerup {p}")

    grid = [rows[y] for y in range(FIELD_H)]

    # A start standing on a solid wall would trap that player for the whole
    # round, so it is worth knowing whether the disc ever does it. (It does
    # not — but three schemes stack two players on one cell, which is legal
    # and is how those maps seat ten players in a small arena.)
    on_solid = [p for p in range(PLAYER_COUNT)
                if grid[starts[p]["y"]][starts[p]["x"]] == SOLID]
    cells_used: dict[tuple[int, int], list[int]] = {}
    for p in range(PLAYER_COUNT):
        cells_used.setdefault((starts[p]["x"], starts[p]["y"]), []).append(p)
    stacked = {f"{x},{y}": ps for (x, y), ps in sorted(cells_used.items())
               if len(ps) > 1}

    teams = sorted({s["team"] for s in starts.values()})
    counts = {kind: sum(row.count(kind) for row in grid)
              for kind in (SOLID, BRICK, BLANK)}

    return {
        "label": label,
        "version": version,
        "name": name,
        "density": density,
        "grid": ["".join(CHAR_OF[k] for k in row) for row in grid],
        "starts": [starts[p] for p in range(PLAYER_COUNT)],
        "powerups": [powerups[p] for p in range(POWERUP_COUNT)],
        "counts": counts,
        "teams_unset": teams == [TEAM_UNSET],
        "starts_on_solid": on_solid,
        "stacked_starts": stacked,
        "distinct_start_cells": len(cells_used),
    }


def to_ascii(scheme: dict) -> str:
    """The map as the file draws it, with the player numbers written in."""
    # scheme["grid"] already holds the file's own #/:/. characters (CHAR_OF
    # above), so no decode step is needed here — there used to be one, keyed
    # by a first-letter encoding that could never actually produce blank's
    # supposed key ("blank"[0] is 'b', the same as "brick"[0], not the 'l'
    # this used to look for), so every blank cell rendered as a brick ':'
    # instead. Silent since --ascii's whole job is a human eyeballing the
    # output, and it still looked like a plausible map.
    out = [list(row) for row in scheme["grid"]]
    for i, s in enumerate(scheme["starts"]):
        out[s["y"]][s["x"]] = f"{i}"
    head = f"{scheme['label']}  {scheme['name']!r}  density {scheme['density']}%"
    body = "\n".join("  " + "".join(row) for row in out)
    tail = (f"  {scheme['counts']['solid']} solid, {scheme['counts']['brick']} brick, "
            f"{scheme['counts']['blank']} blank"
            + ("  ·  no teams" if scheme["teams_unset"] else "  ·  teamed"))
    return f"{head}\n{body}\n{tail}"


def compare_with_godot(root: Path, schemes: dict[str, dict]) -> int:
    """Run the GDScript parser over the same files and diff the two readings.

    The point is independence: `scripts/core/scheme.gd` is what the game
    actually uses, so agreement here means this file's JSON describes the maps
    the port will play, not a second opinion about them.
    """
    godot = Path("/Applications/Godot.app/Contents/MacOS/Godot")
    if not godot.exists():
        print("schemes: --compare needs Godot at "
              f"{godot} — skipping", file=sys.stderr)
        return 0

    script = root / "godot-project" / "tests" / "dump_schemes.gd"
    if not script.exists():
        print(f"schemes: --compare needs {script.relative_to(root)}", file=sys.stderr)
        return 0

    proc = subprocess.run(
        [str(godot), "--headless", "--path", str(root / "godot-project"),
         "--script", str(script)],
        capture_output=True, text=True, timeout=300)
    body = proc.stdout[proc.stdout.find("{"):proc.stdout.rfind("}") + 1]
    if not body:
        print("schemes: --compare got no JSON from Godot", file=sys.stderr)
        print(proc.stdout[-800:], file=sys.stderr)
        return 1
    theirs = json.loads(body)

    bad = 0
    for stem, mine in sorted(schemes.items()):
        other = theirs.get(stem)
        if other is None:
            print(f"schemes: {stem}: the GDScript parser did not read it")
            bad += 1
            continue
        for key in ("name", "density", "grid"):
            if other.get(key) != mine[key]:
                print(f"schemes: {stem}: {key} differs\n"
                      f"    python: {mine[key]}\n    gdscript: {other.get(key)}")
                bad += 1
        mine_starts = [[s["x"], s["y"], s["team"]] for s in mine["starts"]]
        if other.get("starts") != mine_starts:
            print(f"schemes: {stem}: starts differ\n"
                  f"    python: {mine_starts}\n    gdscript: {other.get('starts')}")
            bad += 1
    print(f"schemes: compared {len(schemes)} against scripts/core/scheme.gd — "
          f"{'all agree' if not bad else f'{bad} disagreements'}")
    return 1 if bad else 0


def main(argv: list[str]) -> int:
    root = Path(__file__).resolve().parent.parent

    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--data", type=Path, default=root / "original-game")
    ap.add_argument("--ascii", metavar="NAME",
                    help="print one scheme's map, e.g. BASIC (or ALL)")
    ap.add_argument("--check", action="store_true", help="parse only, write nothing")
    ap.add_argument("--compare", action="store_true",
                    help="diff this parser against scripts/core/scheme.gd")
    args = ap.parse_args(argv)

    src_dir = args.data / "SCHEMES"
    files = sorted(src_dir.glob("*.SCH"))
    if not files:
        print(f"schemes: no .SCH files in {src_dir}", file=sys.stderr)
        return 2

    schemes: dict[str, dict] = {}
    failed = 0
    for src in files:
        stem = src.stem.upper()
        try:
            schemes[stem] = parse(src.read_text(encoding="latin-1"), stem)
        except (ParseError, ValueError) as exc:
            print(f"schemes: {src.name}: {exc}", file=sys.stderr)
            failed += 1
    if failed:
        return 1

    if args.ascii:
        wanted = list(schemes) if args.ascii.upper() == "ALL" else [args.ascii.upper()]
        for stem in wanted:
            if stem not in schemes:
                print(f"schemes: no such scheme: {stem}", file=sys.stderr)
                return 2
            print(to_ascii(schemes[stem]))
            print()
        return 0

    # The summary is chosen to surface the things a port has to decide about:
    # which schemes carry no team assignment (so teamplay has to invent one),
    # which seat two players on one cell, and how wide the density range is.
    no_teams = [s for s in schemes.values() if s["teams_unset"]]
    stacked = [s for s in schemes.values() if s["stacked_starts"]]
    on_solid = [s for s in schemes.values() if s["starts_on_solid"]]
    densities = sorted(s["density"] for s in schemes.values())
    bricks = sorted(s["counts"]["brick"] for s in schemes.values())

    for stem in sorted(schemes):
        s = schemes[stem]
        flags = []
        if s["teams_unset"]:
            flags.append("no teams")
        if s["stacked_starts"]:
            flags.append(f"{len(s['stacked_starts'])} stacked")
        if s["starts_on_solid"]:
            flags.append(f"starts on solid: {s['starts_on_solid']}")
        print(f"schemes: {stem:<12} {s['counts']['solid']:>3} solid "
              f"{s['counts']['brick']:>3} brick {s['counts']['blank']:>3} blank  "
              f"-B {s['density']:>3}%  {s['name'][:34]:<34} {', '.join(flags)}")

    print(f"\nschemes: {len(schemes)} parsed, all complete "
          f"({FIELD_W}x{FIELD_H}, {PLAYER_COUNT} starts, {POWERUP_COUNT} powerups each)")
    print(f"  {len(no_teams)} carry no team assignment, {len(schemes) - len(no_teams)} do")
    print(f"  {len(stacked)} seat two or more players on one cell")
    print(f"  {len(on_solid)} put a start inside a solid wall")
    print(f"  -B density {densities[0]}..{densities[-1]}%, "
          f"actual brick count {bricks[0]}..{bricks[-1]} of {FIELD_W * FIELD_H}")

    if args.compare:
        return compare_with_godot(root, schemes)

    if args.check:
        return 0

    out_dir = root / "tools" / "out"
    out_dir.mkdir(parents=True, exist_ok=True)
    dest = out_dir / "schemes.json"
    dest.write_text(json.dumps(schemes, indent=1), encoding="utf-8")
    print(f"schemes: wrote {dest.relative_to(root)}")

    maps = out_dir / "schemes.txt"
    maps.write_text("\n\n".join(to_ascii(schemes[s]) for s in sorted(schemes)),
                    encoding="utf-8")
    print(f"schemes: wrote {maps.relative_to(root)}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
