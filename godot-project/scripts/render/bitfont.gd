# Draws text with the original's own bitmap font.
#
# The lettering on every screen is `FONT1.FON` from the install root — not
# `KFONT.ANI`, which turned out to be ten digits and an infinity sign for the
# clock. `tools/fonts.py` decodes the format and explains how it was
# established; three of its four parameters were guessed wrong first, and every
# wrong guess produced almost-readable text.
#
# The glyph sheet is WHITE on transparent, so a colour is a modulate. That is
# what lets one sheet serve the menu's yellow, the cursor's highlight and the
# dimmed text of an option that cannot be chosen.
extends RefCounted

const Pack_ := preload("res://scripts/render/pack.gd")

## One pixel between glyphs. The font carries no kerning or advance table —
## each glyph's width IS its advance — so the gap is ours, and one pixel is
## what makes the packed proof read like the original's screens.
const TRACKING := 1

var height: int = 16
var loaded: bool = false

var _texture: Texture2D = null
## character code -> Rect2 in the sheet
var _glyphs: Dictionary = {}


func load_from(pack: Pack_, name: String = "font1") -> bool:
	loaded = false
	_glyphs.clear()
	if pack == null or not pack.has_font(name):
		return false
	var font: Dictionary = pack.font(name)
	_texture = font["texture"]
	height = int(font["height"])
	for code in font["glyphs"]:
		var span: Array = font["glyphs"][code]
		_glyphs[int(String(code))] = Rect2(float(span[0]), 0.0,
			float(span[1]), float(height))
	loaded = not _glyphs.is_empty()
	return loaded


## How wide `text` will be drawn.
func width_of(text: String) -> int:
	var w := 0
	for i in text.length():
		var code := text.unicode_at(i)
		if _glyphs.has(code):
			w += int((_glyphs[code] as Rect2).size.x) + TRACKING
		elif code == 32:
			w += _space_width() + TRACKING
	return maxi(0, w - TRACKING)


## The space, which the font does have a glyph for — but a missing one would
## otherwise collapse a sentence into one word.
func _space_width() -> int:
	if _glyphs.has(32):
		return int((_glyphs[32] as Rect2).size.x)
	return height / 3


## Draw `text` with its top-left at `at`. Returns the width drawn.
func draw(on: CanvasItem, at: Vector2, text: String,
		colour: Color = Color.WHITE) -> int:
	if not loaded:
		return 0
	var x := at.x
	for i in text.length():
		var code := text.unicode_at(i)
		if not _glyphs.has(code):
			if code == 32:
				x += float(_space_width() + TRACKING)
			continue
		var src: Rect2 = _glyphs[code]
		on.draw_texture_rect_region(_texture,
			Rect2(Vector2(x, at.y).round(), src.size), src, colour)
		x += src.size.x + TRACKING
	return int(x - at.x)


## Centred on `centre_x`.
func draw_centred(on: CanvasItem, centre_x: float, y: float, text: String,
		colour: Color = Color.WHITE) -> int:
	return draw(on, Vector2(centre_x - width_of(text) / 2.0, y), text, colour)


## Right-aligned so the text ENDS at `right`.
func draw_right(on: CanvasItem, right: float, y: float, text: String,
		colour: Color = Color.WHITE) -> int:
	return draw(on, Vector2(right - width_of(text), y), text, colour)
