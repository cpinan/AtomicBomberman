# ORACLE — what the original's own data files say

_Written 2026-09-02 from `original-game/`, which is the CD's `DATA` tree.
This is the spec Track A implements against. Where it disagrees with
fpc_atomic, **this document wins** — fpc_atomic is the bootstrap, not the
authority._

Sources, in descending order of authority:

1. **`RES/VALUELST.RES`** — Kurt W. Dekker's own tuning table, dated
   02/04/97–07/11/97, loaded by the game at runtime. Commented throughout. The
   header warns that changing a resource number makes the program exit to DOS,
   which tells us the game looks these up by ID rather than embedding them.
2. **`RES/EXTRA*.RES`**, **`RES/SOUNDLST.RES`**, **`RES/*.CAM`**,
   **`SCHEMES/*.SCH`** — data the game reads, same standing.
3. `BM.EXE` — **absent.** See §6.

Two unit conventions from the VALUELST header, and everything else follows
from them:

> **CHANCES:** all chances are 1-in-N.
> **SPEEDS:** speeds are in **hundredths of a pixel per frame**. A speed of
> 100 moves 1 pixel per frame.

A tile is **40 × 36 px** and the frame rate is **20 Hz**, so a speed value `v`
is `v/100 × 20 / 40` tiles/s horizontally and `v/100 × 20 / 36` vertically.

---

## 1. The frame rate question is settled

| Resource | Value | Meaning |
|---|---|---|
| `30` | 20 | frames per second the game attempts |
| `25` | 20 | nominal reference frame rate for every frame-count value in the file |
| `31` | 150 | max milliseconds the game may advance in one frame (disk-hit clamp) |
| `41` | 40 | fuze length in frames = **2.0 s** |

**The original simulates at 20 Hz.** `AtomBomberman/notes` derived exactly this
("40 animation frames ... which means 20 FPS") and was right. fpc_atomic's
100 Hz sim with a 50 Hz broadcast is its own invention.

Resource `25`'s comment is worth quoting because it governs how to read the
rest of the file:

> this is only a nominal frame rate that is used as a reference for other
> frame-count-based values in this file! Do not change this value because it
> will not improve your performance at all

So every "frames" value in VALUELST is **20ths of a second**, regardless of
what the renderer does. That splits cleanly: **simulate at 20 Hz, render and
interpolate at whatever the display runs at.**

---

## 2. Divergence ledger — original vs. fpc_atomic

Each row is a thing Track A must implement the original's way. `PGT` in the
table below marks values the original file tags `; PGT` — per-game-tunable,
i.e. gameplay-critical.

| # | Behaviour | Original | fpc_atomic | Verdict |
|---|---|---|---|---|
| 1 | Sim rate | **20 Hz** (`30`,`25`) | 100 Hz sim / 50 Hz net | fpc_atomic invented |
| 2 | Speed unit | hundredths **px/frame** (`42`=923) → **4.62 tiles/s horiz, 5.13 vert** | single tiles/s scalar, default 5 | original is **anisotropic** in tile terms; fpc_atomic is not |
| 3 | Skates | **additive +150** per skate (`90`), max **4** (`554`) → 923→1523, +65% | multiplicative ×1.1, 5 steps, +61% | same ballpark, wrong per-step and wrong cap |
| 4 | Clogs (roulette power-down) | **−150** (`91`) | `/1.1²`, −17% | fpc_atomic has no clogs |
| 5 | Powerup caps | bombs **8**, flame **8**, skates **4**, all others **1** (`550`–`564`) | speed only | caps missing |
| 6 | Conveyor speeds | absolute **250 / 350 / 450** (`190`–`192`) | derived from player speed ladder | fpc_atomic derived what was tabulated |
| 7 | Kicked bomb | **1000** (`300`) | derived from player speed | ditto |
| 8 | Punched bomb | **1300** (`301`) | derived | ditto |
| 9 | Disease duration | **300 frames = 15 s**, nine types (`130`–`138`) | 10 s, five types | wrong duration, missing types |
| 10 | Brick disintegration | **10 frames = 500 ms** (`20`) | `BrickExplodeTime = 900` | wrong |
| 11 | Flame animation | **10 frames = 500 ms** (`10`) | `FlameTime = 500` | ✅ match |
| 12 | Fuze | **40 frames = 2000 ms** (`41`) | `AtomicBombDetonateTime = 2000` | ✅ match |
| 13 | Team-colour switch | **40 frames = 2000 ms** (`32`) | `AtomicTeamSwitchTime = 2000` | ✅ match |
| 14 | Dud bombs | ≥**180 s** + rand 180 s between candidates, **1-in-3** chance, wait **120 + rand 200** frames (`320`–`324`) | 2500–5500 ms | completely different model |
| 15 | Death animations | **24** (`105`) | 9 (die8 commented out) | 15 missing |
| 16 | Cornerhead animations | **13** (`330`) | 8 | CD ships CORNER0–7; 13 implies more elsewhere |
| 17 | Round length | default **150 s** (`100`), Hurry at **60 s remaining** (`101`) | editable 90–600 s | Hurry threshold is fixed at 60 and the file says don't touch it |
| 18 | Wins to win a match | **2** (`310`) | configurable | ok as default |
| 19 | Enclosement depth | default **1 = 2 rows**; 4 depths 0–3 (`27`,`28`) | full 160-tile spiral, always | original default closes **two rows**, not the whole field |
| 20 | Hockey rink | **12 arrows** (EXTRA2) **+ 250 ms ice control delay** (`452`) | no specials at all, no ice anywhere | both missing |
| 21 | Regenerating tiles | level **7 only**, every **4 s** (`347`), clear radius **4** (`695`) | random 1000–4000 ms | wrong interval; radius rule present in 0.13003 |
| 22 | Trampolines | **30 frames** bounce (`680`), **35 px/frame** vertical (`681`); **8 total** = 4 fixed + 4 random (EXTRA9) | `AtomicTrampFlyTime = 1500` ms, `FieldTrampCount = 8` | count ✅ **confirms fpc_atomic's guess**; timing 1500 ms vs 30 frames = 1500 ms ✅ |
| 23 | Punch arc | **65** initial 3-space, **20** subsequent 1-space (`660`,`661`) | `AtomicBombBigFlyTime/Small = 500/250` ms | different parameterisation (height vs. time) |
| 24 | Bomb pickup curve | 4 points: (12,10) (25,20) (25,30) (12,40) (`500`–`506`) | none | missing |
| 25 | Pickup pause | **2 frames** (`665`) | none | missing |
| 26 | Jelly direction change | **1-in-3** at each intersection (`667`) | none | missing |
| 27 | Head-hit power loss | lose **1 + rand(3)** powers (`670`,`671`) | not modelled | missing |
| 28 | Diseases: destroyable | yes (`120`) | yes | ✅ |
| 29 | Diseases: recycle when shed | **no** (`122`) | respawns collected powerups on death | check |
| 30 | Diseases: multiply on spread | **yes** (`123`) | hand-off | wrong |
| 31 | Diseases: cured by new powerup | yes, **1-in-10** (`124`,`125`) | not modelled | missing |
| 32 | Disease freshness lock | **10 frames** before re-passing (`129`) | not modelled | missing |
| 33 | Warp gates | 4 gates, **explicit** target ring 0→3, 1→0, 2→1, 3→2 (EXTRA4) | hardcoded "counter-clockwise" | same result, but drive it from data |
| 34 | Powerup spawn counts | `400`–`412`; **negative = that many 1-in-10 rolls** | matches | ✅ and matches AtomBomberman's table |
| 35 | Start positions | `600`–`618`, **negative wraps from right/bottom edge** | matches | ✅ |
| 36 | Attract mode | after **30 s** idle (`92`); `<5` disables | 10 s Zen idle animation | different feature |
| 37 | Post-death taunt | **1-in-5** (`95`) | not modelled | missing |
| 38 | Random-level lockouts | hockey rink **off** — *"too annoying to have control delays"*; aliens **off** — *"too hard to see visually"* (`1150`–`1161`) | all 11 available | the developers' own opinion, worth honouring |
| 39 | Wall segment hits a bomb | **detonates** it (`46`,`1`) | — | check |
| 40 | Concurrent sounds | **5** (`8`) | — | mixer cap |
| 41 | Campaign mode | 3 campaigns, rovers + ghosts + AIs, points 250 / 15 / 25 (`1300`–`1320`, `*.CAM`) | absent | a whole single-player mode the data supports |
| 42 | AI | **1 personality** (`900`), fire-god lookahead **15** (`910`), blast-bricks **1-in-5** (`915`), powerup pursuit radius **4** (`920`) | custom agent | original's AI logic is in the exe; only its knobs are here |
| 43 | Sound list structure | each event owns a RANGE of resource numbers; every number in it is an **alternative take** | one file per event | fpc_atomic throws the variety away |
| 44 | Sound cache budget | **7,000,000 bytes** across at most **200** cached effects (`6`,`5`) | — | the disc's own answer to how much audio to hold |
| 45 | Wins to win a match | **2**, and the comment says settings override it (`310`) | — | a match, not an endless round |
| 46 | Wait at a screen | **3 s** minimum, *"so that other computers can catch up"* (`13`) | — | the nearest thing the disc states to a between-rounds delay |
| 47 | Hurry tile sound | **hard-coded to three takes** (`140`–`142`) and the file warns that adding a fourth does nothing | — | the only statement on the disc about how a range is consumed |
| 48 | AWESOME line | plays on the **7th powerup and every 3rd after** (SOUNDLST 1400–1699 comment) | — | no VALUELST resource for either number |
| 49 | Per-disease sounds | **twelve ranges**, 3000 + 50·i, each named in a comment | five diseases, no sounds | the ordering that named `Types.Disease` |
| 50 | Team split | **slots 1-5 against 6-10** (`OPTIONS.BM`, said twice) | — | the port had `slot % 2`; see BUGS D20 |
| 51 | Level names | **eleven, `MESSAGES.TXT` 150-160** | its own strings | the port had music filenames standing in |
| 52 | Enclosement depth names | **None / A Little / A Lot / All the way!** (`315`-`318`) | always the full spiral | names the four depths resource 27 selects |
| 53 | Play time | **1:00, 1:30, 2:00, 2:30, 3:00, 4:00, 5:00, 10:00, Infinite** (`OPTIONS.BM`) | — | resource 100's 150 s is 2:30, and is in the list |
| 54 | Random level | **"Random Each Game"** heads the level list (`149`) | — | what the `1150`-`1161` lockouts are for |
| 55 | Player slots | **OFF / AI / KEY n / JOY n / NET**, ten of them (`220`-`224`) | fixed player list | expresses layouts a humans+bots pair cannot |
| 56 | Powerup count | **fourteen** named, the 14th being `Clog` (`800`-`813`, `850`-`863`) | thirteen | a scheme places 13; the roulette hands out the 14th |
| 57 | Death animations | **24 `SEQ ` sequences in 17 files** (`105`, `TOOLS/ANIMS.TXT`) | 9, treating it as a file count | BUGS Q4 |
| 58 | Cornerhead animations | **13 `SEQ ` sequences in 8 files** (`330`) | 8, ditto | BUGS Q3 |
| 59 | Colour remap | **`.RMP` tables over palette indices 100-169, 172-174**, through `COLOR.PAL`'s RGB555→index lookup | green-dominance heuristic | implemented; fpc's test approximates the block and agrees on 95.6% of pixels |
| 60 | Sprite colour depth | **15-bit art, quantised to 256 at load** — `WALK.ANI` has 978 colours, 24 of them palette entries | 24-bit throughout | the lookup is a quantiser, so the port applies the remap as a ratio and keeps the depth |
| 61 | Sound take choice | **random among the LEAST-USED**, a shuffled deck (`BM95.EXE` 0x427961) | one file per event | BUGS Q8; the port did round-robin |
| 62 | A full mixer | **refuses the new sound** (0x427859), and admits while `live <= cap`, so **six** can play on a cap of five | — | the port evicted the oldest |
| 63 | Chain reactions | **every bomb's sound is played**, each a different take | — | the port collapsed them to one |
| 64 | Sound group extent | **ends at the first GAP** in the numbering, not at the range the comments describe | — | strands 172 recorded sounds the game never plays |
| 65 | `rand()` | ANSI LCG, `state*0x41C64E6D + 0x3039`, bits 16..30 (0x45190A) | Godot's RNG | the AI is its heaviest user, 20 of 104 sites |
| 66 | AI walkability | **a bomb blocks**, and the two grid queries disagree out of bounds (0x40A59D) | — | BUGS Q5 |
| 67 | AI scheduling | **one call per player per frame**, from the same update that moves a human (0x41F29B → 0x40A1C6) | separate agent | personality is chosen once at round setup |
| 68 | Field geometry | **derived from the screen**: `X = (w - 600)/2`, `Y = h - 396 - 16` (0x42647A, `map.c:317`) | fixed | the port had Y=66 where the formula gives 68 |
| 69 | Sprite anchor | **the hotspot sits on the cell's bottom edge**, `BLOCK_H/2 - 1` below the stored centre — the same 17 `tile_y` subtracts | varies | BUGS D24 |
| 70 | Screens | **25 PCX screens plus 9 elements**, every one 640x480 | its own | the port shipped none of them until Phase 14 |
| 71 | GLUE0-6 | **tiling wallpapers**, not screens | — | GLUE4 is BombFlakes cereal boxes |
| 72 | Menu items | **painted into `MAINMENU.PCX`**, seven bands 37 px apart from y=115 | text | so a port can only put a cursor beside them |
| 73 | Lettering | **`FONT1.FON`**, a 1-bit bitmap font, 191 glyphs | its own | `KFONT.ANI` is digits, a colon and an infinity sign |
| 74 | The clock | **`KFONT` digits and `DC.TGA`**, a 6x19 colon | — | the port drew two squares; BUGS D25 |
| 75 | `KFACE.ANI` | **a photographed human head**, four directions — the Kurt-head easter egg | absent | BUGS D26 |

Rows 1, 2, 3, 9, 10, 14, 19, 20 change how the game *feels* and are the ones to
get right before Phase 4 builds on top of them.

Rows 43–49 came out of Phase 9 and none of them needed a disassembly: they are
all in comments in `SOUNDLST.RES` and `VALUELST.RES`. Row 43 is the one that
changes the most — a port that plays one file per event sounds nothing like the
original, which has 20 explosions and 282 death taunts and picks among them.

Rows 50–59 came from a **more complete copy of the install**, which arrived on
2026-09-02 with `MESSAGES.TXT`, the `*.BM` help files, `TOOLS/`, the ten
`.RMP` files, `COLOR.PAL` and `BM95.EXE`. None of them needed a disassembly
either — they are text files the game reads. Rows 57 and 58 are the two that
were open questions, and both turn on the same thing: **an animation is a named
`SEQ ` sequence, not a file**, and one `.ANI` holds several.

Row 50 is the one that was actively wrong rather than missing.

Rows 61–67 are the first from `BM95.EXE` itself, and they are a different kind
of row: not "the disc's data says X and fpc_atomic does Y" but "the disc's CODE
says X and **this port** did Y". Four of them corrected this port rather than
fpc_atomic, which is what Track C is for. `tools/bmexe.py` is the tool and
`docs/BUGS.md` Q8 and Q5 carry the disassembly.

---

## 3. Player colours

`200`–`247`, RGB triples 0–100, one per `.RMP` remap file. **Identical to
fpc_atomic's `PlayerColors`** — it got these right.

`0` white 100/100/100 · `1` black 20/20/20 · `2` red 100/0/0 ·
`3` blue 0/0/100 · `4` green 0/100/0 · `5` yellow 100/100/0 ·
`6` cyan 0/100/100 · `7` magenta 100/0/100 · `8` orange 100/50/0 ·
`9` purple 50/0/100

The `.RMP` files themselves are **not in the dump**, but these triples are what
they encode, so the remap is reconstructible.

---

## 4. Scheme file format — the real one

`SCHEMES/*.SCH`, 67 files, machine-generated by the game's own editor. This is
**not** the format in `AtomBomberman/default.sch`; that clone rewrote it. Phase
1.3 must target this:

```
-V,2                          internal version
-N,Just the BASIC SET! (10)   display name
-B,90                         brick density, 0-100 %
-R, 0,:::::::::::::::         one row, 11 of them, y=0..10; # solid, : brick, . blank
-S,0,0,0,0                    start position: playerno, X, Y, team
-P, 0, 0,0, 0, 0,an extra bomb
                              powerup#, bornwith, has_override, override_value, forbidden, comment
```

13 powerup rows in fixed order: bomb, flame, disease, kick, skate, punch, grab,
spooge, goldflame, trigger, jelly, super bad disease, random.

## 5. Level specials — exact, from data

Negative coordinates wrap from the right/bottom edge, per the `600` comment.

| File | Level | Contents |
|---|---|---|
| `EXTRA2.RES` | 2 Hockey Rink | **12 arrows** in three 4-arrow rings (`-A,heading,x,y`) |
| `EXTRA3.RES` | 3 Ancient Egypt | **44 arrows**, 11 per heading |
| `EXTRA4.RES` | 4 Coal Mine | **4 warps** `-W,1,gate,x,y,target` → ring 0→3, 1→0, 2→1, 3→2 |
| `EXTRA9.RES` | 9 Deep Forest Green | **8 tramps**: 4 fixed at (2,2) (-3,2) (2,-3) (-3,-3), 4 marked `H,H` = randomly placed |
| `EXTRA10.RES` | 10 Inner City Trash | **32 conveyor cells** — two horizontal belts, two vertical, forming one loop |

Levels 0, 1, 5, 6, 7, 8 have no EXTRA file and therefore no specials — except
level 7, whose regenerating tiles come from VALUELST `347` rather than an
EXTRA file.

## 6. What is still missing, and what only `BM.EXE` can give

**Everything this section used to list as absent has arrived.** A fuller copy
of the install landed on 2026-09-02, and the four items below are struck
through rather than deleted, because each one shaped a decision while it was
believed:

- ~~**`BM.EXE`**~~ — `BM95.EXE` is present, 424,448 bytes. Track C can start.
- ~~`*.RMP` — reconstructible from §3~~ — all ten are present, and §7 has their
  structure. They are not reconstructible from §3 and never were: §3 gives the
  ten target colours, and a `.RMP` gives a per-index mapping over a 73-entry
  block. The reconstruction that was built from §3 is fpc_atomic's heuristic,
  which approximates the block rather than reproducing it. `docs/BUGS.md` Q6.
- ~~`MESSAGES.TXT` — 49 default node names. Cosmetic.~~ — present, and very far
  from cosmetic: it is the specification for every screen. §6b.
- ~~The `ani.zip` expansion — some deaths will be missing~~ — **nothing is
  missing.** `105,24` counts `SEQ ` sequences, not files, and the seventeen
  `XPLODE` files hold exactly 24 of them. `docs/BUGS.md` Q4.

Three of those four were wrong in the same way: a number was compared against a
file count, and the file count lost. The disc counts **animations** and
**strings**, and both live inside files rather than being files.

The data files pin down **every constant, every level special, every scheme and
every sound mapping.** They say nothing about *algorithms*, and these are what
a disassembly would still be needed for:

- the movement and tile re-centring routine (row 2's anisotropy makes this
  non-obvious)
- flame propagation order, and the rule that flames stop on powerups
- the powerup **placement** algorithm — we have the counts, not the scatter
- AI behaviour — VALUELST holds four knobs, the logic is in the exe
- the roulette/Goldman screen
- the bomb-arc integrator that consumes `660`/`661` and `500`–`506`

`BM95.EXE` being present means these are answerable now rather than
permanently open. None of them has been looked at yet.

Note the network values `1100`–`1104` (per-protocol overdue-packet timeouts,
IPX 200 ms / modem 750 / serial 400 / TCP 400) are of historical interest only
— we are replacing the transport with WebSocket.

## 6b. The text files, which turned out to be the specification

`MESSAGES.TXT` is the original's string table, 316 entries, and it is the
closest thing on the disc to a specification for the screens. Blocks that
matter:

| ids | what |
|---|---|
| `149`–`160` | "Random Each Game", then the eleven level names |
| `208`, `209`, `211` | Wins / Kills / "%u %s to win match" |
| `220`–`224`, `230` | what a player slot can be: OFF, AI, KEY %u, JOY %u, NET, TEAM |
| `250`–`268` | the settings screen, label by label, in order |
| `280`, `281` | "Infinite" and "%u:%02u" — the play-time clock |
| `295`–`297` | Low / Medium / High, the conveyor speeds |
| `315`–`318` | None / A Little / A Lot / All the way! — the enclosement depths |
| `500`–`548` | 49 default node names, one picked at random |
| `790`, `791` | the Gold Bomberman announcement |
| `800`–`813`, `850`–`863` | fourteen powerup names, long and short |
| `900`–`928` | the statistics file's header and nineteen counters |
| `1120`–`1125` | Move Up / Right / Down / Left / Action 1 / Action 2 |

Its header is emphatic about the placeholders — *"DO NOT MODIFY ANYTHING WITH A
PERCENT SIGN (%) near it! This will CRASH THE PROGRAM!!"* — so `tools/messages.py`
preserves them exactly and `Messages.fmt()` converts C's `%u` to GDScript's
`%d` at format time rather than in the table.

`OPTIONS.BM` is that settings screen's help text, and it explains what each
option does. It is where rows 50 and 53 come from, and it names options the
simulation does not implement: **Win Matches By Kill Total**, **Gold
Bomberman**, **Random Start**, **Disable Music During Gameplay**. Those are
gaps rather than divergences, and `docs/STATUS.md` lists them.

`TOOLS/ANIMS.TXT` is the disc's guide to adding animations, and it is what
settles rows 57 and 58 — see `docs/BUGS.md` Q3 and Q4.

`BM95.EXE` (424,448 bytes) is present. Track C is no longer blocked.

## 7. Asset formats, confirmed by inspection

- **`.ANI`** — IFF-style chunks. `STAND.ANI` opens `CHFILE`, `ANI `, then
  `HEAD` (0x30 bytes), `PAL ` (0x2000 = 256×4×... palette), then per-frame
  chunks. Matches `cd_data_extractor_src/uanifile.pas`'s `TFileItem`:
  4-byte signature, `uint32` length, `uint16` id. 95 files, 7.7 MB.
- **`.RSS`** — headerless raw PCM, 22050 Hz, signed 16-bit, stereo,
  little-endian, exactly as `SOUNDLST.RES` states. Verified:
  `1000.RSS` is 226 168 B = 2.564 s. 2027 files, 428 MB. **25 of them are
  MONO** — their size is not a multiple of 4, which stereo 16-bit cannot
  produce — and 17 of those are gameplay sounds, so the channel count is
  detected per file rather than taken from the header comment. Probably more
  are mono than that test can see: `docs/BUGS.md` Q7.
- **`SOUNDLST.RES`** — a resource number and a base filename per line, grouped
  into event RANGES by its own section comments. `SOUNDLST` references 1051 of
  the 2027 files on the disc; 959 of those belong to the 36 events the port
  plays, the rest being music and menu furniture. One reference is a typo in
  the original — `ZAHPU111` does not exist on the disc, so resource 3070 is
  silent in the original game too.
- **`.PCX`** — 62 files, 10 MB, all decoded by `tools/pcx.py`: 15 screens, 11
  field backgrounds, 10 victory screens, 16 powerup icons, 9 placed elements,
  and the editor's palette swatch in `TOOLS/`. **None of them carries
  `COLOR.PAL`.** Sixty-one embed their own palette and `QALOGO.PCX` is
  greyscale with none at all, so `COLOR.PAL` belongs to the `.RMP`
  player-recolour path and not to screen drawing — which is why the port can
  convert screens to RGBA at pack time and lose nothing.
- **`COLOR.PAL`** — 33,536 bytes = **768 + 32,768**. The first 768 are 256 RGB
  triples in 6-bit VGA values; the rest is an **RGB555 → palette index lookup**,
  one byte per 15-bit colour. Verified by round trip: reduce each palette
  entry's own colour to RGB555, look it up, and **254 of 256 return their own
  index**. This is how the game gets from the `.ANI` files' direct colour to
  the palette space its remapping works in.
- **`.RMP`** — ten files, 259 bytes each: a 256-entry palette remap plus three
  trailing bytes. Each maps the same block — indices **100–169 and 172–174**,
  73 of 256 — to different values, and touches nothing outside it. That block
  is green-dominant in `COLOR.PAL`, which is why fpc_atomic's `g > r and g > b`
  heuristic approximates it.
- **`MESSAGES.TXT`** — 316 strings; see §6b. One entry, `63`, has an unclosed
  quote in the original.
- **`.FON`** — three bitmap fonts, and all three decode with the same
  layout. `FONT0.FON` was skipped for a while because its flags word is 1
  where the others are 0; that was wrong. Read in the same (width, offset)
  order, it tiles exactly — 108 of 108 glyph gaps equal `ceil(w/8) * height`,
  needing 1819 of 1819 available bytes — and renders codes 19–126: three
  fraction glyphs, two arrows, then space through tilde at 17 pixels tall.
  `flags` is not a layout switch, so `tools/fonts.py` now gates on the tiling
  test, which would actually detect a different format.
- **`.BM`** — ten text screens, not two. Beyond the credits and the manual
  there are the readme, the editor, network, options and input help, the
  roulette explanation and two out-of-memory error screens. The only markup is
  `<IMGNAME>`, placing `RES/NAME.PCX` inline; all 18 placements across the ten
  files resolve, 13 of them powerup icons in `MANUAL.BM`. Angle brackets are
  also used as prose (`<ESC>`, `<drop bomb>`), so the rule is the `IMG`
  prefix, not the brackets. `tools/bmtext.py`.
- 10 stray `.GIF` files in `SOUND/` (493×400), unreferenced — `BM95.EXE`
  contains no `.gif` string at all. They are the lead programmer's own photos
  with captions burned in, and nine are holiday snapshots. The tenth is a
  game fact: it states a hidden feature that puts his head on the character,
  entered as **Up, X, B, Left on a controller**. Not implemented in the port;
  no other source on the disc mentions it.

`ANI/MASTER.ALI` lists which ANIs the game actually loads, and its comments
settle two of AtomBomberman's claims: `flame.ani` is commented out in favour of
`mflame.ani`, and `bombs.ani` carries the note *"this one is only kept around
for the jelly bombs..."*.


## 8. The containers that were nearly missed

Six files were once excluded from the extraction on the strength of their
extension. Five of those exclusions were wrong, and the corrections are the
reason `tools/inventory.py` now treats "excluded" as a claim requiring a
measurement.

- **`INSTALL.DAT` is a compressed archive, not a manifest.** Sixteen bytes of
  header, then per member a length-prefixed name and four big-endian u32s —
  flags, offset, unpacked size, packed size. The offsets chain exactly: the
  first member starts at 609, where the table ends, each begins where the last
  stopped, and the final one ends at byte 173,802, the file's length. The codec
  is Okumura LZSS in chunks: `u16` packed length per chunk, a 4096-byte ring
  **reset per chunk and filled with 0x20**, control byte LSB-first, matches as
  12-bit offset plus 4-bit length + 3. Proof rather than plausibility:
  `FONT0.FON` and `COLOR.PAL` are in the archive *and* on the disc, and both
  come out byte-identical. The space-filled ring is what fixes a divergence at
  byte 2254 of `FONT0.FON`; the chunking is what fixes the five largest members
  decoding short.

  **Eighteen of its 22 members exist nowhere else on the disc:** `AB.PCX`
  (640x480 setup backdrop), `POINTER.PCX`, `LOGOBACK.PCX`, `LOGOBAR.PCX`, four
  more bitmap fonts in the format `tools/fonts.py` reads (`FONT2`, `FONT4`,
  `FONT5`, `FONT8` — heights 10, 17, 17, 10), five files of a **second font
  format** whose magic is `AAFF`, the installer's script and uninstaller, and
  three file lists. Two more, `FONT1.FON` and `FONT6.FON`, share a name with a
  disc file and are **different files** — the installer carries its own faces.

- **`THEME/THEME.ZIP` holds 40 pieces of original art**, not just a desktop
  theme: two multi-megabyte bitmaps, eight icons, thirteen cursors, five
  animated cursors and fourteen WAVs, none of them anywhere else on the disc.

- **`INTRO/BMINTRO.EXE` contains the game's intro movie.** An Interplay MVE
  stream at offset 0x11400: 857 chunks, 640x480, 22 050 Hz stereo 16-bit DPCM
  audio. The signature appears three times in the file and only one of them is
  a real stream, so a stream is identified by parsing to a video-mode and
  audio-init opcode rather than by the signature.

- **`TRAILER.SFA` is a second MVE**, 1 204 chunks, 640x480, 19.8 MB. It was
  described here as a trailer for another Interplay title; nothing on the disc
  supports that, and the strings inside are compressed, so the claim is
  withdrawn rather than repeated.

  Both movies are sliced out whole by `tools/containers.py` as `.mve` files.
  Their video codec is opcode-based and their audio is DPCM; ffmpeg and VLC
  read the format natively, so no decoder is written here.

- **`BM95.RES`** is a Watcom resource file — `WATCOMRC` with the high bit set —
  and it holds five real bitmaps (16x32 and 32x64 at 4 and 8 bpp, and one
  99x198), extracted as PNG.

- **`OOO_LTD.CXT`** was the one exclusion that held: a Director cast of 324
  members with 280 Lingo scripts and **no** bitmap chunks — the intro's code,
  not its art.


## 9. Two formats opened, one only half opened

- **`CIMG` type 0x0b is 8-bit paletted**, and `CLASSICS.ANI` is the only file on
  the disc that uses it — 28 frames that `tools/anifile.py` refused until now,
  leaving the decode at 94 of 95. The identification is arithmetic: the frame
  header's `uncompressed_size` is 2262 for a 39x58 frame and 39 x 58 = 2262
  exactly, one byte per pixel rather than the two type 0x04 uses, and
  `additional_size - 24` is 1032 = 8 + 256 x 4, an eight-byte header and one
  RGBA quad per index. The run/literal encoding is the same Targa datatype-10
  scheme, with the pixel shrunk to one byte. All 28 frames decode to exactly
  width x height and consume their block to within its final padding byte;
  transparency is by index, with `keycolor` naming a palette entry rather than
  a 16-bit colour. `MASTER.ALI` never loads the file, so the game never drew
  it — the decode is for completeness, and the frames are a green bomberman.
  **The disc is now 95 of 95.**

- **`.AAF` is an antialiased font format, and it is NOT cracked.** Five of them
  came out of `INSTALL.DAT` and they appear nowhere else. What is established:
  the magic is `AAFF`; the big-endian `u16` at offset 4 is the height (9, 11,
  13, 15, 19 across FONT0-4.AAF); a table of 256 eight-byte records begins at
  0x10, each `u32` then `u16` then `u16`, and the last two are plainly a width
  and a height — 'A' in FONT0.AAF is 7x8, '0' is 5x8, which matches that
  font's `.FON` twin. Records exist for codes 23 to 125, one glyph is shared by
  three codes, and the pixel bytes run 0 to 8 — nine coverage levels, which is
  what makes it antialiased rather than 1-bit.

  What is NOT established is where a glyph's pixels are. Reading the `u32` as
  the start of a `width * height` raster renders noise; so does reading it as
  the end, which the gap arithmetic suggested. Both were tried and both are
  wrong, so the data is packed or compressed in a way not yet identified. This
  is recorded rather than guessed at, and the cost of leaving it is nil: the
  AAF faces belong to the SETUP program, not to the game. The game's own
  lettering is `FONT0/1/6.FON`, which `tools/fonts.py` reads in full.
