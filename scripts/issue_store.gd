class_name IssueStore
extends RefCounted
## Keeps what the driver flagged from behind the wheel: the issues, one record
## each, so they can be read and diagnosed long after the drive ("analyse the
## issues": the store and the telemetry sessions it names, read together).
## One small JSON file under user://, e.g.
##   {"version": 1, "next_issue_id": 3, "issues": [
##     {"id": "issue-0001", "status": "open", "description": "the car snaps sideways over the crest",
##      "started_at": "2026-09-23T10:32:45", "stopped_at": "2026-09-23T10:33:10", "duration_s": 25.0,
##      "binding": "telemetry", "session_id": 7, "t_start_s": 812.5, "t_stop_s": 837.5,
##      "odometer_start_m": 12345.678, "odometer_stop_m": 12960.1,
##      "car_state": {"x": 12.3, "y": 0.4, "z": -150.2, "heading_deg": 91.0, "speed_ms": 24.1,
##        "gear": 3, "odometer_m": 12345.678}}]}
## What a record holds, then: the id (issue-NNNN, the file's own counter,
## never reused), the status (open until somebody closes it), the description
## typed after the drive ("" when none was), the WALL CLOCK at the start and
## the stop (started_at / stopped_at, the telemetry's own idiom: a record is
## found again by when it was driven, nothing is measured against them), the
## DURATION counted in physics ticks [s] (the flagger's own count, the same
## drive the same number), THE TELEMETRY BINDING - binding "telemetry": the
## recorder's own session id (its session_start line's) and the range inside
## that session's .jsonl in the recorder's own clock, t_start_s .. t_stop_s
## [s], the samples' t_session_s; binding "odometer+wallclock": no recorder was
## recording (the Ring has none), session_id 0 and both seconds 0.0, the drive
## identified by the odometer and the wall clock alone -, the ODOMETER at the
## start and the stop [m] (both bindings: an odometer range is a range on any
## map), and the CAR STATE at the start: the telemetry sample's own fields,
## position [m], heading [degrees, left positive], speed along the nose [m/s],
## the gear (0 neutral, 1..5, -1 reverse engaged) and the odometer [m], each
## snapped as a sample is (TelemetryRecorder.VALUE_SNAP).
##
## Behind the telemetry's own switch (TelemetryRecorder.should_record): on in
## the running game, off with no window - the headless test suite reads and
## writes nothing under user:// - unless FD_TELEMETRY=1 asks for it. The
## flagger asks (enabled()); the functions here do as they are told, to
## whatever path, so the tests can try them on a file of their own: the ONE
## path refused while the switch is off is the default one (PATH), read and
## written by nobody then.
## WHERE user:// IS: every read and write goes through DataDir.resolve, so a
## user:// path lands in the data folder chosen for this run (FD_DATA_DIR or
## the garage's SETTINGS page, scripts/data_dir.gd) and any other path is
## itself - a test's file of its own is read and written where it says.
# chosen for the flagging tool: one file beside cars.json and the telemetry
# folder, a list of records with the file's own counter for ids, in
# OdometerStore's style (constants, static functions, a path override on
# every call, per-field problems in words) - the one per-car ledger's idiom
# reused for the one per-driver complaint book.

## Where the issues live, and the version of what is in there.
const PATH := "user://issues.json"
const VERSION := 1

## An id as it is written: "issue-" and the counter, at least four digits.
const ID_PREFIX := "issue-"
const ID_DIGITS := 4

## What a record's status may be: open until it is diagnosed and closed by
## hand (nothing here closes one).
const STATUSES: Array[String] = ["open", "closed"]

## What a record is bound to (see the header): the recorder's session, or
## the odometer and the wall clock with no recorder recording.
const BINDING_TELEMETRY := "telemetry"
const BINDING_ODOMETER := "odometer+wallclock"
const BINDINGS: Array[String] = [BINDING_TELEMETRY, BINDING_ODOMETER]

## What the car state at the start holds - and what a number in the file that
## is none of its own is read as. The telemetry sample's own fields, less the
## pedals and the slips: where the car was and what it was doing.
const CAR_STATE_DEFAULTS := {
	"x": 0.0,
	"y": 0.0,
	"z": 0.0,
	"heading_deg": 0.0,
	"speed_ms": 0.0,
	"gear": 0,
	"odometer_m": 0.0,
}

## A record's fields, less the id, and what a field that is there and is none
## of its own is read as. The id has no default: a record without one is no
## record, and is left out with a word.
const ISSUE_DEFAULTS := {
	"status": "open",
	"description": "",
	"started_at": "",
	"stopped_at": "",
	"duration_s": 0.0,
	"binding": BINDING_ODOMETER,
	"session_id": 0,
	"t_start_s": 0.0,
	"t_stop_s": 0.0,
	"odometer_start_m": 0.0,
	"odometer_stop_m": 0.0,
	"car_state": CAR_STATE_DEFAULTS,
}


## Whether the driver's issues are read and written at all in this run.
static func enabled() -> bool:
	return TelemetryRecorder.should_record()


## Whether `path` may be touched: any path of one's own, and the default one
## only while the switch is on.
static func allowed(path: String) -> bool:
	return path != PATH or enabled()


## The id the next record will get, e.g. "issue-0003": the file's counter
## as load_issues checks it, 1 for no file. Nothing is written by asking.
static func next_id(path := PATH) -> String:
	return format_id(load_issues(path).next_issue_id)


## "issue-0007" for 7.
static func format_id(number: int) -> String:
	return "%s%0*d" % [ID_PREFIX, ID_DIGITS, number]


## The counter behind an id, 7 for "issue-0007"; 0 for anything that is no id.
static func id_number(id: Variant) -> int:
	if not id is String or not (id as String).begins_with(ID_PREFIX):
		return 0
	var digits := (id as String).trim_prefix(ID_PREFIX)
	if digits.length() < ID_DIGITS or not digits.is_valid_int() or digits.begins_with("-") or digits.begins_with("+"):
		return 0
	return maxi(digits.to_int(), 0)


## Everything the file holds, checked:
##   {"issues": the records, each with every field of ISSUE_DEFAULTS and its id,
##    "next_issue_id": the counter the next record gets,
##    "problems": what was wrong with the file, one text per field}
## No file is no issues, counter 1, no problems. A field that is there and is
## none of its own reads as its default and puts one text in "problems",
## naming the record and the field; the other fields still load. A record
## that is no dictionary, or has no usable id, is left out, with a text. A
## counter that is no whole number over every id in the file is brought up
## to one, with a text. Nothing is reported from here: whoever asked says it,
## the tests read the texts. The default path while the switch is off is
## not read: no file, as above.
static func load_issues(path := PATH) -> Dictionary:
	var stored := _read(path)
	var issues: Array[Dictionary] = []
	var problems: Array[String] = []
	var raw: Variant = stored.get("issues", [])
	if not raw is Array:
		problems.append("%s: issues is not a list (%s), none are read" % [path, str(raw)])
		raw = []
	var highest := 0
	for position in (raw as Array).size():
		var record: Variant = (raw as Array)[position]
		if not record is Dictionary:
			problems.append("%s: issue %d is not a record (%s), it is left out" % [path, position, str(record)])
			continue
		var number := id_number((record as Dictionary).get("id"))
		if number == 0:
			problems.append("%s: issue %d has no id (%s), it is left out" % [path, position, str((record as Dictionary).get("id"))])
			continue
		highest = maxi(highest, number)
		issues.append(_checked(record, path, problems))
	var cursor: Variant = stored.get("next_issue_id", highest + 1)
	var counter := highest + 1
	if not (cursor is float or cursor is int) or not is_finite(cursor) or cursor != floorf(cursor) or cursor < highest + 1:
		problems.append("%s: next_issue_id %s is no counter over the %d issue(s) there are, %d is used" % [path, str(cursor), issues.size(), highest + 1])
	else:
		counter = int(cursor)
	return {"issues": issues, "next_issue_id": counter, "problems": problems}


## Writes `issue` into the file as one more record and returns the id it was
## written under; "" when nothing was written. The id is the record's own
## when it is one and the file has no record under it yet, else the file's
## counter's (the flagger shows the counter's before the drive and hands it
## back after: the same id unless another writer got in between); the
## counter moves past it. Every other field goes in checked: what is left
## out, or is none of its own, goes in as its default, so what is in the file
## is always readable back; the rest of the file is written back as it was
## read. The default path while the switch is off is refused: nothing read,
## nothing written.
static func add(issue: Dictionary, path := PATH) -> String:
	if not allowed(path):
		return ""
	var stored := _read(path)
	var loaded := load_issues(path)
	var issues: Array = stored.get("issues", []) if stored.get("issues") is Array else []
	var taken := {}
	for record: Dictionary in loaded.issues:
		taken[record.id] = true
	var number := id_number(issue.get("id"))
	if number == 0 or taken.has(format_id(number)):
		number = loaded.next_issue_id
	var written := _checked(issue, path, [])
	written["id"] = format_id(number)
	issues.append(written)
	stored["version"] = VERSION
	stored["next_issue_id"] = maxi(loaded.next_issue_id, number + 1)
	stored["issues"] = issues
	var on_disk := DataDir.resolve(path)
	if on_disk != path:
		DirAccess.make_dir_recursive_absolute(on_disk.get_base_dir())
	var file := FileAccess.open(on_disk, FileAccess.WRITE)
	if file == null:
		return ""
	# Full precision: an odometer is read to the millimetre it was snapped to.
	file.store_string(JSON.stringify(stored, "  ", true, true))
	file.close()
	return written["id"]


## What keeps `stored` from being the record field `field`; "" when it is one.
## The texts are strings; the status and the binding are from their lists;
## the seconds and the metres are finite numbers, none of them negative; the
## session id is a whole number, none or a session's; the car state is a
## dictionary (its own fields are checked one by one, car_state_problem).
static func issue_problem(field: String, stored: Variant) -> String:
	match field:
		"status":
			if not stored is String:
				return "is not a status (%s)" % str(stored)
			if not STATUSES.has(stored):
				return "is no status (%s), they are %s" % [str(stored), ", ".join(STATUSES)]
			return ""
		"description", "started_at", "stopped_at":
			return "" if stored is String else "is not a text (%s)" % str(stored)
		"binding":
			if not stored is String:
				return "is not a binding (%s)" % str(stored)
			if not BINDINGS.has(stored):
				return "is no binding (%s), they are %s" % [str(stored), ", ".join(BINDINGS)]
			return ""
		"session_id":
			var whole := _whole_problem(stored)
			if whole != "":
				return whole
			return "" if stored >= 0 else "is under 0 (%s)" % str(stored)
		"duration_s", "t_start_s", "t_stop_s", "odometer_start_m", "odometer_stop_m":
			return _non_negative_problem(stored)
		"car_state":
			return "" if stored is Dictionary else "is not the car's state (%s)" % str(stored)
	return "is no issue field"


## What keeps `stored` from being the car-state field `field`; "" when it is
## one. The gear is a whole number; the rest are finite numbers.
static func car_state_problem(field: String, stored: Variant) -> String:
	if not field in CAR_STATE_DEFAULTS:
		return "is no car-state field"
	if field == "gear":
		return _whole_problem(stored)
	if not (stored is float or stored is int):
		return "is not a number (%s)" % str(stored)
	if not is_finite(stored):
		return "is not finite (%s)" % str(stored)
	return ""


# A record as the store holds it: every field of ISSUE_DEFAULTS checked and
# in its own type (JSON gives every number back as a float: the session id
# and the gear go back to whole numbers), the id as it came. A field that is
# none of its own is its default, and one text goes into `problems` (add
# hands an array it drops: a record is written checked, not reported).
static func _checked(record: Dictionary, path: String, problems: Array) -> Dictionary:
	var checked := {"id": record.get("id")}
	var label := str(record.get("id"))
	for field: String in ISSUE_DEFAULTS:
		if not record.has(field):
			checked[field] = ISSUE_DEFAULTS[field].duplicate() if ISSUE_DEFAULTS[field] is Dictionary else ISSUE_DEFAULTS[field]
			continue
		var stored: Variant = record[field]
		var problem := issue_problem(field, stored)
		if problem != "":
			problems.append("%s: issue %s's %s %s, %s is used" % [path, label, field, problem, str(ISSUE_DEFAULTS[field])])
			checked[field] = ISSUE_DEFAULTS[field].duplicate() if ISSUE_DEFAULTS[field] is Dictionary else ISSUE_DEFAULTS[field]
			continue
		match field:
			"car_state":
				checked[field] = _checked_car_state(stored, path, label, problems)
			"session_id":
				checked[field] = int(stored)
			"duration_s", "t_start_s", "t_stop_s", "odometer_start_m", "odometer_stop_m":
				checked[field] = float(stored)
			_:
				checked[field] = stored
	return checked


static func _checked_car_state(state: Dictionary, path: String, label: String, problems: Array) -> Dictionary:
	var checked := CAR_STATE_DEFAULTS.duplicate()
	for field: String in CAR_STATE_DEFAULTS:
		if not state.has(field):
			continue
		var stored: Variant = state[field]
		var problem := car_state_problem(field, stored)
		if problem != "":
			problems.append("%s: issue %s's car_state %s %s, %s is used" % [path, label, field, problem, str(CAR_STATE_DEFAULTS[field])])
			continue
		checked[field] = int(stored) if field == "gear" else float(stored)
	return checked


static func _whole_problem(stored: Variant) -> String:
	if not (stored is float or stored is int):
		return "is not a number (%s)" % str(stored)
	if not is_finite(stored):
		return "is not finite (%s)" % str(stored)
	if stored != floorf(stored):
		return "is no whole number (%s)" % str(stored)
	return ""


static func _non_negative_problem(stored: Variant) -> String:
	if not (stored is float or stored is int):
		return "is not a number (%s)" % str(stored)
	if not is_finite(stored):
		return "is not finite (%s)" % str(stored)
	if stored < 0.0:
		return "is under 0 (%s)" % str(stored)
	return ""


## What the file holds, empty when there is none, it is not a dictionary, or
## it is the default path while the switch is off. `path` as DataDir resolves
## it (see the header).
static func _read(path: String) -> Dictionary:
	if not allowed(path):
		return {}
	var on_disk := DataDir.resolve(path)
	if not FileAccess.file_exists(on_disk):
		return {}
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(on_disk))
	return value if value is Dictionary else {}
