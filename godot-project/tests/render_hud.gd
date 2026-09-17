# The status band above the playfield: the clock, the per-player readout, and
# the HURRY banner.
#
# Windowed, because it renders.
#
# WHY IT IS ITS OWN SUITE. The band is 68 px of the 480 and nothing in it is
# simulation, so no headless suite touches it and render_field.gd deliberately
# looks only at cells. Every bug the band has had — the placeholder text line,
# the clock's colon landing in the wrong place, seven photographs of the
# programmer's face across the top — was invisible until somebody looked.
extends SceneTree

const T_ := preload("res://tests/t.gd")
const Const_ := preload("res://scripts/core/const.gd")
const Types_ := preload("res://scripts/core/types.gd")
const Values_ := preload("res://scripts/core/values.gd")
const Scheme_ := preload("res://scripts/core/scheme.gd")
const Sim_ := preload("res://scripts/sim/sim.gd")
const Match_ := preload("res://scripts/core/match.gd")
const Pack_ := preload("res://scripts/render/pack.gd")
const GameView := preload("res://scripts/render/game_view.gd")

const SEATS := 6


func _init() -> void:
	var t := T_.new("render_hud")

	var pack: Pack_ = Pack_.new()
	if not pack.load_from(Pack_.default_dir()):
		t.note(pack.error)
		t.note("skipping: no asset pack")
		quit(t.finish())
		return

	_test_the_font_is_there(t, pack)

	var scheme: Scheme_ = Scheme_.new()
	scheme.parse_text(_scheme_text(), "<hud>")
	var slots := []
	for i in SEATS:
		slots.append({"slot": i, "team": Const_.default_team(i)})
	var sim: Sim_ = Sim_.new()
	sim.setup(scheme, slots, 1)
	# OFF THE TOP TWO ROWS. A bomberman is 67 px of ink over a 36 px cell, so
	# one standing on row 0 reaches up into the band — which is the thing this
	# suite measures. Moved down so the band's own ink is the only ink there.
	for i in sim.players.size():
		sim.players[i].place_at_tile_centre(1 + i, 5)
	var m: Match_ = Match_.new()
	m.setup(1, 0, false)
	m.record(Match_.OUTCOME_LAST_STANDING, 2, 0)

	var view: Node2D = GameView.new()
	view.sim = sim
	view.pack = pack
	view.level = 1
	view.the_match = m
	root.add_child(view)
	await process_frame
	view.queue_redraw_all()
	await process_frame
	await RenderingServer.frame_post_draw
	var shot := root.get_texture().get_image()
	if not t.ok(shot != null, "the viewport produced an image"):
		quit(t.finish())
		return

	# The level background, as the reference for "what was drawn here". An
	# absolute brightness threshold measures the band's own mid-grey instead:
	# 122 of 122 columns came back "lit" before this.
	var bg := pack.background(1).get_image()
	_test_the_band_is_used(t, shot, bg)
	_test_the_clock_reads(t, shot, bg, sim, pack)
	_test_a_marker_per_seat(t, shot, sim)
	_test_nothing_in_the_band_covers_the_field(t, shot, bg)

	# HURRY, which only exists once the clock has run down to resource 101.
	sim.time_left = Values_.V[Const_.Res.HURRY_AT_SECONDS] * Const_.TICK_HZ + 1
	sim.tick()
	view.queue_redraw_all()
	await process_frame
	await RenderingServer.frame_post_draw
	_test_hurry_banner(t, root.get_texture().get_image(), sim, pack)

	quit(t.finish())


# The clock is KFONT.ANI's digits. There is no alphabetic font in the ANIs,
# which is why the screens use FONT1.FON instead — this checks the one the band
# actually needs.
func _test_the_font_is_there(t: T_, pack: Pack_) -> void:
	t.ok(pack.has_sheet("kfont"), "the pack has kfont")
	t.ok(pack.has_sequence("kfont", "numeric font"),
		"with a numeric font sequence")
	# Eleven steps, not ten: D0..D9 and then DC.TGA, the colon. The clock drew
	# two squares in its place until the sequence was counted.
	var steps := pack.sequence_steps("kfont", "numeric font")
	t.eq(steps.size(), 11, "of ten digits and a colon")
	var colon := pack.frame_rect("kfont", steps[10])
	t.eq(colon.size, Vector2(6, 19), "the colon is 6x19")
	for i in 10:
		var d := pack.frame_rect("kfont", steps[i])
		t.ok(d.size.x >= 12 and d.size.y >= 26,
			"digit %d is %s" % [i, d.size])
	t.ok(pack.has_sequence("kfont", "infinity"),
		"and an infinity sign, for MESSAGES.TXT 280's Infinite play time")

	# KFACE is NOT the status head. It is a photographed human face with
	# directional frames — the Kurt-head easter egg player — and using it here
	# put seven identical photographs across the top of the playfield.
	t.ok(pack.has_sheet("kface"), "kface is in the pack")
	t.eq(pack.frame_count("kface"), 4, "with four directional frames")


func _test_the_band_is_used(t: T_, shot: Image, bg: Image) -> void:
	# Something is drawn in the band: pixels that differ from the level
	# background there, so a band showing only the backdrop fails.
	var ink := 0
	for y in range(4, Const_.FIELD_Y_OFF - 4, 2):
		for x in range(4, Const_.SCREEN_W - 4, 2):
			if _differs(shot, bg, x, y):
				ink += 1
	t.ok(ink > 60, "%d marks are drawn in the status band" % ink)


func _test_the_clock_reads(t: T_, shot: Image, bg: Image, sim: Sim_,
		pack: Pack_) -> void:
	# The clock is at the left of the band. Its digits are ~26 px tall.
	var ink := 0
	for y in range(8, 48):
		for x in range(8, 110):
			if _differs(shot, bg, x, y):
				ink += 1
	t.ok(ink > 40, "the clock is drawn (%d pixels over the backdrop)" % ink)

	# The COLON, specifically. KFONT's `numeric font` is eleven steps and the
	# eleventh is DC.TGA — the clock drew two squares in its place until the
	# sequence was counted, and pointing the step index at nothing draws no
	# colon at all while the digits still read.
	#
	# Found by columns: a "M:SS" clock has ink, a two-pixel-wide gap of colon,
	# then ink again. Counting the inked columns in the clock's strip
	# distinguishes "2:27" from "227".
	var columns := 0
	var runs := 0
	var was := false
	for x in range(8, 130):
		var lit := false
		for y in range(8, 48):
			if _differs(shot, bg, x, y):
				lit = true
				break
		if lit:
			columns += 1
			if not was:
				runs += 1
		was = lit
	t.ok(runs >= 3, "the clock has %d groups of inked columns" % runs)
	t.note("clock: %d inked columns in %d groups" % [columns, runs])

	# THE COLON, by TEMPLATE MATCH against its own glyph.
	#
	# Two weaker attempts failed. Counting groups of inked columns passed with
	# the colon deleted, because the digits already fall into four groups.
	# Requiring a column with exactly two 5-9 pixel runs also passed, because
	# some digit has a column shaped like that too.
	#
	# So this takes DC.TGA's alpha out of the pack and looks for that exact
	# 6x19 pattern anywhere in the clock's strip. Nothing but the glyph
	# satisfies it — not two drawn squares, and not a digit.
	var steps2: Array = pack.sequence_steps("kfont", "numeric font")
	var found_colon := false
	if steps2.size() > 10:
		var sheet: Image = pack.texture_of("kfont").get_image()
		var src: Rect2 = pack.frame_rect("kfont", int(steps2[10]))
		var mask: Array[Vector2i] = []
		var holes: Array[Vector2i] = []
		for gy in int(src.size.y):
			for gx in int(src.size.x):
				var a: Color = sheet.get_pixel(int(src.position.x) + gx,
					int(src.position.y) + gy)
				if a.a > 0.5:
					mask.append(Vector2i(gx, gy))
				else:
					holes.append(Vector2i(gx, gy))
		t.ok(mask.size() > 40, "the colon glyph has %d lit pixels"
			% mask.size())
		for oy in range(10, 40):
			for ox in range(8, 130):
				var hit := true
				for m in mask:
					if not _differs(shot, bg, ox + m.x, oy + m.y):
						hit = false
						break
				if not hit:
					continue
				# And its gap must be empty, or a solid block would match.
				var clear := true
				for h in holes:
					if _differs(shot, bg, ox + h.x, oy + h.y):
						clear = false
						break
				if clear:
					found_colon = true
					break
			if found_colon:
				break

	t.ok(found_colon,
		"the clock draws KFONT's own colon glyph, matched pixel for pixel")
	t.eq(sim.seconds_left(), int(Values_.V[Const_.Res.ROUND_SECONDS]),
		"and the round starts at resource 100's %d seconds"
			% int(Values_.V[Const_.Res.ROUND_SECONDS]))


# One marker per seat, in that seat's own colour — which is what says whose
# score is whose. Found by looking for each player's colour in the band.
func _test_a_marker_per_seat(t: T_, shot: Image, sim: Sim_) -> void:
	var found := 0
	for p in sim.players:
		if not p.in_play:
			continue
		var want := Const_.player_colour_f(p.slot)
		if _chroma(want) < 0.15:
			# White and black have no hue to find; their discs are checked by
			# the band-is-used test instead.
			found += 1
			continue
		var hits := 0
		for y in range(10, 52):
			for x in range(110, Const_.SCREEN_W):
				if _near(shot.get_pixel(x, y), want, 0.16):
					hits += 1
		if hits >= 12:
			found += 1
		else:
			t.ok(false, "player %d's marker (%s) is not in the band (%d px)"
				% [p.slot, want, hits])
	t.eq(found, SEATS, "a marker for each of the %d seats" % SEATS)


func _test_nothing_in_the_band_covers_the_field(t: T_, shot: Image,
		bg: Image) -> void:
	# The band ends where the field begins. A readout drawn into the playfield
	# would sit on top of the top row of cells.
	t.eq(Const_.STATUS_H, Const_.FIELD_Y_OFF,
		"the band is exactly the space above the field")
	t.ok(Const_.FIELD_Y_OFF > 40,
		"and is tall enough for a 26px clock plus margins")

	# AND IT FITS IN THE PANEL THE ART LEAVES. Const_.HUD_H is 42, measured
	# from the eleven backgrounds; below it every one of them draws its own
	# border, and a readout over that border is a readout over the frame.
	# The clock ran to y=43 and the player discs to y=43 before this.
	t.ok(Const_.HUD_H < Const_.FIELD_Y_OFF,
		"the panel is shallower than the whole band")
	var spill := 0
	for y in range(Const_.HUD_H, Const_.FIELD_Y_OFF):
		for x in range(2, Const_.SCREEN_W - 2):
			if _differs(shot, bg, x, y):
				spill += 1
	t.eq(spill, 0,
		"nothing the band draws reaches below y=%d (%d pixels did)"
			% [Const_.HUD_H, spill])


func _test_hurry_banner(t: T_, shot: Image, sim: Sim_, pack: Pack_) -> void:
	t.ok(sim.hurry_index >= 0, "Hurry has started")
	t.ok(pack.has_sequence("hurry", "hurry"),
		"and HURRY.ANI is in the pack")
	var index := pack.sequence_frame("hurry", "hurry", 0)
	var src := pack.frame_rect("hurry", index)
	t.eq(src.size, Vector2(278, 91), "one 278x91 banner")

	# It must be inside the playfield, centred.
	var at := Vector2((Const_.SCREEN_W - src.size.x) / 2.0,
		Const_.FIELD_Y_OFF + (Const_.FIELD_H * Const_.BLOCK_H
			- src.size.y) / 2.0)
	t.ok(at.x >= 0 and at.x + src.size.x <= Const_.SCREEN_W,
		"the banner fits across the screen")
	t.ok(at.y >= Const_.FIELD_Y_OFF, "and sits inside the playfield")

	# Drawn on the first Hurry tick — it flashes, and tick 0 is a lit frame.
	var ink := 0
	for y in range(int(at.y), int(at.y + src.size.y), 3):
		for x in range(int(at.x), int(at.x + src.size.x), 3):
			var c := shot.get_pixel(x, y)
			if _saturated(c) and (c.r + c.g) / 2.0 > 0.45:
				ink += 1
	t.ok(ink > 30, "and the banner is on screen (%d marks)" % ink)


## Was anything drawn at (x, y), as against the level background?
static func _differs(shot: Image, bg: Image, x: int, y: int) -> bool:
	var a := shot.get_pixel(x, y)
	var b := bg.get_pixel(x, y)
	return absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b) > 0.12


static func _saturated(c: Color) -> bool:
	return _chroma(c) > 0.22


static func _chroma(c: Color) -> float:
	return maxf(c.r, maxf(c.g, c.b)) - minf(c.r, minf(c.g, c.b))


static func _near(a: Color, b: Color, tol: float) -> bool:
	return absf(a.r - b.r) < tol and absf(a.g - b.g) < tol \
		and absf(a.b - b.b) < tol


func _scheme_text() -> String:
	var lines := PackedStringArray()
	lines.append("-V,2")
	lines.append("-N,HUD fixture (10)")
	lines.append("-B,0")
	for y in Const_.FIELD_H:
		lines.append("-R,%2d,%s" % [y, ".".repeat(Const_.FIELD_W)])
	for p in Const_.PLAYER_COUNT:
		lines.append("-S,%d,%d,%d,%d" % [p, 1 + p, 1 + (p % 8), p % 2])
	for i in Const_.POWERUP_COUNT:
		lines.append("-P,%2d, 0,0, 0, 0,x" % i)
	return "\n".join(lines)
