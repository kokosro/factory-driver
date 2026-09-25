class_name FirstCar
extends RefCounted
## The first car (docs/design/4b/first-run-flow.md §5, step 8): at the
## dealership the voucher buys the FD-1001 (configs/cars/fd_1001.json: a
## serial-number car of boxster_986.json's shape, unbranded). take() is
## what the garage's "Take the FD-1001 (voucher)" row does:
##   1. WorldStore.spend_voucher: the first unspent voucher is marked spent
##      (none unspent: nothing is taken, the reason says so),
##   2. the car's entry goes into cars.json with a new car's defaults -
##      odometer 0, the tank full (its own config's capacity), the
##      dashboard OdometerStore.DRIVER_DEFAULTS, the battery
##      BATTERY_DEFAULTS, the wear WEAR_DEFAULTS, the licence
##      LICENCE_DEFAULTS (the licence is per car today: the new car's
##      driver starts UNLICENSED in its own entry - first-run-flow.md's
##      open question 1, the driver's to rule on) - where the store is
##      kept (`store_kept`: the running game; the headless suite writes no
##      entry, as the licence manager keeps none there),
##   3. "active_car" in world.json becomes "fd_1001",
##   4. a rental on the car ends (the rule: the loaner is for a driver
##      without a car of their own).
##
## "MAKES IT THE CAR IN THE SCENE" - DEFERRED, honestly: car.gd is FROZEN
## and its config path is a const (ArcadeCar.CONFIG_PATH), read once in
## _ready; worse for any runtime swap, _apply_config writes the car's
## tuning into STATIC vars - one config per process, shared by every
## ArcadeCar in it - so a second config applied in the same process would
## re-tune the certified car under every test and every run. A subclass
## cannot change what the parent's _read_config reads, and there is no
## frozen-safe seam for a per-instance config. What lands here is the
## store side and the record: the voucher spent, the entry in cars.json,
## the CAR page naming the car owned, "active_car" persisted for the swap
## to read when car.gd learns to be built per instance (a later
## iteration). The driving car stays the Boxster until then.

## The serial-number car's id and config.
const CAR_ID := "fd_1001"
const CONFIG_PATH := "res://configs/cars/fd_1001.json"

## The car's name and tank from its config; the id when the file says none.
static func config() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
	return parsed if parsed is Dictionary else {}


static func car_name() -> String:
	var identity: Variant = config().get("identity")
	if identity is Dictionary:
		return String((identity as Dictionary).get("name", CAR_ID))
	return CAR_ID


static func tank_capacity_l() -> float:
	var fuel: Variant = config().get("fuel")
	if fuel is Dictionary and ((fuel as Dictionary).get("tank_capacity_l") is float or (fuel as Dictionary).get("tank_capacity_l") is int):
		return float((fuel as Dictionary).tank_capacity_l)
	return ArcadeCar.FUEL_TANK_CAPACITY_L


## The entry a car that has never been driven gets: the store's defaults.
static func default_entry() -> Dictionary:
	return {
		"odometer_m": 0.0,
		"fuel_l": tank_capacity_l(),
		"driver": OdometerStore.DRIVER_DEFAULTS.duplicate(true),
		"battery": OdometerStore.BATTERY_DEFAULTS.duplicate(true),
		"wear": OdometerStore.WEAR_DEFAULTS.duplicate(true),
		"licence": OdometerStore.LICENCE_DEFAULTS.duplicate(true),
	}


## Takes the car on the voucher: see the header. `world_path` is the world
## record's file ("" writes no record: nothing is taken), `store_path` the
## cars file the entry goes into where `store_kept`; `target_car` the car
## in the scene, whose rental ends. Returns
##   {"taken": bool, "reason": "" or why not, "voucher": the voucher spent,
##    "entry": the entry written or {}}
static func take(world_path: String, store_path := OdometerStore.PATH, store_kept := false, target_car: ArcadeCar = null) -> Dictionary:
	if world_path == "":
		return {"taken": false, "reason": "no world record this run", "voucher": {}, "entry": {}}
	if WorldStore.unspent_vouchers(world_path).is_empty():
		return {"taken": false, "reason": "no unspent voucher", "voucher": {}, "entry": {}}
	var spent := WorldStore.spend_voucher(world_path)
	var entry := {}
	if store_kept:
		entry = default_entry()
		OdometerStore.save_car(CAR_ID, entry.odometer_m, entry.fuel_l, store_path, entry.driver, entry.battery, entry.wear)
		OdometerStore.save_licence(CAR_ID, entry.licence, store_path)
	WorldStore.set_active_car(CAR_ID, world_path)
	var rental := RentalGate.active_on(target_car)
	if rental:
		rental.end()
	elif WorldStore.rental_active(world_path):
		WorldStore.clear_rental(world_path)
	return {"taken": true, "reason": "", "voucher": spent, "entry": entry}
