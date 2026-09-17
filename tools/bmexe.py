#!/usr/bin/env python3
"""Static analysis of `BM95.EXE` — Track C, the algorithms the data cannot state.

`docs/ORACLE.md` §6: the disc's data files pin down every constant, every level
special, every scheme and every sound mapping, and say nothing about
*algorithms*. This is the tool for the algorithms. It is not a decompiler; it
is a set of measurements that locate code, so that a reading of that code can
be written down in `docs/BUGS.md` with an address beside it.

---------------------------------------------------------------------------
WHAT THE BINARY IS
---------------------------------------------------------------------------
PE32 for i386, GUI subsystem, 424,448 bytes, dated 11 July 1997. Sections named
`BEGTEXT` and `DGROUP` and a linker version of 2.18 make it **Watcom C/C++**,
which matters more than it looks: Watcom's default calling convention passes
the first arguments in **EAX, EDX, EBX, ECX**, not on the stack. Every
cross-reference below looks for `mov eax, <imm>` before a `call`, and would
find nothing at all if this were assumed to be MSVC.

Imports name the whole runtime: DDRAW, DSOUND, DINPUT, WINMM (joystick and
`timeGetTime`), WSOCK32.

---------------------------------------------------------------------------
THE THREE ACCESSORS, AND WHY THEY ARE THE WAY IN
---------------------------------------------------------------------------
Every tuning value the game uses is fetched through one function, by number.
Find that function and the numbers become a map: `docs/ORACLE.md` says what
resource 920 MEANS, and the call sites say WHERE it is used, which is the AI.

    0x412135  value_of(valueno) -> int          VALUELST.RES
    0x4124A4  message_of(id)    -> char *       MESSAGES.TXT
    0x427961  play_sound(base)                  SOUNDLST.RES

They were identified by scoring each function's constant arguments against the
three key sets parsed from the data files, and the result is not ambiguous:

    0x4124A4   167 of 167 distinct arguments are MESSAGES.TXT ids
    0x427961    20 of  21 are SOUNDLST.RES resource numbers
    0x412135    99 of 151 are VALUELST.RES numbers

`value_of` is confirmed by its own failure path rather than by that score,
which is the weakest of the three because the three number ranges overlap. It
bounds-checks against a count, indexes a dword table, and compares the entry
against **0xFFFFCFC7 = -12345**, the "absent" sentinel. On a miss it formats
`"invalid valueno requested: %u"` — the string sits at 0x458F82, next to
`"valuelst.res"` and `"open VALUELST.RES file!"` — and exits with code 0x69.
That is VALUELST.RES's own header warning, in code:

    DO NOT CHANGE the first number! if you do the program will exit to
    DOS because it cannot find a particular value.

---------------------------------------------------------------------------
LIMITS, STATED UP FRONT
---------------------------------------------------------------------------
  * The disassembly is a LINEAR SWEEP, restarted after each undecodable byte.
    On Watcom output that is mostly right, and it is wrong somewhere. 21 bytes
    in 356 KB did not decode. Any single instruction it reports could be a
    misaligned read of the middle of another one.
  * Function boundaries are approximated by "every address that is the target
    of a direct call". A function nobody calls directly — a vtable entry, a
    callback handed to Windows — is invisible, and code before the first call
    target is attributed to nothing.
  * A resource number computed rather than written as a constant (the
    `550 + powerup` cap lookups, the `130 + slot` disease durations) has no
    constant call site and does not appear in the cross-reference. That is why
    `--xref` prints how many of the 251 resources it accounts for.

Usage:
    tools/bmexe.py --info              the PE, its sections and imports
    tools/bmexe.py --accessors         re-derive the three accessors
    tools/bmexe.py --xref              resource number -> code addresses
    tools/bmexe.py --func 0x427859     disassemble one function
    tools/bmexe.py --callers 0x412135  who calls this
    tools/bmexe.py --strings AI        strings matching a pattern, with uses
"""

from __future__ import annotations

import argparse
import bisect
import collections
import json
import re
import sys
from pathlib import Path

IMAGE_BASE = 0x400000
VALUE_OF = 0x412135
MESSAGE_OF = 0x4124A4
PLAY_SOUND = 0x427961
MISSING_VALUE = 0xFFFFCFC7          # -12345

## What each address turned out to be, as it gets established. An entry here is
## a claim with a reading behind it in docs/BUGS.md, not a guess.
KNOWN = {
    0x412135: "value_of(valueno) -> int          VALUELST.RES lookup",
    0x4124A4: "message_of(id) -> char *          MESSAGES.TXT lookup",
    0x427961: "play_sound(soundno)               least-used take, random tie",
    0x427859: "start_sound(handle)               the concurrent-voice gate",
    0x45190A: "rand() -> 0..0x7fff               LCG 0x41C64E6D / 0x3039",
    0x4518D0: "sprintf",
    0x451900: "the rand() state pointer",
    # --- the AI, mapped. Priority table at 0x45BA78 (DGROUP, dumped directly):
    # 8 function pointers then a null terminator, walked by 0x40A1C6 via the
    # indirect `call dword ptr [edx]` at 0x40A404, first non-zero return wins;
    # running past the null falls through to the tail rather than panicking.
    # TABLE ORDER (the true priority order) is NOT memory order. None of the
    # 8 entries is a *direct* call target, which is the tool's own stated
    # limit above ("a function nobody calls directly... is invisible") and is
    # why 0x40A76E/0x40B046 were misread as 592/1069 instructions and as the
    # readers of resources 915/920 in an earlier pass: that function-length
    # and --xref containing-function both walk to the next *direct* call
    # target, which swallowed one or more of these indirectly-dispatched
    # functions. docs/BUGS.md Q5 has the full per-entry reading.
    0x40A140: "ai_choose_personality()           reads resource 900, at setup",
    0x40A1C6: "ai_think(player)                  called once per player/frame,"
              " dispatches through the table at 0x45BA78",
    0x40A59D: "ai_cell_is_open(x, y)             four predicates, see below",
    0x40A76E: "ai_cancel_blocked_dir(player)     57 ins; 1-cell lookahead,"
              " clears the chosen direction if cell_query() blocks it;"
              " helper, called from table entry idx2 (0x40B20F)",
    0x40B046: "ai_score_flee_dir(x, y)           137 ins; 4-ray scan up to"
              " distance 9, no queue and no propagation across the grid;"
              " helper, called from table entry idx6's own-bomb helper"
              " 0x40B594. This is NOT the AI's only search: the real"
              " breadth-first one is 0x40970B / 0x4092A1, below",
    0x40BD44: "ai_table[0](player)               63 ins, read in full;"
              " own-bomb reaction, gated on byte +0x5c, 1-in-2 chance",
    0x40BE02: "ai_table[1]_kick(player)          75 ins; scans 4 adjacent"
              " cells for a bomb, gated on byte +0x5b, 1-in-4 chance",
    0x40B20F: "ai_table[2]_route(player)         246 ins, read in full;"
              " the routing entry, and the ONLY caller of the AI's two"
              " breadth-first searches (0x40970B to pick a destination,"
              " 0x4092A1 to step toward one), depth limit 20",
    0x40AD8D: "ai_table[3]_blast_brick(player)   116 ins, reads resource 915"
              " (AI_BLAST_BRICK_CHANCE); not yet read in full",
    0x40ABED: "ai_table[4]_bomb_enemy(player)    128 ins, read in full;"
              " live-bomb count vs byte +0x56, Manhattan distance >= 3,"
              " 5-cell plus-shape scan, team check, 1-in-5 chance",
    0x40BAF5: "ai_table[5]_take_powerup(player)  167 ins, reads resource 920"
              " (AI_POWERUP_RADIUS), ends with ai_cell_is_open()",
    0x40B594: "ai_flee_own_bomb(player)          224 ins; bomb_at_tile() then"
              " ai_score_flee_dir(); helper, called from table entry idx6",
    0x40B8C2: "ai_table[6]_flee(player)          161 ins; calls"
              " ai_flee_own_bomb, ends with ai_cell_is_open()",
    0x40A81F: "ai_table[7]_wander(player)        117 ins; no resource, no"
              " gate — always-evaluated fallback: persisted facing (global"
              " +0x40), 1-in-25 reconsider, ai_cell_is_open() to commit",
    # --- the field and object queries the AI is built on
    0x422E48: "bomb_at_tile(x, y)                scans 100 x 152-byte records",
    0x425FB9: "cell_at(x, y) -> dword            1 outside the field",
    0x42708D: "cell_query(x, y) -> dword         0 outside the field",
    0x424D37: "influence_get(x, y) -> int        the influence map; 0"
              " outside the field. Its own error string is \"Influence"
              " size\" (0x45A2FE) beside \"GET (%u,%u) - \". Also the"
              " fourth term of ai_cell_is_open",
    0x424DFE: "influence_set(x, y, v)            the same map, \"SET (%u,%u)\"."
              " Five writers: 0x4242DE a bomb's tile and 0x4243B7 its arms,"
              " both (bomb +0x42 >> 16) + 100 = fuze left + 100; 0x426E29 and"
              " 0x42703A a burning cell, 1000; 0x4269F8 ahead of the closing"
              " wall, value_of(910)*10 + 100 decaying 10 a cell. Low = safe",
    # --- the AI's breadth-first machinery. Reached ONLY from table entry
    # idx2 (0x40B20F), which is why an earlier pass that scanned the
    # 0x40A1C6..0x40BD44 cluster for a queue/visited pattern concluded there
    # was no field-wide search: this lives below that range, at 0x409xxx.
    0x40970B: "ai_search_safest(x, y, limit, ..) 387 ins; breadth-first"
              " walker flood; goal is the lowest influence_get() reachable,"
              " stops early on an influence of 0 (a cell no fire reaches);"
              " returns first-step direction+1 and the cell it chose",
    0x4092A1: "ai_search_route(x, y, tx, ty, ..) 337 ins; the same flood"
              " toward a KNOWN cell; returns first-step direction+1, rounds"
              " used, and the widest frontier it reached. ret 0x10",
    0x4091A0: "ai_marks_clear()                  memcpy 0x640 B (20x20"
              " dwords) from the template at 0x45E724 to the mark grid at"
              " 0x45E0E4",
    0x409083: "ai_marks_get(x, y) -> int         1 outside the field, so an"
              " out-of-bounds cell reads as already-visited",
    0x40902A: "ai_marks_set(x, y, v)             walkers stamp direction+0xA",
    0x4091C9: "ai_walk_alloc() -> node *         first free of 100 x 24-byte"
              " records at [0x45ED68], zeroed; 0 when the frontier is full",
    0x42665C: "tile_x(pixel_x)",
    0x4266A3: "tile_y(pixel_y)",
    0x41F29B: "player_update(player)             per frame; skate/clog/hurry",
    0x410F81: "round_setup()                     reads 35, 900",
    0x41095A: "match_setup()                     reads 27, 46, 100, 310",
    0x426D06: "flame_?()                         reads resource 10",
    0x42331C: "bomb_arc/jelly()                  reads 660, 661, 667",
    0x42464B: "kick_bomb()                       reads resource 300",
    0x4248C6: "punch_bomb()                      reads resource 301",
    0x426704: "brick_regen()                     reads resource 695",
    0x4214BC: "player_or_bomb_init()             reads 41, 42",
}

## What the AI's walkability test is made of, from 0x40A59D. Kept here because
## it is the one piece of the AI that is fully read:
##
##     ai_cell_is_open(x, y):
##         if bomb_at_tile(x, y):   return 0      ; 0x422E48
##         if cell_at(x, y):        return 0      ; 0x425FB9, 1 out of bounds
##         if cell_query(x, y):     return 0      ; 0x42708D, 0 out of bounds
##         return !cell_predicate(x, y)           ; 0x424D37
##
## So a bomb BLOCKS the AI, and the two grid queries disagree about what lies
## outside the field — one reports blocked, the other clear — which only works
## because the first is checked first.
AI_IS_OPEN = (0x422E48, 0x425FB9, 0x42708D, 0x424D37)

## The object table 0x422E48 walks: 100 records of 152 bytes, pixel x at +0x1C,
## pixel y at +0x20, and a state word at +0x2E tested against 2 and 3.
OBJECT_TABLE = {"count": 100, "stride": 0x98, "x": 0x1C, "y": 0x20,
                "state": 0x2E}

## The resources whose call sites locate something the port had to reconstruct.
INTEREST = {
    8: "CONCURRENT_SOUNDS", 10: "FLAME_FRAMES", 27: "ENCLOSE_DEPTH",
    35: "LEVEL_COUNT", 41: "FUZE_FRAMES", 42: "START_SPEED",
    46: "WALL_DETONATES_BOMB", 90: "SKATE_BONUS", 91: "CLOG_PENALTY",
    100: "ROUND_SECONDS", 101: "HURRY_AT_SECONDS", 105: "DEATH_ANIM_COUNT",
    300: "KICKED_BOMB_SPEED", 301: "PUNCHED_BOMB_SPEED", 310: "WINS_TO_WIN",
    330: "CORNERHEAD_COUNT", 660: "PUNCH_ARC_BIG", 661: "PUNCH_ARC_SMALL",
    665: "PICKUP_PAUSE_FRAMES", 667: "JELLY_TURN_CHANCE",
    695: "REGEN_CLEAR_RADIUS", 900: "AI_PERSONALITIES", 910: "AI_LOOKAHEAD",
    915: "AI_BLAST_BRICK_CHANCE", 920: "AI_POWERUP_RADIUS",
}

_IMM = re.compile(r"^eax,\s*(0x[0-9a-f]+|\d+)$")


def _int(text: str) -> int:
    return int(text, 16) if text.startswith("0x") else int(text)


class Binary:
    """The parsed executable, its linear disassembly, and the indexes over it."""

    def __init__(self, path: Path):
        import lief
        self.lief = lief.parse(str(path))
        if self.lief is None:
            raise SystemExit(f"bmexe: cannot parse {path}")
        self.path = path
        self._text = None
        self.insns: list[tuple[int, int, str, str]] = []
        self.by_addr: dict[int, int] = {}
        self.entries: list[int] = []

    # -- sections and bytes ------------------------------------------------
    def section_of(self, va: int):
        for s in self.lief.sections:
            lo = IMAGE_BASE + s.virtual_address
            content = bytes(s.content)
            if lo <= va < lo + len(content):
                return s, lo, content
        return None, 0, b""

    def text(self):
        if self._text is None:
            for s in self.lief.sections:
                if s.name.startswith("BEGTEXT"):
                    self._text = (IMAGE_BASE + s.virtual_address,
                                  bytes(s.content))
                    break
        return self._text

    def cstring(self, va: int, limit: int = 200) -> str | None:
        _s, lo, content = self.section_of(va)
        if not content:
            return None
        off = va - lo
        end = content.find(b"\0", off, off + limit)
        raw = content[off:end if end >= 0 else off + limit]
        return raw.decode("latin-1")

    # -- disassembly -------------------------------------------------------
    def disassemble(self) -> None:
        """Linear sweep, restarted one byte on after every undecodable byte."""
        import capstone
        base, data = self.text()
        md = capstone.Cs(capstone.CS_ARCH_X86, capstone.CS_MODE_32)
        out = []
        off = 0
        self.skipped = 0
        while off < len(data):
            got = 0
            for i in md.disasm(data[off:], base + off):
                out.append((i.address, i.size, i.mnemonic, i.op_str))
                got += i.size
            if got == 0:
                self.skipped += 1
                off += 1
            else:
                off += got
        self.insns = out
        self.by_addr = {a: k for k, (a, _s, _m, _o) in enumerate(out)}
        self.entries = sorted({_int(o) for _a, _s, m, o in out
                               if m == "call" and o.startswith("0x")})

    def func_of(self, addr: int) -> int:
        i = bisect.bisect_right(self.entries, addr) - 1
        return self.entries[i] if i >= 0 else 0

    def body(self, addr: int, limit: int = 200):
        """Instructions from `addr` to the first `ret` at depth zero."""
        k = self.by_addr.get(addr)
        if k is None:
            return []
        out = []
        for a, s, m, o in self.insns[k:k + limit]:
            out.append((a, s, m, o))
            if m.startswith("ret"):
                break
        return out

    # -- the argument index ------------------------------------------------
    def eax_args(self) -> dict[int, list[tuple[int, int, int]]]:
        """target -> [(constant, call site, containing function)].

        Watcom puts the first argument in EAX, so the constant is whatever the
        nearest preceding `mov eax, imm` loaded. The search stops at any call,
        jump or return, because past one the register is not ours to read.
        """
        out = collections.defaultdict(list)
        for k, (a, _s, m, o) in enumerate(self.insns):
            if m != "call" or not o.startswith("0x"):
                continue
            target = _int(o)
            for back in range(1, 5):
                if k - back < 0:
                    break
                _a2, _s2, m2, o2 = self.insns[k - back]
                if m2 in ("call", "jmp", "ret", "retn"):
                    break
                if m2 == "mov":
                    mm = _IMM.match(o2)
                    if mm:
                        out[target].append((_int(mm.group(1)), a,
                                            self.func_of(a)))
                        break
        return out

    def callers(self, target: int) -> list[tuple[int, int]]:
        return [(a, self.func_of(a)) for a, _s, m, o in self.insns
                if m == "call" and o.startswith("0x") and _int(o) == target]


def key_sets(root: Path) -> dict[str, set[int]]:
    """The three number spaces, from the data files themselves."""
    sys.path.insert(0, str(root / "tools"))
    import rss
    out = {}
    vl = root / "tools" / "out" / "valuelist.json"
    if vl.is_file():
        out["VALUELST"] = {int(k) for k in json.loads(vl.read_text())["values"]}
    ms = root / "tools" / "out" / "messages.json"
    if ms.is_file():
        out["MESSAGES"] = {int(k) for k in json.loads(ms.read_text())}
    sl = root / "original-game" / "RES" / "SOUNDLST.RES"
    if sl.is_file():
        out["SOUNDLST"] = {n for n, _ in rss.parse_soundlist(sl)}
    return out


def cmd_info(bm: Binary) -> None:
    oh = bm.lief.optional_header
    print(f"{bm.path.name}: PE32 i386, entry 0x{oh.addressof_entrypoint:X}, "
          f"base 0x{oh.imagebase:X}")
    print(f"linker {oh.major_linker_version}.{oh.minor_linker_version} "
          f"— BEGTEXT/DGROUP section names and this version are Watcom C/C++, "
          f"so arguments come in EAX/EDX/EBX/ECX")
    print("\nsections:")
    for s in bm.lief.sections:
        print(f"  {s.name:<9} va 0x{s.virtual_address:06X} "
              f"raw {s.size:>7} at 0x{s.offset:05X}")
    print("\nimports:")
    for imp in bm.lief.imports:
        names = [e.name for e in imp.entries if e.name]
        print(f"  {imp.name:<16} {len(imp.entries):>3}  "
              f"{', '.join(names[:5])}{' ...' if len(names) > 5 else ''}")


def cmd_accessors(bm: Binary, root: Path) -> None:
    bm.disassemble()
    print(f"{len(bm.insns)} instructions, {bm.skipped} undecodable bytes, "
          f"{len(bm.entries)} call targets")
    keys = key_sets(root)
    args = bm.eax_args()
    scored = []
    for target, uses in args.items():
        imms = {c for c, _a, _f in uses if 0 < c < 4000}
        if len(imms) < 15:
            continue
        row = {name: len(imms & ks) for name, ks in keys.items()}
        scored.append((len(imms), target, row))
    scored.sort(reverse=True)
    print(f"\n{'function':<12} {'imms':>5}  " + "  ".join(
        f"{n:>9}" for n in keys))
    for n_imms, target, row in scored[:8]:
        note = KNOWN.get(target, "")
        print(f"0x{target:X}  {n_imms:>5}  " + "  ".join(
            f"{row[n]:>4}/{n_imms:<4}" for n in keys) + f"  {note}")
    print("\nvalue_of's failure path, which is what identifies it:")
    for a, _s, m, o in bm.body(VALUE_OF, 60):
        if "cfc7" in o.lower() or "0x458f82" in o.lower():
            print(f"  0x{a:X}  {m:<6} {o}")
    print(f"  0x458F82 -> {bm.cstring(0x458F82)!r}")
    print(f"  0x458FA0 -> {bm.cstring(0x458FA0)!r}")


def cmd_xref(bm: Binary, root: Path, only: set[int] | None) -> None:
    bm.disassemble()
    args = bm.eax_args()
    uses = collections.defaultdict(list)
    for const, site, func in args.get(VALUE_OF, []):
        uses[const].append((site, func))
    vals = {}
    vl = root / "tools" / "out" / "valuelist.json"
    if vl.is_file():
        vals = json.loads(vl.read_text())["values"]
    print(f"value_of() is called with {len(uses)} distinct constants at "
          f"{sum(len(v) for v in uses.values())} sites")
    if vals:
        print(f"VALUELST.RES defines {len(vals)}; the rest are read with a "
              f"computed number (550+powerup, 130+slot, 200+3*colour ...)")
    wanted = sorted(only) if only else sorted(INTEREST)
    print(f"\n{'res':>5} {'name':<22} {'value':>8}  where")
    for n in wanted:
        sites = uses.get(n, [])
        funcs = sorted({f for _s, f in sites})
        where = ", ".join(f"0x{f:X}" for f in funcs) if funcs else "—"
        print(f"{n:>5} {INTEREST.get(n, ''):<22} "
              f"{vals.get(str(n), '?'):>8}  {where}")


def cmd_func(bm: Binary, addr: int, limit: int) -> None:
    bm.disassemble()
    note = KNOWN.get(addr, "")
    print(f"--- 0x{addr:X} {note}")
    for a, _s, m, o in bm.body(addr, limit):
        tag = ""
        if m == "call" and o.startswith("0x"):
            tag = "  ; " + KNOWN.get(_int(o), "")
        elif o.startswith("0x") or "0x4" in o:
            for token in re.findall(r"0x[0-9a-f]{6,}", o):
                text = bm.cstring(_int(token), 60)
                if text and text.isprintable() and len(text) > 3:
                    tag = f'  ; "{text}"'
                    break
        print(f"  0x{a:X}  {m:<8} {o}{tag}")


def cmd_callers(bm: Binary, addr: int) -> None:
    bm.disassemble()
    calls = bm.callers(addr)
    funcs = collections.Counter(f for _s, f in calls)
    print(f"0x{addr:X} {KNOWN.get(addr, '')} — {len(calls)} calls from "
          f"{len(funcs)} functions")
    for func, n in funcs.most_common(30):
        print(f"  0x{func:X}  {n} call(s)  {KNOWN.get(func, '')}")


def cmd_strings(bm: Binary, pattern: str) -> None:
    rx = re.compile(pattern, re.I)
    for s in bm.lief.sections:
        content = bytes(s.content)
        lo = IMAGE_BASE + s.virtual_address
        for m in re.finditer(rb"[\x20-\x7e]{4,}", content):
            text = m.group().decode("latin-1")
            if rx.search(text):
                print(f"  0x{lo + m.start():X}  {text!r}")


def main(argv: list[str]) -> int:
    root = Path(__file__).resolve().parent.parent
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--exe", type=Path,
                    default=root / "original-game" / "BM95.EXE")
    ap.add_argument("--info", action="store_true")
    ap.add_argument("--accessors", action="store_true")
    ap.add_argument("--xref", action="store_true")
    ap.add_argument("--res", type=str,
                    help="with --xref: only these resource numbers")
    ap.add_argument("--func", type=str, help="disassemble one function")
    ap.add_argument("--limit", type=int, default=120)
    ap.add_argument("--callers", type=str)
    ap.add_argument("--strings", type=str)
    args = ap.parse_args(argv)

    if not args.exe.is_file():
        print(f"bmexe: need {args.exe}", file=sys.stderr)
        return 2
    bm = Binary(args.exe)

    did = False
    if args.info:
        cmd_info(bm); did = True
    if args.accessors:
        cmd_accessors(bm, root); did = True
    if args.xref:
        only = {int(x, 0) for x in args.res.split(",")} if args.res else None
        cmd_xref(bm, root, only); did = True
    if args.func:
        cmd_func(bm, int(args.func, 0), args.limit); did = True
    if args.callers:
        cmd_callers(bm, int(args.callers, 0)); did = True
    if args.strings:
        cmd_strings(bm, args.strings); did = True
    if not did:
        cmd_info(bm)
        print()
        cmd_accessors(bm, root)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
