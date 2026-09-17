#!/usr/bin/env python3
"""The ABPK container: one file holding a JSON manifest and many blobs.

Two packs use it — the art pack (tools/pack_assets.py) and the sound pack
(tools/rss.py) — and they use the same reader on the Godot side
(scripts/render/pack.gd, scripts/audio/sfx.gd), so the format lives here rather
than being written twice and drifting.

WHY A CONTAINER AT ALL. Godot's importer claims any `.png` under res://,
converts it to its own compressed texture and STRIPS the source from an export
— so the first web build shipped 58 file names and none of the bytes. Adding a
`.gdignore` stops the importer but also removes the files from the index, so
`include_filter` can no longer see them either. Neither half works alone. A
single unknown-extension file sidesteps both: nothing imports it, one
`include_filter` entry ships it, the bytes arrive unmodified, and a browser
makes one request instead of hundreds.

Layout, little-endian:

    "ABPK"  4 bytes
    u32     format version
    u32     manifest length
    ...     manifest JSON, UTF-8
    ...     the blobs, concatenated

The manifest's own `blobs` key is written here: name -> [offset, length] into
the blob region, offsets relative to the end of the manifest. A reader needs
nothing but this file.
"""

from __future__ import annotations

import json
from pathlib import Path

MAGIC = b"ABPK"
VERSION = 1


def write(path: Path, manifest: dict, blobs: dict[str, bytes]) -> int:
    """Write one container. Returns its size in bytes.

    `manifest` is copied, not mutated: its `blobs` key is replaced with the
    computed offset table, so calling this twice with the same dict is safe.
    """
    order = sorted(blobs)
    offsets: dict[str, tuple[int, int]] = {}
    cursor = 0
    for name in order:
        offsets[name] = (cursor, len(blobs[name]))
        cursor += len(blobs[name])

    manifest = dict(manifest)
    manifest["blobs"] = {n: list(offsets[n]) for n in order}

    body = json.dumps(manifest, separators=(",", ":")).encode("utf-8")
    out = bytearray()
    out += MAGIC
    out += VERSION.to_bytes(4, "little")
    out += len(body).to_bytes(4, "little")
    out += body
    for name in order:
        out += blobs[name]
    path.write_bytes(out)
    return len(out)


def read(path: Path) -> tuple[dict, dict[str, bytes]]:
    """Inverse of write(). Raises ValueError if the file is not a container.

    Only the tests use this — Godot has its own reader — and that is the point:
    a round-trip here proves the layout is what the manifest claims before any
    of it reaches the game.
    """
    data = path.read_bytes()
    if len(data) < 12 or data[:4] != MAGIC:
        raise ValueError(f"{path} is not an ABPK container")
    version = int.from_bytes(data[4:8], "little")
    if version != VERSION:
        raise ValueError(f"{path}: container version {version}, expected {VERSION}")
    manifest_len = int.from_bytes(data[8:12], "little")
    if 12 + manifest_len > len(data):
        raise ValueError(f"{path}: manifest length {manifest_len} exceeds the file")
    manifest = json.loads(data[12:12 + manifest_len].decode("utf-8"))
    base = 12 + manifest_len
    blobs = {}
    for name, (offset, length) in manifest.get("blobs", {}).items():
        start = base + offset
        if start + length > len(data):
            raise ValueError(f"{path}: blob {name} runs past the end")
        blobs[name] = data[start:start + length]
    return manifest, blobs
