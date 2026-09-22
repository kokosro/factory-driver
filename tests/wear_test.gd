extends SceneTree
## Headless wear test. Run via tests/run_tests.sh, or:
##
##   godot --headless --path . --import
##   godot --headless --fixed-fps 60 --path . --script res://tests/wear_test.gd
##
## Loads the main scene and puts the car's wear (ArcadeCar, "Wear and aging")
## through what the kilometres and the driving do. First the gate: the car
## comes out of _ready with nothing worn - every share exactly 0 and every
## multiplier exactly 1 - and idles so through the settle; and the model's
## own numbers: the multipliers are exactly 1 under a hundredth of wear, step
## once a percent in a line to the floor and never under it, the config's
## rated lives, costs per kilojoule, multipliers and floors are the car's,
## and a life of no distance, a cost under zero, a multiplier under 1 and a
## floor outside its range are refused by name. Then each share from its own
## activity, wired to the tick's own quantities to the bit - the way the
## odometer counted plus what the driving cost over a gentle cruise, over
## the rated life: the clutch from a flat-out launch (its metres plus the
## slip energy's, the brakes their metres alone); the brakes from a full
## stop (each disc's work on top of the metres, the rears more on this car;
## the engine its revolutions at no load on the overrun); the tyres from a
## donut (the rears' slip work, three times over once they are over the
## window, the fronts a fraction); the engine from its own metres (the
## revolutions in top-gear metres times the load's style: flat out from
## rest, at the limiter in neutral at no load, idling warm, and idling
## overheated at full load and ten times over). Then the cruise: 1.5 km in
## top gear at 72 km/h wears every component its rated share - the style
## multiplier exactly 1 for the clutch, the brakes and the fronts, a hair
## over for the driven rears and the lightly loaded engine - and the second
## 750 m the same as the first (twice the kilometres, twice the wear). Then
## the worn car, measurably and boundedly different: worn brakes stop the
## car longer, a worn clutch bites softer and slips longer, worn tyres hold
## less in the same corner, a worn engine makes less torque, and past
## worn-out nothing gets worse - the floor holds. Then the store: the six
## shares go through a file of the test's own and come back to the bit in
## the one entry beside the rest, in the one write, an old file without them
## is a new car's and rounds through untouched, what is no share of a life
## is refused with the reason naming the car and the field, and a car that
## loads worn components starts with them. Then the reset: it keeps the wear
## to the bit (R does not un-wear) and tells the file nothing; a handling
## test's start hands out the new car. Last, nothing of it is ever NaN.
# was every share its rate times the tick's joules or radians, 15 launches
# or 46 stops to a percent -> the kilometres, and the driving on top (the
# user's 15:24 verdict, 2026-09-22: "the measurement is more in kilometers
# driven and how they were driven rather than how many times i can start
# the car from a hill").
## Exits 0 on success, 1 on any failed check.

const MAIN_SCENE := "res://scenes/main.tscn"
const CAR_CONFIG := "res://configs/cars/boxster_986.json"

## Physics frames to let the car settle on the ground at the start.
const SETTLE_FRAMES := 60

## Ticks of flat-out driving from rest the clutch's and the engine's wear are
## measured over (8 s: the launch and two or three upshifts).
const LAUNCH_FRAMES := 480

## The speed the stops are made from [km/h] and where a stop is over [km/h]
## (the tyre/brake thermal test's).
const STOP_FROM_KMH := 90.0
const STOPPED_KMH := 1.0

## Ticks of a donut (25 s: the rears are over the window in ~18 s, measured in
## the tyre/brake thermal test, so the last seconds wear at the abuse rate).
const DONUT_FRAMES := 1500

## Ticks the engine free-revs at the limiter in neutral (2 s), and ticks it
## idles overheated in neutral (2 s).
const NEUTRAL_REV_FRAMES := 120
const HOT_IDLE_FRAMES := 120

## How hot the overheat check holds the coolant [C]: ten degrees over the fade
## line (the thermal test's).
const HOT_C := 120.0

## The cruise: the speed held [km/h] in top gear (5th at 72 km/h is ~1900
## rpm), the ticks the hold settles for before the count starts (5 s), the
## metres counted (1.5 km, the pad's straight and the flat beyond it: a
## modest distance, the suite stays fast) and how many halves it is read in
## (the linearity: each half the same wear). The speed is held by a plain
## proportional throttle (CRUISE_THROTTLE_BASE plus CRUISE_THROTTLE_GAIN per
## km/h under the mark).
const CRUISE_KMH := 72.0
const CRUISE_SETTLE_FRAMES := 300
const CRUISE_M := 1500.0
const CRUISE_HALVES := 2
const CRUISE_THROTTLE_BASE := 0.15
const CRUISE_THROTTLE_GAIN := 0.1

## How far a cruise's style multiplier may sit over 1 where the physics puts
## a little on top of the metres: the driven rears' slip (a per-mille), the
## engine's light load and its wheels' slip (a fifth); and how far the two
## halves of the cruise may differ for those two (the road's swells shift the
## load), where the others' halves are the same metres to a tick.
const CRUISE_REAR_TYRE_TOLERANCE := 0.01
const CRUISE_ENGINE_TOLERANCE := 0.2
const CRUISE_HALVES_TOLERANCE := 0.1
const CRUISE_METRES_TOLERANCE := 0.005

## The corner the fresh and the worn grip are compared in (the tyre/brake
## thermal test's): the steer held at this share of the lock from 60 km/h with
## this much throttle for this many ticks (4 s), the peak lateral acceleration
## compared.
const CORNER_STEER := 0.5
const CORNER_THROTTLE := 0.3
const CORNER_FROM_KMH := 60.0
const CORNER_FRAMES := 240

## The most the engine's own metres come to a second at idle [m/s]: a
## generous bound on IDLE_RPM in top-gear metres (900 rpm x TAU / 60 x
## TOP_GEAR_M_PER_RAD is ~8.5 m/s), what an idling car's engine wears by.
const IDLE_M_PER_S := 10.0

## The wear the worn car is tried at (0..1): half, and worn out; and far past
## worn out, which the setters hold at WEAR_LIMIT.
const MID_WEAR := 0.5
const FULL_WEAR := 1.0
const PAST_WEAR := 5.0

## A hair over MID_WEAR, inside the same hundredth: the multiplier reads the
## wear at whole steps, so the same stop to the bit.
const MID_STEP_WEAR := 0.505

## How far a share may be from the sum of the tick quantities it is wired to,
## as a share of it: the same additions in another order.
const WIRING_TOLERANCE := 1.0e-9

## Where the store is tried out: a file of the test's own, in a tmp dir of the
## run's own, never the game's user://cars.json.
const TMP_DIR_PREFIX := "/tmp/fd-3AB-wear-"
var _store_dir := TMP_DIR_PREFIX + str(OS.get_process_id())
var _store_file := _store_dir + "/cars.json"

## Wear store: shares that have to come back to the bit, and the worn car a
## car is started with.
const STORE_HARD_WEAR := {
	"clutch": 0.0123456789012345, "brakes_front": 0.234567890123456, "brakes_rear": 0.345678901234567,
	"tyres_front": 0.456789012345678, "tyres_rear": 0.567890123456789, "engine": 0.678901234567890,
}
const STORE_WORN := {"clutch": 0.5, "brakes_front": 0.25, "brakes_rear": 0.2, "tyres_front": 0.3, "tyres_rear": 0.4, "engine": 0.15}

## The dashboard and the battery the one-write check saves beside the wear.
const STORE_DRIVER := {"tcs_on": false, "abs_on": true, "sc_on": false, "gearbox_mode": "eco", "automatic": false, "camera_view": 2}
const STORE_BATTERY := {"charge": 0.5, "capacity_wear": 0.1}

## The six shares on the car, in the store's order, and their fields.
const WEAR_FIELDS := ["clutch", "brakes_front", "brakes_rear", "tyres_front", "tyres_rear", "engine"]
const WEAR_PROPERTIES := ["clutch_wear", "front_brake_wear", "rear_brake_wear", "front_tyre_wear", "rear_tyre_wear", "engine_wear"]

var _failures := 0

## The wear as _ready left it, before a tick could touch it.
var _wear_at_start: Array[float] = []
var _factors_at_start: Array[float] = []


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
		_wear_at_start = _shares(car_at_ready)
		_factors_at_start = _factors(car_at_ready)
	await _step(SETTLE_FRAMES)

	var car := main.get_node_or_null("Car") as ArcadeCar
	var pad := main.get_node_or_null("TestPad") as TestPad
	if not _check(car != null and pad != null, "car and test pad exist"):
		_finish()
		return

	_check_suite_gate(car)
	_check_model_numbers()
	_check_validation()
	await _check_clutch(car)
	await _check_brakes(car)
	await _check_tyres(car)
	await _check_engine(car)
	await _check_cruise(car)
	await _check_worn_brakes(car)
	await _check_worn_clutch(car)
	await _check_worn_tyres(car)
	await _check_worn_engine(car)
	_check_store()
	await _check_car_loads(car)
	await _check_reset(car, pad)
	await _check_no_nan(car)

	_fresh(car)
	await _step(5)
	_finish()


## Nothing worn: the car came out of _ready with every share exactly 0 and
## every multiplier exactly 1, the store off, and idled so through the settle
## - an idling car moves nothing and wears nothing but its engine, which
## runs: its idle's revolutions in top-gear metres, a second of them.
# was "an idling car wears nothing", the engine's share exactly 0 too -> the
# engine by its revolutions (the user's 15:24 verdict).
func _check_suite_gate(car: ArcadeCar) -> void:
	var zero_at_start := _wear_at_start.size() == WEAR_FIELDS.size() and _all_equal(_wear_at_start, 0.0)
	var one_at_start := _factors_at_start.size() == 6 and _all_equal(_factors_at_start, 1.0)
	var shares := _shares(car)
	var idle_m := IDLE_M_PER_S * SETTLE_FRAMES / Engine.physics_ticks_per_second
	var still_zero := shares[0] == 0.0 and shares[1] == 0.0 and shares[2] == 0.0 and shares[3] == 0.0 and shares[4] == 0.0 and _all_equal(_factors(car), 1.0) and car._clutch_slip_w == 0.0
	var idled := shares[5] > 0.0 and shares[5] < 2.0 * idle_m / (ArcadeCar.ENGINE_LIFE_KM * 1000.0)
	_check(
		zero_at_start and one_at_start and still_zero and idled and not OdometerStore.enabled() and not car._odometer_kept,
		"suite: the car came out of _ready with nothing worn - all six shares exactly 0, the clutch's, the brakes', the tyres' and the engine's multipliers exactly 1 - the store off whatever %s holds, and after %d idling ticks still nothing but the engine's %.3f ppm of idling (under %.0f m of its own metres, the multipliers still exactly 1)" % [OdometerStore.PATH, SETTLE_FRAMES, shares[5] * 1.0e6, 2.0 * idle_m],
	)


## The model's own numbers: a multiplier is exactly 1 under a hundredth of
## wear, one step down per hundredth from there, in a line to the floor at
## worn out and never under it past that; the config's rated lives, costs
## per kilojoule, multipliers and floors are the car's; the curve's peak is
## what the engine's load is weighed against, and the top gear's metres per
## radian are what its revolutions count in.
func _check_model_numbers() -> void:
	var step := ArcadeCar.WEAR_EFFECT_STEP
	var floors := [ArcadeCar.CLUTCH_WEAR_FLOOR, ArcadeCar.BRAKE_WEAR_FLOOR, ArcadeCar.TYRE_WEAR_FLOOR, ArcadeCar.ENGINE_WEAR_FLOOR]
	var exact_one := true
	var steps := true
	var line := true
	var floored := true
	var monotone := true
	for floor: float in floors:
		exact_one = exact_one and ArcadeCar.wear_factor(0.0, floor) == 1.0 and ArcadeCar.wear_factor(step * 0.999, floor) == 1.0 and ArcadeCar.wear_factor(step - 1.0e-12, floor) == 1.0
		steps = steps and ArcadeCar.wear_factor(step, floor) < 1.0 and ArcadeCar.wear_factor(step, floor) == ArcadeCar.wear_factor(step * 1.5, floor) \
			and is_equal_approx(ArcadeCar.wear_factor(step, floor), 1.0 - step * (1.0 - floor))
		line = line and is_equal_approx(ArcadeCar.wear_factor(MID_WEAR, floor), 1.0 - MID_WEAR * (1.0 - floor))
		floored = floored and ArcadeCar.wear_factor(FULL_WEAR, floor) == floor and ArcadeCar.wear_factor(PAST_WEAR, floor) == floor and ArcadeCar.wear_factor(INF, floor) == floor
		var last := 1.0
		for i in 201:
			var factor := ArcadeCar.wear_factor(i * 0.005, floor)
			monotone = monotone and factor <= last and factor >= floor
			last = factor
	_check(
		exact_one and steps and line and floored and monotone and step > 0.0 and step < 0.1 and ArcadeCar.WEAR_LIMIT == 1.0,
		"model: a multiplier is exactly 1 under %.0f %% of wear, one step down per %.0f %% from there (%.4f at the first, the clutch), the line's %.3f at %.0f %%, the floor at worn out (clutch %.2f, brakes %.2f, tyres %.2f, engine %.2f), the floor still past it, never up and never under" % [step * 100.0, step * 100.0, ArcadeCar.wear_factor(step, ArcadeCar.CLUTCH_WEAR_FLOOR), ArcadeCar.wear_factor(MID_WEAR, ArcadeCar.CLUTCH_WEAR_FLOOR), MID_WEAR * 100.0, floors[0], floors[1], floors[2], floors[3]],
	)
	var config: Variant = JSON.parse_string(FileAccess.get_file_as_string(CAR_CONFIG))
	var wear: Dictionary = config.get("wear", {}) if config is Dictionary else {}
	# was the eleven rates, multipliers and floors -> the sixteen lives, costs
	# per kilojoule, multipliers and floors (the user's 15:24 verdict).
	var statics := {
		"clutch_life_km": ArcadeCar.CLUTCH_LIFE_KM, "clutch_slip_m_per_kj": ArcadeCar.CLUTCH_SLIP_M_PER_KJ, "clutch_floor": ArcadeCar.CLUTCH_WEAR_FLOOR,
		"brake_life_km": ArcadeCar.BRAKE_LIFE_KM, "brake_work_m_per_kj": ArcadeCar.BRAKE_WORK_M_PER_KJ, "brake_abuse": ArcadeCar.BRAKE_WEAR_ABUSE, "brake_floor": ArcadeCar.BRAKE_WEAR_FLOOR,
		"tyre_life_km_front": ArcadeCar.FRONT_TYRE_LIFE_KM, "tyre_life_km_rear": ArcadeCar.REAR_TYRE_LIFE_KM, "tyre_slip_m_per_kj": ArcadeCar.TYRE_SLIP_M_PER_KJ,
		"tyre_abuse": ArcadeCar.TYRE_WEAR_ABUSE, "tyre_floor": ArcadeCar.TYRE_WEAR_FLOOR,
		"engine_life_km": ArcadeCar.ENGINE_LIFE_KM, "engine_flat_out": ArcadeCar.ENGINE_FLAT_OUT, "engine_abuse": ArcadeCar.ENGINE_WEAR_ABUSE, "engine_floor": ArcadeCar.ENGINE_WEAR_FLOOR,
	}
	var read := 0
	for key: String in statics:
		if wear.has(key) and float(wear[key]) == statics[key]:
			read += 1
	var peak := 0.0
	for anchor: Vector2 in ArcadeCar.TORQUE_CURVE:
		peak = maxf(peak, anchor.y)
	var top_gear_m_per_rad: float = ArcadeCar.WHEEL_RADIUS / (ArcadeCar.GEAR_RATIOS[ArcadeCar.GEAR_RATIOS.size() - 1] * ArcadeCar.FINAL_DRIVE)
	_check(
		read == statics.size() and wear.size() == statics.size() and ArcadeCar.ENGINE_PEAK_TORQUE == peak and peak > 0.0
			and ArcadeCar.TOP_GEAR_M_PER_RAD == top_gear_m_per_rad and top_gear_m_per_rad > 0.0
			and ArcadeCar.CLUTCH_LIFE_KM > 0.0 and ArcadeCar.BRAKE_LIFE_KM > 0.0 and ArcadeCar.FRONT_TYRE_LIFE_KM > 0.0 and ArcadeCar.REAR_TYRE_LIFE_KM > 0.0 and ArcadeCar.ENGINE_LIFE_KM > 0.0
			and ArcadeCar.BRAKE_WEAR_ABUSE >= 1.0 and ArcadeCar.TYRE_WEAR_ABUSE >= 1.0 and ArcadeCar.ENGINE_WEAR_ABUSE >= 1.0 and ArcadeCar.ENGINE_FLAT_OUT >= 1.0,
		"model: all %d numbers of the config's wear table are the car's to the bit (the clutch's life %.0f km and %.1f m of it per kJ of slip; the pads' %.0f km and %.1f m per kJ of disc work, x%.0f over the fade line; the tyres' %.0f km front and %.0f km rear and %.1f m per kJ of slip work, x%.0f over the window; the engine's %.0f km, x%.0f flat out and x%.0f overheated); the engine's load is weighed against the curve's %.0f Nm peak and its revolutions count %.4f m each in top gear (the wheel's radius over the top ratio times the final drive)" % [statics.size(), ArcadeCar.CLUTCH_LIFE_KM, ArcadeCar.CLUTCH_SLIP_M_PER_KJ, ArcadeCar.BRAKE_LIFE_KM, ArcadeCar.BRAKE_WORK_M_PER_KJ, ArcadeCar.BRAKE_WEAR_ABUSE, ArcadeCar.FRONT_TYRE_LIFE_KM, ArcadeCar.REAR_TYRE_LIFE_KM, ArcadeCar.TYRE_SLIP_M_PER_KJ, ArcadeCar.TYRE_WEAR_ABUSE, ArcadeCar.ENGINE_LIFE_KM, ArcadeCar.ENGINE_FLAT_OUT, ArcadeCar.ENGINE_WEAR_ABUSE, ArcadeCar.ENGINE_PEAK_TORQUE, ArcadeCar.TOP_GEAR_M_PER_RAD],
	)


## The validation: a config without a wear table is a car, one with an empty
## table is a car, and a life of no distance, a cost under zero, an abuse
## multiplier under 1, a flat-out multiplier under 1, a floor of 0 or over 1
## and a key the schema does not know are each refused by name - by the
## validation's functions alone, never read into the running car.
# was a rate under zero -> a life of no distance and a cost under zero (the
# user's 15:24 verdict).
func _check_validation() -> void:
	var config: Variant = JSON.parse_string(FileAccess.get_file_as_string(CAR_CONFIG))
	if not _check(config is Dictionary and CarConfigValidation.validate(config, "boxster_986").is_empty(), "validation: the car's config passes with its wear table"):
		return
	var without: Dictionary = config.duplicate(true)
	without.erase("wear")
	var empty: Dictionary = config.duplicate(true)
	empty.wear = {}
	var one_floor: Dictionary = config.duplicate(true)
	one_floor.wear.tyre_floor = 1.0
	var bad: Dictionary = config.duplicate(true)
	bad.wear.clutch_life_km = 0.0
	bad.wear.tyre_slip_m_per_kj = -0.5
	bad.wear.brake_abuse = 0.5
	bad.wear.engine_flat_out = 0.5
	bad.wear.tyre_floor = 0.0
	bad.wear.engine_floor = 1.5
	bad.wear.clutch_abuse = 2.0
	var faults := CarConfigValidation.validate(bad, "worn")
	var named := 0
	for fault: String in faults:
		if fault.begins_with("worn: wear.clutch_life_km is") or fault.begins_with("worn: wear.tyre_slip_m_per_kj is") or fault.begins_with("worn: wear.brake_abuse is") \
				or fault.begins_with("worn: wear.engine_flat_out is") or fault.begins_with("worn: wear.tyre_floor is") \
				or fault.begins_with("worn: wear.engine_floor is") or fault == "worn: wear.clutch_abuse is not in the schema":
			named += 1
	var nan_life: Dictionary = config.duplicate(true)
	nan_life.wear.engine_life_km = NAN
	var nan_faults := CarConfigValidation.validate(nan_life, "nan")
	_check(
		CarConfigValidation.validate(without, "bare").is_empty() and CarConfigValidation.validate(empty, "empty").is_empty() and CarConfigValidation.validate(one_floor, "one").is_empty()
			and faults.size() == 7 and named == 7 and nan_faults.size() == 1 and nan_faults[0] == "nan: wear.engine_life_km is not a finite number"
			and ArcadeCar.CLUTCH_LIFE_KM > 0.0 and ArcadeCar.TYRE_SLIP_M_PER_KJ >= 0.0 and ArcadeCar.BRAKE_WEAR_ABUSE >= 1.0 and ArcadeCar.ENGINE_FLAT_OUT >= 1.0 and ArcadeCar.TYRE_WEAR_FLOOR > 0.0,
		"validation: a config without a wear table is a car, so is one with an empty table and one with a floor of 1; a life of no distance, a cost under zero, an abuse under 1, a flat-out multiplier under 1, a floor of 0, a floor over 1 and a key the schema does not know are refused by name (%d faults: %s); a NaN life is not a finite number; the running car kept its own" % [faults.size(), "; ".join(faults)],
	)


## The clutch wears by the metres and by its slips: a flat-out launch from
## rest through the upshifts costs it exactly the way the odometer counted
## plus the slip energy's metres of its life (CLUTCH_SLIP_M_PER_KJ), over its
## rated life; on a locked tick exactly the metres alone; the brakes, the
## pedal up, exactly their metres over theirs; the tyres roll and the engine
## turns under load, so they wear a little more (their own checks below). The
## launch's style multiplier - its metres of life over its metres of road -
## is well over 1.
# was exactly its rate times the slip energy, nothing while locked, the
# brakes exactly 0: 15 launches to a percent -> the metres and the slips over
# the rated life (the user's 15:24 verdict).
func _check_clutch(car: ArcadeCar) -> void:
	var tick := 1.0 / Engine.physics_ticks_per_second
	_fresh(car)
	await _step(SETTLE_FRAMES)
	var slip_j := 0.0
	var slip_m := 0.0
	var way_m := 0.0
	var expected := 0.0
	var brakes_expected := 0.0
	var locked_expected := 0.0
	var locked_wear := 0.0
	var slipping_ticks := 0
	var last := car.clutch_wear
	var shifts := 0
	var last_gear := car.gear
	car.set_driver_input(1.0, 0.0, 0.0)
	for frame in LAUNCH_FRAMES:
		await physics_frame
		var tick_slip_m := car._clutch_slip_w * tick * ArcadeCar.CLUTCH_SLIP_M_PER_KJ * 0.001
		slip_j += car._clutch_slip_w * tick
		slip_m += tick_slip_m
		way_m += car._wear_way_m
		expected += (car._wear_way_m + tick_slip_m) / (ArcadeCar.CLUTCH_LIFE_KM * 1000.0)
		brakes_expected += car._wear_way_m / (ArcadeCar.BRAKE_LIFE_KM * 1000.0)
		if car._clutch_slip_w > 0.0:
			slipping_ticks += 1
		else:
			locked_expected += car._wear_way_m / (ArcadeCar.CLUTCH_LIFE_KM * 1000.0)
			locked_wear += car.clutch_wear - last
		if car.gear != last_gear:
			shifts += 1
			last_gear = car.gear
		last = car.clutch_wear
	var speed := car.speed_kmh
	var others := _shares(car)
	var style := (way_m + slip_m) / way_m
	car.clear_driver_input()
	_fresh(car)
	await _step(5)
	_check(
		slip_j > 0.0 and slipping_ticks > 0 and slipping_ticks < LAUNCH_FRAMES and last > 0.0 and way_m > 0.0
			and absf(last / expected - 1.0) < WIRING_TOLERANCE and absf(locked_wear / locked_expected - 1.0) < WIRING_TOLERANCE and shifts >= 2
			and absf(others[1] / brakes_expected - 1.0) < WIRING_TOLERANCE and absf(others[2] / brakes_expected - 1.0) < WIRING_TOLERANCE
			and others[3] > 0.0 and others[4] > 0.0 and others[5] > 0.0 and style > 2.0
			and last < ArcadeCar.WEAR_EFFECT_STEP,
		"clutch: %.0f s flat out from rest (%d upshifts, %.0f km/h, %.0f m) slips the clutch %.1f kJ over %d ticks - %.0f m of its life on top of the %.0f m driven, a style of %.1f - and wears it %.2f ppm, the metres plus the slip's metres over its %.0f km life to the bit, the metres alone on the %d locked ticks; %.0f such launches to the first hundredth (was 15); the brakes wore exactly their %.2f ppm of metres, the tyres %.2f and %.2f ppm and the engine %.2f ppm meanwhile (rolling, turning under load)" % [LAUNCH_FRAMES * tick, shifts, speed, way_m, slip_j / 1000.0, slipping_ticks, slip_m, way_m, style, last * 1.0e6, ArcadeCar.CLUTCH_LIFE_KM, LAUNCH_FRAMES - slipping_ticks, ArcadeCar.WEAR_EFFECT_STEP / last, others[1] * 1.0e6, others[3] * 1.0e6, others[4] * 1.0e6, others[5] * 1.0e6],
	)


## The brakes wear by the metres and by their work: a full stop from 90 km/h
## costs each axle's pads exactly the way the odometer counted plus the
## work's metres of their life (BRAKE_WORK_M_PER_KJ; the rears' more on this
## car: the ABS holds the fronts at the tyres' limit, and the driven axle's
## discs slow the engine too), over the rated life; the engine wears exactly
## its own metres - the revolutions in top-gear metres times the load's
## style, the load all but gone on the overrun (the flywheel unloading into
## the braked driveline, the downshifts' catches) - a small share of the
## drive up to speed. The stop's style multiplier is well over 1.
# was exactly the rate times the work, 46 stops to a percent of the rears ->
# the metres and the work over the rated life (the user's 15:24 verdict).
func _check_brakes(car: ArcadeCar) -> void:
	var tick := 1.0 / Engine.physics_ticks_per_second
	_fresh(car)
	await _step(SETTLE_FRAMES)
	car.set_driver_input(1.0, 0.0, 0.0)
	while car.speed_kmh < STOP_FROM_KMH:
		await physics_frame
	var before := _shares(car)
	var from_kmh := car.speed_kmh
	var front_j := 0.0
	var rear_j := 0.0
	var way_m := 0.0
	var fade_ticks := 0
	var front_expected := 0.0
	var rear_expected := 0.0
	var engine_expected := 0.0
	var loaded_ticks := 0
	car.set_driver_input(0.0, 1.0, 0.0)
	var ticks := 0
	while car.speed_kmh > STOPPED_KMH and ticks < 600:
		await physics_frame
		ticks += 1
		front_j += car._front_brake_heat_w * tick
		rear_j += car._rear_brake_heat_w * tick
		way_m += car._wear_way_m
		if ArcadeCar.brake_fade(car.front_brake_temp) < 1.0 or ArcadeCar.brake_fade(car.rear_brake_temp) < 1.0:
			fade_ticks += 1
		front_expected += (car._wear_way_m + car._front_brake_heat_w * tick * ArcadeCar.BRAKE_WORK_M_PER_KJ * 0.001) / (ArcadeCar.BRAKE_LIFE_KM * 1000.0)
		rear_expected += (car._wear_way_m + car._rear_brake_heat_w * tick * ArcadeCar.BRAKE_WORK_M_PER_KJ * 0.001) / (ArcadeCar.BRAKE_LIFE_KM * 1000.0)
		var load_share := clampf(car.clutch_torque / ArcadeCar.ENGINE_PEAK_TORQUE, 0.0, 1.0)
		if load_share > 0.0:
			loaded_ticks += 1
		engine_expected += _engine_metres(car, tick, load_share) / (ArcadeCar.ENGINE_LIFE_KM * 1000.0)
	var after := _shares(car)
	var front_wear := after[1] - before[1]
	var rear_wear := after[2] - before[2]
	var engine_wear := after[5] - before[5]
	var clutch_wear := after[0] - before[0]
	var rear_style := rear_wear * ArcadeCar.BRAKE_LIFE_KM * 1000.0 / way_m
	car.clear_driver_input()
	_fresh(car)
	await _step(5)
	_check(
		car.speed_kmh <= STOPPED_KMH + 1.0 and front_j > 0.0 and rear_j > 0.0 and fade_ticks == 0 and way_m > 0.0
			and front_wear > 0.0 and rear_wear > 0.0 and absf(front_wear / front_expected - 1.0) < WIRING_TOLERANCE and absf(rear_wear / rear_expected - 1.0) < WIRING_TOLERANCE
			and loaded_ticks < ticks and absf(engine_wear / engine_expected - 1.0) < WIRING_TOLERANCE and engine_wear < 0.1 * before[5]
			and rear_style > 2.0 and rear_wear < ArcadeCar.WEAR_EFFECT_STEP,
		"brakes: a stop from %.0f km/h (%d ticks, %.0f m, the discs under the fade line throughout) gives the front discs %.0f kJ of work and the rears %.0f kJ (the driven axle's slow the engine too, the ABS holds the fronts at the tyres' limit) and wears them %.2f and %.2f ppm - the metres plus the work's metres over the pads' %.0f km life to the bit each, the rears' style %.1f; %.0f such stops to the rears' first hundredth (was 46); the engine wore %.3f ppm - exactly its revolutions in top-gear metres times the load's style, the crank loaded on %d of the ticks (the flywheel unloading into the braked driveline, the downshifts' catches) and free on the other %d, under a tenth of the %.2f ppm the drive up to speed cost; the clutch %.3f ppm through those downshifts" % [from_kmh, ticks, way_m, front_j / 1000.0, rear_j / 1000.0, front_wear * 1.0e6, rear_wear * 1.0e6, ArcadeCar.BRAKE_LIFE_KM, rear_style, ArcadeCar.WEAR_EFFECT_STEP / rear_wear, engine_wear * 1.0e6, loaded_ticks, ticks - loaded_ticks, before[5] * 1.0e6, clutch_wear * 1.0e6],
	)


## The tyres wear by the metres and by their slip work: a donut (full
## throttle, full lock, the aids off) costs the rears exactly the way the
## odometer counted plus the slip work's metres of their life
## (TYRE_SLIP_M_PER_KJ), three times over on every tick they are over the
## window, over their rated life; the fronts a fraction of it over theirs;
## the brakes do no work on any tick the pedal is off (the spinning car rolls
## backwards for a few ticks, where the throttle key is the brake: the
## driver's rule, and those ticks alone give them work) and wear exactly
## their metres plus that. The donut's style multiplier is well over 1.
# was exactly the rate times the tyres' heat, 35 donuts to a percent of the
# rears -> the metres and the slip work over the rated lives (the user's
# 15:24 verdict).
func _check_tyres(car: ArcadeCar) -> void:
	var tick := 1.0 / Engine.physics_ticks_per_second
	_fresh(car)
	await _step(SETTLE_FRAMES)
	car.tcs_on = false
	car.sc_on = false
	car.set_driver_input(1.0, 0.0, 1.0)
	var rear_expected := 0.0
	var front_expected := 0.0
	var front_brake_expected := 0.0
	var rear_brake_expected := 0.0
	var rear_j := 0.0
	var rear_m := 0.0
	var way_m := 0.0
	var hot_j := 0.0
	var hot_ticks := 0
	var pedal_ticks := 0
	var backwards_ticks := 0
	var off_pedal_brake_j := 0.0
	for frame in DONUT_FRAMES:
		await physics_frame
		if car.brake_pedal > 0.0:
			pedal_ticks += 1
		else:
			off_pedal_brake_j += (car._front_brake_heat_w + car._rear_brake_heat_w) * tick
		if car.forward_speed < 0.0:
			backwards_ticks += 1
		var rear_hot := ArcadeCar.tyre_c_of(car.rear_tyre_temp) > ArcadeCar.TYRE_WINDOW_HIGH_C
		var front_hot := ArcadeCar.tyre_c_of(car.front_tyre_temp) > ArcadeCar.TYRE_WINDOW_HIGH_C
		var rear_slip_m := car._rear_slip_w * tick * ArcadeCar.TYRE_SLIP_M_PER_KJ * 0.001 * (ArcadeCar.TYRE_WEAR_ABUSE if rear_hot else 1.0)
		var front_slip_m := car._front_slip_w * tick * ArcadeCar.TYRE_SLIP_M_PER_KJ * 0.001 * (ArcadeCar.TYRE_WEAR_ABUSE if front_hot else 1.0)
		rear_expected += (car._wear_way_m + rear_slip_m) / (ArcadeCar.REAR_TYRE_LIFE_KM * 1000.0)
		front_expected += (car._wear_way_m + front_slip_m) / (ArcadeCar.FRONT_TYRE_LIFE_KM * 1000.0)
		front_brake_expected += (car._wear_way_m + car._front_brake_heat_w * tick * ArcadeCar.BRAKE_WORK_M_PER_KJ * 0.001 * (ArcadeCar.BRAKE_WEAR_ABUSE if ArcadeCar.brake_fade(car.front_brake_temp) < 1.0 else 1.0)) / (ArcadeCar.BRAKE_LIFE_KM * 1000.0)
		rear_brake_expected += (car._wear_way_m + car._rear_brake_heat_w * tick * ArcadeCar.BRAKE_WORK_M_PER_KJ * 0.001 * (ArcadeCar.BRAKE_WEAR_ABUSE if ArcadeCar.brake_fade(car.rear_brake_temp) < 1.0 else 1.0)) / (ArcadeCar.BRAKE_LIFE_KM * 1000.0)
		rear_j += car._rear_slip_w * tick
		rear_m += rear_slip_m
		way_m += car._wear_way_m
		if rear_hot:
			hot_ticks += 1
			hot_j += car._rear_slip_w * tick
	var shares := _shares(car)
	var rear_c := ArcadeCar.tyre_c_of(car.rear_tyre_temp)
	var style := (way_m + rear_m) / way_m
	car.clear_driver_input()
	car.tcs_on = true
	car.sc_on = true
	_fresh(car)
	await _step(5)
	_check(
		shares[4] > 0.0 and absf(shares[4] / rear_expected - 1.0) < WIRING_TOLERANCE and absf(shares[3] / front_expected - 1.0) < WIRING_TOLERANCE
			and shares[4] > 5.0 * shares[3] and hot_ticks > 0 and hot_ticks < DONUT_FRAMES and hot_j > 0.0 and way_m > 0.0 and style > 2.0
			and off_pedal_brake_j == 0.0 and pedal_ticks < DONUT_FRAMES / 4
			and absf(shares[1] / front_brake_expected - 1.0) < WIRING_TOLERANCE and absf(shares[2] / rear_brake_expected - 1.0) < WIRING_TOLERANCE
			and shares[4] < ArcadeCar.WEAR_EFFECT_STEP and shares[0] < ArcadeCar.WEAR_EFFECT_STEP,
		"tyres: a %.0f s donut (%.0f m of way) is %.0f kJ of slip work against the rears (%.0f kJ of it on the %d ticks they are over the window, %.0f C at the end) - %.0f m of their life, x%.0f on the hot ticks, a style of %.1f - and wears them %.1f ppm, the metres plus the slip's metres over their %.0f km life to the bit, and the fronts %.2f ppm over theirs, %.0f times less; the brakes did exactly no work on the %d ticks the pedal was off and wore their metres plus the %d ticks it was on (%.2f and %.2f ppm: the spinning car rolled backwards on %d ticks, where the throttle key is the brake); the clutch %.1f ppm, slipping under the automatic's hunting; %.0f such donuts to the rears' first hundredth (was 35)" % [DONUT_FRAMES * tick, way_m, rear_j / 1000.0, hot_j / 1000.0, hot_ticks, rear_c, rear_m, ArcadeCar.TYRE_WEAR_ABUSE, style, shares[4] * 1.0e6, ArcadeCar.REAR_TYRE_LIFE_KM, shares[3] * 1.0e6, shares[4] / shares[3], DONUT_FRAMES - pedal_ticks, pedal_ticks, shares[1] * 1.0e6, shares[2] * 1.0e6, backwards_ticks, shares[0] * 1.0e6, ArcadeCar.WEAR_EFFECT_STEP / shares[4]],
	)


## The engine wears by its own metres - its revolutions in top-gear metres
## (TOP_GEAR_M_PER_RAD) times the load's style, 1 + (ENGINE_FLAT_OUT - 1) x
## the load share squared: flat out from rest exactly so, the style well
## over 1; free-revving at the limiter in neutral exactly its revolutions at
## no load (a style of 1: an engine that runs ages, ~27 km/h of it idling),
## everything else exactly 0 at the standstill; idling warm in neutral the
## same, by its revolutions; idling overheated every revolution at full load
## and ten times over.
# was exactly the rate times the radians weighted by the load, and exactly 0
# at the limiter in neutral and idling -> its revolutions in top-gear
# metres, running or driving (the user's 15:24 verdict: "how many kilometers
# would the engine run on average").
func _check_engine(car: ArcadeCar) -> void:
	var tick := 1.0 / Engine.physics_ticks_per_second
	_fresh(car)
	await _step(SETTLE_FRAMES)
	var loaded_from := car.engine_wear
	car.set_driver_input(1.0, 0.0, 0.0)
	var expected := 0.0
	var engine_m := 0.0
	var way_m := 0.0
	var rad := 0.0
	for frame in LAUNCH_FRAMES:
		await physics_frame
		var load_share := clampf(car.clutch_torque / ArcadeCar.ENGINE_PEAK_TORQUE, 0.0, 1.0)
		var metres := _engine_metres(car, tick, load_share)
		expected += metres / (ArcadeCar.ENGINE_LIFE_KM * 1000.0)
		engine_m += metres
		way_m += car._wear_way_m
		rad += absf(car.engine_omega) * tick
	var loaded_wear := car.engine_wear - loaded_from
	var style := engine_m / way_m
	car.clear_driver_input()

	# Neutral, full throttle: the limiter, no load.
	_fresh(car)
	await _step(SETTLE_FRAMES)
	car.automatic = false
	car.shift_down()
	var free_from := car.engine_wear
	car.set_driver_input(1.0, 0.0, 0.0)
	var limited := false
	var free_expected := 0.0
	var free_rad := 0.0
	var free_loaded := 0
	for frame in NEUTRAL_REV_FRAMES:
		await physics_frame
		limited = limited or car.limiter_cutting
		free_expected += _engine_metres(car, tick, 0.0) / (ArcadeCar.ENGINE_LIFE_KM * 1000.0)
		free_rad += absf(car.engine_omega) * tick
		if car.clutch_torque != 0.0:
			free_loaded += 1
	var free := _shares(car)
	var free_engine := free[5] - free_from
	var in_neutral := car.gear == 0
	car.clear_driver_input()

	# Neutral, idling: warm, then overheated.
	_fresh(car)
	await _step(SETTLE_FRAMES)
	car.automatic = false
	car.shift_down()
	var warm_from := car.engine_wear
	var warm_expected := 0.0
	var warm_rad := 0.0
	for frame in HOT_IDLE_FRAMES:
		await physics_frame
		warm_expected += _engine_metres(car, tick, 0.0) / (ArcadeCar.ENGINE_LIFE_KM * 1000.0)
		warm_rad += absf(car.engine_omega) * tick
	var warm_idle := car.engine_wear - warm_from
	var hot_expected := 0.0
	var hot_rad := 0.0
	var hot := ArcadeCar.coolant_temp_of_c(HOT_C)
	for frame in HOT_IDLE_FRAMES:
		car.coolant_temp = hot
		await physics_frame
		hot_expected += _engine_metres(car, tick, 1.0) * ArcadeCar.ENGINE_WEAR_ABUSE / (ArcadeCar.ENGINE_LIFE_KM * 1000.0)
		hot_rad += absf(car.engine_omega) * tick
	var hot_idle := car.engine_wear - warm_from - warm_idle
	var idle_rpm := car.engine_rpm
	var idle_kmh := idle_rpm * TAU / 60.0 * ArcadeCar.TOP_GEAR_M_PER_RAD * 3.6
	_fresh(car)
	await _step(5)
	_check(
		loaded_wear > 0.0 and absf(loaded_wear / expected - 1.0) < WIRING_TOLERANCE and engine_m > way_m and style > 2.0
			and limited and in_neutral and free_loaded == 0 and free_engine > 0.0 and absf(free_engine / free_expected - 1.0) < WIRING_TOLERANCE
			and free[0] == 0.0 and free[1] == 0.0 and free[2] == 0.0 and free[3] == 0.0 and free[4] == 0.0
			and warm_idle > 0.0 and absf(warm_idle / warm_expected - 1.0) < WIRING_TOLERANCE
			and hot_idle > 0.0 and absf(hot_idle / hot_expected - 1.0) < WIRING_TOLERANCE and hot_idle > 10.0 * warm_idle and loaded_wear < ArcadeCar.WEAR_EFFECT_STEP,
		"engine: %.0f s flat out from rest turns it %.0f krad - %.0f m of its life for %.0f m of road, a style of %.1f - and wears it %.2f ppm, its revolutions in top-gear metres times the load's style over its %.0f km life to the bit, %.0f such runs to the first hundredth (was 306); %.0f s at the limiter in neutral (%.0f rad, the crank never loaded) wears it %.3f ppm - exactly its revolutions at a style of 1 (was exactly 0) - and everything else exactly 0; %.0f s idling warm in neutral %.3f ppm the same way (%.0f rpm is %.0f km/h of the engine's own metres), the same idling at %.0f C (%.0f rad) %.2f ppm - every revolution at full load, x%.0f, and %.0f times over" % [LAUNCH_FRAMES * tick, rad / 1000.0, engine_m, way_m, style, loaded_wear * 1.0e6, ArcadeCar.ENGINE_LIFE_KM, ArcadeCar.WEAR_EFFECT_STEP / loaded_wear, NEUTRAL_REV_FRAMES * tick, free_rad, free_engine * 1.0e6, HOT_IDLE_FRAMES * tick, warm_idle * 1.0e6, idle_rpm, idle_kmh, HOT_C, hot_rad, hot_idle * 1.0e6, ArcadeCar.ENGINE_FLAT_OUT, ArcadeCar.ENGINE_WEAR_ABUSE],
	)


## The cruise: CRUISE_M in top gear at CRUISE_KMH, straight down the pad,
## wears every component its rated share of the metres - the style
## multiplier (the wear over the metres' share of the life) exactly 1 for
## the clutch (locked), the brakes (the pedal up) and the fronts (rolling
## free), a hair over for the driven rears (their drive slip) and the engine
## (its light load, its wheels' slip) - each wired to the tick's quantities
## to the bit; and the second half of the way wears the same as the first,
## twice the kilometres twice the wear.
func _check_cruise(car: ArcadeCar) -> void:
	var tick := 1.0 / Engine.physics_ticks_per_second
	_fresh(car)
	await _step(SETTLE_FRAMES)
	car.set_driver_input(1.0, 0.0, 0.0)
	while car.speed_kmh < CRUISE_KMH:
		await physics_frame
	var top_gear := ArcadeCar.GEAR_RATIOS.size() - 1
	var shift_ticks := 0
	while car.gear < top_gear and shift_ticks < 1200:
		if not car.is_shifting:
			car.shift_up()
		await physics_frame
		shift_ticks += 1
	for frame in CRUISE_SETTLE_FRAMES:
		car.set_driver_input(_cruise_throttle(car), 0.0, 0.0)
		await physics_frame
	var gear_held := car.gear == top_gear and not car.is_shifting
	var from := _shares(car)
	var expected: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
	var half_wear: Array[Array] = []
	var half_way: Array[float] = []
	var way_m := 0.0
	var slip_ticks := 0
	var brake_ticks := 0
	var rpm_sum := 0.0
	var load_sum := 0.0
	var ticks := 0
	var next_half := CRUISE_M / CRUISE_HALVES
	var half_from := from
	var half_from_way := 0.0
	while way_m < CRUISE_M and ticks < 20000:
		car.set_driver_input(_cruise_throttle(car), 0.0, 0.0)
		await physics_frame
		ticks += 1
		way_m += car._wear_way_m
		rpm_sum += car.engine_rpm
		var load_share := clampf(car.clutch_torque / ArcadeCar.ENGINE_PEAK_TORQUE, 0.0, 1.0)
		load_sum += load_share
		if car._clutch_slip_w > 0.0:
			slip_ticks += 1
		if car._front_brake_heat_w > 0.0 or car._rear_brake_heat_w > 0.0:
			brake_ticks += 1
		expected[0] += (car._wear_way_m + car._clutch_slip_w * tick * ArcadeCar.CLUTCH_SLIP_M_PER_KJ * 0.001) / (ArcadeCar.CLUTCH_LIFE_KM * 1000.0)
		expected[1] += (car._wear_way_m + car._front_brake_heat_w * tick * ArcadeCar.BRAKE_WORK_M_PER_KJ * 0.001 * (ArcadeCar.BRAKE_WEAR_ABUSE if ArcadeCar.brake_fade(car.front_brake_temp) < 1.0 else 1.0)) / (ArcadeCar.BRAKE_LIFE_KM * 1000.0)
		expected[2] += (car._wear_way_m + car._rear_brake_heat_w * tick * ArcadeCar.BRAKE_WORK_M_PER_KJ * 0.001 * (ArcadeCar.BRAKE_WEAR_ABUSE if ArcadeCar.brake_fade(car.rear_brake_temp) < 1.0 else 1.0)) / (ArcadeCar.BRAKE_LIFE_KM * 1000.0)
		expected[3] += (car._wear_way_m + car._front_slip_w * tick * ArcadeCar.TYRE_SLIP_M_PER_KJ * 0.001 * (ArcadeCar.TYRE_WEAR_ABUSE if ArcadeCar.tyre_c_of(car.front_tyre_temp) > ArcadeCar.TYRE_WINDOW_HIGH_C else 1.0)) / (ArcadeCar.FRONT_TYRE_LIFE_KM * 1000.0)
		expected[4] += (car._wear_way_m + car._rear_slip_w * tick * ArcadeCar.TYRE_SLIP_M_PER_KJ * 0.001 * (ArcadeCar.TYRE_WEAR_ABUSE if ArcadeCar.tyre_c_of(car.rear_tyre_temp) > ArcadeCar.TYRE_WINDOW_HIGH_C else 1.0)) / (ArcadeCar.REAR_TYRE_LIFE_KM * 1000.0)
		expected[5] += _engine_metres(car, tick, load_share) / (ArcadeCar.ENGINE_LIFE_KM * 1000.0)
		if way_m >= next_half and half_wear.size() < CRUISE_HALVES - 1:
			var now := _shares(car)
			var grown: Array[float] = []
			for i in now.size():
				grown.append(now[i] - half_from[i])
			half_wear.append(grown)
			half_way.append(way_m - half_from_way)
			half_from = now
			half_from_way = way_m
			next_half += CRUISE_M / CRUISE_HALVES
	var to := _shares(car)
	var last_half: Array[float] = []
	for i in to.size():
		last_half.append(to[i] - half_from[i])
	half_wear.append(last_half)
	half_way.append(way_m - half_from_way)
	var speed := car.speed_kmh
	var still_top := car.gear == top_gear and not car.is_shifting
	car.clear_driver_input()
	_fresh(car)
	await _step(5)
	var lives: Array[float] = [ArcadeCar.CLUTCH_LIFE_KM, ArcadeCar.BRAKE_LIFE_KM, ArcadeCar.BRAKE_LIFE_KM, ArcadeCar.FRONT_TYRE_LIFE_KM, ArcadeCar.REAR_TYRE_LIFE_KM, ArcadeCar.ENGINE_LIFE_KM]
	var styles: Array[float] = []
	var wired := true
	var rated := true
	var linear := true
	for i in to.size():
		var wear := to[i] - from[i]
		wired = wired and wear > 0.0 and absf(wear / expected[i] - 1.0) < WIRING_TOLERANCE
		var style := wear * lives[i] * 1000.0 / way_m
		styles.append(style)
		var tolerance := CRUISE_ENGINE_TOLERANCE if i == 5 else (CRUISE_REAR_TYRE_TOLERANCE if i == 4 else WIRING_TOLERANCE)
		rated = rated and style >= 1.0 - WIRING_TOLERANCE and style <= 1.0 + tolerance
		var halves_tolerance := CRUISE_HALVES_TOLERANCE if i >= 4 else CRUISE_METRES_TOLERANCE
		for half: Array in half_wear:
			linear = linear and absf(half[i] * CRUISE_HALVES / wear - 1.0) < halves_tolerance
	var halves_ok := half_wear.size() == CRUISE_HALVES and half_way.size() == CRUISE_HALVES and absf(half_way[0] / half_way[CRUISE_HALVES - 1] - 1.0) < CRUISE_METRES_TOLERANCE
	_check(
		gear_held and still_top and way_m >= CRUISE_M and ticks < 20000 and slip_ticks == 0 and brake_ticks == 0 and wired and rated and linear and halves_ok
			and absf(speed - CRUISE_KMH) < 5.0,
		"cruise: %.0f m in %dth gear at %.0f km/h (%.0f rpm, %d ticks, the clutch locked and the pedal up throughout, the crank loaded %.2f of its peak) wears the clutch %.2f ppm, the pads %.2f and %.2f, the tyres %.2f and %.2f, the engine %.2f - each the tick's metres over its life to the bit - at styles of %.4f, %.4f, %.4f, %.4f (exactly 1: the rated life is the gentle cruise), %.4f for the driven rears (their drive slip's %.1f m) and %.3f for the engine (its light load and its wheels' slip); the first %.0f m wore each of them the same as the second %.0f m to within %.1f %% (the rears and the engine within %.0f %%): twice the kilometres, twice the wear" % [way_m, top_gear, CRUISE_KMH, rpm_sum / ticks, ticks, load_sum / ticks, (to[0] - from[0]) * 1.0e6, (to[1] - from[1]) * 1.0e6, (to[2] - from[2]) * 1.0e6, (to[3] - from[3]) * 1.0e6, (to[4] - from[4]) * 1.0e6, (to[5] - from[5]) * 1.0e6, styles[0], styles[1], styles[2], styles[3], styles[4], (styles[4] - 1.0) * way_m, styles[5], half_way[0], half_way[CRUISE_HALVES - 1], CRUISE_METRES_TOLERANCE * 100.0, CRUISE_HALVES_TOLERANCE * 100.0],
	)


## The cruise's throttle: a plain proportional hold on CRUISE_KMH.
func _cruise_throttle(car: ArcadeCar) -> float:
	return clampf(CRUISE_THROTTLE_BASE + CRUISE_THROTTLE_GAIN * (CRUISE_KMH - car.speed_kmh), 0.0, 1.0)


## The engine's own metres this tick, as _advance_wear counts them: the
## revolutions in top-gear metres times the load's style, 1 +
## (ENGINE_FLAT_OUT - 1) x `load_share` squared.
func _engine_metres(car: ArcadeCar, tick: float, load_share: float) -> float:
	return absf(car.engine_omega) * tick * ArcadeCar.TOP_GEAR_M_PER_RAD * (1.0 + (ArcadeCar.ENGINE_FLAT_OUT - 1.0) * load_share * load_share)


## Worn brakes stop the car measurably longer, worn-out ones longer again,
## and past worn out no longer: the same stop to the bit.
func _check_worn_brakes(car: ArcadeCar) -> void:
	var fresh := await _stop(car, 0.0)
	var mid := await _stop(car, MID_WEAR)
	var mid_step := await _stop(car, MID_STEP_WEAR)
	var full := await _stop(car, FULL_WEAR)
	var past := await _stop(car, PAST_WEAR)
	_check(
		fresh.stopped and mid.stopped and full.stopped and past.stopped and mid.distance_m > fresh.distance_m * 1.02 and full.distance_m > mid.distance_m * 1.02
			and mid_step.distance_m == mid.distance_m and mid_step.ticks == mid.ticks and mid_step.factor == mid.factor
			and past.distance_m == full.distance_m and past.ticks == full.ticks and is_equal_approx(mid.factor, 1.0 - MID_WEAR * (1.0 - ArcadeCar.BRAKE_WEAR_FLOOR)) and full.factor == ArcadeCar.BRAKE_WEAR_FLOOR and past.factor == ArcadeCar.BRAKE_WEAR_FLOOR,
		"worn brakes: a stop from %.0f km/h takes %.1f m on new pads, %.1f m half worn (%.0f %% of the torque, %.0f %% longer; at %.1f %% worn, inside the same hundredth, the same stop to the bit), %.1f m worn out (the floor's %.0f %%, %.0f %% longer), and %.1f m past worn out - the same stop to the bit: the floor holds" % [STOP_FROM_KMH, fresh.distance_m, mid.distance_m, mid.factor * 100.0, (mid.distance_m / fresh.distance_m - 1.0) * 100.0, MID_STEP_WEAR * 100.0, full.distance_m, full.factor * 100.0, (full.distance_m / fresh.distance_m - 1.0) * 100.0, past.distance_m],
	)


## A worn clutch bites softer and slips longer: on the same launch it never
## passes more than the floor's share of its capacity (to a millionth: the
## wheelspin easing rounds the torque through a Vector2's single precision)
## where the new one does, spends more ticks slipping, and past worn out
## slips the same to the bit.
func _check_worn_clutch(car: ArcadeCar) -> void:
	var fresh := await _launch(car, 0.0)
	var full := await _launch(car, FULL_WEAR)
	var past := await _launch(car, PAST_WEAR)
	var capacity := ArcadeCar.CLUTCH_TORQUE_MAX
	var floor := ArcadeCar.CLUTCH_WEAR_FLOOR
	_check(
		fresh.peak_nm > capacity * floor * 1.2 and full.peak_nm <= capacity * floor * (1.0 + 1.0e-6) and full.slipping_ticks > fresh.slipping_ticks
			and full.slip_kj > 0.0 and past.peak_nm == full.peak_nm and past.slipping_ticks == full.slipping_ticks and past.slip_kj == full.slip_kj and past.speed_kmh == full.speed_kmh
			and full.speed_kmh <= fresh.speed_kmh,
		"worn clutch: on the same %.0f s launch the new clutch passes up to %.0f Nm and slips %d ticks (%.1f kJ, %.0f km/h at the end); worn out it passes at most %.0f Nm (the floor's %.0f %% of %.0f) and slips %d ticks (%.1f kJ, %.0f km/h); past worn out the same launch to the bit" % [LAUNCH_FRAMES / float(Engine.physics_ticks_per_second), fresh.peak_nm, fresh.slipping_ticks, fresh.slip_kj, fresh.speed_kmh, full.peak_nm, floor * 100.0, capacity, full.slipping_ticks, full.slip_kj, full.speed_kmh],
	)


## Worn tyres hold measurably less in the same corner, worn-out ones less
## again, never under the floor's share, and past worn out the same to the
## bit.
func _check_worn_tyres(car: ArcadeCar) -> void:
	var fresh := await _corner(car, 0.0)
	var mid := await _corner(car, MID_WEAR)
	var full := await _corner(car, FULL_WEAR)
	var past := await _corner(car, PAST_WEAR)
	var floor := ArcadeCar.TYRE_WEAR_FLOOR
	_check(
		mid.lateral_g < fresh.lateral_g * 0.99 and full.lateral_g < mid.lateral_g * 0.99 and full.lateral_g > fresh.lateral_g * floor * 0.95
			and past.lateral_g == full.lateral_g and is_equal_approx(mid.factor, 1.0 - MID_WEAR * (1.0 - floor)) and full.factor == floor and past.factor == floor,
		"worn tyres: the same corner from %.0f km/h holds %.2f g on new tyres, %.2f g half worn (%.0f %% of the grip), %.2f g worn out (the floor's %.0f %%, still over %.0f %% of the new tyres' hold), and %.2f g past worn out - the same corner to the bit" % [CORNER_FROM_KMH, fresh.lateral_g, mid.lateral_g, mid.factor * 100.0, full.lateral_g, floor * 100.0, floor * 95.0, past.lateral_g],
	)


## A worn engine makes measurably less torque at the same rpm and throttle -
## the curve times the multiplier, the friction as it was - never under the
## floor's share, and is measurably slower over the same flat-out seconds.
func _check_worn_engine(car: ArcadeCar) -> void:
	var rpm := ArcadeCar.TORQUE_CURVE[3].x
	var friction := ArcadeCar.ENGINE_FRICTION_TORQUE + ArcadeCar.ENGINE_FRICTION_TORQUE_PER_RPM * rpm
	var floor := ArcadeCar.ENGINE_WEAR_FLOOR
	_fresh(car)
	await _step(5)
	var fresh_torque := car._combustion_torque(rpm, 1.0, 0.0)
	car.engine_wear = MID_WEAR
	var mid_torque := car._combustion_torque(rpm, 1.0, 0.0)
	car.engine_wear = FULL_WEAR
	var full_torque := car._combustion_torque(rpm, 1.0, 0.0)
	car.engine_wear = PAST_WEAR
	var past_torque := car._combustion_torque(rpm, 1.0, 0.0)
	var curve := ArcadeCar.engine_torque(rpm)
	var torques_ok := fresh_torque == curve + friction and is_equal_approx(mid_torque, curve * (1.0 - MID_WEAR * (1.0 - floor)) + friction) \
		and is_equal_approx(full_torque, curve * floor + friction) and past_torque == full_torque
	var fresh_run := await _launch(car, 0.0, 0.0)
	var worn_run := await _launch(car, 0.0, FULL_WEAR)
	_check(
		torques_ok and worn_run.speed_kmh < fresh_run.speed_kmh * 0.99 and worn_run.speed_kmh > fresh_run.speed_kmh * floor * 0.9,
		"worn engine: at %.0f rpm flat out the new engine burns for %.1f Nm (the curve's %.0f plus its %.1f of friction), half worn %.1f Nm, worn out %.1f Nm (the floor's %.0f %% of the curve), past worn out the same; over the same %.0f s flat out from rest the new engine reaches %.1f km/h, the worn-out one %.1f" % [rpm, fresh_torque, curve, friction, mid_torque, full_torque, floor * 100.0, LAUNCH_FRAMES / float(Engine.physics_ticks_per_second), fresh_run.speed_kmh, worn_run.speed_kmh],
	)


## The store itself, on a file of the test's own: the six shares come back to
## the bit in the one entry beside the rest, in the one write; a save without
## them leaves them; a NaN share goes in as its default; a car, a file or an
## entry with no wear is a new car's; an old file - no wear object - rounds
## through a save untouched, its version still 1; and what is no share of a
## life is refused with the reason, naming the car and the field.
func _check_store() -> void:
	DirAccess.make_dir_recursive_absolute(_store_dir)
	if FileAccess.file_exists(_store_file):
		DirAccess.remove_absolute(_store_file)
	var new_car := OdometerStore.load_wear(ArcadeCar.CAR_ID, _store_file)
	# An old file: an entry with everything but the wear.
	OdometerStore.save_car(ArcadeCar.CAR_ID, 4321.5, 12.5, _store_file, STORE_DRIVER, STORE_BATTERY)
	var old_text := FileAccess.get_file_as_string(_store_file)
	var old_car := OdometerStore.load_wear(ArcadeCar.CAR_ID, _store_file)
	OdometerStore.save_car(ArcadeCar.CAR_ID, 4400.0, NAN, _store_file, {}, {}, STORE_HARD_WEAR)
	OdometerStore.save_car("some_other_car", NAN, NAN, _store_file, {}, {}, {"clutch": NAN, "engine": 0.5})
	OdometerStore.save_car(ArcadeCar.CAR_ID, 4500.0, NAN, _store_file)
	var written: Variant = JSON.parse_string(FileAccess.get_file_as_string(_store_file))
	var entry: Dictionary = written["cars"][ArcadeCar.CAR_ID] if written is Dictionary else {}
	var back := OdometerStore.load_wear(ArcadeCar.CAR_ID, _store_file)
	var other := OdometerStore.load_wear("some_other_car", _store_file)
	var unknown := OdometerStore.load_wear("no_such_car", _store_file)
	var to_the_bit := true
	var floats := true
	for field: String in WEAR_FIELDS:
		to_the_bit = to_the_bit and back[field] == STORE_HARD_WEAR[field] and entry.get("wear", {}).get(field) == STORE_HARD_WEAR[field]
		floats = floats and typeof(back[field]) == TYPE_FLOAT
	var defaults_back := true
	for wear: Dictionary in [new_car, old_car, unknown]:
		for field: String in WEAR_FIELDS:
			defaults_back = defaults_back and wear[field] == 0.0
		defaults_back = defaults_back and (wear.problems as Array).is_empty()
	var other_ok: bool = other.clutch == 0.0 and other.engine == 0.5 and (other.problems as Array).is_empty() and not written["cars"]["some_other_car"].has("odometer_m")
	var beside: bool = entry.get("odometer_m") == 4500.0 and entry.get("fuel_l") == 12.5 and entry.get("driver", {}).get("gearbox_mode") == "eco" \
		and entry.get("battery", {}).get("charge") == 0.5 and entry.get("battery", {}).get("capacity_wear") == 0.1 and written.get("version") == OdometerStore.VERSION and OdometerStore.VERSION == 1
	var old_had_no_wear: bool = not (JSON.parse_string(old_text) as Dictionary)["cars"][ArcadeCar.CAR_ID].has("wear")
	_check(
		(back.problems as Array).is_empty() and to_the_bit and floats and defaults_back and other_ok and beside and old_had_no_wear,
		"store: all six shares come back to the bit (clutch %.16f .. engine %.15f) in the one entry beside the odometer, the fuel, the dashboard and the battery, in the one write, version still %d; a save of the metres alone leaves them; a NaN share goes in as 0 beside a good one; a car, a file, an entry with no wear and an old file's entry are a new car's, nothing wrong; and the old file had no wear object until it was handed one" % [back.clutch, back.engine, OdometerStore.VERSION],
	)

	# A number that is no share of a life: its default and the reason, as text
	# - the car that asks makes the error of it (push_error; not here, the
	# suite's output has none). NaN and inf never get through a JSON file, so
	# they go to the check itself.
	var not_shares: Array = [NAN, INF, -INF, -0.001, 1.001, 2, "worn", "", null, true, false, [0.5], {"clutch": 0.5}]
	var refused := 0
	var tried := 0
	for field: String in OdometerStore.WEAR_DEFAULTS:
		for value: Variant in not_shares:
			tried += 1
			if OdometerStore.wear_problem(field, value) != "":
				refused += 1
	var shares_ok := true
	for field: String in OdometerStore.WEAR_DEFAULTS:
		for value: Variant in [0, 1, 0.0, 1.0, 0.5, 0.999]:
			shares_ok = shares_ok and OdometerStore.wear_problem(field, value) == ""
	var no_field := OdometerStore.wear_problem("gearbox", 0.5) != ""
	var garage_file := FileAccess.open(_store_file, FileAccess.WRITE)
	garage_file.store_string('{"version": 1, "cars": {"bad_car": {"odometer_m": 7.5, "wear": {"clutch": "worn", "engine": -0.1, "tyres_rear": 0.25}}, "part_bad": {"wear": {"brakes_front": 0.4, "brakes_rear": 2}}, "whole": {"wear": {"clutch": 1, "engine": 0}}}}')
	garage_file.close()
	var bad := OdometerStore.load_wear("bad_car", _store_file)
	var said := 0
	for field: String in OdometerStore.WEAR_DEFAULTS:
		for problem: String in bad.problems:
			if problem.contains("bad_car's wear " + field):
				said += 1
	var part_bad := OdometerStore.load_wear("part_bad", _store_file)
	var whole := OdometerStore.load_wear("whole", _store_file)
	_check(
		refused == tried and shares_ok and no_field and said == 2 and (bad.problems as Array).size() == 2 and bad.clutch == 0.0 and bad.engine == 0.0 and bad.tyres_rear == 0.25
			and part_bad.brakes_front == 0.4 and part_bad.brakes_rear == 0.0 and (part_bad.problems as Array).size() == 1
			and whole.clutch == 1.0 and whole.engine == 0.0 and typeof(whole.clutch) == TYPE_FLOAT and (whole.problems as Array).is_empty()
			and OdometerStore.load_odometer("bad_car", _store_file) == 7.5,
		"store: NaN, inf, under 0, over 1, words, null, a bool, a list and an object are no share of a life (%d of %d refused; two bad fields of an entry read as 0 with the reason each, naming the car and the field, the good one beside them still loads, and the car's metres with them); a whole 1 and 0 are floats" % [refused, tried],
	)


## The car that loads worn components starts with them, not new: the shares
## to the bit and the multipliers under 1 where a share is over a hundredth.
func _check_car_loads(car: ArcadeCar) -> void:
	OdometerStore.save_car(ArcadeCar.CAR_ID, 1000.0, 30.0, _store_file, {}, {}, STORE_WORN)
	_fresh(car)
	car._load_stored_wear(_store_file)
	var loaded := _shares(car)
	var loaded_ok := true
	for i in WEAR_FIELDS.size():
		loaded_ok = loaded_ok and loaded[i] == STORE_WORN[WEAR_FIELDS[i]]
	var factors := _factors(car)
	var under_one := true
	for factor: float in factors:
		under_one = under_one and factor < 1.0
	var settings := car.wear_settings()
	var settings_ok := settings.size() == WEAR_FIELDS.size()
	for field: String in WEAR_FIELDS:
		settings_ok = settings_ok and settings.get(field) == STORE_WORN[field]
	await _step(2)
	var still := _shares(car)
	var grew_only := true
	for i in WEAR_FIELDS.size():
		grew_only = grew_only and still[i] >= loaded[i]
	_fresh(car)
	var renewed := _all_equal(_shares(car), 0.0)
	await _step(5)
	_check(
		loaded_ok and under_one and settings_ok and grew_only and renewed,
		"store: a car that loads a clutch %.0f %% worn, brakes %.0f/%.0f %%, tyres %.0f/%.0f %% and an engine %.0f %% starts exactly so, every multiplier under 1 (clutch %.3f, engine %.4f), wear_settings hands the six back, and two ticks later none of them is less" % [STORE_WORN.clutch * 100.0, STORE_WORN.brakes_front * 100.0, STORE_WORN.brakes_rear * 100.0, STORE_WORN.tyres_front * 100.0, STORE_WORN.tyres_rear * 100.0, STORE_WORN.engine * 100.0, factors[0], factors[5]],
	)


## A reset keeps the wear: six distinct shares set by hand are there to the
## bit after reset_to and after the settle, still worn, the file not told; a
## handling test's start is the one thing that hands out the new car - every
## share exactly 0, every multiplier exactly 1, before its first tick.
func _check_reset(car: ArcadeCar, pad: TestPad) -> void:
	_fresh(car)
	await _step(5)
	var set_to: Array[float] = [0.11, 0.22, 0.33, 0.44, 0.55, 0.66]
	for i in WEAR_PROPERTIES.size():
		car.set(WEAR_PROPERTIES[i], set_to[i])
	await _step(1)
	var before := _shares(car)
	var file_before := FileAccess.get_file_as_string(_store_file)
	_fresh_fuel(car)
	car.reset_to_spawn()
	var kept := _shares(car) == before
	var worn_after := true
	for factor: float in _factors(car):
		worn_after = worn_after and factor < 1.0
	await _step(SETTLE_FRAMES)
	var still := _shares(car)
	var still_kept := true
	for i in WEAR_FIELDS.size():
		still_kept = still_kept and still[i] >= before[i] and still[i] - before[i] < 1.0e-6
	var file_untold := FileAccess.get_file_as_string(_store_file) == file_before and not car._odometer_kept
	var run := HandlingTests.begin(HandlingTests.all_tests()[0], car, pad)
	var fresh := run != null and not run.finished and _all_equal(_shares(car), 0.0) and _all_equal(_factors(car), 1.0) and car._clutch_slip_w == 0.0
	_fresh_fuel(car)
	car.reset_to_spawn()
	pad.reset_cones()
	_fresh(car)
	await _step(5)
	_check(
		kept and worn_after and still_kept and file_untold and fresh,
		"reset keeps the wear: six shares set by hand (%.2f .. %.2f) are there to the bit after a reset, the multipliers still under 1, and still there after %d idling ticks, the file not told; a handling test's start on that worn car hands out the new one before its first tick - every share exactly 0, every multiplier exactly 1" % [set_to[0], set_to[5], SETTLE_FRAMES],
	)


## Nothing of it is ever NaN: a NaN share is none, inf worn out, -inf none; a
## tick's NaN, infinite or negative quantity - the way among them - adds
## nothing and takes nothing; and after everything above the whole state is
## finite.
func _check_no_nan(car: ArcadeCar) -> void:
	var tick := 1.0 / Engine.physics_ticks_per_second
	car.clutch_wear = NAN
	car.engine_wear = NAN
	var nan_none := car.clutch_wear == 0.0 and car.engine_wear == 0.0 and car.clutch_wear_factor() == 1.0
	car.front_brake_wear = INF
	car.rear_tyre_wear = INF
	var inf_out := car.front_brake_wear == ArcadeCar.WEAR_LIMIT and car.rear_tyre_wear == ArcadeCar.WEAR_LIMIT and car.front_brake_wear_factor() == ArcadeCar.BRAKE_WEAR_FLOOR
	car.front_brake_wear = -INF
	car.rear_tyre_wear = -INF
	var neg_inf_none := car.front_brake_wear == 0.0 and car.rear_tyre_wear == 0.0
	_fresh(car)
	for i in WEAR_PROPERTIES.size():
		car.set(WEAR_PROPERTIES[i], 0.1 * (i + 1))
	var before := _shares(car)
	car._wear_way_m = NAN
	car._clutch_slip_w = NAN
	car._front_brake_heat_w = NAN
	car._rear_brake_heat_w = -1000.0
	car._front_slip_w = -INF
	car._rear_slip_w = NAN
	car.engine_omega = NAN
	car._advance_wear(tick)
	var unchanged := _shares(car) == before
	car._wear_way_m = INF
	car._front_slip_w = INF
	car._advance_wear(tick)
	var inf_none := _shares(car) == before
	car.engine_omega = ArcadeCar.IDLE_RPM * TAU / 60.0
	_fresh(car)
	await _step(2)
	var finite := true
	for share: float in _shares(car):
		finite = finite and is_finite(share)
	for factor: float in _factors(car):
		finite = finite and is_finite(factor)
	_check(nan_none and inf_out and neg_inf_none and unchanged and inf_none and finite, "no NaN: a NaN share is none (the multiplier 1), inf is worn out (the multiplier the floor), -inf none; NaN, inf, -inf and negative tick quantities - the way among them - add nothing and take nothing (six shares unchanged to the bit); and the whole state is finite after the run")


## A reset, the car driven up to STOP_FROM_KMH on new brakes, both axles'
## brakes set to `wear` there, and a full-pedal stop:
## { distance_m, ticks, stopped, factor: the front brakes' multiplier }.
func _stop(car: ArcadeCar, wear: float) -> Dictionary:
	_fresh(car)
	await _step(SETTLE_FRAMES)
	car.set_driver_input(1.0, 0.0, 0.0)
	while car.speed_kmh < STOP_FROM_KMH:
		await physics_frame
	car.front_brake_wear = wear
	car.rear_brake_wear = wear
	var start := car.global_position
	car.set_driver_input(0.0, 1.0, 0.0)
	var ticks := 0
	while car.speed_kmh > STOPPED_KMH and ticks < 600:
		await physics_frame
		ticks += 1
	var seen := {
		"distance_m": (car.global_position - start).length(),
		"ticks": ticks,
		"stopped": car.speed_kmh <= STOPPED_KMH,
		"factor": car.front_brake_wear_factor(),
	}
	car.clear_driver_input()
	_fresh(car)
	await _step(5)
	return seen


## A reset, the clutch set to `clutch_wear` and the engine to `engine_wear`,
## and LAUNCH_FRAMES ticks flat out from rest: { peak_nm: the most the clutch
## passed, slipping_ticks, slip_kj, speed_kmh at the end }.
func _launch(car: ArcadeCar, clutch_wear: float, engine_wear := 0.0) -> Dictionary:
	var tick := 1.0 / Engine.physics_ticks_per_second
	_fresh(car)
	await _step(SETTLE_FRAMES)
	car.clutch_wear = clutch_wear
	car.engine_wear = engine_wear
	car.set_driver_input(1.0, 0.0, 0.0)
	var peak := 0.0
	var slipping := 0
	var slip_j := 0.0
	for frame in LAUNCH_FRAMES:
		await physics_frame
		peak = maxf(peak, absf(car.clutch_torque))
		if car._clutch_slip_w > 0.0:
			slipping += 1
		slip_j += car._clutch_slip_w * tick
	var seen := {"peak_nm": peak, "slipping_ticks": slipping, "slip_kj": slip_j / 1000.0, "speed_kmh": car.speed_kmh}
	car.clear_driver_input()
	_fresh(car)
	await _step(5)
	return seen


## A reset, the car driven up to CORNER_FROM_KMH on new tyres, both axles'
## tyres set to `wear` there, and CORNER_FRAMES ticks at CORNER_STEER with
## CORNER_THROTTLE: { lateral_g: the peak lateral acceleration [g], factor:
## the front tyres' multiplier }.
func _corner(car: ArcadeCar, wear: float) -> Dictionary:
	_fresh(car)
	await _step(SETTLE_FRAMES)
	car.set_driver_input(1.0, 0.0, 0.0)
	while car.speed_kmh < CORNER_FROM_KMH:
		await physics_frame
	car.front_tyre_wear = wear
	car.rear_tyre_wear = wear
	car.set_driver_input(CORNER_THROTTLE, 0.0, CORNER_STEER)
	var peak := 0.0
	for frame in CORNER_FRAMES:
		await physics_frame
		peak = maxf(peak, absf(car.lateral_accel))
	var seen := {"lateral_g": peak / 9.8, "factor": car.front_tyre_wear_factor()}
	car.clear_driver_input()
	_fresh(car)
	await _step(5)
	return seen


## The six shares as the car has them, in WEAR_FIELDS' order.
func _shares(car: ArcadeCar) -> Array[float]:
	return [car.clutch_wear, car.front_brake_wear, car.rear_brake_wear, car.front_tyre_wear, car.rear_tyre_wear, car.engine_wear]


## The six multipliers as the car has them, in the same order.
func _factors(car: ArcadeCar) -> Array[float]:
	return [car.clutch_wear_factor(), car.front_brake_wear_factor(), car.rear_brake_wear_factor(), car.front_tyre_wear_factor(), car.rear_tyre_wear_factor(), car.engine_wear_factor()]


func _all_equal(values: Array[float], to: float) -> bool:
	for value: float in values:
		if value != to:
			return false
	return true


## A reset and the certified fresh car after it: the thermal state by hand (a
## reset keeps the heat), the new components (a reset keeps the wear) and the
## full tank (a reset keeps the fuel) - what HandlingTests._start sets for a
## certified run.
func _fresh(car: ArcadeCar) -> void:
	_fresh_fuel(car)
	car.reset_to_spawn()
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
	car.clutch_wear = 0.0
	car.front_brake_wear = 0.0
	car.rear_brake_wear = 0.0
	car.front_tyre_wear = 0.0
	car.rear_tyre_wear = 0.0
	car.engine_wear = 0.0
	car._clutch_slip_w = 0.0
	car._front_slip_w = 0.0
	car._rear_slip_w = 0.0
	car._wear_way_m = 0.0


## And the certified fresh car's tank: full, its mass with it.
# was the reset's own (reset_to filled the tank until 3Y) -> set by hand: a
# reset keeps the fuel (the user's report, 2026-09-22 12:55: "resetting the
# car MUST NOT refuel ... tests must not affect the game"), and every check
# here was measured on the full tank - the kerb mass everything was tuned
# with. What reset_to set until then, and what HandlingTests._start sets for
# a certified run. Called before every reset here: the reset stands the car
# on its springs by its mass (_settle_suspension reads total_mass()) and
# keeps the tank it finds. A check that wants a dry tank empties it after.
func _fresh_fuel(car: ArcadeCar) -> void:
	car.fuel_l = ArcadeCar.FUEL_TANK_CAPACITY_L
	car.fuel_mass = car.fuel_l * ArcadeCar.FUEL_DENSITY


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
	if FileAccess.file_exists(_store_file):
		DirAccess.remove_absolute(_store_file)
	if DirAccess.dir_exists_absolute(_store_dir):
		DirAccess.remove_absolute(_store_dir)
	if _failures == 0:
		print("WEAR TEST PASSED")
	else:
		printerr("WEAR TEST FAILED: %d check(s) failed" % _failures)
	quit(1 if _failures > 0 else 0)
