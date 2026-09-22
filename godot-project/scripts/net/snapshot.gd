# Packs a whole simulation state into bytes and back.
#
# This is the load-bearing piece of the netcode. The client never simulates —
# it applies snapshots — so anything this fails to carry is a field the client
# renders wrongly, and anything it packs in a different order on the two sides
# is a desynchronised game.
#
# THE GUARANTEE IT MUST PROVIDE: apply(write(sim)) leaves a sim whose
# state_hash() equals the original's. That is one assertion, it covers every
# field at once, and tests/test_net.gd makes it on real rounds rather than on
# hand-built states. A field added to player.gd and forgotten here fails it
# immediately.
#
# The layout deliberately reuses the simulation's own to_bytes() records rather
# than defining a second format. One format cannot drift from itself.
class_name Snapshot

const Const_ := preload("res://scripts/core/const.gd")
const Types_ := preload("res://scripts/core/types.gd")
const Field_ := preload("res://scripts/sim/field.gd")
const Player_ := preload("res://scripts/sim/player.gd")
const Bomb_ := preload("res://scripts/sim/bomb.gd")

## Bumped when the layout changes, alongside Protocol.VERSION.
const LAYOUT := 3


static func write(sim: RefCounted) -> PackedByteArray:
	var b := PackedByteArray()
	b.append(LAYOUT)

	# Round state first: small, and a client that only wants the clock can
	# stop reading here.
	_put_i32(b, sim.tick_count)
	_put_i32(b, sim.time_left)
	_put_i32(b, sim.hurry_index)
	b.append(sim.outcome)
	b.append(clampi(sim.winner_slot + 1, 0, 255))
	b.append(clampi(sim.winner_team + 1, 0, 255))
	b.append(int(sim.team_play))

	# The field, as its six byte planes.
	b.append_array(sim.field.to_bytes())

	# Players, ordered by slot so the two sides cannot disagree about order.
	var slots: Array = sim.players.duplicate()
	slots.sort_custom(func(x, y): return x.slot < y.slot)
	b.append(slots.size())
	for p in slots:
		b.append_array(p.to_bytes())

	# Bombs, ordered by cell for the same reason.
	var ordered: Array = sim.bombs.duplicate()
	ordered.sort_custom(func(x, y):
		return (y_key(x)) < (y_key(y)))
	b.append(mini(ordered.size(), 255))
	for i in mini(ordered.size(), 255):
		b.append_array(ordered[i].to_bytes())

	return b


static func y_key(b: RefCounted) -> int:
	return b.y * Const_.FIELD_W * Bomb_.TILE_W_CP + b.x


## Apply a snapshot to a sim, replacing its state entirely.
##
## Returns false when the bytes do not describe a state this build understands,
## which is safer than applying half of one.
static func apply(sim: RefCounted, data: PackedByteArray) -> bool:
	if data.size() < 20 or data[0] != LAYOUT:
		return false
	var pos := 1

	sim.tick_count = _get_i32(data, pos); pos += 4
	sim.time_left = _get_i32(data, pos); pos += 4
	sim.hurry_index = _get_i32(data, pos); pos += 4
	sim.outcome = data[pos]; pos += 1
	sim.winner_slot = int(data[pos]) - 1; pos += 1
	sim.winner_team = int(data[pos]) - 1; pos += 1
	sim.team_play = data[pos] != 0; pos += 1

	var planes := Field_.CELLS * 6
	if pos + planes > data.size():
		return false
	if sim.field == null:
		sim.field = Field_.new()
	_read_planes(sim.field, data, pos)
	pos += planes

	if pos >= data.size():
		return false
	var n_players := data[pos]; pos += 1
	var player_len := _player_record_len()
	if pos + n_players * player_len > data.size():
		return false
	# Reuse the existing player objects where the slots match, so a renderer
	# holding a reference to one keeps working across a snapshot.
	var by_slot := {}
	for p in sim.players:
		by_slot[p.slot] = p
	var rebuilt: Array = []
	for i in n_players:
		var slot := data[pos]
		var p = by_slot.get(slot, null)
		if p == null:
			p = Player_.new()
		_read_player(p, data, pos)
		rebuilt.append(p)
		pos += player_len
	sim.players = rebuilt

	if pos >= data.size():
		return false
	var n_bombs := data[pos]; pos += 1
	var bomb_len := _bomb_record_len()
	if pos + n_bombs * bomb_len > data.size():
		return false
	var bombs: Array = []
	for i in n_bombs:
		var b: Bomb_ = Bomb_.new()
		_read_bomb(b, data, pos)
		bombs.append(b)
		pos += bomb_len
	sim.bombs = bombs
	return true


static func _read_planes(field: Field_, data: PackedByteArray, pos: int) -> void:
	var n := Field_.CELLS
	field.brick = data.slice(pos, pos + n); pos += n
	field.powerup = data.slice(pos, pos + n); pos += n
	field.flame = data.slice(pos, pos + n); pos += n
	field.flame_owner = data.slice(pos, pos + n); pos += n
	field.flame_timer = data.slice(pos, pos + n); pos += n
	field.brick_timer = data.slice(pos, pos + n)


# The record lengths are derived from the records themselves rather than
# written down, so adding a field to player.gd cannot leave a stale constant
# here — it changes both sides at once.
static func _player_record_len() -> int:
	return Player_.new().to_bytes().size()


static func _bomb_record_len() -> int:
	return Bomb_.new().to_bytes().size()


static func _read_player(p: Player_, d: PackedByteArray, at: int) -> void:
	var pos := at
	p.slot = d[pos]; pos += 1
	p.in_play = d[pos] != 0; pos += 1
	p.alive = d[pos] != 0; pos += 1
	p.dying = d[pos] != 0; pos += 1
	p.team = int(d[pos]) - 1; pos += 1
	p.facing = d[pos]; pos += 1
	p.move = d[pos]; pos += 1
	p.action = d[pos]; pos += 1
	p.action_first_held = d[pos] != 0; pos += 1
	p.killed_by = int(d[pos]) - 1; pos += 1
	p.x = _get_i32(d, pos); pos += 4
	p.y = _get_i32(d, pos); pos += 4
	p.speed = _get_i32(d, pos); pos += 4
	p.flame_len = _get_i32(d, pos); pos += 4
	p.bombs_available = _get_i32(d, pos); pos += 4
	p.bombs_total = _get_i32(d, pos); pos += 4
	p.can_kick = d[pos] != 0; pos += 1
	p.can_punch = d[pos] != 0; pos += 1
	p.can_grab = d[pos] != 0; pos += 1
	p.can_spooge = d[pos] != 0; pos += 1
	p.jelly_bombs = d[pos] != 0; pos += 1
	p.trigger_bombs = _get_i32(d, pos); pos += 4
	p.disease_freshness = _get_i32(d, pos); pos += 4
	p.speed_before_slow = _get_i32(d, pos); pos += 4
	p.pickup_pause = _get_i32(d, pos); pos += 4
	p.fly_ticks = _get_i32(d, pos); pos += 4
	p.fly_to_x = d[pos]; pos += 1
	p.fly_to_y = d[pos]; pos += 1
	p.warp_cooldown = _get_i32(d, pos); pos += 4
	# Read in the same order player.gd's to_bytes() writes them — see the
	# comment there for why the animation timers have to cross the wire.
	p.death_anim = _get_i32(d, pos); pos += 4
	p.kick_ticks = _get_i32(d, pos); pos += 4
	p.punch_ticks = _get_i32(d, pos); pos += 4
	p.cornerhead = _get_i32(d, pos); pos += 4
	p.cornerhead_ticks = _get_i32(d, pos); pos += 4
	p.invulnerable = _get_i32(d, pos); pos += 4
	p.pickups = _get_i32(d, pos); pos += 4
	for i in Const_.POWERUP_COUNT:
		p.collected[i] = _get_i32(d, pos); pos += 4
	for i in Types_.DISEASE_COUNT:
		p.disease_ticks[i] = _get_i32(d, pos); pos += 4


static func _read_bomb(b: Bomb_, d: PackedByteArray, at: int) -> void:
	var pos := at
	b.x = _get_i32(d, pos); pos += 4
	b.y = _get_i32(d, pos); pos += 4
	b.move_dir = d[pos]; pos += 1
	b.speed = _get_i32(d, pos); pos += 4
	b.flying = d[pos] != 0; pos += 1
	b.fly_tick = _get_i32(d, pos); pos += 4
	b.fly_ticks = _get_i32(d, pos); pos += 4
	b.fly_to_x = _get_i32(d, pos); pos += 4
	b.fly_to_y = _get_i32(d, pos); pos += 4
	b.triggered = d[pos] != 0; pos += 1
	b.jelly_bounce = d[pos] != 0; pos += 1
	b.carried_by = int(d[pos]) - 1; pos += 1
	b.hold_required_to_carry = d[pos] != 0; pos += 1
	b.cells_travelled = d[pos]; pos += 1
	b.owner = d[pos]; pos += 1
	b.chain_owner = d[pos]; pos += 1
	b.state = d[pos]; pos += 1
	b.detonated = d[pos] != 0; pos += 1
	b.fuze = d[pos] | (d[pos + 1] << 8); pos += 2
	b.flame_len = d[pos]; pos += 1
	b.placed_tick = _get_i32(d, pos)


static func _put_i32(b: PackedByteArray, v: int) -> void:
	b.append(v & 0xFF)
	b.append((v >> 8) & 0xFF)
	b.append((v >> 16) & 0xFF)
	b.append((v >> 24) & 0xFF)


static func _get_i32(b: PackedByteArray, pos: int) -> int:
	if pos + 4 > b.size():
		return 0
	var v: int = b[pos] | (b[pos + 1] << 8) | (b[pos + 2] << 16) \
		| (b[pos + 3] << 24)
	# Sign-extend: these are i32 on the wire and GDScript ints are 64-bit, so a
	# negative would otherwise read as a large positive. hurry_index is -1 when
	# Hurry is not running, which is exactly this case.
	if v & 0x80000000:
		v -= 0x100000000
	return v
