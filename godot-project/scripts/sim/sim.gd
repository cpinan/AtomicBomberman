# The authoritative simulation. No rendering, no scene tree, no clock.
#
# ---------------------------------------------------------------------------
# Two decisions govern everything in this file.
# ---------------------------------------------------------------------------
#
# 1. 20 Hz, fixed. VALUELST resource 30 is the rate the game attempts and
#    resource 25 is the rate every frame-count in the tuning table is expressed
#    against; both are 20. So one tick is 50 ms and a "frames" value from the
#    table IS a tick count — a 40-frame fuze is 40 ticks, and no conversion
#    exists to get wrong. fpc_atomic simulates at 100 Hz; that is its own
#    invention. docs/ORACLE.md section 1.
#
# 2. Integers only. Position is in centipixels — hundredths of a pixel — which
#    is the unit the tuning table already uses for speed. A tick is therefore
#    `x += speed`, one integer add, with no rounding and no drift. There is not
#    a single float in the simulation.
#
#    This is not fastidiousness. Phase 5 broadcasts state 50 times a second and
#    asserts every client's state_hash() matches the server's; Track C diffs
#    this engine against a C oracle tick by tick. Both of those are exact-match
#    tests, and a float sim would fail them for reasons that have nothing to do
#    with the game.
#
# tick() takes no delta and reads no clock, so a test can step it 40 times and
# assert on tick 40. advance() is the only thing that knows about wall time.
extends RefCounted

const Const_ := preload("res://scripts/core/const.gd")
const Types_ := preload("res://scripts/core/types.gd")
const Values_ := preload("res://scripts/core/values.gd")
const Field_ := preload("res://scripts/sim/field.gd")
const Player_ := preload("res://scripts/sim/player.gd")
const Bomb_ := preload("res://scripts/sim/bomb.gd")
const Ai_ := preload("res://scripts/sim/ai.gd")
const Stats_ := preload("res://scripts/core/stats.gd")
const Creature_ := preload("res://scripts/sim/creature.gd")

const CP := Player_.CP
const TILE_W_CP := Player_.TILE_W_CP
const TILE_H_CP := Player_.TILE_H_CP

## How many death animations the disc has — VALUELST 105, and the seventeen
## XPLODE files hold exactly that many named sequences.
const DEATH_ANIMS := 24

## How long the kicking animation is held for, in ticks. KICK.ANI has four
## frames per direction and the disc states no duration, so this is the port's.
const KICK_ANIM_TICKS := 6

## And for PUNCH.ANI, which has ten frames per direction. Same reasoning: the
## disc states no duration, so this is the port's, and it is long enough for
## the swing to read at 20 Hz.
const PUNCH_ANIM_TICKS := 8

## How long a cornerhead animation plays, in ticks. `0x41F29B` advances its
## own frame counter on a real-time sub-loop and resets once it exceeds 8 —
## nine steps — but that inner loop runs against the original's own frame
## clock, not this port's 20 Hz tick, so nine STEPS is read; nine TICKS is
## this port's own translation of it, same reasoning as KICK_ANIM_TICKS.
const CORNERHEAD_TICKS := 9

## How long a killed player stays on the field before it is gone, in ticks.
##
## The disc gives no such value. fpc_atomic does — `AtomicDieTimeout = 5000`,
## "the time in ms that is waited until the game ends after the last dying
## player" — and 5 s is 100 ticks, which is also longer than the longest death
## animation the disc ships (XPLODE4's "die green 4", 93 steps). So every one
## of the 24 gets to finish, and then the body is gone rather than lying there
## for the rest of the round with a shadow under it.
const DEATH_TICKS := 100

## At most one bomb per cell, so the field size is also the hard cap.
const MAX_BOMBS := Const_.FIELD_W * Const_.FIELD_H

var field: Field_ = null
var players: Array = []
var bombs: Array = []

var tick_count: int = 0

## Ticks left in the round. Resource 100 gives the default length in seconds
## (150) and the round ends when this reaches zero even if players survive.
var time_left: int = 0

## How far the closing wall has advanced, or -1 when Hurry is not running.
## Resource 101 starts Hurry at 60 seconds remaining and its comment says not
## to change that value.
var hurry_index: int = -1

## Set once the round is over, with why. The caller reads this and moves on;
## the simulation keeps ticking so death animations can finish.
enum Outcome { RUNNING, LAST_STANDING, DRAW, TIME_UP }
var outcome: int = Outcome.RUNNING
var winner_slot: int = -1
var winner_team: int = Types_.TEAM_UNSET

## Ticks since the round ended, so the caller knows when the animations are
## done. fpc_atomic waits 5 s; the original has no resource for it, so the
## caller decides.
var ticks_since_over: int = 0

## True when teams are being scored rather than individuals.
var team_play: bool = false

## Seeded explicitly so a round is reproducible from its seed alone. Godot's
## RandomNumberGenerator is PCG32 and gives the same stream everywhere, which
## is what makes the server's layout reproducible on a client for replay.
var rng := RandomNumberGenerator.new()
var seed_used: int = 0

# Values read once at setup rather than per tick. They cannot change during a
# round, and re-reading a Dictionary 20 times a second for a constant is waste.
var _fuze_ticks: int = 0
var _flame_ticks: int = 0
var _brick_ticks: int = 0

var _accum_ms: int = 0

## Cells that have had a bomb detonate on them this tick, so the chain
## resolution pass cannot loop.
var _pending: Array[int] = []

## "you are now AWESOME (7th powerup and 3rd thereafter)" — SOUNDLST's own
## description of its 1400..1699 range, and the only statement anywhere on the
## disc about when that sound plays. There is no VALUELST resource for either
## number, so they live here rather than in a generated table.
const AWESOME_AT := 7
const AWESOME_EVERY := 3

## The scheme this round was laid out from. See setup().
var scheme_used: RefCounted = null

## Sound events raised this tick, as {"slot": int, "effect": Types.SoundEffect}.
## The simulation never plays anything — it records what happened, the renderer
## plays it, and Phase 5 puts the same list on the wire. Cleared every tick, so
## a client that misses one has simply missed it, which is correct: a sound is
## not state.
var sounds: Array[Dictionary] = []


## Raise a sound event. `arg` carries whatever the effect needs to name a
## specific sound — for DISEASE_CAUGHT it is the disease, because SOUNDLST has
## twelve per-disease ranges at 3000 + 50*i and the generic one is a fallback.
func _play(slot: int, effect: int, arg: int = 0) -> void:
	sounds.append({"slot": slot, "effect": effect, "arg": arg})


## Start a round. `slots` is an array of {"slot": int, "team": int} naming who
## is playing; their start cells come from the scheme.
## Which slots are played by a bot. A bot decides its own input at the top of
## every tick, from the simulation's own state and the seeded RNG — so a bot
## game replays exactly like any other, and a client watching one sees the same
## thing the server does without the bots being simulated twice.
var bot_slots: Dictionary = {}
var _ai: Ai_ = null

## The statistics counters, or null. Deliberately NOT part of the simulation's
## state: nothing here is hashed, snapshotted or sent, so a client counting its
## own bombs cannot make its state hash differ from the server's. The original
## counted what the machine in front of the player did, and so does this.
var stats = null

## Random Start — MESSAGES.TXT 251, and OPTIONS.BM: "player start positions
## will be randomized at the beginning of the match". The permutation is drawn
## from start_seed rather than from this round's seed, so it is the MATCH that
## is randomised and not each round; the caller sets start_seed once, from the
## match's first seed. A separate generator, not this simulation's `rng`,
## because drawing from that one would move the layout and the powerup scatter
## along with the positions.
##
## OPTIONS.BM also says a team scheme should be played with this off. It is the
## player's choice, so nothing here refuses it.
##
## The DEFAULT is the disc's, and it is ON: VALUELST resource 40 is "default
## value of \"do we randomize player starting positions?\"" and it is 1.
## The field is initialised from the resource, so a caller that says nothing
## gets the original's behaviour rather than this file's.
var random_start: bool = Values_.V[Const_.Res.RANDOM_START] != 0
var start_seed: int = 0

## Kills this round, per slot, for the Win Matches By Kill Total option
## (MESSAGES.TXT 255). Net of suicides: OPTIONS.BM says "if you kill yourself
## with your own bomb, your kill count will go down by 1", so it can go
## negative. Not part of state_hash() and not snapshotted — the server owns the
## win condition, and a client only ever needs to be told who won.
var round_kills: PackedInt32Array = PackedInt32Array()

## Campaign mode's rovers and ghosts. Empty in every ordinary round, which is
## why nothing else in this file has to know about them. scripts/sim/creature.gd
## says where they come from and what had to be decided.
var creatures: Array = []

## Points scored this round, per slot — VALUELST 1300/1310/1320, and campaign
## mode is the only thing that reads it.
var round_score: PackedInt32Array = PackedInt32Array()


func add_bot(slot: int) -> void:
	bot_slots[slot] = true
	if _ai == null:
		_ai = Ai_.new()
	var p := player_by_slot(slot)
	if p != null:
		p.in_play = true
		p.alive = true


func is_bot(slot: int) -> bool:
	return bot_slots.has(slot)


func bot_count() -> int:
	return bot_slots.size()


## Which level's specials this round uses. Set before setup(); the client gets
## it in its welcome so both sides build identical geometry.
var level: int = 0


func setup(scheme: RefCounted, slots: Array, round_seed: int = 0) -> void:
	# Kept so a second round can be laid out without the caller having to hold
	# the scheme too. Not simulation state: it never enters state_hash() and
	# never travels — the scheme's TEXT is what the wire carries.
	scheme_used = scheme
	seed_used = round_seed
	_apply_defaults()
	_hurry_path_cache = []
	rng.seed = round_seed
	tick_count = 0
	_accum_ms = 0
	time_left = Values_.V[Const_.Res.ROUND_SECONDS] * Const_.TICK_HZ
	hurry_index = -1
	outcome = Outcome.RUNNING
	winner_slot = -1
	winner_team = Types_.TEAM_UNSET
	ticks_since_over = 0
	bombs = []
	players = []
	creatures = []
	round_kills = PackedInt32Array()
	round_kills.resize(Const_.PLAYER_COUNT)
	round_score = PackedInt32Array()
	round_score.resize(Const_.PLAYER_COUNT)

	_fuze_ticks = Values_.V[Const_.Res.FUZE_FRAMES]
	_flame_ticks = Values_.V[Const_.Res.FLAME_ANIM_FRAMES]
	_brick_ticks = Values_.V[Const_.Res.BRICK_ANIM_FRAMES]

	# Random Start permutes which start cell each playing slot gets. Positions
	# only: a slot keeps its own team, so a team game stays two teams however
	# the corners are dealt out.
	var start_order := []
	for i in slots.size():
		start_order.append(i)
	if random_start and slots.size() > 1:
		var srng := RandomNumberGenerator.new()
		srng.seed = start_seed ^ 0x57A27
		for i in range(start_order.size() - 1, 0, -1):
			var j := srng.randi_range(0, i)
			var swap = start_order[i]
			start_order[i] = start_order[j]
			start_order[j] = swap

	var start_cells := []
	var entry_index := -1
	for entry in slots:
		entry_index += 1
		var slot: int = entry["slot"]
		# The cell this slot starts on, which Random Start may have dealt to
		# somebody else; and the slot's OWN scheme row, which is where a team
		# comes from when the caller did not name one. Keeping them apart is
		# what stops a shuffle from also shuffling the teams.
		var start: Dictionary = scheme.starts[
			slots[start_order[entry_index]]["slot"]]
		var own: Dictionary = scheme.starts[slot]
		var p: Player_ = Player_.new()
		p.slot = slot
		p.team = entry.get("team", own.get("team", Types_.TEAM_UNSET))
		p.speed = Values_.V[Const_.Res.START_SPEED]
		p.speed_before_slow = p.speed
		p.flame_len = Values_.V[Const_.Res.BORN_WITH_BASE + Types_.PowerUp.FLAME]
		p.bombs_available = Values_.V[Const_.Res.BORN_WITH_BASE + Types_.PowerUp.BOMB]
		p.bombs_total = p.bombs_available
		# On top of the VALUELST loadout, the scheme's -P rows can grant
		# powerups at birth. AtomBomberman's notes on the format: "bornwith -
		# how many has at start (doesnt include the default 1 bomb & 2 flames)",
		# so these ADD to the table's defaults rather than replacing them.
		for which in Const_.POWERUP_COUNT:
			var row: Dictionary = scheme.powerups[which]
			for _n in int(row.get("born_with", 0)):
				give_powerup(p, which)
		p.place_at_tile_centre(start["x"], start["y"])
		players.append(p)
		start_cells.append({"x": start["x"], "y": start["y"]})

	field = Field_.new()
	field.initialize(scheme, start_cells, rng)
	# The level's arrows, conveyors, warps and trampolines. Built here from the
	# level number and the seed, on the server and on every client alike, so
	# they never travel on the wire — see field.gd's plane declarations.
	field.load_extras(level, start_cells, rng)


## The tuning-table durations this round is running with. Exposed so the
## renderer can drive an animation's progress from the same numbers the
## simulation times it with, rather than keeping a second copy.
func flame_ticks() -> int:
	return _flame_ticks


func brick_anim_ticks() -> int:
	return _brick_ticks


func fuze_ticks() -> int:
	return _fuze_ticks


func set_input(slot: int, move: int, action: int = Types_.Action.NONE,
		first_held: bool = false) -> void:
	var p := player_by_slot(slot)
	if p == null:
		return
	# A DEAD PLAYER TAKES NO INPUT. kill() sets move to STILL, and this used to
	# hand it back on the very next tick, because main.gd calls this once per
	# tick for every keyset whatever is happening on the field. The simulation
	# ignores a dying player's move, so nothing walked — but the VIEW picks the
	# walk sheet whenever move is not STILL, so a corpse jogged on the spot for
	# as long as the key was held. That is "the player still moves".
	if not p.alive or p.dying:
		return
	p.move = move
	p.action = action
	p.action_first_held = first_held


func player_by_slot(slot: int) -> Player_:
	for p in players:
		if p.slot == slot:
			return p
	return null


func living_players() -> int:
	var n := 0
	for p in players:
		if p.alive and not p.dying:
			n += 1
	return n


## Advance by wall-clock milliseconds, running whole ticks only and keeping the
## remainder. Returns how many ticks ran.
##
## A single call is clamped to resource 31 — 150 ms, which is 3 ticks. The
## original's comment on that value says why:
##
##     what is the maximum milliseconds the game can advance in any given
##     "frame."  this prevents a disk hit from moving everybody a whole
##     huge distance on the screen and screwing things up.
##
## Time beyond the clamp is DISCARDED, not banked. Banking it would reproduce
## the stall on the next call and turn one hitch into a cascade.
func advance(delta_ms: int) -> int:
	var budget: int = mini(delta_ms, Values_.V[Const_.Res.MAX_ADVANCE_MS])
	_accum_ms += budget
	var ran := 0
	while _accum_ms >= Const_.TICK_MS:
		_accum_ms -= Const_.TICK_MS
		tick()
		ran += 1
	return ran


## Exactly one 50 ms step.
##
## Order matters and is the same order fpc_atomic's CreateNewFrame uses, because
## it is the order the effects depend on: a player must move before we ask
## whether they walked into a flame, and bombs must be resolved before the
## flames they created are aged.
func tick() -> void:
	tick_count += 1
	sounds.clear()

	# Bots choose their input first, so the rest of the tick cannot tell a bot
	# from a human. Their decisions read only committed state and the seeded
	# RNG, which is what keeps a bot round reproducible.
	if _ai != null:
		for p in players:
			if not bot_slots.has(p.slot):
				continue
			if not p.in_play or not p.alive or p.dying:
				continue
			var choice := _ai.think(self, p)
			p.move = int(choice["move"])
			p.action = int(choice["action"])

	# Age LAST tick's flames and animations before this tick's logic, never
	# after it. Ageing at the end would decrement a flame on the very tick it
	# was created, so resource 10's "10 frames" would burn for nine ticks. The
	# durations in the tuning table are the whole point of matching the
	# original's 20 Hz, and an off-by-one here quietly discards that.
	field.tick_timers()

	for p in players:
		if p.alive and not p.dying:
			if p.kick_ticks > 0:
				p.kick_ticks -= 1
			if p.punch_ticks > 0:
				p.punch_ticks -= 1
			# Resource 665's pickup freeze ages here rather than inside
			# _move_player(), which never sees a player who is standing
			# still — see the comment on its own pickup_pause check.
			if p.pickup_pause > 0:
				p.pickup_pause -= 1
			_move_player(p)

	# The field acting on the players, after they have moved: a conveyor
	# carries whoever ENDED the tick on it, and a gate takes whoever stepped
	# onto it.
	for p in players:
		if p.alive and not p.dying:
			_field_vs_player(p)

	for p in players:
		if p.alive and not p.dying:
			# POOPS: "places bombs constantly, whether you want to or not"
			# (types.gd's own comment on the enum). fpc_atomic's `dEbola` —
			# its own name for this disease, cross-referenced in docs/BUGS.md
			# Q1 — forces `Action := aaFirst` every tick regardless of the
			# player's real input, unconditionally overwriting it; matched
			# here rather than only firing when the player did nothing, since
			# that override is the one piece of ground truth this has.
			if p.has_disease(Types_.Disease.POOPS):
				p.action = Types_.Action.FIRST
			_player_action(p)
			_check_hold_to_carry(p)

	# Collection happens after movement: stepping onto a powerup this tick
	# picks it up this tick.
	for p in players:
		if p.alive and not p.dying:
			_collect_powerup(p)

	_move_bombs()
	_tick_bombs()

	# CONTAGION: a disease passes from body to body on contact. MANUAL.BM only
	# spells this out from the player's side — "Good disease strategies often
	# involve passing the disease to as many opponents as possible. Good
	# diseases to do this with are: Short Fuze, Reverse Controls, Poops, and
	# Short Flame" — but that is enough, and VALUELST backs it with two
	# resources that exist for nothing else: DISEASE_FRESHNESS, "frames before
	# it can pass again", and DISEASE_MULTIPLIES, whether the giver keeps it.
	#
	# spread_disease() below was written for this and then never called from
	# anywhere but its own test, so in a real match a disease could only ever
	# be caught off a skull on the field and never off another player. Both
	# halves of the mechanic — the strategy the manual names and the reason a
	# skull is worth running away from — were missing.
	#
	# After movement, so it reads the tile each player actually ended the tick
	# on. Both directions are tried on a meeting: two diseased players trade
	# whatever the other does not already have. catch_disease() zeroes the
	# receiver's freshness, so nothing bounces straight back in the same tick.
	for giver in players:
		if not giver.alive or giver.dying or not giver.any_disease():
			continue
		for taker in players:
			if taker == giver or not taker.alive or taker.dying:
				continue
			if giver.tile_x() != taker.tile_x() \
					or giver.tile_y() != taker.tile_y():
				continue
			spread_disease(giver, taker)

	# After movement and after this tick's flames exist, so a player who walks
	# into a standing flame and a player this tick's blast reaches both die on
	# the same tick.
	for p in players:
		if p.alive and not p.dying:
			_check_flame_death(p)

	# After movement resolves, so this reads the tile the player actually
	# ended the tick on — the same order `0x41F29B` reads it in.
	for p in players:
		if p.alive and not p.dying:
			_check_cornerhead(p)

	# The campaign's monsters move after the players and before the round is
	# judged: a rover that walks onto a player kills them this tick, and a
	# ghost caught by this tick's flame dies on it.
	if not creatures.is_empty():
		_tick_creatures()

	_tick_diseases()
	_tick_field()
	_tick_round()


# ---------------------------------------------------------------------------
# Movement
# ---------------------------------------------------------------------------
#
# ASSUMED ALGORITHM — docs/BUGS.md Q5.1. The original's speed is known
# (resource 42) but its corner-rounding rule is not, and it cannot be inferred
# from a speed: the original moves in pixels on 40x36 cells, so the same speed
# crosses a row faster than a column (ORACLE row 2). Settling this needs BM.EXE.
#
# What is implemented, and why each part:
#
#   One axis at a time. AtomBomberman's notes: "bomberman can only move in one
#   direction at a time". The input layer picks the direction; this only ever
#   sees one.
#
#   A cell-sized collision box centred on the player. The box spans one cell,
#   so movement stops when the box would overlap a blocked cell — which puts
#   the player's centre at the centre of the last open cell. In an open
#   corridor there is no constraint at all, so movement is free until the wall.
#   This has no invented constants in it, which is the reason for choosing it:
#   a radius or a margin would be a number the oracle cannot check.
#
#   Cross-axis re-centring, by up to `speed` per tick. The notes again: "the
#   game corrects the position itself i guess to help the player". Without it a
#   player who is a few centipixels off-centre is blocked by walls they are
#   visually clear of.
func _move_player(p: Player_) -> void:
	if p.move == Types_.MoveState.STILL:
		return

	# CONTROLS_REVERSED flips the input before anything acts on it, so every
	# consequence — facing, kicking, where a bomb is thrown — is reversed too.
	var move := p.move
	if p.has_disease(Types_.Disease.CONTROLS_REVERSED):
		move = _reverse_move(move)

	var dir := _move_to_dir(move)
	p.facing = dir
	var step: Vector2i = Types_.DIR_VEC[dir]

	# Resource 665: the player is frozen for 2 frames after picking a bomb up.
	# The COUNTDOWN is tick()'s, next to kick_ticks and punch_ticks, not here:
	# this function returns early for a player who is standing still, so a
	# player who grabbed a bomb and then did not walk never aged the pause out.
	# It stuck at 2 forever, and the view draws BPICKUP.ANI's pickup pose for
	# as long as it is above zero — ahead of the carrying pose — while
	# draw_bombs_of() skips a carried bomb entirely. A standing grab therefore
	# made the bomb vanish and left the player frozen mid-pickup, which is
	# exactly what "the blue glove does nothing" looks like.
	if p.pickup_pause > 0:
		return

	var was := Vector2i(p.x, p.y)
	# Where a completely free step would have put them, kept so the kick test
	# below can ask whether anything capped it.
	var want := Vector2i(p.x, p.y)
	if step.x != 0:
		_recentre_y(p)
		want.x = p.x + step.x * p.speed
		p.x = _slide_x(p, step.x * p.speed)
	else:
		_recentre_x(p)
		want.y = p.y + step.y * p.speed
		p.y = _slide_y(p, step.y * p.speed)

	# WALKING INTO A BOMB KICKS IT — on contact, after the move, not before it.
	# MANUAL.BM: "Allows you to kick any bomb down a hallway."
	#
	# This used to run BEFORE the slide, on nothing but "a bomb is in the cell
	# I face". Turning to face a bomb is what sets p.facing, so the kick fired
	# on the first tick of the direction key with the player still at the
	# centre of their own cell, a full cell clear of the bomb: the bomb shot
	# off before it could be touched. Worse, it made the other two gloves
	# unreachable for anyone also holding the kicker — you cannot punch or grab
	# a bomb in front of you if facing it is enough to kick it away, and facing
	# it is the only way to aim either one.
	#
	# The slide above stops the player flush against whatever blocked them, so
	# "the step came up short" AND "a bomb is the thing ahead" is the contact
	# the manual means. A wall stops the step too, which is why the bomb lookup
	# still has to agree before anything is kicked.
	if p.can_kick:
		var capped: bool = p.x != want.x if step.x != 0 else p.y != want.y
		if capped:
			var ahead := bomb_at(p.tile_x() + step.x, p.tile_y() + step.y)
			# THE CELL BEYOND THE BOMB MUST BE FREE — BM95.EXE 0x41EEAC.
			#
			# The original computes the bomb's cell plus the same direction
			# again and calls its "is this cell free" predicate (0x41E5C3: no
			# bomb there AND the cell itself empty) before kicking. A bomb
			# with a wall, a brick or another bomb directly behind it is NOT
			# kicked — the player is simply blocked by it.
			#
			# This port kicked regardless, which cost two things. A bomb
			# against a wall played the kick sound and animation over a bomb
			# that could not move, and — because aiming a glove means facing
			# the bomb — it took away the one situation in which the Boxing
			# Glove is reachable for a player who also holds the kicker. That
			# situation is MANUAL.BM's own Wallybomb advice: "Throw and punch
			# your bombs over the wall."
			var beyond_x: int = p.tile_x() + step.x * 2
			var beyond_y: int = p.tile_y() + step.y * 2
			if ahead != null and Field_.in_bounds(beyond_x, beyond_y) \
					and not _player_blocked(beyond_x, beyond_y):
				kick_bomb(p)
	if stats != null:
		# Both axes, because re-centring moves the other one. Counter 918 is
		# "Total Pixel Distances Run" and re-centring is running.
		stats.add_distance_cp(absi(p.x - was.x) + absi(p.y - was.y))


func _recentre_x(p: Player_) -> void:
	var off := p.offset_x()
	if off == 0:
		return
	var pull: int = mini(absi(off), p.speed)
	p.x -= pull if off > 0 else -pull


func _recentre_y(p: Player_) -> void:
	var off := p.offset_y()
	if off == 0:
		return
	var pull: int = mini(absi(off), p.speed)
	p.y -= pull if off > 0 else -pull


## Move horizontally as far as the cell-sized box allows, and return the new x.
func _slide_x(p: Player_, delta: int) -> int:
	var want: int = p.x + delta
	# The rows the box touches. When re-centring has not finished the box spans
	# two rows and BOTH must be clear, which is what stops a player cutting a
	# corner diagonally.
	var top_row: int = (p.y - TILE_H_CP / 2) / TILE_H_CP
	var bottom_row: int = (p.y + TILE_H_CP / 2 - 1) / TILE_H_CP

	if delta > 0:
		var edge: int = want + TILE_W_CP / 2 - 1
		var col: int = edge / TILE_W_CP
		for row in range(top_row, bottom_row + 1):
			if _player_blocked(col, row):
				# Stop with the box flush against the blocked cell — but never
				# BEHIND where the player already is. A player standing partly
				# past the flush line (they walked off their own bomb's cell,
				# say, and turned back) would otherwise be pushed the way they
				# are not pressing: hold left against the bomb you just left
				# and you slid right instead.
				return maxi(p.x, col * TILE_W_CP - TILE_W_CP / 2)
	else:
		var edge: int = want - TILE_W_CP / 2
		var col: int = _floor_div(edge, TILE_W_CP)
		for row in range(top_row, bottom_row + 1):
			if _player_blocked(col, row):
				return mini(p.x, (col + 1) * TILE_W_CP + TILE_W_CP / 2)
	return want


func _slide_y(p: Player_, delta: int) -> int:
	var want: int = p.y + delta
	var left_col: int = (p.x - TILE_W_CP / 2) / TILE_W_CP
	var right_col: int = (p.x + TILE_W_CP / 2 - 1) / TILE_W_CP

	if delta > 0:
		var edge: int = want + TILE_H_CP / 2 - 1
		var row: int = edge / TILE_H_CP
		for col in range(left_col, right_col + 1):
			if _player_blocked(col, row):
				return maxi(p.y, row * TILE_H_CP - TILE_H_CP / 2)
	else:
		var edge: int = want - TILE_H_CP / 2
		var row: int = _floor_div(edge, TILE_H_CP)
		for col in range(left_col, right_col + 1):
			if _player_blocked(col, row):
				return mini(p.y, (row + 1) * TILE_H_CP + TILE_H_CP / 2)
	return want


## Integer division that floors for negatives too. GDScript's `/` truncates
## toward zero, so -1 / 4000 is 0 and the cell left of the field would read as
## cell 0 — which would let a player walk out through the left wall.
static func _floor_div(a: int, b: int) -> int:
	var q := a / b
	if (a % b) != 0 and ((a < 0) != (b < 0)):
		q -= 1
	return q


static func _reverse_move(move: int) -> int:
	match move:
		Types_.MoveState.LEFT: return Types_.MoveState.RIGHT
		Types_.MoveState.RIGHT: return Types_.MoveState.LEFT
		Types_.MoveState.UP: return Types_.MoveState.DOWN
		Types_.MoveState.DOWN: return Types_.MoveState.UP
	return move


static func _move_to_dir(move: int) -> int:
	match move:
		Types_.MoveState.LEFT: return Types_.Dir.LEFT
		Types_.MoveState.RIGHT: return Types_.Dir.RIGHT
		Types_.MoveState.UP: return Types_.Dir.UP
		Types_.MoveState.DOWN: return Types_.Dir.DOWN
	return Types_.Dir.NONE


# ---------------------------------------------------------------------------
# Actions
# ---------------------------------------------------------------------------
## Dispatch this tick's action.
##
## The mapping is the MANUAL's, which describes the two buttons and what a
## double-press does:
##
##   first action          place a bomb
##   first, double-pressed grab and throw, or spooge — whichever the player has
##   second action         trigger every own triggerable bomb; or punch the
##                         bomb ahead, if walking into one
##
## Grabbing and then releasing without pressing again (hold-to-carry,
## `_check_hold_to_carry()` below) drops the bomb rather than throwing it —
## to throw, press again BEFORE letting go, which is a fast enough
## release-then-repress that the two arrive in the same tick and `throw_bomb`
## wins before the release is ever seen as a plain drop. A slower release —
## genuinely letting go and doing nothing else — sets it down instead.
##
## Grab and spooge are mutually exclusive by the powerups themselves (taking
## the grab disables spooging), so one button serves both.
## TEMPORARY DIAGNOSTIC — set AB_DEBUG_ACTIONS=1 to have every action press
## explain itself on stdout. Remove once the live glove reports are settled.
static var _debug_actions: int = -1

func _explain_action(p: Player_) -> void:
	if _debug_actions == -1:
		_debug_actions = 1 if OS.get_environment("AB_DEBUG_ACTIONS") != "" else 0
	if _debug_actions == 0 or p.action == Types_.Action.NONE:
		return
	var step: Vector2i = Types_.DIR_VEC[p.facing]
	var ahead := bomb_at(p.tile_x() + step.x, p.tile_y() + step.y)
	var under := bomb_at(p.tile_x(), p.tile_y())
	var carried := -1
	for b in bombs:
		if b.carried_by == p.slot:
			carried = bombs.find(b)
	print("[act] t=%d slot=%d action=%d held=%s facing=%d tile=(%d,%d) " % [
			tick_count, p.slot, p.action, p.action_first_held, p.facing,
			p.tile_x(), p.tile_y()]
		+ "bombs=%d/%d kick=%s punch=%s grab=%s spooge=%s trig=%d " % [
			p.bombs_available, p.bombs_total, p.can_kick, p.can_punch,
			p.can_grab, p.can_spooge, p.trigger_bombs]
		+ "under=%s ahead=%s(own=%s) carrying=%d pause=%d" % [
			under != null, ahead != null,
			ahead != null and ahead.owner == p.slot, carried, p.pickup_pause])


func _player_action(p: Player_) -> void:
	_explain_action(p)
	match p.action:
		Types_.Action.FIRST:
			# THE DISC'S OWN RULE, from MANUAL.BM: "To drop a bomb, press this
			# button. Otherwise, this button is used to drop a Spooge and
			# Grab/Throw a bomb. PRESS THE BUTTON AGAIN AFTER DROPPING A BOMB
			# to do either if you have the appropriate powerup."
			#
			# So it is one button and the SECOND press does the other thing —
			# not a timed double-tap and not a separate key. A press that
			# cannot place a bomb (one is already on this cell, or none are
			# left) falls through to throw, then grab, then spooge.
			#
			# This used to require Action.FIRST_DOUBLE, which nothing in the
			# game ever produced: grab, throw and spooge were unreachable for a
			# human player and only tests could call them.
			if place_bomb(p) != null:
				_play(p.slot, Types_.SoundEffect.BOMB_DROP)
			elif not throw_bomb(p):
				if p.can_grab:
					grab_bomb(p)
				elif p.can_spooge:
					spooge(p)

		Types_.Action.FIRST_DOUBLE:
			# Still honoured for a caller that says exactly what it means.
			if not throw_bomb(p):
				if p.can_grab:
					grab_bomb(p)
				elif p.can_spooge:
					spooge(p)

		Types_.Action.SECOND:
			# MANUAL.BM gives this button three jobs and this is their order of
			# specificity: stop a bomb you kicked, punch the one in front of
			# you, then trigger. "if your bomberman has the Kick powerup, press
			# the action button to stop a kicked bomb... if you have the Boxing
			# Glove, you can punch bombs in front of you... Finally, you can
			# activate a Trigger bomb."
			if not stop_bomb(p):
				if not punch_bomb(p):
					if trigger_bombs(p) == 0 and p.can_punch:
						# A SWING AT AIR. Nothing to stop, nothing to punch,
						# nothing to trigger — but a player wearing the Boxing
						# Glove who presses the action button has to SEE the
						# glove move, or the button reads as dead and the
						# powerup reads as broken. That was a live report, and
						# it is the same complaint an earlier session answered
						# from the other end by refusing the punch outright;
						# refusing it silently is what made it unreadable.
						#
						# The animation only. No _launch, no bomb, and
						# deliberately no BOMB_PUNCH sound — that sound is a
						# bomb being hit, and there is no bomb here.
						p.punch_ticks = PUNCH_ANIM_TICKS

	p.action = Types_.Action.NONE


## Place a bomb on the centre of the player's cell. Returns the bomb, or null
## if it could not be placed.
func place_bomb(p: Player_) -> Bomb_:
	if p.bombs_available <= 0:
		return null
	# CONSTIPATION: no bombs at all while it lasts. VALUELST 0.12009's own
	# changelog notes the edge case — a bomb refused by the disease must not
	# pop out the moment the disease ends, and it does not here because nothing
	# is queued.
	if p.has_disease(Types_.Disease.CONSTIPATION):
		return null
	var tx := p.tile_x()
	var ty := p.tile_y()
	if bomb_at(tx, ty) != null:
		return null
	if bombs.size() >= MAX_BOMBS:
		return null

	var b: Bomb_ = Bomb_.new()
	b.place_at_tile_centre(tx, ty)
	b.owner = p.slot
	b.chain_owner = p.slot
	b.placed_tick = tick_count
	# Copied now, not read at detonation: a flame powerup collected after the
	# drop must not lengthen this bomb's blast. SHORT_FLAME cuts it here for
	# the same reason.
	b.flame_len = 1 if p.has_disease(Types_.Disease.SHORT_FLAME) else p.flame_len

	if p.trigger_bombs > 0:
		# A trigger bomb waits for its owner's second action rather than
		# burning down. Resource 322's AtomicTimeTriggeredBombTimeOut has no
		# equivalent in VALUELST, so it simply waits.
		b.triggered = true
		b.fuze = _fuze_ticks
		p.trigger_bombs -= 1
	elif p.has_disease(Types_.Disease.SHORT_FUZE):
		# Almost immediate. A quarter of the normal fuze; the exact figure is
		# not in the table, so it is a guess and flagged as one.
		b.fuze = maxi(1, _fuze_ticks / 4)
	else:
		b.fuze = _fuze_ticks

	# DUDS: resource 322 makes it a 1-in-3 chance that the bomb is a dud, and
	# 323/324 that it then waits 120 + rand(200) frames before going off.
	if p.has_disease(Types_.Disease.DUDS):
		if rng.randi_range(1, Values_.V[Const_.Res.DUD_CHANCE]) == 1:
			b.state = Types_.BombState.DUD
			b.fuze = Values_.V[Const_.Res.DUD_WAIT_FRAMES] \
				+ rng.randi_range(0, Values_.V[Const_.Res.DUD_WAIT_RAND_FRAMES])

	bombs.append(b)
	p.bombs_available -= 1
	if stats != null:
		stats.bump(Stats_.C.BOMBS_DROPPED)
	return b


## The bomb on a cell, if any. A flying or carried bomb is not ON a cell, so it
## is not returned — which is what lets a player walk under a thrown bomb.
func bomb_at(tx: int, ty: int) -> Bomb_:
	for b in bombs:
		if b.detonated or b.flying or b.carried_by >= 0:
			continue
		if b.tile_x() == tx and b.tile_y() == ty:
			return b
	return null


# ---------------------------------------------------------------------------
# Bombs and flame
# ---------------------------------------------------------------------------
func _tick_bombs() -> void:
	# 1. Burn fuzes and collect what goes off this tick.
	_pending.clear()
	for i in bombs.size():
		var b: Bomb_ = bombs[i]
		if b.detonated:
			continue
		# A bomb placed during THIS tick does not burn this tick. Without
		# this, a bomb dropped through the input path burns a tick that a
		# bomb placed by a direct call does not, and the two paths disagree
		# about when a 40-frame fuze runs out.
		if b.placed_tick == tick_count:
			continue
		# A CARRIED bomb's fuze stops. AtomBomberman's notes: "when its picked
		# up its not even ticking (starts ticking when it falls)".
		if b.carried_by >= 0:
			continue
		# A TRIGGER bomb waits for its owner's signal instead of burning down.
		# If the owner dies it reverts to an ordinary bomb, or it would sit on
		# the field for the rest of the round with nobody able to fire it —
		# fpc_atomic reaches the same conclusion via a 15-second timeout, which
		# VALUELST has no resource for. A guess, and the only one here.
		if b.triggered:
			var owner_p := player_by_slot(b.owner)
			if owner_p != null and owner_p.alive and not owner_p.dying:
				continue
			b.triggered = false
		b.fuze -= 1
		if b.fuze <= 0:
			b.detonated = true
			_pending.append(i)

	# 2. A bomb caught by a flame goes off in the same tick, and can catch
	#    further bombs. Resolve to a fixed point rather than over several ticks,
	#    so a chain of any length is instantaneous — which is what the original
	#    looks like, and what makes a chain's outcome independent of the order
	#    bombs happen to sit in the array.
	var cursor := 0
	while cursor < _pending.size():
		var b: Bomb_ = bombs[_pending[cursor]]
		cursor += 1
		_explode(b)

	# 3. Give the bombs back and drop them from the list.
	var keep := []
	for b in bombs:
		if b.detonated:
			var owner := player_by_slot(b.owner)
			if owner != null:
				owner.bombs_available = mini(owner.bombs_available + 1,
					owner.bombs_total)
		else:
			keep.append(b)
	bombs = keep


func _explode(b: Bomb_) -> void:
	# One per bomb, so a chain reaction raises one per link. The mixer collapses
	# a tick's worth into a single voice — see scripts/audio/sfx.gd rule 1 —
	# because eight copies of one explosion 0 ms apart is not eight explosions.
	_play(b.chain_owner, Types_.SoundEffect.BOMB_EXPLODE)

	# The epicentre always burns. The original writes it once per direction,
	# inside the loop below (0x424008) — four identical writes, since the write
	# memsets the cell record and fills it in again. Once is the same result.
	field.add_flame(b.tile_x(), b.tile_y(), Types_.Flame.CROSS, b.chain_owner,
		_flame_ticks)

	# A powerup can be sitting on the bomb's own tile — a scattered pickup
	# landing there after the bomb was already placed, or a test editor drop
	# (docs/BUGS.md Q10's sibling case: _propagate()'s arm loop below starts
	# at n=1, one cell OUT from the bomb, and never looked at the bomb's own
	# cell at all). A live player can't normally leave one under themselves —
	# _collect_powerup() picks it up the same tick they stand on it — but
	# nothing stops one arriving after the bomb is already down. The arms
	# destroy a powerup they reach; the epicentre burns every bit as hot and
	# was silently letting one survive.
	if field.has_powerup(b.tile_x(), b.tile_y()):
		field.powerup[Field_.idx(b.tile_x(), b.tile_y())] = Field_.NO_POWERUP

	# ARM ORDER IS THE ORIGINAL'S, and it is the direction table's own:
	# 0x45BECC/0x45BEDC are (0,-1) (1,0) (0,1) (-1,0) — up, right, down, left —
	# and 0x423FA4's loop walks each arm to its end before starting the next.
	# It matters wherever two arms reach one cell: the LAST arm to write owns
	# the flame, and that decides who gets the kill.
	for dir in [Types_.Dir.UP, Types_.Dir.RIGHT, Types_.Dir.DOWN,
			Types_.Dir.LEFT]:
		# A bomb lit by another bomb does not fire back down the arm that lit
		# it — the original skips that direction outright (0x423FA4).
		if dir == b.blocked_dir:
			continue
		_propagate(b, dir)


## Walk one arm of the cross outward from a bomb.
##
## Stop rules, in the order they are tested:
##   solid    no flame on the cell, arm ends
##   brick    flame on the cell, brick destroyed, arm ends
##   powerup  flame on the cell, powerup destroyed, arm ends
##            — AtomBomberman's notes: flames "are stopped by blocks
##              (indestructible & destructible) and by powerups"
##   bomb     NO flame on the cell, that bomb detonates too, arm ENDS — the
##            chained bomb paints that cell itself, as its own epicentre, and
##            is told not to fire back the way the arm came
##   open     flame on the cell, arm continues
##
## Read out of `BM95.EXE` at 0x423FA4-0x424287 rather than reconstructed; the
## order of the tests is the original's too, bomb before powerup before cell.
## docs/BUGS.md Q5.3.
func _propagate(b: Bomb_, dir: int) -> void:
	var step: Vector2i = Types_.DIR_VEC[dir]
	var arm: int = _arm_flag(dir)

	for n in range(1, b.flame_len + 1):
		var x: int = b.tile_x() + step.x * n
		var y: int = b.tile_y() + step.y * n

		if not Field_.in_bounds(x, y):
			return

		# A bomb first, and it takes the cell: the original paints no flame
		# there (0x4240E0 jumps straight to the end of the arm) because the
		# bomb it just lit will paint that cell as its own epicentre in this
		# same tick.
		var other := bomb_at(x, y)
		if other != null:
			# The chain's ORIGINATING owner carries through, so the player who
			# started it gets the kill even three bombs down the line. The
			# original copies the same field, +0x3e, at 0x4240E9.
			other.chain_owner = b.chain_owner
			# And tells it not to fire back down this arm: 0x4240FA computes
			# (d + 2) & 3, which is the opposite direction.
			other.blocked_dir = _opposite(dir)
			other.detonated = true
			_pending.append(bombs.find(other))
			return

		# EXPOSED powerups only. field.gd hides a powerup UNDER a brick until
		# that brick is destroyed — "Hide powerups under the destructible
		# bricks" — so a cell can have has_powerup() true while brick_at() is
		# still BRICK, a combination the original's own memory layout never
		# produces (there the powerup flag is set only once the brick is
		# already gone). Testing has_powerup() first, as the disassembly does
		# for the original's data model, meant a brick hiding a powerup ate
		# the flame on its hidden powerup and never got destroyed at all —
		# same complaint from D27/D28 photographed live, "bombs sometimes do
		# not destroy walls": every brick VALUELST happened to hide a powerup
		# under needed two hits, one wasted on a powerup nobody ever saw. The
		# `brick_at` guard here is the port's own fix for its own storage
		# choice, not a change to the original's tested order below.
		if field.has_powerup(x, y) and field.brick_at(x, y) != Types_.Brick.BRICK:
			field.add_flame(x, y, arm | Types_.Flame.END, b.chain_owner,
				_flame_ticks)
			field.powerup[Field_.idx(x, y)] = Field_.NO_POWERUP
			return

		if field.brick_at(x, y) == Types_.Brick.SOLID:
			return

		# THE END BIT IS A FLAG ON THE ARM, NOT A REPLACEMENT FOR IT. It used
		# to be written instead of the direction, so the last cell of every arm
		# carried END and nothing else — and the view, which picks its sprite
		# from the direction bits, had no direction to pick from and fell
		# through to the CENTRE sprite. Every arm therefore ended in a second
		# epicentre instead of MFLAME.ANI's own `flame tip<dir> green`, which
		# was never drawn at all. The tip art is four of its nine sequences.
		#
		# An arm also ENDS on a brick it destroys, which is the other way it
		# stops and had the same defect from the other side: that cell drew the
		# mid piece and ran off the edge of the rubble.
		var stops: bool = n == b.flame_len \
			or field.brick_at(x, y) == Types_.Brick.BRICK
		field.add_flame(x, y, arm | (Types_.Flame.END if stops else 0),
			b.chain_owner, _flame_ticks)

		if field.brick_at(x, y) == Types_.Brick.BRICK:
			# destroy_brick() leaves `powerup[i]` untouched — the whole point
			# of hiding it there — so any powerup this brick was hiding is now
			# sitting exposed on the blank cell, exactly as if it had always
			# been in the open. Nothing further to do here.
			field.destroy_brick(x, y, _brick_ticks)
			if stats != null:
				stats.bump(Stats_.C.BRICKS_DESTROYED)
			return


static func _arm_flag(dir: int) -> int:
	match dir:
		Types_.Dir.UP: return Types_.Flame.UP
		Types_.Dir.DOWN: return Types_.Flame.DOWN
		Types_.Dir.LEFT: return Types_.Flame.LEFT
		Types_.Dir.RIGHT: return Types_.Flame.RIGHT
	return Types_.Flame.CROSS


## A player dies when the cell their centre is in is burning. Cell-based rather
## than box-based on purpose: the notes say "flames go thru bombermans", so the
## flame is not a solid the box collides with — the question is only which cell
## the player is standing on.
func _check_flame_death(p: Player_) -> void:
	# In the air off a trampoline, or briefly immortal after a teleport. The
	# notes: a teleporting player "is immortal when he is transported".
	if p.fly_ticks > 0 or p.invulnerable > 0:
		return
	if not field.has_flame(p.tile_x(), p.tile_y()):
		return
	kill(p, field.flame_owner_at(p.tile_x(), p.tile_y()))


## `0x41F29B`: every tick, test all four adjacent cells with the same
## bomb-or-wall test the AI's `ai_cell_is_open` uses minus its danger term
## (`0x41E5C3` — bomb_at_tile, then cell_at). When all four are blocked and no
## other special animation is already running (`cornerhead == 0` here stands
## in for the original's single shared "current special state" field, which
## also covers pickup/punch/kick in the real struct), roll one of the 13
## `cornerhead N` sequences and start it. Read from the disassembly, not
## invented: the trigger is purely geometric, independent of the player's own
## input — a player who has simply stopped moving in a dead end triggers it
## exactly as one who is actively trying to escape.
##
## Departure from the disassembly: the original reroll a fresh random variant
## every span for as long as the player stays boxed in, which onscreen reads
## as "every animation plays" rather than one. `p.cornered` latches once a
## variant has been rolled for this trapped episode, so it plays out exactly
## once and holds until the player is no longer boxed in — the episode ends
## and the latch clears the moment any adjacent cell opens up.
func _check_cornerhead(p: Player_) -> void:
	if p.cornerhead_ticks > 0:
		p.cornerhead_ticks -= 1
		if p.cornerhead_ticks == 0:
			p.cornerhead = 0
		return
	if p.pickup_pause > 0 or p.kick_ticks > 0 or p.punch_ticks > 0:
		return
	if p.fly_ticks > 0:
		return          # "out of play entirely: no cell" — same rule as elsewhere
	var tx := p.tile_x()
	var ty := p.tile_y()
	for dir in [Types_.Dir.UP, Types_.Dir.DOWN, Types_.Dir.LEFT,
			Types_.Dir.RIGHT]:
		var step: Vector2i = Types_.DIR_VEC[dir]
		var nx := tx + step.x
		var ny := ty + step.y
		if field.is_open(nx, ny) and bomb_at(nx, ny) == null:
			p.cornered = false
			return
	if p.cornered:
		return          # already played this trapped episode's one variant
	p.cornered = true
	p.cornerhead = 1 + rng.randi_range(0, Values_.V[Const_.Res.CORNERHEAD_COUNT] - 1)
	p.cornerhead_ticks = CORNERHEAD_TICKS


## Age everyone who is dying, and take away those whose animation is over.
##
## Before this a killed player was `dying` and `alive` FOREVER: nothing in the
## simulation ever cleared `alive`, so a corpse kept its place in every loop
## that tested it, kept a shadow under it, and kept being drawn. The renderer
## stopped after the animation's own frames, which hid most of it — but the
## body was still there.
func _tick_the_dying() -> void:
	for p in players:
		if not p.alive or not p.dying:
			continue
		if tick_count - p.death_tick >= DEATH_TICKS:
			p.alive = false


## Whether any player's death animation is still playing.
##
## `dying` is set once, in kill(), and NEVER cleared — it is not "is this
## player currently animating a death", it is "has this player died this
## round at all". `alive` is what `_tick_the_dying()` flips to false once
## DEATH_TICKS have passed, which is the actual end of the animation. So the
## still-animating test is both flags together, not `dying` alone — testing
## `dying` alone would stay true for the rest of the round after the first
## death and stall the caller forever.
##
## `_check_round_over()` drops a dying player from `standing` the instant
## they die, so a cornered last-standing player's death can end the round on
## the very same tick their animation starts — and DEATH_TICKS' own header
## promises "every one of the 24 gets to finish". The caller (main.gd's
## round/match transition) uses this to hold the intermission open rather
## than tearing the Sim down — and the corpse it is rendering — out from
## under an animation that has not.
func anyone_dying() -> bool:
	for p in players:
		if p.dying and p.alive:
			return true
	return false


func kill(p: Player_, by: int = -1) -> void:
	if p.dying or not p.alive:
		return
	p.dying = true
	p.death_tick = tick_count
	# One of the disc's 24 deaths, from the seeded RNG so a replay dies the
	# same way. VALUELST 105 is where the 24 comes from.
	p.death_anim = rng.randi_range(1, DEATH_ANIMS)
	if stats != null:
		stats.bump(Stats_.C.DEATHS_ALL)
		if is_bot(p.slot):
			stats.bump(Stats_.C.DEATHS_AI)
	# The kill goes to whoever owned the flame. p.killed_by is set two lines
	# below in the original order of this function, so the attribution is read
	# from `by` here rather than from the player.
	var killer := -1 if by == Field_.NO_OWNER else by
	if killer >= 0 and killer < round_kills.size():
		# Your own bomb costs you one. OPTIONS.BM says so in as many words.
		round_kills[killer] += -1 if killer == p.slot else 1
	# VALUELST 1300, "250 for killing an AI" (docs/AUDIT.md) — round_score
	# exists for campaign mode alone (see its own declaration above) and
	# _kill_creature() already reads 1310/1320 for a rover/ghost; this is
	# 1300's own case, a bot PLAYER rather than a creature. Not a suicide —
	# the same exclusion round_kills already makes two lines up — and not
	# outside a campaign, where round_score is never read at all.
	if killer >= 0 and killer != p.slot and killer < round_score.size() \
			and is_bot(p.slot) and not creatures.is_empty():
		round_score[killer] += Values_.V[Const_.Res.SCORE_AI]
	p.killed_by = -1 if by == Field_.NO_OWNER else by
	p.move = Types_.MoveState.STILL
	p.action = Types_.Action.NONE
	# Their pickups go back on the field — fpc_atomic does the same at its
	# 0.07004, "Respawn collected powerups of dead player".
	repopulate_powerups(p)
	_play(p.slot, Types_.SoundEffect.PLAYER_DIED)
	# SOUNDLST 341 "burnedup" — "death anim sounds BASED on which anim is
	# chosen (this is just clunk-type sound effects to sync with the anim, no
	# screams or anything)". Read as describing 24 animations sharing 9
	# sounds; checked directly against the disc and it is not — there is
	# exactly one resource here (341) and one file (BURNEDUP.RSS), no
	# "NNN is the last..." comment bounding a wider group the way every
	# other event has one. tools/rss.py's EVENTS table said (341, 349) by
	# analogy with the neighbouring 9-wide groups; that was a guess, and
	# wrong. There is nothing to map: one sound, every death. docs/BUGS.md
	# D29.
	_play(p.slot, Types_.SoundEffect.DEATH_CLUNK)
	# "after a player death" — 282 taunts, the largest range on the disc. Raised
	# as its own event so the mixer can drop it under load without losing the
	# scream, which is the one that tells you what happened.
	_play(p.killed_by, Types_.SoundEffect.DEATH_TAUNT)


# ---------------------------------------------------------------------------
# Map specials — conveyors, arrows, warps, trampolines, regrowth
# ---------------------------------------------------------------------------
#
# Coordinates are the original's, from EXTRA*.RES. The RULES below are
# reconstructed, in the same sense as movement — docs/BUGS.md Q5.
#
# THE CONVEYOR SPEED. Resources 190-192 give three, 250 / 350 / 450 hundredths
# of a pixel per frame, and resource 189 says there are three. Which one a
# round uses is a game setting the original exposes in its options; there is no
# resource naming a default, so the middle one is used and the choice is
# settable rather than baked in.
var conveyor_speed_index: int = 1

## Settings the original exposes on its own options screen, each defaulting to
## the VALUELST resource that is its documented default. MESSAGES.TXT 250-268
## is that screen, label by label, and OPTIONS.BM is its help text; between
## them they say which resources are settings rather than constants.
##
## They live here rather than being read from Values_ at the point of use so
## that a menu can change them — which is exactly what resource 310's comment
## ("default; override by settings configuration") describes.
var enclose_depth: int = -1        ## resource 27, four depths named by 315-318
var stomped_detonate: bool = true  ## resource 46
var diseases_destroyable: bool = true  ## resource 120


## Fill in any setting still at its sentinel from the tuning table. Called by
## setup(), so a caller that sets nothing gets the disc's defaults and a caller
## that sets something keeps it.
func _apply_defaults() -> void:
	if enclose_depth < 0:
		enclose_depth = int(Values_.V[Const_.Res.ENCLOSE_DEPTH])
	stomped_detonate = stomped_detonate \
		and Values_.V[Const_.Res.WALL_DETONATES_BOMB] != 0
	diseases_destroyable = diseases_destroyable \
		and Values_.V[Const_.Res.DISEASE_DESTROYABLE] != 0


func conveyor_speed() -> int:
	var n: int = Values_.V[Const_.Res.CONVEYOR_SPEED_COUNT]
	var i: int = clampi(conveyor_speed_index, 0, n - 1)
	return Values_.V[Const_.Res.CONVEYOR_SPEED_BASE + i]


## A player who is flying off a trampoline is out of play: not on a cell, not
## hit by flame, not carried by anything.
func _field_vs_player(p: Player_) -> void:
	if p.fly_ticks > 0:
		p.fly_ticks -= 1
		if p.fly_ticks == 0:
			# Landed. The destination was chosen when they were launched.
			p.place_at_tile_centre(p.fly_to_x, p.fly_to_y)
			_play(p.slot, Types_.SoundEffect.TRAMPOLINE)
		return

	var tx := p.tile_x()
	var ty := p.tile_y()

	# A trampoline launches whoever steps on it. Resource 680 is 30 frames in
	# the air, resource 681 the 35 pixels per frame it rises — the renderer's
	# business; the simulation only needs to know they are away and where they
	# come down.
	if field.tramp_at(tx, ty):
		var dest := _random_open_cell(tx, ty)
		if dest.x >= 0:
			p.fly_ticks = Values_.V[Const_.Res.TRAMP_BOUNCE_FRAMES]
			p.fly_to_x = dest.x
			p.fly_to_y = dest.y
			return

	# A warp gate takes whoever steps on it to the gate it leads to. The notes:
	# a teleporting player is briefly immortal, flames pass over a gate, and
	# bombs are stopped by one.
	var gate := field.warp_at(tx, ty)
	if gate >= 0 and p.warp_cooldown == 0:
		var exit_cell := field.warp_exit(gate)
		if exit_cell.x >= 0:
			p.place_at_tile_centre(exit_cell.x, exit_cell.y)
			# Without a cooldown the player would immediately be standing on
			# the destination gate and be sent straight back, forever.
			p.warp_cooldown = Values_.V[Const_.Res.TRAMP_BOUNCE_FRAMES] / 2
			p.invulnerable = p.warp_cooldown
			_play(p.slot, Types_.SoundEffect.WARP)
			return

	# A conveyor carries whoever is on it, in its direction, at the round's
	# conveyor speed. It moves the player even when they are standing still,
	# which is the whole point of it.
	var carry := field.conveyor_at(tx, ty)
	if carry != Types_.Dir.NONE:
		var step: Vector2i = Types_.DIR_VEC[carry]
		var speed := conveyor_speed()
		if step.x != 0:
			p.x = _slide_x_by(p, step.x * speed)
		else:
			p.y = _slide_y_by(p, step.y * speed)


## Move a player along an axis by an explicit amount, reusing the same
## collision the player's own movement uses — so a conveyor cannot push
## somebody into a wall.
func _slide_x_by(p: Player_, delta: int) -> int:
	var saved := p.speed
	p.speed = absi(delta)
	var result := _slide_x(p, delta)
	p.speed = saved
	return result


func _slide_y_by(p: Player_, delta: int) -> int:
	var saved := p.speed
	p.speed = absi(delta)
	var result := _slide_y(p, delta)
	p.speed = saved
	return result


## A cell to land on after a trampoline. Anywhere open that is not another
## trampoline, or the player could bounce forever.
func _random_open_cell(from_x: int, from_y: int) -> Vector2i:
	var options: Array[Vector2i] = []
	for y in Const_.FIELD_H:
		for x in Const_.FIELD_W:
			if x == from_x and y == from_y:
				continue
			if not field.is_open(x, y) or field.tramp_at(x, y):
				continue
			if bomb_at(x, y) != null:
				continue
			options.append(Vector2i(x, y))
	if options.is_empty():
		return Vector2i(-1, -1)
	return options[rng.randi_range(0, options.size() - 1)]


## Per-tick field business: cooldowns and the haunted house's regrowth.
func _tick_field() -> void:
	for p in players:
		if p.warp_cooldown > 0:
			p.warp_cooldown -= 1
		if p.invulnerable > 0:
			p.invulnerable -= 1

	var cells: Array[Vector2i] = []
	for p in players:
		if p.alive and not p.dying:
			cells.append(Vector2i(p.tile_x(), p.tile_y()))
	field.tick_regen(cells, rng)


# ---------------------------------------------------------------------------
# The round
# ---------------------------------------------------------------------------
#
# HURRY. Resource 101 says the message first flashes at 60 seconds remaining,
# and its comment is unusually firm about it:
#
#     it is NOT RECOMMENDED that you modify this value! A lot of strange
#     things will happen if you set it to "non standard" values.
#
# From then on the playfield closes in. Resource 27 is the default enclosement
# DEPTH and it is 1, which resource 28's list of four depths (0..3) makes "2
# rows" — NOT the whole field. fpc_atomic always runs its full 160-cell spiral,
# which is depth 3. ORACLE row 19.
func _tick_round() -> void:
	_tick_the_dying()
	if outcome != Outcome.RUNNING:
		ticks_since_over += 1
		return

	if time_left > 0:
		time_left -= 1

	var hurry_at: int = Values_.V[Const_.Res.HURRY_AT_SECONDS] * Const_.TICK_HZ
	if hurry_index < 0 and time_left <= hurry_at:
		hurry_index = 0
		_play(-1, Types_.SoundEffect.HURRY)
	elif hurry_index >= 0:
		_advance_hurry()

	_check_round_over()
	if outcome != Outcome.RUNNING:
		# The transition tick, and only it: this function returns at the top
		# once the round is over, so it cannot be reached twice in one round.
		_play(winner_slot, Types_.SoundEffect.ROUND_WIN
			if outcome == Outcome.LAST_STANDING else Types_.SoundEffect.DRAW)


## One step of the closing wall. Its path is a clockwise inward spiral, which
## fpc_atomic tabulates as 160 points; it is generated here instead, because a
## generated spiral cannot be mis-transcribed and the shape is not in any data
## file either way.
##
## The wall drops a SOLID on the cell, and per resource 46 a bomb caught by it
## is DETONATED rather than destroyed.
func _advance_hurry() -> void:
	var path := hurry_path()
	if hurry_index >= path.size():
		return
	# One cell per 8 ticks, so the field closes over a plausible span rather
	# than instantly. Not a tabulated figure — a guess, and the only one in
	# this function.
	if tick_count % 8 != 0:
		return
	var cell: Vector2i = path[hurry_index]
	hurry_index += 1

	var b := bomb_at(cell.x, cell.y)
	if b != null and stomped_detonate:
		b.detonated = true
		_pending.append(bombs.find(b))
		var cursor := 0
		while cursor < _pending.size():
			_explode(bombs[_pending[cursor]])
			cursor += 1

	field.brick[Field_.idx(cell.x, cell.y)] = Types_.Brick.SOLID
	field.powerup[Field_.idx(cell.x, cell.y)] = Field_.NO_POWERUP
	# "a solid tile slamming in place (after 'hurry' is displayed)" — and the
	# original's own note that the code is HARD-CODED to pick one of three.
	_play(-1, Types_.SoundEffect.SOLID_DROP)

	# Anyone standing there is crushed.
	for p in players:
		if p.alive and not p.dying \
				and p.tile_x() == cell.x and p.tile_y() == cell.y:
			kill(p, -1)


## The cells the closing wall fills, in order, for the configured depth.
##
## Depth comes from resource 27 and resource 28 says there are four of them.
## Reading 0 as none, 1 as two rows, 2 as four rows and 3 as the whole field is
## the only reading consistent with both resources; the mapping itself is not
## stated. docs/BUGS.md.
func hurry_path() -> Array[Vector2i]:
	if _hurry_path_cache.is_empty():
		_hurry_path_cache = _build_hurry_path(enclose_depth)
	return _hurry_path_cache


func _build_hurry_path(depth: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if depth <= 0:
		return out
	# Rings of the spiral: depth 1 fills two rows, i.e. one ring; depth 2 two
	# rings; depth 3 every ring there is.
	var rings: int = 1 if depth == 1 else (2 if depth == 2 else 99)
	var left := 0
	var top := 0
	var right := Const_.FIELD_W - 1
	var bottom := Const_.FIELD_H - 1
	var ring := 0
	while left <= right and top <= bottom and ring < rings:
		for x in range(left, right + 1):
			out.append(Vector2i(x, top))
		for y in range(top + 1, bottom + 1):
			out.append(Vector2i(right, y))
		if bottom > top:
			for x in range(right - 1, left - 1, -1):
				out.append(Vector2i(x, bottom))
		if right > left:
			for y in range(bottom - 1, top, -1):
				out.append(Vector2i(left, y))
		left += 1
		top += 1
		right -= 1
		bottom -= 1
		ring += 1
	return out


var _hurry_path_cache: Array[Vector2i] = []


## Is the round over, and why?
##
## Three ways to end. A DRAW is the case where the last players die close
## enough together that nobody outlived anyone — AtomBomberman's notes call it
## "draw game condition (draw time) - if last bomber dies in some time after
## the one before".
func _check_round_over() -> void:
	if outcome != Outcome.RUNNING:
		return

	if time_left <= 0:
		outcome = Outcome.TIME_UP
		return

	var standing: Array[Player_] = []
	var contenders := 0
	for p in players:
		if not p.in_play:
			continue
		contenders += 1
		if p.alive and not p.dying:
			standing.append(p)

	if team_play:
		if contenders < 2:
			return
		var teams := {}
		for p in standing:
			teams[p.team] = true
		if teams.size() == 1:
			outcome = Outcome.LAST_STANDING
			winner_team = standing[0].team
		elif teams.is_empty():
			outcome = Outcome.DRAW
		return

	# Both endings need the round to have STARTED with more than one player IN
	# PLAY. Counting seats rather than players made a server with ten empty
	# seats declare an instant draw, and counting all players made a solo round
	# end on tick one with its only player as the winner.
	if contenders < 2:
		return
	if standing.size() == 1:
		outcome = Outcome.LAST_STANDING
		winner_slot = standing[0].slot
		winner_team = standing[0].team
	elif standing.is_empty():
		outcome = Outcome.DRAW


## End the round with nobody winning it. MANUAL.BM: "F10 - Forces a draw game."
##
## The same outcome running out of clock produces, so the match counts it the
## same way and no new case appears anywhere downstream.
func force_draw() -> bool:
	if outcome != Outcome.RUNNING:
		return false
	outcome = Outcome.DRAW
	winner_slot = -1
	winner_team = Types_.TEAM_UNSET
	_play(-1, Types_.SoundEffect.DRAW)
	return true


func round_over() -> bool:
	return outcome != Outcome.RUNNING


func seconds_left() -> int:
	return time_left / Const_.TICK_HZ


# ---------------------------------------------------------------------------
# Bombs in motion — kick, punch, throw, jelly
# ---------------------------------------------------------------------------
#
# ASSUMED, in the same sense as movement — docs/BUGS.md Q5. Every SPEED and
# HEIGHT is the original's (resources 300, 301, 660, 661, 500-506, 665, 667);
# what is reconstructed is how they are applied. A bomb rolls until something
# blocks it, and a punched or thrown bomb flies over everything and lands.
func _move_bombs() -> void:
	for b in bombs:
		if b.detonated:
			continue
		if b.carried_by >= 0:
			_carry_bomb(b)
		elif b.flying:
			_fly_bomb(b)
		elif b.move_dir != Types_.Dir.NONE:
			_roll_bomb(b)


## A carried bomb sits on its carrier and its fuze does not burn — the notes:
## "when its picked up its not even ticking".
func _carry_bomb(b: Bomb_) -> void:
	var p := player_by_slot(b.carried_by)
	if p == null or not p.alive or p.dying:
		# The carrier died holding it. It falls where they stood and resumes.
		b.carried_by = -1
		return
	b.x = p.x
	b.y = p.y


## One step of a rolling bomb. It stops on anything solid; a jelly bomb bounces
## back instead, and may change direction crazily at a cell centre — resource
## 667 makes that a 1-in-3 chance.
func _roll_bomb(b: Bomb_) -> void:
	var step: Vector2i = Types_.DIR_VEC[b.move_dir]
	var next_x: int = b.x + step.x * b.speed
	var next_y: int = b.y + step.y * b.speed

	# The cell the bomb's leading edge is entering.
	var lead_x: int = (next_x + step.x * (Bomb_.TILE_W_CP / 2 - 1)) / Bomb_.TILE_W_CP \
		if step.x != 0 else next_x / Bomb_.TILE_W_CP
	var lead_y: int = (next_y + step.y * (Bomb_.TILE_H_CP / 2 - 1)) / Bomb_.TILE_H_CP \
		if step.y != 0 else next_y / Bomb_.TILE_H_CP

	if _bomb_blocked(b, lead_x, lead_y):
		if b.jelly_bounce:
			# Snapped back to the cell centre it bounced off of, same as the
			# stop path below — the half-cell lookahead lets the bomb creep
			# right up to the wall before this fires, and without the snap it
			# stayed there, sprite sitting into the wall, for the tick before
			# the reversed direction pulled it away.
			b.place_at_tile_centre(b.tile_x(), b.tile_y())
			b.move_dir = _opposite(b.move_dir)
			b.state = Types_.BombState.WOBBLE
			_play(b.owner, Types_.SoundEffect.BOMB_BOUNCE)
		else:
			b.move_dir = Types_.Dir.NONE
			b.speed = 0
			# Snap to the cell it came to rest on, so a stopped bomb is always
			# cell-aligned and bomb_at() can find it.
			b.place_at_tile_centre(b.tile_x(), b.tile_y())
			_play(b.owner, Types_.SoundEffect.BOMB_STOP)
		return

	b.x = next_x
	b.y = next_y

	# An ARROW redirects a bomb that rolls onto it. A bomb PLACED on one is not
	# moved — AtomBomberman's notes: "when bomb is put on an arrow, or its
	# thrown onto it, it doesnt move because of the arrow" — which is why this
	# is here, in the rolling path, and not in place_bomb().
	if _at_cell_centre(b):
		var push := field.arrow_at(b.tile_x(), b.tile_y())
		if push != Types_.Dir.NONE and push != b.move_dir:
			_turn_rolling_bomb(b, push)
			return
		# A CONVEYOR under a rolling bomb turns it too, at the belt's speed.
		var carry := field.conveyor_at(b.tile_x(), b.tile_y())
		if carry != Types_.Dir.NONE:
			_turn_rolling_bomb(b, carry)
			b.speed = conveyor_speed()

	# A jelly bomb crossing a cell centre may turn. "at each 0,0 intersection,
	# what is the chances that a punched jelly bomb will change directions
	# crazily" — resource 667.
	if b.jelly_bounce and _at_cell_centre(b):
		if rng.randi_range(1, Values_.V[Const_.Res.JELLY_TURN_CHANCE]) == 1:
			# A QUARTER TURN, LEFT OR RIGHT — BM95.EXE 0x423A1E:
			#
			#     rand() % 2 -> {0, 1}, doubled -> {0, 2}
			#     dir = (dir + {0,2} - 1) & 3
			#
			# which over the original's 0..3 direction encoding is exactly
			# "turn ninety degrees one way or the other". It never reverses
			# and never keeps going straight.
			#
			# This port picked freely among all four directions, filtered by
			# what was unblocked — so a jelly bomb could double back on itself
			# or carry straight on through the roll, neither of which the
			# original can produce. The filtering goes too: the original does
			# not test the new direction at all, it just takes it and lets the
			# next tick's ordinary bounce handle a wall.
			_turn_rolling_bomb(b,
				_quarter_turn(b.move_dir, rng.randi_range(0, 1) == 1))


## The two directions ninety degrees off this one, `right` choosing which.
## BM95.EXE does this arithmetically over its own 0..3 encoding ((d±1) & 3);
## this enum is not that encoding, so the same rule is written out rather than
## faked with modular arithmetic that would only coincidentally agree.
static func _quarter_turn(dir: int, right: bool) -> int:
	match dir:
		Types_.Dir.UP:
			return Types_.Dir.RIGHT if right else Types_.Dir.LEFT
		Types_.Dir.DOWN:
			return Types_.Dir.LEFT if right else Types_.Dir.RIGHT
		Types_.Dir.LEFT:
			return Types_.Dir.UP if right else Types_.Dir.DOWN
		Types_.Dir.RIGHT:
			return Types_.Dir.DOWN if right else Types_.Dir.UP
	return dir


## Turn a rolling bomb, snapping it to the intersection it is turning at.
##
## _at_cell_centre() is a TOLERANCE — "within half a step of the centre" —
## because a bomb moving `speed` centipixels a tick almost never lands exactly
## on a centre. Turning without closing that gap left the bomb up to half a
## step off-centre on the axis it was now crossing, and nothing ever pulled it
## back: every later turn added its own error. A jelly bomb doing its 1-in-3
## crazy turns drifted visibly off the grid within a few bounces, and its
## tile_x()/tile_y() flipped a tick early or late against what the player could
## see, so its bounces off walls and the map border read as random.
##
## Players get the same treatment from _recentre_x()/_recentre_y() for the same
## reason; a bomb has no drift to absorb, so it snaps in one go.
func _turn_rolling_bomb(b: Bomb_, dir: int) -> void:
	b.place_at_tile_centre(b.tile_x(), b.tile_y())
	b.move_dir = dir


func _at_cell_centre(b: Bomb_) -> bool:
	var ox: int = b.x % Bomb_.TILE_W_CP
	var oy: int = b.y % Bomb_.TILE_H_CP
	return absi(ox - Bomb_.TILE_W_CP / 2) <= b.speed / 2 \
		and absi(oy - Bomb_.TILE_H_CP / 2) <= b.speed / 2


## Is a cell blocked for a PLAYER? The field, plus any bomb at rest on it — a
## player cannot walk through a bomb, which is what makes kicking meaningful.
func _player_blocked(tx: int, ty: int) -> bool:
	if not field.is_open(tx, ty):
		return true
	return bomb_at(tx, ty) != null


## Can a rolling bomb enter this cell? Blocked by the field, by another bomb,
## and — for a bomb ROLLING along the ground — by a player, since a bomb
## cannot roll through someone.
##
## `for_landing`, for a bomb arriving by air (punch/throw), skips that last
## check: landing ON a player is `_bomb_on_the_head()`'s whole mechanic, not
## an obstruction. Still stopped by everything else — the field, a warp, a
## trampoline, another bomb — which is the port's own rule for what
## `_landing_cell()` treats as occupied; the disassembly does not say.
func _bomb_blocked(b: Bomb_, tx: int, ty: int, for_landing: bool = false) -> bool:
	if not field.is_open(tx, ty):
		return true
	# A warp gate stops a bomb — the notes: teleports "stop bombs".
	if field.warp_at(tx, ty) >= 0:
		return true
	# So does a trampoline. fpc_atomic 0.11002 disables kicking and throwing
	# onto one for the same reason.
	if field.tramp_at(tx, ty):
		return true
	var other := bomb_at(tx, ty)
	if other != null and other != b:
		return true
	# A BOMB ALREADY IN THE AIR HEADING HERE counts as occupying the cell.
	#
	# bomb_at() deliberately ignores a flying bomb — that is what lets a player
	# walk under one — so a landing search could not see a bomb that was
	# airborne and aimed at the same cell. Throw or punch two bombs at the same
	# spot and both were cleared to land on it, and they came to rest stacked:
	# "the bombs overlap instead of continuing to the next free space", from a
	# live playtest. Each one has to see the other's destination.
	for flier in bombs:
		if flier == b or flier.detonated or not flier.flying:
			continue
		if flier.fly_to_x / Bomb_.TILE_W_CP == tx \
				and flier.fly_to_y / Bomb_.TILE_H_CP == ty:
			return true
	if for_landing:
		return false
	for p in players:
		if not p.alive or p.dying:
			continue
		if p.tile_x() == tx and p.tile_y() == ty:
			return true
	return false


## One tick of a flying bomb. It travels in a straight line between two cell
## centres over fly_ticks and lands on arrival; the arc is the renderer's
## business and lives in fly_height.
func _fly_bomb(b: Bomb_) -> void:
	b.fly_tick += 1
	var f: float = float(b.fly_tick) / float(maxi(1, b.fly_ticks))
	b.x = b.fly_from_x + int((b.fly_to_x - b.fly_from_x) * f)
	b.y = b.fly_from_y + int((b.fly_to_y - b.fly_from_y) * f)
	# The arc is computed in unwrapped coordinates and only then brought back
	# onto the field, so a bomb thrown off an edge crosses the boundary and
	# reappears on the far side instead of sliding back across the arena.
	_wrap_bomb_pos(b)
	if b.fly_tick < b.fly_ticks:
		return

	# Landed. SOUNDLST 160 is "a punched/grabbed bomb bouncing along", which is
	# this moment and not the throw: the throw is BOMB_PUNCH or BOMB_GRAB.
	b.flying = false
	b.x = b.fly_to_x
	b.y = b.fly_to_y
	_wrap_bomb_pos(b)
	b.place_at_tile_centre(b.tile_x(), b.tile_y())
	_play(b.owner, Types_.SoundEffect.BOMB_THROWN)
	_bomb_on_the_head(b)

	# IT BOUNCES ON, one cell at a time, until something stops it or its fuze
	# runs out. VALUELST 660 and 661 are "initial three-space punch bounces"
	# and "subsequent small 1-space punch bounces" — the first hop covers the
	# three cells at the tall arc, every hop after that covers one at the
	# small one. SOUNDLST 160 is "a punched/GRABBED bomb bouncing along", so a
	# thrown bomb does this too; it used to be given no bounces at all and
	# simply stopped dead where it landed.
	#
	# No bounce count any more: the fuze is what ends it, now that a bounce no
	# longer resets it. The landing cell is wrapped for the same reason the
	# flight is — a bomb bouncing along is still travelling over the arena
	# wall, not into it.
	if b.move_dir != Types_.Dir.NONE:
		var step: Vector2i = Types_.DIR_VEC[b.move_dir]
		var tx := _wrap_tx(b.tile_x() + step.x)
		var ty := _wrap_ty(b.tile_y() + step.y)
		if Field_.in_bounds(tx, ty) and not _bomb_blocked(b, tx, ty, true):
			_launch(b, tx, ty, Values_.V[Const_.Res.PUNCH_ARC_SMALL],
				Values_.V[Const_.Res.PUNCHED_BOMB_SPEED], false)
			return
	b.move_dir = Types_.Dir.NONE
	b.speed = 0


## A BOMB LANDING ON SOMEBODY'S HEAD, which the disc tunes and the port had not
## implemented at all.
##
## Two resources say what happens, and their comments are the whole rule:
##
##     670,1   what's the minimum number of powers you lose when hit on the head?
##     671,3   what's the additional random number of powers you might lose?
##
## and SOUNDLST 360-399 gives it forty recordings of its own, described as "you
## are stunned by a bomb landing on you". Forty takes is not a sound for
## something that never happens.
##
## The powers go back on the field the same way a dead player's do — the field
## is where a lost powerup belongs, and scatter_powerup is already the disc's
## own answer to "where". WHICH powers are lost is this port's: the disc says a
## number, not a choice, so they are taken in the order the powerup table is
## in, from whatever the player actually holds.
func _bomb_on_the_head(b: Bomb_) -> void:
	var lose: int = int(Values_.V[Const_.Res.HEAD_HIT_MIN_LOSS]) \
		+ rng.randi_range(0, int(Values_.V[Const_.Res.HEAD_HIT_RAND_LOSS]))
	if lose <= 0:
		return
	for p in players:
		if not p.in_play or not p.alive or p.dying:
			continue
		if p.tile_x() != b.tile_x() or p.tile_y() != b.tile_y():
			continue
		if p.slot == b.owner and b.carried_by == p.slot:
			# You do not brain yourself with the bomb you are holding.
			continue
		var lost := 0
		for which in Const_.POWERUP_COUNT:
			if lost >= lose:
				break
			# The diseases are not powers you can lose: VALUELST 122 already
			# says a disease does not recycle when it leaves a player, and
			# taking one away would be a reward.
			if which == Types_.PowerUp.DISEASE \
					or which == Types_.PowerUp.SUPER_BAD_DISEASE:
				continue
			while p.collected[which] > 0 and lost < lose:
				p.collected[which] -= 1
				field.scatter_powerup(which, rng)
				lost += 1
		if lost > 0:
			recompute_powers(p)
			_play(p.slot, Types_.SoundEffect.BOMB_HIT_HEAD)


## The furthest open cell along a straight line, up to `max_dist` out.
##
## A flying bomb crosses whatever ground is under its arc — that is the whole
## point of punching or throwing one over a brick — so only where it LANDS
## needs to be clear, not the cells it passes over, and landing ON A PLAYER
## is not an obstruction, it is `_bomb_on_the_head()`. Nothing in VALUELST or
## the disassembly says what the original does when the intended landing
## spot has another BOMB already on it; this is the port's own call, made
## the same way a rolling (kicked) bomb already behaves — it stops on the
## nearest open cell rather than overwriting whatever is there.
func _landing_cell(b: Bomb_, from_tx: int, from_ty: int, dir: int,
		max_dist: int) -> Vector2i:
	var step: Vector2i = Types_.DIR_VEC[dir]

	# THE INTENDED SPOT: the full distance out, whatever the arc passed over.
	# The cells in between are deliberately NOT tested. This loop used to walk
	# out one cell at a time and `break` on the first blocked one, which is the
	# exact opposite of what the docstring above it describes and meant a
	# thrown or punched bomb could never clear a wall: the search stopped at
	# the brick and the "landing" came back as the thrower's own cell, so the
	# bomb was set down at their feet. MANUAL.BM is explicit that this is the
	# point of both abilities — "Throw and punch your bombs over the wall to
	# destroy your opponents."
	# Walk outward from the intended distance until a cell will take it. The
	# search runs in UNWRAPPED tile coordinates and tests each candidate at its
	# WRAPPED position, returning the unwrapped one: that is what lets the
	# flight carry the bomb off the edge of the arena and bring it back on the
	# far side, rather than teleporting it across the screen.
	var limit: int = max_dist + Const_.FIELD_W + Const_.FIELD_H + 2 * WRAP_MARGIN
	for n in range(max_dist, limit + 1):
		var tx: int = from_tx + step.x * n
		var ty: int = from_ty + step.y * n
		var wx: int = _wrap_tx(tx)
		var wy: int = _wrap_ty(ty)
		if not Field_.in_bounds(wx, wy):
			continue          # the margin outside the arena: fly on over it
		if not _bomb_blocked(b, wx, wy, true):
			return Vector2i(tx, ty)

	# Every cell in the ring is taken. Fall back toward the thrower and take
	# the nearest that will have it, their own as the last resort.
	for back in range(max_dist - 1, 0, -1):
		var tx: int = from_tx + step.x * back
		var ty: int = from_ty + step.y * back
		if Field_.in_bounds(tx, ty) and not _bomb_blocked(b, tx, ty, true):
			return Vector2i(tx, ty)
	return Vector2i(from_tx, from_ty)


## THE ARENA WRAPS FOR A BOMB IN THE AIR — BM95.EXE 0x4238E1:
##
##     if tile_x >= field_w + 2:  x -= (field_w + 3) * cell_w
##     if tile_x <= -2:           x += (field_w + 3) * cell_w
##
## and the same pair for y. A thrown or punched bomb that leaves the arena
## comes back on the opposite side; it is not stopped by the outer wall,
## because it is flying over it. Without this a player standing near an edge
## and facing out had every candidate cell refused, so the throw collapsed to
## zero distance and the bomb was set down at their feet — "you cannot throw
## bombs from the edge", from a live playtest.
##
## The margin of 3 and the "two cells past the edge" trigger are the
## original's own numbers, so a bomb spends a moment genuinely off the field
## before reappearing rather than snapping across the instant it passes the
## wall.
const WRAP_MARGIN := 3

static func _wrap_tx(tx: int) -> int:
	var span: int = Const_.FIELD_W + WRAP_MARGIN
	while tx >= Const_.FIELD_W + 2:
		tx -= span
	while tx <= -2:
		tx += span
	return tx


static func _wrap_ty(ty: int) -> int:
	var span: int = Const_.FIELD_H + WRAP_MARGIN
	while ty >= Const_.FIELD_H + 2:
		ty -= span
	while ty <= -2:
		ty += span
	return ty


## The same rule in centipixels, applied to a bomb in flight. Kept in pixel
## space rather than going through tile_x(), which truncates toward zero and
## would read -1 as cell 0 for a bomb left of the field.
func _wrap_bomb_pos(b: Bomb_) -> void:
	var span_x: int = (Const_.FIELD_W + WRAP_MARGIN) * Bomb_.TILE_W_CP
	var span_y: int = (Const_.FIELD_H + WRAP_MARGIN) * Bomb_.TILE_H_CP
	while b.x >= (Const_.FIELD_W + 2) * Bomb_.TILE_W_CP:
		b.x -= span_x
	while b.x < -2 * Bomb_.TILE_W_CP:
		b.x += span_x
	while b.y >= (Const_.FIELD_H + 2) * Bomb_.TILE_H_CP:
		b.y -= span_y
	while b.y < -2 * Bomb_.TILE_H_CP:
		b.y += span_y


## Send a bomb flying to a cell. The flight time comes from the distance and
## the speed, so a bomb crosses ground at the tabulated rate rather than at a
## made-up number of ticks.
func _launch(b: Bomb_, tx: int, ty: int, height: int, speed: int,
		reset_fuze: bool = true) -> void:
	b.fly_from_x = b.x
	b.fly_from_y = b.y
	b.fly_to_x = tx * Bomb_.TILE_W_CP + Bomb_.TILE_W_CP / 2
	b.fly_to_y = ty * Bomb_.TILE_H_CP + Bomb_.TILE_H_CP / 2
	var dist: int = absi(b.fly_to_x - b.fly_from_x) + absi(b.fly_to_y - b.fly_from_y)
	b.fly_ticks = maxi(1, dist / maxi(1, speed))
	b.fly_tick = 0
	b.fly_height = height
	b.flying = true
	b.speed = speed
	# A punched bomb's timer is reset — the notes: "bomb timer is reset when
	# its punched". Only on the punch or the throw itself, NOT on each of the
	# bounces that follow: resetting it every hop meant the fuze could never
	# run down while a bomb was bouncing, which is why the bouncing had to be
	# stopped by an invented three-bounce cap instead of by the bomb going
	# off. VALUELST 661 calls them "subsequent small 1-space punch bounces"
	# and names no count.
	if reset_fuze:
		b.fuze = _fuze_ticks


## The other way round. Also what a chained bomb is told not to fire down: the
## original computes (d + 2) & 3 over its own direction table, at 0x4240FA.
static func _opposite(dir: int) -> int:
	match dir:
		Types_.Dir.UP: return Types_.Dir.DOWN
		Types_.Dir.DOWN: return Types_.Dir.UP
		Types_.Dir.LEFT: return Types_.Dir.RIGHT
		Types_.Dir.RIGHT: return Types_.Dir.LEFT
	return Types_.Dir.NONE


## Kick the bomb a player has walked into. Automatic when they have the kicker;
## returns false if there was nothing to kick.
func kick_bomb(p: Player_) -> bool:
	if not p.can_kick:
		return false
	var step: Vector2i = Types_.DIR_VEC[p.facing]
	var b := bomb_at(p.tile_x() + step.x, p.tile_y() + step.y)
	if b == null:
		return false
	# A MOVING BOMB KICKED THE OTHER WAY SNAPS TO ITS CELL CENTRE FIRST —
	# BM95.EXE 0x42464B, which tests "already moving" against "direction
	# differs" and, when both hold, rewrites the bomb's x and y to the centre
	# of the tile it is on before taking the new direction. Without it a bomb
	# caught mid-cell reverses from wherever it happened to be and spends the
	# rest of its life off the grid, which is the same drift _turn_rolling_bomb()
	# exists to prevent for a jelly turn.
	#
	# The sound follows the original's own condition rather than firing on
	# every kick: it plays when the direction changes or the bomb was at rest,
	# so re-kicking a bomb along the direction it is already rolling is silent.
	var was_moving: bool = b.move_dir != Types_.Dir.NONE
	var changed: bool = b.move_dir != p.facing
	if was_moving and changed:
		b.place_at_tile_centre(b.tile_x(), b.tile_y())
	b.move_dir = p.facing
	b.speed = Values_.V[Const_.Res.KICKED_BOMB_SPEED]
	b.jelly_bounce = p.jelly_bombs
	b.kicked_by = p.slot
	# Long enough to see: KICK.ANI's own sequences are four frames.
	p.kick_ticks = KICK_ANIM_TICKS
	if changed or not was_moving:
		_play(p.slot, Types_.SoundEffect.BOMB_KICK)
	return true


## Stop a bomb this player kicked, where it stands.
##
## MANUAL.BM, on the action button: "if your bomberman has the Kick powerup,
## press the action button to stop a kicked bomb." Nothing did that before, and
## SoundEffect.BOMB_STOP sat unused as the evidence.
func stop_bomb(p: Player_) -> bool:
	if not p.can_kick:
		return false
	for b in bombs:
		if b.detonated or b.flying or b.carried_by >= 0:
			continue
		if b.kicked_by != p.slot or b.move_dir == Types_.Dir.NONE:
			continue
		b.move_dir = Types_.Dir.NONE
		b.speed = 0
		b.kicked_by = -1
		# Left where it stopped rather than snapped to the cell centre: the
		# original's bombs sit where they stop, which is what makes a stopped
		# bomb a hazard in a corridor.
		_play(p.slot, Types_.SoundEffect.BOMB_STOP)
		return true
	return false


## Punch the bomb in front of the player: three cells through the air, then
## one-cell bounces. Resources 660 and 661 are the two arc heights.
func punch_bomb(p: Player_) -> bool:
	if not p.can_punch:
		return false
	var step: Vector2i = Types_.DIR_VEC[p.facing]
	var b := bomb_at(p.tile_x() + step.x, p.tile_y() + step.y)
	if b == null:
		return false
	# Three cells through the air, but no further than the nearest open one —
	# see _landing_cell(). Field bounds are one case of "not open".
	var landing := _landing_cell(b, b.tile_x(), b.tile_y(), p.facing, 3)
	# Compared WRAPPED: the search returns unwrapped coordinates so the flight
	# can leave the arena and come back, so a bomb that went all the way round
	# and found nothing but its own cell reports a landing far off the field
	# that is nonetheless exactly where it started.
	if _wrap_tx(landing.x) == b.tile_x() and _wrap_ty(landing.y) == b.tile_y():
		# Nowhere to fly to — the very next cell was already blocked. Without
		# this the punch played its full animation and sound over a
		# zero-distance _launch() that visibly went nowhere, which read as
		# "the glove doesn't work" even though can_punch and the bomb lookup
		# were both fine.
		return false
	var tx := landing.x
	var ty := landing.y
	b.move_dir = p.facing
	b.jelly_bounce = p.jelly_bombs
	# No longer a limit — the fuze ends the bouncing (see _fly_bomb). Kept at
	# zero so the field, which still travels in a snapshot, means nothing.
	b.bounces_left = 0
	_launch(b, tx, ty, Values_.V[Const_.Res.PUNCH_ARC_BIG],
		Values_.V[Const_.Res.PUNCHED_BOMB_SPEED])
	p.punch_ticks = PUNCH_ANIM_TICKS
	_play(p.slot, Types_.SoundEffect.BOMB_PUNCH)
	return true


## Pick up the bomb under or in front of the player. Its fuze stops while
## carried, and resource 665 says the player pauses 2 frames doing it.
func grab_bomb(p: Player_) -> bool:
	if not p.can_grab:
		return false
	for b in bombs:
		if b.detonated or b.flying or b.carried_by >= 0:
			continue
		if b.owner != p.slot:
			continue
		var step: Vector2i = Types_.DIR_VEC[p.facing]
		var on_me: bool = b.tile_x() == p.tile_x() and b.tile_y() == p.tile_y()
		var in_front: bool = b.tile_x() == p.tile_x() + step.x \
			and b.tile_y() == p.tile_y() + step.y
		if not (on_me or in_front):
			continue
		b.carried_by = p.slot
		b.move_dir = Types_.Dir.NONE
		# A tap grabs it; holding the same button keeps it carried, and
		# LETTING GO THROWS IT — MANUAL.BM: "you may carry a bomb by grabbing
		# and holding down the Drop Bomb button." _check_hold_to_carry() is
		# the other half, called every tick right after this one runs.
		b.hold_required_to_carry = true
		p.pickup_pause = Values_.V[Const_.Res.PICKUP_PAUSE_FRAMES]
		_play(p.slot, Types_.SoundEffect.BOMB_GRAB)
		return true
	return false


## Hold-to-carry's other half. MANUAL.BM: "you may carry a bomb by grabbing
## and holding down the Drop Bomb button" — `grab_bomb()` above is the grab,
## an edge like any other; this is what "holding down" means for a
## simulation that only sees one tick at a time. Called once per player every
## tick, right after `_player_action()`: if this player is carrying a bomb
## and the button is NOT down this tick, letting go THROWS it — the manual's
## own words, "holding down" implies letting go is the release action, and a
## live playtest confirmed that is the mechanic wanted here. A player can
## still throw with an explicit second press without ever releasing first
## (`throw_bomb()` below, `_player_action()`'s own FIRST-while-carrying case);
## either path reaches the same `_throw_carried()`.
func _check_hold_to_carry(p: Player_) -> void:
	if p.action_first_held:
		return
	for b in bombs:
		if b.carried_by != p.slot:
			continue
		if not b.hold_required_to_carry:
			return    # this carry was never a hold — nothing to release
		_throw_carried(p, b)
		return


## Throw the carried bomb. It travels along the four-point curve at resources
## 500..506 — (12,10) (25,20) (25,30) (12,40) — whose last point is 40, which
## is the width of a cell, so the throw reaches three cells ahead.
func throw_bomb(p: Player_) -> bool:
	for b in bombs:
		if b.carried_by != p.slot:
			continue
		_throw_carried(p, b)
		return true
	return false


## The actual launch, shared by throw_bomb() (an explicit second press) and
## _check_hold_to_carry() (letting go of the grab button) — same result
## either way, just a different trigger.
func _throw_carried(p: Player_, b: Bomb_) -> void:
	# Three cells ahead, but no further than the nearest open one — a
	# thrown bomb landing where another bomb already sits was the port's
	# own gap (docs/BUGS.md), not a case _bomb_blocked() left uncovered.
	var landing := _landing_cell(b, p.tile_x(), p.tile_y(), p.facing, 3)
	var tx := landing.x
	var ty := landing.y
	b.carried_by = -1
	b.hold_required_to_carry = false
	b.move_dir = p.facing
	b.jelly_bounce = p.jelly_bombs
	b.bounces_left = 0
	# The GRAB left p.pickup_pause counting down so BPICKUP.ANI could play
	# out. A throw ends that pose — it is the deliberate next action, not
	# an interruption of the pickup — and without this the view's own
	# check for pickup_pause (game_view.gd) outranks the "carrying" check,
	# so a fast grab-then-throw kept drawing the player picking up a bomb
	# that had already left their hands.
	p.pickup_pause = 0
	_launch(b, tx, ty, Values_.V[Const_.Res.PUNCH_ARC_BIG],
		Values_.V[Const_.Res.PUNCHED_BOMB_SPEED])
	_play(p.slot, Types_.SoundEffect.BOMB_THROWN)


## Spooge: place every available bomb in a line ahead of the player, until
## something blocks it. Disabled by having the grab, and vice versa.
func spooge(p: Player_) -> int:
	if not p.can_spooge:
		return 0
	var step: Vector2i = Types_.DIR_VEC[p.facing]
	var placed := 0
	var n := 1
	while p.bombs_available > 0 and n < Const_.FIELD_W:
		var tx := p.tile_x() + step.x * n
		var ty := p.tile_y() + step.y * n
		if not field.is_open(tx, ty) or bomb_at(tx, ty) != null:
			break
		var b: Bomb_ = Bomb_.new()
		b.place_at_tile_centre(tx, ty)
		b.owner = p.slot
		b.chain_owner = p.slot
		b.fuze = _fuze_ticks
		b.placed_tick = tick_count
		b.flame_len = p.flame_len
		bombs.append(b)
		p.bombs_available -= 1
		placed += 1
		n += 1
	if placed > 0:
		# One sound for the line, not one per bomb: SOUNDLST's range is
		# "after laying out a HUGE string of bombs", which is the act and not
		# each bomb in it. The individual BOMB_DROPs are deliberately not
		# raised here for the same reason.
		_play(p.slot, Types_.SoundEffect.SPOOGE)
	return placed


## Detonate every triggerable bomb this player owns. A flying bomb is not
## triggerable — fpc_atomic reached the same rule at its 0.07005.
func trigger_bombs(p: Player_) -> int:
	var fired := 0
	for i in bombs.size():
		var b: Bomb_ = bombs[i]
		if b.detonated or not b.triggered or b.flying:
			continue
		if b.owner != p.slot:
			continue
		b.detonated = true
		_pending.append(i)
		fired += 1
	if fired > 0:
		# Resolve the chain now, so a trigger goes off on the tick it is
		# pressed rather than a tick later.
		var cursor := 0
		while cursor < _pending.size():
			var b: Bomb_ = bombs[_pending[cursor]]
			cursor += 1
			_explode(b)
	return fired


# ---------------------------------------------------------------------------
# Powerups
# ---------------------------------------------------------------------------
func _collect_powerup(p: Player_) -> void:
	var what := field.take_powerup(p.tile_x(), p.tile_y())
	if what == Field_.NO_POWERUP:
		return
	give_powerup(p, what)
	p.pickups += 1

	# A disease is a powerup you did not want, and SOUNDLST gives the two
	# separate ranges — 400 "you get a powerup (a good one)" against 550's
	# "ploppy poop sounds". RANDOM resolves to something else inside
	# give_powerup(), so it is judged by what it turned into, not by its own
	# slot: catch_disease() is what raises the disease's own sound.
	var bad := what == Types_.PowerUp.DISEASE \
		or what == Types_.PowerUp.SUPER_BAD_DISEASE
	_play(p.slot, Types_.SoundEffect.GET_BAD_POWERUP if bad
		else Types_.SoundEffect.GET_GOOD_POWERUP)

	# "you are now AWESOME (7th powerup and 3rd thereafter)" — SOUNDLST's own
	# description of range 1400..1699. The 7th, then the 10th, 13th and so on.
	if p.pickups >= AWESOME_AT and (p.pickups - AWESOME_AT) % AWESOME_EVERY == 0:
		_play(p.slot, Types_.SoundEffect.AWESOME)


## The cap on a powerup, from VALUELST 550..564. Zero there means no limit.
func cap_of(which: int) -> int:
	return Values_.V[Const_.Res.CAP_BASE + which]


func at_cap(p: Player_, which: int) -> bool:
	var cap := cap_of(which)
	return cap > 0 and p.collected[which] >= cap


## Apply one powerup to a player.
##
## Returns false when it had no effect, which for the caps means the powerup is
## consumed and wasted — the original has nowhere to put it back.
func give_powerup(p: Player_, which: int) -> bool:
	# A fresh powerup can cure a disease: VALUELST 124 enables it and 125 makes
	# it a 1-in-10 chance. Rolled before the powerup is applied, so a cure and
	# a new disease in the same pickup cannot cancel each other out.
	if Values_.V[Const_.Res.DISEASE_CURABLE] != 0 and p.any_disease():
		if rng.randi_range(1, Values_.V[Const_.Res.DISEASE_CURE_CHANCE]) == 1:
			cure_all(p)

	match which:
		Types_.PowerUp.RANDOM:
			# Becomes some other powerup. Never itself, or a run of randoms
			# could loop.
			var pool: Array[int] = []
			for other in Const_.POWERUP_COUNT:
				if other != Types_.PowerUp.RANDOM:
					pool.append(other)
			return give_powerup(p, pool[rng.randi_range(0, pool.size() - 1)])

		Types_.PowerUp.DISEASE:
			# Counted like any other pickup — VALUELST 122's wording, "will a
			# disease recycle like other powerups when it COMES OUT OF YOU",
			# only makes sense if the game tracks that you took one, and the
			# match statistics need it. repopulate_powerups() is what then
			# declines to put it back.
			p.collected[which] += 1
			return _inflict(p, Types_.ORDINARY_DISEASES)

		Types_.PowerUp.SUPER_BAD_DISEASE:
			# MANUAL.BM: "Gives you up to three (3) diseases simultaneously" —
			# not one, and not the whole 4-item pool either.
			p.collected[which] += 1
			return _inflict_several(p, Types_.SUPER_BAD_DISEASES, 3)

	if at_cap(p, which):
		return false
	p.collected[which] += 1

	match which:
		Types_.PowerUp.BOMB:
			p.bombs_total += 1
			p.bombs_available += 1
		Types_.PowerUp.FLAME:
			p.flame_len += 1
		Types_.PowerUp.GOLDFLAME:
			# Straight to the maximum rather than +1. The cap on FLAME is the
			# maximum, so this is that number and not an invented "infinity".
			p.flame_len = cap_of(Types_.PowerUp.FLAME)
		Types_.PowerUp.SKATE:
			# ADDITIVE, not multiplicative — ORACLE row 3. fpc_atomic scales by
			# 1.1 per skate, which is its own invention.
			p.speed += Values_.V[Const_.Res.SKATE_BONUS]
			p.speed_before_slow = p.speed
		Types_.PowerUp.KICK:
			p.can_kick = true
		Types_.PowerUp.PUNCH:
			p.can_punch = true
			# MANUAL.BM's exclusivity table: "Boxing Glove will drop Trigger."
			_drop_trigger(p)
		Types_.PowerUp.GRAB:
			p.can_grab = true
			# MANUAL.BM: "Blue Hand will drop Spooge."
			p.can_spooge = false
			p.collected[Types_.PowerUp.SPOOGE] = 0
		Types_.PowerUp.SPOOGE:
			p.can_spooge = true
			# MANUAL.BM: "Spooge will drop Blue Hand."
			p.can_grab = false
			p.collected[Types_.PowerUp.GRAB] = 0
		Types_.PowerUp.JELLY:
			p.jelly_bombs = true
			# MANUAL.BM: "Jelly will drop Trigger."
			_drop_trigger(p)
		Types_.PowerUp.TRIGGER:
			# Trigger is exclusive with jelly and punch, and taking it DROPS
			# both — MANUAL.BM's own exclusivity table: "Trigger will drop
			# Jelly and Boxing Glove." (Grab and Spooge are a separate,
			# unrelated exclusive pair, not touched by Trigger.)
			p.jelly_bombs = false
			p.can_punch = false
			p.collected[Types_.PowerUp.JELLY] = 0
			p.collected[Types_.PowerUp.PUNCH] = 0
			# Topping up an existing trigger stock rather than replacing it —
			# VALUELST 0.13003's changelog: "give extra trigger bomb if
			# availibility already exists and a new bomb is taken".
			p.trigger_bombs += p.bombs_total
	return true


## Rebuild everything a player's powerups DERIVE from what they still hold.
##
## give_powerup() applies each one as it arrives, which is right while they only
## ever arrive. VALUELST 670 makes them leave — "what's the minimum number of
## powers you lose when hit on the head?" — and undoing each kind by hand would
## be thirteen inverse rules, several of which do not have one (GOLDFLAME sets
## flame_len to the cap outright, so subtracting one is meaningless).
##
## So the derived values are recomputed from `collected` and the same VALUELST
## numbers a player is born with. Speed is written through `speed_before_slow`
## rather than to `speed`, because Molasses and Crack own `speed` while they
## last and _end_disease() restores it from there.
func recompute_powers(p: Player_) -> void:
	var base_bombs: int = Values_.V[Const_.Res.BORN_WITH_BASE
		+ Types_.PowerUp.BOMB]
	var base_flame: int = Values_.V[Const_.Res.BORN_WITH_BASE
		+ Types_.PowerUp.FLAME]
	var spent: int = p.bombs_total - p.bombs_available
	p.bombs_total = maxi(1, base_bombs + p.collected[Types_.PowerUp.BOMB])
	p.bombs_available = clampi(p.bombs_total - maxi(spent, 0), 0,
		p.bombs_total)
	if p.collected[Types_.PowerUp.GOLDFLAME] > 0:
		p.flame_len = cap_of(Types_.PowerUp.FLAME)
	else:
		p.flame_len = maxi(1, base_flame + p.collected[Types_.PowerUp.FLAME])
	var speed: int = Values_.V[Const_.Res.START_SPEED] \
		+ p.collected[Types_.PowerUp.SKATE] \
			* int(Values_.V[Const_.Res.SKATE_BONUS])
	var was := p.speed_before_slow
	p.speed_before_slow = speed
	if p.speed == was:
		# Not under a speed disease, so the live value moves with it.
		p.speed = speed
	p.can_kick = p.collected[Types_.PowerUp.KICK] > 0
	p.can_punch = p.collected[Types_.PowerUp.PUNCH] > 0
	p.can_grab = p.collected[Types_.PowerUp.GRAB] > 0
	p.can_spooge = p.collected[Types_.PowerUp.SPOOGE] > 0
	p.jelly_bombs = p.collected[Types_.PowerUp.JELLY] > 0
	if p.collected[Types_.PowerUp.TRIGGER] <= 0:
		p.trigger_bombs = 0


## Jelly and punch are dropped when trigger is taken, and vice versa —
## MANUAL.BM's exclusivity table.
func _drop_trigger(p: Player_) -> void:
	p.trigger_bombs = 0
	p.collected[Types_.PowerUp.TRIGGER] = 0


# ---------------------------------------------------------------------------
# Diseases
# ---------------------------------------------------------------------------
func _inflict(p: Player_, pool: Array) -> bool:
	if pool.is_empty():
		return false
	return catch_disease(p, pool[rng.randi_range(0, pool.size() - 1)])


## Infect with up to `count` distinct diseases from `pool`, at random and
## without repeats — SUPER_BAD_DISEASE's "up to three simultaneously" rather
## than DISEASE's one. Returns true if at least one took (a player who
## already has all of them catches nothing new).
func _inflict_several(p: Player_, pool: Array, count: int) -> bool:
	# Fisher-Yates over the sim's own `rng`, not Array.shuffle()'s global one —
	# this has to stay reproducible for replay/netplay determinism the same
	# way every other roll in this file is.
	var shuffled: Array = pool.duplicate()
	for i in range(shuffled.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = shuffled[i]
		shuffled[i] = shuffled[j]
		shuffled[j] = tmp
	var caught := false
	for i in mini(count, shuffled.size()):
		if catch_disease(p, shuffled[i]):
			caught = true
	return caught


## Give a player a disease. Returns false if they already had it.
func catch_disease(p: Player_, disease: int) -> bool:
	if p.has_disease(disease):
		return false
	p.disease_ticks[disease] = disease_duration(disease)
	p.disease_freshness = 0
	if disease == Types_.Disease.MOLASSES:
		p.speed_before_slow = p.speed
		p.speed = maxi(1, p.speed - Values_.V[Const_.Res.CLOG_PENALTY])
	elif disease == Types_.Disease.CRACK or disease == Types_.Disease.CRACK_POOPS:
		p.speed_before_slow = p.speed
		p.speed += Values_.V[Const_.Res.SKATE_BONUS]
	elif disease == Types_.Disease.SWAP_PLAYERS:
		# One-shot on infection, not a state that lasts the disease's own
		# duration — `types.gd`'s own comment on the enum says "swaps places
		# with another player", not "keeps swapping". The duration slot still
		# counts down like any other disease (VALUELST gives it one, and
		# passing it on by contact still needs `has_disease()` to read true
		# for a while), it just has nothing further to DO once it has fired.
		_swap_places(p)
	_play(p.slot, Types_.SoundEffect.DISEASE_CAUGHT, disease)
	return true


## SWAP_PLAYERS' effect: trade tile positions with another random LIVE
## player. No resource or disassembly pins the mechanic beyond the enum's own
## "swaps places with another player" — fpc_atomic's unfinished
## `dSwitchBomberman` ("not stored, because it's never taken back") agrees
## this is a one-shot rather than a lasting state, which is the one point of
## corroboration; the swap itself (positions, not control) is this port's
## own reading of "swap 2 players", the disc's own name for it.
func _swap_places(p: Player_) -> void:
	var others: Array[Player_] = []
	for other in players:
		if other != p and other.in_play and other.alive and not other.dying:
			others.append(other)
	if others.is_empty():
		return
	var other: Player_ = others[rng.randi_range(0, others.size() - 1)]
	var p_tile := Vector2i(p.tile_x(), p.tile_y())
	var other_tile := Vector2i(other.tile_x(), other.tile_y())
	p.place_at_tile_centre(other_tile.x, other_tile.y)
	other.place_at_tile_centre(p_tile.x, p_tile.y)


## How long a disease lasts, in ticks.
##
## VALUELST holds NINE duration slots (130..138) for TWELVE diseases, and which
## name maps to which slot is not established — docs/BUGS.md Q1. All nine hold
## 300, so this is currently exact for every disease whatever the mapping is;
## the modulo keeps it in range and is the one line to revisit if a slot is
## ever re-tuned.
func disease_duration(disease: int) -> int:
	var slot: int = disease % Const_.DISEASE_DURATION_SLOTS
	return Values_.V[Const_.Res.DISEASE_DURATION_BASE + slot]


func cure_all(p: Player_) -> void:
	for d in Types_.DISEASE_COUNT:
		if p.disease_ticks[d] > 0:
			_end_disease(p, d)


func _end_disease(p: Player_, disease: int) -> void:
	p.disease_ticks[disease] = 0
	if disease == Types_.Disease.MOLASSES or disease == Types_.Disease.CRACK \
			or disease == Types_.Disease.CRACK_POOPS:
		p.speed = p.speed_before_slow


## No resource or disassembly gives LEPROSY's drop rate — types.gd's own
## comment on the enum is the only thing that says what it does at all
## ("powerups fall off as you walk"), and it names no number. This port's
## own guess, the same way the closing wall's ticks-per-cell is a flagged
## guess a few functions over: about one drop every four seconds of walking
## at 20 Hz, which is often enough to matter and rare enough not to strip a
## player bare in one lap of the field.
const LEPROSY_DROP_CHANCE := 80

func _tick_diseases() -> void:
	if Values_.V[Const_.Res.DISEASE_TIME_LIMITED] == 0:
		return
	for p in players:
		if not p.alive:
			continue
		p.disease_freshness += 1
		if p.has_disease(Types_.Disease.LEPROSY) and p.move != Types_.MoveState.STILL \
				and rng.randi_range(1, LEPROSY_DROP_CHANCE) == 1:
			_leprosy_drop(p)
		for d in Types_.DISEASE_COUNT:
			if p.disease_ticks[d] <= 0:
				continue
			p.disease_ticks[d] -= 1
			if p.disease_ticks[d] == 0:
				_end_disease(p, d)


## One powerup falls off, onto the field, the way a punch to the head scatters
## one — same call, same "not diseases, they don't recycle" exclusion.
func _leprosy_drop(p: Player_) -> void:
	var held: Array[int] = []
	for which in Const_.POWERUP_COUNT:
		if which == Types_.PowerUp.DISEASE or which == Types_.PowerUp.SUPER_BAD_DISEASE:
			continue
		if p.collected[which] > 0:
			held.append(which)
	if held.is_empty():
		return
	var which: int = held[rng.randi_range(0, held.size() - 1)]
	p.collected[which] -= 1
	field.scatter_powerup(which, rng)
	recompute_powers(p)


## Pass a disease on by contact. Whether it MULTIPLIES or hands off is
## VALUELST 123, which says multiply — the giver keeps it.
##
## The freshness lock (resource 129, 10 frames) is what stops one contact
## passing a disease several times in consecutive ticks.
func spread_disease(from: Player_, to: Player_) -> bool:
	if from.disease_freshness < Values_.V[Const_.Res.DISEASE_FRESHNESS]:
		return false
	var passed := false
	for d in from.active_diseases():
		if catch_disease(to, d):
			passed = true
			if Values_.V[Const_.Res.DISEASE_MULTIPLIES] == 0:
				_end_disease(from, d)
	return passed


## Scatter a dead player's powerups back onto the field.
##
## VALUELST 122 says diseases do NOT recycle, so only the ordinary powerups
## come back. fpc_atomic does the same at its 0.07004 ("Respawn collected
## powerups of dead player").
func repopulate_powerups(p: Player_) -> int:
	var returned := 0
	for which in Const_.POWERUP_COUNT:
		# The two disease powerups are skipped: VALUELST 122 says a disease
		# does not recycle when it leaves a player.
		if which == Types_.PowerUp.DISEASE \
				or which == Types_.PowerUp.SUPER_BAD_DISEASE:
			continue
		for _i in p.collected[which]:
			if field.scatter_powerup(which, rng):
				returned += 1
		p.collected[which] = 0
	return returned


# ---------------------------------------------------------------------------
# Hashing
# ---------------------------------------------------------------------------
## FNV-1a over the whole simulation state, 64-bit.
##
## The parity primitive. Phase 5 asserts client and server agree on it every
## broadcast; Track C diffs it against the C oracle per tick. Anything that can
## diverge must be in here — a field left out is a divergence no test can see,
## which is why players and bombs contribute their full byte records rather
## than a summary.
##
## Bombs are sorted by cell first. Two engines that place the same bombs in a
## different array order are not diverging, and a hash that said they were
## would be a hash nobody trusts.
func state_hash() -> int:
	var buf := PackedByteArray()
	Player_._append_i32(buf, tick_count)
	# The ROUND state belongs in the hash too. It was left out at first, and
	# tests/test_net.gd caught it: a client whose clock, Hurry wall, outcome or
	# winner had desynced would have hashed identical to the server, which is
	# exactly the failure the netcode's equality assertion exists to catch.
	Player_._append_i32(buf, time_left)
	Player_._append_i32(buf, hurry_index)
	buf.append(outcome)
	buf.append(clampi(winner_slot + 1, 0, 255))
	buf.append(clampi(winner_team + 1, 0, 255))
	buf.append(int(team_play))
	buf.append_array(field.to_bytes())
	# The level geometry is hashed but never sent per tick: it cannot change,
	# and both sides derive it from the level and the seed. Hashing it is what
	# proves they derived the same thing.
	buf.append_array(field.static_bytes())

	var slots := []
	for p in players:
		slots.append(p)
	slots.sort_custom(func(a, b): return a.slot < b.slot)
	for p in slots:
		buf.append_array(p.to_bytes())

	var ordered := bombs.duplicate()
	ordered.sort_custom(func(a, b):
		return (a.y * Const_.FIELD_W + a.x) < (b.y * Const_.FIELD_W + b.x))
	for b in ordered:
		buf.append_array(b.to_bytes())

	return fnv1a(buf)


# FNV-1a's 64-bit offset basis is 0xCBF29CE484222325 = 14695981039346656037,
# which does not fit in a GDScript int — those are SIGNED 64-bit, and Godot
# rejects the hex literal outright with "Cannot represent ... as a 64-bit
# signed integer". Written here as the same bit pattern reinterpreted as
# signed, which is what the arithmetic below needs: the multiply wraps modulo
# 2^64 either way, so the resulting hash is standard FNV-1a.
#
# This was silently broken first: the rejected literal left the constant at a
# wrong value, and every test still passed because they only asserted that the
# hash CHANGES, never what it is. test_sim.gd now pins a known digest.
const FNV_OFFSET := -3750763034362895579   # 0xCBF29CE484222325 as int64
const FNV_PRIME := 0x100000001B3           # 1099511628211, fits signed


static func fnv1a(data: PackedByteArray) -> int:
	var h: int = FNV_OFFSET
	for byte in data:
		h ^= byte
		h *= FNV_PRIME
	return h


# ---------------------------------------------------------------------------
# Campaign mode: rovers and ghosts
# ---------------------------------------------------------------------------
#
# The two resources that govern them are 1200 ("chance that a ghost or rover
# will change directions at an intersection", 1-in-3) and 1205 ("chance that
# the direction change will NOT towards a human", 1-in-3). Everything else is
# this port's, and scripts/sim/creature.gd lists what and why.


## Put a creature on the field. Campaign stages say how many and how fast; the
## caller picks the cells, because "where" is a property of the scheme rather
## than of the creature.
func add_creature(kind: int, tx: int, ty: int, speed: int) -> RefCounted:
	var c: Creature_ = Creature_.new()
	c.kind = kind
	c.speed = speed
	c.place_at_tile_centre(tx, ty)
	c.facing = Creature_.DIRECTIONS[rng.randi_range(
		0, Creature_.DIRECTIONS.size() - 1)]
	creatures.append(c)
	return c


func creature_count(kind: int = -1) -> int:
	var n := 0
	for c in creatures:
		if c.alive and not c.dying and (kind < 0 or c.kind == kind):
			n += 1
	return n


func _tick_creatures() -> void:
	for c in creatures:
		if not c.alive:
			continue
		if c.dying:
			# One tick of dying, then gone — there is no death animation on the
			# disc for these, only the four walking directions.
			c.alive = false
			continue
		_move_creature(c)
		# Flame kills it where it stands, and the kill is scored to whoever
		# owns that flame.
		if field.has_flame(c.tile_x(), c.tile_y()):
			var owner: int = field.flame_owner_at(c.tile_x(), c.tile_y())
			_kill_creature(c, -1 if owner == Field_.NO_OWNER else owner)
			continue
		# Touching a player kills the player. Cell for cell, the way flame
		# does: the notes say flames go through bombermen, and a monster that
		# needs pixel overlap would be a different game from the one the cells
		# describe.
		for p in players:
			if not p.alive or p.dying or not p.in_play:
				continue
			if p.invulnerable > 0 or p.fly_ticks > 0:
				continue
			if p.tile_x() == c.tile_x() and p.tile_y() == c.tile_y():
				kill(p)


func _kill_creature(c: RefCounted, by: int) -> void:
	c.dying = true
	c.death_tick = tick_count
	c.killed_by = by
	if by >= 0 and by < round_score.size():
		round_score[by] += Values_.V[
			Const_.Res.SCORE_ROVER if c.kind == Creature_.Kind.ROVER
			else Const_.Res.SCORE_GHOST]
		if by < round_kills.size():
			round_kills[by] += 1
	_play(by, Types_.SoundEffect.PLAYER_DIED)


## One creature's step. It walks in a straight line until the cell ahead is
## closed to it, and at an intersection it may turn anyway — 1-in-1200.
func _move_creature(c: RefCounted) -> void:
	var ahead: Vector2i = Types_.DIR_VEC[c.facing]
	var at_centre: bool = (c.x % Player_.TILE_W_CP == Player_.TILE_W_CP / 2) \
		and (c.y % Player_.TILE_H_CP == Player_.TILE_H_CP / 2)

	if at_centre:
		var options := _creature_options(c)
		if options.is_empty():
			return                      # boxed in; nothing to do but wait
		var blocked: bool = not c.can_enter(field, c.tile_x() + ahead.x,
			c.tile_y() + ahead.y)
		var turning: bool = blocked
		if not turning and options.size() > 1:
			# Resource 1200: at a junction it may turn for no reason at all.
			turning = rng.randi_range(1,
				Values_.V[Const_.Res.CREATURE_TURN_CHANCE]) == 1
		if turning:
			c.facing = _creature_choose(c, options)
			ahead = Types_.DIR_VEC[c.facing]
		if not c.can_enter(field, c.tile_x() + ahead.x, c.tile_y() + ahead.y):
			return

	c.x += ahead.x * c.speed
	c.y += ahead.y * c.speed


## The directions this creature could take from the cell it is standing on.
func _creature_options(c: RefCounted) -> Array[int]:
	var out: Array[int] = []
	for dir in Creature_.DIRECTIONS:
		var step: Vector2i = Types_.DIR_VEC[dir]
		if c.can_enter(field, c.tile_x() + step.x, c.tile_y() + step.y):
			out.append(dir)
	return out


## Which way to turn. Resource 1205 is the chance the choice is NOT toward a
## human — so four times in five it hunts, and the fifth it wanders.
func _creature_choose(c: RefCounted, options: Array[int]) -> int:
	var away: bool = rng.randi_range(1,
		Values_.V[Const_.Res.CREATURE_AWAY_CHANCE]) == 1
	if away:
		return options[rng.randi_range(0, options.size() - 1)]

	var target := _nearest_player_cell(c)
	if target.x < 0:
		return options[rng.randi_range(0, options.size() - 1)]

	var best: int = options[0]
	var best_d: int = 1 << 30
	for dir in options:
		var step: Vector2i = Types_.DIR_VEC[dir]
		var d: int = absi(c.tile_x() + step.x - target.x) \
			+ absi(c.tile_y() + step.y - target.y)
		if d < best_d:
			best_d = d
			best = dir
	return best


func _nearest_player_cell(c: RefCounted) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_d: int = 1 << 30
	for p in players:
		if not p.alive or p.dying or not p.in_play:
			continue
		var d: int = absi(p.tile_x() - c.tile_x()) + absi(p.tile_y() - c.tile_y())
		if d < best_d:
			best_d = d
			best = Vector2i(p.tile_x(), p.tile_y())
	return best
