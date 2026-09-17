#!/usr/bin/env python3
"""Convert Atomic Bomberman `.RSS` sound files, driven by SOUNDLST.RES.

`.RSS` is headerless raw PCM. `SOUNDLST.RES` states the format in its own
header comment:

    These files all should have a .RSS extension and be raw 22khz Stereo 16bit
    signed, Intel-endian.

That is true of most of the disc but not all of it. 25 files have a size that
is not a multiple of 4, which stereo 16-bit cannot produce; all 25 divide
evenly by 2, so they are 16-bit MONO. 17 of them are gameplay sounds —
BMBTHRW*, BOMBBOUN, BOMBHIT*, PU*, TRANSOUT — so playing them as stereo would
halve their pitch and interleave two half-streams. Channel count is therefore
detected per file rather than taken from the header comment.

Verified: `1000.RSS` is 226,168 bytes, which at 22050 x 2 channels x 2 bytes is
2.564 s.

OPEN QUESTION, recorded in docs/BUGS.md Q7. The size test is decisive only when
the size is odd-of-4; it cannot see a mono file whose length happens to divide
by 4. Measured evidence that some do: BMDROP2 and BMDROP3 both show a
left/right correlation of exactly 1.000 while their channels are equal in under
2% of frames — the signature of consecutive samples of a single stream, not of
two channels. A genuinely mono-in-stereo file like MENUEXIT instead has L == R
in 100% of frames. So more files are probably mono than this detects. Settling
it needs BM.EXE, or an ear.

---------------------------------------------------------------------------
HOW SOUNDLST GROUPS ITS SOUNDS
---------------------------------------------------------------------------
A line maps a resource number to a base filename:

    100,bmdrop2         resource 100 plays SOUND/BMDROP2.RSS
    ;102,bmdrop4        commented out

The numbers are not a flat list: each EVENT owns a RANGE of them, and every
number in the range is an alternative take the game picks among so a repeated
action does not sound identical every time. The file says so itself, in
comments that name the end of each range —

    ; 139 is last jelly boing sound
    ; 299 is the last exploding bomb sound...
    ; 499 is the last standard "you get a powerup" sound
    ; 2299 is the last "we have a winner" sound number.

— and in one case says what the code does with a range:

    ; a solid tile slamming in place (after "hurry" is displayed)
    ; NOTE! the code is HARD-CODED to play one of the three below randomly.
    ; if you add more sounds below 142, they will not be used!!!

So `solid_drop` is 140..142 even though 140..146 are listed. That comment is
the only direct statement anywhere on the disc about how a range is consumed,
and it is why EVENTS below carries explicit bounds rather than deriving them.

HOW THE GROUP REALLY ENDS, from `BM95.EXE` rather than from the comments.
`play_sound` (0x427961) walks forward from the number it is given and stops at
the first resource with no name — see `event_takes` below. So:

  * A GAP ENDS THE GROUP. 451 is absent, so "you get a powerup" is 400..450 and
    the 33 takes at 452..484 are unreachable however clearly the comment says
    "499 is the last". `--check` lists every sound stranded this way.
  * The named ranges below are therefore an UPPER BOUND on each event, not its
    extent. They are still needed: without them nothing would stop `bomb_drop`
    at 119 and the group would run on into the kicking sounds.
  * The hard-coded 140..142 for the Hurry tiles is the one range the code
    genuinely bounds more tightly than the data — the file says so itself.

This corrects a correction. The first version of this tool grouped by runs of
consecutive numbers, which was right about gaps; the second replaced that with
the comment ranges, which was wrong about them. docs/BUGS.md has both.

---------------------------------------------------------------------------
WHAT THE PACK CONTAINS, AND WHY IT IS NOT EVERYTHING
---------------------------------------------------------------------------
The 23 events below reference 109.7 MB of audio, most of it in two events:
282 death taunts (39.5 MB) and 144 "you are now AWESOME" lines (19.7 MB). No
browser should download that to play a round.

The disc states its own budget. VALUELST resource 6:

    ; how much memory can be consumed by these cached sounds before we start
    ; tossing out old ones to make more room?
    6,7000000	; valid numbers are .5mb to 20mb

So 7 MB is how much sound the original itself intends to hold at once, and that
is the pack's budget too. Takes are chosen ROUND-ROBIN: every event gets its
first take before any event gets a second, so no event can end up silent
however tight the budget. What was dropped is printed, per event — a pack that
quietly shipped one take of everything would sound wrong in a way nobody would
trace back to here.

Usage:
    tools/rss.py --check                parse, verify sizes, write nothing
    tools/rss.py --pack                 build godot-project/data/packs/sfx.bin
    tools/rss.py --out DIR              also write WAVs there, for listening
    tools/rss.py --out DIR --all        convert every .RSS on the disc
"""

from __future__ import annotations

import argparse
import json
import re
import struct
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import abpk  # noqa: E402

SAMPLE_RATE = 22050
CHANNELS = 2
BYTES_PER_SAMPLE = 2
FRAME_BYTES = CHANNELS * BYTES_PER_SAMPLE

## VALUELST resource 6: the original's own cache budget for sound, in bytes.
CACHE_BUDGET = 7_000_000

# `100,bmdrop2` with optional whitespace. A leading ';' comments the line out,
# and SOUNDLST uses that to disable alternative takes.
ENTRY_RE = re.compile(r"^\s*(\d+)\s*,\s*([^\s,;]+)\s*$")

# Names the original deliberately points at nothing, with its own comments
# saying so: "dummy value; do not take this out!" and "just to prevent
# crashing". Not missing files.
PLACEHOLDERS = {"0", "XXX"}

# Event -> inclusive resource range, from SOUNDLST's own section comments. The
# name on the left is what scripts/core/types.gd's SoundEffect maps to; the
# comment is the disc's wording, so a disagreement is visible without opening
# the file.
EVENTS: dict[str, tuple[int, int]] = {
    "bomb_drop":     (100, 119),   # "dropping a bomb sounds"
    "bomb_kick":     (120, 129),   # "kicking a bomb sounds"
    "bomb_stop":     (130, 134),   # "stopping a bomb"
    "bomb_bounce":   (135, 139),   # "139 is last jelly boing sound"
    "solid_drop":    (140, 142),   # "HARD-CODED to play one of the three below"
    "bomb_punch":    (150, 159),   # "punching a bomb"
    "bomb_thrown":   (160, 169),   # "a punched/grabbed bomb bouncing along"
    "bomb_grab":     (170, 199),   # "when you grab a bomb"
    "bomb_explode":  (200, 299),   # "299 is the last exploding bomb sound"
    "player_died":   (300, 319),   # "you die in flames sounds"
    "round_win":     (320, 340),   # "we have a winner of the match" (short list)
    "death_anim":    (341, 349),   # "death anim sounds BASED on which anim"
    "trampoline":    (350, 359),   # "step on a trampoline"
    "bomb_hit_head": (360, 399),   # "you are stunned by a bomb landing on you"
    "powerup_good":  (400, 499),   # "499 is the last standard powerup sound"
    "powerup_bad":   (550, 599),   # "ploppy poop sounds"
    "death_taunt":   (701, 999),   # "999 is the last possible death taunt"
    "spooge":        (1200, 1299),  # "1299 is last huge string of bombs sound"
    "roulette_tick": (1300, 1309),  # "periodic roulette tick sound"
    "roulette_clap": (1310, 1319),  # "clapping people, happy sound"
    "roulette_buzz": (1320, 1329),  # "buzzer sound, you got the molasses
                                    #  roulette powerup (powerdown)"
    "warp":          (1330, 1339),  # "a warp-hole transfer sound"
    "awesome":       (1400, 1699),  # "1699 is the last AWESOME powerup sound"
    "draw":          (1700, 1999),  # "1999 is the last tie game/draw game sound"
    "match_win":     (2000, 2299),  # "2299 is the last we have a winner sound"
    "disease":       (2300, 2599),  # "2599 is the last generic disease sound"
    "hurry":         (2700, 2799),  # "2799 is last hurry up! sound"
}

# 320..340 and 2000..2299 open with the SAME three files — proud, theman,
# youwin1 — under the same description. 320 reads as the original short list
# and 2000 as the expanded one that replaced it. The port plays match_win for
# a match and round_win for a round, which is a use the disc does not state.
DUPLICATE_HEADS = {"round_win": "match_win"}

# How many alternative takes each event is worth keeping. Round-robin alone
# would hand a "we have a winner" line — played once a match — the same share
# of the budget as an explosion, and the voice events are also the long files:
# a taunt averages 140 KB where a bomb drop is 25 KB. So the long-tail voice
# events are capped first and the budget then fills whatever is left.
#
# These are judgement, not disc data. The disc's own position is that it can
# hold 200 cached effects (resource 5) inside 7 MB (resource 6), and it streams
# the rest off the CD, which a browser cannot do.
DEFAULT_TAKE_CAP = 8
TAKE_CAP: dict[str, int] = {
    "death_taunt": 4,
    "awesome": 2,
    "spooge": 3,
    "draw": 3,
    "match_win": 3,
    "round_win": 3,
    "hurry": 3,
}
DISEASE_TAKE_CAP = 2

# The twelve per-disease ranges, 3000 + 50*i, one per Types.Disease in order.
# SOUNDLST names each of them in a comment — molasses, crack, constipation,
# poops, short flame, crack poops, short fuze, swap 2 players, controls
# reversed, leprosy, invisible, duds — which is where DISEASE_NAMES came from.
DISEASE_BASE = 3000
DISEASE_STRIDE = 50
DISEASE_COUNT = 12


class RssError(Exception):
    pass


## SOUNDLST 1100-1110: one music track per level, in level order.
MUSIC_BASE = 1100
MUSIC_COUNT = 11

## And the screens have music of their own, which SOUNDLST names one by one
## with a comment above each:
##
##     1000 title      "title page music"
##     1010 menu       "main menu music"
##     1020 win        "music for input selection"   (the setup screen)
##     1030 lose       "game is over screen music"
##     1040 network    "join/start a network game"
##     1130 draw       "(used for end of a game, generally)"
##
## Names only, like the level tracks: these six come to 8 MB of raw PCM.
MUSIC_SCREENS = {
    "title": 1000,
    "menu": 1010,
    "setup": 1020,
    "gameover": 1030,
    "network": 1040,
    "draw": 1130,
}


def music_names(entries: list[tuple[int, str]]) -> list[str]:
    """The eleven level tracks, by level index.

    Names, not audio. The tracks total 120 MB of raw PCM — resource 6's whole
    sound budget is 7 MB — so they are never packed; this is what lets a
    desktop run find them on the disc it was given.
    """
    by_id = {n: name for n, name in entries}
    return [by_id.get(MUSIC_BASE + i, "") for i in range(MUSIC_COUNT)]


def screen_music(entries: list[tuple[int, str]]) -> dict:
    """The six screen tracks, by the port's own name for each screen."""
    by_id = {n: name for n, name in entries}
    out = {}
    for key, number in MUSIC_SCREENS.items():
        name = by_id.get(number, "")
        if name:
            out[key] = name
    return out


def parse_soundlist(path: Path) -> list[tuple[int, str]]:
    """[(resource_number, base_name)] in file order, comments dropped."""
    entries: list[tuple[int, str]] = []
    for lineno, raw in enumerate(
            path.read_text(encoding="latin-1").replace("\r", "").split("\n"),
            start=1):
        line = raw.replace("\x1a", "")
        head, _, _comment = line.partition(";")
        if not head.strip():
            continue
        m = ENTRY_RE.match(head)
        if not m:
            raise RssError(f"{path.name}:{lineno}: cannot parse {raw.strip()!r}")
        entries.append((int(m.group(1)), m.group(2)))
    return entries


def group_alternatives(entries: list[tuple[int, str]]) -> dict[int, list[str]]:
    """Collapse runs of consecutive resource numbers into one group.

    An honest answer to "what runs exist in this file" and nothing more — see
    the module docstring on why runs are not events. EVENTS is what the port
    plays from.
    """
    groups: dict[int, list[str]] = {}
    current = None
    previous = None
    for number, name in entries:
        if previous is None or number != previous + 1:
            current = number
            groups[current] = []
        groups[current].append(name)
        previous = number
    return groups


def event_takes(entries: list[tuple[int, str]],
                ranges: dict[str, tuple[int, int]] | None = None
                ) -> dict[str, list[str]]:
    """Event name -> its alternative takes, in resource order.

    THE GROUP ENDS AT THE FIRST GAP, not at the end of the range. That is what
    `BM95.EXE` does, at `play_sound` (0x427961):

        count = 0; i = soundno
        while (i < total && names[i] != 0) { count++; i++; }

    — it walks forward from the number it was asked for and stops at the first
    resource with no name. So the range bounds below are an upper limit and the
    data decides the real end.

    It matters. SOUNDLST has no `451`, and its comment says "499 is the last
    standard 'you get a powerup' sound" — so the author intended 400..499, but
    the code stops at 450 and **452..484 are unreachable** unless something
    asks for 452 directly. 33 recorded takes the original never plays.

    This is the second time this has been got wrong in this file, in opposite
    directions; docs/BUGS.md has both corrections.
    """
    ranges = EVENTS if ranges is None else ranges
    first: dict[int, str] = {}
    for number, name in entries:
        first.setdefault(number, name)
    out: dict[str, list[str]] = {}
    for event, (low, high) in ranges.items():
        takes: list[str] = []
        n = low
        while n <= high and n in first:
            takes.append(first[n])
            n += 1
        out[event] = takes
    return out


def unreachable(entries: list[tuple[int, str]]) -> dict[str, list[int]]:
    """Resource numbers inside an event's range that play_sound cannot reach.

    Anything past the first gap. Reported rather than silently dropped: they
    are sounds on the disc that the original never plays, which is a fact about
    the game and not about this tool.
    """
    present = {n for n, _ in entries}
    out: dict[str, list[int]] = {}
    for event, (low, high) in EVENTS.items():
        n = low
        while n <= high and n in present:
            n += 1
        rest = [k for k in sorted(present) if n < k <= high]
        if rest:
            out[event] = rest
    return out


def cap_takes(takes: dict[str, list[str]]) -> dict[str, list[str]]:
    """Truncate each event to TAKE_CAP takes. See that table for why."""
    out = {}
    for event, names in takes.items():
        cap = (DISEASE_TAKE_CAP if event.startswith("disease_")
               else TAKE_CAP.get(event, DEFAULT_TAKE_CAP))
        out[event] = names[:cap]
    return out


def disease_takes(entries: list[tuple[int, str]]) -> dict[str, list[str]]:
    """The twelve per-disease events, as `disease_0` .. `disease_11`."""
    ranges = {}
    for i in range(DISEASE_COUNT):
        base = DISEASE_BASE + i * DISEASE_STRIDE
        ranges[f"disease_{i}"] = (base, base + DISEASE_STRIDE - 1)
    return event_takes(entries, ranges)


def choose_within_budget(takes: dict[str, list[str]],
                         size_of, budget: int = CACHE_BUDGET
                         ) -> tuple[dict[str, list[str]], dict[str, int], int]:
    """Pick takes round-robin until `budget` bytes are spent.

    Round-robin, not event-by-event: every event gets take 1 before any event
    gets take 2, so a tight budget costs variety rather than making an event
    silent. Returns (chosen, dropped_count_per_event, bytes_used).

    `size_of(name)` returns a take's size in bytes, or None if it is not on the
    disc — the original's own SOUNDLST has dangling references (see main()).
    """
    chosen: dict[str, list[str]] = {e: [] for e in takes}
    dropped: dict[str, int] = {e: 0 for e in takes}
    # kbomb1 is both a kick and a punch. It is stored once, so it costs once —
    # counting it twice would leave the pack short of its own budget.
    taken: set[str] = set()
    used = 0
    depth = 0
    deepest = max((len(v) for v in takes.values()), default=0)
    while depth < deepest:
        for event in takes:
            names = takes[event]
            if depth >= len(names):
                continue
            name = names[depth]
            size = size_of(name)
            if size is None:
                dropped[event] += 1
                continue
            shared = name.lower() in taken
            if not shared and used + size > budget:
                dropped[event] += 1
                continue
            chosen[event].append(name)
            if not shared:
                taken.add(name.lower())
                used += size
        depth += 1
    return chosen, dropped, used


def duration_seconds(size_bytes: int) -> float:
    return size_bytes / (SAMPLE_RATE * FRAME_BYTES)


def detect_channels(size_bytes: int) -> int:
    """2 for stereo, 1 for mono, from the file size alone.

    A stereo 16-bit stream is 4 bytes per frame, so a size that is not a
    multiple of 4 cannot be stereo. This is decisive in that direction only —
    see the module docstring's open question.
    """
    return 1 if size_bytes % 4 else 2


def to_wav(raw: bytes, path: Path, channels: int = CHANNELS) -> None:
    """Wrap raw PCM in a 44-byte canonical WAV header. No resampling."""
    data_size = len(raw)
    frame_bytes = channels * BYTES_PER_SAMPLE
    byte_rate = SAMPLE_RATE * frame_bytes
    header = b"RIFF" + struct.pack("<I", 36 + data_size) + b"WAVEfmt "
    header += struct.pack("<IHHIIHH", 16, 1, channels, SAMPLE_RATE,
                          byte_rate, frame_bytes, 8 * BYTES_PER_SAMPLE)
    header += b"data" + struct.pack("<I", data_size)
    path.write_bytes(header + raw)


def build_pack(container: Path, on_disc: dict[str, Path],
               takes: dict[str, list[str]], budget: int,
               loose_dir: Path | None = None,
               entries: list[tuple[int, str]] | None = None) -> dict:
    """Write the sound container and return its manifest.

    The blobs are RAW PCM, not WAV. Godot's AudioStreamWAV takes raw samples
    plus a format, so the 44-byte header would be 44 bytes of nothing per
    sound and one more thing that could disagree with the manifest.
    """
    def size_of(name: str):
        p = on_disc.get(name.upper())
        return None if p is None else p.stat().st_size

    chosen, dropped, used = choose_within_budget(takes, size_of, budget)

    blobs: dict[str, bytes] = {}
    sounds: dict[str, dict] = {}
    for event in chosen:
        for name in chosen[event]:
            key = name.lower()
            if key in sounds:
                continue          # shared between events: kbomb1 is kick and punch
            raw = on_disc[name.upper()].read_bytes()
            channels = detect_channels(len(raw))
            blobs[f"{key}.pcm"] = raw
            sounds[key] = {
                "blob": f"{key}.pcm",
                "channels": channels,
                "frames": len(raw) // (channels * BYTES_PER_SAMPLE),
            }

    manifest = {
        "source": "original-game",
        "note": ("Generated by tools/rss.py from the original CD. "
                 "Interplay Productions (c) 1997 - never redistribute."),
        "format": {
            "sample_rate": SAMPLE_RATE,
            "bits": 8 * BYTES_PER_SAMPLE,
            "signed": True,
            "endian": "little",
        },
        "budget": {"bytes": budget, "used": used},
        "events": {e: chosen[e] for e in sorted(chosen)},
        # The eleven per-level tracks, SOUNDLST 1100-1110, by level. NAMES
        # only: the audio is 120 MB on the disc against a 7 MB budget, so it
        # can never travel in this container. A desktop run reads them from
        # the player's own copy of the game; see scripts/audio/music.gd.
        "music": music_names(entries or []),
        "music_screens": screen_music(entries or []),
        "dropped": {e: dropped[e] for e in sorted(dropped) if dropped[e]},
        "sounds": sounds,
    }
    size = abpk.write(container, manifest, blobs)
    manifest["_container_bytes"] = size

    if loose_dir is not None:
        loose_dir.mkdir(parents=True, exist_ok=True)
        (loose_dir / ".gdignore").write_text("", encoding="utf-8")
        for key, info in sounds.items():
            to_wav(blobs[info["blob"]], loose_dir / f"{key}.wav",
                   int(info["channels"]))
        (loose_dir / "sounds.json").write_text(
            json.dumps(manifest, indent=1), encoding="utf-8")
    return manifest


def main(argv: list[str]) -> int:
    root = Path(__file__).resolve().parent.parent
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--data", type=Path, default=root / "original-game")
    ap.add_argument("--out", type=Path, help="write WAVs here")
    ap.add_argument("--pack", action="store_true",
                    help="build godot-project/data/packs/sfx.bin")
    ap.add_argument("--budget", type=int, default=CACHE_BUDGET,
                    help="pack size budget in bytes (default: VALUELST 6)")
    ap.add_argument("--all", action="store_true",
                    help="convert every .RSS, not only the referenced ones")
    ap.add_argument("--check", action="store_true",
                    help="parse and verify, write nothing")
    args = ap.parse_args(argv)

    sound_dir = args.data / "SOUND"
    list_path = args.data / "RES" / "SOUNDLST.RES"
    if not sound_dir.is_dir() or not list_path.is_file():
        print(f"rss: need {sound_dir} and {list_path}", file=sys.stderr)
        return 2

    try:
        entries = parse_soundlist(list_path)
    except RssError as exc:
        print(f"rss: {exc}", file=sys.stderr)
        return 1
    groups = group_alternatives(entries)
    takes = event_takes(entries)
    stranded = unreachable(entries)
    takes.update(disease_takes(entries))
    full_takes = {e: list(v) for e, v in takes.items()}
    takes = cap_takes(takes)

    on_disc = {p.stem.upper(): p for p in sound_dir.glob("*.RSS")}
    print(f"rss: SOUNDLST references {len(entries)} sounds in "
          f"{len(groups)} consecutive runs; {len(on_disc)} .RSS files on disc")
    n_takes = sum(len(v) for v in full_takes.values())
    n_capped = sum(len(v) for v in takes.values())
    print(f"rss: {len(takes)} events own {n_takes} of them "
          f"({len(EVENTS)} named ranges plus {DISEASE_COUNT} diseases); "
          f"{n_capped} survive TAKE_CAP")
    if stranded:
        total = sum(len(v) for v in stranded.values())
        print(f"rss: {total} recorded sounds are UNREACHABLE — they sit past a "
              f"gap in their event's numbering, and play_sound stops at the "
              f"gap (BM95.EXE 0x427961):")
        for event in sorted(stranded):
            nums = stranded[event]
            print(f"rss:   {event}: {len(nums)} from {nums[0]} to {nums[-1]}")

    empty = sorted(e for e, v in takes.items() if not v)
    if empty:
        print(f"rss: {len(empty)} events have NO takes: {', '.join(empty)}")

    # Every referenced name must resolve, or an event would be silent at
    # runtime for a reason nobody would connect to the sound list.
    ref_upper = {name.upper() for _n, name in entries}
    missing = sorted(n for n in ref_upper if n not in on_disc
                     and n not in PLACEHOLDERS)
    if missing:
        # ZAHPU111 is a typo in the original's own sound list: ZAHPU11A,
        # ZAHPU11B, ZAHPU11C, ZAHPU114 and ZAHPU115 all exist on the disc but
        # ZAHPU111 does not. Resource 3070 is silent in the original game too,
        # so this is reported and then ignored rather than treated as our bug.
        print(f"rss: {len(missing)} referenced sounds are MISSING from the "
              f"disc: {', '.join(missing)}")
        print("rss: (these are bugs in the original's own SOUNDLST.RES)")

    # A size that is not a multiple of 4 cannot be stereo 16-bit, so those
    # files are mono. Reported rather than treated as an error: it is a fact
    # about the disc, and 17 of them are gameplay sounds.
    mono = []
    total_bytes = 0
    for name, path in sorted(on_disc.items()):
        size = path.stat().st_size
        total_bytes += size
        if detect_channels(size) == 1:
            mono.append(name)
    if mono:
        referenced_mono = sorted(set(mono) & ref_upper)
        print(f"rss: {len(mono)} files are 16-bit MONO, not stereo "
              f"({len(referenced_mono)} of them referenced): "
              f"{', '.join(referenced_mono[:8])}"
              f"{' ...' if len(referenced_mono) > 8 else ''}")

    print(f"rss: {total_bytes / 1e6:.0f} MB total, "
          f"{duration_seconds(total_bytes) / 60:.1f} minutes of audio")

    # Mono files are not an error, and the original's own dangling references
    # are not ours. --check passes on a disc that matches what we expect.
    if args.check:
        # The group rule, asserted where it has an effect. It cannot be checked
        # from the Godot side: TAKE_CAP truncates every affected event before
        # its gap is reached, so widening the rule changes nothing in the
        # shipped pack — measured, not assumed. That makes this the only place
        # a regression would show.
        # Checked on NUMBERS, not names. SOUNDLST reuses the same file across
        # events on purpose — `kbomb1` is resource 120 and 150, `proud` is 320
        # and 2000 — so a name does not identify a resource, and a first
        # version of this check that keyed by name reported eight false
        # failures.
        #
        # The property: an event's takes must be the numbers
        # [base, base + len), every one present, and base + len must be absent
        # or past the range. That is verifiable without re-running the walk
        # that produced them.
        present = {number for number, _name in entries}
        bad = []
        for event, (low, high) in EVENTS.items():
            run = len(full_takes.get(event, []))
            for i in range(run):
                if low + i not in present:
                    bad.append(f"{event} claims {run} takes but resource "
                               f"{low + i} is absent")
                    break
            else:
                nxt = low + run
                if nxt <= high and nxt in present:
                    bad.append(f"{event} stops at {nxt - 1} but resource "
                               f"{nxt} is present and in range")
        if bad:
            print(f"rss: {len(bad)} event(s) do not match what play_sound "
                  f"walks (BM95.EXE 0x427961 stops at the first gap):",
                  file=sys.stderr)
            for line in bad:
                print(f"rss:   {line}", file=sys.stderr)
            return 1
        print(f"rss: every event is a contiguous run from its base, which is "
              f"what play_sound walks")
        return 0

    if not args.pack and not args.out:
        print("rss: pass --pack to build the game's pack, --out DIR to write "
              "WAVs, or --check to verify only", file=sys.stderr)
        return 2

    if args.pack or args.out:
        container = root / "godot-project" / "data" / "packs" / "sfx.bin"
        container.parent.mkdir(parents=True, exist_ok=True)
        loose = args.out if args.out and not args.all else None
        manifest = build_pack(container, on_disc, takes, args.budget, loose,
                              entries)
        used = manifest["budget"]["used"]
        n_sounds = len(manifest["sounds"])
        n_dropped = sum(manifest["dropped"].values())
        print(f"rss: wrote {container} "
              f"({manifest['_container_bytes'] / 1e6:.2f} MB, "
              f"{n_sounds} sounds, {duration_seconds(used):.0f} s)")
        source = ("VALUELST resource 6" if args.budget == CACHE_BUDGET
                  else "--budget")
        print(f"rss: budget {args.budget / 1e6:.1f} MB "
              f"({source}), used {used / 1e6:.2f} MB")
        if n_dropped:
            worst = sorted(manifest["dropped"].items(),
                           key=lambda kv: -kv[1])[:6]
            print(f"rss: {n_dropped} takes DROPPED to fit — "
                  + ", ".join(f"{e} -{n}" for e, n in worst))
            print("rss: every event still has at least one take "
                  "(round-robin); see --budget to change this")
        if loose is not None:
            print(f"rss: also wrote {n_sounds} WAVs to {loose}")

    if args.all:
        args.out.mkdir(parents=True, exist_ok=True)
        for name in sorted(on_disc):
            raw = on_disc[name].read_bytes()
            to_wav(raw, args.out / f"{name.lower()}.wav",
                   detect_channels(len(raw)))
        print(f"rss: wrote all {len(on_disc)} WAVs to {args.out}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
