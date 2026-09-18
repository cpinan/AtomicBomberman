# STATUS — Atomic Bomberman Godot port

_Last updated: 2026-09-18 · branch `main` · 0 uncommitted files_

## Next action

**Draw a replacement art set** (`docs/ART.md`, `tools/artpack.py`) — the
only remaining path to a build that could ever be redistributed; the port
currently plays on the original's own extracted assets, which cannot ship.

## State

- The game starts, plays and finishes on the original's own screens, art,
  sounds and level data — all 67 shipped schemes, all 13 powerups, all 12
  diseases, campaign mode, full networked play (WebSocket, server-
  authoritative, FNV-1a state hash every tick).
- `tools/verify.sh` is green: 37 suites, ~6,100+ checks, a parse pass over
  every `.gd` file, a real server-plus-two-clients WebSocket match, the
  scheme two-parser cross-check (67/67 agree), mutation testing (211/213
  caught, 2 equivalent).
- Repo is on GitHub, private: `github.com/cpinan/AtomicBomberman`.
- AI is built from `BM95.EXE`'s own disassembled decision table, then
  deliberately tuned more aggressive than a strict fidelity read (see
  `docs/BUGS.md`'s "GAMEPLAY AGGRESSION" note in `ai.gd`) — a documented
  gameplay choice, not a fidelity gap.
- The one known, inherent (not fixable by more code) rendering issue: a
  0.5px flame-alignment quantization from an odd-width sprite in an
  even-width cell — `docs/BUGS.md` Q10.

## In flight

Nothing in flight — working tree is clean, everything committed and pushed.

## Verify

```bash
tools/verify.sh                  # 37 suites, all checks, 74 .gd files parsed
EXPORT=1 tools/verify.sh         # plus both export presets, .pck probed
tools/schemes.py --compare       # the two-parser check, now wired into verify.sh
tools/extract.py --check         # re-parse the whole disc, write nothing
cd godot-project && ../tools/mutate.py   # mutation run
```

`AB_DATA` overrides where the disc is found (default `../original-game`
from `godot-project/`). Without game data the data-driven suites skip and
the app falls back to a built-in grid. **Never run two Godot processes
against this project at once** — they share a LAN discovery port
(`test_discovery.gd`) and corrupt each other's results.

## Open questions

- **Pixels.** The art pipeline is proven; nobody has drawn a replacement
  set. Until then no build is distributable. `docs/ART.md`.
- **A pad.** The gamepad layer is tested against synthesised events only;
  nobody has held a real controller.
- **`.AAF` is not cracked** — five antialiased fonts from `INSTALL.DAT`.
  Zero port value (they're the *setup program's* fonts). `docs/ORACLE.md` §9.
- **`APPLBITE`/`NUCKBLOW`/`ZEN`** — a still-unexplained 73×73 animation
  family, distinct from cornerhead (which IS explained and implemented as
  of 2026-09-18). Name appears nowhere on the disc's own text.
- **Death animation/cornerhead netcode sync** — neither `death_anim` nor
  the newer `cornerhead`/`cornerhead_ticks` are in
  `Player_.to_bytes()`/`state_hash()`, so a joining client doesn't see
  either animation correctly. Cosmetic only; doesn't affect sim correctness.

## Do not redo

- **The default keys are `INPUT.BM`'s, not an invention** — cursor keys +
  Space + Enter, and R/D/F/G + S + A. Do not "improve" them to WASD.
- **The test editor is on `T`, not F3** — F3 is macOS's own Mission Control
  shortcut on most keyboards; the OS eats it before Godot sees it.
- **The status panel is 42 px** (`Const_.HUD_H`); `FIELD_Y_OFF` is 68.
- **Flame frames are centred on the cell**, never anchored on their hotspot
  — and centring an odd-width sprite in the 40px-wide cell has an
  irreducible 0.5px error; don't re-litigate this as a rounding bug (Q10).
- **A game left open in another window breaks netplay-adjacent test
  suites** (`test_discovery.gd`, occasionally `test_net.gd`'s version
  assertions if you also bumped `Protocol_.VERSION` and forgot to update a
  hardcoded expectation somewhere). Kill stray headless Godot processes
  before blaming the code: `pgrep -fl Godot`.
- **The movement algorithm is read but deliberately not adopted** (Q5.1) —
  every other system and the network hash sit on the movement this port
  has.
- **The AI's search is a graded danger map + BFS, not the original's
  cloning-walker frontier over a 100-node pool** — a deliberate,
  documented simplification (Q5.4), not a bug to "fix" toward fidelity.
- **The netplay server-override key is scoped to mid-round demote/restore
  only** — it does NOT implement the original's full pre-round KEY/AI/OFF/
  JOY lobby cycle, because this port has no pre-round lobby screen. Don't
  assume the key does more than toggle AI on/off for a seat.
- **`bmexe.py`'s `--xref` only follows DIRECT call targets** — an
  indirectly-dispatched function's own resource reads get attributed to
  whichever function calls it. Hit three times now (AI dispatch, twice;
  cornerhead's trigger). If a resource's "owning function" via `--xref`
  doesn't contain the code you expect, read that function's own
  instructions directly rather than trusting the summary.
