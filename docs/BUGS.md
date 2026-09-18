# BUGS — divergences and open questions

Two kinds of entry, kept apart on purpose:

- **§1 Open questions.** Behaviour nobody has established yet. These are the
  places where the port would otherwise be guessing, and a guess presented as
  parity is the thing this file exists to prevent. Each names what would settle
  it.
- **§2 Defects.** Behaviour we have got wrong, with the test that will prove
  the fix.

The systematic ledger of where fpc_atomic disagrees with the original's own
data files is `docs/ORACLE.md` §2, not here. This file is for what neither
document settles.

_Last updated 2026-09-02, end of Phases 4b, 5, 6, 7 and 8._

---

## 1. Open questions

### Q1 — Which disease is which
**Status:** NAMES ANSWERED 2026-09-02. The duration-slot mapping is still open
and currently unobservable.

**The names come from the original.** `SOUNDLST.RES` groups its sound effects
one disease per 50 resources from 3000 to 3550 and comments each group with its
name. Twelve diseases, in resource order:

| # | resource | name | | # | resource | name |
|---|---|---|---|---|---|---|
| 0 | 3000 | molasses | | 6 | 3300 | short fuze |
| 1 | 3050 | crack | | 7 | 3350 | swap 2 players |
| 2 | 3100 | constipation | | 8 | 3400 | controls reversed |
| 3 | 3150 | poops | | 9 | 3450 | leprosy |
| 4 | 3200 | short flame | | 10 | 3500 | invisible |
| 5 | 3250 | crack poops | | 11 | 3550 | duds |

Cross-check: fpc_atomic implements five diseases and every one lands on a name
here — its `dSuperSlow` is MOLASSES, `dNoBombs` CONSTIPATION, `dEbola` POOPS,
`dInvertedKeyboard` CONTROLS_REVERSED, `dDudBombs` DUDS. Two independent
sources agreeing on five of twelve is good evidence for the list.

**What is still open.** VALUELST has only **nine** duration slots (`130`-`138`)
for these twelve, and `DISEASE.H` — which its comment points at for the
mapping — is not on the disc. `sim.disease_duration()` takes the disease index
modulo nine, and says so at the point it does it.

This is currently **exact regardless of the mapping**, because all nine slots
hold 300. It would start to matter the moment one is re-tuned, which is the
single line to revisit.

**Also open, and separate:** which diseases the ordinary DISEASE powerup draws
from and which belong to SUPER_BAD_DISEASE. VALUELST separates the two
powerups (resources 402 and 411) but never says which pool is which.
`Types.SUPER_BAD_DISEASES` puts poops, crack poops, swap-players and leprosy in
the bad pool — the ones that end a round rather than inconvenience it, which is
also where fpc_atomic put its `dEbola`. A guess, flagged as one.

**Would settle it:** `DISEASE.H`, or `BM.EXE`.

**IMPLEMENTED 2026-09-17.** Four of the twelve had been classified into the
right pool since the names were answered but never given an actual effect —
`sim.gd`'s `catch_disease()`/`_tick_diseases()` now cover all twelve:

- **POOPS** forces `Action.FIRST` every tick regardless of the player's own
  input. Sourced, not guessed: fpc_atomic's `dEbola` — its own name for this
  disease, per the five-name cross-check above — does exactly this
  unconditionally in its own tick loop, and `dEbola`'s German comment
  ("die Pupserkrankheit") is bathroom humour matching "poops" directly.
- **SWAP_PLAYERS** trades tile positions with a random other live player,
  once, on infection (`_swap_places()`). One-shot rather than a lasting
  state is corroborated by fpc_atomic's own unfinished `dSwitchBomberman`
  ("not stored, because it is never taken back") — but which of "positions
  swap" or "control swaps" is meant is this port's own reading of the disc's
  name, "swap 2 players"; fpc_atomic never finished its version either way.
- **LEPROSY** drops one held powerup onto the field per `types.gd`'s own
  enum comment, "powerups fall off as you walk" — that comment predates this
  fix and is the only source for the mechanic at all; the drop RATE
  (`LEPROSY_DROP_CHANCE`, `sim.gd`) has no resource behind it and is flagged
  as this port's own number, the same way the closing wall's ticks-per-cell
  is.
- **INVISIBLE** hides a player's own sprite from a viewer who is actually
  driving that slot (`game_view.gd`'s `local_slots` + `draw_player_of`) —
  "you cannot see yourself", not "nobody can see you", per the enum comment.
  Does not touch simulation state; every other player still sees and
  collides with them normally.

All four are judgment calls beyond what fpc_atomic's cross-reference or the
enum's own pre-existing comments state — flagged as such at the point each
is implemented, the same convention as `SUPER_BAD_DISEASES`' own pool
assignment above.

### Q2 — Two active players on one start cell
**Status:** ASSUMED and implemented, 2026-09-02. Players overlap freely.

Six of the 67 shipped schemes put more than one start slot on the same cell,
and it is clearly deliberate — the `-N` names say so. `CUNFUSED? (10)` puts
**all ten players on one square**; `TWO'S A CROWD (10)` puts two on each of
five. `FORTIFIED (4 ONLY)`, `CHAIN LINKS (4)` and `VERY EVIL (4 ONLY)` declare
all ten slots but only use four cells, so slots 4–9 stack.

Measured, with the distinct-cell count each lands on:

| Scheme | `-N` name | Cells | Max stacked |
|---|---|---|---|
| `4CORNERS.SCH` | FORTIFIED (4 ONLY) | 4 | 3 |
| `CHAIN.SCH` | CHAIN LINKS (4) | 4 | 3 |
| `CHASE.SCH` | VERY EVIL (4 ONLY) | 4 | 3 |
| `CONFUSED.SCH` | CUNFUSED? (10) | **1** | **10** |
| `DIAMOND.SCH` | UNCUT (9) | 9 | 2 |
| `ROOMMATE.SCH` | TWO'S A CROWD (10) | 5 | 2 |

The parser accepts all of it — refusing would refuse valid data — and exposes
`stacked_starts()` and `distinct_start_cells()`.

**What is implemented:** players have no collision with each other at all. Two
players on one cell simply overlap, and nothing pushes them apart; they walk
through each other for the whole round. `field.initialize()`'s start clearing is
idempotent, so ten players stacked on one cell clear the same five cells one
player would, and `tests/test_field.gd` asserts that directly.

**Why this and not a nudge:** every Bomberman in the series lets players pass
through each other, and a nudge would need a separation distance — a number that
is in no data file and that the oracle therefore could not check. Overlapping
needs no constant at all. `tests/test_sim.gd` runs a round on all 67 shipped
schemes with ten players and asserts nobody is ever inside a wall, which is the
invariant that actually matters here.

**Still unconfirmed:** whether the original really has no player-player
collision. If it turns out to nudge, the change is local to `_move_player` and
`tests/test_movement.gd` will show the diff.

**Would settle it:** `BM.EXE`, or running the original.

### Q3 — Cornerhead animation count
**Status:** ANSWERED 2026-09-02. **The count is not a file count.**

Resource `330` says **13** cornerhead animations and warns that every network
player must have exactly the same number. `original-game/ANI/` ships
`CORNER0`–`CORNER7`, which is 8 — so this looked like five missing files, and
fpc_atomic uses 8 as though that were the number.

`TOOLS/ANIMS.TXT`, the disc's own guide to adding animations, says what the
number actually counts:

> Number of Cornerhead Animations: [...] `330,(n)`. Currently this is set to 13.
> If you add a new cornerhead, it would now be 14. You should follow the naming
> convention within the `corner(n).ani` files.

An animation is a **named `SEQ ` sequence**, and one `.ANI` can hold several.
Counted:

    CORNER0  1  cornerhead 0        CORNER4  3  cornerhead 4, 5, 6
    CORNER1  1  cornerhead 1        CORNER5  2  cornerhead 7, 8
    CORNER2  1  cornerhead 2        CORNER6  3  cornerhead 9, 10, 11
    CORNER3  1  cornerhead 3        CORNER7  1  cornerhead 12

**8 files, 13 sequences, named `cornerhead 0` through `cornerhead 12`.** Exactly
resource 330. Nothing is missing from the disc.

This is also the strongest vindication of driving off the `SEQ ` chunks:
fpc_atomic ignores them, hand-authors its sheets, and therefore has to treat
the count as a file count and get 8.

**2026-09-17 — what a cornerhead IS, not just how many.** `TOOLS/ANIMS.TXT`'s
own heading for resource 330, quoted above only in part, states the purpose
outright, sitting right after the death-animation section it mirrors:

> **Number of Cornerhead Animations:**
> If your animation is that of a character getting trapped, ready to die
> you will need to add that here.

So `CORNER0`–`CORNER7` are not decoration — they are a **pre-death "trapped,
about to die" state**, distinct from the `XPLODE*` death animations and
presumably played in the moment before one, the way a `!` or gasp precedes a
death in other games of the era. `docs/STATUS.md`'s "decoration" framing and
`docs/AUDIT.md`'s matching line are both wrong and should be corrected to
this.

**What is still NOT established: the trigger.** `tools/bmexe.py --xref`
attributes `value_of(330)`'s call site to `0x41F29B`, `player_update` — the
same per-player-per-frame dispatch function Q5.4 already reads for movement
and the AI — but the actual `value_of(330)` call and whatever selects
`corner%d` is not in the ~120 instructions directly in that function; per
the same lesson Q5.4 learned twice over (`0x40A76E`/`0x40B046`, then the AI's
own search), `bmexe.py`'s function-length and `--xref` attribution both walk
only to the next DIRECT call target, so an indirectly-reached or
deeper-nested sub-function's own resource reads get attributed to whichever
function calls it. The real trigger is in a function `player_update` calls,
not read yet.

**A reasonable guess, not implemented**: the closing wall's crush
(`sim.gd` `_advance_hurry()`, "anyone standing there is crushed") is
exactly "a character getting trapped, ready to die" already modelled in
this port — a player who cannot escape the wall in time. It is a plausible
trigger. It is not a read, and this port's own rule (docs/BUGS.md's
running theme) is not to wire a mechanic to an invented condition and call
it sourced. Left for the next pass, which should find `player_update`'s own
call to whatever reads resource 330 before writing any trigger code.

**`APPLBITE`, `NUCKBLOW` and `ZEN` are a separate, still-unexplained
family** — not the same thing. Checked this session: neither name appears
anywhere in `original-game/TOOLS/ANIMS.TXT` or any `.BM` text file, and
their own dimensions (73×73, matching `XPLODE1`/`XPLODE3`/`KFACE`/
`HEADWIPE`'s "big head" format) do not match `CORNER0`-`7`'s 110×110 at all
— two different sprite families that happen to sit in the same "still not
packed" bullet, not one. `docs/BUGS.md`'s "still not done" list and
`docs/AUDIT.md` should describe them separately from cornerhead rather than
as one item, since they are not established to be related and nothing found
this session connects them.

### Q4 — Death animation count
**Status:** ANSWERED 2026-09-02, the same way as Q3.

Resource `105` says **24**. `ANI/` has `XPLODE1`–`XPLODE17`. Counting `SEQ `
sequences instead of files:

    XPLODE1..9    1 each   die green 1..9
    XPLODE10      3        die green 10, 11, 12
    XPLODE11      3        die green 13, 14, 15
    XPLODE12      1        die green 16
    XPLODE13      1        die green 17
    XPLODE14      3        die green 18, 19, 20
    XPLODE15      2        die green 21, 22
    XPLODE16      1        die green 23
    XPLODE17      1        die green 24

**17 files, 24 sequences, named `die green 1` through `die green 24`.** Exactly
resource 105. The `ani.zip` expansion this was blocked on is not needed, and
fpc_atomic's README claiming `xplode18.ani` comes from it is a red herring —
`die green 18` is the first sequence inside `XPLODE14`.

### Q6 — Per-player colour remapping
**Status:** ANSWERED and implemented from the disc's own tables, 2026-09-02.
All ten player colours render. The transform was fpc_atomic's heuristic until
`0.RMP`-`9.RMP` and `COLOR.PAL` arrived; it is now the original's, applied as a
ratio so the art keeps its 15-bit depth. `docs/PLAN.md` Phase 13.

Every actor sprite on the disc is authored in ONE colour — the ANI sequence
names say so outright: `bomb regular green`, `flame center green`,
`die green 5`. The game recolours per player.

**What the data gives us.** VALUELST resources `200`-`247` hold the ten target
colours, three consecutive resources per colour, five apart between colours,
components 0..100 (ORACLE §3). Its own comment reads *"color remaping default
values (RGB pairs, from 0 to 9 of the .RMP files)"* — so a `.RMP` is keyed to a
target RGB and we have all ten targets.

**What the data did not give us at the time**, both recorded so they were not
re-explored:

- The `.RMP` files themselves were not in the copy of the disc we had.
- Each `.ANI` carries a **`TPAL` chunk of 1028 bytes** — 4-byte header plus 256
  four-byte entries, exactly the shape of a remap table. It is **1024 bytes of
  zeros in every one of the 95 files.** An empty reserved chunk, not a palette.

**THE FIRST OF THOSE IS NO LONGER TRUE.** `0.RMP` through `9.RMP` arrived with
the rest of the install on 2026-09-02, along with `COLOR.PAL`, and between them
they contain the original's actual transform. Measured:

- **`.RMP` is 259 bytes**: a 256-entry byte map plus three trailing bytes. The
  mapped entries are palette indices **100–169 and 172–174** — 73 of 256 — and
  every one of the ten files maps the same block to different values. Nothing
  outside that block is touched.
- **`COLOR.PAL` is 33,536 bytes = 768 + 32,768.** The first 768 are 256 RGB
  triples in 6-bit VGA values; the remaining 32,768 are an **RGB555 → palette
  index lookup**, one byte per 15-bit colour. The proof is a round trip: take
  each palette entry's own colour, reduce it to RGB555, look it up, and **254
  of 256 come back to their own index.**
- The mapped block is the green ramp. Indices 100–108 are `(32,49,48)`,
  `(5,48,45)`, `(14,30,27)`, `(9,61,45)` … — green-dominant, every one. So
  fpc_atomic's `g > r and g > b` predicate is an **approximation of exactly
  this block**, which is why it measures so well on the real art (below) and
  why it is not the same thing.

**IMPLEMENTED 2026-09-02, and not as a straight lookup.** Measuring it first
turned up something that changes what "exact" means here:

**The `.ANI` art is not palettised.** `WALK.ANI` uses **978 distinct colours
and 24 of them are palette entries.** So `COLOR.PAL`'s 32 KB table is a
nearest-match QUANTISER — the original reduced its 15-bit art to 256 colours
for an 8-bit display and remapped the indices afterwards. Writing
`palette[mapped]` would reproduce that quantisation faithfully and throw away
colour the port already has, which is fidelity to the display hardware of 1997
rather than to the game.

So the tables decide the CHANGE and the pixel keeps its detail:

    i   = lut[rgb555(pixel)]      the nearest palette entry
    if remap[player][i] == 0: unchanged      (0 IS "not remapped" — no
                                              separate block test is needed)
    S   = palette[i]             what the disc thought the pixel was
    T   = palette[remap[player][i]]
    out = pixel * (T / S)        ratio, or additive where S is near zero

`tools/remap.py` measures all three candidates over the 54,385 recoloured
pixels of `WALK.ANI`, as mean absolute per-channel difference:

| player | heuristic vs disc | this vs disc |
|---|---|---|
| 0 white | 11.6 | 10.8 |
| 1 grey | 20.4 | **5.1** |
| 2 red | 9.3 | 6.6 |
| 3 blue | **30.0** | **7.6** |
| 4 green | 7.6 | 7.5 |
| 6 cyan | 25.6 | 9.6 |
| 9 violet | 20.6 | 7.3 |

and on the 17,551 of those pixels whose colour IS a palette entry — where the
disc's transform is exactly defined — this sits **0.03 to 2.61** away, which is
6-bit rounding. The heuristic is a good approximation for red and green and
visibly wrong for blue, cyan, grey and violet.

**Two independent sources on the disc agree**, which is worth recording:
`tests/render_recolour.gd` asserts every player renders nearer its own VALUELST
`200`-`247` target than any other player's, and that still passes with the
`.RMP` tables driving the recolour instead of those targets.

**Verified pixel for pixel.** `tests/render_shader.gd` feeds the shader a strip
of 62 real art colours — half exactly palette entries, half not — reads the
rendered strip back, and compares every pixel against the same transform
computed independently in GDScript from the same three tables. Worst deviation
**0 to 1 out of 255** across three players.

**What is implemented** is fpc_atomic's `LoadColorTabledImage`, ported to a
shader. For each pixel where green dominates (`g > r` and `g > b`):

    n   = (r + b) / 2        the neutral base
    k   = g - n              how far above it the green sits
    out = n + k * target     then divided by its max if any channel overflows

Pixels where green does not dominate are left exactly as authored.

**Why that predicate is well-founded**, measured on the real art rather than
assumed: 75% of a bomberman is green-dominant and the remainder is pure grey —
the helmet, visor and outline all have `r == g == b`, so the test skips them.
92% of a bomb is green and the other 8% is its yellow lit fuse. 90% of a flame
is green and the rest is black outline. The transform touches what should
change and nothing else.

**The heuristic is kept**, on `exact_remap = false`, because a replacement art
pack (`docs/PLAN.md` track B) will have no palette to look anything up in. It
is also what `AB_EXACT_REMAP=0` selects, which is how the comparison
screenshots were made.

**Still open, and small:** the two predicates agree on 95.6% of actor pixels,
so 4.4% are recoloured by one transform and not the other. Which is right for
those is not established — they are pixels the disc quantises into the block
that are not green-dominant, or the reverse.

### Q7 — How many `.RSS` files are actually mono
**Status:** partly settled; the remainder is open. Low impact.

25 of the 2027 sound files have a size that is not a multiple of 4, so they
cannot be stereo 16-bit and are certainly mono. 17 of those are gameplay
sounds. `tools/rss.py` detects and converts them correctly.

The test is one-directional: a mono file whose length happens to divide by 4 is
indistinguishable by size. There is measured evidence that some do —
`BMDROP2` and `BMDROP3` both show a left/right correlation of exactly 1.000
while their channels are equal in under 2% of frames, which is what consecutive
samples of a single stream look like, not two channels. A genuinely
mono-in-stereo file such as `MENUEXIT` instead has L == R in 100% of frames.

So some files are probably being converted as stereo at half their intended
pitch.

**Phase 9 update.** Sound is wired up and the pack ships 83 of them, so this is
now audible rather than theoretical. It did not block the phase: a file played
at half pitch is a wrong-sounding effect, not a broken one, and every affected
name is known. Settling it needs `BM.EXE` or an ear, and an ear is cheaper —
the 25 certain-mono files are the place to start listening, because if the
detector is right about those it is probably wrong about few others.

**Would settle it:** `BM.EXE`, or listening.

### Q8 — How the original's mixer behaves when all five voices are busy
**Status:** ANSWERED 2026-09-02 from `BM95.EXE`. **Both guesses were wrong**,
and the port now does what the binary does.

`play_sound` is at **0x427961** and the voice gate at **0x427859**.

**1. Every raised sound is played.** There is no per-tick collapsing anywhere.
A chain of eight bombs asks eight times.

**2. The take is random among the LEAST-USED.** There is a per-sound use
counter table at 0x463088, and:

    best = min(uses[n .. n+count-1])
    for (200 tries) { pick = n + rand() % count; if (uses[pick] == best) break }
    play(names[pick]); uses[pick]++

A shuffled deck: every take is heard once before any repeats, and within the
tied set the choice is random. The port did round-robin, which gets the first
half of that right and the second wrong. The counter is incremented **even when
the sound is refused for want of a voice** — `uses[pick]++` sits after the gate
call and is not conditional on it — which is reproduced.

**3. A full mixer drops the NEW sound**, at 0x427859:

    mov eax, 8 ; call value_of      ; the cap, 5
    cmp eax, [0x46307C]             ; against the live count
    jl  exit                        ; cap < live -> play nothing at all
    ...start it...
    inc dword [0x46307C]

Not "evict the oldest". And note the comparison: it admits while `live <= cap`,
so with resource 8 at 5 there can be **six** live at once. That is the
original's own off-by-one; the port reproduces it and sizes its voice array at
cap + 1, because sizing it at 5 would drop a sound the original plays.

**4. The group ends at the first GAP** in the numbering, not at the end of the
range the comments describe:

    count = 0; i = soundno
    while (i < total && names[i] != 0) { count++; i++; }

which strands 172 sounds the original never plays — see the correction below.

`rand()` is at **0x45190A** and is the ANSI LCG: `state = state * 0x41C64E6D +
0x3039`, returning bits 16..30, so `RAND_MAX` is 32767. "One of the three below
randomly", which is what SOUNDLST says about the Hurry tiles, is `rand() % 3`
over a use-counted deck rather than a uniform draw.

**What the two wrong guesses were, and why they were reasonable.** Kept because
they shaped the code for a phase, and because each was a correct observation
about audio that happened not to be what the original did:

- *"A full mixer drops the oldest"* — refusing the new sound makes the
  explosion that just killed you inaudible behind five taunts from the last
  death, and the taunts are the long files, 140 KB against a bomb drop's 25 KB.
  That effect is real and the original simply has it.
- *"One sound per event per tick"* — eight copies of one file 0 ms apart is one
  explosion eight times as loud with comb filtering. Also true, and the
  original avoids it a better way: by playing eight *different* takes.

Measured pressure on the cap, which is why the question mattered at all: eight
bots over 30 s played 167 sounds and 57 of those found every voice busy. A
third of everything the game says is competing for a voice.

**Still open, and much smaller:** nothing read so far ever RESETS the use
counters, so a long match walks the whole deck repeatedly. Where they are
cleared — round start, the cache flush at resource 7's 1800 seconds, or never —
is not established.

### Q9 — Does a match ever change level between rounds?
**Status:** ANSWERED 2026-09-02. **Yes, and it is a menu option.**

The question was asked when the level list had no way to say anything but a
number. `MESSAGES.TXT` 149 is the entry that was missing:

    149,Random Each Game
    ; names of the various levels defined
    150,Green Acres

So "Random Each Game" sits at the head of the level list, which is also what
the lockout array at `1150`–`1161` is FOR — it exists to keep two levels out of
random selection, with the developers' reasons attached. A list of what may be
chosen only makes sense if something chooses.

**Implemented.** `Match.random_level` derives each round's level from that
round's seed rather than rolling it, so the server and every client compute the
same one and a whole match still replays from its first seed. The mechanism the
question was about — the level travelling in `S_MATCH` and the client rebuilding
its static geometry — is now exercised by real packets rather than only by
`tests/test_net.gd` driving it directly.

Resource `35` is **11**, not 35: 35 is the resource number. Corrected below.

### Q10 — The flame centre and an arm can be half a pixel apart, and it is not a rounding bug
**Status:** measured 2026-09-17, root cause proven, not fixed further. Low
visual impact, high investigation cost — recorded so it is not re-chased.

Reported three times live as "the explosion's top piece doesn't line up with
the centre," after two rounds of fixes to `game_view.gd`'s flame-piece
centring (an inbound-edge-flush fix for `flame tipeast green`'s undersize,
then a floor-before-round fix for a tie-breaking asymmetry). Both fixes were
real and are still correct — and neither was the whole story.

**Measured from the actual loaded pack**, not assumed: `flame center green`
is a constant 41 px wide at every animation age. `flame midnorth green`'s
five frames are **22, 27, 22, 24, 25** — even, odd, even, even, odd. Centring
a 41 px (odd) sprite in this port's 40 px (even) cell always leaves a `.5`
px remainder no matter which way it rounds; centring an even-width sprite in
the same cell leaves no remainder at all — there is no tie to break. So on
the two ages where north's width is also odd (27, 25) the two pieces' parities
match and they land pixel-exact; on the other three (22, 22, 24) they are
mechanically **0.5 design pixels (≈1.5 device pixels at this project's
default 3x integer scale) apart**, for 3 of every 5 animation frames. This is
a property of the extracted art's own frame widths, not of the rounding
function — floor, round and ceil were all checked algebraically and every one
produces the identical result: whichever piece's width shares the cell's own
even parity centres exactly, and whichever does not is 0.5 px off, forever.

**Would need one of two real fixes, neither attempted here:** sub-pixel
(unsnapped) drawing for flame pieces specifically, which risks every other
sprite's pixel-art crispness for one sequence's sake and was not attempted
without more testing; or repadding MFLAME's frames by one pixel in the
extraction pipeline (`tools/anifile.py`/`tools/pack_assets.py`) so every
sequence shares one width parity — a content change to a generated,
gitignored asset, not a renderer change, and out of scope for the pass that
found this.

**Would settle it:** either fix above, tried and pixel-measured against a
live screenshot the way this was found.

### Q5 — The four algorithms the data cannot express
**Status:** open, but no longer blocked, and now LOCATED. `BM95.EXE` arrived
2026-09-02 and `tools/bmexe.py` maps it.

`VALUELST.RES` pins every constant and describes no algorithm. What changed is
that every constant is now a **pointer into the code**: one function,
`value_of` at **0x412135**, serves every tuning value by number, so the
resource numbers `docs/ORACLE.md` already explains are a cross-reference to the
code that consumes them. `tools/bmexe.py --xref` prints it.

Where each of the four lives:

1. **Movement and tile re-centring — READ, 2026-09-03.** The walk is
   `0x41EC84`, called from the player update `0x41F29B`. In full:

       move_step(p):
         if p[+0x74] <= 0: return                  ; no movement budget
         p.vx = p.vy = 0                           ; +0x24, +0x28
         if p.dir(+0x2c) == -1: return             ; standing still
         p.dir = p.requested_dir(+0x2e)            ; the input is committed here
         ox = offset_in_cell_x(p.px)               ; 0x426599
         oy = offset_in_cell_y(p.py)               ; 0x4265EB
         along = ox*dx[dir] + oy*dy[dir]           ; along the way you are going
         perp  = oy*dx[dir] - ox*dy[dir]           ; across it
         ahead = tile + (dx[dir], dy[dir])

         if along == 0 and p[+0x59] and bomb_at(ahead) and open(ahead + dir):
             kick that bomb                        ; 0x424708

         if along < 0 or open(ahead):
             ; FREE TO WALK, and the step is DIAGONAL while off-centre:
             v = (dx[p+0x2a], dy[p+0x2a])
             side = dir            if perp == 0
                    (dir + 1) & 3  if perp < 0
                    (dir - 1) & 3  if perp > 0
             v += (dx[side], dy[side])
             p.dir = side                          ; the sprite turns as it slides
         else:
             ; BLOCKED AHEAD
             if perp < 0 and open(tile + (dir-1)&3)
                        and open(tile + (dir-1)&3 + dir):
                 v = (dx[(dir-1)&3], dy[(dir-1)&3])     ; round the corner
             elif perp > 0 and open(tile + (dir+1)&3)
                          and open(tile + (dir+1)&3 + dir):
                 v = (dx[(dir+1)&3], dy[(dir+1)&3])
             elif perp == 0 and along > 0:
                 v = (dx[(dir+2)&3], dy[(dir+2)&3]) * along   ; pushed back to
                                                              ; the cell centre
         p.px += v.x; p.py += v.y

   Three things follow that the port does differently, and they are listed as
   knowing differences in `docs/AUDIT.md` §3 rather than fixed here — movement
   is the one part of the simulation every other part and the network hash
   depend on, so it is a phase of its own:

   * **The original's step is diagonal.** Off-centre in a lane, it moves along
     AND sideways in the same tick. The port re-centres first
     (`_recentre_x`/`_recentre_y`) and then moves along, at full speed on each,
     which is the same intent in two phases.
   * **Corner rounding needs TWO open cells** — the one beside you and the one
     diagonally ahead — before the player is turned sideways. The port decides
     cornering from its collision box instead.
   * **Walking into a wall dead-centre pushes you BACK to the cell centre** by
     `along` units. The port simply stops flush against the wall.

   Unresolved: `+0x2a`, a second direction field the base step is taken from,
   distinct from `+0x2c` (current) and `+0x2e` (requested).
2. **Powerup scatter — READ, 2026-09-03.** The second half of `0x4258E5`:

       for kind in 0..12:
           n = value_of(400 + kind)
           if <generated level> and kind == 12: n = 0
           forced = n >= 0
           n = abs(n)
           for each of n units:
               if not forced and rand() % 10 != 0: continue
               for 200 attempts:                    ; 0xC8, and then it gives up
                   x = rand() % width; y = rand() % height
                   if cell_at(x, y) != 2: continue  ; must be a brick
                   if object_at(x, y): continue     ; with nothing under it
                   put the powerup there; break

   **A NEGATIVE count means "1-in-10 each"**, which the port already reads out
   of the resource's own comment — 408, 409, 411 and 412 are negative. What
   differs is the sampling: the original throws darts at the whole field and
   gives up after 200 misses, so on a sparse map it can place FEWER than the
   table asks for; the port picks from a list of brick cells without
   replacement and always places what it can. Also in `docs/AUDIT.md` §3.
3. **Flame propagation order — READ AND ADOPTED, 2026-09-03.** `0x423FA4` to
   `0x424287`, inside the per-frame object update. The arms are walked ONE AT A
   TIME in the direction table's own order — **up, right, down, left**
   (`0x45BECC`/`0x45BEDC`) — each to its end before the next begins, and the
   epicentre is written once per direction rather than once per bomb (four
   identical writes; `make_flame` at `0x426FCC` memsets the cell record first,
   so they are idempotent). Each arm stops on, in this order of test:

       a bomb      NO flame on that cell. The bomb is given this bomb's owner
                   (+0x3E) and told not to fire back down the arm that lit it
                   (+0x38 = (d+2)&3, written by 0x423209), and the arm ends —
                   the lit bomb paints that cell as its own epicentre.
       a powerup   destroyed, arm ends
       cell == 1   a solid wall: no flame, arm ends
       cell == 2   a brick: flame type 9, the global brick counter at
                   0x4642B8 is incremented, arm ends

   The port did the opposite on the first of those — it painted the cell and
   carried on through the bomb — and had a test asserting it. Both are fixed;
   `tests/test_bomb.gd` now asserts the binary's behaviour, including the
   reciprocal-arm block, and `scripts/sim/bomb.gd` has the `blocked_dir` field
   the original keeps at +0x38.

   That brick counter is a nice corroboration of something else: it is
   statistic 917, "Bricks Destroyed".
4. **AI.** Read out — see below.

**What is established about the AI:**

- **Entry: `0x40A1C6`, called once per player per frame from `0x41F29B`**, the
  player update. So the AI is not a separate task; it is a branch of the same
  per-player update that moves a human.
- **Personality is chosen once at round setup.** `0x40A140` reads resource
  `900` and is called from `0x410F81`, the round setup, not per frame.
- **`0x40A59D` is the walkability test, and it is fully read:**

      ai_cell_is_open(x, y):
          if bomb_at_tile(x, y):   return 0      ; 0x422E48
          if cell_at(x, y):        return 0      ; 0x425FB9, 1 out of bounds
          if cell_query(x, y):     return 0      ; 0x42708D, 0 out of bounds
          return !influence_get(x, y)            ; 0x424D37 (see below)

  So **a bomb blocks the AI**, which the port's `ai.gd` also assumes, and the
  two grid queries disagree about what lies outside the field — one reports
  blocked, the other clear. That only works because the blocking one is tested
  first, which is the kind of thing a reimplementation gets wrong by tidying.
- **The object table `0x422E48` walks is 100 records of 152 bytes**, pixel x at
  +0x1C, pixel y at +0x20, a state word at +0x2E tested against 2 and 3. A
  hundred is a real cap the port does not have.

**The whole decision order is now read — and the search question is answered
the other way round from the first pass at it: the AI does run a bounded
breadth-first search, over an influence map.** The dispatch below stands as
written; the correction and the machinery it found are at the end of this
entry. `0x40A1C6` dispatches every frame
through an indirect call — `call dword ptr [edx]` at `0x40A404` — into a table
at **`0x45BA78`** (DGROUP, static data, dumped directly): 8 function
pointers then a null terminator. Tried start to end, first to return non-zero
("I acted") wins; running past the null just falls through to the tail
(tile-x/y bookkeeping) rather than panicking — the
`"unknown AI personality type: %u"` panic sitting just above the loop guards a
*different*, earlier check (the personality index itself against resource
900's count), not "no handler matched". **Table order is the true priority
order**, and it does not match memory order — an earlier version of this
entry read `0x40A994`/`0x40B594` as handlers by walking memory instead of the
table; both are internal helpers a table entry calls, not table entries
themselves. Corrected map, in table order:

      idx  addr       ins  what it does
      0  0x40BD44    63   read in full. Gate: byte +0x5c zero -> not handled.
                          If dword +0x94 is non-zero, clear +0x38 and +0x36
                          and report handled. Otherwise bomb_at_tile() on the
                          actor's OWN tile, and if that bomb's owner word
                          (+0x3e) is the player's own, 1-in-2 to set +0x38,
                          clear +0x36 and report handled. +0x38 is the same
                          byte table entry 4 sets to drop a bomb, so this
                          reads as pressing the bomb key while standing on
                          one: the remote trigger.
      1  0x40BE02    75   gate: byte +0x5b (kick-capable?). 1-in-4 chance;
                          scans the 4 adjacent cells with bomb_at_tile(); on a
                          hit, faces that direction (+0x2e) and sets +0x39/
                          clears +0x37. Reads as "kick an adjacent bomb".
      2  0x40B20F   246   read in full — the routing entry, and the ONE
                          place the AI searches. influence_get() on the
                          actor's own tile picks which half runs.
                          NON-ZERO (standing in danger): if a destination is
                          already latched (word +2), route to it with
                          ai_search_route (0x4092A1); otherwise choose one
                          with ai_search_safest (0x40970B) and latch it into
                          +4/+6 with its influence in +8. Either way the
                          returned direction+1, minus 1, becomes the facing
                          (+0x2e) and ai_cancel_blocked_dir() vets it; the
                          entry reports handled unless the facing came back
                          -1.
                          ZERO (safe): if bytes +0x5f and +0x5b are both set,
                          1-in-10 to set +0x39; then walk the 4 adjacent
                          cells with ai_cell_is_open() — the first open one
                          clears the latched destination and reports NOT
                          handled; if none is open, clear it and report
                          handled.
                          Two leftover debug strings guard the 0..3 range
                          check on the facing: "FOUND IT MOTHERFUCKER (1)!"
                          (0x458BE5) and "(2)!" (0x458C00), each followed by
                          exit(0x69).
      3  0x40AD8D   116   reads resource **915 AI_BLAST_BRICK_CHANCE** twice
                          via value_of(); cell_at() and two state-flag gates
                          (word +0x34 == 9, byte +0x86). Matches ai.gd's own
                          comment for 915: "the chance of running the blast
                          bricks routine, 1-in-N" — maybe-blast-a-brick.
      4  0x40ABED   128   read in full. Three gates, then a throttle.
                          0x4245DA counts the player's live bombs and must
                          come back under byte +0x56, its bomb allowance. The
                          Manhattan distance in tiles between the actor and
                          the pixel pair at +0x14/+0x18 must be at least 3
                          (0x451E6D is abs(); which entity that pair belongs
                          to is not pinned down). Then the 5-cell plus shape
                          — tables 0x45BAB0/0x45BA9C, (-1,0) (0,-1) (0,0)
                          (0,1) (1,0) — is scanned with 0x421CB5 for an
                          object, with the player's own list link (+0) nulled
                          across the call so it cannot find itself. On a hit:
                          if team play is on (global 0x464964) and the
                          target's team byte (+0x54) matches, refuse
                          outright; else, if 0x423188 permits a bomb here,
                          1-in-5 to set +0x38 and clear +0x36.
      5  0x40BAF5   167   reads resource **920 AI_POWERUP_RADIUS** at three
                          call sites; ends with ai_cell_is_open(0x40A59D).
                          Matches ai.gd's own priority-2 step almost exactly:
                          take a nearby powerup if it can be reached safely.
      6  0x40B8C2   161   calls 0x422718, checks a type/state field against 1,
                          tile_x/tile_y, ends with ai_cell_is_open(). Sits
                          right after and calls into 0x40B594 (see below) —
                          this is the real "flee danger" table entry; 0x40B594
                          is its own-bomb-detection/scoring helper, not a
                          separate priority step.
      7  0x40A81F   117   no resource read, no gate — always evaluated last,
                          the catch-all. Keeps a persisted facing (global
                          +0x40); 1-in-25 chance per tick to reconsider, biased
                          toward a stored "target" field (+0x3e); commits the
                          new facing only if ai_cell_is_open() on it; if even
                          the current facing is blocked, re-rolls a random
                          facing and reports NOT handled (fine — it is last,
                          so the loop just falls through to the tail).
                          "Wander with a persisted, occasionally-reconsidered
                          direction", not "walk toward the nearest goal".

  Two shared helpers, called by entries above rather than being entries
  themselves:

      0x40A76E   57 ins   ai_cancel_blocked_dir(player) — 1-cell lookahead:
                          reads the player's chosen direction (word +0x2e,
                          range-checked 0..3), tests the one cell ahead with
                          cell_query(), and on a block writes -1 into that
                          field and two global state fields. No resource read.
      0x40B046  137 ins   ai_score_flee_dir(x, y) — for each of the 4 cardinal
                          directions (table (0,1,0,-1)/(-1,0,1,0) at
                          0x45becc/0x45bedc — no diagonals), walk outward
                          distance 1..9, incrementing that direction's open-
                          cell count each step cell_at() reports clear (+2
                          more if a perpendicular neighbour is also open, a
                          corridor-width bonus) and latching a blocked flag
                          the first time it is not. Returns the direction with
                          the highest count. This is the entire "search" found
                          anywhere in the AI: four independent straight rays,
                          radius 9, no queue, no visited set, no propagation
                          across the grid. Called from exactly one place,
                          0x40B594, itself only reached from table entry 6.

  `0x40A76E` and `0x40B046` were previously on record as 592 and 1069
  instructions and as the readers of resources 915/920 — both wrong, and both
  wrong the same way: `tools/bmexe.py`'s function-length and `--xref`
  containing-function both walk to the next *direct* call target, and every
  one of the 8 real table entries above is reached only *indirectly*
  (`call dword ptr [edx]`), so that walk silently swallowed one or more of
  them. All corrected in `tools/bmexe.py`'s `KNOWN` table this session.

  **CORRECTION, made the same session as the entry above.** What stood here
  said the AI has no whole-field search anywhere, on the evidence that no
  function in the `0x40A1C6`..`0x40BD44` cluster allocates a field-sized array
  or contains a queue push/pop, and that no stack frame there exceeds 0x148
  bytes. Every one of those measurements is still true. The conclusion drawn
  from them was wrong, for one reason: **the search is not in that cluster.**
  Table entry 2 (`0x40B20F`) — one of the three handlers that pass had not
  transcribed — calls down into `0x409xxx`, below the range that was scanned,
  where a breadth-first search and all of its apparatus live:

      0x40970B  ai_search_safest(x, y, limit, &dir, ...)     387 ins
      0x4092A1  ai_search_route(x, y, tx, ty, limit, &dir,
                                &rounds, &peak)             337 ins, ret 0x10
      0x4091A0  ai_marks_clear()     memcpy 0x640 B, 0x45E724 -> 0x45E0E4
      0x409083  ai_marks_get(x, y)   1 outside the field
      0x40902A  ai_marks_set(x, y,v) walkers stamp direction + 0xA
      0x4091C9  ai_walk_alloc()      first free of 100 x 24-byte records
                                     at [0x45ED68], memset to 0

  **The shape of it.** Both searches are the same flood; they differ only in
  what stops them. A "walk" is a 24-byte record: active flag at +0, x at +4,
  y at +8, **the direction it first stepped in at +0xC** — which is the value
  the search returns — its current direction at +0x10, and a step/wait counter
  at +0x14. Four walks are seeded, one per cardinal neighbour (`0x45BECC` /
  `0x45BEDC` = up, right, down, left; no diagonals, and `"can't make initial
  4 walks!"` if the pool is dry). Then each round advances every live walk one
  cell, stamps the cell behind it with its origin direction + 0xA, and clones
  it to either side; which side is tried first is one coin flip per search
  (`rand() % 2 * 2 - 1`). A walk dies when the cell ahead is already stamped,
  which is what makes this a breadth-first frontier and not a flood that
  revisits. The frontier is capped by the 100-node pool (`"can't clone to the
  side"` on exhaustion), the depth by the `limit` argument — **20** at both of
  table entry 2's call sites, on a field 15 cells wide and 11 tall, so in
  practice the pool binds before the depth does. The mark grid is 20x20
  dwords, restored from a template rather than zeroed.

  **What it searches over is not the tile grid.** It is an **influence map**:
  `0x424D37` reads `[0x4621F4][y * width + x]`, one int per cell, and its own
  panic string is `"Influence size"` (0x45A2FE), beside `"GET (%u,%u) - "`.
  `0x424DFE` is the matching setter, `"SET (%u,%u) - "`. `0x40970B`'s goal
  test is `influence_get(cell) < best so far`, and an influence of exactly 0
  ends the search where it stands — "walk to the least dangerous cell you can
  reach, and stop at the first perfectly safe one". `0x4092A1` instead stops
  when a walk arrives at the destination it was given, and returns that
  walk's first step. Table entry 2 runs the first only when the actor's own
  cell has a non-zero influence, which is why the whole apparatus is invisible
  to a bot standing somewhere safe.

  **What the numbers in the map mean — read the same session.** Five call
  sites write it (`0x424DFE`), and together they make it a "when will this
  cell burn" field, low = safe:

      0x4242DE  a bomb's own tile      (bomb +0x42 >> 16) + 100
      0x4243B7  that bomb's four arms  the same value, walked out to the
                bomb's power (byte +0x4c), stopping at a wall (cell_at) or
                another bomb (bomb_at_tile), one cell per step
      0x426E29  a live flame cell      1000
      0x42703A  the same, second path  1000
      0x4269F8  ahead of the closing   value_of(910) * 10 + 100, decaying by
                wall, one cell per     10 per cell over value_of(910) cells
                step                   — 250 down to 100 at the default 15

  So `+0x42 >> 16` is the bomb's remaining fuze, and a cell's influence is
  essentially **how soon fire arrives there**, with 1000 meaning "it is on
  fire now" and 0 meaning "nothing is coming". `ai_search_safest` minimising
  it, and stopping dead at 0, is therefore exactly "walk to the cell the fire
  reaches latest, and stop at the first one it never reaches". The map is
  cleared once per generation inside the span the tool attributes to
  `0x42331C` (`memset` at `0x423355`, guarded by `0x462210` against
  `0x464994`) — that span certainly contains more than one real function, for
  the reason given above, so treat `0x42331C` as an address to look near
  rather than a function name.

  This also settles what resource **910** does. `ai.gd` calls it "how far
  ahead the fire-god is treated as a threat", from the name alone. It is the
  literal length, in cells, of the influence gradient stamped ahead of the
  closing wall, and simultaneously that gradient's height: `910 * 10 + 100`
  at the near end, minus 10 per cell.

  **Corrected picture: the AI is an influence map plus a bounded
  breadth-first search over it, wrapped in an 8-slot priority table of local
  reactions.** `ai.gd` is closer to the original than the previous reading
  concluded — the port searches a distance field where the original searches
  an influence field, and it has no equivalent of the cloning-walker frontier
  or its 100-node cap, but "breadth-first from the player, take the first step
  of the best route" is the original's mechanism too, not a port invention.
  What is genuinely different is *when*: the original searches only from table
  entry 2, only when standing in danger or already holding a destination. The
  other seven entries really do look no further than their own tile, the 4
  adjacent cells, or — entry 6 — a radius-9 ray.

  The lesson for the tool is the same one as `0x40A76E`/`0x40B046`, one level
  up: `tools/bmexe.py` reaches only direct call targets, every one of these
  functions was found by following an indirectly-dispatched handler by hand,
  and **an absence measured inside a chosen address range is not an absence.**
  The `~19` rand() call figure quoted before is unchanged for the handlers,
  but is not the whole AI's: each search takes one more.

  **Handlers 0, 1 and 4 implemented in `ai.gd`, 2026-09-17**, closing three of
  the gaps this entry used to leave silent rather than fixing. Not a claim
  that the whole 8-slot table is now the port's shape — it is still a linear
  6-step list, not table dispatch, and entries 2/6 stay the disclosed
  simplification above.

  - **Entry 0, remote trigger.** A bot standing on its own live triggered
    bomb now has a 1-in-2 chance to press it — `ai.gd` step 0. The original's
    own press is the bomb-drop byte; the port's SECOND action is what a human
    uses to detonate a trigger bomb (MANUAL.BM), and pressing it fires every
    triggered bomb the player owns rather than only the one underfoot. Kept,
    and named as broader than the original's single-bomb read.
  - **Entry 1, kick.** A bot with the kick powerup now has a 1-in-4 chance to
    walk into an adjacent bomb at rest — `ai.gd` step 1, scanning the four
    cells in the original's own up/right/down/left order. The port has no
    separate kick button (kicking is automatic on walking into a bomb,
    `sim.gd` `_move_player`), so "face that direction" is done by moving
    that way.
  - **Entry 4, bomb an enemy, corrected shape.** This used to be a
    flame-length-scaled cross with no probability roll — a different rule
    from the original's, not an approximation of it. Now a fixed 5-cell plus
    at Manhattan distance <= 1 from the bot (not scaled by `flame_len`,
    matching the original's own literal offset table), gated on a 1-in-5
    roll. **One gate is a judgement call, not a read:** the original's
    Manhattan-3 distance check is against "the pixel pair at +0x14/+0x18",
    which the disassembly could not identify. It cannot be the enemy the
    plus-shape scan finds — that scan is fixed at distance <= 1, so >= 3
    can never hold for the same target — so it must be something else. The
    port reads it as the actor's own most recently placed live bomb (using
    `sim.bombs`, no new persisted field, no netcode consequence): don't
    queue another attack while one you already dropped sits within three
    tiles. `ai.gd`'s own comment at the call site carries the same
    reasoning; `tests/test_bots.gd` covers both the shape and the gate.

  **Still not attempted:** entries 2 and 6's own mechanism (the cloning-walker
  BFS pool, the four-ray corridor scorer) — the port's single graded-danger
  search stands in for both, as before. And the table's *dispatch* itself:
  the original tries all 8 in a fixed order every tick; the port is a
  straight-line list of 6 steps, first match wins, which behaves the same
  for what it covers but is not literally the same structure.

**What is still NOT established:** all 8 handlers are transcribed now, so
what is left is the data they act on.

1. ~~Who fills the influence map.~~ **Answered above**, same session: five
   writers, units of "ticks until fire arrives" offset by 100, 1000 for a
   cell already burning. What is still open is narrower — whether the port's
   own danger field, which is boolean per cell rather than graded, changes
   any bot decision that the graded field would make differently. The
   gradient orders the dangerous cells, and it orders them the way that
   reads oddly at first: a bomb's cells carry `fuze remaining + 100` and the
   search takes the MINIMUM, so a bot that cannot reach safety walks toward
   the blast that arrives SOONEST — where the fire will have passed — rather
   than the one that arrives latest. The port's bots only distinguish "will
   burn" from "will not".
2. **The player-struct fields** the handlers gate on and set. Cross-checked
   against the port this session, as far as the handlers' own use allows:

       +0x36..+0x39  the four action bytes. Every handler that acts writes
                     them in PAIRS — entries 0 and 4 set +0x38 and clear
                     +0x36; entry 1 sets +0x39 and clears +0x37; entry 2's
                     safe branch sets +0x39. Four contiguous bytes, two
                     pairs, one pair per key: this is almost certainly the
                     port's own `Types.Action` — FIRST, SECOND, FIRST_DOUBLE,
                     SECOND_DOUBLE — with the handlers requesting a single
                     press and cancelling the double. Not proven: which of
                     each pair is the double.
       +0x54         team id. Entry 4 refuses to bomb a match when the team
                     global 0x464964 is on.
       +0x56         bomb allowance; entry 4 compares the live-bomb count
                     from 0x4245DA against it. The port's `max_bombs`.
       +0x5b         gate on entry 1, "kick an adjacent bomb" -> `can_kick`.
       +0x5c         gate on entry 0, the own-bomb trigger reaction ->
                     `trigger_bombs`, which the port keeps as a stock rather
                     than a flag.
       +0x5f         entry 2 rolls its 1-in-10 second-key press only when
                     +0x5f is set AND +0x5b is clear — an ability the bot
                     uses when it cannot kick. `can_punch` fits; unproven.
       +0x86, +0x94  still unread: +0x86 gates entry 3 (blast a brick) and
                     +0x94 is the counter entry 0 checks before anything
                     else.
3. **Four helpers named only by what their callers do with the answer:**
   `0x4245DA` (live-bomb count), `0x421CB5` (object at a cell), `0x423188`
   (may a bomb be dropped here) and `0x422718`.

**Gameplay aggression, 2026-09-17 — a deliberate departure, not a fidelity
read.** Read exactly as disassembled, step 4 fires 1-in-5 and step 6 only
ever sought a brick — nothing in the original's own 8 handlers ever chases
an enemy. Faithful, and also passive: a human playing against it reported
"it walks a lot without looking to fight." `ai.gd`'s "GAMEPLAY AGGRESSION"
block (top of the file) is the fix, and it says outright that it is not a
second disassembly read:

- `ENGAGE_CHANCE_DENOM` replaces step 4's 1-in-5 with 1-in-2.
- Step 6 gained a first half, `_nearest_enemy_cell()` — close on the nearest
  live enemy within `HUNT_RADIUS` (6 cells) before falling back to the
  brick-seeking the original actually has. A bot with nothing safer to do
  now walks toward a fight instead of wandering.

Both numbers are gameplay tuning, kept in one named block precisely so a
later pass that wants to dial them back toward the original's own 1-in-5
and no-chase-at-all knows exactly what to touch and why it's there.
`tests/test_bots.gd`'s throttle assertion reads `Ai_.ENGAGE_CHANCE_DENOM`
rather than a hardcoded rate, so it tracks the constant rather than fighting
it if it moves again.

---

## 2. Defects

### D1 — Flame burned for nine ticks, not ten
**Found and fixed 2026-09-02, during Phase 2. Caught by arithmetic, not by a
test — the test had been written to match the code.**

`sim.tick()` aged the flame and animation timers at the *end* of the tick, so a
flame created during tick N by `_tick_bombs()` was immediately decremented by
the `field.tick_timers()` call in that same tick. Resource 10 specifies a
10-frame flame; the flame was visible on ticks N..N+8, which is nine.

Matching the original's 20 Hz exists precisely so that the tuning table's frame
counts can be used as tick counts unchanged. An off-by-one here throws that
away while still looking correct.

**Fix:** `field.tick_timers()` now runs at the *start* of `tick()`, ageing the
previous tick's timers before this tick's logic. A flame created on tick N is
first aged on tick N+1 and is visible on exactly ten ticks.

**How it was hidden:** `tests/test_bomb.gd` asserted the flame was out after
`flame_ticks - 2` further ticks — a figure derived from the implementation
rather than from resource 10. The assertion now states the duration the table
specifies, and mutation M11 (ageing at the end again) fails it.

### D2 — The two bomb-placement paths disagreed by one tick
**Found and fixed 2026-09-02, during Phase 2.**

`_player_action()` runs before `_tick_bombs()` within a tick, so a bomb placed
through the input path during tick P had its fuze decremented on tick P itself
and detonated on tick P+39. A bomb placed by a direct `place_bomb()` call
between ticks detonated on P+40. Same 40-frame fuze, two different answers.

**Fix:** `Bomb.placed_tick` records the tick a bomb was dropped on, and
`_tick_bombs()` skips a bomb whose `placed_tick` is the current tick. Both paths
now detonate exactly `fuze` ticks after the drop.

**How it was hidden:** every fuze assertion used the direct call, which was the
path that happened to be right. `tests/test_bomb.gd` now drives both and
asserts they detonate on the same tick; mutation M12 fails it.

### D3 — Every sprite decoded fully transparent
**Found and fixed 2026-09-02, during Track B. Caught by looking at the output.**

`tools/anifile.py` read bit 15 of each RGB555 pixel as an opacity flag, on the
strength of fpc_atomic's decoder doing the same. Measured across all 2299
type-4 frames on the disc, **bit 15 is set on exactly zero pixels** and on zero
keycolours. So every frame decoded to alpha 0 and the whole pack was invisible.

Frame counts, cell sizes and hotspots were all correct, and the extractor
reported 94/95 files decoded with 2299 frames. Nothing in the numbers was
wrong; the images were empty.

**Fix:** transparency comes from `keycolor_bytes`, a field the decoder was
already reading and then ignoring. It holds the 16-bit value that means
transparent and it varies per frame — `0x4210` on 1017 frames, `0x7F7F` on 620,
`0x7F5F` on 246, `0x7C1F` (pure magenta) on 171. `STAND.ANI` frame 0 is 10879
of its 12100 pixels at `0x7F5F`, its own declared key. fpc_atomic decodes the
field, names it, and then hardcodes Delphi's `clFuchsia` instead.

**How it was hidden:** nothing was asserting on pixels. The manifest comparison
checked frame counts and sizes against fpc_atomic's `files.txt`, and those were
right. A rendered image was the only thing that could have caught it, which is
why `tests/render_field.gd` now samples actual pixels.

### D4 — `state_hash()` was not FNV-1a
**Found and fixed 2026-09-02, during Phase 3.**

FNV-1a's 64-bit offset basis is `0xCBF29CE484222325` = 14695981039346656037,
which exceeds GDScript's **signed** 64-bit int. Godot rejected the literal at
runtime — *"Cannot represent 0xCBF29CE484222325 as a 64-bit signed integer"* —
and left the constant at a wrong value. The hash still mixed, still changed
when the state changed, and still reproduced from a seed, so it was usable and
wrong.

It only surfaced when the game was run for the first time and printed the error
three times before the first frame.

**Fix:** the same bit pattern written as its signed equivalent,
`-3750763034362895579`. The multiply wraps modulo 2^64 either way, so the
result is now standard FNV-1a.

**How it was hidden:** every hash test asserted a *relation* — that the digest
changes, that ordering does not matter, that a seed reproduces — and none
asserted a *value*. `tests/test_sim.gd` now pins four digests computed
independently in Python, which also gives Track C's C oracle something to match.

### D5 — Two failed attempts at getting the colour into the shader
**Both found and fixed 2026-09-02. Recorded because each looked like it worked.**

A shader material belongs to a NODE, not to a draw call, so ten player colours
cannot share one plain uniform. Two ways round it were tried and both failed in
ways that produced a plausible-looking game:

**Attempt 1 — the colour as each draw call's modulate, read from `COLOR.rgb`.**
In Godot 4 a `canvas_item` `fragment()` receives `COLOR` **already multiplied
by the texture**, so `COLOR.rgb` is `modulate * texel`, not the modulate. Every
sprite came out tinted green-times-target: slot 0, whose target is white,
rendered green because `COLOR.rgb` was the green texel itself. The diagnostic
that settled it was replacing the body with `COLOR = vec4(COLOR.rgb, 1.0)`,
which should have produced flat silhouettes and instead produced shaded
sprites in the right hues — proof the texture was already folded in.

**Attempt 2 — the slot index in `modulate.a`, colours in `uniform vec3
palette[10]`.** The alpha does survive: the pack's transparency is a hard
colour key, so every visible texel has alpha 1.0 and `COLOR.a` is the
modulate's alpha unchanged. But the **array uniform did not bind under the GL
Compatibility renderer** and every sprite took the untinted branch — ten
identical green players, no error logged. GL Compatibility is what the web
export uses, so this was not a corner worth cutting.

**What works:** one node per slot per layer group, each carrying its own
`ShaderMaterial` with a plain `vec3 target_colour`. Two groups keep the
layering right across players — bombs and flames under, shadows and players
over. Ten nodes in a single group would have drawn slot 5's flames over
slot 2's player.

Also fixed along the way: **Godot's shading language forbids `return` inside
`fragment()`**, so the shader is one nested if/else rather than early exits.

**How they were hidden:** nothing asserted on rendered colour.
`tests/render_recolour.gd` now renders all ten players and asserts each is
nearer its own target than any other — and its mutation tests include the
recolour going dead entirely, which is the failure both attempts produced.

### D6 — Powerups drawn through intact bricks
**Found and fixed 2026-09-02, during Phase 4a. Caught by an existing test on
the first run.**

A powerup is hidden UNDER a destructible brick and only appears once the brick
is destroyed — that is what the field's powerup plane is for. The first version
of `_draw_powerups()` drew every powerup on the field regardless of whether its
brick was still standing, so icons sat on top of intact bricks.

`tests/render_field.gd` failed immediately: cell (4,1) is a brick and matched 0
of 9 samples against the brick art, because a powerup icon was over it. That
suite exists to check the field is drawn from the right art at the right
offset, and it caught a bug in a feature added three phases later.

**Fix:** skip any powerup whose cell is not `Brick.BLANK`.

### D7 — The "diseases do not recycle" rule was unreachable
**Found and fixed 2026-09-02, by mutation testing.**

`give_powerup()` handled the two disease powerups in an early branch that
returned before `collected[which] += 1`, so `collected[DISEASE]` was always
zero. `repopulate_powerups()` skips the disease powerups when scattering a dead
player's pickups back onto the field — but with the tally always zero there was
nothing to skip, and the rule was dead code.

Mutation M26 removed the skip entirely and **nothing failed**, which is how it
surfaced. Every other mutation in that batch was caught.

**Fix:** disease pickups are counted like any other. VALUELST 122's wording —
*"will a disease recycle like other powerups when it comes out of you"* — only
makes sense if the game tracks that one was taken, and the match statistics
need the tally anyway. `repopulate_powerups()` now has something real to
decline.

**How it was hidden:** the test injected diseases with `catch_disease()`
directly rather than taking them as powerups, so it never exercised the tally.
It now takes one through `give_powerup()`.

### D8 — A carried bomb's fuze kept burning, and a trigger bomb burned down
**Both found and fixed 2026-09-02, during Phase 4b, by the new ability tests.**

`_tick_bombs()` burned every bomb's fuze unconditionally. Two bombs must not
burn: a CARRIED one (AtomBomberman's notes: *"when its picked up its not even
ticking (starts ticking when it falls)"*) and a TRIGGER one, which waits for
its owner's second action instead.

The trigger case cascaded — a trigger bomb went off on its own after 40 ticks,
so triggering it later found nothing, so the whole trigger mechanic silently
did nothing.

**Fix:** both are skipped. A trigger bomb whose owner has DIED reverts to an
ordinary bomb, or it would sit on the field for the rest of the round with
nobody able to fire it. That reversion is a guess — VALUELST has no resource
for it and fpc_atomic reaches the same conclusion via a 15-second timeout — and
it is the only guess in that function.

### D9 — A server with no players declared an instant draw
**Found and fixed 2026-09-02, during Phase 5, by reading the server's own log.**

The server holds ten seats from the moment it starts listening, so the field
layout does not shift when somebody joins. It marked the unoccupied ones
`alive = false`, and `_check_round_over()` could not tell an empty seat from a
dead player: zero survivors out of ten "players" is a draw. Every server logged
`round over: outcome 2 winner -1` before its first player had even connected.

**Fix:** `Player.in_play` marks whether a seat is occupied at all, and the
round-end check counts contenders rather than seats. The same count fixes the
mirror-image bug — a solo round ending on tick one with its only player
declared the winner.

### D10 — `state_hash()` ignored the whole round state
**Found and fixed 2026-09-02, during Phase 5, by the wire-format test.**

The hash covered the tick count, the field, the players and the bombs — but not
`time_left`, `hurry_index`, `outcome`, `winner_slot`, `winner_team` or
`team_play`. So a client whose clock, closing wall or declared winner had
desynced from the server hashed **identical** to it.

That is precisely the failure the netcode's equality assertion exists to catch,
and the assertion could not have caught it. Found because
`tests/test_net.gd` asserts the wire format carries each field by mutating it
and requiring the hash to move — five of those mutations did not move it.

**Fix:** the round state is in the hash. The five mutations now fail without it.

### D11 — The first two web builds shipped no art at all
**Found and fixed 2026-09-02, during Phase 6, by measuring the `.pck`.**

Both exports succeeded. Both produced a client that would have rendered flat
colours, for two different reasons in sequence:

1. `pack.gd` read the art with `Image.load_from_file()`, which reads the real
   filesystem — and a browser has none. Fixed by reading through `FileAccess`,
   which handles `res://` and real paths alike.

2. With that fixed the `.pck` was still 1.58 MB against a 2.7 MB pack. Godot's
   importer claims any `.png` under `res://`, converts it to its own compressed
   texture and **strips the source from the export** — so the file names
   shipped and the bytes did not. Adding a `.gdignore` stopped the importer and
   also removed the files from the index, so `include_filter` could no longer
   see them either: the `.pck` dropped to 244 KB and zero art. Neither half
   works alone.

**Fix:** one container file, `data/packs/cd.bin` — header, manifest JSON, then
every PNG concatenated. Nothing imports an unknown extension, one
`include_filter` entry ships it, the bytes arrive unmodified (which the recolour
shader needs, since it tests pixels for exact green dominance), and a browser
makes one request instead of 58. The `.pck` is now 2.88 MB.

**How it was hidden:** "the export succeeded" is not the same claim as "the
export contains the game", and only the first was being checked. `EXPORT=1
verify.sh` now moves the real pack aside and loads the art from the `.pck`
alone, which is the only way to ask the question honestly.

### D12 — `--shot` never fired on a joining client
**Found and fixed 2026-09-02, during Phase 6.**

`_process()` returned early in client mode, before the screenshot-and-quit
path. A client asked to capture a frame therefore captured nothing and never
exited — indistinguishable from a hung join, which is how it presented.

**Fix:** the capture path is shared by local and client mode, and takes the
tick to report as an argument. A refused or closed client now also exits with a
reason instead of sitting there.

### D13 — Level specials exposed the powerups under them
**Found and fixed 2026-09-02, during Phase 8, by looking at a screenshot.**

`load_extras()` runs after `place_powerups()` and clears each special's cell so
the feature has somewhere to sit. Clearing a cell whose brick was hiding a
powerup left that powerup lying in the open from tick zero — visible
immediately on level 10, where icons sat along the conveyor belt.

**Fix:** a special's cell is cleared of its powerup as well as its brick.
`tests/test_specials.gd` asserts no arrow, conveyor, trampoline or gate cell
has a powerup on it, on every level.

### D14 — Bots wandered back into the fire they had just escaped
**Found and fixed 2026-09-02, during Phase 7, by a test written to measure
survival rather than distance.**

Three bots in eight died to a bomb dropped under them. The first version of the
test asked "did it get more than four cells from the bomb within 25 ticks",
which a bot drifting toward bricks passes by luck — and mutation M49, deleting
the danger check entirely, passed it too.

Rewritten to ask whether the bot is **alive** after the blast, it failed on the
real code: 3 of 8.

**Cause, established by reverting each candidate separately:** a bot that had
escaped, with no powerup in range and no brick worth walking to, fell through
to the last-resort random wander — which picked any open direction, including
straight back into the blast it had just left.

**Fix:** the wander prefers a safe neighbour. Reverting only that line brings
all three deaths back, which is what pins the diagnosis.

**Recorded honestly:** the same change also made goal pathing avoid danger,
which is defensible on its own terms but is NOT what fixed the deaths, and has
**no independent test** — mutation M51 reverts it and nothing fails, because
the bot turns back at the blast's edge before its own tile index enters it.
`tests/test_bots.gd` says so at the point it would have caught it.

---

### D15 — A new round threw the bots away

**Found and fixed 2026-09-02, by a test written for exactly this.**

`Server._start_round()` builds a fresh `Sim`, which is the right thing to do —
a round is a new field, new spawns, new seed — but the bots live in the `Sim`,
so they went with it. A server started with `--bots 6` played one round and
then sat empty: still listening, still ticking, still accepting joins, with
nobody in it. Nothing about that looks broken from outside, and the round after
the first would simply never end, because ending needs two contenders.

**Fix:** the server remembers which slots are bots (`_bots`) and re-fills them
after every `setup()`. A human who takes a bot's seat is removed from that list
as well as from `sim.bot_slots`, or the next round would hand the seat back to
a bot while the human is sitting in it.

Mutation M62 deletes the bookkeeping and `tests/test_netplay.gd` fails.

Worth noting how it was found: the test was written **because** mutation
testing needed a target for "a new round loses its bots", not because anything
looked wrong. The first run of that test failed against real code.

### D16 — A netplay assertion measured the round and meant the server

**Found and fixed 2026-09-02.**

`tests/test_netplay.gd` asserted `server.sim.tick_count > 20` to mean "the
server ran". That was true while a match was one endless round. Once rounds
could end, a client blowing itself up started the next round, and the next
round's `Sim` begins at tick zero — so the assertion failed on **two runs in
three**, reporting 16 ticks after 240 pumps.

Neither the server nor the netcode was wrong. The test was measuring the round
while claiming to measure the server.

**Fix:** `Server.ticks_served` counts ticks across every round and the
assertion reads that. Four consecutive runs, no failures.

Recorded because the failure looked exactly like a netcode flake — an
intermittent, timing-dependent failure in a WebSocket test is the most
plausible thing in the world to blame on the transport, and the transport was
innocent.

### D17 — Audio leaked at exit

**Found and fixed 2026-09-02.**

Godot reported `8 ObjectDB instances were leaked at exit` on every run with
sound on: four `AudioStreamWAV`s and four `AudioStreamPlaybackWAV`s, all with a
reference count of 1. A stream still playing when the tree is torn down leaves
its playback referenced by the audio server.

Harmless, and that is the problem — it looks exactly like a real leak, and a
warning nobody can explain is a warning everybody learns to ignore.

**Fix:** `Sfx._notification()` stops every voice on `NOTIFICATION_EXIT_TREE`
and `NOTIFICATION_PREDELETE`.

### D18 — One silent socket stalled the server permanently

**Found and fixed 2026-09-02, by leaving a probe connected while looking at
something else.**

A client more than `SYNC_TOLERANCE_TICKS` behind pauses the game for everyone,
which is right — the alternative is letting one player act on a world the
others cannot see. A client silent for `TIMEOUT_TICKS` loses its seat, which is
also right.

The two rules were incompatible. Silence was counted **inside `_tick()`**, and
the pause stops `_tick()`. So a client that connected and then stopped talking
paused the game at 16 ticks behind and could never be reaped, because the
counter that would have reaped it had stopped with the simulation. The server
sat paused with a full round of players waiting on a socket that would never
say anything again.

That is a denial of service anyone who can reach the port can perform by
accident, and a self-hosted server is exactly where it matters.

**Fix:** silence is measured in **milliseconds of real time**, accrued in
`poll()` before the pause decision, so the reaper runs while the simulation is
stopped. `tests/test_netplay.gd` now has a client that goes quiet while another
keeps playing, and asserts the server pauses, drops it, and **runs again**.
Mutation M67 stops the accrual and that test fails.

Worth noting how it was found: three probe runs in a row against a real server,
each leaving a seat behind, and the third one only ever received a single
snapshot. No test could have found it, because every test in the suite keeps
its clients talking.

### D19 — A closed browser tab held its seat for thirty seconds

**Found and fixed 2026-09-02, in the same session as D18 and for the same
reason.**

The server learned that a client was gone only from the silence timeout, so
closing a browser tab left a ghost: a seat held, a player standing on the
field, and — being silent — the game paused for everyone until the thirty
seconds expired. `WebSocketMultiplayerPeer` reports the disconnection
immediately and nothing was listening.

**Fix:** `peer_disconnected` is connected to `_release()`. A seat is freed the
moment the socket closes; the timeout remains for the tab that stops talking
without closing, which is the case it was written for.

Observed: three consecutive `tools/ws_probe.py` runs now each take slot 0 and
the server logs `left (slot 0)` between them. Before the fix, run two got slot
1 and run three only one snapshot.

### D20 — Teams were split odd against even

**Found and fixed 2026-09-02, when `OPTIONS.BM` arrived.**

Where a scheme does not state a team — 31 of the 67 do not — the port assigned
`slot % 2`. The original splits the ten slots down the **middle**, and its own
options help says so twice:

> Generally, players 1 through 5 are on one team and players 6 through 10 are on
> another.

and, under Wally Bomb:

> To ensure that the teams are placed properly, player slots 1 through 5 are on
> one team and player slots 6 through 10 are on the other.

`slot % 2` puts every player on the opposite team from the original for half
the slots, and the halves matter for more than bookkeeping: Wally Bomb starts
the two teams on opposite sides of an indestructible wall, so a scheme laid out
for contiguous halves pairs the wrong people and puts teammates behind
different walls.

**Fix:** `Const.default_team()`, one function, cited to the file. A scheme's own
`-S` team still wins where it states one. `tests/test_round.gd` asserts the
split, that the halves are five and five, and that they change over exactly
once — that last one is the property Wally Bomb depends on. Mutation M68
restores `slot % 2` and it fails.

### D21 — The menu ran off the bottom of the screen, then off the top

**Found and fixed 2026-09-02, by looking at a screenshot.**

The first menu layout drew fourteen option rows and ten player slots in one
column. START, HOST A GAME and QUIT — the only rows that DO anything — were
below y=480 and simply not on screen, and the footer was drawn through the last
two player slots.

Tightening it then broke the other end: the first row moved up into the
subtitle and the two lines overlapped.

**Neither was visible to `tests/test_menu.gd`**, which had 232 passing checks at
the time. Every value was right, every clamp held, every label was correct. The
model was fine and the screen was unusable.

**Fix:** the slots are a five-by-two grid, and `tests/render_menu.gd` computes
where the first row starts and where the last one ends from the view's own
constants, requiring both to clear the header and the footer. Mutations M81
(a taller row) and M82 (slot rows in their raw dark colours) both fail it.

The lesson is the same one D6 and D13 taught — a renderer needs a test that
looks at pixels — and it is the third time it has been learned, which is why
`render_menu.gd` exists rather than a note saying "check the menu by eye".

**And it earned its keep on 2026-09-03.** Adding Win Matches By Kill Total and
Random Start took the list from fourteen rows to sixteen, and
`render_menu.gd` failed with "the last row ends at y=472, inside 480 with room
for the footer" — the same overrun as the original defect, from a change that
never touched the view. `ROW_H` and `SLOT_H` went from 18 to 17 (the header
cannot move: `TOP` is already at its lower bound), which puts the last row at
451. Every model test was green throughout, exactly as it was the first
time.

### D22 — A test's own null check silenced the mutation it existed to catch

**Found and fixed 2026-09-02, by a mutation that would not die.**

`tests/render_recolour.gd` gained a check that `game_view` really hands the
remap tables to the shader, written as:

    if bool(mat.get_shader_parameter("tinted")) != true:

A shader parameter that was never set comes back as **null**, and `bool(null)`
raises *"Invalid call. Nonexistent 'bool' constructor"* in GDScript. So on the
mutated build — where no material has the parameter — the function died on its
first material, before reaching the assertion, and the suite printed
`Result: 90 checks, 0 failures` and a green tick.

**Two fixes, and the second matters more:**

1. The comparison is `mat.get_shader_parameter("tinted") != true` on the
   Variant, which is null-safe.
2. **The mutation runner now treats an engine error as a catch**, which is what
   `verify.sh` has done since the scheme suite taught it that lesson — but the
   throwaway runner used for mutation batches only grepped for `FAIL` and
   `Result:`. It reported a crashed suite as an ESCAPED mutation, which is the
   most misleading way to be wrong about this: it sends you looking for a
   missing assertion when the assertion exists and never ran.

The same class of bug as D1 and the `verify.sh` hole it mirrors: a run that
does not execute its assertions is not a measurement, however green it looks.

### D23 — Two invented mixer rules, both refuted by the binary

**Found 2026-09-02, by reading `BM95.EXE`.** Not a defect found by a test — the
tests passed, because they had been written to pin the invented rules.

`scripts/audio/sfx.gd` shipped two rules that `docs/BUGS.md` Q8 recorded as
guesses: collapse a tick's events so a chain reaction is one sound, and evict
the oldest voice when the mixer is full. Both were wrong. The original plays
every raised sound, picks a different take each time by least-used-with-random-
tie-break, and refuses a new sound outright when the voice count is at the cap.
Q8 has the disassembly.

**What it sounded like:** a chain of eight bombs was one explosion instead of
eight different ones, and a burst of sound cut off whatever was already
playing. Both are audible; neither is a crash, which is why only the binary
could settle them.

**Fixed:** `play_batch` no longer deduplicates, `pick_take` implements the
least-used deck with the original's 200-attempt rejection sampler, the gate
refuses rather than evicts, and the voice array is cap + 1 long because the
original's own comparison admits one more than resource 8 says.
`tests/test_sfx.gd` was rewritten around the new rules — six of its assertions
were pinning the old ones.

### Two equivalent mutants, recorded rather than counted as gaps

Mutation testing the corrected sound rules turned up two mutations that no
suite fails, and in both cases the reason is that the mutation **changes
nothing observable**, not that a test is missing. Recorded because "escaped
mutation" and "equivalent mutant" look identical in a results table and mean
opposite things.

**M98 — the voice gate is redundant with the array length.** Deleting
`if concurrent_cap() < live: refuse` still refuses the seventh sound, because
`_free_voice()` finds nothing when all six voices are busy, and "all six busy"
and "live > cap" are the same condition once the array is cap + 1 long. The
gate is kept anyway: it is the original's own logic, stated where the original
states it, and the array length is a consequence of it rather than a
substitute.

**M120 — the roulette's centre falls back to the value the data holds.**
Making `Roulette.centre()` ignore VALUELST resource 1000 returns its fallback,
`Vector2(320, 240)` — which is exactly what resource 1000 says. The fallback is
that value on purpose, so a pack built without game data still centres the
wheel, and the two paths are therefore indistinguishable. Catching it would
need the data changed under the test, and `Values.V` is a generated constant.

**M102 — the sound group's gap rule cannot be seen from the Godot side.**
Widening `event_takes` to include numbers past a gap changes no shipped pack,
because `TAKE_CAP` truncates every affected event first: `powerup_good` keeps 8
of 51 and `awesome` 2 of 5, while the stranded takes begin at the 52nd and the
6th. Measured, not assumed — the two take lists were compared after capping and
are identical.

So the rule is asserted where it has an effect: `tools/rss.py --check` verifies
each event's takes are the numbers `[base, base + len)` with every one present
and `base + len` absent. It fails on the widened version and names both gaps.
`verify.sh` runs it.

**A false failure on the way**, worth its own note: the first version of that
check keyed by FILENAME, and SOUNDLST reuses files across events on purpose —
`kbomb1` is resource 120 and 150, `proud` is 320 and 2000, `pu1` is 468 and
1400. A name does not identify a resource, so the check reported eight events
as broken when all eight were correct.

### D24 — Everything was drawn two pixels high, and the actors a cell out

**Found and fixed 2026-09-02, from four bug reports after somebody played it.**

Four complaints — the explosion, the bomb's position, the player leaving the
screen, and missing UI — and the first three were one arithmetic error and two
missing terms.

**The field offset was wrong by two pixels.** `BM95.EXE` sets the whole field
geometry in one function at `0x42647A`, which names its own source file as
`map.c` line 317:

    FIELD_W  = 15 ; FIELD_H = 11 ; BLOCK_W = 40 ; BLOCK_H = 36
    X_ORIGIN = (screen_w - FIELD_W * BLOCK_W) / 2      ; 20 at 640
    Y_ORIGIN = screen_h - FIELD_H * BLOCK_H - 16       ; 68 at 480

The port had 66. Both offsets are now DERIVED from that formula rather than
written down, so they are also right at any other screen size.

**Bombs and flames were drawn in field-local coordinates**, without the field
origin at all — 20 px left and 68 px up, which put a bomb a cell and a half
from the player who dropped it. Players had the origin; bombs and flames never
did, and nothing compared the two.

**The actor anchor was a half-cell high.** Every sprite hotspot on the disc is
bottom-centre with all of its ink above — measured: a standing bomberman is
35x67 with its hotspot one pixel below its lowest ink, and the bomb, flame and
shadow frames have their hotspot exactly on their bottom edge. An actor's
stored position is its cell CENTRE, so the hotspot belongs `BLOCK_H / 2 - 1`
lower, on the cell's bottom edge. That 17 is not a guess: it is the same
constant `BM95.EXE`'s `tile_y` (0x4266A3) subtracts to turn a position back
into a row.

**And nothing clipped the actors.** A bomberman is 67 px of ink over a 36 px
cell, so one on the top row reaches 31 px above its own cell and, unclipped,
off the top of the display. That was "the player goes out of the screen".
Actor drawing is now clipped to the playfield rectangle.

**Fixed, and each part tested by pixels rather than by constants**, because
none of these changes a constant that a model test could check:
`tests/render_field.gd` puts a player on row 0 and requires the band above the
field to be untouched, and puts a bomb in the middle of the field and requires
its own cell to hold over 60% of the change. Mutations M103-M106 fail them.

**A fixture broke on the fix**, which is worth recording: two of
`tests/render_recolour.gd`'s sample boxes were positioned by restating where
the feet are — "the feet sit on the cell centre", which was true only while
the anchor was wrong. Correcting the anchor moved every sprite down 17 px and
the boxes started sampling the shadow and the floor, which read as two players
rendering the wrong colour. Both now ask `Const.actor_anchor()`, the renderer's
own rule, instead of restating it.

### D25 — The clock drew two squares where the font has a colon

**Found and fixed 2026-09-02, by counting a sequence.**

`KFONT.ANI`'s `numeric font` sequence is **eleven** steps, not ten: `D0.TGA`
through `D9.TGA` and then `DC.TGA`, a 6x19 glyph that is two 6x7 blocks
separated by five blank rows. A colon.

The status band's clock drew two `draw_rect` squares in its place, with a
comment claiming the font had no colon. It also anchored each digit on its own
hotspot, which made the advance it returned disagree with where the digits
landed and put those squares in the wrong place as well.

**Fixed:** the digits are drawn as a font — from the top-left, advancing by
width — and the colon is `DC.TGA`.

**Three attempts to test it, and the first two passed on the broken code:**

1. Counting groups of inked columns in the clock's strip. The digits already
   fall into four groups, so deleting the colon changed nothing.
2. Requiring a column with exactly two runs of 5-9 pixels — the colon's
   shape. Some digit has a column shaped like that too.
3. A **template match** of `DC.TGA`'s own alpha, taken from the pack, against
   the rendered strip, with the glyph's gap required to be empty. Nothing but
   the glyph satisfies that, and mutations M115 and M117 — deleting it, and
   going back to squares — both fail.

The lesson is the one D21 taught in a different form: a test written from what
the bug looks like tends to pass on the bug.

### D26 — Seven photographs of the programmer across the top of the playfield

**Found and fixed 2026-09-02, immediately, by looking.**

`KFACE.ANI` is 40x40, has four frames, and its sequences are named `kface
north`, `kface east`, `kface west`, `kface south`. Four directions at head size
reads exactly like a status-bar portrait, and `MASTER.ALI` loads it first of
all 76 animations, which made it look important.

It is a photograph of a human head, turning. `KURTHEAD.PCX` beside it in `RES/`
is the same person: it is the Kurt-head easter egg player, not a status icon.
Using it put seven identical photographs of the lead programmer across the top
of the field.

The per-player readout is a disc in that player's colour instead, and is marked
in the code as this port's rather than the original's: no art on the disc has
been identified as the in-game readout, and all eleven level backgrounds leave
that band plain.

### D27 — Eleven defects a player found in ten minutes, and what they had in common

**Found 2026-09-03 by somebody playing the game**, after a session that had
declared it finished. Worth keeping as a list, because nine of the eleven were
invisible to 5,600 passing checks and the two that were not had tests asserting
the wrong thing.

| # | What they saw | What it was |
|---|---|---|
| 1 | No music | The screens have music of their own on the disc — SOUNDLST 1000 title, 1010 menu, 1020 input selection, 1030 game over, 1040 network, 1130 draw — and the port played none of it. Only the per-level tracks were wired |
| 2 | "Available net games" over the menu | Drawn at y=352, straight through MAINMENU.PCX's painted "Exit Bomberman". Moved below the items, into a panel of its own |
| 3 | The options list over its own footer | Nineteen rows at 26 px ran to y=514 on a 480-line screen. The list had grown from thirteen rows as the disc's own settings were implemented |
| 4 | About and the Manual did not scroll | They drew the first screenful and stopped. Both are pages of the disc's own text and the manual is the whole booklet |
| 5 | Return cycled a slot instead of starting | `_prepare_setup` forced `menu.in_slots = true` and the Return branch cycled a slot whenever it was set, so the setup screen's own hint — "Return to start" — was a lie and the game could not be started from it |
| 6 | Keyboard definitions "broken" | Same cause: the row could not be reached. And `screen_view.gd`, which is what the app actually draws its menus with, had no code for that screen at all — it was only in `menu_view.gd`, which nothing but a test uses |
| 7 | Bombs did nothing | Same cause again: pressing Return on the setup screen cycled slot 1 through OFF/AI/KEY/JOY, so the player was moved onto the second keyset or off the keyboard entirely |
| 8 | The shadow drawn over the player | The untinted node, which draws the shadows, was created AFTER the ten player nodes and children draw in order |
| 9 | The player behind the wall on the top row | A standing bomberman is 67 px of ink over a 36 px cell and the sprite was clipped to the playfield, cutting it across the chest |
| 10 | No death animation | The disc has **24** of them — XPLODE1..17.ANI, "die green 1" to "die green 24", which is what VALUELST 105's 24 counts — and none was packed |
| 11 | The score over the gameplay | The band was drawn before the actors, so a player on the top row went through the numbers |

**The pattern.** Nine of the eleven are in the ~15% of this port that the test
suites cannot see: draw ORDER, screen layout arithmetic, and the input routing
between screens. The model tests were all green while the game was unplayable,
which is the same lesson as D21 and D24 and the third time it has been paid
for. What changed as a result: `tests/render_screens.gd` now does the options
list's arithmetic, `tests/render_field.gd` asserts the sprite is whole rather
than clipped, and `tests/render_hud.gd` caught the stale HUD (below) on its
own.

**Two more found while fixing them**, neither reported:

* **The status band never redrew.** `queue_redraw_all()` iterated the ten
  tinted nodes per group and missed the untinted ones and the new HUD node, so
  the clock froze at its first value and the shadows lagged a frame behind.
* **A solo win announced a TEAM win.** Every slot has a team number whether or
  not team play is on, and `Match.record` copied the winner's into
  `champion_team`; the victory screen reads that field first, so a one-player
  match ended on "TEAM 0 WINS" over the winner's own art. It now says
  MESSAGES.TXT 36's own sentence, "PLAYER 1 WINS THE MATCH!".

**And three gameplay gaps the audit turned up afterwards**, all confirmed
against `MANUAL.BM`:

* **Grab, throw and spooge were unreachable.** The simulation implemented them
  under `Action.FIRST_DOUBLE` and no input path ever produced one. The manual
  is explicit: "To drop a bomb, press this button... **Press the button again
  after dropping a bomb** to do either if you have the appropriate powerup."
  One button, and the second press does the other thing.
* **The action button could not stop a kicked bomb**, which the manual gives as
  its first job — "if your bomberman has the Kick powerup, press the action
  button to stop a kicked bomb". `SoundEffect.BOMB_STOP` had sat unused as the
  evidence, and so had `BOMB_THROWN`: throwing was silent too.
* **KICK.ANI and WALK.ANI's `spin` were never drawn.** A kick looked like
  walking into a bomb, and a player thrown by a trampoline kept walking through
  the air.

### D28 — Seven more from a second sitting, and the file that answered them

**Found 2026-09-03 by the same player, on the build that fixed D27.** Seven
reports, and the fixes for them turned up eleven more.

| # | What they saw | What it was |
|---|---|---|
| 1 | START, HOST A GAME and QUIT could not be selected | The cursor walked the **ten player slots** on its way past `Item.SLOTS` — a row the options list stopped drawing when the slots got a screen of their own. Eleven presses of "down" with nothing highlighted, and the three rows after it unreachable in practice |
| 2 | The human could not drop bombs | `INPUT.BM` states the disc's own layouts: "KEY 0: Cursor Keys / Space / Enter". The port had Return and Backspace, both invented, so **Space was bound to nothing** and Return — which the disc makes the ACTION button — dropped the bomb. Compounded by #1: Return while the cursor was in the invisible slot list cycled slot 1 from KEY to OFF, and a game with no keyboard player in it started anyway |
| 3 | Scrolling down needed two presses of up | `screens.text_scroll` was clamped only where it was DRAWN, so it counted past the end of the page. However far past you went was how many presses it took to come back |
| 4 | Still no death animation, and the player still moved | `set_input()` wrote `move` onto a dying player every tick, and the view picks the walk sheet whenever `move` is not STILL — so the corpse jogged on the spot and the death frames were never reached. Nothing ever cleared `alive` either: a body stayed on the field, with a shadow under it, for the rest of the round |
| 5 | The score did not update after a death | A consequence of #2 and #4 — with slot 1 switched off there was no human to die, and with the corpse still walking nothing looked as though it had |
| 6 | The timer overlapped | Two things at once: the clock and the player discs ran to y=43, and the status panel the level art leaves is **42 px** (measured: ten of the eleven backgrounds are solid black from y=0 to y=41, and FIELD1.PCX is solid grey over the same rows). And actors were clipped at y=0 rather than at the panel, so a bomberman on the top row was drawn through the clock |
| 7 | The explosion's middle did not match its ends | Two causes. MFLAME.ANI's 45 frames all carry the same **generic hotspot** — `(width / 2, height - 1)` — so anchoring on it bottom-aligned bands of different heights, and the arms sat about eight pixels below the centre's crossbar. And the sim wrote the END flag **instead of** the arm's direction bit, so the last cell of every arm had no direction for the view to read and fell through to the CENTRE sprite: MFLAME's four `flame tip<dir> green` sequences were never drawn at all |

**`INPUT.BM` is the file that should have been read first.** It is the help
text for the input-selection screen and it states the whole thing as a table:

```
            Movement       Action1      Action2
KEY 0:      Cursor Keys    Space        Enter
KEY 1:      R,D,F,G         S            A
```

`MANUAL.BM` says the same from the player's side — "DROP BOMB: (joystick button
1, spacebar, 'S')", "ACTION: (joystick button 2, enter, 'a')" — and both were
sitting in the install root the whole time. The port had `KEY_ENTER` and
`KEY_BACKSPACE` for keyset 0 and fpc_atomic's WASD for keyset 1.

A corrected default is not enough on its own: `keys.cfg` is written whenever the
keyboard screen is left and stores all twelve bindings, so on any machine that
had already run the game the old layout came straight back over the new one. The
file carries a version now and an older one is discarded.

**What else those two files gave up.** Both name features the port did not have:

* **`T` toggles a player's team on the setup screen** — "You need to have team
  play enabled (from the options screen) for this feature to work". Teams came
  from `Const_.default_team()` and nothing could change them, which made
  OPTIONS.BM's "**generally**, players 1 through 5 are on one team" into a rule
  rather than the default that word says it is.
* **`Ctrl-A` sets every player to AI** on that screen, **`F10` forces a draw**,
  **`Ctrl-Q` quits to the main menu**. All three now work. The port's debug grid
  moved off F1, which MANUAL.BM gives to Help.

**Six more drawing gaps, found by asking what art the disc has that the port
never names.** Every one of them is a sequence with its own file and its own
name:

* `PUNCH.ANI` — `punch <dir> green`. Punching looked like standing still.
* `PUNBOMB1..4` — `punch <dir>`, the bomb tumbling away. A punched bomb slid
  through the air on its standing frame.
* `BOMBWALK.ANI` — `bombwalk <dir> green`, the player with a bomb over its
  head. Carrying one looked exactly like not carrying one, and the bomb was
  drawn a second time at the carrier's feet.
* `BPICKUP.ANI` — `pickup <dir> green`, played over resource 665's own pause.
* `TRIGBOMB.ANI` — `bomb trigger green`. A trigger bomb looked like a timed
  one, which is the difference between walking past a bomb and dying beside it.
* `DUDS.ANI` — `bomb regular green dud`, and `BOMBS.ANI`'s own second sequence
  `bomb jelly green`, which was packed and never drawn.

**And one whole mechanic.** `VALUELST` 670 and 671 —

```
670,1   what's the minimum number of powers you lose when hit on the head?
671,3   what's the additional random number of powers you might lose?
```

— with SOUNDLST 360-399, forty recordings of "you are stunned by a bomb landing
on you". A punched bomb landing on somebody did nothing at all. It now costs
them 1 + rand(3) powerups, scattered back onto the field the way a dead
player's are, and the derived stats are recomputed from what is left rather
than undone one rule at a time.

**Still not done, and named here so it is not rediscovered:**

* ~~MANUAL.BM's **hold-to-carry**~~ **DONE 2026-09-17.** "If you have the
  Blue Hand powerup, you may carry a bomb by grabbing and **holding down**
  the Drop Bomb button." The grab is still the edge it always was; what's
  new is `Player_.action_first_held` (threaded through `keysets.gd`/
  `pads.gd`/the netcode — `Protocol_.VERSION` moved to 3, `Snapshot.LAYOUT`
  to 2) telling the sim whether the button is STILL down, each tick. A
  bomb picked up while it was down (`Bomb_.hold_required_to_carry`) is put
  down, not thrown, the moment it goes back up — a grab reached any other
  way (a direct call, a tap already released again) still carries
  indefinitely as it always did, so nothing that never asked for the hold
  behaviour lost anything. Throwing stays the deliberate second press,
  which a fast release-then-repress still reaches (`throw_bomb()` runs
  before a same-tick release would read as a plain drop) — the disc names
  no release behaviour at all, so both halves of this are the port's own
  reading, not a second disassembly find. `_check_hold_to_carry()` in
  `sim.gd`, `tests/test_abilities.gd`.
* **F1 (help)** — still deliberately free. `MESSAGES.TXT`/`MANUAL.BM` give it
  to "review help / information files," and the port's only screen with that
  content is the pre-game ABOUT/MANUAL menu (`scripts/app/screens.gd`
  `Screen.MANUAL`) — reachable only through `_open_menu()`, which is the
  same call Escape makes and ends the round to get there. Binding F1 to it
  would cost a player their round just to read the manual mid-game, which is
  a worse trade than the key doing nothing. **Alt-N and Alt-D are now
  implemented** (2026-09-17): Alt-N writes `user://NETSTATS.TXT`
  (`main.gd` `_write_netstats()`) with whatever's actually known live —
  host/client mode, `Server.ticks_served` or `Client.server_tick`, and the
  real snapshot size/bandwidth from `Snapshot_.write()`, the same call
  `tests/test_net.gd`'s own bandwidth assertions use. Alt-D
  (`_print_misc_info()`) prints mode/level/player-count/tick to the console
  rather than drawing an overlay — MANUAL.BM's own warning that it "will
  affect synchronization" is the only fact about its content anywhere on the
  disc, which rules out reading or writing sim state to reproduce it, and
  there was nothing else to safely show.
* **The netplay server-override key ('o' or '0')** — investigated, not a
  small fix. `INPUT.BM`: "If you are a SERVER, you can override the player
  selection made by a CLIENT." The port's netcode has no client-side
  selection to override in the first place — a joining client sends no
  slot-type preference at all; `server.gd` just assigns the next free slot
  and the wire protocol (`protocol.gd` `S_WELCOME`) only ever tells a client
  which slot it got, never asks. The original's KEY/AI/OFF/JOY-per-slot
  choice that a host could override belongs to a client-selection mechanism
  this port never built, not a missing override on top of one that exists.
  Implementing the key needs that mechanism first — a new protocol message
  for a client's own slot-type request, which is a real protocol change,
  not a keybinding.
* ~~**SOUNDLST 341-349**, "death anim sounds BASED on which anim". Nine
  sounds for twenty-four animations and no way to recover the mapping.~~
  **DONE 2026-09-17, and the premise was wrong.** Checked directly against
  the disc rather than the comment alone: SOUNDLST.RES has exactly ONE named
  resource in this range (341, "burnedup") and no "NNN is the last..."
  comment bounding it the way every other event has one; `SOUND/` has
  exactly one matching file, `BURNEDUP.RSS`. `tools/rss.py`'s own EVENTS
  table declared `(341, 349)` by analogy with the neighbouring 9-wide
  groups — a guess, and wrong, corrected to `(341, 341)`; the packed output
  was unaffected either way, since `event_takes()`'s own gap rule already
  stopped at 342. There was never a 24-into-9 mapping to recover: one
  sound, every death. `Types_.SoundEffect.DEATH_CLUNK` now plays it in
  `kill()`, alongside `PLAYER_DIED`. Exact frame-sync within the death
  animation ("sync with the anim") is not established and is a guess —
  it plays once, at the moment of death.
* The **cornerhead animations** (`CORNER0..7`, VALUELST **330**, not 308 as
  this bullet said until 2026-09-17) — a real "trapped, about to die" state
  per `TOOLS/ANIMS.TXT`'s own heading (Q3), not decoration. Not packed, and
  its trigger in `BM95.EXE` not yet located — see Q3's 2026-09-17 addendum.
* **`APPLBITE`, `NUCKBLOW` and `ZEN`** — a separate, unrelated, still
  unexplained animation family (different size than cornerhead, name
  appears nowhere on the disc). Not packed.

### D29 — A live session's own report, and what came of chasing each line

**Found 2026-09-17 by a player actually running the build**, across several
rounds of "here's what I'm seeing" while this session was still going. Six
reports, six different outcomes — three real defects fixed, one already-fixed
defect explained (the fix just hadn't been relaunched into yet), one
confirmed-correct mechanic, one confirmed-correct piece of disc art mistaken
for a bug. Kept together because the pattern — a live player finding things
5,600+ passing checks couldn't — is the same one D21/D24/D27/D28 already
established, and it held again.

| # | What they saw | What it was |
|---|---|---|
| 1 | Bombs sometimes don't destroy walls | `_propagate()`'s stop-rule order tested "is there a powerup here" before "is this a brick" — and every powerup sits hidden UNDER a brick by design, so a flame hitting one destroyed the invisible powerup and stopped without ever touching the brick. Swept all 67 schemes: **1,540 of 4,268 bomb-adjacent-to-brick cases (36%) failed before the fix, 0 after** |
| 2 | Explosion top doesn't line up with the centre | Not a rounding bug, in the end — an inherent limit. The centre piece is a constant 41px (odd) in a 40px (even) cell; centring an odd sprite in an even cell always leaves an exact 0.5px remainder, provably, for any choice of floor/round/ceil. `flame midnorth green`'s own frame width alternates 22/27/22/24/25px across its animation, landing exactly on-centre on the 3 frames that share the cell's parity and 0.5px off on the other 2. Recorded as **Q10** above. Fixed anyway: flame pieces now draw at their true fractional position instead of snapping to an integer pixel (`_draw_frame`'s new `snap` parameter, `false` for flame pieces only — every other sprite kind stays pixel-locked) |
| 3 | Powerups aren't destroyed by explosions | Two different claims tangled together. An exposed powerup on open ground WAS already destroyed by flame reaching it (confirmed: 9/9 fresh checks, and `tests/test_bomb.gd` already covered it) — correct, unchanged. But a powerup sitting on the BOMB'S OWN TILE was never checked at all: `_explode()` unconditionally burns the epicentre but `_propagate()`'s arm loop starts one cell OUT and never looks back at the bomb's own cell. A live player can't normally leave a powerup under themselves — `_collect_powerup()` picks it up the same tick — but a scattered pickup landing there after the bomb is already down, or a debug-editor drop, could. Fixed: the epicentre now checks and destroys a powerup on its own cell too |
| 4 | Bombs don't collide with each other | Rolling-bomb collision (`_bomb_blocked()`) was already correct — a kicked bomb stops against another bomb. The gap was in `_launch()`, shared by `punch_bomb()`/`throw_bomb()`: both computed a fixed destination (3 cells out) and clamped only to field bounds, with **no occupancy check** at all. A bomb mid-flight correctly can't collide (that's how a punch clears a brick), but nothing stopped it LANDING on top of another stationary bomb — two `Bomb_` records sharing one cell, with `bomb_at()`'s first-match lookup only ever seeing one of them. Fixed: a new `_landing_cell()` walks the throw/punch path and returns the furthest open cell, the same way a kicked bomb already stops short rather than passing through an obstacle |
| 5 | AI movement is very erratic | Real, and measured: `_any_open_move()`, the wander fallback, re-rolled a brand-new random direction from scratch every single tick — 20 times a second — with no persistence at all, so an idle bot visibly vibrated rather than walking anywhere. The original's own catch-all handler (table slot 7, `0x40A81F`, already cited in this file's own header comment) keeps a persisted facing and only reconsiders it 1-in-25 ticks; the port had never implemented that half. Measured on an open field, 300 ticks, nothing nearby: **75% of ticks changed direction before the fix, 5% after** — matching the original's ~1-in-25 within sampling noise |
| 6 | No death animation when there's no way to avoid a bomb | `sim.gd`'s own header comment promises `DEATH_TICKS` (100 ticks, 5s) is sized so every one of the 24 death animations gets to finish — but the round/match transition timer, `Match_.intermission_ticks()` (`SCREEN_MIN_SECONDS` × 20 = **60 ticks**), is shorter. `_check_round_over()` drops a dying player from `standing` the instant `kill()` sets `dying`, so a cornered kill — which is usually the round-deciding one, exactly "no way to avoid it" — could end the round on the same tick the animation started, and the next round tore the `Sim` down at 60 ticks, well before a longer animation (up to XPLODE4's 93 steps) finished. Fixed: new `Sim.anyone_dying()` (`p.dying and p.alive` — `dying` alone never clears, so testing it bare would stall the round forever after any death) gates both round-transition points in `main.gd` |

**And one live report that wasn't a bug at all.** "Gauntlet-thrown bombs
render the player instead of the bomb" — traced with a windowed probe all
the way through: `carried_by`, `pickup_pause`, and `flying` all transition
correctly, and the flying-bomb draw path correctly finds and draws
`PUNBOMB4.ANI`'s `punch east` sequence. That sprite is a small green
humanoid figure — because it is the disc's own art for a flying bomb in
this game's chibi-robot style, decoded straight from `PUNBOMB4.ANI` with
`tools/anifile.py` independent of the runtime pack, pixel-identical to what
renders. Every character in Atomic Bomberman is bomb-shaped; a flying bomb
apparently looks like a small bomberman rather than a plain sphere on the
original's own art, which reads as "the player" at a glance and is not a
defect anywhere in this pipeline.

## 3. Corrections made to this project's own documents

Kept because a retracted claim that leaves no trace tends to come back.

- **2026-09-03** — `docs/AUDIT.md` cited **VALUELST 36** as the resource behind
  Random Start. There is no resource 36. The right one is **40**, "default
  value of \"do we randomize player starting positions?\"", and its value is
  **1** — so the disc has that option ON, which is the opposite of what the
  port assumed while implementing it. The port now takes its default from the
  resource, and `tests/test_round.gd` and `tests/test_menu.gd` both assert
  resource 40 is 1 rather than hard-coding the behaviour.
- **2026-09-03** — `docs/AUDIT.md`, `docs/PLAN.md` and `docs/STATUS.md` all
  filed `MESSAGES.TXT` 900-928 as the missing part of the RESULTS screen. It is
  not part of any screen: message 900 says "Statistics **File**", and
  `BM95.EXE` writes it to disc at `0x40200C` with no drawing code in sight.
  Corrected in all three, and the port writes the file rather than drawing a
  list.

- **2026-09-02** — `docs/ORACLE.md` and `docs/PLAN.md` said Ancient Egypt has
  **43** arrows. It has **44**, 11 per heading, all on distinct cells. The
  original figure was an eyeball count of grep output; `tools/extras.py` was
  right and the documents were wrong. Both corrected, and
  `tests/test_extras.gd` now asserts the per-heading split, so a miscount shows
  up as an uneven distribution rather than only as a wrong total.
- **2026-09-02** — `tests/test_scheme.gd` initially asserted that no two
  players may share a start cell, and failed 36 times against real data. The
  assertion was wrong, not the data; see Q2.
- **2026-09-02** — the same suite expected 30 solid cells in `BASIC.SCH`. It
  has 35: five odd rows times seven odd columns. Arithmetic error in the test,
  not the parser.
- **2026-09-02** — `tests/render_recolour.gd` first asserted "the dominant
  channel of the render matches the dominant channel of the target". That is
  ill-defined for the four targets with two equal maxima: yellow is
  `(100,100,0)` and magenta `(100,0,100)`, so which channel "dominates" is
  decided by shading noise, and it failed on both while the render was
  correct. Replaced with "nearest of the ten targets by channel ratio", which
  is well-defined for every colour.
- **2026-09-02** — I first attributed the bot deaths (D14) to goal pathing not
  avoiding danger, and wrote that into `ai.gd`'s comments. Measuring the two
  halves separately showed the cause was entirely the idle-wander fallback.
  Both the comment and the test's note now say which half did what.
- **2026-09-02** — three test fixtures measured the wrong thing by choosing
  coordinates carelessly, and all three passed for the wrong reason until they
  were fixed: `test_specials.gd` put a player on the arrow cell it was testing
  (so it measured the player-blocking rule), `test_bots.gd` placed a bot and a
  powerup on odd/odd cells that the pillar grid makes solid (so the powerup was
  unreachable by construction), and `test_bots.gd`'s through-fire test put the
  powerup outside the AI's four-cell radius (so the goal was refused before
  pathing mattered).
- **2026-09-02** — `test_specials.gd`'s regrowth check grew only two bricks
  before asserting none was near a player, which made a violation about a
  one-in-four coincidence; mutation M44 deleted the clear-radius rule and went
  undetected. It now grows about thirty.
- **2026-09-02** — I claimed fpc_atomic's manifests would confirm the ANI
  decoder, and they did for 28 of 29 entries. The 29th, `die5`/`XPLODE5`, fpc
  records as 18 frames; the file has 17 FRAM chunks named EXF0000-EXF0016 and
  its `SEQ ` chunk lists 17 steps. **fpc_atomic's number is wrong**, not the
  decoder's.
- **2026-09-02** — `tests/test_pack.gd` first asserted that all eleven levels
  ship a `blank` tile. Only level 0 does; every other level's empty cells are
  the `FIELD<n>.PCX` floor showing through with nothing drawn over them. The
  renderer already handled that correctly and the assertion was wrong about
  the art.
- **2026-09-02** — `tests/render_field.gd` first sampled the first cell of each
  kind, which put the `blank` sample directly above the player's start. A
  110px-tall sprite over a 36px cell overhangs about three rows, so the sprite
  was drawn over the cell being measured. Correct rendering, bad fixture.
- **2026-09-02** — `tools/rss.py` grouped sounds by collapsing **runs of
  consecutive resource numbers**, and the docstring called those runs events.
  They are not. The rule splits an event at any gap — 451 is absent from
  `SOUNDLST`, so the 84 "good powerup" takes came out as two groups of 51 and
  33 — and it merges events that happen to abut, and it cannot see the
  hard-coded 142 boundary at all. Events are RANGES, named by the file's own
  "; N is the last X sound" comments. `EVENTS` now carries those bounds;
  `group_alternatives()` is kept, because "what runs exist in this file" is
  still a real question, but it is no longer what the port plays from.
- **2026-09-02** — the comment I first wrote on `Client.apply_match_state()`
  said a second round would otherwise "be rendered on the first round's map".
  That is not true today: the level does not change between rounds, and
  everything else about the field arrives in the snapshot, so the rebuild is a
  no-op in practice. Corrected to say what it actually guards — a level change
  — and Q9 records that nothing sends one yet.
- **2026-09-02** — `tools/fonts.py`'s first version read the `.FON` table at
  `0x18` as (offset, width) with no character shift. That fits the byte total —
  4912 needed of 4940 available — and renders text that is **nearly** right:
  every capital was legible and every lowercase letter was the letter after
  it. Three of the format's four parameters were wrong at once.

  What settled it was a tiling test rather than more reading: the glyphs must
  exactly fill the data region, so requiring each offset gap to equal the
  previous glyph's `ceil(width/8) * height` is a hard constraint. Over three
  table positions, both field orders and every row count from 8 to 19, one
  combination scores **190 of 190 pairs exact** and the next best 0.72. The
  character shift then came from rendering the alphabet and reading it.
  Totals now agree to the byte in both fonts: 4944 of 4944 and 2896 of 2896.
- **2026-09-02** — a botched `str.replace` in this session inserted a 2,688
  character block between **every character** of `main.gd`, because the slice
  that computed the search text used two indices in the wrong order and
  produced an empty string. The file went from 30 KB to 82 MB. It was
  recovered by removing every copy of the inserted block, which leaves the
  original characters intact — 30,479 bytes, parsing, one copy of every
  function. Recorded because the recovery only worked by luck of the failure
  mode, and because every edit in this file since counts its matches first.
- **2026-09-02** — `tools/rss.py`'s grouping has now been wrong TWICE, in
  opposite directions, and the binary settled it. Version one grouped by runs
  of consecutive numbers. Version two called that "wrong in both directions"
  and replaced it with the ranges the file's comments describe. `play_sound`
  (0x427961) walks forward from the number it is given and **stops at the first
  resource with no name** — so version one was right about gaps and version two
  was wrong to remove that. The named ranges are still needed as an upper
  bound, or `bomb_drop` would run on into the kicking sounds; they are just not
  the extent.

  The consequence is a fact about the original, not about the tool: **172
  recorded sounds are unreachable.** `451` is absent, so "you get a powerup" is
  400..450 and the 33 takes at 452..484 never play however plainly the comment
  says "499 is the last"; `1405` is absent, so "you are now AWESOME" is five
  takes and 139 more sit at 1406..1545 unused. Two single missing lines in
  SOUNDLST.RES strand 172 sounds — the same species of defect as its dangling
  `ZAHPU111` reference and MESSAGES.TXT's unclosed quote.
- **2026-09-02** — I recorded three AI functions as SELF-RECURSIVE from a
  call-graph pass. They are not: `tools/bmexe.py` approximates function
  boundaries by "every address that is the target of a direct call", so a call
  from a function whose entry is never a direct call target gets attributed to
  the preceding one, and a self-edge appears. Reading 0x40A59D showed it plain
  and not recursive at all. The tool's docstring states that limit; I used the
  output as though it did not.
- **2026-09-02** — `docs/PLAN.md` Phase 13 and `docs/BUGS.md` Q6 both said the
  exact transform was `pixel = palette[remap[index]]` — a straight lookup.
  Measuring first showed why it is not: the art is 15-bit with 978 distinct
  colours in `WALK.ANI` alone, so the lookup is a quantiser and using its
  output directly would reduce the sprites to 256 colours. The plan named the
  right tables and the wrong operation, which is the kind of thing a
  measurement catches and a plan does not.
- **2026-09-02** — `docs/ORACLE.md` said the disc ships **no level names as
  text**, and `scripts/core/const.gd` carried eleven names taken from the music
  filenames at SOUNDLST 1100-1110 on that basis. `MESSAGES.TXT` 150-160 ships
  them: Green Acres, Classic Green Acres, The Hockey Rink, Ancient Egypt, The
  Coal Mine, The Beach, Aliens, Haunted House, Under the Ocean, Deep Forest
  Green, Inner City Trash. The music-filename ordering was right — it has to
  be, since both are indexed by level — but the names were a stand-in for names
  that existed. `Messages.LEVEL_NAMES` is generated from the file now.
- **2026-09-02** — the same document, and Q6, said the `.RMP` colour remap
  files are **not on the disc**. They are: `0.RMP`-`9.RMP`, in the install
  root. Our copy of the disc was incomplete, which is a different thing from
  the disc not having them, and the entry did not distinguish the two. Q6
  above now carries the measured structure.
- **2026-09-02** — `docs/BUGS.md` Q9 said "resource `35` says 35 levels are
  defined". Resource **35** has the *value* **11**. The sentence confused the
  resource number with its value, which is the one mistake a table keyed by
  number invites; every other citation in these documents spells out both.
- **2026-09-02** — `tools/messages.py`'s first version raised on an unclosed
  quote, which stopped the whole generation on `63,"<Empty Server Slot>` —
  line 78 of the original's own file, missing its closing quote. Same class as
  SOUNDLST's dangling `ZAHPU111`: the disc's typo, not ours. Read as if the
  quote were there, and reported.
- **2026-09-02** — `Messages.fmt()` first converted `%u` to `%d` with
  `replace("%u", "%d")`. The padded form is `%02u`, in which `"%u"` is not a
  substring, so the clock's format string passed through unconverted and
  failed at the point something tried to draw it. It is a regex now, and
  `tests/test_messages.gd` asserts the padded case specifically.
- **2026-09-02** — `tools/ws_probe.py`'s first version reported "message id
  176" once per run and I took it for a protocol bug. It is the probe's own
  framing losing sync: a snapshot is about 3 KB and arrives fragmented, and a
  reader that returns each FRAME as a MESSAGE hands back a truncated snapshot
  and then reads the tail as a new one. Reassembly fixed most of it and one
  short message per forty snapshots survives. The server is exonerated by
  something independent of the probe: `tests/test_netplay.gd` compares the
  client's `state_hash()` to the server's on every snapshot and they are
  equal, which is impossible if a snapshot were arriving short. The limitation
  is now in the probe's docstring rather than in its output as a mystery.
- **2026-09-02** — three patches to Godot sources silently did nothing because
  the search text was indented with four tabs where the file has three (or two
  where the file has three). Two of them mattered: the `S_MATCH` decode arm was
  never added, so every field decoded as null, and the server's bot
  bookkeeping was never added, which is D15. Both were caught by tests written
  before the patches were verified, which is the only reason they were caught
  at all.
- **2026-09-02** — `tests/test_bomb.gd`'s flame-duration assertion was written
  to match the implementation rather than to resource 10, and so hid D1 above.
  Recorded here rather than only in D1 because the failure mode is the test
  suite's, not the simulation's: an assertion derived from the code under test
  proves nothing. Every timing assertion in that suite now reads its expected
  value from `Values_.V[...]`.
