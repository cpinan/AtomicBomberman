# STATUS — Atomic Bomberman Godot port

_Last updated: 2026-09-21 · branch `main` · 1 uncommitted file_

## Next action

**Live-playtest GRAB (blue glove)**: hold Space to carry a bomb, release to
throw it. This exact powerup has been "fixed" twice already this session
(commits `5070741`, `75c4734`) and the second fix has never been confirmed
live — see `docs/POWERUP_REVIEW_PLAN.md` §7 for exact repro steps before
reporting it broken again.

## State

- Same baseline as before: game starts/plays/finishes on the original's own
  screens, art, sounds and level data — 67 schemes, 13 powerups, 12
  diseases, campaign mode, server-authoritative WebSocket netplay.
- This session's bug-hunt round (playtesting + fixes, commits `210aa39`,
  `5070741`, `75c4734`): level preview now draws real layout not just
  background; cornerhead no longer replays every variant while trapped;
  jelly bomb bounce snaps to cell centre (no more sitting-in-the-wall
  glitch) and keeps its wobble sprite mid-flight; powerup exclusivity
  matrix fixed to match MANUAL.BM's own table (Trigger↔Jelly, Trigger↔Punch,
  Grab↔Spooge — was backwards); Super Bad Disease now gives up to 3
  diseases, not 1; punch no longer plays its animation over a zero-distance
  blocked throw; options now survive returning to the menu after a match
  (root cause: `_teardown()` nulled `menu` before a match even began); grab
  is hold-to-carry/release-to-throw (see Next action — unverified).
- Invented (no original asset existed): a sickly-green tint pulse on a
  diseased player, since nothing marked disease state visually before.
- New feature this session: internet multiplayer via a room-code
  directory, not a traffic relay — `directory/` (Node, zero deps, own test
  suite) maps a short code to a dedicated server's `ws://` URL; hosting
  from the menu now opens a lobby (roster, host presses Start) instead of
  starting instantly; `scripts/net/directory.gd` is the Godot-side client.
  All 4 build-order steps done and committed (`75fe013`, `fa47130`,
  `bb82918`, `4eac232`) — plan doc at
  `~/.claude/plans/stateless-mapping-mist.md`. **Nothing has left
  localhost/LAN yet** — see Open questions.
- `tools/verify.sh` green throughout this session's changes (last full run:
  all suites passing, counts grew — e.g. `powerups` 168→236 checks,
  `abilities` 179→181, new `directory` and `net` coverage added).

## In flight

- `docs/POWERUP_REVIEW_PLAN.md` (uncommitted, user chose to keep local) —
  per-powerup bug/status handoff doc, written for delegating a live
  playtest pass to another agent. GRAB and SPOOGE flagged top priority
  (GRAB just changed mechanics again; SPOOGE has never been live-tested at
  all this session, sim-layer only).

## Verify

```bash
tools/verify.sh                  # full suite, run from repo root
```

`AB_DATA` overrides where the disc is found (default `../original-game`
from `godot-project/`). **Never run two Godot processes against this
project at once** — they share a LAN discovery port and corrupt each
other's results; `pkill -f Godot.app` before relaunching to test a fix,
every time — stale-process confusion caused several false "still broken"
reports this session.

## Open questions

- **GRAB's hold-to-carry/release-to-throw mechanic** (commit `75c4734`) —
  live-unconfirmed, see Next action.
- **SPOOGE** — never live-playtested this session at all, sim-layer only.
- **Internet multiplayer is untested beyond localhost/LAN.** To actually
  prove it: deploy `directory/` and `server/` (see each README) to a real
  VPS, launch the dedicated server with `--directory <url> --public-host
  <ip-or-domain>`, and join from a genuinely different network. Everything
  built so far only proves the mechanism works, not that it reaches the
  open internet.
- **Menu-hosted (not dedicated-server) internet play has a known gap**: a
  room code only works if that host's own machine is reachable from the
  internet (port-forwarded) — the lookup-only directory design (chosen over
  a full relay) can't solve NAT for a home host. Worth deciding whether
  that's acceptable or whether the relay alternative from the plan's first
  draft should be revisited.
- **AI kicks a bomb before fleeing danger it's standing in** (`ai.gd`,
  entry 1 before entry 2) — matches the original's own disassembled
  decision order, so may be intentional fidelity rather than a bug.
  Flagged for a decision, not fixed either way.
- Pixels/pad/`.AAF`/`APPLBITE` family — unchanged from before this session,
  see prior open questions below (carried forward, still true).
- **Pixels.** The art pipeline is proven; nobody has drawn a replacement
  set. Until then no build is distributable. `docs/ART.md`.
- **A pad.** The gamepad layer is tested against synthesised events only;
  nobody has held a real controller.
- **`.AAF` is not cracked** — five antialiased fonts from `INSTALL.DAT`.
  Zero port value (they're the *setup program's* fonts). `docs/ORACLE.md` §9.
- **`APPLBITE`/`NUCKBLOW`/`ZEN`** — a still-unexplained 73×73 animation
  family, distinct from cornerhead. Name appears nowhere on the disc's own
  text.
- **Death animation/cornerhead netcode sync** — neither is in
  `Player_.to_bytes()`/`state_hash()`, so a joining client doesn't see
  either animation correctly. Cosmetic only.

## Do not redo

- **The default keys are `INPUT.BM`'s, not an invention** — cursor keys +
  Space + Enter, and R/D/F/G + S + A. Do not "improve" them to WASD.
- **The test editor is on `T`, not F3** — F3 is macOS's own Mission Control
  shortcut on most keyboards; the OS eats it before Godot sees it.
- **The status panel is 42 px** (`Const_.HUD_H`); `FIELD_Y_OFF` is 68.
- **Flame frames are centred on the cell**, never anchored on their hotspot
  — centring an odd-width sprite in the 40px-wide cell has an irreducible
  0.5px error; don't re-litigate this as a rounding bug (`docs/BUGS.md` Q10).
- **A game left open in another window breaks netplay-adjacent test
  suites AND causes false "still broken" playtest reports** — this session
  hit the latter repeatedly: a fix was correct but the tester was still on
  a stale process. Kill stray headless/GUI Godot processes before either
  running tests or handing the app back for a retest:
  `pkill -f Godot.app`.
- **The movement algorithm is read but deliberately not adopted** (Q5.1).
- **The AI's search is a graded danger map + BFS, not the original's
  cloning-walker frontier** — a deliberate, documented simplification
  (Q5.4), not a bug to "fix" toward fidelity. Its decision ORDER (kick
  before flee) is a separate, still-open question — see Open questions.
- **The netplay server-override key is scoped to mid-round demote/restore
  only**, distinct from the NEW pre-round lobby built this session — don't
  conflate the two; the lobby (roster + host Start) is a different feature
  added on top, not a replacement for the override key.
- **`bmexe.py`'s `--xref` only follows DIRECT call targets** — an
  indirectly-dispatched function's own resource reads get attributed to
  whichever function calls it. If a resource's "owning function" via
  `--xref` doesn't contain the code you expect, read that function's own
  instructions directly.
- **The directory service (`directory/`) is a lookup table, not a
  relay** — no game traffic passes through it, on purpose (chosen over a
  full relay to keep the build small; see
  `~/.claude/plans/stateless-mapping-mist.md` for why). Don't "fix" it by
  routing gameplay bytes through it — that's a different, bigger feature.
- **GRAB's mechanic has flip-flopped twice** (tap-then-tap → hold-to-carry/
  release-to-throw) — before changing it again, get an explicit, exact
  description of the wanted behavior from the user first; guessing burned
  two iterations already.
