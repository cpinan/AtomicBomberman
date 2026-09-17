# The screen flow: which screen is up, what the cursor is on, and what a
# keypress does next.
#
# A MODEL, like scripts/app/menu.gd — no drawing, no nodes, no input events, so
# tests/test_screens.gd walks the whole flow headless. scripts/render/
# screen_view.gd draws whatever this holds and decides nothing.
#
# ---------------------------------------------------------------------------
# THE SCREENS ARE THE ORIGINAL'S, AND SO ARE THEIR CONTENTS
# ---------------------------------------------------------------------------
# Every screen the original has ships as a 640x480 PCX in `RES/`, and the code
# draws its cursor, its values and its animations over the top:
#
#   TITLE.PCX       the title
#   MAINMENU.PCX    the main menu, with its SEVEN ITEMS PAINTED INTO THE ART
#   GLUE0..GLUE6    tiling wallpapers, the backdrops for the setup screens —
#                   not screens themselves. GLUE0 is a grid of bomberman heads
#   RESULTS.PCX     the statistics screen
#   VICTORY0..9     one per player colour
#   DRAW.PCX        nobody won
#   TEAM0, TEAM1    a team won
#   ROULETTE.PCX    the Goldman wheel
#   BONUS.PCX       the bonus screen
#
# Because the main menu's items are painted in, this file cannot choose them —
# it can only put a cursor on them. Their positions were MEASURED from the art
# by finding the rows of yellow text: seven bands, 22-23 px tall, starting at
# y=115 with a 37 px pitch, all beginning at x=358. MENU_ITEM_Y below.
#
# The words are still needed, for the tests and for saying what was chosen, and
# they are the disc's own: "Start Game", "Start Network Game", "Join Network
# Game", "Options", "About Bomberman", "Online Manual", "Exit Bomberman".
extends RefCounted

const Const_ := preload("res://scripts/core/const.gd")
const Values_ := preload("res://scripts/core/values.gd")
const Messages_ := preload("res://scripts/core/messages.gd")

enum Screen {
	TITLE,        ## TITLE.PCX, any key moves on
	MAIN_MENU,    ## MAINMENU.PCX
	SETUP,        ## who is playing: GLUE0 plus ten slots
	OPTIONS,      ## the settings screen, MESSAGES.TXT 250-268
	ABOUT,        ## About Bomberman — CREDITS.BM
	MANUAL,       ## Online Manual — MANUAL.BM
	GAME,         ## not a screen; the playfield is up
	RESULTS,      ## RESULTS.PCX, after a match
	VICTORY,      ## VICTORY<n>.PCX or TEAM<n>.PCX
	DRAW,         ## DRAW.PCX
	ROULETTE,     ## ROULETTE.PCX — the Goldman wheel, after a match is won
}

## The seven items painted into MAINMENU.PCX, in the order they appear.
enum Menu {
	START_GAME, START_NETWORK, JOIN_NETWORK, OPTIONS, ABOUT, MANUAL, EXIT,
}

const MENU_LABELS := [
	"Start Game", "Start Network Game", "Join Network Game", "Options",
	"About Bomberman", "Online Manual", "Exit Bomberman",
]

## Measured from MAINMENU.PCX: the top of each item's text band.
const MENU_ITEM_Y := [115, 152, 189, 226, 262, 299, 336]
## Where the text starts, and how tall a band is. The cursor goes left of it.
const MENU_ITEM_X := 358
const MENU_ITEM_H := 22

## What the flow is asking the app to do. Read by main.gd and then cleared.
enum Action {
	NONE, PLAY_LOCAL, HOST, JOIN, QUIT, OPEN_OPTIONS, OPEN_SETUP,
	BACK_TO_MENU,
}

var screen: int = Screen.TITLE
var cursor: int = Menu.START_GAME
var action: int = Action.NONE

## Why something could not be done, shown on screen rather than swallowed.
var refusal: String = ""

## Ticks the current screen has been up, for animation.
var age: int = 0

## The transition. HEADWIPE.ANI is 211 frames of a 73x73 bomberman; it plays
## across the screen while one screen becomes another.
var wipe_from: int = -1
var wipe_ticks: int = 0
const WIPE_LENGTH := 30

## Set when a match ends, so RESULTS and VICTORY know what to say.
var champion_slot: int = -1
var champion_team: int = -1
var was_draw: bool = false

## "Gold Bomberman" — MESSAGES.TXT 256, and OPTIONS.BM's own description:
## "a reward given to the winner of the last match. The reward consists of a
## random powerup determined by the roulette wheel. (Not available in network
## games)". No VALUELST resource states a default, so the port defaults it ON
## and the options screen can turn it off — the feature exists on the disc
## complete with its screen, its animation values, its three sounds and its
## announcement, which reads like something that happened by default.
var gold_bomberman: bool = true

## Whether joining is possible: a URL from --join or from the browser's query
## string. Without one there is nothing for "Join Network Game" to do, and the
## screen says so instead of pretending.
var join_url: String = ""

## Games heard on the LAN, as scripts/net/discovery.gd found them. The screen
## lists them with MESSAGES.TXT 60 and 62, and says 61 when there are none.
## Set by main.gd each frame; this model does no networking of its own.
var net_games: Array = []
var net_cursor: int = 0

## First visible line of a text page — About Bomberman and the Online Manual
## are the disc's own CREDITS.BM and MANUAL.BM, both far longer than a screen.
## Reset when a screen is opened.
var text_scroll: int = 0


## Scroll a text page, CLAMPED to what there is to read.
##
## The clamp is here rather than in the view because the view was the only
## thing doing it: it drew clampi(text_scroll, 0, last_page) while this counter
## went on rising, so ten presses of "down" past the end of the Online Manual
## needed ten presses of "up" before the page moved again. That is "when
## scrolling down I need to tap up twice to make it work" — it was however many
## presses past the end you had made.
func scroll_text(delta: int, total_lines: int, rows: int) -> void:
	text_scroll = clampi(text_scroll + delta, 0, maxi(total_lines - rows, 0))


## The URL "Join Network Game" would use: whichever game is selected in the
## list, or the one --join or ?join= named when the list is empty.
func selected_join_url() -> String:
	if net_cursor >= 0 and net_cursor < net_games.size():
		return net_games[net_cursor].url()
	return join_url


func to_screen(next: int) -> void:
	if next == screen:
		return
	wipe_from = screen
	wipe_ticks = WIPE_LENGTH
	screen = next
	age = 0
	refusal = ""
	# A page opens at its top, never where the last one was left.
	text_scroll = 0


func tick() -> void:
	age += 1
	if wipe_ticks > 0:
		wipe_ticks -= 1
		if wipe_ticks == 0:
			wipe_from = -1


func wiping() -> bool:
	return wipe_ticks > 0


## 0.0 at the start of a transition, 1.0 at its end.
func wipe_progress() -> float:
	if not wiping():
		return 1.0
	return 1.0 - float(wipe_ticks) / float(WIPE_LENGTH)


func menu_item_count() -> int:
	return MENU_LABELS.size()


## The band one main-menu item occupies, in screen pixels.
static func menu_item_rect(item: int) -> Rect2:
	var y: int = MENU_ITEM_Y[clampi(item, 0, MENU_ITEM_Y.size() - 1)]
	return Rect2(MENU_ITEM_X, y, 260, MENU_ITEM_H)


func move(delta: int) -> void:
	refusal = ""
	if screen != Screen.MAIN_MENU:
		return
	cursor = posmod(cursor + delta, menu_item_count())


## A key that is not a direction. Returns the action taken.
func activate() -> int:
	refusal = ""
	action = Action.NONE
	match screen:
		Screen.TITLE:
			to_screen(Screen.MAIN_MENU)
		Screen.MAIN_MENU:
			_choose()
		Screen.ABOUT, Screen.MANUAL, Screen.RESULTS:
			to_screen(Screen.MAIN_MENU)
		Screen.VICTORY:
			# The winner spins for next match's reward, if the Gold Bomberman
			# option is on — OPTIONS.BM: "a reward given to the winner of the
			# last match". Then the statistics.
			to_screen(Screen.ROULETTE if gold_bomberman
				else Screen.RESULTS)
		Screen.DRAW:
			# Nobody won, so there is nobody to reward.
			to_screen(Screen.RESULTS)
		Screen.ROULETTE:
			to_screen(Screen.RESULTS)
	return action


func _choose() -> void:
	match cursor:
		Menu.START_GAME:
			action = Action.OPEN_SETUP
			to_screen(Screen.SETUP)
		Menu.START_NETWORK:
			action = Action.HOST
			to_screen(Screen.SETUP)
		Menu.JOIN_NETWORK:
			if not net_games.is_empty():
				# A game was heard on the LAN, so there is something to join
				# without anyone typing a URL.
				join_url = selected_join_url()
				action = Action.JOIN
			elif join_url.is_empty():
				# Said plainly. Typing a URL with arrow keys is worse than not
				# offering it, so a join comes from --join on the desktop or
				# from the browser's ?join= query string, which is how
				# server/README.md tells people to share a game.
				refusal = ("no server to join: start with --join ws://host:port"
					+ ", or open the page with ?join=ws://host:port")
			else:
				action = Action.JOIN
		Menu.OPTIONS:
			action = Action.OPEN_OPTIONS
			to_screen(Screen.OPTIONS)
		Menu.ABOUT:
			to_screen(Screen.ABOUT)
		Menu.MANUAL:
			to_screen(Screen.MANUAL)
		Menu.EXIT:
			action = Action.QUIT


## Escape, or whatever backs out of the current screen.
func back() -> int:
	refusal = ""
	action = Action.NONE
	match screen:
		Screen.TITLE:
			action = Action.QUIT
		Screen.MAIN_MENU:
			action = Action.QUIT
		Screen.SETUP, Screen.OPTIONS, Screen.ABOUT, Screen.MANUAL, \
		Screen.RESULTS, Screen.VICTORY, Screen.DRAW, Screen.ROULETTE:
			action = Action.BACK_TO_MENU
			to_screen(Screen.MAIN_MENU)
		Screen.GAME:
			action = Action.BACK_TO_MENU
			to_screen(Screen.MAIN_MENU)
	return action


## A match has ended. Which screen follows depends on how.
func finish_match(slot: int, team: int, teams: bool) -> void:
	champion_slot = slot
	champion_team = team
	was_draw = slot < 0 and team < 0
	if was_draw:
		to_screen(Screen.DRAW)
	else:
		to_screen(Screen.VICTORY)


## Which screen art the victory shows: a team screen in team play, otherwise
## the winner's own.
func victory_screen_name(teams: bool) -> String:
	if was_draw:
		return "draw"
	if teams and champion_team >= 0:
		return "team%d" % clampi(champion_team, 0, 1)
	return "victory%d" % clampi(champion_slot, 0, Const_.PLAYER_COUNT - 1)


## The line the victory screen shows, in the original's own words:
## MESSAGES.TXT 120 is "(Match winner must score %u victories)" and 208 is
## "Wins", so the announcement is built from them rather than invented.
func victory_line(wins_to_win: int) -> String:
	if was_draw:
		return Messages_.get_text(1130) if Messages_.M.has(1130) else "DRAW"
	if champion_team >= 0:
		return "%s %d" % [Messages_.SLOT_TEAM, champion_team]
	return Messages_.fmt(Messages_.TO_WIN_MATCH,
		[wins_to_win, Messages_.WINS])
