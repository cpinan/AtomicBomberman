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
	_test_hold_to_carry_release_to_throw(t)
	_test_spooge(t)
	_test_trigger(t)
	_test_bomb_diseases(t)
	_test_controls_reversed(t)
	_test_poops(t)
	_test_swap_players(t)
	_test_leprosy(t)
	_test_invisible(t)
	_test_determinism(t)
	_test_the_button_does_the_other_thing(t)
	_test_action_two_stops_a_kicked_bomb(t)
	_test_a_bomb_on_the_head(t)
	_test_kick_needs_contact(t)
	_test_a_blocked_step_never_moves_you_backwards(t)
	_test_pickup_pause_ages_while_standing_still(t)
	_test_a_rolling_bomb_stays_grid_aligned(t)
	_test_disease_passes_by_contact(t)
	_test_a_thrown_bomb_clears_a_wall(t)
	_test_kick_needs_somewhere_to_go(t)
	_test_rekicking_a_rolling_bomb(t)
	_test_jelly_turns_are_quarter_turns(t)
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

	# It must bounce rather than stop. Run until the first bounce, which is
	# what WOBBLE marks — not until a specific direction: a jelly bomb also
	# takes random quarter turns on the way (BM95.EXE 0x423A1E), so which wall
	# it reaches first is not fixed. That it bounces off whatever it reaches,
	# instead of coming to rest the way an ordinary bomb does, is the claim.
	var bounced := false
	for _i in 200:
		sim.tick()
		if b.state == Types_.BombState.WOBBLE:
			bounced = true
			break
	t.ok(bounced, "a jelly bomb bounces off the wall instead of stopping")
	t.ok(b.move_dir != Types_.Dir.NONE, "and is still moving after it")
	# The bounce must SNAP to the cell it bounced off of. Before this was
	# fixed, the half-cell lookahead let the bomb creep right up to the wall
	# and reverse direction from wherever it happened to be, so the sprite
	# visibly sat into the wall for a tick — "goes off the walls then bounces
	# back," from a live playtest.
	t.eq(b.x % Bomb_.TILE_W_CP, Bomb_.TILE_W_CP / 2,
		"the bounce leaves the bomb cell-centred on X")
	t.eq(b.y % Bomb_.TILE_H_CP, Bomb_.TILE_H_CP / 2,
		"the bounce leaves the bomb cell-centred on Y")

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

	# A punch toward an already-occupied cell lands short of it, rather than
	# the two bombs sharing a cell — nothing pinned down what the original
	# does here, so the port stops it the way a rolling bomb already stops:
	# on the nearest open cell. docs/BUGS.md.
	var s5 := _sim(1)
	var p5: Player_ = s5.players[0]
	p5.place_at_tile_centre(2, 5)
	p5.facing = Types_.Dir.RIGHT
	s5.give_powerup(p5, Types_.PowerUp.PUNCH)
	var b5 := s5.place_bomb(p5)
	b5.place_at_tile_centre(3, 5)
	var blocker := Bomb_.new()
	blocker.owner = 0
	blocker.place_at_tile_centre(5, 5)
	s5.bombs.append(blocker)
	s5.punch_bomb(p5)
	t.eq(b5.tile_y(), 5, "still travelling along the row")
	t.ok(b5.tile_x() < 5, "lands short of the occupied cell, not on it")
	for _i in 60:
		s5.tick()
		if not b5.flying and b5.bounces_left == 0:
			break
	t.ok(b5.tile_x() != blocker.tile_x() or b5.tile_y() != blocker.tile_y(),
		"[invariant] two bombs never end up on the same cell")

	# A PUNCHED BOMB FLIES OVER A WALL. MANUAL.BM, on the Wallybomb scheme:
	# "Throw and punch your bombs over the wall to destroy your opponents."
	#
	# This used to assert the opposite — that a punch with the very next cell
	# blocked failed outright — because _landing_cell() walked out one cell at
	# a time and stopped at the first obstacle, so a wall anywhere in the first
	# three cells collapsed the throw to zero distance. That made the bomb drop
	# at the thrower's feet, which an earlier session papered over by refusing
	# the punch entirely. Both the refusal and the assertion were wrong: the
	# arc is supposed to clear the wall.
	var s6 := _sim(1)
	var p6: Player_ = s6.players[0]
	p6.place_at_tile_centre(2, 5)
	p6.facing = Types_.Dir.RIGHT
	s6.give_powerup(p6, Types_.PowerUp.PUNCH)
	var b6 := s6.place_bomb(p6)
	b6.place_at_tile_centre(3, 5)
	s6.field.brick[Field_.idx(4, 5)] = Types_.Brick.SOLID
	t.ok(s6.punch_bomb(p6), "a punch over a wall is allowed")
	t.ok(b6.flying, "and the bomb takes off")
	for _i in 60:
		s6.tick()
		if not b6.flying:
			break
	t.ok(b6.tile_x() > 4, "it lands PAST the wall, not against it")
	t.eq(s6.field.brick[Field_.idx(4, 5)], Types_.Brick.SOLID,
		"and the wall it flew over is untouched")

	# A punch with genuinely nowhere to go — solid all the way to the arena
	# edge — must still fail outright rather than play the animation and the
	# sound over a zero-distance flight. That was a real live report ("the
	# glove doesn't work"), and it stays fixed.
	var s7 := _sim(1)
	var p7: Player_ = s7.players[0]
	p7.place_at_tile_centre(2, 5)
	p7.facing = Types_.Dir.RIGHT
	s7.give_powerup(p7, Types_.PowerUp.PUNCH)
	var b7 := s7.place_bomb(p7)
	b7.place_at_tile_centre(3, 5)
	for x in range(4, Const_.FIELD_W):
		s7.field.brick[Field_.idx(x, 5)] = Types_.Brick.SOLID
	t.ok(not s7.punch_bomb(p7),
		"a punch with nowhere to land at all fails outright")
	t.ok(not b7.flying, "and never takes off")
	t.eq(b7.tile_x(), 3, "staying exactly where it was")


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
	# Grabbing is hold-to-carry now — see _check_hold_to_carry()'s own doc —
	# so the ticks below need the button simulated as still down, or the
	# very next tick would read it as released and throw the bomb.
	p.action_first_held = true

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


## Grab and hold to carry, let go to throw — MANUAL.BM: "you may carry a bomb
## by grabbing and holding down the Drop Bomb button." An earlier version of
## this fix made grab a tap that stayed carried until an explicit second
## press, since the naive hold-required reading dropped the bomb one tick
## after any normal keypress ended (a real press always has the key down at
## the instant its edge fires, so every grab looked hold-required and every
## release looked immediate). That tap-then-tap version wasn't the mechanic
## wanted, confirmed live: holding to carry and releasing to throw is.
## `hold_required_to_carry` is now unconditionally true on every grab, and
## `_check_hold_to_carry()` throws on release instead of dropping in place.
##
## Driven through set_input()/tick() rather than calling
## grab_bomb()/throw_bomb() directly, so this exercises the real dispatch
## path a player's keypresses actually take.
func _test_hold_to_carry_release_to_throw(t: T_) -> void:
	var sim := _sim(1)
	var p: Player_ = sim.players[0]
	p.place_at_tile_centre(5, 5)
	p.facing = Types_.Dir.RIGHT
	sim.give_powerup(p, Types_.PowerUp.GRAB)
	var b := sim.place_bomb(p)
	# The single starting bomb is spent placing it, so place_bomb() cannot
	# succeed again below — every later press falls through to throw or
	# grab, the same way a human out of bombs would see it.
	t.eq(p.bombs_available, 0, "the starting bomb is spent")

	# Grab: an edge, held true the same tick (the key is still down the
	# instant it was pressed).
	sim.set_input(p.slot, Types_.MoveState.STILL, Types_.Action.FIRST, true)
	sim.tick()
	t.eq(b.carried_by, p.slot, "the grab picks it up")

	# Holding, tick after tick, with no new edge: still carried.
	for _i in 10:
		sim.set_input(p.slot, Types_.MoveState.STILL, Types_.Action.NONE,
			true)
		sim.tick()
	t.eq(b.carried_by, p.slot, "holding keeps it carried across many ticks")
	t.ok(not b.flying, "and it never left the hand")

	# Release, with no new press: THROWN, not dropped in place.
	sim.set_input(p.slot, Types_.MoveState.STILL, Types_.Action.NONE, false)
	sim.tick()
	t.eq(b.carried_by, -1, "releasing ends the carry")
	t.ok(b.flying, "and throws it — letting go IS the release action")

	# An explicit second press while STILL holding also throws, without
	# waiting for a release — the fast-tap case, same underlying _throw_carried().
	sim.give_powerup(p, Types_.PowerUp.GRAB)
	sim.set_input(p.slot, Types_.MoveState.STILL, Types_.Action.FIRST, true)
	sim.tick()
	t.eq(b.carried_by, -1, "a second tap throws rather than dropping")
	t.ok(b.flying, "and it is airborne, not just set down")


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


func _test_poops(t: T_) -> void:
	# POOPS forces Action.FIRST every tick, fpc_atomic's dEbola cross-
	# reference (docs/BUGS.md Q1) — the player drops a bomb whenever one is
	# available, whatever their own input said.
	var sim := _sim(1)
	var p: Player_ = sim.players[0]
	p.place_at_tile_centre(5, 5)
	sim.catch_disease(p, Types_.Disease.POOPS)
	t.eq(sim.bombs.size(), 0, "no bomb yet")
	sim.set_input(0, Types_.MoveState.STILL, Types_.Action.NONE)
	sim.tick()
	t.eq(sim.bombs.size(), 1, "a bomb appears with no input at all")


func _test_swap_players(t: T_) -> void:
	var sim := _sim(2)
	var p0: Player_ = sim.players[0]
	var p1: Player_ = sim.players[1]
	p0.place_at_tile_centre(2, 2)
	p1.place_at_tile_centre(9, 8)
	sim.catch_disease(p0, Types_.Disease.SWAP_PLAYERS)
	t.eq(p0.tile_x(), 9, "the catcher lands where the other player was")
	t.eq(p0.tile_y(), 8, "")
	t.eq(p1.tile_x(), 2, "and the other player lands where the catcher was")
	t.eq(p1.tile_y(), 2, "")

	# One-shot: catching it again a moment later does not re-swap on its own,
	# only another catch_disease() call would (has_disease() already refuses
	# a second infection while the first is still running, which _swap_places
	# is never asked to run a second time for).
	var before0 := Vector2i(p0.tile_x(), p0.tile_y())
	sim.tick()
	t.eq(p0.tile_x(), before0.x, "no further movement from the disease itself")
	t.eq(p0.tile_y(), before0.y, "")


func _test_leprosy(t: T_) -> void:
	var sim := _sim(1)
	var p: Player_ = sim.players[0]
	p.place_at_tile_centre(5, 5)
	sim.give_powerup(p, Types_.PowerUp.BOMB)
	sim.give_powerup(p, Types_.PowerUp.FLAME)
	sim.catch_disease(p, Types_.Disease.LEPROSY)
	t.ok(p.collected[Types_.PowerUp.BOMB] > 0
		or p.collected[Types_.PowerUp.FLAME] > 0, "holding something to lose")

	var dropped := false
	for _i in 400:
		p.move = Types_.MoveState.RIGHT
		sim.tick()
		# Walking off the field edge would end the test early; keep it on one
		# cell by re-centring every few ticks instead of letting it wander.
		if p.tile_x() != 5:
			p.place_at_tile_centre(5, 5)
		if p.collected[Types_.PowerUp.BOMB] == 0 \
				and p.collected[Types_.PowerUp.FLAME] == 0:
			dropped = true
			break
	t.ok(dropped, "leprosy eventually drops a held powerup while walking")

	var s2 := _sim(1)
	var p2: Player_ = s2.players[0]
	p2.place_at_tile_centre(5, 5)
	s2.give_powerup(p2, Types_.PowerUp.BOMB)
	s2.catch_disease(p2, Types_.Disease.LEPROSY)
	var before := p2.collected[Types_.PowerUp.BOMB]
	for _i in 100:
		p2.move = Types_.MoveState.STILL
		s2.tick()
	t.eq(p2.collected[Types_.PowerUp.BOMB], before,
		"standing still, nothing falls off")


func _test_invisible(t: T_) -> void:
	# INVISIBLE lives at the view layer (game_view.gd's local_slots +
	# draw_player_of), not the sim — the sim has no notion of "whose screen
	# this is", and no render test covers the view's own skip yet. What a
	# headless test CAN assert is what the sim promises stays true
	# regardless: the disease changes nothing about simulation state, only
	# what a matching viewer draws.
	var sim := _sim(2)
	var p0: Player_ = sim.players[0]
	p0.place_at_tile_centre(5, 5)
	t.ok(sim.catch_disease(p0, Types_.Disease.INVISIBLE), "caught it")
	t.eq(p0.alive, true, "invisibility does not change simulation state")
	t.eq(p0.tile_x(), 5, "the player is still fully present for collision")
	p0.move = Types_.MoveState.RIGHT
	sim.tick()
	t.ok(p0.x > 5 * 4000, "and still moves normally")


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

	# Grabbing is hold-to-carry (_check_hold_to_carry()'s own doc) — a real
	# press has the key down at the instant its edge fires, so `first_held`
	# is true here the same way it would be for an actual keypress.
	sim.set_input(0, Types_.MoveState.STILL, Types_.Action.FIRST, true)
	sim.tick()
	t.eq(sim.bombs[0].carried_by, p.slot,
		"and the second press picks it up, with the Blue Hand")

	sim.set_input(0, Types_.MoveState.STILL, Types_.Action.FIRST, true)
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


## KICK ON CONTACT, NOT ON FACING. MANUAL.BM: "Allows you to kick any bomb
## down a hallway."
##
## The kick test used to run BEFORE the move and ask only "is there a bomb in
## the cell I face" — so it fired on the first tick of the direction key with
## the player still anywhere in their own cell, a full cell of travel short of
## touching the bomb. Live that read as the bomb fleeing before it could be
## reached, and it made the Boxing Glove and the Blue Hand unreachable for a
## player who also held the kicker: turning to face a bomb is the only way to
## aim a punch or a grab, and facing it was enough to kick it away.
func _test_kick_needs_contact(t: T_) -> void:
	var sim := _sim(1)
	var p: Player_ = sim.players[0]
	sim.give_powerup(p, Types_.PowerUp.KICK)
	var b := sim.place_bomb(p)
	b.place_at_tile_centre(5, 5)
	# Standing in the cell next door, on its FAR side. The collision box is a
	# whole cell wide, so the flush line against the bomb's cell IS the centre
	# of this one — anywhere to the right of that centre is clear floor the
	# player still has to cross before touching anything.
	p.place_at_tile_centre(6, 5)
	p.x += 1500
	var start_x := p.x
	t.eq(p.tile_x(), 6, "the player starts in the cell next to the bomb")
	t.ok(p.speed < 1500, "and more than one step short of the bomb")
	p.move = Types_.MoveState.LEFT
	sim.tick()
	t.eq(b.move_dir, Types_.Dir.NONE,
		"merely facing the bomb from a cell away does not kick it")
	t.ok(p.x < start_x, "the player walks toward it instead")
	# Keep walking: the moment the step is capped by the bomb, it goes.
	for _i in 10:
		sim.tick()
		if b.move_dir != Types_.Dir.NONE:
			break
	t.eq(b.move_dir, Types_.Dir.LEFT, "walking INTO it kicks it")
	t.eq(b.speed, int(Values_.V[Const_.Res.KICKED_BOMB_SPEED]),
		"at the tabulated speed")


## A blocked step must never move the player the way they are NOT pressing.
##
## _slide_x()/_slide_y() return the position flush against the blocked cell,
## which is BEHIND a player who is already standing past that line — walk off
## the cell you just bombed, turn back, and the flush position is a step in
## the direction you let go of. Holding left slid you right.
func _test_a_blocked_step_never_moves_you_backwards(t: T_) -> void:
	var sim := _sim(1)
	var p: Player_ = sim.players[0]
	var b := sim.place_bomb(p)
	b.place_at_tile_centre(5, 5)
	# Part-way into the cell to the right of the bomb, past the flush line.
	p.place_at_tile_centre(6, 5)
	p.x += 1000
	var start_x := p.x
	p.move = Types_.MoveState.LEFT
	sim.tick()
	t.ok(p.x <= start_x, "pressing left never moves the player right")
	for _i in 20:
		sim.tick()
	t.ok(p.x <= start_x, "and it still does not, tick after tick")
	# Same on the vertical axis, where the flush line is the other sign.
	var s2 := _sim(1)
	var p2: Player_ = s2.players[0]
	var b2 := s2.place_bomb(p2)
	b2.place_at_tile_centre(5, 5)
	p2.place_at_tile_centre(5, 6)
	p2.y += 900
	var start_y := p2.y
	p2.move = Types_.MoveState.UP
	for _i in 20:
		s2.tick()
	t.ok(p2.y <= start_y, "pressing up never moves the player down")


## Resource 665's pickup freeze has to age out for a player who is standing
## still, not only for one who walks.
##
## The countdown used to live inside _move_player(), which returns early for
## a STILL player — so a grab made standing still left pickup_pause stuck at
## its starting value forever. game_view.gd draws BPICKUP.ANI's pickup pose
## while it is above zero, AHEAD of the carrying pose, and draw_bombs_of()
## skips a carried bomb entirely: the bomb vanished and the player froze
## mid-pickup. That is what "the blue glove does nothing" looked like.
func _test_pickup_pause_ages_while_standing_still(t: T_) -> void:
	var sim := _sim(1)
	var p: Player_ = sim.players[0]
	p.place_at_tile_centre(5, 5)
	p.facing = Types_.Dir.RIGHT
	sim.give_powerup(p, Types_.PowerUp.GRAB)
	var b := sim.place_bomb(p)
	sim.set_input(p.slot, Types_.MoveState.STILL, Types_.Action.FIRST, true)
	sim.tick()
	t.eq(b.carried_by, p.slot, "the grab picks it up")
	t.ok(p.pickup_pause > 0, "and starts the pickup freeze")
	var pause: int = int(Values_.V[Const_.Res.PICKUP_PAUSE_FRAMES])
	for _i in pause + 4:
		sim.set_input(p.slot, Types_.MoveState.STILL, Types_.Action.NONE, true)
		sim.tick()
	t.eq(p.pickup_pause, 0,
		"the freeze ends even though the player never moved")
	t.eq(b.carried_by, p.slot, "and the bomb is still being carried")


## A rolling bomb that turns must snap to the intersection it turns at.
##
## _at_cell_centre() is a tolerance — "within half a step" — so a bomb that
## turned kept up to half a step of error on the axis it was now crossing, and
## every later turn added its own. A jelly bomb doing its 1-in-3 crazy turns
## drifted off the grid within a few bounces and its tile_x()/tile_y() flipped
## a tick out of step with what the player could see, which is what made its
## bounces look random.
func _test_a_rolling_bomb_stays_grid_aligned(t: T_) -> void:
	var worst := 0
	for round_seed in [1, 2, 3, 4, 5, 6]:
		var sim := _sim(1, round_seed)
		var p: Player_ = sim.players[0]
		p.place_at_tile_centre(5, 5)
		sim.give_powerup(p, Types_.PowerUp.KICK)
		sim.give_powerup(p, Types_.PowerUp.JELLY)
		var b := sim.place_bomb(p)
		b.place_at_tile_centre(6, 5)
		b.fuze = 100000        # outlive the roll: this is about position only
		p.move = Types_.MoveState.RIGHT
		for _i in 80:
			sim.tick()
			if b.detonated:
				break
			# While rolling along one axis the bomb must sit exactly on the
			# centre line of the other.
			if b.move_dir == Types_.Dir.LEFT or b.move_dir == Types_.Dir.RIGHT:
				worst = maxi(worst, absi(b.y % Bomb_.TILE_H_CP
					- Bomb_.TILE_H_CP / 2))
			elif b.move_dir == Types_.Dir.UP or b.move_dir == Types_.Dir.DOWN:
				worst = maxi(worst, absi(b.x % Bomb_.TILE_W_CP
					- Bomb_.TILE_W_CP / 2))
	t.eq(worst, 0, "a jelly bomb never drifts off the grid as it turns")


## A DISEASE PASSES BY CONTACT, from a real tick().
##
## MANUAL.BM says it from the player's side — "Good disease strategies often
## involve passing the disease to as many opponents as possible" — and
## VALUELST backs it with two resources that exist for nothing else:
## DISEASE_FRESHNESS, "frames before it can pass again", and
## DISEASE_MULTIPLIES. spread_disease() was written for this and then called
## from nowhere but its own unit test, so in a real match a disease could only
## ever be caught off a skull on the field, never off another player.
func _test_disease_passes_by_contact(t: T_) -> void:
	var sim := _sim(2)
	var a: Player_ = sim.players[0]
	var b: Player_ = sim.players[1]
	a.place_at_tile_centre(5, 5)
	b.place_at_tile_centre(9, 5)
	t.ok(sim.catch_disease(a, Types_.Disease.POOPS), "one player is diseased")
	t.ok(not b.has_disease(Types_.Disease.POOPS), "the other is not, yet")

	# Apart: nothing crosses, however long they stand there.
	for _i in int(Values_.V[Const_.Res.DISEASE_FRESHNESS]) + 5:
		sim.tick()
	t.ok(not b.has_disease(Types_.Disease.POOPS),
		"standing apart passes nothing")

	# Same tile: it crosses.
	b.place_at_tile_centre(a.tile_x(), a.tile_y())
	sim.tick()
	t.ok(b.has_disease(Types_.Disease.POOPS),
		"touching a diseased player catches it")


## A THROWN bomb clears a wall too — the blue glove's half of MANUAL.BM's
## "Throw and punch your bombs over the wall to destroy your opponents."
## Throw and punch share _landing_cell(), so this and the punch case above
## stand or fall together; both are here because both were reported live.
func _test_a_thrown_bomb_clears_a_wall(t: T_) -> void:
	var sim := _sim(1)
	var p: Player_ = sim.players[0]
	p.place_at_tile_centre(2, 5)
	p.facing = Types_.Dir.RIGHT
	sim.give_powerup(p, Types_.PowerUp.GRAB)
	var b := sim.place_bomb(p)
	sim.field.brick[Field_.idx(3, 5)] = Types_.Brick.SOLID
	sim.set_input(p.slot, Types_.MoveState.STILL, Types_.Action.FIRST, true)
	sim.tick()
	t.eq(b.carried_by, p.slot, "the bomb is picked up")
	# Let go: it is thrown, and the wall in the very next cell must not
	# collapse the throw to zero distance the way it used to.
	sim.set_input(p.slot, Types_.MoveState.STILL, Types_.Action.NONE, false)
	sim.tick()
	t.ok(b.flying, "releasing throws it")
	for _i in 60:
		sim.tick()
		if not b.flying:
			break
	t.ok(b.tile_x() > 3, "and it lands PAST the wall, not at the thrower's feet")
	t.eq(sim.field.brick[Field_.idx(3, 5)], Types_.Brick.SOLID,
		"the wall it flew over is untouched")


## A BOMB WITH NOWHERE TO ROLL IS NOT KICKED — BM95.EXE 0x41EEAC.
##
## The original computes the bomb's cell plus the same direction again and
## calls its "is this cell free" predicate (0x41E5C3: no bomb there AND the
## cell itself empty) before kicking at all. This port kicked regardless, so a
## bomb flat against a wall played the kick sound and animation over a bomb
## that could not move — and, because aiming a glove means facing the bomb, it
## removed the one case where the Boxing Glove is usable by a player who also
## holds the kicker. MANUAL.BM's Wallybomb advice is exactly that case.
func _test_kick_needs_somewhere_to_go(t: T_) -> void:
	# A wall directly behind the bomb: no kick, the player is simply blocked.
	var sim := _sim(1)
	var p: Player_ = sim.players[0]
	p.place_at_tile_centre(4, 5)
	sim.give_powerup(p, Types_.PowerUp.KICK)
	var b := sim.place_bomb(p)
	b.place_at_tile_centre(5, 5)
	sim.field.brick[Field_.idx(6, 5)] = Types_.Brick.SOLID
	p.move = Types_.MoveState.RIGHT
	for _i in 12:
		sim.tick()
	t.eq(b.move_dir, Types_.Dir.NONE,
		"a bomb with a wall behind it is not kicked")
	t.eq(b.tile_x(), 5, "and it has not moved")
	t.eq(p.kick_ticks, 0, "no kick animation plays either")

	# Another BOMB behind it counts as blocked too — 0x41E5C3 tests for a bomb
	# before it tests the cell.
	var s2 := _sim(1)
	var p2: Player_ = s2.players[0]
	p2.place_at_tile_centre(4, 5)
	s2.give_powerup(p2, Types_.PowerUp.KICK)
	s2.give_powerup(p2, Types_.PowerUp.BOMB)
	var near := s2.place_bomb(p2)
	near.place_at_tile_centre(5, 5)
	var far := s2.place_bomb(p2)
	far.place_at_tile_centre(6, 5)
	p2.move = Types_.MoveState.RIGHT
	for _i in 12:
		s2.tick()
	t.eq(near.move_dir, Types_.Dir.NONE,
		"a bomb with another bomb behind it is not kicked")

	# Clear floor behind it: kicked, as before.
	var s3 := _sim(1)
	var p3: Player_ = s3.players[0]
	p3.place_at_tile_centre(4, 5)
	s3.give_powerup(p3, Types_.PowerUp.KICK)
	var b3 := s3.place_bomb(p3)
	b3.place_at_tile_centre(5, 5)
	p3.move = Types_.MoveState.RIGHT
	for _i in 12:
		s3.tick()
	t.eq(b3.move_dir, Types_.Dir.RIGHT,
		"with clear floor behind it, the kick still happens")


## RE-KICKING A ROLLING BOMB — BM95.EXE 0x42464B.
##
## The original's kick_bomb() tests "already moving" against "direction
## differs" and, when both hold, rewrites the bomb's x and y to the centre of
## the tile it is on before taking the new direction. This port refused to
## kick a moving bomb at all (it required at_rest()), so a bomb could never be
## turned once rolling.
func _test_rekicking_a_rolling_bomb(t: T_) -> void:
	var sim := _sim(1)
	var p: Player_ = sim.players[0]
	p.place_at_tile_centre(4, 5)
	sim.give_powerup(p, Types_.PowerUp.KICK)
	var b := sim.place_bomb(p)
	b.place_at_tile_centre(5, 5)
	b.fuze = 100000
	p.move = Types_.MoveState.RIGHT
	for _i in 12:
		sim.tick()
	t.eq(b.move_dir, Types_.Dir.RIGHT, "rolling right")

	# Catch it from below and kick it upward: it must turn, and land exactly
	# on the grid rather than carrying its mid-cell offset into the new axis.
	p.place_at_tile_centre(b.tile_x(), b.tile_y() + 1)
	p.facing = Types_.Dir.UP
	t.ok(sim.kick_bomb(p), "a rolling bomb can be kicked again")
	t.eq(b.move_dir, Types_.Dir.UP, "and it takes the new direction")
	t.eq(b.x % Bomb_.TILE_W_CP, Bomb_.TILE_W_CP / 2,
		"snapped to the cell centre in x")
	t.eq(b.y % Bomb_.TILE_H_CP, Bomb_.TILE_H_CP / 2,
		"snapped to the cell centre in y")


## A JELLY BOMB'S CRAZY TURN IS A QUARTER TURN — BM95.EXE 0x423A1E:
##
##     rand() % 2 -> {0, 1}, doubled -> {0, 2}
##     dir = (dir + {0,2} - 1) & 3
##
## which over the original's 0..3 direction encoding is "ninety degrees one way
## or the other". It cannot reverse and it cannot carry straight on. This port
## picked freely among all four directions filtered by what was unblocked, so
## it produced both of the outcomes the original cannot.
func _test_jelly_turns_are_quarter_turns(t: T_) -> void:
	# The rule itself, exhaustively. Both choices, every direction, always
	# perpendicular and never the reverse.
	for dir in [Types_.Dir.UP, Types_.Dir.DOWN, Types_.Dir.LEFT,
			Types_.Dir.RIGHT]:
		var a: int = Sim_._quarter_turn(dir, true)
		var b: int = Sim_._quarter_turn(dir, false)
		t.ok(a != dir and b != dir, "a quarter turn never keeps the heading")
		t.ok(a != Sim_._opposite(dir) and b != Sim_._opposite(dir),
			"and never reverses it")
		t.ok(a != b, "the two choices are distinct")
		# Perpendicular means the dot product of the step vectors is zero.
		var v0: Vector2i = Types_.DIR_VEC[dir]
		var va: Vector2i = Types_.DIR_VEC[a]
		t.eq(v0.x * va.x + v0.y * va.y, 0, "and is perpendicular")

	# And in play: a jelly bomb rolling across open floor never doubles back
	# without bouncing off something first.
	for round_seed in [1, 2, 3, 4, 5, 6, 7, 8]:
		var sim := _sim(1, round_seed)
		var p: Player_ = sim.players[0]
		p.place_at_tile_centre(1, 5)
		sim.give_powerup(p, Types_.PowerUp.KICK)
		sim.give_powerup(p, Types_.PowerUp.JELLY)
		var bomb := sim.place_bomb(p)
		bomb.place_at_tile_centre(2, 5)
		bomb.fuze = 100000
		p.move = Types_.MoveState.RIGHT
		var prev := Types_.Dir.NONE
		for _i in 20:
			sim.tick()
			if bomb.move_dir == Types_.Dir.NONE:
				break
			if prev != Types_.Dir.NONE and bomb.move_dir != prev \
					and bomb.state != Types_.BombState.WOBBLE:
				var pv: Vector2i = Types_.DIR_VEC[prev]
				var nv: Vector2i = Types_.DIR_VEC[bomb.move_dir]
				t.eq(pv.x * nv.x + pv.y * nv.y, 0,
					"seed %d: every mid-roll turn is a quarter turn" % round_seed)
			prev = bomb.move_dir
