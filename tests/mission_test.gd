extends SceneTree
## Headless mission mode test. Run via tests/run_tests.sh, or:
##
##   godot --headless --path . --import
##   godot --headless --fixed-fps 60 --path . --script res://tests/mission_test.gd
##
## Loads the main scene and plays every mission through the MissionManager the
## way a player would: the manager starts a human run (scripted driver off) and
## judges it, while a "pilot" - the same test begun a second time with the
## scripted driver on - works the input actions, exactly like the keyboard
## would. Each mission must come out PASSED with its metrics filled in, the HUD
## must have shown its progress, and the banner must show the medal the run's
## time earned. Before that, the medal times themselves: every test has them in
## order, and HandlingTests.medal_for() maps a time to its medal.
##
## Then the engineered FAIL: the slalom again, with the pilot's steering
## released straight after every tick, so the car runs straight past the cones.
## The manager must report FAILED through the real gate check. And a second
## one: the 180 spun cleanly and then left parked where it stopped, which must
## fail through the goal check alone. Last, the keys: a mission started with its
## number key and aborted with Esc.
##
## The run clock rides along on every mission (HandlingTests, "The run
## clock"): it reads "not started" and stays at 0 until the car crosses the
## test's start line, starts the tick it does, and what the verdict reports as
## run_time_s is the window from that crossing to the finish - less than the
## time since the test began, which is what it used to be. And the complaint it
## answers, checked where the abort test sits still for 2 s: waiting on the
## start point costs nothing.
##
## The idle line is checked against the telemetry summary it now ends with,
## built through the recorder's own helper (scripts/telemetry.gd): nothing is
## recorded with no window, but whatever earlier driving stored is read and
## shown, so the check has to hold with and without it.
## Exits 0 on success, 1 on any failed check.

const MAIN_SCENE := "res://scenes/main.tscn"

## Physics frames to let the car settle on the ground at the start.
const SETTLE_FRAMES := 20

## Give up on a mission after this many physics frames (70 s).
const MAX_MISSION_FRAMES := 4200

## Metrics every mission of a kind must report, and the word its HUD line shows.
const EXPECTED_METRICS := {
	HandlingTests.KIND_SLALOM: ["gates_passed", "cones_hit", "slalom_time_s", "run_time_s"],
	HandlingTests.KIND_SPIN: ["rotation_deg", "heading_error_deg", "run_time_s"],
	HandlingTests.KIND_STOP_BOX: ["box_margin_m", "centre_error_m", "run_time_s"],
	HandlingTests.KIND_REVERSE_SPIN: ["rotation_deg", "heading_error_deg", "exit_speed_ms", "run_time_s"],
}
const EXPECTED_HUD_WORD := {
	HandlingTests.KIND_SLALOM: "GATE",
	HandlingTests.KIND_SPIN: "ROTATION",
	HandlingTests.KIND_STOP_BOX: "BRAKE!",
	HandlingTests.KIND_REVERSE_SPIN: "ROTATION",
}

## The words a test with a goal shows on its HUD line once the manoeuvre is
## done and the car is on its way there.
const EXPECTED_GOAL_WORD := {
	HandlingTests.GOAL_RETURN_TO_START: "RETURN TO START",
	HandlingTests.GOAL_DRIVE_ON: "DRIVE ON",
}

## How many steps of the 180's script it takes to spin the car and get on the
## brakes: accelerate, flick, catch, brake.
const SPIN_180_STEPS_TO_THE_STOP := 4

const STEERING: Array[StringName] = [&"steer_left", &"steer_right"]

## Run clock: how far the finished run's run_time_s may be from the window
## reckoned from outside (time since the test began at the end of the run, less
## what it was at the crossing, less the settle) [s]: a tick and the rounding.
const RUN_CLOCK_TOLERANCE := 0.03

var _failures := 0
var _manager: MissionManager
var _car: ArcadeCar
var _pad: TestPad
var _mission_label: Label
var _banner: Label
var _finished_signals := 0
var _aborted_signals := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var packed: PackedScene = load(MAIN_SCENE)
	if not _check(packed != null, "main scene loads"):
		_finish()
		return
	var main := packed.instantiate()
	root.add_child(main)
	await _step(SETTLE_FRAMES)

	_manager = main.get_node_or_null("MissionManager") as MissionManager
	_car = main.get_node_or_null("Car") as ArcadeCar
	_pad = main.get_node_or_null("TestPad") as TestPad
	_mission_label = main.get_node_or_null("HUD/MissionLabel") as Label
	_banner = main.get_node_or_null("HUD/MissionBanner") as Label
	if not _check(_manager != null and _car != null and _pad != null, "MissionManager, Car and TestPad exist"):
		_finish()
		return
	if not _check(_mission_label != null and _banner != null, "HUD has a mission line and a banner"):
		_finish()
		return
	_manager.mission_finished.connect(func(_index: int, _outcome: Dictionary) -> void: _finished_signals += 1)
	_manager.mission_aborted.connect(func(_index: int) -> void: _aborted_signals += 1)

	_check(_manager.state == MissionManager.State.IDLE, "manager starts idle")
	_check(not _banner.visible, "no banner while idle")
	var tests := HandlingTests.all_tests()
	_check(tests.size() == 5 and MissionManager.START_ACTIONS.size() == tests.size(), "five tests, one start key each (%d tests, %d keys)" % [tests.size(), MissionManager.START_ACTIONS.size()])
	var listed := true
	for index in tests.size():
		listed = listed and _mission_label.text.contains("%d %s" % [index + 1, tests[index].title])
		listed = listed and InputMap.has_action(MissionManager.START_ACTIONS[index])
	_check(listed, "idle mission line lists every test with its key, and every key has its input action ('%s')" % _mission_label.text)
	# was: the line ended at "C  camera" -> it ends with a summary of the stored
	# telemetry when the machine has any (a headless run records nothing, but it
	# still reads what earlier driving left behind). The expected string is built
	# through the same helper the manager builds it with, so this holds either
	# way: no data, no suffix.
	var summary := TelemetryRecorder.idle_suffix(_manager.telemetry.index if _manager.telemetry else {})
	_check(_manager.telemetry != null and not _manager.telemetry.recording, "the manager owns a telemetry recorder, recording nothing with no window")
	_check(_mission_label.text.ends_with("C  camera" + summary), "idle mission line ends with the stored telemetry's summary (%s)" % ("'%s'" % summary if summary != "" else "nothing stored, nothing appended"))
	_check(not _manager.start_mission(99), "starting a test that does not exist is refused")

	for definition in tests:
		_check_medal_times(definition)
	for index in tests.size():
		await _play_mission(index, tests[index], false)
	_check(_finished_signals == tests.size(), "mission_finished fired once per mission (%d)" % _finished_signals)

	await _play_mission(0, tests[0], true)
	await _check_no_return(1, tests[1])
	await _check_abort(1, tests[1])

	_car.reset_to_spawn()
	_pad.reset_cones()
	_finish()


## Plays one mission with the scripted pilot at the controls. With
## `suppress_steering` the pilot's steering never reaches the car and the
## mission is expected to fail; otherwise it is expected to pass.
func _play_mission(index: int, definition: Dictionary, suppress_steering: bool) -> void:
	var label: String = definition.name + (" without steering" if suppress_steering else "")
	print("-- mission %d: %s" % [index + 1, label])
	if not _check(_manager.start_mission(index), "%s: manager starts the mission" % label):
		return
	_check(_manager.state == MissionManager.State.RUNNING and _manager.selected_index == index, "%s: manager is running test %d" % [label, index + 1])
	_check(not _manager.run.scripted, "%s: the manager's run is a human run" % label)
	_check(not _banner.visible, "%s: starting clears the banner" % label)
	_check(_mission_label.text.contains(definition.title), "%s: mission line shows at once ('%s')" % [label, _mission_label.text.get_slice("\n", 0)])
	_check(not _manager.start_mission((index + 1) % MissionManager.START_ACTIONS.size()), "%s: other tests are refused while it runs" % label)
	var target_time: float = definition.target_time_s
	var waiting_clock := "%s / %.1f s" % [MissionManager.CLOCK_NOT_STARTED, target_time]
	_check(
		not _manager.run.started() and _manager.run.run_time() == 0.0 and _mission_label.text.get_slice("\n", 0).ends_with(waiting_clock),
		"%s: the run clock has not started on the start point, and the mission line says so ('%s')" % [label, waiting_clock],
	)

	var pilot := HandlingTests.begin(definition, _car, _pad, true)
	var delta := 1.0 / Engine.physics_ticks_per_second
	var hud_word: String = EXPECTED_HUD_WORD[definition.kind]
	var goal_word: String = EXPECTED_GOAL_WORD.get(definition.get("goal_mode", &""), "")
	var saw_progress := false
	var saw_goal := false
	var saw_timer := false
	var frames := 0
	# The run clock, watched from outside: before the crossing it must stand at 0
	# and read "not started"; the frame it starts the car must be just over the
	# line; from then on the line must show the clock's own reading.
	var run: HandlingTests = _manager.run
	var line_z: float = definition.start_line_z
	var frames_waiting := 0
	var clock_ran_early := false
	var started_at_elapsed := -1.0
	var started_at_z := 0.0
	var z_before_start := 0.0
	var previous_z := _car.global_position.z
	var running_clock_shown := true
	# The pilot may outlast the mission (the slalom pilot straightens up after
	# the last gate) or fall short of it (the 360 pilot leaves the car rolling;
	# a human run wants it stopped, so the handbrake goes on once the pilot is
	# done, as a player would).
	while (_manager.is_running() or not pilot.finished) and frames < MAX_MISSION_FRAMES:
		pilot.tick(delta)
		if suppress_steering:
			for action in STEERING:
				Input.action_release(action)
			if not _manager.is_running():
				pilot.abort()
		elif pilot.finished and _manager.is_running():
			Input.action_press("handbrake")
		await physics_frame
		frames += 1
		if _manager.is_running():
			saw_progress = saw_progress or _mission_label.text.contains(hud_word)
			saw_goal = saw_goal or (goal_word != "" and _mission_label.text.contains(goal_word))
			saw_timer = saw_timer or _mission_label.text.contains(" s")
			var clock_text := _mission_label.text.get_slice("\n", 0)
			if not run.started():
				frames_waiting += 1
				clock_ran_early = clock_ran_early or run.run_time() != 0.0 or not clock_text.ends_with(waiting_clock)
			else:
				if started_at_elapsed < 0.0:
					started_at_elapsed = run.elapsed
					started_at_z = _car.global_position.z
					z_before_start = previous_z
				running_clock_shown = running_clock_shown and clock_text.ends_with("  %.1f / %.1f s" % [run.run_time(), target_time])
		previous_z = _car.global_position.z
	Input.action_release("handbrake")

	if not _check(not _manager.is_running() and pilot.finished, "%s: mission and pilot both finish (%d frames)" % [label, frames]):
		_manager.abort_mission()
		pilot.abort()
		return
	var outcome := _manager.last_result
	for line in HandlingTests.format_result(outcome):
		print("  ", line)
	_check(saw_progress and saw_timer, "%s: HUD mission line showed '%s' progress and the timer" % [label, hud_word])
	_check(
		frames_waiting > 0 and not clock_ran_early,
		"%s: the clock stood at 0 and read '%s' for the %d frames before the start line" % [label, MissionManager.CLOCK_NOT_STARTED, frames_waiting],
	)
	_check(
		started_at_elapsed > 0.0 and z_before_start > line_z and started_at_z <= line_z,
		"%s: the clock started the frame the car crossed its start line at z = %.1f (z %.2f -> %.2f, %.2f s into the test)" % [label, line_z, z_before_start, started_at_z, started_at_elapsed],
	)
	_check(running_clock_shown, "%s: from the crossing on the mission line showed the run clock against the target time" % label)
	var reported: float = outcome.get("metrics", {}).get("run_time_s", INF)
	_check(
		is_equal_approx(reported, snappedf(run.run_time(), 0.01)) and reported > 0.0 and reported < run.elapsed - started_at_elapsed,
		"%s: run_time_s is the run clock, not the time since the test began (%.2f s of %.2f s; over the line at %.2f s)" % [label, reported, run.elapsed, started_at_elapsed],
	)
	# A human run ends `settle` seconds after its finish, so the window from the
	# crossing to the finish can be reckoned from outside too.
	var window: float = run.elapsed - started_at_elapsed - definition.settle
	_check(
		absf(reported - window) <= RUN_CLOCK_TOLERANCE,
		"%s: run_time_s is the window from the crossing to the finish (%.2f s reported, %.2f s reckoned)" % [label, reported, window],
	)
	if goal_word != "":
		_check(saw_goal, "%s: HUD mission line went on to '%s' once the spin was done" % [label, goal_word])
	_check(_manager.state == MissionManager.State.RESULT and _banner.visible, "%s: result banner is up" % label)
	_check(outcome.get("name", "") == definition.name, "%s: result is for this test" % label)

	var metrics: Dictionary = outcome.get("metrics", {})
	var missing := PackedStringArray()
	for key: String in EXPECTED_METRICS[definition.kind]:
		if not metrics.has(key) or str(metrics[key]) == "":
			missing.append(key)
	_check(not metrics.is_empty() and missing.is_empty(), "%s: metrics are populated (missing: %s)" % [label, ", ".join(missing)])

	if suppress_steering:
		_check(outcome.passed == false, "%s: manager reports FAILED" % label)
		var gate_check_failed := false
		for check: Dictionary in outcome.checks:
			if check.label.contains("gate") and not check.passed:
				gate_check_failed = true
		_check(gate_check_failed, "%s: failed through the real gate check (gates %s)" % [label, metrics.get("gates_passed", "?")])
		_check(_banner.text.begins_with("FAILED"), "%s: banner says FAILED ('%s')" % [label, _banner.text])
		var failed_time: float = metrics.get("run_time_s", INF)
		_check(_banner.text == "FAILED  %s" % definition.title and HandlingTests.medal_for(definition, failed_time) != "", "%s: no medal on a failed run, however quick (%.2f s would be %s)" % [label, failed_time, HandlingTests.medal_for(definition, failed_time)])
	else:
		_check(outcome.passed == true, "%s: manager reports PASSED" % label)
		_check(_banner.text.begins_with("PASSED"), "%s: banner says PASSED ('%s')" % [label, _banner.text])
		_check(pilot.result().passed, "%s: the pilot's own run passed too" % label)
		var run_time: float = metrics.get("run_time_s", INF)
		var medal := HandlingTests.medal_for(definition, run_time)
		_check(medal != "", "%s: the certified drive earns a medal (%s, %.2f s)" % [label, medal, run_time])
		_check(_banner.text == "PASSED  %s — %s" % [definition.title, medal.to_upper()], "%s: banner shows the medal its %.2f s earned ('%s')" % [label, run_time, _banner.text])
		var tint: Color = MissionManager.BANNER_COLOR_MEDAL.get(medal, MissionManager.BANNER_COLOR_PASSED)
		_check(_banner.get_theme_color("font_color").is_equal_approx(tint), "%s: headline is tinted %s" % [label, medal])
		if goal_word != "":
			var goal_checked := false
			for check: Dictionary in outcome.checks:
				if (check.label.contains("the start") or check.label.contains("the goal")) and check.passed:
					goal_checked = true
			_check(goal_checked, "%s: passed through the goal check, on top of the manoeuvre's own" % label)


## A test's medal times are there and in order, and medal_for() maps a time to
## its medal: gold up to the gold time, silver up to the silver time, bronze up
## to the bronze time, nothing beyond. Pure data, no driving.
func _check_medal_times(definition: Dictionary) -> void:
	var label: String = definition.name
	var gold: float = definition.get("gold_time_s", 0.0)
	var silver: float = definition.get("silver_time_s", 0.0)
	var bronze: float = definition.get("bronze_time_s", 0.0)
	_check(0.0 < gold and gold < silver and silver < bronze, "%s: has medal times, gold < silver < bronze (%.1f / %.1f / %.1f s)" % [label, gold, silver, bronze])
	var mapped := HandlingTests.medal_for(definition, gold * 0.5) == "gold" \
		and HandlingTests.medal_for(definition, gold) == "gold" \
		and HandlingTests.medal_for(definition, (gold + silver) * 0.5) == "silver" \
		and HandlingTests.medal_for(definition, silver) == "silver" \
		and HandlingTests.medal_for(definition, (silver + bronze) * 0.5) == "bronze" \
		and HandlingTests.medal_for(definition, bronze) == "bronze" \
		and HandlingTests.medal_for(definition, bronze + 0.01) == ""
	_check(mapped, "%s: a fast time maps to gold, a middling one to silver, a slow one to bronze, one over the bronze time to no medal" % label)
	_check(HandlingTests.medal_for({}, 1.0) == "", "%s: a test without medal times gives no medal" % label)


## The 180 without the drive back: the pilot's script is cut off once it is on
## the brakes after the spin, and the car is left parked there. The verdict is
## rotation AND goal: the rotation check passes, the run never gets back to the
## start, runs out of time and fails.
func _check_no_return(index: int, definition: Dictionary) -> void:
	var label: String = definition.name + " without the drive back"
	print("-- mission %d: %s" % [index + 1, label])
	if not _check(_manager.start_mission(index), "%s: manager starts the mission" % label):
		return
	var spin_only := definition.duplicate()
	var steps: Array = definition.steps
	spin_only.steps = steps.slice(0, SPIN_180_STEPS_TO_THE_STOP)
	var pilot := HandlingTests.begin(spin_only, _car, _pad, true)
	var delta := 1.0 / Engine.physics_ticks_per_second
	var frames := 0
	while (_manager.is_running() or not pilot.finished) and frames < MAX_MISSION_FRAMES:
		pilot.tick(delta)
		if pilot.finished and _manager.is_running():
			Input.action_press("handbrake")
		await physics_frame
		frames += 1
	Input.action_release("handbrake")
	if not _check(not _manager.is_running() and pilot.finished, "%s: mission and pilot both finish (%d frames)" % [label, frames]):
		_manager.abort_mission()
		pilot.abort()
		return
	var outcome := _manager.last_result
	for line in HandlingTests.format_result(outcome):
		print("  ", line)
	var rotation_passed := false
	var goal_failed := false
	for check: Dictionary in outcome.checks:
		if check.label.begins_with("rotation"):
			rotation_passed = check.passed
		if check.label.contains("the start"):
			goal_failed = not check.passed
	# A run that never gets to its finish: the clock started at the line and ran
	# to the end, which the time limit (still counted from the start of the test)
	# called.
	var timed_out_run: HandlingTests = _manager.run
	var limit: float = definition.time_limit
	_check(
		timed_out_run.started() and timed_out_run.elapsed >= limit and outcome.metrics.run_time_s > 0.0 and outcome.metrics.run_time_s < limit,
		"%s: the time limit still counts from the start of the test (%.2f s), the run clock from the line (%.2f s)" % [label, timed_out_run.elapsed, outcome.metrics.run_time_s],
	)
	_check(rotation_passed, "%s: the spin itself passes its rotation check (%.1f degrees)" % [label, outcome.metrics.get("rotation_deg", 0.0)])
	_check(outcome.passed == false and goal_failed, "%s: manager reports FAILED through the goal check" % label)
	_check(_banner.text.begins_with("FAILED"), "%s: banner says FAILED ('%s')" % [label, _banner.text.get_slice("\n", 0)])


## Started by its number key and aborted with Esc: no verdict, a brief ABORTED
## banner, then back to idle on its own.
func _check_abort(index: int, definition: Dictionary) -> void:
	var label: String = definition.name + " aborted"
	print("-- mission %d: %s" % [index + 1, label])
	await _tap(MissionManager.START_ACTIONS[index])
	_check(_manager.is_running() and _manager.selected_index == index, "%s: key %d starts the mission" % [label, index + 1])
	await _tap(MissionManager.START_ACTIONS[0])
	_check(_manager.is_running() and _manager.selected_index == index, "%s: other test keys are ignored while it runs" % label)
	await _step(120)
	_check(_manager.is_running(), "%s: still running after 2 s at a standstill" % label)
	var waiting_clock := "%s / %.1f s" % [MissionManager.CLOCK_NOT_STARTED, definition.target_time_s]
	_check(
		_manager.run.elapsed >= 2.0 and not _manager.run.started() and _manager.run.run_time() == 0.0 and _mission_label.text.get_slice("\n", 0).ends_with(waiting_clock),
		"%s: waiting on the start point costs nothing: %.2f s into the test the clock still reads '%s'" % [label, _manager.run.elapsed, waiting_clock],
	)
	await _tap(&"abort_mission")
	_check(_manager.state == MissionManager.State.RESULT and _manager.run.finished, "%s: abort ends the run" % label)
	_check(_manager.last_result.is_empty() and _aborted_signals == 1, "%s: no verdict, mission_aborted fired" % label)
	_check(_banner.visible and _banner.text.begins_with("ABORTED"), "%s: banner says ABORTED ('%s')" % [label, _banner.text])
	await _step(int(MissionManager.ABORT_BANNER_TIME * Engine.physics_ticks_per_second) + 5)
	_check(_manager.state == MissionManager.State.IDLE and not _banner.visible, "%s: banner times out, back to idle" % label)


func _tap(action: StringName) -> void:
	Input.action_press(action)
	await _step(2)
	Input.action_release(action)
	await _step(2)


func _step(frames: int) -> void:
	for i in frames:
		await physics_frame


func _check(condition: bool, description: String) -> bool:
	if condition:
		print("  ok    ", description)
	else:
		_failures += 1
		printerr("  FAIL  ", description)
	return condition


func _finish() -> void:
	for action in HandlingTests.ACTIONS:
		Input.action_release(action)
	if _failures == 0:
		print("MISSION TEST PASSED")
	else:
		print("MISSION TEST FAILED: %d check(s) failed" % _failures)
	quit(1 if _failures > 0 else 0)
