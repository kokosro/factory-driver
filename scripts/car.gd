class_name ArcadeCar
extends CharacterBody3D
## Custom arcade vehicle controller (no VehicleBody3D / VehicleWheel3D).
##
## Model in one paragraph: a rigid body on two axles ("bicycle" model) that
## goes where its tyres push it. The car carries a velocity and a yaw rate;
## nothing else moves it. Every physics tick each axle looks at how its contact
## patch really moves over the road: the SLIP ANGLE (where the wheels point vs
## where that end of the car is going) gives a sideways force from a tyre
## curve, rising to TYRE_MU times the axle's load at *_PEAK_SLIP_ANGLE, then
## easing off to TYRE_SLIDE_GRIP of that as the tyre slides; the SLIP RATIO
## (wheel speed vs road speed, wound up by engine and brake torque) gives the
## force along the wheel from the same curve. Both share one friction circle:
## grip spent along the wheel is not there across it. The forces act at the
## contact patches, along and across each wheel's heading: their sum
## accelerates the 1300 kg, their moments about the centre of mass (front force
## x front arm, rear force x rear arm) wind the yaw inertia up and down
## (YAW_GYRATION_RADIUS). Heading and direction of travel are separate things,
## tied together only by the tyres. The steering sets the front wheel angle
## and nothing else.
##
## Drivetrain: the engine works through a torque curve, a 5-speed gearbox and a
## final drive on the DRIVEN wheels (DRIVEN_WHEELS: rear, front or all four).
## That is where the layouts get their character, nobody scripts it: a
## rear-driven car spends rear grip on drive and pushes from behind, so power
## in a corner loosens the tail (power oversteer); a front-driven car asks its
## front tyres to pull and steer at once, so power pushes the nose wide and a
## launch is traction-limited as the load moves off the driven axle; all-wheel
## drive splits the torque (TORQUE_DISTRIBUTION) and sits in between. The
## brakes split their force front / rear (BRAKE_BIAS_FRONT), each axle capped
## by its own grip; the handbrake locks the rear wheels, which then only drag
## against their direction of travel, so the tail comes round.
##
## Weight and aero: the axle loads start from the static weight distribution,
## shift forward under braking / rearward under acceleration, and grow with
## speed from downforce (DOWNFORCE_COEFF). Each axle's grip follows its load.
##
## The road: the car drives on a RoadProfile (road_profile), a height field.
## Its body follows the road's ELEVATION, the gentle swell the ground mesh
## shows, kinematically: it rides the visible ground and never leaves it. Each
## of the four wheels follows the road in full, micro-bumps and all, through a
## spring and damper (RIDE_FREQUENCY, RIDE_DAMPING_RATIO): a bump pushes load
## into its wheel, a crest dropping away faster than the corner of the car can
## follow takes load off it. The axle loads the tyre model sees are the sums of
## their two wheels (wheel_loads), so grip breathes with the road; the tyre
## model itself knows nothing of any of this. On a flat road every wheel
## carries exactly its share and the car is the flat-ground car it always was.
##
## Two helpers sit on top, both documented where they live: below
## LOW_SPEED_BLEND_END the tyre forces are blended with plain rolling geometry
## (a force model degenerates at a standstill), and an arcade stability assist
## damps the nose swinging relative to the direction of travel; it fades at big
## slip angles (SPIN_COMMIT_ANGLE), so a committed flick becomes a 180 or a
## 360.
##
## Conventions: the car's nose points along local -Z, +X is the car's right,
## positive yaw (rotation about +Y) is a LEFT turn. The car stays upright: the
## road's slopes are gentle (RoadProfile.MAX_SLOPE), so the body takes the
## road's height, not its tilt, and gravity never pulls it downhill. Without a
## road_profile the ground is level (true for a bare car.tscn).

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

## Reverse gear ratio. Only drives the tach; the drive force in reverse is a
## flat one (REVERSE_ACCEL / MAX_REVERSE_SPEED), through the driven tyres.
const REVERSE_RATIO := 3.55

## Share of engine torque that reaches the wheels (0..1); the rest is lost in
## the gearbox and differential.
const DRIVETRAIN_EFFICIENCY := 0.88

## Rolling radius of the tyres [m]; must match the wheel mesh. Turns wheel
## torque into force and wheel speed into engine RPM.
const WHEEL_RADIUS := 0.34

# --- Drivetrain layout ---------------------------------------------------------

## Which wheels the engine drives. Nothing else about the layouts is scripted;
## the differences come out of where the drive force meets the road:
##   RWD  the rear tyres push. Drive uses up rear grip (friction circle) while
##        the fronts are free to steer: power in a corner loosens the tail and
##        tightens the line (power oversteer); lifting tucks it back. Under
##        acceleration load moves ONTO the driven axle, so traction is good.
##   FWD  the front tyres pull along their own heading and steer at once: power
##        in a corner uses up front grip and the nose pushes wide (power
##        understeer); lifting brings it back in. Load moves OFF the driven
##        axle under acceleration, so a launch is traction-limited.
##   AWD  the torque is split (TORQUE_DISTRIBUTION), each axle gives up less
##        grip: more drive out of a corner, balance between the two above.
enum DrivenWheels { RWD, FWD, AWD }

## The Boxster is mid-engined and rear-wheel drive. (Cars copy this into
## `driven_wheels`, which tests may switch to compare the layouts.)
const DRIVEN_WHEELS := DrivenWheels.RWD

## AWD only: share of the drive torque that goes to the FRONT axle (0..1), the
## rest goes to the rear. 0.4 = a rear-biased 40 / 60 split, 964 Carrera 4
## style (that one is 31 / 69).
const TORQUE_DISTRIBUTION := 0.4

## Share of the foot brake's force that goes to the FRONT axle (0..1), the rest
## to the rear. Braking moves load onto the front tyres, so they can take more.
## At 0.6 a full stop has the fronts at their limit with the rears a little
## under theirs: on the brakes the nose pushes wide and the tail stays planted.
## Lower = the rears give up first and braking into a corner swings the tail;
## higher = longer stops, the rears hardly working.
const BRAKE_BIAS_FRONT := 0.6

# --- Tyres and aero ----------------------------------------------------------

## Tyre friction coefficient: a tyre can push with at most this times its load,
## in any direction (1997 road tyres, ~0.95). Full throttle in 1st from
## ~3500 rpm is more than the rear tyres can transmit; 2nd and up stay under
## it.
const TYRE_MU := 0.95

## Grip of each axle's tyres relative to TYRE_MU (no unit). The Boxster's 255
## rears grip their share of the weight a little better than its 205 fronts
## grip theirs (the two average out to 1.0 over the static weight split). That
## is what makes the car safe at the limit, as it does the real one: with both
## ends sliding the front gives up first, the nose pushes wide and the tail
## pulls the car straight again, until power or the handbrake says otherwise.
## Equal = neutral: a slide, once started, just carries on.
const FRONT_TYRE_GRIP := 0.94
const REAR_TYRE_GRIP := 1.04

## Slip ratio at which a tyre makes its peak force ALONG the wheel (no unit):
## (wheel surface speed - road speed) / road speed, 0.1 = the wheel turning
## 10 % faster than the road (drive) or slower (braking). The same curve shape
## as sideways (_tyre_curve): up to the peak the tyre hooks up, past it the
## wheel spins up or locks and the force eases to TYRE_SLIDE_GRIP of the peak.
const PEAK_SLIP_RATIO := 0.1

## Slip ratio the ABS holds a braked wheel at when the pedal asks for more than
## the tyre has (no unit). A little past the peak, as real systems run: in a
## straight line that costs ~3 % of the stop, and braking and steering at once
## it gives the stop the bigger share of the front tyres' grip rather than the
## other way round.
const ABS_SLIP_RATIO := 0.15

## Slip ratio the driver's right foot holds a spinning driven wheel at when
## the engine has more than the tyre can take (no unit): on / off keys cannot
## feather a throttle, so this does. 0.25 is proper wheelspin, 2.5 times the
## peak: the tyre pushes with ~0.9 of its grip and has next to nothing left
## for holding the car sideways (MIN_COMBINED_GRIP is what it keeps), so full
## throttle in 1st still lights the driven tyres up and lets that end of the
## car go. Without the limit the wheels would spin on at any slip until the
## lift, which no driver does. Higher = wilder wheelspin, less drive.
const DRIVE_SLIP_RATIO := 0.25

## A slip angle is sideways speed over rolling speed; this is the least
## rolling speed it is worked out against [m/s]. Keeps the angle (and its
## tangent) finite with a tyre moving dead sideways, and stops the last
## millimetres per second of a car coming to rest reading as 90 degrees of
## slip.
const SLIP_ANGLE_MIN_SPEED := 1.0

## How quickly a wheel's slip ratio moves towards the slip where the tyre force
## balances the torque on the wheel, and runs away past the peak when the
## torque is more than the tyre can hold [1/s]. Stands in for the wheel's
## inertia: 12 means full throttle in 1st lights the rear tyres up in ~0.2 s,
## and they hook up again within ~0.1 s of a lift.
const SLIP_RATIO_RESPONSE := 12.0

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

## Drag coefficient Cd (no unit). Drag force is
## 0.5 * AIR_DENSITY * DRAG_COEFF * FRONTAL_AREA * speed^2 (~0.40 kg/m in
## all). 986: 0.31 roof up; 0.34 allows for the roof down. Balances full power
## in 5th at ~65 m/s (~234 km/h), just under the rev limiter.
## Replaces the flat AERO_DRAG 0.40 [kg/m], the same number in one lump.
const DRAG_COEFF := 0.34

## Frontal area [m^2] (986: 1.93).
const FRONTAL_AREA := 1.93

## Downforce [N per (m/s)^2]: force pressing the car onto the road is this
## times speed squared, ~90 N at 60 km/h, ~490 N at 140, ~1250 N at 215 (a
## tenth of the car's weight). More load = more grip, so fast corners hold
## more than TYRE_MU g while slow ones are untouched. The road 986 makes next
## to none; this is the arcade aero kit. 0 = none.
const DOWNFORCE_COEFF := 0.35

## Share of the downforce that lands on the FRONT axle (0..1). Below the static
## front weight share (0.38) the rear gains more than the front: the faster the
## car goes, the more planted the tail and the less eager the nose.
const AERO_BALANCE_FRONT := 0.35

## Nominal top speed [m/s], ~237 km/h. Not a hard cap: the real top speed
## comes out of drag vs engine power (a touch below this). Used to scale
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

## Deceleration a full brake application asks for [m/s^2]: what the tyres
## could hold with every one of them at its limit, ~9.3 (0.95 g). The force
## (this times CAR_MASS) is split by BRAKE_BIAS_FRONT and each axle delivers
## what its grip allows (ABS holds a wheel at ABS_SLIP_RATIO, it never locks):
## with the fronts at their limit and the rears under theirs, a real stop
## comes out at ~0.9 of this, ~8.4 m/s^2 plus drag.
const BRAKE_DECEL := BRAKE_DECEL_G * TYRE_MU * 9.8

## Density of air [kg/m^3], for the drag force.
const AIR_DENSITY := 1.225

## Rolling resistance [m/s^2], always on while the car rolls. With engine
## braking and aero drag it makes up the coast-down.
const COAST_DECEL := 0.15

## Acceleration in reverse gear [m/s^2]: drive force at the driven wheels of
## this times CAR_MASS (about what the engine gives through REVERSE_RATIO),
## through the tyres like any other drive force.
const REVERSE_ACCEL := 6.0

## Top speed in reverse [m/s]. 12 m/s is about 43 km/h.
const MAX_REVERSE_SPEED := 12.0

## How sharply the drive in reverse tails off into MAX_REVERSE_SPEED [1/s]: the
## acceleration left is this times the speed still to go, so 4.0 starts
## easing off 1.5 m/s short of the top.
const REVERSE_LIMITER_RATE := 4.0

## Below this speed [m/s] the car counts as stopped. The brake only ever slows
## the car to a stop and holds it there; the direction changes on a FRESH key
## press at a standstill: brake pressed anew engages reverse, accelerate
## pressed anew engages forward again (see reverse_engaged). A brake key that
## is still held from the braking never changes direction; a held accelerate
## key does, after FORWARD_ENGAGE_GRACE.
const STANDSTILL_SPEED := 0.5

## Below this speed [m/s] the car is at rest for the tyre forces: nothing but
## the engine sets it rolling (see _physics_process step 6).
const REST_SPEED := 0.01

## Time the car has to stand still in reverse under a held accelerate key
## before forward engages by itself [s]. Forward is the home direction, like an
## automatic's D: holding the throttle through the stop of a J-turn drives away
## in one motion, no release and re-press. 0.2 s is long enough that the stop
## reads as a stop, short enough not to feel like a stall. Deliberately not
## mirrored: reverse is a fresh decision, a brake held through a forward stop
## must never engage it.
const FORWARD_ENGAGE_GRACE := 0.2

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

## Friction circle: a tyre has one grip to share between pushing along the
## wheel (drive, braking) and holding across it (see _tyre_force). Braking
## while turning costs turn-in; trailing off the brake gives it back; power at
## the driven wheels loosens that end of the car. This is the floor: the share
## of its plain sideways force (0..1) a tyre keeps whatever happens along the
## wheel, where a bare friction circle leaves next to none under wheelspin. It stands for
## the ABS (and a driver's right foot) giving up a little of the stop to keep
## the car steerable, which on/off keys cannot do themselves. Lower = braking
## and turning exclude each other more, snappier power oversteer.
const MIN_COMBINED_GRIP := 0.4

# --- Suspension (road feel) ---------------------------------------------------

# One spring / damper channel per wheel, a load layer on top of the axle loads
# above: the corner of the car over each wheel is a mass on a spring that
# follows the road under that wheel (see _suspension_force). On a flat road the
# channels rest at 0 and the wheel loads are the axle loads halved, exactly.

## Ride frequency of a corner of the car on its spring [Hz]. Road cars sit at
## 1 - 1.5, sports cars up to 2. Higher = stiffer: the car follows the road
## more closely and the wheel loads swing more over the same bumps.
const RIDE_FREQUENCY := 1.4

## Damping ratio of that spring (no unit): 0.3 - 0.5 on a road car. 1 would
## settle without any overshoot, lower floats on after a crest.
const RIDE_DAMPING_RATIO := 0.4

## How quickly the tyre lets the road through to the suspension [1/s], ~6 Hz:
## carcass and contact patch swallow what is shorter than themselves, and at
## speed one physics tick is most of a metre of road. Without it the damper
## would turn every sampled ripple into a hammer blow. Lower = smoother ride,
## calmer wheel loads.
const TYRE_ENVELOPE_RATE := 40.0

## Where each tyre meets the road, in the car's frame [m]: front left, front
## right, rear left, rear right (the order of wheel_loads). Must match the
## wheel positions in car.tscn.
const WHEEL_CONTACT_POINTS: Array[Vector3] = [
	Vector3(-0.86, 0.0, -AXLE_DISTANCE),
	Vector3(0.86, 0.0, -AXLE_DISTANCE),
	Vector3(-0.86, 0.0, AXLE_DISTANCE),
	Vector3(0.86, 0.0, AXLE_DISTANCE),
]

# --- Steering ----------------------------------------------------------------

## Front wheel angle at full steering lock [rad], ~27.5 degrees: a 5 m
## turning circle radius at parking speed. Raw steering: the front wheel angle
## is the steering input times this, at any speed, however sideways the car
## is, and nothing else moves the wheels. What the car does with the angle is
## up to the front tyres: full lock at speed is far past their peak slip angle,
## so they scrub and the car pushes wide, and a slide is caught with opposite
## lock by the driver. Also what the front wheels show.
## Replaces MIN_TURN_RADIUS 5.0 (the same lock, as a radius) and MAX_YAW_RATE
## 2.0, the cap of a yaw rate the steering used to aim for: there is no such
## aim any more.
## Was the far end of a slip-sensitive lock (STEER_SLIP_REACH 1.2 -> removed:
## full lock used to stop 1.2 front peak slip angles past the way the front of
## the car travelled, so the wheels moved less the faster the car went, and by
## themselves as that travel angle moved - the driver asked for the wheels
## back). There is no such easing any more.
const MAX_STEER_LOCK := 0.48

## How fast the steering input moves towards the pressed key, and back to
## centre on release [1/s]. 5.0 means centre to full lock in 0.2 s. Smooths out
## the on/off nature of keyboard steering.
const STEER_RESPONSE := 5.0

# --- Slides ------------------------------------------------------------------

## Arcade stability assist: how quickly the nose swinging relative to the
## direction of travel dies away [1/s]. The assist compares the yaw rate with
## the rate at which the tyre forces are really bending the car's path, and
## leans on the difference with a yaw moment (as a stability system does with
## single wheel brakes). Rolling round a steady corner the two match and the
## assist does nothing; it has no idea where the steering points and never
## turns the car for the driver. It checks the tail stepping out and the car
## rotating on after the tyres have stopped turning it, which keeps a power
## slide or a handbrake slide catchable instead of an instant spin.
## Lower = wilder slides that spin more easily, higher = tamer.
const SLIDE_YAW_DAMPING := 8.0

## The assist only leans on a slide that is getting deeper; it comes in over
## this much angle between nose and direction of travel [rad] (~1 degree), so
## it never switches on with a step.
const SLIDE_ASSIST_EASE_ANGLE := 0.02

## Share of the assist (0..1) that also works on a slide that is coming back.
## The tyres straighten the car by themselves; at 160 km/h and up they do it
## with a swing back past straight, and this much takes that out. At 1.0 the
## assist would hold on to a slide as hard as it checks one.
const SLIDE_RECOVERY_ASSIST := 0.4

## Most yaw acceleration the assist can apply [rad/s^2]. It works through the
## tyres like everything else, so it is bounded: ~2000 kg m^2 of yaw inertia
## times 6 is a 12 kNm moment, about what braking both wheels of one side at
## their limit gives. Past that the slide wins.
const MAX_ASSIST_YAW_ACCEL := 6.0

## Stability assist left once the car is committed to a spin [1/s]. Low, so
## the rotation carries on under its own momentum through a 180 or a 360.
const SPIN_YAW_DAMPING := 0.3

## Slip angle (nose vs direction of travel) from which the stability assist
## starts to leave a slide that is coming back alone [rad]: its
## SLIDE_RECOVERY_ASSIST share fades from here to none at SPIN_COMMIT_ANGLE.
## Grip driving stays under ~0.1 even at the limit, so this only touches real
## slides.
## Was also where steering held into a slide started to lose its bite (the
## slide feed, with SLIDE_RELEASE_ANGLE 0.3 -> removed, where none of it got
## through and the front wheels trailed into line by themselves): the wheels
## stay where the input puts them, and that role is gone. The value is
## unchanged, the assist still uses it.
const SLIDE_CATCH_ANGLE := 0.14

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

# --- Low-speed blend -----------------------------------------------------------

# A tyre-force model degenerates at a standstill: slip angles are a ratio of
# two speeds that both go to zero, so they turn into noise. Below
# LOW_SPEED_BLEND_END the forces are therefore blended with plain rolling
# geometry: the car is eased onto the circle its front wheels point round
# (yaw rate = speed * tan(wheel angle) / wheelbase, no sideways speed at the
# rear axle), fully so at LOW_SPEED_BLEND_START and below. The blend goes by
# the car's speed over the ground in any direction, so a car sliding sideways
# through the middle of a spin stays on its tyres. There is no switch: the
# weight is smooth in speed and the geometry is what the tyre forces settle on
# by themselves at parking pace, only without the noise.

## Speed over the ground from which the car runs on tyre forces alone [m/s],
## ~14 km/h.
const LOW_SPEED_BLEND_END := 4.0

## Speed at and below which rolling geometry has its full say [m/s].
const LOW_SPEED_BLEND_START := 1.0

## How quickly the car is eased onto the rolling circle where the geometry has
## its full say [1/s]; less in between. 10 = within about a tenth of a second,
## so the last of a slide still visibly scrubs off instead of stopping dead.
const LOW_SPEED_ALIGN_RATE := 10.0

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

## Furthest a wheel is drawn above or below its place in car.tscn as it follows
## the road [m]. The body follows the elevation only, so under the wheel cam a
## wheel shows up to ~1 cm of bump travel (RoadProfile.MICRO_AMPLITUDE) plus
## the grade across the wheelbase (2 cm at 1.5 %).
const MAX_WHEEL_VISUAL_TRAVEL := 0.04

## Engine speed from which the HUD tach turns to its warning colour [rpm].
const SHIFT_LIGHT_RPM := 6500.0

# =============================================================================
#  STATE
# =============================================================================

## The road the car drives on: what its wheels feel and its body follows. In
## main.tscn the same resource as the pad's. None = level ground.
@export var road_profile: RoadProfile:
	set(value):
		road_profile = value
		if is_inside_tree():
			_settle_suspension()

## Signed speed along the nose [m/s]. Negative while reversing.
var forward_speed := 0.0

## Signed sideways slip speed [m/s], at the middle of the wheelbase. Positive =
## sliding towards the car's right.
var lateral_speed := 0.0

## Current yaw rate [rad/s]. Positive = turning left. Wound up and down by the
## moments of the tyre forces against the yaw inertia, nothing else.
var yaw_rate := 0.0

## How fast the nose swings relative to the direction of travel [rad/s]: the
## yaw rate minus the rate at which the tyre forces bend the car's path. Near
## zero rolling round a corner, large during a handbrake slide. What the
## stability assist works on.
var slide_yaw_rate := 0.0

## Smoothed steering input, -1 (full right) .. +1 (full left).
var steer := 0.0

## Angle of the front wheels to the car [rad], positive = left. All the
## steering ever sets.
var wheel_angle := 0.0

## Which wheels are driven; starts as DRIVEN_WHEELS. A variable so tests (and
## later cars) can compare the layouts on the same chassis.
var driven_wheels := DRIVEN_WHEELS

## Acceleration of the centre of mass from this tick's forces [m/s^2], in the
## car's frame: along the nose, and towards the INSIDE of a left turn
## (positive = pushed left).
var longitudinal_accel := 0.0
var lateral_accel := 0.0

## Selected gear: 0 = neutral, 1..5 forward. Reversing is handled separately
## (reverse_engaged) and does not change this.
var gear := 1

## True while reverse is selected. The keys then swap roles: the brake key is
## the throttle (backwards) and the accelerate key is the brake. Engaged by a
## fresh press of the brake key at a standstill, never by a held one; left by
## a fresh press of the accelerate key at a standstill or while the car rolls
## nose-first (the way out of a J-turn: selecting drive while already rolling
## forwards is harmless, selecting reverse on the move is what a gearbox locks
## out), or by the accelerate key held through the stop for
## FORWARD_ENGAGE_GRACE.
var reverse_engaged := false

## True = the gearbox shifts by itself. The shift keys switch to manual.
var automatic := true

## Engine speed [rpm].
var engine_rpm := IDLE_RPM

## Share of the car's weight on each axle right now (0..1, sums to 1).
var front_load_fraction := 1.0 - REAR_WEIGHT_FRACTION
var rear_load_fraction := REAR_WEIGHT_FRACTION

## Load on each axle right now [N]: its share of the weight plus its share of
## the downforce, and what the road is doing to its two wheels (the sum of
## their wheel_loads).
var front_axle_load := 0.0
var rear_axle_load := 0.0

## Load on each wheel right now [N]: front left, front right, rear left, rear
## right. Half its axle's share plus what its suspension makes of the road.
var wheel_loads: Array[float] = [0.0, 0.0, 0.0, 0.0]

## How much of each axle's grip goes along the wheel, into drive or braking,
## 0..1. 1 = at or past the peak: wheelspin, or ABS holding the wheel.
var front_traction_use := 0.0
var rear_traction_use := 0.0

## Slip angle of each axle's tyres [rad], for tuning and tests. Positive =
## the tyres slide towards their right.
var front_slip_angle := 0.0
var rear_slip_angle := 0.0

## Slip ratio of each axle's tyres (no unit): positive = the wheels turn faster
## than the road passes (pushing the car forwards), negative = slower.
var front_slip_ratio := 0.0
var rear_slip_ratio := 0.0

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

## How long the car has stood still in reverse with the accelerate key held
## [s]. Forward engages at FORWARD_ENGAGE_GRACE.
var _forward_engage_timer := 0.0

## Time left in the current gear change [s].
var _shift_timer := 0.0

## Time since the last gear change [s]; the automatic waits AUTO_SHIFT_HOLD.
var _since_shift := AUTO_SHIFT_HOLD

## Per wheel (the order of wheel_loads): the road height as the tyre passes it
## on [m], and the height [m] and vertical speed [m/s] of the corner of the car
## riding on that wheel's spring. Heights are world heights; only their
## differences matter.
var _tyre_heights: Array[float] = [0.0, 0.0, 0.0, 0.0]
var _corner_heights: Array[float] = [0.0, 0.0, 0.0, 0.0]
var _corner_speeds: Array[float] = [0.0, 0.0, 0.0, 0.0]

## How far each wheel is drawn from its place in car.tscn [m], up positive.
var _wheel_travel: Array[float] = [0.0, 0.0, 0.0, 0.0]

## Elevation of the road under the car's origin, as of the last move [m]: the
## height the body rides at.
var _ground_height := 0.0

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _spawn_transform: Transform3D

@onready var _body: Node3D = $Body
@onready var _front_wheels: Array[Node3D] = [$Wheels/FrontLeft, $Wheels/FrontRight]
@onready var _wheels: Array[Node3D] = [$Wheels/FrontLeft, $Wheels/FrontRight, $Wheels/RearLeft, $Wheels/RearRight]
@onready var _wheel_rest_height: float = _wheels[0].position.y
@onready var _wheel_spinners: Array[Node3D] = [
	$Wheels/FrontLeft/Spin,
	$Wheels/FrontRight/Spin,
	$Wheels/RearLeft/Spin,
	$Wheels/RearRight/Spin,
]


func _ready() -> void:
	_spawn_transform = global_transform
	_settle_suspension()


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

	# 1. The state: the velocity in the car's own frame, and the yaw rate.
	#    Reading the velocity back from `velocity` means collisions are
	#    respected automatically. `velocity` belongs to the car's origin, the
	#    middle of the wheelbase; the forces work on the centre of mass,
	#    CG_OFFSET behind it.
	var forward_dir := -global_basis.z
	var right_dir := global_basis.x
	forward_speed = velocity.dot(forward_dir)
	lateral_speed = velocity.dot(right_dir)
	var vertical_speed := velocity.y
	var cg_lateral_speed := lateral_speed + yaw_rate * CG_OFFSET
	var ground_speed := Vector2(forward_speed, cg_lateral_speed).length()
	_update_direction(forward_speed, drive_input, delta)
	if handbrake_held:
		_handbrake_amount = 1.0
	else:
		_handbrake_amount = move_toward(_handbrake_amount, 0.0, HANDBRAKE_RECOVERY_RATE * delta)

	# 2. Axle loads: the static split, shifted by the acceleration of the last
	#    tick (eased in at the suspension's pace), plus downforce. Each wheel
	#    carries half its axle's share plus what its spring and damper make of
	#    the road under it; the axle load the tyres work with is the sum of its
	#    two wheels.
	var target_transfer := clampf(
		longitudinal_accel * CG_HEIGHT / (_gravity * 2.0 * AXLE_DISTANCE),
		-MAX_LOAD_TRANSFER, MAX_LOAD_TRANSFER
	)
	var current_transfer := rear_load_fraction - REAR_WEIGHT_FRACTION
	var transfer := lerpf(current_transfer, target_transfer, 1.0 - exp(-LOAD_TRANSFER_RESPONSE * delta))
	rear_load_fraction = REAR_WEIGHT_FRACTION + transfer
	front_load_fraction = 1.0 - rear_load_fraction
	var weight := CAR_MASS * _gravity
	var downforce := DOWNFORCE_COEFF * ground_speed * ground_speed
	var front_carried := weight * front_load_fraction + downforce * AERO_BALANCE_FRONT
	var rear_carried := weight * rear_load_fraction + downforce * (1.0 - AERO_BALANCE_FRONT)
	for i in wheel_loads.size():
		# A wheel can be light, or in the air over a crest; the road never
		# pulls it down: no load below 0.
		wheel_loads[i] = maxf((front_carried if i < 2 else rear_carried) * 0.5 + _suspension_force(i, delta), 0.0)
	front_axle_load = wheel_loads[0] + wheel_loads[1]
	rear_axle_load = wheel_loads[2] + wheel_loads[3]
	var front_grip := FRONT_TYRE_GRIP * _axle_grip(front_axle_load, weight * (1.0 - REAR_WEIGHT_FRACTION))
	var rear_grip := REAR_TYRE_GRIP * _axle_grip(rear_axle_load, weight * REAR_WEIGHT_FRACTION)

	# 3. How each contact patch moves over the road. The front axle sits ahead
	#    of the centre of mass and its wheels are steered, so its motion is
	#    split along and across the wheels, not the car; the rear sits behind
	#    and points where the car points. A positive (left) yaw rate moves the
	#    nose left and the tail right. Raw steering: the wheels stand at the
#    (smoothed) input times full lock, the same rolling forwards, backwards
#    or sideways. Was steer * _steering_lock() * _slide_feed() minus a trail
#    towards the way the front travels -> removed: nothing turns the wheels
#    but the driver. The wheels point where they are steered in reverse too:
#    the yaw response flips with the direction of travel, not the wheels (the
#    old signf(forward_speed) only ever picked the side of the leading term).
	steer = move_toward(steer, steer_input, STEER_RESPONSE * delta)
	var front_arm := AXLE_DISTANCE + CG_OFFSET
	var rear_arm := AXLE_DISTANCE - CG_OFFSET
	var yaw_inertia := CAR_MASS * YAW_GYRATION_RADIUS * YAW_GYRATION_RADIUS
	var front_lateral := cg_lateral_speed - yaw_rate * front_arm
	var rear_lateral := cg_lateral_speed + yaw_rate * rear_arm
	wheel_angle = steer * MAX_STEER_LOCK
	var front_across := front_lateral * cos(wheel_angle) + forward_speed * sin(wheel_angle)
	var front_along := forward_speed * cos(wheel_angle) - front_lateral * sin(wheel_angle)
	front_slip_angle = atan2(front_across, maxf(absf(front_along), SLIP_ANGLE_MIN_SPEED))
	rear_slip_angle = atan2(rear_lateral, maxf(absf(forward_speed), SLIP_ANGLE_MIN_SPEED))

	# 4. Slip ratios: engine and brake torque wind each axle's wheels up or
	#    down against the road (see _advance_slip_ratio). The handbrake locks
	#    the rear wheels outright: slip ratio -1 (+1 rolling backwards).
	var demand := _longitudinal_demand(forward_speed, drive_input, delta)
	var front_share := _front_drive_share()
	var abs_active: bool = demand.brake > 0.0
	var front_demand: float = demand.engine * front_share - signf(front_along) * demand.brake * BRAKE_BIAS_FRONT
	var rear_demand: float = demand.engine * (1.0 - front_share) - signf(forward_speed) * demand.brake * (1.0 - BRAKE_BIAS_FRONT)
	front_slip_ratio = _advance_slip_ratio(front_slip_ratio, front_demand / front_grip, front_slip_angle, FRONT_PEAK_SLIP_ANGLE, abs_active, delta)
	rear_slip_ratio = _advance_slip_ratio(rear_slip_ratio, rear_demand / rear_grip, rear_slip_angle, REAR_PEAK_SLIP_ANGLE, abs_active, delta)
	rear_slip_ratio = lerpf(rear_slip_ratio, -signf(forward_speed), _handbrake_amount)
	front_traction_use = _traction_use(front_slip_ratio)
	rear_traction_use = _traction_use(rear_slip_ratio)

	# 5. Tyre forces, along (x) and across (y) each axle's wheels, from slip
	#    ratio and slip angle together (see _tyre_force).
	var front_tyre := front_grip * _tyre_force(front_slip_ratio, front_slip_angle, FRONT_PEAK_SLIP_ANGLE)
	var rear_tyre := rear_grip * _tyre_force(rear_slip_ratio, rear_slip_angle, REAR_PEAK_SLIP_ANGLE)
	# A tyre can stop its contact patch sliding, not throw it back the other
	# way: no more force than brings that slip to zero this tick, sideways and
	# (for a braked or locked wheel) along the wheel. At walking pace this is
	# what makes the car roll where its wheels point, and stand still on the
	# brake with the wheels turned.
	var front_force := _limit_to_stick(front_tyre.y, front_across, front_arm, yaw_inertia, delta)
	var rear_force := _limit_to_stick(rear_tyre.y, rear_lateral, rear_arm, yaw_inertia, delta)
	var front_drive := front_tyre.x
	if front_drive * front_along < 0.0:
		front_drive = _limit_to_stick(front_drive, front_along, front_arm * sin(wheel_angle), yaw_inertia, delta)
	var rear_drive := rear_tyre.x

	# 6. Add it all up at the centre of mass, in the car's frame. The front
	#    forces act along and across the steered wheels: the sideways force of
	#    a steered wheel also points a little backwards (cornering drag), the
	#    pull of a driven one a little into the corner.
	var front_forward := front_drive * cos(wheel_angle) + front_force * sin(wheel_angle)
	var front_right := front_force * cos(wheel_angle) - front_drive * sin(wheel_angle)
	var air_drag := 0.5 * AIR_DENSITY * DRAG_COEFF * FRONTAL_AREA * forward_speed * forward_speed
	var rolling_drag := COAST_DECEL * CAR_MASS
	var right_force := front_right + rear_force
	var yaw_moment := rear_force * rear_arm - front_right * front_arm
	# Forces that push the car along, and forces that only ever slow it down
	# (brakes, engine braking, locked wheels, drag): the second kind stops the
	# car at most, it never pushes it back the other way. At rest only a force
	# the engine is asking for counts as a push; that is what holds the car on
	# the brake.
	var pushing := 0.0
	var slowing := air_drag + rolling_drag
	var at_rest := absf(forward_speed) < REST_SPEED
	for force: float in [front_forward, rear_drive]:
		if force * (demand.engine if at_rest else forward_speed) > 0.0:
			pushing += force
		else:
			slowing += absf(force)
	var speed_before := forward_speed
	forward_speed += pushing / CAR_MASS * delta
	forward_speed = move_toward(forward_speed, 0.0, slowing / CAR_MASS * delta)
	longitudinal_accel = (forward_speed - speed_before) / delta
	lateral_accel = -right_force / CAR_MASS

	# 7. Stability assist: a bounded yaw moment against the nose swinging
	#    relative to the direction of travel. The path bends at the rate the
	#    forces turn the velocity vector: (v x a) / v^2.
	var blend := smoothstep(LOW_SPEED_BLEND_START, LOW_SPEED_BLEND_END, ground_speed)
	var rolling_yaw_rate := forward_speed * tan(wheel_angle) / (2.0 * AXLE_DISTANCE)
	var path_yaw_rate := (cg_lateral_speed * longitudinal_accel + forward_speed * lateral_accel) / maxf(ground_speed * ground_speed, 0.01)
	slide_yaw_rate = yaw_rate - lerpf(rolling_yaw_rate, path_yaw_rate, blend)
	# A slide that is getting deeper is leaned on in full: the nose already
	# pointing to one side of the way the car travels, and still swinging
	# further that way. A slide coming back is the tyres' own work and only
	# gets SLIDE_RECOVERY_ASSIST of it, none from a real slide (the weight
	# eases between the two over SLIDE_ASSIST_EASE_ANGLE, no step).
	var nose_angle := atan2(rear_lateral, absf(forward_speed)) * signf(forward_speed)
	var recovery := SLIDE_RECOVERY_ASSIST * (1.0 - smoothstep(SLIDE_CATCH_ANGLE, SPIN_COMMIT_ANGLE, absf(nose_angle)))
	var deepening := clampf(nose_angle * signf(slide_yaw_rate) / SLIDE_ASSIST_EASE_ANGLE, recovery, 1.0)
	var assist := clampf(
		-_slide_yaw_damping(forward_speed, rear_lateral) * slide_yaw_rate * deepening,
		-MAX_ASSIST_YAW_ACCEL, MAX_ASSIST_YAW_ACCEL
	)

	# 8. Integrate: force / mass into the velocity, moment / yaw inertia into
	#    the yaw rate. Nothing else turns the car or bends its path.
	cg_lateral_speed += right_force / CAR_MASS * delta
	yaw_rate += (yaw_moment / yaw_inertia + assist) * delta

	# 9. Low-speed blend (see LOW_SPEED_BLEND_END): ease the car onto the circle
	#    its front wheels roll round, where the forces lose their meaning.
	var align := (1.0 - blend) * (1.0 - exp(-LOW_SPEED_ALIGN_RATE * delta))
	yaw_rate = lerpf(yaw_rate, rolling_yaw_rate, align)
	cg_lateral_speed = lerpf(cg_lateral_speed, -rolling_yaw_rate * rear_arm, align)

	# 10. Move. The velocity is put together from the directions of *before*
	#     the turn: rotating the body does not touch where the mass is going.
	#     Heading and velocity only ever meet through the tyres, on the next
	#     tick, as slip.
	if not is_on_floor():
		vertical_speed -= _gravity * delta
	var cg_velocity := forward_dir * forward_speed + right_dir * cg_lateral_speed + Vector3.UP * vertical_speed
	rotate_y(yaw_rate * delta)
	lateral_speed = cg_lateral_speed - yaw_rate * CG_OFFSET
	velocity = cg_velocity - global_basis.x * (yaw_rate * CG_OFFSET)
	move_and_slide()
	_follow_elevation()

	_update_visuals(delta)


## Puts the car back where the scene placed it, at rest, in 1st, automatic.
func reset_to_spawn() -> void:
	reset_to(_spawn_transform)


## Where the scene placed the car. Missions offset their start points from it.
func get_spawn_transform() -> Transform3D:
	return _spawn_transform


## Puts the car at `target`, at rest, in 1st, automatic. The height of
## `target` counts from the road: the car is stood on the elevation there.
func reset_to(target: Transform3D) -> void:
	global_transform = target
	if road_profile != null:
		global_position.y += road_profile.elevation_height(target.origin.x, target.origin.z)
	velocity = Vector3.ZERO
	forward_speed = 0.0
	lateral_speed = 0.0
	yaw_rate = 0.0
	slide_yaw_rate = 0.0
	steer = 0.0
	_handbrake_amount = 0.0
	reverse_engaged = false
	_forward_engage_timer = 0.0
	gear = 1
	automatic = true
	engine_rpm = IDLE_RPM
	_shift_timer = 0.0
	_since_shift = AUTO_SHIFT_HOLD
	front_load_fraction = 1.0 - REAR_WEIGHT_FRACTION
	rear_load_fraction = REAR_WEIGHT_FRACTION
	front_traction_use = 0.0
	rear_traction_use = 0.0
	front_slip_angle = 0.0
	rear_slip_angle = 0.0
	front_slip_ratio = 0.0
	rear_slip_ratio = 0.0
	wheel_angle = 0.0
	longitudinal_accel = 0.0
	lateral_accel = 0.0
	_body.rotation = Vector3.ZERO
	_settle_suspension()
	reset_physics_interpolation()


## Suspension at rest on the road under the car as it stands: every corner
## sits on its wheel, nothing moves, every wheel carries its static share.
func _settle_suspension() -> void:
	_ground_height = 0.0
	if road_profile != null:
		_ground_height = road_profile.elevation_height(global_position.x, global_position.z)
	var weight := CAR_MASS * _gravity
	for i in wheel_loads.size():
		var height := _road_height_under_wheel(i)
		_tyre_heights[i] = height
		_corner_heights[i] = height
		_corner_speeds[i] = 0.0
		_wheel_travel[i] = height - _ground_height
		wheel_loads[i] = weight * ((1.0 - REAR_WEIGHT_FRACTION) if i < 2 else REAR_WEIGHT_FRACTION) * 0.5


## Height of the road under wheel `i`, every layer of the profile [m].
func _road_height_under_wheel(i: int) -> float:
	if road_profile == null:
		return 0.0
	var contact := global_transform * WHEEL_CONTACT_POINTS[i]
	return road_profile.sample_height(contact.x, contact.z)


## One tick of wheel `i`'s suspension; returns what it adds to that wheel's
## load [N]. The corner of the car over the wheel is a mass on a spring and a
## damper, standing on the road as the tyre passes it on:
##   corner acceleration = w^2 * (road - corner) + 2 * ratio * w * (road speed - corner speed)
## with w = TAU * RIDE_FREQUENCY, and the wheel load is what it takes to
## accelerate that mass, on top of carrying it. The road coming up at the wheel
## pushes load in; the road dropping away (past a crest, into a dip) faster
## than the corner can fall after it takes load off, which is all a crest is.
## A steady climb or a level road leaves the corner riding along at rest on
## its spring: 0. Over time the corner goes where the road goes, so the force
## averages out to nothing: the road moves load around, it does not add any.
## Semi-implicit Euler; w * delta is 0.15 at 60 ticks a second, far inside
## what it stays stable for (2).
func _suspension_force(i: int, delta: float) -> float:
	if road_profile == null:
		return 0.0
	var tyre_before := _tyre_heights[i]
	_tyre_heights[i] = lerpf(tyre_before, _road_height_under_wheel(i), 1.0 - exp(-TYRE_ENVELOPE_RATE * delta))
	var road_speed := (_tyre_heights[i] - tyre_before) / delta
	var omega := TAU * RIDE_FREQUENCY
	var accel := omega * omega * (_tyre_heights[i] - _corner_heights[i]) \
			+ 2.0 * RIDE_DAMPING_RATIO * omega * (road_speed - _corner_speeds[i])
	_corner_speeds[i] += accel * delta
	_corner_heights[i] += _corner_speeds[i] * delta
	_wheel_travel[i] = _tyre_heights[i] - _ground_height
	# The mass riding on this wheel: its share of the car at rest [kg].
	var corner_mass := CAR_MASS * ((1.0 - REAR_WEIGHT_FRACTION) if i < 2 else REAR_WEIGHT_FRACTION) * 0.5
	return corner_mass * accel


## Keeps the body on the visible ground: lifts or lowers the car by however
## much the road's elevation changed under its origin over this tick's move.
## The pad keeps the ground's collision plane at the same height under the car
## (TestPad._follow_car), so move_and_slide() finds the floor where it left it.
func _follow_elevation() -> void:
	if road_profile == null:
		return
	var ground := road_profile.elevation_height(global_position.x, global_position.z)
	if ground != _ground_height:
		global_position.y += ground - _ground_height
		_ground_height = ground


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


## Engine speed [rpm] the road would turn the engine at in `in_gear`
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


## Forward / reverse selection. A fresh key press changes direction; a brake
## key held through a stop just holds the car (see STANDSTILL_SPEED). The one
## exception is deliberate: forward is the home direction, so an accelerate key
## held through the stop in reverse engages forward after FORWARD_ENGAGE_GRACE
## and drives away in one motion. `drive` is the same signal the speed update
## uses, so both keys held cancel out and never engage anything.
func _update_direction(speed: float, drive: float, delta: float) -> void:
	var accelerate_pressed := Input.is_action_pressed("accelerate")
	var brake_pressed := Input.is_action_pressed("brake")
	var fresh_accelerate := accelerate_pressed and not _accelerate_was_pressed
	var fresh_brake := brake_pressed and not _brake_was_pressed
	_accelerate_was_pressed = accelerate_pressed
	_brake_was_pressed = brake_pressed
	if reverse_engaged and drive > 0.0 and absf(speed) <= STANDSTILL_SPEED:
		_forward_engage_timer += delta
		if _forward_engage_timer >= FORWARD_ENGAGE_GRACE:
			reverse_engaged = false
	else:
		_forward_engage_timer = 0.0
	if fresh_accelerate == fresh_brake:
		return
	if fresh_brake and not reverse_engaged and absf(speed) <= STANDSTILL_SPEED:
		reverse_engaged = true
	elif fresh_accelerate and reverse_engaged and speed >= -STANDSTILL_SPEED:
		reverse_engaged = false


## What the pedals ask of the wheels this tick, as { engine, brake }, and the
## gearbox and engine RPM update on the way. `engine` is the force at the
## driven wheels [N], signed along the nose: drive under throttle, engine
## braking with the throttle closed, reverse gear. `brake` is the total brake
## force asked for [N], always positive; it works against the way each wheel
## rolls. `drive` is +1 for the accelerate key and -1 for the brake key.
func _longitudinal_demand(speed: float, drive: float, delta: float) -> Dictionary:
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

	# Engine force at the driven wheels: drive under throttle, engine braking
	# with the throttle closed. Both need the clutch in and a gear engaged.
	var engine := 0.0
	if reversing:
		if drive < 0.0 and not braking:
			# Tails off into the top speed in reverse (a rev limiter).
			engine = -clampf((speed + MAX_REVERSE_SPEED) * REVERSE_LIMITER_RATE, 0.0, REVERSE_ACCEL * -drive) * CAR_MASS
	elif gear > 0 and not is_shifting:
		var ratio: float = GEAR_RATIOS[gear] * FINAL_DRIVE
		if throttle > 0.0:
			engine = engine_torque(engine_rpm) * throttle * ratio * DRIVETRAIN_EFFICIENCY / WHEEL_RADIUS
		elif speed > STANDSTILL_SPEED:
			engine = -ENGINE_BRAKE_TORQUE_PER_RPM * maxf(engine_rpm - IDLE_RPM, 0.0) * ratio / WHEEL_RADIUS
	var brake := BRAKE_DECEL * absf(drive) * CAR_MASS if braking else 0.0
	return {"engine": engine, "brake": brake}


## Share of the engine's force that goes to the front axle (0..1).
func _front_drive_share() -> float:
	match driven_wheels:
		DrivenWheels.FWD:
			return 1.0
		DrivenWheels.AWD:
			return TORQUE_DISTRIBUTION
	return 0.0


## One tick of an axle's slip ratio. `demand` is the force the engine and the
## brakes ask of the axle as a share of its grip, signed along the nose. Below
## the tyre's limit the wheel settles at the slip where the tyre's force along
## the wheel matches the demand; ask for more than the tyre has left (less,
## the harder it is cornering) and the slip runs away: wheelspin, up to
## DRIVE_SLIP_RATIO, with the force easing towards TYRE_SLIDE_GRIP and the
## sideways hold going with it. Under the foot brake the ABS holds the wheel at
## ABS_SLIP_RATIO instead, it never locks; only the handbrake locks wheels.
## This is the wheel's spin-up written as a relaxation: no wheel speed is
## carried, so nothing divides by a road speed going to zero. The step divides
## by the tyre curve's slope (semi-implicit), which keeps it stable at any tick
## length on the steep part of the curve.
func _advance_slip_ratio(slip_ratio: float, demand: float, slip_angle: float, peak_slip_angle: float, abs_active: bool, delta: float) -> float:
	var force := _tyre_force(slip_ratio, slip_angle, peak_slip_angle).x
	var probe := 0.01 * PEAK_SLIP_RATIO
	var slope := maxf((_tyre_force(slip_ratio + probe, slip_angle, peak_slip_angle).x - force) / probe, 0.0)
	var gain := SLIP_RATIO_RESPONSE * delta
	var limit := ABS_SLIP_RATIO if abs_active else DRIVE_SLIP_RATIO
	demand = clampf(demand, -2.0, 2.0)
	var next := clampf(slip_ratio + gain * (demand - force) / (1.0 + gain * slope), -limit, limit)
	if (demand - force) * (demand - _tyre_force(next, slip_angle, peak_slip_angle).x) < 0.0:
		# Stepped over the slip where force and demand balance (a wheel hooking
		# up again after a lift): home in on it instead of overshooting into
		# the opposite force.
		var near := slip_ratio
		for i in 8:
			var middle := (near + next) * 0.5
			if (demand - force) * (demand - _tyre_force(middle, slip_angle, peak_slip_angle).x) > 0.0:
				near = middle
			else:
				next = middle
		next = (near + next) * 0.5
	return next


## Force of an axle's tyres as a share of their grip: x along the wheels
## (positive = pushing the car towards its nose), y across them (positive =
## pushing it to the right). Combined slip: the slip ratio (in peak slip
## ratios) and the tangent of the slip angle (in that of the peak slip angle)
## are the two components of ONE slip vector. Its length goes through the
## tyre curve, and the force points against it. That is the friction circle:
## a tyre has one grip to give, and it gives it against the way its contact
## patch slides over the road. Pure cornering and pure drive get the plain
## curve; drive or braking in a corner takes from the sideways force; a locked
## wheel (slip ratio -1) just drags against its direction of travel, with next
## to no sideways hold at small slip angles.
## The exception is MIN_COMBINED_GRIP: under drive and ABS braking the
## sideways force never drops below that share of what the slip angle alone
## would give. A wheel on its way to locked (the handbrake) loses the floor.
func _tyre_force(slip_ratio: float, slip_angle: float, peak_slip_angle: float) -> Vector2:
	var along := slip_ratio / PEAK_SLIP_RATIO
	var across := tan(slip_angle) / tan(peak_slip_angle)
	var slip := Vector2(along, across).length()
	if slip < 0.0001:
		return Vector2.ZERO
	var share := _tyre_curve(slip) / slip
	var floor_share := MIN_COMBINED_GRIP * (1.0 - smoothstep(DRIVE_SLIP_RATIO, 1.0, absf(slip_ratio)))
	var sideways := maxf(share * absf(across), floor_share * absf(_tyre_curve(across)))
	return Vector2(share * along, -sideways * signf(across))


## Share of a tyre's grip that goes along the wheel at `slip_ratio` (0..1), for
## tests and the HUD: the tyre curve up to the peak, all of it from there.
func _traction_use(slip_ratio: float) -> float:
	var x := absf(slip_ratio) / PEAK_SLIP_RATIO
	return 1.0 if x >= 1.0 else absf(_tyre_curve(x))


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


## Most force [N] the tyres of an axle can make, in any direction, under
## `load` [N] when the axle carries `static_load` [N] at rest: TYRE_MU times
## the load at rest, sub-linear in load from there (LOAD_GRIP_EXPONENT).
func _axle_grip(load: float, static_load: float) -> float:
	return TYRE_MU * static_load * pow(maxf(load, 0.0) / static_load, LOAD_GRIP_EXPONENT)


## The tyre curve: share of the peak force (-1..1) at `slip`, the slip angle in
## peak slip angles (or the slip ratio in peak slip ratios). Rises smoothly into the peak at 1 (slope 1.5 at
## zero, flat at the top), then eases down to TYRE_SLIDE_GRIP.
func _tyre_curve(slip: float) -> float:
	var x := absf(slip)
	if x <= 1.0:
		return slip * (3.0 - x * x) * 0.5
	var sliding := 1.0 - exp(-(x - 1.0) / TYRE_SLIDE_ONSET)
	return signf(slip) * lerpf(1.0, TYRE_SLIDE_GRIP, sliding)


## Caps a tyre `force` [N] at what stops its contact patch's `slip_speed` [m/s]
## in the force's direction within this tick. A push at an axle `arm` metres from the centre of
## mass moves that axle as if it weighed 1 / (1 / mass + arm^2 / yaw inertia).
func _limit_to_stick(force: float, slip_speed: float, arm: float, yaw_inertia: float, delta: float) -> float:
	var stopping_force := absf(slip_speed) / ((1.0 / CAR_MASS + arm * arm / yaw_inertia) * delta)
	return clampf(force, -stopping_force, stopping_force)


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


# Was _slide_feed() and _steering_lock() here -> removed with raw steering. The
# first took lock held into a slide off the front wheels and let them trail
# into line with the way the front travelled; the second set full lock a
# tyre's peak slip past that travel angle, so it moved with the car. Both
# turned the wheels without the driver. wheel_angle is steer * MAX_STEER_LOCK
# (see step 3 of _physics_process); there is nothing to compute any more.


## Cosmetic motion: wheel spin, front wheel steering and body roll / pitch.
func _update_visuals(delta: float) -> void:
	# Each axle turns at road speed plus its slip: driven wheels visibly spin
	# up when they break traction, handbraked rears stand still.
	var rolling := forward_speed / WHEEL_RADIUS
	var front_spin := clampf(rolling * (1.0 + front_slip_ratio * signf(forward_speed)), -MAX_WHEEL_SPIN, MAX_WHEEL_SPIN)
	var rear_spin := clampf(rolling * (1.0 + rear_slip_ratio * signf(forward_speed)) * (1.0 - _handbrake_amount), -MAX_WHEEL_SPIN, MAX_WHEEL_SPIN)
	for i in _wheel_spinners.size():
		# Rolling towards -Z is a negative rotation about +X.
		_wheel_spinners[i].rotate_x(-(front_spin if i < 2 else rear_spin) * delta)

	for wheel in _front_wheels:
		wheel.rotation.y = wheel_angle

	# Each wheel stays on the road while the body rides the elevation.
	for i in _wheels.size():
		_wheels[i].position.y = _wheel_rest_height + clampf(_wheel_travel[i], -MAX_WHEEL_VISUAL_TRAVEL, MAX_WHEEL_VISUAL_TRAVEL)

	# Weight transfer: the body leans out of the corner, squats under power and
	# dives under braking.
	var target_roll := clampf(-lateral_accel * BODY_ROLL_PER_ACCEL, -MAX_BODY_TILT, MAX_BODY_TILT)
	var target_pitch := clampf(longitudinal_accel * BODY_PITCH_PER_ACCEL, -MAX_BODY_TILT, MAX_BODY_TILT)
	var blend := 1.0 - exp(-BODY_TILT_RESPONSE * delta)
	_body.rotation.z = lerpf(_body.rotation.z, target_roll, blend)
	_body.rotation.x = lerpf(_body.rotation.x, target_pitch, blend)
