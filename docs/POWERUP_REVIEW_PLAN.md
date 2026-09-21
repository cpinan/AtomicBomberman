# Powerup review plan

Handoff doc for a fresh (more powerful) agent to pick up where this session
left off. Covers all 13 powerups in `Types.PowerUp` (`scripts/core/types.gd`).
Effect logic lives in `scripts/sim/sim.gd`'s `give_powerup()` (~line 1994) and
the ability functions it calls (`kick_bomb`, `punch_bomb`, `grab_bomb`,
`spooge`, `trigger_bombs`, `_roll_bomb`'s jelly branch). Rendering is
`scripts/render/game_view.gd`. `MANUAL.BM` (original-game or wherever the
extracted manual text lives) is the source of truth for what each one is
supposed to do — quote it before trusting your own assumption.

## Session 2 result — the sim was mostly fine, four real bugs were elsewhere

The reason this doc's earlier rounds kept "fixing" things that stayed broken
live: every fix and every test targeted `give_powerup()` and the ability
functions, and those were already correct. The four bugs actually behind the
live reports were one layer out — in movement, in a timer that never ran, in
bomb position rounding, and in a function that was written and then never
called. All four are fixed, each with a regression test in
`tests/test_abilities.gd`:

1. **KICK fired from a cell away, not on contact** (`_move_player`). The kick
   test ran BEFORE the move and asked only "is there a bomb in the cell I
   face". Turning to face a bomb is what sets `p.facing`, so the bomb shot off
   on the first tick of the direction key with the player still a full cell
   clear of it. **This is also why the red glove and the blue glove looked
   dead**: facing a bomb is the only way to aim a punch or a grab, and for
   anyone also holding the kicker, facing it was enough to kick it away first.
   One bug, three reports. Now the kick fires only when the step is actually
   capped by the bomb. Test: `_test_kick_needs_contact`.
2. **A blocked step could move the player BACKWARDS** (`_slide_x`/`_slide_y`).
   The "flush against the blocked cell" position is behind a player already
   standing past that line — walk off the cell you just bombed, turn back, and
   holding left slid you right. Now clamped. Test:
   `_test_a_blocked_step_never_moves_you_backwards`.
3. **GRAB while standing still froze the player mid-pickup** (`_move_player`).
   Resource 665's `pickup_pause` counted down inside `_move_player`, which
   returns early for a STILL player — so a grab made standing still left it
   stuck at 2 forever. `game_view.gd` draws BPICKUP.ANI's pose while it is
   above zero, AHEAD of the carrying pose, and `draw_bombs_of()` skips a
   carried bomb: the bomb vanished and the player froze. That is exactly what
   "the blue glove does nothing" looks like, and it is NOT what the previous
   two rounds of grab fixes were aimed at. The countdown now lives in `tick()`
   beside `kick_ticks`/`punch_ticks`. Test:
   `_test_pickup_pause_ages_while_standing_still`.
4. **A rolling bomb drifted off the grid every time it turned** (`_roll_bomb`).
   `_at_cell_centre()` is a tolerance, so a turn kept up to half a step of
   error on the axis it was now crossing and every later turn added its own. A
   jelly bomb doing its 1-in-3 crazy turns was visibly off-grid within a few
   bounces, measured at 400 cp (11% of a cell) after a single seed's roll.
   Turns now snap to the intersection (`_turn_rolling_bomb`). Test:
   `_test_a_rolling_bomb_stays_grid_aligned`.
5. **Diseases never passed by contact** (`tick()`). `spread_disease()` was
   written, commented and unit-tested, and then called from nowhere but its
   own test — so in a real match a disease could only ever be caught off a
   skull on the field. MANUAL.BM names the strategy ("passing the disease to
   as many opponents as possible") and VALUELST has two resources that exist
   for nothing else (`DISEASE_FRESHNESS` "frames before it can pass again",
   `DISEASE_MULTIPLIES`). Now wired into `tick()` after movement. Test:
   `_test_disease_passes_by_contact`.

What was checked and found genuinely correct, driven through the REAL keyboard
path (synthetic `InputEventKey` → `Keysets` → `set_input` → `tick`, not direct
function calls): `punch_bomb` via Enter, `stop_bomb` via Enter, grab/hold/throw
via Space, `catch_disease` landing and expiring on schedule (300 ticks),
SUPER_BAD giving 3 at once, and every animation sequence name the view asks
for (`punch east green`, `kick east`, `pickup east green`, `bombwalk east
green`) existing in the real pack. Those are not where the bugs were.

## Session 3 — read against BM95.EXE, not against the manual

`tools/bmexe.py` can disassemble the original. Three powerup rules were read
straight out of it and this port disagreed with all three. Each fix below
cites the address it came from, so the next reader can check the claim instead
of trusting it. Regression tests are in `tests/test_abilities.gd`.

- **`0x41EE51` — the kick gate.** The original computes the player's signed
  offset from their cell centre ALONG the direction they face (`0x426599`
  returns `((px - field_x) mod cell_w) - cell_w/2`), and refuses the kick
  unless that offset is exactly 0. It then requires the kick powerup, a bomb
  in the cell ahead, **and the cell BEYOND the bomb to be free** — `0x41EEAC`
  computes bomb_tile + dir and calls `0x41E5C3`, which is "no bomb there AND
  the cell itself empty". This port kicked without that last test, so a bomb
  flat against a wall played the kick sound and animation over a bomb that
  could not move. It also mattered for the gloves: aiming a punch or a grab
  means facing the bomb, so for a player who also held the kicker there was no
  situation left in which either glove was reachable. The wall case is exactly
  MANUAL.BM's Wallybomb advice, and it now works.
- **`0x42464B` — re-kicking.** The original's `kick_bomb(bomb, dir)` tests
  "already moving" against "direction differs" and, when both hold, rewrites
  the bomb's x and y to its tile centre before taking the new direction. Its
  kick sound plays only when the direction changed or the bomb was at rest.
  This port refused to kick a moving bomb at all, so a rolling bomb could
  never be turned.
- **`0x423A1E` — the jelly crazy turn.** It is `rand()%2 -> {0,1}`, doubled to
  `{0,2}`, then `dir = (dir + {0,2} - 1) & 3`: a quarter turn, left or right.
  It cannot reverse and it cannot carry straight on, and the original does not
  filter the result against what is blocked — it takes the turn and lets the
  next tick's ordinary bounce deal with a wall. This port picked freely among
  all four directions filtered by what was unblocked, producing both outcomes
  the original cannot.

### Confirmed the same, so leave them alone

- `0x41EEE8` — movement is blocked by the cell ahead only when the along-axis
  offset is >= 0, which is what lets a player always move back toward their own
  cell centre. This port's full-cell collision box produces the same stopping
  positions, so the "should the box be smaller" question raised last session is
  **closed**: the original kicks from the adjacent cell centre too. The
  kick/punch conflict was never the box — it was the missing "cell beyond must
  be free" test above.
- `0x424987` — a bomb can be punched in states 0, 1 and 3 (at rest, rolling,
  and one more), but not 2 (already flying). This port allows the same set.

### NOT yet matched — the biggest remaining difference

**A punched bomb travels in one-cell HOPS, not a single flight to a computed
landing cell.** `0x4243F5` onward: the bomb carries a hop counter at struct
offset `+0x48` and a within-hop distance at `+0x46`. The render height is
`sin(progress) * arc`, where the arc is resource 660 (65) while the hop
counter is under 3 and resource 661 (20) from hop 3 onward — which is the real
meaning of "initial three-space bounce height" versus "subsequent one-space
bounces". The same counter gates the jelly crazy turn (`0x423991`: no turn
until the counter reaches 3), so the initial three cells of a punch are
straight and only the bouncing afterwards can wander.

This port instead computes a landing cell up front (`_landing_cell()`) and
interpolates one flight to it. That is why `punch_bomb()` needs a "nowhere to
go" refusal at all — the original never asks the question, it just starts
hopping. Reworking the flight into per-cell hops with a hop counter is the
next substantial piece of work and was deliberately not started this session.

## How to use this doc

Every powerup below has four fields:

- **Icon** — the on-field pickup's sequence name (`scripts/render/game_view.gd`'s
  `POWERUP_SEQ`, drawn from the `"powers"` sheet), so you can identify it
  visually in a screenshot or in-game without guessing from the name alone.
- **Description** — MANUAL.BM's own words for what it does.
- **Known bugs** — every bug this session found for this powerup, fixed or
  not, with commit hashes (`git show <hash>`) so you can see the exact diff
  and reasoning instead of re-discovering it. "None found" means checked
  and clean, not unchecked.
- **Still to verify** — what this session did NOT confirm, in order of
  priority. Do these first.

Every "confirmed correct" claim was checked either by an automated test
(`tools/verify.sh` must stay green — run it before and after any change) or
a live playtest report. Neither guarantees the other axis is fine: a test
proving the sim-layer effect fires does not prove the input dispatch or the
animation looks right, and vice versa. **Test all three layers per
powerup**: (1) does `give_powerup()` apply the right effect, (2) does a real
keypress actually reach that effect, (3) does it look right on screen.

## The 13 powerups

### 1. BOMB — extra bomb
- **Icon**: `power bomb`
- **Description**: MANUAL.BM: "Allows you to drop an additional bomb."
- **Known bugs**: none found.
- **Still to verify**: nothing outstanding. `bombs_total`/`bombs_available`
  both +1, tested in `tests/test_powerups.gd::_test_every_powerup_effect`.

### 2. FLAME — extended flame
- **Icon**: `power flame`
- **Description**: MANUAL.BM: "Allows your flame to shoot further."
- **Known bugs**: none found.
- **Still to verify**: nothing outstanding. `flame_len` +1, propagation
  stops at `n == flame_len` (`sim.gd:_propagate`), tested.

### 3. DISEASE — skull (one random disease)
- **ROOT CAUSE FOUND**: the effect and the new tint were both fine; what was
  missing is that diseases never passed by contact at all (item 5 at the top
  of this doc). The half of the mechanic the manual actually talks about was
  absent from the game.
- **Icon**: `power disease` (a skull)
- **Description**: MANUAL.BM: "Gives you one random 'disease.'"
- **Known bugs**:
  - Fixed: no visual feedback existed at all when a player was diseased —
    the mechanic worked but looked identical to being healthy. Invented a
    sickly-green tint pulse (`game_view.gd:_disease_tint`, commit
    `5070741`) since no original art marks a disease state on the
    character.
- **Still to verify**: does the new tint read clearly without being
  distracting or mistaken for a rendering glitch, and does it stop the
  instant the disease's own duration ends (not linger a frame)? Also worth
  independently confirming, per-disease: several of the 12 diseases have
  subtle or self-only effects (INVISIBLE only shows to opponents,
  SHORT_FUZE/SHORT_FLAME/DUDS only show on your NEXT bomb) — a player who
  catches one of those may still report "nothing happened" even though it
  worked; that's expected, not a bug, but confirm the tint at least still
  shows regardless of which disease landed.

### 4. KICK — kicker (kick bombs down a hallway)
- **Icon**: `power kicker`
- **Description**: MANUAL.BM: "Allows you to kick any bomb down a hallway.
  Kicked bombs can be stopped using [the action button]."
- **Known bugs**:
  - Fixed: the kick fired on FACING a bomb rather than on touching it — see
    item 1 at the top of this doc. This was the single highest-impact bug
    found, because it also disabled PUNCH and GRAB for anyone holding the
    kicker.
  - Fixed: a step blocked by a bomb could shove the player backwards — item 2.
- **Still to verify**: `stop_bomb()` is confirmed correct through the real
  Enter keypress. Worth a live pass on the new contact rule: walking into your
  own bomb should now take a beat before it goes, not fire the instant you
  turn.

### 5. SKATE — shoes (speed boost)
- **Icon**: `power skate`
- **Description**: MANUAL.BM: "Speed Boost. Allows you to run faster."
- **Known bugs**: none found.
- **Still to verify**: nothing outstanding. Confirmed additive (not
  multiplicative), applied immediately, tested.

### 6. PUNCH — red glove (punch bombs)
- **ROOT CAUSE FOUND**: the punch code was correct all along, exactly as the
  two earlier rounds concluded. What was broken was KICK (item 1 at the top of
  this doc) stealing the bomb before it could be punched, for any tester who
  had both. That is why re-reading `punch_bomb()` kept finding nothing wrong.
- **Icon**: `power punch`
- **Description**: MANUAL.BM: "Allows you to punch any bomb."
- **Known bugs**:
  - Fixed: punching into an immediately-blocked cell (a wall right next to
    the bomb) played the full punch animation and sound over a
    zero-distance flight — looked exactly like "nothing happens" in a live
    report. Now returns false / no state change in that case (fixed before
    commit `4eac232`; `git log -p -- scripts/sim/sim.gd` around the
    `punch_bomb` function for the exact diff).
- **Still to verify**: this session confirmed PUNCH works correctly at BOTH
  the sim layer (`punch_bomb()` called directly) AND the real input-dispatch
  layer (SECOND action → `stop_bomb` → `punch_bomb` → `trigger_bombs`,
  driven through `sim.set_input()` + `sim.tick()`, not just calling the
  function directly) — verified twice after live reports that it was "still
  broken," and both times the code was already correct. If a live report
  says this is STILL broken after all this: (a) confirm the tester
  relaunched Godot after the fix — this was the actual cause more than once
  this session; (b) try scenarios not yet tested — punching while moving,
  punching a bomb that already has jelly/trigger on it, punching near map
  edges. Get an exact repro before assuming the code regressed again.

### 7. GRAB — blue glove / gauntlet (pick up, carry, throw)
- **ROOT CAUSE FOUND**: rounds 1 and 2 were both arguing about the CARRY
  MECHANIC, which was not the bug. The bug was the frozen `pickup_pause`
  (item 3 at the top of this doc) making a standing grab draw the pickup pose
  forever while the carried bomb was not drawn at all — plus KICK stealing the
  bomb first (item 1). The hold-to-carry/release-to-throw model from commit
  `75c4734` is confirmed correct through the real Space keypress.
- **Icon**: `power grab`
- **Description**: MANUAL.BM: "Allows you to pick up (grab), carry, and
  throw your bombs." Elsewhere: "you may carry a bomb by grabbing and
  holding down the Drop Bomb button."
- **Known bugs**: the most-reported-broken powerup this session, through
  three iterations:
  1. **Fixed then reverted**: original logic set `hold_required_to_carry`
     from whether the button happened to be down at the exact instant of
     the grab — trivially always true for a real keypress, so every real
     grab auto-dropped one tick after a normal release, read live as "the
     gauntlet does nothing." First fix made grab a tap that carries until
     an explicit second press (commit `5070741`).
  2. **Superseded**: live feedback said that wasn't the wanted mechanic —
     should be genuine hold-to-carry, release-to-throw, per MANUAL.BM's
     literal wording. Reverted to that model correctly this time:
     `hold_required_to_carry` is now unconditionally true on grab, and
     releasing throws (`_throw_carried()`) instead of dropping in place
     (commit `75c4734`).
- **Still to verify — TOP PRIORITY**: fix #2 has NOT been live-confirmed
  yet. Exact steps: pick up the blue glove, drop a bomb, stand on/face it,
  HOLD the drop-bomb key (default Space), confirm it stays carried while
  held and follows the player, then RELEASE and confirm it THROWS (flies
  away, does not just drop at your feet). Also check: pressing the button
  again WHILE still holding should also throw immediately without needing
  to release first (the "fast tap" case — automated in
  `tests/test_abilities.gd::_test_hold_to_carry_release_to_throw`, but
  worth a live confirmation too since this exact powerup has burned three
  rounds of "fixed" already).

### 8. SPOOGE — lay all bombs at once
- **Icon**: `power spooge`
- **Description**: MANUAL.BM: "Lays down ALL of your bombs at once."
- **Known bugs**: none found — but see "still to verify" below; absence of
  a bug report is not the same as having been tested.
- **Still to verify — HIGH PRIORITY**: this powerup has NEVER been
  live-playtested this session, by anyone. Sim-layer only: `spooge()`
  places `bombs_available` bombs in a line ahead of the player, stopping at
  the first obstacle, confirmed via direct function call in
  `tests/test_powerups.gd::_test_every_powerup_effect`. Nobody has pressed
  the actual button in the actual game and watched it happen. Also confirm
  the GRAB/SPOOGE exclusivity still holds after GRAB's mechanic changed
  twice above (`_test_grab_spooge_exclusion` covers this in isolation, but
  GRAB's carrying state and SPOOGE's exclusivity are separate systems that
  happen to share a powerup slot — a live check that taking one still
  visibly drops the other is worth doing).

### 9. GOLDFLAME — golden boy (max flame length)
- **Icon**: `power goldflame`
- **Description**: MANUAL.BM: "Golden Boy. Max Flamelength. Gives your
  explosions MAXIMUM range."
- **Known bugs**: none found.
- **Still to verify**: nothing outstanding. Sets `flame_len` straight to
  `cap_of(FLAME)` rather than +1, tested.

### 10. TRIGGER — controlled detonation
- **Icon**: `power trigger`
- **Description**: MANUAL.BM: "Allows you to precisely control when your
  bomb detonates." Exclusivity table: "Trigger will drop Jelly and Boxing
  Glove. Jelly will drop Trigger. Boxing Glove will drop Trigger."
- **Known bugs**:
  - Fixed: the exclusivity matrix was backwards against the manual's own
    table — Trigger was dropping Spooge instead of Jelly, and Jelly/Grab/
    Spooge's cross-drops didn't match the table at all (commit `210aa39`).
    Now correct, with dedicated tests (`_test_trigger_exclusion`,
    `_test_grab_spooge_exclusion`).
- **Still to verify**: the actual button flow, live — pick up Trigger, drop
  a bomb, walk away, press the action button (default Enter). The bomb
  should detonate on command, not on its own timer. Sim-layer confirmed
  correct (`trigger_bombs()`), not separately live-confirmed.

### 11. JELLY — bouncy bombs
- **ROOT CAUSE FOUND**: the earlier investigation that concluded "no bug, the
  bomb was simply exploding on time" missed the real one — the bomb drifts off
  the grid on every turn (item 4 at the top of this doc). Measured 400 cp off
  centre, which is why its bounces and its border behaviour read as random.
- **Icon**: `power jelly`
- **Description**: MANUAL.BM: "Turns your bombs into Jelly (bouncy)."
- **Known bugs**:
  - Fixed: a jelly bomb's wall-bounce didn't snap its position to the cell
    centre before reversing direction, so it visibly sat into the wall for
    a tick — reported live as "goes off the walls then bounces back"
    (fixed before commit `5070741`).
  - Fixed: jelly bombs lost their distinctive wobble look during a
    punched/thrown flight, falling back to the generic tumble sprite every
    other bomb type uses (`game_view.gd:622`, same commit range).
- **Still to verify**: JELLY↔TRIGGER exclusivity specifically (see #10) —
  covered by an automated test but not separately live-confirmed. Otherwise
  this session did a deep investigation of a reported "odd bounce/freeze at
  the border" and found NO bug: a jelly bomb kicked toward the map edge
  correctly bounces, does its random "crazy turn" at cell centres (1-in-3,
  resource-driven), and eventually detonates on its normal fuze schedule —
  what looked like a freeze in one debug session was the bomb simply
  exploding on time, not getting stuck. If a live report of jelly acting
  strangely comes in again, check `b.detonated`/`b.fuze` before assuming
  the movement code is broken.

### 12. SUPER_BAD_DISEASE — skull (up to three diseases)
- **Icon**: `power disease3` (also a skull — visually similar to plain
  DISEASE's icon, worth confirming they're actually distinguishable on
  screen; this session did not check that)
- **Description**: MANUAL.BM: "Gives you up to three (3) diseases
  simultaneously."
- **Known bugs**:
  - Fixed: was applying exactly one disease, not up to three (commit
    `210aa39`). Fixed with a seeded Fisher-Yates over up to 3 distinct
    diseases from `SUPER_BAD_DISEASES`
    (`tests/test_powerups.gd::_test_diseases`).
- **Still to verify**: same visual-feedback caveat as plain DISEASE — the
  invented tint doesn't distinguish "one disease" from "three at once."
  Whether it should (e.g. pulse harder/faster with more active diseases) is
  a design judgment call, not a bug, but flag it if it comes up live. Also
  unverified: does the icon actually read as visually distinct from plain
  DISEASE's skull in the pack's real art, or do they look identical on
  screen despite different sequence names?

### 13. RANDOM — resolves to another powerup
- **Icon**: `power random`
- **Description**: not separately quoted from MANUAL.BM this session —
  inferred from `give_powerup()`'s own comment and behavior: resolves to
  any other powerup, never itself.
- **Known bugs**: none found.
- **Still to verify**: nothing outstanding at the sim layer
  (`tests/test_powerups.gd::_test_random` asserts variety across seeds and
  that it never re-picks RANDOM). Not separately live-playtested, but low
  risk given the mechanic's simplicity — lowest priority of the 13.

## Also flagged, not a powerup bug but adjacent

- **AI kicking a bomb before fleeing danger** (`scripts/sim/ai.gd`): the
  bot's decision order runs "kick an adjacent bomb, 1-in-4 chance" (entry 1)
  BEFORE "standing in danger: flee" (entry 2) — so a bot standing in its own
  blast radius can still roll a kick instead of escaping. This matches the
  original's own disassembled AI order (comments in `ai.gd` cite
  `0x40BE02`), so it may be an intentional recreation rather than a bug —
  flagged for a decision, not fixed.
- **Options not saved across matches** and **level preview showing only
  background** were both fixed this session (`210aa39`, `5070741`) — not
  powerup issues but worth knowing they're resolved so they aren't
  re-reported as new.
