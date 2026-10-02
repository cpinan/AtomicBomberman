# The client. Sends input, renders what it is told, simulates nothing.
#
# It holds a Sim object, but only as a container for the state the server sends
# — tick() is never called on it. That is what makes the netcode verifiable:
# the client's state_hash() must equal the server's, and since the client
# cannot have computed anything, any difference is a transport or format bug.
#
# It also means the renderer needed no changes at all. game_view.gd reads a Sim;
# whether that Sim was ticked locally or filled in from a packet is not its
# business.
extends RefCounted

const Const_ := preload("res://scripts/core/const.gd")
const Types_ := preload("res://scripts/core/types.gd")
const Scheme_ := preload("res://scripts/core/scheme.gd")
const Sim_ := preload("res://scripts/sim/sim.gd")
const Match_ := preload("res://scripts/core/match.gd")
const Protocol_ := preload("res://scripts/net/protocol.gd")
const Snapshot_ := preload("res://scripts/net/snapshot.gd")
const Stats_ := preload("res://scripts/core/stats.gd")

## The statistics counters, or null. Set by the caller; see scripts/core/stats.gd.
var stats = null

signal welcomed(slot: int)
signal rejected(code: int, reason: String)
signal round_finished(outcome: int, winner_slot: int)
signal sound(slot: int, effect: int, arg: int)
## A new round's field has been built. The view listens so it can re-read the
## level's background and specials.
signal round_started(round_index: int, level: int)
signal match_finished(champion_slot: int, champion_team: int)
signal slot_overridden(slot: int, now_ai: bool)
## The lobby roster changed — a peer joined or left, or this client just
## learned it's the host. Fires on every S_LOBBY, so a screen can just redraw
## `lobby_roster` each time rather than diffing anything itself.
signal lobby_updated()
## A won match is over and the server has reopened the room. `the_match` still
## holds the result that ended it — the next S_WELCOME replaces it — so a
## screen can say who won while everybody waits for the next one.
signal returned_to_lobby()

enum State { IDLE, CONNECTING, JOINING, WAITING, PLAYING, REFUSED, CLOSED }

var state: int = State.IDLE
var slot: int = -1
var level: int = 0
var team_play: bool = false
var sim: Sim_ = null
var paused: bool = false

## Set from S_LOBBY while State.WAITING — see server.gd's own State.WAITING.
## `lobby_slot` is this client's own slot in the room (not yet a seated
## player: there is no sim to seat it in). `lobby_roster` is an Array of
## {"slot": int, "name": String} for everyone currently in the room,
## including this client itself.
var lobby_slot: int = -1
var lobby_is_host: bool = false
var lobby_roster: Array = []

## The match, as the server reports it. Never computed here: a client that
## counted its own wins could disagree about whether the game is over.
var the_match: Match_ = Match_.new()

## The scheme text the server sent, kept so a new round can be rebuilt from it
## without asking for it again.
var scheme_text: String = ""

## The last tick the server sent. Reported back so the server can tell how far
## behind we are — it is the only number we volunteer, and the server treats it
## as information, never as instruction.
var server_tick: int = 0

var name: String = "player"
var reject_reason: String = ""

var _peer := WebSocketMultiplayerPeer.new()
var _sent_hello: bool = false
var _url: String = ""
var _snapshots: int = 0


func connect_to(url: String, player_name: String) -> bool:
	name = player_name
	_url = url
	var err := _peer.create_client(url)
	if err != OK:
		reject_reason = "cannot connect to %s: %s" % [url, error_string(err)]
		state = State.REFUSED
		return false
	state = State.CONNECTING
	return true


func close() -> void:
	_peer.close()
	state = State.CLOSED


func poll() -> void:
	_peer.poll()
	var status := _peer.get_connection_status()

	if status == MultiplayerPeer.CONNECTION_DISCONNECTED:
		if state == State.PLAYING or state == State.JOINING \
				or state == State.WAITING:
			state = State.CLOSED
		elif state == State.CONNECTING:
			# Never got as far as a socket: nothing listening, no route, a
			# firewall. This used to sit in CONNECTING forever, which on
			# screen is a join that silently never happens.
			reject_reason = "nothing answered at %s" % _url
			state = State.REFUSED
			rejected.emit(-1, reject_reason)
		return

	if status == MultiplayerPeer.CONNECTION_CONNECTED and not _sent_hello:
		_sent_hello = true
		state = State.JOINING
		_send(Protocol_.hello(name))

	while _peer.get_available_packet_count() > 0:
		var packet := _peer.get_packet()
		if stats != null:
			stats.bump(Stats_.C.PACKETS_IN)
			stats.bump(Stats_.C.BYTES_IN, packet.size())
		var msg := Protocol_.decode(packet)
		if msg.is_empty():
			continue
		_handle(msg)


func _handle(msg: Dictionary) -> void:
	match msg["id"]:
		Protocol_.S_LOBBY:
			# Before the first round: still waiting for the host. After one:
			# the match was won and the server has reopened the room
			# (server.gd's _back_to_lobby()). The server only ever sends this
			# while it is WAITING, so arriving mid-PLAYING means exactly that,
			# and the sim goes — there is no round left for it to show, and
			# game_view.gd draws the lobby only when it has no sim.
			var was_playing := state == State.PLAYING
			state = State.WAITING
			if was_playing:
				sim = null
				slot = -1
				paused = false
				returned_to_lobby.emit()
			lobby_slot = int(msg["your_slot"])
			lobby_is_host = bool(msg["is_host"])
			lobby_roster = msg["roster"]
			lobby_updated.emit()

		Protocol_.S_WELCOME:
			slot = int(msg["slot"])
			level = int(msg["level"])
			team_play = bool(msg["team_play"])
			# The scheme arrives as text, so a browser needs no local copy of
			# the original's SCHEMES folder.
			var scheme: Scheme_ = Scheme_.new()
			if not scheme.parse_text(String(msg["scheme"]), "<from server>"):
				reject_reason = "the server sent a scheme we cannot read: %s" \
					% scheme.error()
				state = State.REFUSED
				return
			sim = Sim_.new()
			sim.team_play = team_play
			sim.level = level
			var slots := []
			for i in Const_.PLAYER_COUNT:
				slots.append({"slot": i, "team": Const_.default_team(i)})
			# setup() here only shapes the containers; every field is about to
			# be overwritten by the first snapshot. The seed is the server's so
			# that anything not yet on the wire still matches.
			sim.setup(scheme, slots, int(msg["seed"]))
			scheme_text = String(msg["scheme"])
			# A fresh match, whether this is the first or one started again
			# from the lobby. The S_MATCH right behind this fills it in; the
			# old one still said who won the last match.
			the_match = Match_.new()
			state = State.PLAYING
			welcomed.emit(slot)
			_send(Protocol_.ready())

		Protocol_.S_SNAPSHOT:
			if sim == null:
				return
			if Snapshot_.apply(sim, msg["body"]):
				server_tick = int(msg["tick"])
				_snapshots += 1

		Protocol_.S_SOUNDS:
			for e in msg.get("events", []):
				sound.emit(int(e["slot"]), int(e["effect"]),
					int(e.get("arg", 0)))

		Protocol_.S_MATCH:
			apply_match_state(msg)

		Protocol_.S_ROUND_OVER:
			round_finished.emit(int(msg["outcome"]), int(msg["winner_slot"]))

		Protocol_.S_PAUSE:
			paused = bool(msg["paused"])

		Protocol_.S_SLOT_OVERRIDDEN:
			slot_overridden.emit(int(msg["slot"]), bool(msg["now_ai"]))

		Protocol_.S_REJECT:
			var code := int(msg["code"])
			reject_reason = Protocol_.REJECT_TEXT.get(code, "refused")
			state = State.REFUSED
			rejected.emit(code, reject_reason)


## Take the server's word for the score, and rebuild the field if this names a
## round we are not playing yet.
##
## WHY REBUILD AT ALL. Everything a snapshot carries is overwritten every tick,
## so most of a round change needs nothing here. What a snapshot does NOT carry
## is the static geometry — arrows, warps, conveyors, trampolines, the regrowth
## and ice values — because both sides derive it from the LEVEL and it would
## otherwise be 660 bytes of unchanging bytes on every packet. So the level
## travels with the score, and a level that changed has to be rebuilt from.
##
## Today the server keeps one level for a whole match, which makes this path a
## no-op in practice and is why tests/test_net.gd drives it directly with a
## message naming a different level rather than waiting for the server to send
## one. It stops being a no-op the moment a match rotates levels.
##
## Public so that test can call it: it is otherwise only reached from _handle().
func apply_match_state(msg: Dictionary) -> void:
	var index := int(msg["round_index"])
	var seed_value := int(msg["seed"])
	var fresh := sim != null and (index != the_match.round_index
		or seed_value != the_match.round_seed
		or int(msg["level"]) != level)

	the_match.round_index = index
	the_match.round_seed = seed_value
	the_match.level = int(msg["level"])
	the_match.wins_to_win = int(msg["wins_to_win"])
	the_match.champion_slot = int(msg["champion_slot"])
	the_match.champion_team = int(msg["champion_team"])
	the_match.team_play = team_play
	the_match.wins = msg["wins"]
	the_match.team_wins = msg["team_wins"]

	if fresh:
		level = the_match.level
		sim.level = level
		var scheme: Scheme_ = Scheme_.new()
		if scheme.parse_text(scheme_text, "<from server>"):
			var slots := []
			for i in Const_.PLAYER_COUNT:
				slots.append({"slot": i, "team": Const_.default_team(i)})
			sim.setup(scheme, slots, seed_value)
		round_started.emit(index, level)

	if the_match.over():
		match_finished.emit(the_match.champion_slot, the_match.champion_team)


## Send this frame's input. Called once per rendered frame rather than per
## simulation tick: the server is the clock, and sending more often than the
## server ticks only costs bandwidth.
func send_input(move: int, action: int, first_held: bool = false) -> void:
	if state != State.PLAYING:
		return
	_send(Protocol_.input(server_tick, move, action, first_held))


func send_heartbeat() -> void:
	if state == State.PLAYING:
		_send(Protocol_.heartbeat(server_tick))


func playing() -> bool:
	return state == State.PLAYING and sim != null


## Waiting in a lobby room — connected, seated in the roster, no round
## running yet. A screen uses this to know whether to draw the lobby (roster,
## room code, a Start item if `lobby_is_host`) instead of gameplay or a bare
## "connecting" spinner.
func in_lobby() -> bool:
	return state == State.WAITING


## Ask the server to begin the round. Only the host's C_START is honoured —
## server.gd silently ignores it from anyone else — so this is safe to expose
## unconditionally rather than gating it on `lobby_is_host` here too.
func request_start() -> void:
	if state == State.WAITING:
		_send(Protocol_.start())


func snapshots_applied() -> int:
	return _snapshots


func _send(data: PackedByteArray) -> void:
	if stats != null:
		stats.bump(Stats_.C.PACKETS_OUT)
		stats.bump(Stats_.C.BYTES_OUT, data.size())
	_peer.set_target_peer(MultiplayerPeer.TARGET_PEER_BROADCAST)
	_peer.put_packet(data)
