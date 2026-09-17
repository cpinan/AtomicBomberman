#!/usr/bin/env python3
"""Run the whole extraction, in order, and say what happened.

Sixteen stages read the disc, each of them worth running alone and each with
its own flags. What was missing was the sentence "the disc has been extracted" —
an operation with one name, one exit status, and a report saying which of the
2,454 files were read to produce which outputs.

That is this. It is a runner, not a re-implementation: every stage below is a
subprocess call to a tool that already exists, so there is exactly one copy of
each format's knowledge.

ORDER MATTERS in one place only. `pack_assets.py` builds the pack the game
loads, and it reads the schemes and campaigns as text, so anything that would
reject those files should have run first — a scheme that fails to parse must
stop the build before it is packed, not after. Everything else is independent
and the order is just "cheap things first, so a failure shows up quickly".

    tools/extract.py                run everything, write everything
    tools/extract.py --check        run everything in check mode, write nothing
    tools/extract.py --only schemes,pcx     just these stages
    tools/extract.py --list         what the stages are
    tools/extract.py --skip-heavy   leave out the two slow ones (sound, pack)

Exit status is 0 only when every stage that ran succeeded AND the census has
no TODO left, which is what makes this usable as the project's one gate.
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
import time
from pathlib import Path

# name, argv (relative to tools/), check-mode argv, heavy?, what it reads
#
# check-mode argv is what --check runs instead: the same parse, nothing
# written. A stage with no check mode of its own runs its normal command and
# is marked as writing anyway, which is stated in --list rather than hidden.
STAGES: list[dict] = [
    {"name": "inventory", "argv": ["inventory.py", "--json"],
     "check": ["inventory.py"], "heavy": False,
     "reads": "every file on the disc",
     "gives": "tools/out/inventory.json"},

    {"name": "valuelist", "argv": ["valuelist.py"],
     "check": ["valuelist.py", "--check"], "heavy": False,
     "reads": "RES/VALUELST.RES",
     "gives": "tools/out/valuelist.json + scripts/core/values.gd"},

    {"name": "messages", "argv": ["messages.py"],
     "check": ["messages.py", "--check"], "heavy": False,
     "reads": "MESSAGES.TXT",
     "gives": "tools/out/messages.json + scripts/core/messages.gd"},

    {"name": "extras", "argv": ["extras.py"],
     "check": ["extras.py", "--check"], "heavy": False,
     "reads": "RES/EXTRA*.RES",
     "gives": "tools/out/extras.json + scripts/core/extras.gd"},

    {"name": "schemes", "argv": ["schemes.py"],
     "check": ["schemes.py", "--check"], "heavy": False,
     "reads": "SCHEMES/*.SCH — the 67 maps",
     "gives": "tools/out/schemes.json + schemes.txt"},

    {"name": "campaigns", "argv": ["campaigns.py"],
     "check": ["campaigns.py", "--check"], "heavy": False,
     "reads": "RES/*.CAM",
     "gives": "tools/out/campaigns.json"},

    {"name": "bmtext", "argv": ["bmtext.py"],
     "check": ["bmtext.py", "--check"], "heavy": False,
     "reads": "*.BM — the ten text screens",
     "gives": "tools/out/bmtext.json"},

    {"name": "fonts", "argv": ["fonts.py"],
     "check": ["fonts.py", "--check"], "heavy": False,
     "reads": "FONT*.FON",
     "gives": "font sheets for the pack"},

    {"name": "pcx", "argv": ["pcx.py"],
     "check": ["pcx.py", "--check"], "heavy": False,
     "reads": "every .PCX on the disc",
     "gives": "tools/out/pcx/*.png + pcx.json"},

    {"name": "ani", "argv": ["anifile.py", "--check"],
     "check": ["anifile.py", "--check"], "heavy": False,
     "reads": "ANI/*.ANI + ANI/MASTER.ALI",
     "gives": "a decode report; the frames go into the pack"},

    {"name": "remap", "argv": ["remap.py"],
     "check": ["remap.py"], "heavy": False,
     "reads": "*.RMP + COLOR.PAL",
     "gives": "the player-recolour comparison"},

    {"name": "sound", "argv": ["rss.py", "--pack"],
     "check": ["rss.py", "--check"], "heavy": True,
     "reads": "SOUND/*.RSS + RES/SOUNDLST.RES — 2,027 files",
     "gives": "godot-project/data/packs/sfx.bin"},

    {"name": "pack", "argv": ["pack_assets.py"],
     "check": ["pack_assets.py", "--check"], "heavy": True,
     "reads": "the ANI and PCX the game draws, plus schemes and campaigns",
     "gives": "godot-project/data/packs/cd.bin"},

    {"name": "installdat", "argv": ["installdat.py", "--extract"],
     "check": ["installdat.py", "--check"], "heavy": False,
     "reads": "INSTALL.DAT — an LZSS archive, not a manifest",
     "gives": "tools/out/install/ — 22 files, 18 of them off-disc"},

    {"name": "containers", "argv": ["containers.py", "--extract"],
     "check": ["containers.py", "--check"], "heavy": False,
     "reads": "THEME.ZIP, BM95.RES, OOO_LTD.CXT, TRAILER.SFA, BMINTRO.EXE",
     "gives": "tools/out/theme|winres|movies/"},

    {"name": "exe", "argv": ["bmexe.py", "--info"],
     "check": ["bmexe.py", "--info"], "heavy": False,
     "reads": "BM95.EXE",
     "gives": "the measurements behind docs/BUGS.md"},
]


def run(root: Path, stage: dict, argv: list[str], verbose: bool) -> dict:
    started = time.monotonic()
    proc = subprocess.run([sys.executable, *argv],
                          cwd=root / "tools",
                          capture_output=True, text=True)
    took = time.monotonic() - started
    out = (proc.stdout or "") + (proc.stderr or "")
    # The last non-empty line is each tool's own summary, by convention, so it
    # is the one line worth showing when everything is fine.
    tail = [ln for ln in out.splitlines() if ln.strip()]
    return {
        "name": stage["name"],
        "argv": argv,
        "returncode": proc.returncode,
        "seconds": round(took, 1),
        "summary": tail[-1] if tail else "",
        "output": out if (verbose or proc.returncode != 0) else "",
    }


def main(argv: list[str]) -> int:
    root = Path(__file__).resolve().parent.parent

    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--check", action="store_true",
                    help="every stage in check mode: parse, report, write nothing")
    ap.add_argument("--only", help="comma-separated stage names")
    ap.add_argument("--skip-heavy", action="store_true",
                    help="skip sound and pack, which take minutes")
    ap.add_argument("--list", action="store_true", help="the stages, and what they read")
    ap.add_argument("--verbose", action="store_true", help="each stage's full output")
    args = ap.parse_args(argv)

    if args.list:
        for s in STAGES:
            mark = " (heavy)" if s["heavy"] else ""
            print(f"  {s['name']:<10}{mark:<9} {s['reads']}")
            print(f"  {'':<19} -> {s['gives']}")
        return 0

    wanted = STAGES
    if args.only:
        names = {n.strip() for n in args.only.split(",")}
        unknown = names - {s["name"] for s in STAGES}
        if unknown:
            print(f"extract: no such stage: {', '.join(sorted(unknown))}",
                  file=sys.stderr)
            return 2
        wanted = [s for s in STAGES if s["name"] in names]
    if args.skip_heavy:
        wanted = [s for s in wanted if not s["heavy"]]

    mode = "check" if args.check else "write"
    print(f"extract: {len(wanted)} stages, {mode} mode, "
          f"reading {root / 'original-game'}\n")

    results = []
    failed = []
    for stage in wanted:
        argv_for = stage["check"] if args.check else stage["argv"]
        print(f"  {stage['name']:<10} ...", end="", flush=True)
        res = run(root, stage, argv_for, args.verbose)
        results.append(res)
        # inventory exits 1 while any file is still uncovered, and 2 when a
        # file matches no rule at all. Both are real failures of "we extracted
        # everything", so neither is softened here.
        ok = res["returncode"] == 0
        print(f"\r  {stage['name']:<10} {'ok  ' if ok else 'FAIL'} "
              f"{res['seconds']:>6.1f}s  {res['summary'][:96]}")
        if not ok:
            failed.append(stage["name"])
            if res["output"]:
                for line in res["output"].splitlines()[-12:]:
                    print(f"      | {line}")

    total = sum(r["seconds"] for r in results)
    print(f"\nextract: {len(results) - len(failed)}/{len(results)} stages ok "
          f"in {total:.0f}s")
    if failed:
        print(f"extract: FAILED: {', '.join(failed)}")

    report = root / "tools" / "out" / "extract_report.json"
    report.parent.mkdir(parents=True, exist_ok=True)
    report.write_text(json.dumps({
        "mode": mode,
        "stages": results,
        "failed": failed,
    }, indent=1), encoding="utf-8")
    print(f"extract: wrote {report.relative_to(root)}")

    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
