#!/usr/bin/env python3
"""Build a Godot-ready asset pack from the original's ANI and PCX files.

Emits TWO things, and the second is the one that ships:

    godot-project/data/packs/cd/       loose files, for looking at
        pack.json                      every sheet, frame rect, hotspot, sequence,
                                       and all 67 schemes as text
        <name>.png                     one horizontal-strip atlas per source ANI
        field<n>.png                   the eleven level backgrounds, from PCX
        power_<name>.png               the powerup icons, cut from POWERS.ANI
        .gdignore                      keeps Godot's importer out of the above

    godot-project/data/packs/cd.bin    ONE container, what an export carries

WHY A CONTAINER. Godot's importer claims any `.png` under res://, converts it
to its own compressed texture and STRIPS the source from an export — so the
first web build shipped 58 file names and none of the bytes. Adding a
`.gdignore` stops the importer but also removes the files from the index, so
`include_filter` can no longer see them either. Neither half works alone.

A single unknown-extension file sidesteps both: nothing imports it, one
`include_filter` entry ships it, the bytes arrive unmodified — which the
recolour shader needs, since it tests pixels for exact green dominance — and a
browser makes one request instead of 58.

The container layout is tools/abpk.py's ABPK — shared with the sound pack.

The manifest keeps two things fpc_atomic's hand-authored `files.txt` throws
away, and both matter:

  * PER-FRAME hotspots. The ANI carries one per frame and they genuinely vary —
    CORNER6's range up to y=109 while fpc_atomic records a single 90 for the
    whole sheet. A sprite drawn at a uniform offset is drawn wrong on any frame
    whose hotspot differs.

  * The `SEQ ` chunks. These are the original's own animation definitions:
    which frames, in what order, under a name the game uses. WALK.ANI holds
    "walk north/south/west/east" plus "spin" over one pool of 60 frames.
    fpc_atomic ignores them entirely.

Sheets are horizontal strips of fixed-size cells, the cell being the largest
frame in that ANI. A strip is trivial to address from Godot's AtlasTexture and
costs a little padding; nothing here is tight enough on VRAM to justify a
packer.

Usage:
    tools/pack_assets.py                 build the pack
    tools/pack_assets.py --check         report what would be built
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import abpk  # noqa: E402
import anifile  # noqa: E402

# The ANIs the port needs, and why. Everything else on the disc is menu
# furniture, the editor, or unused.
WANTED = {
    # field
    "TILES": "the blank / brick / solid cell art, one ANI per level",
    "XBRICK": "brick disintegration, one ANI per level",
    # actors
    "STAND": "player standing, four directions",
    "WALK": "player walking, four directions, plus spin",
    "KICK": "player kicking a bomb",
    "SHADOW": "the blob under every actor",
    # --- the three things the action button does, which the port could do and
    # could not show. MANUAL.BM names all of them and the disc animates all of
    # them; the port drew a walking bomberman for each.
    "PUNCH": "player punching a bomb, four directions",
    "BOMBWALK": "player carrying a bomb over its head, four directions",
    "BPICKUP": "player picking a bomb up, four directions",
    # bombs and fire
    "BOMBS": "bomb idle and jelly",
    # A bomb has four looks on the disc and the port drew one of them. TRIGBOMB
    # is `bomb trigger green` — the bomb that waits for its owner's signal —
    # and DUDS is `bomb regular green dud`, the 1-in-3 the Duds disease makes.
    "TRIGBOMB": "the trigger bomb, and the trigger powerup beside it",
    "DUDS": "a dud bomb, for VALUELST 322's one-in-three",
    # PUNBOMB1..4 are the punched bomb in flight, one file per direction:
    # `punch south`, `punch north`, `punch west`, `punch east`.
    "PUNBOMB": "the punched bomb tumbling through the air, one per direction",
    "MFLAME": "flame centre, mid and tip for four directions",
    # pickups and furniture
    "POWERS": "the powerup icons, one cell each",
    "CONVEYOR": "conveyor belt cells",
    "EXTRAS": "arrows, warps, trampolines",
    "MISC": "cursors, rings, goldman",
    "HURRY": "the HURRY banner",
    # --- the interface. MASTER.ALI loads kface FIRST and kfont right after
    # the cornerheads, which is how these were found.
    "KFACE": "the 40x40 bomberman head, four directions — the status readout",
    "KFONT": "the numeric font: ten digits and an infinity sign",
    "BFONT": "a second, smaller numeric font",
    # --- campaign mode's own monsters. `BM95.EXE` builds their sequence names
    # from "rover %s" and "ghost %s" (0x45807A, 0x458071) and ALIENS1.ANI is
    # where those eight sequences live: rover and ghost, north/east/south/west.
    # The three .CAM files say how many of each a stage has and how fast.
    "ALIENS1": "campaign rovers and ghosts, four directions each",
    # --- the deaths. VALUELST 105 says 24 and the seventeen XPLODE files hold
    # exactly 24 named SEQ sequences between them — "die green 1" to
    # "die green 24" — which is where that number comes from. 705 frames.
    "XPLODE": "the 24 death animations, spread over seventeen files",
    "HEADWIPE": "211 frames of screen transition",
}

# The ones that exist per level, numbered 0..10.
## Every screen on the disc, and what it is. All 640x480 PCX.
SCREENS = {
    "TITLE": "the title screen",
    "MAINMENU": "the main menu, its seven items painted in",
    "RESULTS": "the statistics screen",
    "DRAW": "nobody won",
    "ROULETTE": "the Goldman roulette wheel",
    "BONUS": "the bonus screen",
    "TEAM0": "team 0 wins",
    "TEAM1": "team 1 wins",
    "GLUE0": "wallpaper: a grid of bomberman heads",
    "GLUE1": "wallpaper: A.B. roundels",
    "GLUE2": "wallpaper: ATOMIC BOMBERMAN on brick",
    "GLUE3": "wallpaper: grey plate",
    "GLUE4": "wallpaper: BombFlakes boxes",
    "GLUE5": "wallpaper: starbursts",
    "GLUE6": "wallpaper: dark brick",
}

## Not screens: PCX art the screens place. Kept apart because "every screen is
## 640x480" is a property worth asserting, and these three break it — WINZ is
## 72x72, CREDBAR 200x100, BOMBDUDE 110x110.
ELEMENTS = {
    "CREDBAR": "the credits bar, placed by CREDITS.BM's <IMGCREDBAR>",
    "WINZ": "the wins readout for the status area",
    "BOMBDUDE": "a small bomberman",
    "JERM": "a developer photo, placed by <IMGJERM>",
    "KURT": "a developer photo, placed by <IMGKURT>",
    "KURTHEAD": "and a smaller one",
    "IPLOGO": "the Interplay logo",
    "HSLOGO": "a logo",
    "QALOGO": "a logo",
}
## One victory screen per player colour.
VICTORY_COUNT = 10

PER_LEVEL = {"TILES", "XBRICK"}
LEVEL_COUNT = 11

## Numbered from 1 rather than 0, and there are seventeen of them.
XPLODE_COUNT = 17


def sheet_for(ani: anifile.Ani, name: str, out_dir: Path,
              write: bool, blobs: dict | None = None) -> dict:
    """Write one horizontal-strip PNG and return its manifest entry."""
    from PIL import Image

    frames = ani.frames
    cell_w = max(f.width for f in frames)
    cell_h = max(f.height for f in frames)

    entry = {
        "sheet": f"{name}.png",
        "cell": [cell_w, cell_h],
        "count": len(frames),
        "frames": [
            {
                "rect": [i * cell_w, 0, f.width, f.height],
                "hotspot": [f.hotspot_x, f.hotspot_y],
                "name": f.name,
            }
            for i, f in enumerate(frames)
        ],
        "sequences": {
            s.name: {"steps": [list(step) for step in s.steps]}
            for s in ani.sequences
        },
    }
    if ani.warnings:
        entry["warnings"] = ani.warnings

    if write:
        sheet = Image.new("RGBA", (cell_w * len(frames), cell_h), (0, 0, 0, 0))
        for i, f in enumerate(frames):
            img = Image.frombytes("RGBA", (f.width, f.height), f.pixels)
            # Top-left of the cell, so the rect in the manifest is exact. The
            # hotspot, not the cell, is what positions the sprite.
            sheet.paste(img, (i * cell_w, 0))
        sheet.save(out_dir / f"{name}.png")
        if blobs is not None:
            blobs[f"{name}.png"] = _png_bytes(sheet)

    return entry


def _png_bytes(img) -> bytes:
    """A PIL image as PNG bytes, for the container."""
    import io
    buf = io.BytesIO()
    img.save(buf, format="PNG")
    return buf.getvalue()


def write_container(path: Path, manifest: dict, blobs: dict) -> int:
    """One file: header, manifest JSON, then every blob concatenated.

    The layout lives in tools/abpk.py because the sound pack uses it too, and
    one format cannot drift from itself.
    """
    return abpk.write(path, manifest, blobs)


def cut_powerups(ani: anifile.Ani, out_dir: Path, write: bool,
                 blobs: dict | None = None) -> dict:
    """One PNG per named powerup, from POWERS.ANI's single-step sequences.

    The names are the original's own: 'power bomb', 'power kicker', and so on.
    'power random' is a 12-step animation that cycles the others, which is how
    the original shows a random pickup, so it is left as a sequence rather than
    cut to a still.
    """
    from PIL import Image

    icons = {}
    for seq in ani.sequences:
        key = seq.name.replace("power ", "").strip().replace(" ", "_")
        if len(seq.steps) != 1:
            icons[key] = {"animated": True, "steps": [list(s) for s in seq.steps]}
            continue
        index = seq.steps[0][0]
        f = ani.frames[index]
        icons[key] = {
            "file": f"power_{key}.png",
            "size": [f.width, f.height],
            "hotspot": [f.hotspot_x, f.hotspot_y],
            "frame": index,
        }
        if write:
            img = Image.frombytes("RGBA", (f.width, f.height), f.pixels)
            img.save(out_dir / f"power_{key}.png")
            if blobs is not None:
                blobs[f"power_{key}.png"] = _png_bytes(img)
    return icons


PALETTE_BYTES = 768
LUT_BYTES = 32768
PLAYER_COUNT = 10


def _pack_remap(data_dir: Path, out_dir: Path, write: bool,
                blobs: dict) -> dict:
    """COLOR.PAL and the .RMP files, as three sampler-ready images."""
    from PIL import Image

    pal_path = data_dir / "COLOR.PAL"
    rmp_paths = [data_dir / f"{i}.RMP" for i in range(PLAYER_COUNT)]
    missing = [p.name for p in [pal_path] + rmp_paths if not p.is_file()]
    if missing:
        print(f"pack: no colour remap tables ({', '.join(missing)}) — the "
              f"recolour shader will fall back to the heuristic")
        return {}

    raw = pal_path.read_bytes()
    if len(raw) != PALETTE_BYTES + LUT_BYTES:
        print(f"pack: {pal_path.name} is {len(raw)} bytes, expected "
              f"{PALETTE_BYTES + LUT_BYTES}")
        return {}

    # Palette entry 0 is stored as ff ff ff where every other entry is 0..63.
    # It reads as a sentinel; clamped to 6 bits it is white, which is what it
    # looks like it means.
    palette = bytearray()
    for i in range(256):
        for c in raw[i * 3:i * 3 + 3]:
            v = min(c, 0x3F)
            palette.append((v << 2) | (v >> 4))
    lut = raw[PALETTE_BYTES:]

    remap = bytearray()
    for path in rmp_paths:
        table = path.read_bytes()[:256]
        if len(table) != 256:
            print(f"pack: {path.name} is short")
            return {}
        remap += table

    pal_img = Image.frombytes("RGB", (256, 1), bytes(palette))
    lut_img = Image.frombytes("L", (256, 128), lut)
    rmp_img = Image.frombytes("L", (256, PLAYER_COUNT), bytes(remap))

    mapped = sorted({i for row in range(PLAYER_COUNT)
                     for i in range(256) if remap[row * 256 + i]})
    entry = {
        "palette": "palette.png",
        "lut": "colorlut.png",
        "remap": "remap.png",
        "players": PLAYER_COUNT,
        "mapped_count": len(mapped),
        "mapped_first": mapped[0] if mapped else 0,
        "mapped_last": mapped[-1] if mapped else 0,
    }
    if write:
        for name, img in (("palette.png", pal_img), ("colorlut.png", lut_img),
                          ("remap.png", rmp_img)):
            img.save(out_dir / name)
            blobs[name] = _png_bytes(img)
    print(f"pack: colour remap — {len(mapped)} of 256 indices remapped, "
          f"{mapped[0]}..{mapped[-1]}")
    return entry


def main(argv: list[str]) -> int:
    root = Path(__file__).resolve().parent.parent
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--data", type=Path, default=root / "original-game")
    ap.add_argument("--out", type=Path,
                    default=root / "godot-project" / "data" / "packs" / "cd")
    ap.add_argument("--check", action="store_true",
                    help="report what would be built, write nothing")
    args = ap.parse_args(argv)

    ani_dir = args.data / "ANI"
    res_dir = args.data / "RES"
    if not ani_dir.is_dir() or not res_dir.is_dir():
        print(f"pack: need {ani_dir} and {res_dir}", file=sys.stderr)
        return 2

    write = not args.check
    if write:
        args.out.mkdir(parents=True, exist_ok=True)
        # Keeps Godot's importer off the loose PNGs. They are debug output; the
        # container next to them is what ships.
        (args.out / ".gdignore").write_text("", encoding="utf-8")

    from PIL import Image

    blobs: dict = {}
    manifest: dict = {
        "source": "original-game",
        "note": ("Generated by tools/pack_assets.py from the original CD. "
                 "Interplay Productions (c) 1997 — never redistribute."),
        "sheets": {},
        "powerups": {},
        "backgrounds": {},
        "schemes": {},
        "screens": {},
        "elements": {},
    }

    # --- the ANIs
    targets: list[tuple[str, str]] = []
    for base in sorted(WANTED):
        if base in PER_LEVEL:
            for n in range(LEVEL_COUNT):
                targets.append((f"{base}{n}", f"{base}{n}.ANI"))
        elif base == "XPLODE":
            for n in range(1, XPLODE_COUNT + 1):
                targets.append((f"{base}{n}", f"{base}{n}.ANI"))
        elif base == "PUNBOMB":
            # One file per direction, and each names its own sequence, so they
            # travel as four sheets rather than being merged.
            for n in range(1, 5):
                targets.append((f"{base}{n}", f"{base}{n}.ANI"))
        else:
            targets.append((base, f"{base}.ANI"))

    missing = []
    for name, filename in targets:
        src = ani_dir / filename
        if not src.is_file():
            missing.append(filename)
            continue
        try:
            ani = anifile.load(src)
        except anifile.AniError as exc:
            print(f"  FAIL {filename}: {exc}")
            return 1
        key = name.lower()
        manifest["sheets"][key] = sheet_for(ani, key, args.out, write, blobs)
        if name == "POWERS":
            manifest["powerups"] = cut_powerups(ani, args.out, write, blobs)

    if missing:
        print(f"pack: {len(missing)} wanted ANIs absent: {', '.join(missing)}")

    # --- the fonts
    #
    # KFONT.ANI is digits only, so the alphabet comes from the .FON files in
    # the install root. tools/fonts.py has the format.
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    import fonts as fontsmod
    manifest["fonts"] = {}
    for fname in fontsmod.WANTED:
        fpath = args.data / f"{fname}.FON"
        if not fpath.is_file():
            print(f"pack: missing {fpath.name}")
            continue
        try:
            font = fontsmod.Font(fpath)
        except fontsmod.FontError as exc:
            print(f"pack: {exc}")
            continue
        img, metrics = fontsmod.sheet_of(font)
        key = fname.lower()
        manifest["fonts"][key] = {"file": f"{key}.png", "height": font.height,
            "glyphs": metrics}
        if write:
            img.save(args.out / f"{key}.png")
            blobs[f"{key}.png"] = _png_bytes(img)
    print(f"pack: {len(manifest['fonts'])} fonts")

    # --- the screens
    #
    # Every screen the original has is a 640x480 PCX, and the code draws the
    # cursor, the values and the animations over it. MAINMENU has its seven
    # items painted INTO the art, which is why the menu needs their positions
    # rather than their text.
    #
    # GLUE0..GLUE6 are not screens: they are tiling wallpapers, the backdrops
    # the setup and options screens are drawn on. GLUE0 is a grid of bomberman
    # heads, GLUE4 is BombFlakes cereal boxes.
    for name, what in SCREENS.items():
        src = res_dir / f"{name}.PCX"
        if not src.is_file():
            print(f"pack: missing screen {src.name}")
            continue
        img = Image.open(src).convert("RGBA")
        manifest["screens"][name.lower()] = {
            "file": f"screen_{name.lower()}.png",
            "size": list(img.size), "what": what}
        if write:
            img.save(args.out / f"screen_{name.lower()}.png")
            blobs[f"screen_{name.lower()}.png"] = _png_bytes(img)

    for name, what in ELEMENTS.items():
        src = res_dir / f"{name}.PCX"
        if not src.is_file():
            print(f"pack: missing element {src.name}")
            continue
        img = Image.open(src).convert("RGBA")
        manifest["elements"][name.lower()] = {
            "file": f"element_{name.lower()}.png",
            "size": list(img.size), "what": what}
        if write:
            img.save(args.out / f"element_{name.lower()}.png")
            blobs[f"element_{name.lower()}.png"] = _png_bytes(img)

    for n in range(VICTORY_COUNT):
        src = res_dir / f"VICTORY{n}.PCX"
        if not src.is_file():
            print(f"pack: missing {src.name}")
            continue
        img = Image.open(src).convert("RGBA")
        key = f"victory{n}"
        manifest["screens"][key] = {"file": f"screen_{key}.png",
            "size": list(img.size), "what": f"player {n} wins"}
        if write:
            img.save(args.out / f"screen_{key}.png")
            blobs[f"screen_{key}.png"] = _png_bytes(img)

    # --- the level backgrounds
    from PIL import Image
    for n in range(LEVEL_COUNT):
        src = res_dir / f"FIELD{n}.PCX"
        if not src.is_file():
            print(f"pack: missing {src.name}")
            continue
        img = Image.open(src).convert("RGBA")
        manifest["backgrounds"][str(n)] = {
            "file": f"field{n}.png", "size": list(img.size)}
        if write:
            img.save(args.out / f"field{n}.png")
            blobs[f"field{n}.png"] = _png_bytes(img)

    # --- the colour remap tables
    #
    # COLOR.PAL and the ten .RMP files. Between them they are the original's
    # own per-player recolour, and tools/remap.py measures what that is worth:
    # the port's fpc_atomic heuristic sits 7.6 to 30.0 per channel away from
    # the disc's transform depending on the player, where using these tables
    # sits 0.03 to 2.61 away on any pixel whose colour is a palette entry.
    #
    # Three images rather than raw blobs, because the shader has to sample them
    # and Godot already knows how to make a texture from a PNG:
    #
    #   palette.png    256 x 1   RGB    the 256 palette colours, 6-bit
    #                                   expanded to 8
    #   colorlut.png   256 x 128 L      COLOR.PAL's RGB555 -> index lookup,
    #                                   32768 entries in row-major order
    #   remap.png      256 x 10  L      one .RMP per row; 0 means "not
    #                                   remapped", which is how the block of
    #                                   73 recolourable indices is expressed
    manifest["remap"] = _pack_remap(args.data, args.out, write, blobs)

    # --- the schemes
    #
    # In the manifest as TEXT rather than as blobs. All 67 come to 268 KB, the
    # parser already takes text (scheme.gd's parse_text is what the wire uses),
    # and a browser has no SCHEMES folder to read — so without this, local play
    # in a browser has exactly one level: the built-in grid main.gd falls back
    # to. The menu needs a list to offer.
    scheme_dir = args.data / "SCHEMES"
    if scheme_dir.is_dir():
        for src in sorted(scheme_dir.glob("*.SCH")):
            manifest["schemes"][src.stem.upper()] = src.read_text(
                encoding="latin-1").replace("\r", "")
    else:
        print(f"pack: missing {scheme_dir}")

    # --- the campaigns, for the same reason and in the same way: three text
    # files of 514 to 824 bytes describing seventeen stages between them.
    # `BM95.EXE` reads them as `*.cam` (0x45805F) and says "Total of %u
    # campaigns loaded."
    manifest["campaigns"] = {}
    for src in sorted(res_dir.glob("*.CAM")):
        manifest["campaigns"][src.stem.upper()] = src.read_text(
            encoding="latin-1").replace("\r", "")

    # --- the help texts. `*.BM` in the game's own root: CREDITS.BM is "About
    # Bomberman" and MANUAL.BM is the "Online Manual", both named on the main
    # menu, and the rest are the screens the original shows for the editor,
    # the network setup, the input setup and the two out-of-memory dialogs.
    # 390 lines and 157 lines respectively, which is why they have to scroll.
    #
    # They travel in the manifest for the same reason the schemes do: the port
    # used to read them straight off the disc at draw time, so a build without
    # the CD beside it showed a hard-coded stub instead of the disc's own text.
    manifest["help"] = {}
    for src in sorted(args.data.glob("*.BM")):
        manifest["help"][src.stem.upper()] = src.read_text(
            encoding="latin-1").replace("\r", "")

    n_frames = sum(s["count"] for s in manifest["sheets"].values())
    print(f"pack: {len(manifest['screens'])} screens, "
          f"{len(manifest['elements'])} elements")
    n_seqs = sum(len(s["sequences"]) for s in manifest["sheets"].values())
    print(f"pack: {len(manifest['sheets'])} sheets, {n_frames} frames, "
          f"{n_seqs} sequences, {len(manifest['powerups'])} powerups, "
          f"{len(manifest['backgrounds'])} backgrounds, "
          f"{len(manifest['schemes'])} schemes, "
          f"{len(manifest['campaigns'])} campaigns, "
          f"{len(manifest['help'])} help texts")

    if write:
        (args.out / "pack.json").write_text(
            json.dumps(manifest, indent=1), encoding="utf-8")
        print(f"pack: wrote {args.out}/pack.json")
        container = args.out.parent / (args.out.name + ".bin")
        size = write_container(container, manifest, blobs)
        print(f"pack: wrote {container} ({size / 1e6:.2f} MB, "
              f"{len(blobs)} blobs) — this is what an export carries")
    else:
        for key in sorted(manifest["sheets"]):
            s = manifest["sheets"][key]
            print(f"    {key:<12} {s['count']:>3} frames  cell={s['cell']}  "
                  f"{len(s['sequences'])} seq")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
