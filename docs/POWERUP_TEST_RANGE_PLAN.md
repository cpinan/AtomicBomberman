# Plan: a powerup test range

**Why this exists.** Three sessions have now "fixed" the gloves and had a live
playtest come back saying they still do not work. Every one of those rounds was
blind in the same way: the automated tests give a player exactly ONE powerup in
an empty fixture, and a live player holds several at once on a real level, with
no way to see what the simulation thinks they are holding. The gap between
those two is where every surviving bug has been.

This is not a gameplay feature. It is an instrument. Its whole job is to make
one powerup testable **in isolation, on demand, with the sim's own state
visible on screen**, so the next bug report is "GRAB, alone, facing east,
standing on my own bomb, `can_grab=true`, press Space, nothing happens" instead
of "the gloves don't work".

Read `docs/POWERUP_REVIEW_PLAN.md` first — it lists all 13 powerups, what
MANUAL.BM says each one does, and the five bugs already fixed.

---

## What already exists (do not rebuild it)

- **The T test editor.** Press `T` in a running game. `scripts/app/main.gd`
  `_editor_key()` (~line 1667) and `scripts/render/game_view.gd`
  `_draw_test_editor()` (~line 1178), state on `game_view.gd:43-45`
  (`editor_active`, `editor_cursor`, `editor_powerup`). It already does:
  left-click cycles a cell solid→brick→blank, right-click drops the selected
  powerup, `[`/`]` choose which, `B` spawns a bomb, `K` kills, `D` diseases,
  `C` cures, `R` clears the field.
- **Solo launch.** `--players 1 --bots 0` already gives a one-player game with
  no AI. `--key-slots` / `--ai-slots` / `--pad-slots` override the slot mapping
  (`main.gd:744-760`).
- **A scheme with every powerup on it.** `test_data/TESTALL.SCH`, via
  `--scheme test_data/TESTALL.SCH`.
- **A temporary stdout diagnostic.** `sim.gd:_explain_action()`, gated on
  `AB_DEBUG_ACTIONS=1`, prints one line per action press with the full decision
  input (facing, bombs, can_* flags, whether a bomb is under/ahead, carry
  state). **This is scaffolding — the plan below replaces it with the on-screen
  panel in step 3 and then deletes it.**

So the work is not "build a test mode". It is "finish the one that is already
there", in four specific ways.

---

## The four gaps, in priority order

### Step 1 — Grant a powerup straight to the player, and strip them

Right-click places a pickup on the field, which the player then has to walk
over. That is the wrong instrument for this job: collecting it runs
`give_powerup()`'s exclusivity rules against whatever the player already has,
which is precisely the interaction that has been hiding bugs.

Add to `_editor_key()` in `main.gd`:

- **`G`** — `sim.give_powerup(_editor_target(view.editor_cursor), view.editor_powerup)`.
  Grant the selected powerup directly, no pickup, no walking.
- **`X`** — strip the target player back to a newborn: zero `p.collected[]`
  across `Const_.POWERUP_COUNT`, `sim.cure_all(p)`, then
  `sim.recompute_powers(p)` (`sim.gd:2186`) to rebuild every derived flag from
  the cleared `collected` array. Do NOT hand-clear `can_kick`/`can_punch`/etc —
  `recompute_powers()` is the one place that owns that derivation and hand-
  clearing would drift from it.

`X` then `G` is the whole point: **exactly one powerup, nothing else**. That
combination is what proves or disproves "the red glove is broken" versus "the
kicker was eating the bomb first", which is the shape the last real bug had.

Acceptance: `X` then `G` with PUNCH selected leaves a player with
`can_punch=true` and every other `can_*` false and `collected` all-zero but
PUNCH.

### Step 2 — Freeze the clock

A bomb's fuze runs while you are reading the screen, so half the repro attempts
end in an explosion before the button is pressed.

- **`P`** — pause/unpause the simulation. `main.gd:_process()` (~line 1095)
  drives ticks from a `while _accum_ms >= TICK_MS` loop; gate that loop on a
  new `_paused` flag. Keep `view.queue_redraw_all()` running so the frozen
  frame still draws and the panel from step 3 still updates.
- **`.`** (period) — advance exactly one tick while paused, by calling `_step()`
  once. This is what makes "on which tick did the grab actually fire" an
  answerable question.

Acceptance: paused, a lit bomb's fuze does not fall; each `.` drops it by
exactly 1.

### Step 3 — Show the sim's own state on screen

This is the highest-value item and the reason the previous rounds could not
converge. Extend `_draw_test_editor()` in `game_view.gd` with a panel for the
target player, drawn only while `editor_active`:

- `can_kick`, `can_punch`, `can_grab`, `can_spooge`, `jelly_bombs`,
  `trigger_bombs` — the derived flags, read live off the `Player_`.
- `bombs_available` / `bombs_total`, `flame_len`, `speed`.
- `facing` as a compass word (`_compass()` already exists, `game_view.gd:1037`),
  `tile_x()`/`tile_y()`, `pickup_pause`, `kick_ticks`, `punch_ticks`.
- Active diseases by name, and the ticks left on each.
- Whether a bomb is **under** the player and whether one is **ahead** of them
  (`sim.bomb_at()`, `sim.gd:817`) plus, for the one ahead, whether the player
  owns it — `grab_bomb()` requires `b.owner == p.slot` and that requirement has
  never been visible to a tester.
- The last action the sim dispatched and the branch it took. Port the body of
  the temporary `_explain_action()` into a small ring buffer on the Sim (last
  ~8 entries, `tick`, `action`, `held`, and which branch won: placed / threw /
  grabbed / spooged / stopped / punched / triggered / **nothing**). "Nothing"
  is the answer the last three sessions needed and could not get.

Draw it in a corner, small font, semi-transparent backing so it does not cover
the field. Reuse whatever font the existing editor legend uses.

Acceptance: pressing the action button with no valid target visibly appends a
`nothing` entry naming the branch that refused.

### Step 4 — One flag that sets the whole thing up

`--test-range`, handled where the other flags are read (`main.gd:~647-760`).
It should imply, without the user having to remember the combination:

`--players 1 --bots 0 --scheme test_data/TESTALL.SCH`, the T editor already
open, the sim already paused, and the player stripped (step 1's `X`).

Acceptance: `godot --path . --test-range` lands in a solo, AI-free, paused game
with the panel up and a player holding nothing.

---

## Constraints — these are not negotiable

1. **`tools/verify.sh` must be green before and after.** Run it both times. It
   is the project's one gate and it has caught real regressions in this work
   already.
2. **Do not change `scripts/sim/` behaviour.** This is an instrument. The only
   permitted sim change is additive and inert: the action ring buffer from step
   3, which records and never decides. If building the tool seems to require a
   sim rule change, stop and report that instead — it means a bug was found,
   and it belongs in `POWERUP_REVIEW_PLAN.md`, not in a silent edit here.
3. **Determinism must survive.** The sim is replay- and netplay-deterministic
   and `tests/test_net.gd` / `test_netplay.gd` assert it. Anything the editor
   writes must go through the existing seeded `sim.rng`, never
   `randi()`/`Array.shuffle()`.
4. **Delete the scaffolding.** Once the step 3 panel works, remove
   `_explain_action()` and its `_debug_actions` static from `sim.gd`. Two
   diagnostics for one question is how the next session gets confused.
5. **Editor keys must not collide.** `B K D C R T [ ]` are taken, and the game
   itself uses `Escape`, `Ctrl-Q`, `F10`, `R`. Check `main.gd:_input()` before
   claiming `G X P .`.

---

## Still-open bugs this tool exists to settle

Hand these to whoever uses it first. Each one is a live report that the
automated tests call passing.

1. **Blue glove (GRAB) and red glove (PUNCH) reported still not working**,
   after five fixes that `verify.sh` says are correct and that a synthetic-key
   harness (`InputEventKey` → `Keysets` → `set_input` → `tick`) also says are
   correct. The exact question to answer with step 3's panel: at the moment of
   the press, is `can_grab`/`can_punch` actually true, is there a bomb in the
   cell the panel says the player faces, and does the player own it? One of
   those three is presumably false, and nobody has been able to see which.
2. **Top-centre flame arm drawn a few pixels right of centre.** Groundwork
   done, not yet fixed: `game_view.gd:_draw_flame_piece()` (~line 745) positions
   every flame piece by re-centring its frame width inside the cell
   (`_centre()`, ~line 802) with `use_hotspot=false`, rather than by the
   frame's own hotspot the way bombs and players are positioned
   (`game_view.gd:1087`). Measured from the real pack: the MFLAME frames along
   an arm's own axis are full-cell (41 px wide for east/west, 37 px tall for
   north/south) while the cross axis is cropped to a bounding box (north widths
   vary 22, 27, 22, 24, 25 across the five animation frames), and **every**
   MFLAME hotspot is the generic synthesized `(w/2, h-1)` rather than a real
   one. `tools/pack_assets.py:32` states the ANI does carry genuine per-frame
   hotspots that "genuinely vary", and `tools/anifile.py:50-51` parses
   `hotspot_x`/`hotspot_y` — so the most likely cause is that the real offsets
   are being discarded or overwritten for this sheet somewhere between
   `anifile.py` and `pack.json`, and the renderer's width-centring is a
   reconstruction standing in for them. **Verify that claim against
   `tools/pack_assets.py` before changing any renderer maths** — if the real
   hotspots are present and merely unused, the fix is in `_draw_flame_piece()`;
   if they were never written, the fix is in the extractor and the pack has to
   be rebuilt.

---

## Suggested order

Steps 1 and 3 first — together they answer bug 1, which is the one actually
blocking. Steps 2 and 4 are convenience and can follow. Bug 2 is independent of
the tool and can be done by a separate agent in parallel.
