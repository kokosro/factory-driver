extends SceneTree
## Headless handling tests. Run via tests/run_tests.sh, or:
##
##   godot --headless --path . --import
##   godot --headless --fixed-fps 60 --path . --script res://tests/handling_test.gd
##
## Loads the main scene and lets the scripted driver of every test in
## scripts/handling_tests.gd drive the real car, one after the other, from a
## fresh start each time. Prints "PASS name" / "FAIL name" plus a metrics line
## per test. Exits 0 only if every test passes. Add `-- --trace` to also print
## the car's state every TRACE_INTERVAL frames, and `-- --only=NAME` to run a
## single test, when tuning a test or the car.
## (--fixed-fps just stops the run waiting for the wall clock; the physics
## steps are the same 1/60 s either way.)

const MAIN_SCENE := "res://scenes/main.tscn"

## Physics frames to let the car settle on the ground after each reset.
const SETTLE_FRAMES := 20

## With --trace, print the run's state every this many physics frames.
const TRACE_INTERVAL := 10


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var packed: PackedScene = load(MAIN_SCENE)
	if packed == null:
		printerr("FAIL main scene does not load")
		quit(1)
		return
	var main := packed.instantiate()
	root.add_child(main)
	await _step(SETTLE_FRAMES)

	var car := main.get_node_or_null("Car") as ArcadeCar
	var pad := main.get_node_or_null("TestPad") as TestPad
	if car == null or pad == null:
		printerr("FAIL main scene has no Car / TestPad")
		quit(1)
		return

	var trace := false
	var only := ""
	for argument in OS.get_cmdline_user_args():
		if argument == "--trace":
			trace = true
		elif argument.begins_with("--only="):
			only = argument.trim_prefix("--only=")

	var delta := 1.0 / Engine.physics_ticks_per_second
	var failures := 0
	for definition in HandlingTests.all_tests():
		if only != "" and definition.name != only:
			continue
		var run := HandlingTests.begin(definition, car, pad)
		await _step(SETTLE_FRAMES)
		var frame := 0
		while not run.finished:
			run.tick(delta)
			await physics_frame
			frame += 1
			if trace and frame % TRACE_INTERVAL == 0:
				print("  ", run.describe_state())
		var outcome := run.result()
		for line in HandlingTests.format_result(outcome):
			print(line)
		if not outcome.passed:
			failures += 1

	car.reset_to_spawn()
	pad.reset_cones()
	if failures == 0:
		print("HANDLING TESTS PASSED")
	else:
		print("HANDLING TESTS FAILED: %d test(s) failed" % failures)
	quit(1 if failures > 0 else 0)


func _step(frames: int) -> void:
	for i in frames:
		await physics_frame
