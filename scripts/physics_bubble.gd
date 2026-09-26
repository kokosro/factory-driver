class_name PhysicsBubble
extends Node3D
## The physics bubble (decisions.org 5BE9FBA3, the driver's ruling of
## 2026-09-26: "we want everything around the player to have interaction
## ... if a driver is not near the element, the element doesn't get a
## collision box, if a driver comes near it gets a collision box, making
## sure to deactivate the ones that are less likely to be hit because the
## driver drove away. It's like creating the physics bubble where a car
## is."): the world's elements carry NO permanent collision; the bodies
## near the car are switched ON as it comes near and OFF as it drives
## away. BUBBLE-1 is the trees: ForestWalls builds one StaticBody3D per
## tree chunk holding every trunk prism of the chunk (42 bodies for
## 19 339 trunks: never a node per tree) and hands them here with each
## body's horizontal box (the chunk's trunks' extent); the buildings and
## the furniture follow on the same node (4B-8).
##
## THE STATE MACHINE, per body, driven by the car's position every physics
## tick (process_physics_priority -2: before the road's floor follower at
## -1 and the car's own step at 0, and the server reads the layers at the
## step that follows, so a body switched on this tick is solid to the car
## this tick): a body whose box is within ACTIVATE_M of the car is ACTIVE
## - collision_layer ACTIVE_LAYER (1, the car's mask: scripts/car.gd is
## frozen at the CharacterBody3D default, mask 1, so the trunks stand on
## the one layer the car meets, beside the road's floor slab; the road's
## own strips keep layer 2 and never meet the car); a body whose box is
## past DEACTIVATE_M is INACTIVE - collision_layer INACTIVE_LAYER (0: on
## no layer the body pairs with nothing; a layer write, not a shape
## toggle - CollisionShape3D.disabled removes and re-adds the shape from
## the broadphase, a layer write is one integer on a body that stays
## where it is). Between the radii a body keeps its state: the hysteresis
## band (ACTIVATE_M < DEACTIVATE_M) so a car idling at one radius never
## flickers a body on and off. The distance is to the body's BOX, not its
## centre: a chunk is 1 km across, so a trunk 20 m from the car can stand
## 500 m from its chunk's centre; the box distance is 0 inside the chunk
## and the gap to its nearest edge outside, so every trunk within
## ACTIVATE_M of the car is under an active body.
##
## COST AND DETERMINISM: update() is one pass over the bodies (O(bodies),
## 42 here, never O(elements)), squared distances against squared radii,
## writes only on a state change; no allocation after attach() (the state
## is a PackedByteArray sized once; the counters are ints), no RNG, no
## wall clock, no dependence on the frame rate: the state after a tick is
## a function of the car's position and the state before, and outside
## the band a function of the position alone - after any jump (reset_to,
## the reset test's teleport) the bubble around the new position is right
## at the next tick. update(at) is public so a test drives it by hand.
##
## RADII: ACTIVATE_M 80 / DEACTIVATE_M 110 (chosen for BUBBLE-1). A car at
## the ring drive's cruise (18 m/s; 30 m/s on the straights) stops in
## under 50 m from 30 m/s at the sim's braking, so a body switched on 80 m
## out is solid long before the car can reach any trunk under it; the
## chase camera sees the trees to the fog's 100-300 m band, so the bubble
## is well inside what the driver sees; the band of 30 m is more than a
## tick's way (0.5 m at 30 m/s) by a wide margin and under the smallest
## chunk gap that matters, so a body is toggled once per approach.
## Measured (tests/bubble_test.gd with FD_BUBBLE_PERF=1): the numbers in
## the landing's commit message.

## The radii [m]: active within ACTIVATE_M of a body's box, inactive past
## DEACTIVATE_M; the band between keeps the state.
const ACTIVATE_M := 80.0
const DEACTIVATE_M := 110.0
## The layers: active bodies on the car's mask (1), inactive on none (0).
const ACTIVE_LAYER := 1
const INACTIVE_LAYER := 0
## The bodies' own mask: a static body needs none.
const BODY_MASK := 0

## The car whose position drives the bubble (null: every body stays
## inactive - a forest built without a car is visuals only).
var car: Node3D = null
## The bodies and their horizontal boxes (x_lo, z_lo, x_hi, z_hi per body).
var bodies: Array[StaticBody3D] = []
var boxes := PackedFloat64Array()
## 1 where the body is active.
var active := PackedByteArray()
## The counters (ints only): ticks updated, activations, deactivations.
var updates := 0
var activations := 0
var deactivations := 0
## Whether _physics_process drives update(): off, a test drives it by hand
## (or holds every body off for a control run).
var enabled := true


func _ready() -> void:
	process_physics_priority = -2


## Takes the bodies and their boxes; every body starts INACTIVE (layer 0,
## mask 0). Sized once: nothing here allocates after this call.
func attach(car_node: Node3D, chunk_bodies: Array[StaticBody3D], chunk_boxes: PackedFloat64Array) -> void:
	car = car_node
	bodies = chunk_bodies
	boxes = chunk_boxes
	active = PackedByteArray()
	active.resize(bodies.size())
	active.fill(0)
	for body: StaticBody3D in bodies:
		body.collision_layer = INACTIVE_LAYER
		body.collision_mask = BODY_MASK
	updates = 0
	activations = 0
	deactivations = 0


func _physics_process(_delta: float) -> void:
	if enabled and car != null:
		update(car.global_position)


## One tick of the state machine at `at`: returns the number of bodies
## whose state changed (activations + deactivations this call).
func update(at: Vector3) -> int:
	updates += 1
	var changed := 0
	var activate_sq := ACTIVATE_M * ACTIVATE_M
	var deactivate_sq := DEACTIVATE_M * DEACTIVATE_M
	for i: int in bodies.size():
		var d_sq := box_distance_squared(i, at.x, at.z)
		if active[i] == 0:
			if d_sq < activate_sq:
				active[i] = 1
				bodies[i].collision_layer = ACTIVE_LAYER
				activations += 1
				changed += 1
		elif d_sq > deactivate_sq:
			active[i] = 0
			bodies[i].collision_layer = INACTIVE_LAYER
			deactivations += 1
			changed += 1
	return changed


## The squared horizontal distance from (x, z) to body `i`'s box: 0 inside.
func box_distance_squared(i: int, x: float, z: float) -> float:
	var k := i * 4
	var dx := maxf(0.0, maxf(boxes[k] - x, x - boxes[k + 2]))
	var dz := maxf(0.0, maxf(boxes[k + 1] - z, z - boxes[k + 3]))
	return dx * dx + dz * dz


## The horizontal distance from (x, z) to body `i`'s box [m].
func box_distance(i: int, x: float, z: float) -> float:
	return sqrt(box_distance_squared(i, x, z))


func is_active(i: int) -> bool:
	return active[i] == 1


func active_count() -> int:
	var n := 0
	for i: int in active.size():
		n += active[i]
	return n


## Every body off (layer 0) and the state cleared; with `enabled` false a
## control run drives through what the bubble would have made solid.
func deactivate_all() -> void:
	for i: int in bodies.size():
		if active[i] == 1:
			active[i] = 0
			bodies[i].collision_layer = INACTIVE_LAYER
			deactivations += 1


## One line: bodies, active, the counters.
func describe() -> String:
	return "%d bodies, %d active, %d updates, %d activations, %d deactivations, radii %.0f / %.0f m" % [bodies.size(), active_count(), updates, activations, deactivations, ACTIVATE_M, DEACTIVATE_M]
