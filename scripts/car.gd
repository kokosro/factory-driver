class_name ArcadeCar
extends CharacterBody3D
## Custom arcade vehicle controller (no VehicleBody3D / VehicleWheel3D).
##
## Model in one paragraph: a two-axle ("bicycle") model driven by tyre forces.
## Every physics tick the car's horizontal velocity is split into a FORWARD
## component (along the nose) and a LATERAL component (sideways slip), and the
## car carries a yaw rate. Throttle and brake change the forward component.
## Steering turns the front wheels; nothing turns the body directly. Each axle
## looks at its own slip angle (the angle between where its wheels point and
## where that end of the car is actually moving) and answers with a sideways
## force from a tyre curve: rising to TYRE_MU times the axle's load at
## *_PEAK_SLIP_ANGLE, then easing off to TYRE_SLIDE_GRIP of that as the tyre
## slides. The two forces push the car's mass sideways and, on their lever
## arms about the centre of mass, wind its yaw inertia up and down
## (YAW_GYRATION_RADIUS). Brake or drive force uses up part of a tyre's grip
## and leaves less for cornering (friction ellipse). The handbrake locks the
## rear wheels: a locked tyre just drags against its direction of travel, with
## next to no sideways hold at small slip angles, so the tail comes round. An
## arcade stability assist damps yaw the steering did not ask for; it fades at
## big slip angles (SPIN_COMMIT_ANGLE), so a committed flick becomes a 180 or
## a 360.
##
## Drivetrain: throttle drives the rear wheels through a torque curve, a
## 5-speed gearbox and a final drive; the resulting force is capped by what the
## rear tyres can transmit. Engine RPM follows the rear wheels in gear.
##
## Weight: the axle loads start from the car's static weight distribution and
## shift forward under braking / rearward under acceleration. Each axle's
## grip scales with its load (braking sharpens turn-in, power dulls it), and
## drive force spent at the rear leaves less rear grip for cornering (power
## oversteer).
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

## How far the centre of mass sits behind the middle of the wheelbase [m]:
## follows from the weight distribution. The front tyres work on the longer
## lever arm, the heavier-loaded rears on the shorter, so with both axles
## sliding flat out the car neither straightens nor tightens by itself.
const CG_OFFSET := (REAR_WEIGHT_FRACTION - 0.5) * 2.0 * AXLE_DISTANCE

## Radius of gyration about the vertical axis [m]: yaw inertia is
## CAR_MASS * radius^2 (~2000 kg m^2 here). How much the mass resists being
## turned: the front tyres have to wind the car up into a corner and back out
## of it. A mid-engined car keeps its mass near the middle (~1.2); a 911 with
## the engine slung out behind the rear axle gets more. Higher = lazier
## turn-in that carries on longer, lower = darty.
const YAW_GYRATION_RADIUS := 1.25

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

## Slip angle at which the front tyres make their peak sideways force [rad]
## (0.11 = 6.3 degrees). Up to the peak the force rises along a smooth curve
## (1.5x the straight-line slope at first, levelling off into the peak); past
## it the tyre slides (see TYRE_SLIDE_GRIP). Peak force is TYRE_MU times the
## axle load for both axles, so a smaller peak angle simply means a stiffer,
## sharper tyre: cornering stiffness is 1.5 * peak force / peak angle (front
## ~63 kN/rad, rear ~113 kN/rad at rest). Stiffer also settles quicker: at
## 170 km/h, 0.125 left the car still drifting straight 1.5 s after a jab.
## Replaces FRONT_LATERAL_GRIP 6.0 / REAR_LATERAL_GRIP 5.6, hand-set rates at
## which each axle's slip decayed [1/s], with no force and no mass in them.
const FRONT_PEAK_SLIP_ANGLE := 0.11

## The same for the rear tyres [rad] (0.10 = 5.7 degrees): the Boxster's wide
## 255 rears are stiffer than its 205 fronts. The balance of the car is the
## difference between the two: understeer gradient =
## (front - rear peak angle) / (1.5 * TYRE_MU * g), here ~0.4 degrees per g.
## Front above rear = understeer: stable at any speed, and at the limit the
## nose pushes wide before the tail lets go. Equal = neutral. Rear above front
## = oversteer, with a speed above which the car will not run straight. More
## understeer than this (0.03 apart) and the nose visibly swings back past
## straight when the steering is let go at speed.
const REAR_PEAK_SLIP_ANGLE := 0.10

## Sideways force a fully sliding tyre still makes, as a share of its peak
## (0..1): rubber sliding over the road grips less than rubber keying into it.
## The curve eases from the peak down to this over TYRE_SLIDE_ONSET. Also the
## grip of a locked (handbraked) wheel. 1.0 = no drop, the limit is a plateau;
## lower = the car lets go more suddenly and a slide scrubs less speed.
const TYRE_SLIDE_GRIP := 0.85

## How far past the peak the tyre is ~two thirds of the way down to
## TYRE_SLIDE_GRIP, in peak slip angles. Higher = a wider, more forgiving top.
const TYRE_SLIDE_ONSET := 2.0

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

## How much of the tyres' grip a full brake application uses (0..1+). The
## brakes themselves are stronger than the tyres, so the tyres set the limit:
## 1.0 = a threshold-braking stop right at the grip limit, below 1 = a driver
## who leaves a margin, above 1 = stickier than the tyres really are (arcade).
const BRAKE_DECEL_G := 1.0

## Deceleration while braking [m/s^2]: what the tyres can hold, ~9.3 (0.95 g).
## Was a flat 26.0 (2.7 g), which no 1300 kg road car can do: 72 km/h -> 0 took
## ~8 m. Now it takes ~22 m, 90 km/h ~34 m, 125 km/h ~66 m. Brake earlier.
const BRAKE_DECEL := BRAKE_DECEL_G * TYRE_MU * 9.8

## Rolling resistance [m/s^2], always on while the car rolls. With engine
## braking and aero drag it makes up the coast-down.
const COAST_DECEL := 0.15

## Acceleration in reverse gear [m/s^2].
const REVERSE_ACCEL := 6.0

## Top speed in reverse [m/s]. 12 m/s is about 43 km/h.
const MAX_REVERSE_SPEED := 12.0

## Below this speed [m/s] the car counts as stopped. The brake only ever slows
## the car to a stop and holds it there; the direction changes on a FRESH key
## press at a standstill: brake pressed anew engages reverse, accelerate
## pressed anew engages forward again (see reverse_engaged). A key that is
## still held from the braking never changes direction.
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

## How strongly axle load changes axle grip: grip is TYRE_MU * static load *
## (load / static load) ^ exponent. Below 1 = tyres gain grip slower than
## load, as real tyres do, so moving weight onto one axle costs the other one
## more than it gains: the balance shift is felt. 0 = no effect.
const LOAD_GRIP_EXPONENT := 0.7

## Largest share of the car's weight that can move between the axles (0..1).
## A safety net: tyre-limited braking and drive stay inside it.
const MAX_LOAD_TRANSFER := 0.18

## How quickly the load follows acceleration changes [1/s]: the suspension
## taking a moment to pitch.
const LOAD_TRANSFER_RESPONSE := 8.0

## Friction ellipse: a tyre using the share `use` (0..1) of its grip along the
## car, for braking or drive, has sqrt(1 - use^2) of its sideways grip left.
## Braking while turning costs turn-in; trailing off the brake gives it back;
## power at the rear loosens the tail. This is the floor: the sideways grip
## left at full use (0..1), where a bare ellipse leaves none. It stands for
## the ABS (and a driver's right foot) giving up a little of the stop to keep
## the car steerable, which on/off keys cannot do themselves. Lower = braking
## and turning exclude each other more, snappier power oversteer.
const MIN_COMBINED_GRIP := 0.4

# --- Steering ----------------------------------------------------------------

## Upper bound on the yaw rate the steering aims for [rad/s], about 115 degrees
## per second. A safety net: with this car's turning circle and tyres the aim
## (see _steering_yaw_limit) peaks at ~1.4 rad/s around 25 km/h.
## Was the whole steering feel: MAX_YAW_RATE / (1 + speed / 9), a kinematic
## curve with no mass in it that asked for up to 1.8 g of cornering. Now the
## front wheels are steered to the angle that aims for the tightest corner the
## tyres can hold (TYRE_MU * g / speed, ~0.95 g), and the tyre forces have to
## wind the yaw inertia up to it (YAW_GYRATION_RADIUS).
const MAX_YAW_RATE := 2.0

## How far past their peak slip angle full steering lock pushes the front
## tyres, in peak slip angles. At speed, full lock is the angle of the
## tightest corner the tyres can hold plus this much slip: 1.0 stops right on
## the peak, a little more makes sure the front tyres are used up (the car
## pushes wide at the limit rather than the driver never reaching it).
const STEER_SLIP_REACH := 1.2

## Tightest turning circle radius [m]: full lock at low speed is the wheel
## angle that rolls round this circle (~27 degrees).
const MIN_TURN_RADIUS := 5.0

## How fast the steering input moves towards the pressed key, and back to
## centre on release [1/s]. 5.0 means centre to full lock in 0.2 s. Smooths out
## the on/off nature of keyboard steering.
const STEER_RESPONSE := 5.0

# --- Slides ------------------------------------------------------------------

## Arcade stability assist: how quickly yaw the steering did not ask for dies
## away [1/s]. "Asked for" is anything from zero up to the yaw rate of the
## corner the steering aims at, so the assist never helps the car turn in (the
## tyres have to do that); it only checks the tail swinging further, and the
## car rotating on after the steering has come off. Keeps a handbrake slide
## controllable instead of an instant spin.
## Lower = wilder slides that spin more easily, higher = tamer.
const SLIDE_YAW_DAMPING := 8.0

## Stability assist left once the car is committed to a spin [1/s]. Low, so
## the rotation carries on under its own momentum through a 180 or a 360.
const SPIN_YAW_DAMPING := 0.3

## Slip angle (nose vs direction of travel) from which steering further into a
## slide starts to count as yaw nobody asked for [rad]. Grip driving stays
## under ~0.1 even at the limit, so this only touches real slides.
const SLIDE_CATCH_ANGLE := 0.2

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

# --- Handbrake ---------------------------------------------------------------

# The handbrake locks the rear wheels. A locked tyre cannot roll, so it drags
# against whatever way it is moving with TYRE_SLIDE_GRIP of its grip: rolling
# straight that is all braking (~0.45 g on this car's rear axle) and hardly
# any sideways hold (a fourteenth of a rolling tyre's at small slip angles),
# so steering kicks the tail out; sideways it is all sideways drag.
# Replaces HANDBRAKE_REAR_GRIP_FACTOR 0.15 and HANDBRAKE_DECEL 5.0, which set
# the same two things by hand.

## How fast the rear wheels pick up rolling again after releasing the
## handbrake [1/s]. 2.5 means full grip again after 0.4 s, so the tail catches
## smoothly instead of snapping straight. The handbrake itself bites instantly.
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

## Signed sideways slip speed [m/s], at the middle of the wheelbase. Positive =
## sliding towards the car's right.
var lateral_speed := 0.0

## Current yaw rate [rad/s]. Positive = turning left. Wound up and down by the
## tyre forces against the yaw inertia.
var yaw_rate := 0.0

## Yaw the steering is not asking for [rad/s]: the part of yaw_rate outside
## zero .. the yaw rate of the corner the steering aims at. Near zero in
## normal driving, large during a handbrake slide. What the stability assist
## works on.
var slide_yaw_rate := 0.0

## Smoothed steering input, -1 (full right) .. +1 (full left).
var steer := 0.0

## Selected gear: 0 = neutral, 1..5 forward. Reversing is handled separately
## (reverse_engaged) and does not change this.
var gear := 1

## True while reverse is selected. The keys then swap roles: the brake key is
## the throttle (backwards) and the accelerate key is the brake. Engaged by a
## fresh press of the brake key at a standstill; left by a fresh press of the
## accelerate key at a standstill or while the car rolls nose-first (the way
## out of a J-turn: selecting drive while already rolling forwards is harmless,
## selecting reverse on the move is what a gearbox locks out).
var reverse_engaged := false

## True = the gearbox shifts by itself. The shift keys switch to manual.
var automatic := true

## Engine speed [rpm].
var engine_rpm := IDLE_RPM

## Share of the car's weight on each axle right now (0..1, sums to 1).
var front_load_fraction := 1.0 - REAR_WEIGHT_FRACTION
var rear_load_fraction := REAR_WEIGHT_FRACTION

## How much of the rear tyres' traction the drive force uses, 0..1.
var rear_traction_use := 0.0

## How much of every tyre's grip the brakes are using, 0..1.
var brake_grip_use := 0.0

## Slip angle of each axle's tyres [rad], for tuning and tests. Positive =
## the tyres slide towards their right.
var front_slip_angle := 0.0
var rear_slip_angle := 0.0

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

## Whether the accelerate / brake keys were down on the previous tick, to tell
## a fresh press from a held key.
var _accelerate_was_pressed := false
var _brake_was_pressed := false

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

	# +1 = accelerate key, -1 = brake key. Both keys held cancel out.
	var drive_input := Input.get_action_strength("accelerate") - Input.get_action_strength("brake")
	# +1 = left, -1 = right (matches the sign of yaw).
	var steer_input := Input.get_axis("steer_right", "steer_left")
	var handbrake_held := Input.is_action_pressed("handbrake")

	# 1. Split the current horizontal velocity into the car's own frame. Reading
	#    it back from `velocity` means collisions are respected automatically.
	#    `velocity` belongs to the car's origin, the middle of the wheelbase;
	#    the forces work on the centre of mass, CG_OFFSET behind it.
	var forward_dir := -global_basis.z
	var right_dir := global_basis.x
	forward_speed = velocity.dot(forward_dir)
	lateral_speed = velocity.dot(right_dir)
	var vertical_speed := velocity.y
	var cg_lateral_speed := lateral_speed + yaw_rate * CG_OFFSET
	_update_direction(forward_speed)
	if handbrake_held:
		_handbrake_amount = 1.0
	else:
		_handbrake_amount = move_toward(_handbrake_amount, 0.0, HANDBRAKE_RECOVERY_RATE * delta)

	# 2. Longitudinal: engine through the gearbox, brakes, reverse, coasting,
	#    and the drag of the locked rear wheels under the handbrake.
	var previous_forward_speed := forward_speed
	var rear_slip_speed := lateral_speed + yaw_rate * AXLE_DISTANCE
	forward_speed = _update_forward_speed(forward_speed, drive_input, delta)
	forward_speed = move_toward(forward_speed, 0.0, _handbrake_drag(forward_speed, rear_slip_speed) * delta)
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

	# 4. Tyres: each axle makes a sideways force from its slip angle. The front
	#    axle sits ahead of the centre of mass and its wheels are steered, so
	#    its slip is measured across the wheels, not across the car; the rear
	#    sits behind and points where the car points. A positive (left) yaw
	#    rate moves the nose left and the tail right.
	steer = move_toward(steer, steer_input, STEER_RESPONSE * delta)
	var front_arm := AXLE_DISTANCE + CG_OFFSET
	var rear_arm := AXLE_DISTANCE - CG_OFFSET
	var yaw_inertia := CAR_MASS * YAW_GYRATION_RADIUS * YAW_GYRATION_RADIUS
	var front_lateral := cg_lateral_speed - yaw_rate * front_arm
	var rear_lateral := cg_lateral_speed + yaw_rate * rear_arm
	var steer_angle := steer * _steering_lock(absf(forward_speed), atan2(front_lateral, absf(forward_speed)))
	var front_across := front_lateral * cos(steer_angle) + forward_speed * sin(steer_angle)
	var front_along := forward_speed * cos(steer_angle) - front_lateral * sin(steer_angle)
	front_slip_angle = atan2(front_across, absf(front_along))
	rear_slip_angle = atan2(rear_lateral, absf(forward_speed))

	var front_grip := _axle_grip(front_load_fraction, 1.0 - REAR_WEIGHT_FRACTION) * _combined_grip(brake_grip_use)
	var rear_grip := _axle_grip(rear_load_fraction, REAR_WEIGHT_FRACTION)
	var front_force := -front_grip * _tyre_curve(front_slip_angle / FRONT_PEAK_SLIP_ANGLE)
	var rear_rolling := -rear_grip * _combined_grip(maxf(brake_grip_use, rear_traction_use)) * _tyre_curve(rear_slip_angle / REAR_PEAK_SLIP_ANGLE)
	var rear_locked := -rear_grip * TYRE_SLIDE_GRIP * sin(rear_slip_angle)
	var rear_force := lerpf(rear_rolling, rear_locked, _handbrake_amount)
	# A tyre can stop its end of the car sliding, not throw it back the other
	# way: no more force than brings that axle's slip to zero this tick. At
	# walking pace this is what makes the car roll where its wheels point.
	front_force = _limit_to_stick(front_force, front_across, front_arm, yaw_inertia, delta)
	rear_force = _limit_to_stick(rear_force, rear_lateral, rear_arm, yaw_inertia, delta)

	# The forces push the mass sideways and turn the car about its centre of
	# mass. The steered front force also points a little backwards: cornering
	# drag.
	forward_speed += front_force * sin(steer_angle) / CAR_MASS * delta
	cg_lateral_speed += (front_force * cos(steer_angle) + rear_force) / CAR_MASS * delta
	yaw_rate += (rear_force * rear_arm - front_force * cos(steer_angle) * front_arm) / yaw_inertia * delta

	# 5. Stability assist: yaw beyond what the steering aims for dies away.
	var aim := _compute_yaw_rate(steer, forward_speed) * _slide_feed(forward_speed, cg_lateral_speed, steer)
	var asked := clampf(yaw_rate, minf(aim, 0.0), maxf(aim, 0.0))
	slide_yaw_rate = (yaw_rate - asked) * exp(-_slide_yaw_damping(forward_speed, cg_lateral_speed) * delta)
	yaw_rate = asked + slide_yaw_rate

	# 6. Move. The velocity is rebuilt from the directions of *before* the turn:
	#    the mass carries straight on while the body rotates, and the
	#    difference shows up as slip on the next tick.
	if not is_on_floor():
		vertical_speed -= _gravity * delta
	var cg_velocity := forward_dir * forward_speed + right_dir * cg_lateral_speed + Vector3.UP * vertical_speed
	rotate_y(yaw_rate * delta)
	lateral_speed = cg_lateral_speed - yaw_rate * CG_OFFSET
	velocity = cg_velocity - global_basis.x * (yaw_rate * CG_OFFSET)
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
	reverse_engaged = false
	gear = 1
	automatic = true
	engine_rpm = IDLE_RPM
	_shift_timer = 0.0
	_since_shift = AUTO_SHIFT_HOLD
	front_load_fraction = 1.0 - REAR_WEIGHT_FRACTION
	rear_load_fraction = REAR_WEIGHT_FRACTION
	rear_traction_use = 0.0
	brake_grip_use = 0.0
	front_slip_angle = 0.0
	rear_slip_angle = 0.0
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


## Forward / reverse selection: only a fresh key press changes direction, so a
## brake key held through a stop just holds the car (see STANDSTILL_SPEED).
func _update_direction(speed: float) -> void:
	var accelerate_pressed := Input.is_action_pressed("accelerate")
	var brake_pressed := Input.is_action_pressed("brake")
	var fresh_accelerate := accelerate_pressed and not _accelerate_was_pressed
	var fresh_brake := brake_pressed and not _brake_was_pressed
	_accelerate_was_pressed = accelerate_pressed
	_brake_was_pressed = brake_pressed
	if fresh_accelerate == fresh_brake:
		return
	if fresh_brake and not reverse_engaged and absf(speed) <= STANDSTILL_SPEED:
		reverse_engaged = true
	elif fresh_accelerate and reverse_engaged and speed >= -STANDSTILL_SPEED:
		reverse_engaged = false


## Returns the new forward speed after one tick of engine / brake / coasting,
## and updates the gearbox, engine RPM and rear traction use on the way.
## `drive` is +1 for the accelerate key and -1 for the brake key.
func _update_forward_speed(speed: float, drive: float, delta: float) -> float:
	# The key of the selected direction is the throttle, the other one the
	# brake: it slows the car to a stop whichever way it rolls, and holds it
	# there. The throttle key also brakes while the car still rolls against the
	# selected direction (backwards out of a 180, nose-first out of a J-turn).
	var is_moving := absf(speed) > STANDSTILL_SPEED
	var direction := -1.0 if reverse_engaged else 1.0
	var against_travel := is_moving and signf(speed) != direction
	var braking := not is_zero_approx(drive) and (signf(drive) != direction or against_travel)
	var reversing := reverse_engaged
	var throttle := drive if drive > 0.0 and not braking and not reversing else 0.0

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

	brake_grip_use = clampf(BRAKE_DECEL_G * absf(drive), 0.0, 1.0) if braking and is_moving else 0.0
	if braking:
		speed = move_toward(speed, 0.0, BRAKE_DECEL * absf(drive) * delta)
	elif reversing and drive < 0.0:
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


## Most sideways force [N] an axle carrying `load` of the car's weight can make
## when it carries `static_load` at rest: TYRE_MU times the load at rest,
## sub-linear in load from there (LOAD_GRIP_EXPONENT).
func _axle_grip(load: float, static_load: float) -> float:
	var load_factor := pow(maxf(load, 0.0) / static_load, LOAD_GRIP_EXPONENT)
	return TYRE_MU * CAR_MASS * _gravity * static_load * load_factor


## The tyre curve: share of the peak sideways force (-1..1) at `slip`, the slip
## angle in peak slip angles. Rises smoothly into the peak at 1 (slope 1.5 at
## zero, flat at the top), then eases down to TYRE_SLIDE_GRIP.
func _tyre_curve(slip: float) -> float:
	var x := absf(slip)
	if x <= 1.0:
		return slip * (3.0 - x * x) * 0.5
	var sliding := 1.0 - exp(-(x - 1.0) / TYRE_SLIDE_ONSET)
	return signf(slip) * lerpf(1.0, TYRE_SLIDE_GRIP, sliding)


## Friction ellipse: share of its sideways grip a tyre has left while `use`
## (0..1) of its grip goes into braking or drive. See MIN_COMBINED_GRIP.
func _combined_grip(use: float) -> float:
	return maxf(sqrt(maxf(1.0 - use * use, 0.0)), MIN_COMBINED_GRIP)


## Caps an axle's sideways `force` [N] at what stops its sideways `slip_speed`
## [m/s] within this tick. A push at an axle `arm` metres from the centre of
## mass moves that axle as if it weighed 1 / (1 / mass + arm^2 / yaw inertia).
func _limit_to_stick(force: float, slip_speed: float, arm: float, yaw_inertia: float, delta: float) -> float:
	var stopping_force := absf(slip_speed) / ((1.0 / CAR_MASS + arm * arm / yaw_inertia) * delta)
	return clampf(force, -stopping_force, stopping_force)


## Deceleration along the car [m/s^2] from the locked rear wheels: their
## sliding grip, pointed against the way the rear axle is moving, minus what
## the foot brake already takes from the rear tyres.
func _handbrake_drag(speed: float, rear_slip_speed: float) -> float:
	if _handbrake_amount <= 0.0:
		return 0.0
	var rear_grip := _axle_grip(rear_load_fraction, REAR_WEIGHT_FRACTION) / CAR_MASS
	var along := absf(speed) / maxf(Vector2(speed, rear_slip_speed).length(), 0.01)
	return maxf(_handbrake_amount * TYRE_SLIDE_GRIP * along - brake_grip_use, 0.0) * rear_grip


## Stability assist strength right now [1/s]: SLIDE_YAW_DAMPING while the car
## points roughly where it is going, fading to SPIN_YAW_DAMPING as the slip
## angle (nose vs direction of travel, 0..PI) grows past SPIN_COMMIT_ANGLE.
## Off while the handbrake is held (that slide is deliberate) and, like a real
## stability system, with reverse engaged: a flick at speed in reverse swings
## the nose round (J-turn).
func _slide_yaw_damping(along: float, across: float) -> float:
	if reverse_engaged:
		return SPIN_YAW_DAMPING
	if Vector2(along, across).length() < SPIN_MIN_SPEED:
		return SLIDE_YAW_DAMPING
	var slip_angle := absf(atan2(across, along))
	var spin := maxf(smoothstep(SPIN_COMMIT_ANGLE, SPIN_FREE_ANGLE, slip_angle), _handbrake_amount)
	return lerpf(SLIDE_YAW_DAMPING, SPIN_YAW_DAMPING, spin)


## How much of the steering's aim the assist still counts as asked for (0..1)
## while the car slides: all of it up to SLIDE_CATCH_ANGLE of slip, none from
## SPIN_COMMIT_ANGLE, if the steering is turning the nose further into the
## slide. Steering held into a slide then no longer feeds it, and the slide
## settles at a catchable angle instead of creeping on into a spin.
func _slide_feed(along: float, across: float, steer_amount: float) -> float:
	if steer_amount * across * along <= 0.0:
		return 1.0
	return 1.0 - smoothstep(SLIDE_CATCH_ANGLE, SPIN_COMMIT_ANGLE, absf(atan2(across, along)))


## Returns the yaw rate [rad/s] the steering aims for with a steering amount
## (-1..1) at a given speed: that of the tightest corner the car can hold.
func _compute_yaw_rate(steer_amount: float, speed: float) -> float:
	# In reverse the same steering lock swings the nose the other way.
	return steer_amount * _steering_yaw_limit(absf(speed)) * signf(speed)


## Highest yaw rate [rad/s] the car can hold at `abs_speed`.
func _steering_yaw_limit(abs_speed: float) -> float:
	# Turning circle limit: no yaw at standstill, ramps in with speed.
	var available := minf(MAX_YAW_RATE, abs_speed / MIN_TURN_RADIUS)
	# Grip limit: cornering at yaw rate r needs speed * r of sideways
	# acceleration, and the tyres have TYRE_MU * g to give.
	return minf(available, TYRE_MU * _gravity / maxf(abs_speed, 0.01))


## Front wheel angle at full steering lock [rad] at `abs_speed`: the angle that
## rolls round the tightest corner the car can hold at that speed, plus the
## slip the front tyres need to make the force for it (STEER_SLIP_REACH), and
## never more than the turning circle's lock. In a slide the front of the car
## travels at an angle to where it points (`front_travel_angle`); the driver
## winds that much more lock on, as opposite lock needs, so the keys keep
## their bite on the front tyres however sideways the car is.
func _steering_lock(abs_speed: float, front_travel_angle: float) -> float:
	var wheelbase := 2.0 * AXLE_DISTANCE
	var full_lock := atan(wheelbase / MIN_TURN_RADIUS)
	var corner := atan(wheelbase * _steering_yaw_limit(abs_speed) / maxf(abs_speed, 0.01))
	return minf(full_lock, corner + FRONT_PEAK_SLIP_ANGLE * STEER_SLIP_REACH + absf(front_travel_angle))


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
