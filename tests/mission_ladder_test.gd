extends SceneTree
## ML-1/2 ladder proof; ML-3 delivery, extended slaloms and promotion car.
var failures := 0
var checks := 0
var changes := 0
var fixture: Dictionary
var test_path := ProjectSettings.globalize_path("res://build/ml3-test-%d/campaign.json" % OS.get_process_id())

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

func promoted(id: String, rank: String) -> Dictionary:
	var m := fixture.duplicate(true)
	m.id = id
	m.rank = rank
	m.unlock.required_rank = rank
	return m

func _run() -> void:
	OS.set_environment("FD_TELEMETRY", "0")
	fixture = JSON.parse_string(FileAccess.get_file_as_string("res://tests/ml1_proof.json"))
	_schema()
	var rs: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://configs/cars/fd_1073.json"))
	ok(CarConfigValidation.validate(rs, "fd_1073").is_empty(), "RS config validates every field and exact mass ledger")
	_store()
	await _episode()
	await _production()
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
	ok(runner != null and runner.catalog.size() == 8, "autoload discovers eight production missions")
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
	ok(Garage.PAGE_TITLES.size() == 6 and Garage.PAGE_TITLES[5] == "MISSIONS", "six-page pin")
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

const PRODUCTION_IDS := ["FD-01", "FD-02", "FD-03", "FD-04", "FD-05", "FD-06", "FD-07", "FD-12"]

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
	ok(runner.catalog.size() == 8, "production scan finds exactly eight missions")
	ok(MissionSchema.catalog_errors(runner.catalog.values()).is_empty(), "production catalog has no reference or schema errors")
	for id: String in PRODUCTION_IDS:
		ok(runner.catalog.has(id), id + " discovered")
		if not runner.catalog.has(id):
			return
		ok(MissionSchema.validate(runner.catalog[id]).is_empty(), id + " validates without errors")
	for id: String in ["FD-05", "FD-06", "FD-07"]:
		var m: Dictionary = runner.catalog[id]
		var bands: Dictionary = m.scoring.medal_times
		var source_limit: int = {"FD-05": 110, "FD-06": 50, "FD-07": 58}[id]
		ok(m.rank == "junior" and m.scoring.time_limit_s == source_limit, id + " preserves source rank and limit")
		ok(bands.gold < bands.silver and bands.silver < bands.bronze and bands.bronze < source_limit, id + " medal bands strictly precede source limit")
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
	ok(rows.size() == 8 and rows["FD-01"].enabled and rows["FD-01"].label == "FD-01 — Simple Slalom", "fresh Junior sees playable FD-01")
	for i in range(1, PRODUCTION_IDS.size()):
		var id: String = PRODUCTION_IDS[i]
		var reason: String = "Complete " + PRODUCTION_IDS[i - 1]
		ok(not rows[id].enabled and rows[id].hint.contains("Locked: " + reason) and runner.campaign.unlock_reason(runner.catalog[id]) == reason, id + " row shows exact prerequisite lock")
	garage._start_episode("FD-01")
	ok(runner.active.get("id") == "FD-01" and runner._driver == null, "garage starts the unlocked human mission without a scripted driver")
	runner.abort()
	for i in range(PRODUCTION_IDS.size() - 1):
		var id: String = PRODUCTION_IDS[i]
		var mission: Dictionary = runner.catalog[id]
		ok(runner.campaign.record_result(mission, 1, false) and runner.campaign.unlock_reason(runner.catalog[PRODUCTION_IDS[i + 1]]) == "Complete " + id, id + " failed attempt cannot unlock successor")
		ok(not runner.start(PRODUCTION_IDS[i + 1]), id + " successor cannot bypass lock via runner")
		ok(runner.campaign.record_result(mission, mission.scoring.medal_times.silver, true), id + " prerequisite result saved")
		rows = _mission_rows(garage)
		var next_id: String = PRODUCTION_IDS[i + 1]
		ok(rows[next_id].enabled and runner.campaign.unlock_reason(runner.catalog[next_id]) == "", next_id + " row unlocks after predecessor")
	# Real production geometry; position injection isolates failure/scoring from
	# vehicle pace. Band midpoints come from the config so later tuning is safe.
	for id: String in PRODUCTION_IDS:
		var mission: Dictionary = runner.catalog[id]
		ok(runner.start(id), id + " starts for failure injection")
		runner.set_physics_process(false)
		if id in ["FD-02", "FD-05"]:
			var gate := _point(mission.episode[2].position)
			runner._previous = gate + Vector3(10, 0, 0)
			runner.tick(0.1, gate)
			ok(runner.last_result.get("reason") == "skipped gate" and not runner.last_result.get("passed", true), id + " later gate fails out of order")
		else:
			var cone := _point(mission.episode[0].cones[0])
			runner._previous = cone + Vector3(2, 0, 0)
			runner.tick(0.1, cone - Vector3(2, 0, 0))
			ok(runner.last_result.get("reason") == "cone hit" and not runner.last_result.get("passed", true), id + " swept cone contact fails")
		ok(runner.start(id), id + " starts for timeout")
		runner.set_physics_process(false)
		runner.tick(mission.scoring.time_limit_s + 1.0, car.global_position)
		ok(runner.last_result.get("reason") == "time limit" and not runner.last_result.get("passed", true), id + " time limit fails")
		var bands: Dictionary = mission.scoring.medal_times
		var samples := {"gold": bands.gold / 2.0, "silver": (bands.gold + bands.silver) / 2.0, "bronze": (bands.silver + bands.bronze) / 2.0, "complete": (bands.bronze + mission.scoring.time_limit_s) / 2.0}
		for medal: String in samples:
			ok(runner.start(id), id + " starts for " + medal + " scoring")
			runner.set_physics_process(false)
			for step: Dictionary in mission.episode:
				var point := _point(step.position)
				# Each gate is crossed independently: these are timing tests,
				# not synthetic straight segments through the slalom cones.
				runner._previous = point + Vector3(0, step.radius + 1.0, 0)
				runner.tick(float(samples[medal]) / mission.episode.size(), point)
			ok(runner.last_result.get("passed", false) and runner.last_result.get("medal") == medal and is_equal_approx(runner.last_result.get("time_s", -1.0), samples[medal]), id + " injected elapsed awards " + medal)
		if id == "FD-12":
			_reward_roundtrip(runner, garage)
			ok(runner.campaign.state.rank == "test_driver" and runner.campaign.state.credentials.test_driver_licence and runner.campaign.state.rewards.test_driver, "production FD-12 grants Test Driver and RS 2.7 entitlement")
	scene.queue_free()
	await process_frame
	WorldStore.path_override = ""
	# Every shipped script runs on a newly loaded, otherwise untouched pad car.
	# Never assert a medal or fixed completion time for the measured drives.
	_fresh_campaign(runner)
	for id: String in PRODUCTION_IDS:
		scene = load("res://scenes/main.tscn").instantiate()
		root.add_child(scene)
		await process_frame
		car = scene.get_node("Car")
		runner.configure(car, scene.get_node("HUD"))
		ok(runner.start(id, true), id + " shipped scripted drive starts")
		for frame in 3600:
			await physics_frame
			if runner.active.is_empty():
				break
		ok(runner.active.is_empty() and runner.last_result.get("passed", false), id + " shipped script passes with the actual pad car")
		print("  " + runner.result_text())
		var loaded := CampaignStore.new()
		loaded.load_state()
		var result: Dictionary = loaded.state.results.get(id, {})
		ok(runner.last_result.get("saved", false) and result.get("medal", "") != "" and is_equal_approx(result.get("best_time_s", -1.0), runner.last_result.get("time_s", -2.0)), id + " scripted pass survives store reload")
		ok(not Input.is_action_pressed("accelerate") and not Input.is_action_pressed("steer_left") and not Input.is_action_pressed("steer_right"), id + " script releases its inputs")
		if id in ["FD-05", "FD-06", "FD-07"]:
			var shipped: Dictionary = runner.catalog[id].input_script
			runner.catalog[id].input_script = {"steps": [{"press": ["brake" if id == "FD-05" else "accelerate"]}]}
			ok(runner.start(id, true), id + " bad scripted drive starts")
			for frame in 7200:
				await physics_frame
				if runner.active.is_empty():
					break
			ok(runner.active.is_empty() and not runner.last_result.get("passed", true), id + " bad scripted drive fails on the actual pad car")
			runner.catalog[id].input_script = shipped
			loaded.load_state()
			ok(loaded.state.results[id].attempts == 2 and loaded.state.results[id].best_time_s == result.best_time_s, id + " failed drive persists attempt and preserves best")
		runner.abort()
		scene.queue_free()
		await process_frame
	var persisted := CampaignStore.new()
	persisted.load_state()
	ok(persisted.state.rank == "test_driver" and persisted.state.credentials.test_driver_licence and persisted.state.rewards.test_driver and persisted.owns_car("fd_1073"), "scripted promotion persists rank, licence and RS entitlement together")

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
