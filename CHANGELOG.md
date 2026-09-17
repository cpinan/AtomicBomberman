# Changelog

## 2026-09-17 — documentation

Added the top-level `README.md` (full technical writeup, original-vs-port
screenshots) and `HUMAN_README.md` (plain-language summary). Screenshots in
`docs/screenshots/`: the original's own extracted title/menu/field art next
to the Godot port rendering the same screens live.

This is the first commit, so this entry covers the state of the port at that
point rather than a diff against a prior release. Going forward, each entry
records what changed and why — the day-by-day defect history, with full
reasoning and disassembly citations, stays in `docs/BUGS.md`; this file is
the short version.

## 2026-09-17 — first commit

**Repository structure.** Git initialized at the top level for the first
time (the port existed and was verified for two weeks before this — see
`docs/STATUS.md`'s dates). `original-game/` (the disc, 525 MB, copyrighted),
`git-reference-projects/` (third-party ports, each their own repo),
`build/`, and every generated/extracted artifact stay out — see
`.gitignore` for the full list and why each one is excluded.

**Fixed this session, all verified via `tools/verify.sh` (37 suites, ~6100
checks) staying green:**

- **Bombs sometimes not destroying bricks.** `sim.gd`'s flame-arm walk
  (`_propagate()`) tested "is there a powerup here" before "is this a
  brick" — and every powerup sits hidden under a brick by design, so a flame
  reaching such a cell destroyed the invisible powerup and stopped without
  ever destroying the brick. Swept all 67 shipped schemes: 1540 of 4268
  bomb-adjacent-to-brick cases failed (36%) before the fix, 0 after.
- **Flame centre/north-arm misalignment.** `game_view.gd`'s flame-piece
  centring computed `(cell - sprite) / 2.0` and let `round()` resolve the
  `.5` ties — but Godot's `round()` breaks ties away from zero, so a
  negative offset (the centre piece) and a positive one (north's widest
  frame) landed a full pixel apart from the same formula. Now floors the
  offset before rounding, so every piece's tie resolves the same way.
- **Flame `tipeast` gap.** That one sequence's frame is undersized relative
  to the cell (34px on 40px) compared to the other eight (~41px); centring
  it left a visible gap on its inbound edge. Now flush-aligned to the
  inbound edge, only the cross-axis centred.
- **SFX going silent after the first round.** `Sfx` outlives every round
  (built once for the whole app) but tracked voice-busy state as absolute
  simulation ticks, and `Sim.tick_count` restarts at 0 each round — so a
  voice that finished at, say, tick 900 of round 1 read as still busy for
  the first 900 ticks of round 2. Added `Sfx.new_round()`, wired to both
  local and netplay round transitions.
- **Glove throw rendering the player instead of the bomb.** `throw_bomb()`
  never cleared `pickup_pause`, left set by the preceding grab, so the view
  kept drawing the carrying pose over the already-thrown bomb.
- **`--auto-bomb` firing every round instead of once**, a screenshot-
  automation-only flag that compared against `tick_count`, which restarts
  each round.
- **AI gaps**, cross-checked against `BM95.EXE`'s disassembled 8-handler
  priority table (`docs/BUGS.md` Q5 #4): added the remote-trigger and
  bomb-kick handlers (entirely missing before), and corrected the
  enemy-bombing rule from a flame-length-scaled deterministic cross to the
  original's fixed 5-cell plus shape with a 1-in-5 roll.

**Added:**

- **The F3 test editor** (`scripts/app/main.gd`, `scripts/render/
  game_view.gd`) — a live in-game overlay for placing bricks and powerups,
  spawning bombs, killing/diseasing/curing a player, all without depending
  on which scheme or level happens to be loaded.
- **`godot-project/test_data/TESTALL.SCH`** — a hand-authored scheme with a
  sparse pillar grid (mostly destructible brick) and every one of the 13
  powerup types guaranteed to appear, for exercising every mechanic in one
  round.
- **This file, and `godot-project/README.md`.**

See `docs/BUGS.md` for the full defect history predating this repository
(28 documented defects, D1-D28) and `docs/STATUS.md` for what's still open.
