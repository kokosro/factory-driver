class_name LoadingScreen
extends Control
## 4B-8: nine stages -> thirteen. buildings_prepare reads the reduction
## after terrain_fields; buildings_place places shells/furniture and groups
## chunks; buildings_meshes fills independent jobs; buildings_nodes consumes
## them under NODE_BUDGET_MS. Buildings is attached/claimed outside the tree
## with BuildingsShells.of(), the watcher's same idempotent path.
##
## The loading screen (LOADING-1; decisions.org C07BE6F1, the driver's
## canon of 2026-09-27: "no freezing load" - the synchronous Ring build
## held the window for ~17 s under the macOS loading bubble; the Ring must
## come up behind a proper loading screen that keeps drawing). The garage's
## drive row for the Ring lands here (Garage._free_drive through go()) and
## this scene builds the Ring beside itself, draws a progress bar every
## frame and hands over when the Ring stands. The world-around-the-car
## streaming is L2 and not this pass: the whole Ring is built, once, off
## the main thread.
##
## THE PIPELINE. The Ring scene is instantiated but NOT added to the tree
## (instantiation runs no _ready), and its three builders are claimed
## (build_deferred = true: their _ready then builds nothing). Each builder
## is split at the same seam (their headers' THE ASYNC SEAM): a DATA STAGE
## of pure arithmetic over the files and the profile, run here on
## WorkerThreadPool threads, and a NODE STAGE that makes the meshes and
## the bodies, run here on the main thread over as many frames as its
## budget takes - node instantiation is not thread-safe in Godot, so no
## Node is made off the main thread, ever. The stages and what they wait
## for:
##
##   road_prepare   one task: RoadBuilder.prepare_data - the files, the
##                  rim rule, the right of way, the profile, the roads in
##                  CHUNK_ORDER (measured 1.8 s: the rules 1.5 s)
##   road_sweep     a group task over the roads: RoadBuilder.sweep_road
##                  per road into its own Strip (after road_prepare)
##   terrain_fields one task: TerrainBuilder.compute_fields - the lattice,
##                  the distance field, the raster, the forms, the plan
##                  (after road_prepare: it reads the profile and the
##                  parsed files)
##   terrain_meshes a group task over TerrainBuilder.mesh_jobs() in
##                  CHUNK_ORDER, each into its own arrays (after the
##                  fields)
##   forest_place   one task: ForestWalls.place, the walk and the trees
##                  (after the fields: it reads the terrain's distance
##                  field and the ribbons), then mesh_jobs() - the chunk
##                  grouping and the index memo's growth, still on that
##                  one thread
##   forest_meshes  a group task over the forest's jobs in CHUNK_ORDER
##   road_nodes     main thread, over frames: add_strip per strip in
##                  CHUNK_ORDER, then the floor (after road_sweep)
##   terrain_nodes  main thread, over frames: add_job per job in
##                  CHUNK_ORDER (after terrain_meshes)
##   forest_nodes   main thread, over frames: add_job per job in
##                  CHUNK_ORDER, then the element counts and the bubble
##                  (after forest_meshes)
##   handover       main thread: the Ring added under the root as the
##                  current scene, this scene freed (after every node
##                  stage)
##
## The main-thread steps between the tasks (apply_prepared: the members,
## the car's profile, the asphalt's textures; TerrainBuilder.prepare: the
## table and the materials; ForestWalls.prepare: the assets - load() and
## an archetype scene instantiated, 4 ms measured - the cells and the
## budgets) are milliseconds each. The node stages take NODE_BUDGET_MS of
## a frame and yield: the bar moves per chunk. A frame is never held by
## the data stages, whichever thread count the pool has.
##
## CHUNK_ORDER is each builder's own sequential order (the road's strips
## in the drape's segment order; the terrain's near chunks row-major,
## Mid, Far, the bands per ribbon, the water, the four continuation
## bands; the forest's wall, tree and trunk chunks in their members'
## first-seen order): a worker fills each chunk's slot in whatever order
## the pool runs them, and the node stage consumes the slots in
## CHUNK_ORDER, so the children under Road, Terrain and Forest stand in
## the order the one-thread build always gave them and every mesh, body
## and count is the same - tests/async_build_test.gd hashes the two
## builds' arrays against each other. No RNG, no wall clock in any
## result; only the wall clock's order of thread completion differs.
##
## THREADS, MEASURED (this machine, 2026-09-27; .scratch/loading-1/):
## GDScript does not spread across the pool - the sweep took 4 917 ms on
## the main thread, 4 935 ms on one worker, 4 325 ms on four and 4 383 on
## eight (the interpreter's shared refcounts and object locks serialise
## it) - so the async build takes about as long as the sync one did. The
## gain is the one the canon asks for: the main thread draws every frame,
## the dock icon stays still, the window answers. DATA_THREADS caps each
## group at four workers: the best of the measured counts, and the rest
## of the machine left to the renderer and the main thread.
##
## THE FALLBACK: a stage that cannot run - the files missing (an empty
## prepare_data), a drape without a lattice - is a push_warning here, the
## screen says so for a frame, the partial Ring is dropped and a fresh
## Ring is instantiated and added to the tree the ordinary way: its
## builders build synchronously in _ready as they always did (the freeze,
## honestly, and the builders' own push_error where a file is missing) -
## never a broken scene. A script error inside a worker's task cannot be
## caught from GDScript; that is the one failure this fallback does not
## reach.
##
## ABANDONMENT: leaving the tree before the handover (Esc - the
## abort_mission action - back to the pad; a test unloading the scene;
## the window closed) cancels the group tasks at their next element,
## waits for every task the pool still holds (a serial task runs to its
## end: up to the fields' 2.3 s) and frees the partial Ring. A task never
## outlives this node.
##
## FD_LOADING_FRAMES=1 in the environment prints one line per frame with
## the frame's wall-clock delta and the stage, and a summary at the
## handover (tests/bubble_test.gd's FD_BUBBLE_PERF precedent; never in
## the suite's lines). frame_deltas_ms keeps them for the async test's
## ceiling either way.
##
## Styled from the garage's own palette and frame (Garage.COLOR_*, a
## StyleBoxFlat panel), no theme asset.

## The project setting (project.godot [application]): true, the game's
## default, routes the Ring through this scene; false takes every map
## direct, the way the suite's scene loads build (tests/menu_test.gd pins
## it false in its _initialize so its Ring row check stays on the sync
## path; the one additive check there sets it true for itself).
const SETTING := "application/use_async_build"

## This scene, and the one scene it builds: the Ring.
const SCENE := "res://scenes/loading.tscn"
const RING_SCENE := "res://scenes/eifel_ring.tscn"

## The pad, where Esc goes back to.
const PAD_SCENE := "res://scenes/main.tscn"

## Workers per group task (the header's THREADS, MEASURED).
const DATA_THREADS := 4

## The node stages' budget per frame [ms]: how long add_strip / add_job
## calls are made before the frame is let go (a strip's mesh and trimesh
## take about 0.1 ms, a terrain chunk's or a tree chunk's mesh a few ms).
const NODE_BUDGET_MS := 8.0

## The bar's share per stage, from the measured wall time of each (the
## header's table; the node stages measured at about a second each): the
## bar then moves about linearly with the clock. Within a stage the share
## fills per chunk done.
const STAGE_WEIGHTS := {
	"road_prepare": 1.8, "road_sweep": 4.9, "terrain_fields": 2.3, "terrain_meshes": 6.5,
	"forest_place": 1.7, "forest_meshes": 0.7, "road_nodes": 0.6, "terrain_nodes": 0.5, "forest_nodes": 0.5,
	"buildings_prepare": 0.1, "buildings_place": 0.2, "buildings_meshes": 0.5, "buildings_nodes": 0.1,
}

## What the screen says for each stage.
const STAGE_TEXT := {
	"buildings_prepare": "Buildings: reading the footprints and catalogue",
	"buildings_place": "Buildings: placing shells and road furniture",
	"buildings_meshes": "Buildings: making the chunks",
	"buildings_nodes": "Buildings: meshes and nearby collision",
	"road_prepare": "Road: reading the files, the rim rule, the right of way, the profile",
	"road_sweep": "Road: sweeping the strips",
	"terrain_fields": "Terrain: the lattice, the distance field, the forms, the plan",
	"terrain_meshes": "Terrain: the chunks",
	"forest_place": "Forest: walking the forests, placing the trees",
	"forest_meshes": "Forest: the chunks",
	"road_nodes": "Road: the strips and their colliders",
	"terrain_nodes": "Terrain: the meshes",
	"forest_nodes": "Forest: the meshes and the trunk bodies",
}

## The frame: size [px], corner radius, border and margins (the garage's
## proportions), the bar's height [px].
const FRAME_SIZE := Vector2(760, 230)
const FRAME_CORNER_RADIUS := 18
const FRAME_BORDER_WIDTH := 4
const FRAME_MARGIN := 18
const BAR_HEIGHT := 18

## The scene the next instance builds: set by go() before the change of
## scene, read once in _ready (a static: the scene change instantiates
## this script's scene with no argument to give it).
static var target_scene := RING_SCENE

## The Ring stands under the root as the current scene.
signal handed_over(ring: Node)

## The Ring, instantiated and not yet in the tree (null after the
## handover or the abandonment).
var ring: Node
var road: RoadBuilder
var terrain: TerrainBuilder
var forest: ForestWalls
var buildings: BuildingsShells

## What the screen reports: the stage names running, the last chunk
## counts, the bar's fraction, whether the handover happened, and the
## fallback's reason where the sync build had to step in ("" otherwise).
var step_name := ""
var chunks_done := 0
var chunks_total := 0
var progress := 0.0
var done := false
var fallback_reason := ""

## Every frame's wall-clock delta while this scene ran [ms], for the
## async test's ceiling and FD_LOADING_FRAMES (the header).
var frame_deltas_ms := PackedFloat64Array()
## The stage each frame was in (parallel to frame_deltas_ms).
var frame_stages := PackedStringArray()

## The stages by name: {deps: [names], kind: "task" | "group" | "nodes",
## started, finished, id (the pool's), total, done (chunks)}.
var _stages := {}
## The stages in order (the header's table), for the report and the bar.
var _order := PackedStringArray()
## The data slots, filled by the workers: one Strip per road, the
## terrain's jobs, the forest's jobs.
var _roads: Array[RoadBuilder.Road] = []
var _strips: Array = []
var _prepared := {}
var _fields_ok := false
var _terrain_jobs: Array[TerrainBuilder.MeshJob] = []
var _forest_jobs: Array[ForestWalls.MeshJob] = []
var _building_jobs: Array[BuildingsShells.MeshJob] = []
## The node stages' cursors: the next slot to add.
var _cursor := {"road_nodes": 0, "terrain_nodes": 0, "forest_nodes": 0}
var _cancelled := false
var _started_ms := 0
var _last_frame_usec := 0
var _log_frames := false
var _handed := false

var _title: Label
var _step: Label
var _bar: ProgressBar
var _percent: Label
var _note: Label


## Whether the drive row for `scene` goes through this screen: the Ring,
## with the setting on. The pad stays direct (its build is trivial).
static func routes(scene: String) -> bool:
	return scene == RING_SCENE and bool(ProjectSettings.get_setting(SETTING, true))


## Changes the tree's scene to this one, which then builds `scene`.
static func go(tree: SceneTree, scene: String) -> void:
	target_scene = scene
	tree.change_scene_to_file(SCENE)


func _ready() -> void:
	_log_frames = OS.get_environment("FD_LOADING_FRAMES") == "1"
	_build_ui()
	_started_ms = Time.get_ticks_msec()
	_last_frame_usec = Time.get_ticks_usec()
	# The first frame draws the screen before the Ring is instantiated.
	_start.call_deferred()


func _exit_tree() -> void:
	_abandon()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"abort_mission") and not done and fallback_reason == "":
		_step.text = "Cancelled: back to the pad"
		get_viewport().set_input_as_handled()
		# _exit_tree abandons the build (the header); the pad comes up as
		# it always did.
		get_tree().change_scene_to_file(PAD_SCENE)


# =============================================================================
#  THE PIPELINE
# =============================================================================

func _start() -> void:
	var packed: PackedScene = load(target_scene)
	if packed == null:
		_fallback("the scene %s does not load" % target_scene)
		return
	ring = packed.instantiate()
	road = ring.get_node_or_null("Road") as RoadBuilder
	terrain = ring.get_node_or_null("Terrain") as TerrainBuilder
	forest = ring.get_node_or_null("Forest") as ForestWalls
	if road == null or terrain == null or forest == null:
		_fallback("the scene has no Road, Terrain and Forest to build")
		return
	road.build_deferred = true
	terrain.build_deferred = true
	forest.build_deferred = true
	buildings = BuildingsShells.of(ring)
	buildings.build_deferred = true
	buildings.warm_catalogue()
	_add_stage("road_prepare", "task", [])
	_add_stage("road_sweep", "group", ["road_prepare"])
	_add_stage("terrain_fields", "task", ["road_prepare"])
	_add_stage("terrain_meshes", "group", ["terrain_fields"])
	_add_stage("forest_place", "task", ["terrain_fields"])
	_add_stage("forest_meshes", "group", ["forest_place"])
	_add_stage("road_nodes", "nodes", ["road_sweep"])
	_add_stage("terrain_nodes", "nodes", ["terrain_meshes"])
	_add_stage("forest_nodes", "nodes", ["forest_meshes"])
	_add_stage("buildings_prepare", "task", ["terrain_fields"])
	_add_stage("buildings_place", "task", ["buildings_prepare"])
	_add_stage("buildings_meshes", "group", ["buildings_place"])
	_add_stage("buildings_nodes", "nodes", ["buildings_meshes"])


func _add_stage(name_of: String, kind: String, deps: Array) -> void:
	_stages[name_of] = {"deps": deps, "kind": kind, "started": false, "finished": false, "id": -1, "total": 1, "done": 0, "started_ms": 0, "ms": 0}
	_order.append(name_of)


func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	var frame_ms := float(now - _last_frame_usec) / 1000.0
	_last_frame_usec = now
	var running := _running_stages()
	frame_deltas_ms.append(frame_ms)
	frame_stages.append(running)
	if _log_frames:
		print("loading frame %d: %.1f ms [%s]" % [frame_deltas_ms.size(), frame_ms, running])
	if done or fallback_reason != "" or ring == null:
		return
	for name_of: String in _order:
		var stage: Dictionary = _stages[name_of]
		if stage.finished:
			continue
		if not stage.started:
			if _deps_done(stage):
				_submit(name_of, stage)
		elif stage.kind == "nodes":
			_add_nodes(name_of, stage)
		else:
			_poll(name_of, stage)
		if fallback_reason != "":
			return
	_report()
	if _all_finished():
		_handover()


func _deps_done(stage: Dictionary) -> bool:
	for dep: String in stage.deps:
		if not _stages[dep].finished:
			return false
	return true


func _all_finished() -> bool:
	for name_of: String in _order:
		if not _stages[name_of].finished:
			return false
	return true


func _running_stages() -> String:
	var names := PackedStringArray()
	for name_of: String in _order:
		if _stages[name_of].started and not _stages[name_of].finished:
			names.append(name_of)
	return ", ".join(names) if not names.is_empty() else ("handover" if not done else "done")


## Submits a stage: its main-thread prelude, then its task or group.
func _submit(name_of: String, stage: Dictionary) -> void:
	stage.started = true
	stage.started_ms = Time.get_ticks_msec()
	match name_of:
		"buildings_prepare":
			stage.id = WorkerThreadPool.add_task(_run_buildings_prepare, false, name_of)
		"buildings_place":
			if buildings.data.is_empty():
				_fallback("the building reduction is missing or invalid")
				return
			stage.id = WorkerThreadPool.add_task(_run_buildings_place, false, name_of)
		"buildings_meshes":
			stage.total = _building_jobs.size()
			stage.id = WorkerThreadPool.add_group_task(_run_building_job, _building_jobs.size(), DATA_THREADS, false, name_of)
		"buildings_nodes":
			stage.total = _building_jobs.size()
		"road_prepare":
			stage.id = WorkerThreadPool.add_task(_run_road_prepare, false, name_of)
		"road_sweep":
			if not road.apply_prepared(_prepared):
				_fallback("the road's files are missing or not JSON")
				return
			_roads = _prepared.roads
			_strips.resize(_roads.size())
			stage.total = _roads.size()
			stage.id = WorkerThreadPool.add_group_task(_run_sweep, _roads.size(), DATA_THREADS, false, name_of)
		"terrain_fields":
			terrain.prepare(road.profile)
			stage.id = WorkerThreadPool.add_task(_run_terrain_fields, false, name_of)
		"terrain_meshes":
			if not _fields_ok:
				_fallback("the drape has no terrain lattice")
				return
			stage.total = _terrain_jobs.size()
			stage.id = WorkerThreadPool.add_group_task(_run_terrain_job, _terrain_jobs.size(), DATA_THREADS, false, name_of)
		"forest_place":
			forest.prepare(terrain.profile, terrain.landcover, terrain.ribbons)
			stage.id = WorkerThreadPool.add_task(_run_forest_place, false, name_of)
		"forest_meshes":
			stage.total = _forest_jobs.size()
			stage.id = WorkerThreadPool.add_group_task(_run_forest_job, _forest_jobs.size(), DATA_THREADS, false, name_of)
		"road_nodes":
			stage.total = _strips.size()
		"terrain_nodes":
			stage.total = _terrain_jobs.size()
		"forest_nodes":
			stage.total = _forest_jobs.size()


## Polls a running task or group; releases it when done.
func _poll(name_of: String, stage: Dictionary) -> void:
	if stage.kind == "group":
		stage.done = WorkerThreadPool.get_group_processed_element_count(stage.id)
		if WorkerThreadPool.is_group_task_completed(stage.id):
			WorkerThreadPool.wait_for_group_task_completion(stage.id)
			stage.done = stage.total
			_finish(name_of, stage)
	elif WorkerThreadPool.is_task_completed(stage.id):
		WorkerThreadPool.wait_for_task_completion(stage.id)
		stage.done = 1
		_finish(name_of, stage)


func _finish(name_of: String, stage: Dictionary) -> void:
	stage.finished = true
	stage.ms = Time.get_ticks_msec() - stage.started_ms
	if _log_frames:
		print("loading stage %s: %d ms" % [name_of, stage.ms])


## A node stage's slice of this frame: slots added in CHUNK_ORDER until
## the budget is spent or the stage is done.
func _add_nodes(name_of: String, stage: Dictionary) -> void:
	var until := Time.get_ticks_usec() + int(NODE_BUDGET_MS * 1000.0)
	while stage.done < stage.total and Time.get_ticks_usec() < until:
		var at: int = stage.done
		match name_of:
			"buildings_nodes":
				buildings.add_job(_building_jobs[at])
			"road_nodes":
				road.add_strip(_strips[at])
				_strips[at] = null
			"terrain_nodes":
				terrain.add_job(_terrain_jobs[at])
			"forest_nodes":
				forest.add_job(_forest_jobs[at])
		stage.done = at + 1
	if stage.done < stage.total:
		return
	match name_of:
		"buildings_nodes":
			buildings.finish_build(_started_ms)
		"road_nodes":
			road.finish_build(_started_ms)
		"forest_nodes":
			forest.finish_build(_started_ms)
		"terrain_nodes":
			terrain.build_ms = Time.get_ticks_msec() - _started_ms
	_finish(name_of, stage)


# The workers' callables: each reads what the main thread set before its
# stage was submitted and writes its own slot, nothing else.

func _run_buildings_prepare() -> void:
	buildings.prepare(terrain.profile)


func _run_buildings_place() -> void:
	buildings.place()
	_building_jobs = buildings.mesh_jobs()


func _run_building_job(i: int) -> void:
	if not _cancelled:
		buildings.run_job(_building_jobs[i])


func _run_road_prepare() -> void:
	_prepared = RoadBuilder.prepare_data()


func _run_sweep(i: int) -> void:
	if _cancelled:
		return
	_strips[i] = road.sweep_road(_roads[i])


func _run_terrain_fields() -> void:
	_fields_ok = terrain.compute_fields(road.skeleton_data, road.drape_data, TerrainBuilder.read_landcover())
	if _fields_ok:
		_terrain_jobs = terrain.mesh_jobs()


func _run_terrain_job(i: int) -> void:
	if _cancelled:
		return
	terrain.run_job(_terrain_jobs[i])


func _run_forest_place() -> void:
	forest.place()
	_forest_jobs = forest.mesh_jobs()


func _run_forest_job(i: int) -> void:
	if _cancelled:
		return
	forest.run_job(_forest_jobs[i])


# =============================================================================
#  THE HANDOVER, THE FALLBACK, THE ABANDONMENT
# =============================================================================

## The Ring under the root as the current scene; this scene goes.
func _handover() -> void:
	done = true
	progress = 1.0
	_report()
	var tree := get_tree()
	var built := ring
	ring = null
	_handed = true
	tree.root.add_child(built)
	tree.current_scene = built
	if _log_frames:
		var worst := 0.0
		var worst_at := 0
		var sum := 0.0
		for k: int in frame_deltas_ms.size():
			sum += frame_deltas_ms[k]
			if frame_deltas_ms[k] > worst:
				worst = frame_deltas_ms[k]
				worst_at = k
		print("loading done: %d frames in %d ms, the longest %.1f ms at frame %d [%s], mean %.1f ms; stages: %s" % [frame_deltas_ms.size(), Time.get_ticks_msec() - _started_ms, worst, worst_at + 1, frame_stages[worst_at], sum / maxf(1.0, float(frame_deltas_ms.size())), _stage_times()])
	handed_over.emit(built)
	queue_free()


## The stages by name for a test or a log: {total, done, finished, ms}.
func stages_report() -> Dictionary:
	var out := {}
	for name_of: String in _order:
		var stage: Dictionary = _stages[name_of]
		out[name_of] = {"total": stage.total, "done": stage.done, "finished": stage.finished, "ms": stage.ms}
	return out


## The stages running right now, by name ("" for none).
func stages_running() -> String:
	var names := PackedStringArray()
	for name_of: String in _order:
		if _stages[name_of].started and not _stages[name_of].finished:
			names.append(name_of)
	return ", ".join(names)


func _stage_times() -> String:
	var parts := PackedStringArray()
	for name_of: String in _order:
		parts.append("%s %d ms" % [name_of, _stages[name_of].ms])
	return ", ".join(parts)


## The sync build steps in (the header's THE FALLBACK): the partial Ring
## dropped, a fresh one built the ordinary way as it enters the tree.
func _fallback(reason: String) -> void:
	fallback_reason = reason
	push_warning("LoadingScreen: falling back to the synchronous build: %s" % reason)
	_step.text = "Falling back to the synchronous build: %s" % reason
	_note.text = "The window holds for the build's duration."
	_fallback_build.call_deferred()


func _fallback_build() -> void:
	# One frame drawn with the message, then the freeze the fallback is.
	await get_tree().process_frame
	_wait_for_tasks()
	if ring != null:
		ring.free()
		ring = null
	var packed: PackedScene = load(target_scene)
	if packed == null:
		push_error("LoadingScreen: %s does not load; nothing to hand over" % target_scene)
		return
	var built := packed.instantiate()
	done = true
	progress = 1.0
	_report()
	var tree := get_tree()
	_handed = true
	tree.root.add_child(built)
	tree.current_scene = built
	handed_over.emit(built)
	queue_free()


## Leaving before the handover: the tasks cancelled and waited for, the
## partial Ring freed.
func _abandon() -> void:
	if _handed:
		return
	_cancelled = true
	_wait_for_tasks()
	if ring != null:
		ring.free()
		ring = null


func _wait_for_tasks() -> void:
	for name_of: String in _order:
		var stage: Dictionary = _stages[name_of]
		if not stage.started or stage.finished or stage.kind == "nodes":
			continue
		if stage.kind == "group":
			WorkerThreadPool.wait_for_group_task_completion(stage.id)
		else:
			WorkerThreadPool.wait_for_task_completion(stage.id)
		stage.finished = true


# =============================================================================
#  THE SCREEN
# =============================================================================

## The bar's fraction and the labels from the stages.
func _report() -> void:
	var weight_sum := 0.0
	var weighed := 0.0
	var running := PackedStringArray()
	var running_done := 0
	var running_total := 0
	for name_of: String in _order:
		var stage: Dictionary = _stages[name_of]
		var weight: float = STAGE_WEIGHTS.get(name_of, 1.0)
		weight_sum += weight
		if stage.finished:
			weighed += weight
		elif stage.started:
			weighed += weight * float(stage.done) / float(maxi(stage.total, 1))
			running.append(STAGE_TEXT.get(name_of, name_of))
			running_done += stage.done
			running_total += stage.total
	if not done:
		progress = clampf(weighed / maxf(weight_sum, 1.0e-9), 0.0, 1.0)
	chunks_done = running_done
	chunks_total = running_total
	if done:
		step_name = "The Ring stands"
	elif running.is_empty():
		step_name = "Instancing the Ring"
	else:
		step_name = "\n".join(running)
	if _step != null:
		_step.text = step_name if running_total <= 1 or done else "%s\n%d / %d chunks" % [step_name, running_done, running_total]
		_bar.value = progress * 100.0
		_percent.text = "%d %%" % int(floor(progress * 100.0))


func _build_ui() -> void:
	name = "Loading"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var backdrop := ColorRect.new()
	backdrop.name = "Backdrop"
	backdrop.color = Garage.COLOR_FRAME
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)

	var frame := PanelContainer.new()
	frame.name = "Frame"
	frame.anchor_left = 0.5
	frame.anchor_right = 0.5
	frame.anchor_top = 0.5
	frame.anchor_bottom = 0.5
	frame.offset_left = -FRAME_SIZE.x * 0.5
	frame.offset_right = FRAME_SIZE.x * 0.5
	frame.offset_top = -FRAME_SIZE.y * 0.5
	frame.offset_bottom = FRAME_SIZE.y * 0.5
	var frame_style := StyleBoxFlat.new()
	frame_style.bg_color = Garage.COLOR_FRAME
	frame_style.border_color = Garage.COLOR_BORDER
	frame_style.set_border_width_all(FRAME_BORDER_WIDTH)
	frame_style.set_corner_radius_all(FRAME_CORNER_RADIUS)
	frame_style.set_content_margin_all(FRAME_MARGIN)
	frame.add_theme_stylebox_override("panel", frame_style)
	add_child(frame)

	var column := VBoxContainer.new()
	column.name = "Column"
	column.add_theme_constant_override("separation", 10)
	frame.add_child(column)

	_title = Label.new()
	_title.name = "Title"
	_title.text = "LOADING  —  Nordschleife"
	_title.add_theme_font_size_override("font_size", 30)
	_title.add_theme_color_override("font_color", Garage.COLOR_TITLE)
	column.add_child(_title)

	_step = Label.new()
	_step.name = "Step"
	_step.text = "Instancing the Ring"
	_step.add_theme_font_size_override("font_size", 16)
	_step.add_theme_color_override("font_color", Garage.COLOR_TEXT)
	_step.custom_minimum_size = Vector2(0, 44)
	column.add_child(_step)

	_bar = ProgressBar.new()
	_bar.name = "Bar"
	_bar.min_value = 0.0
	_bar.max_value = 100.0
	_bar.value = 0.0
	_bar.show_percentage = false
	_bar.custom_minimum_size = Vector2(0, BAR_HEIGHT)
	var back := StyleBoxFlat.new()
	back.bg_color = Garage.COLOR_BAR_BACK
	back.set_corner_radius_all(6)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Garage.COLOR_BORDER
	fill.set_corner_radius_all(6)
	_bar.add_theme_stylebox_override("background", back)
	_bar.add_theme_stylebox_override("fill", fill)
	column.add_child(_bar)

	_percent = Label.new()
	_percent.name = "Percent"
	_percent.text = "0 %"
	_percent.add_theme_font_size_override("font_size", 14)
	_percent.add_theme_color_override("font_color", Garage.COLOR_DIM_TEXT)
	column.add_child(_percent)

	_note = Label.new()
	_note.name = "Note"
	_note.text = "The Ring is built beside this screen on worker threads; the window keeps answering.      Esc  back to the pad"
	_note.add_theme_font_size_override("font_size", 14)
	_note.add_theme_color_override("font_color", Garage.COLOR_DIM_TEXT)
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_note)
