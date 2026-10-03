# STATUS — Atomic Bomberman (Godot 4 port)

_Last updated: 2026-10-02 · branch `main` · 0 uncommitted files, all pushed_

## Next action

`docs/IMPROVEMENTS.md` A2 — every powerup in a network game, with the T
editor on the host (`N` to pick, `G` to give). The 2026-10-02 network and
flame work was live-tested by the user that day and passed.

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
- The flame joint (A4) is fixed: vertical arms sit on the centre piece's
  stem (`game_view.gd` `_column_x()`/`_stem_x()`); `render_field.gd` checks
  the joint.
- **The repo is public** (https://github.com/cpinan/AtomicBomberman) and
  holds no disc-extracted content in tree or history.
- All of the 2026-10-02 work was live-tested by the user on 2026-10-02
  (two windows, one machine): hosting and joining from the menu, deaths and
  punched-bomb arcs on the guest, editor refusals, match end and play
  again, rejoin, on-screen failures, and the flame joint.

## In flight

- Unexamined: a window closed from the menu printed `WARNING: 2 ObjectDB
  instances were leaked at exit` (2026-10-02). Harmless at shutdown; start
  with `--verbose` to name the two objects.

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

- **The repository is PUBLIC since 2026-10-02.** Before that, history was
  rewritten to purge the disc's own content: three extracted screenshots
  and `server/schemes/{basic,og}.sch` (backup:
  `~/AtomicBomberman-pre-public-backup.bundle`, SHA map:
  `~/AtomicBomberman-sha-map-pre-public.txt`, the three images moved to
  `~/AtomicBomberman-disc-extracts/`). Never commit anything extracted
  from the disc — art, sounds, schemes or generated `values.gd`/`extras.gd`
  /`messages.gd`; `.gitignore` covers each.
- Delete when convenient: both backup bundles and SHA maps in `~/`
  (`AtomicBomberman-pre-rewrite-*`, `AtomicBomberman-pre-public-*`,
  `AtomicBomberman-sha-map-*`). The agent was blocked from deleting them.
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
