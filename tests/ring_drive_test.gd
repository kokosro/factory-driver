extends SceneTree
## Headless ring drive test: the Nordschleife as a drivable road
## (implementation-plan.md §4B-4). Run via tests/run_tests.sh, or:
##
##   godot --headless --path . --import
##   godot --headless --fixed-fps 60 --path . --script res://tests/ring_drive_test.gd
##
## Loads scenes/eifel_ring.tscn the way the game does and lets RoadBuilder
## build the Ring's road headless from the checked-in skeleton and drape
## (drape.json pinned by sha256: the rim rule changes the parsed data, never
## the file); then holds what was built to the plan: the road node exists
## with every covered segment swept (the build's numbers reported), the
## car stands on the profile at the pit anchor with a WorldRoadProfile;
## the mesh is the field: every vertex of the loop's strips and of the pit
## and access strips lies on the CORRECTED profile's sample_height (the
## rim rule applied, the same field the car reads) within a millimetre, and
## the mesh between the vertices is probed at the quads' edges and centres
## (the twist bound) away from the skeleton's kinks, where the field itself
## steps between two chords and a continuous mesh cannot follow (measured,
## reported); the rim rule: Breidscheid's deck drawn straight between its
## rims, every loop bridge's abutment spike measured before and after
## through ramp_gradient (the car's own call), 41395668-0's east end -
## the one residual with two-segment junctions only, its approach
## 41395670-0 ending at the four-way T13 junction after 4.1 m - resolved
## by amendment 2's heading continuation onto the straighter Boxengasse
## branch 769107218-0 (59.3 % -> 3.0 %), 41226730-0 untouched with its
## below-ground reading and 41395681-0 (both abutments their own rims)
## likewise, the decks linear in the mesh, the rule a pure function of
## the parsed data (the complete parsed inputs snapshotted before and
## compared after, the complete outputs of two calls compared); every
## maximum folded from finite readings only over a positive count (the
## codex review of 4B-4: a NaN compares false against a worst and an
## empty sweep reports a clean zero); the hill step made executable: at the
## loop's steepest honest sample the world profile's gradient is non-zero
## and RoadProfile.flat()'s at the same point exactly zero (§2.3's
## byte-lock argument); the Karussell's bank read through ramp_gradient
## with the crossfall's sign; body attitude measured on the bank and on
## the steepest stretch (pitch and roll against the small-angle model,
## car.gd:87-90; sanity bounds only, the decision is the Conductor's); the
## scripted driver (a pure-pursuit follower of the loop's centreline, fed
## through set_driver_input every tick the way HandlingTests feeds the
## keys) drives 2 km from Döttinger Höhe along the loop's one-way direction
## with all four wheels carried (car.wheel_supported) every tick and every
## wheel's contact point (global_transform × WHEEL_CONTACT_POINTS, the
## seam car.gd itself reads the road through) inside the nearest loop
## chord's paved half width every tick, its worst lateral offset and its
## speeds logged, the two crossings on the way passed; and determinism: a second scene, instanced fresh,
## driven the same 2 km, lands on the same odometer and the same position
## to the bit. Garage.MAPS lists the Ring (the row's scene change itself is
## the menu test's). No network, no python; writes nothing under /tmp.
## Exits 0 on success, 1 on any fault.

const RING_SCENE := "res://scenes/eifel_ring.tscn"

## drape.json as checked in: the rim rule corrects parsed data, the file
## stays these bytes. was 4B-3's b8d4e531... (00db178 / 80b3917) ->
## ROAD-SMOOTHING's (2026-09-23: the plain segments' centre heights
## Whittaker-smoothed at lambda 5 with the crest/dip runs held to the raw
## data, every junction's ends stitched in height and crossfall;
## tools/world/drape.py's header, docs/design/4b/data-pipeline.md §5).
const DRAPE_SHA256 := "f3ca142bcc1a3a36ec559889f4d4261a36ee583c4fd52381f64fa09aae64354a"

## The drape's covered segments (tests/world_profile_test.gd's count) and
## the loop's (tests/skeleton_test.gd's): every one swept but the ten
## crossing structures the loop's right of way uncovers (measured 4B-4;
## RoadBuilder's header): along the lap from Döttinger Höhe the tunnel
## under the straight, the track bridge over Antoniusbuche, the roads
## under Hohenrain, T13, 41395681-0, two more track structures, Trierer
## Straße under Breidscheid, a tunnel, the secondary under the Döttinger
## Höhe bridge.
const COVERED_ROADS := 3314
const LOOP_SEGMENTS := 92
const CROSSINGS: Array[String] = ["377340334-0", "29898554-0", "41455756-6", "421642912-0", "828126276-0", "41795617-0", "41454323-0", "828129905-0", "288075148-0", "1050475919-0"]

## Physics frames to let the car settle after a load or a reset.
const SETTLE_FRAMES := 20

## The share of the loop's quads a vertex or a probe of which reads
## another road (a junction's field). was 0.05 (4B-4: 925 of 21 673
## quads) -> 0.10 (ROAD-SMOOTHING, 2026-09-23: the crossfall stitch at
## every junction puts a crossfall ramp on each segment's end chord, and
## the twist bound splits a ramp of 8 % into ~85 sections whatever its
## length, so the quads at the loop's own seams - counted here as
## "another road", the next loop segment - went 925 -> 1 593 of 22 721,
## 7.0 % (1 602 of 22 849 after the codex review's world-space re-tilt of
## the crossfall stitch): a mesh-density count, the field the same
## single-valued one).
const OTHER_ROAD_QUADS_SHARE_MAX := 0.10

## The driver's issue-0002 ("there is something that appears as a big
## whole in the road", 2026-09-23T19:02, gear -1, speed 0): the car at
## this region point, the nearest loop chord and the crossing under it.
const ISSUE_0002_CAR := Vector2(714.38, -1782.091)
const ISSUE_0002_BRIDGE := "41395681-0"
const ISSUE_0002_UNDER := "828126276-0"
## Beyond the paved edge and the 6 m blend band the field is the terrain
## lattice: under a bridge that is the valley floor.
const ISSUE_0002_PROBE_M := 12.0
## Each side of the deck, and the ground under it, drops at least this
## much [m] (measured 4.13 m left, 5.61 m right, 5.58 m under).
const ISSUE_0002_DROP_MIN_M := 4.0

## The build's wall-time budget [ms]: 8-10 s measured on a machine at load
## average 7 (about a quarter of a core), 17 s with the suite's steps side
## by side; a minute is a broken build, not a slow machine.
const BUILD_TIME_LIMIT_MS := 60000

## A vertex is on the field within this [m]; between the vertices the
## twist bound (RoadBuilder.MESH_TOLERANCE_M) plus the mesh's single
## precision (a vertex 7 km from the origin is kept to ~0.5 mm in x and z,
## which on a 30 % bank moves the field under it by 0.15 mm).
const VERTEX_TOLERANCE_M := 0.001
const OFF_VERTEX_TOLERANCE_M := 0.0015

## The side roads whose strips are held to the field beside the loop's:
## the access link and the pit lane (ring-region-decisions.md §4).
const SIDE_SEGMENTS: Array[String] = ["26543901-0", "199642469-0", "199642470-0"]

## The Karussell (way 414785755, R9): the bank read at this chainage [m],
## clear of both ends.
const KARUSSELL_SEGMENT := "414785755-0"
const KARUSSELL_CHAINAGE_M := 76.0
const KARUSSELL_BANK := 0.30
const BANK_TOLERANCE := 0.01

## The loop's bridges (bridge=yes on relation 38566's segments) and what
## the rim rule was measured to do at 4B-4: every abutment spike under
## RIM_SLOPE afterwards. With two-segment junctions only, 41395668-0's east
## end kept its wall (its approach 41395670-0, 4.1 m, ends at the four-way
## T13 junction still climbing); amendment 2 (Conductor-endorsed
## 2026-09-23) lets the walk continue through the junction along the
## best-continuing segment, and that end resolves too - held here with
## its numbers.
const LOOP_BRIDGES: Array[String] = ["41395647-0", "41395652-0", "41395668-0", "41395673-0", "41395681-0"]
const HOHENRAIN_BRIDGE := "41395668-0"
const HOHENRAIN_END := 1
const BREIDSCHEID_BRIDGE := "41395647-0"
## Breidscheid's corrected deck line: the rims measured 338.76 m at 8.4 m
## before the bridge and 337.00 m at 8.0 m after it, the line -5.1 %
## (was the brief's -4.8 % estimate with the rim taken at 10 m: the first
## station climbing under 20 % onward is at 8.4 m).
const BREIDSCHEID_LINE_SLOPE := -0.0514
const BREIDSCHEID_RIMS_M := [8.44, 8.0]
const BREIDSCHEID_RIM_HEIGHTS_M := [338.76, 337.0]
const RIM_TOLERANCE_M := 0.05
const SLOPE_TOLERANCE := 0.002
## How far past an abutment the spike is looked for [m]: the walls are
## within 8.5 m, the rims within 8.5 m.
const SPIKE_REACH_M := 14.0

## The codex review's below-ground bridge: its deck this far under the
## DEM at this chainage (docs/night-shift-3.md, 4B-3), which the rule
## deliberately leaves.
const CODEX_BRIDGE := "41226730-0"
const CODEX_CHAINAGE_M := 94.0
const CODEX_BELOW_DEM_M := 1.472
## The profile's terrain is the 10 m lattice, not the 1 m DEM the review
## read: the deck is under the ground by more than this either way [m].
const CODEX_BELOW_MIN_M := 1.0

## The loop bridge the rule leaves as the file has it: both abutments
## already climb under RIM_SLOPE (their own rims: 1.3 % and 5.0 %), so
## there is no hole and no deck line - its dense heights are the file's.
const CLEAN_BRIDGE := "41395681-0"

## The codex review's twist-bound counterexample (RoadBuilder._twist_pieces):
## an interval this long [m] on a road of this half width [m] whose
## crossfall swings between these values needs this many pieces for the
## 1 mm bound; the old clamp to floor(interval / MIN_SECTION_M) returned
## one and left 10 mm of twist.
const TWIST_CASE_INTERVAL_M := 0.05
const TWIST_CASE_HALF_WIDTH_M := 4.0
const TWIST_CASE_CROSSFALL := [0.02, 0.03]
const TWIST_CASE_PIECES := 10

## A deck the rule left alone carries the file's centimetre-rounded
## stations, so its centre line is collinear within this [m]; a lifted
## deck's stations are exactly on the line.
const DECK_LINE_TOLERANCE_M := 0.01

## The steepest-sample search skips stations within this of a loop
## bridge's abutment [m] (tests/world_profile_test.gd's ABUTMENT_M): the
## honest grade, not the hole.
const ABUTMENT_M := 12.0

## Body attitude sanity bounds (open question 4: measure, do not fix): the
## small-angle model would be nonsense past this [deg], and a settled car
## stands over the road by its ride height, never in it.
const ATTITUDE_CEILING_DEG := 30.0
## (the car's origin sits at the road's height at rest, the ride height
## counted from there; on a grade it is lower by the pitch times the
## centre of mass's offset, 5 cm at 16 %).
const RIDE_HEIGHT_MIN_M := -0.2
const RIDE_HEIGHT_MAX_M := 1.5
const HOLD_FRAMES := 120

## The scripted drive: from Döttinger Höhe (segment 683303211-0, loop
## index 43) at this chainage, this far along the loop's one-way direction
## (the loop chains forward: every segment's last point is the next one's
## first), at this cruise speed [m/s] eased for the bends by a lateral
## acceleration budget [m/s²] read off the centreline's curvature ahead;
## the pure-pursuit lookahead grows with speed [s] between two bounds
## [m]; the pedals are a proportional controller on the speed error; the
## drive has this long [s].
const DRIVE_START_SEGMENT := "683303211-0"
const DRIVE_START_CHAINAGE_M := 30.0
const DRIVE_DISTANCE_M := 2000.0
const CRUISE_SPEED := 18.0
const LATERAL_ACCEL_BUDGET := 4.0
const LOOKAHEAD_S := 1.2
const LOOKAHEAD_MIN_M := 8.0
const LOOKAHEAD_MAX_M := 40.0
const CURVATURE_PREVIEW_M := 60.0
const PEDAL_GAIN := 0.3
const DRIVE_TIME_LIMIT_S := 240.0
## The path is built this far along the loop [m]: the drive plus the
## preview.
const PATH_LENGTH_M := 2400.0
## The whole-loop sweep's spacing [m] (half a station: a step over a
## metre or two cannot hide between samples).
const LOOP_SWEEP_STEP_M := 1.0
## The drive is held clean this close to a crossing's along-lap distance
## [m]: on the loop's own field, no wheel in the air.
const CROSSING_PASS_M := 5.0
## Speed statistics skip the pull-away [s].
const SPEED_STATS_FROM_S := 10.0
## The follower floor is the field's height at its place (its position is
## a single-precision Vector3: the height is kept to a tenth of a
## millimetre at 600 m) [m], and its tick-to-tick step may exceed the
## grade times the way by the field's crossfall and rounding [m].
const FLOOR_FIELD_TOLERANCE_M := 0.0002
const FLOOR_STEP_SLACK_M := 0.02

var _failures := 0
var _skeleton: Dictionary
var _drape: Dictionary
var _segments: Dictionary
var _raw_points: Dictionary = {}
var _loop: SkeletonLoader.Loop
## Every loop station: [x, z, id, chainage], and the loop's abutments.
var _loop_stations: Array[Array] = []
var _abutments: Array[Vector2] = []
var _steepest := {}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_skeleton = SkeletonLoader.read_file()
	_drape = WorldRoadProfile.read_file()
	_segments = SkeletonLoader.segments_of(_skeleton)
	for raw: Variant in _skeleton.get("segments", []):
		if raw is Dictionary and raw.get("id") is String:
			_raw_points[raw.id] = raw.points
	_loop = SkeletonLoader.loops_of(_skeleton)[SkeletonLoader.NORDSCHLEIFE_LOOP]
	print("-- the files and the rule")
	_check_files()
	var raw_profile := WorldRoadProfile.from_data(_skeleton, _drape)
	_check_rule_purity()
	print("-- the scene")
	var scene := await _load_scene()
	if scene == null:
		_finish()
		return
	var road: RoadBuilder = scene.get_node("Road")
	var car: ArcadeCar = scene.get_node("Car")
	_check_scene(road, car)
	_collect_loop_stations(road.profile)
	print("-- the mesh is the field")
	_check_mesh_vertices(road)
	_check_mesh_between(road)
	print("-- the rim rule")
	_check_rim_rule(road, raw_profile)
	print("-- the loop's right of way")
	_check_right_of_way(road)
	print("-- the drive")
	var first := await _drive(car, road, true)
	print("-- the hill step, the bank, the body")
	_check_hill_step(road.profile)
	_check_bank(road.profile)
	await _check_attitude(car, road.profile)
	root.remove_child(scene)
	scene.free()
	await _step(1)
	print("-- determinism")
	var again := await _load_scene()
	if again != null:
		var second := await _drive(again.get_node("Car"), again.get_node("Road"), false)
		_ok(first.odometer == second.odometer and first.position == second.position, "two scenes instanced fresh and driven the same 2 km land on the same odometer (%.6f m) and the same position (%s) to the bit" % [first.odometer, first.position], "the runs differ: odometer %.9f vs %.9f, position %s vs %s" % [first.odometer, second.odometer, first.position, second.position])
		root.remove_child(again)
		again.free()
	_finish()


func _finish() -> void:
	print("RING DRIVE TEST PASSED" if _failures == 0 else "RING DRIVE TEST FAILED: %d fault(s)" % _failures)
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


# =============================================================================
#  THE FILES AND THE RULE
# =============================================================================

func _check_files() -> void:
	_ok(_skeleton is Dictionary and _drape is Dictionary, "the skeleton and the drape read as JSON")
	_ok(FileAccess.get_sha256(WorldRoadProfile.PATH) == DRAPE_SHA256, "drape.json is byte-identical to ROAD-SMOOTHING's (sha256 %s; was 4B-3's b8d4e531...): the rim rule corrects parsed data, never the file" % DRAPE_SHA256.left(12), "drape.json's sha256 is %s" % FileAccess.get_sha256(WorldRoadProfile.PATH))
	var entry: Dictionary = Garage.MAPS[Garage.MAPS.size() - 1] if Garage.MAPS.size() == 2 else {}
	_ok(Garage.MAPS.size() == 2 and entry.get("id") == "eifel_ring" and entry.get("scene") == RING_SCENE and ResourceLoader.exists(RING_SCENE), "Garage.MAPS lists the Ring after the pad: id %s, scene %s, and the scene file exists (was one map, the Ring row a push_error)" % [entry.get("id"), entry.get("scene")], "Garage.MAPS is %s" % [Garage.MAPS])


## The rim rule is a pure function of the parsed data: twice on the same
## dictionaries, the same lifts and the same heights; the input untouched.
## Both transforms: the COMPLETE parsed inputs (the skeleton and the
## drape, every key) serialised before each call and compared after it,
## and the complete outputs of two independent calls compared (the whole
## output drape and every lift / every crossing), not a sample record or
## a count.
func _check_rule_purity() -> void:
	var skeleton_before := JSON.stringify(_skeleton)
	var drape_before := JSON.stringify(_drape)
	var first := RoadBuilder.apply_rim_rule(_skeleton, _drape)
	var input_kept: bool = JSON.stringify(_skeleton) == skeleton_before and JSON.stringify(_drape) == drape_before
	var second := RoadBuilder.apply_rim_rule(_skeleton, _drape)
	input_kept = input_kept and JSON.stringify(_skeleton) == skeleton_before and JSON.stringify(_drape) == drape_before
	var same: bool = JSON.stringify(first.drape) == JSON.stringify(second.drape) and JSON.stringify(first.lifts) == JSON.stringify(second.lifts)
	var changed := 0
	for i: int in first.drape.segments.size():
		if not is_same(first.drape.segments[i], _drape.segments[i]):
			changed += 1
	_ok(same and input_kept and first.drape.segments.size() == _drape.segments.size() and first.lifts.size() > 0, "apply_rim_rule is pure: twice on the parsed files, %d bridges lifted and %d records replaced, the complete output drape and every lift the same both times, the complete skeleton and drape (%d and %d bytes as JSON) untouched by either call" % [first.lifts.size(), changed, skeleton_before.length(), drape_before.length()], "same outputs %s, inputs kept %s" % [same, input_kept])
	var ruled_before := JSON.stringify(first.drape)
	var cleared := RoadBuilder.apply_right_of_way(_skeleton, first.drape)
	var ruled_kept: bool = JSON.stringify(_skeleton) == skeleton_before and JSON.stringify(first.drape) == ruled_before
	var cleared_again := RoadBuilder.apply_right_of_way(_skeleton, first.drape)
	ruled_kept = ruled_kept and JSON.stringify(_skeleton) == skeleton_before and JSON.stringify(first.drape) == ruled_before
	var cleared_same: bool = JSON.stringify(cleared.drape) == JSON.stringify(cleared_again.drape) and JSON.stringify(cleared.crossings) == JSON.stringify(cleared_again.crossings)
	var uncovered := 0
	for i: int in cleared.drape.segments.size():
		if not cleared.drape.segments[i].covered and first.drape.segments[i].covered:
			uncovered += 1
	_ok(cleared_same and ruled_kept and uncovered == cleared.crossings.size() and uncovered > 0, "apply_right_of_way is pure: twice on the ruled data, the complete output drape and every one of the %d crossings the same both times, %d records uncovered, the complete skeleton and ruled drape untouched by either call" % [cleared.crossings.size(), uncovered], "same outputs %s, inputs kept %s, %d uncovered vs %d crossings" % [cleared_same, ruled_kept, uncovered, cleared.crossings.size()])


# =============================================================================
#  THE SCENE
# =============================================================================

## The scene added at the start of a physics step every time (the first
## call comes from a deferred call in idle time, the second right after a
## step began: added in idle time the car's first tick is a frame later,
## and a run's odometer would carry one idle tick more of creep than the
## other's).
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


func _check_scene(road: RoadBuilder, car: ArcadeCar) -> void:
	_ok(road != null and car != null and road.profile is WorldRoadProfile and car.road_profile == road.profile, "the scene loads headless: Road (RoadBuilder) and Car exist, the car's road_profile is the WorldRoadProfile the road was built from", "Road %s, Car %s, profile %s" % [road, car, car.road_profile if car else null])
	_ok(road.road_count == COVERED_ROADS - CROSSINGS.size() and road.strips.size() == road.road_count, "every covered segment but the %d crossing structures is swept: %s" % [CROSSINGS.size(), road.describe()], "%d roads swept, %d expected" % [road.road_count, COVERED_ROADS - CROSSINGS.size()])
	_ok(road.build_ms > 0 and road.build_ms <= BUILD_TIME_LIMIT_MS, "the road was built at load within the %d s budget (the wall time is not printed: a few seconds on a quiet machine, more on a loaded one, the suite's lines the same either way)" % (BUILD_TIME_LIMIT_MS / 1000), "the build took %d ms" % road.build_ms)
	var loop_swept := _loop.segments.size() == LOOP_SEGMENTS
	for id: String in _loop.segments:
		loop_swept = loop_swept and road.strip(id) != null
	_ok(loop_swept, "all %d loop segments have a strip" % _loop.segments.size(), "%d loop segments, %d expected, or one without a strip" % [_loop.segments.size(), LOOP_SEGMENTS])
	var strip: RoadBuilder.Strip = road.strip(DRIVE_START_SEGMENT)
	_ok(strip.body.collision_layer == RoadBuilder.ROAD_COLLISION_LAYER and strip.body.collision_mask == RoadBuilder.ROAD_COLLISION_MASK and strip.mesh_instance.mesh.get_surface_count() == 1, "a strip is a MeshInstance3D and a StaticBody3D trimesh on layer %d, mask %d (the car's mask is 1: it stands on the profile, chosen for the ring build)" % [strip.body.collision_layer, strip.body.collision_mask])
	var floor_body: StaticBody3D = road.get_node_or_null("Floor")
	_ok(floor_body != null and floor_body.collision_layer == 1 and floor_body.get_child(0).shape is BoxShape3D and is_equal_approx(floor_body.get_child(0).shape.size.y, RoadBuilder.FLOOR_THICKNESS_M), "the floor the car meets is one level slab (%.0f m square, %.1f m thick) on layer 1, its top put at the road under the car every tick (the pad's follower plane, as a slab: a plane left over the car for a tick after a reset ejected it)" % [RoadBuilder.FLOOR_SIZE_M, RoadBuilder.FLOOR_THICKNESS_M])
	var under := road.profile.sample_height(car.global_position.x, car.global_position.z)
	var describe := road.profile.describe(car.global_position.x, car.global_position.z)
	_ok(describe.get("road") == "199642470-0" and describe.get("on_road", false) and absf(describe.get("chainage", 0.0) - 20.0) < 0.05 and absf(describe.get("offset", 1.0)) < 0.01, "the car spawns at the pit anchor: Boxengasse an T13 %s chainage %.2f, offset %.3f m, (%.3f, %.3f), road height %.2f m, heading along the pit lane toward the loop (yaw %.2f°; chosen for the ring build)" % [describe.get("road"), describe.get("chainage", 0.0), describe.get("offset", 0.0), car.global_position.x, car.global_position.z, under, rad_to_deg(car.global_rotation.y)], "the car is over %s" % [describe])
	_ok(car.global_position.y - under > RIDE_HEIGHT_MIN_M and car.global_position.y - under < RIDE_HEIGHT_MAX_M and absf(floor_body.position.y - under) < 0.001, "the car stands on the road at %.3f m over it and the floor's top is at the road's height" % (car.global_position.y - under), "the car is %.3f m over the road, the floor at %.3f vs %.3f" % [car.global_position.y - under, floor_body.position.y, under])


## Every loop station as [x, z, id, chainage] from the files' 64-bit
## points, and the loop bridges' abutments.
func _collect_loop_stations(profile: WorldRoadProfile) -> void:
	for id: String in _loop.segments:
		var xs := PackedFloat64Array()
		var zs := PackedFloat64Array()
		for point: Array in _raw_points[id]:
			xs.append(point[0])
			zs.append(point[1])
		var chain := WorldRoadProfile.chainages(xs, zs)
		for s: float in WorldRoadProfile.station_chainages(chain[chain.size() - 1]):
			var p := _point_on(xs, zs, chain, s)
			_loop_stations.append([p[0], p[1], id, s])
		var segment: SkeletonLoader.Segment = _segments[id]
		if segment.tags.has("bridge") and segment.tags["bridge"] != "no":
			_abutments.append(segment.first())
			_abutments.append(segment.last())
	# The steepest honest sample: the grade along the travel direction
	# (not the bank across it), away from the abutments.
	var steepest := 0.0
	for station: Array in _loop_stations:
		if _near_abutment(Vector2(station[0], station[1])) or not _own(profile, station):
			continue
		var slope := _grade_along(profile, station)
		if slope > steepest:
			steepest = slope
			_steepest = {"x": station[0], "z": station[1], "id": station[2], "s": station[3], "slope": slope}


## Whether the field at a loop station and at its four gradient taps is
## the station's own segment (tests/world_profile_test.gd's own-road rule:
## at a junction with another road the field is the nearer centreline's).
func _own(profile: WorldRoadProfile, station: Array) -> bool:
	for tap: Vector2 in [Vector2.ZERO, Vector2(-1.0, 0.0), Vector2(1.0, 0.0), Vector2(0.0, -1.0), Vector2(0.0, 1.0)]:
		if profile.describe(station[0] + tap.x, station[1] + tap.y).get("road") != station[2]:
			return false
	return true


var _geometries := {}


## The grade along the road at a loop station: ramp_gradient's component
## along the chord's direction of travel (the Karussell's 30 % bank is
## across, not along).
func _grade_along(profile: WorldRoadProfile, station: Array) -> float:
	if not _geometries.has(station[2]):
		_geometries[station[2]] = _geometry_of(station[2])
	var geometry: Dictionary = _geometries[station[2]]
	var travel := _direction_on(geometry.xs, geometry.zs, geometry.chain, station[3])
	return absf(profile.ramp_gradient(station[0], station[1]).dot(travel))


func _near_abutment(at: Vector2) -> bool:
	for abutment: Vector2 in _abutments:
		if at.distance_to(abutment) <= ABUTMENT_M:
			return true
	return false


static func _point_on(xs: PackedFloat64Array, zs: PackedFloat64Array, chain: PackedFloat64Array, s: float) -> PackedFloat64Array:
	for i: int in range(1, chain.size()):
		if chain[i] >= s:
			var span := chain[i] - chain[i - 1]
			var u := 0.0 if span <= 0.0 else (s - chain[i - 1]) / span
			return PackedFloat64Array([xs[i - 1] + u * (xs[i] - xs[i - 1]), zs[i - 1] + u * (zs[i] - zs[i - 1])])
	return PackedFloat64Array([xs[xs.size() - 1], zs[zs.size() - 1]])


## The unit direction of travel at chainage s: the chord's.
static func _direction_on(xs: PackedFloat64Array, zs: PackedFloat64Array, chain: PackedFloat64Array, s: float) -> Vector2:
	for i: int in range(1, chain.size()):
		if chain[i] >= s and chain[i] > chain[i - 1]:
			return Vector2(xs[i] - xs[i - 1], zs[i] - zs[i - 1]).normalized()
	return Vector2(xs[xs.size() - 1] - xs[xs.size() - 2], zs[zs.size() - 1] - zs[zs.size() - 2]).normalized()


## Distance along the lap from Döttinger Höhe's start (the test drive's
## origin, loop index 43) to a chainage on a loop segment [m].
func _along_lap(id: String, chainage: float) -> float:
	var start := _loop.segments.find(DRIVE_START_SEGMENT)
	var along := 0.0
	for k: int in _loop.segments.size():
		var segment_id: String = _loop.segments[(start + k) % _loop.segments.size()]
		if segment_id == id:
			return along + chainage
		along += _geometry_of(segment_id).length
	return -1.0


func _geometry_of(id: String) -> Dictionary:
	var xs := PackedFloat64Array()
	var zs := PackedFloat64Array()
	for point: Array in _raw_points[id]:
		xs.append(point[0])
		zs.append(point[1])
	var chain := WorldRoadProfile.chainages(xs, zs)
	return {"xs": xs, "zs": zs, "chain": chain, "length": chain[chain.size() - 1]}


# =============================================================================
#  THE MESH IS THE FIELD
# =============================================================================

## Every vertex of the loop's strips and the side strips against
## sample_height at its own (x, z): the CORRECTED profile's, after the rim
## rule - the field the car reads.
func _check_mesh_vertices(road: RoadBuilder) -> void:
	var worst := 0.0
	var worst_where := ""
	var sampled := 0
	var ids: Array[String] = []
	ids.append_array(_loop.segments)
	ids.append_array(SIDE_SEGMENTS)
	var non_finite := 0
	for id: String in ids:
		var strip: RoadBuilder.Strip = road.strip(id)
		if strip == null:
			_ok(false, "", "%s has no strip" % id)
			continue
		for v: Vector3 in strip.vertices:
			var gap := absf(road.profile.sample_height(v.x, v.z) - v.y)
			sampled += 1
			if not is_finite(gap):
				non_finite += 1
				continue
			if gap > worst:
				worst = gap
				worst_where = id
	_ok(sampled > 0 and non_finite == 0 and worst <= VERTEX_TOLERANCE_M, "every one of the %d vertices of the %d loop strips and the %d side strips lies on the corrected profile's sample_height: the worst is %.3f mm off (%s), within 1 mm; every reading finite" % [sampled, _loop.segments.size(), SIDE_SEGMENTS.size(), 1000.0 * worst, worst_where], "a vertex of %s is %.4f m off the field, %d of %d readings not finite" % [worst_where, worst, non_finite, sampled])


## Between the vertices: the loop's quads probed at the along-edges'
## midpoints and the quads' centres. A quad touching a section at a
## skeleton point (or a segment's end, the junction with the next loop
## segment) is measured apart: there the field itself steps between two
## chords (their perpendicular offsets tie on the bisector and the
## nearest-chord answer changes chainage), which a continuous mesh cannot
## follow - reported, the interior held to the twist bound.
func _check_mesh_between(road: RoadBuilder) -> void:
	var worst_interior := 0.0
	var worst_kink := 0.0
	var worst_other := 0.0
	var interior := 0
	var at_kinks := 0
	var at_others := 0
	var non_finite := 0
	var where := ""
	for id: String in _loop.segments:
		var strip: RoadBuilder.Strip = road.strip(id)
		var geometry := _geometry_of(id)
		# The kinks' chainages; a quad within the paved half width of one is
		# in the tie region (half width × tan of half the kink along the
		# road on the outer side), where the field steps between chords.
		var kinks := PackedFloat64Array()
		for i: int in range(1, geometry.chain.size() - 1):
			kinks.append(geometry.chain[i])
		var half_width: float = strip.offsets[strip.offsets.size() - 1]
		var across := strip.offsets.size()
		# Which road the field answered at each vertex: a quad with a vertex
		# on another road's field (a side road's centreline nearer at a
		# junction) spans the field's step and is that road's quad.
		var vertex_own: Array[bool] = []
		for v: Vector3 in strip.vertices:
			vertex_own.append(road.profile.describe(v.x, v.z).get("road") == id)
		for k: int in strip.chainages.size() - 1:
			# A strip's first and last quads meet the neighbouring loop
			# segment at a junction: a kink like any other.
			var kink: bool = k == 0 or k == strip.chainages.size() - 2
			for kink_at: float in kinks:
				kink = kink or (kink_at >= strip.chainages[k] - half_width and kink_at <= strip.chainages[k + 1] + half_width)
			var quad_worst := 0.0
			var own := true
			for i: int in across:
				own = own and vertex_own[k * across + i] and vertex_own[(k + 1) * across + i]
			for i: int in across:
				var a := strip.vertex(k, i)
				var b := strip.vertex(k + 1, i)
				var m := (a + b) * 0.5
				var described := road.profile.describe(m.x, m.z)
				own = own and described.get("road") == id
				var gap: float = absf(described.height - m.y)
				if is_finite(gap):
					quad_worst = maxf(quad_worst, gap)
				else:
					non_finite += 1
				if i + 1 < across:
					var c := strip.vertex(k + 1, i + 1)
					var centre := (a + c) * 0.5
					described = road.profile.describe(centre.x, centre.z)
					own = own and described.get("road") == id
					gap = absf(described.height - centre.y)
					if is_finite(gap):
						quad_worst = maxf(quad_worst, gap)
					else:
						non_finite += 1
			if not own:
				at_others += 1
				worst_other = maxf(worst_other, quad_worst)
			elif kink:
				at_kinks += 1
				worst_kink = maxf(worst_kink, quad_worst)
			else:
				interior += 1
				if quad_worst > worst_interior:
					worst_interior = quad_worst
					where = "%s at %.1f m" % [id, strip.chainages[k]]
	_ok(interior > 0 and non_finite == 0 and worst_interior <= OFF_VERTEX_TOLERANCE_M, "between the vertices, at the edges' midpoints and the centres of %d interior quads of the loop, the mesh is within %.2f mm of the field (worst %s; the twist bound %.0f mm); every probe finite" % [interior, 1000.0 * worst_interior, where, 1000.0 * RoadBuilder.MESH_TOLERANCE_M], "an interior quad of the loop is %.4f m off the field at %s, %d interior quads, %d probes not finite" % [worst_interior, where, interior, non_finite])
	_ok(at_kinks > 0 and worst_kink < 1.0, "at the %d quads within the half width of a skeleton kink or a segment's end the field's own step between chords shows: the mesh is up to %.1f mm off it there (reported, not the mesh's fault: the nearest-chord field is not continuous across a bisector)" % [at_kinks, 1000.0 * worst_kink], "a kink quad is %.3f m off, %d kink quads" % [worst_kink, at_kinks])
	_ok(at_others < OTHER_ROAD_QUADS_SHARE_MAX * (interior + at_kinks + at_others), "at %d of %d quads a vertex or a probe reads another road (a junction: the next loop segment's, the pit lane's, the access links'), where the field is that road's and the mesh is up to %.2f m off it - the single-valued field's step at a junction, the same the car feels (under %.0f %%; was 925 quads under 5 %% before the crossfall stitch's ramps were split for the twist bound)" % [at_others, interior + at_kinks + at_others, worst_other, 100.0 * OTHER_ROAD_QUADS_SHARE_MAX], "%d of %d quads read another road" % [at_others, interior + at_kinks + at_others])


# =============================================================================
#  THE RIM RULE
# =============================================================================

func _check_rim_rule(road: RoadBuilder, raw_profile: WorldRoadProfile) -> void:
	var lifts := {}
	for lift: Dictionary in road.lifts:
		lifts[lift.bridge] = lift
	# Breidscheid's deck line.
	var breidscheid: Dictionary = lifts.get(BREIDSCHEID_BRIDGE, {})
	var rims_right: bool = not breidscheid.is_empty() and absf(breidscheid.start.rim_m - BREIDSCHEID_RIMS_M[0]) <= RIM_TOLERANCE_M and absf(breidscheid.end.rim_m - BREIDSCHEID_RIMS_M[1]) <= RIM_TOLERANCE_M and absf(breidscheid.start.rim_height - BREIDSCHEID_RIM_HEIGHTS_M[0]) <= 0.005 and absf(breidscheid.end.rim_height - BREIDSCHEID_RIM_HEIGHTS_M[1]) <= 0.005
	_ok(rims_right and absf(breidscheid.line_slope - BREIDSCHEID_LINE_SLOPE) <= SLOPE_TOLERANCE, "Breidscheid %s: the rims are %.2f m before the bridge at %.2f m and %.2f m after it at %.2f m (the first stations climbing under %.0f %% onward); the deck line runs straight between them at %.2f %%, %d stations lifted by up to %.2f m (the V of 62-65 %% down and 50 %% up is gone)" % [BREIDSCHEID_BRIDGE, breidscheid.get("start", {}).get("rim_m", 0.0), breidscheid.get("start", {}).get("rim_height", 0.0), breidscheid.get("end", {}).get("rim_m", 0.0), breidscheid.get("end", {}).get("rim_height", 0.0), 100.0 * RoadBuilder.RIM_SLOPE, 100.0 * breidscheid.get("line_slope", 0.0), breidscheid.get("stations", 0), breidscheid.get("max_lift_m", 0.0)], "Breidscheid's lift is %s" % [breidscheid])
	# Every loop bridge's spike before and after, through ramp_gradient.
	var loop_ids := {}
	for id: String in _loop.segments:
		loop_ids[id] = true
	var unresolved := 0
	for id: String in LOOP_BRIDGES:
		var segment: SkeletonLoader.Segment = _segments[id]
		var ends: Array[Vector2] = [segment.first(), segment.last()]
		var lift: Dictionary = lifts.get(id, {})
		for end: int in 2:
			var before := _spike_near(ends[end], raw_profile)
			var after := _spike_near(ends[end], road.profile)
			var resolved: bool = before.samples > 0 and after.samples > 0 and after.slope < RoadBuilder.RIM_SLOPE
			if not resolved:
				unresolved += 1
			var rim: Dictionary = lift.get("start" if end == 0 else "end", {})
			var walk := ""
			for approach: Dictionary in rim.get("approaches", []):
				walk += (" -> " if walk != "" else "") + approach.id
			var rim_text := "no lift" if lift.is_empty() else ("rim %.2f m out at %.2f m along %s" % [rim.rim_m, rim.rim_height, walk] if rim.rim_m > 0.0 else ("its own rim" if rim.found else "no rim within reach"))
			var amended := " (was the one residual with two-segment junctions only, 59.2 %% before and after: amendment 2's continuation through the four-way T13 junction onto %s resolves it)" % (rim.approaches[1].id if rim.get("approaches", []).size() > 1 else "?") if id == HOHENRAIN_BRIDGE and end == HOHENRAIN_END else ""
			_ok(resolved and after.slope <= before.slope + 1e-9, "%s %s end (%s): the spike is %.1f %% before and %.1f %% after at %s (%d stations read) - resolved: true%s%s" % [id, "west" if end == 0 else "east", rim_text, 100.0 * before.slope, 100.0 * after.slope, after.where, after.samples, "" if before.slope >= RoadBuilder.RIM_SLOPE else " (already clean)", amended], "%s end %d: before %.3f (%d stations) after %.3f (%d stations) at %s (%s)" % [id, end, before.slope, before.samples, after.slope, after.samples, after.where, rim_text])
	_ok(unresolved == 0, "no residual on the loop: every abutment spike is under %.0f %% (was one, Hohenrain's east end, before amendment 2)" % (100.0 * RoadBuilder.RIM_SLOPE))
	# Stations past RIM_SLOPE after the rule, anywhere on the loop.
	var steep := 0
	var steepest := 0.0
	var steepest_where := ""
	var own_stations := 0
	var non_finite := 0
	for station: Array in _loop_stations:
		if not _own(road.profile, station):
			continue
		var grade := _grade_along(road.profile, station)
		if not is_finite(grade):
			non_finite += 1
			continue
		own_stations += 1
		if grade >= RoadBuilder.RIM_SLOPE:
			steep += 1
		if grade > steepest:
			steepest = grade
			steepest_where = "%s chainage %.0f" % [station[2], station[3]]
	_ok(steep == 0 and non_finite == 0 and own_stations > 0, "of the loop's %d stations, none of the %d on the loop's own field reads a grade along the road of %.0f %% or more after the rule (the steepest is %.1f %% at %s, every reading finite; was 19 stations at 50-64 %% in the DGM1's bridge holes)" % [_loop_stations.size(), own_stations, 100.0 * RoadBuilder.RIM_SLOPE, 100.0 * steepest, steepest_where], "%d stations past %.2f, the steepest %.3f at %s, %d own stations, %d readings not finite" % [steep, RoadBuilder.RIM_SLOPE, steepest, steepest_where, own_stations, non_finite])
	# The decks linear in the mesh.
	var worst_line := 0.0
	var worst_deck := ""
	var deck_vertices := 0
	var foreign := 0
	var line_non_finite := 0
	for id: String in LOOP_BRIDGES:
		var strip: RoadBuilder.Strip = road.strip(id)
		var n := strip.chainages.size()
		var h0 := strip.vertex(0, 1).y
		var h1 := strip.vertex(n - 1, 1).y
		var s0 := strip.chainages[0]
		var s1 := strip.chainages[n - 1]
		for k: int in range(1, n - 1):
			var v := strip.vertex(k, 1)
			if road.profile.describe(v.x, v.z).get("road") != id:
				foreign += 1
				continue
			deck_vertices += 1
			var line := h0 + (h1 - h0) * (strip.chainages[k] - s0) / (s1 - s0)
			var gap := absf(v.y - line)
			if not is_finite(gap):
				line_non_finite += 1
				continue
			if gap > worst_line:
				worst_line = gap
				worst_deck = id
	_ok(deck_vertices > 0 and line_non_finite == 0 and worst_line <= DECK_LINE_TOLERANCE_M and foreign == 0, "every loop bridge's deck is a straight line in the mesh: its %d centre vertices between the abutments are collinear within %.1f mm (worst %s, a deck the rule left as the file's centimetre stations), every reading finite, none reading another road now the crossings under the decks are uncovered" % [deck_vertices, 1000.0 * worst_line, worst_deck], "%s's deck bends by %.4f m in the mesh, %d centre vertices, %d not finite, %d read another road" % [worst_deck, worst_line, deck_vertices, line_non_finite, foreign])
	# 41226730-0 untouched, its below-ground reading.
	var raw_record := {}
	var ruled_record := {}
	for raw: Dictionary in _drape.segments:
		if raw.id == CODEX_BRIDGE:
			raw_record = raw
	for raw: Dictionary in road.drape_data.segments:
		if raw.id == CODEX_BRIDGE:
			ruled_record = raw
	var geometry := _geometry_of(CODEX_BRIDGE)
	var at := _point_on(geometry.xs, geometry.zs, geometry.chain, CODEX_CHAINAGE_M)
	var described := road.profile.describe(at[0], at[1])
	var below: float = described.terrain - described.centre
	_ok(ruled_record.dense == raw_record.dense and ruled_record.covered and not lifts.has(CODEX_BRIDGE) and described.get("road") == CODEX_BRIDGE and below > CODEX_BELOW_MIN_M, "%s is unchanged (its dense heights the file's, covered, no lift): its one walkable approach climbs away at 1-2 %% so its abutment is its own rim, the other end stands at a junction the walk does not enter; its deck stays %.2f m below the 10 m terrain lattice at chainage %.0f (the codex review read %.3f m below the 1 m DEM) - the below-ground instance the rule deliberately does not take" % [CODEX_BRIDGE, below, CODEX_CHAINAGE_M, CODEX_BELOW_DEM_M], "%s: same heights %s, lifted %s, road %s, below the lattice by %.3f" % [CODEX_BRIDGE, ruled_record.dense == raw_record.dense, lifts.has(CODEX_BRIDGE), described.get("road"), below])
	# 41395681-0 likewise: both abutments their own rims, no line drawn.
	var clean_raw := {}
	var clean_ruled := {}
	for raw: Dictionary in _drape.segments:
		if raw.id == CLEAN_BRIDGE:
			clean_raw = raw
	for raw: Dictionary in road.drape_data.segments:
		if raw.id == CLEAN_BRIDGE:
			clean_ruled = raw
	_ok(not clean_raw.is_empty() and clean_ruled.dense == clean_raw.dense and clean_ruled.covered and not lifts.has(CLEAN_BRIDGE) and road.strip(CLEAN_BRIDGE) != null, "%s is unchanged (its dense heights the file's, covered, swept, no lift): both abutments already climb under %.0f %% onward, their own rims at distance zero, so there is no hole and no deck line is drawn" % [CLEAN_BRIDGE, 100.0 * RoadBuilder.RIM_SLOPE], "%s: same heights %s, covered %s, lifted %s" % [CLEAN_BRIDGE, clean_ruled.get("dense") == clean_raw.get("dense"), clean_ruled.get("covered"), lifts.has(CLEAN_BRIDGE)])
	# Every lift has a rim found at both ends (nothing where no rim is
	# found), and a bridge with an end whose walk found none is not
	# lifted: 134220315-0 (off the loop) was, drawn to its unfound end's
	# abutment, before the codex review.
	var both_found := true
	for lift: Dictionary in road.lifts:
		both_found = both_found and lift.start.found and lift.end.found and (lift.start.rim_m > 0.0 or lift.end.rim_m > 0.0)
	_ok(road.lifts.size() > 0 and road.lifts.size() < 33 and both_found and not lifts.has("134220315-0"), "%d of the 33 covered bridges were lifted by the rule, every one with a rim found at both ends and at least one rim out past the abutment (the rest are their own rims at both ends, or have an end whose walk finds no rim: no line is drawn to an abutment that is not a rim - 134220315-0 was, 46 stations by up to 1.505 m, before the codex review)" % road.lifts.size(), "%d lifts, both ends found in all: %s, 134220315-0 lifted: %s" % [road.lifts.size(), both_found, lifts.has("134220315-0")])
	# The twist bound's piece count is the tolerance's, never clamped by
	# MIN_SECTION_M (the codex review's counterexample).
	var builder := RoadBuilder.new()
	var case_road := RoadBuilder.Road.new()
	case_road.half_width = TWIST_CASE_HALF_WIDTH_M
	var pieces: int = builder._twist_pieces(case_road, TWIST_CASE_CROSSFALL[0], TWIST_CASE_CROSSFALL[1], 0.0, TWIST_CASE_INTERVAL_M)
	var twist_left: float = absf(TWIST_CASE_CROSSFALL[1] - TWIST_CASE_CROSSFALL[0]) * TWIST_CASE_HALF_WIDTH_M / 4.0 / pieces
	var flat_pieces: int = builder._twist_pieces(case_road, 0.0, 0.0, 0.0, TWIST_CASE_INTERVAL_M)
	_ok(pieces == TWIST_CASE_PIECES and twist_left <= RoadBuilder.MESH_TOLERANCE_M + 1e-12 and builder.fine_split_count == 1 and flat_pieces == 1, "the twist bound's piece count is the tolerance's alone: a %.2f m interval on a %.0f m half width whose crossfall swings %.2f -> %.2f is split into %d pieces (%.1f mm of twist left, the bound %.0f mm; the old clamp to the interval over MIN_SECTION_M %.2f m returned one piece and left %.0f mm), counted as a fine split; a flat interval one piece" % [TWIST_CASE_INTERVAL_M, TWIST_CASE_HALF_WIDTH_M, TWIST_CASE_CROSSFALL[0], TWIST_CASE_CROSSFALL[1], pieces, 1000.0 * twist_left, 1000.0 * RoadBuilder.MESH_TOLERANCE_M, RoadBuilder.MIN_SECTION_M, 1000.0 * absf(TWIST_CASE_CROSSFALL[1] - TWIST_CASE_CROSSFALL[0]) * TWIST_CASE_HALF_WIDTH_M / 4.0], "%d pieces (%d expected), %.4f m of twist, fine splits %d, flat %d" % [pieces, TWIST_CASE_PIECES, twist_left, builder.fine_split_count, flat_pieces])
	builder.free()
	_ok(road.fine_split_count >= 0, "on the Ring's build %d intervals were split finer than MIN_SECTION_M %.2f m for the twist bound (reported: the bound holds everywhere, the interior quads above)" % [road.fine_split_count, RoadBuilder.MIN_SECTION_M])


## The steepest grade along the road (ramp_gradient's component along the
## travel direction) among the loop stations within SPIKE_REACH_M of `at`,
## where, and how many stations qualified (`samples`: zero when none did
## or a reading was not finite - the slope is then no measurement, and a
## caller must not take its 0.0 for a clean reading).
func _spike_near(at: Vector2, profile: WorldRoadProfile) -> Dictionary:
	var out := {"slope": 0.0, "where": "", "samples": 0}
	for station: Array in _loop_stations:
		if Vector2(station[0], station[1]).distance_to(at) > SPIKE_REACH_M or not _own(profile, station):
			continue
		var slope := _grade_along(profile, station)
		if not is_finite(slope):
			out.samples = 0
			out.slope = NAN
			out.where = "a non-finite reading at %s chainage %.0f" % [station[2], station[3]]
			return out
		out.samples += 1
		if slope > out.slope:
			out.slope = slope
			out.where = "%s chainage %.0f" % [station[2], station[3]]
	return out


# =============================================================================
#  THE LOOP'S RIGHT OF WAY
# =============================================================================

## The ten crossing structures uncovered: exactly the measured list, in
## the drape's order, each overlapping the loop's platform at another
## height, none with a strip; the loop's own field at each crossing.
func _check_right_of_way(road: RoadBuilder) -> void:
	var ids: Array[String] = []
	var total_length := 0.0
	for crossing: Dictionary in road.crossings:
		ids.append(crossing.id)
		var segment: SkeletonLoader.Segment = _segments[crossing.id]
		var length: float = _geometry_of(crossing.id).length
		total_length += length
		var removed: bool = road.strip(crossing.id) == null
		var kind := "tunnel" if segment.tags.get("tunnel") == "yes" else ("bridge" if segment.tags.get("bridge", "no") != "no" else "road under the loop's bridge")
		_ok(removed and absf(crossing.height - crossing.loop_height) > RoadBuilder.CROSSING_HEIGHT_M and crossing.distance_m <= RoadBuilder.CROSSING_DISTANCE_M and crossing.layer != crossing.loop_layer, "crossing %s (%s %s, %.0f m, layer %d against the loop's %d) at %.0f m along the lap from Döttinger Höhe (%s chainage %.0f): the loop at %.2f m, it at %.2f m, a step of %+.2f m - removed: %s" % [crossing.id, segment.road_class, kind, length, crossing.layer, crossing.loop_layer, _along_lap(crossing.loop, crossing.loop_chainage), crossing.loop, crossing.loop_chainage, crossing.loop_height, crossing.height, crossing.height - crossing.loop_height, removed], "crossing %s: removed %s, %s" % [crossing.id, removed, crossing])
	var expected := CROSSINGS.duplicate()
	expected.sort()
	var got := ids.duplicate()
	got.sort()
	_ok(got == expected, "the loop's right of way uncovers exactly the %d crossing structures measured at 4B-4 (%.0f m of side road in all), not built this iteration (chosen for the ring build)" % [ids.size(), total_length], "the crossings are %s" % [ids])
	# The whole loop's centreline, every metre: no step in the field
	# anywhere (the ten's were 1.6-6.0 m over a metre or two).
	var worst_step := 0.0
	var worst_at := ""
	var samples := 0
	var sweep_non_finite := 0
	var first_height := NAN
	var previous := NAN
	for id: String in _loop.segments:
		var geometry := _geometry_of(id)
		var s := 0.0
		while s < geometry.length:
			var p := _point_on(geometry.xs, geometry.zs, geometry.chain, s)
			var h := road.profile.sample_height(p[0], p[1])
			samples += 1
			s += LOOP_SWEEP_STEP_M
			if not is_finite(h):
				sweep_non_finite += 1
				continue
			if is_nan(first_height):
				first_height = h
			if not is_nan(previous) and absf(h - previous) > worst_step:
				worst_step = absf(h - previous)
				worst_at = "%s chainage %.0f" % [id, s - LOOP_SWEEP_STEP_M]
			previous = h
	# The closing seam: the last sample against the first (the loop's last
	# segment ends where its first begins).
	var closing_step := absf(first_height - previous)
	if is_finite(closing_step) and closing_step > worst_step:
		worst_step = closing_step
		worst_at = "the closing seam (%s's end onto %s's start)" % [_loop.segments[_loop.segments.size() - 1], _loop.segments[0]]
	_ok(samples > 0 and sweep_non_finite == 0 and is_finite(closing_step) and worst_step <= RoadBuilder.CROSSING_HEIGHT_M, "the whole loop swept along its centreline every %.0f m (%d samples, every height finite, the last sample folded back onto the first across the closing seam: %.3f m): no step over %.1f m remains anywhere in the field, the largest %.3f m at %s" % [LOOP_SWEEP_STEP_M, samples, closing_step, RoadBuilder.CROSSING_HEIGHT_M, worst_step, worst_at], "a step of %.3f m at %s, %d samples, %d not finite, the closing seam %.3f m" % [worst_step, worst_at, samples, sweep_non_finite, closing_step])
	var loop_field := true
	for crossing: Dictionary in road.crossings:
		var geometry := _geometry_of(crossing.loop)
		var at := _point_on(geometry.xs, geometry.zs, geometry.chain, crossing.loop_chainage)
		loop_field = loop_field and road.profile.describe(at[0], at[1]).get("road") == crossing.loop
	_ok(loop_field, "at every crossing the field on the loop's centreline is the loop's own (was the crossing road's, a step of 1.6-6.0 m the car drove into)")
	# Issue-0002's localisation: the car on the bridge deck over a
	# crossing structure the right of way uncovers, the valley floor
	# beside the deck.
	var where := road.profile.describe(ISSUE_0002_CAR.x, ISSUE_0002_CAR.y)
	var under_crossing := {}
	for crossing: Dictionary in road.crossings:
		if crossing.id == ISSUE_0002_UNDER:
			under_crossing = crossing
	var deck_geometry := _geometry_of(ISSUE_0002_BRIDGE)
	var deck_direction := _direction_on(deck_geometry.xs, deck_geometry.zs, deck_geometry.chain, where.get("chainage", 0.0))
	var right := Vector2(-deck_direction.y, deck_direction.x)
	var deck_here := road.profile.sample_height(ISSUE_0002_CAR.x, ISSUE_0002_CAR.y)
	var beside_right := road.profile.sample_height(ISSUE_0002_CAR.x + right.x * ISSUE_0002_PROBE_M, ISSUE_0002_CAR.y + right.y * ISSUE_0002_PROBE_M)
	var beside_left := road.profile.sample_height(ISSUE_0002_CAR.x - right.x * ISSUE_0002_PROBE_M, ISSUE_0002_CAR.y - right.y * ISSUE_0002_PROBE_M)
	var terrain := road.profile.terrain_height(ISSUE_0002_CAR.x, ISSUE_0002_CAR.y)
	var bridge_segment: SkeletonLoader.Segment = _segments[ISSUE_0002_BRIDGE]
	_ok(where.get("road") == ISSUE_0002_BRIDGE and where.get("on_road", false) and not under_crossing.is_empty() and under_crossing.loop == ISSUE_0002_BRIDGE and road.strip(ISSUE_0002_UNDER) == null and bridge_segment.tags.get("bridge", "no") != "no" and deck_here - terrain > ISSUE_0002_DROP_MIN_M and deck_here - beside_left > ISSUE_0002_DROP_MIN_M and deck_here - beside_right > ISSUE_0002_DROP_MIN_M, "issue-0002 (\"a big hole in the road\", the car at (%.2f, %.2f), reverse, standing) - checked: the car is on the loop's bridge deck %s (bridge=yes) at chainage %.1f, %.2f m from its centreline, %.2f m above the terrain lattice under it; the primary %s passes %.2f m under the deck and is one of the ten crossing structures the right of way uncovers (no strip built); %.0f m beside the deck the field drops %.2f m on the left and %.2f m on the right, each over %.0f m. The reading for the driver: the DGM1 is a ground model, so the terrain under and beside the deck is the valley floor, and neither the bridge's sides nor the road under it is built - the hole is that missing structure, not a height in the file (the deck is linear and the same bytes as before the smoothing); reader-side work, recorded" % [ISSUE_0002_CAR.x, ISSUE_0002_CAR.y, where.get("road"), where.get("chainage", 0.0), where.get("offset", 0.0), deck_here - terrain, ISSUE_0002_UNDER, under_crossing.get("loop_height", 0.0) - under_crossing.get("height", 0.0), ISSUE_0002_PROBE_M, deck_here - beside_left, deck_here - beside_right, ISSUE_0002_DROP_MIN_M], "issue-0002: over %s (%s), the crossing %s, deck %.2f terrain %.2f beside %.2f / %.2f" % [where.get("road"), where, under_crossing, deck_here, terrain, beside_left, beside_right])


# =============================================================================
#  THE HILL STEP, THE BANK, THE BODY
# =============================================================================

## §2.3 made executable: at the loop's steepest honest sample the world
## profile's gradient is non-zero (the hill step carries gravity's share)
## and the pad's flat profile's at the same world point is exactly
## Vector2.ZERO (nothing added: every certified run's physics is the bit it
## was).
func _check_hill_step(profile: WorldRoadProfile) -> void:
	var world := profile.ramp_gradient(_steepest.x, _steepest.z)
	var flat := RoadProfile.flat().ramp_gradient(_steepest.x, _steepest.z)
	_ok(world != Vector2.ZERO and world.length() > RoadProfile.MAX_SLOPE and flat == Vector2.ZERO, "the hill step: at the loop's steepest honest sample (%s chainage %.0f, (%.1f, %.1f), %.1f %% along the road) WorldRoadProfile.ramp_gradient is (%.4f, %.4f), %.1f %%, past the pad's MAX_SLOPE %.1f %%; RoadProfile.flat().ramp_gradient at the same point is exactly %s" % [_steepest.id, _steepest.s, _steepest.x, _steepest.z, 100.0 * _steepest.slope, world.x, world.y, 100.0 * world.length(), 100.0 * RoadProfile.MAX_SLOPE, flat], "world %s, flat %s at %s" % [world, flat, _steepest])


## The Karussell's bank through ramp_gradient: the gradient's component to
## the right of travel is the crossfall, +0.30 (rising to the right, the
## outside of the bend), the sign the drape's.
func _check_bank(profile: WorldRoadProfile) -> void:
	var geometry := _geometry_of(KARUSSELL_SEGMENT)
	var at := _point_on(geometry.xs, geometry.zs, geometry.chain, KARUSSELL_CHAINAGE_M)
	var travel := _direction_on(geometry.xs, geometry.zs, geometry.chain, KARUSSELL_CHAINAGE_M)
	var right := Vector2(-travel.y, travel.x)
	var gradient := profile.ramp_gradient(at[0], at[1])
	var across := gradient.dot(right)
	var along := gradient.dot(travel)
	var crossfall := 0.0
	for raw: Dictionary in _drape.segments:
		if raw.id == KARUSSELL_SEGMENT:
			crossfall = raw.crossfall[0]
	_ok(signf(across) == signf(crossfall) and absf(across - KARUSSELL_BANK) <= BANK_TOLERANCE, "the Karussell's bank via ramp_gradient at %s chainage %.0f: %.4f across to the right of travel (the drape's crossfall %+.2f: the bank rises to the right), %.4f along; the 30 %% bank" % [KARUSSELL_SEGMENT, KARUSSELL_CHAINAGE_M, across, crossfall, along], "the gradient across is %.4f, the crossfall %.2f" % [across, crossfall])


## Body attitude, measured not judged (open question 4): the car stood on
## the bank and on the steepest stretch, held on the brakes, its pitch and
## roll against the small-angle model (car.gd:87-90: pitch and roll are
## small angles of the body on an upright CharacterBody3D; the springs read
## the four wheel heights, so the body's angle is the slope's tangent) and
## against the true angle; sanity bounds only.
func _check_attitude(car: ArcadeCar, profile: WorldRoadProfile) -> void:
	var karussell := _geometry_of(KARUSSELL_SEGMENT)
	var bank_at := _point_on(karussell.xs, karussell.zs, karussell.chain, KARUSSELL_CHAINAGE_M)
	var bank_dir := _direction_on(karussell.xs, karussell.zs, karussell.chain, KARUSSELL_CHAINAGE_M)
	await _stand(car, bank_at[0], bank_at[1], bank_dir)
	_report_attitude(car, profile, "on the Karussell bank (%s chainage %.0f)" % [KARUSSELL_SEGMENT, KARUSSELL_CHAINAGE_M])
	var steep := _geometry_of(_steepest.id)
	var steep_dir := _direction_on(steep.xs, steep.zs, steep.chain, _steepest.s)
	await _stand(car, _steepest.x, _steepest.z, steep_dir)
	_report_attitude(car, profile, "on the steepest stretch along the road (%s chainage %.0f, %.1f %% along)" % [_steepest.id, _steepest.s, 100.0 * _steepest.slope])


## Puts the car at (x, z) heading along `direction`, on its springs, and
## holds it on the brake and the handbrake for HOLD_FRAMES.
func _stand(car: ArcadeCar, x: float, z: float, direction: Vector2) -> void:
	car.reset_to(Transform3D(Basis(Vector3.UP, atan2(-direction.x, -direction.y)), Vector3(x, 0.0, z)))
	car.set_driver_input(0.0, 1.0, 0.0, true)
	await _step(HOLD_FRAMES)


func _report_attitude(car: ArcadeCar, profile: WorldRoadProfile, where: String) -> void:
	var forward := -car.global_basis.z
	var right := car.global_basis.x
	var gradient := profile.ramp_gradient(car.global_position.x, car.global_position.z)
	var along := gradient.x * forward.x + gradient.y * forward.z
	var across := gradient.x * right.x + gradient.y * right.z
	var pitch_deg := rad_to_deg(car.body_pitch)
	var roll_deg := rad_to_deg(car.body_roll)
	# Nose up when the road ahead rises: the gradient's share along the nose.
	var true_pitch_deg := rad_to_deg(atan(along))
	var true_roll_deg := rad_to_deg(atan(across))
	var over := car.global_position.y - profile.sample_height(car.global_position.x, car.global_position.z)
	var supported := true
	for held: bool in car.wheel_supported:
		supported = supported and held
	_ok(absf(pitch_deg) < ATTITUDE_CEILING_DEG and absf(roll_deg) < ATTITUDE_CEILING_DEG and over > RIDE_HEIGHT_MIN_M and over < RIDE_HEIGHT_MAX_M and supported and not car.is_airborne and absf(car.forward_speed) < 0.5, "body attitude %s: pitch %.4f rad (%.2f°, the slope along %.1f %% whose true angle is %.2f°), roll %.4f rad (%.2f°, the slope across %.1f %% whose true angle is %.2f°); the small-angle gap %.2f° / %.2f°; the body %.3f m over the road, four wheels carried, speed %.2f m/s (measured; sanity bounds %.0f°)" % [where, car.body_pitch, pitch_deg, 100.0 * along, true_pitch_deg, car.body_roll, roll_deg, 100.0 * across, true_roll_deg, pitch_deg - true_pitch_deg, roll_deg - true_roll_deg, over, car.forward_speed, ATTITUDE_CEILING_DEG], "attitude %s: pitch %.2f° roll %.2f° over %.3f m supported %s airborne %s speed %.2f" % [where, pitch_deg, roll_deg, over, supported, car.is_airborne, car.forward_speed])


# =============================================================================
#  THE DRIVE
# =============================================================================

## The loop's centreline from Döttinger Höhe onward as one 64-bit
## polyline, and a pure-pursuit driver on it fed through set_driver_input.
class LoopDriver:
	extends RefCounted
	var xs := PackedFloat64Array()
	var zs := PackedFloat64Array()
	var chain := PackedFloat64Array()
	## The paved half width [m] of the loop segment each point belongs to;
	## a chord's is its end point's (the point shared by two segments is
	## the first's, the chord leading into the next segment the next's).
	var half_widths := PackedFloat64Array()
	var car: ArcadeCar
	var cursor := 0
	var progress := 0.0
	var offset := 0.0
	var worst_offset := 0.0
	var worst_offset_at := 0.0
	var target_speed := 0.0

	func add_point(x: float, z: float, half_width: float) -> void:
		if xs.is_empty():
			chain.append(0.0)
		else:
			var last := xs.size() - 1
			var d := sqrt((x - xs[last]) * (x - xs[last]) + (z - zs[last]) * (z - zs[last]))
			if d <= 1e-6:
				return
			chain.append(chain[last] + d)
		xs.append(x)
		zs.append(z)
		half_widths.append(half_width)

	## How far inside the loop's paved width a world point is [m]: the
	## nearest loop chord around the cursor (the car's own chord, the ones
	## behind and ahead of it that a 2.6 m wheelbase can reach), that
	## chord's half width less the point's perpendicular distance from it;
	## negative outside the platform. The loop's own geometry and width,
	## not the single-valued field's answer (which at a junction is the
	## side road's).
	func margin_of(x: float, z: float) -> float:
		var best := INF
		var best_c := cursor
		for c: int in range(maxi(cursor - 2, 0), mini(cursor + 6, xs.size() - 1)):
			var dx := xs[c + 1] - xs[c]
			var dz := zs[c + 1] - zs[c]
			var len2 := dx * dx + dz * dz
			var t := clampf(((x - xs[c]) * dx + (z - zs[c]) * dz) / len2, 0.0, 1.0)
			var px := xs[c] + t * dx
			var pz := zs[c] + t * dz
			var d := (x - px) * (x - px) + (z - pz) * (z - pz)
			if d < best:
				best = d
				best_c = c
		return half_widths[best_c + 1] - sqrt(best)

	func length() -> float:
		return chain[chain.size() - 1]

	func point_at(s: float) -> Vector2:
		var t := clampf(s, 0.0, length())
		for i: int in range(1, chain.size()):
			if chain[i] >= t:
				var span := chain[i] - chain[i - 1]
				var u := 0.0 if span <= 0.0 else (t - chain[i - 1]) / span
				return Vector2(xs[i - 1] + u * (xs[i] - xs[i - 1]), zs[i - 1] + u * (zs[i] - zs[i - 1]))
		return Vector2(xs[xs.size() - 1], zs[zs.size() - 1])

	func heading_at(s: float) -> float:
		var t := clampf(s, 0.0, length())
		for i: int in range(1, chain.size()):
			if chain[i] >= t and chain[i] > chain[i - 1]:
				return atan2(zs[i] - zs[i - 1], xs[i] - xs[i - 1])
		return atan2(zs[zs.size() - 1] - zs[zs.size() - 2], xs[xs.size() - 1] - xs[xs.size() - 2])

	## Where the car is along the path (the nearest chord from the cursor
	## on) and how far to the right of it.
	func locate() -> void:
		var x := car.global_position.x
		var z := car.global_position.z
		var best := INF
		var best_c := cursor
		var best_t := 0.0
		for c: int in range(cursor, mini(cursor + 4, xs.size() - 1)):
			var dx := xs[c + 1] - xs[c]
			var dz := zs[c + 1] - zs[c]
			var len2 := dx * dx + dz * dz
			var t := clampf(((x - xs[c]) * dx + (z - zs[c]) * dz) / len2, 0.0, 1.0)
			var px := xs[c] + t * dx
			var pz := zs[c] + t * dz
			var d := (x - px) * (x - px) + (z - pz) * (z - pz)
			if d < best:
				best = d
				best_c = c
				best_t = t
		cursor = best_c
		var dx := xs[cursor + 1] - xs[cursor]
		var dz := zs[cursor + 1] - zs[cursor]
		var span := sqrt(dx * dx + dz * dz)
		progress = chain[cursor] + best_t * span
		# Right of travel in the x-east / z-south frame: (-tz, tx).
		offset = ((x - xs[cursor]) * (-dz) + (z - zs[cursor]) * dx) / span
		if absf(offset) > absf(worst_offset):
			worst_offset = offset
			worst_offset_at = progress

	## One tick of driving: the wheel toward the lookahead point, the
	## pedals toward the speed the curvature ahead allows.
	func tick(cruise: float, lateral_budget: float, lookahead_s: float, lookahead_min: float, lookahead_max: float, preview_m: float, gain: float) -> void:
		locate()
		var speed := car.forward_speed
		var ahead := clampf(speed * lookahead_s, lookahead_min, lookahead_max)
		var target := point_at(progress + ahead)
		var forward := -car.global_basis.z
		var right := car.global_basis.x
		var to := Vector3(target.x - car.global_position.x, 0.0, target.y - car.global_position.z)
		var alpha := atan2(-to.dot(right), to.dot(forward))
		var distance := maxf(to.length(), 1.0)
		var wheel := atan(2.0 * 2.0 * ArcadeCar.AXLE_DISTANCE * sin(alpha) / distance)
		var steer := clampf(wheel / ArcadeCar.MAX_STEER_LOCK, -1.0, 1.0)
		var turn := absf(angle_difference(heading_at(progress + 5.0), heading_at(progress + preview_m)))
		var curvature := turn / (preview_m - 5.0)
		target_speed = minf(cruise, sqrt(lateral_budget / maxf(curvature, 1e-4)))
		var throttle := clampf((target_speed - speed) * gain, 0.0, 1.0)
		var brake := clampf((speed - target_speed - 0.5) * gain, 0.0, 1.0)
		car.set_driver_input(throttle, brake, steer)


## The path from the drive's start segment along the loop's chain.
func _loop_path(car: ArcadeCar) -> LoopDriver:
	var driver := LoopDriver.new()
	driver.car = car
	var start := _loop.segments.find(DRIVE_START_SEGMENT)
	var k := start
	while driver.xs.is_empty() or driver.length() < PATH_LENGTH_M:
		var id: String = _loop.segments[k % _loop.segments.size()]
		var half_width: float = _segments[id].width_m * 0.5
		for point: Array in _raw_points[id]:
			driver.add_point(point[0], point[1], half_width)
		k += 1
	return driver


## The 2 km drive; {odometer, position} at its end. With `report`, the ok
## lines.
func _drive(car: ArcadeCar, road: RoadBuilder, report: bool) -> Dictionary:
	var profile := road.profile
	var floor_body: StaticBody3D = road.get_node("Floor")
	var driver := _loop_path(car)
	var start_point := driver.point_at(DRIVE_START_CHAINAGE_M)
	var heading := driver.heading_at(DRIVE_START_CHAINAGE_M)
	var direction := Vector2(cos(heading), sin(heading))
	car.reset_to(Transform3D(Basis(Vector3.UP, atan2(-direction.x, -direction.y)), Vector3(start_point.x, 0.0, start_point.y)))
	await _step(SETTLE_FRAMES)
	var ticks := 0
	var limit := int(DRIVE_TIME_LIMIT_S * Engine.physics_ticks_per_second)
	var stats_from := int(SPEED_STATS_FROM_S * Engine.physics_ticks_per_second)
	var speed_min := INF
	var speed_max := 0.0
	var speed_sum := 0.0
	var speed_ticks := 0
	var airborne_ticks := 0
	var pitch_max := 0.0
	var roll_max := 0.0
	var half_width: float = _segments[DRIVE_START_SEGMENT].width_m * 0.5
	# Every tick: all four wheels carried (car.wheel_supported, the
	# corner check's own flags; is_airborne clears when ANY wheel carries)
	# and every wheel's contact point - global_transform ×
	# WHEEL_CONTACT_POINTS, the seam car.gd's _road_height_under_wheel
	# reads the road through, with the car's yaw, axles and track in it -
	# inside the nearest loop chord's own paved half width.
	var unsupported_ticks := 0
	var unsupported_first := -1
	var wheel_margin := INF
	var wheel_margin_at := 0.0
	var wheel_margin_which := -1
	var wheel_readings := 0
	var wheel_non_finite := 0
	# The follower floor: its top is the corrected field's height at its
	# own place every tick (the same profile, no third height source), and
	# from one tick to the next it steps by no more than the field itself
	# does over the car's way (the grade times the way, plus the field's
	# rounding).
	var floor_off_field := 0.0
	var floor_step_worst := 0.0
	var floor_step_over := 0
	var floor_last := floor_body.position
	# The crossings the drive passes: the field under the car the loop's
	# own there and every wheel carried.
	var passes := {}
	for crossing: Dictionary in road.crossings:
		var along := _along_lap(crossing.loop, crossing.loop_chainage)
		if along > DRIVE_START_CHAINAGE_M and along < DRIVE_START_CHAINAGE_M + DRIVE_DISTANCE_M:
			passes[crossing.id] = {"along": along, "ticks": 0, "clean": true, "roads": {}, "margin": INF, "unsupported": 0}
	while ticks < limit:
		driver.tick(CRUISE_SPEED, LATERAL_ACCEL_BUDGET, LOOKAHEAD_S, LOOKAHEAD_MIN_M, LOOKAHEAD_MAX_M, CURVATURE_PREVIEW_M, PEDAL_GAIN)
		if driver.progress >= DRIVE_START_CHAINAGE_M + DRIVE_DISTANCE_M:
			break
		await physics_frame
		ticks += 1
		var all_supported := true
		for held: bool in car.wheel_supported:
			all_supported = all_supported and held
		if not all_supported:
			unsupported_ticks += 1
			if unsupported_first < 0:
				unsupported_first = ticks
		var tick_margin := INF
		for i: int in ArcadeCar.WHEEL_CONTACT_POINTS.size():
			var contact: Vector3 = car.global_transform * ArcadeCar.WHEEL_CONTACT_POINTS[i]
			var margin := driver.margin_of(contact.x, contact.z)
			wheel_readings += 1
			if not is_finite(margin):
				wheel_non_finite += 1
				continue
			tick_margin = minf(tick_margin, margin)
			if margin < wheel_margin:
				wheel_margin = margin
				wheel_margin_at = driver.progress
				wheel_margin_which = i
		for id: String in passes:
			var passing: Dictionary = passes[id]
			if absf(driver.progress - passing.along) <= CROSSING_PASS_M:
				passing.ticks += 1
				var under: String = profile.describe(car.global_position.x, car.global_position.z).get("road", "")
				passing.roads[under] = true
				passing.margin = minf(passing.margin, tick_margin)
				if not all_supported:
					passing.unsupported += 1
				passing.clean = passing.clean and _loop.segments.has(under) and all_supported and not car.is_airborne and tick_margin >= 0.0
		var placed := floor_body.position
		floor_off_field = maxf(floor_off_field, absf(placed.y - profile.sample_height(placed.x, placed.z)))
		var way := Vector2(placed.x - floor_last.x, placed.z - floor_last.z).length()
		var step := absf(placed.y - floor_last.y)
		floor_step_worst = maxf(floor_step_worst, step)
		if step > profile.ramp_gradient(floor_last.x, floor_last.z).length() * way + FLOOR_STEP_SLACK_M:
			floor_step_over += 1
		floor_last = placed
		if ticks >= stats_from:
			speed_min = minf(speed_min, car.forward_speed)
			speed_max = maxf(speed_max, car.forward_speed)
			speed_sum += car.forward_speed
			speed_ticks += 1
		if car.is_airborne:
			airborne_ticks += 1
		pitch_max = maxf(pitch_max, absf(car.body_pitch))
		roll_max = maxf(roll_max, absf(car.body_roll))
	car.set_driver_input(0.0, 1.0, 0.0)
	var out := {"odometer": car.odometer_m, "position": car.global_position, "ticks": ticks}
	if report:
		var seconds := float(ticks) / Engine.physics_ticks_per_second
		var on_road: bool = absf(driver.worst_offset) + ArcadeCar.HALF_TRACK <= half_width
		_ok(driver.progress >= DRIVE_START_CHAINAGE_M + DRIVE_DISTANCE_M, "the scripted driver covered %.0f m of the loop from %s chainage %.0f in %.1f s (%d ticks), the time limit %.0f s" % [driver.progress - DRIVE_START_CHAINAGE_M, DRIVE_START_SEGMENT, DRIVE_START_CHAINAGE_M, seconds, ticks, DRIVE_TIME_LIMIT_S], "the drive reached %.0f m in %d ticks" % [driver.progress - DRIVE_START_CHAINAGE_M, ticks])
		_ok(on_road, "the car's centre stayed on the road: its worst lateral offset from the loop's centreline is %+.3f m at %.0f m along (the outer wheel by track alone %.3f m from the centreline, the start road's paved half width %.2f m; the estimate - the wheels themselves are measured next)" % [driver.worst_offset, driver.worst_offset_at, absf(driver.worst_offset) + ArcadeCar.HALF_TRACK, half_width], "the car strayed %.3f m from the centreline at %.0f m: a wheel %.3f m out on a %.2f m half width" % [driver.worst_offset, driver.worst_offset_at, absf(driver.worst_offset) + ArcadeCar.HALF_TRACK, half_width])
		_ok(ticks > 0 and wheel_readings == 4 * ticks and wheel_non_finite == 0 and wheel_margin >= 0.0, "no wheel left the paved width: every tick each of the four contact points (global_transform × WHEEL_CONTACT_POINTS, car.gd's own seam: the yaw, the axles and the track in it) lay inside the nearest loop chord's own paved half width - %d readings over %d ticks, the smallest margin %.3f m inside the edge at %.0f m along (wheel %d)" % [wheel_readings, ticks, wheel_margin, wheel_margin_at, wheel_margin_which], "a wheel (%d) was %.3f m outside the paved width at %.0f m along; %d readings over %d ticks, %d not finite" % [wheel_margin_which, -wheel_margin, wheel_margin_at, wheel_readings, ticks, wheel_non_finite])
		_ok(ticks > 0 and unsupported_ticks == 0 and airborne_ticks == 0, "all four wheels carried every tick of the drive (car.wheel_supported, the corner check's own flags: %d of %d ticks with a wheel unsupported; is_airborne clears when any one wheel carries, %d airborne ticks)" % [unsupported_ticks, ticks, airborne_ticks], "%d of %d ticks with a wheel unsupported (the first at tick %d), %d airborne ticks" % [unsupported_ticks, ticks, unsupported_first, airborne_ticks])
		_ok(speed_ticks > 0 and speed_min > 0.0, "speed after the first %.0f s: %.1f-%.1f m/s, mean %.1f m/s (%.0f km/h; the cruise %.0f m/s eased for the bends), %d airborne ticks, the body's pitch up to %.2f° and roll up to %.2f° on the way" % [SPEED_STATS_FROM_S, speed_min, speed_max, speed_sum / maxi(speed_ticks, 1), 3.6 * speed_sum / maxi(speed_ticks, 1), CRUISE_SPEED, airborne_ticks, rad_to_deg(pitch_max), rad_to_deg(roll_max)], "speeds %.1f-%.1f" % [speed_min, speed_max])
		_ok(car.odometer_m > DRIVE_DISTANCE_M * 0.99, "the odometer counted %.1f m for the drive" % car.odometer_m)
		var pass_ids := passes.keys()
		pass_ids.sort()
		_ok(passes.size() == 2 and passes.has("377340334-0") and passes.has("29898554-0"), "the 2 km drive passes two of the ten crossings (the tunnel 377340334-0 under the Döttinger Höhe straight and the track bridge 29898554-0 over Antoniusbuche), both within the drive's reach: %s" % [", ".join(pass_ids)], "the passes are %s" % [pass_ids])
		for id: String in pass_ids:
			var passing: Dictionary = passes[id]
			_ok(passing.ticks > 0 and passing.clean, "the drive passed the crossing of %s at %.0f m along: over %d ticks within %.0f m of it the field under the car was the loop's own (%s), all four wheels were carried every tick (wheel_supported; %d ticks with one unsupported) and every wheel's contact point stayed inside the loop's paved width (the smallest margin %.3f m) - was a wall of +2.88 m at 1 901 m that stopped the car dead, a hole of -2.76 m at 888 m" % [id, passing.along, passing.ticks, CROSSING_PASS_M, ", ".join(passing.roads.keys()), passing.unsupported, passing.margin], "at %s (%.0f m): %d ticks, clean %s, roads %s, %d unsupported, margin %.3f" % [id, passing.along, passing.ticks, passing.clean, passing.roads.keys(), passing.unsupported, passing.margin])
		_ok(floor_off_field <= FLOOR_FIELD_TOLERANCE_M and floor_step_over == 0, "the follower floor over %d ticks: its top is the corrected profile's height at its own place every tick (worst %.4f mm off: the same field the mesh and the car read), and it never steps more than the field does over the car's way (worst step %.3f m per tick)" % [ticks, 1000.0 * floor_off_field, floor_step_worst], "the floor was %.4f m off the field, %d steps beyond the field's own (worst %.3f m)" % [floor_off_field, floor_step_over, floor_step_worst])
	return out
