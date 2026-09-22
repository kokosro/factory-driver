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

	# The second jump: the steering held hard left the moment the car is in
	# the air, let go the tick it touches down.
	var steered: Dictionary = await _jump(car, 1.0)
	_check_steering(steered)
	_check_finite(steered, "steering held in the air")

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
	for i in 4:
		# The same expression _update_visuals places the wheel with, solved
		# for the drawn travel: the wheel's offset from its seat under the body.
		drawn.append(car._wheels[i].position.y - (car._wheel_rest_height + car._corner_height(i) + car._corner_trim[i] - car.global_position.y))
	return {
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
	_check(ticks > 0 and yaw_grew <= 0.0 and first_heading == 0.0,
		"steering in the air does not turn the car: the yaw rate never grows in the air, the heading of a straight launch stays exactly put (flight 1: 0 rad); flight %d launched yawing at %.3f rad/s from the wheels held over the first touchdown, damped to %.3f by the stability assist" % [flights.size(), launch_yaw, landing_yaw])


## The centre of mass's velocity [m/s, world]: the car's own is its origin's,
## CG_OFFSET ahead of the centre of mass, which a yaw rate swings.
func _cg_velocity(snapshot: Dictionary) -> Vector3:
	var yaw_rate: float = snapshot.yaw_rate
	return snapshot.velocity + snapshot.right * (yaw_rate * ArcadeCar.CG_OFFSET)


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
