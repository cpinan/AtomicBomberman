# Bombs, flame, chain reactions and death.
#
# Every timing here is a frame count straight out of the original's tuning
# table, used as a tick count with no conversion — which is the whole point of
# simulating at the original's own 20 Hz. Resource 41 is a 40-frame fuze, so the
# assertion is "on tick 40", not "at about 2 seconds".
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
	var t := T_.new("bomb")
	_test_placement(t)
	_test_fuze_timing(t)
	_test_flame_shape(t)
	_test_flame_stops(t)
	_test_brick_destruction(t)
	_test_bomb_budget(t)
	_test_properties_fixed_at_drop(t)
	_test_chain(t)
	_test_death(t)
	_test_kill_tally(t)
	_test_cornerhead(t)
	quit(t.finish())


func _test_placement(t: T_) -> void:
	var sim := _sim(1)
	var p: Player_ = sim.players[0]
	p.place_at_tile_centre(5, 5)

	var b = sim.place_bomb(p)
	t.ok(b != null, "a bomb is placed")
	t.eq(b.tile_x(), 5, "placed on the player's column")
	t.eq(b.tile_y(), 5, "placed on the player's row")
	t.eq(b.owner, p.slot, "the placer owns it")
	t.eq(b.chain_owner, p.slot, "and starts its own chain")
	t.eq(b.fuze, Values_.V[Const_.Res.FUZE_FRAMES], "fuze is resource 41 ticks")
	t.eq(sim.bombs.size(), 1, "one bomb on the field")

	# One bomb per cell.
	p.bombs_available = 5
	t.ok(sim.place_bomb(p) == null, "a second bomb on the same cell is refused")
	t.eq(sim.bombs.size(), 1, "still one bomb")

	# Off-centre placement still lands on the cell the player is standing in.
	var sim2 := _sim(1)
	var p2: Player_ = sim2.players[0]
	p2.place_at_tile_centre(3, 3)
	p2.x += 1900   # nearly at the edge of the cell, but still inside it
	var b2 = sim2.place_bomb(p2)
	t.eq(b2.tile_x(), 3, "an off-centre player still bombs their own cell")
	t.eq(b2.tile_y(), 3, "and its row")

	# Placement through the input path, not just the direct call.
	var sim3 := _sim(1)
	sim3.players[0].place_at_tile_centre(4, 4)
	sim3.set_input(0, Types_.MoveState.STILL, Types_.Action.FIRST)
	sim3.tick()
	t.eq(sim3.bombs.size(), 1, "Action.FIRST places a bomb")
	t.eq(sim3.players[0].action, Types_.Action.NONE,
		"the action is consumed, so one press is one bomb")
	sim3.tick()
	t.eq(sim3.bombs.size(), 1, "a held action does not place a second bomb")

	# The two placement paths must agree on when the fuze runs out. They did
	# not: a bomb dropped through the input path used to burn a tick that a
	# directly-placed bomb did not, so it went off one tick early.
	var fuze: int = Values_.V[Const_.Res.FUZE_FRAMES]

	var via_input := _sim(1)
	via_input.players[0].place_at_tile_centre(4, 4)
	via_input.set_input(0, Types_.MoveState.STILL, Types_.Action.FIRST)
	via_input.tick()                      # placed on tick 1
	t.eq(via_input.bombs.size(), 1, "placed through the input path")
	_run(via_input, fuze - 1)
	t.eq(via_input.bombs.size(), 1, "still ticking one tick short of the fuze")
	via_input.tick()
	t.eq(via_input.bombs.size(), 0, "goes off exactly 40 ticks after the drop")
	t.eq(via_input.tick_count, 1 + fuze, "which is placement tick + 40")

	var via_call := _sim(1)
	via_call.players[0].place_at_tile_centre(4, 4)
	via_call.tick()                       # burn a tick first, to match
	via_call.place_bomb(via_call.players[0])
	_run(via_call, fuze - 1)
	t.eq(via_call.bombs.size(), 1, "direct placement also still ticking")
	via_call.tick()
	t.eq(via_call.bombs.size(), 0, "and also goes off after exactly 40 ticks")
	t.eq(via_call.tick_count, via_input.tick_count,
		"both placement paths detonate on the same tick")


# The fuze is 40 ticks: still there on tick 39, gone on tick 40.
func _test_fuze_timing(t: T_) -> void:
	var fuze: int = Values_.V[Const_.Res.FUZE_FRAMES]
	var flame_ticks: int = Values_.V[Const_.Res.FLAME_ANIM_FRAMES]

	var sim := _sim(1)
	var p: Player_ = sim.players[0]
	p.place_at_tile_centre(5, 5)
	sim.place_bomb(p)

	for i in fuze - 1:
		sim.tick()
		t.ok(sim.bombs.size() == 1, "bomb still ticking on tick %d" % (i + 1))
		t.ok(not sim.field.has_flame(5, 5), "no flame yet on tick %d" % (i + 1))

	sim.tick()
	t.eq(sim.tick_count, fuze, "detonation is on tick 40")
	t.eq(sim.bombs.size(), 0, "the bomb is gone")
	t.ok(sim.field.has_flame(5, 5), "the epicentre is burning")

	# Resource 10 says the flame animation is 10 frames, so the flame must be
	# visible on exactly 10 ticks: the detonation tick and the nine after it.
	# Stated as the duration the tuning table specifies, NOT as whatever the
	# implementation happens to produce — an earlier version of this assertion
	# was written to match the code and hid a nine-tick flame.
	for i in flame_ticks - 1:
		sim.tick()
		t.ok(sim.field.has_flame(5, 5),
			"flame still burning on tick %d of %d" % [i + 2, flame_ticks])
	t.eq(sim.tick_count, fuze + flame_ticks - 1, "ten ticks of flame have run")
	sim.tick()
	t.ok(not sim.field.has_flame(5, 5),
		"flame is out on the tick after its %d frames" % flame_ticks)
	t.eq(sim.field.flaming_cells(), 0, "no flame anywhere")


# A cross of flame_len cells in each of four directions, plus the epicentre.
func _test_flame_shape(t: T_) -> void:
	for reach in [1, 2, 3, 5]:
		var sim := _sim(1)
		var p: Player_ = sim.players[0]
		p.place_at_tile_centre(7, 5)
		p.flame_len = reach
		sim.place_bomb(p)
		_run(sim, Values_.V[Const_.Res.FUZE_FRAMES])

		t.ok(sim.field.has_flame(7, 5), "reach %d: epicentre burns" % reach)
		for n in range(1, reach + 1):
			t.ok(sim.field.has_flame(7 - n, 5), "reach %d: %d cells left" % [reach, n])
			t.ok(sim.field.has_flame(7 + n, 5), "reach %d: %d cells right" % [reach, n])
			t.ok(sim.field.has_flame(7, 5 - n), "reach %d: %d cells up" % [reach, n])
			t.ok(sim.field.has_flame(7, 5 + n), "reach %d: %d cells down" % [reach, n])
		# And exactly one cell beyond the reach is clear.
		t.ok(not sim.field.has_flame(7 - reach - 1, 5),
			"reach %d: stops after %d cells left" % [reach, reach])
		t.ok(not sim.field.has_flame(7 + reach + 1, 5),
			"reach %d: stops after %d cells right" % [reach, reach])
		t.eq(sim.field.flaming_cells(), 1 + 4 * reach,
			"reach %d: exactly 1 + 4*%d cells burn" % [reach, reach])

	# EVERY CELL OF AN ARM SAYS WHICH ARM IT IS, and the last one also says it
	# is the last. The view has nine sequences to choose between — a centre, a
	# mid and a tip for each of four directions — and it chooses by these bits.
	#
	# The END bit used to be written INSTEAD of the direction, so the last cell
	# of every arm carried END alone, the view had no direction to read, and it
	# fell through to the centre sprite: every arm ended in a second epicentre
	# and MFLAME.ANI's four `flame tip<dir> green` sequences were never drawn.
	var shape := _sim(1)
	var sp: Player_ = shape.players[0]
	sp.place_at_tile_centre(7, 5)
	sp.flame_len = 3
	shape.place_bomb(sp)
	_run(shape, Values_.V[Const_.Res.FUZE_FRAMES])

	t.ok(shape.field.flame_at(7, 5) & Types_.Flame.CROSS,
		"the epicentre is a centre")
	t.ok(not (shape.field.flame_at(7, 5) & Types_.Flame.END),
		"and not an end")
	var arms := {
		Types_.Flame.LEFT: Vector2i(-1, 0),
		Types_.Flame.RIGHT: Vector2i(1, 0),
		Types_.Flame.UP: Vector2i(0, -1),
		Types_.Flame.DOWN: Vector2i(0, 1),
	}
	for bit in arms:
		var step: Vector2i = arms[bit]
		for n in range(1, 4):
			var cell := Vector2i(7, 5) + step * n
			var bits: int = shape.field.flame_at(cell.x, cell.y)
			t.ok(bits & bit,
				"cell %s carries the arm's own direction bit" % cell)
			t.eq((bits & Types_.Flame.END) != 0, n == 3,
				"and the END bit on the last cell of the arm only (%s)" % cell)

	# An arm that stops on a BRICK ends there too — that cell is a tip, not a
	# middle running off the edge of the rubble.
	var wall := _sim(1)
	var wp: Player_ = wall.players[0]
	wp.place_at_tile_centre(7, 5)
	wp.flame_len = 4
	wall.field.brick[Field_.idx(9, 5)] = Types_.Brick.BRICK
	wall.place_bomb(wp)
	_run(wall, Values_.V[Const_.Res.FUZE_FRAMES])
	t.ok(wall.field.flame_at(9, 5) & Types_.Flame.RIGHT,
		"the brick's cell is part of the right arm")
	t.ok(wall.field.flame_at(9, 5) & Types_.Flame.END,
		"and is where that arm ends")
	t.ok(not (wall.field.flame_at(8, 5) & Types_.Flame.END),
		"the cell before it is not")

	# A bomb in a corner clips off-field arms without erroring.
	var corner := _sim(1)
	var cp: Player_ = corner.players[0]
	cp.place_at_tile_centre(0, 0)
	cp.flame_len = 3
	corner.place_bomb(cp)
	_run(corner, Values_.V[Const_.Res.FUZE_FRAMES])
	t.ok(corner.field.has_flame(0, 0), "a corner bomb burns its own cell")
	t.eq(corner.field.flaming_cells(), 1 + 3 + 3,
		"a corner bomb's two off-field arms are clipped")


func _test_flame_stops(t: T_) -> void:
	# A solid stops the arm and does NOT burn.
	var sim := _sim(1)
	var p: Player_ = sim.players[0]
	p.place_at_tile_centre(5, 5)
	p.flame_len = 4
	sim.field.brick[Field_.idx(7, 5)] = Types_.Brick.SOLID
	sim.place_bomb(p)
	_run(sim, Values_.V[Const_.Res.FUZE_FRAMES])
	t.ok(sim.field.has_flame(6, 5), "flame reaches the cell before the solid")
	t.ok(not sim.field.has_flame(7, 5), "a solid does not burn")
	t.ok(not sim.field.has_flame(8, 5), "and the arm stops there")

	# A brick DOES burn, and stops the arm.
	var s2 := _sim(1)
	var p2: Player_ = s2.players[0]
	p2.place_at_tile_centre(5, 5)
	p2.flame_len = 4
	s2.field.brick[Field_.idx(7, 5)] = Types_.Brick.BRICK
	s2.place_bomb(p2)
	_run(s2, Values_.V[Const_.Res.FUZE_FRAMES])
	t.ok(s2.field.has_flame(7, 5), "a brick burns")
	t.ok(not s2.field.has_flame(8, 5), "and stops the arm")

	# A powerup stops the arm and is destroyed. AtomBomberman's notes: flames
	# "are stopped by blocks (indestructible & destructible) and by powerups".
	var s3 := _sim(1)
	var p3: Player_ = s3.players[0]
	p3.place_at_tile_centre(5, 5)
	p3.flame_len = 4
	s3.field.powerup[Field_.idx(7, 5)] = Types_.PowerUp.KICK
	s3.place_bomb(p3)
	_run(s3, Values_.V[Const_.Res.FUZE_FRAMES])
	t.ok(s3.field.has_flame(7, 5), "the powerup's cell burns")
	t.ok(not s3.field.has_flame(8, 5), "a powerup stops the arm")
	t.eq(s3.field.powerup[Field_.idx(7, 5)], Field_.NO_POWERUP,
		"the powerup is destroyed")

	# A powerup on the BOMB'S OWN TILE — the epicentre — burns too. A live
	# player can't normally leave one under themselves (_collect_powerup()
	# picks it up the same tick), but a scattered pickup can land there after
	# the bomb is already down. _propagate()'s arm loop starts one cell OUT
	# and never looked at the epicentre at all.
	var s4 := _sim(1)
	var p4: Player_ = s4.players[0]
	p4.place_at_tile_centre(5, 5)
	s4.place_bomb(p4)
	s4.field.powerup[Field_.idx(5, 5)] = Types_.PowerUp.KICK
	_run(s4, Values_.V[Const_.Res.FUZE_FRAMES])
	t.eq(s4.field.powerup[Field_.idx(5, 5)], Field_.NO_POWERUP,
		"a powerup on the epicentre is destroyed too")


func _test_brick_destruction(t: T_) -> void:
	var sim := _sim(1)
	var p: Player_ = sim.players[0]
	p.place_at_tile_centre(1, 1)
	p.flame_len = 2
	sim.field.brick[Field_.idx(2, 1)] = Types_.Brick.BRICK
	sim.field.brick[Field_.idx(3, 1)] = Types_.Brick.BRICK
	sim.place_bomb(p)
	_run(sim, Values_.V[Const_.Res.FUZE_FRAMES])

	t.ok(sim.field.is_open(2, 1), "the first brick is destroyed")
	# The second is shielded by the first, even though it is within reach.
	t.ok(not sim.field.is_open(3, 1),
		"the brick behind it survives — one brick stops the arm")
	t.eq(sim.field.brick_timer[Field_.idx(2, 1)],
		Values_.V[Const_.Res.BRICK_ANIM_FRAMES],
		"disintegration is set to the full resource 20 frames, not one less")


func _test_bomb_budget(t: T_) -> void:
	var sim := _sim(1)
	var p: Player_ = sim.players[0]
	p.place_at_tile_centre(5, 5)
	p.bombs_total = 2
	p.bombs_available = 2

	sim.place_bomb(p)
	t.eq(p.bombs_available, 1, "placing spends one bomb")
	p.place_at_tile_centre(7, 5)
	sim.place_bomb(p)
	t.eq(p.bombs_available, 0, "and the second")
	p.place_at_tile_centre(9, 5)
	t.ok(sim.place_bomb(p) == null, "no bombs left, so no third")

	_run(sim, Values_.V[Const_.Res.FUZE_FRAMES])
	t.eq(p.bombs_available, 2, "both come back when they go off")
	t.ok(p.bombs_available <= p.bombs_total,
		"[invariant] available never exceeds the total")

	# A player with zero bombs — the "no bombs" disease state — places none.
	var s2 := _sim(1)
	var p2: Player_ = s2.players[0]
	p2.bombs_available = 0
	t.ok(s2.place_bomb(p2) == null, "a player with no bombs places none")


# Bomb properties are fixed at DROP time, not at explode time. From
# AtomBomberman's notes, and it is a real gameplay rule: picking up a flame
# after dropping must not lengthen that bomb's blast.
func _test_properties_fixed_at_drop(t: T_) -> void:
	var sim := _sim(1)
	var p: Player_ = sim.players[0]
	p.place_at_tile_centre(7, 5)
	p.flame_len = 1
	var b = sim.place_bomb(p)
	t.eq(b.flame_len, 1, "the bomb took the reach it was dropped with")

	# Now "collect" a flame powerup and let the bomb go off.
	p.flame_len = 5
	_run(sim, Values_.V[Const_.Res.FUZE_FRAMES])
	t.ok(sim.field.has_flame(6, 5), "the bomb's one cell of reach burns")
	t.ok(not sim.field.has_flame(5, 5),
		"a flame collected after the drop does not lengthen that bomb")
	t.eq(sim.field.flaming_cells(), 5, "still a 1-reach cross")


# A flame reaching a bomb sets it off in the SAME tick, and the chain's
# originating owner carries through however long the chain is — so the player
# who started it gets the kill. AtomBomberman's notes and fpc_atomic 0.11006.
func _test_chain(t: T_) -> void:
	var sim := _sim(2)
	var a: Player_ = sim.players[0]
	var b: Player_ = sim.players[1]

	a.place_at_tile_centre(2, 5)
	a.flame_len = 2
	b.place_at_tile_centre(4, 5)
	b.flame_len = 2

	var bomb_a = sim.place_bomb(a)
	var bomb_b = sim.place_bomb(b)
	# Slow B's fuze right down, so only a chain can set it off in time.
	bomb_b.fuze = 500

	_run(sim, Values_.V[Const_.Res.FUZE_FRAMES])
	t.eq(sim.bombs.size(), 0, "both bombs went off")
	t.ok(sim.field.has_flame(4, 5), "B's cell burns")
	t.ok(sim.field.has_flame(6, 5),
		"B's own flame propagated, so it really did detonate")
	t.eq(sim.field.flame_owner_at(6, 5), a.slot,
		"the chain's flame is credited to A, who started it")

	# A three-bomb chain, to prove it is a fixed point and not one hop.
	var s2 := _sim(3)
	var x: Player_ = s2.players[0]
	var y: Player_ = s2.players[1]
	var z: Player_ = s2.players[2]
	x.place_at_tile_centre(1, 5); x.flame_len = 2
	y.place_at_tile_centre(3, 5); y.flame_len = 2
	z.place_at_tile_centre(5, 5); z.flame_len = 2
	s2.place_bomb(x)
	s2.place_bomb(y).fuze = 500
	s2.place_bomb(z).fuze = 500
	_run(s2, Values_.V[Const_.Res.FUZE_FRAMES])
	t.eq(s2.bombs.size(), 0, "all three went off in one tick")
	t.ok(s2.field.has_flame(7, 5), "the third bomb's own flame propagated")
	t.eq(s2.field.flame_owner_at(7, 5), x.slot,
		"three bombs down the chain, X still gets the credit")

	# Every owner gets their bomb back, whoever set it off.
	t.eq(x.bombs_available, x.bombs_total, "X's bomb is returned")
	t.eq(y.bombs_available, y.bombs_total, "Y's bomb is returned")
	t.eq(z.bombs_available, z.bombs_total, "Z's bomb is returned")

	# A BOMB ENDS THE ARM. This used to assert the opposite — "the flame passes
	# over it" — which was the port's own reconstruction. `BM95.EXE` at
	# 0x4240E0 jumps to the end of the arm the moment bomb_at_tile() finds one,
	# without painting that cell: the bomb it just lit paints it, as its own
	# epicentre, in the same tick. docs/BUGS.md Q5.3.
	var s3 := _sim(2)
	var m: Player_ = s3.players[0]
	var n: Player_ = s3.players[1]
	m.place_at_tile_centre(5, 5); m.flame_len = 3
	n.place_at_tile_centre(6, 5); n.flame_len = 1
	s3.place_bomb(m)
	s3.place_bomb(n).fuze = 500
	_run(s3, Values_.V[Const_.Res.FUZE_FRAMES])
	t.ok(s3.field.has_flame(6, 5), "the bomb that was lit burns its own cell")
	t.ok(s3.field.has_flame(7, 5), "and its own arm, one cell of reach")
	t.ok(not s3.field.has_flame(8, 5),
		"but the arm that lit it stopped there — 3 cells of reach did not"
		+ " carry past the bomb at 2")

	# AND IT DOES NOT FIRE BACK. The chained bomb is told the direction the arm
	# came from and skips it (+0x38, written at 0x423209, tested at 0x423FA4).
	# Reach is arranged so only the back-fire could light (3,5).
	var s4 := _sim(2)
	var e: Player_ = s4.players[0]
	var f: Player_ = s4.players[1]
	e.place_at_tile_centre(5, 5); e.flame_len = 1
	f.place_at_tile_centre(6, 5); f.flame_len = 3
	var lit := s4.place_bomb(e)
	var chained := s4.place_bomb(f)
	chained.fuze = 500
	_run(s4, Values_.V[Const_.Res.FUZE_FRAMES])
	t.eq(chained.blocked_dir, Types_.Dir.LEFT,
		"the chained bomb is told not to fire back to the left")
	t.ok(s4.field.has_flame(9, 5), "its other arms are unaffected")
	t.ok(not s4.field.has_flame(3, 5),
		"and nothing burns two cells back down the arm that lit it")
	t.eq(lit.blocked_dir, Types_.Dir.NONE,
		"a bomb that nobody lit blocks nothing")


func _test_death(t: T_) -> void:
	# Killed by the epicentre.
	var sim := _sim(1)
	var p: Player_ = sim.players[0]
	p.place_at_tile_centre(5, 5)
	sim.place_bomb(p)
	_run(sim, Values_.V[Const_.Res.FUZE_FRAMES] - 1)
	t.ok(not p.dying, "alive the tick before it goes off")
	sim.tick()
	t.ok(p.dying, "standing on your own bomb kills you")
	t.eq(p.death_tick, Values_.V[Const_.Res.FUZE_FRAMES], "death tick recorded")
	t.eq(p.killed_by, p.slot, "a self-kill is attributed to yourself")
	t.eq(sim.living_players(), 0, "nobody left standing")

	# In reach dies, out of reach lives — the assertion PLAN.md names for
	# Phase 2. Reach 2 from (1,1) down the column: (1,2) and (1,3) burn,
	# (1,4) does not.
	var s2 := _sim(3)
	var bomber: Player_ = s2.players[0]
	var near: Player_ = s2.players[1]
	var far: Player_ = s2.players[2]
	bomber.place_at_tile_centre(1, 1)
	bomber.flame_len = 2
	near.place_at_tile_centre(1, 3)
	far.place_at_tile_centre(1, 4)
	s2.place_bomb(bomber)
	_run(s2, Values_.V[Const_.Res.FUZE_FRAMES])
	t.ok(near.dying, "a player 2 cells away with reach 2 dies")
	t.ok(not far.dying, "a player 3 cells away with reach 2 survives")
	t.eq(near.killed_by, bomber.slot, "the kill is credited to the bomber")

	# A player shielded by a brick survives, because the brick stops the arm.
	var s3 := _sim(2)
	var b3: Player_ = s3.players[0]
	var shielded: Player_ = s3.players[1]
	b3.place_at_tile_centre(1, 1)
	b3.flame_len = 4
	shielded.place_at_tile_centre(1, 4)
	s3.field.brick[Field_.idx(1, 2)] = Types_.Brick.BRICK
	s3.place_bomb(b3)
	_run(s3, Values_.V[Const_.Res.FUZE_FRAMES])
	t.ok(not shielded.dying, "a brick shields the player behind it")
	t.ok(s3.field.is_open(1, 2), "and is itself destroyed")

	# Walking into a standing flame kills, so the check must run after
	# movement — not only when the flame is created.
	var s4 := _sim(2)
	var b4: Player_ = s4.players[0]
	var walker: Player_ = s4.players[1]
	b4.place_at_tile_centre(5, 5)
	b4.flame_len = 1
	walker.place_at_tile_centre(8, 5)
	s4.place_bomb(b4)
	_run(s4, Values_.V[Const_.Res.FUZE_FRAMES])
	t.ok(not walker.dying, "out of reach when it went off")
	t.ok(s4.field.has_flame(6, 5), "the flame is standing at (6,5)")
	walker.move = Types_.MoveState.LEFT
	var died := false
	for _i in 12:
		s4.tick()
		if walker.dying:
			died = true
			break
	t.ok(died, "walking into a standing flame kills")

	# A dead player stops acting: no more input, no more bombs.
	var s5 := _sim(1)
	var p5: Player_ = s5.players[0]
	p5.place_at_tile_centre(5, 5)
	s5.place_bomb(p5)
	_run(s5, Values_.V[Const_.Res.FUZE_FRAMES])
	t.ok(p5.dying, "the player is dying")
	var held_x := p5.x
	s5.set_input(0, Types_.MoveState.RIGHT, Types_.Action.FIRST)
	_run(s5, 5)
	t.eq(p5.x, held_x, "a dying player does not move")
	t.eq(s5.bombs.size(), 0, "a dying player places no bombs")

	# kill() is idempotent — a player caught by two flames on one tick dies
	# once, and keeps the first attribution.
	var s6 := _sim(2)
	var v: Player_ = s6.players[0]
	v.place_at_tile_centre(5, 5)
	s6.kill(v, 1)
	var first_tick := v.death_tick
	s6.kill(v, 0)
	t.eq(v.killed_by, 1, "the first attribution stands")
	t.eq(v.death_tick, first_tick, "and the first death tick")


func _run(sim: Sim_, ticks: int) -> void:
	for _i in ticks:
		sim.tick()


# An open field, so a case's own walls are the only obstacles.
func _sim(count: int) -> Sim_:
	var lines := PackedStringArray()
	lines.append("-V,2")
	lines.append("-N,Open")
	lines.append("-B,0")
	for y in Const_.FIELD_H:
		lines.append("-R,%2d,%s" % [y, ".".repeat(Const_.FIELD_W)])
	for p in Const_.PLAYER_COUNT:
		lines.append("-S,%d,%d,0,%d" % [p, p, p % 2])
	for i in Const_.POWERUP_COUNT:
		lines.append("-P,%2d, 0,0, 0, 0,x" % i)
	var s: Scheme_ = Scheme_.new()
	s.parse_text("\n".join(lines), "<open>")
	assert(s.ok(), "open scheme must parse: %s" % s.error())

	var slots := []
	for i in count:
		slots.append({"slot": i, "team": i % 2})
	var sim: Sim_ = Sim_.new()
	sim.setup(s, slots, 1)
	return sim


# ---------------------------------------------------------------------------
# The kill tally the Win Matches By Kill Total option counts — MESSAGES.TXT
# 255, and OPTIONS.BM: "If you kill yourself with your own bomb, your kill
# count will go down by 1."
# ---------------------------------------------------------------------------
func _test_kill_tally(t: T_) -> void:
	var sim := _sim(3)
	t.eq(sim.round_kills.size(), Const_.PLAYER_COUNT,
		"a kill column exists for every slot")
	for k in sim.round_kills:
		t.eq(k, 0, "and starts at zero")

	var bomber: Player_ = sim.players[0]
	var victim: Player_ = sim.players[1]
	bomber.place_at_tile_centre(1, 1)
	bomber.flame_len = 3
	victim.place_at_tile_centre(1, 3)
	# Out of the blast, so the bomber is not counting its own death here.
	sim.players[2].place_at_tile_centre(9, 9)
	sim.place_bomb(bomber)
	# Walk the bomber out of its own blast. Otherwise it dies on its own bomb
	# for -1 and kills the victim for +1, and the column reads zero — which is
	# correct, and tests nothing.
	bomber.place_at_tile_centre(9, 1)
	_run(sim, Values_.V[Const_.Res.FUZE_FRAMES])
	t.ok(victim.dying, "the victim is caught")
	t.eq(sim.round_kills[bomber.slot], 1, "the kill goes to the bomber")
	t.eq(sim.round_kills[victim.slot], 0, "and not to the victim")

	# Standing on your own bomb costs you one instead of earning one.
	var own := _sim(1)
	var solo: Player_ = own.players[0]
	solo.place_at_tile_centre(5, 5)
	own.place_bomb(solo)
	_run(own, Values_.V[Const_.Res.FUZE_FRAMES])
	t.ok(solo.dying, "the bomber dies on their own bomb")
	t.eq(own.round_kills[solo.slot], -1, "which costs a kill rather than"
		+ " scoring one")

	# A death nobody owns credits nobody. kill() is called directly here
	# because that is how the closing wall and a level's own hazards kill.
	var wall := _sim(2)
	wall.kill(wall.players[0])
	t.ok(wall.players[0].dying, "an unattributed death still kills")
	for k in wall.round_kills:
		t.eq(k, 0, "and puts a kill on nobody's column")


## `0x41F29B`: boxed in on all four sides rolls one of the 13 `cornerhead N`
## sequences. docs/BUGS.md.
func _test_cornerhead(t: T_) -> void:
	var lines := PackedStringArray()
	lines.append("-V,2")
	lines.append("-N,Boxed")
	lines.append("-B,0")
	for y in Const_.FIELD_H:
		var row := ""
		for x in Const_.FIELD_W:
			# A solid ring around (5,5): every one of its four neighbours.
			var boxed_in := (x == 4 and y == 5) or (x == 6 and y == 5) \
				or (x == 5 and y == 4) or (x == 5 and y == 6)
			row += "#" if boxed_in else "."
		lines.append("-R,%2d,%s" % [y, row])
	# Start well away from (5,5): a live player's start cell and its four
	# neighbours are auto-blanked at round setup, which would eat the very
	# walls this test needs. place_at_tile_centre() below moves the player
	# into the box afterward.
	lines.append("-S,0,10,9,0")
	lines.append("-S,1,1,1,0")
	for slot in range(2, Const_.PLAYER_COUNT):
		lines.append("-S,%d,%d,%d,0" % [slot, slot, slot])
	for i in Const_.POWERUP_COUNT:
		lines.append("-P,%2d, 0,0, 0, 0,x" % i)
	var s: Scheme_ = Scheme_.new()
	s.parse_text("\n".join(lines), "<boxed>")
	assert(s.ok(), "boxed scheme must parse: %s" % s.error())

	var boxed: Sim_ = Sim_.new()
	boxed.setup(s, [{"slot": 0, "team": 0}, {"slot": 1, "team": 0}], 1)
	var p: Player_ = boxed.players[0]
	p.place_at_tile_centre(5, 5)
	t.eq(p.cornerhead, 0, "not playing before the check has run")
	boxed.tick()
	t.ok(p.cornerhead >= 1 and p.cornerhead <= Values_.V[Const_.Res.CORNERHEAD_COUNT],
		"boxed in on all four sides rolls a cornerhead sequence in range")
	t.eq(p.cornerhead_ticks, Sim_.CORNERHEAD_TICKS, "with its full duration")

	var ticks := p.cornerhead_ticks
	for _i in ticks:
		boxed.tick()
	t.eq(p.cornerhead, 0, "and it clears again once its duration elapses")

	# An open field never triggers it.
	var open := _sim(1)
	var q: Player_ = open.players[0]
	q.place_at_tile_centre(5, 5)
	for _i in 5:
		open.tick()
	t.eq(q.cornerhead, 0, "an open field never boxes a player in")

	# Mid-kick, mid-punch or mid-pickup takes priority — the original's own
	# state field is shared, and this port's own gate mirrors that.
	var busy := Sim_.new()
	busy.setup(s, [{"slot": 0, "team": 0}, {"slot": 1, "team": 0}], 1)
	var r: Player_ = busy.players[0]
	r.place_at_tile_centre(5, 5)
	r.kick_ticks = 3
	busy.tick()
	t.eq(r.cornerhead, 0, "boxed in but mid-kick: no cornerhead yet")
