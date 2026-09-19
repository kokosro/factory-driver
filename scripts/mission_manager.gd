class_name MissionManager
extends Node
## Mission mode: the handling tests with a human at the wheel. Keys 1-4 put the
## car on a test's start point and begin a run, Esc or R abort it, and the HUD
## shows progress during the run and PASSED / FAILED after it.
##
## The missions themselves (start points, tracking, pass / fail checks, metrics)
## are the test data in scripts/handling_tests.gd, run with the scripted driver
## switched off. This node only picks a test, moves a run through
## idle -> running -> result shown -> idle, and hands the HUD its strings. It
## never presses or releases an input action.

signal mission_started(index: int, definition: Dictionary)
signal mission_finished(index: int, outcome: Dictionary)
signal mission_aborted(index: int)

enum State { IDLE, RUNNING, RESULT }

## Input actions that start a test, in the order of HandlingTests.all_tests().
const START_ACTIONS: Array[StringName] = [&"test_1", &"test_2", &"test_3", &"test_4"]

## How long the PASSED / FAILED banner stays up unless dismissed [s] ...
const RESULT_BANNER_TIME := 5.0

## ... and the shorter ABORTED one [s].
const ABORT_BANNER_TIME := 2.0

const LINE_COLOR_IDLE := Color(1, 1, 1, 0.85)
const LINE_COLOR_RUNNING := Color(1.0, 0.9, 0.35, 1)
const BANNER_COLOR_PASSED := Color(0.35, 1.0, 0.45, 1)
const BANNER_COLOR_FAILED := Color(1.0, 0.3, 0.2, 1)
const BANNER_COLOR_ABORTED := Color(1.0, 0.75, 0.25, 1)

@export var car: ArcadeCar
@export var pad: TestPad
@export var hud: HUD

var state := State.IDLE

## Index into HandlingTests.all_tests() of the test last started; -1 = none yet.
var selected_index := -1

## The run in progress, or the last one. Null before the first start.
var run: HandlingTests

## Verdict of the last completed run ({ name, passed, metrics, checks }, see
## HandlingTests.result()). Empty while a run is active and after an abort.
var last_result: Dictionary = {}

var _banner_left := 0.0


func _ready() -> void:
	_show_idle_line()


func _physics_process(delta: float) -> void:
	if state == State.RUNNING:
		# R also resets the car (the car sees to that itself).
		if Input.is_action_just_pressed("abort_mission") or Input.is_action_just_pressed("reset_car"):
			abort_mission()
			return
		run.tick(delta)
		if run.finished:
			_complete()
		else:
			_show_progress()
		return

	for index in START_ACTIONS.size():
		if Input.is_action_just_pressed(START_ACTIONS[index]):
			start_mission(index)
			return
	if state == State.RESULT:
		_banner_left -= delta
		if _banner_left <= 0.0 or Input.is_action_just_pressed("abort_mission"):
			dismiss_banner()


# =============================================================================
#  Run state
# =============================================================================

## Starts test `index` of HandlingTests.all_tests() with a human driving: car on
## the test's start point, cones back up. Returns false if a run is active (it
## has to be aborted first) or there is no such test.
func start_mission(index: int) -> bool:
	var tests := HandlingTests.all_tests()
	if state == State.RUNNING or index < 0 or index >= tests.size():
		return false
	if state == State.RESULT:
		dismiss_banner()
	selected_index = index
	last_result = {}
	run = HandlingTests.begin(tests[index], car, pad, false)
	state = State.RUNNING
	_show_progress()
	mission_started.emit(index, run.test)
	return true


## Cancels the active run. There is no verdict for an aborted run.
func abort_mission() -> void:
	if state != State.RUNNING:
		return
	run.abort()
	state = State.RESULT
	_banner_left = ABORT_BANNER_TIME
	_show_idle_line()
	if hud:
		hud.show_mission_banner("ABORTED  %s" % run.test.title, _keys_hint(), BANNER_COLOR_ABORTED)
	mission_aborted.emit(selected_index)


## Takes the banner down early and returns to idle.
func dismiss_banner() -> void:
	if state != State.RESULT:
		return
	state = State.IDLE
	if hud:
		hud.hide_mission_banner()


func is_running() -> bool:
	return state == State.RUNNING


func _complete() -> void:
	last_result = run.result()
	state = State.RESULT
	_banner_left = RESULT_BANNER_TIME
	_show_idle_line()
	_show_result(last_result)
	mission_finished.emit(selected_index, last_result)


# =============================================================================
#  Presentation
# =============================================================================

func _show_idle_line() -> void:
	if not hud:
		return
	var tests := HandlingTests.all_tests()
	var entries := PackedStringArray()
	for index in tests.size():
		entries.append("%d %s" % [index + 1, tests[index].title])
	hud.set_mission_line("HANDLING TESTS:   %s      C  camera" % "   ".join(entries), LINE_COLOR_IDLE)


func _show_progress() -> void:
	if not hud:
		return
	var test := run.test
	hud.set_mission_line(
		"TEST %d  %s      %s  %.1f s\n%s   Esc / R  abort" % [selected_index + 1, test.title, _progress_text(), run.elapsed, test.objective],
		LINE_COLOR_RUNNING,
	)


## The live objective readout, from what the run reports about itself.
func _progress_text() -> String:
	var progress := run.progress()
	match progress.kind:
		HandlingTests.KIND_SLALOM:
			return "GATE %d/%d" % [progress.gates_reached, progress.gates_total]
		HandlingTests.KIND_SPIN:
			return "ROTATION %d° / %d°" % [roundi(absf(progress.rotation_deg)), roundi(progress.target_rotation_deg)]
		_:
			var distance: float = progress.distance_to_box_m
			var half_length: float = TestPad.stop_box().size.y * 0.5
			if not progress.up_to_speed:
				var wanted := roundi(HandlingTests.STOP_BOX_MIN_ENTRY_SPEED * 3.6)
				return "BUILD SPEED %d/%d km/h  %d m to box" % [roundi(car.speed_kmh), wanted, roundi(distance)]
			if distance > half_length:
				return "BRAKE! %d m to box" % roundi(distance)
			if distance < -half_length:
				return "PAST THE BOX!"
			return "STOP!"


## PASSED / FAILED banner. The small print is HandlingTests.format_result()'s
## metrics line, with the failed checks moved onto a line of their own.
func _show_result(outcome: Dictionary) -> void:
	if not hud:
		return
	var summary := HandlingTests.format_result(outcome)[1].strip_edges().split(" | failed: ")
	var detail := "%s\n%s" % [outcome.name, summary[0]]
	if summary.size() > 1:
		detail += "\nfailed: " + summary[1]
	detail += "\n" + _keys_hint()
	hud.show_mission_banner(
		"%s  %s" % ["PASSED" if outcome.passed else "FAILED", run.test.title],
		detail,
		BANNER_COLOR_PASSED if outcome.passed else BANNER_COLOR_FAILED,
	)


func _keys_hint() -> String:
	return "%d  retry      1-%d  pick a test      Esc  close" % [selected_index + 1, START_ACTIONS.size()]
