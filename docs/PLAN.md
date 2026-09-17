# PLAN — Atomic Bomberman → Godot 4, web-playable, self-hosted server

_Written 2026-09-02. Godot 4.7.1, Python 3.11. Decisions recorded in §1 are the
user's; the analysis behind them is in §2._

_Revised 2026-09-02, same day: the CD's `DATA` tree arrived in
`original-game/`. It contains the original programmer's own tuning table, so
**every constant is now anchored to the original** and Track C narrows to
algorithms only. The full ledger is `docs/ORACLE.md`, which supersedes
fpc_atomic wherever the two disagree. `BM.EXE` itself is still absent._

---

## 1. Decisions

| Decision | Choice | Consequence |
|---|---|---|
| Source of truth | **The original's own data files, then BM.EXE** | `RES/VALUELST.RES` is Kurt Dekker's commented tuning table, loaded by the game at runtime — authoritative for constants without any disassembly. Track C reduces to the algorithms the data cannot express, and needs `BM.EXE`, which is not yet here. |
| Assets | **Python CD extractor + a free replacement pack** | Two swappable packs behind one manifest. The free pack is what makes a public web build legal. |
| Netcode | **Headless Godot server + WebSocket, 50 Hz full-state, no prediction** | Mirrors fpc_atomic exactly, so the oracle diff stays meaningful. ~1.6 Mbps/client; delta encoding is a later, measured optimization. |
| Bots | **Port the AI early** | Every milestone stays testable solo and headless. |

The one place the choice of oracle was argued: reverse-engineering BM.EXE is
weeks of work before the first tile renders, whereas fpc_atomic is a complete,
working, permissively-licensed reimplementation that could serve as the spec
directly. The decision stands, and this plan absorbs it by making fpc_atomic the
**bootstrap** and the original the **authority**: Track A gets playable from
fpc_atomic's source, and every correction lands in `docs/ORACLE.md`. No Godot
phase ever waits on a disassembly.

That argument got much cheaper the moment `original-game/` arrived.
`VALUELST.RES` alone settles 42 behaviours — including the frame rate, the
speed units, the powerup caps and the disease model — and it does so with the
original programmer's comments attached. **The expensive half of the oracle was
paid for by one folder.** What remains genuinely needs the binary: the movement
and re-centring routine, flame propagation order, the powerup scatter
algorithm, and the AI. Those are §5 C3–C6.

---

## 2. What the references actually give us

### fpc_atomic — the bootstrap

Uwe Schächterle's Free Pascal reimplementation. **Postcardware or modified
LGPL**, so translating it is permitted; its source headers say the attribution
text may not be removed, so ported files carry a provenance comment naming the
original unit.

Its sim is already cleanly separated from its renderer by `{$IFDEF Server}`, and
that server half *is* the game:

```
CreateNewFrame()              # server/uatomic_server.pas:1765, every FrameRate=10ms → 100 Hz
  HandleMovePlayer()          # units/uatomic_field.pas:788   movement, conveyors, kick
  HandleActionPlayer()        # units/uatomic_field.pas:1120  place / grab / throw / spooge / punch / trigger
  HandleBombs()               # units/uatomic_field.pas:1296  fuse, chains, flight, jelly bounce, arrows
  HandlePlayerVsMap()         # units/uatomic_field.pas:1741  powerups, flame deaths, holes, tramps
  HandleFieldAnims()          # units/uatomic_field.pas:1878  brick explode, flame decay, tramp wobble
UpdateAllClients()            # server/uatomic_server.pas:1930, every UpdateRate=20ms → 50 Hz
```

Free with it: every tuned constant in `units/uatomic_common.pas`
(`AtomicBombDetonateTime=2000`, `AtomicDefaultSpeed=0.5` tiles/s,
`AtomicSpeedChange=1.1`, `FlameTime=500`, `BrickExplodeTime=900`,
`AtomicDiseaseTime=10000`, `AtomicTrampFlyTime=1500`), the ten player colours,
the 160-entry `HurryCoords` spiral (`units/uatomic_field.pas:194`), the powerup
and disease enums, the eleven maps with their per-map specials, and a C-ABI AI
interface (`server/uai_types.pas`).

Its netcode is server-authoritative with **no prediction and no lockstep**.
Clients send `miClientKeyEvent` and nothing else. The server broadcasts
`miUpdateGameData` = round time + 10×`TAtomicInfo` + the whole 15×11
`TFieldBrick` array + the live bomb list. A 100 ms heartbeat, and any client
more than 800 ms behind hard-pauses everyone (`SynchonizeTimeOut`). 26 message
IDs total, all in `units/uatomic_messages.pas`.

Measured cost of that design: `TFieldBrick` is ~20 B, ×165 tiles ≈ 3.3 KB, plus
players and bombs ≈ **3.5 KB × 50/s ≈ 1.6 Mbps down per client**. Fine on a LAN
or a VPS with a handful of players. Wasteful over the internet, which is why
delta encoding is scheduled as Phase 10 rather than assumed away in Phase 5.

### AtomBomberman — behaviour notes, no code

GPL-2, so **no code may be copied**. Its `notes` file is nonetheless the single
densest description of original behaviour anywhere in the three repos, and
observations are not copyrightable. Load-bearing claims to verify in Track C:

- Bomb fuse is exactly 2 s = 40 animation frames ⇒ **20 FPS**. Contradicts
  fpc_atomic's 100 Hz sim; see §5, C3.
- Flames last 500 ms, drawn *under* bombers; only one flame per tile (the last).
- Bomb properties are fixed at drop time, not at explode time.
- Movement is one axis at a time with direction priority; the game re-centres
  the player through tiles to help them round corners.
- Flames pass through bombers but are stopped by blocks **and by powerups**.
- If bomb A ignites bomb B and B kills someone, A's owner gets the kill — but
  the flame colour stays B's. (fpc_atomic reached the same rule at 0.11006,
  independently. Good sign for both.)
- Trigger + oil and trigger + punch are mutually exclusive; picking up trigger
  drops both oil and punch.
- A punched bomb's timer resets; a carried bomb's timer stops entirely.
- Teleports pass flames, stop bombs, and make the player briefly immortal.
- `mflame.ani` is used, `flame.ani` is not. From `data/res` only `field?.pcx`;
  everything else comes from `data/graphics` in ANI form.

Its `default.sch` documents the original scheme text format: an 11×15 grid of
`#`/`:`/`.`, then a count and a list of specials (`A`rrow / `C`arry /
`T`rampoline / `W`arp with headings and coordinates), then start positions with
teams, then the 13-row powerup table (`bornwith`, `override_value`).

### Atomic-Bomberman — largely superseded

GPL-2, docs only. 144 files, a cell-object-per-tile design and a hand-rolled GUI
widget set. Its structure is worth one read for the cell polymorphism idea and
nothing else; fpc_atomic's flat `TFieldBrick` array is the better model for a
port that has to serialise the field 50 times a second.

### Asset formats on the CD

Counts are what `original-game/` actually holds, not what fpc_atomic's
extractor jobs cover — its 44 PCX and 102 RSS jobs are a *subset* it chose,
and the CD has considerably more.

| Format | Where | Count | Size | Contents |
|---|---|---|---|---|
| `.PCX` | `RES/` | **61** | 10 MB | Backgrounds, menus, powerup icons, victory plates |
| `.ANI` | `ANI/` | **95** | 7.7 MB | Interplay container: IFF-style chunks, per-frame RLE'd TGA-like blobs with hotspots and a palette-index colour key |
| `.RSS` | `SOUND/` | **2027** | 428 MB | Headerless raw PCM, 22050 Hz, s16, stereo, LE |
| `.SCH` | `SCHEMES/` | **67** | 268 KB | The real `-V/-N/-B/-R/-S/-P` format |
| `.RES` | `RES/` | 7 | — | `VALUELST`, `SOUNDLST`, `EXTRA{2,3,4,9,10}` |
| `.CAM` | `RES/` | 3 | — | Campaign definitions |
| `MASTER.ALI` | `ANI/` | 1 | — | Which ANIs the game actually loads |

The expansion `ani.zip` (xplode18 and friends) merges into `DATA/ANI` and is a
separate download; without it the extractor warns and some death animations are
missing.

fpc_atomic's extractor output shape is worth copying verbatim, because it is
already the right shape for Godot: spritesheet PNGs plus a `files.txt` manifest
whose columns are
`Filename; TimePerFrame; FramesPerRow; FramesPerCol; FrameW; FrameH; TotalFrames; RenderOffsetX; RenderOffsetY`
— e.g. `applbite.png;50;11;11;73;73;121;36;64`. Those manifests are **checked
into `fpc_atomic/data/atomic/*/files.txt` already**, which makes them free
ground truth for testing our own extractor before we ever see the CD.

### Licence summary

- fpc_atomic — postcardware / modified LGPL → **may port, must attribute**.
- AtomBomberman, Atomic-Bomberman — GPL-2 → **read, never copy**.
- Original art, audio, level design — Interplay Productions, © 1997 → **never
  redistribute**. `original-game/` and `data/packs/cd/` are gitignored from the
  first commit, before any `git add`, and neither is ever pushed. Extractor
  output stays on the machine that ran it.
  - The **data** files are a subtler case. `VALUELST.RES` is a copyrighted
    file, so it is not redistributed either — but the *facts* in it (a fuze is
    40 frames, skates add 150) are not copyrightable, and `docs/ORACLE.md`
    records those facts in our own words with our own analysis. That document
    is safe to commit and publish; the `.RES` file it was read from is not.

---

## 3. Repository layout

Mirrors DOSSkyRoads, because that layout worked: git lives in the Godot project
only, and the reverse-engineering apparatus sits outside it.

```
AtomicBomberman/
  godot-project/          the Godot 4 project — its own git repo, the deliverable
    project.godot
    scripts/core/         constants, enums, scheme parser  (no engine deps)
    scripts/sim/          the authoritative simulation      (no engine deps)
    scripts/net/          protocol, server, client
    scripts/render/       everything that draws
    scenes/
    data/packs/free/      distributable art pack
    data/packs/cd/        extractor output — gitignored
    tests/                headless GDScript suites + harness.gd
    verify.sh
  git-reference-projects/ fpc_atomic, AtomBomberman, Atomic-Bomberman  (given)
  original-game/          the CD's DATA tree — ANI, RES, SCHEMES, SOUND
                          gitignored, never committed, 446 MB  (given)
  tools/                  Python: valuelist.py, scheme.py, extras.py,
                          pcx.py, anifile.py, rss.py, pack_atlas.py, parity.py
  ab-oracle/              C reference implementation anchored to BM.EXE
  analysis/               BM.EXE notes, format specs, disassembly artefacts
  docs/                   PLAN.md (this), ORACLE.md, STATUS.md, BUGS.md
```

`docs/ORACLE.md` is the spec. When a Godot behaviour and fpc_atomic disagree,
ORACLE decides; when ORACLE is silent, the behaviour is an open question for
Track C and gets an entry in `BUGS.md` rather than a guess in the code.

`docs/STATUS.md` is the one handoff file. No PROGRESS.md, no HANDOFF.md.

---

## 4. Track A — simulation and client in Godot

Every phase ends with a command that either passes or fails. Nothing is
"working" because it looked right on screen.

### Phase 0 — scaffold · ✅ DONE 2026-09-02

- **0.1** `godot-project/project.godot`: GL Compatibility renderer, viewport
  **640×480** (fpc_atomic's `GameWidth`/`GameHeight`, which is the original's
  own resolution), `canvas_items` stretch, `integer` scale mode, `keep` aspect.
  Black boot splash, no Godot logo.
- **0.2** Port `verify.sh` and `tests/harness.gd` from DOSSkyRoads. Keep both
  hard-won properties: a **parse pass over every script** whether referenced or
  not, and assertion on a positive `Result:` line rather than on the absence of
  `FAIL`. Do not pass `--quit` — it exits after one frame and silently skips
  frame-driven suites.
- **0.3** `docs/STATUS.md`, `docs/BUGS.md`, `analysis/README.md`, `.gitignore`
  covering `data/packs/cd/` and `cd-content/`.

**Verify:** `./verify.sh` green with one trivial suite.

### Phase 1 — constants and data model, nothing rendered · ✅ DONE 2026-09-02

No engine dependencies, so all of it is headless-testable. Constants are
**generated from `VALUELST.RES`, not hand-copied** — a transcription typo in a
tuning table is invisible for months.

- **1.1** `tools/valuelist.py` — parse `RES/VALUELST.RES` into
  `{resource_number: value | (v1, v2, ...)}`, preserving comments, and emit
  `scripts/core/Values.gd` as generated code. Multi-value rows exist
  (`500,12,10`, `690,2,2`, `600,0,0`), so the parser must handle them.
- **1.2** `scripts/core/Const.gd` — the things VALUELST does *not* hold: the
  15×11 field, the 40×36 tile, the render offsets (20, 66), and the
  frames-to-ms bridge `FRAME_MS = 50` with `TICK_HZ = 20` from resource `30`.
- **1.3** `scripts/core/Types.gd` — `PowerUp` (13 in the scheme file's fixed
  order), `Disease` (nine, per resources `130`–`138`), `BrickData`, `Flame`,
  `BombAnimation`, `RenderAnimation`, `AtomicKey`, `MoveState`.
- **1.4** `scripts/core/Scheme.gd` — parser for the **real** original `.SCH`
  format: `-V` version, `-N` name, `-B` density, 11× `-R` rows,
  10× `-S,playerno,X,Y,team`, 13× `-P,powerup,bornwith,has_override,override,forbidden`.
  Not AtomBomberman's rewritten format.
- **1.5** `tools/extras.py` → `scripts/core/Extras.gd` — the per-level specials
  from `EXTRA{2,3,4,9,10}.RES`, resolving negative coordinates as wraps from the
  right/bottom edge, and expanding EXTRA9's four `H,H` rows into
  randomly-placed trampolines.
- **1.6** Speed helpers. Speeds are **hundredths of a pixel per frame**;
  `tiles_per_sec_h(v) = v/100 * 20 / 40`, `_v(v) = v/100 * 20 / 36`. Movement
  is therefore anisotropic in tile terms and the sim must work in pixels, not
  tiles.

**Verify:** `tests/test_values.gd` asserts the generated table against
hand-checked spot values (`30`→20, `41`→40, `42`→923, `90`→150, `554`→4,
`452`→250) and that no resource number is missing between the documented
ranges. `tests/test_scheme.gd` parses **all 67** files in `SCHEMES/` and
asserts each yields an 11×15 grid, 10 start positions and 13 powerup rows —
67 files is a real parser test, one file is not.
`tests/test_extras.gd` asserts 12 arrows for level 2, 44 for level 3, 4 warps
forming the ring 0→3→2→1→0, 8 tramps for level 9, 32 conveyor cells for
level 10.

### Phase 2 — headless simulation: one player, one bomb · ✅ DONE 2026-09-02

**The first real milestone.** No rendering, no networking, no scene tree.

Delivered beyond the plan: chain reactions with originating-owner kill
attribution, and a 67-scheme smoke run. Two off-by-ones found and fixed —
`docs/BUGS.md` D1, D2.

- **2.1** `scripts/sim/Field.gd` — the tile array and
  `initialize(players, scheme)`: brick-density fill from `-B`, then clear the
  start positions and their neighbours.
- **2.2** `scripts/sim/Sim.gd` — `tick()` at a **fixed 20 Hz / 50 ms** driven by
  an accumulator, per resources `30` and `25`. Never `delta`. Clamp a single
  advance to **150 ms** (resource `31`) so a stall cannot teleport everyone.
  The sim must be steppable from a test with no clock at all.
  *This is a change from fpc_atomic, which runs 100 Hz; see ORACLE §1.*
- **2.3** Movement in **pixels**, not tiles: axis priority, tile re-centring,
  blocked by solid and brick. Speed 923 hundredths px/frame (resource `42`).
- **2.4** Bomb place → **40-frame** fuze (`41`) → cross flame of `FireLen`
  tiles → **10-frame** flame (`10`) → brick destroyed with a **10-frame**
  disintegration (`20`). Note ORACLE row 10: fpc_atomic's 900 ms is wrong.
- **2.5** Player dies on flame contact. Flames pass through players, stop on
  blocks **and on powerups**.
- **2.6** `Sim.state_hash()` — a stable hash over the whole field, players and
  bombs. This is the parity primitive; everything downstream measures with it.

**Verify:** `tests/test_sim_bomb.gd` — place a bomb at (1,1), step 60 ticks,
assert the flame appears on tick 40, is gone by tick 50, the brick at (2,1) is
destroyed, and a player at (1,3) with `FireLen=2` is dead while one at (1,4)
is alive. Because a tick is now 50 ms, every frame count in the test reads
directly off VALUELST rather than needing conversion — which is the point of
matching the original's rate.

### Phase 3 — render the field, two players on one keyboard · ✅ DONE 2026-09-02

- **3.1** Field render at the exact original geometry from 1.1.
- **3.2** Player sprite driven by `RenderAnimation` + `Counter`, using the free
  pack's manifest for frame timing and render offsets.
- **3.3** Two keysets — `ks0` = arrows/Return/Backspace, `ks1` = WASD — so one
  keyboard drives two players, as fpc_atomic does.

**Verify:** playable locally. Plus `tests/render_field.gd` renders tick 0 of
Field01 headless and compares against a checked-in reference PNG, so a layout
regression fails the suite rather than being noticed a week later.

### Phase 4 — powerups, diseases and every ability · PART A ✅ DONE 2026-09-02

Split in two once the work was under way, because the abilities that move bombs
are a different problem from the ones that change a number:

**4a — DONE.** Placement from the VALUELST counts, collection, the caps, the
trigger/spooge/punch exclusion, and the disease model: twelve named diseases,
durations, spreading with the freshness lock, curing, and scattering a dead
player's pickups back onto the field.

**4b — DONE 2026-09-02.** Kick, punch, grab and throw, spooge, jelly bouncing
and trigger, plus the diseases that act on bombs or input: constipation, duds,
short fuze, short flame, controls reversed. `bomb.gd` gained a centipixel
position, a velocity and a flight.

Also delivered here, because a round cannot end without it: the round clock,
Hurry's closing wall at the original's depth of two rows, and the three
round-end cases.

One sub-phase per ability, each with its own test. This is where
`HandleActionPlayer` and `HandleBombs` get ported in full.

The 13 in the scheme file's fixed order: `extra bomb` · `flame` · `disease` ·
`kick` · `skates` · `punch` · `grab` · `spooger` · `goldflame` · `trigger` ·
`jelly` · `super bad disease` · `random`. Plus `clogs`, which is not a level
powerup — it comes from the roulette wheel (resource `91`).

Enforce the caps from resources `550`–`564`: **bombs 8, flame 8, skates 4,
everything else 1.** Skates are **additive** (+150 each), not multiplicative.

Diseases are **nine** types (resources `130`–`138`), each 300 frames = 15 s,
and the model has five rules Track A must implement, none of which fpc_atomic
has in full — see ORACLE rows 28–32: destroyable, time-limited, do **not**
recycle when shed, **multiply** on spread rather than hand off, cured by a
fresh powerup at 1-in-10, and a 10-frame freshness lock preventing re-pass on
a single contact.

Also here, and all missing from the bootstrap: the bomb pickup arc
(`500`–`506`) with its 2-frame pause (`665`), the punch arc heights
(`660`,`661`), the 1-in-3 jelly direction change at intersections (`667`), and
losing 1 + rand(3) powers to a head hit (`670`,`671`).

Watch the exclusions from AtomBomberman's notes (§2): trigger excludes oil and
punch, and picking up trigger drops both.

**Verify:** one test per powerup asserting the exact state transition; one per
disease rule; one asserting each cap; one asserting the trigger exclusion.

### Phase 5 — netcode · ✅ DONE 2026-09-02

**The web milestone.**

- **5.1** Split `Sim.gd` behind an interface. The server owns the sim; the
  client owns only a `GameState` it renders. Phase 3's local mode becomes a
  server and a client in one process.
- **5.2** `WebSocketMultiplayerPeer`. Headless export preset `ab-server`.
- **5.3** Port the 26-message protocol semantics from
  `units/uatomic_messages.pas`, bodies as `PackedByteArray`. WebSocket already
  frames, so fpc_atomic's 12-byte chunk header is dropped.
- **5.4** The screen flow from `client/uscreens.pas`: login → lobby → player
  setup (colour/team) → field setup → round → statistics → victory.
- **5.5** 100 ms heartbeat and the 800 ms sync-pause.

**Verify:** `tests/test_protocol.gd` round-trips every message type. Then an
integration run inside `verify.sh`: one headless server plus two headless
clients, 600 ticks, asserting both clients' `state_hash()` matches the server's
on every broadcast.

### Phase 6 — web export and the self-host kit · ✅ DONE 2026-09-02

- **6.1** HTML5 export. **A browser on an `https://` page cannot open `ws://`** —
  the kit must terminate TLS or serve client and socket from one origin. Settle
  this before writing the compose file, not after.
- **6.2** `server/Dockerfile` + `docker-compose.yml`: headless server plus a
  static file server, one `docker compose up`.
- **6.3** Pack switch: `data/packs/pack.cfg` selects `free/` or `cd/`.

**Verify:** `EXPORT=1 verify.sh` builds both presets and proves the web `.pck`
really carries the art — with the working tree's copy moved aside, because "the
export succeeded" and "the export contains the game" are different claims and
only the first was being checked at first (`docs/BUGS.md` D11).

Still unverified: `docker compose up` with two real browsers. The pieces are
built and the two-process host/join path is exercised, but nobody has yet run
it in a browser.

### Phase 7 — bots · ✅ DONE 2026-09-02

Port `ai/uatomicai.pas` to `scripts/sim/Ai.gd`, keeping the `TAiInfo` /
`TAiCommand` / `TAiField` shapes from `server/uai_types.pas` so a future
alternative AI is a drop-in.

**Verify:** a 10-bot headless match runs three rounds to completion with no
crash and a declared winner.

### Phase 8 — maps and their specials · ✅ DONE 2026-09-02

Driven entirely by `Extras.gd` from Phase 1.5, so this phase is wiring, not
guessing:

- **Level 2, Hockey Rink** — 12 arrows **and** a 250 ms ice control delay
  (resource `452`). fpc_atomic has neither; ice exists on no other level.
- **Level 3, Ancient Egypt** — 44 arrows, 11 per heading.
- **Level 4, Coal Mine** — 4 warp gates, ring 0→3→2→1→0 from data.
- **Level 7, Haunted House** — regenerating tiles every **4 s** (resource
  `347`), only where no player is within radius **4** (`695`).
- **Level 9, Deep Forest Green** — 8 trampolines, 4 fixed and 4 random,
  30-frame bounce at 35 px/frame.
- **Level 10, Inner City Trash** — 32 conveyor cells at 250/350/450.
- **Hurry** — starts at 60 s remaining (`101`, and the file says do not change
  it). Default enclosement depth is **1 = two rows** (`27`), not the full
  spiral fpc_atomic always runs.
- **Random-level lockouts** (`1150`–`1161`) — the developers excluded the
  hockey rink and aliens from random selection, with reasons. Honour it.

Documented interactions: holes and trampolines are **disabled in Hurry mode**,
and a closing wall segment **detonates** a bomb rather than destroying it
(resource `46`).

**Verify:** one test per special, each asserting against the coordinates
`Extras.gd` loaded rather than against a hardcoded list.

### Phase 9 — sound and the match · ✅ DONE 2026-09-02

Split from the original "polish" catch-all, because sound and the match are the
two things a working round is not a game without. What is left of polish —
per-map music, gamepad via Godot's `Input`, options and key rebinding — moves
to Phase 11.

**Sound.** `SOUNDLST.RES` does not list sounds, it lists RANGES: each event
owns a block of resource numbers and every number in the block is an
alternative take, so a repeated action does not sound identical. The file names
the end of each range in its own comments ("299 is the last exploding bomb
sound", "499 is the last standard powerup sound") and in one place states how a
range is consumed — "the code is HARD-CODED to play one of the three below
randomly" for the Hurry tiles, which is the only direct statement anywhere on
the disc about that. `tools/rss.py`'s `EVENTS` table carries those bounds with
the disc's wording beside each.

- **24 named events plus 12 per-disease events**, covering 959 of the 1051
  referenced sounds. The rest is music and menu furniture.
- **The pack is budgeted, not truncated at a round number.** The 36 events
  reference 109.7 MB, most of it 282 death taunts and 144 "you are now AWESOME"
  lines. VALUELST resource 6 states the original's own sound cache budget —
  7,000,000 bytes — so that is the pack's budget too. Takes are chosen
  round-robin, every event getting its first before any gets a second, so a
  tight budget costs variety and never makes an event silent. What was dropped
  is printed per event. Result: **6.99 MB, 83 sounds, 9 takes dropped.**
  `--budget 2000000` gives 2.0 MB and 22 sounds with all 36 events still
  covered, for a leaner web build.
- **Five voices**, from resource 8, whose comment is "how many concurrent
  sounds do we want to allow?". Two rules follow and both are decisions rather
  than measurements, recorded as such in `docs/BUGS.md`: one sound per event
  per tick, so an eight-bomb chain is one explosion rather than eight copies
  0 ms apart; and a full mixer drops the OLDEST voice, so the explosion that
  just killed you is not inaudible behind five taunts from the last death.
- **Raw PCM in an ABPK container**, the same format as the art pack —
  `tools/abpk.py` now owns the layout and `scripts/core/abpk.gd` reads it, so
  the two packs cannot drift. `AudioStreamWAV` takes samples plus a format, so
  a 44-byte RIFF header per sound would be 44 bytes of nothing.

**The match.** Resource 310 — "how many wins to win a match? (default; override
by settings configuration)" — is **2**, and settable, exactly as the comment
says. A `LAST_STANDING` credits its winner; a `DRAW` and a `TIME_UP` credit
nobody, so a match of nothing but draws stays unwon. Team play counts TEAM wins,
because crediting the survivor would let one player's two rounds end a match
their partner also played. Between rounds the field waits resource 13's three
seconds — "MINIMUM number of seconds to wait at screens so that other computers
can catch up", which is exactly this situation and the nearest thing the disc
states to a between-rounds delay.

One implementation, `scripts/core/match.gd`, driven from two places: the server
owns it in network play and tells the client (`S_MATCH`), and `main.gd` drives
the same object in local play. Each round gets its own seed, advanced by a
written-down LCG step rather than randomised, so a whole match replays from its
first seed and a desync is reproducible.

**Verify:** `tests/test_match.gd` (the rules), `tests/test_sfx.gd` (the pack is
complete and the mixer's rules hold), `tests/test_sounds.gd` (every event the
sim can raise, provoked from a real round), plus a match played to its end over
real WebSockets in `tests/test_netplay.gd`. 16 mutations, 16 caught.

**Found on the way, and not by any of that:** two netcode defects that had
nothing to do with sound or matches. Leaving `tools/ws_probe.py` connected to a
real server showed that a **silent client stalled the server permanently** —
the pause stops `_tick()`, and the silence timeout was counted inside `_tick()`
— and that a **closed browser tab held its seat for thirty seconds**, because
nothing listened to `peer_disconnected`. `docs/BUGS.md` D18 and D19. Both are
now tested; neither could have been caught by a suite whose clients all keep
talking.

`tools/ws_probe.py` is kept as a shipped diagnostic: it speaks WebSocket by
hand, with a browser's `Origin` header and no Godot involved, which is the only
way to separate "the server is unreachable" from "the page cannot open a socket
to it".

### Phase 12 — menus · ✅ DONE 2026-09-02

Not a guess at what a menu should offer: `MESSAGES.TXT` 250-268 is the
original's settings screen, label by label and in order, and `OPTIONS.BM` is
that screen's help text saying what each option does. Between them they name
which VALUELST resources are **settings** rather than constants, which is what
resource 310's own comment — "default; override by settings configuration" —
had been pointing at all along.

- **Ten player slots**, not "N humans plus M bots". `MESSAGES.TXT` 220-224 says
  a slot is OFF, AI, KEY %u, JOY %u or NET. That expresses layouts a pair of
  counts cannot — keyboard players on slots 5 and 8 with AI on 1, 3 and 4 —
  and `tests/test_start.gd` starts exactly that game and checks keyset 0
  drives slot 5.
- **The options that map to implemented behaviour are live**: scheme, level
  (including "Random Each Game", `149`), play time from `OPTIONS.BM`'s own
  list, wins, team play, enclosement depth named by `315`-`318`, conveyor
  speed named by `295`-`297`, stomped bombs, destroyable diseases, and lost net
  players reverting to AIs. The ones the simulation does not implement are left
  out rather than shown as toggles that do nothing.
- **The words are the game's own.** `tools/messages.py` generates
  `scripts/core/messages.gd` the way `valuelist.py` generates `values.gd`, and
  every label reads from it.
- **The schemes travel in the asset pack**, as text. A browser has no SCHEMES
  folder, so without that the menu could offer one level.
- **Escape returns to the menu** rather than quitting, and a won match goes
  back to it after holding the victory banner. Quitting is an item on the menu,
  which is where a player looks for it.

The command line is unchanged: any flag that configures a game skips the menu
and starts immediately, so every invocation in `docs/STATUS.md` still means
what it meant. One list, `MENU_SKIPPING_FLAGS`, decides that.

**Verify:** `tests/test_menu.gd` (the model — every clamp, every refusal),
`tests/test_messages.gd` (the generated table), `tests/test_start.gd` (menu to
running game, through main.gd itself), `tests/render_menu.gd` (it fits on the
screen and every row is legible). 17 mutations, 16 caught by suites and one by
the generator refusing to emit an incomplete block.

### Phase 13 — the exact colour remap · ✅ DONE 2026-09-02

The measurement came first, and it changed the implementation.

**What the plan said to do** was `pixel = palette[lut[rgb555(pixel)]]` remapped
per player — a straight lookup. **What the measurement found** was that the
`.ANI` art is not palettised: `WALK.ANI` uses **978 distinct colours and 24 of
them are palette entries**. So `COLOR.PAL`'s 32 KB table is a nearest-match
QUANTISER — the original reduced 15-bit art to 256 colours for an 8-bit display
and remapped the indices afterwards — and writing its output directly would
quantise the sprites for no gain anybody would call fidelity.

So the tables decide the change and the pixel keeps its detail:

    i   = lut[rgb555(pixel)]
    if remap[player][i] == 0: unchanged     # 0 IS "not remapped"
    out = pixel * (palette[remap[player][i]] / palette[i])

Mean absolute per-channel difference from the disc's own transform, over the
54,385 recoloured pixels of `WALK.ANI` — heuristic against this:

    white 11.6 / 10.8    grey 20.4 / 5.1     red   9.3 / 6.6
    blue  30.0 /  7.6    green 7.6 / 7.5     cyan 25.6 / 9.6

and on the pixels whose colour IS a palette entry, where the disc's transform
is exactly defined, **0.03 to 2.61** — 6-bit rounding.

Three blobs go into the asset pack: a 256×1 palette, the 32 KB lookup as a
256×128 greyscale image, and the ten remap tables as 256×10. The shader samples
them with `filter_nearest`, because every one is a table whose texels are
values and interpolating two palette indices produces a third that means
nothing.

**The heuristic stays** on `exact_remap = false`, for a replacement art pack
with no palette to look anything up in, and `AB_EXACT_REMAP=0` selects it.

**Verify:** `tools/remap.py` (the measurement, re-runnable),
`tests/render_shader.gd` (the shader against an independent GDScript
implementation of the same tables, 62 real art colours, worst deviation 0–1 of
255), `tests/render_recolour.gd` (all ten still render nearest their own
VALUELST target — two independent sources on the disc agreeing — and the view
really hands the tables over). 8 mutations, 8 caught, one of which first
exposed D22.

### Phase 14 — the screens · ✅ DONE 2026-09-02

Prompted by four bug reports from actual play — the explosion, the bomb's
position, players leaving the screen, and missing UI — and by "ensure all
screens and gameplay is properly ported". Three of the four were one arithmetic
error and two missing terms; `docs/BUGS.md` D24 has them.

**Every screen the original has ships as a 640x480 PCX**, and the port now
carries all 25 plus 9 smaller elements. `docs/AUDIT.md` is the row-by-row
account of what is ported and what is not.

- **The title, the main menu, the setup screen, the options screen, About,
  Online Manual, Results, ten victory screens, the draw screen** and the team
  screens. `MAINMENU.PCX` has its seven items painted in, so the port measured
  their positions from the art — seven bands, 37 px apart from y=115 — and
  draws `MISC.ANI`'s four-frame pointer beside them.
- **`GLUE0`-`GLUE6` are wallpapers, not screens.** That was the first
  assumption and it was wrong: GLUE4 is a wall of BombFlakes cereal boxes.
  They are the backdrops the setup and options screens are drawn on.
- **The lettering is the game's own.** `KFONT.ANI` turned out to be ten digits,
  a colon and an infinity sign — the clock — so the alphabet came from
  `FONT1.FON` in the install root. `tools/fonts.py` decodes it; three of the
  format's four parameters were guessed wrong first and every wrong guess
  produced almost-readable text. A tiling test settled it: 190 of 190 glyph
  gaps exact, and the totals agree to the byte.
- **`HEADWIPE.ANI`** — 211 frames of a 73x73 bomberman — runs across the
  screen between screens.
- **The in-game status band** shows the clock in `KFONT`'s own digits and its
  own colon, and a disc per player with their win count. The band's layout is
  the port's: the original draws it in code, and no art for it has been
  identified.
- **`KFACE.ANI` is not a status portrait.** It is a photographed human head in
  four directions — the Kurt-head easter egg player. `docs/BUGS.md` D26.

**Verify:** `tests/test_screens.gd` (the flow, headless — every item, every
back-out, no dead ends), `tests/test_fonts.gd` (shift-sensitive glyph widths),
`tests/render_screens.gd` (every screen draws, uses the original's art, and its
cursor lands beside the painted text), `tests/render_hud.gd` (the clock, the
colon by template match, a marker per seat, the HURRY banner),
`tests/render_field.gd` (nothing leaves the field; a bomb sits on its cell).
16 mutations, 16 caught — four of them only after the tests were strengthened
twice.

### Phase 15 — the Goldman roulette · ✅ DONE 2026-09-02

The last screen with art on the disc and nothing drawing it, and the only one
whose LAYOUT did not have to be invented — because VALUELST spells the
animation out, in multi-value entries:

    1000,320,240   ; center of roulette wheel for goldman screen
    1002,200,150   ; radius(es) (x,y) of roulette wheel perimeter
    1004,70        ; resolution of the circle the roulette wheel turns on
    1006,1,1       ; X,Y parameters for lissajous-shaped roulette wheel
    1010,5         ; how many seconds the twinkling of goldman lasts
     805,320,30,0,400  ; Goldman Roulette Wheel (title at top)

Fourteen powerup icons on an ELLIPSE of radii 200x150 about (320, 240), stepped
at a resolution of 70, on a Lissajous path whose parameters are both 1 — which
is a plain ellipse, presumably why the comment beside resource 1006 ends in
"(grin)". The general form is implemented anyway, because the data can say
otherwise.

`OPTIONS.BM` says what it is for: *"The Gold Bomberman is a reward given to the
winner of the last match. The reward consists of a random powerup determined by
the roulette wheel. (Not available in network games)"*. So the winner spins,
and the prize is granted at the start of the FIRST round of the next match and
then spent. It is off over a network, as that sentence requires.

**It can punish.** The wheel offers all fourteen powerups including CLOG, the
fourteenth, which `MESSAGES.TXT` 813 calls "a speed brake (slowness)" and which
resource 91 describes as *"how much speed the CLOGS (special roulette
power-'down') take away"* — 150 hundredths of a pixel. SOUNDLST has a sound for
exactly that case: 1320, *"buzzer sound, you got the molasses roulette powerup
(powerdown)"*, alongside 1300's periodic tick and 1310's clapping.

**Two bugs found by its own tests**, both of which would have shipped:

- **The wheel ignored its seed.** With a fixed start and a fixed speed the
  deceleration is deterministic, so it landed on the same icon every time —
  measured over 119 seeds, one prize. Both the starting position and the speed
  come from the seed now.
- **It spun five times too fast**, because it was ticked once per frame while
  the screen it is drawn on ticks once per 50 ms. It had already landed by the
  twentieth screen tick. Found by making `--shot` report the screen's age.

**Verify:** `tests/test_roulette.gd` asserts every icon lies on the ellipse the
data specifies, that the wheel reaches most of its positions across seeds, that
the same seed awards the same prize, and that the announcement is built from
`MESSAGES.TXT` 790, 791 and 800-813. `tests/render_screens.gd` checks the icons
are drawn where the data puts them. 10 mutations, 9 caught and one equivalent.

### Phase 10 — delta encoding, if measured to be needed

Dirty-tile tracking and client interpolation, only once Phase 5's bandwidth has
been measured over a real internet link rather than assumed.

### Phase 11 — the rest of polish

~~Per-map music~~ and ~~gamepad~~ are DONE, 2026-09-03. The music is read from
the player's own copy of the game rather than packed — eleven tracks, 120 MB
against resource 6's 7 MB — so a desktop run has it and a browser build cannot;
`MESSAGES.TXT` 263 turns it off. The gamepad is `MESSAGES.TXT` 223's `JOY %u`
slot type, offered when a pad is plugged in, with the keyboard's own
one-axis-at-a-time rule on the stick.

**Campaign mode is DONE too**, out of the disc's own three `.CAM` files and
`ALIENS1.ANI`'s rovers and ghosts. What the files do not say — what a rover or
a ghost actually does — is listed as this port's decision in
`scripts/sim/creature.gd`.

**The network game list is DONE** in the only way it can be: the screen is
`MESSAGES.TXT` 60-66's, and the discovery behind it is a UDP beacon this port
invented, because a WebSocket cannot be enumerated the way IPX could.

**Key rebinding is DONE, 2026-09-03.** `MESSAGES.TXT` 1100-1140 specified the
whole screen and the port now has it, reached from the options list's own 265
"Define keyboard layouts": twelve rows (six actions each for the two keysets),
1105's prompt while a row waits for a key, 1130's restore-defaults row and
1131's confirmation. Keys live in `user://keys.cfg`. `tests/test_keys.gd`, 83
checks; 11 mutations, 11 caught.

~~The statistics screen turns out not to need art~~ — **DONE 2026-09-03, and it
is not a screen at all.** Message 900 says "Statistics **File**", and
`BM95.EXE` writes it at `0x40200C` without ever drawing it: `bmstats.dat`,
100 dwords of totals, and `bmstats.txt`, `"%-30s %13u %13u"` a row with Total
before Last Run. `scripts/core/stats.gd` writes both, to `user://`, and 14 of
the 19 counters are collected — `docs/AUDIT.md` §1.1 lists the five that
cannot be and why. `tests/test_stats.gd`, 98 checks; 9 mutations, 9 caught;
and `verify.sh` runs the game itself to prove the wiring, because a suite can
only reach the format.

The options the simulation does not implement yet, each named by the original's
own settings screen: **Gold Bomberman** (`256`, with the roulette at `650` and
the announcement at `790`/`791` — the roulette itself is built, the switch to
turn it off is not) and **Disable Music During Gameplay** (`263`), which has no
music to disable until `SOUNDLST` 1100-1110's per-level tracks are in the pack.

**Win Matches By Kill Total** (`255`) and **Random Start** (`251`) are DONE,
2026-09-03. Kills count toward the same target the wins do — the disc has one
number and two sentences for it, `120` and `121` — a suicide costs one
(`OPTIONS.BM`), and every round counts, including the draws and time-ups that
credit nobody in the ordinary mode. Random Start deals the scheme's start cells
out once per match, positions only, and **defaults to ON because VALUELST 40
says so**; `docs/BUGS.md` §3 records that the resource number in `AUDIT.md` was
wrong. 13 mutations, 13 caught, across `tests/test_round.gd`,
`tests/test_bomb.gd`, `tests/test_match.gd` and `tests/test_menu.gd`.

---

## 5. Track C — BM.EXE as oracle

Runs in parallel and never blocks Track A. Its output is entries in
`docs/BUGS.md`, each naming a behaviour, what the binary does, what the Godot
sim does, and the test that will prove the fix.

- **C1 — data. ✅ Done, 2026-09-02.** `original-game/` holds the whole install.
  Constants, level specials, all 67 schemes, 1051 sound mappings, 316 strings
  and the colour remap tables are extracted into `docs/ORACLE.md`. Nothing is
  still to fetch: the `ani.zip` expansion turned out not to exist as a need —
  resource `105`'s 24 death animations are 24 named `SEQ ` sequences inside the
  seventeen `XPLODE` files, not 24 files. `docs/BUGS.md` Q4.
- **C2 — settle the tick rate. ✅ Done.** Resources `30` and `25` both say
  **20 FPS**, resource `41` says a 40-frame fuze, and resource `31` caps a
  single advance at 150 ms. AtomBomberman's notes were right and fpc_atomic's
  100 Hz is its own invention. No disassembly was needed. ORACLE §1.
- **C3 — acquire the binary. ✅ Done, 2026-09-02.** `BM95.EXE`, 424,448 bytes,
  dated 11 July 1997.
- **C4 — identify the binary. ✅ Done, 2026-09-02.** PE32 for i386, GUI
  subsystem, not packed. Sections named `BEGTEXT` and `DGROUP` with linker
  version 2.18 make it **Watcom C/C++**, and that is the fact the whole track
  turns on: Watcom passes the first arguments in **EAX, EDX, EBX, ECX**, so
  every cross-reference has to look for `mov eax, imm` before a `call` and
  would find nothing at all under an MSVC assumption. Imports name the runtime:
  DDRAW, DSOUND, DINPUT, WINMM, WSOCK32. `tools/bmexe.py --info`.
- **C4b — the way in. ✅ Done, 2026-09-02.** Every tuning value is fetched
  through **one** function, by number, so `docs/ORACLE.md` already says what
  each number MEANS and the call sites say WHERE it is used:

      0x412135  value_of(valueno) -> int      VALUELST.RES
      0x4124A4  message_of(id) -> char *      MESSAGES.TXT
      0x427961  play_sound(soundno)           SOUNDLST.RES
      0x45190A  rand()                        ANSI LCG

  Identified by scoring each function's constant arguments against the three
  key sets parsed from the data files — `message_of` takes 167 of 167 MESSAGES
  ids — and `value_of` confirmed by its own failure path, which compares
  against **-12345** and prints `"invalid valueno requested: %u"` before
  exiting. That is `VALUELST.RES`'s own header warning, in code.
  `tools/bmexe.py --accessors --xref`.
- **C5 — the four algorithms the data cannot express.** All four are now
  LOCATED by the cross-reference; one is partly read. `docs/BUGS.md` Q5 has the
  addresses. **A fifth thing was settled on the way and was not on this list:**
  the sound mixer, `docs/BUGS.md` Q8 — both of the port's invented rules were
  wrong, and the port now does what 0x427961 and 0x427859 do. That is the first
  time Track C has corrected Track A rather than fpc_atomic.

  In priority order, because each is a thing Track A would otherwise guess:
  1. **Movement and tile re-centring.** Resource `42` gives the speed but not
     the corner-rounding rule, and ORACLE row 2 shows the original is
     anisotropic in tile terms (4.62 h, 5.13 v tiles/s) because it moves in
     pixels. This is the highest-value target.
  2. **Powerup scatter.** We have the counts (`400`–`412`) and the
     negative-means-1-in-10 rule, not the placement algorithm.
  3. **Flame propagation order**, and the rule that flames stop on powerups.
  4. **AI.** Resources `900`, `910`, `915`, `920` are four knobs; the logic is
     in the exe. Until then Phase 7 ports fpc_atomic's agent, which is honest
     but is not the original's.
- **C6 — `ab-oracle/`.** A headless C reimplementation anchored to the binary,
  the same role `skyroads-port/` played. Driven by a scripted input file, dumps
  one state record per tick. Its constants come from `tools/valuelist.py`, so
  the two engines cannot drift on a number.
- **C7 — `tools/parity.py`.** Feeds the same input script to `ab-oracle` and to
  the Godot sim, diffs per-tick state, and reports the first divergence with the
  field it diverged on. This is what turns "feels right" into a number.

**Verify:** `THREEWAY=1 tools/verify.sh` — C oracle, Godot sim, and (where a
Python model exists) all three agreeing tick-by-tick on real levels.

If `BM.EXE` never arrives, the port is still **constant-exact and
data-exact** — 42 behaviours anchored, 67 real schemes, every level special at
its real coordinates. Only the four algorithms above stay at
fpc_atomic-plus-notes fidelity, and each gets a `BUGS.md` entry saying so
rather than being quietly presented as parity.

---

## 6. Track B — assets

**B1-B4 ✅ DONE 2026-09-02.** B6 (colour remapping) ✅ DONE — `docs/BUGS.md`
Q6. B5, the free art pack, is now unblocked: a replacement set needs to be
authored in ONE colour with the recolourable areas green-dominant and
everything meant to stay fixed grey or non-green, which is exactly how the
original's own art is built.

Doubly testable: fpc_atomic's checked-in `files.txt` manifests give expected
frame counts, and the real files are now on disk to run against.

- **B1** `tools/pcx.py` — PCX decode. **61 files** in `RES/`, 10 MB.
  **Verify:** byte-identical to Pillow's PCX reader on all 61.
- **B2** `tools/anifile.py` — ANI container → frames, hotspots, colour key.
  Format confirmed by inspection: IFF-style chunks, `CHFILE` / `ANI ` / `HEAD`
  / `PAL ` then per-frame records; 4-byte signature, `uint32` length, `uint16`
  id. Spec from `cd_data_extractor_src/uanifile.pas` and `mmatyas/ab_aniex`.
  **95 files**, 7.7 MB. Load order from `ANI/MASTER.ALI`.
  **Verify:** frame counts and cell sizes match
  `fpc_atomic/data/atomic/*/files.txt` exactly — e.g. `applbite` must yield
  121 frames of 73×73 with hotspot (36, 64).
- **B3** `tools/rss.py` — raw 22050 Hz / s16 / stereo / LE → wav, then ogg.
  **2027 files**, 428 MB, driven by the 1051 entries in `SOUNDLST.RES` so
  unreferenced files are skipped.
  **Verify:** duration equals `bytes / (22050·2·2)` — checked, `1000.RSS` is
  226 168 B = 2.564 s — and every `SOUNDLST` name resolves to a file on disk.
- **B4** `tools/pack_atlas.py` — frames → Godot atlas + `SpriteFrames` `.tres`,
  emitting the same manifest columns. Use the `sprite-atlas` skill.
- **B5** Free replacement pack via `sprite-forge` / `ai-gen` / `pixel-post`,
  built to the **same cell sizes, frame counts and hotspots** as the extracted
  frames, so the two packs are drop-in swappable and the pack switch in 6.3 is
  a one-line change rather than a code path.
- **B6** `.RMP` colour remaps are **not** in the dump, but resources `200`–`247`
  give the ten RGB triples they encode (ORACLE §3), so build the remap from
  those instead.

The 10 stray `.GIF` files in `SOUND/` are 493×400 development artefacts.
Ignore them.

---

## 7. Risks

| Risk | Why it matters | Mitigation |
|---|---|---|
| ~~CD content unavailable~~ | ~~Blocks Track C and Track B~~ | **Resolved 2026-09-02** — `original-game/` |
| `BM.EXE` never arrives | The four algorithms in C5 stay at bootstrap fidelity | Port is still constant- and data-exact; each gap gets a `BUGS.md` entry rather than a parity claim |
| `BM.EXE` packed or hostile | Track C's cost balloons | C4 answers this before any C6 work is committed |
| `ani.zip` expansion missing | Resource `105` wants 24 death animations; the dump has `XPLODE1`–`17` | Fetch it, or ship 17 and record the shortfall |
| `ws://` blocked from `https://` | Silent failure that looks like a server bug | Settled in 6.1, before the compose file |
| 1.6 Mbps/client over the internet | Playable on LAN, unplayable on a cheap VPS with 10 players | Measure in Phase 5, fix in Phase 10 |
| Float sim divergence across browsers | Would break the client-side `state_hash()` assertion in 5.5 | Server is authoritative and clients never simulate, so divergence is a bug not a design constraint |
| fpc_atomic attribution | Its headers forbid removing the provenance text | Ported files carry a comment naming the original unit and its licence |

---

## 8. First session

1. **Phase 0** — scaffold, `verify.sh`, `docs/STATUS.md`.
2. **Phase 1** — `tools/valuelist.py`, `tools/extras.py`, the real `.SCH`
   parser, generated `Values.gd`, and the three test suites. All 67 schemes
   parsing is the milestone, not one.
3. **Track B1–B3 in parallel** — the extractors, now that the data is on disk.
   B2 is the one with real risk in it; B1 and B3 are an afternoon each.

Deliberately **not** first: any Godot rendering. Phases 0 and 1 produce no
pixels and are entirely headless, which is what makes Phase 2's sim testable
before anything is drawn.
