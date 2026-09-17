# The original's bitmap font, as tools/fonts.py decodes it.
#
# WHY THIS SUITE EXISTS. The `.FON` layout has four parameters — where the
# table starts, whether each entry is (offset, width) or (width, offset), how
# many rows a glyph has, and which character code entry zero belongs to — and
# THREE OF THE FOUR WERE GUESSED WRONG FIRST. Every wrong guess produced
# almost-readable text: one of them drew every capital correctly and every
# lowercase letter as the letter after it.
#
# So "every printable character has a glyph" is not enough, because a
# one-character shift keeps that true. These assertions are shift-sensitive:
# they compare glyph widths against the shape of the letters.
extends SceneTree

const T_ := preload("res://tests/t.gd")
const Pack_ := preload("res://scripts/render/pack.gd")
const BitFont_ := preload("res://scripts/render/bitfont.gd")


func _init() -> void:
	var t := T_.new("fonts")
	var pack: Pack_ = Pack_.new()
	if not pack.load_from(Pack_.default_dir()):
		t.note(pack.error)
		t.note("skipping: no asset pack")
		quit(t.finish())
		return

	_test_it_loads(t, pack)
	_test_every_printable_glyph(t, pack)
	_test_widths_match_the_letters(t, pack)
	_test_measuring(t, pack)
	quit(t.finish())


func _test_it_loads(t: T_, pack: Pack_) -> void:
	for name in ["font1", "font6"]:
		t.ok(pack.has_font(name), "the pack has %s" % name)
		var font: BitFont_ = BitFont_.new()
		t.ok(font.load_from(pack, name), "%s loads" % name)
		t.eq(font.height, 16, "%s is 16 pixels tall" % name)
	var missing: BitFont_ = BitFont_.new()
	t.ok(not missing.load_from(pack, "nosuchfont"),
		"and an absent font fails rather than half-loading")


func _test_every_printable_glyph(t: T_, pack: Pack_) -> void:
	var font: BitFont_ = BitFont_.new()
	font.load_from(pack, "font1")
	var absent: Array[String] = []
	for code in range(32, 127):
		if font.width_of(char(code)) <= 0:
			absent.append(char(code))
	t.eq(absent.size(), 0,
		"every printable ASCII draws (missing: %s)" % "".join(absent))


# The shift-sensitive part. A font shifted by one code still has a glyph for
# every character; what it does NOT have is the right SHAPE for each, and width
# is the cheapest measurable proxy for shape.
func _test_widths_match_the_letters(t: T_, pack: Pack_) -> void:
	var font: BitFont_ = BitFont_.new()
	font.load_from(pack, "font1")

	# The narrow letters must be narrower than the wide ones. Shifted by one,
	# 'i' takes 'h''s width and 'l' takes 'k''s, and this fails.
	for narrow in ["i", "l", "j", ".", ",", "'", "!"]:
		for wide in ["m", "w", "W", "M", "@"]:
			t.ok(font.width_of(narrow) < font.width_of(wide),
				"'%s' (%d) is narrower than '%s' (%d)"
					% [narrow, font.width_of(narrow), wide,
						font.width_of(wide)])

	# 'm' and 'w' are the widest lowercase letters in almost every face.
	var widest := ""
	var widest_w := 0
	for code in range(97, 123):
		var w := font.width_of(char(code))
		if w > widest_w:
			widest_w = w
			widest = char(code)
	t.ok(widest == "m" or widest == "w",
		"the widest lowercase letter is m or w, not '%s'" % widest)

	# The space is 12 px in a 16 px font — WIDER than 'n' at 10, which is
	# generous and is what the file says. An assertion that a space is
	# narrower than a letter failed here, and the font was right.
	var space := font.width_of(" ")
	t.ok(space > 0, "a space has width (%d)" % space)
	t.ok(space <= font.width_of("W"),
		"and is no wider than the widest letter (%d vs %d)"
			% [space, font.width_of("W")])

	# The widths that pin the decode. Shifted by one code, every one of these
	# takes its neighbour's number.
	t.eq(font.width_of("i"), 4, "'i' is 4 px")
	t.eq(font.width_of("l"), 5, "'l' is 5")
	t.eq(font.width_of("."), 3, "'.' is 3")
	t.eq(font.width_of("m"), 13, "'m' is 13")
	t.eq(font.width_of("w"), 14, "'w' is 14")
	t.eq(font.width_of("W"), 15, "and 'W' is 15")


func _test_measuring(t: T_, pack: Pack_) -> void:
	var font: BitFont_ = BitFont_.new()
	font.load_from(pack, "font1")
	t.eq(font.width_of(""), 0, "an empty string is zero wide")

	# Measuring must be additive, or centring is wrong by a growing amount.
	var a := font.width_of("Start")
	var b := font.width_of(" Game")
	var whole := font.width_of("Start Game")
	t.eq(whole, a + b + BitFont_.TRACKING,
		"measuring is additive across a join (%d vs %d + %d + 1)"
			% [whole, a, b])

	# And a real menu line has to fit the screen, which is what the measure is
	# for.
	for line in ["Start Network Game", "Diseases Can Be Destroyed",
			"Lost net players revert to AIs"]:
		t.ok(font.width_of(line) < 560,
			"'%s' is %d px, inside the screen" % [line, font.width_of(line)])
