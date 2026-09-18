# Owns the simulation, drives it at a fixed 20 Hz, and lets the view draw
# between ticks.
#
# The loop is the only place in the project that knows about wall-clock time.
# `_process` accumulates real milliseconds and runs whole ticks; the view is
# handed the leftover fraction so it can interpolate. The simulation itself
# still takes no delta and reads no clock.
#
# Command line:
#   --scheme PATH     a .SCH to play; defaults to the first one found
#   --level N         which level's art to use, 0..10
#   --players N       how many slots to fill, 1 or 2 on one keyboard
#   --seed N          round seed, for a reproducible layout
#   --debug-grid      draw the cell grid and collision boxes
#   --shot PATH       render one frame to PATH and quit; for the render test
#   --shot-tick N     which tick to capture at (default 1)
#   --auto-bomb N     every player drops a bomb on tick N, with no input. Lets
#                     a bomb or an explosion be captured without a human at the
#                     keyboard, which is the only way to eyeball those states.
#   --campaign NAME   play one of the disc's own campaigns: SIMPLE (4 stages),
#                     GHOSTS (4) or CROUTON (9). Each stage names its level,
#                     its scheme and how many rovers and ghosts at what speed;
#                     clearing it means killing everything. VALUELST 1300/1310/
#                     1320 score a kill. One life: a campaign ends when you do.
#   --campaign-stage N  start a campaign on stage N (1-based) rather than its
#                     first. For looking at one stage without playing the
#                     three before it.
#   --gold N          MESSAGES.TXT 256's "Gold Bomberman": the match winner
#                     spins the roulette for a powerup. On by default, and off
#                     over a network whatever this says, which OPTIONS.BM
#                     requires. --gold 0 turns it off.
#   --no-music        MESSAGES.TXT 263's "Disable music during gameplay". The
#                     music is read from the player's own game data and is
#                     absent from any build that has none — a browser build has
#                     no music whatever this says.
#   --pack DIR        the art pack to play with. data/packs/cd by default.
#   --pack-overlay D  replacement art laid OVER the pack: whatever the folder
#                     names is replaced and everything else is left alone. Give
#                     it more than once to stack overlays. docs/ART.md.
#   --pad-slots LIST  which slots the gamepads drive, in pad order. The menu
#                     writes this; MESSAGES.TXT 223's JOY %u is the slot type
#                     it comes from.
#   --stats-off       do not count or write the statistics file. --shot implies
#                     it, so a render test leaves no bmstats.dat behind.
#   --quit-tick N     quit at tick N, drawing nothing. --shot needs a window
#                     and a window needs the focus; this does not, which is
#                     what lets a headless check run the game and then read
#                     what it wrote on the way out.
#   --stats-path DIR  write bmstats.dat and bmstats.txt into DIR instead of
#                     user://, and count even under --shot. How the end-to-end
#                     test gets a file it can read.
#
# Two of the original's own settings, from its options screen, each defaulting
# to the resource the disc gives for it:
#   --kill-total      MESSAGES.TXT 255: the match is won on kills rather than
#                     on rounds. The target is the same --wins number, because
#                     the disc has one number and two words for it (120/121).
#   --random-start N  MESSAGES.TXT 251: deal the scheme's start cells out at
#                     random, once per match. VALUELST 40 has this ON by
#                     default, so the useful form is --random-start 0, which
#                     turns it off; OPTIONS.BM says to do that for a team
#                     scheme.
#
# Networked play. Three modes, and the local one is still the default so the
# game runs with no arguments at all:
#
#   (none)            local: this process owns the simulation, two players on
#                     one keyboard
#   --serve PORT      host: run the authoritative server AND play on it
#   --join URL        client: play on somebody else's server, e.g.
#                     --join ws://192.168.1.20:47600
#   --dedicated PORT  server only, no window, no art. This is what the
#                     container runs.
#   --name NAME       the name to join under
#   --bots N          fill N slots with bots. Works in local and host mode; a
#                     joining client cannot add them, because the server owns
#                     the simulation.
#   --mute            load no sounds and play none. What the render tests use,
#                     and what a machine with no audio device wants.
#   --menu            start on the menu even when other flags are given.
#   --screen NAME     open straight onto one screen: title, menu, setup,
#                     options, about, manual, results, victory, draw.
#   --scale N         window size as a multiple of 640x480. Default: the
#                     largest that fits the display, capped at 4.
#   --fullscreen      start filling the screen. F11 toggles it.
#
# THE MENU AND THE COMMAND LINE. A bare launch shows the menu. Any flag that
# configures a game — scheme, level, players, bots, wins, seconds, seed, shot,
# auto-bomb — skips it and starts immediately, so every command line in
# docs/STATUS.md and every screenshot script still means what it meant. That
# rule is one list, MENU_SKIPPING_FLAGS, rather than a condition spread out.
#   --wins N          how many round wins take the match. Defaults to VALUELST
#                     resource 310's two, whose comment says it is a setting.
#   --seconds N       round length, overriding resource 100's 150. A setting in
#                     the original too; here it is mostly how a whole match can
#                     be watched in under a minute.
extends Node2D

const Const_ := preload("res://scripts/core/const.gd")
const Types_ := preload("res://scripts/core/types.gd")
const Values_ := preload("res://scripts/core/values.gd")
const Field_ := preload("res://scripts/sim/field.gd")
const Player_ := preload("res://scripts/sim/player.gd")
const Bomb_ := preload("res://scripts/sim/bomb.gd")
const Snapshot_ := preload("res://scripts/net/snapshot.gd")
const Messages_ := preload("res://scripts/core/messages.gd")
const Scheme_ := preload("res://scripts/core/scheme.gd")
const Sim_ := preload("res://scripts/sim/sim.gd")
const Pack_ := preload("res://scripts/render/pack.gd")
const Keysets_ := preload("res://scripts/app/keysets.gd")
const Pads_ := preload("res://scripts/app/pads.gd")
const Match_ := preload("res://scripts/core/match.gd")
const Sfx_ := preload("res://scripts/audio/sfx.gd")
const Music_ := preload("res://scripts/audio/music.gd")
const Campaign_ := preload("res://scripts/core/campaign.gd")
const Creature_ := preload("res://scripts/sim/creature.gd")
const Discovery_ := preload("res://scripts/net/discovery.gd")
const Menu_ := preload("res://scripts/app/menu.gd")
const Screens_ := preload("res://scripts/app/screens.gd")
const Roulette_ := preload("res://scripts/app/roulette.gd")
const Server_ := preload("res://scripts/net/server.gd")
const Client_ := preload("res://scripts/net/client.gd")
const Stats_ := preload("res://scripts/core/stats.gd")

const GameView := preload("res://scripts/render/game_view.gd")
const MenuView := preload("res://scripts/render/menu_view.gd")
const ScreenView := preload("res://scripts/render/screen_view.gd")

var sim: Sim_ = null

## The statistics counters — MESSAGES.TXT 900-928, written to user://bmstats.dat
## and user://bmstats.txt when the game exits. See scripts/core/stats.gd.
var stats: Stats_ = null
var _stats_dat: String = Stats_.DAT_PATH
var _stats_txt: String = Stats_.TXT_PATH
var pack: Pack_ = null
var sfx: Sfx_ = null

## The per-level music — SOUNDLST 1100-1110, read from the player's own copy of
## the game because 120 MB of it cannot travel in a 7 MB pack.
## scripts/audio/music.gd says the rest.
var music: Music_ = null

## The match, in LOCAL mode. In HOST and JOIN the server owns it and the client
## is told; see scripts/core/match.gd.
var the_match: Match_ = null

## Ticks since a local round ended, or -1 when one is running.
var _intermission: int = -1

## The tick a local match was won on, or -1. The banner holds for the
## between-rounds wait and then the victory screen comes up.
var _match_over_at: int = -1

## Sounds the client was told about since the last frame.
var _heard: Array[Dictionary] = []

## How many bots a local game started with, so a new round gets them back.
var _local_bots: int = 0

## True when the setup screen was reached by Start Network Game.
var _hosting_from_menu: bool = false

## Which slots the keysets drive, and which are AI. See _start_from_args.
var _key_slots: Array[int] = []
var _ai_slots: Array[int] = []

## The options-screen settings this game was started with, re-applied to every
## round's simulation. Empty means "the tuning table's defaults".
var _settings: Dictionary = {}

## Round length in seconds, or 0 for resource 100's default.
var _round_seconds: int = 0
var keys: Keysets_ = null

## Gamepads — MESSAGES.TXT 223's JOY slot type. scripts/app/pads.gd.
var pads: Pads_ = null

## Which slot each pad drives, in pad order, the way _key_slots works.
var _pad_slots: Array[int] = []

## Which team each slot is on, when the setup screen's own 'T' has been used —
## INPUT.BM: "To toggle which team a player is on, press 'T'." Empty means the
## default split, which is OPTIONS.BM's 1-5 against 6-10.
var _slot_team: Array[int] = []

# ---------------------------------------------------------------------------
# Campaign mode — the disc's own single-player mode, out of its three .CAM
# files. scripts/core/campaign.gd has the format and the evidence.
# ---------------------------------------------------------------------------
## Games found on the LAN — MESSAGES.TXT 60-66's list. The listener runs
## while the menu is up and stops when a game starts, because a beacon is
## only interesting when you are looking for one.
var lan: Discovery_ = null
var _lan_ms: int = 0

var campaign: Campaign_ = null
var campaign_stage: int = 0
var campaign_score: int = 0
## Set when a stage is cleared or lost, so the next tick moves on rather than
## the same one firing every frame.
var _campaign_settled: bool = false
var view: Node2D = null

## The menu, and its view. Both null once a game has started.
var menu: Menu_ = null
var menu_view: Node2D = null


## The screen flow — title, main menu, setup, options, results, victory. Mode
## MENU means "a screen is up", whichever one; `screens.screen` says which.
var screens: Screens_ = null

## The Goldman wheel, while it is spinning, and what it last awarded. The
## reward is "given to the winner of the LAST match" (OPTIONS.BM), so it is
## held across to the next one.
var roulette: Roulette_ = null
var _gold_slot: int = -1
var _gold_powerup: int = -1

## Kept so the menu can be returned to, and so a restart does not have to
## re-derive what was asked for.
var _args: Dictionary = {}

var level: int = 0
var players: int = 2
var round_seed: int = 1

var _accum_ms: float = 0.0
var _shot_path: String = ""
var _shot_tick: int = 1
var _shot_taken: bool = false
var _auto_bomb_tick: int = -1

## Quit at this tick, drawing nothing. See --quit-tick.
var _quit_tick: int = -1

## Networking. In LOCAL mode both are null and this process ticks its own
## simulation. Hosting runs a server here and joins it as a client, so the host
## plays through exactly the same path as everyone else — which means the host
## cannot accidentally get a different game from its guests.
enum Mode { MENU, LOCAL, HOST, JOIN, DEDICATED }

## Any of these on the command line means "start a game now", not "show me the
## menu". Kept as a list so adding a flag cannot silently change which
## invocations open the menu.
const MENU_SKIPPING_FLAGS := ["scheme", "level", "players", "bots", "wins",
	"seconds", "seed", "auto-bomb", "serve", "join", "dedicated", "campaign"]
var mode: int = Mode.LOCAL
var server: Server_ = null
var client: Client_ = null
var player_name: String = "player"


func _ready() -> void:
	var args := _parse_args()
	_args = args

	# The statistics counters, before anything that could increment one. The
	# totals from previous runs come off disc here; a first run has none and
	# that is not an error. --shot and --stats-off skip the whole thing, so a
	# render test does not leave a bmstats.dat behind.
	var stats_dir := str(args.get("stats-path", ""))
	if not args.has("stats-off") and (stats_dir != "" or not args.has("shot")):
		if stats_dir != "":
			_stats_dat = stats_dir.path_join("bmstats.dat")
			_stats_txt = stats_dir.path_join("bmstats.txt")
		stats = Stats_.new()
		stats.load_totals(_stats_dat)

	pack = Pack_.new()
	if not pack.load_from(str(args.get("pack", Pack_.default_dir()))):
		# Not fatal. The view falls back to flat colours and says why, which is
		# more useful than refusing to start: the simulation is what is being
		# exercised, and it needs no art at all.
		push_warning(pack.error)
	# Replacement art, laid over whatever loaded: --pack-overlay DIR replaces
	# only what that folder names and leaves the rest alone, which is what
	# makes repainting the game a job that can be done one sheet at a time.
	# tools/artpack.py builds the folders; docs/ART.md is the guide.
	for overlay in _string_list(args.get("pack-overlay", [])):
		if pack.overlay_from(overlay):
			print("main: art overlay %s" % overlay)
		else:
			push_warning("overlay %s: %s" % [overlay, pack.error])

	# Audio first, so the menu can be heard as well as the game.
	if not args.has("dedicated") and not args.has("mute"):
		sfx = Sfx_.new()
		add_child(sfx)
		sfx.load_pack()
		music = Music_.new()
		add_child(music)
		music.disabled = _flag_value(args.get("no-music", false))
		music.data_dir = data_dir()
		if sfx.pack != null:
			music.names = sfx.pack.music
			music.screen_names = sfx.pack.music_screens

	# A player's own key choices, from a previous run. Missing is not an error:
	# it means the two defaults stand. MESSAGES.TXT 1100-1140 is the screen
	# that writes this file.
	Keysets_.load_keys()
	keys = Keysets_.new()
	pads = Pads_.new()
	_size_the_window(args)

	# Read here rather than in _start_from_args, so `--menu --shot PATH`
	# captures the menu. Without it the screenshot path is unreachable from
	# the one screen that has no simulation to tick.
	_shot_path = str(args.get("shot", ""))
	_shot_tick = int(args.get("shot-tick", 1))
	_quit_tick = int(args.get("quit-tick", -1))

	# A bare launch shows the menu. See MENU_SKIPPING_FLAGS.
	var wants_menu := args.has("menu")
	if not wants_menu:
		wants_menu = true
		for flag in MENU_SKIPPING_FLAGS:
			if args.has(flag):
				wants_menu = false
				break
	if wants_menu:
		# --screen NAME opens straight onto one, which is how the render tests
		# and the screenshots reach a screen that is normally several
		# keypresses in.
		_open_menu(_screen_named(str(args.get("screen", ""))))
		return

	_start_from_args(args)


## Show the menu. Also where a finished game comes back to, so it tears down
## whatever was running rather than assuming a clean start.
## Open as large as the display allows, in whole multiples of 640x480.
##
## The original ran at 640x480 and nothing else — DirectDraw, one mode — and its
## art is authored for it: `BM95.EXE` derives the playfield origin from the
## screen size (0x42647A) but the status area, the menus and all eleven level
## backgrounds are 640x480 bitmaps. So the faithful way to fill a modern display
## is to SCALE that canvas rather than to widen it, which is what
## project.godot's `canvas_items` stretch with `integer` scaling does.
##
## Only the window size is decided here. A whole multiple keeps every pixel
## square, which matters: at a fractional scale a 1px flame outline lands on
## some rows and not others.
##
##   --scale N     force a multiple
##   --fullscreen  start filling the screen
##   F11           toggle it at any time
func _size_the_window(args: Dictionary) -> void:
	if OS.has_feature("web") or args.has("shot"):
		# A browser sizes its own canvas, and a screenshot run must keep the
		# resolution it was given or the render tests measure the wrong thing.
		return
	var screen := DisplayServer.screen_get_usable_rect(
		DisplayServer.window_get_current_screen())
	var want := int(args.get("scale", 0))
	if want <= 0:
		# The largest whole multiple that leaves a little room for the window
		# chrome, capped at 4x — beyond that the pixels are enormous and the
		# window is unwieldy.
		want = mini(
			int(float(screen.size.x) * 0.92) / Const_.SCREEN_W,
			int(float(screen.size.y) * 0.88) / Const_.SCREEN_H)
		want = clampi(want, 1, 4)
	var size := Vector2i(Const_.SCREEN_W * want, Const_.SCREEN_H * want)
	DisplayServer.window_set_size(size)
	DisplayServer.window_set_position(
		screen.position + (screen.size - size) / 2)
	if args.has("fullscreen"):
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	print("main: window %dx%d (%dx of 640x480) on a %dx%d screen"
		% [size.x, size.y, want, screen.size.x, screen.size.y])


## "Alt-N - dump out the networking statistics (NETSTATS.TXT)". MANUAL.BM
## names the file and nothing else about its format — no data file states
## one, unlike bmstats.dat/.txt's resource 900-928. Written the same way
## those are: user://, plain text, on demand, a real measurement rather than
## an invented one. The size and rate come straight from Snapshot_.write(),
## the same call tests/test_net.gd's own bandwidth assertions use.
func _write_netstats() -> void:
	var lines: Array[String] = ["NETSTATS.TXT", ""]
	match mode:
		Mode.HOST:
			lines.append("mode: host")
			lines.append("clients connected: %d" % server.player_count())
			lines.append("ticks served: %d" % server.ticks_served)
		Mode.JOIN:
			lines.append("mode: client")
			lines.append("server tick: %d" % client.server_tick)
		_:
			lines.append("mode: local (no network session)")
	if sim != null:
		var size := Snapshot_.write(sim).size()
		var bps := size * Const_.TICK_HZ
		lines.append("snapshot size: %d bytes" % size)
		lines.append("bandwidth per client: %.1f kbps at %d Hz"
			% [bps * 8.0 / 1000.0, Const_.TICK_HZ])
	var f := FileAccess.open("user://NETSTATS.TXT", FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(lines) + "\n")
		f.close()
		print("main: wrote NETSTATS.TXT")


## "Alt-D - display the misc info screen". MANUAL.BM's own warning —
## "use it VERY sparingly when network play is going on... it will affect
## synchronization!" — is the one fact known about it beyond the name: it
## does something disruptive enough to desync a match, which nothing this
## port could safely reproduce is worth reproducing. What IS safe, and
## shown here instead, is everything this build already knows about its own
## state without touching the simulation: printed to the console rather
## than drawn, since no in-game overlay for it exists and inventing one
## would be exactly the kind of screen this file elsewhere warns against
## drawing from nothing.
func _print_misc_info() -> void:
	var player_count := sim.players.size() if sim != null else players
	print("main: misc info — mode=%s level=%d players=%d tick=%s"
		% [Mode.keys()[mode], level, player_count,
			str(sim.tick_count) if sim != null else "n/a"])


func _toggle_fullscreen() -> void:
	var mode := DisplayServer.window_get_mode()
	if mode == DisplayServer.WINDOW_MODE_FULLSCREEN \
			or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)


## `at` picks which screen to open on: the title on a cold start, the main
## menu when a game has just ended, a victory screen when a match has.
## A screen by name, for --screen. Unknown or absent gives the title.
static func _screen_named(name: String) -> int:
	match name.to_lower():
		"title": return Screens_.Screen.TITLE
		"menu", "mainmenu", "main": return Screens_.Screen.MAIN_MENU
		"setup": return Screens_.Screen.SETUP
		"options": return Screens_.Screen.OPTIONS
		"about": return Screens_.Screen.ABOUT
		"manual": return Screens_.Screen.MANUAL
		"results": return Screens_.Screen.RESULTS
		"victory": return Screens_.Screen.VICTORY
		"roulette": return Screens_.Screen.ROULETTE
		"draw": return Screens_.Screen.DRAW
	return Screens_.Screen.TITLE


## Every name --screen accepts, so a test can walk all of them.
static func screen_names() -> Array[String]:
	return ["title", "menu", "setup", "options", "about", "manual",
		"results", "victory", "draw", "roulette"] as Array[String]


func _open_menu(at: int = Screens_.Screen.TITLE) -> void:
	var keep_match = the_match
	var champion := -1
	var champion_team := -1
	var teams := false
	if keep_match != null:
		champion = keep_match.champion_slot
		champion_team = keep_match.champion_team
		teams = keep_match.team_play
	_teardown()
	mode = Mode.MENU
	menu = Menu_.new()
	menu.setup(pack.scheme_names() if pack != null and pack.loaded else [])
	# Which slots may be JOY depends on what is plugged in right now.
	menu.pads_available = Pads_.connected().size()
	menu.set_campaigns(pack.campaign_names() if pack != null and pack.loaded
		else [])
	# Listen for games while the menu is up. A browser cannot: UDP is not
	# something a page may open, so the list is simply empty there and the
	# ?join= URL remains the way in.
	if lan == null and not OS.has_feature("web"):
		lan = Discovery_.new()
		if not lan.listen():
			push_warning("no LAN game list: %s" % lan.error)
			lan = null
	screens = Screens_.new()
	screens.screen = at
	screens.join_url = String(_args.get("join", ""))
	if at == Screens_.Screen.VICTORY or at == Screens_.Screen.DRAW:
		screens.finish_match(champion, champion_team, teams)
	# The wheel is not offered over a network: OPTIONS.BM says the Gold
	# Bomberman is "not available in network games", and the reward would
	# have to be agreed by every client to be fair.
	# MESSAGES.TXT 256's own option, and then the network rule on top of it.
	if _args.has("gold"):
		screens.gold_bomberman = _flag_value(_args["gold"])
	screens.gold_bomberman = screens.gold_bomberman \
		and not _args.has("serve") and not _args.has("join")
	if at == Screens_.Screen.ROULETTE and roulette == null:
		# Opened straight onto the wheel by --screen, with no match behind it.
		roulette = Roulette_.new()
		roulette.start(maxi(champion, 0), 1)
	menu_view = ScreenView.new()
	menu_view.screens = screens
	menu_view.roulette = roulette
	menu_view.menu = menu
	menu_view.pack = pack
	menu_view.the_match = keep_match
	add_child(menu_view)
	menu_view.queue_redraw()


## Drop the running game, whatever kind it was. Called before opening the menu
## and before starting anything from it.
func _teardown() -> void:
	# The menu is not gameplay, and MESSAGES.TXT 263 says "during gameplay".
	if music != null:
		music.stop()
	# Stop listening for games once one has started: the socket is only
	# interesting while somebody is choosing.
	if lan != null:
		lan.close()
		lan = null
	if client != null:
		client.close()
		client = null
	if server != null:
		server.close()
		server = null
	if sfx != null:
		sfx.stop_all()
	if view != null:
		view.queue_free()
		view = null
	if menu_view != null:
		menu_view.queue_free()
		menu_view = null
	menu = null
	screens = null
	sim = null
	the_match = null
	_intermission = -1
	_match_over_at = -1
	_accum_ms = 0.0
	_heard.clear()


## Start what the menu asked for.
func _start_from_menu() -> void:
	if not menu.validate(pack):
		# validate() has put the reason in menu.refusal; the view shows it.
		menu_view.queue_redraw()
		return
	var cfg := menu.config(pack)
	var host := menu.action == Menu_.Action.HOST or _hosting_from_menu
	var scheme: Scheme_ = Scheme_.new()
	if String(cfg["scheme_text"]).is_empty():
		scheme = _builtin_scheme()
	elif not scheme.parse_text(String(cfg["scheme_text"]),
			String(cfg["scheme_name"])):
		# validate() already rejected this, so reaching here means the two
		# disagree — say so rather than starting something unplayable.
		menu.refusal = "%s will not parse: %s" % [cfg["scheme_name"],
			scheme.error()]
		menu_view.queue_redraw()
		return

	var args := {
		"level": cfg["level"], "wins": cfg["wins"], "teams": cfg["teams"],
		"kill-total": cfg["kill_total"], "random-start": cfg["random_start"],
		"no-music": cfg["no_music"], "gold": cfg["gold"],
		"seconds": cfg["seconds"], "enclose": cfg["enclose_depth"],
		"conveyor": cfg["conveyor"], "stomped": cfg["stomped"],
		"diseases": cfg["diseases_destroyable"],
		"lost-net-ai": cfg["lost_net_to_ai"],
		"seed": _args.get("seed", 1), "name": _args.get("name", "player"),
		# The slot lists, which is what the menu adds that flags cannot say:
		# WHICH slots are AI and which keyset drives which.
		"ai-slots": cfg["ai_slots"], "key-slots": cfg["key_slots"],
		"pad-slots": cfg["pad_slots"], "slot-teams": cfg["slot_teams"],
	}
	if not String(cfg["campaign"]).is_empty():
		# A campaign is not a match: it brings its own scheme, level and
		# opponents, so nothing else on the screen applies to it.
		args["campaign"] = cfg["campaign"]
	if host:
		args["serve"] = cfg["port"]
	if _args.has("debug-grid"):
		args["debug-grid"] = true
	_teardown()
	_start_from_args(args, scheme)


## The whole start path, for both the command line and the menu. One function,
## because two would drift and the menu would end up playing a subtly different
## game from the flags.
func _start_from_args(args: Dictionary, ready_scheme: Scheme_ = null) -> void:
	var scheme := ready_scheme
	if scheme == null:
		scheme = _load_scheme(str(args.get("scheme", "")))
	if scheme == null:
		push_error("no scheme could be loaded; nothing to play")
		_quit(2)
		return

	level = clampi(int(args.get("level", 0)), 0, 10)
	players = clampi(int(args.get("players", 2)), 1, Const_.PLAYER_COUNT)
	round_seed = int(args.get("seed", 1))
	_shot_path = str(args.get("shot", ""))
	_shot_tick = int(args.get("shot-tick", 1))
	_quit_tick = int(args.get("quit-tick", -1))
	_auto_bomb_tick = int(args.get("auto-bomb", -1))

	player_name = str(args.get("name", "player"))

	mode = Mode.LOCAL
	if args.has("dedicated"):
		mode = Mode.DEDICATED
	elif args.has("serve"):
		mode = Mode.HOST
	elif args.has("join"):
		mode = Mode.JOIN

	var scheme_source := scheme.to_text()

	match mode:
		Mode.DEDICATED, Mode.HOST:
			var port := int(args.get("dedicated", args.get("serve", 47600)))
			server = Server_.new()
			server.stats = stats
			if not server.listen(port, scheme_source, level, round_seed):
				push_error("cannot listen on %d" % port)
				_quit(2)
				return
			print("main: serving on port %d" % port)
			# Shout on the LAN so another machine's "Available net games"
			# list has something in it. scripts/net/discovery.gd.
			server.announce(player_name)
			if stats != null:
				stats.bump(Stats_.C.NET_HOSTED)
				stats.bump(Stats_.C.MATCHES_STARTED)
			if int(args.get("wins", 0)) > 0:
				server.the_match.wins_to_win = int(args["wins"])
			server.the_match.win_by_kills = bool(args.get("kill-total", false))
			if mode == Mode.HOST:
				client = Client_.new()
				client.round_started.connect(_on_client_round_started)
				client.connect_to("ws://127.0.0.1:%d" % port, player_name)
		Mode.JOIN:
			client = Client_.new()
			client.round_started.connect(_on_client_round_started)
			# Only a JOINing client counts: a host's own client shares the
			# process with the server, and would count the same loopback
			# packets twice.
			client.stats = stats
			var url := str(args.get("join", ""))
			if not client.connect_to(url, player_name):
				push_error(client.reject_reason)
				_quit(2)
				return
			if stats != null:
				stats.bump(Stats_.C.NET_JOINED)
			print("main: joining %s as %s" % [url, player_name])

	# WHO IS PLAYING. Two ways in and one representation out.
	#
	# The command line says "N humans then M bots", which is all a flag can
	# say. The menu says which of the ten slots is a keyboard player and which
	# is an AI, because MESSAGES.TXT 220-224 is the original's slot model and
	# it can express things the pair of counts cannot — slots 1 and 5 on the
	# keyboard with 2, 3 and 4 as AI, say. Both are reduced to the two lists
	# below, and nothing downstream knows which way it was asked.
	var bots := int(args.get("bots", 0))
	if args.has("key-slots") or args.has("ai-slots"):
		_key_slots = _int_list(args.get("key-slots", []))
		_ai_slots = _int_list(args.get("ai-slots", []))
		_pad_slots = _int_list(args.get("pad-slots", []))
		_slot_team = _int_list(args.get("slot-teams", []))
	else:
		_key_slots = []
		_ai_slots = []
		_pad_slots = []
		_slot_team = []
		for i in players:
			_key_slots.append(i)
		for i in bots:
			_ai_slots.append(players + i)
	players = _key_slots.size() + _pad_slots.size()
	_local_bots = _ai_slots.size()

	_round_seconds = int(args.get("seconds", 0))

	# A campaign is its own thing: one player, the stage's own scheme and
	# level, and no match around it. It takes over before the ordinary local
	# path builds anything.
	# The options screen's own music setting, which only the command line used
	# to reach: _ready() read the flag once and a game started from the menu
	# never told the player again.
	if music != null:
		music.disabled = _flag_value(args.get("no-music", false))

	if mode == Mode.LOCAL and args.has("campaign"):
		_apply_settings(args)
		if start_campaign(str(args["campaign"]).to_upper()):
			if mode != Mode.DEDICATED:
				view = GameView.new()
				view.sim = sim
				view.pack = pack
				view.level = level
				view.local_slots = _key_slots + _pad_slots
				view.show_grid = args.has("debug-grid")
				add_child(view)
			return
		_quit(2)
		return

	if mode == Mode.LOCAL:
		sim = Sim_.new()
		sim.stats = stats
		if stats != null:
			stats.bump(Stats_.C.MATCHES_STARTED)
		the_match = Match_.new()
		the_match.random_level = level < 0
		the_match.level_count = int(Values_.V[Const_.Res.LEVEL_COUNT])
		the_match.win_by_kills = bool(args.get("kill-total", false))
		the_match.setup(round_seed, maxi(level, 0),
			bool(args.get("teams", false)), int(args.get("wins", 0)))
		level = the_match.level
		_scheme = scheme
		_apply_settings(args)
		_start_local_round()
	elif server != null:
		server.the_match.random_level = level < 0
		server.the_match.level_count = int(Values_.V[Const_.Res.LEVEL_COUNT])
		server.settings = _settings_of(args)
		server.lost_net_to_ai = bool(args.get("lost-net-ai", false))
		if not _ai_slots.is_empty():
			server.add_bot_slots(_ai_slots)
		elif bots > 0:
			server.add_bots(bots)


	if client != null:
		client.sound.connect(_on_client_sound)

	if mode != Mode.DEDICATED:
		view = GameView.new()
		view.sim = sim
		view.pack = pack
		view.level = level
		view.local_slots = _key_slots + _pad_slots
		view.show_grid = args.has("debug-grid")
		view.the_match = the_match if the_match != null else (
			client.the_match if client != null else null)
		add_child(view)

	print("main: %s — level %d, %d players, seed %d%s" % [
		scheme.name, level, players, round_seed,
		"" if pack.loaded else "  (no art pack: flat colours)"])


## A flag that may be given more than once, or once with a comma-separated
## value. Used by --pack-overlay, where stacking is the point.
static func _string_list(value: Variant) -> Array[String]:
	var out: Array[String] = []
	if value is Array:
		for entry in (value as Array):
			out.append(String(entry))
	elif value is String and not (value as String).is_empty():
		for part in (value as String).split(",", false):
			out.append(part)
	return out


## An Array of ints from whatever the caller passed — the menu hands over real
## arrays, and a command line could not.
static func _int_list(value: Variant) -> Array[int]:
	var out: Array[int] = []
	if value is Array:
		for v in (value as Array):
			out.append(int(v))
	return out


## The settings the original's options screen exposes, gathered in one place so
## the server and a local game apply the same set. Absent keys keep the
## simulation's VALUELST defaults.
## Every seat's team in slot order, for Win Matches By Kill Total. The mirror
## of server.gd's own — a local match has no server to ask.
## The team a slot plays on: what the setup screen's 'T' set, or the default.
func _team_for(slot: int) -> int:
	if slot >= 0 and slot < _slot_team.size():
		return _slot_team[slot]
	return Const_.default_team(slot)


func _slot_teams() -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize(Const_.PLAYER_COUNT)
	if sim != null:
		for p in sim.players:
			if p.slot >= 0 and p.slot < out.size():
				out[p.slot] = p.team
	return out


## Where the original's data lives. AB_DATA overrides it, which is what the
## tools and the documentation both say; otherwise it is the folder beside the
## project, which is where a working tree keeps it.
static func data_dir() -> String:
	var env := OS.get_environment("AB_DATA")
	if not env.is_empty():
		return env
	return ProjectSettings.globalize_path("res://").path_join(
		"../original-game").simplify_path()


func _settings_of(args: Dictionary) -> Dictionary:
	var out := {}
	if args.has("enclose"):
		out["enclose_depth"] = int(args["enclose"])
	if args.has("conveyor"):
		out["conveyor_speed_index"] = int(args["conveyor"])
	if args.has("stomped"):
		out["stomped_detonate"] = bool(args["stomped"])
	if args.has("diseases"):
		out["diseases_destroyable"] = bool(args["diseases"])
	if args.has("random-start"):
		# The disc's default is ON (VALUELST 40), so this flag has to be able
		# to say NO as well as yes: --random-start 0 turns it off. A bare
		# --random-start is a `true` from the parser and means on.
		out["random_start"] = _flag_value(args["random-start"])
	return out


## A command-line flag's truth. `--flag` on its own is true; `--flag 0`,
## `--flag no` and `--flag false` are false. Without this, a flag whose
## DEFAULT is on could only ever be turned on again.
static func _flag_value(raw: Variant) -> bool:
	if raw is bool:
		return raw
	var text := String(raw).strip_edges().to_lower()
	return not (text in ["0", "no", "off", "false"])


func _apply_settings(args: Dictionary) -> void:
	_settings = _settings_of(args)
	_settings_to(sim)


func _settings_to(target: Sim_) -> void:
	if target == null:
		return
	for key in _settings:
		target.set(key, _settings[key])


func _parse_args() -> Dictionary:
	var out := {}

	# In a browser there is no command line. The query string is the only way
	# a player can be told which server to join, which is why server/README.md
	# hands out URLs of the form
	#     http://host:8080/?join=ws://host:47600
	if OS.has_feature("web"):
		var query: Variant = JavaScriptBridge.eval(
			"window.location.search.substring(1)", true)
		if query is String and not (query as String).is_empty():
			for pair in (query as String).split("&"):
				var kv: PackedStringArray = pair.split("=")
				if kv.size() == 2:
					out[kv[0].uri_decode()] = kv[1].uri_decode()

	var argv := OS.get_cmdline_user_args()
	var i := 0
	while i < argv.size():
		var a: String = argv[i]
		if a.begins_with("--"):
			var name := a.substr(2)
			if i + 1 < argv.size() and not (argv[i + 1] as String).begins_with("--"):
				out[name] = argv[i + 1]
				i += 1
			else:
				out[name] = true
		i += 1
	return out


func _load_scheme(path: String) -> Scheme_:
	var scheme: Scheme_ = Scheme_.new()
	if not path.is_empty():
		if scheme.parse_file(path):
			return scheme
		push_error("cannot load %s: %s" % [path, scheme.error()])
		return null

	# No scheme named: take the first from the original's SCHEMES folder if it
	# is there, else fall back to a built-in grid so the app still runs on a
	# machine with no copy of the game.
	var dir_path := ProjectSettings.globalize_path("res://").path_join(
		"../original-game/SCHEMES").simplify_path()
	var dir := DirAccess.open(dir_path)
	if dir != null:
		var names: Array[String] = []
		for f in dir.get_files():
			if f.to_upper().ends_with(".SCH"):
				names.append(f)
		names.sort()
		for n in names:
			if scheme.parse_file(dir_path.path_join(n)):
				return scheme
	return _builtin_scheme()


# The classic pillar grid, so the app is runnable with no game data at all.
func _builtin_scheme() -> Scheme_:
	var lines := PackedStringArray()
	lines.append("-V,2")
	lines.append("-N,Built-in grid (10)")
	lines.append("-B,90")
	for y in Const_.FIELD_H:
		var row := ""
		for x in Const_.FIELD_W:
			row += "#" if (x % 2 == 1 and y % 2 == 1) else ":"
		lines.append("-R,%2d,%s" % [y, row])
	var starts := [[0, 0], [14, 10], [0, 10], [14, 0], [6, 4],
		[8, 0], [12, 4], [2, 6], [10, 8], [6, 10]]
	for p in Const_.PLAYER_COUNT:
		lines.append("-S,%d,%d,%d,%d" % [p, starts[p][0], starts[p][1], p % 2])
	for i in Const_.POWERUP_COUNT:
		lines.append("-P,%2d, 0,0, 0, 0,x" % i)
	var s: Scheme_ = Scheme_.new()
	s.parse_text("\n".join(lines), "<built-in>")
	return s if s.ok() else null


func _process(delta: float) -> void:
	if stats != null:
		stats.bump(Stats_.C.FRAMES_RENDERED)
	# A screen is not a simulation, but it does animate — so it gets the same
	# fixed tick and nothing else here runs while one is up.
	if mode == Mode.MENU:
		# Games on the LAN, while the menu is up. The clock is passed in so the
		# forgetting is testable; here it is just elapsed milliseconds.
		if lan != null:
			_lan_ms += int(delta * 1000.0)
			lan.poll(delta * 1000.0, _lan_ms)
			if screens != null:
				screens.net_games = lan.games()
		# The screens have music of their own on the disc — SOUNDLST 1000 title,
		# 1010 menu, 1020 the input-selection screen, 1030 game over, 1040
		# network. A menu in silence was the first thing anyone noticed.
		if music != null and screens != null:
			var want := _screen_track(screens.screen)
			if not want.is_empty() and music.screen() != want:
				music.play_screen(want)
		# The screens animate: a blinking prompt, the cursor's four frames, and
		# the HEADWIPE transition. Ticked at the simulation's rate so the
		# animation speeds match the game's.
		# Clamped by resource 31, exactly as the simulation is. Without it the
		# first frame — which carries the whole window-and-pack load, about a
		# second — runs twenty ticks at once, and an animation is already over
		# by the time anybody sees it.
		# Clamped by resource 31, exactly as the simulation is. Without it the
		# first frame — which carries the whole window-and-pack load, about a
		# second — runs twenty ticks at once, and an animation is already over
		# by the time anybody sees it.
		_accum_ms += delta * 1000.0
		_accum_ms = minf(_accum_ms, float(Values_.V[Const_.Res.MAX_ADVANCE_MS]))
		while _accum_ms >= float(Const_.TICK_MS):
			_accum_ms -= float(Const_.TICK_MS)
			if screens != null:
				screens.tick()
			# INSIDE the fixed step, with the screens. Ticked once per frame
			# instead, the wheel ran five times faster than the screen it is
			# drawn on and had already landed by the twentieth screen tick.
			if roulette != null and not roulette.finished():
				var was := roulette.result
				roulette.tick()
				if sfx != null:
					if roulette.result < 0 and roulette.age % 4 == 0:
						sfx.play_batch([{"slot": roulette.slot,
							"effect": Types_.SoundEffect.ROULETTE_TICK,
							"arg": 0}], roulette.age)
					elif was < 0 and roulette.result >= 0:
						sfx.play_batch([{"slot": roulette.slot,
							"effect": Types_.SoundEffect.ROULETTE_BUZZ
								if roulette.punishment()
								else Types_.SoundEffect.ROULETTE_CLAP,
							"arg": 0}], roulette.age)
				if roulette.result >= 0 and _gold_powerup < 0:
					_take_the_prize()
		if menu_view != null:
			menu_view.queue_redraw()
		# The screen's own age, not _shot_tick: passing the target made the
		# test always true and every screenshot came out on frame one, so a
		# mid-animation frame could not be captured at all.
		_maybe_shoot(screens.age if screens != null else _shot_tick)
		return
	# A server, if this process is one. It owns the clock; everything else
	# follows from its snapshots.
	if server != null:
		server.poll(delta * 1000.0)
	if client != null:
		_poll_client(delta)
		# The screenshot path has to run in client mode too. It did not at
		# first, because this returned before reaching it — so --shot on a
		# joining client never fired and the process never quit, which looks
		# exactly like a hung join.
		_maybe_shoot(client.server_tick)
		_maybe_quit(client.server_tick)
		return
	if mode == Mode.DEDICATED:
		return
	if sim == null:
		return

	# Real time in, whole ticks out. The clamp is the sim's, from resource 31.
	_accum_ms += delta * 1000.0
	var budget: float = minf(_accum_ms, float(Values_.V[Const_.Res.MAX_ADVANCE_MS]))
	_accum_ms = budget

	while _accum_ms >= float(Const_.TICK_MS):
		_accum_ms -= float(Const_.TICK_MS)
		_step()

	# A tick can end the game under us: a campaign that is lost or finished
	# tears down its simulation and opens a screen from inside _step(). The
	# rest of this frame has nothing left to do, and doing it anyway threw
	# once a frame, forever.
	if sim == null:
		return

	# The leftover is how far into the next tick we are. The view uses it to
	# interpolate and never gives it back.
	if view != null:
		view.alpha = _accum_ms / float(Const_.TICK_MS)
		view.queue_redraw_all()

	_maybe_shoot(sim.tick_count)
	_maybe_quit(sim.tick_count)


## Exit cleanly once the requested tick has been reached, drawing nothing.
##
## --shot does the same job but needs a frame, so it needs a window, and a
## window that never comes to the front on macOS never draws — which made the
## statistics check in verify.sh fail once for no reason of its own. This is
## the headless version: no renderer, no focus, no wait. Wired into the client
## path as well, for the same reason --shot is.
func _maybe_quit(at_tick: int) -> void:
	if _quit_tick < 0 or at_tick < _quit_tick:
		return
	_report_audio()
	_quit(0)


## Capture one frame and exit, once the requested tick has been reached.
## Shared by local and client mode so --shot means the same thing in both.
func _maybe_shoot(at_tick: int) -> void:
	if _shot_path.is_empty() or _shot_taken or at_tick < _shot_tick:
		return
	_shot_taken = true
	# One frame has to be drawn before the viewport holds anything.
	await RenderingServer.frame_post_draw
	_capture(_shot_path)
	_report_audio()
	_quit(0)


## What the mixer actually did, printed on the way out.
##
## The only way to check audio in a headless or scripted run: nobody is
## listening, and a mixer that played nothing looks identical to one that
## played everything.
func _report_audio() -> void:
	if sfx == null or not sfx.ready_to_play():
		return
	var events := {}
	for entry in sfx.log:
		var name: String = entry["event"]
		events[name] = int(events.get(name, 0)) + 1
	var parts: Array[String] = []
	for name in events:
		parts.append("%s x%d" % [name, events[name]])
	parts.sort()
	print("audio: %d recent sounds — %s" % [sfx.log.size(), ", ".join(parts)])
	if not sfx.dropped.is_empty():
		print("audio: dropped %s" % str(sfx.dropped))


## A networked client renders whatever the server last sent. It never ticks a
## simulation of its own, which is what makes the netcode checkable: there is
## no prediction to blame a difference on.
func _poll_client(delta: float) -> void:
	client.poll()
	if not client.playing():
		if client.state == Client_.State.REFUSED:
			push_error("refused: %s" % client.reject_reason)
			_quit(3)
			return
		if client.state == Client_.State.CLOSED:
			print("main: the server closed the connection")
			_quit(0)
			return
		if view != null:
			view.queue_redraw_all()
		return

	# The view was built before the client had a simulation to show.
	if view != null and view.sim != client.sim:
		view.sim = client.sim
		view.level = client.level
		view.the_match = client.the_match
	elif view != null and view.level != client.level:
		# A new round can change the level under us.
		view.level = client.level
	# A joined client hears the level's own music too, out of its own copy of
	# the game — the server never sends any.
	if music != null and client.playing() and music.level() != client.level:
		music.play_level(client.level)

	# Input up, once per frame. The server is the clock; sending faster than it
	# ticks only costs bandwidth.
	# A joining client is one player, driven by the first keyset or the first
	# pad — whichever is being used. The keyboard wins a tie, and the pad is
	# read only when the keyboard says nothing, so a hand on both does not
	# fight itself.
	var move := keys.move_state(0)
	var act := keys.take_action(0)
	var held := keys.first_held(0)
	var connected := Pads_.connected()
	if not connected.is_empty():
		var pad: int = connected[0]
		if move == Types_.MoveState.STILL:
			move = pads.move_state(pad)
		var pad_action := pads.take_action(pad)
		if act == Types_.Action.NONE:
			act = pad_action
			held = pads.first_held(pad)
	client.send_input(move, act, held)

	# Sounds arrive as they are broadcast, which is per server tick, but this
	# runs per rendered frame. Batching them here means the mixer's one-per-
	# event-per-tick rule applies to what a frame heard, which is the closest
	# equivalent a client has.
	if sfx != null and not _heard.is_empty():
		sfx.play_batch(_heard, client.server_tick)
	_heard.clear()

	# Interpolation has nothing to interpolate FROM on a client: it is handed
	# whole states rather than stepping between its own. Snapping to the last
	# snapshot is honest — the alternative is inventing motion the server never
	# reported. Smoothing belongs in Phase 9, with the latency to tune against.
	if view != null:
		view.snapshot()
		view.alpha = 1.0
		view.queue_redraw_all()


func _step() -> void:
	# Snapshot before the tick, so the next frame interpolates from where
	# everyone actually was.
	view.snapshot()
	# Keyset n drives whatever slot the menu (or the flags) put it on, which is
	# not necessarily slot n: MESSAGES.TXT's model lets slot 5 be a keyboard
	# player while 1 is an AI.
	for ks in mini(Keysets_.MAPS.size(), _key_slots.size()):
		var slot: int = _key_slots[ks]
		var action := keys.take_action(ks)
		if sim.tick_count + 1 == _auto_bomb_tick:
			action = Types_.Action.FIRST
		sim.set_input(slot, keys.move_state(ks), action, keys.first_held(ks))
	# The same for the pads. JOY n is the n-th pad Godot reports, so pulling a
	# pad out renumbers the rest rather than leaving a seat driven by nothing.
	var connected := Pads_.connected()
	for i in _pad_slots.size():
		if i >= connected.size():
			continue
		var pad: int = connected[i]
		var pad_action := pads.take_action(pad)
		if sim.tick_count + 1 == _auto_bomb_tick:
			pad_action = Types_.Action.FIRST
		sim.set_input(_pad_slots[i], pads.move_state(pad), pad_action,
			pads.first_held(pad))
	# Slots beyond the two keysets get the auto-bomb too, so a ten-player
	# capture is not limited to the two that have keys.
	if sim.tick_count + 1 == _auto_bomb_tick:
		for p in sim.players:
			if not _key_slots.has(p.slot):
				sim.set_input(p.slot, Types_.MoveState.STILL,
					Types_.Action.FIRST)
		# Fire once. Left set, this re-triggers every round after the first,
		# because Sim.tick_count restarts at 0 and a long match walks back
		# past this same tick number again.
		_auto_bomb_tick = -1
	sim.tick()
	if sfx != null:
		sfx.play_batch(sim.sounds, sim.tick_count)
	_run_local_match()


## The match, in LOCAL mode. HOST and JOIN get this from the server instead —
## one implementation of the rules, in scripts/core/match.gd, driven from two
## places rather than written twice.
func _run_local_match() -> void:
	if campaign != null:
		_run_campaign()
		return
	if the_match == null:
		return
	if sim.round_over() and sim.ticks_since_over == 1:
		print("main: round over — outcome %d winner %d — %s"
			% [sim.outcome, sim.winner_slot, the_match.summary()])
		if the_match.record(sim.outcome, sim.winner_slot, sim.winner_team,
				sim.round_kills, _slot_teams()):
			if sfx != null:
				sfx.play_batch([{"slot": the_match.champion_slot,
					"effect": Types_.SoundEffect.MATCH_WIN, "arg": 0}],
					sim.tick_count)
			print("main: %s" % the_match.summary())
			# A won match holds the victory banner and then goes back to the
			# menu, which is the only way out that does not require knowing
			# that Escape does something.
			_match_over_at = sim.tick_count
		else:
			_intermission = 0
	if _match_over_at >= 0 and sim.tick_count - _match_over_at \
			>= Match_.intermission_ticks() and not sim.anyone_dying():
		# The victory screen, then the results, then the menu — which is the
		# order MESSAGES.TXT implies: 120/121 announce the winner and 900-928
		# are the statistics. _open_menu carries the match across so both
		# screens have something to show.
		#
		# Held on anyone_dying() too: SCREEN_MIN_SECONDS (3s, 60 ticks) is a
		# MINIMUM wait, and is shorter than DEATH_TICKS' own 5s guarantee that
		# every death animation gets to finish (up to XPLODE4's 93 steps).
		# The round-deciding kill is exactly the death a player is watching —
		# without this, the match-winning screen could cut it off mid-frame.
		_match_over_at = -1
		_open_menu(Screens_.Screen.VICTORY if not _was_draw()
			else Screens_.Screen.DRAW)
	if _intermission >= 0:
		_intermission += 1
		if _intermission >= Match_.intermission_ticks() \
				and not sim.anyone_dying():
			_intermission = -1
			the_match.next_round()
			_start_local_round()


# ---------------------------------------------------------------------------
# Campaign mode
# ---------------------------------------------------------------------------
#
# A stage is cleared by killing everything the .CAM row asked for — every rover,
# every ghost and every AI. There is one life: the disc says nothing about
# continues, and a campaign that cannot be lost is not one.


## Start a campaign by name. Returns false if the pack has no such file.
func start_campaign(which: String) -> bool:
	var text := ""
	if pack != null:
		text = pack.campaign_text(which)
	if text.is_empty():
		push_error("no campaign %s in the asset pack" % which)
		return false
	campaign = Campaign_.new()
	if not campaign.parse_text(text, which):
		push_error("campaign %s: %s" % [which, campaign.error])
		campaign = null
		return false
	campaign_stage = clampi(int(_args.get("campaign-stage", 1)) - 1,
		0, campaign.size() - 1)
	campaign_score = 0
	print("main: campaign %s — %d stages" % [which, campaign.size()])
	return _start_campaign_stage()


## Lay out the stage the campaign is on: its own level and scheme, its AIs as
## ordinary bots, and its rovers and ghosts scattered clear of the player.
func _start_campaign_stage() -> bool:
	var stage = campaign.stage_at(campaign_stage)
	if stage == null:
		return false
	_campaign_settled = false
	level = stage.level
	var scheme_text := pack.scheme_text(stage.scheme) if pack != null else ""
	var scheme: Scheme_ = Scheme_.new()
	if scheme_text.is_empty() or not scheme.parse_text(scheme_text,
			stage.scheme):
		# A stage naming a scheme this pack does not have still has to be
		# playable, or one missing file ends the campaign.
		push_warning("campaign stage %d: no scheme %s, using the built-in grid"
			% [campaign_stage + 1, stage.scheme])
		scheme = _builtin_scheme()
	_scheme = scheme

	sim = Sim_.new()
	sim.stats = stats
	sim.level = level
	sim.start_seed = campaign_stage + 1
	var slots := [{"slot": 0, "team": Const_.default_team(0)}]
	for i in stage.ais:
		slots.append({"slot": 1 + i, "team": Const_.default_team(1 + i)})
	_settings_to(sim)
	sim.setup(scheme, slots, campaign_stage + 1)
	for i in stage.ais:
		sim.add_bot(1 + i)
	_key_slots = [0]
	_pad_slots = []
	_ai_slots = []
	for i in stage.ais:
		_ai_slots.append(1 + i)
	_spawn_stage_creatures(stage)
	_apply_round_length()

	if view != null:
		view.level = level
		view.sim = sim
	if music != null:
		music.play_level(level)
	print("main: stage %d/%d — %s" % [campaign_stage + 1, campaign.size(),
		stage.summary()])
	return true


## Where the monsters start: any open cell at least four cells from every
## player, so a stage does not open with a rover already touching you. Four is
## this port's number — the disc gives counts and speeds and no positions.
func _spawn_stage_creatures(stage) -> void:
	var free: Array[Vector2i] = []
	for y in Const_.FIELD_H:
		for x in Const_.FIELD_W:
			if sim.field.brick_at(x, y) != Types_.Brick.BLANK:
				continue
			var clear := true
			for p in sim.players:
				if absi(p.tile_x() - x) + absi(p.tile_y() - y) < 4:
					clear = false
					break
			if clear:
				free.append(Vector2i(x, y))
	if free.is_empty():
		return
	var wanted: Array = []
	for i in stage.rovers:
		wanted.append([Creature_.Kind.ROVER, stage.rover_speed])
	for i in stage.ghosts:
		wanted.append([Creature_.Kind.GHOST, stage.ghost_speed])
	for entry in wanted:
		var cell: Vector2i = free[sim.rng.randi_range(0, free.size() - 1)]
		sim.add_creature(int(entry[0]), cell.x, cell.y, int(entry[1]))


## One tick of a campaign: score what died, then see whether the stage is over.
func _run_campaign() -> void:
	if sim == null or _campaign_settled:
		return
	var player = sim.players[0] if not sim.players.is_empty() else null
	if player == null:
		return

	# The rule itself is in scripts/core/campaign.gd, as a function of what is
	# left alive, so it can be tested without playing a stage to its end.
	var outcome := Campaign_.outcome_of(player.alive and not player.dying,
		sim.creature_count(), _campaign_bots_alive())
	if outcome == Campaign_.Outcome.RUNNING:
		return

	_campaign_settled = true
	campaign_score += _stage_score()
	if outcome == Campaign_.Outcome.LOST:
		print("main: campaign over on stage %d/%d — %d points"
			% [campaign_stage + 1, campaign.size(), campaign_score])
		_end_campaign()
		return

	campaign_stage += 1
	if campaign_stage >= campaign.size():
		print("main: campaign complete — %d points" % campaign_score)
		_end_campaign()
		return
	print("main: stage cleared — %d points so far" % campaign_score)
	_start_campaign_stage()


## The stage's own points, VALUELST 1300/1310/1320 by way of the simulation.
func _stage_score() -> int:
	var n := 0
	for i in sim.round_score.size():
		n += sim.round_score[i]
	return n


func _campaign_bots_alive() -> int:
	var n := 0
	for p in sim.players:
		if p.slot == 0 or not p.in_play:
			continue
		if p.alive and not p.dying:
			n += 1
	return n


func _end_campaign() -> void:
	campaign = null
	campaign_stage = 0
	if music != null:
		music.stop()
	# Everything the stage built goes before the screen comes up, or the frame
	# loop keeps ticking a simulation nobody is watching.
	_teardown()
	sim = null
	_open_menu(Screens_.Screen.RESULTS)


## Rebuild the field for the next local round. The scheme is re-parsed from the
## sim's own copy so nothing has to be kept in two places.
func _start_local_round() -> void:
	if stats != null:
		stats.bump(Stats_.C.GAMES_STARTED)
	if music != null:
		music.play_level(the_match.level)
	var seat_slots: Array[int] = []
	for i in _key_slots:
		seat_slots.append(i)
	for i in _pad_slots:
		seat_slots.append(i)
	for i in _ai_slots:
		seat_slots.append(i)
	seat_slots.sort()
	var slots := []
	for i in seat_slots:
		slots.append({"slot": i, "team": _team_for(i)})
	level = the_match.level
	sim.level = level
	sim.team_play = the_match.team_play
	_settings_to(sim)
	# One permutation for the whole match, from the seed it started on.
	sim.start_seed = the_match.first_seed
	sim.setup(_round_scheme(), slots, the_match.round_seed)
	if sfx != null:
		sfx.new_round()
	for i in _ai_slots:
		sim.add_bot(i)
	_grant_the_gold_prize()
	_apply_round_length()
	if view != null:
		view.level = level
		view.sim = sim
		view.the_match = the_match
	print("main: round %d — %s, seed %d" % [the_match.round_index + 1,
		Messages_.LEVEL_NAMES[clampi(level, 0,
			Messages_.LEVEL_NAMES.size() - 1)], the_match.round_seed])


## The scheme this round is laid out from. Held by the sim after the first
## round; the caller supplies it for the first.
var _scheme: Scheme_ = null


func _round_scheme() -> Scheme_:
	if _scheme == null and sim != null:
		_scheme = sim.scheme_used
	return _scheme


## Was the match won by nobody? A draw shows DRAW.PCX rather than a victory
## screen, which is the only thing that distinguishes the two paths.
func _was_draw() -> bool:
	return the_match != null and the_match.champion_slot < 0 \
		and the_match.champion_team < 0


## The Gold Bomberman's reward, handed over at the start of the next match.
##
## OPTIONS.BM: "The Gold Bomberman is a reward given to the winner of the last
## match. The reward consists of a random powerup determined by the roulette
## wheel." So it applies to the FIRST round of the next match and is then spent
## — a reward for every round would be a different game.
func _grant_the_gold_prize() -> void:
	if _gold_powerup < 0 or _gold_slot < 0 or the_match == null:
		return
	if the_match.round_index != 0:
		return
	var p := sim.player_by_slot(_gold_slot)
	if p == null:
		return
	if _gold_powerup == Roulette_.CLOG:
		# The wheel can punish: resource 91 is "how much speed the CLOGS
		# (special roulette power-'down') take away".
		p.speed = maxi(1, p.speed - int(Values_.V[Const_.Res.CLOG_PENALTY]))
		p.speed_before_slow = p.speed
	else:
		sim.give_powerup(p, _gold_powerup)
	print("main: player %d starts with the gold prize" % (_gold_slot + 1))
	_gold_powerup = -1
	_gold_slot = -1


func _apply_round_length() -> void:
	if _round_seconds > 0:
		sim.time_left = _round_seconds * Const_.TICK_HZ


func _on_client_sound(slot: int, effect: int, arg: int) -> void:
	_heard.append({"slot": slot, "effect": effect, "arg": arg})


## A client's round_index/level/seed changed, so its Sim was rebuilt and its
## tick count is back at 0. Sfx outlives every round — see Sfx.new_round() —
## so the mixer's per-round busy-until bookkeeping has to be told the same
## thing the local host path tells it in _start_local_round().
func _on_client_round_started(_round_index: int, _level: int) -> void:
	if sfx != null:
		sfx.new_round()


## Screen pixels to a field cell, inverting Const_.tile_origin(). Out of
## bounds comes back as a cell that fails Field_.in_bounds(), which every
## caller checks before acting on it.
func _editor_tile_at(screen_pos: Vector2) -> Vector2i:
	return Vector2i(
		int(floor((screen_pos.x - Const_.FIELD_X_OFF) / Const_.BLOCK_W)),
		int(floor((screen_pos.y - Const_.FIELD_Y_OFF) / Const_.BLOCK_H)))


## SOLID -> BRICK -> BLANK -> SOLID. Bypasses give_powerup entirely — this is
## for shaping the field itself, not for testing a pickup.
func _editor_cycle_brick(tile: Vector2i) -> void:
	var i := Field_.idx(tile.x, tile.y)
	var next: int = (int(sim.field.brick[i]) + 1) % 3
	sim.field.brick[i] = next
	if next != Types_.Brick.BLANK:
		sim.field.powerup[i] = Field_.NO_POWERUP


## Drops the selected type straight onto the field, visible immediately — no
## brick to break first, which is the point: it is for testing what the
## powerup DOES, not for testing how it is uncovered.
func _editor_place_powerup(tile: Vector2i) -> void:
	var i := Field_.idx(tile.x, tile.y)
	sim.field.brick[i] = Types_.Brick.BLANK
	sim.field.powerup[i] = view.editor_powerup


## A bomb with slot 0's own flame length and jelly flag, fused normally so it
## detonates on its own — the fastest way to see one arm pattern without
## needing a live player to place it.
func _editor_spawn_bomb(tile: Vector2i) -> void:
	if sim.bomb_at(tile.x, tile.y) != null:
		return
	var owner: Player_ = sim.player_by_slot(0)
	var b := Bomb_.new()
	b.x = tile.x * Const_.BLOCK_W * 100 + Const_.BLOCK_W * 50
	b.y = tile.y * Const_.BLOCK_H * 100 + Const_.BLOCK_H * 50
	b.owner = owner.slot if owner != null else 0
	b.chain_owner = b.owner
	b.flame_len = owner.flame_len if owner != null else 1
	b.jelly_bounce = owner.jelly_bombs if owner != null else false
	b.fuze = sim.fuze_ticks()
	b.placed_tick = sim.tick_count
	sim.bombs.append(b)


## The player standing on `tile`, or slot 0 if nobody is — K/D/C need a
## target and the field is usually emptier than the roster.
func _editor_target(tile: Vector2i) -> Player_:
	for p in sim.players:
		if p.in_play and p.tile_x() == tile.x and p.tile_y() == tile.y:
			return p
	return sim.player_by_slot(0)


func _editor_key(keycode: int) -> void:
	match keycode:
		KEY_BRACKETLEFT:
			view.editor_powerup = posmod(view.editor_powerup - 1,
				Const_.POWERUP_COUNT)
		KEY_BRACKETRIGHT:
			view.editor_powerup = posmod(view.editor_powerup + 1,
				Const_.POWERUP_COUNT)
		KEY_B:
			if Field_.in_bounds(view.editor_cursor.x, view.editor_cursor.y):
				_editor_spawn_bomb(view.editor_cursor)
		KEY_K:
			var target := _editor_target(view.editor_cursor)
			if target != null and target.alive and not target.dying:
				sim.kill(target)
		KEY_D:
			var target := _editor_target(view.editor_cursor)
			if target != null:
				sim.give_powerup(target, Types_.PowerUp.DISEASE)
		KEY_C:
			var target := _editor_target(view.editor_cursor)
			if target != null:
				sim.cure_all(target)
		KEY_R:
			sim.field.brick.fill(Types_.Brick.BLANK)
			sim.field.powerup.fill(Field_.NO_POWERUP)


func _input(event: InputEvent) -> void:
	if mode == Mode.MENU:
		_menu_input(event)
		return
	if keys != null:
		keys.handle(event)
	if pads != null:
		pads.handle(event)
	if event is InputEventKey and (event as InputEventKey).pressed:
		var pressed := event as InputEventKey
		match pressed.keycode:
			KEY_ESCAPE:
				# Back to the menu, not out of the program. Quitting is an item
				# on the menu, which is where a player looks for it; a game
				# that exits on Escape loses a match to a mistyped key.
				_open_menu()
			KEY_Q:
				# MANUAL.BM's own key for it: "Ctrl-Q - Quit game in progress;
				# go back to main menu (terminates game completely)". Escape
				# does the same thing and is kept, because a player who does
				# not read the manual presses Escape.
				if pressed.ctrl_pressed:
					_open_menu()
			KEY_F10:
				# "F10 - Forces a draw game." Which ends the round with nobody
				# winning it, exactly as running out of clock does.
				if sim != null and not sim.round_over():
					sim.force_draw()
			KEY_F2:
				# The debug grid. It was on F1, and MANUAL.BM gives F1 to
				# "Help (review help / information files)" — a screen this port
				# does not have in-game, so F1 is left alone rather than given
				# a second meaning.
				if view != null:
					view.show_grid = not view.show_grid
			KEY_T:
				# The test editor — place bricks and powerups, spawn bombs,
				# kill/disease/cure a player, all live, so every mechanic can
				# be exercised without depending on which scheme is loaded.
				# Was F3, which macOS reserves for Mission Control on most
				# keyboards — the OS ate the keystroke before Godot ever saw
				# it, and on the ones where it didn't, whatever ran it next
				# still had a phantom Mission Control invocation to clean up.
				# A plain letter has no such collision.
				if view != null:
					view.editor_active = not view.editor_active
			KEY_F11:
				_toggle_fullscreen()
			KEY_F5:
				# Replay the same round from the top — useful when watching a
				# specific layout.
				if mode == Mode.LOCAL and the_match != null:
					_start_local_round()
			KEY_N:
				# "Alt-N - dump out the networking statistics (NETSTATS.TXT)".
				# MANUAL.BM. Only meaningful with a network session actually
				# running; a local game writes what it can — that there is
				# none — rather than staying silent about the key doing
				# nothing.
				if pressed.alt_pressed:
					_write_netstats()
			KEY_D:
				# "Alt-D - display the misc info screen (use it VERY
				# sparingly when network play is going on... it will affect
				# synchronization!)". MANUAL.BM names the key and the warning
				# but not the screen's actual content — nothing on the disc
				# does. What IS known and safe to show without touching the
				# simulation (the warning is exactly why nothing here reads
				# or writes sim state) is everything else this build already
				# knows about itself: mode, tick, level, player count.
				if pressed.alt_pressed:
					_print_misc_info()
		if view != null and view.editor_active:
			_editor_key(pressed.keycode)
	if view != null and view.editor_active and sim != null:
		if event is InputEventMouseMotion:
			view.editor_cursor = _editor_tile_at(
				(event as InputEventMouseMotion).position)
		elif event is InputEventMouseButton \
				and (event as InputEventMouseButton).pressed:
			var click := event as InputEventMouseButton
			var tile := _editor_tile_at(click.position)
			if Field_.in_bounds(tile.x, tile.y):
				if click.button_index == MOUSE_BUTTON_LEFT:
					_editor_cycle_brick(tile)
				elif click.button_index == MOUSE_BUTTON_RIGHT:
					_editor_place_powerup(tile)
				elif click.button_index == MOUSE_BUTTON_MIDDLE:
					_editor_spawn_bomb(tile)


## The screens' keys.
##
## Which screen is up decides what a key does; the model decides what that
## means, and this only translates. Up/down and left/right everywhere, Return
## to choose, Escape to back out, F11 for fullscreen — the same four the game
## uses, so nothing has to be learned twice.
func _menu_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not (event as InputEventKey).pressed:
		return
	var key := event as InputEventKey

	# The title takes ANY key, which is what "Press any key" means. Escape and
	# F11 keep their meanings so a mistyped key cannot trap anybody there.
	if screens != null and screens.screen == Screens_.Screen.TITLE:
		match key.keycode:
			KEY_ESCAPE:
				_quit(0)
			KEY_F11:
				_toggle_fullscreen()
			_:
				screens.activate()
		if menu_view != null:
			menu_view.queue_redraw()
		return

	var on_options: bool = screens != null \
		and screens.screen == Screens_.Screen.OPTIONS
	var on_setup: bool = screens != null \
		and screens.screen == Screens_.Screen.SETUP

	# The keyboard-definitions screen swallows the keyboard while it is waiting
	# for one — otherwise the arrow keys could never be rebound, because they
	# would move the cursor instead. MESSAGES.TXT 1105 is the prompt it shows.
	if (on_options or on_setup) and menu != null and menu.in_keys \
			and menu.awaiting_key >= 0:
		menu.take_key(key.keycode)
		if menu_view != null:
			menu_view.queue_redraw()
		return

	# CTRL-A BEFORE THE MATCH BELOW, because `KEY_LEFT, KEY_A` is one of its
	# arms — A is the menu's alias for "left" — and a match takes the first arm
	# that fits. Written as a case of its own it was dead code.
	#
	# MANUAL.BM: "Ctrl-A - Set all players to AI in the controller setup screen
	# (won't work in network play!)".
	if on_setup and menu != null and key.ctrl_pressed \
			and key.keycode == KEY_A:
		var to_ai := menu.all_to_ai()
		menu.refusal = "%d player%s set to AI" % [to_ai,
			"" if to_ai == 1 else "s"]
		if menu_view != null:
			menu_view.queue_redraw()
		return

	match key.keycode:
		KEY_UP, KEY_W:
			if on_options or on_setup:
				menu.move(-1)
			elif _on_text_page():
				_scroll_page(-1)
			elif screens != null:
				screens.move(-1)
		KEY_DOWN, KEY_S:
			if on_options or on_setup:
				menu.move(1)
			elif _on_text_page():
				_scroll_page(1)
			elif screens != null:
				screens.move(1)
		KEY_LEFT, KEY_A:
			if on_options or on_setup:
				menu.adjust(-1)
			elif screens != null \
					and screens.cursor == Screens_.Menu.JOIN_NETWORK:
				screens.net_cursor = maxi(screens.net_cursor - 1, 0)
		KEY_RIGHT, KEY_D:
			if on_options or on_setup:
				menu.adjust(1)
			elif screens != null \
					and screens.cursor == Screens_.Menu.JOIN_NETWORK:
				screens.net_cursor = mini(screens.net_cursor + 1,
					maxi(screens.net_games.size() - 1, 0))
		KEY_T:
			# INPUT.BM: "To toggle which team a player is on, press 'T'. You
			# need to have team play enabled (from the options screen) for this
			# feature to work." The port had no way to change a team at all.
			if on_setup and menu != null:
				if not menu.toggle_team():
					menu.refusal = "turn Team Play on first"
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			if (on_options or on_setup) and menu.in_keys:
				menu.activate()
			elif on_setup:
				# "Return to start" — the setup screen says so itself, at the
				# bottom of scripts/render/screen_view.gd's own drawing. It
				# used to call menu.adjust(1) here, which cycled the slot under
				# the cursor instead, so the game could not be started from
				# this screen at all. Left/right changes a slot; Return starts.
				_start_from_menu()
				return
			elif on_options:
				# The settings list: Return acts on the row it is on, which is
				# how "Define keyboard layouts" opens.
				match menu.activate():
					Menu_.Action.START, Menu_.Action.HOST:
						_start_from_menu()
						return
					Menu_.Action.QUIT:
						_quit(0)
						return
			elif screens != null and screens.screen \
					== Screens_.Screen.ROULETTE and roulette != null \
					and not roulette.finished():
				# Return while it spins takes whatever is under the pointer,
				# for somebody who does not want to watch five seconds of
				# twinkling.
				roulette.skip()
				_take_the_prize()
			elif screens != null:
				var was_screen := screens.screen
				match screens.activate():
					Screens_.Action.OPEN_SETUP:
						_prepare_setup(false)
					Screens_.Action.HOST:
						_prepare_setup(true)
					Screens_.Action.OPEN_OPTIONS:
						# The settings list, which is not the slots. Leaving
						# the flag set here highlighted nothing on it, because
						# the list dims every row while the cursor is "in" a
						# screen the list does not draw.
						_prepare_options()
					Screens_.Action.JOIN:
						_join_from_screen()
						return
					Screens_.Action.QUIT:
						_quit(0)
						return
				if screens.screen == Screens_.Screen.ROULETTE \
						and was_screen != Screens_.Screen.ROULETTE:
					_start_the_wheel()
		KEY_PAGEUP:
			# 390 lines of MANUAL.BM at one line a press is not reading.
			if _on_text_page():
				_scroll_page(-ScreenView.page_rows())
		KEY_PAGEDOWN:
			if _on_text_page():
				_scroll_page(ScreenView.page_rows())
		KEY_F11:
			_toggle_fullscreen()
		KEY_ESCAPE:
			if (on_options or on_setup) and menu != null and menu.leave_keys():
				# Escape left the keyboard-definitions screen, not the options
				# screen. leave_keys() saves whatever was bound.
				pass
			elif on_options or on_setup:
				# Both screens back out to the main menu. Escape on the setup
				# screen used to call leave_slots() instead, which left the
				# screen up with its cursor taken out of the slots — ten player
				# rows and none of them selected, and up/down walking a
				# settings list that screen does not draw.
				if menu != null:
					menu.in_slots = false
				screens.to_screen(Screens_.Screen.MAIN_MENU)
			elif screens != null:
				if screens.back() == Screens_.Action.QUIT:
					_quit(0)
					return
		_:
			return
	if menu_view != null:
		menu_view.queue_redraw()


## Spin the wheel for the player who just won the match.
##
## Seeded from the match, so the same match awards the same prize on a replay —
## the wheel is presentation, but a reward that carries into the next match is
## not, and a game that replays differently from its own seed is not
## reproducible.
func _start_the_wheel() -> void:
	roulette = Roulette_.new()
	var slot := the_match.champion_slot if the_match != null else 0
	var from_seed: int = the_match.round_seed if the_match != null else 1
	roulette.start(slot, from_seed ^ 0x901D)
	if menu_view != null:
		menu_view.roulette = roulette


## Keep what the wheel landed on, for the next match.
func _take_the_prize() -> void:
	if roulette == null or roulette.result < 0:
		return
	_gold_slot = roulette.slot
	_gold_powerup = roulette.result
	var name := "?"
	if _gold_powerup < Messages_.POWERUP_SHORT.size():
		name = String(Messages_.POWERUP_SHORT[_gold_powerup])
	print("main: the gold player is %d and has %s for the next match"
		% [_gold_slot + 1, name])


## Entering the setup screen. `hosting` is Start Network Game rather than Start
## Game; the setup is the same either way and only Return differs.
func _prepare_setup(hosting: bool) -> void:
	_hosting_from_menu = hosting
	# The SETUP screen IS the ten slots — "Who is playing" — so the cursor
	# starts in them. The settings list is a different screen (OPTIONS).
	menu.in_slots = true
	menu.in_keys = false
	menu.slot_cursor = 0


## The OPTIONS screen: the settings list, and never the slots.
func _prepare_options() -> void:
	if menu == null:
		return
	menu.in_slots = false
	menu.in_keys = false
	if menu.selected() == Menu_.Item.SLOTS:
		menu.cursor = Menu_.Item.SCHEME


## Join whatever --join or the browser's ?join= named. The screen refuses
## before reaching here when there is nothing to join.
## Which of the disc's screen tracks belongs to a screen, or "" for the ones it
## does not name (About, the Manual and the roulette keep whatever is playing).
static func _screen_track(screen: int) -> String:
	match screen:
		Screens_.Screen.TITLE:
			return "title"
		Screens_.Screen.MAIN_MENU:
			return "menu"
		Screens_.Screen.SETUP, Screens_.Screen.OPTIONS:
			return "setup"
		Screens_.Screen.RESULTS, Screens_.Screen.VICTORY:
			return "gameover"
		Screens_.Screen.DRAW:
			return "draw"
	return ""


## About Bomberman and the Online Manual are pages of the disc's own text, long
## enough to need scrolling; up and down move them rather than a cursor.
func _on_text_page() -> bool:
	return screens != null and (screens.screen == Screens_.Screen.ABOUT
		or screens.screen == Screens_.Screen.MANUAL)


## Scroll About Bomberman or the Online Manual, clamped to their own length.
## The view knows how many lines the page has; the model does the clamping.
func _scroll_page(delta: int) -> void:
	if screens == null or menu_view == null:
		return
	screens.scroll_text(delta, menu_view.page_line_count(),
		ScreenView.page_rows())


## The games heard on the LAN, newest list each call. Used by the join screen
## and by nothing else.
func net_games() -> Array:
	return lan.games() if lan != null else []


func _join_from_screen() -> void:
	if screens == null or screens.join_url.is_empty():
		return
	var url := screens.join_url
	_teardown()
	var args := _args.duplicate()
	args["join"] = url
	_start_from_args(args)


func _notification(what: int) -> void:
	# A window that loses focus with a key held would otherwise keep walking.
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		if keys != null:
			keys.release_all()
		if pads != null:
			pads.release_all()
	# The original writes its statistics once, on the way out. This covers the
	# window's own close button, which does not go through _quit().
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_EXIT_TREE:
		_save_stats()


## The one way out. Every exit path writes the statistics file first, because
## a notification is not raised for all of them — a window closed with its own
## button and a quit() from the menu do not agree, and a process killed from
## outside raises nothing at all. save() only accumulates once, so the paths
## that reach here twice are harmless.
func _quit(code: int) -> void:
	_save_stats()
	get_tree().quit(code)


func _save_stats() -> void:
	if stats != null:
		stats.save(_stats_dat, _stats_txt)


func _capture(path: String) -> void:
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(path)
	if err != OK:
		push_error("could not write %s (%d)" % [path, err])
	else:
		# In client mode there is no local simulation, so report the server's
		# tick — which is the tick the frame actually shows.
		var at: int = client.server_tick if client != null \
			else (sim.tick_count if sim != null else 0)
		if mode == Mode.MENU and screens != null:
			at = screens.age
			print("main: wrote %s at screen tick %d (screen %d%s)"
				% [path, at, screens.screen,
					", wheel age %d result %d" % [roulette.age, roulette.result]
						if roulette != null else ""])
			return
		print("main: wrote %s at tick %d" % [path, at])
