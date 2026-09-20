extends Camera3D
## The game's one camera. Starts as a third-person chase camera that swings in
## behind the car's heading and trails its position with a little lag, so the
## car visibly moves against the frame when it accelerates, brakes or turns.
## The camera_cycle action steps through the other views: cockpit, front
## (bonnet), overhead and wheel (down by the front-left tyre), then back to
## chase. Holding look_back shows the rear view for as long as it is held.
## Holding look_left / look_right turns the view to that side for as long as it
## is held (a glance, not a view of its own: mode_name() stays what it was).

## REAR is held-only: look_back cuts to it, the cycle never lands on it.
enum Mode { CHASE, COCKPIT, FRONT, OVERHEAD, WHEEL, REAR }

const MODE_NAMES: Array[String] = ["chase", "cockpit", "front", "overhead", "wheel", "rear"]

# --- Tuning ------------------------------------------------------------------

## Distance behind the car [m].
const FOLLOW_DISTANCE := 6.5

## Height above the car's origin [m].
const FOLLOW_HEIGHT := 2.6

## The camera aims at a point this far above the car's origin [m].
const LOOK_AT_HEIGHT := 1.1

## How quickly the camera swings round behind the car's heading [1/s].
## Lower = lazier swing that shows more of the car's flank in corners.
const YAW_FOLLOW_RATE := 5.0

## How quickly the camera closes in on its ideal position [1/s]. The trailing
## lag is roughly speed / rate metres, so it stretches out a little at speed.
const POSITION_FOLLOW_RATE := 14.0

# --- Looking left and right -----------------------------------------------------
# Held keys (look_left / look_right; both or neither = straight ahead). Chase:
# the camera swings round the car so the view turns to that side. Cockpit and
# front: the head turns, the eye stays where it is. Overhead, wheel and rear
# have no side to look to and ignore the keys. look_back wins over both: the
# rear view is a cut, and the glance is back at 0 by the time it ends.

## How far the chase view turns to the side [degrees]: the camera ends up off
## the car's opposite rear quarter, the car still in frame, the road to that
## side in view.
const LOOK_CHASE_YAW_DEG := 65.0

## How far the driver's head turns in the cockpit (and the bonnet view)
## [degrees]: over the door top, short of the seat back.
const LOOK_HEAD_YAW_DEG := 60.0

## How quickly the glance goes out and comes back [1/s]: 12 is there within a
## quarter of a second, a turn of the head, not a cut. Eased, per frame, from
## the frame time alone.
const LOOK_RATE := 12.0

## Field of view at standstill and at the car's top speed [degrees].
const FOV_AT_REST := 65.0
const FOV_AT_MAX_SPEED := 82.0

# --- Modes -------------------------------------------------------------------
# Offsets are in the car's own space: origin on the ground under the middle of
# the car, nose towards -Z, +X to the driver's right, +Y up. Cockpit, front,
# wheel and rear are fixed rigidly to the car, with no lag.

## Cockpit: the driver's eye, inside the cabin box on the left-hand seat [m].
## The cabin's walls face outwards, so from in here they are not drawn; the
## bonnet ahead and the roof above are.
const COCKPIT_EYE := Vector3(-0.32, 1.12, 0.1)

## Cockpit: downward tilt of the view [degrees].
const COCKPIT_PITCH_DEG := 3.0

## Cockpit: field of view at standstill and at top speed [degrees].
const COCKPIT_FOV_AT_REST := 72.0
const COCKPIT_FOV_AT_MAX_SPEED := 84.0

## Cockpit: near clip plane [m], close enough to keep the steering wheel whole.
const COCKPIT_NEAR := 0.03

## Cockpit dashboard silhouette: centre and size of the panel across the base
## of the windscreen [m] ...
const DASH_PANEL_CENTRE := Vector3(0.0, 0.91, -0.6)
const DASH_PANEL_SIZE := Vector3(1.4, 0.12, 0.5)

## ... the instrument cowl on top of it, in front of the driver [m] ...
const DASH_COWL_CENTRE := Vector3(-0.32, 0.995, -0.5)
const DASH_COWL_SIZE := Vector3(0.36, 0.05, 0.2)

## ... a dark floor over the cabin's footprint, so a glance down does not show
## the top of the painted body [m] ...
const DASH_FLOOR_CENTRE := Vector3(0.0, 0.86, 0.25)
const DASH_FLOOR_SIZE := Vector3(1.4, 0.02, 1.9)

## ... and the steering wheel: hub position, rim radius, rim thickness [m] and
## how far the wheel leans back from upright [degrees]. It turns with the car's
## own steering wheel (ArcadeCar.steering_wheel_deg), all 450 degrees each way:
## past half a turn the spoke simply comes round again, as the real one does;
## nothing is clamped or wrapped, the angle is the angle. A marker at the top
## of the rim (12 o'clock with the wheels straight) tells one turn from the
## next.
# was WHEEL_LOCK_DEG 100.0, the dashboard wheel turned steer x 100 degrees, a
# gesture -> removed: the true rotation, 450 degrees at full lock.
const WHEEL_CENTRE := Vector3(-0.32, 0.95, -0.27)
const WHEEL_RADIUS := 0.16
const WHEEL_RIM_THICKNESS := 0.022
const WHEEL_LEAN_DEG := 20.0
const WHEEL_MARKER_COLOR := Color(0.85, 0.7, 0.1, 1)

const DASH_COLOR := Color(0.035, 0.035, 0.04, 1)
const WHEEL_COLOR := Color(0.1, 0.1, 0.11, 1)

## Front: on the bonnet, far enough back that its leading edge is in shot [m].
const FRONT_EYE := Vector3(0.0, 1.0, -1.0)

## Front: downward tilt of the view [degrees].
const FRONT_PITCH_DEG := 5.0

## Front: field of view at standstill and at top speed [degrees].
const FRONT_FOV_AT_REST := 70.0
const FRONT_FOV_AT_MAX_SPEED := 86.0

## Overhead: straight down, north (-Z, the way the tests run) always up the
## screen. The view does not turn with the car, so spins stay readable and the
## ground holds still for parking. Height above the car at standstill and at
## top speed [m]: low for placing the car in a box, high to see ahead.
const OVERHEAD_HEIGHT_AT_REST := 26.0
const OVERHEAD_HEIGHT_AT_MAX_SPEED := 40.0

## Overhead: field of view [degrees].
const OVERHEAD_FOV := 55.0

## Overhead: the view centres on where the car will be in this many seconds ...
const OVERHEAD_LEAD_TIME := 0.25

## ... and how quickly that lead and the height follow the car's speed [1/s].
const OVERHEAD_FOLLOW_RATE := 3.0

## Overhead: screen-right is +X, screen-up is -Z, and the camera looks down -Y.
const OVERHEAD_BASIS := Basis(Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0))

## Wheel: low, ahead and outboard of the front-left wheel (the one that steers
## and does most of the braking), outside the body and clear of the tyre [m] ...
const WHEEL_CAM_EYE := Vector3(-1.75, 0.5, -2.2)

## ... aimed back at that wheel, just above its contact patch [m], so the tyre,
## its steering angle, its spin and the tarmac running under it are all in shot.
const WHEEL_CAM_LOOK_AT := Vector3(-0.86, 0.12, -1.3)

## Wheel: field of view at standstill and at top speed [degrees].
const WHEEL_CAM_FOV_AT_REST := 60.0
const WHEEL_CAM_FOV_AT_MAX_SPEED := 68.0

## Rear (held): ahead of the nose and above the roof line (~1.35 m), so the
## road behind shows over the car [m] ...
const REAR_EYE := Vector3(0.0, 1.8, -3.2)

## ... aimed back along the car at the top of its tail [m].
const REAR_LOOK_AT := Vector3(0.0, 1.1, 2.1)

## Rear: field of view at standstill and at top speed [degrees].
const REAR_FOV_AT_REST := 70.0
const REAR_FOV_AT_MAX_SPEED := 80.0

@export var target: ArcadeCar

## The active view. Change it with set_mode() or cycle_mode().
var mode := Mode.CHASE

## The view look_back interrupted, restored when the key is released.
var _mode_before_rear := Mode.CHASE
var _yaw := 0.0

## The glance: -1 (fully right) .. +1 (fully left), eased towards what the look
## keys ask for (_look_target, polled with the other keys).
var _look := 0.0
var _look_target := 0.0
var _default_near := 0.05
var _overhead_lead := Vector3.ZERO
var _overhead_height := OVERHEAD_HEIGHT_AT_REST
var _dashboard: Node3D
var _steering_wheel: Node3D


func _ready() -> void:
	# The camera does its own per-frame smoothing from the car's interpolated
	# transform, so engine physics interpolation must stay out of its way.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	top_level = true
	_default_near = near
	if target:
		_build_dashboard()
		set_mode(Mode.CHASE)


func _physics_process(_delta: float) -> void:
	# Polled here, like the car's own keys.
	var look_back := Input.is_action_pressed("look_back")
	if look_back and mode != Mode.REAR:
		_mode_before_rear = mode
		set_mode(Mode.REAR)
	elif not look_back and mode == Mode.REAR:
		set_mode(_mode_before_rear)
	# +1 = look_left, -1 = look_right (the sign of yaw). Not while looking back.
	_look_target = 0.0 if look_back else Input.get_axis("look_right", "look_left")
	# The cycle waits while the rear view is held.
	if Input.is_action_just_pressed("camera_cycle") and mode != Mode.REAR:
		cycle_mode()


func _process(delta: float) -> void:
	if not target:
		return
	var target_xform := target.get_global_transform_interpolated()
	_look = lerpf(_look, _look_target, 1.0 - exp(-LOOK_RATE * delta))
	match mode:
		Mode.CHASE:
			_update_chase(target_xform, delta)
		Mode.COCKPIT:
			_update_cockpit(target_xform)
		Mode.FRONT:
			_update_front(target_xform)
		Mode.OVERHEAD:
			_update_overhead(target_xform, delta)
		Mode.WHEEL:
			_update_wheel(target_xform)
		Mode.REAR:
			_update_rear(target_xform)


## Name of the active view: "chase", "cockpit", "front", "overhead" or "wheel",
## and "rear" while look_back is held.
func mode_name() -> String:
	return MODE_NAMES[mode]


## Steps to the next view, wrapping back to chase after the last. The held-only
## rear view is not a stop on the way.
func cycle_mode() -> void:
	var next := (mode + 1) % Mode.size()
	if next == Mode.REAR:
		next = (next + 1) % Mode.size()
	set_mode(next as Mode)


## Cuts straight to a view, placing the camera where that view wants it now.
func set_mode(new_mode: Mode) -> void:
	mode = new_mode
	near = COCKPIT_NEAR if mode == Mode.COCKPIT else _default_near
	if _dashboard:
		_dashboard.visible = mode == Mode.COCKPIT
	if not target:
		return
	var target_xform := target.global_transform
	match mode:
		Mode.CHASE:
			_yaw = target.global_rotation.y
			global_position = _ideal_position(target_xform.origin)
			_update_chase(target_xform, 0.0)
		Mode.COCKPIT:
			_update_cockpit(target_xform)
		Mode.FRONT:
			_update_front(target_xform)
		Mode.OVERHEAD:
			_overhead_lead = _overhead_lead_target()
			_overhead_height = _overhead_height_target()
			_update_overhead(target_xform, 0.0)
		Mode.WHEEL:
			_update_wheel(target_xform)
		Mode.REAR:
			_update_rear(target_xform)


# --- Chase ---------------------------------------------------------------------

func _update_chase(target_xform: Transform3D, delta: float) -> void:
	var target_yaw := target_xform.basis.get_euler().y

	_yaw = lerp_angle(_yaw, target_yaw, 1.0 - exp(-YAW_FOLLOW_RATE * delta))
	global_position = global_position.lerp(
		_ideal_position(target_xform.origin), 1.0 - exp(-POSITION_FOLLOW_RATE * delta)
	)
	_aim_at(target_xform.origin)
	fov = lerpf(FOV_AT_REST, FOV_AT_MAX_SPEED, target.speed_ratio)


func _ideal_position(target_position: Vector3) -> Vector3:
	# The car's nose is -Z, so "behind" is +Z rotated by the camera's yaw.
	# A glance to the side swings the camera round the car the same way.
	var offset := Vector3(0.0, FOLLOW_HEIGHT, FOLLOW_DISTANCE).rotated(Vector3.UP, _yaw + _look * deg_to_rad(LOOK_CHASE_YAW_DEG))
	return target_position + offset


func _aim_at(target_position: Vector3) -> void:
	look_at(target_position + Vector3.UP * LOOK_AT_HEIGHT, Vector3.UP)


# --- Cockpit and front -----------------------------------------------------------

## The cockpit and the bonnet view ride on the BODY, not on the wheels: they
## dive with it under braking, lean with it in a corner and heave with it over
## a crest (ArcadeCar.get_body_ride). The dashboard goes along.
func _update_cockpit(target_xform: Transform3D) -> void:
	var ride := target.get_body_ride()
	_dashboard.transform = ride
	_mount(target_xform * ride, COCKPIT_EYE, COCKPIT_PITCH_DEG)
	fov = lerpf(COCKPIT_FOV_AT_REST, COCKPIT_FOV_AT_MAX_SPEED, target.speed_ratio)
	_steering_wheel.rotation.y = deg_to_rad(target.steering_wheel_deg)


func _update_front(target_xform: Transform3D) -> void:
	_mount(target_xform * target.get_body_ride(), FRONT_EYE, FRONT_PITCH_DEG)
	fov = lerpf(FRONT_FOV_AT_REST, FRONT_FOV_AT_MAX_SPEED, target.speed_ratio)


## Fixes the camera to the car at `eye` (car space), looking along the nose,
## turned to the side by the glance (LOOK_HEAD_YAW_DEG) and tilted down by
## `pitch_deg`.
func _mount(target_xform: Transform3D, eye: Vector3, pitch_deg: float) -> void:
	var head := Basis(Vector3.UP, _look * deg_to_rad(LOOK_HEAD_YAW_DEG)) * Basis(Vector3.RIGHT, -deg_to_rad(pitch_deg))
	global_transform = Transform3D(target_xform.basis.orthonormalized() * head, target_xform * eye)


## Fixes the camera to the car at `eye`, aimed at `look_at_point` (both car
## space), upright in the car's own frame.
func _mount_aimed(target_xform: Transform3D, eye: Vector3, look_at_point: Vector3) -> void:
	var view := target_xform.basis.orthonormalized() * Basis.looking_at(look_at_point - eye, Vector3.UP)
	global_transform = Transform3D(view, target_xform * eye)


## The cockpit's dashboard: a dark panel, an instrument cowl, a floor and a
## steering wheel, all primitives. It rides on the car and only shows in the cockpit view.
func _build_dashboard() -> void:
	var dash_material := StandardMaterial3D.new()
	dash_material.albedo_color = DASH_COLOR
	dash_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var wheel_material := StandardMaterial3D.new()
	wheel_material.albedo_color = WHEEL_COLOR
	wheel_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	_dashboard = Node3D.new()
	_dashboard.name = "CockpitDashboard"
	_dashboard.visible = false
	target.add_child(_dashboard)
	_add_dash_box(DASH_PANEL_CENTRE, DASH_PANEL_SIZE, dash_material)
	_add_dash_box(DASH_COWL_CENTRE, DASH_COWL_SIZE, dash_material)
	_add_dash_box(DASH_FLOOR_CENTRE, DASH_FLOOR_SIZE, dash_material)

	# The column points back and up at the driver; the wheel turns about it.
	var column := Node3D.new()
	column.position = WHEEL_CENTRE
	column.rotation.x = deg_to_rad(90.0 - WHEEL_LEAN_DEG)
	_dashboard.add_child(column)
	_steering_wheel = Node3D.new()
	column.add_child(_steering_wheel)
	var rim_mesh := TorusMesh.new()
	rim_mesh.inner_radius = WHEEL_RADIUS - WHEEL_RIM_THICKNESS
	rim_mesh.outer_radius = WHEEL_RADIUS
	rim_mesh.material = wheel_material
	_add_part(_steering_wheel, rim_mesh, Vector3.ZERO)
	var spoke_mesh := BoxMesh.new()
	spoke_mesh.size = Vector3(WHEEL_RADIUS * 2.0 - WHEEL_RIM_THICKNESS, WHEEL_RIM_THICKNESS, WHEEL_RIM_THICKNESS * 1.6)
	spoke_mesh.material = wheel_material
	_add_part(_steering_wheel, spoke_mesh, Vector3.ZERO)
	# The centre marker: a band round the top of the rim. The wheel lies in the
	# column's XZ plane, the top of the rim towards the column's -Z.
	var marker_material := StandardMaterial3D.new()
	marker_material.albedo_color = WHEEL_MARKER_COLOR
	marker_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var marker_mesh := BoxMesh.new()
	marker_mesh.size = Vector3(WHEEL_RIM_THICKNESS * 1.2, WHEEL_RIM_THICKNESS * 1.2, WHEEL_RIM_THICKNESS * 1.3)
	marker_mesh.material = marker_material
	_add_part(_steering_wheel, marker_mesh, Vector3(0.0, 0.0, -(WHEEL_RADIUS - WHEEL_RIM_THICKNESS * 0.5)))


func _add_dash_box(centre: Vector3, size: Vector3, material: Material) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	_add_part(_dashboard, mesh, centre)


func _add_part(parent: Node3D, mesh: Mesh, at: Vector3) -> void:
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.position = at
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(part)


# --- Wheel and rear ---------------------------------------------------------------

func _update_wheel(target_xform: Transform3D) -> void:
	_mount_aimed(target_xform, WHEEL_CAM_EYE, WHEEL_CAM_LOOK_AT)
	fov = lerpf(WHEEL_CAM_FOV_AT_REST, WHEEL_CAM_FOV_AT_MAX_SPEED, target.speed_ratio)


func _update_rear(target_xform: Transform3D) -> void:
	_mount_aimed(target_xform, REAR_EYE, REAR_LOOK_AT)
	fov = lerpf(REAR_FOV_AT_REST, REAR_FOV_AT_MAX_SPEED, target.speed_ratio)


# --- Overhead --------------------------------------------------------------------

func _update_overhead(target_xform: Transform3D, delta: float) -> void:
	var blend := 1.0 - exp(-OVERHEAD_FOLLOW_RATE * delta)
	_overhead_lead = _overhead_lead.lerp(_overhead_lead_target(), blend)
	_overhead_height = lerpf(_overhead_height, _overhead_height_target(), blend)
	var centre := target_xform.origin + _overhead_lead
	global_transform = Transform3D(OVERHEAD_BASIS, centre + Vector3.UP * _overhead_height)
	fov = OVERHEAD_FOV


func _overhead_lead_target() -> Vector3:
	return Vector3(target.velocity.x, 0.0, target.velocity.z) * OVERHEAD_LEAD_TIME


func _overhead_height_target() -> float:
	return lerpf(OVERHEAD_HEIGHT_AT_REST, OVERHEAD_HEIGHT_AT_MAX_SPEED, target.speed_ratio)
