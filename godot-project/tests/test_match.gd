# The match: counting wins to resource 310's two.
#
# The rules are small and every one of them is a place a match could quietly
# never end, or end early, so each gets its own assertion. The two that matter
# most are that a DRAW credits nobody — a match of nothing but draws must stay
# unwon rather than crown somebody — and that a finished match stops counting.
extends SceneTree

const T_ := preload("res://tests/t.gd")
const Const_ := preload("res://scripts/core/const.gd")
const Types_ := preload("res://scripts/core/types.gd")
const Values_ := preload("res://scripts/core/values.gd")
const Match_ := preload("res://scripts/core/match.gd")


func _init() -> void:
	var t := T_.new("match")
	_test_target(t)
	_test_wins(t)
	_test_draws_credit_nobody(t)
	_test_stops_when_over(t)
	_test_teams(t)
	_test_seeds(t)
	_test_intermission(t)
	_test_win_by_kills(t)
	_test_a_solo_win_is_not_a_team_win(t)
	quit(t.finish())


# Resource 310, whose own comment says it is a default that settings override.
func _test_target(t: T_) -> void:
	t.eq(Values_.V[Const_.Res.WINS_TO_WIN], 2,
		"resource 310 says two wins take a match")
	var m: Match_ = Match_.new()
	m.setup(1, 0, false)
	t.eq(m.wins_to_win, 2, "and a fresh match uses it")
	t.eq(m.round_index, 0, "starting on round 0")
	t.ok(not m.over(), "with nobody having won")
	t.eq(m.champion_slot, -1, "and no champion")
	t.eq(m.wins.size(), Const_.PLAYER_COUNT,
		"a win column exists for every slot")

	# The comment says a setting overrides it, so the setting has to work.
	var five: Match_ = Match_.new()
	five.setup(1, 0, false, 5)
	t.eq(five.wins_to_win, 5, "an explicit target overrides resource 310")


func _test_wins(t: T_) -> void:
	var m: Match_ = Match_.new()
	m.setup(1, 0, false)

	t.ok(not m.record(Match_.OUTCOME_LAST_STANDING, 3, 1),
		"one win does not take a match of two")
	t.eq(m.wins_of(3), 1, "but it is counted")
	t.eq(m.wins_of(4), 0, "and only for the winner")
	t.ok(not m.over(), "the match is still running")

	t.ok(m.record(Match_.OUTCOME_LAST_STANDING, 3, 1),
		"the second win takes it")
	t.eq(m.champion_slot, 3, "player 3 is the champion")
	t.ok(m.over(), "and the match is over")
	t.ok(m.summary().contains("3"), "the summary names them: %s" % m.summary())


func _test_draws_credit_nobody(t: T_) -> void:
	var m: Match_ = Match_.new()
	m.setup(1, 0, false)
	for _i in 10:
		t.ok(not m.record(Match_.OUTCOME_DRAW, -1, -1),
			"a draw does not end the match")
		t.ok(not m.record(Match_.OUTCOME_TIME_UP, -1, -1),
			"nor does the clock running out")
	var total := 0
	for w in m.wins:
		total += w
	t.eq(total, 0, "twenty unwon rounds have awarded no wins at all")
	t.ok(not m.over(), "so the match is still unwon after twenty rounds")

	# A LAST_STANDING with no winner recorded — which _check_round_over cannot
	# currently produce, but a future team rule could — must also credit
	# nobody rather than index into the array with -1.
	t.ok(not m.record(Match_.OUTCOME_LAST_STANDING, -1, -1),
		"a win with no winner credits nobody")
	t.ok(not m.over(), "and does not end the match")

	# The OUTCOME decides, not the slot. A draw and a time-up both arrive from
	# the server carrying whatever sim.winner_slot happens to hold, and today
	# that is -1 — so a rule that tested the slot instead of the outcome would
	# look correct here and start awarding wins the moment TIME_UP named the
	# player with the most kills. Recorded WITH a slot for exactly that reason.
	var live: Match_ = Match_.new()
	live.setup(1, 0, false)
	t.ok(not live.record(Match_.OUTCOME_DRAW, 2, 0),
		"a draw with a surviving player still ends nothing")
	t.eq(live.wins_of(2), 0, "and credits them with nothing")
	t.ok(not live.record(Match_.OUTCOME_TIME_UP, 2, 0),
		"nor does the clock running out with somebody alive")
	t.eq(live.wins_of(2), 0, "still nothing")
	t.ok(not live.record(Match_.OUTCOME_RUNNING, 2, 0),
		"and a round that has not finished is not a win either")
	t.eq(live.wins_of(2), 0, "and awards nothing")
	t.ok(not live.over(), "so the match is unwon")


func _test_stops_when_over(t: T_) -> void:
	var m: Match_ = Match_.new()
	m.setup(1, 0, false)
	m.record(Match_.OUTCOME_LAST_STANDING, 0, 0)
	m.record(Match_.OUTCOME_LAST_STANDING, 0, 0)
	t.eq(m.champion_slot, 0, "player 0 won")

	# A late round — a packet that arrived twice, a server that ticked once
	# more — must not move the score or change who won.
	t.ok(m.record(Match_.OUTCOME_LAST_STANDING, 5, 1),
		"recording after the match is over still reports it over")
	t.eq(m.wins_of(5), 0, "and awards nothing")
	t.eq(m.champion_slot, 0, "the champion does not change")


func _test_teams(t: T_) -> void:
	var m: Match_ = Match_.new()
	m.setup(1, 0, true)
	t.ok(m.team_play, "a team match knows it")

	t.ok(not m.record(Match_.OUTCOME_LAST_STANDING, 2, 1), "team 1 wins one")
	t.eq(m.team_wins_of(1), 1, "the team's column moves")
	t.eq(m.wins_of(2), 1, "and so does the survivor's, for the scoreboard")
	t.eq(m.champion_team, Types_.TEAM_UNSET, "nobody has won yet")

	# The second win comes from the OTHER member of the team. Counting
	# individuals would leave the match unwon here, which is the bug this
	# asserts against.
	t.ok(m.record(Match_.OUTCOME_LAST_STANDING, 4, 1),
		"a different player on the same team takes the match")
	t.eq(m.champion_team, 1, "team 1 is the champion")
	t.eq(m.champion_slot, -1, "no individual is")
	t.ok(m.summary().contains("team"), "the summary says so: %s" % m.summary())


func _test_seeds(t: T_) -> void:
	var m: Match_ = Match_.new()
	m.setup(12345, 0, false)
	t.eq(m.round_seed, 12345, "the first round uses the seed it was given")

	var seen := {12345: true}
	var previous := 12345
	for i in 20:
		m.next_round()
		t.eq(m.round_index, i + 1, "the round counter rises")
		t.ok(m.round_seed != previous, "and the seed changes every round")
		t.ok(not seen.has(m.round_seed),
			"round %d's seed is one no earlier round used" % (i + 1))
		t.ok(m.round_seed >= 0, "and stays non-negative")
		seen[m.round_seed] = true
		previous = m.round_seed

	# Both sides compute the next seed from the same one, so the sequence has
	# to be a function of the start and nothing else.
	var again: Match_ = Match_.new()
	again.setup(12345, 0, false)
	for _i in 20:
		again.next_round()
	t.eq(again.round_seed, m.round_seed,
		"two matches from one seed reach the same 20th round")


func _test_intermission(t: T_) -> void:
	t.eq(Values_.V[Const_.Res.SCREEN_MIN_SECONDS], 3,
		"resource 13 waits three seconds at a screen")
	t.eq(Match_.intermission_ticks(), 3 * Const_.TICK_HZ,
		"so the gap between rounds is 60 ticks at 20 Hz")
	t.ok(Match_.intermission_ticks() > 0,
		"and it is not zero, or the winner would never be seen")


# ---------------------------------------------------------------------------
# Win Matches By Kill Total — MESSAGES.TXT 255, OPTIONS.BM's own words:
# "the winner will be determined by the kill count... If you kill yourself with
# your own bomb, your kill count will go down by 1."
# ---------------------------------------------------------------------------
func _test_win_by_kills(t: T_) -> void:
	var m: Match_ = Match_.new()
	m.win_by_kills = true
	m.setup(1, 0, false, 3)
	t.eq(m.wins_to_win, 3, "the target is the same number either way")

	# Two kills in the first round. Nobody has three yet.
	t.ok(not m.record(Match_.OUTCOME_LAST_STANDING, 2, 0, _kills({2: 2})),
		"two kills do not take a match of three")
	t.eq(m.wins_of(2), 2, "and the score column carries them")
	t.eq(m.wins_of(3), 0, "for the killer only")

	# Winning the round is not itself worth anything now.
	t.ok(not m.record(Match_.OUTCOME_LAST_STANDING, 3, 0, _kills({})),
		"a round win with no kills scores nothing in this mode")
	t.eq(m.wins_of(3), 0, "the round winner's column did not move")

	# A time-up still counts its kills: the option says the KILL count decides.
	t.ok(m.record(Match_.OUTCOME_TIME_UP, -1, -1, _kills({2: 1})),
		"the third kill takes the match, even in a round nobody won")
	t.eq(m.champion_slot, 2, "player 2 is the champion")

	# Suicide costs one, and cannot take a score below zero.
	var s: Match_ = Match_.new()
	s.win_by_kills = true
	s.setup(1, 0, false, 5)
	s.record(Match_.OUTCOME_DRAW, -1, -1, _kills({4: 2}))
	t.eq(s.wins_of(4), 2, "two kills")
	s.record(Match_.OUTCOME_DRAW, -1, -1, _kills({4: -1}))
	t.eq(s.wins_of(4), 1, "a suicide takes one back")
	s.record(Match_.OUTCOME_DRAW, -1, -1, _kills({4: -5}))
	t.eq(s.wins_of(4), 0, "and the column stops at zero, not below it")

	# Teams add their members' kills together, by the team each slot is on and
	# NOT by slot parity.
	var team: Match_ = Match_.new()
	team.win_by_kills = true
	team.setup(1, 0, true, 4)
	var teams := PackedInt32Array()
	teams.resize(Const_.PLAYER_COUNT)
	for i in Const_.PLAYER_COUNT:
		teams[i] = 0 if i < 5 else 1
	t.ok(not team.record(Match_.OUTCOME_DRAW, -1, -1, _kills({0: 2, 7: 3}),
			teams), "2 for one side and 3 for the other takes nothing")
	t.eq(team.team_wins_of(0), 2, "slot 0's kills went to team 0")
	t.eq(team.team_wins_of(1), 3, "slot 7's went to team 1 — OPTIONS.BM puts"
		+ " slots 1-5 against 6-10, so parity is not the rule")
	t.ok(team.record(Match_.OUTCOME_DRAW, -1, -1, _kills({1: 2}), teams),
		"team 0's fourth kill takes it")
	t.eq(team.champion_team, 0, "team 0 is the champion")

	# The ordinary mode is untouched by any of this.
	var w: Match_ = Match_.new()
	w.setup(1, 0, false, 2)
	w.record(Match_.OUTCOME_LAST_STANDING, 6, 1, _kills({7: 9}))
	t.eq(w.wins_of(6), 1, "a round win still scores 1 when kills are off")
	t.eq(w.wins_of(7), 0, "and nine kills score nothing")


## A kills-by-slot map as the PackedInt32Array record() takes.
func _kills(by_slot: Dictionary) -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize(Const_.PLAYER_COUNT)
	for slot in by_slot:
		out[int(slot)] = int(by_slot[slot])
	return out


# A match without team play must not end on a TEAM banner.
#
# Every slot has a team number whether or not team play is on —
# Const_.default_team gives one to each — and the match used to copy the
# winner's into champion_team. The victory screen reads that field first, so a
# one-player win announced "TEAM 0 WINS" over the winner's own victory art.
func _test_a_solo_win_is_not_a_team_win(t: T_) -> void:
	var m: Match_ = Match_.new()
	m.setup(1, 0, false, 1)
	t.ok(m.record(Match_.OUTCOME_LAST_STANDING, 0, 0),
		"one win takes a match of one")
	t.eq(m.champion_slot, 0, "player 1 is the champion")
	t.eq(m.champion_team, Types_.TEAM_UNSET,
		"and nobody's team is, because there are no teams")

	# With team play on, the team IS the champion.
	var team: Match_ = Match_.new()
	team.setup(1, 0, true, 1)
	t.ok(team.record(Match_.OUTCOME_LAST_STANDING, 3, 1),
		"a team match ends on a team win")
	t.eq(team.champion_team, 1, "team 1 took it")
