class_name MissionRunner
extends Node
## Non-singleton autoload named MissionRunner: the class remains available to
## early-compiled scripts, of(tree) reaches the node. Idle has no children,
## physics processing, input processing, car changes or periodic store writes.
## ECON-1: jobs are missions that carry reward_credits. They live in
## JOBS_DIR, join the one catalog and start through the same start(); a
## PASSED job pays the credits ledger once (pay_last_result). A mission
## without reward_credits never reaches the ledger.
signal episode_finished(result: Dictionary)
const CATALOG_DIR := "res://configs/missions"
const JOBS_DIR := "res://configs/jobs"
var campaign := CampaignStore.new()
var credits := CreditsLedger.new()
var catalog: Dictionary = {}
var active: Dictionary = {}
var last_result: Dictionary = {}
var elapsed := 0.0
var step_index := 0
var car: ArcadeCar
var hud: HUD
var _driver: HandlingTests
var _previous := Vector3.ZERO
var _suspended: Dictionary = {}
var _lap_outside := false
var _flag_index := 0
var _flag_props: Array[Dictionary] = []
var _surface_original: Array[float] = []
var _surface_car: ArcadeCar
## start() counts the episodes; the payment remembers the one it paid.
var _episode := 0
var _paid_episode := 0
var _payable: Dictionary = {}

static func of(tree: SceneTree) -> MissionRunner:
	return tree.root.get_node_or_null("MissionRunner") as MissionRunner

func _ready() -> void:
	set_physics_process(false)
	set_process_input(false)
	campaign.load_state()
	load_catalog()
	get_tree().node_added.connect(_node_added)

func _node_added(node: Node) -> void:
	if node is LicenceManager:
		_attach_licence.call_deferred(node.get_instance_id())

func _attach_licence(id: int) -> void:
	var manager := instance_from_id(id) as LicenceManager
	if is_instance_valid(manager) and manager.is_inside_tree() and not manager.is_queued_for_deletion():
		campaign.attach(manager)

## Explicit paths permit tests to load their fixture; production scans
## configs/missions (the ladder) and then configs/jobs (the job board) into
## one catalog, the ladder first.
func load_catalog(paths: PackedStringArray = PackedStringArray()) -> void:
	var entries: Array = []
	if paths.is_empty():
		for dir: String in [CATALOG_DIR, JOBS_DIR]:
			if not DirAccess.dir_exists_absolute(dir):
				continue
			for file in DirAccess.get_files_at(dir):
				if file.ends_with(".json"):
					paths.append(dir.path_join(file))
	for path in paths:
		var parser := JSON.new()
		entries.append(parser.data if parser.parse(FileAccess.get_file_as_string(path)) == OK else null)
	var errors := MissionSchema.catalog_errors(entries)
	catalog.clear()
	for id in errors:
		push_error("Mission catalog %s: %s" % [id, "; ".join(errors[id])])
	for entry in entries:
		if entry is Dictionary and entry.get("id") is String and not errors.has(entry.id):
			catalog[entry.id] = entry.duplicate(true)

func configure(target: ArcadeCar, display: HUD) -> void:
	car = target
	hud = display

func environment_matches(environment: String) -> bool:
	if not is_instance_valid(car) or car.get_parent() == null:
		return false
	return car.get_parent().find_child("TestPad", true, false) != null if environment == "pad" else car.road_profile is WorldRoadProfile

func start(mission_id: String, scripted := false) -> bool:
	if not active.is_empty() or not catalog.has(mission_id) or not is_instance_valid(car):
		return false
	var mission: Dictionary = catalog[mission_id]
	if campaign.unlock_reason(mission) != "" or not MissionSchema.validate(mission).is_empty():
		return false
	var scene := car.get_parent()
	if not environment_matches(mission.environment):
		return false
	for node in scene.get_children():
		if node is MissionManager or node is LicenceManager or node is Study:
			if node.is_running():
				return false
	active = mission.duplicate(true)
	last_result = {}
	_payable = {}
	_episode += 1
	elapsed = 0.0
	step_index = 0
	_lap_outside = false
	_flag_index = 0
	_build_flag_props()
	for node in scene.get_children():
		if node is MissionManager or node is LicenceManager or node is Study:
			_suspended[node] = node.process_mode
			node.process_mode = Node.PROCESS_MODE_DISABLED
	car.reset_to(car.get_spawn_transform())
	# Mission setup uses the existing thermal model; reset_to preserves heat.
	if active.get("cold_tyres", false):
		car.front_tyre_temp = 0.0
		car.rear_tyre_temp = 0.0
	if active.has("surface_override"):
		_surface_car = car
		_surface_original.assign([car.front_surface_grip, car.rear_surface_grip, car.surface_rolling_decel])
		_apply_surface_override()
	_previous = car.global_position
	# HandlingTests owns the scripted driver's press/release, hold_speed and
	# steering servo. Use that mechanism alone; episode scoring is ours.
	if scripted:
		_driver = HandlingTests.new()
		_driver.car = car
		_driver.test = active.get("input_script", {"steps": []}).duplicate(true)
		_driver._mark_position = car.global_position
		_driver._start_position = car.global_position
		_driver._start_forward = -car.global_basis.z
		_driver._drive()
	set_physics_process(true)
	_show_progress()
	return true

func _physics_process(delta: float) -> void:
	if active.is_empty():
		return
	if not is_instance_valid(car) or Input.is_action_just_pressed("abort_mission") or Input.is_action_just_pressed("reset_car"):
		abort()
		return
	# Surfaces runs at -1; this autoload runs at 0 before the scene's car.
	# Reassert after classification and before the car consumes its inputs.
	_apply_surface_override()
	tick(delta, car.global_position)

func _apply_surface_override() -> void:
	if _surface_original.is_empty():
		return
	var surface: Dictionary = active.surface_override
	car.front_surface_grip = surface.grip
	car.rear_surface_grip = surface.grip
	car.surface_rolling_decel = surface.rolling_drag
	# Bump needs the ring's Surfaces + RingProfile micro-profile machinery.
	# The pad has neither; this override delivers grip and drag, not bumps.

## Swept segment gates prevent tunnelling. Later gates hit before the current
## one fail when requested. Lap requires leaving its radius before returning;
## pickup/return ordering is checked by the schema. Cone constraints apply
## throughout the episode, including the finish tick.
func tick(delta: float, position: Vector3) -> void:
	if active.is_empty() or not is_finite(delta) or delta <= 0:
		return
	elapsed += delta
	var steps: Array = active.episode
	var failures: Array = active.scoring.failure_conditions
	if elapsed > active.scoring.time_limit_s:
		finish(false, "time limit")
		return
	if "cone_hit" in failures:
		for step: Dictionary in steps:
			if step.type == "cone_slalom":
				for cone: Array in step.cones:
					if _touches(cone, step.cone_radius, _previous, position):
						finish(false, "cone hit")
						return
	# Sort crossings along the swept segment, so several ordered gates in
	# one physics tick count, but crossing a later gate first still fails.
	var crossings: Array = []
	for i in range(step_index, steps.size()):
		var step: Dictionary = steps[i]
		if step.type == "flag":
			for target in step.cones.size():
				var contact := _entry_fraction(step.cones[target], step.cone_radius, _previous, position)
				if contact >= 0:
					crossings.append({"index": i, "fraction": contact, "flag": target})
			continue
		var fraction := _entry_fraction(step.position, step.radius, _previous, position)
		if i == step_index and step.type == "lap":
			var p := Vector3(step.position[0], step.position[1], step.position[2])
			if position.distance_to(p) > step.radius:
				_lap_outside = true
				fraction = -1.0
			elif not _lap_outside:
				fraction = -1.0
		if fraction >= 0:
			crossings.append({"index": i, "fraction": fraction})
	crossings.sort_custom(func(a: Dictionary, b: Dictionary):
		if a.fraction != b.fraction:
			return a.fraction < b.fraction
		return a.index < b.index or (a.index == b.index and a.get("flag", -1) < b.get("flag", -1)))
	for crossing: Dictionary in crossings:
		# A later cone is neither a knock nor a fault. Sorting also prevents
		# crediting a newly revealed target already passed earlier this tick.
		if crossing.has("flag"):
			if crossing.index == step_index and crossing.flag == _flag_index:
				_flag_index += 1
				if _flag_index == steps[step_index].cones.size():
					step_index += 1
					_flag_index = 0
			continue
		if crossing.index == step_index:
			step_index += 1
			_lap_outside = false
		elif "skipped_gate" in failures:
			finish(false, "skipped gate")
			return
	if step_index == steps.size():
		finish(true, "course complete")
		return
	_previous = position
	if _driver:
		_driver._since_step += delta
		_driver._drive()
	_show_progress()

static func _entry_fraction(point: Array, radius: float, a: Vector3, b: Vector3) -> float:
	var offset := a - Vector3(point[0], point[1], point[2])
	var delta := b - a
	var c := offset.length_squared() - radius * radius
	if c <= 0:
		return 0.0
	var length_sq := delta.length_squared()
	if length_sq == 0:
		return -1.0
	var dot := offset.dot(delta)
	var discriminant := dot * dot - length_sq * c
	if discriminant < 0:
		return -1.0
	var fraction := (-dot - sqrt(discriminant)) / length_sq
	return fraction if fraction >= 0 and fraction <= 1 else -1.0

static func _touches(point: Array, radius: float, a: Vector3, b: Vector3) -> bool:
	var p := Vector3(point[0], point[1], point[2])
	return Geometry3D.get_closest_point_to_segment(p, a, b).distance_to(p) <= radius

func finish(passed: bool, reason: String) -> void:
	if active.is_empty():
		return
	passed = passed and step_index == active.episode.size()
	var mission := active
	var medal := MissionSchema.medal(mission.scoring, elapsed) if passed else ""
	last_result = {"id": mission.id, "passed": passed and medal != "", "time_s": elapsed, "medal": medal, "reason": reason}
	last_result["saved"] = campaign.record_result(mission, elapsed, last_result.passed)
	# The pay does not wait on the campaign record: a job done is a job paid,
	# whether or not the result could be saved.
	if mission.has("reward_credits"):
		_payable = mission
		last_result["credits"] = pay_last_result()
	_cleanup()
	if is_instance_valid(hud):
		hud.show_mission_banner("PASSED" if last_result.passed else "FAILED", result_text(), Color.GOLD)
	episode_finished.emit(last_result.duplicate(true))

## Pays the job finish() last closed, once: the credits written, 0 when
## nothing was. Single-shot per episode: start() numbers the episodes and a
## committed payment remembers its number, so calling this again for the
## same result - a retry, a listener, a second finish() - pays nothing. A
## failed or aborted episode has nothing payable; passing the job again is
## a new episode and new pay. A payment the ledger refused (gated, a write
## that failed) is not remembered: the retry may still commit it, once.
func pay_last_result() -> int:
	if _payable.is_empty() or _paid_episode == _episode:
		return 0
	if last_result.get("id") != _payable.get("id") or not last_result.get("passed", false):
		return 0
	var written := credits.earn(int(_payable.reward_credits), "job:" + str(_payable.id))
	if written.is_empty():
		return 0
	_paid_episode = _episode
	return written.amount

func abort() -> void:
	if active.is_empty():
		return
	last_result = {}
	_payable = {}
	_cleanup()
	if is_instance_valid(hud):
		hud.hide_mission_banner()

func _cleanup() -> void:
	if not _surface_original.is_empty():
		if is_instance_valid(_surface_car):
			_surface_car.front_surface_grip = _surface_original[0]
			_surface_car.rear_surface_grip = _surface_original[1]
			_surface_car.surface_rolling_decel = _surface_original[2]
		_surface_original.clear()
		_surface_car = null
	for prop: Dictionary in _flag_props:
		prop.node.free()
	_flag_props.clear()
	_flag_index = 0
	if _driver:
		_driver._release_all()
		_driver = null
	for node in _suspended:
		if is_instance_valid(node):
			node.process_mode = _suspended[node]
	_suspended.clear()
	active = {}
	set_physics_process(false)

func _exit_tree() -> void:
	_cleanup()
	campaign.attach(null)

func result_text() -> String:
	if last_result.is_empty():
		return "No episode result yet."
	var line := "episode result: %s — %.3f s — %s — %s%s" % [last_result.id, last_result.time_s, last_result.medal, last_result.reason, " (save failed)" if not last_result.saved else ""]
	if last_result.get("credits", 0) > 0:
		line += " — paid %d credits" % last_result.credits
	return line

## Only the current target is revealed; props have no physics bodies or areas.
func _build_flag_props() -> void:
	for step: Dictionary in active.episode:
		if step.type != "flag":
			continue
		for target in step.cones.size():
			var point: Array = step.cones[target]
			var prop := Node3D.new()
			prop.name = "Flag_%d_%d" % [step.sequence, target + 1]
			add_child(prop)
			prop.position = Vector3(point[0], point[1] - 0.7, point[2])
			var cone := CylinderMesh.new()
			cone.top_radius = 0.06
			cone.bottom_radius = 0.35
			cone.height = 0.7
			_flag_mesh(prop, cone, Vector3(0, 0.35, 0), Color.ORANGE)
			var pole := CylinderMesh.new()
			pole.top_radius = 0.035
			pole.bottom_radius = 0.035
			pole.height = 2.8
			_flag_mesh(prop, pole, Vector3(0, 1.4, 0), Color.LIGHT_GRAY)
			var flag := BoxMesh.new()
			flag.size = Vector3(1.1, 0.65, 0.04)
			_flag_mesh(prop, flag, Vector3(0.55, 2.4, 0), Color.GOLD)
			_flag_props.append({"step": int(step.sequence), "target": target, "node": prop})

func _flag_mesh(parent: Node3D, mesh: Mesh, offset: Vector3, color: Color) -> void:
	var instance := MeshInstance3D.new()
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	instance.mesh = mesh
	instance.material_override = material
	instance.position = offset
	parent.add_child(instance)

func flag_progress() -> Dictionary:
	if active.is_empty() or active.episode[step_index].type != "flag":
		return {}
	var step: Dictionary = active.episode[step_index]
	return {"current": _flag_index + 1, "total": step.cones.size(), "position": step.cones[_flag_index].duplicate()}

func progress_text() -> String:
	if active.is_empty():
		return ""
	var line := "Step %d/%d — %.2f s / %.2f s — Esc / R abort" % [step_index + 1, active.episode.size(), elapsed, active.scoring.time_limit_s]
	var flag := flag_progress()
	if not flag.is_empty():
		line += "\nFlag %d/%d — knock the revealed cone at (%.1f, %.1f)" % [flag.current, flag.total, flag.position[0], flag.position[2]]
	return line

func _show_progress() -> void:
	for prop: Dictionary in _flag_props:
		prop.node.visible = prop.step == step_index and prop.target == _flag_index
	if is_instance_valid(hud):
		hud.show_mission_banner(active.title, progress_text(), Color.GOLD)
