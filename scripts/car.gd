class_name ArcadeCar
extends CharacterBody3D
## Custom arcade vehicle controller (no VehicleBody3D / VehicleWheel3D).
##
## Model in one paragraph: every physics tick the car's horizontal velocity is
## split into a FORWARD component (along the nose) and a LATERAL component
## (sideways slip). Throttle/brake only ever change the forward component.
## Steering only ever rotates the body. Because the velocity vector does not
## rotate with the body, turning creates lateral slip, and LATERAL_GRIP decides
## how quickly that slip is scrubbed away. High grip = on rails, low grip = drift.
##
## Conventions: the car's nose points along local -Z, +X is the car's right,
## positive yaw (rotation about +Y) is a LEFT turn. The car is assumed to drive
## on level ground (true for the Phase 0 test pad).

# =============================================================================
#  DRIVING FEEL TUNING
#  The one place to tweak how the car feels. Speeds are m/s, accelerations are
#  m/s^2, angles are radians, rates are per second. (1 m/s = 3.6 km/h.)
# =============================================================================

# --- Longitudinal: engine, brakes, reverse -----------------------------------

## Forward acceleration at standstill with full throttle [m/s^2]. Fades out
## towards MAX_SPEED (see _update_forward_speed). 9.0 gives roughly 0-100 km/h
## in ~3.5 s.
const ENGINE_ACCEL := 9.0

## Top speed going forward [m/s]. 61 m/s is about 220 km/h. Engine acceleration
## reaches zero exactly here, so the car approaches it asymptotically.
const MAX_SPEED := 61.0

## Deceleration while braking, i.e. pressing the key that opposes the current
## direction of travel [m/s^2]. 1 g is about 9.8; arcade brakes are stronger.
const BRAKE_DECEL := 26.0

## Deceleration with no throttle or brake input: engine braking plus rolling
## resistance lumped together [m/s^2].
const COAST_DECEL := 2.5

## Acceleration in reverse gear [m/s^2].
const REVERSE_ACCEL := 6.0

## Top speed in reverse [m/s]. 12 m/s is about 43 km/h.
const MAX_REVERSE_SPEED := 12.0

## Below this speed [m/s] the car counts as stopped: holding brake engages
## reverse and holding accelerate engages forward drive, instead of braking.
const STANDSTILL_SPEED := 0.5

# --- Steering ----------------------------------------------------------------

## Steering rate: the highest yaw rate the car can reach, at low speed with full
## lock [rad/s]. 2.0 rad/s is about 115 degrees per second.
const MAX_YAW_RATE := 2.0

## Speed-sensitive steering falloff [m/s]. Available yaw rate is
## MAX_YAW_RATE / (1 + speed / STEER_FALLOFF_SPEED): halved at this speed,
## a third at twice this speed, and so on. At high speed cornering force
## levels off near MAX_YAW_RATE * STEER_FALLOFF_SPEED (18 m/s^2, ~1.8 g).
## Lower = calmer, more stable at speed. Higher = twitchier at speed.
const STEER_FALLOFF_SPEED := 9.0

## Tightest turning circle radius [m]. Caps yaw rate at speed / radius so the
## car cannot spin on the spot: no steering at standstill, and parking-speed
## turns look like the wheels are actually rolling.
const MIN_TURN_RADIUS := 5.0

## How fast the steering input moves towards the pressed key, and back to
## centre on release [1/s]. 5.0 means centre to full lock in 0.2 s. Smooths out
## the on/off nature of keyboard steering.
const STEER_RESPONSE := 5.0

# --- Lateral grip / drift ----------------------------------------------------

## Lateral grip: how quickly sideways slip is scrubbed off [1/s]. Each second
## the lateral speed decays by a factor of e^-LATERAL_GRIP. ~10+ feels glued to
## the road, ~7 is grippy with a hint of slide, ~2-3 is a loose drift car.
## Scrubbed slip is lost energy, so hard cornering also bleeds a little speed.
const LATERAL_GRIP := 7.0

# --- Visual only (no effect on handling) -------------------------------------

## Wheel radius [m]; must match the wheel mesh. Used for the wheel spin speed.
const WHEEL_RADIUS := 0.34

## Front wheel visual steering angle at full lock [rad].
const MAX_WHEEL_STEER_ANGLE := 0.5

## Cap on the visual wheel spin [rad/s], kept under half a turn per physics
## tick so the wheels never appear to spin backwards at high speed.
const MAX_WHEEL_SPIN := 100.0

## Body roll per unit of lateral acceleration [rad per m/s^2].
const BODY_ROLL_PER_ACCEL := 0.004

## Body pitch per unit of longitudinal acceleration [rad per m/s^2].
const BODY_PITCH_PER_ACCEL := 0.003

## Largest body roll / pitch angle [rad].
const MAX_BODY_TILT := 0.09

## How quickly the body settles towards its target tilt [1/s].
const BODY_TILT_RESPONSE := 6.0

# =============================================================================
#  STATE
# =============================================================================

## Signed speed along the nose [m/s]. Negative while reversing.
var forward_speed := 0.0

## Signed sideways slip speed [m/s]. Positive = sliding towards the car's right.
var lateral_speed := 0.0

## Current yaw rate [rad/s]. Positive = turning left.
var yaw_rate := 0.0

## Smoothed steering input, -1 (full right) .. +1 (full left).
var steer := 0.0

## Speedometer value [km/h], always positive.
var speed_kmh: float:
	get:
		return absf(forward_speed) * 3.6

## Forward speed as a fraction of MAX_SPEED, 0..1. Handy for camera/HUD effects.
var speed_ratio: float:
	get:
		return clampf(absf(forward_speed) / MAX_SPEED, 0.0, 1.0)

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _spawn_transform: Transform3D

@onready var _body: Node3D = $Body
@onready var _front_wheels: Array[Node3D] = [$Wheels/FrontLeft, $Wheels/FrontRight]
@onready var _wheel_spinners: Array[Node3D] = [
	$Wheels/FrontLeft/Spin,
	$Wheels/FrontRight/Spin,
	$Wheels/RearLeft/Spin,
	$Wheels/RearRight/Spin,
]


func _ready() -> void:
	_spawn_transform = global_transform


func _physics_process(delta: float) -> void:
	if Input.is_action_just_pressed("reset_car"):
		reset_to_spawn()

	# +1 = drive forward, -1 = brake / reverse. Both keys held cancel out.
	var drive_input := Input.get_action_strength("accelerate") - Input.get_action_strength("brake")
	# +1 = left, -1 = right (matches the sign of yaw).
	var steer_input := Input.get_axis("steer_right", "steer_left")

	# 1. Split the current horizontal velocity into the car's own frame. Reading
	#    it back from `velocity` means collisions are respected automatically.
	var forward_dir := -global_basis.z
	var right_dir := global_basis.x
	forward_speed = velocity.dot(forward_dir)
	lateral_speed = velocity.dot(right_dir)
	var vertical_speed := velocity.y

	# 2. Longitudinal: engine, brakes, reverse, coasting.
	var previous_forward_speed := forward_speed
	forward_speed = _update_forward_speed(forward_speed, drive_input, delta)
	var longitudinal_accel := (forward_speed - previous_forward_speed) / delta

	# 3. Lateral: tyres scrub off sideways slip.
	lateral_speed *= exp(-LATERAL_GRIP * delta)

	# 4. Steering: turn the body. The velocity is rebuilt from the directions of
	#    *before* the turn, so the nose rotates away from the direction of travel
	#    and the difference shows up as lateral slip on the next tick.
	steer = move_toward(steer, steer_input, STEER_RESPONSE * delta)
	yaw_rate = _compute_yaw_rate(steer, forward_speed)

	if not is_on_floor():
		vertical_speed -= _gravity * delta
	velocity = forward_dir * forward_speed + right_dir * lateral_speed + Vector3.UP * vertical_speed

	rotate_y(yaw_rate * delta)
	move_and_slide()

	_update_visuals(longitudinal_accel, delta)


## Puts the car back where the scene placed it, at rest.
func reset_to_spawn() -> void:
	global_transform = _spawn_transform
	velocity = Vector3.ZERO
	forward_speed = 0.0
	lateral_speed = 0.0
	yaw_rate = 0.0
	steer = 0.0
	_body.rotation = Vector3.ZERO
	reset_physics_interpolation()


## Returns the new forward speed after one tick of engine / brake / coasting.
## `drive` is +1 for the accelerate key and -1 for the brake key.
func _update_forward_speed(speed: float, drive: float, delta: float) -> float:
	if is_zero_approx(drive):
		return move_toward(speed, 0.0, COAST_DECEL * delta)

	# Pressing against the direction of travel brakes. Once the car has come to
	# a stop, the same key takes over as drive in the other direction, so
	# holding brake flows from braking straight into reverse.
	var is_moving := absf(speed) > STANDSTILL_SPEED
	if is_moving and signf(drive) != signf(speed):
		return move_toward(speed, 0.0, BRAKE_DECEL * absf(drive) * delta)

	if drive > 0.0:
		# Engine pull fades with the square of speed: strong through the low and
		# mid range, tapering to nothing at MAX_SPEED.
		var speed_fraction := clampf(speed / MAX_SPEED, 0.0, 1.0)
		var accel := ENGINE_ACCEL * (1.0 - speed_fraction * speed_fraction)
		return minf(speed + accel * drive * delta, MAX_SPEED)

	return move_toward(speed, -MAX_REVERSE_SPEED, REVERSE_ACCEL * -drive * delta)


## Returns the yaw rate [rad/s] for a steering amount (-1..1) at a given speed.
func _compute_yaw_rate(steer_amount: float, speed: float) -> float:
	var abs_speed := absf(speed)
	# Speed-sensitive falloff: less yaw available the faster the car goes.
	var available := MAX_YAW_RATE / (1.0 + abs_speed / STEER_FALLOFF_SPEED)
	# Turning circle limit: no yaw at standstill, ramps in with speed.
	available = minf(available, abs_speed / MIN_TURN_RADIUS)
	# In reverse the same steering lock swings the nose the other way.
	return steer_amount * available * signf(speed)


## Cosmetic motion: wheel spin, front wheel steering and body roll / pitch.
func _update_visuals(longitudinal_accel: float, delta: float) -> void:
	var spin_speed := clampf(forward_speed / WHEEL_RADIUS, -MAX_WHEEL_SPIN, MAX_WHEEL_SPIN)
	for spinner in _wheel_spinners:
		# Rolling towards -Z is a negative rotation about +X.
		spinner.rotate_x(-spin_speed * delta)

	for wheel in _front_wheels:
		wheel.rotation.y = steer * MAX_WHEEL_STEER_ANGLE

	# Weight transfer: the body leans out of the corner, squats under power and
	# dives under braking.
	var lateral_accel := forward_speed * yaw_rate
	var target_roll := clampf(-lateral_accel * BODY_ROLL_PER_ACCEL, -MAX_BODY_TILT, MAX_BODY_TILT)
	var target_pitch := clampf(longitudinal_accel * BODY_PITCH_PER_ACCEL, -MAX_BODY_TILT, MAX_BODY_TILT)
	var blend := 1.0 - exp(-BODY_TILT_RESPONSE * delta)
	_body.rotation.z = lerpf(_body.rotation.z, target_roll, blend)
	_body.rotation.x = lerpf(_body.rotation.x, target_pitch, blend)
