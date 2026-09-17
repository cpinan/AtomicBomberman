# A rover or a ghost — campaign mode's own monsters.
#
# ---------------------------------------------------------------------------
# WHAT THE DISC SAYS, AND IT IS NOT MUCH
# ---------------------------------------------------------------------------
# The `.CAM` files give a count and a SPEED for each kind, in the same unit
# every other speed on the disc uses ("speeds are in hundredths of a pixel per
# frame" — VALUELST's own header). A rover in CROUTON.CAM moves at 200 to 500,
# a ghost at 150 to 400; a player starts at resource 42's 923, so both are
# slower than a player, and a ghost is usually slower than a rover.
#
# Two VALUELST resources govern the turning and nothing governs anything else:
#
#     1200  chance that a ghost or rover will change directions at an
#           intersection                                              1-in-3
#     1205  chance that the direction change will NOT towards a human 1-in-3
#
# The art is the disc's: ALIENS1.ANI's `rover north/east/south/west` and
# `ghost` the same, which is what `BM95.EXE` builds from "rover %s" / "ghost %s"
# at 0x45807A and 0x458071.
#
# ---------------------------------------------------------------------------
# WHAT THIS PORT DECIDED, BECAUSE THE DISC DOES NOT SAY
# ---------------------------------------------------------------------------
# Every one of these is a disclosed invention, in the same sense as the AI's:
#
#   * A GHOST passes through bricks and walls; a ROVER does not. That is what
#     the words mean, it is why a ghost is given the slower speeds, and it is
#     the only reading under which the two kinds differ at all — the files give
#     them identical fields otherwise.
#   * Both kill a player on contact, cell for cell, the way flame does.
#   * Both die to flame. A rover dies where it stands; a ghost does too, which
#     is arguable — but a monster that cannot be killed turns a stage with 20
#     ghosts into a stage nobody can finish, and GHOSTS.CAM's last stage has
#     exactly that.
#   * A creature turns only when it must (blocked) or when 1200's roll says so
#     at an intersection, which is what 1200 is for.
#   * "Toward a human" in 1205 is read as: of the directions available, the one
#     that reduces the distance to the nearest living player. The 1-in-3 is the
#     chance the choice is made AWAY from that instead.
extends RefCounted

const Const_ := preload("res://scripts/core/const.gd")
const Types_ := preload("res://scripts/core/types.gd")
const Field_ := preload("res://scripts/sim/field.gd")
const Player_ := preload("res://scripts/sim/player.gd")

enum Kind { ROVER, GHOST }

## The four directions, in the original's own table order — up, right, down,
## left (0x45BECC/0x45BEDC). Creatures turn within this list, so the order is
## the order a tie is broken in.
const DIRECTIONS: Array[int] = [Types_.Dir.UP, Types_.Dir.RIGHT,
	Types_.Dir.DOWN, Types_.Dir.LEFT]

var kind: int = Kind.ROVER

## Centre, in centipixels — the same unit and the same origin the players use,
## so "same cell" is the same test for both.
var x: int = 0
var y: int = 0

## Hundredths of a pixel per tick, straight out of the .CAM row.
var speed: int = 200

var facing: int = Types_.Dir.DOWN
var alive: bool = true

## Set on the tick it is killed, so the view can play a death frame and the
## simulation can drop it afterwards.
var dying: bool = false
var death_tick: int = -1

## Who killed it, for the campaign score. -1 when the closing wall or a
## level's own hazard did it.
var killed_by: int = -1


func tile_x() -> int:
	return x / Player_.TILE_W_CP


func tile_y() -> int:
	return y / Player_.TILE_H_CP


func place_at_tile_centre(tx: int, ty: int) -> void:
	x = Player_.tile_centre_x(tx)
	y = Player_.tile_centre_y(ty)


## The sequence this creature is drawn with — the original's own names, built
## the way the binary builds them.
func sequence_name() -> String:
	var word := "rover" if kind == Kind.ROVER else "ghost"
	match facing:
		Types_.Dir.UP: return "%s north" % word
		Types_.Dir.RIGHT: return "%s east" % word
		Types_.Dir.DOWN: return "%s south" % word
		Types_.Dir.LEFT: return "%s west" % word
	return "%s south" % word


## Can this creature stand on that cell? A ghost can stand anywhere inside the
## field; a rover needs it open.
func can_enter(field: RefCounted, tx: int, ty: int) -> bool:
	if not Field_.in_bounds(tx, ty):
		return false
	if kind == Kind.GHOST:
		return true
	return field.brick_at(tx, ty) == Types_.Brick.BLANK


func to_bytes() -> PackedByteArray:
	var b := PackedByteArray()
	b.append(kind)
	b.append(facing)
	b.append(1 if alive else 0)
	_append_i32(b, x)
	_append_i32(b, y)
	return b


static func _append_i32(b: PackedByteArray, value: int) -> void:
	var at := b.size()
	b.resize(at + 4)
	b.encode_s32(at, value)
