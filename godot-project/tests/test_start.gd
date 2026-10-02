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
const Screens_ := preload("res://scripts/app/screens.gd")
const Server_ := preload("res://scripts/net/server.gd")


func _init() -> void:
	var t := T_.new("start")
	await _test_opens_on_the_menu(t)
	await _test_start_makes_a_game(t)
	await _test_slots_become_seats(t)
	await _test_settings_reach_the_sim(t)
	await _test_refusal_does_not_start(t)
	await _test_escape_comes_back(t)
	await _test_options_survive_a_match(t)
	await _test_host_lobby_then_start(t)
	await _test_a_local_match_ends_on_the_victory_screen(t)
	await _test_a_hosted_match_ends_back_in_the_lobby(t)
	await _test_a_dead_server_returns_to_the_menu(t)
	await _test_nobody_answering_is_said_on_the_menu(t)
	await _test_the_editor_in_a_network_game(t)
	_test_flags_before_the_separator(t)
	_test_hosting_lines(t)
	_test_an_address_is_joined_directly(t)
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


## Hosting from the menu now opens in a lobby (server.gd's State.WAITING)
## rather than starting the round the instant the host's own client
## connects — this drives the real path (menu -> _prepare_setup(true) ->
## _start_from_menu() -> Mode.HOST) end to end, through main.gd's actual
## _process()/_input() wiring, not by calling sim/server methods directly.
func _test_host_lobby_then_start(t: T_) -> void:
	var main := await _boot()
	main._prepare_setup(true)
	main.menu.cursor = Menu_.Item.START
	main.menu.activate()
	main._start_from_menu()
	await process_frame
	if not t.ok(main.mode == Main.Mode.HOST, "hosting begins"):
		main.free()
		return

	for _i in 200:
		await process_frame
		if main.client != null and main.client.in_lobby():
			break
	if not t.ok(main.client != null and main.client.in_lobby(),
			"the host's own client reaches the lobby instead of playing at once"):
		main.free()
		return
	t.ok(not main.client.playing(), "[invariant] not playing yet")
	t.ok(main.client.lobby_is_host, "and knows it's the host")
	t.ok(main.view != null and main.view.lobby_active,
		"the view was told to draw the lobby")
	var lines: PackedStringArray = main.view.lobby_hosting_lines
	t.ok(lines.size() >= 3, "the host's lobby says how others reach it")
	t.ok("\n".join(lines).contains("%d" % main.server.port),
		"including the port: %s" % " | ".join(lines))

	main.client.request_start()
	for _i in 200:
		await process_frame
		if main.client.playing():
			break
	t.ok(main.client.playing(), "request_start() begins the round")
	main.free()


## docs/IMPROVEMENTS.md A1 asked for the local path to be checked as well as
## the network one: a won local match must leave the field for the victory
## screen on its own, without anybody having to know about Escape.
func _test_a_local_match_ends_on_the_victory_screen(t: T_) -> void:
	var main := await _boot()
	main.menu.scheme_index = main.menu.scheme_names.size() - 1
	main.menu.wins = 1
	main.menu.cursor = Menu_.Item.START
	main.menu.activate()
	main._start_from_menu()
	await process_frame
	if not t.ok(main.mode == Main.Mode.LOCAL, "a local game is running"):
		main.free()
		return
	var survivor: int = -1
	for p in main.sim.players:
		if p.in_play and p.alive:
			if survivor < 0:
				survivor = p.slot
			else:
				main.sim.kill(p, survivor)
	t.ok(survivor >= 0, "somebody is left standing")
	for _i in 600:
		main._step()
		if main.mode == Main.Mode.MENU:
			break
	t.eq(main.mode, Main.Mode.MENU, "[invariant] a won local match ends")
	t.ok(main.screens != null
		and main.screens.screen == Screens_.Screen.VICTORY,
		"on the victory screen")
	main.free()


## The same, hosted from the menu: the host's own window must come back to
## the lobby with the result on it, and be able to start the next match.
## Driven by real frames, so main.gd's own _process()/_poll_client() wiring
## is what moves it, not a test calling the pieces.
func _test_a_hosted_match_ends_back_in_the_lobby(t: T_) -> void:
	var main := await _boot()
	main._prepare_setup(true)
	main.menu.cursor = Menu_.Item.START
	main.menu.activate()
	main._start_from_menu()
	await process_frame
	if not t.ok(main.mode == Main.Mode.HOST, "hosting begins"):
		main.free()
		return
	main.server.the_match.wins_to_win = 1
	# Somebody to beat. Recorded now, seated when the round is built.
	main.server.add_bots(1)
	var in_lobby := func(): return main.client != null and main.client.in_lobby()
	if not await _frames_until(in_lobby, 10.0):
		t.ok(false, "the host reaches the lobby")
		main.free()
		return
	main.client.request_start()
	var seated := func(): return main.client.playing() and main.server.ready_count() == 1
	if not t.ok(await _frames_until(seated, 10.0), "the round begins"):
		main.free()
		return
	for p in main.server.sim.players:
		if p.in_play and p.alive and p.slot != main.client.slot:
			main.server.sim.kill(p, main.client.slot)
	t.ok(await _frames_until(in_lobby, 20.0),
		"[invariant] the won match comes back to the lobby")
	t.eq(main.mode, Main.Mode.HOST, "still hosting, not quit or in the menu")
	t.ok(main.view != null and main.view.sim == null
		and main.view.lobby_active, "the view draws the lobby, not the old field")
	t.ok(main.view != null and main.view.lobby_notice.ends_with("wins the match"),
		"and says who won: '%s'" % (main.view.lobby_notice if main.view else ""))
	main.client.request_start()
	var shown := func(): return main.client.playing() and main.view.sim == main.client.sim
	t.ok(await _frames_until(shown, 10.0), "the host starts another match from it")
	main.free()


## docs/IMPROVEMENTS.md A2b: when the server went away, a joined client's
## whole application EXITED, with the reason on a console nobody was reading.
func _test_a_dead_server_returns_to_the_menu(t: T_) -> void:
	var port := 47671
	var server: Server_ = Server_.new()
	if not t.ok(server.listen(port, _grid_scheme_text(), 0, 5),
			"a server for the joiner to lose"):
		return
	var main := await _boot()
	main._teardown()
	main._start_from_args({"join": "ws://127.0.0.1:%d" % port, "name": "joiner"})
	var joined := func():
		server.poll(16.0)
		return main.client != null and main.client.playing()
	if not t.ok(await _frames_until(joined, 10.0), "the client joins"):
		server.close()
		main.free()
		return
	server.close()
	var back := func(): return main.mode == Main.Mode.MENU
	t.ok(await _frames_until(back, 10.0),
		"[invariant] losing the server goes back to the menu, not out of the game")
	t.ok(main.screens != null and main.screens.screen == Screens_.Screen.MAIN_MENU,
		"the main menu")
	t.eq(main.screens.refusal if main.screens != null else "",
		"The host ended the game", "and says why on screen")
	t.eq(main.client, null, "the dead connection is gone")
	main.free()


## A join to an address where nothing listens sat in CONNECTING forever.
func _test_nobody_answering_is_said_on_the_menu(t: T_) -> void:
	var main := await _boot()
	main._teardown()
	main._start_from_args({"join": "ws://127.0.0.1:47672", "name": "joiner"})
	var back := func(): return main.mode == Main.Mode.MENU
	t.ok(await _frames_until(back, 15.0),
		"[invariant] a join nobody answers comes back to the menu")
	var why: String = main.screens.refusal if main.screens != null else ""
	t.ok(why.begins_with("Could not join: nothing answered at ws://127.0.0.1:47672"),
		"and says so: '%s'" % why)
	main.free()


## docs/IMPROVEMENTS.md A2 asks for every powerup to be checked with the T
## editor in a network game, and every editor function reached for main.gd's
## own `sim` — null in HOST and JOIN — so the first key pressed crashed. A host
## now edits its server, and the snapshot carries the change to every window.
## A2c: the editor's pause cannot stop a server, so it says so.
func _test_the_editor_in_a_network_game(t: T_) -> void:
	var main := await _boot()
	main._prepare_setup(true)
	main.menu.cursor = Menu_.Item.START
	main.menu.activate()
	main._start_from_menu()
	await process_frame
	if not t.ok(main.mode == Main.Mode.HOST, "hosting begins"):
		main.free()
		return
	var in_lobby := func(): return main.client != null and main.client.in_lobby()
	await _frames_until(in_lobby, 10.0)
	main.client.request_start()
	var seated := func(): return main.client.playing() and main.server.ready_count() == 1
	if not t.ok(await _frames_until(seated, 10.0), "the round begins"):
		main.free()
		return
	main.view.editor_active = true
	var me: int = main.client.slot
	var p = main.server.sim.player_by_slot(me)
	main.view.editor_cursor = Vector2i(p.tile_x(), p.tile_y())
	main.view.editor_powerup = Types_.PowerUp.KICK
	main._editor_key(KEY_G)
	t.ok(main.server.sim.player_by_slot(me).can_kick,
		"[invariant] G gives the host's server player the kick")
	var arrived := func(): return main.client.sim.player_by_slot(me).can_kick
	t.ok(await _frames_until(arrived, 5.0), "and the snapshot carries it to the window")
	main._editor_key(KEY_X)
	t.ok(not main.server.sim.player_by_slot(me).can_kick, "X strips it again")
	main._editor_key(KEY_P)
	t.ok(not main._editor_paused, "P does not pause a network game")
	t.eq(main.view.editor_notice, "No pause in a network game", "and says so")
	main.mode = Main.Mode.JOIN
	main._editor_key(KEY_G)
	t.eq(main.view.editor_notice, "Only the host can edit a network game",
		"a joiner's edit is refused out loud, not crashed on")
	main.mode = Main.Mode.HOST
	main.free()


## docs/IMPROVEMENTS.md B4: `godot --path . --serve 47600` (no bare `--`)
## used to start a plain local game in silence. The flags are now found among
## Godot's own, with Godot's flags and their values left alone.
func _test_flags_before_the_separator(t: T_) -> void:
	var argv := PackedStringArray(["--path", ".", "--resolution", "640x480",
		"--serve", "47600", "--name", "alice", "--headless", "--debug-grid"])
	t.eq(Main.flags_from(argv, Main.GAME_FLAGS),
		{"serve": "47600", "name": "alice", "debug-grid": true},
		"the game's flags are found, Godot's and their values skipped")
	t.eq(Main.flags_from(PackedStringArray(["--join", "ws://h:1", "--teams"])),
		{"join": "ws://h:1", "teams": true},
		"after the separator, every flag is the game's")


func _test_hosting_lines(t: T_) -> void:
	var lines := Main.hosting_lines(47600, ["192.168.1.20"])
	t.ok(lines.has("On this network: ws://192.168.1.20:47600"),
		"the LAN address a guest types")
	t.ok(Main.hosting_lines(47600, []).has(
		"No network address found — only this machine can join"),
		"and an honest line when there is none")
	for ip in Main.lan_addresses():
		t.ok(not String(ip).begins_with("127.") and not String(ip).contains(":"),
			"%s is a private IPv4 address, not loopback or IPv6" % ip)


## docs/NETWORK_PLAN.md item 2: from the menu, without flags, a player could
## join only a game the LAN list happened to hear. The code field now takes
## the host's address too.
func _test_an_address_is_joined_directly(t: T_) -> void:
	t.eq(Main.address_url("192.168.1.20"), "ws://192.168.1.20:47600",
		"a bare IP joins on the menu's default port")
	t.eq(Main.address_url("HOST.EXAMPLE:47601"), "ws://host.example:47601",
		"a name and port, typed in the field's capitals")
	t.eq(Main.address_url("LOCALHOST"), "ws://localhost:47600", "localhost")
	t.eq(Main.address_url("AB3XZ"), "", "a room code is not an address")
	t.eq(Main.address_url("1.2.3.4:PORT"), "", "nor is a junk port")


## The built-in grid's text, for a test server that must not need the pack.
func _grid_scheme_text() -> String:
	var lines := PackedStringArray(["-V,2", "-N,Start fixture (10)", "-B,0"])
	for y in Const_.FIELD_H:
		lines.append("-R,%2d,%s" % [y, ".".repeat(Const_.FIELD_W)])
	for p in Const_.PLAYER_COUNT:
		lines.append("-S,%d,%d,%d,%d" % [p, 1 + p, 1 + (p % 8), p % 2])
	for i in Const_.POWERUP_COUNT:
		lines.append("-P,%2d, 0,0, 0, 0,x" % i)
	return "\n".join(lines)


## Run real frames until `cond` holds or `seconds` of wall time pass.
func _frames_until(cond: Callable, seconds: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		await process_frame
		if cond.call():
			return true
	return false


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
