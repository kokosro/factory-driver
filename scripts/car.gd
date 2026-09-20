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
## (the axle's wheel speed, a state wound up and down by drive, brake and tyre
## torque, vs the road speed under it) gives the force along the wheel from
## the same curve. Both share one friction circle:
## grip spent along the wheel is not there across it. The forces act at the
## contact patches, along and across each wheel's heading: their sum
## accelerates the 1300 kg, their moments about the centre of mass (front force
## x front arm, rear force x rear arm) wind the yaw inertia up and down
## (YAW_GYRATION_RADIUS). Heading and direction of travel are separate things,
## tied together only by the tyres. The steering sets the front wheel angle
## and nothing else.
##
## Drivetrain: a chain of things that turn, each with its own speed and its own
## inertia, tied together by torque. The ENGINE speed is integrated from what
## the fuel makes (torque curve x throttle) less its friction, against
## ENGINE_INERTIA: it free-revs in neutral, bounces off a fuel-cut limiter and
## idles on a controller. The CLUTCH passes a friction torque while its two
## sides turn at different speeds (pulling away, after a gear change) and locks
## them into one shaft once they have met; locked, the engine's inertia rides
## on the driven axle through the gear ratio squared, which is what dulls 1st
## gear and makes engine braking a matter of gear. The 5-speed GEARBOX and the
## final drive put that torque on the DRIVEN wheels (DRIVEN_WHEELS: rear, front
## or all four), and each axle's WHEEL SPEED is a state too, between driveline,
## brakes and the road (_advance_drivetrain). Nothing in the chain follows road
## speed by decree: the tach reads what the engine does.
## The driven wheels are where the layouts get their character, nobody scripts it: a
## rear-driven car spends rear grip on drive and pushes from behind, so power
## in a corner loosens the tail (power oversteer); a front-driven car asks its
## front tyres to pull and steer at once, so power pushes the nose wide and a
## launch is traction-limited as the load moves off the driven axle; all-wheel
## drive splits the torque (TORQUE_DISTRIBUTION) and sits in between. The
## brakes split their force front / rear (BRAKE_BIAS_FRONT), each axle capped
## by its own grip; the handbrake locks the rear wheels, which then only drag
## against their direction of travel, so the tail comes round.
##
## Weight, suspension and aero: the body is a rigid mass on four springs, with
## heave, pitch and roll as states of their own (see Suspension). What each
## spring pushes up with is its wheel's load, and the axle loads the tyres work
## with are the sums of their two wheels (wheel_loads): at rest the static
## weight distribution, to the Newton. Nothing scripts weight transfer: the
## tyres pull at the road, CG_HEIGHT below the centre of mass, so braking dives
## the nose into the front springs and the front tyres carry more; power squats
## the tail, cornering rolls the body onto the outside wheels. Downforce
## (DOWNFORCE_COEFF) presses on the body and reaches the tyres through the
## springs too. Each axle's grip follows its load.
##
## The road: the car drives on a RoadProfile (road_profile), a height field,
## and every wheel follows it in full, swell, micro-bumps and all. The springs
## carry the body over it: a bump pushes load into its wheel, a crest dropping
## away faster than the body can fall after it takes load off (past the droop
## stop the wheel is in the air), the swell lifts and lowers the whole car.
## The tyre model itself knows nothing of any of this. On a flat road every
## wheel carries exactly its share.
##
## Two helpers sit on top, both documented where they live: below
## LOW_SPEED_BLEND_END the tyre forces are blended with plain rolling geometry
## (a force model degenerates at a standstill), and an arcade stability assist
## damps the nose swinging relative to the direction of travel; it fades at big
## slip angles (SPIN_COMMIT_ANGLE), so a committed flick becomes a 180 or a
## 360.
##
## Conventions: the car's nose points along local -Z, +X is the car's right,
## positive yaw (rotation about +Y) is a LEFT turn, positive pitch (about +X)
## is NOSE UP, positive roll (about +Z) is RIGHT SIDE UP. The CharacterBody3D
## itself stays upright, pitch and roll are small angles of the body on it: the
## road's slopes are gentle (RoadProfile.MAX_SLOPE), the springs push straight
## up and gravity never pulls the car downhill. Without a road_profile the
## ground is level (true for a bare car.tscn).

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

## Engine speed with no load [rpm]. The tach never reads lower while running:
## the idle controller (see _engine_net_torque) opens the throttle by itself as
## the revs come down to this, and holds them there. The engine idles from
## _ready on; a cold start is out of scope, there is no starter and no stall.
const IDLE_RPM := 900.0

## Rev limiter [rpm]: a fuel cut. At this speed the engine stops firing and
## falls back on its own friction until LIMITER_RESUME_RPM, then fires again:
## held against it, the revs bounce between the two (~8 times a second with
## no load). Free, the engine never turns faster than this; in gear the car's
## momentum can carry it a few rpm past before the cut bites.
const REDLINE_RPM := 7200.0

## Engine speed at which the rev limiter lets the fuel back in [rpm].
const LIMITER_RESUME_RPM := 7000.0

## Moment of inertia of what turns with the crankshaft [kg m^2]: crank,
## flywheel, clutch cover. 0.25 is the order of the real 986's flat six with
## its dual-mass flywheel. The engine speed is a state of its own, wound up and
## down by torque against this: d(omega) / dt = net torque / ENGINE_INERTIA.
## With no load, full throttle takes it from idle to the limiter in ~0.8 s.
## Lower = revs that snap up and down, higher = a lazy engine.
const ENGINE_INERTIA := 0.25

## Friction and pumping losses of the engine [Nm]: ENGINE_FRICTION_TORQUE
## whatever the speed, plus ENGINE_FRICTION_TORQUE_PER_RPM [Nm per rpm] for
## every rpm it turns: ~18 Nm at idle, ~61 Nm at 7000 rpm. What slows the revs
## with the throttle closed (let go at the limiter in neutral, they are back
## at idle in ~4 s), and, through a locked clutch and the gear, the engine
## braking. The shape is the old ENGINE_BRAKE_TORQUE_PER_RPM's (0.01 Nm per rpm
## above idle, ~61 Nm at 7000), now a torque on the crankshaft that is there at
## idle too; 15 + 0.01 had the revs down in 3.5 s but, through 1st, put the
## rear tyres at their ABS limit under braking from 60 km/h. TORQUE_CURVE is torque at the flywheel, these
## losses already taken off: what the burning fuel makes at full throttle is
## the curve plus the losses, and the throttle scales that.
const ENGINE_FRICTION_TORQUE := 12.0
const ENGINE_FRICTION_TORQUE_PER_RPM := 0.007

## Idle controller: torque it adds per rad/s the engine is below IDLE_RPM, on
## top of what carries the friction there [Nm per rad/s]; 2.5 against
## ENGINE_INERTIA closes a gap at 10 per second, no overshoot ...
const IDLE_CONTROL_GAIN := 2.5

## ... and the most throttle it may open by itself (0..1): ~35 Nm net at idle.
const IDLE_CONTROL_MAX_THROTTLE := 0.3

# was ENGINE_BRAKE_TORQUE_PER_RPM 0.01 (an explicit engine-brake force at the
# wheels) -> removed with the kinematic engine speed: engine braking is
# ENGINE_FRICTION_TORQUE* through the locked clutch and the gear.
# LAUNCH_RPM moved to the Clutch section, where it means something now.

# --- Gearbox -----------------------------------------------------------------

## Gear ratios; index 0 is neutral, 1..5 the forward gears (986 5-speed).
const GEAR_RATIOS: Array[float] = [0.0, 3.82, 2.20, 1.52, 1.22, 0.97]

## Final drive (differential) ratio.
const FINAL_DRIVE := 3.89

## Reverse gear ratio: a gear like the others, engine, clutch and driven wheels
## work through it the same way (the wheels turning backwards).
# was tach-only, the drive force in reverse a flat REVERSE_ACCEL x CAR_MASS ->
# the real thing. What is left of the flat force is the driver's foot easing
# off into MAX_REVERSE_SPEED (see _pedals).
const REVERSE_RATIO := 3.55

## Share of engine torque that reaches the wheels (0..1); the rest is lost in
## the gearbox and differential.
const DRIVETRAIN_EFFICIENCY := 0.88

## Rolling radius of the tyres [m]; must match the wheel mesh. Turns wheel
## torque into force and wheel speed into engine RPM.
const WHEEL_RADIUS := 0.34

# --- Clutch --------------------------------------------------------------------

# A dry plate between the engine and the gearbox, worked by the car (there is
# no clutch pedal): see _clutch_target for when it opens and closes. Slipping,
# it passes a friction torque from the faster side to the slower one, the same
# torque on both; once the two sides turn together it locks and they are one
# shaft (see _advance_drivetrain).

## Most torque the clutch passes fully engaged [Nm]. Road car clutches are sized
## at 1.5 - 2.5 times the engine's peak torque so they never slip once home;
## ~2 x 245 Nm. It is also the most the clutch can push into the driveline
## while it drags a fast-turning engine down after a shift or a launch: more
## than the engine itself ever makes. Higher = harsher catches.
const CLUTCH_TORQUE_MAX := 500.0

## Pulling away, the car feathers the clutch so the engine is not dragged
## under a floor [rpm]: IDLE_RPM with the throttle closed, this at full
## throttle, in between in between. While the gearbox side is slower than that
## the clutch slips and passes no more than the engine can give without
## falling under the floor: flat out the revs flare to the engine's torque peak
## and sit there, all 245 Nm going into the car, until the wheels have caught
## up. A clutch simply let in would drag the engine down to idle and its
## 160 Nm before the car has moved a length.
# was LAUNCH_RPM 2000, a clamp on the tach alone ("the clutch slips", though
# nothing slipped and the drive force never knew) -> 4500, the speed a real
# slipping clutch holds the engine at, with the torque that goes with it.
# was 3500 (232 Nm) -> 4000 (238 Nm) with the real suspension - at 3500 the
# launch sat on the edge of the rear tyres' limit and only reached it the tick
# the clutch locked: 0.99967 of the peak force with the old eased load transfer
# (the smoke test asks for 0.999), 0.99864 now that the squatting tail carries
# its full share at that moment (9488 N on the rear axle against 9378). At 4000
# the rears are worked past their peak before the clutch is home (slip ratio
# 0.100 at 26 km/h, use 1.000), which is what "traction-limited" is meant to
# say; 9.6 m/s after 2 s against 9.5, the clutch home after 1.83 s against 1.63.
const LAUNCH_RPM := 4000.0

## While the revs are still under that floor the clutch takes this share of
## the engine's torque (0..1) and the rest winds the engine up: the car moves
## off at once, gently, and harder as the revs arrive ...
const LAUNCH_CLUTCH_SHARE := 0.5

## ... over the last this many rad/s (~500 rpm) under the floor the share eases
## up to all of it, so the clutch bites over a few ticks and not in one.
const LAUNCH_BITE_BAND := 50.0

## Time the clutch takes to come in from fully open pulling away [s]: the
## torque it can pass ramps up over this, the engine flares against it and the
## car moves off on the slip torque.
const CLUTCH_ENGAGE_TIME := 0.5

## The same on the move, after a gear change [s]: the revs the engine has too
## many (upshift) or too few (downshift) are dragged to the new gear's speed
## within about this. Shorter = quicker, harsher shifts.
const CLUTCH_SHIFT_ENGAGE_TIME := 0.1

## Downshifts: while the clutch is open the driver blips the throttle towards
## the speed the lower gear will turn the engine at, wide open until this close
## to it [rad/s] (~300 rpm), easing off from there. The engine has 0.2 s and
## its own torque to get there (~1500 rpm at most); what is still missing when
## the clutch comes back in, the clutch drags out of the car. Without the blip
## it is all dragged out of the car: a 2nd-to-1st change at 42 km/h asks the
## rear tyres for 2000 rpm of engine through 1st gear, more than they have, and
## they lock for a moment. Upshifts need none: the engine has revs to lose and
## loses them into the clutch.
const DOWNSHIFT_BLIP_BAND := 30.0

## Slipping, the friction torque follows the sign of the speed difference
## across the clutch; within this band [rad/s] (~50 rpm) it eases through zero
## instead of flipping, and inside it the clutch can lock.
const CLUTCH_SLIP_BAND := 5.0

## With the throttle closed the clutch opens when the gearbox would turn the
## engine slower than this [rpm]: coming to a stop in gear the engine is let
## go a little above idle instead of being stalled.
const CLUTCH_DISENGAGE_RPM := 1000.0

## How far the clutch stays in (0..1) while the car rolls AGAINST the selected
## gear with the pedals released (backwards in a forward gear, out of a spin):
## a light drag, ~10 Nm at the clutch, ~430 N at the wheels in 1st, the idling
## engine leaning against the roll.
# was an explicit engine-brake force either way round (iteration 2I: "the
# engine is a pump, it holds back a car rolling backwards in a forward gear") ->
# absorbed into the clutch - rolling forwards the engine braking now comes out
# of the engine's friction through the locked clutch, per gear. Rolling
# backwards a locked clutch would turn the engine backwards, which it cannot;
# what a driveline can honestly do there is slip, so the old floor lives on as
# this drag: the torque goes through the clutch, loads the idling engine (the
# idle controller carries it) and reaches the driven wheels through the gear.
# ~0.33 m/s^2 in 1st on top of rolling resistance, was 0.17 at 3.7 m/s.
const CLUTCH_DRAG_ENGAGEMENT := 0.02

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
## in any direction (1997 road tyres, ~0.95). Through 1st the engine's torque
## from ~3000 rpm would be more than the rear tyres can transmit, and on a
## slipping clutch (the launch) it is; with the clutch locked a quarter of it
## winds up the engine's own inertia and the rears run just under their peak.
## 2nd and up stay well under it.
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

## Slip ratio the driver's feet hold a spinning driven wheel at while the
## clutch slips and passes more than the tyre can take (no unit): pulling away
## flat out, dropping the clutch on a revving engine. On / off keys cannot
## feather anything, so this does (_ease_for_wheelspin). 0.25 is proper
## wheelspin, 2.5 times the peak: the tyre pushes with ~0.9 of its grip and has
## little left for holding the car sideways (MIN_COMBINED_GRIP is what it
## keeps, fading out from here to a slip ratio of 1). Higher = wilder
## wheelspin off the line, less drive.
# was a clamp on the slip ratio itself, whatever wound it up -> the clutch
# foot's limit while the clutch slips. With the clutch locked nothing holds the
# wheels back but the engine's own inertia and the limiter: what the throttle
# spins up, the throttle has to let go again.
const DRIVE_SLIP_RATIO := 0.25

## A slip angle is sideways speed over rolling speed; this is the least
## rolling speed it is worked out against [m/s]. Keeps the angle (and its
## tangent) finite with a tyre moving dead sideways, and stops the last
## millimetres per second of a car coming to rest reading as 90 degrees of
## slip.
const SLIP_ANGLE_MIN_SPEED := 1.0

## A slip ratio is a speed difference over the road speed; this is the least
## road speed it is worked out against [m/s], as SLIP_ANGLE_MIN_SPEED is for
## slip angles. At a standstill a slip ratio is then simply the wheel's surface
## speed in m/s: the tyre makes its peak force turning 0.1 m/s faster than the
## road, which is how a launch starts, and a car at rest on wheels at rest has
## slip 0 and no force. Smaller = a harsher bite pulling away.
const SLIP_RATIO_MIN_SPEED := 1.0

## Moment of inertia of an axle's two wheels [kg m^2]: ~1.2 each (a 20 kg wheel
## and tyre with its mass ~0.24 m out), brake discs and half shafts in. What
## torque has to wind up before a wheel spins, and what the brakes have to
## stop. Small next to everything else (as a mass at the tyre it is ~21 kg), so
## a free axle follows the road within a tick; the engine hanging on the driven
## one through a locked clutch is what makes wheelspin slow (see
## _advance_drivetrain).
# was SLIP_RATIO_RESPONSE 12.0 [1/s], a relaxation rate that "stands in for the
# wheel's inertia" -> removed: the wheel speed is a state and this is its
# inertia.
const AXLE_INERTIA := 2.4

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
## The front tyres' figure, and a locked rear's; rear tyres that still roll
## have their own (REAR_TYRE_SLIDE_GRIP).
const TYRE_SLIDE_GRIP := 0.85

## How far past the peak the tyre is ~two thirds of the way down to
## TYRE_SLIDE_GRIP, in peak slip angles. Higher = a wider, more forgiving top.
const TYRE_SLIDE_ONSET := 2.0

## The same for rear tyres that still roll (0..1): the wide rears hold on in a
## slide where the fronts let go. This is what ends a slide nobody is driving:
## with both ends sliding the yaw moments of the two axles nearly cancel (the
## REAR / FRONT_TYRE_GRIP margin of 1.106 is eaten by the weight a sliding,
## slowing car moves onto its nose, x0.94, and by the rear sliding deeper down
## the curve than the front, x0.98), and the more the sliding rear holds over
## the sliding front, the harder the tail is pulled back into line. A grip
## figure like the rest: it knows nothing of the steering or the heading. A
## locked wheel stays on TYRE_SLIDE_GRIP (eased over by the handbrake, see
## HANDBRAKE_RECOVERY_RATE), so the handbrake kicks the tail out and carries a
## spin as before. Lower = slides hang on longer, equal to TYRE_SLIDE_GRIP = a
## slide with the keys released carries on as a drift.
# was TYRE_SLIDE_GRIP 0.85 for both axles -> 1.0 at the rolling rear - a 0.2 s
# flick of the handbrake at 85 km/h, every key released: the nose took 3.83 s
# to come back in line with the travel (within 0.1 rad) and the car turned
# 115 degrees on the way, a drift held at 0.28 rad with a net yaw moment of
# ~2 % of either axle's; now 2.10 s and 60 degrees. The same at 58 km/h:
# 2.23 s / 102 degrees -> 1.57 s / 70. A deeper slide (0.67 s of handbrake at
# 58 km/h) used to end creeping backwards, at rest after 10.28 s; now it stops
# nose-first after 2.55 s. Lowering the shared figure instead went the wrong
# way (0.75: 6.02 s / 210 degrees), 1.0 for both got 2.65 s and flattens the
# front's limit too; more rear-biased REAR / FRONT_TYRE_GRIP (1.052 / 0.92)
# stopped the 180 at 138 degrees, and less SLIDE_RECOVERY_ASSIST (0.2) brought
# back the swing past straight after a jab at speed. It only counts for slip
# across the wheel (see _tyre_force): wheelspin and the launch are untouched
# (12.0 m/s after 2 s, as before). Certified runs before -> after: SPIN_180
# 179.9 degrees, slalom closest pass 2.1 m and stop box margin 0.9 m all
# unchanged, SPIN_360 361.9 -> 362.4, REVERSE_180 -174.1 -> -181.8.
const REAR_TYRE_SLIDE_GRIP := 1.0

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
## (this times CAR_MASS) is split by BRAKE_BIAS_FRONT, put on each axle as a
## brake torque (with what it takes to slow the turning parts down as well,
## see _brake_torque), and each axle delivers what its grip allows (ABS holds a
## wheel at ABS_SLIP_RATIO, it never locks):
## with the fronts at their limit and the rears under theirs, a real stop
## comes out at ~0.9 of this, ~8.4 m/s^2 plus drag.
const BRAKE_DECEL := BRAKE_DECEL_G * TYRE_MU * 9.8

## Density of air [kg/m^3], for the drag force.
const AIR_DENSITY := 1.225

## Rolling resistance [m/s^2], always on while the car rolls. With engine
## braking and aero drag it makes up the coast-down.
const COAST_DECEL := 0.15

## Acceleration the driver counts on in reverse gear [m/s^2], about what the
## engine gives through REVERSE_RATIO: with REVERSE_LIMITER_RATE it says how
## far short of MAX_REVERSE_SPEED the foot starts to ease off the throttle.
# was the drive force in reverse itself (this times CAR_MASS, flat) -> the
# engine drives the car in reverse as it does forwards; measured ~5 m/s^2
# through the middle of the rev range, the rear tyres unloaded by it.
const REVERSE_ACCEL := 6.0

## Top speed in reverse [m/s]. 12 m/s is about 43 km/h.
const MAX_REVERSE_SPEED := 12.0

## How sharply the throttle in reverse tails off into MAX_REVERSE_SPEED [1/s]:
## the share of REVERSE_ACCEL the foot still asks for is this times the speed
## still to go, so 4.0 starts easing off 1.5 m/s short of the top and the car
## settles a little under it, where what throttle is left carries the drag.
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

## Time a gear change takes [s]. The clutch is open meanwhile and the driver's
## foot off the throttle: no drive torque, no engine braking, and the engine
## on its own, drifting down on its friction. Then the clutch comes back in
## (CLUTCH_SHIFT_ENGAGE_TIME) and drags the engine to the new gear's speed:
## down after an upshift, the revs it gives up pushing the car for a moment; up
## after a downshift, the car paying for them.
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

# was RPM_RESPONSE 20.0 [1/s], how quickly the engine speed followed a target
# worked out from road speed and gear -> removed. The engine speed has no
# target any more: it is integrated from torque against ENGINE_INERTIA, and
# how fast the revs drop across an upshift is CLUTCH_TORQUE_MAX dragging that
# inertia down (CLUTCH_SHIFT_ENGAGE_TIME).

# --- Weight transfer ---------------------------------------------------------

## How strongly axle load changes axle grip: grip is TYRE_MU * static load *
## (load / static load) ^ exponent. Below 1 = tyres gain grip slower than
## load, as real tyres do, so moving weight onto one axle costs the other one
## more than it gains: the balance shift is felt. 0 = no effect.
const LOAD_GRIP_EXPONENT := 0.7

# was MAX_LOAD_TRANSFER 0.18 (largest share of the weight that could move
# between the axles) and LOAD_TRANSFER_RESPONSE 8.0 [1/s] (the pace of a formula
# that moved it: acceleration x CG_HEIGHT / wheelbase, eased in "at the
# suspension's pace") -> both removed - there is a suspension now, and weight
# transfer is what it does: the tyre forces act at the road, CG_HEIGHT under the
# centre of mass, the body pitches against its springs and the springs carry
# the difference (see Suspension, _advance_body). Steady state that is the same
# CAR_MASS x acceleration x CG_HEIGHT / wheelbase the formula had, which the
# smoke test now holds the springs to as a cross-check (_wheel_baselines); on
# the way there the body pitches at ~1.5 Hz instead of easing at 8 per second.
# Measured in the smoke test: a full stop from 108 km/h moves 1976 N onto the
# front axle where the formula says 2115 (the rest is the dive still swinging),
# a 0.88 g corner puts 6243 N more on the outside pair than on the inside where
# statics says 6215; the front share under braking from 185 km/h reads 0.54
# against 0.53. The 0.18 cap never bound (tyre-limited braking moves 0.17) and
# has no successor: what bounds it now is the tyres, and the bump stops.

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

# --- Suspension ----------------------------------------------------------------

# The body is a rigid mass on four springs. It has three ways to move on them,
# each a state with its rate: HEAVE (up and down: the CharacterBody3D's own
# height and vertical velocity, gravity pulling it down), PITCH and ROLL (small
# angles, body_pitch / body_roll). Each corner of the body stands on its wheel
# through a spring, a damper, a share of its axle's anti-roll bar and, at the
# ends of the travel, a bump stop; the wheel follows the road (there is no
# unsprung mass: tyre and wheel are part of the road as far as the spring is
# concerned, the tyre's give is TYRE_ENVELOPE_RATE). What each spring pushes up
# with is what its tyre presses on the road with: that IS the wheel load
# (wheel_loads), and the grip. Nothing else moves load around: braking dives
# the nose because the tyres pull back at the road, CG_HEIGHT under the centre
# of mass, and the front springs have to carry the moment; cornering rolls the
# body the same way; a crest drops away and the springs stretch after it.
# See _corner_forces and _advance_body.
#
# was (iteration 2G) a load LAYER: RIDE_FREQUENCY 1.4 Hz and RIDE_DAMPING_RATIO
# 0.4 on four independent corner masses whose only job was to add a ripple to
# wheel loads that came out of the weight-transfer formula, under a body that
# followed the road's elevation kinematically (the elevation follow, a teleport
# by the elevation change after every move -> removed) and leaned by a cosmetic rule
# (BODY_ROLL_PER_ACCEL and friends -> removed, see Visual only) -> one rigid
# body on real springs, which does all three.

## Ride frequency of each end of the car on its springs [Hz]: how fast a corner
## mass (FRONT / REAR_CORNER_MASS) bounces on its spring alone. Road cars 1 -
## 1.5, sports cars 1.5 - 2. The rear is set ~13 % above the front, as on real
## cars ("flat ride": the rear hits every bump a wheelbase later and has to
## catch the front up, or the car pitches along the road).
# was RIDE_FREQUENCY 1.4 for all four corners -> 1.5 / 1.7 - the springs now
# also hold the body against dive and roll: in a full stop from 142 km/h 1.4
# all round dived 0.028 rad and ran the front springs 7.7 cm in, onto their
# bump stops (travel 7); 1.5 / 1.7 dives 0.022 rad and peaks at 6.8 cm, 5 cm
# once the first swing is over. And no flat ride with the two ends the same.
const FRONT_RIDE_FREQUENCY := 1.5
const REAR_RIDE_FREQUENCY := 1.7

## Damping ratio of each corner on its spring (no unit): 0.3 - 0.5 on a road
## car. 1 would settle without any overshoot, lower floats on after a crest.
## Unchanged from 2G; it now also damps pitch (ratio ~0.4, the car's pitch
## inertia being what its corner masses make it) and roll (~0.43 with the bars).
const RIDE_DAMPING_RATIO := 0.4

## Sprung mass riding on one front / rear wheel at rest [kg]: ~247 and ~403.
const FRONT_CORNER_MASS := CAR_MASS * (1.0 - REAR_WEIGHT_FRACTION) * 0.5
const REAR_CORNER_MASS := CAR_MASS * REAR_WEIGHT_FRACTION * 0.5

## Spring rate at the wheel [N/m]: corner mass x (TAU x ride frequency)^2.
## Front ~21.9 kN/m, rear ~46.0 kN/m (static compression 11.0 and 8.6 cm).
const FRONT_SPRING_RATE := FRONT_CORNER_MASS * (TAU * FRONT_RIDE_FREQUENCY) * (TAU * FRONT_RIDE_FREQUENCY)
const REAR_SPRING_RATE := REAR_CORNER_MASS * (TAU * REAR_RIDE_FREQUENCY) * (TAU * REAR_RIDE_FREQUENCY)

## Damper rate at the wheel [N s/m]: 2 x ratio x corner mass x TAU x ride
## frequency. Front ~1860, rear ~3440. One rate for bump and rebound.
const FRONT_DAMPER_RATE := 2.0 * RIDE_DAMPING_RATIO * FRONT_CORNER_MASS * TAU * FRONT_RIDE_FREQUENCY
const REAR_DAMPER_RATE := 2.0 * RIDE_DAMPING_RATIO * REAR_CORNER_MASS * TAU * REAR_RIDE_FREQUENCY

## Anti-roll bars [N per m of travel difference between an axle's two wheels]:
## the bar pushes the more compressed wheel down and lifts the other with this
## times the difference. Does nothing in heave and pitch. With the springs
## (~100 kNm/rad of roll stiffness on the 1.72 m track) the bars add ~38: the
## body rolls ~2.5 degrees per g, a sports car's figure; on springs alone it
## would be 3.6. Front-biased, as on the real car. The tyres work with AXLE
## loads (the bicycle model), so how the bars split the roll between the axles
## shows in wheel_loads and in the body, not in the balance of the car.
const FRONT_ANTI_ROLL_RATE := 8000.0
const REAR_ANTI_ROLL_RATE := 5000.0

## Suspension travel either way from the static position [m]: 7 cm of bump and
## 7 cm of droop before the stops.
const SUSPENSION_TRAVEL := 0.07

## Bump stops. Past SUSPENSION_TRAVEL a rubber stop joins the spring, and it is
## progressive: its force is BUMP_STOP_RATE x the corner's spring rate x the
## depth into it x (1 + depth / BUMP_STOP_PROGRESSION), so its stiffness starts
## at 3 springs and has doubled 1 cm in. In bump it pushes the body up; in
## droop it is the damper topping out and takes the last of the spring's push
## off the tyre (at rest the springs are compressed 9 - 11 cm, so without it a
## wheel would stay loaded further down than it can reach): by ~2 cm past the
## travel the wheel is in the air, load 0. Stability: 5 cm into a stop (where
## the body's collision box meets the floor, GROUND_CLEARANCE) the corner's
## stiffness is 19 spring rates, w x delta = 0.78 at 60 ticks a second, where
## semi-implicit Euler holds to 2; on the springs alone it is 0.16 / 0.18, in
## roll with the bars 0.25.
const BUMP_STOP_RATE := 3.0
const BUMP_STOP_PROGRESSION := 0.02

## Moment of inertia of the body in pitch [kg m^2]. A car's two ends bounce
## independently of each other when its pitch gyration radius squared equals
## front arm x rear arm (dynamic index 1), which road cars sit close to:
## 1300 kg x 1.612 m x 0.988 m = 2070. Measured figures for small sports cars
## are 1800 - 2300.
const PITCH_INERTIA := 2100.0

## Moment of inertia of the body in roll [kg m^2]: a gyration radius of ~0.68 m
## on a 1.8 m wide car with its masses low and central (measured road cars:
## 400 - 700). Roll on springs and bars comes out at ~2.4 Hz.
const ROLL_INERTIA := 600.0

## Height of the body's underside (its collision box) above the road at rest
## [m], the 986's ~12 cm. The springs hold the body up; the floor only ever
## meets it 5 cm into the bump stops of all four wheels at once. Must match the
## CollisionShape3D in car.tscn.
const GROUND_CLEARANCE := 0.12

## How quickly the tyre lets the road through to the suspension [1/s], ~6 Hz:
## carcass and contact patch swallow what is shorter than themselves, and at
## speed one physics tick is most of a metre of road. Without it the damper
## would turn every sampled ripple into a hammer blow. Lower = smoother ride,
## calmer wheel loads. (Kept from 2G: it is the tyre's, not the old layer's.)
const TYRE_ENVELOPE_RATE := 40.0

## Half the track width [m]: how far each wheel stands from the car's centre
## line. Must match the wheel positions in car.tscn. (Real 986: 1.47 / 1.53 m
## front / rear track; the placeholder body is wider.)
const HALF_TRACK := 0.86

## Where each tyre meets the road, in the car's frame [m]: front left, front
## right, rear left, rear right (the order of wheel_loads). Must match the
## wheel positions in car.tscn.
const WHEEL_CONTACT_POINTS: Array[Vector3] = [
	Vector3(-HALF_TRACK, 0.0, -AXLE_DISTANCE),
	Vector3(HALF_TRACK, 0.0, -AXLE_DISTANCE),
	Vector3(-HALF_TRACK, 0.0, AXLE_DISTANCE),
	Vector3(HALF_TRACK, 0.0, AXLE_DISTANCE),
]

## Lever arms of each wheel's load about the centre of mass [m], the order of
## wheel_loads: how far AHEAD of it the wheel stands (pitch; the fronts on the
## long arm, the rears behind on the short one) and how far to its RIGHT
## (roll). In full precision, not read back off the Vector3s above (32 bit):
## the static loads times these arms cancel exactly, as they have to for a car
## at rest to stay at rest.
const WHEEL_ARMS_AHEAD: Array[float] = [
	AXLE_DISTANCE + CG_OFFSET, AXLE_DISTANCE + CG_OFFSET, CG_OFFSET - AXLE_DISTANCE, CG_OFFSET - AXLE_DISTANCE,
]
const WHEEL_ARMS_RIGHT: Array[float] = [-HALF_TRACK, HALF_TRACK, -HALF_TRACK, HALF_TRACK]

# --- Steering ----------------------------------------------------------------

## Front wheel angle at full steering lock [rad], ~27.5 degrees: a 5 m
## turning circle radius at parking speed. Raw steering: the front wheel angle
## is the steering wheel's share of its lock (steer) times this, at any speed,
## however sideways the car is, and nothing but the steering wheel moves the
## wheels. What the car does with the angle is
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

## The driver's steering wheel turns this far each way from centre [degrees]:
## 900 degrees lock to lock, two and a half turns, a road car's rack.
const STEERING_WHEEL_LOCK_DEG := 450.0

## How fast the driver's hands turn the steering wheel [degrees per second],
## towards where the steer input asks for it and back to centre on release:
## 1300 is a quick pair of hands (900 degrees lock to lock in 0.69 s, centre to
## lock in 0.35 s), about what a driver manages catching a slide. The keys are
## on / off, the hands are not: a tap is a few degrees of wheel, a held key
## winds lock on at this pace, and countersteer is wound on the same way: a
## slide is caught by steering against it early and in proportion, as far as
## the hands get in the time, not by flicking to opposite lock. The stability
## assist (see Slides) is what it always was and keeps that catchable.
# was STEER_RESPONSE 5.0 [1/s], the steer input easing to the key in 0.2 s
# centre to lock (a wheel spun at 2250 degrees per second, had there been one)
# -> the wheel is a state (steering_wheel_deg) turned at a hand's speed: 0.35 s
# centre to lock, 1.7 times as long.
const STEERING_HAND_SPEED := 1300.0

## Steering ratio: degrees of steering wheel per degree of front wheel. Follows
## from the two ends of the rack, 450 degrees of steering wheel for
## MAX_STEER_LOCK (27.5 degrees) at the front wheels: 16.4 to 1, a road car's
## (the 986's rack is 16.9 to 1). Front wheel angle = steering wheel angle /
## this, at any speed, however sideways the car is.
const STEERING_RATIO := STEERING_WHEEL_LOCK_DEG / (MAX_STEER_LOCK * 180.0 / PI)

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
# against whatever way it is moving with TYRE_SLIDE_GRIP of its grip (not the
# rolling rear's REAR_TYRE_SLIDE_GRIP): rolling
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

# was BODY_ROLL_PER_ACCEL 0.004 and BODY_PITCH_PER_ACCEL 0.003 [rad per m/s^2],
# MAX_BODY_TILT 0.09 [rad] and BODY_TILT_RESPONSE 6.0 [1/s]: a cosmetic lean,
# the body mesh eased towards an angle read off the accelerations -> removed.
# The body is drawn at the suspension's own pitch and roll (body_pitch,
# body_roll): measured 0.0044 rad per m/s^2 in roll (2.5 degrees per g) and
# 0.0030 in pitch, the old figures as it happens, but with the bounce, the
# overshoot and the road in them.

## Furthest a wheel is drawn from its static place under the body [m]: the
## suspension's travel plus the 2 cm of bump stop it takes to lift a wheel off
## the road. Inside that the wheel is drawn ON the road, whatever the body does
## above it; past it (droop) it hangs from the body, visibly in the air.
# was 0.04, a clamp on how far the wheel was drawn off a body that did not move
# -> 0.09 = SUSPENSION_TRAVEL + 0.02: the travel is real now and the clamp is
# its mechanical end.
const MAX_WHEEL_VISUAL_TRAVEL := SUSPENSION_TRAVEL + 0.02

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

## Angle of the driver's steering wheel [degrees], positive = turned left,
## within +/- STEERING_WHEEL_LOCK_DEG. A state: the hands turn it towards what
## the steer input asks for at STEERING_HAND_SPEED. What the cockpit shows.
var steering_wheel_deg := 0.0

## The same as a share of full lock, -1 (full right) .. +1 (full left):
## steering_wheel_deg / STEERING_WHEEL_LOCK_DEG.
var steer := 0.0

## Angle of the front wheels to the car [rad], positive = left: the steering
## wheel's angle through the rack, steering_wheel_deg / STEERING_RATIO (worked
## out as steer x MAX_STEER_LOCK, which is the same thing and lands on full
## lock to the bit). All the steering ever sets.
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

## Engine speed [rad/s]: a state of its own, integrated from the torques on
## the crankshaft (see _engine_net_torque) against ENGINE_INERTIA.
var engine_omega := IDLE_RPM * TAU / 60.0

## Engine speed [rpm]: engine_omega as the tach shows it.
var engine_rpm: float:
	get:
		return engine_omega * 60.0 / TAU
	set(value):
		engine_omega = value * TAU / 60.0

## Wheel speed of each axle [rad/s], positive = rolling forwards: states of
## their own, integrated from drive, brake and tyre torque (_advance_axle). One
## speed per axle, as there is one tyre force per axle.
var front_omega := 0.0
var rear_omega := 0.0

## How far the clutch is in, 0 (open) .. 1 (home): the share of
## CLUTCH_TORQUE_MAX it can pass.
var clutch_engagement := 0.0

## True while the two sides of the clutch turn as one shaft.
var clutch_locked := false

## Torque the clutch passes into the gearbox right now [Nm], positive = the
## engine driving the car the way the gear points, negative = the car turning
## the engine (engine braking).
var clutch_torque := 0.0

## True while the rev limiter holds the fuel back (REDLINE_RPM reached, not yet
## back under LIMITER_RESUME_RPM).
var limiter_cutting := false

## Share of the load the four tyres carry that is on each axle right now
## (0..1, sums to 1): the static split at rest, moved by braking, power, aero
## and the road. Read off the springs (wheel_loads), not set by anything.
var front_load_fraction := 1.0 - REAR_WEIGHT_FRACTION
var rear_load_fraction := REAR_WEIGHT_FRACTION

## Load on each axle right now [N]: the sum of its two wheel_loads.
var front_axle_load := 0.0
var rear_axle_load := 0.0

## Load on each wheel right now [N]: front left, front right, rear left, rear
## right. What that corner's spring, damper, bar and stops push the body up
## with, which is what the tyre presses on the road with; never below 0.
var wheel_loads: Array[float] = [0.0, 0.0, 0.0, 0.0]

## How far each wheel is pushed up into the body from where it sits at rest
## [m], the order of wheel_loads: positive = bump (spring compressed), negative
## = droop. The stops start at +/- SUSPENSION_TRAVEL.
var wheel_travel: Array[float] = [0.0, 0.0, 0.0, 0.0]

## Pitch of the body on its springs [rad], positive = nose up, and its rate
## [rad/s]. A small angle about the centre of mass; on a slope it includes the
## slope (the body lies parallel to the road it stands on).
var body_pitch := 0.0
var pitch_rate := 0.0

## Roll of the body on its springs [rad], positive = right side up (what a
## right-hand corner does), and its rate [rad/s].
var body_roll := 0.0
var roll_rate := 0.0

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

## True from the start of a gear change until the clutch has locked again: the
## driver's foot is off the throttle for the change and comes back on once the
## clutch is home.
var _shift_catching := false

## Time since the last gear change [s]; the automatic waits AUTO_SHIFT_HOLD.
var _since_shift := AUTO_SHIFT_HOLD

## Per wheel (the order of wheel_loads): the road height as the tyre passes it
## on [m, world], and how fast that is changing under the moving car [m/s].
var _tyre_heights: Array[float] = [0.0, 0.0, 0.0, 0.0]
var _tyre_height_rates: Array[float] = [0.0, 0.0, 0.0, 0.0]

## Per wheel: how far its spring seat is trimmed [m], set when the car is stood
## on the road (_settle_suspension). A rigid body on four springs can match
## three of the four heights under its wheels; the fourth, the WARP of the
## patch of road it stands on (one diagonal higher than the other, a
## millimetre or so of micro-bumps), would sit in the springs as cross weight.
## The car is corner-weighted where it is stood, as on a set-up pad: the trim
## takes the warp out, every wheel carries its static share exactly. Equal and
## opposite across each axle, so the axle loads never see it.
var _corner_trim: Array[float] = [0.0, 0.0, 0.0, 0.0]

## Height above the road the car was last stood at [m] (reset_to's y).
var _stand_height := 0.0

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _spawn_transform: Transform3D

@onready var _body: Node3D = $Body
@onready var _front_wheels: Array[Node3D] = [$Wheels/FrontLeft, $Wheels/FrontRight]
@onready var _wheels: Array[Node3D] = [$Wheels/FrontLeft, $Wheels/FrontRight, $Wheels/RearLeft, $Wheels/RearRight]
@onready var _wheel_rest_height: float = _wheels[0].position.y
@onready var _body_rest_height: float = _body.position.y
@onready var _wheel_spinners: Array[Node3D] = [
	$Wheels/FrontLeft/Spin,
	$Wheels/FrontRight/Spin,
	$Wheels/RearLeft/Spin,
	$Wheels/RearRight/Spin,
]


func _ready() -> void:
	_spawn_transform = global_transform
	# The body floats on its springs over the floor; nothing may pull it onto
	# it (CharacterBody3D snaps to a floor within 0.1 m by default).
	floor_snap_length = 0.0
	_settle_suspension(global_position.y)


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

	# 2. Wheel loads: what the four corners of the suspension push the body up
	#    with right now, from where the body is on its springs and what the
	#    road does under each wheel (see _corner_forces). The axle load the
	#    tyres work with is the sum of its two wheels. Nothing is shifted by
	#    hand: braking, power, cornering, downforce and the road are all in the
	#    springs' states (_advance_body, at the end of the tick).
	#    was a static split shifted by acceleration x CG_HEIGHT / wheelbase
	#    (eased in at LOAD_TRANSFER_RESPONSE, capped at MAX_LOAD_TRANSFER) plus
	#    downforce, halved per wheel, plus a road ripple -> the spring forces.
	var weight := CAR_MASS * _gravity
	var downforce := DOWNFORCE_COEFF * ground_speed * ground_speed
	_corner_forces(vertical_speed, delta)
	front_axle_load = wheel_loads[0] + wheel_loads[1]
	rear_axle_load = wheel_loads[2] + wheel_loads[3]
	var carried := front_axle_load + rear_axle_load
	if carried > 0.0:
		front_load_fraction = front_axle_load / carried
		rear_load_fraction = rear_axle_load / carried
	var front_grip := FRONT_TYRE_GRIP * _axle_grip(front_axle_load, weight * (1.0 - REAR_WEIGHT_FRACTION))
	var rear_grip := REAR_TYRE_GRIP * _axle_grip(rear_axle_load, weight * REAR_WEIGHT_FRACTION)

	# 3. How each contact patch moves over the road. The front axle sits ahead
	#    of the centre of mass and its wheels are steered, so its motion is
	#    split along and across the wheels, not the car; the rear sits behind
	#    and points where the car points. A positive (left) yaw rate moves the
	#    nose left and the tail right. Raw steering: the wheels stand at the
#    steering wheel's share of its lock times full lock, the same forwards, backwards
#    or sideways. Was steer * _steering_lock() * _slide_feed() minus a trail
#    towards the way the front travels -> removed: nothing turns the wheels
#    but the driver. The wheels point where they are steered in reverse too:
#    the yaw response flips with the direction of travel, not the wheels (the
#    old signf(forward_speed) only ever picked the side of the leading term).
	#    The driver's hands turn the steering wheel towards what the input asks
	#    for (a share of its 450 degrees each way) at STEERING_HAND_SPEED; the
	#    rack turns that into front wheel angle.
	steering_wheel_deg = move_toward(steering_wheel_deg, steer_input * STEERING_WHEEL_LOCK_DEG, STEERING_HAND_SPEED * delta)
	steer = steering_wheel_deg / STEERING_WHEEL_LOCK_DEG
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

	# 4. Drivetrain and wheels: engine, clutch and the two axles' wheel speeds
	#    are integrated from the torques on them (see _advance_drivetrain), and
	#    each axle's slip ratio is its wheel speed against the road passing
	#    under it. The handbrake locks the rear wheels outright: wheel speed 0,
	#    slip ratio -1 (+1 rolling backwards).
	var pedals := _pedals(forward_speed, drive_input, delta)
	# Rolling rears slide on REAR_TYRE_SLIDE_GRIP, locked ones on TYRE_SLIDE_GRIP.
	var rear_slide_grip := lerpf(REAR_TYRE_SLIDE_GRIP, TYRE_SLIDE_GRIP, _handbrake_amount)
	var front_contact := {"along": front_along, "grip": front_grip, "slip_angle": front_slip_angle, "peak_slip_angle": FRONT_PEAK_SLIP_ANGLE, "slide_grip": TYRE_SLIDE_GRIP}
	var rear_contact := {"along": forward_speed, "grip": rear_grip, "slip_angle": rear_slip_angle, "peak_slip_angle": REAR_PEAK_SLIP_ANGLE, "slide_grip": rear_slide_grip}
	_advance_drivetrain(pedals.throttle, pedals.coasting, pedals.brake, front_contact, rear_contact, delta)
	rear_omega = lerpf(rear_omega, 0.0, _handbrake_amount)
	front_slip_ratio = _slip_ratio(front_omega, front_along)
	rear_slip_ratio = _slip_ratio(rear_omega, forward_speed)
	front_traction_use = _traction_use(front_slip_ratio)
	rear_traction_use = _traction_use(rear_slip_ratio)

	# 5. Tyre forces, along (x) and across (y) each axle's wheels, from slip
	#    ratio and slip angle together (see _tyre_force).
	var front_tyre := front_grip * _tyre_force(front_slip_ratio, front_slip_angle, FRONT_PEAK_SLIP_ANGLE, TYRE_SLIDE_GRIP)
	var rear_tyre := rear_grip * _tyre_force(rear_slip_ratio, rear_slip_angle, REAR_PEAK_SLIP_ANGLE, rear_slide_grip)
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
		if force * (clutch_torque * _drive_ratio() if at_rest else forward_speed) > 0.0:
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
	#     Up and down the body goes where springs, gravity and downforce send
	#     it (_advance_body); the floor under the pad only meets it bottomed
	#     out, and move_and_slide() takes the vertical speed away there.
	#     was gravity while not on the floor, the collision box resting on it,
	#     and a lift by the elevation change after the move -> the heave state.
	vertical_speed = _advance_body(vertical_speed, downforce, air_drag * signf(forward_speed), delta)
	var cg_velocity := forward_dir * forward_speed + right_dir * cg_lateral_speed + Vector3.UP * vertical_speed
	rotate_y(yaw_rate * delta)
	lateral_speed = cg_lateral_speed - yaw_rate * CG_OFFSET
	velocity = cg_velocity - global_basis.x * (yaw_rate * CG_OFFSET)
	move_and_slide()

	_update_visuals(delta)


## Puts the car back where the scene placed it, at rest, in 1st, automatic.
func reset_to_spawn() -> void:
	reset_to(_spawn_transform)


## How the springs have carried the body from its place at rest, in the car's
## frame: maps a point fixed to the body (the driver's eye, the dashboard) from
## where car.tscn has it to where pitch, roll and heave have it now. Heave is
## the car's own height; this is pitch and roll about the centre of mass.
func get_body_ride() -> Transform3D:
	return _body.transform * Transform3D(Basis.IDENTITY, Vector3.DOWN * _body_rest_height)


## Where the scene placed the car. Missions offset their start points from it.
func get_spawn_transform() -> Transform3D:
	return _spawn_transform


## Puts the car at `target`, at rest, in 1st, automatic. The height of
## `target` counts from the road: the car is stood on its springs on the road
## there (_settle_suspension), 0 = at its ride height.
func reset_to(target: Transform3D) -> void:
	global_transform = target
	velocity = Vector3.ZERO
	forward_speed = 0.0
	lateral_speed = 0.0
	yaw_rate = 0.0
	slide_yaw_rate = 0.0
	steering_wheel_deg = 0.0
	steer = 0.0
	_handbrake_amount = 0.0
	reverse_engaged = false
	_forward_engage_timer = 0.0
	gear = 1
	automatic = true
	engine_omega = IDLE_RPM * TAU / 60.0
	limiter_cutting = false
	clutch_engagement = 0.0
	clutch_locked = false
	clutch_torque = 0.0
	_shift_catching = false
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
	front_omega = 0.0
	rear_omega = 0.0
	wheel_angle = 0.0
	longitudinal_accel = 0.0
	lateral_accel = 0.0
	_settle_suspension(target.origin.y)
	_update_visuals(0.0)
	reset_physics_interpolation()


## Stands the car on the road where it is, `height` above its ride height, at
## rest on its springs: the body lies in the plane of the road under its four
## wheels (heave, pitch and roll solved for it, nothing moving), what is left
## over of the four heights (the warp) goes into the corner trim, and every
## spring sits exactly at its static compression: every wheel carries its
## static share to the bit.
func _settle_suspension(height := _stand_height) -> void:
	_stand_height = height
	var heights: Array[float] = [0.0, 0.0, 0.0, 0.0]
	for i in heights.size():
		heights[i] = _road_height_under_wheel(i)
	var front := (heights[0] + heights[1]) * 0.5
	var rear := (heights[2] + heights[3]) * 0.5
	var left := (heights[0] + heights[2]) * 0.5
	var right := (heights[1] + heights[3]) * 0.5
	body_pitch = (front - rear) / (2.0 * AXLE_DISTANCE)
	body_roll = (right - left) / (2.0 * HALF_TRACK)
	pitch_rate = 0.0
	roll_rate = 0.0
	# The car's height is its centre of mass's: CG_OFFSET behind the middle of
	# the wheelbase, where the plane is at the mean of the four.
	global_position.y = height + (front + rear) * 0.5 - body_pitch * CG_OFFSET
	velocity.y = 0.0
	var weight := CAR_MASS * _gravity
	for i in wheel_loads.size():
		_tyre_heights[i] = heights[i]
		_tyre_height_rates[i] = 0.0
		_corner_trim[i] = heights[i] - _corner_height(i) + height
		wheel_travel[i] = -height
		wheel_loads[i] = weight * ((1.0 - REAR_WEIGHT_FRACTION) if i < 2 else REAR_WEIGHT_FRACTION) * 0.5
	front_axle_load = wheel_loads[0] + wheel_loads[1]
	rear_axle_load = wheel_loads[2] + wheel_loads[3]
	front_load_fraction = 1.0 - REAR_WEIGHT_FRACTION
	rear_load_fraction = REAR_WEIGHT_FRACTION


## Height of the road under wheel `i`, every layer of the profile [m].
func _road_height_under_wheel(i: int) -> float:
	if road_profile == null:
		return 0.0
	var contact := global_transform * WHEEL_CONTACT_POINTS[i]
	return road_profile.sample_height(contact.x, contact.z)


## Height of the corner of the body over wheel `i` [m, world], counted so that
## it equals the road's height under the wheel with the spring at its static
## compression: the car's height (its centre of mass's) plus what pitch and
## roll do at that corner, small angles.
func _corner_height(i: int) -> float:
	return global_position.y + body_pitch * WHEEL_ARMS_AHEAD[i] + body_roll * WHEEL_ARMS_RIGHT[i]


## One tick of the four corners: works out wheel_travel and wheel_loads from
## where the body is on its springs now. Per corner, with the travel x [m] the
## wheel is pushed up into the body from its static place (the road's height as
## the tyre passes it on, less the corner's height) and its rate v [m/s] (how
## fast the road comes up under the moving wheel, less how fast the corner of
## the body moves: heave, pitch and roll rates):
##   load = static share + spring rate * x + damper rate * v
##          + anti-roll rate * (x - x of the wheel across) + bump stop(x)
## never below 0: a tyre pushes on the road, it cannot pull on it. Past the
## droop stop the wheel hangs in the air. `vertical_speed` is the body's.
func _corner_forces(vertical_speed: float, delta: float) -> void:
	var envelope := 1.0 - exp(-TYRE_ENVELOPE_RATE * delta)
	for i in wheel_loads.size():
		var tyre_before := _tyre_heights[i]
		_tyre_heights[i] = lerpf(tyre_before, _road_height_under_wheel(i), envelope)
		_tyre_height_rates[i] = (_tyre_heights[i] - tyre_before) / delta
		wheel_travel[i] = _tyre_heights[i] - _corner_height(i) - _corner_trim[i]
	var weight := CAR_MASS * _gravity
	for i in wheel_loads.size():
		var front := i < 2
		var spring_rate := FRONT_SPRING_RATE if front else REAR_SPRING_RATE
		var corner_speed := vertical_speed + pitch_rate * WHEEL_ARMS_AHEAD[i] + roll_rate * WHEEL_ARMS_RIGHT[i]
		var travel := wheel_travel[i]
		# i ^ 1: the wheel across the axle.
		var across := wheel_travel[i ^ 1]
		var depth := maxf(absf(travel) - SUSPENSION_TRAVEL, 0.0)
		var stop := signf(travel) * BUMP_STOP_RATE * spring_rate * depth * (1.0 + depth / BUMP_STOP_PROGRESSION)
		var pushing := weight * ((1.0 - REAR_WEIGHT_FRACTION) if front else REAR_WEIGHT_FRACTION) * 0.5 \
				+ spring_rate * travel \
				+ (FRONT_DAMPER_RATE if front else REAR_DAMPER_RATE) * (_tyre_height_rates[i] - corner_speed) \
				+ (FRONT_ANTI_ROLL_RATE if front else REAR_ANTI_ROLL_RATE) * (travel - across) \
				+ stop
		wheel_loads[i] = maxf(pushing, 0.0)


## One tick of the body on its springs; returns its new vertical speed [m/s]
## (the move itself is move_and_slide's). Forces on the body: the four wheel
## loads pushing up at their corners, gravity and `downforce` [N] pulling down
## (the downforce at the axles, split by AERO_BALANCE_FRONT), and the tyres'
## grip on the road, CG_HEIGHT below the centre of mass: along the car that is
## what accelerates it plus what holds it against the air (`air_drag` [N],
## signed like the speed, taken to act at the height of the centre of mass),
## across it what bends its path.
##   heave:  CAR_MASS     x d(vertical speed) = sum of loads - weight - downforce
##   pitch:  PITCH_INERTIA x d(pitch_rate)    = sum of load x (how far ahead of the CG)
##                                              + tyre force along x CG_HEIGHT - aero moment
##   roll:   ROLL_INERTIA  x d(roll_rate)     = sum of load x (how far right of the CG)
##                                              - tyre force towards the left x CG_HEIGHT
## Semi-implicit Euler: rates from the forces, angles from the new rates.
## Steady state the springs then carry exactly the classic weight transfer
## (force x CG_HEIGHT / wheelbase or track); how they get there is the ride.
func _advance_body(vertical_speed: float, downforce: float, air_drag: float, delta: float) -> float:
	var lift := 0.0
	var pitch_moment := 0.0
	var roll_moment := 0.0
	for i in wheel_loads.size():
		lift += wheel_loads[i]
		pitch_moment += wheel_loads[i] * WHEEL_ARMS_AHEAD[i]
		roll_moment += wheel_loads[i] * WHEEL_ARMS_RIGHT[i]
	var front_arm := AXLE_DISTANCE + CG_OFFSET
	var rear_arm := AXLE_DISTANCE - CG_OFFSET
	pitch_moment += (CAR_MASS * longitudinal_accel + air_drag) * CG_HEIGHT
	pitch_moment -= downforce * (AERO_BALANCE_FRONT * front_arm - (1.0 - AERO_BALANCE_FRONT) * rear_arm)
	roll_moment -= CAR_MASS * lateral_accel * CG_HEIGHT
	pitch_rate += pitch_moment / PITCH_INERTIA * delta
	roll_rate += roll_moment / ROLL_INERTIA * delta
	body_pitch += pitch_rate * delta
	body_roll += roll_rate * delta
	return vertical_speed + (lift - CAR_MASS * _gravity - downforce) / CAR_MASS * delta


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
	_shift_catching = true
	_since_shift = 0.0
	return true


## Engine speed [rpm] the road would turn the engine at in `in_gear`
## at the current speed (0 in neutral).
func wheel_rpm(in_gear: int) -> float:
	return absf(forward_speed) / WHEEL_RADIUS * GEAR_RATIOS[in_gear] * FINAL_DRIVE * 60.0 / TAU


## Road speed [m/s] at which the engine turns `rpm` in `in_gear`.
func speed_at_rpm(in_gear: int, rpm: float) -> float:
	return rpm / (60.0 / TAU) / (GEAR_RATIOS[in_gear] * FINAL_DRIVE) * WHEEL_RADIUS


## Full-throttle engine torque at the flywheel [Nm] at `rpm`, from
## TORQUE_CURVE. Zero at and above the rev limiter.
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


## What the pedals ask for this tick, as { throttle, brake, coasting }, and the
## gearbox update on the way. `throttle` is the engine's, 0..1; `coasting` is
## true while the driver asks for none (a lift for a gear change is not
## coasting). `brake` is the total
## brake force asked for at the tyres [N], always positive; it works against
## the way each wheel turns. `drive` is +1 for the accelerate key and -1 for
## the brake key.
func _pedals(speed: float, drive: float, delta: float) -> Dictionary:
	# The key of the selected direction is the throttle, the other one the
	# brake: it slows the car to a stop whichever way it rolls, and holds it
	# there. The throttle key also brakes while the car still rolls against the
	# selected direction (backwards out of a 180, nose-first out of a J-turn).
	var is_moving := absf(speed) > STANDSTILL_SPEED
	var direction := -1.0 if reverse_engaged else 1.0
	var against_travel := is_moving and signf(speed) != direction
	var braking := not is_zero_approx(drive) and (signf(drive) != direction or against_travel)
	var reversing := reverse_engaged
	var throttle := 0.0
	if not braking and drive > 0.0 and not reversing:
		throttle = drive
	elif not braking and drive < 0.0 and reversing:
		# was a flat force of REVERSE_ACCEL x CAR_MASS -> the engine, through the
		# clutch and REVERSE_RATIO like any other gear. The driver's foot eases
		# off into MAX_REVERSE_SPEED (the old limiter, now on the throttle): wide
		# open until REVERSE_ACCEL / REVERSE_LIMITER_RATE short of it, shut at it.
		throttle = -drive * clampf((speed + MAX_REVERSE_SPEED) * REVERSE_LIMITER_RATE / REVERSE_ACCEL, 0.0, 1.0)

	var coasting := throttle <= 0.0
	_update_gearbox(speed, throttle, reversing, delta)
	# The driver lifts for a gear change and comes back on the throttle once
	# the clutch is home again. On the way down the box the same foot blips the
	# throttle while the clutch is open (DOWNSHIFT_BLIP_BAND).
	if _shift_catching:
		var revs_missing := _gearbox_omega() - engine_omega
		throttle = clampf(revs_missing / DOWNSHIFT_BLIP_BAND, 0.0, 1.0) if is_shifting else 0.0
	var brake := BRAKE_DECEL * absf(drive) * CAR_MASS if braking else 0.0
	return {"throttle": throttle, "brake": brake, "coasting": coasting}


## Overall ratio between the engine and the driven wheels right now: gear x
## final drive, negative in reverse (the engine turns its own way, the wheels
## backwards), 0 in neutral.
func _drive_ratio() -> float:
	if reverse_engaged:
		return -REVERSE_RATIO * FINAL_DRIVE
	return GEAR_RATIOS[gear] * FINAL_DRIVE


## How far in the car wants its clutch (0..1). Open in neutral, for the
## SHIFT_TIME of a gear change, while the handbrake locks driven rear wheels
## (or it would stall the engine), and, throttle closed, once the gearbox
## would turn the engine under CLUTCH_DISENGAGE_RPM: that is the stop in gear,
## and the standstill. Home otherwise: under throttle from any speed (from a
## standstill that is the launch, slipping), and throttle closed at speed
## (engine braking). Coasting, a clutch that comes back in is there to hold
## the car back, never to shove it on: while the engine still turns faster
## than the gearbox (the revs left over from before a handbrake turn) it stays
## open and waits for the revs to fall. A gear change is seen through either
## way: that catch is part of the change. Rolling
## against the gear it drags at CLUTCH_DRAG_ENGAGEMENT.
func _clutch_target(speed: float, gearbox_omega: float, throttle: float, coasting: bool) -> float:
	var rear_driven := driven_wheels != DrivenWheels.FWD
	if (gear == 0 and not reverse_engaged) or is_shifting or (_handbrake_amount > 0.0 and rear_driven):
		return 0.0
	if throttle > 0.0:
		return 1.0
	if gearbox_omega < 0.0:
		return CLUTCH_DRAG_ENGAGEMENT if absf(speed) > STANDSTILL_SPEED else 0.0
	if coasting and not _shift_catching and not clutch_locked and engine_omega > gearbox_omega + CLUTCH_SLIP_BAND:
		return 0.0
	return 1.0 if gearbox_omega >= CLUTCH_DISENGAGE_RPM * TAU / 60.0 else 0.0


## Speed of the gearbox side of the clutch [rad/s]: the driven wheels' speed
## through the gear, positive = the way the engine turns. With two driven axles
## the centre differential turns at the torque-weighted mean of the two.
func _gearbox_omega() -> float:
	var front_share := _front_drive_share()
	return (front_omega * front_share + rear_omega * (1.0 - front_share)) * _drive_ratio()


## One tick of the whole driveline: engine, clutch, and the wheel speeds of the
## two axles, each a state integrated from the torques on it. `front` and
## `rear` say how each axle's contact patches meet the road this tick (see
## _advance_axle); `brake` [N at the tyres] goes to the axles by
## BRAKE_BIAS_FRONT, as a torque.
##   Slipping, the clutch passes CLUTCH_TORQUE_MAX x clutch_engagement from its
## faster side to its slower one (eased through zero over CLUTCH_SLIP_BAND).
## The engine is integrated under its own torque less that; the same torque,
## through the gear (and DRIVETRAIN_EFFICIENCY on the way out), turns the
## driven axle. While the gearbox side is slower than the launch floor
## (IDLE_RPM .. LAUNCH_RPM by throttle) the car feathers the clutch so it never
## drags the engine under it: pulling away on little throttle the engine sits
## near idle and the car moves off on what it makes there; flat out the revs
## flare to LAUNCH_RPM and hold there, the clutch slipping and passing all the
## engine makes: in 1st that is more than the rear tyres hold, they spin up,
## and the clutch is feathered against that too (_ease_for_wheelspin) until
## the two sides meet. When they do they go on as one (merged by their
## angular momentum: the engine outweighs an axle fifteen times over in 1st,
## so it is the wheels that are snatched to the engine's speed, not the other
## way round, and if the tyres cannot hold that, they spin).
##   Locked, engine and driven axle are one shaft and integrate as one: the
## engine turns ratio (gear x final drive) times as fast as the wheels, so at
## the axle its torque counts ratio times and its inertia
##   ENGINE_INERTIA x ratio^2 x DRIVETRAIN_EFFICIENCY   [kg m^2]
## (speeding the engine up by ratio x d(omega) takes ratio x that torque at
## the axle): ~49 kg m^2 in 1st against AXLE_INERTIA 2.4, ~16 in 2nd, 3 in 5th.
## That is what dulls 1st gear (~25 % of the engine's torque goes into its own
## revs) and what makes wheelspin under power a slow swell instead of a snap:
## the tyres have to let the whole engine go. Throttle closed, the engine's
## friction comes through the same way: engine braking, more in the lower
## gears without anybody scripting it. The clutch torque is read back from the
## engine's side (its net torque less what its own speeding up took) and the
## lock holds while that stays inside what the clutch can pass and the engine
## above idle.
##   Open differentials, axle by axle: the two wheels of an axle share one
## speed and one tyre force (the bicycle model), so an unloaded inside wheel
## spinning its torque away is not modelled.
func _advance_drivetrain(throttle: float, coasting: bool, brake: float, front: Dictionary, rear: Dictionary, delta: float) -> void:
	var idle_omega := IDLE_RPM * TAU / 60.0
	var ratio := _drive_ratio()
	var front_share := _front_drive_share()
	var rear_share := 1.0 - front_share
	var front_brake := _brake_torque(BRAKE_BIAS_FRONT, brake, AXLE_INERTIA)
	var rear_brake := _brake_torque(1.0 - BRAKE_BIAS_FRONT, brake, AXLE_INERTIA)
	var abs_active := brake > 0.0
	var gearbox_omega := _gearbox_omega()

	var target := _clutch_target(forward_speed, gearbox_omega, throttle, coasting)
	if target <= clutch_engagement:
		# Opening is a stab at the pedal: at once.
		clutch_engagement = target
	else:
		var engage_time := CLUTCH_ENGAGE_TIME if gearbox_omega < idle_omega else CLUTCH_SHIFT_ENGAGE_TIME
		clutch_engagement = minf(clutch_engagement + delta / engage_time, target)
	var capacity := CLUTCH_TORQUE_MAX * clutch_engagement
	if not is_shifting and (target <= 0.0 or gearbox_omega < idle_omega):
		# Nothing to catch: neutral, a stop, or a gear taken at a standstill,
		# where pulling away is the launch's business. The foot is free again.
		_shift_catching = false

	if clutch_locked:
		# One shaft: each driven axle carries its share of the engine's torque
		# and of its inertia.
		var net := _engine_net_torque(engine_rpm, throttle, 0.0)
		var at_axle := net * ratio * (DRIVETRAIN_EFFICIENCY if net > 0.0 else 1.0)
		var reflected := ENGINE_INERTIA * ratio * ratio * DRIVETRAIN_EFFICIENCY
		# The brakes have the engine to slow down too (see _brake_torque).
		front_brake += _brake_torque(0.0, brake, reflected * front_share)
		rear_brake += _brake_torque(0.0, brake, reflected * rear_share)
		var next_front := _advance_axle(front_omega, at_axle * front_share, front_brake, AXLE_INERTIA + reflected * front_share, front, abs_active, delta)
		var next_rear := _advance_axle(rear_omega, at_axle * rear_share, rear_brake, AXLE_INERTIA + reflected * rear_share, rear, abs_active, delta)
		var next_engine := (next_front * front_share + next_rear * rear_share) * ratio
		var held := net - ENGINE_INERTIA * (next_engine - engine_omega) / delta
		if absf(held) <= capacity and next_engine >= idle_omega:
			front_omega = next_front
			rear_omega = next_rear
			engine_omega = next_engine
			clutch_torque = held
			_update_limiter()
			return
		clutch_locked = false

	var slip := engine_omega - gearbox_omega
	clutch_torque = capacity * clampf(slip / CLUTCH_SLIP_BAND, -1.0, 1.0)
	var floor_omega := lerpf(IDLE_RPM, LAUNCH_RPM, throttle) * TAU / 60.0
	if gearbox_omega < floor_omega and clutch_torque > 0.0:
		# Feathering: under the floor the clutch takes LAUNCH_CLUTCH_SHARE of
		# what the engine makes (the idle controller leaning in against the
		# load), at the floor all of it, plus whatever speed the engine has
		# above the floor.
		var available := maxf(_engine_net_torque(engine_rpm, throttle, clutch_torque), 0.0)
		var share := lerpf(LAUNCH_CLUTCH_SHARE, 1.0, smoothstep(floor_omega - LAUNCH_BITE_BAND, floor_omega, engine_omega))
		clutch_torque = minf(clutch_torque, available * share + ENGINE_INERTIA * maxf(engine_omega - floor_omega, 0.0) / delta)
	var to_axle := clutch_torque * ratio * (DRIVETRAIN_EFFICIENCY if clutch_torque > 0.0 else 1.0)
	var front_torque := to_axle * front_share
	var rear_torque := to_axle * rear_share
	var next_front := _advance_axle(front_omega, front_torque, front_brake, AXLE_INERTIA, front, abs_active, delta)
	var next_rear := _advance_axle(rear_omega, rear_torque, rear_brake, AXLE_INERTIA, rear, abs_active, delta)
	if clutch_torque > 0.0:
		# The same foot feathers the clutch against wheelspin: a driven axle is
		# let spin up to DRIVE_SLIP_RATIO and given no more torque than holds
		# it there. Only while the clutch slips; locked, the wheels are the
		# engine's.
		if front_share > 0.0:
			var eased := _ease_for_wheelspin(front_omega, next_front, front_torque, front, delta)
			if eased.x != front_torque:
				front_torque = eased.x
				next_front = eased.y if eased.x != 0.0 else _advance_axle(front_omega, 0.0, front_brake, AXLE_INERTIA, front, abs_active, delta)
		if rear_share > 0.0:
			var eased := _ease_for_wheelspin(rear_omega, next_rear, rear_torque, rear, delta)
			if eased.x != rear_torque:
				rear_torque = eased.x
				next_rear = eased.y if eased.x != 0.0 else _advance_axle(rear_omega, 0.0, rear_brake, AXLE_INERTIA, rear, abs_active, delta)
		clutch_torque = (front_torque + rear_torque) / (ratio * DRIVETRAIN_EFFICIENCY)
	front_omega = next_front
	rear_omega = next_rear
	_advance_engine(_engine_net_torque(engine_rpm, throttle, clutch_torque) - clutch_torque, delta)
	if clutch_engagement <= 0.0:
		return
	var slip_after := engine_omega - _gearbox_omega()
	if (slip * slip_after <= 0.0 or absf(slip_after) < CLUTCH_SLIP_BAND) and _gearbox_omega() >= idle_omega:
		# The two sides have met: one shaft from here, at the speed their
		# angular momentum comes to (the axles' inertia seen from the engine).
		var axle_inertia := AXLE_INERTIA * (signf(front_share) + signf(rear_share)) / (ratio * ratio)
		engine_omega = (engine_omega * ENGINE_INERTIA + _gearbox_omega() * axle_inertia) / (ENGINE_INERTIA + axle_inertia)
		if front_share > 0.0:
			front_omega = engine_omega / ratio
		if rear_share > 0.0:
			rear_omega = engine_omega / ratio
		clutch_locked = true
		_shift_catching = false
		_update_limiter()


## Feathering against wheelspin: if `torque` [Nm at the axle, from a slipping
## clutch] would take the axle from `omega` to `next` past DRIVE_SLIP_RATIO in
## the direction it drives, returns the torque that lands it on that slip
## instead (x, never past 0: the foot can come off, it cannot brake) and the
## wheel speed there (y). Backward Euler read the other way round: the torque
## is what the speed change takes plus what the tyre pushes back with there.
## Otherwise returns `torque` and `next` as they are.
func _ease_for_wheelspin(omega: float, next: float, torque: float, contact: Dictionary, delta: float) -> Vector2:
	var along: float = contact.along
	var direction := signf(torque)
	var limit := (along + direction * DRIVE_SLIP_RATIO * maxf(absf(along), SLIP_RATIO_MIN_SPEED)) / WHEEL_RADIUS
	if (next - limit) * direction <= 0.0:
		return Vector2(torque, next)
	var tyre: float = contact.grip * WHEEL_RADIUS * _tyre_force(_slip_ratio(limit, along), contact.slip_angle, contact.peak_slip_angle, contact.slide_grip).x
	var holding := AXLE_INERTIA * (limit - omega) / delta + tyre
	if holding * direction <= 0.0:
		return Vector2(0.0, next)
	return Vector2(holding, limit)


## Brake torque on an axle [Nm] for a pedal asking for `brake` [N] at the
## tyres, `share` of it on this axle, with `inertia` [kg m^2] turning with the
## axle. The pedal asks for a deceleration of the CAR (BRAKE_DECEL, at the
## tyres), and what turns has to be slowed down along with it: the wheels, and
## through a locked clutch the engine, which in 1st weighs on the driven axle
## like another 420 kg. That takes inertia x (deceleration / WHEEL_RADIUS) of
## brake torque on top of the tyres' share; without it a stop in a low gear
## would be the engine's flywheel unloading the rear brakes.
func _brake_torque(share: float, brake: float, inertia: float) -> float:
	return share * brake * WHEEL_RADIUS + inertia * brake / (CAR_MASS * WHEEL_RADIUS)


## One tick of an axle's wheel speed [rad/s], positive = rolling forwards:
##   d(omega) / dt = (torque - brake torque - tyre force x WHEEL_RADIUS) / inertia
## `torque` is what the driveline puts in [Nm], `brake_torque` works against
## the way the wheels turn (and holds them once they have stopped), and the
## tyre force is the road's answer to the slip the wheel speed makes
## (_slip_ratio, _tyre_force): a wheel turning faster than the road is pushed
## back by exactly the force with which it pushes the car on. `contact` is the
## axle's contact patch this tick: `along` [m/s] the road speed along the
## wheels, `grip` [N], `slip_angle`, `peak_slip_angle`, `slide_grip`.
##   Stability: the tyre is a very stiff spring between wheel and road (at
## walking pace a bare axle answers at ~4000 per second, the tick is 60), so
## the step is implicit in the wheel speed: the tyre force is taken at the END
## of the step. It is linearised on the tyre curve's slope where the curve
## rises (one Newton step of backward Euler; past the peak the slope counts as
## 0, a spinning wheel runs away at the pace its inertia sets), and where that
## steps over the speed at which the torques balance (a wheel hooking up again,
## a light axle let go) the backward-Euler equation is solved by bisection
## between the old speed and the overshoot. This is what the old slip-ratio
## relaxation did with its slope division and its homing-in, now on a real
## state with a real inertia; it holds at any tick length.
##   Under the foot brake the ABS holds the wheel at ABS_SLIP_RATIO instead of
## letting it lock (it lets go of as much brake torque as that takes); only the
## handbrake locks wheels, the rear ones, by _handbrake_amount.
func _advance_axle(omega: float, torque: float, brake_torque: float, inertia: float, contact: Dictionary, abs_active: bool, delta: float) -> float:
	var along: float = contact.along
	var road_torque: float = contact.grip * WHEEL_RADIUS
	# The brake works against the wheel's turning; on a stopped wheel against
	# whatever would turn it, and holds it if it can.
	var brake_direction := signf(omega)
	if brake_direction == 0.0:
		var turning := torque - road_torque * _tyre_force(_slip_ratio(0.0, along), contact.slip_angle, contact.peak_slip_angle, contact.slide_grip).x
		if absf(turning) <= brake_torque:
			return 0.0
		brake_direction = signf(turning)
	torque -= brake_direction * brake_torque

	var net := torque - road_torque * _tyre_force(_slip_ratio(omega, along), contact.slip_angle, contact.peak_slip_angle, contact.slide_grip).x
	var probe := 0.01 * PEAK_SLIP_RATIO
	var slip_per_omega := WHEEL_RADIUS / maxf(absf(along), SLIP_RATIO_MIN_SPEED)
	var slip_ratio := _slip_ratio(omega, along)
	var slope := maxf(
		(_tyre_force(slip_ratio + probe, contact.slip_angle, contact.peak_slip_angle, contact.slide_grip).x
			- _tyre_force(slip_ratio, contact.slip_angle, contact.peak_slip_angle, contact.slide_grip).x) / probe,
		0.0
	) * road_torque * slip_per_omega
	var next := omega + net * delta / (inertia + slope * delta)
	var net_next := torque - road_torque * _tyre_force(_slip_ratio(next, along), contact.slip_angle, contact.peak_slip_angle, contact.slide_grip).x
	if net * net_next < 0.0:
		var near := omega
		for i in 16:
			var middle := (near + next) * 0.5
			var net_middle := torque - road_torque * _tyre_force(_slip_ratio(middle, along), contact.slip_angle, contact.peak_slip_angle, contact.slide_grip).x
			# Backward Euler: middle - omega = net(middle) x delta / inertia.
			if ((middle - omega) * inertia - net_middle * delta) * net < 0.0:
				near = middle
			else:
				next = middle
		next = (near + next) * 0.5
	if brake_torque > 0.0 and next * omega < 0.0:
		# A brake stops a wheel, it does not turn it back the other way.
		next = 0.0
	if abs_active:
		var abs_margin := ABS_SLIP_RATIO * maxf(absf(along), SLIP_RATIO_MIN_SPEED)
		if along >= 0.0:
			next = maxf(next, (along - abs_margin) / WHEEL_RADIUS)
		else:
			next = minf(next, (along + abs_margin) / WHEEL_RADIUS)
	return next


## Slip ratio of a wheel turning at `omega` [rad/s] over a road passing at
## `along` [m/s]: (wheel surface speed - road speed) / road speed. The road
## speed it is worked out against is at least SLIP_RATIO_MIN_SPEED.
func _slip_ratio(omega: float, along: float) -> float:
	return (omega * WHEEL_RADIUS - along) / maxf(absf(along), SLIP_RATIO_MIN_SPEED)


## Share of the engine's force that goes to the front axle (0..1).
func _front_drive_share() -> float:
	match driven_wheels:
		DrivenWheels.FWD:
			return 1.0
		DrivenWheels.AWD:
			return TORQUE_DISTRIBUTION
	return 0.0


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
func _tyre_force(slip_ratio: float, slip_angle: float, peak_slip_angle: float, slide_grip: float) -> Vector2:
	var along := slip_ratio / PEAK_SLIP_RATIO
	var across := tan(slip_angle) / tan(peak_slip_angle)
	var slip := Vector2(along, across).length()
	if slip < 0.0001:
		return Vector2.ZERO
	# Sliding along the wheel (wheelspin, a locked wheel) is TYRE_SLIDE_GRIP's
	# on either axle; `slide_grip` has its say by how far sideways the slip is.
	var sideways_slip := across * across / (slip * slip)
	var share := _tyre_curve(slip, lerpf(TYRE_SLIDE_GRIP, slide_grip, sideways_slip)) / slip
	var floor_share := MIN_COMBINED_GRIP * (1.0 - smoothstep(DRIVE_SLIP_RATIO, 1.0, absf(slip_ratio)))
	var sideways := maxf(share * absf(across), floor_share * absf(_tyre_curve(across, slide_grip)))
	return Vector2(share * along, -sideways * signf(across))


## Share of a tyre's grip that goes along the wheel at `slip_ratio` (0..1), for
## tests and the HUD: the tyre curve up to the peak, all of it from there.
func _traction_use(slip_ratio: float) -> float:
	var x := absf(slip_ratio) / PEAK_SLIP_RATIO
	return 1.0 if x >= 1.0 else absf(_tyre_curve(x, TYRE_SLIDE_GRIP))


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


## Net torque on the crankshaft from the engine itself [Nm] at `rpm` with the
## pedal at `throttle` (0..1): what the burning fuel makes, less friction and
## pumping losses. TORQUE_CURVE is what is left of the two at full throttle, so
## combustion is the curve plus the losses, scaled by the throttle; closed, the
## losses are all there is, and that is the engine braking. Two things work the
## throttle besides the driver: the idle controller adds to it as the revs come
## down to IDLE_RPM (enough to carry the friction and the `load` [Nm] the
## clutch takes off the crankshaft there, plus IDLE_CONTROL_GAIN for every
## rad/s below), and the rev limiter shuts the fuel off (limiter_cutting).
func _engine_net_torque(rpm: float, throttle: float, load: float) -> float:
	var friction := ENGINE_FRICTION_TORQUE + ENGINE_FRICTION_TORQUE_PER_RPM * rpm
	if limiter_cutting:
		return -friction
	var full_combustion := engine_torque(rpm) + friction
	var idle_torque := friction + load + IDLE_CONTROL_GAIN * (IDLE_RPM - rpm) * TAU / 60.0
	var idle_throttle := clampf(idle_torque / full_combustion, 0.0, IDLE_CONTROL_MAX_THROTTLE)
	return full_combustion * minf(throttle + idle_throttle, 1.0) - friction


## One tick of the engine speed under `torque` [Nm], everything on the
## crankshaft added up: d(omega) = torque / ENGINE_INERTIA * delta. The limiter
## cuts the fuel the moment the revs get to REDLINE_RPM, so the engine never
## runs past it under its own power: the step stops there.
func _advance_engine(torque: float, delta: float) -> void:
	var limit := REDLINE_RPM * TAU / 60.0
	var next := engine_omega + torque / ENGINE_INERTIA * delta
	if engine_omega <= limit:
		next = minf(next, limit)
	engine_omega = maxf(next, 0.0)
	_update_limiter()


## The rev limiter's fuel cut: on at REDLINE_RPM, off again under
## LIMITER_RESUME_RPM.
func _update_limiter() -> void:
	if engine_rpm >= REDLINE_RPM:
		limiter_cutting = true
	elif engine_rpm < LIMITER_RESUME_RPM:
		limiter_cutting = false


## Most force [N] the tyres of an axle can make, in any direction, under
## `load` [N] when the axle carries `static_load` [N] at rest: TYRE_MU times
## the load at rest, sub-linear in load from there (LOAD_GRIP_EXPONENT).
func _axle_grip(load: float, static_load: float) -> float:
	return TYRE_MU * static_load * pow(maxf(load, 0.0) / static_load, LOAD_GRIP_EXPONENT)


## The tyre curve: share of the peak force (-1..1) at `slip`, the slip angle in
## peak slip angles (or the slip ratio in peak slip ratios). Rises smoothly into the peak at 1 (slope 1.5 at
## zero, flat at the top), then eases down to `slide_grip` (TYRE_SLIDE_GRIP, or
## REAR_TYRE_SLIDE_GRIP for rear tyres that roll).
func _tyre_curve(slip: float, slide_grip: float) -> float:
	var x := absf(slip)
	if x <= 1.0:
		return slip * (3.0 - x * x) * 0.5
	var sliding := 1.0 - exp(-(x - 1.0) / TYRE_SLIDE_ONSET)
	return signf(slip) * lerpf(1.0, slide_grip, sliding)


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


## What shows: wheel spin, front wheel steering, the wheels on the road and the
## body on its springs.
func _update_visuals(delta: float) -> void:
	# Each axle is drawn turning at its real wheel speed (front_omega,
	# rear_omega): driven wheels that break traction visibly outrun the road,
	# braked ones lag it, handbraked rears stand still.
	# was road speed x (1 + slip ratio), the handbrake faded in by hand -> the
	# wheel speed states themselves; nothing to reconstruct any more.
	var front_spin := clampf(front_omega, -MAX_WHEEL_SPIN, MAX_WHEEL_SPIN)
	var rear_spin := clampf(rear_omega, -MAX_WHEEL_SPIN, MAX_WHEEL_SPIN)
	for i in _wheel_spinners.size():
		# Rolling towards -Z is a negative rotation about +X.
		_wheel_spinners[i].rotate_x(-(front_spin if i < 2 else rear_spin) * delta)

	for wheel in _front_wheels:
		wheel.rotation.y = wheel_angle

	# Each wheel is drawn on the road (as far as its travel reaches), the body
	# above it where its springs have it: pitched and rolled about the centre
	# of mass, CG_OFFSET behind the body node.
	# The road as it lies under the wheel now, after the move, every bump of it:
	# the springs feel it through the tyre (TYRE_ENVELOPE_RATE), the eye does not.
	for i in _wheels.size():
		var seat := _corner_height(i) + _corner_trim[i]
		var drawn_travel := clampf(_road_height_under_wheel(i) - seat, -MAX_WHEEL_VISUAL_TRAVEL, MAX_WHEEL_VISUAL_TRAVEL)
		_wheels[i].position.y = _wheel_rest_height + seat - global_position.y + drawn_travel
	_body.rotation.x = body_pitch
	_body.rotation.z = body_roll
	_body.position.y = _body_rest_height + body_pitch * CG_OFFSET
