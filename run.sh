#!/usr/bin/env bash
# Launches Factory Driver. Requires Godot 4.7.
# Extra arguments are passed through to Godot, e.g. ./run.sh --fullscreen
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if command -v godot >/dev/null 2>&1; then
	GODOT="godot"
elif [ -x /opt/homebrew/bin/godot ]; then
	GODOT="/opt/homebrew/bin/godot"
else
	echo "error: Godot 4.7 not found. Put 'godot' on PATH or install it to /opt/homebrew/bin/godot." >&2
	exit 1
fi

# A fresh clone has no .godot/ cache (imported assets, script class list).
# Build it once, headlessly, so the game starts cleanly without the editor.
if [ ! -d "$ROOT/.godot" ]; then
	"$GODOT" --headless --path "$ROOT" --import
fi

exec "$GODOT" --path "$ROOT" "$@"
