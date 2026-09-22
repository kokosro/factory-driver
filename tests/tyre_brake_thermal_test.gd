extends SceneTree
## Headless tyre and brake thermal test. Run via tests/run_tests.sh, or:
##
##   godot --headless --path . --import
##   godot --headless --fixed-fps 60 --path . --script res://tests/tyre_brake_thermal_test.gd
##
## Loads the main scene and puts the car's tyres and brakes (ArcadeCar,
## "Thermal: tyres and brakes") through what their temperatures do. First
## the gate: the car comes out of _ready with its tyres at the operating
## temperature and its brakes at the air's, where the grip factor is exactly
## 1 and the brake fade exactly 1 - the axle grip is the pre-thermal line to
## the bit at every load, the brake torque the pre-thermal line, and a stop
## on brakes well under the fade line is the stop on cold brakes to the bit.
## Then the certified runs themselves, driven by their own scripted drivers:
## on every tick of every one of them the tyres stay inside the window and
## the brakes under the line (the margins stated in the output), and the run
## times are the certified ones. Then the tyres' heat: a donut has the rears
## over the window in tens of seconds, the rise tick by tick exactly the heat
## in over the lump; a handbrake slide heats the locked rears and puts no work
## into their discs; a hot tyre cools at speed, faster than standing. Then the
## warm-up: on the model alone at a cruise the fronts and the rears climb from
## the air's temperature into the window and settle inside it (the minutes
## stated), and in the scene a minute or two of hard mixed driving has both
## axles in the window. Then the grip: cold tyres stop the car measurably
## longer and hold measurably less in a corner than warm ones, warm ones
## exactly as ever, overheated ones measurably less again, the factor never
## under its floor. Then the brakes' heat: a stop from 90 km/h warms the
## discs by its share of the car's energy, a hot disc cools at speed, faster
## than standing, and a red-hot one is back under the fade line in minutes of
## cruising (stated). Then the fade: hot brakes stop the car measurably
## longer, a string of hard stops brings the fade on, the fade never goes
## under its floor, the discs never over their ceiling, and brakes at the
## ceiling still stop the car - nothing dies; and the handbrake is the lever's,
## the same slide to the bit with the rear discs at the ceiling. Then the
## HUD's two bars: they follow the hotter axle, blue cold, grey in the window,
## red over it, brighter red hotter, their lines the car's own. Last, nothing
## of it is ever NaN, after the limiter, a stall, handbrake slides and resets.
## Exits 0 on success, 1 on any failed check.

const MAIN_SCENE := "res://scenes/main.tscn"

## Physics frames to let the car settle on the ground at the start.
const SETTLE_FRAMES := 60

## Physics frames to let the car settle after a certified run's begin (the
## handling test's).
const RUN_SETTLE_FRAMES := 20

## The certified run times [s] (scripts/handling_tests.gd's tests in their
## order), as certified at 3040705: the runs here have to come out at them.
# was 28.77 / 15.92 / 18.13 / 8.72 / 7.68 -> 28.82 / 15.95 / 18.07 / 8.72 /
# 7.72 - the steering feel (the power assist, the rack's play, the bushings'
# compliance; see ArcadeCar STEERING_ASSIST_FULL_SPEED): +0.17 %, +0.19 %,
# -0.33 %, 0, +0.52 %, measured at 3781c8a with the three in.
const CERTIFIED_RUN_TIMES := {
	"SLALOM_TEST": 28.82,
	"SPIN_180": 15.95,
	"SPIN_360": 18.07,
	"STOP_BOX": 8.72,
	"REVERSE_180": 7.72,
}

## The speed the stops are made from [km/h] (25 m/s, the stop box's entry).
const STOP_FROM_KMH := 90.0

## Where a stop is over [km/h].
const STOPPED_KMH := 1.0

## The most ticks a donut is given to put the rears over the window (40 s;
## measured 18 s) and a check every this many ticks that they are still
## climbing.
const DONUT_MAX_FRAMES := 2400

## Ticks of a handbrake slide from 100 km/h (3 s).
const HANDBRAKE_FRAMES := 180

## How far a tick's temperature may be from the heat in less the cooling
## over the lump, on the 0..1 scales (0.006 K on the tyres'): the airflow a
## tick cools with is the road speed it begins with, read off the body after
## the tick before moved it, which in a donut is a hair from the speed that
## tick left (its yaw turns a little of the lateral speed forwards). A tick's
## rise in a donut is ~1e-3 of the unit; the difference seen is ~5e-7.
const WIRING_TOLERANCE := 1.0e-4

## How far the settled warm-up may still move in its last minute, on the
## tyres' scale (a tenth of a kelvin): the fronts' time constant at the
## cruise is ~5 min, and 30 min is six of them.
const SETTLED_TOLERANCE := 1.0e-3

## A hot tyre and a hot brake for the cooling checks [C].
const HOT_TYRE_C := 140.0
const HOT_BRAKE_C := 400.0

## The cruise the warm-up is measured at on the model alone [m/s] (20 m/s,
## 72 km/h, the coolant's), and the most ticks it is watched for (30 min).
const CRUISE_SPEED := 20.0
const WARM_UP_WATCH_FRAMES := 108000

## The warm-up on the model alone has to have both axles in the window within
## this many minutes of that cruise (measured: the rears in ~1.5 min, the
## fronts in ~6).
const WARM_UP_MAX_MINUTES := 10.0

## The mixed driving in the scene: laps of flat out (4 s), a hard dab of brake
## (1 s) and a corner (4 s) to alternate sides, and the most laps the cold
## tyres are given to reach the window (20 laps, 3 min; measured: ~1 min).
const MIXED_THROTTLE_FRAMES := 240
const MIXED_BRAKE_FRAMES := 60
const MIXED_CORNER_FRAMES := 240
const MIXED_MAX_LAPS := 20

## The corner the cold and the warm grip are compared in: the steer held at
## this share of the lock from 60 km/h with this much throttle for this many
## ticks (4 s), the peak lateral acceleration compared.
const CORNER_STEER := 0.5
const CORNER_THROTTLE := 0.3
const CORNER_FROM_KMH := 60.0
const CORNER_FRAMES := 240

## How much longer a cold stop has to be than a warm one, at the least (the
## grip is TYRE_COLD_GRIP: measured 14 % longer, the tyres warming a little
## through the stop), and how much less a cold corner has to hold.
const COLD_STOP_MIN_LONGER := 1.05
const COLD_CORNER_MIN_LESS := 0.95

## Stops made in a row for the fade to come on (12: measured, the fade is on
## from the seventh), the car driven straight back up to STOP_FROM_KMH between
## them.
const FADE_STOPS := 12

## The most minutes a red-hot front brake may take to cool to the fade line
## on a 30 m/s cruise (measured 1.6 min from 417 C).
const RECOVERY_MAX_MINUTES := 5.0
const RECOVERY_CRUISE := 30.0

## Ticks the limiter is held in neutral (2 s), and ticks a dry tank is given
## to stall the engine (4 s).
const LIMITER_FRAMES := 120
const RUN_DOWN_FRAMES := 240

var _failures := 0

## The temperatures as _ready left them, before a tick could touch them.
var _tyres_at_start := [-1.0, -1.0]
var _brakes_at_start := [-1.0, -1.0]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var packed: PackedScene = load(MAIN_SCENE)
	if not _check(packed != null, "main scene loads"):
		_finish()
		return
	var main := packed.instantiate()
	root.add_child(main)
	var car_at_ready := main.get_node_or_null("Car") as ArcadeCar
	if car_at_ready:
		_tyres_at_start = [car_at_ready.front_tyre_temp, car_at_ready.rear_tyre_temp]
		_brakes_at_start = [car_at_ready.front_brake_temp, car_at_ready.rear_brake_temp]
	await _step(SETTLE_FRAMES)

	var car := main.get_node_or_null("Car") as ArcadeCar
	var pad := main.get_node_or_null("TestPad") as TestPad
	var hud := main.get_node_or_null("HUD") as HUD
	var tyre_bar := main.get_node_or_null("HUD/TyreBarBack/TyreBar") as ColorRect
	var brake_bar := main.get_node_or_null("HUD/BrakeHeatBarBack/BrakeHeatBar") as ColorRect
	if not _check(car != null and pad != null and hud != null and tyre_bar != null and brake_bar != null, "car, test pad, HUD and the HUD's tyre and brake bars exist"):
		_finish()
		return

	_check_model_numbers()
	_check_suite_gate(car)
	await _check_certified_untouched(car)
	await _check_certified_runs(car, pad)
	await _check_tyre_heat(car)
	await _check_tyre_cooling(car)
	_check_warm_up(car)
	await _check_mixed_driving(car)
	await _check_grip(car)
	await _check_brake_heat(car)
	await _check_brake_fade(car)
	await _check_handbrake_untouched(car)
	await _check_hud_bars(car, hud, tyre_bar, brake_bar)
	await _check_no_nan(car)

	car.reset_to_spawn()
	pad.reset_cones()
	await _step(5)
	_finish()


## The model's own numbers: the two scales (the tyres' 0 the air and 1
## operating, the brakes' 0 the air and 1 the fade line), and the lines in
## their order - the window's lower edge under operating under its upper edge
## under the tyres' ceiling, the brakes' fade line under red hot under their
## ceiling, the cold grip and the floors between 0 and 1, the rates over 0.
func _check_model_numbers() -> void:
	var tyre_scale := ArcadeCar.tyre_c_of(0.0) == ArcadeCar.COOLANT_AMBIENT_C and ArcadeCar.tyre_c_of(1.0) == ArcadeCar.TYRE_OPERATING_C \
		and ArcadeCar.tyre_temp_of_c(ArcadeCar.COOLANT_AMBIENT_C) == 0.0 and ArcadeCar.tyre_temp_of_c(ArcadeCar.TYRE_OPERATING_C) == 1.0 \
		and is_equal_approx(ArcadeCar.TYRE_MAX_TEMP, ArcadeCar.tyre_temp_of_c(ArcadeCar.TYRE_MAX_C)) and ArcadeCar.TYRE_SPAN_K > 0.0
	var brake_scale := ArcadeCar.brake_c_of(0.0) == ArcadeCar.COOLANT_AMBIENT_C and ArcadeCar.brake_c_of(1.0) == ArcadeCar.BRAKE_FADE_START_C \
		and ArcadeCar.brake_temp_of_c(ArcadeCar.COOLANT_AMBIENT_C) == 0.0 and ArcadeCar.brake_temp_of_c(ArcadeCar.BRAKE_FADE_START_C) == 1.0 \
		and is_equal_approx(ArcadeCar.BRAKE_MAX_TEMP, ArcadeCar.brake_temp_of_c(ArcadeCar.BRAKE_MAX_C)) and ArcadeCar.BRAKE_SPAN_K > 0.0
	_check(
		tyre_scale and brake_scale,
		"model: tyre_temp runs from 0 at the air's %.0f C to 1 at the operating %.0f C (%.0f K to the unit) and stops at %.3f, the %.0f C ceiling; brake_temp from 0 at the air to 1 at the %.0f C fade line (%.0f K to the unit), stopping at %.3f, the %.0f C ceiling" % [ArcadeCar.COOLANT_AMBIENT_C, ArcadeCar.TYRE_OPERATING_C, ArcadeCar.TYRE_SPAN_K, ArcadeCar.TYRE_MAX_TEMP, ArcadeCar.TYRE_MAX_C, ArcadeCar.BRAKE_FADE_START_C, ArcadeCar.BRAKE_SPAN_K, ArcadeCar.BRAKE_MAX_TEMP, ArcadeCar.BRAKE_MAX_C],
	)
	var order_ok := ArcadeCar.COOLANT_AMBIENT_C < ArcadeCar.TYRE_WINDOW_LOW_C and ArcadeCar.TYRE_WINDOW_LOW_C < ArcadeCar.TYRE_OPERATING_C \
		and ArcadeCar.TYRE_OPERATING_C < ArcadeCar.TYRE_WINDOW_HIGH_C and ArcadeCar.TYRE_WINDOW_HIGH_C < ArcadeCar.TYRE_MAX_C \
		and ArcadeCar.COOLANT_AMBIENT_C < ArcadeCar.BRAKE_FADE_START_C and ArcadeCar.BRAKE_FADE_START_C < ArcadeCar.BRAKE_RED_HOT_C \
		and ArcadeCar.BRAKE_RED_HOT_C < ArcadeCar.BRAKE_MAX_C \
		and ArcadeCar.TYRE_COLD_GRIP > 0.0 and ArcadeCar.TYRE_COLD_GRIP < 1.0 and ArcadeCar.TYRE_FADE_RATE > 0.0 \
		and ArcadeCar.TYRE_FADE_FLOOR > 0.0 and ArcadeCar.TYRE_FADE_FLOOR < 1.0 and ArcadeCar.BRAKE_FADE_RATE > 0.0 \
		and ArcadeCar.BRAKE_FADE_FLOOR > 0.0 and ArcadeCar.BRAKE_FADE_FLOOR < 1.0 \
		and ArcadeCar.TYRE_SLIP_HEAT_SHARE > 0.0 and ArcadeCar.TYRE_SLIP_HEAT_SHARE <= 1.0 \
		and ArcadeCar.TYRE_HEAT_CAPACITY > 0.0 and ArcadeCar.BRAKE_HEAT_CAPACITY > 0.0
	_check(
		order_ok,
		"model: the lines stand in order - the window %.0f .. %.0f C around the operating %.0f, the tyres' ceiling %.0f; the brakes' fade line %.0f C, red hot %.0f, their ceiling %.0f; a cold tyre has %.2f of its grip, the floors %.2f (tyres) and %.2f (brakes), %.0f %% of the slip work into the rubber" % [ArcadeCar.TYRE_WINDOW_LOW_C, ArcadeCar.TYRE_WINDOW_HIGH_C, ArcadeCar.TYRE_OPERATING_C, ArcadeCar.TYRE_MAX_C, ArcadeCar.BRAKE_FADE_START_C, ArcadeCar.BRAKE_RED_HOT_C, ArcadeCar.BRAKE_MAX_C, ArcadeCar.TYRE_COLD_GRIP, ArcadeCar.TYRE_FADE_FLOOR, ArcadeCar.BRAKE_FADE_FLOOR, ArcadeCar.TYRE_SLIP_HEAT_SHARE * 100.0],
	)


## The suite starts in the certified thermal state: the car came out of _ready
## with both tyres at exactly the operating temperature and both brakes at
## exactly the air's, and there the grip factor is exactly 1 and the fade
## exactly 1. Standing through the settle the tyres cool a hair (the still
## air's share, nothing warms a standing tyre) and stay well inside the
## window, the factor still exactly 1; the brakes stay at the air's.
func _check_suite_gate(car: ArcadeCar) -> void:
	_check(
		_tyres_at_start[0] == 1.0 and _tyres_at_start[1] == 1.0 and _brakes_at_start[0] == 0.0 and _brakes_at_start[1] == 0.0
			and ArcadeCar.tyre_grip_factor(1.0) == 1.0 and ArcadeCar.brake_fade(0.0) == 1.0
			and car.front_tyre_temp < 1.0 and car.front_tyre_temp > 0.99 and car.rear_tyre_temp == car.front_tyre_temp
			and ArcadeCar.tyre_grip_factor(car.front_tyre_temp) == 1.0 and car.front_brake_temp == 0.0 and car.rear_brake_temp == 0.0,
		"suite: the car came out of _ready with its tyres at the operating temperature (front %.3f, rear %.3f: %.0f C) and its brakes at the air's (front %.3f, rear %.3f: %.0f C) - the grip factor exactly 1, the fade exactly 1: the certified path; standing through the %d settle ticks the tyres cool %.3f K, the factor still exactly 1" % [_tyres_at_start[0], _tyres_at_start[1], ArcadeCar.tyre_c_of(_tyres_at_start[0]), _brakes_at_start[0], _brakes_at_start[1], ArcadeCar.brake_c_of(_brakes_at_start[0]), SETTLE_FRAMES, (1.0 - car.front_tyre_temp) * ArcadeCar.TYRE_SPAN_K],
	)


## The certified path untouched: at the operating temperature - and anywhere
## in the window, its two edges included - the axle grip is the pre-thermal
## line to the bit at every load (TYRE_MU x static load x (load / static)^
## LOAD_GRIP_EXPONENT); the brake torque is the pre-thermal line to the bit;
## and a stop from 90 km/h on brakes well under the fade line is the stop on
## brakes at the air's temperature to the bit, the same metres in the same
## ticks - the fade is exactly 1 up to the line, and exactly the same physics.
func _check_certified_untouched(car: ArcadeCar) -> void:
	var static_load := car.total_mass() * 9.8 * ArcadeCar.REAR_WEIGHT_FRACTION
	var loads := [0.0, 0.3, 0.7, 1.0, 1.4, 2.0]
	var temps := [1.0, ArcadeCar.tyre_temp_of_c(ArcadeCar.TYRE_WINDOW_LOW_C), ArcadeCar.tyre_temp_of_c(ArcadeCar.TYRE_WINDOW_HIGH_C), ArcadeCar.tyre_temp_of_c((ArcadeCar.TYRE_WINDOW_LOW_C + ArcadeCar.TYRE_OPERATING_C) / 2.0)]
	var to_the_bit := 0
	for share: float in loads:
		var load := share * static_load
		var pre_thermal := ArcadeCar.TYRE_MU * static_load * pow(maxf(load, 0.0) / static_load, ArcadeCar.LOAD_GRIP_EXPONENT)
		var all_temps := true
		for temp: float in temps:
			all_temps = all_temps and car._axle_grip(load, static_load, temp) == pre_thermal and ArcadeCar.tyre_grip_factor(temp) == 1.0
		if all_temps:
			to_the_bit += 1
	var brake_n := ArcadeCar.BRAKE_DECEL * car.total_mass()
	var brake_line := ArcadeCar.BRAKE_BIAS_FRONT * brake_n * ArcadeCar.WHEEL_RADIUS + ArcadeCar.AXLE_INERTIA * brake_n / (car.total_mass() * ArcadeCar.WHEEL_RADIUS)
	var brake_ok := car._brake_torque(ArcadeCar.BRAKE_BIAS_FRONT, brake_n, ArcadeCar.AXLE_INERTIA) == brake_line \
		and ArcadeCar.brake_fade(ArcadeCar.brake_temp_of_c(ArcadeCar.BRAKE_FADE_START_C)) == 1.0 and ArcadeCar.brake_fade(ArcadeCar.brake_temp_of_c(ArcadeCar.BRAKE_FADE_START_C) + 0.01) < 1.0
	var cold := await _stop(car, 1.0, 0.0)
	var warm_discs := await _stop(car, 1.0, ArcadeCar.brake_temp_of_c(150.0))
	var same_stop: bool = cold.distance_m == warm_discs.distance_m and cold.ticks == warm_discs.ticks and cold.from_ms == warm_discs.from_ms
	_check(
		to_the_bit == loads.size() and brake_ok and same_stop and warm_discs.front_c < ArcadeCar.BRAKE_FADE_START_C,
		"certified: in the window the axle grip is the pre-thermal line to the bit at all %d loads and at operating, both edges and between; the brake torque is the pre-thermal line to the bit, the fade exactly 1 at the %.0f C line and under 1 just over it; a stop from %.1f m/s on brakes at 150 C is the stop on brakes at the air's to the bit (%.2f m in %d ticks, the discs at %.0f C after it)" % [loads.size(), ArcadeCar.BRAKE_FADE_START_C, cold.from_ms, cold.distance_m, cold.ticks, warm_discs.front_c],
	)


## The certified runs, driven by their own scripted drivers from the warm
## tyres and the cold brakes the suite starts on: on every tick of every run
## both axles' tyres are inside the window (the factor exactly 1) and both
## brakes under the fade line (the fade exactly 1), and the run times are the
## certified ones. The margins - the hottest and the coldest a tyre gets, the
## hottest a disc gets - are stated: they are what the window and the line
## are calibrated against.
func _check_certified_runs(car: ArcadeCar, pad: TestPad) -> void:
	var delta := 1.0 / Engine.physics_ticks_per_second
	var certified := 0
	var in_window := 0
	var tyre_low := INF
	var tyre_high := -INF
	var brake_high := -INF
	var hottest_run := ""
	var coldest_run := ""
	var hottest_brake_run := ""
	var names := ""
	for definition in HandlingTests.all_tests():
		var run := HandlingTests.begin(definition, car, pad)
		await _step(RUN_SETTLE_FRAMES)
		var every_tick := true
		var run_low := INF
		var run_high := -INF
		var run_brake := -INF
		while not run.finished:
			run.tick(delta)
			await physics_frame
			every_tick = every_tick and ArcadeCar.tyre_grip_factor(car.front_tyre_temp) == 1.0 and ArcadeCar.tyre_grip_factor(car.rear_tyre_temp) == 1.0 \
				and ArcadeCar.brake_fade(car.front_brake_temp) == 1.0 and ArcadeCar.brake_fade(car.rear_brake_temp) == 1.0
			run_low = minf(run_low, minf(car.front_tyre_temp, car.rear_tyre_temp))
			run_high = maxf(run_high, maxf(car.front_tyre_temp, car.rear_tyre_temp))
			run_brake = maxf(run_brake, maxf(car.front_brake_temp, car.rear_brake_temp))
		var outcome := run.result()
		var expected: float = CERTIFIED_RUN_TIMES.get(definition.name, -1.0)
		if outcome.passed and is_equal_approx(outcome.metrics.run_time_s, expected):
			certified += 1
		if every_tick:
			in_window += 1
		if run_high > tyre_high:
			tyre_high = run_high
			hottest_run = definition.name
		if run_low < tyre_low:
			tyre_low = run_low
			coldest_run = definition.name
		if run_brake > brake_high:
			brake_high = run_brake
			hottest_brake_run = definition.name
		names += ("" if names == "" else ", ") + "%s %.2f s" % [definition.name, outcome.metrics.run_time_s]
	car.reset_to_spawn()
	pad.reset_cones()
	await _step(5)
	var runs := CERTIFIED_RUN_TIMES.size()
	_check(
		certified == runs and in_window == runs and runs == HandlingTests.all_tests().size(),
		"certified runs: all %d pass at their certified times (%s), and on every tick of every one the tyres are in the window and the brakes under the line - the hottest tyre %.1f C (%s, %.0f K under the window's %.0f C edge), the coldest %.1f C (%s, %.0f K over its %.0f C edge), the hottest disc %.1f C (%s, %.0f K under the %.0f C fade line)" % [runs, names, ArcadeCar.tyre_c_of(tyre_high), hottest_run, ArcadeCar.TYRE_WINDOW_HIGH_C - ArcadeCar.tyre_c_of(tyre_high), ArcadeCar.TYRE_WINDOW_HIGH_C, ArcadeCar.tyre_c_of(tyre_low), coldest_run, ArcadeCar.tyre_c_of(tyre_low) - ArcadeCar.TYRE_WINDOW_LOW_C, ArcadeCar.TYRE_WINDOW_LOW_C, ArcadeCar.brake_c_of(brake_high), hottest_brake_run, ArcadeCar.BRAKE_FADE_START_C - ArcadeCar.brake_c_of(brake_high), ArcadeCar.BRAKE_FADE_START_C],
	)


## The tyres' heat: a donut (full throttle, full lock, the aids off) from the
## operating temperature has the rears climbing tick by tick, the rise each
## tick exactly the heat in less the cooling over the lump, and over the
## window in tens of seconds - the fronts, rolling, hardly warm; and a
## handbrake slide from 100 km/h heats the locked rears (the slide is their
## work) and puts no work into their discs past the tick the lever bites (a
## locked wheel's brake does none), while the fronts, rolling free, get none
## of either.
func _check_tyre_heat(car: ArcadeCar) -> void:
	var tick := 1.0 / Engine.physics_ticks_per_second
	car.reset_to_spawn()
	await _step(SETTLE_FRAMES)
	car.tcs_on = false
	car.sc_on = false
	car.set_driver_input(1.0, 0.0, 1.0)
	var over_tick := -1
	var wired := true
	var climbs := true
	var last := car.rear_tyre_temp
	var front_rise_start := car.front_tyre_temp
	var high := ArcadeCar.tyre_temp_of_c(ArcadeCar.TYRE_WINDOW_HIGH_C)
	for frame in DONUT_MAX_FRAMES:
		var before := car.rear_tyre_temp
		var airflow := absf(car.forward_speed)
		await physics_frame
		# The tick's heat in and its cooling (the airflow the tick began
		# with) over the lump: what the setter let through.
		var expected := before + (car._rear_tyre_heat_w - ArcadeCar.tyre_cooling_w(before, airflow)) * tick / (ArcadeCar.TYRE_HEAT_CAPACITY * ArcadeCar.TYRE_SPAN_K)
		wired = wired and absf(car.rear_tyre_temp - clampf(expected, 0.0, ArcadeCar.TYRE_MAX_TEMP)) < WIRING_TOLERANCE
		if frame % 60 == 59:
			climbs = climbs and car.rear_tyre_temp > last
			last = car.rear_tyre_temp
		if over_tick < 0 and car.rear_tyre_temp > high:
			over_tick = frame + 1
			break
	var front_rise := car.front_tyre_temp - front_rise_start
	var rear_c := ArcadeCar.tyre_c_of(car.rear_tyre_temp)
	var faded := ArcadeCar.tyre_grip_factor(car.rear_tyre_temp) < 1.0
	car.clear_driver_input()
	car.tcs_on = true
	car.sc_on = true
	# The handbrake slide.
	car.reset_to_spawn()
	await _step(SETTLE_FRAMES)
	car.set_driver_input(1.0, 0.0, 0.0)
	while car.speed_kmh < 100.0:
		await physics_frame
	var rear_before := car.rear_tyre_temp
	var front_before := car.front_tyre_temp
	var from_kmh := car.speed_kmh
	car.set_driver_input(0.0, 0.0, 0.0, true)
	var bite_j := 0.0
	var rear_disc_w := 0.0
	var rear_slip_j := 0.0
	var locked := true
	for frame in HANDBRAKE_FRAMES:
		await physics_frame
		if frame == 0:
			# The tick the lever bites the wheels are still turning: the
			# shoes' one tick of work. From the next, the wheels stand.
			bite_j = car._rear_brake_heat_w * tick
		else:
			rear_disc_w = maxf(rear_disc_w, car._rear_brake_heat_w)
		rear_slip_j += car._rear_tyre_heat_w * tick
		locked = locked and car.rear_omega == 0.0
	var rear_rise := car.rear_tyre_temp - rear_before
	var front_change := car.front_tyre_temp - front_before
	var slid_kmh := car.speed_kmh
	car.clear_driver_input()
	car.reset_to_spawn()
	await _step(5)
	_check(
		over_tick > 0 and wired and climbs and faded and front_rise * ArcadeCar.TYRE_SPAN_K < 5.0
			and locked and rear_rise > 0.0 and rear_disc_w == 0.0 and rear_slip_j > 0.0 and front_change < 0.0 and slid_kmh < from_kmh,
		"tyre heat: a donut from operating has the rears over the %.0f C window edge in %.1f s (%.1f C, the grip fading; every tick's rise the heat in less the cooling over the lump to 0.006 K, the fronts up %.1f K meanwhile); a %.0f s handbrake slide from %.0f km/h heats the locked rears %.1f K (%.0f kJ of the slide's work into them, %.1f kJ into their discs on the tick the lever bit and none after) and cools the rolling fronts %.1f K, %.0f km/h at the end" % [ArcadeCar.TYRE_WINDOW_HIGH_C, over_tick * tick, rear_c, front_rise * ArcadeCar.TYRE_SPAN_K, HANDBRAKE_FRAMES * tick, from_kmh, rear_rise * ArcadeCar.TYRE_SPAN_K, rear_slip_j / 1000.0, bite_j / 1000.0, -front_change * ArcadeCar.TYRE_SPAN_K, slid_kmh],
	)


## The tyres' cooling: on the model alone a hot tyre sheds more at speed than
## standing (the airflow's line, the standing term alone at rest, nothing at
## the air's temperature), and in the scene a hot rear tyre coasting from
## 100 km/h falls tick by tick - by the cooling less the rolling heat over
## the lump (coasting: flat out, a gear change's flare of wheelspin would
## warm it for a tick).
func _check_tyre_cooling(car: ArcadeCar) -> void:
	var tick := 1.0 / Engine.physics_ticks_per_second
	var hot := ArcadeCar.tyre_temp_of_c(HOT_TYRE_C)
	var over := HOT_TYRE_C - ArcadeCar.COOLANT_AMBIENT_C
	var standing := ArcadeCar.tyre_cooling_w(hot, 0.0)
	var at_speed := ArcadeCar.tyre_cooling_w(hot, RECOVERY_CRUISE)
	var model_ok := is_equal_approx(standing, ArcadeCar.TYRE_COOLING_STILL * over) and is_equal_approx(at_speed, (ArcadeCar.TYRE_COOLING_STILL + ArcadeCar.TYRE_COOLING_AIRFLOW * RECOVERY_CRUISE) * over) \
		and at_speed > standing and ArcadeCar.tyre_cooling_w(0.0, RECOVERY_CRUISE) == 0.0
	car.reset_to_spawn()
	await _step(SETTLE_FRAMES)
	car.set_driver_input(1.0, 0.0, 0.0)
	while car.speed_kmh < 100.0:
		await physics_frame
	car.rear_tyre_temp = hot
	car.set_driver_input(0.0, 0.0, 0.0)
	var falls := true
	var wired := true
	var start := car.rear_tyre_temp
	for frame in 120:
		var before := car.rear_tyre_temp
		var airflow := absf(car.forward_speed)
		await physics_frame
		var expected := before + (car._rear_tyre_heat_w - ArcadeCar.tyre_cooling_w(before, airflow)) * tick / (ArcadeCar.TYRE_HEAT_CAPACITY * ArcadeCar.TYRE_SPAN_K)
		wired = wired and absf(car.rear_tyre_temp - expected) < WIRING_TOLERANCE
		falls = falls and car.rear_tyre_temp < before
	var fell := (start - car.rear_tyre_temp) * ArcadeCar.TYRE_SPAN_K
	var speed := car.speed_kmh
	car.clear_driver_input()
	car.reset_to_spawn()
	await _step(5)
	_check(
		model_ok and falls and wired and fell > 0.0,
		"tyre cooling: a tyre at %.0f C sheds %.0f W standing and %.0f W at %.0f m/s (nothing at the air's temperature); coasting from 100 km/h (%.0f km/h after) a rear tyre at %.0f C falls every tick, %.2f K in 2 s, each tick the cooling less the rolling heat over the lump (to 0.006 K)" % [HOT_TYRE_C, standing, at_speed, RECOVERY_CRUISE, speed, HOT_TYRE_C, fell],
	)


## The warm-up on the model alone (_advance_tyres, tick by tick at the
## suite's tick) at a steady CRUISE_SPEED: the rolling resistance's heat
## (COAST_DECEL x the mass x the speed, the axle's share by its static load)
## and the airflow's cooling. Both axles climb from the air's temperature
## without a dip, are in the window within the minutes stated, and settle
## inside it - the fronts, with less of the load, cooler than the rears.
func _check_warm_up(car: ArcadeCar) -> void:
	var tick := 1.0 / Engine.physics_ticks_per_second
	var rolling_w := ArcadeCar.COAST_DECEL * car.total_mass() * CRUISE_SPEED
	var front_w := rolling_w * (1.0 - ArcadeCar.REAR_WEIGHT_FRACTION)
	var rear_w := rolling_w * ArcadeCar.REAR_WEIGHT_FRACTION
	var low := ArcadeCar.tyre_temp_of_c(ArcadeCar.TYRE_WINDOW_LOW_C)
	var high := ArcadeCar.tyre_temp_of_c(ArcadeCar.TYRE_WINDOW_HIGH_C)
	car.reset_to_spawn()
	car.front_tyre_temp = 0.0
	car.rear_tyre_temp = 0.0
	var monotonic := true
	var front_tick := -1
	var rear_tick := -1
	var last_front := 0.0
	var last_rear := 0.0
	var a_minute_ago := Vector2.ZERO
	var ticks_in_a_minute := int(60.0 / tick)
	for frame in WARM_UP_WATCH_FRAMES:
		car._advance_tyres(front_w, rear_w, CRUISE_SPEED, tick)
		monotonic = monotonic and car.front_tyre_temp >= last_front and car.rear_tyre_temp >= last_rear
		last_front = car.front_tyre_temp
		last_rear = car.rear_tyre_temp
		if front_tick < 0 and car.front_tyre_temp >= low:
			front_tick = frame + 1
		if rear_tick < 0 and car.rear_tyre_temp >= low:
			rear_tick = frame + 1
		if frame == WARM_UP_WATCH_FRAMES - ticks_in_a_minute - 1:
			a_minute_ago = Vector2(car.front_tyre_temp, car.rear_tyre_temp)
	var settled_front := car.front_tyre_temp
	var settled_rear := car.rear_tyre_temp
	var front_minutes := front_tick * tick / 60.0
	var rear_minutes := rear_tick * tick / 60.0
	car.reset_to_spawn()
	_check(
		monotonic and front_tick > 0 and rear_tick > 0 and front_minutes <= WARM_UP_MAX_MINUTES and rear_minutes <= WARM_UP_MAX_MINUTES
			and settled_front > low and settled_front < high and settled_rear > low and settled_rear < high and settled_rear > settled_front
			and absf(settled_front - a_minute_ago.x) < SETTLED_TOLERANCE and absf(settled_rear - a_minute_ago.y) < SETTLED_TOLERANCE
			and car.front_tyre_temp == 1.0 and car.rear_tyre_temp == 1.0,
		"warm-up: at a steady %.0f m/s (%.1f kW of rolling heat, %.2f kW of it on the fronts, %.2f on the rears) both axles climb from %.0f C without a dip, the rears are in the window (%.0f C) after %.1f min and the fronts after %.1f min (at most %.0f), and they settle at %.1f C (front) and %.1f C (rear), inside it; a reset is the warm tyres again" % [CRUISE_SPEED, rolling_w / 1000.0, front_w / 1000.0, rear_w / 1000.0, ArcadeCar.COOLANT_AMBIENT_C, ArcadeCar.TYRE_WINDOW_LOW_C, rear_minutes, front_minutes, WARM_UP_MAX_MINUTES, ArcadeCar.tyre_c_of(settled_front), ArcadeCar.tyre_c_of(settled_rear)],
	)


## In the scene: from the air's temperature, laps of hard mixed driving (flat
## out, a dab of brake, a corner to alternate sides) have both axles in the
## window within the laps given - the minute or two the model is calibrated
## on - and the grip on the way there is measurably under its own.
func _check_mixed_driving(car: ArcadeCar) -> void:
	var tick := 1.0 / Engine.physics_ticks_per_second
	var low := ArcadeCar.tyre_temp_of_c(ArcadeCar.TYRE_WINDOW_LOW_C)
	car.reset_to_spawn()
	await _step(SETTLE_FRAMES)
	car.front_tyre_temp = 0.0
	car.rear_tyre_temp = 0.0
	var first_lap_factor := 1.0
	var front_tick := -1
	var rear_tick := -1
	var frame := 0
	var side := 1.0
	var laps := 0
	while laps < MIXED_MAX_LAPS and (front_tick < 0 or rear_tick < 0):
		for phase: Array in [[1.0, 0.0, 0.0, MIXED_THROTTLE_FRAMES], [0.0, 0.6, 0.0, MIXED_BRAKE_FRAMES], [0.5, 0.0, CORNER_STEER * side, MIXED_CORNER_FRAMES]]:
			car.set_driver_input(phase[0], phase[1], phase[2])
			for i in phase[3]:
				await physics_frame
				frame += 1
				if laps == 0:
					first_lap_factor = minf(first_lap_factor, minf(ArcadeCar.tyre_grip_factor(car.front_tyre_temp), ArcadeCar.tyre_grip_factor(car.rear_tyre_temp)))
				if front_tick < 0 and car.front_tyre_temp >= low:
					front_tick = frame
				if rear_tick < 0 and car.rear_tyre_temp >= low:
					rear_tick = frame
		side = -side
		laps += 1
	car.clear_driver_input()
	var front_c := ArcadeCar.tyre_c_of(car.front_tyre_temp)
	var rear_c := ArcadeCar.tyre_c_of(car.rear_tyre_temp)
	car.reset_to_spawn()
	await _step(5)
	_check(
		front_tick > 0 and rear_tick > 0 and first_lap_factor < 1.0 and first_lap_factor >= ArcadeCar.TYRE_COLD_GRIP,
		"mixed driving: from the air's temperature, laps of flat out, brake and a corner have the fronts in the window after %.0f s and the rears after %.0f s (%d laps of %.0f s; %.1f and %.1f C at the end), the grip on the first lap down to %.3f of itself" % [front_tick * tick, rear_tick * tick, laps, (MIXED_THROTTLE_FRAMES + MIXED_BRAKE_FRAMES + MIXED_CORNER_FRAMES) * tick, front_c, rear_c, first_lap_factor],
	)


## The grip: the factor's own numbers (TYRE_COLD_GRIP at the air, halfway to
## the edge halfway, exactly 1 at both edges and at operating, the fade over
## the upper edge, the floor at the ceiling); and in the scene, cold tyres
## stop the car from 90 km/h measurably longer than warm ones and hold
## measurably less in the same corner, warm ones stop it in the certified
## metres, and overheated ones stop it measurably longer again.
func _check_grip(car: ArcadeCar) -> void:
	var at_air := ArcadeCar.tyre_grip_factor(0.0)
	var halfway := ArcadeCar.tyre_grip_factor(ArcadeCar.tyre_temp_of_c((ArcadeCar.COOLANT_AMBIENT_C + ArcadeCar.TYRE_WINDOW_LOW_C) / 2.0))
	var over_c := ArcadeCar.TYRE_WINDOW_HIGH_C + 20.0
	var over := ArcadeCar.tyre_grip_factor(ArcadeCar.tyre_temp_of_c(over_c))
	var at_ceiling := ArcadeCar.tyre_grip_factor(ArcadeCar.TYRE_MAX_TEMP)
	var factor_ok := at_air == ArcadeCar.TYRE_COLD_GRIP and is_equal_approx(halfway, (ArcadeCar.TYRE_COLD_GRIP + 1.0) / 2.0) \
		and is_equal_approx(over, 1.0 - ArcadeCar.TYRE_FADE_RATE * 20.0) and over < 1.0 and at_ceiling == ArcadeCar.TYRE_FADE_FLOOR \
		and ArcadeCar.tyre_grip_factor(1.0) == 1.0
	var warm := await _stop(car, 1.0, 0.0)
	var cold := await _stop(car, 0.0, 0.0)
	var hot := await _stop(car, ArcadeCar.tyre_temp_of_c(HOT_TYRE_C), 0.0)
	var warm_corner := await _corner(car, 1.0)
	var cold_corner := await _corner(car, 0.0)
	var stops_ok: bool = cold.distance_m > warm.distance_m * COLD_STOP_MIN_LONGER and hot.distance_m > warm.distance_m * COLD_STOP_MIN_LONGER \
		and cold.ticks > warm.ticks and absf(cold.from_ms - warm.from_ms) < 0.01
	var corner_ok: bool = cold_corner.lateral_g < warm_corner.lateral_g * COLD_CORNER_MIN_LESS and cold_corner.lateral_g > 0.0
	_check(
		factor_ok and stops_ok and corner_ok,
		"grip: the factor is %.2f at the air's temperature, %.3f halfway to the window, exactly 1 at operating and both edges, %.2f at %.0f C, %.2f at the ceiling; from %.1f m/s warm tyres stop the car in %.2f m, cold ones in %.2f m (%.0f %% longer) and tyres at %.0f C in %.2f m; the corner holds %.2f g warm and %.2f g cold" % [at_air, halfway, over, over_c, at_ceiling, warm.from_ms, warm.distance_m, cold.distance_m, (cold.distance_m / warm.distance_m - 1.0) * 100.0, HOT_TYRE_C, hot.distance_m, warm_corner.lateral_g, cold_corner.lateral_g],
	)


## The brakes' heat: a stop from 90 km/h warms both discs, each by its work
## over its capacity (the front's share of the car's energy by the bias and
## what the ABS lets through, the rear's with the engine's inertia to slow
## on top: the work is what _advance_axle read off the wheels), the rise
## each tick exactly the work in over the lump; on the model alone a hot disc
## sheds more at speed than standing and nothing at the air's; and a red-hot
## front disc on a cruise is back under the fade line in the minutes stated.
func _check_brake_heat(car: ArcadeCar) -> void:
	var tick := 1.0 / Engine.physics_ticks_per_second
	car.reset_to_spawn()
	await _step(SETTLE_FRAMES)
	car.set_driver_input(1.0, 0.0, 0.0)
	while car.speed_kmh < STOP_FROM_KMH:
		await physics_frame
	var energy_j := 0.5 * car.total_mass() * car.forward_speed * car.forward_speed
	car.set_driver_input(0.0, 1.0, 0.0)
	var front_j := 0.0
	var rear_j := 0.0
	var wired := true
	var ticks := 0
	while car.speed_kmh > STOPPED_KMH and ticks < 600:
		var before := car.front_brake_temp
		var airflow := absf(car.forward_speed)
		await physics_frame
		ticks += 1
		front_j += car._front_brake_heat_w * tick
		rear_j += car._rear_brake_heat_w * tick
		var expected := before + (car._front_brake_heat_w - ArcadeCar.brake_cooling_w(before, airflow)) * tick / (ArcadeCar.BRAKE_HEAT_CAPACITY * ArcadeCar.BRAKE_SPAN_K)
		wired = wired and absf(car.front_brake_temp - expected) < WIRING_TOLERANCE
	var front_rise := car.front_brake_temp * ArcadeCar.BRAKE_SPAN_K
	var rear_rise := car.rear_brake_temp * ArcadeCar.BRAKE_SPAN_K
	var work_ok := front_j > 0.0 and rear_j > 0.0 and front_j + rear_j < energy_j and front_j + rear_j > 0.7 * energy_j
	car.clear_driver_input()
	var hot := ArcadeCar.brake_temp_of_c(HOT_BRAKE_C)
	var over := HOT_BRAKE_C - ArcadeCar.COOLANT_AMBIENT_C
	var standing := ArcadeCar.brake_cooling_w(hot, 0.0)
	var at_speed := ArcadeCar.brake_cooling_w(hot, RECOVERY_CRUISE)
	var model_ok := is_equal_approx(standing, ArcadeCar.BRAKE_COOLING_STILL * over) and is_equal_approx(at_speed, (ArcadeCar.BRAKE_COOLING_STILL + ArcadeCar.BRAKE_COOLING_AIRFLOW * RECOVERY_CRUISE) * over) \
		and at_speed > standing and ArcadeCar.brake_cooling_w(0.0, RECOVERY_CRUISE) == 0.0
	# The recovery on the model alone: from red hot to the fade line at the
	# cruise, no brake touched.
	car.front_brake_temp = hot
	car.rear_brake_temp = 0.0
	var recovery_ticks := 0
	var monotonic := true
	var last := car.front_brake_temp
	while car.front_brake_temp > 1.0 and recovery_ticks < int(RECOVERY_MAX_MINUTES * 60.0 / tick):
		car._advance_brakes(0.0, 0.0, RECOVERY_CRUISE, tick)
		monotonic = monotonic and car.front_brake_temp < last
		last = car.front_brake_temp
		recovery_ticks += 1
	var recovery_minutes := recovery_ticks * tick / 60.0
	var recovered := car.front_brake_temp <= 1.0 and car.rear_brake_temp == 0.0
	car.reset_to_spawn()
	await _step(5)
	_check(
		wired and work_ok and front_rise > 0.0 and rear_rise > 0.0 and model_ok and recovered and monotonic and recovery_minutes < RECOVERY_MAX_MINUTES,
		"brake heat: a stop from %.0f km/h (%.0f kJ) puts %.0f kJ into the front discs and %.0f kJ into the rears (the wheels' work, the rest the drag's and the tyres'), %.1f K and %.1f K on them, every tick the work in over the lump; a disc at %.0f C sheds %.0f W standing and %.0f W at %.0f m/s (nothing at the air's); from %.0f C a front disc is back under the %.0f C fade line after %.1f min of that cruise, falling all the way (at most %.0f min)" % [STOP_FROM_KMH, energy_j / 1000.0, front_j / 1000.0, rear_j / 1000.0, front_rise, rear_rise, HOT_BRAKE_C, standing, at_speed, RECOVERY_CRUISE, HOT_BRAKE_C, ArcadeCar.BRAKE_FADE_START_C, recovery_minutes, RECOVERY_MAX_MINUTES],
	)


## The fade: hot brakes stop the car from 90 km/h measurably longer than
## cold ones (the fade's own number at the temperature, the torque scaled by
## it), a string of hard stops in a row brings the fade on by itself (exactly
## 1 for the first, under 1 by the last, the discs climbing every stop and
## never over the ceiling), the fade never goes under its floor, and brakes at
## the ceiling still stop the car, in more metres - nothing dies.
func _check_brake_fade(car: ArcadeCar) -> void:
	var cold := await _stop(car, 1.0, 0.0)
	var hot := await _stop(car, 1.0, ArcadeCar.brake_temp_of_c(HOT_BRAKE_C))
	var ceiling := await _stop(car, 1.0, ArcadeCar.BRAKE_MAX_TEMP)
	var hot_fade := ArcadeCar.brake_fade(ArcadeCar.brake_temp_of_c(HOT_BRAKE_C))
	var fade_expected := 1.0 - ArcadeCar.BRAKE_FADE_RATE * (HOT_BRAKE_C - ArcadeCar.BRAKE_FADE_START_C)
	var floor_fade := ArcadeCar.brake_fade(ArcadeCar.BRAKE_MAX_TEMP)
	var fade_ok := is_equal_approx(hot_fade, fade_expected) and hot_fade < 1.0 and floor_fade == ArcadeCar.BRAKE_FADE_FLOOR and floor_fade < hot_fade \
		and ArcadeCar.brake_fade(100.0) == ArcadeCar.BRAKE_FADE_FLOOR
	var stops_ok: bool = hot.distance_m > cold.distance_m and ceiling.distance_m > hot.distance_m and ceiling.ticks < 600 and ceiling.stopped \
		and ceiling.distance_m < cold.distance_m / ArcadeCar.BRAKE_FADE_FLOOR * 1.2
	# The string of stops: back up to speed straight after each one.
	car.reset_to_spawn()
	await _step(SETTLE_FRAMES)
	var first_fade := -1.0
	var last_fade := 1.0
	var climbs := true
	var over_ceiling := false
	var last_front := car.front_brake_temp
	var first_ticks := 0
	var last_ticks := 0
	var peak_c := 0.0
	for stop in FADE_STOPS:
		car.set_driver_input(1.0, 0.0, 0.0)
		while car.speed_kmh < STOP_FROM_KMH:
			await physics_frame
		var fade_now := ArcadeCar.brake_fade(car.front_brake_temp)
		if stop == 0:
			first_fade = fade_now
		last_fade = fade_now
		car.set_driver_input(0.0, 1.0, 0.0)
		var ticks := 0
		while car.speed_kmh > STOPPED_KMH and ticks < 600:
			await physics_frame
			ticks += 1
			over_ceiling = over_ceiling or car.front_brake_temp > ArcadeCar.BRAKE_MAX_TEMP or car.rear_brake_temp > ArcadeCar.BRAKE_MAX_TEMP
		if stop == 0:
			first_ticks = ticks
		last_ticks = ticks
		climbs = climbs and car.front_brake_temp > last_front
		last_front = car.front_brake_temp
		peak_c = maxf(peak_c, ArcadeCar.brake_c_of(car.front_brake_temp))
	car.clear_driver_input()
	car.reset_to_spawn()
	await _step(5)
	_check(
		fade_ok and stops_ok and first_fade == 1.0 and last_fade < 1.0 and last_fade >= ArcadeCar.BRAKE_FADE_FLOOR and climbs and not over_ceiling and last_ticks > first_ticks,
		"brake fade: at %.0f C the fade is %.2f and the stop from %.1f m/s %.2f m to the cold %.2f m; at the %.0f C ceiling the fade is its floor %.2f and the car still stops, in %.2f m; %d hard stops in a row have the front discs at %.0f C, climbing every stop and never over the ceiling, the fade exactly 1 for the first and %.3f for the last (%d ticks to the first stop, %d to the last)" % [HOT_BRAKE_C, hot_fade, cold.from_ms, hot.distance_m, cold.distance_m, ArcadeCar.BRAKE_MAX_C, floor_fade, ceiling.distance_m, FADE_STOPS, peak_c, last_fade, first_ticks, last_ticks],
	)


## The handbrake is the lever's: a handbrake slide from 100 km/h with the
## rear discs at the ceiling is the slide with them at the air's temperature
## to the bit, tick for tick - the speed, the yaw and the rear wheel speed the
## same numbers - and so is the ABS's hold with the discs anywhere under the
## line (the certified check has it): the fade is on the pedal's torque and
## on nothing else.
func _check_handbrake_untouched(car: ArcadeCar) -> void:
	var cold := await _handbrake_slide(car, 0.0)
	var hot := await _handbrake_slide(car, ArcadeCar.BRAKE_MAX_TEMP)
	var identical: bool = cold.speeds == hot.speeds and cold.yaws == hot.yaws and cold.rears == hot.rears and cold.speeds.size() == HANDBRAKE_FRAMES
	_check(
		identical and cold.hold_seen and hot.hold_seen,
		"handbrake: a %.0f s handbrake slide from 100 km/h with the rear discs at the %.0f C ceiling is the slide with them at the air's to the bit on all %d ticks (speed, yaw rate and rear wheel speed; the lever's hold seen letting go in both), %.0f km/h at the end" % [HANDBRAKE_FRAMES / float(Engine.physics_ticks_per_second), ArcadeCar.BRAKE_MAX_C, HANDBRAKE_FRAMES, cold.end_kmh],
	)


## The HUD's two bars follow the hotter axle each, from the left, in the
## coolant bar's idiom: the tyre bar blue cold, grey in the window, red over
## it and brighter red hotter; the brake bar grey under the fade line, red
## from it, brighter red from red hot; both hidden at 0 and for NaN, clamped
## at their end; their lines the car's own numbers; and the fuel, battery
## and coolant bars left alone.
func _check_hud_bars(car: ArcadeCar, hud: HUD, tyre_bar: ColorRect, brake_bar: ColorRect) -> void:
	var fuel_bar := hud.get_node("FuelBarBack/FuelBar") as ColorRect
	var battery_bar := hud.get_node("BatteryBarBack/BatteryBar") as ColorRect
	var coolant_bar := hud.get_node("CoolantBarBack/CoolantBar") as ColorRect
	car.reset_to_spawn()
	await _step(2)
	var start_ok := tyre_bar.visible and is_equal_approx(tyre_bar.scale.x, maxf(car.front_tyre_temp, car.rear_tyre_temp) / HUD.TYRE_BAR_FULL) and tyre_bar.color == HUD.TYRE_COLOR \
		and not brake_bar.visible
	var tyre_levels := {
		"cold": ArcadeCar.tyre_temp_of_c(30.0),
		"hot": ArcadeCar.tyre_temp_of_c(ArcadeCar.TYRE_WINDOW_HIGH_C + 2.0),
		"very hot": HUD.TYRE_VERY_HOT_FRACTION + 1.0 / ArcadeCar.TYRE_SPAN_K,
	}
	var tyre_colours := {"cold": HUD.TYRE_COLD_COLOR, "hot": HUD.TYRE_HOT_COLOR, "very hot": HUD.TYRE_VERY_HOT_COLOR}
	var brake_levels := {
		"warm": ArcadeCar.brake_temp_of_c(100.0),
		"hot": ArcadeCar.brake_temp_of_c(ArcadeCar.BRAKE_FADE_START_C + 2.0),
		"red hot": ArcadeCar.brake_temp_of_c(ArcadeCar.BRAKE_RED_HOT_C + 1.0),
	}
	var brake_colours := {"warm": HUD.BRAKE_HEAT_COLOR, "hot": HUD.BRAKE_HOT_COLOR, "red hot": HUD.BRAKE_VERY_HOT_COLOR}
	var followed := 0
	for level: String in tyre_levels:
		# The rear alone at the level, the front the cooler: the bar shows the
		# hotter axle. Cold: both, or the warm front would be the hotter.
		car.front_tyre_temp = tyre_levels[level] if level == "cold" else 1.0
		car.rear_tyre_temp = tyre_levels[level]
		await _step(2)
		if tyre_bar.visible and is_equal_approx(tyre_bar.scale.x, car.rear_tyre_temp / HUD.TYRE_BAR_FULL) and tyre_bar.color == tyre_colours[level] \
				and fuel_bar.color == HUD.FUEL_COLOR and battery_bar.color == HUD.BATTERY_COLOR and coolant_bar.color == HUD.COOLANT_COLOR:
			followed += 1
	for level: String in brake_levels:
		car.front_brake_temp = brake_levels[level]
		car.rear_brake_temp = 0.0
		await _step(2)
		if brake_bar.visible and is_equal_approx(brake_bar.scale.x, car.front_brake_temp / HUD.BRAKE_BAR_FULL) and brake_bar.color == brake_colours[level] \
				and fuel_bar.color == HUD.FUEL_COLOR and battery_bar.color == HUD.BATTERY_COLOR and coolant_bar.color == HUD.COOLANT_COLOR:
			followed += 1
	hud.set_tyre_bar(0.0)
	hud.set_brake_heat_bar(0.0)
	var hidden := not tyre_bar.visible and not brake_bar.visible
	hud.set_tyre_bar(NAN)
	hud.set_brake_heat_bar(NAN)
	hidden = hidden and not tyre_bar.visible and not brake_bar.visible
	hud.set_tyre_bar(9.0)
	hud.set_brake_heat_bar(9.0)
	var clamped := tyre_bar.visible and tyre_bar.scale.x == 1.0 and brake_bar.visible and brake_bar.scale.x == 1.0
	var lines_ok := is_equal_approx(HUD.TYRE_COLD_FRACTION, ArcadeCar.tyre_temp_of_c(ArcadeCar.TYRE_WINDOW_LOW_C)) \
		and is_equal_approx(HUD.TYRE_HOT_FRACTION, ArcadeCar.tyre_temp_of_c(ArcadeCar.TYRE_WINDOW_HIGH_C)) \
		and HUD.TYRE_HOT_FRACTION < HUD.TYRE_VERY_HOT_FRACTION and HUD.TYRE_VERY_HOT_FRACTION < HUD.TYRE_BAR_FULL \
		and is_equal_approx(HUD.TYRE_BAR_FULL, ArcadeCar.TYRE_MAX_TEMP) \
		and is_equal_approx(HUD.BRAKE_HOT_FRACTION, ArcadeCar.brake_temp_of_c(ArcadeCar.BRAKE_FADE_START_C)) \
		and is_equal_approx(HUD.BRAKE_VERY_HOT_FRACTION, ArcadeCar.brake_temp_of_c(ArcadeCar.BRAKE_RED_HOT_C)) \
		and is_equal_approx(HUD.BRAKE_BAR_FULL, ArcadeCar.BRAKE_MAX_TEMP)
	car.reset_to_spawn()
	await _step(2)
	_check(
		start_ok and followed == tyre_levels.size() + brake_levels.size() and hidden and clamped and lines_ok and tyre_bar.visible and tyre_bar.color == HUD.TYRE_COLOR and not brake_bar.visible,
		"HUD: the tyre bar and the brake bar follow the hotter axle (%d of %d levels to the bit: the tyres blue at 30 C, red at %.0f, brighter red at %.0f; the brakes grey at 100 C, red at %.0f, brighter red at %.0f), grey warm and empty cold respectively, hidden at 0 and for NaN, clamped at their ends (%.0f and %.0f C, the ceilings), the fuel, battery and coolant bars untouched; the tyre bar's lines are the window's edges and the brake bar's the fade line and red hot; and they are the car's again after a reset" % [followed, tyre_levels.size() + brake_levels.size(), ArcadeCar.TYRE_WINDOW_HIGH_C + 2.0, ArcadeCar.tyre_c_of(tyre_levels["very hot"]), ArcadeCar.BRAKE_FADE_START_C + 2.0, ArcadeCar.BRAKE_RED_HOT_C + 1.0, ArcadeCar.tyre_c_of(HUD.TYRE_BAR_FULL), ArcadeCar.brake_c_of(HUD.BRAKE_BAR_FULL)],
	)


## Nothing of it is ever NaN: a NaN tyre temperature is operating, a NaN brake
## temperature the air, inf the ceilings, -inf the air; NaN heat into a tick
## leaves them where they were; and after the limiter, a dry-tank stall, a
## handbrake slide and resets the whole state is finite and the car is in its
## certified thermal state again.
func _check_no_nan(car: ArcadeCar) -> void:
	var tick := 1.0 / Engine.physics_ticks_per_second
	car.front_tyre_temp = NAN
	car.rear_brake_temp = NAN
	var nan_ok := car.front_tyre_temp == 1.0 and car.rear_brake_temp == 0.0
	car.front_tyre_temp = INF
	car.rear_brake_temp = INF
	var inf_ok := car.front_tyre_temp == ArcadeCar.TYRE_MAX_TEMP and car.rear_brake_temp == ArcadeCar.BRAKE_MAX_TEMP
	car.front_tyre_temp = -INF
	car.rear_brake_temp = -INF
	var neg_inf_ok := car.front_tyre_temp == 0.0 and car.rear_brake_temp == 0.0
	car.front_tyre_temp = 1.0
	car.rear_tyre_temp = 1.0
	car.front_brake_temp = 0.0
	car.rear_brake_temp = 0.0
	car._advance_tyres(NAN, NAN, 0.0, tick)
	car._advance_brakes(NAN, NAN, NAN, tick)
	var nan_heat := car.front_tyre_temp == 1.0 and car.rear_tyre_temp == 1.0 and car.front_brake_temp == 0.0 and car.rear_brake_temp == 0.0
	# The limiter in neutral, flat out.
	car.reset_to_spawn()
	await _step(5)
	car.automatic = false
	car.shift_down()
	car.set_driver_input(1.0, 0.0, 0.0)
	var limited := false
	for frame in LIMITER_FRAMES:
		await physics_frame
		limited = limited or car.limiter_cutting
	car.clear_driver_input()
	# A stall on a dry tank with cold tyres and hot brakes.
	car.reset_to_spawn()
	await _step(5)
	car.front_tyre_temp = 0.0
	car.rear_tyre_temp = 0.0
	car.front_brake_temp = ArcadeCar.BRAKE_MAX_TEMP
	car.fuel_l = 0.0
	await _step(RUN_DOWN_FRAMES)
	var stalled := not car.engine_running and car.engine_rpm == 0.0
	# A handbrake slide with everything hot.
	car.reset_to_spawn()
	await _step(5)
	car.set_driver_input(1.0, 0.0, 0.0)
	while car.speed_kmh < 80.0:
		await physics_frame
	car.front_tyre_temp = ArcadeCar.TYRE_MAX_TEMP
	car.rear_tyre_temp = ArcadeCar.TYRE_MAX_TEMP
	car.front_brake_temp = ArcadeCar.BRAKE_MAX_TEMP
	car.rear_brake_temp = ArcadeCar.BRAKE_MAX_TEMP
	car.set_driver_input(0.0, 1.0, 0.5, true)
	await _step(HANDBRAKE_FRAMES)
	var abused_finite := is_finite(car.forward_speed) and is_finite(car.yaw_rate) and is_finite(car.rear_omega) and is_finite(car.front_omega) \
		and is_finite(car.front_tyre_temp) and is_finite(car.rear_tyre_temp) and is_finite(car.front_brake_temp) and is_finite(car.rear_brake_temp)
	car.clear_driver_input()
	car.reset_to_spawn()
	await _step(2)
	var finite := is_finite(car.front_tyre_temp) and is_finite(car.rear_tyre_temp) and is_finite(car.front_brake_temp) and is_finite(car.rear_brake_temp) \
		and is_finite(car._front_tyre_heat_w) and is_finite(car._rear_tyre_heat_w) and is_finite(car._front_brake_heat_w) and is_finite(car._rear_brake_heat_w) \
		and is_finite(ArcadeCar.tyre_grip_factor(car.front_tyre_temp)) and is_finite(ArcadeCar.brake_fade(car.front_brake_temp)) \
		and is_finite(ArcadeCar.tyre_cooling_w(car.rear_tyre_temp, car.forward_speed)) and is_finite(ArcadeCar.brake_cooling_w(car.rear_brake_temp, car.forward_speed)) \
		and is_finite(car.forward_speed) and is_finite(car.engine_rpm)
	_check(
		nan_ok and inf_ok and neg_inf_ok and nan_heat and limited and stalled and abused_finite and finite
			# Two ticks standing after the reset: the tyres a hair under
			# operating, in the window; the brakes at the air's.
			and car.front_tyre_temp > 0.999 and car.front_tyre_temp <= 1.0 and car.rear_tyre_temp == car.front_tyre_temp
			and car.front_brake_temp == 0.0 and car.rear_brake_temp == 0.0 and car.engine_running,
		"no NaN: a NaN tyre temperature is operating and a NaN brake temperature the air, inf the ceilings, -inf the air, NaN heat leaves them where they were; after %.0f s on the limiter, a dry-tank stall on cold tyres and hot brakes, a handbrake slide with everything at its ceiling and resets the whole state is finite and the car is on warm tyres and cold brakes again (tyres %.4f, brakes %.1f, %.0f rpm)" % [LIMITER_FRAMES * tick, car.front_tyre_temp, car.front_brake_temp, car.engine_rpm],
	)


## A reset, the car driven up to STOP_FROM_KMH, both tyres set to
## `tyre_temp` and both brakes to `brake_temp` there, and a full-pedal stop:
## { distance_m, ticks, from_ms, stopped, front_c: the front discs after }.
func _stop(car: ArcadeCar, tyre_temp: float, brake_temp: float) -> Dictionary:
	car.reset_to_spawn()
	await _step(SETTLE_FRAMES)
	car.set_driver_input(1.0, 0.0, 0.0)
	while car.speed_kmh < STOP_FROM_KMH:
		await physics_frame
	car.front_tyre_temp = tyre_temp
	car.rear_tyre_temp = tyre_temp
	car.front_brake_temp = brake_temp
	car.rear_brake_temp = brake_temp
	var from_ms := car.forward_speed
	var start := car.global_position
	car.set_driver_input(0.0, 1.0, 0.0)
	var ticks := 0
	while car.speed_kmh > STOPPED_KMH and ticks < 600:
		await physics_frame
		ticks += 1
	var seen := {
		"distance_m": (car.global_position - start).length(),
		"ticks": ticks,
		"from_ms": from_ms,
		"stopped": car.speed_kmh <= STOPPED_KMH,
		"front_c": ArcadeCar.brake_c_of(car.front_brake_temp),
	}
	car.clear_driver_input()
	car.reset_to_spawn()
	await _step(5)
	return seen


## A reset, the car driven up to CORNER_FROM_KMH, and CORNER_FRAMES ticks at
## CORNER_STEER with CORNER_THROTTLE, both tyres held at `tyre_temp` every
## tick: { lateral_g: the peak lateral acceleration [g] }.
func _corner(car: ArcadeCar, tyre_temp: float) -> Dictionary:
	car.reset_to_spawn()
	await _step(SETTLE_FRAMES)
	car.set_driver_input(1.0, 0.0, 0.0)
	while car.speed_kmh < CORNER_FROM_KMH:
		await physics_frame
	car.set_driver_input(CORNER_THROTTLE, 0.0, CORNER_STEER)
	var peak := 0.0
	for frame in CORNER_FRAMES:
		car.front_tyre_temp = tyre_temp
		car.rear_tyre_temp = tyre_temp
		await physics_frame
		peak = maxf(peak, absf(car.lateral_accel))
	car.clear_driver_input()
	car.reset_to_spawn()
	await _step(5)
	return {"lateral_g": peak / 9.8}


## A reset, the car driven up to 100 km/h, both rear discs set to
## `brake_temp`, and HANDBRAKE_FRAMES ticks with the lever pulled for the
## first third and let go for the rest: { speeds, yaws, rears: the tick by
## tick state, hold_seen: the lever's hold seen letting go, end_kmh }.
func _handbrake_slide(car: ArcadeCar, brake_temp: float) -> Dictionary:
	car.reset_to_spawn()
	await _step(SETTLE_FRAMES)
	car.set_driver_input(1.0, 0.0, 0.0)
	while car.speed_kmh < 100.0:
		await physics_frame
	car.front_brake_temp = brake_temp
	car.rear_brake_temp = brake_temp
	var speeds: Array[float] = []
	var yaws: Array[float] = []
	var rears: Array[float] = []
	var hold_seen := false
	for frame in HANDBRAKE_FRAMES:
		car.set_driver_input(0.0, 0.0, 0.3, frame < HANDBRAKE_FRAMES / 3)
		await physics_frame
		speeds.append(car.forward_speed)
		yaws.append(car.yaw_rate)
		rears.append(car.rear_omega)
		hold_seen = hold_seen or (car._rear_lock_recovery > 0.0 and car._rear_lock_recovery < 1.0)
	var seen := {"speeds": speeds, "yaws": yaws, "rears": rears, "hold_seen": hold_seen, "end_kmh": car.speed_kmh}
	car.clear_driver_input()
	car.reset_to_spawn()
	await _step(5)
	return seen


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
		print("TYRE/BRAKE THERMAL TEST PASSED")
	else:
		printerr("TYRE/BRAKE THERMAL TEST FAILED: %d check(s) failed" % _failures)
	quit(1 if _failures > 0 else 0)
