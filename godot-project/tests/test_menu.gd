# The menu's model: every value, every clamp, every refusal.
#
# All of it runs without a window, which is the reason the model and the view
# are separate files. What is NOT tested here is drawing — that is
# scripts/render/menu_view.gd, and a screenshot is the only honest test of it.
extends SceneTree

const T_ := preload("res://tests/t.gd")
const Const_ := preload("res://scripts/core/const.gd")
const Values_ := preload("res://scripts/core/values.gd")
const Messages_ := preload("res://scripts/core/messages.gd")
const Keysets_ := preload("res://scripts/app/keysets.gd")
const Menu_ := preload("res://scripts/app/menu.gd")
const Pack_ := preload("res://scripts/render/pack.gd")


func _init() -> void:
	var t := T_.new("menu")
	_test_defaults(t)
	_test_labels_are_the_discs(t)
	_test_level(t)
	_test_play_time(t)
	_test_clamps(t)
	_test_cursor(t)
	_test_slots(t)
	_test_the_setup_screens_own_keys(t)
	_test_validate(t)
	_test_config(t)
	_test_with_a_pack(t)
	_test_the_two_new_options(t)
	_test_flag_values(t)
	quit(t.finish())


# Every default is a VALUELST resource, not a number typed in here.
func _test_defaults(t: T_) -> void:
	var m := _menu()
	t.eq(m.wins, int(Values_.V[Const_.Res.WINS_TO_WIN]),
		"wins defaults to resource 310")
	t.eq(m.enclose_depth, int(Values_.V[Const_.Res.ENCLOSE_DEPTH]),
		"enclosement depth to resource 27")
	t.eq(m.play_time_seconds(), int(Values_.V[Const_.Res.ROUND_SECONDS]),
		"play time to resource 100")
	t.eq(m.play_time_text(), "2:30", "which reads as 2:30")
	t.eq(m.stomped_detonate, Values_.V[Const_.Res.WALL_DETONATES_BOMB] != 0,
		"stomped bombs to resource 46")
	t.eq(m.diseases_destroyable, Values_.V[Const_.Res.DISEASE_DESTROYABLE] != 0,
		"destroyable diseases to resource 120")
	t.eq(m.level, 0, "level 0")
	t.ok(not m.team_play, "team play off")
	t.eq(m.cursor, Menu_.Item.SCHEME, "the cursor starts at the top")
	t.eq(m.action, Menu_.Action.NONE, "and nothing has been chosen")

	# The default has to BE a startable game, or the quickest path through the
	# menu — Return twice — refuses.
	t.ok(m.seats() >= 2, "the default has %d players" % m.seats())
	t.eq(m.keyboard_count(), 1, "one of them on the keyboard")
	# Checked on the built-in grid, because validate() without a pack cannot
	# confirm a scheme that only exists inside one. _test_with_a_pack() does
	# the real thing against all 67.
	m.scheme_index = m.scheme_names.size() - 1
	t.ok(m.validate(null), "and it starts: %s" % m.refusal)


# The words on screen are the game's own, from MESSAGES.TXT 250-268.
func _test_labels_are_the_discs(t: T_) -> void:
	var m := _menu()
	t.eq(m.label_of(Menu_.Item.TEAM_PLAY), "Team Play",
		"the label is the disc's, minus its ': %s'")
	t.eq(m.label_of(Menu_.Item.ENCLOSE), "Enclosement Depth", "and so is this")
	t.eq(m.label_of(Menu_.Item.CONVEYOR), "Conveyor Speed", "and this")
	t.eq(m.label_of(Menu_.Item.STOMPED), "Stomped Bombs Detonate", "and this")
	t.eq(m.label_of(Menu_.Item.DISEASES), "Diseases Can Be Destroyed",
		"and this")
	t.eq(m.label_of(Menu_.Item.SCHEME), "Scheme File", "and this")
	t.eq(m.label_of(Menu_.Item.PLAY_TIME), "Play Time", "and this")
	t.eq(m.label_of(Menu_.Item.KILL_TOTAL), "Win Matches By Kill Total",
		"and 255, which used to be left out")
	t.eq(m.label_of(Menu_.Item.RANDOM_START), "Random Start", "and 251")

	# No label may still carry a format specifier: that is what reaches
	# draw_string, and a stray %s on screen is the bug this catches.
	for item in m.item_count():
		t.ok(not m.label_of(item).contains("%"),
			"label %d has no placeholder left: %s" % [item, m.label_of(item)])
		t.ok(not m.value_text(item).contains("%"),
			"value %d has no placeholder left: %s" % [item, m.value_text(item)])


func _test_level(t: T_) -> void:
	var m := _menu()
	t.eq(m.level_count(), 11, "eleven levels, from resource 35")
	for i in 11:
		m.level = i
		t.eq(m.value_text(Menu_.Item.LEVEL),
			"%d  %s" % [i, Messages_.LEVEL_NAMES[i]],
			"level %d reads as %s" % [i, Messages_.LEVEL_NAMES[i]])

	# Clamps at both ends, and the bottom end is Random rather than 0.
	m.cursor = Menu_.Item.LEVEL
	m.level = 10
	m.adjust(1)
	t.eq(m.level, 10, "level stops at the last one")
	m.level = Menu_.LEVEL_RANDOM
	m.adjust(-1)
	t.eq(m.level, Menu_.LEVEL_RANDOM, "and at Random going the other way")
	t.eq(m.value_text(Menu_.Item.LEVEL), Messages_.LEVEL_RANDOM,
		"which reads as the disc's own 'Random Each Game'")
	m.adjust(1)
	t.eq(m.level, 0, "and one step up from Random is level 0")


# OPTIONS.BM lists the play times the original offers.
func _test_play_time(t: T_) -> void:
	var m := _menu()
	var expected := ["1:00", "1:30", "2:00", "2:30", "3:00", "4:00", "5:00",
		"10:00", Messages_.TIME_INFINITE]
	t.eq(Menu_.PLAY_TIMES.size(), expected.size(),
		"nine play times, as OPTIONS.BM lists them")
	for i in expected.size():
		m.play_time_index = i
		t.eq(m.play_time_text(), expected[i], "play time %d" % i)
	m.play_time_index = expected.size() - 1
	t.eq(m.play_time_seconds(), 0, "Infinite is zero seconds")

	# Resource 100's default being IN the list is the evidence the list is the
	# right one.
	t.ok(Menu_.PLAY_TIMES.has(int(Values_.V[Const_.Res.ROUND_SECONDS])),
		"resource 100's 150 s is one of the offered times")


func _test_clamps(t: T_) -> void:
	var m := _menu()
	# Wins: 1..9, and never zero — a match nobody can win.
	m.cursor = Menu_.Item.WINS
	for _i in 20:
		m.adjust(-1)
	t.eq(m.wins, 1, "wins stops at 1, never 0")
	for _i in 20:
		m.adjust(1)
	t.eq(m.wins, 9, "and at 9")

	# Enclosement: 0..3, resource 28's count.
	m.cursor = Menu_.Item.ENCLOSE
	for _i in 10:
		m.adjust(1)
	t.eq(m.enclose_depth, int(Values_.V[Const_.Res.ENCLOSE_DEPTH_COUNT]) - 1,
		"enclosement stops at the last depth")
	t.eq(m.value_text(Menu_.Item.ENCLOSE), "All the way!",
		"which is All the way!")
	for _i in 10:
		m.adjust(-1)
	t.eq(m.enclose_depth, 0, "and at None")

	# Conveyor: resource 189's count.
	m.cursor = Menu_.Item.CONVEYOR
	for _i in 10:
		m.adjust(1)
	t.eq(m.conveyor_index, int(Values_.V[Const_.Res.CONVEYOR_SPEED_COUNT]) - 1,
		"conveyor stops at High")

	# The toggles.
	m.cursor = Menu_.Item.TEAM_PLAY
	m.adjust(1)
	t.ok(m.team_play, "team play toggles on")
	m.adjust(-1)
	t.ok(not m.team_play, "and off, whichever way you press")
	m.adjust(0)
	t.ok(not m.team_play, "and a zero delta changes nothing")

	# Scheme WRAPS, because 68 of them is a long walk.
	m.cursor = Menu_.Item.SCHEME
	m.scheme_index = 0
	m.adjust(-1)
	t.eq(m.scheme_index, m.scheme_names.size() - 1, "the scheme list wraps")


func _test_cursor(t: T_) -> void:
	# THE OPTIONS LIST AND THE SLOT SCREEN ARE TWO SCREENS, and the cursor
	# belongs to one at a time. It used to be one column — arriving on
	# Item.SLOTS entered the ten player slots and walking off the end left
	# again — which was right while the slots were drawn in the settings list
	# and wrong from the moment they got a screen of their own. The options
	# list stopped drawing Item.SLOTS and kept walking through it, so the
	# cursor vanished for ten presses in the middle of the list and START,
	# HOST A GAME and QUIT sat eleven presses past a row that was not there.
	var m := _menu()
	var seen := {}
	for _i in 200:
		t.ok(not m.in_slots, "the options list never enters the slots")
		seen[m.cursor] = true
		m.move(1)
	t.eq(seen.size(), m.item_count() - 1,
		"every item except Players is reached going down (%d of %d)"
			% [seen.size(), m.item_count() - 1])
	t.ok(not seen.has(Menu_.Item.SLOTS),
		"and Players itself is stepped over, because it is not on this screen")
	for item in [Menu_.Item.START, Menu_.Item.HOST, Menu_.Item.QUIT]:
		t.ok(seen.has(item), "%s is reachable" % m.label_of(item))

	# THE THREE ROWS AFTER THE SLOTS are the ones the defect hid. Landing on
	# each of them takes exactly one press from the row above.
	m = _menu()
	m.cursor = Menu_.Item.KEY_DEFS
	m.move(1)
	t.eq(m.cursor, Menu_.Item.START,
		"one press from Define Keys reaches Start, not the first of ten "
			+ "invisible slots")
	m.move(1)
	t.eq(m.cursor, Menu_.Item.HOST, "then Host a Game")
	m.move(1)
	t.eq(m.cursor, Menu_.Item.QUIT, "then Quit")
	m.move(-1)
	t.eq(m.cursor, Menu_.Item.HOST, "and back up the same way")
	m.move(-2)
	t.eq(m.cursor, Menu_.Item.KEY_DEFS, "two rows at a time as well")

	# Wrapping past the end and past the top skips it too.
	m.cursor = Menu_.Item.QUIT
	m.move(1)
	t.eq(m.cursor, Menu_.Item.CAMPAIGN, "the list wraps to the top")
	m.move(-1)
	t.eq(m.cursor, Menu_.Item.QUIT, "and back to the bottom")

	# THE SETUP SCREEN is the ten slots and wraps inside them: there is no
	# settings list under it to fall into, and falling into one left the screen
	# up with nothing selected on it.
	m = _menu()
	m.in_slots = true
	m.slot_cursor = 0
	m.move(-1)
	t.ok(m.in_slots, "the slot screen does not leak out of the top")
	t.eq(m.slot_cursor, m.slots.size() - 1, "it wraps to the last slot")
	for _i in m.slots.size():
		m.move(1)
	t.ok(m.in_slots, "nor out of the bottom")
	t.eq(m.slot_cursor, m.slots.size() - 1, "a full lap comes back")


func _test_slots(t: T_) -> void:
	var m := _menu()
	t.eq(m.slots.size(), Const_.PLAYER_COUNT, "ten slots")

	# Cycling a slot never lands on NET: a network player claims its own seat.
	m.in_slots = true
	m.slot_cursor = 0
	var states := {}
	for _i in 40:
		m.adjust(1)
		states[m.slots[0]] = true
		t.ok(m.slots[0] != Menu_.Slot.NET,
			"cycling never selects NET")
	t.eq(states.size(), 3, "the three selectable states are reachable")
	for _i in 40:
		m.adjust(-1)
		t.ok(m.slots[0] != Menu_.Slot.NET, "and not backwards either")

	# KEY numbering is by position among the keyboard slots, not by slot index.
	m = _menu()
	for i in m.slots.size():
		m.slots[i] = Menu_.Slot.OFF
	m.slots[4] = Menu_.Slot.KEY
	m.slots[7] = Menu_.Slot.KEY
	t.eq(m.slot_text(4), "KEY 1", "the first keyboard slot is KEY 1")
	t.eq(m.slot_text(7), "KEY 2", "the second is KEY 2, whatever its index")
	t.eq(m.keyboard_count(), 2, "two keyboard players")
	t.eq(m.key_slots(), [4, 7] as Array[int], "on slots 4 and 7")
	t.eq(m.seats(), 2, "and two seats")
	t.eq(m.ai_count(), 0, "no AI")

	m.slots[2] = Menu_.Slot.AI
	m.slots[9] = Menu_.Slot.AI
	t.eq(m.ai_slots(), [2, 9] as Array[int], "the AI slots are named")
	t.eq(m.seats(), 4, "four seats now")
	t.eq(m.slot_text(2), Messages_.SLOT_AI, "and read as AI")
	t.eq(m.slot_text(0), Messages_.SLOT_OFF, "an unused slot reads as OFF")

	# RETURN ON THE SLOT SCREEN STARTS THE GAME — the screen says so at its own
	# bottom — so the model does nothing with it and main.gd handles it. It
	# used to cycle the slot under the cursor, which was survivable while the
	# cursor was visible and was not once the options list started walking
	# through the slots without drawing them: Return then turned player 1 from
	# KEY to OFF, and the game that started had nobody at the keyboard.
	# Left/right still cycles a slot, which is what the screen offers.
	m.in_slots = true
	m.slot_cursor = 0
	var was: int = m.slots[0]
	t.eq(m.activate(), Menu_.Action.NONE, "Return on a slot starts nothing")
	t.eq(m.slots[0], was, "and does not cycle it either")
	m.adjust(1)
	t.ok(m.slots[0] != was, "left and right are what cycles a slot")


# INPUT.BM AND MANUAL.BM NAME KEYS THIS SCREEN HAS, and the port had neither.
#
#   "To toggle which team a player is on, press 'T'. You need to have team play
#    enabled (from the options screen) for this feature to work."
#   "Ctrl-A - Set all players to AI in the controller setup screen"
#
# Teams came from Const_.default_team() and nothing could change them, which
# made OPTIONS.BM's "generally, players 1 through 5 are on one team" a rule
# rather than the default its own "generally" says it is.
func _test_the_setup_screens_own_keys(t: T_) -> void:
	var m := _menu()
	m.in_slots = true
	m.slot_cursor = 0
	m.team_play = false
	t.ok(not m.toggle_team(),
		"T does nothing while team play is off, as INPUT.BM says")

	m.team_play = true
	t.eq(m.team_of(0), Const_.default_team(0),
		"a slot starts on OPTIONS.BM's own side")
	t.ok(m.toggle_team(), "and T moves it")
	t.eq(m.team_of(0), 1 - Const_.default_team(0), "to the other team")
	t.ok(m.toggle_team(), "and back")
	t.eq(m.team_of(0), Const_.default_team(0), "again")
	t.eq(m.team_of(9), Const_.default_team(9),
		"while every other slot is where it was")

	# It travels: a team chosen here has to reach the round.
	m.slot_cursor = 3
	m.toggle_team()
	var cfg := m.config(null)
	t.eq(int((cfg["slot_teams"] as Array)[3]), 1 - Const_.default_team(3),
		"the configuration carries the chosen teams")

	# Ctrl-A: every slot that is ON becomes an AI, and the empty ones stay
	# empty — turning ten empty seats into ten opponents is not what it is for.
	m = _menu()
	m.in_slots = true
	m.slots[0] = Menu_.Slot.KEY
	m.slots[1] = Menu_.Slot.AI
	m.slots[2] = Menu_.Slot.KEY
	for i in range(3, m.slots.size()):
		m.slots[i] = Menu_.Slot.OFF
	t.eq(m.all_to_ai(), 2, "Ctrl-A converts the two keyboard players")
	t.eq(m.slots[0], Menu_.Slot.AI, "slot 1 is an AI")
	t.eq(m.slots[2], Menu_.Slot.AI, "and so is slot 3")
	t.eq(m.slots[5], Menu_.Slot.OFF, "an empty slot is left empty")
	t.eq(m.all_to_ai(), 0, "and pressing it again changes nothing")

	# It only works on that screen, which is what "in the controller setup
	# screen" means.
	m.in_slots = false
	m.slots[0] = Menu_.Slot.KEY
	t.eq(m.all_to_ai(), 0, "and it does nothing from the settings list")


func _test_validate(t: T_) -> void:
	var m := _menu()

	# Nothing switched on.
	for i in m.slots.size():
		m.slots[i] = Menu_.Slot.OFF
	t.ok(not m.validate(null), "a game with no players is refused")
	t.ok(m.refusal.contains("switched on"), "and says so: %s" % m.refusal)

	# One player: a round that cannot be won, only timed out.
	m.slots[0] = Menu_.Slot.KEY
	t.ok(not m.validate(null), "and so is a game with one")
	t.ok(m.refusal.contains("two"), "and says why: %s" % m.refusal)

	# NOBODY AT THE CONTROLS. Ten AI slots is two players by every count this
	# used to make, and it is nobody playing — the first report of it was
	# "human user cannot put bombs", which was exactly what it looked like from
	# the other side of the screen.
	m = _menu()
	for i in m.slots.size():
		m.slots[i] = Menu_.Slot.AI
	m.scheme_index = m.scheme_names.size() - 1
	t.ok(not m.validate(null), "a game of nothing but AI is refused")
	t.ok(m.refusal.contains("keyboard"), "and says why: %s" % m.refusal)
	m.slots[0] = Menu_.Slot.KEY
	t.ok(m.validate(null), "one keyboard player is enough to start one")

	# Two is enough. On the built-in grid, so the scheme is not what is being
	# measured here.
	m = _menu()
	for i in m.slots.size():
		m.slots[i] = Menu_.Slot.OFF
	m.slots[0] = Menu_.Slot.KEY
	m.slots[1] = Menu_.Slot.AI
	m.scheme_index = m.scheme_names.size() - 1
	t.ok(m.validate(null), "two is a game")
	t.eq(m.refusal, "", "with nothing to complain about")

	# More keyboard players than keysets.
	for i in 4:
		m.slots[i] = Menu_.Slot.KEY
	t.ok(not m.validate(null), "four keyboard players are refused")
	t.ok(m.refusal.contains("keysets"), "and told why: %s" % m.refusal)
	t.eq(Keysets_.MAPS.size(), 2, "because there are two keysets")

	# A scheme the pack does not have.
	m = _menu()
	m.scheme_index = 0
	t.ok(not m.built_in_selected(), "a real scheme is selected")
	t.ok(not m.validate(null), "and with no pack it cannot be checked")
	t.ok(m.refusal.contains("asset pack"), "so it says so: %s" % m.refusal)

	# The built-in grid always works, which is what makes the menu usable on a
	# machine with no copy of the game.
	m.scheme_index = m.scheme_names.size() - 1
	t.ok(m.built_in_selected(), "the last entry is the built-in grid")
	t.ok(m.validate(null), "which needs no pack at all")


func _test_config(t: T_) -> void:
	var m := _menu()
	m.level = 7
	m.wins = 4
	m.team_play = true
	m.enclose_depth = 3
	m.conveyor_index = 2
	m.stomped_detonate = false
	m.diseases_destroyable = false
	m.lost_net_to_ai = false
	m.play_time_index = 0
	var cfg := m.config(null)
	t.eq(cfg["level"], 7, "the level travels")
	t.eq(cfg["wins"], 4, "the win target")
	t.eq(cfg["teams"], true, "team play")
	t.eq(cfg["enclose_depth"], 3, "the enclosement depth")
	t.eq(cfg["conveyor"], 2, "the conveyor speed")
	t.eq(cfg["stomped"], false, "stomped bombs")
	t.eq(cfg["diseases_destroyable"], false, "destroyable diseases")
	t.eq(cfg["lost_net_to_ai"], false, "the lost-net rule")
	t.eq(cfg["seconds"], 60, "the play time in seconds")
	t.eq(cfg["port"], 47600, "the port")
	t.eq(cfg["ai_slots"], m.ai_slots(), "which slots are AI")
	t.eq(cfg["key_slots"], m.key_slots(), "and which are on the keyboard")

	# START and HOST are the only two things that start anything, and QUIT is
	# the only thing that leaves.
	m.cursor = Menu_.Item.START
	t.eq(m.activate(), Menu_.Action.START, "START starts")
	m.cursor = Menu_.Item.HOST
	t.eq(m.activate(), Menu_.Action.HOST, "HOST hosts")
	m.cursor = Menu_.Item.QUIT
	t.eq(m.activate(), Menu_.Action.QUIT, "QUIT quits")
	for item in m.item_count():
		if m.is_action(item):
			continue
		m.cursor = item
		m.in_slots = false
		t.eq(m.activate(), Menu_.Action.NONE,
			"Return on %s starts nothing" % m.label_of(item))


# With the real pack, every scheme it carries has to be startable — that is 67
# schemes the menu offers and must not offer one that fails.
func _test_with_a_pack(t: T_) -> void:
	var pack: Pack_ = Pack_.new()
	if not pack.load_from(Pack_.default_dir()):
		t.note("no asset pack: %s" % pack.error)
		return
	# An assertion, not a skip. A pack that loaded but carries no schemes
	# leaves the menu offering nothing but the built-in grid, which is a
	# working menu and a broken game — exactly the kind of regression a skip
	# would hide. verify.sh rebuilds the pack before running this.
	if not t.ok(not pack.scheme_names().is_empty(),
			"a loaded pack carries schemes — rebuild with tools/pack_assets.py"):
		return

	var m: Menu_ = Menu_.new()
	m.setup(pack.scheme_names())
	t.eq(m.scheme_names.size(), pack.scheme_names().size() + 1,
		"%d schemes plus the built-in grid" % pack.scheme_names().size())

	var refused := 0
	for i in m.scheme_names.size():
		m.scheme_index = i
		if not m.validate(pack):
			refused += 1
			t.ok(false, "%s is offered but refused: %s"
				% [m.scheme_name(), m.refusal])
	t.eq(refused, 0, "every scheme the menu offers can be started")
	t.note("%d schemes offered, all startable" % m.scheme_names.size())


func _menu() -> Menu_:
	var m: Menu_ = Menu_.new()
	m.setup(["4CORNERS", "BASIC", "OG"])
	return m


# ---------------------------------------------------------------------------
# The two settings that were on the "left out" list until the simulation could
# honour them: MESSAGES.TXT 255 and 251.
# ---------------------------------------------------------------------------
func _test_the_two_new_options(t: T_) -> void:
	var m := _menu()
	t.ok(not m.win_by_kills, "Win Matches By Kill Total is off by default")
	t.eq(m.value_text(Menu_.Item.KILL_TOTAL), "No", "shown as No")
	# Random Start's default is the disc's, and the disc says ON: resource 40
	# is "default value of \"do we randomize player starting positions?\"".
	t.eq(Values_.V[Const_.Res.RANDOM_START], 1, "resource 40 says randomise")
	t.ok(m.random_start, "so Random Start starts on")
	t.eq(m.value_text(Menu_.Item.RANDOM_START), "Yes", "and reads Yes")

	# The number does not change when the thing it counts does. The disc has
	# one target and two words for it: 208 "Wins" and 209 "Kills".
	t.eq(m.label_of(Menu_.Item.WINS), "Wins to win match",
		"the target reads as wins while kills are off")
	m.cursor = Menu_.Item.KILL_TOTAL
	m.adjust(1)
	t.ok(m.win_by_kills, "and toggles on")
	t.eq(m.value_text(Menu_.Item.KILL_TOTAL), "Yes", "showing Yes")
	t.eq(m.label_of(Menu_.Item.WINS), "Kills to win match",
		"and the same target now reads as kills")
	m.adjust(-1)
	t.ok(not m.win_by_kills, "either direction toggles it back")

	m.cursor = Menu_.Item.RANDOM_START
	m.adjust(1)
	t.ok(not m.random_start, "Random Start toggles off")
	m.adjust(1)
	t.ok(m.random_start, "and back on")

	# Both have to reach the game, or the screen is decoration.
	m.cursor = Menu_.Item.KILL_TOTAL
	m.adjust(1)
	var cfg := m.config()
	t.ok(bool(cfg["kill_total"]), "the config carries the kill setting")
	t.ok(bool(cfg["random_start"]), "and the random start setting")


# ---------------------------------------------------------------------------
# The other way a setting arrives: the command line. main.gd's flag parser is
# here rather than in a suite of its own because this is the suite about how a
# player chooses settings, and the two paths have to agree.
#
# It matters for Random Start specifically: VALUELST 40 has it ON, so a flag
# that could only ever mean "true" would leave no way to turn it off.
# ---------------------------------------------------------------------------
func _test_flag_values(t: T_) -> void:
	const Main_ := preload("res://scripts/app/main.gd")
	t.ok(Main_._flag_value(true), "a bare --flag is true")
	t.ok(Main_._flag_value("1"), "--flag 1 is true")
	t.ok(Main_._flag_value("yes"), "--flag yes is true")
	t.ok(not Main_._flag_value("0"), "--flag 0 is false")
	t.ok(not Main_._flag_value("no"), "--flag no is false")
	t.ok(not Main_._flag_value("off"), "--flag off is false")
	t.ok(not Main_._flag_value("false"), "--flag false is false")
	t.ok(not Main_._flag_value(" NO "), "and the parse is trimmed and folded")
