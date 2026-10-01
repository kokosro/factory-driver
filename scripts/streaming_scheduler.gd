class_name StreamingScheduler
extends Node
## The L2 streaming scheduler (L2-STREAMING-1 slices 1+2; decisions.org
## C07BE6F1, the driver's canon of 2026-09-27: "no freezing load,
## world-around-the-car streaming"; the ruling FD79B028 of 2026-10-01:
## about 2 km of dressed vicinity is enough, the loading screen vanishes
## the moment the car can roll, the tail streams with no bar, every road's
## mesh stays resident; docs/design/l2-streaming-design.md). An autoload
## (project.godot, Streaming) on the ShellsWatch / MarksWatch pattern: it
## watches the tree's node_added, no builder is edited for it and no scene
## file names it.
##
## WHAT IT DOES. The loading scene (scripts/loading.gd) claims its Ring
## here while the Ring is still outside the tree - claim(), the
## BuildingsShells.of() precedent - and hands each of the three dressing
## builders' job lists through split(): the RESIDENT jobs and the VICINITY
## chunks come back in CHUNK_ORDER and are built behind the bar as ever;
## the rest, the TAIL, stays here. When the claimed Ring enters the tree
## (the handover: node_added) the tail streams: each chunk's data stage on
## a WorkerThreadPool task, DATA_THREADS in flight at most, each chunk's
## node stage on the main thread under NODE_BUDGET_MS a frame - the loading
## scene's seam and its two numbers, so nothing new runs on the main thread
## un-budgeted. No bar: the screen is gone, the car already drives.
##
## WHAT STREAMS, WHAT IS RESIDENT. The streaming unit is the builders' own
## 1 km chunk: a terrain "near" job (Near_<row>_<col>, 42 of them), a
## forest "walls" or "trees" job (Walls_<x>_<z>, Trees_<x>_<z>), a
## buildings mesh job (<element>_<x>_<z>). Everything else is resident and
## built before the handover whatever the car's position: the terrain's
## Mid, Far, Water, the Band_ apron of every road and the four
## Continuation_ bands, the forest's trunk bodies and the buildings' rail
## and solid bodies (the two bubbles' fixed input: PhysicsBubble.attach
## takes them once, in finish_build), and - never through here at all -
## the road's strips, their colliders, the floor slab and the profile.
## Every streamed chunk is a picture: TerrainBuilder is visuals only, a
## wall or a crown carries no shape, a shell's mesh none either; the car
## reads the profile and the floor slab, both resident, so a chunk not yet
## there shows a hole and changes no physics read
## (tests/streaming_test.gd drives the same 2 km on a one-shot build and
## while the tail streams and lands on the same bit).
##
## THE BANDS. A chunk's distance is the horizontal distance from the car
## to the chunk's BOX, the bubble's own measure (PhysicsBubble: 0 inside
## the box, the gap to its nearest edge outside). A chunk within
## R_HANDOVER_M of the car's start position (the Ring scene's pit anchor,
## read off the claimed scene's car when the first list is split) is
## vicinity; past it, tail. In the tail a chunk's band is its distance
## over BAND_M, rounded down, from where the car is NOW.
##
## THE ORDER. Whenever a flight slot is free the next chunk is the pending
## one with the smallest (band, builder, CHUNK_ORDER index) - the builders
## in the order Terrain, Forest, Buildings, the index the job's place in
## its builder's own mesh_jobs() list - and the chunks are added under
## their builders in the order they were dispatched, never in the order
## the workers finished. The order is therefore a function of the car's
## positions and the chunk states alone; for a car standing still it is
## the pending chunks sorted by (band, builder, CHUNK_ORDER), which the
## tests pin. `arrivals` keeps it.
##
## DETERMINISM AND COST (the bubble's and the loading scene's contract):
## a job's data stage is a pure function of the checked-in files, so a
## streamed chunk's arrays are the one-shot build's to the byte whenever
## and in whatever order it is built. No RNG; the wall clock is read only
## for the frame's node budget and the probe line, never into a result.
## step() is one pass over the chunk table per free flight slot (some
## hundreds of entries, squared distances) and allocates nothing: the
## table is packed arrays sized at the split, the flight queue a packed
## array with two cursors. step(at) is public so a test drives it by hand.
##
## THE COUNTS. A builder's counts and describe() are session totals merged
## at each add (their own add_job): at the handover they read the resident
## set plus the vicinity, and they reach the one-shot build's values to
## the integer when the tail completes. This node's own counters are
## additive and new: chunks_total, chunks_at_handover, chunks_streamed.
## Nothing built is retired in this landing (slices 3 and 4).
##
## CANCELLING. The tail belongs to this node, not to the loading scene
## (which is freed at the handover; its own contract, "a task never
## outlives this node", covers its own tasks). When the Ring leaves the
## tree (Esc to the pad, a test unloading it, the window closed) or this
## node does, the tasks in flight skip their work if they have not begun,
## are waited for (a chunk's data stage: some tens of milliseconds, a
## heavy terrain chunk a few hundred) and everything is dropped: a task
## never outlives the Ring it builds for. A Ring abandoned before the
## handover is released by the loading scene (release()).
##
## NEVER ON A SYNC BUILD. Only a claimed scene streams, and claim() takes
## only a scene outside the tree whose four builders are build_deferred -
## the loading scene's async path. A Ring instanced the ordinary way (every
## suite scene, the fallback) builds whole in _ready and this node never
## looks at it; the pad has no builders at all.
##
## FD_LOADING_FRAMES=1 in the environment prints one line per streamed
## chunk and a summary when the tail completes (the loading scene's probe,
## extended; never in the suite's lines).

## The claimed Ring entered the tree and its tail began to stream.
signal tail_started(ring: Node)
## One tail chunk was added under its builder.
signal chunk_streamed(builder: String, chunk: String)
## Every tail chunk is in: the Ring stands whole.
signal tail_completed(ring: Node)

## The autoload's node name under the tree's root (project.godot's
## [autoload] key), reached by name through of().
const AUTOLOAD_NAME := "Streaming"

## The vicinity [m]: a chunk whose box is within this of the car's start
## position is built before the handover (the ruling: about 2 km).
const R_HANDOVER_M := 2000.0
## A band's width [m] in the tail's order: the chunk's own size.
const BAND_M := 1000.0

## The tail's workers and the node stage's frame budget [ms]: the loading
## scene's DATA_THREADS and NODE_BUDGET_MS, the same numbers.
const DATA_THREADS := 4
const NODE_BUDGET_MS := 8.0

## The builders that stream, in the order's rank, by node name.
const BUILDERS: Array[String] = ["Terrain", "Forest", "Buildings"]
const TERRAIN := 0
const FOREST := 1
const BUILDINGS := 2

## A chunk's state in the table.
const PENDING := 0
const FLYING := 1
const ADDED := 2

## The rank's stride per builder (a builder's list is some thousands of
## jobs at most) and the key's per band.
const RANK_STRIDE := 1 << 20
const BAND_STRIDE := 1 << 24

## The claimed Ring (null: nothing claimed) and whether its tail streams.
var ring: Node = null
var streaming := false
## The car's start position the vicinity was measured from.
var origin := Vector3.ZERO
## The counters: streamable chunks in all, those built before the handover
## (the vicinity), those streamed after it.
var chunks_total := 0
var chunks_at_handover := 0
var chunks_streamed := 0
## The tail's arrival order, "<Builder>/<chunk name>" per chunk added.
var arrivals := PackedStringArray()

var _car: Node3D = null
var _nodes: Array = [null, null, null]
var _origin_set := false
## The tail's table, one entry per chunk: the job, its builder, its rank
## (builder, CHUNK_ORDER index), its box (x_lo, z_lo, x_hi, z_hi), its
## state and its pool task.
var _jobs: Array = []
var _builder := PackedByteArray()
var _rank := PackedInt32Array()
var _boxes := PackedFloat64Array()
var _state := PackedByteArray()
var _task := PackedInt64Array()
## The flight queue: table indices in dispatch order, the head the next
## to add, the tail the next free slot.
var _flight := PackedInt32Array()
var _flight_head := 0
var _flight_tail := 0
var _pending := 0
var _cancelled := false
var _log := false
var _began_ms := 0


## The scheduler in `tree`, or null where the autoload is not registered.
static func of(tree: SceneTree) -> StreamingScheduler:
	return tree.root.get_node_or_null(AUTOLOAD_NAME) as StreamingScheduler


func _enter_tree() -> void:
	# The tail streams behind a paused tree too (the garage open, the map).
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().node_added.connect(_on_node_added)


func _ready() -> void:
	# Nothing to do every frame until a claimed Ring hands over.
	set_process(streaming)


func _exit_tree() -> void:
	get_tree().node_added.disconnect(_on_node_added)
	_drop()


# =============================================================================
#  THE CLAIM AND THE SPLIT (the loading scene's calls, before the handover)
# =============================================================================

## Claims `scene` for streaming: a Ring outside the tree whose four
## builders the loading scene has deferred. False (and nothing claimed)
## for anything else - the caller then builds every chunk itself.
func claim(scene: Node) -> bool:
	if scene == null or scene.is_inside_tree():
		return false
	var road := scene.get_node_or_null("Road") as RoadBuilder
	var terrain := scene.get_node_or_null("Terrain") as TerrainBuilder
	var forest := scene.get_node_or_null("Forest") as ForestWalls
	var buildings := scene.get_node_or_null("Buildings") as BuildingsShells
	if road == null or terrain == null or forest == null or buildings == null:
		return false
	if not (road.build_deferred and terrain.build_deferred and forest.build_deferred and buildings.build_deferred):
		return false
	_drop()
	ring = scene
	_car = road.car
	_nodes = [terrain, forest, buildings]
	_log = OS.get_environment("FD_LOADING_FRAMES") == "1"
	return true


## Gives up `scene` (the loading scene abandoned or fell back before the
## handover): the tail's jobs dropped, none of them ever run.
func release(scene: Node) -> void:
	if scene != null and scene == ring:
		_drop()


## Splits one builder's mesh_jobs() list (`jobs`, in CHUNK_ORDER): returns
## the jobs to build before the handover - the resident ones and the
## vicinity chunks, in CHUNK_ORDER - and files the others as the tail.
## Main thread, once per builder. An unclaimed scheduler returns `jobs`.
func split(builder: int, jobs: Array) -> Array:
	if ring == null or streaming:
		return jobs
	if not _origin_set:
		# The Ring is outside the tree: the car's own transform under the
		# scene's root, the pit anchor the scene file gives it.
		origin = _car.position if _car != null else Vector3.ZERO
		_origin_set = true
	var now := []
	var limit_sq := R_HANDOVER_M * R_HANDOVER_M
	for k: int in jobs.size():
		var box := chunk_box(builder, _nodes[builder], jobs[k])
		if box.is_empty():
			now.append(jobs[k])
			continue
		chunks_total += 1
		if box_distance_squared(box, origin.x, origin.z) <= limit_sq:
			chunks_at_handover += 1
			now.append(jobs[k])
			continue
		_jobs.append(jobs[k])
		_builder.append(builder)
		_rank.append(builder * RANK_STRIDE + k)
		_boxes.append_array(box)
		_state.append(PENDING)
		_task.append(-1)
	_pending = _jobs.size()
	_flight.resize(_jobs.size())
	return now


## A job's chunk box (x_lo, z_lo, x_hi, z_hi) [m], or an empty array for a
## resident job (one that never streams). The terrain's near chunks stand
## on the tile grid from the lattice's origin, row `index` along +z and
## column `index2` along +x; the forest's and the buildings' on the world
## grid of CHUNK_M their keys are cut on.
static func chunk_box(builder: int, node: Node, job: RefCounted) -> PackedFloat64Array:
	match builder:
		TERRAIN:
			var terrain := node as TerrainBuilder
			var near := job as TerrainBuilder.MeshJob
			if near.kind != "near":
				return PackedFloat64Array()
			var x := terrain.x0 + near.index2 * TerrainBuilder.CHUNK_M
			var z := terrain.z0 + near.index * TerrainBuilder.CHUNK_M
			return PackedFloat64Array([x, z, x + TerrainBuilder.CHUNK_M, z + TerrainBuilder.CHUNK_M])
		FOREST:
			var chunk := job as ForestWalls.MeshJob
			if chunk.kind == "trunks":
				return PackedFloat64Array()
			return _grid_box(chunk.key.x, chunk.key.y, ForestWalls.CHUNK_M)
		BUILDINGS:
			var group := job as BuildingsShells.MeshJob
			if group.solid or group.members.is_empty():
				return PackedFloat64Array()
			var p: Vector2 = group.members[0].position
			return _grid_box(floori(p.x / BuildingsShells.CHUNK_M), floori(p.y / BuildingsShells.CHUNK_M), BuildingsShells.CHUNK_M)
	return PackedFloat64Array()


static func _grid_box(i: int, j: int, size: float) -> PackedFloat64Array:
	return PackedFloat64Array([i * size, j * size, (i + 1) * size, (j + 1) * size])


## The squared horizontal distance from (x, z) to a box: 0 inside (the
## bubble's measure).
static func box_distance_squared(box: PackedFloat64Array, x: float, z: float, at: int = 0) -> float:
	var dx := maxf(0.0, maxf(box[at] - x, x - box[at + 2]))
	var dz := maxf(0.0, maxf(box[at + 1] - z, z - box[at + 3]))
	return dx * dx + dz * dz


## The band of a distance [m]: whole BAND_M, rounded down.
static func band_of(distance: float) -> int:
	return int(floor(distance / BAND_M))


# =============================================================================
#  THE TAIL (after the handover)
# =============================================================================

func _on_node_added(node: Node) -> void:
	if ring != null and node == ring and not streaming:
		_begin()


## The claimed Ring is in the tree: the tail streams from the next frame.
func _begin() -> void:
	streaming = true
	_cancelled = false
	_began_ms = Time.get_ticks_msec()
	ring.tree_exiting.connect(_on_ring_exiting, CONNECT_ONE_SHOT)
	if _log:
		print("streaming: the handover with %d of %d chunks within %.0f m of (%.0f, %.0f); %d to stream" % [chunks_at_handover, chunks_total, R_HANDOVER_M, origin.x, origin.z, _pending])
	tail_started.emit(ring)
	set_process(true)
	if _jobs.is_empty():
		_complete()


func _on_ring_exiting() -> void:
	_drop()


func _process(_delta: float) -> void:
	if not streaming:
		return
	step(_car.global_position if _car != null and _car.is_inside_tree() else origin)


## One frame of the tail with the car at `at`: the chunks whose data stage
## is done are added in dispatch order until the frame's node budget is
## spent, then the free flight slots are filled with the nearest pending
## chunks (the header's THE ORDER).
func step(at: Vector3) -> void:
	if not streaming:
		return
	var until := Time.get_ticks_usec() + int(NODE_BUDGET_MS * 1000.0)
	while _flight_head < _flight_tail and Time.get_ticks_usec() < until:
		var i := _flight[_flight_head]
		if not WorkerThreadPool.is_task_completed(_task[i]):
			break
		WorkerThreadPool.wait_for_task_completion(_task[i])
		_flight_head += 1
		_add(i)
	while _pending > 0 and _flight_tail - _flight_head < DATA_THREADS:
		var next := _next_pending(at.x, at.z)
		_state[next] = FLYING
		_pending -= 1
		_flight[_flight_tail] = next
		_flight_tail += 1
		_task[next] = WorkerThreadPool.add_task(_run.bind(next), false, "streaming")
	if _pending == 0 and _flight_head == _flight_tail:
		_complete()


## The pending chunk with the smallest (band, builder, CHUNK_ORDER index)
## for a car at (x, z).
func _next_pending(x: float, z: float) -> int:
	var best := -1
	var best_key := 0
	for i: int in _state.size():
		if _state[i] != PENDING:
			continue
		var key := band_of(sqrt(box_distance_squared(_boxes, x, z, i * 4))) * BAND_STRIDE + _rank[i]
		if best < 0 or key < best_key:
			best = i
			best_key = key
	return best


## A worker's: one chunk's data stage into its own job (the builder's
## run_job, a pure function of what the builder holds), nothing else.
func _run(i: int) -> void:
	if _cancelled:
		return
	_nodes[_builder[i]].run_job(_jobs[i])


## The node stage of one chunk (main thread): the builder's own add_job.
func _add(i: int) -> void:
	var job: RefCounted = _jobs[i]
	_nodes[_builder[i]].add_job(job)
	_jobs[i] = null
	_state[i] = ADDED
	chunks_streamed += 1
	var builder_name := BUILDERS[_builder[i]]
	var chunk_name: String = job.get("name")
	arrivals.append(builder_name + "/" + chunk_name)
	if _log:
		print("streaming chunk %d / %d: %s/%s" % [chunks_streamed, _jobs.size(), builder_name, chunk_name])
	chunk_streamed.emit(builder_name, chunk_name)


func _complete() -> void:
	streaming = false
	set_process(false)
	if _log:
		print("streaming done: %d chunks in %d ms after the handover; %s" % [chunks_streamed, Time.get_ticks_msec() - _began_ms, describe()])
	tail_completed.emit(ring)


## Cancels what is in flight, waits for it and forgets the Ring (the
## header's CANCELLING): the counters and the arrivals are the claimed
## Ring's and go with it.
func _drop() -> void:
	_cancelled = true
	while _flight_head < _flight_tail:
		WorkerThreadPool.wait_for_task_completion(_task[_flight[_flight_head]])
		_flight_head += 1
	if ring != null and is_instance_valid(ring) and ring.tree_exiting.is_connected(_on_ring_exiting):
		ring.tree_exiting.disconnect(_on_ring_exiting)
	chunks_total = 0
	chunks_at_handover = 0
	chunks_streamed = 0
	arrivals = PackedStringArray()
	ring = null
	streaming = false
	set_process(false)
	_car = null
	_nodes = [null, null, null]
	_origin_set = false
	_jobs = []
	_builder = PackedByteArray()
	_rank = PackedInt32Array()
	_boxes = PackedFloat64Array()
	_state = PackedByteArray()
	_task = PackedInt64Array()
	_flight = PackedInt32Array()
	_flight_head = 0
	_flight_tail = 0
	_pending = 0


## How many tail chunks are still to come (pending or in flight).
func chunks_remaining() -> int:
	return _pending + _flight_tail - _flight_head


## One line: the counters and the state.
func describe() -> String:
	return "%d streamable chunks, %d at the handover (within %.0f m), %d streamed after it, %d to come, %s" % [chunks_total, chunks_at_handover, R_HANDOVER_M, chunks_streamed, chunks_remaining(), "streaming" if streaming else ("claimed" if ring != null else "idle")]
