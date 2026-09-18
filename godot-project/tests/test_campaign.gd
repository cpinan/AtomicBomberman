# Campaign mode — the disc's own single-player mode, out of its own files.
#
# Three `.CAM` files describe seventeen stages between them; VALUELST 1300,
# 1310 and 1320 score a kill; 1200 and 1205 govern how a rover or a ghost picks
# its next direction; and ALIENS1.ANI carries the eight sequences the binary
# builds from "rover %s" and "ghost %s".
#
# What is NOT on the disc is what the two creatures actually DO — a ghost
# passing through walls, both killing on contact, both dying to flame. Those
# are this port's decisions, listed in scripts/sim/creature.gd, and they are
# asserted here as decisions rather than as findings.
extends SceneTree

const T_ := preload("res://tests/t.gd")
const Const_ := preload("res://scripts/core/const.gd")
const Types_ := preload("res://scripts/core/types.gd")
const Values_ := preload("res://scripts/core/values.gd")
const Scheme_ := preload("res://scripts/core/scheme.gd")
const Field_ := preload("res://scripts/sim/field.gd")
const Sim_ := preload("res://scripts/sim/sim.gd")
const Player_ := preload("res://scripts/sim/player.gd")
const Creature_ := preload("res://scripts/sim/creature.gd")
const Campaign_ := preload("res://scripts/core/campaign.gd")
const Pack_ := preload("res://scripts/render/pack.gd")


func _init() -> void:
	var t := T_.new("campaign")
	_test_the_files_parse(t)
	_test_the_disc_carries_them(t)
	_test_scoring_resources(t)
	_test_a_rover_walks(t)
	_test_a_ghost_walks_through_walls(t)
	_test_contact_kills(t)
	_test_flame_kills_and_scores(t)
	_test_killing_a_bot_scores_in_campaign(t)
	_test_sequence_names(t)
	_test_the_stage_rule(t)
	quit(t.finish())


# The format is the file's own header: -C, then eight fields.
func _test_the_files_parse(t: T_) -> void:
	var c: Campaign_ = Campaign_.new()
	t.ok(c.parse_text("""; Campaign stage information file.
-C,Just One Ghost,           1,basic,    0,  0, 1,150, 0, 50
-C,One Rover & Two Dudes,    1,clear,    1,500, 0,  0, 2, 50
""", "TEST"), "a campaign parses: %s" % c.error)
	t.eq(c.size(), 2, "two stages")
	var first = c.stage_at(0)
	t.eq(first.name, "Just One Ghost", "field 0 is the stage's name")
	t.eq(first.level, 1, "field 1 is the level")
	t.eq(first.scheme, "BASIC", "field 2 is the scheme, upper-cased")
	t.eq(first.rovers, 0, "field 3: no rovers")
	t.eq(first.ghosts, 1, "field 5: one ghost")
	t.eq(first.ghost_speed, 150, "field 6: at 150 hundredths of a pixel")
	t.eq(first.ais, 0, "field 7: no AI")
	var second = c.stage_at(1)
	t.eq(second.rovers, 1, "the second stage has a rover")
	t.eq(second.rover_speed, 500, "at 500 — faster than any ghost in the file")
	t.eq(second.ais, 2, "and two AI opponents")

	# Comments and blank lines are not stages, and a file of them is not a
	# campaign.
	var empty: Campaign_ = Campaign_.new()
	t.ok(not empty.parse_text("; nothing here\n\n", "EMPTY"),
		"a file with no -C rows is refused")
	t.ok(not empty.error.is_empty(), "and says why: %s" % empty.error)

	# A short row is a broken file, not a stage with defaults. The MESSAGE
	# matters as much as the refusal: without the length check GDScript's own
	# bounds error refuses it too, silently and with nothing to read, so
	# asserting only "false" would not tell the two apart.
	var short: Campaign_ = Campaign_.new()
	t.ok(not short.parse_text("-C,Too Short,1,basic,0,0\n", "SHORT"),
		"a row with too few fields is refused")
	t.ok(short.error.contains("8"),
		"and says how many fields a stage needs: %s" % short.error)


# The three real files, through the asset pack — which is how a browser build
# gets them, there being no RES folder in a browser.
func _test_the_disc_carries_them(t: T_) -> void:
	var pack: Pack_ = Pack_.new()
	if not pack.load_from(Pack_.default_dir()):
		t.note("skipping the disc's own campaigns: no asset pack")
		return
	var names := pack.campaign_names()
	t.eq(names.size(), 3, "three campaigns: %s" % str(names))
	for want in ["SIMPLE", "GHOSTS", "CROUTON"]:
		t.ok(names.has(want), "%s is one of them" % want)

	var counts := {"SIMPLE": 4, "GHOSTS": 4, "CROUTON": 9}
	for name in counts:
		var c: Campaign_ = Campaign_.new()
		t.ok(c.parse_text(pack.campaign_text(name), name),
			"%s parses: %s" % [name, c.error])
		t.eq(c.size(), int(counts[name]),
			"%s has %d stages" % [name, counts[name]])

	# The art the binary names is in the pack too.
	t.ok(pack.has_sheet("aliens1"), "ALIENS1 is packed")
	for word in ["rover", "ghost"]:
		for dir_name in ["north", "east", "south", "west"]:
			t.ok(pack.has_sequence("aliens1", "%s %s" % [word, dir_name]),
				"aliens1 has '%s %s'" % [word, dir_name])


func _test_scoring_resources(t: T_) -> void:
	t.eq(Values_.V[Const_.Res.SCORE_AI], 250, "1300: 250 for an AI")
	t.eq(Values_.V[Const_.Res.SCORE_ROVER], 15, "1310: 15 for a rover")
	t.eq(Values_.V[Const_.Res.SCORE_GHOST], 25, "1320: 25 for a ghost")
	t.eq(Values_.V[Const_.Res.CREATURE_TURN_CHANCE], 3,
		"1200: 1-in-3 to turn at an intersection")
	t.eq(Values_.V[Const_.Res.CREATURE_AWAY_CHANCE], 3,
		"1205: 1-in-3 that the turn is not toward a human")


func _test_a_rover_walks(t: T_) -> void:
	var sim := _open_sim(1)
	sim.players[0].place_at_tile_centre(13, 9)
	var rover = sim.add_creature(Creature_.Kind.ROVER, 3, 3, 400)
	t.eq(sim.creature_count(), 1, "one creature on the field")
	var start := Vector2i(rover.x, rover.y)
	for _i in 30:
		sim.tick()
	t.ok(Vector2i(rover.x, rover.y) != start, "a rover moves on its own")
	t.ok(sim.field.in_bounds(rover.tile_x(), rover.tile_y()),
		"and stays on the field")

	# A rover cannot enter a brick or a wall.
	var walled := _open_sim(1)
	walled.players[0].place_at_tile_centre(13, 9)
	for x in Const_.FIELD_W:
		for y in Const_.FIELD_H:
			if x != 3:
				walled.field.brick[Field_.idx(x, y)] = Types_.Brick.SOLID
	var boxed = walled.add_creature(Creature_.Kind.ROVER, 3, 3, 400)
	for _i in 60:
		walled.tick()
	t.eq(boxed.tile_x(), 3, "a rover kept to the one open column")


func _test_a_ghost_walks_through_walls(t: T_) -> void:
	# THIS IS A PORT DECISION, not something the disc says: a ghost ignores the
	# field. It is why the .CAM files give ghosts the slower speeds and it is
	# the only way the two kinds differ.
	var sim := _open_sim(1)
	sim.players[0].place_at_tile_centre(13, 9)
	for x in Const_.FIELD_W:
		for y in Const_.FIELD_H:
			if not (x == 3 and y == 3):
				sim.field.brick[Field_.idx(x, y)] = Types_.Brick.SOLID
	var ghost = sim.add_creature(Creature_.Kind.GHOST, 3, 3, 400)
	t.ok(ghost.can_enter(sim.field, 4, 3),
		"a ghost may enter a solid cell")
	var rover: Creature_ = Creature_.new()
	rover.kind = Creature_.Kind.ROVER
	t.ok(not rover.can_enter(sim.field, 4, 3), "a rover may not")
	t.ok(not ghost.can_enter(sim.field, -1, 3),
		"but not even a ghost leaves the field")


func _test_contact_kills(t: T_) -> void:
	var sim := _open_sim(1)
	var p: Player_ = sim.players[0]
	p.place_at_tile_centre(5, 5)
	sim.add_creature(Creature_.Kind.GHOST, 5, 5, 100)
	sim.tick()
	t.ok(p.dying, "a creature on your cell kills you")

	# Invulnerable and airborne players are not touchable, the same two
	# exceptions flame makes.
	var safe := _open_sim(1)
	var q: Player_ = safe.players[0]
	q.place_at_tile_centre(5, 5)
	q.invulnerable = 10
	safe.add_creature(Creature_.Kind.GHOST, 5, 5, 100)
	safe.tick()
	t.ok(not q.dying, "an invulnerable player is not caught")


func _test_flame_kills_and_scores(t: T_) -> void:
	var sim := _open_sim(1)
	var p: Player_ = sim.players[0]
	p.place_at_tile_centre(5, 5)
	p.flame_len = 3
	var ghost = sim.add_creature(Creature_.Kind.GHOST, 7, 5, 0)
	sim.place_bomb(p)
	# Walk the bomber out of its own blast so the score is the creature's.
	p.place_at_tile_centre(5, 9)
	for _i in Values_.V[Const_.Res.FUZE_FRAMES] + 2:
		sim.tick()
	t.ok(not ghost.alive, "flame kills a ghost")
	t.eq(sim.round_score[p.slot], Values_.V[Const_.Res.SCORE_GHOST],
		"and the kill scores 1320's 25 points to whoever lit it")
	t.eq(sim.creature_count(), 0, "the field is clear")

	var rover_sim := _open_sim(1)
	var r: Player_ = rover_sim.players[0]
	r.place_at_tile_centre(5, 5)
	r.flame_len = 3
	rover_sim.add_creature(Creature_.Kind.ROVER, 7, 5, 0)
	rover_sim.place_bomb(r)
	r.place_at_tile_centre(5, 9)
	for _i in Values_.V[Const_.Res.FUZE_FRAMES] + 2:
		rover_sim.tick()
	t.eq(rover_sim.round_score[r.slot], Values_.V[Const_.Res.SCORE_ROVER],
		"a rover is worth 1310's 15 instead")


## VALUELST 1300, "250 for killing an AI" — the third of the three campaign
## scoring resources, and the only one that scores a PLAYER kill rather than
## a creature. round_score exists for campaign mode alone (sim.gd's own
## declaration), so it needs a creature on the field to say so — a plain
## multiplayer round must not pay it out, and a bot must not pay itself for
## dying by its own hand either.
func _test_killing_a_bot_scores_in_campaign(t: T_) -> void:
	var sim := _open_sim(2)
	sim.add_bot(1)
	# A creature on the field is this sim's own signal that a round is a
	# campaign one — see the comment on `round_score`.
	sim.add_creature(Creature_.Kind.GHOST, 14, 10, 0)
	sim.players[0].place_at_tile_centre(5, 5)
	sim.kill(sim.players[1], 0)
	t.eq(sim.round_score[0], Values_.V[Const_.Res.SCORE_AI],
		"killing a bot in campaign mode scores 1300's 250")

	# The same kill, with no creature on the field: not campaign mode, and
	# round_score is never read outside it.
	var mp := _open_sim(2)
	mp.add_bot(1)
	mp.kill(mp.players[1], 0)
	t.eq(mp.round_score[0], 0, "no creature on the field, no AI score")

	# A bot dying to its own bomb does not score itself.
	var suicide := _open_sim(2)
	suicide.add_bot(1)
	suicide.add_creature(Creature_.Kind.GHOST, 14, 10, 0)
	suicide.kill(suicide.players[1], 1)
	t.eq(suicide.round_score[1], 0, "a bot's own death is not its own kill")


# The names are the binary's own format strings, "rover %s" and "ghost %s",
# filled in with the compass words ALIENS1.ANI uses.
func _test_sequence_names(t: T_) -> void:
	var c: Creature_ = Creature_.new()
	c.kind = Creature_.Kind.ROVER
	c.facing = Types_.Dir.UP
	t.eq(c.sequence_name(), "rover north", "up is north")
	c.facing = Types_.Dir.RIGHT
	t.eq(c.sequence_name(), "rover east", "right is east")
	c.facing = Types_.Dir.DOWN
	t.eq(c.sequence_name(), "rover south", "down is south")
	c.facing = Types_.Dir.LEFT
	t.eq(c.sequence_name(), "rover west", "left is west")
	c.kind = Creature_.Kind.GHOST
	t.eq(c.sequence_name(), "ghost west", "and a ghost is a ghost")


func _open_sim(count: int) -> Sim_:
	var lines := PackedStringArray()
	lines.append("-V,2")
	lines.append("-N,Campaign fixture (10)")
	lines.append("-B,0")
	for y in Const_.FIELD_H:
		lines.append("-R,%2d,%s" % [y, ".".repeat(Const_.FIELD_W)])
	for p in Const_.PLAYER_COUNT:
		lines.append("-S,%d,%d,%d,%d" % [p, p, p % 9, p % 2])
	for i in Const_.POWERUP_COUNT:
		lines.append("-P,%2d, 0,0, 0, 0,x" % i)
	var s: Scheme_ = Scheme_.new()
	s.parse_text("\n".join(lines), "<campaign>")
	assert(s.ok(), "fixture must parse: %s" % s.error())
	var slots := []
	for i in count:
		slots.append({"slot": i, "team": i % 2})
	var sim: Sim_ = Sim_.new()
	sim.setup(s, slots, 1)
	return sim


# When a stage is over, and which way. A function rather than a branch inside
# the frame loop, so it can be asserted instead of played.
func _test_the_stage_rule(t: T_) -> void:
	t.eq(Campaign_.outcome_of(true, 2, 0), Campaign_.Outcome.RUNNING,
		"two creatures left: still going")
	t.eq(Campaign_.outcome_of(true, 0, 1), Campaign_.Outcome.RUNNING,
		"an AI left: still going")
	t.eq(Campaign_.outcome_of(true, 0, 0), Campaign_.Outcome.CLEARED,
		"nothing left: cleared")
	t.eq(Campaign_.outcome_of(false, 0, 0), Campaign_.Outcome.LOST,
		"the player dead on a cleared field is still a loss — one life")
	t.eq(Campaign_.outcome_of(false, 3, 2), Campaign_.Outcome.LOST,
		"and dying is a loss whatever else is alive")
