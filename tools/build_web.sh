#!/usr/bin/env bash
# Export the HTML5 client.
#
# The art pack IS included here — a browser cannot read the user's disc, so
# whoever builds this must own the game. That is why the web build is something
# a server owner produces for their own players and not something published.
# See docs/PLAN.md on the two asset packs.
set -euo pipefail
GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
HERE="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [ -d "$HERE/original-game/RES" ]; then
    python3 "$HERE/tools/valuelist.py" >/dev/null
    python3 "$HERE/tools/extras.py" >/dev/null
    python3 "$HERE/tools/pack_assets.py" >/dev/null
    # The sound pack. AB_SFX_BUDGET shrinks it: the default is VALUELST
    # resource 6's 7 MB, which is what the original itself intends to hold,
    # and 2000000 gives a 2 MB pack that still covers every event.
    python3 "$HERE/tools/rss.py" --pack \
        --budget "${AB_SFX_BUDGET:-7000000}" >/dev/null
fi
if [ ! -f "$HERE/godot-project/data/packs/cd/pack.json" ]; then
    echo "build_web: no asset pack. Run tools/pack_assets.py with the game data." >&2
    exit 2
fi
if [ ! -f "$HERE/godot-project/data/packs/sfx.bin" ]; then
    echo "build_web: no sound pack. Run tools/rss.py --pack with the game data." >&2
    echo "build_web: (the game runs silent without it, but a build should not.)" >&2
    exit 2
fi

mkdir -p "$HERE/build/web"
"$GODOT" --headless --path "$HERE/godot-project" \
    --export-release "Web" "$HERE/build/web/index.html"
echo "build_web: $HERE/build/web/index.html"
echo
echo "The client needs to know where the server is. Append it to the URL:"
echo "  http://localhost:8080/?join=ws://localhost:47600"
echo
echo "There will be no sound until you click the page or press a key: a browser"
echo "will not start an audio context without a user gesture. This is normal and"
echo "is not the sound pack failing to load."
