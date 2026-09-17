# Does the recolour shader compute what the disc's tables say, pixel for pixel?
#
# Windowed, because it renders.
#
# WHY A SEPARATE SUITE FROM render_recolour.gd. That one asks "does each player
# come out its own colour", which is the question a human asks looking at the
# screen, and it passes under BOTH transforms — a heuristic that is 30 per
# channel away from the disc's tables still produces a recognisably blue
# bomberman. Two mutations proved it: making the shader ignore the tables
# entirely, and making it quantise to the palette, both went undetected.
#
# So this one asks the narrow question instead, and answers it exactly: feed the
# shader a strip of known source colours, read the rendered strip back, and
# compare every pixel against the same transform computed in GDScript from the
# same three tables. Nothing here is a tolerance on hue; it is equality within
# rounding.
#
# The strip is built from REAL ART, half of it colours that are exactly palette
# entries and half that are not, because that is the distinction the two
# candidate transforms disagree about — see recolour.gdshader on why writing
# `palette[mapped]` would quantise 15-bit art to 256 colours.
extends SceneTree

const T_ := preload("res://tests/t.gd")
const Const_ := preload("res://scripts/core/const.gd")
const Pack_ := preload("res://scripts/render/pack.gd")

## How many source colours to test, and how tall to draw the strip. Eight rows
## so a sample can be taken from the middle and be nowhere near an edge.
const COLOURS := 96
const ROWS := 8

## Rounding budget. The tables are 6-bit expanded to 8, the shader works in
## normalised floats, and the viewport is 8-bit — so a couple of levels of
## disagreement is arithmetic, not a bug.
const TOLERANCE := 3


func _init() -> void:
	var t := T_.new("render_shader")

	var pack: Pack_ = Pack_.new()
	if not pack.load_from(Pack_.default_dir()):
		t.note(pack.error)
		t.note("skipping: no asset pack")
		quit(t.finish())
		return
	if not pack.has_remap():
		t.note("the pack carries no remap tables, so the shader runs the "
			+ "heuristic and there is nothing here to check")
		quit(t.finish())
		return

	var palette := pack.remap_palette().get_image()
	var lut := pack.remap_lut().get_image()
	var table := pack.remap_table().get_image()

	var sources := _pick_sources(t, pack, palette, lut, table)
	if not t.ok(sources.size() >= 24,
			"%d source colours picked from the art" % sources.size()):
		quit(t.finish())
		return

	# Slot 3 (blue) and slot 4 (green) — the players the two candidate
	# transforms disagree about most and least, so a pass here is not an
	# accident of one easy target.
	for slot in [3, 4, 1]:
		await _check_slot(t, pack, palette, lut, table, sources, slot)

	quit(t.finish())


## Source colours from the real art: half exactly palette entries, half not.
func _pick_sources(t: T_, pack: Pack_, palette: Image, lut: Image,
		table: Image) -> Array[Color]:
	var sheet := "stand"
	if not pack.has_sheet(sheet):
		return []
	var art := pack.texture_of(sheet).get_image()
	var exact_ones: Array[Color] = []
	var inexact: Array[Color] = []
	var seen := {}
	for y in art.get_height():
		for x in art.get_width():
			var c := art.get_pixel(x, y)
			if c.a < 0.5:
				continue
			var key := _key(c)
			if seen.has(key):
				continue
			seen[key] = true
			var index := _lut_index(lut, c)
			if _mapped(table, index, 0) == 0:
				continue          # not a recoloured index
			if _is_palette_colour(palette, index, c):
				if exact_ones.size() < COLOURS / 2:
					exact_ones.append(c)
			elif inexact.size() < COLOURS / 2:
				inexact.append(c)
			if exact_ones.size() >= COLOURS / 2 \
					and inexact.size() >= COLOURS / 2:
				break
	t.note("%d source colours are palette entries, %d are not"
		% [exact_ones.size(), inexact.size()])
	# Both halves have to be represented, or the suite could pass while only
	# testing the case the two transforms agree on.
	t.ok(exact_ones.size() >= 8, "enough palette-entry sources")
	t.ok(inexact.size() >= 8, "enough sources that are NOT palette entries")
	var out: Array[Color] = []
	out.append_array(exact_ones)
	out.append_array(inexact)
	return out


func _check_slot(t: T_, pack: Pack_, palette: Image, lut: Image, table: Image,
		sources: Array[Color], slot: int) -> void:
	var img := Image.create(sources.size(), ROWS, false, Image.FORMAT_RGBA8)
	for x in sources.size():
		for y in ROWS:
			img.set_pixel(x, y, sources[x])
	var strip := ImageTexture.create_from_image(img)

	var node := Strip.new()
	node.texture = strip
	node.material = _material(pack, slot)
	node.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	root.add_child(node)
	await process_frame
	node.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	var shot := root.get_texture().get_image()

	var worst := 0
	var worst_at := -1
	var checked := 0
	var quantised := 0
	var inexact := 0
	for x in sources.size():
		var got := shot.get_pixel(x, ROWS / 2)
		var want := _expected(palette, lut, table, sources[x], slot)
		var d := maxi(
			absi(int(round(got.r * 255.0)) - int(round(want.r * 255.0))),
			maxi(absi(int(round(got.g * 255.0)) - int(round(want.g * 255.0))),
				absi(int(round(got.b * 255.0)) - int(round(want.b * 255.0)))))
		if d > worst:
			worst = d
			worst_at = x
		checked += 1
		# Would the quantising version have produced this pixel instead? If a
		# source is not a palette entry the two differ, and counting it tells
		# the failure apart from a rounding drift.
		var index := _lut_index(lut, sources[x])
		var mapped := _mapped(table, index, slot)
		if mapped != 0 and not _is_palette_colour(palette, index, sources[x]):
			inexact += 1
			var dst := palette.get_pixel(mapped, 0)
			if absi(int(round(got.r * 255.0)) - int(round(dst.r * 255.0))) <= 1 \
					and absi(int(round(got.g * 255.0))
						- int(round(dst.g * 255.0))) <= 1:
				quantised += 1

	t.ok(checked == sources.size(), "player %d: %d pixels read back"
		% [slot, checked])
	t.ok(worst <= TOLERANCE,
		"player %d: the shader matches the tables everywhere (worst %d at "
			% [slot, worst] + "colour %d, budget %d)" % [worst_at, TOLERANCE])
	# Relative to how many sources are NOT palette entries, because those are
	# the only ones where the two transforms differ at all. If the shader
	# quantised, every one of them would land on `palette[mapped]`; a minority
	# coinciding is just pixels that happen to sit near their palette entry.
	t.ok(quantised * 2 < inexact,
		("player %d: %d of %d non-palette pixels coincide with the quantised "
			+ "transform — under half, so the shader is not quantising")
			% [slot, quantised, inexact])
	t.note("player %d: worst deviation %d/255, %d of %d non-palette pixels "
		% [slot, worst, quantised, inexact] + "match the quantised form")
	node.queue_free()


func _material(pack: Pack_, slot: int) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://scripts/render/recolour.gdshader")
	mat.set_shader_parameter("tinted", true)
	mat.set_shader_parameter("exact_remap", true)
	mat.set_shader_parameter("player_slot", slot)
	mat.set_shader_parameter("remap_palette", pack.remap_palette())
	mat.set_shader_parameter("remap_lut", pack.remap_lut())
	mat.set_shader_parameter("remap_table", pack.remap_table())
	var c := Const_.player_colour_f(slot)
	mat.set_shader_parameter("target_colour", Vector3(c.r, c.g, c.b))
	return mat


# ---------------------------------------------------------------------------
# The same transform, in GDScript. Deliberately written from the shader's
# comment rather than transcribed from its code, so a shared mistake needs to
# be made twice.
# ---------------------------------------------------------------------------
func _expected(palette: Image, lut: Image, table: Image, src: Color,
		slot: int) -> Color:
	var index := _lut_index(lut, src)
	var mapped := _mapped(table, index, slot)
	if mapped == 0:
		return Color(src.r, src.g, src.b, 1.0)
	var s := palette.get_pixel(index, 0)
	var d := palette.get_pixel(mapped, 0)
	var out := Vector3()
	var sv := Vector3(s.r, s.g, s.b)
	var dv := Vector3(d.r, d.g, d.b)
	var pv := Vector3(src.r, src.g, src.b)
	for i in 3:
		if sv[i] > 8.0 / 255.0:
			out[i] = pv[i] * dv[i] / sv[i]
		else:
			out[i] = pv[i] + (dv[i] - sv[i])
	var m: float = maxf(out.x, maxf(out.y, out.z))
	if m > 1.0:
		out /= m
	return Color(clampf(out.x, 0.0, 1.0), clampf(out.y, 0.0, 1.0),
		clampf(out.z, 0.0, 1.0), 1.0)


## The five-bit reduction the ANI stored, then COLOR.PAL's lookup.
static func _lut_index(lut: Image, c: Color) -> int:
	var r5 := int(round(c.r * 255.0)) >> 3
	var g5 := int(round(c.g * 255.0)) >> 3
	var b5 := int(round(c.b * 255.0)) >> 3
	var idx := (r5 << 10) | (g5 << 5) | b5
	return int(round(lut.get_pixel(idx & 255, idx >> 8).r * 255.0))


static func _mapped(table: Image, index: int, slot: int) -> int:
	return int(round(table.get_pixel(index, slot).r * 255.0))


static func _is_palette_colour(palette: Image, index: int, c: Color) -> bool:
	var p := palette.get_pixel(index, 0)
	return int(round(p.r * 255.0)) >> 3 == int(round(c.r * 255.0)) >> 3 \
		and int(round(p.g * 255.0)) >> 3 == int(round(c.g * 255.0)) >> 3 \
		and int(round(p.b * 255.0)) >> 3 == int(round(c.b * 255.0)) >> 3


static func _key(c: Color) -> int:
	return (int(round(c.r * 255.0)) << 16) | (int(round(c.g * 255.0)) << 8) \
		| int(round(c.b * 255.0))


## A node that draws one texture at the origin, 1:1, through its material.
class Strip extends Node2D:
	var texture: Texture2D = null

	func _draw() -> void:
		if texture != null:
			draw_texture(texture, Vector2.ZERO)
