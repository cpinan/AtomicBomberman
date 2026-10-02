# STATUS — Atomic Bomberman (Godot 4 port)

_Last updated: 2026-10-02 · branch `main` · 0 uncommitted files, all pushed_

## Next action

Finish the live QA pass from 2026-10-02 on two machines: joining from the
menu was confirmed working by the user that day (two windows, one machine);
still unseen by a human are the match-end return to the lobby, rejoining a
dropped game, punched-bomb arcs and death animations on the guest, and the
flame joint (A4). Then `docs/IMPROVEMENTS.md` A2, every powerup online.

## State

- **Network play works from the menu with no flags.** The host's lobby shows
  its LAN address and the port to forward. The join field takes an address or
  a room code. A won match returns everyone to the lobby to play again.
  Protocol version 8.
- Failures land on the main menu with the reason on screen ("Lost the
  connection to the host", "Could not join: …"); the process no longer exits.
- A dropped player who rejoins under the same name gets their seat, colour
  and score back. Duplicate names are numbered (`player 2`), not refused.
- The T editor works in a hosted game (edits the server's sim; snapshots
  carry it). Joiners and `P` (pause) are refused with a message.
- `tests/test_snapshot_coverage.gd` fails for any field game_view.gd reads
  that no snapshot carries. It found `death_tick` and `fly_height` missing.
- Of the 2026-10-02 work, only hosting and joining from the menu has been
  seen by a human; the rest is verified by tests and rendered screenshots.

## In flight

- `scripts/app/main.gd` `_input()` and `scripts/net/server.gd` C_START —
  `AB_DEBUG_INPUT` tracing; `scripts/sim/sim.gd` `_explain_action()` —
  `AB_DEBUG_ACTIONS`. Fold into one on-screen panel (C3) before removing.

## Verify

```bash
tools/verify.sh
```

Needs Pillow. Homebrew's Python 3.14 has none, so `pack_assets.py` and the
artpack check fail. Either `python3 -m pip install pillow`, or point
`PYTHON=` at a venv that has it. verify.sh now refuses to start while a game
window holds UDP 47601. The machine sleeping mid-run looks like a hang: run
it under `caffeinate -i`.

## Open questions

- Delete `~/AtomicBomberman-pre-rewrite-backup.bundle` (457M) and
  `~/AtomicBomberman-sha-map-old-to-new.txt`. Checked 2026-10-02: the remote
  `main` matches the local one and no `win/` objects remain. The permission
  system blocked the agent from deleting them, so this one is for the user.
- A3, the level selection screen, and B2, a held-powerups HUD strip — design
  decisions; check what the original shows first.
- Room codes need a `--directory` server; no default one exists, so the menu
  has no room code without flags. Typing an address works without one.
- Distribution is constrained by copyright (players supply their own disc
  data). Unchanged.

## Do not redo

- **A4 is fixed by moving the vertical arms onto the centre piece's stem.**
  Do not move the centre piece instead (opens a seam to the west arm) and
  do not ink-centre every piece on both axes (breaks the horizontal arm).
  Measure at the JOINT — mid-cell bands cannot see this bug.
- **A finished match goes to the lobby, not the menu, in network play** —
  `server.gd` `_back_to_lobby()`. Local play still goes to the victory screen.
- **The player collision box is NOT the problem.** BM95.EXE `0x41EEE8`; the
  kick/punch conflict was the "cell beyond must be free" test at `0x41EEAC`.
- **Do not re-read `punch_bomb()`/`grab_bomb()` hunting a glove bug.**
- **Do not recover a per-draw modulate from `COLOR` in `recolour.gdshader`**;
  use the `actor_tint` uniform per slot node.
- **Disease tint: square wave, all three channels dimmed.** Not a linear fade.
- **No fuze in the air** (`0x423F02`); a punched bomb rests on the first clear
  cell (`0x423A60`).
- **Every netplay test used to drive one input per tick; the real client
  sends six.** When a live report contradicts a green suite, suspect cadence.
- **Wikis lose to the disc:** bomb cap is VALUELST 550 = 8; diseases are the
  twelve SOUNDLST names.
