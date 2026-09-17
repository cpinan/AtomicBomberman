# The per-level music — `SOUNDLST` 1100-1110, one track per level.
#
# ---------------------------------------------------------------------------
# WHY IT IS NOT IN THE ASSET PACK
# ---------------------------------------------------------------------------
# The eleven tracks are **120 MB** of raw PCM on the disc. VALUELST resource 6,
# the game's own sound budget, is **7 MB**, and `tools/rss.py` already spends
# all of it on the 36 sound events. So the pack carries the NAMES (the manifest
# has a `music` list, in level order) and nothing else, and the audio is read
# from the player's own copy of the game at the moment it is needed.
#
# The consequence is worth stating plainly: **a desktop run pointed at the disc
# has music, and a browser build does not.** A browser has no disc to read, and
# 120 MB — or even ten of it, re-encoded — is not a download a player should
# take for a game that fits in ten megabytes without it.
#
# ---------------------------------------------------------------------------
# THE OPTION IS THE DISC'S OWN
# ---------------------------------------------------------------------------
# `MESSAGES.TXT` 263 is "Disable music during gameplay: %s" and `OPTIONS.BM`
# explains it: "If this option is set to 'YES', no music will play during
# gameplay. Disabling music during gameplay will increase the performance of
# the game, especially in network play." That option now has something to turn
# off, so `scripts/app/menu.gd` offers it.
#
# ---------------------------------------------------------------------------
# THE FORMAT
# ---------------------------------------------------------------------------
# `.RSS` is headerless PCM — SOUNDLST's own header says "raw 22khz Stereo 16bit
# signed, Intel-endian" — so a track becomes an AudioStreamWAV with no parsing
# at all. Channel count is detected the way `tools/rss.py` detects it: a size
# that is not a multiple of 4 cannot be 16-bit stereo.
extends Node

const Const_ := preload("res://scripts/core/const.gd")

## SOUNDLST's own format for these files.
const SAMPLE_RATE := 22050
const BYTES_PER_SAMPLE := 2

## Where the tracks live inside the game's data directory.
const SUBDIR := "SOUND"
const EXTENSION := ".RSS"

## Music sits under the sound effects rather than over them: the effects are
## what a player needs to hear to survive.
const VOLUME_DB := -12.0

## Track names by level, from the sound pack's manifest. Empty until a pack is
## given, and empty is not an error — it means no music, which is what a
## browser build gets.
var names: PackedStringArray = PackedStringArray()

## The screens' own tracks, by the port's name for each screen. SOUNDLST names
## them one by one with a comment above each: 1000 title, 1010 menu, 1020 the
## input-selection screen, 1030 game over, 1040 network, 1130 draw.
var screen_names: Dictionary = {}

## Where the original's data was found. The same directory the art and sounds
## were built from; AB_DATA overrides it, as everywhere else.
var data_dir: String = ""

## The disc's own option, MESSAGES.TXT 263. When true nothing plays.
var disabled: bool = false

var _player: AudioStreamPlayer = null
var _level: int = -1
var _screen: String = ""
var _cache: Dictionary = {}

## Why the last attempt played nothing, for the caller to print or ignore.
var reason: String = ""


## The player is built on first use rather than in _init(): a child added
## during construction is not in the scene tree yet, and AudioStreamPlayer
## refuses to play from outside it ("Playback can only happen when a node is
## inside the scene tree"). Building it here means it is created when this node
## is already where it needs to be.
func _ensure_player() -> bool:
	if _player != null:
		return _player.is_inside_tree()
	if not is_inside_tree():
		return false
	_player = AudioStreamPlayer.new()
	_player.volume_db = VOLUME_DB
	add_child(_player)
	return true


## Take the track names out of a sound pack's manifest.
func load_names(manifest: Dictionary) -> bool:
	names = PackedStringArray()
	screen_names = {}
	var screens: Variant = manifest.get("music_screens", {})
	if screens is Dictionary:
		screen_names = (screens as Dictionary).duplicate()
	var list: Variant = manifest.get("music", [])
	if not (list is Array):
		return false
	for entry in (list as Array):
		names.append(String(entry))
	return names.size() > 0


## The file a level's track would be read from, or "" if there is none. Public
## because "where would it have looked" is the first question when a track does
## not play.
func path_for(level: int) -> String:
	if level < 0 or level >= names.size():
		return ""
	var name := names[level]
	if name.is_empty() or data_dir.is_empty():
		return ""
	return data_dir.path_join(SUBDIR).path_join(name.to_upper() + EXTENSION)


## Start a screen's own track — "title", "menu", "setup", "gameover",
## "network" or "draw". The menus are not gameplay, so MESSAGES.TXT 263's
## "disable music DURING GAMEPLAY" does not silence them.
func play_screen(which: String) -> bool:
	reason = ""
	var name := String(screen_names.get(which, ""))
	if name.is_empty():
		reason = "no screen track named %s" % which
		return false
	if _screen == which and playing():
		return true
	var stream := _stream_for_name(name)
	if stream == null:
		stop()
		return false
	if not _ensure_player():
		reason = "no audio player: this node is not in the scene tree"
		return false
	_screen = which
	_level = -1
	_player.stream = stream
	_player.play()
	return true


## Which screen's track is playing, or "".
func screen() -> String:
	return _screen if playing() else ""


## Start the track for a level, or stop if there is nothing to play. Returns
## true when something is playing when it returns.
func play_level(level: int) -> bool:
	reason = ""
	if disabled:
		reason = "music is disabled — MESSAGES.TXT 263"
		stop()
		return false
	if level == _level and playing():
		return true
	var stream := stream_for(level)
	if stream == null:
		stop()
		return false
	if not _ensure_player():
		reason = "no audio player: this node is not in the scene tree"
		return false
	_level = level
	_screen = ""
	_player.stream = stream
	_player.play()
	return true


## The stream for a level, cached. Null when the file is not there, which is
## the ordinary case for a build with no disc behind it.
func stream_for(level: int) -> AudioStreamWAV:
	var path := path_for(level)
	if path.is_empty():
		reason = "no track name for level %d" % level
		return null
	return _stream_at(path)


## One track by its SOUNDLST name, for the screens.
func _stream_for_name(name: String) -> AudioStreamWAV:
	if data_dir.is_empty():
		reason = "no data directory to read music from"
		return null
	return _stream_at(data_dir.path_join(SUBDIR).path_join(
		name.to_upper() + EXTENSION))


func _stream_at(path: String) -> AudioStreamWAV:
	if _cache.has(path):
		return _cache[path]
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		reason = "no music at %s" % path
		return null
	var raw := file.get_buffer(file.get_length())
	file.close()
	var stream := from_pcm(raw)
	_cache[path] = stream
	return stream


## Raw PCM to a looping stream. The loop is the whole file: these are pieces
## written to run under a round of unknown length.
static func from_pcm(raw: PackedByteArray) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	# tools/rss.py's own rule: 16-bit stereo frames are 4 bytes, so a size that
	# is not a multiple of 4 cannot be stereo.
	stream.stereo = raw.size() % 4 == 0
	stream.data = raw
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	var frame_bytes := 4 if stream.stereo else 2
	stream.loop_end = raw.size() / frame_bytes
	return stream


func stop() -> void:
	_level = -1
	_screen = ""
	if _player != null:
		_player.stop()


func playing() -> bool:
	return _player != null and _player.playing


func level() -> int:
	return _level
