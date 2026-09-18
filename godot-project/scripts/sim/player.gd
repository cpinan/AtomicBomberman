# One player's simulation state.
#
# Position is in CENTIPIXELS — hundredths of a pixel — because that is the unit
# the original's own tuning table uses for every speed ("a speed of 100 will
# move 1 pixel per frame cycle", VALUELST's header). Storing position in the
# same unit as velocity means a tick is a single integer add, with no rounding
# and no accumulated error. See sim.gd on why that matters.
extends RefCounted

const Const_ := preload("res://scripts/core/const.gd")
const Types_ := preload("res://scripts/core/types.gd")

## Centipixels per pixel, and the field's dimensions in centipixels.
const CP := 100
const TILE_W_CP := Const_.BLOCK_W * CP   # 4000
const TILE_H_CP := Const_.BLOCK_H * CP   # 3600

## Slot number, 0..9. Also the index into the scheme's start positions and the
## player colour table.
var slot: int = 0

## Team from the scheme, or Types.TEAM_UNSET when the file did not say. 31 of
## the 67 shipped schemes omit it entirely.
var team: int = Types_.TEAM_UNSET

## Is this seat occupied at all? A server holds ten seats from the moment it
## starts listening so the field layout does not shift when somebody joins, and
## an unoccupied seat is NOT a dead player — without the distinction a server
## waiting for its first player declares the round a draw, which is exactly
## what it did.
var in_play: bool = true

var alive: bool = true

## Set on the tick the player is killed. They stop taking input immediately but
## remain in the round while the death animation runs, so the round-end check
## can tell "dying" from "gone".
var dying: bool = false
var death_tick: int = -1

## Who gets credit. The ORIGINATING bomb owner, not the owner of the bomb whose
## flame did it — see field.gd's flame_owner.
var killed_by: int = -1

## Centre of the player, in centipixels from the playfield's top-left corner.
var x: int = 0
var y: int = 0

## Walk speed in centipixels per tick. Which is exactly the tuning table's own
## unit, since one tick is one frame: resource 42 = 923 means 9.23 px/frame.
var speed: int = 0

## How many cells beyond the epicentre this player's bombs reach.
var flame_len: int = 1

## Bombs the player may still place. Decremented on place, restored on
## detonation.
var bombs_available: int = 1
var bombs_total: int = 1

## Abilities, each capped by VALUELST 550..564. Every cap but bombs, flame and
## skates is 1, so these are booleans rather than counts.
var can_kick: bool = false
var can_punch: bool = false
var can_grab: bool = false
var can_spooge: bool = false
var jelly_bombs: bool = false

## How many bombs the player may still place in trigger mode. Not a boolean:
## the trigger powerup grants a limited stock, and picking up another while you
## already have the ability tops it up (VALUELST 0.13003's own changelog).
var trigger_bombs: int = 0

## How many of each powerup this player has collected, indexed by
## Types.PowerUp. Two jobs: enforcing the caps, and knowing what to scatter
## back onto the field when the player dies.
var collected: PackedInt32Array = PackedInt32Array()

## Active diseases, indexed by Types.Disease: 0 for absent, otherwise the ticks
## remaining. VALUELST 121 says diseases are time-limited and 130..138 give the
## durations — all 300, so 15 seconds.
var disease_ticks: PackedInt32Array = PackedInt32Array()

## Ticks since the newest disease was caught. VALUELST 129 requires 10 frames
## before it can be passed on again, which is what stops a single contact
## passing it several times.
var disease_freshness: int = 0

## Speed before MOLASSES or a clog slowed the player, so it can be restored
## rather than recomputed — recomputing would lose any skates collected while
## slowed.
var speed_before_slow: int = 0

## Ticks left of the pause after picking a bomb up — resource 665, 2 frames.
## The player cannot move while it runs.
var pickup_pause: int = 0

## Ticks left in the air off a trampoline, and where the player comes down.
## While flying they are out of play entirely: no cell, no flame, no conveyor.
var fly_ticks: int = 0

## Ticks left of the kicking animation. The disc has a KICK.ANI with four
## directions and nothing drew it: a kick looked like walking into a bomb.
## Not part of state_hash() — it decides a frame, not an outcome.
var kick_ticks: int = 0

## The same, for PUNCH.ANI. MANUAL.BM gives the action button three jobs and
## the disc animates all three; a punch looked like standing still next to a
## bomb that suddenly left.
var punch_ticks: int = 0
var fly_to_x: int = 0
var fly_to_y: int = 0

## Ticks before this player can use a warp gate again. Without it, arriving on
## the destination gate would send them straight back, forever.
var warp_cooldown: int = 0

## Ticks of immunity to flame. A teleporting player is briefly immortal — from
## AtomBomberman's notes.
var invulnerable: int = 0

## How many powerups this player has picked up this round, ever. NOT the sum of
## `collected`: taking trigger zeroes the spooge and punch counts, so that sum
## goes down and this does not. SOUNDLST's "you are now AWESOME (7th powerup
## and 3rd thereafter)" needs a number that only rises.
var pickups: int = 0

## This tick's input.
var move: int = Types_.MoveState.STILL
var action: int = Types_.Action.NONE

## Whether the FIRST action button (Drop Bomb) is physically down THIS tick,
## as opposed to `action`, which is the one-shot edge of it having just been
## pressed. MANUAL.BM: "If you have the Blue Hand powerup, you may carry a
## bomb by grabbing and holding down the Drop Bomb button" — the edge alone
## grabs it (same as any other second-press); this is what lets the sim tell
## a continued hold from a release, so releasing while carrying puts the
## bomb down rather than requiring a third explicit press. docs/BUGS.md.
var action_first_held: bool = false

## Which way the player is facing, kept when they stop so the sprite does not
## snap back to a default.
var facing: int = Types_.Dir.DOWN


## Which of the disc's 24 death animations this player is playing, 1..24, or 0
## before they die. VALUELST 105 says 24 and the seventeen XPLODE files hold
## exactly that many named sequences — "die green 1" to "die green 24".
## Chosen from the simulation's own RNG, so a replay dies the same way.
var death_anim: int = 0

## Which of the 13 `cornerhead N` sequences is playing, 1..13, or 0 when none
## is. Read from `0x41F29B` (`player_update`): every tick it tests all four
## adjacent cells with the same bomb-or-wall test the AI's own
## `ai_cell_is_open` uses (minus the AI's danger term), and when all four are
## blocked AND no special animation is already active, it rolls one of the 13
## sequences at random and plays it for a fixed span before clearing back to
## none — ANIMS.TXT's own words for what this is: "a character getting
## trapped, ready to die." docs/BUGS.md. Chosen from the simulation's own RNG,
## for the same replay-determinism reason as `death_anim` — and, matching
## that field's own existing gap, not yet in `to_bytes()`/`state_hash()`; a
## joining client does not see either one correctly today.
var cornerhead: int = 0
var cornerhead_ticks: int = 0


func _init() -> void:
	collected.resize(Const_.POWERUP_COUNT)
	disease_ticks.resize(Types_.DISEASE_COUNT)


func has_disease(disease: int) -> bool:
	return disease_ticks[disease] > 0


func any_disease() -> bool:
	for t in disease_ticks:
		if t > 0:
			return true
	return false


func active_diseases() -> Array[int]:
	var out: Array[int] = []
	for d in Types_.DISEASE_COUNT:
		if disease_ticks[d] > 0:
			out.append(d)
	return out


func tile_x() -> int:
	return x / TILE_W_CP


func tile_y() -> int:
	return y / TILE_H_CP


## Put the player at the exact centre of a cell. Rounds start here, and a bomb
## is always placed on the centre of the placer's cell.
func place_at_tile_centre(tx: int, ty: int) -> void:
	x = tx * TILE_W_CP + TILE_W_CP / 2
	y = ty * TILE_H_CP + TILE_H_CP / 2


static func tile_centre_x(tx: int) -> int:
	return tx * TILE_W_CP + TILE_W_CP / 2


static func tile_centre_y(ty: int) -> int:
	return ty * TILE_H_CP + TILE_H_CP / 2


## Offset from the centre of the cell the player is standing in. Zero when
## perfectly aligned; the sign says which way they have drifted.
func offset_x() -> int:
	return x - tile_centre_x(tile_x())


func offset_y() -> int:
	return y - tile_centre_y(tile_y())


## Fixed-width record for state_hash() and the wire format. Little-endian
## throughout, and every field that can change must be in here — a field left
## out is a divergence the parity harness cannot see.
func to_bytes() -> PackedByteArray:
	var b := PackedByteArray()
	b.append(slot)
	b.append(int(in_play))
	b.append(int(alive))
	b.append(int(dying))
	b.append(team + 1)              # TEAM_UNSET is -1; shift into a byte
	b.append(facing)
	b.append(move)
	b.append(action)
	b.append(int(action_first_held))
	b.append(clampi(killed_by + 1, 0, 255))
	_append_i32(b, x)
	_append_i32(b, y)
	_append_i32(b, speed)
	_append_i32(b, flame_len)
	_append_i32(b, bombs_available)
	_append_i32(b, bombs_total)
	b.append(int(can_kick))
	b.append(int(can_punch))
	b.append(int(can_grab))
	b.append(int(can_spooge))
	b.append(int(jelly_bombs))
	_append_i32(b, trigger_bombs)
	_append_i32(b, disease_freshness)
	_append_i32(b, speed_before_slow)
	_append_i32(b, pickup_pause)
	_append_i32(b, fly_ticks)
	b.append(clampi(fly_to_x, 0, 255))
	b.append(clampi(fly_to_y, 0, 255))
	_append_i32(b, warp_cooldown)
	_append_i32(b, invulnerable)
	_append_i32(b, pickups)
	for c in collected:
		_append_i32(b, c)
	for d in disease_ticks:
		_append_i32(b, d)
	return b


static func _append_i32(b: PackedByteArray, value: int) -> void:
	b.append(value & 0xFF)
	b.append((value >> 8) & 0xFF)
	b.append((value >> 16) & 0xFF)
	b.append((value >> 24) & 0xFF)
