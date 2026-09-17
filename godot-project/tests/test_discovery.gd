# The network game list — MESSAGES.TXT 60-66 — and the beacon behind it.
#
# The SCREEN is the disc's: 60 "Available net games:", 61 "No net games
# found!", 62 "'%s' (%u) (id:%u)", 65 "Must select a server!". The way a game
# is FOUND is not: the original enumerated whatever IPX or TCP/IP could see in
# 1997, and this port speaks WebSocket, which nothing can enumerate. So the
# beacon is a port invention — scripts/net/discovery.gd says so — and what is
# asserted here is that it works and that it says no when it should.
extends SceneTree

const T_ := preload("res://tests/t.gd")
const Messages_ := preload("res://scripts/core/messages.gd")
const Discovery_ := preload("res://scripts/net/discovery.gd")

## Not the beacon's own port: two suites running at once would collide, and a
## developer machine may have a real server on it.
const TEST_PORT := 47699


func _init() -> void:
	var t := T_.new("discovery")
	_test_the_words_are_the_discs(t)
	_test_the_line(t)
	_test_rejects_rubbish(t)
	_test_the_row(t)
	await _test_over_a_real_socket(t)
	quit(t.finish())


func _test_the_words_are_the_discs(t: T_) -> void:
	t.eq(Messages_.NET_GAMES_AVAILABLE, "Available net games:", "60")
	t.eq(Messages_.NET_GAMES_NONE, "No net games found!", "61")
	t.eq(Messages_.NET_GAME_ROW, "'%s' (%u) (id:%u)", "62")
	t.eq(Messages_.NET_MUST_SELECT, "Must select a server!", "65")
	t.ok(Messages_.NET_OUR_NODENAME.begins_with("Our Nodename"), "66")


func _test_the_line(t: T_) -> void:
	var line := Discovery_.beacon_line(47600, 3, 10, "kitchen table")
	t.eq(line, "AB1 47600 3/10 kitchen table",
		"the beacon is one readable line")

	var back := Discovery_.parse_beacon(line, "192.168.1.20")
	t.ok(back != null, "and parses back")
	t.eq(back.port, 47600, "the game port")
	t.eq(back.players, 3, "how many are playing")
	t.eq(back.seats, 10, "out of how many seats")
	t.eq(back.name, "kitchen table",
		"and a name with a space in it, because the name is the rest of the line")
	t.eq(back.address, "192.168.1.20",
		"the address is where the packet came from, not what it claimed")
	t.eq(back.url(), "ws://192.168.1.20:47600", "which is what you join")


func _test_rejects_rubbish(t: T_) -> void:
	t.ok(Discovery_.parse_beacon("", "1.2.3.4") == null, "an empty line")
	t.ok(Discovery_.parse_beacon("hello there", "1.2.3.4") == null,
		"somebody else's traffic on the same port")
	t.ok(Discovery_.parse_beacon("AB0 47600 1/10 old", "1.2.3.4") == null,
		"a different version of this protocol")
	t.ok(Discovery_.parse_beacon("AB1 47600 1 nope", "1.2.3.4") == null,
		"a count that is not players/seats")
	t.ok(Discovery_.parse_beacon("AB1 0 1/10 zero", "1.2.3.4") == null,
		"port 0")
	t.ok(Discovery_.parse_beacon("AB1 99999 1/10 big", "1.2.3.4") == null,
		"and a port that is not one")


# MESSAGES.TXT 62 has one %s and two %u, and they are name, players, id.
func _test_the_row(t: T_) -> void:
	var found := Discovery_.parse_beacon("AB1 47600 4/10 upstairs", "10.0.0.5")
	t.eq(found.row(Messages_.NET_GAME_ROW), "'upstairs' (4) (id:47600)",
		"the disc's own row, filled in")


# Over a real UDP socket, because a beacon that only works in a unit test is
# not a beacon.
func _test_over_a_real_socket(t: T_) -> void:
	var server: Discovery_ = Discovery_.new()
	var client: Discovery_ = Discovery_.new()

	# The listener binds first: a beacon nobody is listening for is lost.
	if not t.ok(client.listen(), "the client listens: %s" % client.error):
		return
	if not t.ok(server.serve(TEST_PORT, "test server"),
			"the server broadcasts: %s" % server.error):
		client.close()
		return

	# Drive both for a second of make-believe time. The clock is a parameter,
	# so this takes no real time at all beyond the packets themselves.
	var now := 0
	for i in 40:
		server.poll(100.0, now, 2, 10)
		client.poll(100.0, now)
		now += 100
		await process_frame
		var mine := false
		for game in client.games():
			if game.port == TEST_PORT:
				mine = true
		if mine:
			break

	# OURS, not whatever else is shouting. The beacon port is shared and a real
	# game running on this machine broadcasts on it too — which is exactly what
	# happened: a copy of the game left open in another window failed this
	# suite three assertions deep, on a port and a name that were perfectly
	# correct for the server that had sent them.
	var games := client.games()
	var heard = null
	for game in games:
		if game.port == TEST_PORT:
			heard = game
	if not t.ok(heard != null,
			"the client heard our server among %d game(s)" % games.size()):
		t.note("a firewall that blocks UDP broadcast to localhost will do this")
		server.close()
		client.close()
		return
	t.eq(heard.port, TEST_PORT, "on the port the server named")
	t.eq(heard.name, "test server", "with its name")
	t.eq(heard.players, 2, "and how full it was when it shouted")

	# A server that stops shouting drops off the list rather than lingering.
	server.close()
	client.poll(100.0, now + Discovery_.FORGET_MS + 1)
	var still_ours := 0
	for game in client.games():
		if game.port == TEST_PORT:
			still_ours += 1
	t.eq(still_ours, 0,
		"a server that has gone quiet for %d ms is forgotten"
			% Discovery_.FORGET_MS)
	client.close()
