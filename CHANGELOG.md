# Changelog

## 2026-10-02 — network play from the menu, and the bugs between two windows

**Network play**

- **A won match returns everyone to the lobby** (it used to stop on the
  final frame for good). The lobby says who won; the host presses Enter
  for the next match. Dedicated servers do the same, with the first
  player in the room as host.
- **Hosting explains itself.** The host's lobby shows the LAN address,
  how others join, and the port to forward for internet play.
- **Joining needs no flags.** Join Network Game takes a typed address
  (`192.168.1.20`, `host:port`) as well as a room code; the empty list says
  so instead of naming `--join`.
- **The LAN list works with two windows on one machine** — the second
  window keeps trying for the discovery port and gets it once the first
  starts hosting.
- **Duplicate names are numbered** ("player 2") instead of refused, which
  made every menu-only join fail.
- **Losing the connection returns to the menu** with the reason on screen,
  instead of quitting the game. A join nobody answers no longer hangs.
- **Rejoining mid-match reclaims your seat**, colour and score — taking it
  back from the AI if `lost_net_to_ai` put one there.
- **Deaths animate and punched bombs arc on every client.** `death_tick`
  and `fly_height` were never sent; a new suite,
  `tests/test_snapshot_coverage.gd`, fails for any field the renderer
  reads that a snapshot does not carry.
- Protocol version 6 → 8, `Snapshot.LAYOUT` 3 → 4.

**Fixes**

- **The T editor crashed on every key in a network game.** It now edits
  the host's server, and refuses on a guest with a message. `P` is refused
  in network games (A2c: no manual pause online).
- **The host's override key (`O`) crashed a lobby** with no round running.
- **The flame's top arm sat ~3 px right of the centre** (A4). MFLAME's
  centre frames carry their stem ~2.5 px left of the frame's middle; the
  vertical arms now line up on it. 2.75 px at the joint before, 0.15 px
  after.
- **Flags given before the bare `--` are honoured with a warning** instead
  of silently ignored.
- The between-rounds wait holds for a death animation over the network,
  as it already did locally.

**Tooling**

- `verify.sh` refuses to run while a game window holds UDP 47601, and
  honours `PYTHON=` everywhere (two checks called `python3` directly).
- A flaky three-client check counted living players; it counts seated
  ones.

`tools/verify.sh`: **VERIFY OK** — 39 suites, ~6,500 checks.

## 2026-09-18 — the last two known gaps

The two items from the prior batch that were correctly left undone —
because they needed more disassembly work and real netcode design, not a
quick patch — are done:

- **Cornerhead animations.** The trigger `0x41F29B` uses was found: boxed
  in on all four sides, every tick, geometric and independent of input —
  not tied to the closing-wall crush as guessed, since any dead end
  triggers it, not just one closing in on you. Packed, drawn, tested.
  Not yet network-synced (same pre-existing gap `death_anim` has).
- **Netplay server-override key ('o'/'0').** Implemented in the scope this
  port's architecture actually supports: a connected human's seat can be
  demoted to AI mid-round and an AI seat freed back to open, broadcast to
  every peer. Not the original's full pre-round KEY/AI/OFF/JOY lobby cycle
  — this port has no lobby screen to run that on — but a real, working,
  tested mechanism for the one transition that means something once play
  is underway. Protocol version 3→4.

`tools/verify.sh`: **VERIFY OK**, 0 failures.

## 2026-09-17 — the remaining known-gaps list, worked through

Six items off the standing "known bugs" list, investigated properly rather
than patched blind — two turned out to need real architecture work and were
correctly left as documented gaps rather than forced:

- **Hold-to-carry bombs — implemented.** The manual says holding Drop Bomb
  carries it, releasing drops it; the port grabbed on a second press and
  threw on a third. Now threads the button's live held-state from input
  through netcode into the sim (`Protocol_.VERSION` 2→3, `Snapshot.LAYOUT`
  1→2 — new synced fields, not a wire-format-incompatible change in
  practice since nothing shipped against version 2 outside this repo).
- **Death-animation sound mapping — resolved, and the premise was wrong.**
  "9 sounds for 24 animations, unrecoverable" wasn't true: `SOUNDLST.RES`
  has exactly one resource in that range (341, "burnedup"), not nine —
  `tools/rss.py`'s own event-range guess was wrong by analogy with
  neighbouring groups. Corrected the range, wired the one real sound up.
- **Two of three missing manual keys — implemented.** Alt-N writes a real
  `NETSTATS.TXT` (actual snapshot size/bandwidth, not invented numbers);
  Alt-D prints what the port actually knows, since the manual's only stated
  fact about this screen is a warning it "will affect synchronization" —
  not enough to build a real one from. F1 stays a deliberate no-op: the
  port's only matching content is the pre-game manual screen, reachable
  only by ending the current round to open the menu — worse than not
  having the key.
- **Netplay server-override key — investigated, correctly not implemented.**
  `INPUT.BM` confirms the key, but the port's netcode has no client-side
  slot-type selection to override in the first place — a joining client
  never sends one. Needs a new protocol message before a keybinding means
  anything; documented rather than faked.
- **Cornerhead animations — real finding, correctly not implemented.** The
  disc's own `TOOLS/ANIMS.TXT` states what they're for: a "trapped, about
  to die" pre-death state, not decoration — three docs had this wrong.
  Also caught a transcription error (resource 330, not 308) repeated
  across `docs/AUDIT.md`/`BUGS.md`/`STATUS.md`. Not implemented: the actual
  trigger call site isn't in the disassembly reached so far, and a plausible
  guess (the closing wall's crush) was correctly left as a guess, not code.
- **The two-parser scheme check's own blind spot — fixed, and it found a
  real bug on the way.** The check's grid encoding collapsed brick and
  blank to the same letter on both sides, so a brick/blank divergence
  between the two parsers couldn't have been caught. Fixed to use `#`/`:`/
  `.` directly on both sides — and in the process found that
  `tools/schemes.py --ascii` was rendering every blank cell as a brick,
  a real, separate, user-visible bug the same collision was hiding. Also
  wired the check into `verify.sh` for the first time (gated on the disc
  being present, so a machine without `original-game/` still passes).

`tools/verify.sh`: **VERIFY OK**, 0 failures, all four fixes verified
together in one pass.

## 2026-09-17 — six more from a live session (D29)

Real bugs found while the port was actively being played, fixed and
verified per `docs/BUGS.md` D29:

- **Death animation could get cut off by the round ending underneath it.**
  The round-transition timer (60 ticks) was shorter than the longest death
  animation needs (up to 93 steps), and `_check_round_over()` dropped a
  dying player from the standing count the instant they died — so a
  cornered, round-deciding death (exactly "no way to avoid it") could tear
  the `Sim` down for the next round before the animation finished playing,
  which read as no animation at all. Fixed: a new `Sim.anyone_dying()`
  gates both round-transition points in `main.gd` until every corpse's
  animation window has actually elapsed.

- **Flame top-centre alignment, actually fixed this time.** Root cause
  (Q10) was a genuine 0.5px quantization limit from centring a 41px sprite
  in a 40px cell — not fixable by choosing a different rounding rule.
  Fixed properly: flame pieces now draw at their true fractional pixel
  position (`_draw_frame`'s new `snap` parameter, off for flame pieces
  only — every other sprite stays pixel-locked, unaffected).
- **A powerup sitting on a bomb's own tile (the epicentre) was never
  destroyed** — `_propagate()`'s arm loop starts one cell out and never
  checked the bomb's own cell. Fixed; new regression test in
  `tests/test_bomb.gd`.
- **Bombs could land on top of each other.** A punched or thrown bomb's
  destination was clamped to field bounds only, with no occupancy check —
  a kicked (rolling) bomb already stopped correctly against another bomb,
  but a flying one could land directly on one. Fixed with a new
  `_landing_cell()` that walks the throw/punch path to the furthest open
  cell, mirroring how a kicked bomb already stops short. New test in
  `tests/test_abilities.gd`.
- **AI movement was genuinely erratic** — the wander fallback re-rolled a
  random direction every single tick (20/s) with zero persistence. Fixed
  to hold a direction and only reconsider 1-in-25 ticks, matching the
  original's own documented rule. Measured: 75% of ticks changed direction
  before the fix, 5% after.
- Two reports turned out correct as-is: an exposed powerup on open ground
  already was destroyed by flame (confirmed, unchanged); a "player instead
  of bomb" sighting during a punch/throw turned out to be the disc's own
  intended art (`PUNBOMB4.ANI`) — every character in this game is
  bomb-shaped, including a flying bomb.

## 2026-09-17 — project icon, GitHub topics, doc fix, flame Q10

- **Project icon**: `godot-project/project.godot` now points `config/icon`
  at the original's own app icon, extracted from `BM95.EXE`'s resources
  (`tools/containers.py`'s winres stage). Not committed — `icon.png` is
  gitignored alongside every other extracted asset; a fresh clone needs its
  own disc extraction to have it.
- **GitHub topics** added to the repo: pc, godot, godot4, bomberman,
  atomic-bomberman, reverse-engineering, game-port, gdscript.
- **`docs/AUDIT.md`**: fixed a stale table row claiming keyboard definitions
  are unimplemented — superseded by the "Key rebinding" row further down,
  which correctly says yes. Left over from before that feature was built.
- **Flame centre/north alignment — root cause finally settled, not a bug.**
  Two earlier fixes this session narrowed it but didn't close it. The real
  cause: the centre flame piece is a constant 41px wide (odd) and the cell
  is 40px (even) — centring an odd-width sprite in an even-width cell always
  leaves an exact 0.5px remainder, and no choice of floor/round/ceil changes
  that. North's own frame width alternates 22/27/22/24/25px across its
  5-frame animation, so it lands exactly on-centre on the 3 frames that
  share the cell's even parity and 0.5px off on the other 2 — an inherent
  property of the extracted art's own frame dimensions. Documented as Q10
  in `docs/BUGS.md`, with what would actually fix it (sub-pixel rendering,
  or repadding the extracted frames to unify parity) and why neither was
  done here.
- **Confirmed, not a bug**: an exposed powerup on open ground IS destroyed
  by flame reaching it (already covered by `tests/test_bomb.gd`, and a
  fresh repro this session: 9/9 checks). A powerup a blast just REVEALS by
  breaking its brick survives that same blast — the arm has already ended
  at that cell — which is intentional: a powerup is a reward for breaking a
  wall, not something the same explosion should also delete.
- **UI audit**: reviewed HUD, options, setup, key-rebinding, and victory
  screens against `docs/AUDIT.md`'s record of the original. No missing or
  broken screens found. The original has no pause feature to port (checked
  `MANUAL.BM`/`INPUT.BM` directly — zero mentions).

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
