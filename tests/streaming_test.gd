extends SceneTree
## Headless streaming test (L2-STREAMING-1 slices 1+2 and 3; decisions.org
## C07BE6F1 "no freezing load, world-around-the-car streaming"; the ruling
## FD79B028 of 2026-10-01: about 2 km of dressed vicinity is enough, the
## loading screen vanishes the moment the car can roll, the tail streams
## with no bar, every road's mesh stays resident, far chunks RETIRE and
## rebuild on return; docs/design/l2-streaming-design.md). A standalone,
## not a step of
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
## THE RETIREMENT (slice 3: R_RETIRE_IN_M 3 000, R_RETIRE_OUT_M 4 500, on
## the distance to the chunk's box; every expected set and order below is
## this test's own state machine over the three job lists' names and
## boxes, never the scheduler's - _expect_stop):
##   (a) the standing car at each corner, the scheduler on its own
##       _process: once the tail has completed the streamed chunks past
##       4 500 m retire in the order (builder, CHUNK_ORDER) - their nodes
##       freed and their meshes with them (the instance ids and weak
##       references taken at the completion are dead), the others
##       standing, the builders' describe() lines and counts unmoved, the
##       scheduler's retired counter the set's size; at the pit anchor
##       the same along the 2 km drive, every retirement of a chunk past
##       4 500 m of the car in that frame;
##   (b) away and back BY HAND (the scheduler's own processing off,
##       step(at) called with the car's place): to the other corner and
##       back, then to a place 40 km off and over a 4 000 m lattice of
##       stops across the tail's chunks - every tail chunk retired and
##       rebuilt at least once, each rebuild through the scheduler's
##       pending set in the pinned order (band, builder, CHUNK_ORDER) and
##       its child BYTE-IDENTICAL (SHA-256) to its first build and to the
##       one-shot reference;
##   (c) the two radii on one chunk's own box, both sides of both and
##       exactly on them: standing to 4 500 m, retired past it, retired
##       still all the way back in to 3 000 m, rebuilt inside it - the
##       band between is inert, the same place holding the chunk standing
##       on the way out and retired on the way in;
##   (d) nothing but the tail's chunks ever retires: 40 km off the Ring
##       is the handover's Ring again name for name (the resident set,
##       the vicinity, every child under Road); a one-shot Ring and the
##       pad stepped by hand lose nothing, the scheduler idle;
##   (e) no count drift: after every retirement and rebuild the four
##       describe() lines and every count are the one-shot build's, every
##       child standing the reference's to the byte, the scheduler's five
##       counters only ever risen (retired - rebuilt = the chunks away).
##
## THE MOVED PIN (slice 3; was -> now): the tail's completion - the
## children's set, the per-child SHA-256, the describe() lines and the
## scheduler's "nothing pending" - was read when this test's loop next
## saw the tail done (at the pit: after the 2 km drive); now it is taken
## in tail_completed's own frame, by the signal: from the next step on
## the far chunks retire, and after the drive the Ring is no longer
## whole. The same three checks, the same words, the same values.
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
## The retire band [m], this test's own copy likewise: a streamed chunk
## farther than R_RETIRE_OUT_M retires, a retired one nearer than
## R_RETIRE_IN_M is rebuilt, between and exactly on them nothing changes.
const R_RETIRE_IN_M := 3000.0
const R_RETIRE_OUT_M := 4500.0
## The builders that stream, in the scheduler's rank order.
const STREAMED: Array[String] = ["Terrain", "Forest", "Buildings"]
## A place by hand that every chunk is far past R_RETIRE_OUT_M of [m].
const NOWHERE := Vector2(-40000.0, 40000.0)
## The sweep's lattice of stops [m]: every point of the tail's chunks is
## within half its diagonal (2 828 m) of a stop, inside R_RETIRE_IN_M.
const SWEEP_M := 4000.0
## The boundary walk's distances from one chunk's box [m], in order, and
## whether the chunk stands at each: out past R_RETIRE_OUT_M and back in
## past R_RETIRE_IN_M, both radii exactly, the band between both ways.
const WALK_M: Array[float] = [2999.0, 3750.0, 4499.0, 4500.0, 4501.0, 4500.0, 3750.0, 3001.0, 3000.0, 2999.0]
const WALK_STANDS: Array[bool] = [true, true, true, true, false, false, false, false, false, true]
## Steps by hand after a stop has settled, in which nothing may change.
const INERT_STEPS := 3

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
## The scheduler's retirements and rebuilds as its two signals named
## them, in order: [kind, "<Builder>/<chunk>", the car's (x, z) in that
## frame or null]; emptied at each streamed load.
var _events: Array = []
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
	scheduler.chunk_retired.connect(func(builder: String, chunk: String) -> void: _events.append(["retired", builder + "/" + chunk, _car_place()]))
	scheduler.chunk_rebuilt.connect(func(builder: String, chunk: String) -> void: _events.append(["rebuilt", builder + "/" + chunk, _car_place()]))

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
	for k: int in INERT_STEPS:
		scheduler.step(Vector3(NOWHERE.x, 0.0, NOWHERE.y))
	_ok(_children_of(sync_ring) == reference.children and _idle(scheduler) and not scheduler.is_processing() and _events.is_empty(), "(d) a one-shot Ring is never retired: the scheduler stepped by hand with the car %.0f km off, every child under its four builders stands, name for name; the scheduler idle, not processing" % (NOWHERE.length() / 1000.0), "the one-shot Ring after the steps: the scheduler %s, %d events" % [scheduler.describe(), _events.size()])
	_ok(sync_drive.reached and sync_drive.unsupported == 0 and sync_drive.airborne == 0 and sync_drive.margin >= 0.0, "the reference drive: the ring drive test's scripted driver covered its %.0f m from %s on the one-shot build in %d ticks, all four wheels carried every tick, every wheel inside the paved width (the smallest margin %.3f m); the odometer %.6f m" % [RingDrive.DRIVE_DISTANCE_M, RingDrive.DRIVE_START_SEGMENT, sync_drive.ticks, sync_drive.margin, sync_drive.odometer], "the reference drive: reached %s in %d ticks, %d unsupported, %d airborne, margin %.3f" % [sync_drive.reached, sync_drive.ticks, sync_drive.unsupported, sync_drive.airborne, sync_drive.margin])
	root.remove_child(sync_ring)
	sync_ring.free()
	await _step(2)

	print("-- the pad")
	var pad: Node = (load(PAD_SCENE) as PackedScene).instantiate()
	root.add_child(pad)
	await _step(SETTLE_FRAMES)
	_ok(_idle(scheduler), "the pad came up and the scheduler stayed idle: no builders, nothing claimed, nothing streams there")
	var pad_nodes := _count_nodes(pad)
	for k: int in INERT_STEPS:
		scheduler.step(Vector3(NOWHERE.x, 0.0, NOWHERE.y))
	_ok(_count_nodes(pad) == pad_nodes and pad_nodes > 0 and _idle(scheduler) and not scheduler.is_processing() and _events.is_empty(), "(d) the pad is never retired: stepped by hand the same way, its %d nodes stand; the scheduler idle" % pad_nodes, "the pad after the steps: %d nodes (was %d), the scheduler %s" % [_count_nodes(pad), pad_nodes, scheduler.describe()])
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
	await _check_drive_retirement(scheduler, pit, reference, lattice_origin)
	_check_counts(scheduler, pit, reference, lattice_origin, PIT_ANCHOR)
	unload_current_scene()
	await _step(2)
	_ok(current_scene == null and root.get_child_count() == root_children_before and _idle(scheduler), "the Ring unloaded: the root holds what it held, the scheduler forgot the Ring")

	for c: int in CORNERS.size():
		var corner: Dictionary = CORNERS[c]
		var other: Dictionary = CORNERS[(c + 1) % CORNERS.size()]
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
		if outcome.completion.is_empty():
			unload_current_scene()
			await _step(2)
			continue
		print("-- the retirement at %s" % corner.name)
		var trip := _trip(outcome, reference, lattice_origin, corner.at)
		await _check_standing_retirement(scheduler, outcome, trip, corner.at, corner.name)
		await _check_away_and_back(scheduler, trip, corner, other)
		await _check_radii(scheduler, trip)
		await _check_sweep(scheduler, outcome, trip, corner)
		_check_no_drift(scheduler, outcome, trip, corner.name)
		var away_at_unload := scheduler.chunks_away()
		unload_current_scene()
		await _step(2)
		_ok(away_at_unload > 0 and current_scene == null and root.get_child_count() == root_children_before and _idle(scheduler), "the Ring at %s unloaded with %d of its chunks retired: the root holds what it held, the scheduler forgot the Ring, every counter zero" % [corner.name, away_at_unload], "away %d, current %s, root children %d (was %d), the scheduler %s" % [away_at_unload, current_scene, root.get_child_count(), root_children_before, scheduler.describe()])

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
	_ok(StreamingScheduler.R_RETIRE_IN_M == R_RETIRE_IN_M and StreamingScheduler.R_RETIRE_OUT_M == R_RETIRE_OUT_M and R_HANDOVER_M < R_RETIRE_IN_M and R_RETIRE_IN_M < R_RETIRE_OUT_M, "the retire band's numbers: a streamed chunk farther than %.0f m from the car retires, a retired one nearer than %.0f m is rebuilt, between them nothing changes; both past the %.0f m vicinity" % [R_RETIRE_OUT_M, R_RETIRE_IN_M, R_HANDOVER_M])
	_ok(_idle(scheduler) and not scheduler.is_processing(), "at rest the scheduler is idle and does not process: %s" % scheduler.describe())
	return scheduler


## Nothing claimed, nothing streaming, nothing retired, every counter zero.
func _idle(scheduler: StreamingScheduler) -> bool:
	return scheduler.ring == null and not scheduler.streaming and not scheduler.tail_done and scheduler.chunks_total == 0 and scheduler.chunks_at_handover == 0 and scheduler.chunks_streamed == 0 and scheduler.chunks_retired == 0 and scheduler.chunks_rebuilt == 0 and scheduler.chunks_away() == 0 and scheduler.chunks_remaining() == 0 and scheduler.arrivals.is_empty()


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
## scheduler's counters and origin, the car's seam. What stands at the
## tail's completion is taken in tail_completed's own frame (THE MOVED
## PIN): the Ring whole, before the first retirement.
func _load_streamed(scheduler: StreamingScheduler, at: Variant) -> Dictionary:
	LoadingScreen.target_scene = RING_SCENE
	var loading: LoadingScreen = (load(LoadingScreen.SCENE) as PackedScene).instantiate()
	var outcome := {"ring": null, "children": {}, "at_handover": 0, "total": 0, "to_stream": 0, "origin": Vector3.ZERO, "on_profile": false, "claimed": false, "streaming": false, "moved": false, "ticks": {}, "completion": {}}
	_events.clear()
	var on_completed := func(done: Node) -> void:
		outcome.completion = {
			"snapshot": _snapshot(done),
			"handles": _handles(done),
			"done": not scheduler.streaming and scheduler.ring == done and scheduler.chunks_remaining() == 0,
			"whole": scheduler.chunks_retired == 0 and scheduler.chunks_rebuilt == 0 and scheduler.chunks_away() == 0 and _events.is_empty(),
			"streamed": scheduler.chunks_streamed,
			"arrivals": scheduler.arrivals.duplicate(),
		}
	scheduler.tail_completed.connect(on_completed, CONNECT_ONE_SHOT)
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
	var ordered: bool = arrived == expected_order and not expected_order.is_empty() and not outcome.completion.is_empty()
	var children: Dictionary = outcome.completion.snapshot.children if not outcome.completion.is_empty() else _children_of(ring)
	for builder: String in STREAMED:
		ordered = ordered and children[builder] == outcome.children[builder] + expected_tail[builder]
	_ok(ordered, "the tail at %s arrived in the pinned order: the %d far chunks by (the band of %.0f m from the standing car - %d bands - then the builder, then CHUNK_ORDER), standing under each builder after the handover's children in that order" % [where, expected_order.size(), BAND_M, bands.size()], "arrivals %d, expected %d, the first difference at %d" % [arrived.size(), expected_order.size(), _first_difference(arrived, expected_order)])


## The tail's completion, as it stood in tail_completed's own frame (THE
## MOVED PIN): the reference's set, every child the reference's to the
## byte, the describe() lines and counts the reference's.
func _check_completion(scheduler: StreamingScheduler, outcome: Dictionary, reference: Dictionary, where: String) -> void:
	var ring: Node = outcome.ring
	var completion: Dictionary = outcome.completion
	if completion.is_empty():
		_ok(false, "", "the tail at %s never completed: %s" % [where, scheduler.describe()])
		return
	_ok(not scheduler.streaming and scheduler.ring == ring and completion.done and completion.whole and completion.streamed == outcome.to_stream and scheduler.chunks_streamed == outcome.to_stream and outcome.to_stream > 0, "the tail at %s completed: the %d chunks left at the handover streamed in, nothing pending" % [where, outcome.to_stream], "the tail: %s; at its completion done %s, whole %s, %d streamed" % [scheduler.describe(), completion.done, completion.whole, completion.streamed])
	var built: Dictionary = completion.snapshot
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
#  The retirement (slice 3)
# =============================================================================

## A Ring's retirement as this test follows it, from the tail's
## completion on: the tail's chunks for a car that started at `at`, by
## this test's own arithmetic on the three job lists' names - every
## streamable job whose box is past R_HANDOVER_M, in the order (builder,
## CHUNK_ORDER), each {key, builder, name, b, k, box} - whether each has a
## child (a near chunk with nothing in it is a job, never a child), which
## are away, the children each builder should hold (the completion's; a
## retirement takes a name out, a rebuild puts it at the end), the
## transitions counted and the chunks rebuilt since the last reset.
func _trip(outcome: Dictionary, reference: Dictionary, lattice_origin: Vector2, at: Vector2) -> Dictionary:
	var ring: Node = outcome.ring
	var first: Dictionary = outcome.completion.snapshot
	var names := {"Terrain": PackedStringArray(), "Forest": PackedStringArray(), "Buildings": PackedStringArray()}
	for job: TerrainBuilder.MeshJob in (ring.get_node("Terrain") as TerrainBuilder).mesh_jobs():
		names.Terrain.append(job.name)
	for job: ForestWalls.MeshJob in (ring.get_node("Forest") as ForestWalls).mesh_jobs():
		names.Forest.append(job.name)
	for job: BuildingsShells.MeshJob in (ring.get_node("Buildings") as BuildingsShells).mesh_jobs():
		names.Buildings.append(job.name)
	var tail: Array = []
	var child := {}
	var standing := {}
	for b: int in STREAMED.size():
		var builder: String = STREAMED[b]
		standing[builder] = first.children[builder].duplicate()
		for k: int in names[builder].size():
			var job_name: String = names[builder][k]
			var box := _chunk_box(builder, job_name, lattice_origin)
			if box.is_empty() or _box_distance(box, at) <= R_HANDOVER_M:
				continue
			var key := builder + "/" + job_name
			tail.append({"key": key, "builder": builder, "name": job_name, "b": b, "k": k, "box": box})
			child[key] = reference.chunks[builder].has(job_name)
	return {"ring": ring, "reference": reference, "first": first, "tail": tail, "child": child, "away": {}, "standing": standing, "retirements": 0, "rebuilds": 0, "rebuilt_once": {}}


## THIS TEST'S OWN STATE MACHINE, one stop of the car at `p`: a chunk
## standing whose box is farther than R_RETIRE_OUT_M retires, in the
## order (builder, CHUNK_ORDER); a chunk away whose box is nearer than
## R_RETIRE_IN_M is rebuilt, in the order (band of BAND_M from `p`,
## builder, CHUNK_ORDER); nothing else moves. Squared distances against
## squared radii, strictly. Returns {retired, rebuilt} as keys in order
## and follows them in `trip`.
func _expect_stop(trip: Dictionary, p: Vector2) -> Dictionary:
	var retired := PackedStringArray()
	var nearer: Array = []
	for chunk: Dictionary in trip.tail:
		var d_sq := _box_distance_squared(chunk.box, p)
		if trip.away.has(chunk.key):
			if d_sq < R_RETIRE_IN_M * R_RETIRE_IN_M:
				nearer.append([int(floor(sqrt(d_sq) / BAND_M)), chunk.b, chunk.k, chunk.key])
		elif d_sq > R_RETIRE_OUT_M * R_RETIRE_OUT_M:
			retired.append(chunk.key)
	nearer.sort_custom(func(x: Array, y: Array) -> bool:
		if x[0] != y[0]:
			return x[0] < y[0]
		if x[1] != y[1]:
			return x[1] < y[1]
		return x[2] < y[2]
	)
	var rebuilt := PackedStringArray()
	for entry: Array in nearer:
		rebuilt.append(entry[3])
	_follow(trip, retired, rebuilt)
	return {"retired": retired, "rebuilt": rebuilt}


## `trip` after these retirements and rebuilds: the chunks away, the
## children each builder should hold, the counts.
func _follow(trip: Dictionary, retired: PackedStringArray, rebuilt: PackedStringArray) -> void:
	for key: String in retired:
		trip.away[key] = true
	for key: String in rebuilt:
		trip.away.erase(key)
	var gone := {}
	for key: String in retired:
		gone[key] = true
	for builder: String in STREAMED:
		var held := PackedStringArray()
		for child_name: String in trip.standing[builder]:
			if not gone.has(builder + "/" + child_name):
				held.append(child_name)
		for key: String in rebuilt:
			if key.get_slice("/", 0) == builder and trip.child[key]:
				held.append(key.get_slice("/", 1))
		trip.standing[builder] = held
	trip.retirements += retired.size()
	trip.rebuilds += rebuilt.size()


## The car put at `p` BY HAND (the scheduler's own processing is off):
## step(p) a frame until a step retires nothing, rebuilds nothing and
## leaves nothing to come - whatever was expected: a scheduler that does
## less fails at once, not at the clock - then INERT_STEPS more in which
## nothing may happen; held against the state machine.
func _stop(scheduler: StreamingScheduler, trip: Dictionary, p: Vector2) -> Dictionary:
	var expected := _expect_stop(trip, p)
	var from := _events.size()
	var at := Vector3(p.x, 0.0, p.y)
	var gave_up := Time.get_ticks_msec() + TAIL_TIMEOUT_MS
	while Time.get_ticks_msec() < gave_up:
		var retired_before := scheduler.chunks_retired
		var rebuilt_before := scheduler.chunks_rebuilt
		scheduler.step(at)
		if scheduler.chunks_retired == retired_before and scheduler.chunks_rebuilt == rebuilt_before and scheduler.chunks_remaining() == 0:
			break
		await process_frame
	for k: int in INERT_STEPS:
		await process_frame
		scheduler.step(at)
	return _held(trip, expected, from)


## What the scheduler did since event `from` against what the state
## machine expected: the retirements and the rebuilds, each list in its
## order; the children under the three builders, name for name in order,
## and Road's the reference's; every rebuilt chunk's child BYTE-IDENTICAL
## to its first build and to the one-shot reference (none for a chunk
## that never had one). {ok, retired, rebuilt, why}.
func _held(trip: Dictionary, expected: Dictionary, from: int) -> Dictionary:
	var retired := PackedStringArray()
	var rebuilt := PackedStringArray()
	for e: int in range(from, _events.size()):
		if _events[e][0] == "retired":
			retired.append(_events[e][1])
		else:
			rebuilt.append(_events[e][1])
	var why := PackedStringArray()
	if retired != expected.retired:
		why.append("%d retired, %d expected, the first difference at %d" % [retired.size(), expected.retired.size(), _first_difference(retired, expected.retired)])
	if rebuilt != expected.rebuilt:
		why.append("%d rebuilt, %d expected, the first difference at %d" % [rebuilt.size(), expected.rebuilt.size(), _first_difference(rebuilt, expected.rebuilt)])
	var children := _children_of(trip.ring)
	for builder: String in STREAMED:
		if children[builder] != trip.standing[builder]:
			why.append("%d children under %s, %d expected, the first difference at %d" % [children[builder].size(), builder, trip.standing[builder].size(), _first_difference(children[builder], trip.standing[builder])])
	if children.Road != trip.reference.children.Road:
		why.append("the children under Road changed")
	for key: String in expected.rebuilt:
		var builder := key.get_slice("/", 0)
		var chunk_name := key.get_slice("/", 1)
		var node: Node = trip.ring.get_node(builder).get_node_or_null(NodePath(chunk_name))
		if trip.child[key]:
			var digest := _digest(node) if node != null else ""
			if digest != trip.reference.chunks[builder][chunk_name] or digest != trip.first.chunks[builder][chunk_name]:
				why.append("%s rebuilt is not its first build's bytes" % key)
				continue
		elif node != null:
			why.append("%s rebuilt has a child it never had" % key)
			continue
		trip.rebuilt_once[key] = true
	return {"ok": why.is_empty(), "retired": expected.retired.size(), "rebuilt": expected.rebuilt.size(), "why": "; ".join(why)}


## The children standing under the three builders that are not the
## reference's child of the same name to the byte, and how many stand.
func _standing_faults(now: Dictionary, reference: Dictionary) -> Dictionary:
	var faults := PackedStringArray()
	var standing := 0
	for builder: String in STREAMED:
		for child_name: String in now.chunks[builder]:
			standing += 1
			if now.chunks[builder][child_name] != reference.chunks[builder].get(child_name, ""):
				faults.append(builder + "/" + child_name)
	return {"faults": faults, "standing": standing}


## (a) at the pit anchor, the scheduler on its own _process along the
## 2 km drive: what it retired and rebuilt around the moving car, event
## by event at the car's place in that frame, then - its processing off,
## the car where it stopped - one stop by hand against the state machine,
## and (e) the tallies. WHEN the tail completed along the drive is the
## wall clock's, so which chunks the band took is too: no count of them
## is printed.
func _check_drive_retirement(scheduler: StreamingScheduler, outcome: Dictionary, reference: Dictionary, lattice_origin: Vector2) -> void:
	if outcome.completion.is_empty():
		return
	# The car stands (the drive left it on the brakes): the retirements
	# for its place happen, the rebuilds in flight land.
	await _step(HOLD_FRAMES)
	var gave_up := Time.get_ticks_msec() + TAIL_TIMEOUT_MS
	while scheduler.chunks_remaining() > 0 and Time.get_ticks_msec() < gave_up:
		await process_frame
	scheduler.set_process(false)
	var trip := _trip(outcome, reference, lattice_origin, PIT_ANCHOR)
	var boxes := {}
	for chunk: Dictionary in trip.tail:
		boxes[chunk.key] = chunk.box
	var faults := PackedStringArray()
	var retirements := 0
	for event: Array in _events:
		var key: String = event[1]
		var one := PackedStringArray([key])
		if not boxes.has(key) or event[2] == null:
			faults.append("%s %s: not a chunk of the tail" % [key, event[0]])
		elif event[0] == "retired":
			retirements += 1
			if trip.away.has(key) or _box_distance_squared(boxes[key], event[2]) <= R_RETIRE_OUT_M * R_RETIRE_OUT_M:
				faults.append("%s retired %.1f m from the car" % [key, _box_distance(boxes[key], event[2])])
			_follow(trip, one, PackedStringArray())
		else:
			if not trip.away.has(key):
				faults.append("%s rebuilt, never retired" % key)
			_follow(trip, PackedStringArray(), one)
	var place: Vector2 = _car_place()
	var stopped := await _stop(scheduler, trip, place)
	_ok(faults.is_empty() and retirements > 0 and stopped.ok, "(a) along the drive at the pit anchor, the scheduler on its own _process: every retirement was of a chunk streamed after the handover whose box was farther than %.0f m from the car in that frame, every rebuild of a chunk retired before; with the car stopped the chunks of the tail away and standing are the ones this test's own arithmetic on the boxes gives, every child that stood at the handover and every child under Road in its place" % R_RETIRE_OUT_M, "%d retirements; %d faults (the first: %s); stopped: %s" % [retirements, faults.size(), faults[0] if not faults.is_empty() else "none", stopped.why])
	var now := _snapshot(trip.ring)
	var bytes := _standing_faults(now, reference)
	var counters: bool = scheduler.chunks_total == outcome.total and scheduler.chunks_at_handover == outcome.at_handover and scheduler.chunks_streamed == outcome.to_stream and scheduler.chunks_retired == trip.retirements and scheduler.chunks_rebuilt == trip.rebuilds and scheduler.chunks_away() == trip.away.size() and scheduler.chunks_retired - scheduler.chunks_rebuilt == scheduler.chunks_away() and scheduler.chunks_remaining() == 0 and scheduler.arrivals == outcome.completion.arrivals
	_ok(now.report == reference.report and bytes.faults.is_empty() and counters, "(e) no count drift along the drive: with chunks retired the four describe() lines and every count are the one-shot build's to the character and the integer still; every child standing is the reference's to the byte; the scheduler's counters only rose - the retirements less the rebuilds are the chunks away, the %d streamable, %d at the handover and %d streamed as they were" % [scheduler.chunks_total, scheduler.chunks_at_handover, scheduler.chunks_streamed], "report equal %s; %d children differ (the first: %s); the scheduler %s against %d retirements, %d rebuilds, %d away" % [now.report == reference.report, bytes.faults.size(), bytes.faults[0] if not bytes.faults.is_empty() else "none", scheduler.describe(), trip.retirements, trip.rebuilds, trip.away.size()])


## (a) the standing car at a corner, the scheduler on its own _process:
## the streamed chunks past R_RETIRE_OUT_M retire once the tail has
## completed - freed, in order, the tallies unmoved. Leaves the
## scheduler's own processing OFF: the stops after this are by hand.
func _check_standing_retirement(scheduler: StreamingScheduler, outcome: Dictionary, trip: Dictionary, at: Vector2, where: String) -> void:
	var expected := _expect_stop(trip, at)
	var gave_up := Time.get_ticks_msec() + TAIL_TIMEOUT_MS
	while scheduler.chunks_retired < expected.retired.size() and Time.get_ticks_msec() < gave_up:
		await process_frame
	await _step(INERT_STEPS)
	scheduler.set_process(false)
	var held := _held(trip, expected, 0)
	# The car stood where this test's arithmetic has it: nearer its place
	# than the nearest box is to the radius.
	var margin := INF
	for chunk: Dictionary in trip.tail:
		margin = minf(margin, absf(_box_distance(chunk.box, at) - R_RETIRE_OUT_M))
	var place: Vector2 = _car_place()
	var drift := place.distance_to(at)
	for event: Array in _events:
		drift = maxf(drift, (event[2] as Vector2).distance_to(at) if event[2] != null else INF)
	# What the completion held: a retired chunk's node and mesh are dead,
	# every other child's alive.
	var freed := 0
	var alive := 0
	var wrong := 0
	for key: String in outcome.completion.handles:
		var handle: Dictionary = outcome.completion.handles[key]
		var node_lives := is_instance_id_valid(handle.id)
		var mesh_lives: bool = handle.mesh.get_ref() != null
		if trip.away.has(key) and not node_lives and not mesh_lives:
			freed += 1
		elif not trip.away.has(key) and node_lives and mesh_lives:
			alive += 1
		else:
			wrong += 1
	_ok(held.ok and held.retired > 0 and held.rebuilt == 0 and drift < margin and wrong == 0 and freed > 0 and scheduler.chunks_retired == held.retired and scheduler.chunks_rebuilt == 0 and scheduler.chunks_away() == held.retired and scheduler.chunks_remaining() == 0, "(a) the standing car at %s, the scheduler on its own _process: once the tail completed, the %d streamed chunks whose box is farther than %.0f m retired, in the order (builder, CHUNK_ORDER) - the %d of them with a mesh freed (the MeshInstance3D and its ArrayMesh both dead), nothing rebuilt; the other %d streamed chunks and every child of the handover stand (%d meshes alive); the scheduler's retired counter %d; the nearest box %.1f m off the radius, the car nearer its place than that" % [where, held.retired, R_RETIRE_OUT_M, freed, trip.tail.size() - held.retired, alive, scheduler.chunks_retired, margin], "%s; the scheduler %s; drift %.3f m against a margin of %.3f m; %d freed, %d alive, %d wrong" % [held.why, scheduler.describe(), drift, margin, freed, alive, wrong])
	var now := _snapshot(trip.ring)
	var bytes := _standing_faults(now, trip.reference)
	_ok(now.report == trip.reference.report and bytes.faults.is_empty(), "(a) the retirement at %s took no tally and touched no other child: the four describe() lines and every count are the one-shot build's to the character and the integer still, and each of the %d children standing under Terrain, Forest and Buildings is the reference's to the byte" % [where, bytes.standing], "report equal %s; %d children differ (the first: %s)" % [now.report == trip.reference.report, bytes.faults.size(), bytes.faults[0] if not bytes.faults.is_empty() else "none"])


## (b) away to the other corner and back, by hand; and the band between
## the radii from home after it, by this test's own arithmetic: chunks
## standing there that the trip never took, chunks retired there that the
## return did not bring back.
func _check_away_and_back(scheduler: StreamingScheduler, trip: Dictionary, corner: Dictionary, other: Dictionary) -> void:
	var there := await _stop(scheduler, trip, other.at)
	var back := await _stop(scheduler, trip, corner.at)
	var stood := 0
	var stayed_away := 0
	for chunk: Dictionary in trip.tail:
		var d := _box_distance(chunk.box, corner.at)
		if d >= R_RETIRE_IN_M and d <= R_RETIRE_OUT_M:
			if trip.away.has(chunk.key):
				stayed_away += 1
			else:
				stood += 1
	_ok(there.ok and back.ok and there.retired > 0 and there.rebuilt > 0 and back.rebuilt > 0 and stood > 0 and stayed_away > 0, "(b) away to %s and back BY HAND: there %d chunks retired and %d were rebuilt, back at %s %d retired and %d were rebuilt - each rebuild through the scheduler's pending set in the pinned order (the band of %.0f m from the car, then the builder, then CHUNK_ORDER), its child BYTE-IDENTICAL to its first build and to the one-shot reference; in the band between %.0f m and %.0f m of %s nothing moved on the return: %d chunks stand there that the trip never took, %d stay retired that it did" % [other.name, there.retired, there.rebuilt, corner.name, back.retired, back.rebuilt, BAND_M, R_RETIRE_IN_M, R_RETIRE_OUT_M, corner.name, stood, stayed_away], "there: %s (%d retired, %d rebuilt); back: %s (%d retired, %d rebuilt); in the band %d standing, %d away" % [there.why, there.retired, there.rebuilt, back.why, back.retired, back.rebuilt, stood, stayed_away])


## (c) the two radii on one chunk's own box - the tail's first forest
## chunk with a mesh - the car put west of its western edge at WALK_M,
## level with its middle: the box distance is the walk's number exactly.
func _check_radii(scheduler: StreamingScheduler, trip: Dictionary) -> void:
	var chunk := {}
	for candidate: Dictionary in trip.tail:
		if candidate.builder == "Forest" and trip.child[candidate.key]:
			chunk = candidate
			break
	if chunk.is_empty():
		_ok(false, "", "no forest chunk in the tail to walk the radii on")
		return
	var faults := PackedStringArray()
	var retired := 0
	var rebuilt := 0
	for s: int in WALK_M.size():
		var p := Vector2(chunk.box[0] - WALK_M[s], (chunk.box[1] + chunk.box[3]) * 0.5)
		if _box_distance(chunk.box, p) != WALK_M[s]:
			faults.append("the stop at %.0f m is %.6f m from the box" % [WALK_M[s], _box_distance(chunk.box, p)])
		var held := await _stop(scheduler, trip, p)
		if not held.ok:
			faults.append("at %.0f m: %s" % [WALK_M[s], held.why])
		var stands: bool = trip.ring.get_node(chunk.builder).has_node(NodePath(chunk.name))
		if stands != WALK_STANDS[s] or trip.away.has(chunk.key) == WALK_STANDS[s]:
			faults.append("at %.0f m (stop %d) the chunk %s" % [WALK_M[s], s, "stands" if stands else "is away"])
		retired += held.retired
		rebuilt += held.rebuilt
	_ok(faults.is_empty(), "(c) the two radii BY HAND on %s's own box, the car west of its edge: the chunk stands at 2999 m, at 3750 m, at 4499 m and at %.0f m exactly; is retired at 4501 m; is retired still back at %.0f m, at 3750 m - where it stood on the way out - at 3001 m and at %.0f m exactly; is rebuilt at 2999 m, to the byte. At each of the %d stops every other chunk of the tail moved as this test's own arithmetic on its box says (%d retirements, %d rebuilds in all)" % [chunk.key, R_RETIRE_OUT_M, R_RETIRE_OUT_M, R_RETIRE_IN_M, WALK_M.size(), retired, rebuilt], "%d faults on %s: %s" % [faults.size(), chunk.get("key", ""), "; ".join(faults)])


## (d) 40 km off, the handover's Ring again; (b) from there the sweep: a
## SWEEP_M lattice of stops across the box of the tail's chunks, row by
## row, and home - every chunk of the tail rebuilt at least once.
func _check_sweep(scheduler: StreamingScheduler, outcome: Dictionary, trip: Dictionary, corner: Dictionary) -> void:
	var far := await _stop(scheduler, trip, NOWHERE)
	var children := _children_of(trip.ring)
	var handed := 0
	var as_handed: bool = far.ok and trip.away.size() == trip.tail.size() and scheduler.chunks_away() == trip.tail.size() and children.Road == trip.reference.children.Road
	for builder: String in STREAMED:
		as_handed = as_handed and children[builder] == outcome.children[builder]
		handed += children[builder].size()
	_ok(as_handed, "(d) nothing but the tail's chunks ever retires: with the car %.0f km off every one of the %d chunks streamed after the handover is retired and the Ring is the handover's Ring again, name for name in its order - the %d children under Terrain, Forest and Buildings that stood at the handover (the resident set and the vicinity's %d chunks, never the scheduler's) and all %d under Road" % [NOWHERE.length() / 1000.0, trip.tail.size(), handed, outcome.at_handover, children.Road.size()], "%s; %d away of %d; the scheduler %s" % [far.why, trip.away.size(), trip.tail.size(), scheduler.describe()])
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for chunk: Dictionary in trip.tail:
		lo = Vector2(minf(lo.x, chunk.box[0]), minf(lo.y, chunk.box[1]))
		hi = Vector2(maxf(hi.x, chunk.box[2]), maxf(hi.y, chunk.box[3]))
	trip.rebuilt_once = {}
	var faults := PackedStringArray()
	var stops := 0
	var retired := 0
	var rebuilt := 0
	var z := lo.y + SWEEP_M * 0.5
	while z - SWEEP_M * 0.5 < hi.y:
		var x := lo.x + SWEEP_M * 0.5
		while x - SWEEP_M * 0.5 < hi.x:
			var held := await _stop(scheduler, trip, Vector2(x, z))
			if not held.ok:
				faults.append("at (%.0f, %.0f): %s" % [x, z, held.why])
			stops += 1
			retired += held.retired
			rebuilt += held.rebuilt
			x += SWEEP_M
		z += SWEEP_M
	var home := await _stop(scheduler, trip, corner.at)
	_ok(faults.is_empty() and home.ok and trip.rebuilt_once.size() == trip.tail.size() and not trip.tail.is_empty(), "(b) the sweep BY HAND, from there over the %d stops of a %.0f m lattice across the tail's chunks and back to %s: every one of the %d chunks of the tail was retired and rebuilt at least once (%d rebuilds and %d retirements on the way), each rebuild through the scheduler's pending set in the pinned order, its child BYTE-IDENTICAL to its first build and to the one-shot reference" % [stops, SWEEP_M, corner.name, trip.tail.size(), rebuilt + home.rebuilt, retired + home.retired], "%d of %d chunks rebuilt over %d stops; %d faults (the first: %s); home: %s" % [trip.rebuilt_once.size(), trip.tail.size(), stops, faults.size(), faults[0] if not faults.is_empty() else "none", home.why])


## (e) no count drift after the whole trip: the builders' lines and
## counts the reference's, every child standing the reference's to the
## byte, the scheduler's counters this test's own sums.
func _check_no_drift(scheduler: StreamingScheduler, outcome: Dictionary, trip: Dictionary, where: String) -> void:
	var now := _snapshot(trip.ring)
	var bytes := _standing_faults(now, trip.reference)
	var counters: bool = scheduler.chunks_total == outcome.total and scheduler.chunks_at_handover == outcome.at_handover and scheduler.chunks_streamed == outcome.to_stream and scheduler.chunks_retired == trip.retirements and scheduler.chunks_rebuilt == trip.rebuilds and scheduler.chunks_away() == trip.away.size() and scheduler.chunks_retired - scheduler.chunks_rebuilt == scheduler.chunks_away() and scheduler.chunks_remaining() == 0 and scheduler.arrivals == outcome.completion.arrivals
	_ok(now.report == trip.reference.report and bytes.faults.is_empty() and counters and trip.rebuilds > 0, "(e) no count drift at %s after %d retirements and %d rebuilds: the four describe() lines and every count are the one-shot build's to the character and the integer still; the scheduler's counters only rose - %d streamable chunks, %d at the handover and %d streamed as at the tail's completion, %d retired, %d rebuilt, %d away now (%d - %d); each of the %d children standing is the reference's to the byte" % [where, trip.retirements, trip.rebuilds, scheduler.chunks_total, scheduler.chunks_at_handover, scheduler.chunks_streamed, scheduler.chunks_retired, scheduler.chunks_rebuilt, scheduler.chunks_away(), scheduler.chunks_retired, scheduler.chunks_rebuilt, bytes.standing], "report equal %s; %d children differ (the first: %s); the scheduler %s against %d retirements, %d rebuilds, %d away" % [now.report == trip.reference.report, bytes.faults.size(), bytes.faults[0] if not bytes.faults.is_empty() else "none", scheduler.describe(), trip.retirements, trip.rebuilds, trip.away.size()])


## The car's (x, z) in the current scene, or null where there is none.
func _car_place() -> Variant:
	if current_scene == null:
		return null
	var car := current_scene.get_node_or_null("Car") as Node3D
	if car == null:
		return null
	return Vector2(car.global_position.x, car.global_position.z)


## The instance id of every MeshInstance3D child under the three streamed
## builders and a weak reference to its mesh, by "<Builder>/<name>".
func _handles(ring: Node) -> Dictionary:
	var handles := {}
	for builder: String in STREAMED:
		for child: Node in ring.get_node(builder).get_children():
			if child is MeshInstance3D and (child as MeshInstance3D).mesh != null:
				handles[builder + "/" + String(child.name)] = {"id": child.get_instance_id(), "mesh": weakref((child as MeshInstance3D).mesh)}
	return handles


## A node and everything under it, counted.
func _count_nodes(node: Node) -> int:
	var n := 1
	for child: Node in node.get_children():
		n += _count_nodes(child)
	return n


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
			digests[String(child.name)] = _digest(child)
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


## The SHA-256 of one child and everything under it, in hex.
func _digest(child: Node) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	_hash_node(context, child)
	return context.finish().hex_encode()


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


## The same distance squared (the retire band's comparisons are on
## squares, as the bubble's).
func _box_distance_squared(box: PackedFloat64Array, at: Vector2) -> float:
	var dx := maxf(0.0, maxf(box[0] - at.x, at.x - box[2]))
	var dz := maxf(0.0, maxf(box[1] - at.y, at.y - box[3]))
	return dx * dx + dz * dz


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
