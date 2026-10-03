class_name StreamingScheduler
extends Node
## The L2 streaming scheduler (L2-STREAMING-1 slices 1+2, 3 and 4;
## decisions.org C07BE6F1, the driver's canon of 2026-09-27: "no freezing
## load, world-around-the-car streaming"; the ruling FD79B028 of
## 2026-10-01: about 2 km of dressed vicinity is enough, the loading
## screen vanishes the moment the car can roll, the tail streams with no
## bar, every road's mesh stays resident, far chunks RETIRE and rebuild on
## return; docs/design/l2-streaming-design.md). An autoload
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
## hundreds of entries, squared distances) and, once the tail has
## completed, one more for the retire bands; the table is packed arrays
## sized at the split, the flight queue a packed ring of DATA_THREADS
## slots with two cursors. Nothing is allocated but at a transition: a
## rebuild's job record and the copy of its builder's totals, a retired
## near chunk's stand-in (below).
## step(at) is public so a test drives it by hand.
##
## THE COUNTS. A builder's counts and describe() are session totals merged
## at each add (their own add_job): at the handover they read the resident
## set plus the vicinity, and they reach the one-shot build's values to
## the integer when the tail completes - and stay there: a retirement
## takes nothing from them and a rebuild adds nothing to them. This node's
## own counters are additive and never fall while the Ring is claimed:
## chunks_total, chunks_at_handover, chunks_streamed, chunks_retired,
## chunks_rebuilt.
##
## THE RETIREMENT (slice 3, the ruling's "RETIRE far chunks and accept a
## rebuild on return", the bubble's hysteresis). Once the tail has
## completed - every chunk built once, the builders' totals whole: the
## step that completes it retires nothing, so tail_completed fires on a
## whole Ring - each step holds the tail's chunks against two radii, the
## distance again the car's to the chunk's box:
##   - a chunk standing whose box is farther than R_RETIRE_OUT_M is
##     RETIRED: its node (the MeshInstance3D and the mesh it holds) is
##     taken from under its builder and freed; its job record - the name
##     and the inputs of its data stage - is kept, and so is every tally;
##   - a retired chunk whose box is nearer than R_RETIRE_IN_M goes back to
##     the pending set and is REBUILT by the tail's own path: nearest
##     first by the same key, its data stage on a worker (the builder's
##     add_job released the first build's arrays, so the stage runs again
##     on a fresh copy of the record, as mesh_jobs() made it - a pure
##     function of the checked-in files: the same bytes), its node stage
##     on the main thread under the same budget;
##   - between the two radii nothing changes: a chunk standing stays, a
##     retired one stays retired (a car idling at one radius never
##     flickers a chunk), and exactly at a radius likewise - the bubble's
##     strict comparisons. A rebuild still pending when its box passes
##     R_RETIRE_OUT_M again is dropped from the pending set, unbuilt; one
##     already in flight lands and retires in a later step.
## The decision is a function of the car's position and the chunk states
## alone. The frees share the frame's NODE_BUDGET_MS with the adds (the
## adds first: they are what the driver is near), in the order (builder,
## CHUNK_ORDER); the budget decides only how many frames a standing car's
## retirements take, never their order nor the state they end in.
## ONLY the tail's chunks retire: the vicinity's (built behind the bar by
## the loading scene, never this node's) and every resident job stand for
## the session, as does everything on a Ring this node never claimed.
##
## THE STAND-IN (slice 4, the ruling's "terrain near-band retirement with
## the 50 m stand-in"; the design's "a retiring near chunk swaps to one
## Mid-style 50 m quad per tile built from the same fields (pure), so no
## hole shows; rebuild restores the fine mesh"). A terrain near chunk that
## retires leaves its place to a stand-in, Standin_<row>_<col> under
## Terrain: TerrainBuilder.standin_job(), a pure function of the same
## resident fields the near mesh reads, built and added in the retirement
## itself, on the main thread, after the fine child is freed - at the fine
## child's own index among Terrain's children, so the children's order is
## the transitions' and never the frames'. The rebuild's add frees the
## stand-in FIRST and adds the fine mesh after it, in one call: no frame
## shows both, none shows neither. A near chunk with nothing in it never
## had a child and gets no stand-in; a forest or buildings chunk has none
## (their retirement leaves air, as slice 3 left it).
## WHAT IT IS (TerrainBuilder's header, THE STAND-IN): a near tile no road
## reaches is ONE 50 m quad at its corners; a near tile a road reaches
## keeps its 10 m cells, each kept or dropped by the near mesh's own rule
## (a cell with a node inside a road's reach is the road's apron's, which
## is resident) - a 50 m chord across a road in a cutting would roof it,
## and a tile left out would open a 50 m slit beside every road. The
## stand-in covers exactly the cells the near mesh covered, BY DESIGN: no
## hole, no slit, no roof - the trade slice 4 makes for the hole it
## closes is what that coverage keeps resident. No tally anywhere: the
## builder's counts, elements and describe() are the session's totals of
## the near meshes and never move for a stand-in, and none of this node's
## five counters counts one (chunks_stood_in() is the state). The
## stand-ins are the Ring's children and go with it: this node forgets
## them wherever it forgets the Ring.
## MEASURED (2026-10-03, this machine, headless). Triangles, over the
## Ring's 42 near chunks: 593 266 -> 280 238 (47 %); a chunk's stand-in
## 2 842 to 8 892 for a near mesh of 7 398 to 16 820 - from 24 %
## (Near_5_4: 3 796 for 16 018) to 69 % (Near_5_1: 5 102 for 7 398), the
## largest Near_2_4's 8 892 for 12 992 (68 %): the Ring has 3 304 roads
## and about half its near cells lie in tiles one reaches. Arrays as
## built: 20.8 MB -> 13.1 MB, so a retired near chunk gives back 37 % of
## its near mesh's arrays and keeps 63 %; in the process's static memory
## the pit anchor's 24 near chunks of the tail hold 6.38 MB standing and
## 4.39 MB as stand-ins (69 % kept). The main thread, inside the
## retirement: the stand-in's data stage 3.3 to 7.4 ms a chunk (mean
## 6.3 ms, GDScript), its add 0.25 ms. NODE_BUDGET_MS (8.0) is read
## before each retirement, so one begins only while the frame's budget
## lasts and the one that runs past it is the frame's last: a step with
## one terrain retirement measured 4.1 to 9.4 ms, with two 11.3 to
## 15.6 ms (stepped by hand at the pit anchor, then 57 km off at once:
## the tail's 24 near chunks over 13 steps), a step of 122 forest and
## buildings retirements 0.7 ms. THE NAMED FOLLOW-UP, not
## built: the stand-in's data stage on a worker, as the rebuild's is - a
## prefetch or an asynchronous retirement, either one new machinery and
## new pins - if the driver ever feels that frame.
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
## chunk, a summary when the tail completes, one line per retirement and
## per rebuild and one per stand-in put up and taken down (the loading
## scene's probe, extended; never in the suite's lines).

## The claimed Ring entered the tree and its tail began to stream.
signal tail_started(ring: Node)
## One tail chunk was added under its builder.
signal chunk_streamed(builder: String, chunk: String)
## Every tail chunk is in: the Ring stands whole (once per claimed Ring;
## the retirements begin with the next step).
signal tail_completed(ring: Node)
## One tail chunk past R_RETIRE_OUT_M was freed from under its builder (a
## terrain near chunk's stand-in already in its place).
signal chunk_retired(builder: String, chunk: String)
## One retired chunk back within R_RETIRE_IN_M was added again (its
## stand-in already freed).
signal chunk_rebuilt(builder: String, chunk: String)

## The autoload's node name under the tree's root (project.godot's
## [autoload] key), reached by name through of().
const AUTOLOAD_NAME := "Streaming"

## The vicinity [m]: a chunk whose box is within this of the car's start
## position is built before the handover (the ruling: about 2 km).
const R_HANDOVER_M := 2000.0
## A band's width [m] in the tail's order: the chunk's own size.
const BAND_M := 1000.0
## The retire band [m] (the ruling; the bubble's 80 / 110 ratio): a tail
## chunk whose box is farther than R_RETIRE_OUT_M from the car is retired,
## a retired one nearer than R_RETIRE_IN_M is rebuilt, between them
## nothing changes.
const R_RETIRE_IN_M := 3000.0
const R_RETIRE_OUT_M := 4500.0

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
const RETIRED := 3

## The rank's stride per builder (a builder's list is some thousands of
## jobs at most) and the key's per band.
const RANK_STRIDE := 1 << 20
const BAND_STRIDE := 1 << 24

## The claimed Ring (null: nothing claimed), whether its tail streams and
## whether the tail has completed (every chunk built once: from the next
## step the retire band is watched).
var ring: Node = null
var streaming := false
var tail_done := false
## The car's start position the vicinity was measured from.
var origin := Vector3.ZERO
## The counters: streamable chunks in all, those built before the handover
## (the vicinity), those streamed after it; the retirements and the
## rebuilds since (a chunk counts each time).
var chunks_total := 0
var chunks_at_handover := 0
var chunks_streamed := 0
var chunks_retired := 0
var chunks_rebuilt := 0
## The tail's arrival order, "<Builder>/<chunk name>" per chunk added.
var arrivals := PackedStringArray()

var _car: Node3D = null
var _nodes: Array = [null, null, null]
var _origin_set := false
## The tail's table, one entry per chunk: the job (kept after the add as
## the chunk's record: a rebuild's data stage is made from it), its
## builder, its rank (builder, CHUNK_ORDER index), its box (x_lo, z_lo,
## x_hi, z_hi), its state and its pool task; and the table's indices by
## rank, the retire pass's order.
var _jobs: Array = []
var _builder := PackedByteArray()
var _rank := PackedInt32Array()
var _boxes := PackedFloat64Array()
var _state := PackedByteArray()
var _task := PackedInt64Array()
var _by_rank := PackedInt32Array()
## The stand-ins standing (THE STAND-IN), by the retired near chunk's
## table index: the MeshInstance3D under Terrain.
var _standins: Dictionary = {}
## The flight queue: table indices in dispatch order, a ring of
## DATA_THREADS slots (a cursor's slot is the cursor modulo that), the
## head the next to add, the tail the next free slot.
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
	if ring == null or streaming or tail_done:
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
	_flight.resize(DATA_THREADS)
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
	if ring != null and node == ring and not streaming and not tail_done:
		_begin()


## The claimed Ring is in the tree: the tail streams from the next frame.
func _begin() -> void:
	streaming = true
	_cancelled = false
	_began_ms = Time.get_ticks_msec()
	var by_rank: Array = range(_jobs.size())
	by_rank.sort_custom(func(a: int, b: int) -> bool: return _rank[a] < _rank[b])
	_by_rank = PackedInt32Array(by_rank)
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
	if not streaming and not tail_done:
		return
	step(_car.global_position if _car != null and _car.is_inside_tree() else origin)


## One frame of the tail with the car at `at`: the chunks whose data stage
## is done are added in dispatch order until the frame's node budget is
## spent; once the tail has completed, the retire band is watched (the
## header's THE RETIREMENT; the frees on what is left of the budget); then
## the free flight slots are filled with the nearest pending chunks (the
## header's THE ORDER).
func step(at: Vector3) -> void:
	if not streaming and not tail_done:
		return
	var until := Time.get_ticks_usec() + int(NODE_BUDGET_MS * 1000.0)
	while _flight_head < _flight_tail and Time.get_ticks_usec() < until:
		var i := _flight[_flight_head % DATA_THREADS]
		if not WorkerThreadPool.is_task_completed(_task[i]):
			break
		WorkerThreadPool.wait_for_task_completion(_task[i])
		_flight_head += 1
		_add(i)
	if tail_done:
		_watch(at.x, at.z, until)
	while _pending > 0 and _flight_tail - _flight_head < DATA_THREADS:
		var next := _next_pending(at.x, at.z)
		if tail_done:
			_jobs[next] = _record_again(_builder[next], _jobs[next])
		_state[next] = FLYING
		_pending -= 1
		_flight[_flight_tail % DATA_THREADS] = next
		_flight_tail += 1
		_task[next] = WorkerThreadPool.add_task(_run.bind(next), false, "streaming")
	if streaming and _pending == 0 and _flight_head == _flight_tail:
		_complete()


## The retire band for a car at (x, z), the table walked in the order
## (builder, CHUNK_ORDER): a standing chunk past R_RETIRE_OUT_M is retired
## while the frame's budget lasts (`until`, the clock's; the others wait
## for the next step), a retired one inside R_RETIRE_IN_M joins the
## pending set, a rebuild still pending past R_RETIRE_OUT_M leaves it.
## Every pending chunk here is a rebuild: the tail has completed.
func _watch(x: float, z: float, until: int) -> void:
	var in_sq := R_RETIRE_IN_M * R_RETIRE_IN_M
	var out_sq := R_RETIRE_OUT_M * R_RETIRE_OUT_M
	for k: int in _by_rank.size():
		var i := _by_rank[k]
		var state := _state[i]
		if state == FLYING:
			continue
		var d_sq := box_distance_squared(_boxes, x, z, i * 4)
		if state == RETIRED:
			if d_sq < in_sq:
				_state[i] = PENDING
				_pending += 1
		elif d_sq > out_sq:
			if state == PENDING:
				_state[i] = RETIRED
				_pending -= 1
			elif Time.get_ticks_usec() < until:
				_retire(i)


## One standing chunk retired (main thread): its node taken from under its
## builder and freed with the mesh it holds - none for a near chunk with
## nothing in it, which never had one - its record and every tally kept.
## A terrain near chunk's stand-in takes the freed child's place (THE
## STAND-IN: built here from the builder's fields, added at the child's
## own index, no tally touched).
func _retire(i: int) -> void:
	var node: Node = _nodes[_builder[i]]
	var chunk_name: String = _jobs[i].get("name")
	var child := node.get_node_or_null(NodePath(chunk_name))
	if child != null:
		var place := child.get_index()
		node.remove_child(child)
		child.free()
		if _builder[i] == TERRAIN:
			_stand_in(i, place)
	_state[i] = RETIRED
	chunks_retired += 1
	var builder_name := BUILDERS[_builder[i]]
	if _log:
		print("streaming retire %d: %s/%s" % [chunks_retired, builder_name, chunk_name])
	chunk_retired.emit(builder_name, chunk_name)


## The stand-in of the terrain near chunk `i`, put up at index `place`
## among Terrain's children (the fine child's, just freed).
func _stand_in(i: int, place: int) -> void:
	var terrain := _nodes[TERRAIN] as TerrainBuilder
	var near := _jobs[i] as TerrainBuilder.MeshJob
	var job := terrain.standin_job(near.index, near.index2)
	var standin := terrain.add_standin(job)
	if standin == null:
		return
	terrain.move_child(standin, place)
	_standins[i] = standin
	if _log:
		print("streaming stand-in up: Terrain/%s (%d triangles), %d standing" % [job.name, job.indices.size() / 3, _standins.size()])


## The stand-in of chunk `i` taken down and freed with its mesh, where one
## stands (the rebuild's add: before the fine mesh is added).
func _stand_down(i: int) -> void:
	if not _standins.has(i):
		return
	var standin: Node = _standins[i]
	_standins.erase(i)
	var standin_name := String(standin.name)
	standin.get_parent().remove_child(standin)
	standin.free()
	if _log:
		print("streaming stand-in down: Terrain/%s, %d standing" % [standin_name, _standins.size()])


## A retired chunk's job as its builder's mesh_jobs() made it, from the
## record kept: the same name and inputs, nothing of the first run (the
## arrays went into the mesh at the add; the tallies were merged there).
static func _record_again(builder: int, job: RefCounted) -> RefCounted:
	match builder:
		TERRAIN:
			var near := job as TerrainBuilder.MeshJob
			return TerrainBuilder.MeshJob.make(near.kind, near.name, near.index, near.index2)
		FOREST:
			var chunk := job as ForestWalls.MeshJob
			var again := ForestWalls.MeshJob.make(chunk.kind, chunk.name, chunk.key)
			again.members = chunk.members
			again.by_archetype = chunk.by_archetype
			return again
		BUILDINGS:
			var group := job as BuildingsShells.MeshJob
			var again := BuildingsShells.MeshJob.new()
			again.name = group.name
			again.element = group.element
			again.members = group.members
			return again
	return job


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
## The job stays in the table as the chunk's record (add_job released its
## arrays). A rebuild's add leaves the builder's counts and elements as
## they stood: the totals are the session's, and they hold this chunk
## since its first add; a near chunk's stand-in is freed first, the fine
## mesh added after it (THE STAND-IN: never both, never neither).
func _add(i: int) -> void:
	var job: RefCounted = _jobs[i]
	var node: Variant = _nodes[_builder[i]]
	var builder_name := BUILDERS[_builder[i]]
	var chunk_name: String = job.get("name")
	_state[i] = ADDED
	if tail_done:
		_stand_down(i)
		var counts: Dictionary = node.counts.duplicate()
		var elements: Dictionary = node.elements.duplicate()
		node.add_job(job)
		node.counts.clear()
		node.counts.merge(counts)
		node.elements.clear()
		node.elements.merge(elements)
		chunks_rebuilt += 1
		if _log:
			print("streaming rebuild %d: %s/%s" % [chunks_rebuilt, builder_name, chunk_name])
		chunk_rebuilt.emit(builder_name, chunk_name)
		return
	node.add_job(job)
	chunks_streamed += 1
	arrivals.append(builder_name + "/" + chunk_name)
	if _log:
		print("streaming chunk %d / %d: %s/%s" % [chunks_streamed, _jobs.size(), builder_name, chunk_name])
	chunk_streamed.emit(builder_name, chunk_name)


## The tail is in: the Ring stands whole, and from the next step the
## retire band is watched (nothing to watch where no chunk streamed).
func _complete() -> void:
	streaming = false
	tail_done = true
	set_process(not _jobs.is_empty())
	if _log:
		print("streaming done: %d chunks in %d ms after the handover; %s" % [chunks_streamed, Time.get_ticks_msec() - _began_ms, describe()])
	tail_completed.emit(ring)


## Cancels what is in flight, waits for it and forgets the Ring (the
## header's CANCELLING): the counters and the arrivals are the claimed
## Ring's and go with it, and so do the stand-ins - the Ring's children,
## freed with it, here only forgotten.
func _drop() -> void:
	_cancelled = true
	while _flight_head < _flight_tail:
		WorkerThreadPool.wait_for_task_completion(_task[_flight[_flight_head % DATA_THREADS]])
		_flight_head += 1
	if ring != null and is_instance_valid(ring) and ring.tree_exiting.is_connected(_on_ring_exiting):
		ring.tree_exiting.disconnect(_on_ring_exiting)
	chunks_total = 0
	chunks_at_handover = 0
	chunks_streamed = 0
	chunks_retired = 0
	chunks_rebuilt = 0
	arrivals = PackedStringArray()
	ring = null
	streaming = false
	tail_done = false
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
	_by_rank = PackedInt32Array()
	_standins = {}
	_flight = PackedInt32Array()
	_flight_head = 0
	_flight_tail = 0
	_pending = 0


## How many tail chunks are still to come (pending or in flight): the
## tail's while it streams, the rebuilds' after it.
func chunks_remaining() -> int:
	return _pending + _flight_tail - _flight_head


## How many of the tail's chunks are retired now (a state, not a counter:
## chunks_retired counts the retirements).
func chunks_away() -> int:
	return _state.count(RETIRED)


## How many stand-ins stand now (a state, as chunks_away() is: one per
## retired terrain near chunk that had a mesh).
func chunks_stood_in() -> int:
	return _standins.size()


## One line: the counters and the state.
func describe() -> String:
	return "%d streamable chunks, %d at the handover (within %.0f m), %d streamed after it, %d to come, %d retired and %d rebuilt since (%d away), %s" % [chunks_total, chunks_at_handover, R_HANDOVER_M, chunks_streamed, chunks_remaining(), chunks_retired, chunks_rebuilt, chunks_away(), "streaming" if streaming else ("claimed" if ring != null else "idle")]
