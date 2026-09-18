# The GDScript half of the two-parser rule (tools/README.md). Not a test
# suite — it prints no `Result:` line on purpose, so verify.sh's runner must
# not pick it up as one (see docs/BUGS.md D22 for what happens when a script
# without a Result: line is mistaken for a passing suite).
#
# Parses every shipped .SCH with the exact parser the game uses at runtime
# (scripts/core/scheme.gd) and prints one JSON object, keyed by the same
# upper-cased filename stem tools/schemes.py uses, to stdout. tools/schemes.py
# --compare invokes this and diffs the two readings — the whole point of the
# check is that this side is independent of the Python side's own assumptions
# about the format, so it re-derives everything from Scheme_ itself rather
# than importing any shared table.
#
# Field-for-field with tools/schemes.py's own `schemes[stem]` dict:
#   name, density        straight copies
#   grid                 one string per row. tools/schemes.py encodes a row
#                         by taking CELLS[ch][0] — CELLS maps a source
#                         character to the WORD "solid"/"brick"/"blank", so
#                         it is really the word's first letter, and "brick"
#                         and "blank" both start with 'b'. That looks like an
#                         accident on the Python side (it means --compare
#                         cannot tell a brick apart from blank ground by this
#                         field alone), but this script exists to compare
#                         against what tools/schemes.py actually emits, not
#                         what it should — so this reproduces the same
#                         collision rather than silently fixing it out from
#                         under the diff. Flagged, not fixed, here.
#   starts                [x, y, team] triples, in player order — matches
#                         compare_with_godot()'s own mine_starts reshaping.
extends SceneTree

const Scheme_ := preload("res://scripts/core/scheme.gd")
const Types_ := preload("res://scripts/core/types.gd")
const Const_ := preload("res://scripts/core/const.gd")

## Mirrors tools/schemes.py's CELLS = {"#": SOLID, ":": BRICK, ".": BLANK}
## reduced to its first letter — see the header comment on the collision.
const GRID_LETTER := {
	Types_.Brick.SOLID: "s",
	Types_.Brick.BRICK: "b",
	Types_.Brick.BLANK: "b",
}


func _init() -> void:
	var dir_path := ProjectSettings.globalize_path("res://").path_join(
		"../original-game/SCHEMES").simplify_path()
	var dir := DirAccess.open(dir_path)
	if dir == null:
		printerr("dump_schemes: no SCHEMES directory at ", dir_path)
		print("{}")
		quit(1)
		return

	var names: Array[String] = []
	for f in dir.get_files():
		if f.to_upper().ends_with(".SCH"):
			names.append(f)
	names.sort()

	var out := {}
	for n in names:
		var stem := n.get_basename().to_upper()
		var scheme := Scheme_.new()
		if not scheme.parse_file(dir_path.path_join(n)):
			printerr("dump_schemes: ", stem, ": ", scheme.error())
			continue
		out[stem] = _dump_one(scheme)

	print(JSON.stringify(out))
	quit(0)


func _dump_one(scheme: Scheme_) -> Dictionary:
	var grid: Array = []
	for y in Const_.FIELD_H:
		var row := ""
		for x in Const_.FIELD_W:
			row += GRID_LETTER[scheme.grid[y][x]]
		grid.append(row)

	var starts: Array = []
	for p in Const_.PLAYER_COUNT:
		var s: Dictionary = scheme.starts[p]
		starts.append([s["x"], s["y"], s["team"]])

	return {
		"name": scheme.name,
		"density": scheme.density,
		"grid": grid,
		"starts": starts,
	}
