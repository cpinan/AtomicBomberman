#!/usr/bin/env python3
"""Compare the two per-player colour transforms: the disc's tables and ours.

WHY THIS RUNS BEFORE ANY SHADER IS WRITTEN. The port recolours players with
fpc_atomic's green-dominance heuristic, and the disc's own `.RMP` files plus
`COLOR.PAL` are an exact table lookup. Replacing one with the other is a
worthwhile piece of work only if they disagree by an amount somebody can see,
and that is measurable now.

THE HYPOTHESIS, and it is the first thing checked, because everything else
rests on it:

    COLOR.PAL = 256 RGB triples (6-bit) + a 32768-byte RGB555 -> index lookup
    a .RMP    = a 256-entry palette remap, non-zero over indices 100..174
    so        index = lut[rgb555(pixel)] ; pixel = palette[rmp[index]]

If the `.ANI` art really lives in that palette, then the pixels a bomberman is
drawn from should land INSIDE the remapped block, and the pixels of its helmet
and outline should land outside it. If they scatter, the hypothesis is wrong
and the tables belong to some other stage of the original's pipeline.

Usage:
    tools/remap.py                 the whole report
    tools/remap.py --ani WALK      one sheet
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import anifile  # noqa: E402

PALETTE_BYTES = 768
LUT_BYTES = 32768

## The actors, which are the only things that get recoloured.
ACTORS = ["WALK", "STAND", "KICK", "BOMBS", "MFLAME", "SHADOW"]


def load_color_pal(path: Path) -> tuple[list[tuple[int, int, int]], bytes]:
    """(palette, lut). Palette entries are 6-bit, as stored."""
    data = path.read_bytes()
    if len(data) != PALETTE_BYTES + LUT_BYTES:
        raise ValueError(f"{path}: {len(data)} bytes, expected "
                         f"{PALETTE_BYTES + LUT_BYTES}")
    palette = [(data[i * 3], data[i * 3 + 1], data[i * 3 + 2])
               for i in range(256)]
    return palette, data[PALETTE_BYTES:]


def load_rmp(path: Path) -> bytes:
    """The 256-entry remap. The file is 259 bytes; the last three are not part
    of the map — every one of the ten is non-zero there, and the map's own
    non-zero run ends at 174."""
    data = path.read_bytes()
    if len(data) < 256:
        raise ValueError(f"{path}: {len(data)} bytes, expected at least 256")
    return data[:256]


def rgb555(r8: int, g8: int, b8: int) -> int:
    """8-bit back to the 15-bit value the ANI stored.

    tools/anifile.py expands 5 bits to 8 with `(v << 3) | (v >> 2)`, so the top
    five bits are exactly what was in the file.
    """
    return ((r8 >> 3) << 10) | ((g8 >> 3) << 5) | (b8 >> 3)


def six_to_eight(c: int) -> int:
    """A 6-bit VGA component as 8-bit, replicating the top bits.

    Clamped to 6 bits first because palette entry 0 is stored as
    `ff ff ff` — 255 in every channel, where every other entry is 0..63. It
    reads as a sentinel for "white" or "unused"; taken literally it produces a
    colour off the end of the 15-bit cube. It is also one of the two entries
    that fail the round trip below.
    """
    c = min(c, 0x3F)
    return (c << 2) | (c >> 4)


def mapped_indices(rmps: list[bytes]) -> set[int]:
    """Every index any .RMP changes. All ten agree on the block."""
    out: set[int] = set()
    for rmp in rmps:
        for i, v in enumerate(rmp):
            if v:
                out.add(i)
    return out


def heuristic(r: int, g: int, b: int,
              target: tuple[float, float, float]) -> tuple[int, int, int]:
    """fpc_atomic's transform, which is what the port's shader implements.

    Green-dominant pixels are split into a neutral base plus a green tint and
    re-tinted; everything else is left alone.
    """
    if not (g > r and g > b):
        return r, g, b
    n = (r + b) / 2.0
    k = g - n
    out = [n + k * target[0], n + k * target[1], n + k * target[2]]
    peak = max(out)
    if peak > 255.0:
        out = [c * 255.0 / peak for c in out]
    return tuple(int(round(min(max(c, 0.0), 255.0))) for c in out)


def exact(r: int, g: int, b: int, lut: bytes, palette: list, rmp: bytes,
          block: set[int]) -> tuple[int, int, int]:
    """The disc's transform."""
    index = lut[rgb555(r, g, b)]
    if index not in block:
        return r, g, b
    mapped = rmp[index]
    pr, pg, pb = palette[mapped]
    return six_to_eight(pr), six_to_eight(pg), six_to_eight(pb)


def ratio(r: int, g: int, b: int, lut: bytes, palette: list, rmp: bytes,
          block: set[int]) -> tuple[int, int, int]:
    """The disc's TABLES applied without the disc's QUANTISATION.

    The reason this exists: the `.ANI` art is not palettised. WALK.ANI uses 978
    distinct colours and 24 of them are palette entries, so `COLOR.PAL`'s
    lookup is a nearest-match quantiser — the original reduced its 15-bit art
    to 256 colours for an 8-bit display and then remapped the indices.
    Reproducing that faithfully means quantising, which throws away colour the
    port already has.

    So the index is used only to decide WHICH recolour applies, and the pixel
    keeps its own detail:

        i = lut[rgb555(pixel)]          the nearest palette entry
        S = palette[i]                  what the disc thought this pixel was
        T = palette[rmp[i]]             what the disc turns that into
        out = pixel * (T / S)           the same change, applied to the real pixel

    Multiplicative, because the remap is a hue-and-brightness change over a
    ramp and a ratio preserves the ramp's shape. Additive where a source
    channel is near zero and a ratio would be meaningless or explode.
    """
    index = lut[rgb555(r, g, b)]
    if index not in block:
        return r, g, b
    src = palette[index]
    dst = palette[rmp[index]]
    out = []
    for c, s6, d6 in zip((r, g, b), src, dst):
        s8 = six_to_eight(s6)
        d8 = six_to_eight(d6)
        if s8 > 8:
            out.append(c * d8 / s8)
        else:
            out.append(c + (d8 - s8))
    peak = max(out)
    if peak > 255.0:
        out = [v * 255.0 / peak for v in out]
    return tuple(int(round(min(max(v, 0.0), 255.0))) for v in out)


def targets_from_valuelist(path: Path) -> list[tuple[float, float, float]]:
    """The ten player colours, VALUELST 200-247, components 0..100."""
    values = json.loads(path.read_text())["values"]
    out = []
    for slot in range(10):
        base = 200 + slot * 5
        out.append(tuple(int(values[str(base + i)]) / 100.0 for i in range(3)))
    return out


def _all_slots(args, ani_dir: Path, lut: bytes, palette: list,
               rmps: list[bytes], block: set[int], targets: list) -> int:
    """One row per player colour, so a conclusion does not rest on one target.

    Restricted to the pixels BOTH transforms agree to recolour, because that is
    the population where the question is about colour rather than about which
    pixels are touched.
    """
    path = ani_dir / f"{(args.ani or ['WALK'])[0]}.ANI"
    ani = anifile.load(path)
    pixels = []
    for frame in ani.frames:
        px = frame.pixels
        for o in range(0, len(px), 4):
            if px[o + 3] == 0:
                continue
            r, g, b = px[o], px[o + 1], px[o + 2]
            if (lut[rgb555(r, g, b)] in block) and (g > r and g > b):
                pixels.append((r, g, b))
    print(f"\n{path.stem}: {len(pixels)} pixels both transforms recolour\n")
    # Three transforms, pairwise. `exact` is the disc's, quantisation and all;
    # `ratio` is the disc's tables without its quantisation; `heuristic` is
    # what the port ships.
    print(f"{'slot':>4} {'target':>18} | {'heur vs exact':>13} "
          f"{'ratio vs exact':>14} {'heur vs ratio':>13} | {'pal-exact':>9}")
    exact_pixels = [(r, g, b) for r, g, b in pixels
                    if _is_palette_colour(r, g, b, lut, palette)]
    for slot in range(10):
        target = targets[slot]
        he = re_ = hr = 0.0
        pal_gap = 0.0
        for r, g, b in pixels:
            e = exact(r, g, b, lut, palette, rmps[slot], block)
            h = heuristic(r, g, b, target)
            t = ratio(r, g, b, lut, palette, rmps[slot], block)
            he += max(abs(e[i] - h[i]) for i in range(3))
            re_ += max(abs(e[i] - t[i]) for i in range(3))
            hr += max(abs(h[i] - t[i]) for i in range(3))
        for r, g, b in exact_pixels:
            e = exact(r, g, b, lut, palette, rmps[slot], block)
            t = ratio(r, g, b, lut, palette, rmps[slot], block)
            pal_gap += max(abs(e[i] - t[i]) for i in range(3))
        n = len(pixels)
        m = max(1, len(exact_pixels))
        print(f"{slot:>4} {str(tuple(round(c, 2) for c in target)):>18} | "
              f"{he/n:>13.1f} {re_/n:>14.1f} {hr/n:>13.1f} | "
              f"{pal_gap/m:>9.2f}")
    print(f"\nmean absolute per-channel difference, over {len(pixels)} pixels")
    print(f"pal-exact: ratio vs exact on the {len(exact_pixels)} pixels whose "
          f"colour IS a palette entry — should be ~0")
    return 0


def _is_palette_colour(r: int, g: int, b: int, lut: bytes,
                       palette: list) -> bool:
    v = rgb555(r, g, b)
    pr, pg, pb = palette[lut[v]]
    return rgb555(six_to_eight(pr), six_to_eight(pg), six_to_eight(pb)) == v


def main(argv: list[str]) -> int:
    root = Path(__file__).resolve().parent.parent
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--data", type=Path, default=root / "original-game")
    ap.add_argument("--ani", action="append",
                    help="only these sheets (default: the actors)")
    ap.add_argument("--slot", type=int, default=1,
                    help="which player colour to compare with (default 1)")
    ap.add_argument("--all-slots", action="store_true",
                    help="one row per player colour, over WALK.ANI")
    args = ap.parse_args(argv)

    pal_path = args.data / "COLOR.PAL"
    if not pal_path.is_file():
        print(f"remap: need {pal_path}", file=sys.stderr)
        return 2
    palette, lut = load_color_pal(pal_path)
    rmps = [load_rmp(args.data / f"{i}.RMP") for i in range(10)]
    block = mapped_indices(rmps)

    runs = []
    start = None
    for i in range(257):
        inside = i in block
        if inside and start is None:
            start = i
        elif not inside and start is not None:
            runs.append((start, i - 1))
            start = None
    print(f"remap: COLOR.PAL is {PALETTE_BYTES} + {LUT_BYTES} bytes")
    print(f"remap: the .RMP files change {len(block)} of 256 indices, in runs "
          + ", ".join(f"{a}..{b}" for a, b in runs))

    # The round trip that proves the lookup is a lookup.
    hits = 0
    for i in range(256):
        r, g, b = palette[i]
        if lut[rgb555(six_to_eight(r), six_to_eight(g), six_to_eight(b))] == i:
            hits += 1
    print(f"remap: {hits}/256 palette entries map back to their own index")

    targets = targets_from_valuelist(root / "tools" / "out" / "valuelist.json")
    target = targets[args.slot]
    print(f"remap: comparing against player {args.slot}, target "
          f"{tuple(round(c, 2) for c in target)}")

    ani_dir = args.data / "ANI"
    if args.all_slots:
        return _all_slots(args, ani_dir, lut, palette, rmps, block, targets)

    wanted = args.ani or ACTORS
    print()
    print(f"{'sheet':<10} {'pixels':>8} {'in block':>9} {'green':>7} "
          f"{'agree':>7} {'differ':>7} {'mean d':>7} {'max d':>6}")
    totals = [0, 0, 0, 0, 0, 0.0, 0]
    for name in wanted:
        path = ani_dir / f"{name}.ANI"
        if not path.is_file():
            print(f"{name:<10} absent")
            continue
        ani = anifile.load(path)
        opaque = in_block = green = agree = differ = 0
        total_d = 0.0
        max_d = 0
        for frame in ani.frames:
            px = frame.pixels
            for o in range(0, len(px), 4):
                if px[o + 3] == 0:
                    continue
                r, g, b = px[o], px[o + 1], px[o + 2]
                opaque += 1
                index = lut[rgb555(r, g, b)]
                is_block = index in block
                is_green = g > r and g > b
                in_block += int(is_block)
                green += int(is_green)
                agree += int(is_block == is_green)
                e = exact(r, g, b, lut, palette, rmps[args.slot], block)
                h = heuristic(r, g, b, target)
                d = max(abs(e[0] - h[0]), abs(e[1] - h[1]), abs(e[2] - h[2]))
                if d > 8:
                    differ += 1
                total_d += d
                max_d = max(max_d, d)
        if opaque == 0:
            continue
        print(f"{name:<10} {opaque:>8} {100*in_block/opaque:>8.1f}% "
              f"{100*green/opaque:>6.1f}% {100*agree/opaque:>6.1f}% "
              f"{100*differ/opaque:>6.1f}% {total_d/opaque:>7.1f} {max_d:>6}")
        totals[0] += opaque
        totals[1] += in_block
        totals[2] += green
        totals[3] += agree
        totals[4] += differ
        totals[5] += total_d
        totals[6] = max(totals[6], max_d)

    if totals[0]:
        n = totals[0]
        print(f"{'ALL':<10} {n:>8} {100*totals[1]/n:>8.1f}% "
              f"{100*totals[2]/n:>6.1f}% {100*totals[3]/n:>6.1f}% "
              f"{100*totals[4]/n:>6.1f}% {totals[5]/n:>7.1f} {totals[6]:>6}")
        print()
        print("in block  the disc's tables would recolour this pixel")
        print("green     fpc_atomic's heuristic would recolour it")
        print("agree     the two predicates give the same answer")
        print("differ    the two OUTPUT colours differ by more than 8/255")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
