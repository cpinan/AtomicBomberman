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

Useful launch flags (see `scripts/app/main.gd`'s header comment for the
full list): `--scheme PATH` to load a specific `.SCH` file, `--bots N`,
`--debug-grid`, `--auto-bomb N` (force a bomb on tick N, for scripted
screenshots).

## Testing

```bash
./verify.sh                  # 37 suites, ~6100 checks, parses all 74 .gd files
EXPORT=1 ./verify.sh          # plus both export presets, .pck probed
../tools/mutate.py            # mutation testing (run from here)
```

Never run two Godot processes against this project at once — headless test
runs and a live window both hit the same LAN discovery port and can corrupt
each other's results. Kill stray processes first: `pgrep -fl Godot`.

## The T test editor

Press **T** in a running game to open a live test editor, for exercising
every mechanic without hunting for the right scheme or level. (Was F3 —
macOS reserves that for Mission Control on most keyboards, so the OS ate
the keystroke before the game ever saw it.)

- **Left click** a cell — cycles solid → brick → blank
- **Right click** a cell — drops the selected powerup there, immediately
  visible (no brick to break first)
- **[ / ]** — choose which of the 13 powerup types RMB places
- **B** — spawn a bomb at the cursor, using slot 0's own flame length/jelly
- **K** — kill the player standing on the cursor cell (or slot 0)
- **D** — give that player a random ordinary disease
- **C** — cure that player
- **R** — clear every brick and powerup on the field

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
