# Does the menu fit on the screen, and is every row legible?
#
# Needs a real GPU context, so verify.sh runs this one windowed.
#
# WHY IT EXISTS. The menu's first layout ran START, HOST and QUIT off the
# bottom of a 640x480 screen and drew the footer through the last two player
# slots. Nothing in tests/test_menu.gd could see that — the model was correct
# and every value was right — and it was obvious the moment anybody looked at
# a screenshot. So the two things this asserts are the two things a screenshot
# answers: it FITS, and the text is not drawn in a colour nobody can read.
extends SceneTree

const T_ := preload("res://tests/t.gd")
const Const_ := preload("res://scripts/core/const.gd")
const Menu_ := preload("res://scripts/app/menu.gd")
const Pack_ := preload("res://scripts/render/pack.gd")
const MenuView := preload("res://scripts/render/menu_view.gd")


func _init() -> void:
	var t := T_.new("render_menu")

	var pack: Pack_ = Pack_.new()
	# Not a skip: the menu is meant to work with no pack at all, and it says so
	# on screen. This suite runs either way.
	var have_pack := pack.load_from(Pack_.default_dir())
	t.note("asset pack: %s" % ("loaded" if have_pack else pack.error))

	var menu: Menu_ = Menu_.new()
	menu.setup(pack.scheme_names() if have_pack else [])

	var view: Node2D = MenuView.new()
	view.menu = menu
	view.pack = pack
	root.add_child(view)

	await process_frame
	view.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw

	var shot := root.get_texture().get_image()
	if not t.ok(shot != null and shot.get_width() > 0,
			"the viewport produced an image"):
		quit(t.finish())
		return
	t.note("viewport is %dx%d" % [shot.get_width(), shot.get_height()])

	_test_it_fits(t, shot, view, menu)
	_test_rows_are_legible(t, shot, view, menu)
	await _test_slots_are_legible(t, view, menu)
	_test_the_cursor_is_visible(t, view, menu)

	quit(t.finish())


# Every row the model has must be drawn inside the screen, with the last one
# clear of the footer. Computed from the view's own constants, so a layout
# change either keeps this true or fails here.
func _test_it_fits(t: T_, shot: Image, view: Node2D, menu: Menu_) -> void:
	# The header, too. Tightening the bottom is what broke this end: the first
	# row was moved up into the subtitle, which reads as a smear rather than as
	# two lines of text.
	t.ok(float(MenuView.TOP) - MenuView.ROW_H + 4 >= float(MenuView.HEADER_BOTTOM),
		"the first row starts at y=%d, below the header at %d"
			% [MenuView.TOP, MenuView.HEADER_BOTTOM])

	# The player slots moved to a screen of their own, so the list is rows and
	# nothing else. Both sub-screens are measured below.
	var rows: int = menu.item_count()
	var bottom: float = float(MenuView.TOP) + rows * MenuView.ROW_H + 6
	t.ok(bottom <= float(Const_.SCREEN_H) - 20,
		"the last row ends at y=%d, inside %d with room for the footer"
			% [int(bottom), Const_.SCREEN_H])
	t.ok(bottom <= float(shot.get_height()),
		"and inside the viewport")

	# The slots screen: five rows of two, at double spacing.
	var slots_bottom: float = float(MenuView.TOP) \
		+ MenuView.SLOT_ROWS * MenuView.SLOT_H * 2 + 12 + MenuView.ROW_H
	t.ok(slots_bottom <= float(Const_.SCREEN_H) - 20,
		"the player slots end at y=%d, clear of the footer" % int(slots_bottom))

	# The keyboard definitions: thirteen rows plus the gap before the last.
	var keys_bottom: float = float(MenuView.TOP) \
		+ Menu_.KEY_ROWS * MenuView.ROW_H + 6 + 24
	t.ok(keys_bottom <= float(Const_.SCREEN_H) - 20,
		"the keyboard definitions end at y=%d" % int(keys_bottom))

	# The two columns of slots must fit across, too.
	var right: float = float(MenuView.LABEL_X) + 16 + MenuView.SLOT_W + 78 + 60
	t.ok(right <= float(Const_.SCREEN_W),
		"the second slot column ends at x=%d, inside %d"
			% [int(right), Const_.SCREEN_W])


# Sample where each row's label is drawn and require it to be brighter than the
# background. That is what catches a row drawn in a colour too dark to read —
# four of the ten player colours are dark enough for that to be a real risk,
# which is why the slot rows are lifted toward white.
func _test_rows_are_legible(t: T_, shot: Image, view: Node2D,
		menu: Menu_) -> void:
	var dark := 0
	var checked := 0
	var y := float(MenuView.TOP)
	for item in menu.item_count():
		checked += 1
		if not _row_has_ink(shot, y, MenuView.LABEL_X):
			dark += 1
			t.ok(false, "row %d (%s) has no legible ink"
				% [item, menu.label_of(item)])
		y += MenuView.ROW_H
	t.eq(dark, 0, "all %d rows are legible" % checked)


# The player slots are their own screen now, so they are drawn and sampled on
# their own. Four of the ten player colours are dark enough that this is a real
# risk, which is why the slot rows are lifted toward white.
func _test_slots_are_legible(t: T_, view: Node2D, menu: Menu_) -> void:
	menu.in_slots = true
	view.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	var shot := root.get_texture().get_image()
	var dark := 0
	for i in menu.slots.size():
		var col: int = i / MenuView.SLOT_ROWS
		var row: int = i % MenuView.SLOT_ROWS
		var sy: float = float(MenuView.TOP) + row * MenuView.SLOT_H * 2
		var sx: int = MenuView.LABEL_X + 16 + col * MenuView.SLOT_W
		if not _row_has_ink(shot, sy, sx):
			dark += 1
			t.ok(false, "player %d's row has no legible ink" % (i + 1))
	t.eq(dark, 0, "all ten player slots are legible on their own screen")
	menu.in_slots = false
	view.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw


## Is there a pixel bright enough to read in the band this row's text occupies?
##
## The threshold is deliberately low — this is a legibility floor, not a colour
## match. A row drawn in the background colour scores zero.
func _row_has_ink(shot: Image, y: float, x: int) -> bool:
	var top := maxi(int(y) - 12, 0)
	var bottom := mini(int(y) + 2, shot.get_height() - 1)
	var brightest := 0.0
	for py in range(top, bottom + 1):
		for px in range(x, mini(x + 150, shot.get_width())):
			var c := shot.get_pixel(px, py)
			brightest = maxf(brightest, (c.r + c.g + c.b) / 3.0)
	return brightest > 0.45


# The selected row has to look selected, or the arrow keys appear to do nothing.
func _test_the_cursor_is_visible(t: T_, view: Node2D, menu: Menu_) -> void:
	t.eq(menu.selected(), Menu_.Item.SCHEME, "the cursor starts at the top")
	t.ok(not menu.in_slots, "and not inside the slot list")
	# Moving it has to change what selected() reports, which is what the view
	# highlights. The model's own suite covers the walk; this asserts only that
	# the view is reading a value that moves.
	menu.move(1)
	t.ok(menu.selected() != Menu_.Item.SCHEME, "and it moves")
