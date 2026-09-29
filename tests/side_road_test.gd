extends SceneTree
## ROAD-7 / issue-0069: the exact stopped sideways pose, using the real
## Ring scene, wheel contacts and Surfaces classifier. No physics changes.
const ISSUE_SEGMENT := "314755146-2"
const CONTROL_SEGMENT := "1017207294-0"
const ISSUE_POSE := Vector3(969.409, 576.206, -1573.217)
const ISSUE_YAW := -55.9
const SKELETON_SHA256 := "bcdd9456b5376b2bc21ec69187c2f0daa7e906f506d53818394ea3b3ce733de3"
var _failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _ok(condition: bool, message: String) -> void:
	if condition:
		print("  ok    " + message)
	else:
		_failures += 1
		print("  FAIL: " + message)

func _run() -> void:
	OS.set_environment("FD_TELEMETRY", "0")
	var skeleton: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SkeletonLoader.PATH))
	var drape: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(WorldRoadProfile.PATH))
	var segments := SkeletonLoader.segments_of(skeleton)
	_ok(FileAccess.get_sha256(SkeletonLoader.PATH) == SKELETON_SHA256, "ROAD-7 skeleton bytes pinned: " + SKELETON_SHA256)
	_ok(segments[ISSUE_SEGMENT].width_m == 5.0 and segments[ISSUE_SEGMENT].width_source == "road7", "314755146-2 is 5.0 m paved by the ROAD-7 ruling")
	var covered := {}
	for record: Dictionary in drape.segments:
		covered[record.id] = record.covered
	var loop: Array = skeleton.loops[0].segments
	var covered_sides := 0
	var overrides := 0
	var widths_ok := true
	for id: String in segments:
		if segments[id].width_source == "road7":
			widths_ok = widths_ok and not id in loop and covered.get(id, false) and segments[id].width_m == 5.0
		if id in loop or not covered.get(id, false):
			continue
		covered_sides += 1
		widths_ok = widths_ok and segments[id].width_m >= 5.0
		overrides += int(segments[id].width_source == "road7")
	_ok(widths_ok and covered_sides == 3222 and overrides == 2379, "ROAD-7: all 3222 covered non-loop roads >=5 m, 2379 explicit overrides (217 ROAD-6 + 2162 newly widened)")
	_ok(segments[CONTROL_SEGMENT].width_m == 5.0, "former ROAD-6 control 1017207294-0 now also 5 m")
	var scene: Node3D = load("res://scenes/eifel_ring.tscn").instantiate()
	root.add_child(scene)
	for i: int in 3:
		await physics_frame
	var car: ArcadeCar = scene.get_node("Car")
	var surfaces: Surfaces = scene.get_node("Surfaces")
	# Hold exactly the reported pose: y is retained, no reset snaps it to
	# the road or recentres the car. Classify the same contacts as each tick.
	car.set_physics_process(false)
	car.global_transform = Transform3D(Basis(Vector3.UP, deg_to_rad(ISSUE_YAW)), ISSUE_POSE)
	var points: PackedVector2Array = segments[ISSUE_SEGMENT].points
	var closest := INF
	var axis := Vector2.ZERO
	var centre := Vector2(ISSUE_POSE.x, ISSUE_POSE.z)
	for i: int in points.size() - 1:
		var nearest := Geometry2D.get_closest_point_to_segment(centre, points[i], points[i + 1])
		if centre.distance_to(nearest) < closest:
			closest = centre.distance_to(nearest)
			axis = (points[i + 1] - points[i]).normalized()
	var forward := -car.global_basis.z
	_ok(absf(axis.dot(Vector2(forward.x, forward.z))) < 0.3, "issue heading -55.9 degrees is approximately sideways to the closest road chord")
	for i: int in ArcadeCar.WHEEL_CONTACT_POINTS.size():
		var contact: Vector3 = car.global_transform * ArcadeCar.WHEEL_CONTACT_POINTS[i]
		_ok(surfaces.classify(contact.x, contact.z) == &"road", "issue-0069 wheel %d classifies road at the reported sideways pose" % i)
	surfaces._physics_process(1.0 / 60.0)
	_ok(surfaces.front_surface == &"road" and surfaces.rear_surface == &"road", "issue-0069 axles read front road / rear road")
	scene.queue_free()
	await process_frame
	print("SIDE ROAD TEST PASSED" if _failures == 0 else "SIDE ROAD TEST FAILED: %d" % _failures)
	quit(0 if _failures == 0 else 1)
