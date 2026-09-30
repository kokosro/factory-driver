class_name Dealership
extends RefCounted
## ECON-3: the dealership's price table, configs/dealership.json - what the
## garage's CAR page sells and for how many credits:
##   {"version": 1, "cars": [
##     {"car_id": "fd_1073", "price_credits": 60000, "basis": "AUTHORED ..."}]}
## The prices are NOT fields of the car configs: configs/validation.gd is
## outside the editable surface and its schema pins a config's top-level
## keys (OTHER_KEYS[""]), so a price in configs/cars/<id>.json would be a
## fault there. A table of its own, at configs/ root, keyed by car_id, one
## price and one basis string per car: the basis is the price's provenance
## (JSON has no comments; the string is where the reasoning lives, as the
## mission configs carry theirs), and every price is AUTHORED - the source
## docs carry no car prices - which every basis says.
##
## WHO IS IN IT: the three reward cars, fd_1073, boxster_986 and fd_2000.
## The ladder grants them at the promotions (CampaignStore.REWARD_CARS) and
## the table sells them as well: a price lets a driver buy a reward car
## early, the 2000 game's own dealership shape, and the ladder stays the
## ordinary road (the prices are long-horizon: hundreds of the board's
## 95-150 credit jobs). fd_1001 is NOT in it: the serial-number car is the
## voucher's (scripts/first_car.gd), bought with the L0 voucher and never
## with credits.
##
## STRICT READER (the config house style, CarConfigValidation's): the file
## is read once per ask, every fault listed in "problems", nothing invented.
## Version 1 only: a later build's table reads as unusable (newer_file set)
## and is never written over - this class writes nothing at all. An entry
## that is none of the table's own (not an object; a key missing or
## unknown; car_id not a nonempty string, or no configs/cars/<car_id>.json;
## price_credits not a whole number above zero; basis not nonempty text; a
## car_id already listed) is refused and reported, the rest kept in file
## order. A well-formed table with no valid entry sells nothing, and says
## so.
##
## OWNERSHIP BY THE LOG: a bought car is owned exactly as a promotion's
## reward car is owned (CampaignStore.owns_car: the committed entitlement
## IS the ownership, no second flag) - the credits log's committed
## "car:<car_id>" spend is the purchase, a later "refund:car:<car_id>" earn
## undoes it (purchased). No new store, no write on load.
##
## No autoload, no node: statics, the VoucherLedger/CreditsLedger
## precedent.

const PATH := "res://configs/dealership.json"
const VERSION := 1
const CARS_DIR := "res://configs/cars"

## Exactly what a table and an entry carry.
const TABLE_KEYS := ["version", "cars"]
const ENTRY_KEYS := ["car_id", "price_credits", "basis"]

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
	return ""


## Reads the table at `path`:
##   {"version": what the file says (0 for none), "usable": bool,
##    "newer_file": bool, "cars": the entries kept, in file order, each
##    {car_id, price_credits (int), basis}, "problems": one text per fault}
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
		table.cars.append({"car_id": entry.car_id, "price_credits": int(entry.price_credits), "basis": entry.basis})
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
