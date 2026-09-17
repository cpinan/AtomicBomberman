#!/usr/bin/env python3
"""The disc's remaining containers, opened rather than asserted about.

Five files on the CD were once excluded from the extraction with a one-line
reason each, and three of those reasons were wrong. This tool exists so that
no file is dismissed on the strength of its extension:

    THEME/THEME.ZIP     called "a Windows 95 desktop theme". It is — and it
                        holds 40 members of ORIGINAL ART: two multi-megabyte
                        bitmaps, eight icons, thirteen cursors, five animated
                        cursors and fourteen WAVs, none of which appear
                        anywhere else on the disc.
    INTRO/BMINTRO.EXE   called "a separate 16-bit program". It is 15.8 MB and
                        it CONTAINS THE GAME'S INTRO: an Interplay MVE movie,
                        640x480, 858 chunks, 22 050 Hz stereo audio, starting
                        at offset 0x11400.
    TRAILER.SFA         called "a video trailer for another Interplay title",
                        which was never checked. What is measurable: it is an
                        Interplay MVE movie, 640x480, 1 205 chunks, 19.8 MB.
                        Whose trailer it is, this tool does not claim.
    BM95.RES            "the Win32 window chrome" — true, and it has five real
                        bitmaps in it, which are extracted here rather than
                        described.
    OOO_LTD.CXT         a Macromedia Director cast: 324 cast members and 280
                        Lingo scripts, and NO bitmap chunks, so it is the
                        intro's code rather than its art.

WHAT IS AND IS NOT DECODED. The MVE movies are sliced out whole, as `.mve`
files. Their video is an opcode-based codec and their audio is DPCM — flags
0xA817 says stereo, 16-bit, compressed — and writing a decoder for either
would be shipping something this repo cannot verify. ffmpeg and VLC both read
Interplay MVE natively, so the useful act is to hand over the stream, not to
re-implement it. That boundary is stated rather than hidden.

    tools/containers.py             report on all five
    tools/containers.py --extract   write out everything extractable
    tools/containers.py --check     open and verify them, write nothing
"""

from __future__ import annotations

import argparse
import json
import struct
import sys
import zipfile
from collections import Counter
from pathlib import Path

MVE_SIG = b"Interplay MVE File\x1a\x00"


# --------------------------------------------------------------------- MVE

def mve_scan(blob: bytes, start: int) -> dict:
    """Walk one MVE's chunk/opcode stream and report what it holds."""
    pos = start + 26  # 20-byte signature plus a six-byte header
    chunks = 0
    ops: Counter = Counter()
    video = None
    audio = None
    audio_bytes = 0

    while pos + 4 <= len(blob):
        clen, ctype = struct.unpack("<HH", blob[pos:pos + 4])
        pos += 4
        if ctype > 0x10:
            break
        end = pos + clen
        if end > len(blob):
            break
        while pos + 3 <= end:
            olen, op, _ver = struct.unpack("<HBB", blob[pos:pos + 4])
            pos += 4
            ops[op] += 1
            payload = blob[pos:pos + olen]
            if op == 0x03 and len(payload) >= 6:
                _unk, flags, rate = struct.unpack("<HHH", payload[:6])
                audio = {"rate": rate, "flags": flags,
                         "stereo": bool(flags & 1), "bits": 16 if flags & 2 else 8,
                         "compressed": bool(flags & 4)}
            elif op == 0x0A and len(payload) >= 4:
                video = list(struct.unpack("<HH", payload[:4]))
            elif op in (0x08, 0x09):
                audio_bytes += olen
            pos += olen
        chunks += 1
        pos = end
        # Opcode 0 is end-of-stream; stopping there is what makes the byte
        # length below the movie's real length rather than the rest of the file.
        if ops.get(0):
            break

    return {"start": start, "end": pos, "bytes": pos - start,
            "chunks": chunks, "video": video, "audio": audio,
            "audio_bytes": audio_bytes, "opcodes": dict(sorted(ops.items()))}


def find_mves(blob: bytes) -> list[int]:
    """Offsets of real MVE streams — the signature alone is not enough.

    BMINTRO.EXE mentions the signature three times; only one of them is
    followed by a parsable chunk stream, the other two being the string as the
    program's own data.
    """
    out = []
    i = 0
    while True:
        i = blob.find(MVE_SIG[:18], i)
        if i < 0:
            return out
        # A real stream announces its video mode and its audio format. The
        # signature on its own is not enough: BMINTRO.EXE carries the string
        # three times, and one of those parses into 255 chunks of nothing.
        info = mve_scan(blob, i)
        if info["chunks"] > 2 and info["video"] and info["audio"]:
            out.append(i)
        i += 1


# ------------------------------------------------------------ Watcom .RES

def dib_to_png(blob: bytes, at: int, out: Path) -> tuple[int, int] | None:
    """One BITMAPINFOHEADER-and-palette image out of a resource file.

    Icons and cursors store the colour image and its AND mask stacked, so the
    stated height is twice the real one; only the top half is the picture.
    """
    from PIL import Image

    size, w, h, planes, bpp = struct.unpack("<IiiHH", blob[at:at + 16])
    if size != 40 or planes != 1 or bpp not in (1, 4, 8, 24):
        return None
    real_h = abs(h) // 2 if abs(h) == 2 * w or abs(h) % 2 == 0 and abs(h) > w else abs(h)
    ncol = 0 if bpp == 24 else 1 << bpp
    pal_at = at + 40
    palette = [tuple(blob[pal_at + i * 4 + 2::-1][:3]) for i in range(ncol)]
    bits_at = pal_at + ncol * 4
    stride = ((w * bpp + 31) // 32) * 4

    img = Image.new("RGB", (w, real_h))
    px = img.load()
    for y in range(real_h):
        row_at = bits_at + (real_h - 1 - y) * stride
        row = blob[row_at:row_at + stride]
        if len(row) < stride:
            return None
        for x in range(w):
            if bpp == 8:
                idx = row[x]
            elif bpp == 4:
                idx = (row[x // 2] >> 4) if x % 2 == 0 else (row[x // 2] & 0x0F)
            elif bpp == 1:
                idx = (row[x // 8] >> (7 - x % 8)) & 1
            else:
                px[x, y] = (row[x * 3 + 2], row[x * 3 + 1], row[x * 3])
                continue
            px[x, y] = palette[idx] if idx < len(palette) else (0, 0, 0)
    img.save(out)
    return w, real_h


def scan_res(blob: bytes) -> list[int]:
    """Offsets of the DIB headers inside a Watcom .RES."""
    hits = []
    for i in range(len(blob) - 16):
        if struct.unpack("<I", blob[i:i + 4])[0] != 40:
            continue
        w, h, planes, bpp = struct.unpack("<iiHH", blob[i + 4:i + 16])
        if 0 < w <= 1024 and 0 < abs(h) <= 2048 and planes == 1 and bpp in (1, 4, 8, 24):
            hits.append(i)
    return hits


# ------------------------------------------------------------------- main

def main(argv: list[str]) -> int:
    root = Path(__file__).resolve().parent.parent

    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--data", type=Path, default=root / "original-game")
    ap.add_argument("--out", type=Path, default=root / "tools" / "out")
    ap.add_argument("--extract", action="store_true", help="write everything out")
    ap.add_argument("--check", action="store_true", help="open and verify, write nothing")
    args = ap.parse_args(argv)

    report: dict = {}
    problems: list[str] = []

    # --- THEME.ZIP
    zpath = args.data / "THEME" / "THEME.ZIP"
    if zpath.is_file():
        with zipfile.ZipFile(zpath) as z:
            members = z.infolist()
            kinds = Counter(Path(m.filename).suffix.lower() for m in members)
            report["theme_zip"] = {
                "members": len(members),
                "bytes": sum(m.file_size for m in members),
                "kinds": dict(sorted(kinds.items())),
            }
            print(f"containers: THEME.ZIP    {len(members)} members, "
                  f"{sum(m.file_size for m in members) / 1e6:.1f} MB — "
                  + ", ".join(f"{n}{k}" for k, n in sorted(kinds.items())))
            if args.extract:
                dest = args.out / "theme"
                dest.mkdir(parents=True, exist_ok=True)
                for m in members:
                    if m.is_dir():
                        continue
                    (dest / Path(m.filename).name).write_bytes(z.read(m))
                print(f"containers:              -> {dest.relative_to(root)}/")
    else:
        problems.append(f"missing {zpath}")

    # --- BM95.RES
    rpath = args.data / "BM95.RES"
    if rpath.is_file():
        blob = rpath.read_bytes()
        magic = bytes(c & 0x7F for c in blob[:8])
        hits = scan_res(blob)
        report["bm95_res"] = {"magic": magic.decode("ascii", "replace"),
                              "bitmaps": len(hits)}
        print(f"containers: BM95.RES     {magic.decode('ascii', 'replace')}, "
              f"{len(hits)} bitmaps")
        if args.extract:
            dest = args.out / "winres"
            dest.mkdir(parents=True, exist_ok=True)
            written = 0
            for at in hits:
                got = dib_to_png(blob, at, dest / f"res_{at:06x}.png")
                if got:
                    written += 1
            print(f"containers:              -> {written} PNGs in "
                  f"{dest.relative_to(root)}/")
    else:
        problems.append(f"missing {rpath}")

    # --- OOO_LTD.CXT
    cpath = args.data / "OOO_LTD.CXT"
    if cpath.is_file():
        blob = cpath.read_bytes()
        tally = {t.decode(): blob.count(t)
                 for t in (b"CASt", b"Lscr", b"STXT", b"BITD", b"snd ")}
        report["director_cast"] = {"magic": blob[:4].decode("ascii", "replace"),
                                   "chunks": tally}
        print(f"containers: OOO_LTD.CXT  {blob[:4].decode('ascii', 'replace')} cast — "
              + ", ".join(f"{v} {k.strip()}" for k, v in tally.items() if v))
        # No extraction: with no BITD chunks there is no bitmap to take out,
        # and Lingo bytecode is not something this port can use.

    # --- the two MVE movies
    movies = []
    for path, label in ((args.data / "TRAILER.SFA", "TRAILER.SFA"),
                        (args.data / "INTRO" / "BMINTRO.EXE", "BMINTRO.EXE")):
        if not path.is_file():
            problems.append(f"missing {path}")
            continue
        blob = path.read_bytes()
        for start in find_mves(blob):
            info = mve_scan(blob, start)
            info["source"] = label
            movies.append(info)
            v = info["video"] or ["?", "?"]
            a = info["audio"] or {}
            print(f"containers: {label:<12} MVE at {start:#08x}: "
                  f"{info['chunks']} chunks, {v[0]}x{v[1]}, "
                  f"{a.get('rate', '?')} Hz "
                  f"{'stereo' if a.get('stereo') else 'mono'} "
                  f"{a.get('bits', '?')}-bit"
                  f"{', DPCM' if a.get('compressed') else ''}, "
                  f"{info['bytes'] / 1e6:.1f} MB")
            if args.extract:
                dest = args.out / "movies"
                dest.mkdir(parents=True, exist_ok=True)
                name = f"{Path(label).stem.lower()}_{start:06x}.mve"
                (dest / name).write_bytes(blob[start:info["end"]])
                print(f"containers:              -> {dest.relative_to(root)}/{name}"
                      "  (play with ffmpeg/VLC; no decoder here)")
    report["movies"] = movies

    print(f"\ncontainers: {report.get('theme_zip', {}).get('members', 0)} theme "
          f"members, {report.get('bm95_res', {}).get('bitmaps', 0)} resource bitmaps, "
          f"{len(movies)} MVE movies")
    for bad in problems:
        print(f"  problem: {bad}", file=sys.stderr)
    if problems:
        return 1

    if args.check:
        return 0

    dest = args.out / "containers.json"
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_text(json.dumps(report, indent=1), encoding="utf-8")
    print(f"containers: wrote {dest.relative_to(root)}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
