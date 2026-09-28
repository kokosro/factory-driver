extends SceneTree
## ROAD-6 / issue-0069: the exact stopped sideways pose, using the real
## Ring scene, wheel contacts and Surfaces classifier. No physics changes.
const ISSUE_SEGMENT := "314755146-2"
const CONTROL_SEGMENT := "1017207294-0"
const ISSUE_POSE := Vector3(969.409, 576.206, -1573.217)
const ISSUE_YAW := -55.9
const SKELETON_SHA256 := "3c05fc5633b2b1bf34ee7572e44877b78eab840e7657bcbeee97e6f39050c11e"
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
	_ok(FileAccess.get_sha256(SkeletonLoader.PATH) == SKELETON_SHA256, "ROAD-6 skeleton bytes pinned: " + SKELETON_SHA256)
	_ok(segments[ISSUE_SEGMENT].width_m == 5.0 and segments[ISSUE_SEGMENT].width_source == "road6", "314755146-2 is 5.0 m paved by the ROAD-6 ruling")
	var covered := {}
	for record: Dictionary in drape.segments:
		covered[record.id] = record.covered
	_ok(covered[ISSUE_SEGMENT] and covered[CONTROL_SEGMENT] and segments[CONTROL_SEGMENT].road_class == "track" and segments[CONTROL_SEGMENT].width_m == 3.0, "covered control 1017207294-0 remains a 3.0 m track outside the selection")
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
