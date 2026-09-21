class_name OdometerStore
extends RefCounted
## Keeps what a car has on it from one session to the next - its odometer and
## the fuel in its tank: one small JSON file under user://, an entry per car, e.g.
##   {"version": 1, "cars": {"boxster_986": {"odometer_m": 123.4, "fuel_l": 31.5}}}
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

## Where the cars' entries live, and the version of what is in there.
const PATH := "user://cars.json"
const VERSION := 1


## Whether odometers and fuel levels are loaded and saved at all in this run.
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


## Writes `odometer_m` [m] into `car_id`'s entry and leaves the rest of the file
## as it is. Nothing is written for a number that is not finite.
static func save_odometer(car_id: String, odometer_m: float, path := PATH) -> void:
	_save_fields(car_id, {"odometer_m": odometer_m}, path)


## Writes `odometer_m` [m] and `fuel_l` [L] into `car_id`'s entry in one write
## and leaves the rest of the file as it is. A number that is not finite is not
## written (the other one is); nothing is written when neither is.
static func save_car(car_id: String, odometer_m: float, fuel_l: float, path := PATH) -> void:
	_save_fields(car_id, {"odometer_m": odometer_m, "fuel_l": fuel_l}, path)


# was save_odometer's own body -> shared with save_car, field by field.
static func _save_fields(car_id: String, fields: Dictionary, path: String) -> void:
	var finite := {}
	for field: String in fields:
		if is_finite(fields[field]):
			finite[field] = fields[field]
	if finite.is_empty():
		return
	var stored := _read(path)
	var cars := _cars(stored)
	var entry: Variant = cars.get(car_id)
	if not entry is Dictionary:
		entry = {}
	for field: String in finite:
		entry[field] = finite[field]
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
