extends SceneTree
## Headless airborne test. Run via tests/run_tests.sh, or:
##
##   godot --headless --path . --import
##   godot --headless --fixed-fps 60 --path . --script res://tests/airborne_test.gd
##
## Loads the main scene and drives the real car (set_driver_input) flat out up
## the licence ramp along its axis, from far enough back that it leaves the
## ground at the crest and again off the end of the level top, and checks that
## a car in the air is a car in the air: ballistic, no drive, no steering, the
## wheels hanging at full droop, a landing thud on the springs, the odometer
## counting the metres flown, nothing NaN, nothing teleported - and that on
## the ground nothing of it shows. The user's catch on the ramp jump
## (2026-09-22): "the jump started fine, but then the wheels and body fell
## apart... somehow the joints stretched."
## Prints "  ok    <check>" / "  FAIL  <check>" lines and the measured numbers
## of every flight. Exits 0 only if every check passes. Every wait is counted
## in physics ticks (--fixed-fps 60: the same 1/60 s steps, no wall clock).

const MAIN_SCENE := "res://scenes/main.tscn"

## Physics ticks to let the car settle on its springs after a reset.
const SETTLE_FRAMES := 20

## Where the run-up starts [m along z], on the ramp's axis (RoadProfile.RAMP_X),
## facing -z, the way the ramp climbs: 75 m of flat to the foot of the ramp, flat
## out in automatic. Measured: 26.2 m/s at the crest (from z = 130 it is 20.9
## and the car still flies, a shorter hop).
const RUN_UP_Z := 170.0

## The run is over this far past the ramp's tail [m along z], plus the settle.
const RUN_END_Z := RoadProfile.RAMP_TAIL_Z - 5.0

## Ticks the car is given on the flat past the tail to settle from the landing.
const SETTLE_AFTER_FRAMES := 120

## Most ticks a run may take (a car that never gets there fails).
const MAX_RUN_FRAMES := 1200

## Tolerances, all measured on the reference jump and given room:
## The vertical speed of a car in the air changes by exactly gravity plus its
## downforce over its mass each tick (semi-implicit Euler, the same as
## _advance_body's); anything else on it would show here [m/s per tick].
const BALLISTIC_STEP_TOLERANCE := 0.001
## The height against the closed form vy0 t - g t^2 / 2 from the first airborne
## tick [m]: the discrete integration lags it by g dt^2 n / 2 (2.6 cm at 19
## ticks) and downforce adds a few mm; 5 cm is the honest bound.
const BALLISTIC_PATH_TOLERANCE := 0.05
## The speed over the ground may only fall in the air (the air's drag); a push
## would show as a rise [m/s per tick].
const NO_THRUST_TOLERANCE := 0.000001
## The centre of mass's sideways speed (along the car's right at launch) does
## not change in the air: no force acts across the car. The air's drag acts
## along the car, and a car launched yawing drifts its heading, so a hair of
## it turns sideways: measured 0.0005 m/s [m/s].
const STEERING_LATERAL_TOLERANCE := 0.002
## A landing puts more on a wheel than its static share: the measured spike is
## 2.2 x on the fronts (nose first, crest flight) and 5.4 x on the rears
## (the tail's foot, into the bump stops); 1.5 x says it is a thud, not a graze.
const LANDING_SPIKE_MIN_RATIO := 1.5
## No tick moves the car more than this [m]: 0.45 m at the speeds here.
const MAX_STEP_M := 3.0
## The odometer's metres in the air against the same sum from the positions [m].
const ODOMETER_TOLERANCE := 0.001
## Settled after the landing: the body within this of level [rad] (measured
## 0.006 pitch, 0.000 roll).
const SETTLED_ANGLE := 0.05
## The heading of a straight launch in the air, from the launch tick [rad].
# was exactly 0 -> within 1e-5: the front lip of the body's shell kisses the
# ramp's knee at the foot (ArcadeCar.SHELL_RATE: 3.5 kN for a tick, a hair
# more on the left by the body's 0.002 rad of roll), which leaves 4e-6 rad/s
# of yaw the stability assist has all but damped by the crest; the heading
# then drifts 6e-7 rad over the 17 ticks of the crest flight (the user's
# 20:35 retest). Still no steering, still nothing put in in the air.
const STRAIGHT_HEADING_TOLERANCE := 0.00001

## The tail hop and the slope (the user's 20:35 retest). The ramp's tail falls
## RAMP_HEIGHT over RAMP_TOP_END_Z - RAMP_TAIL_Z towards -z, the way the car
## goes: a body lying on it is pitched this much, nose down [rad], -0.08.
const TAIL_SLOPE := -RoadProfile.RAMP_HEIGHT / (RoadProfile.RAMP_TOP_END_Z - RoadProfile.RAMP_TAIL_Z)
## By the tail's foot the body's pitch is within this of the slope [rad]
## (measured 0.019 off: the nose a degree high, the tyres' envelope reading
## the descending road a little late).
const SLOPE_PITCH_TOLERANCE := 0.03
## More than this either way is a tumble, not a landing [rad]; the tail hop
## keeps well under it (measured 0.125 of pitch at touchdown).
const NO_TUMBLE_ANGLE := 0.3

## The user's own jump (the 20:35 retest, sessions 78 and 79): across the
## licence ramp's 32 % flank, not along its axis. Heading 90 degrees (facing
## -x) from FLANK_RUN_UP m east of the axis at z = FLANK_Z, flat out to the
## first launch and off the throttle after it: 30 m/s at the flank, as the
## user's 31 - 36.
const FLANK_Z := 64.0
const FLANK_RUN_UP := 180.0
## The crossing that rolls the car: ROLLOVER_HEADING_DEG off the ramp's axis
## (0 = along it towards -z, 90 = across it towards -x) from ROLLOVER_RUN_UP
## m out along that heading, ~27 m/s at the flank.
const ROLLOVER_HEADING_DEG := 50.0
const ROLLOVER_RUN_UP := 120.0
## A flank run is followed this many ticks after its first touchdown, and
## may take this many in all.
const AFTER_LANDING_FRAMES := 600
const MAX_FLANK_FRAMES := 2000
## The most a wheel may ever carry [N]: its stop crushed solid at
## GROUND_CLEARANCE (~35 kN a rear wheel) plus its damper on the hardest
## touchdown. Measured 26 kN on the flank jump; 266 kN at c5ee9c3, the
## catapult (the user's 20:35 retest).
const WHEEL_LOAD_BOUND := 80000.0
## At rest on its shell the shell carries the car's weight within this share.
const REST_LOAD_TOLERANCE := 0.01
## The drop tests: the car let go with its lowest shell corner this far over
## the road [m], and given this many ticks to settle.
const DROP_HEIGHT := 0.05
const DROP_FRAMES := 300
## The car's scene: the wheels' and the body's places in it are what the
## level picture draws (the user's flip catches; see _check_flip_draws).
const CAR_SCENE := "res://scenes/car.tscn"
## A drawn wheel's bottom is on the road within this [m]: the node's place is
## single precision at a metre or two.
const DRAWN_ON_ROAD_TOLERANCE := 0.00001
## The user's handbrake roll (the 3AF catch: session 82, 23:33, t = 37 s):
## along the hill's lateral, heading -90 degrees (facing +x) at z = ROLL_Z
## (the user's 61: the body over the end of the ramp's level top), flat out
## from ROLL_RUN_UP m west of the axis, and from ROLL_PULL_X on (20 m short
## of the west flank's foot at RAMP_X - RAMP_HALF_WIDTH - RAMP_FLANK; the
## user's between x = -65 and -50 at 29 - 31 m/s) the throttle off, the
## handbrake on and the wheel ROLL_STEER to the right (the user's -0.78 ..
## -0.87), held to the end: the user let go after 0.6 s, but in the roll no
## wheel is on the road and neither matters, and on the wheels again the held
## handbrake stops the car where the idle creep would take it away.
const ROLL_Z := 61.0
const ROLL_RUN_UP := 180.0
const ROLL_PULL_X := RoadProfile.RAMP_X - 30.0
const ROLL_STEER := -0.8
## The roll is followed to rest (ROLL_REST_FRAMES ticks under ROLL_REST_SPEED
## m/s over the ground and rad/s of roll), at most ROLL_MAX_FRAMES in all.
const ROLL_REST_FRAMES := 60
const ROLL_REST_SPEED := 0.01
const ROLL_MAX_FRAMES := 2400
## Slack on the friction cap's tick-by-tick bound [m/s]: the yaw rate's
## change over a tick swings the car's origin about its centre of mass by a
## few mm/s, and the tick's air drag is taken at the speed it began with.
const ROLL_CAP_SLACK := 0.002
## The state the two flank runs start from, restored between them so the
## second is the first to the bit: what HandlingTests._start hands out fresh,
## the odometer and the battery with it.
const CARRIED_STATE: Array[String] = [
	"fuel_l", "fuel_mass", "payload_mass", "coolant_temp", "coolant_fan_on", "_combustion_heat_w", "_idle_wobble_phase",
	"front_tyre_temp", "rear_tyre_temp", "front_brake_temp", "rear_brake_temp",
	"_front_tyre_heat_w", "_rear_tyre_heat_w", "_front_brake_heat_w", "_rear_brake_heat_w",
	"clutch_wear", "front_brake_wear", "rear_brake_wear", "front_tyre_wear", "rear_tyre_wear", "engine_wear", "_clutch_slip_w",
	"battery_charge", "battery_wear", "_battery_deep", "odometer_m",
]

var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var packed: PackedScene = load(MAIN_SCENE)
	if packed == null:
		printerr("FAIL main scene does not load")
		quit(1)
		return
	var main := packed.instantiate()
	root.add_child(main)
	await _step(SETTLE_FRAMES)
	var car := main.get_node_or_null("Car") as ArcadeCar
	if car == null:
		printerr("FAIL main scene has no Car")
		quit(1)
		return

	# On the ground nothing of it shows: the car stood at its spawn, on the flat.
	_check(not car.is_airborne and car.airborne_frames == 0 and car.wheel_supported.all(func(s: bool) -> bool: return s) and car.wheel_loads.min() > 0.0,
		"stood on the flat: every wheel on the road and loaded, not airborne, 0 airborne frames")
	# The level picture draws the whole transform now, and what it draws for
	# the wheels' and the body's places across and along the car is the
	# scene's own layout to the bit: every certified tick draws what it drew.
	# (the user's flip catches; see _check_flip_draws)
	_check(_drawn_at_layout(car), "level, the wheels and the body are drawn at the scene's places across and along the car to the bit (%s): the level picture writes them every tick and changes nothing" % _layout_text(car))

	# The reference jump: throttle held through the flights, no steering.
	var run: Dictionary = await _jump(car, 0.0)
	_check_run_up(run)
	var flights: Array = run.flights
	_check(flights.size() >= 1 and int(flights[0].ticks) > 0,
		"the car leaves the ground on the ramp: %d flight(s), the first %d ticks in the air" % [flights.size(), int(flights[0].ticks) if flights.size() > 0 else 0])
	for flight: Dictionary in flights:
		print("  flight %d: launch %.2f m/s at z = %.1f, %d ticks (%.3f s) in the air, %.2f m flown, apex +%.3f m, landing %.2f m/s at z = %.1f, %.2f m/s down" % [
			flight.index, flight.launch_speed, flight.launch_z, flight.ticks, flight.ticks / 60.0, flight.distance, flight.apex, flight.landing_speed, flight.landing_z, flight.landing_sink])
	_check_ballistic(run)
	_check_droop(run)
	_check_no_thrust(run)
	_check_landing(car, run)
	_check_finite(run, "throttle held")
	_check_odometer(run)
	_check_tail_hop(run)
	_check_slope_landing(run)

	# The second jump: the steering held hard left the moment the car is in
	# the air, let go the tick it touches down.
	var steered: Dictionary = await _jump(car, 1.0)
	_check_steering(steered)
	_check_finite(steered, "steering held in the air")

	# The flip is refused upright (the user's 20:55 thought): at rest on the
	# flat here, at speed in the flank run below.
	car.clear_driver_input()
	car.reset_to_spawn()
	await _step(SETTLE_FRAMES)
	var before := _snapshot(car, 0)
	var refused := not car.flip_car()
	_check(refused and not car.can_flip() and not car.is_overturned() and car.global_position == before.position and car.body_roll == before.roll and car.body_pitch == before.pitch,
		"the flip is refused on an upright car at rest: flip_car() false, nothing moved (up %.3f of the world's, on its shell: %s)" % [cos(car.body_pitch) * cos(car.body_roll), car.shell_load > 0.0])

	# The user's jump: across the flank, twice from the same state (the second
	# the first to the bit), the flip tried at speed on the way.
	var carried := _capture(car)
	var flank_a: Dictionary = await _flank(car, 90.0, FLANK_RUN_UP, true)
	_restore(car, carried)
	var flank_b: Dictionary = await _flank(car, 90.0, FLANK_RUN_UP, false)
	_check_flank_jump(car, flank_a)
	_check_finite(flank_a, "the flank jump")
	_check_same(flank_a, flank_b, "the flank jump twice from the same state")

	# The diagonal crossing: a rollover, the car left on its side, and the flip.
	var rollover: Dictionary = await _flank(car, ROLLOVER_HEADING_DEG, ROLLOVER_RUN_UP, true)
	_check_rollover(car, rollover)
	_check_finite(rollover, "the rollover")
	await _check_flip(car)

	# Let go leaning: the car's own tipping angle, and the roof.
	await _check_drops(car)

	# The flip and the reset off the side and off the roof redraw the wheels
	# where they are (the user's two catches on the flip).
	await _check_flip_draws(car)

	# The user's handbrake roll on the hill's lateral, twice from the same
	# state: the tumble carries its momentum, the contact no wall.
	var carried_roll := _capture(car)
	var roll_a: Dictionary = await _handbrake_roll(car)
	_restore(car, carried_roll)
	var roll_b: Dictionary = await _handbrake_roll(car)
	_check_handbrake_roll(roll_a)
	_check_finite(roll_a, "the handbrake roll")
	_check_same(roll_a, roll_b, "the handbrake roll twice from the same state")

	car.clear_driver_input()
	car.reset_to_spawn()
	_finish()


## One run: from RUN_UP_Z flat out along the ramp's axis, over the ramp and to
## RUN_END_Z, then SETTLE_AFTER_FRAMES more. `steer_in_air` is held whenever
## the car is in the air, the wheel straight otherwise. Returns the snapshots
## of every tick and the flights found in them.
func _jump(car: ArcadeCar, steer_in_air: float) -> Dictionary:
	car.reset_to(Transform3D(Basis.IDENTITY, Vector3(RoadProfile.RAMP_X, 0.0, RUN_UP_Z)))
	await _step(SETTLE_FRAMES)
	var snapshots: Array[Dictionary] = []
	var settle_left := -1
	var frame := 0
	while frame < MAX_RUN_FRAMES and settle_left != 0:
		car.set_driver_input(1.0, 0.0, steer_in_air if car.is_airborne else 0.0)
		await physics_frame
		frame += 1
		snapshots.append(_snapshot(car, frame))
		if settle_left < 0 and car.global_position.z < RUN_END_Z:
			settle_left = SETTLE_AFTER_FRAMES
		elif settle_left > 0:
			settle_left -= 1
	car.set_driver_input(0.0, 0.0, 0.0)
	return {"snapshots": snapshots, "flights": _flights(snapshots), "reached_end": settle_left == 0}


## The car's state after a tick, read once so every check sees the same tick.
func _snapshot(car: ArcadeCar, frame: int) -> Dictionary:
	var drawn: Array[float] = []
	var wheel_ups: Array[Vector3] = []
	for i in 4:
		drawn.append(_drawn_travel(car, i))
		wheel_ups.append(car._wheels[i].basis.y)
	var v := car.velocity
	return {
		"shell": car.shell_load,
		"shell_loads": car._shell_loads.duplicate(),
		"floor": car.is_on_floor(),
		"overturned": car.is_overturned(),
		"up": cos(car.body_pitch) * cos(car.body_roll),
		"body_up": car._body_basis().y,
		"wheel_ups": wheel_ups,
		"y_over_road": car.global_position.y - car.road_profile.sample_height(car.global_position.x, car.global_position.z),
		"ground_speed": Vector2(v.x, v.z).length(),
		"frame": frame,
		"position": car.global_position,
		"velocity": car.velocity,
		"right": car.global_basis.x,
		"forward": -car.global_basis.z,
		"airborne": car.is_airborne,
		"airborne_frames": car.airborne_frames,
		"supported": car.wheel_supported.duplicate(),
		"loads": car.wheel_loads.duplicate(),
		"travel": car.wheel_travel.duplicate(),
		"drawn": drawn,
		"pitch": car.body_pitch,
		"roll": car.body_roll,
		"pitch_rate": car.pitch_rate,
		"roll_rate": car.roll_rate,
		"yaw_rate": car.yaw_rate,
		"heading": car.global_rotation.y,
		"wheel_angle": car.wheel_angle,
		"rpm": car.engine_rpm,
		"rear_wheel_speed": car.rear_omega * ArcadeCar.WHEEL_RADIUS,
		"throttle": car.throttle_pedal,
		"odometer": car.odometer_m,
		"mass": car.total_mass(),
	}


## Every stretch of airborne ticks in `snapshots`: launch and landing, speed,
## distance and time. A flight still going at the last snapshot does not count.
func _flights(snapshots: Array[Dictionary]) -> Array:
	var flights: Array = []
	var first := -1
	for k in snapshots.size():
		var air: bool = snapshots[k].airborne
		if air and first < 0:
			first = k
		elif not air and first >= 0:
			var launch: Dictionary = snapshots[first]
			var last: Dictionary = snapshots[k - 1]
			var touchdown: Dictionary = snapshots[k]
			var apex := 0.0
			for j in range(first, k):
				apex = maxf(apex, snapshots[j].position.y - launch.position.y)
			flights.append({
				"index": flights.size() + 1, "first": first, "last": k - 1, "touchdown": k,
				"ticks": k - first,
				"launch_speed": _ground_speed(launch), "launch_z": launch.position.z,
				"landing_speed": _ground_speed(touchdown), "landing_z": touchdown.position.z,
				"landing_sink": -last.velocity.y,
				"distance": Vector2(touchdown.position.x - launch.position.x, touchdown.position.z - launch.position.z).length(),
				"apex": apex,
			})
			first = -1
	return flights


func _ground_speed(snapshot: Dictionary) -> float:
	var v: Vector3 = snapshot.velocity
	return Vector2(v.x, v.z).length()


## The drawn travel of wheel `i`: the wheel's offset from its seat under the
## body, solved back from where _update_visuals put the wheel node. Under
## ArcadeCar.ATTITUDE_BLEND_START that is the wheel's height alone over its
## seat; past it the wheel is carried round the centre of mass with the body,
## its travel hung along the body's own down, the two lerped by the blend -
## the same placement, inverted (the wheel's height there is lerp(level, carried, blend)
## with the travel counting 1 in the level picture and the body's up's share in
## the carried one).
# was the height alone -> through the body's basis: the wheels go round with
# the body now (the user's 20:35 retest: "the wheels stuck to the vertical
# axis").
func _drawn_travel(car: ArcadeCar, i: int) -> float:
	var level := car._wheel_rest_height + car._corner_height(i) + car._corner_trim[i] - car.global_position.y
	var blend: float = car._attitude_blend()
	if blend == 0.0:
		return car._wheels[i].position.y - level
	var basis: Basis = car._body_basis()
	var cg_local := Vector3(0.0, ArcadeCar.CG_HEIGHT, ArcadeCar.CG_OFFSET)
	var carried: float = (cg_local + basis * (car._seat_offset(i) + Vector3(0.0, car._wheel_rest_height + car._corner_trim[i], 0.0))).y
	return (car._wheels[i].position.y - lerpf(level, carried, blend)) / lerpf(1.0, basis.y.y, blend)


## On the way to the ramp's foot every wheel is on the road every tick: the
## airborne state is a no-op on the ground.
func _check_run_up(run: Dictionary) -> void:
	var ticks := 0
	var clean := true
	for snapshot: Dictionary in run.snapshots:
		if snapshot.position.z <= RoadProfile.RAMP_FOOT_Z:
			break
		ticks += 1
		clean = clean and not snapshot.airborne and snapshot.airborne_frames == 0 and snapshot.supported.all(func(s: bool) -> bool: return s) and snapshot.loads.min() > 0.0
	_check(ticks > 0 and clean, "the run-up to the ramp's foot: %d ticks on the flat, every wheel on the road and loaded, never airborne" % ticks)
	_check(run.reached_end, "the run gets over the ramp and settles past its tail within %d ticks" % MAX_RUN_FRAMES)


## Every airborne tick: the vertical speed changed by gravity plus downforce
## over the mass and nothing else, and the height follows the closed form.
func _check_ballistic(run: Dictionary) -> void:
	var snapshots: Array[Dictionary] = run.snapshots
	var delta := 1.0 / Engine.physics_ticks_per_second
	var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
	var worst_step := 0.0
	var worst_path := 0.0
	var ticks := 0
	for flight: Dictionary in run.flights:
		var first: int = flight.first
		var launch: Dictionary = snapshots[first]
		for k in range(first, int(flight.last) + 1):
			var before: Dictionary = snapshots[k - 1]
			var now: Dictionary = snapshots[k]
			# The tick's downforce is from the speed it began with, the mass
			# the one it weighed (_physics_process: downforce, then the loads).
			var speed := _ground_speed(before)
			var mass: float = now.mass
			var fall := (gravity + ArcadeCar.DOWNFORCE_COEFF * speed * speed / mass) * delta
			worst_step = maxf(worst_step, absf(now.velocity.y - before.velocity.y + fall))
			var t := float(k - first) * delta
			var launch_vy: float = launch.velocity.y
			var closed := launch_vy * t - 0.5 * gravity * t * t
			worst_path = maxf(worst_path, absf((now.position.y - launch.position.y) - closed))
			ticks += 1
	_check(ticks > 0 and worst_step < BALLISTIC_STEP_TOLERANCE,
		"ballistic: over %d airborne ticks the vertical speed steps by gravity + downforce and nothing else (worst %.6f m/s off, tolerance %.3f)" % [ticks, worst_step, BALLISTIC_STEP_TOLERANCE])
	_check(ticks > 0 and worst_path < BALLISTIC_PATH_TOLERANCE,
		"ballistic: the height follows vy0 t - g t^2 / 2 from the launch tick (worst %.3f m off, tolerance %.2f)" % [worst_path, BALLISTIC_PATH_TOLERANCE])


## Every airborne tick: no wheel is drawn past full droop; a wheel the road is
## out of reach of is drawn at exactly full droop, its travel reads the same;
## and in the air proper (all four out of reach) all four hang there.
func _check_droop(run: Dictionary) -> void:
	var snapshots: Array[Dictionary] = run.snapshots
	var limit: float = ArcadeCar.MAX_WHEEL_VISUAL_TRAVEL
	var ticks := 0
	var all_four := 0
	var never_past := true
	var hanging_at_limit := true
	var worst := 0.0
	for flight: Dictionary in run.flights:
		for k in range(flight.first, flight.last + 1):
			var snapshot: Dictionary = snapshots[k]
			ticks += 1
			var four := true
			for i in 4:
				var drawn: float = snapshot.drawn[i]
				never_past = never_past and drawn >= -limit - 0.000001
				if snapshot.supported[i]:
					four = false
				else:
					worst = maxf(worst, absf(drawn + limit))
					hanging_at_limit = hanging_at_limit and absf(drawn + limit) < 0.000001 and snapshot.travel[i] == -limit
			if four:
				all_four += 1
	_check(ticks > 0 and never_past, "in the air no wheel is drawn past full droop (%.3f m) on any of %d airborne ticks" % [limit, ticks])
	_check(ticks > 0 and hanging_at_limit, "a wheel the road is out of reach of hangs at exactly full droop, drawn and in wheel_travel (worst %.7f m off)" % worst)
	_check(all_four > 0, "all four wheels hang at full droop on %d of the %d airborne ticks (the rest: a wheel still within reach of the road, unloaded, drawn on it)" % [all_four, ticks])


## Every airborne tick with the throttle down: the speed over the ground only
## falls (the air's drag), while the engine and the driven wheels rev free.
func _check_no_thrust(run: Dictionary) -> void:
	var snapshots: Array[Dictionary] = run.snapshots
	var ticks := 0
	var worst_rise := -INF
	var throttle_down := true
	var spin_up := 0.0
	for flight: Dictionary in run.flights:
		var launch: Dictionary = snapshots[flight.first]
		var last: Dictionary = snapshots[flight.last]
		spin_up = maxf(spin_up, (last.rear_wheel_speed - _ground_speed(last)) - (launch.rear_wheel_speed - _ground_speed(launch)))
		for k in range(flight.first, flight.last + 1):
			worst_rise = maxf(worst_rise, _ground_speed(snapshots[k]) - _ground_speed(snapshots[k - 1]))
			throttle_down = throttle_down and snapshots[k].throttle > 0.9
			ticks += 1
	_check(ticks > 0 and throttle_down and worst_rise < NO_THRUST_TOLERANCE,
		"no drive in the air: throttle down on every airborne tick, the speed over the ground never rises (worst step %+.6f m/s, drag only)" % worst_rise)
	_check(spin_up > 0.0, "the driven wheels rev free in the air: the rears outrun the ground by %.2f m/s more at touchdown than at launch" % spin_up)


## The touchdown: the wheels that find the road first carry well over their
## static share; then the car settles on its springs, on the flat, drivable.
func _check_landing(car: ArcadeCar, run: Dictionary) -> void:
	var snapshots: Array[Dictionary] = run.snapshots
	var least_ratio := INF
	var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
	for flight: Dictionary in run.flights:
		var ratio := 0.0
		# The touchdown tick and the ten after it: the spike as the springs
		# take the fall.
		for k in range(flight.touchdown, mini(flight.touchdown + 11, snapshots.size())):
			var snapshot: Dictionary = snapshots[k]
			var weight: float = snapshot.mass * gravity
			for i in 4:
				var share: float = weight * ((1.0 - ArcadeCar.REAR_WEIGHT_FRACTION) if i < 2 else ArcadeCar.REAR_WEIGHT_FRACTION) * 0.5
				ratio = maxf(ratio, snapshot.loads[i] / share)
		print("  flight %d landing: the hardest-hit wheel carries %.2f x its static share" % [flight.index, ratio])
		least_ratio = minf(least_ratio, ratio)
	_check(run.flights.size() > 0 and least_ratio > LANDING_SPIKE_MIN_RATIO,
		"the landing thud: every flight's touchdown spikes a wheel load past %.1f x its static share (least %.2f x)" % [LANDING_SPIKE_MIN_RATIO, least_ratio])
	var last: Dictionary = snapshots[snapshots.size() - 1]
	_check(not car.is_airborne and last.supported.all(func(s: bool) -> bool: return s) and last.loads.min() > 0.0 and car.forward_speed > 10.0
		and absf(last.pitch) < SETTLED_ANGLE and absf(last.roll) < SETTLED_ANGLE,
		"settled past the tail after %d ticks: on all four wheels, rolling on at %.1f m/s, the body within %.2f rad of level (pitch %.3f, roll %.3f)" % [
			SETTLE_AFTER_FRAMES, car.forward_speed, SETTLED_ANGLE, last.pitch, last.roll])


## Every tick of the run: every read state finite, no tick a teleport.
func _check_finite(run: Dictionary, name: String) -> void:
	var snapshots: Array[Dictionary] = run.snapshots
	var finite := true
	var worst_step := 0.0
	for k in snapshots.size():
		var s: Dictionary = snapshots[k]
		finite = finite and s.position.is_finite() and s.velocity.is_finite() and is_finite(s.pitch) and is_finite(s.roll) \
			and is_finite(s.yaw_rate) and is_finite(s.rpm) and is_finite(s.odometer) and is_finite(s.wheel_angle)
		for i in 4:
			finite = finite and is_finite(s.loads[i]) and is_finite(s.travel[i]) and is_finite(s.drawn[i])
		if k > 0:
			worst_step = maxf(worst_step, s.position.distance_to(snapshots[k - 1].position))
	_check(finite and worst_step < MAX_STEP_M,
		"%s: every state finite on all %d ticks, no tick moves the car more than %.1f m (worst %.3f m)" % [name, snapshots.size(), MAX_STEP_M, worst_step])


## The odometer counts the metres flown: the level way from tick to tick.
func _check_odometer(run: Dictionary) -> void:
	var snapshots: Array[Dictionary] = run.snapshots
	var counted := 0.0
	var flown := 0.0
	for flight: Dictionary in run.flights:
		for k in range(flight.first, flight.last + 1):
			var a: Vector3 = snapshots[k - 1].position
			var b: Vector3 = snapshots[k].position
			flown += Vector2(b.x - a.x, b.z - a.z).length()
			counted += snapshots[k].odometer - snapshots[k - 1].odometer
	_check(flown > 0.0 and absf(counted - flown) < ODOMETER_TOLERANCE,
		"the odometer counts the %.2f m flown (%.2f m on the odometer, within %.3f m)" % [flown, counted, ODOMETER_TOLERANCE])


## Steering held in the air turns the wheels and nothing else: no force
## across the car (the centre of mass keeps its sideways speed), no yaw put
## in (the yaw rate never grows in the air; launched with one, from the
## turn the wheels still held at the first touchdown, the stability assist
## damps it - the existing rule, "the nose swinging relative to the
## direction of travel" - and the heading drifts with what is left).
func _check_steering(run: Dictionary) -> void:
	var snapshots: Array[Dictionary] = run.snapshots
	var flights: Array = run.flights
	var worst_lateral := 0.0
	var yaw_grew := 0.0
	var first_heading := 0.0
	var wheels_turned := 0.0
	var launch_yaw := 0.0
	var landing_yaw := 0.0
	var ticks := 0
	for flight: Dictionary in flights:
		var first: int = flight.first
		var launch: Dictionary = snapshots[first]
		var lateral0 := _cg_velocity(launch).dot(launch.right)
		for k in range(first, int(flight.last) + 1):
			var s: Dictionary = snapshots[k]
			worst_lateral = maxf(worst_lateral, absf(_cg_velocity(s).dot(launch.right) - lateral0))
			var yaw_before: float = snapshots[k - 1].yaw_rate
			yaw_grew = maxf(yaw_grew, absf(s.yaw_rate) - absf(yaw_before))
			if flight.index == 1:
				first_heading = maxf(first_heading, absf(wrapf(s.heading - launch.heading, -PI, PI)))
			wheels_turned = maxf(wheels_turned, absf(s.wheel_angle))
			ticks += 1
		if flight.index == flights.size():
			launch_yaw = launch.yaw_rate
			landing_yaw = snapshots[int(flight.last)].yaw_rate
	_check(flights.size() >= 1 and ticks > 0, "the steered jump flies too: %d flight(s), %d ticks in the air" % [flights.size(), ticks])
	_check(ticks > 0 and wheels_turned > 0.0, "the wheels turn in the air (to %.1f degrees) - the steering moves them, nothing else" % rad_to_deg(wheels_turned))
	_check(ticks > 0 and worst_lateral < STEERING_LATERAL_TOLERANCE,
		"steering in the air does not bend the flight: the centre of mass keeps its sideways speed within %.3f m/s (worst %.6f; the air's drag along a drifting heading)" % [STEERING_LATERAL_TOLERANCE, worst_lateral])
	# was first_heading == 0.0, "stays exactly put" -> within
	# STRAIGHT_HEADING_TOLERANCE (the user's 20:35 retest; see the constant).
	_check(ticks > 0 and yaw_grew <= 0.0 and first_heading < STRAIGHT_HEADING_TOLERANCE,
		"steering in the air does not turn the car: the yaw rate never grows in the air, the heading of a straight launch stays put within %.5f rad (flight 1: %.7f rad, the shell's kiss on the ramp's knee); flight %d launched yawing at %.3f rad/s from the wheels held over the first touchdown, damped to %.3f by the stability assist" % [STRAIGHT_HEADING_TOLERANCE, first_heading, flights.size(), launch_yaw, landing_yaw])


## The centre of mass's velocity [m/s, world]: the car's own is its origin's,
## CG_OFFSET ahead of the centre of mass, which a yaw rate swings.
func _cg_velocity(snapshot: Dictionary) -> Vector3:
	var yaw_rate: float = snapshot.yaw_rate
	return snapshot.velocity + snapshot.right * (yaw_rate * ArcadeCar.CG_OFFSET)


## The tail hop (the user's 20:35 retest): the second flight of the reference
## run lands on the ramp's tail, and the landing goes through the wheels -
## the springs and their stops - not through the shell or the collision box.
## Measured at c5ee9c3 and unchanged: 3.4 m/s of sink, the fronts first (the
## body pitched -0.12 rad against the -0.08 slope), the rears four ticks
## later, no wheel deeper than 2.9 cm into its stop (the shell's underside 5
## cm in), nothing else touching; then the tail's foot, where the flat catches
## the body still descending along the slope, into all four stops at once,
## 6 x static on a rear - and still 2 cm clear of the shell.
func _check_tail_hop(run: Dictionary) -> void:
	var snapshots: Array[Dictionary] = run.snapshots
	var tail: Dictionary = {}
	for flight: Dictionary in run.flights:
		if flight.landing_z < RoadProfile.RAMP_TOP_END_Z and flight.landing_z > RoadProfile.RAMP_TAIL_Z:
			tail = flight
	_check(not tail.is_empty(), "the reference run's last flight lands on the ramp's tail (z %.1f, between %.0f and %.0f), %.2f m/s down" % [
		tail.get("landing_z", 0.0), RoadProfile.RAMP_TAIL_Z, RoadProfile.RAMP_TOP_END_Z, tail.get("landing_sink", 0.0)])
	if tail.is_empty():
		return
	# From the touchdown to 30 ticks past the tail's foot.
	var last := int(tail.touchdown)
	while last < snapshots.size() - 1 and snapshots[last].position.z > RoadProfile.RAMP_TAIL_Z:
		last += 1
	last = mini(last + 30, snapshots.size() - 1)
	var touchdown: Dictionary = snapshots[tail.touchdown]
	var fronts_first: bool = (touchdown.loads[0] > 0.0 or touchdown.loads[1] > 0.0) and touchdown.loads[2] == 0.0 and touchdown.loads[3] == 0.0
	var rears_at := -1
	var deepest := 0.0
	var shell_free := true
	var box_free := true
	var lowest := INF
	for k in range(tail.touchdown, last + 1):
		var s: Dictionary = snapshots[k]
		if rears_at < 0 and (s.loads[2] > 0.0 or s.loads[3] > 0.0):
			rears_at = k - int(tail.touchdown)
		deepest = maxf(deepest, s.travel.max())
		shell_free = shell_free and s.shell == 0.0
		box_free = box_free and not s.floor
		lowest = minf(lowest, s.y_over_road)
	_check(fronts_first and rears_at > 0,
		"the tail hop lands on the wheels that reach the slope first: the fronts (body pitch %.3f rad against the %.3f slope), the rears %d ticks later" % [touchdown.pitch, TAIL_SLOPE, rears_at])
	_check(shell_free and box_free and deepest < ArcadeCar.GROUND_CLEARANCE,
		"the tail landing goes through the springs and stops: the deepest any wheel goes is %.1f cm into its stop, %.1f cm short of the shell's underside; the shell and the collision box never touch from the touchdown to past the tail's foot (body lowest %.3f m under its ride height, at the foot, all four in their stops)" % [
			(deepest - ArcadeCar.SUSPENSION_TRAVEL) * 100.0, (ArcadeCar.GROUND_CLEARANCE - deepest) * 100.0, -lowest])


## The slope (the user's 20:35 retest): on the tail the body comes to lie
## along it - pitch within SLOPE_PITCH_TOLERANCE of TAIL_SLOPE by the tail's
## foot - on all four wheels, without a bounce and without a tumble; nothing
## makes it flat. What it measures: the nose comes down from 0.04 rad steeper
## than the slope at touchdown to a degree shallower than it by the foot, no
## roll to speak of, no airborne tick after the touchdown.
func _check_slope_landing(run: Dictionary) -> void:
	var snapshots: Array[Dictionary] = run.snapshots
	var tail: Dictionary = {}
	for flight: Dictionary in run.flights:
		if flight.landing_z < RoadProfile.RAMP_TOP_END_Z and flight.landing_z > RoadProfile.RAMP_TAIL_Z:
			tail = flight
	if tail.is_empty():
		_check(false, "the slope landing needs the tail hop")
		return
	var foot := int(tail.touchdown)
	while foot < snapshots.size() - 1 and snapshots[foot + 1].position.z > RoadProfile.RAMP_TAIL_Z:
		foot += 1
	var at_foot: Dictionary = snapshots[foot]
	var worst_pitch := 0.0
	var worst_roll := 0.0
	var bounced := 0
	for k in range(tail.touchdown, foot + 1):
		var s: Dictionary = snapshots[k]
		worst_pitch = maxf(worst_pitch, absf(s.pitch))
		worst_roll = maxf(worst_roll, absf(s.roll))
		if s.airborne:
			bounced += 1
	_check(absf(at_foot.pitch - TAIL_SLOPE) < SLOPE_PITCH_TOLERANCE and at_foot.supported.all(func(v: bool) -> bool: return v) and at_foot.loads.min() > 0.0,
		"on the tail the body lies along the slope: pitch %.3f rad at the foot against the slope's %.3f (within %.2f), on all four wheels, %d ticks after touching down %.3f rad nose-down" % [
			at_foot.pitch, TAIL_SLOPE, SLOPE_PITCH_TOLERANCE, foot - int(tail.touchdown), snapshots[tail.touchdown].pitch])
	_check(worst_pitch < NO_TUMBLE_ANGLE and worst_roll < SETTLED_ANGLE and bounced == 0,
		"and neither bounces nor tumbles there: pitch never past %.3f rad, roll never past %.3f, %d airborne ticks between the touchdown and the foot" % [worst_pitch, worst_roll, bounced])


## One flank run: from `run_up` m out along `heading_deg` (0 = the ramp's
## axis towards -z, 90 = across it towards -x) at z = FLANK_Z, flat out to
## the first launch, off the throttle after it, followed AFTER_LANDING_FRAMES
## past the first touchdown. `try_flip` calls flip_car() once on the way at
## speed, upright, and every tick the car is overturned and over
## FLIP_MAX_SPEED: refusals, every one of them, touching nothing.
func _flank(car: ArcadeCar, heading_deg: float, run_up: float, try_flip: bool) -> Dictionary:
	var heading := deg_to_rad(heading_deg)
	var forward := Vector3(-sin(heading), 0.0, -cos(heading))
	car.reset_to(Transform3D(Basis.IDENTITY.rotated(Vector3.UP, heading), Vector3(RoadProfile.RAMP_X, 0.0, FLANK_Z) - forward * run_up))
	await _step(SETTLE_FRAMES)
	var snapshots: Array[Dictionary] = []
	var launched := false
	var landed_at := -1
	var frame := 0
	var refused_at_speed := false
	var refusals_sliding := 0
	var flips_sliding := 0
	while frame < MAX_FLANK_FRAMES and (landed_at < 0 or frame < landed_at + AFTER_LANDING_FRAMES):
		car.set_driver_input(0.0 if launched else 1.0, 0.0, 0.0)
		await physics_frame
		frame += 1
		if car.is_airborne and not launched:
			launched = true
		if launched and landed_at < 0 and not car.is_airborne:
			landed_at = frame
		if try_flip:
			if not launched and not refused_at_speed and car.forward_speed > 20.0:
				refused_at_speed = not car.flip_car()
			if car.is_overturned() and Vector2(car.forward_speed, car.lateral_speed).length() > ArcadeCar.FLIP_MAX_SPEED:
				if car.flip_car():
					flips_sliding += 1
				else:
					refusals_sliding += 1
		snapshots.append(_snapshot(car, frame))
	car.set_driver_input(0.0, 0.0, 0.0)
	return {"snapshots": snapshots, "flights": _flights(snapshots), "landed": landed_at > 0,
		"refused_at_speed": refused_at_speed, "refusals_sliding": refusals_sliding, "flips_sliding": flips_sliding}


## The user's jump, honest (the 20:35 retest): the car leaves the flank's
## crest, its attitude leaves the small angles in the air and the flight
## itself is clean (the pitch rate constant, nothing touching), it comes down
## on its shell, and what happens then is what the numbers give - bounded (no
## wheel past WHEEL_LOAD_BOUND, never flung up faster than it left), on the
## wheels or overturned as it falls, the collision box never the ground. What
## it measures, and states: 0.42 rad nose-up at launch pitching down at 0.72
## rad/s, 5.1 m of apex, nose-first on to the road 1.7 s later at 8.5 m/s of
## sink, 0.74 rad down, 169 kN on the two nose corners (~0.4 m into the road
## at SHELL_RATE, back out again: the shell yields like a spring), which
## pole-vaults it (pitch rate -0.7 to +1.8 rad/s) on to its rear wheels 0.6
## s later at 3 m/s; on all four and rolling on. At c5ee9c3: 10.3 m/s of
## launch (no shell to scrape), 7 m of apex, 1.21 rad nose-up, a seat 1.2 m
## under the body, 266 kN on one wheel, three flights, pulled flat by the
## springs - the cat.
func _check_flank_jump(car: ArcadeCar, run: Dictionary) -> void:
	var snapshots: Array[Dictionary] = run.snapshots
	var flights: Array = run.flights
	var launch_x: float = snapshots[flights[0].first].position.x if flights.size() > 0 else 0.0
	# The car comes from +x: up the east flank, which tops out at RAMP_X +
	# RAMP_HALF_WIDTH, and leaves the ground there or just past it, on the top.
	var crest := RoadProfile.RAMP_X + RoadProfile.RAMP_HALF_WIDTH
	_check(run.landed and flights.size() >= 1 and launch_x < crest + 1.0 and launch_x > RoadProfile.RAMP_X - RoadProfile.RAMP_HALF_WIDTH,
		"the car leaves the ground off the flank's crest: %d flight(s) by the wheels, the first launched at x = %.1f (the flank tops out at %.0f), %.2f m/s up at %.1f m/s over the ground" % [
			flights.size(), launch_x, crest, snapshots[flights[0].first].velocity.y if flights.size() > 0 else 0.0, flights[0].launch_speed if flights.size() > 0 else 0.0])
	if flights.is_empty():
		return
	var first: Dictionary = flights[0]
	var launch: Dictionary = snapshots[first.first]
	# The flight proper: from the launch to the first thing that touches the
	# road, a shell corner or a wheel.
	var contact := int(first.touchdown)
	for k in range(first.first + 1, int(first.touchdown) + 1):
		if snapshots[k].shell > 0.0:
			contact = k
			break
	# The tail corners may still drag off the crest for a few ticks after the
	# wheels have left; the clean flight is from the last of that.
	var clean_from := int(first.first)
	for k in range(first.first, contact):
		if snapshots[k].shell > 0.0:
			clean_from = k + 1
	var apex := 0.0
	var steepest := 0.0
	var steepest_at := clean_from
	var rate_drift := 0.0
	for k in range(clean_from, contact):
		var s: Dictionary = snapshots[k]
		apex = maxf(apex, s.y_over_road)
		rate_drift = maxf(rate_drift, absf(s.pitch_rate - snapshots[clean_from].pitch_rate))
		if absf(s.pitch) > steepest:
			steepest = absf(s.pitch)
			steepest_at = k
	var down: Dictionary = snapshots[contact]
	_check(steepest > ArcadeCar.ATTITUDE_BLEND_END and rate_drift < 0.02 and contact - clean_from > 60,
		"in the air the body's attitude leaves the small angles and the flight is clean: launched %.2f rad nose-up pitching at %.2f rad/s, the rate held within %.3f rad/s over %d ticks with nothing touching, %.1f m of apex, %.2f rad at the steepest" % [
			launch.pitch, launch.pitch_rate, rate_drift, contact - clean_from, apex, steepest])
	# The wheels go round with the body: at the steepest, each wheel's up is
	# the body's, drawn, not the world's.
	var carried := true
	var body_up: Vector3 = snapshots[steepest_at].body_up
	for up: Vector3 in snapshots[steepest_at].wheel_ups:
		carried = carried and up.distance_to(body_up) < 0.000001
	_check(carried and body_up.distance_to(Vector3.UP) > 0.1,
		"the wheels are drawn going round with the body: at %.2f rad every wheel's axle tilts with the body's up (%.3f, %.3f, %.3f), none hangs on the vertical" % [snapshots[steepest_at].pitch, body_up.x, body_up.y, body_up.z])
	# What it comes down on, and everything after it.
	var nose_first: bool = down.shell > 0.0 and down.loads.max() == 0.0
	var corner_peak := 0.0
	var shell_peak := 0.0
	var wheel_peak := 0.0
	var flung := -INF
	var box := false
	var rate_after: float = down.pitch_rate
	var plant_peak := 0.0
	var plant_corner := 0.0
	for k in range(contact, snapshots.size()):
		var s: Dictionary = snapshots[k]
		shell_peak = maxf(shell_peak, s.shell)
		corner_peak = maxf(corner_peak, s.shell_loads.max())
		if k <= contact + 20:
			plant_peak = maxf(plant_peak, s.shell)
			plant_corner = maxf(plant_corner, s.shell_loads.max())
		wheel_peak = maxf(wheel_peak, s.loads.max())
		box = box or s.floor
		if k > contact:
			flung = maxf(flung, s.velocity.y)
		if k <= contact + 20:
			rate_after = maxf(rate_after, s.pitch_rate)
	_check(nose_first and rate_after > 0.0,
		"it comes down nose-first on its shell, no wheel in reach: %.2f rad down at %.2f m/s of sink, the two nose corners carrying %.0f kN at the most (%.0f on one: at least %.2f m into the road at its rate, and back out), which pole-vaults it - pitch rate %.2f to %+.2f rad/s - on to its rear wheels %.2f s later at %.2f m/s" % [
			down.pitch, -snapshots[contact - 1].velocity.y, plant_peak / 1000.0, plant_corner / 1000.0, plant_corner / ArcadeCar.SHELL_RATE, snapshots[contact - 1].pitch_rate, rate_after, (int(first.touchdown) - contact) / 60.0, first.landing_sink])
	_check(wheel_peak < WHEEL_LOAD_BOUND and flung < launch.velocity.y and not box,
		"and nothing catapults it: no wheel carries more than %.0f kN (%.0f measured; 266 at c5ee9c3), the shell at most %.0f kN, after the nose is down the body never rises faster than %.2f m/s (it left the ramp at %.2f), the collision box never meets the ground, %d flight(s) by the wheels in all" % [
			WHEEL_LOAD_BOUND / 1000.0, wheel_peak / 1000.0, shell_peak / 1000.0, flung, launch.velocity.y, flights.size()])
	var last: Dictionary = snapshots[snapshots.size() - 1]
	var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
	var on_wheels: bool = not last.overturned and last.supported.all(func(v: bool) -> bool: return v) and last.loads.min() > 0.0 and absf(last.pitch) < SETTLED_ANGLE and absf(last.roll) < SETTLED_ANGLE
	var on_shell: bool = last.overturned and last.ground_speed < 0.01 and absf(last.shell - last.mass * gravity) < REST_LOAD_TOLERANCE * last.mass * gravity
	_check(on_wheels or on_shell,
		"%d ticks after the wheels are down the car is %s, by the numbers and not by a rule: pitch %.3f, roll %.3f, %.1f m/s, up %.3f of the world's" % [
			AFTER_LANDING_FRAMES, "on all four wheels, rolling on" if on_wheels else ("overturned at rest on its shell" if on_shell else "neither at rest on its wheels nor on its shell"), last.pitch, last.roll, last.ground_speed, last.up])
	_check(run.refused_at_speed, "the flip is refused on an upright car at speed: flip_car() false on the run-up")


## Two runs from the same state are the same run to the bit: every tick's
## position, velocity, pitch, roll, heading, wheel loads and shell load.
func _check_same(a: Dictionary, b: Dictionary, name: String) -> void:
	var sa: Array[Dictionary] = a.snapshots
	var sb: Array[Dictionary] = b.snapshots
	var same := sa.size() == sb.size()
	var first_off := -1
	for k in mini(sa.size(), sb.size()):
		var x: Dictionary = sa[k]
		var y: Dictionary = sb[k]
		if x.position != y.position or x.velocity != y.velocity or x.pitch != y.pitch or x.roll != y.roll or x.heading != y.heading or x.loads != y.loads or x.shell != y.shell:
			same = false
			first_off = k
			break
	_check(same, "%s: %d ticks, identical to the bit (first tick off: %d)" % [name, sa.size(), first_off])


## The rollover (the user's 20:35 retest, the no-cat world): the diagonal
## crossing puts the car down on the wheels of one side, rolled past its
## tipping angle; it goes over, on to the shell, past 90 degrees, comes to
## rest on its side and stays there - overturned, its weight on the shell, no
## wheel on the road, nothing pulling it flat. What it measures: down 0.98 rad
## of roll on the left wheels at 7.2 m/s of sink, rolled to 2.18 rad (125
## degrees) at the furthest, at rest on its side at 1.56 rad; the flip refused
## every tick of the slide.
# was 212 refusals of the flip on the slide and the car at rest at x -94.87,
# z 8.73 -> 266 and x -106.08, z -0.84: on its side the car is slowed at
# ROLL_FRICTION_COEFF x g now, not by SHELL_FRICTION x the tick's shell load,
# and slides 15 m further before it rests (the user's 3AF catch: "like the
# car hit a wall"). The roll itself is the same to 0.003 rad.
func _check_rollover(car: ArcadeCar, run: Dictionary) -> void:
	var snapshots: Array[Dictionary] = run.snapshots
	var flights: Array = run.flights
	var furthest := 0.0
	var lowest_up := 1.0
	var wheel_peak := 0.0
	var box := false
	var overturned_ticks := 0
	for s: Dictionary in snapshots:
		furthest = maxf(furthest, absf(s.roll))
		lowest_up = minf(lowest_up, s.up)
		wheel_peak = maxf(wheel_peak, s.loads.max())
		box = box or s.floor
		if s.overturned:
			overturned_ticks += 1
	var touchdown: Dictionary = snapshots[flights[0].touchdown] if flights.size() > 0 else snapshots[0]
	_check(flights.size() >= 1 and absf(touchdown.roll) > 0.5,
		"crossed at %.0f degrees the car comes down rolled %.2f rad on the wheels of one side, %.2f m/s of sink" % [ROLLOVER_HEADING_DEG, touchdown.roll, flights[0].landing_sink if flights.size() > 0 else 0.0])
	_check(lowest_up < ArcadeCar.OVERTURN_COS and overturned_ticks > 0 and wheel_peak < WHEEL_LOAD_BOUND and not box,
		"and goes over: rolled to %.2f rad at the furthest (up %.3f of the world's), overturned on %d ticks, no wheel past %.0f kN, the collision box never the ground" % [furthest, lowest_up, overturned_ticks, wheel_peak / 1000.0])
	var last: Dictionary = snapshots[snapshots.size() - 1]
	var weight: float = last.mass * ProjectSettings.get_setting("physics/3d/default_gravity")
	_check(last.overturned and last.ground_speed < 0.01 and absf(absf(last.roll) - PI * 0.5) < SETTLED_ANGLE and absf(last.shell - weight) < REST_LOAD_TOLERANCE * weight and last.loads.max() == 0.0 and last.airborne,
		"and rests on its side: roll %.3f rad at %.3f m/s, the shell carrying %.0f N of the car's %.0f, no wheel on the road (airborne to the drive: %s), overturned" % [last.roll, last.ground_speed, last.shell, weight, last.airborne])
	_check(run.refusals_sliding > 0 and run.flips_sliding == 0,
		"the flip is refused while it slides: %d refusals over %.1f m/s, not one flip" % [run.refusals_sliding, ArcadeCar.FLIP_MAX_SPEED])


## The flip (the user's 20:55 thought): the car at rest on its side from the
## rollover is righted where it lies - on its wheels at ride height, loads
## static, heading and place kept, at rest - and nothing else moves: fuel,
## wear, heat, battery, gear, odometer as they were to the bit. Then, upright,
## it is refused again.
func _check_flip(car: ArcadeCar) -> void:
	var kept := _capture(car)
	kept["gear"] = car.gear
	kept["automatic"] = car.automatic
	kept["engine_running"] = car.engine_running
	var place := car.global_position
	var heading := car.global_rotation.y
	var could := car.can_flip()
	var flipped := car.flip_car()
	var weight := car.total_mass() * car._gravity
	var static_loads := true
	for i in 4:
		var share := weight * ((1.0 - ArcadeCar.REAR_WEIGHT_FRACTION) if i < 2 else ArcadeCar.REAR_WEIGHT_FRACTION) * 0.5
		static_loads = static_loads and absf(car.wheel_loads[i] - share) < REST_LOAD_TOLERANCE * share
	_check(could and flipped and absf(car.body_roll) < 0.01 and absf(car.body_pitch) < 0.01 and static_loads and not car.is_airborne and car.shell_load == 0.0 and car.velocity == Vector3.ZERO and car.forward_speed == 0.0 and car.yaw_rate == 0.0 and car.pitch_rate == 0.0 and car.roll_rate == 0.0,
		"the flip rights the overturned car at rest: flip_car() true, on its wheels (roll %.4f, pitch %.4f rad), every wheel at its static share, at rest" % [car.body_roll, car.body_pitch])
	_check(car.global_position.x == place.x and car.global_position.z == place.z and car.global_rotation.y == heading,
		"where it lay, heading as it was (x %.2f, z %.2f, %.3f rad)" % [place.x, place.z, heading])
	var untouched := true
	var moved: Array[String] = []
	for key: String in kept:
		if car.get(key) != kept[key]:
			untouched = false
			moved.append(key)
	_check(untouched, "and nothing else: fuel, wear, heat, battery, odometer, gear all as they were to the bit (moved: %s)" % [", ".join(moved) if not moved.is_empty() else "nothing"])
	await _step(SETTLE_FRAMES)
	_check(not car.is_airborne and absf(car.body_roll) < 0.01 and car.wheel_loads.min() > 0.0 and not car.is_overturned() and not car.flip_car(),
		"%d ticks on it stands on its four wheels, and the flip is refused again, upright" % SETTLE_FRAMES)


## Let go leaning, the car's own tipping angle and the roof: at 0.9 rad of
## roll (52 degrees, under atan(HALF_TRACK / CG_HEIGHT) = 60.8) it comes back
## on to its wheels; at 1.2 rad (69 degrees) it goes on over and rests on its
## side; on its roof it stays on its roof, its weight on the shell, and the
## flip rights it. Every drop from DROP_HEIGHT over the road, at rest.
func _check_drops(car: ArcadeCar) -> void:
	for roll0: float in [0.9, 1.2, PI]:
		await _let_go(car, roll0)
		var weight := car.total_mass() * car._gravity
		var up := cos(car.body_pitch) * cos(car.body_roll)
		var at_rest := absf(car.roll_rate) < 0.001 and absf(car.velocity.y) < 0.001
		if roll0 == 0.9:
			_check(up > 0.99 and not car.is_overturned() and car.wheel_loads.min() > 0.0 and car.shell_load == 0.0 and at_rest,
				"let go at %.1f rad of roll (%.0f degrees, under its tipping angle) the car comes back on to its wheels: roll %.3f, all four loaded, the shell clear" % [roll0, rad_to_deg(roll0), car.body_roll])
		elif roll0 == 1.2:
			_check(car.is_overturned() and absf(car.body_roll - PI * 0.5) < SETTLED_ANGLE and absf(car.shell_load - weight) < REST_LOAD_TOLERANCE * weight and car.wheel_loads.max() == 0.0 and at_rest,
				"let go at %.1f rad (%.0f degrees, past it) it goes on over and rests on its side: roll %.3f, the shell carrying %.0f of %.0f N, no wheel on the road" % [roll0, rad_to_deg(roll0), car.body_roll, car.shell_load, weight])
		else:
			_check(car.is_overturned() and absf(absf(car.body_roll) - PI) < 0.01 and absf(car.shell_load - weight) < REST_LOAD_TOLERANCE * weight and car.wheel_loads.max() == 0.0 and at_rest,
				"on its roof it stays on its roof: roll %.3f rad, the shell carrying %.0f of %.0f N, overturned" % [car.body_roll, car.shell_load, weight])
			var flipped := car.flip_car()
			_check(flipped and absf(car.body_roll) < 0.01 and not car.is_overturned() and car.wheel_loads.min() > 0.0,
				"and the flip rights it off its roof: roll %.4f rad, on its wheels" % car.body_roll)


## Lets the car go at its spawn rolled `roll0` rad, at rest, its lowest shell
## corner DROP_HEIGHT over the road, and gives it DROP_FRAMES to settle.
func _let_go(car: ArcadeCar, roll0: float) -> void:
	car.reset_to_spawn()
	await _step(5)
	car.body_roll = roll0
	car.body_pitch = 0.0
	car.roll_rate = 0.0
	car.pitch_rate = 0.0
	var lowest := INF
	for j in 8:
		lowest = minf(lowest, (car._body_basis() * car._shell_corner(j)).y)
	car.global_position.y = car.road_profile.sample_height(car.global_position.x, car.global_position.z) - ArcadeCar.CG_HEIGHT - lowest + DROP_HEIGHT
	car.velocity = Vector3.ZERO
	await _step(DROP_FRAMES)


## The wheels' and the body's places in the car's scene, as car.tscn has them
## (the scene instantiated and never entered: nothing drawn over them): the
## four wheel nodes' positions in the order of wheel_loads, then the body's.
func _scene_layout() -> Array[Vector3]:
	var scene: Node = (load(CAR_SCENE) as PackedScene).instantiate()
	var layout: Array[Vector3] = []
	for name in ["FrontLeft", "FrontRight", "RearLeft", "RearRight"]:
		layout.append((scene.get_node("Wheels/" + name) as Node3D).position)
	layout.append((scene.get_node("Body") as Node3D).position)
	scene.free()
	return layout


## Whether every wheel node and the body node are drawn at the scene's place
## across and along the car (x and z to the bit; the heights are the springs').
func _drawn_at_layout(car: ArcadeCar) -> bool:
	var layout := _scene_layout()
	var at := true
	for i in 4:
		at = at and car._wheels[i].position.x == layout[i].x and car._wheels[i].position.z == layout[i].z
	return at and car._body.position.x == layout[4].x and car._body.position.z == layout[4].z


## The wheels' drawn places across and along the car, for the check texts:
## "FL x -0.86 z -1.30, ...".
func _layout_text(car: ArcadeCar) -> String:
	var names := ["FL", "FR", "RL", "RR"]
	var parts: Array[String] = []
	for i in 4:
		parts.append("%s x %.2f z %.2f" % [names[i], car._wheels[i].position.x, car._wheels[i].position.z])
	return ", ".join(parts)


## Whether every wheel is drawn on the road at ride height, level: drawn
## travel 0, its bottom (WHEEL_RADIUS under its centre) on the road under it
## within DRAWN_ON_ROAD_TOLERANCE, its axle level.
func _drawn_on_road(car: ArcadeCar) -> bool:
	var on := true
	for i in 4:
		var bottom: float = car.global_position.y + car._wheels[i].position.y - ArcadeCar.WHEEL_RADIUS
		on = on and absf(_drawn_travel(car, i)) < DRAWN_ON_ROAD_TOLERANCE \
			and absf(bottom - car._road_height_under_wheel(i)) < DRAWN_ON_ROAD_TOLERANCE \
			and car._wheels[i].basis.y == Vector3.UP
	return on


## The flip's and the reset's picture (the user's two catches on the flip,
## 3AE): righted off its side, the car had "no tires anymore (visually), only
## tire marks" - the four wheel nodes drawn at x = 0.22, the body's centre
## line, buried in it; righted off its roof "the wheels are reversed" - each
## drawn at the other side's x. The state was right both times
## (_settle_suspension); the level picture wrote the wheels' heights alone
## and left their places across and along the car where the carried picture
## had put them. Now the level picture draws the whole transform: after the
## flip, and after a reset off the side or the roof, all four wheels are on
## the road at ride height at their own corners, the scene's layout to the
## bit, the body on the centre line - the tick of the flip and every tick
## after.
func _check_flip_draws(car: ArcadeCar) -> void:
	for roll0: float in [1.2, PI]:
		var lying := "its side" if roll0 == 1.2 else "its roof"
		for way in ["flip", "reset"]:
			await _let_go(car, roll0)
			var before := _layout_text(car)
			var was_overturned := car.is_overturned()
			var done: bool
			if way == "flip":
				done = car.flip_car()
			else:
				car.reset_to(Transform3D(Basis.IDENTITY, Vector3(5.0, 0.0, 10.0)))
				done = true
			var drawn_now := _drawn_at_layout(car) and _drawn_on_road(car)
			await _step(1)
			var drawn_after := _drawn_at_layout(car) and _drawn_on_road(car)
			await _step(SETTLE_FRAMES)
			var drawn_settled := _drawn_at_layout(car) and _drawn_on_road(car)
			_check(was_overturned and done and drawn_now and drawn_after and drawn_settled and not car.is_overturned(),
				"%s off %s (roll %.2f): all four wheels drawn on the road at ride height at their own corners, the scene's layout to the bit (%s), the body on the centre line - the tick of the %s, the tick after and %d ticks on; was %s (the user's flip catches: \"did not have tires anymore (visually), only tire marks\" off its side, \"the wheels are reversed\" off its roof)" % [
					"the flip" if way == "flip" else "the reset", lying, roll0, _layout_text(car), way, SETTLE_FRAMES, before])


## The user's handbrake roll (see ROLL_Z): flat out along the hill's lateral,
## and from ROLL_PULL_X the throttle off, the handbrake on and the wheel hard
## right, held to rest. Returns the snapshots of every tick from the pull,
## the tick and speed of the pull and whether the car came to rest.
func _handbrake_roll(car: ArcadeCar) -> Dictionary:
	var heading := deg_to_rad(-90.0)
	var forward := Vector3(-sin(heading), 0.0, -cos(heading))
	car.reset_to(Transform3D(Basis.IDENTITY.rotated(Vector3.UP, heading), Vector3(RoadProfile.RAMP_X, 0.0, ROLL_Z) - forward * ROLL_RUN_UP))
	await _step(SETTLE_FRAMES)
	var snapshots: Array[Dictionary] = []
	var pulled := false
	var pull_speed := 0.0
	var frame := 0
	var rest := 0
	while frame < ROLL_MAX_FRAMES and rest < ROLL_REST_FRAMES:
		if not pulled and car.global_position.x >= ROLL_PULL_X:
			pulled = true
			pull_speed = car.forward_speed
		car.set_driver_input(0.0 if pulled else 1.0, 0.0, ROLL_STEER if pulled else 0.0, pulled)
		await physics_frame
		frame += 1
		if not pulled:
			continue
		var snapshot := _snapshot(car, frame)
		snapshots.append(snapshot)
		if snapshot.ground_speed < ROLL_REST_SPEED and absf(snapshot.roll_rate) < ROLL_REST_SPEED:
			rest += 1
		else:
			rest = 0
	car.set_driver_input(0.0, 0.0, 0.0)
	return {"snapshots": snapshots, "flights": _flights(snapshots), "pull_speed": pull_speed, "rested": rest >= ROLL_REST_FRAMES}


## The handbrake roll (the user's 3AF catch: "i've handbreaked while at speed
## claiming the lateral of the hill, naturally rolled over, but at some point
## we only rolled the car around its axis without letting the lateral force
## also move the car in the direction of the fall, like the car hit a wall
## and was rolling against that wall"). The car goes over - that is the
## physics and stays - and while it is overturned the road's friction slows
## its centre of mass at ROLL_FRICTION_COEFF x g at the most, the air's drag
## on top: no tick takes more than that off it, the tumble keeps its momentum
## and scrapes on, the roll turning about a contact that moves with it. From
## the first overturned tick to the last nothing but the shell and the air
## touch it (no wheel on the road), so the way it makes over that stretch is
## at least what a body entering at v0 and slowed at the cap the whole way
## makes: sum over the N ticks of (v0 - a k dt) dt, a = ROLL_FRICTION_COEFF x
## g + the air's drag at v0 over the mass. How it ends - on its wheels, its
## side or its roof - is the numbers' call. At 74aaef5 the same run took
## 1.15 m/s off the centre of mass in one tick (7 g: SHELL_FRICTION x 190 kN
## of shell) and the car went over its nose a full turn on to its roof; in
## the user's session it spun about its axis where it lay.
func _check_handbrake_roll(run: Dictionary) -> void:
	var snapshots: Array[Dictionary] = run.snapshots
	var delta := 1.0 / Engine.physics_ticks_per_second
	var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
	var first_over := -1
	var last_over := -1
	var over_ticks := 0
	var lowest_up := 1.0
	var furthest := 0.0
	var fastest_roll := 0.0
	var box := false
	for k in snapshots.size():
		var s: Dictionary = snapshots[k]
		lowest_up = minf(lowest_up, s.up)
		furthest = maxf(furthest, absf(s.roll))
		fastest_roll = maxf(fastest_roll, absf(s.roll_rate))
		box = box or s.floor
		if s.overturned:
			over_ticks += 1
			last_over = k
			if first_over < 0:
				first_over = k
	_check(run.pull_speed > 28.0 and first_over > 0 and lowest_up < ArcadeCar.OVERTURN_COS and run.rested and not box,
		"handbraked at %.1f m/s on the hill's lateral, the wheel hard right, the car goes over: up %.3f of the world's at the lowest, %.2f rad of roll at the furthest, overturned on %d ticks, rolling at %.2f rad/s at the fastest, at rest after %d ticks, the collision box never the ground" % [
			run.pull_speed, lowest_up, furthest, over_ticks, fastest_roll, snapshots.size()])
	if first_over <= 0:
		return
	# Tick by tick while overturned (the tick's friction is the shell's when
	# the car was overturned going in and is coming out): the centre of
	# mass's speed over the ground falls by no more than the cap plus the
	# air's drag.
	var worst_drop := -INF
	var worst_bound := 0.0
	var capped_ticks := 0
	for k in range(first_over, last_over + 1):
		var before: Dictionary = snapshots[k - 1]
		var now: Dictionary = snapshots[k]
		if not (before.overturned and now.overturned):
			continue
		capped_ticks += 1
		var speed_before := _cg_ground_speed(before)
		var forward_speed: float = before.velocity.dot(before.forward)
		var air_drag: float = 0.5 * ArcadeCar.AIR_DENSITY * ArcadeCar.DRAG_COEFF * ArcadeCar.FRONTAL_AREA * forward_speed * forward_speed
		var bound: float = (ArcadeCar.ROLL_FRICTION_COEFF * gravity + air_drag / now.mass) * delta
		var drop := speed_before - _cg_ground_speed(now)
		if drop - bound > worst_drop - worst_bound:
			worst_drop = drop
			worst_bound = bound
	_check(capped_ticks > 0 and worst_drop < worst_bound + ROLL_CAP_SLACK,
		"the contact is no wall: on %d overturned ticks no tick takes more than ROLL_FRICTION_COEFF x g + drag off the centre of mass's speed over the ground (worst %.4f m/s a tick against %.4f + %.3f of slack; %.2f x g; 1.15 m/s, 7 g, at 74aaef5)" % [
			capped_ticks, worst_drop, worst_bound, ROLL_CAP_SLACK, worst_drop / delta / gravity])
	# From the first overturned tick to the last: shell or air, no wheel.
	var wheel_free := true
	var travel := 0.0
	for k in range(first_over + 1, last_over + 1):
		wheel_free = wheel_free and snapshots[k].loads.max() == 0.0
		var a: Vector3 = snapshots[k - 1].position
		var b: Vector3 = snapshots[k].position
		travel += Vector2(b.x - a.x, b.z - a.z).length()
	var entry_speed := _cg_ground_speed(snapshots[first_over])
	var entry_forward: float = snapshots[first_over].velocity.dot(snapshots[first_over].forward)
	var entry_drag: float = 0.5 * ArcadeCar.AIR_DENSITY * ArcadeCar.DRAG_COEFF * ArcadeCar.FRONTAL_AREA * entry_forward * entry_forward
	var slowing: float = ArcadeCar.ROLL_FRICTION_COEFF * gravity + entry_drag / snapshots[first_over].mass
	var floor := 0.0
	for k in range(1, last_over - first_over + 1):
		floor += maxf(entry_speed - slowing * k * delta, 0.0) * delta
	var last: Dictionary = snapshots[snapshots.size() - 1]
	var to_rest := Vector2(last.position.x - snapshots[first_over].position.x, last.position.z - snapshots[first_over].position.z).length()
	_check(wheel_free and travel > floor and to_rest > floor,
		"and the tumble keeps its momentum: overturned at %.2f m/s, no wheel on the road from the first overturned tick to the last (%d ticks), the centre of mass makes %.2f m over them - at least the %.2f m of a body slowed at ROLL_FRICTION_COEFF x g + drag = %.2f m/s^2 the whole way, sum of (v0 - a k dt) dt - and %.2f m to rest" % [
			entry_speed, last_over - first_over, travel, floor, slowing, to_rest])
	var on_wheels: bool = not last.overturned and last.supported.all(func(v: bool) -> bool: return v) and last.loads.min() > 0.0 and absf(last.pitch) < SETTLED_ANGLE and absf(last.roll) < SETTLED_ANGLE
	var on_shell: bool = last.overturned and absf(last.shell - last.mass * gravity) < REST_LOAD_TOLERANCE * last.mass * gravity
	_check(on_wheels or on_shell,
		"and comes to rest %s, by the numbers and not by a rule: pitch %.3f, roll %.3f, up %.3f of the world's, %.1f m from the pull" % [
			"on all four wheels" if on_wheels else ("overturned on its shell" if on_shell else "neither on its wheels nor on its shell"), last.pitch, last.roll, last.up,
			Vector2(last.position.x - snapshots[0].position.x, last.position.z - snapshots[0].position.z).length()])


## The centre of mass's speed over the ground [m/s] (see _cg_velocity).
func _cg_ground_speed(snapshot: Dictionary) -> float:
	var v := _cg_velocity(snapshot)
	return Vector2(v.x, v.z).length()


## The state the flank runs carry over (CARRIED_STATE), read and put back.
func _capture(car: ArcadeCar) -> Dictionary:
	var state := {}
	for key in CARRIED_STATE:
		state[key] = car.get(key)
	return state


func _restore(car: ArcadeCar, state: Dictionary) -> void:
	for key: String in state:
		car.set(key, state[key])


func _step(frames: int) -> void:
	for i in frames:
		await physics_frame


func _check(condition: bool, description: String) -> bool:
	if condition:
		print("  ok    ", description)
	else:
		_failures += 1
		printerr("  FAIL  ", description)
	return condition


func _finish() -> void:
	if _failures == 0:
		print("AIRBORNE TEST PASSED")
	else:
		print("AIRBORNE TEST FAILED: %d check(s) failed" % _failures)
	quit(1 if _failures > 0 else 0)
