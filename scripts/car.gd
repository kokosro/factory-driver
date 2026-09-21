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
## accelerates the car's mass (total_mass(): 1300 kg on a full tank, less as
## it burns, more with what it carries), their moments about the centre of mass (front force
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
## speed by decree: the tach reads what the engine does. The work costs fuel
## (see Fuel and exhaust), the fuel in the tank is mass the car carries, and
## the exhaust is there as data. The STARTER that turns a stopped engine draws
## on the BATTERY, the alternator puts back what the running engine's belt
## drives, and a battery run flat is one that cranks weakly, or not at all, and
## has lost some of what it held for good (see Electrical). In automatic the
## clutch also creeps the car off a released brake (see Creep, by the clutch).
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
#  2.5 L 986, bent where the placeholder model needs it.
# was "The next car (911) gets its own section like this one", every number a
# const in this file -> the car's own numbers live in its config,
# configs/cars/boxster_986.json (schema: configs/README.md), and a car reads
# them as the first thing it does (_read_config). The same car.gd with another
# config file is another car. What this file keeps is the model, and what
# follows from a car's numbers: everything DERIVED from them (BASE_MASS, the
# corner masses, springs and dampers, the contact points, STEERING_RATIO ...)
# is worked out here, in code, again whenever a config has been read, so it
# can never go stale against the numbers it comes from.
#   The numbers that moved are static vars now, each under its old name and
# with its certified value still written here: the fallback default. For a key
# the schema marks optional that is what a config without it gets; for a
# required one a config without it is refused out loud (CarConfigValidation), and
# the default is only what the class holds until a car has read its config.
# Static, not per car: engine_torque, derived_shift_points and _engine_friction
# are static functions, and the tests read the numbers off the class.
# -----------------------------------------------------------------------------

## The car's config: read, and checked by CarConfigValidation, before a number
## of it is used (see _read_config).
const CONFIG_PATH := "res://configs/cars/boxster_986.json"

# --- Mass and weight distribution --------------------------------------------

## Mass of the car as it stands ready to drive: a driver on board, the tank
## full, nothing loaded [kg]. 986 kerb weight (full tank, no driver) ~1250 kg.
## The car everything here was tuned and certified as, and the one the
## suspension is set up for (see FRONT / REAR_CORNER_MASS).
# was a const -> read from the car's config (mass.kerb_mass, required); the
# certified value stays here as the fallback default.
static var KERB_MASS := 1300.0

# BASE_MASS, the same car with a dry tank, follows from this and the tank: it
# stands under FUEL_DENSITY, the last of the numbers it is made of (a static
# var's initializer can only read what is declared above it).

## Share of the car's weight on the rear axle at rest (0..1). The Boxster's
## flat-six sits behind the seats (mid engine), putting ~62 % on the rear.
## The front axle carries the rest.
# was a const -> read from the car's config (mass.rear_weight_fraction,
# required); the certified value stays here as the fallback default.
static var REAR_WEIGHT_FRACTION := 0.62

## Height of the centre of mass above the road [m]. Higher = more weight moves
## between the axles under braking and acceleration.
# was a const -> read from the car's config (mass.cg_height, required); the
# certified value stays here as the fallback default.
static var CG_HEIGHT := 0.48

## Distance from the car's centre to each axle [m]; half the wheelbase. Must
## match the wheel positions in car.tscn. Longer = the tail swings more lazily
## and less weight moves between the axles. (Real 986: 2.415 m wheelbase.)
# was a const -> read from the car's config (mass.axle_distance, required);
# the certified value stays here as the fallback default.
static var AXLE_DISTANCE := 1.3

## How far the centre of mass sits behind the middle of the wheelbase [m]:
## follows from the weight distribution. The front tyres work on the longer
## lever arm, the heavier-loaded rears on the shorter, so with both axles
## sliding flat out the car neither straightens nor tightens by itself.
# was a const -> derived, never read: worked out again from the config's
# numbers when a car reads them (_derive_from_config, the same sum as here).
static var CG_OFFSET := (REAR_WEIGHT_FRACTION - 0.5) * 2.0 * AXLE_DISTANCE

## Radius of gyration about the vertical axis [m]: yaw inertia is
## total_mass() * radius^2 (~2000 kg m^2 on a full tank). How much the mass resists being
## turned: the front tyres have to wind the car up into a corner and back out
## of it. A mid-engined car keeps its mass near the middle (~1.2); a 911 with
## the engine slung out behind the rear axle gets more. Higher = lazier
## turn-in that carries on longer, lower = darty.
# was a const -> read from the car's config (mass.yaw_gyration_radius,
# required); the certified value stays here as the fallback default.
static var YAW_GYRATION_RADIUS := 1.25

# --- Engine ------------------------------------------------------------------

## Torque curve at full throttle: Vector2(rpm, torque [Nm]) anchor points,
## linearly interpolated, flat below the first point. 245 Nm peak at 4500 rpm,
## ~150 kW peak power at 6000 rpm.
# was a const -> read from the car's config (engine.torque_curve, required);
# the certified value stays here as the fallback default.
static var TORQUE_CURVE: Array[Vector2] = [
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
## _ready on, and after every reset; a cold start is out of scope.
# was "there is no starter and no stall" -> there are both: see STALL_RPM.
# was a const -> read from the car's config (engine.idle_rpm, required); the
# certified value stays here as the fallback default.
static var IDLE_RPM := 900.0

## Under this the engine stops running [rpm]: it cannot fire slowly enough to
## keep itself turning, whatever brought it down here (engine_running = false:
## no combustion, no burn, no exhaust, the tach runs down to 0 on the engine's
## friction). Half of idle, a road engine's order. The car's own clutch never
## lets it come to that: it opens at CLUTCH_DISENGAGE_RPM and feathers the
## launch over a floor that starts at IDLE_RPM, and the idle controller holds
## the creep's sliver. What gets an engine down here is the driver's own clutch
## foot (see CLUTCH_PEDAL_SPEED) letting the clutch in on more car than the
## engine can move, or a dry tank.
# was a const -> read from the car's config (engine.stall_rpm, optional); the
# certified value here is the fallback default a config without it gets.
static var STALL_RPM := 450.0

## The starter motor (the starter key): torque on the crankshaft with the
## engine standing [Nm], easing off in a line to none at STARTER_FREE_RPM [rpm],
## as an electric motor's does. Only while the engine is not running. Against
## ENGINE_INERTIA and the engine's friction that turns a stopped engine past
## ENGINE_CATCH_RPM in ~0.2 s, and with a dry tank spins it at ~620 rpm for as
## long as it cranks. Cranking burns no fuel: nothing burns until the
## engine has caught (the few drops a real start takes are not modelled).
## With a full battery: what the starter really makes is this times the
## battery's cranking strength (battery_cranking_strength, 1 on a full one),
## and every Nm of it is current drawn from the battery (STARTER_POWER).
# was a const -> read from the car's config (engine.cranking_torque,
# optional); the certified value here is the fallback default a config without
# it gets.
static var CRANKING_TORQUE := 150.0
# was a const -> read from the car's config (engine.starter_free_rpm,
# optional); the certified value here is the fallback default a config without
# it gets.
static var STARTER_FREE_RPM := 700.0

## A fresh press of the starter key on an engine that is not running cranks for
## this long [s of physics time] whether the key is held or not, as a modern
## car's starter does on one push of the button; held longer, it cranks for as
## long as it is held. Four times what a catch takes (~0.2 s).
## was the key held and nothing else -> the cycle: a tap of one tick wound the
## engine to ~96 rpm, so tapping the key never restarted a stalled engine (the
## user's report from the driving seat).
# was a const -> read from the car's config (engine.starter_cycle_time,
# optional); the certified value here is the fallback default a config without
# it gets.
static var STARTER_CYCLE_TIME := 0.8

## Turning at least this fast [rpm] with fuel in the tank, an engine that is not
## running catches (engine_running = true) and the idle controller takes it up
## to IDLE_RPM. Above STALL_RPM, so a caught engine is not stalled again on the
## spot. Only the starter ever turns it: the car keeps its clutch open on an
## engine that is not running (see _clutch_target), there is no bump start.
# was a const -> read from the car's config (engine.engine_catch_rpm,
# optional); the certified value here is the fallback default a config without
# it gets.
static var ENGINE_CATCH_RPM := 500.0

## Rev limiter [rpm]: a fuel cut. At this speed the engine stops firing and
## falls back on its own friction until LIMITER_RESUME_RPM, then fires again:
## held against it, the revs bounce between the two (~8 times a second with
## no load). Free, the engine never turns faster than this; in gear the car's
## momentum can carry it a few rpm past before the cut bites.
# was a const -> read from the car's config (engine.redline_rpm, required);
# the certified value stays here as the fallback default.
static var REDLINE_RPM := 7200.0

## Engine speed at which the rev limiter lets the fuel back in [rpm].
# was a const -> read from the car's config (engine.limiter_resume_rpm,
# required); the certified value stays here as the fallback default.
static var LIMITER_RESUME_RPM := 7000.0

## Moment of inertia of what turns with the crankshaft [kg m^2]: crank,
## flywheel, clutch cover. 0.25 is the order of the real 986's flat six with
## its dual-mass flywheel. The engine speed is a state of its own, wound up and
## down by torque against this: d(omega) / dt = net torque / ENGINE_INERTIA.
## With no load, full throttle takes it from idle to the limiter in ~0.8 s.
## Lower = revs that snap up and down, higher = a lazy engine.
# was a const -> read from the car's config (engine.engine_inertia, required);
# the certified value stays here as the fallback default.
static var ENGINE_INERTIA := 0.25

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
# was a const -> read from the car's config (engine.friction_torque,
# required); the certified value stays here as the fallback default.
static var ENGINE_FRICTION_TORQUE := 12.0
# was a const -> read from the car's config (engine.friction_torque_per_rpm,
# required); the certified value stays here as the fallback default.
static var ENGINE_FRICTION_TORQUE_PER_RPM := 0.007

## Idle controller: torque it adds per rad/s the engine is below IDLE_RPM, on
## top of what carries the friction there [Nm per rad/s]; 2.5 against
## ENGINE_INERTIA closes a gap at 10 per second, no overshoot ...
# was a const -> read from the car's config (idle.control_gain, optional); the
# certified value here is the fallback default a config without it gets.
static var IDLE_CONTROL_GAIN := 2.5

## ... and the most throttle it may open by itself (0..1): ~35 Nm net at idle.
# was a const -> read from the car's config (idle.control_max_throttle,
# optional); the certified value here is the fallback default a config without
# it gets.
static var IDLE_CONTROL_MAX_THROTTLE := 0.3

# was ENGINE_BRAKE_TORQUE_PER_RPM 0.01 (an explicit engine-brake force at the
# wheels) -> removed with the kinematic engine speed: engine braking is
# ENGINE_FRICTION_TORQUE* through the locked clutch and the gear.
# LAUNCH_RPM moved to the Clutch section, where it means something now.

# --- Fuel and exhaust ----------------------------------------------------------

# The engine burns what its work costs. What the burning fuel makes on the
# crankshaft is the combustion torque (see _engine_net_torque: the torque curve
# plus the losses, times the throttle the engine really has, the idle
# controller's share included); times the engine speed that is a power [W], and
# the fuel that takes is
#   burn [kg/s] = combustion torque x engine_omega / FUEL_BURN_EFFICIENCY / FUEL_LHV
# Idling (~18 Nm at 900 rpm) that is ~0.6 L/h, flat out at 7000 rpm (~250 Nm)
# ~67 L/h; a certified handling run burns a few hundredths of a litre. The fuel
# in the tank is mass the car carries (fuel_mass, in total_mass()). With the
# tank dry nothing burns: the engine runs down on its friction, stops running
# under STALL_RPM and stays down until there is fuel again (a reset fills the
# tank and starts the engine; fuel put in any other way takes the starter).
# was "stays down (there is no starter) until a reset fills the tank" -> the
# starter, see CRANKING_TORQUE.

## What the tank holds [L]: the 1997 Boxster 986's tank. A reset fills it.
# was a const -> read from the car's config (fuel.tank_capacity_l, required);
# the certified value stays here as the fallback default.
static var FUEL_TANK_CAPACITY_L := 64.0

## Share of the fuel's heat that arrives on the crankshaft as combustion torque
## (no unit): a petrol engine's indicated efficiency, ~0.3 across the map.
# was a const -> read from the car's config (fuel.burn_efficiency, required);
# the certified value stays here as the fallback default.
static var FUEL_BURN_EFFICIENCY := 0.30

## Lower heating value of petrol [J/kg].
# was a const -> read from the car's config (fuel.lhv, required); the
# certified value stays here as the fallback default.
static var FUEL_LHV := 44.0e6

## Density of petrol [kg/L]: 64 L weigh ~48 kg.
# was a const -> read from the car's config (fuel.density, required); the
# certified value stays here as the fallback default.
static var FUEL_DENSITY := 0.745

## The same car with a dry tank [kg], ~1252: the part of its mass that never
## changes. What the car weighs on the road is total_mass(): this plus the fuel
## in the tank (fuel_mass) plus whatever it carries (payload_mass), and every
## force, inertia and weight in the model reads that one figure.
# was CAR_MASS 1300.0, the one mass of the car whatever was in it -> KERB_MASS
# 1300.0 less a full tank (64 L, 47.68 kg) - the 1300 kg had the fuel in them
# all along (a kerb weight does), so the car on a full tank weighs what it
# always did and gets lighter as it burns. 1300 for the dry car was tried: the
# 48 kg on top took the launch in 1st off the rear tyres' limit (grip use 0.981,
# smoke asks for 0.999) and a full stop 2 mm into the front bump stops (7.2 cm
# of 7).
# was a const in the Mass section, above the tank it reads -> down here, a
# static var's initializer only seeing what is declared above it; and derived,
# never read: worked out again from the config's numbers when a car reads them
# (_derive_from_config, the same sum as here).
static var BASE_MASS := KERB_MASS - FUEL_TANK_CAPACITY_L * FUEL_DENSITY

## Combustion events per turn of the crankshaft: a four-stroke fires each
## cylinder every other turn, the flat six three times a turn (see
## exhaust_events).
# was a const -> read from the car's config (engine.firings_per_revolution,
# optional); the certified value here is the fallback default a config without
# it gets.
static var FIRINGS_PER_REVOLUTION := 3.0

## Share of exhaust_flow that the throttle alone makes, at no revs at all
## (0..1); the rest comes with the engine speed, all of it at REDLINE_RPM. An
## open throttle at low revs already puffs, the same throttle at the limiter
## blows.
# was a const -> read from the car's config (exhaust.flow_at_rest, optional);
# the certified value here is the fallback default a config without it gets.
static var EXHAUST_FLOW_AT_REST := 0.3

## How quickly exhaust_flow follows the engine [1/s]: the gas has the manifold
## and the pipes to get through, ~0.1 s. Lower = lazier smoke.
# was a const -> read from the car's config (exhaust.flow_rate, optional); the
# certified value here is the fallback default a config without it gets.
static var EXHAUST_FLOW_RATE := 10.0

# --- Electrical ------------------------------------------------------------------

# A 12 V lead-acid starter battery and a belt-driven alternator, kept in energy
# [J] and power [W]: the one thing in the car that runs on electricity by name
# is the starter, and what the model keeps is how much the battery has in it
# (battery_charge, 0..1 of what it held when new) and how much of that it has
# lost for good (battery_wear). Every tick (_advance_battery):
#   engine off:      the key-on load drains it (BATTERY_KEY_ON_LOAD);
#   cranking:        the starter draws on it, current with the torque it makes
#                    (_advance_engine, STARTER_POWER);
#   engine running:  the alternator charges it with what is left after the
#                    ignition's own loads (alternator_power less
#                    BATTERY_RUNNING_LOAD), at the battery's charge efficiency,
#                    tapering off as it fills (BATTERY_TAPER_CHARGE).
# What a flat battery does: the starter's torque follows its cranking strength
# (the square root of the charge, see battery_cranking_strength), so a weak
# battery winds the engine up more slowly against ENGINE_INERTIA and takes
# longer to ENGINE_CATCH_RPM, one under ~13 % never gets there and an empty one
# turns nothing. Nothing of that is scripted: it falls out of the starter's
# torque line against the engine's friction. A RUNNING engine never fails for
# want of the battery (the alternator and the battery run the ignition between
# them): no electrical stalling. And a battery run down to
# BATTERY_DEEP_DISCHARGE_CHARGE is aged by it, once per such discharge and for
# every second it is left there (BATTERY_DEEP_DISCHARGE_WEAR,
# BATTERY_FLAT_WEAR_RATE): its capacity shrinks from the top, it fills to less
# and, fuller than it can get, cranks weaker than a new one.
# What is NOT counted twice: the alternator's drag on the belt and the fuel
# pump, injection and ignition the running engine feeds are inside the engine's
# own figures already - ENGINE_FRICTION_TORQUE is the installed engine's losses,
# accessories on the belt included, and the burn pays for it (see Fuel and
# exhaust) - so nothing here adds a torque to the crankshaft or a drop of fuel;
# the electrical side alone is kept. That is also what keeps every certified
# run to the bit: a running engine's physics never reads the battery, only the
# starter does, and the certified runs never crank. And the battery's ~20 kg
# are in KERB_MASS as they are in the real car's kerb weight: the car's mass
# does not change with it.
# Kept from one session to the next where the odometer is (_load_stored_battery):
# a car left with a flat battery starts with one, and what a deep discharge has
# taken stays taken. A reset (R) is a fresh car: full and healthy, as it fills
# the tank, without a word to the file.

## Nominal voltage of the electrical system [V]: what turns a battery's amp
## hours into joules. Every car here is a 12 V car; not a car's number.
const BATTERY_NOMINAL_VOLTAGE := 12.0

## What the battery held when new [Ah]: a 986's ~50 Ah starter battery; times
## 3600 s and BATTERY_NOMINAL_VOLTAGE that is BATTERY_CAPACITY_J.
# read from the car's config (battery.capacity_ah, optional); the certified
# value here is the fallback default a config without it gets.
static var BATTERY_CAPACITY_AH := 50.0

## The electrical power the starter draws on a standing crankshaft with a full
## battery [W]: ~1.5 kW, ~125 A off a 12 V battery. It is a DC motor: the
## current, and the power with it, goes with the torque it makes, so the draw
## eases off along the same line as CRANKING_TORQUE, to none at
## STARTER_FREE_RPM. A catch takes ~0.2 s of it, ~170 J (measured 166 J in
## tests/battery_test.gd): a full battery of BATTERY_CAPACITY_J is ~13 000
## starts.
# read from the car's config (battery.starter_power, optional); the certified
# value here is the fallback default a config without it gets.
static var STARTER_POWER := 1500.0

## What the car draws with the key on and the engine off [W]: the ECU awake,
## the cluster lit, the dash's lamps - ~2.5 A. A car in the game always has its
## key on; the 20 .. 50 mA a locked, parked car sleeps on is not what this is.
## 2.16 MJ over 30 W is ~20 hours from full to flat.
# read from the car's config (battery.key_on_load, optional); the certified
# value here is the fallback default a config without it gets.
static var BATTERY_KEY_ON_LOAD := 30.0

## What the ignition takes off the alternator while the engine runs [W]: the
## fuel pump, the coils and injectors, the ECU - ~10 A at 14 V. The
## alternator's output less this is what reaches the battery; under this (the
## alternator barely turning) the battery makes up the difference. The fuel
## these loads cost is in the engine's burn already (see Electrical).
# read from the car's config (battery.running_load, optional); the certified
# value here is the fallback default a config without it gets.
static var BATTERY_RUNNING_LOAD := 150.0

## The most the alternator makes [W]: the 986's ~120 A unit at its 14.4 V
## regulator would be ~1.7 kW, rated hot and on the bench ~1.5 kW.
# read from the car's config (battery.alternator_power, optional); the
# certified value here is the fallback default a config without it gets.
static var ALTERNATOR_POWER := 1500.0

## The alternator's output against engine speed [rpm, the engine's: the belt
## ratio is inside these two]: none under ALTERNATOR_CUT_IN_RPM, rising in a
## line to ALTERNATOR_POWER at ALTERNATOR_RATED_RPM and flat from there. Real
## alternators make little at idle and their rated output from ~2000 engine
## rpm up: at the 900 rpm idle this one makes a fifth of its rating, 300 W, of
## which 150 W are left for the battery; at 2500 rpm and above 1350 W.
# read from the car's config (battery.alternator_cut_in_rpm /
# alternator_rated_rpm, optional); the certified values here are the fallback
# defaults a config without them gets.
static var ALTERNATOR_CUT_IN_RPM := 500.0
static var ALTERNATOR_RATED_RPM := 2500.0

## Share of what goes into the battery that is kept as charge (no unit): a
## lead-acid's ~0.85, the rest is heat and gassing.
# read from the car's config (battery.charge_efficiency, optional); the
# certified value here is the fallback default a config without it gets.
static var BATTERY_CHARGE_EFFICIENCY := 0.85

## From this share of a full charge up (0..1, of what the battery can hold as
## worn as it is) the battery takes less and less, in a line to nothing at
## full: the absorption stage, where the regulator's voltage holds and the
## current falls away. Under it the battery takes all the alternator has left.
# read from the car's config (battery.taper_charge, optional); the certified
# value here is the fallback default a config without it gets.
static var BATTERY_TAPER_CHARGE := 0.8

## Under this charge (0..1) a battery is deeply discharged, and it costs it:
## a tenth. Plates sulphate below there, and a lead-acid does not come all the
## way back from it. Where the starter gives up (~13 %) is just over it.
# read from the car's config (battery.deep_discharge_charge, optional); the
# certified value here is the fallback default a config without it gets.
static var BATTERY_DEEP_DISCHARGE_CHARGE := 0.1

## Share of the new battery's capacity a deep discharge takes for good (0..1),
## once, the tick the charge goes under BATTERY_DEEP_DISCHARGE_CHARGE, and
## again the next time it goes under from above: 3 % each.
# read from the car's config (battery.deep_discharge_wear, optional); the
# certified value here is the fallback default a config without it gets.
static var BATTERY_DEEP_DISCHARGE_WEAR := 0.03

## What a battery LEFT deeply discharged loses on top [share of the new
## capacity per second]: 1 % an hour (2.78e-6 / s), a battery left flat for a
## few days is one to throw away. Physics time: nothing ages a car between
## sessions.
# read from the car's config (battery.flat_wear_rate, optional); the certified
# value here is the fallback default a config without it gets.
static var BATTERY_FLAT_WEAR_RATE := 2.78e-6

## The most a battery can lose (0..1 of the new capacity): 0.9. A tenth is
## always left, so there is a capacity to hold a charge against; a battery
## that far gone fills to a tenth and its starter turns nothing (a full tenth
## is under the ~13 % a catch takes). Replacing a battery is not modelled:
## a reset is a new car, battery and all.
const BATTERY_WEAR_LIMIT := 0.9

## What the battery held when new [J]: BATTERY_CAPACITY_AH x 3600 x
## BATTERY_NOMINAL_VOLTAGE, 2.16 MJ. Derived, never read: worked out again from
## the config's number when a car reads it (_derive_from_config).
static var BATTERY_CAPACITY_J := BATTERY_CAPACITY_AH * 3600.0 * BATTERY_NOMINAL_VOLTAGE

# --- Gearbox -----------------------------------------------------------------

## Gear ratios; index 0 is neutral, 1..5 the forward gears (986 5-speed).
# was a const -> read from the car's config (gearbox.ratios, required); the
# certified value stays here as the fallback default.
static var GEAR_RATIOS: Array[float] = [0.0, 3.82, 2.20, 1.52, 1.22, 0.97]

## Final drive (differential) ratio.
# was a const -> read from the car's config (gearbox.final_drive, required);
# the certified value stays here as the fallback default.
static var FINAL_DRIVE := 3.89

## Reverse gear ratio: a gear like the others, engine, clutch and driven wheels
## work through it the same way (the wheels turning backwards).
# was tach-only, the drive force in reverse a flat REVERSE_ACCEL x CAR_MASS ->
# the real thing. What is left of the flat force is the driver's foot easing
# off into MAX_REVERSE_SPEED (see _pedals).
# was a const -> read from the car's config (gearbox.reverse_ratio, required);
# the certified value stays here as the fallback default.
static var REVERSE_RATIO := 3.55

## Share of engine torque that reaches the wheels (0..1); the rest is lost in
## the gearbox and differential.
# was a const -> read from the car's config (gearbox.drivetrain_efficiency,
# required); the certified value stays here as the fallback default.
static var DRIVETRAIN_EFFICIENCY := 0.88

## Rolling radius of the tyres [m]; must match the wheel mesh. Turns wheel
## torque into force and wheel speed into engine RPM.
const WHEEL_RADIUS := 0.34

# --- Clutch --------------------------------------------------------------------

# A dry plate between the engine and the gearbox, worked by the car: see
# _clutch_target for when it opens and closes. In manual mode the driver has a
# clutch pedal on top of that (see CLUTCH_PEDAL_SPEED). Slipping,
# it passes a friction torque from the faster side to the slower one, the same
# torque on both; once the two sides turn together it locks and they are one
# shaft (see _advance_drivetrain).

# was "worked by the car (there is no clutch pedal)" -> there is one, in manual
# mode; the car still works the clutch whenever the driver's foot is off it.

## Most torque the clutch passes fully engaged [Nm]. Road car clutches are sized
## at 1.5 - 2.5 times the engine's peak torque so they never slip once home;
## ~2 x 245 Nm. It is also the most the clutch can push into the driveline
## while it drags a fast-turning engine down after a shift or a launch: more
## than the engine itself ever makes. Higher = harsher catches.
# was a const -> read from the car's config (gearbox.clutch_torque_max,
# required); the certified value stays here as the fallback default.
static var CLUTCH_TORQUE_MAX := 500.0

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
# The automatic's comfort and eco programs shift up under this, and their
# launch is held no higher than they shift at (see _advance_drivetrain).
# was a const -> read from the car's config (launch.rpm, required); the
# certified value stays here as the fallback default.
static var LAUNCH_RPM := 4000.0

## While the revs are still under that floor the clutch takes this share of
## the engine's torque (0..1) and the rest winds the engine up: the car moves
## off at once, gently, and harder as the revs arrive ...
# was a const -> read from the car's config (launch.clutch_share, optional);
# the certified value here is the fallback default a config without it gets.
static var LAUNCH_CLUTCH_SHARE := 0.5

## ... over the last this many rad/s (~500 rpm) under the floor the share eases
## up to all of it, so the clutch bites over a few ticks and not in one.
# was a const -> read from the car's config (launch.bite_band, optional); the
# certified value here is the fallback default a config without it gets.
static var LAUNCH_BITE_BAND := 50.0

## Time the clutch takes to come in from fully open pulling away [s]: the
## torque it can pass ramps up over this, the engine flares against it and the
## car moves off on the slip torque.
# was a const -> read from the car's config (gearbox.clutch_engage_time,
# required); the certified value stays here as the fallback default.
static var CLUTCH_ENGAGE_TIME := 0.5

## The clutch pedal (the clutch key, the driver's LEFT foot; the two pedal keys
## are the right one's): how fast the foot moves it, down and up [1/s], travel
## per second, 1 = the whole pedal: 0.2 s from up to the floor, and as long back
## up through the bite point. A key is on / off, so this is a quick, even foot,
## as the right one is. Held, the clutch can come in no further than the pedal
## lets it (1 - clutch_pedal): on the floor it is open, whatever the car would
## do. And the driver's foot wins: from the moment the pedal is touched until
## the clutch is home again (or open for the car's own reasons) the car's
## feathering stays out of it - no launch floor holding the revs up, no easing
## for wheelspin, no CLUTCH_ENGAGE_TIME: the clutch comes in as the foot comes
## up and passes what it passes. Revs up and the pedal let go is a clutch dump
## (wheelspin, with no slip limit); the pedal let go on an idling engine with
## more car to move than it can is a stall (STALL_RPM).
##   Manual mode only. In automatic the key does nothing: the car that shifts
## for itself is a two-pedal car, there is no left pedal to press (and no way to
## stall it by mistake).
const CLUTCH_PEDAL_SPEED := 5.0

## The same on the move, after a gear change [s]: the revs the engine has too
## many (upshift) or too few (downshift) are dragged to the new gear's speed
## within about this. Shorter = quicker, harsher shifts.
# was a const -> read from the car's config (gearbox.clutch_shift_engage_time,
# required); the certified value stays here as the fallback default.
static var CLUTCH_SHIFT_ENGAGE_TIME := 0.1

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

# Creep. An automatic held on the brake in gear pulls away gently when the
# brake is let go. This car has a plate clutch and no torque converter, so it
# does what automated clutches do to stand in for one: standing in 1st,
# automatic, the brake that held it released and nothing asked of either pedal,
# the car lets the clutch in by a sliver and the idling engine (the idle
# controller carrying the load, the fuel paying for it) pushes the car along at
# a crawl, the sliver easing out as the crawl speed comes. It goes through the
# clutch like everything else: clutch_torque, the driven tyres' slip, the
# feathering under the launch floor. The pedals are never touched
# (throttle_pedal and brake_pedal show the feet). It is the brake coming off
# that starts it: a car that came to rest by itself (a reset, a coast-down, a
# slide scrubbed off, a mission's start point) stands until its driver does
# something. Forward only: there is no creep in reverse, and none in manual
# mode (the shift keys make the driver the one who decides when the car moves).
# The crawl stays under STANDSTILL_SPEED, so the brake pressed anew selects
# reverse from it as it does from rest.

## How far the clutch comes in for the creep at a standstill (0..1): the torque
## converter's stall push, as a plate clutch gives it. ~10 Nm at the clutch,
## ~390 N at the wheels in 1st, twice the rolling resistance. It eases out
## linearly with forward speed, to nothing at CREEP_FREE_SPEED, as a
## converter's push does when its turbine catches its pump up.
# was a const -> read from the car's config (creep.clutch_engagement,
# optional); the certified value here is the fallback default a config without
# it gets.
static var CREEP_CLUTCH_ENGAGEMENT := 0.02

## Forward speed at which the creep's push has eased out altogether [m/s]. The
## crawl settles where what is left of the push carries the rolling resistance:
## ~0.43 m/s (1.5 km/h) on a full tank, slower loaded.
# was a const -> read from the car's config (creep.free_speed, optional); the
# certified value here is the fallback default a config without it gets.
static var CREEP_FREE_SPEED := 0.9

## The creep only ever starts from a true standstill: slower than this [m/s],
## held there by the brake ...
# was a const -> read from the car's config (creep.engage_speed, optional);
# the certified value here is the fallback default a config without it gets.
static var CREEP_ENGAGE_SPEED := 0.05

## ... and then, the brake let go, still standing for this long [s]: the car
## picks itself up as the clutch finds its bite, not the tick the foot is off.
# was a const -> read from the car's config (creep.dwell, optional); the
# certified value here is the fallback default a config without it gets.
static var CREEP_DWELL := 0.4

## Rolling faster than this either way [m/s] the creep lets go, and waits for
## the next standstill. A fence: the crawl settles well under it.
# was a const -> read from the car's config (creep.max_speed, optional); the
# certified value here is the fallback default a config without it gets.
static var CREEP_MAX_SPEED := 0.8

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
# was a const -> read from the car's config (brakes.bias_front, required); the
# certified value stays here as the fallback default.
static var BRAKE_BIAS_FRONT := 0.6

# --- Tyres and aero ----------------------------------------------------------

## Tyre friction coefficient: a tyre can push with at most this times its load,
## in any direction (1997 road tyres, ~0.95). Through 1st the engine's torque
## from ~3000 rpm would be more than the rear tyres can transmit, and on a
## slipping clutch (the launch) it is; with the clutch locked a quarter of it
## winds up the engine's own inertia and the rears run just under their peak.
## 2nd and up stay well under it.
# was a const -> read from the car's config (tyres.mu, required); the
# certified value stays here as the fallback default.
static var TYRE_MU := 0.95

## Grip of each axle's tyres relative to TYRE_MU (no unit). The Boxster's 255
## rears grip their share of the weight a little better than its 205 fronts
## grip theirs (the two average out to 1.0 over the static weight split). That
## is what makes the car safe at the limit, as it does the real one: with both
## ends sliding the front gives up first, the nose pushes wide and the tail
## pulls the car straight again, until power or the handbrake says otherwise.
## Equal = neutral: a slide, once started, just carries on.
# was a const -> read from the car's config (tyres.front_grip, required); the
# certified value stays here as the fallback default.
static var FRONT_TYRE_GRIP := 0.94
# was a const -> read from the car's config (tyres.rear_grip, required); the
# certified value stays here as the fallback default.
static var REAR_TYRE_GRIP := 1.04

## Slip ratio at which a tyre makes its peak force ALONG the wheel (no unit):
## (wheel surface speed - road speed) / road speed, 0.1 = the wheel turning
## 10 % faster than the road (drive) or slower (braking). The same curve shape
## as sideways (_tyre_curve): up to the peak the tyre hooks up, past it the
## wheel spins up or locks and the force eases to TYRE_SLIDE_GRIP of the peak.
# was a const -> read from the car's config (tyres.peak_slip_ratio, required);
# the certified value stays here as the fallback default.
static var PEAK_SLIP_RATIO := 0.1

## Slip ratio the ABS holds a braked wheel at when the pedal asks for more than
## the tyre has (no unit). A little past the peak, as real systems run: in a
## straight line that costs ~3 % of the stop, and braking and steering at once
## it gives the stop the bigger share of the front tyres' grip rather than the
## other way round. With the ABS switched off (abs_on) nothing holds the wheel:
## a full pedal asks the front axle for more than its tyres have, the front
## wheels lock (wheel speed 0, slip ratio -1) and slide on TYRE_SLIDE_GRIP with
## next to no sideways hold (see _tyre_force: a locked wheel drags against the
## way it travels, and MIN_COMBINED_GRIP has faded out by then) - a longer stop,
## and no steering until the pedal comes up.
# was a const -> read from the car's config (tyres.abs_slip_ratio, required);
# the certified value stays here as the fallback default.
static var ABS_SLIP_RATIO := 0.15

## Slip ratio the driver's feet hold a spinning driven wheel at while the
## clutch slips and passes more than the tyre can take (no unit): pulling away
## flat out, dropping the clutch on a revving engine. On / off keys cannot
## feather anything, so this does (_ease_for_wheelspin). 0.25 is proper
## wheelspin, 2.5 times the peak: the tyre pushes with ~0.9 of its grip and has
## little left for holding the car sideways (MIN_COMBINED_GRIP is what it
## keeps, fading out from here to a slip ratio of 1). Higher = wilder
## wheelspin off the line, less drive.
## This, with the launch floor's hold on the revs (LAUNCH_RPM), is the car's
## traction control: switched off (tcs_on) the clutch is let in the way a driver
## without one does it - the revs flare to the floor as before, and once they
## are there the clutch comes in for good and passes all it can (up to
## CLUTCH_TORQUE_MAX, twice what the engine makes: the flywheel's revs go into
## the driveline), with no slip limit. In 1st that is far more than the rear
## tyres hold: they spin up to the engine's speed, the clutch locks on spinning
## wheels, and past its peak the tyre pushes back with less (TYRE_SLIDE_GRIP),
## so the engine keeps them spinning until the driver lifts or the car has
## caught them up. Nothing about the tyres changes; the wheelspin is what the
## tyre curve makes of the torque.
# was a clamp on the slip ratio itself, whatever wound it up -> the clutch
# foot's limit while the clutch slips. With the clutch locked nothing holds the
# wheels back but the engine's own inertia and the limiter: what the throttle
# spins up, the throttle has to let go again.
# was a const -> read from the car's config (tyres.drive_slip_ratio,
# required); the certified value stays here as the fallback default.
static var DRIVE_SLIP_RATIO := 0.25

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
# was a const -> read from the car's config (tyres.axle_inertia, required);
# the certified value stays here as the fallback default.
static var AXLE_INERTIA := 2.4

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
# was a const -> read from the car's config (tyres.front_peak_slip_angle,
# required); the certified value stays here as the fallback default.
static var FRONT_PEAK_SLIP_ANGLE := 0.11

## The same for the rear tyres [rad] (0.10 = 5.7 degrees): the Boxster's wide
## 255 rears are stiffer than its 205 fronts. The balance of the car is the
## difference between the two: understeer gradient =
## (front - rear peak angle) / (1.5 * TYRE_MU * g), here ~0.4 degrees per g.
## Front above rear = understeer: stable at any speed, and at the limit the
## nose pushes wide before the tail lets go. Equal = neutral. Rear above front
## = oversteer, with a speed above which the car will not run straight. More
## understeer than this (0.03 apart) and the nose visibly swings back past
## straight when the steering is let go at speed.
# was a const -> read from the car's config (tyres.rear_peak_slip_angle,
# required); the certified value stays here as the fallback default.
static var REAR_PEAK_SLIP_ANGLE := 0.10

## Sideways force a fully sliding tyre still makes, as a share of its peak
## (0..1): rubber sliding over the road grips less than rubber keying into it.
## The curve eases from the peak down to this over TYRE_SLIDE_ONSET. Also the
## grip of a locked (handbraked) wheel. 1.0 = no drop, the limit is a plateau;
## lower = the car lets go more suddenly and a slide scrubs less speed.
## The front tyres' figure, and a locked rear's; rear tyres that still roll
## have their own (REAR_TYRE_SLIDE_GRIP).
# was a const -> read from the car's config (tyres.slide_grip, required); the
# certified value stays here as the fallback default.
static var TYRE_SLIDE_GRIP := 0.85

## How far past the peak the tyre is ~two thirds of the way down to
## TYRE_SLIDE_GRIP, in peak slip angles. Higher = a wider, more forgiving top.
# was 2.0 -> 3.0 (iteration 3B, the rubber pass) - the top of the curve read as
# plastic: a front tyre turned past its peak gave its grip up within a dozen
# degrees, and on / off keys live out there. With the wider top the fall is
# spread over ~19 degrees at the front: measured at 60 km/h, coasting, the car
# corners at 0.94 g with 11 degrees of front wheel (was 0.93), 0.90 g with 16.5
# (0.89), 0.82 g scrubbing at full lock (0.79); the peak itself is untouched
# (0.96 g at 6.9 - 8.3 degrees). Handbrake slides go in exactly as before (yaw
# rate 0.64 / 1.14 / 1.62 rad/s at the release of a 12 / 20 / 30 tick pull).
# was a const -> read from the car's config (tyres.slide_onset, required); the
# certified value stays here as the fallback default.
static var TYRE_SLIDE_ONSET := 3.0

## The same for rear tyres that still roll (0..1): the wide rears hold on in a
## slide where the fronts let go. This is what ends a slide nobody is driving:
## with both ends sliding the yaw moments of the two axles nearly cancel (the
## REAR / FRONT_TYRE_GRIP margin of 1.106 is eaten by the weight a sliding,
## slowing car moves onto its nose, x0.94, and by the rear sliding deeper down
## the curve than the front, x0.98), and the more the sliding rear holds over
## the sliding front, the harder the tail is pulled back into line. A grip
## figure like the rest: it knows nothing of the steering or the heading. A
## locked wheel stays on TYRE_SLIDE_GRIP (eased over as the lock leaves the
## tyres, see REAR_LOCK_RECOVERY_RATE), so the handbrake kicks the tail out and carries a
## spin as before. Lower = slides hang on longer, equal to TYRE_SLIDE_GRIP = a
## slide with the keys released carries on as a drift; 1.0 = no limit to go
## over at all, a plateau.
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
# was 1.0 -> 0.97 (iteration 3B, the rubber pass) - at 1.0 the rolling rear had
# no limit to go over: a plateau, the same grip however sideways, which is what
# read as plastic. At 0.97 (eased in over TYRE_SLIDE_ONSET, ~17 degrees) a
# rear that is sliding holds a little less than one that is hooked up, and
# gets that back as the slide comes in under the peak again: breakaway that
# builds (the slide grows 1.6 degrees per tick of handbrake all the way, 9.4 /
# 22.5 / 38.9 degrees for 12 / 20 / 30 ticks, was 9.4 / 22.4 / 38.3) and a
# recovery that takes a moment longer and then bites (nose back in line 1.00 /
# 1.53 / 1.48 s after the release, was 0.98 / 1.43 / 1.40), still with no
# swing back past straight (0.00 degrees before and after: the stability
# assist's share of a recovery, unchanged, sees to that). Power in 1st steps
# the tail a touch further out (peak rear slip 4.7 degrees at 0.45 of lock,
# was 4.5). Lower does not hold: 0.95 left the smoke test's scrubbed slide
# creeping on for 5.6 s, 0.92 for 6.5 (limit 6.0; 5.1 here), the way 0.85 did
# before 2I. Certified runs before -> after: slalom closest pass 2.72 -> 2.15 m,
# SPIN_180 184.3 -> 184.6 degrees, SPIN_360 362.4 -> 361.7, stop box margin
# 0.79 -> 0.61 m (the ABS runs its tyres 1.5 peaks out, where the wider top
# grips more: shorter stops), REVERSE_180 -186.8 -> -185.3.
# was a const -> read from the car's config (tyres.rear_slide_grip, required);
# the certified value stays here as the fallback default.
static var REAR_TYRE_SLIDE_GRIP := 0.97

## Drag coefficient Cd (no unit). Drag force is
## 0.5 * AIR_DENSITY * DRAG_COEFF * FRONTAL_AREA * speed^2 (~0.40 kg/m in
## all). 986: 0.31 roof up; 0.34 allows for the roof down. Balances full power
## in 5th at ~65 m/s (~234 km/h), just under the rev limiter.
## Replaces the flat AERO_DRAG 0.40 [kg/m], the same number in one lump.
# was a const -> read from the car's config (aero.drag_coeff, required); the
# certified value stays here as the fallback default.
static var DRAG_COEFF := 0.34

## Frontal area [m^2] (986: 1.93).
# was a const -> read from the car's config (aero.frontal_area, required); the
# certified value stays here as the fallback default.
static var FRONTAL_AREA := 1.93

## Downforce [N per (m/s)^2]: force pressing the car onto the road is this
## times speed squared, ~90 N at 60 km/h, ~490 N at 140, ~1250 N at 215 (a
## tenth of the car's weight). More load = more grip, so fast corners hold
## more than TYRE_MU g while slow ones are untouched. The road 986 makes next
## to none; this is the arcade aero kit. 0 = none.
# was a const -> read from the car's config (aero.downforce_coeff, required);
# the certified value stays here as the fallback default.
static var DOWNFORCE_COEFF := 0.35

## Share of the downforce that lands on the FRONT axle (0..1). Below the static
## front weight share (0.38) the rear gains more than the front: the faster the
## car goes, the more planted the tail and the less eager the nose.
# was a const -> read from the car's config (aero.balance_front, required);
# the certified value stays here as the fallback default.
static var AERO_BALANCE_FRONT := 0.35

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
# was a const -> read from the car's config (brakes.decel_g, required); the
# certified value stays here as the fallback default.
static var BRAKE_DECEL_G := 1.0

## Deceleration a full brake application asks for [m/s^2]: what the tyres
## could hold with every one of them at its limit, ~9.3 (0.95 g). The force
## (this times total_mass()) is split by BRAKE_BIAS_FRONT, put on each axle as a
## brake torque (with what it takes to slow the turning parts down as well,
## see _brake_torque), and each axle delivers what its grip allows (ABS holds a
## wheel at ABS_SLIP_RATIO, it never locks):
## with the fronts at their limit and the rears under theirs, a real stop
## comes out at ~0.9 of this, ~8.4 m/s^2 plus drag. (With the ABS switched off
## the fronts do lock under a full pedal, see ABS_SLIP_RATIO.)
# was a const -> derived, never read: worked out again from the config's
# numbers when a car reads them (_derive_from_config, the same sum as here).
static var BRAKE_DECEL := BRAKE_DECEL_G * TYRE_MU * 9.8

## Density of air [kg/m^3], for the drag force.
# was a const -> read from the car's config (aero.air_density, optional); the
# certified value here is the fallback default a config without it gets.
static var AIR_DENSITY := 1.225

## Rolling resistance [m/s^2], always on while the car rolls. With engine
## braking and aero drag it makes up the coast-down.
# was a const -> read from the car's config (brakes.coast_decel, optional);
# the certified value here is the fallback default a config without it gets.
static var COAST_DECEL := 0.15

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

## The automatic's three shift programs (gearbox_mode, the gearbox mode key
## goes round them: sport, comfort, eco, sport). Manual mode knows none of them.
##   SPORT    holds every gear to UPSHIFT_RPM and keeps the engine above
##            DOWNSHIFT_RPM: the program the car was certified with, and the one
##            it starts in.
##   COMFORT  shifts up at COMFORT_UPSHIFT_RPM, where sport would shift down,
##            and lets the revs fall to COMFORT_DOWNSHIFT_RPM: short-shifted,
##            quiet, easy on the fuel, and slower.
##   ECO      shifts up at ECO_UPSHIFT_RPM, as early as the engine's efficiency
##            allows, lets the revs fall to ECO_DOWNSHIFT_RPM, and gives the
##            engine no more than ECO_MAX_THROTTLE whatever the foot does.
## Every engine has its own sweet spots for every program: none of the figures
## below is picked by hand, each is what derived_shift_points makes of
## TORQUE_CURVE and the engine's friction, rounded to the 100 rpm, and the smoke
## test holds the two together. Another engine: run the helper on its curve.
# The shift points, the shares they are derived by and the box's timing stay
# consts in this file while the engine they are read off lives in the car's
# config: they are the certified program, rounded by hand to the 100 rpm, and
# the smoke test holds every one of them within 50 rpm of what
# derived_shift_points makes of the TORQUE_CURVE the car has loaded. A config
# with another curve fails that check until the constants here follow it: code
# and config are held together by the derivation, not by a second copy of the
# figures in the file.
# was enum GearboxMode { COMFORT, SPORT } -> ECO appended, never reordered: the
# user's report (2026-09-21), "we should have an eco mode as well, so the
# gearbox changes around perfect consumption not perfect torque".
enum GearboxMode { COMFORT, SPORT, ECO }

## SPORT changes up where the engine's full-throttle power (torque x speed) has
## fallen to this share of its peak, past the peak (0..1): every gear is used to
## the end of the power. 149.5 kW at 6000 rpm on this curve, 95 % of it at
## 6791 rpm.
const SPORT_POWER_SHARE := 0.95

## What each program keeps the engine above: the lowest engine speed at which it
## makes this share of its peak torque (0..1), and the program changes down
## under it. Sport stays in the fat of the curve, 90 % of 245 Nm from 2820 rpm
## up; comfort lets it down to 75 % (1594 rpm), eco to 70 % (1288 rpm), still
## clear of CLUTCH_DISENGAGE_RPM and the idle. COMFORT changes UP at sport's
## figure as well: it leaves a gear where the fat of the curve begins, at the
## speed sport would not let the engine fall to, and the two programs share no
## revs at all.
const SPORT_TORQUE_SHARE := 0.9
const COMFORT_TORQUE_SHARE := 0.75
const ECO_TORQUE_SHARE := 0.7

## ECO changes up at the highest engine speed at which the engine still turns
## fuel into work within this share of its best (0..1). What it goes by is the
## brake efficiency at full throttle, torque at the flywheel over the torque the
## burning fuel makes: TORQUE_CURVE / (TORQUE_CURVE + the engine's friction),
## the friction being what the fuel pays for and the car never sees (see Fuel
## and exhaust). On this engine 0.894 at 1000 rpm, 0.889 at 1500, 0.885 at 2000,
## 0.872 at 3000, 0.849 at 4500, 0.815 at 6000: best at the bottom of the curve
## and worse with every rpm of friction, within 1 % of the best up to 2002 rpm.
const ECO_EFFICIENCY_SHARE := 0.99

## The share of a program's upshift speed that a lower gear has to land under
## it for the box to change down into it (0..1): sport's certified
## DOWNSHIFT_MARGIN_RPM over its UPSHIFT_RPM, 1000 / 6800.
const DOWNSHIFT_MARGIN_SHARE := 0.147

## Automatic mode, SPORT, shifts up at this engine speed under throttle [rpm]:
## SPORT_POWER_SHARE of the peak power, 6791 rpm by derived_shift_points. The
## certified figure, and older than its derivation.
const UPSHIFT_RPM := 6800.0

## Automatic mode, SPORT, shifts down when the engine drops below this [rpm]:
## SPORT_TORQUE_SHARE of the peak torque, 2820 rpm by derived_shift_points, the
## certified figure likewise. Every upshift from UPSHIFT_RPM lands well above it
## (lowest: ~3900 rpm into 2nd), so the box never hunts between two gears.
const DOWNSHIFT_RPM := 2800.0

## Automatic mode, COMFORT, shifts up at this engine speed under throttle [rpm]:
## where the engine first makes SPORT_TORQUE_SHARE of its peak torque, 2820 rpm
## by derived_shift_points. Every gear is left as the engine comes into the fat
## of its curve and the next one picks up at 1600 - 2250 rpm; the upper half of
## the rev range is never used. Whatever the throttle: there is no kickdown,
## flat out in COMFORT is still COMFORT.
# was 4500.0, the torque peak ("every gear is left where the engine pulls
# hardest") -> 2800.0 - the user's report (2026-09-21): "in comfort mode it goes
# to 4000 to change, that is still sporty... nobody is racing in comfort/eco".
# Flat out from rest the box left 1st at 4526 rpm, now at 2829.
const COMFORT_UPSHIFT_RPM := 2800.0

## Automatic mode, COMFORT, shifts down when the engine drops below this [rpm]:
## COMFORT_TORQUE_SHARE of the peak torque, 1594 rpm by derived_shift_points.
## The upshift into 2nd lands right on it (1613 rpm from exactly
## COMFORT_UPSHIFT_RPM, less what the car loses during the change; the others
## at 1930 rpm and up): the margin below is what keeps the box from going
## straight back, the lower gear would land at the upshift speed again.
# was 2000.0 -> 1600.0 - it goes with the upshift speed above.
const COMFORT_DOWNSHIFT_RPM := 1600.0

## Automatic mode, ECO, shifts up at this engine speed under throttle [rpm]: the
## last of ECO_EFFICIENCY_SHARE of the engine's best brake efficiency, 2002 rpm
## by derived_shift_points. The next gear picks up at 1150 - 1600 rpm, the
## clutch locked and the engine pulling from there: the car's own clutch never
## lets a locked engine under IDLE_RPM, so low is not a stall.
const ECO_UPSHIFT_RPM := 2000.0

## Automatic mode, ECO, shifts down when the engine drops below this [rpm]:
## ECO_TORQUE_SHARE of the peak torque, 1288 rpm by derived_shift_points. The
## upshift into 2nd lands under it (~1150 rpm; the others at 1380 rpm and up),
## and the margin below holds the gear, as in COMFORT.
const ECO_DOWNSHIFT_RPM := 1300.0

## Automatic mode, ECO: the most throttle the engine is given, however far down
## the pedal is (0..1). What an eco program does on the road: the pedal's map is
## flattened, the floor is no longer all the engine has. Only the automatic's
## ECO; every other program, and manual mode, passes the pedal on untouched.
## Measured both ways, 400 m from rest with the key held: 0.082 L and 25.9 s
## with it (25 m/s at the end), 0.119 L and 21.7 s without (32 m/s), the same
## shift points either way. A third of the fuel for four seconds, and no check
## minds: it stays. Under it the pedal is what it is (half a pedal burns
## 0.061 L over the same 400 m with and without).
const ECO_MAX_THROTTLE := 0.7

## Automatic mode only shifts down if the lower gear lands at least this far
## below the program's upshift speed [rpm], so a downshift never triggers an
## instant upshift, and an upshift that lands under the program's downshift
## speed is not taken back: the lower gear would be at the upshift speed again.
## Sport's is the certified figure; comfort's and eco's are the same share of
## their own upshift speeds (DOWNSHIFT_MARGIN_SHARE: 415 and 294 rpm by
## derived_shift_points).
# was DOWNSHIFT_MARGIN_RPM for every program -> one each - 1000 rpm under eco's
# 2000 asks a lower gear to land under 1000 rpm, which is under where the car's
# clutch lets go (CLUTCH_DISENGAGE_RPM): eco would never have changed down on a
# turning engine at all, and comfort's changes down would all have been the
# margin's (at 1040 - 1450 rpm) and none COMFORT_DOWNSHIFT_RPM's.
const DOWNSHIFT_MARGIN_RPM := 1000.0
const COMFORT_DOWNSHIFT_MARGIN_RPM := 400.0
const ECO_DOWNSHIFT_MARGIN_RPM := 300.0

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
# was a const -> read from the car's config (tyres.load_grip_exponent,
# required); the certified value stays here as the fallback default.
static var LOAD_GRIP_EXPONENT := 0.7

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
# was a const -> read from the car's config (tyres.min_combined_grip,
# required); the certified value stays here as the fallback default.
static var MIN_COMBINED_GRIP := 0.4

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
# was a const -> read from the car's config (suspension.front_ride_frequency,
# required); the certified value stays here as the fallback default.
static var FRONT_RIDE_FREQUENCY := 1.5
# was a const -> read from the car's config (suspension.rear_ride_frequency,
# required); the certified value stays here as the fallback default.
static var REAR_RIDE_FREQUENCY := 1.7

## Damping ratio of each corner on its spring (no unit): 0.3 - 0.5 on a road
## car. 1 would settle without any overshoot, lower floats on after a crest.
## Unchanged from 2G; it now also damps pitch (ratio ~0.4, the car's pitch
## inertia being what its corner masses make it) and roll (~0.43 with the bars).
# was a const -> read from the car's config (suspension.ride_damping_ratio,
# required); the certified value stays here as the fallback default.
static var RIDE_DAMPING_RATIO := 0.4

## Sprung mass riding on one front / rear wheel at rest [kg]: ~247 and ~403.
## The car's as it stands ready to drive (KERB_MASS), not total_mass(): springs
## and dampers are chosen once, for that car, and a burning tank and a payload
## ride on them as they find them. A loaded car bounces a little slower and a
## little less damped on the same rates (300 kg on board: 1.35 / 1.53 Hz for
## 1.5 / 1.7). What the load does not do here is sink the car: each spring's
## seat carries its static share of what the car weighs NOW (see
## _corner_forces), so it stands at its ride height whatever is in it.
# was a const -> derived, never read: worked out again from the config's
# numbers when a car reads them (_derive_from_config, the same sum as here).
static var FRONT_CORNER_MASS := KERB_MASS * (1.0 - REAR_WEIGHT_FRACTION) * 0.5
# was a const -> derived, never read: worked out again from the config's
# numbers when a car reads them (_derive_from_config, the same sum as here).
static var REAR_CORNER_MASS := KERB_MASS * REAR_WEIGHT_FRACTION * 0.5

## Spring rate at the wheel [N/m]: corner mass x (TAU x ride frequency)^2.
## Front ~21.9 kN/m, rear ~46.0 kN/m (static compression 11.0 and 8.6 cm).
# was a const -> derived, never read: worked out again from the config's
# numbers when a car reads them (_derive_from_config, the same sum as here).
static var FRONT_SPRING_RATE := FRONT_CORNER_MASS * (TAU * FRONT_RIDE_FREQUENCY) * (TAU * FRONT_RIDE_FREQUENCY)
# was a const -> derived, never read: worked out again from the config's
# numbers when a car reads them (_derive_from_config, the same sum as here).
static var REAR_SPRING_RATE := REAR_CORNER_MASS * (TAU * REAR_RIDE_FREQUENCY) * (TAU * REAR_RIDE_FREQUENCY)

## Damper rate at the wheel [N s/m]: 2 x ratio x corner mass x TAU x ride
## frequency. Front ~1860, rear ~3440. One rate for bump and rebound.
# was a const -> derived, never read: worked out again from the config's
# numbers when a car reads them (_derive_from_config, the same sum as here).
static var FRONT_DAMPER_RATE := 2.0 * RIDE_DAMPING_RATIO * FRONT_CORNER_MASS * TAU * FRONT_RIDE_FREQUENCY
# was a const -> derived, never read: worked out again from the config's
# numbers when a car reads them (_derive_from_config, the same sum as here).
static var REAR_DAMPER_RATE := 2.0 * RIDE_DAMPING_RATIO * REAR_CORNER_MASS * TAU * REAR_RIDE_FREQUENCY

## Anti-roll bars [N per m of travel difference between an axle's two wheels]:
## the bar pushes the more compressed wheel down and lifts the other with this
## times the difference. Does nothing in heave and pitch. With the springs
## (~100 kNm/rad of roll stiffness on the 1.72 m track) the bars add ~38: the
## body rolls ~2.5 degrees per g, a sports car's figure; on springs alone it
## would be 3.6. Front-biased, as on the real car. The tyres work with AXLE
## loads (the bicycle model), so how the bars split the roll between the axles
## shows in wheel_loads and in the body, not in the balance of the car.
# was a const -> read from the car's config (suspension.front_anti_roll_rate,
# required); the certified value stays here as the fallback default.
static var FRONT_ANTI_ROLL_RATE := 8000.0
# was a const -> read from the car's config (suspension.rear_anti_roll_rate,
# required); the certified value stays here as the fallback default.
static var REAR_ANTI_ROLL_RATE := 5000.0

## Suspension travel either way from the static position [m]: 7 cm of bump and
## 7 cm of droop before the stops.
# was a const -> read from the car's config (suspension.travel, required); the
# certified value stays here as the fallback default.
static var SUSPENSION_TRAVEL := 0.07

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
# was a const -> read from the car's config (suspension.bump_stop_rate,
# optional); the certified value here is the fallback default a config without
# it gets.
static var BUMP_STOP_RATE := 3.0
# was a const -> read from the car's config (suspension.bump_stop_progression,
# optional); the certified value here is the fallback default a config without
# it gets.
static var BUMP_STOP_PROGRESSION := 0.02

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
# was a const -> read from the car's config (suspension.ground_clearance,
# required); the certified value stays here as the fallback default.
static var GROUND_CLEARANCE := 0.12

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
# was a const -> derived, never read: worked out again from the config's
# numbers when a car reads them (_derive_from_config, the same sum as here).
static var WHEEL_CONTACT_POINTS: Array[Vector3] = [
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
# was a const -> derived, never read: worked out again from the config's
# numbers when a car reads them (_derive_from_config, the same sum as here).
static var WHEEL_ARMS_AHEAD: Array[float] = [
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
# was a const -> read from the car's config (steering.max_steer_lock,
# required); the certified value stays here as the fallback default.
static var MAX_STEER_LOCK := 0.48

## The driver's steering wheel turns this far each way from centre [degrees]:
## 900 degrees lock to lock, two and a half turns, a road car's rack.
# was a const -> read from the car's config (steering.wheel_lock_deg,
# required); the certified value stays here as the fallback default.
static var STEERING_WHEEL_LOCK_DEG := 450.0

## How fast the driver's hands turn the steering wheel [degrees per second],
## towards where the steer input asks for it and back to centre on release:
## 1300 is a quick pair of hands (900 degrees lock to lock in 0.69 s, centre to
## lock in 0.35 s), about what a driver manages catching a slide. The keys are
## on / off, the hands are not: a tap is a few degrees of wheel, a held key
## winds lock on at this pace, and countersteer is wound on the same way: a
## slide is caught by steering against it early and in proportion, as far as
## the hands get in the time, not by flicking to opposite lock. The stability
## assist (see Slides) is what it always was and keeps that catchable.
## The test driver's hands: every driver brings a pair (steering_hand_speed in
## DRIVER_PROFILES).
# was STEER_RESPONSE 5.0 [1/s], the steer input easing to the key in 0.2 s
# centre to lock (a wheel spun at 2250 degrees per second, had there been one)
# -> the wheel is a state (steering_wheel_deg) turned at a hand's speed: 0.35 s
# centre to lock, 1.7 times as long.
# was a const -> read from the car's config (steering.hand_speed, required);
# the certified value stays here as the fallback default.
static var STEERING_HAND_SPEED := 1300.0

## Steering ratio: degrees of steering wheel per degree of front wheel. Follows
## from the two ends of the rack, 450 degrees of steering wheel for
## MAX_STEER_LOCK (27.5 degrees) at the front wheels: 16.4 to 1, a road car's
## (the 986's rack is 16.9 to 1). Front wheel angle = steering wheel angle /
## this, at any speed, however sideways the car is.
# was a const -> derived, never read: worked out again from the config's
# numbers when a car reads them (_derive_from_config, the same sum as here).
static var STEERING_RATIO := STEERING_WHEEL_LOCK_DEG / (MAX_STEER_LOCK * 180.0 / PI)

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
## Lower = wilder slides that spin more easily, higher = tamer. The driver can
## switch the whole assist off (sc_on, the SC key); the low-speed blend further
## down is numerics, not an aid, and has no switch.
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

# The lever is a lever: it bites the tick it is pulled and it is out the tick
# it is let go (_handbrake_amount). What outlasts it is the shoes still on the
# rear brakes as they come off - HANDBRAKE_RELEASE_TORQUE, dying away at
# REAR_LOCK_RECOVERY_RATE - and the rear tyres, which were sliding on
# TYRE_SLIDE_GRIP and take that same moment to find their rolling hold again.
# The driver can end it early: a brake torque is something the engine can pull
# against, so throttle into the release spins the rears up out of the lock (see
# _clutch_target, which lets the clutch in for exactly that).

## What the handbrake still presses the rear brakes with while it lets go [Nm],
## at _rear_lock_recovery of it. Well over the ~2550 Nm the road puts through a
## locked rear tyre on dry asphalt, so with nothing asked for the rears stay
## locked under it and the flick of a tap carries as it always has; 1st gear
## wide open is ~3700 Nm at the axle and pulls them out of it once it has
## decayed a little (measured: the rears outrun the road 11 ticks after the
## release), 2nd ~1900 Nm further down the decay, 3rd not at all. Held, it is
## applied under a lock that is already absolute (see _handbrake_amount) and
## changes nothing.
# 4500 and not 3000, which was the first figure tried: the number is what the
# tap's slide is worth, and 3000 let a little too much of it go. Over the smoke
# test's 0.2 s flick at 60 km/h, nose off the travel and rotation: 0.16 rad /
# 0.79 rad before this change, 0.14 / 0.54 at 4500, 0.13 / 0.42 at 3000 - and
# at 3000 the flick with the stability assist off came to exactly 2.00 times
# the one with it, where the smoke test wants more than twice (0.38 against
# 0.14 at 4500, 0.46 against 0.16 before). The 0.67 s pull is 1.90 rad and at
# rest 5.03 s after the release, against 1.90 and 5.07 before. Firmer still
# only holds the rears on past their use: see REAR_LOCK_RECOVERY_RATE for what
# a longer hold costs the same pull.
# was a const -> read from the car's config (handbrake.release_torque,
# required); the certified value stays here as the fallback default.
static var HANDBRAKE_RELEASE_TORQUE := 4500.0

## How fast that hold dies away once the key is up [1/s], and with it the slide
## grip of a tyre that was locked: 3.0 = gone 0.33 s after the release, so the
## tail catches smoothly instead of snapping straight. The lever itself bites
## instantly, and is out instantly.
# was HANDBRAKE_RECOVERY_RATE 2.5 (0.4 s), and it did a different job: it eased
# _handbrake_amount out, and _handbrake_amount lerped the rear wheel speed to 0
# and held the clutch open. Nothing the driver did could get through it - for
# 0.4 s after the key was up the rears were dragged back towards standstill
# whatever the engine did, and the clutch was open, so the engine was not
# trying. The user, from the driving seat (2026-09-21): "when i handbrake, just
# for a moment - only touching space for a fraction of a second - i feel like
# the handbrake still stays on... if there's a delay between when i released
# and hit the gas, i can't stabilise the car." Now the lever is out on the tick
# the key is, what is left is a brake torque like any other, and the throttle
# is let through to pull against it: the rears outrun the road 11 ticks
# (0.18 s) after a release with the gas down, where before they could not do it
# at any point. The window itself is only shortened, not removed, because it is
# what carries the flick: with the lock gone on the release tick a 0.2 s tap at
# 60 km/h swings the nose 0.05 rad off the travel instead of 0.16 and turns the
# car 0.19 rad instead of 0.79 - a tap would have stopped sliding the car at
# all. 0.33 s keeps 0.14 / 0.54 of that. The two neighbours were tried and
# dropped: 0.25 s leaves the tap 0.11 / 0.29 and the stability assist's flick
# comparison under the twice-as-deep the smoke test asks of it (1.45 times);
# the old 0.4 s holds the rears too long at either torque for the smoke test's
# 0.67 s pull to be at rest inside its 6 s (6.18 s at 3000 Nm, 6.62 at 4500,
# against 5.07 s before this change).
# was a const -> read from the car's config
# (handbrake.rear_lock_recovery_rate, required); the certified value stays
# here as the fallback default.
static var REAR_LOCK_RECOVERY_RATE := 3.0

# --- Driver: feet and hands ----------------------------------------------------

# The car does not read keys, it has a driver: somebody asks for throttle,
# brake and steering (the keys, or whoever calls set_driver_input - an AI
# later), and the driver's feet and hands bring the pedals and the steering
# wheel there at a human pace. The keys are on / off, the feet are not: a held
# key is a foot going down to the floor, a tap is a dab at the pedal that never
# gets there. What the drivetrain is given is where the pedals ARE
# (throttle_pedal, brake_pedal), never what was asked for.
#
# One right foot works both pedals, as on the road: asking for one pedal alone
# takes the foot off the other at once, so going from the throttle to the brake
# costs the brake's attack and nothing on top; the release rates are for letting
# a pedal go with nothing else asked for. Asking for both presses both, and
# they cancel out as the keys always have; a profile's brake_attack should be
# no slower than its throttle_attack, or both asked for at once is a blip of
# throttle before they do.
#
# The handbrake is not part of this: a lever pulled with the hand, it bites
# instantly as it always has, and lets go as instantly (what stays behind is on
# the rear brakes, see HANDBRAKE_RELEASE_TORQUE, not on the lever). The
# flick of a handbrake turn lives on that bite.

## Driver profiles: how fast a driver's feet and hands move, as plain data.
##   throttle_attack     throttle pedal going down [1/s]: travel per second, 1 =
##                       the whole pedal, so 10 is 0.1 s from closed to the
##                       floor and a 3-tick tap is half throttle
##   throttle_release    throttle pedal coming back up [1/s]
##   brake_attack        brake pedal going down [1/s]
##   brake_release       brake pedal coming back up [1/s]
##   steering_hand_speed steering wheel [degrees per second], on and back to
##                       centre (see STEERING_HAND_SPEED)
## Linear, as the hands are: a rate, no easing, a pedal is fully down exactly
## 1 / attack seconds after the key. "test_driver" is who drives unless somebody
## else is put in the seat (set_driver_profile): the driver the handling tests
## were certified with, as quick as feet get. The throttle is rolled on in a
## tenth of a second, the brake is stamped on in half that, the brake is let go
## as fast as the throttle is pressed, and a lift is a lift: the foot is off the
## throttle in two ticks. "chauffeur" is the same car driven with a passenger's
## coffee in mind: feet several times slower, let go a little slower than they
## are pressed, hands half as fast. "comfort_driver" and "eco_driver" are who
## the gearbox mode key seats with those two programs (MODE_DRIVERS), and
## "test_driver" with sport: nobody is racing in comfort or eco, and the feet
## are part of the program. A key is on / off, so how far down the pedal gets
## is how long the key was held times the attack: at the test driver's 10 a
## 6-tick tap is the floor, and the only throttle between none and all is a
## flutter of taps between none and all (6 ticks on, 6 off: 0 .. 1.00 of the
## pedal). At the comfort driver's 4.5 the same tap is 0.45 of the pedal, at the
## eco driver's 3.5 it is 0.35, and the pedal comes back up at the pace it went
## down: an even beat of taps keeps it where it is (from nothing, around a
## quarter), a longer press takes it further down and the beat holds it there,
## a longer gap lets it up. The brake is a little quicker than the throttle in
## both, as it has to be (see above), the hands between the chauffeur's and the
## test driver's.
# was one driver whatever the program -> one each - the user's report
# (2026-09-21): "in comfort the pedals should be less snappy, so i can keep
# acceleration 50% or 25% - currently i'm tapping, but it's impossible to keep
# the same RPMs".
# The test driver's figures are as slow as the certified car allows, measured
# against the checks that pin it:
# throttle_attack was 7.5 (0.13 s) -> 10.0 - the camera test's one-second
# launch on full lock has to gain 3.0 m/s: 3.19 with a switch for a pedal, 2.98
# at 7.5, 3.00 at 9, 3.03 at 10.
# throttle_release was 5.0 (0.2 s, a lift that eases off) -> 30.0 - the J-turn
# lifts with the clutch still slipping in reverse (the rears spinning at 41
# km/h), and a throttle that takes three ticks or more to close keeps the clutch
# in long enough to lock: the engine's revs are pushed into the car (11.5 ->
# 12.2 m/s after the lift), the flick is made on engine braking, the nose comes
# round to -190 degrees for the certified -186 and the scripted driver misses
# its goal (FAIL at 5, 10 and 20). Shut within two ticks the clutch opens as it
# did for the key: -186.0 degrees, 7.68 s for the certified 7.70, at 30, 40 and
# 50 alike.
# brake_attack was 10.0 (0.1 s) -> 20.0 - smoke's 20 ticks on the brake have to
# take off 0.85 of what all four tyres at the limit would: 2.74 m/s of the 3.1
# with a switch, 2.5 at 10, short at 16, there from 17 up.
# brake_release was 6.0 -> 10.0 - nothing pins it: as fast as the throttle
# goes on, in keeping with the rest of this driver.
# With these the five certified runs read 28.77 / 15.83 / 18.28 / 8.72 / 7.68 s
# against 28.75 / 15.83 / 18.23 / 8.67 / 7.70 on keys that were switches.
# was a const -> read from the car's config (driver_profiles, required); the
# certified value stays here as the fallback default.
static var DRIVER_PROFILES := {
	"test_driver": {
		"throttle_attack": 10.0,
		"throttle_release": 30.0,
		"brake_attack": 20.0,
		"brake_release": 10.0,
		"steering_hand_speed": STEERING_HAND_SPEED,
	},
	"chauffeur": {
		"throttle_attack": 3.0,
		"throttle_release": 2.5,
		"brake_attack": 4.0,
		"brake_release": 3.0,
		"steering_hand_speed": 650.0,
	},
	"comfort_driver": {
		"throttle_attack": 4.5,
		"throttle_release": 4.5,
		"brake_attack": 5.0,
		"brake_release": 4.0,
		"steering_hand_speed": 850.0,
	},
	"eco_driver": {
		"throttle_attack": 3.5,
		"throttle_release": 3.5,
		"brake_attack": 4.5,
		"brake_release": 3.5,
		"steering_hand_speed": 850.0,
	},
}

## Who the gearbox mode key puts in the seat with each of the automatic's
## programs: GearboxMode -> a name in DRIVER_PROFILES. Only the key does it (see
## _physics_process); whoever calls set_driver_profile after that has the seat
## until the key is pressed again.
# was a const -> built again when a car reads its config (mode_drivers,
# required: its program names are put onto GearboxMode here, an enum's values
# being code and not car data); the certified seating is the fallback default.
static var MODE_DRIVERS := {
	GearboxMode.SPORT: "test_driver",
	GearboxMode.COMFORT: "comfort_driver",
	GearboxMode.ECO: "eco_driver",
}

# --- Visual only (no effect on handling) -------------------------------------

## The angle after which a drawn wheel looks the same again [rad]: half a turn,
## wheel.tscn's one bar across the rim. A wheel is drawn turning by its real
## step each physics tick, folded into half of this either way (a quarter
## turn): the same picture on every tick, reached the short way in between
## (the renderer interpolates between ticks). What shows is what a wheel
## filmed at 60 frames a second shows, the wagon-wheel effect: its real speed
## up to a quarter turn a tick (94 rad/s, ~115 km/h), a flicker around there,
## then the wheel seeming to turn BACKWARDS, slower the faster the car goes,
## to a standstill at half a turn a tick (~230 km/h).
## was MAX_WHEEL_SPIN 100.0 [rad/s], a cap on the drawn spin "kept under half a
## turn per physics tick so the wheels never appear to spin backwards at high
## speed" -> removed for the fold. The user's report from the driving seat
## (2026-09-21, in the morning) was the opposite of what the cap was for: at
## speed the wheels only shimmered and never showed the backward rotation a
## fast wheel has. The cap held them at 95 degrees a tick from 122 km/h up, and
## with a bar that repeats every 180 that is the one step that reads neither
## forwards nor backwards. (A lower cap, 20 rad/s, was weighed: calm, but one
## and the same forward spin from 24 km/h up, and spinning or locking wheels
## would no longer show against the road.)
const WHEEL_DRAW_PERIOD := PI

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
# was a const -> derived, never read: worked out again from the config's
# numbers when a car reads them (_derive_from_config, the same sum as here).
static var MAX_WHEEL_VISUAL_TRAVEL := SUSPENSION_TRAVEL + 0.02

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
## FORWARD_ENGAGE_GRACE. In manual mode the shift keys reach it as well, as the
## position under neutral (see shift_down): reverse selected with the lever, the
## keys swapped as above.
var reverse_engaged := false

## True = the gearbox shifts by itself. The shift keys switch to manual.
var automatic := true

## Which of its three programs the automatic shifts by (see GearboxMode). A
## switch on the dashboard like tcs_on, and like it left alone by a reset. The
## gearbox mode key seats a driver along with it (MODE_DRIVERS); setting this
## does not.
var gearbox_mode := GearboxMode.SPORT

## The driver aids, on unless switched off (the TCS and ABS keys): traction
## control (see DRIVE_SLIP_RATIO for what the car does without) and anti-lock
## brakes (ABS_SLIP_RATIO). Switches on the dashboard, not the car's state: a
## reset puts the car back, it does not reach over and flip them, so whoever
## switched an aid off keeps driving without it.
var tcs_on := true
var abs_on := true

## The view the driver is looking through, by its index in ChaseCamera.Mode
## (0 chase, 1 cockpit, 2 front, 3 overhead, 4 wheel; the held-only rear view is
## never left in). A dashboard setting like the switches above - kept with them
## from one session to the next and left alone by a reset - and it lives on the
## car because the car is what the store knows: the camera reads it when it
## comes up and writes the cycle key's new view back here (ChaseCamera). A car
## that has not been driven starts in the cockpit, inside the car.
var camera_view := OdometerStore.CAMERA_VIEW_COCKPIT

## The stability assist (see SLIDE_YAW_DAMPING), on unless switched off (the SC
## key): a dashboard switch like the two above, and like them left alone by a
## reset. Off, _slide_yaw_damping is 0 on every branch and the assist's yaw
## moment with it: the car rotates on its tyres alone, a slide hangs on for as
## long as they let it and a spin is the driver's to catch. The low-speed blend
## (LOW_SPEED_BLEND_END) is not part of it and stays on: that is numerics, what
## keeps the tyre model meaningful near a standstill, not a driver aid.
var sc_on := true

## True while the engine runs. False once it has been dragged or has run down
## under STALL_RPM: nothing burns, the tach falls to 0, the throttle does
## nothing, until something turns it past ENGINE_CATCH_RPM again (the starter
## key). A reset starts it: reset_to puts a car there that is ready to drive.
var engine_running := true

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

## Fuel left in the tank [L], 0 .. FUEL_TANK_CAPACITY_L (kept inside that, NaN
## is an empty tank). Burnt by the engine every tick (_run_engine_outputs),
## filled by reset_to. Kept from one session to the next where the odometer is
## (_load_stored_fuel): the car starts with what it was left with, the full
## tank below is a new car's - and every car's in the headless test suite.
var fuel_l := FUEL_TANK_CAPACITY_L:
	set(value):
		fuel_l = 0.0 if is_nan(value) else clampf(value, 0.0, FUEL_TANK_CAPACITY_L)

## Share of the new battery's capacity it has lost for good, 0 ..
## BATTERY_WEAR_LIMIT (kept inside that, NaN is none). Grown by deep
## discharges (_advance_battery), put back to 0 by reset_to. Kept from one
## session to the next with the charge (_load_stored_battery). Set it before
## the charge: the charge is held under what the wear leaves.
var battery_wear := 0.0:
	set(value):
		battery_wear = 0.0 if is_nan(value) else clampf(value, 0.0, BATTERY_WEAR_LIMIT)
		battery_charge = battery_charge

## The energy in the battery as a share of what it held when new, 0 .. 1 less
## battery_wear (kept inside that, NaN is flat): times BATTERY_CAPACITY_J it is
## joules. Drawn on by the starter and the key-on load, charged by the
## alternator (_advance_battery), full again on reset_to. Kept from one session
## to the next where the odometer is: the car starts with what it was left
## with, the full one below is a new car's - and every car's in the headless
## test suite. What the HUD's battery bar shows: a worn battery never fills it.
var battery_charge := 1.0:
	set(value):
		battery_charge = 0.0 if is_nan(value) else clampf(value, 0.0, 1.0 - battery_wear)

## Mass of that fuel [kg]: fuel_l x FUEL_DENSITY, brought up to date at the
## start of every tick, so one tick works with one mass throughout.
var fuel_mass := FUEL_TANK_CAPACITY_L * FUEL_DENSITY

## Mass of what the car carries on top of itself and its fuel [kg]: packages,
## passengers, ballast. Payload is mass and nothing else: it rides at the
## centre of mass and is in total_mass() from the next tick on. Never negative,
## NaN is nothing loaded; reset_to unloads the car.
var payload_mass := 0.0:
	set(value):
		payload_mass = 0.0 if is_nan(value) else maxf(value, 0.0)

## Combustion events since the car was last reset (a count, fractional while a
## cylinder is on its way): FIRINGS_PER_REVOLUTION for every turn of the
## crankshaft while the engine fires, none while the limiter or a dry tank
## holds the fuel back. Pure data, for whatever draws or sounds the exhaust.
var exhaust_events := 0.0

## How hard the exhaust blows right now, 0..1: the throttle the engine really
## has (the idle controller's share included) times EXHAUST_FLOW_AT_REST plus
## the rest by engine speed, followed at EXHAUST_FLOW_RATE. ~0.04 idling, 1 flat
## out at the limiter. Pure data, as exhaust_events.
var exhaust_flow := 0.0

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

## Who is driving: one of DRIVER_PROFILES, or a dictionary with the same keys.
## Set through set_driver_profile, which fills in what is missing.
var driver_profile: Dictionary = DRIVER_PROFILES["test_driver"]

## What the drivetrain is given this tick, 0..1 each: the throttle the engine
## gets and the share of BRAKE_DECEL the brakes are asked for. The driver's
## feet (see Driver: feet and hands) after the car has had its say: the lift
## and the blip of a gear change are in the throttle, the foot easing off into
## MAX_REVERSE_SPEED too, and a throttle foot pressed while the car still rolls
## against the selected direction shows up as brake, which is what it does.
## What the HUD's pedal bars show.
var throttle_pedal := 0.0
var brake_pedal := 0.0

## Where the driver's left foot has the clutch pedal, 0 (up) .. 1 (on the
## floor): moved at CLUTCH_PEDAL_SPEED while the clutch key is held, and back.
## Stays up in automatic mode.
var clutch_pedal := 0.0

## Where the driver's feet have the two pedals, 0..1: wound towards what is
## asked for at the driver_profile's rates. Pedals, not keys: in reverse the
## brake key works the throttle pedal and the accelerate key the brake.
var _throttle_foot := 0.0
var _brake_foot := 0.0

## True while set_driver_input is driving: the keys are not read for throttle,
## brake, steering and handbrake, the _driver_* values are what is asked for,
## held until the next call or clear_driver_input.
var _driver_input_active := false
var _driver_accelerate := 0.0
var _driver_brake := 0.0
var _driver_steer := 0.0
var _driver_handbrake := false

## How far the handbrake lever is on, 0..1: 1 the tick it is pulled, 0 the tick
## it is let go. It locks the rear wheels and nothing rides on it afterwards.
var _handbrake_amount := 0.0

## How much of its hold on the rear wheels the handbrake still has, 0..1: 1
## while the lever is held, easing to 0 at REAR_LOCK_RECOVERY_RATE once it is
## let go. It is HANDBRAKE_RELEASE_TORQUE's share on the rear brakes, the slide
## grip of a tyre that was locked, and what the car's own clutch keeps out of
## the way of - all of them the tyres' business, not the lever's: the lever is
## out with the key.
var _rear_lock_recovery := 0.0

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

## True from the clutch pedal being touched until the clutch is home or open
## again with the foot off it: the clutch is the driver's, the car's feathering
## stays out of it (see CLUTCH_PEDAL_SPEED).
var _driver_has_clutch := false

## TCS off: true once the revs of a launch have flared to the floor and the
## clutch has been let in for good, until it is home or open again (see
## DRIVE_SLIP_RATIO).
var _clutch_dumped := false

## True while the starter key is held, and what is left of the crank cycle a
## fresh press of it started [s] (see STARTER_CYCLE_TIME; 0 = none running,
## and none ever on a running engine: a catch or a reset ends it).
var _starter_held := false
var _crank_timer := 0.0

## True from the tick the battery's charge went under
## BATTERY_DEEP_DISCHARGE_CHARGE until it is back over it: the discharge has
## been paid for (BATTERY_DEEP_DISCHARGE_WEAR), the next one is the next time
## it goes under. Not kept in the file: set from the charge that is loaded.
var _battery_deep := false

## True while the car creeps (see CREEP_CLUTCH_ENGAGEMENT); on the way there,
## whether the brake has held the car at a standstill (what arms the creep) and
## how long it has stood with nothing asked of it since [s] (CREEP_DWELL).
var _creeping := false
var _creep_armed := false
var _creep_rest_time := 0.0

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

## This car's name in the odometer file (see OdometerStore): one entry per car,
## so the garage's cars can each keep their own metres and their own fuel.
# was a const -> read from the car's config (identity.car_id, required); the
# certified value stays here as the fallback default.
static var CAR_ID := "boxster_986"

## How often the odometer is written to its file while the car is driven [s of
## physics time], the fuel level with it; and once more when the car leaves the
## scene tree.
const ODOMETER_SAVE_INTERVAL := 45.0

## The odometer [m]: every metre this car has moved over the ground, whichever
## way - forwards, backwards or sideways in a slide, it is the body's own way
## from tick to tick, not the wheels' turning. Never reset: reset_to puts the
## car somewhere and the jump there is not driven (_odometer_from), the metres
## stay. Bookkeeping only, nothing in the car reads it. Kept from one session
## to the next by OdometerStore where that is switched on (the running game;
## not the headless test suite, which writes nothing).
var odometer_m := 0.0

## Where the car was when the odometer last counted; reset_to moves it along.
var _odometer_from := Vector3.ZERO

## Whether the odometer - and the fuel level with it - is kept in its file in
## this run (OdometerStore.enabled, asked once), and the physics time since
## they were last written there [s].
var _odometer_kept := false
var _since_odometer_save := 0.0

## How many times reset_to has put the car somewhere. Bookkeeping for what
## watches the car from outside (the tyre marks clear when it goes up); nothing
## in the car reads it.
var reset_counter := 0

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
	_read_config()
	# was asked further down, for the odometer alone -> before the car is stood
	# on its springs: the fuel it starts with is weight (_settle_suspension
	# reads total_mass()). Once, here; never in reset_to, which fills the tank.
	_odometer_kept = OdometerStore.enabled()
	if _odometer_kept:
		_load_stored_fuel()
		# After _read_config, which seats the test driver: the stored program
		# seats its own driver over it. Before anything reads a switch, and
		# before the camera comes up (it is this car's sibling in main.tscn and
		# its _ready runs after ours) to pick up camera_view.
		_load_stored_driver()
		_load_stored_battery()
	_spawn_transform = global_transform
	# The body floats on its springs over the floor; nothing may pull it onto
	# it (CharacterBody3D snaps to a floor within 0.1 m by default).
	floor_snap_length = 0.0
	_settle_suspension(global_position.y)
	_odometer_from = global_position
	if _odometer_kept:
		odometer_m = OdometerStore.load_odometer(CAR_ID)


func _exit_tree() -> void:
	if _odometer_kept:
		OdometerStore.save_car(CAR_ID, odometer_m, fuel_l, OdometerStore.PATH, driver_settings(), battery_settings())


## The tank as this car was left with it the last time (OdometerStore, from
## `path`): fuel_l [L] and its mass with it - the setter of fuel_l keeps the
## litres inside the tank and no more, fuel_mass [kg] is a number of its own
## until the next tick. A car the file does not know starts on the full tank
## the config gave it; a level in there that is none of this tank's is an error
## and a full tank. Nothing refuels a car but reset_to: one left at 8 % starts
## at 8 %.
func _load_stored_fuel(path := OdometerStore.PATH) -> void:
	var stored := OdometerStore.load_fuel(CAR_ID, FUEL_TANK_CAPACITY_L, path)
	if stored.problem != "":
		push_error(stored.problem)
	fuel_l = stored.fuel_l
	fuel_mass = fuel_l * FUEL_DENSITY


## The dashboard as this car was left with it (OdometerStore, from `path`): the
## three aid switches, the gearbox program, automatic or manual, and the view
## the driver was looking through. The switches belong to the car, not to
## whoever drove it last, so the next driver gets in to what the last one left.
## A car the file does not know keeps the defaults it was created with (every
## aid on, sport, automatic, the cockpit view); a setting in there that is none
## of its own is an error and that one default, the others still load. The
## program seats its own driver, as the gearbox mode key does (MODE_DRIVERS).
func _load_stored_driver(path := OdometerStore.PATH) -> void:
	var stored := OdometerStore.load_driver(CAR_ID, path)
	for problem: String in stored.problems:
		push_error(problem)
	tcs_on = stored.tcs_on
	abs_on = stored.abs_on
	sc_on = stored.sc_on
	automatic = stored.automatic
	gearbox_mode = OdometerStore.GEARBOX_MODES.find(stored.gearbox_mode) as GearboxMode
	set_driver_profile(DRIVER_PROFILES[MODE_DRIVERS[gearbox_mode]])
	camera_view = stored.camera_view


## The dashboard as it stands, for the store: a car's whole "driver" object
## (OdometerStore.DRIVER_DEFAULTS has the same six fields). The program goes by
## name, the view by its index.
func driver_settings() -> Dictionary:
	return {
		"tcs_on": tcs_on,
		"abs_on": abs_on,
		"sc_on": sc_on,
		"gearbox_mode": OdometerStore.GEARBOX_MODES[gearbox_mode],
		"automatic": automatic,
		"camera_view": camera_view,
	}


## The battery as this car was left with it (OdometerStore, from `path`): how
## full (battery_charge) and how worn (battery_wear), the wear first so the
## charge is held under what it leaves. A car the file does not know starts on
## the full, healthy battery it was created with; a number in there that is no
## share of a battery is an error and that one default, the other still loads.
## Nothing charges a car's battery but the alternator and reset_to: one left
## flat starts flat, and its starter turns nothing.
func _load_stored_battery(path := OdometerStore.PATH) -> void:
	var stored := OdometerStore.load_battery(CAR_ID, path)
	for problem: String in stored.problems:
		push_error(problem)
	battery_wear = stored.capacity_wear
	battery_charge = stored.charge
	_battery_deep = battery_charge < BATTERY_DEEP_DISCHARGE_CHARGE


## The battery as it stands, for the store: a car's whole "battery" object
## (OdometerStore.BATTERY_DEFAULTS has the same two fields).
func battery_settings() -> Dictionary:
	return {
		"charge": battery_charge,
		"capacity_wear": battery_wear,
	}


## Makes this car the one its config describes (CONFIG_PATH), before anything
## else in _ready looks at a number: the file is read and checked
## (CarConfigValidation), its primary numbers go into the static vars of the
## tuning section, what follows from them is worked out again, and the state
## this car was created with from the fallback defaults is set again from what
## was read. A config that is not there, is not JSON or does not pass is an
## error and an assert, and none of it is used: a bad config never becomes
## physics, the car stands on the certified defaults it was written with.
func _read_config() -> void:
	var config: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
	var errors := CarConfigValidation.validate(config, CONFIG_PATH)
	if not errors.is_empty():
		push_error("car config refused, none of it is used:\n  " + "\n  ".join(errors))
		assert(false, "car config refused: " + CONFIG_PATH)
		return
	_apply_config(config)
	_derive_from_config()
	engine_omega = IDLE_RPM * TAU / 60.0
	fuel_l = FUEL_TANK_CAPACITY_L
	fuel_mass = FUEL_TANK_CAPACITY_L * FUEL_DENSITY
	battery_wear = 0.0
	battery_charge = 1.0
	front_load_fraction = 1.0 - REAR_WEIGHT_FRACTION
	rear_load_fraction = REAR_WEIGHT_FRACTION
	driver_profile = DRIVER_PROFILES["test_driver"]


## A checked config's primary numbers into the static vars, section by section
## (the schema: configs/README.md). A key the schema marks optional, left out,
## leaves the static var what it is: the fallback default it was declared with.
static func _apply_config(config: Dictionary) -> void:
	CAR_ID = config.identity.car_id

	var mass: Dictionary = config.mass
	KERB_MASS = mass.kerb_mass
	REAR_WEIGHT_FRACTION = mass.rear_weight_fraction
	CG_HEIGHT = mass.cg_height
	AXLE_DISTANCE = mass.axle_distance
	YAW_GYRATION_RADIUS = mass.yaw_gyration_radius

	var engine: Dictionary = config.engine
	TORQUE_CURVE = []
	for anchor: Array in engine.torque_curve:
		TORQUE_CURVE.append(Vector2(anchor[0], anchor[1]))
	IDLE_RPM = engine.idle_rpm
	STALL_RPM = engine.get("stall_rpm", STALL_RPM)
	CRANKING_TORQUE = engine.get("cranking_torque", CRANKING_TORQUE)
	STARTER_FREE_RPM = engine.get("starter_free_rpm", STARTER_FREE_RPM)
	STARTER_CYCLE_TIME = engine.get("starter_cycle_time", STARTER_CYCLE_TIME)
	ENGINE_CATCH_RPM = engine.get("engine_catch_rpm", ENGINE_CATCH_RPM)
	REDLINE_RPM = engine.redline_rpm
	LIMITER_RESUME_RPM = engine.limiter_resume_rpm
	ENGINE_INERTIA = engine.engine_inertia
	ENGINE_FRICTION_TORQUE = engine.friction_torque
	ENGINE_FRICTION_TORQUE_PER_RPM = engine.friction_torque_per_rpm
	FIRINGS_PER_REVOLUTION = engine.get("firings_per_revolution", FIRINGS_PER_REVOLUTION)

	var idle: Dictionary = config.get("idle", {})
	IDLE_CONTROL_GAIN = idle.get("control_gain", IDLE_CONTROL_GAIN)
	IDLE_CONTROL_MAX_THROTTLE = idle.get("control_max_throttle", IDLE_CONTROL_MAX_THROTTLE)

	var fuel: Dictionary = config.fuel
	FUEL_TANK_CAPACITY_L = fuel.tank_capacity_l
	FUEL_BURN_EFFICIENCY = fuel.burn_efficiency
	FUEL_LHV = fuel.lhv
	FUEL_DENSITY = fuel.density

	var exhaust: Dictionary = config.get("exhaust", {})
	EXHAUST_FLOW_AT_REST = exhaust.get("flow_at_rest", EXHAUST_FLOW_AT_REST)
	EXHAUST_FLOW_RATE = exhaust.get("flow_rate", EXHAUST_FLOW_RATE)

	var battery: Dictionary = config.get("battery", {})
	BATTERY_CAPACITY_AH = battery.get("capacity_ah", BATTERY_CAPACITY_AH)
	STARTER_POWER = battery.get("starter_power", STARTER_POWER)
	BATTERY_KEY_ON_LOAD = battery.get("key_on_load", BATTERY_KEY_ON_LOAD)
	BATTERY_RUNNING_LOAD = battery.get("running_load", BATTERY_RUNNING_LOAD)
	ALTERNATOR_POWER = battery.get("alternator_power", ALTERNATOR_POWER)
	ALTERNATOR_CUT_IN_RPM = battery.get("alternator_cut_in_rpm", ALTERNATOR_CUT_IN_RPM)
	ALTERNATOR_RATED_RPM = battery.get("alternator_rated_rpm", ALTERNATOR_RATED_RPM)
	BATTERY_CHARGE_EFFICIENCY = battery.get("charge_efficiency", BATTERY_CHARGE_EFFICIENCY)
	BATTERY_TAPER_CHARGE = battery.get("taper_charge", BATTERY_TAPER_CHARGE)
	BATTERY_DEEP_DISCHARGE_CHARGE = battery.get("deep_discharge_charge", BATTERY_DEEP_DISCHARGE_CHARGE)
	BATTERY_DEEP_DISCHARGE_WEAR = battery.get("deep_discharge_wear", BATTERY_DEEP_DISCHARGE_WEAR)
	BATTERY_FLAT_WEAR_RATE = battery.get("flat_wear_rate", BATTERY_FLAT_WEAR_RATE)

	var gearbox: Dictionary = config.gearbox
	GEAR_RATIOS = []
	GEAR_RATIOS.assign(gearbox.ratios)
	FINAL_DRIVE = gearbox.final_drive
	REVERSE_RATIO = gearbox.reverse_ratio
	DRIVETRAIN_EFFICIENCY = gearbox.drivetrain_efficiency
	CLUTCH_TORQUE_MAX = gearbox.clutch_torque_max
	CLUTCH_ENGAGE_TIME = gearbox.clutch_engage_time
	CLUTCH_SHIFT_ENGAGE_TIME = gearbox.clutch_shift_engage_time

	var launch: Dictionary = config.launch
	LAUNCH_RPM = launch.rpm
	LAUNCH_CLUTCH_SHARE = launch.get("clutch_share", LAUNCH_CLUTCH_SHARE)
	LAUNCH_BITE_BAND = launch.get("bite_band", LAUNCH_BITE_BAND)

	var creep: Dictionary = config.get("creep", {})
	CREEP_CLUTCH_ENGAGEMENT = creep.get("clutch_engagement", CREEP_CLUTCH_ENGAGEMENT)
	CREEP_FREE_SPEED = creep.get("free_speed", CREEP_FREE_SPEED)
	CREEP_ENGAGE_SPEED = creep.get("engage_speed", CREEP_ENGAGE_SPEED)
	CREEP_DWELL = creep.get("dwell", CREEP_DWELL)
	CREEP_MAX_SPEED = creep.get("max_speed", CREEP_MAX_SPEED)

	var brakes: Dictionary = config.brakes
	BRAKE_BIAS_FRONT = brakes.bias_front
	BRAKE_DECEL_G = brakes.decel_g
	COAST_DECEL = brakes.get("coast_decel", COAST_DECEL)

	var tyres: Dictionary = config.tyres
	TYRE_MU = tyres.mu
	FRONT_TYRE_GRIP = tyres.front_grip
	REAR_TYRE_GRIP = tyres.rear_grip
	PEAK_SLIP_RATIO = tyres.peak_slip_ratio
	ABS_SLIP_RATIO = tyres.abs_slip_ratio
	DRIVE_SLIP_RATIO = tyres.drive_slip_ratio
	FRONT_PEAK_SLIP_ANGLE = tyres.front_peak_slip_angle
	REAR_PEAK_SLIP_ANGLE = tyres.rear_peak_slip_angle
	TYRE_SLIDE_GRIP = tyres.slide_grip
	REAR_TYRE_SLIDE_GRIP = tyres.rear_slide_grip
	TYRE_SLIDE_ONSET = tyres.slide_onset
	AXLE_INERTIA = tyres.axle_inertia
	MIN_COMBINED_GRIP = tyres.min_combined_grip
	LOAD_GRIP_EXPONENT = tyres.load_grip_exponent

	var suspension: Dictionary = config.suspension
	FRONT_RIDE_FREQUENCY = suspension.front_ride_frequency
	REAR_RIDE_FREQUENCY = suspension.rear_ride_frequency
	RIDE_DAMPING_RATIO = suspension.ride_damping_ratio
	FRONT_ANTI_ROLL_RATE = suspension.front_anti_roll_rate
	REAR_ANTI_ROLL_RATE = suspension.rear_anti_roll_rate
	SUSPENSION_TRAVEL = suspension.travel
	BUMP_STOP_RATE = suspension.get("bump_stop_rate", BUMP_STOP_RATE)
	BUMP_STOP_PROGRESSION = suspension.get("bump_stop_progression", BUMP_STOP_PROGRESSION)
	GROUND_CLEARANCE = suspension.ground_clearance

	var steering: Dictionary = config.steering
	MAX_STEER_LOCK = steering.max_steer_lock
	STEERING_WHEEL_LOCK_DEG = steering.wheel_lock_deg
	STEERING_HAND_SPEED = steering.hand_speed

	var aero: Dictionary = config.aero
	DRAG_COEFF = aero.drag_coeff
	FRONTAL_AREA = aero.frontal_area
	DOWNFORCE_COEFF = aero.downforce_coeff
	AERO_BALANCE_FRONT = aero.balance_front
	AIR_DENSITY = aero.get("air_density", AIR_DENSITY)

	var handbrake: Dictionary = config.handbrake
	HANDBRAKE_RELEASE_TORQUE = handbrake.release_torque
	REAR_LOCK_RECOVERY_RATE = handbrake.rear_lock_recovery_rate

	DRIVER_PROFILES = {}
	for profile_name: String in config.driver_profiles:
		DRIVER_PROFILES[profile_name] = config.driver_profiles[profile_name].duplicate()
	# The config names the automatic's programs in words ("sport"); which
	# GearboxMode that is, is this file's business.
	MODE_DRIVERS = {}
	for mode_name: String in config.mode_drivers:
		MODE_DRIVERS[GearboxMode[mode_name.to_upper()]] = config.mode_drivers[mode_name]


## Everything that follows from the primary numbers, worked out from what the
## static vars hold now: the same sums their declarations are written with
## (each documented there), run again so that none of them is left standing on
## the numbers of the fallback defaults.
static func _derive_from_config() -> void:
	BASE_MASS = KERB_MASS - FUEL_TANK_CAPACITY_L * FUEL_DENSITY
	BATTERY_CAPACITY_J = BATTERY_CAPACITY_AH * 3600.0 * BATTERY_NOMINAL_VOLTAGE
	CG_OFFSET = (REAR_WEIGHT_FRACTION - 0.5) * 2.0 * AXLE_DISTANCE
	BRAKE_DECEL = BRAKE_DECEL_G * TYRE_MU * 9.8
	FRONT_CORNER_MASS = KERB_MASS * (1.0 - REAR_WEIGHT_FRACTION) * 0.5
	REAR_CORNER_MASS = KERB_MASS * REAR_WEIGHT_FRACTION * 0.5
	FRONT_SPRING_RATE = FRONT_CORNER_MASS * (TAU * FRONT_RIDE_FREQUENCY) * (TAU * FRONT_RIDE_FREQUENCY)
	REAR_SPRING_RATE = REAR_CORNER_MASS * (TAU * REAR_RIDE_FREQUENCY) * (TAU * REAR_RIDE_FREQUENCY)
	FRONT_DAMPER_RATE = 2.0 * RIDE_DAMPING_RATIO * FRONT_CORNER_MASS * TAU * FRONT_RIDE_FREQUENCY
	REAR_DAMPER_RATE = 2.0 * RIDE_DAMPING_RATIO * REAR_CORNER_MASS * TAU * REAR_RIDE_FREQUENCY
	WHEEL_CONTACT_POINTS = [
		Vector3(-HALF_TRACK, 0.0, -AXLE_DISTANCE),
		Vector3(HALF_TRACK, 0.0, -AXLE_DISTANCE),
		Vector3(-HALF_TRACK, 0.0, AXLE_DISTANCE),
		Vector3(HALF_TRACK, 0.0, AXLE_DISTANCE),
	]
	WHEEL_ARMS_AHEAD = [
		AXLE_DISTANCE + CG_OFFSET, AXLE_DISTANCE + CG_OFFSET, CG_OFFSET - AXLE_DISTANCE, CG_OFFSET - AXLE_DISTANCE,
	]
	STEERING_RATIO = STEERING_WHEEL_LOCK_DEG / (MAX_STEER_LOCK * 180.0 / PI)
	MAX_WHEEL_VISUAL_TRAVEL = SUSPENSION_TRAVEL + 0.02


func _physics_process(delta: float) -> void:
	if Input.is_action_just_pressed("reset_car"):
		reset_to_spawn()
	if Input.is_action_just_pressed("shift_up"):
		shift_up()
	if Input.is_action_just_pressed("shift_down"):
		shift_down()
	if Input.is_action_just_pressed("toggle_gearbox"):
		automatic = not automatic
	if Input.is_action_just_pressed("gearbox_mode"):
		# was sport <-> comfort -> sport, comfort, eco and round again, and the
		# key seats the program's own driver with it (MODE_DRIVERS). Here and
		# nowhere else: gearbox_mode set from code, and a reset, leave whoever
		# is in the seat, and a driver seated by hand (set_driver_profile)
		# stays until the next press of this key.
		match gearbox_mode:
			GearboxMode.SPORT:
				gearbox_mode = GearboxMode.COMFORT
			GearboxMode.COMFORT:
				gearbox_mode = GearboxMode.ECO
			_:
				gearbox_mode = GearboxMode.SPORT
		set_driver_profile(DRIVER_PROFILES[MODE_DRIVERS[gearbox_mode]])
	if Input.is_action_just_pressed("tcs_toggle"):
		tcs_on = not tcs_on
	if Input.is_action_just_pressed("abs_toggle"):
		abs_on = not abs_on
	if Input.is_action_just_pressed("sc_toggle"):
		sc_on = not sc_on
	_starter_held = Input.is_action_pressed("starter")
	if engine_running:
		_crank_timer = 0.0
	elif Input.is_action_just_pressed("starter"):
		_crank_timer = STARTER_CYCLE_TIME
	else:
		_crank_timer = maxf(_crank_timer - delta, 0.0)

	# What is asked of the driver: the two pedal keys 0..1, the steering +1 =
	# left, -1 = right (matches the sign of yaw). From the keys, or from whoever
	# drives through set_driver_input, where a pedal asked for at all counts as
	# its key held.
	var accelerate_asked := Input.get_action_strength("accelerate")
	var brake_asked := Input.get_action_strength("brake")
	var accelerate_pressed := Input.is_action_pressed("accelerate")
	var brake_pressed := Input.is_action_pressed("brake")
	var steer_input := Input.get_axis("steer_right", "steer_left")
	var handbrake_held := Input.is_action_pressed("handbrake")
	if _driver_input_active:
		accelerate_asked = _driver_accelerate
		brake_asked = _driver_brake
		accelerate_pressed = _driver_accelerate > 0.0
		brake_pressed = _driver_brake > 0.0
		steer_input = _driver_steer
		handbrake_held = _driver_handbrake

	# What the car weighs this tick (total_mass()): the fuel burnt last tick is
	# off it.
	fuel_mass = fuel_l * FUEL_DENSITY

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
	# The direction is chosen by what is asked for, the keys themselves (+1 =
	# accelerate key, -1 = brake key, both held cancel out): a fresh press is a
	# fresh press however far the foot has got. The pedals then go where the
	# feet take them, and `drive_input` is the same signal read off the pedals,
	# which is what the drivetrain works with.
	_update_direction(forward_speed, accelerate_asked - brake_asked, accelerate_pressed, brake_pressed, delta)
	_move_feet(accelerate_asked, brake_asked, delta)
	_move_clutch_foot(Input.is_action_pressed("clutch_pedal"), delta)
	var drive_input := (_brake_foot - _throttle_foot) if reverse_engaged else (_throttle_foot - _brake_foot)
	if handbrake_held:
		_handbrake_amount = 1.0
		_rear_lock_recovery = 1.0
	else:
		# The lever comes out with the key - the clutch is the driver's again
		# on that tick - and what is left on the rear brakes dies away after
		# it, the throttle able to pull against it.
		_handbrake_amount = 0.0
		_rear_lock_recovery = move_toward(_rear_lock_recovery, 0.0, REAR_LOCK_RECOVERY_RATE * delta)

	# 2. Wheel loads: what the four corners of the suspension push the body up
	#    with right now, from where the body is on its springs and what the
	#    road does under each wheel (see _corner_forces). The axle load the
	#    tyres work with is the sum of its two wheels. Nothing is shifted by
	#    hand: braking, power, cornering, downforce and the road are all in the
	#    springs' states (_advance_body, at the end of the tick).
	#    was a static split shifted by acceleration x CG_HEIGHT / wheelbase
	#    (eased in at LOAD_TRANSFER_RESPONSE, capped at MAX_LOAD_TRANSFER) plus
	#    downforce, halved per wheel, plus a road ripple -> the spring forces.
	var weight := total_mass() * _gravity
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
	#    for (a share of its 450 degrees each way) at the driver's hand speed
	#    (STEERING_HAND_SPEED for the test driver); the rack turns that into
	#    front wheel angle.
	steering_wheel_deg = move_toward(steering_wheel_deg, steer_input * STEERING_WHEEL_LOCK_DEG, driver_profile.steering_hand_speed * delta)
	steer = steering_wheel_deg / STEERING_WHEEL_LOCK_DEG
	var front_arm := AXLE_DISTANCE + CG_OFFSET
	var rear_arm := AXLE_DISTANCE - CG_OFFSET
	var yaw_inertia := total_mass() * YAW_GYRATION_RADIUS * YAW_GYRATION_RADIUS
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
	throttle_pedal = pedals.throttle
	brake_pedal = pedals.brake / (BRAKE_DECEL * total_mass())
	_update_creep(forward_speed, delta)
	# Rolling rears slide on REAR_TYRE_SLIDE_GRIP, locked ones on TYRE_SLIDE_GRIP,
	# and eased back from one to the other as the lock leaves them.
	var rear_slide_grip := lerpf(REAR_TYRE_SLIDE_GRIP, TYRE_SLIDE_GRIP, _rear_lock_recovery)
	var front_contact := {"along": front_along, "grip": front_grip, "slip_angle": front_slip_angle, "peak_slip_angle": FRONT_PEAK_SLIP_ANGLE, "slide_grip": TYRE_SLIDE_GRIP}
	var rear_contact := {"along": forward_speed, "grip": rear_grip, "slip_angle": rear_slip_angle, "peak_slip_angle": REAR_PEAK_SLIP_ANGLE, "slide_grip": rear_slide_grip}
	_advance_drivetrain(pedals.throttle, pedals.coasting, pedals.brake, front_contact, rear_contact, delta)
	# After the drivetrain: the engine's speed and whether it runs are this
	# tick's, and the starter's draw of this tick is in the charge already.
	_advance_battery(delta)
	if _handbrake_amount > 0.0:
		# Held, the lever stops the rear wheels outright. Let go, what holds
		# them is a brake torque like any other (HANDBRAKE_RELEASE_TORQUE, in
		# _advance_drivetrain), which the engine can pull against.
		rear_omega = 0.0
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
	var rolling_drag := COAST_DECEL * total_mass()
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
	forward_speed += pushing / total_mass() * delta
	forward_speed = move_toward(forward_speed, 0.0, slowing / total_mass() * delta)
	longitudinal_accel = (forward_speed - speed_before) / delta
	lateral_accel = -right_force / total_mass()

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
	cg_lateral_speed += right_force / total_mass() * delta
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

	_count_odometer(delta)
	_update_visuals(delta)


## The way the body got over the ground this tick goes on the odometer (level
## distance, x and z; anything not finite is no way at all), and every
## ODOMETER_SAVE_INTERVAL the odometer goes to its file, where that is on - and
## the fuel level and the battery as they stand with it: after a reset that is
## the full tank and the new battery the reset put in, which is what the car
## has.
func _count_odometer(delta: float) -> void:
	var way := Vector2(global_position.x - _odometer_from.x, global_position.z - _odometer_from.z).length()
	if is_finite(way):
		odometer_m += way
	_odometer_from = global_position
	if not _odometer_kept:
		return
	_since_odometer_save += delta
	if _since_odometer_save >= ODOMETER_SAVE_INTERVAL:
		_since_odometer_save = 0.0
		# was save_odometer -> the fuel in the tank goes with it, and the
		# dashboard the driver has set, and the battery, all in the one write.
		OdometerStore.save_car(CAR_ID, odometer_m, fuel_l, OdometerStore.PATH, driver_settings(), battery_settings())


## Puts the car back where the scene placed it, at rest, in 1st, automatic, the
## engine running, the tank full and nothing loaded.
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


## Puts the car at `target`, at rest, in 1st, automatic, the engine running
## (a stalled one is started: the car is put there ready to drive), the tank
## full, the battery full and healthy (the test pad never strands anyone: a
## reset is a fresh car, its battery new) and nothing loaded (payload_mass is
## for whoever resets the car to load again afterwards). The switches stay as
## the driver has them: tcs_on, abs_on, sc_on, gearbox_mode - and so does the
## view being looked through, camera_view. Of what the store keeps, the gearbox
## is put back (automatic), the tank and the battery are filled; nothing a
## reset does reaches the file, which goes on writing these as they then
## stand. The height of `target` counts from the road: the car is stood on its springs on the road
## there (_settle_suspension), 0 = at its ride height.
## The odometer keeps its metres, and the jump to `target` is not among them.
func reset_to(target: Transform3D) -> void:
	global_transform = target
	_odometer_from = target.origin
	velocity = Vector3.ZERO
	forward_speed = 0.0
	lateral_speed = 0.0
	yaw_rate = 0.0
	slide_yaw_rate = 0.0
	steering_wheel_deg = 0.0
	steer = 0.0
	_handbrake_amount = 0.0
	_rear_lock_recovery = 0.0
	_throttle_foot = 0.0
	_brake_foot = 0.0
	throttle_pedal = 0.0
	brake_pedal = 0.0
	clutch_pedal = 0.0
	_driver_has_clutch = false
	_clutch_dumped = false
	reverse_engaged = false
	_forward_engage_timer = 0.0
	gear = 1
	automatic = true
	engine_omega = IDLE_RPM * TAU / 60.0
	engine_running = true
	limiter_cutting = false
	clutch_engagement = 0.0
	clutch_locked = false
	clutch_torque = 0.0
	_shift_catching = false
	_shift_timer = 0.0
	_since_shift = AUTO_SHIFT_HOLD
	_creeping = false
	_creep_armed = false
	_creep_rest_time = 0.0
	fuel_l = FUEL_TANK_CAPACITY_L
	fuel_mass = fuel_l * FUEL_DENSITY
	battery_wear = 0.0
	battery_charge = 1.0
	_battery_deep = false
	payload_mass = 0.0
	exhaust_events = 0.0
	exhaust_flow = 0.0
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
	reset_counter += 1


## What the car weighs right now [kg]: the base car, the fuel in its tank and
## what it carries. The one mass of the model: everything that pushes, turns,
## brakes or carries the car reads this.
func total_mass() -> float:
	return BASE_MASS + fuel_mass + payload_mass


## True while the starter motor turns the engine: the key held or a press's
## cycle still running (STARTER_CYCLE_TIME), on an engine that is not running.
func cranking() -> bool:
	return (_starter_held or _crank_timer > 0.0) and not engine_running


## How full the tank is, 0 (dry) .. 1 (full). What the HUD's fuel bar shows.
func fuel_fraction() -> float:
	return clampf(fuel_l / FUEL_TANK_CAPACITY_L, 0.0, 1.0)


## The share of its rated torque (CRANKING_TORQUE) the starter makes on the
## battery as it is, 0..1: the square root of battery_charge. The one empirical
## line in the electrical model, the shape of a lead-acid's cranking against
## its state of charge: nearly full strength down to half (0.71 at 0.5), away
## steeply under a fifth (0.45 at 0.2), nothing at empty. What follows is the
## model's own: against the engine's friction (15.5 Nm at ENGINE_CATCH_RPM) the
## 150 Nm, 700 rpm starter gets a stopped engine to the catch only over a
## strength of 0.36, a charge of ~13 %, and takes measurably longer from half.
## The draw goes with the square of this (STARTER_POWER: current with the
## torque, voltage with the strength), so with the charge.
func battery_cranking_strength() -> float:
	return sqrt(clampf(battery_charge, 0.0, 1.0))


## What the alternator makes at `rpm` [W]: none under ALTERNATOR_CUT_IN_RPM, a
## line up to ALTERNATOR_POWER at ALTERNATOR_RATED_RPM, flat from there.
static func alternator_power(rpm: float) -> float:
	if ALTERNATOR_RATED_RPM <= ALTERNATOR_CUT_IN_RPM:
		return ALTERNATOR_POWER if rpm >= ALTERNATOR_RATED_RPM else 0.0
	return ALTERNATOR_POWER * clampf((rpm - ALTERNATOR_CUT_IN_RPM) / (ALTERNATOR_RATED_RPM - ALTERNATOR_CUT_IN_RPM), 0.0, 1.0)


## What the battery holds when full, as worn as it is [J]: BATTERY_CAPACITY_J
## less what battery_wear has taken. What battery_charge x BATTERY_CAPACITY_J
## can get up to.
func battery_capacity_j() -> float:
	return BATTERY_CAPACITY_J * (1.0 - battery_wear)


## Drives the car without the keys: from the next tick on the driver is asked
## for this much of the accelerate key's pedal and of the brake key's (0..1
## each) and this much steering (-1 = full right .. +1 = full left), handbrake
## pulled or not, until the next call or clear_driver_input. The same thing the
## keys ask for and nothing more direct: the driver_profile's feet and hands
## still take the pedals and the wheel there, and the two pedals mean what the
## two keys mean, reverse included (brake asked for anew at a standstill engages
## it, see reverse_engaged). Out of range is clamped, NaN is nothing asked for.
func set_driver_input(throttle: float, brake: float, steer_amount: float, handbrake := false) -> void:
	_driver_input_active = true
	_driver_accelerate = 0.0 if is_nan(throttle) else clampf(throttle, 0.0, 1.0)
	_driver_brake = 0.0 if is_nan(brake) else clampf(brake, 0.0, 1.0)
	_driver_steer = 0.0 if is_nan(steer_amount) else clampf(steer_amount, -1.0, 1.0)
	_driver_handbrake = handbrake


## Hands the car back to the keys.
func clear_driver_input() -> void:
	_driver_input_active = false


## Puts a driver in the seat: one of DRIVER_PROFILES or a dictionary with some
## of its keys, the rest are the test driver's. Rates are never negative, NaN is
## the test driver's figure. Where the feet and hands are right now stays.
func set_driver_profile(profile: Dictionary) -> void:
	var seated := {}
	var test_driver: Dictionary = DRIVER_PROFILES["test_driver"]
	for key: String in test_driver:
		var rate := float(profile.get(key, test_driver[key]))
		seated[key] = test_driver[key] if is_nan(rate) else maxf(rate, 0.0)
	driver_profile = seated


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
	var weight := total_mass() * _gravity
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
	# The static share is that of the car as it weighs now, fuel and payload in:
	# the spring seats carry the load, the rates stay those of the car on its
	# kerb weight (see FRONT / REAR_CORNER_MASS).
	var weight := total_mass() * _gravity
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
##   heave:  total_mass()  x d(vertical speed) = sum of loads - weight - downforce
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
	pitch_moment += (total_mass() * longitudinal_accel + air_drag) * CG_HEIGHT
	pitch_moment -= downforce * (AERO_BALANCE_FRONT * front_arm - (1.0 - AERO_BALANCE_FRONT) * rear_arm)
	roll_moment -= total_mass() * lateral_accel * CG_HEIGHT
	pitch_rate += pitch_moment / PITCH_INERTIA * delta
	roll_rate += roll_moment / ROLL_INERTIA * delta
	body_pitch += pitch_rate * delta
	body_roll += roll_rate * delta
	return vertical_speed + (lift - total_mass() * _gravity - downforce) / total_mass() * delta


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


## What the shift-up key does: manual mode, and one position up the box. Out of
## reverse that is neutral (at any speed: taking a box out of gear never hurt
## one), from there 1st and on up (shift_to). Returns true if the box moved.
func shift_up() -> bool:
	automatic = false
	if reverse_engaged:
		return _select_reverse(false)
	return shift_to(gear + 1)


## What the shift-down key does: manual mode, and one position down the box
## (shift_to), to neutral under 1st and to reverse under neutral. Reverse is
## refused while the car rolls forwards (what a gearbox locks out, and what the
## brake key's way into reverse waits for a standstill for as well) and, rolling
## backwards, where the road would turn the engine past the rev limiter through
## REVERSE_RATIO, as shift_to refuses a downshift. Under reverse there is
## nothing. Returns true if the box moved.
# was shift_to(gear - 1), which left reverse out of the shift keys' reach:
# neutral was the bottom of the box -> one more position under it. 1st to
# neutral is shift_to(0) as it always was.
func shift_down() -> bool:
	automatic = false
	if reverse_engaged:
		return false
	if gear > 0:
		return shift_to(gear - 1)
	var reverse_rpm := absf(forward_speed) / WHEEL_RADIUS * REVERSE_RATIO * FINAL_DRIVE * 60.0 / TAU
	if forward_speed > STANDSTILL_SPEED or reverse_rpm > REDLINE_RPM:
		return false
	return _select_reverse(true)


## Moves the lever between reverse and neutral, a gear change like the others
## (the clutch open for SHIFT_TIME). `gear` is neutral either way: in reverse
## reverse_engaged is what counts, and out of it the box is in neutral.
func _select_reverse(engage: bool) -> bool:
	reverse_engaged = engage
	_forward_engage_timer = 0.0
	gear = 0
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


## Where `mode`'s shift points are on THIS engine, as { upshift_rpm,
## downshift_rpm, margin_rpm } [rpm]: read off TORQUE_CURVE and the engine's
## friction, rpm by rpm from the curve's first point (below it the curve is
## only held flat, nothing is known there) to the limiter.
##   SPORT    up at the highest speed with SPORT_POWER_SHARE of the peak power
##            (torque x speed), down under the lowest speed with
##            SPORT_TORQUE_SHARE of the peak torque
##   COMFORT  up at that same lowest speed with SPORT_TORQUE_SHARE of the peak
##            torque, down under the lowest with COMFORT_TORQUE_SHARE of it
##   ECO      up at the highest speed with ECO_EFFICIENCY_SHARE of the best
##            brake efficiency (torque / (torque + friction), see
##            ECO_EFFICIENCY_SHARE), down under the lowest with ECO_TORQUE_SHARE
##            of the peak torque
## and the margin DOWNSHIFT_MARGIN_SHARE of the upshift speed in all three. The
## gearbox does not call this: it shifts by the constants (UPSHIFT_RPM and the
## rest), which are these figures rounded to the 100 rpm, sport's the certified
## ones. It is where they come from, and the smoke test holds each constant to
## within 50 rpm of it; a car with another curve gets its constants from here.
static func derived_shift_points(mode: GearboxMode) -> Dictionary:
	var first_rpm := int(TORQUE_CURVE[0].x)
	var peak_torque := 0.0
	var peak_power := 0.0
	var best_efficiency := 0.0
	for rpm in range(first_rpm, int(REDLINE_RPM)):
		var torque := engine_torque(rpm)
		peak_torque = maxf(peak_torque, torque)
		peak_power = maxf(peak_power, torque * rpm)
		best_efficiency = maxf(best_efficiency, torque / (torque + _engine_friction(rpm)))
	var torque_share := SPORT_TORQUE_SHARE
	match mode:
		GearboxMode.COMFORT:
			torque_share = COMFORT_TORQUE_SHARE
		GearboxMode.ECO:
			torque_share = ECO_TORQUE_SHARE
	var upshift_rpm := 0.0
	var downshift_rpm := 0.0
	var fat_from_rpm := 0.0
	for rpm in range(int(REDLINE_RPM) - 1, first_rpm - 1, -1):
		var torque := engine_torque(rpm)
		if torque >= torque_share * peak_torque:
			downshift_rpm = rpm
		if torque >= SPORT_TORQUE_SHARE * peak_torque:
			fat_from_rpm = rpm
		if upshift_rpm > 0.0:
			continue
		if mode == GearboxMode.SPORT and torque * rpm >= SPORT_POWER_SHARE * peak_power:
			upshift_rpm = rpm
		elif mode == GearboxMode.ECO and torque / (torque + _engine_friction(rpm)) >= ECO_EFFICIENCY_SHARE * best_efficiency:
			upshift_rpm = rpm
	if mode == GearboxMode.COMFORT:
		upshift_rpm = fat_from_rpm
	return {"upshift_rpm": upshift_rpm, "downshift_rpm": downshift_rpm, "margin_rpm": upshift_rpm * DOWNSHIFT_MARGIN_SHARE}


## Forward / reverse selection. A fresh key press changes direction; a brake
## key held through a stop just holds the car (see STANDSTILL_SPEED). The one
## exception is deliberate: forward is the home direction, so an accelerate key
## held through the stop in reverse engages forward after FORWARD_ENGAGE_GRACE
## and drives away in one motion. `drive` is what is asked for, accelerate
## minus brake, so both keys held cancel out and never engage anything;
## `accelerate_pressed` / `brake_pressed` say whether each key is down (or its
## pedal asked for through set_driver_input). The feet are not looked at: how
## far a pedal has got says nothing about which way the driver wants to go.
func _update_direction(speed: float, drive: float, accelerate_pressed: bool, brake_pressed: bool, delta: float) -> void:
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


## The driver's feet: each pedal is taken towards what is asked of it at the
## driver_profile's rates. `accelerate_asked` / `brake_asked` are the two KEYS'
## (0..1); which pedal each one works follows the selected direction, the brake
## key is the throttle in reverse.
func _move_feet(accelerate_asked: float, brake_asked: float, delta: float) -> void:
	var throttle_asked := brake_asked if reverse_engaged else accelerate_asked
	var brake_pedal_asked := accelerate_asked if reverse_engaged else brake_asked
	_throttle_foot = _move_pedal(_throttle_foot, throttle_asked, brake_pedal_asked, driver_profile.throttle_attack, driver_profile.throttle_release, delta)
	_brake_foot = _move_pedal(_brake_foot, brake_pedal_asked, throttle_asked, driver_profile.brake_attack, driver_profile.brake_release, delta)


## The driver's left foot: the clutch pedal goes down while the clutch key is
## `held` and comes back up when it is let go, at CLUTCH_PEDAL_SPEED. Touched,
## the clutch is the driver's (_driver_has_clutch). Not in automatic mode: there
## is no pedal there, and one that was down when the mode changed comes up.
func _move_clutch_foot(held: bool, delta: float) -> void:
	clutch_pedal = move_toward(clutch_pedal, 1.0 if held and not automatic else 0.0, CLUTCH_PEDAL_SPEED * delta)
	if clutch_pedal > 0.0:
		_driver_has_clutch = true


## Where a pedal at `pedal` is a tick later, asked for `asked` (0..1): down at
## `attack`, up at `release` [1/s]. With nothing asked of it and the other pedal
## asked for, the foot has left it for that one and it is up at once.
func _move_pedal(pedal: float, asked: float, other_asked: float, attack: float, release: float, delta: float) -> float:
	if asked <= 0.0 and other_asked > 0.0:
		return 0.0
	return move_toward(pedal, asked, (attack if asked > pedal else release) * delta)


## What the pedals ask for this tick, as { throttle, brake, coasting }, and the
## gearbox update on the way. `throttle` is the engine's, 0..1; `coasting` is
## true while the driver asks for none (a lift for a gear change is not
## coasting). `brake` is the total
## brake force asked for at the tyres [N], always positive; it works against
## the way each wheel turns. `drive` is +1 for the accelerate key's pedal on the
## floor and -1 for the brake key's, anything in between as the feet have them.
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

	if automatic and gearbox_mode == GearboxMode.ECO:
		# The eco program's flattened pedal: the engine gets no more than this,
		# either way the car is driven. Nothing here for the other programs.
		throttle = minf(throttle, ECO_MAX_THROTTLE)

	var coasting := throttle <= 0.0
	_update_gearbox(speed, throttle, reversing, delta)
	# The driver lifts for a gear change and comes back on the throttle once
	# the clutch is home again. On the way down the box the same foot blips the
	# throttle while the clutch is open (DOWNSHIFT_BLIP_BAND).
	if _shift_catching:
		var revs_missing := _gearbox_omega() - engine_omega
		throttle = clampf(revs_missing / DOWNSHIFT_BLIP_BAND, 0.0, 1.0) if is_shifting else 0.0
	var brake := BRAKE_DECEL * absf(drive) * total_mass() if braking else 0.0
	return {"throttle": throttle, "brake": brake, "coasting": coasting}


## Whether the car creeps this tick (_creeping; what it does with it is
## _clutch_target's). The car has to be in the mood: automatic, 1st, not in
## reverse, no gear change on, the engine running on fuel, handbrake off, no throttle,
## rolling no faster than CREEP_MAX_SPEED; anything else ends the creep and
## disarms it. The brake holding the car at a standstill arms it (and a brake
## on the moving car disarms it: that one is slowing it, not holding it); the
## brake let go, the car armed and still standing, it creeps after CREEP_DWELL
## and goes on until something above ends it. The pedals are read where the
## drivetrain sees them (throttle_pedal, brake_pedal).
func _update_creep(speed: float, delta: float) -> void:
	var standing := absf(speed) < CREEP_ENGAGE_SPEED
	var in_the_mood := (
		automatic and gear == 1 and not reverse_engaged and not is_shifting
		and engine_running and fuel_l > 0.0 and _handbrake_amount <= 0.0
		and throttle_pedal <= 0.0 and absf(speed) <= CREEP_MAX_SPEED
	)
	if not in_the_mood or brake_pedal > 0.0:
		_creeping = false
		_creep_armed = in_the_mood and standing
		_creep_rest_time = 0.0
	elif not _creeping:
		_creep_rest_time = _creep_rest_time + delta if _creep_armed and standing else 0.0
		_creeping = _creep_rest_time >= CREEP_DWELL


## Overall ratio between the engine and the driven wheels right now: gear x
## final drive, negative in reverse (the engine turns its own way, the wheels
## backwards), 0 in neutral.
func _drive_ratio() -> float:
	if reverse_engaged:
		return -REVERSE_RATIO * FINAL_DRIVE
	return GEAR_RATIOS[gear] * FINAL_DRIVE


## How far in the car wants its clutch (0..1). Open in neutral, for the
## SHIFT_TIME of a gear change, on an engine that is not running (a stalled
## car rolls free, and the starter has the engine alone to turn: there is no
## bump start), and, throttle closed, once the gearbox
## would turn the engine under CLUTCH_DISENGAGE_RPM: that is the stop in gear,
## and the standstill. Home otherwise: under throttle from any speed (from a
## standstill that is the launch, slipping), and throttle closed at speed
## (engine braking). Coasting, a clutch that comes back in is there to hold
## the car back, never to shove it on: while the engine still turns faster
## than the gearbox (the revs left over from before a handbrake turn) it stays
## open and waits for the revs to fall. A gear change is seen through either
## way: that catch is part of the change.
##   The handbrake opens it too, driven rear wheels locked (or the locked axle
## would stall the engine), and so does the moment after it in which the lock
## is still leaving the rear tyres - unless the driver asks for throttle, and
## then the driver wins, as with the clutch pedal: the clutch comes back in
## and drives the rears. That is the kick that catches a slide, and it is why
## the throttle is read before the handbrake here. Rolling
## against the gear it drags at CLUTCH_DRAG_ENGAGEMENT, and creeping
## (_update_creep) it is in by CREEP_CLUTCH_ENGAGEMENT, less with every bit of
## forward speed, out at CREEP_FREE_SPEED.
func _clutch_target(speed: float, gearbox_omega: float, throttle: float, coasting: bool) -> float:
	var rear_driven := driven_wheels != DrivenWheels.FWD
	if (gear == 0 and not reverse_engaged) or is_shifting:
		return 0.0
	if not engine_running:
		return 0.0
	# Asked for, the throttle wins over the handbrake's stall protection below:
	# the clutch comes in (at CLUTCH_ENGAGE_TIME / CLUTCH_SHIFT_ENGAGE_TIME, and
	# feathered against the revs falling) and the rears are driven again.
	if throttle > 0.0:
		return 1.0
	if _rear_lock_recovery > 0.0 and rear_driven:
		return 0.0
	if _creeping:
		return CREEP_CLUTCH_ENGAGEMENT * clampf(1.0 - speed / CREEP_FREE_SPEED, 0.0, 1.0)
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
##   All of that feathering is the car's. With the TCS switched off the launch
## floor only sees the revs up, then the clutch is let in for good, with no
## slip limit (see DRIVE_SLIP_RATIO); and a clutch the driver's own foot is
## bringing in (clutch_pedal) is not feathered at all, may lock under idle, and
## can drag the engine down to where it stalls (see CLUTCH_PEDAL_SPEED).
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
	# The handbrake is on the rear brakes, not on the ABS's circuit: what it
	# still holds them with goes on top, and the ABS does not let it go.
	var rear_hold := HANDBRAKE_RELEASE_TORQUE * _rear_lock_recovery
	rear_brake += rear_hold
	var abs_active := abs_on and brake > 0.0
	var rear_abs := abs_active and rear_hold <= 0.0
	var gearbox_omega := _gearbox_omega()

	# The car's own idea of the clutch, and over it the driver's pedal: the
	# clutch is in no further than the pedal lets it. Once the clutch is home,
	# or open with the foot off the pedal, it is the car's again.
	var own_target := _clutch_target(forward_speed, gearbox_omega, throttle, coasting)
	var target := minf(own_target, 1.0 - clutch_pedal)
	if own_target <= 0.0 or clutch_locked:
		_clutch_dumped = false
	if clutch_pedal <= 0.0 and (own_target <= 0.0 or (clutch_locked and engine_omega >= idle_omega)):
		_driver_has_clutch = false
	# The car never lets its clutch lock under idle. The driver's foot can: the
	# engine is then lugged along with the car, down to where it stalls.
	var lock_floor := STALL_RPM * TAU / 60.0 if _driver_has_clutch else idle_omega
	if target <= clutch_engagement or _driver_has_clutch:
		# Opening is a stab at the pedal: at once. And under the driver's foot
		# the clutch is where the pedal has it.
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
		var next_rear := _advance_axle(rear_omega, at_axle * rear_share, rear_brake, AXLE_INERTIA + reflected * rear_share, rear, rear_abs, delta)
		var next_engine := (next_front * front_share + next_rear * rear_share) * ratio
		var held := net - ENGINE_INERTIA * (next_engine - engine_omega) / delta
		if absf(held) <= capacity and next_engine >= lock_floor:
			_run_engine_outputs(throttle, 0.0, delta)
			front_omega = next_front
			rear_omega = next_rear
			engine_omega = next_engine
			clutch_torque = held
			_update_limiter()
			return
		clutch_locked = false

	var slip := engine_omega - gearbox_omega
	clutch_torque = capacity * clampf(slip / CLUTCH_SLIP_BAND, -1.0, 1.0)
	# was LAUNCH_RPM whatever the program -> no higher than the program shifts up
	# at - flat out from rest comfort held the revs at LAUNCH_RPM's 4000 on the
	# slipping clutch until the road had 1st at COMFORT_UPSHIFT_RPM, and changed
	# up with 3954 rpm on the tach: the user's "it goes to 4000 to change, that
	# is still sporty" (2026-09-21) over again, whatever the shift point. Sport's
	# 6800 is over LAUNCH_RPM and manual mode knows no program: LAUNCH_RPM as
	# ever for both.
	var launch_rpm := minf(LAUNCH_RPM, _upshift_rpm()) if automatic else LAUNCH_RPM
	var floor_omega := lerpf(IDLE_RPM, launch_rpm, throttle) * TAU / 60.0
	if not tcs_on and throttle > 0.0 and gearbox_omega < floor_omega and engine_omega >= floor_omega - LAUNCH_BITE_BAND:
		# TCS off: the revs are up to where the clutch bites, and it is let in
		# for good.
		_clutch_dumped = true
	if gearbox_omega < floor_omega and clutch_torque > 0.0 and not _clutch_dumped and not _driver_has_clutch:
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
	var next_rear := _advance_axle(rear_omega, rear_torque, rear_brake, AXLE_INERTIA, rear, rear_abs, delta)
	if clutch_torque > 0.0 and tcs_on and not _driver_has_clutch:
		# The same foot feathers the clutch against wheelspin: a driven axle is
		# let spin up to DRIVE_SLIP_RATIO and given no more torque than holds
		# it there. Only while the clutch slips; locked, the wheels are the
		# engine's. Not with the TCS off, and not under the driver's own foot.
		if front_share > 0.0:
			var eased := _ease_for_wheelspin(front_omega, next_front, front_torque, front, delta)
			if eased.x != front_torque:
				front_torque = eased.x
				next_front = eased.y if eased.x != 0.0 else _advance_axle(front_omega, 0.0, front_brake, AXLE_INERTIA, front, abs_active, delta)
		if rear_share > 0.0:
			var eased := _ease_for_wheelspin(rear_omega, next_rear, rear_torque, rear, delta)
			if eased.x != rear_torque:
				rear_torque = eased.x
				next_rear = eased.y if eased.x != 0.0 else _advance_axle(rear_omega, 0.0, rear_brake, AXLE_INERTIA, rear, rear_abs, delta)
		clutch_torque = (front_torque + rear_torque) / (ratio * DRIVETRAIN_EFFICIENCY)
	front_omega = next_front
	rear_omega = next_rear
	_run_engine_outputs(throttle, clutch_torque, delta)
	_advance_engine(_engine_net_torque(engine_rpm, throttle, clutch_torque) - clutch_torque, delta)
	if clutch_engagement <= 0.0:
		return
	var slip_after := engine_omega - _gearbox_omega()
	if (slip * slip_after <= 0.0 or absf(slip_after) < CLUTCH_SLIP_BAND) and _gearbox_omega() >= lock_floor:
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
	return share * brake * WHEEL_RADIUS + inertia * brake / (total_mass() * WHEEL_RADIUS)


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
##   Under the foot brake the ABS (`abs_active`) holds the wheel at
## ABS_SLIP_RATIO instead of letting it lock (it lets go of as much brake torque
## as that takes); with it the handbrake alone locks wheels, the rear ones -
## outright while the lever is held (_handbrake_amount) and on
## HANDBRAKE_RELEASE_TORQUE as it lets go, which is a brake torque like any
## other and is passed with the ABS switched off for that axle. Without it a
## brake torque the tyre cannot answer stops the
## wheel, and holds it stopped for as long as it is more than the road's pull
## on the locked tyre.
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
			var upshift_rpm := _upshift_rpm()
			var downshift_rpm := DOWNSHIFT_RPM
			var margin_rpm := DOWNSHIFT_MARGIN_RPM
			match gearbox_mode:
				GearboxMode.COMFORT:
					downshift_rpm = COMFORT_DOWNSHIFT_RPM
					margin_rpm = COMFORT_DOWNSHIFT_MARGIN_RPM
				GearboxMode.ECO:
					downshift_rpm = ECO_DOWNSHIFT_RPM
					margin_rpm = ECO_DOWNSHIFT_MARGIN_RPM
			if throttle > 0.0 and gear < GEAR_RATIOS.size() - 1 and wheel_rpm(gear) >= upshift_rpm:
				shift_to(gear + 1)
			elif (
				lower >= 1
				and wheel_rpm(gear) < downshift_rpm
				and wheel_rpm(lower) < upshift_rpm - margin_rpm
			):
				shift_to(lower)


## The engine speed the automatic's program shifts up at [rpm] (see GearboxMode).
func _upshift_rpm() -> float:
	match gearbox_mode:
		GearboxMode.COMFORT:
			return COMFORT_UPSHIFT_RPM
		GearboxMode.ECO:
			return ECO_UPSHIFT_RPM
	return UPSHIFT_RPM


## Net torque on the crankshaft from the engine itself [Nm] at `rpm` with the
## pedal at `throttle` (0..1): what the burning fuel makes, less friction and
## pumping losses. TORQUE_CURVE is what is left of the two at full throttle, so
## combustion is the curve plus the losses, scaled by the throttle; closed, the
## losses are all there is, and that is the engine braking. Two things work the
## throttle besides the driver: the idle controller adds to it as the revs come
## down to IDLE_RPM (enough to carry the friction and the `load` [Nm] the
## clutch takes off the crankshaft there, plus IDLE_CONTROL_GAIN for every
## rad/s below), and the rev limiter shuts the fuel off (limiter_cutting).
## A dry tank is a fuel cut that stays, and an engine that is not running
## (engine_running) makes nothing at all: its friction is what is left.
func _engine_net_torque(rpm: float, throttle: float, load: float) -> float:
	return _combustion_torque(rpm, throttle, load) - _engine_friction(rpm)


## Friction and pumping losses of the engine at `rpm` [Nm] (see
## ENGINE_FRICTION_TORQUE).
static func _engine_friction(rpm: float) -> float:
	return ENGINE_FRICTION_TORQUE + ENGINE_FRICTION_TORQUE_PER_RPM * rpm


## What the burning fuel makes on the crankshaft [Nm] at `rpm` with the pedal
## at `throttle` and the clutch taking `load` [Nm] (see _engine_net_torque):
## full combustion times the throttle the engine really has, the driver's plus
## the idle controller's. None while the fuel is cut or the engine is not
## running. What the fuel burn and the exhaust go by.
func _combustion_torque(rpm: float, throttle: float, load: float) -> float:
	if not engine_running or limiter_cutting or fuel_l <= 0.0:
		return 0.0
	return (engine_torque(rpm) + _engine_friction(rpm)) * _engine_throttle(rpm, throttle, load)


## The throttle the engine really has (0..1) with the pedal at `throttle`: the
## driver's plus what the idle controller opens by itself.
func _engine_throttle(rpm: float, throttle: float, load: float) -> float:
	var friction := _engine_friction(rpm)
	var idle_torque := friction + load + IDLE_CONTROL_GAIN * (IDLE_RPM - rpm) * TAU / 60.0
	var idle_throttle := clampf(idle_torque / (engine_torque(rpm) + friction), 0.0, IDLE_CONTROL_MAX_THROTTLE)
	return minf(throttle + idle_throttle, 1.0)


## What comes out of the engine over one tick at the speed and throttle it has
## going into it, the clutch taking `load` [Nm]: the fuel it burns (see Fuel and
## exhaust) and the exhaust it makes (exhaust_events, exhaust_flow). Called
## once a tick, where the engine's speed is integrated.
func _run_engine_outputs(throttle: float, load: float, delta: float) -> void:
	var combustion := _combustion_torque(engine_rpm, throttle, load)
	var burn := combustion * engine_omega / FUEL_BURN_EFFICIENCY / FUEL_LHV
	fuel_l -= burn / FUEL_DENSITY * delta
	var blowing := 0.0
	if combustion > 0.0:
		exhaust_events += engine_omega / TAU * FIRINGS_PER_REVOLUTION * delta
		blowing = _engine_throttle(engine_rpm, throttle, load) * lerpf(EXHAUST_FLOW_AT_REST, 1.0, clampf(engine_rpm / REDLINE_RPM, 0.0, 1.0))
	exhaust_flow = lerpf(exhaust_flow, blowing, 1.0 - exp(-EXHAUST_FLOW_RATE * delta))


## One tick of the engine speed under `torque` [Nm], everything on the
## crankshaft added up: d(omega) = torque / ENGINE_INERTIA * delta. The limiter
## cuts the fuel the moment the revs get to REDLINE_RPM, so the engine never
## runs past it under its own power: the step stops there. The starter motor's
## torque comes on top while it cranks an engine that is not running
## (CRANKING_TORQUE at the battery's cranking strength, see cranking), drawn
## off the battery as it is made (STARTER_POWER), and where the step leaves the revs decides whether the
## engine runs: under STALL_RPM it has stopped, turned past ENGINE_CATCH_RPM
## with fuel in the tank it has caught.
func _advance_engine(torque: float, delta: float) -> void:
	var limit := REDLINE_RPM * TAU / 60.0
	if cranking():
		# was CRANKING_TORQUE x the line -> x the battery's strength as well:
		# 1.0 on a full battery, the same torque to the bit.
		var strength := battery_cranking_strength()
		var starter_line := maxf(1.0 - engine_rpm / STARTER_FREE_RPM, 0.0)
		torque += CRANKING_TORQUE * strength * starter_line
		# The draw: a DC motor's current goes with its torque, and the power
		# with the current and the voltage - the strength twice, so the charge.
		battery_charge -= STARTER_POWER * strength * strength * starter_line * delta / BATTERY_CAPACITY_J
	var next := engine_omega + torque / ENGINE_INERTIA * delta
	if engine_omega <= limit:
		next = minf(next, limit)
	engine_omega = maxf(next, 0.0)
	if engine_running:
		engine_running = engine_rpm >= STALL_RPM
	else:
		engine_running = engine_rpm >= ENGINE_CATCH_RPM and fuel_l > 0.0
	_update_limiter()


## One tick of the battery under everything but the starter (that draw is in
## _advance_engine, with the torque it buys): the key-on load with the engine
## off, the alternator's output less the ignition's load with it running -
## charging at BATTERY_CHARGE_EFFICIENCY and tapering off from
## BATTERY_TAPER_CHARGE of full, discharging in full when the alternator has
## less than the ignition takes. Then the wear: the tick the charge goes under
## BATTERY_DEEP_DISCHARGE_CHARGE costs BATTERY_DEEP_DISCHARGE_WEAR, and every
## tick down there BATTERY_FLAT_WEAR_RATE more; the setters hold the wear under
## BATTERY_WEAR_LIMIT and the charge under what the wear leaves. On a full,
## healthy battery with the engine running - every certified run - the flow in
## is tapered to exactly 0 and nothing here changes anything.
func _advance_battery(delta: float) -> void:
	var flow := -BATTERY_KEY_ON_LOAD
	if engine_running:
		flow = alternator_power(engine_rpm) - BATTERY_RUNNING_LOAD
	if flow > 0.0:
		var full := 1.0 - battery_wear
		var taper_band := (1.0 - BATTERY_TAPER_CHARGE) * full
		var acceptance := 1.0 if taper_band <= 0.0 else clampf((full - battery_charge) / taper_band, 0.0, 1.0)
		flow *= BATTERY_CHARGE_EFFICIENCY * acceptance
	battery_charge += flow * delta / BATTERY_CAPACITY_J
	if battery_charge < BATTERY_DEEP_DISCHARGE_CHARGE:
		if not _battery_deep:
			_battery_deep = true
			battery_wear += BATTERY_DEEP_DISCHARGE_WEAR
		battery_wear += BATTERY_FLAT_WEAR_RATE * delta
	else:
		_battery_deep = false


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
	var stopping_force := absf(slip_speed) / ((1.0 / total_mass() + arm * arm / yaw_inertia) * delta)
	return clampf(force, -stopping_force, stopping_force)


## Stability assist strength right now [1/s]: SLIDE_YAW_DAMPING while the car
## points roughly where it is going, fading to SPIN_YAW_DAMPING as the slip
## angle (nose vs direction of travel, 0..PI) grows past SPIN_COMMIT_ANGLE.
## Off while the handbrake is held and while the rears it locked are picking
## their grip up again (that slide is deliberate, see REAR_LOCK_RECOVERY_RATE)
## and, like a real stability system, with reverse engaged: a flick at speed in reverse swings
## the nose round (J-turn). None at all with the assist switched off (sc_on),
## not even the SPIN_YAW_DAMPING those two leave.
func _slide_yaw_damping(along: float, across: float) -> float:
	if not sc_on:
		return 0.0
	if reverse_engaged:
		return SPIN_YAW_DAMPING
	if Vector2(along, across).length() < SPIN_MIN_SPEED:
		return SLIDE_YAW_DAMPING
	var slip_angle := absf(atan2(across, along))
	var spin := maxf(smoothstep(SPIN_COMMIT_ANGLE, SPIN_FREE_ANGLE, slip_angle), _rear_lock_recovery)
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
	# The step of a tick is folded into a quarter turn either way (see
	# WHEEL_DRAW_PERIOD): the same picture, and at speed the wagon-wheel effect.
	var front_step := wrapf(front_omega * delta, -WHEEL_DRAW_PERIOD * 0.5, WHEEL_DRAW_PERIOD * 0.5)
	var rear_step := wrapf(rear_omega * delta, -WHEEL_DRAW_PERIOD * 0.5, WHEEL_DRAW_PERIOD * 0.5)
	for i in _wheel_spinners.size():
		# Rolling towards -Z is a negative rotation about +X.
		_wheel_spinners[i].rotate_x(-(front_step if i < 2 else rear_step))

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
