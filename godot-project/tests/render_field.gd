# Does the field get drawn where the original puts it, with the right art?
#
# Needs a real GPU context: the headless rasteriser draws nothing, so this suite
# is run windowed by verify.sh rather than with --headless.
#
# It does NOT compare against a checked-in reference PNG. That would be brittle
# across drivers and machines for no gain here. Instead it samples the rendered
# viewport at computed cell positions and compares each block against the tile
# frame the pack itself holds for that cell's kind. So it answers the question
# that actually matters — is cell (tx, ty) drawn from the right frame at
# FIELD_X_OFF + tx * BLOCK_W — and it stays true on any machine.
extends SceneTree

const T_ := preload("res://tests/t.gd")
const Const_ := preload("res://scripts/core/const.gd")
const Types_ := preload("res://scripts/core/types.gd")
const Field_ := preload("res://scripts/sim/field.gd")
const Sim_ := preload("res://scripts/sim/sim.gd")
const Scheme_ := preload("res://scripts/core/scheme.gd")
const Pack_ := preload("res://scripts/render/pack.gd")
const Player_ := preload("res://scripts/sim/player.gd")
const Bomb_ := preload("res://scripts/sim/bomb.gd")
const GameView := preload("res://scripts/render/game_view.gd")

const LEVEL := 0

## The window of cells no actor sprite can reach — see _test_cells_match_art.
const SAMPLE_ROWS := [0, 4]
const SAMPLE_COLS := [4, 10]


func _init() -> void:
	var t := T_.new("render_field")
	var pack: Pack_ = Pack_.new()
	if not pack.load_from(Pack_.default_dir()):
		t.note(pack.error)
		t.note("skipping: no asset pack, so there is no art to compare against")
		quit(t.finish())
		return

	# A scheme with all three cell kinds present and nothing thinned away, so
	# every kind is somewhere known.
	var scheme: Scheme_ = Scheme_.new()
	scheme.parse_text(_scheme_text(), "<render>")
	if not t.ok(scheme.ok(), "test scheme parses (%s)" % scheme.error()):
		quit(t.finish())
		return

	var sim: Sim_ = Sim_.new()
	sim.setup(scheme, [{"slot": 0, "team": 0}], 1)

	var view: Node2D = GameView.new()
	view.sim = sim
	view.pack = pack
	view.level = LEVEL
	view.alpha = 0.0
	root.add_child(view)

	# Two frames: one to lay out, one to have something in the viewport.
	await process_frame
	view.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw

	var shot := root.get_texture().get_image()
	t.ok(shot != null and shot.get_width() > 0, "the viewport produced an image")
	if shot == null:
		quit(t.finish())
		return
	t.note("viewport is %dx%d" % [shot.get_width(), shot.get_height()])

	_test_geometry(t, shot)
	_test_actor_anchor(t)
	await _test_nothing_leaves_the_field(t, pack, scheme)
	await _test_a_bomb_sits_on_its_cell(t, pack, scheme)
	await _test_the_flame_lines_up(t, pack, scheme)
	await _test_every_state_looks_different(t, pack, scheme)
	_test_cells_match_art(t, shot, sim, pack)
	_test_playfield_is_not_uniform(t, shot)

	quit(t.finish())


# The playfield must sit where the original puts it, and must fit on screen.
#
# The offsets are DERIVED, from BM95.EXE's own geometry setup at 0x42647A —
# which names its source as `map.c` line 317:
#
#     X_ORIGIN = (screen_w - FIELD_W * BLOCK_W) / 2
#     Y_ORIGIN = screen_h - FIELD_H * BLOCK_H - 16
#
# so the field is centred horizontally and pinned 16 px off the bottom. The
# port had 66 for the Y offset where the formula gives 68, and drew everything
# two pixels high. docs/BUGS.md D24.
func _test_geometry(t: T_, shot: Image) -> void:
	var right := Const_.FIELD_X_OFF + Const_.FIELD_W * Const_.BLOCK_W
	var bottom := Const_.FIELD_Y_OFF + Const_.FIELD_H * Const_.BLOCK_H
	t.eq(Const_.FIELD_X_OFF, 20, "the field is centred: (640 - 600) / 2 = 20")
	t.eq(Const_.FIELD_Y_OFF, 68, "and 68 down: 480 - 396 - 16")
	t.eq(right, 620, "so it ends 20px from the right of 640")
	t.eq(bottom, 464, "and exactly 16px from the bottom of 480")
	t.eq(Const_.SCREEN_H - bottom, Const_.BOTTOM_MARGIN,
		"which is map.c's own margin")
	t.ok(right <= shot.get_width(), "the playfield fits horizontally")
	t.ok(bottom <= shot.get_height(), "the playfield fits vertically")

	# The status area is everything above the field, and the level backgrounds
	# leave it plain for the readout.
	t.eq(Const_.STATUS_H, 68, "the status area is 68px tall")


# Nothing an actor draws may leave the playfield.
#
# A standing bomberman is 35x67 of ink over a 36px cell — measured from the art
# — so one on the top row reaches 31px above its own cell and, before the
# clip, off the top of the screen. That was "the player goes out of the
# screen". The anchor rule is asserted here rather than by looking, because a
# sprite one cell out of place still looks like a game.
func _test_actor_anchor(t: T_) -> void:
	# ANCHOR_DROP is the constant BM95.EXE's tile_y subtracts (0x4266A3), and
	# it puts the hotspot on the cell's bottom edge.
	t.eq(Const_.ANCHOR_DROP, Const_.BLOCK_H / 2 - 1,
		"the anchor drops BLOCK_H/2 - 1 below the stored position")
	t.eq(Const_.ANCHOR_DROP, 17, "which is 17")

	# An actor at the centre of cell (tx, ty) must anchor on that cell's
	# bottom edge, in screen coordinates.
	for ty in [0, 5, Const_.FIELD_H - 1]:
		for tx in [0, 7, Const_.FIELD_W - 1]:
			var centre := Vector2(tx * Const_.BLOCK_W + Const_.BLOCK_W / 2,
				ty * Const_.BLOCK_H + Const_.BLOCK_H / 2)
			var anchor := Const_.actor_anchor(centre)
			var origin := Const_.tile_origin(tx, ty)
			t.eq(anchor.x, float(origin.x) + Const_.BLOCK_W / 2,
				"cell %d,%d anchors on its horizontal centre" % [tx, ty])
			t.eq(anchor.y, float(origin.y) + Const_.BLOCK_H - 1,
				"cell %d,%d anchors on its bottom edge" % [tx, ty])

	# And the field rect is the clip.
	var field := Const_.field_rect()
	t.eq(field.position, Vector2(Const_.FIELD_X_OFF, Const_.FIELD_Y_OFF),
		"the clip rect starts at the field origin")
	t.eq(field.end, Vector2(620, 464), "and ends where the field ends")


# Every cell must be drawn from the frame the pack holds for its kind. This is
# the assertion that catches a wrong offset, a swapped brick/solid mapping, or
# an off-by-one in the tile origin — each of which would look plausible.
func _test_cells_match_art(t: T_, shot: Image, sim: Sim_, pack: Pack_) -> void:
	var sheet := "tiles%d" % LEVEL
	if not t.ok(pack.has_sheet(sheet), "the pack has %s" % sheet):
		return
	var tex := pack.texture_of(sheet)
	var art := tex.get_image()

	var kinds := {
		Types_.Brick.BLANK: "tile %d blank" % LEVEL,
		Types_.Brick.BRICK: "tile %d brick" % LEVEL,
		Types_.Brick.SOLID: "tile %d solid" % LEVEL,
	}
	var checked := {}

	# Sample only the clear window the fixture reserves. A player sprite is
	# 110px tall against a 36px cell, so it overhangs roughly three rows above
	# its own — the first version of this test sampled the cell directly above
	# the player's start and failed on the sprite drawn over it, which is
	# correct rendering and a bad fixture. The fixture parks its player in the
	# bottom-left corner; rows 0..4 of columns 4..10 are nowhere near it.
	for ty in range(SAMPLE_ROWS[0], SAMPLE_ROWS[1] + 1):
		for tx in range(SAMPLE_COLS[0], SAMPLE_COLS[1] + 1):
			var kind: int = sim.field.brick_at(tx, ty)
			if checked.has(kind):
				continue
			if not kinds.has(kind) or not pack.has_sequence(sheet, kinds[kind]):
				continue
			var index := pack.sequence_frame(sheet, kinds[kind], 0)
			if index < 0:
				continue
			var src := pack.frame_rect(sheet, index)
			var origin := Const_.tile_origin(tx, ty)

			# Sample a handful of points rather than every pixel: enough to
			# fail on a wrong frame or a shifted origin, cheap enough to run.
			var matches := 0
			var total := 0
			for dy in [2, Const_.BLOCK_H / 2, Const_.BLOCK_H - 3]:
				for dx in [2, Const_.BLOCK_W / 2, Const_.BLOCK_W - 3]:
					var want := art.get_pixel(int(src.position.x) + dx,
						int(src.position.y) + dy)
					var got := shot.get_pixel(origin.x + dx, origin.y + dy)
					total += 1
					# The tile art is opaque, so a match should be exact; a
					# small tolerance covers any colour-space rounding in the
					# viewport read-back.
					if want.a > 0.5 and got.is_equal_approx(want):
						matches += 1
					elif want.a <= 0.5:
						total -= 1     # transparent sample proves nothing
			if total > 0:
				t.ok(matches == total,
					"cell (%d,%d) kind %d is drawn from %s (%d/%d samples)"
					% [tx, ty, kind, kinds[kind], matches, total])
				checked[kind] = true

	t.eq(checked.size(), 3, "all three cell kinds were found and checked")


# A field that failed to draw would be a flat colour, and every per-cell check
# above could still pass on a uniform image if the art were flat too.
func _test_playfield_is_not_uniform(t: T_, shot: Image) -> void:
	var seen := {}
	var y := Const_.FIELD_Y_OFF
	while y < Const_.FIELD_Y_OFF + Const_.FIELD_H * Const_.BLOCK_H:
		var x := Const_.FIELD_X_OFF
		while x < Const_.FIELD_X_OFF + Const_.FIELD_W * Const_.BLOCK_W:
			seen[shot.get_pixel(x, y).to_rgba32()] = true
			x += 7
		y += 5
	t.ok(seen.size() > 20,
		"the playfield has %d distinct sampled colours, so it really drew"
		% seen.size())


# All three cell kinds, at rows the sampling window covers, with density 100 so
# nothing is thinned away by the RNG:
#
#   row 0   all blank   — stated in the grid, NOT produced by start clearing,
#                         so it is blank regardless of where players are
#   row 2   all brick
#   row 4   all solid
#   rest    brick
#
# The player is parked at (0,10), the bottom-left corner, so its sprite cannot
# reach rows 0..4.
func _scheme_text() -> String:
	var lines := PackedStringArray()
	lines.append("-V,2")
	lines.append("-N,Render fixture (10)")
	lines.append("-B,100")
	for y in Const_.FIELD_H:
		var ch := ":"
		if y == 0:
			ch = "."
		elif y == 4:
			ch = "#"
		lines.append("-R,%2d,%s" % [y, ch.repeat(Const_.FIELD_W)])
	for p in Const_.PLAYER_COUNT:
		lines.append("-S,%d,0,10,%d" % [p, p % 2])
	for i in Const_.POWERUP_COUNT:
		lines.append("-P,%2d, 0,0, 0, 0,x" % i)
	return "\n".join(lines)


# A player on the TOP ROW is drawn WHOLE, and above the playfield if that is
# where its head goes.
#
# This assertion used to say the opposite — "must not draw above the
# playfield" — and clipping to the field is what enforced it. It was wrong on
# screen: a bomberman is 35x67 of ink anchored on its cell's bottom edge, so on
# row 0 the clip cut it across the chest and the player read as standing BEHIND
# the wall. The status band is drawn after the actors instead, so a head that
# reaches into it passes under the score rather than through it.
func _test_nothing_leaves_the_field(t: T_, pack: Pack_,
		scheme: Scheme_) -> void:
	var sim: Sim_ = Sim_.new()
	sim.setup(scheme, [{"slot": 4, "team": 0}], 1)
	# Slot 4 is green, which is the one colour certain to differ from the
	# level background above the field.
	var p: Player_ = sim.players[0]
	p.place_at_tile_centre(7, 0)

	var view: Node2D = GameView.new()
	view.sim = sim
	view.pack = pack
	view.level = LEVEL
	root.add_child(view)
	await process_frame
	view.queue_redraw_all()
	await process_frame
	await RenderingServer.frame_post_draw
	var shot := root.get_texture().get_image()

	# The head reaches into the band above the field, and that is correct now.
	var art := pack.background(LEVEL)
	if not t.ok(art != null, "level %d has a background to compare against"
			% LEVEL):
		view.queue_free()
		return
	var bg := art.get_image()
	var changed := 0
	for y in range(2, Const_.FIELD_Y_OFF - 2):
		for x in range(int(Const_.FIELD_X_OFF + 5 * Const_.BLOCK_W),
				int(Const_.FIELD_X_OFF + 10 * Const_.BLOCK_W)):
			var a := bg.get_pixel(x, y)
			var b := shot.get_pixel(x, y)
			if absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b) > 0.25:
				changed += 1
	t.ok(changed > 0,
		"a player on row 0 reaches above the playfield (%d px) rather than"
			% changed + " being cut off at its edge")

	# AND IT IS WHOLE: the head's top lands where a 67 px sprite anchored on
	# its cell's bottom edge puts it. A clip would cut it lower down, which is
	# a number this can see.
	var highest := -1
	for y in range(2, Const_.FIELD_Y_OFF):
		for x in range(int(Const_.FIELD_X_OFF + 5 * Const_.BLOCK_W),
				int(Const_.FIELD_X_OFF + 10 * Const_.BLOCK_W)):
			var a := bg.get_pixel(x, y)
			var b := shot.get_pixel(x, y)
			if absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b) > 0.25:
				highest = y
				break
		if highest >= 0:
			break
	# AND IT STOPS AT THE PANEL. Const_.HUD_H is where the level backgrounds
	# stop drawing and the readout starts, so it is where an actor is clipped.
	# The first version clipped at the playfield and cut the sprite in half —
	# "the player is drawn behind the walls". The second let it through to y=0
	# and put a bomberman through the clock — "the UI for the timer overlaps".
	# The head reaches the panel and no further.
	t.eq(highest, Const_.HUD_H,
		"the head's top is at the panel edge y=%d, not %d"
			% [Const_.HUD_H, highest])
	var above := 0
	for y in range(0, Const_.HUD_H):
		for x in range(2, Const_.SCREEN_W - 2):
			var a2 := bg.get_pixel(x, y)
			var b2 := shot.get_pixel(x, y)
			if absf(a2.r - b2.r) + absf(a2.g - b2.g) + absf(a2.b - b2.b) > 0.25:
				above += 1
	t.eq(above, 0,
		"and no actor pixel is drawn in the readout's panel (%d were)" % above)
	# It still gets 26 px of overhang, which is what keeps the head whole
	# enough to read as a head rather than as a cut.
	t.ok(int(Const_.FIELD_Y_OFF) - Const_.HUD_H >= 26,
		"a sprite may still overhang the playfield by %d px"
			% (int(Const_.FIELD_Y_OFF) - Const_.HUD_H))

	# And it IS drawn — inside the field, on its own cell and the rows above.
	var ink := 0
	var top := int(Const_.FIELD_Y_OFF)
	for y in range(top, top + Const_.BLOCK_H):
		for x in range(int(Const_.FIELD_X_OFF + 7 * Const_.BLOCK_W),
				int(Const_.FIELD_X_OFF + 8 * Const_.BLOCK_W)):
			var a := bg.get_pixel(x, y)
			var b := shot.get_pixel(x, y)
			if absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b) > 0.25:
				ink += 1
	t.ok(ink > 100, "and the clipped sprite is still visible (%d px)" % ink)
	view.queue_free()
	await process_frame


# A bomb must be drawn on the cell it is on.
#
# Bombs and flames were drawn in FIELD-LOCAL coordinates, without the field
# origin — 20 px left and 68 px up, which put every bomb a cell and a half from
# the player who dropped it. No constant is wrong when that happens, so this
# looks at where the bomb's pixels land.
#
# The reference is the SAME SCENE WITHOUT THE BOMB, not the level background:
# the field draws a tile over every cell, so a comparison against the raw
# background reports 1,400 changed pixels for all 165 of them and measures the
# tiles instead of the bomb.
func _test_a_bomb_sits_on_its_cell(t: T_, pack: Pack_,
		scheme: Scheme_) -> void:
	var sim: Sim_ = Sim_.new()
	sim.setup(scheme, [{"slot": 0, "team": 0}], 1)
	var p: Player_ = sim.players[0]
	p.place_at_tile_centre(1, 9)

	var view: Node2D = GameView.new()
	view.sim = sim
	view.pack = pack
	view.level = LEVEL
	root.add_child(view)
	await process_frame
	view.queue_redraw_all()
	await process_frame
	await RenderingServer.frame_post_draw
	var before := root.get_texture().get_image()

	# Now the bomb, in the middle of the field and far from the player.
	var cell := Vector2i(7, 5)
	var b: Bomb_ = Bomb_.new()
	b.place_at_tile_centre(cell.x, cell.y)
	b.owner = 0
	b.chain_owner = 0
	b.fuze = 900
	b.placed_tick = 0
	b.flame_len = 1
	sim.bombs.append(b)
	view.queue_redraw_all()
	await process_frame
	await RenderingServer.frame_post_draw
	var after := root.get_texture().get_image()

	var best := Vector2i(-1, -1)
	var best_count := 0
	var on_cell := 0
	var total := 0
	for ty in Const_.FIELD_H:
		for tx in Const_.FIELD_W:
			var origin := Const_.tile_origin(tx, ty)
			var count := 0
			for y in range(origin.y, origin.y + Const_.BLOCK_H):
				for x in range(origin.x, origin.x + Const_.BLOCK_W):
					var a := before.get_pixel(x, y)
					var c := after.get_pixel(x, y)
					if absf(a.r - c.r) + absf(a.g - c.g) \
							+ absf(a.b - c.b) > 0.12:
						count += 1
			total += count
			if tx == cell.x and ty == cell.y:
				on_cell = count
			if count > best_count:
				best_count = count
				best = Vector2i(tx, ty)

	t.ok(total > 200, "adding a bomb changed %d pixels" % total)
	t.ok(on_cell > 150,
		"the bomb is drawn on cell %s (%d of them)" % [cell, on_cell])
	t.eq(best, cell,
		"and %s is where most of the change is, not %s" % [cell, best])
	# Most of the bomb is on its own cell. Its sprite is 36x37 in a 40x36
	# cell, so a row of it legitimately spills into the cell above.
	t.ok(float(on_cell) / float(total) > 0.6,
		"%.0f%% of the change is on the bomb's own cell"
			% (100.0 * float(on_cell) / float(total)))
	view.queue_free()
	await process_frame


# THE EXPLOSION IS ONE SHAPE, not a centre and four arms at different heights.
#
# MFLAME.ANI's 45 frames all carry the same hotspot — (width / 2, height - 1),
# the generic bottom-centre a converter writes when it has nothing better — so
# anchoring on it bottom-aligned them. The frames are bands of DIFFERENT
# heights (the west arm runs 23, 21, 19, 20, 23 over its five steps) on a 36 px
# cell, so the arms sat about eight pixels below the centre's own crossbar and
# crawled up and down as the animation ran. "The middle sprite does not match
# with the borders of the explosion."
#
# Measured rather than asserted about the code: the ink of each cell along a
# horizontal arm must be centred on the same row, and that row must be the
# cell's own middle.
func _test_the_flame_lines_up(t: T_, pack: Pack_, scheme: Scheme_) -> void:
	if not t.ok(pack.has_sheet("mflame"), "MFLAME.ANI is in the pack"):
		return
	var sim: Sim_ = Sim_.new()
	# Slot 0 is white, which reads against every level background there is.
	sim.setup(scheme, [{"slot": 0, "team": 0}], 1)
	# A clear row, so the arm reaches its full length and every one of the
	# three pieces — centre, mid and tip — is on the screen at once, and clear
	# rows either side of it so nothing else moves in the measured strip.
	for ty in [4, 5, 6]:
		for tx in Const_.FIELD_W:
			sim.field.brick[Field_.idx(tx, ty)] = Types_.Brick.BLANK
			sim.field.powerup[Field_.idx(tx, ty)] = Field_.NO_POWERUP
	var p: Player_ = sim.players[0]
	p.place_at_tile_centre(7, 5)
	p.flame_len = 3
	var bomb := sim.place_bomb(p)
	if not t.ok(bomb != null, "a bomb is placed at the middle of the field"):
		return
	bomb.flame_len = 3
	bomb.fuze = 1
	# Out of the blast before it goes off, so the picture is the flame alone.
	p.place_at_tile_centre(1, 10)
	sim.tick()
	sim.tick()

	var lit := 0
	for tx in range(4, 11):
		if sim.field.has_flame(tx, 5):
			lit += 1
	if not t.eq(lit, 7, "the arm is seven cells of flame"):
		return

	var view: Node2D = GameView.new()
	view.sim = sim
	view.pack = pack
	view.level = LEVEL
	root.add_child(view)
	await process_frame

	# THE REFERENCE IS THE SAME SCENE WITHOUT THE FLAME, not the level
	# background: the field draws its own tiles over the backdrop, so comparing
	# against the backdrop marks every blank cell as "drawn on" and measures
	# the grass instead of the explosion.
	var lit_bits := sim.field.flame.duplicate()
	for i in sim.field.flame.size():
		sim.field.flame[i] = 0
	view.queue_redraw_all()
	await process_frame
	await RenderingServer.frame_post_draw
	var base := root.get_texture().get_image()

	sim.field.flame = lit_bits
	view.queue_redraw_all()
	await process_frame
	await RenderingServer.frame_post_draw
	var shot := root.get_texture().get_image()

	# THE HORIZONTAL ARM, cell by cell. The epicentre is skipped: it carries
	# the vertical arms too, so its ink is a whole column by design.
	var want: float = Const_.FIELD_Y_OFF + 5 * Const_.BLOCK_H \
		+ Const_.BLOCK_H / 2.0
	var middles: Array[float] = []
	for tx in [4, 5, 6, 8, 9, 10]:
		# The middle half of each cell's width, so a neighbour's one-pixel
		# overhang cannot be mistaken for this cell's own piece.
		var left: int = int(Const_.FIELD_X_OFF) + tx * Const_.BLOCK_W + 10
		var right: int = left + Const_.BLOCK_W - 20
		var top := -1
		var bottom := -1
		for y in range(int(Const_.FIELD_Y_OFF) + 4 * Const_.BLOCK_H,
				int(Const_.FIELD_Y_OFF) + 7 * Const_.BLOCK_H):
			var hit := false
			for x in range(left, right):
				if _lit(base, shot, x, y):
					hit = true
					break
			if hit:
				if top < 0:
					top = y
				bottom = y
		if not t.ok(top >= 0, "cell %d,5 has flame drawn on it" % tx):
			continue
		t.ok(bottom - top < Const_.BLOCK_H,
			"cell %d,5's piece is a band %d px tall, not a whole column"
				% [tx, bottom - top + 1])
		middles.append((top + bottom) / 2.0)

	t.note("horizontal arm centres: %s (want %.1f)" % [middles, want])
	if middles.size() < 6:
		view.queue_free()
		return
	# Every piece is centred on the cell's own middle row...
	for i in middles.size():
		t.close(middles[i], want, 3.0,
			"a horizontal piece is centred on its row (%.1f, want %.1f)"
				% [middles[i], want])
	# ...so no two pieces of one arm disagree about where the arm is. Eight
	# pixels apart was what a player saw.
	var lo: float = middles[0]
	var hi: float = middles[0]
	for m in middles:
		lo = minf(lo, m)
		hi = maxf(hi, m)
	t.close(hi - lo, 0.0, 4.0,
		"and the six pieces agree to within %.1f px" % (hi - lo))

	# THE VERTICAL ARM, the same measurement turned on its side. A vertical
	# piece is 22-27 px wide on a 40 px cell, so it has to be centred across
	# the column the same way.
	var want_x: float = Const_.FIELD_X_OFF + 7 * Const_.BLOCK_W \
		+ Const_.BLOCK_W / 2.0
	for ty in [4, 6]:
		var top_y: int = int(Const_.FIELD_Y_OFF) + ty * Const_.BLOCK_H + 8
		var bot_y: int = top_y + Const_.BLOCK_H - 16
		var first := -1
		var last := -1
		for x in range(int(Const_.FIELD_X_OFF) + 6 * Const_.BLOCK_W,
				int(Const_.FIELD_X_OFF) + 9 * Const_.BLOCK_W):
			var hit := false
			for y in range(top_y, bot_y):
				if _lit(base, shot, x, y):
					hit = true
					break
			if hit:
				if first < 0:
					first = x
				last = x
		if not t.ok(first >= 0, "cell 7,%d has flame drawn on it" % ty):
			continue
		t.ok(last - first < Const_.BLOCK_W,
			"cell 7,%d's piece is %d px wide, not a whole row"
				% [ty, last - first + 1])
		t.close((first + last) / 2.0, want_x, 3.0,
			"and is centred across its column (%.1f, want %.1f)"
				% [(first + last) / 2.0, want_x])

	# THE JOINT, which the checks above skip by design (they measure each
	# arm away from the epicentre). docs/IMPROVEMENTS.md A4, "the top-centre
	# arm is a few pixels right": the arm above was ~3 px right of the centre
	# piece's own stem where the two meet. Each band's flame is located by
	# weighting every changed pixel by how much it changed.
	var cell_top: int = int(Const_.FIELD_Y_OFF) + 5 * Const_.BLOCK_H
	var cell_bot: int = cell_top + Const_.BLOCK_H
	var arm_above := _ink_x(base, shot, cell_top - 12, cell_top - 1)
	# Five rows, not six: the crossbar's glow begins on the sixth and pulls
	# the reading towards the middle of the frame.
	var stem_top := _ink_x(base, shot, cell_top, cell_top + 5)
	var stem_bot := _ink_x(base, shot, cell_bot - 6, cell_bot)
	var arm_below := _ink_x(base, shot, cell_bot, cell_bot + 12)
	t.note("joint: arm above %.2f, centre top %.2f, centre bottom %.2f, arm below %.2f"
		% [arm_above, stem_top, stem_bot, arm_below])
	t.close(arm_above, stem_top, 1.0,
		"[invariant] the arm above meets the centre's stem (%.2f vs %.2f)"
			% [arm_above, stem_top])
	t.close(arm_below, stem_bot, 1.5,
		"and so does the arm below (%.2f vs %.2f)" % [arm_below, stem_bot])
	view.queue_free()


## Column 7's flame across rows [y0, y1): the x every changed pixel averages
## to, weighted by how much it changed.
static func _ink_x(base: Image, shot: Image, y0: int, y1: int) -> float:
	var total := 0.0
	var sum := 0.0
	for y in range(y0, y1):
		for x in range(int(Const_.FIELD_X_OFF) + 6 * Const_.BLOCK_W,
				int(Const_.FIELD_X_OFF) + 9 * Const_.BLOCK_W):
			var a := base.get_pixel(x, y)
			var b := shot.get_pixel(x, y)
			var w := absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)
			if w > 0.2:
				total += w
				sum += (x + 0.5) * w
	return sum / total if total > 0.0 else 0.0


## Was anything drawn at (x, y) in `shot` that was not in `base`?
static func _lit(base: Image, shot: Image, x: int, y: int) -> bool:
	var a := base.get_pixel(x, y)
	var b := shot.get_pixel(x, y)
	return absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b) > 0.20


# A PLAYER AND A BOMB EACH HAVE SEVERAL LOOKS AND THE PORT DREW ONE.
#
# The sequences are asserted by tests/test_pack.gd; what is asserted here is
# that the view REACHES them — that a punching player is not drawn with the
# standing frame, and that a trigger bomb is not drawn with the plain one. Both
# were true, and both are invisible to a suite that only checks the pack: the
# name is built from the player's state, and a state nothing tests reaches
# nothing.
func _test_every_state_looks_different(t: T_, pack: Pack_,
		scheme: Scheme_) -> void:
	var sim: Sim_ = Sim_.new()
	sim.setup(scheme, [{"slot": 0, "team": 0}], 1)
	for ty in [4, 5, 6]:
		for tx in Const_.FIELD_W:
			sim.field.brick[Field_.idx(tx, ty)] = Types_.Brick.BLANK
			sim.field.powerup[Field_.idx(tx, ty)] = Field_.NO_POWERUP
	var p: Player_ = sim.players[0]
	p.place_at_tile_centre(7, 5)
	p.facing = Types_.Dir.DOWN
	p.move = Types_.MoveState.STILL

	var view: Node2D = GameView.new()
	view.sim = sim
	view.pack = pack
	view.level = LEVEL
	root.add_child(view)
	await process_frame

	var shots := {}
	# The window the player and its bomb are drawn in: its own cell and the
	# two rows above, where a 67 px sprite and a bomb held overhead land.
	var box := Rect2i(int(Const_.FIELD_X_OFF) + 6 * Const_.BLOCK_W,
		int(Const_.FIELD_Y_OFF) + 3 * Const_.BLOCK_H,
		3 * Const_.BLOCK_W, 3 * Const_.BLOCK_H)

	for state in ["stand", "kick", "punch", "pickup", "carry"]:
		p.kick_ticks = 0
		p.punch_ticks = 0
		p.pickup_pause = 0
		sim.bombs.clear()
		match state:
			"kick":
				p.kick_ticks = Sim_.KICK_ANIM_TICKS
			"punch":
				p.punch_ticks = Sim_.PUNCH_ANIM_TICKS
			"pickup":
				p.pickup_pause = 2
			"carry":
				var held := sim.place_bomb(p)
				if held != null:
					held.carried_by = p.slot
		view.queue_redraw_all()
		await process_frame
		await RenderingServer.frame_post_draw
		shots[state] = _crop(root.get_texture().get_image(), box)

	var names: Array = shots.keys()
	for i in names.size():
		for j in range(i + 1, names.size()):
			var d := _pixels_apart(shots[names[i]], shots[names[j]])
			t.ok(d > 20,
				"%s and %s are drawn differently (%d px apart)"
					% [names[i], names[j], d])

	# A CARRIED BOMB IS NOT ON THE GROUND. BOMBWALK.ANI draws the player and
	# the bomb over its head as one sprite, so drawing the bomb as well left a
	# second one at the carrier's feet. Proved by giving the carried bomb
	# coordinates far from its carrier and looking there: the field is empty
	# whatever the bomb's own x and y say.
	sim.bombs.clear()
	var carried := Bomb_.new()
	carried.place_at_tile_centre(12, 5)
	carried.owner = 0
	carried.chain_owner = 0
	carried.placed_tick = sim.tick_count
	carried.fuze = 100
	carried.carried_by = p.slot
	sim.bombs.append(carried)
	view.queue_redraw_all()
	await process_frame
	await RenderingServer.frame_post_draw
	var far := Rect2i(int(Const_.FIELD_X_OFF) + 12 * Const_.BLOCK_W,
		int(Const_.FIELD_Y_OFF) + 4 * Const_.BLOCK_H,
		Const_.BLOCK_W, 2 * Const_.BLOCK_H)
	var with_bomb := _crop(root.get_texture().get_image(), far)
	sim.bombs.clear()
	view.queue_redraw_all()
	await process_frame
	await RenderingServer.frame_post_draw
	var without := _crop(root.get_texture().get_image(), far)
	t.eq(_pixels_apart(with_bomb, without), 0,
		"a carried bomb draws nothing at its own cell")

	# THE BOMBS, the same way. Four states, four sequences on the disc, and one
	# of them was being drawn for all four.
	sim.bombs.clear()
	p.place_at_tile_centre(1, 10)
	var bomb_shots := {}
	for kind in ["plain", "jelly", "trigger", "dud"]:
		sim.bombs.clear()
		var b := Bomb_.new()
		b.place_at_tile_centre(7, 5)
		b.owner = 0
		b.chain_owner = 0
		b.placed_tick = sim.tick_count
		b.fuze = 100
		match kind:
			"jelly":
				b.jelly_bounce = true
			"trigger":
				b.triggered = true
			"dud":
				b.state = Types_.BombState.DUD
		sim.bombs.append(b)
		view.queue_redraw_all()
		await process_frame
		await RenderingServer.frame_post_draw
		bomb_shots[kind] = _crop(root.get_texture().get_image(), box)

	var kinds: Array = bomb_shots.keys()
	for i in kinds.size():
		for j in range(i + 1, kinds.size()):
			var d := _pixels_apart(bomb_shots[kinds[i]], bomb_shots[kinds[j]])
			t.ok(d > 5,
				"a %s bomb and a %s bomb are drawn differently (%d px)"
					% [kinds[i], kinds[j], d])
	view.queue_free()


static func _crop(img: Image, box: Rect2i) -> Image:
	return img.get_region(box)


static func _pixels_apart(a: Image, b: Image) -> int:
	# Every second pixel in each direction: a sprite that differs at all
	# differs over hundreds of pixels, and the full scan of twenty pairs cost
	# more than the rest of this suite put together.
	var n := 0
	for y in range(0, a.get_height(), 2):
		for x in range(0, a.get_width(), 2):
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			if absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b) > 0.12:
				n += 1
	return n
