# Draws the menu. Decides nothing — scripts/app/menu.gd holds every value and
# every rule, and this reads them.
#
# TEXT, NOT ART, AND ON PURPOSE. The original's menu is `RES/MAINMENU.PCX` plus
# the glue screens `GLUE0`–`GLUE6`, none of which Track B has extracted
# (docs/PLAN.md §6). A plain list that says what it does beats a blank window
# with the real background behind it, and the layout is deliberately dull so
# replacing it with the real art is a rewrite of this file and nothing else.
#
# The one thing it does that matters: it shows `menu.refusal`. A start that is
# refused has to say why on screen, or the player presses Return and nothing
# happens.
extends Node2D

const Const_ := preload("res://scripts/core/const.gd")
const Menu_ := preload("res://scripts/app/menu.gd")
const Messages_ := preload("res://scripts/core/messages.gd")
const Keysets_ := preload("res://scripts/app/keysets.gd")

var menu: Menu_ = null

## Drawn under the menu when the pack loaded, so it does not look like a
## different program from the game.
var pack: RefCounted = null

# Tuned against tests/render_menu.gd, which computes where the first row starts
# and where the last one ends, and requires both to clear the header and the
# footer. Both bounds have been broken here in turn: at ROW_H 20 / TOP 88 the
# last row ended at y=464 with the footer at 456, so QUIT was drawn through;
# tightening to TOP 78 then ran the first row into the subtitle. Neither was
# visible to a model test and both were obvious in a screenshot.
#
# Broken a third time by ADDING two rows — Win Matches By Kill Total and Random
# Start — which put the last row at y=472 with 16 items. The rows and the slot
# grid both lost a pixel rather than the header moving, because TOP can only go
# down to 78 before the first row touches the subtitle and there is no room
# there. At 17 the last row ended at 451, a fourth row — Define keyboard
# layouts — took it back over at 468, and 16 fitted 17 items at 446.
#
# Then Disable Music made 18 and 16 no longer fitted either. Rather than shave
# a pixel a fifth time, the ROW FONT came down from 15 to 13: the label column
# is the same words in a smaller type, which buys 3 pixels a row and stops
# this being a recurring emergency. At 15/13 with 18 items the last row ends
# at 439, with room for two more options before this argument happens again.
const ROW_H := 15
const ROW_FONT := 13
const TOP := 88
const LABEL_X := 74
const VALUE_X := 296

## Where the header ends, which is what TOP has to clear.
const HEADER_BOTTOM := 74

## The player slots, as a grid: five rows, two columns.
const SLOT_ROWS := 5
const SLOT_W := 200
const SLOT_H := 15


func _draw() -> void:
	draw_rect(Rect2(0, 0, Const_.SCREEN_W, Const_.SCREEN_H),
		Color(0.04, 0.05, 0.09))
	if pack != null and pack.loaded:
		var bg = pack.background(menu.level if menu != null else 0)
		if bg != null:
			# Dimmed hard: it is a backdrop, and the text has to win.
			draw_texture(bg, Vector2.ZERO, Color(1, 1, 1, 0.22))
	if menu == null:
		return

	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(LABEL_X, 48),
		Messages_.KEY_DEFINITIONS.to_upper() if menu.in_keys
			else ("PLAYERS" if menu.in_slots else "ATOMIC BOMBERMAN"),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color(1, 0.85, 0.3))
	draw_string(font, Vector2(LABEL_X, HEADER_BOTTOM - 4),
		("Return to rebind, Escape to go back" if menu.in_keys
			else ("Return cycles a slot, Escape to go back" if menu.in_slots
				else "a Godot port — up/down to move, "
					+ "left/right to change, Return to choose")),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.7, 0.75, 0.8))

	if menu.in_keys:
		_draw_keys(font)
		return
	if menu.in_slots:
		_draw_slots(font)
		return

	# One row per item, with the ten player slots drawn as a 5x2 grid where the
	# Players row sits. A single column of ten does not fit under the options
	# on a 640x480 screen — the first version ran START, HOST and QUIT off the
	# bottom edge, which is the one part of a menu that has to be reachable.
	var y := float(TOP)
	for item in menu.item_count():
		var chosen: bool = item == menu.selected()
		_row(font, y, menu.label_of(item),
			"" if menu.is_action(item) else menu.value_text(item), chosen,
			menu.is_action(item))
		y += ROW_H

	if not menu.refusal.is_empty():
		draw_string(font, Vector2(LABEL_X, y + 16), menu.refusal,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 0.45, 0.4))


## One keyset, spelled out: "KEY 1: Up/Down/Left/Right + Enter".
func _keyset_note(ks: int) -> String:
	var map: Dictionary = Keysets_.MAPS[ks]
	var dirs := PackedStringArray()
	for action in ["up", "down", "left", "right"]:
		dirs.append(Keysets_.key_label(int(map[action])))
	return "%s: %s + %s" % [
		Messages_.fmt(Messages_.SLOT_KEY, [ks + 1]),
		"/".join(dirs),
		Keysets_.key_label(int(map["first"])),
	]


## The ten player slots, as a screen of their own.
##
## They used to sit inline under the Players row, five by two, and every option
## added to the list pushed them 15 pixels nearer the bottom edge — three
## separate layout emergencies, all caught by tests/render_menu.gd (docs/BUGS.md
## D21). Giving them their own screen ends that argument: the list is rows and
## nothing else, and the slots have a whole screen for ten of them.
func _draw_slots(font: Font) -> void:
	var y := float(TOP)
	for i in menu.slots.size():
		var col: int = i / SLOT_ROWS
		var row: int = i % SLOT_ROWS
		_slot(font, y + row * SLOT_H * 2, col, i, i == menu.slot_cursor)
	y += SLOT_ROWS * SLOT_H * 2 + 12
	draw_string(font, Vector2(LABEL_X, y),
		"%d playing, %d of them AI" % [menu.seats(), menu.ai_count()],
		HORIZONTAL_ALIGNMENT_LEFT, -1, ROW_FONT, Color(1, 0.95, 0.6))


## The keyboard-definitions screen — MESSAGES.TXT 1100-1140. Thirteen rows:
## six actions for each of the two keysets, then "Return to default keys".
## Drawn instead of the options list, not under it, because it is a screen of
## the original's own and there is no room for both.
func _draw_keys(font: Font) -> void:
	var y := float(TOP)
	for row in Menu_.KEY_ROWS:
		if row == Menu_.KEY_RESTORE_ROW:
			y += 6
		_row(font, y, menu.key_row_label(row), menu.key_row_value(row),
			row == menu.key_cursor, row == Menu_.KEY_RESTORE_ROW)
		y += ROW_H
	if not menu.key_notice.is_empty():
		draw_string(font, Vector2(LABEL_X, y + 18), menu.key_notice,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 0.8, 0.4))


## One player slot, in that player's own colour so the list reads as the ten
## bombermen and not as ten numbers.
func _slot(font: Font, y: float, col: int, index: int, chosen: bool) -> void:
	var x := LABEL_X + 16 + col * SLOT_W
	var tint := Const_.player_colour_f(index)
	# Lifted well toward white: four of the ten colours are dark enough that
	# their own hue is unreadable as text on a dark background.
	var colour := Color(tint.r, tint.g, tint.b).lerp(Color(1, 1, 1), 0.45)
	if chosen:
		draw_rect(Rect2(x - 8, y - 12, SLOT_W - 12, SLOT_H - 3),
			Color(1, 0.95, 0.5, 0.16))
		colour = colour.lerp(Color(1, 1, 1), 0.35)
		draw_string(font, Vector2(x - 20, y), ">",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 0.95, 0.5))
	draw_string(font, Vector2(x, y), "player %d" % (index + 1),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14, colour)
	draw_string(font, Vector2(x + 78, y), menu.slot_text(index),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14, colour)


func _row(font: Font, y: float, label: String, value: String, chosen: bool,
		is_action: bool) -> void:
	var colour := Color(1, 1, 1, 0.8)
	if chosen:
		colour = Color(1, 0.95, 0.5)
		draw_rect(Rect2(LABEL_X - 18, y - 13, 430, ROW_H - 6),
			Color(1, 0.95, 0.5, 0.13))
		draw_string(font, Vector2(LABEL_X - 16, y), ">",
			HORIZONTAL_ALIGNMENT_LEFT, -1, ROW_FONT, colour)
	if is_action:
		colour = Color(1, 0.85, 0.35) if not chosen else Color(1, 1, 0.7)
	draw_string(font, Vector2(LABEL_X, y), label,
		HORIZONTAL_ALIGNMENT_LEFT, -1, ROW_FONT, colour)
	if not value.is_empty():
		draw_string(font, Vector2(VALUE_X, y), value,
			HORIZONTAL_ALIGNMENT_LEFT, -1, ROW_FONT, colour)

	# Built from the keys actually in force, not from the defaults: the
	# keyboard-definitions screen can change them, and a footer that still
	# said "arrows + Return" afterwards would be the only lie on the screen.
	var note := "%s      %s" % [_keyset_note(0), _keyset_note(1)]
	draw_string(font, Vector2(LABEL_X, Const_.SCREEN_H - 24), note,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.65, 0.7, 0.75))
	if pack == null or not pack.loaded:
		draw_string(font, Vector2(LABEL_X, Const_.SCREEN_H - 8),
			"no asset pack: flat colours, built-in grid only",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 0.6, 0.4))

