extends SceneTree
## Headless camera test. Run via tests/run_tests.sh, or:
##
##   godot --headless --path . --import
##   godot --headless --fixed-fps 60 --path . --script res://tests/camera_test.gd
##
## Loads the main scene and cycles the camera through its views with the
## camera_cycle action: chase -> cockpit -> front -> overhead -> chase. Checks
## each press lands on the expected view, that the view sits where it should
## relative to the car, and that the car still drives under it.
## Exits 0 on success, 1 on any failed check.

const MAIN_SCENE := "res://scenes/main.tscn"

## The views in the order the key cycles through them, from the default.
const EXPECTED_CYCLE: Array[String] = ["cockpit", "front", "overhead", "chase"]

## The car's body in its own space [m]: 1.8 wide, 4.2 long, roof at ~1.35.
const CAR_BOUNDS := AABB(Vector3(-0.9, 0.0, -2.1), Vector3(1.8, 1.4, 4.2))

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
	var camera := main.get_node_or_null("ChaseCamera") as Camera3D
	if not _check(car != null and camera != null, "car and camera exist"):
		_finish()
		return
	_check(camera.mode_name() == "chase", "camera starts in chase view ('%s')" % camera.mode_name())
	_check(main.get_node("HUD").visible, "HUD is visible")

	for expected in EXPECTED_CYCLE:
		Input.action_press("camera_cycle")
		await _step(2)
		Input.action_release("camera_cycle")
		await _step(2)
		if not _check(camera.mode_name() == expected, "camera_cycle switches to %s view ('%s')" % [expected, camera.mode_name()]):
			continue
		_check(camera.current, "%s: the one camera stays current" % expected)
		_check(main.get_node("HUD").visible, "%s: HUD stays visible" % expected)

		# Drive under this view, then judge where the camera sits while moving.
		car.reset_to_spawn()
		await _step(20)
		var speed_before := car.forward_speed
		Input.action_press("accelerate")
		Input.action_press("steer_left")
		await _step(60)
		Input.action_release("steer_left")
		_check(car.forward_speed > speed_before + 3.0, "%s: car accelerates (%.1f -> %.1f m/s)" % [expected, speed_before, car.forward_speed])
		_check_view(expected, camera, car)
		Input.action_release("accelerate")
		await _step(10)

	_check(camera.mode_name() == "chase", "four presses end back in chase view ('%s')" % camera.mode_name())
	var dashboard := car.get_node_or_null("CockpitDashboard") as Node3D
	_check(dashboard != null and not dashboard.visible, "cockpit dashboard is hidden outside the cockpit view")
	_finish()


func _check_view(view: String, camera: Camera3D, car: ArcadeCar) -> void:
	var local := car.global_transform.affine_inverse() * camera.global_position
	var looking := -camera.global_basis.z
	var nose := -car.global_basis.z
	match view:
		"cockpit":
			_check(CAR_BOUNDS.has_point(local), "cockpit: camera is inside the car's bounds (local %.2f, %.2f, %.2f)" % [local.x, local.y, local.z])
			_check(looking.dot(nose) > 0.95, "cockpit: looks along the car's nose (dot %.3f)" % looking.dot(nose))
			var dashboard := car.get_node_or_null("CockpitDashboard") as Node3D
			_check(dashboard != null and dashboard.is_visible_in_tree(), "cockpit: dashboard silhouette is shown")
			_check(dashboard != null and dashboard.find_children("*", "MeshInstance3D", true, false).size() >= 3, "cockpit: dashboard is built from primitives")
		"front":
			_check(local.z < -0.5 and local.z > -2.1 and absf(local.x) < 0.1, "front: camera sits over the bonnet (local z %.2f)" % local.z)
			_check(looking.dot(nose) > 0.95, "front: looks along the car's nose (dot %.3f)" % looking.dot(nose))
		"overhead":
			var height := camera.global_position.y - car.global_position.y
			_check(looking.dot(Vector3.UP) < -0.99, "overhead: camera looks straight down (dot %.3f)" % looking.dot(Vector3.UP))
			_check(height > 20.0 and height < 45.0, "overhead: camera is high above the car (%.1f m)" % height)
			var offset := camera.global_position - car.global_position
			_check(Vector2(offset.x, offset.z).length() < 15.0, "overhead: car stays in frame (%.1f m off centre)" % Vector2(offset.x, offset.z).length())
			_check(camera.global_basis.y.dot(Vector3.FORWARD) > 0.99, "overhead: north stays up the screen while the car turns")
		"chase":
			var gap := camera.global_position.distance_to(car.global_position)
			_check(gap > 3.0 and gap < 15.0, "chase: camera follows the car (%.1f m away)" % gap)
			_check(local.z > 0.0, "chase: camera is behind the car (local z %.2f)" % local.z)


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
	for action in ["camera_cycle", "accelerate", "steer_left"]:
		Input.action_release(action)
	if _failures == 0:
		print("CAMERA TEST PASSED")
	else:
		print("CAMERA TEST FAILED: %d check(s) failed" % _failures)
	quit(1 if _failures > 0 else 0)
