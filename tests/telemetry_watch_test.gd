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
## (docs/issues-analysis-2026-09-24.md §1.4). This test loads EVERY scene in
## the repo that instances the car - main.tscn (the pad) and
## eifel_ring.tscn (the Ring), the list pinned in CAR_SCENES and held
## against a scan of scenes/*.tscn for car.tscn instances, so a scene that
## gains a car and is not fenced here fails - and, for each: the
## TelemetryWatch autoload (scripts/telemetry_watch.gd) made a
## TelemetryRecorder for the car, exactly one, appended as the scene root's
## last child, attached to the car, idle with no window (FD_TELEMETRY=0
## pinned first, the refuel test's idiom: no test writes driver data), the
## MissionManager listening through it where there is one and no manager
## where there is none; the issue flagger's own walk finds it once it
## records; switched on to a file of this test's own (record_to_file: never
## under user://) it WRITES - one sample per physics tick, the sample count
## the recorder's own tick count, the timestamps counting every tick, every
## field of the sample, the last sample the car's own position, the car
## having moved -, the issue flag binds a drive to it (telemetry, the
## recorder's session id, a real range; was the odometer and the wall clock
## on the Ring), and the recorder goes with the scene. A bare car straight
## under the root gets one too (under the root), loses it when it leaves
## the tree and gets a fresh one when it comes back. The ruling pinned:
## both strides 1 (SAMPLE_STRIDE_TICKS, FREE_SAMPLE_STRIDE_TICKS; was 5 and
## 30). The size measured and printed: bytes per sample, MB a minute, MB an
## hour at 60 Hz - the README's numbers come from here.
##
## A scene without recording is a test failure here, not a discovery.
## Exits 0 on success, 1 on any failed check.

const CAR_SCENE := "res://scenes/car.tscn"
const SCENES_DIR := "res://scenes"

## Every scene in the repo that instances the car. The scan in
## _check_scene_list holds this list to the .tscn files' own ext_resources:
## a new scene with a car in it must join here to keep the suite green.
const CAR_SCENES: Array[String] = ["res://scenes/main.tscn", "res://scenes/eifel_ring.tscn"]

## Physics frames to let a scene settle after a load (the Ring builds its
## road at load; the watcher's attach is one deferred call).
const SETTLE_FRAMES := 20

## Frames the car is driven with the throttle key down [physics ticks].
const DRIVE_FRAMES := 60

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

## A free sample's size band [bytes]: measured ~308 at the landing (the
## README's ~1.1 MB a minute, ~64 MiB an hour at 60 Hz). A field added or
## dropped, or a snap changed, moves it out of the band and re-pins the
## README.
const SAMPLE_BYTES_MIN := 200
const SAMPLE_BYTES_MAX := 450

## A timestamp is on its tick within this [s] (TIME_SNAP is 1e-5).
const TICK_TOLERANCE_S := 0.0001

var _failures := 0
var _tmp_dir := ""
var _user_dir_before := false
var _measured_bytes: Array[float] = []


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
	_check(node_added.is_connected(watch._on_node_added) and watch.live_recorders().is_empty(), "it watches the tree's node_added, and holds no recorder while there is no car")
	_check(TelemetryRecorder.SAMPLE_STRIDE_TICKS == 1 and TelemetryRecorder.FREE_SAMPLE_STRIDE_TICKS == 1, "THE RULING: both strides are 1, every physics tick, missions and free driving alike (was 5 and 30)")
	_check(not TelemetryRecorder.should_record(), "FD_TELEMETRY=0 pinned by this test: no recorder below starts a session of its own")
	return true


## Every scene under scenes/ that instances car.tscn is in CAR_SCENES, and
## nothing in CAR_SCENES is without one.
func _check_scene_list() -> void:
	var found := PackedStringArray()
	for file_name in DirAccess.get_files_at(SCENES_DIR):
		if not file_name.ends_with(".tscn"):
			continue
		var path := SCENES_DIR.path_join(file_name)
		if FileAccess.get_file_as_string(path).contains('path="%s"' % CAR_SCENE):
			found.append(path)
	found.sort()
	var fenced := PackedStringArray(CAR_SCENES)
	fenced.sort()
	_check(found == fenced, "every scene that instances the car is fenced here: %s (a scene that gains a car must join CAR_SCENES)" % ", ".join(found))


# =============================================================================
#  A scene with a car
# =============================================================================

## The scene loaded whole: the watcher's recorder on its car, idle; then
## writing to a file of this test's own, the issue flag bound to it, the
## file read back; then the scene freed, the recorder with it.
func _check_scene(scene_path: String) -> void:
	var base := scene_path.get_file().get_basename()
	var packed: PackedScene = load(scene_path)
	if not _check(packed != null, "%s loads" % base):
		return
	var scene := packed.instantiate()
	root.add_child(scene)
	await _step(SETTLE_FRAMES)
	var car := scene.get_node_or_null("Car") as ArcadeCar
	var hud := scene.get_node_or_null("HUD") as HUD
	var missions := scene.get_node_or_null("MissionManager") as MissionManager
	if not _check(car != null and hud != null, "%s: Car and HUD exist" % base):
		_drop(scene)
		return
	var watch := TelemetryWatcher.of(self)
	var recorder := watch.recorder_for(car)
	if not _check(recorder != null and recorder.car == car and recorder.is_inside_tree(), "%s: the watcher made a TelemetryRecorder for the car, attached to it" % base):
		_drop(scene)
		return
	_check(recorder.get_parent() == scene and scene.get_child(scene.get_child_count() - 1) == recorder and recorder.name == TelemetryWatcher.RECORDER_NAME and watch.scene_root_of(car) == scene, "%s: it stands as the scene root's last child, named %s (the flagger's walk finds it there; it ticks after every node the scene came with)" % [base, TelemetryWatcher.RECORDER_NAME])
	var live := watch.live_recorders()
	_check(live.size() == 1 and live[0] == recorder, "%s: exactly one recorder for the one car" % base)
	_check(not recorder.recording and recorder._session_id == 0, "%s: idle with no window: attached, no session started, nothing written" % base)
	if missions != null:
		_check(missions.telemetry == recorder and recorder._manager == missions and missions.mission_started.is_connected(recorder._on_mission_started) and missions.mission_finished.is_connected(recorder._on_mission_finished) and missions.mission_aborted.is_connected(recorder._on_mission_aborted), "%s: the MissionManager adopted it (its `telemetry` is the watcher's recorder) and the recorder listens to its three signals" % base)
	else:
		_check(recorder._manager == null, "%s: no missions here, the recorder listens to none (attached with a null manager)" % base)
	var flagger: IssueFlagger = hud.flagger
	_check(flagger != null and flagger.car == car and flagger._recording_recorder() == null, "%s: the HUD's flagger finds no recorder RECORDING yet (its own walk from the scene root)" % base)

	# Switched on to a file of this test's own.
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

	# The scene goes, the recorder with it.
	_drop(scene)
	await _step(1)
	_check(not is_instance_valid(recorder) and watch.live_recorders().is_empty(), "%s: the scene freed, its recorder is gone and the watcher holds none" % base)


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
	var position: Array = last.get("pos", [])
	var last_on_car := position.size() == 3 and absf(float(position[0]) - car_position.x) <= TelemetryRecorder.VALUE_SNAP and absf(float(position[1]) - car_position.y) <= TelemetryRecorder.VALUE_SNAP and absf(float(position[2]) - car_position.z) <= TelemetryRecorder.VALUE_SNAP
	_check(last_on_car and float(last.get("speed_ms", 0.0)) > 0.5 and float(last.get("throttle", 0.0)) == 0.0, "%s: the last sample is the car's own state at the stop: its position to the snap (%.3f, %.3f, %.3f), %.1f m/s, the throttle let go" % [base, car_position.x, car_position.y, car_position.z, float(last.get("speed_ms", 0.0))])
	var bytes := FileAccess.get_file_as_bytes(file).size()
	var per_sample := float(bytes - lines[0].length() - 1) / samples.size()
	_measured_bytes.append(per_sample)
	_check(per_sample >= SAMPLE_BYTES_MIN and per_sample <= SAMPLE_BYTES_MAX, "%s: MEASURED %.1f bytes per sample: at 60 a second %.2f MB a minute, %.1f MB (%.1f MiB) an hour, %.2f GB per 16 h day" % [base, per_sample, per_sample * 3600.0 / 1e6, per_sample * 216000.0 / 1e6, per_sample * 216000.0 / 1048576.0, per_sample * 216000.0 * 16.0 / 1e9])


# =============================================================================
#  A bare car
# =============================================================================

## A car straight under the root, in no scene: a recorder under the root,
## gone when the car leaves, a fresh one when it comes back.
func _check_bare_car() -> void:
	var watch := TelemetryWatcher.of(self)
	var car: ArcadeCar = (load(CAR_SCENE) as PackedScene).instantiate()
	root.add_child(car)
	await _step(SETTLE_FRAMES)
	var recorder := watch.recorder_for(car)
	if not _check(recorder != null and recorder.get_parent() == root and recorder.car == car and recorder._manager == null and not recorder.recording, "a bare car under the root gets a recorder under the root, no manager, idle"):
		root.remove_child(car)
		car.free()
		return
	var file := _tmp_dir.path_join("bare.jsonl")
	recorder.record_to_file(file)
	await _step(5)
	var ticks := recorder._session_ticks
	root.remove_child(car)
	await _step(1)
	var samples := 0
	for raw in FileAccess.get_file_as_string(file).split("\n"):
		var value: Variant = JSON.parse_string(raw) if not raw.strip_edges().is_empty() else null
		if value is Dictionary and (value as Dictionary).has("t_session_s"):
			samples += 1
	_check(not is_instance_valid(recorder) and watch.recorder_for(car) == null and watch.live_recorders().is_empty() and ticks == 5 and samples == 5, "the car out of the tree: its recorder stopped (5 ticks, 5 samples in the file) and freed, the watcher holds none")
	root.add_child(car)
	await _step(2)
	var again := watch.recorder_for(car)
	_check(again != null and again.car == car and again.get_parent() == root and not again.recording, "the car back in the tree gets a fresh recorder")
	root.remove_child(car)
	await _step(1)
	car.free()
	_check(watch.live_recorders().is_empty(), "and none is left once it is gone for good")


# =============================================================================
#  Helpers
# =============================================================================

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
