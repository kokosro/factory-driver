extends SceneTree
## Headless reset test: ROAD-SIDE RESET MEMORY (ArcadeCar.reset_car,
## _record_road_pose, last_road_pose; the user's complaint on the Ring,
## 2026-09-23: "R resets the car back to the pit spawn - unacceptable 5 km
## in"). Run via tests/run_tests.sh, or:
##
##   godot --headless --path . --import
##   godot --headless --fixed-fps 60 --path . --script res://tests/reset_test.gd
##
## THE PAD (main.tscn): the flag is off and the pad's profile has no road
## query, so nothing is ever recorded there; R at the spawn, R after a
## drive - through the car's own reset_car and through a tap of the
## reset_car action - puts the car back on the start line exactly as
## before (was and is: the handling, mission, licence and smoke tests
## depend on it). THE SYNTHETIC ROAD: a WorldRoadProfile built in memory
## (from_data, the way tests/world_profile_test.gd builds its fixture: one
## straight 7 m primary along +x over a level plane at 400 m) handed to the
## pad's car with the flag on: a fresh car holds no pose; stood on the
## road it records its x, z and heading - the recorded transform yaw-only
## about Vector3.UP with origin.y exactly 0, not the car's own transform
## (reset_to stands the car origin.y over the road: the world height in
## it would leave the car floating); stood 30 m beside the road on the
## plane, all four wheels supported on the terrain, it records nothing
## (describe's on_road gates it); R from the field lands on the road at
## the recorded pose, heading along it. THE RING (eifel_ring.tscn): the
## flag is on (RoadBuilder set it beside the profile) and nothing is
## recorded before the first tick; R with no pose recorded lands on the
## spawn (the fallback branch, the codex cross-review's F3 fence); the
## settled car at the pit records the pit and the first R lands on the
## spawn; the scripted follower
## (tests/ring_drive_test.gd's LoopDriver, the proven idiom) drives 400 m
## from Döttinger Höhe with all four wheels supported every tick while the
## recorded pose follows the car within one tick's way (FOLLOW_M, a
## measured 0.292 m at the cruise; was asserted at 1.0 m, several ticks' way
## - the codex cross-review's F2); stopped, the recorded pose is the car's
## own within LAND_M (a centimetre; the printed measurements read finer);
## placed in the field
## beside the road the pose stays; a tap of R puts the car back at it -
## the position, the heading, on the road, at rest, in 1st, automatic,
## the fuel the drive left (no refuel), not the spawn, not the drive's
## start, the collision floor following the reset the same tick (the codex
## cross-review's F1 fence) - and it drives on from there on four wheels; a second scene
## instanced fresh holds no pose before its first tick and its first R
## lands on the spawn (per-session memory). Exits 0 on success, 1 on any
## failed check.

const MAIN_SCENE := "res://scenes/main.tscn"
const RING_SCENE := "res://scenes/eifel_ring.tscn"

## The ring drive test's follower and its drive constants: the one scripted
## driver of the loop, reused rather than copied.
const RingDrive := preload("res://tests/ring_drive_test.gd")

## Physics frames to let the car settle after a load or a reset.
const SETTLE_FRAMES := 20

## The pad drive: full throttle this many ticks, then this many at rest.
const PAD_DRIVE_FRAMES := 90
const PAD_COAST_FRAMES := 30

## The Ring drive [m] and the ticks to stop after it, and to drive on after
## the reset.
const DRIVE_DISTANCE_M := 400.0
const STOP_FRAMES := 240
const DRIVE_ON_FRAMES := 90
const DRIVE_TIME_LIMIT_S := 60.0

## How far the car is put beside the road for the off-road checks [m]: on
## the synthetic road this far to the right; on the Ring the first of these
## (a side, a distance) whose spot the profile's describe reads off any
## road - 30 m to the right of the stopped car at 400 m in is on the side
## road 159029020-0 (measured), so the spot is probed, not assumed.
const BESIDE_M := 30.0
const RING_BESIDE: Array[Vector2] = [Vector2(1.0, 30.0), Vector2(-1.0, 30.0), Vector2(1.0, 60.0), Vector2(-1.0, 60.0), Vector2(1.0, 100.0), Vector2(-1.0, 100.0)]

## After the tap of R the car has ticked this many times since the reset
## (the press's tick resets, then the tap's own frames): on the Ring's grade
## a car at rest rolls, so "at rest" is read as under this speed [m/s].
const ROLL_AFTER_TAP_MPS := 0.5

## What the idling engine burns over the tap's ticks is under this [l]: the
## fuel after R is what it was at the tap less that, never the full tank.
const IDLE_BURN_TAP_L := 0.001

## The recorded pose follows the car within one tick's way at the cruise
## (18 m/s / 60 = 0.3 m, measured worst 0.292 m) and within this heading
## [rad]. was 1.0 m - several ticks' way, not the claim (the codex
## cross-review's F2, 2026-09-24).
const FOLLOW_M := 0.35
const FOLLOW_RAD := 0.05

## A restored position is the recorded one within this [m] and this [rad].
const LAND_M := 0.01
const LAND_RAD := 0.0001

## The body over the road after a reset [m] (ring_drive_test's bounds).
const RIDE_HEIGHT_MIN_M := -0.2
const RIDE_HEIGHT_MAX_M := 1.5

## The synthetic road: a 7 m primary along +x at z = ROAD_Z from ROAD_X0 to
## ROAD_X1 over a level plane at PLANE_M, the lattice at 10 m over a 2 km
## box (the drape's own rules, through drape_segment).
const PLANE_M := 400.0
const ROAD_Z := -500.0
const ROAD_X0 := 500.0
const ROAD_X1 := 1500.0
const FIXTURE_SIZE_M := 2000.0
const LATTICE_STEP_M := 10.0
const PINNED_OSM_BASE := "2026-09-22T08:45:51Z"

var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	print("-- the pad")
	await _check_pad()
	print("-- the Ring")
	await _check_ring()
	_finish()


# =============================================================================
#  The pad: spawn-reset, as before
# =============================================================================

func _check_pad() -> void:
	var packed: PackedScene = load(MAIN_SCENE)
	if not _check(packed != null, "main scene loads"):
		return
	var scene := packed.instantiate()
	root.add_child(scene)
	await _step(SETTLE_FRAMES)
	var car := scene.get_node_or_null("Car") as ArcadeCar
	if not _check(car != null, "the pad's Car exists"):
		return
	var spawn := car.get_spawn_transform()
	_check(not car.reset_to_last_pose and not car.road_profile is WorldRoadProfile and not car.last_road_pose_recorded, "the pad's car keeps the start line: reset_to_last_pose off, its road_profile a plain RoadProfile (no road query), no pose recorded after %d ticks" % SETTLE_FRAMES)

	# R at the spawn, before any drive: the spawn.
	await _tap("reset_car")
	_check(_at(car, spawn) and car.velocity == Vector3.ZERO, "the pad: R at the spawn before any drive puts the car on the start line (%.3f m off, heading %.4f rad off)" % [_xz_off(car, spawn), _yaw_off(car, spawn)])

	# Driven away, the car's own method: the spawn.
	var driven := await _pad_drive(car)
	_check(driven > 5.0 and not car.last_road_pose_recorded, "the pad: driven %.1f m from the start line, nothing recorded (the pad never records)" % driven)
	car.reset_car()
	await _step(2)
	_check(_at(car, spawn) and car.forward_speed == 0.0, "the pad: reset_car() after the drive is reset_to_spawn(): the start line (%.3f m off, heading %.4f rad off)" % [_xz_off(car, spawn), _yaw_off(car, spawn)])

	# Driven away, the key: the spawn (the smoke test's tap, unchanged).
	driven = await _pad_drive(car)
	await _tap("reset_car")
	_check(driven > 5.0 and _at(car, spawn) and car.forward_speed == 0.0, "the pad: a tap of reset_car after a %.1f m drive puts the car on the start line (%.3f m off) - was and is" % [driven, _xz_off(car, spawn)])

	# The synthetic road reuses this scene's car: it needs a tree and a tick,
	# and the pad's floor is 400 m below the plane, never met.
	print("-- the synthetic road")
	await _check_synthetic_on(car, scene)
	scene.queue_free()
	await _step(2)


## Full throttle, then rest; how far from the spawn the car got [m].
func _pad_drive(car: ArcadeCar) -> float:
	Input.action_press("accelerate")
	await _step(PAD_DRIVE_FRAMES)
	Input.action_release("accelerate")
	await _step(PAD_COAST_FRAMES)
	return _xz_off(car, car.get_spawn_transform())


# =============================================================================
#  The synthetic road: the recording's gates, off the Ring's data
# =============================================================================

func _check_synthetic_on(car: ArcadeCar, scene: Node) -> void:
	var skeleton := _fixture_skeleton()
	var drape := _fixture_drape(skeleton)
	var errors := WorldRoadProfile.validate(drape, skeleton)
	if not _check(errors.is_empty(), "the synthetic drape passes validate() (%s)" % [errors]):
		return
	var profile := WorldRoadProfile.from_data(skeleton, drape)
	var spawn := car.get_spawn_transform()
	car.road_profile = profile
	car.reset_to_last_pose = true
	_check(not car.last_road_pose_recorded, "a car handed a world profile and the flag holds no pose until it is stood on a road")

	# On the road, heading +x: the pose is recorded, yaw-only, origin.y 0.
	var on_road := _pose(700.0, ROAD_Z, Vector2(1.0, 0.0))
	car.reset_to(on_road)
	await _step(SETTLE_FRAMES)
	var recorded := car.last_road_pose
	var supported := _all_supported(car)
	_check(car.last_road_pose_recorded and supported and profile.describe(car.global_position.x, car.global_position.z).get("on_road", false), "stood on the synthetic road (x %.0f, z %.0f, heading +x) with all four wheels supported the car records a pose within %d ticks" % [car.global_position.x, car.global_position.z, SETTLE_FRAMES])
	_check(recorded.origin.y == 0.0 and _xz_off(car, recorded) < LAND_M and _yaw_off(car, recorded) < LAND_RAD and recorded.basis.is_equal_approx(Basis(Vector3.UP, atan2(-1.0, 0.0))) and absf(car.global_position.y - PLANE_M) < RIDE_HEIGHT_MAX_M, "the recorded pose is x, z and the heading only: origin.y exactly 0 (the car's own origin is %.3f m from the plane's %.0f m), the basis yaw-only about Vector3.UP for a nose along +x (%.4f rad off), the origin the car's x, z (%.4f m off)" % [car.global_position.y - PLANE_M, PLANE_M, _yaw_off(car, recorded), _xz_off(car, recorded)])

	# Beside the road, on the plane: supported on the terrain, not recorded.
	car.reset_to(_pose(700.0, ROAD_Z + BESIDE_M, Vector2(1.0, 0.0)))
	await _step(SETTLE_FRAMES)
	var beside := profile.describe(car.global_position.x, car.global_position.z)
	var field_supported := _all_supported(car)
	_check(field_supported and not beside.get("on_road", false) and car.last_road_pose == recorded, "stood %.0f m beside the road on the plane - all four wheels supported on the terrain, describe's on_road false (no road within reach: '%s') - the recorded pose stays the on-road one over %d ticks (the on-road gate, not the wheels, holds the memory)" % [BESIDE_M, beside.get("road", ""), SETTLE_FRAMES])

	# R from the field: the road, at the recorded pose.
	await _tap("reset_car")
	_check(_at(car, recorded) and _at(car, on_road) and not _at(car, spawn) and car.velocity == Vector3.ZERO and _all_supported(car), "R from the field lands on the synthetic road at the recorded pose (%.4f m, %.5f rad off), not the pad's start line, at rest on four wheels" % [_xz_off(car, recorded), _yaw_off(car, recorded)])

	# Back to the pad's own profile for the scene's teardown.
	car.reset_to_last_pose = false
	car.road_profile = scene.get_node("TestPad").road_profile
	car.reset_to_spawn()
	await _step(2)


## The fixture's skeleton: one primary straight along +x.
func _fixture_skeleton() -> Dictionary:
	return {
		"snapshot": {"osm_base": PINNED_OSM_BASE, "bbox": SkeletonLoader.BBOX, "query_sha": "0".repeat(64), "pipeline_version": 1},
		"origin": {"epsg": SkeletonLoader.EPSG, "e0": SkeletonLoader.E0, "n0": SkeletonLoader.N0},
		"segments": [
			{"id": "1-0", "osm_way": 1, "class": "primary", "width_m": 7.0, "width_source": "class", "points": [[ROAD_X0, ROAD_Z], [ROAD_X1, ROAD_Z]]},
		],
		"junctions": [],
		"loops": [],
	}


## The level plane, null half a cell outside the box (the mosaic's rule).
func _fixture_sample(x: float, z: float) -> Variant:
	if x < 0.5 or x > FIXTURE_SIZE_M - 0.5 or z < -FIXTURE_SIZE_M + 0.5 or z > -0.5:
		return null
	return PLANE_M


## The fixture's drape: the plane's lattice at 10 m, the segment through
## the mirrored drape rules (world_profile_test.gd's fixture, one road).
func _fixture_drape(skeleton: Dictionary) -> Dictionary:
	var cols := int(FIXTURE_SIZE_M / LATTICE_STEP_M) + 1
	var heights: Array = []
	heights.resize(cols * cols)
	for i: int in cols * cols:
		heights[i] = PLANE_M
	var segments: Array = []
	var typed := SkeletonLoader.segments_of(skeleton)
	for raw: Dictionary in skeleton.segments:
		var record: Variant = WorldRoadProfile.drape_segment(typed[raw.id], raw.points, _fixture_sample)
		if record != null:
			segments.append(record)
	return {
		"snapshot": {"osm_base": PINNED_OSM_BASE, "bbox": SkeletonLoader.BBOX, "query_sha": "0".repeat(64), "skeleton_pipeline_version": 1, "skeleton_sha256": "0".repeat(64), "pipeline_version": 1},
		"origin": {"epsg": SkeletonLoader.EPSG, "e0": SkeletonLoader.E0, "n0": SkeletonLoader.N0},
		"dem": {"source": "synthetic level plane", "epsg": 25832, "vertical_datum": "DHHN2016", "grid_m": 1.0, "tiles": [{"name": "dgm1_32_352_5577_1_rp_2025.tif", "sha256": "0".repeat(64), "verified": true}]},
		"coverage": {"x_min": 0.0, "x_max": FIXTURE_SIZE_M, "z_min": -FIXTURE_SIZE_M, "z_max": 0.0},
		"rules": WorldRoadProfile.RULES.duplicate(),
		"lattice": {"step_m": LATTICE_STEP_M, "x0": 0.0, "z0": -FIXTURE_SIZE_M, "cols": cols, "rows": cols, "heights": heights},
		"segments": segments,
	}


# =============================================================================
#  The Ring
# =============================================================================

func _check_ring() -> void:
	var packed: PackedScene = load(RING_SCENE)
	if not _check(packed != null, "ring scene loads"):
		return
	var scene := packed.instantiate()
	root.add_child(scene)
	var car := scene.get_node_or_null("Car") as ArcadeCar
	var road := scene.get_node_or_null("Road") as RoadBuilder
	if not _check(car != null and road != null and road.profile is WorldRoadProfile, "the Ring's Car and Road exist, the road built"):
		return
	# Before the first tick: the flag is the world's, the memory empty.
	_check(car.reset_to_last_pose and car.road_profile == road.profile and not car.last_road_pose_recorded, "the Ring: RoadBuilder set reset_to_last_pose beside the car's WorldRoadProfile; nothing recorded before the first tick")
	var spawn := car.get_spawn_transform()
	# The fallback branch, never exercised before (the codex cross-review's
	# F3): R with the flag on and no pose recorded lands on the spawn.
	car.reset_car()
	await _step(2)
	_check(_at(car, spawn), "the Ring: R with the flag on and no pose recorded lands on the spawn - the fallback, as before")
	await _step(SETTLE_FRAMES)
	var profile := road.profile
	_check(car.last_road_pose_recorded and _at(car, car.last_road_pose), "settled at the pit for %d ticks the car has recorded the pit lane pose it stands in (%.4f m, %.5f rad off its own)" % [SETTLE_FRAMES, _xz_off(car, car.last_road_pose), _yaw_off(car, car.last_road_pose)])
	await _tap("reset_car")
	_check(_at(car, spawn) and _on_road(car, profile), "the first R at the pit lands on the spawn (%.4f m, %.5f rad off), on the road" % [_xz_off(car, spawn), _yaw_off(car, spawn)])

	# The drive: 400 m along the loop from Döttinger Höhe, the recorded pose
	# following the car.
	var driver := _loop_driver(car)
	var start_point: Vector2 = driver.point_at(RingDrive.DRIVE_START_CHAINAGE_M)
	var heading: float = driver.heading_at(RingDrive.DRIVE_START_CHAINAGE_M)
	var start := _pose(start_point.x, start_point.y, Vector2(cos(heading), sin(heading)))
	car.reset_to(start)
	await _step(SETTLE_FRAMES)
	var fuel_at_start := car.fuel_l
	var ticks := 0
	var unsupported_ticks := 0
	var follow_worst_m := 0.0
	var follow_worst_rad := 0.0
	var limit := int(DRIVE_TIME_LIMIT_S * Engine.physics_ticks_per_second)
	while ticks < limit:
		driver.tick(RingDrive.CRUISE_SPEED, RingDrive.LATERAL_ACCEL_BUDGET, RingDrive.LOOKAHEAD_S, RingDrive.LOOKAHEAD_MIN_M, RingDrive.LOOKAHEAD_MAX_M, RingDrive.CURVATURE_PREVIEW_M, RingDrive.PEDAL_GAIN)
		if driver.progress >= RingDrive.DRIVE_START_CHAINAGE_M + DRIVE_DISTANCE_M:
			break
		await physics_frame
		ticks += 1
		if not _all_supported(car):
			unsupported_ticks += 1
		follow_worst_m = maxf(follow_worst_m, _xz_off(car, car.last_road_pose))
		follow_worst_rad = maxf(follow_worst_rad, _yaw_off(car, car.last_road_pose))
	var covered: float = driver.progress - RingDrive.DRIVE_START_CHAINAGE_M
	_check(covered >= DRIVE_DISTANCE_M and unsupported_ticks == 0, "the follower drove %.0f m of the loop from %s in %d ticks with all four wheels supported every tick (%d ticks with one unsupported)" % [covered, RingDrive.DRIVE_START_SEGMENT, ticks, unsupported_ticks])
	_check(ticks > 0 and follow_worst_m < FOLLOW_M and follow_worst_rad < FOLLOW_RAD, "the recorded pose followed the car every tick of the drive: at most %.3f m and %.4f rad behind it (one tick's way at the cruise; was asserted at 1.0 m, several ticks' way - the codex cross-review's F2)" % [follow_worst_m, follow_worst_rad])

	# Stopped: the recorded pose is the car's own.
	car.set_driver_input(0.0, 1.0, 0.0, true)
	await _step(STOP_FRAMES)
	var rest := car.global_transform
	var recorded := car.last_road_pose
	_check(absf(car.forward_speed) < 0.05 and _at(car, recorded) and recorded.origin.y == 0.0 and _on_road(car, profile), "stopped %.0f m in (speed %.3f m/s) the recorded pose is the car's own: %.4f m, %.5f rad off, origin.y exactly 0, the car on the road" % [covered, car.forward_speed, _xz_off(car, recorded), _yaw_off(car, recorded)])
	_check(car.fuel_l < fuel_at_start, "the drive burnt fuel: %.4f l -> %.4f l" % [fuel_at_start, car.fuel_l])

	# In the field beside the road: nothing recorded there. The spot is the
	# first of RING_BESIDE the profile reads off any road.
	var right := rest.basis.x
	var nose := Vector2(-rest.basis.z.x, -rest.basis.z.z)
	var spot := Vector2.ZERO
	var chosen := Vector2.ZERO
	for candidate: Vector2 in RING_BESIDE:
		var at := Vector2(rest.origin.x + right.x * candidate.x * candidate.y, rest.origin.z + right.z * candidate.x * candidate.y)
		if not profile.describe(at.x, at.y).get("on_road", false):
			spot = at
			chosen = candidate
			break
	if not _check(chosen != Vector2.ZERO, "a spot off every road within %d candidates beside the stopped car" % RING_BESIDE.size()):
		scene.queue_free()
		return
	car.reset_to(_pose(spot.x, spot.y, nose))
	await _step(SETTLE_FRAMES)
	var beside := profile.describe(car.global_position.x, car.global_position.z)
	var field_supported := _all_supported(car)
	_check(not beside.get("on_road", false) and car.last_road_pose == recorded, "put %.0f m to the %s of the road, in the field (describe: covered %s, on_road %s, nearest road '%s'; the wheels %s on the terrain there; 30 m to the right is the side road 159029020-0, so the spot was probed), the recorded pose stays the one on the road over %d ticks" % [chosen.y, "right" if chosen.x > 0.0 else "left", beside.get("covered", false), beside.get("on_road", false), beside.get("road", ""), "all four supported" if field_supported else "not all supported", SETTLE_FRAMES])

	# R: back at the recorded pose, on the road, as reset_to leaves a car.
	# The floor-follows-reset fence (the codex cross-review's F1,
	# ROAD-SIDE RESET MEMORY 2026-09-24: the road-side reset memory broke
	# the slab's old assumption that a slab left behind on the old ground is
	# never under the car - a reset to a pose recorded near where the car was
	# put can land it inside the stale slab's 40 m footprint): the reset
	# announces itself and the floor re-places the same tick, read directly
	# after the action's tick, before the car's own step.
	car.gear = 3
	car.automatic = false
	var fuel_before := car.fuel_l
	var resets_before := car.reset_counter
	Input.action_press("reset_car")
	await physics_frame
	var slab_at := (road.get_node("Floor") as Node3D).global_position
	var car_at := car.global_position
	Input.action_release("reset_car")
	await _step(2)
	var over := car.global_position.y - profile.sample_height(car.global_position.x, car.global_position.z)
	var slab_off := Vector2(slab_at.x - car_at.x, slab_at.z - car_at.z).length()
	_check(_at(car, recorded) and _at(car, rest), "R from the field puts the car back at the recorded pose: %.4f m and %.5f rad off the pose it stopped in" % [_xz_off(car, rest), _yaw_off(car, rest)])
	_check(_on_road(car, profile) and over > RIDE_HEIGHT_MIN_M and over < RIDE_HEIGHT_MAX_M and _all_supported(car), "on the road, %.3f m over it, all four wheels supported" % over)
	_check(slab_off < 0.5, "the floor followed the reset the same tick: the slab %.3f m from the car at the action's tick (the codex cross-review's F1: a nearby reset could land inside the stale slab's 40 m footprint and be shoved)" % slab_off)
	_check(car.reset_counter == resets_before + 1 and absf(car.forward_speed) < ROLL_AFTER_TAP_MPS and car.velocity.length() < ROLL_AFTER_TAP_MPS and car.gear == 1 and car.automatic and car.engine_running, "one reset (reset_counter %d -> %d); the velocity zeroed - %.3f m/s after the tap's ticks on the grade -, in 1st (gear %d), automatic (%s), the engine running (%s): reset_to's own semantics, unchanged; the gearbox was put in 3rd manual before the tap" % [resets_before, car.reset_counter, car.forward_speed, car.gear, car.automatic, car.engine_running])
	_check(car.fuel_l <= fuel_before and fuel_before - car.fuel_l < IDLE_BURN_TAP_L and car.fuel_l < ArcadeCar.FUEL_TANK_CAPACITY_L, "the fuel is what it was at the tap less the idle's burn over the tap's ticks (%.5f -> %.5f l of %.0f; the drive burnt the rest): R is not a refuel" % [fuel_before, car.fuel_l, ArcadeCar.FUEL_TANK_CAPACITY_L])
	_check(_xz_off(car, spawn) > 100.0 and _xz_off(car, start) > DRIVE_DISTANCE_M * 0.5, "not the pit spawn (%.0f m away) and not the drive's start (%.0f m away) - was the spawn" % [_xz_off(car, spawn), _xz_off(car, start)])

	# Drives on from there.
	var on_ticks := 0
	var on_unsupported := 0
	for i in DRIVE_ON_FRAMES:
		driver.tick(RingDrive.CRUISE_SPEED, RingDrive.LATERAL_ACCEL_BUDGET, RingDrive.LOOKAHEAD_S, RingDrive.LOOKAHEAD_MIN_M, RingDrive.LOOKAHEAD_MAX_M, RingDrive.CURVATURE_PREVIEW_M, RingDrive.PEDAL_GAIN)
		await physics_frame
		on_ticks += 1
		if not _all_supported(car):
			on_unsupported += 1
	_check(car.forward_speed > 1.0 and on_unsupported == 0 and _on_road(car, profile) and _xz_off(car, rest) > 1.0, "the car drives on from the restored pose: %.1f m/s after %d ticks, %.1f m further along, all four wheels supported every tick, on the road" % [car.forward_speed, on_ticks, _xz_off(car, rest)])
	car.set_driver_input(0.0, 1.0, 0.0, true)
	scene.queue_free()
	await _step(2)

	# A fresh scene: no memory of the drive.
	var again := packed.instantiate()
	root.add_child(again)
	var fresh := again.get_node("Car") as ArcadeCar
	_check(fresh.reset_to_last_pose and not fresh.last_road_pose_recorded, "a second Ring instanced fresh holds no recorded pose before its first tick (per-session memory)")
	await _step(SETTLE_FRAMES)
	await _tap("reset_car")
	_check(_at(fresh, fresh.get_spawn_transform()) and _on_road(fresh, (again.get_node("Road") as RoadBuilder).profile), "its first R lands on the spawn (%.4f m, %.5f rad off): a fresh load spawns at the pit as before" % [_xz_off(fresh, fresh.get_spawn_transform()), _yaw_off(fresh, fresh.get_spawn_transform())])
	again.queue_free()
	await _step(2)


## The loop's centreline from the drive's start segment as the ring drive
## test builds it, long enough for the drive.
func _loop_driver(car: ArcadeCar) -> RingDrive.LoopDriver:
	var skeleton: Dictionary = SkeletonLoader.read_file()
	var segments := SkeletonLoader.segments_of(skeleton)
	var raw_points := {}
	for raw: Variant in skeleton.get("segments", []):
		if raw is Dictionary and raw.get("id") is String:
			raw_points[raw.id] = raw.points
	var loop: SkeletonLoader.Loop = SkeletonLoader.loops_of(skeleton)[SkeletonLoader.NORDSCHLEIFE_LOOP]
	var driver := RingDrive.LoopDriver.new()
	driver.car = car
	var k: int = loop.segments.find(RingDrive.DRIVE_START_SEGMENT)
	while driver.xs.is_empty() or driver.length() < RingDrive.DRIVE_START_CHAINAGE_M + DRIVE_DISTANCE_M + RingDrive.LOOKAHEAD_MAX_M + RingDrive.CURVATURE_PREVIEW_M + 100.0:
		var id: String = loop.segments[k % loop.segments.size()]
		var half_width: float = segments[id].width_m * 0.5
		for point: Array in raw_points[id]:
			driver.add_point(point[0], point[1], half_width)
		k += 1
	return driver


# =============================================================================
#  Helpers
# =============================================================================

## A yaw-only pose at (x, z) with the nose along `direction` (x east, z
## south), origin.y 0: the way the ring drive test stands the car.
func _pose(x: float, z: float, direction: Vector2) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, atan2(-direction.x, -direction.y)), Vector3(x, 0.0, z))


func _all_supported(car: ArcadeCar) -> bool:
	for held: bool in car.wheel_supported:
		if not held:
			return false
	return true


func _on_road(car: ArcadeCar, profile: WorldRoadProfile) -> bool:
	return profile.describe(car.global_position.x, car.global_position.z).get("on_road", false)


## The car's level distance from a pose's origin [m].
func _xz_off(car: ArcadeCar, pose: Transform3D) -> float:
	return Vector2(car.global_position.x - pose.origin.x, car.global_position.z - pose.origin.z).length()


## The angle between the car's nose and a pose's [rad].
func _yaw_off(car: ArcadeCar, pose: Transform3D) -> float:
	var nose := -car.global_basis.z
	var other := -pose.basis.z
	return absf(angle_difference(atan2(nose.x, nose.z), atan2(other.x, other.z)))


func _at(car: ArcadeCar, pose: Transform3D) -> bool:
	return _xz_off(car, pose) < LAND_M and _yaw_off(car, pose) < LAND_RAD


func _tap(action: StringName) -> void:
	Input.action_press(action)
	await _step(2)
	Input.action_release(action)
	await _step(2)


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
	Input.action_release("reset_car")
	Input.action_release("accelerate")
	if _failures == 0:
		print("RESET TEST PASSED")
	else:
		print("RESET TEST FAILED: %d check(s) failed" % _failures)
	quit(1 if _failures > 0 else 0)
