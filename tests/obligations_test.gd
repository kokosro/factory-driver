extends SceneTree
## TROC-1 slice 1 proof: the obligations ledger, the store alone (no UI).
## TROC-1 slice 2 adds the runner corner: a passed posted job creates the
## poster's obligation to the player, once per episode, and the JOBS page's
## view shows it. The slice-1 seed gap is closed in slice 2: obligations.json
## is in DataDir.SEEDED_FILES (the pin at the end of the failed write flipped).
## TROC-1 slice 3 adds the barter corner: the CAR page's dealership trades a
## car for the obligations the driver holds (Garage.barter_car, the BARTER
## rows) - the fresh-driver arc from a delivered job to an owned car, the
## empty boot, the count, the reversal, and the dormant credits buy_car
## refusing a traded car.
## Run via tests/run_tests.sh, or:
##
##   godot --headless --path . --import
##   godot --headless --fixed-fps 60 --path . --script res://tests/obligations_test.gd
##
## The store is pinned off (FD_TELEMETRY=0); every file is this process's
## own, under TMPDIR, never the driver's data folder (held at the end: the
## real obligations.json is as it was). The record shape, the one-shot
## redemption, the cancellation, the creditor transfers, the derived open
## views, the round trip, the versions, the determinism, the corruption
## tolerance and the failed write; then the runner on the pad, a posted
## fixture of this test's own passed by ticks; then the garage on the pad
## over a world record, a cars file and a campaign file of the test's own.
var failures := 0
var checks := 0
var test_dir := (OS.get_environment("TMPDIR") if not OS.get_environment("TMPDIR").is_empty() else "/tmp").path_join("factory-driver-obligations-%d" % OS.get_process_id())
var ledger_path := test_dir.path_join("obligations.json")
var twin_path := test_dir.path_join("obligations-twin.json")
var real_path := ""
var real_before := ""

## A well-formed open record, as the store writes its first one.
const GOOD := {"id": "OBL-0001", "creditor": "E2.2", "debtor": "player", "owed": "one delivery: Adenau to Döttinger Höhe", "kind": "delivery", "origin": "trade:JOB-01/episode-3", "status": "open", "redemptions": [], "transfers": []}
const REDEMPTION := {"given": "fuel 64 L", "where": "E2.4", "origin": "refuel"}

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

func on_disk() -> Dictionary:
	return JSON.parse_string(read_text(ledger_path))

func stamp(path: String) -> String:
	return "%d:%d" % [FileAccess.get_modified_time(path), read_text(path).length()] if FileAccess.file_exists(path) else "absent"

func files() -> PackedStringArray:
	return DirAccess.get_files_at(test_dir) if DirAccess.dir_exists_absolute(test_dir) else PackedStringArray()

## GOOD with `changes` laid over it; a null value takes the field away.
func record(changes: Dictionary) -> Dictionary:
	var made := GOOD.duplicate(true)
	for key: String in changes:
		if changes[key] == null:
			made.erase(key)
		else:
			made[key] = changes[key]
	return made

func _run() -> void:
	OS.set_environment("FD_TELEMETRY", "0")
	real_path = DataDir.resolve(ObligationsLedger.PATH)
	real_before = stamp(real_path)
	print("-- idle and gated")
	_idle()
	ObligationsLedger.path_override = ledger_path
	print("-- create")
	_create()
	print("-- the one-shot redemption")
	_redeem()
	print("-- cancel")
	_cancel()
	print("-- transfer")
	_transfer()
	print("-- the open views")
	_open_view()
	print("-- the log is the ledger: the round trip")
	_round_trip()
	print("-- versions")
	_versions()
	print("-- determinism")
	_determinism()
	print("-- corruption tolerance")
	_corruption()
	print("-- the failed write")
	_failed_write()
	print("-- the runner creates the poster's obligation (slice 2)")
	await _runner()
	print("-- the dealership barter (slice 3)")
	await _barter()
	print("-- nothing of the driver's was touched")
	ObligationsLedger.path_override = ""
	ok(stamp(real_path) == real_before, "the driver's own obligations.json is as it was before the test (override isolation)")
	for file in files():
		DirAccess.remove_absolute(test_dir.path_join(file))
	DirAccess.remove_absolute(test_dir)
	print("OBLIGATIONS TEST %s: %d checks" % ["PASSED" if failures == 0 else "FAILED", checks])
	quit(0 if failures == 0 else 1)

# =============================================================================
#  Idle and gated
# =============================================================================

func _idle() -> void:
	ok(ObligationsLedger.PATH == "user://obligations.json" and ObligationsLedger.VERSION == 1 and ObligationsLedger.KINDS == ["delivery", "car", "car-part", "material", "favor", "tuna", "fuel-voucher", "anything"] and ObligationsLedger.STATUS == ["open", "settled", "cancelled"], "the store's name, version 1 from birth, the eight kinds and the three states")
	ok(ObligationsLedger.path_override == "" and ObligationsLedger.active_path() == "", "telemetry zero gates the ledger: no path without an override")
	ok(ObligationsLedger.defaults() == {"version": 1, "records": []} and ObligationsLedger.defaults().keys().size() == 2, "the defaults: version 1 and an empty log, no total of any kind")
	var gated := ObligationsLedger.new()
	gated.load_state()
	ok(gated.state == ObligationsLedger.defaults() and gated.records().is_empty() and gated.problems.is_empty() and not gated.newer_file, "gated load reads nothing: the defaults")
	ok(gated.create("E2.2", "player", "one delivery", "delivery", "trade:JOB-01").is_empty() and gated.state == ObligationsLedger.defaults() and gated.redeem("OBL-0001", "fuel", "E2.4", "refuel").is_empty() and gated.cancel("OBL-0001", "void").is_empty() and gated.transfer("OBL-0001", "E2.2", "E2.3", "trade").is_empty() and gated.open_view().is_empty(), "gated create, redeem, cancel and transfer return {} and keep nothing in memory; the view is empty")
	ok(stamp(real_path) == real_before and not DirAccess.dir_exists_absolute(test_dir), "a gated ledger touches no file")

# =============================================================================
#  Create
# =============================================================================

func _create() -> void:
	ok(ObligationsLedger.active_path() == ledger_path, "override enables isolated IO")
	var ledger := ObligationsLedger.new()
	ledger.load_state()
	ok(ledger.state == ObligationsLedger.defaults() and ledger.problems.is_empty() and files().is_empty(), "missing file: the defaults, no problem, nothing written by the read")
	var refused := true
	for bad in ["", "   ", "\n\t"]:
		refused = refused and ledger.create(bad, "player", "one delivery", "delivery", "trade").is_empty()
		refused = refused and ledger.create("E2.2", bad, "one delivery", "delivery", "trade").is_empty()
		refused = refused and ledger.create("E2.2", "player", bad, "delivery", "trade").is_empty()
		refused = refused and ledger.create("E2.2", "player", "one delivery", "delivery", bad).is_empty()
	ok(refused, "create refuses an empty or a blank creditor, debtor, owed thing and origin")
	ok(ledger.create("E2.2", "player", "one delivery", "credits", "trade").is_empty() and ledger.create("E2.2", "player", "one delivery", "Delivery", "trade").is_empty() and ledger.create("E2.2", "player", "one delivery", " ", "trade").is_empty() and ledger.create("player", "player", "one delivery", "delivery", "trade").is_empty() and ledger.create("E2.2", "E2.2", "one delivery", "delivery", "trade").is_empty(), "create refuses a kind that is none of the eight, and a creditor who is the debtor, whoever it is")
	ok(files().is_empty() and ledger.state == ObligationsLedger.defaults() and ledger.problems.is_empty(), "refused creates write no file, keep nothing and publish no problem")
	var first := ledger.create("E2.2", "player", "one delivery: Adenau to Döttinger Höhe", "delivery", "trade:JOB-01/episode-3")
	ok(first == GOOD and first.keys().size() == 9, "the first create returns the record as written: OBL-0001, open, no redemption, no transfer, nine fields")
	ok(on_disk().version == 1 and on_disk().records == [GOOD] and on_disk().keys().size() == 2, "the file holds version and the log, nothing else: no balance, no total")
	ok(FileAccess.file_exists(ledger_path) and not FileAccess.file_exists(ledger_path + ".tmp") and files() == PackedStringArray(["obligations.json"]), "atomic write consumes its temporary file")
	var second := ledger.create("player", "E2.4", "a full tank", "", "trade:JOB-02")
	ok(second.id == "OBL-0002" and second.kind == "anything" and on_disk().records[1].kind == "anything", "a create without a kind writes anything; the id is the record's place")
	var hints := true
	for kind: String in ObligationsLedger.KINDS:
		hints = hints and ObligationsLedger.record_problem(record({"kind": kind})) == ""
	ok(hints and ObligationsLedger.record_problem(GOOD) == "" and ObligationsLedger.record_problem(record({"creditor": "ai:driver-7", "debtor": "ai:driver-9"})) == "", "every kind is a record's; the sides are opaque ids: a record between two AI counterparties is the same record")
	var copy := ledger.records()
	copy[0].owed = "nothing"
	copy[0].redemptions.append(REDEMPTION)
	first.status = "settled"
	ok(ledger.state.records[0] == GOOD, "records() and a returned record are copies: changing them leaves the state as it was")
	DirAccess.remove_absolute(ledger_path)

# =============================================================================
#  The one-shot redemption
# =============================================================================

func _redeem() -> void:
	var ledger := ObligationsLedger.new()
	ledger.create("E2.2", "player", GOOD.owed, "delivery", GOOD.origin)
	ledger.create("E2.3", "player", "a set of tyres", "car-part", "trade:JOB-03")
	var bytes := read_text(ledger_path)
	var refused := true
	for bad in ["", "  "]:
		refused = refused and ledger.redeem("OBL-0001", bad, "E2.4", "refuel").is_empty() and ledger.redeem("OBL-0001", "fuel 64 L", bad, "refuel").is_empty() and ledger.redeem("OBL-0001", "fuel 64 L", "E2.4", bad).is_empty()
	ok(refused and ledger.redeem("OBL-0003", "fuel 64 L", "E2.4", "refuel").is_empty() and ledger.redeem("", "fuel 64 L", "E2.4", "refuel").is_empty() and ledger.redeem("obl-0001", "fuel 64 L", "E2.4", "refuel").is_empty() and read_text(ledger_path) == bytes, "redeem refuses an empty given, where and origin, and an id the log does not hold: the bytes stay")
	var settled := ledger.redeem("OBL-0001", "fuel 64 L", "E2.4", "refuel")
	var expected := record({"status": "settled", "redemptions": [REDEMPTION]})
	ok(settled == expected, "the first redemption closes the obligation: settled, the redemption as given, the record as written")
	ok(ledger.state.records[0] == expected and on_disk().records[0] == expected and on_disk().records[1].status == "open", "in memory and on disk; the other record is still open")
	bytes = read_text(ledger_path)
	ok(ledger.redeem("OBL-0001", "tuna", "E2.3", "gift").is_empty() and read_text(ledger_path) == bytes and ledger.state.records[0] == expected and not FileAccess.file_exists(ledger_path + ".tmp"), "ONE-SHOT: the second redemption is refused, never merged; the record and the bytes are unchanged")
	ok(ledger.cancel("OBL-0002", "the poster left").status == "cancelled" and ledger.redeem("OBL-0002", "tyres", "E2.3", "trade").is_empty() and ledger.state.records[1].redemptions.is_empty() and ledger.problems.is_empty(), "a cancelled obligation is never redeemed; a refused write publishes no problem (problems is the reader's channel)")
	DirAccess.remove_absolute(ledger_path)

# =============================================================================
#  Cancel
# =============================================================================

func _cancel() -> void:
	var ledger := ObligationsLedger.new()
	ledger.create("E2.2", "player", GOOD.owed, "delivery", GOOD.origin)
	ledger.create("E2.3", "player", "a set of tyres", "car-part", "trade:JOB-03")
	var bytes := read_text(ledger_path)
	ok(ledger.cancel("OBL-0001", "").is_empty() and ledger.cancel("OBL-0001", " \t").is_empty() and ledger.cancel("OBL-0009", "void").is_empty() and ledger.cancel("", "void").is_empty() and read_text(ledger_path) == bytes, "cancel refuses an empty origin and an id the log does not hold")
	var cancelled := ledger.cancel("OBL-0001", "trade:JOB-01/abandoned")
	var expected := record({"status": "cancelled", "cancelled_origin": "trade:JOB-01/abandoned"})
	ok(cancelled == expected and cancelled.keys().size() == 10, "cancel writes status cancelled and the one field cancelled_origin, the record as written")
	ok(on_disk().records[0] == expected and ledger.state.records[0] == expected and not on_disk().records[1].has("cancelled_origin"), "in memory and on disk; an open record carries no cancelled_origin")
	bytes = read_text(ledger_path)
	ok(ledger.cancel("OBL-0001", "again").is_empty() and read_text(ledger_path) == bytes and ledger.state.records[0].cancelled_origin == "trade:JOB-01/abandoned", "a second cancel is refused: the first origin stands")
	ok(ledger.redeem("OBL-0002", "tyres", "E2.3", "trade").status == "settled" and ledger.cancel("OBL-0002", "void").is_empty() and ledger.state.records[1].status == "settled" and not ledger.state.records[1].has("cancelled_origin"), "a settled obligation is never cancelled")
	DirAccess.remove_absolute(ledger_path)

# =============================================================================
#  Transfer
# =============================================================================

func _transfer() -> void:
	var ledger := ObligationsLedger.new()
	ledger.create("A", "D", "one delivery", "delivery", "trade:1")
	var bytes := read_text(ledger_path)
	ok(ledger.transfer("OBL-0001", "B", "C", "trade:2").is_empty() and ledger.transfer("OBL-0001", "D", "C", "trade:2").is_empty() and ledger.transfer("OBL-0001", "", "C", "trade:2").is_empty() and read_text(ledger_path) == bytes, "transfer refuses a from who is not the current creditor (the debtor included)")
	ok(ledger.transfer("OBL-0001", "A", "A", "trade:2").is_empty() and ledger.transfer("OBL-0001", "A", "", "trade:2").is_empty() and ledger.transfer("OBL-0001", "A", "  ", "trade:2").is_empty() and read_text(ledger_path) == bytes, "transfer refuses a to that is the from, or empty")
	ok(ledger.transfer("OBL-0001", "A", "D", "trade:2").is_empty() and ledger.transfer("OBL-0001", "A", "B", "").is_empty() and ledger.transfer("OBL-0002", "A", "B", "trade:2").is_empty() and read_text(ledger_path) == bytes, "transfer refuses a to that is the debtor (the two sides are never one id), an empty origin and an id the log does not hold")
	var moved := ledger.transfer("OBL-0001", "A", "B", "trade:2")
	ok(moved.creditor == "B" and moved.debtor == "D" and moved.status == "open" and moved.transfers == [{"from": "A", "to": "B", "origin": "trade:2"}] and on_disk().records[0] == moved, "a transfer reassigns the creditor and writes its entry; the debtor and the status stay")
	ok(ledger.transfer("OBL-0001", "A", "C", "trade:3").is_empty() and ledger.state.records[0].creditor == "B", "the old creditor holds nothing to hand on: refused")
	var chained := ledger.transfer("OBL-0001", "B", "C", "trade:3")
	ok(chained.creditor == "C" and chained.transfers == [{"from": "A", "to": "B", "origin": "trade:2"}, {"from": "B", "to": "C", "origin": "trade:3"}] and on_disk().records[0].transfers.size() == 2, "the chain A to B to C: the history in order, the creditor the current holder")
	ok(ledger.open_view("C").size() == 1 and ledger.open_view("A").is_empty() and ledger.open_view("B").is_empty() and ledger.open_view("", "D").size() == 1, "the open view is the new holder's, no longer the earlier ones'; the debtor's side is unchanged")
	var settled := ledger.redeem("OBL-0001", "one delivery", "E2.2", "trade:4")
	ok(settled.creditor == "C" and settled.status == "settled" and settled.transfers.size() == 2 and settled.redemptions.size() == 1 and ledger.open_view("C").is_empty(), "transferred then redeemed: the settlement is the NEW holder's, the history kept")
	bytes = read_text(ledger_path)
	ledger.create("A", "D", "a favor", "favor", "trade:5")
	ledger.cancel("OBL-0002", "void")
	ok(ledger.transfer("OBL-0001", "C", "A", "trade:6").is_empty() and ledger.transfer("OBL-0002", "A", "B", "trade:6").is_empty() and ledger.state.records[0].creditor == "C" and ledger.state.records[1].creditor == "A" and ledger.state.records[1].transfers.is_empty(), "a settled and a cancelled obligation are never transferred")
	DirAccess.remove_absolute(ledger_path)

# =============================================================================
#  The open views
# =============================================================================

## Five records in every state: two open, one settled, one cancelled, one
## transferred and open. Returns the ledger that wrote them.
func _mixed(path: String) -> ObligationsLedger:
	ObligationsLedger.path_override = path
	var ledger := ObligationsLedger.new()
	ledger.create("E2.2", "player", GOOD.owed, "delivery", GOOD.origin)
	ledger.create("player", "E2.4", "a full tank", "fuel-voucher", "trade:JOB-02")
	ledger.create("E2.2", "ai:driver-7", "three tins", "tuna", "trade:ai-1")
	ledger.create("E2.3", "player", "a set of tyres", "car-part", "trade:JOB-03")
	ledger.create("ai:driver-7", "E2.4", "a job for me", "favor", "trade:ai-2")
	ledger.redeem("OBL-0003", "three tins", "E2.2", "trade:ai-3")
	ledger.cancel("OBL-0004", "the workshop closed")
	ledger.transfer("OBL-0005", "ai:driver-7", "player", "trade:JOB-04")
	ObligationsLedger.path_override = ledger_path
	return ledger

func ids(view: Array) -> Array:
	var found: Array = []
	for entry: Dictionary in view:
		found.append(entry.id)
	return found

func _open_view() -> void:
	var empty := ObligationsLedger.new()
	empty.load_state()
	ok(empty.open_view() == [] and empty.open_view("player") == [] and empty.open_view("", "player") == [] and empty.records() == [], "an empty store: every view is []")
	var ledger := _mixed(ledger_path)
	ok(ids(ledger.open_view()) == ["OBL-0001", "OBL-0002", "OBL-0005"], "no side named: every open record, in the log's order; the settled and the cancelled left out")
	ok(ids(ledger.open_view("player")) == ["OBL-0002", "OBL-0005"] and ids(ledger.open_view("E2.2")) == ["OBL-0001"] and ledger.open_view("E2.3").is_empty() and ledger.open_view("ai:driver-7").is_empty(), "by creditor: what is still owed TO that id (a transferred record under its new holder; a settled one and a cancelled one under nobody)")
	ok(ids(ledger.open_view("", "player")) == ["OBL-0001"] and ids(ledger.open_view("", "E2.4")) == ["OBL-0002", "OBL-0005"] and ledger.open_view("", "ai:driver-7").is_empty(), "by debtor: what that id still owes")
	ok(ids(ledger.open_view("player", "E2.4")) == ["OBL-0002", "OBL-0005"] and ledger.open_view("E2.2", "E2.4").is_empty() and ledger.open_view("nobody").is_empty(), "both sides named: the records between the two; an unknown id holds nothing")
	var view := ledger.open_view()
	var before: Dictionary = ledger.state.duplicate(true)
	var bytes := read_text(ledger_path)
	view[0].status = "settled"
	view[0].transfers.append({"from": "x", "to": "y", "origin": "z"})
	view.clear()
	ok(ledger.state == before and ledger.open_view().size() == 3 and read_text(ledger_path) == bytes, "a view is derived copies: changing one changes neither the state nor the file")
	ok(not ledger.state.has("open") and not on_disk().has("open") and on_disk().keys().size() == 2 and not ledger.has_method("balance") and not ledger.has_method("earn") and not ledger.has_method("spend"), "no view is stored and nothing is summed: the file is version and the log, the store has no balance, earn or spend")
	DirAccess.remove_absolute(ledger_path)

# =============================================================================
#  The log is the ledger: the round trip
# =============================================================================

func _round_trip() -> void:
	var ledger := _mixed(ledger_path)
	var bytes := read_text(ledger_path)
	var loaded := ObligationsLedger.new()
	loaded.load_state()
	ok(loaded.state == ledger.state and loaded.problems.is_empty() and not loaded.newer_file and loaded.state.records.size() == 5, "round trip: five records in every state, written, read into a fresh ledger, the same state, no problem")
	ok(ids(loaded.records()) == ["OBL-0001", "OBL-0002", "OBL-0003", "OBL-0004", "OBL-0005"], "the ids are 1-based and contiguous: a record's place")
	var states: Array = []
	for entry: Dictionary in loaded.records():
		states.append([entry.status, entry.redemptions.size(), entry.transfers.size(), entry.has("cancelled_origin")])
	ok(states == [["open", 0, 0, false], ["open", 0, 0, false], ["settled", 1, 0, false], ["cancelled", 0, 0, true], ["open", 0, 1, false]], "every state reads back as written: open, settled by one redemption, cancelled with its origin, transferred")
	ok(read_text(ledger_path) == bytes and files() == PackedStringArray(["obligations.json"]), "reads never rewrite")
	var other := ObligationsLedger.new()
	ok(other.create("E2.1", "player", "a lap", "anything", "trade:late").id == "OBL-0006" and other.state.records.size() == 6, "a second ledger joins the log as it stands on disk: its first record is the sixth")
	ok(ledger.redeem("OBL-0006", "a lap", "E2.1", "trade:lap").status == "settled" and ledger.state.records.size() == 6, "and the first settles a record it never wrote: the file is read before every write")
	DirAccess.remove_absolute(ledger_path)

# =============================================================================
#  Versions
# =============================================================================

func _versions() -> void:
	var ledger := ObligationsLedger.new()
	write_json(ledger_path, {"version": 2, "records": [GOOD], "later": "build"})
	var bytes := read_text(ledger_path)
	ledger.load_state()
	ok(ledger.state == ObligationsLedger.defaults() and ledger.newer_file and ledger.problems.size() == 1 and ledger.problems[0].contains("later build"), "a later version is never trusted: the defaults, reported")
	ok(ledger.create("E2.2", "player", "one delivery", "delivery", "trade").is_empty() and ledger.redeem("OBL-0001", "fuel", "E2.4", "refuel").is_empty() and ledger.cancel("OBL-0001", "void").is_empty() and ledger.transfer("OBL-0001", "E2.2", "E2.3", "trade").is_empty() and read_text(ledger_path) == bytes and not FileAccess.file_exists(ledger_path + ".tmp") and ledger.open_view().is_empty(), "a later build's file refuses every write (create, redeem, cancel, transfer) and is never written over: the bytes stay, no temporary file")
	var defaulted := true
	for bad in [99, -1, 1.5, "1", [], true]:
		write_json(ledger_path, {"version": bad, "records": [GOOD]})
		ledger.load_state()
		defaulted = defaulted and ledger.state == ObligationsLedger.defaults() and ledger.problems.size() == 1
	ok(defaulted, "versions 99, -1, 1.5, \"1\", [] and true read as the defaults, each reported")
	var read_as_one := true
	var stamped := true
	for legacy in [{"version": 0, "records": [GOOD]}, {"records": [GOOD]}]:
		write_json(ledger_path, legacy)
		bytes = read_text(ledger_path)
		ledger.load_state()
		read_as_one = read_as_one and ledger.state == {"version": 1, "records": [GOOD]} and ledger.problems.is_empty() and not ledger.newer_file and read_text(ledger_path) == bytes
		stamped = stamped and ledger.create("E2.3", "player", "a lap", "", "stamp").id == "OBL-0002" and on_disk().version == 1 and on_disk().records.size() == 2
	ok(read_as_one, "version zero or none reads as version one, and the read does not write")
	ok(stamped, "the first write stamps version one")
	DirAccess.remove_absolute(ledger_path)

# =============================================================================
#  Determinism
# =============================================================================

func _determinism() -> void:
	_mixed(ledger_path)
	_mixed(twin_path)
	ok(read_text(ledger_path) == read_text(twin_path) and read_text(ledger_path).length() > 500, "the same trades written to two files: the same bytes (no wall clock, no randomness in a record)")
	var a := ObligationsLedger.new()
	var b := ObligationsLedger.new()
	a.load_state()
	b.load_state()
	ok(a.state == b.state and JSON.stringify(a.state) == JSON.stringify(b.state) and JSON.stringify(a.open_view("player")) == JSON.stringify(b.open_view("player")) and a.problems == b.problems and JSON.stringify(a.state, "  ") == read_text(ledger_path), "two ledgers over the same file agree to the bit: the state and a view; the state a read holds is the file's own bytes when written again")
	DirAccess.remove_absolute(ledger_path)
	DirAccess.remove_absolute(twin_path)

# =============================================================================
#  Corruption tolerance
# =============================================================================

## Whether `bad`, written between two good records, is reported with `text`
## and left out, the good ones kept in order and the second renumbered.
func dropped(ledger: ObligationsLedger, bad: Variant, text: String) -> bool:
	var third := record({"id": "OBL-0003", "creditor": "E2.3", "owed": "a set of tyres"})
	write_json(ledger_path, {"version": 1, "records": [GOOD, bad, third]})
	ledger.load_state()
	# The dropped record's neighbour takes its place: OBL-0003 reads as OBL-0002, reported.
	return ObligationsLedger.record_problem(bad).contains(text) and ledger.state.records.size() == 2 and ledger.state.records[0] == GOOD and ledger.state.records[1] == record({"id": "OBL-0002", "creditor": "E2.3", "owed": "a set of tyres"}) and ledger.problems.size() == 2 and ledger.problems[0].contains("records[1]") and ledger.problems[0].contains(text) and ledger.problems[0].contains("left out") and ledger.problems[1].contains("OBL-0002 is used")

func _corruption() -> void:
	var ledger := ObligationsLedger.new()
	write_text(ledger_path, "{broken")
	var bytes := read_text(ledger_path)
	ledger.load_state()
	ok(ledger.state == ObligationsLedger.defaults() and ledger.problems.size() == 1 and ledger.problems[0].contains("not JSON") and read_text(ledger_path) == bytes, "malformed JSON reads as the defaults, reported; the read leaves the file as it is")
	var defaulted := true
	for bad in ["[1, 2]", "\"text\"", "3", "null"]:
		write_text(ledger_path, bad)
		ledger.load_state()
		defaulted = defaulted and ledger.state == ObligationsLedger.defaults() and ledger.problems.size() == 1 and ledger.problems[0].contains("not an object")
	ok(defaulted, "a file that is no object reads as the defaults: [1, 2], \"text\", 3, null")
	defaulted = true
	for bad in [{"a": 1}, "log", 3, null]:
		write_json(ledger_path, {"version": 1, "records": bad})
		ledger.load_state()
		defaulted = defaulted and ledger.state == ObligationsLedger.defaults() and ledger.problems.size() == 1 and ledger.problems[0].contains("not a list")
	ok(defaulted, "records that are no list read as an empty log, reported")
	var all := true
	for bad in [null, 3, "x", []]:
		all = all and dropped(ledger, bad, "is not an object")
	ok(all, "a record that is null, 3, \"x\" or [] is reported and left out, the good siblings kept and renumbered")
	ok(dropped(ledger, record({"owed": ""}), "has no owed") and dropped(ledger, record({"owed": null}), "has no owed") and dropped(ledger, record({"owed": 64}), "has no owed"), "fault: an empty, a missing or a non-text owed thing")
	ok(dropped(ledger, record({"creditor": "  "}), "has no creditor") and dropped(ledger, record({"debtor": null}), "has no debtor") and dropped(ledger, record({"origin": ""}), "has no origin"), "fault: an empty creditor, a missing debtor, an empty origin")
	ok(dropped(ledger, record({"creditor": "player"}), "creditor and debtor are the same"), "fault: the creditor is the debtor")
	ok(dropped(ledger, record({"kind": "credits"}), "has no known kind") and dropped(ledger, record({"kind": 3}), "has no known kind"), "fault: a kind present but unknown")
	ok(dropped(ledger, record({"status": "paid"}), "has no known status") and dropped(ledger, record({"status": null}), "has no known status"), "fault: an unknown or a missing status")
	ok(dropped(ledger, record({"status": "settled", "redemptions": [REDEMPTION, REDEMPTION]}), "settled with 2 redemptions"), "fault: two redemptions (one-shot: never merged, never read)")
	ok(dropped(ledger, record({"status": "settled"}), "settled with 0 redemptions") and dropped(ledger, record({"status": "cancelled", "cancelled_origin": "void", "redemptions": [REDEMPTION]}), "cancelled with 1 redemptions") and dropped(ledger, record({"redemptions": [REDEMPTION]}), "open with 1 redemptions"), "fault: settled with no redemption, cancelled with a redemption, open with a redemption")
	ok(dropped(ledger, record({"status": "settled", "redemptions": [{"given": "fuel", "where": "", "origin": "refuel"}]}), "redemptions[0] has no where") and dropped(ledger, record({"redemptions": "fuel"}), "redemptions is not a list") and dropped(ledger, record({"status": "settled", "redemptions": [3]}), "redemptions[0] is not an object"), "fault: a redemption missing a field, redemptions no list, a redemption no object")
	ok(dropped(ledger, record({"transfers": [{"from": "A", "to": "E2.2"}]}), "transfers[0] has no origin") and dropped(ledger, record({"transfers": {}}), "transfers is not a list") and dropped(ledger, record({"transfers": [{"from": "A", "to": "E2.2", "origin": "t"}, null]}), "transfers[1] is not an object"), "fault: a bad transfers entry, transfers no list")
	ok(dropped(ledger, record({"cancelled_origin": "void"}), "has a cancelled_origin and is open") and dropped(ledger, record({"status": "cancelled"}), "cancelled with no cancelled_origin") and dropped(ledger, record({"status": "cancelled", "cancelled_origin": " "}), "cancelled_origin is not a nonempty text"), "fault: a cancelled_origin on a record that is not cancelled; cancelled with no cancelled_origin, or an empty one")
	write_json(ledger_path, {"version": 1, "records": [record({"id": 7}), record({"id": "OBL-0007", "creditor": "E2.3"}), record({"id": null, "creditor": "E2.1"})]})
	bytes = read_text(ledger_path)
	ledger.load_state()
	ok(ids(ledger.records()) == ["OBL-0001", "OBL-0002", "OBL-0003"] and ledger.problems.size() == 3 and ledger.problems[0].contains("id 7") and ledger.problems[1].contains("id OBL-0007 is not its place") and ledger.state.records[1].creditor == "E2.3" and read_text(ledger_path) == bytes, "an id is a record's place: a non-text, a wrong and a missing one are each reported and derived, the records kept")
	write_json(ledger_path, {"version": 1, "records": [record({"note": "kept", "kind": null, "redemptions": null, "transfers": null})], "extra": 1})
	ledger.load_state()
	ok(ledger.problems.is_empty() and ledger.state.records[0] == record({"note": "kept", "kind": "anything"}) and ledger.state.keys().size() == 2, "an extra field rides along; a kind absent on disk reads as anything, absent lists as empty, without complaint")
	ok(ledger.redeem("OBL-0001", "fuel 64 L", "E2.4", "refuel").note == "kept" and on_disk().records[0].note == "kept" and on_disk().records[0].kind == "anything" and not on_disk().has("extra"), "and survives the next write on its record")
	write_text(ledger_path, "{broken")
	ok(ledger.create("E2.2", "player", "one delivery", "delivery", "fresh start").id == "OBL-0001" and on_disk().records.size() == 1 and ledger.problems.size() == 1, "an untrustworthy file of this build's is replaced by the next committed create")
	DirAccess.remove_absolute(ledger_path)

# =============================================================================
#  The failed write
# =============================================================================

func _failed_write() -> void:
	var ledger := ObligationsLedger.new()
	ledger.create("E2.2", "player", GOOD.owed, "delivery", GOOD.origin)
	var committed: Dictionary = ledger.state.duplicate(true)
	var bytes := read_text(ledger_path)
	# The temporary file's name taken by a folder: no write can open it.
	DirAccess.make_dir_absolute(ledger_path + ".tmp")
	ok(ledger.create("E2.3", "player", "a lap", "anything", "trade").is_empty() and ledger.redeem("OBL-0001", "fuel 64 L", "E2.4", "refuel").is_empty() and ledger.cancel("OBL-0001", "void").is_empty() and ledger.transfer("OBL-0001", "E2.2", "E2.3", "trade").is_empty(), "a write that fails returns {}: create, redeem, cancel, transfer")
	DirAccess.remove_absolute(ledger_path + ".tmp")
	ok(read_text(ledger_path) == bytes and ledger.state == committed and ledger.problems.is_empty() and files() == PackedStringArray(["obligations.json"]), "the failed writes publish nothing: the file and the state are the last committed")
	ok(ledger.redeem("OBL-0001", "fuel 64 L", "E2.4", "refuel") == record({"status": "settled", "redemptions": [REDEMPTION]}) and on_disk().records[0].status == "settled", "the retry commits it")
	# was `not has("obligations.json")`, slice 1's known seed gap pinned ->
	# closed (TROC-1 slice 2).
	ok(DataDir.SEEDED_FILES.has("obligations.json") and DataDir.SEEDED_FILES[-1] == "obligations.json" and DataDir.SEEDED_FILES[-2] == "credits.json", "the data folder's seed carries obligations.json, last after credits.json (was: pinned absent, slice 1's known gap, closed by slice 2)")
	DirAccess.remove_absolute(ledger_path)

# =============================================================================
#  The runner creates the poster's obligation (TROC-1 slice 2)
# =============================================================================

## credits_test's way to a pass without driving: the episode's own gates fed
## to the runner's tick, one a second.
func _pass_by_ticks(runner: MissionRunner, mission: Dictionary) -> bool:
	if not runner.start(mission.id):
		return false
	for step: Dictionary in mission.episode:
		runner.tick(1, Vector3(step.position[0], step.position[1], step.position[2]))
	return runner.active.is_empty()

## The pad, the shipped runner, a catalog of this test's own: the ML-1 proof
## fixture posted by a desk of the test's. Gated first, then on the test's
## file: the record, the single shot, the failure, the JOBS page's view.
func _runner() -> void:
	var runner := MissionRunner.of(self)
	var campaign_path := test_dir.path_join("campaign.json")
	CampaignStore.path_override = campaign_path
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	var garage: Garage = scene.get_node("Garage")
	runner.campaign.load_state()
	runner.campaign.reconcile(LicenceExams.LICENCE_L1)
	runner.configure(scene.get_node("Car"), scene.get_node("HUD"))
	var job: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/ml1_proof.json"))
	job.id = "POSTED-PROOF"
	job.title = "Posted proof"
	job.job_kind = "courier"
	job.reward_credits = 95
	job.poster = "DISPATCH-TEST"
	job.poster_owed = "one test delivery: across the pad"
	runner.catalog.clear()
	runner.catalog[job.id] = job
	ok(MissionSchema.validate(job).is_empty() and runner.obligations is ObligationsLedger and runner.obligations.state == ObligationsLedger.defaults() and runner.obligations.problems.is_empty(), "the posted fixture validates; the runner holds an unread obligations ledger at its defaults")

	# Gated: FD_TELEMETRY=0 and no override.
	ObligationsLedger.path_override = ""
	ok(_pass_by_ticks(runner, job) and runner.last_result.passed and runner.last_result.obligation == {} and runner.pay_last_result() == {}, "gated (FD_TELEMETRY=0, no override) a passed job creates nothing: {} in the result, {} asked again")
	ok(runner.obligations.state == ObligationsLedger.defaults() and runner.obligations.open_view("player").is_empty() and not FileAccess.file_exists(ledger_path) and stamp(real_path) == real_before and not runner.result_text().contains("owed by"), "the runner's store is inert: nothing in memory, no file of the test's or the driver's, no owed-by line")
	ObligationsLedger.path_override = ledger_path

	# A pass creates the obligation, once.
	var episode := runner._episode + 1
	var expected := {"id": "OBL-0001", "creditor": "player", "debtor": "DISPATCH-TEST", "owed": "one test delivery: across the pad", "kind": "delivery", "origin": "job:POSTED-PROOF/episode-%d" % episode, "status": "open", "redemptions": [], "transfers": []}
	ok(_pass_by_ticks(runner, job) and runner._episode == episode and runner.last_result.passed and runner.last_result.obligation == expected, "a passed posted job creates the obligation: creditor player, debtor the poster, owed in the poster's words, kind delivery, origin job:<id>/episode-<n>, open")
	ok(on_disk().records == [expected] and on_disk().version == 1 and files().has("obligations.json") and not files().has("credits.json") and runner.result_text().ends_with(" — owed by DISPATCH-TEST: one test delivery: across the pad"), "the one record on disk, no credits file beside it; the result text names who owes what")
	var bytes := read_text(ledger_path)
	runner.finish(true, "again")
	ok(runner.pay_last_result() == {} and runner.pay_last_result() == {} and read_text(ledger_path) == bytes, "a retry pays nothing: the payment asked for twice more and a second finish(), the bytes identical")

	# A failure creates nothing.
	runner.start(job.id)
	runner.tick(21, Vector3(0, 0.7, 0))
	ok(runner.last_result.reason == "time limit" and not runner.last_result.passed and runner.last_result.obligation == {} and runner.pay_last_result() == {} and read_text(ledger_path) == bytes, "a failed job creates nothing: the bytes identical")

	# The JOBS page's view.
	var view := ObligationsLedger.new()
	view.load_state()
	ok(view.open_view("player") == [expected] and view.open_view("", "player").is_empty() and view.open_view("", "DISPATCH-TEST") == [expected] and runner.obligations.open_view("player") == [expected], "the JOBS-page-facing views: open_view(creditor player) shows the record, nothing owed by the player")
	garage.show_page(Garage.Page.JOBS)
	ok(garage.page_text().contains("Owed to you by DISPATCH-TEST: one test delivery: across the pad") and not garage.page_text().contains("You owe") and not garage.page_text().contains("CREDITS:") and read_text(ledger_path) == bytes, "the JOBS page shows it as owed to the driver, reads TROC, and its read wrote nothing")
	ok(_pass_by_ticks(runner, job) and runner.last_result.obligation.id == "OBL-0002" and runner.last_result.obligation.origin == "job:POSTED-PROOF/episode-%d" % (episode + 2) and on_disk().records.size() == 2, "passing the job again is a new episode and a new obligation: the second record, its own episode in the origin")
	CampaignStore.path_override = ""
	runner.load_catalog()
	runner.campaign.load_state()
	scene.queue_free()
	await process_frame

# =============================================================================
#  The dealership barter (TROC-1 slice 3)
# =============================================================================

## The posted fixture of _runner, as a catalog entry.
func _posted() -> Dictionary:
	var job: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/ml1_proof.json"))
	job.id = "POSTED-PROOF"
	job.title = "Posted proof"
	job.job_kind = "courier"
	job.reward_credits = 95
	job.poster = "DISPATCH-TEST"
	job.poster_owed = "one test delivery: across the pad"
	return job

## The CAR page's BARTER row for `car_id` as it stands; {} when the page
## carries none.
func _barter_row(garage: Garage, car_id: String) -> Dictionary:
	garage.show_page(Garage.Page.CAR)
	for row: Dictionary in garage.page_rows():
		if row.kind == "barter_car" and row.id == car_id:
			return row
	return {}

## The record `id` as the file holds it; {} for none.
func _stored(id: String) -> Dictionary:
	for entry: Dictionary in on_disk().records:
		if entry.id == id:
			return entry
	return {}

## credits_test's CAR-page fixture: the pad's garage over a world record, a
## cars file, a campaign file and the ledgers of this test's own (the
## credits one named and never written: the dormant path's guard needs a
## wired ledger to be reached). The fresh-driver arc, the boot that holds
## nothing, the count, the reversal, the row itself.
func _barter() -> void:
	var runner := MissionRunner.of(self)
	var world_path := test_dir.path_join("world.json")
	var store_path := test_dir.path_join("cars.json")
	var campaign_path := test_dir.path_join("campaign.json")
	var credits_path := test_dir.path_join("credits.json")
	DirAccess.remove_absolute(ledger_path)
	DirAccess.remove_absolute(campaign_path)
	CampaignStore.path_override = campaign_path
	CreditsLedger.path_override = credits_path
	# The world record BEFORE the pad loads (credits_test's rule: a path
	# without a record forces the first-run map open).
	WorldStore.set_spawn("eifel_ring", "E8.1", world_path)
	WorldStore.path_override = world_path
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	var car: ArcadeCar = scene.get_node("Car")
	var garage: Garage = scene.get_node("Garage")
	runner.campaign.state = CampaignStore.defaults()
	runner.campaign.reconcile(LicenceExams.LICENCE_L1)
	runner.configure(car, scene.get_node("HUD"))
	var job := _posted()
	runner.catalog.clear()
	runner.catalog[job.id] = job
	var ledger := ObligationsLedger.new()
	var table := Dealership.read()
	ok(Garage.CREDITS_BUY_ENABLED == false and Dealership.dealer_of(Dealership.entry_of(table, "boxster_986")) == "DEALER-EIFEL-02" and Garage.binding_term(Dealership.entry_of(table, "boxster_986")) == {"accepts": "one held obligation", "settle": "obligation"} and Garage.term_count(Garage.binding_term(Dealership.entry_of(table, "fd_2000"))) == 2 and Garage.terms_text_of(Dealership.entry_of(table, "fd_2000")) == "two held obligations", "the shipped state: the credits BUY row dormant, the Boxster's desk DEALER-EIFEL-02 accepting one held obligation, the FD-2000's two")
	var menu := {"terms": [{"accepts": "one dealership voucher", "settle": "voucher"}, {"accepts": "three held obligations", "settle": "obligation", "count": 3}, {"accepts": "two held obligations", "settle": "obligation", "count": 2}, {"accepts": "a pair of held obligations", "settle": "obligation", "count": 2}]}
	ok(Garage.binding_term(menu) == menu.terms[2] and Garage.terms_text_of(menu) == "two held obligations" and Garage.binding_term({"terms": [menu.terms[0]]}).is_empty() and Garage.terms_text_of({"terms": [menu.terms[0]]}) == "one dealership voucher" and Garage.binding_term({}).is_empty() and Garage.term_count({}) == 1, "the terms are a menu: the binding term is the obligation term asking for the fewest, the first among equals; a voucher term binds nothing in this build (slice 4's)")

	# THE INSUFFICIENT BOOT: nothing held, nothing traded, nothing written.
	var row := _barter_row(garage, "boxster_986")
	ok(garage.page_rows().size() == 3 and not row.is_empty() and not row.enabled and row.label == "BARTER — 1997 Boxster 986 — for one held obligation" and row.hint == "The dealer accepts: one held obligation. You hold no obligations the desk accepts.", "a driver who holds nothing: the three BARTER rows, greyed, the desk's words on the label and what is held in the hint")
	var refused := garage.barter_car("boxster_986", world_path, store_path, true, car)
	ok(not refused.bought and refused.reason == "the dealer accepts one held obligation: 1 more needed (0 of 1 held)" and refused.summary == "1997 Boxster 986 not traded: " + refused.reason + "." and refused.traded.is_empty() and refused.reversed.is_empty() and refused.entry.is_empty(), "barter_car with nothing held is refused, the terms and the shortfall in its reason")
	ok(not FileAccess.file_exists(ledger_path) and not FileAccess.file_exists(store_path) and WorldStore.load_driver(world_path).active_car == "", "refused before any write: no obligations file, no cars file, nothing selected")
	var owing := ledger.create("DISPATCH-TEST", "player", "a favor: a job for me", "favor", "trade:test")
	var bytes := read_text(ledger_path)
	row = _barter_row(garage, "boxster_986")
	refused = garage.barter_car("boxster_986", world_path, store_path, true, car)
	ok(owing.id == "OBL-0001" and not row.enabled and row.hint.ends_with("You hold no obligations the desk accepts.") and not refused.bought and read_text(ledger_path) == bytes and not FileAccess.file_exists(store_path), "an obligation the driver OWES is nothing held: still greyed, still refused, the obligations file byte-identical, the store untouched")
	ok(garage.barter_car("fd_1001", world_path, store_path, true, car).reason.contains("does not sell") and garage.barter_car("boxster_986", "", store_path, true, car).reason == "no world record this run" and read_text(ledger_path) == bytes, "a car the table does not trade, and no world record: refused, nothing written")

	# THE FRESH-DRIVER ARC: deliver a job, hold the poster's obligation,
	# trade it for a car (service for voucher for a car, by obligations as
	# payment: the driver's own line, ruling 16036083).
	var episode := runner._episode + 1
	ok(_pass_by_ticks(runner, job) and runner.last_result.passed and runner.last_result.obligation.id == "OBL-0002", "the fresh driver delivers a job")
	ledger.load_state()
	var held := ledger.open_view("player")
	ok(held.size() == 1 and held[0].debtor == "DISPATCH-TEST" and held[0].owed == "one test delivery: across the pad" and held[0].origin == "job:POSTED-PROOF/episode-%d" % episode and held[0].transfers.is_empty(), "and holds the poster's obligation: open_view(player) is the one record")
	row = _barter_row(garage, "boxster_986")
	var dear := _barter_row(garage, "fd_2000")
	ok(row.enabled and row.hint == "The dealer accepts: one held obligation. You hold 1 open obligations." and _barter_row(garage, "fd_1073").enabled and not dear.enabled and dear.label == "BARTER — FD-2000 — for two held obligations" and dear.hint == "The dealer accepts: two held obligations. You hold 1 open obligations: 1 more needed.", "one obligation held: the two one-obligation rows are live, the FD-2000's greyed, saying 1 more needed")
	bytes = read_text(ledger_path)
	refused = garage.barter_car("fd_2000", world_path, store_path, true, car)
	ok(not refused.bought and refused.reason == "the dealer accepts two held obligations: 1 more needed (1 of 2 held)" and read_text(ledger_path) == bytes and not FileAccess.file_exists(store_path), "THE COUNT: the FD-2000 with one held obligation is refused, nothing written")
	var moved := {"from": "player", "to": "DEALER-EIFEL-02", "origin": "dealership:boxster_986"}
	var bought := garage.barter_car("boxster_986", world_path, store_path, true, car)
	ok(bought.bought and bought.reason == "" and bought.summary == "1997 Boxster 986 traded for one held obligation." and bought.traded.size() == 1 and bought.reversed.is_empty(), "the trade: the Boxster for the one held obligation")
	var record_now := _stored("OBL-0002")
	ok(record_now.creditor == "DEALER-EIFEL-02" and record_now.debtor == "DISPATCH-TEST" and record_now.status == "open" and record_now.transfers.size() == 1 and record_now.transfers[0] == moved and bought.traded[0] == record_now and record_now.redemptions.is_empty(), "on disk the obligation is the desk's now: creditor DEALER-EIFEL-02, transfers[0] player to the desk with origin dealership:boxster_986, still open (the poster owes the desk), nothing redeemed")
	ok(on_disk().records.size() == 2 and _stored("OBL-0001") == owing and not FileAccess.file_exists(ledger_path + ".tmp"), "no record was added and the other is as it was: a trade moves a creditor, it creates nothing")
	var stored_car: Dictionary = OdometerStore._cars(OdometerStore._read(store_path)).get("boxster_986", {})
	ok(bought.entry == FirstCar.default_entry() and stored_car.get("odometer_m") == 0.0 and stored_car.get("fuel_l") == 64.0 and OdometerStore.load_licence("boxster_986", store_path).level == LicenceExams.LICENCE_NONE, "the ownership write as buy_car's: a new car's entry in the test's cars.json, 0 m, the tank its config's 64 L, unlicensed")
	ok(WorldStore.load_driver(world_path).active_car == "boxster_986", "active_car set in the test's world record")
	ledger.load_state()
	ok(Garage.traded(ledger.records(), "boxster_986") and not Garage.traded(ledger.records(), "fd_1073") and not Garage.traded(ledger.records(), "fd_2000") and not Garage.traded([], "boxster_986") and not Garage.traded(ledger.records(), "fd_1001") and not runner.campaign.owns_car("boxster_986") and not FileAccess.file_exists(credits_path), "owned by the trade in the obligations log: traded() is true for the Boxster alone - not by the ladder, not by a credits file (none exists)")
	garage.show_page(Garage.Page.CAR)
	var text := garage.page_text()
	ok(text.contains("OWNED  1997 Boxster 986 (boxster_986): traded here for one held obligation.") and text.contains("SELECTED  1997 Boxster 986 (boxster_986): traded at the dealership") and _barter_row(garage, "boxster_986").is_empty() and garage.page_rows().size() == 2 and not text.contains("CREDITS:"), "the CAR page: the OWNED and SELECTED trade lines, no BARTER row for the Boxster, the other two still on offer, no credits balance")
	garage.show_page(Garage.Page.JOBS)
	ok(not garage.page_text().contains("Owed to you by") and garage.page_text().contains("You owe DISPATCH-TEST: a favor: a job for me"), "the JOBS page no longer lists the traded obligation as owed to the driver: it is the desk's")
	bytes = read_text(ledger_path)
	var store_bytes := read_text(store_path)
	ok(garage.barter_car("boxster_986", world_path, store_path, true, car).reason == "already owned" and read_text(ledger_path) == bytes and read_text(store_path) == store_bytes, "trading for it again is refused: already owned, nothing written")
	var dormant := garage.buy_car("boxster_986", world_path, store_path, true, car)
	ok(CreditsLedger.active_path() == credits_path and not dormant.bought and dormant.reason == "already owned" and dormant.transaction.is_empty() and not FileAccess.file_exists(credits_path) and read_text(ledger_path) == bytes, "the dormant credits path refuses the barter-bought car too: buy_car says already owned before any spend, no credits file written")

	# THE COUNT: two held obligations for the FD-2000.
	ok(not _barter_row(garage, "fd_2000").enabled and _barter_row(garage, "fd_2000").hint.ends_with("You hold no obligations the desk accepts.") and _pass_by_ticks(runner, job) and runner.last_result.obligation.id == "OBL-0003", "after the trade the driver holds nothing again; a second job delivered")
	dear = _barter_row(garage, "fd_2000")
	bytes = read_text(ledger_path)
	ok(not dear.enabled and dear.hint.ends_with("You hold 1 open obligations: 1 more needed.") and not garage.barter_car("fd_2000", world_path, store_path, true, car).bought and read_text(ledger_path) == bytes, "one held, two asked: greyed, 1 more needed, refused, the bytes identical")
	ok(_pass_by_ticks(runner, job) and runner.last_result.obligation.id == "OBL-0004", "a third job delivered: two held")
	dear = _barter_row(garage, "fd_2000")
	ok(dear.enabled and dear.hint == "The dealer accepts: two held obligations. You hold 2 open obligations.", "two held: the FD-2000's row is live")
	bought = garage.barter_car("fd_2000", world_path, store_path, true, car)
	var two := {"from": "player", "to": "DEALER-EIFEL-03", "origin": "dealership:fd_2000"}
	ok(bought.bought and bought.summary == "FD-2000 traded for two held obligations." and bought.traded.size() == 2 and bought.traded[0].id == "OBL-0003" and bought.traded[1].id == "OBL-0004" and _stored("OBL-0003").creditor == "DEALER-EIFEL-03" and _stored("OBL-0004").creditor == "DEALER-EIFEL-03" and _stored("OBL-0003").transfers == [two] and _stored("OBL-0004").transfers == [two] and _stored("OBL-0002").creditor == "DEALER-EIFEL-02", "bought: two transfers recorded, the two held obligations in the log's order, each to DEALER-EIFEL-03 with origin dealership:fd_2000; the Boxster's desk keeps its own")
	ledger.load_state()
	ok(WorldStore.load_driver(world_path).active_car == "fd_2000" and OdometerStore._cars(OdometerStore._read(store_path)).has("fd_2000") and Garage.traded(ledger.records(), "fd_2000") and Garage.traded(ledger.records(), "boxster_986") and ledger.open_view("player").is_empty() and on_disk().records.size() == 4, "the FD-2000 selected and in the cars file, both cars owned by trade, nothing held, four records and no fifth")

	# What the desk itself owes is not payment at that desk.
	var desk_owes := ledger.create("player", "DEALER-EIFEL-01", "a set of floor mats", "car-part", "trade:test")
	row = _barter_row(garage, "fd_1073")
	bytes = read_text(ledger_path)
	refused = garage.barter_car("fd_1073", world_path, store_path, true, car)
	ok(desk_owes.id == "OBL-0005" and ledger.open_view("player").size() == 1 and Garage.offerable(ledger.open_view("player"), "DEALER-EIFEL-01").is_empty() and Garage.offerable(ledger.open_view("player"), "DEALER-EIFEL-02").size() == 1 and not row.enabled and row.hint.ends_with("You hold no obligations the desk accepts.") and refused.reason.contains("1 more needed (0 of 1 held)") and read_text(ledger_path) == bytes, "an obligation the desk itself owes the driver cannot be handed to that desk (the ledger never makes the two sides one id): the row greyed, the trade refused, the bytes identical")

	# THE REVERSAL: the store's side fails after the transfer committed.
	ok(_pass_by_ticks(runner, job) and runner.last_result.obligation.id == "OBL-0006" and _barter_row(garage, "fd_1073").enabled, "a fourth job delivered: the FD-1073's row is live")
	var bad_store := test_dir.path_join("cars_dir")
	DirAccess.make_dir_recursive_absolute(bad_store)
	var failed := garage.barter_car("fd_1073", world_path, bad_store, true, car)
	var there := {"from": "player", "to": "DEALER-EIFEL-01", "origin": "dealership:fd_1073"}
	var back := {"from": "DEALER-EIFEL-01", "to": "player", "origin": "dealership:fd_1073:reverse"}
	ok(not failed.bought and failed.reason == "the car's entry could not be written to cars.json, the obligation handed back" and failed.traded.size() == 1 and failed.traded[0].creditor == "DEALER-EIFEL-01" and failed.reversed.size() == 1 and failed.reversed[0].creditor == "player" and failed.entry.is_empty(), "a store path that cannot be written: the transfer committed, then reversed; not bought, the failure and the hand-back in the reason")
	ok(_stored("OBL-0006").creditor == "player" and _stored("OBL-0006").status == "open" and _stored("OBL-0006").transfers == [there, back] and _stored("OBL-0005") == desk_owes, "on disk the record's creditor is back to player and transfers carries both, origins dealership:fd_1073 and dealership:fd_1073:reverse (the log is append-only: nothing erased); the desk's own debt untouched")
	ledger.load_state()
	ok(not Garage.traded(ledger.records(), "fd_1073") and WorldStore.load_driver(world_path).active_car == "fd_2000" and not OdometerStore._cars(OdometerStore._read(store_path)).has("fd_1073") and DirAccess.get_files_at(bad_store).is_empty(), "nothing owned: a reversed trade does not count (the current creditor is the driver), the selection and the cars file as they were")
	DirAccess.remove_absolute(bad_store)
	row = _barter_row(garage, "fd_1073")
	ok(row.enabled and not garage.page_text().contains("OWNED  " + Dealership.car_name("fd_1073")), "the row is live again after the reversal")

	# The row itself: _barter_car through activate_row (the store off
	# headless: no entry, the rest of the flow), on the reversed obligation.
	var index := garage.page_rows().find_custom(func(r: Dictionary): return r.kind == "barter_car" and r.id == "fd_1073")
	ok(index >= 0 and garage.activate_row(index) and garage.last_barter_result.bought and garage.last_barter_result.entry.is_empty() and garage.last_barter_result.traded.size() == 1 and garage.last_barter_result.traded[0].id == "OBL-0006", "Enter on the live row trades: the obligation handed over, no entry (the store is off headless: cars.json in the data folder untouched)")
	ok(_stored("OBL-0006").creditor == "DEALER-EIFEL-01" and _stored("OBL-0006").transfers == [there, back, there] and _stored("OBL-0005").creditor == "player" and _stored("OBL-0005").transfers.is_empty() and WorldStore.load_driver(world_path).active_car == "fd_1073", "traded after a reversal: the history reads there, back, there; the desk's own debt was never offered; active_car fd_1073")
	text = garage.page_text()
	ok(garage.page == Garage.Page.CAR and text.contains("Last trade: %s traded for one held obligation." % Dealership.car_name("fd_1073")) and text.contains("OWNED  %s (fd_1073): traded here for one held obligation." % Dealership.car_name("fd_1073")) and garage.page_rows().is_empty() and not text.contains("Last purchase"), "the page rebuilt: the last trade named, every car owned by trade, no row left")
	ok(not files().has("credits.json") and on_disk().records.size() == 6 and on_disk().keys().size() == 2, "three cars traded for and no credits file was ever written; the obligations file is version and six records, no total")

	# Gated: the terms as text, nothing traded.
	bytes = read_text(ledger_path)
	ObligationsLedger.path_override = ""
	garage.show_page(Garage.Page.CAR)
	ok(garage.page_rows().is_empty() and garage.page_text().contains("No obligations ledger this run (the store is off): the terms are listed, nothing can be traded.") and garage.page_text().contains("FD-2000 (fd_2000): the dealer accepts two held obligations.") and garage.barter_car("fd_2000", world_path, store_path, true, car).reason == "no obligations ledger this run (the store is off)" and read_text(ledger_path) == bytes and stamp(real_path) == real_before, "gated (no override) the page reads no trade and lists the terms as text; barter_car refuses before any write")
	ObligationsLedger.path_override = ledger_path
	CampaignStore.path_override = ""
	CreditsLedger.path_override = ""
	WorldStore.path_override = ""
	runner.load_catalog()
	runner.campaign.load_state()
	scene.queue_free()
	await process_frame
