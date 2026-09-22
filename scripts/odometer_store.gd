class_name OdometerStore
extends RefCounted
## Keeps what a car has on it from one session to the next: its odometer, the
## fuel in its tank, the dashboard it was left with - the aid switches, the
## gearbox program, automatic or manual, and the view the driver was looking
## through - the battery, how full and how worn, the wear, what of its
## clutch, brakes, tyres and engine the car has used up, and the licence, what
## its driver has been certified for at its wheel. One small JSON file
## under user://, an entry per car, e.g.
##   {"version": 1, "cars": {"boxster_986": {"odometer_m": 123.4, "fuel_l": 31.5,
##     "driver": {"tcs_on": true, "abs_on": true, "sc_on": true,
##       "gearbox_mode": "sport", "automatic": true, "camera_view": 1},
##     "battery": {"charge": 0.93, "capacity_wear": 0.0},
##     "wear": {"clutch": 0.012, "brakes_front": 0.03, "brakes_rear": 0.02,
##       "tyres_front": 0.05, "tyres_rear": 0.08, "engine": 0.004},
##     "licence": {"level": 0, "passed": ["L0_CITIZEN", "SLALOM_TEST"],
##       "elements": ["THEORY_QUIZ", "PARALLEL_PARK", "BAY_PARK", "HILL_START",
##         "TURN_IN_ROAD", "REVERSING_COURSE", "EMERGENCY_STOP"]}}}}
## What a car's entry holds, then: odometer_m [m], fuel_l [L], driver (the six
## settings below), battery (the two numbers below), wear (the six shares
## below) and licence (the level, the passes and the L0 elements passed
## below). Not kept yet: where the car was parked.
## A car's entry is a dictionary so the garage can keep more per car than these,
## and a save only ever touches the fields it is handed, of the one car it is
## handed: whatever else the file holds is written back as it was read.
##
## Behind the telemetry's own switch (TelemetryRecorder.should_record): on in
## the running game, off with no window - the headless test suite reads and
## writes nothing, its cars all start at 0 on a full tank - unless
## FD_TELEMETRY=1 asks for it.
## The car does the asking (enabled()); the functions here do as they are told,
## to whatever path, so the tests can try them on a file of their own.
## WHERE user:// IS: every read and write goes through DataDir.resolve, so a
## user:// path lands in the data folder chosen for this run (FD_DATA_DIR or
## the garage's SETTINGS page, scripts/data_dir.gd) and any other path is
## itself - a test's file of its own is read and written where it says.
# was the odometers alone -> the fuel level beside them (fuel_l): it is the
# user's car, and a tank driven half empty one day is half empty the next.
# was odometer and fuel -> the dashboard with them (driver): the switches, the
# program and the view belong to the CAR, not to the session - somebody else
# may have driven it in between, and it is handed over as they left it.
# was odometer, fuel and dashboard -> the battery with them (battery): a
# battery left flat is flat the next day, and what a deep discharge took off
# its capacity stays taken.
# was odometer, fuel, dashboard and battery -> the wear with them (wear): the
# user's wear-and-aging thought, 2026-09-22 07:55 - components age with usage
# and neglect, the odometer is the per-car usage ledger, and what a car has
# worn out is worn out the next day too. VERSION stays 1: a new object in an
# entry, which a file without it reads as a new car's and an old file rounds
# through untouched (_save_fields writes back what it does not know).
# was ... and wear -> the licence with them (licence): the user's licence
# design, 2026-09-22 23:20 - the licence is what gives the clutch key and the
# aid switches a purpose, so it has to outlast the session; per car, riding
# cars.json beside the rest, because this store is the one per-car ledger
# there is (the garage of 4A reads the entry as one thing: the car and who
# may drive it how). VERSION stays 1 for the same reason as the wear. The
# licence manager (scripts/licence_manager.gd) loads and saves it; the car
# knows nothing of it and writes the entry's other fields round it.
# was the level and the passes -> the L0 sitting's elements passed with them
# (licence.elements): the user's verdict, 2026-09-22 14:56 + 15:02 - "it's
# annoying that if i fail any of the L0 tests i need to get back to theory
# and not retry the test i failed, it's like nothing remembers i took the
# tests". Each element passed is kept the moment it is, so the next sitting
# resumes at the first not yet passed. VERSION stays 1 again: a licence
# object without "elements" reads as none passed yet, nothing reported.

## Where the cars' entries live, and the version of what is in there.
const PATH := "user://cars.json"
const VERSION := 1

## The gearbox programs as they are written in a car's entry: lowercase names,
## so the file reads like the dashboard does. The index is the car's own
## numbering (ArcadeCar.GearboxMode: COMFORT 0, SPORT 1, ECO 2), which is why
## that enum is never reordered - the car turns a name into its mode by looking
## it up in here, and a mode into a name by indexing it.
const GEARBOX_MODES: Array[String] = ["comfort", "sport", "eco"]

## The camera views a car can be left in, by their index in ChaseCamera.Mode:
## 0 chase, 1 cockpit, 2 front, 3 overhead, 4 wheel. The rear view (5) is held
## only, for as long as look_back is, and is never one a car is left in.
const CAMERA_VIEW_FIRST := 0
const CAMERA_VIEW_LAST := 4
const CAMERA_VIEW_COCKPIT := 1

## What a car that has never been driven is handed over with - and what a
## setting that is in the file and is none of its own is read as: every aid on,
## the sport program, the automatic shifting for itself, and the cockpit view,
## inside the car. These six fields are a car's whole "driver" object.
const DRIVER_DEFAULTS := {
	"tcs_on": true,
	"abs_on": true,
	"sc_on": true,
	"gearbox_mode": "sport",
	"automatic": true,
	"camera_view": CAMERA_VIEW_COCKPIT,
}

## What a car that has never been driven has for a battery - and what a number
## that is in the file and is none of its own is read as: full and healthy.
## The two fields of a car's whole "battery" object, each 0..1: "charge", the
## energy in it as a share of what the battery held when new, and
## "capacity_wear", the share of that capacity it has lost for good (see
## ArcadeCar.battery_charge / battery_wear). A charge over what the wear leaves
## is the car's to trim, not the file's to refuse: each field is checked alone.
const BATTERY_DEFAULTS := {
	"charge": 1.0,
	"capacity_wear": 0.0,
}

## What a car that has never been driven has worn out - and what a number that
## is in the file and is none of its own is read as: nothing. The six fields of
## a car's whole "wear" object, each 0..1, the share of that component's life
## used up (see ArcadeCar clutch_wear and the rest): "clutch", "brakes_front",
## "brakes_rear", "tyres_front", "tyres_rear", "engine". Each field is checked
## alone.
const WEAR_DEFAULTS := {
	"clutch": 0.0,
	"brakes_front": 0.0,
	"brakes_rear": 0.0,
	"tyres_front": 0.0,
	"tyres_rear": 0.0,
	"engine": 0.0,
}

## What a car that has never been driven has for a licence - and what a field
## that is in the file and is none of its own is read as: none. The three
## fields of a car's whole "licence" object: "level", the licence held
## (LicenceExams.LICENCE_NONE -1, L0 0, L1 1; a whole number in that range),
## "passed", the names of the exams passed at this car's wheel (an array of
## strings, LicenceExams' exam names: the L0 sitting, the skid pad, the five
## handling tests), and "elements", the names of the L0 sitting's elements
## passed at its wheel (an array of strings, LicenceExams.l0_sitting()'s
## names, each kept from the moment it is passed: the next sitting resumes
## at the first missing one). The level is always what the passes and the
## elements earn (LicenceExams.level_for): they are the record, the level in
## the file is a convenience for a reader that has no LicenceExams (the
## garage of 4A), written from them and read back from them, whatever the
## file says. Each field is checked alone; a licence object written before
## there were elements has none and reads as none passed yet.
const LICENCE_DEFAULTS := {
	"level": -1,
	"passed": [],
	"elements": [],
}

## The lowest and highest licence level the file may hold (LicenceExams'
## LICENCE_NONE and LICENCE_L1).
const LICENCE_LEVEL_MIN := -1
const LICENCE_LEVEL_MAX := 1


## Whether a car's entry - odometer, fuel, dashboard - is loaded and saved at
## all in this run.
static func enabled() -> bool:
	return TelemetryRecorder.should_record()


## The odometer stored for `car_id` [m]; 0 for a car, a file or a number that is
## not there (or not finite, or negative: an odometer is neither).
static func load_odometer(car_id: String, path := PATH) -> float:
	var entry: Variant = _cars(_read(path)).get(car_id)
	if not entry is Dictionary:
		return 0.0
	var stored: Variant = (entry as Dictionary).get("odometer_m")
	if not (stored is float or stored is int) or not is_finite(stored) or stored < 0.0:
		return 0.0
	return stored


## The fuel level stored for `car_id`, for a tank of `capacity_l` [L]:
##   {"fuel_l": the level the car starts with [L], "problem": what is wrong}
## No file, no entry or no fuel_l in it is a new car: a full tank, no problem.
## A fuel_l that is there and is no level of this tank (not a number, not
## finite, under 0 or over `capacity_l`) is a full tank too, and "problem" says
## what was found. Nothing is reported from here: the car that asked says it
## (push_error), the tests read the text.
static func load_fuel(car_id: String, capacity_l: float, path := PATH) -> Dictionary:
	var entry: Variant = _cars(_read(path)).get(car_id)
	if not entry is Dictionary or not (entry as Dictionary).has("fuel_l"):
		return {"fuel_l": capacity_l, "problem": ""}
	var problem := fuel_problem((entry as Dictionary)["fuel_l"], capacity_l)
	if problem != "":
		return {"fuel_l": capacity_l, "problem": "%s: %s's fuel_l %s, the tank is taken as full" % [path, car_id, problem]}
	return {"fuel_l": float(entry["fuel_l"]), "problem": ""}


## What keeps `stored` from being a fuel level of a tank of `capacity_l` [L];
## "" when it is one.
static func fuel_problem(stored: Variant, capacity_l: float) -> String:
	if not (stored is float or stored is int):
		return "is not a number (%s)" % str(stored)
	if not is_finite(stored):
		return "is not finite (%s)" % str(stored)
	if stored < 0.0 or stored > capacity_l:
		return "is outside the tank's 0 .. %s L (%s)" % [str(capacity_l), str(stored)]
	return ""


## The dashboard `car_id` was left with:
##   {"tcs_on": bool, "abs_on": bool, "sc_on": bool,
##    "gearbox_mode": one of GEARBOX_MODES, "automatic": bool,
##    "camera_view": int CAMERA_VIEW_FIRST .. CAMERA_VIEW_LAST,
##    "problems": what was wrong with the file, one text per setting}
## No file, no entry or no "driver" in it is a car that has not been driven:
## DRIVER_DEFAULTS, no problems. A setting that is there and is none of its own
## (wrong type, out of range, a program this gearbox has not got) reads as its
## default and puts one text in "problems", naming the car and the field; the
## other five still load. Nothing is reported from here: the car that asked
## says it (push_error), the tests read the texts.
static func load_driver(car_id: String, path := PATH) -> Dictionary:
	var settings := DRIVER_DEFAULTS.duplicate()
	var problems: Array[String] = []
	var entry: Variant = _cars(_read(path)).get(car_id)
	var driver: Variant = (entry as Dictionary).get("driver") if entry is Dictionary else null
	if driver is Dictionary:
		for field: String in DRIVER_DEFAULTS:
			if not (driver as Dictionary).has(field):
				continue
			var stored: Variant = (driver as Dictionary)[field]
			var problem := driver_problem(field, stored)
			if problem != "":
				problems.append("%s: %s's %s %s, %s is used" % [path, car_id, field, problem, str(DRIVER_DEFAULTS[field])])
				continue
			settings[field] = _driver_value(field, stored)
	settings["problems"] = problems
	return settings


## What keeps `stored` from being the driver setting `field`; "" when it is one.
## The switches and automatic are true or false and nothing else; the gearbox
## program is one of GEARBOX_MODES, in any case; the camera view is a whole
## number of the views a car can be left in (the held rear view is not one).
static func driver_problem(field: String, stored: Variant) -> String:
	match field:
		"tcs_on", "abs_on", "sc_on", "automatic":
			return "" if stored is bool else "is not true or false (%s)" % str(stored)
		"gearbox_mode":
			if not stored is String:
				return "is not a program name (%s)" % str(stored)
			if not GEARBOX_MODES.has((stored as String).to_lower()):
				return "is no program of this gearbox (%s), they are %s" % [str(stored), ", ".join(GEARBOX_MODES)]
			return ""
		"camera_view":
			if not (stored is float or stored is int):
				return "is not a view number (%s)" % str(stored)
			var view := float(stored)
			if not is_finite(view):
				return "is not finite (%s)" % str(stored)
			if view != floorf(view):
				return "is no whole view (%s)" % str(stored)
			if view < CAMERA_VIEW_FIRST or view > CAMERA_VIEW_LAST:
				return "is outside the views a car is left in, %d .. %d (%s)" % [CAMERA_VIEW_FIRST, CAMERA_VIEW_LAST, str(stored)]
			return ""
	return "is no driver setting"


# A checked `stored` as the settings dictionary holds it: the program name in
# lowercase (the file may have any case), the camera view a whole int (JSON
# gives every number back as a float), a switch the bool it is.
static func _driver_value(field: String, stored: Variant) -> Variant:
	match field:
		"gearbox_mode":
			return (stored as String).to_lower()
		"camera_view":
			return int(stored)
	return stored


## The battery `car_id` was left with:
##   {"charge": float 0..1, "capacity_wear": float 0..1,
##    "problems": what was wrong with the file, one text per field}
## No file, no entry or no "battery" in it is a car that has not been driven:
## BATTERY_DEFAULTS (full, healthy), no problems. A field that is there and is
## no share of a battery (not a number, not finite, under 0 or over 1) reads as
## its default and puts one text in "problems", naming the car and the field;
## the other field still loads. Nothing is reported from here: the car that
## asked says it (push_error), the tests read the texts. The load_driver idiom,
## field by field.
static func load_battery(car_id: String, path := PATH) -> Dictionary:
	var battery := BATTERY_DEFAULTS.duplicate()
	var problems: Array[String] = []
	var entry: Variant = _cars(_read(path)).get(car_id)
	var stored_battery: Variant = (entry as Dictionary).get("battery") if entry is Dictionary else null
	if stored_battery is Dictionary:
		for field: String in BATTERY_DEFAULTS:
			if not (stored_battery as Dictionary).has(field):
				continue
			var stored: Variant = (stored_battery as Dictionary)[field]
			var problem := battery_problem(field, stored)
			if problem != "":
				problems.append("%s: %s's battery %s %s, %s is used" % [path, car_id, field, problem, str(BATTERY_DEFAULTS[field])])
				continue
			battery[field] = float(stored)
	battery["problems"] = problems
	return battery


## What keeps `stored` from being the battery field `field`; "" when it is one.
## Both are shares, 0..1: a finite number, neither under 0 nor over 1.
static func battery_problem(field: String, stored: Variant) -> String:
	if not field in BATTERY_DEFAULTS:
		return "is no battery field"
	if not (stored is float or stored is int):
		return "is not a number (%s)" % str(stored)
	if not is_finite(stored):
		return "is not finite (%s)" % str(stored)
	if stored < 0.0 or stored > 1.0:
		return "is outside 0 .. 1 (%s)" % str(stored)
	return ""


## The wear `car_id` was left with:
##   {"clutch": float 0..1, "brakes_front": ..., "brakes_rear": ...,
##    "tyres_front": ..., "tyres_rear": ..., "engine": ...,
##    "problems": what was wrong with the file, one text per field}
## No file, no entry or no "wear" in it is a car that has not been driven:
## WEAR_DEFAULTS (nothing worn), no problems. A field that is there and is no
## share of a life (not a number, not finite, under 0 or over 1) reads as its
## default and puts one text in "problems", naming the car and the field; the
## other five still load. Nothing is reported from here: the car that asked
## says it (push_error), the tests read the texts. The load_battery idiom,
## field by field.
static func load_wear(car_id: String, path := PATH) -> Dictionary:
	var wear := WEAR_DEFAULTS.duplicate()
	var problems: Array[String] = []
	var entry: Variant = _cars(_read(path)).get(car_id)
	var stored_wear: Variant = (entry as Dictionary).get("wear") if entry is Dictionary else null
	if stored_wear is Dictionary:
		for field: String in WEAR_DEFAULTS:
			if not (stored_wear as Dictionary).has(field):
				continue
			var stored: Variant = (stored_wear as Dictionary)[field]
			var problem := wear_problem(field, stored)
			if problem != "":
				problems.append("%s: %s's wear %s %s, %s is used" % [path, car_id, field, problem, str(WEAR_DEFAULTS[field])])
				continue
			wear[field] = float(stored)
	wear["problems"] = problems
	return wear


## What keeps `stored` from being the wear field `field`; "" when it is one.
## All six are shares, 0..1: a finite number, neither under 0 nor over 1.
static func wear_problem(field: String, stored: Variant) -> String:
	if not field in WEAR_DEFAULTS:
		return "is no wear field"
	if not (stored is float or stored is int):
		return "is not a number (%s)" % str(stored)
	if not is_finite(stored):
		return "is not finite (%s)" % str(stored)
	if stored < 0.0 or stored > 1.0:
		return "is outside 0 .. 1 (%s)" % str(stored)
	return ""


## The licence `car_id`'s driver holds:
##   {"level": int LICENCE_LEVEL_MIN .. LICENCE_LEVEL_MAX, "passed": Array[String],
##    "elements": Array[String], "problems": what was wrong with the file, one text per field}
## No file, no entry or no "licence" in it is an unlicensed driver:
## LICENCE_DEFAULTS, no problems. A field that is there and is none of its own
## (a level that is no whole number in range, a passed or elements list that
## is no array of strings) reads as its default and puts one text in
## "problems", naming the car and the field; the other fields still load. A
## field that is not there (an "elements" written before there were any)
## reads as its default, nothing reported. The level returned is what the
## passes and the elements earn, always (the file's level is checked and
## reported, not believed: they are the record). Nothing is reported from
## here: the manager that asked says it
## (push_error), the tests read the texts. The load_wear idiom, field by field.
static func load_licence(car_id: String, path := PATH) -> Dictionary:
	var licence := LICENCE_DEFAULTS.duplicate(true)
	var problems: Array[String] = []
	var entry: Variant = _cars(_read(path)).get(car_id)
	var stored_licence: Variant = (entry as Dictionary).get("licence") if entry is Dictionary else null
	if stored_licence is Dictionary:
		for field: String in LICENCE_DEFAULTS:
			if not (stored_licence as Dictionary).has(field):
				continue
			var stored: Variant = (stored_licence as Dictionary)[field]
			var problem := licence_problem(field, stored)
			if problem != "":
				problems.append("%s: %s's licence %s %s, %s is used" % [path, car_id, field, problem, str(LICENCE_DEFAULTS[field])])
				continue
			licence[field] = _licence_value(field, stored)
	licence["level"] = LicenceExams.level_for(licence["passed"], licence["elements"])
	licence["problems"] = problems
	return licence


## What keeps `stored` from being the licence field `field`; "" when it is one.
## The level is a whole number from LICENCE_LEVEL_MIN to LICENCE_LEVEL_MAX;
## the passes and the elements are arrays of strings (names; unknown names
## are kept, they may be a later build's).
static func licence_problem(field: String, stored: Variant) -> String:
	match field:
		"level":
			if not (stored is float or stored is int):
				return "is not a number (%s)" % str(stored)
			var level := float(stored)
			if not is_finite(level):
				return "is not finite (%s)" % str(stored)
			if level != floorf(level):
				return "is no whole level (%s)" % str(stored)
			if level < LICENCE_LEVEL_MIN or level > LICENCE_LEVEL_MAX:
				return "is outside the levels %d .. %d (%s)" % [LICENCE_LEVEL_MIN, LICENCE_LEVEL_MAX, str(stored)]
			return ""
		"passed", "elements":
			if not stored is Array:
				return "is not a list (%s)" % str(stored)
			for name: Variant in stored:
				if not name is String:
					return "holds something that is no %s name (%s)" % ["exam" if field == "passed" else "element", str(name)]
			return ""
	return "is no licence field"


# A checked `stored` as the licence dictionary holds it: the level a whole int
# (JSON gives every number back as a float), the passes and the elements each
# an Array[String] without duplicates, in the order they came.
static func _licence_value(field: String, stored: Variant) -> Variant:
	match field:
		"level":
			return int(stored)
		"passed", "elements":
			var names: Array[String] = []
			for name: String in stored:
				if not names.has(name):
					names.append(name)
			return names
	return stored


## Writes the licence `fields` (the keys of LICENCE_DEFAULTS; see
## load_licence) into `car_id`'s "licence" object and leaves the rest of the
## file as it is. All three are written every time: what is left out, or is
## no field of its own, goes in as its default, so what is in the file is
## always readable back; the level written is what the passes and the
## elements earn.
static func save_licence(car_id: String, fields: Dictionary, path := PATH) -> void:
	_save_fields(car_id, {"licence": _licence_fields(fields)}, path)


# The three fields of a car's "licence" object as they go into the file.
static func _licence_fields(fields: Dictionary) -> Dictionary:
	var written := {}
	for field: String in LICENCE_DEFAULTS:
		var value: Variant = fields.get(field, LICENCE_DEFAULTS[field])
		if licence_problem(field, value) != "":
			value = LICENCE_DEFAULTS[field]
		written[field] = _licence_value(field, value)
	written["level"] = LicenceExams.level_for(written["passed"], written["elements"])
	return written


## Writes `odometer_m` [m] into `car_id`'s entry and leaves the rest of the file
## as it is. Nothing is written for a number that is not finite.
static func save_odometer(car_id: String, odometer_m: float, path := PATH) -> void:
	_save_fields(car_id, {"odometer_m": odometer_m}, path)


## Writes `odometer_m` [m], `fuel_l` [L] and, when it is handed them, the
## dashboard `driver`, the `battery` and the `wear` into `car_id`'s entry in
## ONE write, and leaves the rest of the file as it is. A number that is not
## finite is not written (the other one is); nothing is written when there is
## nothing to write.
# was (car_id, odometer_m, fuel_l, path) -> `driver` appended, behind `path`:
# the car's cadence save carries the dashboard along with the metres and the
# litres, so a car is one write per save, not three.
# was ... driver) -> `battery` appended behind it, the same way and for the
# same reason: still the one write per save.
# was ... battery) -> `wear` appended behind it, the same way and for the same
# reason: still the one write per save. VERSION stays 1 (see the header): an
# old file has no "wear" and reads as a new car's, and everything else in it
# is written back as it was.
static func save_car(car_id: String, odometer_m: float, fuel_l: float, path := PATH, driver := {}, battery := {}, wear := {}) -> void:
	var fields := {"odometer_m": odometer_m, "fuel_l": fuel_l}
	if not driver.is_empty():
		fields["driver"] = _driver_fields(driver)
	if not battery.is_empty():
		fields["battery"] = _battery_fields(battery)
	if not wear.is_empty():
		fields["wear"] = _wear_fields(wear)
	_save_fields(car_id, fields, path)


## Writes the dashboard `fields` (the keys of DRIVER_DEFAULTS; see load_driver)
## into `car_id`'s "driver" object and leaves the rest of the file as it is.
## All six are written every time: what is left out, or is no setting of its
## own, goes in as its default, so what is in the file is always readable back.
static func save_driver(car_id: String, fields: Dictionary, path := PATH) -> void:
	_save_fields(car_id, {"driver": _driver_fields(fields)}, path)


# The six fields of a car's "driver" object as they go into the file: the
# switches and automatic as bools, the program by name, the view by its index.
static func _driver_fields(fields: Dictionary) -> Dictionary:
	var written := {}
	for field: String in DRIVER_DEFAULTS:
		var value: Variant = fields.get(field, DRIVER_DEFAULTS[field])
		if driver_problem(field, value) != "":
			value = DRIVER_DEFAULTS[field]
		written[field] = _driver_value(field, value)
	return written


# The two fields of a car's "battery" object as they go into the file: both
# written every time, as floats; what is left out, or is no share of a battery
# (NaN among them), goes in as its default, so what is in the file is always
# readable back.
static func _battery_fields(fields: Dictionary) -> Dictionary:
	var written := {}
	for field: String in BATTERY_DEFAULTS:
		var value: Variant = fields.get(field, BATTERY_DEFAULTS[field])
		if battery_problem(field, value) != "":
			value = BATTERY_DEFAULTS[field]
		written[field] = float(value)
	return written


# The six fields of a car's "wear" object as they go into the file: all
# written every time, as floats; what is left out, or is no share of a life
# (NaN among them), goes in as its default, so what is in the file is always
# readable back.
static func _wear_fields(fields: Dictionary) -> Dictionary:
	var written := {}
	for field: String in WEAR_DEFAULTS:
		var value: Variant = fields.get(field, WEAR_DEFAULTS[field])
		if wear_problem(field, value) != "":
			value = WEAR_DEFAULTS[field]
		written[field] = float(value)
	return written


# was save_odometer's own body -> shared with save_car, field by field.
# was every field held against is_finite -> the floats alone: a car's entry now
# carries the "driver" object as well (a dictionary of bools, a name and a view
# number), and is_finite on anything but a number is a runtime error. What it
# protected is untouched: a NaN or an inf odometer or fuel level is not written,
# and a write with nothing left to write does not touch the file.
static func _save_fields(car_id: String, fields: Dictionary, path: String) -> void:
	var writable := {}
	for field: String in fields:
		var value: Variant = fields[field]
		if value is float and not is_finite(value):
			continue
		writable[field] = value
	if writable.is_empty():
		return
	var stored := _read(path)
	var cars := _cars(stored)
	var entry: Variant = cars.get(car_id)
	if not entry is Dictionary:
		entry = {}
	for field: String in writable:
		entry[field] = writable[field]
	cars[car_id] = entry
	stored["version"] = VERSION
	stored["cars"] = cars
	# was FileAccess.open(path, ...) -> the path as DataDir resolves it: a
	# user:// path goes to the data folder in use (its folder made if it is
	# new), any other path is itself.
	var on_disk := DataDir.resolve(path)
	if on_disk != path:
		DirAccess.make_dir_recursive_absolute(on_disk.get_base_dir())
	var file := FileAccess.open(on_disk, FileAccess.WRITE)
	if file == null:
		return
	# Full precision: an odometer is read to the metre after a million of them,
	# and a fuel level or a battery's charge comes back the float it was.
	file.store_string(JSON.stringify(stored, "  ", true, true))
	file.close()


## What the file holds, empty when there is none or it is not a dictionary.
## `path` as DataDir resolves it (see the header).
static func _read(path: String) -> Dictionary:
	var on_disk := DataDir.resolve(path)
	if not FileAccess.file_exists(on_disk):
		return {}
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(on_disk))
	return value if value is Dictionary else {}


static func _cars(stored: Dictionary) -> Dictionary:
	var cars: Variant = stored.get("cars")
	return cars if cars is Dictionary else {}
