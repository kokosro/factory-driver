class_name CampaignStore
extends RefCounted
## Driver-wide, independent of cars.json and the numeric licence. Version 1
## migrates version 0's `missions` to `results`. Reads never rewrite files.
## All result/promotion/entitlement changes commit in one tmp+rename write;
## listeners see only the committed snapshot. A test override opts into IO.
signal changed
const PATH := "user://campaign.json"
const VERSION := 1
const RANKS := MissionSchema.RANKS
const PROMOTIONS := {"FD-12": "test_driver", "FD-22": "chief", "FD-33": "ace"}
const REWARD_CARS := {"test_driver": "fd_1073"}
const REWARDS := {
	"test_driver": "Customised 1973 Porsche 911 Carrera RS 2.7 Coupe",
	"chief": "Customised 1997 Porsche Boxster",
	"ace": "Customised 2000 Porsche 911 Turbo (996)",
}
static var path_override := ""
var state := defaults()
var _manager: LicenceManager

static func defaults() -> Dictionary:
	return {"version": VERSION, "rank": "", "results": {}, "credentials": {"junior_licence": false, "test_driver_licence": false, "chief_licence": false, "ace_licence": false}, "rewards": {"test_driver": false, "chief": false, "ace": false}}

static func active_path() -> String:
	if path_override != "":
		return path_override
	return PATH if OdometerStore.enabled() else ""

static func valid_result(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	var attempts: Variant = value.get("attempts")
	var best: Variant = value.get("best_time_s")
	return MissionSchema.number(attempts) and attempts >= 1 and attempts == floor(attempts) and MissionSchema.number(best) and best >= 0 and value.get("medal") in ["", "gold", "silver", "bronze", "complete"] and ((best == 0 and value.medal == "") or (best > 0 and value.medal != ""))

func load_state() -> void:
	state = defaults()
	var path := active_path()
	if path == "" or not FileAccess.file_exists(DataDir.resolve(path)):
		return
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(DataDir.resolve(path))) != OK:
		return
	var data: Variant = parser.data
	if not data is Dictionary or (not MissionSchema.number(data.get("version", 0)) or (data.get("version", 0) != 0 and data.get("version", 0) != VERSION)):
		return
	if data.get("version", 0) == 0:
		data["results"] = data.get("missions", {})
	# Credentials and rewards form a chain; inconsistent rank records fall
	# back to unenrolled rather than manufacturing an entitlement.
	var rank: Variant = data.get("rank", "")
	if rank in RANKS and data.get("credentials") is Dictionary and data.get("rewards") is Dictionary:
		var consistent := true
		for i in RANKS.size():
			var held: bool = i <= RANKS.find(rank)
			consistent = consistent and data.credentials.get(RANKS[i] + "_licence") is bool and data.credentials[RANKS[i] + "_licence"] == held
			if i > 0:
				consistent = consistent and data.rewards.get(RANKS[i]) is bool and data.rewards[RANKS[i]] == held
		if consistent:
			state.rank = rank
			state.credentials = data.credentials.duplicate(true)
			state.rewards = data.rewards.duplicate(true)
	if data.get("results") is Dictionary:
		for id in data.results:
			if id is String and valid_result(data.results[id]):
				state.results[id] = {"attempts": int(data.results[id].attempts), "best_time_s": float(data.results[id].best_time_s), "medal": data.results[id].medal}

func attach(manager: LicenceManager) -> void:
	if is_instance_valid(_manager) and _manager.licence_changed.is_connected(reconcile):
		_manager.licence_changed.disconnect(reconcile)
	_manager = manager
	if _manager:
		_manager.licence_changed.connect(reconcile)
		reconcile(_manager.level())

func reconcile(level: int) -> void:
	if level < LicenceExams.LICENCE_L1 or state.rank != "":
		return
	var next := state.duplicate(true)
	next.rank = "junior"
	next.credentials.junior_licence = true
	_commit(next)

func unlock_reason(mission: Dictionary) -> String:
	if RANKS.find(state.rank) < RANKS.find(mission.unlock.required_rank):
		return "Requires " + mission.unlock.required_rank.replace("_", " ")
	for id: String in mission.unlock.required_missions:
		var result: Variant = state.results.get(id)
		if not valid_result(result) or result.medal == "":
			return "Complete " + id
	return ""

## The promotion grant IS ownership, committed atomically with the result.
## Deriving it from the entitlement also covers existing ML-1/ML-2 saves;
## no purchase, second ownership flag, or write on load is needed.
func owns_car(car_id: String) -> bool:
	for rank: String in REWARD_CARS:
		if REWARD_CARS[rank] == car_id:
			return state.rewards.get(rank, false) == true
	return false

## Select an already-owned reward using FirstCar's store idiom. The live
## car swap is deferred there too: ArcadeCar's config/static tuning is frozen.
## Explicit paths let tests opt into isolated IO while default headless play
## keeps no records. Taking again preserves all existing condition fields.
func take_car(car_id: String, world_path: String, store_path := OdometerStore.PATH, store_kept := false, target_car: ArcadeCar = null) -> bool:
	if not owns_car(car_id) or world_path == "":
		return false
	var config: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://configs/cars/" + car_id + ".json"))
	if not CarConfigValidation.validate(config, car_id).is_empty():
		return false
	if store_kept and not OdometerStore._cars(OdometerStore._read(store_path)).has(car_id):
		var entry := FirstCar.default_entry()
		entry.fuel_l = config.fuel.tank_capacity_l
		OdometerStore.save_car(car_id, entry.odometer_m, entry.fuel_l, store_path, entry.driver, entry.battery, entry.wear)
		OdometerStore.save_licence(car_id, entry.licence, store_path)
		if not OdometerStore._cars(OdometerStore._read(store_path)).has(car_id):
			return false
	WorldStore.set_active_car(car_id, world_path)
	if WorldStore.load_driver(world_path).active_car != car_id:
		return false
	var rental := RentalGate.active_on(target_car)
	if rental:
		rental.end()
	elif WorldStore.rental_active(world_path):
		WorldStore.clear_rental(world_path)
	return true

## Aborts never call this. Failed attempts count but cannot unlock anything.
func record_result(mission: Dictionary, seconds: float, passed: bool) -> bool:
	if not MissionSchema.validate(mission).is_empty() or unlock_reason(mission) != "" or not is_finite(seconds) or seconds <= 0:
		return false
	var medal := MissionSchema.medal(mission.scoring, seconds) if passed else ""
	var next := state.duplicate(true)
	var old: Dictionary = next.results.get(mission.id, {"attempts": 0, "best_time_s": 0.0, "medal": ""})
	if not valid_result(old):
		old = {"attempts": 0, "best_time_s": 0.0, "medal": ""}
	old.attempts += 1
	if medal != "" and (old.best_time_s == 0 or seconds < old.best_time_s):
		old.best_time_s = seconds
		old.medal = medal
	next.results[mission.id] = old
	var promoted: String = PROMOTIONS.get(mission.id, "")
	if medal != "" and promoted != "" and RANKS.find(promoted) == RANKS.find(state.rank) + 1 and mission.rank == state.rank:
		next.rank = promoted
		next.credentials[promoted + "_licence"] = true
		next.rewards[promoted] = true
	return _commit(next)

func _commit(next: Dictionary) -> bool:
	var path := active_path()
	if path != "":
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
	changed.emit()
	return true
