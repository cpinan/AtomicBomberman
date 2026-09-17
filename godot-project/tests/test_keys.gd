# Key rebinding and the keyboard-definitions screen — MESSAGES.TXT 1100-1140.
#
# The disc specifies this screen completely and the port had none of it: 1100
# names it, 1105 is the prompt, 1110 is a row, 1120-1125 are the six actions in
# their own order, 1130 restores the defaults and 1131 is what it then says.
#
# What is NOT on the disc is what to do with a key that is already in use. The
# port refuses it, which is a decision and is asserted here as one.
extends SceneTree

const T_ := preload("res://tests/t.gd")
const Messages_ := preload("res://scripts/core/messages.gd")
const Keysets_ := preload("res://scripts/app/keysets.gd")
const Menu_ := preload("res://scripts/app/menu.gd")


func _init() -> void:
	var t := T_.new("keys")
	_test_the_disc_names_them(t)
	_test_defaults(t)
	_test_binding(t)
	_test_duplicates_are_refused(t)
	_test_persistence(t)
	_test_the_screen(t)
	_test_input_still_works(t)
	Keysets_.reset_to_defaults()
	quit(t.finish())


func _test_the_disc_names_them(t: T_) -> void:
	t.eq(Keysets_.ACTIONS.size(), 6, "six actions per player")
	t.eq(Messages_.KEY_NAMES.size(), 6, "and six names for them")
	t.eq(Messages_.KEY_NAMES[0], "Move Up", "1120")
	t.eq(Messages_.KEY_NAMES[1], "Move Right", "1121")
	t.eq(Messages_.KEY_NAMES[3], "Move Left", "1123")
	t.eq(Messages_.KEY_NAMES[5], "Action 2", "1125")
	# The order of ACTIONS is the disc's, or every row is mislabelled. Naming
	# each pair rather than looping over ACTIONS: a loop that indexes both
	# sides by i is true whatever order ACTIONS is in, which is no assertion
	# at all — a scrambled ACTIONS passed it.
	t.eq(Keysets_.action_label("up"), "Move Up", "up is 1120")
	t.eq(Keysets_.action_label("right"), "Move Right", "right is 1121")
	t.eq(Keysets_.action_label("down"), "Move Down", "down is 1122")
	t.eq(Keysets_.action_label("left"), "Move Left", "left is 1123")
	t.eq(Keysets_.action_label("first"), "Action 1", "first is 1124")
	t.eq(Keysets_.action_label("second"), "Action 2", "second is 1125")
	t.eq(Messages_.KEY_DEFINITIONS, "Keyboard definitions", "1100")
	t.eq(Messages_.RESTORE_DEFAULT_KEYS, "Return to default keys", "1130")
	t.eq(Messages_.DEFAULT_KEYS_RESTORED, "Default key controls restored",
		"1131")


# INPUT.BM — the help text for the input-selection screen — states the two
# default layouts as a table, and MANUAL.BM names the same keys from the
# player's side ("DROP BOMB: (joystick button 1, spacebar, 'S')"):
#
#                 Movement       Action1      Action2
#     KEY 0:      Cursor Keys    Space        Enter
#     KEY 1:      R,D,F,G         S            A
#
# The port had Return and Backspace for keyset 0 and fpc_atomic's WASD for
# keyset 1. Space dropped no bomb, which is the first thing anybody presses.
func _test_defaults(t: T_) -> void:
	Keysets_.reset_to_defaults()
	t.eq(int(Keysets_.MAPS[0]["up"]), KEY_UP, "keyset 1 walks on the arrows")
	t.eq(int(Keysets_.MAPS[0]["down"]), KEY_DOWN, "all four of them")
	t.eq(int(Keysets_.MAPS[0]["left"]), KEY_LEFT, "left")
	t.eq(int(Keysets_.MAPS[0]["right"]), KEY_RIGHT, "and right")
	t.eq(int(Keysets_.MAPS[0]["first"]), KEY_SPACE,
		"and drops its bombs on Space, which is INPUT.BM's Action1")
	t.eq(int(Keysets_.MAPS[0]["second"]), KEY_ENTER,
		"with Enter as the action button, which is its Action2")
	t.eq(int(Keysets_.MAPS[1]["up"]), KEY_R, "keyset 2 walks on R,")
	t.eq(int(Keysets_.MAPS[1]["left"]), KEY_D, "D,")
	t.eq(int(Keysets_.MAPS[1]["down"]), KEY_F, "F")
	t.eq(int(Keysets_.MAPS[1]["right"]), KEY_G, "and G")
	t.eq(int(Keysets_.MAPS[1]["first"]), KEY_S, "and bombs on S")
	t.eq(int(Keysets_.MAPS[1]["second"]), KEY_A, "with A for its action")
	t.eq(Keysets_.key_label(KEY_UP), "Up", "a key's name is the one on the key")


func _test_binding(t: T_) -> void:
	Keysets_.reset_to_defaults()
	t.eq(Keysets_.bind_key(0, "up", KEY_I), "", "a free key binds")
	t.eq(int(Keysets_.MAPS[0]["up"]), KEY_I, "and takes effect")
	t.eq(int(Keysets_.MAPS[0]["down"]), KEY_DOWN, "leaving the others alone")

	t.eq(Keysets_.bind_key(0, "up", KEY_I), "",
		"rebinding a key to what it already is succeeds and changes nothing")
	t.eq(int(Keysets_.MAPS[0]["up"]), KEY_I, "still bound")

	t.ok(not Keysets_.bind_key(0, "up", KEY_ESCAPE).is_empty(),
		"Escape cannot be bound — it is how the screen is left")
	t.eq(int(Keysets_.MAPS[0]["up"]), KEY_I, "and the old binding survives")
	t.ok(not Keysets_.bind_key(9, "up", KEY_J).is_empty(),
		"there is no keyset 9")
	t.ok(not Keysets_.bind_key(0, "jump", KEY_J).is_empty(),
		"and no jump action")

	Keysets_.reset_to_defaults()
	t.eq(int(Keysets_.MAPS[0]["up"]), KEY_UP, "1130 puts them all back")


func _test_duplicates_are_refused(t: T_) -> void:
	Keysets_.reset_to_defaults()
	# Within one keyset.
	var why := Keysets_.bind_key(0, "up", KEY_DOWN)
	t.ok(not why.is_empty(), "a key already used in the same keyset is"
		+ " refused: %s" % why)
	t.eq(int(Keysets_.MAPS[0]["up"]), KEY_UP, "and nothing moved")
	t.eq(int(Keysets_.MAPS[0]["down"]), KEY_DOWN, "on either side")

	# And across the two, which is the case that would let one press drive two
	# players.
	why = Keysets_.bind_key(0, "up", KEY_R)
	t.ok(not why.is_empty(), "a key used by the OTHER player is refused too")
	t.eq(int(Keysets_.MAPS[1]["up"]), KEY_R, "player two keeps it")
	Keysets_.reset_to_defaults()


func _test_persistence(t: T_) -> void:
	var path := "user://test_keys.cfg"
	Keysets_.reset_to_defaults()
	Keysets_.bind_key(0, "second", KEY_M)
	t.ok(Keysets_.save_keys(path), "the keys save")

	Keysets_.reset_to_defaults()
	t.eq(int(Keysets_.MAPS[0]["second"]), KEY_ENTER, "back to the default")
	t.ok(Keysets_.load_keys(path), "and load again")
	t.eq(int(Keysets_.MAPS[0]["second"]), KEY_M, "with the rebound key")
	t.eq(int(Keysets_.MAPS[1]["first"]), KEY_S, "and everything else intact")


	t.ok(not Keysets_.load_keys("user://test_keys_absent.cfg"),
		"a first run has no file, which is not an error")
	t.eq(int(Keysets_.MAPS[0]["second"]), KEY_M,
		"and a failed load leaves the keys alone")
	# A FILE FROM BEFORE THE DEFAULTS WERE CORRECTED IS THROWN AWAY. keys.cfg
	# is written whenever the keyboard screen is left and it stores all twelve
	# bindings, so without a version stamp the old Return-drops-a-bomb layout
	# came straight back over the disc's own on every machine that had ever run
	# the game — and Space, which is what INPUT.BM's table gives Action1, went
	# on being bound to nothing.
	var old_cfg := ConfigFile.new()
	old_cfg.set_value("keys", "version", Keysets_.CONFIG_VERSION - 1)
	for action in Keysets_.ACTIONS:
		old_cfg.set_value("keyset0", action, KEY_Z)
		old_cfg.set_value("keyset1", action, KEY_Z)
	var stale := "user://test_keys_old.cfg"
	old_cfg.save(stale)
	Keysets_.reset_to_defaults()
	t.ok(not Keysets_.load_keys(stale), "a file from an older version is refused")
	t.eq(int(Keysets_.MAPS[0]["first"]), KEY_SPACE,
		"and the disc's own layout stands")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(stale))

	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	Keysets_.reset_to_defaults()


func _test_the_screen(t: T_) -> void:
	Keysets_.reset_to_defaults()
	var m: Menu_ = Menu_.new()
	m.setup([])
	t.ok(not m.in_keys, "the options screen does not start on the key list")
	t.eq(m.label_of(Menu_.Item.KEY_DEFS), "Define keyboard layouts",
		"MESSAGES.TXT 265 names the item that opens it")

	m.cursor = Menu_.Item.KEY_DEFS
	m.activate()
	t.ok(m.in_keys, "Return opens the keyboard-definitions screen")
	t.eq(m.key_cursor, 0, "on the first row")
	t.eq(Menu_.KEY_ROWS, 13, "twelve bindings and the restore row")

	# 1110 with 1120-1125 inside it: "Key 1, Move Up".
	t.eq(m.key_row_label(0), "Key 1, Move Up", "row 0")
	t.eq(m.key_row_value(0), "Up", "shows what it is bound to")
	t.eq(m.key_row_label(6), "Key 2, Move Up", "the second keyset follows")
	t.eq(m.key_row_label(Menu_.KEY_RESTORE_ROW), "Return to default keys",
		"and 1130 is the last row")

	# Return on a row waits for a key, and 1105 says so.
	m.activate()
	t.eq(m.awaiting_key, 0, "row 0 is waiting")
	t.eq(m.key_row_value(0), "Press key for 'Move Up'", "which is 1105")
	# While waiting, the cursor must not move: the arrows are bindable keys.
	m.move(1)
	t.eq(m.key_cursor, 0, "a waiting screen does not navigate")
	t.eq(m.awaiting_key, 0, "and is still waiting")

	t.ok(m.take_key(KEY_I), "the next key is taken")
	t.eq(m.awaiting_key, -1, "the wait is over")
	t.eq(int(Keysets_.MAPS[0]["up"]), KEY_I, "and the key is bound")
	t.eq(m.key_notice, "", "with nothing to say about it")

	# A refused key says why, and leaves the binding alone.
	m.key_cursor = 1
	m.activate()
	m.take_key(KEY_I)
	t.ok(not m.key_notice.is_empty(), "a duplicate is explained: %s"
		% m.key_notice)
	t.eq(int(Keysets_.MAPS[0]["right"]), KEY_RIGHT, "and refused")

	# Escape pressed AT the prompt cancels the binding rather than becoming it.
	m.key_cursor = 3
	m.activate()
	t.eq(m.awaiting_key, 3, "row 3 is waiting")
	t.ok(m.take_key(KEY_ESCAPE), "Escape is consumed by the prompt")
	t.eq(m.awaiting_key, -1, "which ends the wait")
	t.eq(m.key_notice, "", "silently — a cancel is not a refusal")
	t.eq(int(Keysets_.MAPS[0]["left"]), KEY_LEFT, "and binds nothing")

	# Escape with nothing waiting cancels a wait rather than leaving the screen.
	m.key_cursor = 2
	m.activate()
	t.eq(m.awaiting_key, 2, "waiting again")
	t.ok(m.leave_keys(), "Escape is consumed")
	t.eq(m.awaiting_key, -1, "the wait is cancelled")
	t.ok(m.in_keys, "but the screen is still open")
	# Leaving writes the file, once, rather than on every keypress.
	var saved := "user://test_keys_leave.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(saved))
	t.ok(m.leave_keys(saved), "a second Escape leaves it")
	t.ok(not m.in_keys, "and the options list is back")
	t.ok(FileAccess.file_exists(saved), "and the keys were saved on the way")
	var check := ConfigFile.new()
	check.load(saved)
	t.eq(int(check.get_value("keyset0", "up", -1)), KEY_I,
		"with the rebinding in it")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(saved))
	t.ok(not m.leave_keys(saved), "Escape from the options list is not ours")

	# 1130 restores everything and 1131 says so.
	m.cursor = Menu_.Item.KEY_DEFS
	m.activate()
	m.key_cursor = Menu_.KEY_RESTORE_ROW
	m.activate()
	t.eq(m.key_notice, Messages_.DEFAULT_KEYS_RESTORED, "1131 is shown")
	t.eq(int(Keysets_.MAPS[0]["up"]), KEY_UP, "and the arrows are back")
	t.eq(m.awaiting_key, -1, "restoring does not wait for a key")


# A rebound key has to actually drive the player, which is the whole point.
func _test_input_still_works(t: T_) -> void:
	Keysets_.reset_to_defaults()
	var ks: Keysets_ = Keysets_.new()
	var Types_ := preload("res://scripts/core/types.gd")

	var press := InputEventKey.new()
	press.keycode = KEY_UP
	press.pressed = true
	ks.handle(press)
	t.eq(ks.move_state(0), Types_.MoveState.UP, "the default key walks")

	var release := InputEventKey.new()
	release.keycode = KEY_UP
	release.pressed = false
	ks.handle(release)
	t.eq(ks.move_state(0), Types_.MoveState.STILL, "and stops")

	t.eq(Keysets_.bind_key(0, "up", KEY_I), "", "rebind up to I")
	var rebound := InputEventKey.new()
	rebound.keycode = KEY_I
	rebound.pressed = true
	ks.handle(rebound)
	t.eq(ks.move_state(0), Types_.MoveState.UP, "the new key walks")

	var old := InputEventKey.new()
	old.keycode = KEY_UP
	old.pressed = true
	ks.handle(old)
	t.eq(ks.move_state(0), Types_.MoveState.UP,
		"and the old one does nothing — still walking on I, not on Up")
	Keysets_.reset_to_defaults()
