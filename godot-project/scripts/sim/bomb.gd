# One bomb on the field.
#
# Bomb properties are fixed when it is DROPPED, not when it explodes: picking up
# a flame powerup after placing a bomb does not lengthen that bomb's blast.
# AtomBomberman's notes state this outright, so flame_len is copied in at
# placement rather than read back off the owner at detonation.
extends RefCounted

const Const_ := preload("res://scripts/core/const.gd")
const Types_ := preload("res://scripts/core/types.gd")

## Centre of the bomb in CENTIPIXELS, the same unit as a player's position and
## as every speed in the tuning table. A bomb at rest is cell-aligned; kicked,
## punched and thrown bombs are not, which is why this is not a cell index.
var x: int = 0
var y: int = 0

## Which way it is rolling, and how fast in centipixels per tick. Resource 300
## says a kicked bomb moves at 1000 and resource 301 that a punched one moves
## at 1300.
var move_dir: int = 0      ## Types.Dir
var speed: int = 0

## A punched or thrown bomb leaves the field and flies. While flying it
## collides with nothing and its fuze still burns; it lands on fly_to.
var flying: bool = false
var fly_from_x: int = 0
var fly_from_y: int = 0
var fly_to_x: int = 0
var fly_to_y: int = 0
var fly_tick: int = 0
var fly_ticks: int = 0
## Peak height in pixels, for the renderer only — resource 660 is 65 for the
## initial three-cell punch and 661 is 20 for the one-cell bounces after it.
var fly_height: int = 0
## How many one-cell bounces are still to come after this flight.
var bounces_left: int = 0

## Slot carrying this bomb, or -1. A carried bomb's fuze does NOT burn:
## AtomBomberman's notes say "when its picked up its not even ticking (starts
## ticking when it falls)".
var carried_by: int = -1

## Copied from the owner at the moment the bomb starts moving: a jelly bomb
## bounces off what stops an ordinary one. Read at kick/punch/throw time rather
## than at explode time, for the same reason flame_len is.
var jelly_bounce: bool = false

## Set when the owner has a trigger and chose to place this bomb in trigger
## mode. A triggered bomb waits for the owner's second action instead of
## burning down. Resource 43 selects the starting bomb type.
var triggered: bool = false

## Slot of the player who placed it. Gets the kill even when another player's
## bomb is what set this one off.
var owner: int = 0

## Whose bomb started the chain this bomb belongs to. Equal to `owner` for a
## bomb that burns down its own fuze; set to the igniter's originating owner
## when a flame detonates it early.
var chain_owner: int = 0

## Ticks until it goes off. VALUELST resource 41 = 40 frames = 2.0 s.
var fuze: int = 0

## The tick this bomb was placed on. The fuze does not burn on that tick, so
## that a bomb reaches zero exactly `fuze` ticks after being dropped however it
## was placed — through the input path during a tick, or by a direct call
## between ticks.
var placed_tick: int = -1

## A direction this bomb's blast will NOT take, or Types.Dir.NONE.
##
## The original's own field (+0x38 on the bomb record, tested at 0x423FA4 and
## written at 0x423209): when an arm reaches a bomb and sets it off, that bomb
## is told not to fire back along the arm that lit it. Without it a chain
## re-burns the corridor it came down, once per link.
var blocked_dir: int = 0

## Who kicked this bomb, or -1. MANUAL.BM: the action button stops a bomb you
## kicked, so the bomb has to remember whose kick it was.
var kicked_by: int = -1

## Cells beyond the epicentre, copied from the owner at placement.
var flame_len: int = 1

var state: int = Types_.BombState.NORMAL

## Set once the bomb has been scheduled to explode this tick, so a chain
## reaction cannot detonate the same bomb twice inside one resolution pass.
var detonated: bool = false


const CP := 100
const TILE_W_CP := 40 * CP
const TILE_H_CP := 36 * CP


func tile_x() -> int:
	return x / TILE_W_CP


func tile_y() -> int:
	return y / TILE_H_CP


func at_rest() -> bool:
	return not flying and move_dir == 0 and carried_by < 0


func place_at_tile_centre(tile_x_: int, tile_y_: int) -> void:
	x = tile_x_ * TILE_W_CP + TILE_W_CP / 2
	y = tile_y_ * TILE_H_CP + TILE_H_CP / 2


## Fixed-width record. The order here IS the wire order — scripts/net/snapshot.gd
## reads it back field for field, and tests/test_net.gd asserts a round trip
## reproduces the state hash, so the two cannot drift apart silently.
func to_bytes() -> PackedByteArray:
	var b := PackedByteArray()
	_append_i32(b, x)
	_append_i32(b, y)
	b.append(move_dir)
	_append_i32(b, speed)
	b.append(int(flying))
	_append_i32(b, fly_tick)
	_append_i32(b, fly_ticks)
	_append_i32(b, fly_to_x)
	_append_i32(b, fly_to_y)
	b.append(int(triggered))
	b.append(int(jelly_bounce))
	b.append(clampi(carried_by + 1, 0, 255))
	b.append(bounces_left)
	b.append(owner)
	b.append(chain_owner)
	b.append(state)
	b.append(int(detonated))
	b.append(fuze & 0xFF)
	b.append((fuze >> 8) & 0xFF)
	b.append(flame_len & 0xFF)
	_append_i32(b, placed_tick)
	return b


static func _append_i32(b: PackedByteArray, value: int) -> void:
	b.append(value & 0xFF)
	b.append((value >> 8) & 0xFF)
	b.append((value >> 16) & 0xFF)
	b.append((value >> 24) & 0xFF)
