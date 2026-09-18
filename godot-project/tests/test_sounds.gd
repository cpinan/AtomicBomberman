# What the simulation announces, and when.
#
# A sound event is the only thing the simulation says about itself that is not
# state, so nothing else in the test suite covers it: a missing event does not
# change a hash, does not fail a snapshot round-trip, and does not show up in a
# screenshot. It is silence, and silence looks exactly like a working game.
#
# So every event the sim can raise is provoked here from a real round.
extends SceneTree

const T_ := preload("res://tests/t.gd")
const Const_ := preload("res://scripts/core/const.gd")
const Types_ := preload("res://scripts/core/types.gd")
const Values_ := preload("res://scripts/core/values.gd")
const Scheme_ := preload("res://scripts/core/scheme.gd")
const Field_ := preload("res://scripts/sim/field.gd")
const Sim_ := preload("res://scripts/sim/sim.gd")
const Bomb_ := preload("res://scripts/sim/bomb.gd")
const Player_ := preload("res://scripts/sim/player.gd")


func _init() -> void:
	var t := T_.new("sounds")
	_test_cleared_every_tick(t)
	_test_bomb_and_explosion(t)
	_test_powerups(t)
	_test_awesome(t)
	_test_disease_names_itself(t)
	_test_death(t)
	_test_round_end(t)
	_test_solid_drop(t)
	_test_every_effect_reachable(t)
	quit(t.finish())


# A sound is not state: a client that missed one has missed it. That is only
# true if the list is emptied every tick, or a late-joining client would hear
# the whole round at once.
func _test_cleared_every_tick(t: T_) -> void:
	var sim := _sim(2)
	var p: Player_ = sim.players[0]
	sim.set_input(0, Types_.MoveState.STILL, Types_.Action.FIRST)
	sim.tick()
	t.ok(_heard(sim, Types_.SoundEffect.BOMB_DROP),
		"dropping a bomb is announced")
	sim.tick()
	t.eq(sim.sounds.size(), 0, "and the list is empty on the next tick")
	t.ok(p.bombs_available < p.bombs_total, "the bomb is really there")

	# Every event carries the three fields the wire expects.
	sim.set_input(0, Types_.MoveState.STILL, Types_.Action.FIRST)
	sim.tick()
	for e in sim.sounds:
		t.ok(e.has("slot") and e.has("effect") and e.has("arg"),
			"an event carries slot, effect and arg")
		t.ok(int(e["effect"]) > 0, "and is never NONE")


func _test_bomb_and_explosion(t: T_) -> void:
	var sim := _sim(2)
	# Out of its own blast, so the round does not end mid-test.
	sim.players[0].place_at_tile_centre(1, 1)
	sim.players[1].place_at_tile_centre(13, 9)
	sim.set_input(0, Types_.MoveState.STILL, Types_.Action.FIRST)
	sim.tick()
	sim.players[0].place_at_tile_centre(7, 5)

	var explosions := 0
	for _i in Values_.V[Const_.Res.FUZE_FRAMES] + 4:
		sim.tick()
		explosions += _count(sim, Types_.SoundEffect.BOMB_EXPLODE)
	t.eq(explosions, 1, "a bomb going off is announced exactly once")

	# A chain raises one per bomb. The MIXER collapses them — see
	# tests/test_sfx.gd — but the simulation must still report each, because
	# the netcode carries the count and a chain of one is not a chain of three.
	var chain := _sim(2)
	chain.players[0].place_at_tile_centre(1, 1)
	chain.players[1].place_at_tile_centre(13, 9)
	for x in [5, 6, 7]:
		var b: Bomb_ = Bomb_.new()
		b.place_at_tile_centre(x, 5)
		b.owner = 0
		b.chain_owner = 0
		b.fuze = 3 if x == 5 else 900
		b.placed_tick = 0
		b.flame_len = 3
		chain.bombs.append(b)
	var chained := 0
	for _i in 8:
		chain.tick()
		chained += _count(chain, Types_.SoundEffect.BOMB_EXPLODE)
	t.eq(chained, 3, "a three-bomb chain raises three explosions")


func _test_powerups(t: T_) -> void:
	# A good one.
	var sim := _sim(2)
	var p: Player_ = sim.players[0]
	sim.field.powerup[Field_.idx(p.tile_x(), p.tile_y())] = Types_.PowerUp.BOMB
	sim.tick()
	t.ok(_heard(sim, Types_.SoundEffect.GET_GOOD_POWERUP),
		"picking up a bomb is a good-powerup sound")
	t.ok(not _heard(sim, Types_.SoundEffect.GET_BAD_POWERUP),
		"and not a bad one")
	t.eq(p.pickups, 1, "and it counts as a pickup")

	# A bad one. SOUNDLST keeps the two apart — 400 "you get a powerup (a good
	# one)" against 550's "ploppy poop sounds".
	var bad := _sim(2)
	var q: Player_ = bad.players[0]
	bad.field.powerup[Field_.idx(q.tile_x(), q.tile_y())] = \
		Types_.PowerUp.DISEASE
	bad.tick()
	t.ok(_heard(bad, Types_.SoundEffect.GET_BAD_POWERUP),
		"picking up a disease is a bad-powerup sound")
	t.ok(not _heard(bad, Types_.SoundEffect.GET_GOOD_POWERUP),
		"and not a good one")
	t.ok(_heard(bad, Types_.SoundEffect.DISEASE_CAUGHT),
		"and the disease announces itself as well")

	# The super-bad one is also bad, which a naive `which == DISEASE` test
	# would miss.
	var worse := _sim(2)
	var r: Player_ = worse.players[0]
	worse.field.powerup[Field_.idx(r.tile_x(), r.tile_y())] = \
		Types_.PowerUp.SUPER_BAD_DISEASE
	worse.tick()
	t.ok(_heard(worse, Types_.SoundEffect.GET_BAD_POWERUP),
		"so is a super bad disease")


# "you are now AWESOME (7th powerup and 3rd thereafter)" — SOUNDLST's own
# description of its 1400..1699 range.
func _test_awesome(t: T_) -> void:
	var sim := _sim(2)
	var p: Player_ = sim.players[0]
	# Flame rather than bomb: resource 550's cap on bombs would stop the count
	# before it reached ten, and a capped powerup is still a pickup.
	var expected := [7, 10, 13]
	var heard: Array[int] = []
	for n in range(1, 15):
		sim.field.powerup[Field_.idx(p.tile_x(), p.tile_y())] = \
			Types_.PowerUp.FLAME
		sim.tick()
		if _heard(sim, Types_.SoundEffect.AWESOME):
			heard.append(p.pickups)
	t.eq(p.pickups, 14, "fourteen powerups were picked up")
	t.eq(heard, expected,
		"AWESOME fires on the 7th, 10th and 13th — got %s" % str(heard))


func _test_disease_names_itself(t: T_) -> void:
	for d in Types_.DISEASE_COUNT:
		var sim := _sim(2)
		var p: Player_ = sim.players[0]
		t.ok(sim.catch_disease(p, d),
			"%s can be caught" % Types_.DISEASE_NAMES[d])
		var found := -1
		for e in sim.sounds:
			if int(e["effect"]) == Types_.SoundEffect.DISEASE_CAUGHT:
				found = int(e["arg"])
		t.eq(found, d, "and names itself: %s" % Types_.DISEASE_NAMES[d])

		# Catching the same one again changes nothing, so it says nothing.
		sim.sounds.clear()
		t.ok(not sim.catch_disease(p, d), "catching it twice does nothing")
		t.eq(sim.sounds.size(), 0, "and is silent")


func _test_death(t: T_) -> void:
	var sim := _sim(3)
	var victim: Player_ = sim.players[1]
	sim.kill(victim, 0)
	t.ok(_heard(sim, Types_.SoundEffect.PLAYER_DIED),
		"a death is announced")
	t.ok(_heard(sim, Types_.SoundEffect.DEATH_TAUNT),
		"and the taunt that follows it")
	# SOUNDLST 341 "burnedup" — docs/BUGS.md D29: not a 9-sound mapping
	# across 24 animations, one sound on every death.
	t.ok(_heard(sim, Types_.SoundEffect.DEATH_CLUNK),
		"and the clunk that syncs with the animation")

	# The taunt belongs to the KILLER, so the two events differ in slot: the
	# scream is the victim's and the gloating is not.
	var scream := -2
	var taunt := -2
	for e in sim.sounds:
		if int(e["effect"]) == Types_.SoundEffect.PLAYER_DIED:
			scream = int(e["slot"])
		elif int(e["effect"]) == Types_.SoundEffect.DEATH_TAUNT:
			taunt = int(e["slot"])
	t.eq(scream, 1, "the scream is the victim's")
	t.eq(taunt, 0, "the taunt is the killer's")

	# Killing an already-dying player says nothing more.
	sim.sounds.clear()
	sim.kill(victim, 0)
	t.eq(sim.sounds.size(), 0, "a second kill on a dying player is silent")


func _test_round_end(t: T_) -> void:
	# LAST_STANDING.
	var sim := _sim(2)
	sim.kill(sim.players[1], 0)
	var win := 0
	for _i in 40:
		sim.tick()
		win += _count(sim, Types_.SoundEffect.ROUND_WIN)
	t.eq(sim.outcome, Sim_.Outcome.LAST_STANDING, "the round was won")
	t.eq(win, 1, "and the win is announced once, not once per tick")

	# TIME_UP is nobody's win, so it is the draw sound.
	var out_of_time := _sim(2)
	out_of_time.time_left = 1
	var draws := 0
	for _i in 40:
		out_of_time.tick()
		draws += _count(out_of_time, Types_.SoundEffect.DRAW)
	t.eq(out_of_time.outcome, Sim_.Outcome.TIME_UP, "the clock ran out")
	t.eq(draws, 1, "and the draw is announced once")
	t.eq(_count(out_of_time, Types_.SoundEffect.ROUND_WIN), 0,
		"with no winner announced")


func _test_solid_drop(t: T_) -> void:
	var sim := _sim(2)
	sim.players[0].place_at_tile_centre(7, 5)
	sim.players[1].place_at_tile_centre(7, 3)
	sim.time_left = Values_.V[Const_.Res.HURRY_AT_SECONDS] * Const_.TICK_HZ + 1

	var solids := 0
	var hurries := 0
	for _i in 200:
		sim.tick()
		solids += _count(sim, Types_.SoundEffect.SOLID_DROP)
		hurries += _count(sim, Types_.SoundEffect.HURRY)
	t.eq(hurries, 1, "Hurry announces itself once")
	t.ok(solids > 0, "and every tile the wall slams down is announced")
	t.note("%d solids dropped in 200 ticks" % solids)

	# One per cell, not one per tick: the wall moves every 8 ticks.
	t.ok(solids <= 200 / 8 + 1,
		"at most one solid per 8 ticks, got %d" % solids)


# Every effect in the enum has to be reachable from somewhere, or it is a
# sound the pack carries and the game never plays. MATCH_WIN is raised by the
# match rather than the sim, so it is named here and asserted in main's path.
func _test_every_effect_reachable(t: T_) -> void:
	var raised_by_sim := [
		Types_.SoundEffect.BOMB_DROP, Types_.SoundEffect.BOMB_KICK,
		Types_.SoundEffect.BOMB_STOP, Types_.SoundEffect.BOMB_BOUNCE,
		Types_.SoundEffect.BOMB_GRAB, Types_.SoundEffect.BOMB_PUNCH,
		Types_.SoundEffect.BOMB_EXPLODE, Types_.SoundEffect.PLAYER_DIED,
		Types_.SoundEffect.GET_GOOD_POWERUP,
		Types_.SoundEffect.GET_BAD_POWERUP, Types_.SoundEffect.HURRY,
		Types_.SoundEffect.WARP, Types_.SoundEffect.TRAMPOLINE,
		Types_.SoundEffect.BOMB_THROWN, Types_.SoundEffect.BOMB_HIT_HEAD,
		Types_.SoundEffect.SOLID_DROP,
		Types_.SoundEffect.DISEASE_CAUGHT, Types_.SoundEffect.SPOOGE,
		Types_.SoundEffect.AWESOME, Types_.SoundEffect.DEATH_TAUNT,
		Types_.SoundEffect.ROUND_WIN, Types_.SoundEffect.DRAW,
		Types_.SoundEffect.DEATH_CLUNK,
	]
	var source := FileAccess.get_file_as_string("res://scripts/sim/sim.gd")
	for effect in raised_by_sim:
		var name: String = Types_.SoundEffect.find_key(effect)
		t.ok(source.contains("SoundEffect.%s" % name),
			"sim.gd raises %s somewhere" % name)

	# What the SIM does not raise, the app does: the match's own win sound and
	# the three the Goldman wheel makes. Listed rather than counted, so adding
	# an effect and forgetting to raise it anywhere fails here.
	var raised_by_main := [
		Types_.SoundEffect.MATCH_WIN, Types_.SoundEffect.ROULETTE_TICK,
		Types_.SoundEffect.ROULETTE_CLAP, Types_.SoundEffect.ROULETTE_BUZZ,
	]
	t.eq(raised_by_sim.size() + raised_by_main.size(),
		Types_.SoundEffect.size() - 1,
		"every effect but NONE is raised somewhere")
	var main := FileAccess.get_file_as_string("res://scripts/app/main.gd")
	for effect in raised_by_main:
		var name2: String = Types_.SoundEffect.find_key(effect)
		t.ok(main.contains("SoundEffect.%s" % name2),
			"main.gd raises %s" % name2)


# ---------------------------------------------------------------------------
func _heard(sim: Sim_, effect: int) -> bool:
	return _count(sim, effect) > 0


func _count(sim: Sim_, effect: int) -> int:
	var n := 0
	for e in sim.sounds:
		if int(e["effect"]) == effect:
			n += 1
	return n


func _sim(count: int, round_seed: int = 1) -> Sim_:
	var lines := PackedStringArray()
	lines.append("-V,2")
	lines.append("-N,Sound fixture (10)")
	lines.append("-B,0")
	for y in Const_.FIELD_H:
		lines.append("-R,%2d,%s" % [y, ".".repeat(Const_.FIELD_W)])
	for p in Const_.PLAYER_COUNT:
		lines.append("-S,%d,%d,%d,%d" % [p, 1 + p, 1 + (p % 8), p % 2])
	for i in Const_.POWERUP_COUNT:
		lines.append("-P,%2d, 0,0, 0, 0,x" % i)
	var s: Scheme_ = Scheme_.new()
	s.parse_text("\n".join(lines), "<sounds>")
	assert(s.ok(), "fixture must parse: %s" % s.error())

	var slots := []
	for i in count:
		slots.append({"slot": i, "team": i % 2})
	var sim: Sim_ = Sim_.new()
	sim.setup(s, slots, round_seed)
	return sim
