# Replacing the art

Every sprite, screen, font and sound this port draws is Interplay's, off the
1997 disc. That is fine for playing it yourself and fatal for shipping it:
`tools/build_web.sh` refuses to pretend otherwise. The way out is a
**replacement art pack** — the same manifest, the same frame names, the same
hotspots, different pixels — and nothing in the game knows which pack it
loaded. `godot-project/scripts/render/pack.gd` says so in its first paragraph
and has since the beginning.

This file is how you make one.

---------------------------------------------------------------------------

## The shortest version

```bash
# 1. take the current pack apart into editable PNGs
tools/artpack.py --template artkit

# 2. paint. Every file under artkit/ is a plain PNG.

# 3. check what you have against what the game asks for
tools/artpack.py --check artkit

# 4. build a pack and play it
tools/artpack.py --build artkit --out godot-project/data/packs/free \
                 --from godot-project/data/packs/cd
Godot --path godot-project -- --pack godot-project/data/packs/free
```

And while you are still working, the useful one:

```bash
# play with ONE repainted sheet and the original everywhere else
Godot --path godot-project -- --pack-overlay my-bombs/
```

---------------------------------------------------------------------------

## What a kit contains

`--template` writes this, from whatever pack you point it at:

```
artkit/
  kit.json                      what the game requires; --check reads it
  sheets/<name>/frames/000.png  one PNG per frame, numbered in order
  sheets/<name>/frames.json     each frame's hotspot, by index
  sheets/<name>/sequences.json  the named animations, as frame steps
  screens/<name>.png            25 full screens, 640x480
  elements/<name>.png           9 loose pieces of screen art
  backgrounds/<level>.png       11 playfield backgrounds
  powerups/<name>.png           14 icons, plus powerups.json for hotspots
  fonts/<name>.png + .json      2 bitmap fonts and their glyph tables
```

From the disc that comes to **37 sheets, 592 frames**, 25 screens, 9 elements,
11 backgrounds, 14 powerups and 2 fonts. Nothing else in a pack is art:
schemes are text (`--from` carries them across) and the colour-remap tables are
a consequence of the original's own palette, which a replacement set does not
need — see below.

## The one rule: hotspots

**A frame is drawn around its hotspot, not its rectangle.** The hotspot is a
point inside the frame, measured from the top-left, and it genuinely varies
frame to frame — `CORNER6` ranges to y=109 where fpc_atomic assumes a single 90
for the whole sheet, which is why its corners sit wrong and this port's do not.

So:

* If you keep a frame the same size, keep its hotspot.
* If you resize a frame, move its hotspot to match — the same point on the
  drawing, in the new pixels.
* `--check` will tell you when a hotspot has fallen outside its frame. It
  cannot tell you when one is merely in the wrong place; that shows up as a
  sprite standing beside its own shadow.

## The sequences are the contract

`sequences.json` names the animations the game asks for **by name**:
`"bomb regular green"`, `"walk down"`, `"tile 3 brick"`. The game looks them up
by those strings, so they have to survive. You may change how many frames a
sequence has and which frames it uses; you may not rename it.

Each step is `[frame, dx, dy]` — which frame, and how far to nudge it from the
hotspot for that step.

## Colour

The disc's players are one bomberman recoloured through ten `.RMP` tables and
`COLOR.PAL`. A replacement pack does not have to work that way and probably
should not: **paint ten bombermen.** If a pack carries no remap tables the
shader falls back to its own heuristic path, `has_remap()` selects between
them, and nothing else changes.

If you do want the table route, `tools/remap.py` is the tool and
`docs/BUGS.md` D13 is the story.

## Working incrementally

`--pack-overlay DIR` lays a folder over the pack that is already loaded:
whatever it names is replaced, everything else is left alone. The folder is
just a `pack.json` naming the parts you have redone, plus their PNGs — it does
not have to be complete and does not have to be built.

Repaint one sheet, drop it in a folder with a two-line manifest, and play:

```json
{ "sheets": { "bombs": { "sheet": "bombs.png", "cell": [40, 37],
  "count": 17, "frames": [ ... ], "sequences": { ... } } } }
```

Give the flag more than once to stack overlays. `main.gd` prints each one as it
is applied, so a pack that did not load says so rather than quietly not
appearing.

## What "done" looks like

```bash
tools/artpack.py --check artkit     # says nothing is missing
godot-project/verify.sh             # still green, including the render suites
Godot --path godot-project -- --pack .../free --screen menu
```

The render suites (`tests/render_*.gd`) draw real frames and assert on pixels,
so they are the fastest way to find a sheet that loaded but is wrong. They run
against whatever pack is built, which means a replacement pack gets the same
scrutiny the disc's does.

## What this does not solve

The **sounds** are the original's too — 36 events, `tools/rss.py` — and so are
the **level names, messages and tuning values**, which are text and numbers
rather than art but are still Interplay's. A pack of replacement art gets you a
game that looks like your own; it does not by itself get you one you can
distribute. `docs/STATUS.md` keeps the list.
