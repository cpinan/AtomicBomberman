# analysis — reverse-engineering apparatus

Everything here exists to answer a question the original's data files cannot.
`RES/VALUELST.RES` pins every constant; it describes no algorithm. This
directory is where the algorithms get established.

Mirrors the role `analysis/` and `skyroads-port/` played in the SkyRoads port,
with one difference: there, the C reference had to be built before anything
could be measured. Here fpc_atomic is already a working reimplementation, so
the port bootstraps from it and this directory only has to correct it.

## Status

**Empty, and blocked.** `BM.EXE` is not in `original-game/`, which is the CD's
`DATA` tree only. Nothing in Track C can start until it is available.

## What goes here when it can

- `binary.md` — Track C C4. What `BM.EXE` actually is: Win32 PE or not, packed
  or not, which compiler and runtime. Written **first**, because it decides
  whether the rest of Track C is a week or a season, and no C6 work should be
  committed before it is answered.
- Disassembly artefacts, per-routine notes, and the addresses they were read
  at, so a later session can re-derive rather than re-trust.
- Whatever the parity harness needs that is not itself a tool.

`../ab-oracle/` is the C reference implementation, kept separate because it is
code that builds rather than notes that are read. Its constants come from
`tools/valuelist.py`'s JSON output so the two engines cannot drift on a number.

## What is already settled without a disassembly

Worth stating, because it is most of what a disassembly is usually needed for
and it cost one afternoon of reading data files:

- The frame rate — 20 Hz. `docs/ORACLE.md` §1.
- Every timing, speed, chance, cap and count. 251 resources.
- Every level special, at exact coordinates.
- All 67 schemes, in the real format.
- The 1051-entry sound event map.

## The four questions that remain

Listed in `docs/BUGS.md` Q5, in priority order. The first is the one that
matters most, because the original moves in pixels on 40x36 tiles and is
therefore anisotropic in tile terms — which means its corner-rounding rule
cannot be inferred from a speed value:

1. Movement and tile re-centring.
2. Powerup scatter — the counts are known, the placement is not.
3. Flame propagation order, and whether flames really stop on powerups.
4. AI — four knobs are in the data, the logic is in the executable.
