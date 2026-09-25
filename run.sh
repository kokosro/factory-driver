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
# And rebuild it when a script is newer than the cached class list: a pull
# that adds a class_name script (the user's pull-and-run of 68ec1e1, which
# added Refuel, 2026-09-25) left a stale .godot/global_script_class_cache.cfg
# and the game booted to SCRIPT ERRORS - was: the import only when .godot/
# is absent -> also whenever any scripts/*.gd is newer than the cache file
# (find -newer compares the files' own timestamps, sub-second where the
# file system keeps them; only an actually stale cache triggers it, an
# up-to-date one costs one find).
CLASS_CACHE="$ROOT/.godot/global_script_class_cache.cfg"
if [ ! -d "$ROOT/.godot" ]; then
	"$GODOT" --headless --path "$ROOT" --import
elif [ ! -f "$CLASS_CACHE" ] || [ -n "$(find "$ROOT/scripts" -name '*.gd' -newer "$CLASS_CACHE" -print -quit)" ]; then
	"$GODOT" --headless --path "$ROOT" --import
fi

exec "$GODOT" --path "$ROOT" "$@"
