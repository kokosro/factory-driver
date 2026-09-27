class_name PadCone
extends RigidBody3D
## A traffic cone on the test pad with real physics (issue-0067, the fix for
## docs/pad-physics-diagnosis.md §2: the cones WERE visual-only meshes toppled
## by a scripted footprint test and skidded a fixed distance per m/s, so a hit
## at 1 km/h and one at 20 km/h looked the same). Now the cone is a RigidBody3D
## of MASS_KG with two collision shapes (assets/cone_physics.tscn holds them
## and the mesh; the pad instantiates the scene): a square BASE PLATE, a 0.40 m
## box 4 cm thick, as a real cone's rubber base is, and above it a convex hull
## of the frustum (the 12-point base ring at the plate's top and the 12-point
## top ring, the mesh's own radii there). The plate is what stands on the
## ground: the server keeps four contact points per pair of shapes, and a
## 12-point ring standing on a trimesh floor got its four on one side, tipped
## the other way, got them on that side - four of the 108 cones rocked for
## good at 0.15 rad/s, just over the angular sleep threshold, whatever the
## damping (0.6 to 3.0 measured); a plate's four corners are its four contacts
## and it lies still. The centre of mass is CENTRE_OF_MASS_M above the ground,
## in the base: gravity, the floor, the other cones and the sheds are the
## physics server's. The car's part is the BUMPER (below).
##
## THE LAYERS: the cone stands on LAYER (3) and its mask is LAYER ALONE, so
## it rests on the cones' floor (TestPad._build_cone_floor, a trimesh of the
## pad's ground on LAYER) and bounces off the sheds (TestPad._add_box puts a
## solid's body on layer 1 and on LAYER). The car (scripts/car.gd, frozen: a
## CharacterBody3D on the default layer 1 / mask 1) and the cone never pair:
## move_and_slide neither slows nor deflects for a cone, and the server never
## resolves car against cone - measured: it bulldozes. A 4.2 m box whose
## underside is 12 cm off the ground is a wall to a 75 cm cone: the cone can
## neither go under nor over it, so it is shoved ahead at the car's speed for
## as long as the car drives (49.7 m down the slalom line in the smoke test's
## drive-through, three more cones down). A real bumper is 45 cm high: the cone
## flips over it and goes under the car. Nor does the cone pair with the car's
## ground plane (Ground/CollisionShape3D, a WorldBoundaryShape3D on layer 1
## that follows the car's elevation: the wrong height anywhere but under the
## car): NOT an exception but a mask - the server pairs bodies by layer and
## mask and only then reads the exceptions, and a static body whose shape
## moves WAKES every body it is paired with (GodotBody3D::wakeup_neighbours,
## no exception asked). With the plane in the mask (the first draft: mask
## LAYER | 1, the plane excepted) the plane's infinite AABB paired it with all
## 108 cones and _follow_car's every height step woke them all - measured: 0 of
## 108 asleep on the first tick, 104 of 108 after two seconds, four rocking on
## for good. With the mask LAYER alone nothing on the pad can wake a cone but
## another cone, a shed or the bumper.
##
## THE BUMPER: TestPad finds the cones inside the car's box every tick (a shape
## query on LAYER) and calls bump() with the car's velocity. The first tick of
## an overlap at KICK_SPEED or more is the hit: one impulse at KICK_HEIGHT_M up
## the cone's axis - KICK_FACTOR of the CLOSING speed along the car's motion
## (the car's less the cone's own), a KICK_SIDE share outward for a cone off
## the car's centre line (the corner of the bumper flicks it aside), a
## KICK_LIFT share upward - so the cone flips forward (the impulse acts above
## the centre of mass), hops, tumbles and rolls to a stop: the faster the car,
## the further and the wilder, a hit off the centre line spinning it. A cone
## hit dead ahead goes under the car (the car's body is no collider for it),
## and one that lands ahead of the car and is caught up with is kicked again,
## by the speed the car gains on it. Below KICK_SPEED the bumper SHOVES: every
## tick of the overlap the point of the cone at SHOVE_HEIGHT_M is brought up to
## the car's speed along its motion, so a creeping car pushes the cone along
## ahead of it, leaning a little (1 km/h: a wobble, no fall). MEASURED on the
## pad's first slalom cone, the car driven straight at it: at 1.0 km/h the
## cone slides ahead of the car tilted 0.4 deg, 0.75 m in the 3 s until the
## car stops, and stands where it is left (its peak 0.31 m/s, 0.14 rad/s); at
## 19.2 km/h it leaves at 6.66 m/s spinning at 9.98 rad/s, flips, flies, is
## caught once more under the passing car and comes to rest 5.98 m on, on its
## plate again, asleep 25 ticks after landing.
##
## THE STATES: a cone spawns ASLEEP standing on its home (`sleeping` true, at
## rest to the bit: no settling wobble, no cost until touched; an impulse wakes
## it - the how and the why in _physics_process) and sleeps again where it
## comes to rest (a woken cone standing still sleeps in under a second: all
## 108 woken at once where they stand, 106 asleep again by the 45th tick
## after, 107 by the 75th, the last by the 145th, none moved over 1 cm -
## measured, the same to the digit on a second run).
## `toppled` is the pad's verdict:
## read by watch(), it LATCHES once the cone has tilted past TOPPLED_TILT_DEG or
## its base has moved MOVED_M from home (a cone rocked and standing is not
## down; one knocked over and rolled back upright still was; one shoved half a
## metre was hit), and only the pad's reset_cones (a fresh instance) clears it.

## The frustum: what the mesh and the hull are built from [m].
const HEIGHT := 0.75
const BASE_RADIUS := 0.28
const TOP_RADIUS := 0.04

## A real traffic cone: 75 cm, a rubber base, about 2 kg.
const MASS_KG := 2.0
## The centre of mass, measured from the ground [m]: low, in the base.
const CENTRE_OF_MASS_M := 0.2

## Physics layer 3: the pad's cones, their floor and the sheds' second layer
## (the cone's layer AND its whole mask: see THE LAYERS above).
const LAYER := 1 << 2

## Where the car's flat face meets the frustum when it creeps into it [m up
## the axis]: the face's lower edge - the car's box stands 0.12 m off the
## ground (scenes/car.tscn: 1.08 m tall, 0.66 m up) and a frustum is widest at
## its foot, so a vertical face touches it low. Below the centre of mass
## (CENTRE_OF_MASS_M): a push here slides the cone, a push at 0.45 m (the
## first draft's one height) tipped it - the tipping torque about the plate's
## front edge beats the base's friction there, and a 1 km/h creep felled the
## cone in three seconds, tilt 107 deg (measured; docs/pad-physics-diagnosis.md
## §2 wants a wobble, not a fall, at 1 km/h).
const SHOVE_HEIGHT_M := 0.15
## Where a hit at speed bites [m up the axis]: the face's height, the cone
## bending into it - above the centre of mass, so the cone flips.
const KICK_HEIGHT_M := 0.35
## A car at this speed or more kicks the cone (one impulse); slower, it shoves.
const KICK_SPEED := 2.0  # [m/s], 7 km/h.
## The kick: the cone's speed along the car's motion per m/s of the car's. A
## 2 kg cone against a 1 000 kg car leaves at (1 + e) times the car's speed,
## e the restitution of a plastic cone on a bumper, 0.2-0.5 (was 0.6: a
## 20 km/h hit flipped the cone on the spot, 0.44 m from home - measured).
const KICK_FACTOR := 1.2
## ... plus this share of that outward, times how far off the car's centre
## line the cone stands (0 dead ahead, 1 at the car's side) ...
const KICK_SIDE := 0.8
## ... and this share of it upward: the flip over the bumper.
const KICK_LIFT := 0.35

## Tilted this far from upright the cone counts as knocked over [deg].
const TOPPLED_TILT_DEG := 45.0
## Its base this far from home the cone counts as knocked over [m].
const MOVED_M := 0.5

## Where the cone stands, ground height included: its base's centre [m].
var home := Vector3.ZERO
## The pad's group it belongs to (TestPad.GROUP_*).
var group: StringName = &""
## Knocked over since it was stood up (latched; see the class comment).
var toppled := false
## Inside the car's box last tick (the pad's, through bump / clear_of_car).
var in_car := false
## The spawn's sleep is still owed: see _physics_process.
var _sleep_owed := false
## The physics frame the cone entered the tree in (Engine.get_physics_frames).
var _entered_frame := -1


## Stands the cone upright on `base_position` in `cone_group`, painted with
## `material`. Call before adding it to the tree: the cone enters FROZEN (a
## kinematic body, no gravity, nothing moves it) and turns rigid and asleep on
## its first physics tick of a later frame (_physics_process).
func stand(base_position: Vector3, cone_group: StringName, material: Material) -> void:
	home = base_position
	group = cone_group
	toppled = false
	in_car = false
	transform = Transform3D(Basis.IDENTITY, standing_position())
	($Mesh as MeshInstance3D).material_override = material
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	freeze = true
	_sleep_owed = true
	set_physics_process(true)


func _enter_tree() -> void:
	_entered_frame = Engine.get_physics_frames()


## The spawn's sleep, paid on the first physics tick of a frame AFTER the one
## the cone entered the tree in, and then never run again (set_physics_process
## false). A `sleeping` set in the frame the cone enters the tree does not
## hold: the tree's transform flush of that frame (at the frame's start for
## a cone added between frames, after the nodes' _physics_process for one
## added inside a frame, as reset_cones from a test's coroutine adds them)
## delivers the body's transform to the server and a rigid body told its
## transform WAKES - measured on a bare tree, no floor: set before add_child,
## after it, after force_update_transform, deferred, in the same frame's
## _physics_process - awake and falling on the next tick, every one; and a
## body added between frames is stepped once before any node's first tick
## (the deferred-call flush sits between the tree's physics process and the
## server's step): 2.7 mm of fall. The same set in the NEXT frame - after
## every flush, before that frame's step - holds (measured: asleep on every
## tick after, at rest to the bit). Frozen until then the cone does not fall
## that tick. Asleep the cone stands on its home until something hits it;
## awake it would settle the solver's centimetre into the floor and rock for
## half a second on every spawn and every reset.
func _physics_process(_delta: float) -> void:
	if not _sleep_owed:
		set_physics_process(false)
		return
	if Engine.get_physics_frames() <= _entered_frame:
		return
	_sleep_owed = false
	freeze = false
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	sleeping = true
	set_physics_process(false)


## The body's origin when the cone stands upright at home [m].
func standing_position() -> Vector3:
	return home + Vector3.UP * HEIGHT * 0.5


## The car's box holds the cone this tick: `car_velocity` the car's [m/s],
## `side` how far off the car's centre line the cone stands (-1 .. 1, the
## car's left to its right) and `outward` the car's own right, so a cone at
## the car's right side is flicked to the right. See THE BUMPER above.
func bump(car_velocity: Vector3, side: float, outward: Vector3) -> void:
	var motion := Vector3(car_velocity.x, 0.0, car_velocity.z)
	var speed := motion.length()
	var first := not in_car
	in_car = true
	if speed < 0.001:
		return
	var direction := motion / speed
	if speed >= KICK_SPEED:
		if first:
			# The closing speed, not the car's: a cone already on its way (one
			# the car kicked, landed ahead and caught up with) is hit only as
			# fast as the car gains on it - the first draft added the car's
			# whole speed a second time, 6.7 -> 10.0 m/s (measured), and the
			# cone flew 18 m down the slalom line.
			var closing := speed - linear_velocity.dot(direction)
			if closing > 0.0:
				var kick := direction + outward * (KICK_SIDE * clampf(side, -1.0, 1.0)) + Vector3.UP * KICK_LIFT
				apply_impulse(kick * (closing * KICK_FACTOR * mass), global_basis.y * (KICK_HEIGHT_M - HEIGHT * 0.5))
		return
	var at := global_basis.y * (SHOVE_HEIGHT_M - HEIGHT * 0.5)  # Up the axis, from the origin.
	# The shove: the point of the cone the bumper holds cannot move slower than
	# the bumper along the car's motion. One impulse there brings it up to the
	# car's speed, sized by the cone's effective mass at that point along that
	# line (the mass and the inertia about the centre of mass together), so the
	# cone leans on the bumper instead of being pumped into a rock: the way a
	# contact impulse is sized (1 / m_eff = 1 / m + n . ((I^-1 (r x n)) x r)).
	var state := PhysicsServer3D.body_get_direct_state(get_rid())
	if state == null:
		return
	var short := speed - state.get_velocity_at_local_position(at).dot(direction)
	if short <= 0.0:
		return
	var arm := at - state.center_of_mass
	var lever := arm.cross(direction)
	var inverse_effective_mass := state.inverse_mass + direction.dot((state.inverse_inertia_tensor * lever).cross(arm))
	if inverse_effective_mass > 0.0:
		apply_impulse(direction * (short / inverse_effective_mass), at)


## The car's box does not hold the cone this tick.
func clear_of_car() -> void:
	in_car = false


## Reads the cone's pose and latches `toppled`. Returns the verdict.
func watch() -> bool:
	if toppled:
		return true
	var pose := global_transform
	if pose.basis.y.y < cos(deg_to_rad(TOPPLED_TILT_DEG)):
		toppled = true
	else:
		var base := pose.origin - pose.basis.y * HEIGHT * 0.5
		if Vector2(base.x - home.x, base.z - home.z).length() > MOVED_M:
			toppled = true
	return toppled
