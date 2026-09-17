# The Goldman roulette wheel.
#
# `OPTIONS.BM`, in the original's own words:
#
#     Gold Bomberman: (Yes/No) The Gold Bomberman is a reward given to the
#     winner of the last match. The reward consists of a random powerup
#     determined by the roulette wheel. (Not available in network games)
#
# ---------------------------------------------------------------------------
# THE ANIMATION IS IN THE DATA, TO THE PIXEL
# ---------------------------------------------------------------------------
# This is the only screen whose layout the port did not have to invent, because
# VALUELST spells it out — and those entries are multi-value, which is why
# `Values.V[1000]` is an array:
#
#     1000,320,240   ; center of roulette wheel for goldman screen
#     1002,200,150   ; radius(es) (x,y) of roulette wheel perimeter
#     1004,70        ; resolution of the circle the roulette wheel turns on
#     1006,1,1       ; X,Y parameters for lissajous-shaped roulette wheel
#     1010,5         ; how many seconds the twinkling of goldman lasts
#      805,320,30,0,400   ; Goldman Roulette Wheel (title at top)
#      800,150,94,0,400   ; player %u wins the match...
#
# So: fourteen powerup icons on an ELLIPSE of radii 200x150 about (320, 240),
# stepped at a resolution of 70, with the path shaped by a Lissajous figure
# whose X and Y parameters are both 1 — which is a plain ellipse, and is
# presumably why the comment beside it ends in "(grin)". The port implements the
# general form anyway, because the data can say otherwise.
#
# Resource 1004's comment says "300 is minimum!" and its value is 70. The
# comment is wrong about its own value, so the value is used.
#
# ---------------------------------------------------------------------------
# WHAT IT GIVES
# ---------------------------------------------------------------------------
# All fourteen powerups, including CLOG — the fourteenth, which `MESSAGES.TXT`
# 813 calls "a speed brake (slowness)" and which VALUELST resource 91 describes
# as "how much speed the CLOGS (special roulette power-'down') take away". The
# wheel can punish you, and SOUNDLST has a sound for exactly that: 1320 is a
# "buzzer sound, you got the molasses roulette powerup (powerdown)".
extends RefCounted

const Const_ := preload("res://scripts/core/const.gd")
const Types_ := preload("res://scripts/core/types.gd")
const Values_ := preload("res://scripts/core/values.gd")
const Messages_ := preload("res://scripts/core/messages.gd")

## The fourteen the wheel offers, which is every powerup the game has —
## `MESSAGES.TXT` 850-863 names all of them and POWERS.ANI draws all of them.
const WHEEL_SIZE := 14

## The powerup that is a punishment. Types.PowerUp stops at RANDOM (12) because
## a scheme can only place thirteen; the fourteenth exists only here.
const CLOG := 13

enum Phase { SPINNING, SLOWING, TWINKLING, DONE }

var slot: int = -1
var phase: int = Phase.SPINNING
var result: int = -1

## Ticks elapsed, which is the animation's whole clock.
var age: int = 0

## Where the wheel is, in steps of resource 1004's resolution.
var position: float = 0.0
var speed: float = 0.0

## Ticks of each phase. The spin is this port's; the twinkle is resource 1010's
## five seconds.
const SPIN_TICKS := 40
const SLOW_TICKS := 60

var _rng := RandomNumberGenerator.new()


func start(for_slot: int, seed_value: int) -> void:
	slot = for_slot
	phase = Phase.SPINNING
	age = 0
	result = -1
	_rng.seed = seed_value
	# BOTH the starting position and the speed come from the seed. With a fixed
	# speed and a fixed start the deceleration is deterministic and the wheel
	# lands on the same icon every single time — measured over 119 seeds, one
	# prize. A roulette that always pays the same is not one.
	position = _rng.randf() * float(resolution())
	# Fast enough that the icons blur, which is what a spinning wheel does.
	speed = 2.0 + _rng.randf() * 1.4


func resolution() -> int:
	return maxi(1, int(_value(Const_.Res.ROULETTE_RESOLUTION, 70)))


func centre() -> Vector2:
	var v: Variant = Values_.V.get(Const_.Res.ROULETTE_CENTRE, [320, 240])
	if v is Array and (v as Array).size() >= 2:
		return Vector2(float(v[0]), float(v[1]))
	return Vector2(320, 240)


func radii() -> Vector2:
	var v: Variant = Values_.V.get(Const_.Res.ROULETTE_RADII, [200, 150])
	if v is Array and (v as Array).size() >= 2:
		return Vector2(float(v[0]), float(v[1]))
	return Vector2(200, 150)


## The Lissajous parameters. Both are 1 on the disc, which makes the path a
## plain ellipse; the general form is implemented because the data can say
## otherwise and because resource 1006 exists to say it.
func lissajous() -> Vector2:
	var v: Variant = Values_.V.get(Const_.Res.ROULETTE_LISSAJOUS, [1, 1])
	if v is Array and (v as Array).size() >= 2:
		return Vector2(float(v[0]), float(v[1]))
	return Vector2(1, 1)


func twinkle_ticks() -> int:
	return int(_value(Const_.Res.GOLDMAN_TWINKLE_SECONDS, 5)) * Const_.TICK_HZ


func _value(res: int, fallback: int) -> int:
	var v: Variant = Values_.V.get(res, fallback)
	if v is Array:
		return int((v as Array)[0]) if not (v as Array).is_empty() else fallback
	return int(v)


## Where icon `index` sits, for a wheel at `position`.
##
## The path is the Lissajous figure resource 1006 parameterises, sampled at
## resource 1004's resolution:
##
##     x = cx + rx * sin(a * t)
##     y = cy + ry * cos(b * t)
##
## With a = b = 1 that is the ellipse resources 1000 and 1002 describe.
func icon_position(index: int) -> Vector2:
	var steps := float(resolution())
	var at := (position + float(index) * steps / float(WHEEL_SIZE))
	var t := at / steps * TAU
	var l := lissajous()
	var c := centre()
	var r := radii()
	return Vector2(c.x + r.x * sin(l.x * t), c.y + r.y * cos(l.y * t))


## Which icon is at the top of the wheel — the one the pointer reads.
func icon_at_top() -> int:
	var steps := float(resolution())
	var per := steps / float(WHEEL_SIZE)
	# index 0 sits at the top when position is 0, so walk backwards.
	return int(posmod(roundi(-position / per), WHEEL_SIZE))


func tick() -> void:
	age += 1
	match phase:
		Phase.SPINNING:
			position += speed
			if age >= SPIN_TICKS:
				phase = Phase.SLOWING
		Phase.SLOWING:
			# Eased to a stop rather than cut, so the wheel lands rather than
			# stopping dead. When it is slow enough, whatever is at the top is
			# the prize — which is how a wheel decides.
			speed = maxf(speed * 0.94 - 0.006, 0.0)
			position += speed
			if speed <= 0.01 or age >= SPIN_TICKS + SLOW_TICKS:
				speed = 0.0
				result = icon_at_top()
				phase = Phase.TWINKLING
		Phase.TWINKLING:
			if age >= SPIN_TICKS + SLOW_TICKS + twinkle_ticks():
				phase = Phase.DONE


func finished() -> bool:
	return phase == Phase.DONE


## Stop now and take the prize, for a player who does not want to watch.
func skip() -> void:
	if result < 0:
		result = icon_at_top()
	phase = Phase.DONE


func punishment() -> bool:
	return result == CLOG


## "The Gold Player has <powerup> for the next match!!" — MESSAGES.TXT 790 and
## 791, with the powerup's own name from 800-813.
func announcement() -> Array[String]:
	var name := "?"
	if result >= 0 and result < Messages_.POWERUP_LONG.size():
		name = String(Messages_.POWERUP_LONG[result])
	return [String(Messages_.GOLD_PLAYER_HAS), name,
		String(Messages_.FOR_NEXT_MATCH)] as Array[String]


## The POWERS.ANI sequence for one wheel position. Its fourteen sequences are
## named for the powerups, and `power clog` is the fourteenth.
static func icon_sequence(index: int) -> String:
	const NAMES := ["power bomb", "power flame", "power disease3",
		"power kicker", "power skate", "power punch", "power grab",
		"power spooge", "power goldflame", "power trigger", "power jelly",
		"power disease", "power random", "power clog"]
	return NAMES[clampi(index, 0, NAMES.size() - 1)]
