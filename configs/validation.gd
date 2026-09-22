class_name CarConfigValidation
extends RefCounted
## Checks a car's config (configs/cars/*.json, see configs/README.md) before a
## car is built from it. A config is a car's primary numbers and nothing else;
## what is wrong with one has to be said out loud before the first tick, because
## a number that is missing, misspelt or not a number does not crash a physics
## model, it drives: a bad config must never silently become wrong physics.
##
## Static and stateless: validate() takes what JSON.parse_string made of the
## file and the name to call the car by in the messages, and returns what is
## wrong with it as a PackedStringArray, one line per fault. Empty = valid. It
## reports and nothing else; whoever asked decides what a fault costs (the car
## stops the game on one: push_error and assert, see ArcadeCar._read_config).
## Generic: nothing in here knows a Boxster from a 911, a new car is a new file.
##
## A class of static functions, as OdometerStore is, and no autoload: a global
## class name resolves wherever a script is compiled, the headless tests' --script
## SceneTrees included, where an autoload's name does not (they are compiled, and
## car.gd with them, before the autoloads are there).

## The schema this code checks: a config says which one it was written for
## ("config_version"), and any other is refused rather than guessed at.
const VERSION := 1

## The numbers every car has to bring, section by section: all finite.
const REQUIRED_NUMBERS := {
	"mass": ["kerb_mass", "rear_weight_fraction", "cg_height", "axle_distance", "yaw_gyration_radius"],
	"engine": ["idle_rpm", "redline_rpm", "limiter_resume_rpm", "engine_inertia", "friction_torque", "friction_torque_per_rpm"],
	"fuel": ["tank_capacity_l", "burn_efficiency", "lhv", "density"],
	"gearbox": ["final_drive", "reverse_ratio", "drivetrain_efficiency", "clutch_torque_max", "clutch_engage_time", "clutch_shift_engage_time"],
	"brakes": ["bias_front", "decel_g"],
	"tyres": [
		"mu", "front_grip", "rear_grip", "peak_slip_ratio", "abs_slip_ratio", "drive_slip_ratio",
		"front_peak_slip_angle", "rear_peak_slip_angle", "slide_grip", "rear_slide_grip", "slide_onset",
		"axle_inertia", "min_combined_grip", "load_grip_exponent",
	],
	"suspension": [
		"front_ride_frequency", "rear_ride_frequency", "ride_damping_ratio", "front_anti_roll_rate",
		"rear_anti_roll_rate", "travel", "ground_clearance",
	],
	"steering": ["max_steer_lock", "wheel_lock_deg", "hand_speed"],
	"aero": ["drag_coeff", "frontal_area", "downforce_coeff", "balance_front"],
	"handbrake": ["release_torque", "rear_lock_recovery_rate"],
	"launch": ["rpm"],
}

## The numbers a car may leave out, and then gets car.gd's documented default
## for: finite where they are there. A section that holds nothing else ("idle",
## "exhaust", "battery", "thermal", "creep") may be left out whole.
const OPTIONAL_NUMBERS := {
	"engine": ["stall_rpm", "cranking_torque", "starter_free_rpm", "starter_cycle_time", "engine_catch_rpm", "firings_per_revolution"],
	"idle": ["control_gain", "control_max_throttle"],
	"exhaust": ["flow_at_rest", "flow_rate"],
	"battery": [
		"capacity_ah", "starter_power", "key_on_load", "running_load", "alternator_power", "alternator_cut_in_rpm",
		"alternator_rated_rpm", "charge_efficiency", "taper_charge", "deep_discharge_charge", "deep_discharge_wear",
		"flat_wear_rate",
	],
	"thermal": [
		"ambient_c", "operating_c", "thermostat_c", "warm_c", "fan_on_c", "fan_off_c", "max_c", "coolant_heat_capacity",
		"heat_share", "radiator_cooling", "fan_airflow", "overheat_fade_start_c", "overheat_fade_rate", "rich_factor",
		"idle_wobble_rpm", "idle_wobble_hz",
		"tyre_operating_c", "tyre_window_low_c", "tyre_window_high_c", "tyre_max_c", "tyre_heat_capacity",
		"tyre_slip_heat_share", "tyre_cooling_still", "tyre_cooling_airflow", "tyre_cold_grip", "tyre_fade_rate",
		"brake_fade_start_c", "brake_fade_rate", "brake_fade_floor", "brake_red_hot_c", "brake_max_c",
		"brake_heat_capacity", "brake_cooling_still", "brake_cooling_airflow",
	],
	"creep": ["clutch_engagement", "free_speed", "engage_speed", "dwell", "max_speed"],
	"brakes": ["coast_decel"],
	"suspension": ["bump_stop_rate", "bump_stop_progression"],
	"aero": ["air_density"],
	"launch": ["clutch_share", "bite_band"],
}

## What is in a config besides plain numbers, each with a check of its own
## below: section -> keys, "" for what stands at the top of the file.
const OTHER_KEYS := {
	"": ["config_version", "identity", "mass_ledger", "driver_profiles", "mode_drivers"],
	"identity": ["name", "car_id"],
	"engine": ["torque_curve"],
	"gearbox": ["ratios"],
}

## What a driver profile is made of: rates, so finite and never negative. And
## the profile every car has to have: whoever is seated gets what their own
## profile leaves out from this one (see ArcadeCar.set_driver_profile).
const PROFILE_RATES := ["throttle_attack", "throttle_release", "brake_attack", "brake_release", "steering_hand_speed"]
const BASE_PROFILE := "test_driver"

## The automatic's programs, as "mode_drivers" names them: each one seats a
## driver, so each has to be there and name a profile that is.
const MODES := ["sport", "comfort", "eco"]


## Everything that is wrong with `config`, one line each, `car_name` in front;
## empty if it is a valid car.
static func validate(config: Variant, car_name: String) -> PackedStringArray:
	var errors := PackedStringArray()
	if not config is Dictionary:
		errors.append("%s: not a JSON object (a file that is not there, or not JSON)" % car_name)
		return errors
	var car: Dictionary = config
	if not _is_number(car.get("config_version")) or car.config_version != VERSION:
		errors.append("%s: config_version is %s, this code reads version %d" % [car_name, car.get("config_version"), VERSION])
	for section: String in REQUIRED_NUMBERS:
		if not car.get(section) is Dictionary:
			errors.append("%s: section %s is missing" % [car_name, section])
			continue
		for key: String in REQUIRED_NUMBERS[section]:
			if not car[section].has(key):
				errors.append("%s: %s.%s is missing" % [car_name, section, key])
	for section: String in car:
		if not _check_known(errors, car_name, "", section) or (section in OTHER_KEYS[""] and section != "identity"):
			continue
		if not car[section] is Dictionary:
			if not REQUIRED_NUMBERS.has(section) and section != "identity":
				errors.append("%s: %s is not a section" % [car_name, section])
			continue
		for key: String in car[section]:
			if not _check_known(errors, car_name, section, key):
				continue
			if key in OTHER_KEYS.get(section, []):
				continue
			if not _is_number(car[section][key]):
				errors.append("%s: %s.%s is not a finite number" % [car_name, section, key])
	_check_identity(errors, car_name, car.get("identity"))
	_check_mass_ledger(errors, car_name, car.get("mass_ledger"), car.get("mass"))
	if car.get("engine") is Dictionary:
		_check_torque_curve(errors, car_name, car.engine)
	if car.get("gearbox") is Dictionary:
		_check_ratios(errors, car_name, car.gearbox.get("ratios"))
	_check_drivers(errors, car_name, car.get("driver_profiles"), car.get("mode_drivers"))
	return errors


## A number a car can be built from: an int or a float, and finite.
static func _is_number(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(value)


## Whether the schema knows `key` in `section` ("" = a section's own name). One
## it does not know is a fault: a misspelt optional key would otherwise read as
## left out, and the car would quietly drive on the default.
static func _check_known(errors: PackedStringArray, car_name: String, section: String, key: String) -> bool:
	var known: Array = REQUIRED_NUMBERS.get(section, []) + OPTIONAL_NUMBERS.get(section, []) + OTHER_KEYS.get(section, [])
	if section == "":
		known = REQUIRED_NUMBERS.keys() + OPTIONAL_NUMBERS.keys() + OTHER_KEYS[""]
	if key in known:
		return true
	errors.append("%s: %s is not in the schema" % [car_name, key if section == "" else "%s.%s" % [section, key]])
	return false


## The car's two names: what it is called, and what its odometer is kept under.
static func _check_identity(errors: PackedStringArray, car_name: String, identity: Variant) -> void:
	if not identity is Dictionary:
		errors.append("%s: section identity is missing" % car_name)
		return
	for key: String in OTHER_KEYS["identity"]:
		if not identity.get(key) is String or identity[key] == "":
			errors.append("%s: identity.%s is missing or not a name" % [car_name, key])


## The mass ledger (3W, docs/car-component-audit.md section 4): the car's kerb
## mass as a table of its components, one row each of {name, mass_kg,
## x_position_m, sprung} and nothing else, at least one row; the name a name,
## the mass finite and above zero, sprung true or false, the position finite
## and on the wheelbase (|x| <= mass.axle_distance; x from the middle of the
## wheelbase, positive toward the rear, the sign of ArcadeCar.CG_OFFSET). Then
## what the rows add up to has to be the car's certified figures TO THE BIT,
## with the same plain sums car.gd draws its corner masses from
## (_derive_from_config): the masses in row order == mass.kerb_mass, the
## rear axle's share of the weight, sum of m x (a + x) over 2 a x the total,
## == mass.rear_weight_fraction, and some but not all of the mass unsprung.
## Exact equality is meant: a table is authored to the bit (the last row's
## position calibrated, see configs/README.md), and a fault says both numbers
## to every digit that reads back (var_to_str) so that a new car's author has
## what to calibrate against.
static func _check_mass_ledger(errors: PackedStringArray, car_name: String, ledger: Variant, mass: Variant) -> void:
	if not ledger is Array or ledger.is_empty():
		errors.append("%s: section mass_ledger is missing or has no component row" % car_name)
		return
	var axle_distance: float = mass.axle_distance if mass is Dictionary and _is_number(mass.get("axle_distance")) else INF
	var rows_ok := true
	for i: int in ledger.size():
		var row: Variant = ledger[i]
		if not row is Dictionary or row.size() != 4 or not (row.has("name") and row.has("mass_kg") and row.has("x_position_m") and row.has("sprung")):
			errors.append("%s: mass_ledger[%d] is not a row of exactly name, mass_kg, x_position_m, sprung" % [car_name, i])
			return
		if not row.name is String or row.name == "":
			errors.append("%s: mass_ledger[%d].name is missing or not a name" % [car_name, i])
			rows_ok = false
		if not _is_number(row.mass_kg) or row.mass_kg <= 0.0:
			errors.append("%s: mass_ledger[%d].mass_kg is %s, not a finite mass above zero" % [car_name, i, row.mass_kg])
			rows_ok = false
		if not _is_number(row.x_position_m) or absf(row.x_position_m) > axle_distance:
			errors.append("%s: mass_ledger[%d].x_position_m is %s, not a finite position on the wheelbase (|x| <= axle_distance %s)" % [car_name, i, row.x_position_m, axle_distance])
			rows_ok = false
		if not row.sprung is bool:
			errors.append("%s: mass_ledger[%d].sprung is %s, not true or false" % [car_name, i, row.sprung])
			rows_ok = false
	if not rows_ok or not is_finite(axle_distance):
		return
	var total := 0.0
	var moment := 0.0
	var unsprung := 0.0
	for row: Dictionary in ledger:
		total += row.mass_kg
		moment += row.mass_kg * (axle_distance + row.x_position_m)
		if not row.sprung:
			unsprung += row.mass_kg
	var rear_fraction := moment / (2.0 * axle_distance * total)
	if _is_number(mass.get("kerb_mass")) and total != mass.kerb_mass:
		errors.append("%s: mass_ledger sums to %s kg, mass.kerb_mass is %s" % [car_name, var_to_str(total), var_to_str(mass.kerb_mass)])
	if _is_number(mass.get("rear_weight_fraction")) and rear_fraction != mass.rear_weight_fraction:
		errors.append("%s: mass_ledger puts %s of the weight on the rear axle, mass.rear_weight_fraction is %s" % [car_name, var_to_str(rear_fraction), var_to_str(mass.rear_weight_fraction)])
	if unsprung <= 0.0 or unsprung >= total:
		errors.append("%s: mass_ledger's unsprung rows weigh %s kg of %s, some but not all of the car has to be unsprung" % [car_name, unsprung, total])


## The torque curve: at least two [rpm, Nm] anchors of finite numbers, the rpm
## rising from one to the next, no torque under zero, and the limiter no lower
## than the curve's last anchor (the engine never turns past it, see
## ArcadeCar.engine_torque).
static func _check_torque_curve(errors: PackedStringArray, car_name: String, engine: Dictionary) -> void:
	var curve: Variant = engine.get("torque_curve")
	if not curve is Array or curve.size() < 2:
		errors.append("%s: engine.torque_curve needs at least two [rpm, Nm] anchors" % car_name)
		return
	var last_rpm := -INF
	for i: int in curve.size():
		var anchor: Variant = curve[i]
		if not anchor is Array or anchor.size() != 2 or not _is_number(anchor[0]) or not _is_number(anchor[1]):
			errors.append("%s: engine.torque_curve[%d] is not two finite numbers, [rpm, Nm]" % [car_name, i])
			return
		if anchor[0] <= last_rpm:
			errors.append("%s: engine.torque_curve[%d] is at %s rpm, not above the anchor before it" % [car_name, i, anchor[0]])
		if anchor[1] < 0.0:
			errors.append("%s: engine.torque_curve[%d] is %s Nm, under zero" % [car_name, i, anchor[1]])
		last_rpm = anchor[0]
	if _is_number(engine.get("redline_rpm")) and engine.redline_rpm < last_rpm:
		errors.append("%s: engine.redline_rpm %s is under the torque curve's last anchor (%s rpm)" % [car_name, engine.redline_rpm, last_rpm])


## The gear ratios: neutral's 0 first, then at least one forward gear, each a
## finite ratio above zero.
static func _check_ratios(errors: PackedStringArray, car_name: String, ratios: Variant) -> void:
	if not ratios is Array or ratios.size() < 2:
		errors.append("%s: gearbox.ratios needs neutral's 0 and at least one forward gear" % car_name)
		return
	for i: int in ratios.size():
		if not _is_number(ratios[i]) or (i == 0 and ratios[i] != 0.0) or (i > 0 and ratios[i] <= 0.0):
			errors.append("%s: gearbox.ratios[%d] is %s, where %s belongs" % [car_name, i, ratios[i], "neutral's 0" if i == 0 else "a ratio above zero"])


## The drivers: every profile all five rates and nothing else, finite and not
## negative, the base profile among them, and every program of the automatic
## seating one of them.
static func _check_drivers(errors: PackedStringArray, car_name: String, profiles: Variant, mode_drivers: Variant) -> void:
	if not profiles is Dictionary or not profiles.get(BASE_PROFILE) is Dictionary:
		errors.append("%s: driver_profiles.%s is missing" % [car_name, BASE_PROFILE])
		return
	for profile_name: String in profiles:
		for rate: String in PROFILE_RATES:
			var value: Variant = profiles[profile_name].get(rate) if profiles[profile_name] is Dictionary else null
			if not _is_number(value) or value < 0.0:
				errors.append("%s: driver_profiles.%s.%s is not a finite rate of zero or more" % [car_name, profile_name, rate])
		for rate: String in profiles[profile_name] if profiles[profile_name] is Dictionary else {}:
			if not rate in PROFILE_RATES:
				errors.append("%s: driver_profiles.%s.%s is not in the schema" % [car_name, profile_name, rate])
	if not mode_drivers is Dictionary:
		errors.append("%s: section mode_drivers is missing" % car_name)
		return
	for mode: String in MODES:
		if not profiles.has(mode_drivers.get(mode)):
			errors.append("%s: mode_drivers.%s names no profile in driver_profiles" % [car_name, mode])
	for mode: String in mode_drivers:
		if not mode in MODES:
			errors.append("%s: mode_drivers.%s is not one of the automatic's programs" % [car_name, mode])
