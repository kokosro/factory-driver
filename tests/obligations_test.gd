extends SceneTree
## TROC-1 slice 1 proof: the obligations ledger, the store alone (no UI).
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
## tolerance and the failed write.
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
	ok(not DataDir.SEEDED_FILES.has("obligations.json"), "the known seed gap, pinned: obligations.json is not in the data folder's seed in this slice (flagged for slice 2)")
