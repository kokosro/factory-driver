extends SceneTree
## Headless config test: every car config under configs/cars/ is read the way
## the car reads its own (FileAccess, JSON.parse_string, CarConfigValidation)
## and has to pass. Seconds, and ahead of the smoke test in run_tests.sh: a
## config that is broken fails the suite here, not somewhere in the smoke test. Then the file is parsed a second time and has to come out the same: what
## the car is built from is what is written there, however often it is read.
## Exits 0 on success, 1 on any fault.

const CONFIG_DIR := "res://configs/cars"


func _initialize() -> void:
	var failures := 0
	var files := Array(DirAccess.get_files_at(CONFIG_DIR)).filter(func(file: String) -> bool: return file.ends_with(".json"))
	if files.is_empty():
		failures += 1
		printerr("  FAIL  no car config under %s" % CONFIG_DIR)
	for file: String in files:
		var path := CONFIG_DIR.path_join(file)
		var config: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		var errors := CarConfigValidation.validate(config, file)
		var reparsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if errors.is_empty() and var_to_bytes(config) != var_to_bytes(reparsed):
			errors.append("%s: parsed twice, it does not come out the same" % file)
		for error: String in errors:
			printerr("  FAIL  ", error)
		if errors.is_empty():
			print("  ok    ", "%s is a valid car: %s" % [file, config.identity.name])
		failures += errors.size()
	print("CONFIG TEST PASSED" if failures == 0 else "CONFIG TEST FAILED: %d fault(s)" % failures)
	quit(0 if failures == 0 else 1)
