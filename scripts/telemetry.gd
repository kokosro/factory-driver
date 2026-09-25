class_name TelemetryRecorder
extends Node
## Telemetry: what the car was doing, written down while it happens, so a drive
## can be read back long after it was driven. One JSON object per line
## (JSON-lines, .jsonl): a session_start line at the top, then one sample per
## SAMPLE_STRIDE_TICKS physics ticks, then an event line closing the file.
##
## The recorder only ever READS the car and the mission: it presses no input,
## moves nothing and decides nothing. Nothing in the simulation depends on
## whether it is on.
##
## TELEMETRY EVERYWHERE (2026-09-25): one of these rides EVERY car in EVERY
## scene, made by the TelemetryWatch autoload (scripts/telemetry_watch.gd)
## the frame the car enters the tree and parented to the car's scene root -
## no scene wires recording any more. was: main.tscn's MissionManager made
## its own in _ready and eifel_ring.tscn made none, so the Ring's drives
## were never written and its 22 flagged issues have no replay evidence
## (docs/issues-analysis-2026-09-24.md §1.4) -> the watcher makes one for
## every car, attach() takes a null manager (a scene without missions) and
## the manager, where there is one, joins in through listen().
##
## Where the files go:
##   user://telemetry/<YYYY-MM-DD>/<session>_<HHMMSS>_<context>.jsonl
##   user://telemetry/index.json          the running summary (see load_index)
## e.g. 0007_103245_free.jsonl - session 7, started 10:32:45, free driving.
## NOTHING IN THERE IS EVER DELETED BY THE GAME: the sessions accumulate for as
## long as the driver keeps them, and historical telemetry is removed by hand
## when disk space is wanted (README, Telemetry: what is safe to delete).
##
## Two streams. Free driving gets one session-length file at
## FREE_SAMPLE_STRIDE_TICKS; a mission gets a file of its own at
## SAMPLE_STRIDE_TICKS, and the free file PAUSES while it runs (the mission file
## already holds those ticks, with the run's own numbers, and the free file is
## there to show what happened between missions). Both strides are 1 now -
## every physics tick, replay grade - and stay two constants so the
## session_start line names each and a lighter hybrid can come later.
##
## WALL CLOCK: two things here read the system clock - the file NAMES (the date
## folder and the time prefix) and the `started_at` field of the session_start
## line, which is there so a file can be found again by when it was driven.
## Nothing else does. Every timestamp inside a sample is counted in physics
## ticks times TICK_SECONDS, so the same drive always writes the same numbers.
## The test suite asserts the tick-derived fields, the schema and the event
## lines, never the wall-clock ones, and its own recording goes to a fixed tmp
## path (see record_to_file) instead of user://: recording cannot make the suite
## differ from one run to the next.
# was: the last SESSIONS_KEPT (20) sessions' files were kept and the oldest
# deleted when a new session started -> nothing is ever deleted automatically
# (the driver's decision, 2026-09-24: "let them grow and let user delete any
# historical telemetry if they need disk space").

## Ticks between samples while a mission is recorded [physics ticks]: 60 Hz
## physics, so 60 samples a second, every tick.
# was 5 (12 a second) -> 1 (TELEMETRY EVERYWHERE, 2026-09-25, the driver's
# canon: "the full verbose telemetry that we can use to replay exactly what
# happened"). Measured headless (tests/telemetry_watch_test.gd prints it):
# one full-set sample is ~310 bytes on the pad and ~330 on the Ring (its
# coordinates are longer), so a tick-by-tick session writes ~19-20 kB/s,
# ~1.1-1.2 MB a minute, ~64-68 MiB (67-71 MB) an hour, ~1.1 GB per 16 h
# driving day - accepted under the driver's standing
# ruling that nothing is ever deleted and the driver clears what they want
# gone (2026-09-24). A lighter hybrid (the core fields every tick, the rich
# ones coarser) is a possible later landing if the driver ever asks; not
# built.
const SAMPLE_STRIDE_TICKS := 1

## ... and between samples of free driving [physics ticks]: every tick too.
## Free driving runs for as long as the game is open; it is written at the
## same rate as a mission now, so a drive anywhere can be replayed.
# was 30 (2 a second, "written coarsely") -> 1 (the same ruling as above:
# the Ring's drives are all free driving, and they are the ones to replay).
const FREE_SAMPLE_STRIDE_TICKS := 1

## One physics tick [s]: the project's fixed step (physics_ticks_per_second is
## the engine default, 60). Every timestamp in a file is a tick count times
## this, never a clock reading.
const TICK_SECONDS := 1.0 / 60.0

# was: `const SESSIONS_KEPT := 20`, how many sessions' files were kept on disk,
# the oldest deleted when a new session started -> no such number: every
# session's files stay until the driver deletes them (2026-09-24).

## Everything this node writes lives under here, and nothing outside it is ever
## touched. Named under user:// as ever; where that is on disk for this run
## is DataDir's (scripts/data_dir.gd: FD_DATA_DIR or the garage's SETTINGS
## page), and every open, listing and removal below goes through
## DataDir.resolve - a test's fixed path (record_to_file) is itself.
const ROOT_DIR := "user://telemetry"
const INDEX_PATH := "user://telemetry/index.json"

## Set FD_TELEMETRY=1 to record even with no window (a headless run records
## nothing otherwise, see should_record).
const FORCE_ENV := "FD_TELEMETRY"

## Numbers are snapped before they are written: state to a thousandth of its
## unit, times to a hundred-thousandth of a second (a tick is 0.01667 s). Keeps
## the files readable and small without losing anything a drive shows.
const VALUE_SNAP := 0.001
const TIME_SNAP := 0.00001

## The car being recorded. Read only: the recorder never sets anything on it.
var car: ArcadeCar

## True while a file is open and samples are going into it.
var recording := false

## The stored summary, as load_index() returns it. Read at startup, updated
## after every finished mission (in memory always, on disk while recording).
var index: Dictionary = {}

## The mission manager, kept as a plain Node: the recorder listens to its
## signals and reads its `run` while a mission is on. Null on a scene
## without missions (the Ring): only free driving is written there.
var _manager: Node

## Physics ticks since recording started, and since the current run started.
var _session_ticks := 0
var _run_ticks := 0

var _session_id := 0
var _free_file: FileAccess
var _mission_file: FileAccess

## The test definition of the run being recorded; empty when none is.
var _mission_test: Dictionary = {}

## Set by record_to_file(): everything goes into this one file and nothing is
## written under user:// at all.
var _fixed_path := ""


# =============================================================================
#  Turning it on
# =============================================================================

## Whether a session should be recorded at all: yes in the running game, no
## with no window (the test suite, a headless export) unless FD_TELEMETRY=1
## asks for it.
static func should_record() -> bool:
	if OS.get_environment(FORCE_ENV) == "1":
		return true
	return DisplayServer.get_name() != "headless"


## Takes the car to watch and, where there is one, the mission manager: reads
## the stored summary and listens for runs starting and ending. Recording
## itself starts with start_session() or record_to_file().
# was: manager.mission_started / mission_finished / mission_aborted
# connected unconditionally (the manager made the recorder, so there always
# was one) -> null is a manager too: the TelemetryWatch autoload attaches
# with none on a scene without missions (the Ring), and a MissionManager
# that finds the recorder later joins through listen().
func attach(manager: Node, target_car: ArcadeCar) -> void:
	car = target_car
	index = load_index()
	if manager != null:
		listen(manager)


## Listens to `manager`'s runs from now on: mission_started opens the run's
## file, mission_finished / mission_aborted close it. Once per manager (a
## second call for the same one connects nothing twice); a manager listened
## to before is let go.
func listen(manager: Node) -> void:
	if manager == _manager or manager == null:
		return
	if _manager != null and is_instance_valid(_manager):
		_manager.mission_started.disconnect(_on_mission_started)
		_manager.mission_finished.disconnect(_on_mission_finished)
		_manager.mission_aborted.disconnect(_on_mission_aborted)
	_manager = manager
	manager.mission_started.connect(_on_mission_started)
	manager.mission_finished.connect(_on_mission_finished)
	manager.mission_aborted.connect(_on_mission_aborted)


## Starts a normal session: takes the next session id, notes it in the index's
## sessions list (which grows by one int per session, for as long as the data
## folder lives: nothing here trims it or the files it names) and opens the
## free-driving file.
# was: the sessions list was trimmed to the last SESSIONS_KEPT (20) ids
# (`while sessions.size() > SESSIONS_KEPT: sessions.pop_front()`) and
# _prune_sessions deleted the .jsonl files of every session not in it -> the
# list only grows and no file is deleted, ever: telemetry is kept
# indefinitely, the driver removes what they want gone (2026-09-24).
func start_session() -> void:
	if recording:
		return
	_session_id = int(index.get("next_session_id", 1))
	index["next_session_id"] = _session_id + 1
	var sessions: Array = index.get("sessions", [])
	sessions.append(_session_id)
	index["sessions"] = sessions
	_save_index()
	_session_ticks = 0
	_free_file = _open(_unique_path(_file_path("free")))
	if _free_file == null:
		return
	_write(_free_file, _session_start_line("free"))
	recording = true


## Debug and tests: records to this one file, wherever it is, and writes
## nothing under user:// - no index, no session id. The file holds
## one run: it is closed as soon as that run's result or abort is written.
func record_to_file(path: String) -> void:
	stop()
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	_fixed_path = path
	_session_ticks = 0
	_free_file = _open(path)
	if _free_file == null:
		return
	_write(_free_file, _session_start_line("debug"))
	recording = true


## Closes whatever is open and stops sampling.
func stop() -> void:
	_close(_mission_file)
	_mission_file = null
	_close(_free_file)
	_free_file = null
	_mission_test = {}
	_fixed_path = ""
	recording = false


func _exit_tree() -> void:
	stop()


# =============================================================================
#  Sampling
# =============================================================================

## One sample every stride, off the state the tick just left behind. The
## watcher appends this node after every node the scene came with, so the
## manager's run has already been ticked (was: the manager was this node's
## parent, the same order).
func _physics_process(_delta: float) -> void:
	if not recording or car == null:
		return
	if not _mission_test.is_empty():
		if _run_ticks % SAMPLE_STRIDE_TICKS == 0:
			_write(_mission_file if _mission_file != null else _free_file, _sample(true))
		_run_ticks += 1
	elif _session_ticks % FREE_SAMPLE_STRIDE_TICKS == 0:
		_write(_free_file, _sample(false))
	_session_ticks += 1


## One sample line. The car's state as the physics left it, plus the mission's
## own numbers while a run is on. Units are in the key names where they are not
## obvious; see the file header for what is tick-derived and what is not.
func _sample(in_mission: bool) -> String:
	var position := car.global_position
	var sample := {
		# Seconds since recording started, counted in ticks.
		"t_session_s": _seconds(_session_ticks),
		# Where the car is [m], world space, and where its nose points
		# [degrees], left positive.
		"pos": [snappedf(position.x, VALUE_SNAP), snappedf(position.y, VALUE_SNAP), snappedf(position.z, VALUE_SNAP)],
		"heading_deg": snappedf(rad_to_deg(car.global_rotation.y), VALUE_SNAP),
		# Speed along the nose [m/s], negative while reversing.
		"speed_ms": snappedf(car.forward_speed, VALUE_SNAP),
		# 0 = neutral, 1..5 forward, -1 = reverse engaged.
		"gear": -1 if car.reverse_engaged else car.gear,
		"rpm": snappedf(car.engine_rpm, VALUE_SNAP),
		# What the driver's feet are doing: the two pedals 0..1 as the
		# drivetrain is given them (ArcadeCar.throttle_pedal / brake_pedal; in
		# reverse the throttle is the brake key's pedal, see
		# ArcadeCar.reverse_engaged). The handbrake is its key, steering a share
		# of full lock, -1 (right) .. +1 (left).
		# was the strength of the accelerate / brake keys -> the pedals: a key is
		# on / off, the foot is not, and a driver without keys (set_driver_input)
		# never pressed one.
		"throttle": snappedf(car.throttle_pedal, VALUE_SNAP),
		"brake": snappedf(car.brake_pedal, VALUE_SNAP),
		"handbrake": snappedf(Input.get_action_strength(&"handbrake"), VALUE_SNAP),
		"steer": snappedf(car.steer, VALUE_SNAP),
		# Share of the load the car carries on each axle (the two add to 1).
		"load_front": snappedf(car.front_load_fraction, VALUE_SNAP),
		"load_rear": snappedf(car.rear_load_fraction, VALUE_SNAP),
		# How far each axle's tyres are sliding: slip angles [degrees] and slip
		# ratios (a speed difference over the road speed, no unit).
		"slip_front_deg": snappedf(rad_to_deg(car.front_slip_angle), VALUE_SNAP),
		"slip_rear_deg": snappedf(rad_to_deg(car.rear_slip_angle), VALUE_SNAP),
		"slip_ratio_front": snappedf(car.front_slip_ratio, VALUE_SNAP),
		"slip_ratio_rear": snappedf(car.rear_slip_ratio, VALUE_SNAP),
		# How fast the nose is swinging [degrees/s], left positive.
		"yaw_rate_deg_s": snappedf(rad_to_deg(car.yaw_rate), VALUE_SNAP),
	}
	if in_mission:
		# Seconds since the test began (the car put on its start point), counted
		# in ticks, and what the run says about itself (HandlingTests.progress(),
		# which depends on kind). t_run_s and elapsed_s are both since the test
		# began; the run clock, which starts at the start line and is what a
		# result's run_time_s reports, rides in the progress: run_started and
		# run_time_s.
		sample["t_run_s"] = _seconds(_run_ticks)
		var run: HandlingTests = _manager.run
		sample["mission"] = {
			"title": _mission_test.get("title", ""),
			"kind": String(_mission_test.get("kind", &"")),
			"elapsed_s": snappedf(run.elapsed, TIME_SNAP) if run != null else 0.0,
			"progress": _snapped_dictionary(run.progress()) if run != null else {},
		}
	return JSON.stringify(sample)


## Seconds from a tick count, the only clock a sample knows.
func _seconds(ticks: int) -> float:
	return snappedf(ticks * TICK_SECONDS, TIME_SNAP)


## The same dictionary with its floats snapped, so a run's own numbers are
## written as tidily as the car's.
func _snapped_dictionary(values: Dictionary) -> Dictionary:
	var out := {}
	for key: Variant in values:
		var value: Variant = values[key]
		out[String(key)] = snappedf(value, VALUE_SNAP) if value is float else value
	return out


# =============================================================================
#  Runs
# =============================================================================

func _on_mission_started(_index: int, definition: Dictionary) -> void:
	if not recording:
		return
	_mission_test = definition
	_run_ticks = 0
	if _fixed_path != "":
		return
	# A file of its own for the run, e.g. 0007_103312_mission_slalom.jsonl.
	var context := "mission_%s" % _slug(String(definition.get("title", "run")))
	_mission_file = _open(_unique_path(_file_path(context)))
	if _mission_file != null:
		_write(_mission_file, _session_start_line(context))


## A finished run: the verdict goes in as the file's last line, and the stored
## summary gains the run.
# was: run_time_s, as the run reports it, was the time from the start of the
# test to the end of the run, settle included -> it is the run clock: from the
# car crossing the test's start line to its finish (HandlingTests, "The run
# clock"). Nothing changes here, the recorder writes what the run reports; but
# times stored before the change are 2.5 - 3.5 s longer for the same drive, so
# a stored best from then falls to the first like drive on the new clock.
func _on_mission_finished(_index: int, outcome: Dictionary) -> void:
	if not recording or _mission_test.is_empty():
		return
	var metrics: Dictionary = outcome.get("metrics", {})
	var run_time: float = metrics.get("run_time_s", 0.0)
	var medal := HandlingTests.medal_for(_mission_test, run_time) if outcome.get("passed", false) else ""
	# The summary first, while the run is still known; a debug recording keeps
	# out of it, so a test run never touches the stored index.
	if _fixed_path == "":
		_note_run(_mission_test, outcome, run_time, medal)
	_end_run(JSON.stringify({
		"event": "result",
		"passed": outcome.get("passed", false),
		"run_time_s": snappedf(run_time, TIME_SNAP),
		"medal": medal,
	}))


## An aborted run has no verdict; the file says so and ends there.
func _on_mission_aborted(_index: int) -> void:
	if not recording or _mission_test.is_empty():
		return
	_end_run(JSON.stringify({"event": "aborted"}))


## Writes a run's last line, closes its file and goes back to free driving. In
## a fixed-path recording there is nothing to go back to: the file held the one
## run, so recording stops.
func _end_run(last_line: String) -> void:
	_write(_mission_file if _mission_file != null else _free_file, last_line)
	_close(_mission_file)
	_mission_file = null
	_mission_test = {}
	if _fixed_path != "":
		stop()


## Folds a finished run into the stored summary: one more run of this test, its
## time and medal as the last, and a new best if it passed in less time than
## the standing one.
func _note_run(test: Dictionary, outcome: Dictionary, run_time: float, medal: String) -> void:
	var title := String(test.get("title", ""))
	if title == "":
		return
	var best: Dictionary = index.get("best", {})
	var entry: Dictionary = best.get(title, {"best_time_s": 0.0, "runs": 0, "last_time_s": 0.0, "last_medal": ""})
	entry["runs"] = int(entry.get("runs", 0)) + 1
	entry["last_time_s"] = snappedf(run_time, TIME_SNAP)
	entry["last_medal"] = medal
	var standing: float = entry.get("best_time_s", 0.0)
	if outcome.get("passed", false) and (standing <= 0.0 or run_time < standing):
		entry["best_time_s"] = snappedf(run_time, TIME_SNAP)
	best[title] = entry
	index["best"] = best
	# Which test was driven last: what the HUD's summary line is about.
	index["last_test"] = title
	_save_index()


# =============================================================================
#  The stored summary
# =============================================================================

## The index as it stands on disk, or empty if there is none yet:
##   {
##     "next_session_id": 8,
##     "sessions": [1, 2, ...],          every session id started so far (grows
##                                       for good; INFORMATIONAL: nothing opens
##                                       a file by it - a session whose files
##                                       the driver has deleted stays listed
##                                       and harms nothing; was: the ids whose
##                                       files were kept, the rest pruned)
##     "last_test": "SLALOM",            the test driven last
##     "best": { "SLALOM": { "best_time_s": 30.9, "runs": 4,
##                           "last_time_s": 33.2, "last_medal": "silver" } }
##   }
## Times are seconds; best_time_s is 0 for a test that has never been passed.
static func load_index() -> Dictionary:
	var index_on_disk := DataDir.resolve(INDEX_PATH)
	if not FileAccess.file_exists(index_on_disk):
		return {}
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(index_on_disk))
	if not value is Dictionary:
		return {}
	# JSON knows one kind of number: the counts come back as 25.0 and would be
	# written back out that way. They are counts, so they go back to whole
	# numbers here.
	var stored: Dictionary = value
	stored["next_session_id"] = int(stored.get("next_session_id", 1))
	var sessions: Array = stored.get("sessions", [])
	for position in sessions.size():
		sessions[position] = int(sessions[position])
	var best_map: Dictionary = stored.get("best", {})
	for title: String in best_map:
		var entry: Dictionary = best_map[title]
		entry["runs"] = int(entry.get("runs", 0))
	return stored


## The summary the idle mission line ends with, e.g.
## " | last: SILVER, best: 30.9 s": the medal the last run earned and your best
## time on that test. Empty while nothing has been driven yet, so the line
## simply ends where it used to.
static func idle_suffix(stored: Dictionary) -> String:
	var entry := last_entry(stored)
	if entry.is_empty():
		return ""
	var medal := String(entry.get("last_medal", ""))
	var medal_text := medal.to_upper() if medal != "" else "NO MEDAL"
	var best: float = entry.get("best_time_s", 0.0)
	if best <= 0.0:
		return " | last: %s" % medal_text
	return " | last: %s, best: %.1f s" % [medal_text, best]


## The line the PASSED banner carries under the medal times, e.g.
## "BEST 30.9 s SILVER — your 4 run(s)": your standing best on this test, the
## medal it is worth, and how many times you have driven it. Empty for a test
## you have never passed, and the banner then leaves the line out. The best is
## the one you had going into this run; the run just driven joins it a moment
## later, when the recorder notes it down.
static func best_line(stored: Dictionary, test: Dictionary) -> String:
	var best_map: Dictionary = stored.get("best", {})
	var entry: Dictionary = best_map.get(String(test.get("title", "")), {})
	var best: float = entry.get("best_time_s", 0.0)
	if best <= 0.0:
		return ""
	var medal := HandlingTests.medal_for(test, best)
	var medal_text := medal.to_upper() if medal != "" else "NO MEDAL"
	return "BEST %.1f s %s — your %d run(s)" % [best, medal_text, int(entry.get("runs", 0))]


## The stored record of the test driven last, or empty if there is none.
static func last_entry(stored: Dictionary) -> Dictionary:
	var best_map: Dictionary = stored.get("best", {})
	var title := String(stored.get("last_test", ""))
	var entry: Variant = best_map.get(title, {})
	return entry if entry is Dictionary else {}


# =============================================================================
#  Files
# =============================================================================

## The first line of every file, and the only one that reads the clock: when
## the session started (local time, ISO-ish, for finding a drive again), the
## engine that wrote it, and the sampling it was written at.
func _session_start_line(context: String) -> String:
	var now := Time.get_datetime_dict_from_system()
	return JSON.stringify({
		"event": "session_start",
		"session_id": _session_id,
		"context": context,
		# Wall clock, by design. Nothing is measured against it.
		"started_at": "%04d-%02d-%02dT%02d:%02d:%02d" % [now.year, now.month, now.day, now.hour, now.minute, now.second],
		"godot_version": Engine.get_version_info().string,
		"physics_ticks_per_second": Engine.physics_ticks_per_second,
		"sample_stride_ticks": SAMPLE_STRIDE_TICKS,
		"free_sample_stride_ticks": FREE_SAMPLE_STRIDE_TICKS,
	})


## user://telemetry/<date>/<session>_<time>_<context>.jsonl, the folder made if
## it is not there. The date and time are wall clock: they are the file's name,
## nothing inside it.
func _file_path(context: String) -> String:
	var now := Time.get_datetime_dict_from_system()
	var day := "%04d-%02d-%02d" % [now.year, now.month, now.day]
	var file_name := "%04d_%02d%02d%02d_%s.jsonl" % [_session_id, now.hour, now.minute, now.second, context]
	var dir := ROOT_DIR.path_join(day)
	DirAccess.make_dir_recursive_absolute(DataDir.resolve(dir))
	return dir.path_join(file_name)


## The same path with a number added if something is already there (two runs
## started inside the same second), so a file is never written over. "" when
## even _99 is taken: there is no name to write to, and the caller opens
## nothing (was: the occupied original came back after the loop, and the open
## would have written over it - found by the codex cross-review, 2026-09-24;
## recorded, not introduced, by this landing).
func _unique_path(path: String) -> String:
	if not FileAccess.file_exists(DataDir.resolve(path)):
		return path
	var stem := path.trim_suffix(".jsonl")
	for attempt in range(2, 100):
		var candidate := "%s_%d.jsonl" % [stem, attempt]
		if not FileAccess.file_exists(DataDir.resolve(candidate)):
			return candidate
	return ""


func _open(path: String) -> FileAccess:
	if path == "":
		return null
	return FileAccess.open(DataDir.resolve(path), FileAccess.WRITE)


## One line into a file, flushed as it goes: a game that is closed mid-drive
## still leaves the drive behind.
func _write(file: FileAccess, line: String) -> void:
	if file == null:
		return
	file.store_line(line)
	file.flush()


func _close(file: FileAccess) -> void:
	if file != null:
		file.close()


func _save_index() -> void:
	DirAccess.make_dir_recursive_absolute(DataDir.resolve(ROOT_DIR))
	var file := FileAccess.open(DataDir.resolve(INDEX_PATH), FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify(index, "  "))
	file.close()


# was: `_prune_sessions(kept: Array)` stood here, deleting every
# telemetry/<date>/<NNNN>_*.jsonl whose session id was not in the index's
# trimmed list and removing the date folders it emptied -> removed whole. The
# game deletes nothing under user://telemetry/ any more (2026-09-24).


## "180 SPIN" -> "180_spin", for a file name.
static func _slug(title: String) -> String:
	return title.to_lower().replace(" ", "_")
