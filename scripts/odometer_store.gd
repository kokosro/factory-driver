class_name OdometerStore
extends RefCounted
## Keeps what a car has on it from one session to the next: its odometer, the
## fuel in its tank and the dashboard it was left with - the aid switches, the
## gearbox program, automatic or manual, and the view the driver was looking
## through. One small JSON file under user://, an entry per car, e.g.
##   {"version": 1, "cars": {"boxster_986": {"odometer_m": 123.4, "fuel_l": 31.5,
##     "driver": {"tcs_on": true, "abs_on": true, "sc_on": true,
##       "gearbox_mode": "sport", "automatic": true, "camera_view": 1}}}}
## What a car's entry holds, then: odometer_m [m], fuel_l [L] and driver (the
## six settings below). Not kept yet: where the car was parked and what it has
## worn out.
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
# was the odometers alone -> the fuel level beside them (fuel_l): it is the
# user's car, and a tank driven half empty one day is half empty the next.
# was odometer and fuel -> the dashboard with them (driver): the switches, the
# program and the view belong to the CAR, not to the session - somebody else
# may have driven it in between, and it is handed over as they left it.

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


## Writes `odometer_m` [m] into `car_id`'s entry and leaves the rest of the file
## as it is. Nothing is written for a number that is not finite.
static func save_odometer(car_id: String, odometer_m: float, path := PATH) -> void:
	_save_fields(car_id, {"odometer_m": odometer_m}, path)


## Writes `odometer_m` [m], `fuel_l` [L] and, when it is handed one, the
## dashboard `driver` into `car_id`'s entry in ONE write, and leaves the rest of
## the file as it is. A number that is not finite is not written (the other one
## is); nothing is written when there is nothing to write.
# was (car_id, odometer_m, fuel_l, path) -> `driver` appended, behind `path`:
# the car's cadence save carries the dashboard along with the metres and the
# litres, so a car is one write per save, not three.
static func save_car(car_id: String, odometer_m: float, fuel_l: float, path := PATH, driver := {}) -> void:
	var fields := {"odometer_m": odometer_m, "fuel_l": fuel_l}
	if not driver.is_empty():
		fields["driver"] = _driver_fields(driver)
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
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return
	# Full precision: an odometer is read to the metre after a million of them,
	# and a fuel level comes back the float it was.
	file.store_string(JSON.stringify(stored, "  ", true, true))
	file.close()


## What the file holds, empty when there is none or it is not a dictionary.
static func _read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return value if value is Dictionary else {}


static func _cars(stored: Dictionary) -> Dictionary:
	var cars: Variant = stored.get("cars")
	return cars if cars is Dictionary else {}
