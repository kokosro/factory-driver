#!/usr/bin/env bash
# Headless checks: import the project, check the car configs, the element
# catalogue, the Ring skeleton, the Ring's drape through the world profile
# and the Ring's typed buildings (seconds: a broken config, catalogue entry,
# skeleton, drape or building record fails here, not somewhere in the smoke
# test), build the Ring's road and
# drive it (the ring drive test), run the smoke test, then the handling,
# camera, mission, battery, thermal, tyre/brake thermal, steering-feel,
# wear, licence, menu, issue flag, minimap, airborne, reset, refuel and
# telemetry watch tests. Fails on a non-zero exit code or on any engine/script
# error in the output.
#
#   tests/run_tests.sh              one step after the other, stops at the first failure
#   tests/run_tests.sh --parallel   the import first, then the twenty-three tests side by side
#
# Both print the same lines in the same order. --parallel prints a step when it
# and every step before it is done, runs them all to the end and then fails if
# any of them did.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

PARALLEL=0
for arg in "$@"; do
	case "$arg" in
		--parallel) PARALLEL=1 ;;
		*)
			echo "usage: tests/run_tests.sh [--parallel]" >&2
			exit 2
			;;
	esac
done

if command -v godot >/dev/null 2>&1; then
	GODOT="godot"
else
	GODOT="/opt/homebrew/bin/godot"
fi

# One log per step: the steps of a --parallel run write theirs at the same time.
LOG_DIR="$(mktemp -d)"
PIDS=()
cleanup() {
	# An interrupted --parallel run leaves no godot behind.
	if [ "${#PIDS[@]}" -gt 0 ]; then
		kill "${PIDS[@]}" 2>/dev/null
	fi
	rm -rf "$LOG_DIR"
}
trap cleanup EXIT

# What has failed in the step `name`, if anything: its exit status, or an
# engine/script error in its log.
step_failed() {
	local name="$1" status="$2" log="$3"
	if [ "$status" -ne 0 ]; then
		echo "== $name: FAILED (exit $status)" >&2
		return 0
	fi
	if grep -qE "SCRIPT ERROR|ERROR:|Parse Error" "$log"; then
		echo "== $name: FAILED (errors in output)" >&2
		return 0
	fi
	return 1
}

run_step() {
	local name="$1"
	shift
	local log="$LOG_DIR/step.log"
	echo "== $name"
	"$@" 2>&1 | tee "$log"
	local status="${PIPESTATUS[0]}"
	if step_failed "$name" "$status" "$log"; then
		exit 1
	fi
}

NAMES=()
LOGS=()

# Starts a step in the background, its output (stderr too) going to a log of
# its own; join_steps prints it.
start_step() {
	local name="$1"
	shift
	local log="$LOG_DIR/${#NAMES[@]}.log"
	"$@" >"$log" 2>&1 &
	PIDS+=("$!")
	NAMES+=("$name")
	LOGS+=("$log")
}

# Waits for the started steps in the order they were started and prints each
# the way run_step does. Every step is printed, then any failure fails the run.
join_steps() {
	local failed=0 i status
	for i in "${!PIDS[@]}"; do
		wait "${PIDS[$i]}"
		status="$?"
		echo "== ${NAMES[$i]}"
		cat "${LOGS[$i]}"
		if step_failed "${NAMES[$i]}" "$status" "${LOGS[$i]}"; then
			failed=1
		fi
	done
	PIDS=()
	if [ "$failed" -ne 0 ]; then
		exit 1
	fi
}

if [ "$PARALLEL" -eq 1 ]; then
	STEP=start_step
else
	STEP=run_step
fi

# The import is always alone and first: it writes .godot/, the tests only read it.
run_step "import" "$GODOT" --headless --path "$ROOT" --import
"$STEP" "config test" "$GODOT" --headless --path "$ROOT" --script res://tests/config_test.gd
"$STEP" "element catalogue test" "$GODOT" --headless --path "$ROOT" --script res://tests/element_catalogue_test.gd
"$STEP" "skeleton test" "$GODOT" --headless --path "$ROOT" --script res://tests/skeleton_test.gd
"$STEP" "world profile test" "$GODOT" --headless --path "$ROOT" --script res://tests/world_profile_test.gd
"$STEP" "buildings test" "$GODOT" --headless --path "$ROOT" --script res://tests/buildings_test.gd
# --fixed-fps: same 1/60 s physics steps, without waiting for the wall clock.
# Every wait in these tests is counted in physics ticks.
"$STEP" "ring drive test" "$GODOT" --headless --fixed-fps 60 --path "$ROOT" --script res://tests/ring_drive_test.gd
"$STEP" "smoke test" "$GODOT" --headless --fixed-fps 60 --path "$ROOT" --script res://tests/smoke_test.gd
"$STEP" "handling tests" "$GODOT" --headless --fixed-fps 60 --path "$ROOT" --script res://tests/handling_test.gd
"$STEP" "camera test" "$GODOT" --headless --fixed-fps 60 --path "$ROOT" --script res://tests/camera_test.gd
"$STEP" "mission test" "$GODOT" --headless --fixed-fps 60 --path "$ROOT" --script res://tests/mission_test.gd
"$STEP" "battery test" "$GODOT" --headless --fixed-fps 60 --path "$ROOT" --script res://tests/battery_test.gd
"$STEP" "thermal test" "$GODOT" --headless --fixed-fps 60 --path "$ROOT" --script res://tests/thermal_test.gd
"$STEP" "tyre/brake thermal test" "$GODOT" --headless --fixed-fps 60 --path "$ROOT" --script res://tests/tyre_brake_thermal_test.gd
"$STEP" "steering feel test" "$GODOT" --headless --fixed-fps 60 --path "$ROOT" --script res://tests/steering_feel_test.gd
"$STEP" "wear test" "$GODOT" --headless --fixed-fps 60 --path "$ROOT" --script res://tests/wear_test.gd
"$STEP" "licence test" "$GODOT" --headless --fixed-fps 60 --path "$ROOT" --script res://tests/licence_test.gd
"$STEP" "menu test" "$GODOT" --headless --fixed-fps 60 --path "$ROOT" --script res://tests/menu_test.gd
"$STEP" "issue flag test" "$GODOT" --headless --fixed-fps 60 --path "$ROOT" --script res://tests/issue_flag_test.gd
"$STEP" "minimap test" "$GODOT" --headless --fixed-fps 60 --path "$ROOT" --script res://tests/minimap_test.gd
"$STEP" "airborne test" "$GODOT" --headless --fixed-fps 60 --path "$ROOT" --script res://tests/airborne_test.gd
"$STEP" "reset test" "$GODOT" --headless --fixed-fps 60 --path "$ROOT" --script res://tests/reset_test.gd
"$STEP" "refuel test" "$GODOT" --headless --fixed-fps 60 --path "$ROOT" --script res://tests/refuel_test.gd
# TELEMETRY EVERYWHERE's never-again fence: every scene that carries a car
# has a recorder attached and writing (was: the Ring had none).
"$STEP" "telemetry watch test" "$GODOT" --headless --fixed-fps 60 --path "$ROOT" --script res://tests/telemetry_watch_test.gd
if [ "$PARALLEL" -eq 1 ]; then
	join_steps
fi
echo "== all checks passed"
