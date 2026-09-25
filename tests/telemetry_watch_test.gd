extends SceneTree
## Headless telemetry-everywhere test: the never-again fence. Run via
## tests/run_tests.sh, or:
##
##   godot --headless --path . --import
##   godot --headless --fixed-fps 60 --path . --script res://tests/telemetry_watch_test.gd
##
## The driver's canon (2026-09-25): "car telemetry must be saved regardless
## where the car is in the world ... so that we don't ever have the problem
## of telemetry missing because it wasn't in the scene". The Ring scene had
## no recorder, and its 22 flagged issues have no replay evidence
## (docs/issues-analysis-2026-09-24.md §1.4). This test finds EVERY scene in
## the repo that carries the car - every .tscn under res:// (the whole
## project tree, subfolders included, .godot/ left out), each one's
## PackedScene ext_resources read from its text, and a scene carries the
## car when it instances car.tscn or, transitively, a scene that does;
## the set is held equal to CAR_SCENES (main.tscn and eifel_ring.tscn), so
## a scene that gains a car, directly or by instancing a fenced scene, or
## lives in a subfolder, fails here until it is fenced - and, for each: the
## TelemetryWatch autoload (scripts/telemetry_watch.gd) made a
## TelemetryRecorder for EVERY ArcadeCar in the loaded scene, exactly one
## recorder NODE per car in the whole tree (counted by walking the tree,
## not the watcher's own registry) targeting that car, the scene root's
## children, attached, idle with no window (FD_TELEMETRY=0 pinned first,
## the refuel test's idiom: no test writes driver data), each one writing
## that car's own state when switched on to a file of this test's own
## (record_to_file: never under user://); the MissionManager listening
## through the HUD's car's recorder where there is one and no manager where
## there is none; the issue flagger's own walk finding that recorder once
## it records; a drive under the flag - one sample per physics tick, the
## sample count the recorder's own tick count, the timestamps counting
## every tick, every field, the last sample the car's own position, the
## car having moved -, the issue bound to it (telemetry, the recorder's
## session id, a real range; was the odometer and the wall clock on the
## Ring), and the recorders going with the scene. A bare car straight
## under the root gets one too (under the root), loses it when it leaves
## the tree and gets a fresh one when it comes back; a car freed before
## the frame ends, or queued for deletion, gets none and raises no error
## (the deferred attach takes the car's instance id). The ruling pinned:
## both strides 1 (SAMPLE_STRIDE_TICKS, FREE_SAMPLE_STRIDE_TICKS; was 5 and
## 30). The size measured and printed: bytes per sample, MB a minute, MB an
## hour at 60 Hz - the README's numbers come from here.
##
## A scene without recording is a test failure here, not a discovery.
## Exits 0 on success, 1 on any failed check.
# was (the landing, c4cd930): only the flat scenes/ folder scanned for a
# direct car.tscn reference, the node named "Car" alone checked and the
# watcher's registry counted -> the codex cross-review's F3: the whole
# tree walked, the instancing followed transitively, every ArcadeCar in
# the scene checked against the recorder NODES in the tree.

const CAR_SCENE := "res://scenes/car.tscn"

## Every scene in the repo that carries the car. The scan in
## _check_scene_list holds this list to the .tscn files' own PackedScene
## ext_resources, followed transitively: a new scene with a car in it must
## join here to keep the suite green.
const CAR_SCENES: Array[String] = ["res://scenes/main.tscn", "res://scenes/eifel_ring.tscn"]

## Physics frames to let a scene settle after a load (the Ring builds its
## road at load; the watcher's attach is one deferred call).
const SETTLE_FRAMES := 20

## Frames the car is driven with the throttle key down [physics ticks].
const DRIVE_FRAMES := 60

## Ticks each car's own recorder writes in the per-car check.
const PER_CAR_FRAMES := 5

## Where this run writes: a tmp dir of its own, removed at the end.
const TMP_DIR_PREFIX := "/tmp/fd-TW-telemetry-"

## What every sample carries (scripts/telemetry.gd _sample; the smoke
## test's TELEMETRY_SAMPLE_FIELDS).
const SAMPLE_FIELDS: Array[String] = [
	"t_session_s", "pos", "heading_deg", "speed_ms", "gear", "rpm",
	"throttle", "brake", "handbrake", "steer", "load_front", "load_rear",
	"slip_front_deg", "slip_rear_deg", "slip_ratio_front", "slip_ratio_rear",
	"yaw_rate_deg_s",
]

## A free sample's size band [bytes]: measured ~309 on the pad and ~330 on
## the Ring at the landing (the README's ~1.1-1.2 MB a minute, ~64-68 MiB
## an hour at 60 Hz). A field added or dropped, or a snap changed, moves it
## out of the band and re-pins the README.
const SAMPLE_BYTES_MIN := 200
const SAMPLE_BYTES_MAX := 450

## A timestamp is on its tick within this [s] (TIME_SNAP is 1e-5).
const TICK_TOLERANCE_S := 0.0001

var _failures := 0
var _tmp_dir := ""
var _user_dir_before := false
var _attached_count := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	# THE STORE PINNED OFF before anything loads a car (the refuel test's
	# idiom): an inherited FD_TELEMETRY=1 would have the watcher start a
	# real session under the driver's data folder for every car below.
	OS.set_environment("FD_TELEMETRY", "0")
	_tmp_dir = TMP_DIR_PREFIX + str(OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(_tmp_dir)
	_user_dir_before = DirAccess.dir_exists_absolute(TelemetryRecorder.ROOT_DIR)
	print("-- the watcher")
	if not _check_watcher():
		_finish()
		return
	print("-- the scenes that carry a car")
	_check_scene_list()
	for scene_path in CAR_SCENES:
		print("-- %s" % scene_path.get_file())
		await _check_scene(scene_path)
	print("-- a bare car")
	await _check_bare_car()
	print("-- a dying car")
	await _check_dying_car()
	print("-- the driver's data")
	_check(DirAccess.dir_exists_absolute(TelemetryRecorder.ROOT_DIR) == _user_dir_before, "nothing was written under user://telemetry (%s)" % ("it was there before and is unchanged" if _user_dir_before else "never created"))
	_remove_tmp()
	_finish()


# =============================================================================
#  The watcher
# =============================================================================

## The autoload is registered and up, watching the tree; the ruling's
## strides; the switch off with no window.
func _check_watcher() -> bool:
	var watch := TelemetryWatcher.of(self)
	var registered := String(ProjectSettings.get_setting("autoload/%s" % TelemetryWatcher.AUTOLOAD_NAME, "")) == "*res://scripts/telemetry_watch.gd"
	if not _check(watch != null and registered and watch.get_parent() == root and watch.name == TelemetryWatcher.AUTOLOAD_NAME and (watch.get_script() as Script).resource_path == "res://scripts/telemetry_watch.gd", "the TelemetryWatch autoload is registered (project.godot) and stands under the root, scripts/telemetry_watch.gd"):
		return false
	watch.recorder_attached.connect(func(_recorder: TelemetryRecorder) -> void: _attached_count += 1)
	_check(node_added.is_connected(watch._on_node_added) and watch.live_recorders().is_empty() and _recorder_nodes_under(root).is_empty(), "it watches the tree's node_added, and holds no recorder while there is no car (no recorder node in the tree)")
	_check(TelemetryRecorder.SAMPLE_STRIDE_TICKS == 1 and TelemetryRecorder.FREE_SAMPLE_STRIDE_TICKS == 1, "THE RULING: both strides are 1, every physics tick, missions and free driving alike (was 5 and 30)")
	_check(not TelemetryRecorder.should_record(), "FD_TELEMETRY=0 pinned by this test: no recorder below starts a session of its own")
	return true


## Every .tscn in the project that carries the car - directly or through a
## scene it instances - is in CAR_SCENES, and nothing in CAR_SCENES is
## without one.
func _check_scene_list() -> void:
	var scenes := PackedStringArray()
	_collect_scenes("res://", scenes)
	scenes.sort()
	var instances := {}
	for path in scenes:
		instances[path] = _packed_scenes_of(path)
	var found := PackedStringArray()
	for path in scenes:
		if path != CAR_SCENE and _carries_car(path, instances, []):
			found.append(path)
	found.sort()
	var fenced := PackedStringArray(CAR_SCENES)
	fenced.sort()
	var direct := 0
	for path in found:
		if (instances[path] as PackedStringArray).has(CAR_SCENE):
			direct += 1
	_check(scenes.size() >= CAR_SCENES.size() + 1 and scenes.has(CAR_SCENE), "%d scenes under res:// walked (subfolders included), car.tscn among them" % scenes.size())
	_check(found == fenced, "every scene that carries the car, directly or through a scene it instances, is fenced here: %s (%d direct; a scene that gains a car must join CAR_SCENES)" % [", ".join(found), direct])


## Every .tscn under `dir`, recursively; .godot/ and hidden folders left out.
func _collect_scenes(dir: String, out: PackedStringArray) -> void:
	for sub in DirAccess.get_directories_at(dir):
		if sub.begins_with("."):
			continue
		_collect_scenes(dir.path_join(sub), out)
	for file_name in DirAccess.get_files_at(dir):
		if file_name.ends_with(".tscn"):
			out.append(dir.path_join(file_name))


## The PackedScene ext_resources a .tscn names, read from its text.
func _packed_scenes_of(path: String) -> PackedStringArray:
	var out := PackedStringArray()
	var pattern := RegEx.create_from_string("\\[ext_resource[^\\]]*type=\"PackedScene\"[^\\]]*path=\"([^\"]+)\"")
	for found in pattern.search_all(FileAccess.get_file_as_string(path)):
		out.append(found.get_string(1))
	return out


## Whether `path` instances car.tscn, or a scene that carries it.
func _carries_car(path: String, instances: Dictionary, trail: Array) -> bool:
	if trail.has(path):
		return false
	var next := trail.duplicate()
	next.append(path)
	for instanced: String in instances.get(path, PackedStringArray()):
		if instanced == CAR_SCENE or _carries_car(instanced, instances, next):
			return true
	return false


# =============================================================================
#  A scene with a car
# =============================================================================

## The scene loaded whole: every car in it has the watcher's recorder,
## exactly one recorder node each, idle; each writes its own car; then the
## HUD's car's recorder writing to a file of this test's own, the issue
## flag bound to it, the file read back; then the scene freed, the
## recorders with it.
func _check_scene(scene_path: String) -> void:
	var base := scene_path.get_file().get_basename()
	var packed: PackedScene = load(scene_path)
	if not _check(packed != null, "%s loads" % base):
		return
	var scene := packed.instantiate()
	root.add_child(scene)
	await _step(SETTLE_FRAMES)
	var cars: Array[ArcadeCar] = []
	_cars_under(scene, cars)
	var hud := scene.get_node_or_null("HUD") as HUD
	var missions := scene.get_node_or_null("MissionManager") as MissionManager
	if not _check(cars.size() >= 1 and hud != null and hud.car != null and cars.has(hud.car), "%s: %d car(s) in the scene, the HUD holding one of them" % [base, cars.size()]):
		_drop(scene)
		return
	var watch := TelemetryWatcher.of(self)

	# Every car: one recorder node in the whole tree targeting it.
	var nodes := _recorder_nodes_under(root)
	_check(nodes.size() == cars.size(), "%s: %d recorder node(s) in the whole tree for %d car(s) (counted by walking the tree)" % [base, nodes.size(), cars.size()])
	var each_one := true
	var each_placed := true
	var each_idle := true
	var each_registered := true
	for car in cars:
		var mine: Array[TelemetryRecorder] = []
		for node in nodes:
			if node.car == car:
				mine.append(node)
		each_one = each_one and mine.size() == 1
		if mine.size() != 1:
			continue
		var recorder := mine[0]
		each_placed = each_placed and recorder.get_parent() == scene and recorder.name.begins_with(TelemetryWatcher.RECORDER_NAME) and watch.scene_root_of(car) == scene
		each_idle = each_idle and not recorder.recording and recorder._session_id == 0
		each_registered = each_registered and watch.recorder_for(car) == recorder
	_check(each_one, "%s: every car has exactly one recorder node targeting it (recorder.car == the car)" % base)
	_check(each_placed and each_registered, "%s: each stands under the scene root, named %s..., and is the one the watcher registers for that car" % [base, TelemetryWatcher.RECORDER_NAME])
	_check(each_idle, "%s: each idle with no window: attached, no session started, nothing written" % base)
	var live := watch.live_recorders()
	_check(live.size() == cars.size() and _recorder_nodes_under(scene).size() == cars.size(), "%s: the watcher's %d live recorder(s) are the scene's %d node(s)" % [base, live.size(), cars.size()])

	# Every car's recorder writes that car's own state.
	var writes := true
	for position in cars.size():
		var car := cars[position]
		var recorder := watch.recorder_for(car)
		if recorder == null:
			writes = false
			continue
		var file := _tmp_dir.path_join("%s_car%d.jsonl" % [base, position])
		recorder.record_to_file(file)
		await _step(PER_CAR_FRAMES)
		var at_stop := car.global_position
		recorder.stop()
		var samples := _samples_of(file)
		var last: Dictionary = samples.back() if not samples.is_empty() else {}
		writes = writes and samples.size() == PER_CAR_FRAMES and _on_position(last, at_stop)
	_check(writes, "%s: switched on to a file of this test's own, each car's recorder writes that car's own state (%d ticks, %d samples, the last at the car's position)" % [base, PER_CAR_FRAMES, PER_CAR_FRAMES])

	# The HUD's car: the manager, the flagger, a drive, the file.
	var car: ArcadeCar = hud.car
	var recorder := watch.recorder_for(car)
	var scene_last := scene.get_child(scene.get_child_count() - 1)
	_check(recorder != null and scene_last is TelemetryRecorder, "%s: the HUD's car's recorder is there and the scene root's last children are recorders (they tick after every node the scene came with)" % base)
	if missions != null:
		_check(missions.telemetry == recorder and recorder._manager == missions and missions.mission_started.is_connected(recorder._on_mission_started) and missions.mission_finished.is_connected(recorder._on_mission_finished) and missions.mission_aborted.is_connected(recorder._on_mission_aborted), "%s: the MissionManager adopted it (its `telemetry` is the watcher's recorder) and the recorder listens to its three signals" % base)
	else:
		_check(recorder._manager == null, "%s: no missions here, the recorder listens to none (attached with a null manager)" % base)
	var flagger: IssueFlagger = hud.flagger
	_check(flagger != null and flagger.car == car and flagger._recording_recorder() == null, "%s: the HUD's flagger finds no recorder RECORDING now (its own walk from the scene root)" % base)

	var file := _tmp_dir.path_join("%s.jsonl" % base)
	recorder.record_to_file(file)
	await _step(1)
	_check(recorder.recording and recorder._fixed_path == file and FileAccess.file_exists(file) and flagger._recording_recorder() == recorder, "%s: record_to_file switches it on (%s) and the flagger's walk now finds THIS recorder" % [base, file.get_file()])

	# A drive under the issue flag: the record binds to this scene's recorder.
	flagger.path = _tmp_dir.path_join("issues_%s.json" % base)
	var t_start_expected := recorder._seconds(recorder._session_ticks)
	var started := flagger.start()
	var odometer_before := car.odometer_m
	Input.action_press(&"accelerate")
	await _step(DRIVE_FRAMES)
	Input.action_release(&"accelerate")
	await _step(2)
	var ticks_recorded := recorder._session_ticks
	var record := flagger.stop()
	_check(started and record.get("binding") == IssueStore.BINDING_TELEMETRY and record.get("session_id") == 0 and record.get("t_start_s") == t_start_expected and record.get("t_stop_s") == recorder._seconds(ticks_recorded) and record.get("t_stop_s") > record.get("t_start_s"), "%s: the issue flag binds the drive to this scene's recorder: telemetry, session 0 (a debug recording), %.5f - %.5f s in the recorder's own clock (was on the Ring: the odometer and the wall clock, session 0, 0.0 - 0.0 s)" % [base, record.get("t_start_s", -1.0), record.get("t_stop_s", -1.0)])
	_check(car.odometer_m > odometer_before + 1.0 and record.get("odometer_stop_m") > record.get("odometer_start_m"), "%s: the car drove (%.1f m under the throttle key)" % [base, car.odometer_m - odometer_before])
	_check(hud.issue_overlay_visible() and paused, "%s: the HUD asks what is wrong, the tree paused" % base)
	hud.commit_issue_description("telemetry everywhere")
	_check(not paused and flagger.last_written_id == "issue-0001" and IssueStore.load_issues(flagger.path).issues[0].binding == IssueStore.BINDING_TELEMETRY, "%s: filed as issue-0001 of this test's own file, bound to telemetry" % base)
	var car_position := car.global_position
	recorder.stop()
	_check(not recorder.recording and flagger._recording_recorder() == null, "%s: stopped, the flagger finds none again" % base)

	# The file read back.
	_check_file(file, base, ticks_recorded, car_position)

	# The scene goes, the recorders with it.
	_drop(scene)
	await _step(1)
	_check(not is_instance_valid(recorder) and watch.live_recorders().is_empty() and _recorder_nodes_under(root).is_empty(), "%s: the scene freed, its recorders are gone and the watcher holds none" % base)


## The recorder's file: the header, one sample per tick, every field, the
## car's own state, the size.
func _check_file(file: String, base: String, ticks_recorded: int, car_position: Vector3) -> void:
	var lines := PackedStringArray()
	for raw in FileAccess.get_file_as_string(file).split("\n"):
		if not raw.strip_edges().is_empty():
			lines.append(raw)
	var objects: Array[Dictionary] = []
	for line in lines:
		var value: Variant = JSON.parse_string(line)
		if value is Dictionary:
			objects.append(value)
	if not _check(objects.size() == lines.size() and objects.size() >= 2, "%s: the file is JSON lines, %d objects" % [base, objects.size()]):
		return
	var header := objects[0]
	_check(header.get("event") == "session_start" and header.get("context") == "debug" and int(header.get("sample_stride_ticks", 0)) == 1 and int(header.get("free_sample_stride_ticks", 0)) == 1 and int(header.get("physics_ticks_per_second", 0)) == 60, "%s: the session_start line names both strides as 1 at 60 ticks a second" % base)
	var samples: Array[Dictionary] = []
	for object in objects:
		if object.has("t_session_s"):
			samples.append(object)
	_check(samples.size() == ticks_recorded and samples.size() == objects.size() - 1 and ticks_recorded == DRIVE_FRAMES + 3, "%s: one sample per physics tick, no tick missed: %d ticks recorded, %d samples (was every 30th tick of free driving)" % [base, ticks_recorded, samples.size()])
	var on_tick := true
	var complete := true
	var missing := PackedStringArray()
	for index in samples.size():
		var sample := samples[index]
		on_tick = on_tick and absf(float(sample.get("t_session_s", -1.0)) - index * TelemetryRecorder.TICK_SECONDS) < TICK_TOLERANCE_S
		for field in SAMPLE_FIELDS:
			if not sample.has(field):
				complete = false
				if not missing.has(field):
					missing.append(field)
	_check(on_tick, "%s: the timestamps count every tick, 0, 1/60, 2/60 ... in the recorder's own clock" % base)
	_check(complete, "%s: every sample carries every field (%d; missing: %s)" % [base, SAMPLE_FIELDS.size(), "none" if missing.is_empty() else ", ".join(missing)])
	var last: Dictionary = samples.back()
	_check(_on_position(last, car_position) and float(last.get("speed_ms", 0.0)) > 0.5 and float(last.get("throttle", 0.0)) == 0.0, "%s: the last sample is the car's own state at the stop: its position to the snap (%.3f, %.3f, %.3f), %.1f m/s, the throttle let go" % [base, car_position.x, car_position.y, car_position.z, float(last.get("speed_ms", 0.0))])
	var bytes := FileAccess.get_file_as_bytes(file).size()
	var per_sample := float(bytes - lines[0].length() - 1) / samples.size()
	_check(per_sample >= SAMPLE_BYTES_MIN and per_sample <= SAMPLE_BYTES_MAX, "%s: MEASURED %.1f bytes per free sample: at 60 a second %.2f MB a minute, %.1f MB (%.1f MiB) an hour, %.2f GB per 16 h day (a mission's samples carry the run's block and are larger)" % [base, per_sample, per_sample * 3600.0 / 1e6, per_sample * 216000.0 / 1e6, per_sample * 216000.0 / 1048576.0, per_sample * 216000.0 * 16.0 / 1e9])


# =============================================================================
#  A bare car, a dying car
# =============================================================================

## A car straight under the root, in no scene: a recorder under the root,
## gone when the car leaves, a fresh one when it comes back.
func _check_bare_car() -> void:
	var watch := TelemetryWatcher.of(self)
	var car: ArcadeCar = (load(CAR_SCENE) as PackedScene).instantiate()
	root.add_child(car)
	await _step(SETTLE_FRAMES)
	var recorder := watch.recorder_for(car)
	var nodes := _recorder_nodes_under(root)
	if not _check(recorder != null and nodes.size() == 1 and nodes[0] == recorder and recorder.get_parent() == root and recorder.car == car and recorder._manager == null and not recorder.recording, "a bare car under the root gets one recorder node, under the root, no manager, idle"):
		root.remove_child(car)
		car.free()
		return
	var file := _tmp_dir.path_join("bare.jsonl")
	recorder.record_to_file(file)
	await _step(PER_CAR_FRAMES)
	var ticks := recorder._session_ticks
	root.remove_child(car)
	await _step(1)
	var samples := _samples_of(file).size()
	_check(not is_instance_valid(recorder) and watch.recorder_for(car) == null and watch.live_recorders().is_empty() and _recorder_nodes_under(root).is_empty() and ticks == PER_CAR_FRAMES and samples == PER_CAR_FRAMES, "the car out of the tree: its recorder stopped (%d ticks, %d samples in the file) and freed, no recorder node left, the watcher holds none" % [PER_CAR_FRAMES, PER_CAR_FRAMES])
	root.add_child(car)
	await _step(2)
	var again := watch.recorder_for(car)
	_check(again != null and again.car == car and again.get_parent() == root and not again.recording and _recorder_nodes_under(root).size() == 1, "the car back in the tree gets a fresh recorder, one node")
	root.remove_child(car)
	await _step(1)
	car.free()
	_check(watch.live_recorders().is_empty() and _recorder_nodes_under(root).is_empty(), "and none is left once it is gone for good")


## A car gone before the watcher's deferred attach runs: freed at once, or
## queued for deletion. No recorder, no session, no error (the suite fails
## on any ERROR: line). was: the deferred call carried the car object and
## a typed argument refused the freed one before any guard ran - "Error
## calling deferred method: Cannot convert argument 1 from Object to
## Object" -, and a car queued for deletion got a recorder (a session file
## in the game) for the one frame it had left.
func _check_dying_car() -> void:
	var watch := TelemetryWatcher.of(self)
	var packed := load(CAR_SCENE) as PackedScene
	var attached_before := _attached_count
	var freed: ArcadeCar = packed.instantiate()
	root.add_child(freed)
	root.remove_child(freed)
	freed.free()
	await _step(2)
	_check(_attached_count == attached_before and watch.live_recorders().is_empty() and _recorder_nodes_under(root).is_empty(), "a car freed before the frame ends gets no recorder (the deferred attach takes its instance id and finds nothing)")
	var dying: ArcadeCar = packed.instantiate()
	root.add_child(dying)
	dying.queue_free()
	await _step(2)
	_check(_attached_count == attached_before and watch.live_recorders().is_empty() and _recorder_nodes_under(root).is_empty(), "a car queued for deletion gets no recorder either (is_queued_for_deletion: a dying car opens no session file)")


# =============================================================================
#  Helpers
# =============================================================================

## Every ArcadeCar under `node`, `node` itself included.
func _cars_under(node: Node, out: Array[ArcadeCar]) -> void:
	if node is ArcadeCar:
		out.append(node)
	for child in node.get_children():
		_cars_under(child, out)


## Every TelemetryRecorder node under `node`, `node` itself included: the
## tree's own count, not the watcher's registry.
func _recorder_nodes_under(node: Node) -> Array[TelemetryRecorder]:
	var out: Array[TelemetryRecorder] = []
	_collect_recorders(node, out)
	return out


func _collect_recorders(node: Node, out: Array[TelemetryRecorder]) -> void:
	if node is TelemetryRecorder:
		out.append(node)
	for child in node.get_children():
		_collect_recorders(child, out)


## The sample lines of a recorder's file (the ones with t_session_s).
func _samples_of(file: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for raw in FileAccess.get_file_as_string(file).split("\n"):
		var value: Variant = JSON.parse_string(raw) if not raw.strip_edges().is_empty() else null
		if value is Dictionary and (value as Dictionary).has("t_session_s"):
			out.append(value)
	return out


## Whether a sample's pos is `position` to the snap.
func _on_position(sample: Dictionary, position: Vector3) -> bool:
	var pos: Array = sample.get("pos", [])
	return pos.size() == 3 and absf(float(pos[0]) - position.x) <= TelemetryRecorder.VALUE_SNAP and absf(float(pos[1]) - position.y) <= TelemetryRecorder.VALUE_SNAP and absf(float(pos[2]) - position.z) <= TelemetryRecorder.VALUE_SNAP


func _drop(scene: Node) -> void:
	root.remove_child(scene)
	scene.free()


func _step(frames: int) -> void:
	for i in frames:
		await physics_frame


func _remove_tmp() -> void:
	if not DirAccess.dir_exists_absolute(_tmp_dir):
		return
	for file_name in DirAccess.get_files_at(_tmp_dir):
		DirAccess.remove_absolute(_tmp_dir.path_join(file_name))
	DirAccess.remove_absolute(_tmp_dir)


func _check(condition: bool, description: String) -> bool:
	if condition:
		print("  ok    ", description)
	else:
		_failures += 1
		printerr("  FAIL  ", description)
	return condition


func _finish() -> void:
	Input.action_release(&"accelerate")
	if _failures == 0:
		print("TELEMETRY WATCH TEST PASSED")
	else:
		print("TELEMETRY WATCH TEST FAILED: %d check(s) failed" % _failures)
	quit(1 if _failures > 0 else 0)
