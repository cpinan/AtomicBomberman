# Server and clients over real WebSockets, in one process.
#
# THE ASSERTION THAT MATTERS: every client's state_hash() equals the server's on
# every snapshot it applies. Since a client never ticks its own simulation, any
# difference is a transport or format bug and nothing else — there is no
# prediction to blame it on. That is the whole reason the netcode was built
# server-authoritative with no prediction.
extends SceneTree

const T_ := preload("res://tests/t.gd")
const Const_ := preload("res://scripts/core/const.gd")
const Types_ := preload("res://scripts/core/types.gd")
const Server_ := preload("res://scripts/net/server.gd")
const Client_ := preload("res://scripts/net/client.gd")
const Protocol_ := preload("res://scripts/net/protocol.gd")
const Stats_ := preload("res://scripts/core/stats.gd")

# A high port, so a developer machine is unlikely to have it in use. If it is,
# the suite says so rather than failing mysteriously.
const PORT := 47654


func _init() -> void:
	var t := T_.new("netplay")
	await _test_two_clients_agree(t)
	await _test_rejections(t)
	await _test_disconnect(t)
	await _test_a_whole_match(t)
	await _test_bots_survive_a_round(t)
	await _test_a_silent_client_is_reaped(t)
	quit(t.finish())


func _test_two_clients_agree(t: T_) -> void:
	var server: Server_ = Server_.new()
	if not t.ok(server.listen(PORT, _scheme_text(), 0, 4242),
			"the server listens on %d" % PORT):
		t.note("is something else using port %d?" % PORT)
		return

	# The statistics counters ride along on this test rather than getting a
	# socket of their own: 921-924 can only be checked against real traffic,
	# and this is the one suite that has any. scripts/core/stats.gd.
	var server_stats := Stats_.new()
	server.stats = server_stats
	var alice_stats := Stats_.new()

	var a: Client_ = Client_.new()
	a.stats = alice_stats
	var b: Client_ = Client_.new()
	t.ok(a.connect_to("ws://127.0.0.1:%d" % PORT, "alice"), "alice connects")
	t.ok(b.connect_to("ws://127.0.0.1:%d" % PORT, "bob"), "bob connects")

	# Let the handshake complete.
	for _i in 200:
		await _pump(server, [a, b])
		if a.playing() and b.playing():
			break
	if not t.ok(a.playing(), "alice is playing (%s)" % a.reject_reason):
		server.close()
		return
	if not t.ok(b.playing(), "bob is playing (%s)" % b.reject_reason):
		server.close()
		return

	t.ok(a.slot != b.slot, "they get different slots (%d, %d)" % [a.slot, b.slot])
	t.eq(server.player_count(), 2, "the server has two players")

	# Play. Both clients drive input; the server is the only thing simulating.
	var checked := 0
	var mismatches := 0
	var script := [Types_.MoveState.RIGHT, Types_.MoveState.DOWN,
		Types_.MoveState.LEFT, Types_.MoveState.UP]
	for step in 240:
		a.send_input(script[(step / 6) % 4],
			Types_.Action.FIRST if step % 37 == 0 else Types_.Action.NONE)
		b.send_input(script[(step / 5 + 2) % 4],
			Types_.Action.FIRST if step % 41 == 0 else Types_.Action.NONE)
		await _pump(server, [a, b])

		# Compare only when a client has the server's current tick: a snapshot
		# in flight is not a disagreement.
		for c in [a, b]:
			if c.sim == null:
				continue
			if c.server_tick != server.sim.tick_count:
				continue
			checked += 1
			if c.sim.state_hash() != server.sim.state_hash():
				mismatches += 1

	t.ok(checked > 30, "%d snapshots were compared" % checked)
	t.eq(mismatches, 0,
		"[invariant] every compared snapshot matched the server exactly")
	t.ok(a.snapshots_applied() > 20,
		"alice applied %d snapshots" % a.snapshots_applied())
	t.ok(b.snapshots_applied() > 20,
		"bob applied %d snapshots" % b.snapshots_applied())
	# ticks_served, not sim.tick_count: a client blowing itself up ends the
	# round, and the next round's simulation starts back at tick zero. This
	# assertion used to read sim.tick_count and began failing intermittently
	# the moment matches ran to more than one round — measuring the round when
	# it meant to measure the server.
	t.ok(server.ticks_served > 20,
		"the server ran %d ticks in total" % server.ticks_served)

	# Both clients must see each other, not just themselves.
	var a_others := 0
	for p in a.sim.players:
		if p.alive:
			a_others += 1
	t.ok(a_others >= 2, "alice sees %d live players, including bob" % a_others)

	# 919-924, against traffic that really crossed a socket.
	t.ok(server_stats.value(Stats_.C.PACKETS_OUT) > 20,
		"the server counted %d packets out"
			% server_stats.value(Stats_.C.PACKETS_OUT))
	t.ok(server_stats.value(Stats_.C.PACKETS_IN) > 20,
		"and %d in" % server_stats.value(Stats_.C.PACKETS_IN))
	# Not merely "more bytes than packets": every _send would satisfy that on
	# its own while a broadcast counted one byte each. Most of what a server
	# sends is a ~3 kB snapshot, so the mean packet is far above this floor,
	# and a counter that lost the size would fall through it.
	var mean_out := (server_stats.value(Stats_.C.BYTES_OUT)
		/ maxi(1, server_stats.value(Stats_.C.PACKETS_OUT)))
	t.ok(mean_out > 100,
		"the mean packet out is %d bytes, from %d bytes over %d packets"
			% [mean_out, server_stats.value(Stats_.C.BYTES_OUT),
				server_stats.value(Stats_.C.PACKETS_OUT)])
	t.ok(server_stats.value(Stats_.C.BYTES_IN) > 0,
		"%d bytes in" % server_stats.value(Stats_.C.BYTES_IN))
	t.ok(server_stats.value(Stats_.C.GAMES_STARTED) >= 1,
		"911 counted %d rounds" % server_stats.value(Stats_.C.GAMES_STARTED))
	t.ok(alice_stats.value(Stats_.C.PACKETS_IN) > 20,
		"alice counted %d packets in" % alice_stats.value(Stats_.C.PACKETS_IN))
	t.ok(alice_stats.value(Stats_.C.PACKETS_OUT) > 20,
		"and %d out" % alice_stats.value(Stats_.C.PACKETS_OUT))
	# A client applies snapshots and never ticks a simulation, so there is
	# nothing local for it to count. docs/AUDIT.md §1.1 says so too.
	t.eq(alice_stats.value(Stats_.C.BOMBS_DROPPED), 0,
		"a joined client counts no bombs — it has no simulation of its own")

	a.close()
	b.close()
	server.close()


func _test_rejections(t: T_) -> void:
	var server: Server_ = Server_.new()
	if not server.listen(PORT + 1, _scheme_text()):
		t.ok(false, "the server listens for the rejection tests")
		return

	# A duplicate name is refused, so two players cannot both be "alice".
	var a: Client_ = Client_.new()
	var dup: Client_ = Client_.new()
	a.connect_to("ws://127.0.0.1:%d" % (PORT + 1), "alice")
	for _i in 120:
		await _pump(server, [a])
		if a.playing():
			break
	t.ok(a.playing(), "the first alice joins")

	dup.connect_to("ws://127.0.0.1:%d" % (PORT + 1), "alice")
	for _i in 120:
		await _pump(server, [a, dup])
		if dup.state == Client_.State.REFUSED:
			break
	t.eq(dup.state, Client_.State.REFUSED, "the second alice is refused")
	t.eq(dup.reject_reason, Protocol_.REJECT_TEXT[Protocol_.REJECT_NAME_TAKEN],
		"and told why")

	# Junk must not take the server down. A stranger who can crash a server is
	# a reason nobody hosts one.
	var junk := WebSocketMultiplayerPeer.new()
	junk.create_client("ws://127.0.0.1:%d" % (PORT + 1))
	for _i in 60:
		junk.poll()
		await _pump(server, [a])
		if junk.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
			break
	junk.set_target_peer(MultiplayerPeer.TARGET_PEER_BROADCAST)
	junk.put_packet(PackedByteArray([255, 255, 255]))
	junk.put_packet(PackedByteArray([Protocol_.C_INPUT]))          # truncated
	junk.put_packet(PackedByteArray([Protocol_.C_HELLO, 0]))       # truncated
	junk.put_packet(PackedByteArray())                             # empty
	var before := server.sim.tick_count
	for _i in 60:
		junk.poll()
		await _pump(server, [a])
	t.ok(server.sim.tick_count > before,
		"the server keeps ticking through malformed packets")
	t.ok(a.playing(), "and the real client is unaffected")
	# The junk peer said hello badly, so it never got a seat.
	t.eq(server.player_count(), 1, "and junk never got a seat")

	junk.close()
	a.close()
	dup.close()
	server.close()


func _test_disconnect(t: T_) -> void:
	var server: Server_ = Server_.new()
	if not server.listen(PORT + 2, _scheme_text()):
		t.ok(false, "the server listens for the disconnect test")
		return

	var a: Client_ = Client_.new()
	var b: Client_ = Client_.new()
	a.connect_to("ws://127.0.0.1:%d" % (PORT + 2), "alice")
	b.connect_to("ws://127.0.0.1:%d" % (PORT + 2), "bob")
	for _i in 200:
		await _pump(server, [a, b])
		if a.playing() and b.playing():
			break
	t.eq(server.player_count(), 2, "two players joined")

	# Bob leaves. The server must keep running for alice, which is what makes
	# a self-hosted game survive a browser tab being closed.
	var bob_slot := b.slot
	b.close()
	var before := server.sim.tick_count
	for _i in 120:
		await _pump(server, [a])
	t.ok(server.sim.tick_count > before,
		"the server keeps ticking after a client leaves")
	t.ok(a.playing(), "and the remaining client keeps playing")

	# Alice must still be able to move afterwards.
	var moved := false
	if a.sim != null:
		var me := a.sim.player_by_slot(a.slot)
		if me != null:
			var was := me.x
			for _i in 60:
				a.send_input(Types_.MoveState.RIGHT, Types_.Action.NONE)
				await _pump(server, [a])
			me = a.sim.player_by_slot(a.slot)
			moved = me != null and me.x != was
	t.ok(moved, "and alice can still move")

	a.close()
	server.close()


# A match played to its end over the wire.
#
# The rules themselves are tested in tests/test_match.gd. What this adds is the
# part that only exists once there are two processes: the server counts the
# wins, starts the next round after resource 13's three seconds, and the client
# FOLLOWS — new seed, new field, same hash. A client that kept the first
# round's layout would look exactly like a desync.
func _test_a_whole_match(t: T_) -> void:
	var server: Server_ = Server_.new()
	if not server.listen(PORT + 3, _scheme_text(), 0, 777):
		t.ok(false, "the server listens for the match test")
		return

	var a: Client_ = Client_.new()
	var b: Client_ = Client_.new()
	a.connect_to("ws://127.0.0.1:%d" % (PORT + 3), "alice")
	b.connect_to("ws://127.0.0.1:%d" % (PORT + 3), "bob")
	# Waiting on READY_COUNT, not on playing(). A client is `playing` the moment
	# it has been welcomed, which is BEFORE its own C_READY has reached the
	# server and put its seat in play — and a seat that is not in play is not a
	# contender, so a round with one of them missing cannot end. The first
	# version of this test killed a player who had not been seated yet and the
	# round then ran forever.
	for _i in 200:
		await _pump(server, [a, b])
		if server.ready_count() == 2:
			break
	if not t.ok(server.ready_count() == 2, "both clients joined and were seated"):
		server.close()
		return
	t.ok(a.playing() and b.playing(), "and both are playing")

	t.eq(server.the_match.wins_to_win, 2,
		"the server plays to resource 310's two wins")
	t.eq(a.the_match.wins_to_win, 2, "and told the client so")
	t.eq(a.the_match.round_index, 0, "it is round one")
	t.eq(a.the_match.round_seed, 777,
		"on the seed the server was started with")

	var first_seed := a.the_match.round_seed
	var loser := b.slot

	# Round one. Bob dies, so alice is last standing.
	server.sim.kill(server.sim.player_by_slot(loser), a.slot)
	var mismatches := 0
	var compared := 0
	# The server's hash AT EACH TICK, so a client one tick behind can still be
	# checked against the tick it is actually showing.
	#
	# This used to compare only when the client's tick happened to equal the
	# server's current one, which is a race: the client usually trails by one,
	# so the count depended on how the two were scheduled. Inside a full verify
	# run it fell from ~30 to 3 and failed. Keeping a small history removes the
	# race and compares MORE snapshots, not fewer.
	var history := {}
	for _i in 200:
		# Both clients keep reporting their tick. Without it the server sees
		# them falling behind and pauses everything at SYNC_TOLERANCE_TICKS,
		# which is correct behaviour and would make this test measure nothing.
		a.send_input(Types_.MoveState.STILL, Types_.Action.NONE)
		b.send_input(Types_.MoveState.STILL, Types_.Action.NONE)
		await _pump(server, [a, b])
		history[server.sim.tick_count] = server.sim.state_hash()
		# Only ticks from THIS round: the round change resets the counter, and
		# a hash recorded before it belongs to a different field.
		if history.size() > 64:
			var oldest: int = history.keys().min()
			history.erase(oldest)
		if a.sim != null and history.has(a.server_tick):
			compared += 1
			if a.sim.state_hash() != history[a.server_tick]:
				mismatches += 1

	t.eq(a.the_match.wins_of(a.slot), 1, "alice is credited with the round")
	t.eq(a.the_match.wins_of(loser), 0, "and bob is not")
	t.eq(a.the_match.round_index, 1, "round two has started")
	t.ok(a.the_match.round_seed != first_seed, "on a new seed")
	t.eq(a.the_match.round_seed, server.the_match.round_seed,
		"the same seed the server is using")
	t.ok(not a.the_match.over(), "the match is not over yet")
	t.ok(compared > 10, "%d snapshots were compared across the round change"
		% compared)
	t.eq(mismatches, 0,
		"[invariant] the client matched the server through a round change")

	# Both are alive again on the new field, which is what a new round means.
	var alive := 0
	for p in a.sim.players:
		if p.alive and p.in_play:
			alive += 1
	t.eq(alive, 2, "both players are alive again in round two")

	# Round two ends the match.
	server.sim.kill(server.sim.player_by_slot(loser), a.slot)
	for _i in 140:
		a.send_input(Types_.MoveState.STILL, Types_.Action.NONE)
		b.send_input(Types_.MoveState.STILL, Types_.Action.NONE)
		await _pump(server, [a, b])

	t.ok(a.the_match.over(), "two wins take the match")
	t.eq(a.the_match.champion_slot, a.slot, "alice is the champion")
	t.eq(a.the_match.wins_of(a.slot), 2, "with two wins")
	t.eq(a.the_match.round_index, 1,
		"and no third round was started after it ended")

	# The server keeps serving a finished match rather than closing: whoever is
	# hosting decides what happens next, not the server.
	var before := server.sim.tick_count
	for _i in 60:
		a.send_input(Types_.MoveState.STILL, Types_.Action.NONE)
		b.send_input(Types_.MoveState.STILL, Types_.Action.NONE)
		await _pump(server, [a, b])
	t.ok(server.sim.tick_count > before,
		"the server keeps ticking with the match won")
	t.ok(a.playing(), "and the clients stay connected")

	a.close()
	b.close()
	server.close()


# A new round rebuilds the simulation from scratch, which throws the bots away
# with it. They have to be put back, or a server started with bots plays
# exactly one round and then sits empty — and an empty server still ticks, so
# nothing about it looks broken.
func _test_bots_survive_a_round(t: T_) -> void:
	var server: Server_ = Server_.new()
	if not server.listen(PORT + 4, _scheme_text(), 0, 31337):
		t.ok(false, "the server listens for the bot test")
		return
	server.add_bots(3)
	t.eq(server.sim.bot_slots.size(), 3, "three bots are playing")

	var in_play := 0
	for p in server.sim.players:
		if p.in_play:
			in_play += 1
	t.eq(in_play, 3, "and all three are in play, so the round can end")

	# End the round: two of the three die.
	var slots: Array = server.sim.bot_slots.keys()
	slots.sort()
	server.sim.kill(server.sim.player_by_slot(int(slots[0])), int(slots[2]))
	server.sim.kill(server.sim.player_by_slot(int(slots[1])), int(slots[2]))

	var first_seed := server.the_match.round_seed
	for _i in 140:
		server.poll(float(Const_.TICK_MS))
		await process_frame

	t.eq(server.the_match.round_index, 1, "the next round started")
	t.ok(server.the_match.round_seed != first_seed, "on a new seed")
	t.eq(server.sim.bot_slots.size(), 3, "and the bots came back")
	var again := 0
	for p in server.sim.players:
		if p.in_play and p.alive:
			again += 1
	t.eq(again, 3, "all three alive on the new field")
	t.eq(server.the_match.wins_of(int(slots[2])), 1,
		"the surviving bot is credited with the round")
	server.close()


# A client that connects and then goes quiet must not stall the server forever.
#
# It used to. Silence was counted inside _tick(), the pause stops _tick(), and
# so the counter that would have dropped the silent client stopped with it: one
# socket opened and abandoned paused the game permanently for everybody else.
# Found by leaving a probe connected to a real server while looking at
# something else, not by a test — the tests all keep their clients talking.
func _test_a_silent_client_is_reaped(t: T_) -> void:
	var server: Server_ = Server_.new()
	if not server.listen(PORT + 5, _scheme_text()):
		t.ok(false, "the server listens for the timeout test")
		return

	var talker: Client_ = Client_.new()
	var mute: Client_ = Client_.new()
	talker.connect_to("ws://127.0.0.1:%d" % (PORT + 5), "talker")
	mute.connect_to("ws://127.0.0.1:%d" % (PORT + 5), "mute")
	for _i in 200:
		talker.send_input(Types_.MoveState.STILL, Types_.Action.NONE)
		mute.send_input(Types_.MoveState.STILL, Types_.Action.NONE)
		await _pump(server, [talker, mute])
		if server.ready_count() == 2:
			break
	if not t.ok(server.ready_count() == 2, "both clients are seated"):
		server.close()
		return

	# One of them stops talking. It still POLLS — a browser tab that is
	# backgrounded keeps its socket open and stops sending, which is exactly
	# this — so the connection never closes on its own.
	var paused_at := -1
	var dropped_at := -1
	for i in 800:
		talker.send_input(Types_.MoveState.STILL, Types_.Action.NONE)
		await _pump(server, [talker, mute])
		if server.paused and paused_at < 0:
			paused_at = i
		if server.player_count() == 1 and dropped_at < 0:
			dropped_at = i
			break

	t.ok(paused_at >= 0, "the server paused for the silent client (step %d)"
		% paused_at)
	t.ok(dropped_at > 0, "and then dropped it (step %d)" % dropped_at)
	t.eq(server.player_count(), 1, "leaving one player")

	# And the game runs again once it is gone, which is the point.
	var before := server.ticks_served
	for _i in 60:
		talker.send_input(Types_.MoveState.STILL, Types_.Action.NONE)
		await _pump(server, [talker, mute])
	t.ok(not server.paused, "the server is running again")
	t.ok(server.ticks_served > before,
		"and ticking: %d ticks after the drop" % (server.ticks_served - before))

	talker.close()
	mute.close()
	server.close()


## One frame: give the server a tick's worth of time and let every client read.
func _pump(server: Server_, clients: Array) -> void:
	server.poll(float(Const_.TICK_MS))
	for c in clients:
		c.poll()
	await process_frame


func _scheme_text() -> String:
	var lines := PackedStringArray()
	lines.append("-V,2")
	lines.append("-N,Netplay fixture (10)")
	lines.append("-B,0")
	for y in Const_.FIELD_H:
		lines.append("-R,%2d,%s" % [y, ".".repeat(Const_.FIELD_W)])
	for p in Const_.PLAYER_COUNT:
		lines.append("-S,%d,%d,%d,%d" % [p, 1 + p, 1 + (p % 8), p % 2])
	for i in Const_.POWERUP_COUNT:
		lines.append("-P,%2d, 0,0, 0, 0,x" % i)
	return "\n".join(lines)
