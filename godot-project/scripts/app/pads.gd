# Gamepads, as `MESSAGES.TXT` 223's `JOY %u` slot type asks for.
#
# ---------------------------------------------------------------------------
# WHAT THE DISC SAYS AND WHAT IT DOES NOT
# ---------------------------------------------------------------------------
# 223 is the whole specification: a slot may be a joystick, numbered. The
# keyboard has a definitions screen of its own (1100-1140) and the joystick has
# none, so there is nothing on the disc naming which button does what — the
# original's own joystick handling is DINPUT and a dialog Windows drew.
#
# So the mapping here is the port's, and it is the conventional one:
#
#   left stick or D-pad  the four directions
#   the bottom face button (A / cross) and the right one (B / circle)
#                        action 1 and action 2, in that order
#
# THE DIRECTION RULE IS THE KEYBOARD'S. `scripts/app/keysets.gd` resolves a
# diagonal to whichever direction was pressed most recently, because the
# simulation only ever moves on one axis. A stick pushed diagonally has to obey
# the same rule or a pad would be able to do something a keyboard cannot, so
# the stick is read as four directional "keys" that go down and up at the
# threshold, and the most recent one wins.
extends RefCounted

const Types_ := preload("res://scripts/core/types.gd")

## How far the stick must move before it counts as a press, and how far back it
## must come before it counts as a release. Two values, not one: a single
## threshold makes a stick resting on the line chatter between pressed and
## released every frame.
const PRESS := 0.55
const RELEASE := 0.35

## The buttons, in the order the two actions are numbered.
const BUTTON_FIRST := JOY_BUTTON_A
const BUTTON_SECOND := JOY_BUTTON_B

## How many pads a game can seat. Ten slots, so ten pads.
const MAX_PADS := 10

const DIRECTIONS := ["up", "down", "left", "right"]

# Per pad: which directions are held, most recent last, and the two action
# edges. Same shape and same rule as the keyboard's.
var _held: Dictionary = {}
var _first_edge: Dictionary = {}
var _second_edge: Dictionary = {}

## Whether the FIRST action button is physically down right now, per pad —
## the keyboard's `_first_held` again, same reason: hold-to-carry.
var _first_held: Dictionary = {}


## Feed one input event. Buttons and axes both arrive here.
func handle(event: InputEvent) -> void:
	if event is InputEventJoypadButton:
		_button(event as InputEventJoypadButton)
	elif event is InputEventJoypadMotion:
		_motion(event as InputEventJoypadMotion)


func _button(event: InputEventJoypadButton) -> void:
	var pad := event.device
	match event.button_index:
		JOY_BUTTON_DPAD_UP:
			_set_direction(pad, "up", event.pressed)
		JOY_BUTTON_DPAD_DOWN:
			_set_direction(pad, "down", event.pressed)
		JOY_BUTTON_DPAD_LEFT:
			_set_direction(pad, "left", event.pressed)
		JOY_BUTTON_DPAD_RIGHT:
			_set_direction(pad, "right", event.pressed)
		BUTTON_FIRST:
			if event.pressed:
				_first_edge[pad] = true
			_first_held[pad] = event.pressed
		BUTTON_SECOND:
			if event.pressed:
				_second_edge[pad] = true


func _motion(event: InputEventJoypadMotion) -> void:
	var pad := event.device
	var value := event.axis_value
	match event.axis:
		JOY_AXIS_LEFT_X:
			_axis(pad, "left", "right", value)
		JOY_AXIS_LEFT_Y:
			_axis(pad, "up", "down", value)


## One axis, as two opposed directions. Negative is up and left, which is
## Godot's own sign convention and the screen's.
func _axis(pad: int, negative: String, positive: String, value: float) -> void:
	if value <= -PRESS:
		_set_direction(pad, negative, true)
		_set_direction(pad, positive, false)
	elif value >= PRESS:
		_set_direction(pad, positive, true)
		_set_direction(pad, negative, false)
	elif absf(value) <= RELEASE:
		_set_direction(pad, negative, false)
		_set_direction(pad, positive, false)
	# Between RELEASE and PRESS nothing changes, which is the hysteresis.


func _set_direction(pad: int, direction: String, pressed: bool) -> void:
	var held: Array = _held.get(pad, [])
	if pressed:
		# Most recent wins, so a stale entry goes before the new one lands.
		held.erase(direction)
		held.append(direction)
	else:
		held.erase(direction)
	_held[pad] = held


## The move state for a pad this tick.
func move_state(pad: int) -> int:
	var held: Array = _held.get(pad, [])
	if held.is_empty():
		return Types_.MoveState.STILL
	match held[held.size() - 1]:
		"up": return Types_.MoveState.UP
		"down": return Types_.MoveState.DOWN
		"left": return Types_.MoveState.LEFT
		"right": return Types_.MoveState.RIGHT
	return Types_.MoveState.STILL


## The action for a pad this tick, clearing the edge. One press is one bomb,
## however long the button is held — the keyboard's rule again.
func take_action(pad: int) -> int:
	if bool(_first_edge.get(pad, false)):
		_first_edge[pad] = false
		return Types_.Action.FIRST
	if bool(_second_edge.get(pad, false)):
		_second_edge[pad] = false
		return Types_.Action.SECOND
	return Types_.Action.NONE


## Whether the FIRST action button is down right now, for hold-to-carry.
func first_held(pad: int) -> bool:
	return bool(_first_held.get(pad, false))


## Drop everything — used when the window loses focus, for the same reason the
## keyboard does it.
func release_all() -> void:
	_held = {}
	_first_edge = {}
	_second_edge = {}
	_first_held = {}


func held_count(pad: int) -> int:
	return (_held.get(pad, []) as Array).size()


## The pads Godot can see right now, in its own order. Which one is "JOY 1" is
## this list's first entry, so unplugging a pad renumbers rather than leaving a
## seat driven by nothing.
static func connected() -> Array[int]:
	var out: Array[int] = []
	for id in Input.get_connected_joypads():
		out.append(int(id))
	return out
