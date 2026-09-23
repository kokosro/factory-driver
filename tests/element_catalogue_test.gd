extends SceneTree
## Headless element catalogue test: the seven files under configs/elements/
## (the 4B element library, docs/design/4b/element-library.md, as data) are read
## the way ElementCatalogue reads them (FileAccess, JSON.parse_string) and have
## to pass its validation. Seconds, and right after the config test in
## run_tests.sh: a broken entry fails the suite here, not somewhere a region
## table reads it. Then every entry is held, one ok line per check group, to
## what the plan asks (implementation-plan.md §4B-1): an id of the documented
## form, unique, in its family's file; a canon line cited; a priority of 1-9
## that is its family's; every varying parameter with a range or choices and
## its default inside; a texture size inside the family's budget; and for the
## E-table a shell that is a B entry and privileges from the fixed vocabulary.
## The files parse twice to the same bytes; the counts are the library's (81
## entries: R 18, T 9, S 6, B 11, E 14, V 8, F 15); entry() and by_family()
## answer; and validate() on broken fixtures built here (never on disk) names
## the field, one fixture per fault kind.
## Exits 0 on success, 1 on any fault.

## What the library holds, family by family: a transcription that dropped or
## invented an entry fails here (a new library entry is a "was ->" here).
const EXPECTED_COUNTS := {"R": 18, "T": 9, "S": 6, "B": 11, "E": 14, "V": 8, "F": 15}

## What each family's letter stands for, for the ok lines.
const FAMILY_NAMES := {"R": "road", "T": "terrain", "S": "sky/light", "B": "building", "E": "economy building", "V": "vegetation", "F": "furniture"}

var _failures := 0


func _initialize() -> void:
	var files := ElementCatalogue.read_files()
	_check_files(files)
	var seen := {}
	var b_ids := []
	for element: Dictionary in ElementCatalogue.entries_of(files):
		if element.get("family") == "B" and element.get("id") is String:
			b_ids.append(element.id)
	for family: String in ElementCatalogue.FAMILIES:
		var count := 0
		for element: Dictionary in ElementCatalogue.entries_of({ElementCatalogue.file_of(family): files[ElementCatalogue.file_of(family)]}):
			count += 1
			_check_id(element, family, seen)
			_check_canon(element)
			_check_priority(element, family)
			_check_varies(element)
			_check_texture(element, family)
			if family == "E":
				_check_economy(element, b_ids)
		_ok(count == EXPECTED_COUNTS[family], "%s.json holds the library's %d %s entries" % [family, EXPECTED_COUNTS[family], FAMILY_NAMES[family]], "%s.json holds %d entries, the library has %d" % [family, count, EXPECTED_COUNTS[family]])
	_ok(seen.size() == 81, "81 entries in all, every id unique across the seven files", "%d unique ids, the library has 81" % seen.size())
	_check_lookups()
	_check_broken_fixtures(files)
	print("ELEMENT CATALOGUE TEST PASSED" if _failures == 0 else "ELEMENT CATALOGUE TEST FAILED: %d fault(s)" % _failures)
	quit(0 if _failures == 0 else 1)


## An ok line or a FAIL line, counted.
func _ok(condition: bool, what: String, reason: String = "") -> void:
	if condition:
		print("  ok    ", what)
	else:
		_failures += 1
		printerr("  FAIL  ", reason if reason != "" else what)


## Every file is there, is JSON, parses twice to the same bytes, and the seven
## together pass validate() with nothing to say.
func _check_files(files: Dictionary) -> void:
	for file: String in files:
		var path := ElementCatalogue.DIR.path_join(file)
		var reparsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		var parsed: Variant = files[file]
		_ok(parsed is Dictionary and var_to_bytes(parsed) == var_to_bytes(reparsed), "%s parses, and parsed twice it comes out the same" % file, "%s: %s" % [file, "not a JSON object" if not parsed is Dictionary else "parsed twice, it does not come out the same"])
	var errors := ElementCatalogue.validate(files)
	for error: String in errors:
		printerr("  FAIL  ", error)
	_failures += errors.size()
	_ok(errors.is_empty(), "the seven files pass ElementCatalogue.validate() with nothing to say")


## The id: of the documented form, its family's letter, in its family's file,
## the entry's own family field agreeing, and not seen before.
func _check_id(element: Dictionary, family: String, seen: Dictionary) -> void:
	var id: String = str(element.get("id"))
	var form := ElementCatalogue.is_id(id)
	var own: bool = form and id[0] == family and element.get("family") == family
	var unique := not seen.has(id)
	seen[id] = true
	_ok(form and own and unique, "%s is an id of the documented form, unique, in %s.json (its family's file)" % [id, family], "%s in %s.json: %s" % [id, family, "not of the form family letter + digits" if not form else ("not its family's file" if not own else "seen before")])


## The canon line: non-empty, and shown so the transcription can be read back.
func _check_canon(element: Dictionary) -> void:
	var canon: Variant = element.get("canon")
	var cited: bool = canon is String and canon != ""
	_ok(cited, "%s cites a canon line: %s" % [element.id, _short(canon if cited else "")], "%s cites no canon line" % element.id)


## The priority: a whole number 1-9, and its family's.
func _check_priority(element: Dictionary, family: String) -> void:
	var priority: Variant = element.get("priority")
	var expected: int = ElementCatalogue.FAMILY_PRIORITY[family]
	var whole: bool = (priority is int or priority is float) and priority == floorf(priority)
	var in_band: bool = whole and priority >= ElementCatalogue.PRIORITY_MIN and priority <= ElementCatalogue.PRIORITY_MAX
	_ok(in_band and priority == expected, "%s priority %d, family %s's (1-9)" % [element.id, expected, family], "%s priority is %s, family %s's is %d" % [element.id, priority, family, expected])


## Every varying parameter: a range with a finite default inside it, or a list
## of choices with the default among them.
func _check_varies(element: Dictionary) -> void:
	var varies: Variant = element.get("varies")
	if not varies is Dictionary:
		_ok(false, "", "%s.varies is not an object" % element.id)
		return
	if varies.is_empty():
		_ok(true, "%s varies nothing (the library says so)" % element.id)
		return
	var names := []
	var bad := ""
	for name: String in varies:
		names.append(name)
		var parameter: Variant = varies[name]
		if not parameter is Dictionary or not parameter.has("default"):
			bad = "%s has no default" % name
		elif parameter.has("range"):
			var range: Variant = parameter.range
			var default: Variant = parameter.default
			if not (range is Array and range.size() == 2 and (default is int or default is float) and is_finite(default) and default >= range[0] and default <= range[1]):
				bad = "%s default %s is outside its range %s" % [name, default, range]
		elif parameter.has("choices"):
			if not (parameter.choices is Array and not parameter.choices.is_empty() and parameter.default in parameter.choices):
				bad = "%s default %s is not one of its choices %s" % [name, parameter.default, parameter.choices]
		else:
			bad = "%s has neither a range nor choices" % name
	_ok(bad == "", "%s varies %d parameter(s) (%s), each with a range or choices and its default inside" % [element.id, names.size(), ", ".join(names)], "%s.varies: %s" % [element.id, bad])


## The texture: a look line, and where a size is stated it is inside the
## family's budget (the canon's line; the sky plates have none).
func _check_texture(element: Dictionary, family: String) -> void:
	var texture: Variant = element.get("texture")
	if not texture is Dictionary or not texture.get("look") is String or texture.look == "":
		_ok(false, "", "%s.texture has no look line" % element.id)
		return
	var budget: Array = ElementCatalogue.TEXTURE_BUDGET_PX[family]
	if not texture.has("size_px"):
		_ok(true, "%s texture: no size stated, look: %s" % [element.id, _short(texture.look)])
		return
	var size: Variant = texture.size_px
	var low: float = size[0] if size is Array else size
	var high: float = size[1] if size is Array else size
	var inside: bool = budget.is_empty() or (low >= budget[0] and high <= budget[1])
	var stated: String = "%d-%d" % [low, high] if size is Array else "%d" % low
	_ok(inside, "%s texture: %s px inside the %s budget [%s, %s]" % [element.id, stated, FAMILY_NAMES[family], budget[0] if not budget.is_empty() else "-", budget[1] if not budget.is_empty() else "-"], "%s.texture.size_px %s is outside the %s budget %s" % [element.id, size, FAMILY_NAMES[family], budget])


## An E entry: its shell a B entry that is in the catalogue (or E14's "any"),
## its privileges from the vocabulary.
func _check_economy(element: Dictionary, b_ids: Array) -> void:
	var shell: Variant = element.get("shell")
	var shell_ok: bool = shell == ElementCatalogue.ANY_SHELL or shell in b_ids
	var privileges: Variant = element.get("privileges")
	var privileges_ok := privileges is Array
	if privileges_ok:
		for privilege: Variant in privileges:
			privileges_ok = privileges_ok and privilege in ElementCatalogue.PRIVILEGES
	var what := "%s shell %s %s; privileges %s" % [element.id, shell, "(the region table's)" if shell == ElementCatalogue.ANY_SHELL else "is a B entry", ", ".join(privileges) + " from the vocabulary" if privileges_ok and not privileges.is_empty() else "none of its own"]
	_ok(shell_ok and privileges_ok, what, "%s: shell %s %s; privileges %s" % [element.id, shell, "is no B entry" if not shell_ok else "ok", privileges])


## entry() and by_family() answer from the files, and say nothing for what is
## not there.
func _check_lookups() -> void:
	_ok(ElementCatalogue.entry("R1").get("title") == "Two-lane rural straight", "entry(\"R1\") is the two-lane rural straight")
	_ok(ElementCatalogue.entry("E14").get("shell") == ElementCatalogue.ANY_SHELL, "entry(\"E14\") takes any shell")
	_ok(ElementCatalogue.entry("R99").is_empty() and ElementCatalogue.entry("").is_empty(), "entry() of an id that is not there is empty")
	_ok(ElementCatalogue.by_family("E").size() == EXPECTED_COUNTS["E"] and ElementCatalogue.by_family("E")[0].id == "E1", "by_family(\"E\") is the 14 economy buildings in file order")
	_ok(ElementCatalogue.by_family("Z").is_empty(), "by_family() of a letter that is no family is empty")
	var total := 0
	for family: String in ElementCatalogue.FAMILIES:
		total += ElementCatalogue.by_family(family).size()
	_ok(total == 81, "by_family() over the seven families is the 81 entries", "by_family() over the seven families is %d entries" % total)


## validate() on fixtures broken in code, one per fault kind, has to name the
## entry and the field. A fixture is a copy of the real files with one thing
## changed; nothing is written to disk.
func _check_broken_fixtures(files: Dictionary) -> void:
	_expect_fault(_broken(files, "R", "R1", "id", "R1", "R.json", 1), "R1 is already in R.json", "a duplicate id")
	_expect_fault(_broken(files, "R", "R1", "id", "R01"), "R01 is not an id of the form", "an id of the wrong form (R01)")
	_expect_fault(_broken(files, "R", "R1", "id", "T1"), "T1.id names family T, the file is R's", "an id whose family letter is not its file's")
	_expect_fault(_broken(files, "T", "T1", "canon", ""), "T1.canon is empty", "an empty canon line")
	_expect_fault(_broken(files, "R", "R1", "varies", {"lane_width_m": {"range": [2.75, 3.5], "default": 4.0}}), "R1.varies.lane_width_m.default is 4.0, outside its range", "a default outside its range")
	_expect_fault(_broken(files, "R", "R5", "varies", {"island_dressing": {"choices": ["grass"], "default": "sculpture"}}), "R5.varies.island_dressing.default is sculpture, not one of its choices", "a default that is none of its choices")
	_expect_fault(_broken(files, "R", "R1", "priority", 0), "R1.priority is 0, priorities are 1-9", "a priority of 0")
	_expect_fault(_broken(files, "R", "R1", "priority", 10), "R1.priority is 10, priorities are 1-9", "a priority of 10")
	_expect_fault(_broken(files, "F", "F1", "priority", 1), "F1.priority is 1, family F's is 7", "a priority that is not the family's")
	_expect_fault(_broken(files, "E", "E1", "privileges", ["repair", "sell_beer"]), "E1.privileges has sell_beer, not in the privilege vocabulary", "a privilege name outside the vocabulary")
	_expect_fault(_broken(files, "E", "E1", "shell", "B99"), "E1.shell is B99, no such B entry", "a shell naming no B entry")
	_expect_fault(_broken(files, "E", "E1", "shell", "R1"), "E1.shell is R1, not a B id", "a shell that is not a B id")
	_expect_fault(_broken(files, "B", "B0", "texture", {"look": "a house", "size_px": 4096}), "B0.texture.size_px is 4096, outside family B's budget", "a texture over the family's budget")
	_expect_fault(_broken(files, "V", "V1", "stone_parameters", {"crown_lobes": true}), "V1.stone_parameters.crown_lobes is true, not a finite number", "a stone parameter that is no number, name or pair")
	_expect_fault(_broken(files, "S", "S1", "colour", "blue"), "S1.colour is not in the schema", "a key the schema does not know")
	_expect_fault({"R.json": null}, "R.json: not a JSON object", "a file that is not JSON")


## `files` with the entry `id` of family `family` changed: `key` set to
## `value`; or, with `duplicate_in` and `at`, a copy of the entry inserted at
## index `at` of that file. Deep copies: the real files stay what they are.
func _broken(files: Dictionary, family: String, id: String, key: String, value: Variant, duplicate_in: String = "", at: int = -1) -> Dictionary:
	var copy: Dictionary = files.duplicate(true)
	var file := ElementCatalogue.file_of(family)
	for element: Dictionary in copy[file].elements:
		if element.id == id:
			element[key] = value
			if duplicate_in != "":
				copy[duplicate_in].elements.insert(at, element.duplicate(true))
			break
	return copy


## One broken fixture: validate() has to say something with `expected` in it.
func _expect_fault(fixture: Dictionary, expected: String, what: String) -> void:
	var errors := ElementCatalogue.validate(fixture)
	var named := false
	for error: String in errors:
		if error.contains(expected):
			named = true
	_ok(named, "validate() names %s: \"%s\"" % [what, expected], "validate() on %s says %s, not \"%s\"" % [what, errors, expected])


## The first words of a line, for an ok line.
func _short(line: String) -> String:
	return line if line.length() <= 72 else line.substr(0, 69) + "..."
