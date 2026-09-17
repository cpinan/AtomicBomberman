#!/usr/bin/env python3
"""The art kit: take a pack apart into editable PNGs, and put one back together.

---------------------------------------------------------------------------
WHY THIS EXISTS
---------------------------------------------------------------------------
Every sprite, screen and font this port draws is the original's, so a public
build of it is not legally shippable — `tools/build_web.sh` says so and means
it. The way out has always been a REPLACEMENT art pack: the same manifest, the
same frame names and hotspots, different pixels. Nothing in the game knows
which pack it loaded; `scripts/render/pack.gd` says so in its first paragraph.

What was missing was the middle: a way for somebody with a drawing program to
see what a pack must contain, paint it, and get a pack back out. That is this.

---------------------------------------------------------------------------
THE THREE COMMANDS
---------------------------------------------------------------------------
    artpack.py --template KIT     take a pack apart into KIT/ as one PNG per
                                  frame, with every hotspot recorded beside it
    artpack.py --check KIT        say what a kit is missing or has broken,
                                  before a build wastes anyone's time
    artpack.py --build KIT        put a kit back together as a pack the game
                                  loads, both loose and as a .bin container

A kit is a plain directory of PNGs and small JSON files. Nothing in it is
generated code and nothing in it depends on this project's data formats: an
artist opens a PNG, paints it, and the size and hotspot they leave behind is
what the game uses.

---------------------------------------------------------------------------
THE ONE RULE THAT MATTERS: HOTSPOTS
---------------------------------------------------------------------------
A frame is positioned by its hotspot, not by its rectangle — that is the whole
reason this port draws the original's animations correctly where fpc_atomic
does not (`scripts/render/pack.gd`). So every frame's hotspot travels with it,
in `frames.json` beside the PNGs, in the frame's own pixels: the hotspot is a
point INSIDE the frame, measured from its top-left.

If you resize a frame, move its hotspot to match, or the sprite will walk with
its feet in the wrong place. `--check` catches a hotspot that has fallen
outside its frame; it cannot catch one that is merely wrong.

---------------------------------------------------------------------------
WHAT A REPLACEMENT PACK NEEDS
---------------------------------------------------------------------------
`--check` prints the list, from the kit's own `kit.json`, which `--template`
writes out of the pack it took apart. In outline:

    sheets/       37 animation sheets, each a folder of numbered frames plus
                  frames.json (hotspots) and sequences.json (named animations)
    screens/      25 full screens, 640x480
    elements/     9 loose pieces of screen art
    backgrounds/  11 playfield backgrounds, one per level
    powerups/     14 powerup icons
    fonts/        2 bitmap fonts, each a strip plus its glyph table

Schemes and the colour-remap tables are NOT art and are copied straight from
the source pack when one is given (`--from`), or omitted. A pack with no remap
tables draws players in their sheet's own colours, which is what a replacement
set should do anyway: paint ten bombermen rather than one and a lookup table.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import abpk  # noqa: E402


KIT_VERSION = 1

## The parts of a manifest that are art, and the folder each becomes.
IMAGE_GROUPS = {
    "screens": "screens",
    "elements": "elements",
    "backgrounds": "backgrounds",
}


def _pil():
    try:
        from PIL import Image
    except ImportError:  # pragma: no cover - environment problem, not logic
        raise SystemExit("artpack: this needs Pillow (pip install pillow)")
    return Image


def read_pack(path: Path) -> tuple[dict, dict]:
    """A pack, from either form: <name>.bin or <name>/ with pack.json."""
    if path.suffix == ".bin" or path.with_suffix(".bin").exists():
        container = path if path.suffix == ".bin" else path.with_suffix(".bin")
        manifest, blobs = abpk.read(container)
        return manifest, blobs
    manifest = json.loads((path / "pack.json").read_text(encoding="utf-8"))
    blobs = {p.name: p.read_bytes() for p in path.glob("*.png")}
    return manifest, blobs


# ---------------------------------------------------------------------------
# --template: a pack, taken apart
# ---------------------------------------------------------------------------
def template(pack: Path, kit: Path) -> dict:
    Image = _pil()
    import io

    manifest, blobs = read_pack(pack)
    kit.mkdir(parents=True, exist_ok=True)

    def image_of(name: str):
        return Image.open(io.BytesIO(blobs[name])).convert("RGBA")

    counts = {"sheets": 0, "frames": 0, "screens": 0, "elements": 0,
              "backgrounds": 0, "powerups": 0, "fonts": 0}

    # --- the animation sheets, cut into one PNG per frame
    for name, entry in sorted(manifest.get("sheets", {}).items()):
        sheet_dir = kit / "sheets" / name
        (sheet_dir / "frames").mkdir(parents=True, exist_ok=True)
        sheet = image_of(entry["sheet"])
        frames = []
        for i, frame in enumerate(entry["frames"]):
            x, y, w, h = frame["rect"]
            sheet.crop((x, y, x + w, y + h)).save(
                sheet_dir / "frames" / f"{i:03d}.png")
            frames.append({
                "index": i,
                "hotspot": list(frame["hotspot"]),
                "name": frame.get("name", ""),
            })
            counts["frames"] += 1
        (sheet_dir / "frames.json").write_text(
            json.dumps(frames, indent=1), encoding="utf-8")
        (sheet_dir / "sequences.json").write_text(
            json.dumps(entry.get("sequences", {}), indent=1), encoding="utf-8")
        counts["sheets"] += 1

    # --- the flat image groups
    for group, folder in IMAGE_GROUPS.items():
        out = kit / folder
        out.mkdir(parents=True, exist_ok=True)
        for name, entry in sorted(manifest.get(group, {}).items()):
            image_of(entry["file"]).save(out / f"{name}.png")
            counts[group] += 1

    # --- powerups: a still or an animation, as the pack has it
    out = kit / "powerups"
    out.mkdir(parents=True, exist_ok=True)
    powerups = {}
    for name, entry in sorted(manifest.get("powerups", {}).items()):
        if "file" in entry:
            image_of(entry["file"]).save(out / f"{name}.png")
            powerups[name] = {"hotspot": list(entry.get("hotspot", [0, 0]))}
        else:
            # An animated powerup keeps its steps, which name frames of a
            # sheet rather than pixels of their own.
            powerups[name] = {"steps": entry.get("steps", [])}
        counts["powerups"] += 1
    (out / "powerups.json").write_text(
        json.dumps(powerups, indent=1), encoding="utf-8")

    # --- fonts: the strip plus its glyph table
    out = kit / "fonts"
    out.mkdir(parents=True, exist_ok=True)
    for name, entry in sorted(manifest.get("fonts", {}).items()):
        image_of(entry["file"]).save(out / f"{name}.png")
        (out / f"{name}.json").write_text(json.dumps({
            "height": entry.get("height", 0),
            "glyphs": entry.get("glyphs", {}),
        }, indent=1), encoding="utf-8")
        counts["fonts"] += 1

    kit_manifest = {
        "kit_version": KIT_VERSION,
        "note": ("An art kit for the Atomic Bomberman port. Paint over these "
                 "PNGs and run tools/artpack.py --build to get a pack the "
                 "game loads. docs/ART.md is the guide."),
        "from": str(pack),
        "counts": counts,
        # The contract a replacement must satisfy, so --check needs nothing but
        # the kit itself.
        "required": {
            "sheets": {
                name: {
                    "frames": len(entry["frames"]),
                    "sequences": sorted(entry.get("sequences", {})),
                }
                for name, entry in sorted(manifest.get("sheets", {}).items())
            },
            "screens": sorted(manifest.get("screens", {})),
            "elements": sorted(manifest.get("elements", {})),
            "backgrounds": sorted(manifest.get("backgrounds", {})),
            "powerups": sorted(manifest.get("powerups", {})),
            "fonts": sorted(manifest.get("fonts", {})),
        },
    }
    (kit / "kit.json").write_text(
        json.dumps(kit_manifest, indent=1), encoding="utf-8")
    return kit_manifest


# ---------------------------------------------------------------------------
# --check: what is missing, before anyone waits for a build
# ---------------------------------------------------------------------------
def check(kit: Path) -> list[str]:
    Image = _pil()
    problems: list[str] = []
    kit_path = kit / "kit.json"
    if not kit_path.exists():
        return [f"{kit_path} is not there — run --template first, or copy the "
                "kit.json from a kit that was"]
    manifest = json.loads(kit_path.read_text(encoding="utf-8"))
    required = manifest.get("required", {})

    for name, want in sorted(required.get("sheets", {}).items()):
        sheet_dir = kit / "sheets" / name
        frames_json = sheet_dir / "frames.json"
        if not frames_json.exists():
            problems.append(f"sheets/{name}: no frames.json")
            continue
        frames = json.loads(frames_json.read_text(encoding="utf-8"))
        if len(frames) != want["frames"]:
            problems.append(
                f"sheets/{name}: {len(frames)} frames, the game wants "
                f"{want['frames']}")
        for frame in frames:
            png = sheet_dir / "frames" / f"{int(frame['index']):03d}.png"
            if not png.exists():
                problems.append(f"sheets/{name}: {png.name} is missing")
                continue
            with Image.open(png) as img:
                w, h = img.size
            hx, hy = frame.get("hotspot", [0, 0])
            if not (0 <= hx <= w and 0 <= hy <= h):
                problems.append(
                    f"sheets/{name}/{png.name}: hotspot {hx},{hy} is outside "
                    f"the frame ({w}x{h}) — a sprite drawn by that hotspot "
                    f"would land off its own feet")
        seq_json = sheet_dir / "sequences.json"
        if not seq_json.exists():
            problems.append(f"sheets/{name}: no sequences.json")
            continue
        sequences = json.loads(seq_json.read_text(encoding="utf-8"))
        for seq in want["sequences"]:
            if seq not in sequences:
                problems.append(
                    f"sheets/{name}: the sequence {seq!r} is gone — the game "
                    f"asks for it by that name")

    for group, folder in IMAGE_GROUPS.items():
        for name in required.get(group, []):
            png = kit / folder / f"{name}.png"
            if not png.exists():
                problems.append(f"{folder}/{name}.png is missing")

    powerups_json = kit / "powerups" / "powerups.json"
    if not powerups_json.exists():
        problems.append("powerups/powerups.json is missing")
    else:
        powerups = json.loads(powerups_json.read_text(encoding="utf-8"))
        for name in required.get("powerups", []):
            if name not in powerups:
                problems.append(f"powerups: {name} is not described")
            elif "steps" not in powerups[name] \
                    and not (kit / "powerups" / f"{name}.png").exists():
                problems.append(f"powerups/{name}.png is missing")

    for name in required.get("fonts", []):
        if not (kit / "fonts" / f"{name}.png").exists():
            problems.append(f"fonts/{name}.png is missing")
        if not (kit / "fonts" / f"{name}.json").exists():
            problems.append(f"fonts/{name}.json is missing")
    return problems


# ---------------------------------------------------------------------------
# --build: a kit, put back together
# ---------------------------------------------------------------------------
def build(kit: Path, out_dir: Path, source: Path | None) -> dict:
    Image = _pil()
    import io

    def png_bytes(img) -> bytes:
        buf = io.BytesIO()
        img.save(buf, format="PNG")
        return buf.getvalue()

    kit_manifest = json.loads((kit / "kit.json").read_text(encoding="utf-8"))
    blobs: dict[str, bytes] = {}
    manifest: dict = {
        "source": "art kit",
        "note": (f"Built by tools/artpack.py from {kit}. "
                 "Replacement art: whoever made it owns it."),
        "sheets": {},
        "screens": {},
        "elements": {},
        "backgrounds": {},
        "powerups": {},
        "fonts": {},
        "schemes": {},
    }

    # --- sheets: re-atlas each folder of frames into one strip
    for name in sorted(kit_manifest.get("required", {}).get("sheets", {})):
        sheet_dir = kit / "sheets" / name
        frames = json.loads(
            (sheet_dir / "frames.json").read_text(encoding="utf-8"))
        images = []
        for frame in frames:
            path = sheet_dir / "frames" / f"{int(frame['index']):03d}.png"
            images.append(Image.open(path).convert("RGBA"))
        if not images:
            continue
        cell_w = max(img.width for img in images)
        cell_h = max(img.height for img in images)
        strip = Image.new("RGBA", (cell_w * len(images), cell_h), (0, 0, 0, 0))
        entry_frames = []
        for i, (img, frame) in enumerate(zip(images, frames)):
            strip.paste(img, (i * cell_w, 0))
            entry_frames.append({
                "rect": [i * cell_w, 0, img.width, img.height],
                "hotspot": list(frame.get("hotspot", [0, 0])),
                "name": frame.get("name", f"{i}"),
            })
        blobs[f"{name}.png"] = png_bytes(strip)
        manifest["sheets"][name] = {
            "sheet": f"{name}.png",
            "cell": [cell_w, cell_h],
            "count": len(images),
            "frames": entry_frames,
            "sequences": json.loads(
                (sheet_dir / "sequences.json").read_text(encoding="utf-8")),
        }

    # --- the flat groups
    for group, folder in IMAGE_GROUPS.items():
        for name in sorted(kit_manifest.get("required", {}).get(group, [])):
            path = kit / folder / f"{name}.png"
            if not path.exists():
                continue
            img = Image.open(path).convert("RGBA")
            blob = f"{'screen' if group == 'screens' else group[:-1]}_{name}.png"
            blobs[blob] = png_bytes(img)
            manifest[group][name] = {
                "file": blob,
                "size": [img.width, img.height],
            }

    # --- powerups
    powerups_json = kit / "powerups" / "powerups.json"
    if powerups_json.exists():
        described = json.loads(powerups_json.read_text(encoding="utf-8"))
        for name, entry in sorted(described.items()):
            if "steps" in entry:
                manifest["powerups"][name] = {"steps": entry["steps"]}
                continue
            path = kit / "powerups" / f"{name}.png"
            if not path.exists():
                continue
            img = Image.open(path).convert("RGBA")
            blob = f"power_{name}.png"
            blobs[blob] = png_bytes(img)
            manifest["powerups"][name] = {
                "file": blob,
                "size": [img.width, img.height],
                "hotspot": list(entry.get("hotspot", [img.width // 2,
                                                     img.height - 1])),
            }

    # --- fonts
    for name in sorted(kit_manifest.get("required", {}).get("fonts", [])):
        png = kit / "fonts" / f"{name}.png"
        meta = kit / "fonts" / f"{name}.json"
        if not (png.exists() and meta.exists()):
            continue
        img = Image.open(png).convert("RGBA")
        blob = f"font_{name}.png"
        blobs[blob] = png_bytes(img)
        info = json.loads(meta.read_text(encoding="utf-8"))
        manifest["fonts"][name] = {
            "file": blob,
            "height": info.get("height", img.height),
            "glyphs": info.get("glyphs", {}),
        }

    # --- schemes: not art. Carried from a source pack when one is given, so a
    # replacement pack is still a playable one.
    if source is not None:
        src_manifest, _src_blobs = read_pack(source)
        manifest["schemes"] = src_manifest.get("schemes", {})

    out_dir.mkdir(parents=True, exist_ok=True)
    (out_dir / ".gdignore").write_text("", encoding="utf-8")
    for blob, data in blobs.items():
        (out_dir / blob).write_bytes(data)
    (out_dir / "pack.json").write_text(
        json.dumps(manifest, indent=1), encoding="utf-8")
    container = out_dir.with_suffix(".bin")
    size = abpk.write(container, manifest, blobs)
    manifest["_container"] = str(container)
    manifest["_container_bytes"] = size
    return manifest


def main(argv: list[str]) -> int:
    root = Path(__file__).resolve().parent.parent
    ap = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--pack", type=Path,
                    default=root / "godot-project" / "data" / "packs" / "cd",
                    help="the pack to take apart (--template)")
    ap.add_argument("--template", type=Path, metavar="KIT",
                    help="write an editable kit from --pack")
    ap.add_argument("--check", type=Path, metavar="KIT",
                    help="say what a kit is missing")
    ap.add_argument("--build", type=Path, metavar="KIT",
                    help="build a pack from a kit")
    ap.add_argument("--out", type=Path,
                    default=root / "godot-project" / "data" / "packs" / "free",
                    help="where --build writes the pack")
    ap.add_argument("--from", dest="source", type=Path,
                    help="a pack to copy the non-art parts (schemes) from")
    args = ap.parse_args(argv)

    if args.template:
        info = template(args.pack, args.template)
        counts = info["counts"]
        print(f"artpack: wrote {args.template} — "
              f"{counts['sheets']} sheets ({counts['frames']} frames), "
              f"{counts['screens']} screens, {counts['elements']} elements, "
              f"{counts['backgrounds']} backgrounds, "
              f"{counts['powerups']} powerups, {counts['fonts']} fonts")
        print("artpack: paint over the PNGs, then --check, then --build")
        return 0

    if args.check:
        problems = check(args.check)
        if not problems:
            print(f"artpack: {args.check} has everything the game asks for")
            return 0
        print(f"artpack: {len(problems)} problem(s) in {args.check}:")
        for line in problems[:200]:
            print(f"  {line}")
        if len(problems) > 200:
            print(f"  ... and {len(problems) - 200} more")
        return 1

    if args.build:
        problems = check(args.build)
        if problems:
            print(f"artpack: {args.build} is not complete "
                  f"({len(problems)} problems) — run --check", file=sys.stderr)
            return 1
        info = build(args.build, args.out, args.source)
        print(f"artpack: wrote {args.out} and {info['_container']} "
              f"({info['_container_bytes'] / 1e6:.2f} MB) — "
              f"{len(info['sheets'])} sheets, {len(info['screens'])} screens")
        print(f"artpack: play it with  Godot --path godot-project "
              f"-- --pack {args.out}")
        return 0

    ap.print_help()
    return 2


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
