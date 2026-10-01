class_name ObligationsLedger
extends RefCounted
## TROC-1 slice 1: the obligations ledger, the store of the TROC economy.
## One small JSON file beside cars.json, world.json, campaign.json and
## credits.json, user://obligations.json:
##   {"version": 1, "records": [
##     {"id": "OBL-0001", "creditor": "E2.2", "debtor": "player",
##      "owed": "one delivery: Adenau to Döttinger Höhe", "kind": "delivery",
##      "origin": "trade:JOB-01/episode-3", "status": "settled",
##      "redemptions": [{"given": "fuel 64 L", "where": "E2.4", "origin": "refuel"}],
##      "transfers": [{"from": "E2.1", "to": "E2.2", "origin": "trade"}]}]}
##
## THE RULINGS (decisions.org, the canon this store is built on):
## - 85BE93B5, "THE ECONOMY IS TROC — FULL RULING (driver, 2026-09-30,
##   answering the credits challenge): "it also tracks obligations." The
##   economy has THREE parts, all canonical: (1) NO single common
##   denominator of value — credits are NOT the economy's currency ...;
##   (2) immediate exchanges — any service, thing, or fuel voucher can be
##   exchanged directly for any other service, voucher, or thing,
##   negotiated per-trade between needs; (3) AN OBLIGATIONS LEDGER — when a
##   trade cannot settle immediately, it creates a tracked obligation (X
##   owes Y a specific service or item, or whatever Y later accepts),
##   redeemable against any of the debtor's satisfiable needs." And its
##   mapping: "the CreditsLedger becomes the OBLIGATIONS LEDGER (deliveries
##   create obligations named by the counterparty, with a redemption field
##   for how they were settled — not balance arithmetic)".
## - 16036083 (2026-10-01), the ruling on docs/design/troc-redesign.md: the
##   build order approved (this store is its slice 1; the credits path goes
##   dormant behind a flag LATER, not in this slice); settlements are
##   ONE-SHOT; obligations are TRANSFERABLE and can themselves BE payment;
##   AI counterparties honour the economy; a favor is "i need you to do a
##   job for me", any job.
## The design is docs/design/troc-redesign.md: §2.1 the record, §2.4 where
## it persists, §5 item 1 this slice.
##
## THE TEMPLATE IS CreditsLedger (scripts/credits_ledger.gd), its machinery
## copied honestly: the atomic tmp+rename commit, the version refusal
## (newer_file), the tolerant reader that reports and invents nothing, the
## path_override test seam, the OdometerStore.enabled() gating, reads that
## never rewrite, a write that fails publishes nothing, the file read first
## so an entry joins the log as it stands on disk.
##
## WHAT DIED: `balance`, the earn and spend kinds, every amount and every
## arithmetic. There is NO total, NO number of value, NO comparison of one
## obligation against another anywhere in this file. THE LOG IS THE LEDGER:
## what is owed is named BY THE COUNTERPARTY as free text (`owed`), with
## `kind` as an optional typed hint (KINDS; absent reads as "anything"). A
## view ("what is still open for this creditor") is derived by open_view,
## never stored and never summed.
##
## COUNTERPARTIES ARE OPAQUE IDS from day one: `creditor` and `debtor` are
## non-empty strings and nothing more. "player" is one id among the others,
## special-cased nowhere (the AI-honour ruling: a record between two AI
## counterparties is the same record). The two sides are never the same id.
##
## ONE-SHOT (the ruling): exactly one redemption closes an obligation.
## status "open" has no redemption, "settled" has exactly one, "cancelled"
## has none. A second redemption is refused, never merged; a settled or a
## cancelled record is never redeemed, transferred or cancelled again
## (one-shot states never mutate silently).
##
## TRANSFERS reassign the creditor: the record's `creditor` is the CURRENT
## holder, `transfers` is the history ({"from", "to", "origin"} per
## reassignment, oldest first), the debtor never changes. Only the current
## creditor can be the `from` of a transfer.
##
## CANCELLATION writes status "cancelled" and one flat field,
## "cancelled_origin": what cancelled it. It is the one field cancellation
## adds (provenance is the store's point); it is present exactly on the
## cancelled records.
##
## `id` is derived truth, "OBL-%04d" of a record's 1-based place in the
## accepted log (CreditsLedger's seq): a wrong or a missing one is reported
## and the place-derived one used. A field the store does not know rides
## along.
##
## TOLERANT READER: a missing file is the defaults (an empty log); a record
## that is none of the store's own (record_problem) is reported in
## `problems` and left out, the rest keep their order; malformed JSON, a
## file that is no object, and a version that is no whole number from 0 to
## VERSION read as the defaults. Version 0, or none, reads as version 1 and
## is stamped 1 by the first write (VERSION is 1 from birth: there is no
## migration). A version ABOVE ours is a later build's file: read as the
## defaults AND never written over (every write refuses), so an older build
## cannot destroy a newer one's log. Reads never rewrite. `problems` is the
## READER's channel only: a refused write returns {} and publishes nothing
## there (the earn precedent).
##
## WRITES ARE ATOMIC: the whole file goes to <file>.tmp and is renamed over
## the file. A write that fails publishes nothing: the file and the state
## stay as they were.
##
## NO WALL CLOCK, no randomness: a record carries no time at all.
##
## WHO READS IT IN A RUN (active_path): PATH behind the same switch as
## every other store (OdometerStore.enabled: on with a window, off
## headless); the headless suite reads and writes NOTHING unless a test
## points path_override at a file of its own. Gated, every write returns {}
## and keeps nothing, in memory or on disk.
##
## NO SIGNALS in this slice: nothing consumes one yet (slices 2-4 wire the
## jobs page, the dealership barter and the fuel-for-obligation, and add
## what they need). No autoload, no node: whoever trades holds one and a
## test makes its own.
##
## KNOWN SEED GAP: obligations.json is deliberately NOT in
## DataDir.SEEDED_FILES in this slice (the directive limits the file
## surface), so a data-folder migration would not copy it — the ECON-2
## lesson, where credits.json had the same gap. Flagged to the Conductor
## for a slice-2 one-liner.

const PATH := "user://obligations.json"
const VERSION := 1

## The typed hints a record's `kind` may carry; absent on disk reads as
## "anything", present but unknown is a corrupt record.
const KINDS := ["delivery", "car", "car-part", "material", "favor", "tuna", "fuel-voucher", "anything"]

## The states of a record: open (no redemption), settled (exactly one),
## cancelled (none, and a cancelled_origin).
const STATUS := ["open", "settled", "cancelled"]

## A test's file, read and written instead of PATH; "" for none (the game).
static var path_override := ""

## What the last load or commit holds: {version, records}.
var state := defaults()

## One text per thing the last load found wrong; empty for a clean or an
## absent file.
var problems: Array[String] = []

## Whether the file last loaded is a later build's: never written over.
var newer_file := false


static func defaults() -> Dictionary:
	return {"version": VERSION, "records": []}


static func active_path() -> String:
	if path_override != "":
		return path_override
	return PATH if OdometerStore.enabled() else ""


static func whole(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(value) and value == floor(value)


static func named(value: Variant) -> bool:
	return value is String and not value.strip_edges().is_empty()


## The id of the record at the 1-based `place` of the log.
static func id_of(place: int) -> String:
	return "OBL-%04d" % place


## What keeps `entry` from being a record; "" when it is one. `id` is not
## judged here: a reader derives it from the record's place.
static func record_problem(entry: Variant) -> String:
	if not entry is Dictionary:
		return "is not an object"
	for field: String in ["creditor", "debtor", "owed", "origin"]:
		if not named(entry.get(field)):
			return "has no %s" % field
	if entry.creditor == entry.debtor:
		return "creditor and debtor are the same (%s)" % entry.creditor
	if entry.has("kind") and not entry.kind in KINDS:
		return "has no known kind (%s)" % str(entry.kind)
	if not entry.get("status") in STATUS:
		return "has no known status (%s)" % str(entry.get("status"))
	var redemptions: Variant = entry.get("redemptions", [])
	var problem := _list_problem(redemptions, "redemptions", ["given", "where", "origin"])
	if problem != "":
		return problem
	problem = _list_problem(entry.get("transfers", []), "transfers", ["from", "to", "origin"])
	if problem != "":
		return problem
	# One-shot: open and cancelled hold no redemption, settled exactly one.
	var expected := 1 if entry.status == "settled" else 0
	if redemptions.size() != expected:
		return "is %s with %d redemptions (one-shot: %d)" % [entry.status, redemptions.size(), expected]
	if entry.has("cancelled_origin"):
		if entry.status != "cancelled":
			return "has a cancelled_origin and is %s" % entry.status
		if not named(entry.cancelled_origin):
			return "cancelled_origin is not a nonempty text"
	elif entry.status == "cancelled":
		return "is cancelled with no cancelled_origin"
	return ""


## What keeps `list` from being a list of objects each holding `fields` as
## non-empty strings; "" when it is one.
static func _list_problem(list: Variant, name: String, fields: Array) -> String:
	if not list is Array:
		return "%s is not a list" % name
	for i: int in list.size():
		if not list[i] is Dictionary:
			return "%s[%d] is not an object" % [name, i]
		for field: String in fields:
			if not named(list[i].get(field)):
				return "%s[%d] has no %s" % [name, i, field]
	return ""


func records() -> Array:
	return state.records.duplicate(true)


## The OPEN records, filtered by the named side(s): `creditor` the current
## holder, `debtor` who owes; both empty, every open record. Derived on
## every call, never stored, never summed. Copies.
func open_view(creditor := "", debtor := "") -> Array:
	var view: Array = []
	for record: Dictionary in state.records:
		if record.status != "open":
			continue
		if creditor != "" and record.creditor != creditor:
			continue
		if debtor != "" and record.debtor != debtor:
			continue
		view.append(record.duplicate(true))
	return view


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
	var stored: Variant = data.get("records", [])
	if not stored is Array:
		problems.append("%s: records is not a list, an empty log is used" % path)
		stored = []
	for i: int in stored.size():
		var entry: Variant = stored[i]
		var problem := record_problem(entry)
		if problem != "":
			problems.append("%s: records[%d] %s, it is left out" % [path, i, problem])
			continue
		var kept: Dictionary = entry.duplicate(true)
		var id := id_of(kept_log.size() + 1)
		if not kept.get("id") is String or kept.id != id:
			problems.append("%s: records[%d] id %s is not its place, %s is used" % [path, i, str(kept.get("id")), id])
		kept["id"] = id
		if not kept.has("kind"):
			kept["kind"] = "anything"
		if not kept.has("redemptions"):
			kept["redemptions"] = []
		if not kept.has("transfers"):
			kept["transfers"] = []
		kept_log.append(kept)
	state = {"version": VERSION, "records": kept_log}


## Opens an obligation: `debtor` owes `creditor` the thing `owed` names (the
## counterparty's own words), hinted by `kind` ("" writes "anything"),
## created by `origin`. Returns the record as written, carrying its id; {}
## when nothing was: the store is gated, a side, the owed thing or the
## origin is empty, the kind is not one of KINDS, the two sides are the
## same id, the file is a later build's, or the write failed. The file is
## read first, so the record joins the log as it stands on disk.
func create(creditor: String, debtor: String, owed: String, kind: String, origin: String) -> Dictionary:
	if kind == "":
		kind = "anything"
	if active_path() == "" or not named(creditor) or not named(debtor) or not named(owed) or not named(origin):
		return {}
	if not kind in KINDS or creditor == debtor:
		return {}
	load_state()
	if newer_file:
		return {}
	var record := {"id": id_of(state.records.size() + 1), "creditor": creditor, "debtor": debtor, "owed": owed, "kind": kind, "origin": origin, "status": "open", "redemptions": [], "transfers": []}
	var next: Dictionary = state.duplicate(true)
	next.records.append(record)
	if not _commit(next):
		return {}
	return record.duplicate(true)


## Cancels the open obligation `id` for `origin`: status "cancelled" and
## the one field "cancelled_origin". Returns the record as written; {} when
## nothing was: the id is unknown, the record is not open (settled, or
## cancelled already), the origin is empty, or create's own refusals.
func cancel(id: String, origin: String) -> Dictionary:
	if not named(origin):
		return {}
	var next := _next_with_open(id)
	if next.is_empty():
		return {}
	var record: Dictionary = next.records[_place(next, id)]
	record["status"] = "cancelled"
	record["cancelled_origin"] = origin
	return record.duplicate(true) if _commit(next) else {}


## Hands the open obligation `id` from its creditor `from` to `to`, for
## `origin`: the creditor is now `to`, the reassignment joins `transfers`.
## Returns the record as written; {} when nothing was: the id is unknown,
## the record is not open, `from` is not its current creditor, `to` is
## empty, is `from`, or is the debtor (the two sides are never the same
## id), the origin is empty, or create's own refusals.
func transfer(id: String, from: String, to: String, origin: String) -> Dictionary:
	if not named(to) or to == from or not named(origin):
		return {}
	var next := _next_with_open(id)
	if next.is_empty():
		return {}
	var record: Dictionary = next.records[_place(next, id)]
	if record.creditor != from or record.debtor == to:
		return {}
	record["creditor"] = to
	record.transfers.append({"from": from, "to": to, "origin": origin})
	return record.duplicate(true) if _commit(next) else {}


## Settles the open obligation `id`, ONE-SHOT: `given` is what closed it,
## `where` the place, `origin` what did. The redemption is written and the
## status is "settled". Returns the record as written; {} when nothing
## was: the id is unknown, the record is not open (so a second redemption
## is refused, never merged), an argument is empty, or create's own
## refusals.
func redeem(id: String, given: String, where: String, origin: String) -> Dictionary:
	if not named(given) or not named(where) or not named(origin):
		return {}
	var next := _next_with_open(id)
	if next.is_empty():
		return {}
	var record: Dictionary = next.records[_place(next, id)]
	record.redemptions.append({"given": given, "where": where, "origin": origin})
	record["status"] = "settled"
	return record.duplicate(true) if _commit(next) else {}


## The file read first, then a copy of the state to change, when the
## record `id` is in it and open; {} when the store is gated, the file is
## a later build's, the id is unknown or the record is not open.
func _next_with_open(id: String) -> Dictionary:
	if active_path() == "":
		return {}
	load_state()
	if newer_file:
		return {}
	var place := _place(state, id)
	if place < 0 or state.records[place].status != "open":
		return {}
	return state.duplicate(true)


## The index of the record `id` in `of`'s log; -1 for none.
func _place(of: Dictionary, id: String) -> int:
	for i: int in of.records.size():
		if of.records[i].id == id:
			return i
	return -1


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
