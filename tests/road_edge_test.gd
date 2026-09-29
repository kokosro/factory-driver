extends SceneTree
## ROAD-5 / issue-0068: loop-only physical lip, unchanged pavement, matching
## render geometry and a deterministic suspension drive against the old field.
## ROAD-7 repins fc59167f... -> 482b425b...: widened nearby side-road
## fields affect some queries even though loop widths/heights are unchanged.
## Sample recipe inherited from ROAD-6 3595494:
## every loop chord midpoint at 0, +/-0.5 and +/-0.999 of its own half width,
## float64 sample_height, elevation_height, gradient.x/y in that order.
const PAVED_DIGEST := "482b425b054fae5ccd833727a7f67780d7b4499264bc84dc9855e02ec7e5320a"
var _failures := 0

# Counterfactual for the drive: precisely the old smooth shoulder, with
# identical geometry, widths and gravity. The fixed digest above is an
# independent pre-change oracle, not a comparison of two new code paths.
class BeforeEdge:
	extends WorldRoadProfile
	func elevation_height(x: float, z: float) -> float:
		return _height(x, z, false)

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
	var p := WorldRoadProfile.ring()
	var wrapper := RingProfile.over(p, null, {})
	_check_paved(p, wrapper)
	_check_crossing()
	_check_pose(p, wrapper)
	_check_side(p)
	_check_meshes()
	var before: Dictionary = await _drive(true)
	var after: Dictionary = await _drive(false)
	var again: Dictionary = await _drive(false)
	_ok(before.crossed and after.crossed, "both 8 m/s drives carry all four contacts across the edge")
	_ok(after.peak > before.peak + 1.0 and after.peak > 2.0, "vertical acceleration spike: before %.6f, lip %.6f m/s^2 (at least +1.0)" % [before.peak, after.peak])
	_ok(after == again, "repeated edge drive is byte-identical on the tick clock")
	print("ROAD EDGE TEST PASSED" if _failures == 0 else "ROAD EDGE TEST FAILED: %d" % _failures)
	quit(0 if _failures == 0 else 1)

func _check_paved(p: WorldRoadProfile, wrapper: RingProfile) -> void:
	var samples := PackedFloat64Array()
	var n := 0
	var loops := 0
	var matches := true
	for r: WorldRoadProfile.Road in p._roads:
		if not r.priority:
			continue
		loops += 1
		for k: int in r.xs.size() - 1:
			var dx := r.xs[k + 1] - r.xs[k]
			var dz := r.zs[k + 1] - r.zs[k]
			var length := sqrt(dx * dx + dz * dz)
			if length < 0.001:
				continue
			for f: float in [-0.999, -0.5, 0.0, 0.5, 0.999]:
				var x := (r.xs[k + 1] + r.xs[k]) * 0.5 - dz / length * r.half_width * f
				var z := (r.zs[k + 1] + r.zs[k]) * 0.5 + dx / length * r.half_width * f
				var h := p.sample_height(x, z)
				samples.append(h)
				samples.append(p.elevation_height(x, z))
				var g := p.ramp_gradient(x, z)
				samples.append(g.x)
				samples.append(g.y)
				matches = matches and var_to_bytes(h) == var_to_bytes(wrapper.sample_height(x, z)) and var_to_bytes(h) == var_to_bytes(wrapper.elevation_height(x, z)) and var_to_bytes(g) == var_to_bytes(wrapper.ramp_gradient(x, z))
				n += 1
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(samples.to_byte_array())
	var digest := hash.finish().hex_encode()
	_ok(n == 4965 and loops == 92 and digest == PAVED_DIGEST, "4965 paved queries on all 92 loops, including Karussell, byte-equal to ROAD-7: " + digest)
	_ok(matches, "RingProfile sample/elevation/gradient delegate byte-exactly at all 4965 points")

# Straight flat fixture; crown -0.085 m at an 8.5 m road's edge.
# Exact binary coordinates exercise <= half_width without Vector2 rounding.
func _fixture(before: bool, half_width := 4.25, priority := true) -> WorldRoadProfile:
	var p: WorldRoadProfile = BeforeEdge.new() if before else WorldRoadProfile.new()
	p._x_min = -100.0
	p._x_max = 100.0
	p._z_min = -200.0
	p._z_max = 200.0
	var r := WorldRoadProfile.Road.new()
	r.id = "fixture"
	r.xs = PackedFloat64Array([0.0, 0.0])
	r.zs = PackedFloat64Array([-200.0, 200.0])
	r.chain = PackedFloat64Array([0.0, 400.0])
	r.length = 400.0
	r.half_width = half_width
	r.priority = priority
	r.dense.resize(201)
	r.dense.fill(0.0)
	r.crossfall = PackedFloat64Array([0.0, 0.0])
	p._roads.append(r)
	p._build_cells()
	return p

func _check_crossing() -> void:
	var p := _fixture(false)
	var old := _fixture(true)
	for side: float in [-1.0, 1.0]:
		var exact := true
		for x: float in [0.0, 2.0, 4.0, 4.25]:
			exact = exact and var_to_bytes(p.sample_height(side * x, 0.0)) == var_to_bytes(old.sample_height(side * x, 0.0))
		_ok(exact, "fixture side %.0f is byte-exact through the paved boundary" % side)
		var expected := [0.0, 0.055, 0.11, 0.055, 0.0, 0.0]
		var distances := [0.0, 0.075, 0.15, 0.275, 0.4, 0.6]
		var close := true
		for i: int in distances.size():
			var x: float = side * (4.25 + distances[i])
			close = close and absf(p.sample_height(x, 0.0) - old.sample_height(x, 0.0) - expected[i]) < 1e-12
		_ok(close, "side %.0f lifts [0,.055,.110,.055,0,0] m at outside [0,.075,.15,.275,.4,.6] m" % side)
		_ok(absf(p.sample_height(side * 4.4, 0.0) - 0.02515671875) < 1e-12 and p.sample_height(side * 4.65, 0.0) < -0.083, "side %.0f peaks at absolute 0.02515671875 m then drops below -0.083 m" % side)
	var narrow := _fixture(false, 3.75)
	var narrow_old := _fixture(true, 3.75)
	_ok(absf(narrow.sample_height(3.9, 0.0) - narrow_old.sample_height(3.9, 0.0) - 0.11) < 1e-12, "7.5 m Karussell width places the lip relative to its own 3.75 m half width")

func _check_pose(p: WorldRoadProfile, wrapper: RingProfile) -> void:
	var pose := Transform3D(Basis(Vector3.UP, deg_to_rad(153.1)), Vector3(1918.733, 614.433, -1273.017))
	var baseline := [614.261885934485, 614.513651209879]
	for j: int in 2:
		var i := 1 + j * 2
		var v: Vector3 = pose * ArcadeCar.WHEEL_CONTACT_POINTS[i]
		var found := p._nearest_chord(v.x, v.z)
		var r: WorldRoadProfile.Road = p._roads[found.road]
		# Move along the exact radial direction to the same chord's lip.
		var nearest: Vector2 = p.point_along(r.id, found.chainage)
		var axis := (Vector2(v.x, v.z) - nearest).normalized()
		var lip: Vector2 = nearest + axis * (r.half_width + 0.15)
		var h := wrapper.sample_height(v.x, v.z)
		var top := wrapper.sample_height(lip.x, lip.y)
		_ok(r.id == "1009142895-0" and found.distance - r.half_width > 0.4 and absf(h - baseline[j]) < 1e-9 and top - h > 0.10 and top - h < 0.12, "0068 wheel %d: shoulder before/after %.9f m, lip %.9f m, drop %.6f m" % [i, h, top, top - h])

func _check_side(p: WorldRoadProfile) -> void:
	var count := 0
	var matches := true
	for r: WorldRoadProfile.Road in p._roads:
		if r.id != "314755146-2":
			continue
		for k: int in r.xs.size() - 1:
			var dx := r.xs[k + 1] - r.xs[k]
			var dz := r.zs[k + 1] - r.zs[k]
			var length := sqrt(dx * dx + dz * dz)
			for side: float in [-1.0, 1.0]:
				for outside: float in [0.0, 0.075, 0.15, 0.275, 0.4, 0.6]:
					var x := (r.xs[k + 1] + r.xs[k]) * 0.5 - dz / length * (r.half_width + outside) * side
					var z := (r.zs[k + 1] + r.zs[k]) * 0.5 + dx / length * (r.half_width + outside) * side
					matches = matches and var_to_bytes(p.sample_height(x, z)) == var_to_bytes(p._height(x, z, false))
					count += 1
	_ok(matches and count > 0, "ROAD-6 widened 314755146-2: %d edge/shoulder samples have zero rumble" % count)

func _check_meshes() -> void:
	var builder := RoadBuilder.new()
	_ok(builder.apply_prepared(RoadBuilder.prepare_data()), "road data prepared for physical/render agreement")
	var checked := 0
	var loops := 0
	var sides := 0
	var same := true
	for road: RoadBuilder.Road in RoadBuilder.roads_of(builder.skeleton_data, builder.drape_data):
		# All loop meshes, plus the widened side-road control. Avoid building
		# the whole forest/terrain just to inspect this new road component.
		var is_loop := false
		for r: WorldRoadProfile.Road in builder.profile._roads:
			if r.id == road.id:
				is_loop = r.priority
				break
		if not is_loop and road.id != "314755146-2":
			continue
		var strip := builder.sweep_road(road)
		if is_loop:
			loops += 1
			var vertices: PackedVector3Array = strip.rumble_arrays[Mesh.ARRAY_VERTEX]
			for v: Vector3 in vertices:
				same = same and absf(v.y - builder.profile.elevation_height(v.x, v.z) - 0.02) < 0.0001
				checked += 1
		else:
			sides += 1
			same = same and strip.rumble_arrays.is_empty()
		builder.add_strip(strip)
		if is_loop:
			var mesh := builder.get_node("Rumble_" + strip.id)
			same = same and mesh is MeshInstance3D and mesh.get_child_count() == 0
	_ok(loops == 92 and sides == 1 and same and checked > 1000, "92 loop bands (+2 cm paint lift) agree with physical height at %d vertices; widened side road has none" % checked)
	_ok(builder.rumble_mesh_count == 92 and builder.rumble_vertex_count == 135444 and checked == 135444 and builder.rumble_triangle_count == 179856, "rumble census: %d meshes, %d vertices, %d triangles, zero new collision shapes" % [builder.rumble_mesh_count, builder.rumble_vertex_count, builder.rumble_triangle_count])
	builder.free()

func _drive(before: bool) -> Dictionary:
	await physics_frame
	var scene := Node3D.new()
	root.add_child(scene)
	var car: ArcadeCar = load("res://scenes/car.tscn").instantiate()
	car.road_profile = RingProfile.over(_fixture(before), null, {})
	scene.add_child(car)
	car.reset_to(Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3.ZERO))
	car.set_driver_input(0.0, 0.0, 0.0)
	for i: int in 30:
		await physics_frame
	car.velocity = Vector3(8.0, 0.0, 0.0)
	var last := car.velocity.y
	var peak := 0.0
	var records := PackedFloat64Array()
	for tick: int in 60:
		await physics_frame
		var accel := (car.velocity.y - last) * 60.0
		peak = maxf(peak, absf(accel))
		last = car.velocity.y
		records.append(last)
		records.append(car.global_position.x)
	var crossed := true
	for contact: Vector3 in ArcadeCar.WHEEL_CONTACT_POINTS:
		crossed = crossed and (car.global_transform * contact).x > 4.65
	scene.queue_free()
	await process_frame
	return {"peak": peak, "crossed": crossed, "records": records.to_byte_array()}
