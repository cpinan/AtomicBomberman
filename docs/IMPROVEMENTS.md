# Bugs to fix, and what I would change

Two halves. **Part A** is defects with evidence — do these first. **Part B**
and **C** are recommendations: my opinions, argued, for you to accept or
reject. Network-specific work is in `docs/NETWORK_PLAN.md`; the powerup
history is in `docs/POWERUP_REVIEW_PLAN.md`.

---

## Part A — confirmed defects

### A1. The match never ends. BLOCKING.

Captured live, from the host's own log:

```
server: round over: outcome 1 winner 0 — player 0 wins the match
server: match over: player 0 wins the match
server: player2 left (slot 1)          <- the player closed the window
```

After `match over` the server prints nothing further: it does not reopen the
lobby, return anyone to the menu, or stop. Both windows sit on the final
frame until someone kills them. Reported as "it gets stuck at the end of the
match".

Start at `scripts/core/match.gd` and `server.gd`'s `_intermission` /
`_tick_round`, and decide what the end of a match *is* — the original shows a
winner and returns to the menu. Then decide the network case: most likely the
room should fall back to `State.WAITING` with the roster intact so the host
can start another match, which is also what makes "play again" possible
without everyone relaunching. Note `_ensure_host()` already keeps a host
assigned across that transition.

Check the local path too — it may hang for the same reason or a different one.

### A2. Validate all thirteen powerups, over the network

Single-player is live-confirmed for the gloves and kick only. Everything from
`7e574d2` onward has never been seen by a human, and until `60d6b0a` no
networked player animated at all, so nothing was really testable online.

Use the T editor (`X` strip, `G` give, `N` cycle) and work through the list
in `docs/POWERUP_REVIEW_PLAN.md`, in both windows of a network game.

### A2b. When the server dies, the client kills the whole game

`main.gd:1187`:

```gdscript
if client.state == Client_.State.CLOSED:
    print("main: the server closed the connection")
    _quit(0)
```

The host quits, or their network drops, and every other player's application
**exits**, with the reason printed to a console no player is looking at. It
should return to the menu and say "the host ended the game" (or "connection
lost") on screen. `_open_menu()` already exists and the lobby notice added in
`60d6b0a` is the same shape of one-line message.

Same question for the host side: if the server stops, its own client should
land somewhere sensible rather than taking the process down.

### A2c. Pause in a network game

Two separate things, and only one of them is wired:

- **The sync pause works and is server-driven.** `server.gd:273` pauses
  everyone when a client falls more than `SYNC_TOLERANCE_TICKS` behind, and
  broadcasts `S_PAUSE`; `client.gd:180` applies it. That is the right design
  and should stay.
- **A player-initiated pause does not exist over the network**, and the test
  editor's `P` (added this session) gates the LOCAL `_step()` loop only. In
  HOST mode the server keeps ticking regardless, so at best it does nothing
  and at worst it freezes the host's own view while the match continues.

Decide one of: no manual pause at all in a network game (simplest, and what
most competitive games do), or a real one that goes through the server as a
broadcast like the sync pause already does. Either way the editor's `P`
should be refused, with a message, when `mode` is HOST or JOIN — silently
doing nothing is exactly the failure B1 is about.

### A3. The level selection screen

Asked for as an improvement rather than a bug. Worth establishing first what
the original does — MESSAGES.TXT has the strings and `screen_view.gd` draws
the current one — then deciding. A preview existed and was fixed in
`210aa39`, so the groundwork is there.

### A4. The flame's top-centre arm is a few pixels right

Open since this morning, diagnosed, unfixed. `docs/POWERUP_TEST_RANGE_PLAN.md`
"Still-open bugs" item 2 has the measurements. **Check
`tools/pack_assets.py` before touching renderer maths** — it decides whether
the fix is in the renderer or in the extractor.

---

## Part B — game, UX and usability

### B1. Every refusal should say why. This is the big one.

Three separate bugs this session were the same mistake: the code correctly
declined to do something and said nothing, so it read as broken.

- Pressing Enter in the lobby as a non-host — correct (only the host may
  start), silent, and it cost a whole session of debugging.
- Pressing the action button with the Boxing Glove and no bomb in front —
  correct, silent, reported as "the red glove doesn't work".
- A punch into a wall was *refused outright* by an earlier fix, to stop a
  zero-distance flight looking broken. Both the silence and the refusal were
  wrong; the bomb should fly over the wall.

Make it a rule: if the player pressed a button and the game decided not to
act, the game says so. A line of text, a sound, or an animation — the glove
now swings at air, which is exactly the right shape.

### B2. Show the player what they are carrying

The T editor prints `can_kick`, `can_punch`, `can_grab`, facing, bombs and
flame length — and that readout is the only reason the glove bugs were
finally diagnosable. Players get none of it. Whether the original shows it is
worth checking, but a subtle HUD strip of held powerups would remove a whole
class of "is it broken or do I not have it".

### B3. Network play cannot be started from the menu

Covered in `docs/NETWORK_PLAN.md` items 1 and 2. Today hosting and joining
need command-line flags, and the empty-list message literally tells a player
to pass `--join ws://host:port`.

### B4. The `--` trap will catch every user

`godot --path . --serve 47600` is silently ignored; the flags must come after
a bare `--`. Both READMEs documented the broken form until today. Anyone
following an old copy, a blog post, or their own memory gets a plain local
game and no error. Consider parsing `OS.get_cmdline_args()` as a fallback and
warning loudly when a known flag is seen before the separator.

### B5. Losing a connection ends your match

There is no reconnection. A dropped player's seat empties or becomes an AI;
they cannot rejoin. For a game people play together over an evening this is
the difference between a hiccup and a ruined match.

---

## Part C — the code

### C1. The recurring failure mode is the seam, not the parts

Every hard bug this session lived between two correct layers, and the tests
covered both sides of the gap and not the gap:

- The gloves: the ability functions were right, the tests were right, and the
  bug was in movement and rendering. Three sessions were spent re-reading
  `punch_bomb()`.
- Netplay actions: the sim was right, the netcode was right; the client sends
  per frame and the server ticks per tick, and every test drove them in
  lockstep so nothing noticed.
- Animations over the wire: the sim set the counters, the view read them, and
  nothing carried them between.

**Recommendation: write tests at the seams, in the cadence the real thing
uses.** The netplay harness pumps one input per tick; the real client sends
six. Add a harness that drives input at frame rate against a 20 Hz server,
and one that drives keyboard events through `Keysets` rather than calling
`set_input()`. Both bugs would have been caught the day they were written.

### C2. Make snapshot completeness mechanical

The animation bug was "a field the view reads is not serialised". That is
checkable: enumerate the `Player_`/`Bomb_` fields `game_view.gd` touches and
assert each appears in `snapshot.gd`. One test would close a whole class
instead of the one instance found by hand.

### C3. Fold the debug scaffolding into one real tool

There are now two env-gated tracers (`AB_DEBUG_ACTIONS`, `AB_DEBUG_INPUT`)
plus the T editor's readout, all added under pressure and all recorded for
deletion. They were decisive — every live bug this session was solved from a
log — so do not simply delete them. Finish step 3 of
`docs/POWERUP_TEST_RANGE_PLAN.md`: one on-screen panel with the action history
and the network state, and remove both tracers.

### C4. `_landing_cell()` precomputes what the original resolves per hop

The last structural difference from BM95.EXE. All the observable rules now
match, so this is cosmetic — but it is why the bomb overlap, the arena edge
and the "nowhere to go" refusal each needed their own patch where the
original needs none. Three patches for one model. Worth doing only if a
future bug traces back to it.

### C5. `tools/verify.sh` should refuse to run with a game open

A live window holds the LAN discovery port and `test_discovery.gd` then fails
with `cannot listen on 47601`, which looks exactly like a real regression. It
cost time twice today. Detect a running instance and say so, rather than
producing a failure that has to be recognised.

### C6. Keep using the disassembly

`tools/bmexe.py` settled six behaviours today that had been guessed at for
sessions, and the printed manual in the CD rip settled a seventh and caught
an error I had just made. When a question is "what does the original do", it
is usually answerable in minutes. The order of authority: BM95.EXE, then
VALUELST/SOUNDLST's own comments, then the printed manual, then MANUAL.BM.
Wikis disagree with the disc and lose.
