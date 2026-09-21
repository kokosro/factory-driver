class_name OdometerStore
extends RefCounted
## Keeps the cars' odometers from one session to the next: one small JSON file
## under user://, an entry per car, e.g.
##   {"version": 1, "cars": {"boxster_986": {"odometer_m": 123.4}}}
## A car's entry is a dictionary so the garage can keep more per car than its
## metres, and a save only ever touches the one field of the one car it is
## handed: whatever else the file holds is written back as it was read.
##
## Behind the telemetry's own switch (TelemetryRecorder.should_record): on in
## the running game, off with no window - the headless test suite reads and
## writes nothing, its cars all start at 0 - unless FD_TELEMETRY=1 asks for it.
## The car does the asking (enabled()); the functions here do as they are told,
## to whatever path, so the tests can try them on a file of their own.

## Where the odometers live, and the version of what is in there.
const PATH := "user://cars.json"
const VERSION := 1


## Whether odometers are loaded and saved at all in this run.
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


## Writes `odometer_m` [m] into `car_id`'s entry and leaves the rest of the file
## as it is. Nothing is written for a number that is not finite.
static func save_odometer(car_id: String, odometer_m: float, path := PATH) -> void:
	if not is_finite(odometer_m):
		return
	var stored := _read(path)
	var cars := _cars(stored)
	var entry: Variant = cars.get(car_id)
	if not entry is Dictionary:
		entry = {}
	entry["odometer_m"] = odometer_m
	cars[car_id] = entry
	stored["version"] = VERSION
	stored["cars"] = cars
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return
	# Full precision: an odometer is read to the metre after a million of them.
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
