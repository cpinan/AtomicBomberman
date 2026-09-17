# A bot. Decides one player's input for one tick.
#
# ---------------------------------------------------------------------------
# WHAT IS THE ORIGINAL'S AND WHAT IS NOT
# ---------------------------------------------------------------------------
# VALUELST holds exactly four knobs for the AI and they are used here:
#
#   900  how many personalities are defined              1
#   910  how far ahead the fire-god (the closing wall) is treated as a threat  15
#   915  the chance of running the "blast bricks" routine, 1-in-N              5
#   920  how close a powerup must be to be worth going for                     4
#
# The LOGIC behind them is in BM.EXE and nowhere else — docs/BUGS.md Q5.4. What
# is implemented is a breadth-first search over the field with a priority
# order, which is the same shape fpc_atomic's agent takes. It was written as a
# disclaimed invention, and reading BM95.EXE has since found the original doing
# something closer than that disclaimer allowed: its priority table's routing
# entry (0x40B20F) runs a real breadth-first search — up to 100 cloning
# walkers, depth 20 — but over an INFLUENCE MAP (a danger number per cell,
# 0x424D37) rather than over walkability, and only when the bot is standing in
# danger or already holds a destination. Its other seven entries look no
# further than their own tile, the 4 adjacent cells, or a radius-9 ray. So the
# mechanism here is the original's; the scope and the field it searches are
# not. Still not claimed to be the original's behaviour — docs/BUGS.md Q5.
#
# ---------------------------------------------------------------------------
# THE PRIORITY ORDER
# ---------------------------------------------------------------------------
#   0  Standing on your own live trigger bomb: 1-in-2 to set it off.
#      0x40BD44, the original's own highest-priority entry.
#   1  A kickable bomb next to you: 1-in-4 to walk into it. 0x40BE02.
#   2  If standing somewhere that is about to burn, run to the nearest safe
#      cell. Nothing else matters while a bomb is ticking under you.
#   3  If a powerup is within resource 920's radius and reachable safely, take
#      it.
#   4  If an enemy is reachable and bombing here leaves an escape, bomb —
#      1-in-5, and only if no live bomb of your own already covers the spot.
#   5  If a destructible brick is adjacent and there is an escape, bomb it —
#      1-in-resource-915 of the time, so bots do not all dig identically.
#   6  Otherwise walk toward the nearest thing worth reaching.
#
# Steps 0, 1 and 4 were added later than the rest, once BM95.EXE's own
# priority table (0x45BA78) had been read in full — docs/BUGS.md Q5.4. Two of
# its eight entries are still not attempted at all: entry 2's cloning-walker
# BFS over a 100-node pool (step 2 here is a plain breadth-first search
# instead, disclaimed above) and entry 6's four-ray corridor scorer (folded
# into the same search). Every other entry now has a step here, though not
# always the original's exact shape — see each step's own comment for what
# was read and what was chosen where the disassembly left a gap.
#
# Every decision is made from the simulation's own state and the seeded RNG, so
# a bot game replays exactly like any other.
extends RefCounted

const Const_ := preload("res://scripts/core/const.gd")
const Types_ := preload("res://scripts/core/types.gd")
const Values_ := preload("res://scripts/core/values.gd")
const Field_ := preload("res://scripts/sim/field.gd")
const Player_ := preload("res://scripts/sim/player.gd")
const Bomb_ := preload("res://scripts/sim/bomb.gd")

## Powerups worth collecting, and the ones to avoid. The two disease powerups
## and the slow-down are traps; everything else helps.
const GOOD := [Types_.PowerUp.BOMB, Types_.PowerUp.FLAME,
	Types_.PowerUp.GOLDFLAME, Types_.PowerUp.SKATE, Types_.PowerUp.KICK,
	Types_.PowerUp.SPOOGE, Types_.PowerUp.PUNCH, Types_.PowerUp.GRAB,
	Types_.PowerUp.TRIGGER, Types_.PowerUp.JELLY]
const BAD := [Types_.PowerUp.DISEASE, Types_.PowerUp.SUPER_BAD_DISEASE,
	Types_.PowerUp.RANDOM]

const UNREACHABLE := 9999

## The four directions, typed. Declared once because an inline array literal
## yields Variant elements and every `step.x` off one is untyped.
const STEPS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0),
	Vector2i(0, 1), Vector2i(0, -1)]

## A cell already on fire: nothing is sooner than now.
const BURNING_NOW := 1


## Decide this tick's input for one player. Returns
## {"move": Types.MoveState, "action": Types.Action}.
func think(sim: RefCounted, p: Player_) -> Dictionary:
	if not p.alive or p.dying or p.fly_ticks > 0:
		return {"move": Types_.MoveState.STILL, "action": Types_.Action.NONE}

	var here := Vector2i(p.tile_x(), p.tile_y())

	# 0. Remote trigger — 0x40BD44, entry 0, the original's highest priority.
	# Gate: a live triggered bomb of this player's own is underfoot. The
	# original's own gate is a stock byte (+0x5c); the port already keeps
	# that as `trigger_bombs`, a spend-on-placement counter rather than a
	# flag (docs/BUGS.md D8), so the live-bomb check below is the equivalent
	# ask — "is there one to press right now" — for a stock that may already
	# be zero by the time the bomb is sitting there.
	#
	# The original's own press IS the bomb-drop byte (+0x38) — "reads as
	# pressing the bomb key while standing on one: the remote trigger" — but
	# the port's SECOND action is what detonates a trigger bomb for a human
	# (MANUAL.BM; `sim.gd` `_player_action`), and pressing it fires every
	# triggered bomb this player owns, not only the one underfoot. Broader
	# than the original's single-bomb read; the closest the port's own
	# mechanic allows, recorded here rather than invented silently.
	var own_bomb: Bomb_ = sim.bomb_at(here.x, here.y)
	if own_bomb != null and own_bomb.owner == p.slot and own_bomb.triggered \
			and not own_bomb.detonated and not own_bomb.flying \
			and sim.rng.randi_range(1, 2) == 1:
		return {"move": Types_.MoveState.STILL, "action": Types_.Action.SECOND}

	# 1. Kick an adjacent bomb — 0x40BE02, entry 1. Gate: can_kick. 1-in-4
	# chance; scans the four adjacent cells in the original's own order — up,
	# right, down, left, 0x45BECC/0x45BEDC — for a bomb, and on a hit faces
	# that direction. The port has no separate kick BUTTON: kicking is
	# automatic on WALKING into a bomb at rest (`sim.gd` `_move_player`), so
	# "face that direction" is done here by moving that way.
	if p.can_kick and sim.rng.randi_range(1, 4) == 1:
		var kick_move := _kick_direction(sim, here)
		if kick_move != Types_.MoveState.STILL:
			return {"move": kick_move, "action": Types_.Action.NONE}

	var danger := _danger_map(sim)

	# Two distance fields, and the difference matters.
	#
	#   flee_dist  ignores danger, because escaping a corridor may mean running
	#              ALONG the blast to get out of it
	#   safe_dist  treats danger as wall, for every goal worth walking to —
	#              a bot must not cross fire to reach a powerup or a brick
	var flee_dist := _walk_distances(sim, here)
	var safe_dist := _walk_distances(sim, here, danger)

	# 2. Standing in danger: get out, and do nothing else.
	if danger[Field_.idx(here.x, here.y)] > 0:
		var escape := _nearest(flee_dist, danger, func(_c): return true)
		if escape.x >= 0:
			return {"move": _step_toward(flee_dist, here, escape),
				"action": Types_.Action.NONE}
		# Nowhere safe at all. Take the cell that burns LATEST of the ones it
		# can reach — the graded danger map is what makes that a question the
		# bot can answer, and buying eight ticks is sometimes buying the round.
		#
		# The original's own search would go the other way: its influence map
		# carries fuze + 100 and it takes the MINIMUM, which walks toward the
		# blast that arrives soonest and stands where the fire has passed.
		# That works because its bots wait; these do not, so this port takes
		# the time instead and says so. docs/AUDIT.md §3.
		var latest := _latest_burning(flee_dist, danger, here)
		if latest.x >= 0 and latest != here:
			return {"move": _step_toward(flee_dist, here, latest),
				"action": Types_.Action.NONE}
		# Keep moving rather than standing still to die.
		return {"move": _any_open_move(sim, p, here),
			"action": Types_.Action.NONE}

	# 3. A powerup within resource 920's radius.
	var radius: int = Values_.V[Const_.Res.AI_POWERUP_RADIUS]
	var want := _nearest(safe_dist, danger, func(c: Vector2i) -> bool:
		var which: int = sim.field.powerup[Field_.idx(c.x, c.y)]
		if which == Field_.NO_POWERUP:
			return false
		if sim.field.brick_at(c.x, c.y) != Types_.Brick.BLANK:
			return false
		return GOOD.has(int(which)))
	if want.x >= 0 and safe_dist[Field_.idx(want.x, want.y)] <= radius:
		if want == here:
			return {"move": Types_.MoveState.STILL, "action": Types_.Action.NONE}
		return {"move": _step_toward(safe_dist, here, want),
			"action": Types_.Action.NONE}

	# 4. An enemy in reach: bomb, if there is somewhere to run afterwards.
	# 0x40ABED, entry 4. Three gates then a throttle, in the original's order:
	#
	#   allowance   live-bomb count under the player's own cap — bombs_available
	#   distance    "the Manhattan distance between the actor and the pixel
	#               pair at +0x14/+0x18 must be at least 3" — whose pair the
	#               disassembly could not identify ("which entity that pair
	#               belongs to is not pinned down"). It cannot be the enemy
	#               the next gate finds: that scan is a fixed 5-cell plus
	#               CENTRED ON THE ACTOR (see _enemy_near), so anything it
	#               finds is at Manhattan distance <= 1, and >= 3 can never
	#               hold for the same target. The one candidate that both
	#               fits the block's own order (this gate runs BEFORE the
	#               enemy scan) and needs no new state is the actor's own
	#               most recent bomb — sim.bombs already knows where every
	#               live bomb this player owns is, with no new persisted
	#               field and no netcode-sync consequence. Read as "don't
	#               queue another attack while one you already dropped is
	#               still within three tiles" — bombs land spread out rather
	#               than stacked on one spot. A judgement call, not a read;
	#               recorded as one.
	#   plus-shape  the fixed 5-cell cross at Manhattan distance <= 1 —
	#               _enemy_near, not the flame_len-scaled reach this used to
	#               be. The original does not scale it by blast power.
	#   escape      0x423188 "permits a bomb here" — the port's own
	#               `_escape_exists`, an invented reachability test rather
	#               than a read of that function (docs/BUGS.md Q5.4's own
	#               note on why: it prevents a bot bombing itself into a
	#               corner, D-class behaviour no oracle constant covers).
	#   throttle    1-in-5, last, exactly as read.
	if p.bombs_available > 0 and not _own_bomb_too_close(sim, p, here) \
			and _enemy_near(sim, p, here) \
			and _escape_exists(sim, p, here, danger) \
			and sim.rng.randi_range(1, 5) == 1:
		return {"move": Types_.MoveState.STILL, "action": Types_.Action.FIRST}

	# 5. A brick to blast. Resource 915 makes it 1-in-5, so a field of bots
	# does not dig in lockstep.
	if p.bombs_available > 0 and _brick_adjacent(sim, here) \
			and _escape_exists(sim, p, here, danger) \
			and sim.rng.randi_range(1, Values_.V[Const_.Res.AI_BLAST_BRICKS_CHANCE]) == 1:
		return {"move": Types_.MoveState.STILL, "action": Types_.Action.FIRST}

	# 6. Head for the nearest brick worth blasting, or an enemy.
	var goal := _nearest(safe_dist, danger, func(c: Vector2i) -> bool:
		return _brick_adjacent(sim, c))
	if goal.x >= 0 and goal != here:
		return {"move": _step_toward(safe_dist, here, goal),
			"action": Types_.Action.NONE}

	return {"move": _any_open_move(sim, p, here, danger),
		"action": Types_.Action.NONE}


## Cells that are burning or about to, GRADED by how soon.
##
## 0 means safe. Any other value is "this will burn", and the number is when:
## SOONEST is 1 and later is larger, clamped at 255. The original keeps the
## same idea in its influence map (`0x424D37`, a bomb's cells carry its fuze
## plus 100 and a burning cell 1000) — docs/BUGS.md Q5.4 — and this is the
## port's own units rather than a copy of those, because the port's callers
## want "how many ticks have I got", not "which number is smaller".
##
## Everything that only asks "is this dangerous at all" keeps working
## unchanged: a byte that is non-zero is dangerous, which is what it was when
## the map was a flag.
##
## The closing wall counts too: resource 910 says the fire-god should be
## treated as a threat 15 cells ahead of where it has reached.
func _danger_map(sim: RefCounted) -> PackedByteArray:
	var danger := PackedByteArray()
	danger.resize(Field_.CELLS)
	danger.fill(0)

	for i in Field_.CELLS:
		if sim.field.flame[i] != 0:
			danger[i] = BURNING_NOW

	for b in sim.bombs:
		if b.detonated or b.carried_by >= 0:
			continue
		# A trigger bomb has no countdown to read: it waits for its owner. It
		# is treated as if it were about to go off, which is the assumption
		# that keeps a bot alive.
		var when: int = 1 if b.triggered else clampi(b.fuze + 1, 1, 255)
		var bx: int = b.tile_x()
		var by: int = b.tile_y()
		if Field_.in_bounds(bx, by):
			_mark(danger, Field_.idx(bx, by), when)
		for step in STEPS:
			for n in range(1, b.flame_len + 1):
				var x := bx + step.x * n
				var y := by + step.y * n
				if not Field_.in_bounds(x, y):
					break
				if sim.field.brick_at(x, y) == Types_.Brick.SOLID:
					break
				_mark(danger, Field_.idx(x, y), when)
				if sim.field.brick_at(x, y) == Types_.Brick.BRICK:
					break

	# The closing wall, 15 cells of it.
	if sim.hurry_index >= 0:
		var path: Array = sim.hurry_path()
		var lookahead: int = Values_.V[Const_.Res.AI_FIREGOD_LOOKAHEAD]
		for k in range(sim.hurry_index, mini(sim.hurry_index + lookahead,
				path.size())):
			var cell: Vector2i = path[k]
			# The nearer the wall is to a cell, the sooner it arrives there.
			_mark(danger, Field_.idx(cell.x, cell.y),
				clampi(k - sim.hurry_index + 1, 1, 255))
	return danger


## Two dangers on one cell: the sooner one is the one that matters.
static func _mark(danger: PackedByteArray, i: int, when: int) -> void:
	var current: int = danger[i]
	if current == 0 or when < current:
		danger[i] = when


## Walking distance from a cell to every other. Breadth-first, so the first
## time a cell is reached is by a shortest path.
##
## `avoid`, when given, makes those cells impassable — used for every goal the
## bot walks TO, so it does not route through fire to reach somewhere safe. The
## start cell is always passable, or a bot standing in danger could never
## leave.
##
## Worth being accurate about: this is defensible on its own terms, but it is
## NOT what fixed the bots dying. Measured by reverting each half separately,
## the three-deaths-in-eight came entirely from _any_open_move() — a bot that
## escaped, had no goal left, fell through to the random wander and strolled
## back into the blast. This avoidance has no independent test covering it;
## docs/BUGS.md records that.
func _walk_distances(sim: RefCounted, from: Vector2i,
		avoid: PackedByteArray = PackedByteArray()) -> PackedInt32Array:
	var dist := PackedInt32Array()
	dist.resize(Field_.CELLS)
	dist.fill(UNREACHABLE)
	if not Field_.in_bounds(from.x, from.y):
		return dist
	dist[Field_.idx(from.x, from.y)] = 0
	var queue: Array[Vector2i] = [from]
	var head := 0
	while head < queue.size():
		var cell: Vector2i = queue[head]
		head += 1
		var d: int = dist[Field_.idx(cell.x, cell.y)]
		for step in STEPS:
			var nx := cell.x + step.x
			var ny := cell.y + step.y
			if not Field_.in_bounds(nx, ny):
				continue
			if not sim.field.is_open(nx, ny):
				continue
			# A bomb blocks, unless it is the one under our feet.
			if sim.bomb_at(nx, ny) != null:
				continue
			var i: int = Field_.idx(nx, ny)
			if not avoid.is_empty() and avoid[i] != 0:
				continue
			if dist[i] <= d + 1:
				continue
			dist[i] = d + 1
			queue.append(Vector2i(nx, ny))
	return dist


## The nearest SAFE cell matching a test, or (-1,-1).
## The reachable cell whose fire arrives latest. Only consulted when nothing
## safe is in reach at all, so every candidate is dangerous by definition.
func _latest_burning(dist: PackedInt32Array, danger: PackedByteArray,
		here: Vector2i) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_when := int(danger[Field_.idx(here.x, here.y)])
	var best_d := UNREACHABLE
	for y in Const_.FIELD_H:
		for x in Const_.FIELD_W:
			var i: int = Field_.idx(x, y)
			if dist[i] >= UNREACHABLE:
				continue
			var when: int = danger[i]
			if when == 0:
				continue     # a safe cell would have been taken already
			# Later is better, and among equals the nearer one — every tick
			# spent walking is a tick of the time just bought.
			if when > best_when or (when == best_when and dist[i] < best_d):
				best_when = when
				best_d = dist[i]
				best = Vector2i(x, y)
	return best


func _nearest(dist: PackedInt32Array, danger: PackedByteArray,
		test: Callable) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_d := UNREACHABLE
	for y in Const_.FIELD_H:
		for x in Const_.FIELD_W:
			var i: int = Field_.idx(x, y)
			if dist[i] >= best_d or danger[i] != 0:
				continue
			if not test.call(Vector2i(x, y)):
				continue
			best_d = dist[i]
			best = Vector2i(x, y)
	return best


## The first step of a shortest path from `here` to `goal`: walk the distance
## field back down from the goal.
func _step_toward(dist: PackedInt32Array, here: Vector2i,
		goal: Vector2i) -> int:
	var cell := goal
	var guard := 0
	while guard < Field_.CELLS:
		guard += 1
		var d: int = dist[Field_.idx(cell.x, cell.y)]
		if d <= 1:
			break
		var moved := false
		for step in STEPS:
			var nx := cell.x + step.x
			var ny := cell.y + step.y
			if not Field_.in_bounds(nx, ny):
				continue
			if dist[Field_.idx(nx, ny)] == d - 1:
				cell = Vector2i(nx, ny)
				moved = true
				break
		if not moved:
			break
	var delta := cell - here
	if delta.x > 0:
		return Types_.MoveState.RIGHT
	if delta.x < 0:
		return Types_.MoveState.LEFT
	if delta.y > 0:
		return Types_.MoveState.DOWN
	if delta.y < 0:
		return Types_.MoveState.UP
	return Types_.MoveState.STILL


func _brick_adjacent(sim: RefCounted, cell: Vector2i) -> bool:
	for step in STEPS:
		var x := cell.x + step.x
		var y := cell.y + step.y
		if Field_.in_bounds(x, y) \
				and sim.field.brick_at(x, y) == Types_.Brick.BRICK:
			return true
	return false


## The original's own shape for handler 4 — 0x45BAB0/0x45BA9C, literally
## (-1,0) (0,-1) (0,0) (0,1) (1,0), five named cells and not a ray. Fixed at
## Manhattan distance <= 1 from the actor's own tile; NOT scaled by
## `flame_len`. That the original nulls the actor's own list-link before the
## scan ("so it cannot find itself") only makes sense if the scan is centred
## on the actor — otherwise there would be nothing of the actor's own to
## exclude.
func _enemy_near(sim: RefCounted, me: Player_, cell: Vector2i) -> bool:
	for other in sim.players:
		if other.slot == me.slot or not other.alive or other.dying:
			continue
		if not other.in_play:
			continue
		# Same team is not a target.
		if sim.team_play and other.team == me.team \
				and me.team != Types_.TEAM_UNSET:
			continue
		var dx: int = absi(other.tile_x() - cell.x)
		var dy: int = absi(other.tile_y() - cell.y)
		if dx + dy <= 1:
			return true
	return false


## Gate 2 of handler 4 — see the long comment at its call site in think() for
## why this, rather than distance-to-the-enemy, is the reading used here.
func _own_bomb_too_close(sim: RefCounted, me: Player_, cell: Vector2i) -> bool:
	for b in sim.bombs:
		if b.detonated or b.owner != me.slot:
			continue
		var dx: int = absi(b.tile_x() - cell.x)
		var dy: int = absi(b.tile_y() - cell.y)
		if dx + dy < 3:
			return true
	return false


## Handler 1's own scan order — 0x45BECC/0x45BEDC: up, right, down, left —
## for a bomb at rest on an adjacent cell. Returns the MoveState that walks
## into it, or STILL if none of the four qualifies.
func _kick_direction(sim: RefCounted, here: Vector2i) -> int:
	for pair in [[Vector2i(0, -1), Types_.MoveState.UP],
			[Vector2i(1, 0), Types_.MoveState.RIGHT],
			[Vector2i(0, 1), Types_.MoveState.DOWN],
			[Vector2i(-1, 0), Types_.MoveState.LEFT]]:
		var step: Vector2i = pair[0]
		var b: Bomb_ = sim.bomb_at(here.x + step.x, here.y + step.y)
		if b != null and b.at_rest():
			return int(pair[1])
	return Types_.MoveState.STILL


## Would dropping a bomb here leave anywhere to run to?
##
## Without this a bot bombs itself the moment it is next to a brick, which is
## the single most common way a naive Bomberman agent dies.
func _escape_exists(sim: RefCounted, p: Player_, here: Vector2i,
		danger: PackedByteArray) -> bool:
	var after := danger.duplicate()
	for step in STEPS:
		for n in range(0, p.flame_len + 1):
			var x := here.x + step.x * n
			var y := here.y + step.y * n
			if not Field_.in_bounds(x, y):
				break
			if sim.field.brick_at(x, y) == Types_.Brick.SOLID:
				break
			# The bomb about to be dropped: its whole cross burns when its
			# fuze runs out, which is later than anything already ticking.
			after[Field_.idx(x, y)] = clampi(
				Values_.V[Const_.Res.FUZE_FRAMES] + 1, 1, 255)
			if n > 0 and sim.field.brick_at(x, y) == Types_.Brick.BRICK:
				break

	# Reachable in fewer ticks than the fuze allows, and safe when we get
	# there. A cell is only an escape if the bomb we are about to drop does not
	# also cover it.
	# The escape must avoid what is ALREADY dangerous as well as what the new
	# bomb will make dangerous.
	var dist := _walk_distances(sim, here, danger)
	var reach: int = maxi(1, Values_.V[Const_.Res.FUZE_FRAMES] / 8)
	for y in Const_.FIELD_H:
		for x in Const_.FIELD_W:
			var i: int = Field_.idx(x, y)
			if after[i] == 0 and dist[i] <= reach:
				return true
	return false


## A direction with nothing in the way, preferring a SAFE neighbour when
## `avoid` is given.
##
## THIS is what stopped the bots dying. A bot that had escaped a blast, with no
## powerup in range and no brick worth walking to, fell through to here and
## picked a random open direction — including straight back into the fire it
## had just left. Three bots in eight died that way, and reverting only this
## line brings all three back.
##
## STICKS TO THE CURRENT DIRECTION rather than re-rolling one of up to four
## open options every tick. This function runs from `think()`, which runs
## every simulation tick (20 Hz) — with no persistence, a bot idling with
## nothing to do picked a fresh random direction 20 times a second, visibly
## vibrating rather than walking. The original's own catch-all entry (table
## slot 7, 0x40A81F — the file header's THE PRIORITY ORDER, and docs/BUGS.md
## Q5.4) keeps a persisted facing and only reconsiders it 1-in-25 ticks; that
## is what this now does, using `p.move` itself as the persisted state rather
## than adding a new field — it is already part of Player_.to_bytes(), so this
## needs no change to the wire format or state_hash() to stay network-safe.
func _any_open_move(sim: RefCounted, p: Player_, here: Vector2i,
		avoid: PackedByteArray = PackedByteArray()) -> int:
	var options: Array[int] = []
	for pair in [[Vector2i(1, 0), Types_.MoveState.RIGHT],
			[Vector2i(-1, 0), Types_.MoveState.LEFT],
			[Vector2i(0, 1), Types_.MoveState.DOWN],
			[Vector2i(0, -1), Types_.MoveState.UP]]:
		var step: Vector2i = pair[0]
		var nx: int = here.x + step.x
		var ny: int = here.y + step.y
		if not sim.field.is_open(nx, ny):
			continue
		if not avoid.is_empty() and avoid[Field_.idx(nx, ny)] != 0:
			continue
		options.append(int(pair[1]))
	if options.is_empty():
		return Types_.MoveState.STILL
	if options.has(p.move) and sim.rng.randi_range(1, 25) != 1:
		return p.move
	return options[sim.rng.randi_range(0, options.size() - 1)]
