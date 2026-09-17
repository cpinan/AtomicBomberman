# Finding games on the local network — `MESSAGES.TXT` 60-66's own screen.
#
# ---------------------------------------------------------------------------
# WHAT THE DISC ASKS FOR AND WHAT IT DOES NOT SUPPLY
# ---------------------------------------------------------------------------
# The strings are the original's and they describe a server browser exactly:
#
#     60  "Available net games:"
#     61  "No net games found!"
#     62  "'%s' (%u) (id:%u)"        a name, a count, an id
#     63  "<Empty Server Slot>"
#     65  "Must select a server!"
#     66  "Our Nodename is: '%s'"
#
# What the disc does NOT supply is how a game is found. The original's answer
# was the network layer of 1997 — 620-634 offer IPX, Modem, Serial and TCP/IP,
# and the browser was whatever that layer could enumerate. None of those exist
# here: this port speaks WebSocket, and a WebSocket cannot be discovered.
#
# So the DISCOVERY is this port's, and it is the smallest thing that works: the
# server shouts on a UDP broadcast port every second, and anyone listening
# hears it. That is a port invention and is disclosed as one — the screen is
# the disc's, the protocol behind it is not.
#
# ---------------------------------------------------------------------------
# THE PACKET
# ---------------------------------------------------------------------------
# One line of UTF-8, so it can be read with a packet sniffer and understood:
#
#     AB1 <port> <players>/<seats> <name>
#
# `AB1` is a magic word and a version in three bytes; anything else on the port
# is somebody else's traffic and is ignored. The address a client should join
# is the sender's, which the socket already knows — a server that named its own
# address would be wrong behind every NAT there is.
extends RefCounted

## The port the beacon is broadcast on. Deliberately NOT the game port: a
## server holds 47600 for real players, and this is a different socket with a
## different lifetime.
const BEACON_PORT := 47601

## Three bytes of magic and a version. Bump it when the line changes shape.
const MAGIC := "AB1"

## How often a server shouts, and how long a client remembers having heard it.
## A game that has gone quiet for three beacons is gone.
const BEACON_MS := 1000
const FORGET_MS := 3500


## What one heard server looks like. `address` is where the packet came from,
## which is the only address worth having.
class Found extends RefCounted:
	var address: String = ""
	var port: int = 47600
	var name: String = ""
	var players: int = 0
	var seats: int = 0
	var last_heard_ms: int = 0

	## MESSAGES.TXT 62: "'%s' (%u) (id:%u)" — the name, how many are playing,
	## and an id. The id is the PORT, because that is what tells two servers on
	## one machine apart, and the address is already the row you clicked.
	##
	## The format has one %s and two %u, so it cannot go through String's own
	## formatting in one step without deciding what each stands for. It is
	## filled left to right: name, players, port.
	func row(fmt: String) -> String:
		var text := fmt.replace("%s", name)
		var first := text.find("%u")
		if first >= 0:
			text = text.substr(0, first) + str(players) \
				+ text.substr(first + 2)
		var second := text.find("%u")
		if second >= 0:
			text = text.substr(0, second) + str(port) \
				+ text.substr(second + 2)
		return text

	func url() -> String:
		return "ws://%s:%d" % [address, port]


var error: String = ""

var _socket: PacketPeerUDP = null
var _broadcasting: bool = false
var _since_beacon: float = 0.0

## address:port -> Found
var _seen: Dictionary = {}


## Start shouting. The caller passes what a listener needs to decide whether to
## join: the game port, the server's name, and how full it is.
func serve(game_port: int, server_name: String) -> bool:
	_socket = PacketPeerUDP.new()
	_socket.set_broadcast_enabled(true)
	var err := _socket.set_dest_address("255.255.255.255", BEACON_PORT)
	if err != OK:
		error = "cannot broadcast on %d (%d)" % [BEACON_PORT, err]
		_socket = null
		return false
	_broadcasting = true
	_beacon_port = game_port
	_beacon_name = server_name
	_since_beacon = float(BEACON_MS)
	return true


## Start listening. Nothing is heard until poll() runs.
func listen() -> bool:
	_socket = PacketPeerUDP.new()
	var err := _socket.bind(BEACON_PORT)
	if err != OK:
		error = "cannot listen on %d (%d)" % [BEACON_PORT, err]
		_socket = null
		return false
	_broadcasting = false
	return true


func close() -> void:
	if _socket != null:
		_socket.close()
	_socket = null
	_seen.clear()


## Drive it. `now_ms` is passed in rather than read from a clock so a test can
## age entries without waiting.
func poll(delta_ms: float, now_ms: int, players: int = 0,
		seats: int = 0) -> void:
	if _socket == null:
		return
	if _broadcasting:
		_since_beacon += delta_ms
		if _since_beacon >= float(BEACON_MS):
			_since_beacon = 0.0
			_socket.put_packet(beacon_line(_beacon_port, players, seats,
				_beacon_name).to_utf8_buffer())
		return

	while _socket.get_available_packet_count() > 0:
		var raw := _socket.get_packet()
		var from := _socket.get_packet_ip()
		var found := parse_beacon(raw.get_string_from_utf8(), from)
		if found == null:
			continue
		found.last_heard_ms = now_ms
		_seen["%s:%d" % [found.address, found.port]] = found

	# Forget anything that has stopped shouting.
	for key in _seen.keys():
		var entry: Found = _seen[key]
		if now_ms - entry.last_heard_ms > FORGET_MS:
			_seen.erase(key)


## What is out there, in the order it will be listed: by name, so the list does
## not jump about as packets arrive.
func games() -> Array:
	var out: Array = _seen.values()
	out.sort_custom(func(a, b): return a.name < b.name)
	return out


## The line a server shouts.
static func beacon_line(port: int, players: int, seats: int,
		server_name: String) -> String:
	# The name comes last because it is the only field that can contain a
	# space, and a parser that takes "the rest of the line" cannot be confused
	# by one.
	return "%s %d %d/%d %s" % [MAGIC, port, players, seats, server_name]


## One line back into a Found, or null if it is not ours.
static func parse_beacon(line: String, from: String) -> Found:
	var parts := line.strip_edges().split(" ", false, 3)
	if parts.size() < 4 or parts[0] != MAGIC:
		return null
	var counts := parts[2].split("/")
	if counts.size() != 2:
		return null
	var found := Found.new()
	found.address = from
	found.port = int(parts[1])
	found.players = int(counts[0])
	found.seats = int(counts[1])
	found.name = parts[3]
	if found.port <= 0 or found.port > 65535:
		return null
	return found


var _beacon_port: int = 47600
var _beacon_name: String = "bomberman"
