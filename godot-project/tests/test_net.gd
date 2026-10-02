# The wire format. No sockets — this is the layer below them.
#
# The load-bearing assertion is the round trip: apply(write(sim)) must leave a
# simulation whose state_hash() equals the original's. One assertion covering
# every field at once, made on states from a real round rather than hand-built
# ones. A field added to player.gd or bomb.gd and forgotten in snapshot.gd
# fails it on the next run.
extends SceneTree

const T_ := preload("res://tests/t.gd")
const Const_ := preload("res://scripts/core/const.gd")
const Types_ := preload("res://scripts/core/types.gd")
const Values_ := preload("res://scripts/core/values.gd")
const Scheme_ := preload("res://scripts/core/scheme.gd")
const Client_ := preload("res://scripts/net/client.gd")
const Field_ := preload("res://scripts/sim/field.gd")
const Sim_ := preload("res://scripts/sim/sim.gd")
const Player_ := preload("res://scripts/sim/player.gd")
const Bomb_ := preload("res://scripts/sim/bomb.gd")
const Protocol_ := preload("res://scripts/net/protocol.gd")
const Snapshot_ := preload("res://scripts/net/snapshot.gd")


func _init() -> void:
	var t := T_.new("net")
	_test_protocol_round_trip(t)
	_test_protocol_rejects_junk(t)
	_test_snapshot_round_trip(t)
	_test_snapshot_through_a_whole_round(t)
	_test_snapshot_carries_everything(t)
	_test_snapshot_size(t)
	_test_match_message(t)
	_test_client_rebuilds_on_a_new_level(t)
	quit(t.finish())


func _test_protocol_round_trip(t: T_) -> void:
	var hello := Protocol_.decode(Protocol_.hello("carlos"))
	t.eq(hello.get("id"), Protocol_.C_HELLO, "hello decodes")
	t.eq(hello.get("name"), "carlos", "with its name")
	t.eq(hello.get("version"), Protocol_.VERSION, "and its version")

	# A name with non-ASCII must survive, since the field is UTF-8.
	var uni := Protocol_.decode(Protocol_.hello("Ñandú 💣"))
	t.eq(uni.get("name"), "Ñandú 💣", "a UTF-8 name survives")

	var inp := Protocol_.decode(Protocol_.input(1234, Types_.MoveState.LEFT,
		Types_.Action.FIRST_DOUBLE))
	t.eq(inp.get("id"), Protocol_.C_INPUT, "input decodes")
	t.eq(inp.get("tick"), 1234, "with its tick")
	t.eq(inp.get("move"), Types_.MoveState.LEFT, "its move")
	t.eq(inp.get("action"), Types_.Action.FIRST_DOUBLE, "and its action")
	t.eq(inp.get("first_held"), false,
		"held defaults false when the caller does not say")

	var held_inp := Protocol_.decode(Protocol_.input(1234,
		Types_.MoveState.STILL, Types_.Action.NONE, true))
	t.eq(held_inp.get("first_held"), true, "and true survives the wire")

	var hb := Protocol_.decode(Protocol_.heartbeat(99))
	t.eq(hb.get("tick"), 99, "heartbeat carries its tick")

	# A scheme's whole text goes on the wire, so a browser needs no local copy.
	var scheme_text := _scheme_text()
	var wel := Protocol_.decode(Protocol_.welcome(3, 4242, 7, scheme_text, true))
	t.eq(wel.get("slot"), 3, "welcome carries the slot")
	t.eq(wel.get("seed"), 4242, "the seed")
	t.eq(wel.get("level"), 7, "the level")
	t.ok(wel.get("team_play"), "the teamplay flag")
	t.eq(wel.get("scheme"), scheme_text, "and the scheme verbatim")

	# A large tick must survive: a long match is 3000 ticks a round.
	var big := Protocol_.decode(Protocol_.input(4000000, 0, 0))
	t.eq(big.get("tick"), 4000000, "a large tick survives the u32")

	var rej := Protocol_.decode(Protocol_.reject(Protocol_.REJECT_FULL))
	t.eq(rej.get("code"), Protocol_.REJECT_FULL, "reject carries its reason")
	t.ok(Protocol_.REJECT_TEXT.has(Protocol_.REJECT_FULL),
		"and every reason has text")
	for code in [Protocol_.REJECT_VERSION, Protocol_.REJECT_FULL,
			Protocol_.REJECT_NAME_TAKEN, Protocol_.REJECT_IN_PROGRESS]:
		t.ok(Protocol_.REJECT_TEXT.has(code), "reject %d has text" % code)

	var over := Protocol_.decode(Protocol_.round_over(
		Sim_.Outcome.LAST_STANDING, 4, 1))
	t.eq(over.get("outcome"), Sim_.Outcome.LAST_STANDING, "round-over decodes")
	t.eq(over.get("winner_slot"), 4, "with the winner")
	t.eq(over.get("winner_team"), 1, "and the team")
	# -1 must survive, which is what "nobody won" looks like.
	var draw := Protocol_.decode(Protocol_.round_over(Sim_.Outcome.DRAW, -1, -1))
	t.eq(draw.get("winner_slot"), -1, "a draw has no winner slot")
	t.eq(draw.get("winner_team"), -1, "and no winning team")

	var snd := Protocol_.decode(Protocol_.sounds([
		{"slot": 2, "effect": Types_.SoundEffect.BOMB_DROP, "arg": 0},
		{"slot": -1, "effect": Types_.SoundEffect.HURRY, "arg": 0},
		{"slot": 4, "effect": Types_.SoundEffect.DISEASE_CAUGHT, "arg": 9}]))
	var events: Array = snd.get("events", [])
	t.eq(events.size(), 3, "three sound events decode")
	t.eq(events[0]["slot"], 2, "the first has its slot")
	t.eq(events[0]["effect"], Types_.SoundEffect.BOMB_DROP, "and its effect")
	t.eq(events[1]["slot"], -1, "a slotless event survives as -1")
	# The argument is what names WHICH disease, and SOUNDLST has twelve ranges
	# for them. Losing it would make every disease sound like the first.
	t.eq(events[2]["arg"], Types_.Disease.LEPROSY,
		"and the argument survives")
	t.eq(events[0]["arg"], 0, "an event with no argument decodes as 0")

	# An event dictionary written without an "arg" key at all — which is what
	# older call sites look like — must still encode.
	var legacy := Protocol_.decode(Protocol_.sounds([
		{"slot": 0, "effect": Types_.SoundEffect.BOMB_DROP}]))
	t.eq((legacy.get("events", []) as Array).size(), 1,
		"an event with no arg key still encodes")

	var pz := Protocol_.decode(Protocol_.pause(true))
	t.ok(pz.get("paused"), "pause decodes")

	var st := Protocol_.decode(Protocol_.start())
	t.eq(st.get("id"), Protocol_.C_START, "start decodes")

	var lob := Protocol_.decode(Protocol_.lobby(2, true, [
		{"slot": 0, "name": "alice"}, {"slot": 2, "name": "Ñandú 💣"}]))
	t.eq(lob.get("your_slot"), 2, "lobby carries your own slot")
	t.ok(lob.get("is_host"), "and whether you're the host")
	var roster: Array = lob.get("roster", [])
	t.eq(roster.size(), 2, "the whole roster decodes")
	t.eq(roster[0]["slot"], 0, "each entry's slot")
	t.eq(roster[0]["name"], "alice", "and name")
	t.eq(roster[1]["name"], "Ñandú 💣", "a UTF-8 name in the roster survives")

	var empty_lobby := Protocol_.decode(Protocol_.lobby(0, false, []))
	t.eq((empty_lobby.get("roster", []) as Array).size(), 0,
		"an empty roster (a room of one) decodes cleanly")


# A truncated or hostile packet must decode to nothing, never crash. A server
# that can be killed by a malformed message is a server nobody can host.
func _test_protocol_rejects_junk(t: T_) -> void:
	t.eq(Protocol_.decode(PackedByteArray()), {}, "an empty packet is rejected")
	t.eq(Protocol_.decode(PackedByteArray([255])), {},
		"an unknown message id is rejected")

	# Every message, truncated at every length short of complete.
	var messages := [
		Protocol_.hello("abc"), Protocol_.input(1, 2, 3),
		Protocol_.heartbeat(7), Protocol_.welcome(0, 1, 2, "x", false),
		Protocol_.reject(1), Protocol_.round_over(1, 2, 3),
		Protocol_.sounds([{"slot": 1, "effect": 2, "arg": 3}]),
		Protocol_.pause(true),
		Protocol_.match_state(1, 99, 2, PackedInt32Array([1, 0, 2]),
			PackedInt32Array([2, 1]), 2, -1, -1),
	]
	var survived := 0
	for full in messages:
		for cut in range(1, (full as PackedByteArray).size()):
			var short: PackedByteArray = (full as PackedByteArray).slice(0, cut)
			# Must return a Dictionary either way and must not crash.
			var got := Protocol_.decode(short)
			survived += 1
			if not got.is_empty():
				# Decoding a prefix is allowed only if every field it claims is
				# really there; the length checks are what guarantee that.
				t.ok(got.has("id"), "a partial decode still names its id")
	# Every prefix of every message, which is what a half-received packet is.
	t.ok(survived >= 30,
		"%d truncated packets all handled without crashing" % survived)

	# A hello with an empty name is refused: it would otherwise join as "".
	var nameless := Protocol_.hello("")
	t.eq(Protocol_.decode(nameless), {}, "a nameless hello is rejected")


# The assertion the netcode rests on.
func _test_snapshot_round_trip(t: T_) -> void:
	var sim := _sim(4, 90, 7)
	# Put the state somewhere interesting first: powerups collected, abilities
	# granted, diseases caught, bombs placed and moving.
	var p: Player_ = sim.players[0]
	sim.give_powerup(p, Types_.PowerUp.KICK)
	sim.give_powerup(p, Types_.PowerUp.JELLY)
	sim.give_powerup(p, Types_.PowerUp.FLAME)
	sim.catch_disease(p, Types_.Disease.CONTROLS_REVERSED)
	sim.catch_disease(sim.players[1], Types_.Disease.MOLASSES)
	sim.give_powerup(sim.players[2], Types_.PowerUp.TRIGGER)
	sim.place_bomb(sim.players[2])
	var b := sim.place_bomb(p)
	b.move_dir = Types_.Dir.RIGHT
	b.speed = 1000
	b.jelly_bounce = true
	sim.kill(sim.players[3], 0)
	for _i in 5:
		sim.tick()

	var before := sim.state_hash()
	var bytes := Snapshot_.write(sim)
	t.ok(bytes.size() > 0, "a snapshot is produced")

	var client: Sim_ = Sim_.new()
	t.ok(Snapshot_.apply(client, bytes), "and applies to a fresh simulation")
	t.eq(client.state_hash(), before,
		"[invariant] the round trip reproduces the state hash exactly")

	# And the individual fields, so a failure above says WHERE.
	t.eq(client.tick_count, sim.tick_count, "tick count survives")
	t.eq(client.time_left, sim.time_left, "the round clock survives")
	t.eq(client.hurry_index, sim.hurry_index, "the hurry index survives")
	t.eq(client.players.size(), sim.players.size(), "every player survives")
	t.eq(client.bombs.size(), sim.bombs.size(), "every bomb survives")
	t.eq(client.field.to_bytes(), sim.field.to_bytes(), "the field survives")


# The same assertion on every tick of a real round, which is where an
# uncarried field actually shows up: some states only occur mid-explosion.
func _test_snapshot_through_a_whole_round(t: T_) -> void:
	var sim := _sim(4, 90, 31)
	for p in sim.players:
		sim.give_powerup(p, Types_.PowerUp.KICK)
		sim.give_powerup(p, Types_.PowerUp.PUNCH)
	var client: Sim_ = Sim_.new()
	var mismatches := 0
	var script := [Types_.MoveState.RIGHT, Types_.MoveState.DOWN,
		Types_.MoveState.LEFT, Types_.MoveState.UP]

	for tick in 220:
		for i in sim.players.size():
			var action := Types_.Action.NONE
			if tick % 17 == i:
				action = Types_.Action.FIRST
			elif tick % 29 == i:
				action = Types_.Action.SECOND
			sim.set_input(i, script[(tick / 7 + i) % 4], action)
		sim.tick()
		if not Snapshot_.apply(client, Snapshot_.write(sim)):
			mismatches += 1
			continue
		if client.state_hash() != sim.state_hash():
			mismatches += 1
	t.eq(mismatches, 0,
		"[invariant] 220 ticks of a real round all round-trip exactly")

	# Hurry's closing wall is a state the loop above never reaches. It needs a
	# round that is still RUNNING — the loop above may well have ended one, and
	# _tick_round() stops advancing the wall once a round is over, which is why
	# the first version of this saw no Hurry at all.
	var hsim := _sim(4, 90, 77)
	var hclient: Sim_ = Sim_.new()
	hsim.time_left = Values_.V[Const_.Res.HURRY_AT_SECONDS] * Const_.TICK_HZ + 1
	var hurry_mismatches := 0
	for _i in 200:
		hsim.tick()
		Snapshot_.apply(hclient, Snapshot_.write(hsim))
		if hclient.state_hash() != hsim.state_hash():
			hurry_mismatches += 1
	t.eq(hurry_mismatches, 0, "[invariant] and so does Hurry's closing wall")
	t.ok(hsim.hurry_index > 0, "Hurry really did run (%d cells closed)"
		% hsim.hurry_index)


# A field left out of the wire format is the failure mode this guards. Each
# mutation below changes one field on the server side only; the round trip must
# notice every one.
func _test_snapshot_carries_everything(t: T_) -> void:
	var mutations := {
		"player position": func(s: Sim_): s.players[0].x += 137,
		"player speed": func(s: Sim_): s.players[0].speed += 7,
		"player flame": func(s: Sim_): s.players[0].flame_len += 1,
		"bombs available": func(s: Sim_): s.players[0].bombs_available += 1,
		"kick ability": func(s: Sim_): s.players[0].can_kick = true,
		"punch ability": func(s: Sim_): s.players[0].can_punch = true,
		"grab ability": func(s: Sim_): s.players[0].can_grab = true,
		"spooge ability": func(s: Sim_): s.players[0].can_spooge = true,
		"jelly ability": func(s: Sim_): s.players[0].jelly_bombs = true,
		"trigger stock": func(s: Sim_): s.players[0].trigger_bombs = 3,
		"pickup pause": func(s: Sim_): s.players[0].pickup_pause = 2,
		"a disease": func(s: Sim_): s.players[0].disease_ticks[3] = 120,
		"disease freshness": func(s: Sim_): s.players[0].disease_freshness = 44,
		"a collected powerup": func(s: Sim_): s.players[0].collected[4] = 2,
		"the pickup count": func(s: Sim_): s.players[0].pickups = 9,
		"the warp cooldown": func(s: Sim_): s.players[0].warp_cooldown = 6,
		"invulnerability": func(s: Sim_): s.players[0].invulnerable = 4,
		"death": func(s: Sim_): s.players[0].dying = true,
		"the killer": func(s: Sim_): s.players[0].killed_by = 5,
		"the team": func(s: Sim_): s.players[0].team = 1,
		"facing": func(s: Sim_): s.players[0].facing = Types_.Dir.UP,
		"a brick": func(s: Sim_): s.field.brick[7] = Types_.Brick.SOLID,
		"a powerup on the field": func(s: Sim_): s.field.powerup[9] = 3,
		"a flame": func(s: Sim_): s.field.add_flame(3, 3, 1, 2, 10),
		"the round clock": func(s: Sim_): s.time_left -= 500,
		"the hurry index": func(s: Sim_): s.hurry_index = 12,
		"the outcome": func(s: Sim_): s.outcome = Sim_.Outcome.TIME_UP,
		"the winner": func(s: Sim_): s.winner_slot = 2,
		"teamplay": func(s: Sim_): s.team_play = true,
	}
	for what in mutations:
		var sim := _sim(4, 0, 5)
		var client: Sim_ = Sim_.new()
		Snapshot_.apply(client, Snapshot_.write(sim))
		var clean := client.state_hash()
		mutations[what].call(sim)
		Snapshot_.apply(client, Snapshot_.write(sim))
		t.ok(client.state_hash() != clean,
			"the wire format carries %s" % what)

	# Bomb fields, which need a bomb to exist first.
	var bomb_mutations := {
		"bomb position": func(b: Bomb_): b.x += 200,
		"bomb direction": func(b: Bomb_): b.move_dir = Types_.Dir.LEFT,
		"bomb speed": func(b: Bomb_): b.speed = 1300,
		"bomb flight": func(b: Bomb_): b.flying = true,
		"bomb flight target": func(b: Bomb_): b.fly_to_x = 5000,
		"bomb trigger flag": func(b: Bomb_): b.triggered = true,
		"bomb jelly flag": func(b: Bomb_): b.jelly_bounce = true,
		"bomb carrier": func(b: Bomb_): b.carried_by = 1,
		"bomb bounces": func(b: Bomb_): b.cells_travelled = 2,
		"bomb owner": func(b: Bomb_): b.owner = 3,
		"bomb chain owner": func(b: Bomb_): b.chain_owner = 3,
		"bomb state": func(b: Bomb_): b.state = Types_.BombState.DUD,
		"bomb fuze": func(b: Bomb_): b.fuze = 17,
		"bomb reach": func(b: Bomb_): b.flame_len = 5,
	}
	for what in bomb_mutations:
		var sim := _sim(4, 0, 5)
		sim.place_bomb(sim.players[0])
		var client: Sim_ = Sim_.new()
		Snapshot_.apply(client, Snapshot_.write(sim))
		var clean := client.state_hash()
		bomb_mutations[what].call(sim.bombs[0])
		Snapshot_.apply(client, Snapshot_.write(sim))
		t.ok(client.state_hash() != clean,
			"the wire format carries %s" % what)


# The size the plan's bandwidth estimate rests on.
func _test_snapshot_size(t: T_) -> void:
	var sim := _sim(10, 90, 3)
	for p in sim.players:
		sim.place_bomb(p)
	var size := Snapshot_.write(sim).size()
	t.ok(size < 4096,
		"a ten-player snapshot with ten bombs is %d bytes, under 4 KB" % size)
	var per_second := size * Const_.TICK_HZ
	t.ok(per_second < 80000,
		"which is %d bytes/s per client at 20 Hz" % per_second)
	t.note("snapshot %d B, %.0f kbps per client at %d Hz"
		% [size, per_second * 8.0 / 1000.0, Const_.TICK_HZ])
	# fpc_atomic's design costs ~1.6 Mbps per client (docs/PLAN.md measured it
	# from its record sizes). Ours must be a clear improvement or the 20 Hz
	# decision bought nothing — but the bar is stated as a measurement, not as
	# an invented fraction.
	t.ok(per_second * 8 < 800000,
		"%d kbps per client, under half of fpc_atomic's 1.6 Mbps"
			% (per_second * 8 / 1000))


# S_MATCH. The score, and the seed and level of the round now starting — the
# client builds its own static geometry from those two and never receives it,
# so losing either would render round two on round one's map.
func _test_match_message(t: T_) -> void:
	var wins := PackedInt32Array([0, 2, 0, 1, 0, 0, 0, 0, 0, 0])
	var team_wins := PackedInt32Array([1, 2, 0, 0, 0, 0, 0, 0, 0, 0])
	var got := Protocol_.decode(Protocol_.match_state(3, 987654321, 7,
		wins, team_wins, 2, 1, 1))
	t.eq(got.get("id"), Protocol_.S_MATCH, "it is a match message")
	t.eq(got.get("round_index"), 3, "the round index survives")
	t.eq(got.get("seed"), 987654321, "so does a large seed")
	t.eq(got.get("level"), 7, "and the level")
	t.eq(got.get("wins_to_win"), 2, "and the target")
	t.eq(got.get("champion_slot"), 1, "and the champion")
	t.eq(got.get("champion_team"), 1, "and their team")
	t.eq(got.get("wins"), wins, "every slot's wins survive")
	t.eq(got.get("team_wins"), team_wins, "and every team's")

	# No champion yet is -1 on both, which must not read back as 0 — slot 0
	# would then look like it had won.
	var running := Protocol_.decode(Protocol_.match_state(0, 1, 0,
		wins, team_wins, 2, -1, -1))
	t.eq(running.get("champion_slot"), -1, "an unwon match has no champion")
	t.eq(running.get("champion_team"), -1, "and no champion team")

	# The version had to move for this: a version-1 client reading a version-2
	# S_SOUNDS would misread every event after the first. It moved again for
	# C_INPUT's fourth byte (hold-to-carry) — a version-2 client's 3-byte
	# input would leave the server reading one byte short of the next message.
	# And again for S_SLOT_OVERRIDDEN (the host-override key), and again for
	# C_START/S_LOBBY (the pre-game lobby) — two more new message types, not
	# layout changes to an existing one, but tracked here anyway so this
	# assertion stays the one place that has to move when it does. And again
	# for the player record's animation timers (death_anim, kick_ticks,
	# punch_ticks, cornerhead, cornerhead_ticks): a client draws only what the
	# snapshot carries, so without them a networked player died, kicked and
	# punched with no animation — and a version-5 client reading a version-6
	# record would misread everything after warp_cooldown.
	t.eq(Protocol_.VERSION, 7, "the protocol version moved with each layout")


# The client rebuilds its field when a match message names a different LEVEL.
#
# This is the one thing a snapshot cannot fix by itself: the static geometry —
# arrows, warps, conveyors, trampolines — is derived from the level on both
# sides and never sent, so a client holding the wrong level draws bombs
# bouncing off arrows that are not there.
#
# Driven directly rather than over a socket because the server keeps one level
# for a whole match today, so no real packet exercises this path. That is
# exactly why it needs a test: the code is unreachable in practice and would
# rot unnoticed.
func _test_client_rebuilds_on_a_new_level(t: T_) -> void:
	var client: Client_ = Client_.new()
	var scheme: Scheme_ = Scheme_.new()
	t.ok(scheme.parse_text(_scheme_text(), "<test>"), "the fixture parses")
	client.scheme_text = _scheme_text()
	client.level = 0
	client.sim = Sim_.new()
	client.sim.level = 0
	var slots := []
	for i in Const_.PLAYER_COUNT:
		slots.append({"slot": i, "team": i % 2})
	client.sim.setup(scheme, slots, 1)
	client.the_match.round_index = 0
	client.the_match.round_seed = 1

	var plain := client.sim.field.static_bytes()
	# Level 9 is one of the five with specials (tests/test_extras.gd lists
	# 2, 3, 4, 9 and 10), so its geometry is not the empty level 0's.
	client.apply_match_state({"round_index": 0, "seed": 1, "level": 9,
		"wins_to_win": 2, "champion_slot": -1, "champion_team": -1,
		"wins": PackedInt32Array(), "team_wins": PackedInt32Array()})
	t.eq(client.level, 9, "the client took the new level")
	t.eq(client.sim.level, 9, "and told its simulation")
	t.ok(client.sim.field.static_bytes() != plain,
		"and rebuilt the static geometry, which no snapshot carries")

	# A message naming the round it is already playing changes nothing.
	var settled := client.sim.field.static_bytes()
	client.apply_match_state({"round_index": 0, "seed": 1, "level": 9,
		"wins_to_win": 2, "champion_slot": -1, "champion_team": -1,
		"wins": PackedInt32Array(), "team_wins": PackedInt32Array()})
	t.ok(client.sim.field.static_bytes() == settled,
		"a repeated match message rebuilds nothing")


func _scheme_text() -> String:
	var lines := PackedStringArray()
	lines.append("-V,2")
	lines.append("-N,Net fixture (10)")
	lines.append("-B,90")
	for y in Const_.FIELD_H:
		lines.append("-R,%2d,%s" % [y, ":".repeat(Const_.FIELD_W)])
	for p in Const_.PLAYER_COUNT:
		lines.append("-S,%d,%d,%d,%d" % [p, 1 + p, 1 + (p % 8), p % 2])
	for i in Const_.POWERUP_COUNT:
		lines.append("-P,%2d, 0,0, 0, 0,x" % i)
	return "\n".join(lines)


func _sim(count: int, density: int, round_seed: int) -> Sim_:
	var lines := PackedStringArray()
	lines.append("-V,2")
	lines.append("-N,Net fixture (10)")
	lines.append("-B,%d" % density)
	for y in Const_.FIELD_H:
		var ch := "." if density == 0 else ":"
		lines.append("-R,%2d,%s" % [y, ch.repeat(Const_.FIELD_W)])
	for p in Const_.PLAYER_COUNT:
		lines.append("-S,%d,%d,%d,%d" % [p, 1 + p, 1 + (p % 8), p % 2])
	for i in Const_.POWERUP_COUNT:
		lines.append("-P,%2d, 0,0, 0, 0,x" % i)
	var s: Scheme_ = Scheme_.new()
	s.parse_text("\n".join(lines), "<net>")
	assert(s.ok(), "fixture must parse: %s" % s.error())

	var slots := []
	for i in count:
		slots.append({"slot": i, "team": i % 2})
	var sim: Sim_ = Sim_.new()
	sim.setup(s, slots, round_seed)
	return sim
