# Gamepads — MESSAGES.TXT 223's `JOY %u` slot type.
#
# The disc specifies the slot type and nothing else: the original's joystick
# handling was DINPUT and a Windows dialog, so which button bombs is this
# port's decision. What is NOT a decision is the direction rule — the
# simulation moves on one axis at a time, so a stick has to resolve a diagonal
# exactly the way the keyboard does, and that is most of what this asserts.
extends SceneTree

const T_ := preload("res://tests/t.gd")
const Types_ := preload("res://scripts/core/types.gd")
const Messages_ := preload("res://scripts/core/messages.gd")
const Pads_ := preload("res://scripts/app/pads.gd")
const Menu_ := preload("res://scripts/app/menu.gd")


func _init() -> void:
	var t := T_.new("pads")
	_test_dpad(t)
	_test_stick(t)
	_test_hysteresis(t)
	_test_diagonals(t)
	_test_buttons(t)
	_test_two_pads_are_independent(t)
	_test_the_slot_type(t)
	quit(t.finish())


func _test_dpad(t: T_) -> void:
	var p: Pads_ = Pads_.new()
	t.eq(p.move_state(0), Types_.MoveState.STILL, "an untouched pad is still")
	p.handle(_button(0, JOY_BUTTON_DPAD_RIGHT, true))
	t.eq(p.move_state(0), Types_.MoveState.RIGHT, "the D-pad walks")
	p.handle(_button(0, JOY_BUTTON_DPAD_RIGHT, false))
	t.eq(p.move_state(0), Types_.MoveState.STILL, "and stops")


func _test_stick(t: T_) -> void:
	var p: Pads_ = Pads_.new()
	p.handle(_motion(0, JOY_AXIS_LEFT_X, 1.0))
	t.eq(p.move_state(0), Types_.MoveState.RIGHT, "the stick walks right")
	p.handle(_motion(0, JOY_AXIS_LEFT_X, 0.0))
	t.eq(p.move_state(0), Types_.MoveState.STILL, "and centring stops")

	p.handle(_motion(0, JOY_AXIS_LEFT_Y, -1.0))
	t.eq(p.move_state(0), Types_.MoveState.UP,
		"negative Y is up, which is the screen's sign and Godot's")
	p.handle(_motion(0, JOY_AXIS_LEFT_Y, 1.0))
	t.eq(p.move_state(0), Types_.MoveState.DOWN, "and positive is down")


# A stick resting near the threshold must not chatter: it takes more push to
# press than to release.
func _test_hysteresis(t: T_) -> void:
	t.ok(Pads_.PRESS > Pads_.RELEASE, "the two thresholds are apart")
	var p: Pads_ = Pads_.new()
	p.handle(_motion(0, JOY_AXIS_LEFT_X, 0.45))
	t.eq(p.move_state(0), Types_.MoveState.STILL,
		"a nudge under the press threshold does nothing")
	p.handle(_motion(0, JOY_AXIS_LEFT_X, 0.6))
	t.eq(p.move_state(0), Types_.MoveState.RIGHT, "over it, the pad walks")
	p.handle(_motion(0, JOY_AXIS_LEFT_X, 0.45))
	t.eq(p.move_state(0), Types_.MoveState.RIGHT,
		"and drifting back between the two keeps walking, rather than"
		+ " flickering once a frame")
	p.handle(_motion(0, JOY_AXIS_LEFT_X, 0.2))
	t.eq(p.move_state(0), Types_.MoveState.STILL, "below release, it stops")


# The simulation only ever moves on one axis, so a diagonal has to become one
# direction before it gets there — the most recent, which is the keyboard's own
# rule in scripts/app/keysets.gd.
func _test_diagonals(t: T_) -> void:
	var p: Pads_ = Pads_.new()
	p.handle(_motion(0, JOY_AXIS_LEFT_X, 1.0))
	p.handle(_motion(0, JOY_AXIS_LEFT_Y, 1.0))
	t.eq(p.move_state(0), Types_.MoveState.DOWN,
		"pushed diagonally, the direction pressed last wins")
	p.handle(_motion(0, JOY_AXIS_LEFT_X, 0.0))
	t.eq(p.move_state(0), Types_.MoveState.DOWN, "releasing the other holds")
	p.handle(_motion(0, JOY_AXIS_LEFT_X, 1.0))
	t.eq(p.move_state(0), Types_.MoveState.RIGHT, "and pressing again takes it")

	# Opposite ends of one axis cannot both be held.
	var q: Pads_ = Pads_.new()
	q.handle(_motion(0, JOY_AXIS_LEFT_X, -1.0))
	q.handle(_motion(0, JOY_AXIS_LEFT_X, 1.0))
	t.eq(q.held_count(0), 1, "one axis holds one direction")
	t.eq(q.move_state(0), Types_.MoveState.RIGHT, "the new one")


func _test_buttons(t: T_) -> void:
	var p: Pads_ = Pads_.new()
	t.eq(p.take_action(0), Types_.Action.NONE, "nothing pressed, nothing done")
	p.handle(_button(0, Pads_.BUTTON_FIRST, true))
	t.eq(p.take_action(0), Types_.Action.FIRST, "the bottom button bombs")
	t.eq(p.take_action(0), Types_.Action.NONE,
		"and one press is one bomb, however long it is held")
	p.handle(_button(0, Pads_.BUTTON_SECOND, true))
	t.eq(p.take_action(0), Types_.Action.SECOND, "the right button is action 2")

	# Releasing a button is not an action.
	p.handle(_button(0, Pads_.BUTTON_FIRST, false))
	t.eq(p.take_action(0), Types_.Action.NONE, "a release does nothing")

	# Focus loss drops everything, or a player keeps walking into a wall.
	p.handle(_motion(0, JOY_AXIS_LEFT_X, 1.0))
	p.handle(_button(0, Pads_.BUTTON_FIRST, true))
	p.release_all()
	t.eq(p.move_state(0), Types_.MoveState.STILL, "release_all stops walking")
	t.eq(p.take_action(0), Types_.Action.NONE, "and drops the pending action")


func _test_two_pads_are_independent(t: T_) -> void:
	var p: Pads_ = Pads_.new()
	p.handle(_motion(0, JOY_AXIS_LEFT_X, 1.0))
	p.handle(_motion(1, JOY_AXIS_LEFT_Y, -1.0))
	t.eq(p.move_state(0), Types_.MoveState.RIGHT, "pad 0 goes right")
	t.eq(p.move_state(1), Types_.MoveState.UP, "pad 1 goes up, at the same time")
	p.handle(_button(1, Pads_.BUTTON_FIRST, true))
	t.eq(p.take_action(0), Types_.Action.NONE, "pad 1's button is not pad 0's")
	t.eq(p.take_action(1), Types_.Action.FIRST, "it is pad 1's")


# The slot type is the disc's: MESSAGES.TXT 223, "JOY %u".
func _test_the_slot_type(t: T_) -> void:
	t.eq(Messages_.SLOT_JOY, "JOY %u", "223 is the slot's own word")
	var m: Menu_ = Menu_.new()
	m.setup([])
	m.in_slots = true
	m.slot_cursor = 0
	m.slots[0] = Menu_.Slot.KEY

	# With no pad plugged in, JOY is stepped over rather than offered: a slot
	# that cannot move is worse than one that is not there.
	m.pads_available = 0
	m.adjust(1)
	t.ok(m.slots[0] != Menu_.Slot.JOY, "no pad, no JOY")
	t.ok(m.slots[0] != Menu_.Slot.NET, "and NET is never offered here")

	m.slots[0] = Menu_.Slot.KEY
	m.pads_available = 2
	m.adjust(1)
	t.eq(m.slots[0], Menu_.Slot.JOY, "with a pad plugged in, KEY steps to JOY")
	t.eq(m.slot_text(0), "JOY 1", "and it reads as the disc's own JOY 1")
	m.slots[3] = Menu_.Slot.JOY
	t.eq(m.slot_text(3), "JOY 2", "the second joystick slot is JOY 2")
	t.eq(m.pad_slots(), [0, 3] as Array[int], "and both drive a pad")
	t.eq(m.pad_count(), 2, "two of them")

	# More JOY slots than pads is refused before the round rather than
	# discovered in it.
	m.pads_available = 1
	t.ok(not m.validate(), "two JOY slots and one pad is refused")
	t.ok(m.refusal.contains("joystick"), "and says so: %s" % m.refusal)
	m.pads_available = 2
	m.slots[1] = Menu_.Slot.AI
	t.ok(m.validate(), "with both pads plugged in it is startable")

	# What the menu hands main.gd has to include them, or the seats are empty.
	var cfg := m.config()
	t.eq(cfg["pad_slots"], [0, 3] as Array[int],
		"the config carries which slots the pads drive")


func _button(device: int, index: int, pressed: bool) -> InputEventJoypadButton:
	var e := InputEventJoypadButton.new()
	e.device = device
	e.button_index = index
	e.pressed = pressed
	return e


func _motion(device: int, axis: int, value: float) -> InputEventJoypadMotion:
	var e := InputEventJoypadMotion.new()
	e.device = device
	e.axis = axis
	e.axis_value = value
	return e
