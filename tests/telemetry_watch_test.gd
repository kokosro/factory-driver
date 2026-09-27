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
## THE SURFACE AND THE RESET (2026-09-27, the schema's two additions;
## scripts/telemetry.gd's header of that name): the recorder's `surfaces`
## is the scene's Surfaces node on the Ring and null on the pad; on the
## Ring every sample carries "front_surface" and "rear_surface", plain
## strings among Surfaces.SURFACE_NAMES, the last sample's pair the node's
## own at the stop; on the pad NEITHER key is written (omitted, not null);
## a drive under the throttle writes no reset event; then, in a second
## file of its own per scene, the car nudged RESET_NUDGE_M (under the
## 5 m threshold: no event) and then put RESET_JUMP_M ahead by reset_to
## (the teleport R and a spawn do): exactly one {"event": "reset"} line,
## on the line right after the sample that landed, its t that sample's
## t_session_s, before = the previous sample's pos and the car's odometer
## then, after = the landing sample's pos and the odometer then (the
## odometer not counting the jump: ArcadeCar.reset_to re-bases it), the
## four keys and nothing else, the surface names on the landing sample
## where the scene has them. The sample size on the Ring grows by the two
## strings (~40 bytes) and stays inside the band.
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

## The two keys a sample carries where the scene has a Surfaces node, and
## nowhere else (scripts/telemetry.gd _sample).
const SURFACE_FIELDS: Array[String] = ["front_surface", "rear_surface"]

## The reset check's two moves [m]: a nudge under TelemetryRecorder's
## RESET_JUMP_M (5) that must write no event, and a jump well over it that
## must write one - both along the car's nose (the pad's straight and the
## Ring's spawn straight both run on for that).
const RESET_NUDGE_M := 2.0
const RESET_JUMP_M := 20.0

## Ticks recorded between the reset check's moves.
const RESET_FRAMES := 3

## A free sample's size band [bytes]: measured ~309 on the pad and ~330 on
## the Ring at the landing (the README's ~1.1-1.2 MB a minute, ~64-68 MiB
## an hour at 60 Hz); the Ring's carries the two surface strings since
## 2026-09-27 (~40 bytes more, measured below). A field added or dropped,
## or a snap changed, moves it out of the band and re-pins the README.
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
	var surfaces := _surfaces_under(scene)
	if surfaces != null:
		_check(recorder.surfaces == surfaces and surfaces.get_parent() == scene and TelemetryRecorder.find_surfaces(car) == surfaces, "%s: the recorder found the scene's Surfaces node under the scene root (%s) and holds it" % [base, surfaces.name])
	else:
		_check(recorder.surfaces == null and TelemetryRecorder.find_surfaces(car) == null, "%s: no Surfaces node in this scene, the recorder holds none" % base)

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
	var surfaces_at_stop := _surface_names(surfaces)
	recorder.stop()
	_check(not recorder.recording and flagger._recording_recorder() == null, "%s: stopped, the flagger finds none again" % base)

	# The file read back.
	_check_file(file, base, ticks_recorded, car_position, surfaces_at_stop)

	# A reset, in a file of its own.
	await _check_reset(car, recorder, base, surfaces != null)

	# The scene goes, the recorders with it.
	_drop(scene)
	await _step(1)
	_check(not is_instance_valid(recorder) and watch.live_recorders().is_empty() and _recorder_nodes_under(root).is_empty(), "%s: the scene freed, its recorders are gone and the watcher holds none" % base)


## The recorder's file: the header, one sample per tick, every field, the
## car's own state, the size.
func _check_file(file: String, base: String, ticks_recorded: int, car_position: Vector3, surfaces_at_stop: PackedStringArray) -> void:
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
	# THE SURFACE: the two names on every sample where the scene has a
	# Surfaces node, on none where it has not.
	var surface := _surface_fields_of(samples, not surfaces_at_stop.is_empty())
	if surfaces_at_stop.is_empty():
		_check(surface.ok, "%s: no Surfaces node here, so no sample carries front_surface or rear_surface (omitted, not null; %d samples)" % [base, samples.size()])
	else:
		_check(surface.ok and _surface_names_of(last) == surfaces_at_stop, "%s: every sample carries front_surface and rear_surface as plain strings among the Surfaces table's names, the last the node's own at the stop (%s / %s; seen: %s)" % [base, surfaces_at_stop[0], surfaces_at_stop[1], ", ".join(surface.seen)])
	_check(_reset_events_of(objects).is_empty(), "%s: a drive under the throttle writes no reset event (the car never jumped %.0f m in a tick)" % [base, TelemetryRecorder.RESET_JUMP_M])
	var bytes := FileAccess.get_file_as_bytes(file).size()
	var per_sample := float(bytes - lines[0].length() - 1) / samples.size()
	_check(per_sample >= SAMPLE_BYTES_MIN and per_sample <= SAMPLE_BYTES_MAX, "%s: MEASURED %.1f bytes per free sample%s: at 60 a second %.2f MB a minute, %.1f MB (%.1f MiB) an hour, %.2f GB per 16 h day (a mission's samples carry the run's block and are larger)" % [base, per_sample, "" if surfaces_at_stop.is_empty() else " with the two surface strings", per_sample * 3600.0 / 1e6, per_sample * 216000.0 / 1e6, per_sample * 216000.0 / 1048576.0, per_sample * 216000.0 * 16.0 / 1e9])


## THE RESET: a second file of the test's own; the car nudged under the
## threshold (no event), then put RESET_JUMP_M ahead by reset_to: one reset
## event line right after the sample that landed, its before and after the
## two samples' own positions and the car's odometer at each.
func _check_reset(car: ArcadeCar, recorder: TelemetryRecorder, base: String, has_surfaces: bool) -> void:
	var file := _tmp_dir.path_join("%s_reset.jsonl" % base)
	recorder.record_to_file(file)
	await _step(RESET_FRAMES)
	# The nudge: 2 m along the nose, at rest there (reset_to zeroes the
	# velocity, the car stands on the road again) - a jump, but under the
	# threshold.
	car.reset_to(_ahead(car, RESET_NUDGE_M))
	await _step(RESET_FRAMES)
	# The jump: what the state was as the previous sample left it ...
	var before_position := car.global_position
	var before_odometer: float = car.odometer_m
	var t_expected := recorder._seconds(recorder._session_ticks)
	var landing_index := recorder._session_ticks
	car.reset_to(_ahead(car, RESET_JUMP_M))
	await _step(1)
	# ... and as the landing sample's tick left it (this frame's nodes have
	# not ticked yet: the car stands where the recorder sampled it).
	var after_position := car.global_position
	var after_odometer: float = car.odometer_m
	await _step(RESET_FRAMES - 1)
	var ticks := recorder._session_ticks
	recorder.stop()

	var objects: Array[Dictionary] = []
	for raw in FileAccess.get_file_as_string(file).split("\n"):
		var value: Variant = JSON.parse_string(raw) if not raw.strip_edges().is_empty() else null
		if value is Dictionary:
			objects.append(value)
	var samples := _samples_of(file)
	var resets := _reset_events_of(objects)
	var expected_samples := 2 * RESET_FRAMES + 1 + (RESET_FRAMES - 1)
	if not _check(ticks == expected_samples and samples.size() == expected_samples and objects.size() == expected_samples + 2 and resets.size() == 1, "%s: %d ticks recorded to %s: the header, %d samples and exactly ONE reset event (%d) - the %.0f m nudge wrote none, the %.0f m jump one" % [base, ticks, file.get_file(), samples.size(), resets.size(), RESET_NUDGE_M, RESET_JUMP_M]):
		return
	var event: Dictionary = resets[0]
	var event_line := objects.find(event)
	var landing: Dictionary = samples[landing_index]
	var previous: Dictionary = samples[landing_index - 1]
	_check(event_line == landing_index + 2 and objects[event_line - 1] == landing, "%s: the event is the line right after the sample that landed (line %d, the sample at t_session_s %.5f)" % [base, event_line, float(landing.get("t_session_s", -1.0))])
	_check(absf(float(event.get("t", -1.0)) - t_expected) < TICK_TOLERANCE_S and event.get("t") == landing.get("t_session_s"), "%s: its t is that sample's t_session_s, %.5f s in the recorder's own clock" % [base, float(event.get("t", -1.0))])
	var before: Dictionary = event.get("before", {})
	var after: Dictionary = event.get("after", {})
	_check(event.size() == 4 and event.has("event") and event.has("t") and before.size() == 2 and before.has("pos") and before.has("odometer") and after.size() == 2 and after.has("pos") and after.has("odometer"), "%s: the shape - event, t, before {pos, odometer}, after {pos, odometer} - and nothing else" % base)
	_check(before.get("pos") == previous.get("pos") and _on_position(before, before_position) and absf(float(before.get("odometer", -1.0)) - before_odometer) <= TelemetryRecorder.VALUE_SNAP, "%s: before = the previous sample's pos (%.3f, %.3f, %.3f), the car's own before the jump to the snap, and its odometer then (%.3f m)" % [base, before_position.x, before_position.y, before_position.z, float(before.get("odometer", -1.0))])
	_check(after.get("pos") == landing.get("pos") and _on_position(after, after_position) and absf(float(after.get("odometer", -1.0)) - after_odometer) <= TelemetryRecorder.VALUE_SNAP, "%s: after = the landing sample's pos (%.3f, %.3f, %.3f), the car's own after it to the snap, and its odometer then (%.3f m)" % [base, after_position.x, after_position.y, after_position.z, float(after.get("odometer", -1.0))])
	var jumped := before_position.distance_to(after_position)
	var nudged: float = _position_of(samples[RESET_FRAMES]).distance_to(_position_of(samples[RESET_FRAMES - 1]))
	_check(jumped > TelemetryRecorder.RESET_JUMP_M and absf(jumped - RESET_JUMP_M) < 1.0 and nudged < TelemetryRecorder.RESET_JUMP_M and nudged > RESET_NUDGE_M - 1.0 and absf(float(after.get("odometer", 0.0)) - float(before.get("odometer", 0.0))) < 0.5, "%s: the jump was %.2f m (over the %.0f m threshold), the nudge %.2f m (under it, no event), and the odometer did not count the jump (%.3f -> %.3f m: reset_to re-bases it)" % [base, jumped, TelemetryRecorder.RESET_JUMP_M, nudged, float(before.get("odometer", 0.0)), float(after.get("odometer", 0.0))])
	var surface := _surface_fields_of(samples, has_surfaces)
	_check(surface.ok, "%s: the samples around the reset carry the surface names as the scene does (%s)" % [base, ("seen: " + ", ".join(surface.seen)) if has_surfaces else "no Surfaces node, no keys"])


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
	if not _check(recorder != null and nodes.size() == 1 and nodes[0] == recorder and recorder.get_parent() == root and recorder.car == car and recorder._manager == null and recorder.surfaces == null and not recorder.recording, "a bare car under the root gets one recorder node, under the root, no manager, no Surfaces node (the root's subtree is no scene of its own), idle"):
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


## The pose `distance` m ahead of the car along its heading, for reset_to:
## the yaw kept, y 0 - reset_to's target height stands ON the road
## profile (ArcadeCar._settle_suspension adds it to the road's height
## under the wheels: every Ring test passes y 0, and on the Ring the car's
## own global y is the road's ~627 m, which would be added twice).
func _ahead(car: ArcadeCar, distance: float) -> Transform3D:
	var yaw := Basis(Vector3.UP, car.global_rotation.y)
	var ahead := car.global_position - yaw.z * distance
	return Transform3D(yaw, Vector3(ahead.x, 0.0, ahead.z))


## A sample's pos as a Vector3 (zero where it has none).
func _position_of(sample: Dictionary) -> Vector3:
	var pos: Array = sample.get("pos", [])
	return Vector3(float(pos[0]), float(pos[1]), float(pos[2])) if pos.size() == 3 else Vector3.ZERO


## The reset event lines among a file's objects.
func _reset_events_of(objects: Array[Dictionary]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for object in objects:
		if object.get("event") == "reset":
			out.append(object)
	return out


## The first Surfaces node under `node`, or null.
func _surfaces_under(node: Node) -> Surfaces:
	if node is Surfaces:
		return node
	for child in node.get_children():
		var found := _surfaces_under(child)
		if found != null:
			return found
	return null


## The node's two axle names as the sample writes them; empty for none.
func _surface_names(surfaces: Surfaces) -> PackedStringArray:
	if surfaces == null:
		return PackedStringArray()
	return PackedStringArray([String(surfaces.front_surface), String(surfaces.rear_surface)])


## A sample's two surface strings, empty where it carries none.
func _surface_names_of(sample: Dictionary) -> PackedStringArray:
	if not sample.has("front_surface") or not sample.has("rear_surface"):
		return PackedStringArray()
	return PackedStringArray([str(sample["front_surface"]), str(sample["rear_surface"])])


## Whether every sample carries the two surface keys as strings among the
## table's names (`expected` true) or neither key at all (false), and the
## distinct names seen.
func _surface_fields_of(samples: Array[Dictionary], expected: bool) -> Dictionary:
	var ok := not samples.is_empty()
	var seen := PackedStringArray()
	for sample in samples:
		for field in SURFACE_FIELDS:
			if not expected:
				ok = ok and not sample.has(field)
				continue
			var value: Variant = sample.get(field, null)
			ok = ok and value is String and Surfaces.SURFACE_NAMES.has(value)
			if value is String and not seen.has(value):
				seen.append(value)
	return {"ok": ok, "seen": seen}


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
