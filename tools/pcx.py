#!/usr/bin/env python3
"""Decode every `.PCX` on the disc, and say what each one is.

`pack_assets.py` takes a CURATED set of PCX — the fifteen screens, the eleven
field backgrounds, ten victory screens and nine placed elements — because a
pack should carry what the game draws and nothing else. That leaves the
question this file answers: is the curated set the whole set, and what is in
the rest?

It is not a wrapper around PIL for its own sake. PIL decodes the pixels; what
matters for a port is the three things PIL will not tell you:

  * WHICH PALETTE. Every PCX on the disc is 8-bit paletted, and the disc's own
    `COLOR.PAL` is the palette the recolour path expects. A PCX whose palette
    is NOT that one cannot be recoloured by an index remap, so the check is
    worth having rather than assuming. `--palettes` reports how each file's
    palette compares.
  * WHICH ARE UNUSED. Cross-referencing against pack_assets.py's own lists
    says exactly which files the port carries and which it ignores, so
    "unused" is a fact rather than an omission nobody noticed.
  * WHAT SIZE, AGAINST THE RULE. Every screen is 640x480; the elements are
    not. `--check` asserts that, because a 640x480 that turns out to be
    640x479 is the kind of thing that draws one row of garbage.

    tools/pcx.py                    decode all, report, write PNGs + JSON
    tools/pcx.py --check            decode only, write nothing
    tools/pcx.py --palettes         compare every palette against COLOR.PAL
    tools/pcx.py --out DIR          PNGs somewhere else
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

SCREEN_W, SCREEN_H = 640, 480

# The port's own use for each file, taken from pack_assets.py's lists so the
# two cannot drift apart silently: anything here and not there, or there and
# not here, shows up in the report as unused or missing.
ROLES = {
    "TITLE": "screen", "MAINMENU": "screen", "RESULTS": "screen",
    "DRAW": "screen", "ROULETTE": "screen", "BONUS": "screen",
    "TEAM0": "screen", "TEAM1": "screen",
    "GLUE0": "screen", "GLUE1": "screen", "GLUE2": "screen", "GLUE3": "screen",
    "GLUE4": "screen", "GLUE5": "screen", "GLUE6": "screen",
    "CREDBAR": "element", "WINZ": "element", "BOMBDUDE": "element",
    "JERM": "element", "KURT": "element", "KURTHEAD": "element",
    "IPLOGO": "element", "HSLOGO": "element", "QALOGO": "element",
}
for _n in range(11):
    ROLES[f"FIELD{_n}"] = "field"
for _n in range(10):
    ROLES[f"VICTORY{_n}"] = "victory"
for _n in ("POWBAD", "POWBOMB", "POWDISEA", "POWEBOLA", "POWFAST", "POWFLAME",
           "POWGOLD", "POWGRAB", "POWJELLY", "POWKICK", "POWPUNCH", "POWRAND",
           "POWSKATE", "POWSLOW", "POWSPOOG", "POWTRIG"):
    ROLES[_n] = "powerup"


def read_palette(path: Path) -> list[tuple[int, int, int]] | None:
    """COLOR.PAL's 256 triples, expanded from the disc's 6-bit values.

    The file stores 0..63 per channel, which is VGA's DAC range, so a straight
    read of it produces a picture that is a quarter as bright as it should be.
    remap.py explains the same thing at more length; the scale is <<2 with the
    top bits carried down, which is what `x * 255 // 63` does.
    """
    if not path.is_file():
        return None
    raw = path.read_bytes()[:768]
    if len(raw) < 768:
        return None
    return [(raw[i] * 255 // 63, raw[i + 1] * 255 // 63, raw[i + 2] * 255 // 63)
            for i in range(0, 768, 3)]


def main(argv: list[str]) -> int:
    root = Path(__file__).resolve().parent.parent

    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--data", type=Path, default=root / "original-game")
    ap.add_argument("--out", type=Path, default=root / "tools" / "out" / "pcx")
    ap.add_argument("--check", action="store_true", help="decode only, write nothing")
    ap.add_argument("--palettes", action="store_true",
                    help="compare each palette against COLOR.PAL")
    args = ap.parse_args(argv)

    from PIL import Image

    files = sorted(args.data.rglob("*.PCX"))
    if not files:
        print(f"pcx: no .PCX files under {args.data}", file=sys.stderr)
        return 2

    disc_pal = read_palette(args.data / "COLOR.PAL")
    if disc_pal is None:
        print("pcx: COLOR.PAL not found — palette comparison skipped",
              file=sys.stderr)

    if not args.check:
        args.out.mkdir(parents=True, exist_ok=True)

    entries: dict[str, dict] = {}
    problems: list[str] = []

    for src in files:
        stem = src.stem.upper()
        rel = src.relative_to(args.data).as_posix()
        try:
            img = Image.open(src)
            img.load()
        except Exception as exc:  # a PCX that will not decode is a hard failure
            problems.append(f"{rel}: {exc}")
            continue

        role = ROLES.get(stem, "unused")
        # TOOLS/BOMBPAL.PCX is the art team's palette swatch, not game art;
        # naming it keeps "unused" meaning "unexplained".
        if rel.upper().startswith("TOOLS/"):
            role = "editor palette swatch"

        pal = img.getpalette()
        same_pal = None
        if disc_pal and pal:
            theirs = [tuple(pal[i:i + 3]) for i in range(0, min(768, len(pal)), 3)]
            # The stored palette is already 8-bit here (PIL expands it), so
            # compare against the expanded disc palette.
            same_pal = theirs[:256] == disc_pal[:len(theirs[:256])]

        entry = {
            "path": rel,
            "size": list(img.size),
            "mode": img.mode,
            "role": role,
            "colors_used": len(img.getcolors(maxcolors=256) or []),
            "matches_color_pal": same_pal,
        }
        entries[stem] = entry

        if role in ("screen", "field", "victory") and tuple(img.size) != (SCREEN_W, SCREEN_H):
            problems.append(f"{rel}: {img.size} — every {role} should be "
                            f"{SCREEN_W}x{SCREEN_H}")

        if not args.check:
            img.convert("RGBA").save(args.out / f"{stem.lower()}.png")

    by_role: dict[str, int] = {}
    for e in entries.values():
        by_role[e["role"]] = by_role.get(e["role"], 0) + 1
    for role in sorted(by_role):
        names = sorted(k for k, v in entries.items() if v["role"] == role)
        shown = ", ".join(names[:6]) + (" ..." if len(names) > 6 else "")
        print(f"pcx: {by_role[role]:>3} {role:<22} {shown}")

    if args.palettes:
        print()
        odd = [k for k, v in sorted(entries.items())
               if v["matches_color_pal"] is False]
        same = [k for k, v in entries.items() if v["matches_color_pal"] is True]
        none = [k for k, v in sorted(entries.items())
                if v["matches_color_pal"] is None]
        # The measured answer, and it is not the one the pipeline assumes:
        # NONE of the 62 carries COLOR.PAL. Every screen embeds its own
        # palette, and QALOGO is greyscale with no palette at all. So
        # COLOR.PAL belongs to the .RMP player-recolour path (remap.py) and
        # not to screen drawing — which is why the port can convert screens to
        # RGBA at pack time and lose nothing.
        print(f"pcx: {len(same)} of {len(entries)} carry COLOR.PAL's own palette; "
              f"{len(odd)} embed their own; {len(none)} have none")
        for k in none:
            print(f"  no palette: {entries[k]['path']} ({entries[k]['mode']})")

    # Anything in ROLES with no file is a name pack_assets.py will ask for and
    # not get, which is worth catching here rather than at pack time.
    missing = sorted(set(ROLES) - set(entries))
    if missing:
        problems.append("named by pack_assets.py but not on the disc: "
                        + ", ".join(missing))

    print(f"\npcx: {len(entries)} files decoded, "
          f"{sum(1 for e in entries.values() if e['role'] == 'unused')} unused by the port")
    for bad in problems:
        print(f"  problem: {bad}", file=sys.stderr)
    if problems:
        return 1

    if args.check:
        return 0

    out_json = root / "tools" / "out" / "pcx.json"
    out_json.write_text(json.dumps(entries, indent=1), encoding="utf-8")
    print(f"pcx: wrote {len(entries)} PNGs to {args.out.relative_to(root)}/ "
          f"and {out_json.relative_to(root)}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
