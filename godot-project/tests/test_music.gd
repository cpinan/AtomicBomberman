# The per-level music — SOUNDLST 1100-1110 — and the option that turns it off,
# MESSAGES.TXT 263.
#
# The audio itself is never in the asset pack: eleven tracks, 120 MB of raw
# PCM, against VALUELST resource 6's 7 MB sound budget. So what is asserted
# here is the part that has to be right for a desktop run to find them on the
# player's own disc, and the part that has to be right for a build without one
# to do nothing rather than break.
extends SceneTree

const T_ := preload("res://tests/t.gd")
const Music_ := preload("res://scripts/audio/music.gd")
const Menu_ := preload("res://scripts/app/menu.gd")
const Messages_ := preload("res://scripts/core/messages.gd")
const SoundPack_ := preload("res://scripts/audio/sound_pack.gd")


func _init() -> void:
	var t := T_.new("music")
	_test_names(t)
	_test_paths(t)
	_test_disabled(t)
	_test_pcm(t)
	_test_missing_is_quiet(t)
	_test_the_option(t)
	_test_screen_tracks(t)
	quit(t.finish())


func _test_names(t: T_) -> void:
	var m: Music_ = Music_.new()
	t.ok(not m.load_names({}), "a manifest with no music list gives no names")
	t.eq(m.names.size(), 0, "and leaves the list empty")

	t.ok(m.load_names({"music": ["grnacres", "generic", "hockey"]}),
		"the names come out of the sound pack's manifest")
	t.eq(m.names.size(), 3, "all of them")
	t.eq(m.names[0], "grnacres", "level 0 is Green Acres' own track")
	m.free()


func _test_paths(t: T_) -> void:
	var m: Music_ = Music_.new()
	m.load_names({"music": ["grnacres", "generic", "hockey"]})
	t.eq(m.path_for(0), "", "with no data directory there is no path")

	m.data_dir = "/somewhere/original-game"
	t.eq(m.path_for(0), "/somewhere/original-game/SOUND/GRNACRES.RSS",
		"the disc's own layout: SOUND/<NAME>.RSS, upper case")
	t.eq(m.path_for(2), "/somewhere/original-game/SOUND/HOCKEY.RSS", "level 2")
	t.eq(m.path_for(9), "", "a level with no name has no path")
	t.eq(m.path_for(-1), "", "and neither does a level below zero")
	m.free()


func _test_disabled(t: T_) -> void:
	var m: Music_ = Music_.new()
	m.load_names({"music": ["grnacres"]})
	m.data_dir = "/somewhere/original-game"
	m.disabled = true
	t.ok(not m.play_level(0), "disabled, nothing plays")
	t.ok(m.reason.contains("263"),
		"and it says which option did it: %s" % m.reason)
	t.ok(not m.playing(), "the player is silent")
	m.free()


# The format is SOUNDLST's own: raw 22 kHz 16-bit signed, and stereo unless the
# size says it cannot be — tools/rss.py's rule, because 25 files on the disc
# are mono.
func _test_pcm(t: T_) -> void:
	var stereo := PackedByteArray()
	stereo.resize(800)                    # divides by 4
	var s := Music_.from_pcm(stereo)
	t.eq(s.mix_rate, float(Music_.SAMPLE_RATE), "22050 Hz, from SOUNDLST")
	t.eq(s.format, AudioStreamWAV.FORMAT_16_BITS, "16-bit")
	t.ok(s.stereo, "a size that divides by 4 is read as stereo")
	t.eq(s.loop_mode, AudioStreamWAV.LOOP_FORWARD,
		"and it loops — a round has no fixed length")
	t.eq(s.loop_end, 200, "800 bytes is 200 stereo frames")

	var mono := PackedByteArray()
	mono.resize(802)                      # divides by 2 but not by 4
	var m := Music_.from_pcm(mono)
	t.ok(not m.stereo,
		"a size 16-bit stereo cannot produce is read as mono instead")
	t.eq(m.loop_end, 401, "802 bytes is 401 mono frames")


func _test_missing_is_quiet(t: T_) -> void:
	var m: Music_ = Music_.new()
	m.load_names({"music": ["nosuchtrack"]})
	m.data_dir = "/no/such/place"
	t.ok(m.stream_for(0) == null, "a track that is not there loads as nothing")
	t.ok(m.reason.contains("nosuchtrack".to_upper())
		or m.reason.contains("no music"),
		"and says where it looked: %s" % m.reason)
	t.ok(not m.play_level(0), "so nothing plays")
	t.ok(not m.playing(), "and the game runs on in silence, which is what a"
		+ " build with no copy of the disc does")
	m.free()


# MESSAGES.TXT 263 is a real toggle now that there is music to disable.
func _test_the_option(t: T_) -> void:
	t.eq(Messages_.OPT_DISABLE_MUSIC, "Disable music during gameplay: %s",
		"263 is the disc's own label")
	var menu: Menu_ = Menu_.new()
	menu.setup([])
	t.eq(menu.label_of(Menu_.Item.NO_MUSIC), "Disable music during gameplay",
		"and the menu uses it")
	t.ok(not menu.no_music, "off by default — the disc ships the music")
	t.eq(menu.value_text(Menu_.Item.NO_MUSIC), "No", "shown as No")

	menu.cursor = Menu_.Item.NO_MUSIC
	menu.adjust(1)
	t.ok(menu.no_music, "and it toggles")
	t.eq(menu.value_text(Menu_.Item.NO_MUSIC), "Yes", "reading Yes")
	t.ok(bool(menu.config()["no_music"]), "and reaches the game")

	# MESSAGES.TXT 256 while we are here: the roulette existed before the
	# switch that turns it off did.
	t.eq(menu.label_of(Menu_.Item.GOLD), "Gold Bomberman", "256's own label")
	t.ok(menu.gold_bomberman, "on by default — the disc ships the whole screen")
	menu.cursor = Menu_.Item.GOLD
	menu.adjust(1)
	t.ok(not menu.gold_bomberman, "and it can be turned off")
	t.ok(not bool(menu.config()["gold"]), "which reaches the game too")


# ---------------------------------------------------------------------------
# The screens have music of their own, and the port had none of it: a menu in
# silence was the first thing a player noticed. SOUNDLST names them one by one,
# each with its own comment:
#
#   1000 title    "title page music"
#   1010 menu     "main menu music"
#   1020 win      "music for input selection"
#   1030 lose     "game is over screen music"
#   1040 network  "join/start a network game"
#   1130 draw     "(used for end of a game, generally)"
# ---------------------------------------------------------------------------
func _test_screen_tracks(t: T_) -> void:
	var m: Music_ = Music_.new()
	m.load_names({"music": ["grnacres"], "music_screens": {
		"title": "title", "menu": "menu", "setup": "win",
		"gameover": "lose", "network": "network", "draw": "draw"}})
	t.eq(m.screen_names.size(), 6, "six screen tracks")
	t.eq(String(m.screen_names["menu"]), "menu", "1010 is the main menu's")
	t.eq(String(m.screen_names["setup"]), "win",
		"1020's file is WIN.RSS, whatever it is called")

	m.data_dir = "/no/such/place"
	t.ok(not m.play_screen("menu"),
		"with no data there is nothing to play")
	t.ok(not m.play_screen("nosuchscreen"), "and no track for a screen the"
		+ " disc does not name")
	t.ok(m.reason.contains("nosuchscreen"), "which it says: %s" % m.reason)
	m.free()

	# The pack the game actually loads has to carry them, or none of this
	# reaches a player.
	var pack: SoundPack_ = SoundPack_.new()
	if not pack.load_from(SoundPack_.default_dir()):
		t.note("skipping the packed names: no sound pack")
		return
	t.eq(pack.music.size(), 11, "eleven level tracks in the pack")
	t.eq(pack.music_screens.size(), 6, "and six screen tracks")
