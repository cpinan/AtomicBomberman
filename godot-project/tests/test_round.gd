# The round: its clock, Hurry's closing wall, and how it ends.
#
# The three round-end cases are the ones a match cannot work without, and the
# Hurry depth is ORACLE row 19 — the original closes TWO ROWS by default, not
# the whole field, which is what fpc_atomic does.
extends SceneTree

const T_ := preload("res://tests/t.gd")
const Const_ := preload("res://scripts/core/const.gd")
const Types_ := preload("res://scripts/core/types.gd")
const Values_ := preload("res://scripts/core/values.gd")
const Scheme_ := preload("res://scripts/core/scheme.gd")
const Field_ := preload("res://scripts/sim/field.gd")
const Sim_ := preload("res://scripts/sim/sim.gd")
const Player_ := preload("res://scripts/sim/player.gd")


func _init() -> void:
	var t := T_.new("round")
	_test_clock(t)
	_test_hurry_threshold(t)
	_test_hurry_depth(t)
	_test_hurry_wall(t)
	_test_last_standing(t)
	_test_draw(t)
	_test_time_up(t)
	_test_teams(t)
	_test_default_teams(t)
	_test_random_start(t)
	_test_dying(t)
	_test_forced_draw(t)
	quit(t.finish())


func _test_clock(t: T_) -> void:
	var sim := _sim(2)
	t.eq(Values_.V[Const_.Res.ROUND_SECONDS], 150,
		"the default round is resource 100 = 150 seconds")
	t.eq(sim.seconds_left(), 150, "and the clock starts there")
	t.eq(sim.time_left, 150 * Const_.TICK_HZ, "which is 3000 ticks at 20 Hz")

	for _i in Const_.TICK_HZ:
		sim.tick()
	t.eq(sim.seconds_left(), 149, "one second of ticks costs one second")
	t.ok(not sim.round_over(), "and the round is still running")


# Resource 101 is 60 seconds remaining, and the file says do not change it.
func _test_hurry_threshold(t: T_) -> void:
	t.eq(Values_.V[Const_.Res.HURRY_AT_SECONDS], 60,
		"Hurry starts at resource 101 = 60 seconds remaining")

	var sim := _sim(2)
	t.eq(sim.hurry_index, -1, "Hurry is not running at the start")
	# Wind the clock to one tick before the threshold.
	sim.time_left = 60 * Const_.TICK_HZ + 1
	sim.tick()
	t.ok(sim.hurry_index >= 0, "Hurry starts when the clock reaches 60s")

	var heard := false
	var s2 := _sim(2)
	s2.time_left = 60 * Const_.TICK_HZ + 1
	s2.tick()
	for event in s2.sounds:
		if event["effect"] == Types_.SoundEffect.HURRY:
			heard = true
	t.ok(heard, "and raises the Hurry sound once")


# ORACLE row 19. Resource 27 is 1 of the 4 depths resource 28 counts, which is
# two rows — not the whole field.
func _test_hurry_depth(t: T_) -> void:
	t.eq(Values_.V[Const_.Res.ENCLOSE_DEPTH], 1,
		"the default enclosement depth is resource 27 = 1")
	t.eq(Values_.V[Const_.Res.ENCLOSE_DEPTH_COUNT], 4,
		"and resource 28 says there are four depths")

	var sim := _sim(2)
	var path := sim.hurry_path()
	# Depth 1 is the outer ring only: the full perimeter of a 15x11 field.
	var perimeter := 2 * Const_.FIELD_W + 2 * (Const_.FIELD_H - 2)
	t.eq(path.size(), perimeter,
		"depth 1 closes the outer ring, %d cells" % perimeter)
	t.ok(path.size() < Const_.FIELD_W * Const_.FIELD_H,
		"which is far short of the whole field — fpc_atomic's spiral is depth 3")

	# Every cell on the path is on the field and appears once.
	var seen := {}
	for cell in path:
		t.ok(Field_.in_bounds(cell.x, cell.y),
			"path cell %s is on the field" % cell)
		t.ok(not seen.has(cell), "path cell %s appears once" % cell)
		seen[cell] = true

	# It starts in a corner and hugs the edge.
	t.eq(path[0], Vector2i(0, 0), "the spiral starts at the top-left")
	for cell in path:
		t.ok(cell.x == 0 or cell.y == 0 or cell.x == Const_.FIELD_W - 1
			or cell.y == Const_.FIELD_H - 1,
			"depth 1 only ever fills the outer ring")


func _test_hurry_wall(t: T_) -> void:
	var sim := _sim(2)
	# Put a player in the wall's way, in the top-left corner it starts from.
	var victim: Player_ = sim.players[0]
	victim.place_at_tile_centre(0, 0)
	sim.players[1].place_at_tile_centre(7, 5)

	sim.time_left = 60 * Const_.TICK_HZ + 1
	# Long enough for the wall to reach the corner.
	for _i in 40:
		sim.tick()
		if victim.dying:
			break
	t.ok(victim.dying, "the closing wall crushes a player in its path")
	t.ok(not sim.field.is_open(0, 0), "and leaves a solid behind")

	# Resource 46: a bomb caught by the wall is DETONATED, not destroyed.
	t.eq(Values_.V[Const_.Res.WALL_DETONATES_BOMB], 1,
		"resource 46 says the wall detonates a bomb")
	var s2 := _sim(2)
	var p2: Player_ = s2.players[0]
	p2.place_at_tile_centre(0, 0)
	var b := s2.place_bomb(p2)
	b.fuze = 9999            # so only the wall can set it off
	p2.place_at_tile_centre(7, 7)
	s2.players[1].place_at_tile_centre(9, 7)
	s2.time_left = 60 * Const_.TICK_HZ + 1
	var gone := false
	for _i in 40:
		s2.tick()
		if s2.bombs.is_empty():
			gone = true
			break
	t.ok(gone, "a bomb caught by the wall goes off rather than vanishing")


func _test_last_standing(t: T_) -> void:
	var sim := _sim(3)
	t.ok(not sim.round_over(), "three players, round running")
	sim.kill(sim.players[0], 1)
	sim.tick()
	t.ok(not sim.round_over(), "two left, still running")
	sim.kill(sim.players[1], 2)
	sim.tick()
	t.ok(sim.round_over(), "one left, round over")
	t.eq(sim.outcome, Sim_.Outcome.LAST_STANDING, "by last-standing")
	t.eq(sim.winner_slot, sim.players[2].slot, "and the survivor wins")

	# It keeps ticking afterwards so death animations can finish, and counts
	# how long it has been over.
	var before := sim.ticks_since_over
	sim.tick()
	t.eq(sim.ticks_since_over, before + 1, "and it keeps counting after the end")


func _test_draw(t: T_) -> void:
	var sim := _sim(2)
	sim.kill(sim.players[0], 1)
	sim.kill(sim.players[1], 0)
	sim.tick()
	t.ok(sim.round_over(), "both dead, round over")
	t.eq(sim.outcome, Sim_.Outcome.DRAW, "and it is a draw")
	t.eq(sim.winner_slot, -1, "with no winner")

	# A single player alone is NOT instantly a winner, or a one-player round
	# would end on tick one.
	var solo := _sim(1)
	solo.tick()
	t.ok(not solo.round_over(), "a lone player does not win by default")


func _test_time_up(t: T_) -> void:
	var sim := _sim(2)
	sim.time_left = 2
	sim.tick()
	t.ok(not sim.round_over(), "one tick left, still running")
	sim.tick()
	t.ok(sim.round_over(), "the clock runs out")
	t.eq(sim.outcome, Sim_.Outcome.TIME_UP, "and the round ends on time")
	t.eq(sim.seconds_left(), 0, "with no time left")


# WHICH HALF, not odd against even.
#
# OPTIONS.BM says it twice in its own words: "Generally, players 1 through 5 are
# on one team and players 6 through 10 are on another", and under Wally Bomb,
# "To ensure that the teams are placed properly, player slots 1 through 5 are on
# one team and player slots 6 through 10 are on the other."
#
# The port used slot % 2 until that file arrived, which puts every player on the
# opposite team from the original and pairs the wrong people on a scheme whose
# start positions are laid out for the halves. docs/BUGS.md D20.
func _test_default_teams(t: T_) -> void:
	for slot in Const_.PLAYER_COUNT:
		var expected := 0 if slot < 5 else 1
		t.eq(Const_.default_team(slot), expected,
			"player %d is on team %d" % [slot + 1, expected])

	var first := 0
	var second := 0
	for slot in Const_.PLAYER_COUNT:
		if Const_.default_team(slot) == 0:
			first += 1
		else:
			second += 1
	t.eq(first, 5, "five on the first team")
	t.eq(second, 5, "five on the second")

	# The halves are CONTIGUOUS, which is the property Wally Bomb depends on:
	# the two teams start on opposite sides of a wall, so a scheme's start
	# positions 1-5 must all belong to one team.
	for slot in Const_.PLAYER_COUNT - 1:
		if Const_.default_team(slot) != Const_.default_team(slot + 1):
			t.eq(slot, 4, "the teams change over exactly once, after player 5")

	# A scheme that states a team still wins: 36 of the 67 do, and this is only
	# the fallback for the 31 that do not.
	var sim := _sim(4)
	t.eq(sim.players[1].team, 1,
		"a scheme's own -S team is used where it states one")


func _test_teams(t: T_) -> void:
	var sim := _sim(4)
	sim.team_play = true
	# Slots 0 and 2 are team 0, slots 1 and 3 are team 1 in the fixture.
	sim.kill(sim.players[1], 0)
	sim.tick()
	t.ok(not sim.round_over(), "one of team 1 down, round continues")
	sim.kill(sim.players[3], 0)
	sim.tick()
	t.ok(sim.round_over(), "team 1 wiped out, round over")
	t.eq(sim.winner_team, sim.players[0].team, "and team 0 wins")

	# A team round with survivors on both sides does not end.
	var s2 := _sim(4)
	s2.team_play = true
	s2.kill(s2.players[0], 1)
	s2.kill(s2.players[1], 0)
	s2.tick()
	t.ok(not s2.round_over(), "one left on each side, round continues")


# WHAT DEATH DOES, which turned out to be less than it should have.
#
# Three things were wrong at once and they compounded into one report — "still
# no death animation and player still moves":
#
#   * set_input() wrote move and action onto a dying player. The simulation
#     ignores both, so nothing walked, but the view chooses the WALK sheet
#     whenever move is not STILL, so a corpse jogged on the spot for as long as
#     the key was held and the death frames were never reached.
#   * nothing ever cleared `alive`. A killed player was `dying` and `alive` for
#     the rest of the round, kept its place in every loop that tested `alive`,
#     and kept a shadow under it.
#   * the shadow was drawn for anyone `alive`, dying included.
func _test_dying(t: T_) -> void:
	var sim := _sim(2)
	var p: Player_ = sim.players[0]
	sim.set_input(p.slot, Types_.MoveState.RIGHT, Types_.Action.FIRST)
	t.eq(p.move, Types_.MoveState.RIGHT, "a living player takes its input")

	sim.kill(p, 1)
	t.ok(p.dying, "a killed player is dying")
	t.ok(p.alive, "and still on the field on the tick it happened")
	t.eq(p.move, Types_.MoveState.STILL, "and stopped")
	t.eq(p.death_tick, sim.tick_count, "with the tick it died on recorded")
	t.ok(p.death_anim >= 1 and p.death_anim <= Sim_.DEATH_ANIMS,
		"and one of the disc's %d deaths chosen (%d)"
			% [Sim_.DEATH_ANIMS, p.death_anim])

	# THE ONE THAT SHOWED. A held key, tick after tick, on a dead player.
	for _i in 10:
		sim.set_input(p.slot, Types_.MoveState.RIGHT, Types_.Action.FIRST)
		t.eq(p.move, Types_.MoveState.STILL,
			"a dying player takes no input, however long the key is held")

	# The same death is chosen from the same seed, so a replay dies the same
	# way — the animation is part of the simulation's output, not the view's.
	var again := _sim(2)
	again.kill(again.players[0], 1)
	t.eq(again.players[0].death_anim, p.death_anim,
		"and the same seed picks the same death")

	# It is gone once the animation has had its time.
	var start := sim.tick_count
	while sim.tick_count - start < Sim_.DEATH_TICKS - 1:
		sim.tick()
	t.ok(sim.players[0].alive,
		"the body is still there while the animation runs")
	sim.tick()
	t.ok(not sim.players[0].alive,
		"and gone %d ticks after the kill" % Sim_.DEATH_TICKS)
	t.ok(Sim_.DEATH_TICKS >= 93,
		"which is longer than the longest death the disc ships (93 steps)")

	# Neither state counts as standing, so the round ended when it should have
	# and does not un-end when the body is taken away.
	t.eq(sim.living_players(), 1, "one player is left standing")


# MANUAL.BM: "F10 - Forces a draw game." One of six in-game keys the disc names
# and the port had none of.
func _test_forced_draw(t: T_) -> void:
	var sim := _sim(4)
	t.ok(not sim.round_over(), "the round is running")
	t.ok(sim.force_draw(), "F10 ends it")
	t.ok(sim.round_over(), "the round is over")
	t.eq(sim.outcome, Sim_.Outcome.DRAW, "as a draw")
	t.eq(sim.winner_slot, -1, "with no winner")
	t.eq(sim.winner_team, Types_.TEAM_UNSET, "and no winning team")
	t.ok(not sim.force_draw(), "and a second press does nothing")

	# Everyone is still standing: it ends the ROUND, it does not kill anybody.
	t.eq(sim.living_players(), 4, "nobody was killed to do it")

	# A round already decided is not turned into a draw.
	var won := _sim(2)
	won.kill(won.players[1], 0)
	won.tick()
	t.eq(won.outcome, Sim_.Outcome.LAST_STANDING, "this round has a winner")
	t.ok(not won.force_draw(), "and F10 will not take it away")
	t.eq(won.winner_slot, won.players[0].slot, "the winner stands")


func _sim(count: int, round_seed: int = 1) -> Sim_:
	var lines := PackedStringArray()
	lines.append("-V,2")
	lines.append("-N,Round fixture (10)")
	lines.append("-B,0")
	for y in Const_.FIELD_H:
		lines.append("-R,%2d,%s" % [y, ".".repeat(Const_.FIELD_W)])
	for p in Const_.PLAYER_COUNT:
		lines.append("-S,%d,%d,%d,%d" % [p, 1 + p, 1 + (p % 8), p % 2])
	for i in Const_.POWERUP_COUNT:
		lines.append("-P,%2d, 0,0, 0, 0,x" % i)
	var s: Scheme_ = Scheme_.new()
	s.parse_text("\n".join(lines), "<round>")
	assert(s.ok(), "fixture must parse: %s" % s.error())

	var slots := []
	for i in count:
		slots.append({"slot": i, "team": i % 2})
	var sim: Sim_ = Sim_.new()
	sim.setup(s, slots, round_seed)
	return sim


# ---------------------------------------------------------------------------
# Random Start — MESSAGES.TXT 251, OPTIONS.BM: "player start positions will be
# randomized at the beginning of the match".
#
# AT THE BEGINNING OF THE MATCH, not of each round: the permutation comes from
# sim.start_seed, which its owner sets once from the match's first seed, and
# not from the round seed that lays out the bricks.
# ---------------------------------------------------------------------------
func _test_random_start(t: T_) -> void:
	# The disc's own default is ON — VALUELST 40, "default value of \"do we
	# randomize player starting positions?\"", which is 1 — so the baseline
	# here has to ask for it off rather than assume it.
	t.eq(Values_.V[Const_.Res.RANDOM_START], 1, "resource 40 says randomise")
	t.ok(Sim_.new().random_start, "and a fresh simulation starts that way")
	var plain := _sim(6)
	plain.random_start = false
	plain.setup(plain.scheme_used, _slots(6), 1)
	var fixed := _cells(plain)
	t.eq(fixed.size(), 6, "six players took the field")
	for p in plain.players:
		t.eq(p.tile_x(), p.slot + 1,
			"with it off, slot %d is on its own scheme cell" % p.slot)

	var shuffled := _random_sim(6, 99, 1)
	var moved := _cells(shuffled)
	t.eq(moved.size(), 6, "and six with Random Start on")

	# The same cells, dealt out differently: nobody is on a cell the scheme did
	# not name, and nobody shares one.
	var a := fixed.duplicate()
	var b := moved.duplicate()
	a.sort()
	b.sort()
	t.eq(b, a, "the same start cells are used, only dealt differently")
	t.ok(moved != fixed, "and this seed really does deal them differently")

	# The permutation is the start seed's, not the round seed's. Two rounds of
	# one match lay out different bricks and put the players in the same
	# places.
	var r1 := _cells(_random_sim(6, 99, 1))
	var r2 := _cells(_random_sim(6, 99, 12345))
	t.eq(r2, r1, "a second round of the same match starts everyone where the"
		+ " first one did")
	var other := _cells(_random_sim(6, 100, 1))
	t.ok(other != r1, "a different match deals a different hand")

	# Positions move; teams do not. The slots here name NO team, so the team
	# has to come from the slot's own -S row rather than from whichever row the
	# shuffle handed it a cell from. The fixture's rows put slot n on team n%2.
	#
	# Across seeds, not on one: the fixture puts slot n on team n%2 and its
	# cells in the same order, so a permutation that happens to move everyone
	# by an even number of places would keep the teams right by luck. Seed 99
	# is one of those.
	var unteamed := []
	for i in 6:
		unteamed.append({"slot": i})
	var wrong_team := 0
	var dealt_elsewhere := 0
	for start_seed in range(1, 25):
		var sim := _sim(6)
		sim.random_start = true
		sim.start_seed = start_seed
		sim.setup(sim.scheme_used, unteamed, 1)
		for p in sim.players:
			if p.team != p.slot % 2:
				wrong_team += 1
			if p.tile_x() != p.slot + 1:
				dealt_elsewhere += 1
	t.ok(dealt_elsewhere > 0,
		"%d players were dealt somebody else's cell across 24 seeds"
			% dealt_elsewhere)
	t.eq(wrong_team, 0, "and not one of them took that cell's team with it")

	# Two players either swap or they do not, and across seeds both happen.
	# A shuffle that stops one iteration short would never swap a pair — it
	# looks random for six players and is frozen for two.
	var swapped := 0
	var kept := 0
	var pair_plain := _sim(2)
	pair_plain.random_start = false
	pair_plain.setup(pair_plain.scheme_used, _slots(2), 1)
	var pair_fixed := _cells(pair_plain)
	for start_seed in range(1, 41):
		var pair := _cells(_random_sim(2, start_seed, 1))
		if pair[0] == pair_fixed[0]:
			kept += 1
		else:
			swapped += 1
	t.ok(swapped > 0, "two players sometimes swap (%d of 40)" % swapped)
	t.ok(kept > 0, "and sometimes do not (%d of 40)" % kept)

	# One player has nothing to permute, and must not crash or move.
	var solo := _random_sim(1, 7, 1)
	var solo_plain := _sim(1)
	solo_plain.random_start = false
	solo_plain.setup(solo_plain.scheme_used, _slots(1), 1)
	t.eq(_cells(solo), _cells(solo_plain), "a single player starts where it"
		+ " would have anyway")


## The cell each player is standing on, in slot order.
func _cells(sim: Sim_) -> Array:
	var out := []
	for p in sim.players:
		out.append(Vector2i(p.tile_x(), p.tile_y()))
	return out


func _random_sim(count: int, start_seed: int, round_seed: int) -> Sim_:
	var sim := _sim(count, round_seed)
	sim.random_start = true
	sim.start_seed = start_seed
	sim.setup(sim.scheme_used, _slots(count), round_seed)
	return sim


func _slots(count: int) -> Array:
	var out := []
	for i in count:
		out.append({"slot": i, "team": i % 2})
	return out
