#!/usr/bin/env python3
"""Classify every file on the disc, so "we extracted everything" is checkable.

The port's problem was never any single format — it is knowing when the disc
has been read to the end. `original-game/` holds 2,400-odd files, most of them
sound, and the ones that matter are mixed in with a 1997 DirectX 5
redistributable, an Acrobat Reader, and five floppy images of a CompuServe
dialler. Without a census, "is that covered?" is answered by memory.

So: one rule table naming every path on the disc, and one of four verdicts.

    extracted   a tool reads it and produces something the port loads
    analysed    a tool reads it and produces a finding, not an asset
                (BM95.EXE — the algorithms live in code, not data)
    excluded    it is on the CD but is not this game: third-party
                redistributables, installers, manuals, the Windows chrome
    TODO        game data with no tool. The list this file exists to empty.

A file matching NO rule is an error, not a TODO: the table is meant to be
exhaustive, so an unmatched path means the disc holds something nobody has
looked at, and that is exactly the case the port cannot afford to miss.

    tools/inventory.py              the report
    tools/inventory.py --todo       only what is still uncovered
    tools/inventory.py --verify     also confirm each tool's outputs exist
    tools/inventory.py --json       machine-readable, to tools/out/

Exit status is 1 while any TODO remains, so `tools/extract.py --check` can
gate on it.
"""

from __future__ import annotations

import argparse
import fnmatch
import json
import sys
from pathlib import Path

EXTRACTED = "extracted"
ANALYSED = "analysed"
EXCLUDED = "excluded"
TODO = "TODO"

# (glob against the disc-relative path, verdict, owning tool, why)
#
# Order matters: the first match wins, so specific paths precede their
# directory. Globs are matched case-insensitively against the path with '/'
# separators, because the CD is uppercase and copies of it are not always.
RULES: list[tuple[str, str, str, str]] = [
    # ---------------------------------------------------------------- art
    ("ANI/*.ANI", EXTRACTED, "anifile.py + pack_assets.py",
     "every sprite: 95 IFF-chunked animation containers"),
    ("ANI/MASTER.ALI", EXTRACTED, "anifile.py + pack_assets.py",
     "the load list: which ANIs the game actually opens, and in what order"),
    ("RES/*.PCX", EXTRACTED, "pcx.py + pack_assets.py",
     "every screen, field background and powerup icon"),
    ("*.RMP", EXTRACTED, "remap.py",
     "the ten per-player palette remaps"),
    ("COLOR.PAL", EXTRACTED, "remap.py",
     "the 256-entry palette and its RGB555 lookup"),
    ("FONT?.FON", EXTRACTED, "fonts.py",
     "the bitmap alphabets the screens letter with"),

    # -------------------------------------------------------------- sound
    ("SOUND/*.RSS", EXTRACTED, "rss.py",
     "raw PCM, 2027 files, channel count detected per file"),
    ("RES/SOUNDLST.RES", EXTRACTED, "rss.py",
     "which sound plays for which event"),

    # --------------------------------------------------------------- data
    ("SCHEMES/*.SCH", EXTRACTED, "schemes.py + pack_assets.py",
     "the 67 maps: grid, brick density, starts, powerup table"),
    ("RES/*.CAM", EXTRACTED, "campaigns.py + pack_assets.py",
     "campaign stage lists"),
    ("RES/EXTRA*.RES", EXTRACTED, "extras.py",
     "per-level arrows, conveyors, trampolines and warps"),
    ("RES/VALUELST.RES", EXTRACTED, "valuelist.py",
     "Kurt Dekker's tuning table — every constant the game reads"),
    ("MESSAGES.TXT", EXTRACTED, "messages.py",
     "the string table, and the closest thing to a screen spec"),
    ("*.BM", EXTRACTED, "bmtext.py",
     "the markup screens: credits, manual, readme, the error screens"),

    # ------------------------------------------------------------- levels
    # 0.RMP..9.RMP are caught by *.RMP above; these are the level layouts
    # the editor writes, and the disc ships none, so this is a stub that
    # fires only if a copy has them.
    ("*.MAP", TODO, "-", "level editor output, if any copy has some"),

    # ------------------------------------------------------------ the exe
    ("BM95.EXE", ANALYSED, "bmexe.py",
     "the algorithms no data file states — measured, not decompiled"),

    # ------------------------------------------------------ known, unread
    ("TOOLS/ANIMS.TXT", ANALYSED, "docs/ORACLE.md",
     "modding notes: how master.ali and VALUELST 105 add a death animation"),
    ("TOOLS/STAGES.TXT", ANALYSED, "docs/ORACLE.md",
     "modding notes: which FIELD/TILES/XBRICK files a new level needs"),

    # ----------------------------------------------- excluded: not a game
    ("BM95.RES", EXTRACTED, "containers.py",
     "Watcom resource file — 5 bitmaps, extracted as PNG"),
    ("BM95.ICO", EXCLUDED, "-", "the desktop icon"),
    # Four bytes: 81 fb bf 33. Called "a copy-protection or install stamp"
    # here once, which was a guess with nothing behind it. What is actually
    # known: it is four bytes, no tool on the disc references it by name, and
    # it is far too small to hold a level. Unexplained is the honest verdict.
    ("LEVELS.DAT", EXCLUDED, "-",
     "four bytes, unexplained — too small to be level data"),
    ("INSTALL.DAT", EXTRACTED, "installdat.py",
     "an LZSS archive of 22 files, 18 of which are on the disc nowhere else"),
    ("INSTALL.DIR", EXCLUDED, "-", "installer script"),
    ("CFG.INI", EXCLUDED, "-",
     "66 bytes of install paths; the port has its own settings"),
    ("*.DLL", EXCLUDED, "-", "1997 Microsoft/Watcom runtime redistributables"),
    ("SETUP.EXE", EXCLUDED, "-", "installer"),
    ("Setup95.exe", EXCLUDED, "-", "installer"),
    ("MAKECFG.EXE", EXCLUDED, "-", "the config writer"),
    ("SFADMO95.EXE", EXCLUDED, "-", "a Sound Forge demo"),
    ("INTRO/BMINTRO.EXE", EXTRACTED, "containers.py",
     "the intro player, and the 640x480 Interplay MVE movie inside it"),
    ("TRAILER.SFA", EXTRACTED, "containers.py",
     "a 640x480 Interplay MVE movie, sliced out whole"),
    ("OOO_LTD.CXT", ANALYSED, "containers.py",
     "Director cast: 324 members, 280 Lingo scripts, no bitmaps — code, not art"),
    ("THEME/THEME.ZIP", EXTRACTED, "containers.py",
     "40 members of original art: 2 bitmaps, 8 icons, 18 cursors, 14 WAVs"),
    ("THEME/*", EXCLUDED, "-", "the theme's own install note"),
    ("TOOLS/*.EXE", EXCLUDED, "-", "the shipped level editor, FRED"),
    ("TOOLS/*.DOC", EXCLUDED, "-", "the editor's manual"),
    ("TOOLS/*.PCX", EXCLUDED, "-", "the editor's own palette art"),
    ("TOOLS/*.TXT", EXCLUDED, "-", "editor notes"),
    ("DIRECTX5/*", EXCLUDED, "-", "the DirectX 5 redistributable"),
    ("Acrobat/*", EXCLUDED, "-", "an Acrobat Reader 3 installer"),
    ("Techsupp/*", EXCLUDED, "-", "five floppy images of a CompuServe dialler"),
    ("Extras/*", EXCLUDED, "-", "an ActiveX redistributable and a blurb"),
    ("Manparts/*", EXCLUDED, "-", "PDFs of manuals for other products"),
    ("Manual.pdf", EXCLUDED, "-", "the game's manual, as a PDF"),
    ("*.txt", EXCLUDED, "-", "readmes"),
    ("*.url", EXCLUDED, "-", "a download link added by whoever archived the disc"),
    ("*.DS_Store", EXCLUDED, "-", "macOS metadata, not from the disc"),
    # Ten 493x400 GIFs sitting in SOUND/, none of them referenced: BM95.EXE
    # contains no ".gif" string at all. They are the lead programmer's own
    # photos, with captions burned in. One caption is a game fact and is
    # recorded in docs/ORACLE.md rather than lost here: a hidden feature that
    # puts his head on the character, entered as Up, X, B, Left on a
    # controller. The other nine are helicopters, cards and Lego.
    ("SOUND/*.GIF", EXCLUDED, "-",
     "dev photos shipped in SOUND/, unreferenced by the exe"),
]

# What each extracting tool must have left behind, relative to the repo root.
# --verify checks these exist; it is the difference between "a tool exists"
# and "a tool has been run".
OUTPUTS: dict[str, list[str]] = {
    "anifile.py + pack_assets.py": ["godot-project/data/packs/cd.bin"],
    "pcx.py + pack_assets.py": ["godot-project/data/packs/cd.bin"],
    "remap.py": ["godot-project/data/packs/cd.bin"],
    "fonts.py": ["godot-project/data/packs/cd.bin"],
    "rss.py": ["godot-project/data/packs/sfx.bin"],
    "schemes.py + pack_assets.py": ["tools/out/schemes.json"],
    "campaigns.py + pack_assets.py": ["tools/out/campaigns.json"],
    "extras.py": ["tools/out/extras.json",
                  "godot-project/scripts/core/extras.gd"],
    "valuelist.py": ["tools/out/valuelist.json"],
    "messages.py": ["tools/out/messages.json",
                    "godot-project/scripts/core/messages.gd"],
    "bmtext.py": ["tools/out/bmtext.json"],
    "installdat.py": ["tools/out/installdat.json", "tools/out/install/AB.PCX"],
    "containers.py": ["tools/out/containers.json",
                      "tools/out/movies/bmintro_011400.mve"],
}


def deep(root: Path, data: Path) -> int:
    """How much of what the tools READ actually REACHES the port.

    The census above answers "does a tool read this file". That is not the
    same question as "does the port have it", and conflating the two is how a
    100% covered disc can still ship a game missing two thirds of its
    animations. This opens the packs and counts.

    A gap here is not automatically a bug — `pack_assets.py` selects the ANIs
    the game draws, and `rss.py` caps takes per event on purpose — but an
    unmeasured gap is, so both numbers are printed side by side.
    """
    import abpk

    cd = root / "godot-project" / "data" / "packs" / "cd.bin"
    sfx = root / "godot-project" / "data" / "packs" / "sfx.bin"
    if not cd.is_file() or not sfx.is_file():
        print("inventory: --deep needs both packs; run tools/extract.py first",
              file=sys.stderr)
        return 2

    man, _ = abpk.read(cd)
    sman, _ = abpk.read(sfx)

    on_disc_ani = len(list((data / "ANI").glob("*.ANI")))
    on_disc_pcx = len(list((data / "RES").glob("*.PCX")))
    on_disc_rss = len(list((data / "SOUND").glob("*.RSS")))
    screens = len(man.get("screens", {})) + len(man.get("elements", {})) \
        + len(man.get("backgrounds", {}))

    rows = [
        ("animations (.ANI)", on_disc_ani, len(man.get("sheets", {})),
         "pack_assets.py packs the ones the game draws"),
        ("screens+art (.PCX)", on_disc_pcx, screens,
         "powerup icons come from POWERS.ANI, not from the PCX"),
        ("maps (.SCH)", len(list((data / "SCHEMES").glob("*.SCH"))),
         len(man.get("schemes", {})), "all of them, as text"),
        ("campaigns (.CAM)", len(list((data / "RES").glob("*.CAM"))),
         len(man.get("campaigns", {})), "all of them, as text"),
        ("text screens (.BM)", len(list(data.glob("*.BM"))),
         len(man.get("help", {})), "all of them"),
        ("fonts (.FON)", len(list(data.glob("FONT?.FON"))),
         len(man.get("fonts", {})), "all three, since FONT0 decodes"),
        ("sounds (.RSS)", on_disc_rss, len(sman.get("sounds", {})),
         "SOUNDLST names 1051; the pack caps takes per event to fit a budget"),
    ]

    print("inventory: what reaches the port\n")
    print(f"  {'':<20} {'on disc':>8} {'in pack':>8}")
    for name, disc_n, pack_n, why in rows:
        pct = f"{pack_n * 100 // disc_n}%" if disc_n else "-"
        print(f"  {name:<20} {disc_n:>8} {pack_n:>8}  {pct:>4}  {why}")
    return 0


def classify(rel: str) -> tuple[str, str, str]:
    """Verdict, owner and reason for one disc-relative path."""
    low = rel.lower()
    for pattern, verdict, owner, why in RULES:
        pat = pattern.lower()
        if fnmatch.fnmatch(low, pat):
            return verdict, owner, why
        # A bare-name pattern also matches that name in any directory, so
        # "*.DLL" catches DIRECTX5/DSETUP.DLL without a rule per folder.
        if "/" not in pat and fnmatch.fnmatch(low.rsplit("/", 1)[-1], pat):
            return verdict, owner, why
    return "", "", ""


def walk(data: Path) -> list[tuple[str, int]]:
    out = []
    for path in sorted(data.rglob("*")):
        if path.is_file():
            out.append((path.relative_to(data).as_posix(), path.stat().st_size))
    return out


def main(argv: list[str]) -> int:
    root = Path(__file__).resolve().parent.parent

    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--data", type=Path, default=root / "original-game")
    ap.add_argument("--todo", action="store_true", help="only the uncovered files")
    ap.add_argument("--verify", action="store_true",
                    help="also check each tool's outputs are on disk")
    ap.add_argument("--json", action="store_true",
                    help="write tools/out/inventory.json")
    ap.add_argument("--deep", action="store_true",
                    help="count what actually reaches the packs")
    args = ap.parse_args(argv)

    if not args.data.is_dir():
        print(f"inventory: not found: {args.data}", file=sys.stderr)
        return 2

    if args.deep:
        return deep(root, args.data)

    files = walk(args.data)
    if not files:
        print(f"inventory: no files under {args.data}", file=sys.stderr)
        return 2

    rows = []
    unmatched: list[str] = []
    for rel, size in files:
        verdict, owner, why = classify(rel)
        if not verdict:
            unmatched.append(rel)
            continue
        rows.append({"path": rel, "bytes": size, "verdict": verdict,
                     "tool": owner, "why": why})

    by_owner: dict[str, dict] = {}
    for row in rows:
        key = (row["verdict"], row["tool"], row["why"])
        slot = by_owner.setdefault(key, {"count": 0, "bytes": 0})
        slot["count"] += 1
        slot["bytes"] += row["bytes"]

    todo = [r for r in rows if r["verdict"] == TODO]

    if args.todo:
        for row in todo:
            print(f"TODO  {row['path']:<28} {row['bytes']:>9,}  {row['why']}")
        if not todo:
            print("inventory: nothing left to cover")
        return 1 if todo else 0

    order = {EXTRACTED: 0, ANALYSED: 1, TODO: 2, EXCLUDED: 3}
    print(f"inventory: {len(files)} files, "
          f"{sum(s for _, s in files) / 1e6:.1f} MB under "
          f"{args.data.name}/\n")
    for (verdict, owner, why), slot in sorted(
            by_owner.items(), key=lambda kv: (order[kv[0][0]], -kv[1]["count"])):
        print(f"  {verdict:<9} {slot['count']:>5} files "
              f"{slot['bytes'] / 1e6:>7.1f} MB  {owner:<26} {why}")

    counts = {v: sum(1 for r in rows if r["verdict"] == v)
              for v in (EXTRACTED, ANALYSED, TODO, EXCLUDED)}
    game = counts[EXTRACTED] + counts[ANALYSED] + counts[TODO]
    print(f"\n  game data: {counts[EXTRACTED]} extracted, "
          f"{counts[ANALYSED]} analysed, {counts[TODO]} TODO "
          f"of {game} — {(game - counts[TODO]) * 100 // game}% covered")
    print(f"  not this game: {counts[EXCLUDED]} files excluded, by rule")

    if unmatched:
        print(f"\n  UNMATCHED — no rule covers these {len(unmatched)}:")
        for rel in unmatched[:20]:
            print(f"    {rel}")
        if len(unmatched) > 20:
            print(f"    ... and {len(unmatched) - 20} more")

    if args.verify:
        print()
        missing_out = []
        for owner in sorted({r["tool"] for r in rows
                             if r["verdict"] == EXTRACTED}):
            for out in OUTPUTS.get(owner, []):
                mark = "ok " if (root / out).exists() else "MISSING"
                if mark != "ok ":
                    missing_out.append(out)
                print(f"  {mark} {out}")
        if missing_out:
            print(f"\n  {len(missing_out)} output(s) missing — run tools/extract.py")

    if args.json:
        out_dir = root / "tools" / "out"
        out_dir.mkdir(parents=True, exist_ok=True)
        dest = out_dir / "inventory.json"
        dest.write_text(json.dumps({
            "files": rows,
            "unmatched": unmatched,
            "counts": counts,
        }, indent=1), encoding="utf-8")
        print(f"\ninventory: wrote {dest.relative_to(root)}")

    if unmatched:
        return 2
    return 1 if todo else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
