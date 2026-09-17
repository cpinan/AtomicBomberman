#!/usr/bin/env bash
# One command that has to be green before anything is called working.
#
# Structure inherited from the SkyRoads port, where two failure modes were
# learned the hard way:
#
#   1. `--script suite.gd` only loads what that suite references, so a syntax
#      error in an unreferenced file ships with a 100% green run. Hence the
#      parse pass over every .gd file, referenced or not.
#   2. Grepping for "FAIL" reports a suite that died early — parse error,
#      crash, missing data — as passing, because it printed no FAIL. Every
#      suite must print a "Result:" line and we assert on that positive signal.
#
# `--quit` is deliberately NOT passed: it exits after one frame and would skip
# any frame-driven suite entirely.
set -uo pipefail
GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
PYTHON="${PYTHON:-python3}"

# resolve through symlinks, so a tools/verify.sh -> godot-project/verify.sh
# symlink works from either directory
SRC="${BASH_SOURCE[0]}"
while [ -L "$SRC" ]; do
    DIR="$(cd -P "$(dirname "$SRC")" && pwd)"
    SRC="$(readlink "$SRC")"
    [[ $SRC != /* ]] && SRC="$DIR/$SRC"
done
HERE="$(cd -P "$(dirname "$SRC")" && pwd)"
ROOT="$(cd -P "$HERE/.." && pwd)"
status=0

if [ ! -x "$GODOT" ]; then
    echo "verify: no Godot at $GODOT — set GODOT to the binary"
    exit 2
fi

# ---------------------------------------------------------------------------
# Generated sources. values.gd and extras.gd are produced from the original's
# own data files and are NOT committed (see tools/valuelist.py's docstring), so
# a fresh clone has to generate them before anything can compile. Doing it here
# rather than documenting it means the failure mode is "regenerated" and not
# "mysterious parse error in a file that does not exist".
# ---------------------------------------------------------------------------
echo "== generated sources =="
AB_DATA="${AB_DATA:-$ROOT/original-game}"
export AB_DATA
if [ -d "$AB_DATA/RES" ]; then
    # rss.py needs --pack: without it it reports and writes nothing, which is
    # the right default for a tool that can also dump 443 MB of WAVs.
    # A case rather than an associative array: macOS still ships bash 3.2,
    # where `declare -A` does not exist.
    for gen in valuelist extras messages pack_assets rss; do
        case "$gen" in
            rss) gen_args="--pack" ;;
            *)   gen_args="" ;;
        esac
        if out=$("$PYTHON" "$ROOT/tools/$gen.py" --data "$AB_DATA" \
                 $gen_args 2>&1); then
            printf '%s\n' "$out" | sed 's/^/       /'
        else
            printf '%s\n' "$out" | sed 's/^/       /'
            echo "  FAIL tools/$gen.py"
            status=1
        fi
    done
else
    echo "       no game data at $AB_DATA"
    echo "       set AB_DATA to the CD's DATA folder; data-driven suites will skip"
    for gen in values extras messages; do
        if [ ! -f "$HERE/scripts/core/$gen.gd" ]; then
            echo "  FAIL scripts/core/$gen.gd is absent and cannot be generated"
            status=1
        fi
    done
fi

# ---------------------------------------------------------------------------
# Parse pass. Every .gd file, whether any suite references it or not.
# ---------------------------------------------------------------------------
echo
echo "== parse pass (every script, referenced or not) =="
while IFS= read -r f; do
    rel="res://${f#"$HERE"/}"
    out=$("$GODOT" --headless --path "$HERE" --check-only --script "$rel" 2>&1 \
          | grep -E "SCRIPT ERROR|Parse Error")
    if [ -n "$out" ]; then
        echo "  FAIL $rel"
        echo "$out" | sed 's/^/       /'
        status=1
    else
        echo "  ok   $rel"
    fi
done < <(find "$HERE/scripts" "$HERE/tests" -name '*.gd' 2>/dev/null | sort)

# ---------------------------------------------------------------------------
# Rendering. The headless rasteriser draws nothing, so anything asserting on
# pixels has to run windowed. On macOS a windowed capture is starved of frames
# whenever its window is not frontmost and then produces nothing, which would
# fail for a reason unrelated to the code — so retry once and say so.
# ---------------------------------------------------------------------------
echo
echo "== rendering (needs a real GPU context, so not headless) =="
shopt -s nullglob
for t in "$HERE"/tests/render_*.gd; do
    name="$(basename "$t")"
    ok=0
    for attempt in 1 2; do
        out=$("$GODOT" --path "$HERE" --resolution 640x480 \
              --script "res://tests/$name" 2>&1)
        if printf '%s' "$out" | grep -q "^Result:"; then ok=1; break; fi
        echo "       (no Result from $name on attempt $attempt; retrying)"
    done
    if [ $ok -eq 0 ]; then
        echo "  FAIL $name (no Result line)"
        printf '%s\n' "$out" | grep -vE "^$|Godot Engine" | tail -8 | sed 's/^/       /'
        status=1
        continue
    fi
    printf '%s\n' "$out" | grep -E "^(     |Result:)" | sed 's/^/       /'
    if printf '%s' "$out" | grep -q "FAIL"; then
        echo "  FAIL $name"
        printf '%s\n' "$out" | grep "FAIL" | head -12 | sed 's/^/       /'
        status=1
    else
        echo "  ok   $name"
    fi
done
shopt -u nullglob

# ---------------------------------------------------------------------------
# The statistics file, end to end. tests/test_stats.gd covers the format and
# the counters; only a real run of the game covers the wiring — that main
# creates the counters, hands them to the simulation, and writes both files on
# its way out. Needs the same GPU context as the render suites, because --shot
# is what makes a run end by itself.
# ---------------------------------------------------------------------------
STATS_DIR="$(mktemp -d)"
# HEADLESS, via --quit-tick. This was a windowed --shot run at first and it
# failed once for no reason of its own: macOS throttles a window that never
# comes to the front, --shot waits on frame_post_draw, and the run behind six
# other windowed suites lost that race. --quit-tick needs no frame, so there is
# no window, no focus and nothing to race.
"$GODOT" --headless --path "$HERE" -- \
    --quit-tick 40 --stats-path "$STATS_DIR" \
    --players 1 --bots 3 --auto-bomb 5 --mute >/dev/null 2>&1
stat_rows=$(grep -cE '^[A-Z].*: +[0-9]+ +[0-9]+$' "$STATS_DIR/bmstats.txt" 2>/dev/null || echo 0)
stat_bytes=$(wc -c < "$STATS_DIR/bmstats.dat" 2>/dev/null | tr -d ' ' || echo 0)
if [ "$stat_rows" = "19" ] && [ "$stat_bytes" = "400" ]; then
    echo "  ok   bmstats — 19 rows written, bmstats.dat is 400 bytes"
else
    echo "  FAIL bmstats — $stat_rows rows (want 19), .dat $stat_bytes bytes (want 400)"
    status=1
fi
rm -rf "$STATS_DIR"

# ---------------------------------------------------------------------------
# The art kit, round trip. docs/ART.md is the promise this keeps: a pack can be
# taken apart into PNGs, checked, and put back together into a pack the game
# loads. If that breaks, replacing the art stops being possible and nothing
# else in this suite would notice.
# ---------------------------------------------------------------------------
if [ -f "$HERE/data/packs/cd.bin" ] || [ -f "$HERE/data/packs/cd/pack.json" ]; then
    KIT_DIR="$(mktemp -d)"
    if python3 "$HERE/../tools/artpack.py" --template "$KIT_DIR/kit" \
            >/dev/null 2>&1 \
        && python3 "$HERE/../tools/artpack.py" --check "$KIT_DIR/kit" \
            >/dev/null 2>&1 \
        && python3 "$HERE/../tools/artpack.py" --build "$KIT_DIR/kit" \
            --out "$KIT_DIR/pack" >/dev/null 2>&1 \
        && [ -f "$KIT_DIR/pack.bin" ]; then
        kit_sheets=$(python3 -c "import json,sys;print(len(json.load(open('$KIT_DIR/kit/kit.json'))['required']['sheets']))" 2>/dev/null || echo 0)
        echo "  ok   artpack — kit of $kit_sheets sheets went out and came back"
    else
        echo "  FAIL artpack — the art kit did not survive a round trip"
        status=1
    fi
    rm -rf "$KIT_DIR"
else
    echo "       (no art pack; skipping the art-kit round trip)"
fi

# ---------------------------------------------------------------------------
# Headless suites.
# ---------------------------------------------------------------------------
echo
echo "== suites =="
shopt -s nullglob
for t in "$HERE"/tests/test_*.gd; do
    name="$(basename "$t")"
    out=$("$GODOT" --headless --path "$HERE" --script "res://tests/$name" 2>&1)
    # A suite that never printed Result: died before its assertions ran.
    if ! printf '%s' "$out" | grep -q "^Result:"; then
        echo "  FAIL $name (no Result line — died before asserting)"
        printf '%s\n' "$out" | grep -vE "^$|Godot Engine" | tail -8 | sed 's/^/       /'
        status=1
        continue
    fi
    printf '%s\n' "$out" | grep -E "^(     |Result:)" | sed 's/^/       /'
    if printf '%s' "$out" | grep -q "FAIL"; then
        echo "  FAIL $name"
        printf '%s\n' "$out" | grep "FAIL" | head -20 | sed 's/^/       /'
        status=1
    # A suite can print Result: AND 0 failures while runtime errors killed most
    # of its assertions before they ran — assertions that never execute cannot
    # fail. This was a real hole: the scheme suite reported "1 checks, 0
    # failures" and a green tick while three of its four sections had died on a
    # missing global class. Any engine-level error means the run is not a
    # measurement, whatever the Result: line claims.
    elif printf '%s' "$out" | grep -qE "SCRIPT ERROR|Compile Error|Parse Error"; then
        echo "  FAIL $name (engine errors — its Result line does not mean anything)"
        printf '%s\n' "$out" | grep -E "SCRIPT ERROR|Compile Error|Parse Error" \
            | sort -u | head -10 | sed 's/^/       /'
        status=1
    else
        echo "  ok   $name"
    fi
done
shopt -u nullglob

# ---------------------------------------------------------------------------
# Exports. Opt-in with EXPORT=1, because each one takes tens of seconds and
# needs the export templates installed.
#
# The check that matters is not "did the export succeed" — it did, twice, while
# shipping no art at all. It is whether the asset container is really INSIDE
# the .pck, which is only answerable with the real files moved out of the way.
# ---------------------------------------------------------------------------
if [ "${EXPORT:-0}" = "1" ]; then
    echo
    echo "== exports =="
    BUILD="$ROOT/build"
    mkdir -p "$BUILD/web" "$BUILD/server"

    for preset in "Web:$BUILD/web/index.html" "Linux Server:$BUILD/server/ab-server.x86_64"; do
        name="${preset%%:*}"; out="${preset##*:}"
        if "$GODOT" --headless --path "$HERE" \
                --export-release "$name" "$out" >/dev/null 2>&1 \
                && [ -s "$out" ]; then
            echo "  ok   export \"$name\" -> $(basename "$out")"
        else
            echo "  FAIL export \"$name\""
            status=1
        fi
    done

    # Does the web .pck actually contain the art? Answered with the real pack
    # moved aside, so nothing can be read from the working tree by accident.
    if [ -f "$BUILD/web/index.pck" ] && [ -d "$HERE/data/packs" ]; then
        mv "$HERE/data/packs" "$HERE/data/packs.aside"
        cat > "$HERE/pck_probe.gd" <<'PROBE'
extends SceneTree
const Pack_ := preload("res://scripts/render/pack.gd")
const SoundPack_ := preload("res://scripts/audio/sound_pack.gd")
const Sfx_ := preload("res://scripts/audio/sfx.gd")
func _init() -> void:
	ProjectSettings.load_resource_pack(
		ProjectSettings.globalize_path("res://../build/web/index.pck"), false)
	var pack: Pack_ = Pack_.new()
	if not pack.load_from("res://data/packs/cd"):
		print("PCK-ART FAIL ", pack.error)
		quit(1)
	if pack.sheet_names().size() < 30 or pack.background_count() != 11:
		print("PCK-ART FAIL only %d sheets, %d backgrounds"
			% [pack.sheet_names().size(), pack.background_count()])
		quit(1)
	# The sound pack is in the same .pck and fails the same way — silently,
	# with a successful export.
	var sfx: SoundPack_ = SoundPack_.new()
	if not sfx.load_from("res://data/packs/sfx"):
		print("PCK-ART FAIL sound: ", sfx.error)
		quit(1)
	for name in Sfx_.required_events():
		if not sfx.has_event(name):
			print("PCK-ART FAIL sound event %s is not in the .pck" % name)
			quit(1)
	if sfx.stream_for("bomb_explode", 0) == null:
		print("PCK-ART FAIL sound bytes did not survive the export")
		quit(1)
	# The colour remap tables and the schemes: three more blobs and a chunk of
	# manifest text in the same container, and they would fail the same silent
	# way — a successful export carrying none of them.
	if not pack.has_remap():
		print("PCK-ART FAIL the remap tables are not in the .pck")
		quit(1)
	var info := pack.remap_info()
	if int(info["count"]) != 73 or int(info["players"]) != 10:
		print("PCK-ART FAIL remap tables are %s" % str(info))
		quit(1)
	if pack.scheme_names().size() != 67:
		print("PCK-ART FAIL %d schemes in the .pck" % pack.scheme_names().size())
		quit(1)
	print("PCK-ART OK %d sheets, %d powerups, %d backgrounds, %d schemes, "
		% [pack.sheet_names().size(), pack.powerup_keys().size(),
			pack.background_count(), pack.scheme_names().size()]
		+ "%d sound events, %d remapped indices"
		% [sfx.event_names().size(), int(info["count"])])
	quit(0)
PROBE
        out=$("$GODOT" --headless --path "$HERE" --script res://pck_probe.gd 2>&1)
        rm -f "$HERE/pck_probe.gd"
        mv "$HERE/data/packs.aside" "$HERE/data/packs"
        if printf '%s' "$out" | grep -q "PCK-ART OK"; then
            printf '%s\n' "$out" | grep "PCK-ART OK" | sed 's/^/       /'
            echo "  ok   the web .pck really carries the art"
        else
            printf '%s\n' "$out" | grep -E "PCK-ART|ERROR" | head -4 | sed 's/^/       /'
            echo "  FAIL the web .pck does NOT carry the art"
            status=1
        fi
    fi
fi

echo
[ $status -eq 0 ] && echo "VERIFY OK" || echo "VERIFY FAILED"
exit $status
