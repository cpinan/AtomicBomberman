# The generated level-specials table.
#
# These coordinates are the whole reason Phase 8 is wiring rather than guessing,
# so they are asserted against counts and positions read by hand out of the
# original's EXTRA*.RES files — and against the geometric properties the
# features must have to work at all: a warp ring that closes, conveyor cells
# that form a loop, arrows that do not stack.
extends SceneTree

const T_ := preload("res://tests/t.gd")
const Const_ := preload("res://scripts/core/const.gd")
const Types_ := preload("res://scripts/core/types.gd")
const Values_ := preload("res://scripts/core/values.gd")
const Extras_ := preload("res://scripts/core/extras.gd")

# Levels with a specials file, and what it holds. Hand-counted.
const EXPECT := {
	2: {"arrows": 12, "conveyors": 0, "tramps": 0, "random": 0, "warps": 0},
	3: {"arrows": 44, "conveyors": 0, "tramps": 0, "random": 0, "warps": 0},
	4: {"arrows": 0, "conveyors": 0, "tramps": 0, "random": 0, "warps": 4},
	9: {"arrows": 0, "conveyors": 0, "tramps": 4, "random": 4, "warps": 0},
	10: {"arrows": 0, "conveyors": 32, "tramps": 0, "random": 0, "warps": 0},
}

# The four fixed trampolines on Deep Forest Green, with the file's negative
# coordinates already resolved: -3 becomes 12 across and 8 down.
const LEVEL9_TRAMPS := [Vector2i(2, 2), Vector2i(12, 2), Vector2i(2, 8), Vector2i(12, 8)]

# The Coal Mine's four gates and the ring they form. Top-left, top-right,
# bottom-right, bottom-left; the ring runs TL -> BL -> BR -> TR, which is
# counter-clockwise and matches how fpc_atomic describes the original.
const LEVEL4_GATES := {
	0: Vector2i(2, 2),
	1: Vector2i(12, 2),
	2: Vector2i(12, 8),
	3: Vector2i(2, 8),
}
const LEVEL4_RING := [0, 3, 2, 1]


func _init() -> void:
	var t := T_.new("extras")

	# 1. Exactly the five levels that ship a specials file, and no others.
	var levels: Array = Extras_.LEVELS.keys()
	levels.sort()
	var expected: Array = EXPECT.keys()
	expected.sort()
	t.eq(levels, expected, "levels with a specials file")

	# 2. Counts.
	for level in expected:
		var d: Dictionary = Extras_.of_level(level)
		var e: Dictionary = EXPECT[level]
		t.eq((d["arrows"] as Array).size(), e["arrows"], "level %d arrows" % level)
		t.eq((d["conveyors"] as Array).size(), e["conveyors"],
			"level %d conveyors" % level)
		t.eq((d["tramps"] as Array).size(), e["tramps"], "level %d fixed tramps" % level)
		t.eq(d["random_tramps"], e["random"], "level %d random tramps" % level)
		t.eq((d["warps"] as Array).size(), e["warps"], "level %d warps" % level)

	# 3. Levels without a file get an empty, non-null set — a caller must not
	# have to special-case them.
	for level in 11:
		if EXPECT.has(level):
			continue
		var d: Dictionary = Extras_.of_level(level)
		t.eq((d["arrows"] as Array).size(), 0, "level %d has no arrows" % level)
		t.eq((d["warps"] as Array).size(), 0, "level %d has no warps" % level)
		t.eq(d["random_tramps"], 0, "level %d has no random tramps" % level)

	# 4. Every cell of every feature is on the field, and no two features of
	# the same kind stack on one cell.
	for level in expected:
		var d: Dictionary = Extras_.of_level(level)
		for key in ["arrows", "conveyors", "tramps"]:
			var seen := {}
			for item in d[key] as Array:
				var p := Vector2i(item["x"], item["y"])
				t.ok(p.x >= 0 and p.x < Const_.FIELD_W
					and p.y >= 0 and p.y < Const_.FIELD_H,
					"level %d %s cell %s is on the field" % [level, key, p])
				t.ok(not seen.has(p),
					"level %d has one %s at %s" % [level, key, p])
				seen[p] = true

	# 5. Directions are resolved names, not the file's letters.
	for level in expected:
		var d: Dictionary = Extras_.of_level(level)
		for key in ["arrows", "conveyors"]:
			for item in d[key] as Array:
				t.ok(Types_.DIR_NAMES.has(item["dir"]),
					"level %d %s direction %s is known" % [level, key, item["dir"]])

	# 6. Ancient Egypt is symmetric: 11 arrows per heading. Worth asserting
	# because an off-by-one in the parser would show up as an uneven split
	# rather than as a wrong total.
	var per_dir := {}
	for a in Extras_.of_level(3)["arrows"] as Array:
		per_dir[a["dir"]] = int(per_dir.get(a["dir"], 0)) + 1
	for dir_name in ["up", "down", "left", "right"]:
		t.eq(per_dir.get(dir_name, 0), 11, "level 3 arrows heading %s" % dir_name)

	# 7. The Coal Mine's warp gates and their ring.
	var warps: Array = Extras_.of_level(4)["warps"]
	var by_gate := {}
	for w in warps:
		by_gate[w["gate"]] = w
	t.eq(by_gate.size(), 4, "level 4 has four distinct gate numbers")
	for gate in LEVEL4_GATES:
		if t.ok(by_gate.has(gate), "level 4 has gate %d" % gate):
			var w: Dictionary = by_gate[gate]
			t.eq(Vector2i(w["x"], w["y"]), LEVEL4_GATES[gate],
				"level 4 gate %d position" % gate)
	# Walk the ring from gate 0 and prove it visits all four and closes. A ring
	# that did not close would strand a player mid-teleport.
	var walk: Array[int] = []
	var gate: int = 0
	while not walk.has(gate) and by_gate.has(gate):
		walk.append(gate)
		gate = by_gate[gate]["to"]
	t.eq(walk, LEVEL4_RING, "level 4 warp ring order")
	t.eq(gate, 0, "level 4 warp ring closes back to gate 0")

	# 8. Deep Forest Green's four authored trampolines, plus four random ones,
	# is the 8 that fpc_atomic guessed. Assert both halves.
	var tramps: Array[Vector2i] = []
	for tr in Extras_.of_level(9)["tramps"] as Array:
		tramps.append(Vector2i(tr["x"], tr["y"]))
	tramps.sort()
	var want_tramps := LEVEL9_TRAMPS.duplicate()
	want_tramps.sort()
	t.eq(tramps, want_tramps, "level 9 fixed trampoline positions")
	t.eq((Extras_.of_level(9)["tramps"] as Array).size()
		+ int(Extras_.of_level(9)["random_tramps"]), 8,
		"level 9 has 8 trampolines in total")

	# 9. Inner City Trash's conveyors form one closed loop: two horizontal
	# runs and two vertical, each cell carrying along its run.
	var conv: Array = Extras_.of_level(10)["conveyors"]
	var counts := {}
	for c in conv:
		counts[c["dir"]] = int(counts.get(c["dir"], 0)) + 1
	t.eq(counts.get("right", 0), 10, "level 10 rightward conveyor cells")
	t.eq(counts.get("left", 0), 10, "level 10 leftward conveyor cells")
	t.eq(counts.get("up", 0), 6, "level 10 upward conveyor cells")
	t.eq(counts.get("down", 0), 6, "level 10 downward conveyor cells")
	# Each run is contiguous, which is what makes it a belt rather than 32
	# unrelated cells.
	_check_run(t, conv, "right", true, 2, 2, 11)
	_check_run(t, conv, "left", true, 8, 3, 12)
	_check_run(t, conv, "up", false, 2, 3, 8)
	_check_run(t, conv, "down", false, 12, 2, 7)

	# 10. The features the EXTRA files do NOT carry come from VALUELST, and the
	# levels they apply to must line up with the levels that have no file.
	# Haunted House regenerates tiles and has no EXTRA file; the Hockey Rink
	# has ice AND arrows.
	t.eq(Values_.V[Const_.Res.REGEN_INTERVAL_BASE + 7], 4,
		"level 7 regenerates tiles every 4s and ships no EXTRA file")
	t.ok(not Extras_.LEVELS.has(7), "level 7 has no EXTRA file")
	t.eq(Values_.V[Const_.Res.ICE_DELAY_BASE + 2], 250,
		"level 2 has ice as well as arrows")
	t.ok(Extras_.LEVELS.has(2), "level 2 does have an EXTRA file")

	t.note("levels with specials: %s" % str(levels))
	quit(t.finish())


# Assert that all cells of one direction sit on a single row (or column) and
# cover a contiguous span, which is what makes a belt a belt.
func _check_run(t: T_, cells: Array, dir_name: String, horizontal: bool,
		fixed: int, from: int, to: int) -> void:
	var along: Array[int] = []
	for c in cells:
		if c["dir"] != dir_name:
			continue
		var cross: int = c["y"] if horizontal else c["x"]
		if not t.eq(cross, fixed, "level 10 %s cells share %s %d"
				% [dir_name, "row" if horizontal else "column", fixed]):
			return
		along.append(c["x"] if horizontal else c["y"])
	along.sort()
	var want: Array[int] = []
	for v in range(from, to + 1):
		want.append(v)
	t.eq(along, want, "level 10 %s run is contiguous %d..%d" % [dir_name, from, to])
