extends Camera3D
## Third-person chase camera. Swings in behind the car's heading and trails its
## position with a little lag, so the car visibly moves against the frame when
## it accelerates, brakes or turns.

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

## Field of view at standstill and at the car's top speed [degrees].
const FOV_AT_REST := 65.0
const FOV_AT_MAX_SPEED := 82.0

@export var target: ArcadeCar

var _yaw := 0.0


func _ready() -> void:
	# The camera does its own per-frame smoothing from the car's interpolated
	# transform, so engine physics interpolation must stay out of its way.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	top_level = true
	if target:
		_yaw = target.global_rotation.y
		global_position = _ideal_position(target.global_position)
		_aim_at(target.global_position)


func _process(delta: float) -> void:
	if not target:
		return
	var target_xform := target.get_global_transform_interpolated()
	var target_yaw := target_xform.basis.get_euler().y

	_yaw = lerp_angle(_yaw, target_yaw, 1.0 - exp(-YAW_FOLLOW_RATE * delta))
	global_position = global_position.lerp(
		_ideal_position(target_xform.origin), 1.0 - exp(-POSITION_FOLLOW_RATE * delta)
	)
	_aim_at(target_xform.origin)
	fov = lerpf(FOV_AT_REST, FOV_AT_MAX_SPEED, target.speed_ratio)


func _ideal_position(target_position: Vector3) -> Vector3:
	# The car's nose is -Z, so "behind" is +Z rotated by the camera's yaw.
	var offset := Vector3(0.0, FOLLOW_HEIGHT, FOLLOW_DISTANCE).rotated(Vector3.UP, _yaw)
	return target_position + offset


func _aim_at(target_position: Vector3) -> void:
	look_at(target_position + Vector3.UP * LOOK_AT_HEIGHT, Vector3.UP)
