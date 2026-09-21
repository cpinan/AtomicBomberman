# STATUS — Atomic Bomberman (Godot 4 port)

_Last updated: 2026-09-21 · branch `main` · 7 uncommitted files_

## Next action

Live-playtest the **punch whiff animation** (`sim.gd:_player_action`, SECOND branch): wear
only the Boxing Glove, press Enter with no bomb anywhere, and confirm the glove
visibly swings. It was written in response to a live report and the game was
closed before it was tested once — the session log for that run recorded zero
action presses.

## State

- Eight powerup bugs found and fixed this session, all with regression tests in
  `godot-project/tests/test_abilities.gd` (207 checks). `tools/verify.sh` is
  green. None of the eight is live-confirmed yet — see "In flight".
- The previous three rounds of "glove" fixes were aimed at the wrong layer. The
  sim's ability functions (`punch_bomb`, `grab_bomb`, `stop_bomb`) were correct
  all along; every real bug was in movement, rendering, a timer that never ran,
  or a function that was never called. `docs/POWERUP_REVIEW_PLAN.md` has the
  full write-up per powerup.
- The T test editor now has the keys needed to test one powerup in isolation:
  `X` strips a player to newborn, `G` gives the selected powerup directly, `P`
  pauses, `.` steps one tick. A live state line shows `can_*` flags, facing,
  and whether a bomb is under/ahead.
- `docs/POWERUP_TEST_RANGE_PLAN.md` is a delegation-ready plan for the rest of
  that tooling (steps 3 and 4 are unbuilt: the full on-screen action-history
  panel, and a single `--test-range` flag).
- Deliberately NOT built: any change to the player collision box (see Open
  questions).

## In flight

- `godot-project/scripts/sim/sim.gd:~646` — `_explain_action()` and its
  `_debug_actions` static are **temporary scaffolding**, gated on
  `AB_DEBUG_ACTIONS=1`. Delete them once the test-range panel (step 3 of
  `docs/POWERUP_TEST_RANGE_PLAN.md`) replaces them. Two diagnostics for one
  question is how the next session gets confused.
- `godot-project/scripts/render/game_view.gd:~745` `_draw_flame_piece()` — the
  reported "top-centre flame arm sits a few px right" is diagnosed but NOT
  fixed. Groundwork and the exact next step are in
  `docs/POWERUP_TEST_RANGE_PLAN.md` under "Still-open bugs", item 2. Short
  version: flames are positioned by re-centring frame width with
  `use_hotspot=false`, while every MFLAME hotspot in the pack is the generic
  synthesised `(w/2, h-1)`. `tools/pack_assets.py:32` claims the ANI carries
  real per-frame hotspots that "genuinely vary" — verify that against
  `tools/pack_assets.py` BEFORE touching renderer maths, because it decides
  whether the fix is in the renderer or in the extractor.
- Nothing is committed. All eight fixes plus both plan docs are in the working
  tree.

## Verify

```bash
tools/verify.sh
```

## Open questions

- **Player collision box, for the user to decide.** With KICK and PUNCH both
  held, punch is close to unreachable: aiming a glove means facing the bomb,
  facing it means pressing toward it, and this port's full-cell collision box
  makes "standing in the next cell" already count as contact, which fires the
  kick. The original almost certainly used a smaller box with a gap.
  `docs/BUGS.md` Q5.1 already flags the box as an assumption. Changing it is a
  real behaviour change affecting all movement, so it was left alone.
- **Disease tint strength**, unconfirmed live. The pulse reaches the screen now
  (it never did before), but whether it reads clearly on every player colour
  has not been seen by a human.

## Do not redo

- **Do not re-read `punch_bomb()`/`grab_bomb()` looking for the glove bug.**
  Three sessions did. They are correct, and were verified again this session
  through the real keyboard path (synthetic `InputEventKey` → `Keysets` →
  `set_input` → `tick`, not direct calls). A live "glove does nothing" report
  is a movement, render or ergonomics problem, not a sim one.
- **Do not recover a per-draw modulate by reading `COLOR` at the top of
  `fragment()` in `recolour.gdshader`.** Tried; it does not survive Godot's
  canvas batching and multiplied every sprite by something that was not white.
  `tests/render_recolour.gd` caught it as all ten players collapsing to two
  dark colours. The working mechanism is the `actor_tint` uniform set per slot
  node, alongside the existing `player_slot`/`target_colour` uniforms.
- **Do not make a disease tint that leaves the green channel at 1.0.** The
  original `Color(0.55, 1.0, 0.45)` was invisible on the green player — the one
  channel it did not touch. All three channels must dim, green least.
- **Do not "fix" a punch into a wall by refusing it.** An earlier session did,
  and a test asserted it. MANUAL.BM line 208 is explicit: "Throw and punch your
  bombs over the wall to destroy your opponents." `_landing_cell()` now flies
  the full distance and overshoots to the next free cell; it only refuses when
  the whole line to the arena edge is solid.
- **A session log showing six bombermen with `--players 1` is not a bug.**
  Starting a new match from the in-game menu replaces the CLI solo setup with
  the menu's own roster, AI included. Check the scheme name in the log first.
