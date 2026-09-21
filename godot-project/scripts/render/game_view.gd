# Draws one simulation frame. Reads the sim; never writes to it.
#
# INTERPOLATION. The simulation runs at a fixed 20 Hz and the display does not,
# so drawing the sim's raw position would show 20 distinct positions a second
# and read as a stutter at any refresh rate above that. Every actor is drawn
# between its previous tick's position and its current one, using the fraction
# of a tick the accumulator is holding.
#
# That fraction comes from the sim and is never fed back into it. The sim has no
# floats in it and no knowledge that a renderer exists; this is the only place
# a fractional position is computed, and it is discarded every frame.
extends Node2D

const Const_ := preload("res://scripts/core/const.gd")
const Types_ := preload("res://scripts/core/types.gd")
const Field_ := preload("res://scripts/sim/field.gd")
const Player_ := preload("res://scripts/sim/player.gd")
const Pack_ := preload("res://scripts/render/pack.gd")
const Sim_ := preload("res://scripts/sim/sim.gd")
const Values_ := preload("res://scripts/core/values.gd")

## Centipixels to pixels.
const CP := Player_.CP

var sim: Sim_ = null
var pack: Pack_ = null

## Which level's art to use — picks the tiles, xbrick and background sheets.
var level: int = 0

## 0.0 to 1.0 through the current tick, for interpolation.
var alpha: float = 0.0

## Draw the cell grid and the collision boxes. Off by default; the run script
## turns it on with --debug-grid.
var show_grid: bool = false

## The test editor (T): place bricks and powerups, spawn bombs, kill or
## disease a player, all live in a running round, for exercising every
## mechanic without depending on a scheme's own layout. main.gd owns the
## input and the sim calls; this only reads the state back to draw the cursor
## and the on-screen legend.
var editor_active: bool = false
var editor_cursor: Vector2i = Vector2i(-1, -1)
var editor_powerup: int = 0

## Types.PowerUp's thirteen values in order — the same list POWERUP_SEQ below
## uses for its art sequence names, reused here for the legend's plain names.
const EDITOR_POWERUP_NAMES := ["bomb", "flame", "disease", "kick", "skate",
	"punch", "grab", "spooge", "goldflame", "trigger", "jelly",
	"super bad disease", "random"]

## The pre-game lobby (scripts/net/server.gd's State.WAITING) — no sim exists
## yet, so `_draw()` cannot fall back to reading one the way it does for
## gameplay. Plain data, not a Client_ reference, on purpose: this file reads
## a Sim and now this, and does not otherwise know netcode exists (client.gd's
## own header comment). main.gd copies these from `client.lobby_*` each frame
## it isn't yet playing.
var lobby_active: bool = false
var lobby_roster: Array = []
var lobby_is_host: bool = false
var lobby_room_code: String = ""

## Which slots THIS viewer actually controls — populated by main.gd from its
## own keyset/pad slot lists, the same for local, host and join (a joining
## client still drives its own keyset locally and sends the result to the
## server). Only this list, not the sim, can say "you" — the INVISIBLE
## disease's own comment is "you cannot see yourself", not "nobody can see
## you", so it has to be judged per viewer rather than per player.
var local_slots: Array[int] = []

## How long the HURRY banner stays up, in wall steps. hurry_index counts the
## cells the closing wall has filled, and one is filled every 8 ticks, so 6 is
## about two and a half seconds of flashing.
const HURRY_BANNER_TICKS := 6

## KFONT's `numeric font` is eleven steps: the ten digits, then the colon.
const COLON_STEP := 10
## The tallest digit, for sitting shorter glyphs on the same baseline.
const DIGIT_H := 27.0

## The match, when there is one. Null in a bare render test. Read-only here:
## the view shows the score, it never keeps it.
var the_match = null

# Previous tick's player positions in centipixels, for interpolation. Keyed by
# slot so a player joining or leaving mid-round cannot shift the array.
var _prev_pos: Dictionary = {}
var _prev_tick: int = -1


## The recolour shader belongs to a NODE, so each player colour needs its own.
##
## Two groups, drawn in this order, each holding one node per slot plus one
## untinted node:
##
##   _under   bombs and flames  — AtomBomberman's notes: the flame is "drawn
##                                under (before) bomberman"
##   _over    shadows and players
##
## Grouping this way keeps the layering right across players. Ten nodes in one
## group would have drawn all of slot 5's flames over slot 2's player.
var _under: Node2D = null
var _over: Node2D = null
var _under_slot: Array[Node2D] = []
var _over_slot: Array[Node2D] = []
var _under_plain: Node2D = null
var _over_plain: Node2D = null

## The status band, drawn ABOVE the actors.
##
## A standing bomberman is 67 px of ink over a 36 px cell, so one on the top
## row reaches a long way into the band. Clipping it there cut the sprite in
## half — it read as the player being behind the wall. Letting it through
## instead put a bomberman through the score. Drawing the band last does both
## jobs: the sprite is whole, and the numbers stay readable over it.
var _hud: Node2D = null


func _ready() -> void:
	z_as_relative = false
	_under = Node2D.new()
	_over = Node2D.new()
	# The field is drawn by this node, which carries no material, so it is
	# never recoloured. Both groups are children added after, so they draw on
	# top of it and in the order added.
	add_child(_under)
	add_child(_over)
	for group in [[_under, _under_slot], [_over, _over_slot]]:
		var parent: Node2D = group[0]
		var list: Array[Node2D] = group[1]
		var is_over: bool = parent == _over
		# THE UNTINTED NODE COMES FIRST IN THE OVER GROUP, because that is
		# where the shadows are drawn and a shadow goes under its player.
		# Added last, it drew a black ellipse over every bomberman's feet.
		if is_over:
			_over_plain = _make_tint_node(-1, "over")
			parent.add_child(_over_plain)
		for slot in range(Const_.PLAYER_COUNT):
			var node := _make_tint_node(slot, "under" if not is_over else "over")
			parent.add_child(node)
			list.append(node)
		if not is_over:
			_under_plain = _make_tint_node(-1, "under")
			parent.add_child(_under_plain)
	# Last child, so it is drawn over the actors.
	_hud = HudNode.new()
	_hud.view = self
	add_child(_hud)


func _make_tint_node(slot: int, group: String) -> Node2D:
	var node := TintNode.new()
	node.view = self
	node.slot = slot
	node.group = group
	node.material = _make_material(slot)
	return node


func _make_material(slot: int) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://scripts/render/recolour.gdshader")
	if slot < 0:
		mat.set_shader_parameter("tinted", false)
	else:
		mat.set_shader_parameter("tinted", true)
		var c := Const_.player_colour(slot)
		mat.set_shader_parameter("target_colour",
			Vector3(c.x / 100.0, c.y / 100.0, c.z / 100.0))
		mat.set_shader_parameter("player_slot", slot)
		# The disc's own remap tables when the pack has them, and fpc_atomic's
		# heuristic when it does not. The target_colour above is set either way,
		# because a pack without the tables is the fallback's whole reason for
		# existing. scripts/render/recolour.gdshader has the measurements.
		# AB_EXACT_REMAP=0 forces the heuristic even when the tables are
		# there. What the comparison screenshots use, and the only way to
		# exercise the fallback path on a machine that has the real disc.
		var allow := OS.get_environment("AB_EXACT_REMAP") != "0"
		if allow and pack != null and pack.has_remap():
			mat.set_shader_parameter("exact_remap", true)
			mat.set_shader_parameter("remap_palette", pack.remap_palette())
			mat.set_shader_parameter("remap_lut", pack.remap_lut())
			mat.set_shader_parameter("remap_table", pack.remap_table())
	return mat


## The node a given slot's sprites are drawn on, in a given group.
func _node_for(group: String, slot: int) -> Node2D:
	var list: Array[Node2D] = _under_slot if group == "under" else _over_slot
	if list.is_empty():
		return null
	if slot < 0 or slot >= Const_.PLAYER_COUNT:
		return _under_plain if group == "under" else _over_plain
	return list[slot]


func queue_redraw_all() -> void:
	queue_redraw()
	for list in [_under_slot, _over_slot]:
		for node in list:
			node.queue_redraw()
	# The untinted nodes and the status band are children too. Leaving the band
	# out froze the clock: it drew once and never again, which looked like a
	# stopped timer rather than a missing redraw.
	if _under_plain != null:
		_under_plain.queue_redraw()
	if _over_plain != null:
		_over_plain.queue_redraw()
	if _hud != null:
		_hud.queue_redraw()


## Call once per tick, from whatever owns the sim, BEFORE the tick runs.
## Snapshots where everyone is so the next frame can interpolate from it.
func snapshot() -> void:
	if sim == null:
		return
	for p in sim.players:
		_prev_pos[p.slot] = Vector2i(p.x, p.y)
	_prev_tick = sim.tick_count


func _draw() -> void:
	if sim == null:
		if lobby_active:
			_draw_lobby()
		else:
			_draw_missing()
		return
	if pack == null or not pack.loaded:
		_draw_missing()
		return

	_draw_background()
	_draw_field()
	_draw_specials()
	_draw_powerups()
	_draw_creatures()
	# Bombs, flames, shadows and players are drawn by _actors, through the
	# recolour shader. Its draw order is bombs, flames, shadows, players:
	# AtomBomberman's notes say the flame is "drawn under (before) bomberman",
	# and shadows before both.
	# The scoreboard, the clock and the HURRY banner are drawn by _hud, the
	# last child, so a player standing on the top row passes UNDER them
	# instead of through them.
	if show_grid:
		_draw_debug_grid()
	if editor_active:
		_draw_test_editor()


func _draw_missing() -> void:
	# A blank window is indistinguishable from a hang, so say what is wrong.
	var msg := "no asset pack loaded"
	if pack != null and not pack.error.is_empty():
		msg = pack.error
	draw_rect(Rect2(0, 0, Const_.SCREEN_W, Const_.SCREEN_H), Color(0.05, 0.05, 0.08))
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(16, 40), msg, HORIZONTAL_ALIGNMENT_LEFT,
		Const_.SCREEN_W - 32, 12, Color(1, 0.5, 0.4))


## The score, and who won.
##
## Text, not the original's art. The original has a statistics screen and a
## victory screen of its own and neither is extracted yet (docs/PLAN.md track
## B); a legible number beats a blank corner in the meantime, and the layout is
## deliberately plain so that replacing it is not a refactor.
##
## Drawn in the top border, above FIELD_Y_OFF, which is where the original's
## own status area is.
## Everything the status band carries, drawn by _hud after the actors.
func draw_hud(on: CanvasItem) -> void:
	_draw_scoreboard(on)


func _draw_scoreboard(on: CanvasItem) -> void:
	if the_match == null or sim == null:
		return

	# THE STATUS AREA is the band above the playfield — 68 px at 640x480, and
	# whatever `map.c`'s Y_ORIGIN leaves at any other size. The eleven level
	# backgrounds leave it plain, so everything in it is drawn here.
	#
	# The ART is the original's where the original has art for it: KFONT.ANI's
	# ten digits and its infinity sign draw the clock and the win counts, and
	# MESSAGES.TXT 281 gives the clock's own format, "%u:%02u".
	#
	# KFACE.ANI is NOT used here, though it was at first. It is 40x40 and has
	# four directional frames, which reads like a status head — and it is a
	# photographed human face, the Kurt-head easter egg player. KURTHEAD.PCX
	# beside it in RES/ is the same person. Seven identical photographs across
	# the top of the playfield is how that mistake looked.
	#
	# So the per-player marker is a disc in that player's colour, which is this
	# port's and is marked as such: no art on the disc has been identified as
	# the original's in-game readout, and the eleven level backgrounds leave
	# this band plain.
	#
	# The LAYOUT is this port's. The original draws its status area in code and
	# that code is not read yet (docs/BUGS.md Q5), so the arrangement below —
	# heads across the band at a 62 px pitch, the clock at the left — is a
	# choice, not a reconstruction.
	var seats: Array = []
	for p in sim.players:
		if p.in_play:
			seats.append(p)
	if seats.is_empty():
		return

	_draw_clock(on)

	# EVERYTHING HERE FITS INSIDE Const_.HUD_H — 42 px, which is what the
	# eleven backgrounds leave blank. It did not: the heads were centred on
	# y=30 with a 13 px radius, so they ran to y=43 and out of the panel.
	#
	# The pitch is computed rather than fixed at 62. Ten seats at 62 needed
	# 620 px of a 514 px band, and the old code clamped the left edge instead
	# of the spacing — so a ten-player game drew four of its heads off the
	# right of the screen.
	var left_edge := 118.0
	var span := Const_.SCREEN_W - 8.0 - left_edge
	var pitch: float = minf(62.0, span / float(seats.size()))
	var first: float = Const_.SCREEN_W - 8.0 - pitch * seats.size()
	for i in seats.size():
		var p = seats[i]
		var x := first + i * pitch
		var centre := Vector2(x + 13.0, 21.0)
		var colour := Const_.player_colour_f(p.slot)
		var alive: bool = p.alive and not p.dying
		on.draw_circle(centre, 12.0, Color(0, 0, 0, 0.45))
		on.draw_circle(centre, 10.0,
			colour if alive else colour.darkened(0.65))
		if not alive:
			# Struck through, so the readout says who is still in it.
			on.draw_line(centre + Vector2(-8, 8), centre + Vector2(8, -8),
				Color(0.05, 0.05, 0.05, 0.9), 3.0)
		# The win count beside it, in the game's own digits.
		_draw_digits(on, the_match.wins_of(p.slot), Vector2(x + 26.0, 12.0),
			0.6)

	if the_match.over():
		_draw_banner(on, ThemeDB.fallback_font, the_match.summary().to_upper())
	elif sim.round_over():
		var who := "DRAW"
		if sim.winner_slot >= 0:
			who = "PLAYER %d WINS THE ROUND" % (sim.winner_slot + 1)
		elif sim.winner_team >= 0:
			who = "TEAM %d WINS THE ROUND" % sim.winner_team
		_draw_banner(on, ThemeDB.fallback_font, who)
	elif sim.hurry_index >= 0 and sim.hurry_index < HURRY_BANNER_TICKS:
		_draw_hurry(on)


## The round clock, in KFONT's digits. MESSAGES.TXT 281 is "%u:%02u" and 280 is
## "Infinite", and KFONT.ANI carries an `infinity` sequence for exactly that.
func _draw_clock(on: CanvasItem) -> void:
	var left := 12.0
	# KFONT's digits are 27 px tall and the panel is 42, so 8 leaves a 7 px
	# margin either side. At 16 the clock ran to y=43 and out of the panel.
	var top := 8.0
	var seconds: int = maxi(0, sim.seconds_left())
	if sim.time_left <= 0 and Values_.V[Const_.Res.ROUND_SECONDS] <= 0:
		_draw_infinity(on, Vector2(left, top))
		return
	var minutes := seconds / 60
	var rest := seconds % 60
	var x := _draw_digits(on, minutes, Vector2(left, top), 1.0)
	# KFONT HAS a colon: `numeric font` is eleven steps, ten digits `D0`..`D9`
	# and then `DC.TGA`, 6x19. Two drawn squares stood in for it until the
	# sequence was counted.
	var colon := _draw_colon(on, Vector2(left + x + 3.0, top))
	_draw_digits(on, rest, Vector2(left + x + colon + 6.0, top), 1.0, 2)


## `value` in KFONT digits, right-aligned on `at`. Returns the width drawn.
func _draw_digits(on: CanvasItem, value: int, at: Vector2, scale: float,
		pad_to: int = 0) -> float:
	if not pack.has_sequence("kfont", "numeric font"):
		# No art: the fallback font, so a clock is never simply absent.
		on.draw_string(ThemeDB.fallback_font, at, str(value),
			HORIZONTAL_ALIGNMENT_LEFT, -1, int(20 * scale),
			Color(1, 0.95, 0.6))
		return 20.0 * scale
	var text := str(value)
	while text.length() < pad_to:
		text = "0" + text
	var steps := pack.sequence_steps("kfont", "numeric font")
	# Drawn from the TOP-LEFT and advanced by width, ignoring the hotspots.
	# KFONT's frames are a font, and a font's advance is its width; anchoring
	# each digit on its own hotspot made the returned advance disagree with
	# where the digits actually landed, which put the clock's colon in the
	# wrong place.
	var x := 0.0
	for i in text.length():
		var digit := text.unicode_at(i) - 48
		if digit < 0 or digit >= steps.size():
			continue
		var index: int = steps[digit]
		var src := pack.frame_rect("kfont", index)
		var size := src.size * scale
		on.draw_texture_rect_region(pack.texture_of("kfont"),
			Rect2((at + Vector2(x, 0.0)).round(), size), src, Color.WHITE)
		x += size.x + 1.0
	return x


## KFONT's colon, step 10 of its numeric font. Returns the width drawn.
func _draw_colon(on: CanvasItem, at: Vector2) -> float:
	var steps := pack.sequence_steps("kfont", "numeric font")
	if steps.size() <= COLON_STEP:
		return 0.0
	var src := pack.frame_rect("kfont", steps[COLON_STEP])
	# Sat on the digits' baseline rather than their top: the colon is 19 px
	# where a digit is 26.
	on.draw_texture_rect_region(pack.texture_of("kfont"),
		Rect2((at + Vector2(0.0, DIGIT_H - src.size.y)).round(), src.size),
		src, Color.WHITE)
	return src.size.x


func _draw_infinity(on: CanvasItem, at: Vector2) -> void:
	if not pack.has_sequence("kfont", "infinity"):
		return
	var index := pack.sequence_frame("kfont", "infinity", 0)
	if index < 0:
		return
	var src := pack.frame_rect("kfont", index)
	var hot := pack.frame_hotspot("kfont", index)
	on.draw_texture_rect_region(pack.texture_of("kfont"),
		Rect2((at - hot).round(), src.size), src, Color.WHITE)


## HURRY.ANI: one 278x91 banner. Resource 101 says the message flashes at 60
## seconds remaining, and its comment is unusually firm that the value should
## not be changed.
func _draw_hurry(on: CanvasItem) -> void:
	if not pack.has_sequence("hurry", "hurry"):
		return
	var index := pack.sequence_frame("hurry", "hurry", 0)
	if index < 0:
		return
	var src := pack.frame_rect("hurry", index)
	# Flashing, which is what "flashes across the screen" describes.
	if (sim.hurry_index / 4) % 2 == 1:
		return
	var at := Vector2((Const_.SCREEN_W - src.size.x) / 2.0,
		Const_.FIELD_Y_OFF + (Const_.FIELD_H * Const_.BLOCK_H
			- src.size.y) / 2.0)
	on.draw_texture_rect_region(pack.texture_of("hurry"),
		Rect2(at.round(), src.size), src, Color.WHITE)


## The round-over and match-over line, across the middle of the playfield.
##
## Text, not art: the original announces a round with MESSAGES.TXT 120/121 and
## its own screens, which the port shows AFTER the match rather than during it
## (scripts/app/screens.gd). This is the between-rounds line.
func _draw_banner(on: CanvasItem, font: Font, text: String) -> void:
	var w := Const_.SCREEN_W
	on.draw_rect(Rect2(0, Const_.SCREEN_H / 2 - 24, w, 48), Color(0, 0, 0, 0.55))
	on.draw_string(font, Vector2(0, Const_.SCREEN_H / 2 + 8), text,
		HORIZONTAL_ALIGNMENT_CENTER, w, 22, Color(1, 0.95, 0.6))


func _draw_background() -> void:
	var bg := pack.background(level)
	if bg != null:
		draw_texture(bg, Vector2.ZERO)
	else:
		draw_rect(Rect2(0, 0, Const_.SCREEN_W, Const_.SCREEN_H),
			Color(0.06, 0.08, 0.06))


func _draw_field() -> void:
	var tiles := "tiles%d" % level
	var xbrick := "xbrick%d" % level
	var has_tiles := pack.has_sheet(tiles)

	for ty in Const_.FIELD_H:
		for tx in Const_.FIELD_W:
			var origin := Vector2(Const_.tile_origin(tx, ty))
			var kind: int = sim.field.brick_at(tx, ty)

			# A cell mid-disintegration shows the xbrick animation rather than
			# the blank it has already become.
			var timer: int = sim.field.brick_timer[Field_.idx(tx, ty)]
			if timer > 0 and pack.has_sheet(xbrick):
				var total := pack.frame_count(xbrick)
				var anim_len: int = sim.brick_anim_ticks()
				# Timer counts DOWN from anim_len, so elapsed is the complement.
				var elapsed: int = anim_len - timer
				var index: int = clampi(
					int(float(elapsed) / maxf(1.0, float(anim_len)) * total),
					0, total - 1)
				_draw_frame(xbrick, index, origin, false)
				continue

			if kind == Types_.Brick.BLANK:
				if has_tiles:
					_draw_seq_frame(tiles, "tile %d blank" % level, origin, 0)
				continue
			if not has_tiles:
				# No art: still show the structure, or the field reads as empty.
				draw_rect(Rect2(origin, Vector2(Const_.BLOCK_W, Const_.BLOCK_H)),
					Color(0.45, 0.35, 0.25) if kind == Types_.Brick.BRICK
					else Color(0.3, 0.3, 0.35))
				continue
			var seq := "tile %d brick" % level if kind == Types_.Brick.BRICK \
				else "tile %d solid" % level
			_draw_seq_frame(tiles, seq, origin, 0)


## Arrows, conveyors, warp gates and trampolines.
##
## Drawn on the field layer, below the actors and above the tiles: they are part
## of the floor. EXTRAS.ANI names its own sequences — the four arrows, the warp
## hole, the trampoline rings — and CONVEYOR.ANI holds the belt cells.
func _draw_specials() -> void:
	for ty in Const_.FIELD_H:
		for tx in Const_.FIELD_W:
			var origin := Vector2(Const_.tile_origin(tx, ty))

			var belt := sim.field.conveyor_at(tx, ty)
			if belt != Types_.Dir.NONE and pack.has_sheet("conveyor"):
				# The belt animates, so it reads as moving rather than as
				# painted-on floor.
				var seq := "extra conveyor %s" % _dir_word(belt)
				if pack.has_sequence("conveyor", seq):
					_draw_seq_frame("conveyor", seq, origin, sim.tick_count)
				else:
					# Should not happen: CONVEYOR.ANI names all four. Drawing
					# the first frame beats drawing nothing if it ever does.
					_draw_frame("conveyor", 0, origin, false)

			var arr := sim.field.arrow_at(tx, ty)
			if arr != Types_.Dir.NONE and pack.has_sheet("extras"):
				var seq2 := "extra arrow %s" % _dir_word(arr)
				if pack.has_sequence("extras", seq2):
					_draw_seq_frame("extras", seq2, origin, 0)

			if sim.field.warp_at(tx, ty) >= 0 and pack.has_sheet("extras"):
				# The original calls it "extra warp 1", not "warp".
				if pack.has_sequence("extras", "extra warp 1"):
					_draw_seq_frame("extras", "extra warp 1", origin,
						sim.tick_count)

			if sim.field.tramp_at(tx, ty) and pack.has_sheet("extras"):
				if pack.has_sequence("extras", "extra trampoline"):
					_draw_seq_frame("extras", "extra trampoline", origin,
						sim.tick_count)


## The word the original's own sequence names use for a direction.
static func _dir_word(dir: int) -> String:
	match dir:
		Types_.Dir.UP: return "north"
		Types_.Dir.DOWN: return "south"
		Types_.Dir.LEFT: return "west"
		Types_.Dir.RIGHT: return "east"
	return "north"


## The powerups lying on the field. Not recoloured — each has its own art, cut
## from POWERS.ANI at exactly one cell, which is why the 16 40x36 PCX files in
## the CD's RES/ folder line up with BLOCK_W x BLOCK_H.
##
## 'random' is an animation over the other icons rather than a still, which is
## how the original shows a random pickup, so it cycles with the tick.
func _draw_powerups() -> void:
	for ty in Const_.FIELD_H:
		for tx in Const_.FIELD_W:
			var which := sim.field.powerup[Field_.idx(tx, ty)]
			if which == Field_.NO_POWERUP:
				continue
			# A powerup is HIDDEN UNDER a brick and only shows once the brick
			# is destroyed. Drawing it regardless put icons on top of intact
			# bricks, which tests/render_field.gd caught on the first run.
			if sim.field.brick_at(tx, ty) != Types_.Brick.BLANK:
				continue
			var origin := Vector2(Const_.tile_origin(tx, ty))
			if not pack.has_sheet("powers"):
				draw_rect(Rect2(origin + Vector2(10, 8), Vector2(20, 20)),
					Color(1.0, 0.9, 0.2))
				continue
			var seq := "power %s" % _powerup_seq(which)
			if pack.has_sequence("powers", seq):
				# A powerup sits on the cell, not on a hotspot: its art IS a
				# cell.
				_draw_seq_frame("powers", seq, origin, sim.tick_count)


# POWERS.ANI names its sequences itself — "power bomb", "power kicker",
# "power disease3" for the super bad one, "power clog" for the roulette
# power-down. These are those names, indexed by Types.PowerUp.
const POWERUP_SEQ := ["bomb", "flame", "disease", "kicker", "skate", "punch",
	"grab", "spooge", "goldflame", "trigger", "jelly", "disease3", "random"]


static func _powerup_seq(which: int) -> String:
	if which < 0 or which >= POWERUP_SEQ.size():
		return "bomb"
	return POWERUP_SEQ[which]


## Bombs belonging to one slot. A bomb wears its OWNER's colour, not that of
## whoever set off the chain it ended up in.
func draw_bombs_of(on: CanvasItem, slot: int) -> void:
	if not pack.has_sheet("bombs"):
		for b in sim.bombs:
			if b.owner != slot:
				continue
			var c := Vector2(b.x, b.y) / CP
			on.draw_circle(c, 12.0, colour_of(b.owner))
		return
	for b in sim.bombs:
		if b.owner != slot:
			continue
		# A CARRIED bomb is not on the field. It is over its carrier's head,
		# and BOMBWALK.ANI draws the pair as one sprite — drawing it here as
		# well put a second bomb at the carrier's feet.
		if b.carried_by >= 0:
			continue
		# Bombs sit on the cell centre. The animation is driven by how long the
		# bomb has been alive, so every bomb is not on the same frame.
		var age: int = sim.tick_count - b.placed_tick
		# A flying bomb is lifted by its arc; resources 660 and 661 give the
		# peak height for the initial three-cell punch and the bounces after.
		var lift := 0.0
		if b.flying and b.fly_ticks > 0:
			var f := float(b.fly_tick) / float(b.fly_ticks)
			lift = -float(b.fly_height) * 4.0 * f * (1.0 - f)
		var at := Const_.actor_anchor(Vector2(b.x, b.y) / CP
			+ Vector2(0, lift))
		# A BOMB IN THE AIR is its own animation — PUNBOMB1..4, one file per
		# direction, ten frames of it tumbling. Punched bombs used to slide
		# through the air on the standing frame.
		#
		# PUNBOMB has one tumble per direction shared by every bomb kind — the
		# disc has no jelly-specific flight art (checked: each punbombN sheet
		# holds exactly one "punch <dir>" sequence). Using it for a jelly bomb
		# mid-arc makes it look like a plain thrown bomb until it lands, which
		# is the one moment jelly's own identity (the BOMBS.ANI wobble) drops
		# out. So a jelly bomb keeps its own look through the whole arc instead
		# of borrowing the generic tumble.
		if b.flying and not b.jelly_bounce:
			var sheet := "punbomb%d" % _punbomb_sheet(b.move_dir)
			var seq := "punch %s" % _compass(b.move_dir)
			if pack.has_sequence(sheet, seq):
				_draw_seq_frame(sheet, seq, at, b.fly_tick, true,
					Color.WHITE, on, true)
				continue
		_draw_bomb_frame(on, b, at, age)


## Which of BOMBS, TRIGBOMB and DUDS a bomb is drawn from.
##
## The disc has FOUR looks for a bomb and the port drew one of them. The other
## three are named as plainly as the first: `bomb jelly green` is a second
## sequence inside BOMBS.ANI, `bomb trigger green` is TRIGBOMB.ANI, and
## `bomb regular green dud` is DUDS.ANI. A trigger bomb that looks exactly like
## a timed one is unreadable — it is the difference between walking past a bomb
## and dying beside it.
func _draw_bomb_frame(on: CanvasItem, b, at: Vector2, age: int) -> void:
	var tries: Array = []
	if b.triggered:
		tries.append(["trigbomb", "bomb trigger green"])
	if b.state == Types_.BombState.DUD:
		tries.append(["duds", "bomb regular green dud"])
	if b.jelly_bounce or b.state == Types_.BombState.WOBBLE:
		tries.append(["bombs", "bomb jelly green"])
	tries.append(["bombs", "bomb regular green"])
	for pair in tries:
		if pack.has_sequence(pair[0], pair[1]):
			_draw_seq_frame(pair[0], pair[1], at, age, true, Color.WHITE,
				on, true)
			return


## PUNBOMB1..4 are south, north, west, east — the order the files are in, and
## the order their own sequence names give.
static func _punbomb_sheet(dir: int) -> int:
	match dir:
		Types_.Dir.DOWN: return 1
		Types_.Dir.UP: return 2
		Types_.Dir.LEFT: return 3
		Types_.Dir.RIGHT: return 4
	return 1


## Flame cells owned by one slot. After a chain reaction the owner is the
## player who STARTED the chain, so the fire wears their colour.
func draw_flames_of(on: CanvasItem, slot: int) -> void:
	if not pack.has_sheet("mflame"):
		for ty in Const_.FIELD_H:
			for tx in Const_.FIELD_W:
				if sim.field.has_flame(tx, ty) \
						and sim.field.flame_owner_at(tx, ty) == slot:
					on.draw_rect(Rect2(Vector2(Const_.tile_origin(tx, ty)),
						Vector2(Const_.BLOCK_W, Const_.BLOCK_H)),
						Color(1.0, 0.8, 0.2, 0.8))
		return

	for ty in Const_.FIELD_H:
		for tx in Const_.FIELD_W:
			var bits: int = sim.field.flame_at(tx, ty)
			if bits == 0:
				continue
			if sim.field.flame_owner_at(tx, ty) != slot:
				continue
			var elapsed: int = sim.field.flame_timer[Field_.idx(tx, ty)]
			# Timer counts down, so age up from it for a forward animation.
			var age: int = sim.flame_ticks() - elapsed
			for seq in _flame_sequences(bits):
				_draw_flame_piece(on, seq, tx, ty, age)


## One piece of one cell's flame, FLUSH ON ITS INBOUND EDGE.
##
## Not on the actor anchor, which is what every other sprite uses and what this
## used to do. MFLAME.ANI's frames carry no usable hotspot: every one of the
## 45 is stored at (width / 2, height - 1), the generic bottom-centre a
## converter writes when it has nothing better, so anchoring on it bottom-aligns
## them. The frames are bands of DIFFERENT heights — the west arm alone runs 23,
## 21, 19, 20, 23 over its five steps — so bottom-aligning them made the arms
## crawl up and down while the centre stayed put, and left the arms sitting
## about eight pixels below the centre's own crossbar. That is what "the middle
## sprite does not match the borders of the explosion" was.
##
## Centring both axes on the cell was tried next and is not right either: it
## assumes every piece fills its own axis, and measured against the real pack
## most do (mid pieces run 41 px on a 40 px cell, or 36-37 on 36) but a TIP does
## not — `flame tipeast green` is 34 px on a 40 px cell. Centring that piece
## opens a 3 px gap on BOTH sides, including the side facing the cell it is
## supposed to connect to, which is "the middle fire does not connect properly
## with the arm" for real pack data.
##
## What actually connects two pieces is their SHARED edge, not their midpoint:
## every piece is flush against the cell nearer the bomb (the "inbound" side)
## and free to fall short on the far side, which is where a tip's taper
## belongs. The cross axis (the one the arm does not travel along) is still
## centred, because nothing on the disc says a flame drifts sideways in its
## own lane.
func _draw_flame_piece(on: CanvasItem, seq: String, tx: int, ty: int,
		age: int) -> void:
	var index := pack.sequence_frame("mflame", seq, age)
	if index < 0:
		return
	var src := pack.frame_rect("mflame", index)
	var origin := Vector2(Const_.tile_origin(tx, ty))
	var at := origin
	if seq.contains("north"):
		at.x += _centre(Const_.BLOCK_W, src.size.x)
		at.y += Const_.BLOCK_H - src.size.y   # flush bottom: bomb is below
	elif seq.contains("south"):
		at.x += _centre(Const_.BLOCK_W, src.size.x)
		# flush top: bomb is above, origin.y already the top edge
	elif seq.contains("west"):
		at.x += Const_.BLOCK_W - src.size.x   # flush right: bomb is to the east
		at.y += _centre(Const_.BLOCK_H, src.size.y)
	elif seq.contains("east"):
		# flush left: bomb is to the west, origin.x already the left edge
		at.y += _centre(Const_.BLOCK_H, src.size.y)
	else:
		# the centre piece has no direction to be flush against
		at.x += _centre(Const_.BLOCK_W, src.size.x)
		at.y += _centre(Const_.BLOCK_H, src.size.y)
	# snap=false: a flame piece's centring offset is deliberately fractional
	# (Q10) and rounding it back to a pixel is exactly the bug this is fixing.
	_draw_frame("mflame", index, at, false, Color.WHITE, on, true, false)


## (cell - sprite) / 2, kept as an exact fraction — NOT floored, NOT left for
## `_draw_frame`'s `.round()` to settle. Two earlier attempts rounded this to
## a pixel and neither could be exactly right at once for every piece:
##
## Godot's `round()` breaks a .5 tie AWAY FROM ZERO — `round(-0.5) == -1` but
## `round(6.5) == 7` — so a piece narrower than the cell (positive offset) and
## one wider (negative offset) round to OPPOSITE sides of a tie even from the
## identical formula. Flooring first (the second attempt) made every offset
## already an integer so that rule stopped mattering, but only relocated the
## problem: `flame center green` is a constant 41 px (odd) on this 40 px
## (even) cell, so its true centred offset is exactly `-0.5` — there is no
## integer that is "centred", by construction, whichever way it rounds.
## `flame midnorth green`'s own five animation frames are 22, 27, 22, 24, 25 px
## wide (even, odd, even, even, odd), so on 3 of 5 ages its width shares the
## cell's even parity and floors to a *different* pixel than the odd-width
## centre piece does. Measured: a real, reproducible 0.5 design px (≈1.5
## device px at this project's default 3x integer scale) seam, present on
## exactly the frames the parities disagree on. docs/BUGS.md Q10.
##
## The actual fix is upstream of rounding: don't round a flame piece's
## position at all. `_draw_frame`'s `snap` parameter is `false` for every
## flame call, so the fractional offset computed here reaches
## `draw_texture_rect_region` untouched — Godot's canvas API takes floats
## natively, and a glow-style translucent sprite loses nothing visible to a
## 0.5 px shift the way a flat-shaded, hard-edged sprite (a player, a bomb)
## would. Every other sprite kind still goes through `_draw_frame`'s default
## `snap = true` and stays pixel-locked; only MFLAME's nine sequences ever
## call this function.
static func _centre(cell: int, sprite: float) -> float:
	return (cell - sprite) / 2.0


# MFLAME.ANI's nine sequences map one-to-one onto the flame bits the sim sets:
# a centre, and a mid and a tip for each of four directions. The sim's END bit
# marks the last cell of an arm, which is the "tip" art.
func _flame_sequences(bits: int) -> Array:
	var out: Array = []
	if bits & Types_.Flame.CROSS:
		out.append("flame center green")
	var tip: bool = (bits & Types_.Flame.END) != 0
	if bits & Types_.Flame.UP:
		out.append("flame %snorth green" % ("tip" if tip else "mid"))
	if bits & Types_.Flame.DOWN:
		out.append("flame %ssouth green" % ("tip" if tip else "mid"))
	if bits & Types_.Flame.LEFT:
		out.append("flame %swest green" % ("tip" if tip else "mid"))
	if bits & Types_.Flame.RIGHT:
		out.append("flame %seast green" % ("tip" if tip else "mid"))
	# A cell that is only END — the far tip of an arm whose direction bit was
	# not also set — still has to draw something.
	if out.is_empty() and tip:
		out.append("flame center green")
	return out


## Campaign mode's rovers and ghosts, from ALIENS1.ANI's own eight sequences.
## Drawn straight on this node rather than through the recolour shader: they
## are not players and have no colour to take.
func _draw_creatures() -> void:
	if sim.creatures.is_empty() or not pack.has_sheet("aliens1"):
		return
	for c in sim.creatures:
		if not c.alive:
			continue
		var pos := Const_.actor_anchor(Vector2(c.x, c.y) / CP)
		var seq: String = c.sequence_name()
		if not pack.has_sequence("aliens1", seq):
			draw_circle(pos, 12.0, Color(0.8, 0.3, 0.9))
			continue
		# A ghost is drawn half-there, which is the only thing on screen that
		# says it can walk through a wall.
		var tint := Color(1, 1, 1, 0.65) if c.kind == 1 else Color.WHITE
		_draw_seq_frame("aliens1", seq, pos, sim.tick_count, true, tint,
			self, true)


func draw_shadows_on(on: CanvasItem) -> void:
	if not pack.has_sheet("shadow"):
		return
	for p in sim.players:
		# NOT the dying: a corpse that still casts a shadow reads as a player
		# who is somehow still standing there. The death animation is its own
		# picture and brings whatever shadow it wants.
		if not p.alive or p.dying:
			continue
		# The shadow is black, so the shader's green test skips it and the
		# tint is irrelevant. Passed anyway rather than special-cased.
		# Drawn on the untinted node: the shadow is black, so the shader's
		# green test would skip it anyway, but saying so beats relying on it.
		_draw_seq_frame("shadow", "shadow", _player_pos(p), 0, true,
			Color.WHITE, on, true)


## One player, on the node carrying that player's colour.
func draw_player_of(on: CanvasItem, slot: int) -> void:
	for p in sim.players:
		if not p.alive or p.slot != slot:
			continue
		# INVISIBLE: "you cannot see yourself" (types.gd), not "nobody can see
		# you" — only a viewer who is actually driving this slot loses the
		# sprite; every other player's own draw call for this slot is
		# untouched. Still shown while dying, same reasoning D28's dying-input
		# guard used: the feedback that you died matters more than the
		# disease's own rule holding to the last frame.
		if not p.dying and p.slot in local_slots \
				and p.has_disease(Types_.Disease.INVISIBLE):
			continue
		var pos := _player_pos(p)
		# SICK: no original art marks a diseased player at all — checked the
		# whole pack, the only disease-related art is the powerup's own pickup
		# icon. A live playtest asked for some feedback ("I do not see the
		# debuff"), so this invents one: a slow tint pulse toward a sickly
		# green while any disease is active, applied to the normal standing/
		# walking/kicking/punching/carrying frames below. Not restored from
		# the original — there is nothing to restore.
		var tint := _disease_tint(p)
		# DYING: one of the disc's own 24 death animations, played once from
		# the tick of death rather than cycled. The seventeen XPLODE files hold
		# them — "die green 1" to "die green 24", which is what VALUELST 105's
		# 24 counts — so the sheet has to be looked up by sequence name.
		if p.dying and p.death_anim > 0:
			if _draw_death(on, p, pos):
				continue
		# IN THE AIR — off a trampoline or through a warp — the disc's own
		# `spin` sequence, which is in WALK.ANI and was never drawn.
		if p.fly_ticks > 0 and pack.has_sequence("walk", "spin"):
			_draw_seq_frame("walk", "spin", pos, sim.tick_count, true,
				Color.WHITE, on, true)
			continue

		# CORNERED: boxed in on all four sides, one of 13 `cornerhead N`
		# sequences (docs/BUGS.md) — `sim.gd`'s own trigger already refuses to
		# start this while kicking/punching/picking up, so this check sits
		# ahead of theirs without needing to repeat that exclusion here.
		if p.cornerhead > 0:
			var corner_seq := "cornerhead %d" % (p.cornerhead - 1)
			if not _cornerhead_sheets.has(corner_seq):
				_cornerhead_sheets[corner_seq] = pack.sheet_with_sequence(corner_seq)
			var corner_sheet: String = _cornerhead_sheets[corner_seq]
			if not corner_sheet.is_empty():
				_draw_seq_frame(corner_sheet, corner_seq, pos,
					Sim_.CORNERHEAD_TICKS - p.cornerhead_ticks, true,
					Color.WHITE, on, true)
				continue

		# KICKING: KICK.ANI, four directions, held for a few ticks after the
		# kick. Also never drawn before — a kick looked like walking into a
		# bomb.
		if p.kick_ticks > 0 and pack.has_sheet("kick"):
			var kick_seq := "kick %s" % _compass(p.facing)
			if pack.has_sequence("kick", kick_seq):
				_draw_seq_frame("kick", kick_seq, pos,
					Sim_.KICK_ANIM_TICKS - p.kick_ticks, true, tint,
					on, true)
				continue

		# PUNCHING: PUNCH.ANI, the same idea and the same gap. MANUAL.BM gives
		# the action button three jobs — stop, punch, trigger — and the disc
		# animates all three.
		if p.punch_ticks > 0 and pack.has_sheet("punch"):
			var punch_seq := "punch %s green" % _compass(p.facing)
			if pack.has_sequence("punch", punch_seq):
				_draw_seq_frame("punch", punch_seq, pos,
					Sim_.PUNCH_ANIM_TICKS - p.punch_ticks, true, tint,
					on, true)
				continue

		# PICKING A BOMB UP: BPICKUP.ANI, played over resource 665's own pause
		# — "the player pauses N frames doing it", which is exactly the window
		# this animation is for.
		if p.pickup_pause > 0 and pack.has_sheet("bpickup"):
			var pick_seq := "pickup %s green" % _compass(p.facing)
			if pack.has_sequence("bpickup", pick_seq):
				var pause: int = int(Values_.V[Const_.Res.PICKUP_PAUSE_FRAMES])
				_draw_seq_frame("bpickup", pick_seq, pos,
					pause - p.pickup_pause, true, tint, on, true)
				continue

		# CARRYING ONE: BOMBWALK.ANI is the player with a bomb over its head,
		# 73x146 of it, and it draws the pair as one sprite — which is why
		# draw_bombs_of() skips a carried bomb. Without this a player who had
		# grabbed a bomb looked exactly like one who had not, and the bomb was
		# drawn at their feet.
		if _is_carrying(p.slot) and pack.has_sheet("bombwalk"):
			var carry_seq := "bombwalk %s green" % _compass(p.facing)
			if pack.has_sequence("bombwalk", carry_seq):
				_draw_seq_frame("bombwalk", carry_seq, pos, sim.tick_count,
					true, tint, on, true)
				continue

		var sheet := "walk" if p.move != Types_.MoveState.STILL else "stand"
		if not pack.has_sheet(sheet):
			on.draw_circle(pos, 14.0, colour_of(p.slot))
			continue
		var seq := _player_sequence(sheet, p)
		# Walk cycles with the tick so the legs move; standing is one frame.
		_draw_seq_frame(sheet, seq, pos, sim.tick_count, true, tint,
			on, true)


## A slow pulse toward sickly green while any disease is active, plain white
## otherwise. Invented — see the "SICK" comment above draw_player_of()'s own
## use of this; there is no original art to restore for a disease state.
## Ten ticks (half a second at 20 Hz) each way, so it reads as a pulse, not a
## flicker fast enough to be mistaken for a rendering glitch.
const DISEASE_TINT := Color(0.55, 1.0, 0.45)
const DISEASE_PULSE_TICKS := 10

func _disease_tint(p: Player_) -> Color:
	if not p.any_disease():
		return Color.WHITE
	var phase := sim.tick_count % (DISEASE_PULSE_TICKS * 2)
	var f := float(phase) / float(DISEASE_PULSE_TICKS)
	if f > 1.0:
		f = 2.0 - f
	return Color.WHITE.lerp(DISEASE_TINT, f)


## Is this player holding a bomb? The bomb knows, so this asks it.
func _is_carrying(slot: int) -> bool:
	for b in sim.bombs:
		if b.carried_by == slot:
			return true
	return false


## sequence name -> sheet, built once. Seventeen sheets is too many to search
## per player per frame.
var _death_sheets: Dictionary = {}

## Same idea, for cornerhead's eight sheets.
var _cornerhead_sheets: Dictionary = {}


## Draw one frame of a player's death. Returns false when there is nothing to
## draw — no art for it, or the animation has played out — so the caller can
## fall back to the standing frame.
func _draw_death(on: CanvasItem, p, pos: Vector2) -> bool:
	var seq := "die green %d" % p.death_anim
	if not _death_sheets.has(seq):
		_death_sheets[seq] = pack.sheet_with_sequence(seq)
	var sheet: String = _death_sheets[seq]
	if sheet.is_empty():
		return false
	var age: int = sim.tick_count - p.death_tick
	var steps := pack.sequence_steps(sheet, seq)
	if steps.is_empty():
		return false
	if age >= steps.size():
		# Played out. The simulation keeps a dead player around for a while;
		# once the animation is over there is nothing left to show.
		return true
	_draw_seq_frame(sheet, seq, pos, age, true, Color.WHITE, on, true)
	return true


func _player_sequence(sheet: String, p: Player_) -> String:
	return "%s %s" % ["walk" if sheet == "walk" else "stand",
		_compass(p.facing)]


## The disc's own word for a direction: its sequences are named north, east,
## south and west rather than up, right, down and left.
static func _compass(facing: int) -> String:
	match facing:
		Types_.Dir.UP: return "north"
		Types_.Dir.DOWN: return "south"
		Types_.Dir.LEFT: return "west"
		Types_.Dir.RIGHT: return "east"
	return "south"


## Interpolated screen position of a player, in pixels.
func _player_pos(p: Player_) -> Vector2:
	var now := Vector2(p.x, p.y)
	var prev: Vector2 = now
	if _prev_pos.has(p.slot):
		prev = Vector2(_prev_pos[p.slot])
	var cp := prev.lerp(now, clampf(alpha, 0.0, 1.0))
	return Const_.actor_anchor(cp / CP)


func _draw_seq_frame(sheet: String, seq: String, at: Vector2, tick: int,
		use_hotspot: bool = false, tint: Color = Color.WHITE,
		on: CanvasItem = null, clip_to_field: bool = false) -> void:
	var index := pack.sequence_frame(sheet, seq, tick)
	if index < 0:
		return
	_draw_frame(sheet, index, at, use_hotspot, tint, on, clip_to_field)


## The literal colour, for the fallback shapes drawn when no art is loaded —
## those go through no shader, so they need a real colour.
func colour_of(slot: int) -> Color:
	if slot < 0 or slot >= Const_.PLAYER_COUNT:
		return Color.WHITE
	return Const_.player_colour_f(slot)


## `snap` rounds the destination to a whole pixel, which is right for
## everything authored as flat pixel art — a player, a bomb, a shadow — where
## a fractional position blurs a crisp 1997 edge. Flame pieces pass `false`:
## see `_centre()` and docs/BUGS.md Q10 for why they need the fraction kept.
func _draw_frame(sheet: String, index: int, at: Vector2,
		use_hotspot: bool, tint: Color = Color.WHITE,
		on: CanvasItem = null, clip_to_field: bool = false,
		snap: bool = true) -> void:
	var tex := pack.texture_of(sheet)
	if tex == null:
		return
	var src := pack.frame_rect(sheet, index)
	var top_left := at
	if use_hotspot:
		top_left = at - pack.frame_hotspot(sheet, index)
	var dest := Rect2(top_left.round() if snap else top_left, src.size)

	# Clip to the playfield. A standing bomberman is 67 px of ink over a 36 px
	# cell, so one on the top row reaches into the status area above the field
	# and, before this, off the top of the screen — which is what "the player
	# goes out of the screen" was. Both rects are trimmed together so the
	# sprite is cut rather than squashed.
	if clip_to_field:
		var field := Const_.field_rect()
		# Upward only, and only as far as the status panel. A 67 px sprite on a
		# 36 px cell has to be allowed out of the top of the playfield or a
		# player on the top row is cut in half — that was the first version,
		# which clipped at the playfield and read as the player being behind
		# the wall. The second let it through to the top of the screen, and put
		# a bomberman through the clock.
		#
		# Const_.HUD_H is where the backgrounds themselves stop: everything
		# above it is the panel the readout is drawn in, everything below it is
		# border art a sprite may cross.
		field.size.y += field.position.y - float(Const_.HUD_H)
		field.position.y = float(Const_.HUD_H)
		var kept := dest.intersection(field)
		if kept.size.x <= 0.0 or kept.size.y <= 0.0:
			return
		if kept != dest:
			src = Rect2(src.position + (kept.position - dest.position),
				kept.size)
			dest = kept

	var target: CanvasItem = on if on != null else self
	target.draw_texture_rect_region(tex, dest, src, tint)


func _draw_debug_grid() -> void:
	var grid := Color(1, 1, 1, 0.12)
	for tx in Const_.FIELD_W + 1:
		var x := Const_.FIELD_X_OFF + tx * Const_.BLOCK_W
		draw_line(Vector2(x, Const_.FIELD_Y_OFF),
			Vector2(x, Const_.FIELD_Y_OFF + Const_.FIELD_H * Const_.BLOCK_H), grid)
	for ty in Const_.FIELD_H + 1:
		var y := Const_.FIELD_Y_OFF + ty * Const_.BLOCK_H
		draw_line(Vector2(Const_.FIELD_X_OFF, y),
			Vector2(Const_.FIELD_X_OFF + Const_.FIELD_W * Const_.BLOCK_W, y), grid)
	# The cell-sized collision box each player is actually constrained by.
	for p in sim.players:
		if not p.alive:
			continue
		var pos := _player_pos(p)
		draw_rect(Rect2(pos - Vector2(Const_.BLOCK_W, Const_.BLOCK_H) / 2.0,
			Vector2(Const_.BLOCK_W, Const_.BLOCK_H)),
			Color(1, 0.3, 0.3, 0.5), false, 1.0)
		draw_circle(pos, 1.5, Color(1, 1, 0))


## The pre-game lobby: room code (if this session registered one with a
## directory), the roster so far, and a prompt telling the host they can
## start it. Plain text over a dark panel — invented wholesale, like the
## disease tint elsewhere in this file; there is no original screen for a
## lobby to draw from, because the original never had one either (server.gd's
## own doc comment on `override_slot()`).
func _draw_lobby() -> void:
	var font := ThemeDB.fallback_font
	var lines := PackedStringArray()
	lines.append("WAITING FOR PLAYERS" if not lobby_room_code.is_empty()
		else "WAITING IN LOBBY")
	if not lobby_room_code.is_empty():
		lines.append("Room code: %s" % lobby_room_code)
	lines.append("")
	if lobby_roster.is_empty():
		lines.append("  (nobody here yet)")
	for entry in lobby_roster:
		var e: Dictionary = entry
		lines.append("  slot %d — %s" % [int(e.get("slot", 0)),
			String(e.get("name", "?"))])
	lines.append("")
	lines.append("Press Enter to start" if lobby_is_host
		else "Waiting for the host to start…")

	var panel_h := 20.0 + 16.0 * lines.size()
	var panel := Rect2(Const_.SCREEN_W / 2.0 - 180, Const_.SCREEN_H / 2.0
		- panel_h / 2.0, 360, panel_h)
	draw_rect(panel, Color(0, 0, 0, 0.75))
	draw_rect(panel, Color(1, 0.95, 0.5, 0.6), false, 2.0)
	for i in lines.size():
		draw_string(font, panel.position + Vector2(20, 24 + i * 16),
			lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 0.9))


## The cursor cell and the legend of what every editor key does. Kept to one
## call so main.gd's input handling stays free of drawing.
func _draw_test_editor() -> void:
	if Field_.in_bounds(editor_cursor.x, editor_cursor.y):
		var at := Vector2(Const_.tile_origin(editor_cursor.x, editor_cursor.y))
		draw_rect(Rect2(at, Vector2(Const_.BLOCK_W, Const_.BLOCK_H)),
			Color(1, 1, 0, 0.9), false, 2.0)

	var font := ThemeDB.fallback_font
	var name: String = EDITOR_POWERUP_NAMES[editor_powerup] \
		if editor_powerup >= 0 and editor_powerup < EDITOR_POWERUP_NAMES.size() \
		else "?"
	var lines := [
		"TEST EDITOR — T to leave",
		"LMB cycle brick   RMB place powerup   [ ] choose: %s" % name,
		"B bomb   K kill   D disease   C cure   R clear field",
	]
	draw_rect(Rect2(0, 0, Const_.SCREEN_W, 11 * lines.size() + 6),
		Color(0, 0, 0, 0.6))
	for i in lines.size():
		draw_string(font, Vector2(4, 10 + i * 11), lines[i],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(1, 1, 0.6))


## One node per player colour per layer group. Each carries its own material
## with its own target colour, and draws only the sprites belonging to its
## slot — which is what lets ten differently-coloured players share one shader.
## The status band: score, clock and the HURRY banner, drawn above the actors.
class HudNode extends Node2D:
	var view: Node2D = null

	func _draw() -> void:
		if view == null or view.sim == null or view.pack == null:
			return
		if not view.pack.loaded:
			return
		view.draw_hud(self)


class TintNode extends Node2D:
	var view: Node2D = null
	var slot: int = -1
	var group: String = "over"

	func _draw() -> void:
		if view == null or view.sim == null or view.pack == null:
			return
		if not view.pack.loaded:
			return
		if group == "under":
			view.draw_bombs_of(self, slot)
			view.draw_flames_of(self, slot)
		else:
			if slot < 0:
				view.draw_shadows_on(self)
			else:
				view.draw_player_of(self, slot)
