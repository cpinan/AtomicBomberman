# STATUS — Atomic Bomberman (Godot 4 port)

_Last updated: 2026-09-21 · branch `main` · 0 uncommitted files_

## Next action

Live-playtest the three fixes in `7e574d2` — throw a bomb off an arena edge (it
should reappear on the far side, not drop at your feet), throw two bombs at the
same cell (they must not stack), and catch a disease (the tint should flash
on/off twice a second). None has been seen by a human yet.

## State

- Sixteen powerup bugs fixed across three commits this session, all with
  regression tests in `godot-project/tests/test_abilities.gd` (260 checks).
  `tools/verify.sh` green.
- The gloves, kick and the action button are **live-confirmed working** as of
  this session. Everything in `0a06b1a` and `7e574d2` is not.
- Three powerup rules now come from BM95.EXE rather than inference, each
  commented with its address: the kick gate (`0x41EE51`), re-kicking a rolling
  bomb (`0x42464B`), and the jelly quarter turn (`0x423A1E`). `tools/bmexe.py`
  is the tool; `docs/POWERUP_REVIEW_PLAN.md` records what was read.
- The T test editor can isolate one powerup: `X` strips a player to newborn,
  `G` gives the selected one directly, `[`/`]` choose, `P` pauses, `.` steps one
  tick, and a status line shows the `can_*` flags, facing, and whether a bomb is
  under/ahead.
- All 13 powerups audited against VALUELST and SOUNDLST; no further gaps found.
- Deliberately NOT built: the per-hop bomb flight model (see "In flight").

## In flight

- `godot-project/scripts/sim/sim.gd` `_landing_cell()` — **the one structural
  mismatch left.** BM95.EXE moves a punched bomb in one-cell HOPS with a hop
  counter at struct offset `+0x48`; the arc is resource 660 while that counter
  is under 3 and 661 from 3 onward, which is what "initial three-space bounce
  height" versus "subsequent one-space bounces" actually means, and the same
  counter gates the jelly turn so a punch's first three cells are straight
  (`0x4243F5`, `0x423991`). This port precomputes a landing cell and
  interpolates one flight to it. Every throw/punch bug reported this session —
  bombs stacking, the arena edge, the "nowhere to go" refusal the original
  never needs — came from that mismatch and was patched at the landing-search
  level instead. Three patches where the original has one model. Full write-up
  with addresses in `docs/POWERUP_REVIEW_PLAN.md`.
- `godot-project/scripts/sim/sim.gd` `_explain_action()` — temporary
  scaffolding behind `AB_DEBUG_ACTIONS=1`. Delete it once the on-screen action
  history (step 3 of `docs/POWERUP_TEST_RANGE_PLAN.md`) exists.
- `godot-project/scripts/render/game_view.gd` `_draw_flame_piece()` (~line 745)
  — the "top-centre flame arm sits a few px right" report is diagnosed, not
  fixed. `docs/POWERUP_TEST_RANGE_PLAN.md`, "Still-open bugs" item 2, has the
  measurements and says to check `tools/pack_assets.py` BEFORE touching
  renderer maths: that decides whether the fix belongs in the renderer or in
  the extractor.

## Verify

```bash
tools/verify.sh
```

**Close the game first.** It holds the LAN discovery port, and
`test_discovery.gd` then fails with "cannot listen on 47601" — which looks
exactly like a real regression and is not one.

## Open questions

- Observed 2026-09-21, not chased: a player stood on tiles `(0,7)` and `(7,0)`,
  the arena's outer ring. Either legitimate scheme data for that level or a
  border that is not solid. Unrelated to powerups, so left alone.
- Whether to do the per-hop flight rework at all, or keep the landing-cell
  model now that its known symptoms are patched.

## Do not redo

- **The player collision box is NOT the problem, and this is settled.** An
  earlier session suspected the full-cell box made PUNCH and GRAB unreachable
  alongside KICK. BM95.EXE `0x41EEE8` blocks movement on the cell ahead only
  when the along-axis offset is >= 0, producing the same stopping positions the
  full-cell box already produces — the original kicks from the adjacent cell
  centre too. The real cause was the missing "cell beyond the bomb must be
  free" test at `0x41EEAC`. Leave the box alone.
- **Do not re-read `punch_bomb()`/`grab_bomb()` hunting a glove bug.** Three
  sessions did. They were correct every time. A live "glove does nothing"
  report is movement, rendering or ergonomics.
- **Do not recover a per-draw modulate by reading `COLOR` in `fragment()`** in
  `recolour.gdshader`. It does not survive Godot's canvas batching;
  `tests/render_recolour.gd` catches it as all ten players collapsing to two
  dark colours. The working mechanism is the `actor_tint` uniform per slot node.
- **Do not make the disease tint a linear fade, and do not leave green at 1.0.**
  The ramp measured 40/255 mean across the sprite and read live as "doesn't
  blink"; leaving green at 1.0 made it invisible on the green player. A square
  wave with all three channels dimmed measures 48/255 mean, 138/255 worst.
- **Do not "fix" a punch into a wall by refusing it.** MANUAL.BM: "Throw and
  punch your bombs over the wall to destroy your opponents." A punch refuses
  only when the whole line, wrapped, has no free cell.
- **Six bombermen with `--players 1` is not a bug** — starting a match from the
  in-game menu replaces the CLI solo setup with the menu's roster, AI included.
  Check the scheme name in the log first.
- **The wikis disagree with the disc on two points and the disc wins:** the bomb
  cap is VALUELST 550 = 8, not 10; and the twelve diseases are the ones
  SOUNDLST.RES names per 50-resource group, which excludes the "can't stop" and
  "long fuse" of other Bomberman titles.
