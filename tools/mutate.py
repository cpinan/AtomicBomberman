#!/usr/bin/env python3
"""Mutation testing for the Godot port: break each fix on purpose, on the
assumption that a suite which cannot fail is not a suite.

WHY THIS EXISTS. Every defect a player has found in this port was found while
the whole test suite was green — 5,600 checks the first time, 6,100 the second.
Adding an assertion after the fact proves nothing on its own: the assertion has
to be shown to FAIL when the fix is taken away. This runs that experiment for
every fix worth keeping.

Each entry is (label, file, the code as it is now, the code as it was when it
was wrong, the suites that should notice). The file is patched, the named
suites are run, the file is restored whatever happens, and an entry whose
suites all stay green is reported as an ESCAPE — a fix nothing is holding in
place.

    tools/mutate.py                 run every mutation
    tools/mutate.py PATTERN         only those whose label contains PATTERN

Run it from `godot-project/`, or with --path. A mutation whose "as it is now"
text is not found is reported as a SKIP and counted as an escape, because the
usual cause is the code having moved on without the mutation following it.

The exit code is the number of escapes, so this is usable from a shell script.
Deliberately NOT part of verify.sh: it edits sources and runs the suites many
times over, which is a minute of wall clock and a bad thing to have running
while somebody is editing the same files.
"""

from __future__ import annotations

import argparse
import os
import subprocess
import sys

GODOT = os.environ.get(
    "GODOT", "/Applications/Godot.app/Contents/MacOS/Godot")

MUTATIONS = [
 ("menu: options walks into the slots again",
  "scripts/app/menu.gd",
  """	# The options list, with Item.SLOTS stepped over because it is not on it.
	var step := 1 if delta >= 0 else -1
	var target := cursor
	for i in absi(delta):
		target = posmod(target + step, item_count())
		if target == Item.SLOTS:
			target = posmod(target + step, item_count())
	cursor = target""",
  """	var target := posmod(cursor + delta, item_count())
	if target == Item.SLOTS:
		in_slots = true
		slot_cursor = 0 if delta > 0 else slots.size() - 1
	cursor = target""",
  ["test_menu.gd", "test_play.gd"]),

 ("screens: the scroll counter is not clamped",
  "scripts/app/screens.gd",
  "	text_scroll = clampi(text_scroll + delta, 0, maxi(total_lines - rows, 0))",
  "	text_scroll = maxi(text_scroll + delta, 0)",
  ["test_screens.gd", "test_play.gd"]),

 ("sim: a dying player takes input again",
  "scripts/sim/sim.gd",
  "	if not p.alive or p.dying:\n		return\n	p.move = move\n	p.action = action",
  "	p.move = move\n	p.action = action",
  ["test_round.gd"]),

 ("sim: nothing ever clears alive",
  "scripts/sim/sim.gd",
  "		if tick_count - p.death_tick >= DEATH_TICKS:\n			p.alive = false",
  "		if false:\n			p.alive = false",
  ["test_round.gd"]),

 ("sim: END replaces the arm bit again",
  "scripts/sim/sim.gd",
  "		field.add_flame(x, y, arm | (Types_.Flame.END if stops else 0),\n			b.chain_owner, _flame_ticks)",
  "		field.add_flame(x, y, Types_.Flame.END if stops else arm,\n			b.chain_owner, _flame_ticks)",
  ["test_bomb.gd", "render_field.gd"]),

 ("view: flames anchored on the actor anchor again",
  "scripts/render/game_view.gd",
  "	var at := origin + (Vector2(Const_.BLOCK_W, Const_.BLOCK_H)\n		- src.size) / 2.0\n	_draw_frame(\"mflame\", index, at, false, Color.WHITE, on, true)",
  "	var at := Const_.actor_anchor(Vector2(Player_.tile_centre_x(tx),\n		Player_.tile_centre_y(ty)) / CP)\n	_draw_frame(\"mflame\", index, at, true, Color.WHITE, on, true)",
  ["render_field.gd"]),

 ("view: actors clipped to the top of the screen again",
  "scripts/render/game_view.gd",
  "		field.size.y += field.position.y - float(Const_.HUD_H)\n		field.position.y = float(Const_.HUD_H)",
  "		field.size.y += field.position.y\n		field.position.y = 0.0",
  ["render_field.gd"]),

 ("view: the clock sits where it overran the panel",
  "scripts/render/game_view.gd",
  "	var top := 8.0",
  "	var top := 16.0",
  ["render_hud.gd"]),

 ("view: the player discs overrun the panel again",
  "scripts/render/game_view.gd",
  "		var centre := Vector2(x + 13.0, 21.0)\n		var colour := Const_.player_colour_f(p.slot)\n		var alive: bool = p.alive and not p.dying\n		on.draw_circle(centre, 12.0, Color(0, 0, 0, 0.45))",
  "		var centre := Vector2(x + 15.0, 30.0)\n		var colour := Const_.player_colour_f(p.slot)\n		var alive: bool = p.alive and not p.dying\n		on.draw_circle(centre, 13.0, Color(0, 0, 0, 0.45))",
  ["render_hud.gd"]),

 ("menu: a game of nothing but AI is allowed again",
  "scripts/app/menu.gd",
  "	if keyboard_count() == 0 and pad_count() == 0 and campaign.is_empty():",
  "	if false:",
  ["test_menu.gd"]),
 ("view: a punch is drawn as standing again",
  "scripts/render/game_view.gd",
  "		if p.punch_ticks > 0 and pack.has_sheet(\"punch\"):",
  "		if false and pack.has_sheet(\"punch\"):",
  ["render_field.gd"]),

 ("view: carrying a bomb is drawn as walking again",
  "scripts/render/game_view.gd",
  "		if _is_carrying(p.slot) and pack.has_sheet(\"bombwalk\"):",
  "		if false and pack.has_sheet(\"bombwalk\"):",
  ["render_field.gd"]),

 ("view: picking a bomb up is drawn as standing again",
  "scripts/render/game_view.gd",
  "		if p.pickup_pause > 0 and pack.has_sheet(\"bpickup\"):",
  "		if false and pack.has_sheet(\"bpickup\"):",
  ["render_field.gd"]),

 ("view: every bomb is the plain bomb again",
  "scripts/render/game_view.gd",
  "	var tries: Array = []\n	if b.triggered:",
  "	var tries: Array = []\n	if false:",
  ["render_field.gd"]),

 ("sim: a carried bomb is drawn on the ground too",
  "scripts/render/game_view.gd",
  "		if b.carried_by >= 0:\n			continue",
  "		if false:\n			continue",
  ["render_field.gd"]),

 ("sim: a bomb landing on your head does nothing again",
  "scripts/sim/sim.gd",
  "	_bomb_on_the_head(b)",
  "	pass",
  ["test_abilities.gd"]),

 ("sim: the derived stats are not recomputed after a loss",
  "scripts/sim/sim.gd",
  "		if lost > 0:\n			recompute_powers(p)",
  "		if lost > 0:\n			pass",
  ["test_abilities.gd"]),

 ("keys: the invented defaults come back",
  "scripts/app/keysets.gd",
  '	"first": KEY_SPACE, "second": KEY_ENTER,',
  '	"first": KEY_ENTER, "second": KEY_BACKSPACE,',
  ["test_keys.gd", "test_play.gd"]),

 ("keys: an old keys.cfg is loaded over the corrected defaults",
  "scripts/app/keysets.gd",
  "	if int(cfg.get_value(\"keys\", \"version\", 1)) != CONFIG_VERSION:",
  "	if false:",
  ["test_keys.gd"]),

 ("menu: T cannot change a team again",
  "scripts/app/menu.gd",
  "	slot_team[slot_cursor] = 1 - slot_team[slot_cursor]\n	return true",
  "	return true",
  ["test_menu.gd"]),

 ("menu: Ctrl-A converts nothing",
  "scripts/app/menu.gd",
  "		if slots[i] != Slot.AI:\n			slots[i] = Slot.AI\n			changed += 1",
  "		if slots[i] != Slot.AI:\n			changed += 1",
  ["test_menu.gd"]),

 ("sim: F10 does not force a draw",
  "scripts/sim/sim.gd",
  "	outcome = Outcome.DRAW\n	winner_slot = -1",
  "	winner_slot = -1",
  ["test_round.gd"]),

 ("main: Ctrl-A goes back to being an arm of the same match as left",
  "scripts/app/main.gd",
  "	if on_setup and menu != null and key.ctrl_pressed \\\n			and key.keycode == KEY_A:",
  "	if false and key.ctrl_pressed \\\n			and key.keycode == KEY_A:",
  ["test_play.gd"]),

 ("main: T is not wired to the setup screen",
  "scripts/app/main.gd",
  "			if on_setup and menu != null:\n				if not menu.toggle_team():",
  "			if false:\n				if not menu.toggle_team():",
  ["test_play.gd"]),

]


def run(name: str, here: str) -> str:
    """Run one suite and return its output. render_* suites need a real GPU
    context and so are run windowed, exactly as verify.sh runs them."""
    windowed = name.startswith("render_")
    cmd = [GODOT, "--path", here, "--script", "res://tests/" + name]
    if windowed:
        cmd[1:1] = ["--resolution", "640x480"]
    else:
        cmd[1:1] = ["--headless"]
    try:
        done = subprocess.run(cmd, capture_output=True, text=True, timeout=300)
    except subprocess.TimeoutExpired:
        return "FAIL (timed out)"
    return done.stdout


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("pattern", nargs="?", default="",
                    help="only run mutations whose label contains this")
    ap.add_argument("--path", default=os.getcwd(),
                    help="the godot-project directory (default: cwd)")
    args = ap.parse_args(argv)
    here = os.path.abspath(args.path)

    if not os.path.isdir(os.path.join(here, "tests")):
        print(f"mutate: no tests/ under {here} — run from godot-project/")
        return 2

    chosen = [m for m in MUTATIONS if args.pattern.lower() in m[0].lower()]
    if not chosen:
        print(f"mutate: nothing matches {args.pattern!r}")
        return 2

    escapes = 0
    for label, rel, now, was, suites in chosen:
        path = os.path.join(here, rel)
        with open(path) as f:
            source = f.read()
        if now not in source:
            print(f"SKIP    {label:<52} (the code has moved on)")
            escapes += 1
            continue
        with open(path, "w") as f:
            f.write(source.replace(now, was, 1))
        try:
            caught = [s for s in suites if "FAIL" in run(s, here)]
        finally:
            with open(path, "w") as f:
                f.write(source)
        if caught:
            print(f"caught  {label:<52} by {', '.join(caught)}")
        else:
            print(f"ESCAPED {label:<52} ({', '.join(suites)} said nothing)")
            escapes += 1

    print()
    print(f"{len(chosen)} mutations, {escapes} escaped")
    return escapes


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
