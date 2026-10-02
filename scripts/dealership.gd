class_name Dealership
extends RefCounted
## TROC-1 slice 3: the dealership's EXCHANGE-TERMS table,
## configs/dealership.json - what the garage's CAR page trades and what
## each car's desk accepts for it (was ECON-3: the price table, "what the
## CAR page sells and for how many credits"):
##   {"version": 1, "cars": [
##     {"car_id": "fd_1073", "price_credits": 60000,
##      "dealer": "DEALER-EIFEL-01",
##      "terms": [{"accepts": "one held obligation", "settle": "obligation"}],
##      "basis": "AUTHORED ..."}]}
##
## THE RULINGS (decisions.org): 85BE93B5, the economy is TROC - "the
## dealership's price list becomes an EXCHANGE-TERMS list (what
## goods/services the dealer accepts per car — barter, not debit)"; and the
## design's mapping row for this slice (docs/design/troc-redesign.md §3),
## verbatim: "`Dealership` price table (scripts/dealership.gd,
## configs/dealership.json: `price_credits` per car, all `basis: AUTHORED`)
## -> EXCHANGE-TERMS per car: what the dealer accepts (e.g. "a delivery
## obligation + one named part")".
##
## THE TERMS are the counterparty's side (§2.3): `dealer` is the desk's
## opaque counterparty id (the obligations ledger's ruling: ids are opaque
## non-empty strings), `terms` a non-empty MENU of acceptable settlements,
## each {"accepts": the desk's own words, "settle": HOW the garage settles
## it, "count": how many, a whole number of 1 or more, absent meaning 1}.
## A count is how many things the desk asks for, never a price: there is
## no number of value in a term and nothing here sums or compares one.
## TERMS_SETTLES is the vocabulary: "obligation" - the driver transfers
## obligations they hold as creditor to the desk (ruling 16036083:
## obligations are TRANSFERABLE and can themselves BE payment) - and
## "voucher", VALIDATED AND UNUSED in v1: no shipped entry carries a
## voucher term and the garage settles none, because nothing grants
## dealership vouchers yet (the store's vouchers are CAR vouchers, the
## first-run one is fd_1001's, honoured by FirstCar.take at E4.1; the job
## board's "one dealership voucher" tips are displayed and consumed by no
## system). The word is slice 4's, kept here so a table that names it
## reads.
##
## THE CREDITS PRICE IS DORMANT, NOT DELETED (ruling 16036083, slice 3's
## point, overruling the design's proposed retire - the doc itself notes
## "The driver may prefer dormancy; it is one flag either way"):
## price_credits stays in every entry, read and validated exactly as
## before, and price_of, purchased, purchase_reason and refund_reason - the
## credits path's machinery - are unchanged. What charges it is the
## garage's buy_car, unreached while Garage.CREDITS_BUY_ENABLED is false.
##
## WHY VERSION STAYS 1: the table is shipped, never migrated - the config
## and this reader move together in one landing, so there is no file of an
## older shape for this build to read. An OLDER build reading this table
## degrades safely: its entry check refuses the keys it does not know
## ("has an unknown key (dealer)"), every entry is left out, the dealership
## sells nothing and says so, and nothing is ever written (this class
## writes nothing at all). A version bump would buy the same outcome by
## another message.
##
## The terms are NOT fields of the car configs, as the prices never were:
## configs/validation.gd is outside the editable surface and its schema
## pins a config's top-level keys (OTHER_KEYS[""]). A table of its own, at
## configs/ root, keyed by car_id; the basis is the entry's provenance
## (JSON has no comments; the string is where the reasoning lives, as the
## mission configs carry theirs), and every term and every price is
## AUTHORED - the source docs carry neither - which every basis says.
##
## WHO IS IN IT: the three reward cars, fd_1073, boxster_986 and fd_2000,
## one desk each. The ladder grants them at the promotions
## (CampaignStore.REWARD_CARS) and the table trades them as well. fd_1001
## is NOT in it: the serial-number car is the voucher's
## (scripts/first_car.gd), taken on the L0 voucher.
##
## STRICT READER (the config house style, CarConfigValidation's): the file
## is read once per ask, every fault listed in "problems", nothing invented.
## Version 1 only: a later build's table reads as unusable (newer_file set)
## and is never written over. An entry that is none of the table's own (not
## an object; a key missing or unknown; car_id not a nonempty string, or no
## configs/cars/<car_id>.json; price_credits not a whole number above zero;
## basis not nonempty text; dealer not a nonempty string; terms not a
## nonempty list of terms - each an object with a nonempty accepts, a
## settle of TERMS_SETTLES, an optional whole count of 1 or more, and no
## other key; a car_id already listed) is refused and reported, the rest
## kept in file order. A well-formed table with no valid entry sells
## nothing, and says so.
##
## OWNERSHIP BY THE LOG: a car is owned exactly as a promotion's reward car
## is owned (CampaignStore.owns_car: the committed entitlement IS the
## ownership, no second flag). On the dormant credits path the credits
## log's committed "car:<car_id>" spend is the purchase, a later
## "refund:car:<car_id>" earn undoes it (purchased). On the barter path the
## committed transfer in the obligations log is the trade (Garage.traded
## reads it). No new store, no write on load.
##
## No autoload, no node: statics, the VoucherLedger/CreditsLedger
## precedent.

const PATH := "res://configs/dealership.json"
const VERSION := 1
const CARS_DIR := "res://configs/cars"

## Exactly what a table and an entry carry.
const TABLE_KEYS := ["version", "cars"]
## was ["car_id", "price_credits", "basis"] -> the desk and its terms
## (TROC-1 slice 3).
const ENTRY_KEYS := ["car_id", "price_credits", "basis", "dealer", "terms"]

## Exactly what a term carries (count optional), and how a term may be
## settled: "obligation" by transferring held obligations to the desk;
## "voucher" is slice 4's word, validated and used by no entry in v1.
const TERM_KEYS := ["accepts", "settle", "count"]
const TERMS_SETTLES := ["obligation", "voucher"]

## The ledger reasons a purchase and its refund are written under.
const PURCHASE_PREFIX := "car:"
const REFUND_PREFIX := "refund:car:"


static func whole(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(value) and value == floor(value)


## The config a car_id names.
static func config_path(car_id: String) -> String:
	return CARS_DIR.path_join(car_id + ".json")


## The car's name from its config's identity; the id when the file says
## none (Garage.car_name's rule, for any car).
static func car_name(car_id: String) -> String:
	if not FileAccess.file_exists(config_path(car_id)):
		return car_id
	var config: Variant = JSON.parse_string(FileAccess.get_file_as_string(config_path(car_id)))
	if config is Dictionary and (config as Dictionary).get("identity") is Dictionary:
		return String((config as Dictionary).identity.get("name", car_id))
	return car_id


## What keeps `entry` from being a table entry; "" when it is one. A
## duplicate is not judged here (it is a property of the list).
static func entry_problem(entry: Variant) -> String:
	if not entry is Dictionary:
		return "is not an object"
	for key: String in ENTRY_KEYS:
		if not entry.has(key):
			return "has no %s" % key
	for key: Variant in entry.keys():
		if not key in ENTRY_KEYS:
			return "has an unknown key (%s)" % str(key)
	if not entry.car_id is String or (entry.car_id as String).strip_edges().is_empty():
		return "car_id is not a nonempty string (%s)" % str(entry.car_id)
	if not FileAccess.file_exists(config_path(entry.car_id)):
		return "car_id %s has no config under %s" % [entry.car_id, CARS_DIR]
	if not whole(entry.price_credits) or entry.price_credits <= 0:
		return "price_credits is not a whole number above zero (%s)" % str(entry.price_credits)
	if not entry.basis is String or (entry.basis as String).strip_edges().is_empty():
		return "basis is not a nonempty string (%s)" % str(entry.basis)
	if not entry.dealer is String or (entry.dealer as String).strip_edges().is_empty():
		return "dealer is not a nonempty string (%s)" % str(entry.dealer)
	if not entry.terms is Array:
		return "terms is not a list (%s)" % str(entry.terms)
	if (entry.terms as Array).is_empty():
		return "terms is an empty list"
	for i: int in entry.terms.size():
		var problem := term_problem(entry.terms[i])
		if problem != "":
			return "terms[%d] %s" % [i, problem]
	return ""


## What keeps `term` from being one of an entry's terms; "" when it is one.
static func term_problem(term: Variant) -> String:
	if not term is Dictionary:
		return "is not an object"
	for key: Variant in term.keys():
		if not key in TERM_KEYS:
			return "has an unknown key (%s)" % str(key)
	if not term.has("accepts"):
		return "has no accepts"
	if not term.accepts is String or (term.accepts as String).strip_edges().is_empty():
		return "accepts is not a nonempty string (%s)" % str(term.accepts)
	if not term.has("settle"):
		return "has no settle"
	if not term.settle in TERMS_SETTLES:
		return "has an unknown settle (%s)" % str(term.settle)
	if term.has("count") and (not whole(term.count) or term.count < 1):
		return "count is not a whole number of 1 or more (%s)" % str(term.count)
	return ""


## Reads the table at `path`:
##   {"version": what the file says (0 for none), "usable": bool,
##    "newer_file": bool, "cars": the entries kept, in file order, each
##    {car_id, price_credits (int), basis, dealer, terms (a deep copy,
##    each count an int where given)}, "problems": one text per fault}
## Never writes. Unusable (not a version-1 object): no cars, the fault
## listed; usable with no cars: sells nothing, and says so.
static func read(path := PATH) -> Dictionary:
	var table := {"version": 0, "usable": false, "newer_file": false, "cars": [], "problems": []}
	if not FileAccess.file_exists(path):
		table.problems.append("%s: no such file, the dealership sells nothing" % path)
		return table
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(path)) != OK:
		table.problems.append("%s: not JSON, the dealership sells nothing" % path)
		return table
	var data: Variant = parser.data
	if not data is Dictionary:
		table.problems.append("%s: not an object, the dealership sells nothing" % path)
		return table
	var version: Variant = data.get("version", 0)
	if not whole(version):
		table.problems.append("%s: version is no whole number (%s), the dealership sells nothing" % [path, str(version)])
		return table
	table.version = int(version)
	if version > VERSION:
		table.newer_file = true
		table.problems.append("%s: version %d is a later build's (this one reads %d), the dealership sells nothing and the file is left alone" % [path, int(version), VERSION])
		return table
	if version != VERSION:
		table.problems.append("%s: version %d is not %d, the dealership sells nothing" % [path, int(version), VERSION])
		return table
	table.usable = true
	for key: Variant in data.keys():
		if not key in TABLE_KEYS:
			table.problems.append("%s: unknown key %s is ignored" % [path, str(key)])
	var listed: Variant = data.get("cars")
	if not listed is Array:
		table.problems.append("%s: cars is not a list, the dealership sells nothing" % path)
		return table
	var seen: Array[String] = []
	for i: int in listed.size():
		var entry: Variant = listed[i]
		var problem := entry_problem(entry)
		if problem == "" and entry.car_id in seen:
			problem = "lists %s again" % entry.car_id
		if problem != "":
			table.problems.append("%s: cars[%d] %s, it is left out" % [path, i, problem])
			continue
		seen.append(entry.car_id)
		var terms: Array = (entry.terms as Array).duplicate(true)
		for term: Dictionary in terms:
			if term.has("count"):
				term["count"] = int(term.count)
		table.cars.append({"car_id": entry.car_id, "price_credits": int(entry.price_credits), "basis": entry.basis, "dealer": entry.dealer, "terms": terms})
	if table.cars.is_empty():
		table.problems.append("%s: no entry is valid, the dealership sells nothing" % path)
	return table


## The kept entry for `car_id` in `table` (read's result); {} when it is
## not for sale.
static func entry_of(table: Dictionary, car_id: String) -> Dictionary:
	for entry: Dictionary in table.get("cars", []):
		if entry.car_id == car_id:
			return entry.duplicate(true)
	return {}


## The terms of `entry` (read's kept entry): the desk's menu of acceptable
## settlements, a deep copy; [] for an entry that carries none.
static func terms_of(entry: Dictionary) -> Array:
	var terms: Variant = entry.get("terms", [])
	return (terms as Array).duplicate(true) if terms is Array else []


## The desk's counterparty id of `entry`; "" when it carries none (the
## reader requires one, so only for {} - a car not for sale).
static func dealer_of(entry: Dictionary) -> String:
	return str(entry.get("dealer", ""))


## The price of `car_id` in `table`; 0 when it is not for sale.
static func price_of(table: Dictionary, car_id: String) -> int:
	return int(entry_of(table, car_id).get("price_credits", 0))


static func purchase_reason(car_id: String) -> String:
	return PURCHASE_PREFIX + car_id


static func refund_reason(car_id: String) -> String:
	return REFUND_PREFIX + car_id


## Whether the credits log `transactions` (CreditsLedger.transactions())
## holds a purchase of `car_id` that no refund undid: the committed
## "car:<car_id>" spends less the "refund:car:<car_id>" earns, above zero.
static func purchased(transactions: Array, car_id: String) -> bool:
	var held := 0
	for entry: Variant in transactions:
		if not entry is Dictionary:
			continue
		if entry.get("kind") == "spend" and entry.get("reason") == purchase_reason(car_id):
			held += 1
		elif entry.get("kind") == "earn" and entry.get("reason") == refund_reason(car_id):
			held -= 1
	return held > 0
