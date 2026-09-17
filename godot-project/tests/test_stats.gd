# The statistics file — MESSAGES.TXT 900-928, written the way 0x40200C writes it.
#
# The format assertions are exact on purpose. Every part of the layout came off
# the disassembly (`%-30s %13u %13u`, the colon appended before the padding,
# Total before Last Run, 100 dwords in the binary file rather than 19) and each
# is the kind of detail a tidy-up would quietly change.
extends SceneTree

const T_ := preload("res://tests/t.gd")
const Const_ := preload("res://scripts/core/const.gd")
const Types_ := preload("res://scripts/core/types.gd")
const Values_ := preload("res://scripts/core/values.gd")
const Messages_ := preload("res://scripts/core/messages.gd")
const Scheme_ := preload("res://scripts/core/scheme.gd")
const Field_ := preload("res://scripts/sim/field.gd")
const Sim_ := preload("res://scripts/sim/sim.gd")
const Player_ := preload("res://scripts/sim/player.gd")
const Stats_ := preload("res://scripts/core/stats.gd")


func _init() -> void:
	var t := T_.new("stats")
	_test_labels(t)
	_test_text_format(t)
	_test_accumulate(t)
	_test_binary_file(t)
	_test_distance(t)
	_test_sim_events(t)
	_test_not_collected(t)
	quit(t.finish())


# ---------------------------------------------------------------------------
# The names are the disc's own
# ---------------------------------------------------------------------------
func _test_labels(t: T_) -> void:
	t.eq(Stats_.COUNT, 19, "nineteen counters, 910 to 928")
	t.eq(Messages_.STAT_LABELS.size(), Stats_.COUNT,
		"one label per counter")
	for i in Stats_.COUNT:
		t.eq(Messages_.STAT_LABELS[i], Messages_.M[Stats_.FIRST_ID + i],
			"label %d is message %d" % [i, Stats_.FIRST_ID + i])
	t.eq(Messages_.M[900], "Bomberman Statistics File:", "the file's title")
	t.ok(Messages_.M[905].ends_with("Total      Last Run"),
		"the column heading is the disc's own")

	# The enum has to be in the file's order or every row is mislabelled.
	t.eq(Stats_.C.MATCHES_STARTED, 0, "910 is first")
	t.eq(Stats_.C.BOMBS_DROPPED, 4, "914 Bombs Dropped")
	t.eq(Stats_.C.PIXELS_RUN, 8, "918 Total Pixel Distances Run")
	t.eq(Stats_.C.GHOST_LOST, 18, "928 is last")


# ---------------------------------------------------------------------------
# The layout, character for character
# ---------------------------------------------------------------------------
func _test_text_format(t: T_) -> void:
	var s := Stats_.new()
	s.total[Stats_.C.BOMBS_DROPPED] = 1234
	s.run[Stats_.C.BOMBS_DROPPED] = 7

	var lines := s.text().split("\n")
	t.eq(lines[0], "Bomberman Statistics File:", "title first")
	t.eq(lines[1], "", "a blank line after it — the format is \"%s\\n\\n\"")
	t.eq(lines[2], Messages_.M[905], "the column heading")
	t.eq(lines[3], "", "and a blank line after that too")

	# Row 0 is counter 910, so row N is at line 4 + N.
	var row: String = lines[4 + Stats_.C.BOMBS_DROPPED]
	t.eq(row, "%-30s %13d %13d" % ["Bombs Dropped:", 1234, 7],
		"a row is the label with its colon, padded to 30, then two 13s")
	t.eq(row.substr(0, 30), "Bombs Dropped:                ",
		"the colon is inside the 30-character field, not after it")
	t.ok(row.find("         1234 ") >= 0, "Total is the first column")
	t.ok(row.ends_with("            7"), "Last Run is the second")

	# 4 heading lines + 19 rows + the trailing newline's empty split.
	t.eq(lines.size(), 4 + Stats_.COUNT + 1, "nineteen rows and no more")
	for i in Stats_.COUNT:
		t.ok(lines[4 + i].begins_with(Messages_.STAT_LABELS[i] + ":"),
			"row %d is counter %d" % [i, Stats_.FIRST_ID + i])


# ---------------------------------------------------------------------------
# Total is accumulated at save time, once
# ---------------------------------------------------------------------------
func _test_accumulate(t: T_) -> void:
	var dat := "user://test_stats_a.dat"
	var txt := "user://test_stats_a.txt"
	var s := Stats_.new()
	s.total[Stats_.C.DEATHS_ALL] = 40
	s.bump(Stats_.C.DEATHS_ALL, 2)
	t.eq(s.value(Stats_.C.DEATHS_ALL), 2, "this run counts 2")
	t.eq(s.total_value(Stats_.C.DEATHS_ALL), 40, "the total is untouched until save")

	t.ok(s.save(dat, txt), "the first save writes")
	t.eq(s.total_value(Stats_.C.DEATHS_ALL), 42, "and folds the run into the total")
	t.eq(s.value(Stats_.C.DEATHS_ALL), 2, "the run column still reads 2")

	t.ok(not s.save(dat, txt), "a second save refuses")
	t.eq(s.total_value(Stats_.C.DEATHS_ALL), 42,
		"so the run cannot be counted into the total twice")

	DirAccess.remove_absolute(ProjectSettings.globalize_path(dat))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(txt))


# ---------------------------------------------------------------------------
# bmstats.dat: 100 dwords of totals, and it round-trips
# ---------------------------------------------------------------------------
func _test_binary_file(t: T_) -> void:
	var dat := "user://test_stats_b.dat"
	var txt := "user://test_stats_b.txt"
	var s := Stats_.new()
	s.bump(Stats_.C.MATCHES_STARTED, 3)
	s.bump(Stats_.C.BRICKS_DESTROYED, 500)
	# A counter the game never names still has room in the file, exactly as the
	# original's 0..99 accumulate loop gives it room.
	s.bump(60, 99)
	t.ok(s.save(dat, txt), "saved")

	var f := FileAccess.open(dat, FileAccess.READ)
	t.ok(f != null, "the binary file exists")
	if f != null:
		t.eq(f.get_length(), Stats_.DAT_BYTES, "400 bytes — 100 dwords, not 19")
		f.close()

	var back := Stats_.new()
	t.ok(back.load_totals(dat), "and loads back")
	t.eq(back.total_value(Stats_.C.MATCHES_STARTED), 3, "matches survived")
	t.eq(back.total_value(Stats_.C.BRICKS_DESTROYED), 500, "bricks survived")
	t.eq(back.total_value(60), 99, "so did the unnamed slot")
	t.eq(back.value(Stats_.C.MATCHES_STARTED), 0,
		"but the run column starts empty — only totals are on disc")

	# A first run has no file, which is not an error.
	var fresh := Stats_.new()
	t.ok(not fresh.load_totals("user://test_stats_absent.dat"),
		"a missing file reports false rather than failing")
	t.eq(fresh.total_value(0), 0, "and leaves the totals at zero")

	DirAccess.remove_absolute(ProjectSettings.globalize_path(dat))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(txt))


# ---------------------------------------------------------------------------
# 918 is in pixels, and the simulation runs in hundredths of one
# ---------------------------------------------------------------------------
func _test_distance(t: T_) -> void:
	var s := Stats_.new()
	s.add_distance_cp(250)
	t.eq(s.value(Stats_.C.PIXELS_RUN), 2, "250 centipixels is 2 whole pixels")
	s.add_distance_cp(250)
	t.eq(s.value(Stats_.C.PIXELS_RUN), 5,
		"and the carried half-pixel makes the next one 3, not 2")
	s.add_distance_cp(0)
	t.eq(s.value(Stats_.C.PIXELS_RUN), 5, "standing still adds nothing")


# ---------------------------------------------------------------------------
# What the simulation actually feeds it
# ---------------------------------------------------------------------------
func _test_sim_events(t: T_) -> void:
	var s := Stats_.new()
	var sim := _sim(2, s)
	var p: Player_ = sim.players[0]
	p.place_at_tile_centre(1, 1)
	p.flame_len = 2
	sim.field.brick[Field_.idx(2, 1)] = Types_.Brick.BRICK

	t.ok(sim.place_bomb(p) != null, "a bomb is placed")
	t.eq(s.value(Stats_.C.BOMBS_DROPPED), 1, "914 counts it")
	t.ok(sim.place_bomb(p) == null, "a second on the same cell is refused")
	t.eq(s.value(Stats_.C.BOMBS_DROPPED), 1, "and a refusal is not counted")

	# Walking moves the player, and 918 measures it.
	var before: int = s.value(Stats_.C.PIXELS_RUN)
	var q: Player_ = sim.players[1]
	q.place_at_tile_centre(5, 5)
	q.move = Types_.MoveState.RIGHT
	sim.tick()
	t.ok(s.value(Stats_.C.PIXELS_RUN) > before, "918 grows as a player walks")

	for _i in Values_.V[Const_.Res.FUZE_FRAMES]:
		sim.tick()
	t.ok(sim.field.is_open(2, 1), "the brick went")
	t.eq(s.value(Stats_.C.BRICKS_DESTROYED), 1, "917 counts the brick")

	# Deaths: 915 counts everyone, 916 only the bots.
	var s2 := Stats_.new()
	var sim2 := _sim(2, s2)
	sim2.add_bot(1)
	sim2.kill(sim2.players[0])
	t.eq(s2.value(Stats_.C.DEATHS_ALL), 1, "915 counts a human death")
	t.eq(s2.value(Stats_.C.DEATHS_AI), 0, "916 does not")
	sim2.kill(sim2.players[1])
	t.eq(s2.value(Stats_.C.DEATHS_ALL), 2, "915 counts the bot too")
	t.eq(s2.value(Stats_.C.DEATHS_AI), 1, "916 counts only the bot")
	sim2.kill(sim2.players[1])
	t.eq(s2.value(Stats_.C.DEATHS_ALL), 2, "and dying twice is once")

	# A simulation with no counters attached must behave identically. This is
	# the property that keeps the counters out of the network hash.
	var plain := _sim(1, null)
	plain.players[0].place_at_tile_centre(1, 1)
	t.ok(plain.place_bomb(plain.players[0]) != null,
		"a sim with no stats object still plays")


# ---------------------------------------------------------------------------
# The five the port cannot collect are still in the file
# ---------------------------------------------------------------------------
func _test_not_collected(t: T_) -> void:
	var s := Stats_.new()
	var lines := s.text().split("\n")
	for which in [Stats_.C.GRAPHIC_REQUESTS, Stats_.C.ATTRACT_MODES,
			Stats_.C.RETRANSMITS, Stats_.C.GHOST_FOUND, Stats_.C.GHOST_LOST]:
		t.eq(s.value(which), 0, "counter %d is not collected" % which)
		t.ok(lines[4 + which].begins_with(
				Messages_.STAT_LABELS[which] + ":"),
			"but its row is written anyway, so the file keeps its shape")


# ---------------------------------------------------------------------------
func _sim(count: int, stats) -> Sim_:
	var lines := PackedStringArray()
	lines.append("-V,2")
	lines.append("-N,Open")
	lines.append("-B,0")
	for y in Const_.FIELD_H:
		lines.append("-R,%2d,%s" % [y, ".".repeat(Const_.FIELD_W)])
	for p in Const_.PLAYER_COUNT:
		lines.append("-S,%d,%d,0,%d" % [p, p, p % 2])
	for i in Const_.POWERUP_COUNT:
		lines.append("-P,%2d, 0,0, 0, 0,x" % i)
	var s: Scheme_ = Scheme_.new()
	s.parse_text("\n".join(lines), "<open>")
	assert(s.ok(), "open scheme must parse: %s" % s.error())

	var slots := []
	for i in count:
		slots.append({"slot": i, "team": i % 2})
	var sim: Sim_ = Sim_.new()
	sim.stats = stats
	sim.setup(s, slots, 1)
	return sim
