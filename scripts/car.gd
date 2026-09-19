class_name ArcadeCar
extends CharacterBody3D
## Custom arcade vehicle controller (no VehicleBody3D / VehicleWheel3D).
##
## Model in one paragraph: every physics tick the car's horizontal velocity is
## split into a FORWARD component (along the nose) and a LATERAL component
## (sideways slip). Throttle/brake only ever change the forward component.
## Steering only ever rotates the body. Because the velocity vector does not
## rotate with the body, turning creates lateral slip, and the tyres scrub it
## away. Grip is split over two axles: the slip at each axle is the car's slip
## plus the sideways swing of that end of the car, and FRONT_LATERAL_GRIP /
## REAR_LATERAL_GRIP decide how quickly each axle scrubs its own slip. When the
## rear lets go (handbrake), the unscrubbed rear slip swings the tail out and
## adds extra yaw on top of the steering (slide_yaw_rate). With equal grip on
## both axles the car simply scrubs slip away and never slides on its own.
## Tyres saturate (TYRE_SLIDE_DECEL), so a car thrown sideways keeps its
## momentum, and the stability assist fades at big slip angles
## (SPIN_COMMIT_ANGLE), so a committed handbrake flick becomes a 180 or a 360.
##
## Drivetrain: throttle drives the rear wheels through a torque curve, a
## 5-speed gearbox and a final drive; the resulting force is capped by what the
## rear tyres can transmit. Engine RPM follows the rear wheels in gear.
##
## Weight: the axle loads start from the car's static weight distribution and
## shift forward under braking / rearward under acceleration. Each axle's
## lateral grip scales with its load, and drive force spent at the rear leaves
## less rear grip for cornering (power oversteer).
##
## Conventions: the car's nose points along local -Z, +X is the car's right,
## positive yaw (rotation about +Y) is a LEFT turn. The car is assumed to drive
## on level ground (true for the Phase 0 test pad).

# =============================================================================
#  DRIVING FEEL TUNING
#  The one place to tweak how the car feels. Speeds are m/s, accelerations are
#  m/s^2, angles are radians, rates are per second. (1 m/s = 3.6 km/h.)
# =============================================================================

# -----------------------------------------------------------------------------
#  CAR: 1997 Boxster 986 (placeholder tuning)
#  Everything that makes this car *this* car. Rounded public specs of the
#  2.5 L 986, bent where the placeholder model needs it. The next car (911)
#  gets its own section like this one.
# -----------------------------------------------------------------------------

# --- Mass and weight distribution --------------------------------------------

## Mass with a driver on board [kg]. 986 kerb weight ~1250 kg.
const CAR_MASS := 1300.0

## Share of the car's weight on the rear axle at rest (0..1). The Boxster's
## flat-six sits behind the seats (mid engine), putting ~62 % on the rear.
## The front axle carries the rest.
const REAR_WEIGHT_FRACTION := 0.62

## Height of the centre of mass above the road [m]. Higher = more weight moves
## between the axles under braking and acceleration.
const CG_HEIGHT := 0.48

## Distance from the car's centre to each axle [m]; half the wheelbase. Must
## match the wheel positions in car.tscn. Longer = the tail swings more lazily
## and less weight moves between the axles. (Real 986: 2.415 m wheelbase.)
const AXLE_DISTANCE := 1.3

# --- Engine ------------------------------------------------------------------

## Torque curve at full throttle: Vector2(rpm, torque [Nm]) anchor points,
## linearly interpolated, flat below the first point. 245 Nm peak at 4500 rpm,
## ~150 kW peak power at 6000 rpm.
const TORQUE_CURVE: Array[Vector2] = [
	Vector2(1000.0, 160.0),
	Vector2(2000.0, 200.0),
	Vector2(3000.0, 225.0),
	Vector2(4500.0, 245.0),
	Vector2(6000.0, 238.0),
	Vector2(7200.0, 180.0),
]

## Engine speed with no load [rpm]. The tach never reads lower while running.
const IDLE_RPM := 900.0

## Rev limiter [rpm]. The engine makes no torque at or above this.
const REDLINE_RPM := 7200.0

## Pulling away, the clutch slips so the engine sits at least this high [rpm]
## until the wheels catch up. Stops the car from bogging at walking pace.
const LAUNCH_RPM := 2000.0

## Engine braking with the throttle closed in gear [Nm per rpm above idle].
## 0.01 gives ~60 Nm at 7000 rpm: a gentle tug in top gear, a firm one in 1st.
const ENGINE_BRAKE_TORQUE_PER_RPM := 0.01

# --- Gearbox -----------------------------------------------------------------

## Gear ratios; index 0 is neutral, 1..5 the forward gears (986 5-speed).
const GEAR_RATIOS: Array[float] = [0.0, 3.82, 2.20, 1.52, 1.22, 0.97]

## Final drive (differential) ratio.
const FINAL_DRIVE := 3.89

## Reverse gear ratio. Only drives the tach; reversing itself stays simple
## (REVERSE_ACCEL / MAX_REVERSE_SPEED).
const REVERSE_RATIO := 3.55

## Share of engine torque that reaches the wheels (0..1); the rest is lost in
## the gearbox and differential.
const DRIVETRAIN_EFFICIENCY := 0.88

## Rolling radius of the tyres [m]; must match the wheel mesh. Turns wheel
## torque into force and wheel speed into engine RPM.
const WHEEL_RADIUS := 0.34

# --- Tyres and aero ----------------------------------------------------------

## Tyre friction coefficient: the rear tyres can push with at most this times
## the rear axle's load (1997 road tyres, ~0.95). Full throttle in 1st from
## ~3500 rpm hits this limit; 2nd and up stay under it.
const TYRE_MU := 0.95

## Front axle lateral grip at the static weight distribution: how quickly
## sideways slip at the front wheels is scrubbed off [1/s]. Each second that
## slip decays by a factor of e^-grip. ~10+ feels glued to the road, ~6 is
## grippy with a playful slide, ~2-3 is a loose drift car. Scrubbed slip is
## lost energy, so hard cornering also bleeds a little speed. Scaled at run
## time by the axle's load (see LOAD_GRIP_EXPONENT).
const FRONT_LATERAL_GRIP := 6.0

## Rear axle lateral grip at the static weight distribution [1/s], same scale
## as FRONT_LATERAL_GRIP. A little below the front lets the tail step out a
## touch in hard corners; above the front makes the car more planted. Equal
## grip = neutral. Scaled by load and by drive force (see MIN_COMBINED_GRIP).
const REAR_LATERAL_GRIP := 5.6

## Aerodynamic drag, 0.5 * air density * Cd * frontal area [kg/m]. Drag force
## is this times speed squared. Balances full power in 5th at ~65 m/s
## (~235 km/h), just under the rev limiter.
const AERO_DRAG := 0.40

## Nominal top speed [m/s], ~237 km/h. Not a hard cap: the real top speed
## comes out of AERO_DRAG vs engine power (a touch below this). Used to scale
## camera effects (speed_ratio).
const MAX_SPEED := 66.0

# -----------------------------------------------------------------------------
#  GENERAL (shared by every car)
# -----------------------------------------------------------------------------

# --- Longitudinal: brakes, reverse, rolling resistance -----------------------

## Deceleration while braking, i.e. pressing the key that opposes the current
## direction of travel [m/s^2]. 1 g is about 9.8; arcade brakes are stronger.
const BRAKE_DECEL := 26.0

## Rolling resistance [m/s^2], always on while the car rolls. With engine
## braking and aero drag it makes up the coast-down.
const COAST_DECEL := 0.15

## Acceleration in reverse gear [m/s^2].
const REVERSE_ACCEL := 6.0

## Top speed in reverse [m/s]. 12 m/s is about 43 km/h.
const MAX_REVERSE_SPEED := 12.0

## Below this speed [m/s] the car counts as stopped: holding brake engages
## reverse and holding accelerate engages forward drive, instead of braking.
const STANDSTILL_SPEED := 0.5

# --- Gear shifting -----------------------------------------------------------

## Time a gear change takes [s]. The clutch is open meanwhile: no drive
## torque and no engine braking.
const SHIFT_TIME := 0.2

## Automatic mode shifts up at this engine speed under throttle [rpm].
const UPSHIFT_RPM := 6800.0

## Automatic mode shifts down when the engine drops below this [rpm]. Every
## upshift from UPSHIFT_RPM lands well above it (lowest: ~3900 rpm into 2nd),
## so the box never hunts between two gears.
const DOWNSHIFT_RPM := 2800.0

## Automatic mode only shifts down if the lower gear lands at least this far
## below UPSHIFT_RPM [rpm], so a downshift never triggers an instant upshift.
const DOWNSHIFT_MARGIN_RPM := 1000.0

## Automatic mode waits at least this long between two shifts [s].
const AUTO_SHIFT_HOLD := 0.5

## How quickly the engine speed follows its target [1/s]. Sets how fast the
## revs drop across an upshift and flare on a launch.
const RPM_RESPONSE := 20.0

# --- Weight transfer ---------------------------------------------------------

## How strongly axle load changes axle grip: grip multiplier is
## (load / static load) ^ exponent. Below 1 = tyres gain grip slower than
## load, as real tyres do, so moving weight onto one axle costs the other one
## more than it gains: the balance shift is felt. 0 = no effect.
const LOAD_GRIP_EXPONENT := 0.7

## Largest share of the car's weight that can move between the axles (0..1).
## Caps the transfer from the arcade brakes, which pull harder than tyres
## really could.
const MAX_LOAD_TRANSFER := 0.18

## How quickly the load follows acceleration changes [1/s]: the suspension
## taking a moment to pitch.
const LOAD_TRANSFER_RESPONSE := 8.0

## Rear lateral grip left over when the rear tyres spend all their traction on
## drive force (0..1). In between it follows the friction circle,
## sqrt(1 - traction use^2). Lower = snappier power oversteer.
const MIN_COMBINED_GRIP := 0.4

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

# --- Slides ------------------------------------------------------------------

## Arcade stability assist: how quickly any extra tail-out yaw dies away on its
## own [1/s]. Keeps a handbrake slide controllable instead of an instant spin.
## Lower = wilder slides that spin more easily, higher = tamer.
## Was 12.0: the tail could never build enough swing to reach a spin.
const SLIDE_YAW_DAMPING := 8.0

## Stability assist left once the car is committed to a spin [1/s]. Low, so
## the rotation carries on under its own momentum through a 180 or a 360.
const SPIN_YAW_DAMPING := 0.3

## Slip angle (nose vs direction of travel) where the stability assist starts
## to fade [rad]. Below it slides stay tame and catchable.
const SPIN_COMMIT_ANGLE := 0.45

## Slip angle from which the assist is down to SPIN_YAW_DAMPING [rad]. Also
## covers travelling backwards mid-spin. Coming back under it at the end of a
## spin, the assist returns and settles the car.
const SPIN_FREE_ANGLE := 1.05

## Below this speed [m/s] the slip angle means nothing and the full assist
## applies.
const SPIN_MIN_SPEED := 2.0

## Tyre saturation: the most sideways deceleration one axle can deliver once it
## is properly sliding [m/s^2], at static load. Below the limit the axle scrubs
## slip exponentially (the *_LATERAL_GRIP rates); past it the tyres just drag at
## this constant rate, so a car thrown sideways keeps moving and can spin
## instead of stopping dead. Sits above the hardest steady cornering the
## steering can ask for (see STEER_FALLOFF_SPEED), so grip driving never
## touches it. Scaled like the grip rates (load, drive force, handbrake).
const TYRE_SLIDE_DECEL := 16.0

# --- Handbrake ---------------------------------------------------------------

## Rear grip multiplier while the handbrake is fully on (0..1). 0.15 leaves the
## rear with a seventh of its grip, so steering into a corner kicks the tail out.
## Was 0.2: a looser locked rear swings round harder, enough for a 360 from
## ~110 km/h.
const HANDBRAKE_REAR_GRIP_FACTOR := 0.15

## Extra deceleration while the handbrake is held [m/s^2], on top of coasting.
## Much gentler than BRAKE_DECEL: it is for sliding, not for stopping.
const HANDBRAKE_DECEL := 5.0

## How fast the rear grip comes back after releasing the handbrake [1/s].
## 2.5 means full grip again after 0.4 s, so the tail catches smoothly instead
## of snapping straight. The handbrake itself bites instantly.
const HANDBRAKE_RECOVERY_RATE := 2.5

# --- Visual only (no effect on handling) -------------------------------------

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

## Engine speed from which the HUD tach turns to its warning colour [rpm].
const SHIFT_LIGHT_RPM := 6500.0

# =============================================================================
#  STATE
# =============================================================================

## Signed speed along the nose [m/s]. Negative while reversing.
var forward_speed := 0.0

## Signed sideways slip speed [m/s]. Positive = sliding towards the car's right.
var lateral_speed := 0.0

## Current yaw rate [rad/s]. Positive = turning left. Steering yaw plus
## slide_yaw_rate.
var yaw_rate := 0.0

## Extra yaw from the tail sliding out [rad/s], on top of what the steering
## asks for. Near zero in normal driving, large during a handbrake slide.
var slide_yaw_rate := 0.0

## Smoothed steering input, -1 (full right) .. +1 (full left).
var steer := 0.0

## Selected gear: 0 = neutral, 1..5 forward. Reversing is handled separately
## and does not change this.
var gear := 1

## True = the gearbox shifts by itself. The shift keys switch to manual.
var automatic := true

## Engine speed [rpm].
var engine_rpm := IDLE_RPM

## Share of the car's weight on each axle right now (0..1, sums to 1).
var front_load_fraction := 1.0 - REAR_WEIGHT_FRACTION
var rear_load_fraction := REAR_WEIGHT_FRACTION

## How much of the rear tyres' traction the drive force uses, 0..1.
var rear_traction_use := 0.0

## Speedometer value [km/h], always positive.
var speed_kmh: float:
	get:
		return absf(forward_speed) * 3.6

## Forward speed as a fraction of MAX_SPEED, 0..1. Handy for camera/HUD effects.
var speed_ratio: float:
	get:
		return clampf(absf(forward_speed) / MAX_SPEED, 0.0, 1.0)

## True while a gear change is in progress (clutch open).
var is_shifting: bool:
	get:
		return _shift_timer > 0.0

## How far the handbrake is on, 0..1. Jumps to 1 when pulled, eases back to 0
## at HANDBRAKE_RECOVERY_RATE when released.
var _handbrake_amount := 0.0

## Time left in the current gear change [s].
var _shift_timer := 0.0

## Time since the last gear change [s]; the automatic waits AUTO_SHIFT_HOLD.
var _since_shift := AUTO_SHIFT_HOLD

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
	if Input.is_action_just_pressed("shift_up"):
		automatic = false
		shift_to(gear + 1)
	if Input.is_action_just_pressed("shift_down"):
		automatic = false
		shift_to(gear - 1)
	if Input.is_action_just_pressed("toggle_gearbox"):
		automatic = not automatic

	# +1 = drive forward, -1 = brake / reverse. Both keys held cancel out.
	var drive_input := Input.get_action_strength("accelerate") - Input.get_action_strength("brake")
	# +1 = left, -1 = right (matches the sign of yaw).
	var steer_input := Input.get_axis("steer_right", "steer_left")
	var handbrake_held := Input.is_action_pressed("handbrake")

	# 1. Split the current horizontal velocity into the car's own frame. Reading
	#    it back from `velocity` means collisions are respected automatically.
	var forward_dir := -global_basis.z
	var right_dir := global_basis.x
	forward_speed = velocity.dot(forward_dir)
	lateral_speed = velocity.dot(right_dir)
	var vertical_speed := velocity.y

	# 2. Longitudinal: engine through the gearbox, brakes, reverse, coasting.
	var previous_forward_speed := forward_speed
	forward_speed = _update_forward_speed(forward_speed, drive_input, delta)
	if handbrake_held:
		forward_speed = move_toward(forward_speed, 0.0, HANDBRAKE_DECEL * delta)
	var longitudinal_accel := (forward_speed - previous_forward_speed) / delta

	# 3. Weight transfer: acceleration pitches load onto the rear axle, braking
	#    onto the front, eased in at the suspension's pace.
	var target_transfer := clampf(
		longitudinal_accel * CG_HEIGHT / (_gravity * 2.0 * AXLE_DISTANCE),
		-MAX_LOAD_TRANSFER, MAX_LOAD_TRANSFER
	)
	var current_transfer := rear_load_fraction - REAR_WEIGHT_FRACTION
	var transfer := lerpf(current_transfer, target_transfer, 1.0 - exp(-LOAD_TRANSFER_RESPONSE * delta))
	rear_load_fraction = REAR_WEIGHT_FRACTION + transfer
	front_load_fraction = 1.0 - rear_load_fraction

	# 4. Lateral: each axle scrubs off its own sideways slip. The front axle
	#    sits AXLE_DISTANCE ahead of the centre, the rear the same behind, so a
	#    positive (left) slide yaw moves the nose left and the tail right. The
	#    corrected axle slips then give back the car's slip and slide yaw. Grip
	#    scales with axle load; drive force eats into the rear's share.
	if handbrake_held:
		_handbrake_amount = 1.0
	else:
		_handbrake_amount = move_toward(_handbrake_amount, 0.0, HANDBRAKE_RECOVERY_RATE * delta)
	var front_grip := FRONT_LATERAL_GRIP * _load_grip(front_load_fraction, 1.0 - REAR_WEIGHT_FRACTION)
	var combined := maxf(sqrt(maxf(1.0 - rear_traction_use * rear_traction_use, 0.0)), MIN_COMBINED_GRIP)
	var rear_grip := REAR_LATERAL_GRIP * _load_grip(rear_load_fraction, REAR_WEIGHT_FRACTION) * combined
	rear_grip *= lerpf(1.0, HANDBRAKE_REAR_GRIP_FACTOR, _handbrake_amount)
	var front_slip := lateral_speed - slide_yaw_rate * AXLE_DISTANCE
	var rear_slip := lateral_speed + slide_yaw_rate * AXLE_DISTANCE
	front_slip = _scrub_slip(front_slip, front_grip, FRONT_LATERAL_GRIP, delta)
	rear_slip = _scrub_slip(rear_slip, rear_grip, REAR_LATERAL_GRIP, delta)
	lateral_speed = (front_slip + rear_slip) * 0.5
	slide_yaw_rate = (rear_slip - front_slip) / (2.0 * AXLE_DISTANCE)
	slide_yaw_rate *= exp(-_slide_yaw_damping() * delta)

	# 5. Steering: turn the body. The velocity is rebuilt from the directions of
	#    *before* the turn, so the nose rotates away from the direction of travel
	#    and the difference shows up as lateral slip on the next tick.
	steer = move_toward(steer, steer_input, STEER_RESPONSE * delta)
	yaw_rate = _compute_yaw_rate(steer, forward_speed) + slide_yaw_rate

	if not is_on_floor():
		vertical_speed -= _gravity * delta
	velocity = forward_dir * forward_speed + right_dir * lateral_speed + Vector3.UP * vertical_speed

	rotate_y(yaw_rate * delta)
	move_and_slide()

	_update_visuals(longitudinal_accel, delta)


## Puts the car back where the scene placed it, at rest, in 1st, automatic.
func reset_to_spawn() -> void:
	reset_to(_spawn_transform)


## Where the scene placed the car. Missions offset their start points from it.
func get_spawn_transform() -> Transform3D:
	return _spawn_transform


## Puts the car at `target`, at rest, in 1st, automatic.
func reset_to(target: Transform3D) -> void:
	global_transform = target
	velocity = Vector3.ZERO
	forward_speed = 0.0
	lateral_speed = 0.0
	yaw_rate = 0.0
	slide_yaw_rate = 0.0
	steer = 0.0
	_handbrake_amount = 0.0
	gear = 1
	automatic = true
	engine_rpm = IDLE_RPM
	_shift_timer = 0.0
	_since_shift = AUTO_SHIFT_HOLD
	front_load_fraction = 1.0 - REAR_WEIGHT_FRACTION
	rear_load_fraction = REAR_WEIGHT_FRACTION
	rear_traction_use = 0.0
	_body.rotation = Vector3.ZERO
	reset_physics_interpolation()


## Starts a gear change to `new_gear` (0 = neutral). Refuses gears that do not
## exist and downshifts that would throw the engine past the rev limiter.
## Returns true if the shift happens.
func shift_to(new_gear: int) -> bool:
	if new_gear < 0 or new_gear >= GEAR_RATIOS.size() or new_gear == gear:
		return false
	if new_gear > 0 and new_gear < gear and wheel_rpm(new_gear) > REDLINE_RPM:
		return false
	gear = new_gear
	_shift_timer = SHIFT_TIME
	_since_shift = 0.0
	return true


## Engine speed [rpm] the rear wheels would turn the engine at in `in_gear`
## at the current speed (0 in neutral).
func wheel_rpm(in_gear: int) -> float:
	return absf(forward_speed) / WHEEL_RADIUS * GEAR_RATIOS[in_gear] * FINAL_DRIVE * 60.0 / TAU


## Road speed [m/s] at which the engine turns `rpm` in `in_gear`.
func speed_at_rpm(in_gear: int, rpm: float) -> float:
	return rpm / (60.0 / TAU) / (GEAR_RATIOS[in_gear] * FINAL_DRIVE) * WHEEL_RADIUS


## Full-throttle engine torque [Nm] at `rpm`, from TORQUE_CURVE. Zero at and
## above the rev limiter.
static func engine_torque(rpm: float) -> float:
	if rpm >= REDLINE_RPM:
		return 0.0
	if rpm <= TORQUE_CURVE[0].x:
		return TORQUE_CURVE[0].y
	for i in range(1, TORQUE_CURVE.size()):
		var hi := TORQUE_CURVE[i]
		if rpm <= hi.x:
			var lo := TORQUE_CURVE[i - 1]
			return lerpf(lo.y, hi.y, (rpm - lo.x) / (hi.x - lo.x))
	return TORQUE_CURVE[-1].y


## Returns the new forward speed after one tick of engine / brake / coasting,
## and updates the gearbox, engine RPM and rear traction use on the way.
## `drive` is +1 for the accelerate key and -1 for the brake key.
func _update_forward_speed(speed: float, drive: float, delta: float) -> float:
	# Pressing against the direction of travel brakes. Once the car has come to
	# a stop, the same key takes over as drive in the other direction, so
	# holding brake flows from braking straight into reverse.
	var is_moving := absf(speed) > STANDSTILL_SPEED
	var braking := is_moving and not is_zero_approx(drive) and signf(drive) != signf(speed)
	var reversing := speed < -STANDSTILL_SPEED or (drive < 0.0 and not braking)
	var throttle := drive if drive > 0.0 and not braking else 0.0

	_update_gearbox(speed, throttle, reversing, delta)

	# Engine force at the rear wheels: drive under throttle, engine braking with
	# the throttle closed. Both need the clutch in and a gear engaged.
	var drive_force := 0.0
	if gear > 0 and not is_shifting and not reversing:
		var ratio: float = GEAR_RATIOS[gear] * FINAL_DRIVE
		if throttle > 0.0:
			drive_force = engine_torque(engine_rpm) * throttle * ratio * DRIVETRAIN_EFFICIENCY / WHEEL_RADIUS
		elif speed > STANDSTILL_SPEED:
			drive_force = -ENGINE_BRAKE_TORQUE_PER_RPM * maxf(engine_rpm - IDLE_RPM, 0.0) * ratio / WHEEL_RADIUS
	# Traction limit: the rear tyres cannot push harder than their load allows.
	var traction_limit := TYRE_MU * CAR_MASS * _gravity * rear_load_fraction
	drive_force = clampf(drive_force, -traction_limit, traction_limit)
	rear_traction_use = absf(drive_force) / traction_limit

	if braking:
		speed = move_toward(speed, 0.0, BRAKE_DECEL * absf(drive) * delta)
	elif drive < 0.0:
		speed = move_toward(speed, -MAX_REVERSE_SPEED, REVERSE_ACCEL * -drive * delta)

	if drive_force >= 0.0:
		speed += drive_force / CAR_MASS * delta
	else:
		# Engine braking slows the car but never pushes it backwards.
		speed = move_toward(speed, 0.0, -drive_force / CAR_MASS * delta)

	# Rolling resistance and aero drag always oppose the motion.
	var resistance := COAST_DECEL + AERO_DRAG * speed * speed / CAR_MASS
	return move_toward(speed, 0.0, resistance * delta)


## Automatic shifting and engine speed for this tick.
func _update_gearbox(speed: float, throttle: float, reversing: bool, delta: float) -> void:
	_shift_timer = maxf(_shift_timer - delta, 0.0)
	_since_shift += delta

	if automatic and not is_shifting:
		if absf(speed) <= STANDSTILL_SPEED or reversing:
			# Stopped or backing up: be ready to pull away in 1st.
			if gear != 1:
				gear = 1
				_since_shift = 0.0
		elif _since_shift >= AUTO_SHIFT_HOLD:
			var lower := gear - 1
			if throttle > 0.0 and gear < GEAR_RATIOS.size() - 1 and wheel_rpm(gear) >= UPSHIFT_RPM:
				shift_to(gear + 1)
			elif (
				lower >= 1
				and wheel_rpm(gear) < DOWNSHIFT_RPM
				and wheel_rpm(lower) < UPSHIFT_RPM - DOWNSHIFT_MARGIN_RPM
			):
				shift_to(lower)

	# Where the engine wants to be: tied to the wheels in gear (with a slipping
	# clutch when pulling away), free-revving in neutral.
	var target: float
	if reversing:
		target = absf(speed) / WHEEL_RADIUS * REVERSE_RATIO * FINAL_DRIVE * 60.0 / TAU
	elif gear == 0:
		target = lerpf(IDLE_RPM, REDLINE_RPM, throttle)
	else:
		target = wheel_rpm(gear)
		if throttle > 0.0:
			target = maxf(target, LAUNCH_RPM)
	target = maxf(target, IDLE_RPM)
	engine_rpm = lerpf(engine_rpm, target, 1.0 - exp(-RPM_RESPONSE * delta))


## Grip multiplier for an axle carrying `load` of the car's weight when it
## carries `static_load` at rest: 1.0 at rest, sub-linear in load.
func _load_grip(load: float, static_load: float) -> float:
	return pow(maxf(load, 0.0) / static_load, LOAD_GRIP_EXPONENT)


## Stability assist strength right now [1/s]: SLIDE_YAW_DAMPING while the car
## points roughly where it is going, fading to SPIN_YAW_DAMPING as the slip
## angle (nose vs direction of travel, 0..PI) grows past SPIN_COMMIT_ANGLE.
func _slide_yaw_damping() -> float:
	if Vector2(forward_speed, lateral_speed).length() < SPIN_MIN_SPEED:
		return SLIDE_YAW_DAMPING
	var slip_angle := absf(atan2(lateral_speed, forward_speed))
	var spin := smoothstep(SPIN_COMMIT_ANGLE, SPIN_FREE_ANGLE, slip_angle)
	return lerpf(SLIDE_YAW_DAMPING, SPIN_YAW_DAMPING, spin)


## One tick of an axle scrubbing its sideways slip [m/s] at `grip` [1/s]. The
## tyres saturate: the slip never drops faster than TYRE_SLIDE_DECEL, scaled by
## how much of the axle's `static_grip` is left (load, drive force, handbrake).
func _scrub_slip(slip: float, grip: float, static_grip: float, delta: float) -> float:
	var max_scrub := TYRE_SLIDE_DECEL * grip / static_grip * delta
	return move_toward(slip, slip * exp(-grip * delta), max_scrub)


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
