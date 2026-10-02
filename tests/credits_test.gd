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
## TROC-1 slice 2: a job's pay is the poster's obligation to the player
## (ObligationsLedger, a file of this test's own beside the credits one),
## no longer credits: the payment pins moved to the obligation, each saying
## what it was; the credits ledger stays under test for the dealership and
## paid fuel, which stake their own credits here.
## TROC-1 slice 3: the dealership trades by barter. The table's pins gain
## the desk and its exchange-terms, the CAR page's pins moved to the BARTER
## shape (each saying what it was), and the credits BUY path is DORMANT
## (Garage.CREDITS_BUY_ENABLED false): buy_car is intact and still driven
## here by direct calls, the refund round trip included. The barter itself
## is proven in tests/obligations_test.gd.
var failures := 0
var checks := 0
var heard: Array = []
var fixture: Dictionary
var test_dir := (OS.get_environment("TMPDIR") if not OS.get_environment("TMPDIR").is_empty() else "/tmp").path_join("factory-driver-credits-%d" % OS.get_process_id())
var ledger_path := test_dir.path_join("credits.json")
var campaign_path := test_dir.path_join("campaign.json")
var obligations_path := test_dir.path_join("obligations.json")
var real_path := ""
var real_before := ""
var real_obligations_path := ""
var real_obligations_before := ""

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
## TROC-1 slice 2: who posts each job (the dispatch desk at its origin
## station), what they owe on delivery and the tip they offer, as authored.
const JOB_POSTERS := {"JOB-01": "DISPATCH-E2.4", "JOB-02": "DISPATCH-E2.2", "JOB-03": "DISPATCH-E2.2", "JOB-04": "DISPATCH-E2.3"}
const JOB_OWED := {"JOB-01": "one parcel delivery: Paddock station to Döttinger Höhe", "JOB-02": "one parcel delivery: Döttinger Höhe to Paddock station", "JOB-03": "one parcel delivery: Döttinger Höhe to Adenau station", "JOB-04": "one parcel delivery: Adenau station to Döttinger Höhe"}
const JOB_OFFERS := {"JOB-01": "a tip for a clean run: one rare material", "JOB-02": "a tip for a clean run: one dealership voucher", "JOB-03": "a tip for a clean run: some tuna for the cat", "JOB-04": "a tip for a clean run: one dealership voucher"}
## The paid fixture's poster, what it owes and its tip.
const PROOF_POSTER := "DISPATCH-PROOF"
const PROOF_OWED := "one proof delivery: across the pad"
const PROOF_OFFERS := "a tip for a clean run: one proof"
## ECON-3: the prices as documented (docs/econ3-implementation.md), the
## station the paid fill is driven at (the refuel test's E2.4) and the tank
## the fills start from [L].
## TROC-1 slice 3: PRICES is the DORMANT credits path's data now (was: the
## buying prices); DEALERS and TERMS are each car's desk and what it
## accepts, as authored in configs/dealership.json.
const PRICES := {"fd_1073": 60000, "boxster_986": 44000, "fd_2000": 100000}
const DEALERS := {"fd_1073": "DEALER-EIFEL-01", "boxster_986": "DEALER-EIFEL-02", "fd_2000": "DEALER-EIFEL-03"}
const TERMS := {
	"fd_1073": [{"accepts": "one held obligation", "settle": "obligation"}],
	"boxster_986": [{"accepts": "one held obligation", "settle": "obligation"}],
	"fd_2000": [{"accepts": "two held obligations", "settle": "obligation", "count": 2}],
}
const FUEL_STATION_ID := "E2.4"
const PART_TANK_L := 20.0

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
	real_obligations_path = DataDir.resolve(ObligationsLedger.PATH)
	real_obligations_before = stamp(real_obligations_path)
	print("-- idle and gated")
	_idle()
	print("-- the ledger")
	_ledger()
	print("-- the ledger's spend side (ECON-3)")
	_spend()
	print("-- the schema")
	_schema()
	print("-- the dealership's exchange-terms table (TROC-1 slice 3; was the price table, ECON-3)")
	_dealership()
	print("-- the job board's configs")
	_jobs()
	print("-- the runner pays")
	await _payment()
	print("-- the CAR page barters, the credits purchase dormant (TROC-1 slice 3; was the purchase, ECON-3)")
	await _purchase()
	print("-- the Ring: the board, a real pass, a real failure, paid fuel")
	await _ring()
	print("-- nothing of the driver's was touched")
	CreditsLedger.path_override = ""
	ObligationsLedger.path_override = ""
	CampaignStore.path_override = ""
	ok(stamp(real_path) == real_before, "the driver's own credits.json is as it was before the test (override isolation)")
	ok(stamp(real_obligations_path) == real_obligations_before, "and the driver's own obligations.json (TROC-1 slice 2: the jobs' pay goes through that store now)")
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
	ok(runner.obligations is ObligationsLedger and runner.obligations.state == ObligationsLedger.defaults() and runner.obligations.problems.is_empty() and ObligationsLedger.path_override == "" and ObligationsLedger.active_path() == "", "the idle runner holds an unread obligations ledger at its defaults beside the credits one, gated the same way (TROC-1 slice 2)")
	ok(runner.get_child_count() == 0 and not runner.is_physics_processing() and not runner.is_processing_input() and runner.active.is_empty(), "idle runner inert")
	var gated := CreditsLedger.new()
	gated.earned.connect(func(t: Dictionary): heard.append(t))
	gated.load_state()
	ok(gated.state == CreditsLedger.defaults() and gated.balance() == 0 and gated.transactions().is_empty(), "gated load reads nothing: the defaults")
	ok(gated.earn(95, "job:GATED").is_empty() and gated.balance() == 0 and heard.is_empty(), "gated earn returns {} and keeps nothing, in memory or as a signal")
	ok(stamp(real_path) == real_before and not DirAccess.dir_exists_absolute(test_dir), "a fresh runner and a gated ledger touch no file")
	# was KINDS == ["earn"], "the one kind written" -> both kinds (ECON-3), the
	# version unchanged: the schema reserved the kind, no migration.
	ok(CreditsLedger.PATH == "user://credits.json" and CreditsLedger.VERSION == 1 and CreditsLedger.KINDS == ["earn", "spend"], "the store's name, version 1 still, and the two kinds written (was earn alone, spend reserved)")
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
	# was: a spend entry among the bad ones -> it is read now (ECON-3); a
	# kind that is neither stands in for it.
	for bad in [null, 3, "earn", [], {}, {"seq": 2, "kind": "refund", "amount": 5, "reason": "b"}, {"seq": 2, "kind": "spend", "amount": 0, "reason": "b"}, {"seq": 2, "kind": "spend", "amount": -5, "reason": "b"}, {"seq": 2, "kind": "earn", "amount": 0, "reason": "b"}, {"seq": 2, "kind": "earn", "amount": -5, "reason": "b"}, {"seq": 2, "kind": "earn", "amount": 1.5, "reason": "b"}, {"seq": 2, "kind": "earn", "amount": "5", "reason": "b"}, {"seq": 2, "kind": "earn", "amount": 5}, {"seq": 2, "kind": "earn", "amount": 5, "reason": " "}, {"seq": 2, "kind": "earn", "amount": 5, "reason": 7}, {"seq": 2, "kind": "earn", "amount": 5, "reason": "b", "at_s": -1}, {"seq": 2, "kind": "earn", "amount": 5, "reason": "b", "at_s": "soon"}]:
		write_json(ledger_path, {"version": 1, "balance": 30, "transactions": [good, bad, {"seq": 3, "kind": "earn", "amount": 10, "reason": "c"}]})
		loaded.load_state()
		ok(loaded.balance() == 30 and loaded.state.transactions.size() == 2 and loaded.state.transactions[1].seq == 2 and loaded.state.transactions[1].reason == "c" and loaded.problems.size() == 2, "entry left out, the rest renumbered: " + str(bad))
	# was `!= ""`, "spend is reserved: no entry of that kind is read yet".
	ok(CreditsLedger.transaction_problem({"kind": "spend", "amount": 5, "reason": "b"}) == "" and CreditsLedger.transaction_problem(good) == "", "a spend entry is read (was reserved): the same amount rule as an earn, a whole number above zero")
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
	# was `not has("credits.json")`, ECON-1's known gap pinned -> closed (ECON-2).
	# was `[-1] == "credits.json" and [-2] == "campaign.json"`, the five files
	# -> the six: obligations.json follows it (TROC-1 slice 2).
	ok(DataDir.SEEDED_FILES == ["cars.json", "issues.json", "world.json", "campaign.json", "credits.json", "obligations.json"], "the data folder's seed carries credits.json after campaign.json (was ECON-1's known gap), and obligations.json after it (was the five, credits.json last)")
	DirAccess.remove_absolute(ledger_path)

# =============================================================================
#  The spend side (ECON-3)
# =============================================================================

func _spend() -> void:
	CreditsLedger.path_override = ledger_path
	DirAccess.remove_absolute(ledger_path)
	var ledger := CreditsLedger.new()
	var spends: Array = []
	heard.clear()
	ledger.earned.connect(func(t: Dictionary): heard.append(t))
	ledger.spent.connect(func(t: Dictionary): spends.append(t))
	ledger.load_state()
	ok(ledger.spend(1, "fuel").is_empty() and spends.is_empty() and not FileAccess.file_exists(ledger_path) and ledger.balance() == 0, "a spend on an empty ledger is refused: nothing written, nothing emitted, the balance 0")
	ok(ledger.earn(200, "job:JOB-01").seq == 1 and ledger.balance() == 200, "200 earned to spend from")
	for bad in [0, -1, -50]:
		ok(ledger.spend(bad, "fuel").is_empty(), "spend refuses amount " + str(bad))
	for bad in ["", "   ", "\n\t"]:
		ok(ledger.spend(5, bad).is_empty(), "spend refuses an empty reason")
	for bad in [NAN, INF, -INF]:
		ok(ledger.spend(5, "fuel", bad).is_empty(), "spend refuses the time " + str(bad))
	ok(ledger.spend(201, "car:fd_1073").is_empty() and spends.is_empty() and ledger.balance() == 200, "a spend above the balance is refused: 201 of 200, the balance unchanged, nothing emitted")
	var bytes := read_text(ledger_path)
	ok(JSON.parse_string(bytes).transactions.size() == 1 and not FileAccess.file_exists(ledger_path + ".tmp"), "refused spends write nothing")
	var first := ledger.spend(60, "fuel")
	ok(first == {"seq": 2, "kind": "spend", "amount": 60, "reason": "fuel"}, "the first spend returns the transaction as written: kind spend, the POSITIVE amount, no time")
	ok(spends.size() == 1 and spends[0] == first and heard.size() == 1, "spent fires once with the committed transaction; earned did not fire for it")
	ok(ledger.balance() == 140 and JSON.parse_string(read_text(ledger_path)).balance == 140, "the balance is the earns less the spends, in memory and on disk")
	ok(not FileAccess.file_exists(ledger_path + ".tmp") and files() == PackedStringArray(["credits.json"]), "atomic write: the temporary file consumed")
	var timed := ledger.spend(40, "car:test", 3.5)
	ok(timed == {"seq": 3, "kind": "spend", "amount": 40, "reason": "car:test", "at_s": 3.5} and ledger.balance() == 100, "a time on the caller's tick clock is written when given")
	ok(ledger.spend(100, "fuel").seq == 4 and ledger.balance() == 0, "a spend of exactly the balance is allowed: zero")
	ok(ledger.spend(1, "fuel").is_empty() and ledger.balance() == 0 and spends.size() == 3, "and one more credit is refused: the balance never goes below zero through the write path")
	var loaded := CreditsLedger.new()
	loaded.spent.connect(func(t: Dictionary): spends.append(t))
	loaded.load_state()
	ok(loaded.state == ledger.state and loaded.problems.is_empty() and loaded.balance() == 0 and loaded.state.transactions.size() == 4, "round trip: the mixed log reads back to the same state, no problem")
	var other := CreditsLedger.new()
	ok(other.earn(10, "job:JOB-02").seq == 5 and other.spend(4, "fuel").seq == 6 and other.balance() == 6, "a second ledger joins the log as it stands on disk, spends included")
	loaded.load_state()
	ok(loaded.balance() == 6, "and the first reads the joined log")

	# The derived sum: earn minus spend; a stored balance is never trusted.
	write_json(ledger_path, {"version": 1, "balance": 150, "transactions": [{"seq": 1, "kind": "earn", "amount": 100, "reason": "a"}, {"seq": 2, "kind": "spend", "amount": 30, "reason": "fuel"}, {"seq": 3, "kind": "earn", "amount": 50, "reason": "b"}, {"seq": 4, "kind": "spend", "amount": 20, "reason": "fuel"}]})
	bytes = read_text(ledger_path)
	loaded.load_state()
	ok(loaded.balance() == 100 and loaded.problems.size() == 1 and loaded.problems[0].contains("balance 150") and loaded.problems[0].contains("100"), "a stored balance that is the earns alone is reported: the derived earn-minus-spend sum 100 is adopted")
	ok(read_text(ledger_path) == bytes, "the read leaves the file as it is")
	write_json(ledger_path, {"version": 1, "transactions": [{"seq": 1, "kind": "earn", "amount": 100, "reason": "a"}, {"seq": 2, "kind": "spend", "amount": 30.0, "reason": "fuel"}]})
	loaded.load_state()
	ok(loaded.balance() == 70 and loaded.problems.is_empty() and loaded.state.transactions[1].kind == "spend" and loaded.state.transactions[1].amount is int, "a missing balance is derived from the mixed log without complaint, the spend's amount a whole number")
	write_json(ledger_path, {"version": 1, "balance": -50, "transactions": [{"seq": 1, "kind": "earn", "amount": 50, "reason": "a"}, {"seq": 2, "kind": "spend", "amount": 100, "reason": "fuel"}]})
	bytes = read_text(ledger_path)
	loaded.load_state()
	ok(loaded.balance() == -50 and loaded.problems.size() == 1 and loaded.problems[0].contains("spends more than it earns") and loaded.state.transactions.size() == 2, "a hand-edited log that spends more than it earns reads as its negative sum, reported, both entries kept (nothing invented)")
	ok(read_text(ledger_path) == bytes and loaded.spend(1, "fuel").is_empty(), "the read leaves the file alone and no spend is possible from it")
	ok(loaded.earn(60, "job:x").seq == 3 and loaded.balance() == 10 and JSON.parse_string(read_text(ledger_path)).balance == 10, "an earn on it writes the derived balance: 10")
	write_json(ledger_path, {"version": 1, "balance": 0, "transactions": [{"seq": 1, "kind": "spend", "amount": 5, "reason": "fuel"}]})
	loaded.load_state()
	ok(loaded.balance() == -5 and loaded.problems.size() == 2, "a spend-only log: the negative sum reported, and the stored 0 reported as not the sum")

	# Version refusal protects a newer file from spends too; gated keeps nothing.
	write_json(ledger_path, {"version": 2, "balance": 500, "transactions": [{"seq": 1, "kind": "earn", "amount": 500, "reason": "later build"}]})
	bytes = read_text(ledger_path)
	spends.clear()
	ok(ledger.spend(5, "fuel").is_empty() and spends.is_empty() and read_text(ledger_path) == bytes and not FileAccess.file_exists(ledger_path + ".tmp"), "a later build's file is never written over: spend refuses, the bytes stay")
	CreditsLedger.path_override = ""
	ok(ledger.spend(5, "fuel").is_empty() and spends.is_empty() and stamp(real_path) == real_before, "gated, a spend returns {} and keeps nothing")
	CreditsLedger.path_override = ledger_path

	# A write that fails publishes nothing: the temporary file's name taken by a folder.
	write_json(ledger_path, {"version": 1, "balance": 100, "transactions": [{"seq": 1, "kind": "earn", "amount": 100, "reason": "a"}]})
	bytes = read_text(ledger_path)
	loaded.load_state()
	var committed: Dictionary = loaded.state.duplicate(true)
	DirAccess.make_dir_absolute(ledger_path + ".tmp")
	ok(loaded.spend(5, "fuel").is_empty() and spends.is_empty(), "a write that fails returns {} and emits nothing")
	DirAccess.remove_absolute(ledger_path + ".tmp")
	ok(read_text(ledger_path) == bytes and loaded.state == committed, "the failed spend publishes nothing: the file and the state are the last committed")
	ok(loaded.spend(5, "fuel").seq == 2 and loaded.balance() == 95, "the retry commits it")
	ok(loaded.earn(1, "a").seq == 3 and loaded.earn(0, "a").is_empty() and loaded.earn(1, " ").is_empty() and loaded.earn(1, "a", NAN).is_empty() and loaded.balance() == 96, "the earn path's rules stand beside the spend's")
	DirAccess.remove_absolute(ledger_path)

# =============================================================================
#  The schema
# =============================================================================

func _schema() -> void:
	ok(MissionSchema.validate(fixture).is_empty() and not fixture.has("reward_credits") and not fixture.has("job_kind") and not fixture.has("poster") and not fixture.has("poster_owed") and not fixture.has("poster_offers"), "a mission without either field is valid: not a paid mission (and none of the poster fields)")
	var job := fixture.duplicate(true)
	job.reward_credits = 95
	# was `validate(job).is_empty()`, "reward_credits alone is valid" -> a paid
	# job is a posted job (TROC-1 slice 2): the poster and what they owe come
	# with the reward.
	ok(MissionSchema.validate(job) == PackedStringArray(["reward_credits needs poster", "reward_credits needs poster_owed"]), "reward_credits alone is refused: it needs its poster and what the poster owes (was valid)")
	job.poster = PROOF_POSTER
	ok(MissionSchema.validate(job) == PackedStringArray(["reward_credits needs poster_owed"]), "reward_credits with a poster and nothing owed is refused")
	job.erase("poster")
	job.poster_owed = PROOF_OWED
	ok(MissionSchema.validate(job) == PackedStringArray(["reward_credits needs poster"]), "reward_credits with something owed and no poster is refused")
	job.poster = PROOF_POSTER
	ok(MissionSchema.validate(job).is_empty(), "reward_credits with poster and poster_owed is valid: the posted job (was reward_credits alone)")
	job.poster_offers = PROOF_OFFERS
	ok(MissionSchema.validate(job).is_empty(), "poster_offers is optional beside them: valid with, valid without")
	job.job_kind = "courier"
	ok(MissionSchema.validate(job).is_empty(), "reward_credits with a job_kind is valid")
	for kind in ["testdrive", "scouting", "anything new"]:
		job.job_kind = kind
		ok(MissionSchema.validate(job).is_empty(), "the kind is free vocabulary: " + kind)
	job.reward_credits = 95.0
	ok(MissionSchema.validate(job).is_empty(), "a whole number read from JSON is a whole number")
	for bad in [0, -5, 1.5, 0.5, "95", true, null, [], {}, INF, -INF, NAN]:
		# The fixtures below are posted (TROC-1 slice 2), so each refusal is
		# the pinned field's own and not the missing poster's.
		var m := _paid(fixture.id, 95)
		m.reward_credits = bad
		ok(MissionSchema.validate(m) == PackedStringArray(["reward_credits must be a whole number above zero"]), "reward_credits refuses " + str(bad))
	for bad in ["", "  ", 3, null, [], {}, true]:
		var m := _paid(fixture.id, 95)
		m.job_kind = bad
		ok(MissionSchema.validate(m) == PackedStringArray(["job_kind must be nonempty text"]), "job_kind refuses " + str(bad))
	var unpaid := fixture.duplicate(true)
	unpaid.job_kind = "courier"
	ok(not MissionSchema.validate(unpaid).is_empty(), "a job_kind without reward_credits is refused")
	var bad_entry := _paid(fixture.id, 0)
	ok(MissionSchema.catalog_errors([bad_entry]).has(fixture.id), "a bad reward keeps the entry out of the catalog")
	# TROC-1 slice 2: the poster fields.
	for field: String in ["poster", "poster_owed", "poster_offers"]:
		for bad in ["", "  ", 3, null, [], {}, true]:
			var m := _paid(fixture.id, 95)
			m[field] = bad
			ok(MissionSchema.validate(m) == PackedStringArray([field + " must be nonempty text"]), field + " refuses " + str(bad))
		var lone := fixture.duplicate(true)
		lone[field] = "text"
		ok(MissionSchema.validate(lone) == PackedStringArray([field + " needs reward_credits"]), "a " + field + " without reward_credits is refused: the ladder is posted by nobody")
	var unposted := _paid(fixture.id, 95)
	unposted.erase("poster")
	ok(MissionSchema.catalog_errors([unposted]).has(fixture.id) and MissionSchema.catalog_errors([_paid(fixture.id, 95)]).is_empty(), "a paid job without its poster stays out of the catalog; the posted one is in")

# =============================================================================
#  The dealership's exchange-terms table (TROC-1 slice 3; was ECON-3's
#  price table)
# =============================================================================

## A table entry of the test's own, well-formed, with `changes` laid over it
## and the keys in `without` taken away.
func _entry(changes := {}, without := []) -> Dictionary:
	var made := {"car_id": "fd_1073", "price_credits": 60000, "basis": "b", "dealer": "DESK-TEST", "terms": [{"accepts": "one held obligation", "settle": "obligation"}]}
	for key: String in changes:
		made[key] = changes[key]
	for key: String in without:
		made.erase(key)
	return made

func _dealership() -> void:
	var shipped := FileAccess.get_file_as_string(Dealership.PATH)
	var table := Dealership.read()
	ok(Dealership.PATH == "res://configs/dealership.json" and Dealership.VERSION == 1 and table.usable and not table.newer_file and table.problems.is_empty() and table.version == 1, "the shipped table reads clean: version 1, no problem")
	var ids: Array = []
	for entry: Dictionary in table.cars:
		ids.append(entry.car_id)
		# was "is priced as documented: %d credits", the buying price -> the
		# number stays in the table as the dormant credits path's data.
		ok(entry.price_credits == PRICES.get(entry.car_id, -1) and entry.price_credits is int, entry.car_id + " keeps price_credits %d: the DORMANT credits path's data, charged by nothing on the page (was: the buying price)" % entry.price_credits)
		# was `contains("AUTHORED") and contains("no source price")`, "the basis
		# says the price is authored and why" -> the terms' provenance beside it.
		ok(entry.basis is String and entry.basis.length() > 40 and entry.basis.contains("AUTHORED") and entry.basis.contains("no source price") and entry.basis.contains("no source exchange-terms") and entry.basis.contains("docs/design/troc-redesign.md §3") and entry.basis.contains("DORMANT") and entry.basis.contains("16036083") and entry.basis.contains("not a price") and entry.basis.contains("voucher term is deferred to slice 4"), entry.car_id + "'s basis says the terms and the price are authored, the price dormant by the ruling, a count no price, the voucher term deferred (was: the price authored and why)")
		ok(entry.dealer == DEALERS.get(entry.car_id, "") and entry.terms == TERMS.get(entry.car_id, []) and Dealership.dealer_of(entry) == entry.dealer and Dealership.terms_of(entry) == entry.terms, entry.car_id + " is traded by its own desk %s, which accepts: %s" % [entry.dealer, entry.terms[0].accepts])
		ok(FileAccess.file_exists(Dealership.config_path(entry.car_id)) and Dealership.car_name(entry.car_id) != entry.car_id, entry.car_id + " has a config and a name of its own (" + Dealership.car_name(entry.car_id) + ")")
	ok(ids == ["fd_1073", "boxster_986", "fd_2000"], "the three reward cars in file order")
	var no_voucher := true
	var numbers_free := true
	for entry: Dictionary in table.cars:
		for term: Dictionary in entry.terms:
			no_voucher = no_voucher and term.settle == "obligation"
			numbers_free = numbers_free and term.keys().all(func(key: String): return key in ["accepts", "settle", "count"]) and (not term.has("count") or term.count is int)
	ok(no_voucher and numbers_free and Dealership.TERMS_SETTLES == ["obligation", "voucher"] and DEALERS.values().size() == 3 and DEALERS["fd_1073"] != DEALERS["boxster_986"] and DEALERS["boxster_986"] != DEALERS["fd_2000"] and DEALERS["fd_1073"] != DEALERS["fd_2000"], "v1 terms are held obligations only: no shipped term is settled by a voucher (the word is validated vocabulary, slice 4's), a term carries its words, its settle and a count of things, no number of value; three desks, three ids")
	var copied := Dealership.terms_of(table.cars[2])
	copied[0].count = 99
	copied.append({})
	ok(Dealership.terms_of(table.cars[2]) == TERMS["fd_2000"] and table.cars[2].terms == TERMS["fd_2000"] and Dealership.terms_of({}).is_empty() and Dealership.dealer_of({}) == "" and Dealership.ENTRY_KEYS == ["car_id", "price_credits", "basis", "dealer", "terms"], "terms_of hands out a deep copy; {} has no terms and no dealer; an entry carries exactly the five keys (was three: car_id, price_credits, basis)")
	var configs := PackedStringArray()
	for file in DirAccess.get_files_at(Dealership.CARS_DIR):
		if file.ends_with(".json"):
			configs.append(file.get_basename())
	var all_but_voucher := true
	for id in configs:
		all_but_voucher = all_but_voucher and (ids.has(id) != (id == FirstCar.CAR_ID))
	ok(configs.size() == 4 and all_but_voucher and Dealership.entry_of(table, FirstCar.CAR_ID).is_empty() and Dealership.price_of(table, FirstCar.CAR_ID) == 0, "every car under configs/cars is for sale except fd_1001, the voucher's car, absent")
	for rank: String in CampaignStore.REWARD_CARS:
		ok(ids.has(CampaignStore.REWARD_CARS[rank]), "the " + rank + " reward car is purchasable early as well as granted")
	ok(Dealership.price_of(table, "fd_1073") == 60000 and Dealership.entry_of(table, "fd_1073").basis == table.cars[0].basis and Dealership.entry_of(table, "nobody").is_empty() and Dealership.price_of(table, "nobody") == 0, "entry_of and price_of: the entry, the price, {} and 0 for a car not sold")
	ok(Dealership.purchase_reason("fd_1073") == "car:fd_1073" and Dealership.refund_reason("fd_1073") == "refund:car:fd_1073" and Refuel.FUEL_REASON == "fuel", "the spend reasons the game writes: car:<id>, refund:car:<id>, fuel")
	var log := [{"seq": 1, "kind": "spend", "amount": 5, "reason": "car:fd_1073"}]
	ok(Dealership.purchased(log, "fd_1073") and not Dealership.purchased(log, "fd_2000") and not Dealership.purchased([], "fd_1073"), "purchased: a car:<id> spend in the log is the ownership")
	log.append({"seq": 2, "kind": "earn", "amount": 5, "reason": "refund:car:fd_1073"})
	ok(not Dealership.purchased(log, "fd_1073"), "a refund:car:<id> earn undoes it")
	log.append({"seq": 3, "kind": "spend", "amount": 5, "reason": "car:fd_1073"})
	ok(Dealership.purchased(log, "fd_1073") and not Dealership.purchased([{"kind": "earn", "amount": 5, "reason": "car:fd_1073"}], "fd_1073") and not Dealership.purchased([null, 3], "fd_1073"), "bought again after a refund; an earn under the purchase reason is no purchase; junk is skipped")

	# The validation battery on tables of the test's own.
	var table_path := test_dir.path_join("dealership.json")
	# was {car_id, price_credits, basis} alone: an entry carries its desk and
	# its terms now, and one without them is refused (pinned below).
	var good := _entry({"basis": "authored"})
	var second := _entry({"car_id": "boxster_986", "price_credits": 44000, "basis": "authored", "dealer": "DESK-TWO", "terms": [{"accepts": "one dealership voucher", "settle": "voucher"}, {"accepts": "three held obligations", "settle": "obligation", "count": 3}]})
	write_json(table_path, {"version": 1, "cars": [good, second]})
	var read := Dealership.read(table_path)
	ok(read.usable and read.problems.is_empty() and read.cars.size() == 2 and read.cars[0] == good and read.cars[1] == second, "a good table of the test's own loads: the entries as kept, the desk and the terms carried through - a voucher term among them (validated vocabulary, read; nothing settles it yet)")
	ok(read.cars[1].terms[1].count is int and read.cars[1].terms[1].count == 3 and not read.cars[1].terms[0].has("count") and not read.cars[0].terms[0].has("count") and Garage.term_count(read.cars[0].terms[0]) == 1, "a term's count read from JSON is kept as int; an absent count stays absent and means 1 (nothing invented)")
	write_json(table_path, {"version": 1, "cars": [_entry({"price_credits": 60000.0})]})
	read = Dealership.read(table_path)
	ok(read.cars.size() == 1 and read.cars[0].price_credits == 60000 and read.cars[0].price_credits is int, "a whole number read from JSON as a float is a whole number, kept as int")
	for bad in [2, 99]:
		write_json(table_path, {"version": bad, "cars": [good]})
		read = Dealership.read(table_path)
		ok(not read.usable and read.newer_file and read.cars.is_empty() and read.problems.size() == 1 and read.problems[0].contains("later build"), "version %d is a later build's: unusable, reported, sells nothing" % bad)
	for bad in [0, -1, 1.5, "1", null, [], true]:
		write_json(table_path, {"version": bad, "cars": [good]})
		read = Dealership.read(table_path)
		ok(not read.usable and not read.newer_file and read.cars.is_empty() and read.problems.size() == 1, "version " + str(bad) + " is not 1: unusable, reported")
	write_json(table_path, {"cars": [good]})
	read = Dealership.read(table_path)
	ok(not read.usable and read.cars.is_empty() and read.problems.size() == 1, "a table without a version is unusable (no version-zero grace: the table is shipped, never migrated)")
	for bad in ["[1]", "\"x\"", "3", "null", "{broken"]:
		write_text(table_path, bad)
		read = Dealership.read(table_path)
		ok(not read.usable and read.cars.is_empty() and read.problems.size() == 1, "a file that is no object, or no JSON, sells nothing: " + bad)
	read = Dealership.read(test_dir.path_join("nowhere.json"))
	ok(not read.usable and read.cars.is_empty() and read.problems.size() == 1 and read.problems[0].contains("no such file"), "a missing table sells nothing, reported")
	for bad in [{"version": 1}, {"version": 1, "cars": {}}, {"version": 1, "cars": "fd_1073"}, {"version": 1, "cars": null}]:
		write_json(table_path, bad)
		read = Dealership.read(table_path)
		ok(read.usable and read.cars.is_empty() and read.problems.size() == 1 and read.problems[0].contains("not a list"), "cars missing or no list: usable, sells nothing, reported: " + str(bad))
	write_json(table_path, {"version": 1, "cars": []})
	read = Dealership.read(table_path)
	ok(read.usable and read.cars.is_empty() and read.problems.size() == 1 and read.problems[0].contains("no entry is valid"), "a well-formed table with no entry sells nothing and says so")
	write_json(table_path, {"version": 1, "cars": [good], "extra": 1})
	read = Dealership.read(table_path)
	ok(read.usable and read.cars.size() == 1 and read.problems.size() == 1 and read.problems[0].contains("unknown key extra"), "an unknown top-level key is reported and ignored")
	var bad_entries := [
		[null, "is not an object"], [3, "is not an object"], ["fd_1073", "is not an object"], [[], "is not an object"], [{}, "has no car_id"],
		# was bare {car_id, price_credits, basis} fixtures -> each carries the
		# desk and the terms, so the refusal is the pinned field's own.
		[_entry({}, ["basis"]), "has no basis"],
		[_entry({}, ["price_credits"]), "has no price_credits"],
		[_entry({}, ["car_id"]), "has no car_id"],
		[_entry({"name": "x"}), "unknown key (name)"],
		[_entry({"car_id": ""}), "car_id is not a nonempty string"],
		[_entry({"car_id": "  "}), "car_id is not a nonempty string"],
		[_entry({"car_id": 7}), "car_id is not a nonempty string"],
		[_entry({"car_id": "no_such_car"}), "has no config"],
		[_entry({"price_credits": 0}), "not a whole number above zero"],
		[_entry({"price_credits": -5}), "not a whole number above zero"],
		[_entry({"price_credits": 1.5}), "not a whole number above zero"],
		[_entry({"price_credits": "60000"}), "not a whole number above zero"],
		[_entry({"price_credits": null}), "not a whole number above zero"],
		[_entry({"basis": ""}), "basis is not a nonempty string"],
		[_entry({"basis": "  "}), "basis is not a nonempty string"],
		[_entry({"basis": 3}), "basis is not a nonempty string"],
		# TROC-1 slice 3: the desk and the terms. The first is ECON-3's own
		# entry shape: a table of the old build's is refused whole.
		[{"car_id": "fd_1073", "price_credits": 60000, "basis": "b"}, "has no dealer"],
		[_entry({}, ["dealer"]), "has no dealer"],
		[_entry({"dealer": ""}), "dealer is not a nonempty string"],
		[_entry({"dealer": "  "}), "dealer is not a nonempty string"],
		[_entry({"dealer": 7}), "dealer is not a nonempty string"],
		[_entry({"dealer": null}), "dealer is not a nonempty string"],
		[_entry({}, ["terms"]), "has no terms"],
		[_entry({"terms": "one held obligation"}), "terms is not a list"],
		[_entry({"terms": {"accepts": "one held obligation", "settle": "obligation"}}), "terms is not a list"],
		[_entry({"terms": null}), "terms is not a list"],
		[_entry({"terms": []}), "terms is an empty list"],
		[_entry({"terms": [3]}), "terms[0] is not an object"],
		[_entry({"terms": ["one held obligation"]}), "terms[0] is not an object"],
		[_entry({"terms": [{"settle": "obligation"}]}), "terms[0] has no accepts"],
		[_entry({"terms": [{"accepts": "", "settle": "obligation"}]}), "terms[0] accepts is not a nonempty string"],
		[_entry({"terms": [{"accepts": 3, "settle": "obligation"}]}), "terms[0] accepts is not a nonempty string"],
		[_entry({"terms": [{"accepts": "one held obligation"}]}), "terms[0] has no settle"],
		[_entry({"terms": [{"accepts": "44000 credits", "settle": "credits"}]}), "terms[0] has an unknown settle (credits)"],
		[_entry({"terms": [{"accepts": "one held obligation", "settle": null}]}), "terms[0] has an unknown settle"],
		[_entry({"terms": [{"accepts": "none", "settle": "obligation", "count": 0}]}), "terms[0] count is not a whole number of 1 or more"],
		[_entry({"terms": [{"accepts": "some", "settle": "obligation", "count": 1.5}]}), "terms[0] count is not a whole number of 1 or more"],
		[_entry({"terms": [{"accepts": "two", "settle": "obligation", "count": "2"}]}), "terms[0] count is not a whole number of 1 or more"],
		[_entry({"terms": [{"accepts": "owed", "settle": "obligation", "count": -1}]}), "terms[0] count is not a whole number of 1 or more"],
		[_entry({"terms": [{"accepts": "one held obligation", "settle": "obligation", "price_credits": 5}]}), "terms[0] has an unknown key (price_credits)"],
		[_entry({"terms": [{"accepts": "one held obligation", "settle": "obligation"}, {"accepts": "cash", "settle": "cash"}]}), "terms[1] has an unknown settle (cash)"],
	]
	for pair in bad_entries:
		write_json(table_path, {"version": 1, "cars": [second, pair[0], good]})
		read = Dealership.read(table_path)
		ok(read.usable and read.cars.size() == 2 and read.cars[0].car_id == "boxster_986" and read.cars[1].car_id == "fd_1073" and read.problems.size() == 1 and read.problems[0].contains("cars[1]") and read.problems[0].contains(pair[1]) and read.problems[0].contains("left out"), "entry refused and reported, the rest kept in order: " + str(pair[0]))
	write_json(table_path, {"version": 1, "cars": [good, second, _entry({"price_credits": 1, "basis": "cheap"})]})
	read = Dealership.read(table_path)
	ok(read.cars.size() == 2 and read.cars[0].price_credits == 60000 and read.problems.size() == 1 and read.problems[0].contains("cars[2]") and read.problems[0].contains("again"), "a duplicated car_id is refused: the first listing stands, the second reported")
	write_json(table_path, {"version": 1, "cars": [null, _entry({"car_id": "nobody"})]})
	read = Dealership.read(table_path)
	ok(read.usable and read.cars.is_empty() and read.problems.size() == 3, "a table whose every entry is refused sells nothing: each refusal and the empty result reported")
	ok(FileAccess.get_file_as_string(Dealership.PATH) == shipped and JSON.parse_string(shipped).cars.size() == 3, "the shipped table was never written by the reader")
	DirAccess.remove_absolute(table_path)

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
		ok(job.poster == JOB_POSTERS[id] and job.poster == "DISPATCH-" + JOB_STATIONS[id][0] and job.poster_owed == JOB_OWED[id] and job.poster_offers == JOB_OFFERS[id], id + " is posted by the dispatch desk at its origin station (" + JOB_POSTERS[id] + "), with what the desk owes on delivery and the tip it offers, as authored (TROC-1 slice 2)")
		pays.append(int(job.reward_credits))
	# was "the board pays 95, 100, 130 and 150 credits" -> the numbers stay in
	# the configs, inert: the board neither shows nor pays them (TROC-1 slice 2;
	# the rows and the pay are pinned in _payment and _ring).
	ok(pays == [95, 100, 130, 150], "reward_credits is still authored 95, 100, 130 and 150: what marks a paid job, no longer displayed or paid (was: the board pays them)")
	ok(runner.catalog["JOB-02"].poster == runner.catalog["JOB-03"].poster and runner.catalog["JOB-01"].poster != runner.catalog["JOB-04"].poster, "two jobs, one poster: the Döttinger Höhe desk posts JOB-02 and JOB-03; three desks post the four")
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
	m.poster = PROOF_POSTER
	m.poster_owed = PROOF_OWED
	m.poster_offers = PROOF_OFFERS
	return m

## The open record a pass of the paid fixture writes at the 1-based `place`
## of the log, in episode `episode`.
func _proof_record(place: int, episode: int) -> Dictionary:
	return {"id": "OBL-%04d" % place, "creditor": "player", "debtor": PROOF_POSTER, "owed": PROOF_OWED, "kind": "delivery", "origin": "job:PAID-PROOF/episode-%d" % episode, "status": "open", "redemptions": [], "transfers": []}

func _pass_by_ticks(runner: MissionRunner, mission: Dictionary) -> bool:
	if not runner.start(mission.id):
		return false
	for step: Dictionary in mission.episode:
		runner.tick(1, Vector3(step.position[0], step.position[1], step.position[2]))
	return runner.active.is_empty()

func _payment() -> void:
	var runner := MissionRunner.of(self)
	CreditsLedger.path_override = ledger_path
	ObligationsLedger.path_override = obligations_path
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
	# was `var ledger := CreditsLedger.new()`: the pay is read back from the
	# obligations file now (TROC-1 slice 2). The credits ledger's earned
	# signal is still listened to, to pin that no job earns a credit.
	var owed := ObligationsLedger.new()
	var results: Array = []
	var listener := func(result: Dictionary): results.append(result)
	runner.episode_finished.connect(listener)
	heard.clear()
	var hear := func(t: Dictionary): heard.append(t)
	runner.credits.earned.connect(hear)

	# A mission without the field never reaches the ledger.
	ok(_pass_by_ticks(runner, plain) and runner.last_result.passed and not runner.last_result.has("obligation") and not runner.last_result.has("credits"), "an unpaid mission passes without an obligation field in its result (was: without a credits field)")
	ok(not FileAccess.file_exists(obligations_path) and not FileAccess.file_exists(ledger_path) and heard.is_empty() and not runner.result_text().contains("owed by") and not runner.result_text().contains("paid"), "and writes no ledger, obligations or credits: inert when the field is absent")

	# Failed and aborted jobs pay nothing.
	runner.start(job.id)
	runner._previous = Vector3(10, 0.7, -18)
	runner.tick(1, Vector3(0, 0.7, -18))
	ok(not runner.last_result.passed and runner.last_result.reason == "skipped gate" and runner.last_result.obligation == {} and not runner.last_result.has("credits"), "a failed job reports no obligation: {} (was zero credits)")
	ok(runner.pay_last_result() == {} and not FileAccess.file_exists(obligations_path), "a failed job creates nothing, asked again or not (was: pays nothing)")
	runner.start(job.id)
	runner.tick(21, Vector3(0, 0.7, 0))
	ok(runner.last_result.reason == "time limit" and runner.last_result.obligation == {} and not FileAccess.file_exists(obligations_path), "a job that runs out of time creates nothing (was: pays nothing)")
	runner.start(job.id)
	runner.tick(1, Vector3(0, 0.7, -4))
	runner.abort()
	ok(runner.last_result.is_empty() and runner.pay_last_result() == {} and not FileAccess.file_exists(obligations_path) and heard.is_empty(), "an aborted job creates nothing: zero records so far (was: zero transactions)")

	# A pass pays once: the poster's obligation to the player.
	results.clear()
	var episode := runner._episode + 1
	var first := _proof_record(1, episode)
	ok(_pass_by_ticks(runner, job) and runner._episode == episode and runner.last_result.passed and runner.last_result.obligation == first and not runner.last_result.has("credits") and runner.last_result.saved, "a passed job leaves its poster owing: the record in the result (was: pays its reward, credits == 95)")
	owed.load_state()
	ok(owed.records() == [first] and owed.problems.is_empty() and JSON.parse_string(read_text(obligations_path)).records.size() == 1, "one record on disk: creditor player, debtor the poster, owed in the poster's words, kind delivery, origin job:<id>/episode-<n>, open, no redemption, no transfer (was: one earn transaction, reasoned job:<id>)")
	# was `heard.size() == 1 ... contains("paid 95 credits")`: one earned signal
	# -> none, no credit is earned; the result text names who owes what.
	ok(heard.is_empty() and not FileAccess.file_exists(ledger_path) and results.size() == 1 and results[0].obligation == first and runner.result_text().ends_with(" — owed by %s: %s" % [PROOF_POSTER, PROOF_OWED]) and not runner.result_text().contains("credits"), "no earned signal and no credits file (was one earned signal), one finished episode, the owed-by line in the result text (was: paid 95 credits)")
	ok(runner.active.is_empty() and not runner.is_physics_processing() and runner.get_child_count() == 0, "finish returns to inert")

	# No double pay: every retry of the payment is refused.
	var bytes := read_text(obligations_path)
	runner.finish(true, "course complete")
	runner.finish(true, "again")
	ok(runner.pay_last_result() == {} and runner.pay_last_result() == {}, "the payment asked for again creates nothing (was: pays nothing)")
	var delivered: Dictionary = runner.last_result.duplicate(true)
	runner.episode_finished.emit(delivered)
	runner.episode_finished.emit(delivered)
	ok(results.size() == 3 and read_text(obligations_path) == bytes and heard.is_empty(), "the same result delivered twice more, a second and third finish(): the obligations file's bytes are the same (was: the credits ledger's)")
	var greedy := func(_result: Dictionary): runner.pay_last_result()
	runner.episode_finished.connect(greedy)
	ok(_pass_by_ticks(runner, job) and runner.last_result.obligation == _proof_record(2, episode + 1), "passing the job again is new work: a second record, the next episode in its origin")
	owed.load_state()
	ok(owed.records() == [first, _proof_record(2, episode + 1)] and owed.open_view("player", PROOF_POSTER).size() == 2 and heard.is_empty(), "and new pay, once: a listener that asks for the payment inside the signal gets nothing (was: balance 190, two transactions)")
	runner.episode_finished.disconnect(greedy)
	ok(runner.campaign.state.results[job.id].attempts == 4 and runner.campaign.state.results[job.id].medal == "gold", "the campaign counts the job's attempts and keeps its medal beside the ladder's")

	# The pay does not wait on the campaign record.
	CampaignStore.path_override = test_dir
	ok(_pass_by_ticks(runner, job) and not runner.last_result.saved and runner.last_result.obligation == _proof_record(3, episode + 2), "a result that could not be saved still leaves the poster owing (was: is still paid)")
	DirAccess.remove_absolute(test_dir + ".tmp")
	CampaignStore.path_override = campaign_path
	owed.load_state()
	ok(owed.records().size() == 3 and runner.result_text().contains("(save failed)") and runner.result_text().contains("owed by " + PROOF_POSTER), "the ledger holds three records; the text says both (was: balance 285, paid 95 credits)")

	# A payment the ledger refused is not remembered as paid.
	bytes = read_text(obligations_path)
	ObligationsLedger.path_override = test_dir
	ok(_pass_by_ticks(runner, job) and runner.last_result.passed and runner.last_result.obligation == {}, "an obligations write that fails creates nothing (was: a credits write that fails pays nothing)")
	DirAccess.remove_absolute(test_dir + ".tmp")
	ObligationsLedger.path_override = obligations_path
	ok(read_text(obligations_path) == bytes, "and publishes nothing")
	ok(runner.pay_last_result() == _proof_record(4, episode + 3) and runner.pay_last_result() == {}, "the retry commits it, once: the record of the episode that passed (was: 95, then 0)")
	owed.load_state()
	ok(owed.records().size() == 4 and owed.open_view("player").size() == 4 and owed.problems.is_empty(), "four records, none doubled (was: balance 380, four payments)")

	# Gated, a pass pays nothing and writes nothing.
	bytes = read_text(obligations_path)
	ObligationsLedger.path_override = ""
	ok(_pass_by_ticks(runner, job) and runner.last_result.passed and runner.last_result.obligation == {} and read_text(obligations_path) == bytes and stamp(real_obligations_path) == real_obligations_before and stamp(real_path) == real_before, "gated, a passed job creates nothing anywhere (was: pays nothing anywhere)")
	ObligationsLedger.path_override = obligations_path

	# The pad car, the fixture's own scripted driver.
	ok(runner.start(job.id, true), "the paid fixture starts scripted on the pad car")
	for i in 1300:
		await physics_frame
		if runner.active.is_empty():
			break
	owed.load_state()
	# was `credits == 95 and ledger.balance() == 475`.
	ok(runner.last_result.get("passed", false) and runner.last_result.get("obligation") == _proof_record(5, episode + 5) and not runner.last_result.has("credits") and owed.records().size() == 5, "a real pad drive to a pass leaves the poster owing: the fifth record, no credits key (was: credits 95, balance 475)")
	ok(not FileAccess.file_exists(ledger_path) and heard.is_empty(), "five jobs delivered and the credits ledger was never written: no file, no earned signal (was: five earn transactions)")

	# The JOBS page on the pad.
	garage.show_page(Garage.Page.JOBS)
	var rows := garage.page_rows()
	var row: Dictionary = {}
	for candidate: Dictionary in rows:
		if candidate.id == job.id:
			row = candidate
	# was `contains("CREDITS: 475") and contains("Payments received: 5") and
	# contains("+95 job:PAID-PROOF")` -> the TROC board.
	var text := garage.page_text()
	ok(text.contains("JOB BOARD") and not text.contains("CREDITS:") and not text.contains("Payments received") and text.contains("The board trades by TROC") and text.count("Owed to you by %s: %s" % [PROOF_POSTER, PROOF_OWED]) == 5 and not text.contains("You owe") and not text.contains("Nothing owed"), "the JOBS page reads TROC: no credits heading, no payments line, the five open obligations owed to the driver by the fixture's poster, nothing owed by the driver (was: the credits held and the last payment)")
	# was label "... —  courier  —  95 credits".
	ok(not row.is_empty() and row.kind == "job" and row.enabled and row.label == "DONE — PAID-PROOF — Paid proof  —  courier" and row.hint.contains(job.briefing) and row.hint.contains("Enter to start — pad") and row.hint.contains("gold") and row.hint.ends_with("\nPosted by %s — on delivery they owe you: %s — tip: %s" % [PROOF_POSTER, PROOF_OWED, PROOF_OFFERS]), "a job row: done mark, id, title, kind, no pay on the label (was: —  95 credits); the briefing, the best and the poster's offer in its hint")
	var owing: Dictionary = _proof_record(1, 1)
	owing.creditor = "DISPATCH-E2.2"
	owing.debtor = "player"
	owing.owed = "a favor: a job for me"
	owing.kind = "favor"
	owing.origin = "trade:test"
	ok(ObligationsLedger.new().create(owing.creditor, owing.debtor, owing.owed, owing.kind, owing.origin).id == "OBL-0006", "an obligation the driver owes, written by the test's own ledger")
	garage.show_page(Garage.Page.JOBS)
	text = garage.page_text()
	ok(text.count("Owed to you by") == 5 and text.count("You owe") == 1 and text.contains("You owe DISPATCH-E2.2: a favor: a job for me") and text.find("You owe") > text.rfind("Owed to you by"), "the page lists what the driver owes after what is owed to them: You owe <creditor>: <owed>")
	var no_tip := job.duplicate(true)
	no_tip.id = "PAID-NO-TIP"
	no_tip.erase("poster_offers")
	runner.catalog[no_tip.id] = no_tip
	garage.show_page(Garage.Page.JOBS)
	var plain_hint := ""
	for candidate: Dictionary in garage.page_rows():
		if candidate.id == no_tip.id:
			plain_hint = candidate.hint
	ok(plain_hint.ends_with("\nPosted by %s — on delivery they owe you: %s" % [PROOF_POSTER, PROOF_OWED]) and not plain_hint.contains("tip:"), "a job posted without an offer shows no tip")
	runner.catalog.erase(no_tip.id)
	ObligationsLedger.path_override = ""
	garage.show_page(Garage.Page.JOBS)
	ok(garage.page_text().contains("Nothing owed to you or by you yet.") and not garage.page_text().contains("Owed to you by") and not garage.page_text().contains("You owe"), "gated (no override) the page reads no obligations: the one line, nothing owed")
	ObligationsLedger.path_override = obligations_path
	garage.show_page(Garage.Page.JOBS)
	rows = garage.page_rows()
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
	ObligationsLedger.path_override = ""
	DirAccess.remove_absolute(ledger_path)
	DirAccess.remove_absolute(obligations_path)
	DirAccess.remove_absolute(campaign_path)

# =============================================================================
#  The CAR page barters; the credits purchase is dormant (TROC-1 slice 3;
#  was: the purchase, ECON-3)
# =============================================================================

## The CAR page's dealership on the pad, wired to the test's own credits
## ledger, world record and cars file, and to an obligations file of the
## test's own that holds nothing (the two wirings are independent): the
## page's BARTER shape and the dormancy (was: the greyed BUY rows), then
## the dormant path's machinery by direct calls, intact - the refusals, the
## forced store failure and its refund, the round trip, persistence, the
## rank grant, the dormant row's own callable, and the gated page.
func _purchase() -> void:
	var runner := MissionRunner.of(self)
	var world_path := test_dir.path_join("world.json")
	var store_path := test_dir.path_join("cars.json")
	CreditsLedger.path_override = ledger_path
	CampaignStore.path_override = campaign_path
	DirAccess.remove_absolute(ledger_path)
	# The world record BEFORE the pad loads: a path without a record forces
	# the first-run map open, the tree paused under it (world_map.gd).
	WorldStore.set_spawn("eifel_ring", "E8.1", world_path)
	WorldStore.path_override = world_path
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	var car: ArcadeCar = scene.get_node("Car")
	var garage: Garage = scene.get_node("Garage")
	ok(WorldStore.has_record(world_path) and not paused and not (scene.get_node("WorldMap") as WorldMap).is_open, "the pad loads over a world record of the test's own: no forced map, the tree runs")
	runner.campaign.state = CampaignStore.defaults()
	runner.campaign.reconcile(LicenceExams.LICENCE_L1)
	runner.configure(car, scene.get_node("HUD"))
	var table := Dealership.read()
	var price := Dealership.price_of(table, "boxster_986")
	var ledger := CreditsLedger.new()
	var spends: Array = []
	var refunds: Array = []
	var on_spent := func(t: Dictionary): spends.append(t)
	var on_earned := func(t: Dictionary): refunds.append(t)
	runner.credits.spent.connect(on_spent)
	runner.credits.earned.connect(on_earned)

	# The dormancy flag, and the page before any obligations ledger is wired
	# (the credits ledger alone): no BUY row, the terms as text.
	# was "DEALERSHIP  —  CREDITS: 0 ... wired to the test's ledger" and "one
	# BUY row per table entry in file order".
	ok(Garage.CREDITS_BUY_ENABLED == false, "the dormancy flag: Garage.CREDITS_BUY_ENABLED is false, the shipped state (ruling 16036083: the credits BUY row dormant, not deleted)")
	ok(ObligationsLedger.path_override == "" and ObligationsLedger.active_path() == "", "the obligations ledger is gated here; the credits one is wired - the two wirings are independent")
	garage.show_page(Garage.Page.CAR)
	var rows := garage.page_rows()
	var text := garage.page_text()
	ok(text.contains("DEALERSHIP") and not text.contains("CREDITS:") and text.contains("trades by TROC: barter, not debit") and text.contains("The credits BUY row is dormant") and text.contains("general dealership E4.1") and not text.contains("Last purchase") and not text.contains("Last trade"), "the CAR page carries the dealership WITHOUT a credits balance, in TROC words, no purchase or trade yet (was: DEALERSHIP  —  CREDITS: 0)")
	var listed := rows.is_empty() and text.contains("No obligations ledger this run (the store is off): the terms are listed, nothing can be traded.") and not text.contains("the prices are listed")
	for entry: Dictionary in table.cars:
		listed = listed and text.contains("%s (%s): the dealer accepts %s." % [Dealership.car_name(entry.car_id), entry.car_id, entry.terms[0].accepts]) and not text.contains("%d credits" % entry.price_credits)
	ok(listed, "with a credits ledger wired and no obligations ledger: no row at all, the terms listed as text, no price anywhere (was: one BUY row per table entry)")

	# The obligations ledger wired, holding nothing: the BARTER rows, greyed.
	ObligationsLedger.path_override = obligations_path
	garage.show_page(Garage.Page.CAR)
	rows = garage.page_rows()
	text = garage.page_text()
	ok(rows.size() == 3 and rows[0].id == "fd_1073" and rows[1].id == "boxster_986" and rows[2].id == "fd_2000" and not text.contains("No obligations ledger this run") and not text.contains("CREDITS:"), "one BARTER row per table entry in file order (was: one BUY row)")
	var greyed := rows.size() == 3
	for i in mini(rows.size(), 3):
		var entry: Dictionary = table.cars[i]
		# was label "BUY — <name> — <n> credits", the hint the basis and "You
		# hold 0 credits: <n> short".
		greyed = greyed and rows[i].kind == "barter_car" and not rows[i].enabled and rows[i].label == "BARTER — %s — for %s" % [Dealership.car_name(entry.car_id), entry.terms[0].accepts] and rows[i].hint == "The dealer accepts: %s. You hold no obligations the desk accepts." % entry.terms[0].accepts and not rows[i].hint.contains(entry.basis) and not rows[i].hint.contains("credits")
	ok(greyed, "with no held obligation every row is greyed: the desk's own words on the label, the terms and what is held in the hint - not the basis, no price (was: the price on the label, the basis and the shortfall in the hint)")
	ok(not garage.activate_row(1) and not FileAccess.file_exists(ledger_path) and not FileAccess.file_exists(obligations_path) and garage.last_barter_result.is_empty(), "a greyed row does nothing: no file of either ledger")
	var direct := garage.buy_car("boxster_986", world_path, store_path, true, car)
	ok(not direct.bought and direct.reason.contains("short") and direct.transaction.is_empty() and direct.summary.begins_with("1997 Boxster 986 not bought:") and not FileAccess.file_exists(ledger_path) and not FileAccess.file_exists(store_path), "buy_car called directly re-checks: refused short of credits, nothing written (the dormant path's code, intact)")

	# One short: refused; exactly the price: still no BUY row (dormant).
	ledger.earn(price - 1, "job:test")
	# was `page_text().contains("CREDITS: <price - 1>") and not rows[1].enabled
	# and rows[1].hint.contains("1 short")`: the greyed row's guard is asked
	# of buy_car itself, the page shows no balance.
	ok(garage.buy_car("boxster_986", world_path, store_path, true, car).reason == "1 credits short (%d of %d)" % [price - 1, price], "one credit short: buy_car refuses and says 1 short (was: the BUY row greyed, saying 1 short)")
	ledger.earn(1, "job:test")
	garage.show_page(Garage.Page.CAR)
	rows = garage.page_rows()
	# was `rows[1].enabled and hint.contains("You hold <price> credits.")`,
	# "exactly the price: the Boxster's row is live".
	ok(rows.size() == 3 and rows.all(func(r: Dictionary): return r.kind == "barter_car" and not r.enabled) and not garage.page_text().contains("CREDITS:") and not garage.page_text().contains("%d credits" % price), "exactly the price on hand and DORMANT: no BUY row appears, the BARTER rows stay greyed, the balance shown nowhere (was: the Boxster's BUY row live)")

	# Refusals before any write.
	ok(garage.buy_car("fd_1001", world_path, store_path, true, car).reason.contains("does not sell") and garage.buy_car("nobody", world_path, store_path, true, car).reason.contains("does not sell"), "a car the table does not sell (fd_1001, an unknown id) is refused")
	ok(garage.buy_car("boxster_986", "", store_path, true, car).reason == "no world record this run", "no world record: refused")
	ok(garage.buy_car("fd_1073", world_path, store_path, true, car).reason.contains("short"), "the dearer car: refused short")
	ledger.load_state()
	ok(ledger.balance() == price and ledger.transactions().size() == 2 and spends.is_empty() and not FileAccess.file_exists(store_path), "every refusal wrote nothing")

	# The forced store-write failure AFTER the spend: the refund.
	var bad_store := test_dir.path_join("cars_dir")
	DirAccess.make_dir_recursive_absolute(bad_store)
	var failed := garage.buy_car("boxster_986", world_path, bad_store, true, car)
	ok(not failed.bought and failed.reason.contains("could not be written") and failed.reason.contains("refunded") and failed.transaction == {"seq": 3, "kind": "spend", "amount": price, "reason": "car:boxster_986"} and failed.refund == {"seq": 4, "kind": "earn", "amount": price, "reason": "refund:car:boxster_986"}, "a store write that fails after the spend: the debit committed, then refunded exactly, reason refund:car:<id>")
	ledger.load_state()
	ok(ledger.balance() == price and ledger.transactions().size() == 4 and spends.size() == 1 and refunds.size() == 1 and not Dealership.purchased(ledger.transactions(), "boxster_986"), "the ledger sums back: the balance as before, four entries, one spent and one earned signal, the car not owned")
	ok(WorldStore.load_driver(world_path).active_car == "" and not FileAccess.file_exists(store_path), "nothing selected, no entry")
	garage.show_page(Garage.Page.CAR)
	# was `page_rows()[1].enabled and kind == "buy_car" and
	# contains("CREDITS: <price>")`, "the row is live again after the refund".
	ok(garage.page_rows().size() == 3 and garage.page_rows()[1].id == "boxster_986" and garage.page_rows()[1].kind == "barter_car" and not garage.page_text().contains("OWNED  1997 Boxster 986") and ledger.balance() == price, "after the refund the car is not owned: its row is back on the page, the BARTER row (was: the BUY row live again, the balance on the heading)")
	DirAccess.remove_absolute(bad_store)

	# The round trip through the store: buy_car with the test's paths, the
	# store kept (the shipped row passes OdometerStore.enabled(), false
	# headless; the row itself is driven below).
	var bought := garage.buy_car("boxster_986", world_path, store_path, true, car)
	ok(bought.bought and bought.reason == "" and bought.summary == "1997 Boxster 986 bought for %d credits." % price and bought.transaction == {"seq": 5, "kind": "spend", "amount": price, "reason": "car:boxster_986"} and bought.refund.is_empty(), "bought: the spend recorded with reason car:<id>")
	ledger.load_state()
	ok(ledger.balance() == 0 and ledger.transactions().size() == 5 and spends.size() == 2 and refunds.size() == 1, "the balance debited exactly once: zero")
	var stored: Dictionary = OdometerStore._cars(OdometerStore._read(store_path)).get("boxster_986", {})
	ok(bought.entry == FirstCar.default_entry(), "the entry written is FirstCar.default_entry: a new car's defaults (%s)" % str(bought.entry.keys()))
	ok(stored.get("odometer_m") == 0.0 and stored.get("fuel_l") == 64.0, "the entry in cars.json: 0 m, the tank its config's 64 L (%s)" % str(stored))
	var read_back := Garage.stored_entry("boxster_986", store_path)
	var new_car := Garage.stored_entry("no_such_car", store_path)
	ok(read_back == new_car, "read back through the store the entry is a new car's: 0 km, a full tank, nothing worn, the dashboard and the battery defaults, unlicensed (%s vs %s)" % [str(read_back), str(new_car)])
	ok(OdometerStore.load_licence("boxster_986", store_path).level == LicenceExams.LICENCE_NONE, "the new car's driver starts unlicensed in its own entry (FirstCar's rule)")
	ok(WorldStore.load_driver(world_path).active_car == "boxster_986", "active_car set")
	ok(Dealership.purchased(ledger.transactions(), "boxster_986") and not runner.campaign.owns_car("boxster_986"), "owned by the log, not by the ladder (no chief credential)")
	garage.show_page(Garage.Page.CAR)
	rows = garage.page_rows()
	text = garage.page_text()
	ok(rows.size() == 2 and rows[0].id == "fd_1073" and rows[1].id == "fd_2000" and text.contains("OWNED  1997 Boxster 986 (boxster_986): bought here for %d credits." % price) and text.contains("SELECTED  1997 Boxster 986 (boxster_986): bought at the dealership") and not text.contains("CREDITS:") and rows.all(func(r: Dictionary): return r.kind == "barter_car"), "the CAR page: OWNED and SELECTED lines by the credits log (the dormant path's semantics kept), no row for it, the other two still on offer as BARTER rows (was: BUY rows, CREDITS: 0)")
	ok(garage.buy_car("boxster_986", world_path, store_path, true, car).reason == "already owned" and ledger.transactions().size() == 5, "buying it again is refused: already owned, nothing written")
	var bytes := read_text(store_path)
	ok(garage.buy_car("boxster_986", world_path, store_path, true, car).transaction.is_empty() and read_text(store_path) == bytes, "and the entry is not touched")

	# Persistence across reload.
	var persisted := CreditsLedger.new()
	persisted.load_state()
	ok(persisted.balance() == 0 and persisted.problems.is_empty() and persisted.transactions()[4].reason == "car:boxster_986" and Dealership.purchased(persisted.transactions(), "boxster_986"), "reloaded from disk: the purchase stands")
	var on_disk: Dictionary = JSON.parse_string(read_text(ledger_path))
	ok(on_disk.balance == 0 and on_disk.transactions.size() == 5 and on_disk.transactions[2].kind == "spend" and on_disk.transactions[3].kind == "earn" and on_disk.transactions[4].kind == "spend", "the file: earn, earn, spend, refund earn, spend; balance 0")

	# A rank grant: OWNED by promotion, not for sale to its owner.
	runner.campaign.state.rewards["test_driver"] = true
	garage.show_page(Garage.Page.CAR)
	rows = garage.page_rows()
	# was `kind == "buy_car"`, "... and no BUY row"; the OWNED line said
	# "listed at <n> credits, not for sale to its owner".
	var buy_rows: Array = rows.filter(func(r: Dictionary): return r.kind == "barter_car")
	var take_rows: Array = rows.filter(func(r: Dictionary): return r.kind == "take_reward")
	ok(buy_rows.size() == 1 and buy_rows[0].id == "fd_2000" and take_rows.size() == 1 and take_rows[0].id == "fd_1073" and garage.page_text().contains("OWNED  Customised 1973 Porsche 911 Carrera RS 2.7 Coupe (fd_1073): granted at promotion; not for trade to its owner.") and not garage.page_text().contains("listed at"), "a rank-granted car shows OWNED by promotion (its TAKE row as before) and no BARTER row, no price on its line (was: no BUY row, listed at 60000 credits)")
	ok(garage.buy_car("fd_1073", world_path, store_path, true, car).reason == "already owned", "and cannot be bought")
	runner.campaign.state.rewards["test_driver"] = false

	# The dormant row's own callable: _buy_car, called as the BUY row would
	# (the store off headless: no entry, the rest of the flow).
	# was: the shipped row driven through activate_row - no row reaches it
	# while CREDITS_BUY_ENABLED is false.
	ledger.earn(Dealership.price_of(table, "fd_2000"), "job:big")
	garage.show_page(Garage.Page.CAR)
	rows = garage.page_rows()
	var index := rows.find_custom(func(r: Dictionary): return r.kind == "buy_car")
	garage._buy_car("fd_2000")
	ok(index == -1, "the FD-2000's price on hand and no BUY row to press: _buy_car is called directly, the dormant row's callable (was: the row live, Enter buys)")
	ledger.load_state()
	ok(garage.last_purchase_result.bought and garage.last_purchase_result.entry.is_empty() and ledger.balance() == 0 and ledger.transactions()[-1] == {"seq": 7, "kind": "spend", "amount": 100000, "reason": "car:fd_2000"} and WorldStore.load_driver(world_path).active_car == "fd_2000", "the dormant row's purchase (was: the row's): the spend committed, active_car fd_2000, no entry (the store is off headless: cars.json in the data folder untouched)")
	ok(garage.page == Garage.Page.CAR and garage.page_text().contains("Last purchase: FD-2000 bought for 100000 credits.") and garage.page_text().contains("OWNED  FD-2000 (fd_2000): bought here") and garage.page_text().contains("SELECTED  FD-2000 (fd_2000)") and garage.page_rows().size() == 1 and garage.page_rows()[0].id == "fd_1073" and garage.page_rows()[0].kind == "barter_car", "the page rebuilt: the last purchase named, FD-2000 owned and selected, one car left on offer, a BARTER row (was: for sale)")
	ok(stamp(real_path) == real_before, "the driver's own credits.json is as it was")

	# The credits ledger gated, the obligations one still wired: the BARTER
	# rows stand on their own wiring (the dormant log's purchases unread).
	CreditsLedger.path_override = ""
	garage.show_page(Garage.Page.CAR)
	ok(garage.page_rows().size() == 3 and garage.page_rows().all(func(r: Dictionary): return r.kind == "barter_car" and not r.enabled) and not garage.page_text().contains("bought here") and not garage.page_text().contains("No obligations ledger this run"), "the credits ledger gated and the obligations ledger wired: three greyed BARTER rows, no purchase read - the two wirings are independent")
	ok(garage.barter_car("boxster_986", world_path, store_path, true, car).reason == "the dealer accepts one held obligation: 1 more needed (0 of 1 held)" and garage.barter_car("fd_2000", world_path, store_path, true, car).reason == "the dealer accepts two held obligations: 2 more needed (0 of 2 held)" and not FileAccess.file_exists(obligations_path), "barter_car called directly re-checks: refused with nothing held, nothing written")
	# Gated: no rows, the terms as text (menu_test's rowless CAR page).
	# was `contains("No ledger this run") and contains("FD-2000 (fd_2000):
	# 100000 credits.") and contains("CREDITS: 0")`, the prices as text.
	ObligationsLedger.path_override = ""
	garage.show_page(Garage.Page.CAR)
	ok(garage.page_rows().is_empty() and garage.page_text().contains("No obligations ledger this run (the store is off): the terms are listed, nothing can be traded.") and garage.page_text().contains("FD-2000 (fd_2000): the dealer accepts two held obligations.") and garage.page_text().contains("1997 Boxster 986 (boxster_986): the dealer accepts one held obligation.") and not garage.page_text().contains("CREDITS:") and not garage.page_text().contains("FD-2000 (fd_2000): 100000 credits."), "gated (the stores off, no override): the terms listed as text, no row, no price line (was: the prices listed as text, no BUY row)")
	ok(garage.barter_car("fd_1073", world_path, store_path, true, car).reason == "no obligations ledger this run (the store is off)" and stamp(real_obligations_path) == real_obligations_before and not FileAccess.file_exists(obligations_path), "gated, barter_car refuses before any write; this section never wrote an obligations file")
	ok(garage.buy_car("fd_1073", world_path, store_path, true, car).reason.contains("no ledger") and stamp(real_path) == real_before, "gated, buy_car refuses before any write")
	CreditsLedger.path_override = ledger_path
	runner.credits.spent.disconnect(on_spent)
	runner.credits.earned.disconnect(on_earned)
	WorldStore.path_override = ""
	scene.queue_free()
	await process_frame
	for file in ["credits.json", "campaign.json", "world.json", "cars.json"]:
		DirAccess.remove_absolute(test_dir.path_join(file))

# =============================================================================
#  The Ring
# =============================================================================

func _ring() -> void:
	var runner := MissionRunner.of(self)
	CreditsLedger.path_override = ledger_path
	ObligationsLedger.path_override = obligations_path
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
	var owed := ObligationsLedger.new()
	runner.configure(car, scene.get_node("HUD"))
	ok(car.road_profile is WorldRoadProfile and runner.environment_matches("ring") and not runner.environment_matches("pad"), "the Ring's car stands on a world profile: the ring is the jobs' environment")

	# Not enrolled: the board is listed and locked.
	runner.campaign.state = CampaignStore.defaults()
	garage.show_page(Garage.Page.JOBS)
	var rows := garage.page_rows()
	var locked := rows.size() == JOB_IDS.size()
	for i in mini(rows.size(), JOB_IDS.size()):
		locked = locked and rows[i].id == JOB_IDS[i] and not rows[i].enabled and rows[i].hint.contains("Locked: Requires junior")
	# was `contains("CREDITS: 0")` -> the TROC board's own lines.
	ok(locked and not runner.start(PASS_JOB) and garage.page_text().contains("JOB BOARD") and not garage.page_text().contains("CREDITS:") and garage.page_text().contains("The board trades by TROC") and garage.page_text().contains("Nothing owed to you or by you yet."), "a driver who is not enrolled sees the four jobs locked and cannot start one; the board reads TROC, nothing owed either way (was: CREDITS: 0)")

	# Enrolled: every job is open, no chain.
	runner.campaign.reconcile(LicenceExams.LICENCE_L1)
	garage.show_page(Garage.Page.JOBS)
	rows = garage.page_rows()
	var open := rows.size() == JOB_IDS.size()
	for i in mini(rows.size(), JOB_IDS.size()):
		var job: Dictionary = runner.catalog[JOB_IDS[i]]
		open = open and rows[i].kind == "job" and rows[i].id == JOB_IDS[i] and rows[i].enabled and rows[i].label == "%s — %s  —  courier" % [JOB_IDS[i], job.title] and not rows[i].label.contains("credits") and rows[i].hint.contains("Enter to start — ring") and rows[i].hint.contains(job.briefing) and rows[i].hint.ends_with("\nPosted by %s — on delivery they owe you: %s — tip: %s" % [JOB_POSTERS[JOB_IDS[i]], JOB_OWED[JOB_IDS[i]], JOB_OFFERS[JOB_IDS[i]]])
	# was label "<id> — <title>  —  courier  —  <n> credits", "id, title, kind, pay".
	ok(open, "an enrolled junior sees the four jobs open on the Ring: id, title, kind, no pay on the label (was: —  <n> credits), the poster, what they will owe and their tip in the hint, none marked done")
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
	ok(not FileAccess.file_exists(obligations_path) and not FileAccess.file_exists(ledger_path), "no ledger file, obligations or credits, before the first job is delivered")
	var job: Dictionary = runner.catalog[PASS_JOB]
	var pass_record := {"id": "OBL-0001", "creditor": "player", "debtor": "DISPATCH-E2.4", "owed": "one parcel delivery: Paddock station to Döttinger Höhe", "kind": "delivery", "origin": "job:%s/episode-%d" % [PASS_JOB, runner._episode + 1], "status": "open", "redemptions": [], "transfers": []}
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
	ok(result.get("passed", false) and result.get("reason") == "course complete" and result.get("medal") == "gold", PASS_JOB + " shipped controls drive the actual Ring car to a pass (" + runner.result_text() + ")")
	var measured: float = result.get("time_s", 0.0)
	var bands: Dictionary = job.scoring.medal_times
	ok(absf(measured - job.provenance.medals.scripted_time_s) < 0.000001, PASS_JOB + " measurement matches recorded provenance")
	ok(measured > 0 and measured <= job.scoring.time_limit_s and bands.gold == ceil(measured * 1.05) and bands.silver == ceil(measured * 1.25) and bands.bronze == ceil(measured * 1.50), PASS_JOB + " medal bands derive from this real pass inside the limit")
	ok(absf((car.odometer_m - odometer_before) - job.provenance.route.driven_m) < 0.1 and airborne == 0, PASS_JOB + " drove its recorded distance with a wheel on the road every tick")
	ok(car.global_position.distance_to(Vector3(job.episode[5].position[0], job.episode[5].position[1], job.episode[5].position[2])) <= STATION_RADIUS_M + 1.0, PASS_JOB + " ends at the delivery station's gate")
	# was `result.get("credits") == int(job.reward_credits)`.
	ok(result.get("obligation") == pass_record and not result.has("credits") and result.get("saved", false) and runner.result_text().ends_with(" — owed by DISPATCH-E2.4: one parcel delivery: Paddock station to Döttinger Höhe"), "the pass leaves the poster owing: DISPATCH-E2.4's obligation in the result and in its text (was: pays the job's reward in credits)")
	print("  the record: " + JSON.stringify(result.get("obligation", {})))
	owed.load_state()
	# was `ledger.balance() == reward and transactions() == [the earn]`: the
	# credits ledger is never written by a job now.
	ok(owed.open_view("", "DISPATCH-E2.4") == [pass_record] and owed.open_view("player") == [pass_record] and owed.records().size() == 1 and owed.problems.is_empty() and not FileAccess.file_exists(ledger_path), "the obligation lands: the one open record on disk, owed by DISPATCH-E2.4 to the player; the job's pay never created credits.json (was: the credits land, one transaction)")
	ok(runner.pay_last_result() == {} and read_text(obligations_path).count("\"id\"") == 1, "and cannot be collected twice")
	ok(not Input.is_action_pressed("accelerate") and not Input.is_action_pressed("brake") and runner.get_child_count() == 0 and not runner.is_physics_processing(), "inputs released, the runner inert again")

	# A real failure: the shipped controls, a deadline the route cannot meet.
	# After the pass, on the same car (warm tyres, less fuel): the deadline
	# fails it whatever line the controls now drive.
	# was `read_text(ledger_path)`: the pay's file is the obligations one.
	var paid_bytes := read_text(obligations_path)
	var spawn_origin := car.get_spawn_transform().origin
	var shipped_scoring: Dictionary = runner.catalog[FAIL_JOB].scoring
	runner.catalog[FAIL_JOB].scoring = {"time_limit_s": FAIL_DEADLINE_S, "medal_times": {"gold": FAIL_DEADLINE_S * 0.25, "silver": FAIL_DEADLINE_S * 0.5, "bronze": FAIL_DEADLINE_S * 0.75}, "failure_conditions": []}
	ok(runner.start(FAIL_JOB, true), FAIL_JOB + " starts scripted on the Ring car")
	ok(not garage.can_open() and runner.is_physics_processing(), "the job owns the driving context")
	for frame in range(int(FAIL_DEADLINE_S * 60) + 120):
		await physics_frame
		if runner.active.is_empty():
			break
	ok(runner.active.is_empty() and not runner.last_result.get("passed", true) and runner.last_result.get("reason") == "time limit" and runner.last_result.get("obligation") == {} and not runner.last_result.has("credits"), FAIL_JOB + " fails on the actual Ring car: the deadline passes, no obligation in the result (was: credits == 0)")
	ok(car.global_position.distance_to(spawn_origin) > 100.0, FAIL_JOB + " shipped controls drove the car away from the pit before the deadline")
	ok(read_text(obligations_path) == paid_bytes and runner.pay_last_result() == {} and read_text(obligations_path) == paid_bytes and not FileAccess.file_exists(ledger_path), "the failed job creates no obligation: the obligations file's bytes are the same, asked again or not (was: no credits written)")
	ok(not Input.is_action_pressed("accelerate") and not Input.is_action_pressed("brake") and not Input.is_action_pressed("steer_left") and not Input.is_action_pressed("steer_right"), "script inputs released after the failure")
	runner.catalog[FAIL_JOB].scoring = shipped_scoring
	ok(runner.campaign.state.results[FAIL_JOB].attempts == 1 and runner.campaign.state.results[FAIL_JOB].medal == "", "the failed attempt is counted and completes nothing")

	# The board afterwards.
	garage.show_page(Garage.Page.JOBS)
	rows = garage.page_rows()
	# was `contains("CREDITS: 95") and contains("Payments received: 1") and
	# contains("job:JOB-01")`.
	var board := garage.page_text()
	print("  the board:\n    " + board.replace("\n", "\n    "))
	ok(board.count("Owed to you by") == 1 and board.contains("Owed to you by DISPATCH-E2.4: one parcel delivery: Paddock station to Döttinger Höhe") and not board.contains("You owe") and not board.contains("Nothing owed") and not board.contains("CREDITS:") and not board.contains("Payments received"), "the board shows what the delivery left owed: DISPATCH-E2.4's parcel delivery, owed to the driver; the driver owes nothing yet (was: the credits earned)")
	ok(rows[0].id == PASS_JOB and rows[0].label.begins_with("DONE — " + PASS_JOB) and rows[0].hint.contains("gold") and rows[0].hint.contains("1 attempts") and rows[0].enabled, "the delivered job is marked done and can be driven again")
	ok(rows[1].id == FAIL_JOB and not rows[1].label.begins_with("DONE") and rows[1].hint.contains("not yet delivered") and rows[1].hint.contains("1 attempts") and rows[1].enabled, "the failed job is not")
	var persisted := CampaignStore.new()
	persisted.load_state()
	ok(persisted.state.rank == "junior" and persisted.state.results[PASS_JOB].medal == "gold" and persisted.state.results[FAIL_JOB].medal == "" and not persisted.state.rewards.test_driver, "the campaign keeps both results; a job promotes nobody")
	# was funded by the job's pay (JOB-01's 95 credits); jobs pay obligations
	# now, so the fuel test stakes its own credits: the same 95, the fuel
	# arithmetic below bit-exact as it was.
	ok(not FileAccess.file_exists(ledger_path) and ledger.earn(95, "staked-for-fuel-test") == {"seq": 1, "kind": "earn", "amount": 95, "reason": "staked-for-fuel-test"} and ledger.balance() == 95, "the fuel test's own stake: 95 credits earned by the test into a credits file no job wrote (was funded by the job's pay)")
	await _fuel(scene, car, runner, ledger)
	# was ["campaign.json", "credits.json"], the two stores.
	ok(files() == PackedStringArray(["campaign.json", "credits.json", "obligations.json"]), "the test's folder holds the three stores it opted into, no temporary file (was two: the obligations file is the jobs' pay now)")
	ok(read_text(obligations_path) == paid_bytes, "paid fuel never touched the obligations file: its bytes are the job's one record still")
	root.remove_child(scene)
	scene.free()
	await physics_frame

# =============================================================================
#  Paid fuel (ECON-3)
# =============================================================================

## The Ring's shipped Refuel node, wired to the runner's ledger (the test's
## file, the test's own 95-credit stake in it; was the job's pay, which is
## an obligation now): the dry run away from every station,
## the paid fill at E2.4 by the ceil rule, the line's texts, the
## unaffordable fill, the exact-balance fill, and the gated (unwired) free
## fill.
func _fuel(scene: Node, car: ArcadeCar, runner: MissionRunner, ledger: CreditsLedger) -> void:
	var refuel: Refuel = scene.get_node("Refuel")
	var station := Buildings.record(FUEL_STATION_ID)
	var at := station.position()
	var spends: Array = []
	var on_spent := func(t: Dictionary): spends.append(t)
	runner.credits.spent.connect(on_spent)
	ok(Refuel.LITRE_PRICE_CREDITS == 2 and Refuel.fill_cost(20.0) == 88 and Refuel.fill_cost(0.0) == 128 and Refuel.fill_cost(63.7) == 1 and Refuel.fill_cost(64.0) == 0 and Refuel.fill_cost(70.0) == 0 and Refuel.fill_cost(63.5) == 1 and Refuel.fill_cost(63.4) == 2, "the price: 2 credits a litre, the cost the gap rounded up to the whole credit (a full fill 128, 0.3 L 1, 0.6 L 2, a full tank 0)")
	ok(Refuel.hint_line(88, 95, false) == Refuel.HINT_TEXT and Refuel.hint_line(88, 95, true) == "FUEL STATION near — hold U to fill (2 cr/L — you hold 95 cr)" and Refuel.hint_line(88, 7, true) == "FUEL STATION near — hold U to fill (2 cr/L — need ~88 cr, you hold 7 cr)" and Refuel.hint_line(88, 88, true).contains("you hold 88 cr") and not Refuel.hint_line(88, 88, true).contains("need"), "the line: the old text unwired; the price and the balance wired; the shortfall when the balance cannot cover the gap; exactly enough is enough")
	ok(refuel.wired_ledger() == runner.credits and refuel.fill_count == 0 and refuel.paid_credits == 0 and refuel.refused_count == 0, "the Ring's Refuel node is wired to the runner's ledger; the jobs filled and paid nothing")

	# Away from every station: the dry run.
	car.reset_to(Transform3D(car.global_basis, Vector3(at.x + 100.0, 0.0, at.y)))
	_engine_off(car)
	car.fuel_l = PART_TANK_L
	for i in 20:
		await physics_frame
	var bytes := read_text(ledger_path)
	Input.action_press(Refuel.ACTION)
	for i in 30:
		await physics_frame
	Input.action_release(Refuel.ACTION)
	ok(refuel.near == null and not refuel.hint_visible() and refuel.fill_count == 0 and refuel.paid_credits == 0 and refuel.refused_count == 0 and car.fuel_l == PART_TANK_L and read_text(ledger_path) == bytes, "100 m off E2.4 the key held 30 ticks fills nothing, pays nothing, the ledger untouched")

	# At the station with the staked 95 credits (was the job's), 44 L short: 88 credits.
	car.reset_to(Transform3D(car.global_basis, Vector3(at.x, 0.0, at.y)))
	_engine_off(car)
	car.fuel_l = PART_TANK_L
	for i in 20:
		await physics_frame
	ok(refuel.near == station and refuel.hint_visible() and car.fuel_l == PART_TANK_L and refuel.hint_text() == "FUEL STATION near — hold U to fill (2 cr/L — you hold 95 cr)", "at E2.4 with 95 credits and 44 L short: the line names the price and the balance")
	Input.action_press(Refuel.ACTION)
	await physics_frame
	ok(car.fuel_l == ArcadeCar.FUEL_TANK_CAPACITY_L and refuel.fill_count == 1 and refuel.paid_credits == 88 and refuel.refused_count == 0, "the first tick with the key held: the tank filled to capacity, 88 credits paid")
	ledger.load_state()
	ok(ledger.balance() == 7 and ledger.transactions().size() == 2 and ledger.transactions()[1] == {"seq": 2, "kind": "spend", "amount": 88, "reason": "fuel"} and spends.size() == 1 and spends[0].amount == 88, "the ledger: one spend of 88 with reason fuel after the test's stake (was the job's pay), 7 credits left, one spent signal")
	for i in 30:
		await physics_frame
	Input.action_release(Refuel.ACTION)
	ledger.load_state()
	ok(refuel.fill_count == 1 and refuel.paid_credits == 88 and ledger.balance() == 7 and ledger.transactions().size() == 2, "held on at a full tank 30 ticks: nothing more filled, nothing more paid")
	ok(refuel.hint_text() == "FUEL STATION near — hold U to fill (2 cr/L — you hold 7 cr)", "the line follows the balance")
	car.fuel_l = 63.7
	Input.action_press(Refuel.ACTION)
	await physics_frame
	Input.action_release(Refuel.ACTION)
	ledger.load_state()
	ok(car.fuel_l == ArcadeCar.FUEL_TANK_CAPACITY_L and refuel.fill_count == 2 and refuel.paid_credits == 89 and ledger.balance() == 6 and ledger.transactions()[-1].amount == 1, "a 0.3 L gap costs 1 credit: the station rounds up to the whole credit")

	# Unaffordable: 6 credits, 44 L short.
	car.fuel_l = PART_TANK_L
	await physics_frame
	ok(refuel.hint_text() == "FUEL STATION near — hold U to fill (2 cr/L — need ~88 cr, you hold 6 cr)", "short of credits the line says the shortfall")
	bytes = read_text(ledger_path)
	Input.action_press(Refuel.ACTION)
	for i in 30:
		await physics_frame
	Input.action_release(Refuel.ACTION)
	ledger.load_state()
	ok(car.fuel_l == PART_TANK_L and refuel.fill_count == 2 and refuel.paid_credits == 89 and refuel.refused_count == 30 and read_text(ledger_path) == bytes and ledger.balance() == 6 and spends.size() == 2, "the unaffordable fill: no fuel, no debit, every one of the 30 ticks refused (all or nothing: no partial fill)")
	car.fuel_l = 62.5
	Input.action_press(Refuel.ACTION)
	await physics_frame
	Input.action_release(Refuel.ACTION)
	ledger.load_state()
	ok(car.fuel_l == ArcadeCar.FUEL_TANK_CAPACITY_L and refuel.paid_credits == 92 and ledger.balance() == 3, "1.5 L short with 6 credits: 3 paid, 3 left")
	car.fuel_l = 60.5
	Input.action_press(Refuel.ACTION)
	await physics_frame
	Input.action_release(Refuel.ACTION)
	ledger.load_state()
	ok(car.fuel_l == 60.5 and refuel.refused_count == 31 and ledger.balance() == 3 and refuel.hint_text().contains("need ~7 cr, you hold 3 cr"), "3.5 L short with 3 credits: refused, 7 needed")

	# Unwired: the ledger gated, the fill is free and the line the old text.
	CreditsLedger.path_override = ""
	bytes = read_text(ledger_path)
	await physics_frame
	ok(refuel.wired_ledger() == null and refuel.hint_text() == Refuel.HINT_TEXT, "the ledger gated: no ledger wired, the line is exactly the old text")
	Input.action_press(Refuel.ACTION)
	await physics_frame
	Input.action_release(Refuel.ACTION)
	ok(car.fuel_l == ArcadeCar.FUEL_TANK_CAPACITY_L and refuel.fill_count == 4 and refuel.paid_credits == 92 and refuel.refused_count == 31 and read_text(ledger_path) == bytes and stamp(real_path) == real_before, "the fill is free: the tank full, nothing paid, the file and the driver's own untouched (the grace seam)")
	CreditsLedger.path_override = ledger_path
	runner.credits.spent.disconnect(on_spent)
	Input.action_release(Refuel.ACTION)


## The engine off, honestly (the refuel test's rule): engine_running false
## AND the crank at rest, so the idle burn cannot move the tank under the
## bit-exact assertions.
func _engine_off(car: ArcadeCar) -> void:
	car.engine_running = false
	car.engine_omega = 0.0
