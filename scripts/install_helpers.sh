#!/bin/sh
# Copy lua/helpers/*.lua into REAPER's Scripts folder as reaper_mcp_<name>.lua.
# Then register + run one from the MCP (see skills/reaper/SKILL.md, "Helper scripts").
set -eu
SRC="$(cd "$(dirname "$0")/.." && pwd)/lua/helpers"
DEST="$HOME/Library/Application Support/REAPER/Scripts"
mkdir -p "$DEST"
for f in "$SRC"/*.lua; do
	cp "$f" "$DEST/reaper_mcp_$(basename "$f")"
	echo "installed reaper_mcp_$(basename "$f")"
done
