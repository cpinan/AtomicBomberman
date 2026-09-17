# Loads the sound pack tools/rss.py emits, and hands out playable streams.
#
# Data only: no players, no mixing, no tree. That is scripts/audio/sfx.gd's
# job, and the split is what lets the choosing be tested headless — a suite can
# ask which take an event would use without an audio device existing.
#
# ---------------------------------------------------------------------------
# WHAT AN EVENT IS
# ---------------------------------------------------------------------------
# SOUNDLST.RES gives each event a RANGE of resource numbers, and every number
# in the range is an alternative take the game picks among so a repeated action
# does not sound identical every time. `bomb_drop` has bmdrop2 and bmdrop3;
# `bomb_explode` has twenty. tools/rss.py's EVENTS table carries those ranges
# with the disc's own wording beside each, and the pack manifest carries the
# takes that survived the size budget.
#
# ---------------------------------------------------------------------------
# WHY RAW PCM AND NOT WAV
# ---------------------------------------------------------------------------
# AudioStreamWAV wants samples plus a format, so a 44-byte RIFF header per
# sound would be 44 bytes of nothing and one more thing that could disagree
# with the manifest. The container holds the `.RSS` bytes unaltered — no
# resampling, no downmix — and the manifest states the rate, the width and the
# channel count.
extends RefCounted

const Abpk_ := preload("res://scripts/core/abpk.gd")

var root: String = ""
var loaded: bool = false
var error: String = ""

## Sample rate the whole pack is in. From the manifest, not assumed: the disc
## says 22050 and every file measured agrees, but a pack built by hand might
## not.
var sample_rate: int = 22050

## event name -> [take name, ...] in resource order
var _events: Dictionary = {}
## The per-level music track names, by level. Empty when the pack predates
## them or the manifest has none.
var music: PackedStringArray = PackedStringArray()

## The screens' own tracks, by the port's name for each screen — SOUNDLST
## 1000/1010/1020/1030/1040/1130. Names only, for the same reason.
var music_screens: Dictionary = {}

## take name -> AudioStreamWAV, built on first use
var _streams: Dictionary = {}
## take name -> {blob, channels, frames}
var _sounds: Dictionary = {}

var _container: Abpk_ = null


## Load a pack. The container first, then the loose directory, exactly as the
## art pack does — an export carries `sfx.bin`, a source checkout may have both.
func load_from(dir_path: String) -> bool:
	root = dir_path
	loaded = false
	error = ""
	_events = {}
	_streams = {}
	_sounds = {}
	_container = null
	music = PackedStringArray()
	music_screens = {}

	var manifest: Dictionary = {}
	var container := dir_path.trim_suffix("/") + ".bin"
	if FileAccess.file_exists(container):
		var box: Abpk_ = Abpk_.new()
		if not box.open(container):
			error = box.error
			return false
		_container = box
		manifest = box.manifest
	else:
		var manifest_path := dir_path.path_join("sounds.json")
		if not FileAccess.file_exists(manifest_path):
			error = ("no sound pack at %s or %s — run tools/rss.py --pack "
				+ "(needs the original game data; see docs/PLAN.md)") \
				% [container, dir_path]
			return false
		var parsed: Variant = JSON.parse_string(
			FileAccess.get_file_as_string(manifest_path))
		if not (parsed is Dictionary):
			error = "%s is not valid JSON" % manifest_path
			return false
		manifest = parsed

	# The eleven per-level track NAMES — SOUNDLST 1100-1110. The audio is 120 MB
	# and never travels in this container; scripts/audio/music.gd reads it from
	# the player's own disc. Names only, so a build with no disc still knows
	# what it is missing.
	for entry in manifest.get("music", []):
		music.append(String(entry))
	var screens: Variant = manifest.get("music_screens", {})
	if screens is Dictionary:
		music_screens = (screens as Dictionary).duplicate()

	var fmt: Dictionary = manifest.get("format", {})
	sample_rate = int(fmt.get("sample_rate", sample_rate))
	_sounds = manifest.get("sounds", {})

	# An event whose takes are all absent from `sounds` would be silent at
	# runtime for a reason nobody would trace back to the pack, so it is an
	# error here rather than a surprise later.
	var empty: Array[String] = []
	for event in manifest.get("events", {}):
		var takes: Array = manifest["events"][event]
		var kept: Array[String] = []
		for take in takes:
			if _sounds.has(String(take).to_lower()):
				kept.append(String(take).to_lower())
		if kept.is_empty():
			empty.append(String(event))
		else:
			_events[String(event)] = kept
	if not empty.is_empty():
		error = "%d events have no playable take: %s" \
			% [empty.size(), ", ".join(empty)]
		return false
	if _events.is_empty():
		error = "%s names no events" % container
		return false

	loaded = true
	return true


func has_event(event: String) -> bool:
	return _events.has(event)


func event_names() -> Array:
	return _events.keys()


## The takes behind an event, in resource order.
func takes(event: String) -> Array:
	return _events.get(event, [])


func take_count(event: String) -> int:
	return (_events[event] as Array).size() if _events.has(event) else 0


## The take at one index within an event, wrapping.
##
## WHICH index is scripts/audio/sfx.gd's decision, and it is the original's:
## random among the LEAST-USED takes. This function only resolves an index to a
## name — it holds no counters, because a pack is data.
func take_at(event: String, index: int) -> String:
	var list: Array = _events.get(event, [])
	if list.is_empty():
		return ""
	return String(list[posmod(index, list.size())])


## An event's stream by take index. Returns null when the event is unknown,
## which callers treat as silence.
func stream_for(event: String, index: int) -> AudioStreamWAV:
	var take := take_at(event, index)
	return null if take.is_empty() else stream(take)


func stream(take: String) -> AudioStreamWAV:
	if _streams.has(take):
		return _streams[take]
	if not _sounds.has(take):
		return null
	var info: Dictionary = _sounds[take]
	var data := _bytes_of(String(info.get("blob", take + ".pcm")))
	if data.is_empty():
		return null
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = sample_rate
	s.stereo = int(info.get("channels", 2)) == 2
	s.data = data
	_streams[take] = s
	return s


func _bytes_of(blob: String) -> PackedByteArray:
	if _container != null and _container.has(blob):
		return _container.blob(blob)
	var path := root.path_join(blob)
	if FileAccess.file_exists(path):
		return FileAccess.get_file_as_bytes(path)
	# The loose form writes WAVs rather than raw PCM, since a WAV is what can
	# be listened to. Strip the 44-byte canonical header tools/rss.py wrote.
	var wav := root.path_join(blob.get_basename() + ".wav")
	if FileAccess.file_exists(wav):
		var bytes := FileAccess.get_file_as_bytes(wav)
		if bytes.size() > 44:
			return bytes.slice(44)
	return PackedByteArray()


## Where to look. res:// first, because that is where an exported build's
## sounds are and a browser has no filesystem to fall back to.
##
## AB_SFX overrides it, which is how a smaller pack — `tools/rss.py --pack
## --budget 2000000` — gets tested without moving anything.
static func default_dir() -> String:
	var env := OS.get_environment("AB_SFX")
	if not env.is_empty():
		return env
	if FileAccess.file_exists("res://data/packs/sfx.bin") \
			or FileAccess.file_exists("res://data/packs/sfx/sounds.json"):
		return "res://data/packs/sfx"
	return ProjectSettings.globalize_path("res://data/packs/sfx")
