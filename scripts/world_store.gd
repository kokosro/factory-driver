class_name WorldStore
extends RefCounted
## The driver's world record: where they dropped the pin, which test centre
## they chose, the vouchers they hold and the rental they are in. One small
## JSON file beside cars.json, user://world.json, e.g.
##   {"version": 1, "driver": {"spawn_region": "eifel_ring", "test_centre": "E8.1",
##     "vouchers": [{"kind": "car", "class": "general", "dealership": "E4.1",
##       "granted_by": "L0", "spent": false}],
##     "rental": {"active": true, "granted_at_s": 0.0, "expires_s": 3600.0},
##     "active_car": ""}}
## The rule (docs/design/4b/first-run-flow.md §2): the licence stays in
## cars.json per car, the driver's world state goes in here. A class of
## static functions like OdometerStore, no autoload: every function takes
## the path it reads or writes (default PATH), a test hands a file of its
## own and never touches the data folder; a user:// path goes through
## DataDir.resolve like every other store's. Tolerant readers: a missing
## file or a missing field is its default; a field that is there and is
## none of its own is reported in "problems" and read as its default, never
## trusted. A save writes back untouched what it does not know (an older or
## a later build's fields round through).
##
## WHO READS IT IN A RUN (active_path): the running game reads and writes
## PATH, behind the same switch as the car's store (OdometerStore.enabled:
## on with a window, off headless); the headless suite reads NOTHING unless
## a test points path_override at a file of its own. So no test ever reads
## the developer's real world.json, and no scene node in the suite opens
## the first-run map on a record it did not write itself.

## Where the record lives, and the version of what is in there.
const PATH := "user://world.json"
const VERSION := 1

## The driver object's fields and what a driver who has never dropped a pin
## has for them: no region, no centre, no vouchers, no rental, no car of
## their own. "active_car" (first-run-flow.md §5: the voucher's car "makes
## it the car in the scene") is the id of the car the driver took at the
## dealership; the car's config swap is deferred (see scripts/first_car.gd),
## the field is what the swap will read.
const DRIVER_DEFAULTS := {
	"spawn_region": "",
	"test_centre": "",
	"vouchers": [],
	"rental": {},
	"active_car": "",
}

## A voucher's fields and their defaults (first-run-flow.md §4): what it is
## for, the class of car, the dealership it is honoured at (a focus-table
## id), what granted it, and whether it has been spent.
const VOUCHER_DEFAULTS := {
	"kind": "car",
	"class": "general",
	"dealership": "",
	"granted_by": "",
	"spent": false,
}

## A rental's fields and their defaults: whether one is on, when it began
## on the car's tick clock [s], and how long it lasts [s] (the driver's
## rule: one hour). An empty object is no rental.
const RENTAL_DEFAULTS := {
	"active": false,
	"granted_at_s": 0.0,
	"expires_s": 3600.0,
}

## A test's file, read and written instead of PATH by everything that asks
## active_path(); "" for none (the game).
static var path_override := ""


## The path the game's nodes read and write this run: path_override where
## a test set one, PATH in the running game (the store's switch on), ""
## headless - read nothing, write nothing.
static func active_path() -> String:
	if path_override != "":
		return path_override
	if OdometerStore.enabled():
		return PATH
	return ""


# =============================================================================
#  The driver object
# =============================================================================

## The driver object as the file at `path` has it: every field of
## DRIVER_DEFAULTS, plus "problems" (one text per field that was there and
## was none of its own; empty when the file is clean or absent).
static func load_driver(path := PATH) -> Dictionary:
	var driver := DRIVER_DEFAULTS.duplicate(true)
	var problems: Array[String] = []
	var stored: Variant = _read(path).get("driver")
	if stored is Dictionary:
		for field: String in DRIVER_DEFAULTS:
			if not (stored as Dictionary).has(field):
				continue
			var value: Variant = (stored as Dictionary)[field]
			var problem := driver_problem(field, value)
			if problem != "":
				problems.append("%s: driver.%s %s, %s is used" % [path, field, problem, str(DRIVER_DEFAULTS[field])])
				continue
			driver[field] = _driver_value(field, value)
	driver["problems"] = problems
	return driver


## What keeps `value` from being the driver field `field`; "" when it is one.
static func driver_problem(field: String, value: Variant) -> String:
	match field:
		"spawn_region", "test_centre", "active_car":
			return "" if value is String else "is not a name (%s)" % str(value)
		"vouchers":
			if not value is Array:
				return "is not a list (%s)" % str(value)
			for i: int in (value as Array).size():
				var problem := voucher_problem((value as Array)[i])
				if problem != "":
					return "[%d] %s" % [i, problem]
			return ""
		"rental":
			if not value is Dictionary:
				return "is not an object (%s)" % str(value)
			return rental_problem(value)
	return "is no driver field"


## What keeps `voucher` from being a voucher; "" when it is one: an object
## with every field of VOUCHER_DEFAULTS of its type (extra fields tolerated).
static func voucher_problem(voucher: Variant) -> String:
	if not voucher is Dictionary:
		return "is not a voucher object (%s)" % str(voucher)
	for field: String in VOUCHER_DEFAULTS:
		if not (voucher as Dictionary).has(field):
			return "has no %s" % field
		var value: Variant = (voucher as Dictionary)[field]
		if field == "spent":
			if not value is bool:
				return "spent is not true or false (%s)" % str(value)
		elif not value is String:
			return "%s is not a name (%s)" % [field, str(value)]
	return ""


## What keeps `rental` from being a rental object; "" when it is one: empty
## (no rental), or every field of RENTAL_DEFAULTS of its type, the seconds
## finite and not negative.
static func rental_problem(rental: Dictionary) -> String:
	if rental.is_empty():
		return ""
	for field: String in RENTAL_DEFAULTS:
		if not rental.has(field):
			return "has no %s" % field
		var value: Variant = rental[field]
		if field == "active":
			if not value is bool:
				return "active is not true or false (%s)" % str(value)
		elif not (value is float or value is int) or not is_finite(value) or value < 0.0:
			return "%s is not a finite number of seconds of zero or more (%s)" % [field, str(value)]
	return ""


# A checked value as the driver dictionary holds it: the vouchers each a
# full voucher object (defaults filled, extras kept), the rental with its
# seconds as floats, the names as they are.
static func _driver_value(field: String, value: Variant) -> Variant:
	match field:
		"vouchers":
			var vouchers: Array = []
			for voucher: Dictionary in value:
				vouchers.append(_voucher_fields(voucher))
			return vouchers
		"rental":
			return _rental_fields(value)
	return value


## Writes the driver `fields` (any of DRIVER_DEFAULTS' keys) into the file
## at `path` and leaves everything else in it - the other driver fields,
## anything above them - exactly as it was. A field that is none of its own
## is not written (the file is never made unreadable from here).
static func save_driver(fields: Dictionary, path := PATH) -> void:
	var stored := _read(path)
	var driver: Variant = stored.get("driver")
	if not driver is Dictionary:
		driver = {}
	var written := 0
	for field: String in fields:
		if not DRIVER_DEFAULTS.has(field) or driver_problem(field, fields[field]) != "":
			continue
		driver[field] = _driver_value(field, fields[field])
		written += 1
	if written == 0:
		return
	stored["version"] = VERSION
	stored["driver"] = driver
	_write(stored, path)


## Whether the file at `path` holds a world record: a pin dropped (a
## spawn_region). A fresh file, or none, is no record: the map opens first.
static func has_record(path := PATH) -> bool:
	return String(load_driver(path).spawn_region) != ""


## Writes the pin's choice: the region and the test centre.
static func set_spawn(region: String, centre: String, path := PATH) -> void:
	save_driver({"spawn_region": region, "test_centre": centre}, path)


## Writes the id of the car the driver took (FirstCar), "" for none.
static func set_active_car(car_id: String, path := PATH) -> void:
	save_driver({"active_car": car_id}, path)


# =============================================================================
#  Vouchers
# =============================================================================

## A voucher as the file holds it: `fields` over VOUCHER_DEFAULTS (a field
## left out is its default; extra fields kept).
static func voucher(fields: Dictionary) -> Dictionary:
	return _voucher_fields(fields)


## Every voucher in the file at `path`, in the order they were granted.
static func vouchers(path := PATH) -> Array:
	return load_driver(path).vouchers


## The vouchers not yet spent, in order.
static func unspent_vouchers(path := PATH) -> Array:
	var found: Array = []
	for entry: Dictionary in vouchers(path):
		if not entry.spent:
			found.append(entry)
	return found


## Appends `record` (a voucher's fields, see VOUCHER_DEFAULTS) to the
## vouchers in the file at `path`. Returns the voucher as written.
static func add_voucher(record: Dictionary, path := PATH) -> Dictionary:
	var written := _voucher_fields(record)
	var held: Array = vouchers(path)
	held.append(written)
	save_driver({"vouchers": held}, path)
	return written


## Marks the first unspent voucher spent and returns it as it now stands
## (spent true); {} when none is unspent, and the file is left alone.
static func spend_voucher(path := PATH) -> Dictionary:
	var held: Array = vouchers(path)
	for entry: Dictionary in held:
		if not entry.spent:
			entry["spent"] = true
			save_driver({"vouchers": held}, path)
			return entry
	return {}


static func _voucher_fields(fields: Dictionary) -> Dictionary:
	var written := fields.duplicate(true)
	for field: String in VOUCHER_DEFAULTS:
		var value: Variant = written.get(field, VOUCHER_DEFAULTS[field])
		if field == "spent":
			written[field] = value if value is bool else VOUCHER_DEFAULTS[field]
		else:
			written[field] = value if value is String else VOUCHER_DEFAULTS[field]
	return written


# =============================================================================
#  The rental
# =============================================================================

## The rental as the file at `path` has it: RENTAL_DEFAULTS' fields, or {}
## for none.
static func rental(path := PATH) -> Dictionary:
	return load_driver(path).rental


## Whether a rental is on.
static func rental_active(path := PATH) -> bool:
	return bool(rental(path).get("active", false))


## Writes a rental: on, begun at `granted_at_s` on the tick clock, lasting
## `expires_s` [s].
static func set_rental(granted_at_s: float, expires_s: float, path := PATH) -> Dictionary:
	var written := _rental_fields({"active": true, "granted_at_s": granted_at_s, "expires_s": expires_s})
	save_driver({"rental": written}, path)
	return written


## Ends the rental: the object is emptied (no rental).
static func clear_rental(path := PATH) -> void:
	save_driver({"rental": {}}, path)


static func _rental_fields(fields: Dictionary) -> Dictionary:
	if fields.is_empty():
		return {}
	var written := fields.duplicate(true)
	for field: String in RENTAL_DEFAULTS:
		var value: Variant = written.get(field, RENTAL_DEFAULTS[field])
		if field == "active":
			written[field] = value if value is bool else RENTAL_DEFAULTS[field]
		else:
			written[field] = float(value) if (value is float or value is int) and is_finite(value) and value >= 0.0 else RENTAL_DEFAULTS[field]
	return written


# =============================================================================
#  The file
# =============================================================================

## What the file holds, empty when there is none or it is not a dictionary.
## `path` as DataDir resolves it (the header).
static func _read(path: String) -> Dictionary:
	var on_disk := DataDir.resolve(path)
	if not FileAccess.file_exists(on_disk):
		return {}
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(on_disk))
	return value if value is Dictionary else {}


static func _write(stored: Dictionary, path: String) -> void:
	var on_disk := DataDir.resolve(path)
	if on_disk != path:
		DirAccess.make_dir_recursive_absolute(on_disk.get_base_dir())
	elif not path.begins_with("user://"):
		DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(on_disk, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify(stored, "  ", true, true))
	file.close()
