extends SceneTree
## ECON-1 proof: the credits ledger, jobs as paid missions, the job board.
## Run via tests/run_tests.sh, or:
##
##   godot --headless --path . --import
##   godot --headless --fixed-fps 60 --path . --script res://tests/credits_test.gd
##
## The store is pinned off (FD_TELEMETRY=0); every file is this process's
## own, under TMPDIR, never the driver's data folder (held at the end: the
## real credits.json is as it was). The pad carries the payment pins on a
## test-only paid fixture; the Ring carries the job board: one job driven
## to a real failure and one to a real pass through their shipped controls.
var failures := 0
var checks := 0
var heard: Array = []
var fixture: Dictionary
var test_dir := (OS.get_environment("TMPDIR") if not OS.get_environment("TMPDIR").is_empty() else "/tmp").path_join("factory-driver-credits-%d" % OS.get_process_id())
var ledger_path := test_dir.path_join("credits.json")
var campaign_path := test_dir.path_join("campaign.json")
var real_path := ""
var real_before := ""

const JOB_IDS := ["JOB-01", "JOB-02", "JOB-03", "JOB-04"]
## Pickup and delivery of each job, as focus.json ids.
const JOB_STATIONS := {"JOB-01": ["E2.4", "E2.2"], "JOB-02": ["E2.2", "E2.4"], "JOB-03": ["E2.2", "E2.3"], "JOB-04": ["E2.3", "E2.2"]}
const STATION_RADIUS_M := 30.0
const ROUTE_RADIUS_M := 20.0
## The job driven to a real pass and the one driven to a real failure.
const PASS_JOB := "JOB-01"
const FAIL_JOB := "JOB-02"
const FAIL_DEADLINE_S := 45.0
const RING_SCENE := "res://scenes/eifel_ring.tscn"

func _initialize() -> void:
	_run.call_deferred()

func ok(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
	print("  %s %s" % ["ok" if value else "FAIL", label])

func write_text(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()

func write_json(path: String, value: Variant) -> void:
	write_text(path, JSON.stringify(value))

func read_text(path: String) -> String:
	return FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""

func stamp(path: String) -> String:
	return "%d:%d" % [FileAccess.get_modified_time(path), read_text(path).length()] if FileAccess.file_exists(path) else "absent"

func files() -> PackedStringArray:
	return DirAccess.get_files_at(test_dir) if DirAccess.dir_exists_absolute(test_dir) else PackedStringArray()

func _run() -> void:
	OS.set_environment("FD_TELEMETRY", "0")
	fixture = JSON.parse_string(FileAccess.get_file_as_string("res://tests/ml1_proof.json"))
	real_path = DataDir.resolve(CreditsLedger.PATH)
	real_before = stamp(real_path)
	print("-- idle and gated")
	_idle()
	print("-- the ledger")
	_ledger()
	print("-- the schema")
	_schema()
	print("-- the job board's configs")
	_jobs()
	print("-- the runner pays")
	await _payment()
	print("-- the Ring: the board, a real pass, a real failure")
	await _ring()
	print("-- nothing of the driver's was touched")
	CreditsLedger.path_override = ""
	CampaignStore.path_override = ""
	ok(stamp(real_path) == real_before, "the driver's own credits.json is as it was before the test (override isolation)")
	for file in files():
		DirAccess.remove_absolute(test_dir.path_join(file))
	DirAccess.remove_absolute(test_dir)
	print("CREDITS TEST %s: %d checks" % ["PASSED" if failures == 0 else "FAILED", checks])
	quit(0 if failures == 0 else 1)

# =============================================================================
#  Idle and gated
# =============================================================================

func _idle() -> void:
	var runner := MissionRunner.of(self)
	ok(CreditsLedger.path_override == "" and CreditsLedger.active_path() == "", "telemetry zero gates the ledger: no path without an override")
	ok(runner != null and runner.credits is CreditsLedger and runner.credits.state == CreditsLedger.defaults() and runner.credits.problems.is_empty(), "the idle runner holds an unread ledger at its defaults")
	ok(runner.get_child_count() == 0 and not runner.is_physics_processing() and not runner.is_processing_input() and runner.active.is_empty(), "idle runner inert")
	var gated := CreditsLedger.new()
	gated.earned.connect(func(t: Dictionary): heard.append(t))
	gated.load_state()
	ok(gated.state == CreditsLedger.defaults() and gated.balance() == 0 and gated.transactions().is_empty(), "gated load reads nothing: the defaults")
	ok(gated.earn(95, "job:GATED").is_empty() and gated.balance() == 0 and heard.is_empty(), "gated earn returns {} and keeps nothing, in memory or as a signal")
	ok(stamp(real_path) == real_before and not DirAccess.dir_exists_absolute(test_dir), "a fresh runner and a gated ledger touch no file")
	ok(CreditsLedger.PATH == "user://credits.json" and CreditsLedger.VERSION == 1 and CreditsLedger.KINDS == ["earn"], "the store's name, version and the one kind written")
	ok(MissionRunner.JOBS_DIR == "res://configs/jobs" and MissionRunner.CATALOG_DIR == "res://configs/missions", "the runner scans the ladder and the job board")

# =============================================================================
#  The ledger
# =============================================================================

func _ledger() -> void:
	CreditsLedger.path_override = ledger_path
	ok(CreditsLedger.active_path() == ledger_path, "override enables isolated IO")
	var ledger := CreditsLedger.new()
	heard.clear()
	ledger.earned.connect(func(t: Dictionary): heard.append(t))
	ledger.load_state()
	ok(ledger.state == CreditsLedger.defaults() and ledger.problems.is_empty() and files().is_empty(), "missing file: the defaults, no problem, nothing written by the read")
	for bad in [0, -1, -95]:
		ok(ledger.earn(bad, "job:BAD").is_empty(), "earn refuses amount " + str(bad))
	for bad in ["", "   ", "\n\t"]:
		ok(ledger.earn(95, bad).is_empty(), "earn refuses an empty reason")
	for bad in [NAN, INF, -INF]:
		ok(ledger.earn(95, "job:BAD", bad).is_empty(), "earn refuses the time " + str(bad))
	ok(files().is_empty() and heard.is_empty() and ledger.balance() == 0, "refused earns write no file and emit nothing")
	var first := ledger.earn(95, "job:JOB-01")
	ok(first == {"seq": 1, "kind": "earn", "amount": 95, "reason": "job:JOB-01"}, "the first earn returns the transaction as written, without a time")
	ok(heard.size() == 1 and heard[0] == first, "earned fires once with the committed transaction")
	ok(FileAccess.file_exists(ledger_path) and not FileAccess.file_exists(ledger_path + ".tmp") and files() == PackedStringArray(["credits.json"]), "atomic write consumes its temporary file")
	var second := ledger.earn(50, "job:JOB-02", 12.5)
	ok(second == {"seq": 2, "kind": "earn", "amount": 50, "reason": "job:JOB-02", "at_s": 12.5}, "a time on the caller's tick clock is written when given")
	ok(ledger.earn(5, "tip", 0.0).get("at_s", -1.0) == 0.0 and ledger.balance() == 150 and heard.size() == 3, "zero is a time; the balance is the sum")
	var on_disk: Dictionary = JSON.parse_string(read_text(ledger_path))
	ok(on_disk.version == 1 and on_disk.balance == 150 and on_disk.transactions.size() == 3 and on_disk.keys().size() == 3, "the file holds version, balance and the log")
	var contiguous := true
	for i in on_disk.transactions.size():
		contiguous = contiguous and on_disk.transactions[i].seq == i + 1 and on_disk.transactions[i].kind == "earn"
	ok(contiguous, "seq is 1-based and contiguous on disk")
	var bytes := read_text(ledger_path)
	var loaded := CreditsLedger.new()
	loaded.load_state()
	ok(loaded.state == ledger.state and loaded.problems.is_empty() and loaded.balance() == 150, "round trip: earn, file, load")
	ok(loaded.state.transactions[0].amount is int and loaded.state.transactions[0].seq is int and loaded.state.balance is int and loaded.state.transactions[1].at_s is float, "amounts, places and the balance load as whole numbers, the time as seconds")
	ok(read_text(ledger_path) == bytes, "reads never rewrite")
	var copy := loaded.transactions()
	copy[0].amount = 1
	ok(loaded.state.transactions[0].amount == 95, "transactions() hands out a copy")
	var other := CreditsLedger.new()
	ok(other.earn(10, "job:JOB-03").seq == 4 and other.balance() == 160, "a second ledger joins the log as it stands on disk")

	# Balance derivation: the log is the ledger.
	write_json(ledger_path, {"version": 1, "balance": 999, "transactions": [{"seq": 1, "kind": "earn", "amount": 95, "reason": "job:JOB-01"}, {"seq": 2, "kind": "earn", "amount": 50, "reason": "job:JOB-02"}]})
	bytes = read_text(ledger_path)
	loaded.load_state()
	ok(loaded.balance() == 145 and loaded.problems.size() == 1 and loaded.problems[0].contains("balance 999") and loaded.problems[0].contains("145"), "a balance that is not the sum is reported and the sum adopted")
	ok(read_text(ledger_path) == bytes, "the repair is in memory: the read leaves the corrupt file as it is")
	ok(loaded.earn(5, "repair").seq == 3 and JSON.parse_string(read_text(ledger_path)).balance == 150, "the next earn writes the derived balance")
	write_json(ledger_path, {"version": 1, "transactions": [{"seq": 1, "kind": "earn", "amount": 20, "reason": "a"}]})
	loaded.load_state()
	ok(loaded.balance() == 20 and loaded.problems.is_empty(), "a missing balance is derived without complaint")
	for bad in [-5, 1.5, "20", null, [], true]:
		write_json(ledger_path, {"version": 1, "balance": bad, "transactions": [{"seq": 1, "kind": "earn", "amount": 20, "reason": "a"}]})
		loaded.load_state()
		ok(loaded.balance() == 20 and loaded.problems.size() == 1, "balance " + str(bad) + " is never trusted")

	# Entries that are none of the ledger's own are reported and left out.
	var good := {"seq": 1, "kind": "earn", "amount": 20, "reason": "a"}
	for bad in [null, 3, "earn", [], {}, {"seq": 2, "kind": "spend", "amount": 5, "reason": "b"}, {"seq": 2, "kind": "earn", "amount": 0, "reason": "b"}, {"seq": 2, "kind": "earn", "amount": -5, "reason": "b"}, {"seq": 2, "kind": "earn", "amount": 1.5, "reason": "b"}, {"seq": 2, "kind": "earn", "amount": "5", "reason": "b"}, {"seq": 2, "kind": "earn", "amount": 5}, {"seq": 2, "kind": "earn", "amount": 5, "reason": " "}, {"seq": 2, "kind": "earn", "amount": 5, "reason": 7}, {"seq": 2, "kind": "earn", "amount": 5, "reason": "b", "at_s": -1}, {"seq": 2, "kind": "earn", "amount": 5, "reason": "b", "at_s": "soon"}]:
		write_json(ledger_path, {"version": 1, "balance": 30, "transactions": [good, bad, {"seq": 3, "kind": "earn", "amount": 10, "reason": "c"}]})
		loaded.load_state()
		ok(loaded.balance() == 30 and loaded.state.transactions.size() == 2 and loaded.state.transactions[1].seq == 2 and loaded.state.transactions[1].reason == "c" and loaded.problems.size() == 2, "entry left out, the rest renumbered: " + str(bad))
	ok(CreditsLedger.transaction_problem({"kind": "spend", "amount": 5, "reason": "b"}) != "" and CreditsLedger.transaction_problem(good) == "", "spend is reserved: no entry of that kind is read yet")
	write_json(ledger_path, {"version": 1, "balance": 30, "transactions": [{"seq": 7, "kind": "earn", "amount": 20, "reason": "a", "note": "kept"}, {"kind": "earn", "amount": 10, "reason": "c"}]})
	loaded.load_state()
	ok(loaded.balance() == 30 and loaded.state.transactions[0].seq == 1 and loaded.state.transactions[1].seq == 2 and loaded.problems.size() == 2 and loaded.state.transactions[0].note == "kept", "seq is an entry's place: a wrong or a missing one is reported and derived, an extra field rides along")
	for bad in [{"a": 1}, "log", 3, null]:
		write_json(ledger_path, {"version": 1, "balance": 0, "transactions": bad})
		loaded.load_state()
		ok(loaded.state == CreditsLedger.defaults() and loaded.problems.size() == 1, "transactions that are no list read as an empty log: " + str(bad))

	# Versions.
	write_json(ledger_path, {"version": 2, "balance": 500, "transactions": [{"seq": 1, "kind": "earn", "amount": 500, "reason": "later build"}]})
	bytes = read_text(ledger_path)
	heard.clear()
	loaded.load_state()
	ok(loaded.state == CreditsLedger.defaults() and loaded.newer_file and loaded.problems.size() == 1, "a later version is never trusted: the defaults")
	ok(ledger.earn(95, "job:JOB-01").is_empty() and heard.is_empty() and read_text(ledger_path) == bytes and not FileAccess.file_exists(ledger_path + ".tmp"), "a later build's file is never written over: earn refuses, the bytes stay")
	for bad in [99, -1, 1.5, "1", [], true]:
		write_json(ledger_path, {"version": bad, "balance": 20, "transactions": [good]})
		loaded.load_state()
		ok(loaded.state == CreditsLedger.defaults() and not loaded.problems.is_empty(), "version " + str(bad) + " reads as the defaults")
	for legacy in [{"version": 0, "balance": 20, "transactions": [good]}, {"balance": 20, "transactions": [good]}]:
		write_json(ledger_path, legacy)
		bytes = read_text(ledger_path)
		loaded.load_state()
		ok(loaded.balance() == 20 and loaded.state.version == 1 and loaded.problems.is_empty() and not loaded.newer_file and read_text(ledger_path) == bytes, "version zero or none reads as version one, and the read does not write")
		ok(loaded.earn(5, "stamp").seq == 2 and JSON.parse_string(read_text(ledger_path)).version == 1 and JSON.parse_string(read_text(ledger_path)).balance == 25, "the first write stamps version one")
	for bad in ["[1, 2]", "\"text\"", "3", "null"]:
		write_text(ledger_path, bad)
		loaded.load_state()
		ok(loaded.state == CreditsLedger.defaults() and loaded.problems.size() == 1, "a file that is no object reads as the defaults: " + bad)
	write_text(ledger_path, "{broken")
	loaded.load_state()
	ok(loaded.state == CreditsLedger.defaults() and loaded.problems.size() == 1, "malformed JSON reads as the defaults")
	ok(loaded.earn(95, "fresh start").seq == 1 and JSON.parse_string(read_text(ledger_path)).balance == 95, "an untrustworthy file of this build's is replaced by the next committed earn")

	# A write that fails publishes nothing.
	var committed: Dictionary = loaded.state.duplicate(true)
	bytes = read_text(ledger_path)
	heard.clear()
	loaded.earned.connect(func(t: Dictionary): heard.append(t))
	CreditsLedger.path_override = test_dir
	ok(loaded.earn(95, "job:JOB-01").is_empty() and heard.is_empty(), "a rename that fails returns {} and emits nothing")
	DirAccess.remove_absolute(test_dir + ".tmp")
	CreditsLedger.path_override = ledger_path
	ok(read_text(ledger_path) == bytes and files() == PackedStringArray(["credits.json"]), "the failed write publishes nothing: the file is the last committed one")
	loaded.load_state()
	ok(loaded.state == committed, "and the ledger is where it was")
	ok(not DataDir.SEEDED_FILES.has("credits.json"), "known gap, documented: the data folder's seed does not carry credits.json yet (DataDir is outside ECON-1's surface)")
	DirAccess.remove_absolute(ledger_path)

# =============================================================================
#  The schema
# =============================================================================

func _schema() -> void:
	ok(MissionSchema.validate(fixture).is_empty() and not fixture.has("reward_credits") and not fixture.has("job_kind"), "a mission without either field is valid: not a paid mission")
	var job := fixture.duplicate(true)
	job.reward_credits = 95
	ok(MissionSchema.validate(job).is_empty(), "reward_credits alone is valid")
	job.job_kind = "courier"
	ok(MissionSchema.validate(job).is_empty(), "reward_credits with a job_kind is valid")
	for kind in ["testdrive", "scouting", "anything new"]:
		job.job_kind = kind
		ok(MissionSchema.validate(job).is_empty(), "the kind is free vocabulary: " + kind)
	job.reward_credits = 95.0
	ok(MissionSchema.validate(job).is_empty(), "a whole number read from JSON is a whole number")
	for bad in [0, -5, 1.5, 0.5, "95", true, null, [], {}, INF, -INF, NAN]:
		var m := fixture.duplicate(true)
		m.job_kind = "courier"
		m.reward_credits = bad
		ok(not MissionSchema.validate(m).is_empty(), "reward_credits refuses " + str(bad))
	for bad in ["", "  ", 3, null, [], {}, true]:
		var m := fixture.duplicate(true)
		m.reward_credits = 95
		m.job_kind = bad
		ok(not MissionSchema.validate(m).is_empty(), "job_kind refuses " + str(bad))
	var unpaid := fixture.duplicate(true)
	unpaid.job_kind = "courier"
	ok(not MissionSchema.validate(unpaid).is_empty(), "a job_kind without reward_credits is refused")
	var bad_entry := fixture.duplicate(true)
	bad_entry.reward_credits = 0
	ok(MissionSchema.catalog_errors([bad_entry]).has(fixture.id), "a bad reward keeps the entry out of the catalog")

# =============================================================================
#  The job board's configs
# =============================================================================

func _jobs() -> void:
	var runner := MissionRunner.of(self)
	runner.load_catalog()
	var stations := {}
	for station: Buildings.Record in Buildings.stations():
		stations[station.id] = station.position()
	var found: Array = []
	var ladder := 0
	for id: String in runner.catalog:
		if runner.catalog[id].has("reward_credits"):
			found.append(id)
		else:
			ladder += 1
	ok(found == JOB_IDS and ladder == 33, "the production scan finds the four jobs after the thirty-three ladder missions, the ladder unpaid")
	ok(MissionSchema.catalog_errors(runner.catalog.values()).is_empty(), "the whole catalog, jobs included, has no schema or reference error")
	var files_found := PackedStringArray()
	for file in DirAccess.get_files_at(MissionRunner.JOBS_DIR):
		if file.ends_with(".json"):
			files_found.append(file)
	ok(files_found.size() == JOB_IDS.size(), "configs/jobs holds one file per job")
	var pays: Array = []
	for id: String in JOB_IDS:
		if not runner.catalog.has(id):
			ok(false, id + " discovered")
			continue
		var job: Dictionary = runner.catalog[id]
		ok(MissionSchema.validate(job).is_empty(), id + " validates without errors")
		ok(job.rank == "junior" and job.unlock == {"required_rank": "junior", "required_missions": []} and job.environment == "ring" and job.job_kind == "courier", id + " is an open junior courier job on the Ring: no unlock chain")
		var steps: Array = job.episode
		var types: Array = []
		for step: Dictionary in steps:
			types.append(step.type)
		ok(types == ["delivery_pickup", "waypoint_gate", "waypoint_gate", "waypoint_gate", "delivery_return", "timed_finish"] and job.scoring.failure_conditions.is_empty(), id + " is pickup, three route gates, delivery, finish; a relaxed drive without failure conditions")
		var pickup: Vector2 = stations.get(JOB_STATIONS[id][0], Vector2.INF)
		var delivery: Vector2 = stations.get(JOB_STATIONS[id][1], Vector2.INF)
		ok(Vector2(steps[0].position[0], steps[0].position[2]).distance_to(pickup) < 0.001 and steps[0].radius == STATION_RADIUS_M and job.provenance.stations.pickup.id == JOB_STATIONS[id][0], id + " picks up at " + JOB_STATIONS[id][0] + "'s own position from the focus table")
		ok(Vector2(steps[4].position[0], steps[4].position[2]).distance_to(delivery) < 0.001 and steps[4].position == steps[5].position and steps[4].radius == STATION_RADIUS_M and steps[5].radius == STATION_RADIUS_M and job.provenance.stations.delivery.id == JOB_STATIONS[id][1], id + " delivers and finishes at " + JOB_STATIONS[id][1] + "'s own position")
		var inside := true
		for step: Dictionary in steps:
			inside = inside and step.position[0] > 0.0 and step.position[0] < 7000.0 and step.position[2] > -6000.0 and step.position[2] < 0.0 and step.position[1] > 300.0 and step.position[1] < 700.0
		ok(inside and steps[1].radius == ROUTE_RADIUS_M and steps[2].radius == ROUTE_RADIUS_M and steps[3].radius == ROUTE_RADIUS_M, id + " keeps every gate inside the drape's coverage at road height")
		var measured: float = job.provenance.medals.scripted_time_s
		var bands: Dictionary = job.scoring.medal_times
		ok(measured > 0 and bands.gold == ceil(measured * 1.05) and bands.silver == ceil(measured * 1.25) and bands.bronze == ceil(measured * 1.50), id + " bands derive from the recorded scripted measurement")
		ok(job.scoring.time_limit_s == ceil(measured * 2.0 / 60.0) * 60.0 and bands.bronze < job.scoring.time_limit_s and job.provenance.time_limit.seconds == job.scoring.time_limit_s, id + " allows twice the scripted time, to the minute: a relaxed limit above every band")
		var driven: float = job.provenance.route.driven_m
		ok(driven > 1000.0 and job.reward_credits == roundf((40.0 + 6.0 * driven / 1000.0) / 5.0) * 5.0 and job.provenance.pay.credits == job.reward_credits and job.reward_credits >= 80 and job.reward_credits <= 150, id + " pays by the driven distance inside the starter spread")
		ok(job.briefing.contains("%d credits" % int(job.reward_credits)) and job.briefing.contains(JOB_STATIONS[id][0]) and job.briefing.contains(JOB_STATIONS[id][1]) and job.briefing.contains("not simulated"), id + " briefing names its stations, its pay and what is not simulated")
		ok(job.input_script.steps.size() > 1000 and not job.input_script.has("hold_speed"), id + " ships its recorded trace")
		pays.append(int(job.reward_credits))
	ok(pays == [95, 100, 130, 150], "the board pays 95, 100, 130 and 150 credits")
	for pair in [["JOB-01", "JOB-02"], ["JOB-01", "JOB-03"], ["JOB-01", "JOB-04"], ["JOB-02", "JOB-03"], ["JOB-02", "JOB-04"], ["JOB-03", "JOB-04"]]:
		var a: Dictionary = runner.catalog[pair[0]]
		var b: Dictionary = runner.catalog[pair[1]]
		ok(a.episode != b.episode and a.input_script != b.input_script and a.title != b.title, pair[0] + " and " + pair[1] + " are different jobs: route and trace")

# =============================================================================
#  The runner pays
# =============================================================================

func _paid(id: String, reward: int) -> Dictionary:
	var m := fixture.duplicate(true)
	m.id = id
	m.title = "Paid proof"
	m.job_kind = "courier"
	m.reward_credits = reward
	return m

func _pass_by_ticks(runner: MissionRunner, mission: Dictionary) -> bool:
	if not runner.start(mission.id):
		return false
	for step: Dictionary in mission.episode:
		runner.tick(1, Vector3(step.position[0], step.position[1], step.position[2]))
	return runner.active.is_empty()

func _payment() -> void:
	var runner := MissionRunner.of(self)
	CreditsLedger.path_override = ledger_path
	CampaignStore.path_override = campaign_path
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	var car: ArcadeCar = scene.get_node("Car")
	var garage: Garage = scene.get_node("Garage")
	runner.campaign.load_state()
	runner.campaign.reconcile(LicenceExams.LICENCE_L1)
	runner.configure(car, scene.get_node("HUD"))
	var job := _paid("PAID-PROOF", 95)
	var plain := fixture.duplicate(true)
	runner.catalog[job.id] = job
	runner.catalog[plain.id] = plain
	var ledger := CreditsLedger.new()
	var results: Array = []
	var listener := func(result: Dictionary): results.append(result)
	runner.episode_finished.connect(listener)
	heard.clear()
	var hear := func(t: Dictionary): heard.append(t)
	runner.credits.earned.connect(hear)

	# A mission without the field never reaches the ledger.
	ok(_pass_by_ticks(runner, plain) and runner.last_result.passed and not runner.last_result.has("credits"), "an unpaid mission passes without a credits field in its result")
	ok(not FileAccess.file_exists(ledger_path) and heard.is_empty() and not runner.result_text().contains("paid"), "and writes no ledger: inert when the field is absent")

	# Failed and aborted jobs pay nothing.
	runner.start(job.id)
	runner._previous = Vector3(10, 0.7, -18)
	runner.tick(1, Vector3(0, 0.7, -18))
	ok(not runner.last_result.passed and runner.last_result.reason == "skipped gate" and runner.last_result.credits == 0, "a failed job reports zero credits")
	ok(runner.pay_last_result() == 0 and not FileAccess.file_exists(ledger_path), "a failed job pays nothing, asked again or not")
	runner.start(job.id)
	runner.tick(21, Vector3(0, 0.7, 0))
	ok(runner.last_result.reason == "time limit" and runner.last_result.credits == 0 and not FileAccess.file_exists(ledger_path), "a job that runs out of time pays nothing")
	runner.start(job.id)
	runner.tick(1, Vector3(0, 0.7, -4))
	runner.abort()
	ok(runner.last_result.is_empty() and runner.pay_last_result() == 0 and not FileAccess.file_exists(ledger_path) and heard.is_empty(), "an aborted job pays nothing: zero transactions so far")

	# A pass pays once.
	results.clear()
	ok(_pass_by_ticks(runner, job) and runner.last_result.passed and runner.last_result.credits == 95 and runner.last_result.saved, "a passed job pays its reward")
	ledger.load_state()
	ok(ledger.balance() == 95 and ledger.transactions() == [{"seq": 1, "kind": "earn", "amount": 95, "reason": "job:PAID-PROOF"}], "one transaction on disk: the reward, reasoned job:<id>, no wall clock")
	ok(heard.size() == 1 and results.size() == 1 and results[0].credits == 95 and runner.result_text().contains("paid 95 credits"), "one earned signal, one finished episode, the pay in the result text")
	ok(runner.active.is_empty() and not runner.is_physics_processing() and runner.get_child_count() == 0, "finish returns to inert")

	# No double credit: every retry of the payment is refused.
	var bytes := read_text(ledger_path)
	runner.finish(true, "course complete")
	runner.finish(true, "again")
	ok(runner.pay_last_result() == 0 and runner.pay_last_result() == 0, "the payment asked for again pays nothing")
	var delivered: Dictionary = runner.last_result.duplicate(true)
	runner.episode_finished.emit(delivered)
	runner.episode_finished.emit(delivered)
	ok(results.size() == 3 and read_text(ledger_path) == bytes and heard.size() == 1, "the same result delivered twice more, a second and third finish(): the ledger's bytes are the same")
	var greedy := func(_result: Dictionary): runner.pay_last_result()
	runner.episode_finished.connect(greedy)
	ok(_pass_by_ticks(runner, job) and runner.last_result.credits == 95, "passing the job again is new work")
	ledger.load_state()
	ok(ledger.balance() == 190 and ledger.state.transactions.size() == 2 and ledger.state.transactions[1] == {"seq": 2, "kind": "earn", "amount": 95, "reason": "job:PAID-PROOF"} and heard.size() == 2, "and new pay, once: a listener that asks for the payment inside the signal gets nothing")
	runner.episode_finished.disconnect(greedy)
	ok(runner.campaign.state.results[job.id].attempts == 4 and runner.campaign.state.results[job.id].medal == "gold", "the campaign counts the job's attempts and keeps its medal beside the ladder's")

	# The pay does not wait on the campaign record.
	CampaignStore.path_override = test_dir
	ok(_pass_by_ticks(runner, job) and not runner.last_result.saved and runner.last_result.credits == 95, "a result that could not be saved is still paid")
	DirAccess.remove_absolute(test_dir + ".tmp")
	CampaignStore.path_override = campaign_path
	ledger.load_state()
	ok(ledger.balance() == 285 and runner.result_text().contains("(save failed)") and runner.result_text().contains("paid 95 credits"), "the ledger holds three payments; the text says both")

	# A payment the ledger refused is not remembered as paid.
	bytes = read_text(ledger_path)
	CreditsLedger.path_override = test_dir
	ok(_pass_by_ticks(runner, job) and runner.last_result.passed and runner.last_result.credits == 0, "a ledger write that fails pays nothing")
	DirAccess.remove_absolute(test_dir + ".tmp")
	CreditsLedger.path_override = ledger_path
	ok(read_text(ledger_path) == bytes, "and publishes nothing")
	ok(runner.pay_last_result() == 95 and runner.pay_last_result() == 0, "the retry commits it, once")
	ledger.load_state()
	ok(ledger.balance() == 380 and ledger.state.transactions.size() == 4, "four payments, none doubled")

	# Gated, a pass pays nothing and writes nothing.
	bytes = read_text(ledger_path)
	CreditsLedger.path_override = ""
	ok(_pass_by_ticks(runner, job) and runner.last_result.passed and runner.last_result.credits == 0 and read_text(ledger_path) == bytes and stamp(real_path) == real_before, "gated, a passed job pays nothing anywhere")
	CreditsLedger.path_override = ledger_path

	# The pad car, the fixture's own scripted driver.
	ok(runner.start(job.id, true), "the paid fixture starts scripted on the pad car")
	for i in 1300:
		await physics_frame
		if runner.active.is_empty():
			break
	ledger.load_state()
	ok(runner.last_result.get("passed", false) and runner.last_result.credits == 95 and ledger.balance() == 475, "a real pad drive to a pass pays")

	# The JOBS page on the pad.
	garage.show_page(Garage.Page.JOBS)
	var rows := garage.page_rows()
	var row: Dictionary = {}
	for candidate: Dictionary in rows:
		if candidate.id == job.id:
			row = candidate
	ok(garage.page_text().contains("JOB BOARD") and garage.page_text().contains("CREDITS: 475") and garage.page_text().contains("Payments received: 5") and garage.page_text().contains("+95 job:PAID-PROOF"), "the JOBS page shows the credits held and the last payment")
	ok(not row.is_empty() and row.kind == "job" and row.enabled and row.label == "DONE — PAID-PROOF — Paid proof  —  courier  —  95 credits" and row.hint.contains(job.briefing) and row.hint.contains("Enter to start — pad") and row.hint.contains("gold"), "a job row: done mark, id, title, kind, pay; the briefing and the best in its hint")
	var listed_plain := false
	for candidate: Dictionary in rows:
		listed_plain = listed_plain or candidate.id == plain.id or candidate.kind != "job"
	ok(not listed_plain and rows.size() == JOB_IDS.size() + 1, "the page lists the jobs alone: the four ring jobs and the paid fixture")
	garage.show_page(Garage.Page.MISSIONS)
	var on_ladder := false
	for candidate: Dictionary in garage.page_rows():
		on_ladder = on_ladder or candidate.id == job.id
	ok(not on_ladder, "the MISSIONS page does not list a paid job")
	garage.show_page(Garage.Page.JOBS)
	var index := garage.page_rows().find_custom(func(r: Dictionary): return r.id == job.id)
	ok(garage.activate_row(index) and runner.active.get("id") == job.id and runner._driver == null, "the row starts the job through the runner, without a scripted driver")
	runner.abort()
	runner.catalog.clear()
	garage.show_page(Garage.Page.JOBS)
	ok(garage.page_text().contains("No jobs posted.") and garage.page_rows().is_empty(), "an empty board says so")
	runner.episode_finished.disconnect(listener)
	runner.credits.earned.disconnect(hear)
	runner.load_catalog()
	scene.queue_free()
	await process_frame
	DirAccess.remove_absolute(ledger_path)
	DirAccess.remove_absolute(campaign_path)

# =============================================================================
#  The Ring
# =============================================================================

func _ring() -> void:
	var runner := MissionRunner.of(self)
	CreditsLedger.path_override = ledger_path
	CampaignStore.path_override = campaign_path
	var packed: PackedScene = load(RING_SCENE)
	await physics_frame
	var scene := packed.instantiate()
	root.add_child(scene)
	for i in 20:
		await physics_frame
	var car: ArcadeCar = scene.get_node("Car")
	var garage: Garage = scene.get_node("Garage")
	var ledger := CreditsLedger.new()
	runner.configure(car, scene.get_node("HUD"))
	ok(car.road_profile is WorldRoadProfile and runner.environment_matches("ring") and not runner.environment_matches("pad"), "the Ring's car stands on a world profile: the ring is the jobs' environment")

	# Not enrolled: the board is listed and locked.
	runner.campaign.state = CampaignStore.defaults()
	garage.show_page(Garage.Page.JOBS)
	var rows := garage.page_rows()
	var locked := rows.size() == JOB_IDS.size()
	for i in mini(rows.size(), JOB_IDS.size()):
		locked = locked and rows[i].id == JOB_IDS[i] and not rows[i].enabled and rows[i].hint.contains("Locked: Requires junior")
	ok(locked and not runner.start(PASS_JOB) and garage.page_text().contains("CREDITS: 0"), "a driver who is not enrolled sees the four jobs locked and cannot start one")

	# Enrolled: every job is open, no chain.
	runner.campaign.reconcile(LicenceExams.LICENCE_L1)
	garage.show_page(Garage.Page.JOBS)
	rows = garage.page_rows()
	var open := rows.size() == JOB_IDS.size()
	for i in mini(rows.size(), JOB_IDS.size()):
		var job: Dictionary = runner.catalog[JOB_IDS[i]]
		open = open and rows[i].kind == "job" and rows[i].id == JOB_IDS[i] and rows[i].enabled and rows[i].label == "%s — %s  —  courier  —  %d credits" % [JOB_IDS[i], job.title, int(job.reward_credits)] and rows[i].hint.contains("Enter to start — ring") and rows[i].hint.contains(job.briefing)
	ok(open, "an enrolled junior sees the four jobs open on the Ring: id, title, kind, pay, none marked done")
	garage.show_page(Garage.Page.MISSIONS)
	var ladder_rows := 0
	var ladder_open := 0
	for row: Dictionary in garage.page_rows():
		if row.kind == "mission":
			ladder_rows += 1
			ladder_open += 1 if row.enabled else 0
	ok(ladder_rows == 33 and ladder_open == 0, "the ladder's page on the Ring: thirty-three pad missions, none startable here, no job among them")

	# A real pass: the shipped job, the shipped controls, the pay. First, on
	# the fresh car: the recorded trace is open-loop, the car it was
	# recorded on had cold tyres and a full tank.
	ok(not FileAccess.file_exists(ledger_path), "no ledger file before the first job is delivered")
	var job: Dictionary = runner.catalog[PASS_JOB]
	var odometer_before := car.odometer_m
	ok(runner.start(PASS_JOB, true), PASS_JOB + " starts scripted on the Ring car")
	var airborne := 0
	for frame in range(int(job.scoring.time_limit_s * 60) + 120):
		await physics_frame
		if car.is_airborne:
			airborne += 1
		if runner.active.is_empty():
			break
	var result: Dictionary = runner.last_result
	ok(result.get("passed", false) and result.get("reason") == "course complete" and result.get("medal") == "gold", PASS_JOB + " shipped controls drive the actual Ring car to a pass")
	var measured: float = result.get("time_s", 0.0)
	var bands: Dictionary = job.scoring.medal_times
	ok(absf(measured - job.provenance.medals.scripted_time_s) < 0.000001, PASS_JOB + " measurement matches recorded provenance")
	ok(measured > 0 and measured <= job.scoring.time_limit_s and bands.gold == ceil(measured * 1.05) and bands.silver == ceil(measured * 1.25) and bands.bronze == ceil(measured * 1.50), PASS_JOB + " medal bands derive from this real pass inside the limit")
	ok(absf((car.odometer_m - odometer_before) - job.provenance.route.driven_m) < 0.1 and airborne == 0, PASS_JOB + " drove its recorded distance with a wheel on the road every tick")
	ok(car.global_position.distance_to(Vector3(job.episode[5].position[0], job.episode[5].position[1], job.episode[5].position[2])) <= STATION_RADIUS_M + 1.0, PASS_JOB + " ends at the delivery station's gate")
	ok(result.get("credits") == int(job.reward_credits) and result.get("saved", false), "the pass pays the job's reward")
	ledger.load_state()
	ok(ledger.balance() == int(job.reward_credits) and ledger.transactions() == [{"seq": 1, "kind": "earn", "amount": int(job.reward_credits), "reason": "job:" + PASS_JOB}] and ledger.problems.is_empty(), "the credits land: one transaction on disk")
	ok(runner.pay_last_result() == 0 and ledger.transactions().size() == 1 and read_text(ledger_path).count("\"seq\"") == 1, "and cannot be collected twice")
	ok(not Input.is_action_pressed("accelerate") and not Input.is_action_pressed("brake") and runner.get_child_count() == 0 and not runner.is_physics_processing(), "inputs released, the runner inert again")

	# A real failure: the shipped controls, a deadline the route cannot meet.
	# After the pass, on the same car (warm tyres, less fuel): the deadline
	# fails it whatever line the controls now drive.
	var paid_bytes := read_text(ledger_path)
	var spawn_origin := car.get_spawn_transform().origin
	var shipped_scoring: Dictionary = runner.catalog[FAIL_JOB].scoring
	runner.catalog[FAIL_JOB].scoring = {"time_limit_s": FAIL_DEADLINE_S, "medal_times": {"gold": FAIL_DEADLINE_S * 0.25, "silver": FAIL_DEADLINE_S * 0.5, "bronze": FAIL_DEADLINE_S * 0.75}, "failure_conditions": []}
	ok(runner.start(FAIL_JOB, true), FAIL_JOB + " starts scripted on the Ring car")
	ok(not garage.can_open() and runner.is_physics_processing(), "the job owns the driving context")
	for frame in range(int(FAIL_DEADLINE_S * 60) + 120):
		await physics_frame
		if runner.active.is_empty():
			break
	ok(runner.active.is_empty() and not runner.last_result.get("passed", true) and runner.last_result.get("reason") == "time limit" and runner.last_result.credits == 0, FAIL_JOB + " fails on the actual Ring car: the deadline passes")
	ok(car.global_position.distance_to(spawn_origin) > 100.0, FAIL_JOB + " shipped controls drove the car away from the pit before the deadline")
	ok(read_text(ledger_path) == paid_bytes and runner.pay_last_result() == 0 and read_text(ledger_path) == paid_bytes, "the failed job pays nothing: the ledger's bytes are the same, asked again or not")
	ok(not Input.is_action_pressed("accelerate") and not Input.is_action_pressed("brake") and not Input.is_action_pressed("steer_left") and not Input.is_action_pressed("steer_right"), "script inputs released after the failure")
	runner.catalog[FAIL_JOB].scoring = shipped_scoring
	ok(runner.campaign.state.results[FAIL_JOB].attempts == 1 and runner.campaign.state.results[FAIL_JOB].medal == "", "the failed attempt is counted and completes nothing")

	# The board afterwards.
	garage.show_page(Garage.Page.JOBS)
	rows = garage.page_rows()
	ok(garage.page_text().contains("CREDITS: %d" % int(job.reward_credits)) and garage.page_text().contains("Payments received: 1") and garage.page_text().contains("job:" + PASS_JOB), "the board shows the credits earned")
	ok(rows[0].id == PASS_JOB and rows[0].label.begins_with("DONE — " + PASS_JOB) and rows[0].hint.contains("gold") and rows[0].hint.contains("1 attempts") and rows[0].enabled, "the delivered job is marked done and can be driven again")
	ok(rows[1].id == FAIL_JOB and not rows[1].label.begins_with("DONE") and rows[1].hint.contains("not yet delivered") and rows[1].hint.contains("1 attempts") and rows[1].enabled, "the failed job is not")
	var persisted := CampaignStore.new()
	persisted.load_state()
	ok(persisted.state.rank == "junior" and persisted.state.results[PASS_JOB].medal == "gold" and persisted.state.results[FAIL_JOB].medal == "" and not persisted.state.rewards.test_driver, "the campaign keeps both results; a job promotes nobody")
	ok(files() == PackedStringArray(["campaign.json", "credits.json"]), "the test's folder holds the two stores it opted into, no temporary file")
	root.remove_child(scene)
	scene.free()
	await physics_frame
