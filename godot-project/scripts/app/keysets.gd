# Two players on one keyboard, as the original and fpc_atomic both do.
#
# Direction priority. The original allows movement on one axis at a time
# (AtomBomberman's notes: "bomberman can only move in one direction at a time,
# directions have priorities so if you press up+left it moves left as much it
# can then up as long as it cant move left"). This resolves a diagonal press to
# a single direction before the simulation ever sees it, which is why the sim
# only ever handles one axis.
#
# The exact priority order is NOT established — docs/BUGS.md Q5.1. What is
# implemented is "the most recently pressed direction wins", which is what
# makes cornering feel right and is the behaviour every later Bomberman uses.
# A fixed priority (always left over up) would make one direction unreachable
# while its partner is held.
class_name Keysets

const Types_ := preload("res://scripts/core/types.gd")
const Messages_ := preload("res://scripts/core/messages.gd")

## The six actions a player has, in MESSAGES.TXT 1120-1125's own order:
## Move Up, Move Right, Move Down, Move Left, Action 1, Action 2. The keys are
## stored under these names.
const ACTIONS := ["up", "right", "down", "left", "first", "second"]

## Where a player's own key choices are kept between runs.
const CONFIG_PATH := "user://keys.cfg"

## Bumped whenever the DEFAULTS change. A saved file from an older version is
## discarded rather than loaded.
##
## Without this, correcting the defaults corrected nothing for anybody who had
## already run the game once: keys.cfg is written whenever the
## keyboard-definitions screen is left, and it stores all twelve bindings, so
## the old wrong ones came straight back over the new right ones. The player
## sees the disc's layout; a player who has genuinely rebound a key loses that
## one change, which is the smaller loss.
const CONFIG_VERSION := 2

## THE DISC'S OWN DEFAULTS, from `INPUT.BM` — the help text for the very screen
## that sets them, which states them as a table:
##
##                 Movement       Action1      Action2
##     KEY 0:      Cursor Keys    Space        Enter
##     KEY 1:      R,D,F,G         S            A
##
## and MANUAL.BM says the same thing from the player's side: "DROP BOMB:
## (joystick button 1, spacebar, 'S')" and "ACTION: (joystick button 2, enter,
## 'a')".
##
## The port had Return and Backspace for keyset 0 and fpc_atomic's WASD for
## keyset 1, both invented. Space — the key the manual names first, and the one
## anybody reaches for — dropped no bomb at all, and Return, which the disc
## makes the ACTION button, dropped one.
const KS0 := {
	"up": KEY_UP, "down": KEY_DOWN, "left": KEY_LEFT, "right": KEY_RIGHT,
	"first": KEY_SPACE, "second": KEY_ENTER,
}

## R, D, F and G is an inverted T with the left hand: R above, D and G either
## side, F below. Read straight off INPUT.BM's table in its own order —
## movement is listed as up, left, down, right everywhere on this disc, which
## is the order MESSAGES.TXT 1120-1125 gives the six actions in.
const KS1 := {
	"up": KEY_R, "down": KEY_F, "left": KEY_D, "right": KEY_G,
	"first": KEY_S, "second": KEY_A,
}

const DEFAULTS := [KS0, KS1]

## The keys in force. Starts as the two defaults above and is rebound by the
## keyboard-definitions screen — MESSAGES.TXT 1100-1131, which names the
## screen, the prompt, all six actions and the "return to default keys" it
## offers. Static so that every part of the app sees one set of keys without
## the object having to be threaded through screens that do not otherwise
## need it.
static var MAPS: Array = [KS0.duplicate(), KS1.duplicate()]


## Put every key back the way the disc has it. MESSAGES.TXT 1130 is the item
## that does this and 1131 is what it says afterwards.
static func reset_to_defaults() -> void:
	MAPS = [KS0.duplicate(), KS1.duplicate()]


## Bind one action. Returns "" on success, or the reason it was refused.
##
## A key already in use is REFUSED rather than stolen. Nothing on the disc says
## what the original does with a duplicate, and the two alternatives are worse:
## stealing it leaves an action with no key at all, and allowing it makes one
## press do two things. The screen shows the refusal.
static func bind_key(ks: int, action: String, keycode: int) -> String:
	if ks < 0 or ks >= MAPS.size():
		return "no such keyset"
	if not ACTIONS.has(action):
		return "no such action"
	if keycode == KEY_NONE or keycode == KEY_ESCAPE:
		return "that key cannot be bound"
	for other_ks in MAPS.size():
		var map: Dictionary = MAPS[other_ks]
		for other in ACTIONS:
			if map[other] != keycode:
				continue
			if other_ks == ks and other == action:
				return ""   # already bound to exactly this: nothing to do
			return "%s is already %s on key %d" % [
				key_label(keycode), action_label(other), other_ks + 1]
	(MAPS[ks] as Dictionary)[action] = keycode
	return ""


## The disc's own word for an action — MESSAGES.TXT 1120-1125.
static func action_label(action: String) -> String:
	var i := ACTIONS.find(action)
	if i < 0 or i >= Messages_.KEY_NAMES.size():
		return action
	return Messages_.KEY_NAMES[i]


## A key's name, for the screen. Godot's own spelling, which is what a player
## sees on the key itself.
static func key_label(keycode: int) -> String:
	if keycode == KEY_NONE:
		return "-"
	return OS.get_keycode_string(keycode)


## Save the current keys. Called when the screen is left, not on every press.
static func save_keys(path: String = CONFIG_PATH) -> bool:
	var cfg := ConfigFile.new()
	cfg.set_value("keys", "version", CONFIG_VERSION)
	for ks in MAPS.size():
		for action in ACTIONS:
			cfg.set_value("keyset%d" % ks, action, int(MAPS[ks][action]))
	return cfg.save(path) == OK


## Load keys saved by a previous run. A missing file is not an error: it means
## the defaults stand. A file naming a key that is not there falls back to the
## default for that one action rather than to none.
static func load_keys(path: String = CONFIG_PATH) -> bool:
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return false
	if int(cfg.get_value("keys", "version", 1)) != CONFIG_VERSION:
		# Written before the defaults were corrected against INPUT.BM. Loading
		# it would put Return back on Drop Bomb and leave Space bound to
		# nothing, on every machine that had ever run the game.
		reset_to_defaults()
		return false
	var loaded: Array = [KS0.duplicate(), KS1.duplicate()]
	for ks in loaded.size():
		for action in ACTIONS:
			var value: Variant = cfg.get_value("keyset%d" % ks, action,
				DEFAULTS[ks][action])
			(loaded[ks] as Dictionary)[action] = int(value)
	MAPS = loaded
	return true

# Which directions are held, per keyset, most recent last. A list rather than a
# set because the order IS the priority.
var _held: Array = [[], []]
var _first_edge: Array = [false, false]
var _second_edge: Array = [false, false]


func handle(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var key := event as InputEventKey
	if key.echo:
		return
	for ks in MAPS.size():
		_handle_for(ks, key)


func _handle_for(ks: int, key: InputEventKey) -> void:
	var map: Dictionary = MAPS[ks]
	for action in ["up", "down", "left", "right"]:
		if key.keycode != map[action]:
			continue
		var held: Array = _held[ks]
		if key.pressed:
			# Most recent wins, so remove any stale entry before appending.
			held.erase(action)
			held.append(action)
		else:
			held.erase(action)
		return
	# Actions are edges, not states: one press is one bomb, however long the
	# key is held. The sim consumes the edge and clears it.
	if key.keycode == map["first"] and key.pressed:
		_first_edge[ks] = true
	elif key.keycode == map["second"] and key.pressed:
		_second_edge[ks] = true


## The move state for a keyset this tick.
func move_state(ks: int) -> int:
	var held: Array = _held[ks]
	if held.is_empty():
		return Types_.MoveState.STILL
	match held[held.size() - 1]:
		"up": return Types_.MoveState.UP
		"down": return Types_.MoveState.DOWN
		"left": return Types_.MoveState.LEFT
		"right": return Types_.MoveState.RIGHT
	return Types_.MoveState.STILL


## The action for a keyset this tick, clearing the edge.
func take_action(ks: int) -> int:
	if _first_edge[ks]:
		_first_edge[ks] = false
		return Types_.Action.FIRST
	if _second_edge[ks]:
		_second_edge[ks] = false
		return Types_.Action.SECOND
	return Types_.Action.NONE


## Drop every held key — used when focus is lost, so a player does not keep
## walking into a wall while the window is in the background.
func release_all() -> void:
	_held = [[], []]
	_first_edge = [false, false]
	_second_edge = [false, false]


func held_count(ks: int) -> int:
	return (_held[ks] as Array).size()
