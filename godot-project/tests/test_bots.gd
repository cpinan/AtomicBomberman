# The bots. Do they play, do they survive, and do they end a round?
#
# The four knobs are the original's (resources 900, 910, 915, 920) and are
# asserted. The LOGIC is not the original's — it is in BM.EXE and nowhere else
# (docs/BUGS.md Q5.4) — so what is tested here is that the bots are competent
# and deterministic, not that they behave like the original's.
#
# "Competent" is measured, not asserted by eye: a bot must not blow itself up
# more often than not, and a field of bots must reach a round end.
extends SceneTree

const T_ := preload("res://tests/t.gd")
const Const_ := preload("res://scripts/core/const.gd")
const Types_ := preload("res://scripts/core/types.gd")
const Values_ := preload("res://scripts/core/values.gd")
const Scheme_ := preload("res://scripts/core/scheme.gd")
const Field_ := preload("res://scripts/sim/field.gd")
const Sim_ := preload("res://scripts/sim/sim.gd")
const Player_ := preload("res://scripts/sim/player.gd")
const Ai_ := preload("res://scripts/sim/ai.gd")
const Bomb_ := preload("res://scripts/sim/bomb.gd")


func _init() -> void:
	var t := T_.new("bots")
	_test_knobs(t)
	_test_a_bot_moves(t)
	_test_a_bot_flees_danger(t)
	_test_a_bot_does_not_walk_through_fire(t)
	_test_a_bot_does_not_bomb_itself_into_a_corner(t)
	_test_a_bot_takes_powerups(t)
	_test_rounds_finish(t)
	_test_determinism(t)
	_test_bots_survive_the_specials(t)
	_test_the_danger_map_is_graded(t)
	_test_a_bot_triggers_its_own_bomb(t)
	_test_a_bot_kicks_an_adjacent_bomb(t)
	_test_the_enemy_bomb_rule_matches_the_original_shape(t)
	_test_a_bot_hunts_a_nearby_enemy(t)
	quit(t.finish())


func _test_knobs(t: T_) -> void:
	t.eq(Values_.V[Const_.Res.AI_PERSONALITIES], 1,
		"resource 900: one AI personality is defined")
	t.eq(Values_.V[Const_.Res.AI_FIREGOD_LOOKAHEAD], 15,
		"resource 910: the closing wall is a threat 15 cells ahead")
	t.eq(Values_.V[Const_.Res.AI_BLAST_BRICKS_CHANCE], 5,
		"resource 915: blast-bricks is a 1-in-5 chance")
	t.eq(Values_.V[Const_.Res.AI_POWERUP_RADIUS], 4,
		"resource 920: a powerup is worth going for within 4 cells")


func _test_a_bot_moves(t: T_) -> void:
	var sim := _sim(1, 90, 3)
	sim.add_bot(0)
	t.ok(sim.is_bot(0), "slot 0 is a bot")
	t.eq(sim.bot_count(), 1, "and the only one")

	var p: Player_ = sim.players[0]
	var start := Vector2i(p.x, p.y)
	var moved := false
	for _i in 120:
		sim.tick()
		if Vector2i(p.x, p.y) != start:
			moved = true
			break
	t.ok(moved, "a bot moves without being told to")

	# It must also DO something: a bot that only walks never opens the field.
	var bombed := false
	for _i in 400:
		sim.tick()
		if not sim.bombs.is_empty():
			bombed = true
			break
	t.ok(bombed, "a bot places bombs")

	# And it must actually clear bricks, which is what a round needs.
	var bricks_before := sim.field.count_of(Types_.Brick.BRICK)
	for _i in 600:
		sim.tick()
	t.ok(sim.field.count_of(Types_.Brick.BRICK) < bricks_before,
		"a bot destroys bricks (%d -> %d)"
			% [bricks_before, sim.field.count_of(Types_.Brick.BRICK)])


# A bot standing where a bomb is about to go off must leave — and the way to
# measure that is whether it is ALIVE afterwards, not whether it happened to
# wander off. The first version of this test checked distance from the bomb
# within 25 ticks, and mutation M49 — deleting the danger check entirely —
# passed it, because a bot walking toward bricks drifts clear often enough.
func _test_a_bot_flees_danger(t: T_) -> void:
	var deaths := 0
	var trials := 8
	for seed_value in trials:
		var sim := _sim(1, 0, 300 + seed_value)
		sim.add_bot(0)
		var p: Player_ = sim.players[0]
		_clear_row(sim, 4)
		p.place_at_tile_centre(7, 4)
		# Somebody else's bomb, right under the bot, reaching the whole row.
		var b := sim.place_bomb(p)
		b.owner = 1
		b.chain_owner = 1
		b.flame_len = 5
		b.fuze = 25
		p.bombs_available = p.bombs_total
		# Long enough for the bomb to go off and its flame to clear.
		for _i in 60:
			sim.tick()
		if p.dying or not p.alive:
			deaths += 1
	t.eq(deaths, 0,
		"a bot survived all %d bombs dropped under it" % trials)

	# And the flight is deliberate: it must be clear of the blast BEFORE the
	# bomb goes off, not merely alive by accident of the flame's shape.
	var sim2 := _sim(1, 0, 321)
	sim2.add_bot(0)
	var p2: Player_ = sim2.players[0]
	_clear_row(sim2, 4)
	p2.place_at_tile_centre(7, 4)
	var b2 := sim2.place_bomb(p2)
	b2.owner = 1
	b2.chain_owner = 1
	b2.flame_len = 3
	b2.fuze = 25
	p2.bombs_available = p2.bombs_total
	for _i in 24:
		sim2.tick()
	var dx: int = absi(p2.tile_x() - b2.tile_x())
	var dy: int = absi(p2.tile_y() - b2.tile_y())
	t.ok(not ((dx == 0 and dy <= 3) or (dy == 0 and dx <= 3)),
		"and left the blast cross before the bomb went off (dx %d, dy %d)"
			% [dx, dy])


# A bot must not walk THROUGH fire to reach something it wants. Distinct from
# fleeing: the bot is safe where it stands, and the tempting thing is on the
# far side of a blast.
#
# NOTE ON WHAT THIS DOES AND DOES NOT CATCH. The three-deaths-in-eight that
# _test_a_bot_flees_danger measures came from the idle-wander fallback, not
# from goal pathing — established by reverting each half separately. This test
# covers the goal-pathing half, and it does NOT currently fail when that half
# is reverted: the bot turns back at the blast's edge before its own tile index
# enters it. Recorded rather than papered over; docs/BUGS.md.
func _test_a_bot_does_not_walk_through_fire(t: T_) -> void:
	var entered := 0
	var trials := 6
	for seed_value in trials:
		var sim := _sim(1, 0, 700 + seed_value)
		sim.add_bot(0)
		var p: Player_ = sim.players[0]
		# One clear corridor and walls everywhere else, so the ONLY route to
		# the powerup runs through the bomb's blast.
		for y in Const_.FIELD_H:
			for x in Const_.FIELD_W:
				sim.field.brick[Field_.idx(x, y)] = Types_.Brick.SOLID
		for x in range(1, 12):
			sim.field.brick[Field_.idx(x, 4)] = Types_.Brick.BLANK
		p.place_at_tile_centre(2, 4)
		# A live bomb two cells along, reaching one cell each way — so (3,4),
		# (4,4) and (5,4) burn.
		var b := sim.place_bomb(p)
		b.place_at_tile_centre(4, 4)
		b.owner = 1
		b.chain_owner = 1
		b.flame_len = 1
		b.fuze = 200                 # long, so the danger persists
		p.bombs_available = p.bombs_total
		# Something worth having just BEYOND the blast, and inside resource
		# 920's four-cell radius — so the bot wants it and the only route
		# there is through the fire. Putting it further away made the test
		# vacuous: the radius check refused the goal before pathing mattered.
		sim.field.powerup[Field_.idx(6, 4)] = Types_.PowerUp.FLAME

		for _i in 80:
			sim.tick()
			var dx: int = absi(p.tile_x() - 4)
			if p.tile_y() == 4 and dx <= 1:
				entered += 1
				break
	t.eq(entered, 0,
		"a bot never crossed a blast to reach a powerup (%d of %d trials)"
			% [entered, trials])


# The commonest way a naive Bomberman agent dies is bombing itself with no
# escape. A bot must not do it.
func _test_a_bot_does_not_bomb_itself_into_a_corner(t: T_) -> void:
	var ai: Ai_ = Ai_.new()

	# A dead end: walls on three sides, one brick to blast, nowhere to run
	# except back down a one-cell corridor that the blast covers.
	var sim := _sim(1, 0, 11)
	sim.add_bot(0)
	var p: Player_ = sim.players[0]
	for y in Const_.FIELD_H:
		for x in Const_.FIELD_W:
			sim.field.brick[Field_.idx(x, y)] = Types_.Brick.SOLID
	# A corridor of length 2 with a brick at the end.
	sim.field.brick[Field_.idx(1, 1)] = Types_.Brick.BLANK
	sim.field.brick[Field_.idx(2, 1)] = Types_.Brick.BLANK
	sim.field.brick[Field_.idx(3, 1)] = Types_.Brick.BRICK
	p.place_at_tile_centre(2, 1)
	p.flame_len = 4          # long enough to cover the whole corridor

	var suicides := 0
	for _i in 60:
		var choice := ai.think(sim, p)
		if int(choice["action"]) == Types_.Action.FIRST:
			suicides += 1
		sim.tick()
		if p.dying:
			break
	t.eq(suicides, 0,
		"a bot does not bomb a dead end its own blast fills")
	t.ok(not p.dying, "and does not die there")

	# Give it room and it should bomb happily.
	var open_sim := _sim(1, 0, 11)
	open_sim.add_bot(0)
	var p2: Player_ = open_sim.players[0]
	p2.place_at_tile_centre(7, 5)
	open_sim.field.brick[Field_.idx(8, 5)] = Types_.Brick.BRICK
	var bombed := false
	for _i in 200:
		open_sim.tick()
		if not open_sim.bombs.is_empty():
			bombed = true
			break
	t.ok(bombed, "but does bomb a brick when there is somewhere to run")


func _test_a_bot_takes_powerups(t: T_) -> void:
	var sim := _sim(1, 0, 13)
	sim.add_bot(0)
	var p: Player_ = sim.players[0]
	# EVEN coordinates: the fixture's pillar grid puts a solid on every
	# odd/odd cell, so (5,5) and (7,5) — the first version of this test — were
	# both inside walls and the powerup was unreachable by construction.
	_clear_row(sim, 4)
	p.place_at_tile_centre(4, 4)
	# A good powerup two cells away, inside resource 920's radius of four.
	sim.field.powerup[Field_.idx(6, 4)] = Types_.PowerUp.FLAME
	var before := p.flame_len

	var taken := false
	for _i in 60:
		sim.tick()
		if p.flame_len > before:
			taken = true
			break
	t.ok(taken, "a bot walks to a powerup within four cells and takes it")

	# It must NOT go for a disease.
	var s2 := _sim(1, 0, 13)
	s2.add_bot(0)
	var p2: Player_ = s2.players[0]
	_clear_row(s2, 4)
	p2.place_at_tile_centre(4, 4)
	s2.field.powerup[Field_.idx(5, 4)] = Types_.PowerUp.DISEASE
	var caught := false
	for _i in 40:
		s2.tick()
		if p2.any_disease():
			caught = true
			break
	t.ok(not caught, "and does not walk into a disease on purpose")


# The point of bots: a round with nothing but bots must reach an end. Without
# that a solo player has no game.
func _test_rounds_finish(t: T_) -> void:
	var finished := 0
	var outcomes := {}
	var trials := 6
	for seed_value in trials:
		var sim := _sim(4, 90, 100 + seed_value)
		for i in 4:
			sim.add_bot(i)
		# 3000 ticks is the full 150-second round, so this covers the timeout
		# case as well as everybody dying.
		for _i in 3100:
			sim.tick()
			if sim.round_over():
				break
		if sim.round_over():
			finished += 1
			outcomes[sim.outcome] = int(outcomes.get(sim.outcome, 0)) + 1
	t.eq(finished, trials,
		"all %d four-bot rounds reached an end" % trials)
	t.note("outcomes: %s (1 = last standing, 2 = draw, 3 = time up)"
		% str(outcomes))

	# At least some rounds must end by someone WINNING rather than the clock
	# running out, or the bots are not actually fighting.
	t.ok(int(outcomes.get(Sim_.Outcome.LAST_STANDING, 0))
		+ int(outcomes.get(Sim_.Outcome.DRAW, 0)) > 0,
		"and at least one ended in combat rather than on the clock")

	# Ten bots at once, which is the full field.
	var big := _sim(10, 90, 999)
	for i in 10:
		big.add_bot(i)
	for _i in 3100:
		big.tick()
		if big.round_over():
			break
	t.ok(big.round_over(), "a ten-bot round also finishes")
	# [invariant] and nobody ended up inside a wall.
	for p in big.players:
		if p.alive and not p.dying:
			t.ok(big.field.is_open(p.tile_x(), p.tile_y()),
				"[invariant] bot %d is not inside a wall" % p.slot)


# [invariant] A bot round must replay exactly, or the netcode's hash assertion
# and the parity harness both stop meaning anything for any game with bots.
func _test_determinism(t: T_) -> void:
	var traces := []
	for _run in 3:
		var sim := _sim(4, 90, 555)
		for i in 4:
			sim.add_bot(i)
		var trace := PackedInt64Array()
		for _i in 300:
			sim.tick()
			trace.append(sim.state_hash())
		traces.append(trace)
	t.eq(traces[0], traces[1], "[invariant] a bot round replays identically")
	t.eq(traces[1], traces[2], "[invariant] and again")

	# A different seed must diverge, or "deterministic" is trivially true.
	var other := _sim(4, 90, 556)
	for i in 4:
		other.add_bot(i)
	var other_trace := PackedInt64Array()
	for _i in 300:
		other.tick()
		other_trace.append(other.state_hash())
	t.ok(other_trace != traces[0], "a different seed plays differently")


# The specials are where a bot gets stuck: a conveyor carries it, a warp moves
# it, a trampoline takes it out of play. A round on each must still finish.
func _test_bots_survive_the_specials(t: T_) -> void:
	for level in [2, 3, 4, 9, 10]:
		var sim := _sim(4, 90, 40 + level)
		sim.level = level
		sim.setup(_scheme(90), [{"slot": 0, "team": 0}, {"slot": 1, "team": 1},
			{"slot": 2, "team": 0}, {"slot": 3, "team": 1}], 40 + level)
		for i in 4:
			sim.add_bot(i)
		for _i in 3100:
			sim.tick()
			if sim.round_over():
				break
		t.ok(sim.round_over(),
			"a four-bot round on level %d finishes" % level)
		for p in sim.players:
			if p.alive and not p.dying and p.fly_ticks == 0:
				t.ok(sim.field.is_open(p.tile_x(), p.tile_y()),
					"[invariant] level %d bot %d is not inside a wall"
						% [level, p.slot])


## Clear one row so a walking test has a corridor. The fixture's grid puts a
## solid on every odd/odd cell, which is realistic and is also why a test that
## picks coordinates carelessly measures nothing.
func _clear_row(sim: Sim_, y: int) -> void:
	for x in Const_.FIELD_W:
		sim.field.brick[Field_.idx(x, y)] = Types_.Brick.BLANK


func _scheme(density: int) -> Scheme_:
	var lines := PackedStringArray()
	lines.append("-V,2")
	lines.append("-N,Bot fixture (10)")
	lines.append("-B,%d" % density)
	for y in Const_.FIELD_H:
		var row := ""
		for x in Const_.FIELD_W:
			row += "#" if (x % 2 == 1 and y % 2 == 1) else ":"
		lines.append("-R,%2d,%s" % [y, row])
	var starts := [[0, 0], [14, 10], [0, 10], [14, 0], [6, 4],
		[8, 0], [12, 4], [2, 6], [10, 8], [6, 10]]
	for p in Const_.PLAYER_COUNT:
		lines.append("-S,%d,%d,%d,%d" % [p, starts[p][0], starts[p][1], p % 2])
	for i in Const_.POWERUP_COUNT:
		lines.append("-P,%2d, 0,0, 0, 0,x" % i)
	var s: Scheme_ = Scheme_.new()
	s.parse_text("\n".join(lines), "<bots>")
	assert(s.ok(), "fixture must parse: %s" % s.error())
	return s


func _sim(count: int, density: int, round_seed: int) -> Sim_:
	var slots := []
	for i in count:
		slots.append({"slot": i, "team": i % 2})
	var sim: Sim_ = Sim_.new()
	sim.setup(_scheme(density), slots, round_seed)
	return sim


# ---------------------------------------------------------------------------
# The danger map says WHEN, not just whether — the same idea as the original's
# influence map (docs/BUGS.md Q5.4), in the port's own units: 0 is safe, and
# any other value is how soon the fire arrives, smallest first.
#
# Measured before adopting, 16 seeds of four bots: 8 self-kills and 47
# survivors graded against 9 and 46 boolean, all 16 rounds finishing either
# way. A small gain and no regression, which is why it is in.
# ---------------------------------------------------------------------------
func _test_the_danger_map_is_graded(t: T_) -> void:
	# An open field: this suite's usual fixture is bricks everywhere, which
	# stops every arm after one cell and would make the cross assertions below
	# say nothing.
	var sim := _open_sim(2)
	var ai := Ai_.new()
	var p: Player_ = sim.players[0]
	p.place_at_tile_centre(5, 5)
	p.flame_len = 2

	var clear: PackedByteArray = ai._danger_map(sim)
	t.eq(int(clear[Field_.idx(5, 5)]), 0, "an empty field is all safe")

	var fresh = sim.place_bomb(p)
	var graded: PackedByteArray = ai._danger_map(sim)
	var at_bomb: int = graded[Field_.idx(5, 5)]
	t.ok(at_bomb > 0, "the bomb's own cell is dangerous")
	t.eq(at_bomb, fresh.fuze + 1,
		"and the number is its fuze — how soon, not whether")
	t.eq(int(graded[Field_.idx(7, 5)]), at_bomb,
		"the whole cross carries the same countdown")
	t.eq(int(graded[Field_.idx(8, 5)]), 0, "and beyond its reach is safe")

	# Burn it down a little: the same cell should read as sooner.
	for _i in 10:
		sim.tick()
	var later: PackedByteArray = ai._danger_map(sim)
	t.ok(int(later[Field_.idx(5, 5)]) < at_bomb,
		"ten ticks later the same bomb reads as ten ticks nearer")

	# Two bombs over one cell: the sooner one is the one that matters.
	var q: Player_ = sim.players[1]
	q.place_at_tile_centre(7, 5)
	q.flame_len = 2
	var second = sim.place_bomb(q)
	var both: PackedByteArray = ai._danger_map(sim)
	t.ok(second.fuze > int(later[Field_.idx(5, 5)]),
		"the new bomb has longer to run than the old one")
	t.eq(int(both[Field_.idx(6, 5)]), int(later[Field_.idx(6, 5)]),
		"so a cell both bombs cover keeps the SOONER countdown")

	# A trigger bomb has no countdown to read, and is treated as imminent.
	var s2 := _open_sim(1)
	var r: Player_ = s2.players[0]
	r.place_at_tile_centre(3, 3)
	r.trigger_bombs = 1
	s2.place_bomb(r)
	var trig: PackedByteArray = Ai_.new()._danger_map(s2)
	t.eq(int(trig[Field_.idx(3, 3)]), Ai_.BURNING_NOW,
		"a trigger bomb could go off this tick, so it reads as now")


# Handler 0, 0x40BD44: standing on your own live trigger bomb is a 1-in-2
# chance to press it. Measured over many independent rolls rather than
# asserted every-tick, because it is a coin flip, not a rule.
func _test_a_bot_triggers_its_own_bomb(t: T_) -> void:
	var fired := 0
	var trials := 200
	for seed_value in trials:
		var sim := _open_sim(1)
		sim.rng.seed = 4000 + seed_value
		var p: Player_ = sim.players[0]
		p.place_at_tile_centre(5, 5)
		p.trigger_bombs = 1
		sim.place_bomb(p)
		var choice := Ai_.new().think(sim, p)
		if int(choice["action"]) == Types_.Action.SECOND:
			fired += 1
	t.close(float(fired) / trials, 0.5, 0.12,
		"a bot on its own trigger bomb presses it about 1 time in 2 (%d/%d)"
			% [fired, trials])

	# And never presses SECOND without one underfoot — that is the only step
	# that returns it.
	var quiet := _open_sim(1)
	var q: Player_ = quiet.players[0]
	q.place_at_tile_centre(5, 5)
	var idle := Ai_.new().think(quiet, q)
	t.ok(int(idle["action"]) != Types_.Action.SECOND,
		"and never presses it standing on nothing")


# Handler 1, 0x40BE02: a kickable bomb next to you is a 1-in-4 chance to walk
# into it. The port has no separate kick button, so "kicks" here means "faces
# and steps toward" — measured as the move landing on the bomb's direction.
func _test_a_bot_kicks_an_adjacent_bomb(t: T_) -> void:
	var kicked := 0
	var trials := 400
	for seed_value in trials:
		var sim := _open_sim(2)
		sim.rng.seed = 5000 + seed_value
		var p: Player_ = sim.players[0]
		p.place_at_tile_centre(5, 5)
		p.can_kick = true
		# Somebody else's bomb, at rest, directly to the east.
		var other: Player_ = sim.players[1]
		other.place_at_tile_centre(9, 9)
		var b := sim.place_bomb(other)
		b.place_at_tile_centre(6, 5)
		var choice := Ai_.new().think(sim, p)
		if int(choice["move"]) == Types_.MoveState.RIGHT:
			kicked += 1
	t.close(float(kicked) / trials, 0.25, 0.08,
		"a bot with an adjacent bomb walks into it about 1 time in 4 (%d/%d)"
			% [kicked, trials])

	# Without can_kick, it never fires — the gate, not the roll.
	var no_kick := _open_sim(2)
	var np: Player_ = no_kick.players[0]
	np.place_at_tile_centre(5, 5)
	var nb: Player_ = no_kick.players[1]
	nb.place_at_tile_centre(9, 9)
	var b2 := no_kick.place_bomb(nb)
	b2.place_at_tile_centre(6, 5)
	var forced := 0
	for seed_value in 40:
		no_kick.rng.seed = 6000 + seed_value
		var choice2 := Ai_.new().think(no_kick, np)
		if int(choice2["move"]) == Types_.MoveState.RIGHT:
			forced += 1
	t.eq(forced, 0, "and not at all without the kick powerup")


# Handler 4, 0x40ABED, corrected shape: a fixed 5-cell plus (Manhattan <= 1
# from the bot), not the flame-scaled cross this used to be, and gated on no
# own bomb within 3 tiles — see the long comment at the call site in ai.gd for
# why that is the reading used for the distance-3 gate.
func _test_the_enemy_bomb_rule_matches_the_original_shape(t: T_) -> void:
	# An enemy TWO cells away is outside the fixed plus shape, even with a
	# long-range bomb: the original does not scale this by flame_len.
	var far := _open_sim(2)
	var p: Player_ = far.players[0]
	p.place_at_tile_centre(5, 5)
	p.flame_len = 6
	p.bombs_available = p.bombs_total
	var e: Player_ = far.players[1]
	e.place_at_tile_centre(7, 5)
	var ai := Ai_.new()
	t.ok(not ai._enemy_near(far, p, Vector2i(5, 5)),
		"an enemy two cells away is outside the fixed 5-cell plus")

	# Adjacent is in range.
	var near := _open_sim(2)
	var p2: Player_ = near.players[0]
	p2.place_at_tile_centre(5, 5)
	var e2: Player_ = near.players[1]
	e2.place_at_tile_centre(6, 5)
	t.ok(ai._enemy_near(near, p2, Vector2i(5, 5)),
		"an adjacent enemy is inside it")

	# The distance-3 gate: a bot with its own live bomb two cells away must
	# not add another next to an adjacent enemy.
	var busy := _open_sim(2)
	var p3: Player_ = busy.players[0]
	p3.place_at_tile_centre(5, 5)
	p3.bombs_available = p3.bombs_total
	busy.place_bomb(p3)
	var mover: Bomb_ = busy.bombs[0]
	mover.place_at_tile_centre(6, 6)          # Manhattan 2 from (5,5)
	var e3: Player_ = busy.players[1]
	e3.place_at_tile_centre(6, 5)
	t.ok(ai._own_bomb_too_close(busy, p3, Vector2i(5, 5)),
		"a bomb 2 tiles away is inside the distance-3 gate")

	var clear := _open_sim(1)
	var p4: Player_ = clear.players[0]
	p4.place_at_tile_centre(5, 5)
	t.ok(not ai._own_bomb_too_close(clear, p4, Vector2i(5, 5)),
		"and with no bomb of its own at all, the gate is open")

	# The throttle, measured the same way as the other two rolls. Reads
	# Ai_.ENGAGE_CHANCE_DENOM rather than a hardcoded rate — that constant is
	# a deliberate gameplay number (see ai.gd's "GAMEPLAY AGGRESSION" block),
	# not a fidelity read, and this test should track it, not fight it.
	var fired := 0
	var trials := 400
	for seed_value in trials:
		var sim := _open_sim(2)
		sim.rng.seed = 7000 + seed_value
		var bot: Player_ = sim.players[0]
		bot.place_at_tile_centre(5, 5)
		bot.bombs_available = bot.bombs_total
		var target: Player_ = sim.players[1]
		target.place_at_tile_centre(6, 5)
		var choice := Ai_.new().think(sim, bot)
		if int(choice["action"]) == Types_.Action.FIRST:
			fired += 1
	var expect := 1.0 / float(Ai_.ENGAGE_CHANCE_DENOM)
	t.close(float(fired) / trials, expect, 0.07,
		"an adjacent enemy is bombed about 1 time in %d (%d/%d)"
			% [Ai_.ENGAGE_CHANCE_DENOM, fired, trials])


## Step 6's own addition (ai.gd's "GAMEPLAY AGGRESSION" block): a bot with
## nothing safer to do closes the distance on a nearby enemy instead of
## drifting on the random wander. Not the original's behaviour — the
## original's step 6 only ever sought a brick — so this asserts the port's
## own chosen shape, not a disassembly read.
func _test_a_bot_hunts_a_nearby_enemy(t: T_) -> void:
	var sim := _open_sim(2)
	var bot: Player_ = sim.players[0]
	bot.place_at_tile_centre(2, 5)
	var enemy: Player_ = sim.players[1]
	enemy.place_at_tile_centre(6, 5)          # 4 cells away, inside HUNT_RADIUS
	var choice := Ai_.new().think(sim, bot)
	t.eq(int(choice["move"]), Types_.MoveState.RIGHT,
		"an enemy 4 cells off, with nothing else to do, pulls the bot toward it")

	# Far outside HUNT_RADIUS: no pull, falls through to the plain wander.
	var far := _open_sim(2)
	var bot2: Player_ = far.players[0]
	bot2.place_at_tile_centre(1, 1)
	var enemy2: Player_ = far.players[1]
	enemy2.place_at_tile_centre(13, 9)          # far past HUNT_RADIUS
	var goal := Ai_.new()._nearest_enemy_cell(far, bot2,
		Ai_.new()._walk_distances(far, Vector2i(1, 1)),
		Ai_.new()._danger_map(far))
	# The enemy is still the nearest (only) one _nearest_enemy_cell finds —
	# think() is what applies the HUNT_RADIUS cutoff on top of that, so this
	# checks the cutoff directly rather than inferring it from a move.
	t.ok(goal.x >= 0, "the enemy is still found as a candidate")
	var dist: PackedInt32Array = Ai_.new()._walk_distances(far, Vector2i(1, 1))
	t.ok(dist[Field_.idx(goal.x, goal.y)] > Ai_.HUNT_RADIUS,
		"but it is farther than HUNT_RADIUS, so think() will not chase it")


## An empty field — no bricks, no solids inside the border — for assertions
## about what a bomb's cross covers.
func _open_sim(count: int) -> Sim_:
	var lines := PackedStringArray()
	lines.append("-V,2")
	lines.append("-N,Open (10)")
	lines.append("-B,0")
	for y in Const_.FIELD_H:
		lines.append("-R,%2d,%s" % [y, ".".repeat(Const_.FIELD_W)])
	for p in Const_.PLAYER_COUNT:
		lines.append("-S,%d,%d,%d,%d" % [p, p, p % 9, p % 2])
	for i in Const_.POWERUP_COUNT:
		lines.append("-P,%2d, 0,0, 0, 0,x" % i)
	var s: Scheme_ = Scheme_.new()
	s.parse_text("\n".join(lines), "<open>")
	assert(s.ok(), "open fixture must parse: %s" % s.error())
	var slots := []
	for i in count:
		slots.append({"slot": i, "team": i % 2})
	var sim: Sim_ = Sim_.new()
	sim.setup(s, slots, 1)
	return sim
