# Do all ten players come out in the ten colours the tuning table names?
#
# Windowed, because the recolour is a shader and the headless rasteriser runs
# none. This is the suite that makes the recolour safe to rely on: the sprites
# are all authored green (the ANI sequences are literally named "bomb regular
# green"), so a broken recolour looks like a perfectly good game in which every
# player is the same colour — which is exactly what happened twice while this
# was being built. docs/BUGS.md Q6, D5.
extends SceneTree

const T_ := preload("res://tests/t.gd")
const Const_ := preload("res://scripts/core/const.gd")
const Types_ := preload("res://scripts/core/types.gd")
const Scheme_ := preload("res://scripts/core/scheme.gd")
const Sim_ := preload("res://scripts/sim/sim.gd")
const Pack_ := preload("res://scripts/render/pack.gd")
const Player_ := preload("res://scripts/sim/player.gd")
const GameView := preload("res://scripts/render/game_view.gd")

# Ten cells with clear space above each, so a 110px sprite over a 36px cell
# cannot overlap another player.
const CELLS := [
	Vector2i(1, 3), Vector2i(4, 3), Vector2i(7, 3), Vector2i(10, 3),
	Vector2i(13, 3), Vector2i(1, 7), Vector2i(4, 7), Vector2i(7, 7),
	Vector2i(10, 7), Vector2i(13, 7),
]

const NAMES := ["white", "black", "red", "blue", "green",
	"yellow", "cyan", "magenta", "orange", "purple"]


func _init() -> void:
	var t := T_.new("render_recolour")
	var pack: Pack_ = Pack_.new()
	if not pack.load_from(Pack_.default_dir()):
		t.note(pack.error)
		t.note("skipping: no asset pack, so there is nothing to recolour")
		quit(t.finish())
		return

	var scheme: Scheme_ = Scheme_.new()
	scheme.parse_text(_scheme_text(), "<recolour>")
	if not t.ok(scheme.ok(), "probe scheme parses (%s)" % scheme.error()):
		quit(t.finish())
		return

	var slots := []
	for i in Const_.PLAYER_COUNT:
		slots.append({"slot": i, "team": i % 2})
	var sim: Sim_ = Sim_.new()
	sim.setup(scheme, slots, 1)

	var view: Node2D = GameView.new()
	view.sim = sim
	view.pack = pack
	view.level = 1     # level 1's floor is the background, so no grass overlay
	root.add_child(view)

	await process_frame
	view.queue_redraw_all()
	await process_frame
	await RenderingServer.frame_post_draw

	var shot := root.get_texture().get_image()
	if not t.ok(shot != null, "the viewport produced an image"):
		quit(t.finish())
		return

	_test_each_player_is_its_own_colour(t, shot, sim)
	_test_all_ten_are_distinct(t, shot, sim)
	_test_the_shader_uses_the_discs_tables(t, shot, sim, pack)
	_test_the_view_wires_the_tables(t, view, pack)
	quit(t.finish())


# Does game_view actually HAND the tables to the shader?
#
# tests/render_shader.gd proves the shader computes the right thing when it is
# given them, but it builds its own material to do that — so it cannot see a
# view that never passes them and leaves the shader on its heuristic path. That
# mutation escaped both suites until this existed, and it is the most likely
# regression of the lot: one `if` in _make_material.
#
# Checked by reading the materials the view built, which is the wiring itself
# rather than a consequence of it.
func _test_the_view_wires_the_tables(t: T_, view: Node2D, pack: Pack_) -> void:
	var materials: Array[ShaderMaterial] = []
	_collect_materials(view, materials)
	t.ok(materials.size() >= Const_.PLAYER_COUNT,
		"%d recolour materials exist" % materials.size())

	var exact := 0
	var slots_seen := {}
	for mat in materials:
		# Compared against `true` rather than passed through bool(): a shader
		# parameter that was never set comes back as NULL, and `bool(null)`
		# throws "Nonexistent 'bool' constructor" — which killed this function
		# mid-run and let the very mutation it exists to catch look like a
		# pass. Exactly the failure mode described at the top of this file.
		if mat.get_shader_parameter("tinted") != true:
			continue          # the untinted node, which opts out by design
		if mat.get_shader_parameter("exact_remap") == true:
			exact += 1
			t.ok(mat.get_shader_parameter("remap_palette") != null,
				"an exact material has a palette")
			t.ok(mat.get_shader_parameter("remap_lut") != null,
				"and a lookup")
			t.ok(mat.get_shader_parameter("remap_table") != null,
				"and a remap table")
			slots_seen[int(mat.get_shader_parameter("player_slot"))] = true

	if pack.has_remap():
		t.ok(exact > 0,
			"the view puts the shader on the exact path when the pack has "
			+ "the tables (%d of %d materials)" % [exact, materials.size()])
		# And every player's material must name ITS OWN slot, or they would
		# share a ramp.
		t.eq(slots_seen.size(), Const_.PLAYER_COUNT,
			"all ten slots are represented (%d)" % slots_seen.size())
	else:
		t.eq(exact, 0, "and stays on the heuristic when it does not")


func _collect_materials(node: Node, into: Array[ShaderMaterial]) -> void:
	if node is CanvasItem:
		var mat = (node as CanvasItem).material
		if mat is ShaderMaterial and not into.has(mat):
			into.append(mat)
	for child in node.get_children():
		_collect_materials(child, into)


# Is the shader really running the disc's tables, or has it quietly fallen back
# to the heuristic?
#
# The two produce different colours — tools/remap.py measures a mean per-channel
# difference of 7.6 to 30.0 depending on the player — but both produce
# PLAUSIBLE ones, so every assertion above passes either way. That is the
# failure mode this catches, and it is the same shape as D5: a recolour that is
# wrong but looks fine.
#
# THE DISCRIMINATOR. Where a source pixel's colour IS one of the 256 palette
# entries — 32% of the actor art — the disc's transform outputs another palette
# entry exactly: `palette[remap[player][index]]`. So for each player there is a
# set of 73 colours the tables can produce and the heuristic essentially never
# does. Counting rendered pixels near each set separates them.
func _test_the_shader_uses_the_discs_tables(t: T_, shot: Image, sim: Sim_,
		pack: Pack_) -> void:
	if not t.ok(pack.has_remap(),
			"the pack carries the disc's remap tables"):
		t.note("built without COLOR.PAL and the .RMP files; the shader is "
			+ "running the heuristic and that is the only thing checked above")
		return

	var info := pack.remap_info()
	t.eq(info["count"], 73, "73 of 256 palette indices are remapped")
	t.eq(info["first"], 100, "the block starts at index 100")
	t.eq(info["last"], 174, "and ends at 174")
	t.eq(info["players"], Const_.PLAYER_COUNT, "one row per player")

	var palette := pack.remap_palette().get_image()
	var table := pack.remap_table().get_image()
	t.eq(palette.get_width(), 256, "the palette is 256 wide")
	t.eq(table.get_width(), 256, "and so is the remap table")
	t.eq(table.get_height(), Const_.PLAYER_COUNT, "with ten rows")

	# Every player's ramp must differ from every other's, or the tables would
	# recolour two players the same and nothing above would notice.
	var ramps := []
	for slot in Const_.PLAYER_COUNT:
		var ramp: Array[Color] = []
		for i in range(info["first"], info["last"] + 1):
			var mapped := int(round(table.get_pixel(i, slot).r * 255.0))
			if mapped != 0:
				ramp.append(palette.get_pixel(mapped, 0))
		ramps.append(ramp)
		t.ok(ramp.size() > 50,
			"player %d's ramp has %d colours" % [slot, ramp.size()])
	for a in Const_.PLAYER_COUNT:
		for b in range(a + 1, Const_.PLAYER_COUNT):
			t.ok(ramps[a] != ramps[b],
				"players %d and %d have different ramps" % [a, b])

	# The count that decides it, for the player the two transforms disagree about most:
	# blue, at 30.0 per channel.
	var slot := 3
	var p: Player_ = sim.player_by_slot(slot)
	var tc := Const_.player_colour_f(slot)
	var target := Vector3(tc.r, tc.g, tc.b)
	var on_ramp := 0
	var on_heuristic := 0
	var opaque := 0
	var box := _body_box(p)
	for y in range(box.position.y, box.end.y):
		for x in range(box.position.x, box.end.x):
			if x < 0 or y < 0 or x >= shot.get_width() \
					or y >= shot.get_height():
				continue
			var c := shot.get_pixel(x, y)
			opaque += 1
			if _near_any(c, ramps[slot]):
				on_ramp += 1
			elif _near_any(c, _heuristic_ramp(ramps, palette, info, target)):
				on_heuristic += 1
	t.ok(opaque > 200, "%d pixels sampled over player %d" % [opaque, slot])
	# The string is built before the call: `"a" + "b" % args` binds the % to
	# "b" alone, so the arguments do not all get used and Godot reports a
	# formatting error at runtime while the assertion still passes.
	var verdict := ("player %d's pixels land on the disc's ramp (%d) more "
		+ "than on the heuristic's (%d)") % [slot, on_ramp, on_heuristic]
	t.ok(on_ramp > on_heuristic, verdict)
	t.note("player %d: %d of %d sampled pixels are on the disc's own ramp"
		% [slot, on_ramp, opaque])


## The heuristic's outputs for the same source colours, so the two sets can be
## counted against each other rather than one being asserted in a vacuum.
func _heuristic_ramp(ramps: Array, palette: Image, info: Dictionary,
		target: Vector3) -> Array[Color]:
	var out: Array[Color] = []
	for i in range(info["first"], info["last"] + 1):
		var src := palette.get_pixel(i, 0)
		if not (src.g > src.r and src.g > src.b):
			continue
		var n: float = (src.r + src.b) * 0.5
		var k: float = src.g - n
		var v := Vector3(n, n, n) + k * target
		var m: float = maxf(v.x, maxf(v.y, v.z))
		if m > 1.0:
			v /= m
		out.append(Color(v.x, v.y, v.z))
	return out


static func _near_any(c: Color, set_of: Array) -> bool:
	for other in set_of:
		var o: Color = other
		if absf(c.r - o.r) < 0.02 and absf(c.g - o.g) < 0.02 \
				and absf(c.b - o.b) < 0.02:
			return true
	return false


## The screen rectangle a standing player's torso occupies. Deliberately small
## and inside the sprite, so nothing sampled is background.
static func _body_box(p: Player_) -> Rect2i:
	# From the renderer's own anchor rule, for the same reason _body_points
	# does: a box positioned by restating where the feet are goes wrong the
	# moment the anchor is corrected.
	var anchor := Const_.actor_anchor(Vector2(p.x, p.y) / float(Player_.CP))
	return Rect2i(int(anchor.x) - 9, int(anchor.y) - 43, 18, 22)


# Each player's rendered colour must be nearer its OWN target than any other
# player's target.
#
# "Nearer" compares the channel RATIOS, not raw RGB: the transform rescales
# brightness and the sprite is shaded, so no rendered pixel equals its target
# outright — what survives is the direction in colour space. Ratios also handle
# the targets with two equal maxima. An earlier version of this test asserted
# "the dominant channel matches" and broke on yellow (r == g) and magenta
# (r == b), where the winner is decided by shading noise.
#
# White and black have no direction at all, so they are checked for being grey,
# and for white being the brighter of the two.
func _test_each_player_is_its_own_colour(t: T_, shot: Image, sim: Sim_) -> void:
	var lum := {}
	for p in sim.players:
		var mean: Variant = _mean_body(shot, p)
		if not t.ok(mean != null, "player %d has a visible body" % p.slot):
			continue
		var c: Color = mean
		var target := Const_.player_colour_f(p.slot)
		lum[p.slot] = (c.r + c.g + c.b) / 3.0

		if _chroma(target) < 0.01:
			# Achromatic target: assert the render is grey too.
			t.ok(_chroma(c) < 0.16,
				"player %d (%s) renders grey, chroma %.3f"
					% [p.slot, NAMES[p.slot], _chroma(c)])
			continue

		# Chromatic: the nearest of the ten targets by ratio must be its own.
		var best := -1
		var best_d := 1e9
		for other in Const_.PLAYER_COUNT:
			var ot := Const_.player_colour_f(other)
			if _chroma(ot) < 0.01:
				continue      # grey targets have no ratio to compare against
			var d := _ratio_distance(c, ot)
			if d < best_d:
				best_d = d
				best = other
		t.eq(best, p.slot,
			"player %d (%s) renders closest to its own colour, not %s (rendered %s)"
				% [p.slot, NAMES[p.slot],
					NAMES[best] if best >= 0 else "none", c])

	# White must come out brighter than black, which is the only thing that
	# tells the two achromatic players apart.
	if lum.has(0) and lum.has(1):
		t.ok(lum[0] > lum[1],
			"white (%.2f) renders brighter than black (%.2f)" % [lum[0], lum[1]])


static func _chroma(c: Color) -> float:
	return maxf(c.r, maxf(c.g, c.b)) - minf(c.r, minf(c.g, c.b))


## Distance between two colours' channel ratios, brightness removed.
static func _ratio_distance(a: Color, b: Color) -> float:
	var an := _normalise(a)
	var bn := _normalise(b)
	return absf(an.x - bn.x) + absf(an.y - bn.y) + absf(an.z - bn.z)


static func _normalise(c: Color) -> Vector3:
	# Subtract the grey floor, then scale so the largest channel is 1. What is
	# left is the colour's direction regardless of how light or dark it is.
	var lo: float = minf(c.r, minf(c.g, c.b))
	var v := Vector3(c.r - lo, c.g - lo, c.b - lo)
	var hi: float = maxf(v.x, maxf(v.y, v.z))
	return v / hi if hi > 0.0001 else Vector3.ZERO


# Ten players must render as ten different colours. This is the check that
# fails when the recolour silently stops working, because then they are all
# identical and every per-player assertion above could still pass.
func _test_all_ten_are_distinct(t: T_, shot: Image, sim: Sim_) -> void:
	var seen := {}
	for p in sim.players:
		var mean: Variant = _mean_body(shot, p)
		if mean == null:
			continue
		var c: Color = mean
		# Quantise, so shading noise does not make two identical players look
		# different.
		var key := "%d,%d,%d" % [int(c.r * 12), int(c.g * 12), int(c.b * 12)]
		seen[key] = int(seen.get(key, 0)) + 1
	t.ok(seen.size() >= 8,
		"the ten players render as %d distinct colours (need >= 8; all-identical means the recolour is dead)"
			% seen.size())


# Mean of every visible pixel of a player's sprite.
func _mean_body(shot: Image, p: Player_) -> Variant:
	var acc := Vector3.ZERO
	var n := 0
	var bg := shot.get_pixel(Const_.FIELD_X_OFF + 4, Const_.FIELD_Y_OFF + 4)
	for point in _body_points(p):
		var c := shot.get_pixelv(point)
		if c.is_equal_approx(bg):
			continue
		acc += Vector3(c.r, c.g, c.b)
		n += 1
	if n < 8:
		return null
	return Color(acc.x / n, acc.y / n, acc.z / n)


# The sprite's torso, which is where the recoloured area is.
#
# The feet position comes from Const.actor_anchor(), the renderer's own rule,
# rather than being restated here. It was restated here, as "the feet sit on
# the cell centre", and that was true only while the renderer had the anchor
# wrong: fixing the anchor moved every sprite down 17px and this band started
# sampling the shadow and the floor instead of the body, which read as two
# players rendering the wrong colour. docs/BUGS.md D24.
#
# A bomberman is 35x67 of ink above the anchor, measured from the art, so the
# torso is the band 20-45px up.
func _body_points(p: Player_) -> Array[Vector2i]:
	var anchor := Const_.actor_anchor(
		Vector2(p.x, p.y) / float(Player_.CP))
	var feet := Vector2i(int(anchor.x), int(anchor.y))
	var out: Array[Vector2i] = []
	for dy in range(-46, -18):
		for dx in range(-12, 13):
			var q := feet + Vector2i(dx, dy)
			if q.x >= 0 and q.y >= 0 and q.x < Const_.SCREEN_W and q.y < Const_.SCREEN_H:
				out.append(q)
	return out


func _scheme_text() -> String:
	var lines := PackedStringArray()
	lines.append("-V,2")
	lines.append("-N,Recolour probe (10)")
	lines.append("-B,0")
	for y in Const_.FIELD_H:
		lines.append("-R,%2d,%s" % [y, ".".repeat(Const_.FIELD_W)])
	for i in Const_.PLAYER_COUNT:
		lines.append("-S,%d,%d,%d,%d" % [i, CELLS[i].x, CELLS[i].y, i % 2])
	for i in Const_.POWERUP_COUNT:
		lines.append("-P,%2d, 0,0, 0, 0,x" % i)
	return "\n".join(lines)
