#!/usr/bin/env python3
"""Parse `MESSAGES.TXT` into a generated GDScript table.

This is the original's own string table, and it turns out to be the closest
thing on the disc to a specification for the game's screens. It settles several
things that were open until it arrived:

  * `150`-`160` are the ELEVEN LEVEL NAMES — Green Acres, Classic Green Acres,
    The Hockey Rink, Ancient Egypt, The Coal Mine, The Beach, Aliens, Haunted
    House, Under the Ocean, Deep Forest Green, Inner City Trash. Before this
    file, docs/ORACLE.md said the disc shipped no level names as text and the
    port used the music filenames from SOUNDLST instead.

    The ordering cross-checks: VALUELST's random-level lockout array disables
    `1152` — "too annoying to have control delays!" — and 152 is The Hockey
    Rink, the level with the 250 ms ice value; and `1156` — "too hard to see
    visually!" — and 156 is Aliens. `1150 + n` and `150 + n` are the same
    level, which also makes the lockout array 0-based with a spare entry.

  * `315`-`318` NAME THE FOUR ENCLOSEMENT DEPTHS: None, A Little, A Lot, All
    the way!. VALUELST resource 27 selects one of them and docs/BUGS.md
    recorded the 0..3 mapping as "not stated anywhere". It is stated here.

  * `250`-`268` are the SETTINGS SCREEN, label by label and in order, which is
    the option set the port's own menu should offer.

  * `220`-`224` and `230` are what a PLAYER SLOT can be: OFF, AI, KEY n, JOY n,
    NET, TEAM. Ten slots each holding one of those is the original's player
    model, and it is a better one than "N humans plus M bots".

  * `800`-`813` and `850`-`863` are FOURTEEN powerup names, long and short.
    Thirteen are placeable by a scheme; the fourteenth is `Clog`, the speed
    brake the roulette wheel hands out (VALUELST resource 91).

  * `900`-`928` are the STATISTICS FILE's own labels, with a Total and a Last
    Run column — so the statistics screen is a list of 19 counters and not art.

  * `500`-`548` are 49 default node names, one picked at random, which is what
    the original calls a player when you do not name one.

FORMAT. One entry per line, `id,text`, the text optionally in double quotes:

    150,Green Acres
    120,"(Match winner must score %u victories)"

Text can contain commas — `547,Light Me Up, Baby!` — so the split is on the
FIRST comma only. The file's own header is emphatic about the `%` placeholders:
"DO NOT MODIFY ANYTHING WITH A PERCENT SIGN (%) near it! This will CRASH THE
PROGRAM!!" They are preserved exactly and never reordered.

Output is `godot-project/scripts/core/messages.gd`, generated and gitignored,
the same arrangement as values.gd and extras.gd.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

ENTRY_RE = re.compile(r'^\s*(\d+)\s*,(.*)$')

# The named blocks worth exposing as something better than a number. Each is
# (first id, count) and the comment beside it is the file's own.
BLOCKS = {
    "LEVEL_NAMES": (150, 11),        # "names of the various levels defined"
    "ENCLOSE_NAMES": (315, 4),       # "; enclosement depth"
    "CONVEYOR_NAMES": (295, 3),      # Low / Medium / High
    "POWERUP_LONG": (800, 14),       # "DO NOT PUT ANY COMMAS IN ... (800 - 813)"
    "POWERUP_SHORT": (850, 14),      # "short description of the powerups"
    "KEY_NAMES": (1120, 6),          # Move Up .. Action 2
    "STAT_LABELS": (910, 19),        # the statistics file's counters
}

## id -> the name the port refers to it by. Only the ones it actually uses.
NAMED = {
    120: "MATCH_BY_WINS",
    121: "MATCH_BY_KILLS",
    149: "LEVEL_RANDOM",
    208: "WINS",
    209: "KILLS",
    211: "TO_WIN_MATCH",
    220: "SLOT_OFF",
    221: "SLOT_AI",
    222: "SLOT_KEY",
    223: "SLOT_JOY",
    224: "SLOT_NET",
    230: "SLOT_TEAM",
    250: "OPT_TEAM_PLAY",
    251: "OPT_RANDOM_START",
    253: "OPT_CONVEYOR_SPEED",
    254: "OPT_STOMPED_DETONATE",
    255: "OPT_WIN_BY_KILLS",
    256: "OPT_GOLD_BOMBERMAN",
    257: "OPT_ENCLOSE_DEPTH",
    258: "OPT_SCHEME_FILE",
    259: "OPT_PLAY_TIME",
    260: "OPT_ASSIGN_KEYBOARD",
    261: "OPT_DISEASES_DESTROYED",
    262: "OPT_LOST_NET_TO_AI",
    263: "OPT_DISABLE_MUSIC",
    265: "OPT_DEFINE_KEYS",
    60: "NET_GAMES_AVAILABLE",
    61: "NET_GAMES_NONE",
    62: "NET_GAME_ROW",
    65: "NET_MUST_SELECT",
    66: "NET_OUR_NODENAME",
    280: "TIME_INFINITE",
    281: "TIME_FORMAT",
    330: "PRESS_F1",
    650: "ROULETTE",
    790: "GOLD_PLAYER_HAS",
    791: "FOR_NEXT_MATCH",
    900: "STATS_HEADER",
    1105: "PRESS_KEY_FOR",
    1110: "KEY_ROW",
    1130: "RESTORE_DEFAULT_KEYS",
    1131: "DEFAULT_KEYS_RESTORED",
    1140: "KEY_IS",
    905: "STATS_COLUMNS",
    1100: "KEY_DEFINITIONS",
}

## The random node names, 500..548 in the file.
NODE_NAME_FIRST = 500
NODE_NAME_LAST = 548


class MessagesError(Exception):
    pass


def parse(path: Path) -> tuple[dict[int, str], list[str]]:
    """(id -> text, notes). Raises on a duplicate id; notes the disc's typos.

    The disc has one: line 78 is

        63,"<Empty Server Slot>

    with no closing quote. That is the original's file, not ours — the same
    class of thing as SOUNDLST's dangling ZAHPU111 reference — so it is read as
    if the quote were there and reported rather than treated as a failure.
    """
    out: dict[int, str] = {}
    notes: list[str] = []
    for lineno, raw in enumerate(
            path.read_text(encoding="latin-1").replace("\r", "").split("\n"),
            start=1):
        line = raw.replace("\x1a", "")
        if not line.strip() or line.lstrip().startswith(";"):
            continue
        m = ENTRY_RE.match(line)
        if not m:
            raise MessagesError(f"{path.name}:{lineno}: cannot parse "
                                f"{line.strip()!r}")
        ident = int(m.group(1))
        text = m.group(2)
        # Quoted text is taken from inside the quotes, which is the only way to
        # keep leading and trailing spaces — " No " and " Yes " rely on them.
        if text.lstrip().startswith('"'):
            body = text.lstrip()
            end = body.rfind('"')
            if end <= 0:
                notes.append(f"{path.name}:{lineno}: id {ident} has an "
                             f"unclosed quote (the disc's own typo)")
                text = body[1:].rstrip()
            else:
                text = body[1:end]
        else:
            text = text.rstrip()
        if ident in out:
            raise MessagesError(f"{path.name}:{lineno}: id {ident} again")
        out[ident] = text
    return out, notes


def gd_string(value: str) -> str:
    return '"' + value.replace("\\", "\\\\").replace('"', '\\"') + '"'


def emit(entries: dict[int, str], out_path: Path) -> None:
    lines: list[str] = []
    add = lines.append
    add("# GENERATED by tools/messages.py from the original's MESSAGES.TXT.")
    add("# Do not edit; do not commit. verify.sh regenerates it.")
    add("#")
    add("# The original's own string table. Every label the port shows comes")
    add("# from here rather than being written again in English, which is")
    add("# what makes the level names, the option names and the enclosement")
    add("# depth names the game's own words and not a guess at them.")
    add("#")
    add("# The file's header is emphatic: \"DO NOT MODIFY ANYTHING WITH A")
    add("# PERCENT SIGN (%) near it! This will CRASH THE PROGRAM!!\" The")
    add("# placeholders are preserved exactly; format() supplies the values.")
    add("class_name Messages")
    add("")
    add(f"## {len(entries)} strings, by their own id.")
    add("const M := {")
    for ident in sorted(entries):
        add(f"\t{ident}: {gd_string(entries[ident])},")
    add("}")
    add("")

    for name, (first, count) in BLOCKS.items():
        missing = [first + i for i in range(count) if first + i not in entries]
        if missing:
            raise MessagesError(
                f"{name} wants {first}..{first + count - 1}, missing {missing}")
        add(f"## {name.lower().replace('_', ' ')}, ids {first}"
            f"..{first + count - 1}.")
        add(f"const {name} := [")
        for i in range(count):
            add(f"\t{gd_string(entries[first + i])},")
        add("]")
        add("")

    add("## The ids the port names rather than numbers.")
    for ident, name in sorted(NAMED.items(), key=lambda kv: kv[1]):
        if ident not in entries:
            raise MessagesError(f"{name} wants id {ident}, which is absent")
        add(f"const {name} := {gd_string(entries[ident])}")
    add("")

    node_names = [entries[i] for i in range(NODE_NAME_FIRST, NODE_NAME_LAST + 1)
                  if i in entries]
    add("## \"here are some random node names, one of which will be default\"")
    add("const NODE_NAMES := [")
    for name in node_names:
        add(f"\t{gd_string(name)},")
    add("]")
    add("")
    add("")
    add("## One string by id, or a visible marker rather than \"\": a missing")
    add("## label should look wrong on screen, not look like nothing.")
    add("static func get_text(ident: int) -> String:")
    add("\treturn String(M.get(ident, \"<%d?>\" % ident))")
    add("")
    add("")
    add("## Format one of these strings.")
    add("##")
    add("## The placeholders are C's: %u for an unsigned, %02u for a padded")
    add("## one. GDScript's % operator knows %d and %s and fails on either")
    add("## with \"incomplete format in operator\", so the conversion happens")
    add("## HERE, at format time, and never in the table — the file's own")
    add("## header forbids modifying anything near a percent sign, and the")
    add("## stored text stays exactly what the disc says.")
    add("##")
    add("## A regex and not replace(\"%u\", \"%d\"): the padded form is")
    add("## \"%02u\", where \"%u\" is not a substring, so a plain replace")
    add("## silently leaves it and the failure lands on whatever draws it.")
    add("## MESSAGES.TXT 281 — the clock — is exactly that case.")
    add("static var _unsigned := RegEx.new()")
    add("")
    add("static func fmt(text: String, args: Variant) -> String:")
    add("\tif _unsigned.get_pattern().is_empty():")
    add("\t\t_unsigned.compile(\"%([-+ 0#]*[0-9]*(?:\\\\.[0-9]+)?)u\")")
    add("\treturn _unsigned.sub(text, \"%${1}d\", true) % args")
    out_path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main(argv: list[str]) -> int:
    root = Path(__file__).resolve().parent.parent
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--data", type=Path, default=root / "original-game")
    ap.add_argument("--out", type=Path,
                    default=root / "godot-project" / "scripts" / "core"
                    / "messages.gd")
    ap.add_argument("--json", type=Path,
                    default=root / "tools" / "out" / "messages.json")
    ap.add_argument("--check", action="store_true",
                    help="parse and report, write nothing")
    args = ap.parse_args(argv)

    path = args.data / "MESSAGES.TXT"
    if not path.is_file():
        print(f"messages: need {path}", file=sys.stderr)
        return 2
    try:
        entries, notes = parse(path)
    except MessagesError as exc:
        print(f"messages: {exc}", file=sys.stderr)
        return 1

    print(f"messages: {len(entries)} strings, ids {min(entries)}..{max(entries)}")
    placeholders = sum(1 for v in entries.values() if "%" in v)
    print(f"messages: {placeholders} carry a % placeholder")
    for note in notes:
        print(f"messages: {note}")
    print("messages: levels — " + ", ".join(
        entries[150 + i] for i in range(min(4, 11))) + ", ...")

    if args.check:
        # The blocks are checked even on --check: a gap in one of them means a
        # disc that does not match what the port expects, and that should fail
        # here rather than as a blank label at runtime.
        for name, (first, count) in BLOCKS.items():
            missing = [first + i for i in range(count)
                       if first + i not in entries]
            if missing:
                print(f"messages: {name} is missing {missing}", file=sys.stderr)
                return 1
        print("messages: every named block is complete")
        return 0

    args.out.parent.mkdir(parents=True, exist_ok=True)
    try:
        emit(entries, args.out)
    except MessagesError as exc:
        print(f"messages: {exc}", file=sys.stderr)
        return 1
    print(f"messages: wrote {args.out}")
    args.json.parent.mkdir(parents=True, exist_ok=True)
    args.json.write_text(json.dumps({str(k): v for k, v in sorted(
        entries.items())}, indent=1), encoding="utf-8")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
