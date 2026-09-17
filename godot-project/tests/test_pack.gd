# The asset pack's manifest: is everything the renderer asks for actually in it?
#
# This is the suite that catches a pack built from a different disc, a rename in
# tools/pack_assets.py, or a sequence the renderer names that the art does not
# have — each of which would otherwise show up as a silently missing sprite.
extends SceneTree

const T_ := preload("res://tests/t.gd")
const Const_ := preload("res://scripts/core/const.gd")
const Types_ := preload("res://scripts/core/types.gd")
const Pack_ := preload("res://scripts/render/pack.gd")
const Scheme_ := preload("res://scripts/core/scheme.gd")

# Sheets the renderer names directly. A pack without these cannot draw a round.
const REQUIRED := ["stand", "walk", "bombs", "mflame", "shadow", "powers"]

# The nine flame sequences, which must exist because game_view.gd derives their
# names from the sim's flame bits and would silently draw nothing otherwise.
const FLAME_SEQS := [
	"flame center green",
	"flame midnorth green", "flame midsouth green",
	"flame midwest green", "flame mideast green",
	"flame tipnorth green", "flame tipsouth green",
	"flame tipwest green", "flame tipeast green",
]

# The 13 powerups the scheme file's -P lines index, by the key pack_assets.py
# derives from the original's own sequence names. 'disease3' is the original's
# name for the super bad disease, and 'clog' is the roulette power-down that
# VALUELST resource 91 governs.
const POWERUP_KEYS := ["bomb", "flame", "disease", "kicker", "skate", "punch",
	"grab", "spooge", "goldflame", "trigger", "jelly", "disease3", "random",
	"clog"]


func _init() -> void:
	var t := T_.new("pack")
	var pack: Pack_ = Pack_.new()
	if not pack.load_from(Pack_.default_dir()):
		t.note(pack.error)
		t.note("skipping: no asset pack built")
		quit(t.finish())
		return

	for name in REQUIRED:
		t.ok(pack.has_sheet(name), "the pack has sheet %s" % name)

	_test_schemes(t, pack)
	_test_every_action_has_its_animation(t, pack)
	_test_the_help_texts_travel(t, pack)
	# LAST: it replaces the bomb sheet with a one-frame stand-in, and every
	# assertion above it is about what the disc's own sheets hold.
	_test_overlay(t, pack)

	# Per-level tiles and brick animations, one set per level.
	for level in Const_.FIELD_H:
		if level > 10:
			break
		t.ok(pack.has_sheet("tiles%d" % level), "tiles%d present" % level)
		t.ok(pack.has_sheet("xbrick%d" % level), "xbrick%d present" % level)
		# Brick and solid are required: a level without them cannot show its
		# structure at all.
		for kind in ["brick", "solid"]:
			t.ok(pack.has_sequence("tiles%d" % level, "tile %d %s" % [level, kind]),
				"tiles%d has 'tile %d %s'" % [level, level, kind])
		# A 'blank' tile is OPTIONAL, and only level 0 has one. Everywhere else
		# an empty cell is the FIELD<n>.PCX floor showing through, with nothing
		# drawn over it — which is why game_view.gd asks for the sequence and
		# draws nothing when it is absent. Asserting all eleven had a blank
		# tile was this suite's first version, and it was wrong about the art.
		if level == 0:
			t.ok(pack.has_sequence("tiles0", "tile 0 blank"),
				"level 0 does have a blank tile (the grass overlay)")
		else:
			t.ok(not pack.has_sequence("tiles%d" % level, "tile %d blank" % level),
				"level %d has no blank tile; its floor is the background" % level)

	for seq in FLAME_SEQS:
		t.ok(pack.has_sequence("mflame", seq), "mflame has %s" % seq)

	# The player sequences the renderer builds from Types.Dir.
	for dir_name in ["north", "south", "west", "east"]:
		t.ok(pack.has_sequence("stand", "stand %s" % dir_name),
			"stand has 'stand %s'" % dir_name)
		t.ok(pack.has_sequence("walk", "walk %s" % dir_name),
			"walk has 'walk %s'" % dir_name)

	# The map specials. game_view.gd derives these names from Types.Dir, so a
	# mismatch draws nothing at all — which is how the first version, using
	# "arrow north" instead of the original's "extra arrow north", would have
	# presented.
	for dir_name in ["north", "south", "west", "east"]:
		t.ok(pack.has_sequence("extras", "extra arrow %s" % dir_name),
			"extras has 'extra arrow %s'" % dir_name)
		t.ok(pack.has_sequence("conveyor", "extra conveyor %s" % dir_name),
			"conveyor has 'extra conveyor %s'" % dir_name)
	t.ok(pack.has_sequence("extras", "extra warp 1"),
		"extras has 'extra warp 1'")
	t.ok(pack.has_sequence("extras", "extra trampoline"),
		"extras has 'extra trampoline'")

	t.ok(pack.has_sequence("bombs", "bomb regular green"),
		"bombs has the idle sequence")
	t.ok(pack.has_sequence("shadow", "shadow"), "shadow has its sequence")

	# The names game_view.gd derives from Types.PowerUp must all resolve, or a
	# powerup would silently draw nothing.
	const RENDER_SEQ := ["bomb", "flame", "disease", "kicker", "skate",
		"punch", "grab", "spooge", "goldflame", "trigger", "jelly",
		"disease3", "random"]
	for name in RENDER_SEQ:
		t.ok(pack.has_sequence("powers", "power %s" % name),
			"powers has 'power %s'" % name)
	t.eq(RENDER_SEQ.size(), Const_.POWERUP_COUNT,
		"one render sequence per scheme powerup")

	for key in POWERUP_KEYS:
		t.ok(pack.powerup_keys().has(key), "the pack has powerup %s" % key)
	t.eq(pack.powerup_keys().size(), POWERUP_KEYS.size(),
		"exactly the 13 scheme powerups plus clog")

	# One background per level.
	t.eq(pack.background_count(), 11, "eleven level backgrounds")
	for level in 11:
		t.ok(pack.background(level) != null, "background %d loads" % level)

	# Cell geometry. The tile art must be exactly one cell, or the field would
	# not tile — and the powerup icons are cell-sized too, which is why the 16
	# 40x36 PCX files in RES/ line up with BLOCK_W x BLOCK_H.
	var tile_rect := pack.frame_rect("tiles0", 0)
	t.eq(int(tile_rect.size.x), Const_.BLOCK_W, "a tile frame is BLOCK_W wide")
	t.eq(int(tile_rect.size.y), Const_.BLOCK_H, "a tile frame is BLOCK_H tall")

	# Every sequence step must address a frame the sheet actually has. The
	# extractor already refuses a dangling reference; this is the same check on
	# the far side of the manifest, so a bad hand-edit cannot slip through.
	var dangling := 0
	for sheet in pack.sheet_names():
		var count := pack.frame_count(sheet)
		for seq in pack.sequence_names(sheet):
			for index in pack.sequence_steps(sheet, seq):
				if index < 0 or index >= count:
					dangling += 1
					t.ok(false, "%s/%s references frame %d of %d"
						% [sheet, seq, index, count])
	t.eq(dangling, 0, "no sequence references a frame that does not exist")

	# Hotspots must be inside their frame, or a sprite would be positioned by
	# an anchor outside its own art.
	var bad_hotspots := 0
	for sheet in pack.sheet_names():
		for i in pack.frame_count(sheet):
			var r := pack.frame_rect(sheet, i)
			var h := pack.frame_hotspot(sheet, i)
			if h.x < 0 or h.y < 0 or h.x > r.size.x + 64 or h.y > r.size.y + 64:
				bad_hotspots += 1
	t.eq(bad_hotspots, 0, "every hotspot is near its own frame")

	t.note("%d sheets, %d powerups, %d backgrounds"
		% [pack.sheet_names().size(), pack.powerup_keys().size(),
			pack.background_count()])
	quit(t.finish())


# The 67 schemes travel in the manifest as TEXT.
#
# Not for the renderer's sake — for the menu's, and for a browser's. There is no
# SCHEMES folder inside a web build, so without these the only level local play
# could offer is the built-in fallback grid. scheme.gd already parses text,
# which is what the wire sends, so this needs no second format.
func _test_schemes(t: T_, pack: Pack_) -> void:
	var names := pack.scheme_names()
	t.eq(names.size(), 67, "all 67 schemes are in the pack")
	t.ok(pack.has_scheme("BASIC"), "including BASIC")
	t.ok(pack.has_scheme("basic"), "case-insensitively")
	t.ok(not pack.has_scheme("NOSUCHSCHEME"), "and not one that does not exist")

	# Every one has to parse, or the menu offers a level that cannot start.
	var failed: Array[String] = []
	var total_bytes := 0
	for name in names:
		var text := pack.scheme_text(String(name))
		total_bytes += text.length()
		var scheme: Scheme_ = Scheme_.new()
		if not scheme.parse_text(text, String(name)):
			failed.append("%s (%s)" % [name, scheme.error()])
	t.eq(failed.size(), 0,
		"every scheme in the pack parses (%s)" % ", ".join(failed))
	t.note("%d schemes, %d KB of text" % [names.size(), total_bytes / 1024])

	# Sorted, because the menu walks the list and an arbitrary order would make
	# a scheme hard to find among 67.
	var sorted_names := names.duplicate()
	sorted_names.sort()
	t.eq(names, sorted_names, "the list comes back sorted")


# ---------------------------------------------------------------------------
# Replacement art, laid over the pack a sheet at a time — what makes repainting
# this game a job somebody can start without finishing. tools/artpack.py writes
# the folders and docs/ART.md is the guide; this is the loader's half.
# ---------------------------------------------------------------------------
func _test_overlay(t: T_, pack: Pack_) -> void:
	var dir := "user://test_overlay"
	DirAccess.make_dir_recursive_absolute(dir)

	# A one-frame sheet, in a colour nothing on the disc is, replacing a name
	# the pack already has.
	var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 0, 1, 1))
	img.save_png(dir.path_join("bombs.png"))
	var manifest := {
		"sheets": {
			"bombs": {
				"sheet": "bombs.png",
				"cell": [8, 8],
				"count": 1,
				"frames": [{"rect": [0, 0, 8, 8], "hotspot": [4, 7],
					"name": "replacement"}],
				"sequences": {"bomb regular green": {"steps": [[0, 0, 0]]}},
			},
		},
	}
	var f := FileAccess.open(dir.path_join("pack.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(manifest))
	f.close()

	var before_frames: int = pack.frame_count("bombs")
	var other_before: int = pack.frame_count("mflame")
	t.ok(before_frames > 1, "the disc's bomb sheet has %d frames" % before_frames)

	t.ok(pack.overlay_from(dir), "the overlay loads: %s" % pack.error)
	t.eq(pack.frame_count("bombs"), 1,
		"and the sheet it names is replaced, not merged")
	t.eq(pack.frame_count("mflame"), other_before,
		"while everything it does not name is left exactly alone")
	t.ok(pack.has_sheet("stand"), "including sheets from the pack underneath")
	t.eq(pack.overlays.size(), 1, "and the pack records what was laid over it")

	# Schemes are not art and must survive an overlay that mentions none.
	t.ok(pack.scheme_names().size() > 0,
		"the schemes are still there afterwards")

	# An overlay that is not there is an error, not a crash.
	t.ok(not pack.overlay_from("user://test_overlay_absent"),
		"a missing overlay is refused")
	t.ok(not pack.error.is_empty(), "and says so")

	DirAccess.remove_absolute(ProjectSettings.globalize_path(
		dir.path_join("bombs.png")))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(
		dir.path_join("pack.json")))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(dir))


# EVERY THING A PLAYER CAN DO HAS A PICTURE ON THE DISC, and the port drew four
# of them. MANUAL.BM names the rest and each has its own ANI with its own
# sequence names, which is how they were found:
#
#   PUNCH.ANI     `punch <dir> green`     the swing
#   PUNBOMB1..4   `punch <dir>`           the bomb tumbling away from it
#   BOMBWALK.ANI  `bombwalk <dir> green`  carrying one over your head
#   BPICKUP.ANI   `pickup <dir> green`    picking it up
#   TRIGBOMB.ANI  `bomb trigger green`    the bomb that waits for its owner
#   DUDS.ANI      `bomb regular green dud`  VALUELST 322's one-in-three
#   BOMBS.ANI     `bomb jelly green`      already packed, and never drawn
#
# The names are asserted, not the pictures: game_view.gd builds them with the
# same "%s" the binary does, so a sequence that is not there draws NOTHING and
# the player falls back to standing — which is what a kick, a punch, a grab and
# a carry all looked like.
func _test_every_action_has_its_animation(t: T_, pack: Pack_) -> void:
	const COMPASS := ["north", "south", "east", "west"]
	for dir in COMPASS:
		t.ok(pack.has_sequence("walk", "walk %s" % dir),
			"walk %s" % dir)
		t.ok(pack.has_sequence("stand", "stand %s" % dir),
			"stand %s" % dir)
		t.ok(pack.has_sequence("kick", "kick %s" % dir),
			"kick %s" % dir)
		t.ok(pack.has_sequence("punch", "punch %s green" % dir),
			"punch %s green" % dir)
		t.ok(pack.has_sequence("bombwalk", "bombwalk %s green" % dir),
			"bombwalk %s green" % dir)
		t.ok(pack.has_sequence("bpickup", "pickup %s green" % dir),
			"pickup %s green" % dir)
	# One PUNBOMB file per direction, each naming only its own.
	for pair in [[1, "south"], [2, "north"], [3, "west"], [4, "east"]]:
		t.ok(pack.has_sequence("punbomb%d" % pair[0], "punch %s" % pair[1]),
			"punbomb%d holds `punch %s`" % [pair[0], pair[1]])

	t.ok(pack.has_sequence("bombs", "bomb regular green"), "the plain bomb")
	t.ok(pack.has_sequence("bombs", "bomb jelly green"), "the jelly bomb")
	t.ok(pack.has_sequence("trigbomb", "bomb trigger green"),
		"the trigger bomb")
	t.ok(pack.has_sequence("duds", "bomb regular green dud"), "and a dud")

	# WALK.ANI's fifth sequence, which is one frame from each direction and is
	# what a player in the air off a trampoline is drawn with.
	t.ok(pack.has_sequence("walk", "spin"), "and the trampoline spin")

	# All 24 deaths, spread over the seventeen XPLODE files. VALUELST 105 says
	# 24 and one that is missing falls through to the standing frame — which is
	# a player who dies by standing still.
	var deaths := 0
	for n in range(1, 25):
		if not pack.sheet_with_sequence("die green %d" % n).is_empty():
			deaths += 1
	t.eq(deaths, 24, "all 24 death animations are in the pack")


# CREDITS.BM and MANUAL.BM travel in the pack. They used to be opened by path
# from ../original-game at draw time, so About Bomberman and the Online Manual
# were blank in any build that did not have the CD sitting beside it.
func _test_the_help_texts_travel(t: T_, pack: Pack_) -> void:
	for name in ["CREDITS", "MANUAL"]:
		var text := pack.help_text(name)
		t.ok(text.length() > 1500,
			"%s.BM is in the pack (%d bytes)" % [name, text.length()])
		t.ok(text.split("\n").size() > 100,
			"and is %d lines, which is why it scrolls"
				% text.split("\n").size())
	t.eq(pack.help_text("NOT-A-FILE"), "",
		"and asking for one that is not there gives nothing rather than an error")
