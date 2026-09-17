# The abilities that move bombs: kick, punch, grab and throw, spooge, jelly,
# trigger. Plus the diseases that act on bombs or input.
#
# Every speed and height is read from the tuning table, never written down here.
# What is NOT from the table is how those numbers are applied — docs/BUGS.md Q5
# — so these assertions pin the reconstruction so a future correction is a
# visible diff rather than a silent change.
extends SceneTree

const T_ := preload("res://tests/t.gd")
const Const_ := preload("res://scripts/core/const.gd")
const Types_ := preload("res://scripts/core/types.gd")
const Values_ := preload("res://scripts/core/values.gd")
const Scheme_ := preload("res://scripts/core/scheme.gd")
const Field_ := preload("res://scripts/sim/field.gd")
const Sim_ := preload("res://scripts/sim/sim.gd")
const Player_ := preload("res://scripts/sim/player.gd")
const Bomb_ := preload("res://scripts/sim/bomb.gd")


func _init() -> void:
	var t := T_.new("abilities")
	_test_bomb_blocks_player(t)
	_test_kick(t)
	_test_jelly(t)
	_test_punch(t)
	_test_grab_and_throw(t)
	_test_spooge(t)
	_test_trigger(t)
	_test_bomb_diseases(t)
	_test_controls_reversed(t)
	_test_determinism(t)
	_test_the_button_does_the_other_thing(t)
	_test_action_two_stops_a_kicked_bomb(t)
	_test_a_bomb_on_the_head(t)
	quit(t.finish())


# A bomb is solid to a player. Without this, kicking would be pointless — you
# would simply walk over your own bombs.
func _test_bomb_blocks_player(t: T_) -> void:
	var sim := _sim(1)
	var p: Player_ = sim.players[0]
	p.place_at_tile_centre(2, 5)
	var b := sim.place_bomb(p)
	t.ok(b != null, "a bomb is placed under the player")

	# Step off it, then try to walk back through it.
	p.move = Types_.MoveState.RIGHT
	for _i in 12:
		sim.tick()
	t.ok(p.tile_x() > 2, "the player walks off their own bomb")
	p.move = Types_.MoveState.LEFT
	for _i in 30:
		sim.tick()
	t.eq(p.tile_x(), 3, "and cannot walk back through it")


func _test_kick(t: T_) -> void:
	var speed: int = Values_.V[Const_.Res.KICKED_BOMB_SPEED]
	t.eq(speed, 1000, "a kicked bomb moves at resource 300 = 1000")

	# Without the kicker, walking into a bomb just blocks.
	var sim := _sim(1)
	var p: Player_ = sim.players[0]
	p.place_at_tile_centre(2, 5)
	var b := sim.place_bomb(p)
	b.place_at_tile_centre(4, 5)
	p.move = Types_.MoveState.RIGHT
	for _i in 30:
		sim.tick()
	t.eq(b.tile_x(), 4, "without the kicker the bomb does not move")
	t.eq(p.tile_x(), 3, "and the player is stopped by it")

	# With it, the bomb rolls away.
	var s2 := _sim(1)
	var p2: Player_ = s2.players[0]
	p2.place_at_tile_centre(2, 5)
	s2.give_powerup(p2, Types_.PowerUp.KICK)
	var b2 := s2.place_bomb(p2)
	b2.place_at_tile_centre(4, 5)
	p2.move = Types_.MoveState.RIGHT
	for _i in 6:
		s2.tick()
	t.eq(b2.move_dir, Types_.Dir.RIGHT, "the bomb is kicked rightwards")
	t.eq(b2.speed, speed, "at the tabulated speed")
	var was := b2.tile_x()
	for _i in 10:
		s2.tick()
	t.ok(b2.tile_x() > was, "and it keeps rolling")

	# It stops at a wall, cell-aligned so it can be found again. The fuze is
	# held off rather than running 60 ticks past it — an earlier version of
	# this let the bomb explode and then asserted it was still there.
	for x in range(0, Const_.FIELD_W):
		if x >= 9:
			s2.field.brick[Field_.idx(x, 5)] = Types_.Brick.SOLID
	for _i in 24:
		b2.fuze = Values_.V[Const_.Res.FUZE_FRAMES]
		s2.tick()
	t.eq(b2.move_dir, Types_.Dir.NONE, "the bomb stops at the wall")
	t.eq(b2.tile_x(), 8, "in the last open cell")
	t.eq(b2.x, Bomb_.TILE_W_CP * 8 + Bomb_.TILE_W_CP / 2,
		"cell-aligned, so bomb_at() finds it")
	t.ok(s2.bomb_at(8, 5) != null, "and it does")

	# A rolling bomb is stopped by a player too.
	var s3 := _sim(2)
	var a: Player_ = s3.players[0]
	var blocker: Player_ = s3.players[1]
	a.place_at_tile_centre(2, 7)
	blocker.place_at_tile_centre(7, 7)
	s3.give_powerup(a, Types_.PowerUp.KICK)
	var b3 := s3.place_bomb(a)
	b3.place_at_tile_centre(4, 7)
	a.move = Types_.MoveState.RIGHT
	for _i in 60:
		s3.tick()
	t.ok(b3.tile_x() < 7, "a rolling bomb is stopped by a player")


func _test_jelly(t: T_) -> void:
	var sim := _sim(1)
	var p: Player_ = sim.players[0]
	p.place_at_tile_centre(2, 5)
	sim.give_powerup(p, Types_.PowerUp.KICK)
	sim.give_powerup(p, Types_.PowerUp.JELLY)
	t.ok(p.jelly_bombs, "the player has jelly bombs")

	var b := sim.place_bomb(p)
	b.place_at_tile_centre(4, 5)
	for x in range(9, Const_.FIELD_W):
		sim.field.brick[Field_.idx(x, 5)] = Types_.Brick.SOLID
	p.move = Types_.MoveState.RIGHT
	for _i in 6:
		sim.tick()
	t.ok(b.jelly_bounce, "the kicked bomb is a jelly bomb")

	# It must bounce rather than stop. Run long enough to reach the wall and
	# come back past where it started.
	var bounced := false
	for _i in 200:
		sim.tick()
		if b.move_dir == Types_.Dir.LEFT:
			bounced = true
			break
	t.ok(bounced, "a jelly bomb bounces off the wall instead of stopping")
	t.eq(b.state, Types_.BombState.WOBBLE, "and goes into its wobble state")

	# Resource 667 is the 1-in-3 chance of a crazy turn at an intersection.
	t.eq(Values_.V[Const_.Res.JELLY_TURN_CHANCE], 3,
		"the jelly turn chance is 1-in-3")


func _test_punch(t: T_) -> void:
	t.eq(Values_.V[Const_.Res.PUNCHED_BOMB_SPEED], 1300,
		"a punched bomb moves at resource 301 = 1300")
	t.eq(Values_.V[Const_.Res.PUNCH_ARC_BIG], 65,
		"the initial punch arc is resource 660 = 65")
	t.eq(Values_.V[Const_.Res.PUNCH_ARC_SMALL], 20,
		"the bounce arc is resource 661 = 20")

	# No punch, no effect.
	var sim := _sim(1)
	var p: Player_ = sim.players[0]
	p.place_at_tile_centre(2, 5)
	p.facing = Types_.Dir.RIGHT
	var b := sim.place_bomb(p)
	b.place_at_tile_centre(3, 5)
	t.ok(not sim.punch_bomb(p), "without the glove there is no punch")

	# With it, the bomb flies three cells.
	var s2 := _sim(1)
	var p2: Player_ = s2.players[0]
	p2.place_at_tile_centre(2, 5)
	p2.facing = Types_.Dir.RIGHT
	s2.give_powerup(p2, Types_.PowerUp.PUNCH)
	var b2 := s2.place_bomb(p2)
	b2.place_at_tile_centre(3, 5)
	t.ok(s2.punch_bomb(p2), "the bomb is punched")
	t.ok(b2.flying, "and is in the air")
	t.eq(b2.fly_height, 65, "with the big arc")
	t.eq(b2.tile_x(), 3, "starting where it was")

	# A flying bomb is not on a cell, so a player can walk under it.
	t.ok(s2.bomb_at(3, 5) == null, "a flying bomb is not on the field")

	for _i in 60:
		s2.tick()
		if not b2.flying and b2.bounces_left == 0:
			break
	t.ok(not b2.flying, "it lands")
	t.ok(b2.tile_x() > 3, "further along than it started")

	# Punching resets the fuze — the notes: "bomb timer is reset when its
	# punched".
	var s3 := _sim(1)
	var p3: Player_ = s3.players[0]
	p3.place_at_tile_centre(2, 5)
	p3.facing = Types_.Dir.RIGHT
	s3.give_powerup(p3, Types_.PowerUp.PUNCH)
	var b3 := s3.place_bomb(p3)
	b3.place_at_tile_centre(3, 5)
	b3.fuze = 4
	s3.punch_bomb(p3)
	t.eq(b3.fuze, Values_.V[Const_.Res.FUZE_FRAMES],
		"punching resets the fuze to the full 40 frames")

	# A punch cannot send a bomb off the field.
	var s4 := _sim(1)
	var p4: Player_ = s4.players[0]
	p4.place_at_tile_centre(13, 5)
	p4.facing = Types_.Dir.RIGHT
	s4.give_powerup(p4, Types_.PowerUp.PUNCH)
	var b4 := s4.place_bomb(p4)
	b4.place_at_tile_centre(14, 5)
	s4.punch_bomb(p4)
	for _i in 80:
		s4.tick()
	t.ok(b4.tile_x() >= 0 and b4.tile_x() < Const_.FIELD_W,
		"[invariant] a punched bomb stays on the field")
	t.ok(b4.tile_y() >= 0 and b4.tile_y() < Const_.FIELD_H,
		"[invariant] in both axes")


func _test_grab_and_throw(t: T_) -> void:
	t.eq(Values_.V[Const_.Res.PICKUP_PAUSE_FRAMES], 2,
		"the pickup pause is resource 665 = 2 frames")

	var sim := _sim(1)
	var p: Player_ = sim.players[0]
	p.place_at_tile_centre(5, 5)
	p.facing = Types_.Dir.RIGHT
	var b := sim.place_bomb(p)
	t.ok(not sim.grab_bomb(p), "without the glove there is no grab")

	sim.give_powerup(p, Types_.PowerUp.GRAB)
	t.ok(sim.grab_bomb(p), "with it the bomb is picked up")
	t.eq(b.carried_by, p.slot, "and is carried")
	t.eq(p.pickup_pause, 2, "and the player pauses two frames")

	# A carried bomb is not on the field and its fuze does NOT burn — the
	# notes: "when its picked up its not even ticking".
	t.ok(sim.bomb_at(5, 5) == null, "a carried bomb is not on a cell")
	var fuze_before := b.fuze
	for _i in 20:
		sim.tick()
	t.eq(b.fuze, fuze_before, "a carried bomb's fuze does not burn")

	# It follows the carrier.
	p.move = Types_.MoveState.DOWN
	for _i in 25:
		sim.tick()
	t.eq(b.x, p.x, "the carried bomb tracks its carrier in x")
	t.eq(b.y, p.y, "and in y")

	# Throwing sends it flying and restarts the fuze.
	p.facing = Types_.Dir.RIGHT
	t.ok(sim.bomb_at(p.tile_x(), p.tile_y()) == null,
		"still not on a cell after being carried around")
	t.ok(sim.throw_bomb(p), "the carried bomb is thrown")
	t.eq(b.carried_by, -1, "and is no longer carried")
	t.ok(b.flying, "and is in the air")
	for _i in 60:
		sim.tick()
		if not b.flying:
			break
	t.ok(not b.flying, "it lands")
	t.ok(b.tile_x() > p.tile_x(), "ahead of the thrower")

	# A carrier who dies drops it.
	var s2 := _sim(1)
	var p2: Player_ = s2.players[0]
	p2.place_at_tile_centre(5, 5)
	s2.give_powerup(p2, Types_.PowerUp.GRAB)
	var b2 := s2.place_bomb(p2)
	s2.grab_bomb(p2)
	s2.kill(p2, 1)
	s2.tick()
	t.eq(b2.carried_by, -1, "a dead carrier drops the bomb")


func _test_spooge(t: T_) -> void:
	var sim := _sim(1)
	var p: Player_ = sim.players[0]
	p.place_at_tile_centre(2, 5)
	p.facing = Types_.Dir.RIGHT
	p.bombs_total = 5
	p.bombs_available = 5
	t.eq(sim.spooge(p), 0, "without the spooger nothing happens")

	sim.give_powerup(p, Types_.PowerUp.SPOOGE)
	var placed := sim.spooge(p)
	t.eq(placed, 5, "the spooger places every available bomb")
	t.eq(p.bombs_available, 0, "spending them all")
	# In a line ahead of the player, one per cell.
	for n in range(1, 6):
		t.ok(sim.bomb_at(2 + n, 5) != null,
			"a bomb landed %d cells ahead" % n)

	# A wall stops the line short.
	var s2 := _sim(1)
	var p2: Player_ = s2.players[0]
	p2.place_at_tile_centre(2, 7)
	p2.facing = Types_.Dir.RIGHT
	p2.bombs_total = 8
	p2.bombs_available = 8
	s2.give_powerup(p2, Types_.PowerUp.SPOOGE)
	s2.field.brick[Field_.idx(5, 7)] = Types_.Brick.SOLID
	t.eq(s2.spooge(p2), 2, "a wall three cells away stops the line at two")


func _test_trigger(t: T_) -> void:
	var sim := _sim(1)
	var p: Player_ = sim.players[0]
	p.place_at_tile_centre(5, 5)
	sim.give_powerup(p, Types_.PowerUp.TRIGGER)
	t.ok(p.trigger_bombs > 0, "the trigger grants a stock of bombs")

	var b := sim.place_bomb(p)
	t.ok(b.triggered, "a bomb placed with a trigger waits for the signal")

	# It must NOT go off on its own within the normal fuze.
	for _i in Values_.V[Const_.Res.FUZE_FRAMES] + 20:
		sim.tick()
	t.eq(sim.bombs.size(), 1, "a trigger bomb does not burn down on its own")
	t.ok(not sim.field.has_flame(5, 5), "and has not gone off")

	# The second action fires it.
	t.eq(sim.trigger_bombs(p), 1, "the second action fires it")
	t.ok(sim.field.has_flame(5, 5), "and it explodes on that tick")

	# A flying bomb is not triggerable.
	var s2 := _sim(1)
	var p2: Player_ = s2.players[0]
	p2.place_at_tile_centre(5, 5)
	p2.facing = Types_.Dir.RIGHT
	s2.give_powerup(p2, Types_.PowerUp.TRIGGER)
	var b2 := s2.place_bomb(p2)
	b2.flying = true
	b2.fly_ticks = 10
	t.eq(s2.trigger_bombs(p2), 0, "a flying bomb cannot be triggered")

	# Only your own bombs.
	var s3 := _sim(2)
	var a: Player_ = s3.players[0]
	var other: Player_ = s3.players[1]
	a.place_at_tile_centre(3, 3)
	other.place_at_tile_centre(9, 9)
	s3.give_powerup(a, Types_.PowerUp.TRIGGER)
	s3.give_powerup(other, Types_.PowerUp.TRIGGER)
	s3.place_bomb(a)
	s3.place_bomb(other)
	t.eq(s3.trigger_bombs(a), 1, "a player triggers only their own bombs")


func _test_bomb_diseases(t: T_) -> void:
	# CONSTIPATION: no bombs.
	var sim := _sim(1)
	var p: Player_ = sim.players[0]
	p.place_at_tile_centre(5, 5)
	sim.catch_disease(p, Types_.Disease.CONSTIPATION)
	t.ok(sim.place_bomb(p) == null, "constipation prevents placing a bomb")
	t.eq(p.bombs_available, p.bombs_total, "and does not spend one")
	sim.cure_all(p)
	t.ok(sim.place_bomb(p) != null, "curing it allows bombs again")

	# SHORT_FLAME: reach cut to one.
	var s2 := _sim(1)
	var p2: Player_ = s2.players[0]
	p2.place_at_tile_centre(5, 5)
	s2.give_powerup(p2, Types_.PowerUp.FLAME)
	s2.give_powerup(p2, Types_.PowerUp.FLAME)
	s2.catch_disease(p2, Types_.Disease.SHORT_FLAME)
	var b2 := s2.place_bomb(p2)
	t.eq(b2.flame_len, 1, "short flame cuts the blast to one cell")

	# SHORT_FUZE: goes off much sooner.
	var s3 := _sim(1)
	var p3: Player_ = s3.players[0]
	p3.place_at_tile_centre(5, 5)
	s3.catch_disease(p3, Types_.Disease.SHORT_FUZE)
	var b3 := s3.place_bomb(p3)
	t.ok(b3.fuze < Values_.V[Const_.Res.FUZE_FRAMES],
		"short fuze shortens the fuze")
	t.ok(b3.fuze >= 1, "but never to zero")

	# DUDS: resource 322 is a 1-in-3 chance, 323/324 the wait.
	t.eq(Values_.V[Const_.Res.DUD_CHANCE], 3, "the dud chance is 1-in-3")
	var duds := 0
	for seed_value in 120:
		var s4 := _sim(1, seed_value)
		var p4: Player_ = s4.players[0]
		p4.place_at_tile_centre(5, 5)
		s4.catch_disease(p4, Types_.Disease.DUDS)
		var b4 := s4.place_bomb(p4)
		if b4.state == Types_.BombState.DUD:
			duds += 1
			t.ok(b4.fuze >= Values_.V[Const_.Res.DUD_WAIT_FRAMES],
				"a dud waits at least resource 323 frames")
	t.close(float(duds) / 120.0, 1.0 / 3.0, 0.12,
		"about one bomb in three is a dud (%d of 120)" % duds)


func _test_controls_reversed(t: T_) -> void:
	var sim := _sim(1)
	var p: Player_ = sim.players[0]
	p.place_at_tile_centre(7, 5)
	var start := p.x

	p.move = Types_.MoveState.RIGHT
	sim.tick()
	t.ok(p.x > start, "normally RIGHT moves right")

	var s2 := _sim(1)
	var p2: Player_ = s2.players[0]
	p2.place_at_tile_centre(7, 5)
	var start2 := p2.x
	s2.catch_disease(p2, Types_.Disease.CONTROLS_REVERSED)
	p2.move = Types_.MoveState.RIGHT
	s2.tick()
	t.ok(p2.x < start2, "with controls reversed RIGHT moves left")
	t.eq(p2.facing, Types_.Dir.LEFT, "and the player faces left")


# [invariant] Every ability must stay reproducible from a seed, or the netcode
# assertion and the parity harness both stop meaning anything.
func _test_determinism(t: T_) -> void:
	var traces := []
	for _run in 3:
		var sim := _sim(2, 4242)
		for p in sim.players:
			sim.give_powerup(p, Types_.PowerUp.KICK)
			sim.give_powerup(p, Types_.PowerUp.JELLY)
			sim.give_powerup(p, Types_.PowerUp.PUNCH)
		var trace := PackedInt64Array()
		var script := [Types_.MoveState.RIGHT, Types_.MoveState.DOWN,
			Types_.MoveState.LEFT, Types_.MoveState.UP]
		for tick in 160:
			for i in sim.players.size():
				var action := Types_.Action.NONE
				if tick % 23 == 0:
					action = Types_.Action.FIRST
				elif tick % 31 == 0:
					action = Types_.Action.SECOND
				sim.set_input(i, script[(tick / 9 + i) % 4], action)
			sim.tick()
			trace.append(sim.state_hash())
		traces.append(trace)
	t.eq(traces[0], traces[1], "[invariant] abilities replay identically")
	t.eq(traces[1], traces[2], "[invariant] and again")


# VALUELST 670 AND 671, which the port had named and never used:
#
#     670,1   what's the minimum number of powers you lose when hit on the head?
#     671,3   what's the additional random number of powers you might lose?
#
# and SOUNDLST 360-399 — forty recordings of "you are stunned by a bomb landing
# on you" — is the other half of the evidence. A punched bomb landing on
# somebody did nothing at all.
func _test_a_bomb_on_the_head(t: T_) -> void:
	var sim := _sim(2)
	var thrower: Player_ = sim.players[0]
	var victim: Player_ = sim.players[1]
	t.eq(int(Values_.V[Const_.Res.HEAD_HIT_MIN_LOSS]), 1, "670 is 1")
	t.eq(int(Values_.V[Const_.Res.HEAD_HIT_RAND_LOSS]), 3, "671 is 3")

	# A victim with plenty to lose, and the derived stats that go with them.
	victim.place_at_tile_centre(9, 5)
	for _i in 4:
		sim.give_powerup(victim, Types_.PowerUp.BOMB)
		sim.give_powerup(victim, Types_.PowerUp.FLAME)
	sim.give_powerup(victim, Types_.PowerUp.KICK)
	var held_before: int = _powers_held(victim)
	var bombs_before: int = victim.bombs_total
	var flame_before: int = victim.flame_len
	t.ok(victim.can_kick, "the victim has the kicker")
	t.eq(bombs_before, 5, "and five bombs")
	t.eq(flame_before, 6, "and six of flame")

	# Punched from two cells away, so it lands on them.
	thrower.place_at_tile_centre(5, 5)
	thrower.facing = Types_.Dir.RIGHT
	thrower.can_punch = true
	var b := sim.place_bomb(thrower)
	t.ok(b != null, "a bomb to punch")
	b.place_at_tile_centre(6, 5)
	thrower.place_at_tile_centre(5, 5)
	t.ok(sim.punch_bomb(thrower), "and it is punched")
	t.eq(b.tile_x() + 0, 6, "from cell 6")

	var loose_before: int = _loose_powerups(sim)
	var landed_on_them := false
	for _i in 40:
		sim.tick()
		if not b.flying and b.tile_x() == 9 and b.tile_y() == 5:
			landed_on_them = true
		if b.detonated or b.tile_x() > 9:
			break
	t.ok(landed_on_them or _powers_held(victim) < held_before,
		"the bomb came down on the victim's cell")

	var lost := held_before - _powers_held(victim)
	t.ok(lost >= int(Values_.V[Const_.Res.HEAD_HIT_MIN_LOSS]),
		"at least 670's minimum was lost (%d)" % lost)
	t.ok(lost <= int(Values_.V[Const_.Res.HEAD_HIT_MIN_LOSS])
			+ int(Values_.V[Const_.Res.HEAD_HIT_RAND_LOSS]),
		"and no more than 670 + 671 (%d)" % lost)
	t.eq(_loose_powerups(sim) - loose_before, lost,
		"every one of them went back on the field")

	# AND THE DERIVED STATS FOLLOWED. Losing a bomb powerup that leaves you
	# with the same bomb count is not losing it.
	t.ok(victim.bombs_total <= bombs_before,
		"the bomb count did not go up")
	t.eq(victim.bombs_total,
		int(Values_.V[Const_.Res.BORN_WITH_BASE + Types_.PowerUp.BOMB])
			+ victim.collected[Types_.PowerUp.BOMB],
		"and matches what is still held")
	t.eq(victim.flame_len,
		int(Values_.V[Const_.Res.BORN_WITH_BASE + Types_.PowerUp.FLAME])
			+ victim.collected[Types_.PowerUp.FLAME],
		"and so does the flame length")
	t.eq(victim.can_kick, victim.collected[Types_.PowerUp.KICK] > 0,
		"and the kicker is there exactly while its powerup is")

	# It is deterministic: the same seed loses the same powers.
	var a := _head_hit_loss(1)
	var b2 := _head_hit_loss(1)
	t.eq(a, b2, "the same seed loses the same number")


func _head_hit_loss(round_seed: int) -> int:
	var sim := _sim(2, round_seed)
	var thrower: Player_ = sim.players[0]
	var victim: Player_ = sim.players[1]
	victim.place_at_tile_centre(9, 5)
	for _i in 4:
		sim.give_powerup(victim, Types_.PowerUp.BOMB)
	var before := _powers_held(victim)
	thrower.place_at_tile_centre(5, 5)
	thrower.facing = Types_.Dir.RIGHT
	thrower.can_punch = true
	var b := sim.place_bomb(thrower)
	b.place_at_tile_centre(6, 5)
	thrower.place_at_tile_centre(5, 5)
	sim.punch_bomb(thrower)
	for _i in 40:
		sim.tick()
		if b.detonated or b.tile_x() > 9:
			break
	return before - _powers_held(victim)


static func _powers_held(p: Player_) -> int:
	var n := 0
	for which in Const_.POWERUP_COUNT:
		n += p.collected[which]
	return n


static func _loose_powerups(sim: Sim_) -> int:
	var n := 0
	for y in Const_.FIELD_H:
		for x in Const_.FIELD_W:
			if sim.field.has_powerup(x, y):
				n += 1
	return n


func _sim(count: int, round_seed: int = 1) -> Sim_:
	var lines := PackedStringArray()
	lines.append("-V,2")
	lines.append("-N,Ability fixture (10)")
	lines.append("-B,0")
	for y in Const_.FIELD_H:
		lines.append("-R,%2d,%s" % [y, ".".repeat(Const_.FIELD_W)])
	for p in Const_.PLAYER_COUNT:
		lines.append("-S,%d,%d,%d,%d" % [p, 1 + p, 1 + (p % 8), p % 2])
	for i in Const_.POWERUP_COUNT:
		lines.append("-P,%2d, 0,0, 0, 0,x" % i)
	var s: Scheme_ = Scheme_.new()
	s.parse_text("\n".join(lines), "<abilities>")
	assert(s.ok(), "fixture must parse: %s" % s.error())

	var slots := []
	for i in count:
		slots.append({"slot": i, "team": i % 2})
	var sim: Sim_ = Sim_.new()
	sim.setup(s, slots, round_seed)
	return sim


# ---------------------------------------------------------------------------
# ONE BUTTON, TWO JOBS — MANUAL.BM, on the drop-bomb button:
#
#   "To drop a bomb, press this button. Otherwise, this button is used to drop
#    a Spooge and Grab/Throw a bomb. Press the button again after dropping a
#    bomb to do either if you have the appropriate powerup."
#
# The port used to need a separate FIRST_DOUBLE action for the second job, and
# nothing in the game ever produced one: grab, throw and spooge were reachable
# from a test and from nowhere else.
# ---------------------------------------------------------------------------
func _test_the_button_does_the_other_thing(t: T_) -> void:
	var sim := _sim(1)
	var p: Player_ = sim.players[0]
	p.place_at_tile_centre(5, 5)
	p.can_grab = true

	sim.set_input(0, Types_.MoveState.STILL, Types_.Action.FIRST)
	sim.tick()
	t.eq(sim.bombs.size(), 1, "the first press drops a bomb")
	t.eq(sim.bombs[0].carried_by, -1, "which is on the ground")

	sim.set_input(0, Types_.MoveState.STILL, Types_.Action.FIRST)
	sim.tick()
	t.eq(sim.bombs[0].carried_by, p.slot,
		"and the second press picks it up, with the Blue Hand")

	sim.set_input(0, Types_.MoveState.STILL, Types_.Action.FIRST)
	sim.tick()
	t.ok(sim.bombs[0].flying, "a third press throws it")
	t.ok(_sounds_of(sim).has("BOMB_THROWN"),
		"and the throw is heard: %s" % str(_sounds_of(sim)))

	# Spooge instead, for a player with that powerup rather than the hand.
	var s2 := _sim(1)
	var q: Player_ = s2.players[0]
	q.place_at_tile_centre(5, 5)
	q.can_spooge = true
	q.bombs_available = 5
	s2.set_input(0, Types_.MoveState.STILL, Types_.Action.FIRST)
	s2.tick()
	s2.set_input(0, Types_.MoveState.STILL, Types_.Action.FIRST)
	s2.tick()
	t.ok(s2.bombs.size() > 1,
		"the second press spooges the rest: %d bombs" % s2.bombs.size())

	# With neither powerup the second press simply does nothing, because a
	# bomb is already on that cell.
	var s3 := _sim(1)
	var r: Player_ = s3.players[0]
	r.place_at_tile_centre(5, 5)
	r.bombs_available = 3
	s3.set_input(0, Types_.MoveState.STILL, Types_.Action.FIRST)
	s3.tick()
	s3.set_input(0, Types_.MoveState.STILL, Types_.Action.FIRST)
	s3.tick()
	t.eq(s3.bombs.size(), 1, "one cell, one bomb, whatever is pressed")


# MANUAL.BM again, on the action button: "if your bomberman has the Kick
# powerup, press the action button to stop a kicked bomb."
func _test_action_two_stops_a_kicked_bomb(t: T_) -> void:
	var sim := _sim(1)
	var p: Player_ = sim.players[0]
	p.place_at_tile_centre(5, 5)
	p.can_kick = true
	p.facing = Types_.Dir.RIGHT
	var b = sim.place_bomb(p)
	b.place_at_tile_centre(6, 5)
	t.ok(sim.kick_bomb(p), "the bomb is kicked")
	t.ok(b.move_dir != Types_.Dir.NONE, "and moving")
	t.eq(b.kicked_by, p.slot, "and remembers whose kick it was")
	t.ok(p.kick_ticks > 0, "the kicker plays KICK.ANI for a few ticks")

	sim.tick()
	sim.set_input(0, Types_.MoveState.STILL, Types_.Action.SECOND)
	sim.tick()
	t.eq(b.move_dir, Types_.Dir.NONE, "action 2 stops it where it stands")
	t.ok(_sounds_of(sim).has("BOMB_STOP"),
		"and says so: %s" % str(_sounds_of(sim)))

	# Somebody else's kicked bomb is not yours to stop.
	var s2 := _sim(2)
	var a: Player_ = s2.players[0]
	var c: Player_ = s2.players[1]
	a.place_at_tile_centre(5, 5)
	a.can_kick = true
	a.facing = Types_.Dir.RIGHT
	c.place_at_tile_centre(9, 9)
	c.can_kick = true
	var b2 = s2.place_bomb(a)
	b2.place_at_tile_centre(6, 5)
	s2.kick_bomb(a)
	s2.tick()
	s2.set_input(c.slot, Types_.MoveState.STILL, Types_.Action.SECOND)
	s2.tick()
	t.ok(b2.move_dir != Types_.Dir.NONE,
		"the other player's action does not stop it")


func _sounds_of(sim) -> Array:
	var names := {}
	for key in Types_.SoundEffect.keys():
		names[Types_.SoundEffect[key]] = key
	var out := []
	for ev in sim.sounds:
		out.append(names.get(int(ev["effect"]), "?"))
	return out
