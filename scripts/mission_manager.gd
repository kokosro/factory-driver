class_name MissionManager
extends Node
## Mission mode: the handling tests with a human at the wheel. Keys 1-5 put the
## car on a test's start point and begin a run, Esc or R abort it, and the HUD
## shows progress during the run and PASSED / FAILED after it.
##
## The missions themselves (start points, tracking, pass / fail checks, metrics)
## are the test data in scripts/handling_tests.gd, run with the scripted driver
## switched off. This node only picks a test, moves a run through
## idle -> running -> result shown -> idle, and hands the HUD its strings. It
## never presses or releases an input action. While a run is on it also shows
## where the run starts and where it is headed: a golden orb by the start point
## and a golden chevron by the goal (looks only). The 180 goes back to the
## start: its orb is its goal.
##
## It also owns the telemetry recorder (scripts/telemetry.gd), which listens to
## the signals below and writes every run down, and shows what it has stored:
## your last medal and best time on the idle line, your standing best on a
## PASSED banner.

signal mission_started(index: int, definition: Dictionary)
signal mission_finished(index: int, outcome: Dictionary)
signal mission_aborted(index: int)

enum State { IDLE, RUNNING, RESULT }

## Input actions that start a test, in the order of HandlingTests.all_tests().
const START_ACTIONS: Array[StringName] = [&"test_1", &"test_2", &"test_3", &"test_4", &"test_5"]

## How long the PASSED / FAILED banner stays up unless dismissed [s] ...
const RESULT_BANNER_TIME := 5.0

## ... and the shorter ABORTED one [s].
const ABORT_BANNER_TIME := 2.0

## What the running line's clock reads until the car crosses the test's start
## line: the run is not being timed yet (HandlingTests, "The run clock").
const CLOCK_NOT_STARTED := "not started"

const LINE_COLOR_IDLE := Color(1, 1, 1, 0.85)
const LINE_COLOR_RUNNING := Color(1.0, 0.9, 0.35, 1)
const BANNER_COLOR_PASSED := Color(0.35, 1.0, 0.45, 1)
const BANNER_COLOR_FAILED := Color(1.0, 0.3, 0.2, 1)
const BANNER_COLOR_ABORTED := Color(1.0, 0.75, 0.25, 1)

## Headline tint of a PASSED banner by the medal the run earned (sRGB, opaque);
## a pass without a medal stays BANNER_COLOR_PASSED.
const BANNER_COLOR_MEDAL := {
	"gold": Color(1.0, 0.84, 0.25, 1),
	"silver": Color(0.82, 0.86, 0.92, 1),
	"bronze": Color(0.85, 0.55, 0.3, 1),
}

# --- Run markers ----------------------------------------------------------------
# A golden orb by the start and a golden chevron by the goal, up while a run is
# on. Looks only: plain meshes with no collision, stood clear of the driving
# line, so they are never something to hit or to miss. Nothing judges them.

const MARKER_COLOR := Color(1.0, 0.78, 0.2)  # Gold, albedo and glow alike.
const MARKER_EMISSION_ENERGY := 2.0  # Glow strength, a multiplier [-].

const START_ORB_RADIUS := 0.35  # [m].
const START_ORB_HEIGHT := 1.0  # Centre of the orb above the ground [m].

## From a test's start point to its orb, along the pad's X and Z whichever way
## the car faces [m]: to the right of the way down the pad and a little behind.
## From the spawn point that is outside the painted staging box (3.4 x 6.6 m).
const START_ORB_OFFSET := Vector3(3.5, 0.0, 2.0)

## The chevron is a V standing across the way down the pad, pointing at the
## ground: two bars of this length, width and depth [m] ...
const FINISH_CHEVRON_ARM_SIZE := Vector3(0.22, 1.2, 0.12)
const FINISH_CHEVRON_ARM_DEG := 40.0  # ... each leant this far out from upright [degrees] ...
const FINISH_CHEVRON_TIP_HEIGHT := 1.2  # ... meeting this high above the ground [m].

## Stop box: the chevron stands this far to the right of the box's edge [m]
## (x = 1.8 + 2.2 = 4.0, clear of the corner cones and the red stop bar).
const FINISH_CHEVRON_BOX_CLEARANCE := 2.2

## Drive-on goals (the 360, the reverse 180): the chevron stands this far to the
## pad's right of the goal point [m], beside the painted bar of the distance
## board there, the same x as the stop box's.
const FINISH_CHEVRON_GOAL_OFFSET := 4.0

## Slalom: from the last cone to the chevron [m]: on the way out to the painted
## exit bar, further off the line of cones than the bar reaches (5 m).
const FINISH_CHEVRON_SLALOM_OFFSET := Vector3(5.5, 0.0, -8.0)

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

## Writes the driving down (scripts/telemetry.gd) and holds the stored summary
## of earlier runs the HUD shows. Made here, listening to this node's signals.
## It records nothing with no window, so the test suite writes no files.
var telemetry: TelemetryRecorder

var _banner_left := 0.0

var _markers: Node3D
var _start_orb: MeshInstance3D
var _finish_chevron: Node3D


func _ready() -> void:
	_start_telemetry()
	_build_markers()
	_show_idle_line()


## The recorder goes up before the first line is drawn: it reads the stored
## summary of earlier runs (times, medals) that the idle line and the PASSED
## banner show. It connects to the signals below first, so by the time the idle
## line is built again after a run the run is already in the summary.
func _start_telemetry() -> void:
	telemetry = TelemetryRecorder.new()
	telemetry.name = "TelemetryRecorder"
	add_child(telemetry)
	telemetry.attach(self, car)
	if TelemetryRecorder.should_record():
		telemetry.start_session()
	mission_finished.connect(func(_index: int, _outcome: Dictionary) -> void: _show_idle_line())


## The stored summary of earlier runs, empty when there is none.
func _telemetry_index() -> Dictionary:
	return telemetry.index if telemetry else {}


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
	_show_markers(run.test)
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
	_hide_markers()
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
	_hide_markers()
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
	# was: the line ended at "C  camera" -> when there is telemetry stored from
	# earlier runs it ends with a summary of it: " | last: SILVER, best: 30.9 s"
	# (TelemetryRecorder.idle_suffix, the one place that string is built).
	# Nothing stored, nothing appended.
	hud.set_mission_line(
		"HANDLING TESTS:   %s      C  camera%s" % ["   ".join(entries), TelemetryRecorder.idle_suffix(_telemetry_index())],
		LINE_COLOR_IDLE,
	)


func _show_progress() -> void:
	if not hud:
		return
	var test := run.test
	# The clock: against the test's target time, where it has one.
	# was run.elapsed, counting from the moment the test began ("0.0 / 11.0 s",
	# "0.1 / 11.0 s", ...) -> the run clock: it reads "not started" until the car
	# crosses the test's start line ("not started / 9.5 s"), counts from there
	# and stands once the car is at the finish. Waiting on the start point costs
	# nothing, and the line says so.
	var clock := CLOCK_NOT_STARTED
	if run.started():
		clock = "%.1f" % run.run_time()
	if test.has("target_time_s"):
		clock += " / %.1f" % test.target_time_s
	if run.started() or test.has("target_time_s"):
		clock += " s"
	hud.set_mission_line(
		"TEST %d  %s      %s  %s\n%s   Esc / R  abort" % [selected_index + 1, test.title, _progress_text(), clock, test.objective],
		LINE_COLOR_RUNNING,
	)


## The live objective readout, from what the run reports about itself.
func _progress_text() -> String:
	var progress := run.progress()
	match progress.kind:
		HandlingTests.KIND_SLALOM:
			return "GATE %d/%d" % [progress.gates_reached, progress.gates_total]
		HandlingTests.KIND_SPIN:
			return _spin_progress_text(progress)
		HandlingTests.KIND_REVERSE_SPIN:
			if not progress.up_to_speed:
				var wanted := roundi(HandlingTests.REVERSE_180_MIN_ENTRY_SPEED * 3.6)
				return "REVERSE %d/%d km/h" % [roundi(progress.reverse_speed_ms * 3.6), wanted]
			return _spin_progress_text(progress)
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


## The rotation while the car spins, then the way to the goal.
func _spin_progress_text(progress: Dictionary) -> String:
	if not progress.spin_done:
		return "ROTATION %d° / %d°" % [roundi(absf(progress.rotation_deg)), roundi(progress.target_rotation_deg)]
	if progress.spin_overshot:
		return "OVER-ROTATED %d° / %d°" % [roundi(absf(progress.rotation_deg)), roundi(progress.target_rotation_deg)]
	var heading := "RETURN TO START" if progress.goal_mode == HandlingTests.GOAL_RETURN_TO_START else "DRIVE ON"
	return "SPIN DONE — %s %d m" % [heading, roundi(progress.goal_distance_m)]


## PASSED / FAILED banner. A passed run shows the medal its time earned, in the
## headline and its colour, and the medal times in the small print; the verdict
## is made by then, the medal is only looked up. The rest of the small print is
## HandlingTests.format_result()'s metrics line, with the failed checks moved
## onto a line of their own.
func _show_result(outcome: Dictionary) -> void:
	if not hud:
		return
	var headline := "%s  %s" % ["PASSED" if outcome.passed else "FAILED", run.test.title]
	var color := BANNER_COLOR_PASSED if outcome.passed else BANNER_COLOR_FAILED
	var medal := HandlingTests.medal_for(run.test, outcome.metrics.run_time_s) if outcome.passed else ""
	if medal != "":
		headline += " — %s" % medal.to_upper()
		color = BANNER_COLOR_MEDAL[medal]
	var summary := HandlingTests.format_result(outcome)[1].strip_edges().split(" | failed: ")
	var detail := "%s\n%s" % [outcome.name, summary[0]]
	if summary.size() > 1:
		detail += "\nfailed: " + summary[1]
	if outcome.passed:
		detail += "\n" + _medal_times_text(run.test)
		# was: the small print ended at the medal times -> your standing best on
		# this test goes under them, from the stored telemetry
		# (TelemetryRecorder.best_line). Never driven it before, no line.
		var best := TelemetryRecorder.best_line(_telemetry_index(), run.test)
		if best != "":
			detail += "\n" + best
	detail += "\n" + _keys_hint()
	hud.show_mission_banner(headline, detail, color)


## The test's medal times on one line: "GOLD 20.5 s   SILVER 23.5 s   ...".
func _medal_times_text(test: Dictionary) -> String:
	var entries := PackedStringArray()
	for medal in HandlingTests.MEDALS:
		var key := medal + "_time_s"
		if test.has(key):
			entries.append("%s %.1f s" % [medal.to_upper(), test[key]])
	return "   ".join(entries)


func _keys_hint() -> String:
	return "%d  retry      1-%d  pick a test      Esc  close" % [selected_index + 1, START_ACTIONS.size()]


# =============================================================================
#  Run markers
# =============================================================================

## Builds the start orb and the finish chevron, hidden, under one Node3D of this
## node's own. Meshes only: no body, no shape, the car drives through them.
func _build_markers() -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = MARKER_COLOR
	material.roughness = 0.4
	material.emission_enabled = true
	material.emission = MARKER_COLOR
	material.emission_energy_multiplier = MARKER_EMISSION_ENERGY

	_markers = Node3D.new()
	_markers.name = "RunMarkers"
	_markers.visible = false
	add_child(_markers)

	var orb := SphereMesh.new()
	orb.radius = START_ORB_RADIUS
	orb.height = START_ORB_RADIUS * 2.0
	orb.radial_segments = 24
	orb.rings = 12
	orb.material = material
	_start_orb = MeshInstance3D.new()
	_start_orb.name = "StartOrb"
	_start_orb.mesh = orb
	_start_orb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_markers.add_child(_start_orb)

	# The chevron's own origin is its tip. Turned about Z, a bar's length (its
	# Y) points up and out to `side`.
	var arm := BoxMesh.new()
	arm.size = FINISH_CHEVRON_ARM_SIZE
	arm.material = material
	_finish_chevron = Node3D.new()
	_finish_chevron.name = "FinishChevron"
	_markers.add_child(_finish_chevron)
	for side: float in [-1.0, 1.0]:
		var instance := MeshInstance3D.new()
		instance.mesh = arm
		instance.basis = Basis(Vector3.BACK, -side * deg_to_rad(FINISH_CHEVRON_ARM_DEG))
		instance.position = instance.basis.y * FINISH_CHEVRON_ARM_SIZE.y * 0.5
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_finish_chevron.add_child(instance)


## Puts the orb by `test`'s start point (where HandlingTests._start() puts the
## car: the spawn point plus the test's start_offset) and the chevron by its
## goal, if it has one, both standing on the pad's ground, and shows them.
func _show_markers(test: Dictionary) -> void:
	var start_offset: Vector3 = test.get("start_offset", Vector3.ZERO)
	var orb_at := car.get_spawn_transform().origin + start_offset + START_ORB_OFFSET
	orb_at.y = _ground_height(orb_at.x, orb_at.z) + START_ORB_HEIGHT
	_start_orb.position = orb_at

	var goal := _goal_marker_position(test)
	_finish_chevron.visible = goal.is_finite()
	if _finish_chevron.visible:
		goal.y = _ground_height(goal.x, goal.z) + FINISH_CHEVRON_TIP_HEIGHT
		_finish_chevron.position = goal
	_markers.visible = true


func _hide_markers() -> void:
	_markers.visible = false


## Where the chevron goes (x and z; the height is the ground's), or Vector3.INF
## for none.
func _goal_marker_position(test: Dictionary) -> Vector3:
	# was: the spins and the reverse 180 end wherever the car does, orb only ->
	# they have a goal now: a chevron by a drive-on goal; a return to the start
	# ends at the orb, no chevron.
	if test.get("goal_mode", &"") == HandlingTests.GOAL_DRIVE_ON:
		return run.goal_position() + Vector3.RIGHT * FINISH_CHEVRON_GOAL_OFFSET
	match test.kind:
		HandlingTests.KIND_STOP_BOX:
			var box := TestPad.stop_box()
			var centre: Vector3 = box.centre
			var size: Vector2 = box.size
			return centre + Vector3.RIGHT * (size.x * 0.5 + FINISH_CHEVRON_BOX_CLEARANCE)
		HandlingTests.KIND_SLALOM:
			var last_cone: Vector3 = TestPad.slalom_cone_positions().back()
			return last_cone + FINISH_CHEVRON_SLALOM_OFFSET
		_:
			return Vector3.INF


## Height of the pad's ground at (x, z) [m]; level without a pad.
func _ground_height(x: float, z: float) -> float:
	return pad.elevation_height(x, z) if pad else 0.0
