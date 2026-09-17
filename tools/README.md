# tools — reading the disc

Everything the port knows about Atomic Bomberman comes from `original-game/`,
and everything that reads it lives here. One command runs the lot:

```bash
python3 tools/extract.py            # read the disc, write every output
python3 tools/extract.py --check    # parse everything, write nothing
python3 tools/extract.py --list     # the stages, and what each one reads
```

Exit status is 0 only when every stage succeeded **and** the census below has
no uncovered file left, so this is the one gate worth wiring into CI.

## What reads what

| On the disc | Files | Tool | Comes out as |
|---|---|---|---|
| `ANI/*.ANI`, `MASTER.ALI` | 96 | `anifile.py` → `pack_assets.py` | sprite atlases + frame rects, hotspots, sequences |
| `RES/*.PCX` | 62 | `pcx.py` → `pack_assets.py` | screens, field backgrounds, powerup icons |
| `*.RMP`, `COLOR.PAL` | 11 | `remap.py` | the ten per-player colour transforms |
| `FONT0/1/6.FON` | 3 | `fonts.py` | the game's own lettering, as glyph sheets |
| `SOUND/*.RSS`, `SOUNDLST.RES` | 2 028 | `rss.py` | `sfx.bin`, with per-file channel detection |
| `SCHEMES/*.SCH` | 67 | `schemes.py` → `pack_assets.py` | **the maps**: grid, starts, teams, powerup table |
| `RES/*.CAM` | 3 | `campaigns.py` → `pack_assets.py` | single-player stage lists |
| `RES/EXTRA*.RES` | 5 | `extras.py` | arrows, conveyors, trampolines, warp gates |
| `RES/VALUELST.RES` | 1 | `valuelist.py` | every tuning constant the game reads |
| `MESSAGES.TXT` | 1 | `messages.py` | the string table — level names, menus, options |
| `*.BM` | 10 | `bmtext.py` | the ten text screens and their `<IMG…>` placements |
| `BM95.EXE` | 1 | `bmexe.py` | the algorithms no data file states |
| `INSTALL.DAT` | 1 | `installdat.py` | 22 LZSS members — 18 exist nowhere else on the disc |
| `THEME.ZIP`, `BM95.RES`, `TRAILER.SFA`, `BMINTRO.EXE`, `OOO_LTD.CXT` | 5 | `containers.py` | theme art, resource bitmaps, the intro movie |

Plus the plumbing: `abpk.py` (the container both packs use), `artpack.py`
(take a pack apart into editable PNGs and build a replacement),
`pack_assets.py` (the pack the game loads), `ws_probe.py` (poke a running
server), `build_web.sh` / `build_server.sh`.

## Is that everything?

`inventory.py` answers it by rule rather than by memory. It classifies all
2 454 files on the disc, and a file matching **no** rule is a hard error —
that is the case a port cannot afford to miss.

```bash
python3 tools/inventory.py            # the census
python3 tools/inventory.py --todo     # only what is still uncovered
python3 tools/inventory.py --verify   # and check each tool's outputs exist
```

Current state: **2 295 game files, 100 % covered** — 2 291 extracted, 4
analysed, 0 TODO. The other 159 files are excluded by rule and each rule says
why: a DirectX 5 redistributable, an Acrobat Reader, five floppy images of a
CompuServe dialler, the installer, and ten holiday photos the lead programmer
left in `SOUND/`. One of those photos carries a caption stating a hidden
feature — Up, X, B, Left on a controller puts his head on the character —
recorded in `docs/ORACLE.md` rather than lost with the file.

Six files were excluded by assertion in the first pass and turned out to hold
content, which is why the rule table now demands a measurement rather than a
description. `INSTALL.DAT` is a compressed archive holding four extra fonts, a
second font format and the setup art; `THEME.ZIP` holds 40 pieces of original
art; `BMINTRO.EXE` embeds the game's own intro movie; `TRAILER.SFA` is a second
one; `BM95.RES` has five bitmaps in it. Only `OOO_LTD.CXT` was as described.

### Covered is not the same as shipped

```bash
python3 tools/inventory.py --deep
```

The census says a tool reads a file. `--deep` opens the packs and says what
reaches the game, which is a different number and deliberately so — the pack
carries 64 of 95 animations because `pack_assets.py` selects the ones the game
draws, and 81 sound takes because `rss.py` caps takes per event to a budget.
Both numbers are printed side by side so neither hides the other.

## The two-parser rule

`SCHEMES/*.SCH` is parsed twice: here in `schemes.py`, and at runtime by
`godot-project/scripts/core/scheme.gd`. That is deliberate. The pack copies the
67 files in verbatim, so validating them at build time is the only thing that
stops a malformed scheme reaching a player, and two parsers written from the
same grammar are an independent check on each other:

```bash
python3 tools/schemes.py --compare    # diff the two readings
python3 tools/schemes.py --ascii BASIC
```

## Conventions every tool follows

- `--data PATH` points at a copy of the disc; the default is `original-game/`.
- `--check` parses, reports and writes nothing. `extract.py --check` is that
  for all of them at once.
- Machine-readable output goes to `tools/out/`; generated GDScript goes into
  `godot-project/scripts/core/`; packs go to `godot-project/data/packs/`.
- Nothing guesses. Where a format was worked out rather than documented, the
  module docstring says how it was established and what the wrong readings
  looked like — `fonts.py` on the glyph table, `rss.py` on mono files,
  `remap.py` on the palette, `anifile.py` on the chunk layout.
