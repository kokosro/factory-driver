class_name CreditsLedger
extends RefCounted
## ECON-1: the driver's credits, the economy's numeric spine. One small JSON
## file beside cars.json, world.json and campaign.json, user://credits.json:
##   {"version": 1, "balance": 95, "transactions": [
##     {"seq": 1, "kind": "earn", "amount": 95, "reason": "job:JOB-01"}]}
## The canon economy is TROC (docs/design/design-synthesis-draft.md §4: no
## money, goods for services for vouchers). Credits are NOT that economy's
## currency: they are its accounting unit, the number a paid job adds to,
## which the barter layer will price against when it comes. ECON-1 wrote
## "earn" alone and reserved "spend"; ECON-3 activates it: a car bought at
## the garage's dealership (scripts/dealership.gd, reason "car:<car_id>";
## a refund "refund:car:<car_id>" is an earn) and a fill at a station
## (scripts/refuel.gd, reason "fuel") are spends. The kind carries the
## direction: an amount is a whole number above zero for BOTH kinds, and
## the derived balance is the earns less the spends. VERSION stays 1: the
## schema reserved the kind, so no migration and no version bump.
##
## A FILE OF ITS OWN, not a field of world.json: world.json is the driver's
## place in the world (the pin, the vouchers, the rental) and is written by
## the first-run flow; an append-only money log has another writer, another
## growth rate and another corruption story. Separate concern, separate file
## (the campaign store's precedent, campaign_store.gd).
##
## THE LOG IS THE LEDGER. `balance` is derived truth: a reader sums the
## transactions it accepts (earns added, spends taken off) and adopts that
## sum; a stored balance that says otherwise is reported in "problems" and
## never trusted. `seq` is derived the same way (1-based, contiguous: an
## entry's place in the accepted log). The write path never takes the
## balance below zero (spend refuses what the balance cannot cover); a
## hand-edited log that spends more than it earns reads as the negative
## sum it is, reported, never repaired (the tolerant reader reports and
## invents nothing).
##
## TOLERANT READER (WorldStore's rule): a missing file or field is its
## default (balance 0, an empty log); an entry that is none of its own is
## reported and left out; malformed JSON, a file that is no object, and a
## version that is no whole number from 0 to VERSION read as the defaults.
## Version 0, or none, is a version 1 file written before the field
## existed: read as it stands, stamped 1 by the first write (no other
## migration). A version ABOVE ours is a later build's file: read as the
## defaults AND never written over (earn refuses), so an older build cannot
## destroy a newer one's money. Reads never rewrite.
##
## WRITES ARE ATOMIC: the whole file goes to <file>.tmp and is renamed over
## the file (CampaignStore._commit's pattern). A write that fails publishes
## nothing: the file, the state and the signal stay as they were.
##
## NO WALL CLOCK. "at_s" is optional: seconds on a deterministic tick clock
## the caller supplies (the telemetry recorder's style of session clock).
## The mission runner supplies none in ECON-1, so a job's entry carries no
## time at all rather than a machine's idea of one; the suite's output
## stays the same on every run.
##
## WHO READS IT IN A RUN (active_path): the running game reads and writes
## PATH behind the same switch as every other store (OdometerStore.enabled:
## on with a window, off headless); the headless suite reads and writes
## NOTHING unless a test points path_override at a file of its own. Gated,
## earn and spend return {} and keep nothing, in memory or on disk.
##
## No autoload, no node: whoever pays holds one (MissionRunner.credits) and
## a test makes its own.

## Fired when an earn was committed, with the transaction as written.
signal earned(transaction: Dictionary)

## Fired when a spend was committed, with the transaction as written.
signal spent(transaction: Dictionary)

const PATH := "user://credits.json"
const VERSION := 1

## The kinds a transaction may have: what a job pays in, what a car or a
## fill takes out. was ["earn"], "spend" reserved -> both written and read
## (ECON-3).
const KINDS := ["earn", "spend"]

## A test's file, read and written instead of PATH; "" for none (the game).
static var path_override := ""

## What the last load or commit holds: {version, balance, transactions}.
var state := defaults()

## One text per thing the last load found wrong; empty for a clean or an
## absent file.
var problems: Array[String] = []

## Whether the file last loaded is a later build's: never written over.
var newer_file := false


static func defaults() -> Dictionary:
	return {"version": VERSION, "balance": 0, "transactions": []}


static func active_path() -> String:
	if path_override != "":
		return path_override
	return PATH if OdometerStore.enabled() else ""


static func whole(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(value) and value == floor(value)


## What keeps `entry` from being a transaction; "" when it is one. `seq` is
## not judged here: a reader derives it from the entry's place.
static func transaction_problem(entry: Variant) -> String:
	if not entry is Dictionary:
		return "is not an object"
	if not entry.get("kind") in KINDS:
		return "has no known kind (%s)" % str(entry.get("kind"))
	if not whole(entry.get("amount")) or entry.amount <= 0:
		return "amount is not a whole number above zero (%s)" % str(entry.get("amount"))
	if not entry.get("reason") is String or entry.reason.strip_edges().is_empty():
		return "has no reason"
	if entry.has("at_s"):
		var at: Variant = entry.at_s
		if not (at is int or at is float) or not is_finite(at) or at < 0:
			return "at_s is not a finite number of seconds of zero or more (%s)" % str(at)
	return ""


func balance() -> int:
	return state.balance


func transactions() -> Array:
	return state.transactions.duplicate(true)


## Reads the file active_path() names into `state`; the defaults where
## there is none, where the store is gated, or where the file cannot be
## trusted. Never writes.
func load_state() -> void:
	state = defaults()
	problems = []
	newer_file = false
	var path := active_path()
	if path == "":
		return
	var disk := DataDir.resolve(path)
	if not FileAccess.file_exists(disk):
		return
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(disk)) != OK:
		problems.append("%s: not JSON, the defaults are used" % path)
		return
	var data: Variant = parser.data
	if not data is Dictionary:
		problems.append("%s: not an object, the defaults are used" % path)
		return
	var version: Variant = data.get("version", 0)
	if not whole(version) or version < 0:
		problems.append("%s: version is no whole number of zero or more (%s), the defaults are used" % [path, str(version)])
		return
	if version > VERSION:
		newer_file = true
		problems.append("%s: version %d is a later build's (this one reads %d), the defaults are used and the file is left alone" % [path, int(version), VERSION])
		return
	var kept_log: Array = []
	var stored: Variant = data.get("transactions", [])
	if not stored is Array:
		problems.append("%s: transactions is not a list, an empty log is used" % path)
		stored = []
	var total := 0
	for i: int in stored.size():
		var entry: Variant = stored[i]
		var problem := transaction_problem(entry)
		if problem != "":
			problems.append("%s: transactions[%d] %s, it is left out" % [path, i, problem])
			continue
		var kept: Dictionary = entry.duplicate(true)
		if not whole(kept.get("seq")) or kept.seq != kept_log.size() + 1:
			problems.append("%s: transactions[%d] seq %s is not its place, %d is used" % [path, i, str(kept.get("seq")), kept_log.size() + 1])
		kept["seq"] = kept_log.size() + 1
		kept["amount"] = int(kept.amount)
		if kept.has("at_s"):
			kept["at_s"] = float(kept.at_s)
		# was `total += kept.amount` for the one kind -> the earns less the
		# spends (ECON-3).
		total += kept.amount if kept.kind == "earn" else -kept.amount
		kept_log.append(kept)
	if total < 0:
		problems.append("%s: the log spends more than it earns (%d), no write path does that" % [path, total])
	if data.has("balance") and (not whole(data.balance) or data.balance != total):
		problems.append("%s: balance %s is not the sum of the log, %d is used" % [path, str(data.balance), total])
	state = {"version": VERSION, "balance": total, "transactions": kept_log}


## Adds `amount` credits for `reason`, at `at_s` on the caller's tick clock
## (below zero: no time is written). Returns the transaction as written;
## {} when nothing was: the store is gated, the amount is not above zero,
## the reason is empty, the time is not finite, the file is a later
## build's, or the write failed. The file is read first, so the entry joins
## the log as it stands on disk.
func earn(amount: int, reason: String, at_s := -1.0) -> Dictionary:
	if active_path() == "" or amount <= 0 or reason.strip_edges().is_empty() or not is_finite(at_s):
		return {}
	load_state()
	if newer_file:
		return {}
	var transaction := _commit_transaction("earn", amount, reason, at_s)
	if not transaction.is_empty():
		earned.emit(transaction.duplicate(true))
	return transaction


## Takes `amount` credits off for `reason` (ECON-3): earn's exact mirror,
## the same refusals ({} when the store is gated, the amount is not above
## zero, the reason is empty, the time is not finite, the file is a later
## build's, or the write failed), and one more: an amount the balance as it
## stands on disk cannot cover is refused, so the balance never goes below
## zero through this path. The entry is written with the POSITIVE amount
## under kind "spend" (the kind carries the direction). Returns the
## transaction as written, {} when nothing was.
func spend(amount: int, reason: String, at_s := -1.0) -> Dictionary:
	if active_path() == "" or amount <= 0 or reason.strip_edges().is_empty() or not is_finite(at_s):
		return {}
	load_state()
	if newer_file or amount > balance():
		return {}
	var transaction := _commit_transaction("spend", amount, reason, at_s)
	if not transaction.is_empty():
		spent.emit(transaction.duplicate(true))
	return transaction


## Appends one transaction of `kind` to the state as loaded and commits the
## file; the transaction as written, {} when the write failed.
func _commit_transaction(kind: String, amount: int, reason: String, at_s: float) -> Dictionary:
	var transaction := {"seq": state.transactions.size() + 1, "kind": kind, "amount": amount, "reason": reason}
	if at_s >= 0.0:
		transaction["at_s"] = at_s
	var next: Dictionary = state.duplicate(true)
	next.transactions.append(transaction)
	next.balance += amount if kind == "earn" else -amount
	if not _commit(next):
		return {}
	return transaction.duplicate(true)


func _commit(next: Dictionary) -> bool:
	var path := active_path()
	if path == "":
		return false
	var disk := DataDir.resolve(path)
	if DirAccess.make_dir_recursive_absolute(disk.get_base_dir()) != OK:
		return false
	var file := FileAccess.open(disk + ".tmp", FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(next, "  "))
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK or DirAccess.rename_absolute(disk + ".tmp", disk) != OK:
		return false
	state = next
	return true
