# Movement: centipixel arithmetic, collision, cross-axis re-centring.
#
# The algorithm under test is ASSUMED, not established — docs/BUGS.md Q5.1.
# These assertions therefore pin what we chose and why, so that when BM.EXE
# settles the real rule the diff is visible instead of silent. The ones that
# are NOT assumptions, and would be bugs in any implementation, are marked
# `[invariant]`: staying on the field, never entering a blocked cell, and being
# reproducible.
extends SceneTree

const T_ := preload("res://tests/t.gd")
const Const_ := preload("res://scripts/core/const.gd")
const Types_ := preload("res://scripts/core/types.gd")
const Values_ := preload("res://scripts/core/values.gd")
const Scheme_ := preload("res://scripts/core/scheme.gd")
const Field_ := preload("res://scripts/sim/field.gd")
const Sim_ := preload("res://scripts/sim/sim.gd")
const Player_ := preload("res://scripts/sim/player.gd")

const TILE_W := Player_.TILE_W_CP   # 4000 centipixels
const TILE_H := Player_.TILE_H_CP   # 3600


func _init() -> void:
	var t := T_.new("movement")
	_test_units(t)
	_test_free_walk(t)
	_test_wall_stop(t)
	_test_field_edges(t)
	_test_recentring(t)
	_test_corner_blocking(t)
	_test_determinism(t)
	quit(t.finish())


# The unit conversions the whole sim rests on. 923 hundredths of a pixel per
# frame, one frame per tick.
func _test_units(t: T_) -> void:
	t.eq(TILE_W, 4000, "a cell is 4000 centipixels wide (40 px)")
	t.eq(TILE_H, 3600, "a cell is 3600 centipixels tall (36 px)")
	t.eq(Player_.tile_centre_x(0), 2000, "centre of column 0")
	t.eq(Player_.tile_centre_y(0), 1800, "centre of row 0")
	t.eq(Player_.tile_centre_x(14), 58000, "centre of column 14")
	t.eq(Player_.tile_centre_y(10), 39600 - 1800, "centre of row 10")

	var p: Player_ = Player_.new()
	p.place_at_tile_centre(3, 4)
	t.eq(p.x, 3 * 4000 + 2000, "placed at the centre of column 3")
	t.eq(p.y, 4 * 3600 + 1800, "placed at the centre of row 4")
	t.eq(p.tile_x(), 3, "tile_x reads back")
	t.eq(p.tile_y(), 4, "tile_y reads back")
	t.eq(p.offset_x(), 0, "no x offset when centred")
	t.eq(p.offset_y(), 0, "no y offset when centred")

	# One tick at the default speed moves exactly the tuning table's value —
	# the point of working in centipixels is that this is an integer add.
	var sim := _open_sim(1)
	var pl: Player_ = sim.players[0]
	var start_x := pl.x
	pl.move = Types_.MoveState.RIGHT
	sim.tick()
	t.eq(pl.x - start_x, Values_.V[Const_.Res.START_SPEED],
		"one tick moves exactly resource 42 centipixels")


# In an open corridor there is no constraint until the wall, so N ticks move
# exactly N * speed. [invariant] that it is exact — a rounding step would show
# up here as drift.
func _test_free_walk(t: T_) -> void:
	var sim := _open_sim(1)
	var p: Player_ = sim.players[0]
	p.place_at_tile_centre(1, 5)
	var start := p.x
	var speed := p.speed

	p.move = Types_.MoveState.RIGHT
	for _i in 20:
		sim.tick()
	t.eq(p.x - start, 20 * speed, "20 ticks move exactly 20 * speed")
	t.eq(p.offset_y(), 0, "walking right does not drift vertically")

	# And back again lands on exactly the same centipixel. [invariant]
	p.move = Types_.MoveState.LEFT
	for _i in 20:
		sim.tick()
	t.eq(p.x, start, "walking back returns to the exact starting centipixel")

	# Standing still moves nothing.
	p.move = Types_.MoveState.STILL
	var held := p.x
	for _i in 10:
		sim.tick()
	t.eq(p.x, held, "STILL does not move the player")


# The cell-sized collision box stops the player with their centre on the centre
# of the last open cell. This is the assumed model — see sim.gd's _move_player.
func _test_wall_stop(t: T_) -> void:
	var sim := _open_sim(1)
	var p: Player_ = sim.players[0]
	p.place_at_tile_centre(1, 5)
	# Wall at column 6, so the player should come to rest centred on column 5.
	for y in Const_.FIELD_H:
		sim.field.brick[Field_.idx(6, y)] = Types_.Brick.SOLID

	p.move = Types_.MoveState.RIGHT
	for _i in 60:
		sim.tick()
	t.eq(p.tile_x(), 5, "stops in the cell before the wall")
	t.eq(p.offset_x(), 0, "comes to rest centred on that cell")
	t.eq(p.x, Player_.tile_centre_x(5), "resting x is the cell centre")
	# [invariant] never inside the wall, whatever the algorithm.
	t.ok(sim.field.is_open(p.tile_x(), p.tile_y()),
		"[invariant] the player never occupies a blocked cell")

	# Pushing further changes nothing — no jitter, no creep.
	var settled := p.x
	for _i in 20:
		sim.tick()
	t.eq(p.x, settled, "pushing into a wall does not creep")

	# The same going left, up and down.
	var s2 := _open_sim(1)
	var p2: Player_ = s2.players[0]
	p2.place_at_tile_centre(8, 5)
	for y in Const_.FIELD_H:
		s2.field.brick[Field_.idx(3, y)] = Types_.Brick.SOLID
	p2.move = Types_.MoveState.LEFT
	for _i in 60:
		s2.tick()
	t.eq(p2.tile_x(), 4, "stops before a wall to the left")
	t.eq(p2.offset_x(), 0, "rests centred going left")

	var s3 := _open_sim(1)
	var p3: Player_ = s3.players[0]
	p3.place_at_tile_centre(7, 8)
	for x in Const_.FIELD_W:
		s3.field.brick[Field_.idx(x, 3)] = Types_.Brick.SOLID
	p3.move = Types_.MoveState.UP
	for _i in 60:
		s3.tick()
	t.eq(p3.tile_y(), 4, "stops before a wall above")
	t.eq(p3.offset_y(), 0, "rests centred going up")

	var s4 := _open_sim(1)
	var p4: Player_ = s4.players[0]
	p4.place_at_tile_centre(7, 2)
	for x in Const_.FIELD_W:
		s4.field.brick[Field_.idx(x, 8)] = Types_.Brick.SOLID
	p4.move = Types_.MoveState.DOWN
	for _i in 60:
		s4.tick()
	t.eq(p4.tile_y(), 7, "stops before a wall below")
	t.eq(p4.offset_y(), 0, "rests centred going down")

	# A destructible brick blocks exactly as a solid does.
	var s5 := _open_sim(1)
	var p5: Player_ = s5.players[0]
	p5.place_at_tile_centre(1, 5)
	s5.field.brick[Field_.idx(4, 5)] = Types_.Brick.BRICK
	p5.move = Types_.MoveState.RIGHT
	for _i in 60:
		s5.tick()
	t.eq(p5.tile_x(), 3, "a brick blocks like a solid")


# [invariant] The field border holds without a special case, because off-field
# reads as blocked. The left and top edges are the ones that matter: they need
# flooring division, and truncating division would let a player walk out.
func _test_field_edges(t: T_) -> void:
	var sim := _open_sim(1)
	var p: Player_ = sim.players[0]

	p.place_at_tile_centre(3, 5)
	p.move = Types_.MoveState.LEFT
	for _i in 200:
		sim.tick()
	t.eq(p.tile_x(), 0, "[invariant] stops at the left edge")
	t.eq(p.x, Player_.tile_centre_x(0), "rests centred in column 0")
	t.ok(p.x > 0, "[invariant] never reaches a negative x")

	p.place_at_tile_centre(5, 3)
	p.move = Types_.MoveState.UP
	for _i in 200:
		sim.tick()
	t.eq(p.tile_y(), 0, "[invariant] stops at the top edge")
	t.ok(p.y > 0, "[invariant] never reaches a negative y")

	p.move = Types_.MoveState.RIGHT
	for _i in 400:
		sim.tick()
	t.eq(p.tile_x(), Const_.FIELD_W - 1, "[invariant] stops at the right edge")

	p.move = Types_.MoveState.DOWN
	for _i in 400:
		sim.tick()
	t.eq(p.tile_y(), Const_.FIELD_H - 1, "[invariant] stops at the bottom edge")

	# The flooring-division helper directly, since it is what makes the left
	# and top edges hold.
	t.eq(Sim_._floor_div(-1, 4000), -1, "floor_div(-1, 4000) is -1, not 0")
	t.eq(Sim_._floor_div(-4000, 4000), -1, "floor_div(-4000, 4000)")
	t.eq(Sim_._floor_div(-4001, 4000), -2, "floor_div(-4001, 4000)")
	t.eq(Sim_._floor_div(0, 4000), 0, "floor_div(0, 4000)")
	t.eq(Sim_._floor_div(3999, 4000), 0, "floor_div(3999, 4000)")
	t.eq(Sim_._floor_div(4000, 4000), 1, "floor_div(4000, 4000)")


# Cross-axis re-centring, from AtomBomberman's "the game corrects the position
# itself to help the player". Assumed in its details.
func _test_recentring(t: T_) -> void:
	var sim := _open_sim(1)
	var p: Player_ = sim.players[0]
	p.place_at_tile_centre(5, 5)

	# Nudge off-centre vertically, then walk horizontally: the drift should be
	# pulled out, by at most `speed` per tick.
	p.y += 1000
	t.eq(p.offset_y(), 1000, "the nudge took effect")
	p.move = Types_.MoveState.RIGHT
	sim.tick()
	t.eq(p.offset_y(), 1000 - mini(1000, p.speed),
		"one tick of walking pulls the drift in by at most speed")
	for _i in 10:
		sim.tick()
	t.eq(p.offset_y(), 0, "walking horizontally re-centres vertically")

	# And the other way round.
	var s2 := _open_sim(1)
	var p2: Player_ = s2.players[0]
	p2.place_at_tile_centre(5, 5)
	p2.x -= 1500
	p2.move = Types_.MoveState.DOWN
	for _i in 10:
		s2.tick()
	t.eq(p2.offset_x(), 0, "walking vertically re-centres horizontally")

	# Re-centring must never overshoot into oscillation: from any offset, it
	# converges and stays put. [invariant]
	for offset in [-1999, -1000, -1, 1, 1000, 1999]:
		var s3 := _open_sim(1)
		var p3: Player_ = s3.players[0]
		p3.place_at_tile_centre(5, 5)
		p3.y += offset
		p3.move = Types_.MoveState.RIGHT
		for _i in 30:
			s3.tick()
		t.eq(p3.offset_y(), 0,
			"[invariant] re-centring converges from offset %d" % offset)


# A player who is not aligned on the cross axis spans two rows, and both must
# be clear to move. This is what stops a diagonal cut past a wall corner.
func _test_corner_blocking(t: T_) -> void:
	var sim := _open_sim(1)
	var p: Player_ = sim.players[0]
	p.place_at_tile_centre(5, 5)
	# A wall in row 5 only, at column 6. Row 4 is open.
	sim.field.brick[Field_.idx(6, 5)] = Types_.Brick.SOLID

	# Drift upward so the box spans rows 4 and 5, then push right. Row 5 is
	# blocked, so the move must not happen even though row 4 is clear.
	p.y -= 1200
	var before := p.x
	p.move = Types_.MoveState.RIGHT
	sim.tick()
	# Re-centring pulls back toward row 5's centre, and the blocked row 5
	# prevents the horizontal move while the box still touches it.
	t.ok(p.x == before or p.x == Player_.tile_centre_x(5),
		"a box spanning a blocked row cannot slide past the corner")
	t.ok(sim.field.is_open(p.tile_x(), p.tile_y()),
		"[invariant] still not inside a blocked cell")

	# Once fully in row 4, moving right is fine.
	var s2 := _open_sim(1)
	var p2: Player_ = s2.players[0]
	p2.place_at_tile_centre(5, 4)
	s2.field.brick[Field_.idx(6, 5)] = Types_.Brick.SOLID
	p2.move = Types_.MoveState.RIGHT
	for _i in 20:
		s2.tick()
	t.ok(p2.tile_x() > 5, "row 4 is clear, so the player walks past")


# [invariant] Same inputs, same result — the property Phase 5's state_hash
# assertion and Track C's parity diff both depend on.
func _test_determinism(t: T_) -> void:
	var script := [
		[Types_.MoveState.RIGHT, 13], [Types_.MoveState.DOWN, 7],
		[Types_.MoveState.LEFT, 21], [Types_.MoveState.UP, 4],
		[Types_.MoveState.RIGHT, 9], [Types_.MoveState.STILL, 3],
	]
	var runs := []
	for _r in 3:
		var sim := _open_sim(1, 777)
		var p: Player_ = sim.players[0]
		p.place_at_tile_centre(7, 5)
		for entry in script:
			p.move = entry[0]
			for _i in entry[1]:
				sim.tick()
		runs.append([p.x, p.y, sim.state_hash()])
	t.eq(runs[0], runs[1], "[invariant] the same input script gives the same state")
	t.eq(runs[1], runs[2], "[invariant] and again on a third run")


# A sim on a wholly open field, so movement is tested against nothing but what
# each case puts there.
func _open_sim(count: int, round_seed: int = 1) -> Sim_:
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
	sim.setup(s, slots, round_seed)
	return sim
