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
const Player_ := preload("res://scripts/sim/player.gd")

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
	await _test_slot_override(t)
	await _test_lobby_waits_for_the_host(t)
	await _test_lobby_host_reassigned_on_departure(t)
	await _test_three_clients_through_the_lobby(t)
	await _test_an_action_survives_a_frame_of_silence(t)
	await _test_a_lobby_always_has_a_host(t)
	await _test_a_lobby_does_not_reap_people_for_waiting(t)
	await _test_animation_timers_reach_the_client(t)
	await _test_a_won_match_returns_to_the_lobby(t)
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

	# Round two ends the match. Alice's seat is read now: once the match is
	# won the room reopens and a client in a lobby has no seat.
	var champ := a.slot
	server.sim.kill(server.sim.player_by_slot(loser), a.slot)
	for _i in 140:
		a.send_input(Types_.MoveState.STILL, Types_.Action.NONE)
		b.send_input(Types_.MoveState.STILL, Types_.Action.NONE)
		await _pump(server, [a, b])

	t.ok(a.the_match.over(), "two wins take the match")
	t.eq(a.the_match.champion_slot, champ, "alice is the champion")
	t.eq(a.the_match.wins_of(champ), 2, "with two wins")
	t.eq(a.the_match.round_index, 1,
		"and no third round was started after it ended")

	# A won match goes back to the room rather than ticking a finished field
	# forever — docs/IMPROVEMENTS.md A1, "it gets stuck at the end of the
	# match". Even this server, which started its first match at once, has a
	# host by now to start the next one.
	for _i in 200:
		await _pump(server, [a, b])
		if a.in_lobby() and b.in_lobby():
			break
	t.eq(server.state, Server_.State.WAITING,
		"[invariant] the finished match reopens the room")
	t.ok(a.in_lobby() and b.in_lobby(), "and both clients are back in it")
	t.eq(server.player_count(), 2, "still connected, both of them")
	t.eq(a.the_match.champion_slot, champ,
		"the client still knows who won while it waits")
	t.eq(a.sim, null, "and has dropped the finished field")

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


## INPUT.BM: "'o' or '0' lets the host override a client's player
## selection." server.override_slot()'s own comment explains the scope this
## implements: a connected human demoted to AI, and an AI freed back to
## open — not the original's full KEY/AI/JOY/OFF cycle, which this port has
## no lobby screen to run on.
func _test_slot_override(t: T_) -> void:
	var server: Server_ = Server_.new()
	if not server.listen(PORT + 6, _scheme_text()):
		t.ok(false, "the server listens for the override test")
		return

	var a: Client_ = Client_.new()
	var b: Client_ = Client_.new()
	# Every peer hears the broadcast (Protocol_.slot_overridden()'s own
	# comment on why), not only the overridden one — connect both.
	var heard: Dictionary = {}
	a.slot_overridden.connect(func(s: int, _ai: bool): heard["a"] = s)
	b.slot_overridden.connect(func(s: int, _ai: bool): heard["b"] = s)
	a.connect_to("ws://127.0.0.1:%d" % (PORT + 6), "alice")
	b.connect_to("ws://127.0.0.1:%d" % (PORT + 6), "bob")
	for _i in 200:
		await _pump(server, [a, b])
		if a.playing() and b.playing():
			break
	if not t.ok(a.playing() and b.playing(), "both clients are playing"):
		server.close()
		return

	var slot: int = server.override_next_slot()
	t.ok(slot == a.slot or slot == b.slot,
		"override_next_slot() picked a connected slot (%d)" % slot)
	t.ok(server.sim.is_bot(slot), "the sim now runs that slot as a bot")

	for _i in 5:
		await _pump(server, [a, b])
	t.eq(heard.get("a", -1), slot, "alice's client heard the override")
	t.eq(heard.get("b", -1), slot, "and so did bob's")

	# The overridden client's own input no longer reaches the sim: send it
	# STILL and drive it, then check the player MOVED anyway — think()'s
	# fallback wander does not sit motionless the way an ignored-but-honest
	# STILL would if it still reached the sim.
	var target := a if slot == a.slot else b
	var before_pos := Vector2i(-1, -1)
	if server.sim != null:
		var me := server.sim.player_by_slot(slot)
		if me != null:
			before_pos = Vector2i(me.x, me.y)
	for _i in 60:
		target.send_input(Types_.MoveState.STILL, Types_.Action.NONE)
		await _pump(server, [a, b])
	var moved_on_its_own := false
	if server.sim != null and before_pos.x >= 0:
		var me2 := server.sim.player_by_slot(slot)
		if me2 != null:
			moved_on_its_own = me2.x != before_pos.x or me2.y != before_pos.y
	t.ok(moved_on_its_own,
		"the overridden slot moved on its own, not by the client's STILL")

	# And it reverses: an AI slot this created goes back to open.
	var reverted: int = server.override_next_slot()
	t.eq(reverted, slot, "the same slot is the next thing to override")
	t.ok(not server.sim.is_bot(slot), "and it is no longer a bot")

	a.close()
	b.close()
	server.close()


## A room opened with `lobby: true` holds everyone in State.WAITING — no round
## running, no sim, just a roster — until the first-joined peer sends
## C_START. This is the behaviour change docs/BUGS.md's `override_slot()`
## comment flagged as missing: "there is no lobby a host and already-
## connected clients both sit in."
func _test_lobby_waits_for_the_host(t: T_) -> void:
	var server: Server_ = Server_.new()
	if not t.ok(server.listen(PORT + 7, _scheme_text(), 0, 99, false, true),
			"the server opens a lobby on %d" % (PORT + 7)):
		return
	t.eq(server.state, Server_.State.WAITING, "and starts in State.WAITING")

	var a: Client_ = Client_.new()
	var b: Client_ = Client_.new()
	a.connect_to("ws://127.0.0.1:%d" % (PORT + 7), "alice")
	b.connect_to("ws://127.0.0.1:%d" % (PORT + 7), "bob")
	for _i in 200:
		await _pump(server, [a, b])
		if a.in_lobby() and b.in_lobby():
			break
	if not t.ok(a.in_lobby() and b.in_lobby(), "both clients reach the lobby"):
		server.close()
		return
	t.ok(not a.playing() and not b.playing(),
		"[invariant] neither is playing yet — no sim exists")
	t.eq(server.sim, null, "[invariant] the server has not built a sim either")

	t.ok(a.lobby_is_host, "the first to join (alice) is the host")
	t.ok(not b.lobby_is_host, "the second (bob) is not")
	t.eq(a.lobby_roster.size(), 2, "alice's roster has both of them")
	t.eq(b.lobby_roster.size(), 2, "and so does bob's — it's broadcast, not personal")

	# Bob cannot start it — the server just ignores a C_START from a non-host.
	b.request_start()
	for _i in 10:
		await _pump(server, [a, b])
	t.eq(server.state, Server_.State.WAITING,
		"a non-host's C_START does nothing")

	# Alice, the host, can.
	a.request_start()
	for _i in 200:
		await _pump(server, [a, b])
		if a.playing() and b.playing():
			break
	t.ok(a.playing() and b.playing(), "the host's C_START begins the round")
	t.ok(not a.in_lobby() and not b.in_lobby(),
		"and neither client is 'in lobby' any more")

	a.close()
	b.close()
	server.close()


## If the host leaves before starting, the room does not get stuck — the next
## remaining peer inherits C_START.
func _test_lobby_host_reassigned_on_departure(t: T_) -> void:
	var server: Server_ = Server_.new()
	if not t.ok(server.listen(PORT + 8, _scheme_text(), 0, 1, false, true),
			"the server opens a lobby on %d" % (PORT + 8)):
		return

	var a: Client_ = Client_.new()
	var b: Client_ = Client_.new()
	a.connect_to("ws://127.0.0.1:%d" % (PORT + 8), "alice")
	b.connect_to("ws://127.0.0.1:%d" % (PORT + 8), "bob")
	for _i in 200:
		await _pump(server, [a, b])
		if a.in_lobby() and b.in_lobby():
			break
	if not t.ok(a.in_lobby() and b.in_lobby(), "both reach the lobby"):
		server.close()
		return
	t.ok(a.lobby_is_host, "alice hosts to start with")

	a.close()
	for _i in 20:
		await _pump(server, [b])
	t.ok(server.host_peer_id >= 0,
		"the room still has a host once alice is gone")

	b.request_start()
	for _i in 200:
		await _pump(server, [b])
		if b.playing():
			break
	t.ok(b.playing(), "bob inherited C_START and could start the round himself")

	b.close()
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


## THREE PLAYERS, the whole way: a lobby, the host starting it, and all three
## then playing the same round.
##
## The two-client tests cover the transport and the lobby separately. This is
## the shape a real session actually takes — more than two people, joining a
## room that is waiting rather than one already running — and it is what a
## live "multiplayer is not working" report needs ruling in or out.
func _test_three_clients_through_the_lobby(t: T_) -> void:
	var port := PORT + 9
	var server: Server_ = Server_.new()
	# The last two arguments are what `--serve` uses: open a LOBBY and wait
	# for the host, rather than starting a round the moment anyone connects.
	if not t.ok(server.listen(port, _scheme_text(), 0, 99, false, true),
			"the server opens a lobby on %d" % port):
		return

	var a: Client_ = Client_.new()
	var b: Client_ = Client_.new()
	var c: Client_ = Client_.new()
	var all := [a, b, c]
	t.ok(a.connect_to("ws://127.0.0.1:%d" % port, "host"), "the host connects")
	t.ok(b.connect_to("ws://127.0.0.1:%d" % port, "player2"), "player2 connects")
	t.ok(c.connect_to("ws://127.0.0.1:%d" % port, "player3"), "player3 connects")

	for _i in 300:
		await _pump(server, all)
		if a.in_lobby() and b.in_lobby() and c.in_lobby():
			break
	if not t.ok(a.in_lobby() and b.in_lobby() and c.in_lobby(),
			"all three reach the lobby"):
		server.close()
		return
	t.eq(a.lobby_roster.size(), 3, "the roster shows all three")
	t.ok(a.lobby_is_host, "the first to join is the host")
	t.ok(not b.lobby_is_host and not c.lobby_is_host,
		"and the other two are not")

	# Three distinct rooms slots. In the lobby that is `lobby_slot`: `slot` is
	# the seat in a simulation and there is no simulation yet, which is why
	# client.gd keeps the two apart.
	var rooms := {}
	for client in all:
		rooms[client.lobby_slot] = true
	t.eq(rooms.size(), 3, "they hold three different lobby slots")
	var roster_slots := {}
	for entry in a.lobby_roster:
		roster_slots[int(entry["slot"])] = true
	t.eq(roster_slots.size(), 3, "and the broadcast roster lists all three")

	# The host starts it.
	a.request_start()
	for _i in 300:
		await _pump(server, all)
		if a.playing() and b.playing() and c.playing():
			break
	if not t.ok(a.playing() and b.playing() and c.playing(),
			"the host's start puts all three into the round"):
		server.close()
		return
	t.eq(server.player_count(), 3, "the server has three players")

	# Now that a simulation exists, each client has a real seat in it.
	var seats := {}
	for client in all:
		seats[client.slot] = true
	t.eq(seats.size(), 3, "and each is seated in a different slot")

	# Play, and check every client against the server on every tick where
	# they are level with it.
	var checked := 0
	var mismatches := 0
	var script := [Types_.MoveState.RIGHT, Types_.MoveState.DOWN,
		Types_.MoveState.LEFT, Types_.MoveState.UP]
	for step in 240:
		for i in all.size():
			var client: Client_ = all[i]
			client.send_input(script[(step / (5 + i)) % 4],
				Types_.Action.FIRST if step % (31 + i * 7) == 0 \
					else Types_.Action.NONE)
		await _pump(server, all)
		if server.sim == null:
			continue
		for client in all:
			if client.sim == null or client.server_tick != server.sim.tick_count:
				continue
			checked += 1
			if client.sim.state_hash() != server.sim.state_hash():
				mismatches += 1

	t.ok(checked > 45, "%d snapshots were compared across three clients"
		% checked)
	t.eq(mismatches, 0,
		"[invariant] every one matched the server exactly")
	for i in all.size():
		var client: Client_ = all[i]
		t.ok(client.snapshots_applied() > 20,
			"client %d applied %d snapshots" % [i, client.snapshots_applied()])

	# Each of them sees the other two, not just itself. SEATED, not alive:
	# these clients drop bombs on a schedule while walking, and under a loaded
	# verify run an input can land a tick later, the paths diverge, and
	# somebody walks into their own blast — a death the server and every
	# client agree on, which the hash check above has already proven. Counting
	# the living made this flake about one full run in three.
	var seen := 0
	for p in a.sim.players:
		if p.in_play:
			seen += 1
	t.ok(seen >= 3, "the host sees %d seated players" % seen)

	for client in all:
		client.close()
	server.close()


## A BOMB PRESS MUST NOT BE LOST BETWEEN SERVER TICKS.
##
## A joined client sends its input once per RENDERED FRAME — main.gd's
## _process() — while the server ticks at 20 Hz. So one packet carries
## Action.FIRST and the next, a handful of milliseconds later, carries NONE.
## The server applied each packet straight to the simulation, so the NONE
## overwrote the FIRST before any tick consumed it, and the bomb was placed
## only when a tick happened to land inside that window. At 120 fps that is
## roughly one press in six.
##
## Reported live as "there is lag when placing bombs". It is not latency: the
## presses are being dropped outright.
##
## The local path cannot hit this — main.gd's _step() calls set_input() once
## per tick, so the edge is consumed exactly once.
func _test_an_action_survives_a_frame_of_silence(t: T_) -> void:
	var port := PORT + 10
	var server: Server_ = Server_.new()
	if not t.ok(server.listen(port, _scheme_text(), 0, 4242),
			"the server listens on %d" % port):
		return
	var a: Client_ = Client_.new()
	a.connect_to("ws://127.0.0.1:%d" % port, "presser")
	for _i in 200:
		await _pump(server, [a])
		if a.playing():
			break
	if not t.ok(a.playing(), "the client is playing"):
		server.close()
		return

	var before := server.sim.bombs.size()

	# One press, then the silence a real client sends for the rest of the
	# frames before the next tick. No server poll in between: this is all
	# inside one tick's worth of wall clock.
	a.send_input(Types_.MoveState.STILL, Types_.Action.FIRST)
	a.poll()
	for _i in 6:
		a.send_input(Types_.MoveState.STILL, Types_.Action.NONE)
		a.poll()
	# Let the server read all seven packets and then tick.
	for _i in 4:
		await _pump(server, [a])

	t.ok(server.sim.bombs.size() > before,
		"the press survived the frames of silence after it (%d -> %d bombs)"
			% [before, server.sim.bombs.size()])

	a.close()
	server.close()


## A ROOM WITH PEOPLE IN IT ALWAYS HAS A HOST.
##
## host_peer_id names whoever may send C_START. Live, a lobby reached
## host_peer_id = -1 with two peers still connected, and then refused every
## C_START — the round could not be started at all, and because the refusal
## is silent the host's Enter simply looked dead:
##
##     [srv] C_START from 922376940, host_peer_id=-1, state=0
##
## _ensure_host() states the invariant instead of patching it at each call
## site, and is called on join, on release, and on C_START itself.
func _test_a_lobby_always_has_a_host(t: T_) -> void:
	var port := PORT + 11
	var server: Server_ = Server_.new()
	if not t.ok(server.listen(port, _scheme_text(), 0, 7, false, true),
			"the server opens a lobby on %d" % port):
		return

	var a: Client_ = Client_.new()
	var b: Client_ = Client_.new()
	a.connect_to("ws://127.0.0.1:%d" % port, "first")
	b.connect_to("ws://127.0.0.1:%d" % port, "second")
	for _i in 200:
		await _pump(server, [a, b])
		if a.in_lobby() and b.in_lobby():
			break
	if not t.ok(a.in_lobby() and b.in_lobby(), "both reach the lobby"):
		server.close()
		return
	t.ok(server.host_peer_id >= 0, "the room has a host")
	t.ok(a.lobby_is_host and not b.lobby_is_host,
		"exactly one of them is told they are it")

	# EVERYONE LEAVES. The room is empty and has no host, which is correct.
	a.close()
	b.close()
	for _i in 60:
		await _pump(server, [])
	t.eq(server.host_peer_id, -1, "an empty room has no host")

	# AND THEN PEOPLE COME BACK. The room must adopt one, or it is stuck
	# forever with nobody able to start.
	var c: Client_ = Client_.new()
	var d: Client_ = Client_.new()
	c.connect_to("ws://127.0.0.1:%d" % port, "third")
	d.connect_to("ws://127.0.0.1:%d" % port, "fourth")
	for _i in 200:
		await _pump(server, [c, d])
		if c.in_lobby() and d.in_lobby():
			break
	if not t.ok(c.in_lobby() and d.in_lobby(), "both rejoin the lobby"):
		server.close()
		return
	t.ok(server.host_peer_id >= 0,
		"the refilled room has a host again (%d)" % server.host_peer_id)
	t.ok(c.lobby_is_host != d.lobby_is_host,
		"and exactly one of the two is it")

	# The one who holds it can actually start the round.
	var host_client: Client_ = c if c.lobby_is_host else d
	host_client.request_start()
	for _i in 200:
		await _pump(server, [c, d])
		if c.playing() and d.playing():
			break
	t.ok(c.playing() and d.playing(),
		"and the round starts — the lobby is not wedged")

	c.close()
	d.close()
	server.close()


## SITTING IN A LOBBY IS NOT BEING SILENT.
##
## A client sends C_INPUT only once a round is running, and C_HEARTBEAT only
## once it has a sim to be behind on. A room that is still WAITING therefore
## hears nothing from anybody — and the silent-peer reaper ran anyway, so
## every peer was released after TIMEOUT_MS (30 s) with their windows open,
## connected, and still sending C_START. The observed live sequence:
##
##     server: HOST joined the lobby as slot 0
##     server: player2 joined the lobby as slot 1
##     server: HOST left (slot 0)         <- nobody closed anything
##     server: player2 left (slot 1)
##     [srv] C_START from 922376940, host_peer_id=-1, state=0
##
## which is what "Enter is not working" was: take longer than half a minute
## to decide, and the lobby has quietly thrown everyone out.
func _test_a_lobby_does_not_reap_people_for_waiting(t: T_) -> void:
	var port := PORT + 12
	var server: Server_ = Server_.new()
	if not t.ok(server.listen(port, _scheme_text(), 0, 11, false, true),
			"the server opens a lobby on %d" % port):
		return

	var a: Client_ = Client_.new()
	var b: Client_ = Client_.new()
	a.connect_to("ws://127.0.0.1:%d" % port, "patient")
	b.connect_to("ws://127.0.0.1:%d" % port, "alsopatient")
	for _i in 200:
		await _pump(server, [a, b])
		if a.in_lobby() and b.in_lobby():
			break
	if not t.ok(a.in_lobby() and b.in_lobby(), "both reach the lobby"):
		server.close()
		return
	t.eq(server.player_count_in_lobby() if server.has_method(
		"player_count_in_lobby") else server.peers.size(), 2,
		"the room holds two people")

	# Wait out well past the reaper's timeout, saying nothing — exactly what
	# two people reading the screen do.
	for _i in 4:
		server.poll(float(Server_.TIMEOUT_MS))
		a.poll()
		b.poll()
		await process_frame

	t.eq(server.peers.size(), 2,
		"they are both still in the room after %d s of quiet"
			% (4 * Server_.TIMEOUT_MS / 1000))
	t.ok(a.in_lobby() and b.in_lobby(), "and both still think so")
	t.ok(server.host_peer_id >= 0, "the room still has a host")

	# And the host can still start it.
	var host_client: Client_ = a if a.lobby_is_host else b
	host_client.request_start()
	for _i in 200:
		await _pump(server, [a, b])
		if a.playing() and b.playing():
			break
	t.ok(a.playing() and b.playing(),
		"the round starts after the wait, rather than the lobby being empty")

	a.close()
	b.close()
	server.close()


## A CLIENT CAN ONLY DRAW WHAT THE SNAPSHOT CARRIES.
##
## game_view.gd gates each animation on a counter: the death sequence on
## `dying and death_anim > 0`, KICK.ANI on kick_ticks, PUNCH.ANI on
## punch_ticks, the cornerhead poses on cornerhead. A joined client never
## ticks a simulation, so if those do not cross the wire they read zero for
## ever and the animation simply never plays. They did not, and a live
## netplay session reported "no dead animation".
func _test_animation_timers_reach_the_client(t: T_) -> void:
	var port := PORT + 13
	var server: Server_ = Server_.new()
	if not t.ok(server.listen(port, _scheme_text(), 0, 4242),
			"the server listens on %d" % port):
		return
	var a: Client_ = Client_.new()
	a.connect_to("ws://127.0.0.1:%d" % port, "watcher")
	for _i in 200:
		await _pump(server, [a])
		if a.playing():
			break
	if not t.ok(a.playing(), "the client is playing"):
		server.close()
		return

	# Set the four counters on the server's own simulation and let one
	# snapshot carry them across.
	var victim: Player_ = server.sim.players[0]
	victim.dying = true
	victim.death_anim = 7
	victim.kick_ticks = 5
	victim.punch_ticks = 4
	victim.cornerhead = 9
	victim.cornerhead_ticks = 3
	for _i in 40:
		await _pump(server, [a])
		if a.sim != null and a.sim.players[0].death_anim == 7:
			break

	var seen: Player_ = a.sim.players[0]
	t.eq(seen.death_anim, 7,
		"death_anim reaches the client — without it no death animation plays")
	t.eq(seen.kick_ticks, 5, "and kick_ticks, for KICK.ANI")
	t.eq(seen.punch_ticks, 4, "and punch_ticks, for PUNCH.ANI")
	t.eq(seen.cornerhead, 9, "and cornerhead, for the boxed-in poses")
	t.eq(seen.cornerhead_ticks, 3, "and its own frame counter")

	a.close()
	server.close()


## A WON MATCH REOPENS THE ROOM, AND THE HOST CAN PLAY ANOTHER.
##
## docs/IMPROVEMENTS.md A1, live: "match over: player 0 wins the match" and
## then nothing — no lobby, no menu, both windows on the final frame until
## somebody killed them. The whole cycle a session of several matches takes:
## lobby, start, a won match, back to the lobby with the roster intact, and a
## second match that starts from nil-nil on a different seed.
func _test_a_won_match_returns_to_the_lobby(t: T_) -> void:
	var port := PORT + 14
	var server: Server_ = Server_.new()
	if not t.ok(server.listen(port, _scheme_text(), 0, 31, false, true),
			"the server opens a lobby on %d" % port):
		return
	server.the_match.wins_to_win = 1
	var a: Client_ = Client_.new()
	var b: Client_ = Client_.new()
	var all := [a, b]
	a.connect_to("ws://127.0.0.1:%d" % port, "alice")
	b.connect_to("ws://127.0.0.1:%d" % port, "bob")
	var returned := [0]
	a.returned_to_lobby.connect(func(): returned[0] += 1)
	for _i in 200:
		await _pump(server, all)
		if a.in_lobby() and b.in_lobby():
			break
	if not t.ok(a.in_lobby() and b.in_lobby(), "both reach the lobby"):
		server.close()
		return
	var rooms := {a: a.lobby_slot, b: b.lobby_slot}

	# The host's O with no round running used to reach a null sim.
	t.eq(server.override_next_slot(), -1,
		"the host's override key does nothing in a lobby, and does not crash")

	for match_no in 2:
		a.request_start()
		for _i in 300:
			a.send_input(Types_.MoveState.STILL, Types_.Action.NONE)
			b.send_input(Types_.MoveState.STILL, Types_.Action.NONE)
			await _pump(server, all)
			if server.ready_count() == 2 and a.playing() and b.playing():
				break
		if not t.ok(server.ready_count() == 2,
				"match %d: the host's start seats both" % (match_no + 1)):
			server.close()
			return
		t.eq(a.the_match.round_index, 0,
			"match %d starts on round one" % (match_no + 1))
		t.eq(a.the_match.wins_of(a.slot), 0,
			"match %d starts from nil" % (match_no + 1))
		t.ok(not a.the_match.over(),
			"match %d is not over before it is played" % (match_no + 1))
		t.eq(a.slot, rooms[a], "alice keeps her slot across matches")
		t.eq(b.slot, rooms[b], "and so does bob")

		var seed_played := server.the_match.round_seed
		server.sim.kill(server.sim.player_by_slot(b.slot), a.slot)
		for _i in 400:
			a.send_input(Types_.MoveState.STILL, Types_.Action.NONE)
			b.send_input(Types_.MoveState.STILL, Types_.Action.NONE)
			await _pump(server, all)
			if a.in_lobby() and b.in_lobby():
				break
		t.ok(a.in_lobby() and b.in_lobby(),
			"match %d: a won match puts both back in the lobby" % (match_no + 1))
		t.eq(server.state, Server_.State.WAITING,
			"[invariant] match %d: the server reopened the room" % (match_no + 1))
		t.eq(server.sim, null, "and holds no finished field")
		t.eq(returned[0], match_no + 1, "the client said so exactly once")
		t.eq(a.the_match.champion_slot, rooms[a],
			"alice is still shown as the winner while they wait")
		t.eq(a.lobby_roster.size(), 2, "the roster survived the match")
		t.ok(a.lobby_is_host and not b.lobby_is_host,
			"and so did who hosts it")
		t.ok(server.the_match.round_seed != seed_played,
			"the next match will be on a different seed")

	for client in all:
		client.close()
	server.close()
