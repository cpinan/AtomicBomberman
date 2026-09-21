# Starting a game from the menu, through main.gd's real start path.
#
# tests/test_menu.gd proves the model produces the right configuration.
# tests/render_menu.gd proves the screen is legible. Neither proves that
# pressing START on it produces a running game, which is the whole point of the
# screen — so this drives main.gd itself: no OS arguments, so it opens the
# menu exactly as a bare launch does, then chooses items and starts.
#
# It runs headless. The view draws nothing worth looking at without a GPU, but
# every decision — which slots are seated, which keyset drives which slot, what
# the match target is, which settings reached the simulation — happens in code
# that does not care.
extends SceneTree

const T_ := preload("res://tests/t.gd")
const Const_ := preload("res://scripts/core/const.gd")
const Types_ := preload("res://scripts/core/types.gd")
const Values_ := preload("res://scripts/core/values.gd")
const Menu_ := preload("res://scripts/app/menu.gd")
const Main := preload("res://scripts/app/main.gd")


func _init() -> void:
	var t := T_.new("start")
	await _test_opens_on_the_menu(t)
	await _test_start_makes_a_game(t)
	await _test_slots_become_seats(t)
	await _test_settings_reach_the_sim(t)
	await _test_refusal_does_not_start(t)
	await _test_escape_comes_back(t)
	await _test_options_survive_a_match(t)
	quit(t.finish())


func _test_opens_on_the_menu(t: T_) -> void:
	var main := await _boot()
	t.eq(main.mode, Main.Mode.MENU, "a bare launch opens the menu")
	t.ok(main.menu != null, "and builds one")
	t.ok(main.sim == null, "with no simulation running")
	t.ok(main.the_match == null, "and no match")
	# The scheme list comes from the pack, so a real checkout offers all 67.
	if main.pack.loaded:
		t.eq(main.menu.scheme_names.size(),
			main.pack.scheme_names().size() + 1,
			"the menu offers every scheme in the pack, plus the built-in grid")
	main.free()


func _test_start_makes_a_game(t: T_) -> void:
	var main := await _boot()
	# The built-in grid, so this does not depend on the pack.
	main.menu.scheme_index = main.menu.scheme_names.size() - 1
	main.menu.level = 4
	main.menu.wins = 3
	main.menu.cursor = Menu_.Item.START
	t.eq(main.menu.activate(), Menu_.Action.START, "START was chosen")
	main._start_from_menu()
	await process_frame

	t.eq(main.mode, Main.Mode.LOCAL, "a local game is running")
	t.ok(main.sim != null, "with a simulation")
	t.ok(main.the_match != null, "and a match")
	t.eq(main.the_match.wins_to_win, 3, "to the target the menu set")
	t.eq(main.sim.level, 4, "on the level the menu chose")
	t.eq(main.the_match.level, 4, "which the match agrees about")
	t.ok(main.menu == null, "the menu is gone")
	t.ok(main.menu_view == null, "and so is its view")

	# It really runs.
	var before: int = main.sim.tick_count
	for _i in 5:
		main._step()
	t.eq(main.sim.tick_count, before + 5, "and the simulation ticks")
	main.free()


func _test_slots_become_seats(t: T_) -> void:
	var main := await _boot()
	var m: Menu_ = main.menu
	m.scheme_index = m.scheme_names.size() - 1
	# A layout the old "N humans then M bots" pair could not express: keyboard
	# players on slots 4 and 7, AI on 0 and 9, everything else off.
	#
	# 4 and 7 rather than the first two free slots because the built-in grid
	# starts slot 3 in the right-hand column, against the wall, where pressing
	# right moves nobody — which the first version of this test read as a
	# broken keyset mapping.
	for i in m.slots.size():
		m.slots[i] = Menu_.Slot.OFF
	m.slots[4] = Menu_.Slot.KEY
	m.slots[7] = Menu_.Slot.KEY
	m.slots[0] = Menu_.Slot.AI
	m.slots[9] = Menu_.Slot.AI
	m.cursor = Menu_.Item.START
	m.activate()
	main._start_from_menu()
	await process_frame

	t.eq(main.sim.players.size(), 4, "four seats")
	var seated := []
	for p in main.sim.players:
		seated.append(p.slot)
	seated.sort()
	t.eq(seated, [0, 4, 7, 9], "on exactly the slots the menu named")
	t.ok(main.sim.is_bot(0), "slot 0 is an AI")
	t.ok(main.sim.is_bot(9), "slot 9 is an AI")
	t.ok(not main.sim.is_bot(4), "slot 4 is not")
	t.ok(not main.sim.is_bot(7), "nor is slot 7")

	# Keyset 0 drives slot 3, not slot 0 — the thing a pair of counts cannot
	# say and the reason the slot model exists.
	t.eq(main._key_slots, [4, 7] as Array[int],
		"keyset 0 drives slot 4 and keyset 1 slot 7")
	# Driven through a real key event rather than sim.set_input(), because
	# _step() sets every keyboard slot's input from the keysets on every tick
	# and would overwrite anything set behind its back. Pressing the key is
	# also the only version of this that tests the mapping at all.
	var was_4: int = main.sim.player_by_slot(4).x
	var was_7: int = main.sim.player_by_slot(7).x
	main.keys.handle(_press(KEY_RIGHT))
	for _i in 6:
		main._step()
	t.ok(main.sim.player_by_slot(4).x > was_4,
		"keyset 0's right arrow moves SLOT 4")
	t.eq(main.sim.player_by_slot(7).x, was_7,
		"and leaves slot 7 where it was")

	# And the second keyset drives the other one. G, not D: INPUT.BM's table
	# gives keyset 1 "R,D,F,G" — an inverted T with R up, D left, F down and G
	# right — where the port had invented WASD.
	main.keys.handle(_release(KEY_RIGHT))
	main.keys.handle(_press(KEY_G))
	for _i in 6:
		main._step()
	t.ok(main.sim.player_by_slot(7).x > was_7,
		"keyset 1's G moves SLOT 7")
	main.keys.handle(_release(KEY_D))
	main.free()


func _test_settings_reach_the_sim(t: T_) -> void:
	var main := await _boot()
	var m: Menu_ = main.menu
	m.scheme_index = m.scheme_names.size() - 1
	m.enclose_depth = 3
	m.conveyor_index = 2
	m.stomped_detonate = false
	m.diseases_destroyable = false
	m.team_play = true
	m.play_time_index = 0            # 1:00
	m.cursor = Menu_.Item.START
	m.activate()
	main._start_from_menu()
	# Deliberately NOT awaiting a frame here: _process ticks the simulation,
	# and one tick is enough to move the clock off the value being asserted.
	t.eq(main.sim.enclose_depth, 3, "the enclosement depth reached the sim")
	t.eq(main.sim.conveyor_speed_index, 2, "and the conveyor speed")
	t.eq(main.sim.stomped_detonate, false, "and the stomped-bomb rule")
	t.eq(main.sim.diseases_destroyable, false, "and the disease rule")
	t.ok(main.sim.team_play, "and team play")
	t.eq(main.sim.time_left, 60 * Const_.TICK_HZ, "and the one-minute clock")

	# Depth 3 is "All the way!", so the Hurry wall covers the whole field —
	# which is the depth fpc_atomic always uses and the original does not.
	t.eq(main.sim.hurry_path().size(), Const_.FIELD_W * Const_.FIELD_H,
		"and depth 3 really closes the whole field")

	# The settings survive into the NEXT round, which is where a setting
	# applied once and then forgotten would show up.
	main.the_match.next_round()
	main._start_local_round()
	t.eq(main.sim.enclose_depth, 3, "and they survive a new round")
	t.eq(main.sim.conveyor_speed_index, 2, "all of them")
	t.eq(main.sim.time_left, 60 * Const_.TICK_HZ, "including the clock")
	main.free()


func _test_refusal_does_not_start(t: T_) -> void:
	var main := await _boot()
	var m: Menu_ = main.menu
	for i in m.slots.size():
		m.slots[i] = Menu_.Slot.OFF
	m.cursor = Menu_.Item.START
	m.activate()
	main._start_from_menu()
	await process_frame

	t.eq(main.mode, Main.Mode.MENU, "a refused start stays on the menu")
	t.ok(main.sim == null, "with no simulation")
	t.ok(not main.menu.refusal.is_empty(),
		"and a reason on screen: %s" % main.menu.refusal)
	main.free()


func _test_escape_comes_back(t: T_) -> void:
	var main := await _boot()
	main.menu.scheme_index = main.menu.scheme_names.size() - 1
	main.menu.cursor = Menu_.Item.START
	main.menu.activate()
	main._start_from_menu()
	await process_frame
	t.eq(main.mode, Main.Mode.LOCAL, "a game is running")

	# Escape goes back to the menu rather than out of the program — a game
	# that quits on a mistyped key loses the match.
	main._open_menu()
	await process_frame
	t.eq(main.mode, Main.Mode.MENU, "and Escape returns to the menu")
	t.ok(main.sim == null, "the game is torn down")
	t.ok(main.menu != null, "and a fresh menu is up")

	# And it can start again, which is what "play again" means.
	main.menu.scheme_index = main.menu.scheme_names.size() - 1
	main.menu.cursor = Menu_.Item.START
	main.menu.activate()
	main._start_from_menu()
	await process_frame
	t.eq(main.mode, Main.Mode.LOCAL, "and start another game")
	main.free()


## A live playtest report: "options are not saved, the selection is always
## lost" — a fresh Menu_ was being built on every return to the menu, which
## reset every option to its VALUELST default. Menu_.apply_options_from()
## fixed it; this proves it through the real `_open_menu()` path a player
## actually takes (start a match, come back), not just by calling the model
## method directly.
func _test_options_survive_a_match(t: T_) -> void:
	var main := await _boot()
	var picked_scheme: int = main.menu.scheme_names.size() - 1
	main.menu.scheme_index = picked_scheme
	main.menu.wins = 7
	main.menu.win_by_kills = true
	main.menu.team_play = true
	main.menu.random_start = not main.menu.random_start
	main.menu.play_time_index = 0
	main.menu.no_music = true
	main.menu.cursor = Menu_.Item.START
	main.menu.activate()
	main._start_from_menu()
	await process_frame
	t.eq(main.mode, Main.Mode.LOCAL, "a game is running")

	main._open_menu()
	await process_frame
	t.eq(main.mode, Main.Mode.MENU, "back at the menu")
	t.eq(main.menu.scheme_index, picked_scheme,
		"[invariant] scheme choice survives a played match")
	t.eq(main.menu.wins, 7, "[invariant] win count survives")
	t.ok(main.menu.win_by_kills, "[invariant] win-by-kills survives")
	t.ok(main.menu.team_play, "[invariant] team play survives")
	t.eq(main.menu.play_time_index, 0, "[invariant] play time survives")
	t.ok(main.menu.no_music, "[invariant] the music toggle survives")
	main.free()


static func _press(code: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = code
	e.pressed = true
	return e


static func _release(code: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = code
	e.pressed = false
	return e


## main.gd with no arguments, in the tree, past _ready.
func _boot() -> Node2D:
	var main: Node2D = Main.new()
	root.add_child(main)
	await process_frame
	return main
