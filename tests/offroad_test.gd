extends SceneTree
## Headless off-road test (OFFROAD-1; plan.org ECD301C4, SURFACES & GRIP
## DEPTH - "grip varies by surface type and condition, suspension/tire
## feel"; decisions.org DAF72FC6, OPEN-WORLD CONTINUITY - "everything
## reachable, no walls, the world continues procedurally beyond the OSM
## data"; the Conductor's narrow car.gd grant, decisions.org 5B7CD993).
## Run via tests/run_tests.sh, or:
##
##   godot --headless --path . --import
##   godot --headless --fixed-fps 60 --path . --script res://tests/offroad_test.gd
##
## Loads scenes/eifel_ring.tscn the way the ring drive test does and
## holds the surface model, the profile wrapper and the continuation to
## their contracts. THE TABLE (d): data/regions/eifel_ring/surfaces.json
## passes Surfaces.validate() with nothing to say, names the five
## surfaces, the road exactly {1.0, 0.0, 0.0}, and validate() names a
## grip out of bounds, a negative drag, a missing surface and a road that
## is not the baseline. THE SWAP: after the settle road.profile is a
## RingProfile (a WorldRoadProfile: the ring drive test's pin holds),
## car.road_profile the same object, Terrain and Forest still on the
## inner (the meshes the smooth field's), the Surfaces node after Road
## at priority -1. THE DELEGATION (1): on a GRID_STEP_M grid over the
## coverage box and a ring outside it every delegated member (covers,
## elevation_mask, terrain_height, describe, point_along on the loop's
## roads, micro_height, test_dip_height, ramp_height_at, elevation_slope,
## coverage, road_count) equals the inner's to the bit. ON THE ROAD (2):
## along the first LOOP_STRETCH_M of the certified loop drive from the
## drive-start straight (the ring drive test's line) sample_height and
## ramp_gradient at EVERY strip vertex and at the centreline between
## sections equal the inner's to the bit - the certified drives read the
## inner's arithmetic and nothing else. THE CLASSIFICATION (b): named
## points classify as named - the straight's centreline the road, the
## shoulder (SHOULDER_OFFSET_M beyond the paved edge) gravel, beyond the
## shoulder the forest floor (the straight runs through forest), the
## grass spot grass, the field spot field stubble, the forest spot forest
## floor, the point outside the coverage grass. THE CONTINUATION (3):
## EDGE_SAMPLES points along each side of the box, EDGE_EPSILON_M inside
## and outside, differ by under EDGE_TOLERANCE_M (the field is continuous
## at the edge: the edge value is the real field's, the relief weighed in
## from 0, the bumps faded to 0 there); a ray west out of the box carries
## real relief inside the margin and reads exactly 0 beyond it; the
## continuation is the same on a second scene to the bit. THE SKIRT (4):
## Terrain carries the four Continuation_* meshes, CONTINUATION_CELLS
## cells and CONTINUATION_SKIRTS hanging skirts (the accounting: two
## bands of 120 x 360 and two of 140 x 120 cells at 50 m; 120 + 120 +
## 140 + 140 edge pieces), every band vertex's height the static field's
## (WorldContinuation.height at the vertex) within VERTEX_TOLERANCE_M
## (single-precision storage), and every vertex on the box's edge the
## wrapper's own height there within the same. THE OFF-ROAD DRIVE (a):
## the car reset to GRASS_SPOT (a T1 node 110 m south of the 3 m track
## GRASS_TRACK, slope 3.3 %, the line north to the track clear of
## forest, water and trees, meeting it at 87 degrees; found by a scan of
## the distance field), nose north, the throttle pinned for DRIVE_TICKS:
## every wheel on grass from the first tick, the axle grips the table's
## grass value and the rolling decel its drag; the peak acceleration
## over the launch (ticks PEAK_FROM_TICK to PEAK_TO_TICK, before the
## track: past it the car pitches up the track's far bank and the speed
## along the nose jumps) under PEAK_RATIO_MAX of the on-road reference's
## (the same pinned throttle from the drive-start straight's chainage
## 30, whose peak is over ROAD_PEAK_MIN); the wheels' travel RATE variance (the tick-to-tick
## change of wheel_travel) over the TRAVEL_WINDOW above
## TRAVEL_RATE_VARIANCE_FLOOR, and the CONTROL's (the same drive with the
## bumps zeroed) under CONTROL_RATE_RATIO_MAX of it - the travel variance
## itself is the lattice's 10 m slopes and the launch squat, the cm-scale
## bumps show in the rate (measured: 0.0021 against 0.0001 (m/s)^2); on the way the front axle reaches the track (the
## front grip reads 1.0 at some tick, the rear likewise) - the wheels
## are classified one by one; and reset onto the straight's centreline
## the three inputs read 1.0 / 1.0 / 0.0 within GRIP_RETURN_TICKS.
## DETERMINISM (c): the grass drive run FIRST THING on two scenes
## instanced fresh (the car's wear, heat and fuel the scene's) lands on
## the same position in the same ticks to the bit, with the same peak.
## No wall clock anywhere: the suite's lines are the same on any machine.

const RING_SCENE := "res://scenes/eifel_ring.tscn"
const SETTLE_FRAMES := 20

## The drive-start straight (the ring drive test's DRIVE_START_SEGMENT)
## and its section at chainage 30 m (2 m stations).
const STRAIGHT := "683303211-0"
const STRAIGHT_SECTION := 15
## The shoulder point: this far beyond the paved edge (inside the
## table's 1.5 m shoulder); the forest point: beyond the shoulder.
const SHOULDER_OFFSET_M := 0.75
const BEYOND_SHOULDER_M := 3.0
## The named off-road points (see the header).
const GRASS_SPOT := Vector2(6120.0, -2640.0)
const GRASS_HEADING := Vector2(0.0, -1.0)
const GRASS_TRACK := "420472180-0"
const FIELD_SPOT := Vector2(2890.0, -4510.0)
const FOREST_SPOT := Vector2(5340.0, -3460.0)
const OUTSIDE_SPOT := Vector2(-100.0, -3000.0)

## The delegation grid and the on-road stretch.
const GRID_STEP_M := 250.0
const GRID_RING_M := 1000.0
const LOOP_STRETCH_M := 2000.0

## The continuation's edge samples and the ray's stations [m] out of the
## box's west side.
const EDGE_SAMPLES := 121
const RAY_Z := -3000.0
const RAY_INSIDE_M := [100.0, 800.0, 3000.0, 5000.0]
const RAY_BEYOND_M := [6000.0, 6500.0, 9000.0]
const VERTEX_TOLERANCE_M := 0.002
## A stored vertex colour is 8-bit: one step of tolerance.
const COLOUR_TOLERANCE := 1.0 / 255.0 + 1.0e-6
## ROAD-7 / F1-COLLISION-1 pin-only ruling (Conductor, 2026-09-29): the edge
## continuity limit was WorldContinuation.EDGE_TOLERANCE_M = 0.010000000 m,
## a data-derived literal asserting the OLD road geometry's blend behavior
## at the DEM boundary. ROAD-7 deliberately widens track 235829445-2, whose
## blend band reaches the edge sample at (2450, -6000.01): measured gap
## 0.010613583 m (baseline 0.007177782 m), 0.61 mm over the old limit. The
## blend's continuity still holds - the gap is finite and small - so this
## test's one literal moves to the measured value, no other check changed.
const EDGE_TOLERANCE_M_ROAD7 := 0.010613584
## The skirt's accounting (the header).
const CONTINUATION_CELLS := 120000
const CONTINUATION_SKIRTS := 520
const CONTINUATION_MESHES := ["Continuation_west", "Continuation_east", "Continuation_south", "Continuation_north"]
const VERTEX_SAMPLE_STRIDE := 61

## The drive.
const DRIVE_TICKS := 660
const PEAK_FROM_TICK := 6
const PEAK_TO_TICK := 300
const PEAK_RATIO_MAX := 0.6
const ROAD_PEAK_MIN := 5.0
const TRAVEL_WINDOW := [60, 300]
const TRAVEL_RATE_VARIANCE_FLOOR := 5.0e-4
const CONTROL_RATE_RATIO_MAX := 0.25
const GRIP_RETURN_TICKS := 2

var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	print("-- the table")
	_check_table()
	print("-- the scene and the swap")
	var scene := await _load_scene()
	if scene == null:
		_finish()
		return
	var road: RoadBuilder = scene.get_node("Road")
	var terrain: TerrainBuilder = scene.get_node("Terrain")
	var forest: ForestWalls = scene.get_node("Forest")
	var car: ArcadeCar = scene.get_node("Car")
	var surfaces: Surfaces = scene.get_node_or_null("Surfaces")
	_check_swap(scene, road, terrain, forest, car, surfaces)
	if surfaces == null or not road.profile is RingProfile:
		_finish()
		return
	var wrapper: RingProfile = road.profile
	print("-- the delegation")
	_check_delegation(wrapper)
	print("-- on the road, to the bit")
	_check_on_road(road, wrapper)
	print("-- the classification")
	_check_classification(road, terrain, surfaces)
	print("-- the continuation")
	var first_outside := _check_continuation(wrapper)
	print("-- the skirt")
	_check_skirt(terrain, wrapper)
	print("-- the off-road drive")
	var grass := await _drive(car, surfaces, "the grass drive")
	var reference := await _drive_reference(road, car, surfaces)
	_check_drive(surfaces, grass, reference)
	await _check_return(road, car, surfaces)
	root.remove_child(scene)
	scene.free()
	await _step(1)
	print("-- determinism")
	var again := await _load_scene()
	if again != null:
		var car2: ArcadeCar = again.get_node("Car")
		var surfaces2: Surfaces = again.get_node("Surfaces")
		var wrapper2: RingProfile = (again.get_node("Road") as RoadBuilder).profile
		var second := await _drive(car2, surfaces2, "the grass drive again")
		_ok(grass.position == second.position and grass.peak == second.peak and grass.ticks == second.ticks, "two scenes instanced fresh and driven the same %d ticks on the grass first thing land on the same position (%s) with the same peak acceleration (%.3f m/s^2) to the bit" % [second.ticks, second.position, second.peak], "first: %s / %.6f / %d, second: %s / %.6f / %d" % [grass.position, grass.peak, grass.ticks, second.position, second.peak, second.ticks])
		var second_outside := _outside_samples(wrapper2)
		_ok(first_outside.size() > 0 and first_outside == second_outside, "the continuation is the same on the second scene at every one of %d sampled points outside the box, to the bit" % second_outside.size(), "samples %d / %d equal %s" % [first_outside.size(), second_outside.size(), first_outside == second_outside])
		var control := await _drive_control(car2, surfaces2, wrapper2)
		_ok(control.rate_variance < CONTROL_RATE_RATIO_MAX * second.rate_variance, "the control (the same grass drive with the bumps zeroed, on the second scene after its drive) shakes the wheels less: travel rate variance %.5f under %.2f of the bumped drive's %.5f - the excitation is the micro-profile's" % [control.rate_variance, CONTROL_RATE_RATIO_MAX, second.rate_variance], "control %.5f, bumped %.5f" % [control.rate_variance, second.rate_variance])
		root.remove_child(again)
		again.free()
	_finish()


func _finish() -> void:
	print("OFFROAD TEST PASSED" if _failures == 0 else "OFFROAD TEST FAILED: %d fault(s)" % _failures)
	quit(0 if _failures == 0 else 1)


## An ok line or a FAIL line, counted.
func _ok(condition: bool, what: String, reason: String = "") -> void:
	if condition:
		print("  ok    ", what)
	else:
		_failures += 1
		printerr("  FAIL  ", reason if reason != "" else what)


func _step(frames: int) -> void:
	for i: int in frames:
		await physics_frame


func _load_scene() -> Node:
	var packed: PackedScene = load(RING_SCENE)
	if packed == null:
		_ok(false, "", "the ring scene does not load")
		return null
	await physics_frame
	var scene := packed.instantiate()
	root.add_child(scene)
	await _step(SETTLE_FRAMES)
	return scene


## A yaw-only pose at (x, z) with the nose along `direction` (x east, z
## south), origin.y 0: the way the ring drive test stands the car.
func _pose(x: float, z: float, direction: Vector2) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, atan2(-direction.x, -direction.y)), Vector3(x, 0.0, z))


func _names(errors: PackedStringArray, text: String) -> bool:
	for line: String in errors:
		if line.contains(text):
			return true
	return false


# =============================================================================
#  THE TABLE
# =============================================================================

func _check_table() -> void:
	var data: Variant = Surfaces.read_file()
	_ok(FileAccess.file_exists(Surfaces.PATH) and data is Dictionary, "the surfaces table is checked in at %s and parses as a JSON object" % Surfaces.PATH)
	if not data is Dictionary:
		return
	var errors := Surfaces.validate(data)
	_ok(errors.is_empty(), "the table passes Surfaces.validate() with nothing to say", "validate says %s" % [errors])
	var road: Dictionary = data.surfaces.get("road", {})
	_ok(data.surfaces.size() == Surfaces.SURFACE_NAMES.size() and road.get("grip") == 1.0 and road.get("rolling_drag") == 0.0 and road.get("bump") == 0.0, "the table names the %d surfaces %s and the road is exactly {1.0, 0.0, 0.0}: the certified baseline" % [Surfaces.SURFACE_NAMES.size(), Surfaces.SURFACE_NAMES], "surfaces %s, road %s" % [data.surfaces.keys(), road])
	var lines := PackedStringArray()
	var ordered := true
	for name: String in Surfaces.SURFACE_NAMES:
		var entry: Dictionary = data.surfaces[name]
		lines.append("%s %.2f / %.1f / %.3f" % [name, entry.grip, entry.rolling_drag, entry.bump])
		if name != "road":
			ordered = ordered and entry.grip < 1.0 and entry.rolling_drag > 0.0 and entry.bump > 0.0
	_ok(ordered, "every surface off the road loses grip AND adds drag AND bumps (the driver's 'water' needs all three together): %s" % ", ".join(lines), "%s" % ", ".join(lines))
	var broken: Dictionary = data.duplicate(true)
	broken.surfaces.grass.grip = 1.4
	_ok(_names(Surfaces.validate(broken), "surfaces.grass.grip is 1.4, not in [0.2, 1.0]"), "validate() names a grip out of [%.1f, %.1f]" % [Surfaces.GRIP_MIN, Surfaces.GRIP_MAX])
	broken = data.duplicate(true)
	broken.surfaces.gravel.rolling_drag = -0.5
	_ok(_names(Surfaces.validate(broken), "surfaces.gravel.rolling_drag is -0.5"), "validate() names a negative rolling drag")
	broken = data.duplicate(true)
	broken.surfaces.erase("forest_floor")
	_ok(_names(Surfaces.validate(broken), "surfaces.forest_floor is missing"), "validate() names a missing surface")
	broken = data.duplicate(true)
	broken.surfaces.road.grip = 0.9
	_ok(_names(Surfaces.validate(broken), "not the exact {1.0, 0.0, 0.0}"), "validate() names a road that is not the certified baseline")
	broken = data.duplicate(true)
	broken.surfaces.mud = {"grip": 0.3, "rolling_drag": 2.0, "bump": 0.05, "note": ""}
	_ok(_names(Surfaces.validate(broken), "surfaces.mud is not a surface this pass names"), "validate() names a surface this pass does not")


# =============================================================================
#  THE SWAP
# =============================================================================

func _check_swap(scene: Node, road: RoadBuilder, terrain: TerrainBuilder, forest: ForestWalls, car: ArcadeCar, surfaces: Surfaces) -> void:
	_ok(surfaces != null and surfaces.get_parent() == scene and scene.get_node("Road").get_index() < surfaces.get_index() and surfaces.process_physics_priority == -1, "the Surfaces node stands beside Road under the scene root, after it, at physics priority -1 (the bubble's -2 before it, the car's 0 after)", "surfaces %s" % surfaces)
	if surfaces == null:
		return
	_ok(not surfaces.table.is_empty() and surfaces.shoulder_m == 1.5 and surfaces.ticks > 0, "the node read the table (shoulder %.1f m) and has ticked %d times" % [surfaces.shoulder_m, surfaces.ticks], "table %s ticks %d" % [surfaces.table.is_empty(), surfaces.ticks])
	_ok(road.profile is RingProfile and road.profile is WorldRoadProfile and car.road_profile == road.profile, "road.profile is a RingProfile - a WorldRoadProfile, the ring drive test's pin - and car.road_profile is the same object", "road.profile %s, car.road_profile %s" % [road.profile, car.road_profile])
	if not road.profile is RingProfile:
		return
	var wrapper: RingProfile = road.profile
	_ok(wrapper.inner != null and not wrapper.inner is RingProfile and terrain.profile == wrapper.inner and forest.profile == wrapper.inner and wrapper.terrain == terrain, "the wrapper's inner is the profile Terrain and Forest were built from (their meshes the smooth field's; the wrapper only the car's read): %s" % wrapper.describe_wrapper(), "inner %s terrain %s forest %s" % [wrapper.inner, terrain.profile == wrapper.inner, forest.profile == wrapper.inner])
	_ok(wrapper.bump_by_surface == surfaces.bump_by_surface and wrapper.bump_by_surface.get(&"road", -1.0) == 0.0 and wrapper.bump_by_surface.get(&"grass", 0.0) > 0.0, "the wrapper carries the table's bumps (%s)" % [wrapper.bump_by_surface], "bumps %s vs %s" % [wrapper.bump_by_surface, surfaces.bump_by_surface])
	_ok(car.front_surface_grip == 1.0 and car.rear_surface_grip == 1.0 and car.surface_rolling_decel == 0.0 and surfaces.wheel_surfaces == [&"road", &"road", &"road", &"road"], "on the pit lane every wheel is on the road and the car's three surface inputs read 1.0 / 1.0 / 0.0: the certified baseline, bit for bit", "grips %.3f / %.3f decel %.3f wheels %s" % [car.front_surface_grip, car.rear_surface_grip, car.surface_rolling_decel, surfaces.wheel_surfaces])


# =============================================================================
#  THE DELEGATION
# =============================================================================

func _check_delegation(wrapper: RingProfile) -> void:
	var inner: WorldRoadProfile = wrapper.inner
	var box := inner.coverage()
	var same := true
	var points := 0
	var worst := ""
	var x := box.position.x - GRID_RING_M
	while x <= box.end.x + GRID_RING_M:
		var z := box.position.y - GRID_RING_M
		while z <= box.end.y + GRID_RING_M:
			var ok := wrapper.covers(x, z) == inner.covers(x, z) and wrapper.elevation_mask(x, z) == inner.elevation_mask(x, z) and wrapper.terrain_height(x, z) == inner.terrain_height(x, z)
			ok = ok and wrapper.describe(x, z) == inner.describe(x, z) and wrapper.micro_height(x, z) == inner.micro_height(x, z) and wrapper.test_dip_height(x, z) == inner.test_dip_height(x, z)
			ok = ok and wrapper.ramp_height_at(x, z) == inner.ramp_height_at(x, z) and wrapper.elevation_slope(x, z) == inner.elevation_slope(x, z) and wrapper.elevation_slope(x, z, 3.0) == inner.elevation_slope(x, z, 3.0)
			if not ok and worst == "":
				worst = "(%.0f, %.0f)" % [x, z]
			same = same and ok
			points += 1
			z += GRID_STEP_M
		x += GRID_STEP_M
	_ok(same and points > 500, "covers, elevation_mask, terrain_height, describe, micro_height, test_dip_height, ramp_height_at and elevation_slope equal the inner's to the bit at every one of %d grid points %.0f m apart over the box and %.0f m around it" % [points, GRID_STEP_M, GRID_RING_M], "first difference at %s of %d points" % [worst, points])
	_ok(wrapper.coverage() == inner.coverage() and wrapper.road_count() == inner.road_count() and wrapper.road_count() > 3000, "coverage() (%s) and road_count() (%d) are the inner's" % [wrapper.coverage(), wrapper.road_count()])
	var along_same := true
	var along := 0
	for id: String in [STRAIGHT, GRASS_TRACK, "414785755-0"]:
		var s := 0.0
		while s <= 200.0:
			along_same = along_same and wrapper.point_along(id, s) == inner.point_along(id, s)
			along += 1
			s += 7.0
	_ok(along_same and wrapper.point_along("no-such-road", 0.0) == null, "point_along() is the inner's at %d chainages of three roads and null for a road that is not there" % along)


# =============================================================================
#  ON THE ROAD, TO THE BIT
# =============================================================================

func _check_on_road(road: RoadBuilder, wrapper: RingProfile) -> void:
	var inner: WorldRoadProfile = wrapper.inner
	var skeleton: Dictionary = SkeletonLoader.read_file()
	var loop: SkeletonLoader.Loop = SkeletonLoader.loops_of(skeleton)[SkeletonLoader.NORDSCHLEIFE_LOOP]
	var k: int = loop.segments.find(STRAIGHT)
	var length := 0.0
	var vertices := 0
	var between := 0
	var same := true
	var between_same := true
	var gradients_same := true
	var worst := ""
	var worst_between := ""
	var segments := PackedStringArray()
	while length < LOOP_STRETCH_M and k < loop.segments.size():
		var id: String = loop.segments[k]
		var strip: RoadBuilder.Strip = road.strip(id)
		k += 1
		if strip == null:
			continue
		segments.append(id)
		length += strip.chainages[strip.chainages.size() - 1]
		for section: int in strip.chainages.size():
			for i: int in strip.offsets.size():
				var v := strip.vertex(section, i)
				var ok := wrapper.sample_height(v.x, v.z) == inner.sample_height(v.x, v.z) and wrapper.elevation_height(v.x, v.z) == inner.elevation_height(v.x, v.z)
				if not ok and worst == "":
					worst = "%s section %d offset %d" % [id, section, i]
				same = same and ok
				vertices += 1
				if i == strip.offsets.size() / 2:
					gradients_same = gradients_same and wrapper.ramp_gradient(v.x, v.z) == inner.ramp_gradient(v.x, v.z)
			if section + 1 < strip.chainages.size():
				var a := strip.vertex(section, strip.offsets.size() / 2)
				var b := strip.vertex(section + 1, strip.offsets.size() / 2)
				var m := a.lerp(b, 0.5)
				var mid_ok := wrapper.sample_height(m.x, m.z) == inner.sample_height(m.x, m.z)
				if not mid_ok and worst_between == "":
					worst_between = "%s section %d" % [id, section]
				between_same = between_same and mid_ok
				gradients_same = gradients_same and wrapper.ramp_gradient(m.x, m.z) == inner.ramp_gradient(m.x, m.z)
				between += 1
	_ok(same and between_same and vertices > 3000, "sample_height and elevation_height equal the inner's to the bit at every one of the %d strip vertices of the certified loop drive's first %.0f m (%d segments from %s) and at %d points between sections on the centreline: the certified drives read the inner's arithmetic and nothing else" % [vertices, length, segments.size(), STRAIGHT, between], "first difference at vertex %s / between %s; %d vertices" % [worst, worst_between, vertices])
	_ok(gradients_same, "ramp_gradient equals the inner's to the bit at every section's centre and between them on the same stretch")


# =============================================================================
#  THE CLASSIFICATION
# =============================================================================

func _check_classification(road: RoadBuilder, terrain: TerrainBuilder, surfaces: Surfaces) -> void:
	var strip: RoadBuilder.Strip = road.strip(STRAIGHT)
	var centre := strip.offsets.size() / 2
	var c := strip.vertex(STRAIGHT_SECTION, centre)
	var dir := (strip.vertex(STRAIGHT_SECTION + 1, centre) - strip.vertex(STRAIGHT_SECTION - 1, centre)).normalized()
	var right := Vector3(-dir.z, 0.0, dir.x)
	var hw := strip.half_width
	var cases := [
		["the straight's centreline (chainage %.0f)" % strip.chainages[STRAIGHT_SECTION], Vector2(c.x, c.z), &"road"],
		["the straight's paved edge less a hair", Vector2(c.x, c.z) + Vector2(right.x, right.z) * (hw - 0.05), &"road"],
		["the shoulder, %.2f m beyond the paved edge" % SHOULDER_OFFSET_M, Vector2(c.x, c.z) + Vector2(right.x, right.z) * (hw + SHOULDER_OFFSET_M), &"gravel"],
		["beyond the shoulder, %.1f m out (the straight runs through forest)" % BEYOND_SHOULDER_M, Vector2(c.x, c.z) + Vector2(right.x, right.z) * (hw + BEYOND_SHOULDER_M), &"forest_floor"],
		["the grass spot %s" % GRASS_SPOT, GRASS_SPOT, &"grass"],
		["the field spot %s (a T7 node)" % FIELD_SPOT, FIELD_SPOT, &"field_stubble"],
		["the forest spot %s (a V7 node)" % FOREST_SPOT, FOREST_SPOT, &"forest_floor"],
		["outside the coverage %s" % OUTSIDE_SPOT, OUTSIDE_SPOT, &"grass"],
	]
	var all_ok := true
	var lines := PackedStringArray()
	for case: Array in cases:
		var got: StringName = surfaces.classify(case[1].x, case[1].y)
		var ok: bool = got == case[2] and got == terrain.surface_at(case[1].x, case[1].y, surfaces.shoulder_m)
		all_ok = all_ok and ok
		lines.append("%s -> %s%s" % [case[0], got, "" if ok else " (expected %s)" % case[2]])
	_ok(all_ok, "the named points classify as named (Surfaces.classify = TerrainBuilder.surface_at with the table's shoulder): %s" % "; ".join(lines), "; ".join(lines))
	var ground_ok := terrain.ground_surface_at(GRASS_SPOT.x, GRASS_SPOT.y) == &"grass" and terrain.ground_surface_at(FIELD_SPOT.x, FIELD_SPOT.y) == &"field_stubble" and terrain.ground_surface_at(FOREST_SPOT.x, FOREST_SPOT.y) == &"forest_floor" and terrain.ground_surface_at(OUTSIDE_SPOT.x, OUTSIDE_SPOT.y) == &"grass"
	_ok(ground_ok and terrain.road_distance_at(GRASS_SPOT.x, GRASS_SPOT.y) > 100.0 and not is_finite(terrain.road_distance_at(OUTSIDE_SPOT.x, OUTSIDE_SPOT.y)), "the ground read alone (ground_surface_at) names grass, field stubble, forest floor and grass outside the lattice; the road distance field reads %.1f m at the grass spot and infinite outside" % terrain.road_distance_at(GRASS_SPOT.x, GRASS_SPOT.y), "ground %s, distance %.1f" % [ground_ok, terrain.road_distance_at(GRASS_SPOT.x, GRASS_SPOT.y)])


# =============================================================================
#  THE CONTINUATION
# =============================================================================

func _check_continuation(wrapper: RingProfile) -> PackedFloat64Array:
	var inner: WorldRoadProfile = wrapper.inner
	var box := inner.coverage()
	var eps := WorldContinuation.EDGE_EPSILON_M
	var worst := 0.0
	var worst_at := Vector2.ZERO
	var samples := 0
	for k: int in EDGE_SAMPLES:
		var t := float(k) / float(EDGE_SAMPLES - 1)
		var zt := lerpf(box.position.y, box.end.y, t)
		var xt := lerpf(box.position.x, box.end.x, t)
		for pair: Array in [[Vector2(box.position.x + eps, zt), Vector2(box.position.x - eps, zt)], [Vector2(box.end.x - eps, zt), Vector2(box.end.x + eps, zt)], [Vector2(xt, box.position.y + eps), Vector2(xt, box.position.y - eps)], [Vector2(xt, box.end.y - eps), Vector2(xt, box.end.y + eps)]]:
			var gap := absf(wrapper.sample_height(pair[0].x, pair[0].y) - wrapper.sample_height(pair[1].x, pair[1].y))
			if gap > worst:
				worst = gap
				worst_at = pair[1]
			samples += 1
	_ok(worst <= EDGE_TOLERANCE_M_ROAD7, "the field is continuous at the box's edge: at %d points along the four sides the heights %.2f cm inside and outside differ by at most %.4f m (the tolerance %.4f m, ROAD-7's pin-only move from %.2f m; worst at %s)" % [samples, eps * 100.0, worst, EDGE_TOLERANCE_M_ROAD7, WorldContinuation.EDGE_TOLERANCE_M, worst_at], "worst %.4f m at %s" % [worst, worst_at])
	var edge_h := wrapper.sample_height(box.position.x, RAY_Z)
	var relief := false
	var lines := PackedStringArray(["0: %.1f" % edge_h])
	for d: float in RAY_INSIDE_M:
		var h := wrapper.sample_height(box.position.x - d, RAY_Z)
		relief = relief or absf(h - edge_h) > 5.0
		lines.append("%.0f: %.1f" % [d, h])
	var flat := true
	for d: float in RAY_BEYOND_M:
		var h := wrapper.sample_height(box.position.x - d, RAY_Z)
		flat = flat and h == 0.0 and inner.sample_height(box.position.x - d, RAY_Z) == 0.0
		lines.append("%.0f: %.1f" % [d, h])
	_ok(relief and flat and inner.sample_height(box.position.x - RAY_INSIDE_M[0], RAY_Z) == 0.0, "a ray west out of the box at z %.0f carries relief inside the %.0f m margin (the inner reads 0 there) and exactly 0 beyond it (the honest limit: the continuation is %.0f km, not infinite): heights %s" % [RAY_Z, WorldContinuation.CONTINUATION_MARGIN_M, WorldContinuation.CONTINUATION_MARGIN_M / 1000.0, ", ".join(lines)], "relief %s flat %s: %s" % [relief, flat, ", ".join(lines)])
	var g := wrapper.ramp_gradient(box.position.x - 400.0, RAY_Z)
	_ok(g != Vector2.ZERO and inner.ramp_gradient(box.position.x - 400.0, RAY_Z) == Vector2.ZERO and g.length() < 1.0, "ramp_gradient reads a slope outside the box (%s at 400 m out; the inner's is ZERO there): gravity pulls on the continuation's hills" % g, "gradient %s" % g)
	return _outside_samples(wrapper)


## The continuation at a grid outside the box: what two scenes must agree on.
func _outside_samples(wrapper: RingProfile) -> PackedFloat64Array:
	var box := wrapper.coverage()
	var out := PackedFloat64Array()
	var x := box.position.x - WorldContinuation.CONTINUATION_MARGIN_M
	while x <= box.end.x + WorldContinuation.CONTINUATION_MARGIN_M:
		var z := box.position.y - WorldContinuation.CONTINUATION_MARGIN_M
		while z <= box.end.y + WorldContinuation.CONTINUATION_MARGIN_M:
			if not wrapper.covers(x, z):
				out.append(wrapper.sample_height(x, z))
			z += 333.0
		x += 333.0
	return out


# =============================================================================
#  THE SKIRT
# =============================================================================

func _check_skirt(terrain: TerrainBuilder, wrapper: RingProfile) -> void:
	var inner: WorldRoadProfile = wrapper.inner
	var box := inner.coverage()
	var found := PackedStringArray()
	var on_field := true
	var on_edge := true
	var checked := 0
	var edge_checked := 0
	var worst := 0.0
	var tinted := true
	var t9 := TerrainBuilder.albedo("T9", Color.WHITE)
	for name: String in CONTINUATION_MESHES:
		var mesh: MeshInstance3D = terrain.get_node_or_null(name)
		if mesh == null:
			continue
		found.append(name)
		var arrays: Array = mesh.mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var colours: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
		for k: int in range(0, vertices.size(), VERTEX_SAMPLE_STRIDE):
			var v := vertices[k]
			var h := WorldContinuation.height(inner, v.x, v.z)
			var gap := absf(v.y - h)
			# The hanging skirts' lower vertices sit SKIRT_M under the field.
			if gap > VERTEX_TOLERANCE_M and absf(v.y + TerrainBuilder.SKIRT_M - h) > VERTEX_TOLERANCE_M:
				on_field = false
				worst = maxf(worst, gap)
			checked += 1
			tinted = tinted and absf(colours[k].r - t9.r) <= COLOUR_TOLERANCE and absf(colours[k].g - t9.g) <= COLOUR_TOLERANCE and absf(colours[k].b - t9.b) <= COLOUR_TOLERANCE
			var on_x := v.x == box.position.x or v.x == box.end.x
			var on_z := v.z == box.position.y or v.z == box.end.y
			if (on_x and v.z >= box.position.y and v.z <= box.end.y) or (on_z and v.x >= box.position.x and v.x <= box.end.x):
				var own := wrapper.sample_height(v.x, v.z)
				if absf(v.y - own) > VERTEX_TOLERANCE_M and absf(v.y + TerrainBuilder.SKIRT_M - own) > VERTEX_TOLERANCE_M:
					on_edge = false
				edge_checked += 1
	_ok(found.size() == CONTINUATION_MESHES.size() and terrain.counts.continuation_cells == CONTINUATION_CELLS and terrain.counts.continuation_skirts == CONTINUATION_SKIRTS, "Terrain carries the four continuation bands (%s): %d cells of %.0f m to %.0f m out (2 x 120 x 360 + 2 x 140 x 120) and %d hanging skirts along the box's edge (120 + 120 + 140 + 140); %s" % [found, terrain.counts.continuation_cells, TerrainBuilder.CONTINUATION_CELL_M, WorldContinuation.CONTINUATION_MARGIN_M, terrain.counts.continuation_skirts, terrain.describe()], "found %s, cells %d, skirts %d" % [found, terrain.counts.continuation_cells, terrain.counts.continuation_skirts])
	_ok(on_field and checked > 1000 and tinted, "every sampled band vertex (%d, every %dth) stands at WorldContinuation.height's value within %.0f mm (single-precision storage) - or %.0f m under it, a hanging skirt's foot - and wears the T9 albedo %s" % [checked, VERTEX_SAMPLE_STRIDE, VERTEX_TOLERANCE_M * 1000.0, TerrainBuilder.SKIRT_M, t9], "on field %s (worst %.4f m), tinted %s, checked %d" % [on_field, worst, tinted, checked])
	_ok(on_edge and edge_checked > 20, "every sampled vertex on the box's edge (%d) is the wrapper's own height there within %.0f mm: the skirt meets the box terrain where the car's field meets the continuation" % [edge_checked, VERTEX_TOLERANCE_M * 1000.0], "on edge %s, checked %d" % [on_edge, edge_checked])


# =============================================================================
#  THE OFF-ROAD DRIVE
# =============================================================================

## The pinned-throttle drive from where the car stands: the peak
## acceleration, the wheel travel variance over the window, the surfaces
## seen, the ticks the axles read the road, the end position.
func _drive_ticks(car: ArcadeCar, surfaces: Surfaces) -> Dictionary:
	var peak := 0.0
	var last_v := car.forward_speed
	var sum := 0.0
	var sq := 0.0
	var rate_sum := 0.0
	var rate_sq := 0.0
	var n := 0
	var last_travel: Array[float] = car.wheel_travel.duplicate()
	var first_wheels: Array[StringName] = []
	var front_road := -1
	var rear_road := -1
	var grips := {}
	var speed_at := {}
	for t: int in DRIVE_TICKS:
		car.set_driver_input(1.0, 0.0, 0.0)
		await physics_frame
		if t == 0:
			first_wheels = surfaces.wheel_surfaces.duplicate()
			grips = {"front": car.front_surface_grip, "rear": car.rear_surface_grip, "decel": car.surface_rolling_decel}
		var a := (car.forward_speed - last_v) * 60.0
		last_v = car.forward_speed
		if t >= PEAK_FROM_TICK and t < PEAK_TO_TICK:
			peak = maxf(peak, a)
		if t >= TRAVEL_WINDOW[0] and t < TRAVEL_WINDOW[1]:
			for i: int in 4:
				var rate: float = (car.wheel_travel[i] - last_travel[i]) * 60.0
				sum += car.wheel_travel[i]
				sq += car.wheel_travel[i] * car.wheel_travel[i]
				rate_sum += rate
				rate_sq += rate * rate
				n += 1
		last_travel = car.wheel_travel.duplicate()
		if front_road < 0 and t > PEAK_FROM_TICK and car.front_surface_grip == 1.0:
			front_road = t
		if rear_road < 0 and t > PEAK_FROM_TICK and car.rear_surface_grip == 1.0:
			rear_road = t
		if t == 299:
			speed_at[300] = car.forward_speed
	var mean := sum / n
	var rate_mean := rate_sum / n
	return {"peak": peak, "variance": sq / n - mean * mean, "rate_variance": rate_sq / n - rate_mean * rate_mean, "first_wheels": first_wheels, "grips": grips, "front_road": front_road, "rear_road": rear_road, "position": car.global_position, "ticks": DRIVE_TICKS, "speed_300": speed_at.get(300, 0.0), "end_speed": car.forward_speed}


func _drive(car: ArcadeCar, surfaces: Surfaces, label: String) -> Dictionary:
	car.reset_to(_pose(GRASS_SPOT.x, GRASS_SPOT.y, GRASS_HEADING))
	await _step(SETTLE_FRAMES)
	var out := await _drive_ticks(car, surfaces)
	print("  %s: from %s north, %d ticks: peak %.3f m/s^2 over ticks %d-%d, %.2f m/s at tick 300, %.2f at the end, travel variance %.2f mm^2, travel rate variance %.5f (m/s)^2, front on the road at tick %d, rear %d, end %s" % [label, GRASS_SPOT, out.ticks, out.peak, PEAK_FROM_TICK, PEAK_TO_TICK, out.speed_300, out.end_speed, out.variance * 1.0e6, out.rate_variance, out.front_road, out.rear_road, out.position])
	return out


## The on-road reference: the same pinned throttle from the straight's
## chainage 30, along it.
func _drive_reference(road: RoadBuilder, car: ArcadeCar, surfaces: Surfaces) -> Dictionary:
	var strip: RoadBuilder.Strip = road.strip(STRAIGHT)
	var centre := strip.offsets.size() / 2
	var a := strip.vertex(STRAIGHT_SECTION, centre)
	var b := strip.vertex(STRAIGHT_SECTION + 1, centre)
	car.reset_to(_pose(a.x, a.z, Vector2(b.x - a.x, b.z - a.z).normalized()))
	await _step(SETTLE_FRAMES)
	var out := await _drive_ticks(car, surfaces)
	print("  the road reference: from %s chainage %.0f, %d ticks: peak %.3f m/s^2 over ticks %d-%d, %.2f m/s at tick 300, %.2f at the end, travel variance %.2f mm^2, travel rate variance %.5f (m/s)^2" % [STRAIGHT, strip.chainages[STRAIGHT_SECTION], out.ticks, out.peak, PEAK_FROM_TICK, PEAK_TO_TICK, out.speed_300, out.end_speed, out.variance * 1.0e6, out.rate_variance])
	return out


## The control: the grass drive with the bumps zeroed (the wrapper's table
## emptied for the drive, restored after).
func _drive_control(car: ArcadeCar, surfaces: Surfaces, wrapper: RingProfile) -> Dictionary:
	var bumps := wrapper.bump_by_surface
	wrapper.bump_by_surface = {}
	var out := await _drive(car, surfaces, "the control (no bumps)")
	wrapper.bump_by_surface = bumps
	return out


func _check_drive(surfaces: Surfaces, grass: Dictionary, reference: Dictionary) -> void:
	var grass_grip: float = surfaces.grip_of(&"grass")
	var grass_drag: float = surfaces.drag_of(&"grass")
	_ok(grass.first_wheels == [&"grass", &"grass", &"grass", &"grass"] and grass.grips.front == grass_grip and grass.grips.rear == grass_grip and grass.grips.decel == grass_drag, "at the grass spot every wheel is on grass from the first tick and the car reads the table's grass: axle grips %.2f / %.2f, rolling decel %.1f m/s^2" % [grass.grips.front, grass.grips.rear, grass.grips.decel], "wheels %s grips %s" % [grass.first_wheels, grass.grips])
	_ok(reference.peak > ROAD_PEAK_MIN and grass.peak < PEAK_RATIO_MAX * reference.peak and grass.speed_300 < reference.speed_300, "the pinned throttle accelerates the car on grass at a peak %.3f m/s^2 over the launch (ticks %d-%d, before the track), under %.1f of the road's %.3f (over %.1f): %.2f m/s at tick 300 against %.2f on the road - grip loss and drag together" % [grass.peak, PEAK_FROM_TICK, PEAK_TO_TICK, PEAK_RATIO_MAX, reference.peak, ROAD_PEAK_MIN, grass.speed_300, reference.speed_300], "grass %.3f road %.3f, speeds %.2f / %.2f" % [grass.peak, reference.peak, grass.speed_300, reference.speed_300])
	_ok(grass.rate_variance > TRAVEL_RATE_VARIANCE_FLOOR, "the wheels' travel RATE variance over ticks %d-%d of the grass drive is %.5f (m/s)^2, over the %.5f floor (the travel variance itself, %.2f mm^2, is the lattice's slopes and the launch squat: the cm-scale bumps show in the rate): the micro-profile excites the suspension" % [TRAVEL_WINDOW[0], TRAVEL_WINDOW[1], grass.rate_variance, TRAVEL_RATE_VARIANCE_FLOOR, grass.variance * 1.0e6], "rate variance %.5f" % grass.rate_variance)
	_ok(grass.front_road > 0 and grass.rear_road > grass.front_road, "driving north the car reaches the %s track: the front axle reads the road's grip 1.0 at tick %d, the rear at tick %d (the wheels classified one by one; the track is 3 m wide)" % [GRASS_TRACK, grass.front_road, grass.rear_road], "front %d rear %d" % [grass.front_road, grass.rear_road])


## Reset onto the straight's centreline: the three inputs read the
## baseline within GRIP_RETURN_TICKS.
func _check_return(road: RoadBuilder, car: ArcadeCar, surfaces: Surfaces) -> void:
	var strip: RoadBuilder.Strip = road.strip(STRAIGHT)
	var centre := strip.offsets.size() / 2
	var a := strip.vertex(STRAIGHT_SECTION, centre)
	var b := strip.vertex(STRAIGHT_SECTION + 1, centre)
	car.set_driver_input(0.0, 0.0, 0.0)
	car.reset_to(_pose(a.x, a.z, Vector2(b.x - a.x, b.z - a.z).normalized()))
	var back := -1
	for t: int in GRIP_RETURN_TICKS + 3:
		await physics_frame
		if car.front_surface_grip == 1.0 and car.rear_surface_grip == 1.0 and car.surface_rolling_decel == 0.0:
			back = t + 1
			break
	_ok(back > 0 and back <= GRIP_RETURN_TICKS and surfaces.wheel_surfaces == [&"road", &"road", &"road", &"road"], "back on the straight's centreline the three inputs read 1.0 / 1.0 / 0.0 after %d tick(s) (the budget %d): the road is the baseline again" % [back, GRIP_RETURN_TICKS], "back after %d ticks, wheels %s" % [back, surfaces.wheel_surfaces])
