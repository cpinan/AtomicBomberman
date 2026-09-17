# The sound pack and the mixer.
#
# Two things are worth testing here and neither of them is "does audio come
# out", which no headless run can answer:
#
#   1. THE PACK IS COMPLETE. Every event the simulation can raise has at least
#      one playable take. A missing one is silence at runtime with nothing in
#      the log to connect it to, which is the worst kind of bug to ship.
#
#   2. THE MIXER'S RULES HOLD, and they are the BINARY's rules now rather than
#      this port's guesses. `BM95.EXE` 0x427961 and 0x427859 say: every raised
#      sound is played, the take is random among the LEAST-USED, and a full
#      mixer drops the NEW sound. All three of those replaced an invented rule
#      that this file used to pin — see docs/BUGS.md Q8 and D23.
#
# The mixer runs in `silent` mode: no AudioStreamPlayer is built and no device
# is touched, but the voice bookkeeping is the same code the audible path uses.
extends SceneTree

const T_ := preload("res://tests/t.gd")
const Const_ := preload("res://scripts/core/const.gd")
const Types_ := preload("res://scripts/core/types.gd")
const Values_ := preload("res://scripts/core/values.gd")
const SoundPack_ := preload("res://scripts/audio/sound_pack.gd")
const Sfx_ := preload("res://scripts/audio/sfx.gd")


func _init() -> void:
	var t := T_.new("sfx")
	_test_event_table(t)
	_test_voice_count(t)

	var pack: SoundPack_ = SoundPack_.new()
	if not pack.load_from(SoundPack_.default_dir()):
		t.note("no sound pack: %s" % pack.error)
		t.note("run tools/rss.py --pack (needs the original game data)")
		quit(t.finish())
		return

	_test_pack_complete(t, pack)
	_test_least_used_selection(t, pack)
	_test_streams(t, pack)
	_test_every_event_is_played(t, pack)
	_test_a_full_mixer_drops_the_new_sound(t, pack)
	_test_disease_events(t, pack)
	quit(t.finish())


# The mapping is a table, so a new SoundEffect without a sound is a test
# failure rather than silence.
func _test_event_table(t: T_) -> void:
	var missing: Array[String] = []
	for effect in Types_.SoundEffect.values():
		if effect == Types_.SoundEffect.NONE:
			continue
		if not Types_.SOUND_EVENT.has(effect):
			missing.append(str(effect))
	t.eq(missing.size(), 0,
		"every SoundEffect maps to a pack event (unmapped: %s)"
			% ", ".join(missing))
	t.eq(Types_.SOUND_EVENT.size(), Types_.SoundEffect.size() - 1,
		"and nothing but NONE is left out")

	# Distinct names: two effects sharing an event would be a copy-paste slip
	# that nothing else would catch.
	var seen := {}
	for effect in Types_.SOUND_EVENT:
		var name: String = Types_.SOUND_EVENT[effect]
		t.ok(not seen.has(name), "event name %s is used once" % name)
		seen[name] = true


func _test_voice_count(t: T_) -> void:
	t.eq(Values_.V[Const_.Res.CONCURRENT_SOUNDS], 5,
		"resource 8 allows five concurrent sounds")
	var sfx: Sfx_ = Sfx_.new()
	t.eq(sfx.concurrent_cap(), 5, "the cap is resource 8")
	# SIX voices for a cap of five. The original's admission test is
	# `if (cap < live) return;`, which admits while live <= 5 and therefore
	# lets six be live at once. BM95.EXE 0x427859. Sizing the array at five
	# would drop a sound the original plays.
	t.eq(sfx.voice_count(), 6,
		"and the mixer has cap + 1 voices, as the original's test allows")
	sfx.free()


func _test_pack_complete(t: T_, pack: SoundPack_) -> void:
	t.ok(pack.loaded, "the sound pack loads")
	t.eq(pack.sample_rate, 22050,
		"at the 22050 Hz SOUNDLST's header states")

	var missing: Array[String] = []
	for name in Sfx_.required_events():
		if not pack.has_event(name):
			missing.append(name)
	t.eq(missing.size(), 0,
		"the pack has every event the sim can raise (missing: %s)"
			% ", ".join(missing))

	# Nothing may be an empty list either: load_from() rejects that, so this
	# asserts the rejection is real rather than trusting it.
	for name in Sfx_.required_events():
		if pack.has_event(name):
			t.ok(pack.take_count(name) >= 1,
				"event %s has at least one take" % name)

	t.note("%d events, %d takes"
		% [pack.event_names().size(), _total_takes(pack)])


func _total_takes(pack: SoundPack_) -> int:
	var n := 0
	for name in pack.event_names():
		n += pack.take_count(name)
	return n


# Alternative takes exist so a repeated action does not sound identical, and
# the original's rule for that is a shuffled deck: random among the takes
# played fewest times. So over one full cycle every take is heard exactly once,
# in an order that is not fixed.
func _test_least_used_selection(t: T_, pack: SoundPack_) -> void:
	var multi := ""
	for name in pack.event_names():
		if pack.take_count(name) >= 4:
			multi = name
			break
	t.ok(not multi.is_empty(), "some event has four or more takes")
	if multi.is_empty():
		return

	var sfx := _mixer(pack)
	sfx.rng.seed = 12345
	var count := pack.take_count(multi)

	# One full cycle: every take exactly once, none twice.
	var order: Array[String] = []
	for i in count:
		var index: int = sfx.pick_take(multi)
		var take: String = pack.take_at(multi, index)
		t.ok(not order.has(take),
			"%s take %s is not repeated inside one cycle" % [multi, take])
		order.append(take)
		sfx._uses[take] = sfx.uses_of(take) + 1
	t.eq(order.size(), count,
		"%s: all %d takes are used before any repeats" % [multi, count])

	# A second cycle also covers everything, which is what makes it a deck
	# rather than a fixed rotation.
	var second: Array[String] = []
	for i in count:
		var index: int = sfx.pick_take(multi)
		var take: String = pack.take_at(multi, index)
		second.append(take)
		sfx._uses[take] = sfx.uses_of(take) + 1
	t.eq(second.size(), count, "and the second cycle is a cycle too")
	var distinct := {}
	for take in second:
		distinct[take] = true
	t.eq(distinct.size(), count, "covering every take again")

	# And the order is NOT the same both times — that is the difference from
	# the round-robin this used to do. Tried over several seeds, because one
	# seed could coincide.
	var same := 0
	for attempt in 8:
		var probe := _mixer(pack)
		probe.rng.seed = 1000 + attempt
		var seq: Array[String] = []
		for i in count:
			var index: int = probe.pick_take(multi)
			var take: String = pack.take_at(multi, index)
			seq.append(take)
			probe._uses[take] = probe.uses_of(take) + 1
		if seq == order:
			same += 1
		probe.free()
	t.ok(same < 8, "the order differs between seeds (%d of 8 matched)" % same)
	sfx.free()


func _test_streams(t: T_, pack: SoundPack_) -> void:
	var checked := 0
	for name in pack.event_names():
		var stream := pack.stream_for(name, 0)
		if stream == null:
			t.ok(false, "event %s built no stream" % name)
			continue
		t.eq(stream.mix_rate, 22050, "%s plays at 22050 Hz" % name)
		t.eq(stream.format, AudioStreamWAV.FORMAT_16_BITS,
			"%s is 16-bit" % name)
		t.ok(stream.get_length() > 0.0, "%s has a length" % name)
		t.ok(stream.get_length() < 20.0,
			"%s is a sound effect, not a track (%.1f s)"
				% [name, stream.get_length()])
		checked += 1
	t.ok(checked >= 30, "checked %d streams" % checked)

	# The same take asked for twice is the same object: a browser must not
	# decode 6 MB of audio again on every explosion.
	var again := pack.stream_for("bomb_explode", 0)
	t.ok(again == pack.stream_for("bomb_explode", 0),
		"a stream is built once and cached")


# Every raised sound is played, up to the cap. A chain reaction raises
# BOMB_EXPLODE once per bomb on one tick, and the original plays each of them —
# with a different take each time, because of the least-used rule. This file
# used to assert the opposite: that the batch collapsed to one sound.
func _test_every_event_is_played(t: T_, pack: SoundPack_) -> void:
	var sfx := _mixer(pack)
	sfx.rng.seed = 7

	var chain: Array = []
	for i in 8:
		chain.append({"slot": i % 4,
			"effect": Types_.SoundEffect.BOMB_EXPLODE, "arg": 0})
	var played := sfx.play_batch(chain, 100)
	t.eq(played, sfx.voice_count(),
		"eight bombs on one tick play %d sounds — every voice, and no more"
			% sfx.voice_count())
	t.eq(sfx.log.size(), played, "one log entry each")

	# And they are DIFFERENT takes, which is the point: eight copies of one
	# file 0 ms apart would be one explosion eight times as loud.
	var takes := {}
	for entry in sfx.log:
		takes[entry["take"]] = true
	# As many distinct takes as the pack has, up to the number played: the
	# least-used rule cannot invent a seventh take of a five-take event, and
	# the budget in tools/rss.py decides how many there are.
	var available: int = pack.take_count("bomb_explode")
	t.eq(takes.size(), mini(available, played),
		"and every one is a different take (%d distinct from %d takes, %d played)"
			% [takes.size(), available, played])

	# The two that did not fit are recorded rather than lost.
	t.eq(int(sfx.dropped.get("bomb_explode", 0)), 8 - played,
		"the %d that did not fit are counted" % (8 - played))
	sfx.free()

	# Different events on the same tick are of course also all played.
	var mixed := _mixer(pack)
	t.eq(mixed.play_batch([
		{"slot": 0, "effect": Types_.SoundEffect.BOMB_EXPLODE, "arg": 0},
		{"slot": 1, "effect": Types_.SoundEffect.PLAYER_DIED, "arg": 0},
		{"slot": 1, "effect": Types_.SoundEffect.DEATH_TAUNT, "arg": 0},
	], 200), 3, "three different events on one tick are three sounds")

	# An unmapped effect is silence, not a crash.
	t.eq(mixed.play_batch([{"slot": 0, "effect": 250, "arg": 0}], 300), 0,
		"an effect the table does not know plays nothing")
	t.eq(mixed.play_batch([{"slot": 0,
		"effect": Types_.SoundEffect.NONE, "arg": 0}], 301), 0,
		"and neither does NONE")
	mixed.free()


# A full mixer drops the NEW sound. BM95.EXE 0x427859:
#
#     cmp eax, [live] ; jl exit
#
# so a sound is admitted while `live <= cap` and refused otherwise. This file
# used to assert that the new sound took the oldest voice, which is what the
# port did before the binary was available.
func _test_a_full_mixer_drops_the_new_sound(t: T_, pack: SoundPack_) -> void:
	var sfx := _mixer(pack)
	var effects := [Types_.SoundEffect.BOMB_DROP, Types_.SoundEffect.BOMB_KICK,
		Types_.SoundEffect.BOMB_STOP, Types_.SoundEffect.BOMB_BOUNCE,
		Types_.SoundEffect.WARP, Types_.SoundEffect.TRAMPOLINE,
		Types_.SoundEffect.BOMB_GRAB, Types_.SoundEffect.BOMB_PUNCH]
	var names := ["bomb_drop", "bomb_kick", "bomb_stop", "bomb_bounce",
		"warp", "trampoline", "bomb_grab", "bomb_punch"]

	# All on the SAME tick. Spread over successive ticks the short ones start
	# expiring — a bomb drop is about six ticks long — and a seventh would be
	# admitted quite correctly, which measures the voice lifetime rather than
	# the cap.
	var admitted := 0
	for i in effects.size():
		var got := sfx.play_batch([{"slot": 0, "effect": effects[i],
			"arg": 0}], 0)
		admitted += got
		if got == 0:
			t.eq(int(sfx.dropped.get(names[i], 0)), 1,
				"%s was refused and said so" % names[i])
	t.eq(admitted, sfx.voice_count(),
		"%d of %d sounds on one tick were admitted" % [admitted,
			effects.size()])
	t.eq(sfx.busy_at(0), sfx.voice_count(),
		"every voice is busy and none was stolen")

	# The FIRST sound is still playing — nothing evicted it.
	var first_voice: Dictionary = {}
	for entry in sfx.log:
		if String(entry["event"]) == "bomb_drop":
			first_voice = entry
	t.ok(not first_voice.is_empty(), "the first sound got a voice")
	t.eq(int(sfx.log[0]["voice"]), 0, "the first sound took voice 0")
	t.ok(int(sfx.log[sfx.log.size() - 1]["voice"]) != 0,
		"and the last one did not take it back")

	# Once the streams have run out, a sound is admitted again — which is also
	# why the loop above uses one tick rather than eight.
	var far := 10000
	t.eq(sfx.busy_at(far), 0, "every voice is free again later on")
	t.eq(sfx.play_batch([{"slot": 0, "effect": effects[0], "arg": 0}],
		far), 1, "so a sound then finds one")
	sfx.free()


# A disease names WHICH disease, because SOUNDLST has twelve ranges for them.
func _test_disease_events(t: T_, pack: SoundPack_) -> void:
	for i in Types_.DISEASE_COUNT:
		var e := {"slot": 1, "effect": Types_.SoundEffect.DISEASE_CAUGHT,
			"arg": i}
		t.eq(Sfx_.event_of(e), "disease_%d" % i,
			"disease %d (%s) has its own event"
				% [i, Types_.DISEASE_NAMES[i]])
		t.ok(pack.has_event(Sfx_.event_of(e)),
			"and the pack carries it")

	# Out of range falls back to the generic sound rather than going silent.
	t.eq(Sfx_.event_of({"slot": 1,
		"effect": Types_.SoundEffect.DISEASE_CAUGHT, "arg": 99}), "disease",
		"an unknown disease falls back to the generic sound")
	t.ok(pack.has_event("disease"), "which the pack also carries")

	# Two diseases caught on one tick are two sounds, because they are two
	# events — this is what deduplicating by EVENT rather than by EFFECT buys.
	var sfx := _mixer(pack)
	t.eq(sfx.play_batch([
		{"slot": 0, "effect": Types_.SoundEffect.DISEASE_CAUGHT, "arg": 0},
		{"slot": 1, "effect": Types_.SoundEffect.DISEASE_CAUGHT, "arg": 5},
	], 400), 2, "molasses and crack poops on one tick are two sounds")
	# Two players catching the SAME disease is two sounds, and two different
	# takes of it — the original collapses nothing.
	sfx.log.clear()
	t.eq(sfx.play_batch([
		{"slot": 0, "effect": Types_.SoundEffect.DISEASE_CAUGHT, "arg": 3},
		{"slot": 1, "effect": Types_.SoundEffect.DISEASE_CAUGHT, "arg": 3},
	], 500), 2, "two players catching the SAME disease is two sounds")
	if pack.take_count("disease_3") >= 2:
		t.ok(String(sfx.log[0]["take"]) != String(sfx.log[1]["take"]),
			"and two different takes of it")
	sfx.free()


func _mixer(pack: SoundPack_) -> Sfx_:
	var sfx: Sfx_ = Sfx_.new()
	sfx.silent = true
	sfx.pack = pack
	return sfx
