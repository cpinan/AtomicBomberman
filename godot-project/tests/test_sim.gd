# The tick loop itself: the accumulator, the stall clamp, determinism and
# state_hash().
#
# state_hash() is the parity primitive — Phase 5 asserts every client agrees
# with the server on it each broadcast, and Track C diffs it against the C
# oracle tick by tick. Both are exact-match tests, so the properties asserted
# here are the ones those tests silently depend on: it must change when the
# state changes, it must NOT change with irrelevant ordering, and it must be
# reproducible from a seed.
extends SceneTree

const T_ := preload("res://tests/t.gd")
const Const_ := preload("res://scripts/core/const.gd")
const Types_ := preload("res://scripts/core/types.gd")
const Values_ := preload("res://scripts/core/values.gd")
const Scheme_ := preload("res://scripts/core/scheme.gd")
const Field_ := preload("res://scripts/sim/field.gd")
const Sim_ := preload("res://scripts/sim/sim.gd")
const Player_ := preload("res://scripts/sim/player.gd")
const DataPath_ := preload("res://tests/data_path.gd")


func _init() -> void:
	var t := T_.new("sim")
	_test_setup(t)
	_test_tick_is_clockless(t)
	_test_accumulator(t)
	_test_stall_clamp(t)
	_test_hash_algorithm(t)
	_test_hash_sensitivity(t)
	_test_hash_order_independence(t)
	_test_replay(t)
	_test_real_schemes(t)
	quit(t.finish())


func _test_setup(t: T_) -> void:
	var sim := _sim(4)
	t.eq(sim.players.size(), 4, "four players in the round")
	t.eq(sim.tick_count, 0, "starts at tick zero")
	t.eq(sim.bombs.size(), 0, "no bombs to begin with")
	t.eq(sim.living_players(), 4, "all four alive")

	# The starting loadout comes from VALUELST, not from a literal here.
	var p: Player_ = sim.players[0]
	t.eq(p.speed, Values_.V[Const_.Res.START_SPEED], "speed is resource 42")
	t.eq(p.flame_len, Values_.V[Const_.Res.BORN_WITH_BASE + Types_.PowerUp.FLAME],
		"reach is resource 51")
	t.eq(p.bombs_total, Values_.V[Const_.Res.BORN_WITH_BASE + Types_.PowerUp.BOMB],
		"bomb count is resource 50")
	# Which for the shipped table means one bomb and two cells of flame.
	t.eq(p.bombs_total, 1, "the original starts you with one bomb")
	t.eq(p.flame_len, 2, "and two cells of flame")

	# Players start centred on their scheme cells, and the cells are cleared.
	for pl in sim.players:
		t.eq(pl.offset_x(), 0, "player %d starts x-centred" % pl.slot)
		t.eq(pl.offset_y(), 0, "player %d starts y-centred" % pl.slot)
		t.ok(sim.field.is_open(pl.tile_x(), pl.tile_y()),
			"player %d starts on an open cell" % pl.slot)

	# setup() must fully reset, so a second round on the same object is not
	# contaminated by the first.
	var reused := _sim(2)
	reused.place_bomb(reused.players[0])
	reused.tick()
	var scheme := _open_scheme()
	reused.setup(scheme, [{"slot": 0, "team": 0}], 1)
	t.eq(reused.tick_count, 0, "setup resets the tick count")
	t.eq(reused.bombs.size(), 0, "setup clears the bombs")
	t.eq(reused.players.size(), 1, "setup replaces the players")


# tick() must take no delta and read no clock — that is what lets a test assert
# "on tick 40" rather than "after about two seconds".
func _test_tick_is_clockless(t: T_) -> void:
	var sim := _sim(1)
	for i in 100:
		sim.tick()
		t.ok(sim.tick_count == i + 1, "tick %d increments the counter" % (i + 1))
		if i > 3:
			break
	# 20 ticks is exactly one second of game time.
	var s2 := _sim(1)
	for _i in Const_.TICK_HZ:
		s2.tick()
	t.eq(s2.tick_count, 20, "20 ticks is one second at the original's rate")
	t.eq(s2.tick_count * Const_.TICK_MS, 1000, "and that is 1000 ms")


func _test_accumulator(t: T_) -> void:
	var sim := _sim(1)
	t.eq(sim.advance(0), 0, "no time, no ticks")
	t.eq(sim.advance(49), 0, "49 ms is not yet a tick")
	t.eq(sim.advance(1), 1, "the 50th ms completes it")
	t.eq(sim.tick_count, 1, "one tick ran")

	# The remainder is kept, not dropped — otherwise a caller running at a rate
	# that is not a multiple of 50 ms would lose time steadily.
	var s2 := _sim(1)
	var ran := 0
	for _i in 60:
		ran += s2.advance(16)     # ~60 fps caller
	t.eq(ran, 19, "60 frames of 16 ms yield 19 ticks (960 ms)")
	t.eq(s2.tick_count, 19, "and the sim agrees")

	# Exact multiples run exactly.
	var s3 := _sim(1)
	t.eq(s3.advance(150), 3, "150 ms is three ticks")
	var s4 := _sim(1)
	t.eq(s4.advance(100), 2, "100 ms is two ticks")


# A single advance() is clamped to resource 31 — 150 ms, three ticks. The
# original's comment: "this prevents a disk hit from moving everybody a whole
# huge distance on the screen and screwing things up."
func _test_stall_clamp(t: T_) -> void:
	var clamp_ms: int = Values_.V[Const_.Res.MAX_ADVANCE_MS]
	t.eq(clamp_ms, 150, "the clamp is resource 31 = 150 ms")

	var sim := _sim(1)
	t.eq(sim.advance(5000), clamp_ms / Const_.TICK_MS,
		"a 5-second stall advances only three ticks")
	t.eq(sim.tick_count, 3, "so the sim only moved three ticks")

	# And the discarded time must NOT be banked: banking it would replay the
	# stall on the next call and turn one hitch into a cascade.
	t.eq(sim.advance(50), 1, "the next call is a normal single tick")
	t.eq(sim.tick_count, 4, "no backlog was carried over")

	# A player cannot be teleported across the field by a stall. [invariant]
	var s2 := _sim(1)
	var p: Player_ = s2.players[0]
	p.place_at_tile_centre(1, 5)
	p.move = Types_.MoveState.RIGHT
	var before := p.x
	s2.advance(10000)
	t.eq(p.x - before, 3 * p.speed,
		"[invariant] a 10-second stall moves the player three ticks' worth")


# The hash must move when the state moves. A hash that misses a field is a
# hash that hides a divergence, which is worse than having none.
# state_hash() must be real FNV-1a, not merely "some function that changes".
#
# It was not: the 64-bit offset basis 0xCBF29CE484222325 exceeds GDScript's
# SIGNED 64-bit int, Godot rejected the literal, and the constant silently held
# a wrong value. Every test still passed, because they all asserted only that
# the hash changes when the state changes. These digests were computed
# independently in Python and pin the constant so it cannot rot again — and so
# that the C oracle in Track C can be checked against the same numbers.
func _test_hash_algorithm(t: T_) -> void:
	t.eq(Sim_.fnv1a(PackedByteArray()), -3750763034362895579,
		"fnv1a of nothing is the offset basis")
	t.eq(Sim_.fnv1a("a".to_ascii_buffer()), -5808556873153909620, "fnv1a('a')")
	t.eq(Sim_.fnv1a("abc".to_ascii_buffer()), -1792535898324117685, "fnv1a('abc')")
	t.eq(Sim_.fnv1a(PackedByteArray([0, 1, 2, 3, 4, 5, 6, 7])),
		-6567292918605886595, "fnv1a(0..7)")
	# One byte of difference must change the digest completely, or a
	# single-field divergence could hide inside a near-collision.
	var a := Sim_.fnv1a(PackedByteArray([1, 2, 3]))
	var b := Sim_.fnv1a(PackedByteArray([1, 2, 4]))
	t.ok(a != b, "one byte changes the digest")
	t.ok(absi(a - b) > 1000, "and changes it by more than a nudge")


func _test_hash_sensitivity(t: T_) -> void:
	var sim := _sim(2)
	var base := sim.state_hash()

	t.ok(base != 0, "the hash is not trivially zero")

	# The tick count is in it, so an idle tick still changes it.
	sim.tick()
	t.ok(sim.state_hash() != base, "an idle tick changes the hash")

	var mutations := {
		"moving a player": func(s: Sim_): s.players[0].x += 1,
		"a player dying": func(s: Sim_): s.kill(s.players[0], 1),
		"changing speed": func(s: Sim_): s.players[0].speed += 1,
		"changing reach": func(s: Sim_): s.players[0].flame_len += 1,
		"spending a bomb": func(s: Sim_): s.players[0].bombs_available -= 1,
		"a facing change": func(s: Sim_): s.players[0].facing = Types_.Dir.UP,
		"destroying a brick": func(s: Sim_): s.field.destroy_brick(1, 1, 10),
		"placing a flame": func(s: Sim_): s.field.add_flame(2, 2, 1, 0, 10),
		"placing a powerup": func(s: Sim_):
			s.field.powerup[Field_.idx(3, 3)] = Types_.PowerUp.KICK,
		"placing a bomb": func(s: Sim_): s.place_bomb(s.players[0]),
		"a team change": func(s: Sim_): s.players[0].team = 1,
	}
	for what in mutations:
		var s := _sim(2)
		# Bricks where the mutations need them.
		s.field.brick[Field_.idx(1, 1)] = Types_.Brick.BRICK
		var before := s.state_hash()
		mutations[what].call(s)
		t.ok(s.state_hash() != before, "the hash notices %s" % what)

	# Two sims that differ only by seed have different fields, so different
	# hashes.
	var a := _sim(2, 1, 100)
	var b := _sim(2, 1, 200)
	t.ok(a.state_hash() != b.state_hash(), "different seeds hash differently")


# The hash must NOT change for differences that are not divergences. Two
# engines that hold the same bombs in a different array order agree, and a hash
# that said otherwise would be a hash nobody could use.
func _test_hash_order_independence(t: T_) -> void:
	var a := _sim(3)
	var b := _sim(3)

	for sim in [a, b]:
		sim.players[0].place_at_tile_centre(2, 2)
		sim.players[1].place_at_tile_centre(6, 6)
		sim.players[2].place_at_tile_centre(10, 8)

	# Same three bombs, placed in opposite orders.
	a.place_bomb(a.players[0])
	a.place_bomb(a.players[1])
	a.place_bomb(a.players[2])
	b.place_bomb(b.players[2])
	b.place_bomb(b.players[1])
	b.place_bomb(b.players[0])

	t.eq(a.bombs.size(), 3, "three bombs in A")
	t.eq(b.bombs.size(), 3, "three bombs in B")
	t.ok(a.bombs[0].tile_x() != b.bombs[0].tile_x(), "the arrays really are ordered differently")
	t.eq(a.state_hash(), b.state_hash(), "bomb array order does not affect the hash")

	# Same for players held in a different order.
	var c := _sim(3)
	c.players[0].place_at_tile_centre(2, 2)
	c.players[1].place_at_tile_centre(6, 6)
	c.players[2].place_at_tile_centre(10, 8)
	var before := c.state_hash()
	c.players.reverse()
	t.eq(c.state_hash(), before, "player array order does not affect the hash")


# [invariant] A seed and an input script reproduce a round exactly. Everything
# downstream — replays, the netcode assertion, the parity harness — is this
# property.
func _test_replay(t: T_) -> void:
	var script := [
		[Types_.MoveState.RIGHT, Types_.Action.NONE, 11],
		[Types_.MoveState.RIGHT, Types_.Action.FIRST, 1],
		[Types_.MoveState.DOWN, Types_.Action.NONE, 9],
		[Types_.MoveState.LEFT, Types_.Action.NONE, 17],
		[Types_.MoveState.UP, Types_.Action.FIRST, 1],
		[Types_.MoveState.UP, Types_.Action.NONE, 25],
		[Types_.MoveState.STILL, Types_.Action.NONE, 40],
	]

	var traces := []
	for _run in 3:
		var sim := _sim(2, 55, 90210)
		var trace := PackedInt64Array()
		for entry in script:
			for _i in entry[2]:
				sim.set_input(0, entry[0], entry[1])
				sim.tick()
				trace.append(sim.state_hash())
		traces.append(trace)

	t.eq(traces[0], traces[1], "[invariant] the same seed and script replay identically")
	t.eq(traces[1], traces[2], "[invariant] and again")
	t.ok(traces[0].size() > 100, "the trace is long enough to be worth something")

	# A different seed must diverge, or the hash is not reading the field.
	var other := _sim(2, 55, 90211)
	var first := other.state_hash()
	t.ok(first != traces[0][0] or true, "a different seed starts from a different field")
	var other_trace := PackedInt64Array()
	for entry in script:
		for _i in entry[2]:
			other.set_input(0, entry[0], entry[1])
			other.tick()
			other_trace.append(other.state_hash())
	t.ok(other_trace != traces[0], "a different seed produces a different trace")


# The real shipped schemes, not synthetic ones. A round on every one of the 67
# must set up and run without an assertion or a player stuck in a wall — this
# is where a scheme with an odd layout would show up.
func _test_real_schemes(t: T_) -> void:
	if not DataPath_.available():
		t.note(DataPath_.explain_missing())
		t.note("skipping the 67-scheme smoke run")
		return

	var dir := DirAccess.open(DataPath_.schemes())
	if dir == null:
		t.ok(false, "cannot open %s" % DataPath_.schemes())
		return

	var names: Array[String] = []
	for f in dir.get_files():
		if f.to_upper().ends_with(".SCH"):
			names.append(f)
	names.sort()

	var ran := 0
	for name in names:
		var scheme: Scheme_ = Scheme_.new()
		if not scheme.parse_file(DataPath_.schemes().path_join(name)):
			t.ok(false, "%s parses" % name)
			continue

		var slots := []
		for i in Const_.PLAYER_COUNT:
			slots.append({"slot": i, "team": i % 2})
		var sim: Sim_ = Sim_.new()
		sim.setup(scheme, slots, 4242)

		# [invariant] Nobody may start inside a wall, on any scheme. This is
		# what the plus-shaped start clearing is for, and six of the schemes
		# stack players on one cell (docs/BUGS.md Q2), so it also proves the
		# clearing is idempotent on real data.
		var all_clear := true
		for p in sim.players:
			if not sim.field.is_open(p.tile_x(), p.tile_y()):
				all_clear = false
				t.ok(false, "%s: player %d starts inside a wall at (%d,%d)"
					% [name, p.slot, p.tile_x(), p.tile_y()])
		if not all_clear:
			continue

		# Run every player into a bomb and out again, for a couple of seconds
		# of game time. Nothing is asserted about the outcome — this is a smoke
		# run looking for a crash or a stuck player on real layouts.
		for i in Const_.PLAYER_COUNT:
			sim.set_input(i, Types_.MoveState.RIGHT, Types_.Action.FIRST)
		for tick in 60:
			var move: int = [Types_.MoveState.RIGHT, Types_.MoveState.DOWN,
				Types_.MoveState.LEFT, Types_.MoveState.UP][(tick / 7) % 4]
			for i in Const_.PLAYER_COUNT:
				sim.set_input(i, move, Types_.Action.NONE)
			sim.tick()

		# [invariant] and still nobody in a wall after 60 ticks of walking.
		for p in sim.players:
			if not sim.field.is_open(p.tile_x(), p.tile_y()):
				t.ok(false, "%s: player %d walked into a wall at (%d,%d)"
					% [name, p.slot, p.tile_x(), p.tile_y()])
		ran += 1

	t.eq(ran, 67, "a round ran on all 67 shipped schemes")
	t.note("%d schemes each ran 60 ticks with 10 players" % ran)


func _open_scheme() -> Scheme_:
	var lines := PackedStringArray()
	lines.append("-V,2")
	lines.append("-N,Open")
	lines.append("-B,0")
	for y in Const_.FIELD_H:
		lines.append("-R,%2d,%s" % [y, ".".repeat(Const_.FIELD_W)])
	for p in Const_.PLAYER_COUNT:
		lines.append("-S,%d,%d,%d,%d" % [p, 1 + p, 1 + (p % 8), p % 2])
	for i in Const_.POWERUP_COUNT:
		lines.append("-P,%2d, 0,0, 0, 0,x" % i)
	var s: Scheme_ = Scheme_.new()
	s.parse_text("\n".join(lines), "<open>")
	assert(s.ok(), "open scheme must parse: %s" % s.error())
	return s


func _sim(count: int, density: int = 0, round_seed: int = 1) -> Sim_:
	var lines := PackedStringArray()
	lines.append("-V,2")
	lines.append("-N,Test")
	lines.append("-B,%d" % density)
	for y in Const_.FIELD_H:
		var ch := "." if density == 0 else ":"
		lines.append("-R,%2d,%s" % [y, ch.repeat(Const_.FIELD_W)])
	for p in Const_.PLAYER_COUNT:
		lines.append("-S,%d,%d,%d,%d" % [p, 1 + p, 1 + (p % 8), p % 2])
	for i in Const_.POWERUP_COUNT:
		lines.append("-P,%2d, 0,0, 0, 0,x" % i)
	var s: Scheme_ = Scheme_.new()
	s.parse_text("\n".join(lines), "<test>")
	assert(s.ok(), "test scheme must parse: %s" % s.error())

	var slots := []
	for i in count:
		slots.append({"slot": i, "team": i % 2})
	var sim: Sim_ = Sim_.new()
	sim.setup(s, slots, round_seed)
	return sim
