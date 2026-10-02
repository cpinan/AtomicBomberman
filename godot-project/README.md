# Atomic Bomberman — Godot 4 port

A from-scratch reimplementation of the 1997 DOS/Windows Atomic Bomberman in
Godot 4, built entirely from what the original disc and binary state — every
constant, sprite, sound and algorithm here traces back to `VALUELST.RES`,
`SOUNDLST.RES`, the `.ANI`/`.PCX`/`.SCH` files, or `BM95.EXE`'s own
disassembly. Nothing is guessed without saying so.

This directory is the Godot project and the deliverable. It sits inside the
same git repository as the reverse-engineering toolkit and the full
defect/decision history one level up (see **Documentation** below) — the one
thing never in this repo, anywhere, is the disc itself (`../original-game/`).

## Running it

```bash
godot --path .                          # the game, with your own game data
AB_DATA=/path/to/disc godot --path .    # point at a different copy of the disc
```

Without game data the data-driven suites skip and the app falls back to a
built-in grid — it still runs, just with placeholder content. Extract game
data first with `../tools/extract.py` (see `../tools/README.md`).

Launch flags go AFTER a bare `--`, which is where Godot starts handing
arguments to the game rather than eating them itself:

```bash
godot --path . -- --players 2 --bots 4
```

Without the separator Godot keeps the flag for itself; the game still finds
its own flags there, but warns you to move them after the `--`.
Useful ones (see `scripts/app/main.gd`'s header comment for the full list):
`--scheme PATH` to load a specific `.SCH` file, `--players N`, `--bots N`,
`--scale N`, `--debug-grid`, `--auto-bomb N` (force a bomb on tick N, for
scripted screenshots).

Playing with other people — from the menu with no flags, two on one
keyboard, or two windows over the network on one machine — is
`../docs/MULTIPLAYER.md`.

## Testing

```bash
./verify.sh                  # 39 suites, ~6500 checks, parses every .gd file
EXPORT=1 ./verify.sh          # plus both export presets, .pck probed
../tools/mutate.py            # mutation testing (run from here)
```

Close every game window first — a live window holds the LAN discovery port,
and `verify.sh` stops with a message naming its process rather than failing
in a way that looks like a regression. Find strays with `pgrep -fl Godot`.

## The T test editor

Press **T** in a running game to open a live test editor, for exercising
every mechanic without hunting for the right scheme or level. (Was F3 —
macOS reserves that for Mission Control on most keyboards, so the OS ate
the keystroke before the game ever saw it.)

- **Left click** a cell — cycles solid → brick → blank
- **Right click** a cell — drops the selected powerup there, immediately
  visible (no brick to break first)
- **N** / **shift-N** (or **[ / ]**) — choose which of the 13 powerup types
  RMB places and G gives
- **G** — give the selected powerup to the player on the cursor
- **X** — strip that player back to newborn: no powerups, no diseases
- **B** — spawn a bomb at the cursor, using slot 0's own flame length/jelly
- **K** — kill the player standing on the cursor cell (or slot 0)
- **D** — give that player a random ordinary disease
- **C** — cure that player
- **R** — clear every brick and powerup on the field
- **P** — pause the clock, **.** — one tick while paused (local games only)

In a network game the editor works on the **host**, and edits the real game
— every window sees the change. A guest's edits, and `P` anywhere online,
are refused with a message on the panel.

Pair it with `test_data/TESTALL.SCH` (`--scheme test_data/TESTALL.SCH`) — a
hand-authored scheme with a sparse pillar grid (mostly destructible brick,
for real flame-vs-wall testing) and every one of the 13 powerup types
guaranteed to appear on the field.

## Documentation

Everything about *why* the port behaves the way it does lives in `../docs/`,
outside this repo (it covers the reverse-engineering process, not just the
Godot code):

- `../docs/STATUS.md` — current state and the next action
- `../docs/BUGS.md` — every open question and every defect found and fixed,
  with the reasoning
- `../docs/PLAN.md` — how the port was built, phase by phase
- `../docs/ORACLE.md` — what the disc's data files say, cross-referenced
- `../docs/AUDIT.md` — the game screen by screen, against the original
- `../docs/ART.md` — the art replacement pipeline (`../tools/artpack.py`)

`../tools/README.md` covers the extraction toolkit — the Python scripts that
turn the disc into everything this project loads.

## What's not done

See `../docs/STATUS.md` and `../docs/BUGS.md`'s "In flight" / D28 sections
for the current list. As of this writing: hold-to-carry bombs, three of
`MANUAL.BM`'s in-game keys (F1/Alt-N/Alt-D), death-animation sound mapping,
cornerhead decoration animations, and the netplay server-override key.
The one hard blocker to a distributable build is replacement art — the game
currently plays on the original's own assets.
