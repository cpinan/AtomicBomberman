# Loads an asset pack — the manifest ../tools/pack_assets.py emits.
#
# A pack is a directory of sheet PNGs plus a pack.json describing every frame's
# rect and hotspot and every named animation sequence. Two packs are intended:
#
#   data/packs/cd/    built from the user's own disc; gitignored, never shipped
#   data/packs/free/  a distributable replacement, built to the same manifest
#
# Nothing outside this file knows which one is loaded, so the switch is a path.
#
# A frame is positioned by its HOTSPOT, not by its rect. The hotspot is the
# anchor the original draws the frame around, it is stored per frame, and it
# genuinely varies within one animation — CORNER6 ranges to y=109 where
# fpc_atomic records a single 90 for the whole sheet. Drawing at a uniform
# offset is drawing wrong on every frame whose hotspot differs.
class_name Pack

const Const_ := preload("res://scripts/core/const.gd")
const Abpk_ := preload("res://scripts/core/abpk.gd")

var root: String = ""
var loaded: bool = false
var error: String = ""

## sheet name -> {texture, cell, frames[], sequences{}}
var _sheets: Dictionary = {}
## powerup key -> {texture | steps}
var _powerups: Dictionary = {}
## level index -> Texture2D
var _backgrounds: Dictionary = {}
## scheme name (BASIC, OG, ...) -> its .SCH text
var _schemes: Dictionary = {}

## campaign name (SIMPLE, GHOSTS, CROUTON) -> its .CAM text
var _campaigns: Dictionary = {}

## The `*.BM` help texts, by stem: CREDITS, MANUAL, OPTIONS, NETWORK, ...
var _help: Dictionary = {}

## screen name (title, mainmenu, glue0, victory3, ...) -> Texture2D
var _screens: Dictionary = {}
## element name (credbar, winz, kurt, ...) -> Texture2D. PCX art the screens
## place, kept apart from the screens because every screen is 640x480 and none
## of these is.
var _elements: Dictionary = {}
## font name (font1, font6) -> {texture, height, glyphs}
var _fonts: Dictionary = {}

## The colour remap tables, when the pack carries them: the 256-colour palette,
## COLOR.PAL's RGB555 -> index lookup, and one .RMP row per player. See
## scripts/render/recolour.gdshader.
var _remap: Dictionary = {}

## The open container, when one was loaded. Null for a loose directory.
var _container: Abpk_ = null

## Packs laid over this one, in the order they were applied. Empty is the
## ordinary case; see overlay_from().
var overlays: Array[String] = []


## Load a pack. Two forms, and the container is tried first:
##
##   <dir>.bin    ONE file: header, manifest JSON, then every PNG concatenated.
##                This is what an exported build carries, because Godot's
##                importer strips loose PNGs out of an export and a .gdignore
##                that stops the importer also hides them from include_filter.
##                See tools/pack_assets.py for the whole story.
##
##   <dir>/       the loose files, which is what a source checkout has and what
##                is easier to look at while working on the extractor.
func load_from(dir_path: String) -> bool:
	root = dir_path
	loaded = false
	error = ""
	_sheets.clear()
	_powerups.clear()
	_backgrounds.clear()
	_schemes.clear()
	_campaigns.clear()
	_help.clear()
	_screens.clear()
	_elements.clear()
	_fonts.clear()
	_remap.clear()
	_container = null
	overlays.clear()

	var manifest := _read_manifest(dir_path)
	if manifest.is_empty():
		return false
	return _apply(manifest, dir_path)


## Lay a second pack over the one already loaded: whatever it names replaces
## what is there, and everything it does not name is left alone.
##
## This is what makes replacing the art a job somebody can do a sheet at a
## time. Point the game at the original's pack, put one repainted sheet in a
## folder of its own, and the game runs with that sheet replaced and no other
## change — no full pack to build, nothing to keep in step. tools/artpack.py
## writes the folders; docs/ART.md is the guide.
##
## Returns false and sets `error` if the overlay is unreadable. An overlay that
## simply contains nothing is not an error: it replaces nothing.
func overlay_from(dir_path: String) -> bool:
	if not loaded:
		error = "an overlay needs a pack under it"
		return false
	var base_container := _container
	var manifest := _read_manifest(dir_path)
	if manifest.is_empty():
		_container = base_container
		return false
	var ok := _apply(manifest, dir_path)
	# Every texture is loaded eagerly, so the base container goes back as soon
	# as the overlay has been read out of its own.
	_container = base_container
	if ok:
		overlays.append(dir_path)
	return ok


## A pack's manifest, from either form. Empty on failure, with `error` set.
func _read_manifest(dir_path: String) -> Dictionary:
	var container := dir_path.trim_suffix("/") + ".bin"
	if FileAccess.file_exists(container):
		var box: Abpk_ = Abpk_.new()
		if not box.open(container):
			error = box.error
			return {}
		_container = box
		return box.manifest
	_container = null
	var manifest_path := dir_path.path_join("pack.json")
	if not FileAccess.file_exists(manifest_path):
		error = ("no pack at %s or %s — run tools/pack_assets.py (needs "
			+ "the original game data; see docs/PLAN.md)") \
			% [container, dir_path]
		return {}
	var parsed: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(manifest_path))
	if not (parsed is Dictionary):
		error = "%s is not valid JSON" % manifest_path
		return {}
	return parsed


## Everything a manifest names, into the dictionaries. Called once by
## load_from() on a cleared pack, and again by overlay_from() on top of it —
## which is why every assignment here REPLACES a key rather than assuming it
## is new.
func _apply(manifest: Dictionary, dir_path: String) -> bool:
	for name in manifest.get("sheets", {}):
		var entry: Dictionary = manifest["sheets"][name]
		var tex := _load_texture(dir_path.path_join(entry["sheet"]))
		if tex == null:
			error = "missing sheet %s" % entry["sheet"]
			return false
		_sheets[name] = {
			"texture": tex,
			"cell": Vector2i(entry["cell"][0], entry["cell"][1]),
			"frames": entry["frames"],
			"sequences": entry["sequences"],
		}

	for key in manifest.get("powerups", {}):
		var pu: Dictionary = manifest["powerups"][key]
		if pu.has("file"):
			var tex := _load_texture(dir_path.path_join(pu["file"]))
			if tex != null:
				_powerups[key] = {"texture": tex,
					"hotspot": Vector2i(pu["hotspot"][0], pu["hotspot"][1])}
		else:
			# 'random' is an animation over the other icons, not a still.
			_powerups[key] = {"steps": pu.get("steps", [])}

	for level in manifest.get("backgrounds", {}):
		var bg: Dictionary = manifest["backgrounds"][level]
		var tex := _load_texture(dir_path.path_join(bg["file"]))
		if tex != null:
			_backgrounds[int(level)] = tex

	# The schemes travel as text in the manifest, not as blobs: all 67 come to
	# 268 KB, scheme.gd already parses text, and a browser has no SCHEMES
	# folder — so this is the only way local play in a browser gets a level
	# list rather than the single built-in grid.
	for scheme_name in manifest.get("schemes", {}):
		_schemes[scheme_name] = manifest["schemes"][scheme_name]

	# The three campaigns travel the same way and for the same reason: text,
	# 514 to 824 bytes each, and a browser has no RES folder to read them from.
	for campaign_name in manifest.get("campaigns", {}):
		_campaigns[campaign_name] = manifest["campaigns"][campaign_name]

	# The help texts — CREDITS.BM and MANUAL.BM are the two the main menu
	# names, and the rest are the original's other help screens. Text again,
	# and for the third time the same reason: the screens that show them used
	# to open ../original-game/MANUAL.BM by path at draw time, which works on
	# the machine the disc is on and nowhere else.
	for help_name in manifest.get("help", {}):
		_help[help_name] = manifest["help"][help_name]

	# The screens. Every one is a 640x480 bitmap the original draws its own
	# widgets over — MAINMENU has its seven items painted in, and GLUE0..6 are
	# tiling wallpapers rather than screens.
	for name in manifest.get("screens", {}):
		var entry: Dictionary = manifest["screens"][name]
		var tex := _load_texture(dir_path.path_join(entry["file"]))
		if tex != null:
			_screens[String(name)] = tex

	for name in manifest.get("elements", {}):
		var el: Dictionary = manifest["elements"][name]
		var etex := _load_texture(dir_path.path_join(el["file"]))
		if etex != null:
			_elements[String(name)] = etex

	# The fonts, from the .FON files rather than from an ANI: KFONT.ANI turned
	# out to be digits only. tools/fonts.py has the format and how it was
	# established.
	for name in manifest.get("fonts", {}):
		var entry2: Dictionary = manifest["fonts"][name]
		var tex2 := _load_texture(dir_path.path_join(entry2["file"]))
		if tex2 != null:
			_fonts[String(name)] = {"texture": tex2,
				"height": int(entry2["height"]),
				"glyphs": entry2["glyphs"]}

	# The colour remap tables. Absent from a replacement art pack, which is why
	# the shader keeps the heuristic path — has_remap() is what selects.
	var remap: Dictionary = manifest.get("remap", {})
	if not remap.is_empty():
		var pal := _load_texture(dir_path.path_join(remap["palette"]))
		var lut := _load_texture(dir_path.path_join(remap["lut"]))
		var table := _load_texture(dir_path.path_join(remap["remap"]))
		if pal != null and lut != null and table != null:
			_remap = {"palette": pal, "lut": lut, "table": table,
				"players": int(remap.get("players", 10)),
				"mapped_count": int(remap.get("mapped_count", 0)),
				"mapped_first": int(remap.get("mapped_first", 0)),
				"mapped_last": int(remap.get("mapped_last", 0))}
		else:
			error = "the pack names colour remap tables it does not contain"
			return false

	loaded = true
	return true


# Read through FileAccess and decode from the buffer, rather than
# Image.load_from_file().
#
# load_from_file() reads the real filesystem, which does not exist in a browser
# — the web build's art lives inside the .pck. FileAccess handles res:// and
# real paths alike, so one code path serves both, and the export preset names
# the pack files explicitly so they are actually in the .pck.
#
# This was found by exporting: the first web build produced a 1.58 MB .pck with
# no art in it at all.
func _load_texture(path: String) -> Texture2D:
	var bytes := PackedByteArray()
	# From the container if it is loaded, by filename; otherwise off disk.
	var leaf := path.get_file()
	if _container != null and _container.has(leaf):
		bytes = _container.blob(leaf)
	elif FileAccess.file_exists(path):
		bytes = FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		return null
	var img := Image.new()
	if img.load_png_from_buffer(bytes) != OK:
		return null
	return ImageTexture.create_from_image(img)


func has_sheet(name: String) -> bool:
	return _sheets.has(name)


func sheet_names() -> Array:
	return _sheets.keys()


func texture_of(sheet: String) -> Texture2D:
	return _sheets[sheet]["texture"] if _sheets.has(sheet) else null


func frame_count(sheet: String) -> int:
	return (_sheets[sheet]["frames"] as Array).size() if _sheets.has(sheet) else 0


## Source rect of one frame within its sheet.
func frame_rect(sheet: String, index: int) -> Rect2:
	var frames: Array = _sheets[sheet]["frames"]
	var r: Array = frames[index]["rect"]
	return Rect2(r[0], r[1], r[2], r[3])


## The frame's own anchor. Subtract it from a world position to get the
## top-left at which to draw.
func frame_hotspot(sheet: String, index: int) -> Vector2:
	var frames: Array = _sheets[sheet]["frames"]
	var h: Array = frames[index]["hotspot"]
	return Vector2(h[0], h[1])


func sequence_names(sheet: String) -> Array:
	return (_sheets[sheet]["sequences"] as Dictionary).keys() if _sheets.has(sheet) else []


func has_sequence(sheet: String, seq: String) -> bool:
	return _sheets.has(sheet) and (_sheets[sheet]["sequences"] as Dictionary).has(seq)


## The frame indices of a named sequence, in playback order.
func sequence_steps(sheet: String, seq: String) -> Array:
	if not has_sequence(sheet, seq):
		return []
	var steps: Array = _sheets[sheet]["sequences"][seq]["steps"]
	var out: Array = []
	for s in steps:
		out.append(int(s[0]))
	return out


## Which frame of a sequence to show, given how many ticks it has been running.
## Loops. The sim is the clock, so this takes ticks and not seconds.
func sequence_frame(sheet: String, seq: String, tick: int) -> int:
	var steps := sequence_steps(sheet, seq)
	if steps.is_empty():
		return -1
	return steps[posmod(tick, steps.size())]


## Which sheet carries a named sequence, or "". The 24 death animations are
## spread over seventeen XPLODE sheets — "die green 13" is in xplode11 — so
## the caller has a name and needs the sheet.
func sheet_with_sequence(seq: String) -> String:
	for name in _sheets:
		if (_sheets[name]["sequences"] as Dictionary).has(seq):
			return String(name)
	return ""


func powerup_texture(key: String) -> Texture2D:
	if _powerups.has(key) and _powerups[key].has("texture"):
		return _powerups[key]["texture"]
	return null


func powerup_keys() -> Array:
	return _powerups.keys()


func background(level: int) -> Texture2D:
	return _backgrounds.get(level, null)


func background_count() -> int:
	return _backgrounds.size()


## The scheme names the pack carries, sorted. Empty for a pack built before
## schemes were included, which the menu treats as "only the built-in grid".
func scheme_names() -> Array:
	var names: Array = _schemes.keys()
	names.sort()
	return names


## The campaigns this pack carries, by name.
func campaign_names() -> Array:
	var out := _campaigns.keys()
	out.sort()
	return out


func campaign_text(name: String) -> String:
	return String(_campaigns.get(name.to_upper(), ""))


## One of the original's `*.BM` help texts, by stem — "CREDITS", "MANUAL".
## Empty when the pack does not carry it.
func help_text(name: String) -> String:
	return String(_help.get(name.to_upper(), ""))


func scheme_text(name: String) -> String:
	return String(_schemes.get(name.to_upper(), ""))


func has_scheme(name: String) -> bool:
	return _schemes.has(name.to_upper())


func has_screen(name: String) -> bool:
	return _screens.has(name)


func screen(name: String) -> Texture2D:
	return _screens.get(name, null)


func screen_names() -> Array:
	var names: Array = _screens.keys()
	names.sort()
	return names


func has_element(name: String) -> bool:
	return _elements.has(name)


func element(name: String) -> Texture2D:
	return _elements.get(name, null)


func element_names() -> Array:
	var names: Array = _elements.keys()
	names.sort()
	return names


func has_font(name: String) -> bool:
	return _fonts.has(name)


func font_names() -> Array:
	return _fonts.keys()


## A font as {texture, height, glyphs}, where glyphs maps a character code to
## [x, width] in the texture. scripts/render/bitfont.gd draws with it.
func font(name: String) -> Dictionary:
	return _fonts.get(name, {})


## Does this pack carry the original's own recolour tables?
##
## False for any pack built without `COLOR.PAL` and the ten `.RMP` files —
## a replacement art set, or a disc dump missing them, which is what the port
## had until 2026-09-02. The shader falls back to fpc_atomic's heuristic.
func has_remap() -> bool:
	return not _remap.is_empty()


func remap_palette() -> Texture2D:
	return _remap.get("palette", null)


func remap_lut() -> Texture2D:
	return _remap.get("lut", null)


func remap_table() -> Texture2D:
	return _remap.get("table", null)


## How many of the 256 palette indices the .RMP files recolour, and the range
## they span. 73, over 100..174, on the original's own files.
func remap_info() -> Dictionary:
	return {
		"count": int(_remap.get("mapped_count", 0)),
		"first": int(_remap.get("mapped_first", 0)),
		"last": int(_remap.get("mapped_last", 0)),
		"players": int(_remap.get("players", 0)),
	}


## Where to look for a pack.
##
## res:// FIRST, because that is where an exported build's art is and a browser
## has no filesystem to fall back to. Running from source, res:// resolves to
## the project directory and finds the same files, so one order serves both.
##
## AB_PACK overrides it, which is how a second pack — the free replacement set —
## gets tested without moving anything.
static func default_dir() -> String:
	var env := OS.get_environment("AB_PACK")
	if not env.is_empty():
		return env
	# The container ships in an export; the loose directory is what a source
	# checkout has. Either resolves to the same name here.
	if FileAccess.file_exists("res://data/packs/cd.bin") \
			or FileAccess.file_exists("res://data/packs/cd/pack.json"):
		return "res://data/packs/cd"
	return ProjectSettings.globalize_path("res://data/packs/cd")
