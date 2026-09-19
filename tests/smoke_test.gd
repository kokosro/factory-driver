extends SceneTree
## Headless smoke test for the main scene. Run via tests/run_tests.sh, or:
##
##   godot --headless --path . --import
##   godot --headless --path . --script res://tests/smoke_test.gd
##
## Loads the main scene, checks the key nodes exist, then drives the car with
## simulated input and checks it accelerates, steers, brakes and reverses.
## Exits 0 on success, 1 on any failed check. Later phases extend this file.

const MAIN_SCENE := "res://scenes/main.tscn"

var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var packed: PackedScene = load(MAIN_SCENE)
	if not _check(packed != null, "main scene loads"):
		_finish()
		return
	var main := packed.instantiate()
	root.add_child(main)
	await _step(60)

	var car := main.get_node_or_null("Car") as ArcadeCar
	var hud := main.get_node_or_null("HUD")
	var speed_label := main.get_node_or_null("HUD/SpeedLabel") as Label
	var camera := main.get_node_or_null("ChaseCamera") as Camera3D
	_check(car != null, "car node exists and is an ArcadeCar")
	_check(hud != null and speed_label != null, "HUD with speed label exists")
	_check(camera != null and camera.current, "chase camera exists and is current")
	_check(main.get_node_or_null("Sun") is DirectionalLight3D, "sun light exists")
	_check(main.get_node_or_null("WorldEnvironment") is WorldEnvironment, "world environment exists")
	_check(main.get_node("TestPad").get_child_count() > 1, "test pad generated its markers")
	if car == null or speed_label == null or camera == null:
		_finish()
		return

	_check(car.is_on_floor(), "car rests on the ground")
	_check(absf(car.forward_speed) < 0.01, "car is stationary without input (%.3f m/s)" % car.forward_speed)
	_check(speed_label.text == "0 km/h", "HUD reads 0 km/h at rest ('%s')" % speed_label.text)

	# Accelerate: moves along -Z, HUD follows, camera keeps up.
	Input.action_press("accelerate")
	await _step(120)
	_check(car.forward_speed > 10.0, "accelerates forward (%.1f m/s after 2 s)" % car.forward_speed)
	_check(car.global_position.z < -10.0, "travels along -Z (z = %.1f)" % car.global_position.z)
	_check(absf(car.global_position.x) < 0.01, "tracks straight without steering (x = %.3f)" % car.global_position.x)
	_check(speed_label.text == "%d km/h" % roundi(car.speed_kmh), "HUD shows current speed ('%s')" % speed_label.text)
	var camera_gap := camera.global_position.distance_to(car.global_position)
	_check(camera_gap > 3.0 and camera_gap < 15.0, "camera follows the car (%.1f m away)" % camera_gap)

	# Steer left: heading yaws positive, car drifts towards -X.
	var yaw_before := car.global_rotation.y
	Input.action_press("steer_left")
	await _step(45)
	Input.action_release("steer_left")
	_check(angle_difference(yaw_before, car.global_rotation.y) > 0.2, "steers left (yaw %.2f -> %.2f)" % [yaw_before, car.global_rotation.y])
	_check(car.global_position.x < -0.5, "turning left moves the car towards -X (x = %.1f)" % car.global_position.x)

	# Steer right turns the other way (once the steering has re-centred).
	await _step(15)
	yaw_before = car.global_rotation.y
	Input.action_press("steer_right")
	await _step(45)
	Input.action_release("steer_right")
	_check(angle_difference(yaw_before, car.global_rotation.y) < -0.2, "steers right (yaw %.2f -> %.2f)" % [yaw_before, car.global_rotation.y])
	Input.action_release("accelerate")
	await _step(30)
	_check(absf(car.lateral_speed) < 0.5, "lateral slip settles after steering (%.2f m/s)" % car.lateral_speed)

	# Coast, then brake to a stop and carry on into reverse.
	var speed_before := car.forward_speed
	await _step(30)
	_check(car.forward_speed < speed_before and car.forward_speed > 0.0, "coasts down gently (%.1f -> %.1f m/s)" % [speed_before, car.forward_speed])
	speed_before = car.forward_speed
	Input.action_press("brake")
	await _step(20)
	_check(car.forward_speed < speed_before - 5.0, "brakes hard (%.1f -> %.1f m/s)" % [speed_before, car.forward_speed])
	await _step(240)
	_check(car.forward_speed < -1.0, "reverses after stopping (%.1f m/s)" % car.forward_speed)
	_check(car.forward_speed >= -ArcadeCar.MAX_REVERSE_SPEED - 0.01, "reverse speed is capped (%.1f m/s)" % car.forward_speed)
	_check(speed_label.text.begins_with("R"), "HUD flags reverse ('%s')" % speed_label.text)
	Input.action_release("brake")

	# Reset puts the car back on the start line.
	car.reset_to_spawn()
	await _step(5)
	_check(car.global_position.length() < 0.1, "reset returns the car to spawn")

	_finish()


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
	if _failures == 0:
		print("SMOKE TEST PASSED")
	else:
		printerr("SMOKE TEST FAILED: %d check(s) failed" % _failures)
	quit(1 if _failures > 0 else 0)
