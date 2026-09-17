# The map specials: arrows, conveyors, warp gates, trampolines, regrowth, ice.
#
# Every COORDINATE here is the original's, from EXTRA*.RES via
# scripts/core/extras.gd, and is asserted against the levels that actually have
# them. The RULES are reconstructed — docs/BUGS.md Q5 — so these assertions pin
# the reconstruction.
#
# Also asserted: the geometry is built from the level and the seed alone, which
# is what lets it stay off the wire while still being covered by state_hash().
extends SceneTree

const T_ := preload("res://tests/t.gd")
const Const_ := preload("res://scripts/core/const.gd")
const Types_ := preload("res://scripts/core/types.gd")
const Values_ := preload("res://scripts/core/values.gd")
const Extras_ := preload("res://scripts/core/extras.gd")
const Scheme_ := preload("res://scripts/core/scheme.gd")
const Field_ := preload("res://scripts/sim/field.gd")
const Sim_ := preload("res://scripts/sim/sim.gd")
const Player_ := preload("res://scripts/sim/player.gd")


func _init() -> void:
	var t := T_.new("specials")
	_test_geometry_matches_the_data(t)
	_test_geometry_is_deterministic(t)
	_test_arrows(t)
	_test_conveyors(t)
	_test_warps(t)
	_test_trampolines(t)
	_test_regrowth(t)
	_test_ice(t)
	_test_hurry_disables(t)
	quit(t.finish())


# What the field ends up holding must be what EXTRA*.RES said.
func _test_geometry_matches_the_data(t: T_) -> void:
	for level in 11:
		var sim := _sim(level, 2)
		var data: Dictionary = Extras_.of_level(level)

		for a in data["arrows"] as Array:
			t.eq(sim.field.arrow_at(int(a["x"]), int(a["y"])),
				Types_.DIR_NAMES[a["dir"]],
				"level %d arrow at (%d,%d) points %s"
					% [level, a["x"], a["y"], a["dir"]])
		for c in data["conveyors"] as Array:
			t.eq(sim.field.conveyor_at(int(c["x"]), int(c["y"])),
				Types_.DIR_NAMES[c["dir"]],
				"level %d conveyor at (%d,%d) runs %s"
					% [level, c["x"], c["y"], c["dir"]])
		for w in data["warps"] as Array:
			t.eq(sim.field.warp_at(int(w["x"]), int(w["y"])), int(w["gate"]),
				"level %d gate %d is at (%d,%d)"
					% [level, w["gate"], w["x"], w["y"]])
		for tr in data["tramps"] as Array:
			t.ok(sim.field.tramp_at(int(tr["x"]), int(tr["y"])),
				"level %d trampoline at (%d,%d)" % [level, tr["x"], tr["y"]])

		# Every special's cell must be WALKABLE, or the feature does nothing
		# until a brick is destroyed — and a warp gate under a brick would
		# strand whoever arrived on it.
		for group in ["arrows", "conveyors", "tramps"]:
			for item in data[group] as Array:
				t.ok(sim.field.is_open(int(item["x"]), int(item["y"])),
					"level %d %s cell (%d,%d) is walkable"
						% [level, group, item["x"], item["y"]])

		# A special's cell must not have a powerup lying on it. load_extras()
		# runs after place_powerups(), so blanking a cell for an arrow can
		# reveal what was hidden under its brick — visible immediately on
		# level 10, where powerups sat on the conveyor belt from tick zero.
		for group2 in ["arrows", "conveyors", "tramps"]:
			for item2 in data[group2] as Array:
				t.ok(not sim.field.has_powerup(int(item2["x"]), int(item2["y"])),
					"level %d %s cell (%d,%d) has no powerup on it"
						% [level, group2, item2["x"], item2["y"]])
		for w2 in data["warps"] as Array:
			t.ok(not sim.field.has_powerup(int(w2["x"]), int(w2["y"])),
				"level %d gate cell (%d,%d) has no powerup on it"
					% [level, w2["x"], w2["y"]])

		# The random trampolines bring the total to what EXTRA9 asks for.
		var want_tramps := (data["tramps"] as Array).size() \
			+ int(data["random_tramps"])
		var got := 0
		for y in Const_.FIELD_H:
			for x in Const_.FIELD_W:
				if sim.field.tramp_at(x, y):
					got += 1
		t.eq(got, want_tramps, "level %d has %d trampolines" % [level, want_tramps])

	# Level 9 is the one with eight, which is the count fpc_atomic guessed and
	# EXTRA9 confirms: four authored plus four random.
	var forest := _sim(9, 2)
	var n := 0
	for y in Const_.FIELD_H:
		for x in Const_.FIELD_W:
			if forest.field.tramp_at(x, y):
				n += 1
	t.eq(n, 8, "Deep Forest Green has eight trampolines")

	# Levels with no specials file must have no specials.
	for level in [0, 1, 5, 6, 8]:
		var plain := _sim(level, 2)
		var found := 0
		for y in Const_.FIELD_H:
			for x in Const_.FIELD_W:
				if plain.field.arrow_at(x, y) != 0 \
						or plain.field.conveyor_at(x, y) != 0 \
						or plain.field.tramp_at(x, y) \
						or plain.field.warp_at(x, y) >= 0:
					found += 1
		t.eq(found, 0, "level %d has no specials" % level)


# The geometry never travels on the wire, so both sides must derive it from the
# level and the seed alone. That is what makes leaving it out of the snapshot
# safe, and state_hash() covers it so a divergence still fails.
func _test_geometry_is_deterministic(t: T_) -> void:
	for level in [3, 4, 9, 10]:
		var a := _sim(level, 2, 8080)
		var b := _sim(level, 2, 8080)
		t.eq(a.field.static_bytes(), b.field.static_bytes(),
			"level %d geometry is identical for the same seed" % level)
		t.eq(a.state_hash(), b.state_hash(),
			"level %d hashes identically" % level)

	# Level 9's four random trampolines must actually depend on the seed, or
	# "deterministic" would be trivially true.
	var s1 := _sim(9, 2, 1)
	var s2 := _sim(9, 2, 2)
	t.ok(s1.field.static_bytes() != s2.field.static_bytes(),
		"a different seed moves the random trampolines")

	# And the geometry must be in the hash, or a client that built it wrongly
	# would hash the same as the server.
	var probe := _sim(3, 2)
	var before := probe.state_hash()
	probe.field.arrow[Field_.idx(0, 0)] = Types_.Dir.UP
	t.ok(probe.state_hash() != before,
		"state_hash covers the level geometry")


# An arrow redirects a bomb that ROLLS onto it, and leaves a bomb PLACED on it
# alone — AtomBomberman's notes are explicit about the difference.
func _test_arrows(t: T_) -> void:
	var sim := _sim(3, 2)          # Ancient Egypt, 44 arrows
	var arrows: Array = Extras_.of_level(3)["arrows"]
	t.eq(arrows.size(), 44, "Ancient Egypt has 44 arrows")
	# Park everyone but slot 0 out of the way. A bomb is correctly stopped by a
	# player, and the fixture's default starts put slot 1 on (2,2) — which is
	# an arrow cell, so the first version of this test measured the
	# player-blocking rule instead of the arrow rule.
	_clear_the_field_of_players(sim, 0)

	# Find an arrow with a clear cell to its west, so a bomb can roll onto it.
	var target := Vector2i(-1, -1)
	var want_dir := 0
	for a in arrows:
		var ax: int = int(a["x"])
		var ay: int = int(a["y"])
		# Not pointing the way the bomb already travels, or "was it
		# redirected?" has no answer.
		if Types_.DIR_NAMES[a["dir"]] == Types_.Dir.RIGHT:
			continue
		if ax >= 2 and sim.field.is_open(ax - 1, ay) and sim.field.is_open(ax - 2, ay):
			target = Vector2i(ax, ay)
			want_dir = Types_.DIR_NAMES[a["dir"]]
			break
	if not t.ok(target.x >= 0, "an arrow with clear approach was found"):
		return

	# A bomb placed ON the arrow does not move.
	var p: Player_ = sim.players[0]
	p.place_at_tile_centre(target.x, target.y)
	var placed := sim.place_bomb(p)
	t.eq(placed.move_dir, Types_.Dir.NONE,
		"a bomb placed on an arrow does not move")
	for _i in 5:
		sim.tick()
	t.eq(placed.move_dir, Types_.Dir.NONE, "and still does not")

	# A bomb kicked onto it is redirected.
	var s2 := _sim(3, 2)
	_clear_the_field_of_players(s2, 0)
	var p2: Player_ = s2.players[0]
	p2.place_at_tile_centre(target.x - 2, target.y)
	s2.give_powerup(p2, Types_.PowerUp.KICK)
	var b := s2.place_bomb(p2)
	b.place_at_tile_centre(target.x - 1, target.y)
	p2.facing = Types_.Dir.RIGHT
	t.ok(s2.kick_bomb(p2), "the bomb is kicked toward the arrow")
	t.eq(b.move_dir, Types_.Dir.RIGHT, "and starts moving right")
	var redirected := false
	for _i in 40:
		b.fuze = Values_.V[Const_.Res.FUZE_FRAMES]   # keep it alive to watch
		s2.tick()
		if b.move_dir == want_dir:
			redirected = true
			break
	t.ok(redirected,
		"the arrow at (%d,%d) redirected the rolling bomb to dir %d"
			% [target.x, target.y, want_dir])


func _test_conveyors(t: T_) -> void:
	var conv: Array = Extras_.of_level(10)["conveyors"]
	t.eq(conv.size(), 32, "Inner City Trash has 32 conveyor cells")
	t.eq(Values_.V[Const_.Res.CONVEYOR_SPEED_COUNT], 3,
		"resource 189 says there are three conveyor speeds")
	for i in 3:
		t.eq(Values_.V[Const_.Res.CONVEYOR_SPEED_BASE + i], [250, 350, 450][i],
			"conveyor speed %d is resource %d"
				% [i, Const_.Res.CONVEYOR_SPEED_BASE + i])

	var sim := _sim(10, 2)
	# A player standing still on a belt is carried.
	var cell: Dictionary = conv[0]
	var p: Player_ = sim.players[0]
	p.place_at_tile_centre(int(cell["x"]), int(cell["y"]))
	p.move = Types_.MoveState.STILL
	var before := Vector2i(p.x, p.y)
	for _i in 6:
		sim.tick()
	t.ok(Vector2i(p.x, p.y) != before,
		"a conveyor carries a player who is standing still")

	# It carries them in ITS direction, not an arbitrary one.
	var s2 := _sim(10, 2)
	var p2: Player_ = s2.players[0]
	p2.place_at_tile_centre(int(cell["x"]), int(cell["y"]))
	p2.move = Types_.MoveState.STILL
	var start := Vector2i(p2.x, p2.y)
	for _i in 4:
		s2.tick()
	var step: Vector2i = Types_.DIR_VEC[Types_.DIR_NAMES[cell["dir"]]]
	if step.x != 0:
		t.ok(signi(p2.x - start.x) == step.x,
			"carried %s along x" % cell["dir"])
	else:
		t.ok(signi(p2.y - start.y) == step.y,
			"carried %s along y" % cell["dir"])

	# The speed used is the round's, and settable.
	t.eq(s2.conveyor_speed(), 350, "the middle speed is the default")
	s2.conveyor_speed_index = 2
	t.eq(s2.conveyor_speed(), 450, "and the index selects another")

	# A conveyor cannot push a player into a wall. [invariant]
	var s3 := _sim(10, 2)
	for _i in 200:
		s3.tick()
	for pl in s3.players:
		if pl.alive:
			t.ok(s3.field.is_open(pl.tile_x(), pl.tile_y()),
				"[invariant] player %d is never conveyed into a wall" % pl.slot)


func _test_warps(t: T_) -> void:
	var gates: Array = Extras_.of_level(4)["warps"]
	t.eq(gates.size(), 4, "The Coal Mine has four warp gates")

	var sim := _sim(4, 2)
	var g0: Dictionary = gates[0]
	var exit_cell := sim.field.warp_exit(0)
	t.ok(exit_cell.x >= 0, "gate 0 leads somewhere")
	# EXTRA4's ring is 0 -> 3 -> 2 -> 1 -> 0.
	t.eq(sim.field.warp_at(exit_cell.x, exit_cell.y), 3,
		"gate 0 leads to gate 3, as EXTRA4 says")

	var p: Player_ = sim.players[0]
	p.place_at_tile_centre(int(g0["x"]), int(g0["y"]))
	sim.tick()
	t.eq(Vector2i(p.tile_x(), p.tile_y()), exit_cell,
		"stepping on a gate teleports the player to its exit")
	t.ok(p.warp_cooldown > 0,
		"and a cooldown stops them being sent straight back")
	t.ok(p.invulnerable > 0,
		"a teleporting player is briefly immortal, per the notes")

	# The cooldown must actually prevent a loop: after many ticks the player is
	# somewhere, not oscillating between two gates forever.
	for _i in 200:
		sim.tick()
	t.ok(sim.field.is_open(p.tile_x(), p.tile_y()),
		"[invariant] the player ends up somewhere valid")

	# A flame passes OVER a gate; a bomb is stopped BY one.
	var s2 := _sim(4, 2)
	var p2: Player_ = s2.players[0]
	var gx := int(g0["x"])
	var gy := int(g0["y"])
	s2.give_powerup(p2, Types_.PowerUp.KICK)
	# Put the player two cells from the gate along a clear line, if there is one.
	var placed := false
	for step in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var ax: int = gx - step.x * 2
		var ay: int = gy - step.y * 2
		if s2.field.is_open(ax, ay) and s2.field.is_open(gx - step.x, gy - step.y):
			p2.place_at_tile_centre(ax, ay)
			p2.facing = Types_.DIR_VEC.find_key(step)
			var b := s2.place_bomb(p2)
			b.place_at_tile_centre(gx - step.x, gy - step.y)
			s2.kick_bomb(p2)
			for _i in 30:
				b.fuze = Values_.V[Const_.Res.FUZE_FRAMES]
				s2.tick()
			t.ok(Vector2i(b.tile_x(), b.tile_y()) != Vector2i(gx, gy),
				"a bomb is stopped by a warp gate rather than rolling onto it")
			placed = true
			break
	t.ok(placed, "a clear approach to a gate was found")


func _test_trampolines(t: T_) -> void:
	t.eq(Values_.V[Const_.Res.TRAMP_BOUNCE_FRAMES], 30,
		"a trampoline holds a player for resource 680 = 30 frames")
	t.eq(Values_.V[Const_.Res.TRAMP_RISE_PX], 35,
		"rising resource 681 = 35 pixels a frame")

	var sim := _sim(9, 2)
	var tramps: Array = Extras_.of_level(9)["tramps"]
	var cell: Dictionary = tramps[0]
	var p: Player_ = sim.players[0]
	p.place_at_tile_centre(int(cell["x"]), int(cell["y"]))
	sim.tick()
	t.eq(p.fly_ticks, 30, "stepping on a trampoline launches the player")

	# In the air they are out of play: flame cannot touch them.
	sim.field.add_flame(p.tile_x(), p.tile_y(), Types_.Flame.CROSS, 1, 20)
	sim.tick()
	t.ok(not p.dying, "a player in the air is not burned")

	# They come down somewhere open, and not on another trampoline.
	for _i in 40:
		sim.tick()
		if p.fly_ticks == 0:
			break
	t.eq(p.fly_ticks, 0, "they land")
	t.ok(sim.field.is_open(p.tile_x(), p.tile_y()), "on an open cell")
	t.ok(not sim.field.tramp_at(p.tile_x(), p.tile_y()),
		"and not on another trampoline, which would bounce forever")


# Only the haunted house regrows bricks: resource 347, every four seconds,
# never within resource 695's four cells of a player.
func _test_regrowth(t: T_) -> void:
	for level in 11:
		var want := 4 if level == 7 else 0
		var sim := _sim(level, 2)
		t.eq(sim.field.regen_interval, want,
			"level %d regrowth interval is %d s" % [level, want])

	var haunted := _sim(7, 2, 5)
	t.eq(haunted.field.regen_clear_radius, 4, "the clear radius is four cells")
	# Clear the field so there is somewhere to grow, and park every player in
	# one corner so most of the field is outside the radius.
	for y in Const_.FIELD_H:
		for x in Const_.FIELD_W:
			haunted.field.brick[Field_.idx(x, y)] = Types_.Brick.BLANK
	for pl in haunted.players:
		pl.place_at_tile_centre(0, 0)
	var before := haunted.field.count_of(Types_.Brick.BRICK)
	# Four seconds is 80 ticks. Run long enough to grow MANY bricks, not two:
	# the clear-radius rule can only be measured by giving it enough chances to
	# be broken. With two bricks a violation was about a one-in-four
	# coincidence, and mutation M44 — deleting the radius check — went
	# undetected because of it.
	haunted.time_left = 100000       # do not let the round end mid-measurement
	for _i in 80 * 40:
		# Keep everyone pinned in the corner, so "outside the radius" means the
		# same thing on every tick.
		for pl in haunted.players:
			pl.place_at_tile_centre(0, 0)
		haunted.tick()
	var after := haunted.field.count_of(Types_.Brick.BRICK)
	t.ok(after - before >= 20,
		"the haunted house grew %d bricks back, enough to measure the radius"
			% (after - before))

	# Never within four cells of a player. With ~30 bricks grown and 25 cells
	# inside the radius out of 165, dropping the rule puts several there.
	var violations := 0
	for y in Const_.FIELD_H:
		for x in Const_.FIELD_W:
			if haunted.field.brick_at(x, y) != Types_.Brick.BRICK:
				continue
			if x <= haunted.field.regen_clear_radius \
					and y <= haunted.field.regen_clear_radius:
				violations += 1
	t.eq(violations, 0,
		"no brick grew within %d cells of the player at (0,0)"
			% haunted.field.regen_clear_radius)

	# A level with no regrowth grows nothing.
	var plain := _sim(0, 2, 5)
	for y in Const_.FIELD_H:
		for x in Const_.FIELD_W:
			plain.field.brick[Field_.idx(x, y)] = Types_.Brick.BLANK
	for _i in 200:
		plain.tick()
	t.eq(plain.field.count_of(Types_.Brick.BRICK), 0,
		"a level without regrowth grows nothing")


# ORACLE row 20: the hockey rink is the only level with ice, and fpc_atomic has
# it on none.
func _test_ice(t: T_) -> void:
	for level in 11:
		var want := 250 if level == 2 else 0
		var sim := _sim(level, 2)
		t.eq(sim.field.ice_delay_ms, want,
			"level %d ice delay is %d ms" % [level, want])
	var rink := _sim(2, 2)
	t.eq(rink.field.ice_delay_ms, 250,
		"The Hockey Rink has 250 ms of control delay")
	# And it has arrows too, which fpc_atomic's Field02 does not.
	t.eq((Extras_.of_level(2)["arrows"] as Array).size(), 12,
		"and twelve arrows, which fpc_atomic's level 2 does not have")


# Holes and trampolines are disabled in Hurry mode — ORACLE row 22.
func _test_hurry_disables(t: T_) -> void:
	var normal := Field_.new()
	var hurry := Field_.new()
	var scheme := _scheme()
	var starts := [{"x": 1, "y": 1}]
	normal.initialize(scheme, starts, _rng(3))
	normal.load_extras(9, starts, _rng(3), false)
	hurry.initialize(scheme, starts, _rng(3))
	hurry.load_extras(9, starts, _rng(3), true)

	var n_normal := 0
	var n_hurry := 0
	for y in Const_.FIELD_H:
		for x in Const_.FIELD_W:
			if normal.tramp_at(x, y):
				n_normal += 1
			if hurry.tramp_at(x, y):
				n_hurry += 1
	t.eq(n_normal, 8, "level 9 normally has eight trampolines")
	t.eq(n_hurry, 0, "and none in Hurry mode")

	var warp_normal := Field_.new()
	var warp_hurry := Field_.new()
	warp_normal.initialize(scheme, starts, _rng(3))
	warp_normal.load_extras(4, starts, _rng(3), false)
	warp_hurry.initialize(scheme, starts, _rng(3))
	warp_hurry.load_extras(4, starts, _rng(3), true)
	t.ok(warp_normal.warp_at(2, 2) >= 0, "level 4 normally has its gates")
	t.eq(warp_hurry.warp_at(2, 2), -1, "and none in Hurry mode")

	# Arrows and conveyors are NOT disabled: only holes and trampolines are.
	var arrows_hurry := Field_.new()
	arrows_hurry.initialize(scheme, starts, _rng(3))
	arrows_hurry.load_extras(3, starts, _rng(3), true)
	var found := 0
	for y in Const_.FIELD_H:
		for x in Const_.FIELD_W:
			if arrows_hurry.arrow_at(x, y) != 0:
				found += 1
	t.eq(found, 44, "arrows are not disabled in Hurry mode")


## Move every player except one far off the play area's specials, so a test
## measures the rule it names and not the player-blocking rule.
func _clear_the_field_of_players(sim: Sim_, keep: int) -> void:
	for p in sim.players:
		if p.slot == keep:
			continue
		p.in_play = false
		p.alive = false


func _scheme() -> Scheme_:
	var lines := PackedStringArray()
	lines.append("-V,2")
	lines.append("-N,Specials fixture (10)")
	lines.append("-B,0")
	for y in Const_.FIELD_H:
		lines.append("-R,%2d,%s" % [y, ".".repeat(Const_.FIELD_W)])
	for p in Const_.PLAYER_COUNT:
		lines.append("-S,%d,%d,%d,%d" % [p, 1 + p, 1 + (p % 8), p % 2])
	for i in Const_.POWERUP_COUNT:
		lines.append("-P,%2d, 0,0, 0, 0,x" % i)
	var s: Scheme_ = Scheme_.new()
	s.parse_text("\n".join(lines), "<specials>")
	assert(s.ok(), "fixture must parse: %s" % s.error())
	return s


func _rng(seed_value: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	return r


func _sim(level: int, count: int, round_seed: int = 1) -> Sim_:
	var slots := []
	for i in count:
		slots.append({"slot": i, "team": i % 2})
	var sim: Sim_ = Sim_.new()
	sim.level = level
	sim.setup(_scheme(), slots, round_seed)
	return sim
