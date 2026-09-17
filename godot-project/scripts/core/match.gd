# The match: a sequence of rounds, and who is winning them.
#
# ---------------------------------------------------------------------------
# HOW LONG A MATCH IS
# ---------------------------------------------------------------------------
# VALUELST resource 310, with the disc's own comment above it:
#
#     ; how many wins to win a match? (default; override by settings config)
#     310,2
#
# Two. `wins_to_win` is therefore settable rather than baked in, exactly as the
# comment says it is in the original.
#
# ---------------------------------------------------------------------------
# WHAT COUNTS AS A WIN
# ---------------------------------------------------------------------------
# LAST_STANDING credits the winner. DRAW and TIME_UP credit nobody — a round
# that nobody won moves the match no closer to ending, which is why a match can
# in principle run forever and why the round counter exists to show that it is.
#
# Team play counts TEAM wins. A team match is won by a team, and crediting the
# individual who happened to survive would let one player's two rounds end a
# match their partner also played.
#
# ---------------------------------------------------------------------------
# WHERE IT LIVES
# ---------------------------------------------------------------------------
# On the server, beside the simulation but not inside it: the sim knows about
# one round and should keep knowing about one round. The client is TOLD the
# match state (Protocol.S_MATCH) rather than deriving it, so a client that
# joins mid-match sees the right score immediately.
extends RefCounted

const Const_ := preload("res://scripts/core/const.gd")
const Types_ := preload("res://scripts/core/types.gd")
const Values_ := preload("res://scripts/core/values.gd")

## Round outcomes, mirroring Sim.Outcome. Duplicated rather than imported
## because sim.gd preloads nothing from here and the dependency should not run
## the other way.
const OUTCOME_RUNNING := 0
const OUTCOME_LAST_STANDING := 1
const OUTCOME_DRAW := 2
const OUTCOME_TIME_UP := 3

var wins_to_win: int = 2
var team_play: bool = false

## Win Matches By Kill Total — MESSAGES.TXT 255, and OPTIONS.BM: "the winner
## will be determined by the kill count. Otherwise, a player wins a match by
## winning the required number of games (score)."
##
## The TARGET is the same number either way. MESSAGES.TXT has both halves of
## that sentence as its own strings — 120 "(Match winner must score %u
## victories)" and 121 "(Match winner must score %u kills)" — one number, two
## words for what it counts, which is why this reuses `wins_to_win` and the
## `wins` array rather than adding a second score. The disc names the column
## both ways too: 208 "Wins" and 209 "Kills".
var win_by_kills: bool = false

## The seed the match started on, kept because Random Start permutes the start
## cells once per MATCH and every round after the first has a different seed.
var first_seed: int = 0

## Wins per slot, and per team. Both are kept whatever the mode, so a scoreboard
## can show individual rounds won inside a team match.
var wins: PackedInt32Array = PackedInt32Array()
var team_wins: PackedInt32Array = PackedInt32Array()

## Which round is being played, from 0. Rises on every round, won or drawn.
var round_index: int = 0

## The seed of the round in progress. Each round gets its own, so a match does
## not replay one layout, and the client is told it so both sides build the
## same field.
var round_seed: int = 1
var level: int = 0

## "Random Each Game" — MESSAGES.TXT 149, the level list's own extra entry, and
## VALUELST's lockout array (1150..1161) exists precisely to keep levels out of
## it. When it is on, the level is derived from the round seed rather than
## rolled, so the server and every client compute the same one and a whole
## match still replays from its first seed.
var random_level: bool = false
var level_count: int = 11

## Set once somebody reaches wins_to_win.
var champion_slot: int = -1
var champion_team: int = Types_.TEAM_UNSET


func setup(first_seed: int, on_level: int, teams: bool,
		target: int = -1) -> void:
	wins_to_win = target if target > 0 else int(Values_.V[Const_.Res.WINS_TO_WIN])
	team_play = teams
	self.first_seed = first_seed
	level = on_level
	round_seed = first_seed
	round_index = 0
	if random_level:
		level = _level_for(first_seed)
	champion_slot = -1
	champion_team = Types_.TEAM_UNSET
	wins = PackedInt32Array()
	team_wins = PackedInt32Array()
	wins.resize(Const_.PLAYER_COUNT)
	# Two teams, but sized by player count so a scheme that numbers its teams
	# oddly cannot index past the end.
	team_wins.resize(Const_.PLAYER_COUNT)


## Record a finished round. Returns true if it ended the match.
##
## Called once per round: server.gd guards it with the same tick test that
## broadcasts S_ROUND_OVER, so a round cannot be counted twice.
func record(outcome: int, winner_slot: int, winner_team: int,
		round_kills: PackedInt32Array = PackedInt32Array(),
		slot_teams: PackedInt32Array = PackedInt32Array()) -> bool:
	if over():
		return true
	if win_by_kills:
		return _record_kills(round_kills, slot_teams)
	if outcome == OUTCOME_LAST_STANDING:
		if team_play:
			if winner_team >= 0 and winner_team < team_wins.size():
				team_wins[winner_team] += 1
				if team_wins[winner_team] >= wins_to_win:
					champion_team = winner_team
			# The surviving player's own tally still moves, for the scoreboard.
			if winner_slot >= 0 and winner_slot < wins.size():
				wins[winner_slot] += 1
		elif winner_slot >= 0 and winner_slot < wins.size():
			wins[winner_slot] += 1
			if wins[winner_slot] >= wins_to_win:
				champion_slot = winner_slot
				# NOT the winner's team. Every player has a team number
				# whether or not team play is on — Const_.default_team gives
				# one to each slot — so copying it here made a solo match end
				# on "TEAM 0 WINS" over the victory screen of the player who
				# had actually won it.
				champion_team = Types_.TEAM_UNSET
	return over()


## Fold a round's kills into the match score, and see whether that ended it.
##
## Every outcome counts, including a time-up and a draw: a round nobody won
## can still have been a round somebody killed two people in, and the option
## says the winner is decided by the kill count, not by the rounds.
func _record_kills(round_kills: PackedInt32Array,
		slot_teams: PackedInt32Array) -> bool:
	for slot in mini(round_kills.size(), wins.size()):
		# A negative running total would be a scoreboard nobody can read, and
		# the packet that carries it is a byte per player. A suicide still
		# costs a kill; it cannot cost more than the player has.
		wins[slot] = maxi(0, wins[slot] + round_kills[slot])
		if team_play:
			# The slot's own team, from whoever is running the round. Slot
			# parity is NOT it: OPTIONS.BM puts slots 1-5 against 6-10, which
			# is what Const_.default_team says when nobody says otherwise.
			var team: int = (slot_teams[slot] if slot < slot_teams.size()
				else Const_.default_team(slot))
			if team >= 0 and team < team_wins.size():
				team_wins[team] = maxi(0, team_wins[team] + round_kills[slot])
	if team_play:
		for team in team_wins.size():
			if team_wins[team] >= wins_to_win:
				champion_team = team
				break
	else:
		# Ties go to the lowest slot, which is the order the scoreboard is
		# drawn in. Nothing on the disc says what the original does here.
		for slot in wins.size():
			if wins[slot] >= wins_to_win:
				champion_slot = slot
				break
	return over()


## Move to the next round. The seed is advanced rather than randomised so a
## whole match replays from its first seed — which is what makes a desync
## reproducible.
func next_round() -> void:
	round_index += 1
	round_seed = _advance(round_seed)
	if random_level:
		level = _level_for(round_seed)


## The level a seed implies. The seed is mixed before use so that the level and
## the NEXT seed are not the same function of the same number — otherwise
## consecutive rounds would walk the level list in step with the layout.
func _level_for(value: int) -> int:
	return posmod(_advance(value ^ 0x5AB1E), maxi(1, level_count))


## A 32-bit LCG step (Numerical Recipes' constants). Any full-period generator
## would do; what matters is that both sides compute the same next seed from
## the same one, and that it is written down.
static func _advance(value: int) -> int:
	return ((value * 1664525 + 1013904223) & 0x7FFFFFFF)


func over() -> bool:
	return champion_slot >= 0 or champion_team >= 0


func wins_of(slot: int) -> int:
	return wins[slot] if slot >= 0 and slot < wins.size() else 0


func team_wins_of(team: int) -> int:
	return team_wins[team] if team >= 0 and team < team_wins.size() else 0


## How long to wait between rounds, in ticks.
##
## VALUELST resource 13 — "MINIMUM number of seconds to wait at screens so that
## other computers can catch up (does not affect non-net games)" — is three
## seconds, and this is exactly that situation: everyone has to see who won
## before the next round takes the field away. The disc does not state a
## between-rounds delay directly, so this is the nearest thing it does state.
static func intermission_ticks() -> int:
	return int(Values_.V[Const_.Res.SCREEN_MIN_SECONDS]) * Const_.TICK_HZ


## A one-line summary, for logs and for the round-over banner.
func summary() -> String:
	if champion_team >= 0 and team_play:
		return "team %d wins the match" % champion_team
	if champion_slot >= 0:
		return "player %d wins the match" % champion_slot
	var best := 0
	for w in wins:
		best = maxi(best, w)
	return "round %d, best %d of %d" % [round_index + 1, best, wins_to_win]
