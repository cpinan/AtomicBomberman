# The playfield: 15x11 cells of structural content, powerups and flame.
#
# Stored as parallel PackedByteArrays indexed y * FIELD_W + x rather than as an
# array of cell objects. Three reasons, in order of how much they matter:
#
#   1. state_hash() and the netcode both need the whole field as bytes. With
#      byte arrays that is a concatenation; with objects it is a serialisation
#      pass that has to be kept in step with the fields by hand.
#   2. 165 cells broadcast 50 times a second is the hot path of Phase 5.
#   3. A missing field in a byte array is a compile error, not a null.
#
# Everything here is integer. See sim.gd on why the simulation has no floats.
extends RefCounted

const Const_ := preload("res://scripts/core/const.gd")
const Types_ := preload("res://scripts/core/types.gd")
const Values := preload("res://scripts/core/values.gd")
const Extras := preload("res://scripts/core/extras.gd")

const CELLS := Const_.FIELD_W * Const_.FIELD_H

## Sentinel for the powerup and owner planes. 255 rather than a NONE enum
## member, so that Types.PowerUp keeps the exact ordinals the scheme file's -P
## lines and VALUELST's 400/550/50 blocks are indexed by.
const NO_POWERUP := 255
const NO_OWNER := 255

## Structural content: Types.Brick.
var brick := PackedByteArray()

## What is revealed when a brick here is destroyed: Types.PowerUp or
## NO_POWERUP. Placement is Phase 4; this plane exists in Phase 2 because
## flames stop on powerups and the stop rule is part of flame propagation.
var powerup := PackedByteArray()

## Which arms of a flame cross occupy the cell: Types.Flame bit flags.
var flame := PackedByteArray()

## Whose bomb produced the flame, for kill attribution. When bomb A ignites
## bomb B and B's flame kills someone, A's owner gets the kill — so this
## carries the ORIGINATING owner, not the owner of the bomb that made the
## flame. AtomBomberman's notes and fpc_atomic 0.11006 agree on this.
var flame_owner := PackedByteArray()

## Ticks of flame left on the cell. VALUELST resource 10 = 10 frames = 500 ms.
var flame_timer := PackedByteArray()

## ---------------------------------------------------------------------------
## LEVEL GEOMETRY. Four planes that never change once a round starts.
## ---------------------------------------------------------------------------
##
## Deliberately NOT part of to_bytes(), so they are not re-sent 20 times a
## second for data that cannot change. Both sides build them from the level
## number and the round seed, which the client receives in its welcome, and
## static_bytes() feeds them into state_hash() — so a divergence is still
## caught, it just costs nothing per tick.
##
## Their coordinates come from the original's own EXTRA*.RES via
## scripts/core/extras.gd; nothing here is invented except where noted.

## Arrows push a MOVING bomb in their direction. Types.Dir, 0 for none.
##
## A bomb PLACED on an arrow is not moved by it — AtomBomberman's notes: "when
## bomb is put on an arrow, or its thrown onto it, it doesnt move because of
## the arrow". Only something already rolling is redirected.
var arrow := PackedByteArray()

## Conveyors carry whatever stands on them. Types.Dir, 0 for none. Their three
## speeds are resources 190-192 (250 / 350 / 450 hundredths of a px per frame).
var conveyor := PackedByteArray()

## Warp gates. Gate index PLUS ONE, so 0 means "no gate here".
var warp := PackedByteArray()

## Where each gate leads, and where each gate is. Straight from EXTRA4.RES,
## whose ring is 0 -> 3 -> 2 -> 1 -> 0.
var warp_target: PackedInt32Array = PackedInt32Array()
var warp_cell: Array[Vector2i] = []

## Trampolines launch a player who steps on one. 1 or 0.
var tramp := PackedByteArray()

## Seconds between attempts to regenerate a destroyed brick, or 0 for never.
## Resource 347 makes the haunted house the only level with any, at 4 seconds,
## and resource 695 keeps them away from players by 4 cells.
var regen_interval: int = 0
var regen_clear_radius: int = 0
var _regen_countdown: int = 0

## Milliseconds of control delay from ice. Resource 452 gives the hockey rink
## 250 and every other level 0 — fpc_atomic has ice on no level at all.
var ice_delay_ms: int = 0

## Ticks of brick-disintegration animation left. The brick is already BLANK and
## already walkable; this is a render hint only. Resource 20 = 10 frames.
var brick_timer := PackedByteArray()


func _init() -> void:
	brick.resize(CELLS)
	powerup.resize(CELLS)
	flame.resize(CELLS)
	flame_owner.resize(CELLS)
	flame_timer.resize(CELLS)
	brick_timer.resize(CELLS)
	arrow.resize(CELLS)
	conveyor.resize(CELLS)
	warp.resize(CELLS)
	tramp.resize(CELLS)
	_clear()


func _clear() -> void:
	brick.fill(Types_.Brick.BLANK)
	powerup.fill(NO_POWERUP)
	flame.fill(0)
	flame_owner.fill(NO_OWNER)
	flame_timer.fill(0)
	brick_timer.fill(0)
	arrow.fill(0)
	conveyor.fill(0)
	warp.fill(0)
	tramp.fill(0)
	warp_target = PackedInt32Array()
	warp_cell = []
	regen_interval = 0
	regen_clear_radius = 0
	_regen_countdown = 0
	ice_delay_ms = 0


static func idx(x: int, y: int) -> int:
	return y * Const_.FIELD_W + x


static func in_bounds(x: int, y: int) -> bool:
	return x >= 0 and x < Const_.FIELD_W and y >= 0 and y < Const_.FIELD_H


## Lay out a round from a scheme.
##
## Follows fpc_atomic's TAtomicField.Initialize for the two rules the original's
## data files do not state:
##
##   density  `density > rng.randi_range(0, 99)` — so -B,100 keeps every brick
##            and -B,90 keeps 90% of them. 54 of the 67 shipped schemes are 100.
##   starts   each live player's cell AND its four orthogonal neighbours are
##            blanked, so nobody is walled in at tick zero.
##
## Powerup placement is deliberately NOT done here. fpc_atomic rolls a uniform
## 1-in-15 per brick, but the original specifies exact per-level counts in
## VALUELST 400..412 with "negative means that many 1-in-10 rolls". Those two
## are not the same distribution, so guessing now would bake in a divergence
## that Phase 4 would then have to find. docs/BUGS.md Q5.
##
## `starts` is an array of {"x": int, "y": int} for the players that are
## actually in the round — pass only live slots.
func initialize(scheme: RefCounted, starts: Array, rng: RandomNumberGenerator) -> void:
	_clear()

	for y in Const_.FIELD_H:
		for x in Const_.FIELD_W:
			var i := idx(x, y)
			var kind: int = scheme.cell(x, y)
			if kind == Types_.Brick.BRICK:
				# Thin the destructible bricks by the scheme's density.
				var keep: bool = scheme.density > rng.randi_range(0, 99)
				brick[i] = Types_.Brick.BRICK if keep else Types_.Brick.BLANK
			else:
				brick[i] = kind

	for s in starts:
		var sx: int = s["x"]
		var sy: int = s["y"]
		_blank(sx, sy)
		_blank(sx - 1, sy)
		_blank(sx + 1, sy)
		_blank(sx, sy - 1)
		_blank(sx, sy + 1)

	place_powerups(scheme, rng)


## Hide powerups under the destructible bricks.
##
## ASSUMED ALGORITHM — docs/BUGS.md Q5.2. What the data states, and what it
## does not:
##
##   VALUELST 400..412 gives a count per powerup, and its comment explains the
##   negative case: "a negative number here indicates how many times we'll do a
##   1-in-10 chance of putting the powerup down". So bombs are 10, flames 10,
##   goldflame -2 (two 1-in-10 rolls), trigger -4, super bad disease -4.
##
##   A scheme's -P row can override the count (has_override + override) or
##   forbid the powerup outright (forbidden), and both are honoured here.
##
##   What is NOT stated is WHERE they go. This places each one on a uniformly
##   chosen brick cell that has no powerup yet, which is the simplest rule
##   consistent with the counts.
##
## Deliberately NOT fpc_atomic's algorithm: it rolls a uniform 1-in-15 per
## brick, which produces a different distribution AND a different total from
## the counts the original tabulates. Following the counts is the more
## defensible guess because the counts are data and the scatter is not.
func place_powerups(scheme: RefCounted, rng: RandomNumberGenerator) -> void:
	# Every brick cell is a candidate. Collected first so that "somewhere with
	# no powerup yet" is a cheap check rather than a re-scan.
	var candidates: Array[int] = []
	for y in Const_.FIELD_H:
		for x in Const_.FIELD_W:
			if brick[idx(x, y)] == Types_.Brick.BRICK:
				candidates.append(idx(x, y))
	if candidates.is_empty():
		return

	for which in Const_.POWERUP_COUNT:
		var row: Dictionary = scheme.powerups[which]
		if row.get("forbidden", false):
			continue

		var count: int = Values.V[Const_.Res.SPAWN_BASE + which]
		if row.get("has_override", false):
			count = row.get("override", 0)

		var wanted := 0
		if count >= 0:
			wanted = count
		else:
			# Negative: that many 1-in-10 rolls, per the resource's own comment.
			for _roll in absi(count):
				if rng.randi_range(1, 10) == 1:
					wanted += 1

		for _i in wanted:
			if candidates.is_empty():
				return
			var pick := rng.randi_range(0, candidates.size() - 1)
			var cell: int = candidates[pick]
			# Remove rather than retry, so one cell never gets two powerups and
			# the loop cannot spin when the field is nearly full.
			candidates.remove_at(pick)
			powerup[cell] = which


## Lay in the level's specials.
##
## Every coordinate comes from the original's EXTRA*.RES, already resolved by
## tools/extras.py — the source files use negative values to wrap from the
## right and bottom edges and that is applied at generation time.
##
## Called AFTER the bricks are placed and the starts cleared, because a special
## needs its cell to be walkable: an arrow under a brick would do nothing until
## the brick was destroyed, and a warp gate under one would strand a player.
func load_extras(level: int, starts: Array, rng: RandomNumberGenerator,
		hurry: bool = false) -> void:
	var data: Dictionary = Extras.of_level(level)

	for a in data["arrows"] as Array:
		var i := idx(int(a["x"]), int(a["y"]))
		arrow[i] = Types_.DIR_NAMES[a["dir"]]
		_clear_for_special(int(a["x"]), int(a["y"]))

	for c in data["conveyors"] as Array:
		var i2 := idx(int(c["x"]), int(c["y"]))
		conveyor[i2] = Types_.DIR_NAMES[c["dir"]]
		_clear_for_special(int(c["x"]), int(c["y"]))

	# Holes and trampolines are DISABLED in Hurry mode. ORACLE row 22 and
	# fpc_atomic 0.13001, which cites the two levels' own wiki pages: a closing
	# field plus a teleport is a way to be crushed with no escape.
	if not hurry:
		var gates: Array = data["warps"]
		warp_target.resize(gates.size())
		warp_cell.resize(gates.size())
		for w in gates:
			var g := int(w["gate"])
			var wx := int(w["x"])
			var wy := int(w["y"])
			warp[idx(wx, wy)] = g + 1
			warp_target[g] = int(w["to"])
			warp_cell[g] = Vector2i(wx, wy)
			_clear_for_special(wx, wy)
			# A gate must have somewhere to walk to, or a player arriving is
			# walled in. fpc_atomic does the same.
			if not (is_open(wx - 1, wy) or is_open(wx + 1, wy)
					or is_open(wx, wy - 1) or is_open(wx, wy + 1)):
				var dirs := [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1),
					Vector2i(0, 1)]
				var pick: Vector2i = dirs[rng.randi_range(0, 3)]
				_clear_for_special(wx + pick.x, wy + pick.y)

		for tr in data["tramps"] as Array:
			tramp[idx(int(tr["x"]), int(tr["y"]))] = 1
			_clear_for_special(int(tr["x"]), int(tr["y"]))

		# EXTRA9 marks four of its eight trampolines "H,H" — placed at random.
		# Never on a player's start cell, or the round would begin with someone
		# already in the air.
		var wanted := int(data["random_tramps"])
		var guard := 0
		while wanted > 0 and guard < 1000:
			guard += 1
			var rx := rng.randi_range(0, Const_.FIELD_W - 1)
			var ry := rng.randi_range(0, Const_.FIELD_H - 1)
			var i3 := idx(rx, ry)
			if tramp[i3] != 0 or warp[i3] != 0 or arrow[i3] != 0 \
					or conveyor[i3] != 0:
				continue
			var on_start := false
			for st in starts:
				if int(st["x"]) == rx and int(st["y"]) == ry:
					on_start = true
					break
			if on_start:
				continue
			tramp[i3] = 1
			_clear_for_special(rx, ry)
			wanted -= 1

	# Regenerating bricks and ice are per-level values from VALUELST rather
	# than an EXTRA file.
	regen_interval = Values.V[Const_.Res.REGEN_INTERVAL_BASE + level]
	regen_clear_radius = Values.V[Const_.Res.REGEN_CLEAR_RADIUS]
	_regen_countdown = regen_interval * Const_.TICK_HZ
	ice_delay_ms = Values.V[Const_.Res.ICE_DELAY_BASE + level]


func arrow_at(x: int, y: int) -> int:
	return arrow[idx(x, y)] if in_bounds(x, y) else 0


func conveyor_at(x: int, y: int) -> int:
	return conveyor[idx(x, y)] if in_bounds(x, y) else 0


func tramp_at(x: int, y: int) -> bool:
	return in_bounds(x, y) and tramp[idx(x, y)] != 0


## The gate on a cell, or -1.
func warp_at(x: int, y: int) -> int:
	if not in_bounds(x, y):
		return -1
	var v := warp[idx(x, y)]
	return int(v) - 1 if v > 0 else -1


## Where a gate leads, as a cell.
func warp_exit(gate: int) -> Vector2i:
	if gate < 0 or gate >= warp_target.size():
		return Vector2i(-1, -1)
	var to := warp_target[gate]
	if to < 0 or to >= warp_cell.size():
		return Vector2i(-1, -1)
	return warp_cell[to]


## Try to grow a brick back. Resource 347 gives the interval and 695 the radius
## players must be outside of. Returns the cell it grew on, or (-1,-1).
func tick_regen(player_cells: Array, rng: RandomNumberGenerator) -> Vector2i:
	if regen_interval <= 0:
		return Vector2i(-1, -1)
	_regen_countdown -= 1
	if _regen_countdown > 0:
		return Vector2i(-1, -1)
	_regen_countdown = regen_interval * Const_.TICK_HZ

	var candidates: Array[Vector2i] = []
	for y in Const_.FIELD_H:
		for x in Const_.FIELD_W:
			var i := idx(x, y)
			if brick[i] != Types_.Brick.BLANK or powerup[i] != NO_POWERUP:
				continue
			if flame[i] != 0 or tramp[i] != 0 or warp[i] != 0 \
					or arrow[i] != 0 or conveyor[i] != 0:
				continue
			var clear := true
			for cell in player_cells:
				if absi(int(cell.x) - x) <= regen_clear_radius \
						and absi(int(cell.y) - y) <= regen_clear_radius:
					clear = false
					break
			if clear:
				candidates.append(Vector2i(x, y))
	if candidates.is_empty():
		return Vector2i(-1, -1)
	var pick: Vector2i = candidates[rng.randi_range(0, candidates.size() - 1)]
	brick[idx(pick.x, pick.y)] = Types_.Brick.BRICK
	return pick


## The level geometry, for hashing. Not sent per tick — see the planes above.
func static_bytes() -> PackedByteArray:
	var out := PackedByteArray()
	out.append_array(arrow)
	out.append_array(conveyor)
	out.append_array(warp)
	out.append_array(tramp)
	out.append(regen_interval)
	out.append(clampi(ice_delay_ms / 10, 0, 255))
	return out


func _blank(x: int, y: int) -> bool:
	if not in_bounds(x, y):
		return false
	brick[idx(x, y)] = Types_.Brick.BLANK
	return true


## Clear a cell for a special: no brick and no powerup.
##
## load_extras() runs AFTER place_powerups(), so a cell that gets an arrow or a
## conveyor may already have a powerup hidden under the brick that is about to
## be removed — which would leave it lying in the open on the belt from tick
## zero. Visible immediately in a screenshot of level 10, which is how it was
## found.
func _clear_for_special(x: int, y: int) -> bool:
	if not _blank(x, y):
		return false
	powerup[idx(x, y)] = NO_POWERUP
	return true


func brick_at(x: int, y: int) -> int:
	return brick[idx(x, y)]


## Whether a cell can be walked into or a flame can pass through it.
## Off-field counts as blocked: the border is not a special case anywhere else.
func is_open(x: int, y: int) -> bool:
	if not in_bounds(x, y):
		return false
	return brick[idx(x, y)] == Types_.Brick.BLANK


func has_powerup(x: int, y: int) -> bool:
	return in_bounds(x, y) and powerup[idx(x, y)] != NO_POWERUP


func flame_at(x: int, y: int) -> int:
	if not in_bounds(x, y):
		return 0
	return flame[idx(x, y)]


func has_flame(x: int, y: int) -> bool:
	return flame_at(x, y) != 0


func flame_owner_at(x: int, y: int) -> int:
	if not in_bounds(x, y):
		return NO_OWNER
	return flame_owner[idx(x, y)]


## Put one arm of a flame cross on a cell.
##
## When two flames reach the same cell in the same tick the later one wins the
## ownership, which is AtomBomberman's "there is only one flame per tile (the
## last one)". The arm bits accumulate, because a cell can be the crossing
## point of two different bombs' flames.
func add_flame(x: int, y: int, arm: int, owner: int, ticks: int) -> void:
	if not in_bounds(x, y):
		return
	var i := idx(x, y)
	flame[i] = flame[i] | arm
	flame_owner[i] = owner
	flame_timer[i] = ticks


## Destroy a brick. The cell becomes walkable at once and the timer is only the
## disintegration animation — resource 20, 10 frames. Returns the powerup that
## was hidden under it, or NO_POWERUP.
func destroy_brick(x: int, y: int, anim_ticks: int) -> int:
	if not in_bounds(x, y):
		return NO_POWERUP
	var i := idx(x, y)
	if brick[i] != Types_.Brick.BRICK:
		return NO_POWERUP
	brick[i] = Types_.Brick.BLANK
	brick_timer[i] = anim_ticks
	return powerup[i]


## Age the flame and animation timers by one tick.
## Take the powerup on a cell, if any. Returns what was there, or NO_POWERUP.
func take_powerup(x: int, y: int) -> int:
	if not in_bounds(x, y):
		return NO_POWERUP
	var i := idx(x, y)
	var what := powerup[i]
	powerup[i] = NO_POWERUP
	return what


## Put a powerup back on the field, on a blank cell chosen at random.
##
## Used when a player dies: VALUELST 122 says diseases do NOT recycle, but the
## ordinary powerups a player was carrying return to the field. Returns false
## when there is nowhere to put it.
func scatter_powerup(which: int, rng: RandomNumberGenerator) -> bool:
	var free: Array[int] = []
	for i in CELLS:
		if brick[i] == Types_.Brick.BLANK and powerup[i] == NO_POWERUP \
				and flame[i] == 0:
			free.append(i)
	if free.is_empty():
		return false
	powerup[free[rng.randi_range(0, free.size() - 1)]] = which
	return true


func count_powerups() -> int:
	var n := 0
	for i in CELLS:
		if powerup[i] != NO_POWERUP:
			n += 1
	return n


func count_powerups_of(which: int) -> int:
	var n := 0
	for i in CELLS:
		if powerup[i] == which:
			n += 1
	return n


func tick_timers() -> void:
	for i in CELLS:
		if flame_timer[i] > 0:
			flame_timer[i] -= 1
			if flame_timer[i] == 0:
				flame[i] = 0
				flame_owner[i] = NO_OWNER
		if brick_timer[i] > 0:
			brick_timer[i] -= 1


func count_of(kind: int) -> int:
	var n := 0
	for i in CELLS:
		if brick[i] == kind:
			n += 1
	return n


func flaming_cells() -> int:
	var n := 0
	for i in CELLS:
		if flame[i] != 0:
			n += 1
	return n


## Every byte plane, in a fixed order, for hashing and for the wire format.
func to_bytes() -> PackedByteArray:
	var out := PackedByteArray()
	out.append_array(brick)
	out.append_array(powerup)
	out.append_array(flame)
	out.append_array(flame_owner)
	out.append_array(flame_timer)
	out.append_array(brick_timer)
	return out


## The grid as the original's own scheme comments draw it, for test output.
func to_ascii() -> String:
	var chars := {Types_.Brick.SOLID: "#", Types_.Brick.BRICK: ":",
		Types_.Brick.BLANK: "."}
	var out := PackedStringArray()
	for y in Const_.FIELD_H:
		var row := ""
		for x in Const_.FIELD_W:
			row += "*" if has_flame(x, y) else chars[brick_at(x, y)]
		out.append(row)
	return "\n".join(out)
