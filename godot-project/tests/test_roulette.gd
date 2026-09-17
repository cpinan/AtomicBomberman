# The Goldman roulette wheel.
#
# The one screen whose LAYOUT came out of the data rather than out of this
# port, so most of these assertions are against VALUELST directly:
#
#     1000,320,240   ; center of roulette wheel for goldman screen
#     1002,200,150   ; radius(es) (x,y) of roulette wheel perimeter
#     1004,70        ; resolution of the circle the roulette wheel turns on
#     1006,1,1       ; X,Y parameters for lissajous-shaped roulette wheel
#     1010,5         ; how many seconds the twinkling of goldman lasts
#
# Those entries are MULTI-VALUE, which is worth an assertion of its own: 40 of
# VALUELST's 251 resources are arrays, and a parser that kept only the first
# number would leave this wheel a circle of radius 200 centred on nothing.
extends SceneTree

const T_ := preload("res://tests/t.gd")
const Const_ := preload("res://scripts/core/const.gd")
const Types_ := preload("res://scripts/core/types.gd")
const Values_ := preload("res://scripts/core/values.gd")
const Messages_ := preload("res://scripts/core/messages.gd")
const Roulette_ := preload("res://scripts/app/roulette.gd")


func _init() -> void:
	var t := T_.new("roulette")
	_test_the_data_says_this(t)
	_test_the_wheel_is_an_ellipse(t)
	_test_it_spins_and_lands(t)
	_test_every_position_is_reachable(t)
	_test_the_prize(t)
	_test_skipping(t)
	quit(t.finish())


func _test_the_data_says_this(t: T_) -> void:
	# Multi-value resources, which is the format that carries this screen.
	for res in [Const_.Res.ROULETTE_CENTRE, Const_.Res.ROULETTE_RADII,
			Const_.Res.ROULETTE_LISSAJOUS]:
		var v: Variant = Values_.V.get(res, null)
		t.ok(v is Array, "resource %d is a multi-value entry" % res)
		if v is Array:
			t.eq((v as Array).size(), 2, "of two numbers")

	var r: Roulette_ = Roulette_.new()
	t.eq(r.centre(), Vector2(320, 240), "the wheel is centred on 320,240")
	t.eq(r.radii(), Vector2(200, 150), "with radii 200 and 150")
	t.eq(r.resolution(), 70, "at a resolution of 70")
	t.eq(r.lissajous(), Vector2(1, 1), "and Lissajous parameters of 1 and 1")
	t.eq(r.twinkle_ticks(), 5 * Const_.TICK_HZ,
		"the winner twinkles for resource 1010's five seconds")

	# Fourteen icons, which is every powerup the game has — including the
	# fourteenth, Clog, which a scheme cannot place and which is what makes
	# this wheel able to punish.
	t.eq(Roulette_.WHEEL_SIZE, Messages_.POWERUP_SHORT.size(),
		"the wheel offers all fourteen powerups")
	t.eq(Roulette_.CLOG, 13, "and the fourteenth is the Clog")
	t.eq(Messages_.POWERUP_SHORT[Roulette_.CLOG], "Clog",
		"which MESSAGES.TXT 863 names")
	t.eq(Values_.V[Const_.Res.CLOG_PENALTY], 150,
		"and resource 91 says it costs 150 hundredths of a pixel")


# The path is an ellipse, so every icon must sit on it: (dx/rx)^2 + (dy/ry)^2
# is 1 for every one of them, whatever the wheel's rotation.
func _test_the_wheel_is_an_ellipse(t: T_) -> void:
	var r: Roulette_ = Roulette_.new()
	r.start(0, 1)
	var c := r.centre()
	var radii := r.radii()
	for step in [0.0, 7.5, 31.0, 63.25]:
		r.position = step
		for i in Roulette_.WHEEL_SIZE:
			var at: Vector2 = r.icon_position(i)
			var dx := (at.x - c.x) / radii.x
			var dy := (at.y - c.y) / radii.y
			t.close(dx * dx + dy * dy, 1.0, 0.001,
				"icon %d at rotation %.1f is on the ellipse" % [i, step])
			# And on the screen, which a radius of 200 about x=320 just is.
			t.ok(at.x >= 0.0 and at.x <= float(Const_.SCREEN_W),
				"icon %d is on screen horizontally" % i)
			t.ok(at.y >= 0.0 and at.y <= float(Const_.SCREEN_H),
				"and vertically")

	# The fourteen are evenly spaced, so the wheel reads as a wheel.
	r.position = 0.0
	var gaps: Array[float] = []
	for i in Roulette_.WHEEL_SIZE:
		var a: Vector2 = r.icon_position(i)
		var b: Vector2 = r.icon_position((i + 1) % Roulette_.WHEEL_SIZE)
		gaps.append(a.distance_to(b))
	var lo: float = gaps.min()
	var hi: float = gaps.max()
	# Not equal, because the ellipse is wider than it is tall — but within a
	# factor that keeps them from bunching.
	t.ok(hi / lo < 1.8,
		"the icons are spread evenly enough (%.0f to %.0f px apart)"
			% [lo, hi])


func _test_it_spins_and_lands(t: T_) -> void:
	var r: Roulette_ = Roulette_.new()
	r.start(3, 12345)
	t.eq(r.phase, Roulette_.Phase.SPINNING, "it starts spinning")
	t.eq(r.result, -1, "with no result yet")
	t.eq(r.slot, 3, "for the player who won")

	var moved := false
	var last := r.position
	for _i in 20:
		r.tick()
		if not is_equal_approx(r.position, last):
			moved = true
		last = r.position
	t.ok(moved, "and the wheel turns")
	t.eq(r.result, -1, "still with no result while it spins")

	# It slows to a stop and takes what is under the pointer.
	for _i in 200:
		r.tick()
		if r.result >= 0:
			break
	t.ok(r.result >= 0, "it lands on something (%d)" % r.result)
	t.ok(r.result < Roulette_.WHEEL_SIZE, "which is one of the fourteen")
	t.eq(r.speed, 0.0, "and stops")
	t.eq(r.result, r.icon_at_top(),
		"on whatever the pointer is over")

	# Then it twinkles for resource 1010's five seconds and finishes.
	t.ok(not r.finished(), "it is not finished the moment it lands")
	var twinkled := 0
	while not r.finished() and twinkled < r.twinkle_ticks() * 3:
		r.tick()
		twinkled += 1
	t.ok(r.finished(), "and finishes after the twinkle (%d ticks)" % twinkled)
	t.ok(twinkled >= r.twinkle_ticks() - 2,
		"having twinkled for at least resource 1010's five seconds (%d of %d)"
			% [twinkled, r.twinkle_ticks()])

	# Same seed, same prize — the reward carries into the next match, so a
	# match that replays must award the same thing.
	var again: Roulette_ = Roulette_.new()
	again.start(3, 12345)
	for _i in 400:
		again.tick()
	t.eq(again.result, r.result, "the same seed awards the same prize")


func _test_every_position_is_reachable(t: T_) -> void:
	# Over many seeds the wheel must be able to land anywhere, or some
	# powerups would never be awarded.
	var seen := {}
	for seed_value in range(1, 120):
		var r: Roulette_ = Roulette_.new()
		r.start(0, seed_value * 7919)
		for _i in 400:
			r.tick()
			if r.result >= 0:
				break
		seen[r.result] = true
	t.ok(seen.size() >= 8,
		"the wheel reaches %d of its %d positions over 119 seeds"
			% [seen.size(), Roulette_.WHEEL_SIZE])
	t.ok(not seen.has(-1), "and always lands on something")


func _test_the_prize(t: T_) -> void:
	var r: Roulette_ = Roulette_.new()
	r.start(0, 1)
	r.result = Roulette_.CLOG
	t.ok(r.punishment(), "the Clog is a punishment")
	r.result = Types_.PowerUp.BOMB
	t.ok(not r.punishment(), "an extra bomb is not")

	# The announcement is the disc's own: MESSAGES.TXT 790 and 791 around the
	# powerup's name from 800-813.
	var lines := r.announcement()
	t.eq(lines.size(), 3, "the announcement is three parts")
	t.eq(lines[0], Messages_.GOLD_PLAYER_HAS, "the disc's own opening")
	t.eq(lines[1], Messages_.POWERUP_LONG[Types_.PowerUp.BOMB],
		"the powerup's own long name")
	t.eq(lines[2], Messages_.FOR_NEXT_MATCH, "and the disc's own closing")

	# Every wheel position names a POWERS.ANI sequence that exists.
	for i in Roulette_.WHEEL_SIZE:
		var seq := Roulette_.icon_sequence(i)
		t.ok(seq.begins_with("power "),
			"position %d draws %s" % [i, seq])


func _test_skipping(t: T_) -> void:
	# Somebody who does not want to watch five seconds of twinkling takes
	# whatever is under the pointer.
	var r: Roulette_ = Roulette_.new()
	r.start(1, 99)
	for _i in 10:
		r.tick()
	t.eq(r.result, -1, "still spinning")
	r.skip()
	t.ok(r.finished(), "skipping finishes it")
	t.ok(r.result >= 0, "with a prize (%d)" % r.result)
	t.eq(r.result, r.icon_at_top(), "which is what was under the pointer")
