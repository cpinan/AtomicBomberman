# STATUS — Atomic Bomberman (Godot 4 port)

_Last updated: 2026-09-21 · branch `main` · 0 uncommitted files, nothing unpushed_

## Next action

Fix `docs/IMPROVEMENTS.md` A1 — **the match never ends**. The server logs
`match over` and then nothing: no lobby, no menu, no stop, both windows stuck
on the final frame. It blocks live-testing everything else.

## State

- Twenty-four bugs fixed this session across powerups and netplay, all with
  regression tests. `tools/verify.sh` green; netplay alone is 135 checks.
- **Three plan documents carry the outstanding work.** `docs/IMPROVEMENTS.md`
  (defects with evidence, then game/UX and code recommendations),
  `docs/NETWORK_PLAN.md` (six items to make network play usable from the menu,
  with an inventory of what already exists so none of it gets rebuilt), and
  `docs/POWERUP_REVIEW_PLAN.md` (per-powerup history and what BM95.EXE says).
- Powerup behaviour now follows the disc rather than inference: the kick gate,
  re-kicking, the jelly quarter turn, the three-cell straight run, the
  punched-bomb hop model, no fuze in the air, and the arena wrapping for
  anything airborne — each commented with the address it came from.
- Netplay is sound in principle — server-authoritative, no prediction, state
  hashes equal across three clients — but everything around it assumes a
  developer with a terminal. Hosting and joining still need CLI flags.
- Single-player powerups are live-confirmed for the gloves and kick only.
  Everything from `7e574d2` onward has never been seen by a human.
- `docs/MULTIPLAYER.md` is the user-facing guide to playing together.

## In flight

- `godot-project/scripts/app/main.gd` `_input()` and `scripts/net/server.gd`'s
  C_START handler — tracing behind `AB_DEBUG_INPUT=1`. Every live bug this
  session was solved from a log, so do not simply delete these; fold them into
  the on-screen panel (step 3 of `docs/POWERUP_TEST_RANGE_PLAN.md`) first.
- `godot-project/scripts/sim/sim.gd` `_explain_action()` — same, behind
  `AB_DEBUG_ACTIONS=1`.
- `godot-project/scripts/render/game_view.gd` `_draw_flame_piece()` (~line 745)
  — the top-centre flame arm sits a few pixels right. Diagnosed, unfixed.
  **Check `tools/pack_assets.py` before touching renderer maths**: it decides
  whether the fix belongs in the renderer or the extractor.
- `godot-project/scripts/sim/sim.gd` `_landing_cell()` — precomputes a landing
  where BM95.EXE resolves each hop. All observable rules match now, so this is
  cosmetic; do it only if a future bug traces back to it.

## Verify

```bash
tools/verify.sh
```

**Close every game window first.** A live window holds the LAN discovery port
and `test_discovery.gd` then fails with "cannot listen on 47601", which looks
exactly like a real regression. It cost time twice on 2026-09-21.

## Open questions

- Delete `~/AtomicBomberman-pre-rewrite-backup.bundle` (457M) and
  `~/AtomicBomberman-sha-map-old-to-new.txt` when convenient — the history
  rewrite that removed 5,100 disc files from `win/` pushed cleanly, so they
  are only insurance now. `.git` went 491M to 2.8M.
- **Distribution is constrained by copyright.** The disc cannot ship: the port
  reads it through `AB_DATA` and `.gitignore` excludes every copy. Any GitHub
  release or web build needs players to supply their own game data. Routes
  sketched but not started: a hosted web build plus a public dedicated server
  (`build_web.sh`, `server/`, and `?join=ws://…` already exist), or exported
  binaries on GitHub Releases.
- A host once pressed Enter in the lobby with the key proven to reach `_input`
  and the round did not start. The cause was almost certainly the lobby reaper
  (fixed), but that specific run was never explained; `AB_DEBUG_INPUT=1` will
  catch it if it recurs.

## Do not redo

- **The player collision box is NOT the problem.** BM95.EXE `0x41EEE8` blocks
  movement on the cell ahead only when the along-axis offset is >= 0, which is
  what the full-cell box already produces. The kick/punch conflict was the
  missing "cell beyond the bomb must be free" test at `0x41EEAC`.
- **Do not re-read `punch_bomb()`/`grab_bomb()` hunting a glove bug.** Three
  sessions did; they were correct every time. A live "glove does nothing" is
  movement, rendering or ergonomics.
- **Do not recover a per-draw modulate by reading `COLOR` in `fragment()`** in
  `recolour.gdshader` — it does not survive canvas batching and collapses all
  ten players to two dark colours. Use the `actor_tint` uniform per slot node.
- **Do not make the disease tint a linear fade or leave green at 1.0.** A ramp
  measures 40/255 and reads as no blink; green at 1.0 is invisible on the
  green player. Square wave, all three channels dimmed.
- **Do not make a bomb's fuze run in the air** (`0x423F02`), and do not let a
  punched bomb bounce unconditionally — it comes to rest on the first clear
  cell (`0x423A60`) and hops on only past occupied ground.
- **Launch flags only reach the game after a bare `--`.** `godot --path .
  -- --serve 47600`; without it Godot eats them silently.
- **Every netplay test drives one input per tick; the real client sends six.**
  That difference hid the dropped-action bug behind 135 passing checks. When a
  live report contradicts a green suite, suspect the cadence, not the logic.
- **The wikis disagree with the disc and lose:** bomb cap is VALUELST 550 = 8,
  not 10, and the twelve diseases are the ones SOUNDLST.RES names.
