# STATUS — Atomic Bomberman (Godot 4 port)

_Last updated: 2026-09-21 · branch `main` · 0 uncommitted files_

## Next action

Start `docs/NETWORK_PLAN.md` — item 3 (audit the network logic) for anything
that blocks play, then items 1 and 2 (the host and join screens) together.
Before that, live-playtest everything from `7e574d2` onward — throw a bomb off an arena
edge (it should reappear on the far side, not drop at your feet), throw two
at the same cell (they must not stack), throw one along an open row (it
should bounce on a cell at a time and only tick once it settles), kick a
jelly bomb (straight for three cells, then wandering), and catch a disease
(the tint should flash on/off twice a second). None of it has been seen by a
human yet.

## State

- Twenty-one powerup bugs fixed across six commits this session, all with
  regression tests in `godot-project/tests/test_abilities.gd` (264 checks).
  `tools/verify.sh` green.
- The gloves, kick and the action button are **live-confirmed working** as of
  this session. Everything from `0a06b1a` onward is not.
- The punched/thrown bomb model now matches the disc: a three-cell first hop
  at the tall arc, one-cell bounces at the small arc for thrown bombs as well
  as punched ones, no fuze advance while airborne, a per-bomb cell counter
  holding a jelly bomb straight for three cells, and the arena wrapping for
  anything in the air.
- Three powerup rules now come from BM95.EXE rather than inference, each
  commented with its address: the kick gate (`0x41EE51`), re-kicking a rolling
  bomb (`0x42464B`), and the jelly quarter turn (`0x423A1E`). `tools/bmexe.py`
  is the tool; `docs/POWERUP_REVIEW_PLAN.md` records what was read.
- The T test editor can isolate one powerup: `X` strips a player to newborn,
  `G` gives the selected one directly, `[`/`]` choose, `P` pauses, `.` steps one
  tick, and a status line shows the `can_*` flags, facing, and whether a bomb is
  under/ahead.
- All 13 powerups audited against VALUELST and SOUNDLST; no further gaps found.
- **Netplay: every action over the wire used to be dropped about five times
  in six.** A joined client sends input once per rendered frame while the
  server ticks at 20 Hz, so a press arrived as one FIRST packet followed by
  several NONEs, and the server applied each straight to the sim — the NONEs
  overwrote the press before any tick consumed it. Fixed by latching: a NONE
  no longer clears a pending action, only the tick does. This affected bombs,
  punch, trigger, kick-stop and grab/throw equally; all of them will have felt
  unreliable online and none has been re-tested live since the fix.
- `docs/MULTIPLAYER.md` is the user-facing guide to playing together, and
  `docs/NETWORK_PLAN.md` is the plan for making network play usable from the
  menu (host/join screens, a network audit, docs, and a gameplay comparison
  against the original).
- Three netplay faults fixed and pushed in `60d6b0a`: the lobby reaped
  waiting players after 30 s (which is what "Enter is not working" was),
  animation timers never crossed the wire so networked players never animated
  dying/kicking/punching, and a send to an already-closing socket logged an
  engine error that verify.sh reads as a dead suite.
- Deliberately NOT built: the per-hop bomb flight model (see "In flight").

## In flight

- `godot-project/scripts/sim/sim.gd` `_landing_cell()` — the last structural
  difference, and now a cosmetic one rather than a behavioural one: this port
  precomputes a landing cell and interpolates to it, where BM95.EXE resolves
  each hop as it arrives. The observable rules all match now (three-cell first
  hop, one-cell bounces after, no fuze in the air, the +0x48 cell counter, the
  wrap), so this is worth doing only if a future bug traces back to it. It is
  why the overlap, arena-edge and "nowhere to go" cases each needed their own
  patch where the original needs none. Addresses in
  `docs/POWERUP_REVIEW_PLAN.md`.
- `godot-project/scripts/app/main.gd` `_input()` and
  `godot-project/scripts/net/server.gd`'s C_START handler — temporary tracing
  behind `AB_DEBUG_INPUT=1`, printing `[key] code=... mode=... in_lobby=...
  is_host=...` and `[srv] C_START from N, host_peer_id=M`. Kept because the
  lobby-start problem below is not fully explained; remove once it is.
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

- `win/Atomic Bomberman - CDRIP/` carries the PRINTED MANUAL as a PDF, which
  `MANUAL.BM` is only a text subset of. `pdftotext` gets usable (OCR-noisy)
  text; the powerup descriptions are around lines 285-400. It is the source
  that settled the airborne-fuze rule and independently confirmed the kick
  rule ("walk into any UNOBSTRUCTED bomb"). Its BM95.EXE, VALUELST, SOUNDLST
  and MANUAL.BM are all identical to `original-game/`; it adds one scheme,
  `DOUG.SCH`. **Check the PDF before inferring a mechanic** — it is the most
  detailed prose source available.
- `win/Bomberman/` is a SECOND INSTALL of the same game, not source. Its
  `bombeman.EXE` has the same MD5 as `original-game/BM95.EXE`
  (`380baabe114af0596d860477d976a4c7`), and VALUELST.RES and the manual are
  byte-identical; its SOUNDLST.RES is a cut-down copy missing the announcer
  samples, so `original-game/` stays the reference tree. Nothing further to
  mine there.
- Observed 2026-09-21, not chased: a player stood on tiles `(0,7)` and `(7,0)`,
  the arena's outer ring. Either legitimate scheme data for that level or a
  border that is not solid. Unrelated to powerups, so left alone.
- **A host once pressed Enter in the lobby and the round did not start**, with
  the key proven to reach `_input` (`code=4194309 mode=2 in_lobby=true`). A
  later run with the same code started fine and the trace showed the whole
  chain working, so the cause is unknown and it may be a race on `lobby_is_host`
  arriving with S_LOBBY. `AB_DEBUG_INPUT=1` will catch it next time.
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
- **Do not make a bomb's fuze run while it is in the air.** BM95.EXE
  `0x423F02` skips the timer for the punched and bouncing states, and the PDF
  manual says it plainly of The Hand: "The bomb is not active until it hits
  the ground." Bouncing is ended by running into something, never by the fuze.
- **Do not "fix" a punch into a wall by refusing it.** MANUAL.BM: "Throw and
  punch your bombs over the wall to destroy your opponents." A punch refuses
  only when the whole line, wrapped, has no free cell.
- **Launch flags only reach the game after a bare `--`.** `godot --path .
  -- --serve 47600` works; without the separator Godot eats it and you get a
  default local game. Measured: `-- --scale 1` gives a 640x480 window, the
  plain form 1920x1440.
- **A non-host pressing Enter in the lobby is correctly ignored** — the server
  only honours C_START from `host_peer_id`. It used to do so silently, which
  cost a live session; the lobby now says "Only the host can start this game".
- **Six bombermen with `--players 1` is not a bug** — starting a match from the
  in-game menu replaces the CLI solo setup with the menu's roster, AI included.
  Check the scheme name in the log first.
- **The wikis disagree with the disc on two points and the disc wins:** the bomb
  cap is VALUELST 550 = 8, not 10; and the twelve diseases are the ones
  SOUNDLST.RES names per 50-resource group, which excludes the "can't stop" and
  "long fuse" of other Bomberman titles.
