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
##   (a) DETERMINISM: the three builders' describe() lines, their counts
##       and the road's seven counters equal to the character and the
##       integer, the children under Road, Terrain and Forest the same
##       names in the same order, and a SHA-256 over every mesh's surface
##       arrays (vertices, normals, UVs, colours, indices, in child and
##       surface order) and every collider's faces (the strips' trimeshes,
##       the trunk prisms, the floor slab's box) equal per builder - the
##       async build's meshes are the sync build's to the byte. The
##       digests' first sixteen hex characters are printed: the pin;
##   (b) THE PROGRESS: every stage's chunks counted - the sweep group's
##       total the road count and the road node stage's total the same,
##       the terrain's and the forest's group totals their mesh_jobs()
##       sizes and their node stages' totals the same, every stage's done
##       equal to its total at the handover - and the bar's fraction never
##       falling from one frame to the next, 1.0 at the handover, the
##       percent label at 100 %;
##   (c) THE MAIN THREAD NEVER BLOCKS: this script measures the wall-clock
##       delta between consecutive process frames from outside the loading
##       scene, from the frame the scene is added to two frames after the
##       handover (the enter-tree of the built Ring included), and holds
##       the longest under FRAME_CEILING_MS; the loading scene's own
##       per-frame deltas the same. The numbers are printed only on a
##       failure (or with FD_LOADING_FRAMES=1): the suite's lines are the
##       same on every machine;
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
## road) - 9 913 children under Road, was 6 609.

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
	var sync_hashes := _hashes_of(sync_ring)
	var sync_children := _children_of(sync_ring)
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
	_check_determinism(ring, sync_report, sync_hashes, sync_children)
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
	var outcome := {"loading": loading, "ring": null, "deltas": PackedFloat64Array(), "internal": PackedFloat64Array(), "stages": {}, "progress": PackedFloat64Array(), "percent": "", "step": "", "fallback": "", "bar": false, "warnings": 0}
	loading.handed_over.connect(func(built: Node) -> void:
		outcome.ring = built
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


# =============================================================================
#  The checks
# =============================================================================

func _check_determinism(ring: Node, sync_report: Dictionary, sync_hashes: Dictionary, sync_children: Dictionary) -> void:
	var report := _report_of(ring)
	_ok(report.road.describe == sync_report.road.describe and report.terrain.describe == sync_report.terrain.describe and report.forest.describe == sync_report.forest.describe, "(a) the three describe() lines equal the reference's: %s | %s | %s" % [report.road.describe, report.terrain.describe, report.forest.describe], "async %s | %s | %s" % [report.road.describe, report.terrain.describe, report.forest.describe])
	_ok(report.road.counters == sync_report.road.counters and report.terrain.counts == sync_report.terrain.counts and report.forest.counts == sync_report.forest.counts and report.terrain.elements == sync_report.terrain.elements and report.forest.elements == sync_report.forest.elements, "(a) the road's seven counters, the terrain's and the forest's counts and element tallies equal the reference's", "road %s vs %s, terrain %s vs %s, forest %s vs %s, elements %s / %s vs %s / %s" % [report.road.counters, sync_report.road.counters, report.terrain.counts, sync_report.terrain.counts, report.forest.counts, sync_report.forest.counts, report.terrain.elements, report.forest.elements, sync_report.terrain.elements, sync_report.forest.elements])
	var children := _children_of(ring)
	var same_children := true
	for builder: String in ["Road", "Terrain", "Forest"]:
		same_children = same_children and children[builder] == sync_children[builder]
	_ok(same_children, "(a) the children under Road (%d), Terrain (%d) and Forest (%d) are the reference's names in the reference's order: CHUNK_ORDER held" % [children.Road.size(), children.Terrain.size(), children.Forest.size()], "async %d / %d / %d, sync %d / %d / %d" % [children.Road.size(), children.Terrain.size(), children.Forest.size(), sync_children.Road.size(), sync_children.Terrain.size(), sync_children.Forest.size()])
	var hashes := _hashes_of(ring)
	var same_hashes := true
	for builder: String in ["Road", "Terrain", "Forest"]:
		same_hashes = same_hashes and hashes[builder].digest == sync_hashes[builder].digest
	_ok(same_hashes, "(a) SHA-256 over every surface array and collider face list equals the reference's: Road %s (%d meshes, %d shapes), Terrain %s (%d meshes), Forest %s (%d meshes, %d shapes) - the async build's meshes are the sync build's to the byte" % [hashes.Road.digest.substr(0, 16), hashes.Road.meshes, hashes.Road.shapes, hashes.Terrain.digest.substr(0, 16), hashes.Terrain.meshes, hashes.Forest.digest.substr(0, 16), hashes.Forest.meshes, hashes.Forest.shapes], "async %s / %s / %s, sync %s / %s / %s" % [hashes.Road.digest, hashes.Terrain.digest, hashes.Forest.digest, sync_hashes.Road.digest, sync_hashes.Terrain.digest, sync_hashes.Forest.digest])


func _check_progress(ring: Node, outcome: Dictionary) -> void:
	var road: RoadBuilder = ring.get_node("Road")
	var terrain: TerrainBuilder = ring.get_node("Terrain")
	var forest: ForestWalls = ring.get_node("Forest")
	var stages: Dictionary = outcome.stages
	var terrain_jobs := terrain.mesh_jobs().size()
	var forest_jobs := forest.mesh_jobs().size()
	var counted: bool = stages.size() == 9 and stages.road_sweep.total == road.road_count and stages.road_nodes.total == road.road_count and stages.terrain_meshes.total == terrain_jobs and stages.terrain_nodes.total == terrain_jobs and stages.forest_meshes.total == forest_jobs and stages.forest_nodes.total == forest_jobs and stages.road_prepare.total == 1 and stages.terrain_fields.total == 1 and stages.forest_place.total == 1
	var all_done := true
	for name_of: String in stages:
		all_done = all_done and stages[name_of].done == stages[name_of].total and stages[name_of].finished
	_ok(counted and all_done, "(b) every chunk counted: the sweep and the road node stage %d roads, the terrain's two stages %d jobs, the forest's two %d jobs, the three serial stages one each, every stage done to its total at the handover" % [road.road_count, terrain_jobs, forest_jobs], "stages %s, road_count %d, terrain jobs %d, forest jobs %d" % [stages, road.road_count, terrain_jobs, forest_jobs])
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
	_ok(deltas.size() > 10 and worst < FRAME_CEILING_MS and internal_worst < FRAME_CEILING_MS, "(c) the main thread never blocked: the longest process frame from outside the loading scene (the handover's enter-tree included) and the scene's own longest frame both under %.0f ms" % FRAME_CEILING_MS, "longest from outside %.1f ms at frame %d of %d (the handover at %d), the scene's own longest %.1f ms of %d" % [worst, worst_at + 1, deltas.size(), deltas.size() - 2, internal_worst, internal.size()])


func _check_handover(ring: Node, outcome: Dictionary) -> void:
	var road: RoadBuilder = ring.get_node("Road")
	var car: ArcadeCar = ring.get_node("Car")
	var floor_body := road.get_node_or_null("Floor")
	_ok(car != null and car.road_profile is WorldRoadProfile and car.road_profile == road.profile and car.reset_to_last_pose and floor_body is StaticBody3D and road.build_deferred and ring.get_node("Terrain").build_deferred and ring.get_node("Forest").build_deferred and outcome.fallback == "", "(d) the car stands on the road's profile (the same object, a WorldRoadProfile), the reset flag set, the floor slab under it; the three builders still marked deferred (their _ready built nothing, the loading scene did); no fallback", "profile %s == %s: %s, reset %s, floor %s, deferred %s/%s/%s, fallback '%s'" % [car.road_profile if car else null, road.profile, car.road_profile == road.profile if car else false, car.reset_to_last_pose if car else false, floor_body, road.build_deferred, ring.get_node("Terrain").build_deferred, ring.get_node("Forest").build_deferred, outcome.fallback])


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
		"road": {"describe": road.describe(), "road_count": road.road_count, "counters": [road.road_count, road.section_count, road.split_count, road.fine_split_count, road.vertex_count, road.triangle_count, road.body_count]},
		"terrain": {"describe": terrain.describe(), "counts": terrain.counts.duplicate(), "elements": terrain.elements.duplicate()},
		"forest": {"describe": forest.describe(), "counts": forest.counts.duplicate(), "elements": forest.elements.duplicate()},
	}


## The child names under each builder, in order.
func _children_of(ring: Node) -> Dictionary:
	var out := {}
	for builder: String in ["Road", "Terrain", "Forest"]:
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
## number in every build) is not data and is left out.
func _hashes_of(ring: Node) -> Dictionary:
	var out := {}
	for builder: String in ["Road", "Terrain", "Forest"]:
		var context := HashingContext.new()
		context.start(HashingContext.HASH_SHA256)
		var counters := {"meshes": 0, "shapes": 0}
		_hash_under(context, ring.get_node(builder), counters)
		out[builder] = {"digest": context.finish().hex_encode(), "meshes": counters.meshes, "shapes": counters.shapes}
	return out


func _hash_under(context: HashingContext, node: Node, counters: Dictionary) -> void:
	for child: Node in node.get_children():
		if not String(child.name).begins_with("@"):
			context.update(child.name.to_utf8_buffer())
		context.update(child.get_class().to_utf8_buffer())
		if child is MeshInstance3D and (child as MeshInstance3D).mesh is ArrayMesh:
			var mesh: ArrayMesh = (child as MeshInstance3D).mesh
			for s: int in mesh.get_surface_count():
				var arrays := mesh.surface_get_arrays(s)
				for k: int in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_TEX_UV, Mesh.ARRAY_COLOR, Mesh.ARRAY_INDEX]:
					var array: Variant = arrays[k]
					if array is PackedVector3Array or array is PackedVector2Array or array is PackedColorArray or array is PackedInt32Array:
						context.update(array.to_byte_array())
			counters.meshes += 1
		elif child is CollisionShape3D:
			var shape: Shape3D = (child as CollisionShape3D).shape
			if shape is ConcavePolygonShape3D:
				context.update((shape as ConcavePolygonShape3D).get_faces().to_byte_array())
				counters.shapes += 1
			elif shape is BoxShape3D:
				context.update(var_to_bytes((shape as BoxShape3D).size))
				counters.shapes += 1
		_hash_under(context, child, counters)


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
