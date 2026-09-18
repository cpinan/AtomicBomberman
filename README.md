# Atomic Bomberman — a from-scratch Godot 4 port

A reimplementation of the 1997 DOS/Windows *Atomic Bomberman* in Godot 4,
built by reverse-engineering the original disc and binary rather than by
copying another project's guesswork. Every constant, sprite, sound, and
algorithm in this port traces back to a specific byte on the disc or a
specific address in `BM95.EXE`'s own disassembly — and where that isn't
possible, the gap is written down instead of guessed over.

For the human-language version of this document, see
**[HUMAN_README.md](HUMAN_README.md)**.

## Screenshots — original disc art vs. the Godot port

The left column is the original's own art, extracted byte-for-byte from the
disc (`tools/pcx.py`, no modification). The right column is the Godot port
rendering the same screen, live.

| Original (extracted from disc) | Godot port (live) |
|---|---|
| ![original title](docs/screenshots/original-title.png) | ![port title](docs/screenshots/port-title.png) |
| ![original main menu](docs/screenshots/original-mainmenu.png) | ![port main menu](docs/screenshots/port-mainmenu.png) |
| ![original field background](docs/screenshots/original-field0-greenacres.png) | ![port gameplay](docs/screenshots/port-gameplay-greenacres.png) |

The gameplay shot on the right is real, not staged for the screenshot: five
players, two simultaneous bomb explosions, and the brick/powerup/wall art
all drawn from the original's own sprite sheets.

## What actually works

- The game **starts, plays, and finishes** entirely on the original's own
  screens, art, sounds, and level data.
- **Full network play** — WebSocket server/client, tested with real
  multi-client sessions, deterministic simulation kept in sync by an FNV-1a
  state hash every tick.
- **Every one of the 67 shipped multiplayer schemes** loads and plays, with
  team splits, player-start stacking, and per-scheme powerup overrides all
  read from the scheme file itself.
- **All 13 powerups**, all 12 diseases, kick/punch/grab/spooge/trigger/jelly
  bomb abilities, the closing wall ("Hurry"), brick regrowth, campaign mode,
  and bots with a real (if simplified) AI.
- **A from-scratch bot AI** built by disassembling `BM95.EXE`'s own decision
  routine — not a fresh design, a read of what the original does.
- **A live in-game test editor** (press T) for placing bricks, dropping any
  powerup, spawning bombs, and killing/curing/diseasing a player, all
  without needing the right scheme or level loaded.

## How this was built

Nothing here is invented where the disc has an answer. The pipeline:

1. **`tools/extract.py`** reads the entire disc — 2,454 files, 16 stages —
   and writes out every asset in a form Godot can load: sprite atlases from
   `.ANI` files, screens from `.PCX`, the ten per-player colour transforms
   from `.RMP`/`COLOR.PAL`, sound effects from `.RSS` with per-file
   mono/stereo detection, all 67 scheme files, every tuning constant from
   `VALUELST.RES`, and the entire string table from `MESSAGES.TXT`.
2. **`tools/bmexe.py`** disassembles `BM95.EXE` itself for the four
   algorithms no data file states: movement and tile re-centring, powerup
   scatter sampling, flame propagation order, and the AI's full decision
   tree (an 8-handler priority table dispatched indirectly, driving a
   bounded breadth-first search over an influence map).
3. **`tools/inventory.py`** is the honesty check: it classifies all 2,454
   files on the disc by rule, and a file matching no rule is a hard build
   error. Every exclusion states why. Six files were wrongly excluded in an
   early pass and turned out to hold real content (`INSTALL.DAT` alone had
   18 files nowhere else on the disc) — the rule table now demands a
   measurement, not a description, before excluding anything.
4. **The Godot simulation** (`godot-project/scripts/sim/`) is
   integer-only — centipixels, no floats anywhere in game logic — so a
   client and server computing the same inputs get bit-identical results,
   checked every tick by the state hash.
5. **`tools/verify.sh`** is the single gate: 37 headless test suites, ~6,100
   assertions, a parse pass over all 74 `.gd` files whether referenced or
   not, a real WebSocket match between a server and two clients, and a
   mutation-testing pass (`tools/mutate.py`) that deliberately breaks the
   simulation 213 ways to confirm the test suite would actually catch each
   one (211 of 213 caught; the other two are provably equivalent mutants,
   not gaps).

### Two things that make this port harder to get wrong than most

- **The two-parser rule.** `.SCH` scheme files are parsed twice — once in
  Python at build time (`tools/schemes.py`), once in GDScript at runtime
  (`scripts/core/scheme.gd`) — deliberately, so the two independent
  implementations catch each other's mistakes rather than sharing one bug.
- **Documented wrongness.** `docs/BUGS.md` doesn't just list what's fixed —
  it lists every wrong guess this project itself made along the way (a
  mis-transcribed resource number, a mutation-testing false negative caused
  by a crashed test being counted as a pass, a `str.replace` bug that
  inflated a 30 KB file to 82 MB) and how each was caught, so a mistake
  doesn't get quietly re-made.

## This session's work

Starting from a build that already played start-to-finish with ~6,100
green checks, a live playtesting pass — followed by a deliberate
port-vs-original ground-truth hunt — turned up defects the test suite
could not see (the recurring lesson of this whole project — see
`docs/BUGS.md`'s D21/D24/D27/D28, and now D29). All fixed and re-verified
against the full suite:

**Found by playing it (D29):**

- **Bombs sometimes not destroying bricks.** The flame-arm walk tested "is
  there a powerup here" before "is this a brick" — and every powerup sits
  hidden under a brick by design, so a flame hitting one destroyed the
  invisible powerup and stopped without ever touching the brick. Swept all
  67 schemes: **1,540 of 4,268 bomb-adjacent-to-brick cases (36%) failed
  before the fix, 0 after.**
- **Flame centre/north-arm misalignment** — a genuine sub-pixel quantization
  limit (a 41px sprite centred in a 40px cell always leaves an exact 0.5px
  remainder, provably, for any rounding rule), fixed by letting flame
  pieces draw at their true fractional pixel position instead of snapping —
  every other sprite kind stays pixel-locked.
- **A powerup sitting on a bomb's own tile was never destroyed** — the
  flame arms checked for one, the epicentre never did.
- **Bombs could land on top of each other.** A punched or thrown bomb's
  destination was clamped to field bounds only, with zero occupancy
  check — fixed to stop at the furthest open cell, the way a kicked bomb
  already did.
- **AI movement was genuinely erratic** — the wander fallback re-rolled a
  random direction every single tick (20/s) instead of persisting one.
  Measured: 75% of ticks changed direction before the fix, 5% after,
  matching the original's own 1-in-25 reconsider rule.
- **A death animation could get cut off by the round ending underneath
  it** — the round-transition timer (60 ticks) was shorter than the
  longest death animation needs (up to 93 steps), so a cornered,
  round-deciding kill could tear the simulation down mid-animation.

**Found by hunting the port against the disassembled original, not by
playing:**

- **Four of twelve diseases were dead stubs** — `POOPS`, `SWAP_PLAYERS`,
  `LEPROSY` and `INVISIBLE` were correctly classified into the disease
  pool (so a player could catch them) but had no effect at all.
  Implemented, cross-checked against an independent prior port where the
  disc itself doesn't say (POOPS confirmed via a second port's own
  `dEbola` — same disease, same mechanism).
- **Campaign mode never scored a kill on a bot player** — VALUELST
  resource 1300 ("250 for killing an AI") was declared and never read.
- **The project's own "two-parser" safety check wasn't running.**
  `tools/schemes.py --compare` — meant to catch the Python and GDScript
  scheme parsers disagreeing — depended on a test-support script that
  didn't exist, so it passed by checking nothing. Rebuilt; run for real:
  all 67 schemes agree between the two parsers.

Two live reports turned out to be correct behaviour, not bugs: an exposed
powerup already died to flame (only the epicentre case was broken), and a
"player instead of bomb" sighting during a punch/throw was the disc's own
art — every character in this game is bomb-shaped, including a flying bomb.

Every fix above was found and root-caused through actual repro — headless
simulation sweeps across all 67 schemes, live-session playtesting, and
pixel-level measurement of the rendered art — not by reasoning about the
code in the abstract. See `docs/BUGS.md` D29 for the full defect history
and `CHANGELOG.md` for the itemized diff.

## What's not done

- **Art.** The port plays on the original's own extracted art. A
  replacement set (the only path to a build that could ever be
  redistributed) is designed for (`docs/ART.md`, `tools/artpack.py`) but
  not drawn.
- Hold-to-carry bombs (the port grabs on a second press, the manual says
  hold), three of the manual's six in-game keys (help, net-stats,
  misc-info), death-animation sound mapping (nine sounds for 24 animations,
  the mapping is unrecovered), decoration-only cornerhead animations, and
  the netplay server-override key.
- The AI's search is a simplification of the original's — a graded danger
  map with breadth-first search, rather than the original's cloning-walker
  frontier over a 100-node pool — a deliberate, documented approximation,
  not a bug.

Full detail in `docs/STATUS.md` (current state, next action) and
`docs/BUGS.md` (every open question, with what would settle it).

## Repository layout

```
godot-project/     the Godot 4 project — the deliverable
  scripts/core/     constants, enums, the scheme parser (no engine deps)
  scripts/sim/      the simulation — integer-only, no engine deps
  scripts/net/      protocol, server, client
  scripts/render/   everything that draws
  tests/            37 headless suites + the test harness
  test_data/        TESTALL.SCH — a scheme with every powerup guaranteed
  verify.sh         the one command that has to stay green
tools/              the extraction toolkit — 21 Python scripts, one per
                    format on the disc, plus BM95.EXE's disassembler
docs/               the reverse-engineering record: what the disc says,
                    every defect and open question, the build plan
server/             Docker/nginx config for hosting a dedicated server
```

`original-game/` (the disc itself) and `git-reference-projects/` (third-party
reference ports) are gitignored — see `.gitignore` for the complete,
commented list of what's excluded and why.

## Running it

```bash
cd godot-project
godot --path .                          # needs a copy of the disc — see below
AB_DATA=/path/to/disc godot --path .    # point at a disc that isn't at
                                         # ../original-game
```

Without game data, the data-driven test suites skip and the app falls back
to a built-in grid — it still runs. Extract real game data first with
`tools/extract.py` (see `tools/README.md`).

```bash
cd godot-project
./verify.sh                  # 37 suites, ~6100 checks
EXPORT=1 ./verify.sh         # plus both export presets, .pck probed
../tools/mutate.py            # mutation testing
```

Never run two Godot processes against this project at once — they share a
LAN discovery port and will corrupt each other's test results.

See `godot-project/README.md` for the full flag list and the T test
editor's controls.
