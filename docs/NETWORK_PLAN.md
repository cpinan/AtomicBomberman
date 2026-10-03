# Plan: make network play usable, then audit it

Six pieces of work, from a session that fixed three real netplay faults and
strongly suggested more are there. Read `docs/STATUS.md` first for where the
code stands; `docs/MULTIPLAYER.md` is the current user-facing guide.

**The theme:** the netcode is sound — server-authoritative, no prediction,
state hashes proven equal across three clients — but everything *around* it
assumes a developer with a terminal. A player who opens the game cannot start
or join a network match without command-line flags, and when something goes
wrong it fails silently.

---

## What already exists (do not rebuild)

- **Menu items.** `scripts/app/screens.gd:54` — `START_NETWORK` and
  `JOIN_NETWORK` are in `Menu`, labelled "Start Network Game" and "Join
  Network Game". `START_NETWORK` already routes to `Action.HOST` + the setup
  screen (`screens.gd:230`).
- **A LAN game list.** `screens.net_games` / `net_cursor`
  (`screens.gd:113-114`), drawn by `screen_view.gd:_draw_net_games()`
  (line 162) under the Join item — three entries, no scrolling. Fed by
  `scripts/net/discovery.gd`.
- **Room codes.** `directory/` is a lookup service and `scripts/net/directory.gd`
  its client, so a game can be joined by short code instead of an IP. Wired
  into the menu in `412370c`. `screens.join_url` and `screens.room_code`.
- **A dedicated server.** `--dedicated PORT`, plus `server/` with Docker and
  nginx config.
- **The refusal text** at `screens.gd:240` — "no server to join: start with
  --join ws://host:port" — which is honest and completely unusable for a
  player who has never seen a command line.

---

## 1. "Start Network Game" must explain itself

> **Done 2026-10-02 (`5170977`)**: the host's lobby shows the LAN address,
> how others join, and the port to forward. Not done: the room code needs a
> directory service, which still only `--directory` provides.

Today it opens the setup screen and silently begins hosting. Nothing tells
the player what just happened, what address others need, or that their
firewall matters.

Add a hosting screen shown after `Action.HOST` succeeds, before or alongside
the lobby:

- **The room code**, large, if `directory` registered one — that is the thing
  to read out over voice chat. `lobby_room_code` already reaches the view.
- **The LAN address** (`ws://<local-ip>:<port>`) for people on the same
  network. The local IP is not currently discovered anywhere; `IP.get_local_addresses()`.
- **A one-line "what to do"**: others pick Join Network Game and either see
  this game in the list, or type the room code.
- **The port**, and a plain note that hosting over the internet needs that
  port forwarded — which is the single most common reason a remote join fails.

Acceptance: a player who has never used a terminal can host a game and tell a
friend how to reach it, using only what is on screen.

## 2. "Join Network Game" needs a real browser screen

> **Mostly done 2026-10-02 (`5170977`)**: the field takes the host's
> address, the empty state says what to do, and every failure reaches the
> screen with its reason. Not done: a scrollable list of more than three
> games, and player counts in the LAN announce.

Today the list is three lines squeezed under a menu item, and an empty list
gives a command-line instruction.

Build it as its own screen (or a popup over the menu):

- **Games found on the LAN**, scrollable, each showing host name, player
  count, and the scheme — `discovery.gd` already carries enough for name and
  URL; extend the announce if count/scheme are wanted.
- **An explicit empty state**: "No games found on this network" plus what to
  do about it — enter a room code, or ask the host for their address. Not a
  flag.
- **Room-code entry** that a player can actually complete with the keyboard
  or a pad. `screens.gd:116` notes a code is being typed on JOIN_NETWORK;
  finish that path and give it a visible field.
- **A failure that says which failure it was.** `client.reject_reason`
  already distinguishes a full server from a version mismatch
  (`Protocol_.REJECT_*`); surface it rather than dropping back to the menu.

Acceptance: from a cold start with a friend hosting, a player joins using only
the menu — no flags, no URL typed by hand.

## 3. Audit the network logic

> **Progress 2026-10-02**: snapshot completeness is now a test and found two
> more missing fields (`d8e88fb`); match end and reconnection fixed
> (`c6480e8`, `ef3c656`); duplicate names no longer block a join
> (`5170977`). Still open: sounds when a client is behind, and a host
> whose window stops polling.

Three real faults turned up in one session of live testing, all invisible to a
suite of 135 passing checks, and all in the seam between the netcode and the
client that drives it. Assume more.

Already fixed, as evidence of the shape to look for:

- **Actions dropped between ticks** (`3ad767e`). The client sends input once
  per rendered frame, the server ticks at 20 Hz, and every packet was applied
  straight to the sim — so the `NONE`s after a press overwrote it. Every
  edge-triggered action over the wire was lost about five times in six.
- **The lobby reaped waiting players** (`e47642b`). The silent-peer timer ran
  in a room with no round, where clients legitimately say nothing, so everyone
  was dropped after 30 s while still connected.
- **Animation timers never crossed the wire** (`e47642b`). A client draws only
  what the snapshot carries; `death_anim`, `kick_ticks`, `punch_ticks`,
  `cornerhead` were missing, so nobody animated dying, kicking or punching.

Where to look next, in rough order of likely yield:

- **What else does the view read that the snapshot does not carry?** Diff the
  fields `game_view.gd` touches on `Player_` and `Bomb_` against
  `snapshot.gd`'s readers. The animation bug was one instance of a whole
  class; walk the class rather than the instance.
- **Round and match transitions over the wire** — round end, the intermission,
  the next round's seed, the win screen. A client that missed a transition
  message has no way to recover.
- **Reconnection.** There is none. A dropped player's seat empties (or becomes
  an AI with `lost_net_to_ai`); they cannot rejoin the match they were in.
- **Sounds.** `S_SOUNDS` is broadcast per tick; check nothing is lost or
  doubled when a client is behind.
- **The clock.** `poll(delta_ms)` accumulates real time; a host whose window
  is dragged or backgrounded stops polling. What happens to everyone else?

Method that worked: play it live with `AB_DEBUG_INPUT=1`, read the server log,
and only then write the test. Every one of the three was found from a log and
none from reading code.

## 4. Document creating and joining (items 4 and 5 are the same job)

> **Done 2026-10-02 (`11dcc17`)**: `docs/MULTIPLAYER.md` section 0.

`docs/MULTIPLAYER.md` covers the terminal already. What is missing is the
player-facing half, which should live in-game and in a short page:

- Hosting on a LAN, hosting over the internet (port forwarding, or the room
  code service), and joining by list, by code, and by URL.
- What each failure means: version mismatch, server full, no route.
- The `--` separator trap, once, prominently — flags before it are eaten by
  Godot and the game silently ignores them.

Fold the in-game text from items 1 and 2 and this page into one source of
wording so they cannot drift.

## 5. Compare gameplay against the original

Broad, and the most valuable thing after the network work. The oracles, in
order of authority: **BM95.EXE** (`tools/bmexe.py` disassembles it; the same
binary is in every copy of the disc), **VALUELST.RES / SOUNDLST.RES** (their
own comments state intent), **the printed manual** as a PDF in a CD rip, and
**MANUAL.BM**. Secondary wikis disagree with the disc and lose.

- **The win-round screen and the scoreboard** — not yet compared at all.
  What does the original show between rounds, and at match end? MESSAGES.TXT
  has the strings; `scripts/core/match.gd` and the roulette (`c54e8de`,
  `45061cb`) are the code.
- **Options and configuration** — every switch on OPTIONS.BM against what the
  port implements, and whether each is honoured in network play (the port
  already forces Gold Bomberman off over a network, per OPTIONS.BM).
- **Powerups** — the thirteen are audited (`docs/POWERUP_REVIEW_PLAN.md`) and
  six behaviours now come from the disassembly, but only single-player has
  been live-validated. Re-check them over the network now that actions and
  animations reach clients.
- **The flame alignment bug**, still open: the top-centre arm sits a few
  pixels right. Diagnosed in `docs/POWERUP_TEST_RANGE_PLAN.md`, item 2 of
  "Still-open bugs" — **check `tools/pack_assets.py` before touching renderer
  maths**, because that decides whether the fix belongs in the renderer or in
  the extractor.

---

## Suggested order

Item 3 first for anything that blocks play, then 1 and 2 together (they share
the wording and the screens), then 4 to write down what they do, then 5.

Keep `tools/verify.sh` green throughout, and **close every game window before
running it** — a live window holds the LAN discovery port and `test_discovery.gd`
then fails in a way that looks exactly like a real regression.
