#!/usr/bin/env python3
"""Unpack `INSTALL.DAT` — a compressed archive, not the manifest it looks like.

This file was written off once already, as "the installer's own manifest: 22
names, sizes and CRCs". That was wrong, and the way it was wrong is the reason
this tool exists: the 22 names are followed by 173 KB nobody had explained, and
eighteen of the names are files that **exist nowhere else on the disc**. An
extraction that skips this one is not an extraction of the disc.

WHAT IS IN IT. Twenty-two members, 646,034 bytes unpacked from 173,193:

    AB.PCX          the setup program's 640x480 backdrop — 399 KB, off-disc
    POINTER.PCX     the setup cursor art — off-disc
    LOGOBACK.PCX    the setup logo plate and its bar — both off-disc
    LOGOBAR.PCX
    FONT2/4/5/8.FON four more bitmap fonts in the same format tools/fonts.py
                    reads; the disc's install root ships only 0, 1 and 6
    FONT0-4.AAF     five files of a SECOND font format, magic "AAFF", which
                    appears nowhere else on the disc
    COLOR.PAL       byte-identical to the disc's copy
    FONT0.FON       byte-identical to the disc's copy
    FONT1/6.FON     SAME NAMES, DIFFERENT FILES — the installer carries its own
                    faces, so a name match is not a content match
    INSTALL.INI     the installer's script
    MIN/MED/MAX.TXT the three install sizes, as file lists
    IPUNINST.EXE    the uninstaller

THE CONTAINER, big-endian where it counts:

    0x00  u32 x4      1, 10, 0, 0x82FCF318 — version, count-ish, and a stamp
    then, per member:
        u8          name length
        ...         name, ASCII
        u32         flags; 0x40 on every member, 0x16 on the "." root entry
        u32         offset of the member's data, absolute
        u32         unpacked size
        u32         packed size

The offsets chain exactly — the first member starts at 609, which is where the
table ends, each member begins where the previous one stopped, and the last
ends at byte 173,802, the length of the file. That is what identifies the four
fields; nothing else fits.

THE CODEC is Okumura's LZSS, in chunks:

    per chunk:  u16 big-endian packed length, then the LZSS stream
    ring        4096 bytes, RESET PER CHUNK, initialised to 0x20 (space)
    control     one byte, LSB first; 1 = literal byte
    match       two bytes: offset = lo | (hi & 0xF0) << 4, length = (hi & 0xF) + 3

Every one of those was forced by evidence rather than guessed:

  * FONT0.FON is in the archive AND on the disc, so it is known plaintext. The
    ring's 0x20 fill is the reason: with a zero-filled ring the decode diverges
    at byte 2254, where the original has a run of spaces.
  * The chunking is why the five largest members decoded short at first. The
    two bytes ahead of each stream are a length: 0x04E5 = 1253 = FONT0.FON's
    1255 packed bytes minus the two. Small members have one chunk, which is
    why 17 of 22 came out right while AB.PCX stopped at a quarter.
  * With chunking, COLOR.PAL comes out byte-identical to the disc's copy, and
    all 22 reach their stated size exactly. Two independent files reproduced
    bit-for-bit is the proof; the rest is consistency.

    tools/installdat.py             list the members
    tools/installdat.py --extract   write them to tools/out/install/
    tools/installdat.py --check     unpack in memory, verify sizes, write nothing
"""

from __future__ import annotations

import argparse
import json
import struct
import sys
from pathlib import Path

HEADER = 0x10
RING = 4096
RING_INIT = 0x20
MIN_MATCH = 3


class ArchiveError(Exception):
    pass


def _lzss_chunk(data: bytes, out: bytearray, limit: int) -> None:
    """One chunk, into `out`, stopping at `limit` bytes of output."""
    ring = bytearray([RING_INIT]) * RING
    r = RING - 18
    i = 0
    flags = 0
    bits = 0
    start = len(out)
    while len(out) - start < limit and i < len(data):
        if bits == 0:
            flags = data[i]
            i += 1
            bits = 8
        if flags & 1:
            c = data[i]
            i += 1
            out.append(c)
            ring[r] = c
            r = (r + 1) % RING
        else:
            if i + 1 >= len(data):
                break
            lo, hi = data[i], data[i + 1]
            i += 2
            off = lo | ((hi & 0xF0) << 4)
            for k in range((hi & 0x0F) + MIN_MATCH):
                c = ring[(off + k) % RING]
                out.append(c)
                ring[r] = c
                r = (r + 1) % RING
        flags >>= 1
        bits -= 1


def unpack_member(blob: bytes, offset: int, packed: int, unpacked: int) -> bytes:
    out = bytearray()
    pos, end = offset, offset + packed
    while len(out) < unpacked and pos + 2 <= end:
        clen = struct.unpack(">H", blob[pos:pos + 2])[0]
        pos += 2
        _lzss_chunk(blob[pos:pos + clen], out, unpacked - len(out))
        pos += clen
    return bytes(out)


def read_table(blob: bytes) -> list[dict]:
    entries = []
    pos = HEADER
    while pos + 17 <= len(blob):
        n = blob[pos]
        if not 1 <= n <= 30:
            break
        name = blob[pos + 1:pos + 1 + n]
        if not all(32 <= c < 127 for c in name):
            break
        flags, offset, unpacked, packed = struct.unpack(
            ">4I", blob[pos + 1 + n:pos + 17 + n])
        entries.append({
            "name": name.decode("ascii"),
            "flags": flags,
            "offset": offset,
            "unpacked": unpacked,
            "packed": packed,
        })
        pos += 17 + n
    if not entries:
        raise ArchiveError("no member table")

    # The chain is the check that the four fields were read in the right
    # order: each member must begin where the previous one ended, and the last
    # must end at the end of the file. A wrong field order breaks this at the
    # second member.
    # The root entry ("." with no extension) uses these four fields for
    # something else — its "packed" is the 0x82FC... stamp — so it is not part
    # of the chain and would break the check if it were.
    data = [e for e in entries if "." in e["name"][1:]]
    for a, b in zip(data, data[1:]):
        if a["offset"] + a["packed"] != b["offset"]:
            raise ArchiveError(
                f"{a['name']} ends at {a['offset'] + a['packed']} but "
                f"{b['name']} starts at {b['offset']} — the chain is broken")
    last = data[-1]
    if last["offset"] + last["packed"] != len(blob):
        raise ArchiveError(
            f"the last member ends at {last['offset'] + last['packed']}, "
            f"the file is {len(blob)} bytes")
    return entries


def main(argv: list[str]) -> int:
    root = Path(__file__).resolve().parent.parent

    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--data", type=Path, default=root / "original-game")
    ap.add_argument("--out", type=Path, default=root / "tools" / "out" / "install")
    ap.add_argument("--extract", action="store_true", help="write the members out")
    ap.add_argument("--check", action="store_true",
                    help="unpack in memory, verify, write nothing")
    args = ap.parse_args(argv)

    src = args.data / "INSTALL.DAT"
    if not src.is_file():
        print(f"installdat: not found: {src}", file=sys.stderr)
        return 2
    blob = src.read_bytes()

    try:
        entries = read_table(blob)
    except ArchiveError as exc:
        print(f"installdat: {src.name}: {exc}", file=sys.stderr)
        return 1

    if args.extract:
        args.out.mkdir(parents=True, exist_ok=True)

    report: list[dict] = []
    short = 0
    for e in entries:
        name = e["name"]
        # The root entry names the install directory rather than a file.
        if not e["packed"] or "." not in name[1:]:
            print(f"installdat: {name:<13} {'':>9}  the install root, not a file")
            continue

        got = unpack_member(blob, e["offset"], e["packed"], e["unpacked"])
        exact = len(got) == e["unpacked"]
        if not exact:
            short += 1

        # Where the disc has a file of the same name, say whether it is the
        # same file. Three of them are not, which is the trap: the installer
        # ships its own FONT1.FON and FONT6.FON under the game's names.
        on_disc = args.data / name
        if on_disc.is_file():
            same = on_disc.read_bytes() == got
            note = "same as the disc's copy" if same else "DIFFERENT from the disc's copy"
        else:
            same = None
            note = "not on the disc at all"

        print(f"installdat: {name:<13} {e['unpacked']:>7}B from {e['packed']:>6}B  "
              f"{'ok  ' if exact else 'SHORT'} {note}")
        report.append({**e, "decoded": len(got), "exact": exact,
                       "on_disc": on_disc.is_file(), "same_as_disc": same})

        if args.extract:
            (args.out / name).write_bytes(got)

    off_disc = [r["name"] for r in report if not r["on_disc"]]
    differs = [r["name"] for r in report if r["same_as_disc"] is False]
    print(f"\ninstalldat: {len(report)} members, "
          f"{sum(r['unpacked'] for r in report):,} bytes unpacked from "
          f"{sum(r['packed'] for r in report):,}")
    print(f"  {len(off_disc)} exist nowhere else on the disc: {', '.join(off_disc)}")
    print(f"  {len(differs)} share a name with a disc file but differ: "
          f"{', '.join(differs) or 'none'}")
    if short:
        print(f"  {short} member(s) decoded SHORT — the codec is wrong for them",
              file=sys.stderr)
        return 1

    if args.check:
        return 0

    out_json = root / "tools" / "out" / "installdat.json"
    out_json.parent.mkdir(parents=True, exist_ok=True)
    out_json.write_text(json.dumps(report, indent=1), encoding="utf-8")
    print(f"installdat: wrote {out_json.relative_to(root)}")
    if args.extract:
        print(f"installdat: wrote {len(report)} files to {args.out.relative_to(root)}/")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
