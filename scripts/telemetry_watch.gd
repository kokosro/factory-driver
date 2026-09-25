class_name TelemetryWatcher
extends Node
## TELEMETRY EVERYWHERE (2026-09-25): the one mechanism that puts a telemetry
## recorder on every car, whatever scene the car is in. An autoload
## (project.godot, TelemetryWatch; the DataBootstrap precedent) that watches
## the scene tree: the tree's node_added signal fires for every node that
## enters, and every ArcadeCar that enters gets a TelemetryRecorder
## (scripts/telemetry.gd) of its own - made here, never by a scene. The
## driver's canon: "car telemetry must be saved regardless where the car is
## in the world ... so that we don't ever have the problem of telemetry
## missing because it wasn't in the scene" (docs/issues-analysis-2026-09-24.md
## §1.4: the Ring scene had no recorder, so all 22 flagged issues have no
## replay evidence).
# was: main.tscn's MissionManager made the recorder in its _ready
# (TelemetryRecorder.new(), a child of its own, attach(self, car),
# start_session() if should_record()) and eifel_ring.tscn made none -> this
# node makes one for every car in every scene; the manager only adopts the
# one made for its car (MissionManager._start_telemetry).
##
## WHERE THE RECORDER GOES: appended as the LAST child of the car's scene
## root - the car's topmost ancestor below the tree's root (Main in
## main.tscn, EifelRing in eifel_ring.tscn); a bare car straight under the
## root (a test's) gets it under the root. Never under this autoload: the
## issue flagger (scripts/issue_flagger.gd _recording_recorder) looks for a
## recording recorder under the HUD's scene, and finds this one there in
## both scenes - which is what binds an issue to a real session id and a
## replayable range instead of the odometer and the wall clock. Last, so it
## ticks after every node the scene came with: the MissionManager's run has
## been ticked when the sample reads it (as when the recorder was the
## manager's child) and the HUD's flagger reads the recorder's clock before
## the recorder counts the tick (as before).
##
## WHEN: the attach is deferred one frame. node_added fires while the car's
## parent is still adding its children (blocked), and a child cannot be
## added to it then; by the end of the frame the whole scene is in and
## ready, and the recorder joins it. The recorder is freed when its car
## leaves the tree (tree_exiting: the recording stopped, the files closed);
## a scene change frees it with the scene either way, and the next scene's
## car gets a fresh one - a new session, its own file.
##
## The switch is the recorder's own: TelemetryRecorder.should_record() - on
## in the running game, off with no window unless FD_TELEMETRY=1 - gates
## start_session() here exactly as it gated the manager's. A headless run
## (the suite) gets the recorders, attached and idle; a test that wants one
## writing points it at a file of its own (record_to_file). Nothing here
## reads or presses anything on the car: the recorder is a passive observer
## and this node only makes it.

## A recorder was made and attached for `recorder.car`: the MissionManager
## takes the one for its car from here (mission signals, the stored summary
## the idle line shows).
signal recorder_attached(recorder: TelemetryRecorder)

## The recorder's node name (was the MissionManager's child of this name).
const RECORDER_NAME := "TelemetryRecorder"

## The autoload's node name under the tree's root (project.godot's
## [autoload] key). The class is TelemetryWatcher and the node
## TelemetryWatch: a script compiled before the autoloads are registered -
## every test script's dependencies under --script, the runner's case -
## cannot name the autoload as a bare identifier ("Identifier not found:
## TelemetryWatch", measured), so it is reached by name through of().
const AUTOLOAD_NAME := "TelemetryWatch"

## Car instance id -> its TelemetryRecorder, for every car in the tree.
var _recorders: Dictionary = {}


## The watcher in `tree`, or null where the autoload is not registered.
static func of(tree: SceneTree) -> TelemetryWatcher:
	return tree.root.get_node_or_null(AUTOLOAD_NAME) as TelemetryWatcher


func _enter_tree() -> void:
	get_tree().node_added.connect(_on_node_added)


func _exit_tree() -> void:
	get_tree().node_added.disconnect(_on_node_added)


## The car goes to the deferred attach as its instance id, not as the
## object: a car freed before the frame ends (a test's, a scene torn down
## at once) would be refused by the typed argument before any guard ran -
## "Error calling deferred method: Cannot convert argument 1 from Object
## to Object", measured (the codex cross-review's F2, 2026-09-25) - and
## the id resolves to null instead.
func _on_node_added(node: Node) -> void:
	if node is ArcadeCar:
		_attach.call_deferred(node.get_instance_id())


## The recorder made for `car`, or null when it has none (yet): the frame
## the car entered, or a car outside the tree.
func recorder_for(car: ArcadeCar) -> TelemetryRecorder:
	if car == null:
		return null
	var recorder: Variant = _recorders.get(car.get_instance_id())
	if recorder is TelemetryRecorder and is_instance_valid(recorder) and (recorder as TelemetryRecorder).is_inside_tree() and (recorder as TelemetryRecorder).car == car:
		return recorder
	return null


## Every recorder alive and in the tree right now, one per car.
func live_recorders() -> Array[TelemetryRecorder]:
	var live: Array[TelemetryRecorder] = []
	for id: int in _recorders:
		var recorder: Variant = _recorders[id]
		if recorder is TelemetryRecorder and is_instance_valid(recorder) and (recorder as TelemetryRecorder).is_inside_tree():
			live.append(recorder)
	return live


## The node a car's recorder is parented to: the car's topmost ancestor
## below the tree's root (the scene's root node), or the root itself for a
## car standing straight under it.
func scene_root_of(car: Node) -> Node:
	var root := get_tree().root
	var top := car
	while top.get_parent() != null and top.get_parent() != root:
		top = top.get_parent()
	return top if top != car else root


## `car_id` is the car's instance id (see _on_node_added). Nothing for a
## car gone, out of the tree, on its way out (queue_free before the frame
## ended: a dying car opens no session file) or already holding one.
func _attach(car_id: int) -> void:
	var car := instance_from_id(car_id) as ArcadeCar
	if car == null or not car.is_inside_tree() or car.is_queued_for_deletion() or recorder_for(car) != null:
		return
	var recorder := TelemetryRecorder.new()
	recorder.name = RECORDER_NAME
	scene_root_of(car).add_child(recorder, true)
	recorder.attach(null, car)
	_recorders[car.get_instance_id()] = recorder
	car.tree_exiting.connect(_on_car_exiting.bind(car), CONNECT_ONE_SHOT)
	if TelemetryRecorder.should_record():
		recorder.start_session()
	recorder_attached.emit(recorder)


## The car is leaving the tree: its recorder stops (the files closed) and
## goes. A car leaving with its whole scene takes the recorder along in
## any case (a sibling under the same scene root); queue_free on a node
## its parent is about to delete is harmless.
func _on_car_exiting(car: ArcadeCar) -> void:
	var id := car.get_instance_id()
	var recorder: Variant = _recorders.get(id)
	_recorders.erase(id)
	if recorder is TelemetryRecorder and is_instance_valid(recorder):
		(recorder as TelemetryRecorder).stop()
		(recorder as TelemetryRecorder).queue_free()
