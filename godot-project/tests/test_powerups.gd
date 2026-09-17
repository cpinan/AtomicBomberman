# Powerups: placement, collection, caps, exclusions and the disease model.
#
# Every number here is read out of the tuning table rather than written down, so
# the suite measures the port against the original's data and not against
# itself. docs/ORACLE.md rows 3, 5, 9, 28-32.
extends SceneTree

const T_ := preload("res://tests/t.gd")
const Const_ := preload("res://scripts/core/const.gd")
const Types_ := preload("res://scripts/core/types.gd")
const Values_ := preload("res://scripts/core/values.gd")
const Scheme_ := preload("res://scripts/core/scheme.gd")
const Field_ := preload("res://scripts/sim/field.gd")
const Sim_ := preload("res://scripts/sim/sim.gd")
const Player_ := preload("res://scripts/sim/player.gd")


func _init() -> void:
	var t := T_.new("powerups")
	_test_placement(t)
	_test_collection(t)
	_test_caps(t)
	_test_stat_effects(t)
	_test_trigger_exclusion(t)
	_test_random(t)
	_test_diseases(t)
	_test_repopulate(t)
	quit(t.finish())


# Placement follows the counts in VALUELST 400..412, including the
# negative-means-1-in-10 rule the resource's own comment describes.
func _test_placement(t: T_) -> void:
	var sim := _sim(1, 100)

	# Powerups only ever hide under destructible bricks.
	for y in Const_.FIELD_H:
		for x in Const_.FIELD_W:
			if sim.field.has_powerup(x, y):
				t.ok(sim.field.brick_at(x, y) == Types_.Brick.BRICK,
					"the powerup at (%d,%d) is under a brick" % [x, y])

	# The positive counts are exact. Bombs are 10 and flames 10.
	for which in [Types_.PowerUp.BOMB, Types_.PowerUp.FLAME,
			Types_.PowerUp.KICK, Types_.PowerUp.SKATE]:
		var want: int = Values_.V[Const_.Res.SPAWN_BASE + which]
		t.eq(sim.field.count_powerups_of(which), want,
			"powerup %d placed exactly %d times" % [which, want])

	# The negative counts are 1-in-10 rolls, so somewhere between none and all.
	for which in [Types_.PowerUp.GOLDFLAME, Types_.PowerUp.TRIGGER,
			Types_.PowerUp.SUPER_BAD_DISEASE]:
		var rolls: int = absi(Values_.V[Const_.Res.SPAWN_BASE + which])
		var got := sim.field.count_powerups_of(which)
		t.ok(got >= 0 and got <= rolls,
			"powerup %d from %d rolls placed %d" % [which, rolls, got])

	# Averaged over many seeds, a -N powerup lands about N/10 times.
	var total := 0
	var runs := 60
	for seed_value in runs:
		var s2 := _sim(1, 100, seed_value)
		total += s2.field.count_powerups_of(Types_.PowerUp.TRIGGER)
	var rolls_t: int = absi(Values_.V[Const_.Res.SPAWN_BASE + Types_.PowerUp.TRIGGER])
	t.close(float(total) / runs, rolls_t / 10.0, 0.35,
		"trigger averages about %.1f per round over %d seeds" % [rolls_t / 10.0, runs])

	# A scheme can forbid a powerup, and then it never appears.
	var forbidden := _sim(1, 100, 1, {Types_.PowerUp.BOMB: {"forbidden": true}})
	t.eq(forbidden.field.count_powerups_of(Types_.PowerUp.BOMB), 0,
		"a forbidden powerup is never placed")

	# And it can override the count.
	var over := _sim(1, 100, 1,
		{Types_.PowerUp.KICK: {"has_override": true, "override": 3}})
	t.eq(over.field.count_powerups_of(Types_.PowerUp.KICK), 3,
		"an overridden count is honoured")

	# One cell never holds two powerups.
	var cells := {}
	var dupes := 0
	for y in Const_.FIELD_H:
		for x in Const_.FIELD_W:
			if sim.field.has_powerup(x, y):
				if cells.has(Vector2i(x, y)):
					dupes += 1
				cells[Vector2i(x, y)] = true
	t.eq(dupes, 0, "no cell holds two powerups")

	# Same seed, same layout. [invariant]
	var a := _sim(1, 100, 99)
	var b := _sim(1, 100, 99)
	t.eq(a.field.to_bytes(), b.field.to_bytes(),
		"[invariant] the same seed places powerups identically")


func _test_collection(t: T_) -> void:
	var sim := _sim(1, 0)
	var p: Player_ = sim.players[0]
	p.place_at_tile_centre(5, 5)
	sim.field.powerup[Field_.idx(5, 5)] = Types_.PowerUp.BOMB

	var before := p.bombs_total
	sim.tick()
	t.eq(p.bombs_total, before + 1, "standing on a bomb powerup collects it")
	t.ok(not sim.field.has_powerup(5, 5), "and takes it off the field")
	t.eq(p.collected[Types_.PowerUp.BOMB], 1, "and counts it")

	# Nothing there, nothing collected.
	var before2 := p.bombs_total
	sim.tick()
	t.eq(p.bombs_total, before2, "an empty cell gives nothing")


# VALUELST 550..564: bombs 8, flame 8, skates 4, everything else 1.
func _test_caps(t: T_) -> void:
	var expected := {
		Types_.PowerUp.BOMB: 8, Types_.PowerUp.FLAME: 8,
		Types_.PowerUp.SKATE: 4, Types_.PowerUp.KICK: 1,
		Types_.PowerUp.PUNCH: 1, Types_.PowerUp.GRAB: 1,
		Types_.PowerUp.SPOOGE: 1, Types_.PowerUp.GOLDFLAME: 1,
		Types_.PowerUp.TRIGGER: 1, Types_.PowerUp.JELLY: 1,
	}
	for which in expected:
		t.eq(Values_.V[Const_.Res.CAP_BASE + which], expected[which],
			"cap on powerup %d" % which)

	# Collecting past the cap must not keep raising the stat.
	var sim := _sim(1, 0)
	var p: Player_ = sim.players[0]
	for _i in 30:
		sim.give_powerup(p, Types_.PowerUp.BOMB)
	t.eq(p.collected[Types_.PowerUp.BOMB], 8, "bombs stop at the cap of 8")
	t.eq(p.bombs_total,
		Values_.V[Const_.Res.BORN_WITH_BASE + Types_.PowerUp.BOMB] + 8,
		"and the bomb count stops with it")

	var s2 := _sim(1, 0)
	var p2: Player_ = s2.players[0]
	for _i in 30:
		s2.give_powerup(p2, Types_.PowerUp.SKATE)
	t.eq(p2.collected[Types_.PowerUp.SKATE], 4, "skates stop at the cap of 4")
	# Four skates, additive, is the fully-skated speed ORACLE row 3 gives.
	t.eq(p2.speed, Values_.V[Const_.Res.START_SPEED]
		+ 4 * Values_.V[Const_.Res.SKATE_BONUS], "fully skated is 923 + 4*150")
	t.eq(p2.speed, 1523, "which is 1523 hundredths of a pixel per frame")

	# A capped pickup reports that it did nothing.
	var s3 := _sim(1, 0)
	var p3: Player_ = s3.players[0]
	t.ok(s3.give_powerup(p3, Types_.PowerUp.KICK), "the first kicker applies")
	t.ok(not s3.give_powerup(p3, Types_.PowerUp.KICK),
		"the second is refused, being at the cap of 1")


func _test_stat_effects(t: T_) -> void:
	var sim := _sim(1, 0)
	var p: Player_ = sim.players[0]

	var flame0 := p.flame_len
	sim.give_powerup(p, Types_.PowerUp.FLAME)
	t.eq(p.flame_len, flame0 + 1, "a flame powerup adds one cell of reach")

	sim.give_powerup(p, Types_.PowerUp.GOLDFLAME)
	t.eq(p.flame_len, Values_.V[Const_.Res.CAP_BASE + Types_.PowerUp.FLAME],
		"goldflame goes straight to the flame cap, not +1")

	for ability in [Types_.PowerUp.KICK, Types_.PowerUp.GRAB,
			Types_.PowerUp.JELLY]:
		var s2 := _sim(1, 0)
		var p2: Player_ = s2.players[0]
		s2.give_powerup(p2, ability)
		match ability:
			Types_.PowerUp.KICK: t.ok(p2.can_kick, "the kicker grants kicking")
			Types_.PowerUp.GRAB: t.ok(p2.can_grab, "the glove grants grabbing")
			Types_.PowerUp.JELLY: t.ok(p2.jelly_bombs, "jelly grants bouncing")


# Trigger is exclusive with spooge and punch, and taking it drops both.
# AtomBomberman's notes: "you can have oil+punch, but you cant have trigger+oil
# or trigger+punch / if you have oil+punch and you pick-up trigger, you will
# drop oil AND punch".
func _test_trigger_exclusion(t: T_) -> void:
	var sim := _sim(1, 0)
	var p: Player_ = sim.players[0]

	sim.give_powerup(p, Types_.PowerUp.SPOOGE)
	sim.give_powerup(p, Types_.PowerUp.PUNCH)
	t.ok(p.can_spooge and p.can_punch, "spooge and punch coexist")

	sim.give_powerup(p, Types_.PowerUp.TRIGGER)
	t.ok(not p.can_spooge, "taking trigger drops spooge")
	t.ok(not p.can_punch, "taking trigger drops punch")
	t.ok(p.trigger_bombs > 0, "and grants trigger bombs")
	t.eq(p.collected[Types_.PowerUp.SPOOGE], 0, "spooge is uncollected")
	t.eq(p.collected[Types_.PowerUp.PUNCH], 0, "punch is uncollected")

	# And the reverse: taking punch drops trigger.
	sim.give_powerup(p, Types_.PowerUp.PUNCH)
	t.ok(p.can_punch, "punch applies again")
	t.eq(p.trigger_bombs, 0, "taking punch drops the trigger stock")

	# A second trigger tops the stock up rather than replacing it.
	var s2 := _sim(1, 0)
	var p2: Player_ = s2.players[0]
	s2.give_powerup(p2, Types_.PowerUp.TRIGGER)
	var first := p2.trigger_bombs
	p2.collected[Types_.PowerUp.TRIGGER] = 0     # clear the cap to allow another
	s2.give_powerup(p2, Types_.PowerUp.TRIGGER)
	t.ok(p2.trigger_bombs > first, "a second trigger tops the stock up")


func _test_random(t: T_) -> void:
	# A random powerup must become some OTHER powerup, never itself, or a run
	# of them could recurse.
	var seen := {}
	for seed_value in 40:
		var sim := _sim(1, 0, seed_value)
		var p: Player_ = sim.players[0]
		sim.give_powerup(p, Types_.PowerUp.RANDOM)
		t.eq(p.collected[Types_.PowerUp.RANDOM], 0,
			"a random powerup never resolves to itself")
		for which in Const_.POWERUP_COUNT:
			if p.collected[which] > 0 or p.any_disease():
				seen[which] = true
	t.ok(seen.size() >= 3, "random resolves to a variety (%d kinds seen)" % seen.size())


func _test_diseases(t: T_) -> void:
	# The twelve names are the original's, from SOUNDLST.RES.
	t.eq(Types_.DISEASE_NAMES.size(), 12, "twelve diseases are named")
	t.eq(Types_.DISEASE_COUNT, 12, "and the count agrees")
	t.eq(Types_.DISEASE_NAMES[Types_.Disease.MOLASSES], "molasses",
		"disease 0 is molasses")
	t.eq(Types_.DISEASE_NAMES[Types_.Disease.DUDS], "duds", "disease 11 is duds")
	t.eq(Types_.disease_sound_base(Types_.Disease.CONSTIPATION), 3100,
		"constipation's sounds start at resource 3100")
	# The pools between them cover every disease exactly once.
	var pooled := {}
	for d in Types_.ORDINARY_DISEASES:
		pooled[d] = true
	for d in Types_.SUPER_BAD_DISEASES:
		t.ok(not pooled.has(d), "disease %d is in only one pool" % d)
		pooled[d] = true
	t.eq(pooled.size(), Types_.DISEASE_COUNT,
		"the two pools together cover all twelve")

	# Duration: 300 frames, which at 20 Hz is 15 seconds.
	var sim := _sim(1, 0)
	var p: Player_ = sim.players[0]
	t.ok(sim.catch_disease(p, Types_.Disease.CONSTIPATION), "a disease is caught")
	t.eq(p.disease_ticks[Types_.Disease.CONSTIPATION], 300,
		"it lasts 300 ticks, from VALUELST 130..138")
	t.eq(Const_.frames_to_ms(300), 15000, "which is 15 seconds")
	t.ok(not sim.catch_disease(p, Types_.Disease.CONSTIPATION),
		"catching the same disease twice does nothing")

	# It wears off exactly on schedule: VALUELST 121 says time-limited.
	t.eq(Values_.V[Const_.Res.DISEASE_TIME_LIMITED], 1,
		"diseases are time-limited")
	for _i in 299:
		sim.tick()
	t.ok(p.has_disease(Types_.Disease.CONSTIPATION), "still ill on tick 299")
	sim.tick()
	t.ok(not p.has_disease(Types_.Disease.CONSTIPATION), "cured on tick 300")
	t.ok(not p.any_disease(), "and clean")

	# Molasses slows and restores. Its restore must preserve skates collected
	# while slowed, which is why the speed is remembered rather than recomputed.
	var s2 := _sim(1, 0)
	var p2: Player_ = s2.players[0]
	var base := p2.speed
	s2.catch_disease(p2, Types_.Disease.MOLASSES)
	t.ok(p2.speed < base, "molasses slows the player")
	s2.cure_all(p2)
	t.eq(p2.speed, base, "and curing restores the speed")

	# Crack speeds up.
	var s3 := _sim(1, 0)
	var p3: Player_ = s3.players[0]
	var base3 := p3.speed
	s3.catch_disease(p3, Types_.Disease.CRACK)
	t.ok(p3.speed > base3, "crack speeds the player up")

	# Spreading: VALUELST 123 says a disease MULTIPLIES rather than hands off,
	# so the giver keeps it.
	t.eq(Values_.V[Const_.Res.DISEASE_MULTIPLIES], 1, "diseases multiply")
	var s4 := _sim(2, 0)
	var a: Player_ = s4.players[0]
	var b: Player_ = s4.players[1]
	s4.catch_disease(a, Types_.Disease.SHORT_FUZE)
	# The freshness lock blocks an immediate pass — resource 129, 10 frames.
	t.eq(Values_.V[Const_.Res.DISEASE_FRESHNESS], 10, "the lock is 10 frames")
	t.ok(not s4.spread_disease(a, b), "cannot pass it on the same tick")
	for _i in 10:
		s4.tick()
	t.ok(s4.spread_disease(a, b), "can pass it after the lock expires")
	t.ok(b.has_disease(Types_.Disease.SHORT_FUZE), "the other player catches it")
	t.ok(a.has_disease(Types_.Disease.SHORT_FUZE),
		"and the giver keeps it, because diseases multiply")

	# Curing on a fresh powerup: enabled by 124, 1-in-10 by 125.
	t.eq(Values_.V[Const_.Res.DISEASE_CURABLE], 1, "a powerup can cure")
	t.eq(Values_.V[Const_.Res.DISEASE_CURE_CHANCE], 10, "at 1-in-10")
	var cured := 0
	for seed_value in 200:
		var s5 := _sim(1, 0, seed_value)
		var p5: Player_ = s5.players[0]
		s5.catch_disease(p5, Types_.Disease.INVISIBLE)
		s5.give_powerup(p5, Types_.PowerUp.FLAME)
		if not p5.any_disease():
			cured += 1
	t.close(float(cured) / 200.0, 0.1, 0.06,
		"a powerup cures about 1 in 10 (%d of 200)" % cured)


# A dead player's powerups return to the field, but their diseases do not —
# VALUELST 122.
func _test_repopulate(t: T_) -> void:
	t.eq(Values_.V[Const_.Res.DISEASE_RECYCLES], 0, "diseases do not recycle")

	var sim := _sim(1, 0)
	var p: Player_ = sim.players[0]
	sim.give_powerup(p, Types_.PowerUp.KICK)
	sim.give_powerup(p, Types_.PowerUp.BOMB)
	sim.give_powerup(p, Types_.PowerUp.BOMB)
	# Taken as a POWERUP, not injected directly, so it is counted the way a
	# real pickup would be — which is the only way the "does not recycle" rule
	# has anything to act on. An earlier version of this test called
	# catch_disease() directly, left collected[DISEASE] at zero, and so could
	# not tell whether the rule was implemented at all.
	sim.give_powerup(p, Types_.PowerUp.DISEASE)
	t.eq(p.collected[Types_.PowerUp.DISEASE], 1, "the disease pickup is counted")

	var before := sim.field.count_powerups()
	var returned := sim.repopulate_powerups(p)
	t.eq(returned, 3, "three collected powerups come back, but not the disease")
	t.eq(sim.field.count_powerups(), before + 3, "and are on the field")
	t.eq(sim.field.count_powerups_of(Types_.PowerUp.KICK), 1, "the kicker returns")
	t.eq(sim.field.count_powerups_of(Types_.PowerUp.BOMB), 2, "both bombs return")
	t.eq(sim.field.count_powerups_of(Types_.PowerUp.DISEASE), 0,
		"the disease does not come back")
	t.eq(p.collected[Types_.PowerUp.KICK], 0, "the player's tally is cleared")


func _sim(count: int, density: int = 0, round_seed: int = 1,
		powerup_rows: Dictionary = {}) -> Sim_:
	var lines := PackedStringArray()
	lines.append("-V,2")
	lines.append("-N,Powerup fixture (10)")
	lines.append("-B,%d" % density)
	for y in Const_.FIELD_H:
		var ch := "." if density == 0 else ":"
		lines.append("-R,%2d,%s" % [y, ch.repeat(Const_.FIELD_W)])
	for p in Const_.PLAYER_COUNT:
		lines.append("-S,%d,%d,%d,%d" % [p, 1 + p, 1 + (p % 8), p % 2])
	for i in Const_.POWERUP_COUNT:
		var row: Dictionary = powerup_rows.get(i, {})
		lines.append("-P,%2d, %d,%d, %d, %d,x" % [i,
			row.get("born_with", 0),
			1 if row.get("has_override", false) else 0,
			row.get("override", 0),
			1 if row.get("forbidden", false) else 0])
	var s: Scheme_ = Scheme_.new()
	s.parse_text("\n".join(lines), "<powerups>")
	assert(s.ok(), "fixture must parse: %s" % s.error())

	var slots := []
	for i in count:
		slots.append({"slot": i, "team": i % 2})
	var sim: Sim_ = Sim_.new()
	sim.setup(s, slots, round_seed)
	return sim
