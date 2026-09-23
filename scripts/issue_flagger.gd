class_name IssueFlagger
extends Node
## The issue flag: the driver's complaint channel, worked from behind the
## wheel. Press the key (ACTION, V) while driving and a flagging session
## STARTS: the car's state is taken down and the drive is bound to the
## telemetry (see below); drive around showing the problem; press it again
## and the session STOPS: the record is frozen with its range and handed to
## the HUD (`stopped`), which asks what is wrong and hands the text back
## (describe); the record then goes into the store (IssueStore) and the
## issue is filed. Later the driver says "analyse the issues" and the store
## and the sessions it names are read together.
##
## THE TELEMETRY BINDING, honest on both maps. The recorder is found at every
## start, never made here: the TelemetryRecorder recording under the HUD's
## parent (the scene's root: main.tscn's MissionManager makes one in its
## _ready, after the HUD's, and the Ring's eifel_ring.tscn has none). Found
## and recording, the issue is bound to THE RECORDER'S OWN session id - its
## _session_id, the number in its session_start line and its file's name,
## read from the object, never a parallel number of this node's own (0 in a
## debug recording, record_to_file, which has no id: honest as well) - and
## to the range inside that session in THE RECORDER'S OWN CLOCK: its
## _session_ticks turned to seconds by its own _seconds, the samples'
## t_session_s, read at the start and at the stop. The HUD stands before the
## MissionManager in main.tscn, so this node's tick runs before the
## recorder's: what is read at a tick is the second of the sample the
## recorder writes that tick. No recorder recording, the binding is the
## odometer and the wall clock (IssueStore.BINDING_ODOMETER): session_id 0
## and both seconds 0.0, the drive identified by odometer_start_m ..
## odometer_stop_m and started_at .. stopped_at. Either way the odometer
## range and the wall clock are written, and the duration is counted here in
## physics ticks (TelemetryRecorder.TICK_SECONDS each: the same drive the
## same number), one tick per tick this node sees - a pause (the garage, the
## typing) stops it as it stops the recorder.
##
## This node only ever READS the car: it presses no input, moves nothing and
## decides nothing. The key is polled here (Input.is_action_just_pressed in
## _physics_process, the mission manager's own idiom), never through the
## car's input path. Made in code by the HUD (scripts/hud.gd, _ready): the
## HUD is the one node in both scenes that holds the car - no autoload (the
## project has one, DataBootstrap, and no pattern for more), no scene edit.
# chosen for the flagging tool: the flagger rides the HUD, so it works on
# the pad and on the Ring alike; the recorder is looked up at every start
# (it is made after the HUD, and the Ring has none); the id is the store's
# counter, shown before the drive and written after it; the description is
# the HUD's to ask for (a LineEdit overlay, the garage's row being blocked
# by the frozen menu test).

## A session started: the id the HUD shows.
signal started(id: String)

## A session stopped: the record, frozen, with no description yet; the HUD
## asks for one and calls describe.
signal stopped(issue: Dictionary)

## The record filed: with its description, and the id it was written under
## ("" when the store refused: the switch off and no path of one's own).
signal filed(issue: Dictionary, written_id: String)

## The key: V, the driver's voice. Free of everything: no action of the
## game's on plain V (project.godot's [input]) and no engine built-in either
## (H, the first candidate, is the engine's own ui_filedialog_show_hidden,
## plain, in Godot 4.7; the free plain letters were J, O, P, U, V, Y, Z),
## and handled raw by nothing. The test walks the map to hold it there.
const ACTION := &"issue_flag"

## The car being watched. Read only.
var car: ArcadeCar

## Where the issues go; the tests hand a file of their own.
var path := IssueStore.PATH

## The id of the session under way, "" while none is.
var active_id := ""

## The record stopped and not yet described; empty otherwise. While it is
## there the key does nothing (the HUD is asking).
var pending: Dictionary = {}

## The last record filed, and the id the store wrote it under ("" when it
## refused).
var last_filed: Dictionary = {}
var last_written_id := ""

## Physics ticks since the session started.
var _ticks := 0

## What the start wrote down: the wall clock, the binding, the car.
var _start: Dictionary = {}

## The recorder the session is bound to, null for none.
var _recorder: TelemetryRecorder


## The tick: the count first, so a session started at tick N and stopped at
## tick M is M - N ticks long, the recorder's own count between the two
## reads; then the key, matched exactly: a modified V (Cmd+V, the engine's
## paste) is another key and flags nothing.
func _physics_process(_delta: float) -> void:
	if active_id != "":
		_ticks += 1
	if not pending.is_empty() or not Input.is_action_just_pressed(ACTION, true):
		return
	if active_id == "":
		start()
	else:
		stop()


## Whether a session is under way.
func recording() -> bool:
	return active_id != ""


## Starts a session: the recorder found, the id taken from the store's
## counter, the car's state and the odometer written down, the wall clock
## read. False, and nothing done, with no car, a session already under way
## or a stopped one still waiting for its description.
func start() -> bool:
	if car == null or active_id != "" or not pending.is_empty():
		return false
	_recorder = _recording_recorder()
	active_id = IssueStore.next_id(path)
	_ticks = 0
	_start = {
		"started_at": _stamp(),
		"binding": IssueStore.BINDING_TELEMETRY if _recorder != null else IssueStore.BINDING_ODOMETER,
		"session_id": _recorder._session_id if _recorder != null else 0,
		"t_start_s": _recorder_seconds(),
		"odometer_start_m": snappedf(car.odometer_m, TelemetryRecorder.VALUE_SNAP),
		"car_state": snapshot(car),
	}
	started.emit(active_id)
	return true


## Stops the session under way: the record frozen with its stop (the wall
## clock, the recorder's second, the odometer, the duration in ticks), held
## as `pending` until describe, and handed out (`stopped`). Empty, and
## nothing done, with no session under way.
func stop() -> Dictionary:
	if active_id == "":
		return {}
	var issue := _start.duplicate(true)
	issue["id"] = active_id
	issue["status"] = IssueStore.ISSUE_DEFAULTS["status"]
	issue["description"] = ""
	issue["stopped_at"] = _stamp()
	issue["duration_s"] = snappedf(_ticks * TelemetryRecorder.TICK_SECONDS, TelemetryRecorder.TIME_SNAP)
	issue["t_stop_s"] = _recorder_seconds()
	issue["odometer_stop_m"] = snappedf(car.odometer_m, TelemetryRecorder.VALUE_SNAP)
	active_id = ""
	_start = {}
	pending = issue
	stopped.emit(issue)
	return issue


## Files the stopped record with `text` as its description ("" is a record
## without one: filed all the same, open, the drive is the evidence): into
## the store, under the id it was shown with unless the counter moved in
## between (IssueStore.add). Returns the id written, "" when the store
## refused or nothing was pending.
func describe(text: String) -> String:
	if pending.is_empty():
		return ""
	var issue := pending
	pending = {}
	issue["description"] = text
	last_filed = issue
	last_written_id = IssueStore.add(issue, path)
	filed.emit(issue, last_written_id)
	return last_written_id


## The car's state as a record holds it: the telemetry sample's own fields
## and snaps (TelemetryRecorder._sample), less the pedals and the slips.
static func snapshot(target_car: ArcadeCar) -> Dictionary:
	var position := target_car.global_position
	return {
		"x": snappedf(position.x, TelemetryRecorder.VALUE_SNAP),
		"y": snappedf(position.y, TelemetryRecorder.VALUE_SNAP),
		"z": snappedf(position.z, TelemetryRecorder.VALUE_SNAP),
		"heading_deg": snappedf(rad_to_deg(target_car.global_rotation.y), TelemetryRecorder.VALUE_SNAP),
		"speed_ms": snappedf(target_car.forward_speed, TelemetryRecorder.VALUE_SNAP),
		"gear": -1 if target_car.reverse_engaged else target_car.gear,
		"odometer_m": snappedf(target_car.odometer_m, TelemetryRecorder.VALUE_SNAP),
	}


## The recorder recording under the HUD's parent (the scene's root), or null.
## The scope is this node's grandparent when it has one below the tree's
## root (the HUD's scene), else its parent.
func _recording_recorder() -> TelemetryRecorder:
	var scope := get_parent()
	if scope == null:
		return null
	var above := scope.get_parent()
	if above != null and above != get_tree().root:
		scope = above
	return _find_recording(scope)


static func _find_recording(node: Node) -> TelemetryRecorder:
	if node is TelemetryRecorder and (node as TelemetryRecorder).recording:
		return node
	for child in node.get_children():
		var found := _find_recording(child)
		if found != null:
			return found
	return null


## The bound recorder's second right now, its own count through its own
## conversion; 0.0 with no recorder bound (or one gone from the tree since
## the start: the range then ends where it began, an honest nothing).
func _recorder_seconds() -> float:
	if _recorder == null or not is_instance_valid(_recorder):
		return 0.0
	return _recorder._seconds(_recorder._session_ticks)


## The wall clock, the telemetry's started_at idiom: local time, ISO-ish,
## for finding a drive again. Nothing is measured against it.
func _stamp() -> String:
	var now := Time.get_datetime_dict_from_system()
	return "%04d-%02d-%02dT%02d:%02d:%02d" % [now.year, now.month, now.day, now.hour, now.minute, now.second]
