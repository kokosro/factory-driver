class_name ElementCatalogue
extends RefCounted
## The 4B element library (docs/design/4b/element-library.md) as data: the
## seven files under configs/elements/, one per family, read, looked up and
## checked here. An entry is what the library says of an element and nothing
## else: its id, family, title, priority, the canon line it cites, the OSM/DEM
## data that instantiates it, what is put in stone, what a region's focus table
## may vary (each parameter with a range or a list of choices and its default),
## and its texture budget. The economy buildings (E) carry their shell, their
## privileges and their rarity rule as well. Nothing here touches the game: no
## mesh, no scene, no physics reads the catalogue yet (4B-5 and later do; the
## implementation plan, §4B-1). It loads, it answers entry(id) and
## by_family(letter), and validate() says what is wrong with the files.
##
## A class of static functions, as CarConfigValidation is, and no autoload: a
## global class name resolves wherever a script is compiled, the headless
## tests' --script SceneTrees included. validate() is stateless: it takes what
## JSON.parse_string made of the files, keyed by file name, and returns what is
## wrong as a PackedStringArray, one line per fault naming the file, the entry
## and the field; empty = valid. It reports and nothing else. The lookups keep
## the one piece of state there is: the files read once, on the first lookup,
## into _entries (res:// files do not change under a running game).

## Where the seven files are, and the families in the canon's priority order
## (art-direction.md, "Blender → Godot asset rule"): R road, T terrain, S
## sky/light, B building, E economy building, V vegetation, F furniture. A
## family's file is its letter + ".json".
const DIR := "res://configs/elements"
const FAMILIES := ["R", "T", "S", "B", "E", "V", "F"]

## Each family's asset priority (the canon's 1-9: 1 road shape, 2 landscape
## silhouette, 3 the car (not in the library), 4 lighting/atmosphere, 5
## landmarks and typed buildings, 6 vegetation masses, 7 road furniture, 8
## texture, 9 props). Every entry states its own and it has to be its family's.
const FAMILY_PRIORITY := {"R": 1, "T": 2, "S": 4, "B": 5, "E": 5, "V": 6, "F": 7}
const PRIORITY_MIN := 1
const PRIORITY_MAX := 9

## An id is its family's letter and a number with no leading zero (B0 is one):
## "R1", "B10", "E14". The region tables refer to them, so they are stable.
const ID_PATTERN := "^[RTSBEVF](0|[1-9][0-9]*)$"

## The canon's texture budgets, in pixels on a side, [smallest, largest]:
## "important building: 512–1024 / road: repeating 512/1024 / terrain: 512/1024
## tiled / props: 128–512 / vegetation: 128–512". The economy buildings draw
## their shell's. The sky plates have no line in the budget: empty = unchecked.
const TEXTURE_BUDGET_PX := {
	"R": [512, 1024],
	"T": [512, 1024],
	"S": [],
	"B": [512, 1024],
	"E": [512, 1024],
	"V": [128, 512],
	"F": [128, 512],
}

## The privilege vocabulary of the E-table (element-library.md §5; proposed
## there, to be put in stone in 4B-5): the only names an E entry's privileges
## may hold.
const PRIVILEGES := [
	"sell_fuel", "sell_tuna", "buy_cars", "sell_cars", "build_cars", "build_components", "repair", "tyres",
	"salvage", "exam", "ring_booking", "telemetry_desk", "adopt_cat", "rescue_cat", "teleport", "store_bulk_fuel",
	"rent_car",
]

## E14's shell: the abstract building takes any shell the region table names.
## Every other E entry's shell is a B id that is in the catalogue.
const ANY_SHELL := "any"

## The R-family's surface classes (element-library.md §1, "Surface classes"):
## the texture per OSM surface=* value and the friction class the world
## profile will carry. Physics is deferred: nothing reads friction_class yet,
## 1.0 is the pad's, and gravel's null means "to be measured before use; never
## assumed", as the library says.
const SURFACE_CLASSES := {
	"asphalt": {"texture": "road_asphalt_1024", "friction_class": 1.0, "note": "the default; the pad's"},
	"concrete": {"texture": "road_concrete_1024", "friction_class": 1.0, "note": "slab seams baked"},
	"asphalt;concrete": {"texture": "split strip: asphalt inner 1 m, concrete bank", "friction_class": 1.0, "note": "the Karussell (R9)"},
	"gravel": {"texture": "road_gravel_512", "friction_class": null, "note": "to be measured before use; never assumed"},
	"compacted": {"texture": "road_gravel_512", "friction_class": null, "note": "to be measured before use; never assumed"},
	"paving_stones": {"texture": "road_cobble_512", "friction_class": 1.0, "note": "villages; 1.00 in 4B (visual only)"},
	"cobblestone": {"texture": "road_cobble_512", "friction_class": 1.0, "note": "villages; 1.00 in 4B (visual only)"},
}

## What every entry is made of: the library's five fields as data. "stone" is
## the library's line; "stone_parameters" the numbers and names it states
## (a finite number, a name, or a [min, max] pair; nothing the library does not
## say); "varies" the region-table parameters, each {"range": [min, max],
## "default": x} or {"choices": [...], "default": y}, with an optional "note";
## "texture" {"look": the 2000-look line, "size_px": a size or a [min, max]
## pair when the line states one}. "notes" is optional: the library's asides
## (live counts, deferrals, rarity rules) as strings, never as logic.
const REQUIRED_KEYS := ["id", "family", "title", "priority", "canon", "data", "stone", "stone_parameters", "varies", "texture"]
const OPTIONAL_KEYS := ["notes"]
## What an E entry carries on top: its B shell, its privileges, its rarity rule.
const ECONOMY_KEYS := ["shell", "privileges", "rarity"]
## What a varying parameter is made of: its default and its range or choices.
const PARAMETER_KEYS := ["range", "choices", "default", "note"]
const TEXTURE_KEYS := ["look", "size_px"]

## The files read once, on the first lookup: id -> entry, in family order then
## file order. Only the lookups touch it; validate() takes its files as given.
static var _entries: Dictionary = {}


## The seven files as JSON.parse_string makes of them, keyed by file name
## ("R.json"): null where a file is missing or is not JSON. What validate() and
## the lookups read; what the test reads the same way.
static func read_files() -> Dictionary:
	var files := {}
	for family: String in FAMILIES:
		var file := file_of(family)
		files[file] = JSON.parse_string(FileAccess.get_file_as_string(DIR.path_join(file)))
	return files


## A family's file name: its letter + ".json".
static func file_of(family: String) -> String:
	return family + ".json"


## Whether `id` is of the documented form: a family letter and a number.
static func is_id(id: String) -> bool:
	return RegEx.create_from_string(ID_PATTERN).search(id) != null


## Every entry in `files` (as read_files() returns them) that is an object, in
## family order then file order; whatever is not (a file that did not parse, an
## element that is not an object) is skipped: validate() reports those.
static func entries_of(files: Dictionary) -> Array:
	var found := []
	for family: String in FAMILIES:
		var parsed: Variant = files.get(file_of(family))
		if not parsed is Dictionary or not parsed.get("elements") is Array:
			continue
		for element: Variant in parsed.elements:
			if element is Dictionary:
				found.append(element)
	return found


## The entry with this id, or an empty Dictionary if the catalogue has none.
static func entry(id: String) -> Dictionary:
	return _catalogue().get(id, {})


## Every entry of a family (its letter), in file order; empty for a letter
## that is no family.
static func by_family(family: String) -> Array:
	var found := []
	for element: Dictionary in _catalogue().values():
		if element.get("family") == family:
			found.append(element)
	return found


## The catalogue by id, read on the first call. An entry without a String id
## has no place in it (validate() names it).
static func _catalogue() -> Dictionary:
	if _entries.is_empty():
		for element: Dictionary in entries_of(read_files()):
			if element.get("id") is String:
				_entries[element.id] = element
	return _entries


## Everything that is wrong with `files` (file name -> what JSON.parse_string
## made of it, as read_files() returns them), one line each, the file name in
## front and then the entry and the field; empty if it is a valid catalogue.
## Checks each file on its own (structure, ids, fields, priorities, varying
## parameters, texture budgets, the E-table's privileges), then across the
## files: every id unique, every E shell a B entry that is there.
static func validate(files: Dictionary) -> PackedStringArray:
	var errors := PackedStringArray()
	var seen := {}
	var shells := []
	for file: String in files:
		var family := file.get_basename()
		var parsed: Variant = files[file]
		if not parsed is Dictionary:
			errors.append("%s: not a JSON object (a file that is not there, or not JSON)" % file)
			continue
		if not family in FAMILIES:
			errors.append("%s: not a family's file, the families are %s" % [file, ", ".join(FAMILIES)])
			continue
		if parsed.get("family") != family:
			errors.append("%s: family is %s, the file is %s's" % [file, parsed.get("family"), family])
		for key: String in parsed:
			if key != "family" and key != "elements":
				errors.append("%s: %s is not in the schema" % [file, key])
		if not parsed.get("elements") is Array or parsed.elements.is_empty():
			errors.append("%s: elements is missing or holds no entry" % file)
			continue
		for i: int in parsed.elements.size():
			var element: Variant = parsed.elements[i]
			if not element is Dictionary or not element.get("id") is String or element.id == "":
				errors.append("%s: elements[%d] is not an entry with an id" % [file, i])
				continue
			var id: String = element.id
			if seen.has(id):
				errors.append("%s: %s is already in %s, ids are unique" % [file, id, seen[id]])
			seen[id] = file
			_check_entry(errors, file, family, element)
			if family == "E" and element.get("shell") is String and element.shell != ANY_SHELL:
				shells.append([id, element.shell])
	for shell: Array in shells:
		if not seen.has(shell[1]) or not seen[shell[1]].begins_with("B"):
			errors.append("%s: %s.shell is %s, no such B entry" % [file_of("E"), shell[0], shell[1]])
	return errors


## One entry's own faults: its id's form and family, its keys, its fields.
static func _check_entry(errors: PackedStringArray, file: String, family: String, element: Dictionary) -> void:
	var id: String = element.id
	if not is_id(id):
		errors.append("%s: %s is not an id of the form family letter + digits" % [file, id])
	elif id[0] != family:
		errors.append("%s: %s.id names family %s, the file is %s's" % [file, id, id[0], family])
	if element.get("family") != family:
		errors.append("%s: %s.family is %s, the file is %s's" % [file, id, element.get("family"), family])
	var known: Array = REQUIRED_KEYS + OPTIONAL_KEYS + (ECONOMY_KEYS if family == "E" else [])
	for key: String in REQUIRED_KEYS + (ECONOMY_KEYS if family == "E" else []):
		if not element.has(key):
			errors.append("%s: %s.%s is missing" % [file, id, key])
	for key: String in element:
		if not key in known:
			errors.append("%s: %s.%s is not in the schema" % [file, id, key])
	for key: String in ["title", "canon", "data", "stone"]:
		if element.has(key) and not _is_text(element[key]):
			errors.append("%s: %s.%s is empty, every entry %s" % [file, id, key, "cites a canon line" if key == "canon" else "states it"])
	if element.has("priority"):
		var priority: Variant = element.priority
		if not _is_number(priority) or priority != floorf(priority) or priority < PRIORITY_MIN or priority > PRIORITY_MAX:
			errors.append("%s: %s.priority is %s, priorities are %d-%d" % [file, id, priority, PRIORITY_MIN, PRIORITY_MAX])
		elif priority != FAMILY_PRIORITY[family]:
			errors.append("%s: %s.priority is %s, family %s's is %d" % [file, id, priority, family, FAMILY_PRIORITY[family]])
	if element.has("stone_parameters"):
		_check_stone_parameters(errors, file, id, element.stone_parameters)
	if element.has("varies"):
		_check_varies(errors, file, id, element.varies)
	if element.has("texture"):
		_check_texture(errors, file, id, family, element.texture)
	if element.has("notes") and not _is_text_list(element.notes):
		errors.append("%s: %s.notes is not a list of strings" % [file, id])
	if family == "E":
		_check_economy(errors, file, id, element)


## The stone parameters: each a finite number, a name, or a [min, max] pair.
static func _check_stone_parameters(errors: PackedStringArray, file: String, id: String, parameters: Variant) -> void:
	if not parameters is Dictionary:
		errors.append("%s: %s.stone_parameters is not an object" % [file, id])
		return
	for name: String in parameters:
		var value: Variant = parameters[name]
		if not (_is_number(value) or _is_text(value) or _is_range(value)):
			errors.append("%s: %s.stone_parameters.%s is %s, not a finite number, a name or a [min, max] pair" % [file, id, name, value])


## The varying parameters: each {"range": [min, max], "default": x} with the
## default inside the range, or {"choices": [...], "default": y} with the
## default one of the choices; an optional "note"; nothing else.
static func _check_varies(errors: PackedStringArray, file: String, id: String, varies: Variant) -> void:
	if not varies is Dictionary:
		errors.append("%s: %s.varies is not an object" % [file, id])
		return
	for name: String in varies:
		var parameter: Variant = varies[name]
		if not parameter is Dictionary or not parameter.has("default") or parameter.has("range") == parameter.has("choices"):
			errors.append("%s: %s.varies.%s is not a parameter with a default and a range or choices" % [file, id, name])
			continue
		for key: String in parameter:
			if not key in PARAMETER_KEYS:
				errors.append("%s: %s.varies.%s.%s is not in the schema" % [file, id, name, key])
		if parameter.has("note") and not _is_text(parameter.note):
			errors.append("%s: %s.varies.%s.note is empty" % [file, id, name])
		var default: Variant = parameter.default
		if parameter.has("range"):
			if not _is_range(parameter.range):
				errors.append("%s: %s.varies.%s.range is %s, not a [min, max] pair of finite numbers" % [file, id, name, parameter.range])
			elif not _is_number(default) or default < parameter.range[0] or default > parameter.range[1]:
				errors.append("%s: %s.varies.%s.default is %s, outside its range [%s, %s]" % [file, id, name, default, parameter.range[0], parameter.range[1]])
		elif not parameter.choices is Array or parameter.choices.is_empty():
			errors.append("%s: %s.varies.%s.choices is %s, not a list of choices" % [file, id, name, parameter.choices])
		elif not default in parameter.choices:
			errors.append("%s: %s.varies.%s.default is %s, not one of its choices %s" % [file, id, name, default, parameter.choices])


## The texture: a look line, and a size (a number or a [min, max] pair) that
## is inside the family's budget when the family has one.
static func _check_texture(errors: PackedStringArray, file: String, id: String, family: String, texture: Variant) -> void:
	if not texture is Dictionary or not _is_text(texture.get("look")):
		errors.append("%s: %s.texture has no look line" % [file, id])
		return
	for key: String in texture:
		if not key in TEXTURE_KEYS:
			errors.append("%s: %s.texture.%s is not in the schema" % [file, id, key])
	if not texture.has("size_px"):
		return
	var size: Variant = texture.size_px
	if not (_is_number(size) or _is_range(size)):
		errors.append("%s: %s.texture.size_px is %s, not a size or a [min, max] pair" % [file, id, size])
		return
	var budget: Array = TEXTURE_BUDGET_PX[family]
	if budget.is_empty():
		return
	var low: float = size[0] if size is Array else size
	var high: float = size[1] if size is Array else size
	if low < budget[0] or high > budget[1]:
		errors.append("%s: %s.texture.size_px is %s, outside family %s's budget [%d, %d]" % [file, id, size, family, budget[0], budget[1]])


## An E entry's own fields: a shell that is a B id (or "any"), privileges from
## the vocabulary with no repeats, a rarity rule. Whether the shell is in the
## catalogue is validate()'s cross-file check.
static func _check_economy(errors: PackedStringArray, file: String, id: String, element: Dictionary) -> void:
	var shell: Variant = element.get("shell")
	if element.has("shell") and not (shell == ANY_SHELL or (shell is String and is_id(shell) and shell.begins_with("B"))):
		errors.append("%s: %s.shell is %s, not a B id or %s" % [file, id, shell, ANY_SHELL])
	if element.has("privileges"):
		if not element.privileges is Array:
			errors.append("%s: %s.privileges is not a list" % [file, id])
		else:
			for i: int in element.privileges.size():
				var privilege: Variant = element.privileges[i]
				if not privilege in PRIVILEGES:
					errors.append("%s: %s.privileges has %s, not in the privilege vocabulary" % [file, id, privilege])
				elif element.privileges.find(privilege) != i:
					errors.append("%s: %s.privileges has %s twice" % [file, id, privilege])
	if element.has("rarity") and not _is_text(element.rarity):
		errors.append("%s: %s.rarity is empty" % [file, id])


## A number the catalogue can carry: an int or a float, and finite.
static func _is_number(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(value)


## A line of text that says something.
static func _is_text(value: Variant) -> bool:
	return value is String and value != ""


## A list of lines of text (empty is a list too).
static func _is_text_list(value: Variant) -> bool:
	if not value is Array:
		return false
	for line: Variant in value:
		if not _is_text(line):
			return false
	return true


## A [min, max] pair of finite numbers, min no more than max.
static func _is_range(value: Variant) -> bool:
	return value is Array and value.size() == 2 and _is_number(value[0]) and _is_number(value[1]) and value[0] <= value[1]
