#!/usr/bin/env bash
# Headless checks: import the project, run the smoke test, then the handling
# tests. Fails on a non-zero exit code or on any engine/script error in the
# output.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if command -v godot >/dev/null 2>&1; then
	GODOT="godot"
else
	GODOT="/opt/homebrew/bin/godot"
fi

LOG="$(mktemp)"
trap 'rm -f "$LOG"' EXIT

run_step() {
	local name="$1"
	shift
	echo "== $name"
	"$@" 2>&1 | tee "$LOG"
	local status="${PIPESTATUS[0]}"
	if [ "$status" -ne 0 ]; then
		echo "== $name: FAILED (exit $status)" >&2
		exit 1
	fi
	if grep -qE "SCRIPT ERROR|ERROR:|Parse Error" "$LOG"; then
		echo "== $name: FAILED (errors in output)" >&2
		exit 1
	fi
}

run_step "import" "$GODOT" --headless --path "$ROOT" --import
run_step "smoke test" "$GODOT" --headless --path "$ROOT" --script res://tests/smoke_test.gd
# --fixed-fps: same 1/60 s physics steps, without waiting for the wall clock.
run_step "handling tests" "$GODOT" --headless --fixed-fps 60 --path "$ROOT" --script res://tests/handling_test.gd
echo "== all checks passed"
