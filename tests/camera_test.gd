extends SceneTree
## Headless camera test. Run via tests/run_tests.sh, or:
##
##   godot --headless --path . --import
##   godot --headless --fixed-fps 60 --path . --script res://tests/camera_test.gd
##
## Loads the main scene and cycles the camera through its views with the
## camera_cycle action: chase -> cockpit -> front -> overhead -> wheel -> chase.
## Checks each press lands on the expected view, that the view sits where it
## should relative to the car, and that the car still drives under it. Then
## holds look_back (rear view while held, the old view back on release) and
## toggles xray_view (translucent body, primitives inside, physics untouched).
## Exits 0 on success, 1 on any failed check.

const MAIN_SCENE := "res://scenes/main.tscn"

## The views in the order the key cycles through them, from the default.
const EXPECTED_CYCLE: Array[String] = ["cockpit", "front", "overhead", "wheel", "chase"]

## The car's body in its own space [m]: 1.8 wide, 4.2 long, roof at ~1.35.
const CAR_BOUNDS := AABB(Vector3(-0.9, 0.0, -2.1), Vector3(1.8, 1.4, 4.2))

## Centre of the front-left wheel in the car's space [m] (scenes/car.tscn).
const FRONT_LEFT_WHEEL := Vector3(-0.86, 0.34, -1.3)

## The body meshes whose materials the X-ray view fades: the paint and the glass.
const XRAY_BODY_MESHES: Array[String] = ["Body/Lower", "Body/Cabin"]

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
		if expected == "wheel":
			# Still on the throttle: the view has to ride along with the car.
			var car_before := car.global_position
			await _step(30)
			var travelled := car.global_position.distance_to(car_before)
			var wheel_gap := _local(car, camera.global_position).distance_to(FRONT_LEFT_WHEEL)
			_check(travelled > 2.0 and wheel_gap < 2.2, "wheel: camera follows the car while driving (car moved %.1f m, camera still %.2f m from the wheel)" % [travelled, wheel_gap])
		Input.action_release("accelerate")
		await _step(10)

	_check(camera.mode_name() == "chase", "five presses end back in chase view ('%s')" % camera.mode_name())
	var dashboard := car.get_node_or_null("CockpitDashboard") as Node3D
	_check(dashboard != null and not dashboard.visible, "cockpit dashboard is hidden outside the cockpit view")

	await _check_look_back(camera, car)
	await _check_xray(car)
	_finish()


## Holds look_back from the chase view and from the cockpit: rear view while
## held, the interrupted view back on release, and the cycle never stops on it.
func _check_look_back(camera: Camera3D, car: ArcadeCar) -> void:
	var dashboard := car.get_node_or_null("CockpitDashboard") as Node3D
	for from in ["chase", "cockpit"]:
		if from == "cockpit":
			await _tap("camera_cycle")
		if not _check(camera.mode_name() == from, "look-back: starts from the %s view ('%s')" % [from, camera.mode_name()]):
			continue
		car.reset_to_spawn()
		await _step(20)
		Input.action_press("look_back")
		Input.action_press("accelerate")
		await _step(60)
		_check(camera.mode_name() == "rear", "look-back from %s: holding look_back shows the rear view ('%s')" % [from, camera.mode_name()])
		_check(camera.current, "look-back from %s: the one camera stays current" % from)
		_check(car.forward_speed > 3.0, "look-back from %s: car drives under the rear view (%.1f m/s)" % [from, car.forward_speed])
		_check_view("rear", camera, car)
		_check(dashboard != null and not dashboard.visible, "look-back from %s: cockpit dashboard is hidden in the rear view" % from)
		await _tap("camera_cycle")
		_check(camera.mode_name() == "rear", "look-back from %s: camera_cycle waits while look_back is held ('%s')" % [from, camera.mode_name()])
		Input.action_release("look_back")
		await _step(2)
		_check(camera.mode_name() == from, "look-back from %s: releasing restores the %s view ('%s')" % [from, from, camera.mode_name()])
		_check_view(from, camera, car)
		Input.action_release("accelerate")
		await _step(10)

	# Back round to chase: the cycle must pass wheel -> chase without a rear stop.
	for expected in ["front", "overhead", "wheel", "chase"]:
		await _tap("camera_cycle")
		_check(camera.mode_name() == expected, "look-back: the cycle skips the rear view (%s, got '%s')" % [expected, camera.mode_name()])


## Toggles the X-ray view on and off: the Xray node shows, the body materials
## fade and come back exactly, and the car drives the same throughout.
func _check_xray(car: ArcadeCar) -> void:
	var xray := car.get_node_or_null("Xray") as Node3D
	if not _check(xray != null, "x-ray: the car has an Xray node"):
		return
	_check(not xray.visible and not xray.is_on(), "x-ray: hidden by default")
	var parts := xray.find_children("*", "MeshInstance3D", true, false).size()
	_check(parts >= 10, "x-ray: chassis, engine and drivetrain are built from primitives (%d parts)" % parts)

	var materials: Array[BaseMaterial3D] = []
	var transparency_before: Array[int] = []
	var albedo_before: Array[Color] = []
	for path in XRAY_BODY_MESHES:
		var material := (car.get_node(path) as MeshInstance3D).mesh.surface_get_material(0) as BaseMaterial3D
		materials.append(material)
		transparency_before.append(material.transparency)
		albedo_before.append(material.albedo_color)
		_check(material.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED and material.albedo_color.a == 1.0, "x-ray: %s is opaque by default" % path)

	# Reference run with the X-ray off, to hold the X-ray run against.
	var reference_speed := await _launch(car)

	await _tap("xray_view")
	_check(xray.is_on() and xray.is_visible_in_tree(), "x-ray: xray_view shows the X-ray parts")
	for i in materials.size():
		_check(materials[i].transparency != BaseMaterial3D.TRANSPARENCY_DISABLED and materials[i].albedo_color.a < 1.0, "x-ray: %s turns translucent (alpha %.2f)" % [XRAY_BODY_MESHES[i], materials[i].albedo_color.a])
		var faded := materials[i].albedo_color
		_check(Color(faded.r, faded.g, faded.b, 1.0) == albedo_before[i], "x-ray: %s keeps its colour" % XRAY_BODY_MESHES[i])

	var xray_speed := await _launch(car)
	_check(xray_speed > 3.0, "x-ray: car still drives with the X-ray on (%.1f m/s)" % xray_speed)
	_check(xray_speed == reference_speed, "x-ray: physics untouched, same launch with and without (%.4f vs %.4f m/s)" % [xray_speed, reference_speed])

	await _tap("xray_view")
	_check(not xray.is_on() and not xray.visible, "x-ray: xray_view again hides the X-ray parts")
	for i in materials.size():
		_check(materials[i].transparency == transparency_before[i] and materials[i].albedo_color == albedo_before[i], "x-ray: %s is restored exactly" % XRAY_BODY_MESHES[i])

	# Round again: on and off must leave the same state as the first time.
	await _tap("xray_view")
	await _tap("xray_view")
	_check(not xray.is_on() and not xray.visible, "x-ray: a second on / off round ends hidden")
	for i in materials.size():
		_check(materials[i].transparency == transparency_before[i] and materials[i].albedo_color == albedo_before[i], "x-ray: %s is restored exactly after the second round" % XRAY_BODY_MESHES[i])


## Full throttle from the spawn for one second; returns the speed reached [m/s].
func _launch(car: ArcadeCar) -> float:
	car.reset_to_spawn()
	await _step(20)
	Input.action_press("accelerate")
	await _step(60)
	Input.action_release("accelerate")
	var reached := car.forward_speed
	await _step(10)
	return reached


## Presses and releases an action, two physics frames each.
func _tap(action: String) -> void:
	Input.action_press(action)
	await _step(2)
	Input.action_release(action)
	await _step(2)


func _local(car: ArcadeCar, point: Vector3) -> Vector3:
	return car.global_transform.affine_inverse() * point


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
		"wheel":
			var wheel_gap := local.distance_to(FRONT_LEFT_WHEEL)
			_check(wheel_gap > 0.6 and wheel_gap < 2.2, "wheel: camera sits near the front-left wheel (%.2f m from its centre)" % wheel_gap)
			_check(local.y > 0.05 and local.y < 0.9, "wheel: camera is close to the ground (local y %.2f)" % local.y)
			_check(not CAR_BOUNDS.has_point(local) and local.x < FRONT_LEFT_WHEEL.x, "wheel: camera is outside the body, on the left (local %.2f, %.2f, %.2f)" % [local.x, local.y, local.z])
			var to_wheel := (car.global_transform * FRONT_LEFT_WHEEL - camera.global_position).normalized()
			_check(looking.dot(to_wheel) > 0.9, "wheel: looks at the front-left wheel (dot %.3f)" % looking.dot(to_wheel))
			_check(looking.dot(Vector3.UP) < 0.0, "wheel: looks down at the tarmac (dot %.3f)" % looking.dot(Vector3.UP))
		"rear":
			_check(local.z < CAR_BOUNDS.position.z and absf(local.x) < 0.5, "rear: camera is ahead of the nose (local z %.2f)" % local.z)
			_check(local.y > 1.0 and local.y < 3.0, "rear: camera is above the bonnet (local y %.2f)" % local.y)
			_check(looking.dot(nose) < -0.9, "rear: looks backwards over the car (dot %.3f)" % looking.dot(nose))


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
	for action in ["camera_cycle", "accelerate", "steer_left", "look_back", "xray_view"]:
		Input.action_release(action)
	if _failures == 0:
		print("CAMERA TEST PASSED")
	else:
		print("CAMERA TEST FAILED: %d check(s) failed" % _failures)
	quit(1 if _failures > 0 else 0)
