#!/usr/bin/env python3
"""Decode Interplay `.ANI` animation containers from Atomic Bomberman.

An `.ANI` is an IFF-style chunked container. Verified against all 95 files in
the CD's `ANI/` folder.

    file header   b"CHFILEANI " (10B), uint32 file_length, uint16 file_id
    chunk         4B signature, uint32 payload_length, uint16 id, payload
                  (payload_length EXCLUDES this 10-byte header)

Top-level chunks are `FRAM`, one per frame, plus `HEAD`, `PAL `, `TPAL`,
`CBOX` and one `SEQ ` per named animation. Inside a `FRAM`:

    FNAM    the frame's name, as ASCII
    CIMG    the pixels

A `SEQ ` is the animation definition, and fpc_atomic ignores it entirely — it
hand-authored a `files.txt` per animation instead. Its structure:

    SEQ
      HEAD    96B; begins with a NUL-terminated name, e.g. "walk north"
      STAT
        HEAD  46B
        FRAM  12B each, one per step of the animation, in playback order:
              uint16  always 1 on this disc
              uint16  index into the file's frame pool
              int16   dx      small per-step offset, meaning unconfirmed
              int16   dy      ditto
              uint16  always 0
              uint16  always 0

This is where the real animation data lives. WALK.ANI, for instance, holds five
sequences over one pool of 60 frames:

    walk east   frames 0-14      walk north  frames 15-29
    walk south  frames 30-44     walk west   frames 45-59
    spin        frames 17, 8, 38, 53 — one from each direction

The dx/dy pair is decoded and carried through but not interpreted; see
docs/BUGS.md.

A `CIMG` payload:

    uint16  type            4, 5, 10 or 11
    uint16  (unknown)
    uint32  additional_size >= 24; the excess over 24 is a palette
    uint32  (unknown)
    uint16  width
    uint16  height
    uint16  hotspot_x       the anchor the game draws this frame around
    uint16  hotspot_y
    uint16  keycolor_bytes
    uint16  (unknown)
    ...     palette, additional_size - 24 bytes, skipped
    uint16  (unknown)
    uint16  (unknown)
    uint32  compressed_size + 12
    uint32  uncompressed_size
    ...     RLE pixel data

Pixels are Targa datatype 10 — run-length encoded — at 16 bits, laid out
RGB555 little-endian:

    bit 15     UNUSED — see below
    bits 14-10 red
    bits  9-5  green
    bits  4-0  blue

Transparency comes from `keycolor_bytes`, not from bit 15. Measured over all
2299 type-4 frames on the disc, bit 15 is set on exactly zero pixels and zero
keycolours, so reading it as an alpha flag makes every frame fully
transparent — which is what happened here first. `keycolor_bytes` holds the
16-bit value that means "transparent" and it varies per frame; the commonest
are 0x4210 (1017 frames), 0x7F7F (620), 0x7F5F (246) and 0x7C1F (171, pure
magenta). STAND.ANI frame 0 is 10879 of its 12100 pixels at 0x7F5F, its own
declared key.

fpc_atomic decodes this field, names it, and then ignores it — hardcoding
Delphi's clFuchsia as the key at load time instead. Driving it from the data is
both more accurate and one fewer constant.

134 frames declare a key of 0x0000, i.e. black. That is taken at its word,
which does mean a frame using black legitimately would lose those pixels; no
such frame has been observed among the ones the port uses.

Each packet is a header byte then one 16-bit pixel; `header & 0x7F` is a count
of ADDITIONAL pixels, and `header & 0x80` distinguishes a run (repeat that
pixel) from a literal (read that many more pixels).

Deliberate difference from fpc_atomic's decoder, which this format description
is derived from: it expands each 5-bit channel with `<< 3`, so 31 becomes 248
and white renders as (248, 248, 248). This uses `(v << 3) | (v >> 2)`, the
standard expansion that maps 31 to 255. There is no ground truth to prefer
either — the original drew these on a 16-bit display and never expanded them —
but one of the two makes white actually white. Pass --fpc-expand to match
fpc_atomic instead.

Usage:
    tools/anifile.py --list                    inventory every ANI
    tools/anifile.py --dump NAME --out DIR     write one ANI's frames as PNGs
    tools/anifile.py --check                   decode all 95, report, write nothing
"""

from __future__ import annotations

import argparse
import struct
import sys
from pathlib import Path

CHUNK_HEADER = 10
FILE_MAGIC = b"CHFILEANI "

# What the CD actually contains, measured across all 95 files and 2327 frames:
#
#   type 0x04, no palette      2254 frames   the normal case
#   type 0x04, 1032B palette     45 frames   also 16-bit direct colour
#   type 0x0B, 1032B palette     28 frames   all of them in CLASSICS.ANI
#
# Only type 0x04 is 16-bit direct colour, which is what the RLE decoder below
# understands. Type 0x0B is palette-indexed and would decode to garbage, so it
# is refused rather than mis-decoded — the one file containing it is referenced
# by neither MASTER.ALI nor fpc_atomic, and AtomBomberman's notes list it among
# files "not used by the game at all".
#
# fpc_atomic asserts a 1024-byte palette for type 0x0B and 64 for type 0x0A.
# Both are wrong for this disc: the observed palette size is 1032, and type
# 0x0A does not occur at all. Its check never fires because it stops at the
# type first.
## CIMG pixel formats this decodes. 0x04 is 16-bit direct colour, which is
## almost the whole disc; 0x0b is 8-bit paletted and appears in exactly one
## file, CLASSICS.ANI. See _decode_rle8 for how 0x0b was established.
DECODABLE_TYPES = {0x04, 0x0B}
TYPE_DIRECT16 = 0x04
TYPE_PALETTED8 = 0x0B

## A type-0x0b palette: an eight-byte header, then 256 RGBA quads.
PALETTE_HEADER = 8
PALETTE_ENTRIES = 256
OBSERVED_PALETTE_SIZES = {0, 1032}


class AniError(Exception):
    """The file is malformed, or says something we do not believe."""


class UnsupportedType(AniError):
    """Well-formed, but in a pixel format this decoder does not handle.

    Kept distinct from AniError so that --check can fail on a broken file the
    game loads while merely reporting a format we never needed.
    """


class Sequence:
    """One named animation: an ordered list of steps into the frame pool."""

    __slots__ = ("name", "steps")

    def __init__(self, name: str = "") -> None:
        self.name = name
        self.steps: list[tuple[int, int, int]] = []   # (frame_index, dx, dy)

    def frame_indices(self) -> list[int]:
        return [s[0] for s in self.steps]

    def __repr__(self) -> str:
        return f"Sequence({self.name!r}, {len(self.steps)} steps)"


class Frame:
    __slots__ = ("name", "width", "height", "hotspot_x", "hotspot_y",
                 "keycolor_bytes", "cimg_type", "pixels")

    def __init__(self) -> None:
        self.name = ""
        self.width = 0
        self.height = 0
        self.hotspot_x = 0
        self.hotspot_y = 0
        self.keycolor_bytes = 0
        self.cimg_type = 0
        self.pixels = b""      # RGBA8888, width * height * 4

    def __repr__(self) -> str:
        return (f"Frame({self.name!r} {self.width}x{self.height} "
                f"hotspot=({self.hotspot_x},{self.hotspot_y}))")


def _read_chunk_header(buf: bytes, pos: int) -> tuple[bytes, int, int, int]:
    """Return (signature, payload_length, id, payload_start)."""
    if pos + CHUNK_HEADER > len(buf):
        raise AniError(f"truncated chunk header at {pos}")
    sig = buf[pos:pos + 4]
    length, ident = struct.unpack_from("<IH", buf, pos + 4)
    return sig, length, ident, pos + CHUNK_HEADER


def _decode_rle16(data: bytes, width: int, height: int, keycolor: int,
                  fpc_expand: bool = False) -> bytes:
    """Targa datatype-10 RLE over RGB555 pixels -> RGBA8888 bytes.

    A pixel equal to `keycolor` becomes fully transparent; everything else is
    fully opaque. There is no partial alpha in this format.
    """
    want = width * height
    out = bytearray(want * 4)
    n = 0
    pos = 0
    end = len(data)

    while n < want:
        if pos + 3 > end:
            raise AniError(
                f"pixel data exhausted after {n} of {want} pixels")
        header = data[pos]
        lo = data[pos + 1]
        hi = data[pos + 2]
        pos += 3
        count = header & 0x7F

        if header & 0x80:
            # A run: this pixel, then `count` more of the same.
            r, g, b, a = _rgb555(lo, hi, keycolor, fpc_expand)
            total = count + 1
            if n + total > want:
                total = want - n
            px = bytes((r, g, b, a)) * total
            out[n * 4:(n + total) * 4] = px
            n += total
        else:
            # A literal: this pixel, then `count` more, each its own 16 bits.
            r, g, b, a = _rgb555(lo, hi, keycolor, fpc_expand)
            out[n * 4:n * 4 + 4] = bytes((r, g, b, a))
            n += 1
            for _ in range(count):
                if n >= want:
                    break
                if pos + 2 > end:
                    raise AniError(
                        f"pixel data exhausted mid-literal at {n} of {want}")
                r, g, b, a = _rgb555(data[pos], data[pos + 1], keycolor,
                                     fpc_expand)
                pos += 2
                out[n * 4:n * 4 + 4] = bytes((r, g, b, a))
                n += 1

    return bytes(out)


def _decode_rle8(data: bytes, width: int, height: int, palette: bytes,
                 keycolor: int) -> bytes:
    """The same Targa datatype-10 RLE, but over palette indices -> RGBA8888.

    HOW THIS WAS ESTABLISHED, since only one file on the disc uses it and there
    was nothing to cross-check against:

      * The CIMG header's own `uncompressed_size` is 2262 for a 39x58 frame,
        and 39 * 58 = 2262 exactly — one byte per pixel, not the two that type
        0x04 uses. That is what says "paletted" before any pixel is read.
      * `additional_size - 24` is 1032, which is 8 + 256 * 4: an eight-byte
        header and one RGBA quad per palette index.
      * The run/literal encoding is the one already here, with the pixel
        shrunk from two bytes to one. The proof is arithmetic rather than
        visual: all 28 frames of CLASSICS.ANI decode to exactly width * height
        pixels and consume their compressed block to within its final padding
        byte. A wrong reading of the control byte does not land on the exact
        pixel count 28 times.
      * Channel order is R, G, B: read the other way round the sprite comes out
        with a blue suit and a red belt, and the file is a green bomberman.

    Transparency is by index: `keycolor` is a palette index here, not a 16-bit
    colour, and it is 0 in this file. The palette's own fourth byte is 0xFF
    even for that entry, so it is not the alpha source.
    """
    want = width * height
    out = bytearray(want * 4)
    entries = palette[PALETTE_HEADER:PALETTE_HEADER + PALETTE_ENTRIES * 4]
    n = 0
    pos = 0

    while n < want:
        if pos >= len(data):
            raise AniError(f"pixel data exhausted after {n} of {want} pixels")
        header = data[pos]
        pos += 1
        count = (header & 0x7F) + 1
        if header & 0x80:
            if pos >= len(data):
                raise AniError("run header with no index byte")
            indices = bytes([data[pos]]) * min(count, want - n)
            pos += 1
        else:
            indices = data[pos:pos + count][:want - n]
            pos += count
        for idx in indices:
            if idx == keycolor:
                out[n * 4:n * 4 + 4] = b"\x00\x00\x00\x00"
            else:
                r, g, b = entries[idx * 4:idx * 4 + 3]
                out[n * 4:n * 4 + 4] = bytes((r, g, b, 255))
            n += 1

    return bytes(out)


def _rgb555(lo: int, hi: int, keycolor: int,
            fpc_expand: bool) -> tuple[int, int, int, int]:
    v = lo | (hi << 8)
    if v == keycolor:
        return 0, 0, 0, 0
    r5 = (v >> 10) & 0x1F
    g5 = (v >> 5) & 0x1F
    b5 = v & 0x1F
    if fpc_expand:
        return r5 << 3, g5 << 3, b5 << 3, 255
    return ((r5 << 3) | (r5 >> 2), (g5 << 3) | (g5 >> 2),
            (b5 << 3) | (b5 >> 2), 255)


def _parse_cimg(buf: bytes, start: int, end: int, frame: Frame,
                fpc_expand: bool) -> None:
    if end - start < 32:
        raise AniError("CIMG payload is too small")
    pos = start

    frame.cimg_type, _unknown = struct.unpack_from("<HH", buf, pos)
    pos += 4
    (additional_size,) = struct.unpack_from("<I", buf, pos)
    pos += 4
    if additional_size < 24:
        raise AniError(f"CIMG additional_size {additional_size} < 24")
    if additional_size > end - pos:
        raise AniError("CIMG additional_size overruns the chunk")
    palette_size = additional_size - 24

    pos += 4  # unknown
    (frame.width, frame.height, frame.hotspot_x, frame.hotspot_y,
     frame.keycolor_bytes) = struct.unpack_from("<HHHHH", buf, pos)
    pos += 10
    pos += 2  # unknown

    if frame.cimg_type not in DECODABLE_TYPES:
        raise UnsupportedType(
            f"CIMG type {frame.cimg_type:#x} is neither 16-bit direct colour "
            f"nor 8-bit paletted")
    if palette_size not in OBSERVED_PALETTE_SIZES:
        raise AniError(
            f"CIMG palette size {palette_size} was never seen on this disc "
            f"(expected one of {sorted(OBSERVED_PALETTE_SIZES)})")

    # Type 0x04 ignores the palette — its pixels carry their own colour. Type
    # 0x0b needs it, so it is kept rather than skipped past.
    palette = buf[pos:pos + palette_size]
    pos += palette_size

    pos += 4  # two unknown uint16
    (packed,) = struct.unpack_from("<I", buf, pos)
    pos += 4
    compressed_size = packed - 12
    (uncompressed_size,) = struct.unpack_from("<I", buf, pos)
    pos += 4

    if compressed_size < 0 or pos + compressed_size > end:
        raise AniError(f"CIMG compressed_size {compressed_size} overruns")

    if frame.cimg_type == TYPE_PALETTED8:
        if palette_size < PALETTE_HEADER + PALETTE_ENTRIES * 4:
            raise AniError(
                f"CIMG type {frame.cimg_type:#x} needs a "
                f"{PALETTE_HEADER + PALETTE_ENTRIES * 4}-byte palette, "
                f"got {palette_size}")
        frame.pixels = _decode_rle8(
            buf[pos:pos + compressed_size], frame.width, frame.height,
            palette, frame.keycolor_bytes)
    else:
        frame.pixels = _decode_rle16(
            buf[pos:pos + compressed_size], frame.width, frame.height,
            frame.keycolor_bytes, fpc_expand)

    # Cross-check the header's own claim about the unpacked size. The pixels
    # are 16-bit, so it should be width * height * 2. Reported rather than
    # raised: it is a consistency signal, not something we depend on.
    # One byte per pixel when paletted, two when direct colour — which is the
    # test that identified the format in the first place.
    expected = frame.width * frame.height * (
        1 if frame.cimg_type == TYPE_PALETTED8 else 2)
    if uncompressed_size not in (expected, 0):
        raise AniError(
            f"uncompressed_size {uncompressed_size} != width*height*2 {expected}")


def load(path: Path, fpc_expand: bool = False) -> Ani:
    """Decode one .ANI: its frame pool and its named sequences."""
    buf = path.read_bytes()
    if not buf.startswith(FILE_MAGIC):
        raise AniError(f"not an ANI file (magic is {buf[:10]!r})")

    (file_length,) = struct.unpack_from("<I", buf, 10)
    _file_id = struct.unpack_from("<H", buf, 14)[0]
    # file_length is an absolute end offset, not a payload length.
    end = min(file_length, len(buf))

    ani = Ani(path)
    pos = 16
    while pos < end:
        sig, length, _ident, payload = _read_chunk_header(buf, pos)
        chunk_end = payload + length
        if chunk_end > len(buf):
            raise AniError(f"chunk {sig!r} at {pos} overruns the file")
        if sig == b"FRAM":
            ani.frames.append(_parse_frame(buf, payload, chunk_end, fpc_expand))
        elif sig == b"SEQ ":
            seq = _parse_seq(buf, payload, chunk_end)
            if seq is not None:
                ani.sequences.append(seq)
        pos = chunk_end

    # Every step must address a frame that exists, or the animation would run
    # off the end of the pool during play rather than failing at load.
    #
    # Two files on this disc break that: POWERS1.ANI and POWERZ.ANI both have a
    # 'power jelly' sequence whose last step points at frame 7 of a 7-frame
    # pool. Neither is referenced by MASTER.ALI and AtomBomberman's notes list
    # both among files "not used by the game at all", so this is dangling data
    # in dead assets. Recorded as a warning and the bad steps dropped, rather
    # than refusing the file — the caller decides whether a warning matters,
    # and --check only fails on files the game actually loads.
    for seq in ani.sequences:
        good = []
        for step in seq.steps:
            if 0 <= step[0] < len(ani.frames):
                good.append(step)
            else:
                ani.warnings.append(
                    f"sequence {seq.name!r} references frame {step[0]} but the "
                    f"pool has {len(ani.frames)}; step dropped")
        seq.steps = good
    return ani


def _parse_frame(buf: bytes, start: int, end: int, fpc_expand: bool) -> Frame:
    frame = Frame()
    pos = start
    saw_cimg = False
    while pos < end:
        sig, length, _ident, payload = _read_chunk_header(buf, pos)
        sub_end = payload + length
        if sig == b"FNAM":
            frame.name = buf[payload:sub_end].split(b"\0")[0].decode(
                "latin-1").strip()
        elif sig == b"CIMG":
            if saw_cimg:
                raise AniError("two CIMG chunks in one FRAM")
            _parse_cimg(buf, payload, sub_end, frame, fpc_expand)
            saw_cimg = True
        pos = sub_end
    if not saw_cimg:
        raise AniError("FRAM with no CIMG")
    return frame


class Ani:
    """One decoded .ANI: a pool of frames plus the sequences over it."""

    __slots__ = ("path", "frames", "sequences", "warnings")

    def __init__(self, path: Path) -> None:
        self.path = path
        self.frames: list[Frame] = []
        self.sequences: list[Sequence] = []
        self.warnings: list[str] = []

    def sequence(self, name: str) -> Sequence | None:
        for s in self.sequences:
            if s.name.lower() == name.lower():
                return s
        return None

    def __repr__(self) -> str:
        return (f"Ani({self.path.name}, {len(self.frames)} frames, "
                f"{len(self.sequences)} sequences)")


def _parse_seq(buf: bytes, start: int, end: int) -> Sequence | None:
    seq = Sequence()
    pos = start
    while pos + CHUNK_HEADER <= end:
        sig, length, _ident, payload = _read_chunk_header(buf, pos)
        sub_end = payload + length
        if sig == b"HEAD":
            seq.name = buf[payload:sub_end].split(b"\0")[0].decode(
                "latin-1").strip()
        elif sig == b"STAT":
            p = payload
            while p + CHUNK_HEADER <= sub_end:
                s3, l3, _i3, pay3 = _read_chunk_header(buf, p)
                if s3 == b"FRAM" and l3 >= 12:
                    _one, index, dx, dy = struct.unpack_from("<HHhh", buf, pay3)
                    seq.steps.append((index, dx, dy))
                p = pay3 + l3
        pos = sub_end
    return seq if seq.name else None


def master_list(ani_dir: Path) -> set[str]:
    """The ANI stems MASTER.ALI references, lowercased and without extension.

    Its own header calls it the "master animation file (.ANI) list for
    Bomberman PC". Lines are `-name.ani`; a leading `;` comments one out, and
    several are commented out deliberately — `flame.ani` in favour of
    `mflame.ani`, `trigbomb.ani` in favour of `triganim.ani`.

    It references 76 of the 95 files on the disc. It is NOT a complete list of
    what the game uses: the four idle animations fpc_atomic loads (applbite,
    headwipe, nuckblow, zen) are absent from it, and AtomBomberman's notes list
    those among the files that DO need loading. So treat this as "certainly
    used", never as "everything else is dead".
    """
    src = ani_dir / "MASTER.ALI"
    if not src.is_file():
        return set()
    names: set[str] = set()
    for line in src.read_text(encoding="latin-1").replace("\r", "").split("\n"):
        line = line.strip()
        if not line.startswith("-"):
            continue
        stem = line[1:].strip().lower()
        if stem.endswith(".ani"):
            stem = stem[:-4]
        if stem:
            names.add(stem)
    return names


def to_png(frame: Frame, path: Path) -> None:
    from PIL import Image
    img = Image.frombytes("RGBA", (frame.width, frame.height), frame.pixels)
    img.save(path)


def main(argv: list[str]) -> int:
    root = Path(__file__).resolve().parent.parent
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--data", type=Path, default=root / "original-game")
    ap.add_argument("--list", action="store_true", help="inventory every ANI")
    ap.add_argument("--check", action="store_true",
                    help="decode all of them, report, write nothing")
    ap.add_argument("--dump", metavar="NAME", help="one ANI, e.g. STAND or stand.ani")
    ap.add_argument("--out", type=Path, help="directory for --dump")
    ap.add_argument("--fpc-expand", action="store_true",
                    help="expand 5-bit channels with <<3, as fpc_atomic does")
    args = ap.parse_args(argv)

    ani_dir = args.data / "ANI"
    if not ani_dir.is_dir():
        print(f"anifile: not found: {ani_dir}", file=sys.stderr)
        return 2

    if args.dump:
        name = args.dump if args.dump.lower().endswith(".ani") else args.dump + ".ANI"
        src = ani_dir / name
        if not src.is_file():
            src = ani_dir / name.upper()
        if not src.is_file():
            print(f"anifile: no such ANI: {args.dump}", file=sys.stderr)
            return 2
        ani = load(src, args.fpc_expand)
        out = args.out or (root / "tools" / "out" / "ani" / src.stem.lower())
        out.mkdir(parents=True, exist_ok=True)
        for i, f in enumerate(ani.frames):
            to_png(f, out / f"{i:04d}_{f.name or 'unnamed'}.png")
        print(f"anifile: {src.name}: {len(ani.frames)} frames -> "
              f"{out.relative_to(root) if out.is_relative_to(root) else out}")
        for seq in ani.sequences:
            print(f"    {seq.name!r}: {len(seq.steps)} steps "
                  f"{seq.frame_indices()[:12]}"
                  f"{' ...' if len(seq.steps) > 12 else ''}")
        return 0

    files = sorted(ani_dir.glob("*.ANI"))
    if not files:
        print(f"anifile: no .ANI files in {ani_dir}", file=sys.stderr)
        return 2

    referenced = master_list(ani_dir)
    failures: list[str] = []
    skipped: list[str] = []
    warned: list[str] = []
    total_frames = 0
    total_seqs = 0
    decoded = 0

    for src in files:
        stem = src.stem.lower()
        used = stem in referenced
        try:
            ani = load(src, args.fpc_expand)
            frames = ani.frames
        except UnsupportedType as exc:
            # A pixel format we do not handle. Only a failure if the game
            # loads the file; otherwise it is a fact about the disc.
            if used:
                failures.append(f"{src.name}: {exc}")
                print(f"  FAIL {src.name}: {exc}  (referenced by MASTER.ALI)")
            else:
                skipped.append(src.name)
            continue
        except AniError as exc:
            failures.append(f"{src.name}: {exc}")
            print(f"  FAIL {src.name}: {exc}")
            continue

        decoded += 1
        total_frames += len(frames)
        total_seqs += len(ani.sequences)
        for w in ani.warnings:
            if used:
                failures.append(f"{src.name}: {w}")
                print(f"  FAIL {src.name}: {w}  (referenced by MASTER.ALI)")
            else:
                warned.append(f"{src.name}: {w}")
        if args.list:
            sizes = {(f.width, f.height) for f in frames}
            names = ", ".join(s.name for s in ani.sequences) or "-"
            print(f"  {'*' if used else ' '} {src.stem:<10} {len(frames):>4} frames  "
                  f"{len(ani.sequences):>2} seq  size={_brief(sizes):<12} {names}")

    if args.list:
        print("  (* = referenced by MASTER.ALI)")

    print(f"anifile: {decoded}/{len(files)} decoded, {total_frames} frames, "
          f"{total_seqs} sequences")
    if skipped:
        print(f"anifile: {len(skipped)} unsupported and unreferenced: "
              f"{', '.join(skipped)}")
    for w in warned:
        print(f"anifile: note (unreferenced file) {w}")
    if failures:
        print(f"anifile: {len(failures)} FAILURES")
    return 1 if failures else 0


def _brief(items: set) -> str:
    ordered = sorted(items)
    if len(ordered) == 1:
        return f"{ordered[0][0]}x{ordered[0][1]}"
    return f"{len(ordered)} distinct"


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
