# STATUS — Atomic Bomberman Godot port

_Last updated: 2026-09-03 · no git repository yet (`godot-project/` is where it
will live, per `docs/PLAN.md` §3) · nothing committable_

The game starts, plays and finishes on the original's own screens. What it is,
screen by screen, is in `docs/AUDIT.md`; how it was built, in `docs/PLAN.md`;
what the disc says, in `docs/ORACLE.md`; every defect and open question, in
`docs/BUGS.md`; the extraction toolkit, in `tools/README.md`.

## Next action

**Read the content of `README.BM`, `NETWORK.BM` and `EDITOR.BM`** — now
extracted to `tools/out/bmtext.json`, or `tools/bmtext.py --dump README`.

They are parsed but not *read*. `INPUT.BM` is thirty lines and answered five of
the last seven defects a player found; unread text files remain the cheapest
evidence on the disc, cheaper than the disassembly. Read: `INPUT`, `OPTIONS`,
`ROULETTE`, `CREDITS`, `MANUAL`. Unread: `README` (398 lines), `NETWORK` (116),
`EDITOR` (154), `HIGHMEM`, `LOWMEM`.

Then, in order of value: play it again (two sittings produced 34 defects with
the suites green throughout); adopt the original's movement (`docs/BUGS.md`
Q5.1 — read out line by line, deliberately not adopted); draw a replacement art
set (`docs/ART.md` — the only path to a distributable build); the powerup
scatter's sampling (Q5.2); campaign polish and a score screen.

## State

- **`tools/verify.sh` is green: 6108 checks, 37 suites**, plus a parse pass over
  all 74 `.gd` files, a server-plus-two-clients WebSocket match, a real run that
  writes the statistics file, and the art kit round-tripped.
- **211 of 213 mutations are caught**, three recorded as EQUIVALENT.
- **The disc is fully extracted and the claim is checkable.**
  `tools/extract.py` runs 16 stages; `tools/inventory.py` classifies all 2 454
  files with **0 TODO**, and a file matching no rule is a hard error.
  Cross-checked against the installer's own `MAX.TXT`: it lists 2 293 files and
  our copy has **every one**.
- **Every asset decodes.** 95 of 95 `.ANI` (was 94 — `CLASSICS.ANI` is `CIMG`
  type 0x0b, 8-bit paletted, cracked 2026-09-03), 62 PCX, 3 fonts (FONT0 too),
  67 schemes, 3 campaigns, 10 text screens, 2 027 `.RSS`.
- **`inventory.py --deep` separates "read" from "shipped"**: the pack carries 64
  of 95 animations and 81 sound takes on purpose — `pack_assets.py` selects what
  the game draws, `rss.py` caps takes per event. Both numbers print together so
  neither hides the other.
- **The whole simulation is integer-only** (centipixels), one container format
  (`abpk`), and everything the game says is the game's own words via three
  generated, gitignored tables.
- **The art can be replaced**: `tools/artpack.py --template` / `--check` /
  `--build` / `--pack-overlay`. `docs/ART.md`.

## In flight

Known gaps, each with a file to open. All written up in `docs/BUGS.md` D28.

- `godot-project/scripts/sim/sim.gd:613` `_player_action()` — **hold-to-carry**.
  `MANUAL.BM` says a bomb is carried by grabbing and *holding* Drop Bomb; the
  port grabs on a second press. Needs `scripts/app/keysets.gd:192` Action 1 to
  become a held state as well as an edge.
- `godot-project/scripts/app/main.gd:1437` `_input()` — **three of MANUAL.BM's
  six in-game keys are missing**: F1 (help), Alt-N (network stats to
  NETSTATS.TXT), Alt-D (misc info). F1 is deliberately free; the debug grid
  moved to F2. Alt-N's data mostly exists already.
- `godot-project/scripts/sim/sim.gd:926` `kill()` — **SOUNDLST 341-349**, nine
  sounds for 24 death animations, mapping unrecovered, so nothing plays rather
  than the wrong thing.
- `tools/pack_assets.py:65` `WANTED` — **cornerhead animations unpacked**
  (`CORNER0..7`, VALUELST **330**, not 308). Not decoration: `TOOLS/ANIMS.TXT`
  says this is a "character getting trapped, ready to die" state, distinct
  from the death animation. Trigger in `BM95.EXE` not yet located —
  `docs/BUGS.md` Q3. `APPLBITE`/`NUCKBLOW`/`ZEN` (121 unnamed frames each,
  a different size) are a separate, still-unexplained family.
- `godot-project/scripts/net/server.gd` — **INPUT.BM's server override** ('o' or
  '0' to override a client's player selection). Nothing implements it.

## Verify

```bash
tools/verify.sh                  # 6108 checks, 37 suites, 74 files parsed
EXPORT=1 tools/verify.sh         # and the two export presets, with the .pck probed
tools/extract.py                 # 16 stages: read the disc, write every output
tools/extract.py --check         # same, writing nothing
tools/inventory.py               # the census — 0 TODO, or it exits non-zero
tools/inventory.py --deep        # what reaches the packs, vs what is merely read
cd godot-project && ../tools/mutate.py   # mutation run
```

`AB_DATA` overrides where the disc is found (default `./original-game`);
`AB_PACK` and `AB_SFX` override the packs. Without game data the data-driven
suites skip and the app falls back to a built-in grid.

## Open questions

- **Pixels.** The art pipeline is proven; a replacement set has to be drawn by a
  person. Until then no build is distributable. `docs/ART.md`.
- **A pad.** The gamepad layer is tested against synthesised events only; nobody
  has held a real controller. `JOY` appears in the slot list only when one is
  plugged in — check that first.
- **`.AAF` is not cracked.** Five antialiased fonts recovered from
  `INSTALL.DAT`. Header, height field and the 256-record table (`u32`, `u16`
  width, `u16` height) are established; where a glyph's pixels live is not.
  Zero port value — they are the *setup program's* fonts. `docs/ORACLE.md` §9.
- **Unexplained, and labelled as such:** `LEVELS.DAT` (four bytes),
  `INSTALL.DAT`'s `0x40` flags and `0x82FCF318` stamp.
- **Left to existing tools on purpose:** MVE video/audio (both movies sliced out
  as `.mve`; ffmpeg and VLC read them), Director Lingo bytecode.

## Do not redo

- **The default keys are `INPUT.BM`'s, not an invention** — cursor keys + Space
  + Enter, and R/D/F/G + S + A. Do not "improve" them to WASD. Bump
  `CONFIG_VERSION` in `user://keys.cfg` if they ever change.
- **The status panel is 42 px** (`Const_.HUD_H`), measured from all eleven
  backgrounds; `FIELD_Y_OFF` is 68 and is right.
- **Flame frames are centred on the cell**, never anchored on their hotspot.
- **`sheet_with_sequence()` is the only way to reach a death animation** — the
  24 are spread over seventeen XPLODE files and the mapping is not by number.
- **`test_pack.gd` must assert sheet contents before `_test_overlay`**, which
  swaps the bomb sheet for a stand-in.
- **A game left open in another window breaks `test_discovery.gd`** — the LAN
  beacon port is shared; the suite filters by port now. Kill stray headless
  Godot processes before blaming the extraction.
- **The movement algorithm is read but deliberately not adopted** (Q5.1): every
  other system and the network hash sit on the movement this port has. Its own
  phase, with the parity harness watching.
- **`BONUS.PCX` is cut art**; `flame.ani` is superseded by `mflame.ani`.
- **Do not exclude a disc file on the strength of its extension.** Six were, and
  five of those exclusions were wrong: `INSTALL.DAT` is an LZSS archive holding
  18 files found nowhere else, `THEME.ZIP` holds 40 pieces of original art,
  `BMINTRO.EXE` embeds the game's intro movie, `TRAILER.SFA` is a second movie,
  `BM95.RES` has five bitmaps. `docs/ORACLE.md` §8.
- **`fonts.py`'s flags word is not a layout switch** — FONT0 was skipped for
  years on that basis and decodes fine. Gate on the tiling test.
