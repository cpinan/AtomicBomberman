# The authoritative server. Owns the only real simulation.
#
# Headless by design: it draws nothing, loads no art, and needs no GPU. That is
# what lets it run in a container next to a static file server, which is how
# "people mounting their own server" is meant to work (docs/PLAN.md Phase 6).
#
# WebSocket rather than raw TCP, because a browser cannot open a TCP socket.
# fpc_atomic uses TCP and is therefore desktop-only; this is the one place the
# port must diverge from it to reach the web at all.
#
# ---------------------------------------------------------------------------
# WHAT IT DOES AND DOES NOT TRUST
# ---------------------------------------------------------------------------
# A client sends its name once and its input every tick. Nothing else is
# believed: not its tick number, not its position, not whether it thinks it
# died. Every message is length-checked by Protocol.decode() before it is
# looked at, and an unparseable one is dropped rather than acted on — a server
# a stranger can crash is a server nobody will host.
extends RefCounted

const Const_ := preload("res://scripts/core/const.gd")
const Types_ := preload("res://scripts/core/types.gd")
const Values_ := preload("res://scripts/core/values.gd")
const Scheme_ := preload("res://scripts/core/scheme.gd")
const Sim_ := preload("res://scripts/sim/sim.gd")
const Match_ := preload("res://scripts/core/match.gd")
const Protocol_ := preload("res://scripts/net/protocol.gd")
const Snapshot_ := preload("res://scripts/net/snapshot.gd")
const Stats_ := preload("res://scripts/core/stats.gd")
const Discovery_ := preload("res://scripts/net/discovery.gd")

## The statistics counters, or null. Set by the caller; see scripts/core/stats.gd.
var stats = null

## The LAN beacon — MESSAGES.TXT 60-66's screen needs something to list, and a
## WebSocket cannot be discovered. scripts/net/discovery.gd says what this is
## and that the protocol is the port's own invention.
var beacon: Discovery_ = null

## The name this server shouts. MESSAGES.TXT 66 calls it a nodename.
var beacon_name: String = "bomberman"


## Start shouting on the LAN so a client's game list can find this server.
func announce(server_name: String = "") -> bool:
	if not server_name.is_empty():
		beacon_name = server_name
	beacon = Discovery_.new()
	if not beacon.serve(port, beacon_name):
		push_warning("no LAN beacon: %s" % beacon.error)
		beacon = null
		return false
	return true

## How far behind a client may fall before everyone waits for it.
##
## fpc_atomic uses 800 ms and its comment says it had to raise the figure twice
## — once for slow machines, once for internet play. 800 ms at 20 Hz is 16
## ticks, and the same reasoning applies, so the same number.
const SYNC_TOLERANCE_TICKS := 16

## A client silent for this long is gone. Generous, because a browser tab that
## is merely backgrounded stops sending and should not be kicked for it.
##
## MILLISECONDS, NOT TICKS, and that is the whole point. Silence used to be
## counted in simulation ticks, inside _tick() — which does not run while the
## server is paused. So a client that connected and then went quiet paused the
## game at SYNC_TOLERANCE_TICKS and could never be reaped, because the counter
## that would have reaped it had stopped. One silent socket stalled the server
## for everyone, permanently, and a self-hosted server anybody can reach is
## exactly where that matters. Found by leaving a probe connected.
const TIMEOUT_MS := 30 * 1000

signal player_joined(slot: int, name: String)
signal player_left(slot: int, name: String)
signal round_finished(outcome: int, winner_slot: int)
signal match_finished(champion_slot: int, champion_team: int)

var sim: Sim_ = null
var the_match: Match_ = null
var scheme: Scheme_ = null
var scheme_text: String = ""
var level: int = 0
var round_seed: int = 1
var team_play: bool = false

## Ticks served since the server started, across every round. sim.tick_count
## restarts at zero on a new round, so it answers "how far into this round",
## never "how long has this server been up".
var ticks_served: int = 0

## The options-screen settings this game runs with, applied to every round's
## simulation. Empty means the tuning table's own defaults. See
## scripts/sim/sim.gd on which VALUELST resources are settings.
var settings: Dictionary = {}

## "Lost net players revert to AIs" — MESSAGES.TXT 262, an option the original
## has on its own settings screen. Off by default, which is the behaviour the
## port had before the option existed.
var lost_net_to_ai: bool = false

var listening: bool = false
var port: int = 0
var paused: bool = false

## WAITING: a lobby room, nobody seated, `sim` does not exist yet — everything
## that touches `sim` in `poll()`/`_handle()` is skipped, and a peer joining
## gets S_LOBBY instead of S_WELCOME. PLAYING: the ordinary, always-been-this-
## way behaviour — `listen()` defaults to PLAYING outright unless told to open
## a lobby, so every existing caller (a dedicated server, every current test)
## is unaffected. `docs/BUGS.md`-worthy: `override_slot()`'s own doc comment
## used to say plainly "there is no lobby a host and already-connected clients
## both sit in" — this is that lobby.
enum State { WAITING, PLAYING }
var state: int = State.PLAYING

## Which connected peer may send C_START. The first peer to join a WAITING
## room becomes the host; if they leave before starting, the next remaining
## peer inherits it. -1 means "no lobby is open" (a State.PLAYING server
## never sets this) or "a lobby is open but empty."
var host_peer_id: int = -1

## peer id -> {slot, name, last_tick, silent_ms, ready}
var peers: Dictionary = {}

var _peer := WebSocketMultiplayerPeer.new()
var _accum_ms: float = 0.0
var _log: Array[String] = []

## Ticks since the round ended, counted only while waiting to start the next
## one. Separate from sim.ticks_since_over so that a paused server does not
## advance the intermission.
var _intermission: int = -1

## Ticks since the match was won, or -1. The winning round's field stays up
## for the same wait as an intermission, and then the room goes back to the
## lobby. See _back_to_lobby().
var _match_over_hold: int = -1

## The level the room was opened on, so the next match starts where the first
## one did rather than wherever Random Each Game left the last round.
var _start_level: int = 0

## The bot slots to re-fill when a round restarts. sim is rebuilt per round, so
## without this the bots would vanish after the first one.
var _bots: Array[int] = []


## `lobby`: hold in State.WAITING (a room, roster, no round running) until a
## host peer sends C_START, instead of starting round 1 immediately. Every
## existing caller leaves this false and sees no change at all — a dedicated
## server has no host to press Start, and every current test already assumes
## the round is running the instant `listen()` returns.
func listen(on_port: int, scheme_source: String, on_level: int = 0,
		seed_value: int = 1, teams: bool = false, lobby: bool = false) -> bool:
	scheme_text = scheme_source
	scheme = Scheme_.new()
	if not scheme.parse_text(scheme_source, "<server>"):
		_note("scheme rejected: %s" % scheme.error())
		return false
	level = on_level
	_start_level = on_level
	round_seed = seed_value
	team_play = teams
	the_match = Match_.new()
	the_match.setup(seed_value, on_level, teams)

	# A closed socket frees its seat AT ONCE rather than after TIMEOUT_MS.
	# Without this, a player who closes their browser tab leaves a ghost that
	# holds a slot and — being silent — pauses the game for everybody until it
	# times out thirty seconds later. The timeout still exists, for the tab
	# that stops talking without closing.
	if not _peer.peer_disconnected.is_connected(_release):
		_peer.peer_disconnected.connect(_release)

	var err := _peer.create_server(on_port)
	if err != OK:
		_note("cannot listen on %d: %s" % [on_port, error_string(err)])
		return false
	port = on_port
	listening = true
	if lobby:
		state = State.WAITING
		_note("lobby open on %d, scheme %s — waiting for the host to start"
			% [on_port, scheme.name])
	else:
		state = State.PLAYING
		_start_round()
		_note("listening on %d, scheme %s" % [on_port, scheme.name])
	return true


func close() -> void:
	if listening:
		_peer.close()
		listening = false


func _start_round() -> void:
	if stats != null:
		stats.bump(Stats_.C.GAMES_STARTED)
	sim = Sim_.new()
	sim.stats = stats
	sim.team_play = team_play
	_intermission = -1
	_match_over_hold = -1
	round_seed = the_match.round_seed
	# The level decides the specials, and the client is told it in its welcome
	# so both sides build the same geometry without it ever being sent.
	level = the_match.level
	sim.level = level
	# Slots are assigned as clients join, so a round can start with none and
	# fill up. Every seat exists from the beginning so the field layout does
	# not change when somebody arrives.
	var slots := []
	for i in Const_.PLAYER_COUNT:
		slots.append({"slot": i, "team": Const_.default_team(i)})
	for key in settings:
		sim.set(key, settings[key])
	# Random Start deals the cells out once per MATCH, so every round of the
	# match permutes from the same number. scripts/sim/sim.gd says why.
	sim.start_seed = the_match.first_seed
	sim.setup(scheme, slots, round_seed)
	# Ten seats exist from the start so the field layout does not shift when
	# somebody joins, but none of them is IN PLAY until a client claims it.
	for p in sim.players:
		p.in_play = false
		p.alive = false
	# Re-seat anyone already connected, so a mid-round restart does not orphan
	# the players who are already here.
	for id in peers:
		var seat: Dictionary = peers[id]
		if bool(seat["ready"]):
			_seat(int(seat["slot"]))
	for slot in _bots:
		if not _slot_taken(slot):
			sim.add_bot(slot)
	_broadcast(_match_packet())


## Drive the server forward by real milliseconds. Returns how many ticks ran.
func poll(delta_ms: float) -> int:
	if not listening:
		return 0
	_peer.poll()
	if beacon != null:
		beacon.poll(delta_ms, 0, player_count(), Const_.PLAYER_COUNT)
	# Silence is measured in real time and BEFORE the pause decision, so a
	# client that has stopped talking is dropped even though the pause it
	# caused has stopped the simulation. See TIMEOUT_MS.
	# SILENCE IN A LOBBY IS NORMAL, NOT A FAULT. A client only sends C_INPUT
	# once a round is running and C_HEARTBEAT once it has a sim to be behind
	# on, so a room that is still WAITING hears nothing from anybody — and
	# the reaper below was dropping every peer the moment they had sat in the
	# lobby for TIMEOUT_MS, while their windows were open and connected and
	# still sending C_START.
	#
	# Live, that is what "Enter is not working" was: by the time the host
	# pressed it, the server had already released both of them and
	# host_peer_id was -1, so every C_START was refused in silence:
	#
	#     server: HOST left (slot 0)
	#     server: player2 left (slot 1)
	#     [srv] C_START from 922376940, host_peer_id=-1, state=0
	#
	# A genuinely dead socket in a lobby is still noticed — the peer's own
	# disconnect does that, not this timer.
	if state != State.WAITING:
		for id in peers:
			var seat: Dictionary = peers[id]
			seat["silent_ms"] = float(seat["silent_ms"]) + delta_ms
	_accept_and_drop()
	_receive()

	# A lobby room has no sim to tick and nobody to pause — joins and C_START
	# are the only things that can happen, and _receive() above already
	# handled those for this poll.
	if state == State.WAITING:
		return 0

	# A client too far behind stops the world for everyone. The alternative is
	# letting them play a different game from the one everyone else can see.
	var behind := _worst_lag()
	var want_pause := behind > SYNC_TOLERANCE_TICKS
	if want_pause != paused:
		paused = want_pause
		_broadcast(Protocol_.pause(paused))
		_note("pause %s (worst lag %d ticks)" % [paused, behind])

	if paused:
		return 0

	_accum_ms += delta_ms
	var budget: float = minf(_accum_ms,
		float(Values_.V[Const_.Res.MAX_ADVANCE_MS]))
	_accum_ms = budget
	var ran := 0
	while _accum_ms >= float(Const_.TICK_MS):
		_accum_ms -= float(Const_.TICK_MS)
		_tick()
		ran += 1
		# A tick can end the match and close the round: there is no sim left
		# to tick, and the rest of this budget belongs to nobody.
		if state == State.WAITING:
			_accum_ms = 0.0
			break
	return ran


func _tick() -> void:
	sim.tick()
	ticks_served += 1

	# One snapshot per tick. 20 Hz, not fpc_atomic's 50 over a 100 Hz sim —
	# see scripts/net/protocol.gd on what that costs.
	_broadcast(Protocol_.snapshot(sim.tick_count, Snapshot_.write(sim)))
	if not sim.sounds.is_empty():
		_broadcast(Protocol_.sounds(sim.sounds))

	if sim.round_over() and sim.ticks_since_over == 1:
		_broadcast(Protocol_.round_over(sim.outcome, sim.winner_slot,
			sim.winner_team))
		round_finished.emit(sim.outcome, sim.winner_slot)
		var ended := the_match.record(sim.outcome, sim.winner_slot,
			sim.winner_team, sim.round_kills, _slot_teams())
		_broadcast(_match_packet())
		_note("round over: outcome %d winner %d — %s"
			% [sim.outcome, sim.winner_slot, the_match.summary()])
		if ended:
			match_finished.emit(the_match.champion_slot,
				the_match.champion_team)
			_note("match over: %s" % the_match.summary())
			_match_over_hold = 0
		else:
			_intermission = 0

	# Between rounds. Everyone sees who won for resource 13's three seconds,
	# then the next round takes the field. Held on anyone_dying() as well, the
	# way main.gd's local match is: the round-deciding death is the one
	# everybody is watching, and resource 13 is a minimum, not a deadline.
	if _intermission >= 0:
		_intermission += 1
		if _intermission >= Match_.intermission_ticks() \
				and not sim.anyone_dying():
			the_match.next_round()
			_note("round %d starting, seed %d"
				% [the_match.round_index + 1, the_match.round_seed])
			_start_round()

	# A WON MATCH GOES BACK TO THE ROOM. It used to stop here: the server
	# logged "match over" and kept ticking a finished field forever, with no
	# lobby, no menu and nothing any player could press — reported live as "it
	# gets stuck at the end of the match". Starting another match is still the
	# host's decision, not the server's, so this does not start one; it puts
	# everybody back where that decision is made.
	if _match_over_hold >= 0:
		_match_over_hold += 1
		if _match_over_hold >= Match_.intermission_ticks() \
				and not sim.anyone_dying():
			_back_to_lobby()


## End a won match: the room reopens with everyone still in it, and the host
## can start the next match from there.
##
## Every server does this, a dedicated one included. A dedicated server
## starts its FIRST match at once because nobody is there to press Start, but
## by the end of a match somebody is — `_ensure_host()` names the first peer —
## and an empty room simply waits for its next arrival to host it.
##
## The roster survives intact, slots included, so nobody changes colour
## between matches. Each peer has to C_READY again after the next S_WELCOME,
## exactly as it did the first time.
func _back_to_lobby() -> void:
	var champion := the_match.summary()
	# A new seed, advanced from the last one rather than reused, so the next
	# match is not a replay of this one but the whole session still replays
	# from the seed the room was opened with.
	the_match.setup(Match_._advance(the_match.round_seed), _start_level,
		team_play, the_match.wins_to_win)
	round_seed = the_match.round_seed
	level = the_match.level
	sim = null
	state = State.WAITING
	_intermission = -1
	_match_over_hold = -1
	_accum_ms = 0.0
	if paused:
		paused = false
		_broadcast(Protocol_.pause(false))
	for id in peers:
		var seat: Dictionary = peers[id]
		seat["ready"] = false
		seat["silent_ms"] = 0.0
		seat["last_tick"] = 0
	_ensure_host()
	_broadcast_lobby()
	_note("%s — back to the lobby with %d player(s)" % [champion, peers.size()])


## Drop anyone who has gone quiet for too long. Joining is handled by the
## HELLO that arrives on a new connection, so there is nothing to accept here —
## a peer that connects but never says hello simply never gets a seat, which is
## the right outcome for a port scanner.
func _accept_and_drop() -> void:
	var to_drop: Array = []
	for id in peers:
		var seat: Dictionary = peers[id]
		if float(seat["silent_ms"]) > float(TIMEOUT_MS):
			to_drop.append(id)
	for id in to_drop:
		_release(id)


func _receive() -> void:
	while _peer.get_available_packet_count() > 0:
		var from := _peer.get_packet_peer()
		var data := _peer.get_packet()
		if stats != null:
			stats.bump(Stats_.C.PACKETS_IN)
			stats.bump(Stats_.C.BYTES_IN, data.size())
		var msg := Protocol_.decode(data)
		if msg.is_empty():
			# Unparseable. Dropped in silence: replying would let a stranger
			# use the server to generate traffic.
			continue
		_handle(from, msg)


func _handle(from: int, msg: Dictionary) -> void:
	match msg["id"]:
		Protocol_.C_HELLO:
			_join(from, msg)
		Protocol_.C_START:
			# Before judging who asked: a room with people in it must have a
			# host, and if it has somehow lost one this is the last moment to
			# notice. Live, a lobby reached host_peer_id = -1 with two peers
			# still connected and then refused every C_START — the round
			# could not be started at all and the key looked dead.
			_ensure_host()
			if OS.get_environment("AB_DEBUG_INPUT") != "":
				print("[srv] C_START from %d, host_peer_id=%d, state=%d"
					% [from, host_peer_id, state])
			if from == host_peer_id:
				_begin_from_lobby()
		Protocol_.C_INPUT:
			if sim == null:
				return
			var seat = peers.get(from, null)
			if seat == null:
				return
			seat["last_tick"] = int(msg["tick"])
			seat["silent_ms"] = 0.0
			# The input is applied to THEIR seat and no other, whatever the
			# packet claims — unless the host has overridden that seat to an
			# AI (override_slot()), in which case the bot's own think() drives
			# it now and this peer's packets are accepted (so their connection
			# stays alive and they keep proving they are not silent) but no
			# longer acted on.
			if sim.is_bot(int(seat["slot"])):
				return
			# LATCH THE ACTION UNTIL A TICK CONSUMES IT.
			#
			# A joined client sends its input once per RENDERED FRAME
			# (main.gd's _process) while this server ticks at 20 Hz, so a
			# press arrives as one packet carrying Action.FIRST followed
			# immediately by several carrying NONE. Applying each packet
			# straight to the simulation let those NONEs overwrite the press
			# before any tick had consumed it, and the bomb appeared only when
			# a tick happened to land in the few milliseconds between them —
			# about one press in six at 120 fps. Live, that reads as "there is
			# lag when placing bombs"; the presses are not late, they are
			# gone.
			#
			# So a NONE never clears a pending action; only the tick does,
			# which _player_action() already handles by setting p.action back
			# to NONE once it has acted on it. Movement and the held flag are
			# still taken from every packet, because those ARE states rather
			# than edges and the freshest one is the right one.
			#
			# The local path cannot hit this: _step() calls set_input() once
			# per tick, so an edge is offered exactly once.
			var in_slot := int(seat["slot"])
			var action := int(msg["action"])
			if action == Types_.Action.NONE:
				var seated := sim.player_by_slot(in_slot)
				if seated != null and seated.action != Types_.Action.NONE:
					action = seated.action
			sim.set_input(in_slot, int(msg["move"]), action,
				bool(msg.get("first_held", false)))
		Protocol_.C_HEARTBEAT:
			var seat2 = peers.get(from, null)
			if seat2 != null:
				seat2["last_tick"] = int(msg["tick"])
				seat2["silent_ms"] = 0.0
		Protocol_.C_READY:
			var seat3 = peers.get(from, null)
			if seat3 != null:
				seat3["ready"] = true
				seat3["silent_ms"] = 0.0
				_seat(int(seat3["slot"]))


func _join(from: int, msg: Dictionary) -> void:
	if peers.has(from):
		return
	if int(msg["version"]) != Protocol_.VERSION:
		_send(from, Protocol_.reject(Protocol_.REJECT_VERSION))
		return
	var name: String = msg["name"]
	for id in peers:
		if String(peers[id]["name"]) == name:
			_send(from, Protocol_.reject(Protocol_.REJECT_NAME_TAKEN))
			return

	# WAITING: seat them in the roster, not in the sim — there is no sim yet.
	# S_WELCOME (and the round itself) waits for the host's own C_START.
	if state == State.WAITING:
		var lobby_slot := _free_lobby_slot()
		if lobby_slot < 0:
			_send(from, Protocol_.reject(Protocol_.REJECT_FULL))
			return
		peers[from] = {"slot": lobby_slot, "name": name, "last_tick": 0,
			"silent_ms": 0.0, "ready": false}
		_ensure_host()
		_broadcast_lobby()
		player_joined.emit(lobby_slot, name)
		_note("%s joined the lobby as slot %d" % [name, lobby_slot])
		return

	var slot := _free_slot()
	if slot < 0:
		_send(from, Protocol_.reject(Protocol_.REJECT_FULL))
		return

	peers[from] = {"slot": slot, "name": name, "last_tick": sim.tick_count,
		"silent_ms": 0.0, "ready": false}
	_send(from, Protocol_.welcome(slot, round_seed, level, scheme_text,
		team_play))
	# The snapshot right after the welcome, so the client has a state to render
	# before its first tick rather than a blank field.
	_send(from, Protocol_.snapshot(sim.tick_count, Snapshot_.write(sim)))
	# The score, so a client joining mid-match does not start it at nil-nil.
	_send(from, _match_packet())
	player_joined.emit(slot, name)
	_note("%s joined as slot %d" % [name, slot])


## A seat for a lobby arrival — no sim exists yet to check `is_bot()` against,
## unlike `_free_slot()`, because nobody is seated in anything until the round
## actually starts.
func _free_lobby_slot() -> int:
	var taken := {}
	for id in peers:
		taken[int(peers[id]["slot"])] = true
	for i in Const_.PLAYER_COUNT:
		if not taken.has(i):
			return i
	return -1


func _roster() -> Array:
	var out := []
	for id in peers:
		var seat: Dictionary = peers[id]
		out.append({"slot": int(seat["slot"]), "name": String(seat["name"])})
	return out


func _broadcast_lobby() -> void:
	for id in peers:
		_send(id, Protocol_.lobby(int(peers[id]["slot"]), id == host_peer_id,
			_roster()))


## Called on C_START from the recognised host, while still WAITING. Every
## current peer gets its S_WELCOME now — the same message an immediate-start
## server sends at join time — and then joins the ordinary ready/seat flow via
## its own C_READY, exactly as it always has.
func _begin_from_lobby() -> void:
	if state != State.WAITING:
		return
	for id in peers:
		var seat: Dictionary = peers[id]
		_send(id, Protocol_.welcome(int(seat["slot"]), round_seed, level,
			scheme_text, team_play))
	state = State.PLAYING
	_start_round()
	_note("lobby started: %d player(s)" % peers.size())


## Put a slot into play. A no-op while a lobby is still WAITING — there is no
## sim to seat anyone into yet, and nobody should legitimately be sending
## C_READY before they've been sent S_WELCOME.
func _seat(slot: int) -> void:
	if sim == null:
		return
	var p := sim.player_by_slot(slot)
	if p != null:
		p.in_play = true
		p.alive = true


func _release(id: int) -> void:
	if not peers.has(id):
		return
	var seat: Dictionary = peers[id]
	var slot := int(seat["slot"])
	var p := null if sim == null else sim.player_by_slot(slot)
	if p != null:
		# A player who disconnects mid-round leaves the field rather than
		# standing there. Their powerups scatter, as if they had died.
		p.in_play = false
		p.alive = false
		p.move = Types_.MoveState.STILL
	player_left.emit(slot, String(seat["name"]))
	_note("%s left (slot %d)" % [seat["name"], slot])
	peers.erase(id)
	# MESSAGES.TXT 262's option: a lost net player can become an AI rather than
	# vanishing. OPTIONS.BM: "If this is set to 'NO' they will be dropped out of
	# the game without notice." Off by default, so the seat simply empties.
	if lost_net_to_ai and p != null:
		sim.add_bot(slot)
		if not _bots.has(slot):
			_bots.append(slot)
		_note("slot %d reverts to an AI" % slot)

	if state == State.WAITING:
		# The room outlives whoever happened to open it — the next remaining
		# peer inherits C_START rather than the lobby getting stuck with no
		# one able to start it.
		_ensure_host()
		_broadcast_lobby()


## THE ROOM ALWAYS HAS A HOST WHILE ANYONE IS IN IT.
##
## host_peer_id is whoever may send C_START. It used to be set on the first
## join and patched up on a departure, which left two ways for it to end up
## naming nobody while peers were still connected — and then the lobby was
## stuck: the server refused every C_START and the host's Enter did nothing,
## with no message to say why. Rather than chase which sequence of joins and
## drops produced it, this states the invariant and is called from every
## place that can disturb it: a join, a release, and C_START itself.
func _ensure_host() -> void:
	if peers.is_empty():
		host_peer_id = -1
		return
	if not peers.has(host_peer_id):
		host_peer_id = peers.keys()[0]


## A seat for an arriving player. A bot's seat is fair game — a human turning up
## displaces one rather than being told the game is full.
func _free_slot() -> int:
	var taken := {}
	for id in peers:
		taken[int(peers[id]["slot"])] = true
	for i in Const_.PLAYER_COUNT:
		if not taken.has(i) and not sim.is_bot(i):
			return i
	for i in Const_.PLAYER_COUNT:
		if not taken.has(i):
			sim.bot_slots.erase(i)
			# And forgotten, so the next round does not hand the seat back to
			# a bot the human is sitting in.
			_bots.erase(i)
			_note("a human took bot slot %d" % i)
			return i
	return -1


## How far behind the furthest-behind client is, in ticks.
func _worst_lag() -> int:
	var worst := 0
	for id in peers:
		var seat: Dictionary = peers[id]
		if not bool(seat["ready"]):
			continue
		worst = maxi(worst, sim.tick_count - int(seat["last_tick"]))
	return worst


func _broadcast(data: PackedByteArray) -> void:
	# One packet counted, however many peers it reaches: this layer hands the
	# multiplayer peer a single broadcast and never sees the fan-out, so the
	# counter is "packets this server sent", not "packets that left the NIC".
	if stats != null:
		stats.bump(Stats_.C.PACKETS_OUT)
		stats.bump(Stats_.C.BYTES_OUT, data.size())
	_peer.set_target_peer(MultiplayerPeer.TARGET_PEER_BROADCAST)
	_peer.put_packet(data)


func _send(to: int, data: PackedByteArray) -> void:
	# A PEER WHOSE SOCKET HAS ALREADY GONE is not an error to be shouted
	# about. _release() broadcasts the new roster to whoever is left, and
	# when two people leave at once the second one's socket is closing while
	# that broadcast goes out — put_packet() then logs an engine-level
	# "Condition ready_state != STATE_OPEN is true" for something entirely
	# routine. verify.sh reads those as a suite that died, and it is right to:
	# a real error here would be invisible among them.
	if _peer.get_peer(to) == null \
			or _peer.get_peer(to).get_ready_state() \
				!= WebSocketPeer.STATE_OPEN:
		return
	if stats != null:
		stats.bump(Stats_.C.PACKETS_OUT)
		stats.bump(Stats_.C.BYTES_OUT, data.size())
	_peer.set_target_peer(to)
	_peer.put_packet(data)


## Fill the highest slots with bots, so a host can start a game alone and so a
## half-empty server is still worth joining.
##
## Bots live on the SERVER only. A client is told about them through the same
## snapshots as everyone else and never runs the AI itself, which is what keeps
## the state hashes equal.
## Callable before a lobby room has started (`sim` is null): `_bots` is what
## `_start_round()`/`_begin_from_lobby()` reads to fill the same seats once
## the round actually exists, so recording the slot is all there is to do
## until then.
func add_bots(count: int) -> void:
	var added := 0
	for slot in range(Const_.PLAYER_COUNT - 1, -1, -1):
		if added >= count:
			break
		if _slot_taken(slot) or (sim != null and sim.is_bot(slot)) \
				or (sim == null and _bots.has(slot)):
			continue
		if sim != null:
			sim.add_bot(slot)
		if not _bots.has(slot):
			_bots.append(slot)
		added += 1
	_note("%d bots added" % added)


## Every seat's team, in slot order — what Win Matches By Kill Total needs to
## add a kill to the right side. The server knows it; the match does not.
func _slot_teams() -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize(Const_.PLAYER_COUNT)
	for p in sim.players:
		if p.slot >= 0 and p.slot < out.size():
			out[p.slot] = p.team
	return out


func _match_packet() -> PackedByteArray:
	return Protocol_.match_state(the_match.round_index, the_match.round_seed,
		the_match.level, the_match.wins, the_match.team_wins,
		the_match.wins_to_win, the_match.champion_slot,
		the_match.champion_team)


## Fill exactly these slots with bots. What the menu's ten-slot model needs:
## add_bots(n) can only say "how many", and the menu says "which". Same
## before-the-round-exists case as add_bots() above — sim may be null.
func add_bot_slots(which: Array) -> void:
	for slot in which:
		var i := int(slot)
		if i < 0 or i >= Const_.PLAYER_COUNT or _slot_taken(i):
			continue
		if sim != null:
			sim.add_bot(i)
		if not _bots.has(i):
			_bots.append(i)
	_note("%d bot slots set" % _bots.size())


## INPUT.BM: "'o' or '0' lets the host override a client's player selection."
##
## What the ORIGINAL's own shared pre-game lobby let a host do — reassign any
## seat's type, KEY/AI/JOY/OFF, before the round starts — this port has no
## screen for: a client here never chooses a type at all (the server just
## seats it), and there is no lobby a host and already-connected clients both
## sit in, because listen() starts the round at once. What the architecture
## DOES support, and what this implements, is the one transition that means
## anything server-side once play is under way: a HUMAN seat can be demoted
## to an AI (their connection stays open, `_handle()`'s C_INPUT guard just
## stops acting on it, and `_ai.think()` takes over next tick), and an AI
## seat this created can be freed back to OFF for a new human to claim
## (`_free_slot()` already treats an AI seat as fair game the same way).
##
## Returns true if the slot actually changed. A slot with no peer and no bot
## on it has nothing to override.
func override_slot(slot: int) -> bool:
	# No round, no seats to override: the host's O in a lobby used to reach
	# sim.is_bot() on a null sim.
	if sim == null or slot < 0 or slot >= Const_.PLAYER_COUNT:
		return false
	# is_bot() FIRST. A demoted peer's own record in `peers` is left alone —
	# see the note above on why — so it is still there and would look like
	# "occupied" to the other branch; checking bot status first is what
	# makes a second call on the same slot a TOGGLE rather than a no-op that
	# just re-demotes whoever is still attached.
	if sim.is_bot(slot):
		sim.bot_slots.erase(slot)
		_bots.erase(slot)
		var occupant := _peer_id_for_slot(slot)
		if occupant >= 0:
			# The peer this demoted never disconnected — restoring means
			# handing their own input back, and _handle()'s C_INPUT guard
			# already stops ignoring them the instant is_bot(slot) is
			# false, so there is nothing further to change here.
			_note("host restored slot %d to %s"
				% [slot, String(peers[occupant]["name"])])
		else:
			# A standalone bot (add_bots()/add_bot_slots()), not a demoted
			# human — nobody is waiting to reclaim the seat, so it goes back
			# to OFF, the same as _free_slot() already treats an unclaimed
			# AI seat as open.
			var p := sim.player_by_slot(slot)
			if p != null:
				p.in_play = false
				p.alive = false
			_note("host overrode slot %d back to open" % slot)
		_broadcast(Protocol_.slot_overridden(slot, false))
		return true
	var occupant := _peer_id_for_slot(slot)
	if occupant >= 0:
		sim.add_bot(slot)
		if not _bots.has(slot):
			_bots.append(slot)
		_broadcast(Protocol_.slot_overridden(slot, true))
		_note("host overrode slot %d to AI (was %s)"
			% [slot, String(peers[occupant]["name"])])
		return true
	return false


## The host's own key has no roster cursor to point with — see
## override_slot()'s own note on why no lobby screen exists to put one on —
## so it walks the slots in order and overrides the first one with anything
## to override. Returns the slot changed, or -1 if every slot is already
## empty and not a bot.
func override_next_slot() -> int:
	if sim == null:
		return -1
	for slot in Const_.PLAYER_COUNT:
		if _peer_id_for_slot(slot) >= 0 or sim.is_bot(slot):
			override_slot(slot)
			return slot
	return -1


func _peer_id_for_slot(slot: int) -> int:
	for id in peers:
		if int(peers[id]["slot"]) == slot:
			return id
	return -1


func _slot_taken(slot: int) -> bool:
	for id in peers:
		if int(peers[id]["slot"]) == slot:
			return true
	return false


func player_count() -> int:
	return peers.size()


func ready_count() -> int:
	var n := 0
	for id in peers:
		if bool(peers[id]["ready"]):
			n += 1
	return n


func _note(line: String) -> void:
	_log.append(line)
	print("server: %s" % line)


func log_lines() -> Array[String]:
	return _log
