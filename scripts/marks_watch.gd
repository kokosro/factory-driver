class_name MarksWatcher
extends Node
## SKIDMARKS-1 (2026-09-28): the one mechanism that puts a skidmarks layer
## (scripts/marks.gd, MarksLayer) on every car, whatever scene the car is
## in - the TelemetryWatch precedent (scripts/telemetry_watch.gd), line for
## line where it fits. An autoload (project.godot, MarksWatch) that watches
## the tree's node_added: every ArcadeCar that enters gets a MarksLayer of
## its own one deferred call later (node_added fires while the car's
## parent is still adding its children; by the end of the frame the scene
## is in), appended under the car's scene root (the car's topmost ancestor
## below the tree's root; the root itself for a bare car) and named
## "Marks". Driver issue-0003: the Ring scene had no marks at all (the pad
## had its own, scripts/tyre_marks.gd, a node of main.tscn).
##
## THE ORDER UNDER THE ROOT: the TelemetryRecorder must stay the scene
## root's LAST child (the telemetry watch test's pin, the issue flagger's
## walk). Both watchers hear node_added; this one is registered after
## TelemetryWatch, so its deferred attach runs after the recorder is in -
## the layer is added and then moved in front of the first recorder among
## the root's children. Whichever order the two attaches run in, the
## recorder ends last.
##
## THE SWITCH: FD_MARKS in the environment. "0" = off everywhere (no node,
## no quad); "1" = on, even with no window; unset = on in the running game,
## off with no window (the test suite: the 2 850-check baseline is untouched
## - tests/marks_test.gd sets "1" for its own scenes and restores). Read at
## each attach, so a test may toggle it between scenes.
##
## THE PAD KEEPS ITS OWN: a scene root that already carries a TyreMarks
## node wired to this car (main.tscn's, pinned by the frozen smoke test)
## gets no layer - two layers on one tarmac would double every mark. The
## Ring has none and gets this one.

## A layer was made and attached for `layer.car`.
signal layer_attached(layer: MarksLayer)

## The autoload's node name under the tree's root (project.godot's
## [autoload] key). Reached by name through of(): a script compiled before
## the autoloads are registered cannot name it as a bare identifier.
const AUTOLOAD_NAME := "MarksWatch"

## The environment switch.
const ENV_VAR := "FD_MARKS"

## Car instance id -> its MarksLayer, for every car in the tree.
var _layers: Dictionary = {}


## The watcher in `tree`, or null where the autoload is not registered.
static func of(tree: SceneTree) -> MarksWatcher:
	return tree.root.get_node_or_null(AUTOLOAD_NAME) as MarksWatcher


## Whether a car entering now gets a layer: FD_MARKS "0" never, "1" always,
## else only with a window (never in the headless suite).
static func should_attach() -> bool:
	var setting := OS.get_environment(ENV_VAR)
	if setting == "0":
		return false
	if setting == "1":
		return true
	return DisplayServer.get_name() != "headless"


func _enter_tree() -> void:
	get_tree().node_added.connect(_on_node_added)


func _exit_tree() -> void:
	get_tree().node_added.disconnect(_on_node_added)


## The car goes to the deferred attach as its instance id (the telemetry
## watcher's lesson: a car freed before the frame ends would be refused by
## a typed Object argument before any guard ran).
func _on_node_added(node: Node) -> void:
	if node is ArcadeCar:
		_attach.call_deferred(node.get_instance_id())


## The layer made for `car`, or null when it has none: the frame the car
## entered, a car outside the tree, the switch off, or the pad's own marks.
func layer_for(car: ArcadeCar) -> MarksLayer:
	if car == null:
		return null
	var layer: Variant = _layers.get(car.get_instance_id())
	if layer is MarksLayer and is_instance_valid(layer) and (layer as MarksLayer).is_inside_tree() and (layer as MarksLayer).car == car:
		return layer
	return null


## Every layer alive and in the tree right now, one per car.
func live_layers() -> Array[MarksLayer]:
	var live: Array[MarksLayer] = []
	for id: int in _layers:
		var layer: Variant = _layers[id]
		if layer is MarksLayer and is_instance_valid(layer) and (layer as MarksLayer).is_inside_tree():
			live.append(layer)
	return live


## The node a car's layer is parented to: the car's topmost ancestor below
## the tree's root, or the root itself for a car standing straight under it.
func scene_root_of(car: Node) -> Node:
	var root := get_tree().root
	var top := car
	while top.get_parent() != null and top.get_parent() != root:
		top = top.get_parent()
	return top if top != car else root


## The Surfaces node of the scene `car` stands in (the first under its
## scene root), or null: a bare car, a scene without one (the pad).
func surfaces_of(car: Node) -> Surfaces:
	var top := scene_root_of(car)
	if top == get_tree().root:
		return null
	return _surfaces_under(top)


## Whether `scene_root` already carries the pad's own marks for `car`
## (a TyreMarks node wired to it).
static func has_own_marks(scene_root: Node, car: ArcadeCar) -> bool:
	for child in scene_root.get_children():
		if child is TyreMarks and (child as TyreMarks).car == car:
			return true
	return false


## `car_id` is the car's instance id (see _on_node_added). Nothing for a
## car gone, out of the tree, on its way out, already holding a layer, with
## the switch off, or on a scene with marks of its own.
func _attach(car_id: int) -> void:
	var car := instance_from_id(car_id) as ArcadeCar
	if car == null or not car.is_inside_tree() or car.is_queued_for_deletion() or layer_for(car) != null:
		return
	if not should_attach():
		return
	var scene_root := scene_root_of(car)
	if has_own_marks(scene_root, car):
		return
	var layer := MarksLayer.new()
	layer.name = MarksLayer.NODE_NAME
	layer.attach(car, surfaces_of(car))
	scene_root.add_child(layer, true)
	# The recorder stays the root's last child: the layer goes in front of
	# the first recorder among the children.
	for child in scene_root.get_children():
		if child is TelemetryRecorder:
			scene_root.move_child(layer, child.get_index())
			break
	_layers[car.get_instance_id()] = layer
	car.tree_exiting.connect(_on_car_exiting.bind(car), CONNECT_ONE_SHOT)
	layer_attached.emit(layer)


## The car is leaving the tree: its layer goes with it.
func _on_car_exiting(car: ArcadeCar) -> void:
	var id := car.get_instance_id()
	var layer: Variant = _layers.get(id)
	_layers.erase(id)
	if layer is MarksLayer and is_instance_valid(layer):
		(layer as MarksLayer).queue_free()


static func _surfaces_under(node: Node) -> Surfaces:
	if node is Surfaces:
		return node
	for child in node.get_children():
		var found := _surfaces_under(child)
		if found != null:
			return found
	return null
