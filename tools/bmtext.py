#!/usr/bin/env python3
"""Parse the ten `.BM` files — the original's text screens and their markup.

A `.BM` is the credits screen, the manual, the readme, the network and options
help, the roulette explanation, and the two out-of-memory error screens. The
port already shows `CREDITS.BM` and `MANUAL.BM`; this reads all ten the same
way, so the remaining eight are available rather than merely present.

THE FORMAT is plain CRLF text with two pieces of markup and nothing else:

    <IMGNAME>       place RES/NAME.PCX at this point in the flow
    \\t              a tab stop; the original's renderer advances to a column
    0x1A            DOS end-of-file, present at the end of nine of the ten

The tag name is case-insensitive on the disc — `<IMGCREDBAR>` and
`<IMGpowbomb>` both appear — and always resolves to a PCX in `RES/`. That is
worth checking rather than assuming: an unresolvable tag is a hole in a screen,
and MANUAL.BM alone places thirteen powerup icons this way. All 18 tags across
the ten files resolve.

Text in angle brackets that is NOT an image is left alone, because the disc
uses angle brackets as prose too — `<ESC>`, `<button>`, `<action>`,
`<drop bomb>`. Only `<IMG...>` is markup; the rule is the prefix, not the
brackets.

WHAT COMES OUT. One entry per file, holding the text as lines with their tab
runs preserved, and the image placements as (line, column, pcx) so a renderer
can put them back where the original put them:

    tools/bmtext.py                 parse all ten, report, write JSON
    tools/bmtext.py --dump README   print one, tags resolved
    tools/bmtext.py --check         parse only, write nothing
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

TAG = re.compile(r"<IMG([A-Za-z0-9_]+)>", re.IGNORECASE)

# What each screen is, in the order the game can reach them. The two memory
# screens are error paths — BM95.EXE shows one when it cannot get the memory
# it wants — and are the reason "ten .BM files" is more than "credits and
# manual".
SCREENS = {
    "CREDITS": "the credits, shown by About Bomberman",
    "MANUAL": "the online manual, and the only file that places powerup icons",
    "README": "the shipped readme, updated in 1999 — the newest file on the disc",
    "EDITOR": "how to use FRED, the level editor in TOOLS/",
    "NETWORK": "network play help",
    "OPTIONS": "the settings screen's own help text",
    "INPUT": "controller and keyboard help",
    "ROULETTE": "what the Goldman roulette wheel does",
    "HIGHMEM": "the error screen for too little memory",
    "LOWMEM": "the other memory error screen",
}


class ParseError(Exception):
    pass


def parse(text: str, label: str = "<text>") -> dict:
    """One screen: its lines, its image placements, and its tab usage."""
    body = text.replace("\x1a", "").replace("\r\n", "\n").replace("\r", "\n")
    lines_out: list[str] = []
    images: list[dict] = []

    for lineno, raw in enumerate(body.split("\n")):
        # Record where each tag sits before removing it, so a renderer can put
        # the picture back at the column the original put it at.
        col_shift = 0
        for m in TAG.finditer(raw):
            images.append({
                "line": lineno,
                "col": m.start() - col_shift,
                "pcx": m.group(1).upper(),
                "tag": m.group(0),
            })
            col_shift += len(m.group(0))
        lines_out.append(TAG.sub("", raw))

    # Trailing blank lines are layout in some files and litter in others;
    # keeping them is the safe reading, since the original scrolls the whole
    # buffer. Only a trailing empty line from the final newline is dropped.
    while lines_out and lines_out[-1] == "":
        lines_out.pop()

    return {
        "label": label,
        "what": SCREENS.get(label, "unlisted .BM"),
        "lines": lines_out,
        "images": images,
        "tabs": sum(line.count("\t") for line in lines_out),
        "chars": sum(len(line) for line in lines_out),
    }


def main(argv: list[str]) -> int:
    root = Path(__file__).resolve().parent.parent

    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--data", type=Path, default=root / "original-game")
    ap.add_argument("--dump", metavar="NAME", help="print one screen, e.g. ROULETTE")
    ap.add_argument("--check", action="store_true", help="parse only, write nothing")
    args = ap.parse_args(argv)

    files = sorted(args.data.glob("*.BM"))
    if not files:
        print(f"bmtext: no .BM files in {args.data}", file=sys.stderr)
        return 2

    have_pcx = {p.stem.upper() for p in (args.data / "RES").glob("*.PCX")}

    screens: dict[str, dict] = {}
    dangling: list[str] = []
    for src in files:
        stem = src.stem.upper()
        screens[stem] = parse(src.read_text(encoding="latin-1"), stem)
        for img in screens[stem]["images"]:
            if img["pcx"] not in have_pcx:
                dangling.append(f"{stem}: {img['tag']} -> RES/{img['pcx']}.PCX")

    if args.dump:
        stem = args.dump.upper().removesuffix(".BM")
        if stem not in screens:
            print(f"bmtext: no such screen: {args.dump}", file=sys.stderr)
            return 2
        s = screens[stem]
        placed = {(i["line"], i["col"]): i["pcx"] for i in s["images"]}
        for n, line in enumerate(s["lines"]):
            marks = " ".join(f"[{p} at col {c}]"
                             for (ln, c), p in placed.items() if ln == n)
            print(f"{line}{'  ' + marks if marks else ''}")
        return 0

    for stem in sorted(screens):
        s = screens[stem]
        print(f"bmtext: {stem:<9} {len(s['lines']):>4} lines "
              f"{s['chars']:>6} chars {len(s['images']):>2} images "
              f"{s['tabs']:>3} tabs   {s['what']}")

    total_img = sum(len(s["images"]) for s in screens.values())
    print(f"\nbmtext: {len(screens)} screens, {total_img} image placements, "
          f"{'all resolve' if not dangling else f'{len(dangling)} DANGLING'}")
    for bad in dangling:
        print(f"  dangling: {bad}", file=sys.stderr)
    if dangling:
        return 1

    if args.check:
        return 0

    out_dir = root / "tools" / "out"
    out_dir.mkdir(parents=True, exist_ok=True)
    dest = out_dir / "bmtext.json"
    dest.write_text(json.dumps(screens, indent=1), encoding="utf-8")
    print(f"bmtext: wrote {dest.relative_to(root)}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
