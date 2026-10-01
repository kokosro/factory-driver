extends SceneTree
## Headless async build test (LOADING-1; decisions.org C07BE6F1, the
## driver's canon of 2026-09-27: "no freezing load" - the Ring behind a
## real loading screen, its build off the main thread). Run via
## tests/run_tests.sh, or:
##
##   godot --headless --path . --import
##   godot --headless --path . --script res://tests/async_build_test.gd
##
## Builds the Ring twice: once the way every other test loads it (the
## scene instanced and added, its builders building synchronously in
## _ready: the reference) and once through scenes/loading.tscn - the
## loading scene instanced under the root with the Ring as its target,
## its pipeline driven by _process (RoadBuilder.prepare_data and the
## sweeps, TerrainBuilder.compute_fields and its mesh jobs,
## ForestWalls.place and its chunk jobs on WorkerThreadPool tasks in
## CHUNK_ORDER; the node stages on the main thread over frames; the
## handover) - and holds the two against each other:
##
##   (a) DETERMINISM (re-scoped by L2-STREAMING-1, THE MOVED PINS below):
##       AT THE HANDOVER the children under Road are the reference's
##       names in the reference's order, and the children under Terrain,
##       Forest and Buildings are the reference's order held to the
##       resident set and the car's vicinity (this test's own arithmetic
##       on the chunk names: a 1 km chunk whose box is within 2 000 m of
##       the car), the far chunks absent; every child standing at the
##       handover is the reference's child of that name to the byte
##       (SHA-256 per chunk). AT THE TAIL'S COMPLETION the builders'
##       describe() lines, their counts and the road's seven counters
##       equal the reference's to the character and the integer, the
##       children are the reference's set, the streamed ones after the
##       handover's in the scheduler's (band, builder, CHUNK_ORDER) order
##       for the standing car, every child the reference's to the byte,
##       and a SHA-256 over every mesh's surface arrays (vertices,
##       normals, UVs, colours, indices) and every collider's faces (the
##       strips' trimeshes, the trunk prisms, the floor slab's box), the
##       children walked in the reference's order, equal per builder -
##       the async build's meshes are the sync build's to the byte. The
##       digests' first sixteen hex characters are printed: the pin;
##   (b) THE PROGRESS: every stage's chunks counted - the sweep group's
##       total the road count and the road node stage's total the same,
##       the terrain's, the forest's and the buildings' group totals the
##       resident jobs plus the vicinity's chunks of their mesh_jobs()
##       (counted here from the job names) and their node stages' totals
##       the same, every stage's done equal to its total at the handover,
##       the scheduler's counters the same arithmetic - and the bar's
##       fraction never falling from one frame to the next, 1.0 at the
##       handover, the percent label at 100 %;
##   (c) THE MAIN THREAD NEVER BLOCKS: this script measures the wall-clock
##       delta between consecutive process frames from outside the loading
##       scene, from the frame the scene is added to two frames after the
##       handover (the enter-tree of the built Ring included), and holds
##       the longest under FRAME_CEILING_MS; the loading scene's own
##       per-frame deltas the same; and every frame of the streaming tail
##       after that under the same ceiling. The numbers are printed only
##       on a failure (or with FD_LOADING_FRAMES=1): the suite's lines
##       are the same on every machine;
##   (d) THE HANDOVER: the Ring is the tree's current scene at its own
##       scene path, its car on the road's profile (the same object, a
##       WorldRoadProfile: the ring drive test's pin holds across the
##       handover, the Surfaces node swapping in its wrapper at its first
##       tick as ever), the loading scene freed;
##   (e) THE SETTING AND THE ROUTE: application/use_async_build reads true
##       (the game's default) and LoadingScreen.routes says the Ring goes
##       through the screen and the pad does not; with the setting false
##       the Ring goes direct (restored after);
##   (f) THE FALLBACK: a loading scene pointed at a scene with no builders
##       (scenes/car.tscn) says so (fallback_reason, one push_warning),
##       and hands over that scene built the ordinary way as the current
##       scene - never a broken scene;
##   (g) THE ABANDONMENT: a loading scene freed while its stages run
##       cancels and waits for its tasks and drops its partial Ring - the
##       root holds what it held before, nothing of the Ring left under
##       it.
## Exits 0 on success, 1 on any failed check.
##
## THE PINS' HISTORY (the digests and counts this test printed, the
## reference build's; the checks compare the two builds, never a
## literal): LOADING-1 - Road 0affd901536981e0 (3 304 meshes, 3 305
## shapes), Terrain 5fe56671536fbd58 (3 352 meshes; 1 855 846 vertices,
## 3 111 171 triangles), Forest 37d8d855599b8de2 (84 meshes, 42 shapes).
## ROAD-3 (the carve and the road body; was -> those): Road
## dfa68bb59bdb78c7 (6 608 meshes: a Skirt_<id> MeshInstance3D beside
## every strip, the 3 305 shapes the same - the strips' trimeshes and the
## floor's box untouched, the road's describe() and seven counters
## byte-identical: 3 304 roads, 361 393 sections, 1 085 645 vertices,
## 1 435 286 triangles, 3 304 bodies), Terrain f3d51da12b5f6547 (the
## same 3 352 meshes; 2 772 530 vertices, 4 466 373 triangles: the
## platform strips' ten columns, was six, no quad across the paved
## width, and 331 888 vertices capped under other roads' footprints),
## Forest 37d8d855599b8de2 unchanged. The Road digest now covers
## the skirts' surfaces too, in child order (Strip_, Body_, Skirt_ per
## road) - 9 913 children under Road, was 6 609. ROAD-4 (the zone,
## the own cap and the step cap in TerrainBuilder.strip_caps; was ->
## Terrain f3d51da12b5f6547): Terrain b5646e3bd1f1a7a8 (the same 3 352
## meshes, 2 772 530 vertices and 4 466 373 triangles; 361 787 vertices
## capped, was 331 888), Road dfa68bb59bdb78c7 and Forest
## 37d8d855599b8de2 unchanged.
## ROAD-6 (217 selected side tracks 3 -> 5 m): Road a76bb21a8ba8d268,
## Terrain cee78c6ead17be04, Forest ec3096859e758d72. Mesh/shape counts
## remain 6608/3305, 3352, 84/42. Width changes the road twist subdivision,
## terrain carve/caps and the field heights used by forest geometry. The
## full hashes still compare independently built sync and async arrays.
## ROAD-5 (loop lip and 92 rumble meshes): Road a76bb21a8ba8d268 ->
## af1cd69f426516cc, meshes 6608 -> 6700, shapes unchanged at 3305;
## Road children 9913 -> 10005. New bands: 135444 vertices / 179856
## triangles, counted separately from the unchanged paved platform.
## Terrain cee78c6ead17be04 -> 5c5ee1f6ba4d1b4a (3352 meshes unchanged,
## cap count 364819 -> 364933); Forest ec3096859e758d72 ->
## 3241b4b76c9e000a (84 meshes / 42 shapes unchanged). Their vertices
## sample the changed shoulder field. No literal pin was relaxed: every
## array, collider and child order still compares sync against async.

## 4B-8: the stage pin was 9 -> 13 (four Buildings stages); builder
## comparisons were Road/Terrain/Forest -> those plus Buildings. Existing
## arrays/children/colliders remain compared, and Buildings adds its own
## complete digest, counts and describe() comparison. No old pin relaxed.
## Measured before the continuation-height correction: Buildings
## 9d14a5ceeeb1a49d, 227 meshes / 12 shapes, 240
## children, 586254 vertices / 195418 triangles. Continuation-height fix
## changes Buildings to c91220c9e775c1da; counts remain the same. Road af1cd69f426516cc,
## Terrain 5c5ee1f6ba4d1b4a, Forest 3241b4b76c9e000a unchanged.

## ROAD-7 / F1-COLLISION-1 (all covered non-loop roads >=5 m;
## rails 1.5 m outside pavement, 44 exit gaps and bubbled F1 solids):
## Road af1cd69f426516cc -> e84b7f4c3a8ef510;
## Terrain 5c5ee1f6ba4d1b4a -> 787f0642584fd0bb;
## Forest 3241b4b76c9e000a -> 9082e0a1bdf6f057;
## Buildings c91220c9e775c1da -> 1ef2afe47edc751e.
## Road sections 369357 -> 441723, vertices 1109537 -> 1326635,
## triangles 1467142 -> 1756606; 3304 roads and the rumble census unchanged.
## Terrain now 2766897 vertices / 4456307 triangles, 388003 capped vertices;
## Forest now 2598435 vertices / 2183322 triangles, 19379 trunks / 42 bodies.
## Buildings 227 meshes unchanged, shapes 12 -> 33, children 240 -> 261,
## jobs per chunk stage 239 -> 260, vertices 586254 -> 567138,
## triangles 195418 -> 189046. Full digests still compare independent
## sync/async arrays and faces, with all thirteen stages and the 250 ms gate.

## L2-STREAMING-1 (slices 1+2, the thin handover; the ruling FD79B028) -
## THE MOVED PINS, each was -> now; no digest value changed (Road
## 76ddab80073fbd2b, Terrain 2a778a385fdf94e8, Forest 9082e0a1bdf6f057,
## Buildings 1ef2afe47edc751e as before), no build changed, only WHEN the
## far chunks arrive:
##   - the describe() lines and the counts: was -> all four builders'
##     equal the reference's at the handover; now -> Road's at the
##     handover, all four at the tail's completion (a streamed builder's
##     counts are merged per add: at the handover they are the base's and
##     the vicinity's);
##   - the children: was -> under all four builders the reference's names
##     in the reference's order at the handover; now -> Road's so at the
##     handover; Terrain's, Forest's and Buildings' at the handover the
##     reference's order filtered to the resident set and the 2 000 m
##     vicinity (computed here, not asked of the scheduler), at least one
##     far chunk absent per builder; at completion the same set as the
##     reference, the streamed children appended in the pinned
##     (band, builder, CHUNK_ORDER) order;
##   - the digests: was -> one SHA-256 per builder over its children in
##     child order, equal at the handover; now -> one SHA-256 per CHILD
##     equal to the reference's child of that name, for the handover's
##     set and for every child at completion, and the per-builder SHA-256
##     over the children walked in the REFERENCE's order equal at
##     completion (the same bytes in the same order as before: the
##     printed digests are the old ones);
##   - the stage totals: was -> terrain / forest / buildings group and
##     node totals their whole mesh_jobs() sizes; now -> the resident
##     jobs plus the vicinity's chunks, counted here from the job names;
##     the road's two totals, the five serial stages, the count of
##     thirteen and the bar's monotonic rise to 100 % at the handover
##     are unchanged;
##   - (c) gains the tail's frames under the same ceiling; (g) gains the
##     scheduler's claim released. Both additive.
## Measured at this landing: 353 streamable chunks, 94 at the handover,
## 259 streamed after it.

const RING_SCENE := "res://scenes/eifel_ring.tscn"
const PAD_SCENE := "res://scenes/main.tscn"
const CAR_SCENE := "res://scenes/car.tscn"

## Process frames to let a scene settle after the add.
const SETTLE_FRAMES := 5

## The longest process frame the main thread may take during the async
## load [ms] (c): measured on this machine 2026-09-27 (headless, the
## suite's conditions) - the loading scene's own longest frame 53-55 ms
## over three runs (a frame beside two running data stages: the
## interpreter's threads contend with the main thread's own GDScript;
## the node-stage slices themselves stay near their 8 ms budget), the
## frame of the handover (13 579 nodes entering the tree) 96-98 ms from
## outside - so 250 ms holds both with room for a loaded machine (the
## suite's --parallel runs twenty-eight godots at once), and is a
## seventieth of the 17 s the synchronous build held the main thread
## for, the thing the canon forbids.
const FRAME_CEILING_MS := 250.0

## Wall-clock cap on a load before the test gives up [ms] (the async
## build takes about 17 s here; never printed).
const LOAD_TIMEOUT_MS := 300000

## Frames the abandonment check lets the stages run before it frees the
## loading scene (the prepare task runs for about two seconds: the
## sweep group is running by then).
const ABANDON_AFTER_FRAMES := 240

## L2-STREAMING-1, this test's own copy of the ruling's numbers (not read
## from the scheduler: a change there fails here): the vicinity built
## before the handover [m], the chunk and the band [m].
const R_HANDOVER_M := 2000.0
const CHUNK_M := 1000.0
const BAND_M := 1000.0
## The builders that stream, in the scheduler's rank order.
const STREAMED: Array[String] = ["Terrain", "Forest", "Buildings"]
## Wall-clock cap on the tail before the test gives up [ms] (it takes a
## second or two here; never printed).
const TAIL_TIMEOUT_MS := 120000

var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	print("-- the synchronous build (the reference)")
	var sync_ring := await _load_sync()
	if sync_ring == null:
		_finish()
		return
	var sync_report := _report_of(sync_ring)
	var sync_children := _children_of(sync_ring)
	var sync_hashes := _hashes_of(sync_ring, sync_children)
	_ok(sync_report.road.road_count > 0 and sync_report.terrain.counts.vertices > 0 and sync_report.forest.counts.trees > 0, "the reference built in _ready: %s | %s | %s" % [sync_report.road.describe, sync_report.terrain.describe, sync_report.forest.describe])
	root.remove_child(sync_ring)
	sync_ring.free()
	await _step(2)
	var root_children_before := root.get_child_count()

	print("-- the asynchronous build (the loading scene)")
	var outcome := await _load_async(RING_SCENE)
	var ring: Node = outcome.ring
	_ok(ring != null and ring.scene_file_path == RING_SCENE and current_scene == ring and not is_instance_valid(outcome.loading), "the loading scene handed over: the current scene is %s, the loading scene freed" % (ring.scene_file_path if ring else "none"), "ring %s, current %s, loading valid %s" % [ring, current_scene, is_instance_valid(outcome.loading)])
	if ring == null:
		_finish()
		return
	await _await_tail(outcome)
	_check_determinism(ring, outcome, sync_report, sync_hashes, sync_children)
	_check_progress(ring, outcome)
	_check_frames(outcome)
	_check_handover(ring, outcome)
	unload_current_scene()
	await _step(2)
	_ok(current_scene == null and root.get_child_count() == root_children_before, "the Ring unloaded again; the root holds what it held before the async load", "current %s, root children %d (was %d)" % [current_scene, root.get_child_count(), root_children_before])

	print("-- the setting and the route")
	_check_setting()
	print("-- the fallback")
	await _check_fallback()
	print("-- the abandonment")
	await _check_abandonment(root_children_before)
	_finish()


# =============================================================================
#  The two builds
# =============================================================================

func _load_sync() -> Node:
	var packed: PackedScene = load(RING_SCENE)
	if packed == null:
		_ok(false, "", "the ring scene does not load")
		return null
	var scene := packed.instantiate()
	root.add_child(scene)
	await _step(SETTLE_FRAMES)
	return scene


## The loading scene added under the root with `target` as its scene,
## every process frame's wall-clock delta measured from here until two
## frames after the handover; what the scene reported, captured in the
## handover's own frame before the scene is freed.
func _load_async(target: String) -> Dictionary:
	LoadingScreen.target_scene = target
	var loading: LoadingScreen = (load(LoadingScreen.SCENE) as PackedScene).instantiate()
	var outcome := {"loading": loading, "ring": null, "deltas": PackedFloat64Array(), "internal": PackedFloat64Array(), "stages": {}, "progress": PackedFloat64Array(), "percent": "", "step": "", "fallback": "", "bar": false, "warnings": 0, "children": {}, "road": {}, "start": Vector3.ZERO, "at_handover": 0, "to_stream": 0, "streamable": 0, "tail_deltas": PackedFloat64Array(), "tail_done": false, "arrivals": PackedStringArray(), "streamed": 0}
	loading.handed_over.connect(func(built: Node) -> void:
		outcome.ring = built
		# L2-STREAMING-1: what stands at the handover, taken in its own
		# frame before the tail's first chunk (names and counters only:
		# the bytes are hashed after the tail, a child never changes).
		if built.get_node_or_null("Road") is RoadBuilder and built.get_node_or_null("Buildings") != null:
			outcome.children = _children_of(built)
			outcome.road = _road_report_of(built.get_node("Road"))
			outcome.start = (built.get_node("Car") as Node3D).global_position
			var scheduler := StreamingScheduler.of(self)
			if scheduler != null:
				outcome.at_handover = scheduler.chunks_at_handover
				outcome.streamable = scheduler.chunks_total
				outcome.to_stream = scheduler.chunks_remaining()
		outcome.internal = loading.frame_deltas_ms.duplicate()
		outcome.stages = loading.stages_report()
		outcome.percent = loading.get_node("Frame/Column/Percent").text
		outcome.step = loading.step_name
		outcome.fallback = loading.fallback_reason
		outcome.bar = loading.get_node("Frame/Column/Bar") is ProgressBar and (loading.get_node("Frame/Column/Bar") as ProgressBar).value == 100.0
	)
	var last := Time.get_ticks_usec()
	var gave_up := Time.get_ticks_msec() + LOAD_TIMEOUT_MS
	root.add_child(loading)
	var after := 0
	while after < 2 and Time.get_ticks_msec() < gave_up:
		await process_frame
		var now := Time.get_ticks_usec()
		outcome.deltas.append(float(now - last) / 1000.0)
		last = now
		if is_instance_valid(loading) and outcome.ring == null:
			outcome.progress.append(loading.progress)
		if outcome.ring != null:
			after += 1
	return outcome


## L2-STREAMING-1: the streaming tail waited for, every process frame's
## wall-clock delta measured; the scheduler's arrival order and counter
## kept.
func _await_tail(outcome: Dictionary) -> void:
	var scheduler := StreamingScheduler.of(self)
	if scheduler == null:
		return
	var last := Time.get_ticks_usec()
	var gave_up := Time.get_ticks_msec() + TAIL_TIMEOUT_MS
	while scheduler.streaming and Time.get_ticks_msec() < gave_up:
		await process_frame
		var now := Time.get_ticks_usec()
		outcome.tail_deltas.append(float(now - last) / 1000.0)
		last = now
	outcome.tail_done = not scheduler.streaming and scheduler.ring == outcome.ring and scheduler.chunks_remaining() == 0
	outcome.arrivals = scheduler.arrivals.duplicate()
	outcome.streamed = scheduler.chunks_streamed


# =============================================================================
#  The checks
# =============================================================================

func _check_determinism(ring: Node, outcome: Dictionary, sync_report: Dictionary, sync_hashes: Dictionary, sync_children: Dictionary) -> void:
	var start: Vector3 = outcome.start
	var terrain: TerrainBuilder = ring.get_node("Terrain")
	# AT THE HANDOVER (what the handover's own frame held).
	var handed: Dictionary = outcome.children
	_ok(not handed.is_empty() and handed.Road == sync_children.Road and outcome.road == sync_report.road, "(a) at the handover the road is whole: the children under Road (%d) the reference's names in the reference's order, its describe() line and seven counters the reference's (every strip, collider and the floor resident)" % sync_children.Road.size(), "handed %d Road children, the reference %d; road %s vs %s" % [handed.get("Road", PackedStringArray()).size(), sync_children.Road.size(), outcome.road, sync_report.road])
	var thin := not handed.is_empty()
	var absent := {}
	var expected_handed := {}
	for builder: String in STREAMED:
		var expected := PackedStringArray()
		absent[builder] = 0
		for child_name: String in sync_children[builder]:
			if _built_before_handover(builder, child_name, terrain, start):
				expected.append(child_name)
			else:
				absent[builder] += 1
		expected_handed[builder] = expected
		thin = thin and handed.get(builder, PackedStringArray()) == expected and absent[builder] > 0
	_ok(thin, "(a) at the handover the children under Terrain (%d of %d), Forest (%d of %d) and Buildings (%d of %d) are the reference's names in the reference's order held to the resident set and the chunks whose box is within %.0f m of the car: CHUNK_ORDER held, the %d / %d / %d far chunks absent" % [expected_handed.Terrain.size(), sync_children.Terrain.size(), expected_handed.Forest.size(), sync_children.Forest.size(), expected_handed.Buildings.size(), sync_children.Buildings.size(), R_HANDOVER_M, absent.Terrain, absent.Forest, absent.Buildings], "handed %d / %d / %d children, expected %d / %d / %d; absent %s" % [handed.get("Terrain", PackedStringArray()).size(), handed.get("Forest", PackedStringArray()).size(), handed.get("Buildings", PackedStringArray()).size(), expected_handed.Terrain.size(), expected_handed.Forest.size(), expected_handed.Buildings.size(), absent])
	# AT THE TAIL'S COMPLETION.
	_ok(outcome.tail_done, "(a) the streaming tail completed: every far chunk streamed in after the handover, nothing pending, the scheduler still on this Ring", "the tail did not complete: %s" % (StreamingScheduler.of(self).describe() if StreamingScheduler.of(self) != null else "no scheduler"))
	var report := _report_of(ring)
	_ok(report.buildings == sync_report.buildings, "(a) Buildings describe/counts/elements equal the reference: %s" % report.buildings.describe)
	_ok(report.road.describe == sync_report.road.describe and report.terrain.describe == sync_report.terrain.describe and report.forest.describe == sync_report.forest.describe, "(a) the three describe() lines equal the reference's: %s | %s | %s" % [report.road.describe, report.terrain.describe, report.forest.describe], "async %s | %s | %s" % [report.road.describe, report.terrain.describe, report.forest.describe])
	_ok(report.road.counters == sync_report.road.counters and report.terrain.counts == sync_report.terrain.counts and report.forest.counts == sync_report.forest.counts and report.terrain.elements == sync_report.terrain.elements and report.forest.elements == sync_report.forest.elements, "(a) the road's seven counters, the terrain's and the forest's counts and element tallies equal the reference's", "road %s vs %s, terrain %s vs %s, forest %s vs %s, elements %s / %s vs %s / %s" % [report.road.counters, sync_report.road.counters, report.terrain.counts, sync_report.terrain.counts, report.forest.counts, sync_report.forest.counts, report.terrain.elements, report.forest.elements, sync_report.terrain.elements, sync_report.forest.elements])
	var children := _children_of(ring)
	var same_set: bool = children.Road == sync_children.Road
	for builder: String in STREAMED:
		var sorted_async := Array(children[builder])
		var sorted_sync := Array(sync_children[builder])
		sorted_async.sort()
		sorted_sync.sort()
		same_set = same_set and sorted_async == sorted_sync
	_ok(same_set, "(a) at the tail's completion the children under Road (%d), Terrain (%d), Forest (%d) and Buildings (%d) are the reference's set, name for name" % [children.Road.size(), children.Terrain.size(), children.Forest.size(), children.Buildings.size()], "async %d / %d / %d / %d, sync %d / %d / %d / %d" % [children.Road.size(), children.Terrain.size(), children.Forest.size(), children.Buildings.size(), sync_children.Road.size(), sync_children.Terrain.size(), sync_children.Forest.size(), sync_children.Buildings.size()])
	# The streamed children's order: this test's own sort of the far
	# chunks by (band from the standing car, builder, the reference's
	# child index - CHUNK_ORDER), against the scheduler's arrivals and the
	# children as they stand after the handover's.
	var expected_arrivals: Array = []
	var index_of := {}
	for b: int in STREAMED.size():
		var builder: String = STREAMED[b]
		for k: int in sync_children[builder].size():
			var child_name: String = sync_children[builder][k]
			index_of[builder + "/" + child_name] = k
			if not _built_before_handover(builder, child_name, terrain, start):
				expected_arrivals.append([_band_of(builder, child_name, terrain, start), b, k, builder + "/" + child_name])
	expected_arrivals.sort_custom(func(x: Array, y: Array) -> bool:
		if x[0] != y[0]:
			return x[0] < y[0]
		if x[1] != y[1]:
			return x[1] < y[1]
		return x[2] < y[2]
	)
	var expected_order := PackedStringArray()
	var expected_tail := {"Terrain": PackedStringArray(), "Forest": PackedStringArray(), "Buildings": PackedStringArray()}
	for entry: Array in expected_arrivals:
		expected_order.append(entry[3])
		expected_tail[STREAMED[entry[1]]].append(String(entry[3]).get_slice("/", 1))
	# A near chunk with nothing in it is a job and an arrival, never a
	# child: the arrivals are held to the ones that left a child.
	var arrived := PackedStringArray()
	for arrival: String in outcome.arrivals:
		if index_of.has(arrival):
			arrived.append(arrival)
	var ordered: bool = arrived == expected_order and not expected_order.is_empty()
	for builder: String in STREAMED:
		ordered = ordered and children[builder] == expected_handed[builder] + expected_tail[builder]
	_ok(ordered, "(a) the %d streamed children arrived in the pinned order - the far chunks by (the band of %.0f m from the standing car, the builder, CHUNK_ORDER) - and stand under each builder after the handover's children in that order" % [expected_order.size(), BAND_M], "arrivals %d (expected %d), the first difference at %d" % [arrived.size(), expected_order.size(), _first_difference(arrived, expected_order)])
	# The bytes: per child, then per builder in the reference's order.
	var hashes := _hashes_of(ring, sync_children)
	var chunk_faults := PackedStringArray()
	var handed_equal := 0
	var streamed_equal := 0
	for builder: String in ["Road", "Terrain", "Forest", "Buildings"]:
		var at_handover := {}
		for child_name: String in handed.get(builder, PackedStringArray()):
			at_handover[child_name] = true
		for child_name: String in sync_hashes[builder].chunks:
			if hashes[builder].chunks.get(child_name, "") != sync_hashes[builder].chunks[child_name]:
				chunk_faults.append(builder + "/" + child_name)
			elif at_handover.has(child_name):
				handed_equal += 1
			else:
				streamed_equal += 1
	_ok(chunk_faults.is_empty() and handed_equal > 0 and streamed_equal == expected_order.size(), "(a) SHA-256 per child: each of the %d children that stood at the handover and each of the %d streamed after it is the reference's child of the same name to the byte" % [handed_equal, streamed_equal], "%d children differ from the reference's (the first: %s); %d handed and %d streamed equal, %d streamed expected" % [chunk_faults.size(), chunk_faults[0] if not chunk_faults.is_empty() else "none", handed_equal, streamed_equal, expected_order.size()])
	_ok(hashes.Buildings.digest == sync_hashes.Buildings.digest and hashes.Buildings.meshes == sync_hashes.Buildings.meshes and hashes.Buildings.shapes == sync_hashes.Buildings.shapes, "(a) Buildings SHA-256 %s (%d meshes, %d shapes), identical sync/async" % [hashes.Buildings.digest.substr(0,16), hashes.Buildings.meshes, hashes.Buildings.shapes])
	var same_hashes := true
	for builder: String in ["Road", "Terrain", "Forest", "Buildings"]:
		same_hashes = same_hashes and hashes[builder].digest == sync_hashes[builder].digest and hashes[builder].missing == 0
	_ok(same_hashes, "(a) SHA-256 over every surface array and collider face list, the children walked in the reference's order, equals the reference's: Road %s (%d meshes, %d shapes), Terrain %s (%d meshes), Forest %s (%d meshes, %d shapes) - the async build's meshes are the sync build's to the byte" % [hashes.Road.digest.substr(0, 16), hashes.Road.meshes, hashes.Road.shapes, hashes.Terrain.digest.substr(0, 16), hashes.Terrain.meshes, hashes.Forest.digest.substr(0, 16), hashes.Forest.meshes, hashes.Forest.shapes], "async %s / %s / %s, sync %s / %s / %s" % [hashes.Road.digest, hashes.Terrain.digest, hashes.Forest.digest, sync_hashes.Road.digest, sync_hashes.Terrain.digest, sync_hashes.Forest.digest])


## L2-STREAMING-1, this test's own arithmetic: the box (x_lo, z_lo, x_hi,
## z_hi) of the 1 km chunk a child or job name stands for, or an empty
## array for a resident one - under Terrain only Near_<row>_<col> streams
## (on the tile grid from the lattice's origin), under Forest Walls_ and
## Trees_<x>_<z>, under Buildings every <element>_<x>_<z> mesh (the
## Rails_ and Solids_ bodies and the bubbles are resident), on the world
## grid.
func _chunk_box(builder: String, child_name: String, terrain: TerrainBuilder) -> PackedFloat64Array:
	var parts := child_name.rsplit("_", true, 2)
	if parts.size() != 3 or not parts[1].is_valid_int() or not parts[2].is_valid_int():
		return PackedFloat64Array()
	var x := 0.0
	var z := 0.0
	match builder:
		"Terrain":
			if parts[0] != "Near":
				return PackedFloat64Array()
			x = terrain.x0 + float(int(parts[2])) * CHUNK_M
			z = terrain.z0 + float(int(parts[1])) * CHUNK_M
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


## The horizontal distance from `at` to a chunk's box [m]: 0 inside.
func _box_distance(box: PackedFloat64Array, at: Vector3) -> float:
	var dx := maxf(0.0, maxf(box[0] - at.x, at.x - box[2]))
	var dz := maxf(0.0, maxf(box[1] - at.z, at.z - box[3]))
	return sqrt(dx * dx + dz * dz)


## Whether a child or job of this name is built before the handover for a
## car starting at `start`: resident, or a chunk within R_HANDOVER_M.
func _built_before_handover(builder: String, child_name: String, terrain: TerrainBuilder, start: Vector3) -> bool:
	var box := _chunk_box(builder, child_name, terrain)
	return box.is_empty() or _box_distance(box, start) <= R_HANDOVER_M


func _band_of(builder: String, child_name: String, terrain: TerrainBuilder, at: Vector3) -> int:
	return int(floor(_box_distance(_chunk_box(builder, child_name, terrain), at) / BAND_M))


func _first_difference(a: PackedStringArray, b: PackedStringArray) -> int:
	for k: int in mini(a.size(), b.size()):
		if a[k] != b[k]:
			return k
	return mini(a.size(), b.size())


func _check_progress(ring: Node, outcome: Dictionary) -> void:
	var road: RoadBuilder = ring.get_node("Road")
	var terrain: TerrainBuilder = ring.get_node("Terrain")
	var forest: ForestWalls = ring.get_node("Forest")
	var stages: Dictionary = outcome.stages
	# L2-STREAMING-1: the three streamed builders' totals are the resident
	# jobs plus the vicinity's chunks of their whole lists (was -> the
	# whole lists), counted here from the job names; the scheduler's
	# counters are the same arithmetic.
	var start: Vector3 = outcome.start
	var terrain_jobs := 0
	var forest_jobs := 0
	var building_jobs := 0
	var streamable := 0
	var vicinity := 0
	var all_jobs := 0
	for job: TerrainBuilder.MeshJob in terrain.mesh_jobs():
		all_jobs += 1
		streamable += 0 if _chunk_box("Terrain", job.name, terrain).is_empty() else 1
		if _built_before_handover("Terrain", job.name, terrain, start):
			terrain_jobs += 1
			vicinity += 0 if _chunk_box("Terrain", job.name, terrain).is_empty() else 1
	for job: ForestWalls.MeshJob in forest.mesh_jobs():
		all_jobs += 1
		streamable += 0 if _chunk_box("Forest", job.name, terrain).is_empty() else 1
		if _built_before_handover("Forest", job.name, terrain, start):
			forest_jobs += 1
			vicinity += 0 if _chunk_box("Forest", job.name, terrain).is_empty() else 1
	for job: BuildingsShells.MeshJob in (ring.get_node("Buildings") as BuildingsShells).mesh_jobs():
		all_jobs += 1
		streamable += 0 if _chunk_box("Buildings", job.name, terrain).is_empty() else 1
		if _built_before_handover("Buildings", job.name, terrain, start):
			building_jobs += 1
			vicinity += 0 if _chunk_box("Buildings", job.name, terrain).is_empty() else 1
	var counted: bool = stages.size() == 13 and stages.buildings_prepare.total == 1 and stages.buildings_place.total == 1 and stages.buildings_meshes.total == building_jobs and stages.buildings_nodes.total == stages.buildings_meshes.total and stages.road_sweep.total == road.road_count and stages.road_nodes.total == road.road_count and stages.terrain_meshes.total == terrain_jobs and stages.terrain_nodes.total == terrain_jobs and stages.forest_meshes.total == forest_jobs and stages.forest_nodes.total == forest_jobs and stages.road_prepare.total == 1 and stages.terrain_fields.total == 1 and stages.forest_place.total == 1
	var all_done := true
	for name_of: String in stages:
		all_done = all_done and stages[name_of].done == stages[name_of].total and stages[name_of].finished
	_ok(counted and all_done, "(b) every chunk counted: the sweep and the road node stage %d roads, the terrain's two stages %d jobs, the forest's two %d jobs, Buildings %d jobs (the resident jobs and the chunks within %.0f m of the car), the five serial stages one each, all thirteen stages done to their totals at the handover" % [road.road_count, terrain_jobs, forest_jobs, stages.buildings_nodes.total, R_HANDOVER_M], "stages %s, road_count %d, terrain jobs %d, forest jobs %d, building jobs %d" % [stages, road.road_count, terrain_jobs, forest_jobs, building_jobs])
	_ok(streamable > vicinity and vicinity > 0 and outcome.streamable == streamable and outcome.at_handover == vicinity and outcome.to_stream == streamable - vicinity and outcome.streamed == streamable - vicinity and terrain_jobs + forest_jobs + building_jobs + outcome.streamed == all_jobs, "(b) the scheduler's counters are the same arithmetic: %d streamable chunks, %d built before the handover, %d left to stream at the handover and %d streamed after it - with the three stages' totals, every one of the %d jobs built exactly once" % [streamable, vicinity, outcome.to_stream, outcome.streamed, all_jobs], "streamable %d (the scheduler %d), vicinity %d (%d), to stream %d, streamed %d, jobs %d + %d + %d of %d" % [streamable, outcome.streamable, vicinity, outcome.at_handover, outcome.to_stream, outcome.streamed, terrain_jobs, forest_jobs, building_jobs, all_jobs])
	var monotonic := true
	var samples: PackedFloat64Array = outcome.progress
	for k: int in range(1, samples.size()):
		monotonic = monotonic and samples[k] >= samples[k - 1]
	_ok(monotonic and not samples.is_empty() and samples[0] >= 0.0 and outcome.percent == "100 %" and outcome.bar and outcome.step == "The Ring stands", "(b) the bar's fraction never fell from one frame to the next and read 100 %% at the handover, the step label \"%s\"" % outcome.step, "monotonic %s over %d samples, percent %s, bar %s, step %s" % [monotonic, samples.size(), outcome.percent, outcome.bar, outcome.step])


func _check_frames(outcome: Dictionary) -> void:
	var worst := 0.0
	var worst_at := -1
	var deltas: PackedFloat64Array = outcome.deltas
	for k: int in deltas.size():
		if deltas[k] > worst:
			worst = deltas[k]
			worst_at = k
	var internal_worst := 0.0
	var internal: PackedFloat64Array = outcome.internal
	for k: int in internal.size():
		internal_worst = maxf(internal_worst, internal[k])
	if OS.get_environment("FD_LOADING_FRAMES") == "1":
		print("  frames: %d measured from outside, the longest %.1f ms at frame %d (the handover's frame is %d); the loading scene's own %d frames, the longest %.1f ms" % [deltas.size(), worst, worst_at + 1, deltas.size() - 2, internal.size(), internal_worst])
	var tail_worst := 0.0
	var tail_deltas: PackedFloat64Array = outcome.tail_deltas
	for k: int in tail_deltas.size():
		tail_worst = maxf(tail_worst, tail_deltas[k])
	if OS.get_environment("FD_LOADING_FRAMES") == "1":
		print("  the tail: %d frames, the longest %.1f ms" % [tail_deltas.size(), tail_worst])
	_ok(not tail_deltas.is_empty() and tail_worst < FRAME_CEILING_MS, "(c) the streaming tail never blocked the main thread either: every process frame from the handover to the last streamed chunk under %.0f ms" % FRAME_CEILING_MS, "the tail's longest frame %.1f ms of %d" % [tail_worst, tail_deltas.size()])
	_ok(deltas.size() > 10 and worst < FRAME_CEILING_MS and internal_worst < FRAME_CEILING_MS, "(c) the main thread never blocked: the longest process frame from outside the loading scene (the handover's enter-tree included) and the scene's own longest frame both under %.0f ms" % FRAME_CEILING_MS, "longest from outside %.1f ms at frame %d of %d (the handover at %d), the scene's own longest %.1f ms of %d" % [worst, worst_at + 1, deltas.size(), deltas.size() - 2, internal_worst, internal.size()])


func _check_handover(ring: Node, outcome: Dictionary) -> void:
	var road: RoadBuilder = ring.get_node("Road")
	var car: ArcadeCar = ring.get_node("Car")
	var floor_body := road.get_node_or_null("Floor")
	_ok(car != null and car.road_profile is WorldRoadProfile and car.road_profile == road.profile and car.reset_to_last_pose and floor_body is StaticBody3D and road.build_deferred and ring.get_node("Terrain").build_deferred and ring.get_node("Forest").build_deferred and ring.get_node("Buildings").build_deferred and outcome.fallback == "", "(d) the car stands on the road's profile (the same object, a WorldRoadProfile), the reset flag set, the floor slab under it; all four builders still marked deferred (their _ready built nothing, the loading scene did); no fallback", "profile %s == %s: %s, reset %s, floor %s, deferred %s/%s/%s, fallback '%s'" % [car.road_profile if car else null, road.profile, car.road_profile == road.profile if car else false, car.reset_to_last_pose if car else false, floor_body, road.build_deferred, ring.get_node("Terrain").build_deferred, ring.get_node("Forest").build_deferred, outcome.fallback])


func _check_setting() -> void:
	var was: Variant = ProjectSettings.get_setting(LoadingScreen.SETTING, true)
	_ok(was == true and LoadingScreen.routes(RING_SCENE) and not LoadingScreen.routes(PAD_SCENE), "(e) %s reads true, the game's default: the Ring's drive row goes through the loading scene, the pad's goes direct" % LoadingScreen.SETTING, "setting %s, routes ring %s, pad %s" % [was, LoadingScreen.routes(RING_SCENE), LoadingScreen.routes(PAD_SCENE)])
	ProjectSettings.set_setting(LoadingScreen.SETTING, false)
	_ok(not LoadingScreen.routes(RING_SCENE) and not LoadingScreen.routes(PAD_SCENE), "(e) with the setting false the Ring goes direct too (the suite's menu test pins it so; restored here)")
	ProjectSettings.set_setting(LoadingScreen.SETTING, was)


func _check_fallback() -> void:
	var outcome := await _load_async(CAR_SCENE)
	var handed: Node = outcome.ring
	_ok(handed != null and handed.scene_file_path == CAR_SCENE and current_scene == handed and outcome.fallback != "" and not is_instance_valid(outcome.loading), "(f) pointed at %s, a scene with no Road, Terrain and Forest, the loading scene fell back honestly - \"%s\" (one push_warning) - and handed over that scene built the ordinary way as the current scene" % [CAR_SCENE, outcome.fallback], "handed %s, current %s, fallback '%s', loading valid %s" % [handed, current_scene, outcome.fallback, is_instance_valid(outcome.loading)])
	if handed != null:
		unload_current_scene()
		await _step(2)


func _check_abandonment(root_children_before: int) -> void:
	LoadingScreen.target_scene = RING_SCENE
	var loading: LoadingScreen = (load(LoadingScreen.SCENE) as PackedScene).instantiate()
	root.add_child(loading)
	await _step(ABANDON_AFTER_FRAMES)
	var running := loading.stages_running()
	var had_ring: bool = loading.ring != null and not loading.ring.is_inside_tree()
	root.remove_child(loading)
	loading.free()
	await _step(2)
	var ring_left := false
	for child: Node in root.get_children():
		ring_left = ring_left or child.scene_file_path == RING_SCENE
	var scheduler := StreamingScheduler.of(self)
	_ok(scheduler != null and scheduler.ring == null and not scheduler.streaming and scheduler.chunks_remaining() == 0, "(g) the abandoned Ring's claim at the streaming scheduler was released: nothing claimed, nothing to stream", "the scheduler: %s" % (scheduler.describe() if scheduler != null else "none"))
	_ok(had_ring and running != "" and not ring_left and root.get_child_count() == root_children_before and current_scene == null, "(g) a loading scene freed while its stages ran (%s) cancelled and waited for its tasks and dropped its partial Ring: nothing of the Ring under the root, the root as it was" % running, "had ring %s, running '%s', ring left %s, root children %d (was %d), current %s" % [had_ring, running, ring_left, root.get_child_count(), root_children_before, current_scene])


# =============================================================================
#  The measures
# =============================================================================

## The builders' describe() lines, counts and tallies.
func _report_of(ring: Node) -> Dictionary:
	var road: RoadBuilder = ring.get_node("Road")
	var terrain: TerrainBuilder = ring.get_node("Terrain")
	var forest: ForestWalls = ring.get_node("Forest")
	return {
		"road": _road_report_of(road),
		"terrain": {"describe": terrain.describe(), "counts": terrain.counts.duplicate(), "elements": terrain.elements.duplicate()},
		"forest": {"describe": forest.describe(), "counts": forest.counts.duplicate(), "elements": forest.elements.duplicate()},
		"buildings": {"describe": ring.get_node("Buildings").describe(), "counts": ring.get_node("Buildings").counts.duplicate(), "elements": ring.get_node("Buildings").elements.duplicate()},
	}


## The road's describe() line and counters (what _report_of holds for it).
func _road_report_of(road: RoadBuilder) -> Dictionary:
	return {"describe": road.describe(), "road_count": road.road_count, "counters": [road.road_count, road.section_count, road.split_count, road.fine_split_count, road.vertex_count, road.triangle_count, road.body_count]}


## The child names under each builder, in order.
func _children_of(ring: Node) -> Dictionary:
	var out := {}
	for builder: String in ["Road", "Terrain", "Forest", "Buildings"]:
		var names := PackedStringArray()
		for child: Node in ring.get_node(builder).get_children():
			names.append(child.name)
		out[builder] = names
	return out


## Per builder: SHA-256 over every child's name and class and, in order,
## every mesh surface's vertices, normals, UVs, colours and indices and
## every collider's faces or box; with the counts of what went in. A
## name Godot made up for an unnamed node (the strips' collision shapes:
## "@CollisionShape3D@<n>", n the engine's instance counter, another
## number in every build) is not data and is left out. L2-STREAMING-1:
## the builder's children are walked in `order` (the reference's child
## names in the reference's order - for the reference itself its own
## child order, the walk this function always made; a streamed build's
## far chunks stand in another order, the bytes fed are the same ones in
## the same order when every child is there and equal; `missing` counts
## the names with no child), and each child's own SHA-256 over the same
## bytes is kept by name in `chunks`.
func _hashes_of(ring: Node, order: Dictionary) -> Dictionary:
	var out := {}
	for builder: String in ["Road", "Terrain", "Forest", "Buildings"]:
		var context := HashingContext.new()
		context.start(HashingContext.HASH_SHA256)
		var counters := {"meshes": 0, "shapes": 0}
		var chunks := {}
		var missing := 0
		var node := ring.get_node(builder)
		for child_name: String in order[builder]:
			var child := node.get_node_or_null(NodePath(child_name))
			if child == null:
				missing += 1
				continue
			var own := HashingContext.new()
			own.start(HashingContext.HASH_SHA256)
			_hash_node([context, own], child, counters)
			chunks[child_name] = own.finish().hex_encode()
		out[builder] = {"digest": context.finish().hex_encode(), "meshes": counters.meshes, "shapes": counters.shapes, "chunks": chunks, "missing": missing}
	return out


## One node and everything under it into every context of `contexts`.
func _hash_node(contexts: Array, child: Node, counters: Dictionary) -> void:
	if not String(child.name).begins_with("@"):
		_feed(contexts, child.name.to_utf8_buffer())
	_feed(contexts, child.get_class().to_utf8_buffer())
	if child is MeshInstance3D and (child as MeshInstance3D).mesh is ArrayMesh:
		var mesh: ArrayMesh = (child as MeshInstance3D).mesh
		for s: int in mesh.get_surface_count():
			var arrays := mesh.surface_get_arrays(s)
			for k: int in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_TEX_UV, Mesh.ARRAY_COLOR, Mesh.ARRAY_INDEX]:
				var array: Variant = arrays[k]
				if array is PackedVector3Array or array is PackedVector2Array or array is PackedColorArray or array is PackedInt32Array:
					_feed(contexts, array.to_byte_array())
		counters.meshes += 1
	elif child is CollisionShape3D:
		var shape: Shape3D = (child as CollisionShape3D).shape
		if shape is ConcavePolygonShape3D:
			_feed(contexts, (shape as ConcavePolygonShape3D).get_faces().to_byte_array())
			counters.shapes += 1
		elif shape is BoxShape3D:
			_feed(contexts, var_to_bytes((shape as BoxShape3D).size))
			counters.shapes += 1
	for below: Node in child.get_children():
		_hash_node(contexts, below, counters)


func _feed(contexts: Array, bytes: PackedByteArray) -> void:
	for context: HashingContext in contexts:
		context.update(bytes)


# =============================================================================
#  Harness
# =============================================================================

func _step(frames: int) -> void:
	for i: int in frames:
		await process_frame


## An ok line or a FAIL line, counted.
func _ok(condition: bool, what: String, reason: String = "") -> void:
	if condition:
		print("  ok    ", what)
	else:
		_failures += 1
		printerr("  FAIL  ", reason if reason != "" else what)


func _finish() -> void:
	print("ASYNC BUILD TEST PASSED" if _failures == 0 else "ASYNC BUILD TEST FAILED: %d fault(s)" % _failures)
	quit(0 if _failures == 0 else 1)
