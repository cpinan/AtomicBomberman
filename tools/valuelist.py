#!/usr/bin/env python3
"""Parse the original's RES/VALUELST.RES into machine-readable form.

VALUELST.RES is Kurt W. Dekker's own tuning table, dated 02/04/97 - 07/11/97,
which the game loads at runtime. Its header states the two conventions that
govern every number in it:

    CHANCES:  all chances are 1-in-N.
    SPEEDS:   speeds are in hundredths of a pixel per frame. A speed of 100
              moves 1 pixel per frame.

and warns that the resource numbers are lookup keys:

    DO NOT CHANGE the first number! if you do the program will exit to DOS
    because it cannot find a particular value.

which is why this reads them as a {number: value} map rather than positionally.

Grammar, as observed across the whole file:

    <blank>                     ignored
    ; text                      comment, ignored
    NNN,V                       single value
    NNN,V1,V2                   multi-value (e.g. 500,12,10 and 600,0,0)
    NNN,V<tab>; text            trailing comment, ignored for the value
    \x1a                        DOS EOF marker at end of file

Values are always integers. Trailing comments frequently carry "; PGT", which
marks the value as gameplay-critical (per-game-tunable).

Emits:
    scripts/core/values.gd      generated GDScript, consumed by the port
    tools/out/valuelist.json    same data for the C oracle and Python models

Neither output is committed: VALUELST.RES is a copyrighted file, and while the
facts in it are not copyrightable, its comments are its author's prose. The
generated GDScript therefore carries values only. Our own analysis of what the
values mean lives in docs/ORACLE.md, which is safe to publish.

Usage:
    tools/valuelist.py [--data DIR] [--check]

    --data   the CD's DATA tree            (default: ./original-game)
    --check  parse and report, write nothing
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

# A data line: resource number, then one or more comma-separated integers.
# Anything from an unquoted ';' onwards is a comment. Whitespace is free-form —
# the file uses both spaces and tabs, inconsistently.
LINE_RE = re.compile(r"^\s*(\d+)\s*,\s*(-?\d+(?:\s*,\s*-?\d+)*)\s*$")

# Values the file marks '; PGT' are gameplay-critical. Worth surfacing, because
# a mistake in one of these changes how the game feels rather than merely
# breaking something loudly.
PGT_RE = re.compile(r";\s*PGT\b", re.IGNORECASE)


class ParseError(Exception):
    pass


def parse(text: str) -> tuple[dict[int, object], set[int]]:
    """Return ({resource: int | [int, ...]}, {resource, ...} marked PGT)."""
    values: dict[int, object] = {}
    pgt: set[int] = set()

    for lineno, raw in enumerate(text.splitlines(), start=1):
        # Strip the DOS EOF marker wherever it appears.
        line = raw.replace("\x1a", "")

        # Split off the comment before parsing, but keep it to look for PGT.
        head, _, comment = line.partition(";")
        if not head.strip():
            continue

        m = LINE_RE.match(head)
        if not m:
            raise ParseError(f"line {lineno}: cannot parse {raw.strip()!r}")

        number = int(m.group(1))
        parts = [int(p) for p in m.group(2).split(",")]

        if number in values:
            raise ParseError(
                f"line {lineno}: resource {number} defined twice "
                f"(was {values[number]!r}, now {parts!r})"
            )

        values[number] = parts[0] if len(parts) == 1 else parts
        if PGT_RE.search(comment):
            pgt.add(number)

    return values, pgt


def emit_gdscript(values: dict[int, object], pgt: set[int], src: Path) -> str:
    """Render the value table as a GDScript const Dictionary.

    Values only, no comments carried over from the source file — see the module
    docstring on why. Resource numbers are the keys because that is how the
    original addresses them, and because a name we invented would be a name the
    oracle cannot be checked against.
    """
    lines = [
        "# GENERATED FILE — do not edit.",
        "#",
        "# Produced by tools/valuelist.py from the original's RES/VALUELST.RES.",
        "# Regenerate with:  tools/valuelist.py",
        "#",
        "# Keys are the original's resource numbers, which are how the game",
        "# itself addresses these values. Names would be ours, not the",
        "# original's, and could not be checked against it. What each number",
        "# means is documented in docs/ORACLE.md.",
        "#",
        "# Units, from the source file's own header:",
        "#   chances are 1-in-N",
        "#   speeds are hundredths of a pixel per frame (100 = 1 px/frame)",
        "#   'frames' are 20ths of a second (resource 25 = the nominal rate)",
        "",
        "class_name Values",
        "",
        "## Every value in the original's tuning table, keyed by resource number.",
        "const V := {",
    ]

    for number in sorted(values):
        value = values[number]
        rendered = (
            "[" + ", ".join(str(v) for v in value) + "]"
            if isinstance(value, list)
            else str(value)
        )
        lines.append(f"\t{number}: {rendered},")

    lines += [
        "}",
        "",
        "## Resources the original tags '; PGT' — per-game-tunable, meaning a",
        "## change here alters how the game plays rather than merely breaking it.",
        "const PGT := [" + ", ".join(str(n) for n in sorted(pgt)) + "]",
        "",
        "",
        "## Look up a resource, failing loudly rather than returning a silent",
        "## default. A missing resource is a bug in the port, not a condition to",
        "## paper over: the original exits to DOS in the same situation.",
        "static func v(number: int) -> int:",
        "\tassert(V.has(number), \"VALUELST resource %d not found\" % number)",
        "\tvar value: Variant = V[number]",
        "\tassert(not (value is Array), \"resource %d is multi-valued; use vs()\" % number)",
        "\treturn value",
        "",
        "",
        "## Look up a multi-valued resource, e.g. 600 (an x,y pair).",
        "static func vs(number: int) -> Array:",
        "\tassert(V.has(number), \"VALUELST resource %d not found\" % number)",
        "\tvar value: Variant = V[number]",
        "\tif value is Array:",
        "\t\treturn value",
        "\treturn [value]",
        "",
    ]
    return "\n".join(lines)


def main(argv: list[str]) -> int:
    root = Path(__file__).resolve().parent.parent

    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--data", type=Path, default=root / "original-game")
    ap.add_argument("--check", action="store_true", help="parse only, write nothing")
    args = ap.parse_args(argv)

    src = args.data / "RES" / "VALUELST.RES"
    if not src.is_file():
        print(f"valuelist: not found: {src}", file=sys.stderr)
        print("valuelist: pass --data <the CD's DATA folder>", file=sys.stderr)
        return 2

    # The file is DOS-encoded; latin-1 round-trips every byte without raising.
    try:
        values, pgt = parse(src.read_text(encoding="latin-1"))
    except ParseError as exc:
        print(f"valuelist: {exc}", file=sys.stderr)
        return 1

    multi = sorted(n for n, v in values.items() if isinstance(v, list))
    print(f"valuelist: {len(values)} resources, {len(pgt)} tagged PGT, "
          f"{len(multi)} multi-valued")

    if args.check:
        return 0

    gd = root / "godot-project" / "scripts" / "core" / "values.gd"
    gd.parent.mkdir(parents=True, exist_ok=True)
    gd.write_text(emit_gdscript(values, pgt, src), encoding="utf-8")
    print(f"valuelist: wrote {gd.relative_to(root)}")

    out = root / "tools" / "out"
    out.mkdir(parents=True, exist_ok=True)
    js = out / "valuelist.json"
    js.write_text(
        json.dumps({"values": {str(k): v for k, v in sorted(values.items())},
                    "pgt": sorted(pgt)}, indent=1),
        encoding="utf-8",
    )
    print(f"valuelist: wrote {js.relative_to(root)}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
