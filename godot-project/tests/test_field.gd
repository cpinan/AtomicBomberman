# Field layout: density thinning, start clearing, walkability, flame planes.
#
# Runs entirely on synthetic schemes so it needs no copy of the original game.
extends SceneTree

const T_ := preload("res://tests/t.gd")
const Const_ := preload("res://scripts/core/const.gd")
const Types_ := preload("res://scripts/core/types.gd")
const Scheme_ := preload("res://scripts/core/scheme.gd")
const Field_ := preload("res://scripts/sim/field.gd")


func _init() -> void:
	var t := T_.new("field")
	_test_indexing(t)
	_test_density(t)
	_test_start_clearing(t)
	_test_walkability(t)
	_test_flame_plane(t)
	_test_brick_destruction(t)
	_test_bytes(t)
	quit(t.finish())


func _test_indexing(t: T_) -> void:
	t.eq(Field_.idx(0, 0), 0, "idx(0,0)")
	t.eq(Field_.idx(14, 0), 14, "idx(14,0)")
	t.eq(Field_.idx(0, 1), Const_.FIELD_W, "idx(0,1)")
	t.eq(Field_.idx(14, 10), Field_.CELLS - 1, "idx of the last cell")

	# The border must be blocked without anyone testing for it, because every
	# movement and flame path relies on off-field reading as "blocked".
	t.ok(not Field_.in_bounds(-1, 0), "x = -1 is off the field")
	t.ok(not Field_.in_bounds(0, -1), "y = -1 is off the field")
	t.ok(not Field_.in_bounds(Const_.FIELD_W, 0), "x = 15 is off the field")
	t.ok(not Field_.in_bounds(0, Const_.FIELD_H), "y = 11 is off the field")
	t.ok(Field_.in_bounds(14, 10), "(14,10) is on the field")


# Density is `density > randi_range(0, 99)`, following fpc_atomic. The two
# boundary values are the ones worth asserting exactly: 100 must keep every
# brick and 0 must keep none, whatever the seed.
func _test_density(t: T_) -> void:
	var all_brick := _scheme(":", 100)
	var all_solid := _scheme("#", 100)

	for seed_value in [0, 1, 12345, 999999]:
		var f: Field_ = Field_.new()
		f.initialize(all_brick, [], _rng(seed_value))
		t.eq(f.count_of(Types_.Brick.BRICK), Field_.CELLS,
			"density 100 keeps every brick (seed %d)" % seed_value)

	for seed_value in [0, 1, 12345, 999999]:
		var f: Field_ = Field_.new()
		f.initialize(_scheme(":", 0), [], _rng(seed_value))
		t.eq(f.count_of(Types_.Brick.BRICK), 0,
			"density 0 keeps no bricks (seed %d)" % seed_value)

	# Solids are structural and density must not touch them at all.
	var f_solid: Field_ = Field_.new()
	f_solid.initialize(all_solid, [], _rng(7))
	t.eq(f_solid.count_of(Types_.Brick.SOLID), Field_.CELLS,
		"density does not thin solids")

	# A mid density must land near its nominal rate. Averaged over several
	# seeds, because a single seed can legitimately sit some way off.
	var total := 0
	var runs := 40
	for seed_value in runs:
		var f: Field_ = Field_.new()
		f.initialize(_scheme(":", 50), [], _rng(seed_value))
		total += f.count_of(Types_.Brick.BRICK)
	var mean := float(total) / runs / Field_.CELLS
	t.close(mean, 0.5, 0.05, "density 50 keeps about half the bricks")

	# Same seed, same layout — the property every replay and every parity run
	# depends on.
	var a: Field_ = Field_.new()
	var b: Field_ = Field_.new()
	a.initialize(_scheme(":", 60), [], _rng(4242))
	b.initialize(_scheme(":", 60), [], _rng(4242))
	t.eq(a.to_bytes(), b.to_bytes(), "same seed gives an identical field")

	var c: Field_ = Field_.new()
	c.initialize(_scheme(":", 60), [], _rng(4243))
	t.ok(a.to_bytes() != c.to_bytes(), "a different seed gives a different field")


# Each live player's cell and its four orthogonal neighbours are blanked, so
# nobody is walled in at tick zero. Follows fpc_atomic's Initialize.
func _test_start_clearing(t: T_) -> void:
	var f: Field_ = Field_.new()
	f.initialize(_scheme(":", 100), [{"x": 5, "y": 5}], _rng(1))

	t.ok(f.is_open(5, 5), "the start cell is cleared")
	t.ok(f.is_open(4, 5), "the cell left of the start is cleared")
	t.ok(f.is_open(6, 5), "the cell right of the start is cleared")
	t.ok(f.is_open(5, 4), "the cell above the start is cleared")
	t.ok(f.is_open(5, 6), "the cell below the start is cleared")
	# A plus, not a square: the diagonals stay.
	t.ok(not f.is_open(4, 4), "the diagonal is not cleared")
	t.ok(not f.is_open(6, 6), "the other diagonal is not cleared")
	t.eq(f.count_of(Types_.Brick.BLANK), 5, "exactly five cells cleared")

	# A corner start clips off-field without erroring, and clears the three
	# cells that exist.
	var corner: Field_ = Field_.new()
	corner.initialize(_scheme(":", 100), [{"x": 0, "y": 0}], _rng(1))
	t.ok(corner.is_open(0, 0), "corner start cell cleared")
	t.ok(corner.is_open(1, 0), "corner start, right cleared")
	t.ok(corner.is_open(0, 1), "corner start, below cleared")
	t.eq(corner.count_of(Types_.Brick.BLANK), 3,
		"a corner start clears three cells, not five")

	# Clearing must beat a solid too, or a scheme could seal a player in.
	var solid: Field_ = Field_.new()
	solid.initialize(_scheme("#", 100), [{"x": 7, "y": 5}], _rng(1))
	t.ok(solid.is_open(7, 5), "start clearing removes a solid on the start cell")
	t.ok(solid.is_open(7, 4), "start clearing removes an adjacent solid")

	# Ten players stacked on one cell — CONFUSED.SCH does exactly this
	# (docs/BUGS.md Q2). Clearing must be idempotent, not cumulative.
	var stacked := []
	for _i in 10:
		stacked.append({"x": 7, "y": 5})
	var many: Field_ = Field_.new()
	many.initialize(_scheme(":", 100), stacked, _rng(1))
	t.eq(many.count_of(Types_.Brick.BLANK), 5,
		"ten players on one cell clears the same five cells")


func _test_walkability(t: T_) -> void:
	var f: Field_ = Field_.new()
	f.initialize(_scheme(".", 100), [], _rng(1))
	t.ok(f.is_open(0, 0), "a blank cell is open")

	f.brick[Field_.idx(3, 3)] = Types_.Brick.SOLID
	f.brick[Field_.idx(4, 3)] = Types_.Brick.BRICK
	t.ok(not f.is_open(3, 3), "a solid cell is not open")
	t.ok(not f.is_open(4, 3), "a brick cell is not open")

	# Off-field reads as blocked, which is what keeps players inside without a
	# separate border check anywhere.
	t.ok(not f.is_open(-1, 5), "off the left edge is not open")
	t.ok(not f.is_open(Const_.FIELD_W, 5), "off the right edge is not open")
	t.ok(not f.is_open(5, -1), "off the top edge is not open")
	t.ok(not f.is_open(5, Const_.FIELD_H), "off the bottom edge is not open")


func _test_flame_plane(t: T_) -> void:
	var f: Field_ = Field_.new()
	f.initialize(_scheme(".", 100), [], _rng(1))

	t.ok(not f.has_flame(2, 2), "no flame to begin with")
	f.add_flame(2, 2, Types_.Flame.CROSS, 3, 10)
	t.ok(f.has_flame(2, 2), "flame added")
	t.eq(f.flame_owner_at(2, 2), 3, "flame owner recorded")

	# Arms accumulate: one cell can be the crossing point of two bombs.
	f.add_flame(2, 2, Types_.Flame.LEFT, 4, 10)
	t.eq(f.flame_at(2, 2), Types_.Flame.CROSS | Types_.Flame.LEFT,
		"flame arms accumulate on one cell")
	t.eq(f.flame_owner_at(2, 2), 4,
		"the later flame owns the cell (one flame per tile, the last)")

	# It must expire exactly on schedule: 10 ticks, so present on 9 and gone
	# on 10.
	for i in 9:
		f.tick_timers()
		t.ok(f.has_flame(2, 2), "flame still burning after %d ticks" % (i + 1))
	f.tick_timers()
	t.ok(not f.has_flame(2, 2), "flame is out after 10 ticks")
	t.eq(f.flame_owner_at(2, 2), Field_.NO_OWNER,
		"flame owner cleared when it burns out")

	# Off-field flame writes are dropped rather than crashing, because flame
	# propagation walks outward and will ask.
	f.add_flame(-1, 5, Types_.Flame.LEFT, 0, 10)
	t.ok(not f.has_flame(-1, 5), "an off-field flame write is dropped")


func _test_brick_destruction(t: T_) -> void:
	var f: Field_ = Field_.new()
	f.initialize(_scheme(":", 100), [], _rng(1))

	t.ok(not f.is_open(5, 5), "the brick is there to begin with")
	f.destroy_brick(5, 5, 10)
	# Walkable at once: the timer is only the disintegration animation.
	t.ok(f.is_open(5, 5), "a destroyed brick is walkable immediately")
	t.eq(f.brick_timer[Field_.idx(5, 5)], 10, "disintegration timer set")

	for _i in 10:
		f.tick_timers()
	t.eq(f.brick_timer[Field_.idx(5, 5)], 0, "disintegration timer runs out")
	t.ok(f.is_open(5, 5), "the cell stays walkable afterwards")

	# Destroying a solid, or an already-empty cell, must be a no-op.
	f.brick[Field_.idx(6, 6)] = Types_.Brick.SOLID
	f.destroy_brick(6, 6, 10)
	t.ok(not f.is_open(6, 6), "a solid cannot be destroyed")
	t.eq(f.brick_timer[Field_.idx(6, 6)], 0, "no animation on a solid")


func _test_bytes(t: T_) -> void:
	var f: Field_ = Field_.new()
	f.initialize(_scheme(":", 100), [], _rng(1))
	# Six planes of 165 cells. Asserted because state_hash() depends on the
	# whole field being in here; a plane added later without being appended
	# would be invisible to every parity test.
	t.eq(f.to_bytes().size(), Field_.CELLS * 6, "to_bytes covers six planes")

	var before := f.to_bytes()
	f.destroy_brick(5, 5, 10)
	t.ok(f.to_bytes() != before, "destroying a brick changes the bytes")

	var before_flame := f.to_bytes()
	f.add_flame(1, 1, Types_.Flame.CROSS, 0, 10)
	t.ok(f.to_bytes() != before_flame, "adding a flame changes the bytes")


# A scheme whose every cell is `ch`, at the given density. Solid borders are
# deliberately absent so that edge behaviour is exercised by the field's own
# bounds checks rather than masked by a wall.
func _scheme(ch: String, density: int) -> Scheme_:
	var lines := PackedStringArray()
	lines.append("-V,2")
	lines.append("-N,Synthetic")
	lines.append("-B,%d" % density)
	for y in Const_.FIELD_H:
		lines.append("-R,%2d,%s" % [y, ch.repeat(Const_.FIELD_W)])
	for p in Const_.PLAYER_COUNT:
		lines.append("-S,%d,%d,0,%d" % [p, p, p % 2])
	for i in Const_.POWERUP_COUNT:
		lines.append("-P,%2d, 0,0, 0, 0,x" % i)
	var s: Scheme_ = Scheme_.new()
	s.parse_text("\n".join(lines), "<synthetic>")
	assert(s.ok(), "synthetic scheme must parse: %s" % s.error())
	return s


func _rng(seed_value: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	return r
