class_name Buildings
extends RefCounted
## The typed buildings of a region (docs/design/4b/element-library.md §5,
## implementation-plan.md §4B-5): the E-table's records as data the game
## can load. Every record is what the library says an economy building is,
## {shell: a B id, privileges: a set, demand: a set, owner: none|driver|npc},
## placed by the region's focus table (data/regions/eifel_ring/focus.json,
## the "put in stone" file of data-pipeline.md §6) from the OSM element it
## comes from: the library element id, the OSM id (node/way + id), the
## position as WGS84 lat/lon the way OSM records it, the privileges the
## record holds, its owner, and for a gas station whether it is the social
## one. Region metres are derived at load through SkeletonLoader's
## projection (the file bakes none: one projection, the pipeline's). A
## record answers can(privilege): whether it holds that privilege; a name
## outside the vocabulary is refused with the reason, never taken as "not
## held". The privilege vocabulary has ONE source of truth,
## ElementCatalogue.PRIVILEGES (the 17 names element-library.md §5 lists,
## put in stone here): this class refers to it and copies nothing, so the
## catalogue's E entries and a region's records can never disagree on what
## a privilege is called.
##
## What is NOT here (4B-8 builds the shells from footprints): no mesh, no
## scene, no node. The placeholder box of the plan's "B-shell placeholder
## meshes (boxes with the canon's recipe)" is carried as data only: a
## record's footprint_m() is its shell's default footprint from the library
## (B6 12 × 8 m, B7 15 × 10 m, B8 20 × 12 m) or (0, 0) where the library
## states none (B9: "B0 without the chimney", and B0 is built from the OSM
## footprint), read from the catalogue's stone parameters, never repeated.
##
## A class of static functions, as ElementCatalogue and SkeletonLoader are,
## and no autoload. validate() is stateless: it takes what JSON.parse_string
## made of a file and returns one line per fault; empty = valid. The
## lookups keep the one piece of state there is: the file read once, on
## the first lookup. Nothing in the car, the pad or a scene reads this yet.

## Where the Ring's focus table is. One region in 4B; a region id chooses
## the folder when there are more (4C).
const PATH := "res://data/regions/eifel_ring/focus.json"
const REGION := "eifel_ring"

## The pinned snapshot and the bbox the region was put in stone on
## (ring-region-decisions.md §1), as SkeletonLoader holds them: a table
## from another snapshot is a documented re-pin, never taken quietly.
const PINNED_OSM_BASE := SkeletonLoader.PINNED_OSM_BASE
const BBOX := SkeletonLoader.BBOX

## The library's owner states: nobody's (a rule-placed shell with no
## operator), the driver's, or an NPC's (element-library.md §5, "owner:
## none|driver|npc").
const OWNERS := ["none", "driver", "npc"]

## What an OSM id names.
const OSM_TYPES := ["node", "way", "relation"]

## The gas stations' social share (element-library.md §5, E2): "10 % also
## sell_tuna + free fuel (SOCIAL)"; social = round(0.1 × n), and the region
## table names WHICH by OSM id (ring-region-decisions.md §4: "chosen
## deterministically (seeded by OSM id)": the table is the seed; the
## Ring's pick is the Conductor's judgment there, DECIDED, REVISITABLE).
const SOCIAL_SHARE := 0.1
const STATION_ELEMENT := "E2"

## The library's shell keys for a placeholder footprint (the B entries'
## stone parameters, configs/elements/B.json).
const FOOTPRINT_W_KEY := "default_footprint_w_m"
const FOOTPRINT_D_KEY := "default_footprint_d_m"

## The schema of the focus table's building records (data-pipeline.md §6
## names the table; this is its E-record shape). "stone" cites the line of
## ring-region-decisions.md §4 the record comes from. "extra_privileges" is
## the file "saying so" when a record holds a privilege beyond its library
## element's (the plan: "no E1 has sell_fuel unless the file says so").
const TOP_KEYS := ["region", "provenance", "social", "records"]
const PROVENANCE_KEYS := ["osm_base", "bbox", "fetch", "decisions"]
const FETCH_KEYS := ["tool", "date", "endpoint", "served_timestamp_osm_base", "folder", "query_file", "query_sha256", "answer_file", "answer_sha256", "answer_bytes", "answer_elements", "attic_sha256", "attic_note", "e11_source"]
const SOCIAL_KEYS := ["share", "n", "arithmetic", "count", "picks", "why"]
const RECORD_REQUIRED_KEYS := ["id", "element", "shell", "osm", "position", "privileges", "demand", "owner", "stone"]
const RECORD_OPTIONAL_KEYS := ["social", "osm_name", "osm_tags", "bounds", "extra_privileges", "note"]
const OSM_KEYS := ["type", "id"]
const POSITION_KEYS := ["lat", "lon"]
const STONE_KEYS := ["doc", "line", "status"]
const SHA_PATTERN := "^[0-9a-f]{64}$"


## One placed building: the E-table's record, typed.
class Record:
	extends RefCounted
	var id: String
	## The library element (E2) and the shell it stands in (B6).
	var element: String
	var shell: String
	## Where it comes from: the OSM element and, when tagged, its name.
	var osm_type: String
	var osm_id: int
	var osm_name: String
	## WGS84 [deg] as OSM records it (a way: the centre of its bounds).
	var lat: float
	var lon: float
	## The privilege set and the demand set: names from the vocabulary.
	var privileges: PackedStringArray
	var demand: PackedStringArray
	var owner: String
	## A gas station's social flag (free fuel, tuna; the cats' place).
	var social: bool
	## Why the record holds more than its library element's privileges;
	## empty where it holds exactly the library's.
	var extra_privileges: String
	## The line of ring-region-decisions.md §4 the record is put in stone by.
	var stone_line: int

	## Whether this record holds `privilege`. A name outside the vocabulary
	## is refused (false), and refusal() says why: the caller can tell a
	## privilege not held from a privilege that does not exist.
	func can(privilege: String) -> bool:
		return refusal(privilege) == ""

	## Empty when the record holds `privilege`; else the reason it does not:
	## the name is outside the vocabulary (named, with the vocabulary), or
	## the record does not hold it (named, with what it holds).
	func refusal(privilege: String) -> String:
		var outside := Buildings.privilege_refusal(privilege)
		if outside != "":
			return outside
		if privilege in privileges:
			return ""
		return "%s does not hold %s (its privileges: %s)" % [id, privilege, ", ".join(privileges) if not privileges.is_empty() else "none"]

	## The record's place in region metres (x east, z south), the
	## pipeline's projection done at load: SkeletonLoader.wgs84_to_local.
	func position() -> Vector2:
		return SkeletonLoader.wgs84_to_local(lat, lon)

	## The placeholder box's footprint [m] (width, depth): the shell's
	## default from the library, (0, 0) where the library states none.
	func footprint_m() -> Vector2:
		return Buildings.shell_footprint(shell)


## The file read once: what JSON.parse_string made of it, and the typed
## records built from it. Only the lookups touch these.
static var _data: Dictionary = {}
static var _records: Array[Record] = []


## What JSON.parse_string makes of the file at `path`: null where it is
## missing or is not JSON. What validate() takes; what the test reads the
## same way.
static func read_file(path: String = PATH) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	return JSON.parse_string(FileAccess.get_file_as_string(path))


## Whether `name` is a privilege of the vocabulary (ElementCatalogue's).
static func is_privilege(name: String) -> bool:
	return name in ElementCatalogue.PRIVILEGES


## Empty when `name` is in the vocabulary; else the refusal, naming it and
## the vocabulary it is not in.
static func privilege_refusal(name: String) -> String:
	if is_privilege(name):
		return ""
	return "%s is not in the privilege vocabulary (the %d names of ElementCatalogue.PRIVILEGES: %s)" % [name if name != "" else "\"\"", ElementCatalogue.PRIVILEGES.size(), ", ".join(ElementCatalogue.PRIVILEGES)]


## The social share as the catalogue states it (E2's stone parameter
## social_share, configs/elements/E.json): the library is the source;
## SOCIAL_SHARE is what the library says and stands in only when the
## catalogue's E2 does not state it.
static func social_share() -> float:
	var parameters: Variant = ElementCatalogue.entry(STATION_ELEMENT).get("stone_parameters", {})
	if parameters is Dictionary and _is_number(parameters.get("social_share")):
		return float(parameters.social_share)
	return SOCIAL_SHARE


## The social station count for `n` stations: round(share × n), the
## library's arithmetic (round(0.1 × 9) = 1 on the Ring).
static func social_count(n: int) -> int:
	return roundi(social_share() * n)


## A shell's default footprint [m] (width, depth) from the library's stone
## parameters; (0, 0) for a shell that states none, or that is no entry.
static func shell_footprint(shell: String) -> Vector2:
	var entry := ElementCatalogue.entry(shell)
	var parameters: Variant = entry.get("stone_parameters", {})
	if not parameters is Dictionary or not _is_number(parameters.get(FOOTPRINT_W_KEY)) or not _is_number(parameters.get(FOOTPRINT_D_KEY)):
		return Vector2.ZERO
	return Vector2(parameters[FOOTPRINT_W_KEY], parameters[FOOTPRINT_D_KEY])


## The typed records of `data` (what read_file() returns), in file order;
## whatever is not a record with a String id is skipped (validate()
## reports those). Nothing is checked here beyond the shape: a record of
## an invalid file types the same way, so validate() can name it.
static func records_of(data: Variant) -> Array[Record]:
	var found: Array[Record] = []
	if not data is Dictionary or not data.get("records") is Array:
		return found
	for raw: Variant in data.records:
		if not raw is Dictionary or not raw.get("id") is String:
			continue
		var record := Record.new()
		record.id = raw.id
		record.element = str(raw.get("element", ""))
		record.shell = str(raw.get("shell", ""))
		var osm: Variant = raw.get("osm", {})
		if osm is Dictionary:
			record.osm_type = str(osm.get("type", ""))
			record.osm_id = int(osm.get("id", 0)) if _is_number(osm.get("id")) else 0
		record.osm_name = str(raw.get("osm_name", ""))
		var position: Variant = raw.get("position", {})
		if position is Dictionary:
			record.lat = float(position.get("lat", 0.0)) if _is_number(position.get("lat")) else 0.0
			record.lon = float(position.get("lon", 0.0)) if _is_number(position.get("lon")) else 0.0
		record.privileges = _names_of(raw.get("privileges"))
		record.demand = _names_of(raw.get("demand"))
		record.owner = str(raw.get("owner", ""))
		record.social = raw.get("social") == true
		record.extra_privileges = str(raw.get("extra_privileges", ""))
		var stone: Variant = raw.get("stone", {})
		record.stone_line = int(stone.get("line", 0)) if stone is Dictionary and _is_number(stone.get("line")) else 0
		found.append(record)
	return found


## Every record of the loaded file, in file order.
static func records() -> Array[Record]:
	if _records.is_empty():
		_records = records_of(_file())
	return _records


## The record with this id, or null.
static func record(id: String) -> Record:
	for found: Record in records():
		if found.id == id:
			return found
	return null


## Every record of one library element (E2), in file order.
static func by_element(element: String) -> Array[Record]:
	var found: Array[Record] = []
	for candidate: Record in records():
		if candidate.element == element:
			found.append(candidate)
	return found


## The region's gas stations (E2), in file order.
static func stations() -> Array[Record]:
	return by_element(STATION_ELEMENT)


## The social stations: the ones the table flags. Deterministic: the same
## file, the same ids, every run; validate() holds their count to
## social_count(the stations' count) and their ids to the header's picks.
static func social_stations() -> Array[Record]:
	var found: Array[Record] = []
	for station: Record in stations():
		if station.social:
			found.append(station)
	return found


## The provenance block of the loaded file.
static func provenance() -> Dictionary:
	return _file().get("provenance", {})


## The social block of the loaded file.
static func social() -> Dictionary:
	return _file().get("social", {})


## Everything that is wrong with `data` (what read_file() returns), one
## line each; empty if it is a valid focus table of the pinned snapshot.
## The schema first, the provenance and the social block, then every
## record on its own (its element an E entry, its shell the element's B
## entry, its OSM id, its position inside the bbox, its privileges and
## demand from the vocabulary with the element's own privileges held and
## anything beyond them said so, its owner, its social flag on a station
## only), then across the records: ids unique, no element placed twice
## from one OSM id, the social stations exactly the arithmetic's count and
## the header's picks.
static func validate(data: Variant) -> PackedStringArray:
	var errors := PackedStringArray()
	if not data is Dictionary:
		errors.append("not a JSON object (a file that is not there, or not JSON)")
		return errors
	for key: String in TOP_KEYS:
		if not data.has(key):
			errors.append("%s is missing" % key)
	for key: String in data:
		if not key in TOP_KEYS:
			errors.append("%s is not in the schema" % key)
	if data.has("region") and not _is_text(data.region):
		errors.append("region is %s, not a region id" % [data.region])
	_check_provenance(errors, data.get("provenance"))
	var records_raw: Variant = data.get("records")
	if not records_raw is Array or records_raw.is_empty():
		errors.append("records is missing or holds no record")
		return errors
	var seen := {}
	var placed := {}
	var stations_count := 0
	var flagged: Array[int] = []
	for i: int in records_raw.size():
		var raw: Variant = records_raw[i]
		if not raw is Dictionary or not raw.get("id") is String or raw.id == "":
			errors.append("records[%d] is not a record with an id" % i)
			continue
		var id: String = raw.id
		if seen.has(id):
			errors.append("record %s is there twice, ids are unique" % id)
		seen[id] = true
		_check_record(errors, raw)
		var osm: Variant = raw.get("osm")
		if raw.get("element") is String and osm is Dictionary and osm.get("type") is String and _is_whole(osm.get("id")):
			var key := "%s@%s/%d" % [raw.element, osm.type, int(osm.id)]
			if placed.has(key):
				errors.append("record %s places %s at %s/%d, which %s already does" % [id, raw.element, osm.type, int(osm.id), placed[key]])
			placed[key] = id
		if raw.get("element") == STATION_ELEMENT:
			stations_count += 1
			if raw.get("social") == true and osm is Dictionary and _is_whole(osm.get("id")):
				flagged.append(int(osm.id))
	_check_social(errors, data.get("social"), stations_count, flagged)
	return errors


## The provenance block: the pinned snapshot, the Ring's bbox, a fetch
## record with sha256 fields of the form, the decisions' citation.
static func _check_provenance(errors: PackedStringArray, provenance: Variant) -> void:
	if not provenance is Dictionary:
		errors.append("provenance is not an object")
		return
	for key: String in PROVENANCE_KEYS:
		if not provenance.has(key):
			errors.append("provenance.%s is missing" % key)
	for key: String in provenance:
		if not key in PROVENANCE_KEYS:
			errors.append("provenance.%s is not in the schema" % key)
	if provenance.has("osm_base") and provenance.osm_base != PINNED_OSM_BASE:
		errors.append("provenance.osm_base is %s, the pinned snapshot is %s (a re-pin is a documented decision)" % [provenance.osm_base, PINNED_OSM_BASE])
	if provenance.has("bbox") and not _same_numbers(provenance.bbox, BBOX):
		errors.append("provenance.bbox is %s, the Ring's is %s" % [provenance.bbox, BBOX])
	var fetch: Variant = provenance.get("fetch")
	if provenance.has("fetch"):
		if not fetch is Dictionary:
			errors.append("provenance.fetch is not an object")
		else:
			for key: String in FETCH_KEYS:
				if not fetch.has(key):
					errors.append("provenance.fetch.%s is missing" % key)
			for key: String in fetch:
				if not key in FETCH_KEYS:
					errors.append("provenance.fetch.%s is not in the schema" % key)
			for key: String in ["query_sha256", "answer_sha256", "attic_sha256"]:
				if fetch.has(key) and not _is_sha(fetch[key]):
					errors.append("provenance.fetch.%s is %s, not a sha256 hex" % [key, fetch[key]])
			for key: String in ["tool", "date", "endpoint", "served_timestamp_osm_base", "folder", "query_file", "answer_file", "attic_note"]:
				if fetch.has(key) and not _is_text(fetch[key]):
					errors.append("provenance.fetch.%s is %s, not a text" % [key, fetch[key]])
			for key: String in ["answer_bytes", "answer_elements"]:
				if fetch.has(key) and not (_is_whole(fetch[key]) and fetch[key] > 0):
					errors.append("provenance.fetch.%s is %s, not a count" % [key, fetch[key]])
			if fetch.has("e11_source") and not fetch.e11_source is Dictionary:
				errors.append("provenance.fetch.e11_source is %s, not an object" % [fetch.e11_source])
	var decisions: Variant = provenance.get("decisions")
	if provenance.has("decisions"):
		if not decisions is Dictionary or not _is_text(decisions.get("doc")) or not decisions.get("lines") is Dictionary:
			errors.append("provenance.decisions has no doc and lines")
		else:
			for name: String in decisions.lines:
				if not (_is_whole(decisions.lines[name]) and decisions.lines[name] > 0):
					errors.append("provenance.decisions.lines.%s is %s, not a line number" % [name, decisions.lines[name]])


## The social block against the records: the share the library's, n the
## stations' count, count = round(share × n), the picks the flagged
## stations' OSM ids (and as many as the count).
static func _check_social(errors: PackedStringArray, social: Variant, stations_count: int, flagged: Array[int]) -> void:
	if not social is Dictionary:
		errors.append("social is not an object")
		return
	for key: String in SOCIAL_KEYS:
		if not social.has(key):
			errors.append("social.%s is missing" % key)
	for key: String in social:
		if not key in SOCIAL_KEYS:
			errors.append("social.%s is not in the schema" % key)
	if social.has("share") and social.share != social_share():
		errors.append("social.share is %s, the library's is %s" % [social.share, social_share()])
	if social.has("n") and social.n != stations_count:
		errors.append("social.n is %s, the file holds %d %s records" % [social.n, stations_count, STATION_ELEMENT])
	var expected := social_count(stations_count)
	if social.has("count") and social.count != expected:
		errors.append("social.count is %s, round(%s × %d) is %d" % [social.count, social_share(), stations_count, expected])
	if flagged.size() != expected:
		errors.append("%d station(s) flagged social, round(%s × %d) is %d" % [flagged.size(), social_share(), stations_count, expected])
	if social.has("picks"):
		var picks: Variant = social.picks
		if not picks is Array:
			errors.append("social.picks is not a list")
		else:
			var named: Array[int] = []
			for pick: Variant in picks:
				if not _is_whole(pick):
					errors.append("social.picks holds %s, not an OSM id" % [pick])
				else:
					named.append(int(pick))
			named.sort()
			var flagged_sorted := flagged.duplicate()
			flagged_sorted.sort()
			if named != flagged_sorted:
				errors.append("social.picks is %s, the flagged stations are %s" % [picks, flagged])
	if social.has("arithmetic") and not _is_text(social.arithmetic):
		errors.append("social.arithmetic is %s, not a text" % [social.arithmetic])
	if social.has("why") and not _is_text(social.why):
		errors.append("social.why is empty: the pick is a decision, it says why")


## One record's own faults.
static func _check_record(errors: PackedStringArray, raw: Dictionary) -> void:
	var id: String = raw.id
	for key: String in RECORD_REQUIRED_KEYS:
		if not raw.has(key):
			errors.append("record %s.%s is missing" % [id, key])
	for key: String in raw:
		if not key in RECORD_REQUIRED_KEYS and not key in RECORD_OPTIONAL_KEYS:
			errors.append("record %s.%s is not in the schema" % [id, key])
	var element: Variant = raw.get("element")
	var entry := {}
	if raw.has("element"):
		if not element is String or not ElementCatalogue.is_id(element) or not element.begins_with("E"):
			errors.append("record %s.element is %s, not an E id" % [id, element])
		else:
			entry = ElementCatalogue.entry(element)
			if entry.is_empty():
				errors.append("record %s.element is %s, no such entry in the catalogue" % [id, element])
	var shell: Variant = raw.get("shell")
	if raw.has("shell"):
		if not shell is String or not ElementCatalogue.is_id(shell) or not shell.begins_with("B"):
			errors.append("record %s.shell is %s, not a B id" % [id, shell])
		elif ElementCatalogue.entry(shell).is_empty():
			errors.append("record %s.shell is %s, no such B entry in the catalogue" % [id, shell])
		elif not entry.is_empty() and entry.get("shell") != ElementCatalogue.ANY_SHELL and entry.get("shell") != shell:
			errors.append("record %s.shell is %s, %s's shell is %s" % [id, shell, element, entry.get("shell")])
	var osm: Variant = raw.get("osm")
	if raw.has("osm"):
		if not osm is Dictionary or not osm.get("type") in OSM_TYPES or not (_is_whole(osm.get("id")) and osm.id > 0):
			errors.append("record %s.osm is %s, not {type: node|way|relation, id: a positive whole number}" % [id, osm])
		else:
			for key: String in osm:
				if not key in OSM_KEYS:
					errors.append("record %s.osm.%s is not in the schema" % [id, key])
	var position: Variant = raw.get("position")
	if raw.has("position"):
		if not position is Dictionary or not _is_number(position.get("lat")) or not _is_number(position.get("lon")):
			errors.append("record %s.position is %s, not {lat, lon} in degrees" % [id, position])
		else:
			for key: String in position:
				if not key in POSITION_KEYS:
					errors.append("record %s.position.%s is not in the schema" % [id, key])
			if position.lat < BBOX[0] or position.lat > BBOX[2] or position.lon < BBOX[1] or position.lon > BBOX[3]:
				errors.append("record %s.position (%s, %s) is outside the Ring bbox %s" % [id, position.lat, position.lon, BBOX])
	if raw.has("privileges"):
		_check_names(errors, id, "privileges", raw.privileges)
		if raw.privileges is Array and not entry.is_empty() and entry.get("privileges") is Array:
			var missing := []
			for own: Variant in entry.privileges:
				if not own in raw.privileges:
					missing.append(own)
			if not missing.is_empty():
				errors.append("record %s.privileges lacks %s, which every %s holds" % [id, ", ".join(missing), element])
			var extra := []
			for held: Variant in raw.privileges:
				if not held in entry.privileges:
					extra.append(held)
			if not extra.is_empty() and not _is_text(raw.get("extra_privileges")):
				errors.append("record %s.privileges holds %s beyond %s's, and the file does not say so (extra_privileges)" % [id, ", ".join(extra), element])
	if raw.has("demand"):
		_check_names(errors, id, "demand", raw.demand)
	if raw.has("owner") and not raw.owner in OWNERS:
		errors.append("record %s.owner is %s, not one of %s" % [id, raw.owner, ", ".join(OWNERS)])
	if raw.has("social"):
		if not raw.social is bool:
			errors.append("record %s.social is %s, not true or false" % [id, raw.social])
		elif raw.social and element != STATION_ELEMENT:
			errors.append("record %s is social, only a gas station (%s) is" % [id, STATION_ELEMENT])
	if raw.has("extra_privileges") and not _is_text(raw.extra_privileges):
		errors.append("record %s.extra_privileges is empty" % id)
	for key: String in ["osm_name", "note"]:
		if raw.has(key) and not raw[key] is String:
			errors.append("record %s.%s is not a string" % [id, key])
	if raw.has("osm_tags") and not raw.osm_tags is Dictionary:
		errors.append("record %s.osm_tags is not an object" % id)
	if raw.has("bounds") and not (raw.bounds is Dictionary and _is_number(raw.bounds.get("minlat")) and _is_number(raw.bounds.get("minlon")) and _is_number(raw.bounds.get("maxlat")) and _is_number(raw.bounds.get("maxlon"))):
		errors.append("record %s.bounds is %s, not {minlat, minlon, maxlat, maxlon}" % [id, raw.bounds])
	var stone: Variant = raw.get("stone")
	if raw.has("stone"):
		if not stone is Dictionary or not _is_text(stone.get("doc")) or not (_is_whole(stone.get("line")) and stone.line > 0) or not _is_text(stone.get("status")):
			errors.append("record %s.stone is %s, not {doc, line, status}: every record cites the decision it comes from" % [id, stone])
		else:
			for key: String in stone:
				if not key in STONE_KEYS:
					errors.append("record %s.stone.%s is not in the schema" % [id, key])


## A set of privilege names: a list, each in the vocabulary, none twice.
static func _check_names(errors: PackedStringArray, id: String, field: String, names: Variant) -> void:
	if not names is Array:
		errors.append("record %s.%s is not a list" % [id, field])
		return
	for i: int in names.size():
		var name: Variant = names[i]
		if not name is String or not is_privilege(name):
			errors.append("record %s.%s has %s: %s" % [id, field, name, privilege_refusal(str(name))])
		elif names.find(name) != i:
			errors.append("record %s.%s has %s twice" % [id, field, name])


## The focus table's file, parsed once; empty when it is not there or not
## JSON.
static func _file() -> Dictionary:
	if _data.is_empty():
		var parsed: Variant = read_file()
		if parsed is Dictionary:
			_data = parsed
	return _data


## The strings of a list, as a set of names; anything else is left out
## (validate() names it).
static func _names_of(value: Variant) -> PackedStringArray:
	var names := PackedStringArray()
	if value is Array:
		for name: Variant in value:
			if name is String:
				names.append(name)
	return names


static func _is_number(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(value)


static func _is_whole(value: Variant) -> bool:
	return _is_number(value) and value == floorf(value)


static func _is_text(value: Variant) -> bool:
	return value is String and value != ""


static func _is_sha(value: Variant) -> bool:
	return value is String and RegEx.create_from_string(SHA_PATTERN).search(value) != null


## Whether two lists hold the same numbers in the same order.
static func _same_numbers(a: Variant, b: Array) -> bool:
	if not a is Array or a.size() != b.size():
		return false
	for i: int in b.size():
		if not _is_number(a[i]) or a[i] != b[i]:
			return false
	return true
