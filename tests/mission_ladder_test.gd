extends SceneTree
## ML-1..6 ladder proof: thirty-three missions through the terminal Ace promotion.
## ECON-1: the production scan also finds the job board (configs/jobs); the
## ladder itself pays nothing - no ladder mission carries reward_credits.
var failures := 0
var checks := 0
var changes := 0
var fixture: Dictionary
var snow_surface: Dictionary
var test_path := (OS.get_environment("TMPDIR") if not OS.get_environment("TMPDIR").is_empty() else "/tmp").path_join("factory-driver-ladder-%d/campaign.json" % OS.get_process_id())

func _initialize() -> void:
	_run.call_deferred()

func ok(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
	print("  %s %s" % ["ok" if value else "FAIL", label])

func write_json(value: Variant) -> void:
	DirAccess.make_dir_recursive_absolute(test_path.get_base_dir())
	var file := FileAccess.open(test_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(value))
	file.close()

func fixture_with_surface(surface: Dictionary) -> Dictionary:
	var m := fixture.duplicate(true)
	m.surface_override = surface.duplicate()
	return m

func promoted(id: String, rank: String) -> Dictionary:
	var m := fixture.duplicate(true)
	m.id = id
	m.rank = rank
	m.unlock.required_rank = rank
	return m

func _run() -> void:
	OS.set_environment("FD_TELEMETRY", "0")
	fixture = JSON.parse_string(FileAccess.get_file_as_string("res://tests/ml1_proof.json"))
	snow_surface = JSON.parse_string(FileAccess.get_file_as_string("res://configs/missions/fd14_snow_testing.json")).surface_override
	_schema()
	var rs: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://configs/cars/fd_1073.json"))
	ok(CarConfigValidation.validate(rs, "fd_1073").is_empty(), "RS config validates every field and exact mass ledger")
	_store()
	await _episode()
	await _production()
	await _snow_braking()
	WorldStore.path_override = ""
	CampaignStore.path_override = ""
	for file in DirAccess.get_files_at(test_path.get_base_dir()):
		DirAccess.remove_absolute(test_path.get_base_dir().path_join(file))
	DirAccess.remove_absolute(test_path)
	DirAccess.remove_absolute(test_path.get_base_dir())
	print("MISSION LADDER TEST %s: %d checks" % ["PASSED" if failures == 0 else "FAILED", checks])
	quit(0 if failures == 0 else 1)

func _schema() -> void:
	ok(MissionSchema.validate(fixture).is_empty(), "proof schema accepted")
	ok(not fixture.has("surface_override") and MissionSchema.validate(fixture).is_empty(), "surface override absent is valid")
	var incomplete := snow_surface.duplicate()
	incomplete.erase("bump")
	var unknown := snow_surface.duplicate()
	unknown.snow = true
	for value in [null, [], 0, "snow", true, {}, incomplete, unknown]:
		var bad := fixture.duplicate(true)
		bad.surface_override = value
		ok(not MissionSchema.validate(bad).is_empty(), "surface override refuses bad shape " + str(value))
	for key in ["grip", "rolling_drag", "bump"]:
		for value in [null, false, "0.42", [], {}, INF, -INF, NAN, -0.01]:
			var bad := fixture.duplicate(true)
			bad.surface_override = snow_surface.duplicate()
			bad.surface_override[key] = value
			ok(not MissionSchema.validate(bad).is_empty(), "surface override refuses " + key + " = " + str(value))
		var missing := fixture.duplicate(true)
		missing.surface_override = snow_surface.duplicate()
		missing.surface_override.erase(key)
		ok(not MissionSchema.validate(missing).is_empty(), "surface override requires " + key)
	for grip in [Surfaces.GRIP_MIN - 0.001, Surfaces.GRIP_MAX + 0.001]:
		var bad := fixture.duplicate(true)
		bad.surface_override = {"grip": grip, "rolling_drag": 0, "bump": 0}
		ok(not MissionSchema.validate(bad).is_empty(), "surface override refuses out-of-range grip " + str(grip))
	for grip in [Surfaces.GRIP_MIN, Surfaces.GRIP_MAX]:
		var valid := fixture.duplicate(true)
		valid.surface_override = {"grip": grip, "rolling_drag": 0, "bump": 0}
		ok(MissionSchema.validate(valid).is_empty(), "surface override accepts inclusive bounds and zero drag/bump")
	# SNOW-2: the optional ground tint beside the three required keys.
	var shipped_tint: Array = snow_surface.ground_tint
	ok(shipped_tint.size() == 3 and is_equal_approx(shipped_tint[0], 0.82) and is_equal_approx(shipped_tint[1], 0.84) and is_equal_approx(shipped_tint[2], 0.87) and MissionSchema.validate(fixture_with_surface(snow_surface)).is_empty(), "FD-14 packed-snow ground tint validates as shipped")
	var untinted := snow_surface.duplicate()
	untinted.erase("ground_tint")
	ok(untinted.size() == 3 and MissionSchema.validate(fixture_with_surface(untinted)).is_empty(), "surface override without ground_tint stays valid")
	for value in [null, false, 0, 1.0, "white", {}, [], [1, 1], [1, 1, 1, 1], [1, "1", 1], [1, null, 1], [[1], [1], [1]], [INF, 1, 1], [1, NAN, 1], [1, 1, -INF], [-0.1, 1, 1], [1, 1.1, 1], [1, 1, 1.0001], [0, -0.0001, 0]]:
		var tinted := snow_surface.duplicate()
		tinted.ground_tint = value
		var faults := MissionSchema.validate(fixture_with_surface(tinted))
		ok(faults.size() >= 1 and faults[0].begins_with("surface_override.ground_tint"), "ground tint refuses " + str(value))
	for value in [[0, 0, 0], [1, 1, 1], [0.0, 1.0, 0.5], [1, 0.5, 0]]:
		var tinted := snow_surface.duplicate()
		tinted.ground_tint = value
		ok(MissionSchema.validate(fixture_with_surface(tinted)).is_empty(), "ground tint accepts " + str(value))
	var ring := fixture_with_surface(snow_surface)
	ring.environment = "ring"
	ok(MissionSchema.validate(ring).is_empty(), "ring mission carrying ground_tint validates (the runner applies nothing without a pad ground)")
	for value in [null, [], 3, "bad"]:
		ok(not MissionSchema.validate(value).is_empty(), "non-object refused: " + str(value))
	for field in ["id", "rank", "title", "briefing", "environment", "episode", "scoring", "unlock"]:
		var m := fixture.duplicate(true)
		m[field] = false
		ok(not MissionSchema.validate(m).is_empty(), "bad type refused: " + field)
	for pair in [["radius", -1], ["position", [0, 0]], ["sequence", 2], ["type", false], ["radius", INF], ["position", [0, "x", 0]]]:
		var m := fixture.duplicate(true)
		m.episode[0][pair[0]] = pair[1]
		ok(not MissionSchema.validate(m).is_empty(), "bad step refused: " + str(pair[0]) + str(pair[1]))
	for band in ["gold", "silver", "bronze"]:
		var m := fixture.duplicate(true)
		m.scoring.medal_times[band] = 99
		ok(not MissionSchema.validate(m).is_empty(), "bad medal refused: " + band)
	var invalid := fixture.duplicate(true)
	invalid.scoring.failure_conditions = ["damage"]
	ok(not MissionSchema.validate(invalid).is_empty(), "unsupported failure refused")
	invalid = fixture.duplicate(true)
	invalid.input_script.steps[0].press = ["reset_car"]
	ok(not MissionSchema.validate(invalid).is_empty(), "unsafe script action refused")
	invalid = fixture.duplicate(true)
	invalid.episode[0].type = "delivery_return"
	ok(not MissionSchema.validate(invalid).is_empty(), "return before pickup refused")
	var flag := fixture.duplicate(true)
	flag.episode[0].type = "flag"
	flag.episode[0].cones = [[0, 0.7, -10]]
	flag.episode[0].cone_radius = 1.2
	ok(MissionSchema.validate(flag).is_empty(), "reserved flag type now validates sequential targets")
	for pair in [["cones", []], ["cones", false], ["cones", [[0, 0]]], ["cones", [[0, "bad", 0]]], ["cones", [[0, INF, 0]]], ["cone_radius", 0], ["cone_radius", -1], ["cone_radius", "2"], ["cone_radius", INF]]:
		var bad := flag.duplicate(true)
		bad.episode[0][pair[0]] = pair[1]
		ok(not MissionSchema.validate(bad).is_empty(), "bad flag refused: " + str(pair))
	for key in ["cones", "cone_radius"]:
		var bad := flag.duplicate(true)
		bad.episode[0].erase(key)
		ok(not MissionSchema.validate(bad).is_empty(), "flag requires " + key)
	var a := fixture.duplicate(true)
	a.unlock.required_missions = ["MISSING"]
	ok(MissionSchema.catalog_errors([a]).has(a.id), "unknown reference refused")
	var b := fixture.duplicate(true)
	b.id = "B"
	a.unlock.required_missions = ["B"]
	b.unlock.required_missions = [a.id]
	ok(MissionSchema.catalog_errors([a, b]).size() == 2, "cycle excludes both entries")
	ok(MissionSchema.catalog_errors([fixture, fixture]).has(fixture.id), "duplicate excluded")
	b.unlock.required_missions = []
	b.title = 1
	ok(MissionSchema.catalog_errors([a, b]).size() == 2, "invalid predecessor excludes dependent")
	for pair in [[8.0, "gold"], [8.001, "silver"], [12.0, "silver"], [12.001, "bronze"], [18.0, "bronze"], [18.001, "complete"], [20.0, "complete"], [20.001, ""], [-1.0, ""], [INF, ""]]:
		ok(MissionSchema.medal(fixture.scoring, pair[0]) == pair[1], "medal boundary " + str(pair[0]))

func _store() -> void:
	ok(CampaignStore.active_path() == "", "telemetry zero gates default IO")
	CampaignStore.path_override = test_path
	ok(CampaignStore.active_path() == test_path, "override enables isolated IO")
	var store := CampaignStore.new()
	store.load_state()
	ok(store.state == CampaignStore.defaults(), "missing file defaults")
	store.changed.connect(func(): changes += 1)
	store.reconcile(LicenceExams.LICENCE_NONE)
	store.reconcile(LicenceExams.LICENCE_L0)
	ok(store.state.rank == "" and changes == 0, "L0 is not campaign enrollment")
	var manager := LicenceManager.new()
	manager.licence = {"level": LicenceExams.LICENCE_L1}
	store.attach(manager)
	ok(store.state.rank == "junior", "existing L1 enrolls immediately")
	ok(store.state.credentials.junior_licence, "Junior credential granted")
	manager.licence_changed.emit(1)
	ok(changes == 1, "repeated L1 signal is idempotent")
	var bytes := FileAccess.get_file_as_string(test_path)
	manager.licence_changed.emit(0)
	ok(FileAccess.get_file_as_string(test_path) == bytes, "car switch cannot demote driver")
	store.attach(null)
	manager.free()
	var loaded := CampaignStore.new()
	loaded.load_state()
	ok(loaded.state == store.state, "enrollment round-trip")
	ok(not FileAccess.file_exists(test_path + ".tmp"), "atomic write consumes temporary file")
	ok(store.unlock_reason(fixture) == "", "Junior episode unlocked")
	var m := promoted("FD-12", "junior")
	m.unlock.required_missions = [fixture.id]
	ok(store.unlock_reason(m) != "", "missing prerequisite locks")
	store.state.results[fixture.id] = {"attempts": 1, "best_time_s": -1, "medal": "gold"}
	ok(store.unlock_reason(m) != "", "corrupt predecessor cannot unlock")
	store.state.results.clear()
	ok(store.record_result(fixture, 9, false), "failure attempt saved")
	ok(store.unlock_reason(m) != "", "failed predecessor cannot unlock")
	ok(store.record_result(fixture, 8, true), "success saved")
	ok(store.unlock_reason(m) == "", "passed predecessor unlocks")
	store.record_result(fixture, 15, true)
	ok(store.state.results[fixture.id].best_time_s == 8, "worse replay keeps best")
	ok(store.state.results[fixture.id].medal == "gold" and store.state.results[fixture.id].attempts == 3, "medal kept and attempts counted")
	ok(store.record_result(m, 21, true) and store.state.rank == "junior", "timeout cannot promote")
	ok(store.record_result(m, 7, false) and not store.state.rewards.test_driver, "failed promotion grants nothing")
	ok(store.record_result(m, 7, true), "FD-12 promotion commits")
	loaded.load_state()
	ok(loaded.state.rank == "test_driver" and loaded.state.credentials.test_driver_licence and loaded.state.rewards.test_driver, "rank credential and RS entitlement together on disk")
	store.record_result(m, 6, true)
	ok(store.state.rank == "test_driver" and not store.state.rewards.chief, "promotion replay grants nothing new")
	ok(store.unlock_reason(promoted("FD-33", "chief")) != "", "cannot skip rank")
	store.record_result(promoted("FD-22", "test_driver"), 8, true)
	ok(store.state.rank == "chief" and store.state.rewards.chief, "FD-22 grants Chief and Boxster")
	store.record_result(promoted("FD-33", "chief"), 8, true)
	ok(store.state.rank == "ace" and store.state.rewards.ace, "FD-33 grants Ace and 996")
	store.record_result(promoted("FD-33", "chief"), 8, true)
	ok(store.state.rank == "ace" and store.state.rewards.size() == 3, "Ace terminal")
	var committed := store.state.duplicate(true)
	CampaignStore.path_override = test_path.get_base_dir()
	ok(not store.record_result(m, 5, true) and store.state == committed, "failed atomic rename publishes no partial state")
	DirAccess.remove_absolute(test_path.get_base_dir() + ".tmp")
	CampaignStore.path_override = test_path
	ok(DataDir.SEEDED_FILES.has("campaign.json"), "campaign follows data folder migration")
	var legacy := store.state.duplicate(true)
	legacy.version = 0
	legacy.missions = legacy.results
	legacy.erase("results")
	write_json(legacy)
	loaded.load_state()
	ok(loaded.state == store.state, "version zero results migrate")
	ok(JSON.parse_string(FileAccess.get_file_as_string(test_path)).version == 0, "migration read does not write")
	legacy.credentials.ace_licence = "true"
	write_json(legacy)
	loaded.load_state()
	ok(loaded.state.rank == "", "wrong credential type cannot promote")
	write_json({"version": 99, "rank": "ace"})
	loaded.load_state()
	ok(loaded.state == CampaignStore.defaults(), "future version defaults")
	write_json({"version": 1, "rank": "ace", "results": {"bad": {"medal": "gold"}}})
	loaded.load_state()
	ok(loaded.state == CampaignStore.defaults(), "corrupt credentials and results default")
	var file := FileAccess.open(test_path, FileAccess.WRITE)
	file.store_string("{broken")
	file.close()
	loaded.load_state()
	ok(loaded.state == CampaignStore.defaults(), "malformed JSON defaults")
	DirAccess.remove_absolute(test_path)
	manager = LicenceManager.new()
	manager.licence = {"level": -1}
	loaded.attach(manager)
	manager.licence_changed.emit(1)
	ok(loaded.state.rank == "junior", "fresh L1 signal enrolls")
	loaded.attach(null)
	manager.free()
	CampaignStore.path_override = ""
	var gated := CampaignStore.new()
	gated.load_state()
	ok(gated.state.rank == "", "gate reads no persisted progress")
	gated.reconcile(1)
	ok(gated.state.rank == "junior", "gated play retains session progress")
	CampaignStore.path_override = test_path

func _episode() -> void:
	var runner := MissionRunner.of(self)
	# was 33 -> 33 + the four ECON-1 jobs: one catalog, the ladder first.
	ok(runner != null and runner.catalog.size() == 33 + JOB_IDS.size(), "autoload discovers thirty-three production missions and the four jobs")
	ok(runner.get_child_count() == 0 and not runner.is_physics_processing() and not runner.is_processing_input(), "idle runner inert")
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	var car: ArcadeCar = scene.get_node("Car")
	var garage: Garage = scene.get_node("Garage")
	var manager: MissionManager = scene.get_node("MissionManager")
	runner.campaign.load_state()
	runner.campaign.reconcile(1)
	runner.configure(car, scene.get_node("HUD"))
	ok(not runner.start("MISSING"), "unknown mission cannot start")
	runner.load_catalog(PackedStringArray(["res://tests/ml1_proof.json"]))
	ok(runner.catalog.size() == 1, "test-only catalog loads proof")
	garage.show_page(Garage.Page.MISSIONS)
	# was six pages -> seven: ECON-1 adds JOBS after MISSIONS.
	ok(Garage.PAGE_TITLES.size() == 7 and Garage.PAGE_TITLES[5] == "MISSIONS" and Garage.PAGE_TITLES[6] == "JOBS", "seven-page pin")
	ok(garage.page_text().contains("JUNIOR"), "campaign rank displayed")
	ok(garage.page_rows()[0].hint.contains(fixture.briefing), "briefing displayed")
	ok(not garage.page_rows()[-1].enabled, "reward row disabled")
	ok(runner.start(fixture.id), "pad episode starts")
	ok(not garage.can_open() and manager.process_mode == Node.PROCESS_MODE_DISABLED, "episode owns driving context")
	ok(not runner.start(fixture.id), "cannot overlap episodes")
	var before := FileAccess.get_file_as_string(test_path)
	runner.abort()
	ok(FileAccess.get_file_as_string(test_path) == before and runner.last_result.is_empty(), "abort writes nothing")
	ok(not runner.is_physics_processing() and manager.process_mode != Node.PROCESS_MODE_DISABLED, "abort restores context")
	runner.start(fixture.id)
	runner._previous = Vector3(10, 0.7, -18)
	runner.tick(1, Vector3(0, 0.7, -18))
	ok(not runner.last_result.passed and runner.last_result.reason == "skipped gate", "skipped gate fails")
	runner.start(fixture.id)
	runner._previous = Vector3(5, 0.7, -10)
	runner.tick(1, Vector3(4, 0.7, -10))
	ok(runner.last_result.reason == "cone hit", "cone constraint fails")
	runner.start(fixture.id)
	for step: Dictionary in fixture.episode:
		runner.tick(1, Vector3(step.position[0], step.position[1], step.position[2]))
	var ordered_pass: bool = runner.last_result.passed and runner.last_result.medal == "gold"
	runner.start(fixture.id)
	runner._previous = Vector3(0, 0.7, 0)
	runner.tick(1, Vector3(0, 0.7, -20))
	ok(ordered_pass and runner.last_result.passed, "ordered gates and timed finish pass, including several crossings in one tick")
	ok(runner.result_text().begins_with("episode result:"), "episode result text owns its prefix")
	ok(not runner.is_physics_processing() and runner.get_child_count() == 0, "finish returns to inert")
	# Real car, same input driver as handling tests, no position injection.
	runner.start(fixture.id, true)
	for i in 1300:
		await physics_frame
		if runner.active.is_empty():
			break
	ok(not runner.last_result.is_empty() and runner.last_result.passed, "scripted proof drives the actual pad car")
	ok(not Input.is_action_pressed("accelerate"), "script inputs released after finish")
	garage.show_page(Garage.Page.MISSIONS)
	ok(garage.page_text().contains("episode result:"), "results visible in garage")
	# Empty paths trigger a production scan; clear the in-memory catalog to
	# exercise the actual empty-page branch without changing production files.
	runner.catalog.clear()
	garage.show_page(Garage.Page.MISSIONS)
	ok(garage.page_text().contains("No playable campaign missions yet"), "empty catalog page remains honest")
	runner.load_catalog()
	garage.show_page(Garage.Page.MISSIONS)
	ok(not garage.page_text().contains("No playable campaign missions yet") and garage.page_rows()[0].label == "FD-01 — Simple Slalom", "production scan replaces empty state with live rows")
	scene.queue_free()
	await process_frame

## ECON-1's job board: in the catalog, never on the ladder.
const JOB_IDS := ["JOB-01", "JOB-02", "JOB-03", "JOB-04"]
const PRODUCTION_IDS := ["FD-01", "FD-02", "FD-03", "FD-04", "FD-05", "FD-06", "FD-07", "FD-08", "FD-09", "FD-10", "FD-11", "FD-12", "FD-13", "FD-14", "FD-15", "FD-16", "FD-17", "FD-18", "FD-19", "FD-20", "FD-21", "FD-22", "FD-23", "FD-24", "FD-25", "FD-26", "FD-27", "FD-28", "FD-29", "FD-30", "FD-31", "FD-32", "FD-33"]

func _mission_rows(garage: Garage) -> Dictionary:
	garage.show_page(Garage.Page.MISSIONS)
	var rows := {}
	for row: Dictionary in garage.page_rows():
		if row.kind == "mission":
			rows[row.id] = row
	return rows

func _fresh_campaign(runner: MissionRunner) -> void:
	runner.campaign.state = CampaignStore.defaults()
	runner.campaign.reconcile(LicenceExams.LICENCE_L1)

func _point(position: Array) -> Vector3:
	return Vector3(position[0], position[1], position[2])

func _production() -> void:
	var runner := MissionRunner.of(self)
	runner.load_catalog()
	# was 33 -> 33 + the four ECON-1 jobs.
	ok(runner.catalog.size() == 33 + JOB_IDS.size(), "production scan finds exactly thirty-three missions and four jobs")
	ok(MissionSchema.catalog_errors(runner.catalog.values()).is_empty(), "production catalog has no reference or schema errors")
	for id: String in PRODUCTION_IDS:
		ok(runner.catalog.has(id), id + " discovered")
		if not runner.catalog.has(id):
			return
		ok(MissionSchema.validate(runner.catalog[id]).is_empty(), id + " validates without errors")
		# The ladder and the economy are separate loops: promotion pays nothing.
		ok(not runner.catalog[id].has("reward_credits") and not runner.catalog[id].has("job_kind"), id + " carries no reward_credits and no job_kind")
	for id: String in JOB_IDS:
		ok(runner.catalog.has(id) and runner.catalog[id].has("reward_credits") and runner.catalog[id].environment == "ring" and not PRODUCTION_IDS.has(id), id + " is a paid ring job beside the ladder, not on it")
	for id: String in ["FD-05", "FD-06", "FD-07", "FD-08", "FD-09", "FD-10", "FD-11"]:
		var m: Dictionary = runner.catalog[id]
		var bands: Dictionary = m.scoring.medal_times
		var source_limit: int = {"FD-05": 110, "FD-06": 50, "FD-07": 58, "FD-08": 180, "FD-09": 240, "FD-10": 36, "FD-11": 240}[id]
		ok(m.rank == "junior" and m.unlock.required_rank == "junior" and m.environment == "pad" and m.scoring.time_limit_s == source_limit, id + " preserves source rank and limit")
		ok(bands.gold < bands.silver and bands.silver < bands.bronze and bands.bronze < source_limit, id + " medal bands strictly precede source limit")
	for id: String in ["FD-08", "FD-09", "FD-10", "FD-11"]:
		var m: Dictionary = runner.catalog[id]
		var measured: float = m.provenance.medals.scripted_time_s
		var bands: Dictionary = m.scoring.medal_times
		ok(measured > 0 and bands.gold == ceil(measured * 1.05) and bands.silver == ceil(measured * 1.25) and bands.bronze == ceil(measured * 1.50), id + " bands derive from recorded scripted measurement")
		var on_pad := true
		for step: Dictionary in m.episode:
			var points: Array = [step.position] + step.get("cones", [])
			for point: Array in points:
				on_pad = on_pad and point[1] == 0.7 and point[0] >= TestPad.GROUND_CORE_MIN.x and point[0] <= TestPad.GROUND_CORE_MAX.x and point[2] >= TestPad.GROUND_CORE_MIN.y and point[2] <= TestPad.GROUND_CORE_MAX.y
		ok(on_pad, id + " route and cones stay on pad at gate height")
	var delivery2: Array = runner.catalog["FD-08"].episode
	ok(delivery2[0].type == "delivery_pickup" and delivery2[-2].type == "delivery_return" and delivery2[-1].type == "timed_finish" and delivery2 != runner.catalog["FD-05"].episode, "FD-08 preserves delivery mechanics on a different route")
	var circuit: Array = runner.catalog["FD-03"].episode
	var double_circuit: Array = runner.catalog["FD-10"].episode
	var same_ring: bool = double_circuit.size() == 9 and double_circuit[0].cones == circuit[0].cones and double_circuit[0].cone_radius == circuit[0].cone_radius
	for lap in 2:
		for gate in range(1, 5):
			same_ring = same_ring and double_circuit[lap * 4 + gate].position == circuit[gate].position and double_circuit[lap * 4 + gate].radius == circuit[gate].radius
	ok(same_ring, "FD-10 repeats the exact FD-03 gate ring twice with its cone constraints")
	var delivery: Array = runner.catalog["FD-05"].episode
	ok(delivery[0].type == "delivery_pickup" and delivery[-2].type == "delivery_return" and delivery[-1].type == "timed_finish", "delivery uses existing pickup/handover/finish steps")
	# Production constraints use the existing landmark coordinates, not an
	# invented alternating cone layout. Gates weave around that straight line.
	var real_cones := TestPad.slalom_cone_positions()
	for id: String in ["FD-01", "FD-04", "FD-06", "FD-07", "FD-12"]:
		var cones: Array = runner.catalog[id].episode[0].cones
		var count := 6 if id == "FD-01" else 14
		var matches := cones.size() == count
		for k in mini(cones.size(), count):
			matches = matches and _point(cones[k]).is_equal_approx(real_cones[k] + Vector3(0, 0.7, 0))
		ok(matches, id + " uses the real pad slalom cones at gate height")
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	var car: ArcadeCar = scene.get_node("Car")
	var garage: Garage = scene.get_node("Garage")
	runner.configure(car, scene.get_node("HUD"))
	_fresh_campaign(runner)
	WorldStore.path_override = test_path.get_base_dir().path_join("world.json")
	var rows := _mission_rows(garage)
	ok(not runner.campaign.owns_car("fd_1073"), "fresh Junior does not own the RS")
	ok(not runner.campaign.take_car("fd_1073", WorldStore.active_path()), "fresh driver cannot TAKE the RS")
	for row: Dictionary in garage.page_rows():
		if row.kind == "reward" and row.id == "test_driver":
			ok(not row.enabled and not row.label.contains("OWNED"), "fresh garage reward is locked")
	ok(rows.size() == 33 and rows["FD-01"].enabled and rows["FD-01"].label == "FD-01 — Simple Slalom", "fresh Junior sees playable FD-01")
	# ECON-1: the jobs have a page of their own; on the pad they are listed
	# and cannot start (ring jobs), and the ladder's page does not show them.
	var on_ladder_page := false
	for id: String in JOB_IDS:
		on_ladder_page = on_ladder_page or rows.has(id)
	garage.show_page(Garage.Page.JOBS)
	var job_rows := garage.page_rows()
	var jobs_listed := job_rows.size() == JOB_IDS.size()
	for i in mini(job_rows.size(), JOB_IDS.size()):
		jobs_listed = jobs_listed and job_rows[i].kind == "job" and job_rows[i].id == JOB_IDS[i] and not job_rows[i].enabled and job_rows[i].hint.contains("Locked: Open the ring from DRIVE first")
	ok(not on_ladder_page and jobs_listed and not runner.start("JOB-01") and runner.active.is_empty(), "jobs stay off the ladder page; the JOBS page lists the four, greyed on the pad, and the runner refuses a ring job here")
	garage.show_page(Garage.Page.MISSIONS)
	for i in range(1, PRODUCTION_IDS.size()):
		var id: String = PRODUCTION_IDS[i]
		var reason: String = "Complete " + PRODUCTION_IDS[i - 1] if i < 12 else ("Requires test driver" if i < 22 else "Requires chief")
		ok(not rows[id].enabled and rows[id].hint.contains("Locked: " + reason) and runner.campaign.unlock_reason(runner.catalog[id]) == reason, id + " row shows exact prerequisite lock")
	garage._start_episode("FD-01")
	ok(runner.active.get("id") == "FD-01" and runner._driver == null, "garage starts the unlocked human mission without a scripted driver")
	runner.abort()
	var chief_entry: Dictionary
	for i in range(PRODUCTION_IDS.size() - 1):
		var id: String = PRODUCTION_IDS[i]
		var mission: Dictionary = runner.catalog[id]
		ok(runner.campaign.record_result(mission, 1, false) and runner.campaign.unlock_reason(runner.catalog[PRODUCTION_IDS[i + 1]]) == ("Requires test driver" if id == "FD-12" else ("Requires chief" if id == "FD-22" else "Complete " + id)), id + " failed attempt cannot unlock successor")
		ok(not runner.start(PRODUCTION_IDS[i + 1]), id + " successor cannot bypass lock via runner")
		ok(runner.campaign.record_result(mission, mission.scoring.medal_times.silver, true), id + " prerequisite result saved")
		rows = _mission_rows(garage)
		var next_id: String = PRODUCTION_IDS[i + 1]
		ok(rows[next_id].enabled and runner.campaign.unlock_reason(runner.catalog[next_id]) == "", next_id + " row unlocks after predecessor")
		if id == "FD-21":
			await _ml5_configs(runner, car, garage)
			chief_entry = runner.campaign.state.duplicate(true)
	_ml6_configs(runner, garage)
	# Restore the pre-Chief state for the original promotion failure/pass proof.
	runner.campaign.state = chief_entry
	_flag_mechanics(runner)
	_flag_mechanics(runner, "FD-20")
	_double_circuit(runner)
	# Real production geometry; position injection isolates failure/scoring from
	# vehicle pace. Band midpoints come from the config so later tuning is safe.
	for id: String in PRODUCTION_IDS:
		var mission: Dictionary = runner.catalog[id]
		ok(runner.start(id), id + " starts for failure injection")
		runner.set_physics_process(false)
		if id in ["FD-02", "FD-05", "FD-08", "FD-11", "FD-13", "FD-15", "FD-17", "FD-19", "FD-24", "FD-28", "FD-32"]:
			var gate := _point(mission.episode[2].position)
			runner._previous = gate + Vector3(10, 0, 0)
			runner.tick(0.1, gate)
			ok(runner.last_result.get("reason") == "skipped gate" and not runner.last_result.get("passed", true), id + " later gate fails out of order")
		elif id in ["FD-30", "FD-31", "FD-33"]:
			var gate := _point(mission.episode[2].position)
			runner._previous = gate + Vector3(0, 10, 0)
			runner.tick(0.1, gate)
			ok(runner.step_index == 0 and runner.last_result.is_empty(), id + " later shared circuit gate waits its turn")
			runner.abort()
		elif id in ["FD-09", "FD-20"]:
			var cone := _point(mission.episode[0].cones[2])
			runner._previous = cone + Vector3(0, 5, 0)
			runner.tick(0.1, cone)
			ok(runner.step_index == 0 and runner.flag_progress().current == 1 and runner.last_result.is_empty(), "out-of-order flag 3 neither advances nor fails")
			runner.abort()
		else:
			var cone := _point(mission.episode[1 if id in ["FD-21", "FD-23"] else 0].cones[0])
			runner._previous = cone + Vector3(2, 0, 0)
			runner.tick(0.1, cone - Vector3(2, 0, 0))
			ok(runner.last_result.get("reason") == "cone hit" and not runner.last_result.get("passed", true), id + " swept cone contact fails")
			if id == "FD-14":
				ok(_surface_values(car) == [1.0, 1.0, 0.0], "cone failure restores snow inputs")
		ok(runner.start(id), id + " starts for timeout")
		runner.set_physics_process(false)
		runner.tick(mission.scoring.time_limit_s + 1.0, car.global_position)
		ok(runner.last_result.get("reason") == "time limit" and not runner.last_result.get("passed", true), id + " time limit fails")
		if id == "FD-22":
			ok(runner.campaign.state.rank == "test_driver" and not runner.campaign.owns_car("boxster_986"), "failed production promotion grants no Chief ownership")
		if id == "FD-33":
			var failed := CampaignStore.new()
			failed.load_state()
			ok(failed.state.rank == "chief" and not failed.state.credentials.ace_licence and not failed.state.rewards.ace and not failed.owns_car("fd_2000"), "failed production FD-33 persists no Ace grant")
		var bands: Dictionary = mission.scoring.medal_times
		var samples := {"gold": bands.gold / 2.0, "silver": (bands.gold + bands.silver) / 2.0, "bronze": (bands.silver + bands.bronze) / 2.0, "complete": (bands.bronze + mission.scoring.time_limit_s) / 2.0}
		if bands.bronze == mission.scoring.time_limit_s:
			samples.erase("complete") # No unmedalled success interval at this source limit.
		for medal: String in samples:
			ok(runner.start(id), id + " starts for " + medal + " scoring")
			runner.set_physics_process(false)
			for step: Dictionary in mission.episode:
				var points: Array = step.cones if step.type == "flag" else [step.position]
				var radius: float = step.cone_radius if step.type == "flag" else step.radius
				for target: Array in points:
					var point := _point(target)
					# Independent crossings isolate scoring from route geometry.
					runner._previous = point + Vector3(0, radius + 1.0, 0)
					runner.tick(float(samples[medal]) / mission.episode.size() / points.size(), point)
			ok(runner.last_result.get("passed", false) and runner.last_result.get("medal") == medal and is_equal_approx(runner.last_result.get("time_s", -1.0), samples[medal]), id + " injected elapsed awards " + medal)
			if id == "FD-14":
				ok(runner.last_result.get("passed", false) and _surface_values(car) == [1.0, 1.0, 0.0], "PASSED scoring path restores snow inputs: " + medal)
		if id == "FD-12":
			_reward_roundtrip(runner, garage)
			ok(runner.campaign.state.rank == "test_driver" and runner.campaign.state.credentials.test_driver_licence and runner.campaign.state.rewards.test_driver, "production FD-12 grants Test Driver and RS 2.7 entitlement")
		if id == "FD-22":
			_chief_roundtrip(runner, garage)
		if id == "FD-33":
			_ace_roundtrip(runner, garage)
	scene.queue_free()
	await process_frame
	WorldStore.path_override = ""
	# Every shipped script runs on a newly loaded, otherwise untouched pad car.
	# FD-14 also verifies its measured snow provenance and derived medal bands.
	_fresh_campaign(runner)
	for id: String in PRODUCTION_IDS:
		scene = load("res://scenes/main.tscn").instantiate()
		root.add_child(scene)
		await process_frame
		car = scene.get_node("Car")
		runner.configure(car, scene.get_node("HUD"))
		var reverse_crossings: Array = []
		var last_step := 0
		ok(runner.start(id, true), id + " shipped scripted drive starts")
		if id == "FD-14":
			ok(car.front_tyre_temp == 0 and car.rear_tyre_temp == 0 and _surface_values(car) == [snow_surface.grip, snow_surface.grip, snow_surface.rolling_drag], "FD-14 measured drive starts with cold tyres AND snow")
			ok(_ground(car) != null and _close(_ground(car).albedo_color, _linear_tint()), "FD-14 measured drive runs on the packed-snow ground tint")
		for frame in range(int(runner.catalog[id].scoring.time_limit_s * 60) + 120):
			await physics_frame
			if id == "FD-29" and runner.step_index != last_step:
				reverse_crossings.append([runner.step_index, car.reverse_engaged, car.forward_speed])
				last_step = runner.step_index
			if runner.active.is_empty():
				break
		ok(runner.active.is_empty() and runner.last_result.get("passed", false), id + " shipped script passes with the actual pad car")
		if id == "FD-14":
			ok(runner.last_result.get("passed", false) and _surface_values(car) == [1.0, 1.0, 0.0], "snow restored after real PASSED drive")
			ok(_ground(car).albedo_color == TestPad.COLOR_ASPHALT and runner._ground_material == null, "asphalt ground restored after real PASSED drive")
			var measured: float = runner.last_result.get("time_s", -1.0)
			var bands: Dictionary = runner.catalog[id].scoring.medal_times
			ok(measured > 0 and measured <= runner.catalog[id].scoring.time_limit_s and bands.gold == ceil(measured * 1.05) and bands.silver == ceil(measured * 1.25) and bands.bronze == ceil(measured * 1.50), "FD-14 medal bands derive from this real snow pass inside source limit")
			ok(absf(measured - runner.catalog[id].provenance.medals.scripted_time_s) < 0.000001, "FD-14 snow measurement matches recorded provenance")
		if id == "FD-29":
			var reversed := 0
			for crossing: Array in reverse_crossings:
				if crossing[0] in [3, 4] and crossing[1] and crossing[2] < -1.0:
					reversed += 1
			ok(reverse_crossings.size() == 10 and not reverse_crossings[0][1] and reverse_crossings[0][2] > 1 and not reverse_crossings[1][1] and reverse_crossings[1][2] > 1, "FD-29 first two gates cross forward before reversing")
			ok(reversed == 2, "FD-29 crosses both return gates in physical reverse")
			ok(not car.reverse_engaged and car.forward_speed > 1.0, "FD-29 finale finishes driving forward")
		print("  " + runner.result_text())
		print("  scripted time: %s %.6f s" % [id, runner.last_result.get("time_s", -1.0)])
		ok(runner.get_child_count() == 0 and not runner.is_physics_processing(), id + " scripted finish leaves runner inert")
		var loaded := CampaignStore.new()
		loaded.load_state()
		var result: Dictionary = loaded.state.results.get(id, {})
		ok(runner.last_result.get("saved", false) and result.get("medal", "") != "" and is_equal_approx(result.get("best_time_s", -1.0), runner.last_result.get("time_s", -2.0)), id + " scripted pass survives store reload")
		ok(not Input.is_action_pressed("accelerate") and not Input.is_action_pressed("steer_left") and not Input.is_action_pressed("steer_right"), id + " script releases its inputs")
		if id not in ["FD-01", "FD-02", "FD-03", "FD-04", "FD-12"]:
			var shipped: Dictionary = runner.catalog[id].input_script
			var scoring: Dictionary = runner.catalog[id].scoring
			if int(id.substr(3)) >= 23:
				# Keep the shipped controls and route; shorten the clock to force a real-car timeout mid-route.
				var deadline: float = runner.catalog[id].provenance.medals.scripted_time_s * 0.5
				runner.catalog[id].scoring = {"time_limit_s": deadline, "medal_times": {"gold": deadline * 0.25, "silver": deadline * 0.5, "bronze": deadline * 0.75}, "failure_conditions": scoring.failure_conditions}
			else:
				runner.catalog[id].input_script = {"steps": [{"press": ["accelerate" if id in ["FD-06", "FD-07"] else "brake"]}]}
			ok(runner.start(id, true), id + " bad scripted drive starts")
			for frame in range(int(runner.catalog[id].scoring.time_limit_s * 60) + 120):
				await physics_frame
				if runner.active.is_empty():
					break
			ok(runner.active.is_empty() and not runner.last_result.get("passed", true), id + " bad scripted drive fails on the actual pad car")
			if id == "FD-14":
				ok(runner.last_result.get("reason") == "time limit" and _surface_values(car) == [1.0, 1.0, 0.0], "snow restored after real FAILED drive")
				ok(_ground(car).albedo_color == TestPad.COLOR_ASPHALT and runner._ground_material == null, "asphalt ground restored after real FAILED drive")
			if int(id.substr(3)) >= 23:
				ok(runner.last_result.get("reason") == "time limit" and runner.step_index > 0 and car.global_position.distance_to(car.get_spawn_transform().origin) > 1.0, id + " shipped controls drive gates before the forced deadline fails")
			runner.catalog[id].input_script = shipped
			runner.catalog[id].scoring = scoring
			loaded.load_state()
			ok(loaded.state.results.get(id, {}).get("attempts", 0) == 2 and loaded.state.results.get(id, {}).get("best_time_s", -1) == result.get("best_time_s", -2), id + " failed drive persists attempt and preserves best")
		if id == "FD-22":
			ok(loaded.state.rank == "chief" and loaded.state.credentials.chief_licence and loaded.state.rewards.chief and loaded.owns_car("fd_1073") and loaded.owns_car("boxster_986"), "scripted promotion persists Chief rank, licence and both reward entitlements together")
		runner.abort()
		scene.queue_free()
		await process_frame
	var persisted := CampaignStore.new()
	persisted.load_state()
	ok(persisted.state.rank == "ace" and persisted.state.credentials.ace_licence and persisted.state.rewards.ace and persisted.owns_car("fd_1073") and persisted.owns_car("boxster_986") and persisted.owns_car("fd_2000"), "scripted promotion persists Ace rank, licence and all three entitlements together")

func _surface_values(car: ArcadeCar) -> Array:
	return [car.front_surface_grip, car.rear_surface_grip, car.surface_rolling_decel]

## SNOW-2 helpers. The pad's ground material through its own accessor; the
## display tint converted once, as the runner converts it; a Color match within
## one 8-bit step per channel; every OTHER StandardMaterial3D under the pad
## (material overrides and mesh surface materials) keyed by instance id.
func _ground(car: ArcadeCar) -> StandardMaterial3D:
	var pad := car.get_parent().find_child("TestPad", true, false) as TestPad
	return pad.get_ground_material() if pad != null else null

func _linear_tint() -> Color:
	return Color(snow_surface.ground_tint[0], snow_surface.ground_tint[1], snow_surface.ground_tint[2]).srgb_to_linear()

func _close(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) <= 1.0 / 255.0 and absf(a.g - b.g) <= 1.0 / 255.0 and absf(a.b - b.b) <= 1.0 / 255.0 and absf(a.a - b.a) <= 1.0 / 255.0

func _pad_albedos(pad: Node, ground: Material) -> Dictionary:
	var albedos := {}
	var stack: Array[Node] = [pad]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is MeshInstance3D:
			var instance := node as MeshInstance3D
			var materials: Array = [instance.material_override]
			if instance.mesh != null:
				for i in instance.mesh.get_surface_count():
					materials.append(instance.mesh.surface_get_material(i))
					materials.append(instance.get_surface_override_material(i))
			for material in materials:
				if material is StandardMaterial3D and material != ground:
					albedos[material.get_instance_id()] = material.albedo_color
		for child in node.get_children():
			stack.append(child)
	return albedos

func _snow_tint(runner: MissionRunner, car: ArcadeCar) -> void:
	var pad := car.get_parent().find_child("TestPad", true, false) as TestPad
	var ground := _ground(car)
	var ground_mesh := pad.get_node_or_null("Ground/MeshInstance3D") as MeshInstance3D
	var expected := _linear_tint()
	var display := Color(snow_surface.ground_tint[0], snow_surface.ground_tint[1], snow_surface.ground_tint[2])
	ok(ground != null and ground_mesh != null and ground_mesh.material_override == ground and ground.albedo_color == TestPad.COLOR_ASPHALT, "pad ground mesh carries the pad's authored asphalt material before the episode")
	var original: Color = ground.albedo_color
	var witnesses := _pad_albedos(pad, ground)
	var skid_seen := false
	for id in witnesses:
		skid_seen = skid_seen or witnesses[id] == TestPad.COLOR_SKID_SURFACE
	ok(witnesses.size() >= 3 and skid_seen, "pad carries witness materials beside the ground, the skid disc's paler asphalt among them")
	ok(runner._ground_material == null, "no ground capture before the tinted episode")
	ok(runner.start("FD-14"), "tinted human FD-14 starts")
	ok(_close(ground.albedo_color, expected), "ground albedo is the display tint converted once to linear")
	ok(not _close(ground.albedo_color, display) and expected.r < display.r and expected.g < display.g and expected.b < display.b, "the tint is not written raw: linear albedo sits below the display value")
	ok(ground.albedo_color.a == original.a, "tint keeps the ground's alpha")
	ok(ground_mesh.material_override == ground and pad.get_ground_material() == ground and runner._ground_material == ground, "ground mesh keeps the same material instance: tinted in place, not replaced")
	ok(_pad_albedos(pad, ground) == witnesses, "no other pad material takes the tint (material overrides and surface materials)")
	ok(runner._ground_original == original, "the original asphalt albedo was captured before the first write")
	ground.albedo_color = TestPad.COLOR_ASPHALT
	runner._physics_process(1.0 / 60.0)
	ok(_close(ground.albedo_color, expected) and _surface_values(car) == [snow_surface.grip, snow_surface.grip, snow_surface.rolling_drag], "tint reasserted each physics tick beside the surface inputs")
	runner.abort()
	ok(ground.albedo_color == original and runner._ground_material == null, "abort restores the exact original ground albedo and clears the capture")
	ok(_pad_albedos(pad, ground) == witnesses, "witness materials unchanged after abort")
	# PASSED path: every FD-14 target crossed by injection.
	var cold: Dictionary = runner.catalog["FD-14"]
	ok(runner.start("FD-14") and _close(ground.albedo_color, expected), "tinted FD-14 starts for the injected pass")
	runner.set_physics_process(false)
	for step: Dictionary in cold.episode:
		var point := _point(step.position)
		runner._previous = point + Vector3(0, step.radius + 1.0, 0)
		runner.tick(0.1, point)
	ok(runner.last_result.get("passed", false) and ground.albedo_color == original and runner._ground_material == null, "PASSED finish restores the ground albedo")
	# FAILED path: the time limit.
	ok(runner.start("FD-14") and _close(ground.albedo_color, expected), "tinted FD-14 starts for the timeout")
	runner.set_physics_process(false)
	runner.tick(cold.scoring.time_limit_s + 1.0, car.global_position)
	ok(runner.last_result.get("reason") == "time limit" and ground.albedo_color == original and runner._ground_material == null, "FAILED finish restores the ground albedo")
	# FAILED path: cone contact.
	ok(runner.start("FD-14") and _close(ground.albedo_color, expected), "tinted FD-14 starts for the cone contact")
	runner.set_physics_process(false)
	var cone := _point(cold.episode[0].cones[0])
	runner._previous = cone + Vector3(2, 0, 0)
	runner.tick(0.1, cone - Vector3(2, 0, 0))
	ok(runner.last_result.get("reason") == "cone hit" and ground.albedo_color == original, "cone failure restores the ground albedo")
	# Teardown path: the single cleanup, as _exit_tree reaches it.
	ok(runner.start("FD-14") and _close(ground.albedo_color, expected), "tinted FD-14 starts for the teardown")
	runner._cleanup()
	ok(ground.albedo_color == original and runner._ground_material == null and runner.active.is_empty(), "teardown restores the ground albedo")
	runner._cleanup()
	ok(ground.albedo_color == original, "repeated cleanup without a capture leaves the ground untouched")
	# The capture is whatever was there, not the authored asphalt.
	var external := Color(0.1, 0.2, 0.3)
	ground.albedo_color = external
	ok(runner.start("FD-14") and _close(ground.albedo_color, expected), "tint applies over an external ground albedo")
	runner.abort()
	ok(ground.albedo_color == external, "restore writes back the captured pre-episode albedo, not the authored asphalt")
	# Inert without the field: an override without ground_tint, and no override.
	var plain: Dictionary = cold.duplicate(true)
	plain.id = "SNOW-PLAIN"
	plain.surface_override.erase("ground_tint")
	runner.catalog[plain.id] = plain
	ok(runner.start(plain.id) and ground.albedo_color == external and runner._ground_material == null, "override without ground_tint captures and writes no ground material")
	ok(_surface_values(car) == [snow_surface.grip, snow_surface.grip, snow_surface.rolling_drag], "the untinted override still delivers the surface inputs")
	runner._physics_process(1.0 / 60.0)
	ok(ground.albedo_color == external, "untinted tick writes no ground material")
	runner.abort()
	ok(ground.albedo_color == external and runner._ground_material == null, "untinted cleanup writes no ground material")
	runner.catalog.erase(plain.id)
	ok(runner.start("FD-16") and ground.albedo_color == external and runner._ground_material == null, "mission without any override captures no ground material")
	runner._physics_process(1.0 / 60.0)
	runner.abort()
	ok(ground.albedo_color == external, "no-override tick and cleanup leave the ground albedo alone")
	ground.albedo_color = original
	ok(_pad_albedos(pad, ground) == witnesses, "witness materials unchanged through every path")
	# The boundary: a scene without a TestPad (the ring venue) has no ground material to tint.
	var bare := Node3D.new()
	root.add_child(bare)
	runner._capture_ground_tint(bare, snow_surface.ground_tint)
	ok(runner._ground_material == null and ground.albedo_color == original, "no TestPad in the scene: the tint applies nothing (ring venues are not tinted by this mechanism)")
	runner._apply_ground_tint()
	runner._cleanup()
	ok(ground.albedo_color == original, "apply and cleanup without a capture are inert")
	bare.free()
	# A pad torn down under a live tinted episode: the runner's own reference keeps
	# the material alive, so the restore writes to a material nothing displays and
	# the capture clears; the freed car is what the next tick notices.
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	# The spare boot can auto-open the fresh-driver world map (WorldMap._ready's
	# open(true) pauses the tree) and a freed scene never closes it: the pause
	# would latch and stop every later real drive. Closed here, as a player
	# closing it would, with the boot's state pinned.
	var spare_map: WorldMap = scene.get_node_or_null("WorldMap") as WorldMap
	var auto_opened := spare_map != null and spare_map.is_open
	if auto_opened:
		spare_map.close()
	ok(auto_opened and not paused, "the spare boot's fresh-driver world map auto-open is closed before the episode (its open(true) pauses the tree; a freed scene would leave the pause latched)")
	var spare: ArcadeCar = scene.get_node("Car")
	runner.configure(spare, scene.get_node("HUD"))
	var spare_ground := _ground(spare)
	ok(runner.start("FD-14") and spare_ground != null and spare_ground != ground and _close(spare_ground.albedo_color, expected), "a second pad's own fresh ground material is tinted, not the first pad's")
	ok(ground.albedo_color == original, "the first pad's ground keeps its albedo while the second is tinted")
	runner.set_physics_process(false)
	scene.queue_free()
	await process_frame
	ok(not is_instance_valid(spare) and is_instance_valid(spare_ground) and runner._ground_material == spare_ground, "pad freed under the episode: the material reference stays valid (held by the runner and this test) and the capture is still held")
	runner._physics_process(1.0 / 60.0)
	ok(runner.active.is_empty() and runner._ground_material == null and spare_ground.albedo_color == original, "freed-car tick aborts, restores the captured albedo and clears the capture")
	runner.configure(car, car.get_parent().get_node("HUD"))
	ok(runner.start("FD-14") and _close(ground.albedo_color, expected), "the original pad tints again after the torn-down one")
	runner.abort()
	ok(ground.albedo_color == original and _pad_albedos(pad, ground) == witnesses, "original pad restored, witnesses unchanged")

func _snow_braking() -> void:
	var runner := MissionRunner.of(self)
	var distances: Array[float] = []
	for snow in [false, true]:
		var scene: Node = load("res://scenes/main.tscn").instantiate()
		root.add_child(scene)
		await process_frame
		var car: ArcadeCar = scene.get_node("Car")
		runner.configure(car, scene.get_node("HUD"))
		var mission := fixture.duplicate(true)
		mission.id = "SNOW-BRAKING"
		mission.cold_tyres = true
		mission.episode = [{"type": "timed_finish", "sequence": 0, "position": [0, 0.7, -1000], "radius": 2}]
		mission.input_script = {"steps": [{"press": ["brake"]}]}
		if snow:
			mission.surface_override = runner.catalog["FD-14"].surface_override.duplicate()
		runner.catalog[mission.id] = mission
		ok(runner.start(mission.id, true), "identical cold braking script starts: snow=" + str(snow))
		car.velocity = -car.global_basis.z * 20.0
		car.forward_speed = 20.0
		var previous := car.global_position
		var distance := 0.0
		var stopped := false
		for frame in 600:
			await physics_frame
			distance += car.global_position.distance_to(previous)
			previous = car.global_position
			if absf(car.forward_speed) < 0.1:
				stopped = true
				break
		ok(stopped and not runner.active.is_empty(), "physical braking stops from 20 m/s before timeout: snow=" + str(snow))
		distances.append(distance)
		runner.abort()
		scene.queue_free()
		await process_frame
	runner.catalog.erase("SNOW-BRAKING")
	print("  braking distance from 20 m/s: road %.6f m, snow %.6f m" % [distances[0], distances[1]])
	ok(distances[1] > distances[0] * 1.05, "snow grip loss measurably lengthens identical cold braking despite ploughing drag")

func _reward_roundtrip(runner: MissionRunner, garage: Garage) -> void:
	var loaded := CampaignStore.new()
	loaded.load_state()
	ok(loaded.owns_car("fd_1073"), "FD-12 grant auto-owns RS before TAKE and survives reload")
	garage.show_page(Garage.Page.MISSIONS)
	var take_row := -1
	for i in garage.page_rows().size():
		var row: Dictionary = garage.page_rows()[i]
		if row.kind == "reward" and row.id == "test_driver":
			take_row = i
			ok(row.enabled and row.label.contains("OWNED — TAKE"), "entitled garage offers owned RS TAKE")
	ok(take_row >= 0, "RS reward listed")
	if take_row >= 0:
		garage.activate_row(take_row)
	ok(WorldStore.load_driver(WorldStore.active_path()).active_car == "fd_1073", "garage TAKE persists active RS without a voucher")
	garage.show_page(Garage.Page.CAR)
	ok(garage.page_text().contains("OWNED  " + CampaignStore.REWARDS.test_driver) and garage.page_text().contains("SELECTED"), "CAR page identifies owned and selected promotion RS")
	var cars_path := test_path.get_base_dir().path_join("cars.json")
	ok(loaded.take_car("fd_1073", WorldStore.active_path(), cars_path, true), "reward TAKE creates isolated condition entry")
	ok(OdometerStore.load_odometer("fd_1073", cars_path) == 0 and OdometerStore.load_fuel("fd_1073", 85, cars_path).fuel_l == 85, "new RS has zero distance and its own full 85 L tank")
	OdometerStore.save_car("fd_1073", 1234, 42, cars_path)
	var before := FileAccess.get_file_as_string(cars_path)
	ok(loaded.take_car("fd_1073", WorldStore.active_path(), cars_path, true) and FileAccess.get_file_as_string(cars_path) == before, "repeated TAKE cannot reset condition")
	var campaign_bytes := FileAccess.get_file_as_string(test_path)
	loaded.load_state()
	ok(loaded.owns_car("fd_1073") and FileAccess.get_file_as_string(test_path) == campaign_bytes, "reward ownership reload never rewrites campaign")
	ok(not loaded.owns_car("fd_1001"), "reward grant does not manufacture other ownership")

func _visible_flag(runner: MissionRunner, target: int) -> bool:
	var visible: Array[String] = []
	for prop: Node3D in runner.get_children():
		if prop.visible:
			visible.append(prop.name)
	return visible == ["Flag_0_%d" % target] if target > 0 else visible.is_empty()

func _flag_mechanics(runner: MissionRunner, id := "FD-09") -> void:
	ok(runner.start(id), "flag rally starts for reveal checks")
	runner.set_physics_process(false)
	var mission: Dictionary = runner.active.duplicate(true)
	var cones: Array = mission.episode[0].cones
	ok(cones.size() == 12 and runner.get_child_count() == 12, "one mission-owned prop per flag cone")
	var visual_only := true
	for prop: Node3D in runner.get_children():
		visual_only = visual_only and prop.get_child_count() == 3
		for child: Node in prop.get_children():
			visual_only = visual_only and child is MeshInstance3D
	ok(visual_only, "flag cone, pole and cloth meshes have no collision nodes")
	ok(_visible_flag(runner, 1) and runner.hud._mission_banner_detail.text.contains("Flag 1/12"), "first prop and HUD target revealed at start")
	var third := _point(cones[2])
	runner._previous = third + Vector3(0, 5, 0)
	runner.tick(0.1, third)
	ok(runner.step_index == 0 and runner.last_result.is_empty() and runner.flag_progress().current == 1 and _visible_flag(runner, 1), "touching cone 3 before cone 1 leaves reveal and result unchanged")
	for i in cones.size():
		var point := _point(cones[i])
		runner._previous = point + Vector3(0, 5, 0)
		runner.tick(0.1, point - Vector3(0, 5, 0))
		if i == 0:
			runner._previous = point + Vector3(0, 5, 0)
			runner.tick(0.1, point)
			ok(runner.flag_progress().current == 2 and runner.step_index == 0, "a knocked target cannot score again")
		if i < cones.size() - 1:
			ok(runner.step_index == 0 and runner.flag_progress().current == i + 2 and runner.flag_progress().position == cones[i + 1] and _visible_flag(runner, i + 2) and runner.hud._mission_banner_detail.text.contains("Flag %d/12" % (i + 2)), "swept knock %d reveals only its successor in props and HUD" % (i + 1))
	ok(runner.step_index == 1 and runner.last_result.is_empty() and runner.flag_progress().is_empty() and _visible_flag(runner, 0), "twelfth knock advances to finish and hides all props")
	var finish := _point(mission.episode[-1].position)
	runner._previous = finish + Vector3(0, 10, 0)
	runner.tick(0.1, finish)
	ok(runner.last_result.get("passed", false) and runner.get_child_count() == 0 and not runner.is_physics_processing(), "flag finish frees all props synchronously")
	runner.start(id)
	var before := FileAccess.get_file_as_string(test_path)
	runner.abort()
	ok(runner.get_child_count() == 0 and not runner.is_physics_processing() and runner.flag_progress().is_empty() and runner.progress_text().is_empty() and FileAccess.get_file_as_string(test_path) == before, "flag abort frees props, clears progress and writes nothing")
	runner.start(id)
	runner.set_physics_process(false)
	runner.tick(mission.scoring.time_limit_s + 1, Vector3(200, 0.7, 100))
	ok(runner.last_result.get("reason") == "time limit" and not runner.last_result.get("passed", true) and runner.get_child_count() == 0, "missing flags times out and frees props")
	# Reverse spatial order within one sweep must not retroactively count flag 2.
	var original: Dictionary = runner.catalog[id]
	var small := original.duplicate(true)
	small.scoring.failure_conditions = ["skipped_gate"]
	small.episode[0].cones = [[0, 0.7, -20], [0, 0.7, -10], [0, 0.7, -30]]
	runner.catalog[id] = small
	runner.start(id)
	runner.set_physics_process(false)
	runner._previous = Vector3(0, 0.7, 0)
	runner.tick(0.1, Vector3(0, 0.7, -40))
	ok(runner.step_index == 0 and runner.flag_progress().current == 2 and runner.last_result.is_empty(), "sweep ignores target passed before it was revealed")
	runner.abort()
	small.episode[0].cones = [[0, 0.7, -10], [0, 0.7, -20], [0, 0.7, -30]]
	runner.start(id)
	runner.set_physics_process(false)
	runner._previous = Vector3(0, 0.7, 0)
	runner.tick(0.1, Vector3(0, 0.7, -40))
	ok(runner.step_index == 1 and runner.last_result.is_empty(), "several sequential flag contacts in one sweep advance in spatial order")
	runner.abort()
	runner.catalog[id] = original

func _double_circuit(runner: MissionRunner) -> void:
	runner.start("FD-10")
	runner.set_physics_process(false)
	var steps: Array = runner.active.episode
	for i in 5:
		var point := _point(steps[i].position)
		runner._previous = point + Vector3(0, 5, 0)
		runner.tick(0.1, point)
	ok(runner.step_index == 5 and runner.last_result.is_empty(), "FD-10 requires another circuit after the first west crossing")
	var cone := _point(steps[0].cones[0])
	runner._previous = cone + Vector3(0, 5, 0)
	runner.tick(0.1, cone)
	ok(runner.last_result.get("reason") == "cone hit", "FD-10 circle cones still fail on the second circuit")
	runner.start("FD-10")
	runner.set_physics_process(false)
	runner.step_index = steps.size() - 1
	runner._previous = cone
	runner.tick(0.1, _point(steps[-1].position))
	ok(not runner.last_result.get("passed", true) and runner.last_result.get("reason") == "cone hit", "FD-10 cone contact takes precedence on the finish tick")

func _ml5_configs(runner: MissionRunner, car: ArcadeCar, garage: Garage) -> void:
	var limits := [153, 69, 187, 39, 90, 39, 120, 385, 43, 120]
	for n in range(13, 23):
		var id := "FD-%02d" % n
		var m: Dictionary = runner.catalog[id]
		ok(m.rank == "test_driver" and m.unlock.required_rank == "test_driver" and m.environment == "pad", id + " rank and venue pinned")
		ok(m.scoring.time_limit_s == limits[n - 13], id + " source or documented authored limit pinned")
		var prerequisites: Array = []
		for previous in range(13, 22) if n == 22 else [n - 1]:
			prerequisites.append("FD-%02d" % previous)
		ok(m.unlock.required_missions == prerequisites, id + " exact prerequisite list pinned")
		var bands: Dictionary = m.scoring.medal_times
		var measured: float = m.provenance.medals.scripted_time_s
		ok(measured > 0 and bands.gold == ceil(measured * 1.05) and bands.silver == ceil(measured * 1.25) and bands.bronze == ceil(measured * 1.50), id + " medals derive from shipped-script measurement")
		var on_pad := true
		for step: Dictionary in m.episode:
			for point: Array in [step.position] + step.get("cones", []):
				on_pad = on_pad and point[1] == 0.7 and point[0] >= TestPad.GROUND_CORE_MIN.x and point[0] <= TestPad.GROUND_CORE_MAX.x and point[2] >= TestPad.GROUND_CORE_MIN.y and point[2] <= TestPad.GROUND_CORE_MAX.y
		ok(on_pad, id + " all targets lie on pad")
	var promotion: Dictionary = runner.catalog["FD-22"]
	for n in range(13, 22):
		var id := "FD-%02d" % n
		var result: Dictionary = runner.campaign.state.results[id]
		runner.campaign.state.results.erase(id)
		ok(runner.campaign.unlock_reason(promotion) == "Complete " + id and not runner.start("FD-22"), "promotion requires " + id + " independently")
		runner.campaign.state.results[id] = result
	ok(not runner.campaign.owns_car("boxster_986") and not runner.campaign.take_car("boxster_986", WorldStore.active_path()), "before Chief, Boxster reward is neither owned nor takeable")
	garage.show_page(Garage.Page.MISSIONS)
	for row: Dictionary in garage.page_rows():
		if row.kind == "reward" and row.id == "chief":
			ok(not row.enabled and not row.label.contains("OWNED"), "Chief TAKE locked before promotion")
	var cold: Dictionary = runner.catalog["FD-14"]
	ok(cold.cold_tyres and cold.briefing.contains("packed snow") and cold.surface_override == snow_surface.duplicate(), "packed snow and cold setup opted in")
	for value in [null, 0, "true", [], {}]:
		var bad := cold.duplicate(true)
		bad.cold_tyres = value
		ok(not MissionSchema.validate(bad).is_empty(), "cold setup rejects non-boolean " + str(value))
	car.front_tyre_temp = 1.0
	car.rear_tyre_temp = 0.5
	ok(runner.start("FD-14") and car.front_tyre_temp == 0 and car.rear_tyre_temp == 0, "human cold mission resets both axles to ambient")
	ok(_surface_values(car) == [snow_surface.grip, snow_surface.grip, snow_surface.rolling_drag], "human snow start applies both axle grips and drag")
	runner.abort()
	ok(_surface_values(car) == [1.0, 1.0, 0.0], "snow abort restores original road inputs")
	car.front_surface_grip = 0.73
	car.rear_surface_grip = 0.64
	car.surface_rolling_decel = 0.8
	car.front_tyre_temp = 0.8
	car.rear_tyre_temp = 0.6
	ok(runner.start("FD-14", true) and car.front_tyre_temp == 0 and car.rear_tyre_temp == 0, "scripted cold retry also resets both axles")
	ok(_surface_values(car) == [snow_surface.grip, snow_surface.grip, snow_surface.rolling_drag], "scripted snow retry applies override")
	# Simulate a competing writer; the next runner tick must reclaim the inputs.
	car.front_surface_grip = 1.0
	car.rear_surface_grip = 1.0
	car.surface_rolling_decel = 0.0
	runner._physics_process(1.0 / 60.0)
	ok(_surface_values(car) == [snow_surface.grip, snow_surface.grip, snow_surface.rolling_drag], "snow reasserted before car physics after competing writer")
	runner.abort()
	ok(_surface_values(car) == [0.73, 0.64, 0.8], "snow retry restores captured non-default axle inputs")
	runner._cleanup()
	ok(_surface_values(car) == [0.73, 0.64, 0.8], "repeated cleanup without override leaves car untouched")
	car.front_surface_grip = 1.0
	car.rear_surface_grip = 1.0
	car.surface_rolling_decel = 0.0
	ok(runner.start("FD-05") and _surface_values(car) == [1.0, 1.0, 0.0], "mission without override leaves default surface inputs unchanged")
	car.front_surface_grip = 0.81
	car.rear_surface_grip = 0.72
	car.surface_rolling_decel = 0.9
	runner._physics_process(1.0 / 60.0)
	runner.abort()
	ok(_surface_values(car) == [0.81, 0.72, 0.9], "no-override tick and cleanup preserve external surface inputs")
	car.front_surface_grip = 1.0
	car.rear_surface_grip = 1.0
	car.surface_rolling_decel = 0.0
	ok(cold.provenance.medals.run == "Godot 4.7.2, headless fixed 60 Hz, tests/mission_ladder_test.gd, fresh pad Boxster, cold tyres on packed snow (grip 0.42, rolling_drag 1.5, bump 0.03 validated only), shipped input_script, 2026-09-29", "FD-14 snow measurement run provenance pinned")
	await _snow_tint(runner, car)
	car.front_tyre_temp = 0.8
	car.rear_tyre_temp = 0.6
	runner.start("FD-16")
	ok(car.front_tyre_temp == 0.8 and car.rear_tyre_temp == 0.6, "ordinary mission preserves existing tyre heat")
	runner.abort()
	var delivery: Array = runner.catalog["FD-15"].episode
	ok(delivery[0].type == "delivery_pickup" and delivery[3].type == "zone" and delivery[-2].type == "delivery_return" and _point(delivery[0].position).distance_to(_point(delivery[-2].position)) < 30, "Klaus delivery drops at warehouse and comes back to dispatch")
	ok(runner.catalog["FD-20"].episode[0].cones.size() == 12 and runner.catalog["FD-20"].episode != runner.catalog["FD-09"].episode, "second flag rally has twelve targets on a distinct course")
	var stunt: Dictionary = runner.catalog["FD-21"]
	ok(stunt.episode.size() == 13 and stunt.scoring.failure_conditions == ["cone_hit"], "stunt has five route gates plus eight compass crossings; overlapping gates wait their turn")
	runner.start("FD-21")
	runner.set_physics_process(false)
	for i in 6:
		var point := _point(stunt.episode[i].position)
		runner._previous = point + Vector3(0, 10, 0)
		runner.tick(0.1, point)
	ok(runner.step_index == 6 and runner.last_result.is_empty(), "stunt still needs connecting gates and second spin after first circuit")
	var cone := _point(stunt.episode[1].cones[1])
	runner._previous = cone + Vector3(0, 10, 0)
	runner.tick(0.1, cone)
	ok(runner.last_result.get("reason") == "cone hit", "stunt second spot is constrained after first spin")

func _chief_roundtrip(runner: MissionRunner, garage: Garage) -> void:
	var loaded := CampaignStore.new()
	loaded.load_state()
	ok(loaded.state.rank == "chief" and loaded.state.credentials.chief_licence and loaded.state.rewards.chief and loaded.owns_car("boxster_986"), "FD-22 atomically persists Chief credential and auto-owned Boxster")
	ok(loaded.owns_car("fd_1073") and not loaded.state.rewards.ace, "Chief retains RS and does not grant Ace")
	var boxster: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://configs/cars/boxster_986.json"))
	ok(CarConfigValidation.validate(boxster, "boxster_986").is_empty(), "Chief uses existing valid Boxster config")
	garage.show_page(Garage.Page.MISSIONS)
	var take_row := -1
	for i in garage.page_rows().size():
		var row: Dictionary = garage.page_rows()[i]
		if row.kind == "reward" and row.id == "chief":
			take_row = i
			ok(row.enabled and row.label.contains("OWNED — TAKE"), "MISSIONS offers owned Chief TAKE")
	ok(take_row >= 0, "Chief reward listed")
	if take_row >= 0:
		garage.activate_row(take_row)
	ok(WorldStore.load_driver(WorldStore.active_path()).active_car == "boxster_986", "Chief TAKE selects existing Boxster")
	garage.show_page(Garage.Page.CAR)
	ok(garage.page_text().contains("OWNED  " + CampaignStore.REWARDS.chief) and garage.page_text().contains("SELECTED  " + CampaignStore.REWARDS.chief), "CAR identifies Chief ownership and selection")
	var car_take := false
	for row: Dictionary in garage.page_rows():
		car_take = car_take or (row.kind == "take_reward" and row.id == "boxster_986" and row.enabled)
	ok(car_take, "CAR offers enabled Boxster TAKE row")
	var cars_path := test_path.get_base_dir().path_join("chief-cars.json")
	ok(loaded.take_car("boxster_986", WorldStore.active_path(), cars_path, true), "Chief TAKE creates isolated condition record")
	ok(OdometerStore.load_odometer("boxster_986", cars_path) == 0 and OdometerStore.load_fuel("boxster_986", boxster.fuel.tank_capacity_l, cars_path).fuel_l == boxster.fuel.tank_capacity_l, "Chief Boxster begins at zero distance with its own full tank")
	OdometerStore.save_car("boxster_986", 2468, 25, cars_path)
	var before := FileAccess.get_file_as_string(cars_path)
	ok(loaded.take_car("boxster_986", WorldStore.active_path(), cars_path, true) and FileAccess.get_file_as_string(cars_path) == before, "repeated Chief TAKE preserves condition")
	var campaign_bytes := FileAccess.get_file_as_string(test_path)
	loaded.load_state()
	ok(loaded.owns_car("boxster_986") and FileAccess.get_file_as_string(test_path) == campaign_bytes, "Chief reload derives ownership without rewriting save")
	ok(loaded.record_result(runner.catalog["FD-22"], 1, true) and loaded.state.rank == "chief" and not loaded.state.rewards.ace, "FD-22 replay cannot promote again")

func _ml6_configs(runner: MissionRunner, garage: Garage) -> void:
	for pair in [["FD-24", "FD-17"], ["FD-25", "FD-16"], ["FD-26", "FD-22"], ["FD-28", "FD-19"], ["FD-32", "FD-19"], ["FD-28", "FD-32"]]:
		var mission: Dictionary = runner.catalog[pair[0]]
		var other: Dictionary = runner.catalog[pair[1]]
		ok(mission.episode != other.episode, "%s episode distinct from %s" % pair)
		ok(mission.input_script != other.input_script, "%s shipped controls distinct from %s" % pair)
	var limits := [37, 210, 37, 50, 37, 120, 50, 220, 90, 150, 120]
	for n in range(23, 34):
		var id := "FD-%02d" % n
		var m: Dictionary = runner.catalog[id]
		ok(m.rank == "chief" and m.unlock.required_rank == "chief" and m.environment == "pad", id + " Chief rank and pad pinned")
		ok(m.scoring.time_limit_s == limits[n - 23], id + " source or disclosed authored limit pinned")
		var required: Array = []
		for previous in range(23, 33) if n == 33 else [n - 1]:
			required.append("FD-%02d" % previous)
		ok(m.unlock.required_missions == required, id + " exact prerequisites pinned")
		ok(m.provenance.source.contains(id) and not m.provenance.source_course.is_empty() and not m.provenance.source_car.is_empty() and m.provenance.adaptation.contains("Boxster") and m.briefing.contains("Boxster"), id + " source and stand-in provenance present")
		ok(m.provenance.source_time_limit_s == (null if n in [28, 31, 33] else limits[n - 23]), id + " absent source limit stays null")
		if n in [28, 31, 33]:
			ok(m.briefing.contains("authored adaptation limit") and m.provenance.adaptation.contains("E-6 traffic"), id + " authored solo clock disclosed")
		var measured: float = m.provenance.medals.scripted_time_s
		var bands: Dictionary = m.scoring.medal_times
		ok(measured > 0 and bands.gold == ceil(measured * 1.05) and bands.silver == ceil(measured * 1.25) and bands.bronze == ceil(measured * 1.50), id + " measured medal formula pinned")
		ok(m.provenance.medals.run == "Godot 4.7.2, headless fixed 60 Hz, tests/mission_ladder_test.gd, fresh pad car, shipped input_script, 2026-09-29", id + " measurement run provenance pinned")
		var on_pad := true
		for step: Dictionary in m.episode:
			for point: Array in [step.position] + step.get("cones", []):
				on_pad = on_pad and point[1] == 0.7 and point[0] >= TestPad.GROUND_CORE_MIN.x and point[0] <= TestPad.GROUND_CORE_MAX.x and point[2] >= TestPad.GROUND_CORE_MIN.y and point[2] <= TestPad.GROUND_CORE_MAX.y
		ok(on_pad, id + " every gate and cone lies on pad")
		for pair in [[bands.gold, "gold"], [bands.gold + 0.001, "silver"], [bands.silver, "silver"], [bands.silver + 0.001, "bronze"], [bands.bronze, "bronze"], [bands.bronze + 0.001, "complete" if bands.bronze < m.scoring.time_limit_s else ""], [m.scoring.time_limit_s, "complete" if bands.bronze < m.scoring.time_limit_s else "bronze"], [m.scoring.time_limit_s + 0.001, ""]]:
			ok(MissionSchema.medal(m.scoring, pair[0]) == pair[1], id + " medal boundary " + str(pair[0]))
	for n in range(23, 33):
		var id := "FD-%02d" % n
		var result: Dictionary = runner.campaign.state.results[id]
		runner.campaign.state.results.erase(id)
		ok(runner.campaign.unlock_reason(runner.catalog["FD-33"]) == "Complete " + id and not runner.start("FD-33"), "Ace promotion independently requires " + id)
		runner.campaign.state.results[id] = result
	ok(not runner.campaign.owns_car("fd_2000") and not runner.campaign.take_car("fd_2000", WorldStore.active_path()), "before Ace FD-2000 is neither owned nor takeable")
	garage.show_page(Garage.Page.MISSIONS)
	var locked := false
	for row: Dictionary in garage.page_rows():
		locked = locked or (row.kind == "reward" and row.id == "ace" and not row.enabled and not row.label.contains("OWNED"))
	ok(locked, "MISSIONS lists locked Ace TAKE before promotion")
	garage.show_page(Garage.Page.CAR)
	var premature_take := false
	for row: Dictionary in garage.page_rows():
		premature_take = premature_take or (row.kind == "take_reward" and row.id == "fd_2000")
	ok(not premature_take and not garage.page_text().contains("OWNED  " + CampaignStore.REWARDS.ace), "CAR offers no Ace ownership or TAKE before promotion")
	var spin: Dictionary = runner.catalog["FD-23"]
	ok(spin.episode.size() == 8 and spin.episode[1].type == "cone_slalom" and spin.scoring.failure_conditions == ["cone_hit"], "FD-23 approach, full compass circuit and exit preserve spin-route convention")
	var reverse: Dictionary = runner.catalog["FD-29"]
	ok(reverse.episode.size() == 10 and reverse.scoring.failure_conditions == ["cone_hit"] and reverse.briefing.contains("Manual transmission is not simulated") and reverse.briefing.contains("yaw"), "FD-29 overlapping route discloses unscored rotation and manual transmission")
	ok(reverse.episode[2].position[2] > reverse.episode[1].position[2] and reverse.episode[3].position[2] > reverse.episode[2].position[2], "FD-29 two return gates run back toward the start")
	var triple: Dictionary = runner.catalog["FD-30"]
	var three_laps: bool = triple.episode.size() == 14
	for lap in range(1, 3):
		for gate in range(4):
			three_laps = three_laps and triple.episode[1 + lap * 4 + gate].position == triple.episode[1 + gate].position
	ok(three_laps and not triple.get("cold_tyres", false), "FD-30 has three full repeated circuits and normal Monaco tyre setup")
	ok(runner.start("FD-30"), "three-lap circuit starts for lap-count proof")
	runner.set_physics_process(false)
	for i in triple.episode.size():
		var point := _point(triple.episode[i].position)
		runner._previous = point + Vector3(0, 10, 0)
		runner.tick(0.1, point)
		if i in [4, 8, 12]:
			ok(runner.step_index == i + 1 and runner.last_result.is_empty(), "FD-30 lap %d still requires remaining route or finish" % ((i / 4) as int))
	ok(runner.last_result.get("passed", false), "FD-30 finishes only after three circuits and finish gate")
	ok(runner.catalog["FD-31"].episode.size() == 6 and runner.catalog["FD-33"].episode.size() == 10, "race and Ace stand-ins require one and two circuits respectively")
	ok(runner.catalog["FD-32"].briefing.contains("fd_2000") and runner.catalog["FD-33"].provenance.unlock.contains("all ten"), "joy ride reward and terminal all-ten unlock disclosed")
	# was every catalog id -> the ladder's: the jobs (ECON-1) are in the
	# catalog and unlock nothing, FD-33 stays the ladder's last.
	var ids: Array = []
	for id: String in runner.catalog:
		if not runner.catalog[id].has("reward_credits"):
			ids.append(id)
	ids.sort()
	ok(ids == PRODUCTION_IDS and ids[-1] == "FD-33", "FD-33 is terminal with no later catalog mission")

func _ace_roundtrip(runner: MissionRunner, garage: Garage) -> void:
	var loaded := CampaignStore.new()
	loaded.load_state()
	ok(loaded.state.rank == "ace" and loaded.state.credentials.ace_licence and loaded.state.rewards.ace and loaded.owns_car("fd_2000"), "FD-33 atomically persists Ace credential and auto-owned FD-2000")
	ok(loaded.owns_car("fd_1073") and loaded.owns_car("boxster_986"), "Ace retains both earlier reward cars")
	var turbo: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://configs/cars/fd_2000.json"))
	ok(CarConfigValidation.validate(turbo, "fd_2000").is_empty(), "Ace config validates every field and exact mass ledger")
	ok(turbo.identity == {"name": "FD-2000", "car_id": "fd_2000"}, "Ace stand-in identity pinned")
	garage.show_page(Garage.Page.MISSIONS)
	var take_row := -1
	for i in garage.page_rows().size():
		var row: Dictionary = garage.page_rows()[i]
		if row.kind == "reward" and row.id == "ace":
			take_row = i
			ok(row.enabled and row.label.contains("OWNED — TAKE"), "MISSIONS offers owned Ace TAKE")
	ok(take_row >= 0, "Ace reward listed")
	if take_row >= 0:
		garage.activate_row(take_row)
	ok(WorldStore.load_driver(WorldStore.active_path()).active_car == "fd_2000", "Ace TAKE selects FD-2000 without a voucher")
	garage.show_page(Garage.Page.CAR)
	ok(garage.page_text().contains("OWNED  " + CampaignStore.REWARDS.ace) and garage.page_text().contains("SELECTED  " + CampaignStore.REWARDS.ace), "CAR identifies Ace ownership and selection")
	var car_take := -1
	for i in garage.page_rows().size():
		var row: Dictionary = garage.page_rows()[i]
		if row.kind == "take_reward" and row.id == "fd_2000" and row.enabled:
			car_take = i
	ok(car_take >= 0, "CAR offers enabled FD-2000 TAKE row")
	WorldStore.set_active_car("boxster_986", WorldStore.active_path())
	if car_take >= 0:
		garage.activate_row(car_take)
	ok(WorldStore.load_driver(WorldStore.active_path()).active_car == "fd_2000", "CAR TAKE callback selects Ace reward")
	ok(ArcadeCar.CAR_ID == "boxster_986" and ArcadeCar.CONFIG_PATH == "res://configs/cars/boxster_986.json", "Ace selection leaves live pad Boxster physics in place")
	var cars_path := test_path.get_base_dir().path_join("ace-cars.json")
	ok(loaded.take_car("fd_2000", WorldStore.active_path(), cars_path, true), "Ace TAKE creates isolated condition record")
	ok(OdometerStore.load_odometer("fd_2000", cars_path) == 0 and OdometerStore.load_fuel("fd_2000", turbo.fuel.tank_capacity_l, cars_path).fuel_l == turbo.fuel.tank_capacity_l, "FD-2000 begins at zero distance with its own full tank")
	# Compare after JSON numeric normalization (saved integers parse as floats).
	var expected := FirstCar.default_entry()
	expected.fuel_l = turbo.fuel.tank_capacity_l
	ok(OdometerStore._cars(OdometerStore._read(cars_path)).get("fd_2000") == JSON.parse_string(JSON.stringify(expected)), "isolated Ace condition includes default driver, battery, wear and licence")
	OdometerStore.save_car("fd_2000", 3690, 31, cars_path)
	var before := FileAccess.get_file_as_string(cars_path)
	ok(loaded.take_car("fd_2000", WorldStore.active_path(), cars_path, true) and FileAccess.get_file_as_string(cars_path) == before, "repeated Ace TAKE preserves condition")
	var campaign_bytes := FileAccess.get_file_as_string(test_path)
	loaded.load_state()
	ok(loaded.owns_car("fd_2000") and FileAccess.get_file_as_string(test_path) == campaign_bytes, "Ace reload derives ownership without rewriting save")
	var credentials: Dictionary = loaded.state.credentials.duplicate()
	var rewards: Dictionary = loaded.state.rewards.duplicate()
	ok(loaded.record_result(runner.catalog["FD-33"], 1, true) and loaded.state.rank == "ace" and loaded.state.credentials == credentials and loaded.state.rewards == rewards, "FD-33 replay cannot repromote beyond terminal Ace")
	ok(not loaded.owns_car("fd_1001"), "Ace grant does not manufacture voucher-car ownership")
