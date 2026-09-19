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
## would. Each mission must come out PASSED with its metrics filled in, and the
## HUD must have shown its progress.
##
## Then the engineered FAIL: the slalom again, with the pilot's steering
## released straight after every tick, so the car runs straight past the cones.
## The manager must report FAILED through the real gate check. Last, the keys:
## a mission started with its number key and aborted with Esc.
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
}
const EXPECTED_HUD_WORD := {
	HandlingTests.KIND_SLALOM: "GATE",
	HandlingTests.KIND_SPIN: "ROTATION",
	HandlingTests.KIND_STOP_BOX: "BRAKE!",
}

const STEERING: Array[StringName] = [&"steer_left", &"steer_right"]

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
	_check(_mission_label.text.contains("1 ") and _mission_label.text.contains("4 "), "idle mission line lists the test keys ('%s')" % _mission_label.text)
	_check(not _manager.start_mission(99), "starting a test that does not exist is refused")

	var tests := HandlingTests.all_tests()
	for index in tests.size():
		await _play_mission(index, tests[index], false)
	_check(_finished_signals == tests.size(), "mission_finished fired once per mission (%d)" % _finished_signals)

	await _play_mission(0, tests[0], true)
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
	_check(not _manager.start_mission((index + 1) % 4), "%s: other tests are refused while it runs" % label)

	var pilot := HandlingTests.begin(definition, _car, _pad, true)
	var delta := 1.0 / Engine.physics_ticks_per_second
	var hud_word: String = EXPECTED_HUD_WORD[definition.kind]
	var saw_progress := false
	var saw_timer := false
	var frames := 0
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
			saw_timer = saw_timer or _mission_label.text.contains(" s")
	Input.action_release("handbrake")

	if not _check(not _manager.is_running() and pilot.finished, "%s: mission and pilot both finish (%d frames)" % [label, frames]):
		_manager.abort_mission()
		pilot.abort()
		return
	var outcome := _manager.last_result
	for line in HandlingTests.format_result(outcome):
		print("  ", line)
	_check(saw_progress and saw_timer, "%s: HUD mission line showed '%s' progress and the timer" % [label, hud_word])
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
	else:
		_check(outcome.passed == true, "%s: manager reports PASSED" % label)
		_check(_banner.text.begins_with("PASSED"), "%s: banner says PASSED ('%s')" % [label, _banner.text])
		_check(pilot.result().passed, "%s: the pilot's own run passed too" % label)


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
