# AUDIT — what is ported, what is not, and how each answer was reached

_Written 2026-09-02, at the user's request to "challenge the port and ensure all
screens and gameplay is properly ported". Every row is a claim with evidence
beside it. Where the answer is "no", it says no._

The three sources, in the order that settles a disagreement:

1. **`BM95.EXE`** — the code. `tools/bmexe.py` maps it; every tuning value goes
   through one function, so `docs/ORACLE.md`'s resource numbers are a
   cross-reference into it.
2. **The data files** — `VALUELST.RES`, `MESSAGES.TXT`, `SOUNDLST.RES`, the
   `EXTRA*.RES` files, the 67 schemes, `COLOR.PAL`, the `.RMP` files, `*.BM`.
3. **fpc_atomic and AtomBomberman's notes** — secondary, and wrong often
   enough to be worth checking: `docs/ORACLE.md` lists 67 rows where the disc
   disagrees with them.

---

## 1. Screens

The original ships every screen as a 640x480 PCX in `RES/`. There are 25 of
them plus 9 smaller elements, and **all 34 are now in the asset pack**.

| screen | art | in the port | notes |
|---|---|---|---|
| Title | `TITLE.PCX` | **yes** | "Press any key" in the game's own font, blinking |
| Main menu | `MAINMENU.PCX` | **yes** | its seven items are painted INTO the art; the port measures their positions and draws `MISC.ANI`'s four-frame pointer beside them |
| Player setup | `GLUE0` wallpaper | **yes**, layout is the port's | ten slots, each OFF / AI / KEY n, from `MESSAGES.TXT` 220-224 |
| Options | `GLUE3` wallpaper | **yes**, layout is the port's | the settings screen's own labels, `MESSAGES.TXT` 250-268 |
| About Bomberman | `GLUE6` + `CREDITS.BM` | **yes** | the real credits, read from the disc |
| Online Manual | `GLUE3` + `MANUAL.BM` | **yes** | the real manual text |
| Results | `RESULTS.PCX` | **yes** | the art and the match score. `MESSAGES.TXT` 900-928 was read here as a missing part of this screen and is not one: 900 says "Statistics **File**", and `BM95.EXE` writes it to disc at `0x40200C` without drawing it anywhere. It is a file, and the port now writes it — see §1.1 |
| Victory | `VICTORY0..9.PCX` | **yes** | one per player colour, and `TEAM0`/`TEAM1` for a team win |
| Draw | `DRAW.PCX` | **yes** | |
| Transition | `HEADWIPE.ANI` | **yes** | 211 frames of a 73x73 bomberman, run across the screen between screens |
| In-game status band | none on the disc | **yes**, layout is the port's | the clock in `KFONT.ANI`'s own digits and colon; a disc per player. The eleven level backgrounds leave this band plain and no art for it has been identified |
| HURRY banner | `HURRY.ANI` | **yes** | one 278x91 frame, flashing, centred in the playfield |
| Goldman roulette | `ROULETTE.PCX` | **yes, laid out from the data** | the only screen whose layout the port did not invent: VALUELST 1000, 1002, 1004, 1006 and 1010 give the wheel's centre, its two elliptical radii, its resolution, its Lissajous parameters and the winner's five-second twinkle, and 805 places the title |
| Bonus | `BONUS.PCX` | **not a gap — the shipped game does not draw it either** | see §1.2 |

### 1.1 The statistics file

Not a screen. `MESSAGES.TXT` 900 is a title, 905 two column headings and
910-928 nineteen counter names; `BM95.EXE` writes them at `0x40200C` into
`bmstats.dat` (binary, **100 dwords of totals** — its accumulate loop runs
0..99 while its print loop runs 0..18) and `bmstats.txt` (readable,
`"%-30s %13u %13u"` a row, Total then Last Run, the label's colon appended
before the padding). The port writes both, to `user://`, from
`scripts/core/stats.gd`, byte-compatible with the original's.

**Fourteen of the nineteen are collected. Five cannot be**, and are written as
zero rather than dropped so the file keeps the original's shape:

| counter | why not |
|---|---|
| 913 Graphic Requests Serviced | counts DirectDraw blit requests; this port draws through Godot's canvas, where the per-frame draw count belongs to the renderer, not the game |
| 925 Attract Modes Started | there is no attract mode |
| 926 Network Packet Retransmits | WebSocket over TCP retransmits below the application |
| 927 Ghost Bomb Actions Found | server-authoritative netcode has no ghost bombs to reconcile |
| 928 Ghost Bomb Actions Lost | the same |

Two honest limits in what IS collected. **A joined client counts only its own
network traffic**, because it never ticks a simulation — it applies snapshots,
so no bomb is placed and no brick is destroyed on that machine to count.
**A broadcast counts as one packet out**, however many peers it reaches: the
server hands its multiplayer peer a single broadcast and never sees the
fan-out.
| Network game list | none | **NO** | `MESSAGES.TXT` 60-66 and 620-634 describe a server browser and a protocol chooser. The port's netcode takes a URL instead |
| Keyboard definitions | none | **yes, superseded below** | `MESSAGES.TXT` 1100-1130 names the screen and all six actions — see "Key rebinding" further down, the entry this row duplicated before it was implemented |
| Modem / serial setup | none | **not applicable** | `MESSAGES.TXT` 640-648. The transport is WebSocket |
| Level editor | `EDIT.ANI`, `MESSAGES.TXT` 700-753 | **NO** | a separate program on the disc (`TOOLS/FREDIT.EXE`) |

**Not a screen after all:** `GLUE0`-`GLUE6` are tiling wallpapers, not seven
screens. That was the first assumption and it was wrong; GLUE4 is a wall of
BombFlakes cereal boxes.

---

### 1.2 The bonus screen, which is cut art

`BONUS.PCX` is a 640x480 title card reading **"BONUS GAME"**, and it was on
this port's missing list. It should not have been.

1. **`ROULETTE.BM`, the disc's own help text, says what the Bonus Game is:**
   "you will have an opportunity to play the Bonus Game (the Gold Bomberman
   Roulette Wheel)". The bonus game is the roulette, which the port has —
   drawn from `ROULETTE.PCX`, laid out from VALUELST 1000-1010.
2. **`BM95.EXE` cannot load `BONUS.PCX`.** Screens are loaded by name through
   `"%s/%s/%s.pcx"` (0x458ED9), and every screen the game shows is a string in
   the binary: `title`, `draw`, `results.plt`, `victory%u`, `team%u`,
   `mainmenu.plt`, `glue%u.plt`, `field%u.plt`, `hurry`, `iplogo`, `hslogo`,
   `credits.bm`, `@roulette.plt`. **There is no `bonus` string anywhere in the
   executable** — a case-insensitive scan of every section finds none.
3. The only other mention of it on the disc is `INSTALL.DAT`, which lists it
   as a file to copy.

So it is a card for a screen the shipped game never shows, and the thing it
announces is a screen the port already draws. **Nothing is missing, and the
port does not invent a screen the original does not display.**

## 2. Gameplay

| system | in the port | evidence |
|---|---|---|
| 20 Hz fixed tick | **yes** | resources 30 and 25. `docs/ORACLE.md` §1 |
| Centipixel movement | **yes**, rule reconstructed | resource 42; the re-centring rule is `docs/BUGS.md` Q5.1, located at `0x41F29B` and NOT read |
| Field geometry | **yes, exact** | `BM95.EXE` 0x42647A, which names `map.c` line 317. The port had the Y offset 2 px wrong until it was read |
| Bombs, fuzes, chains | **yes** | resource 41; chain owner attribution |
| Flame arms and stops | **yes**, order reconstructed | resource 10; propagation ORDER is Q5.3, at `0x426D06`, NOT read |
| 13 placeable powerups | **yes** | scheme `-P` lines, caps from 550-564 |
| The 14th powerup, Clog | **yes** | `MESSAGES.TXT` 813/863 name it and resource 91 costs 150 hundredths of a pixel; the wheel can award it as a punishment |
| Powerup scatter | **reconstructed** | counts from 400-412; the algorithm is Q5.2 and has no constant call site to find it by |
| 12 diseases | **yes**, 5 change play | named from SOUNDLST's own comments |
| Kick, punch, grab, throw, spooge, jelly, trigger | **yes** | resources 300, 301, 660, 661, 667 |
| Map specials: arrows, warps, conveyors, trampolines, regrowth, ice | **yes, exact coordinates** | the `EXTRA*.RES` files |
| Hurry, closing wall | **yes** | resource 101; depth 1 of 4, named "A Little" by `MESSAGES.TXT` 316 |
| Round end: last standing, draw, time up | **yes** | |
| Match to N wins | **yes** | resource 310 |
| Random level each round | **yes** | `MESSAGES.TXT` 149 |
| Team play | **yes** | slots 1-5 against 6-10, `OPTIONS.BM`. The port had odd/even until that file arrived — `docs/BUGS.md` D20 |
| Bots | **yes**, logic reconstructed | four knobs; the AI is Q5.4, fully mapped and all 8 handlers now read line by line: entry `0x40A1C6` dispatches an 8-entry priority table at `0x45BA78` of local reactions (own-bomb trigger, kick, route, maybe blast a brick, bomb a reachable enemy, take a powerup, flee, wander). One of them — the routing entry `0x40B20F` — runs a real **breadth-first search over an influence map** (`0x40970B`/`0x4092A1`, depth 20, 100-walker frontier), which an earlier pass wrongly reported as absent. `docs/BUGS.md` Q5 |
| Sound | **yes, the binary's rules** | least-used-with-random-tie, no per-tick collapsing, a full mixer refuses. `docs/BUGS.md` Q8 |
| Music | **yes, from the player's own disc** | `SOUNDLST` 1100-1110 names one track per level and the eleven are **120 MB** of raw PCM against resource 6's 7 MB budget, so the pack carries the NAMES and the audio is read from the game data at the moment it is needed. A desktop run has music; a browser build has none and cannot. `MESSAGES.TXT` 263 turns it off |
| Per-player recolour | **yes, the disc's tables** | `COLOR.PAL` and `0.RMP`-`9.RMP`, applied as a ratio so the 15-bit art keeps its depth |
| Networked play | **yes** | server-authoritative, hash-checked every snapshot |
| Win by kill total | **yes** | `MESSAGES.TXT` 255, and the target is the same number as for wins — the disc has one number and two sentences for it, 120 "(Match winner must score %u victories)" and 121 "(Match winner must score %u kills)", and two words for the column, 208 "Wins" and 209 "Kills". `OPTIONS.BM`: a suicide costs a kill. Every round's kills count, including a draw or a time-up — the option says the KILL count decides, not the rounds |
| Gold Bomberman | **yes** | the winner of a match spins for a powerup, granted at the start of the next one, per `OPTIONS.BM`. Off over a network, which `OPTIONS.BM` also says |
| Random start positions | **yes** | `MESSAGES.TXT` 251, and **VALUELST 40, not 36** — "default value of \"do we randomize player starting positions?\"", which is **1**, so the disc has this ON and so does the port. Permuted once per MATCH (`OPTIONS.BM`: "randomized at the beginning of the match"), positions only: a slot keeps its own team, so a team scheme stays two teams. `--random-start 0` turns it off, which `OPTIONS.BM` advises for a team scheme |
| Campaign mode | **yes** | Three `.CAM` files — SIMPLE (4 stages), GHOSTS (4), CROUTON (9) — each stage naming a level, a scheme, and how many rovers and ghosts at what speed. Scoring is **VALUELST** 1300/1310/1320 (250 an AI, 15 a rover, 25 a ghost); 1200/1205 govern how a creature turns; the art is `ALIENS1.ANI`'s eight sequences, which is what `BM95.EXE` builds from `"rover %s"` and `"ghost %s"`. What the disc does NOT say is what the two creatures do — a ghost passing through walls, contact killing, flame killing them — and `scripts/sim/creature.gd` lists each of those as this port's decision. `MESSAGES.TXT` 1300-1320 is NOT this: it is the memory-model dialog |
| Network game list | **yes, over a beacon this port invented** | The SCREEN is the disc's — `MESSAGES.TXT` 60 "Available net games:", 61 "No net games found!", 62 "'%s' (%u) (id:%u)", 65 — but the disc's discovery was IPX/modem/serial/TCP in 1997 and this port speaks WebSocket, which nothing can enumerate. A server shouts one UDP line a second on 47601 and the join screen lists what it hears. 620-634's protocol chooser stays out: there is one protocol |
| Statistics collection | **yes**, 14 of 19 | `MESSAGES.TXT` 900-928, written as the original's own two files. §1.1 has the five that cannot be collected |
| Key rebinding | **yes** | `MESSAGES.TXT` 1100-1140, the whole screen: 1100 titles it, 1110 is a row, 1120-1125 name the six actions, 1130/1131 restore the defaults. Reached from the options list's own 265 "Define keyboard layouts". A key already in use is refused — the disc does not say what the original does, and the alternatives are an action with no key or one press driving two players. Saved to `user://keys.cfg` |
| Gamepad | **yes** | `MESSAGES.TXT` 223's `JOY %u` slot type, offered only when a pad is plugged in. The stick resolves a diagonal the way the keyboard does — one axis at a time, most recent wins — because the simulation only moves on one. Which button bombs is the port's choice: the disc's joystick handling was DINPUT and a Windows dialog |
| Default key layouts | **yes, the disc's own** | `INPUT.BM` states them as a table — "KEY 0: Cursor Keys / Space / Enter", "KEY 1: R,D,F,G / S / A" — and `MANUAL.BM` names the same keys from the player's side. The port had invented both until that file was read: Space, which the manual names first for Drop Bomb, was bound to nothing. `docs/BUGS.md` D28 |
| The other in-game keys | **4 of 7** | `MANUAL.BM` lists them: **Ctrl-A** (all players to AI on the setup screen), **F10** (force a draw), **Ctrl-Q** (quit to the main menu) and `INPUT.BM`'s **T** (toggle a player's team) all work. **F1** (help), **Alt-N** (NETSTATS.TXT) and **Alt-D** (misc info) do not |
| Losing powers to a bomb on the head | **yes** | `VALUELST` 670 "what's the minimum number of powers you lose when hit on the head?" = 1 and 671 "the additional random number" = 3, with SOUNDLST 360-399's forty recordings of "you are stunned by a bomb landing on you". A punched bomb landing on somebody did nothing at all until D28 |
| Hold-to-carry a grabbed bomb | **NO** | `MANUAL.BM`: "you may carry a bomb by grabbing and **holding down** the Drop Bomb button". The port grabs on a second press and drops on a third; the button is an edge here, not a state |
| The four looks of a bomb | **yes** | `BOMBS.ANI` has `bomb regular green` and `bomb jelly green`, `TRIGBOMB.ANI` has `bomb trigger green`, `DUDS.ANI` has `bomb regular green dud`. The port drew the first for all four until D28 |
| Punch, carry and pickup animations | **yes** | `PUNCH.ANI`, `PUNBOMB1..4`, `BOMBWALK.ANI`, `BPICKUP.ANI` — four files whose sequence names the port never built, so all three actions were drawn as a standing or walking bomberman |
| Cornerhead animations | **NO** | `CORNER0..7` hold `cornerhead 0` to `cornerhead 12` and `VALUELST` 308 counts them; `APPLBITE`, `NUCKBLOW` and `ZEN` are 121 frames each and unnamed. Decoration, and not packed |

---

## 3. What the port gets wrong, knowingly

Each of these is a reconstruction that the binary could settle and has not yet:

1. **The AI's search.** `ai.gd` uses breadth-first search with two distance
   fields over the whole map, and says so in its own header comment as a
   known, disclaimed invention. Read, in full, and **less of an invention than
   two passes at this binary suggested**: `0x40A1C6` dispatches every frame
   through an indirect call into an 8-entry, fixed-priority table at
   `0x45BA78` (own-bomb trigger, kick an adjacent bomb, route, maybe blast a
   brick, bomb a reachable enemy, take a nearby powerup, flee danger, wander —
   in that order). Seven of those entries look no further than their own tile,
   the 4 adjacent cells, or a radius-9 ray (`0x40B046`). The eighth, the
   routing entry `0x40B20F`, runs a genuine **breadth-first search**
   (`0x40970B` to pick a destination, `0x4092A1` to step toward one) — a
   frontier of up to 100 cloning walkers, depth limit 20, over an **influence
   map** (`0x424D37`, one int per cell, its own error string `"Influence
   size"`) rather than over walkability. So the mechanism the port guessed is
   the original's mechanism; what differs is that the original searches only
   from that one entry, only when it is standing in danger or already holds a
   destination, and searches a danger field rather than a distance field.
   The intermediate reading that said "no field-wide search at all" was wrong
   because the search lives at `0x409xxx`, outside the address range that had
   been scanned for it. The influence map itself is now read too: five writers
   stamp "how soon fire arrives" — a bomb's tile and its arms get its
   remaining fuze plus 100, a burning cell 1000, the closing wall a gradient
   of `value_of(910) * 10 + 100` decaying 10 a cell. **The port's own danger field is boolean where the original's is
   graded** — but read the gradient carefully before calling that an
   improvement: a bomb's cells carry `fuze remaining + 100`, and
   `ai_search_safest` takes the MINIMUM, so when nothing safe is in reach the
   original walks toward the fire that comes SOONEST, not the one that comes
   latest. "Be where the fire has already passed" rather than "buy time".
   Adopting it is therefore a behaviour change to measure, not an obvious
   fix. `docs/BUGS.md` Q5.
2. **Movement and tile re-centring.** No longer assumed — READ out of
   `0x41EC84` (`docs/BUGS.md` Q5.1) and deliberately NOT adopted yet, because
   movement is what every other system and the network hash sit on. Three
   differences are now known rather than suspected: the original's step is
   diagonal while off-centre (the port re-centres, then moves); its corner
   rounding requires the side cell AND the diagonal cell to be open (the port
   decides from its collision box); and walking into a wall dead-centre pushes
   the player back to the cell centre (the port stops flush).
3. ~~**Flame propagation order.**~~ **Read and adopted, 2026-09-03.** Arms are
   walked one at a time in the direction table's order — up, right, down,
   left — and a bomb ENDS the arm that lights it rather than being passed
   over, with that bomb told not to fire back the way the arm came.
   `docs/BUGS.md` Q5.3.
4. **The powerup scatter.** Counts are exact and so is the negative-count
   rule (1-in-10 each). Placement differs in one measurable way, now read:
   the original throws darts at the whole field and gives up after 200 misses,
   so a sparse map can end up with fewer powerups than the table asks for; the
   port draws from the list of brick cells without replacement and always
   places what it can. `docs/BUGS.md` Q5.2.
5. **Two mixer guesses that were WRONG and are now fixed** — recorded because
   they were confidently documented for a phase: the port collapsed a tick's
   duplicate sounds and evicted the oldest voice, and the original does
   neither. `docs/BUGS.md` Q8.

---

## 4. What the port does that the original does not

Stated so the difference is a decision rather than a drift:

- **Runs at any window size**, by scaling the 640x480 canvas in whole
  multiples. The original had one mode.
- **Keeps the art's 15-bit colour.** The original quantised to 256 colours for
  an 8-bit display; the recolour applies the disc's tables as a ratio instead,
  which is the same hue change without the quantisation.
- **WebSocket instead of IPX, modem, serial and TCP.** A browser cannot open a
  raw socket. `docs/ORACLE.md` notes the four per-protocol timeouts at
  1100-1104 are of historical interest only.
- **A round seed, and a written-down LCG between rounds**, so a whole match
  replays from one number.
- **Refuses a one-player round** from the setup screen, because such a round
  can only end on the clock.
- **A UDP beacon for the game list.** `MESSAGES.TXT` 60-66's screen needs
  something to enumerate and a WebSocket cannot be enumerated, so a server
  shouts one line a second on port 47601 and clients listen. The screen is the
  disc's; the beacon is not. `scripts/net/discovery.gd`.
- **Rovers and ghosts behave the way this port decided.** The `.CAM` files give
  counts and speeds, VALUELST 1200/1205 give two turning chances, and that is
  everything the disc says. A ghost passing through walls, both kinds killing
  on contact and both dying to flame are decisions, each listed in
  `scripts/sim/creature.gd` with the reason.
- **A graded danger field for the bots**, where the original's influence map is
  graded the other way — measured before adopting, 16 seeds of four bots: 8
  self-kills and 47 survivors graded against 9 and 46 boolean, all 16 rounds
  finishing either way.
- **Refuses to bind a key that is already in use**, and refuses a JOY slot with
  no pad behind it. The disc says nothing about either; the alternatives are an
  action with no key, one press driving two players, and a seat that cannot
  move.

---

## 4.1 Replacing the art

`docs/ART.md` is the guide and `tools/artpack.py` is the tool. A pack can be
taken apart into one PNG per frame with every hotspot beside it
(`--template`), checked against what the game requires (`--check`), and put
back together (`--build`); `--pack-overlay DIR` lays a partial replacement over
the pack that is already loaded, so a sheet can be repainted and played
without building anything. `verify.sh` runs the whole round trip, so the
promise cannot rot quietly.

This is what a legally shippable build needs, and it is now the only thing
between here and one: the sounds, the strings and the tuning tables are still
the disc's.

## 5. How to re-check any of this

```bash
godot-project/verify.sh          # 4802 checks, 28 suites
tools/bmexe.py --xref            # which code reads which tuning value
tools/bmexe.py --func 0x42647A   # the field geometry, from map.c
tools/messages.py --check        # the string table and its named blocks
tools/rss.py --check             # the sound events and their gaps
tools/fonts.py --check           # the .FON fonts
tools/remap.py --all-slots       # the two colour transforms, measured
tools/pack_assets.py --check     # what the pack would contain
```

Screens can be looked at one at a time:

```bash
Godot --path godot-project -- --menu --screen title
Godot --path godot-project -- --menu --screen setup
Godot --path godot-project -- --menu --screen victory
```
