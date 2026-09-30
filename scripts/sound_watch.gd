class_name SoundWatcher
extends Node
## SOUND-1 (2026-09-30): the one mechanism that puts a sound node
## (scripts/sound.gd, SoundNode: the engine note, the surface rumble, the
## tyre squeal and, since SOUND-3, the wind, the impact thumps and the
## buildings' environment trim) on every car, whatever scene the car is in - the MarksWatch
## precedent (scripts/marks_watch.gd, SKIDMARKS-1), line for line where it
## fits, itself the TelemetryWatch precedent's. An autoload (project.godot,
## SoundWatch) that watches the tree's node_added: every ArcadeCar that
## enters gets a SoundNode of its own one deferred call later (node_added
## fires while the car's parent is still adding its children; by the end of
## the frame the scene is in), appended under the car's scene root (the
## car's topmost ancestor below the tree's root; the root itself for a bare
## car) and named "Sound". Backlog U-1: the game was completely silent.
##
## THE ORDER UNDER THE ROOT: the TelemetryRecorder must stay the scene
## root's LAST child (the telemetry watch test's pin, the issue flagger's
## walk). Every watcher hears node_added; this one is registered after
## TelemetryWatch (and after MarksWatch and ShellsWatch, the agent autoloads
## together, before MissionRunner which stays last), so its deferred attach
## runs after the recorder is in - the node is added and then moved in
## front of the first recorder among the root's children. Whichever order
## the attaches run in, the recorder ends last.
##
## THE SWITCH: FD_SOUND in the environment. "0" = off everywhere (no node,
## no player); "1" = on, even with no window; unset = on in the running
## game, off with no window (the test suite: its baseline is untouched -
## tests/sound_test.gd sets "1" for its own scenes and restores). Read at
## each attach, so a test may toggle it between scenes.
##
## A SCENE KEEPS ITS OWN: a scene root that already carries a sound of its
## own for this car - a SoundNode, or an audio player wired to the car -
## gets no node: two engines under one car would double the note. Today no
## scene carries any audio at all (SOUND-1 is the first sound in the
## project), so the guard is future-proofing, the MarksWatch has_own_marks
## shape for the day a pad scene ships its own.

## A node was made and attached for `sound.car`.
signal sound_attached(sound: SoundNode)

## The autoload's node name under the tree's root (project.godot's
## [autoload] key). Reached by name through of(): a script compiled before
## the autoloads are registered cannot name it as a bare identifier.
const AUTOLOAD_NAME := "SoundWatch"

## The environment switch.
const ENV_VAR := "FD_SOUND"

## Car instance id -> its SoundNode, for every car in the tree.
var _sounds: Dictionary = {}


## The watcher in `tree`, or null where the autoload is not registered.
static func of(tree: SceneTree) -> SoundWatcher:
	return tree.root.get_node_or_null(AUTOLOAD_NAME) as SoundWatcher


## Whether a car entering now gets a node: FD_SOUND "0" never, "1" always,
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


## The node made for `car`, or null when it has none: the frame the car
## entered, a car outside the tree, the switch off, or the scene's own sound.
func sound_for(car: ArcadeCar) -> SoundNode:
	if car == null:
		return null
	var sound: Variant = _sounds.get(car.get_instance_id())
	if sound is SoundNode and is_instance_valid(sound) and (sound as SoundNode).is_inside_tree() and (sound as SoundNode).car == car:
		return sound
	return null


## Every node alive and in the tree right now, one per car.
func live_sounds() -> Array[SoundNode]:
	var live: Array[SoundNode] = []
	for id: int in _sounds:
		var sound: Variant = _sounds[id]
		if sound is SoundNode and is_instance_valid(sound) and (sound as SoundNode).is_inside_tree():
			live.append(sound)
	return live


## The node a car's sound is parented to: the car's topmost ancestor below
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


## Whether `scene_root` already carries a sound of its own for `car`: a
## SoundNode wired to it, or an audio player with a `car` property wired to
## it. (No shipped scene carries either today: future-proofing.)
static func has_own_sound(scene_root: Node, car: ArcadeCar) -> bool:
	for child in scene_root.get_children():
		if child is SoundNode and (child as SoundNode).car == car:
			return true
		if (child is AudioStreamPlayer or child is AudioStreamPlayer3D) and child.get("car") == car:
			return true
	return false


## `car_id` is the car's instance id (see _on_node_added). Nothing for a
## car gone, out of the tree, on its way out, already holding a node, with
## the switch off, or on a scene with a sound of its own.
func _attach(car_id: int) -> void:
	var car := instance_from_id(car_id) as ArcadeCar
	if car == null or not car.is_inside_tree() or car.is_queued_for_deletion() or sound_for(car) != null:
		return
	if not should_attach():
		return
	var scene_root := scene_root_of(car)
	if has_own_sound(scene_root, car):
		return
	var sound := SoundNode.new()
	sound.name = SoundNode.NODE_NAME
	sound.attach(car, surfaces_of(car))
	scene_root.add_child(sound, true)
	# The recorder stays the root's last child: the node goes in front of
	# the first recorder among the children.
	for child in scene_root.get_children():
		if child is TelemetryRecorder:
			scene_root.move_child(sound, child.get_index())
			break
	_sounds[car.get_instance_id()] = sound
	car.tree_exiting.connect(_on_car_exiting.bind(car), CONNECT_ONE_SHOT)
	sound_attached.emit(sound)


## The car is leaving the tree: its sound goes with it.
func _on_car_exiting(car: ArcadeCar) -> void:
	var id := car.get_instance_id()
	var sound: Variant = _sounds.get(id)
	_sounds.erase(id)
	if sound is SoundNode and is_instance_valid(sound):
		(sound as SoundNode).queue_free()


static func _surfaces_under(node: Node) -> Surfaces:
	if node is Surfaces:
		return node
	for child in node.get_children():
		var found := _surfaces_under(child)
		if found != null:
			return found
	return null
