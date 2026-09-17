# End-to-end: the keyboard, through the real scene, to a bomb on the field.
#
# Every other suite drives a model directly. This one presses keys and reads
# what the whole app did with them — InputEvent, main._input, Keysets, Sim,
# Match. The last two rounds of defects lived almost entirely in that gap: the
# models were right and the wiring was not, and no suite started the app.
extends SceneTree

const T_ := preload("res://tests/t.gd")
const Types_ := preload("res://scripts/core/types.gd")
const Screens_ := preload("res://scripts/app/screens.gd")
const Menu_ := preload("res://scripts/app/menu.gd")
const ScreenView := preload("res://scripts/render/screen_view.gd")
const Keysets_ := preload("res://scripts/app/keysets.gd")

var _main: Node = null


func _init() -> void:
	var t := T_.new("play")
	await _boot()
	if _main == null:
		t.ok(false, "the scene did not load")
		quit(t.finish())
		return
	await _test_options_reaches_its_last_three_rows(t)
	await _test_the_manual_scrolls(t)
	await _test_the_setup_keys_reach_the_menu(t)
	await _test_menu_to_game(t)
	await _test_bomb(t)
	await _test_who_is_playing(t)
	_test_death_ends_the_round_and_scores_it(t)
	quit(t.finish())


func _boot() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	_main = scene.instantiate()
	root.add_child(_main)
	await process_frame
	await process_frame


func _press(code: Key) -> void:
	var down := InputEventKey.new()
	down.keycode = code
	down.pressed = true
	Input.parse_input_event(down)
	await process_frame
	var up := InputEventKey.new()
	up.keycode = code
	up.pressed = false
	Input.parse_input_event(up)
	await process_frame


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _to_main_menu() -> void:
	while _main.screens.screen != Screens_.Screen.MAIN_MENU:
		await _press(KEY_ESCAPE)
	_main.screens.cursor = Screens_.Menu.START_GAME


# THE DEFECT: "in options cannot select START, HOST A GAME, QUIT — they are not
# preselected like others". They were eleven presses below the last row anybody
# could see, because the cursor was walking the ten player slots on its way
# past a row this screen does not draw.
func _test_options_reaches_its_last_three_rows(t: T_) -> void:
	await _press(KEY_SPACE)          # off the title
	await _to_main_menu()
	_main.screens.cursor = Screens_.Menu.OPTIONS
	await _press(KEY_ENTER)
	if not t.eq(_main.screens.screen, Screens_.Screen.OPTIONS,
			"the Options item opens the options screen"):
		return
	t.ok(not _main.menu.in_slots, "which is not the slot screen")

	var reached := {}
	var homeless := 0
	for i in 40:
		reached[_main.menu.selected()] = true
		if _main.menu.in_slots:
			homeless += 1
		await _press(KEY_DOWN)
	t.eq(homeless, 0,
		"the cursor is never on a row this screen does not draw")
	for item in [Menu_.Item.START, Menu_.Item.HOST, Menu_.Item.QUIT]:
		t.ok(reached.has(item), "%s is reachable with the down key"
			% _main.menu.label_of(item))
	t.ok(not reached.has(Menu_.Item.SLOTS),
		"and the slots, which have a screen of their own, are not on it")


# "No scroll on About Bomberman and online manual" was two defects: the text
# was truncated to 24 lines before it ever reached the screen, and the scroll
# counter was not clamped, so going past the end cost as many presses to undo.
func _test_the_manual_scrolls(t: T_) -> void:
	await _to_main_menu()
	_main.screens.cursor = Screens_.Menu.MANUAL
	await _press(KEY_ENTER)
	if not t.eq(_main.screens.screen, Screens_.Screen.MANUAL,
			"the Online Manual opens"):
		return
	var lines: int = _main.menu_view.page_line_count()
	var rows := ScreenView.page_rows()
	t.ok(lines > rows * 4,
		"MANUAL.BM is %d lines, which is more than the %d that fit"
			% [lines, rows])
	t.eq(_main.screens.text_scroll, 0, "and it opens at the top")

	await _press(KEY_DOWN)
	t.eq(_main.screens.text_scroll, 1, "down scrolls it")
	await _press(KEY_PAGEDOWN)
	t.eq(_main.screens.text_scroll, 1 + rows, "page down moves a page")

	for i in 30:
		await _press(KEY_PAGEDOWN)
	t.eq(_main.screens.text_scroll, lines - rows,
		"and it stops at the last page rather than counting past it")
	await _press(KEY_UP)
	t.eq(_main.screens.text_scroll, lines - rows - 1,
		"so ONE press of up moves the page back")
	await _press(KEY_ESCAPE)


func _test_menu_to_game(t: T_) -> void:
	await _to_main_menu()
	# "Start a Game" is the first item, so Return opens the setup screen.
	await _press(KEY_ENTER)
	t.eq(_main.screens.screen, Screens_.Screen.SETUP,
		"Return on the first item opens 'Who is playing'")
	await _press(KEY_ENTER)
	await _frames(4)
	t.eq(_main.mode, _main.Mode.LOCAL, "Return on the setup screen starts")
	t.ok(_main.sim != null, "and there is a simulation")


func _test_bomb(t: T_) -> void:
	if _main.sim == null:
		return
	var slot: int = _main._key_slots[0] if not _main._key_slots.is_empty() else -1
	t.eq(slot, 0, "keyset 1 drives slot 1")
	var before: int = _main.sim.bombs.size()
	# SPACE. Not because it is convenient — because INPUT.BM's own table says
	# "KEY 0: Cursor Keys / Space / Enter" and MANUAL.BM names the spacebar
	# first for Drop Bomb. It was bound to nothing at all.
	t.eq(int(Keysets_.MAPS[0]["first"]), KEY_SPACE,
		"keyset 1 drops its bombs on the key the disc says it does")
	await _press(KEY_SPACE)
	await _frames(8)
	t.ok(_main.sim.bombs.size() > before,
		"pressing Space drops a bomb (%d -> %d)"
			% [before, _main.sim.bombs.size()])


func _test_who_is_playing(t: T_) -> void:
	if _main.sim == null:
		return
	t.ok(not _main._key_slots.is_empty(),
		"a started game has somebody at the keyboard")
	t.ok(not _main.sim.bot_slots.has(_main._key_slots[0]),
		"and that slot is not also driven by the AI")


# "Score not updated after dead". The round has to END when the human dies,
# the match has to RECORD it, and the number the status band draws has to be
# the one that changed. Stepped rather than waited out: _step() is the app's
# own tick, so this is the same path a frame takes with none of the clock.
func _test_death_ends_the_round_and_scores_it(t: T_) -> void:
	if _main.sim == null or _main.the_match == null:
		return
	var sim = _main.sim
	var human: int = _main._key_slots[0]
	var before: int = _main.the_match.round_index
	# Everyone but one bot, so the round has a winner the moment the human dies.
	var survivor := -1
	for p in sim.players:
		if p.slot == human:
			continue
		if survivor < 0:
			survivor = p.slot
			continue
		sim.kill(p, -1)
	t.ok(survivor >= 0, "there is somebody left to win it")
	var was_wins: int = _main.the_match.wins_of(survivor)

	sim.kill(sim.player_by_slot(human), survivor)
	# Long enough for the round to be judged, recorded, and the intermission to
	# run — but the sim is replaced when the next round starts, so stop there.
	for i in 200:
		if _main.sim == null or _main.the_match.round_index != before:
			break
		_main._step()
	t.ok(_main.the_match.wins_of(survivor) > was_wins,
		"the winner's score went up (%d -> %d)"
			% [was_wins, _main.the_match.wins_of(survivor)])
	t.ok(_main.view == null or _main.view.the_match == _main.the_match,
		"and the status band is reading the same match it was recorded in")


# THE SETUP SCREEN'S OWN KEYS, through the app rather than the model. Both are
# named by the disc's own help files and neither could be pressed: Ctrl-A was
# written as a case of `match key.keycode`, and `KEY_LEFT, KEY_A` is an earlier
# arm of that same match — A is the menu's alias for "left" — so the branch was
# dead code that read perfectly well.
func _test_the_setup_keys_reach_the_menu(t: T_) -> void:
	await _to_main_menu()
	await _press(KEY_ENTER)
	if not t.eq(_main.screens.screen, Screens_.Screen.SETUP,
			"the setup screen is up"):
		return
	t.ok(_main.menu.in_slots, "with the cursor in the slots")

	# T, with team play off: INPUT.BM says it needs to be on.
	_main.menu.team_play = false
	_main.menu.slot_cursor = 0
	var was: int = _main.menu.team_of(0)
	await _press(KEY_T)
	t.eq(_main.menu.team_of(0), was, "T does nothing while team play is off")
	t.ok(not _main.menu.refusal.is_empty(), "and says why: %s"
		% _main.menu.refusal)

	_main.menu.team_play = true
	await _press(KEY_T)
	t.eq(_main.menu.team_of(0), 1 - was, "and moves the team when it is on")

	# Ctrl-A, which has to survive being an arm of the same match as "left".
	_main.menu.slots[0] = Menu_.Slot.KEY
	_main.menu.slots[1] = Menu_.Slot.KEY
	var down := InputEventKey.new()
	down.keycode = KEY_A
	down.ctrl_pressed = true
	down.pressed = true
	Input.parse_input_event(down)
	await process_frame
	var up := InputEventKey.new()
	up.keycode = KEY_A
	up.ctrl_pressed = true
	up.pressed = false
	Input.parse_input_event(up)
	await process_frame
	t.eq(_main.menu.slots[0], Menu_.Slot.AI, "Ctrl-A sets slot 1 to AI")
	t.eq(_main.menu.slots[1], Menu_.Slot.AI, "and slot 2")

	# And plain A still moves left, which is what it collided with.
	_main.menu.slot_cursor = 3
	var before: int = _main.menu.slots[3]
	await _press(KEY_A)
	t.ok(_main.menu.slots[3] != before,
		"and plain A still cycles the slot under the cursor")

	# Put the screen back the way it was found: this suite goes on to start a
	# game from it, and a board of ten AI is refused — correctly, since nobody
	# would be playing.
	_main.menu.setup(_main.pack.scheme_names() if _main.pack != null else [])
	_main.menu.team_play = false
	_main.menu.in_slots = true
	await _press(KEY_ESCAPE)
