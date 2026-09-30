extends SceneTree
## ROAD-5 / issue-0068: loop-only physical lip, unchanged pavement, matching
## render geometry and a deterministic suspension drive against the old field.
## ROAD-7 repins fc59167f... -> 482b425b...: widened nearby side-road
## fields affect some queries even though loop widths/heights are unchanged.
## Sample recipe inherited from ROAD-6 3595494:
## every loop chord midpoint at 0, +/-0.5 and +/-0.999 of its own half width,
## float64 sample_height, elevation_height, gradient.x/y in that order.
## ROAD-8: the racing-line kerb table (data/regions/eifel_ring/kerbs.json)
## and its mechanism - the table's shape and its roads, the kerb in the
## lip's place inside a window on the Ring and on the fixture (both types'
## numbers, the teeth, the fades, side and chainage gating), the plain lip
## everywhere else to the bit (the paved digest above unchanged, a
## kerb-free Ring profile from the same files equal off every window),
## gravity byte-identical across every window, and the kerb bands' census.
const PAVED_DIGEST := "482b425b054fae5ccd833727a7f67780d7b4499264bc84dc9855e02ec7e5320a"
## The table as authored: the count, the types, and the segments it must
## never name (the Karussell's bank, the frozen tests' straight and the
## certified ring drive's 2 km from it).
const KERB_ENTRIES := 25
const KERB_RAISED := 18
const KERB_FLAT := 7
const KERB_FORBIDDEN: Array[String] = ["414785755-0", "683303211-0", "683303210-0", "683303209-0", "683303208-0", "41792406-0", "41792406-1", "41395652-0"]
## The kerb census with every loop strip swept (ROAD-8, measured): one mesh
## per entry, the raised bands on the 0.125 m tooth grid.
const KERB_MESHES := 25
const KERB_VERTICES := 69150
const KERB_TRIANGLES := 110440
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
	_check_kerb_table(p)
	_check_kerb_ring(p)
	_check_kerb_fixture()
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
	# ROAD-8: the kerb bands per segment against the table filed on the
	# builder's own profile, every vertex on the physical field.
	var kerb_checked := 0
	var kerb_segments := 0
	var kerb_same := true
	var kerb_placed := true
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
		var entries := 0
		for r: WorldRoadProfile.Road in builder.profile._roads:
			if r.id == road.id:
				entries = r.kerbs.size()
		kerb_placed = kerb_placed and strip.kerb_arrays.size() == entries
		if entries > 0:
			kerb_segments += 1
			for band: Dictionary in strip.kerb_arrays:
				for v: Vector3 in band.arrays[Mesh.ARRAY_VERTEX]:
					kerb_same = kerb_same and absf(v.y - builder.profile.elevation_height(v.x, v.z) - RoadBuilder.KERB_PAINT_LIFT_M) < 0.0001
					kerb_checked += 1
		builder.add_strip(strip)
		if is_loop:
			var mesh := builder.get_node("Rumble_" + strip.id)
			same = same and mesh is MeshInstance3D and mesh.get_child_count() == 0
		for n: int in entries:
			var kerb := builder.get_node_or_null("Kerb_%s_%d" % [strip.id, n])
			kerb_placed = kerb_placed and kerb is MeshInstance3D and kerb.get_child_count() == 0 and kerb.mesh.get_surface_count() == 1
		kerb_placed = kerb_placed and builder.get_node_or_null("Kerb_%s_%d" % [strip.id, entries]) == null
	_ok(loops == 92 and sides == 1 and same and checked > 1000, "92 loop bands (+2 cm paint lift) agree with physical height at %d vertices; widened side road has none" % checked)
	_ok(builder.rumble_mesh_count == 92 and builder.rumble_vertex_count == 135444 and checked == 135444 and builder.rumble_triangle_count == 179856, "rumble census: %d meshes, %d vertices, %d triangles, zero new collision shapes" % [builder.rumble_mesh_count, builder.rumble_vertex_count, builder.rumble_triangle_count])
	_ok(kerb_placed and kerb_segments == 18 and kerb_same and kerb_checked == KERB_VERTICES, "ROAD-8 kerb bands: exactly one Kerb_<id>_<n> mesh per table entry on the %d kerbed segments and none elsewhere, no children, %d vertices on the physical field + %.2f m paint" % [kerb_segments, kerb_checked, RoadBuilder.KERB_PAINT_LIFT_M])
	_ok(builder.kerb_mesh_count == KERB_MESHES and builder.kerb_vertex_count == KERB_VERTICES and builder.kerb_triangle_count == KERB_TRIANGLES, "ROAD-8 kerb census: %d meshes, %d vertices, %d triangles, zero new collision shapes; the rumble census above unchanged" % [builder.kerb_mesh_count, builder.kerb_vertex_count, builder.kerb_triangle_count])
	builder.free()

# ROAD-8: the checked-in table's shape and what it names.
func _check_kerb_table(p: WorldRoadProfile) -> void:
	var data: Variant = WorldRoadProfile.read_file(WorldRoadProfile.KERBS_PATH)
	var faults := WorldRoadProfile.validate_kerbs(data)
	var entries := WorldRoadProfile.read_kerbs()
	var raised := 0
	var flat := 0
	var based := true
	for entry: WorldRoadProfile.Kerb in entries:
		raised += 1 if entry.raised else 0
		flat += 0 if entry.raised else 1
		based = based and entry.basis.length() > 40 and entry.from >= 0.0 and entry.from < entry.to and (entry.side == -1 or entry.side == 1 or entry.side == 0)
	_ok(data is Dictionary and data.get("version") == 1 and faults.is_empty() and entries.size() == KERB_ENTRIES and raised == KERB_RAISED and flat == KERB_FLAT and based, "kerbs.json: version 1, well formed (%d faults), %d entries (%d raised, %d flat), every window ordered and every basis written" % [faults.size(), entries.size(), raised, flat])
	# Every entry names a loop road inside its length: filed, none refused.
	var refused := p.set_kerbs(entries)
	var filed := 0
	var loop_only := true
	for r: WorldRoadProfile.Road in p._roads:
		filed += r.kerbs.size()
		loop_only = loop_only and (r.priority or r.kerbs.is_empty())
		for entry: WorldRoadProfile.Kerb in r.kerbs:
			loop_only = loop_only and entry.to <= r.length
	_ok(refused.is_empty() and filed == KERB_ENTRIES and loop_only, "every entry is filed on a loop (priority) road inside its length: %d filed, %d refused" % [filed, refused.size()])
	# Named corners only, the forbidden segments never, Hatzenbogen wanted.
	var names := {}
	for raw: Variant in SkeletonLoader.read_file().get("segments", []):
		if raw is Dictionary and raw.get("id") is String:
			names[raw.id] = raw.get("name", "")
	var named := true
	var forbidden := 0
	var hatzenbogen_raised_inside := false
	var segments := {}
	for entry: WorldRoadProfile.Kerb in entries:
		var name: String = names.get(entry.segment_id, "")
		named = named and name != "" and name != "Nürburgring Nordschleife"
		forbidden += 1 if KERB_FORBIDDEN.has(entry.segment_id) else 0
		segments[entry.segment_id] = true
		if entry.segment_id == "1009142895-0" and entry.side == 1 and entry.raised:
			hatzenbogen_raised_inside = true
	_ok(named and forbidden == 0 and hatzenbogen_raised_inside and segments.size() == 18, "the %d entries name %d named corner segments (never the generic loop name, a straight, the Karussell, Döttinger Höhe or the certified drive's stretch); Hatzenbogen carries a raised kerb on its inside (right) edge" % [entries.size(), segments.size()])
	# The reader refuses what it should and never errors.
	var bad := {"version": 2, "kerbs": [{"segment_id": "", "side": "middle", "type": "tall", "chainage_from": 10.0, "chainage_to": 5.0, "basis": ""}]}
	var bad_faults := WorldRoadProfile.validate_kerbs(bad)
	var unknown := WorldRoadProfile.Kerb.new()
	unknown.segment_id = "no-such-road"
	unknown.to = 10.0
	var side_road := WorldRoadProfile.Kerb.new()
	side_road.segment_id = "314755146-2"
	side_road.to = 10.0
	var long_window := WorldRoadProfile.Kerb.new()
	long_window.segment_id = "1009142895-0"
	long_window.to = 1000.0
	var refusals := p.set_kerbs([unknown, side_road, long_window])
	var none_filed := true
	for r: WorldRoadProfile.Road in p._roads:
		none_filed = none_filed and r.kerbs.is_empty()
	_ok(bad_faults.size() == 6 and WorldRoadProfile.kerbs_of(bad).is_empty() and WorldRoadProfile.read_kerbs("res://data/regions/eifel_ring/no-such-kerbs.json").is_empty() and refusals.size() == 3 and none_filed, "the reader lists every fault of a bad table (%d: version, id, side, type, window, basis) and reads it as no kerbs, a missing file as no kerbs; set_kerbs refuses an unknown road, a side road and a window past the road's length (%d) and files nothing" % [bad_faults.size(), refusals.size()])
	# Back to the checked-in table for everything after this.
	p.set_kerbs(entries)


## A point beside a loop road: `outside` metres past the paved edge on
## `side` (+1 right of travel) at a chainage, along the local direction.
func _beside(p: WorldRoadProfile, road: WorldRoadProfile.Road, chainage: float, side: float, outside: float) -> Vector2:
	var at: Vector2 = p.point_along(road.id, chainage)
	var ahead: Vector2 = p.point_along(road.id, chainage + 0.25)
	var direction := (ahead - at).normalized()
	var right := Vector2(-direction.y, direction.x)
	return at + right * side * (road.half_width + outside)


func _road(p: WorldRoadProfile, id: String) -> WorldRoadProfile.Road:
	for r: WorldRoadProfile.Road in p._roads:
		if r.id == id:
			return r
	return null


# ROAD-8 on the Ring: the kerb at pinned corners, the plain lip at a named
# corner without an entry, the window's edges, gravity and off-kerb
# heights byte-equal to a kerb-free profile from the same files.
func _check_kerb_ring(p: WorldRoadProfile) -> void:
	var bare := WorldRoadProfile.from_data(SkeletonLoader.read_file(), WorldRoadProfile.read_file(), [])
	var bare_empty := true
	for r: WorldRoadProfile.Road in bare._roads:
		bare_empty = bare_empty and r.kerbs.is_empty()
	_ok(bare_empty and bare._roads.size() == p._roads.size(), "from_data with an injected empty table builds the kerb-free ROAD-7 profile (%d roads, no entry filed)" % bare._roads.size())
	# Hatzenbogen's first raised window (right, 100..180) at chainage 140.
	var hatzenbogen := _road(p, "1009142895-0")
	var lifts := PackedFloat64Array()
	for outside: float in [0.075, 0.15, 0.275, 0.4, 0.6]:
		var q := _beside(p, hatzenbogen, 140.0, 1.0, outside)
		lifts.append(p.sample_height(q.x, q.y) - p._height(q.x, q.y, false))
	_ok(lifts[1] > 0.145 and lifts[1] < 0.185 and lifts[0] > 0.0625 and lifts[0] < 0.1025 and lifts[2] > 0.0725 and lifts[2] < 0.0925 and absf(lifts[3]) < 0.002 and absf(lifts[4]) < 0.002, "Hatzenbogen right at chainage 140 (raised): lifts [%.4f, %.4f, %.4f, %.4f, %.4f] over the smooth shoulder field at [0.075, 0.15, 0.275, 0.4, 0.6] m outside - the crest 0.165 ± the 0.02 tooth, over the plain 0.11, zero again at 0.40" % [lifts[0], lifts[1], lifts[2], lifts[3], lifts[4]])
	# The teeth: a crest and a trough 0.125 m apart along the chainage at
	# the 0.15 m crest, ± KERB_TOOTH_M against the tooth's zeros.
	var tooth := PackedFloat64Array()
	for along: float in [140.0, 140.125, 140.25, 140.375]:
		var q := _beside(p, hatzenbogen, along, 1.0, 0.15)
		tooth.append(p.sample_height(q.x, q.y) - p._height(q.x, q.y, false))
	_ok(absf(tooth[1] - tooth[0] - 0.02) < 0.002 and absf(tooth[3] - tooth[2] + 0.02) < 0.002 and absf(tooth[0] - 0.165) < 0.002 and absf(tooth[2] - 0.165) < 0.002, "the teeth along Hatzenbogen's kerb: %.4f, %.4f, %.4f, %.4f m at chainage 140 + [0, 0.125, 0.25, 0.375] - zero, crest (+0.02), zero, trough (-0.02) on the 0.5 m wavelength" % [tooth[0], tooth[1], tooth[2], tooth[3]])
	# Aremberg (raised right 20..160, flat left 60..170) at chainage 115.
	var aremberg := _road(p, "799394500-1")
	var inside := PackedFloat64Array()
	var outside_band := PackedFloat64Array()
	for outside: float in [0.075, 0.15, 0.275, 0.4, 0.6, 1.0, 1.125, 1.2, 1.5]:
		var q := _beside(p, aremberg, 115.0, 1.0, outside)
		inside.append(p.sample_height(q.x, q.y) - p._height(q.x, q.y, false))
		q = _beside(p, aremberg, 115.0, -1.0, outside)
		outside_band.append(p.sample_height(q.x, q.y) - p._height(q.x, q.y, false))
	# The Ring's pins are to 2 mm: the probe stands a hair off the nominal
	# outside distance at a bend (the exact numbers are the fixture's).
	var flat_ok := absf(outside_band[0] - 0.01) < 0.002 and absf(outside_band[1] - 0.02) < 0.002 and absf(outside_band[2] - 0.02) < 0.002 and absf(outside_band[3] - 0.02) < 0.002 and absf(outside_band[4] - 0.02) < 0.002 and absf(outside_band[5] - 0.02) < 0.002 and absf(outside_band[6] - 0.01) < 0.002 and absf(outside_band[7]) < 0.002 and absf(outside_band[8]) < 0.002
	_ok(inside[1] > 0.145 and inside[1] < 0.185 and absf(inside[3]) < 0.002 and absf(inside[5]) < 0.002 and flat_ok, "Aremberg at chainage 115: the inside (right) raised kerb %.4f m at 0.15 out; the outside (left) flat band [%.4f, %.4f, %.4f, %.4f, %.4f, %.4f, %.4f, %.4f, %.4f] at [0.075, 0.15, 0.275, 0.4, 0.6, 1.0, 1.125, 1.2, 1.5] m - 0.02 m of paint over 1.2 m in the lip's place, ramps of 0.15" % [inside[1], outside_band[0], outside_band[1], outside_band[2], outside_band[3], outside_band[4], outside_band[5], outside_band[6], outside_band[7], outside_band[8]])
	# The control: Lauda-Links, named, no entry - the plain lip exactly.
	var lauda := _road(p, "799394508-0")
	var control := true
	for side: float in [-1.0, 1.0]:
		for outside: float in [0.075, 0.15, 0.275, 0.4, 0.6]:
			var q := _beside(p, lauda, 180.0, side, outside)
			var found := p.describe(q.x, q.y)
			control = control and found.road == lauda.id and lauda.kerbs.is_empty() and var_to_bytes(p.sample_height(q.x, q.y)) == var_to_bytes(bare.sample_height(q.x, q.y)) and absf(p.sample_height(q.x, q.y) - p._height(q.x, q.y, false) - WorldRoadProfile.edge_lift(found.distance - lauda.half_width)) < 1e-9
	_ok(control, "Lauda-Links (named, no entry) at chainage 180 shows the plain lip on both sides to the bit of the kerb-free profile, the blend band resuming at 0.40")
	# The window's edges on Hatzenbogen's first window [100, 180]: the
	# plain lip just outside and at the ends, the kerb past the fade.
	var edges := PackedFloat64Array()
	for along: float in [99.5, 100.0, 101.0, 103.0, 177.0, 180.0, 180.5]:
		var q := _beside(p, hatzenbogen, along, 1.0, 0.15)
		edges.append(p.sample_height(q.x, q.y) - p._height(q.x, q.y, false))
	var plain_ends := absf(edges[0] - 0.11) < 0.002 and absf(edges[1] - 0.11) < 0.002 and absf(edges[5] - 0.11) < 0.002 and absf(edges[6] - 0.11) < 0.002
	_ok(plain_ends and edges[2] > 0.12 and edges[2] < 0.16 and edges[3] > 0.145 and edges[4] > 0.145, "window edges: 0.15 m out at chainage [99.5, 100, 101, 103, 177, 180, 180.5] lifts [%.4f, %.4f, %.4f, %.4f, %.4f, %.4f, %.4f] - the plain 0.11 outside and at both ends, half way up 1 m in, the kerb past the 2 m fade" % [edges[0], edges[1], edges[2], edges[3], edges[4], edges[5], edges[6]])
	# Gravity across every window, and heights off every window, byte-equal
	# to the kerb-free profile.
	var gradients := 0
	var gravity_same := true
	var off := 0
	var off_same := true
	for r: WorldRoadProfile.Road in p._roads:
		for entry: WorldRoadProfile.Kerb in r.kerbs:
			var side := 1.0 if entry.side >= 0 else -1.0
			for f: float in [0.0, 0.25, 0.5, 0.75, 1.0]:
				var along := lerpf(entry.from, entry.to, f)
				for outside: float in [-r.half_width, -0.5 * r.half_width, 0.0, 0.15, 0.6, 1.0]:
					var q := _beside(p, r, along, side, outside)
					gravity_same = gravity_same and var_to_bytes(p.ramp_gradient(q.x, q.y)) == var_to_bytes(bare.ramp_gradient(q.x, q.y))
					gradients += 1
			for along: float in [entry.from - 1.0, entry.to + 1.0]:
				if along < 0.0 or along > r.length:
					continue
				for outside: float in [0.075, 0.15, 0.4, 1.0]:
					var q := _beside(p, r, along, side, outside)
					off_same = off_same and var_to_bytes(p.sample_height(q.x, q.y)) == var_to_bytes(bare.sample_height(q.x, q.y))
					off += 1
			if entry.side != 0:
				for outside: float in [0.075, 0.15, 0.4, 1.0]:
					var q := _beside(p, r, 0.5 * (entry.from + entry.to), -side, outside)
					if r.kerb_at(-side, 0.5 * (entry.from + entry.to)) == null:
						off_same = off_same and var_to_bytes(p.sample_height(q.x, q.y)) == var_to_bytes(bare.sample_height(q.x, q.y))
						off += 1
	_ok(gravity_same and gradients == KERB_ENTRIES * 30, "ramp_gradient is byte-identical to the kerb-free profile at %d points across every kerb window (on pavement, 0.15, 0.6 and 1.0 m out): gravity never sees a kerb" % gradients)
	_ok(off_same and off > 100, "sample_height is byte-identical to the kerb-free profile at %d points 1 m outside every window and on every window's other side: the kerb branch is a no-op wherever no entry covers the point" % off)


# ROAD-8 on the straight fixture: the exact numbers both types give, the
# fades, side and chainage gating, pavement and gravity to the bit. The
# fixture runs along +z, so right of travel is -x (the profile's frame:
# right = (-dz, dx)) and chainage is z + 200.
func _check_kerb_fixture() -> void:
	var plain := _fixture(false)
	var kerbed := _fixture(false)
	var raised := WorldRoadProfile.Kerb.new()
	raised.segment_id = "fixture"
	raised.side = 1
	raised.raised = true
	raised.from = 100.0
	raised.to = 200.0
	var flat := WorldRoadProfile.Kerb.new()
	flat.segment_id = "fixture"
	flat.side = -1
	flat.raised = false
	flat.from = 100.0
	flat.to = 200.0
	var refused := kerbed.set_kerbs([raised, flat])
	_ok(refused.is_empty() and kerbed._roads[0].kerbs.size() == 2 and kerbed._roads[0].kerb_at(1.0, 150.0) == raised and kerbed._roads[0].kerb_at(-1.0, 150.0) == flat and kerbed._roads[0].kerb_at(1.0, 99.0) == null and kerbed._roads[0].kerb_at(-1.0, 201.0) == null, "fixture: a raised right and a flat left entry over chainage [100, 200] filed; kerb_at answers by side sign and window")
	var distances := [0.0, 0.075, 0.15, 0.275, 0.4, 0.6, 1.0, 1.125, 1.2, 1.5]
	# Chainage 150 (z = -50): the tooth's zero (sin of 300 whole turns).
	var expected_raised := [0.0, 0.0825, 0.165, 0.0825, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
	var expected_flat := [0.0, 0.01, 0.02, 0.02, 0.02, 0.02, 0.02, 0.01, 0.0, 0.0]
	var raised_ok := true
	var flat_ok := true
	for i: int in distances.size():
		var x: float = 4.25 + distances[i]
		raised_ok = raised_ok and absf(kerbed.sample_height(-x, -50.0) - plain._height(-x, -50.0, false) - expected_raised[i]) < 1e-9
		flat_ok = flat_ok and absf(kerbed.sample_height(x, -50.0) - plain._height(x, -50.0, false) - expected_flat[i]) < 1e-9
	_ok(raised_ok, "raised right at chainage 150 lifts [0, .0825, .165, .0825, 0, 0, 0, 0, 0, 0] m at outside [0, .075, .15, .275, .4, .6, 1, 1.125, 1.2, 1.5] m: the lip x 1.5, zero teeth at a tooth boundary")
	_ok(flat_ok, "flat left at chainage 150 lifts [0, .01, .02, .02, .02, .02, .02, .01, 0, 0] m at the same distances: 0.02 m over 1.2 m with 0.15 m ramps, in the lip's place")
	# The teeth a quarter and three quarters of a wavelength on: ± 0.02 at
	# the crest, scaled across by the tooth's window (0.25 at 0.075 out,
	# 0.5 at 0.275 out), nothing at the toes.
	var crest := [0.0, 0.0875, 0.185, 0.0925, 0.0, 0.0]
	var trough := [0.0, 0.0775, 0.145, 0.0725, 0.0, 0.0]
	var teeth_ok := true
	for i: int in 6:
		var x: float = 4.25 + distances[i]
		teeth_ok = teeth_ok and absf(kerbed.sample_height(-x, -49.875) - plain._height(-x, -49.875, false) - crest[i]) < 1e-9
		teeth_ok = teeth_ok and absf(kerbed.sample_height(-x, -49.625) - plain._height(-x, -49.625, false) - trough[i]) < 1e-9
	_ok(teeth_ok, "the teeth at chainage 150.125 / 150.375: [0, .0875, .185, .0925, 0, 0] / [0, .0775, .145, .0725, 0, 0] m - ± 0.02 at the crest, 0 at 0.05 and 0.40 out, always above the plain lip")
	# The fade: the plain lip to the bit at both ends, half way 1 m in.
	var fade_ok := true
	for z: float in [-100.0, 0.0]:
		for i: int in 6:
			var x: float = 4.25 + distances[i]
			fade_ok = fade_ok and var_to_bytes(kerbed.sample_height(-x, z)) == var_to_bytes(plain.sample_height(-x, z)) and var_to_bytes(kerbed.sample_height(x, z)) == var_to_bytes(plain.sample_height(x, z))
	var half_raised := kerbed.sample_height(-4.4, -99.0) - plain._height(-4.4, -99.0, false)
	var half_flat := kerbed.sample_height(4.4, -99.0) - plain._height(4.4, -99.0, false)
	_ok(fade_ok and absf(half_raised - 0.1375) < 1e-9 and absf(half_flat - 0.065) < 1e-9, "the 2 m fade: at chainage 100 and 200 both sides are the plain lip to the bit; at 101 the crest reads %.4f (raised: half of the 0.055 excess) and %.4f (flat: half way from 0.11 to 0.02)" % [half_raised, half_flat])
	# Side and chainage gating: outside the window, and a right-only entry
	# leaving the left alone, byte-equal to the plain fixture.
	var right_only := _fixture(false)
	right_only.set_kerbs([raised])
	var gated := true
	for z: float in [-150.0, -101.0, -100.5, 0.5, 1.0, 50.0]:
		for i: int in distances.size():
			var x: float = 4.25 + distances[i]
			gated = gated and var_to_bytes(kerbed.sample_height(-x, z)) == var_to_bytes(plain.sample_height(-x, z)) and var_to_bytes(kerbed.sample_height(x, z)) == var_to_bytes(plain.sample_height(x, z))
	for z: float in [-100.0, -75.0, -50.0, -25.0, 0.0]:
		for i: int in distances.size():
			var x: float = 4.25 + distances[i]
			gated = gated and var_to_bytes(right_only.sample_height(x, z)) == var_to_bytes(plain.sample_height(x, z)) and var_to_bytes(right_only.sample_height(-x, z)) == var_to_bytes(kerbed.sample_height(-x, z))
	_ok(gated, "gating: outside the window both sides are the plain fixture to the bit; a right-only entry leaves the left side the plain lip and the right side the kerb")
	# Pavement to the bit, gravity to the bit across the window.
	var paved := true
	var gravity := true
	var taps := 0
	for z: float in [-105.0, -100.0, -90.0, -50.0, -10.0, 0.0, 5.0]:
		for x: float in [-4.25, -4.0, -2.0, 0.0, 2.0, 4.0, 4.25]:
			paved = paved and var_to_bytes(kerbed.sample_height(x, z)) == var_to_bytes(plain.sample_height(x, z))
		var x := -6.0
		while x <= 6.0:
			gravity = gravity and var_to_bytes(kerbed.ramp_gradient(x, z)) == var_to_bytes(plain.ramp_gradient(x, z))
			taps += 1
			x += 0.25
	_ok(paved and gravity and taps == 343, "fixture: pavement byte-exact through the window on both sides; ramp_gradient byte-identical to the plain fixture at %d points across the window (the taps cross both kerbs)" % taps)


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
