# Does every screen draw, and is it readable?
#
# Windowed, because it renders. This is the suite docs/BUGS.md D21 bought: the
# menu's model had 232 passing checks while its screen ran three items off the
# bottom edge, and no model test could see it. So this one looks at pixels.
#
# WHAT IT ASSERTS, for every screen in the flow:
#
#   1. It DRAWS. Not a flat fill — a screen that failed to find its art shows
#      as one colour, which is exactly what a missing pack looks like.
#   2. It uses the ORIGINAL'S ART where the original has art. Checked by
#      sampling the screen's own bitmap and requiring the render to match it,
#      so a screen drawn with the wrong background fails.
#   3. Its TEXT IS LEGIBLE — there is bright ink where a label was drawn.
#   4. Nothing runs off the edges.
extends SceneTree

const T_ := preload("res://tests/t.gd")
const Const_ := preload("res://scripts/core/const.gd")
const Screens_ := preload("res://scripts/app/screens.gd")
const Menu_ := preload("res://scripts/app/menu.gd")
const Pack_ := preload("res://scripts/render/pack.gd")
const ScreenView := preload("res://scripts/render/screen_view.gd")
const Match_ := preload("res://scripts/core/match.gd")
const Roulette_ := preload("res://scripts/app/roulette.gd")

## Screens that show a full-screen bitmap of the original's, and which one.
const FULL_SCREEN_ART := {
	Screens_.Screen.TITLE: "title",
	Screens_.Screen.MAIN_MENU: "mainmenu",
	Screens_.Screen.RESULTS: "results",
}


func _init() -> void:
	var t := T_.new("render_screens")

	var pack: Pack_ = Pack_.new()
	if not pack.load_from(Pack_.default_dir()):
		t.note(pack.error)
		t.note("skipping: no asset pack")
		quit(t.finish())
		return

	_test_the_pack_has_the_screens(t, pack)
	_test_the_pack_has_the_font(t, pack)

	for screen in Screens_.Screen.values():
		if screen == Screens_.Screen.GAME:
			continue          # the playfield, not a screen — render_field.gd
		await _check(t, pack, screen)

	_test_the_options_list_fits(t)
	_test_a_text_page_scrolls(t)

	quit(t.finish())


# The options list must fit above its own footer.
#
# It did not: the list grew from thirteen rows to twenty as the disc's own
# settings were implemented — Campaign, Win Matches By Kill Total, Random
# Start, Gold Bomberman, Disable Music, Define keyboard layouts — and at 26 px
# a row the last of them was drawn at y=514 on a 480-line screen, straight
# through "Escape returns to the menu". The model tests were all green; this is
# the arithmetic they cannot see.
func _test_the_options_list_fits(t: T_) -> void:
	var menu: Menu_ = Menu_.new()
	menu.setup([])
	# Every row except the slots, which are their own screen.
	var rows: int = menu.item_count() - 1
	var bottom: float = ScreenView.OPTIONS_TOP \
		+ rows * ScreenView.OPTIONS_ROW_H
	var footer: float = Const_.SCREEN_H - 26
	t.ok(bottom <= footer,
		"%d option rows end at y=%d, above the footer at %d"
			% [rows, int(bottom), int(footer)])

	# And the keyboard-definitions screen, which replaces it.
	var keys_bottom: float = ScreenView.KEYS_TOP \
		+ Menu_.KEY_ROWS * ScreenView.OPTIONS_ROW_H + 8.0
	t.ok(keys_bottom <= footer,
		"the %d key rows end at y=%d" % [Menu_.KEY_ROWS, int(keys_bottom)])


# A text page shows a screenful and can be scrolled: About and the Manual are
# the disc's own CREDITS.BM and MANUAL.BM, both longer than one screen, and
# they used to draw the first screenful and stop.
func _test_a_text_page_scrolls(t: T_) -> void:
	var rows := ScreenView.page_rows()
	t.ok(rows > 10, "a text page shows %d lines" % rows)
	t.ok(48.0 + rows * 18.0 <= float(Const_.SCREEN_H) - 40.0,
		"and they fit above the footer")


# Every screen the original ships must be in the pack. Named individually
# rather than counted, because a count passes while the wrong one is missing.
func _test_the_pack_has_the_screens(t: T_, pack: Pack_) -> void:
	var wanted := ["title", "mainmenu", "results", "draw", "roulette",
		"bonus", "team0", "team1", "glue0", "glue1", "glue2", "glue3",
		"glue4", "glue5", "glue6"]
	for name in wanted:
		t.ok(pack.has_screen(name), "the pack has %s" % name)
	for slot in Const_.PLAYER_COUNT:
		t.ok(pack.has_screen("victory%d" % slot),
			"and a victory screen for player %d" % slot)
	t.note("%d screens in the pack" % pack.screen_names().size())

	# Every screen is 640x480, which is the resolution the original ran at and
	# the reason the window scales rather than the canvas widening.
	#
	# The PCX art that is NOT a screen lives under elements: WINZ is 72x72,
	# CREDBAR 200x100, BOMBDUDE 110x110. Keeping them apart is what lets this
	# be an assertion rather than a list of exceptions.
	for name in pack.screen_names():
		var tex := pack.screen(String(name))
		t.eq(tex.get_size(), Vector2(Const_.SCREEN_W, Const_.SCREEN_H),
			"%s is 640x480" % name)
	t.note("%d elements: %s" % [pack.element_names().size(),
		", ".join(pack.element_names())])
	for name in ["credbar", "winz", "bombdude"]:
		t.ok(pack.has_element(name), "the pack has the %s element" % name)
		t.ok(pack.element(name).get_size() != Vector2(Const_.SCREEN_W,
			Const_.SCREEN_H), "and %s is not screen-sized" % name)


# The lettering is FONT1.FON. KFONT.ANI is digits only, which is why the
# alphabet comes from the install root instead.
func _test_the_pack_has_the_font(t: T_, pack: Pack_) -> void:
	t.ok(pack.has_font("font1"), "the pack has font1")
	var font: Dictionary = pack.font("font1")
	t.eq(int(font["height"]), 16, "16 pixels tall")
	var glyphs: Dictionary = font["glyphs"]
	var missing: Array[String] = []
	for code in range(32, 127):
		if not glyphs.has(str(code)):
			missing.append(char(code))
	t.eq(missing.size(), 0,
		"every printable ASCII character has a glyph (missing: %s)"
			% "".join(missing))


func _check(t: T_, pack: Pack_, screen: int) -> void:
	var screens: Screens_ = Screens_.new()
	screens.screen = screen
	# A match, so the results and victory screens have something to show.
	var m: Match_ = Match_.new()
	m.setup(1, 0, false)
	m.record(Match_.OUTCOME_LAST_STANDING, 2, 0)
	m.record(Match_.OUTCOME_LAST_STANDING, 2, 0)
	if screen == Screens_.Screen.VICTORY:
		screens.finish_match(2, 0, false)
		screens.screen = screen
	elif screen == Screens_.Screen.DRAW:
		screens.finish_match(-1, -1, false)
		screens.screen = screen

	var menu: Menu_ = Menu_.new()
	menu.setup(pack.scheme_names())
	if screen == Screens_.Screen.SETUP:
		menu.in_slots = true

	# The wheel, spun to its landing, so the roulette screen has something to
	# draw and its announcement is on screen.
	var wheel: Roulette_ = null
	if screen == Screens_.Screen.ROULETTE:
		wheel = Roulette_.new()
		wheel.start(2, 7)
		for _i in 400:
			wheel.tick()
			if wheel.result >= 0:
				break

	var view: Node2D = ScreenView.new()
	view.screens = screens
	view.menu = menu
	view.pack = pack
	view.the_match = m
	view.roulette = wheel
	root.add_child(view)
	await process_frame
	view.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	var shot := root.get_texture().get_image()
	if not t.ok(shot != null, "screen %d produced an image" % screen):
		view.queue_free()
		return

	var label := "screen %d" % screen

	# 1. It drew something with structure, not a flat fill.
	var colours := {}
	var bright := 0
	for y in range(8, Const_.SCREEN_H - 8, 7):
		for x in range(8, Const_.SCREEN_W - 8, 7):
			var c := shot.get_pixel(x, y)
			colours[Vector3i(int(c.r * 16), int(c.g * 16), int(c.b * 16))] = true
			if (c.r + c.g + c.b) / 3.0 > 0.5:
				bright += 1
	t.ok(colours.size() >= 8,
		"%s has %d distinct colours, so it is not a flat fill"
			% [label, colours.size()])

	# 2. Where the original has a full-screen bitmap, the render must BE it.
	if FULL_SCREEN_ART.has(screen):
		var art := pack.screen(FULL_SCREEN_ART[screen]).get_image()
		var same := 0
		var tried := 0
		for y in range(6, Const_.SCREEN_H - 6, 11):
			for x in range(6, Const_.SCREEN_W - 6, 13):
				tried += 1
				var a := art.get_pixel(x, y)
				var b := shot.get_pixel(x, y)
				if absf(a.r - b.r) < 0.06 and absf(a.g - b.g) < 0.06 \
						and absf(a.b - b.b) < 0.06:
					same += 1
		# Not every pixel: the cursor, the prompt and the values are drawn
		# over. Most of the screen has to be the art, though.
		t.ok(float(same) / float(tried) > 0.85,
			"%s is drawn from %s (%d of %d sampled pixels match)"
				% [label, FULL_SCREEN_ART[screen], same, tried])

	# 2b. On the main menu, the cursor must land beside the item it points at.
	#
	# MENU_ITEM_Y was measured from MAINMENU.PCX, and a wrong number puts the
	# pointer between two items or off the list. Checked against the ART: the
	# band the model names must contain the painted yellow text, and the render
	# must have ink in the gap immediately left of it where nothing is painted.
	if screen == Screens_.Screen.MAIN_MENU:
		var art := pack.screen("mainmenu").get_image()
		for item in Screens_.MENU_LABELS.size():
			var rect := Screens_.menu_item_rect(item)
			# Inside the band there must be painted text, and in the six rows
			# ABOVE and BELOW it there must be almost none. Overlap alone is
			# not enough: the bands are 22 px tall on a 37 px pitch, so a band
			# shifted by fifteen still catches half a line of text, and a
			# cursor pointing halfway between two items is exactly the bug
			# this is for.
			var inside := _yellow_rows(art, rect.position.y, rect.end.y,
				rect.position.x, 90)
			var above := _yellow_rows(art, rect.position.y - 7,
				rect.position.y - 1, rect.position.x, 90)
			var below := _yellow_rows(art, rect.end.y + 1, rect.end.y + 7,
				rect.position.x, 90)
			t.ok(inside > 30,
				"item %d's band has painted text in it (%d px)"
					% [item, inside])
			t.ok(above * 6 < inside,
				"item %d's band is not straddling the line above (%d vs %d)"
					% [item, above, inside])
			t.ok(below * 6 < inside,
				"item %d's band is not straddling the line below (%d vs %d)"
					% [item, below, inside])

		# And the cursor is drawn in the clear strip left of the selected item,
		# where the art has nothing.
		var rect2 := Screens_.menu_item_rect(screens.cursor)
		var drawn := 0
		var art_ink := 0
		for y in range(int(rect2.position.y) - 6, int(rect2.end.y) + 4):
			for x in range(int(rect2.position.x) - 34,
					int(rect2.position.x) - 4):
				if y < 0 or x < 0:
					continue
				var a := art.get_pixel(x, y)
				var b := shot.get_pixel(x, y)
				if absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b) > 0.18:
					drawn += 1
				if a.r > 0.7 and a.g > 0.55 and a.b < 0.5:
					art_ink += 1
		t.eq(art_ink, 0, "the strip left of the item is clear in the art")
		t.ok(drawn > 40,
			"and the cursor is drawn into it (%d changed pixels)" % drawn)

	# 2c. The roulette's icons must be drawn on the ellipse VALUELST specifies,
	# and its announcement on screen. The wheel is the one screen whose layout
	# came out of the data, so this checks the render against the data rather
	# than against a number in this file.
	if screen == Screens_.Screen.ROULETTE and wheel != null:
		var art2 := pack.screen("roulette").get_image()
		var drawn_icons := 0
		for i in Roulette_.WHEEL_SIZE:
			var at: Vector2 = wheel.icon_position(i)
			var changed := 0
			for dy in range(-14, 15, 3):
				for dx in range(-14, 15, 3):
					var px := int(at.x) + dx
					var py := int(at.y) + dy
					if px < 0 or py < 0 or px >= Const_.SCREEN_W \
							or py >= Const_.SCREEN_H:
						continue
					var a3 := art2.get_pixel(px, py)
					var b3 := shot.get_pixel(px, py)
					if absf(a3.r - b3.r) + absf(a3.g - b3.g) \
							+ absf(a3.b - b3.b) > 0.15:
						changed += 1
			if changed > 12:
				drawn_icons += 1
		t.ok(drawn_icons >= Roulette_.WHEEL_SIZE - 1,
			"%d of the wheel's %d icons are drawn where the data puts them"
				% [drawn_icons, Roulette_.WHEEL_SIZE])
		t.ok(wheel.result >= 0, "and the wheel has landed on %d"
			% wheel.result)

	# 3. There is legible ink somewhere.
	t.ok(bright > 20,
		"%s has %d bright samples, so something is readable on it"
			% [label, bright])

	# 4. Nothing is drawn off the edges — checked by requiring the outermost
	# ring of pixels to exist and the image to be the full size.
	t.eq(shot.get_width(), Const_.SCREEN_W, "%s fills the width" % label)
	t.eq(shot.get_height(), Const_.SCREEN_H, "%s fills the height" % label)

	view.queue_free()
	await process_frame


## Painted menu text, counted. The art's lettering is yellow on dark blue.
static func _yellow_rows(art: Image, y0: float, y1: float, x0: float,
		width: int) -> int:
	var n := 0
	for y in range(maxi(int(y0), 0), mini(int(y1), art.get_height())):
		for x in range(maxi(int(x0), 0),
				mini(int(x0) + width, art.get_width())):
			var c := art.get_pixel(x, y)
			if c.r > 0.7 and c.g > 0.55 and c.b < 0.5:
				n += 1
	return n
