# The wire protocol. Binary, little-endian, one byte of message id first.
#
# ---------------------------------------------------------------------------
# TOPOLOGY
# ---------------------------------------------------------------------------
# Server-authoritative with no client prediction, which is fpc_atomic's design
# and the original's. A client sends nothing but its input and renders nothing
# but what it is told. That makes the whole thing verifiable: the client's
# state_hash() must equal the server's on every snapshot, and any difference is
# a bug rather than a smoothing artefact.
#
# ---------------------------------------------------------------------------
# RATE AND SIZE
# ---------------------------------------------------------------------------
# One snapshot per simulation tick — 20 Hz, because that is the rate the
# original runs at (docs/ORACLE.md section 1). fpc_atomic broadcasts at 50 Hz
# over a 100 Hz sim, and docs/PLAN.md measured that at ~1.6 Mbps per client.
#
# Measured here: the field is 6 planes of 165 cells = 990 B, ten players are
# ~90 B each, and a bomb is ~40 B. So a full snapshot is roughly 2 KB, and at
# 20 Hz that is about 40 KB/s — 320 kbps per client. A fifth of fpc's, and low
# enough that Phase 10's delta encoding stays an optimisation rather than a
# prerequisite.
#
# ---------------------------------------------------------------------------
# WHY NOT REUSE fpc_atomic's 26 MESSAGES
# ---------------------------------------------------------------------------
# Its message set carries its menu flow — player setup, field setup, master
# election. That flow is Phase 9's problem and its shape should follow from
# this port's screens, not from another program's. What IS reused is the
# semantics that matter: input up, full state down, a heartbeat, and a
# server-forced pause when a client falls too far behind.
class_name Protocol

const Const_ := preload("res://scripts/core/const.gd")

## Bumped whenever a message's layout changes. A client and server that
## disagree refuse each other at once rather than misreading a snapshot —
## fpc_atomic learned this the hard way and added a version check at its 0.08.
##
## 1 -> 2: S_SOUNDS carries a third byte per event (the disease a DISEASE_CAUGHT
## names), and S_MATCH exists.
## 2 -> 3: C_INPUT carries a fourth byte — whether the FIRST action button is
## held down this tick, for hold-to-carry (docs/BUGS.md, Player_.
## action_first_held). Snapshot.LAYOUT moves alongside this.
const VERSION := 3

# Client -> server
const C_HELLO := 1        ## name, protocol version
const C_INPUT := 2        ## move state, action and held-state for this tick
const C_HEARTBEAT := 3    ## proof the client is still keeping up
const C_READY := 4        ## the client has the scheme and can be spawned

# Server -> client
const S_WELCOME := 64     ## your slot, the round seed, the scheme
const S_SNAPSHOT := 65    ## the whole simulation state for one tick
const S_ROUND_OVER := 66  ## outcome and winner
const S_SOUNDS := 67      ## events raised on the tick just sent
const S_REJECT := 68      ## why you cannot join
const S_PAUSE := 69       ## everyone waits; a client is behind
const S_MATCH := 70       ## the score, and the seed of the round now starting

# Why a join was refused. fpc_atomic's EC_* codes, minus the ones that belong
# to its menu flow.
const REJECT_VERSION := 1
const REJECT_FULL := 2
const REJECT_NAME_TAKEN := 3
const REJECT_IN_PROGRESS := 4

const REJECT_TEXT := {
	REJECT_VERSION: "protocol version mismatch",
	REJECT_FULL: "the game is full",
	REJECT_NAME_TAKEN: "that name is taken",
	REJECT_IN_PROGRESS: "the round is already under way",
}


# ---------------------------------------------------------------------------
# Writing
# ---------------------------------------------------------------------------
static func hello(name: String) -> PackedByteArray:
	var b := PackedByteArray()
	b.append(C_HELLO)
	_put_u16(b, VERSION)
	_put_string(b, name)
	return b


static func input(tick: int, move: int, action: int,
		first_held: bool = false) -> PackedByteArray:
	var b := PackedByteArray()
	b.append(C_INPUT)
	# The tick the client believed it was on. The server does NOT act on it —
	# it is authoritative — but it is what tells the server how far behind a
	# client is, which is what the pause is for.
	_put_u32(b, tick)
	b.append(move)
	b.append(action)
	b.append(int(first_held))
	return b


static func heartbeat(tick: int) -> PackedByteArray:
	var b := PackedByteArray()
	b.append(C_HEARTBEAT)
	_put_u32(b, tick)
	return b


static func ready() -> PackedByteArray:
	var b := PackedByteArray()
	b.append(C_READY)
	return b


static func welcome(slot: int, round_seed: int, level: int,
		scheme_text: String, team_play: bool) -> PackedByteArray:
	var b := PackedByteArray()
	b.append(S_WELCOME)
	b.append(slot)
	_put_u32(b, round_seed)
	b.append(level)
	b.append(int(team_play))
	# The scheme travels as its own text rather than as a name, so a client
	# needs no copy of the original's SCHEMES folder to join — which matters
	# for a browser, where there is no folder to read.
	_put_string(b, scheme_text)
	return b


static func reject(code: int) -> PackedByteArray:
	var b := PackedByteArray()
	b.append(S_REJECT)
	b.append(code)
	return b


static func pause(paused: bool) -> PackedByteArray:
	var b := PackedByteArray()
	b.append(S_PAUSE)
	b.append(int(paused))
	return b


static func round_over(outcome: int, winner_slot: int, winner_team: int)-> PackedByteArray:
	var b := PackedByteArray()
	b.append(S_ROUND_OVER)
	b.append(outcome)
	b.append(clampi(winner_slot + 1, 0, 255))
	b.append(clampi(winner_team + 1, 0, 255))
	return b


## Three bytes per event: whose it was, what it was, and one argument. The
## argument names the specific sound where an effect has more than one — a
## DISEASE_CAUGHT says WHICH disease, because SOUNDLST has twelve per-disease
## ranges at 3000 + 50*i rather than one for all of them.
static func sounds(events: Array) -> PackedByteArray:
	var b := PackedByteArray()
	b.append(S_SOUNDS)
	b.append(mini(events.size(), 255))
	for i in mini(events.size(), 255):
		var e: Dictionary = events[i]
		b.append(clampi(int(e["slot"]) + 1, 0, 255))
		b.append(int(e["effect"]))
		b.append(clampi(int(e.get("arg", 0)), 0, 255))
	return b


## The match state, sent when a round starts and when the match ends.
##
## It carries the next round's SEED and LEVEL as well as the score, because a
## client builds its own field from those two and never receives the static
## geometry — see scripts/sim/field.gd. Without them a second round would be
## rendered on the first round's map.
static func match_state(round_index: int, round_seed: int, level: int,
		wins: PackedInt32Array, team_wins: PackedInt32Array,
		wins_to_win: int, champion_slot: int,
		champion_team: int) -> PackedByteArray:
	var b := PackedByteArray()
	b.append(S_MATCH)
	b.append(mini(round_index, 255))
	_put_u32(b, round_seed)
	b.append(level)
	b.append(mini(wins_to_win, 255))
	b.append(clampi(champion_slot + 1, 0, 255))
	b.append(clampi(champion_team + 1, 0, 255))
	b.append(mini(wins.size(), 255))
	for i in mini(wins.size(), 255):
		b.append(mini(wins[i], 255))
	b.append(mini(team_wins.size(), 255))
	for i in mini(team_wins.size(), 255):
		b.append(mini(team_wins[i], 255))
	return b


# ---------------------------------------------------------------------------
# Reading
# ---------------------------------------------------------------------------
## Decode one message into a Dictionary with an "id" key, or {} if it is
## malformed. Never raises: a hostile or truncated packet must not be able to
## take the server down.
static func decode(data: PackedByteArray) -> Dictionary:
	if data.is_empty():
		return {}
	var id := data[0]
	var pos := 1
	match id:
		C_HELLO:
			if data.size() < 3:
				return {}
			var version := _get_u16(data, pos)
			pos += 2
			var name := _get_string(data, pos)
			if name.is_empty():
				return {}
			return {"id": id, "version": version, "name": name}
		C_INPUT:
			if data.size() < 8:
				return {}
			return {"id": id, "tick": _get_u32(data, pos),
				"move": data[5], "action": data[6],
				"first_held": data[7] != 0}
		C_HEARTBEAT:
			if data.size() < 5:
				return {}
			return {"id": id, "tick": _get_u32(data, pos)}
		C_READY:
			return {"id": id}
		S_WELCOME:
			if data.size() < 8:
				return {}
			var slot := data[1]
			var round_seed := _get_u32(data, 2)
			var level := data[6]
			var team_play := data[7] != 0
			var scheme := _get_string(data, 8)
			return {"id": id, "slot": slot, "seed": round_seed,
				"level": level, "team_play": team_play, "scheme": scheme}
		S_REJECT:
			if data.size() < 2:
				return {}
			return {"id": id, "code": data[1]}
		S_PAUSE:
			if data.size() < 2:
				return {}
			return {"id": id, "paused": data[1] != 0}
		S_ROUND_OVER:
			if data.size() < 4:
				return {}
			return {"id": id, "outcome": data[1],
				"winner_slot": int(data[2]) - 1, "winner_team": int(data[3]) - 1}
		S_SOUNDS:
			if data.size() < 2:
				return {}
			var n := data[1]
			if data.size() < 2 + n * 3:
				return {}
			var events := []
			for i in n:
				events.append({"slot": int(data[2 + i * 3]) - 1,
					"effect": data[3 + i * 3], "arg": data[4 + i * 3]})
			return {"id": id, "events": events}
		S_MATCH:
			if data.size() < 11:
				return {}
			var n_wins := data[10]
			if data.size() < 11 + n_wins + 1:
				return {}
			var w := PackedInt32Array()
			for i in n_wins:
				w.append(data[11 + i])
			var at := 11 + n_wins
			var n_team := data[at]
			at += 1
			if data.size() < at + n_team:
				return {}
			var tw := PackedInt32Array()
			for i in n_team:
				tw.append(data[at + i])
			return {"id": id, "round_index": data[1],
				"seed": _get_u32(data, 2), "level": data[6],
				"wins_to_win": data[7],
				"champion_slot": int(data[8]) - 1,
				"champion_team": int(data[9]) - 1,
				"wins": w, "team_wins": tw}
		S_SNAPSHOT:
			# The body is the simulation's own byte layout; snapshot.gd owns it.
			if data.size() < 5:
				return {}
			return {"id": id, "tick": _get_u32(data, pos), "body": data.slice(5)}
	return {}


static func snapshot(tick: int, body: PackedByteArray) -> PackedByteArray:
	var b := PackedByteArray()
	b.append(S_SNAPSHOT)
	_put_u32(b, tick)
	b.append_array(body)
	return b


# ---------------------------------------------------------------------------
# Primitives. Little-endian throughout, matching the simulation's own records.
# ---------------------------------------------------------------------------
static func _put_u16(b: PackedByteArray, v: int) -> void:
	b.append(v & 0xFF)
	b.append((v >> 8) & 0xFF)


static func _put_u32(b: PackedByteArray, v: int) -> void:
	b.append(v & 0xFF)
	b.append((v >> 8) & 0xFF)
	b.append((v >> 16) & 0xFF)
	b.append((v >> 24) & 0xFF)


static func _get_u16(b: PackedByteArray, pos: int) -> int:
	if pos + 2 > b.size():
		return 0
	return b[pos] | (b[pos + 1] << 8)


static func _get_u32(b: PackedByteArray, pos: int) -> int:
	if pos + 4 > b.size():
		return 0
	return b[pos] | (b[pos + 1] << 8) | (b[pos + 2] << 16) | (b[pos + 3] << 24)


## A string as a u16 length then UTF-8. Length-prefixed rather than
## NUL-terminated so a scheme's own text can contain anything.
static func _put_string(b: PackedByteArray, s: String) -> void:
	var utf := s.to_utf8_buffer()
	_put_u16(b, utf.size())
	b.append_array(utf)


static func _get_string(b: PackedByteArray, pos: int) -> String:
	var n := _get_u16(b, pos)
	if pos + 2 + n > b.size():
		return ""
	return b.slice(pos + 2, pos + 2 + n).get_string_from_utf8()
