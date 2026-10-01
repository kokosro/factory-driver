extends SceneTree
## Headless streaming test (L2-STREAMING-1 slices 1+2; decisions.org
## C07BE6F1 "no freezing load, world-around-the-car streaming"; the ruling
## FD79B028 of 2026-10-01: about 2 km of dressed vicinity is enough, the
## loading screen vanishes the moment the car can roll, the tail streams
## with no bar, every road's mesh stays resident;
## docs/design/l2-streaming-design.md). A standalone, not a step of
## tests/run_tests.sh:
##
##   godot --headless --path . --import
##   godot --headless --fixed-fps 60 --path . --script res://tests/streaming_test.gd
##
## THE SCHEDULER (scripts/streaming_scheduler.gd, the Streaming autoload):
## registered after every other autoload, reached through of(), the
## ruling's numbers (R_HANDOVER_M 2 000, the loading scene's DATA_THREADS
## and NODE_BUDGET_MS), the box distance and the band as pure functions;
## claim() refuses a scene in the tree and a Ring whose builders are not
## deferred - a Ring instanced the ordinary way and the pad leave it idle,
## every counter zero: it never attaches to a sync build.
##
## THE ONE-SHOT BUILD (the reference): the Ring instanced and added, built
## whole in _ready; a SHA-256 per child under Terrain, Forest and
## Buildings (the async build test's hash walk, per chunk); the ring drive
## test's own scripted driver (its LoopDriver class and its constants,
## read from the frozen script, not copied) over the same 2 km from
## Döttinger Höhe.
##
## THE STREAMED BUILD AT THE PIT ANCHOR (the loading scene, the scene
## file's start pose): at the handover the children under the three
## builders are the reference's order held to the resident set and the
## chunks whose box is within 2 000 m of the car (this test's own
## arithmetic on the chunk names, never the scheduler's), the far chunks
## ABSENT, the car on the road's profile over its floor slab; THE DRIVE
## starts in that state, 2.8 km from the pit - over ground whose dressing
## was not there at the handover and streams in around the car as it goes
## - and lands on the one-shot build's odometer and position TO THE BIT in
## the same number of ticks, all four wheels carried every tick, no wheel
## off the paved width: the car reads the profile and the floor slab, and
## a chunk that is not there yet is a picture missing, never a height.
## Then the tail's completion: the same children as the reference name
## for name, every child the reference's to the byte, the four describe()
## lines and every count the reference's to the character and the integer
## (no existing line or counter changes value; the scheduler's three
## counters are new and add up).
##
## THE STREAMED BUILD AT TWO CORNERS (the car put at the Karussell, then
## at Aremberg, 4.9 km apart, before the lists are split): the handover's
## set follows the car - the resident set and that position's vicinity,
## another set than the pit's - and the tail arrives in the pinned order
## for the standing car, the far chunks by (band of 1 000 m, builder,
## CHUNK_ORDER); every child, handed over or streamed, the reference's to
## the byte.
##
## THE CANCEL: a Ring unloaded in the frame after its handover, the tail
## in flight - the scheduler waits for its tasks and forgets the Ring:
## idle, nothing claimed, nothing under the root that was not there.
##
## The store pinned off (FD_TELEMETRY=0, the marks test's idiom); nothing
## is written anywhere. No wall time is printed: the lines are the same
## on every machine. Exits 0 on success, 1 on any failed check.

const RING_SCENE := "res://scenes/eifel_ring.tscn"
const PAD_SCENE := "res://scenes/main.tscn"

## The ring drive test (FROZEN, read only): its scripted pure-pursuit
## driver and the drive's constants are used from the script itself.
const RingDrive := preload("res://tests/ring_drive_test.gd")

## This test's own copy of the ruling's numbers (a change in the
## scheduler fails here): the vicinity [m], the chunk and the band [m].
const R_HANDOVER_M := 2000.0
const CHUNK_M := 1000.0
const BAND_M := 1000.0
## The builders that stream, in the scheduler's rank order.
const STREAMED: Array[String] = ["Terrain", "Forest", "Buildings"]

## The pit anchor: the Car's place in scenes/eifel_ring.tscn [m].
const PIT_ANCHOR := Vector2(2037.199, -1355.401)
## The two corners (skeleton.json's names): the loop segment and the
## point of it the car is put at - the Karussell's fifteenth point, in the
## bowl, and Aremberg's eleventh, the loop's western end.
const CORNERS := [
	{"name": "Karussell", "segment": "414785755-0", "point": 14, "at": Vector2(4762.554, -4898.626)},
	{"name": "Aremberg", "segment": "799394500-1", "point": 10, "at": Vector2(49.41, -3497.627)},
]

## Frames to let a scene settle, and the wall-clock caps on a load and a
## tail before the test gives up [ms] (never printed).
const SETTLE_FRAMES := 5
const LOAD_TIMEOUT_MS := 300000
const TAIL_TIMEOUT_MS := 120000
## Ticks a car put at a corner is held on the brakes before it is read.
const HOLD_FRAMES := 120
## The physics tick, counted from the Ring's entry into the tree, at
## which the drive resets the car to its start - the same tick on the
## one-shot build and on the streamed one, so the two cars have the same
## history to the tick (the ring drive test's determinism check instances
## two scenes the same way for the same reason).
const DRIVE_AT_TICK := 10

var _failures := 0
var _skeleton: Dictionary
var _segments: Dictionary
var _raw_points: Dictionary = {}
var _loop: SkeletonLoader.Loop


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	OS.set_environment("FD_TELEMETRY", "0")
	_skeleton = SkeletonLoader.read_file()
	_segments = SkeletonLoader.segments_of(_skeleton)
	for raw: Variant in _skeleton.get("segments", []):
		if raw is Dictionary and raw.get("id") is String:
			_raw_points[raw.id] = raw.points
	_loop = SkeletonLoader.loops_of(_skeleton)[SkeletonLoader.NORDSCHLEIFE_LOOP]

	print("-- the scheduler")
	var scheduler := _check_scheduler()
	if scheduler == null:
		_finish()
		return

	print("-- the one-shot build (the reference)")
	var sync_ring: Node = (load(RING_SCENE) as PackedScene).instantiate()
	# Added in a process frame, as the loading scene's handover adds its
	# Ring: the tick count below then starts at the car's first tick on
	# both builds.
	await process_frame
	root.add_child(sync_ring)
	var sync_ticks := _count_ticks()
	await _until_tick(sync_ticks, DRIVE_AT_TICK)
	var sync_drive := await _drive(sync_ring.get_node("Car"), sync_ring.get_node("Road"))
	var reference := _snapshot(sync_ring)
	_ok(reference.children.Terrain.size() > 0 and reference.children.Forest.size() > 0 and reference.children.Buildings.size() > 0 and _idle(scheduler), "the Ring instanced the ordinary way built whole in _ready (%d / %d / %d children under Terrain / Forest / Buildings) and the scheduler never looked at it: nothing claimed, every counter zero" % [reference.children.Terrain.size(), reference.children.Forest.size(), reference.children.Buildings.size()], "the scheduler after a sync build: %s" % scheduler.describe())
	var sync_terrain: TerrainBuilder = sync_ring.get_node("Terrain")
	var lattice_origin := Vector2(sync_terrain.x0, sync_terrain.z0)
	_check_refused(scheduler, sync_ring)
	_ok(sync_drive.reached and sync_drive.unsupported == 0 and sync_drive.airborne == 0 and sync_drive.margin >= 0.0, "the reference drive: the ring drive test's scripted driver covered its %.0f m from %s on the one-shot build in %d ticks, all four wheels carried every tick, every wheel inside the paved width (the smallest margin %.3f m); the odometer %.6f m" % [RingDrive.DRIVE_DISTANCE_M, RingDrive.DRIVE_START_SEGMENT, sync_drive.ticks, sync_drive.margin, sync_drive.odometer], "the reference drive: reached %s in %d ticks, %d unsupported, %d airborne, margin %.3f" % [sync_drive.reached, sync_drive.ticks, sync_drive.unsupported, sync_drive.airborne, sync_drive.margin])
	root.remove_child(sync_ring)
	sync_ring.free()
	await _step(2)

	print("-- the pad")
	var pad: Node = (load(PAD_SCENE) as PackedScene).instantiate()
	root.add_child(pad)
	await _step(SETTLE_FRAMES)
	_ok(_idle(scheduler), "the pad came up and the scheduler stayed idle: no builders, nothing claimed, nothing streams there")
	root.remove_child(pad)
	pad.free()
	await _step(2)
	var root_children_before := root.get_child_count()

	print("-- the streamed build at the pit anchor")
	var pit := await _load_streamed(scheduler, null)
	if pit.ring == null:
		_ok(false, "", "the loading scene did not hand over at the pit anchor")
		_finish()
		return
	var pit_set := _check_handover(pit, reference, lattice_origin, PIT_ANCHOR, "the pit anchor")
	# The drive starts with the tail still to come: the far chunks absent.
	await _until_tick(pit.ticks, DRIVE_AT_TICK)
	var pending_at_start := scheduler.chunks_remaining()
	var streamed_drive := await _drive(pit.ring.get_node("Car"), pit.ring.get_node("Road"))
	_ok(pending_at_start > 0 and streamed_drive.reached and streamed_drive.unsupported == 0 and streamed_drive.airborne == 0 and streamed_drive.margin >= 0.0, "the drive over streamed ground: begun at the handover with far chunks still to stream, the same driver covered the same %.0f m from %s - 2.8 km from the pit, ground whose dressing was absent at the handover - all four wheels carried every tick, every wheel inside the paved width (the smallest margin %.3f m)" % [RingDrive.DRIVE_DISTANCE_M, RingDrive.DRIVE_START_SEGMENT, streamed_drive.margin], "the streamed drive: %d chunks pending at its start, reached %s in %d ticks, %d unsupported, %d airborne, margin %.3f" % [pending_at_start, streamed_drive.reached, streamed_drive.ticks, streamed_drive.unsupported, streamed_drive.airborne, streamed_drive.margin])
	_ok(streamed_drive.odometer == sync_drive.odometer and streamed_drive.position == sync_drive.position and streamed_drive.ticks == sync_drive.ticks, "the streamed build drives like the one-shot build TO THE BIT: the same odometer (%.6f m), the same position (%s), the same %d ticks - the car reads the profile and the floor slab, never a chunk" % [streamed_drive.odometer, streamed_drive.position, streamed_drive.ticks], "the drives differ: odometer %.9f vs %.9f, position %s vs %s, ticks %d vs %d" % [streamed_drive.odometer, sync_drive.odometer, streamed_drive.position, sync_drive.position, streamed_drive.ticks, sync_drive.ticks])
	await _await_tail(scheduler)
	_check_completion(scheduler, pit, reference, "the pit anchor")
	_check_counts(scheduler, pit, reference, lattice_origin, PIT_ANCHOR)
	unload_current_scene()
	await _step(2)
	_ok(current_scene == null and root.get_child_count() == root_children_before and _idle(scheduler), "the Ring unloaded: the root holds what it held, the scheduler forgot the Ring")

	for corner: Dictionary in CORNERS:
		print("-- the streamed build at %s" % corner.name)
		var points: Array = _raw_points.get(corner.segment, [])
		var named: bool = points.size() > corner.point and is_equal_approx(points[corner.point][0], corner.at.x) and is_equal_approx(points[corner.point][1], corner.at.y) and _loop.segments.has(corner.segment) and _segment_name(corner.segment) == corner.name
		_ok(named, "%s is the loop's segment %s in skeleton.json; the car is put at its point %d, (%.3f, %.3f), %.0f m from the pit anchor" % [corner.name, corner.segment, corner.point, corner.at.x, corner.at.y, corner.at.distance_to(PIT_ANCHOR)])
		var outcome := await _load_streamed(scheduler, corner.at)
		if outcome.ring == null:
			_ok(false, "", "the loading scene did not hand over at %s" % corner.name)
			continue
		var corner_set := _check_handover(outcome, reference, lattice_origin, corner.at, corner.name)
		_ok(corner_set != pit_set and not corner_set.is_empty(), "the vicinity followed the car: the streamable chunks standing at the handover at %s are another set than the pit anchor's" % corner.name)
		await _await_tail(scheduler)
		_check_order(outcome, reference, lattice_origin, corner.at, corner.name)
		_check_completion(scheduler, outcome, reference, corner.name)
		await _step(HOLD_FRAMES)
		_check_standing(outcome.ring, corner.name)
		unload_current_scene()
		await _step(2)

	print("-- the cancel")
	var cancelled := await _load_streamed(scheduler, null)
	if cancelled.ring != null:
		var in_flight: bool = scheduler.streaming and scheduler.ring == cancelled.ring and scheduler.chunks_remaining() > 0
		unload_current_scene()
		await _step(2)
		_ok(in_flight and _idle(scheduler) and current_scene == null and root.get_child_count() == root_children_before, "a Ring unloaded with its tail in flight: the scheduler waited for its tasks and forgot the Ring - idle, nothing claimed, the root as it was", "in flight %s, the scheduler %s, current %s, root children %d (was %d)" % [in_flight, scheduler.describe(), current_scene, root.get_child_count(), root_children_before])
	else:
		_ok(false, "", "the loading scene did not hand over for the cancel")
	_finish()


# =============================================================================
#  The scheduler
# =============================================================================

func _check_scheduler() -> StreamingScheduler:
	var scheduler := StreamingScheduler.of(self)
	var autoloads := PackedStringArray()
	for property: Dictionary in ProjectSettings.get_property_list():
		if String(property.name).begins_with("autoload/"):
			autoloads.append(String(property.name).trim_prefix("autoload/"))
	var last: bool = not autoloads.is_empty() and autoloads[autoloads.size() - 1] == StreamingScheduler.AUTOLOAD_NAME
	_ok(scheduler != null and scheduler.get_parent() == root and scheduler.name == StreamingScheduler.AUTOLOAD_NAME and last, "the Streaming autoload is registered in project.godot after every other autoload (%s) and stands under the root; StreamingScheduler.of() reaches it" % ", ".join(autoloads), "scheduler %s, autoloads %s" % [scheduler, autoloads])
	if scheduler == null:
		return null
	_ok(StreamingScheduler.R_HANDOVER_M == R_HANDOVER_M and StreamingScheduler.BAND_M == BAND_M and StreamingScheduler.DATA_THREADS == LoadingScreen.DATA_THREADS and StreamingScheduler.NODE_BUDGET_MS == LoadingScreen.NODE_BUDGET_MS and TerrainBuilder.CHUNK_M == CHUNK_M and ForestWalls.CHUNK_M == CHUNK_M and BuildingsShells.CHUNK_M == CHUNK_M, "the ruling's numbers: the vicinity %.0f m, the band %.0f m, the builders' chunk %.0f m; the tail's workers (%d) and node budget (%.0f ms a frame) are the loading scene's own" % [R_HANDOVER_M, BAND_M, CHUNK_M, StreamingScheduler.DATA_THREADS, StreamingScheduler.NODE_BUDGET_MS])
	var box := PackedFloat64Array([1000.0, -2000.0, 2000.0, -1000.0])
	var inside := StreamingScheduler.box_distance_squared(box, 1500.0, -1500.0)
	var beside := StreamingScheduler.box_distance_squared(box, 2300.0, -1500.0)
	var corner := StreamingScheduler.box_distance_squared(box, 2300.0, -600.0)
	_ok(inside == 0.0 and beside == 300.0 * 300.0 and corner == 300.0 * 300.0 + 400.0 * 400.0 and StreamingScheduler.band_of(0.0) == 0 and StreamingScheduler.band_of(999.9) == 0 and StreamingScheduler.band_of(1000.0) == 1 and StreamingScheduler.band_of(2500.0) == 2, "the distance is to the chunk's box, the bubble's measure (0 inside, 300 m beside an edge, 500 m off a corner), and the band its whole thousands of metres")
	_ok(_idle(scheduler) and not scheduler.is_processing(), "at rest the scheduler is idle and does not process: %s" % scheduler.describe())
	return scheduler


## Nothing claimed, nothing streaming, every counter zero.
func _idle(scheduler: StreamingScheduler) -> bool:
	return scheduler.ring == null and not scheduler.streaming and scheduler.chunks_total == 0 and scheduler.chunks_at_handover == 0 and scheduler.chunks_streamed == 0 and scheduler.chunks_remaining() == 0 and scheduler.arrivals.is_empty()


## claim() takes only the loading scene's Ring: outside the tree, its
## four builders deferred.
func _check_refused(scheduler: StreamingScheduler, sync_ring: Node) -> void:
	var in_tree := scheduler.claim(sync_ring)
	var outside: Node = (load(RING_SCENE) as PackedScene).instantiate()
	var no_buildings := scheduler.claim(outside)
	BuildingsShells.of(outside)
	var not_deferred := scheduler.claim(outside)
	outside.free()
	var nothing := scheduler.claim(null)
	_ok(not in_tree and not no_buildings and not not_deferred and not nothing and _idle(scheduler), "claim() refused a Ring in the tree, a Ring outside it whose builders are not deferred (with and without its Buildings node) and no scene at all; the scheduler stayed idle - only the loading scene's async path streams", "in tree %s, no buildings %s, not deferred %s, null %s; %s" % [in_tree, no_buildings, not_deferred, nothing, scheduler.describe()])


# =============================================================================
#  The builds
# =============================================================================

## The Ring through the loading scene; with `at`, the car put there while
## the Ring is still outside the tree, before any list is split (and stood
## on the road there, on the brakes, at the handover). What stood at the
## handover is taken in the handover's own frame: the child names, the
## scheduler's counters and origin, the car's seam.
func _load_streamed(scheduler: StreamingScheduler, at: Variant) -> Dictionary:
	LoadingScreen.target_scene = RING_SCENE
	var loading: LoadingScreen = (load(LoadingScreen.SCENE) as PackedScene).instantiate()
	var outcome := {"ring": null, "children": {}, "at_handover": 0, "total": 0, "to_stream": 0, "origin": Vector3.ZERO, "on_profile": false, "claimed": false, "streaming": false, "moved": false, "ticks": {}}
	loading.handed_over.connect(func(built: Node) -> void:
		outcome.ring = built
		outcome.ticks = _count_ticks()
		outcome.children = _children_of(built)
		outcome.at_handover = scheduler.chunks_at_handover
		outcome.total = scheduler.chunks_total
		outcome.to_stream = scheduler.chunks_remaining()
		outcome.origin = scheduler.origin
		outcome.claimed = scheduler.ring == built
		outcome.streaming = scheduler.streaming
		var road: RoadBuilder = built.get_node("Road")
		var car: ArcadeCar = built.get_node("Car")
		outcome.on_profile = car.road_profile is WorldRoadProfile and car.road_profile == road.profile and road.get_node_or_null("Floor") is StaticBody3D and loading.fallback_reason == ""
		if at != null:
			car.reset_to(Transform3D(Basis.IDENTITY, Vector3(at.x, 0.0, at.y)))
			car.set_driver_input(0.0, 1.0, 0.0, true)
	)
	var gave_up := Time.get_ticks_msec() + LOAD_TIMEOUT_MS
	root.add_child(loading)
	while outcome.ring == null and is_instance_valid(loading) and Time.get_ticks_msec() < gave_up:
		await process_frame
		if at != null and not outcome.moved and is_instance_valid(loading) and loading.ring != null:
			(loading.ring.get_node("Car") as Node3D).position = Vector3(at.x, 0.0, at.y)
			outcome.moved = true
	return outcome


func _await_tail(scheduler: StreamingScheduler) -> void:
	var gave_up := Time.get_ticks_msec() + TAIL_TIMEOUT_MS
	while scheduler.streaming and Time.get_ticks_msec() < gave_up:
		await process_frame


# =============================================================================
#  The checks
# =============================================================================

## The handover: the claimed Ring in the tree, the car on the profile, the
## children the reference's order held to the resident set and the
## vicinity of `at`, the far chunks absent. Returns the streamable chunks
## standing at the handover, "<Builder>/<name>" joined (the set's
## signature).
func _check_handover(outcome: Dictionary, reference: Dictionary, lattice_origin: Vector2, at: Vector2, where: String) -> String:
	var ring: Node = outcome.ring
	var origin: Vector3 = outcome.origin
	_ok(current_scene == ring and outcome.claimed and outcome.streaming and outcome.on_profile and is_equal_approx(origin.x, at.x) and is_equal_approx(origin.z, at.y), "the handover at %s: the Ring is the current scene, claimed by the scheduler and its tail streaming, the vicinity measured from the car's start (%.3f, %.3f); the car stands on the road's profile (the same object, a WorldRoadProfile) over the floor slab, no fallback" % [where, origin.x, origin.z], "current %s, claimed %s, streaming %s, on profile %s, origin %s" % [current_scene == ring, outcome.claimed, outcome.streaming, outcome.on_profile, origin])
	var thin := true
	var absent := {}
	var kept := {}
	var signature := PackedStringArray()
	var near_chunks := 0
	for builder: String in STREAMED:
		var expected := PackedStringArray()
		absent[builder] = 0
		for child_name: String in reference.children[builder]:
			var box := _chunk_box(builder, child_name, lattice_origin)
			if box.is_empty():
				expected.append(child_name)
			elif _box_distance(box, at) <= R_HANDOVER_M:
				expected.append(child_name)
				signature.append(builder + "/" + child_name)
				near_chunks += 1
			else:
				absent[builder] += 1
		kept[builder] = expected.size()
		var handed: PackedStringArray = outcome.children[builder]
		thin = thin and handed == expected and absent[builder] > 0
		for child_name: String in handed:
			var box := _chunk_box(builder, child_name, lattice_origin)
			thin = thin and (box.is_empty() or _box_distance(box, at) <= R_HANDOVER_M)
	_ok(thin and outcome.children.Road == reference.children.Road, "the handover at %s happened with the far chunks ABSENT: under Terrain %d of %d children stand, under Forest %d of %d, under Buildings %d of %d - the reference's names in the reference's order held to the resident set and the %d chunks whose box is within %.0f m of the car; %d / %d / %d chunks beyond it are not there; every one of the %d children under Road is" % [where, kept.Terrain, reference.children.Terrain.size(), kept.Forest, reference.children.Forest.size(), kept.Buildings, reference.children.Buildings.size(), near_chunks, R_HANDOVER_M, absent.Terrain, absent.Forest, absent.Buildings, reference.children.Road.size()], "handed %d / %d / %d, expected %d / %d / %d, absent %s" % [outcome.children.Terrain.size(), outcome.children.Forest.size(), outcome.children.Buildings.size(), kept.Terrain, kept.Forest, kept.Buildings, absent])
	return ",".join(signature)


## The tail's arrival order for a car standing at `at`: this test's own
## sort of the far chunks by (band, builder, the reference's child index
## - CHUNK_ORDER) against the scheduler's arrivals and the children as
## they stand after the handover's.
func _check_order(outcome: Dictionary, reference: Dictionary, lattice_origin: Vector2, at: Vector2, where: String) -> void:
	var scheduler := StreamingScheduler.of(self)
	var ring: Node = outcome.ring
	var expected: Array = []
	var known := {}
	for b: int in STREAMED.size():
		var builder: String = STREAMED[b]
		for k: int in reference.children[builder].size():
			var child_name: String = reference.children[builder][k]
			known[builder + "/" + child_name] = true
			var box := _chunk_box(builder, child_name, lattice_origin)
			if not box.is_empty() and _box_distance(box, at) > R_HANDOVER_M:
				expected.append([int(floor(_box_distance(box, at) / BAND_M)), b, k, builder + "/" + child_name])
	expected.sort_custom(func(x: Array, y: Array) -> bool:
		if x[0] != y[0]:
			return x[0] < y[0]
		if x[1] != y[1]:
			return x[1] < y[1]
		return x[2] < y[2]
	)
	var expected_order := PackedStringArray()
	var expected_tail := {"Terrain": PackedStringArray(), "Forest": PackedStringArray(), "Buildings": PackedStringArray()}
	var bands := {}
	for entry: Array in expected:
		expected_order.append(entry[3])
		expected_tail[STREAMED[entry[1]]].append(String(entry[3]).get_slice("/", 1))
		bands[entry[0]] = true
	# A near chunk with nothing in it is a job and an arrival, never a
	# child: the arrivals are held to the ones that left a child.
	var arrived := PackedStringArray()
	for arrival: String in scheduler.arrivals:
		if known.has(arrival):
			arrived.append(arrival)
	var ordered: bool = arrived == expected_order and not expected_order.is_empty()
	var children := _children_of(ring)
	for builder: String in STREAMED:
		ordered = ordered and children[builder] == outcome.children[builder] + expected_tail[builder]
	_ok(ordered, "the tail at %s arrived in the pinned order: the %d far chunks by (the band of %.0f m from the standing car - %d bands - then the builder, then CHUNK_ORDER), standing under each builder after the handover's children in that order" % [where, expected_order.size(), BAND_M, bands.size()], "arrivals %d, expected %d, the first difference at %d" % [arrived.size(), expected_order.size(), _first_difference(arrived, expected_order)])


## The tail's completion: the reference's set, every child the
## reference's to the byte, the describe() lines and counts the
## reference's.
func _check_completion(scheduler: StreamingScheduler, outcome: Dictionary, reference: Dictionary, where: String) -> void:
	var ring: Node = outcome.ring
	_ok(not scheduler.streaming and scheduler.ring == ring and scheduler.chunks_remaining() == 0 and scheduler.chunks_streamed == outcome.to_stream and outcome.to_stream > 0, "the tail at %s completed: the %d chunks left at the handover streamed in, nothing pending" % [where, outcome.to_stream], "the tail: %s" % scheduler.describe())
	var built := _snapshot(ring)
	var same_set: bool = built.children.Road == reference.children.Road
	for builder: String in STREAMED:
		var a := Array(built.children[builder])
		var b := Array(reference.children[builder])
		a.sort()
		b.sort()
		same_set = same_set and a == b
	var faults := PackedStringArray()
	var handed_equal := 0
	var streamed_equal := 0
	for builder: String in STREAMED:
		var at_handover := {}
		for child_name: String in outcome.children[builder]:
			at_handover[child_name] = true
		for child_name: String in reference.chunks[builder]:
			if built.chunks[builder].get(child_name, "") != reference.chunks[builder][child_name]:
				faults.append(builder + "/" + child_name)
			elif at_handover.has(child_name):
				handed_equal += 1
			else:
				streamed_equal += 1
	_ok(same_set and faults.is_empty() and handed_equal > 0 and streamed_equal > 0, "streamed == one-shot at %s, BYTE-EQUAL per chunk: the children are the reference's set name for name, and the SHA-256 of each of the %d children that stood at the handover and each of the %d streamed after it equals the one-shot build's child of the same name" % [where, handed_equal, streamed_equal], "same set %s; %d children differ (the first: %s); %d handed and %d streamed equal" % [same_set, faults.size(), faults[0] if not faults.is_empty() else "none", handed_equal, streamed_equal])
	_ok(built.report == reference.report, "the four describe() lines and every count at %s are the one-shot build's to the character and the integer: no existing line or counter changed value (Terrain: %s)" % [where, built.report.terrain.describe], "the reports differ: %s vs %s" % [built.report, reference.report])


## The scheduler's own counters (new, additive) against this test's count
## of the chunks from the job lists.
func _check_counts(scheduler: StreamingScheduler, outcome: Dictionary, reference: Dictionary, lattice_origin: Vector2, at: Vector2) -> void:
	var ring: Node = outcome.ring
	var streamable := 0
	var vicinity := 0
	var names := {"Terrain": PackedStringArray(), "Forest": PackedStringArray(), "Buildings": PackedStringArray()}
	for job: TerrainBuilder.MeshJob in (ring.get_node("Terrain") as TerrainBuilder).mesh_jobs():
		names.Terrain.append(job.name)
	for job: ForestWalls.MeshJob in (ring.get_node("Forest") as ForestWalls).mesh_jobs():
		names.Forest.append(job.name)
	for job: BuildingsShells.MeshJob in (ring.get_node("Buildings") as BuildingsShells).mesh_jobs():
		names.Buildings.append(job.name)
	for builder: String in STREAMED:
		for job_name: String in names[builder]:
			var box := _chunk_box(builder, job_name, lattice_origin)
			if box.is_empty():
				continue
			streamable += 1
			if _box_distance(box, at) <= R_HANDOVER_M:
				vicinity += 1
	_ok(streamable > 0 and outcome.total == streamable and outcome.at_handover == vicinity and outcome.to_stream == streamable - vicinity and scheduler.chunks_total == streamable and scheduler.chunks_at_handover == vicinity and scheduler.chunks_streamed == streamable - vicinity, "the scheduler's counters (new, additive): %d streamable chunks in the three job lists by this test's count, %d within %.0f m built before the handover, %d streamed after it - %d + %d = %d" % [streamable, vicinity, R_HANDOVER_M, scheduler.chunks_streamed, vicinity, scheduler.chunks_streamed, streamable], "streamable %d (the scheduler %d), vicinity %d (%d), streamed %d" % [streamable, scheduler.chunks_total, vicinity, scheduler.chunks_at_handover, scheduler.chunks_streamed])


## The car put at a corner stands on the road there: held on the brakes,
## all four wheels carried, at rest, the body over the profile.
func _check_standing(ring: Node, where: String) -> void:
	var car: ArcadeCar = ring.get_node("Car")
	var road: RoadBuilder = ring.get_node("Road")
	var supported := true
	for held: bool in car.wheel_supported:
		supported = supported and held
	var over := car.global_position.y - road.profile.sample_height(car.global_position.x, car.global_position.z)
	_ok(supported and not car.is_airborne and absf(car.forward_speed) < 0.5 and over > RingDrive.RIDE_HEIGHT_MIN_M and over < RingDrive.RIDE_HEIGHT_MAX_M, "the car stands on the profile at %s: four wheels carried, at rest, the body %.3f m over the road" % [where, over], "at %s: supported %s, airborne %s, speed %.2f, %.3f m over the road" % [where, supported, car.is_airborne, car.forward_speed, over])


# =============================================================================
#  The drive (tests/ring_drive_test.gd's, on its own driver and constants)
# =============================================================================

## The path from the drive's start segment along the loop's chain (the
## ring drive test's _loop_path).
func _loop_path(car: ArcadeCar) -> RefCounted:
	var driver := RingDrive.LoopDriver.new()
	driver.car = car
	var k := _loop.segments.find(RingDrive.DRIVE_START_SEGMENT)
	while driver.xs.is_empty() or driver.length() < RingDrive.PATH_LENGTH_M:
		var id: String = _loop.segments[k % _loop.segments.size()]
		var half_width: float = _segments[id].width_m * 0.5
		for point: Array in _raw_points[id]:
			driver.add_point(point[0], point[1], half_width)
		k += 1
	return driver


## The ring drive test's 2 km drive: the car reset to the start, settled,
## driven tick by tick; {odometer, position, ticks, reached, unsupported,
## airborne, margin}.
func _drive(car: ArcadeCar, _road: RoadBuilder) -> Dictionary:
	var driver := _loop_path(car)
	var start_point: Vector2 = driver.point_at(RingDrive.DRIVE_START_CHAINAGE_M)
	var heading: float = driver.heading_at(RingDrive.DRIVE_START_CHAINAGE_M)
	var direction := Vector2(cos(heading), sin(heading))
	car.reset_to(Transform3D(Basis(Vector3.UP, atan2(-direction.x, -direction.y)), Vector3(start_point.x, 0.0, start_point.y)))
	await _step(RingDrive.SETTLE_FRAMES)
	var ticks := 0
	var limit := int(RingDrive.DRIVE_TIME_LIMIT_S * Engine.physics_ticks_per_second)
	var unsupported := 0
	var airborne := 0
	var margin := INF
	var finish: float = RingDrive.DRIVE_START_CHAINAGE_M + RingDrive.DRIVE_DISTANCE_M
	while ticks < limit:
		driver.tick(RingDrive.CRUISE_SPEED, RingDrive.LATERAL_ACCEL_BUDGET, RingDrive.LOOKAHEAD_S, RingDrive.LOOKAHEAD_MIN_M, RingDrive.LOOKAHEAD_MAX_M, RingDrive.CURVATURE_PREVIEW_M, RingDrive.PEDAL_GAIN)
		if driver.progress >= finish:
			break
		await physics_frame
		ticks += 1
		var all_supported := true
		for held: bool in car.wheel_supported:
			all_supported = all_supported and held
		if not all_supported:
			unsupported += 1
		if car.is_airborne:
			airborne += 1
		for i: int in ArcadeCar.WHEEL_CONTACT_POINTS.size():
			var contact: Vector3 = car.global_transform * ArcadeCar.WHEEL_CONTACT_POINTS[i]
			margin = minf(margin, driver.margin_of(contact.x, contact.z))
	car.set_driver_input(0.0, 1.0, 0.0)
	return {"odometer": car.odometer_m, "position": car.global_position, "ticks": ticks, "reached": driver.progress >= finish, "unsupported": unsupported, "airborne": airborne, "margin": margin}


# =============================================================================
#  The measures
# =============================================================================

## A built Ring: the child names under the four builders in order, a
## SHA-256 per child under the three streamed ones, and the builders'
## describe() lines, counts and tallies.
func _snapshot(ring: Node) -> Dictionary:
	var road: RoadBuilder = ring.get_node("Road")
	var terrain: TerrainBuilder = ring.get_node("Terrain")
	var forest: ForestWalls = ring.get_node("Forest")
	var buildings: BuildingsShells = ring.get_node("Buildings")
	var chunks := {}
	for builder: String in STREAMED:
		var digests := {}
		for child: Node in ring.get_node(builder).get_children():
			var context := HashingContext.new()
			context.start(HashingContext.HASH_SHA256)
			_hash_node(context, child)
			digests[String(child.name)] = context.finish().hex_encode()
		chunks[builder] = digests
	return {
		"children": _children_of(ring),
		"chunks": chunks,
		"report": {
			"road": {"describe": road.describe(), "counters": [road.road_count, road.section_count, road.split_count, road.fine_split_count, road.vertex_count, road.triangle_count, road.body_count]},
			"terrain": {"describe": terrain.describe(), "counts": terrain.counts.duplicate(), "elements": terrain.elements.duplicate()},
			"forest": {"describe": forest.describe(), "counts": forest.counts.duplicate(), "elements": forest.elements.duplicate()},
			"buildings": {"describe": buildings.describe(), "counts": buildings.counts.duplicate(), "elements": buildings.elements.duplicate()},
		},
	}


## The child names under each builder, in order.
func _children_of(ring: Node) -> Dictionary:
	var out := {}
	for builder: String in ["Road", "Terrain", "Forest", "Buildings"]:
		var names := PackedStringArray()
		for child: Node in ring.get_node(builder).get_children():
			names.append(child.name)
		out[builder] = names
	return out


## One node and everything under it into the digest (the async build
## test's walk): its name and class, every mesh surface's vertices,
## normals, UVs, colours and indices, every collider's faces or box.
func _hash_node(context: HashingContext, node: Node) -> void:
	if not String(node.name).begins_with("@"):
		context.update(node.name.to_utf8_buffer())
	context.update(node.get_class().to_utf8_buffer())
	if node is MeshInstance3D and (node as MeshInstance3D).mesh is ArrayMesh:
		var mesh: ArrayMesh = (node as MeshInstance3D).mesh
		for s: int in mesh.get_surface_count():
			var arrays := mesh.surface_get_arrays(s)
			for k: int in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_TEX_UV, Mesh.ARRAY_COLOR, Mesh.ARRAY_INDEX]:
				var array: Variant = arrays[k]
				if array is PackedVector3Array or array is PackedVector2Array or array is PackedColorArray or array is PackedInt32Array:
					context.update(array.to_byte_array())
	elif node is CollisionShape3D:
		var shape: Shape3D = (node as CollisionShape3D).shape
		if shape is ConcavePolygonShape3D:
			context.update((shape as ConcavePolygonShape3D).get_faces().to_byte_array())
		elif shape is BoxShape3D:
			context.update(var_to_bytes((shape as BoxShape3D).size))
	for below: Node in node.get_children():
		_hash_node(context, below)


## This test's own arithmetic: the box (x_lo, z_lo, x_hi, z_hi) of the
## 1 km chunk a child or job name stands for, or an empty array for a
## resident one. Under Terrain only Near_<row>_<col> streams, on the tile
## grid from the lattice's origin; under Forest Walls_ and Trees_<x>_<z>,
## under Buildings every <element>_<x>_<z> mesh (the Rails_ and Solids_
## bodies and the bubbles are resident), on the world grid.
func _chunk_box(builder: String, child_name: String, lattice_origin: Vector2) -> PackedFloat64Array:
	var parts := child_name.rsplit("_", true, 2)
	if parts.size() != 3 or not parts[1].is_valid_int() or not parts[2].is_valid_int():
		return PackedFloat64Array()
	var x := 0.0
	var z := 0.0
	match builder:
		"Terrain":
			if parts[0] != "Near":
				return PackedFloat64Array()
			x = lattice_origin.x + float(int(parts[2])) * CHUNK_M
			z = lattice_origin.y + float(int(parts[1])) * CHUNK_M
		"Forest":
			if parts[0] != "Walls" and parts[0] != "Trees":
				return PackedFloat64Array()
			x = float(int(parts[1])) * CHUNK_M
			z = float(int(parts[2])) * CHUNK_M
		"Buildings":
			if parts[0] == "Rails" or parts[0] == "Solids":
				return PackedFloat64Array()
			x = float(int(parts[1])) * CHUNK_M
			z = float(int(parts[2])) * CHUNK_M
		_:
			return PackedFloat64Array()
	return PackedFloat64Array([x, z, x + CHUNK_M, z + CHUNK_M])


## The horizontal distance from `at` (x, z) to a chunk's box [m]: 0 inside.
func _box_distance(box: PackedFloat64Array, at: Vector2) -> float:
	var dx := maxf(0.0, maxf(box[0] - at.x, at.x - box[2]))
	var dz := maxf(0.0, maxf(box[1] - at.y, at.y - box[3]))
	return sqrt(dx * dx + dz * dz)


func _first_difference(a: PackedStringArray, b: PackedStringArray) -> int:
	for k: int in mini(a.size(), b.size()):
		if a[k] != b[k]:
			return k
	return mini(a.size(), b.size())


## A segment's name in skeleton.json ("" where it has none).
func _segment_name(id: String) -> String:
	for raw: Variant in _skeleton.get("segments", []):
		if raw is Dictionary and raw.get("id") == id:
			return String(raw.get("name", ""))
	return ""


# =============================================================================
#  Harness
# =============================================================================

## A count of the physics ticks from now on, {n}.
func _count_ticks() -> Dictionary:
	var counter := {"n": 0}
	physics_frame.connect(func() -> void: counter.n += 1)
	return counter


## Waits for the counter's tick `n` (returns at that tick's physics_frame).
func _until_tick(counter: Dictionary, n: int) -> void:
	while counter.n < n:
		await physics_frame


func _step(frames: int) -> void:
	for i: int in frames:
		await physics_frame


## An ok line or a FAIL line, counted.
func _ok(condition: bool, what: String, reason: String = "") -> void:
	if condition:
		print("  ok    ", what)
	else:
		_failures += 1
		printerr("  FAIL  ", reason if reason != "" else what)


func _finish() -> void:
	print("STREAMING TEST PASSED" if _failures == 0 else "STREAMING TEST FAILED: %d fault(s)" % _failures)
	quit(0 if _failures == 0 else 1)
