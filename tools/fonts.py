#!/usr/bin/env python3
"""Decode the original's `.FON` bitmap fonts.

The screens need the game's own lettering. `KFONT.ANI` turned out to be digits
only — ten numerals and an infinity sign, for the clock — so the alphabet is in
the three `.FON` files in the install root.

THE FORMAT:

    0x00  u32  count       how many entries the table has
    0x04  u32  height      pixel height of every glyph
    0x08  u32  flags       0 for the layout below; FONT0.FON has 1 and is not
    0x0C  u32  unknown x4  the third is 7 in both FONT1 and FONT6
    0x1C  (u32 width, u32 offset) x (count - 1)
          glyph bitmaps: 1 bit per pixel, ceil(width/8) bytes per row,
          `height` rows, MSB leftmost

    Table entry `i` is the glyph for character code **i + 1**.

HOW EACH OF THOSE WAS ESTABLISHED, because three of them were guessed wrong
first and the wrong guesses all produced almost-readable text:

  * The table's POSITION and its FIELD ORDER come from a tiling test. For the
    true layout the glyphs must exactly fill the data region, so sorting the
    entries by offset and requiring each gap to equal the previous glyph's
    `ceil(width/8) * height` is a hard constraint. Over the three plausible
    table positions, both field orders and every row count from 8 to 19, one
    combination scores **190 of 190 pairs exact** and the next best 0.72.
  * The CHARACTER SHIFT comes from rendering the alphabet. At shift 0 the
    string "ABCDEF..." draws "BCDEFG...", at +1 it draws "CDEFGH...", and at
    -1 it draws "ABCDEF...".

An earlier version of this file read the table at 0x18 as (offset, width) with
no shift. That fits the byte total — 4912 needed of 4940 available — and
renders text that is nearly right, which is the worst kind of wrong: every
capital was legible and every lowercase letter was the letter after it.

FONT0.FON was skipped for a while on the strength of its flags word, which is
1 where the other two are 0. That was wrong, and the way it was wrong is worth
keeping: the 14,680,064-pixel width that made it look like another format came
from the OLD (offset, width) reading, not from the flags. Read in the same
(width, offset) order as the others, FONT0 tiles exactly — 108 of its 108
glyph gaps equal ceil(width/8) * height, with no slack — and renders ASCII 19
to 126 at the same code = entry + 1 mapping: three fraction glyphs, two
arrows, then space through tilde. So `flags` is not a layout switch, and the
gate here is the tiling test rather than the flags word, which is the check
that could actually detect a different format.

Output is one PNG per font plus its metrics, packed by tools/pack_assets.py:

    font1.png       every glyph side by side, white on transparent
    manifest        code -> [x, width], plus the height

Usage:
    tools/fonts.py --check       report what each file is
    tools/fonts.py --out DIR     write the PNGs there
"""

from __future__ import annotations

import argparse
import json
import struct
import sys
from pathlib import Path

HEADER = 0x1C

## Table entry i is the glyph for character code i + FIRST_CODE.
FIRST_CODE = 1

## The fonts to extract, and what the port uses each for.
WANTED = {
    "FONT0": "a 17-pixel face with fractions and arrows above ASCII",
    "FONT1": "the menus and every screen's lettering",
    "FONT6": "a second face, one pixel narrower",
}

## Reported but not extracted. Empty since FONT0 turned out to be the same
## layout; kept so a future disc with a genuinely different font has a place
## to be named rather than crashing the run.
UNSUPPORTED: dict[str, str] = {}


class FontError(Exception):
    pass


class Font:
    def __init__(self, path: Path):
        raw = path.read_bytes()
        if len(raw) < HEADER:
            raise FontError(f"{path.name}: {len(raw)} bytes, too short")
        count, height, flags = struct.unpack("<III", raw[:12])
        self.name = path.stem
        self.count = count
        self.height = height
        self.flags = flags
        self.unknown = struct.unpack("<IIII", raw[12:HEADER])
        # No flags gate. The size and tiling checks below are what actually
        # prove the layout, and they pass for all three files; refusing on
        # flags alone cost FONT0 for no reason.
        # count - 1 entries: entry i is the glyph for code i + 1, so a table
        # of `count` codes needs one fewer row. The arithmetic is exact only
        # this way — with `count` entries the last glyph overruns the file by
        # exactly 8 bytes, which is one table row.
        self.entries = count - 1
        need = HEADER + self.entries * 8
        if len(raw) < need:
            raise FontError(f"{path.name}: table wants {need} bytes, file has "
                            f"{len(raw)}")
        # (width, offset), in that order. See the module docstring on how the
        # order was established — the other way round also "works".
        self.table = []
        for i in range(self.entries):
            width, offset = struct.unpack(
                "<II", raw[HEADER + i * 8:HEADER + i * 8 + 8])
            self.table.append((offset, width))
        self.data_at = need
        self.raw = raw

        wanted = 0
        for offset, width in self.table:
            if width:
                wanted = max(wanted, offset + ((width + 7) // 8) * height)
        self.needed = wanted
        self.available = len(raw) - self.data_at
        if wanted > self.available:
            raise FontError(
                f"{path.name}: glyphs need {wanted} bytes, file has "
                f"{self.available} — the layout is not this")

        # The tiling constraint that identified the layout, kept as a check:
        # sorted by offset, each glyph must end exactly where the next begins.
        spans = sorted({(o, w) for o, w in self.table if w})
        self.tiling_exact = 0
        self.tiling_pairs = 0
        for (o1, w1), (o2, _w2) in zip(spans, spans[1:]):
            if o2 == o1:
                continue
            self.tiling_pairs += 1
            if o2 - o1 == ((w1 + 7) // 8) * height:
                self.tiling_exact += 1
        if self.tiling_pairs and self.tiling_exact != self.tiling_pairs:
            raise FontError(
                f"{path.name}: {self.tiling_exact} of {self.tiling_pairs} "
                f"glyphs tile exactly — the layout is not this")

    def codes(self) -> list[int]:
        """The character codes this font has a glyph for."""
        return [i + FIRST_CODE for i, (_o, w) in enumerate(self.table) if w]

    def glyph(self, code: int) -> tuple[int, list[list[int]]] | None:
        """(width, rows of bits) or None where the font has no such glyph."""
        index = code - FIRST_CODE
        if index < 0 or index >= self.count:
            return None
        offset, width = self.table[index]
        if width == 0:
            return None
        stride = (width + 7) // 8
        rows = []
        for y in range(self.height):
            at = self.data_at + offset + y * stride
            row = self.raw[at:at + stride]
            bits = []
            for x in range(width):
                byte = row[x // 8] if x // 8 < len(row) else 0
                bits.append((byte >> (7 - (x % 8))) & 1)
            rows.append(bits)
        return width, rows


def sheet_of(font: Font):
    """(image, metrics). Every glyph side by side, white where set."""
    from PIL import Image

    codes = font.codes()
    widths = {c: font.glyph(c)[0] for c in codes}
    total = sum(widths.values())
    img = Image.new("RGBA", (max(total, 1), font.height), (0, 0, 0, 0))
    metrics: dict[str, list[int]] = {}
    x = 0
    for code in codes:
        width, rows = font.glyph(code)
        for y in range(font.height):
            for i in range(width):
                if rows[y][i]:
                    img.putpixel((x + i, y), (255, 255, 255, 255))
        metrics[str(code)] = [x, width]
        x += width
    return img, metrics


def main(argv: list[str]) -> int:
    root = Path(__file__).resolve().parent.parent
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--data", type=Path, default=root / "original-game")
    ap.add_argument("--out", type=Path)
    ap.add_argument("--check", action="store_true")
    args = ap.parse_args(argv)

    manifest: dict[str, dict] = {}
    for name, what in WANTED.items():
        path = args.data / f"{name}.FON"
        if not path.is_file():
            print(f"fonts: missing {path.name}")
            continue
        try:
            font = Font(path)
        except FontError as exc:
            print(f"fonts: {exc}", file=sys.stderr)
            return 1
        codes = font.codes()
        printable = [c for c in codes if 32 <= c < 127]
        print(f"fonts: {name} — height {font.height}, {len(codes)} glyphs "
              f"({len(printable)} printable ASCII), needs {font.needed} of "
              f"{font.available} bytes, {font.tiling_exact}/"
              f"{font.tiling_pairs} tile exactly — {what}")
        if args.out:
            args.out.mkdir(parents=True, exist_ok=True)
            img, metrics = sheet_of(font)
            img.save(args.out / f"{name.lower()}.png")
            manifest[name.lower()] = {
                "file": f"{name.lower()}.png",
                "height": font.height,
                "glyphs": metrics,
            }
    for name, why in UNSUPPORTED.items():
        path = args.data / f"{name}.FON"
        if path.is_file():
            print(f"fonts: {name} skipped — {why}")

    if args.out and manifest:
        (args.out / "fonts.json").write_text(
            json.dumps(manifest, indent=1), encoding="utf-8")
        print(f"fonts: wrote {args.out}/fonts.json")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
