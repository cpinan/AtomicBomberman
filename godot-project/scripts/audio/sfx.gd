# The mixer. Turns the simulation's sound events into audible ones.
#
# ---------------------------------------------------------------------------
# HOW MANY AT ONCE
# ---------------------------------------------------------------------------
# VALUELST resource 8, with the disc's own question above it:
#
#     ; how many concurrent sounds do we want to allow?
#     8,5
#
# So five. That is a small number and it bites constantly — a four-bomb chain
# reaction alone would ask for more — which is why the two rules below exist.
#
# ---------------------------------------------------------------------------
# THE RULES ARE THE BINARY'S. BOTH GUESSES WERE WRONG.
# ---------------------------------------------------------------------------
# This file used to carry two invented rules, recorded as guesses in
# docs/BUGS.md Q8 because BM.EXE was absent. `BM95.EXE` arrived and refuted
# both of them. What it does, from `play_sound` at 0x427961 and the gate at
# 0x427859:
#
# EVERY RAISED SOUND IS PLAYED. There is no per-tick collapsing. A chain of
# eight bombs asks eight times, and because of the rule below it gets eight
# DIFFERENT explosion takes — which is a better answer than the one this file
# used to give, where a chain cost one voice and sounded like a single bomb.
#
# THE TAKE IS RANDOM AMONG THE LEAST-USED. Per-take counters, and:
#
#     best = min(uses[n .. n+count-1])
#     for (200 tries) { pick = n + rand() % count; if uses[pick] == best break }
#     ... play names[pick] ... uses[pick]++
#
# So it is a shuffled deck: every take is heard once before any repeats, and
# within the tied set the choice is random. Round-robin — what this file did —
# gets the first half right and the second wrong.
#
# The counter is incremented even when the sound is refused for want of a
# voice, which is the original's behaviour and is reproduced here.
#
# A FULL MIXER DROPS THE NEW SOUND. 0x427859, in full:
#
#     mov eax, 8 ; call value_of      ; the cap, 5
#     cmp eax, [0x46307C]             ; against the live count
#     jl  exit                        ; cap < live -> play nothing at all
#     ... start it ...
#     inc dword [0x46307C]
#
# Not "evict the oldest", which is what this file used to do. Note the
# comparison: it admits a new sound while `live <= cap`, so with resource 8 at
# 5 there can be SIX live at once. That is the original's own off-by-one and it
# is reproduced rather than tidied.
#
# ---------------------------------------------------------------------------
# TESTABILITY
# ---------------------------------------------------------------------------
# `silent` builds no AudioStreamPlayers and asserts nothing about an audio
# device, but every other rule above still runs and is recorded in `log`. That
# is what tests/test_sfx.gd measures. A voice is busy until the tick its stream
# would end on, in BOTH modes, so the headless measurement is of the same
# bookkeeping the audible one uses.
#
# The take choice uses this object's own RandomNumberGenerator, never the
# simulation's: a sound is not state, and a client that picked a different take
# from the server must not diverge. `rng.seed` is settable so a test can pin
# the sequence.
extends Node

const Const_ := preload("res://scripts/core/const.gd")
const Types_ := preload("res://scripts/core/types.gd")
const Values_ := preload("res://scripts/core/values.gd")
const SoundPack_ := preload("res://scripts/audio/sound_pack.gd")

var pack: SoundPack_ = null

## No audio device is touched. Set before the first play_batch().
var silent: bool = false

## What was played, as {"tick", "event", "take", "voice"}. Bounded, because a
## long game must not turn this into a leak.
var log: Array[Dictionary] = []
const LOG_LIMIT := 256

## Events asked for and not played, by event name. A number here means the
## mixer is saturated and the player is missing sounds, which is worth being
## able to see rather than guess at.
var dropped: Dictionary = {}

var _voices: Array[Dictionary] = []

## take name -> how many times it has been played. The original's own
## per-sound counters, at [0x463088] in the binary.
var _uses: Dictionary = {}

## Presentation randomness, deliberately not the simulation's.
var rng := RandomNumberGenerator.new()

var _tick: int = 0

## How many attempts the original makes to land on a least-used take before
## giving up and playing whatever it last picked. 0xC8 at 0x427A4B.
const PICK_TRIES := 200


func _init() -> void:
	# cap + 1 voices, because the original's admission test lets `live` reach
	# cap + 1 — see the header. Sizing this at `cap` would drop a sound the
	# original plays.
	var count: int = maxi(1, int(Values_.V[Const_.Res.CONCURRENT_SOUNDS])) + 1
	for i in count:
		_voices.append({"player": null, "started": -1, "until": -1,
			"event": ""})


## The value of resource 8: how many sounds may already be playing for another
## to be admitted.
func concurrent_cap() -> int:
	return int(Values_.V[Const_.Res.CONCURRENT_SOUNDS])


func voice_count() -> int:
	return _voices.size()


## Load the sound pack. Not fatal if it fails: the game is playable silent, and
## saying so beats refusing to start.
func load_pack(dir_path: String = "") -> bool:
	pack = SoundPack_.new()
	var where := dir_path if not dir_path.is_empty() else SoundPack_.default_dir()
	if not pack.load_from(where):
		push_warning(pack.error)
		return false
	return true


func ready_to_play() -> bool:
	return pack != null and pack.loaded


## Every event name the simulation can raise, whether or not the pack has it.
## Used by tests to prove a new SoundEffect cannot be added without a sound.
static func required_events() -> Array[String]:
	var out: Array[String] = []
	for effect in Types_.SOUND_EVENT:
		out.append(String(Types_.SOUND_EVENT[effect]))
	for i in Types_.DISEASE_COUNT:
		out.append(Types_.disease_event(i))
	return out


## The pack event one raised sound maps to. Diseases are per-disease, so the
## event depends on the argument and not only on the effect.
static func event_of(e: Dictionary) -> String:
	var effect := int(e.get("effect", Types_.SoundEffect.NONE))
	if effect == Types_.SoundEffect.DISEASE_CAUGHT:
		var which := int(e.get("arg", -1))
		if which >= 0 and which < Types_.DISEASE_COUNT:
			return Types_.disease_event(which)
	return String(Types_.SOUND_EVENT.get(effect, ""))


## Play one tick's worth of events. `at_tick` is the simulation's own tick, so
## the mixer's clock is the game's and not the frame rate's.
func play_batch(events: Array, at_tick: int) -> int:
	_tick = at_tick
	if not ready_to_play():
		return 0

	# EVERY event, in the order raised. No collapsing — see the header: the
	# original plays each one and the least-used rule makes a chain of eight
	# bombs eight different explosions rather than one eight times over.
	var played := 0
	for e in events:
		var name := event_of(e)
		if name.is_empty() or not pack.has_event(name):
			continue
		if _play_one(name, at_tick):
			played += 1
	return played


## Which take to play: random among the least-used, the original's rule.
##
## Returns the index within the event's take list. The counter is bumped by the
## caller, and bumped even when no voice is free, which is what the binary does.
func pick_take(event: String) -> int:
	var takes: Array = pack.takes(event)
	if takes.is_empty():
		return -1
	var best := 0x7FFFFFFF
	for take in takes:
		best = mini(best, int(_uses.get(take, 0)))
	# Random among the takes tied at that count. The 200 attempts are the
	# original's; it is a rejection sampler, and with every take tied — which
	# is the state at the start of a round — the first attempt always succeeds.
	var index := 0
	for _try in PICK_TRIES:
		index = rng.randi() % takes.size()
		if int(_uses.get(takes[index], 0)) == best:
			break
	return index


func _play_one(event: String, at_tick: int) -> bool:
	var index := pick_take(event)
	if index < 0:
		dropped[event] = int(dropped.get(event, 0)) + 1
		return false
	var take: String = pack.take_at(event, index)
	# Counted here, before the voice test, because the original counts a sound
	# it could not play: `uses[pick]++` sits after the gate at 0x427859 and is
	# not conditional on it.
	_uses[take] = int(_uses.get(take, 0)) + 1

	var stream := pack.stream(take)
	if stream == null:
		dropped[event] = int(dropped.get(event, 0)) + 1
		return false

	# The gate, exactly: admit while the live count is no greater than the cap.
	var live := busy_at(at_tick)
	if concurrent_cap() < live:
		dropped[event] = int(dropped.get(event, 0)) + 1
		return false

	var voice_index := _free_voice(at_tick)
	if voice_index < 0:
		# Cannot happen while the array is cap + 1 long and the gate above
		# passed, but a silent wrong answer here would be a sound that plays
		# over another one, so it is refused rather than forced.
		dropped[event] = int(dropped.get(event, 0)) + 1
		return false
	var voice: Dictionary = _voices[voice_index]

	var ticks := _length_ticks(stream)
	voice["started"] = at_tick
	voice["until"] = at_tick + ticks
	voice["event"] = event

	if not silent:
		var player: AudioStreamPlayer = voice["player"]
		if player == null:
			player = AudioStreamPlayer.new()
			add_child(player)
			voice["player"] = player
		player.stream = stream
		player.play()

	log.append({"tick": at_tick, "event": event, "take": take,
		"voice": voice_index})
	if log.size() > LOG_LIMIT:
		log = log.slice(log.size() - LOG_LIMIT)
	return true


## How many times a take has been played. The original's per-sound counters.
func uses_of(take: String) -> int:
	return int(_uses.get(take, 0))


## How many simulation ticks a stream lasts. Rounded UP, so a voice is never
## reported free while it is still making noise.
func _length_ticks(stream: AudioStreamWAV) -> int:
	var seconds := stream.get_length()
	return maxi(1, int(ceil(seconds * float(Const_.TICK_HZ))))


func _free_voice(at_tick: int) -> int:
	for i in _voices.size():
		if int(_voices[i]["until"]) <= at_tick:
			return i
	return -1


## How many voices are making noise at `at_tick`. For tests and for a debug
## overlay; the mixer itself never asks.
func busy_at(at_tick: int) -> int:
	var n := 0
	for v in _voices:
		if int(v["until"]) > at_tick:
			n += 1
	return n


## Stop everything on the way out.
##
## A stream still playing when the tree is torn down leaves its
## AudioStreamPlaybackWAV referenced by the audio server, and Godot reports
## that at exit as "8 ObjectDB instances were leaked" — harmless, but it looks
## exactly like a real leak, and a warning nobody can explain is a warning
## everybody learns to ignore.
func _notification(what: int) -> void:
	if what == NOTIFICATION_EXIT_TREE or what == NOTIFICATION_PREDELETE:
		stop_all()


func stop_all() -> void:
	for v in _voices:
		v["started"] = -1
		v["until"] = -1


## Forget every voice's busy-until tick. Call this whenever a new round's Sim
## starts, because `until` is an ABSOLUTE tick recorded against the round that
## was playing — Sfx itself outlives every round (main.gd builds one for the
## whole app), but `Sim.tick_count` restarts at 0 each round. Without this, a
## voice whose sound finished at, say, tick 900 of round 1 reports itself busy
## for the first 900 ticks of round 2 as well, because `until (900) > at_tick
## (0..899)` is still true — so every voice looks permanently busy and every
## sound is dropped until the new round's clock catches up to the old one's.
## That is "sound stops working after the first round".
func new_round() -> void:
	for v in _voices:
		v["until"] = -1
		v["event"] = ""
		if not silent and v["player"] != null:
			(v["player"] as AudioStreamPlayer).stop()
