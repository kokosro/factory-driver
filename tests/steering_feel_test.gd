extends SceneTree
## Headless steering-feel test. Run via tests/run_tests.sh, or:
##
##   godot --headless --path . --import
##   godot --headless --fixed-fps 60 --path . --script res://tests/steering_feel_test.gd
##
## What sits between the driver's hands and the front wheels besides the rack
## ratio (ArcadeCar, Steering): the power assist (the hands wind lock on at
## their full speed up to STEERING_ASSIST_FULL_SPEED and at
## STEERING_ASSIST_HIGHWAY of it on the motorway, whoever the driver is), the
## rack's play at centre (STEERING_PLAY_DEG: the hands' motion about dead
## centre adds up in the play and moves nothing until it is through it, a
## held key is through it on its first tick), and the bushings' compliance
## (the front wheels trail the rack by a lag that grows with the front
## tyres' sideways load, and stand on it exactly once close: the steady
## corner is the rigid rack's, the turn-in is softer). The certified
## handling runs and the smoke test's raw-steering identity are checked
## where they are; this is the feel itself, measured.
## Exits 0 on success, 1 on any failed check.

const MAIN_SCENE := "res://scenes/main.tscn"

## Speeds the assist reads exactly 1.0 at [m/s]: a standstill, the two
## raw-steer check speeds (tests/smoke_test.gd RAW_STEER_SPEEDS) and the
## knee itself, and the share it reads between the knee and the motorway,
## with what it must read there (lerp over smoothstep, worked out by hand:
## at 25 m/s t = 0.35, 0.28175 of the way, 0.8873; at 35 t = 0.85,
## 0.93925 of the way, 0.6243).
const ASSIST_FULL_SPEEDS: Array[float] = [0.0, 8.5, 16.7, 18.0]
const ASSIST_AT_25 := 0.8873
const ASSIST_AT_35 := 0.6243
const ASSIST_TOLERANCE := 0.001

## Centre to lock for the test driver's hands [physics ticks]: parking, the
## full 1300 degrees a second on the 450 (0.35 s, 20.8 -> 21 ticks) ...
const PARKING_TICKS_TO_LOCK := 21

## ... and on the motorway, 0.6 of it (0.58 s, 34.6 -> 35 ticks; the car
## coasts down from HIGHWAY_SPEED through the check, so the assist creeps up
## a little as it goes). Measured: 35 at 38.0 m/s.
const HIGHWAY_SPEED := 38.0
const HIGHWAY_MIN_TICKS_TO_LOCK := 33
const HIGHWAY_MAX_TICKS_TO_LOCK := 38

## The chauffeur's hands (DRIVER_PROFILES, 650 degrees a second) on the
## motorway: the assist multiplies the driver's own hand speed, so twice the
## test driver's ticks (69.2 -> 70), give or take the coast-down.
const CHAUFFEUR_TICKS_TOLERANCE := 3

## The rack's play (ArcadeCar.STEERING_PLAY_DEG 0.75): a steer input asking
## 0.18 degrees a tick (0.0004 of lock) is 0.72 in the play after four ticks
## and through it (0.90) on the fifth; a 0.45-degree tap (0.001 of lock),
## one tick on, one tick back, moves nothing ever.
const SUB_PLAY_STEER := 0.0004
const SUB_PLAY_TICKS_HELD := 4
const TAP_STEER := 0.001

## A wheel held off centre (0.2 of lock, 90 degrees) and asked for 0.18
## degrees more: the play has no say there, the next tick has it.
const OFF_CENTRE_STEER := 0.2

## The bushings, winding full lock on at 60 km/h (RAW_STEER_SPEEDS[1]): the
## wheels trail the rack by this much at least and at most [rad] (measured
## 0.043, 2.5 degrees; the rigid rack's was 0) ...
const COMPLIANCE_SPEED := 16.7
const COMPLIANCE_MIN_TRAIL := 0.02
const COMPLIANCE_MAX_TRAIL := 0.06

## ... and stand on full lock this many ticks after the rack at least and at
## most (measured 9: the rack at 21, the wheels at 30).
const COMPLIANCE_MIN_LANDING_TICKS := 2
const COMPLIANCE_MAX_LANDING_TICKS := 15

## The steady corner the bushings must not change: 0.3 of lock held for 2 s
## from 12 and from 25 m/s, off the throttle, and what the rigid rack made
## of it at HEAD 3781c8a (before the bushings): the yaw rate and the
## sideways acceleration on the last tick, the mean radius over the 2 s
## (travelled / turned), and on the way in the front wheel angle on the
## third tick and the sideways acceleration on the first, which the bushings
## soften. Measured with the bushings: yaw 0.5140 / 0.4032 (+0.2 / +0.3 %),
## accel 4.9344 / 8.6065 (the same to 0.01 %), radius 20.50 / 62.28 (+0.9 %,
## the softer turn-in's share of the 2 s), wheel on tick 3 0.0478 / 0.0427
## (0.69 / 0.62 of the rigid rack's), accel on tick 1 0.483 / 0.426 (0.57 /
## 0.51 of it).
const STEADY_CORNERS: Array[Dictionary] = [
	{"speed": 12.0, "yaw_rate": 0.512916, "lateral_accel": 4.934534, "radius": 20.312306, "wheel_tick_3": 0.069333, "accel_tick_1": 0.845715},
	{"speed": 25.0, "yaw_rate": 0.401842, "lateral_accel": 8.606580, "radius": 61.719606, "wheel_tick_3": 0.069333, "accel_tick_1": 0.840080},
]
const STEADY_CORNER_STEER := 0.3
const STEADY_CORNER_FRAMES := 120
const STEADY_YAW_TOLERANCE := 0.005
const STEADY_ACCEL_TOLERANCE := 0.002
const STEADY_RADIUS_TOLERANCE := 0.02
const TRANSIENT_MAX_SHARE := 0.8

var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var packed: PackedScene = load(MAIN_SCENE)
	if not _check(packed != null, "main scene loads"):
		_finish()
		return
	var main := packed.instantiate()
	root.add_child(main)
	await _step(60)
	var car := main.get_node_or_null("Car") as ArcadeCar
	if not _check(car != null, "car node exists and is an ArcadeCar"):
		_finish()
		return
	await _check_assist_curve(car)
	await _check_play(car)
	await _check_compliance(car)
	await _check_steady_corner(car)
	await _check_no_nan(car)
	_finish()


## The assist curve as a function, then as ticks to lock: parking at the full
## hand speed, the motorway at 0.6 of it, the chauffeur's hands the same way.
func _check_assist_curve(car: ArcadeCar) -> void:
	var full := true
	for speed in ASSIST_FULL_SPEEDS:
		full = full and car._steering_assist(speed) == 1.0
	_check(full, "assist: exactly 1.0 (the full hand speed, to the bit) at 0, 8.5, 16.7 and %.0f m/s" % ArcadeCar.STEERING_ASSIST_FULL_SPEED)
	var at_25: float = car._steering_assist(25.0)
	var at_35: float = car._steering_assist(35.0)
	_check(absf(at_25 - ASSIST_AT_25) < ASSIST_TOLERANCE and absf(at_35 - ASSIST_AT_35) < ASSIST_TOLERANCE, "assist: %.4f at 25 m/s and %.4f at 35, easing (expected %.4f and %.4f)" % [at_25, at_35, ASSIST_AT_25, ASSIST_AT_35])
	_check(car._steering_assist(ArcadeCar.STEERING_ASSIST_HIGHWAY_SPEED) == ArcadeCar.STEERING_ASSIST_HIGHWAY and car._steering_assist(60.0) == ArcadeCar.STEERING_ASSIST_HIGHWAY and car._steering_assist(INF) == ArcadeCar.STEERING_ASSIST_HIGHWAY, "assist: %.2f from %.0f m/s up, and at any speed beyond" % [ArcadeCar.STEERING_ASSIST_HIGHWAY, ArcadeCar.STEERING_ASSIST_HIGHWAY_SPEED])
	var monotonic := true
	var previous := 1.0
	for i in 121:
		var share: float = car._steering_assist(i * 0.5)
		monotonic = monotonic and is_finite(share) and share <= previous and share >= ArcadeCar.STEERING_ASSIST_HIGHWAY and share <= 1.0
		previous = share
	_check(monotonic, "assist: never rises with speed, never leaves %.2f .. 1.0, finite at every half metre a second from 0 to 60" % ArcadeCar.STEERING_ASSIST_HIGHWAY)
	_check(car._steering_assist(NAN) == 1.0, "assist: a NaN road speed is the full hand speed")

	# Parking: the full hand speed, the first tick through the play.
	car.reset_to_spawn()
	await _step(10)
	var parking_ticks := await _ticks_to_lock(car)
	var first_tick := await _first_tick_of_lock(car)
	_check(parking_ticks == PARKING_TICKS_TO_LOCK, "assist: at a standstill centre to lock takes the hands %d ticks (%.2f s), as certified" % [parking_ticks, parking_ticks / 60.0])
	_check(is_equal_approx(first_tick, ArcadeCar.STEERING_HAND_SPEED / 60.0), "assist: ... the first tick of a held key is the full %.2f degrees, through the rack's play (%.2f)" % [ArcadeCar.STEERING_HAND_SPEED / 60.0, first_tick])

	# The motorway: the same hands, 0.6 of the pace.
	var speed := await _reach_speed(car, HIGHWAY_SPEED)
	var highway_ticks := await _ticks_to_lock(car)
	_check(speed >= HIGHWAY_SPEED and highway_ticks >= HIGHWAY_MIN_TICKS_TO_LOCK and highway_ticks <= HIGHWAY_MAX_TICKS_TO_LOCK, "assist: from %.1f m/s (%.0f km/h) centre to lock takes the same hands %d ticks (%.2f s, %.0f degrees a second at the wheel; %d .. %d)" % [speed, speed * 3.6, highway_ticks, highway_ticks / 60.0, ArcadeCar.STEERING_WHEEL_LOCK_DEG * 60.0 / highway_ticks, HIGHWAY_MIN_TICKS_TO_LOCK, HIGHWAY_MAX_TICKS_TO_LOCK])
	_check(highway_ticks > parking_ticks * 1.4, "assist: ... visibly longer than parking (%d against %d ticks, x%.2f)" % [highway_ticks, parking_ticks, float(highway_ticks) / parking_ticks])
	_check(car.steering_wheel_deg == ArcadeCar.STEERING_WHEEL_LOCK_DEG and car.rack_angle == ArcadeCar.MAX_STEER_LOCK, "assist: ... and it is still full lock, all %.0f degrees of it (%.2f rad at the rack)" % [car.steering_wheel_deg, car.rack_angle])
	Input.action_release("steer_left")

	# The chauffeur's hands: half the speed, the same assist on top.
	car.set_driver_profile(ArcadeCar.DRIVER_PROFILES["chauffeur"])
	speed = await _reach_speed(car, HIGHWAY_SPEED)
	var chauffeur_ticks := await _ticks_to_lock(car)
	Input.action_release("steer_left")
	car.set_driver_profile(ArcadeCar.DRIVER_PROFILES["test_driver"])
	var expected_chauffeur := int(round(highway_ticks * ArcadeCar.STEERING_HAND_SPEED / ArcadeCar.DRIVER_PROFILES["chauffeur"]["steering_hand_speed"]))
	_check(speed >= HIGHWAY_SPEED and absi(chauffeur_ticks - expected_chauffeur) <= CHAUFFEUR_TICKS_TOLERANCE, "assist: the chauffeur's hands (%.0f degrees a second) take %d ticks from %.0f km/h - the assist multiplies the driver's own hand speed (%d expected, %d either way)" % [ArcadeCar.DRIVER_PROFILES["chauffeur"]["steering_hand_speed"], chauffeur_ticks, speed * 3.6, expected_chauffeur, CHAUFFEUR_TICKS_TOLERANCE])
	car.reset_to_spawn()
	await _step(5)


## The rack's play at centre: sub-play motion adds up and moves nothing
## until it is through, a tap back and forth never moves anything, and off
## centre there is no play at all.
func _check_play(car: ArcadeCar) -> void:
	car.reset_to_spawn()
	await _step(10)
	car.set_driver_input(0.0, 0.0, SUB_PLAY_STEER)
	var still := true
	var play_in := 0.0
	for tick in SUB_PLAY_TICKS_HELD:
		await physics_frame
		still = still and car.steering_wheel_deg == 0.0 and car.rack_angle == 0.0 and car.wheel_angle == 0.0 and car.steer == 0.0
		play_in = car._steering_play_deg
	var asked := SUB_PLAY_STEER * ArcadeCar.STEERING_WHEEL_LOCK_DEG
	_check(still and is_equal_approx(play_in, SUB_PLAY_TICKS_HELD * asked), "play: %.2f degrees a tick asked for is no wheel angle at all for %d ticks, %.2f degrees in the play (under %.2f)" % [asked, SUB_PLAY_TICKS_HELD, play_in, ArcadeCar.STEERING_PLAY_DEG])
	await physics_frame
	_check(is_equal_approx(car.steering_wheel_deg, asked) and car._steering_play_deg == 0.0 and car.rack_angle == car.steer * ArcadeCar.MAX_STEER_LOCK and car.steer == car.steering_wheel_deg / ArcadeCar.STEERING_WHEEL_LOCK_DEG, "play: ... and through it on tick %d the wheel is where the hands have it, %.2f degrees, the play empty, the rack its share of lock (%.5f rad)" % [SUB_PLAY_TICKS_HELD + 1, car.steering_wheel_deg, car.rack_angle])
	await _step(5)
	_check(is_equal_approx(car.steering_wheel_deg, asked) and car.wheel_angle == car.rack_angle, "play: ... held, it stays there and the wheels stand on it (%.2f degrees, %.5f rad)" % [car.steering_wheel_deg, car.wheel_angle])

	# A tap: one tick in, one tick back, nothing moves.
	car.set_driver_input(0.0, 0.0, 0.0)
	car.reset_to_spawn()
	await _step(5)
	car.set_driver_input(0.0, 0.0, TAP_STEER)
	await physics_frame
	var after_in := car.steering_wheel_deg
	var in_play := car._steering_play_deg
	car.set_driver_input(0.0, 0.0, -TAP_STEER)
	await physics_frame
	var after_back := car.steering_wheel_deg
	car.set_driver_input(0.0, 0.0, 0.0)
	await _step(5)
	_check(after_in == 0.0 and is_equal_approx(in_play, TAP_STEER * ArcadeCar.STEERING_WHEEL_LOCK_DEG) and after_back == 0.0 and car._steering_play_deg == 0.0 and car.steering_wheel_deg == 0.0 and car.wheel_angle == 0.0, "play: a %.2f-degree tap, in and back, moves nothing and leaves the play where it was (in %.2f, back to %.2f)" % [TAP_STEER * ArcadeCar.STEERING_WHEEL_LOCK_DEG, in_play, car._steering_play_deg])

	# Off centre: no play.
	car.set_driver_input(0.0, 0.0, OFF_CENTRE_STEER)
	await _step(10)
	var held := car.steering_wheel_deg
	car.set_driver_input(0.0, 0.0, OFF_CENTRE_STEER + SUB_PLAY_STEER)
	await physics_frame
	var moved := car.steering_wheel_deg - held
	_check(is_equal_approx(held, OFF_CENTRE_STEER * ArcadeCar.STEERING_WHEEL_LOCK_DEG) and is_equal_approx(moved, asked) and car._steering_play_deg == 0.0, "play: off centre (%.0f degrees) the same %.2f degrees asked for is on the wheel the next tick, no play (%.2f)" % [held, asked, moved])
	car.set_driver_input(0.0, 0.0, 0.0)
	car.clear_driver_input()
	car.reset_to_spawn()
	await _step(5)


## The bushings: winding full lock on at 60 km/h the wheels trail the rack,
## never lead it, and land on it a measured few ticks after the rack stops;
## the lag's time constant grows with the front tyres' sideways load.
func _check_compliance(car: ArcadeCar) -> void:
	_check(car._steering_compliance_tau() == ArcadeCar.STEERING_COMPLIANCE_TAU_MIN, "bushings: unloaded, the lag's time constant is %.3f s" % car._steering_compliance_tau())
	await _reach_speed(car, COMPLIANCE_SPEED)
	var trailing := true
	var largest_trail := 0.0
	var rack_tick := -1
	var wheels_tick := -1
	var tau_at_lock := 0.0
	Input.action_press("steer_left")
	for frame in 60:
		await physics_frame
		var trail: float = car.rack_angle - car.wheel_angle
		trailing = trailing and trail >= 0.0 and car.wheel_angle >= 0.0
		largest_trail = maxf(largest_trail, trail)
		if rack_tick < 0 and car.rack_angle == ArcadeCar.MAX_STEER_LOCK:
			rack_tick = frame + 1
		if wheels_tick < 0 and car.wheel_angle == ArcadeCar.MAX_STEER_LOCK:
			wheels_tick = frame + 1
			tau_at_lock = car._steering_compliance_tau()
	Input.action_release("steer_left")
	_check(trailing and largest_trail > COMPLIANCE_MIN_TRAIL and largest_trail < COMPLIANCE_MAX_TRAIL, "bushings: from %.1f m/s the wheels trail the rack on every tick, never lead it, by %.4f rad at most (%.1f degrees; %.2f .. %.2f)" % [COMPLIANCE_SPEED, largest_trail, rad_to_deg(largest_trail), COMPLIANCE_MIN_TRAIL, COMPLIANCE_MAX_TRAIL])
	_check(rack_tick == PARKING_TICKS_TO_LOCK and wheels_tick - rack_tick >= COMPLIANCE_MIN_LANDING_TICKS and wheels_tick - rack_tick <= COMPLIANCE_MAX_LANDING_TICKS, "bushings: the rack is at full lock on tick %d, the wheels stand on it to the bit %d ticks later (tick %d; %d .. %d)" % [rack_tick, wheels_tick - rack_tick, wheels_tick, COMPLIANCE_MIN_LANDING_TICKS, COMPLIANCE_MAX_LANDING_TICKS])
	_check(tau_at_lock > ArcadeCar.STEERING_COMPLIANCE_TAU_MIN and tau_at_lock <= ArcadeCar.STEERING_COMPLIANCE_TAU_MAX, "bushings: at full lock at speed the front tyres are loaded and the time constant is up to %.4f s (%.3f .. %.3f)" % [tau_at_lock, ArcadeCar.STEERING_COMPLIANCE_TAU_MIN, ArcadeCar.STEERING_COMPLIANCE_TAU_MAX])
	car.reset_to_spawn()
	await _step(5)


## The steady corner is the rigid rack's; the way in is softer.
func _check_steady_corner(car: ArcadeCar) -> void:
	for corner in STEADY_CORNERS:
		await _reach_speed(car, corner.speed)
		var yaw_before := car.global_rotation.y
		var travelled := 0.0
		var turned := 0.0
		var wheel_tick_3 := 0.0
		var accel_tick_1 := 0.0
		Input.action_press("steer_left", STEADY_CORNER_STEER)
		for frame in STEADY_CORNER_FRAMES:
			var before := car.global_position
			await physics_frame
			travelled += car.global_position.distance_to(before)
			turned += angle_difference(yaw_before, car.global_rotation.y)
			yaw_before = car.global_rotation.y
			if frame == 0:
				accel_tick_1 = car.lateral_accel
			if frame == 2:
				wheel_tick_3 = car.wheel_angle
		Input.action_release("steer_left")
		var radius := travelled / turned
		var yaw_share: float = car.yaw_rate / corner.yaw_rate
		var accel_share: float = car.lateral_accel / corner.lateral_accel
		var radius_share: float = radius / corner.radius
		_check(car.wheel_angle == car.rack_angle and is_equal_approx(car.wheel_angle, STEADY_CORNER_STEER * ArcadeCar.MAX_STEER_LOCK), "corner from %.0f m/s: after %.0f s the wheels stand on the rack, %.3f rad, to the bit" % [corner.speed, STEADY_CORNER_FRAMES / 60.0, car.wheel_angle])
		_check(absf(yaw_share - 1.0) < STEADY_YAW_TOLERANCE and absf(accel_share - 1.0) < STEADY_ACCEL_TOLERANCE, "corner from %.0f m/s: ... the yaw rate is the rigid rack's (%.4f rad/s, %.2f %% off) and so is the sideways acceleration (%.4f m/s^2, %.2f %% off)" % [corner.speed, car.yaw_rate, (yaw_share - 1.0) * 100.0, car.lateral_accel, (accel_share - 1.0) * 100.0])
		_check(absf(radius_share - 1.0) < STEADY_RADIUS_TOLERANCE, "corner from %.0f m/s: ... and the mean radius within %.0f %% of it (%.2f m against %.2f, %.1f %% off)" % [corner.speed, STEADY_RADIUS_TOLERANCE * 100.0, radius, corner.radius, (radius_share - 1.0) * 100.0])
		_check(wheel_tick_3 < corner.wheel_tick_3 * TRANSIENT_MAX_SHARE and accel_tick_1 < corner.accel_tick_1 * TRANSIENT_MAX_SHARE and wheel_tick_3 > 0.0 and accel_tick_1 > 0.0, "corner from %.0f m/s: the way in is softer - %.4f rad on the wheels on tick 3 (the rigid rack's %.4f) and %.3f m/s^2 sideways on tick 1 (%.3f)" % [corner.speed, wheel_tick_3, corner.wheel_tick_3, accel_tick_1, corner.accel_tick_1])
	car.reset_to_spawn()
	await _step(5)


## Nothing new makes a NaN: NaN input, and every new state finite after all
## of the above.
func _check_no_nan(car: ArcadeCar) -> void:
	car.reset_to_spawn()
	await _step(5)
	car.set_driver_input(NAN, NAN, NAN)
	await _step(5)
	var quiet := car.steering_wheel_deg == 0.0 and car.rack_angle == 0.0 and car.wheel_angle == 0.0 and car._steering_play_deg == 0.0
	car.clear_driver_input()
	Input.action_press("steer_left")
	await _step(30)
	Input.action_release("steer_left")
	await _step(30)
	var finite := is_finite(car.steering_wheel_deg) and is_finite(car.rack_angle) and is_finite(car.wheel_angle) and is_finite(car._steering_play_deg) and is_finite(car._front_lateral_load) and is_finite(car._steering_compliance_tau())
	_check(quiet and finite and car.wheel_angle == 0.0, "no NaN: NaN steering asked for is none, and after a full lock and back every steering state is finite and the wheels are at centre (play %.2f, load %.3f, tau %.3f)" % [car._steering_play_deg, car._front_lateral_load, car._steering_compliance_tau()])
	car.reset_to_spawn()
	await _step(5)


## Presses steer_left and counts the ticks until the steering wheel is at
## full lock; leaves the key held.
func _ticks_to_lock(car: ArcadeCar) -> int:
	Input.action_press("steer_left")
	for frame in 120:
		await physics_frame
		if car.steering_wheel_deg == ArcadeCar.STEERING_WHEEL_LOCK_DEG:
			return frame + 1
	return -1


## Lets the key go, waits for centre, presses again for one tick and returns
## how far the wheel went on it [degrees]; leaves the key released.
func _first_tick_of_lock(car: ArcadeCar) -> float:
	Input.action_release("steer_left")
	await _step(30)
	Input.action_press("steer_left")
	await physics_frame
	var moved := car.steering_wheel_deg
	Input.action_release("steer_left")
	await _step(30)
	return moved


## Resets the car and accelerates it in a straight line to `speed`, then
## lifts; returns the speed it got to [m/s].
func _reach_speed(car: ArcadeCar, speed: float) -> float:
	car.reset_to_spawn()
	# was the reset's own -> set by hand: a reset keeps the heat (the user's
	# report, 2026-09-22 morning), and the steady corners are compared against
	# numbers measured on the certified fresh car - warm coolant, warm tyres,
	# cold brakes; every drive-up starts from it.
	_fresh_heat(car)
	await _step(10)
	Input.action_press("accelerate")
	for frame in 2400:
		if car.forward_speed >= speed:
			break
		await physics_frame
	Input.action_release("accelerate")
	return car.forward_speed


## The certified fresh car's thermal state, set by hand: the coolant at
## operating with the fan off, the tyres at operating, the brakes at the
## air's, the tick's heat trackers and the idle hunt's phase at 0 - what
## reset_to set until the reset stopped touching the heat (the user's report,
## 2026-09-22 morning), and what HandlingTests._start sets for a certified
## run.
func _fresh_heat(car: ArcadeCar) -> void:
	car.coolant_temp = 1.0
	car.coolant_fan_on = false
	car._combustion_heat_w = 0.0
	car._idle_wobble_phase = 0.0
	car.front_tyre_temp = 1.0
	car.rear_tyre_temp = 1.0
	car.front_brake_temp = 0.0
	car.rear_brake_temp = 0.0
	car._front_tyre_heat_w = 0.0
	car._rear_tyre_heat_w = 0.0
	car._front_brake_heat_w = 0.0
	car._rear_brake_heat_w = 0.0
	_fresh_wear(car)


## And the certified fresh car's components, new: the six wear shares and the
## clutch's slip tracker at 0 - a reset keeps the wear (R refuels, it does not
## un-wear), what HandlingTests._start sets for a certified run.
func _fresh_wear(car: ArcadeCar) -> void:
	car.clutch_wear = 0.0
	car.front_brake_wear = 0.0
	car.rear_brake_wear = 0.0
	car.front_tyre_wear = 0.0
	car.rear_tyre_wear = 0.0
	car.engine_wear = 0.0
	car._clutch_slip_w = 0.0


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
	for action in ["accelerate", "steer_left", "steer_right"]:
		Input.action_release(action)
	if _failures == 0:
		print("STEERING FEEL TEST PASSED")
	else:
		print("STEERING FEEL TEST FAILED: %d check(s) failed" % _failures)
	quit(1 if _failures > 0 else 0)
