extends SceneTree
## Headless physics bubble test (BUBBLE-1; decisions.org 5BE9FBA3, the
## driver's ruling of 2026-09-26: the open world is interactive through a
## PROXIMITY-ACTIVATED PHYSICS BUBBLE travelling with the car - elements
## carry no permanent collision, inside the bubble collision is active,
## driven-away elements are deactivated; the trees are the first
## consumer). Run via tests/run_tests.sh, or:
##
##   godot --headless --path . --import
##   godot --headless --fixed-fps 60 --path . --script res://tests/bubble_test.gd
##
## Loads scenes/eifel_ring.tscn the way the ring drive test does and holds
## the bubble to its contract. THE WIRING: Forest carries one StaticBody3D
## per tree chunk (42, "Trunks_x_z") with one ConcavePolygonShape3D of
## the chunk's trunk prisms, and one PhysicsBubble child ("Bubble") fed
## the bodies and the road's car; every body on mask 0; the active ones
## on layer 1 (the car's mask - scripts/car.gd is frozen at the default),
## the rest on layer 0; no CollisionShape3D is ever disabled (a layer
## toggle, consistently). THE TREE STOP (a): the named tree - index
## 12355, OSM 420556746, a V2 spruce at (4475.91, -2747.53) beside the
## drive-start straight 683303211-0 (chainage 35.4, 11.5 m right: the
## visual probe's forest_wall spot), 21.34 m tall, scale 1.067 of the
## archetype's 20 m, its trunk radius the archetype's measured 0.32 m ×
## the scale = 0.341 m - driven at nose-first from the straight's
## centreline at chainage 0 (pure pursuit on the tree's point, throttle
## pinned): the tick the car first bites (get_slide_collision_count() >
## 0 against the chunk's body), the impact speed (the tick before), the
## held distance from the trunk axis to the car's origin against the
## prism (its inscribed radius r cos 30° to r) plus the box's half-length
## 2.1 m (nose-first: the brief's 0.9 m is the box's half-WIDTH, the
## broadside figure; a car driving at a tree meets it with its nose),
## the closest the box ever comes to the axis at least the inscribed
## radius (never past), and HOLD_TICKS more of the same pinned throttle
## varying the distance to the axis under HOLD_CREEP_M (held, never
## through) while the nose slides along the round trunk's face under
## HOLD_DRIFT_M with the axis still inside the nose's width (measured:
## a floored car against a round trunk is deflected a little sideways). THE CONTROL (b): the bubble
## off (enabled false, every body deactivated) the same drive passes
## through the trunk's position - no collision, the origin past the axis,
## the box through the prism - and the bubble re-forms when enabled. THE
## RADII (c): from 1 300 m along the loop past Döttinger Höhe the loop
## driver (the ring drive test's LoopDriver, its constants) drives 700 m
## - the survey (this landing) placed chunk (3,-2)'s activation at 1 400
## m and its deactivation at 1 865 m on the way, chunk (3,-3)'s
## deactivation and (2,-2)'s activation between - and EVERY tick every
## body's state is held against the position the bubble saw: activated
## only under ACTIVATE_M, deactivated only past DEACTIVATE_M, unchanged
## otherwise (no state change without a crossing, no re-activation in the
## band), each body activated at most once and deactivated at most once
## (no flicker), the event sequence recorded; run TWICE on scenes
## instanced fresh, first thing on each (the car's wear, heat and fuel
## as the scene's), the sequences and the end positions equal to the
## bit (the house determinism line). THE TELEPORT (d): the car reset_to a
## point 5 000 m along the loop (the reset test's teleport case): after
## ONE physics tick every body within ACTIVATE_M of its box is active and
## every one past DEACTIVATE_M inactive - the bubble a function of the
## position, re-formed in a tick. ZERO ALLOCATION (e): the node count of
## the tree and of Forest, the body count, the state array's size and
## the shapes' face counts are the same before and after every drive;
## the bubble's update counter is the tick count. THE PERF LINES: with
## the environment variable FD_BUBBLE_PERF set the test also prints wall
## times (the builds, every tick of the radii drive, the activation
## ticks, an update() micro-benchmark) as "perf:" lines - never in the
## suite (no wall clock in a check: the suite's lines are the same on
## any machine). No network, no python; writes nothing. Exits 0 on
## success, 1 on any fault.

const RingDrive := preload("res://tests/ring_drive_test.gd")

const RING_SCENE := "res://scenes/eifel_ring.tscn"
const SETTLE_FRAMES := 20

## The named tree (the survey of this landing; the dressing test holds
## the lists deterministic).
const TREE_INDEX := 12355
const TREE_OSM := 420556746
const TREE_ELEMENT := "V2"
const TREE_AT := Vector2(4475.91, -2747.53)
const TREE_HEIGHT_M := 21.34
const TREE_TOLERANCE_M := 0.01
## The archetypes' measured trunk radii at archetype scale [m] (the bark
## surface's widest horizontal extent read from the .glb).
const ARCHETYPE_RADII := {"V2": 0.32, "V1": 0.35, "V6": 0.30}
const RADIUS_TOLERANCE_M := 0.001
## A face vertex against its prism [m]: float32 storage at 4-12 km.
const FACE_TOLERANCE_M := 0.002
## The approach: the straight the tree stands beside, the start chainage.
const APPROACH_SEGMENT := "683303211-0"
const APPROACH_START_M := 0.0
const APPROACH_TICKS_MAX := 900
## The car's box (scenes/car.tscn: 1.8 × 1.08 × 4.2 at y 0.66).
const CAR_HALF_WIDTH_M := 0.9
const CAR_HALF_LENGTH_M := 2.1
## Held: the tolerance on the contact distance; over HOLD_TICKS of pinned
## throttle the distance to the axis may vary by HOLD_CREEP_M (never
## nearer: the trunk holds) while the nose may slide along the prism's
## face by HOLD_DRIFT_M at most with the axis still inside the nose's
## width (the trunk is round: a floored car against it is deflected a
## little sideways, measured, not through).
const CONTACT_TOLERANCE_M := 0.03
const HOLD_TICKS := 120
const HOLD_CREEP_M := 0.01
const HOLD_DRIFT_M := 0.5
## The pass-through control: the origin this far past the axis at least.
const PASS_MIN_M := 3.0

## The radii drive: the loop chainage it starts at and its length [m].
const RADII_START_M := 1300.0
const RADII_DISTANCE_M := 700.0
const RADII_TICKS_MAX := 3600
## The teleport target along the loop [m].
const TELEPORT_M := 5000.0
## The micro-benchmark's calls.
const BENCH_CALLS := 10000

var _failures := 0
var _perf := false


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_perf = OS.get_environment("FD_BUBBLE_PERF") != ""
	print("-- the scene and the wiring")
	var scene := await _load_scene()
	if scene == null:
		_finish()
		return
	var road: RoadBuilder = scene.get_node("Road")
	var forest: ForestWalls = scene.get_node("Forest")
	var car: ArcadeCar = scene.get_node("Car")
	var bubble: PhysicsBubble = forest.get_node_or_null("Bubble")
	_check_wiring(road, forest, car, bubble)
	if bubble == null:
		_finish()
		return
	if _perf:
		print("perf: build ms road %d terrain %d forest %d" % [road.build_ms, (scene.get_node("Terrain") as TerrainBuilder).build_ms, forest.build_ms])
	var nodes_before := _node_census(forest)
	print("-- the radii")
	var first := await _drive_radii(car, forest, bubble, true)
	print("-- the tree stop")
	var stop := await _drive_at_tree(road, forest, car, bubble, true)
	print("-- the control")
	var control := await _drive_at_tree(road, forest, car, bubble, false)
	_check_stop(forest, stop, control)
	print("-- the teleport")
	await _check_teleport(car, forest, bubble)
	print("-- zero allocation")
	var nodes_after := _node_census(forest)
	_ok(nodes_before == nodes_after, "no node, body, shape or face was created or freed by the drives: the census is the same before and after (%s)" % nodes_after, "before %s, after %s" % [nodes_before, nodes_after])
	if _perf:
		_bench(bubble, car)
	root.remove_child(scene)
	scene.free()
	await _step(1)
	print("-- determinism")
	var again := await _load_scene()
	if again != null:
		var forest2: ForestWalls = again.get_node("Forest")
		var second := await _drive_radii(again.get_node("Car"), forest2, forest2.get_node("Bubble"), false)
		_ok(first.events == second.events and first.position == second.position and first.ticks == second.ticks, "two scenes instanced fresh and driven the same %.0f m see the same %d state changes at the same ticks (%s) and land on the same position (%s) in %d ticks to the bit" % [RADII_DISTANCE_M, second.count, second.events, second.position, second.ticks], "first: %s / %s / %d, second: %s / %s / %d" % [first.events, first.position, first.ticks, second.events, second.position, second.ticks])
		if _perf:
			# The same drive with the bubble off: the sim's own tick
			# distribution, for the activation ticks to be read against.
			var bubble2: PhysicsBubble = forest2.get_node("Bubble")
			bubble2.enabled = false
			bubble2.deactivate_all()
			print("perf: the same drive with the bubble OFF (every body on layer 0, no update):")
			await _drive_radii(again.get_node("Car"), forest2, bubble2, false)
			bubble2.enabled = true
		root.remove_child(again)
		again.free()
	_finish()


func _finish() -> void:
	print("BUBBLE TEST PASSED" if _failures == 0 else "BUBBLE TEST FAILED: %d fault(s)" % _failures)
	quit(0 if _failures == 0 else 1)


## An ok line or a FAIL line, counted.
func _ok(condition: bool, what: String, reason: String = "") -> void:
	if condition:
		print("  ok    ", what)
	else:
		_failures += 1
		printerr("  FAIL  ", reason if reason != "" else what)


func _step(frames: int) -> void:
	for i: int in frames:
		await physics_frame


func _load_scene() -> Node:
	var packed: PackedScene = load(RING_SCENE)
	if packed == null:
		_ok(false, "", "the ring scene does not load")
		return null
	await physics_frame
	var scene := packed.instantiate()
	root.add_child(scene)
	await _step(SETTLE_FRAMES)
	return scene


## A yaw-only pose at (x, z) with the nose along `direction` (x east, z
## south), origin.y 0: the way the ring drive test stands the car.
func _pose(x: float, z: float, direction: Vector2) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, atan2(-direction.x, -direction.y)), Vector3(x, 0.0, z))


# =============================================================================
#  THE WIRING
# =============================================================================

func _check_wiring(road: RoadBuilder, forest: ForestWalls, car: ArcadeCar, bubble: PhysicsBubble) -> void:
	_ok(road != null and forest != null and car != null and bubble != null and bubble is PhysicsBubble and bubble.car == car and car.collision_mask == 1 and car.collision_layer == 1, "the scene loads headless with Road, Forest and Car; Forest carries a PhysicsBubble child \"Bubble\" fed the Car (the road's car: no scene file change), the car a CharacterBody3D at the default layer 1 / mask 1 (scripts/car.gd frozen)", "road %s forest %s car %s bubble %s" % [road, forest, car, bubble])
	if bubble == null:
		return
	var bodies := 0
	var shapes := 0
	var faces := 0
	var wired := true
	var meshes := 0
	var others := 0
	for child: Node in forest.get_children():
		if child is MeshInstance3D:
			meshes += 1
		elif child is StaticBody3D and child.name.begins_with("Trunks_"):
			bodies += 1
			var body := child as StaticBody3D
			wired = wired and body.collision_mask == PhysicsBubble.BODY_MASK and (body.collision_layer == PhysicsBubble.ACTIVE_LAYER or body.collision_layer == PhysicsBubble.INACTIVE_LAYER) and body.get_child_count() == 1 and body in forest.trunk_bodies
			for grand: Node in body.get_children():
				if grand is CollisionShape3D and (grand as CollisionShape3D).shape is ConcavePolygonShape3D:
					shapes += 1
					wired = wired and not (grand as CollisionShape3D).disabled
					faces += ((grand as CollisionShape3D).shape as ConcavePolygonShape3D).get_faces().size()
		elif child == bubble:
			pass
		else:
			others += 1
	_ok(wired and others == 0 and bodies == forest.trunk_bodies.size() and shapes == bodies and bodies == forest.counts.bodies and faces == forest.counts.trunks * ForestWalls.TRUNK_SIDES * 6 and forest.counts.trunks == forest.tree_x.size() and bubble.bodies.size() == bodies and bubble.boxes.size() == bodies * 4 and bubble.active.size() == bodies, "Forest's children are its %d chunk meshes, %d trunk bodies (one StaticBody3D per tree chunk, mask %d, on layer %d or %d, one enabled CollisionShape3D each with a ConcavePolygonShape3D; %d faces = %d trunks × %d sides × 6, every tree one prism) and the bubble, which holds every body, its box and its state" % [meshes, bodies, PhysicsBubble.BODY_MASK, PhysicsBubble.ACTIVE_LAYER, PhysicsBubble.INACTIVE_LAYER, faces, forest.counts.trunks, ForestWalls.TRUNK_SIDES], "wired %s others %d bodies %d/%d shapes %d faces %d trunks %d bubble %d/%d/%d" % [wired, others, bodies, forest.trunk_bodies.size(), shapes, faces, forest.counts.trunks, bubble.bodies.size(), bubble.boxes.size(), bubble.active.size()])
	var radii_ok := true
	var lines: Array[String] = []
	for key: String in ["V2", "V1", "V6"]:
		var archetype: ForestWalls.Archetype = forest.archetypes.get(key)
		if archetype == null:
			radii_ok = false
			continue
		radii_ok = radii_ok and absf(archetype.trunk_radius - ARCHETYPE_RADII[key]) <= RADIUS_TOLERANCE_M and archetype.trunk_radius >= ForestWalls.TRUNK_RADIUS_MIN_M and archetype.trunk_radius <= ForestWalls.TRUNK_RADIUS_MAX_M and archetype.trunk_top > 1.0 and archetype.trunk_top < archetype.height
		lines.append("%s r %.3f top %.1f of %.0f m" % [key, archetype.trunk_radius, archetype.trunk_top, archetype.height])
	_ok(radii_ok, "the archetypes' trunks measured from the .glb bark surfaces (the widest horizontal extent, held to [%.2f, %.2f] m; the top the crown base): %s" % [ForestWalls.TRUNK_RADIUS_MIN_M, ForestWalls.TRUNK_RADIUS_MAX_M, ", ".join(lines)], "radii: %s" % [", ".join(lines)])
	_ok(PhysicsBubble.ACTIVATE_M < PhysicsBubble.DEACTIVATE_M and PhysicsBubble.ACTIVATE_M > 0.0 and PhysicsBubble.ACTIVE_LAYER == car.collision_mask and PhysicsBubble.INACTIVE_LAYER == 0 and bubble.enabled and bubble.process_physics_priority < 0, "the radii are ordered (activate %.0f m < deactivate %.0f m: hysteresis), the active layer is the car's mask, the inactive layer none, the bubble enabled and stepping before the car (priority %d)" % [PhysicsBubble.ACTIVATE_M, PhysicsBubble.DEACTIVATE_M, bubble.process_physics_priority])
	var settled := _state_errors(bubble, car.global_position)
	_ok(settled.is_empty() and bubble.active_count() > 0 and bubble.updates >= SETTLE_FRAMES, "settled at the pit the bubble is right for the car's position (%d of %d bodies active, %s)" % [bubble.active_count(), bubble.bodies.size(), bubble.describe()], "errors %s, %s" % [settled, bubble.describe()])
	# The named tree.
	var i := TREE_INDEX
	var named: bool = i < forest.tree_x.size() and forest.tree_osm[i] == TREE_OSM and forest.tree_element[i] == TREE_ELEMENT and absf(forest.tree_x[i] - TREE_AT.x) <= TREE_TOLERANCE_M and absf(forest.tree_z[i] - TREE_AT.y) <= TREE_TOLERANCE_M and absf(forest.tree_height[i] - TREE_HEIGHT_M) <= TREE_TOLERANCE_M
	var archetype: ForestWalls.Archetype = forest.archetypes.get(forest.archetype_of(i)) if named else null
	var radius := forest.trunk_radius(i) if named else 0.0
	var span := forest.trunk_span(i) if named else Vector2.ZERO
	var expected_radius: float = archetype.trunk_radius * forest.tree_height[i] / archetype.height if archetype != null else 0.0
	var prism := forest.trunk_faces(i) if named else PackedVector3Array()
	var prism_ok := prism.size() == ForestWalls.TRUNK_SIDES * 6
	for v: Vector3 in prism:
		prism_ok = prism_ok and absf(Vector2(v.x - forest.tree_x[i], v.z - forest.tree_z[i]).length() - radius) < FACE_TOLERANCE_M and (absf(v.y - span.x) < FACE_TOLERANCE_M or absf(v.y - span.y) < FACE_TOLERANCE_M)
	var in_body := false
	var chunk := forest.chunk_of(i) if named else Vector2i.ZERO
	if named and forest.trunk_chunk_trees.has(chunk):
		var trees: PackedInt32Array = forest.trunk_chunk_trees[chunk]
		var slot := trees.find(i)
		var body: StaticBody3D = forest.trunk_bodies[forest.trunk_chunk_keys.find(chunk)]
		var body_faces: PackedVector3Array = (body.get_child(0) as CollisionShape3D).shape.get_faces()
		in_body = slot >= 0 and body_faces.slice(slot * prism.size(), (slot + 1) * prism.size()) == prism
	_ok(named and prism_ok and in_body and absf(radius - expected_radius) < 1e-6, "the named tree: index %d, OSM %d, %s (%s) at (%.2f, %.2f), %.2f m tall (scale %.3f), its trunk prism radius %.4f m (the archetype's measured %.2f m × the scale) from y %.2f to %.2f (the crown base %.1f m up), its %d faces in chunk %s's body at its slot" % [i, TREE_OSM, TREE_ELEMENT, forest.archetype_of(i) if named else "-", TREE_AT.x, TREE_AT.y, forest.tree_height[i] if named else 0.0, forest.tree_height[i] / archetype.height if archetype != null else 0.0, radius, archetype.trunk_radius if archetype != null else 0.0, span.x, span.y, span.y - span.x, prism.size(), chunk], "named %s prism %s in body %s radius %.4f vs %.4f" % [named, prism_ok, in_body, radius, expected_radius])


## The state errors at `at`: every body must be active within ACTIVATE_M
## and inactive past DEACTIVATE_M (the band may be either).
func _state_errors(bubble: PhysicsBubble, at: Vector3) -> Array[String]:
	var errors: Array[String] = []
	for b: int in bubble.bodies.size():
		var d := bubble.box_distance(b, at.x, at.z)
		var layer := bubble.bodies[b].collision_layer
		if bubble.is_active(b) != (layer == PhysicsBubble.ACTIVE_LAYER):
			errors.append("%s state %s layer %d" % [bubble.bodies[b].name, bubble.is_active(b), layer])
		if d < PhysicsBubble.ACTIVATE_M and not bubble.is_active(b):
			errors.append("%s inactive at %.1f m" % [bubble.bodies[b].name, d])
		if d > PhysicsBubble.DEACTIVATE_M and bubble.is_active(b):
			errors.append("%s active at %.1f m" % [bubble.bodies[b].name, d])
	return errors


func _node_census(forest: ForestWalls) -> String:
	var faces := 0
	for body: StaticBody3D in forest.trunk_bodies:
		faces += ((body.get_child(0) as CollisionShape3D).shape as ConcavePolygonShape3D).get_faces().size()
	return "%d nodes in the tree, %d under Forest, %d bodies, %d states, %d faces" % [root.get_child_count() + _count_under(root), _count_under(forest), forest.trunk_bodies.size(), forest.bubble.active.size(), faces]


func _count_under(node: Node) -> int:
	var n := 0
	for child: Node in node.get_children():
		n += 1 + _count_under(child)
	return n


# =============================================================================
#  THE TREE STOP AND THE CONTROL
# =============================================================================

## Drives the car from the straight's centreline at the named tree with
## the throttle pinned and pure pursuit on the tree's point, the bubble
## on (`solid`) or off; returns what happened.
func _drive_at_tree(road: RoadBuilder, forest: ForestWalls, car: ArcadeCar, bubble: PhysicsBubble, solid: bool) -> Dictionary:
	var i := TREE_INDEX
	var axis := Vector2(forest.tree_x[i], forest.tree_z[i])
	var radius := forest.trunk_radius(i)
	var strip: RoadBuilder.Strip = road.strip(APPROACH_SEGMENT)
	var start := _centre_at(strip, APPROACH_START_M)
	var direction := (axis - start).normalized()
	var body: StaticBody3D = forest.trunk_bodies[forest.trunk_chunk_keys.find(forest.chunk_of(i))]
	bubble.enabled = solid
	if not solid:
		bubble.deactivate_all()
	car.reset_to(_pose(start.x, start.y, direction))
	await _step(SETTLE_FRAMES)
	var result := {"solid": solid, "bite_tick": -1, "impact_speed": 0.0, "bite_distance": 0.0, "held_distance": 0.0, "creep": 0.0, "drift": 0.0, "hold_nearest": INF, "hold_farthest": 0.0, "closest_box": INF, "closest_origin": INF, "along_end": 0.0, "collisions": 0, "other_colliders": 0, "ticks": 0, "start_distance": (axis - start).length(), "bodies_active_control": 0, "axis_in_nose": 0.0}
	var speed_before := 0.0
	var held_from := Vector3.ZERO
	var ticks := 0
	var passed := false
	while ticks < APPROACH_TICKS_MAX:
		var origin := Vector2(car.global_position.x, car.global_position.z)
		var along := (origin - axis).dot(direction)
		if along > 0.0:
			passed = true
		if not passed:
			_pursue(car, axis, 1.0)
		else:
			car.set_driver_input(1.0, 0.0, 0.0)
		speed_before = car.forward_speed
		await physics_frame
		ticks += 1
		var now := Vector2(car.global_position.x, car.global_position.z)
		result.closest_origin = minf(result.closest_origin, (now - axis).length())
		result.closest_box = minf(result.closest_box, _box_distance(car, axis))
		var hits := 0
		for k: int in car.get_slide_collision_count():
			var collider: Object = car.get_slide_collision(k).get_collider()
			if collider == body:
				hits += 1
			elif collider is StaticBody3D and (collider as StaticBody3D).name.begins_with("Trunks_"):
				result.other_colliders += 1
		if hits > 0:
			result.collisions += 1
			if result.bite_tick < 0:
				result.bite_tick = ticks
				result.impact_speed = speed_before
				result.bite_distance = (now - axis).length()
				held_from = car.global_position
		if result.bite_tick >= 0:
			result.hold_nearest = minf(result.hold_nearest, (now - axis).length())
			result.hold_farthest = maxf(result.hold_farthest, (now - axis).length())
		if result.bite_tick >= 0 and ticks >= result.bite_tick + HOLD_TICKS:
			break
		if not solid and passed and (now - axis).length() > PASS_MIN_M + 2.0:
			break
	result.ticks = ticks
	result.held_distance = (Vector2(car.global_position.x, car.global_position.z) - axis).length()
	result.drift = (car.global_position - held_from).length() if result.bite_tick >= 0 else 0.0
	result.creep = result.hold_farthest - result.hold_nearest if result.bite_tick >= 0 else 0.0
	result.axis_in_nose = absf((car.global_transform.affine_inverse() * Vector3(axis.x, car.global_position.y, axis.y)).x)
	result.along_end = (Vector2(car.global_position.x, car.global_position.z) - axis).dot(direction)
	result.end_speed = car.forward_speed
	result.radius = radius
	car.set_driver_input(0.0, 1.0, 0.0)
	if not solid:
		result.bodies_active_control = bubble.active_count()
		bubble.enabled = true
		await _step(1)
		result.reformed = _state_errors(bubble, car.global_position).is_empty() and bubble.active_count() > 0
	await _step(SETTLE_FRAMES)
	return result


func _check_stop(forest: ForestWalls, stop: Dictionary, control: Dictionary) -> void:
	var r: float = stop.radius
	var inscribed := r * cos(PI / ForestWalls.TRUNK_SIDES)
	var held_min := inscribed + CAR_HALF_LENGTH_M - CONTACT_TOLERANCE_M
	var held_max := r + sqrt(CAR_HALF_LENGTH_M * CAR_HALF_LENGTH_M + CAR_HALF_WIDTH_M * CAR_HALF_WIDTH_M) + CONTACT_TOLERANCE_M
	_ok(stop.bite_tick > 0 and stop.impact_speed > 5.0 and stop.other_colliders == 0, "the tree stop: from %.1f m out the car bites the trunk's body at tick %d at %.2f m/s (get_slide_collision_count() > 0 against chunk %s's body, no other body), %d ticks in contact of %d" % [stop.start_distance, stop.bite_tick, stop.impact_speed, forest.chunk_of(TREE_INDEX), stop.collisions, stop.ticks], "bite tick %d speed %.2f others %d" % [stop.bite_tick, stop.impact_speed, stop.other_colliders])
	_ok(stop.bite_tick > 0 and stop.held_distance >= held_min and stop.held_distance <= held_max and stop.closest_origin >= held_min, "held at %.3f m from the trunk axis to the car's origin - the prism's %.3f m (inscribed %.3f m to %.3f m) plus the box's half-length %.1f m nose-first (%.3f to %.3f m allowed; the brief's 0.9 m is the box's half-width, the broadside figure) - and never nearer than %.3f m over the drive: never past" % [stop.held_distance, r, inscribed, r, CAR_HALF_LENGTH_M, held_min, held_max, stop.closest_origin], "held %.3f closest %.3f allowed %.3f-%.3f" % [stop.held_distance, stop.closest_origin, held_min, held_max])
	_ok(stop.bite_tick > 0 and stop.closest_box >= inscribed - CONTACT_TOLERANCE_M, "the car's box never came nearer the axis than %.3f m (the inscribed radius %.3f m): the shell stayed outside the prism every tick" % [stop.closest_box, inscribed], "closest box %.3f inscribed %.3f" % [stop.closest_box, inscribed])
	_ok(stop.bite_tick > 0 and stop.creep <= HOLD_CREEP_M and stop.drift <= HOLD_DRIFT_M and stop.axis_in_nose <= CAR_HALF_WIDTH_M - r and absf(stop.end_speed) < 0.5, "%d further ticks (%.0f s) of the same pinned throttle: the distance to the axis varies %.4f m (under %.2f m: held, never through), the nose slides %.3f m along the trunk's face (under %.1f m; the axis %.2f m off the car's centreline at the end, inside the nose's %.1f m half-width less the radius - the round trunk deflects a floored car a little, the driver's creep, measured), the speed %.3f m/s at the end" % [HOLD_TICKS, HOLD_TICKS / 60.0, stop.creep, HOLD_CREEP_M, stop.drift, HOLD_DRIFT_M, stop.axis_in_nose, CAR_HALF_WIDTH_M, stop.end_speed], "creep %.4f drift %.3f axis in nose %.3f speed %.3f" % [stop.creep, stop.drift, stop.axis_in_nose, stop.end_speed])
	_ok(control.bite_tick < 0 and control.collisions == 0 and control.other_colliders == 0 and control.closest_box < stop.radius and control.along_end >= PASS_MIN_M and control.bodies_active_control == 0, "the control: with the bubble off (every body on layer 0, %d active) the same drive passes through the trunk's position - no collision in %d ticks, the box within %.3f m of the axis (under the radius %.3f m), the origin %.2f m past the axis at the end" % [control.bodies_active_control, control.ticks, control.closest_box, stop.radius, control.along_end], "control: bite %d collisions %d closest box %.3f along %.2f active %d" % [control.bite_tick, control.collisions, control.closest_box, control.along_end, control.bodies_active_control])
	_ok(control.get("reformed", false), "re-enabled, the bubble re-forms around the car within one tick")


## Pure pursuit on one point: the loop driver's steer law on the point.
func _pursue(car: ArcadeCar, target: Vector2, throttle: float) -> void:
	var forward := -car.global_basis.z
	var right := car.global_basis.x
	var to := Vector3(target.x - car.global_position.x, 0.0, target.y - car.global_position.z)
	var alpha := atan2(-to.dot(right), to.dot(forward))
	var distance := maxf(to.length(), 1.0)
	var wheel := atan(2.0 * 2.0 * ArcadeCar.AXLE_DISTANCE * sin(alpha) / distance)
	var steer := clampf(wheel / ArcadeCar.MAX_STEER_LOCK, -1.0, 1.0)
	car.set_driver_input(throttle, 0.0, steer)


## The horizontal distance from the trunk axis to the nearest point of the
## car's box.
func _box_distance(car: ArcadeCar, axis: Vector2) -> float:
	var local := car.global_transform.affine_inverse() * Vector3(axis.x, car.global_position.y, axis.y)
	var dx := maxf(0.0, absf(local.x) - CAR_HALF_WIDTH_M)
	var dz := maxf(0.0, absf(local.z) - CAR_HALF_LENGTH_M)
	return Vector2(dx, dz).length()


## The strip's centre column at chainage `s` (the visual probe's _at).
func _centre_at(strip: RoadBuilder.Strip, s: float) -> Vector2:
	var chain: PackedFloat64Array = strip.chainages
	var s_c: float = clampf(s, chain[0], chain[chain.size() - 1])
	var k: int = 1
	while k < chain.size() and chain[k] < s_c:
		k += 1
	if k >= chain.size():
		k = chain.size() - 1
	var span: float = chain[k] - chain[k - 1]
	var u: float = 0.0 if span <= 0.0 else (s_c - chain[k - 1]) / span
	var centre_i: int = 0
	var best: float = INF
	for i: int in strip.offsets.size():
		if absf(strip.offsets[i]) < best:
			best = absf(strip.offsets[i])
			centre_i = i
	var a: Vector3 = strip.vertex(k - 1, centre_i)
	var b: Vector3 = strip.vertex(k, centre_i)
	var c := a.lerp(b, u)
	return Vector2(c.x, c.z)


# =============================================================================
#  THE RADII
# =============================================================================

func _loop_driver(car: ArcadeCar, length: float) -> RingDrive.LoopDriver:
	var skeleton: Dictionary = SkeletonLoader.read_file()
	var segments := SkeletonLoader.segments_of(skeleton)
	var raw_points := {}
	for raw: Variant in skeleton.get("segments", []):
		if raw is Dictionary and raw.get("id") is String:
			raw_points[raw.id] = raw.points
	var loop: SkeletonLoader.Loop = SkeletonLoader.loops_of(skeleton)[SkeletonLoader.NORDSCHLEIFE_LOOP]
	var driver := RingDrive.LoopDriver.new()
	driver.car = car
	var k: int = loop.segments.find(RingDrive.DRIVE_START_SEGMENT)
	while driver.xs.is_empty() or driver.length() < length:
		var id: String = loop.segments[k % loop.segments.size()]
		var half_width: float = segments[id].width_m * 0.5
		for point: Array in raw_points[id]:
			driver.add_point(point[0], point[1], half_width)
		k += 1
	return driver


## The radii drive: RADII_DISTANCE_M along the loop from RADII_START_M,
## every tick's state held against the position the bubble saw.
func _drive_radii(car: ArcadeCar, forest: ForestWalls, bubble: PhysicsBubble, report: bool) -> Dictionary:
	var driver := _loop_driver(car, RADII_START_M + RADII_DISTANCE_M + RingDrive.LOOKAHEAD_MAX_M + RingDrive.CURVATURE_PREVIEW_M + 100.0)
	var start := driver.point_at(RADII_START_M)
	var heading := driver.heading_at(RADII_START_M)
	car.reset_to(_pose(start.x, start.y, Vector2(cos(heading), sin(heading))))
	await _step(SETTLE_FRAMES)
	driver.locate()
	var n := bubble.bodies.size()
	var state := PackedByteArray()
	state.resize(n)
	for b: int in n:
		state[b] = 1 if bubble.is_active(b) else 0
	var activated := PackedInt32Array()
	activated.resize(n)
	var deactivated := PackedInt32Array()
	deactivated.resize(n)
	var events: Array[String] = []
	var faults: Array[String] = []
	var seen := Vector3(car.global_position)
	var ticks := 0
	var updates_before := bubble.updates
	var tick_us := PackedInt64Array()
	var event_ticks := {}
	var activate_sq := PhysicsBubble.ACTIVATE_M * PhysicsBubble.ACTIVATE_M
	var deactivate_sq := PhysicsBubble.DEACTIVATE_M * PhysicsBubble.DEACTIVATE_M
	while ticks < RADII_TICKS_MAX and driver.progress < RADII_START_M + RADII_DISTANCE_M:
		driver.tick(RingDrive.CRUISE_SPEED, RingDrive.LATERAL_ACCEL_BUDGET, RingDrive.LOOKAHEAD_S, RingDrive.LOOKAHEAD_MIN_M, RingDrive.LOOKAHEAD_MAX_M, RingDrive.CURVATURE_PREVIEW_M, RingDrive.PEDAL_GAIN)
		seen = car.global_position
		var before := Time.get_ticks_usec() if _perf else 0
		await physics_frame
		if _perf:
			tick_us.append(Time.get_ticks_usec() - before)
		ticks += 1
		# The bubble stepped on `seen` this tick, before the car moved.
		for b: int in n:
			var d_sq := bubble.box_distance_squared(b, seen.x, seen.z)
			var now := 1 if bubble.is_active(b) else 0
			if now != state[b]:
				if now == 1:
					activated[b] += 1
					if d_sq >= activate_sq or activated[b] > 1:
						faults.append("tick %d %s activated at %.1f m (the %dth time)" % [ticks, bubble.bodies[b].name, sqrt(d_sq), activated[b]])
					events.append("%d:%s+%.1f" % [ticks, bubble.bodies[b].name, sqrt(d_sq)])
				else:
					deactivated[b] += 1
					if d_sq <= deactivate_sq or deactivated[b] > 1:
						faults.append("tick %d %s deactivated at %.1f m (the %dth time)" % [ticks, bubble.bodies[b].name, sqrt(d_sq), deactivated[b]])
					events.append("%d:%s-%.1f" % [ticks, bubble.bodies[b].name, sqrt(d_sq)])
				event_ticks[ticks] = true
				state[b] = now
			elif now == 0 and d_sq < activate_sq:
				faults.append("tick %d %s inactive at %.1f m" % [ticks, bubble.bodies[b].name, sqrt(d_sq)])
			elif now == 1 and d_sq > deactivate_sq:
				faults.append("tick %d %s active at %.1f m" % [ticks, bubble.bodies[b].name, sqrt(d_sq)])
			if (bubble.bodies[b].collision_layer == PhysicsBubble.ACTIVE_LAYER) != (now == 1):
				faults.append("tick %d %s layer %d state %d" % [ticks, bubble.bodies[b].name, bubble.bodies[b].collision_layer, now])
	car.set_driver_input(0.0, 1.0, 0.0)
	await _step(SETTLE_FRAMES)
	var result := {"events": ",".join(events), "count": events.size(), "position": car.global_position, "ticks": ticks, "faults": faults, "progress": driver.progress}
	if not report and not faults.is_empty():
		result.faults = faults
	if report:
		var activations := 0
		var deactivations := 0
		var twice := 0
		for b: int in n:
			activations += activated[b]
			deactivations += deactivated[b]
			if activated[b] > 1 or deactivated[b] > 1:
				twice += 1
		_ok(ticks > 0 and driver.progress >= RADII_START_M + RADII_DISTANCE_M and bubble.updates - updates_before == ticks + SETTLE_FRAMES, "the radii drive: %.0f m of the loop from %.0f m past Döttinger Höhe in %d ticks (%.1f s), the bubble stepped every tick (%d updates)" % [driver.progress - RADII_START_M, RADII_START_M, ticks, ticks / 60.0, bubble.updates - updates_before], "ticks %d progress %.1f updates %d" % [ticks, driver.progress, bubble.updates - updates_before])
		_ok(faults.is_empty() and activations >= 2 and deactivations >= 2 and twice == 0, "every tick of the drive every body's state held against the position the bubble saw: %d activations each under %.0f m, %d deactivations each past %.0f m, no state change without a crossing, no body toggled twice (no flicker), the layer the state's every tick; the events (tick:body±distance): %s" % [activations, PhysicsBubble.ACTIVATE_M, deactivations, PhysicsBubble.DEACTIVATE_M, result.events], "%d faults (first %s), activations %d deactivations %d twice %d" % [faults.size(), faults[0] if not faults.is_empty() else "-", activations, deactivations, twice])
	if _perf:
		_perf_ticks(tick_us, event_ticks)
	return result


func _perf_ticks(tick_us: PackedInt64Array, event_ticks: Dictionary) -> void:
	if tick_us.is_empty():
		return
	var sorted := tick_us.duplicate()
	sorted.sort()
	var median: int = sorted[sorted.size() / 2]
	var worst := 0
	var worst_tick := 0
	var total := 0
	for t: int in tick_us.size():
		total += tick_us[t]
		if tick_us[t] > worst:
			worst = tick_us[t]
			worst_tick = t + 1
	var event_lines: Array[String] = []
	var event_worst := 0
	for tick: int in event_ticks:
		event_lines.append("tick %d %d us" % [tick, tick_us[tick - 1]])
		event_worst = maxi(event_worst, tick_us[tick - 1])
	var seconds: Array[String] = []
	var s := 0
	while s < tick_us.size():
		var sum := 0
		var e := mini(s + 60, tick_us.size())
		for t: int in range(s, e):
			sum += tick_us[t]
		seconds.append("%d" % (sum / (e - s)))
		s = e
	var over_twice := 0
	var worst_other := 0
	for t: int in tick_us.size():
		if tick_us[t] > 2 * median:
			over_twice += 1
		if not event_ticks.has(t + 1):
			worst_other = maxi(worst_other, tick_us[t])
	var p90: int = sorted[int(sorted.size() * 0.9)]
	var p99: int = sorted[int(sorted.size() * 0.99)]
	print("perf: %d ticks, median %d us, p90 %d us, p99 %d us, mean %d us, worst %d us at tick %d, %d ticks over twice the median; the activation/deactivation ticks: %s (worst %d us, %.2f x the median: the brief's 2x line %s; within the ordinary ticks' worst %d us: %s)" % [tick_us.size(), median, p90, p99, total / tick_us.size(), worst, worst_tick, over_twice, ", ".join(event_lines), event_worst, float(event_worst) / median, "PASS" if event_worst <= 2 * median else "FAIL", worst_other, "PASS" if event_worst <= worst_other else "FAIL"])
	print("perf: mean us per tick by second: %s" % ", ".join(seconds))


func _bench(bubble: PhysicsBubble, car: ArcadeCar) -> void:
	var at := car.global_position
	var before := Time.get_ticks_usec()
	var changes := 0
	for k: int in BENCH_CALLS:
		changes += bubble.update(at)
	var elapsed := Time.get_ticks_usec() - before
	print("perf: update() %d calls over %d bodies: %.2f us a call, %d state changes" % [BENCH_CALLS, bubble.bodies.size(), float(elapsed) / BENCH_CALLS, changes])
	# The layer write itself, on the biggest body, on and off.
	var biggest: StaticBody3D = bubble.bodies[0]
	var most := 0
	for body: StaticBody3D in bubble.bodies:
		var faces: int = ((body.get_child(0) as CollisionShape3D).shape as ConcavePolygonShape3D).get_faces().size()
		if faces > most:
			most = faces
			biggest = body
	var was := biggest.collision_layer
	before = Time.get_ticks_usec()
	for k: int in BENCH_CALLS:
		biggest.collision_layer = PhysicsBubble.ACTIVE_LAYER if k % 2 == 0 else PhysicsBubble.INACTIVE_LAYER
	elapsed = Time.get_ticks_usec() - before
	biggest.collision_layer = was
	print("perf: collision_layer writes on the biggest body (%s, %d faces): %d toggles, %.2f us a write" % [biggest.name, most, BENCH_CALLS, float(elapsed) / BENCH_CALLS])


# =============================================================================
#  THE TELEPORT
# =============================================================================

func _check_teleport(car: ArcadeCar, forest: ForestWalls, bubble: PhysicsBubble) -> void:
	var driver := _loop_driver(car, TELEPORT_M + 100.0)
	var before_active := bubble.active_count()
	var active_before: Array[String] = []
	for b: int in bubble.bodies.size():
		if bubble.is_active(b):
			active_before.append(bubble.bodies[b].name)
	var target := driver.point_at(TELEPORT_M)
	var heading := driver.heading_at(TELEPORT_M)
	var from := car.global_position
	car.reset_to(_pose(target.x, target.y, Vector2(cos(heading), sin(heading))))
	await _step(1)
	var errors := _state_errors(bubble, car.global_position)
	var active_after: Array[String] = []
	for b: int in bubble.bodies.size():
		if bubble.is_active(b):
			active_after.append(bubble.bodies[b].name)
	var jump := Vector2(car.global_position.x - from.x, car.global_position.z - from.z).length()
	_ok(errors.is_empty() and jump > 2.0 * PhysicsBubble.DEACTIVATE_M and active_after != active_before and bubble.active_count() > 0, "teleported %.0f m (reset_to, the reset test's case) to %.0f m along the loop: after ONE tick the bubble is right for the new position - every body within %.0f m active, every one past %.0f m inactive (was %s, now %s)" % [jump, TELEPORT_M, PhysicsBubble.ACTIVATE_M, PhysicsBubble.DEACTIVATE_M, active_before, active_after], "errors %s, jump %.0f, before %s after %s" % [errors, jump, active_before, active_after])
	await _step(SETTLE_FRAMES)
