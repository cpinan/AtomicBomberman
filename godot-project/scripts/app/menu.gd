# The menu, as a model. No drawing, no nodes, no input events.
#
# WHY IT IS SPLIT THIS WAY. Everything a menu can get wrong is in the model —
# a value that will not wrap, a level index out of range, a round with nobody
# in it, a "start" that hands the game a scheme it cannot parse. None of that
# needs a window, and `tests/test_menu.gd` exercises all of it headless.
# scripts/render/menu_view.gd draws whatever this holds and decides nothing.
#
# ---------------------------------------------------------------------------
# THE OPTIONS ARE THE ORIGINAL'S, NOT A GUESS AT THEM
# ---------------------------------------------------------------------------
# `MESSAGES.TXT` 250-268 is the original's settings screen, label by label and
# in order, and `OPTIONS.BM` is that screen's help text explaining what each
# one does. Between them they say exactly which VALUELST resources are SETTINGS
# rather than constants. Every label below comes from `Messages`, so the words
# on screen are the game's own.
#
# The original's list is longer than this one. Left out, because the simulation
# does not implement them yet and a menu item that does nothing is worse than
# its absence: Modem, and the network protocol chooser. docs/STATUS.md names
# them.
#
# Win Matches By Kill Total (255) and Random Start (251) used to be on that
# list and are now real: the first counts kills instead of rounds toward the
# same target, the second deals the scheme's start cells out at random once a
# match. OPTIONS.BM is the source for both, word for word.
#
# ---------------------------------------------------------------------------
# TEN SLOTS, NOT "PLAYERS PLUS BOTS"
# ---------------------------------------------------------------------------
# `MESSAGES.TXT` 220-224 says what a slot can be: OFF, AI, KEY %u, JOY %u, NET.
# That is the original's player model and it is a better one than a human count
# plus a bot count — it is what lets slots 1 and 5 be keyboard players while 2,
# 3 and 4 are AI, which the pair of counts cannot express.
#
# JOY is selectable when a pad is plugged in — `MESSAGES.TXT` 223's own slot
# type, `scripts/app/pads.gd` behind it. NET is not selectable: a network
# player claims its own seat when it joins, which is the server's business
# rather than this screen's.
extends RefCounted

const Const_ := preload("res://scripts/core/const.gd")
const Types_ := preload("res://scripts/core/types.gd")
const Values_ := preload("res://scripts/core/values.gd")
const Messages_ := preload("res://scripts/core/messages.gd")
const Scheme_ := preload("res://scripts/core/scheme.gd")
const Keysets_ := preload("res://scripts/app/keysets.gd")

## The name the built-in fallback grid goes by. Always present, always last, so
## the menu is usable on a machine with no copy of the game.
const BUILT_IN := "BUILT-IN GRID"

## What a player slot is. The values are MESSAGES.TXT 220-224's own list, minus
## JOY. KEY covers both keysets: which one is the slot's index among the
## keyboard slots, so the first keyboard slot is KEY 1 and the second is KEY 2.
enum Slot { OFF, AI, KEY, JOY, NET }

## "Random Each Game" — MESSAGES.TXT 149, the level list's own extra entry.
const LEVEL_RANDOM := -1

enum Item {
	CAMPAIGN, SCHEME, LEVEL, PLAY_TIME, WINS, KILL_TOTAL, RANDOM_START, GOLD,
	TEAM_PLAY, ENCLOSE, CONVEYOR, STOMPED, DISEASES, NO_MUSIC, LOST_NET_AI,
	KEY_DEFS, SLOTS, START, HOST, QUIT,
}

## What activating START or HOST asked for. Read by main.gd; nothing else.
enum Action { NONE, START, HOST, QUIT }

## Items that do something when Return is pressed rather than holding a value.
const ACTIONS := [Item.START, Item.HOST, Item.QUIT, Item.KEY_DEFS]

# ---------------------------------------------------------------------------
# THE KEYBOARD-DEFINITIONS SCREEN — MESSAGES.TXT 1100-1140
# ---------------------------------------------------------------------------
# The disc specifies the whole thing and the port had none of it: 1100 names
# the screen, 1105 is the prompt ("Press key for '%s'"), 1110 is a row's
# heading ("Key %u, %s"), 1120-1125 are the six actions in their own order,
# 1130 is "Return to default keys" and 1131 is what that says afterwards.
#
# It is a MODE of this model rather than a screen of its own, the same way the
# ten player slots are: same cursor, same Return, and Escape backs out. Two
# keysets times six actions is twelve rows, then the restore-defaults row.

## Rows on the key screen: 12 bindings, then "Return to default keys".
const KEY_ROWS := 13
const KEY_RESTORE_ROW := 12

var in_keys: bool = false
var key_cursor: int = 0

## Which row is waiting for a keypress, or -1. While this is set the screen
## shows MESSAGES.TXT 1105 and the next key pressed is bound to that row.
var awaiting_key: int = -1

## What the key screen last said — 1131 after a restore, or why a binding was
## refused. Cleared by the next move.
var key_notice: String = ""

## Play Time, from OPTIONS.BM: "(1:00, 1:30, 2:00, 2:30, 3:00, 4:00, 5:00,
## 10:00, Infinite)". In seconds, with 0 for Infinite. Resource 100's default
## is 150 — which is 2:30, and is in the list, which is a good sign that this
## list is the real one.
const PLAY_TIMES := [60, 90, 120, 150, 180, 240, 300, 600, 0]

var cursor: int = Item.SCHEME

var scheme_names: Array[String] = []
var scheme_index: int = 0
var level: int = 0
var play_time_index: int = 3          ## 150 s, resource 100's default
var wins: int = 2
var win_by_kills: bool = false
var random_start: bool = false
var team_play: bool = false
var enclose_depth: int = 1
var conveyor_index: int = 1
var stomped_detonate: bool = true
var diseases_destroyable: bool = true

## MESSAGES.TXT 263, "Disable music during gameplay". Off by default: the disc
## ships the music and OPTIONS.BM offers this as a performance escape, not as
## the normal way to play.
var no_music: bool = false

## MESSAGES.TXT 256, "Gold Bomberman". On by default — no VALUELST resource
## states a default and the disc ships the whole feature, screen and all.
## OPTIONS.BM: not available in network games, which main.gd enforces
## separately, so this is only about a local match.
var gold_bomberman: bool = true

## Which campaign START plays, or "" for an ordinary match. The three names are
## the disc's own files — SIMPLE, GHOSTS, CROUTON — and the pack carries them,
## so a build with no campaigns simply has nothing to cycle through.
## scripts/core/campaign.gd.
var campaign: String = ""
var campaign_names: Array[String] = []
var lost_net_to_ai: bool = true
var port: int = 47600

## One entry per slot, from Slot. The cursor walks into this list when it is on
## Item.SLOTS, so `slot_cursor` is where inside it.
var slots: Array[int] = []
var slot_cursor: int = 0
var in_slots: bool = false

## WHICH TEAM EACH SLOT IS ON, when team play is enabled.
##
## INPUT.BM, the help text for this very screen: "To toggle which team a player
## is on, press 'T'. You need to have team play enabled (from the options
## screen) for this feature to work."
##
## So the screen can override the default split, and the port could not: teams
## came from Const_.default_team() and nothing could change them. OPTIONS.BM
## gives the default — "generally, players 1 through 5 are on one team and
## players 6 through 10 are on another" — and "generally" is the word that says
## it is a default rather than a rule.
var slot_team: Array[int] = []

## How many gamepads are plugged in. Set by main.gd from
## scripts/app/pads.gd's own count; zero takes JOY out of the slot cycle.
var pads_available: int = 0

## Set by activate(); main.gd clears it once acted on.
var action: int = Action.NONE

## Why a start was refused, or "" — shown by the view rather than swallowed.
var refusal: String = ""


## Build the menu. `available` is the scheme names the pack carries; the
## built-in grid is appended whatever happens.
## The campaigns a pack carries, in the order they will be offered.
func set_campaigns(names: Array) -> void:
	campaign_names = []
	for name in names:
		campaign_names.append(String(name))
	campaign = ""


func setup(available: Array = []) -> void:
	scheme_names = []
	for name in available:
		scheme_names.append(String(name))
	scheme_names.append(BUILT_IN)
	scheme_index = 0
	wins = int(Values_.V[Const_.Res.WINS_TO_WIN])
	enclose_depth = int(Values_.V[Const_.Res.ENCLOSE_DEPTH])
	conveyor_index = 1
	play_time_index = PLAY_TIMES.find(
		int(Values_.V[Const_.Res.ROUND_SECONDS]))
	if play_time_index < 0:
		play_time_index = PLAY_TIMES.size() - 1
	# Resource 40: "default value of \"do we randomize player starting
	# positions?\"", and it is 1. The disc starts this ON.
	random_start = Values_.V[Const_.Res.RANDOM_START] != 0
	stomped_detonate = Values_.V[Const_.Res.WALL_DETONATES_BOMB] != 0
	diseases_destroyable = Values_.V[Const_.Res.DISEASE_DESTROYABLE] != 0

	# One keyboard player and five AI, which is a game somebody can start by
	# pressing Return twice and is what the quickest useful default looks like.
	slots = []
	slot_team = []
	for i in Const_.PLAYER_COUNT:
		slots.append(Slot.KEY if i == 0 else (Slot.AI if i < 6 else Slot.OFF))
		slot_team.append(Const_.default_team(i))
	slot_cursor = 0
	in_slots = false
	cursor = Item.SCHEME
	action = Action.NONE
	refusal = ""


func item_count() -> int:
	return Item.size()


func level_count() -> int:
	# Resource 35 — "how many different levels (waves) are defined?" — is 11,
	# which is also how many FIELD<n>.PCX the disc ships and how many names
	# MESSAGES.TXT 150-160 gives.
	return int(Values_.V[Const_.Res.LEVEL_COUNT])


func selected() -> int:
	return cursor


func is_action(item: int) -> bool:
	return ACTIONS.has(item)


## Move the cursor. Wraps, because a menu that stops at the ends makes the
## reader check whether it is broken.
##
## THE SLOTS ARE A SCREEN, NOT A ROW. They were once walked as part of this
## same column — arriving on Item.SLOTS entered the ten of them and walking off
## the end left again — and that was written when the slots were drawn in the
## settings list. They are not: "Who is playing" is its own screen, and the
## options list skips Item.SLOTS when it draws.
##
## So the cursor used to disappear for ten presses in the middle of the options
## list, and START, HOST A GAME and QUIT — the three rows after it — could only
## be reached by pressing down eleven times past a row that was not on the
## screen. Worse, Return during those ten presses cycled the invisible slot
## under the cursor, and slot 1 going from KEY to OFF is a game with no
## keyboard player in it at all: that is "cannot select START" and "human user
## cannot put bombs", one cause, two symptoms. docs/BUGS.md D28.
func move(delta: int) -> void:
	refusal = ""
	if in_keys:
		# A screen waiting for a key does not navigate: every key belongs to
		# the binding until one is taken or Escape cancels it.
		if awaiting_key >= 0:
			return
		key_notice = ""
		key_cursor = posmod(key_cursor + delta, KEY_ROWS)
		return
	if in_slots:
		# The setup screen is the ten slots and nothing else, so it wraps
		# inside them rather than escaping into a list it does not draw.
		if slots.is_empty():
			return
		slot_cursor = posmod(slot_cursor + delta, slots.size())
		return
	# The options list, with Item.SLOTS stepped over because it is not on it.
	var step := 1 if delta >= 0 else -1
	var target := cursor
	for i in absi(delta):
		target = posmod(target + step, item_count())
		if target == Item.SLOTS:
			target = posmod(target + step, item_count())
	cursor = target


## Change the selected item's value.
##
## Values CLAMP rather than wrap: a play time that jumps from 10:00 to 1:00 on
## one keypress is a way to start the wrong game by accident. The scheme list
## and the slot states wrap, because 68 schemes is a long walk and a slot has
## five states.
func adjust(delta: int) -> void:
	refusal = ""
	if in_slots:
		var step := 1 if delta >= 0 else -1
		slots[slot_cursor] = posmod(slots[slot_cursor] + delta, Slot.size())
		# Two states are stepped over rather than offered. NET, because a
		# network player claims its own seat when it joins, which is the
		# server's business. JOY, when no pad is plugged in: a slot that cannot
		# move is worse than a slot that is not offered, and MESSAGES.TXT 223's
		# "JOY %u" has nothing to number.
		for _guard in Slot.size():
			var state: int = slots[slot_cursor]
			if state == Slot.NET or (state == Slot.JOY and pads_available < 1):
				slots[slot_cursor] = posmod(state + step, Slot.size())
			else:
				break
		return
	match cursor:
		Item.CAMPAIGN:
			if campaign_names.is_empty():
				campaign = ""
			else:
				# OFF, then each campaign, wrapping — OFF is index 0 of a list
				# one longer than the campaigns.
				var at := campaign_names.find(campaign) + 1
				at = posmod(at + delta, campaign_names.size() + 1)
				campaign = "" if at == 0 else campaign_names[at - 1]
		Item.SCHEME:
			scheme_index = posmod(scheme_index + delta, scheme_names.size())
		Item.LEVEL:
			level = clampi(level + delta, LEVEL_RANDOM, level_count() - 1)
		Item.PLAY_TIME:
			play_time_index = clampi(play_time_index + delta, 0,
				PLAY_TIMES.size() - 1)
		Item.WINS:
			wins = clampi(wins + delta, 1, 9)
		Item.KILL_TOTAL:
			if delta != 0:
				win_by_kills = not win_by_kills
		Item.RANDOM_START:
			if delta != 0:
				random_start = not random_start
		Item.TEAM_PLAY:
			if delta != 0:
				team_play = not team_play
		Item.ENCLOSE:
			enclose_depth = clampi(enclose_depth + delta, 0,
				int(Values_.V[Const_.Res.ENCLOSE_DEPTH_COUNT]) - 1)
		Item.CONVEYOR:
			conveyor_index = clampi(conveyor_index + delta, 0,
				int(Values_.V[Const_.Res.CONVEYOR_SPEED_COUNT]) - 1)
		Item.STOMPED:
			if delta != 0:
				stomped_detonate = not stomped_detonate
		Item.DISEASES:
			if delta != 0:
				diseases_destroyable = not diseases_destroyable
		Item.NO_MUSIC:
			if delta != 0:
				no_music = not no_music
		Item.GOLD:
			if delta != 0:
				gold_bomberman = not gold_bomberman
		Item.LOST_NET_AI:
			if delta != 0:
				lost_net_to_ai = not lost_net_to_ai


## Press Return. Returns the action taken, which is Action.NONE for a value
## item — pressing Return on "level" should do nothing, not start the game.
## On a slot it cycles the slot, which is what a player expects of a list.
func activate() -> int:
	refusal = ""
	if in_keys:
		key_notice = ""
		if key_cursor == KEY_RESTORE_ROW:
			Keysets_.reset_to_defaults()
			key_notice = Messages_.DEFAULT_KEYS_RESTORED
		else:
			awaiting_key = key_cursor
		action = Action.NONE
		return action
	if in_slots:
		# The setup screen's own Return STARTS the game — main.gd handles it
		# before this is reached. Nothing else should be able to get here, but
		# if it does, cycling the slot under an invisible cursor is exactly the
		# defect this file now documents, so it does nothing instead.
		action = Action.NONE
		return action
	if cursor == Item.KEY_DEFS:
		in_keys = true
		key_cursor = 0
		awaiting_key = -1
		key_notice = ""
		action = Action.NONE
		return action
	match cursor:
		Item.START:
			action = Action.START
		Item.HOST:
			action = Action.HOST
		Item.QUIT:
			action = Action.QUIT
		_:
			action = Action.NONE
	return action


func scheme_name() -> String:
	return scheme_names[scheme_index] if not scheme_names.is_empty() else BUILT_IN


func built_in_selected() -> bool:
	return scheme_name() == BUILT_IN


## The label for one item, in the original's own words where it has them.
func label_of(item: int) -> String:
	match item:
		Item.CAMPAIGN:
			return "Campaign"
		Item.SCHEME:
			return _strip(Messages_.OPT_SCHEME_FILE)
		Item.LEVEL:
			return "Level"
		Item.PLAY_TIME:
			return _strip(Messages_.OPT_PLAY_TIME)
		Item.WINS:
			# The disc has one number and two words for what it counts:
			# 208 "Wins" and 209 "Kills", 120 and 121 for the whole sentence.
			return "%s to win match" % (Messages_.KILLS if win_by_kills
				else Messages_.WINS)
		Item.KILL_TOTAL:
			return _strip(Messages_.OPT_WIN_BY_KILLS)
		Item.RANDOM_START:
			return _strip(Messages_.OPT_RANDOM_START)
		Item.TEAM_PLAY:
			return _strip(Messages_.OPT_TEAM_PLAY)
		Item.ENCLOSE:
			return _strip(Messages_.OPT_ENCLOSE_DEPTH)
		Item.CONVEYOR:
			return _strip(Messages_.OPT_CONVEYOR_SPEED)
		Item.STOMPED:
			return _strip(Messages_.OPT_STOMPED_DETONATE)
		Item.DISEASES:
			return _strip(Messages_.OPT_DISEASES_DESTROYED)
		Item.NO_MUSIC:
			return _strip(Messages_.OPT_DISABLE_MUSIC)
		Item.GOLD:
			return _strip(Messages_.OPT_GOLD_BOMBERMAN)
		Item.LOST_NET_AI:
			return _strip(Messages_.OPT_LOST_NET_TO_AI)
		Item.KEY_DEFS:
			return Messages_.OPT_DEFINE_KEYS
		Item.SLOTS:
			return "Players"
		Item.START:
			return "START"
		Item.HOST:
			return "HOST A GAME"
		Item.QUIT:
			return "QUIT"
	return ""


## MESSAGES.TXT's option labels are format strings — `"Team Play: %s"` — and
## this screen puts the value in its own column, so the label is the part
## before the colon.
static func _strip(text: String) -> String:
	var colon := text.find(":")
	return text.substr(0, colon) if colon > 0 else text


## What the selected item reads as, right-hand column.
func value_text(item: int) -> String:
	match item:
		Item.SCHEME:
			return "%s  (%d of %d)" % [scheme_name(), scheme_index + 1,
				scheme_names.size()]
		Item.CAMPAIGN:
			if campaign.is_empty():
				return "OFF" if not campaign_names.is_empty() else "none packed"
			return campaign
		Item.LEVEL:
			if level == LEVEL_RANDOM:
				return Messages_.LEVEL_RANDOM
			return "%d  %s" % [level, Messages_.LEVEL_NAMES[level]]
		Item.PLAY_TIME:
			return play_time_text()
		Item.WINS:
			return str(wins)
		Item.KILL_TOTAL:
			return _yes_no(win_by_kills)
		Item.RANDOM_START:
			return _yes_no(random_start)
		Item.TEAM_PLAY:
			return _yes_no(team_play)
		Item.ENCLOSE:
			return Messages_.ENCLOSE_NAMES[clampi(enclose_depth, 0,
				Messages_.ENCLOSE_NAMES.size() - 1)]
		Item.CONVEYOR:
			return Messages_.CONVEYOR_NAMES[clampi(conveyor_index, 0,
				Messages_.CONVEYOR_NAMES.size() - 1)]
		Item.STOMPED:
			return _yes_no(stomped_detonate)
		Item.DISEASES:
			return _yes_no(diseases_destroyable)
		Item.NO_MUSIC:
			return _yes_no(no_music)
		Item.GOLD:
			return _yes_no(gold_bomberman)
		Item.LOST_NET_AI:
			return _yes_no(lost_net_to_ai)
		Item.SLOTS:
			return "%d playing, %d of them AI" % [seats(), ai_count()]
	return ""


## MESSAGES.TXT 25 and 26 are " No " and " Yes ", spaces included — they are
## drawn into a button in the original. Trimmed here, where they are a value in
## a list.
static func _yes_no(on: bool) -> String:
	return "Yes" if on else "No"


# ---------------------------------------------------------------------------
# The key screen's rows
# ---------------------------------------------------------------------------
## Which keyset a row belongs to, and which action within it.
static func key_row_keyset(row: int) -> int:
	return row / Keysets_.ACTIONS.size()


static func key_row_action(row: int) -> String:
	return Keysets_.ACTIONS[row % Keysets_.ACTIONS.size()]


## "Key 1, Move Up" — MESSAGES.TXT 1110 with 1120-1125 inside it.
func key_row_label(row: int) -> String:
	if row == KEY_RESTORE_ROW:
		return Messages_.RESTORE_DEFAULT_KEYS
	return Messages_.fmt(Messages_.KEY_ROW, [key_row_keyset(row) + 1,
		Keysets_.action_label(key_row_action(row))])


## What that row is bound to, or the prompt while it waits.
func key_row_value(row: int) -> String:
	if row == KEY_RESTORE_ROW:
		return ""
	if row == awaiting_key:
		return Messages_.fmt(Messages_.PRESS_KEY_FOR,
			[Keysets_.action_label(key_row_action(row))])
	var ks: int = key_row_keyset(row)
	return Keysets_.key_label(
		int((Keysets_.MAPS[ks] as Dictionary)[key_row_action(row)]))


## Take a key for the row that is waiting. Returns true if it was consumed —
## which it is either way once a row is waiting, so a refused key does not also
## move the cursor.
func take_key(keycode: int) -> bool:
	if not in_keys or awaiting_key < 0:
		return false
	var row := awaiting_key
	awaiting_key = -1
	if keycode == KEY_ESCAPE:
		key_notice = ""
		return true
	var why := Keysets_.bind_key(key_row_keyset(row), key_row_action(row),
		keycode)
	key_notice = why
	return true


## Leave the player-slot screen. Returns false if it was not open, so Escape
## falls through to the screen underneath.
## INPUT.BM's own 'T'. Returns false when there is nothing to toggle — team
## play off, or the cursor not in the slots — so the caller can say why.
func toggle_team() -> bool:
	if not in_slots or not team_play:
		return false
	if slot_cursor < 0 or slot_cursor >= slot_team.size():
		return false
	slot_team[slot_cursor] = 1 - slot_team[slot_cursor]
	return true


## INPUT.BM again, from MANUAL.BM's side this time: "Ctrl-A - Set all players to
## AI in the controller setup screen (won't work in network play!)". Every slot
## that is switched on becomes an AI; the ones that are OFF stay off, because
## turning ten empty seats into ten opponents is not what the key is for.
func all_to_ai() -> int:
	if not in_slots:
		return 0
	var changed := 0
	for i in slots.size():
		if slots[i] == Slot.OFF or slots[i] == Slot.NET:
			continue
		if slots[i] != Slot.AI:
			slots[i] = Slot.AI
			changed += 1
	return changed


func team_of(index: int) -> int:
	if index < 0 or index >= slot_team.size():
		return Const_.default_team(index)
	return slot_team[index]


func leave_slots() -> bool:
	if not in_slots:
		return false
	in_slots = false
	cursor = Item.SLOTS
	return true


## Leave the key screen, keeping whatever was bound. Returns false if it was
## not open, so the caller knows whether Escape was consumed here.
##
## Saving happens HERE and not on every keypress: a player walking down the
## list rebinding four keys should write the file once. The path is a parameter
## so a test can prove the save happens without writing over the player's own.
func leave_keys(path: String = Keysets_.CONFIG_PATH) -> bool:
	if not in_keys:
		return false
	if awaiting_key >= 0:
		awaiting_key = -1
		key_notice = ""
		return true
	in_keys = false
	Keysets_.save_keys(path)
	return true


## MESSAGES.TXT 281 is "%u:%02u" and 280 is "Infinite".
func play_time_text() -> String:
	var seconds: int = PLAY_TIMES[play_time_index]
	if seconds == 0:
		return Messages_.TIME_INFINITE
	return Messages_.fmt(Messages_.TIME_FORMAT, [seconds / 60, seconds % 60])


func play_time_seconds() -> int:
	return int(PLAY_TIMES[play_time_index])


## What one slot reads as. MESSAGES.TXT 220-224: OFF, AI, "KEY %u", NET.
func slot_text(index: int) -> String:
	match slots[index]:
		Slot.OFF:
			return Messages_.SLOT_OFF
		Slot.AI:
			return Messages_.SLOT_AI
		Slot.KEY:
			return Messages_.fmt(Messages_.SLOT_KEY, key_number(index) + 1)
		Slot.JOY:
			return Messages_.fmt(Messages_.SLOT_JOY, pad_number(index) + 1)
		Slot.NET:
			return Messages_.SLOT_NET
	return ""


## Which keyset a slot uses: its position among the keyboard slots. Two exist
## (Keysets.MAPS), so a third keyboard slot has none and says so.
func key_number(index: int) -> int:
	var n := 0
	for i in slots.size():
		if i == index:
			return n
		if slots[i] == Slot.KEY:
			n += 1
	return n


## Which pad a slot uses: its position among the joystick slots, the same rule
## the keyboard slots follow.
func pad_number(index: int) -> int:
	var n := 0
	for i in slots.size():
		if i == index:
			return n
		if slots[i] == Slot.JOY:
			n += 1
	return n


## Which slot each pad drives, in pad order.
func pad_slots() -> Array[int]:
	var out: Array[int] = []
	for i in slots.size():
		if slots[i] == Slot.JOY:
			out.append(i)
	return out


func pad_count() -> int:
	var n := 0
	for state in slots:
		if state == Slot.JOY:
			n += 1
	return n


func keyboard_count() -> int:
	var n := 0
	for state in slots:
		if state == Slot.KEY:
			n += 1
	return n


func ai_count() -> int:
	var n := 0
	for state in slots:
		if state == Slot.AI:
			n += 1
	return n


## How many seats a round will start with.
func seats() -> int:
	var n := 0
	for state in slots:
		if state != Slot.OFF:
			n += 1
	return n


## The slot indices that are AI, which is what the sim needs to add bots.
func ai_slots() -> Array[int]:
	var out: Array[int] = []
	for i in slots.size():
		if slots[i] == Slot.AI:
			out.append(i)
	return out


## Which slot each keyset drives, in keyset order.
func key_slots() -> Array[int]:
	var out: Array[int] = []
	for i in slots.size():
		if slots[i] == Slot.KEY:
			out.append(i)
	return out


## The configuration main.gd should start. Callers pass the pack so the scheme
## text can be looked up; a null pack means the built-in grid.
func config(pack: RefCounted = null) -> Dictionary:
	var text := ""
	if not built_in_selected() and pack != null:
		text = pack.scheme_text(scheme_name())
	return {
		"scheme_name": scheme_name(),
		"scheme_text": text,
		"level": level,
		"seconds": play_time_seconds(),
		"wins": wins,
		"kill_total": win_by_kills,
		"random_start": random_start,
		"teams": team_play,
		"enclose_depth": enclose_depth,
		"conveyor": conveyor_index,
		"stomped": stomped_detonate,
		"diseases_destroyable": diseases_destroyable,
		"no_music": no_music,
		"gold": gold_bomberman,
		"campaign": campaign,
		"lost_net_to_ai": lost_net_to_ai,
		"slots": slots.duplicate(),
		"slot_teams": slot_team.duplicate(),
		"ai_slots": ai_slots(),
		"key_slots": key_slots(),
		"pad_slots": pad_slots(),
		"port": port,
	}


## Check a configuration is startable, and say why not if it is not.
func validate(pack: RefCounted = null) -> bool:
	refusal = ""
	if seats() < 1:
		refusal = "no slot is switched on"
		return false
	if seats() < 2:
		# A one-player round cannot end by anyone winning it, so it would run
		# to the clock every time. Said plainly rather than allowed and then
		# wondered about.
		refusal = "a round needs two players; switch on another slot"
		return false
	if keyboard_count() == 0 and pad_count() == 0 and campaign.is_empty():
		# NOBODY AT THE CONTROLS. Ten AI slots start, play and finish a round
		# with nothing for the person watching to do, and the first report of
		# it was "human user cannot put bombs" — which was exactly true. Said
		# here instead.
		refusal = "no slot is on the keyboard or a pad; nobody would be playing"
		return false
	if keyboard_count() > Keysets_.MAPS.size():
		refusal = "%d keyboard players, and there are only %d keysets" \
			% [keyboard_count(), Keysets_.MAPS.size()]
		return false
	if pad_count() > pads_available:
		# A JOY slot with no pad behind it stands still all round. Refused
		# here rather than discovered on the field.
		refusal = "%d joystick players, and %d %s plugged in" % [
			pad_count(), pads_available,
			"pad is" if pads_available == 1 else "pads are"]
		return false
	if built_in_selected():
		return true
	if pack == null or not pack.has_scheme(scheme_name()):
		refusal = "%s is not in the asset pack" % scheme_name()
		return false
	var scheme: Scheme_ = Scheme_.new()
	if not scheme.parse_text(pack.scheme_text(scheme_name()), scheme_name()):
		refusal = "%s will not parse: %s" % [scheme_name(), scheme.error()]
		return false
	return true
