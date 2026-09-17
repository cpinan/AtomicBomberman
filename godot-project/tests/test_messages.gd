# The original's own string table, as tools/messages.py generates it.
#
# Worth its own suite because MESSAGES.TXT settled several things that were
# open questions until it arrived, and a regeneration that quietly lost one of
# them would show up as a wrong word on a screen nobody was looking at.
extends SceneTree

const T_ := preload("res://tests/t.gd")
const Const_ := preload("res://scripts/core/const.gd")
const Types_ := preload("res://scripts/core/types.gd")
const Values_ := preload("res://scripts/core/values.gd")
const Messages_ := preload("res://scripts/core/messages.gd")


func _init() -> void:
	var t := T_.new("messages")
	_test_levels(t)
	_test_enclosement(t)
	_test_conveyor(t)
	_test_slots(t)
	_test_powerups(t)
	_test_format(t)
	_test_lookup(t)
	quit(t.finish())


# 150-160. Before this file the port used SOUNDLST's music filenames as level
# names, because docs/ORACLE.md said the disc shipped none as text.
func _test_levels(t: T_) -> void:
	t.eq(Messages_.LEVEL_NAMES.size(), 11, "eleven level names")
	t.eq(Messages_.LEVEL_NAMES.size(),
		int(Values_.V[Const_.Res.LEVEL_COUNT]),
		"as many names as resource 35 says there are levels")
	t.eq(Messages_.LEVEL_NAMES[0], "Green Acres", "level 0")
	t.eq(Messages_.LEVEL_NAMES[2], "The Hockey Rink", "level 2")
	t.eq(Messages_.LEVEL_NAMES[3], "Ancient Egypt", "level 3")
	t.eq(Messages_.LEVEL_NAMES[6], "Aliens", "level 6")
	t.eq(Messages_.LEVEL_NAMES[10], "Inner City Trash", "level 10")

	# The ordering is what makes the specials land on the right levels, and it
	# cross-checks against VALUELST's lockout array: 1152 is off — "too
	# annoying to have control delays!" — and 152 is The Hockey Rink, the one
	# level with an ice value. 1156 is off — "too hard to see visually!" — and
	# 156 is Aliens.
	t.eq(Values_.V[1152], 0, "resource 1152 locks a level out of random")
	t.eq(Values_.V[1156], 0, "and so does 1156")
	t.eq(Values_.V[1150], 1, "while 1150 does not")
	for i in 11:
		t.ok(not String(Messages_.LEVEL_NAMES[i]).is_empty(),
			"level %d has a name" % i)


# 315-318. docs/BUGS.md recorded the 0..3 mapping as "not stated anywhere".
func _test_enclosement(t: T_) -> void:
	t.eq(Messages_.ENCLOSE_NAMES.size(), 4, "four enclosement depths")
	t.eq(Messages_.ENCLOSE_NAMES.size(),
		int(Values_.V[Const_.Res.ENCLOSE_DEPTH_COUNT]),
		"which is what resource 28 counts")
	t.eq(Messages_.ENCLOSE_NAMES[0], "None", "depth 0 is None")
	t.eq(Messages_.ENCLOSE_NAMES[1], "A Little", "depth 1 is A Little")
	t.eq(Messages_.ENCLOSE_NAMES[2], "A Lot", "depth 2 is A Lot")
	t.eq(Messages_.ENCLOSE_NAMES[3], "All the way!", "depth 3 is All the way!")
	# Resource 27's default is 1, and "A Little" is the reading the port took
	# for it — two rows rather than the whole field.
	t.eq(Values_.V[Const_.Res.ENCLOSE_DEPTH], 1,
		"and the default is the second of them")


func _test_conveyor(t: T_) -> void:
	t.eq(Messages_.CONVEYOR_NAMES.size(),
		int(Values_.V[Const_.Res.CONVEYOR_SPEED_COUNT]),
		"a name per conveyor speed")
	t.eq(Messages_.CONVEYOR_NAMES, ["Low", "Medium", "High"] as Array,
		"Low, Medium, High — resources 190, 191, 192")


func _test_slots(t: T_) -> void:
	t.eq(Messages_.SLOT_OFF, "OFF", "a slot can be OFF")
	t.eq(Messages_.SLOT_AI, "AI", "or an AI")
	t.eq(Messages_.SLOT_NET, "NET", "or a network player")
	t.ok(Messages_.SLOT_KEY.contains("%"),
		"and KEY takes a number: %s" % Messages_.SLOT_KEY)


func _test_powerups(t: T_) -> void:
	# FOURTEEN, not the thirteen a scheme can place. The fourteenth is Clog,
	# the speed brake the roulette wheel hands out (resource 91).
	t.eq(Messages_.POWERUP_LONG.size(), 14, "fourteen powerup descriptions")
	t.eq(Messages_.POWERUP_SHORT.size(), 14, "and fourteen short names")
	t.eq(Messages_.POWERUP_SHORT[13], "Clog", "the fourteenth is Clog")
	t.eq(Messages_.POWERUP_LONG[13], "a speed brake (slowness)",
		"which is the speed brake")
	t.eq(Const_.POWERUP_COUNT, 13,
		"a scheme places thirteen of them, not fourteen")

	# The thirteen the port knows must match the disc's, in order — the enum's
	# ordinal IS the file format.
	for i in Const_.POWERUP_COUNT:
		t.eq(Types_.POWERUP_NAMES[i], Messages_.POWERUP_LONG[i],
			"powerup %d is %s" % [i, Messages_.POWERUP_LONG[i]])


# The file's placeholders are C's, and GDScript's % knows neither %u nor %02u.
func _test_format(t: T_) -> void:
	t.eq(Messages_.fmt(Messages_.SLOT_KEY, 2), "KEY 2", "%u formats")
	t.eq(Messages_.fmt(Messages_.TIME_FORMAT, [2, 30]), "2:30",
		"%02u formats, which a plain replace(\"%u\") would miss")
	t.eq(Messages_.fmt(Messages_.TIME_FORMAT, [10, 0]), "10:00",
		"and pads")
	t.eq(Messages_.fmt(Messages_.MATCH_BY_WINS, 2),
		"(Match winner must score 2 victories)", "and so does the match line")
	t.eq(Messages_.fmt("nothing to do", []), "nothing to do",
		"a string with no placeholder survives")
	# The table itself keeps the disc's text, untouched.
	t.ok(String(Messages_.TIME_FORMAT).contains("%02u"),
		"the stored text is still the disc's: %s" % Messages_.TIME_FORMAT)


func _test_lookup(t: T_) -> void:
	t.eq(Messages_.M.size(), 316, "316 strings")
	t.eq(Messages_.get_text(150), "Green Acres", "by id")
	t.eq(Messages_.get_text(999999), "<999999?>",
		"and a missing one is visible rather than empty")
	t.ok(Messages_.NODE_NAMES.size() > 40,
		"%d default node names" % Messages_.NODE_NAMES.size())
	t.eq(Messages_.STAT_LABELS.size(), 19,
		"nineteen statistics counters")
