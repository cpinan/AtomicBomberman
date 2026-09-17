# Parser for the original's .SCH scheme files.
#
# This is the REAL format, as shipped in the CD's SCHEMES/ folder and written by
# the game's own editor — not the format in AtomBomberman's default.sch, which
# that clone rewrote. Verified against all 67 shipped files: every one is -V,2
# with exactly 11 -R rows of 15 characters, 10 -S lines and 13 -P lines.
#
#   -V,2                            internal version
#   -N,Just the BASIC SET! (10)     display name
#   -B,90                           brick density, 0..100 percent
#   -R, 0,:::::::::::::::           one row; 11 of them, y = 0..10
#   -S,0,0,0,0                      start position: playerno, X, Y [, team]
#   -P, 0, 0,0, 0, 0,an extra bomb  powerup#, bornwith, has_override,
#                                   override_value, forbidden, comment
#
# Two traps, both found by surveying all 67 rather than one:
#
#   1. -S comes in two shapes. 31 of the 67 files omit the team field
#      completely; fpc_atomic crashed on exactly this until its 0.11006. Those
#      lines yield Types.TEAM_UNSET rather than a guessed 0 or 1, because team
#      is genuine per-scheme data — 77 of the 360 team-bearing lines break
#      player-index parity, so parity would be wrong 21% of the time.
#
#   2. -P's last field is a free-text comment. It never contains a comma in the
#      shipped data, but the parser splits off only the first five numeric
#      fields and treats the remainder as the comment, so one that does cannot
#      corrupt the numbers.
class_name Scheme

const Const_ := preload("res://scripts/core/const.gd")
const Types_ := preload("res://scripts/core/types.gd")

## Where the file was read from, for error messages and for the field hash.
var path: String = ""

## Format version from -V. Every shipped file is 2; anything else is refused
## rather than parsed on the assumption it is compatible.
var version: int = 0

## Display name from -N. Often carries the intended player count, e.g.
## "BACK 2 BACK (5)(5)" or "BOXED IN (8 ONLY)".
var name: String = ""

## Brick density percent from -B. The shipped files use 90, 95 and 100.
var density: int = 0

## grid[y][x] -> Types.Brick. Row-major, because that is the order -R gives.
var grid: Array[Array] = []

## Ten entries of {"x": int, "y": int, "team": int}, indexed by player number.
## team is Types.TEAM_UNSET when the file did not say.
var starts: Array[Dictionary] = []

## Thirteen entries indexed by Types.PowerUp, each
## {"born_with": int, "has_override": bool, "override": int, "forbidden": bool}.
var powerups: Array[Dictionary] = []

## Non-fatal observations. A file can be usable and still odd.
var warnings: PackedStringArray = []

var _error: String = ""


## Human-readable reason the last parse failed, or "" if it did not.
func error() -> String:
	return _error


func ok() -> bool:
	return _error.is_empty()


## Parse a .SCH from an absolute filesystem path, returning ok().
##
## The scheme files live outside res:// — they are the user's own copy of the
## game — so this takes a real path rather than a resource path.
##
## These are instance methods rather than static factories on purpose. A static
## factory would have to write `Scheme.new()`, which needs the global class_name
## to resolve, which needs .godot/global_script_class_cache.cfg, which only
## exists after an editor import pass. A headless CI run must not require one,
## so the caller constructs and this parses.
func parse_file(abs_path: String) -> bool:
	path = abs_path
	var f := FileAccess.open(abs_path, FileAccess.READ)
	if f == null:
		_error = "cannot open %s (%s)" % [
			abs_path, error_string(FileAccess.get_open_error())]
		return false
	var text := f.get_as_text()
	f.close()
	_parse(text)
	return ok()


func parse_text(text: String, label: String = "<text>") -> bool:
	path = label
	_parse(text)
	return ok()


func _fail(lineno: int, message: String) -> void:
	# Keep the first failure; later ones are usually its consequence.
	if _error.is_empty():
		_error = "%s:%d: %s" % [path.get_file(), lineno, message]


func _parse(text: String) -> void:
	grid = []
	starts = []
	powerups = []
	warnings = PackedStringArray()

	# Pre-size so a missing directive is a detectable hole rather than a short
	# array that silently reads as valid.
	grid.resize(Const_.FIELD_H)
	starts.resize(Const_.PLAYER_COUNT)
	powerups.resize(Const_.POWERUP_COUNT)

	var seen_rows := {}
	var seen_starts := {}
	var seen_powerups := {}

	var lineno := 0
	for raw in text.split("\n"):
		lineno += 1
		# The files are DOS-encoded and some end with a 0x1A EOF marker.
		var line := raw.replace("\r", "").replace(String.chr(26), "")
		# Everything from a ';' onwards is a comment. The -N and -P text fields
		# never contain one in the shipped data.
		var semi := line.find(";")
		if semi >= 0:
			line = line.substr(0, semi)
		line = line.strip_edges()
		if line.is_empty():
			continue
		if not line.begins_with("-"):
			_fail(lineno, "expected a -X directive, got %s" % line)
			continue

		var comma := line.find(",")
		if comma < 0:
			_fail(lineno, "directive has no fields: %s" % line)
			continue
		var kind := line.substr(0, comma).to_upper()
		var rest := line.substr(comma + 1)

		match kind:
			"-V":
				version = _to_int(rest)
				if version != 2:
					_fail(lineno, "unsupported scheme version %d (expected 2)" % version)
			"-N":
				# Everything after the first comma, verbatim — the name is text
				# and may contain anything except a newline.
				name = rest.strip_edges()
			"-B":
				density = _to_int(rest)
				if density < 0 or density > 100:
					_fail(lineno, "brick density %d is outside 0..100" % density)
			"-R":
				_parse_row(lineno, rest, seen_rows)
			"-S":
				_parse_start(lineno, rest, seen_starts)
			"-P":
				_parse_powerup(lineno, rest, seen_powerups)
			_:
				# An unknown directive is not fatal — a later format revision
				# could add one — but it is recorded rather than swallowed.
				warnings.append("line %d: ignored unknown directive %s" % [lineno, kind])

	if _error.is_empty():
		_check_complete(seen_rows, seen_starts, seen_powerups)


func _parse_row(lineno: int, rest: String, seen: Dictionary) -> void:
	var comma := rest.find(",")
	if comma < 0:
		_fail(lineno, "-R wants an index and a row")
		return
	var y := _to_int(rest.substr(0, comma))
	var cells := rest.substr(comma + 1).strip_edges()

	if y < 0 or y >= Const_.FIELD_H:
		_fail(lineno, "-R row index %d is outside 0..%d" % [y, Const_.FIELD_H - 1])
		return
	if seen.has(y):
		_fail(lineno, "-R row %d defined twice" % y)
		return
	if cells.length() != Const_.FIELD_W:
		_fail(lineno, "-R row %d is %d characters, expected %d"
			% [y, cells.length(), Const_.FIELD_W])
		return

	var row: Array = []
	row.resize(Const_.FIELD_W)
	for x in Const_.FIELD_W:
		var ch := cells[x]
		if not Types_.BRICK_CHARS.has(ch):
			_fail(lineno, "-R row %d column %d: unknown cell character %s" % [y, x, ch])
			return
		row[x] = Types_.BRICK_CHARS[ch]
	grid[y] = row
	seen[y] = true


func _parse_start(lineno: int, rest: String, seen: Dictionary) -> void:
	var f := rest.split(",")
	# Four fields (playerno, x, y) or five (plus team). 31 of the 67 shipped
	# files use the four-field form throughout — see the header comment.
	if f.size() != 3 and f.size() != 4:
		_fail(lineno, "-S wants 3 or 4 fields, got %d" % f.size())
		return

	var player := _to_int(f[0])
	var x := _to_int(f[1])
	var y := _to_int(f[2])
	var team: int = _to_int(f[3]) if f.size() == 4 else Types_.TEAM_UNSET

	if player < 0 or player >= Const_.PLAYER_COUNT:
		_fail(lineno, "-S player %d is outside 0..%d" % [player, Const_.PLAYER_COUNT - 1])
		return
	if seen.has(player):
		_fail(lineno, "-S player %d defined twice" % player)
		return
	# Two players sharing a cell is LEGAL and deliberate. Every scheme must
	# declare all ten slots even when it was designed for fewer, so the spare
	# slots wrap onto cells already in use: "FORTIFIED (4 ONLY)" has four
	# cells, "TWO'S A CROWD (10)" has five with two players each, and
	# "CUNFUSED? (10)" starts all ten players on one cell. Six of the 67
	# shipped schemes do this. Rejecting it would refuse valid data.
	#
	# What the original does when two ACTIVE players occupy one cell at tick
	# zero is a separate question, and an open one — docs/BUGS.md.
	# Scheme files use plain coordinates; only VALUELST's defaults and the
	# EXTRA files use the negative-wraps convention. Applying it here would
	# silently rescue a genuinely corrupt file, so refuse instead.
	if x < 0 or x >= Const_.FIELD_W or y < 0 or y >= Const_.FIELD_H:
		_fail(lineno, "-S player %d start (%d, %d) is off the field" % [player, x, y])
		return
	if f.size() == 4 and team != 0 and team != 1:
		_fail(lineno, "-S player %d team %d is neither 0 nor 1" % [player, team])
		return

	starts[player] = {"x": x, "y": y, "team": team}
	seen[player] = true


func _parse_powerup(lineno: int, rest: String, seen: Dictionary) -> void:
	var f := rest.split(",")
	# Five numeric fields then a free-text comment. Split off exactly five so a
	# comma inside the comment cannot shift the numbers.
	if f.size() < 5:
		_fail(lineno, "-P wants 5 numeric fields and a comment, got %d fields" % f.size())
		return

	var which := _to_int(f[0])
	if which < 0 or which >= Const_.POWERUP_COUNT:
		_fail(lineno, "-P powerup %d is outside 0..%d" % [which, Const_.POWERUP_COUNT - 1])
		return
	if seen.has(which):
		_fail(lineno, "-P powerup %d defined twice" % which)
		return

	powerups[which] = {
		"born_with": _to_int(f[1]),
		"has_override": _to_int(f[2]) != 0,
		"override": _to_int(f[3]),
		"forbidden": _to_int(f[4]) != 0,
	}
	seen[which] = true


func _check_complete(rows: Dictionary, starts_seen: Dictionary,
		powerups_seen: Dictionary) -> void:
	if version == 0:
		_fail(0, "no -V directive")
	if name.is_empty():
		_fail(0, "no -N directive")
	for y in Const_.FIELD_H:
		if not rows.has(y):
			_fail(0, "missing -R row %d" % y)
			return
	for p in Const_.PLAYER_COUNT:
		if not starts_seen.has(p):
			_fail(0, "missing -S player %d" % p)
			return
	for p in Const_.POWERUP_COUNT:
		if not powerups_seen.has(p):
			_fail(0, "missing -P powerup %d" % p)
			return


## True when no -S line carried a team, which is how the 31 free-for-all
## schemes present. Teamplay needs an answer this file does not have.
func teams_unset() -> bool:
	for s in starts:
		if s != null and s.get("team", Types_.TEAM_UNSET) != Types_.TEAM_UNSET:
			return false
	return true


## Start cells occupied by more than one player slot, as {Vector2i: [slots]}.
## Empty for 61 of the 67 shipped schemes; see _parse_start on why the other
## six are not an error.
func stacked_starts() -> Dictionary:
	var by_cell := {}
	for p in starts.size():
		var st: Dictionary = starts[p]
		if st == null:
			continue
		var key := Vector2i(st["x"], st["y"])
		if not by_cell.has(key):
			by_cell[key] = []
		(by_cell[key] as Array).append(p)
	var stacked := {}
	for key in by_cell:
		if (by_cell[key] as Array).size() > 1:
			stacked[key] = by_cell[key]
	return stacked


## How many distinct cells the ten start slots land on. A scheme authored for
## fewer than ten players has fewer than ten.
func distinct_start_cells() -> int:
	var cells := {}
	for st in starts:
		if st != null:
			cells[Vector2i(st["x"], st["y"])] = true
	return cells.size()


func cell(x: int, y: int) -> int:
	return grid[y][x]


## Count of one cell kind, for tests and for sanity-checking a density.
func count_of(kind: int) -> int:
	var n := 0
	for y in Const_.FIELD_H:
		for x in Const_.FIELD_W:
			if grid[y][x] == kind:
				n += 1
	return n


## The grid as the original's own comments draw it, for test failure output.
func to_ascii() -> String:
	var chars := {Types_.Brick.SOLID: "#", Types_.Brick.BRICK: ":",
		Types_.Brick.BLANK: "."}
	var out := PackedStringArray()
	for y in Const_.FIELD_H:
		var row := ""
		for x in Const_.FIELD_W:
			row += chars[grid[y][x]]
		out.append(row)
	return "\n".join(out)


## Re-emit this scheme in the original's own format.
##
## Needed because the server hands a scheme to its clients as TEXT: a browser
## has no copy of the CD's SCHEMES folder to read, and naming a file the client
## cannot open would make every join fail.
##
## A scheme that declared no team is re-emitted WITHOUT one, so the round trip
## does not invent data the original file did not have — 31 of the 67 shipped
## schemes are in that case. tests/test_scheme.gd round-trips all 67 and
## compares field for field.
func to_text() -> String:
	var chars := {Types_.Brick.SOLID: "#", Types_.Brick.BRICK: ":",
		Types_.Brick.BLANK: "."}
	var lines := PackedStringArray()
	lines.append("-V,%d" % version)
	lines.append("-N,%s" % name)
	lines.append("-B,%d" % density)
	for y in Const_.FIELD_H:
		var row := ""
		for x in Const_.FIELD_W:
			row += chars[cell(x, y)]
		lines.append("-R,%2d,%s" % [y, row])
	for p in Const_.PLAYER_COUNT:
		var st: Dictionary = starts[p]
		if int(st["team"]) == Types_.TEAM_UNSET:
			lines.append("-S,%d,%d,%d" % [p, st["x"], st["y"]])
		else:
			lines.append("-S,%d,%d,%d,%d" % [p, st["x"], st["y"], st["team"]])
	for i in Const_.POWERUP_COUNT:
		var row2: Dictionary = powerups[i]
		lines.append("-P,%2d, %d,%d, %d, %d,x" % [i, row2["born_with"],
			1 if row2["has_override"] else 0, row2["override"],
			1 if row2["forbidden"] else 0])
	return "\n".join(lines)


static func _to_int(s: String) -> int:
	return int(s.strip_edges())
