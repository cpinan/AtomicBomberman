# The .SCH parser against every scheme the original ships.
#
# All 67, not one. A parser written against a single file is a parser written
# against a single file, and this format has a real variant in it: 31 of the 67
# omit the -S team field entirely, which is the case fpc_atomic crashed on until
# its 0.11006.
#
# Also covers the malformed inputs, because a parser that only ever sees good
# data has no proven failure behaviour — and the one thing worse than refusing a
# valid scheme is silently accepting a corrupt one.
extends SceneTree

const T_ := preload("res://tests/t.gd")
const Const_ := preload("res://scripts/core/const.gd")
const Types_ := preload("res://scripts/core/types.gd")
const Scheme_ := preload("res://scripts/core/scheme.gd")
const DataPath_ := preload("res://tests/data_path.gd")

# Surveyed from the shipped files. If a future disc image differs, the test
# says so rather than the port quietly behaving differently.
const EXPECTED_FILES := 67
const EXPECTED_VERSION := 2
const VALID_DENSITIES := [90, 95, 100]

# Hand-checked from SCHEMES/BASIC.SCH.
const BASIC_NAME := "Just the BASIC SET! (10)"
const BASIC_DENSITY := 90
const BASIC_ROW_0 := ":::::::::::::::"
const BASIC_ROW_1 := ":#:#:#:#:#:#:#:"

# The six schemes whose ten start slots land on fewer than ten cells, mapped to
# how many distinct cells they use. Every scheme must declare all ten slots even
# when it was authored for fewer players, so the spare slots wrap onto cells
# already in use — the -N names say so outright:
#
#   4CORNERS  "FORTIFIED (4 ONLY)"   4 cells, slots 4..9 stack onto them
#   CHAIN     "CHAIN LINKS (4)"      4 cells
#   CHASE     "VERY EVIL (4 ONLY)"   4 cells
#   CONFUSED  "CUNFUSED? (10)"       1 cell  — all ten players on one square
#   DIAMOND   "UNCUT (9)"            9 cells, slot 9 doubles up
#   ROOMMATE  "TWO'S A CROWD (10)"   5 cells, two players each
const STACKED_STARTS := {
	"4CORNERS.SCH": 4,
	"CHAIN.SCH": 4,
	"CHASE.SCH": 4,
	"CONFUSED.SCH": 1,
	"DIAMOND.SCH": 9,
	"ROOMMATE.SCH": 5,
}

# The 31 files that omit the team field on every -S line.
const TEAMLESS := [
	"ALLEYS.SCH", "ALLEYS2.SCH", "ANTFARM.SCH", "BOXED.SCH", "BREAKOUT.SCH",
	"BUNCH.SCH", "CASTLE.SCH", "CASTLE2.SCH", "CHAIN.SCH", "CHECKERS.SCH",
	"CLEARING.SCH", "CONFUSED.SCH", "CUBIC.SCH", "CUTTER.SCH", "CUTTHROT.SCH",
	"DOME.SCH", "FAIR.SCH", "FARGO.SCH", "HAPPY.SCH", "JAIL.SCH",
	"NEIGHBOR.SCH", "NEIL.SCH", "OBSTACLE.SCH", "PATTERN.SCH", "RACER1.SCH",
	"SPIRAL.SCH", "SPREAD.SCH", "THE_RIM.SCH", "THISTHAT.SCH", "TIGHT.SCH",
	"X.SCH",
]


func _init() -> void:
	var t := T_.new("scheme")

	# The synthetic cases run with or without the disc, so a machine that has
	# no copy of the game still gets the parser tested.
	_test_malformed(t)
	_test_teamless_synthetic(t)

	if not DataPath_.available():
		t.note(DataPath_.explain_missing())
		t.note("skipping the 67-file sweep; synthetic cases still ran")
		quit(t.finish())
		return

	_test_all_shipped(t)
	quit(t.finish())


func _test_all_shipped(t: T_) -> void:
	var dir := DirAccess.open(DataPath_.schemes())
	if dir == null:
		t.ok(false, "cannot open %s" % DataPath_.schemes())
		return

	var names: Array[String] = []
	for f in dir.get_files():
		if f.to_upper().ends_with(".SCH"):
			names.append(f)
	names.sort()

	t.eq(names.size(), EXPECTED_FILES, "number of shipped scheme files")

	var teamless_found: Array[String] = []
	var stacked_found := {}
	var densities := {}
	var parsed := 0

	for name in names:
		var s: Scheme_ = Scheme_.new()
		s.parse_file(DataPath_.schemes().path_join(name))
		if not t.ok(s.ok(), "%s parses (%s)" % [name, s.error()]):
			continue
		parsed += 1

		# Structure. Every shipped file must satisfy all of this; a single
		# exception would mean the format has a variant we have not modelled.
		t.eq(s.version, EXPECTED_VERSION, "%s version" % name)
		t.ok(not s.name.is_empty(), "%s has a name" % name)
		t.ok(VALID_DENSITIES.has(s.density),
			"%s density %d is one of %s" % [name, s.density, VALID_DENSITIES])
		densities[s.density] = int(densities.get(s.density, 0)) + 1

		t.eq(s.grid.size(), Const_.FIELD_H, "%s row count" % name)
		var grid_ok := true
		for y in Const_.FIELD_H:
			if s.grid[y] == null or (s.grid[y] as Array).size() != Const_.FIELD_W:
				grid_ok = false
				break
		t.ok(grid_ok, "%s every row is %d cells" % [name, Const_.FIELD_W])

		t.eq(s.starts.size(), Const_.PLAYER_COUNT, "%s start count" % name)
		var starts_ok := true
		for p in Const_.PLAYER_COUNT:
			var st: Dictionary = s.starts[p]
			if st == null:
				starts_ok = false
				break
			# A start position must be somewhere a player can stand. A solid
			# cell there would trap them from tick zero.
			if s.cell(st["x"], st["y"]) == Types_.Brick.SOLID:
				t.ok(false, "%s player %d starts on a solid cell (%d, %d)"
					% [name, p, st["x"], st["y"]])
		t.ok(starts_ok, "%s all 10 starts present" % name)

		# Shared start cells are legal — see scheme.gd's _parse_start. Collect
		# rather than assert, and check the exact set afterwards.
		if not s.stacked_starts().is_empty():
			stacked_found[name] = s.distinct_start_cells()

		t.eq(s.powerups.size(), Const_.POWERUP_COUNT, "%s powerup count" % name)
		var pu_ok := true
		for p in Const_.POWERUP_COUNT:
			if s.powerups[p] == null:
				pu_ok = false
				break
		t.ok(pu_ok, "%s all 13 powerups present" % name)

		if s.teams_unset():
			teamless_found.append(name)

		# to_text() must survive a round trip, because the server hands a
		# scheme to a browser as text rather than as a filename. A field lost
		# here is a field every networked client plays without.
		var again: Scheme_ = Scheme_.new()
		if t.ok(again.parse_text(s.to_text(), "<round trip of %s>" % name),
				"%s round-trips through to_text (%s)" % [name, again.error()]):
			t.eq(again.name, s.name, "%s name survives" % name)
			t.eq(again.density, s.density, "%s density survives" % name)
			t.eq(again.version, s.version, "%s version survives" % name)
			t.eq(again.to_ascii(), s.to_ascii(), "%s grid survives" % name)
			t.eq(again.starts, s.starts, "%s starts survive" % name)
			t.eq(again.powerups, s.powerups, "%s powerups survive" % name)
			# A scheme with no team data must not gain any.
			t.eq(again.teams_unset(), s.teams_unset(),
				"%s keeps its team-data status" % name)

	# The team-field variant is the trap this suite exists for, so assert the
	# exact set rather than merely counting.
	teamless_found.sort()
	var expected_teamless := TEAMLESS.duplicate()
	expected_teamless.sort()
	t.eq(teamless_found, expected_teamless,
		"the set of schemes with no team data")

	# The six schemes that reuse start cells, and how many distinct cells each
	# lands on. Asserted exactly: these are deliberate authoring decisions, and
	# a parser change that quietly merged or dropped a start slot would show up
	# here as a changed count rather than not at all.
	t.eq(stacked_found, STACKED_STARTS, "schemes that reuse start cells")

	# BASIC.SCH by hand, to prove the values are read and not just shaped.
	var basic: Scheme_ = Scheme_.new()
	basic.parse_file(DataPath_.schemes().path_join("BASIC.SCH"))
	if t.ok(basic.ok(), "BASIC.SCH parses (%s)" % basic.error()):
		t.eq(basic.name, BASIC_NAME, "BASIC.SCH name")
		t.eq(basic.density, BASIC_DENSITY, "BASIC.SCH density")
		var ascii := basic.to_ascii().split("\n")
		t.eq(ascii[0], BASIC_ROW_0, "BASIC.SCH row 0")
		t.eq(ascii[1], BASIC_ROW_1, "BASIC.SCH row 1")
		# Its ten starts, and their teams, straight off the file.
		t.eq(basic.starts[0], {"x": 0, "y": 0, "team": 0}, "BASIC.SCH player 0")
		t.eq(basic.starts[1], {"x": 14, "y": 10, "team": 1}, "BASIC.SCH player 1")
		t.eq(basic.starts[4], {"x": 6, "y": 4, "team": 0}, "BASIC.SCH player 4")
		t.ok(not basic.teams_unset(), "BASIC.SCH does declare teams")
		# All-default powerup table.
		t.eq(basic.powerups[Types_.PowerUp.BOMB],
			{"born_with": 0, "has_override": false, "override": 0, "forbidden": false},
			"BASIC.SCH bomb powerup row")
		# The classic pillar grid: solids on the five odd rows at the seven odd
		# columns, 5 * 7 = 35, and every other cell a brick. No blanks at all,
		# which is what -B,90 then thins out at round start.
		t.eq(basic.count_of(Types_.Brick.SOLID), 35, "BASIC.SCH solid count")
		t.eq(basic.count_of(Types_.Brick.BLANK), 0, "BASIC.SCH blank count")
		t.eq(basic.count_of(Types_.Brick.BRICK),
			Const_.FIELD_W * Const_.FIELD_H - 35, "BASIC.SCH brick count")
		t.eq(basic.count_of(Types_.Brick.SOLID)
			+ basic.count_of(Types_.Brick.BRICK)
			+ basic.count_of(Types_.Brick.BLANK),
			Const_.FIELD_W * Const_.FIELD_H, "BASIC.SCH cells account for 165")

	t.note("%d/%d schemes parsed, %d with no team data" %
		[parsed, names.size(), teamless_found.size()])
	var dens_summary := PackedStringArray()
	for d in VALID_DENSITIES:
		dens_summary.append("%d%%: %d" % [d, densities.get(d, 0)])
	t.note("densities — " + ", ".join(dens_summary))


# A four-field -S line must yield TEAM_UNSET, not a guessed team. Team is real
# per-scheme data: 77 of the 360 team-bearing lines in the shipped files break
# player-index parity, so inferring it would be wrong 21% of the time.
func _test_teamless_synthetic(t: T_) -> void:
	var s: Scheme_ = Scheme_.new()
	s.parse_text(_synth({"teams": false}), "<teamless>")
	if not t.ok(s.ok(), "synthetic teamless scheme parses (%s)" % s.error()):
		return
	t.eq(s.starts[0]["team"], Types_.TEAM_UNSET, "missing team is TEAM_UNSET")
	t.ok(s.teams_unset(), "teams_unset() true when no line declares a team")

	var withteams: Scheme_ = Scheme_.new()
	withteams.parse_text(_synth({"teams": true}), "<teams>")
	if t.ok(withteams.ok(), "synthetic teamed scheme parses (%s)" % withteams.error()):
		t.eq(withteams.starts[1]["team"], 1, "declared team is kept")
		t.ok(not withteams.teams_unset(), "teams_unset() false when declared")


# Malformed inputs must be refused with a located message, not silently
# repaired. Each case mutates one thing away from a known-good scheme.
func _test_malformed(t: T_) -> void:
	var good: Scheme_ = Scheme_.new()
	good.parse_text(_synth({}), "<good>")
	t.ok(good.ok(), "the synthetic baseline itself parses (%s)" % good.error())

	var cases := {
		"a 14-cell row": _synth({"short_row": true}),
		"a 12-row grid": _synth({"extra_row": true}),
		"an unknown cell character": _synth({"bad_char": true}),
		"a duplicate row index": _synth({"dup_row": true}),
		"version 3": _synth({"version": 3}),
		"density 101": _synth({"density": 101}),
		"a missing row": _synth({"drop_row": true}),
		"a missing player": _synth({"drop_start": true}),
		"a missing powerup": _synth({"drop_powerup": true}),
		"an off-field start": _synth({"bad_start": true}),
		"team 2": _synth({"bad_team": true}),
		"a two-field -S line": _synth({"short_start": true}),
		"a three-field -P line": _synth({"short_powerup": true}),
	}
	for what in cases:
		var s: Scheme_ = Scheme_.new()
		s.parse_text(cases[what], "<%s>" % what)
		if t.ok(not s.ok(), "rejects %s" % what):
			t.ok(not s.error().is_empty(), "rejection of %s carries a reason" % what)

	# The inverse of a rejection case: a scheme that stacks all ten players on
	# one cell must be ACCEPTED, because CONFUSED.SCH does exactly that.
	var stacked: Scheme_ = Scheme_.new()
	stacked.parse_text(_synth({"all_same_start": true}), "<stacked>")
	if t.ok(stacked.ok(), "accepts ten players on one cell (%s)" % stacked.error()):
		t.eq(stacked.distinct_start_cells(), 1, "ten stacked starts is one cell")
		t.eq(stacked.stacked_starts().size(), 1, "one cell reported as stacked")

	# An unknown directive is a warning, not a failure: a later format revision
	# could add one, and refusing would make the port fail on data the original
	# would have loaded.
	var future: Scheme_ = Scheme_.new()
	future.parse_text(_synth({"unknown_directive": true}), "<future>")
	t.ok(future.ok(), "an unknown directive does not fail the parse")
	t.ok(future.warnings.size() > 0, "an unknown directive is warned about")


# Build a scheme file in the original's format. Options mutate exactly one
# thing, so a rejection can only be caused by the thing under test.
func _synth(opt: Dictionary) -> String:
	var out := PackedStringArray()
	out.append("; synthetic scheme for tests")
	out.append("")
	out.append("-V,%d" % opt.get("version", 2))
	out.append("-N,Synthetic (10)")
	out.append("-B,%d" % opt.get("density", 90))

	var rows := Const_.FIELD_H
	if opt.get("drop_row", false):
		rows -= 1
	for y in rows:
		# All blank, so any start position is legal unless a case says not.
		var cells := ".".repeat(Const_.FIELD_W)
		if y == 0 and opt.get("short_row", false):
			cells = ".".repeat(Const_.FIELD_W - 1)
		if y == 0 and opt.get("bad_char", false):
			cells = "?" + ".".repeat(Const_.FIELD_W - 1)
		out.append("-R,%2d,%s" % [y, cells])
	if opt.get("extra_row", false):
		out.append("-R,%2d,%s" % [Const_.FIELD_H, ".".repeat(Const_.FIELD_W)])
	if opt.get("dup_row", false):
		out.append("-R, 0,%s" % ".".repeat(Const_.FIELD_W))

	var starts := Const_.PLAYER_COUNT
	if opt.get("drop_start", false):
		starts -= 1
	for p in starts:
		var x: int = 0 if opt.get("all_same_start", false) else p
		var y := 0
		if p == 0 and opt.get("bad_start", false):
			x = Const_.FIELD_W
		if p == 0 and opt.get("short_start", false):
			out.append("-S,0,0")
			continue
		if opt.get("teams", true):
			var team := 2 if (p == 0 and opt.get("bad_team", false)) else p % 2
			out.append("-S,%d,%d,%d,%d" % [p, x, y, team])
		else:
			out.append("-S,%d,%d,%d" % [p, x, y])

	var pus := Const_.POWERUP_COUNT
	if opt.get("drop_powerup", false):
		pus -= 1
	for i in pus:
		if i == 0 and opt.get("short_powerup", false):
			out.append("-P, 0, 0,0")
			continue
		out.append("-P,%2d, 0,0, 0, 0,%s" % [i, Types_.POWERUP_NAMES[i]])

	if opt.get("unknown_directive", false):
		out.append("-Z,something,from,a,later,version")

	return "\n".join(out) + "\n"
