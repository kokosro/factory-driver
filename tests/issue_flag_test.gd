extends SceneTree
## Headless issue flag test: the driver's complaint channel. Run via
## tests/run_tests.sh, or:
##
##   godot --headless --path . --import
##   godot --headless --fixed-fps 60 --path . --script res://tests/issue_flag_test.gd
##
## Loads the main scene and works the flag the way a driver would: the key
## (V, issue_flag) starts a session - the HUD's line up with the id -, the
## car is driven, the key stops it - the line down, the overlay up with its
## caption, the tree paused and the car frozen while the text is typed into
## the box, character by character through the input pipeline -, Enter
## files it. Every record goes to a file of the test's own; the suite's own
## default path is proven untouched: the store is off with no window, the
## default path is refused to read and to write, and a session driven with
## no path of its own writes nothing (user://issues.json does not exist
## after, a read-only check).
##
## THE TELEMETRY BINDING against the real recorder, the one main.tscn's
## MissionManager makes: recording to a debug file (record_to_file, no
## session id) the record is bound with session_id 0, honestly; the
## recorder's own session id set by hand (test-only) the record carries THAT
## number, read off the recorder, and its range is the recorder's own clock
## - t_start_s the second of the recorder's count at the tick the session
## started, t_stop_s at the tick it stopped, the difference the flagger's
## own tick count to the hundred-thousandth. The recorder stopped, and a
## bare HUD in a scene with no recorder at all (the Ring's case), the record
## binds to the odometer and the wall clock with the telemetry explicitly
## absent (binding "odometer+wallclock", session_id 0, both seconds 0.0), a
## recorder recording in ANOTHER scene not found. The record itself: the
## id (issue-NNNN from the file's own counter, pinned), the wall clock at
## both ends, the duration in ticks, the odometer at both ends, the car's
## state at the start with its seven fields off the car. The store: three
## records round-tripped to the bit, the counter past them, and validate on
## broken fixtures naming the record and the field with the default used,
## a record without an id left out, a counter behind the ids brought up,
## an id already taken re-issued; an id twice in the file loads once (the
## first record keeps it), an id of too many digits, a counter past
## COUNTER_MAX, a session id past an int32 and a gear outside -1..20 each
## refused with their text, a full file writing nothing. The key: V in the
## map and on nothing else, the engine's built-ins walked too. The overlay
## and the line inside the game's own 1280 x 720. Esc in the box files what
## is typed - a text typed first, read back as that text -, and the garage
## - polling its Esc through the pause - opens over it on the same key, as
## the HUD says it does. THE STOP GUARD: a recorder stopped, or restarted
## under a new session id, between the flagger's two keys lends no clock -
## the record keeps the session it started in and its range ends where it
## began (t_stop_s == t_start_s), the duration still counted. The debug
## recording's own .jsonl read back as an independent anchor: its last
## sample's t_session_s inside the record's range.
## Exits 0 on success, 1 on any failed check.

const MAIN_SCENE := "res://scenes/main.tscn"
const HUD_SCENE := "res://scenes/hud.tscn"

## Physics frames to let the car settle on the ground at the start.
const SETTLE_FRAMES := 20

## Frames the car is driven inside a session [physics ticks].
const DRIVE_FRAMES := 120

## Frames the overlay is held up with the throttle key down, to see the car
## frozen [physics ticks].
const FROZEN_FRAMES := 30

## Where the records go: one directory per process, removed at the end
## (tests/README.md).
const TMP_DIR_PREFIX := "/tmp/fd-3IF-issue-"

## The game's own screen [px] (project.godot): every surface is measured on it.
const SCREEN := Rect2(0, 0, 1280, 720)

var _failures := 0
var _main: Node
var _car: ArcadeCar
var _hud: HUD
var _flagger: IssueFlagger
var _recorder: TelemetryRecorder
var _garage: Garage
var _tmp_dir := ""
var _issues_file := ""
var _ring_file := ""

## What the test read off the recorder and the car when the flagger's
## signals fired (in the flagger's own tick, before the recorder's).
var _ticks_at_start := -1
var _ticks_at_stop := -1
var _car_at_start: Dictionary = {}
var _started_ids: Array[String] = []
var _stopped_records: Array[Dictionary] = []
var _filed: Array[Array] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_tmp_dir = "%s%d" % [TMP_DIR_PREFIX, OS.get_process_id()]
	_issues_file = _tmp_dir + "/issues.json"
	_ring_file = _tmp_dir + "/ring_issues.json"
	DirAccess.make_dir_recursive_absolute(_tmp_dir)
	var packed: PackedScene = load(MAIN_SCENE)
	if not _check(packed != null, "main scene loads"):
		_finish()
		return
	_main = packed.instantiate()
	root.add_child(_main)
	root.size = Vector2i(SCREEN.size)
	await _step(SETTLE_FRAMES)

	_car = _main.get_node_or_null("Car") as ArcadeCar
	_hud = _main.get_node_or_null("HUD") as HUD
	_garage = _main.get_node_or_null("Garage") as Garage
	var missions := _main.get_node_or_null("MissionManager") as MissionManager
	_recorder = missions.telemetry if missions != null else null
	if not _check(_car != null and _hud != null and _garage != null and _recorder != null, "Car, HUD, Garage and the MissionManager's TelemetryRecorder exist"):
		_finish()
		return
	_flagger = _hud.flagger
	if not _check(_flagger != null and _flagger.get_parent() == _hud and _flagger.name == "IssueFlagger" and _flagger.car == _car, "the HUD made the flagger in code: a child named IssueFlagger, the car handed over"):
		_finish()
		return
	_flagger.started.connect(_on_started)
	_flagger.stopped.connect(_on_stopped)
	_flagger.filed.connect(func(issue: Dictionary, written_id: String) -> void: _filed.append([issue, written_id]))

	_check_key()
	await _check_gate_and_hud()
	await _check_bindings()
	_check_store()
	await _check_stop_guard()
	await _check_bare_hud()

	_remove_tmp()
	_finish()


# =============================================================================
#  The key
# =============================================================================

## V, plain, and nothing else on plain V: every action's key events walked,
## the engine's built-in ui_ actions among them (H, the first candidate, is
## the engine's own ui_filedialog_show_hidden, plain, which is how this
## check came to walk the built-ins). A modified key is another key: the
## one modified V there is is the engine's ui_paste, Ctrl+V (Cmd+V), which
## pastes into the box and, the flagger matching its key exactly, flags
## nothing.
func _check_key() -> void:
	var events := InputMap.action_get_events(IssueFlagger.ACTION) if InputMap.has_action(IssueFlagger.ACTION) else []
	var on_v := events.size() == 1 and events[0] is InputEventKey and (events[0] as InputEventKey).physical_keycode == KEY_V and (events[0] as InputEventKey).get_modifiers_mask() == 0
	var plain := PackedStringArray()
	var modified := PackedStringArray()
	for action in InputMap.get_actions():
		if action == IssueFlagger.ACTION:
			continue
		for event in InputMap.action_get_events(action):
			if not event is InputEventKey:
				continue
			var key := event as InputEventKey
			if key.physical_keycode != KEY_V and key.keycode != KEY_V:
				continue
			if key.get_modifiers_mask() == 0 and not key.command_or_control_autoremap:
				plain.append(String(action))
			else:
				modified.append(String(action))
	_check(on_v and plain.is_empty() and modified == PackedStringArray(["ui_paste"]), "the flag's key is V (issue_flag, physical 86), no other action - the engine's built-ins included - is on plain V (%s), and the one modified V is the engine's paste (%s)" % [", ".join(plain) if not plain.is_empty() else "none", ", ".join(modified)])


# =============================================================================
#  The gate, the line and the overlay
# =============================================================================

## The store off headless, the default path refused, a session with no
## path of its own writing nothing; the HUD's line and overlay through a
## whole session on the key, the text typed and filed on Enter.
func _check_gate_and_hud() -> void:
	var default_on_disk := DataDir.resolve(IssueStore.PATH)
	var existed_before := FileAccess.file_exists(default_on_disk)
	_check(not IssueStore.enabled() and not TelemetryRecorder.should_record(), "suite: the store is off headless (the telemetry's own switch)")
	_check(not IssueStore.allowed(IssueStore.PATH) and IssueStore.allowed(_issues_file), "the default path is refused while the store is off; a path of one's own is allowed")
	_check(IssueStore.add({"description": "never"}, IssueStore.PATH) == "" and IssueStore.next_id(IssueStore.PATH) == "issue-0001" and IssueStore.load_issues(IssueStore.PATH).issues.is_empty() and FileAccess.file_exists(default_on_disk) == existed_before, "the store refuses to write the default path while off, and reads nothing from it (%s)" % default_on_disk)

	# A whole session on the key, the flagger on its default path.
	_check(_flagger.path == IssueStore.PATH and not _flagger.recording() and _flagger.pending.is_empty() and not _hud.issue_line_visible() and not _hud.issue_overlay_visible(), "before: the flagger on the default path, no session, no line, no overlay")
	await _tap(IssueFlagger.ACTION)
	_check(_flagger.recording() and _flagger.active_id == "issue-0001" and _hud.issue_line_visible() and _hud.issue_line_text() == HUD.ISSUE_LINE_TEXT % "issue-0001" and _hud.issue_line_text().contains("issue-0001"), "the key starts a session: issue-0001 (the counter of no file), the HUD's line up with the id")
	_check(_inside(_hud.get_node("IssueLabel")), "the line lies inside the screen")
	await _step(DRIVE_FRAMES)
	await _tap(IssueFlagger.ACTION)
	var description: LineEdit = _hud.get_node("IssueOverlay/Description")
	_check(not _flagger.recording() and not _flagger.pending.is_empty() and not _hud.issue_line_visible() and _hud.issue_overlay_visible() and paused and description.has_focus() and description.text == "", "the key stops it: the line down, the overlay up, the box empty and focused, the tree paused")
	_check(_hud.issue_caption_text().contains("issue-0001") and _hud.issue_caption_text().contains("bound to the odometer"), "the caption names the id and the binding (no recorder recording: the odometer and the clock)")
	_check((_hud.get_node("IssueOverlay") as Node).process_mode == Node.PROCESS_MODE_ALWAYS and _inside(_hud.get_node("IssueOverlay")), "the overlay processes through the pause (the garage's mechanism) and lies inside the screen")

	# Frozen while typing: the throttle key down, nothing moves.
	var before := _car_snapshot()
	Input.action_press(&"accelerate")
	await _step(FROZEN_FRAMES)
	Input.action_release(&"accelerate")
	await _step(2)
	_check(_car_snapshot() == before and paused, "the car is frozen while the box is up: %d ticks with the throttle down move nothing" % FROZEN_FRAMES)
	# The key does nothing while the box is up (the flagger is paused with the tree).
	await _tap(IssueFlagger.ACTION)
	_check(not _flagger.recording() and _hud.issue_overlay_visible(), "the flag's key does nothing while the box is up")

	await _type("the car swerves sideways")
	_check(description.text == "the car swerves sideways", "the text typed through the input pipeline lands in the box (a plain v types a v: no paste)")
	await _key(KEY_ENTER)
	_check(not _hud.issue_overlay_visible() and not paused and _flagger.pending.is_empty() and not description.has_focus(), "Enter takes the overlay down and the tree runs on")
	_check(_flagger.last_filed.get("description") == "the car swerves sideways" and _flagger.last_filed.get("id") == "issue-0001" and _flagger.last_written_id == "" and _filed.size() == 1 and _filed[0][1] == "", "the record is filed with the text; the store refused it (off, the default path): written id \"\"")
	_check(FileAccess.file_exists(default_on_disk) == existed_before and not _garage.is_open, "nothing was written to the default path (%s: %s), and the garage stayed shut on Enter" % [default_on_disk, "was there before" if existed_before else "not there"])


# =============================================================================
#  The bindings
# =============================================================================

## Three sessions on a file of the test's own: a debug recording (session
## id 0), the recorder's own id set by hand, and the recorder stopped.
func _check_bindings() -> void:
	_flagger.path = _issues_file
	var debug_file := _tmp_dir + "/debug.jsonl"
	_recorder.record_to_file(debug_file)
	await _step(5)
	_check(_recorder.recording and _recorder._session_id == 0, "the real recorder records to a debug file of the test's own: no session id (0)")

	# Session 1: the debug recording, Esc in the box.
	await _session()
	var first: Dictionary = _stopped_records[1]
	_check(first.get("binding") == IssueStore.BINDING_TELEMETRY and first.get("session_id") == 0 and typeof(first.get("session_id")) == TYPE_INT, "the record binds to the recorder's own session id, honestly 0 in a debug recording")
	_check_range(first, "the debug recording")
	# An anchor outside the recorder's fields: the recorder's own file, the
	# last sample it wrote (the tree is paused now, the recorder with it),
	# lies inside the range - the flagger's two reads straddle the tail.
	var last_sample_s := _last_sample_second(debug_file)
	_check(last_sample_s >= 0.0 and first.get("t_start_s") <= last_sample_s and last_sample_s <= first.get("t_stop_s"), "the debug recording's own .jsonl anchors the range: its last sample's t_session_s (%.5f s) lies inside %.5f - %.5f s" % [last_sample_s, first.get("t_start_s"), first.get("t_stop_s")])
	_check(_hud.issue_caption_text().contains("bound to telemetry session 0"), "the caption names the session and the range")
	# was -> Esc was asserted on an EMPTY box, which a discarded text would
	# have passed too: a text is typed first and read back as that text.
	await _type("snaps over the crest")
	var before_esc := (_hud.get_node("IssueOverlay/Description") as LineEdit).text
	await _key(KEY_ESCAPE)
	await _step(3)
	_check(before_esc == "snaps over the crest" and not _hud.issue_overlay_visible() and _flagger.last_filed.get("description") == "snaps over the crest" and _flagger.last_written_id == "issue-0001" and FileAccess.file_exists(_issues_file), "Esc files what is typed (\"%s\", typed into the box first) under issue-0001, into the test's file" % before_esc)
	_check(_garage.is_open and paused, "and the garage opened over it on the same Esc (its poll runs through the pause): the garage holds the pause")
	await _tap(Garage.ACTION_OPEN)
	_check(not _garage.is_open and not paused and IssueStore.load_issues(_issues_file).issues[0].description == "snaps over the crest", "Tab closes the garage, the tree runs on; the text Esc filed is in the file")

	# Session 2: the recorder's own id, set by hand, and Enter with a text.
	_recorder._session_id = 42
	await _session()
	var second: Dictionary = _stopped_records[2]
	_check(second.get("session_id") == 42 and second.get("binding") == IssueStore.BINDING_TELEMETRY and second.get("id") == "issue-0002", "the record carries THE RECORDER'S session id (42, set on the recorder) - no number of the flagger's own - as issue-0002")
	_check_range(second, "the recorder's session")
	await _type("wall at the crest")
	await _key(KEY_ENTER)
	_check(_flagger.last_written_id == "issue-0002" and _flagger.last_filed.get("description") == "wall at the crest" and not paused, "filed with its text under issue-0002")

	# Session 3: the recorder stopped, nothing recording.
	_recorder.stop()
	_recorder._session_id = 0
	await _session()
	var third: Dictionary = _stopped_records[3]
	_check(third.get("binding") == IssueStore.BINDING_ODOMETER and third.get("session_id") == 0 and third.get("t_start_s") == 0.0 and third.get("t_stop_s") == 0.0 and third.get("id") == "issue-0003", "the recorder stopped: the record binds to the odometer and the wall clock, the telemetry explicitly absent (session 0, 0.0 - 0.0 s), as issue-0003")
	# The recorder's count stands still now: the flagger's own count is held
	# to the session before, the same keys the same ticks apart.
	_check(third.get("odometer_stop_m") > third.get("odometer_start_m") and third.get("odometer_start_m") == third.get("car_state", {}).get("odometer_m") and third.get("duration_s") == second.get("duration_s") and third.get("duration_s") > 0.0, "its odometer range is the drive's (%.3f - %.3f m) and its duration the flagger's own tick count, the session before's to the tick (%.5f s)" % [third.get("odometer_start_m"), third.get("odometer_stop_m"), third.get("duration_s")])
	_hud.commit_issue_description("no recorder here")
	_check(_flagger.last_written_id == "issue-0003" and not paused and not _hud.issue_overlay_visible(), "filed through the HUD's own call under issue-0003")
	if FileAccess.file_exists(debug_file):
		DirAccess.remove_absolute(debug_file)


## One session on the key: the car driven DRIVE_FRAMES with the throttle
## down; the overlay is left up for the caller to close.
func _session() -> void:
	await _tap(IssueFlagger.ACTION)
	Input.action_press(&"accelerate")
	await _step(DRIVE_FRAMES)
	Input.action_release(&"accelerate")
	await _step(2)
	await _tap(IssueFlagger.ACTION)


## The range of a telemetry-bound record against what the test read off the
## recorder's own count at the two signals: the same clock, to the
## hundred-thousandth; the car's state the car's at the start.
func _check_range(record: Dictionary, what: String) -> void:
	var t_start: float = record.get("t_start_s", -1.0)
	var t_stop: float = record.get("t_stop_s", -1.0)
	var expected_start: float = _recorder._seconds(_ticks_at_start)
	var expected_stop: float = _recorder._seconds(_ticks_at_stop)
	_check(t_start == expected_start and t_stop == expected_stop and t_stop > t_start, "%s: the range is the recorder's own clock, %.5f - %.5f s (its count at the start and the stop)" % [what, t_start, t_stop])
	_check(snappedf(t_stop - t_start, TelemetryRecorder.TIME_SNAP) == record.get("duration_s") and record.get("duration_s") == snappedf(_ticks_between() * TelemetryRecorder.TICK_SECONDS, TelemetryRecorder.TIME_SNAP), "%s: the range's length is the flagger's own tick count, %.5f s" % [what, record.get("duration_s")])
	_check_record_shape(record, what)


## A record's shape: every field there, the car's state the car's at the
## start (read by the test in the same tick), the wall clock stamped.
func _check_record_shape(record: Dictionary, what: String) -> void:
	var fields := PackedStringArray(["id"])
	for field: String in IssueStore.ISSUE_DEFAULTS:
		fields.append(field)
	var all_there := true
	for field in fields:
		all_there = all_there and record.has(field)
	var state: Dictionary = record.get("car_state", {})
	var state_fields := true
	for field: String in IssueStore.CAR_STATE_DEFAULTS:
		state_fields = state_fields and state.has(field)
	_check(all_there and record.size() == fields.size() and state_fields and state.size() == IssueStore.CAR_STATE_DEFAULTS.size(), "%s: the record has every field of the store's shape (%d) and the car's state its seven" % [what, fields.size()])
	_check(state == _car_at_start and typeof(state.get("gear")) == TYPE_INT, "%s: the car's state is the car's at the start (x %.3f, z %.3f, heading %.3f, %.3f m/s, gear %d, %.3f m)" % [what, state.get("x", NAN), state.get("z", NAN), state.get("heading_deg", NAN), state.get("speed_ms", NAN), state.get("gear", 0), state.get("odometer_m", NAN)])
	var stamp := RegEx.create_from_string("^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}$")
	_check(stamp.search(record.get("started_at", "")) != null and stamp.search(record.get("stopped_at", "")) != null and record.get("status") == "open" and record.get("description") == "", "%s: the wall clock is stamped at both ends, the record open and undescribed" % what)


func _ticks_between() -> int:
	return _ticks_at_stop - _ticks_at_start


## The t_session_s of the last sample line in a recorder's .jsonl (the
## session_start line has none); -1.0 for no sample.
func _last_sample_second(path: String) -> float:
	var last := -1.0
	for line in FileAccess.get_file_as_string(path).split("\n", false):
		var parsed: Variant = JSON.parse_string(line)
		if parsed is Dictionary and (parsed as Dictionary).has("t_session_s"):
			last = float((parsed as Dictionary)["t_session_s"])
	return last


# =============================================================================
#  The store
# =============================================================================

## The three records back to the bit, the counter past them; the broken
## fixtures; the re-issued ids.
func _check_store() -> void:
	var loaded := IssueStore.load_issues(_issues_file)
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(_issues_file))
	_check(loaded.issues.size() == 3 and loaded.next_issue_id == 4 and (loaded.problems as Array).is_empty() and raw is Dictionary and raw.get("version") == IssueStore.VERSION and IssueStore.VERSION == 1 and raw.get("next_issue_id") == 4 and IssueStore.next_id(_issues_file) == "issue-0004", "the file holds the three records, version 1, the counter at 4")
	var to_the_bit := true
	for position in 3:
		var filed: Dictionary = _filed[position + 1][0]
		to_the_bit = to_the_bit and loaded.issues[position] == filed and _filed[position + 1][1] == filed.id
	_check(to_the_bit and loaded.issues[1].description == "wall at the crest" and loaded.issues[1].session_id == 42 and typeof(loaded.issues[1].session_id) == TYPE_INT and typeof(loaded.issues[1].car_state.gear) == TYPE_INT, "the three records read back to the bit, every field, the whole numbers whole")
	_check(IssueStore.format_id(7) == "issue-0007" and IssueStore.format_id(12345) == "issue-12345" and IssueStore.id_number("issue-0007") == 7 and IssueStore.id_number("issue-12345") == 12345 and IssueStore.id_number("issue-7") == 0 and IssueStore.id_number("issue-") == 0 and IssueStore.id_number("bug-0007") == 0 and IssueStore.id_number(7) == 0 and IssueStore.id_number("issue--001") == 0, "the id format is pinned: issue- and the counter, at least four digits")

	# Broken fixtures.
	var broken := _tmp_dir + "/broken.json"
	_write_raw(broken, {
		"version": 1,
		"next_issue_id": 2,
		"issues": [
			{"id": "issue-0009", "status": "weird", "description": 5, "started_at": 1, "binding": "x", "session_id": -1, "t_start_s": "a", "duration_s": -0.5, "odometer_start_m": -5, "car_state": "no"},
			{"id": "issue-0010", "session_id": 1.5, "t_stop_s": 3, "car_state": {"gear": 1.5, "x": "a", "z": 2}},
			{"status": "open"},
			{"id": "issue-12"},
			"not a record",
		],
	})
	var checked := IssueStore.load_issues(broken)
	var problems: Array = checked.problems
	var said := "\n".join(PackedStringArray(problems))
	_check(checked.issues.size() == 2 and checked.issues[0].id == "issue-0009" and checked.issues[1].id == "issue-0010", "two records load, the three without a usable id left out")
	var defaults: Dictionary = checked.issues[0]
	_check(defaults.status == "open" and defaults.description == "" and defaults.started_at == "" and defaults.binding == IssueStore.BINDING_ODOMETER and defaults.session_id == 0 and defaults.t_start_s == 0.0 and defaults.duration_s == 0.0 and defaults.odometer_start_m == 0.0 and defaults.car_state == IssueStore.CAR_STATE_DEFAULTS, "every field that is none of its own reads as its default")
	# JSON gives every number back as a float: the texts say 5.0 for a 5.
	_check(said.contains("issue issue-0009's status is no status (weird), they are open, closed, open is used") and said.contains("issue-0009's description is not a text (5.0),  is used") and said.contains("issue-0009's started_at is not a text (1.0),  is used") and said.contains("issue-0009's binding is no binding (x), they are telemetry, odometer+wallclock, odometer+wallclock is used") and said.contains("issue-0009's session_id is under 0 (-1.0), 0 is used") and said.contains("issue-0009's t_start_s is not a number (a), 0.0 is used") and said.contains("issue-0009's duration_s is under 0 (-0.5), 0.0 is used") and said.contains("issue-0009's odometer_start_m is under 0 (-5.0), 0.0 is used") and said.contains("issue-0009's car_state is not the car's state (no), { \"x\": 0.0,"), "and each is reported by record and field with the default used")
	_check(said.contains("issue-0010's session_id is no whole number (1.5), 0 is used") and said.contains("issue-0010's car_state gear is no whole number (1.5), 0 is used") and said.contains("issue-0010's car_state x is not a number (a), 0.0 is used") and checked.issues[1].t_stop_s == 3.0 and checked.issues[1].car_state.z == 2.0 and checked.issues[1].car_state.gear == 0, "the car's state is checked field by field, the good ones kept")
	_check(said.contains("issue 2 has no id (<null>), it is left out") and said.contains("issue 3 has no id (issue-12), it is left out") and said.contains("issue 4 is not a record (not a record), it is left out"), "the records left out are named by position and reason")
	_check(said.contains("next_issue_id 2.0 is no counter over the 2 issue(s) there are, 11 is used") and checked.next_issue_id == 11 and IssueStore.next_id(broken) == "issue-0011", "a counter behind the ids is brought up past them")
	_check(problems.size() == 16, "sixteen problems, one per fault (%d)" % problems.size())
	_write_raw(broken, {"version": 1, "issues": "none"})
	_check(IssueStore.load_issues(broken).problems == ["%s: issues is not a list (none), none are read" % broken] and IssueStore.load_issues(broken).issues.is_empty(), "issues that is no list is reported and none are read")
	var array_file := _tmp_dir + "/array.json"
	var file := FileAccess.open(array_file, FileAccess.WRITE)
	file.store_string("[1, 2]")
	file.close()
	_check(IssueStore.load_issues(array_file).issues.is_empty() and IssueStore.load_issues(array_file).problems.is_empty() and IssueStore.next_id(array_file) == "issue-0001" and IssueStore.load_issues(_tmp_dir + "/none.json").next_issue_id == 1, "a file that is no dictionary, and no file, are no issues, counter 1")

	# Re-issued ids and a checked write.
	var taken := IssueStore.add({"id": "issue-0001", "description": "again", "session_id": "x"}, _issues_file)
	var none := IssueStore.add({"description": "no id"}, _issues_file)
	var after := IssueStore.load_issues(_issues_file)
	_check(taken == "issue-0004" and none == "issue-0005" and after.issues.size() == 5 and after.next_issue_id == 6 and after.issues[3].description == "again" and after.issues[3].session_id == 0 and after.issues[4].description == "no id" and (after.problems as Array).is_empty(), "an id already taken and no id both get the counter's; a field that is none of its own is written as its default; the first three untouched")
	var far := IssueStore.add({"id": "issue-0100"}, _issues_file)
	_check(far == "issue-0100" and IssueStore.load_issues(_issues_file).next_issue_id == 101 and IssueStore.next_id(_issues_file) == "issue-0101", "an id of one's own that is free is kept, the counter moves past it")

	# The bounds: the id's digits, the counter's ceiling, the session id's
	# and the gear's.
	_check(IssueStore.id_number("issue-999999999999") == 999999999999 and IssueStore.id_number("issue-1000000000000") == 0 and IssueStore.id_number("issue-9223372036854775807") == 0 and IssueStore.ID_MAX_DIGITS == 12, "an id of up to twelve digits counts, thirteen or more (a saturating to_int among them) is no id")
	var bounds := _tmp_dir + "/bounds.json"
	_write_raw(bounds, {
		"version": 1,
		"next_issue_id": 1e30,
		"issues": [
			{"id": "issue-0001", "session_id": 3000000000, "car_state": {"gear": 21}},
			{"id": "issue-0002", "session_id": 2147483647, "car_state": {"gear": -2}},
			{"id": "issue-9223372036854775807"},
		],
	})
	var bounded := IssueStore.load_issues(bounds)
	var bounded_said := "\n".join(PackedStringArray(bounded.problems))
	_check(bounded.issues.size() == 2 and bounded.issues[0].session_id == 0 and bounded.issues[0].car_state.gear == 0 and bounded.issues[1].session_id == 2147483647 and bounded.issues[1].car_state.gear == 0 and bounded.next_issue_id == 3 and bounded.problems.size() == 5, "a session id past an int32 and a gear outside -1..20 read as their defaults (an int32 itself kept), the saturating id left out, a counter of 1e30 brought to 3: five texts (%d)" % bounded.problems.size())
	_check(bounded_said.contains("issue-0001's session_id is over 2147483647 (3000000000.0), 0 is used") and bounded_said.contains("issue-0001's car_state gear is over 20 (21.0), 0 is used") and bounded_said.contains("issue-0002's car_state gear is under -1 (-2.0), 0 is used") and bounded_said.contains("issue 2 has no id (issue-9223372036854775807), it is left out") and bounded_said.contains("next_issue_id ") and bounded_said.contains(" is no counter over the 2 issue(s) there are, 3 is used"), "each bound is reported by record and field with the default used, the counter's text naming 3")
	# The full file: the last id COUNTER_MAX may be written, then nothing.
	var full := _tmp_dir + "/full.json"
	var last_id := IssueStore.add({"id": "issue-99999999", "description": "the last"}, full)
	var full_loaded := IssueStore.load_issues(full)
	var full_bytes := FileAccess.get_file_as_string(full)
	var refused := IssueStore.add({"description": "one more"}, full)
	var refused_taken := IssueStore.add({"id": "issue-99999999", "description": "taken"}, full)
	_check(last_id == "issue-99999999" and IssueStore.COUNTER_MAX == 99999999 and full_loaded.issues.size() == 1 and full_loaded.next_issue_id == 100000000 and full_loaded.problems.size() == 1 and (full_loaded.problems[0] as String).contains("next_issue_id 100000000") and refused == "" and refused_taken == "" and FileAccess.get_file_as_string(full) == full_bytes, "a record under the counter's ceiling issue-99999999 is written; the file is full then: the counter past the ceiling reported, add from the counter - no id, or an id taken - writes nothing and returns \"\", the file's bytes untouched")
	var free_own := IssueStore.add({"id": "issue-0001", "description": "own id"}, full)
	_check(free_own == "issue-0001" and IssueStore.load_issues(full).issues.size() == 2 and IssueStore.load_issues(full).next_issue_id == 100000000, "a free id of one's own under the ceiling is still written into the full file, the counter left past the ceiling")

	# A duplicate id: the first record keeps it, the second is left out.
	var twice := _tmp_dir + "/twice.json"
	_write_raw(twice, {
		"version": 1,
		"next_issue_id": 3,
		"issues": [
			{"id": "issue-0001", "description": "first"},
			{"id": "issue-0001", "description": "second"},
			{"id": "issue-0002", "description": "other"},
		],
	})
	var twice_loaded := IssueStore.load_issues(twice)
	_check(twice_loaded.issues.size() == 2 and twice_loaded.issues[0].description == "first" and twice_loaded.issues[1].id == "issue-0002" and twice_loaded.next_issue_id == 3 and twice_loaded.problems == ["%s: issue 1's id issue-0001 is already in the file, the first record keeps it, this one is left out" % twice], "an id twice in the file: the first record keeps it, the second is left out with one text naming it by position")
	var under_dup := IssueStore.add({"id": "issue-0001", "description": "third"}, twice)
	var twice_after := IssueStore.load_issues(twice)
	_check(under_dup == "issue-0003" and twice_after.issues.size() == 3 and twice_after.issues[2].description == "third" and twice_after.issues[2].id == "issue-0003" and twice_after.next_issue_id == 4 and twice_after.problems.size() == 1, "add under the duplicated id writes under the counter's issue-0003, not the id twice taken; the file's own duplicate is written back as read and still left out")
	for name in ["broken.json", "array.json", "bounds.json", "full.json", "twice.json"]:
		DirAccess.remove_absolute(_tmp_dir.path_join(name))


# =============================================================================
#  The stop guard
# =============================================================================

## The recorder stopped between the flagger's two keys, and the recorder
## restarted under a new session id between them: the record keeps the
## session it started in and its range ends where it began, t_stop_s ==
## t_start_s - no other session's clock borrowed, no range turned round -,
## the binding still the telemetry's and the duration the tick count.
func _check_stop_guard() -> void:
	var guard_file := _tmp_dir + "/guard.json"
	_flagger.path = guard_file
	_recorder.record_to_file(_tmp_dir + "/guard.jsonl")
	await _step(5)
	# The recorder stopped mid-flag.
	var started := _flagger.start()
	var t_start: float = _flagger._start.get("t_start_s", -1.0)
	Input.action_press(&"accelerate")
	await _step(DRIVE_FRAMES)
	Input.action_release(&"accelerate")
	await _step(2)
	_recorder.stop()
	await _step(2)
	var stopped := _flagger.stop()
	_check(started and _recorder.recording == false and t_start == _recorder._seconds(5) and t_start > 0.0 and stopped.get("binding") == IssueStore.BINDING_TELEMETRY and stopped.get("session_id") == 0 and stopped.get("t_start_s") == t_start and stopped.get("t_stop_s") == t_start and stopped.get("duration_s") == snappedf((DRIVE_FRAMES + 4) * TelemetryRecorder.TICK_SECONDS, TelemetryRecorder.TIME_SNAP), "the recorder stopped mid-flag: the record keeps the telemetry binding and session 0, its range ends where it began (%.5f - %.5f s, was a fresh read of whatever the recorder held), the duration still the %d ticks" % [stopped.get("t_start_s"), stopped.get("t_stop_s"), DRIVE_FRAMES + 4])
	_hud.commit_issue_description("recorder stopped mid-flag")
	_check(_flagger.last_written_id == "issue-0001" and not paused, "filed under issue-0001 of the guard's file")

	# The recorder restarted mid-flag under a new session id: its count from
	# 0 again, another session's clock.
	_recorder.record_to_file(_tmp_dir + "/guard.jsonl")
	_recorder._session_id = 42
	await _step(5)
	started = _flagger.start()
	t_start = _flagger._start.get("t_start_s", -1.0)
	Input.action_press(&"accelerate")
	await _step(DRIVE_FRAMES)
	Input.action_release(&"accelerate")
	await _step(2)
	_recorder.record_to_file(_tmp_dir + "/guard2.jsonl")
	_recorder._session_id = 43
	await _step(2)
	var fresh_clock := _recorder._seconds(_recorder._session_ticks)
	stopped = _flagger.stop()
	_check(started and _recorder.recording and _recorder._session_id == 43 and fresh_clock < t_start and stopped.get("session_id") == 42 and stopped.get("binding") == IssueStore.BINDING_TELEMETRY and stopped.get("t_start_s") == t_start and stopped.get("t_stop_s") == t_start and stopped.get("duration_s") == snappedf((DRIVE_FRAMES + 4) * TelemetryRecorder.TICK_SECONDS, TelemetryRecorder.TIME_SNAP), "the recorder restarted mid-flag as session 43 (its clock at %.5f s, below the start's %.5f s): the record keeps session 42 and its range ends where it began (was session 42 with session 43's endpoint), the duration still the %d ticks" % [fresh_clock, t_start, DRIVE_FRAMES + 4])
	_hud.commit_issue_description("recorder restarted mid-flag")
	var guard_loaded := IssueStore.load_issues(guard_file)
	_check(_flagger.last_written_id == "issue-0002" and not paused and guard_loaded.issues.size() == 2 and guard_loaded.issues[1].session_id == 42 and guard_loaded.issues[1].t_stop_s == guard_loaded.issues[1].t_start_s and (guard_loaded.problems as Array).is_empty(), "filed under issue-0002 and read back: session 42, the degenerate range, no problem text")
	_recorder.stop()
	_recorder._session_id = 0
	_flagger.path = IssueStore.PATH
	for name in ["guard.json", "guard.jsonl", "guard2.jsonl"]:
		if FileAccess.file_exists(_tmp_dir.path_join(name)):
			DirAccess.remove_absolute(_tmp_dir.path_join(name))


# =============================================================================
#  A bare HUD: the Ring's case
# =============================================================================

## A second HUD in a scene of its own with no recorder in it (eifel_ring.tscn
## has none; the HUD is the node the Ring and the pad share), the main
## scene's recorder recording all the while: not found, the record binds to
## the odometer and the wall clock. No garage beside it: nothing to wire.
func _check_bare_hud() -> void:
	var bare := Node3D.new()
	bare.name = "Bare"
	root.add_child(bare)
	var hud: HUD = (load(HUD_SCENE) as PackedScene).instantiate()
	hud.car = _car
	bare.add_child(hud)
	await _step(2)
	var flagger: IssueFlagger = hud.flagger
	flagger.path = _ring_file
	_recorder.record_to_file(_tmp_dir + "/other_scene.jsonl")
	await _step(2)
	_check(flagger != null and flagger.car == _car and _recorder.recording, "a bare HUD in a scene of its own made its flagger; the main scene's recorder is recording")
	var started := flagger.start()
	Input.action_press(&"accelerate")
	await _step(DRIVE_FRAMES)
	Input.action_release(&"accelerate")
	await _step(2)
	var record := flagger.stop()
	_check(started and record.get("binding") == IssueStore.BINDING_ODOMETER and record.get("session_id") == 0 and record.get("t_start_s") == 0.0 and record.get("t_stop_s") == 0.0 and record.get("id") == "issue-0001", "no recorder in ITS scene: the record binds to the odometer and the wall clock, the other scene's recorder not found, issue-0001 of its own file")
	_check(record.get("odometer_stop_m") > record.get("odometer_start_m") and record.get("duration_s") == snappedf((DRIVE_FRAMES + 2) * TelemetryRecorder.TICK_SECONDS, TelemetryRecorder.TIME_SNAP) and hud.issue_overlay_visible() and paused, "its odometer range is the drive's, its duration the %d ticks, the overlay up and the tree paused" % (DRIVE_FRAMES + 2))
	hud.commit_issue_description("on the ring")
	var back := IssueStore.load_issues(_ring_file)
	_check(flagger.last_written_id == "issue-0001" and not paused and back.issues.size() == 1 and back.issues[0].description == "on the ring" and back.issues[0].binding == IssueStore.BINDING_ODOMETER and (back.problems as Array).is_empty(), "filed and read back from the Ring-style file")
	_recorder.stop()
	root.remove_child(bare)
	bare.queue_free()
	for name in ["other_scene.jsonl", "ring_issues.json"]:
		if FileAccess.file_exists(_tmp_dir.path_join(name)):
			DirAccess.remove_absolute(_tmp_dir.path_join(name))


# =============================================================================
#  Helpers
# =============================================================================

func _on_started(id: String) -> void:
	_started_ids.append(id)
	_ticks_at_start = _recorder._session_ticks
	var position := _car.global_position
	_car_at_start = {
		"x": snappedf(position.x, TelemetryRecorder.VALUE_SNAP),
		"y": snappedf(position.y, TelemetryRecorder.VALUE_SNAP),
		"z": snappedf(position.z, TelemetryRecorder.VALUE_SNAP),
		"heading_deg": snappedf(rad_to_deg(_car.global_rotation.y), TelemetryRecorder.VALUE_SNAP),
		"speed_ms": snappedf(_car.forward_speed, TelemetryRecorder.VALUE_SNAP),
		"gear": -1 if _car.reverse_engaged else _car.gear,
		"odometer_m": snappedf(_car.odometer_m, TelemetryRecorder.VALUE_SNAP),
	}


func _on_stopped(issue: Dictionary) -> void:
	_stopped_records.append(issue.duplicate(true))
	_ticks_at_stop = _recorder._session_ticks


## What of the car a frozen tree must leave alone.
func _car_snapshot() -> Dictionary:
	return {"position": _car.global_position, "velocity": _car.velocity, "odometer_m": _car.odometer_m, "rpm": _car.engine_rpm, "gear": _car.gear}


## Whether `node`'s rect lies inside the screen.
func _inside(node: Control) -> bool:
	var rect := node.get_global_rect()
	return rect.position.x >= SCREEN.position.x and rect.position.y >= SCREEN.position.y and rect.end.x <= SCREEN.end.x and rect.end.y <= SCREEN.end.y


## Types `text` into whatever has the focus, one key event per character
## through the input pipeline (Input.parse_input_event: the same road a key
## takes), a press and a release each.
func _type(text: String) -> void:
	for character in text:
		var press := InputEventKey.new()
		press.unicode = character.unicode_at(0)
		press.keycode = KEY_SPACE if character == " " else KEY_NONE
		press.pressed = true
		Input.parse_input_event(press)
		var release := InputEventKey.new()
		release.unicode = press.unicode
		release.keycode = press.keycode
		release.pressed = false
		Input.parse_input_event(release)
	await _step(1)


## One key, pressed and released, through the input pipeline.
func _key(keycode: Key) -> void:
	var press := InputEventKey.new()
	press.keycode = keycode
	press.physical_keycode = keycode
	press.pressed = true
	Input.parse_input_event(press)
	await _step(1)
	var release := InputEventKey.new()
	release.keycode = keycode
	release.physical_keycode = keycode
	release.pressed = false
	Input.parse_input_event(release)
	await _step(1)


func _write_raw(path: String, data: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()


func _remove_tmp() -> void:
	if not DirAccess.dir_exists_absolute(_tmp_dir):
		return
	for name in DirAccess.get_files_at(_tmp_dir):
		DirAccess.remove_absolute(_tmp_dir.path_join(name))
	DirAccess.remove_absolute(_tmp_dir)


func _tap(action: StringName) -> void:
	Input.action_press(action)
	await _step(2)
	Input.action_release(action)
	await _step(2)


func _step(frames: int) -> void:
	for i in frames:
		await physics_frame


func _check(condition: bool, description: String) -> bool:
	if condition:
		print("  ok    ", description)
	else:
		_failures += 1
		printerr("  FAIL  ", description)
	return condition


func _finish() -> void:
	for action in [&"accelerate", IssueFlagger.ACTION, Garage.ACTION_OPEN]:
		Input.action_release(action)
	if _failures == 0:
		print("ISSUE FLAG TEST PASSED")
	else:
		print("ISSUE FLAG TEST FAILED: %d check(s) failed" % _failures)
	quit(1 if _failures > 0 else 0)
