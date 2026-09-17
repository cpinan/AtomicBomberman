#!/usr/bin/env bash
# Export the dedicated server. No art, no window, no GPU.
set -euo pipefail
GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
HERE="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# The generated sources must exist before an export, or the .pck ships without
# the constants the simulation reads.
if [ -d "$HERE/original-game/RES" ]; then
    python3 "$HERE/tools/valuelist.py" >/dev/null
    python3 "$HERE/tools/extras.py" >/dev/null
else
    echo "build_server: no game data; scripts/core/values.gd must already exist" >&2
    [ -f "$HERE/godot-project/scripts/core/values.gd" ] || exit 2
fi

mkdir -p "$HERE/build/server"
"$GODOT" --headless --path "$HERE/godot-project" \
    --export-release "Linux Server" "$HERE/build/server/ab-server.x86_64"
echo "build_server: $HERE/build/server/ab-server.x86_64"
