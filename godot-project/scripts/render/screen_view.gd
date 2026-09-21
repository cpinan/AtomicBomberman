# Draws whichever screen scripts/app/screens.gd says is up.
#
# All the art is the original's. Nothing here invents a layout: the main menu's
# items are painted into MAINMENU.PCX and this only puts a cursor beside them,
# at positions measured from the art; the setup and options screens are drawn
# on the original's own GLUE wallpapers in the original's own font; and the
# transition is HEADWIPE.ANI, 211 frames of a 73x73 bomberman, run across the
# screen.
#
# WHAT IS NOT THE ORIGINAL'S. The setup and options screens' LAYOUT — where in
# the wallpaper each row sits — is this port's, because those screens are drawn
# by code in the original and the code is not read yet. The words, the option
# set, the value names and the slot states are all the disc's
# (`docs/BUGS.md` Q5 and `MESSAGES.TXT` 220-268).
extends Node2D

const Const_ := preload("res://scripts/core/const.gd")
const Messages_ := preload("res://scripts/core/messages.gd")
const Screens_ := preload("res://scripts/app/screens.gd")
const Roulette_ := preload("res://scripts/app/roulette.gd")
const Values_ := preload("res://scripts/core/values.gd")
const Menu_ := preload("res://scripts/app/menu.gd")
const BitFont_ := preload("res://scripts/render/bitfont.gd")
const Pack_ := preload("res://scripts/render/pack.gd")
const Scheme_ := preload("res://scripts/core/scheme.gd")
const Types_ := preload("res://scripts/core/types.gd")

var screens: Screens_ = null
var menu: Menu_ = null
var pack: Pack_ = null

## The match, for the results screen. Null until one has been played.
var the_match = null

## The wheel, when one is spinning. main.gd owns it.
var roulette: Roulette_ = null

## The options list's geometry, named so tests/render_screens.gd can do the
## arithmetic that caught the list running off the bottom.
const OPTIONS_TOP := 36.0
const OPTIONS_ROW_H := 21.0
const KEYS_TOP := 46.0

var font: BitFont_ = null
var small: BitFont_ = null

## Which wallpaper each screen is drawn on. GLUE0's grid of bomberman heads is
## the setup screen's, which is what it looks made for; GLUE3's plain plate is
## the options screen's, because a busy backdrop under thirteen rows of text is
## unreadable.
const WALLPAPER := {
	Screens_.Screen.SETUP: "glue0",
	Screens_.Screen.OPTIONS: "glue3",
	# Both text pages want a QUIET backdrop. GLUE2's two-foot letters and
	# GLUE4's cereal boxes make twenty lines of credits unreadable, which the
	# first version proved.
	Screens_.Screen.ABOUT: "glue6",
	Screens_.Screen.MANUAL: "glue3",
}

## Colours. The menu's yellow is sampled from MAINMENU.PCX's own lettering.
const INK := Color(1.0, 0.91, 0.38)
const INK_DIM := Color(0.62, 0.60, 0.52)
const INK_HOT := Color(1.0, 1.0, 0.85)
const SHADOW := Color(0.0, 0.0, 0.0, 0.6)

## How many lines a text page shows. The credits are longer; scrolling them is
## Phase 11's problem.
## As many lines as either text has. It was 24 — one screenful and three
## spare — which is why the Online Manual appeared not to scroll: MANUAL.BM is
## 390 lines and CREDITS.BM 157, and the reader was being shown the first 24 of
## them. A cap is still here as a guard against a pathological file, not as a
## page size.
const MAX_PAGE_LINES := 4000


func _ready() -> void:
	font = BitFont_.new()
	small = BitFont_.new()
	if pack != null:
		font.load_from(pack, "font1")
		small.load_from(pack, "font6")


func _draw() -> void:
	if screens == null:
		return
	if pack == null or not pack.loaded:
		_draw_no_pack()
		return

	match screens.screen:
		Screens_.Screen.TITLE:
			_draw_full("title")
			_blink("Press any key", Const_.SCREEN_H - 54)
		Screens_.Screen.MAIN_MENU:
			_draw_main_menu()
		Screens_.Screen.SETUP:
			_draw_setup()
		Screens_.Screen.OPTIONS:
			_draw_options()
		Screens_.Screen.ABOUT:
			_draw_text_page("About Bomberman", _about_lines())
		Screens_.Screen.MANUAL:
			_draw_text_page("Online Manual", _manual_lines())
		Screens_.Screen.RESULTS:
			_draw_results()
		Screens_.Screen.VICTORY, Screens_.Screen.DRAW:
			_draw_victory()
		Screens_.Screen.ROULETTE:
			_draw_roulette()

	# WHY SOMETHING WAS REFUSED, wherever it was refused. menu.refusal was set
	# by validate() and by _start_from_menu() and then drawn by nothing at all,
	# so a game that would not start simply did not start.
	var why := screens.refusal
	if why.is_empty() and menu != null \
			and (screens.screen == Screens_.Screen.SETUP
				or screens.screen == Screens_.Screen.OPTIONS):
		why = menu.refusal
	if not why.is_empty():
		_shadowed(font, Vector2(24, Const_.SCREEN_H - 28), why,
			Color(1, 0.5, 0.45))
	if screens.wiping():
		_draw_wipe()


# ---------------------------------------------------------------------------
# The screens
# ---------------------------------------------------------------------------
func _draw_main_menu() -> void:
	_draw_full("mainmenu")
	# The items are IN the art, so all that is drawn here is the cursor. Its
	# frames are MISC.ANI's `cursor1` — POINTER1..4, a four-step animation.
	var rect := Screens_.menu_item_rect(screens.cursor)
	# Far enough left to clear the painted text. The pointer's hotspot is at
	# its bottom tip, so it is placed on the item's baseline.
	var at := Vector2(rect.position.x - 22, rect.position.y + rect.size.y - 2)
	if pack.has_sequence("misc", "cursor1"):
		var index := pack.sequence_frame("misc", "cursor1", screens.age / 4)
		if index >= 0:
			var src := pack.frame_rect("misc", index)
			var hot := pack.frame_hotspot("misc", index)
			draw_texture_rect_region(pack.texture_of("misc"),
				Rect2((at - hot).round(), src.size), src, Color.WHITE)
	else:
		# No art: a triangle, so the selection is still visible.
		draw_colored_polygon([at + Vector2(-10, -12), at + Vector2(-10, 0),
			at + Vector2(0, -6)], INK)

	# The games heard on the LAN, beside the menu — MESSAGES.TXT 60's own
	# heading, 62's own row, 61 when there are none. The list only appears
	# while the cursor is on "Join Network Game", because that is the only
	# item it means anything to.
	if screens.cursor == Screens_.Menu.JOIN_NETWORK:
		_draw_net_games()


## MESSAGES.TXT 60-62: the server browser the disc describes, over a beacon
## this port invented because a WebSocket cannot be discovered.
## scripts/net/discovery.gd.
func _draw_net_games() -> void:
	# BELOW the items, not over them. MAINMENU.PCX has its seven items painted
	# into the art from y=115 to y=355, and the first version of this drew the
	# list at y=352 — straight through "Exit Bomberman". The band under them is
	# the only empty part of the screen, and it gets a panel of its own so the
	# text reads over the starfield.
	var x := 300.0
	var y := 392.0
	# One extra row for the code-entry line below the LAN list — invented,
	# same as the lobby screen: there's nothing on the disc a room code could
	# have come from, because the original never left the LAN.
	draw_rect(Rect2(x - 12, y - 22, Const_.SCREEN_W - x - 4, 100),
		Color(0, 0, 0, 0.55))
	_shadowed(small, Vector2(x, y), Messages_.NET_GAMES_AVAILABLE, INK)
	y += 18.0
	if screens.net_games.is_empty():
		_shadowed(small, Vector2(x, y), Messages_.NET_GAMES_NONE,
			Color(1, 0.7, 0.5))
		y += 16.0
	else:
		for i in mini(screens.net_games.size(), 3):
			var game = screens.net_games[i]
			var chosen: bool = i == screens.net_cursor
			_shadowed(small, Vector2(x, y),
				("> " if chosen else "  ") + game.row(Messages_.NET_GAME_ROW),
				Color(1, 0.95, 0.6) if chosen else INK)
			y += 16.0

	var code_line := "Or type a room code: %s_" % screens.typed_code
	if screens.looking_up:
		code_line = "Looking up %s…" % screens.typed_code
	_shadowed(small, Vector2(x, y), code_line,
		Color(1, 0.95, 0.6) if not screens.typed_code.is_empty() else INK_DIM)


func _draw_setup() -> void:
	_tile_wallpaper(WALLPAPER.get(Screens_.Screen.SETUP, "glue0"))
	_dim(0.45)
	_shadowed(font, Vector2(28, 18), "Who is playing", INK)

	if menu == null:
		return
	# Ten slots in two columns of five, each with the KFACE head in that
	# player's colour and its state from MESSAGES.TXT 220-224.
	for i in menu.slots.size():
		var col: int = i / 5
		var row: int = i % 5
		var x := 40.0 + col * 300.0
		var y := 70.0 + row * 74.0
		var chosen: bool = menu.in_slots and i == menu.slot_cursor
		if chosen:
			draw_rect(Rect2(x - 10, y - 6, 280, 66), Color(1, 0.95, 0.5, 0.14))
		_draw_marker(i, Vector2(x + 20, y + 26))
		_shadowed(font, Vector2(x + 56, y + 4),
			"Player %d" % (i + 1), INK if chosen else INK_DIM)
		_shadowed(font, Vector2(x + 56, y + 26), menu.slot_text(i),
			INK_HOT if chosen else INK)

	# SHORT ENOUGH TO FIT. The long version — "up/down to move, left/right to
	# change, Return to start" — already reached x=610 in the small font, and
	# adding INPUT.BM's own T ran it off the right of the screen.
	var hint := "arrows choose, Return starts, Ctrl-A all AI"
	if menu.team_play:
		# INPUT.BM names the key on this screen, so this screen says so.
		hint = "arrows choose, Return starts, T teams, Ctrl-A all AI"
	_shadowed(small, Vector2(28, Const_.SCREEN_H - 26), hint, INK_DIM)
	_shadowed(font, Vector2(Const_.SCREEN_W - 210, 18),
		"%d playing" % menu.seats(), INK)


## One player's marker on the setup screen.
##
## A disc in that player's colour, NOT `KFACE.ANI`. This screen drew kface
## first, for the same reason the status band did — 40x40, four directional
## frames, loaded first of all 76 animations in MASTER.ALI — and for the same
## reason it was wrong: it is a photograph of the lead programmer's head, the
## Kurt-head easter egg player. `docs/BUGS.md` D26.
func _draw_marker(slot: int, at: Vector2) -> void:
	var colour := Const_.player_colour_f(slot)
	draw_circle(at, 15.0, Color(0, 0, 0, 0.5))
	draw_circle(at, 13.0, colour)
	# A ring in the team's colour when teams are on, from MISC.ANI's own
	# teamring0 and teamring1.
	if menu != null and menu.team_play:
		# The team this slot is actually on, which INPUT.BM's 'T' can change —
		# not the default split, which is all this used to be able to show.
		var seq := "teamring%d" % (0 if menu.team_of(slot) == 0 else 1)
		if pack.has_sequence("misc", seq):
			var index := pack.sequence_frame("misc", seq, 0)
			if index >= 0:
				var src := pack.frame_rect("misc", index)
				draw_texture_rect_region(pack.texture_of("misc"),
					Rect2((at - src.size / 2.0).round(), src.size), src,
					Color(1, 1, 1, 0.9))


func _draw_options() -> void:
	_tile_wallpaper(WALLPAPER.get(Screens_.Screen.OPTIONS, "glue3"))
	_dim(0.55)
	if menu == null:
		return
	# The keyboard-definitions screen is a screen, not a row: it replaces this
	# list while it is open. MESSAGES.TXT 1100-1140.
	if menu.in_keys:
		_draw_key_definitions()
		return

	_shadowed(font, Vector2(28, 14), "Options", INK)

	# ROW PITCH. Nineteen rows at 26 px ran to y=514 on a 480-line screen and
	# straight through the hint at the bottom — the options list grew from
	# thirteen rows to twenty as the disc's own settings were implemented. At
	# 22 from y=40 the last row ends at 436, clear of the hint.
	var y := OPTIONS_TOP
	for item in menu.item_count():
		if item == Menu_.Item.SLOTS:
			continue          # the slots have their own screen
		var chosen: bool = item == menu.selected() and not menu.in_slots
		var colour := INK_HOT if chosen else INK
		if chosen:
			draw_rect(Rect2(20, y - 3, Const_.SCREEN_W - 40, 20),
				Color(1, 0.95, 0.5, 0.13))
		_shadowed(font, Vector2(32, y), menu.label_of(item), colour)
		if not menu.is_action(item):
			_shadowed(font, Vector2(360, y), menu.value_text(item), colour)
			if item == Menu_.Item.LEVEL and chosen:
				_draw_level_preview()
		y += OPTIONS_ROW_H

	_shadowed(small, Vector2(28, Const_.SCREEN_H - 26),
		"Escape returns to the menu", INK_DIM)


## A small live thumbnail of the highlighted level's own field art, so
## picking a level shows what it looks like rather than a name alone.
## "Random Each Game" (menu.level == Menu_.LEVEL_RANDOM) has no one
## background to show, so nothing is drawn for it.
const LEVEL_PREVIEW_RECT := Rect2(508, 34, 104, 78)

## Colours for the brick layout drawn over the background: undestructible
## walls and destructible bricks read as two shades, blank floor left
## transparent so the background shows through.
const PREVIEW_SOLID := Color(0.15, 0.15, 0.18, 0.95)
const PREVIEW_BRICK := Color(0.55, 0.38, 0.2, 0.95)

## scheme_name() -> parsed Scheme_, so switching the highlighted level does
## not re-parse its scheme text every single frame.
var _preview_schemes: Dictionary = {}


func _draw_level_preview() -> void:
	if menu.level == Menu_.LEVEL_RANDOM or pack == null:
		return
	var tex := pack.background(menu.level)
	if tex == null:
		return
	draw_rect(LEVEL_PREVIEW_RECT.grow(2), Color(1, 0.95, 0.5, 0.9), false, 2.0)
	draw_texture_rect(tex, LEVEL_PREVIEW_RECT, false)

	var scheme := _scheme_for_preview()
	if scheme == null:
		return
	var cell_w := LEVEL_PREVIEW_RECT.size.x / Const_.FIELD_W
	var cell_h := LEVEL_PREVIEW_RECT.size.y / Const_.FIELD_H
	for y in Const_.FIELD_H:
		for x in Const_.FIELD_W:
			var kind: int = scheme.cell(x, y)
			if kind == Types_.Brick.BLANK:
				continue
			var colour := PREVIEW_SOLID if kind == Types_.Brick.SOLID \
				else PREVIEW_BRICK
			var r := Rect2(
				LEVEL_PREVIEW_RECT.position + Vector2(x * cell_w, y * cell_h),
				Vector2(cell_w, cell_h))
			draw_rect(r, colour)


## Parses (and caches) the highlighted level's scheme, for the layout drawn
## over its background art. Null when the pack has no scheme text for it —
## the preview then falls back to the background alone.
func _scheme_for_preview() -> Scheme_:
	var name := menu.scheme_name()
	if _preview_schemes.has(name):
		return _preview_schemes[name]
	var scheme := Scheme_.new()
	var ok: bool
	if menu.built_in_selected():
		ok = scheme.parse_text(_builtin_grid_text(), name)
	else:
		ok = scheme.parse_text(pack.scheme_text(name), name)
	_preview_schemes[name] = scheme if ok else null
	return _preview_schemes[name]


## The classic pillar grid main.gd's `_builtin_scheme()` falls back to when no
## scheme is chosen — duplicated here (rather than reached through main.gd)
## because this is a menu-only preview with no round to attach a real Scheme_
## to. Starts and powerups are required for parse_text() to accept the text
## even though the preview only reads the row layout back out.
func _builtin_grid_text() -> String:
	var lines := PackedStringArray()
	lines.append("-V,2")
	lines.append("-N,Built-in grid (10)")
	lines.append("-B,90")
	for y in Const_.FIELD_H:
		var row := ""
		for x in Const_.FIELD_W:
			row += "#" if (x % 2 == 1 and y % 2 == 1) else ":"
		lines.append("-R,%2d,%s" % [y, row])
	var starts := [[0, 0], [14, 10], [0, 10], [14, 0], [6, 4],
		[8, 0], [12, 4], [2, 6], [10, 8], [6, 10]]
	for p in Const_.PLAYER_COUNT:
		lines.append("-S,%d,%d,%d,%d" % [p, starts[p][0], starts[p][1], p % 2])
	for i in Const_.POWERUP_COUNT:
		lines.append("-P,%2d, 0,0, 0, 0,x" % i)
	return "\n".join(lines)


## MESSAGES.TXT 1100-1140's own screen: twelve bindings and a restore row.
func _draw_key_definitions() -> void:
	_shadowed(font, Vector2(28, 14), Messages_.KEY_DEFINITIONS, INK)
	var y := KEYS_TOP
	for row in Menu_.KEY_ROWS:
		if row == Menu_.KEY_RESTORE_ROW:
			y += 8.0
		var chosen: bool = row == menu.key_cursor
		var colour := INK_HOT if chosen else INK
		if chosen:
			draw_rect(Rect2(20, y - 3, Const_.SCREEN_W - 40, 20),
				Color(1, 0.95, 0.5, 0.13))
		_shadowed(font, Vector2(32, y), menu.key_row_label(row), colour)
		var value := menu.key_row_value(row)
		if not value.is_empty():
			_shadowed(font, Vector2(360, y), value, colour)
		y += OPTIONS_ROW_H
	if not menu.key_notice.is_empty():
		_shadowed(small, Vector2(32, y + 10), menu.key_notice,
			Color(1, 0.8, 0.4))
	_shadowed(small, Vector2(28, Const_.SCREEN_H - 26),
		"Return to rebind, Escape to go back", INK_DIM)


func _draw_results() -> void:
	_draw_full("results")
	if the_match == null:
		return
	# RESULTS.PCX leaves its middle clear. MESSAGES.TXT 900-928 is the
	# statistics file's own header and its nineteen counters; what the port can
	# fill in is the match, so it shows that and says nothing it does not know.
	var y := 120.0
	_shadowed(font, Vector2(120, 92),
		Messages_.fmt(Messages_.TO_WIN_MATCH,
			[the_match.wins_to_win, Messages_.WINS]), INK)
	for slot in Const_.PLAYER_COUNT:
		var wins: int = the_match.wins_of(slot)
		if wins <= 0 and not the_match.team_play:
			continue
		_shadowed(font, Vector2(140, y), "Player %d" % (slot + 1),
			Const_.player_colour_f(slot).lerp(Color.WHITE, 0.35))
		_shadowed(font, Vector2(330, y), str(wins), INK)
		y += 24.0
	_shadowed(small, Vector2(120, Const_.SCREEN_H - 40),
		"Press Return", INK_DIM)


func _draw_victory() -> void:
	var name := screens.victory_screen_name(
		the_match != null and the_match.team_play)
	if pack.has_screen(name):
		_draw_full(name)
	else:
		_draw_full("draw")
	var line := ""
	if screens.was_draw:
		line = "DRAW"
	elif screens.champion_team >= 0:
		line = "%s %d WINS" % [Messages_.SLOT_TEAM, screens.champion_team]
	else:
		# MESSAGES.TXT 36 is the disc's own sentence for this — "PLAYER %u WINS
		# THE MATCH!" — rather than a line of the port's.
		line = Messages_.fmt(Messages_.M[36], [screens.champion_slot + 1])
	_shadowed(font, Vector2(0, 34), line, INK, true)
	_blink("Press Return", Const_.SCREEN_H - 44)


# The Goldman roulette. The ONLY screen whose layout came out of the data
# rather than out of this file: VALUELST 1000, 1002, 1004, 1006 and 1010 give
# the wheel's centre, its two radii, its resolution, its Lissajous parameters
# and how long the winner twinkles, and 805 gives the title's position.
# scripts/app/roulette.gd quotes all of them.
func _draw_roulette() -> void:
	_draw_full("roulette")
	if roulette == null:
		return

	# The title, at resource 805's own position.
	var title_at := _position(Const_.Res.POS_ROULETTE_TITLE,
		Vector2(320, 30))
	_shadowed_at(font, title_at, Messages_.ROULETTE, INK, true)

	# Fourteen powerup icons around the ellipse. POWERS.ANI draws all of them,
	# including `power clog` — the fourteenth, which is the punishment.
	for i in Roulette_.WHEEL_SIZE:
		var at: Vector2 = roulette.icon_position(i)
		var seq := Roulette_.icon_sequence(i)
		if not pack.has_sequence("powers", seq):
			continue
		var index := pack.sequence_frame("powers", seq, 0)
		if index < 0:
			continue
		var src := pack.frame_rect("powers", index)
		var chosen: bool = roulette.result == i \
			and roulette.phase >= Roulette_.Phase.TWINKLING
		var tint := Color.WHITE
		if chosen:
			# The twinkle, resource 1010's five seconds of it.
			var pulse := (sin(float(roulette.age) * 0.4) + 1.0) * 0.5
			tint = Color(1.0, 1.0, 0.6 + 0.4 * pulse)
			draw_circle(at, 30.0, Color(1, 0.95, 0.5, 0.18 + 0.14 * pulse))
		elif roulette.result >= 0:
			tint = Color(0.55, 0.55, 0.6)
		draw_texture_rect_region(pack.texture_of("powers"),
			Rect2((at - src.size / 2.0).round(), src.size), src, tint)

	# The pointer at the top of the wheel, which is what reads the result.
	var centre: Vector2 = roulette.centre()
	var top := Vector2(centre.x, centre.y - roulette.radii().y - 26.0)
	draw_colored_polygon([top + Vector2(-9, -10), top + Vector2(9, -10),
		top + Vector2(0, 6)], INK)

	if roulette.result >= 0:
		# "The Gold Player has <powerup> for the next match!!" — MESSAGES.TXT
		# 790 and 791 with the powerup's own name from 800-813.
		var lines := roulette.announcement()
		var y := Const_.SCREEN_H - 88.0
		_shadowed(font, Vector2(0, y), "%s %s" % [lines[0], lines[1]],
			INK, true)
		_shadowed(font, Vector2(0, y + 22.0), lines[2],
			Color(1, 0.5, 0.45) if roulette.punishment() else INK, true)
	if roulette.finished():
		_blink("Press Return", Const_.SCREEN_H - 40)


## A screen position from VALUELST's own layout table: (x, y, pitch, width).
func _position(res: int, fallback: Vector2) -> Vector2:
	var v: Variant = Values_.V.get(res, null)
	if v is Array and (v as Array).size() >= 2:
		return Vector2(float(v[0]), float(v[1]))
	return fallback


## Like _shadowed, but centred on a position's own x rather than the screen's.
func _shadowed_at(which: BitFont_, at: Vector2, text: String, colour: Color,
		centred: bool = false) -> void:
	if which == null or not which.loaded:
		_shadowed(which, at, text, colour, centred)
		return
	var x := at.x - (which.width_of(text) / 2.0 if centred else 0.0)
	which.draw(self, Vector2(x + 1, at.y + 1), text, SHADOW)
	which.draw(self, Vector2(x, at.y), text, colour)


## A page of the disc's own text — CREDITS.BM or MANUAL.BM.
##
## SCROLLED, because both are far longer than a screen: the manual is the whole
## instruction booklet. It used to draw the first 23 lines and stop, so
## everything past the first screenful was unreachable.
func _draw_text_page(title: String, lines: Array) -> void:
	_tile_wallpaper(WALLPAPER.get(screens.screen, "glue6"))
	_dim(0.74)
	_shadowed(font, Vector2(28, 14), title, INK)

	var rows := page_rows()
	var first: int = clampi(screens.text_scroll, 0,
		maxi(lines.size() - rows, 0))
	var y := 48.0
	for i in range(first, mini(first + rows, lines.size())):
		_shadowed(small, Vector2(32, y), String(lines[i]), INK)
		y += 18.0

	# Where you are, and which way there is more. Without this a reader cannot
	# tell a short page from a stuck one.
	#
	# ON THE TITLE ROW, not beside the hint at the bottom: the hint grew when
	# page up and page down were added and the two ran into each other.
	var last: int = mini(first + rows, lines.size())
	_shadowed(small, Vector2(Const_.SCREEN_W - 130, 18),
		"%d-%d of %d" % [first + 1, last, lines.size()], INK_DIM)
	var hint := "Return goes back"
	if lines.size() > rows:
		hint = "up/down or page up/down to scroll, Return goes back"
	_shadowed(small, Vector2(28, Const_.SCREEN_H - 26), hint, INK_DIM)


## How many lines of a text page fit between the title and the footer.
static func page_rows() -> int:
	return int((Const_.SCREEN_H - 40 - 48) / 18.0)


## How many lines the page that is up has, for the scroll clamp. Cached: this
## is asked on every keypress and the answer only changes with the screen.
var _page_cache: Dictionary = {}


func page_line_count() -> int:
	if screens == null:
		return 0
	if not _page_cache.has(screens.screen):
		match screens.screen:
			Screens_.Screen.ABOUT:
				_page_cache[screens.screen] = _about_lines().size()
			Screens_.Screen.MANUAL:
				_page_cache[screens.screen] = _manual_lines().size()
			_:
				_page_cache[screens.screen] = 0
	return int(_page_cache[screens.screen])


# ---------------------------------------------------------------------------
# Pieces
# ---------------------------------------------------------------------------
func _draw_full(name: String) -> void:
	var tex := pack.screen(name)
	if tex != null:
		draw_texture(tex, Vector2.ZERO)
	else:
		draw_rect(Rect2(0, 0, Const_.SCREEN_W, Const_.SCREEN_H),
			Color(0.05, 0.05, 0.09))


## GLUE0..GLUE6 are tiling wallpapers, so they tile.
func _tile_wallpaper(name: String) -> void:
	var tex := pack.screen(name)
	if tex == null:
		draw_rect(Rect2(0, 0, Const_.SCREEN_W, Const_.SCREEN_H),
			Color(0.05, 0.05, 0.09))
		return
	var size := tex.get_size()
	var x := 0.0
	while x < Const_.SCREEN_W:
		var y := 0.0
		while y < Const_.SCREEN_H:
			draw_texture(tex, Vector2(x, y))
			y += size.y
		x += size.x


func _dim(amount: float) -> void:
	draw_rect(Rect2(0, 0, Const_.SCREEN_W, Const_.SCREEN_H),
		Color(0, 0, 0, amount))


## Text with a one-pixel shadow, which is what keeps it readable over art.
func _shadowed(which: BitFont_, at: Vector2, text: String, colour: Color,
		centred: bool = false) -> void:
	if which == null or not which.loaded:
		# No packed font: fall back so a screen is never blank and silent.
		var fallback := ThemeDB.fallback_font
		var x := at.x
		if centred:
			x = (Const_.SCREEN_W
				- fallback.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT,
					-1, 16).x) / 2.0
		draw_string(fallback, Vector2(x, at.y + 14), text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 16, colour)
		return
	if centred:
		which.draw(self, Vector2(
			(Const_.SCREEN_W - which.width_of(text)) / 2.0 + 1,
			at.y + 1), text, SHADOW)
		which.draw_centred(self, Const_.SCREEN_W / 2.0, at.y, text, colour)
		return
	which.draw(self, at + Vector2(1, 1), text, SHADOW)
	which.draw(self, at, text, colour)


## A line that fades in and out, for "press any key".
func _blink(text: String, y: float) -> void:
	var phase := (sin(float(screens.age) * 0.13) + 1.0) * 0.5
	_shadowed(font, Vector2(0, y), text,
		Color(1.0, 0.95, 0.55, 0.35 + 0.65 * phase), true)


## HEADWIPE.ANI across the screen. 211 frames of a 73x73 bomberman — named a
## wipe, and long enough to be one: it runs left to right while the screen
## behind it changes, which is what the name describes and what the frame count
## is for.
func _draw_wipe() -> void:
	if not pack.has_sheet("headwipe"):
		return
	var progress := screens.wipe_progress()
	var frames := pack.frame_count("headwipe")
	if frames <= 0:
		return
	var index := clampi(int(progress * float(frames)), 0, frames - 1)
	var src := pack.frame_rect("headwipe", index)
	var hot := pack.frame_hotspot("headwipe", index)
	var x := -80.0 + progress * (Const_.SCREEN_W + 160.0)
	var y := Const_.SCREEN_H * 0.62
	# A dark band travels with it, so the change behind is covered rather than
	# merely accompanied.
	var band := 150.0
	draw_rect(Rect2(x - band, 0, band * 2.0, Const_.SCREEN_H),
		Color(0, 0, 0, 0.55 * (1.0 - absf(progress - 0.5) * 2.0)))
	draw_texture_rect_region(pack.texture_of("headwipe"),
		Rect2((Vector2(x, y) - hot).round(), src.size), src, Color.WHITE)


func _draw_no_pack() -> void:
	draw_rect(Rect2(0, 0, Const_.SCREEN_W, Const_.SCREEN_H),
		Color(0.05, 0.05, 0.09))
	var f := ThemeDB.fallback_font
	draw_string(f, Vector2(24, 60), "no asset pack — run tools/pack_assets.py",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 0.6, 0.4))
	if screens != null:
		draw_string(f, Vector2(24, 90), "screen: %d" % screens.screen,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.8, 0.8, 0.9))


func _about_lines() -> Array:
	# CREDITS.BM is the original's own credits text.
	return _bm_lines("CREDITS.BM", [
		"Atomic Bomberman, Interplay Productions, 1997.",
		"This is a port to Godot 4. The art, audio, level data and",
		"tuning tables are the original's and are not redistributed.",
	])


func _manual_lines() -> Array:
	return _bm_lines("MANUAL.BM", ["MANUAL.BM was not found."])


## The `*.BM` files are the original's own help pages — MESSAGES.TXT 610 gives
## their filespec as "*.BM" and 600 heads the list, and CREDITS.BM is the real
## credits: Alan Pavlish, Jeremy Airey, Brian McInerny, Kurt W. Dekker.
##
## Their markup is small and this honours what it can:
##
##   TAB           indentation, expanded to four spaces
##   <IMGNAME>     place an image. CREDBAR, JERM, KURT and KURTHEAD are all
##                 PCX files in RES/, so the tag names real art — the tag is
##                 dropped here rather than drawn, and that is a gap rather
##                 than a decision.
##   *****         a rule, dropped
func _bm_lines(name: String, fallback: Array) -> Array:
	# FROM THE PACK first, which is where the text now travels. Reading the
	# file by path still works and is kept for a checkout that has the disc
	# beside it but no rebuilt pack, but it cannot be the only source: a built
	# game has no ../original-game to open, so About Bomberman and the Online
	# Manual both showed their three-line stub.
	var text := ""
	if pack != null:
		text = pack.help_text(name.get_basename())
	if text.is_empty():
		var path := ProjectSettings.globalize_path("res://").path_join(
			"../original-game").path_join(name).simplify_path()
		if not FileAccess.file_exists(path):
			return fallback
		text = FileAccess.get_file_as_string(path)
	var out: Array = []
	var blanks := 0
	for raw in text.replace("\r", "").split("\n"):
		var line := String(raw).replace("\t", "    ")
		# Drop the image directives, which name art rather than text.
		while true:
			var open_at := line.find("<")
			var close_at := line.find(">", open_at + 1)
			if open_at < 0 or close_at < 0:
				break
			line = line.substr(0, open_at) + line.substr(close_at + 1)
		line = line.strip_edges(false, true)
		if line.begins_with("*****"):
			continue
		if line.strip_edges().is_empty():
			# Runs of blank lines are layout for a scrolling credit roll and
			# waste a page here, so at most one survives.
			blanks += 1
			if blanks > 1:
				continue
		else:
			blanks = 0
		out.append(line.substr(0, 76))
		if out.size() >= MAX_PAGE_LINES:
			break
	# Trailing blank lines are a page of nothing to scroll through.
	while not out.is_empty() and String(out[out.size() - 1]).strip_edges() \
			.is_empty():
		out.resize(out.size() - 1)
	return out
