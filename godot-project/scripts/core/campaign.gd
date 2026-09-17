# The campaigns — the disc's own single-player mode, from its own `.CAM` files.
#
# ---------------------------------------------------------------------------
# WHAT THE DISC SAYS
# ---------------------------------------------------------------------------
# Three files in RES/, and each one says what it is in its own header:
#
#     ; Campaign stage information file.
#     ; Field descriptions:
#     ;	0. campaign name
#     ;	1. levelno
#     ;	2. scheme to use
#     ;	3. number of rovers
#     ;	4. rover speed
#     ;	5. number of ghosts
#     ;	6. ghost speed
#     ;	7. number of AIs
#     ;	8. AI difficulty (0-100) (unused at present)
#
#     -C,Just One Ghost,           1,basic,    0,  0, 1,150, 0, 50
#
# SIMPLE.CAM has four stages, GHOSTS.CAM four, CROUTON.CAM nine. `BM95.EXE`
# reads them as `*.cam` (0x45805F) and prints "Total of %u campaigns loaded."
# The scoring is VALUELST's: 1300 gives 250 points for killing an AI, 1310
# gives 15 for a rover and 1320 gives 25 for a ghost, each comment ending
# "(in campaign mode only)".
#
# The art is on the disc too — ALIENS1.ANI carries `rover north/east/south/west`
# and the same four for `ghost`, which is exactly what the binary's two format
# strings `"rover %s"` and `"ghost %s"` (0x45807A, 0x458071) build.
#
# ---------------------------------------------------------------------------
# WHAT THE DISC DOES NOT SAY
# ---------------------------------------------------------------------------
# The eighth field is documented as unused, and it is ignored here too. Beyond
# the counts and speeds, how a rover or a ghost BEHAVES is two resources —
# VALUELST 1200 ("chance that a ghost or rover will change directions at an
# intersection", 1-in-3) and 1205 ("chance that the direction change will NOT
# towards a human", 1-in-3) — and nothing else. scripts/sim/creature.gd says
# what it does with that and what it had to decide for itself.
extends RefCounted

const Const_ := preload("res://scripts/core/const.gd")

## One stage: everything a round needs beyond the scheme's own contents.
class Stage extends RefCounted:
	var name: String = ""
	var level: int = 0
	var scheme: String = ""
	var rovers: int = 0
	var rover_speed: int = 0
	var ghosts: int = 0
	var ghost_speed: int = 0
	var ais: int = 0
	## Field 8. The file's own comment says "(unused at present)", so it is
	## carried and not read.
	var difficulty: int = 0

	func summary() -> String:
		return "%s — level %d, %s, %d rovers, %d ghosts, %d AI" % [
			name, level, scheme, rovers, ghosts, ais]


var name: String = ""
var stages: Array[Stage] = []
var error: String = ""


## Parse one `.CAM` file's text. Returns false and sets `error` if nothing in
## it parsed — a file with no stages is not a campaign.
func parse_text(text: String, from_name: String = "") -> bool:
	name = from_name
	stages = []
	error = ""
	for raw in text.split("\n"):
		var line := raw.strip_edges()
		if line.is_empty() or line.begins_with(";"):
			continue
		if not line.begins_with("-C,"):
			continue
		var parts := line.substr(3).split(",")
		if parts.size() < 8:
			error = "a -C row with %d fields, and a stage needs 8" % parts.size()
			return false
		var stage := Stage.new()
		stage.name = parts[0].strip_edges()
		stage.level = _int(parts[1])
		stage.scheme = parts[2].strip_edges().to_upper()
		stage.rovers = _int(parts[3])
		stage.rover_speed = _int(parts[4])
		stage.ghosts = _int(parts[5])
		stage.ghost_speed = _int(parts[6])
		stage.ais = _int(parts[7])
		if parts.size() > 8:
			stage.difficulty = _int(parts[8])
		stages.append(stage)
	if stages.is_empty():
		error = "no -C rows: this is not a campaign file"
		return false
	# The campaign's own name is the first stage's file name, not a field: the
	# header calls field 0 "campaign name" but every row carries a different
	# one, so they are STAGE names and the campaign is the file.
	return true


func size() -> int:
	return stages.size()


func stage_at(index: int) -> Stage:
	if index < 0 or index >= stages.size():
		return null
	return stages[index]


static func _int(text: String) -> int:
	return int(text.strip_edges())


## What a kill is worth. VALUELST 1300/1310/1320, whose comments all end
## "(in campaign mode only)".
static func score_for(kind: int, values: Dictionary) -> int:
	match kind:
		Kind.AI:
			return int(values.get(Const_.Res.SCORE_AI, 250))
		Kind.ROVER:
			return int(values.get(Const_.Res.SCORE_ROVER, 15))
		Kind.GHOST:
			return int(values.get(Const_.Res.SCORE_GHOST, 25))
	return 0


enum Kind { AI, ROVER, GHOST }

## What a stage is doing right now.
enum Outcome { RUNNING, CLEARED, LOST }


## The stage rule, as a function of what is left alive.
##
## A stage is CLEARED when everything the `.CAM` row put on the field is dead —
## every rover, every ghost, every AI — and LOST when the player is. There is
## one life: the disc says nothing about continues, and a campaign that cannot
## be lost is not one.
##
## Pure, because the alternative is a rule you can only test by playing.
static func outcome_of(player_alive: bool, creatures_left: int,
		bots_left: int) -> int:
	if not player_alive:
		return Outcome.LOST
	if creatures_left <= 0 and bots_left <= 0:
		return Outcome.CLEARED
	return Outcome.RUNNING
