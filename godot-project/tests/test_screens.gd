# The screen flow: which screen follows which, and what a key does on each.
#
# Headless, because the flow is a model — scripts/app/screens.gd holds no
# textures and draws nothing. What is NOT tested here is how a screen LOOKS;
# that is tests/render_screens.gd, and the two are separate for the reason
# docs/BUGS.md D21 records: a menu whose every value is right can still be
# unusable on screen, and a screen that looks right can navigate wrongly.
extends SceneTree

const T_ := preload("res://tests/t.gd")
const Const_ := preload("res://scripts/core/const.gd")
const Messages_ := preload("res://scripts/core/messages.gd")
const Screens_ := preload("res://scripts/app/screens.gd")


func _init() -> void:
	var t := T_.new("screens")
	_test_starts_on_the_title(t)
	_test_menu_items_are_the_discs(t)
	_test_menu_geometry_matches_the_art(t)
	_test_cursor_wraps(t)
	_test_every_item_goes_somewhere(t)
	_test_join_refuses_without_a_url(t)
	_test_back_out_of_every_screen(t)
	_test_match_end(t)
	_test_the_wipe(t)
	_test_no_screen_is_a_dead_end(t)
	_test_text_pages_scroll_and_stop(t)
	quit(t.finish())


func _test_starts_on_the_title(t: T_) -> void:
	var s := Screens_.new()
	t.eq(s.screen, Screens_.Screen.TITLE, "it starts on the title")
	t.eq(s.action, Screens_.Action.NONE, "with nothing asked for")

	# "Press any key" means any key, so activate() moves on from the title
	# whatever it was.
	s.activate()
	t.eq(s.screen, Screens_.Screen.MAIN_MENU, "any key reaches the main menu")


# The seven items are painted into MAINMENU.PCX, so the port cannot choose
# them — only name them. These are the disc's own words.
func _test_menu_items_are_the_discs(t: T_) -> void:
	t.eq(Screens_.MENU_LABELS.size(), 7, "seven items")
	t.eq(Screens_.MENU_LABELS[0], "Start Game", "the first is Start Game")
	t.eq(Screens_.MENU_LABELS[1], "Start Network Game", "then network host")
	t.eq(Screens_.MENU_LABELS[2], "Join Network Game", "then network join")
	t.eq(Screens_.MENU_LABELS[3], "Options", "then Options")
	t.eq(Screens_.MENU_LABELS[6], "Exit Bomberman", "and Exit last")
	t.eq(Screens_.MENU_LABELS.size(), Screens_.Menu.size(),
		"and the enum matches the labels")


# Measured from the art: seven bands of yellow text, 37 px apart, starting at
# y=115, all at x=358. A cursor placed anywhere else points at nothing.
func _test_menu_geometry_matches_the_art(t: T_) -> void:
	t.eq(Screens_.MENU_ITEM_Y.size(), 7, "a position per item")
	t.eq(Screens_.MENU_ITEM_Y[0], 115, "the first band starts at y=115")
	t.eq(Screens_.MENU_ITEM_X, 358, "and the text at x=358")
	for i in Screens_.MENU_ITEM_Y.size() - 1:
		var pitch: int = Screens_.MENU_ITEM_Y[i + 1] - Screens_.MENU_ITEM_Y[i]
		t.ok(pitch >= 36 and pitch <= 37,
			"item %d to %d is %d px apart" % [i, i + 1, pitch])
	# Every band must be on the screen, and inside the art.
	for i in Screens_.MENU_ITEM_Y.size():
		var rect := Screens_.menu_item_rect(i)
		t.ok(rect.position.y >= 0 and rect.end.y <= Const_.SCREEN_H,
			"item %d is on screen" % i)
		t.ok(rect.position.x >= 0 and rect.position.x < Const_.SCREEN_W,
			"and its text starts on screen")


func _test_cursor_wraps(t: T_) -> void:
	var s := _at(Screens_.Screen.MAIN_MENU)
	t.eq(s.cursor, Screens_.Menu.START_GAME, "the cursor starts at the top")
	s.move(-1)
	t.eq(s.cursor, s.menu_item_count() - 1, "up from the top wraps to the end")
	s.move(1)
	t.eq(s.cursor, 0, "and down from the end wraps back")
	var seen := {}
	for _i in 40:
		seen[s.cursor] = true
		s.move(1)
	t.eq(seen.size(), s.menu_item_count(), "every item is reachable")

	# The cursor only moves on the main menu; elsewhere the model that owns
	# that screen does the moving.
	var elsewhere := _at(Screens_.Screen.OPTIONS)
	elsewhere.cursor = 3
	elsewhere.move(1)
	t.eq(elsewhere.cursor, 3, "the cursor does not move on other screens")


func _test_every_item_goes_somewhere(t: T_) -> void:
	# Start Game -> the setup screen.
	var s := _at(Screens_.Screen.MAIN_MENU)
	s.cursor = Screens_.Menu.START_GAME
	t.eq(s.activate(), Screens_.Action.OPEN_SETUP, "Start Game opens setup")
	t.eq(s.screen, Screens_.Screen.SETUP, "and goes there")

	# Start Network Game -> setup too, but hosting.
	s = _at(Screens_.Screen.MAIN_MENU)
	s.cursor = Screens_.Menu.START_NETWORK
	t.eq(s.activate(), Screens_.Action.HOST, "Start Network Game hosts")
	t.eq(s.screen, Screens_.Screen.SETUP,
		"through the same setup screen, because the choice is the same")

	# Options, About, Manual.
	for pair in [[Screens_.Menu.OPTIONS, Screens_.Screen.OPTIONS],
			[Screens_.Menu.ABOUT, Screens_.Screen.ABOUT],
			[Screens_.Menu.MANUAL, Screens_.Screen.MANUAL]]:
		s = _at(Screens_.Screen.MAIN_MENU)
		s.cursor = pair[0]
		s.activate()
		t.eq(s.screen, pair[1],
			"%s opens its screen" % Screens_.MENU_LABELS[pair[0]])

	# Exit.
	s = _at(Screens_.Screen.MAIN_MENU)
	s.cursor = Screens_.Menu.EXIT
	t.eq(s.activate(), Screens_.Action.QUIT, "Exit Bomberman quits")


# Typing a URL with arrow keys is worse than not offering it, so a join comes
# from --join or from the browser's ?join= query string. Without one the screen
# says so rather than appearing to do nothing.
func _test_join_refuses_without_a_url(t: T_) -> void:
	var s := _at(Screens_.Screen.MAIN_MENU)
	s.cursor = Screens_.Menu.JOIN_NETWORK
	t.eq(s.activate(), Screens_.Action.NONE, "with no URL, joining does nothing")
	t.ok(not s.refusal.is_empty(), "and says why: %s" % s.refusal)
	t.ok(s.refusal.contains("--join"), "naming the flag")
	t.ok(s.refusal.contains("?join="), "and the query string")
	t.eq(s.screen, Screens_.Screen.MAIN_MENU, "and stays put")

	s.join_url = "ws://127.0.0.1:47600"
	t.eq(s.activate(), Screens_.Action.JOIN, "with a URL it joins")
	t.eq(s.refusal, "", "and complains about nothing")


func _test_back_out_of_every_screen(t: T_) -> void:
	# Every screen that is not the title or the menu backs out to the menu.
	for screen in [Screens_.Screen.SETUP, Screens_.Screen.OPTIONS,
			Screens_.Screen.ABOUT, Screens_.Screen.MANUAL,
			Screens_.Screen.RESULTS, Screens_.Screen.VICTORY,
			Screens_.Screen.DRAW, Screens_.Screen.GAME]:
		var s := _at(screen)
		t.eq(s.back(), Screens_.Action.BACK_TO_MENU,
			"screen %d backs out to the menu" % screen)
		t.eq(s.screen, Screens_.Screen.MAIN_MENU, "and arrives there")

	# The title and the menu are the two places where backing out leaves.
	for screen in [Screens_.Screen.TITLE, Screens_.Screen.MAIN_MENU]:
		var s2 := _at(screen)
		t.eq(s2.back(), Screens_.Action.QUIT,
			"screen %d quits when backed out of" % screen)


func _test_match_end(t: T_) -> void:
	# A winner shows their own victory screen.
	var s := _at(Screens_.Screen.GAME)
	s.finish_match(3, 1, false)
	t.eq(s.screen, Screens_.Screen.VICTORY, "a won match shows victory")
	t.eq(s.victory_screen_name(false), "victory3",
		"player 3's own screen, of the ten on the disc")
	t.ok(not s.was_draw, "and it is not a draw")

	# In team play, the team's screen.
	s = _at(Screens_.Screen.GAME)
	s.finish_match(4, 1, true)
	t.eq(s.victory_screen_name(true), "team1", "a team win shows TEAM1.PCX")

	# Nobody won.
	s = _at(Screens_.Screen.GAME)
	s.finish_match(-1, -1, false)
	t.eq(s.screen, Screens_.Screen.DRAW, "a drawn match shows the draw screen")
	t.ok(s.was_draw, "and knows it")
	t.eq(s.victory_screen_name(false), "draw", "which is DRAW.PCX")

	# Victory, then the roulette if the Gold Bomberman option is on, then the
	# results, then the menu. OPTIONS.BM: the reward goes to "the winner of
	# the last match", so it follows the victory and precedes the next game.
	s = _at(Screens_.Screen.GAME)
	s.gold_bomberman = true
	s.finish_match(0, 0, false)
	s.activate()
	t.eq(s.screen, Screens_.Screen.ROULETTE,
		"a winner spins the wheel for next match's reward")
	s.activate()
	t.eq(s.screen, Screens_.Screen.RESULTS, "then the results")
	s.activate()
	t.eq(s.screen, Screens_.Screen.MAIN_MENU, "then the menu")

	# With the option off, straight to the results.
	s = _at(Screens_.Screen.GAME)
	s.gold_bomberman = false
	s.finish_match(0, 0, false)
	s.activate()
	t.eq(s.screen, Screens_.Screen.RESULTS,
		"with Gold Bomberman off, victory leads straight to the results")

	# And a DRAW never spins, because there is nobody to reward.
	s = _at(Screens_.Screen.GAME)
	s.gold_bomberman = true
	s.finish_match(-1, -1, false)
	s.activate()
	t.eq(s.screen, Screens_.Screen.RESULTS,
		"a drawn match skips the wheel — there is no winner to reward")

	# Every slot has a screen.
	for slot in Const_.PLAYER_COUNT:
		var v := _at(Screens_.Screen.GAME)
		v.finish_match(slot, 0, false)
		t.eq(v.victory_screen_name(false), "victory%d" % slot,
			"player %d has a victory screen" % slot)


func _test_the_wipe(t: T_) -> void:
	var s := _at(Screens_.Screen.MAIN_MENU)
	t.ok(not s.wiping(), "nothing is wiping to begin with")
	s.to_screen(Screens_.Screen.OPTIONS)
	t.ok(s.wiping(), "changing screen starts the wipe")
	t.eq(s.wipe_from, Screens_.Screen.MAIN_MENU, "which remembers where from")
	t.close(s.wipe_progress(), 0.0, 0.05, "and starts at nothing")

	for _i in Screens_.WIPE_LENGTH - 1:
		s.tick()
	t.ok(s.wiping(), "it lasts %d ticks" % Screens_.WIPE_LENGTH)
	t.ok(s.wipe_progress() > 0.9, "and is nearly done")
	s.tick()
	t.ok(not s.wiping(), "then ends")
	t.eq(s.wipe_from, -1, "forgetting where it came from")
	t.close(s.wipe_progress(), 1.0, 0.001, "and reads as complete")

	# Going to the screen already up does nothing, so a held key cannot
	# restart the wipe forever.
	s.to_screen(Screens_.Screen.OPTIONS)
	t.ok(not s.wiping(), "re-entering the same screen does not wipe")


# There must be no screen a player can reach and not leave. Walked
# exhaustively, because the flow is small enough to walk and a dead end is the
# one navigation bug that cannot be worked around.
func _test_no_screen_is_a_dead_end(t: T_) -> void:
	for screen in Screens_.Screen.values():
		var s := _at(screen)
		var out := s.back()
		var moved: bool = s.screen != screen or out == Screens_.Action.QUIT
		t.ok(moved, "screen %d can be left with Escape" % screen)

	# And every screen either goes somewhere on Return or is one of the two
	# that own their own input.
	var owns_input := [Screens_.Screen.SETUP, Screens_.Screen.OPTIONS,
		Screens_.Screen.GAME]
	for screen in Screens_.Screen.values():
		if owns_input.has(screen):
			continue
		var s2 := _at(screen)
		var before := s2.screen
		var act := s2.activate()
		t.ok(s2.screen != before or act != Screens_.Action.NONE,
			"screen %d does something on Return" % screen)


func _at(screen: int) -> Screens_:
	var s: Screens_ = Screens_.new()
	s.screen = screen
	return s


# A text page scrolls, and STOPS. The clamp used to live only in the drawing —
# the view drew clampi(text_scroll, 0, last) while this counter went on rising
# — so pressing down ten times past the end of the Online Manual meant pressing
# up ten times before the page moved. "I need to tap up twice to make it work"
# was that, counted from however far past the end you had gone.
func _test_text_pages_scroll_and_stop(t: T_) -> void:
	var s := Screens_.new()
	const LINES := 100
	const ROWS := 21
	const LAST := LINES - ROWS

	t.eq(s.text_scroll, 0, "a page opens at the top")
	s.scroll_text(-1, LINES, ROWS)
	t.eq(s.text_scroll, 0, "and does not scroll above it")

	s.scroll_text(1, LINES, ROWS)
	t.eq(s.text_scroll, 1, "down moves one line")
	s.scroll_text(ROWS, LINES, ROWS)
	t.eq(s.text_scroll, 1 + ROWS, "page down moves a page")

	# THE ONE THAT BIT. Twenty presses PAST the end, then one press back.
	for _i in LINES + 20:
		s.scroll_text(1, LINES, ROWS)
	t.eq(s.text_scroll, LAST, "down stops at the last page")
	s.scroll_text(-1, LINES, ROWS)
	t.eq(s.text_scroll, LAST - 1,
		"and ONE press of up moves, however many presses of down went past it")

	# A page shorter than the screen does not scroll at all.
	s.text_scroll = 0
	s.scroll_text(1, 5, ROWS)
	t.eq(s.text_scroll, 0, "a page that fits does not move")

	# Opening any screen puts a page back at its top.
	s.text_scroll = 9
	s.to_screen(Screens_.Screen.MANUAL)
	t.eq(s.text_scroll, 0, "and a screen opens at its top")
