# The generated value table against hand-checked spot values.
#
# The point is not to re-assert every one of the 251 resources — that would just
# be the generator compared to itself. It is to catch the two failures that
# matter: the generator silently producing a WRONG number, and the sim's own
# structural constants drifting away from the table they were derived from.
#
# Every expected value below was read by eye out of RES/VALUELST.RES and is
# recorded in docs/ORACLE.md with its meaning.
extends SceneTree

const T_ := preload("res://tests/t.gd")
const Const_ := preload("res://scripts/core/const.gd")
const Types_ := preload("res://scripts/core/types.gd")
const Values_ := preload("res://scripts/core/values.gd")

# resource -> value, transcribed from the original by hand. If the generator
# and this table ever disagree, one of them is wrong and the test says which.
const SPOT := {
	# rate — the whole of ORACLE section 1
	25: 20,      # nominal reference frame rate
	30: 20,      # frame rate the game attempts
	31: 150,     # max ms one frame may advance
	10: 10,      # flame animation frames
	20: 10,      # brick disintegration frames
	32: 40,      # frames before team colours
	# bombs
	41: 40,      # fuze frames
	300: 1000,   # kicked bomb speed
	301: 1300,   # punched bomb speed
	322: 3,      # dud chance, 1-in-N
	323: 120,    # dud wait frames
	324: 200,    # dud wait, random extra
	660: 65,     # punch arc, big
	661: 20,     # punch arc, small
	665: 2,      # pickup pause frames
	667: 3,      # jelly turn chance
	# speed
	42: 923,     # starting speed, hundredths px/frame
	90: 150,     # skate bonus, additive
	91: 150,     # clog penalty
	# caps
	550: 8,      # bombs
	551: 8,      # flame
	553: 1,      # kick
	554: 4,      # skates
	# round
	100: 150,    # default round seconds
	101: 60,     # hurry at, seconds remaining
	310: 2,      # wins to win a match
	27: 1,       # enclosement depth default = two rows
	28: 4,       # number of depths
	46: 1,       # a closing wall detonates a bomb
	# diseases
	125: 10,     # cure chance on new powerup
	129: 10,     # freshness lock, frames
	130: 300,    # first disease duration, frames
	138: 300,    # ninth disease duration, frames
	# conveyors
	189: 3,      # how many speeds
	190: 250,
	191: 350,
	192: 450,
	# levels
	35: 11,      # number of levels
	347: 4,      # haunted house tile regeneration, seconds
	452: 250,    # hockey rink ice delay, ms
	695: 4,      # regeneration clear radius
	680: 30,     # trampoline bounce frames
	681: 35,     # trampoline rise px/frame
	# counts
	105: 24,     # death animations
	330: 13,     # cornerhead animations
	# ai
	900: 1,      # personalities
	910: 15,     # fire-god lookahead
	915: 5,      # blast-bricks chance
	920: 4,      # powerup pursuit radius
	# flavour
	92: 30,      # attract mode after N seconds
	95: 5,       # post-death taunt chance
	8: 5,        # concurrent sounds
	# head hit
	670: 1,
	671: 3,
}

# resource -> [values], for the multi-valued rows
const SPOT_MULTI := {
	500: [12, 10],   # bomb pickup curve, point 1
	502: [25, 20],
	504: [25, 30],
	506: [12, 40],
	600: [0, 0],     # player 0 start
	602: [-1, -1],   # player 1 start — negative wraps to (14, 10)
	690: [2, 2],     # cursor blink base, random
}


func _init() -> void:
	var t := T_.new("values")

	# 1. Spot values.
	for number in SPOT:
		t.eq(Values_.V.get(number), SPOT[number], "resource %d" % number)
	for number in SPOT_MULTI:
		t.eq(Values_.V.get(number), SPOT_MULTI[number], "resource %d" % number)

	# 2. The sim's structural constants must match the table they came from.
	# This is the check that catches a future edit to const.gd drifting away
	# from the original, which no amount of spot-checking the table would.
	t.eq(Const_.TICK_HZ, Values_.V[Const_.Res.TARGET_FPS],
		"Const.TICK_HZ vs resource 30")
	t.eq(Const_.TICK_HZ, Values_.V[Const_.Res.NOMINAL_FPS],
		"Const.TICK_HZ vs resource 25")
	t.eq(Const_.TICK_MS * Const_.TICK_HZ, 1000, "TICK_MS * TICK_HZ == 1000ms")

	# 3. Every resource the Res class names must actually exist. A typo in a
	# resource number would otherwise surface as a crash much later, in
	# whichever phase first reads it.
	_check_res_names(t)

	# 4. The indexed blocks must be complete: one entry per powerup for the
	# loadout, cap and spawn tables, and one per disease for the durations.
	for p in Const_.POWERUP_COUNT:
		t.ok(Values_.V.has(Const_.Res.BORN_WITH_BASE + p),
			"born-with table has powerup %d" % p)
		t.ok(Values_.V.has(Const_.Res.CAP_BASE + p), "cap table has powerup %d" % p)
		t.ok(Values_.V.has(Const_.Res.SPAWN_BASE + p),
			"spawn table has powerup %d" % p)
	for d in Const_.DISEASE_DURATION_SLOTS:
		t.ok(Values_.V.has(Const_.Res.DISEASE_DURATION_BASE + d),
			"disease duration slot %d exists" % d)
	for i in Const_.PLAYER_COUNT:
		t.ok(Values_.V.has(Const_.Res.START_POS_BASE + i * 2),
			"start position table has player %d" % i)
		t.ok(Values_.V.has(Const_.Res.COLOUR_BASE + i * 5),
			"colour table has player %d" % i)

	# 5. The unit conversions, which are the part most likely to be quietly
	# wrong. 923 hundredths px/frame at 20 Hz over 40x36 tiles.
	t.close(Const_.speed_px_per_tick(923), 9.23, 1e-6, "923 -> px/tick")
	t.close(Const_.speed_tiles_h(923), 4.615, 0.001, "923 -> tiles/s horizontal")
	t.close(Const_.speed_tiles_v(923), 5.128, 0.001, "923 -> tiles/s vertical")
	# The anisotropy is the finding, so assert it rather than leaving it
	# implicit: the same speed crosses a row faster than a column.
	t.ok(Const_.speed_tiles_v(923) > Const_.speed_tiles_h(923),
		"vertical tile speed exceeds horizontal (tiles are 40x36)")
	t.eq(Const_.frames_to_ms(40), 2000, "40 frame fuze is 2000ms")

	# 6. Skates are additive and capped at 4, not multiplicative — ORACLE row 3.
	var base: int = Values_.V[Const_.Res.START_SPEED]
	var bonus: int = Values_.V[Const_.Res.SKATE_BONUS]
	var cap: int = Values_.V[Const_.Res.CAP_BASE + Types_.PowerUp.SKATE]
	t.eq(base + bonus * cap, 1523, "fully skated speed is 923 + 4*150")
	t.close(Const_.speed_tiles_h(base + bonus * cap), 7.615, 0.001,
		"fully skated horizontal tiles/s")

	# 7. A negative start coordinate wraps from the far edge.
	var p1: Array = Values_.V[Const_.Res.START_POS_BASE + 2]
	t.eq(Const_.wrap_x(p1[0]), 14, "player 1 start x, -1 wraps to 14")
	t.eq(Const_.wrap_y(p1[1]), 10, "player 1 start y, -1 wraps to 10")

	# 8. The developers disabled two levels from random selection, with
	# reasons. Assert it, because it is the kind of detail a port drops.
	t.eq(Values_.V[Const_.Res.RANDOM_LEVEL_ENABLED_BASE + 2], 0,
		"hockey rink excluded from random levels")
	t.eq(Values_.V[Const_.Res.RANDOM_LEVEL_ENABLED_BASE + 6], 0,
		"aliens excluded from random levels")

	# 9. Only the haunted house regenerates tiles.
	for level in 11:
		var want := 4 if level == 7 else 0
		t.eq(Values_.V[Const_.Res.REGEN_INTERVAL_BASE + level], want,
			"level %d tile regeneration interval" % level)

	# 10. Only the hockey rink has ice.
	for level in 11:
		var want := 250 if level == 2 else 0
		t.eq(Values_.V[Const_.Res.ICE_DELAY_BASE + level], want,
			"level %d ice delay" % level)

	t.note("%d resources in the generated table, %d tagged PGT"
		% [Values_.V.size(), Values_.PGT.size()])
	quit(t.finish())


# Every constant declared in Const.Res is a resource number, so all of them
# must resolve. Listed explicitly because GDScript cannot enumerate a class's
# constants at runtime, and a list that must be maintained by hand is still
# better than a typo that surfaces three phases later.
func _check_res_names(t: T_) -> void:
	var R := Const_.Res
	var named := {
		"FLAME_ANIM_FRAMES": R.FLAME_ANIM_FRAMES,
		"BRICK_ANIM_FRAMES": R.BRICK_ANIM_FRAMES,
		"NOMINAL_FPS": R.NOMINAL_FPS,
		"TARGET_FPS": R.TARGET_FPS,
		"MAX_ADVANCE_MS": R.MAX_ADVANCE_MS,
		"TEAM_COLOUR_FRAMES": R.TEAM_COLOUR_FRAMES,
		"LEVEL_COUNT": R.LEVEL_COUNT,
		"FUZE_FRAMES": R.FUZE_FRAMES,
		"START_SPEED": R.START_SPEED,
		"DEFAULT_BOMBTYPE": R.DEFAULT_BOMBTYPE,
		"SKATE_BONUS": R.SKATE_BONUS,
		"CLOG_PENALTY": R.CLOG_PENALTY,
		"ROUND_SECONDS": R.ROUND_SECONDS,
		"HURRY_AT_SECONDS": R.HURRY_AT_SECONDS,
		"OVERPOWER_LOCKOUT": R.OVERPOWER_LOCKOUT,
		"WINS_TO_WIN": R.WINS_TO_WIN,
		"ENCLOSE_DEPTH": R.ENCLOSE_DEPTH,
		"ENCLOSE_DEPTH_COUNT": R.ENCLOSE_DEPTH_COUNT,
		"WALL_DETONATES_BOMB": R.WALL_DETONATES_BOMB,
		"DISEASE_DESTROYABLE": R.DISEASE_DESTROYABLE,
		"DISEASE_TIME_LIMITED": R.DISEASE_TIME_LIMITED,
		"DISEASE_RECYCLES": R.DISEASE_RECYCLES,
		"DISEASE_MULTIPLIES": R.DISEASE_MULTIPLIES,
		"DISEASE_CURABLE": R.DISEASE_CURABLE,
		"DISEASE_CURE_CHANCE": R.DISEASE_CURE_CHANCE,
		"DISEASE_FRESHNESS": R.DISEASE_FRESHNESS,
		"CONVEYOR_SPEED_COUNT": R.CONVEYOR_SPEED_COUNT,
		"KICKED_BOMB_SPEED": R.KICKED_BOMB_SPEED,
		"PUNCHED_BOMB_SPEED": R.PUNCHED_BOMB_SPEED,
		"DUD_MIN_SECONDS": R.DUD_MIN_SECONDS,
		"DUD_RAND_SECONDS": R.DUD_RAND_SECONDS,
		"DUD_CHANCE": R.DUD_CHANCE,
		"DUD_WAIT_FRAMES": R.DUD_WAIT_FRAMES,
		"DUD_WAIT_RAND_FRAMES": R.DUD_WAIT_RAND_FRAMES,
		"PUNCH_ARC_BIG": R.PUNCH_ARC_BIG,
		"PUNCH_ARC_SMALL": R.PUNCH_ARC_SMALL,
		"PICKUP_PAUSE_FRAMES": R.PICKUP_PAUSE_FRAMES,
		"JELLY_TURN_CHANCE": R.JELLY_TURN_CHANCE,
		"DEATH_ANIM_COUNT": R.DEATH_ANIM_COUNT,
		"CORNER_ANIM_COUNT": R.CORNER_ANIM_COUNT,
		"HEAD_HIT_MIN_LOSS": R.HEAD_HIT_MIN_LOSS,
		"HEAD_HIT_RAND_LOSS": R.HEAD_HIT_RAND_LOSS,
		"TRAMP_BOUNCE_FRAMES": R.TRAMP_BOUNCE_FRAMES,
		"TRAMP_RISE_PX": R.TRAMP_RISE_PX,
		"REGEN_CLEAR_RADIUS": R.REGEN_CLEAR_RADIUS,
		"ATTRACT_SECONDS": R.ATTRACT_SECONDS,
		"TAUNT_CHANCE": R.TAUNT_CHANCE,
		"CONCURRENT_SOUNDS": R.CONCURRENT_SOUNDS,
		"AI_PERSONALITIES": R.AI_PERSONALITIES,
		"AI_FIREGOD_LOOKAHEAD": R.AI_FIREGOD_LOOKAHEAD,
		"AI_BLAST_BRICKS_CHANCE": R.AI_BLAST_BRICKS_CHANCE,
		"AI_POWERUP_RADIUS": R.AI_POWERUP_RADIUS,
	}
	for name in named:
		t.ok(Values_.V.has(named[name]),
			"Const.Res.%s = %d exists in the table" % [name, named[name]])
