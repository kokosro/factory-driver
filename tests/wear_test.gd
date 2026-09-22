extends SceneTree
## Headless wear test. Run via tests/run_tests.sh, or:
##
##   godot --headless --path . --import
##   godot --headless --fixed-fps 60 --path . --script res://tests/wear_test.gd
##
## Loads the main scene and puts the car's wear (ArcadeCar, "Wear and aging")
## through what usage and neglect do. First the gate: the car comes out of
## _ready with nothing worn - every share exactly 0 and every multiplier
## exactly 1 - and idles so through the settle; and the model's own numbers:
## the multipliers are exactly 1 under a hundredth of wear, step once a
## percent in a line to the floor and never under it, the config's rates are
## the car's, and a rate under zero, an abuse under 1 and a floor outside its
## range are refused by name. Then each share from its own activity, wired to
## the tick's own quantity to the bit: the clutch from a flat-out launch's
## slips (its slip energy times the rate, the brakes untouched); the brakes
## from a full stop (each disc's work times the rate, the fronts more by the
## bias, the engine untouched on the overrun); the tyres from a donut (the
## rears' heat times the rate, three times over once they are over the
## window, the fronts hardly, the brakes untouched); the engine from
## revolutions under load (flat out from rest), none at all free-revving at
## the limiter in neutral, and every revolution ten times over idling on an
## overheated engine. Then the worn car, measurably and boundedly different:
## worn brakes stop the car longer, a worn clutch bites softer and slips
## longer, worn tyres hold less in the same corner, a worn engine makes less
## torque, and past worn-out nothing gets worse - the floor holds. Then the
## store: the six shares go through a file of the test's own and come back
## to the bit in the one entry beside the rest, in the one write, an old file
## without them is a new car's and rounds through untouched, what is no
## share of a life is refused with the reason naming the car and the field,
## and a car that loads worn components starts with them. Then the reset: it
## keeps the wear to the bit (R refuels, it does not un-wear) and tells the
## file nothing; a handling test's start hands out the new car. Last, nothing
## of it is ever NaN.
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

## The corner the fresh and the worn grip are compared in (the tyre/brake
## thermal test's): the steer held at this share of the lock from 60 km/h with
## this much throttle for this many ticks (4 s), the peak lateral acceleration
## compared.
const CORNER_STEER := 0.5
const CORNER_THROTTLE := 0.3
const CORNER_FROM_KMH := 60.0
const CORNER_FRAMES := 240

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
const TMP_DIR_PREFIX := "/tmp/fd-3L-wear-"
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
## - an idling car wears nothing.
func _check_suite_gate(car: ArcadeCar) -> void:
	var zero_at_start := _wear_at_start.size() == WEAR_FIELDS.size() and _all_equal(_wear_at_start, 0.0)
	var one_at_start := _factors_at_start.size() == 6 and _all_equal(_factors_at_start, 1.0)
	var still_zero := _all_equal(_shares(car), 0.0) and _all_equal(_factors(car), 1.0) and car._clutch_slip_w == 0.0
	_check(
		zero_at_start and one_at_start and still_zero and not OdometerStore.enabled() and not car._odometer_kept,
		"suite: the car came out of _ready with nothing worn - all six shares exactly 0, the clutch's, the brakes', the tyres' and the engine's multipliers exactly 1 - the store off whatever %s holds, and after %d idling ticks still nothing" % [OdometerStore.PATH, SETTLE_FRAMES],
	)


## The model's own numbers: a multiplier is exactly 1 under a hundredth of
## wear, one step down per hundredth from there, in a line to the floor at
## worn out and never under it past that; the config's rates, multipliers and
## floors are the car's; and the curve's peak is what the engine's load is
## weighed against.
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
	var statics := {
		"clutch_rate": ArcadeCar.CLUTCH_WEAR_RATE, "clutch_floor": ArcadeCar.CLUTCH_WEAR_FLOOR,
		"brake_rate": ArcadeCar.BRAKE_WEAR_RATE, "brake_abuse": ArcadeCar.BRAKE_WEAR_ABUSE, "brake_floor": ArcadeCar.BRAKE_WEAR_FLOOR,
		"tyre_rate": ArcadeCar.TYRE_WEAR_RATE, "tyre_abuse": ArcadeCar.TYRE_WEAR_ABUSE, "tyre_floor": ArcadeCar.TYRE_WEAR_FLOOR,
		"engine_rate": ArcadeCar.ENGINE_WEAR_RATE, "engine_abuse": ArcadeCar.ENGINE_WEAR_ABUSE, "engine_floor": ArcadeCar.ENGINE_WEAR_FLOOR,
	}
	var read := 0
	for key: String in statics:
		if wear.has(key) and float(wear[key]) == statics[key]:
			read += 1
	var peak := 0.0
	for anchor: Vector2 in ArcadeCar.TORQUE_CURVE:
		peak = maxf(peak, anchor.y)
	_check(
		read == statics.size() and wear.size() == statics.size() and ArcadeCar.ENGINE_PEAK_TORQUE == peak and peak > 0.0
			and ArcadeCar.BRAKE_WEAR_ABUSE >= 1.0 and ArcadeCar.TYRE_WEAR_ABUSE >= 1.0 and ArcadeCar.ENGINE_WEAR_ABUSE >= 1.0,
		"model: all %d numbers of the config's wear table are the car's to the bit (clutch %.1f %% per GJ of slip, brakes %.1f %% per GJ of work and x%.0f over the fade line, tyres %.1f %% per GJ of heat and x%.0f over the window, engine %.1f %% per Grad under load and x%.0f overheated), and the engine's load is weighed against the curve's %.0f Nm peak" % [statics.size(), ArcadeCar.CLUTCH_WEAR_RATE * 1.0e11, ArcadeCar.BRAKE_WEAR_RATE * 1.0e11, ArcadeCar.BRAKE_WEAR_ABUSE, ArcadeCar.TYRE_WEAR_RATE * 1.0e11, ArcadeCar.TYRE_WEAR_ABUSE, ArcadeCar.ENGINE_WEAR_RATE * 1.0e11, ArcadeCar.ENGINE_WEAR_ABUSE, ArcadeCar.ENGINE_PEAK_TORQUE],
	)


## The validation: a config without a wear table is a car, one with an empty
## table is a car, and a rate under zero, an abuse multiplier under 1, a floor
## of 0 or over 1 and a key the schema does not know are each refused by name
## - by the validation's functions alone, never read into the running car.
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
	bad.wear.clutch_rate = -1.0e-8
	bad.wear.brake_abuse = 0.5
	bad.wear.tyre_floor = 0.0
	bad.wear.engine_floor = 1.5
	bad.wear.clutch_abuse = 2.0
	var faults := CarConfigValidation.validate(bad, "worn")
	var named := 0
	for fault: String in faults:
		if fault.begins_with("worn: wear.clutch_rate is") or fault.begins_with("worn: wear.brake_abuse is") or fault.begins_with("worn: wear.tyre_floor is") \
				or fault.begins_with("worn: wear.engine_floor is") or fault == "worn: wear.clutch_abuse is not in the schema":
			named += 1
	var nan_rate: Dictionary = config.duplicate(true)
	nan_rate.wear.engine_rate = NAN
	var nan_faults := CarConfigValidation.validate(nan_rate, "nan")
	_check(
		CarConfigValidation.validate(without, "bare").is_empty() and CarConfigValidation.validate(empty, "empty").is_empty() and CarConfigValidation.validate(one_floor, "one").is_empty()
			and faults.size() == 5 and named == 5 and nan_faults.size() == 1 and nan_faults[0] == "nan: wear.engine_rate is not a finite number"
			and ArcadeCar.CLUTCH_WEAR_RATE > 0.0 and ArcadeCar.BRAKE_WEAR_ABUSE >= 1.0 and ArcadeCar.TYRE_WEAR_FLOOR > 0.0,
		"validation: a config without a wear table is a car, so is one with an empty table and one with a floor of 1; a rate under zero, an abuse under 1, a floor of 0, a floor over 1 and a key the schema does not know are refused by name (%d faults: %s); a NaN rate is not a finite number; the running car kept its own" % [faults.size(), "; ".join(faults)],
	)


## The clutch wears from its slips: a flat-out launch from rest through the
## upshifts costs it exactly its rate times the slip energy the tick's own
## tracker adds up to, and nothing while it is locked; the brakes, untouched,
## wear exactly nothing; the tyres roll and the engine turns under load, so
## they wear a little (their own checks below).
func _check_clutch(car: ArcadeCar) -> void:
	var tick := 1.0 / Engine.physics_ticks_per_second
	_fresh(car)
	await _step(SETTLE_FRAMES)
	var slip_j := 0.0
	var slipping_ticks := 0
	var locked_ticks_wore := 0
	var wear_grew_while_locked := false
	var last := car.clutch_wear
	var shifts := 0
	var last_gear := car.gear
	car.set_driver_input(1.0, 0.0, 0.0)
	for frame in LAUNCH_FRAMES:
		await physics_frame
		slip_j += car._clutch_slip_w * tick
		if car._clutch_slip_w > 0.0:
			slipping_ticks += 1
		elif car.clutch_wear != last:
			locked_ticks_wore += 1
		if car.gear != last_gear:
			shifts += 1
			last_gear = car.gear
		last = car.clutch_wear
	var expected := ArcadeCar.CLUTCH_WEAR_RATE * slip_j
	var speed := car.speed_kmh
	var others := _shares(car)
	car.clear_driver_input()
	_fresh(car)
	await _step(5)
	_check(
		slip_j > 0.0 and slipping_ticks > 0 and slipping_ticks < LAUNCH_FRAMES and locked_ticks_wore == 0 and last > 0.0
			and absf(last / expected - 1.0) < WIRING_TOLERANCE and shifts >= 2
			and others[1] == 0.0 and others[2] == 0.0 and others[3] > 0.0 and others[4] > 0.0 and others[5] > 0.0
			and last < ArcadeCar.WEAR_EFFECT_STEP,
		"clutch: %.0f s flat out from rest (%d upshifts, %.0f km/h) slips the clutch %.1f kJ over %d ticks and wears it %.1f ppm - the rate times the slip energy to the bit, nothing on the %d locked ticks, %.0f such launches to the first hundredth; the brakes wore exactly 0, the tyres %.2f and %.2f ppm and the engine %.2f ppm meanwhile (rolling, turning under load)" % [LAUNCH_FRAMES * tick, shifts, speed, slip_j / 1000.0, slipping_ticks, last * 1.0e6, LAUNCH_FRAMES - slipping_ticks, ArcadeCar.WEAR_EFFECT_STEP / last, others[3] * 1.0e6, others[4] * 1.0e6, others[5] * 1.0e6],
	)


## The brakes wear from their work: a full stop from 90 km/h costs each axle's
## discs exactly the rate times the work they were given (the rears' more on
## this car: the ABS holds the fronts at the tyres' limit, and the driven
## axle's discs slow the engine too); the engine wears exactly the rate times
## the radians the clutch had a load on the crank - the flywheel unloading
## into the braked driveline, the downshifts' catches - a small share of a
## launch's.
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
	var fade_ticks := 0
	var engine_expected := 0.0
	var loaded_ticks := 0
	car.set_driver_input(0.0, 1.0, 0.0)
	var ticks := 0
	while car.speed_kmh > STOPPED_KMH and ticks < 600:
		await physics_frame
		ticks += 1
		front_j += car._front_brake_heat_w * tick
		rear_j += car._rear_brake_heat_w * tick
		if ArcadeCar.brake_fade(car.front_brake_temp) < 1.0 or ArcadeCar.brake_fade(car.rear_brake_temp) < 1.0:
			fade_ticks += 1
		var load_share := clampf(car.clutch_torque / ArcadeCar.ENGINE_PEAK_TORQUE, 0.0, 1.0)
		if load_share > 0.0:
			loaded_ticks += 1
		engine_expected += ArcadeCar.ENGINE_WEAR_RATE * absf(car.engine_omega) * tick * load_share
	var after := _shares(car)
	var front_wear := after[1] - before[1]
	var rear_wear := after[2] - before[2]
	var front_expected := ArcadeCar.BRAKE_WEAR_RATE * front_j
	var rear_expected := ArcadeCar.BRAKE_WEAR_RATE * rear_j
	var engine_wear := after[5] - before[5]
	var clutch_wear := after[0] - before[0]
	car.clear_driver_input()
	_fresh(car)
	await _step(5)
	_check(
		car.speed_kmh <= STOPPED_KMH + 1.0 and front_j > 0.0 and rear_j > 0.0 and fade_ticks == 0
			and front_wear > 0.0 and rear_wear > 0.0 and absf(front_wear / front_expected - 1.0) < WIRING_TOLERANCE and absf(rear_wear / rear_expected - 1.0) < WIRING_TOLERANCE
			and loaded_ticks < ticks and (engine_wear == engine_expected or absf(engine_wear / engine_expected - 1.0) < WIRING_TOLERANCE) and engine_wear < 0.1 * before[5]
			and rear_wear < ArcadeCar.WEAR_EFFECT_STEP,
		"brakes: a stop from %.0f km/h (%d ticks, the discs under the fade line throughout) gives the front discs %.0f kJ of work and the rears %.0f kJ (the driven axle's slow the engine too, the ABS holds the fronts at the tyres' limit) and wears them %.1f and %.1f ppm - the rate times the work to the bit each, %.0f such stops to the rears' first hundredth; the engine wore %.2f ppm - exactly the rate times the radians of the %d ticks the clutch had a load on the crank (the flywheel unloading into the braked driveline, the downshifts' catches), nothing on the other %d, under a tenth of the %.1f ppm the drive up to speed cost; the clutch %.2f ppm through those downshifts" % [from_kmh, ticks, front_j / 1000.0, rear_j / 1000.0, front_wear * 1.0e6, rear_wear * 1.0e6, ArcadeCar.WEAR_EFFECT_STEP / rear_wear, engine_wear * 1.0e6, loaded_ticks, ticks - loaded_ticks, before[5] * 1.0e6, clutch_wear * 1.0e6],
	)


## The tyres wear from their heat: a donut (full throttle, full lock, the aids
## off) costs the rears exactly the rate times the heat they were given, three
## times over on every tick they are over the window, the fronts a small
## fraction of it; the brakes do no work on any tick the pedal is off (the
## spinning car rolls backwards for a few ticks, where the throttle key is the
## brake: the driver's rule, and those ticks alone wear them).
func _check_tyres(car: ArcadeCar) -> void:
	var tick := 1.0 / Engine.physics_ticks_per_second
	_fresh(car)
	await _step(SETTLE_FRAMES)
	car.tcs_on = false
	car.sc_on = false
	car.set_driver_input(1.0, 0.0, 1.0)
	var rear_expected := 0.0
	var front_expected := 0.0
	var rear_j := 0.0
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
		rear_expected += ArcadeCar.TYRE_WEAR_RATE * car._rear_tyre_heat_w * tick * (ArcadeCar.TYRE_WEAR_ABUSE if rear_hot else 1.0)
		front_expected += ArcadeCar.TYRE_WEAR_RATE * car._front_tyre_heat_w * tick * (ArcadeCar.TYRE_WEAR_ABUSE if front_hot else 1.0)
		rear_j += car._rear_tyre_heat_w * tick
		if rear_hot:
			hot_ticks += 1
			hot_j += car._rear_tyre_heat_w * tick
	var shares := _shares(car)
	var rear_c := ArcadeCar.tyre_c_of(car.rear_tyre_temp)
	car.clear_driver_input()
	car.tcs_on = true
	car.sc_on = true
	_fresh(car)
	await _step(5)
	_check(
		shares[4] > 0.0 and absf(shares[4] / rear_expected - 1.0) < WIRING_TOLERANCE and absf(shares[3] / front_expected - 1.0) < WIRING_TOLERANCE
			and shares[4] > 5.0 * shares[3] and hot_ticks > 0 and hot_ticks < DONUT_FRAMES and hot_j > 0.0
			and off_pedal_brake_j == 0.0 and pedal_ticks < DONUT_FRAMES / 4 and (pedal_ticks > 0 or (shares[1] == 0.0 and shares[2] == 0.0))
			and shares[4] < ArcadeCar.WEAR_EFFECT_STEP and shares[0] < ArcadeCar.WEAR_EFFECT_STEP,
		"tyres: a %.0f s donut puts %.0f kJ into the rears (%.0f kJ of it on the %d ticks they are over the window, %.0f C at the end) and wears them %.1f ppm - the rate times the heat to the bit, %.0f times over on the hot ticks - and the fronts %.2f ppm, %.0f times less; the brakes did exactly no work on the %d ticks the pedal was off (%.1f and %.1f ppm on the %d ticks it was on: the spinning car rolled backwards on %d ticks, where the throttle key is the brake); the clutch %.0f ppm, slipping under the automatic's hunting; %.0f such donuts to the rears' first hundredth" % [DONUT_FRAMES * tick, rear_j / 1000.0, hot_j / 1000.0, hot_ticks, rear_c, shares[4] * 1.0e6, ArcadeCar.TYRE_WEAR_ABUSE, shares[3] * 1.0e6, shares[4] / shares[3], DONUT_FRAMES - pedal_ticks, shares[1] * 1.0e6, shares[2] * 1.0e6, pedal_ticks, backwards_ticks, shares[0] * 1.0e6, ArcadeCar.WEAR_EFFECT_STEP / shares[4]],
	)


## The engine wears from its revolutions under load: flat out from rest it
## wears exactly the rate times the radians turned weighted by the load on the
## crank; free-revving at the limiter in neutral, under no load, it wears
## exactly nothing (and nor does anything else); idling overheated in neutral
## every revolution counts in full and ten times over, where the same warm
## idle costs exactly nothing.
func _check_engine(car: ArcadeCar) -> void:
	var tick := 1.0 / Engine.physics_ticks_per_second
	_fresh(car)
	await _step(SETTLE_FRAMES)
	car.set_driver_input(1.0, 0.0, 0.0)
	var expected := 0.0
	var loaded_rad := 0.0
	var rad := 0.0
	for frame in LAUNCH_FRAMES:
		await physics_frame
		var load_share := clampf(car.clutch_torque / ArcadeCar.ENGINE_PEAK_TORQUE, 0.0, 1.0)
		expected += ArcadeCar.ENGINE_WEAR_RATE * absf(car.engine_omega) * tick * load_share
		loaded_rad += absf(car.engine_omega) * tick * load_share
		rad += absf(car.engine_omega) * tick
	var loaded_wear := car.engine_wear
	car.clear_driver_input()

	# Neutral, full throttle: the limiter, no load.
	_fresh(car)
	await _step(SETTLE_FRAMES)
	car.automatic = false
	car.shift_down()
	car.set_driver_input(1.0, 0.0, 0.0)
	var limited := false
	for frame in NEUTRAL_REV_FRAMES:
		await physics_frame
		limited = limited or car.limiter_cutting
	var free := _shares(car)
	var in_neutral := car.gear == 0
	car.clear_driver_input()

	# Neutral, idling: warm, then overheated.
	_fresh(car)
	await _step(SETTLE_FRAMES)
	car.automatic = false
	car.shift_down()
	await _step(HOT_IDLE_FRAMES)
	var warm_idle := car.engine_wear
	var hot_expected := 0.0
	var hot_rad := 0.0
	var hot := ArcadeCar.coolant_temp_of_c(HOT_C)
	for frame in HOT_IDLE_FRAMES:
		car.coolant_temp = hot
		await physics_frame
		hot_expected += ArcadeCar.ENGINE_WEAR_RATE * ArcadeCar.ENGINE_WEAR_ABUSE * absf(car.engine_omega) * tick
		hot_rad += absf(car.engine_omega) * tick
	var hot_idle := car.engine_wear
	var idle_rpm := car.engine_rpm
	_fresh(car)
	await _step(5)
	_check(
		loaded_wear > 0.0 and absf(loaded_wear / expected - 1.0) < WIRING_TOLERANCE and loaded_rad > 0.0 and loaded_rad < rad
			and limited and in_neutral and _all_equal(free, 0.0)
			and warm_idle == 0.0 and hot_idle > 0.0 and absf(hot_idle / hot_expected - 1.0) < WIRING_TOLERANCE and loaded_wear < ArcadeCar.WEAR_EFFECT_STEP,
		"engine: %.0f s flat out from rest turns it %.0f krad, %.0f krad of them weighted under load, and wears it %.2f ppm - the rate times the loaded radians to the bit, %.0f such runs to the first hundredth; %.0f s at the limiter in neutral wears it, and everything else, exactly 0; %.0f s idling warm in neutral exactly 0, the same idling at %.0f C (%.0f rpm, %.0f rad) %.2f ppm - every radian in full and %.0f times over" % [LAUNCH_FRAMES * tick, rad / 1000.0, loaded_rad / 1000.0, loaded_wear * 1.0e6, ArcadeCar.WEAR_EFFECT_STEP / loaded_wear, NEUTRAL_REV_FRAMES * tick, HOT_IDLE_FRAMES * tick, HOT_C, idle_rpm, hot_rad, hot_idle * 1.0e6, ArcadeCar.ENGINE_WEAR_ABUSE],
	)


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
	await _step(5)
	_check(
		loaded_ok and under_one and settings_ok and grew_only and _all_equal(_shares(car), 0.0),
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
	car.reset_to_spawn()
	pad.reset_cones()
	_fresh(car)
	await _step(5)
	_check(
		kept and worn_after and still_kept and file_untold and fresh,
		"reset keeps the wear: six shares set by hand (%.2f .. %.2f) are there to the bit after a reset, the multipliers still under 1, and still there after %d idling ticks, the file not told; a handling test's start on that worn car hands out the new one before its first tick - every share exactly 0, every multiplier exactly 1" % [set_to[0], set_to[5], SETTLE_FRAMES],
	)


## Nothing of it is ever NaN: a NaN share is none, inf worn out, -inf none; a
## tick's NaN or negative quantity adds nothing and takes nothing; and after
## everything above the whole state is finite.
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
	car._clutch_slip_w = NAN
	car._front_brake_heat_w = NAN
	car._rear_brake_heat_w = -1000.0
	car._front_tyre_heat_w = -INF
	car._rear_tyre_heat_w = NAN
	car.engine_omega = NAN
	car._advance_wear(tick)
	var unchanged := _shares(car) == before
	car.engine_omega = ArcadeCar.IDLE_RPM * TAU / 60.0
	_fresh(car)
	await _step(2)
	var finite := true
	for share: float in _shares(car):
		finite = finite and is_finite(share)
	for factor: float in _factors(car):
		finite = finite and is_finite(factor)
	_check(nan_none and inf_out and neg_inf_none and unchanged and finite, "no NaN: a NaN share is none (the multiplier 1), inf is worn out (the multiplier the floor), -inf none; NaN, -inf and negative tick quantities add nothing and take nothing (six shares unchanged to the bit); and the whole state is finite after the run")


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
## reset keeps the heat) and the new components (a reset keeps the wear) -
## what HandlingTests._start sets for a certified run.
func _fresh(car: ArcadeCar) -> void:
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
