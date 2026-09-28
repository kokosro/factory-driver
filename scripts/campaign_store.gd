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
