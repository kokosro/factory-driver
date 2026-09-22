extends SceneTree
## Headless menu test: the garage, THE STUDY, the car's condition, the
## licence panel, the data folder and the bar legend. Run via
## tests/run_tests.sh, or:
##
##   godot --headless --path . --import
##   godot --headless --fixed-fps 60 --path . --script res://tests/menu_test.gd
##
## Loads the main scene and opens the garage the way a player would: the
## Tab key, and Esc when nothing at all is up (never the Esc that closes a
## banner); refused over a run. Open, the tree is paused and the car is
## frozen: the same drive with the garage open for a while in the middle
## comes out identical to the bit to the same drive without it. Then the
## DRIVE page's routes, each started through the real manager (a handling
## test through the mission manager, the L0 sitting and the skid pad
## through the licence manager, free driving simply closing the door), the
## one map there is listed as the one map there is. Then THE STUDY: the
## catalogue's integrity (every lesson a title, an objective, a group, and
## a pilot that is found or an honest coming-soon flag; the reused pilots
## the very test and exam definitions, not copies; the lesson pilots'
## steps only conditions and keys the runner and the InputMap know), the
## captions, and lessons run for real: the steering lesson through the
## garage's row (the instructor's car - the gate off, the managers stood
## down - and everything handed back after it, the dashboard included),
## the stall lesson flashing STALL and RUNNING AGAIN, the TCS lesson
## flashing WHEEL SPIN and the switch, a lesson ended on Esc, one refused
## over a mission, a coming-soon row refused, and the STOP BOX walkthrough
## passing on the certified pilot. Then the input display off the car's
## state and the events as pure functions of a snapshot; the CAR page off
## a store file of the test's own and off the live car; the LICENCE panel
## against the manager's record as passes go in; the data folder's
## resolution (the variable, the bootstrap file, the default, what is
## refused), the bootstrap file, the one-time seed (copies, never
## overwrites, never touches the source, once) and the autoload that ran
## it (nothing seeded with no window); the bar legend naming every bar;
## the keys in the map, Tab among them; and no folder dialog ever made.
## Exits 0 on success, 1 on any failed check.

const MAIN_SCENE := "res://scenes/main.tscn"

## Physics frames to let the scene settle after loading.
const SETTLE_FRAMES := 20

## Give up on a lesson after this many physics frames (60 s).
const MAX_LESSON_FRAMES := 3600

## The determinism drive: ticks of driving before the garage opens, ticks
## it stays open, ticks after (the same drive without it is the sum of the
## first and the last) [physics ticks], and the driver's inputs on it.
const DRIVE_BEFORE_FRAMES := 60
const GARAGE_OPEN_FRAMES := 60
const DRIVE_AFTER_FRAMES := 60
const DRIVE_THROTTLE := 1.0
const DRIVE_STEER := 0.35

## Ticks the donuts lesson runs before Esc ends it.
const ABORT_AFTER_FRAMES := 30

## Where the store and folder checks write: a folder of this test's own,
## one per process, removed at the end.
const TMP_DIR_PREFIX := "/tmp/fd-4A-menu-"

## The step conditions LicenceExams' runner knows (its _conditions_met).
const KNOWN_CONDITIONS: Array[String] = [
	"after", "speed_above", "speed_below", "travelled", "rotation_deg", "rotation_deg_below",
	"z_below", "z_above", "x_below", "x_above", "stopped", "reversed", "swept_deg",
]

## The actions the controls text names, every one of which the map must have.
const LISTED_ACTIONS: Array[StringName] = [
	&"accelerate", &"brake", &"steer_left", &"steer_right", &"handbrake", &"shift_down", &"shift_up",
	&"toggle_gearbox", &"gearbox_mode", &"tcs_toggle", &"abs_toggle", &"sc_toggle", &"clutch_pedal",
	&"starter", &"reset_car", &"camera_cycle", &"look_back", &"look_left", &"look_right", &"xray_view",
	&"test_1", &"test_2", &"test_3", &"test_4", &"test_5", &"abort_mission", &"licence_book", &"garage",
]

var _failures := 0
var _main: Node
var _car: ArcadeCar
var _pad: TestPad
var _hud: HUD
var _missions: MissionManager
var _licence: LicenceManager
var _study: Study
var _garage: Garage
var _banner: Label
var _tmp_dir := ""


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var packed: PackedScene = load(MAIN_SCENE)
	if not _check(packed != null, "main scene loads"):
		_finish()
		return
	_main = packed.instantiate()
	root.add_child(_main)
	await _step(SETTLE_FRAMES)
	_car = _main.get_node_or_null("Car") as ArcadeCar
	_pad = _main.get_node_or_null("TestPad") as TestPad
	_hud = _main.get_node_or_null("HUD") as HUD
	_missions = _main.get_node_or_null("MissionManager") as MissionManager
	_licence = _main.get_node_or_null("LicenceManager") as LicenceManager
	_study = _main.get_node_or_null("Study") as Study
	_garage = _main.get_node_or_null("Garage") as Garage
	_banner = _main.get_node_or_null("HUD/MissionBanner") as Label
	if not _check(_car != null and _pad != null and _hud != null and _missions != null and _licence != null and _study != null and _garage != null and _banner != null, "Car, TestPad, HUD, MissionManager, LicenceManager, Study and Garage exist"):
		_finish()
		return
	_tmp_dir = TMP_DIR_PREFIX + str(OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(_tmp_dir)

	print("-- the garage")
	await _check_open_close()
	await _check_frozen_car()
	print("-- the DRIVE page")
	await _check_routes()
	print("-- THE STUDY: the catalogue")
	_check_catalogue()
	print("-- THE STUDY: lessons run")
	await _check_lessons()
	print("-- the input display")
	await _check_input_display()
	print("-- the CAR page")
	_check_condition()
	print("-- the data folder")
	_check_data_dir()
	print("-- the bar legend and the keys")
	_check_legend_and_keys()
	print("-- the LICENCE page")
	_check_licence_panel()

	_car.clear_driver_input()
	_car.reset_to_spawn()
	_pad.reset_cones()
	_finish()


# =============================================================================
#  The garage: open, close, the keys
# =============================================================================

func _check_open_close() -> void:
	_check(not _garage.is_open and not _garage.visible and not paused, "the garage starts closed and the tree unpaused")
	_check(_garage.process_mode == Node.PROCESS_MODE_ALWAYS and _garage.layer > _hud.layer, "the garage processes through a pause and draws over the HUD (layer %d over %d)" % [_garage.layer, _hud.layer])
	_check(_garage.open() and _garage.is_open and _garage.visible and paused, "open(): the garage is up and the tree is paused")
	_garage.close()
	_check(not _garage.is_open and not _garage.visible and not paused, "close(): down again, the tree runs")
	await _tap(Garage.ACTION_OPEN)
	_check(_garage.is_open and paused, "Tab opens the garage")
	await _tap(Garage.ACTION_OPEN)
	_check(not _garage.is_open and not paused, "Tab closes it again")
	await _step(2)
	await _tap(&"abort_mission")
	_check(_garage.is_open, "Esc opens the garage when nothing at all is running")
	await _tap(&"abort_mission")
	_check(not _garage.is_open and not paused, "Esc closes it")
	# The Esc that closes a banner never opens the garage as well.
	await _tap(&"test_4")
	_check(_missions.is_running() and _missions.selected_index == 3, "key 4 starts the stop box")
	_check(not _garage.open() and not _garage.is_open, "the garage refuses to open over a running test")
	await _tap(Garage.ACTION_OPEN)
	_check(not _garage.is_open and _missions.is_running(), "Tab does nothing over a running test, which runs on")
	await _tap(&"abort_mission")
	_check(not _missions.is_running() and _missions.state == MissionManager.State.RESULT and not _garage.is_open, "Esc aborts the test (the banner is up), the garage stays closed")
	await _tap(&"abort_mission")
	_check(_missions.state == MissionManager.State.IDLE and not _garage.is_open, "Esc takes the banner down and does NOT open the garage on the same press")
	await _step(2)
	await _tap(&"abort_mission")
	_check(_garage.is_open, "... the next Esc, everything idle, opens it")
	_garage.close()
	await _step(2)
	# The book: Esc closes it and nothing more.
	await _tap(LicenceManager.ACTION_BOOK)
	_check(_licence.book_open and not _garage.is_open, "L opens the licence book, the garage stays closed")
	await _tap(&"abort_mission")
	_check(not _licence.book_open and not _garage.is_open, "Esc closes the book and does not open the garage on the same press")
	await _tap(LicenceManager.ACTION_BOOK)
	_check(_licence.book_open and _garage.open() and not _licence.book_open and not _hud.licence_card_visible(), "opening the garage over the book closes the book first")
	_garage.close()
	await _step(2)


## The same drive twice, once with the garage open for GARAGE_OPEN_FRAMES in
## the middle: the car does not move a bit while it is open, and the drive
## ends identical to the bit.
func _check_frozen_car() -> void:
	await _fresh()
	_car.set_driver_input(DRIVE_THROTTLE, 0.0, DRIVE_STEER)
	await _step(DRIVE_BEFORE_FRAMES + DRIVE_AFTER_FRAMES)
	var plain := _snapshot()
	_car.clear_driver_input()
	await _fresh()
	_car.set_driver_input(DRIVE_THROTTLE, 0.0, DRIVE_STEER)
	await _step(DRIVE_BEFORE_FRAMES)
	var before_open := _snapshot()
	_garage.open()
	var at_open := _snapshot()
	await _step(GARAGE_OPEN_FRAMES)
	var while_open := _snapshot()
	_garage.close()
	await _step(DRIVE_AFTER_FRAMES)
	var after := _snapshot()
	_car.clear_driver_input()
	_check(before_open.speed > 2.0 and at_open == before_open, "the drive is under way when the garage opens (%.1f m/s), and opening moves nothing" % before_open.speed)
	_check(while_open == at_open, "%d ticks with the garage open: the car's state is identical to the bit (position, velocity, engine, gear, fuel, heat, steering, odometer)" % GARAGE_OPEN_FRAMES)
	_check(after == plain, "the drive after the garage ends identical to the bit to the same %d ticks without it (%.3f m/s, %.4f m along)" % [DRIVE_BEFORE_FRAMES + DRIVE_AFTER_FRAMES, after.speed, after.position.z])
	_check(after.speed > before_open.speed, "... and it is a drive: faster after the door closed than before it opened")


## The car's state as one dictionary of exact values.
func _snapshot() -> Dictionary:
	return {
		"position": _car.global_position,
		"rotation": _car.global_rotation,
		"velocity": _car.velocity,
		"speed": _car.forward_speed,
		"yaw_rate": _car.yaw_rate,
		"engine_omega": _car.engine_omega,
		"gear": _car.gear,
		"front_omega": _car.front_omega,
		"rear_omega": _car.rear_omega,
		"clutch": _car.clutch_engagement,
		"fuel_l": _car.fuel_l,
		"rear_tyre_temp": _car.rear_tyre_temp,
		"coolant": _car.coolant_temp,
		"steering_wheel_deg": _car.steering_wheel_deg,
		"wheel_angle": _car.wheel_angle,
		"odometer_delta": _car.odometer_m - _odometer_at_fresh,
		"throttle": _car.throttle_pedal,
		"body_pitch": _car.body_pitch,
	}


var _odometer_at_fresh := 0.0


## The fresh car on the start line: the full tank, the operating heat, new
## components (what a handling test's start hands out), reset, settled.
func _fresh() -> void:
	_car.fuel_l = ArcadeCar.FUEL_TANK_CAPACITY_L
	_car.fuel_mass = _car.fuel_l * ArcadeCar.FUEL_DENSITY
	_car.coolant_temp = 1.0
	_car.coolant_fan_on = false
	_car._combustion_heat_w = 0.0
	_car._idle_wobble_phase = 0.0
	_car.front_tyre_temp = 1.0
	_car.rear_tyre_temp = 1.0
	_car.front_brake_temp = 0.0
	_car.rear_brake_temp = 0.0
	_car._front_tyre_heat_w = 0.0
	_car._rear_tyre_heat_w = 0.0
	_car._front_brake_heat_w = 0.0
	_car._rear_brake_heat_w = 0.0
	_car.clutch_wear = 0.0
	_car.front_brake_wear = 0.0
	_car.rear_brake_wear = 0.0
	_car.front_tyre_wear = 0.0
	_car.rear_tyre_wear = 0.0
	_car.engine_wear = 0.0
	_car._clutch_slip_w = 0.0
	_car.reset_to_spawn()
	await _step(SETTLE_FRAMES)
	_odometer_at_fresh = _car.odometer_m


# =============================================================================
#  The DRIVE page
# =============================================================================

func _check_routes() -> void:
	_garage.open()
	_garage.show_page(Garage.Page.DRIVE)
	var rows := _garage.page_rows()
	var tests := HandlingTests.all_tests()
	var kinds := PackedStringArray()
	for row in rows:
		kinds.append(row.kind)
	_check(Garage.MAPS.size() == 1 and Garage.MAPS[0].title == "Factory test pad" and Garage.MAPS[0].scene == MAIN_SCENE, "the map list holds exactly the one map there is, the Factory test pad, the main scene")
	_check(rows.size() == 1 + tests.size() + 2 and kinds[0] == "map" and kinds[6] == "l0" and kinds[7] == "skid_pad", "DRIVE lists the map, the %d handling tests, the L0 sitting and the skid pad exam (%s)" % [tests.size(), ", ".join(kinds)])
	var in_order := true
	for index in tests.size():
		in_order = in_order and rows[1 + index].kind == "test" and rows[1 + index].id == tests[index].name and rows[1 + index].label.contains(tests[index].title)
	_check(in_order and rows[0].label.contains("Factory test pad"), "the test rows are HandlingTests.all_tests() in order, by name and title; the map row names the pad")

	var position_before := _car.global_position
	_check(_garage.activate_row(0) and not _garage.is_open and not paused and not _missions.is_running() and not _licence.is_running() and _car.global_position == position_before, "free drive closes the door and starts nothing; the car is where it was")
	_garage.open()
	_check(_garage.activate_row(2) and not _garage.is_open and _missions.is_running() and _missions.selected_index == 1 and not _missions.run.scripted, "the test 2 row starts the 180 through the mission manager, a human run, and closes the door")
	_missions.abort_mission()
	await _step(int(MissionManager.ABORT_BANNER_TIME * Engine.physics_ticks_per_second) + 5)
	_check(_missions.state == MissionManager.State.IDLE, "aborted, the banner timed out")
	_garage.open()
	_garage.show_page(Garage.Page.DRIVE)
	_check(_garage.activate_row(6) and not _garage.is_open and _licence.is_running() and _licence.exam == LicenceExams.EXAM_L0 and _hud.licence_card_visible(), "the L0 row starts the sitting through the licence manager: the theory card is up")
	_licence.abort_sitting()
	await _step(int(LicenceManager.ABORT_BANNER_TIME * Engine.physics_ticks_per_second) + 5)
	_garage.open()
	_garage.show_page(Garage.Page.DRIVE)
	_check(_garage.activate_row(7) and not _garage.is_open and _licence.is_running() and _licence.exam == LicenceExams.EXAM_SKID_PAD, "the skid pad row starts the skid pad test through the licence manager")
	_licence.abort_sitting()
	await _step(int(LicenceManager.ABORT_BANNER_TIME * Engine.physics_ticks_per_second) + 5)
	_check(_licence.state == LicenceManager.State.IDLE and not _garage.is_open, "aborted, idle again")
	_check(not _garage.activate_row(99) and not _garage.activate_row(-1), "a row that is not there does nothing")


# =============================================================================
#  THE STUDY: the catalogue
# =============================================================================

func _check_catalogue() -> void:
	var catalogue := StudyLessons.catalogue()
	var ids := {}
	var well_formed := true
	var real := 0
	var soon := 0
	var reused_intact := true
	var captions_in_range := true
	var pilots_sound := true
	var handling_names := {}
	for test in HandlingTests.all_tests():
		handling_names[test.name] = test
	var exam_names := {}
	for element in LicenceExams.l0_sitting():
		exam_names[element.name] = element
	exam_names[LicenceExams.EXAM_SKID_PAD] = LicenceExams.skid_pad_test()
	for entry in catalogue:
		well_formed = well_formed and entry.get("id", "") != "" and entry.get("title", "") != "" and entry.get("objective", "") != "" and StudyLessons.GROUPS.has(entry.get("group", ""))
		well_formed = well_formed and not ids.has(entry.id)
		ids[entry.id] = true
		var pilot := StudyLessons.pilot_for(entry)
		if entry.get("coming_soon", false):
			soon += 1
			well_formed = well_formed and pilot.is_empty() and entry.pilot == "" and entry.objective.begins_with("Coming soon")
			continue
		real += 1
		well_formed = well_formed and not pilot.is_empty() and pilot.get("name", "") == entry.pilot and pilot.has("kind") and not (pilot.get("steps", []) as Array).is_empty() and pilot.get("time_limit", 0.0) > 0.0
		match entry.source:
			StudyLessons.SOURCE_HANDLING:
				reused_intact = reused_intact and handling_names.has(entry.pilot) and pilot == handling_names[entry.pilot]
			StudyLessons.SOURCE_EXAM:
				reused_intact = reused_intact and exam_names.has(entry.pilot) and pilot == exam_names[entry.pilot]
			StudyLessons.SOURCE_STUDY:
				pilots_sound = pilots_sound and pilot.kind == LicenceExams.KIND_LESSON and _pilot_sound(pilot)
		for caption: Dictionary in entry.get("captions", []):
			captions_in_range = captions_in_range and int(caption.step) >= 0 and int(caption.step) < (pilot.steps as Array).size() and String(caption.say) != ""
	_check(well_formed and catalogue.size() == real + soon and real >= 20 and soon >= 1, "%d lessons, every one with an id, a title, an objective and a group: %d with a pilot that is found, %d honestly coming soon" % [catalogue.size(), real, soon])
	_check(reused_intact, "every handling-test and exam-element lesson runs the test's or the element's own definition, equal in every field (reused, not forked)")
	_check(pilots_sound, "every lesson pilot of the study's own is KIND_LESSON, with steps that use only the runner's conditions, press only keys of LESSON_ACTIONS that the InputMap has, and say non-empty lines")
	_check(captions_in_range, "every caption overlay names a step its pilot has, with a line to say")
	var real_ids := PackedStringArray()
	var soon_ids := PackedStringArray()
	for entry in catalogue:
		if entry.get("coming_soon", false):
			soon_ids.append(entry.id)
		else:
			real_ids.append(entry.id)
	_check(soon_ids.has("traffic_rules") and soon_ids.has("traffic_lights") and not real_ids.has("traffic_rules"), "traffic rules and traffic lights are coming soon (the 4C world), not lessons (soon: %s)" % ", ".join(soon_ids))
	var groups_in_order := true
	var last_group := -1
	for entry in catalogue:
		var group := StudyLessons.GROUPS.find(entry.group)
		groups_in_order = groups_in_order and group >= last_group
		last_group = group
	_check(groups_in_order, "the catalogue is listed group by group in GROUPS' order (%s)" % ", ".join(StudyLessons.GROUPS))
	_check(StudyLessons.lesson("steering").pilot == "STEERING" and StudyLessons.lesson("no_such").is_empty(), "lesson(id) finds a lesson and returns empty for none")

	# Captions: the objective before any step, the last step that says
	# something, a step without a line keeping the one before, an overlay
	# line for a reused pilot.
	var steering := StudyLessons.lesson("steering")
	var steering_pilot := StudyLessons.pilot_for(steering)
	var spin := StudyLessons.lesson("spin_180")
	var spin_pilot := StudyLessons.pilot_for(spin)
	var last_step: int = (steering_pilot.steps as Array).size()
	_check(
		StudyLessons.caption_for(steering, steering_pilot, 0) == steering.objective
		and StudyLessons.caption_for(steering, steering_pilot, 1) == steering_pilot.steps[0].say
		and StudyLessons.caption_for(steering, steering_pilot, last_step) == steering_pilot.steps[last_step - 2].say
		and StudyLessons.caption_for(spin, spin_pilot, 0) == spin.objective
		and StudyLessons.caption_for(spin, spin_pilot, 2) == spin.captions[1].say
		and StudyLessons.caption_for(spin, spin_pilot, 7) == spin.captions[5].say
		and StudyLessons.caption_for(spin, spin_pilot, 8) == spin.captions[6].say,
		"caption_for: the objective before the first step, a step's own line, the line before for a step without one, a reused pilot's overlay line for the last step at or before it",
	)


## A lesson pilot's steps: conditions the runner knows, keys the lesson
## list and the InputMap have, lines to say.
func _pilot_sound(pilot: Dictionary) -> bool:
	var sound := true
	for step: Dictionary in pilot.steps:
		for condition: String in step.get("when", {}):
			sound = sound and KNOWN_CONDITIONS.has(condition)
		for action: StringName in step.get("press", []) + step.get("release", []):
			sound = sound and StudyLessons.LESSON_ACTIONS.has(action) and InputMap.has_action(action)
		if step.has("say"):
			sound = sound and step.say is String and step.say != ""
	return sound


# =============================================================================
#  THE STUDY: lessons run
# =============================================================================

func _check_lessons() -> void:
	# The steering lesson through the garage's row, on a car left in a
	# state of its own: it comes back as it was.
	await _fresh()
	_car.tcs_on = false
	_car.gearbox_mode = ArcadeCar.GearboxMode.ECO
	_car.set_driver_profile(ArcadeCar.DRIVER_PROFILES[ArcadeCar.MODE_DRIVERS[_car.gearbox_mode]])
	_car.automatic = false
	var dashboard_before := _car.driver_settings()
	var gate_before: Object = _car.licence_gate
	_garage.open()
	_garage.show_page(Garage.Page.STUDY)
	var rows := _garage.page_rows()
	var steering_row := -1
	var soon_row := -1
	for index in rows.size():
		if rows[index].id == "steering":
			steering_row = index
		if rows[index].id == "traffic_rules":
			soon_row = index
	_check(steering_row >= 0 and rows[steering_row].enabled and soon_row >= 0 and not rows[soon_row].enabled and rows[soon_row].label.contains("coming soon"), "THE STUDY lists the steering lesson startable and traffic rules greyed as coming soon")
	_check(not _garage.activate_row(soon_row) and _garage.is_open and not _study.is_running(), "a coming-soon row starts nothing")
	_check(_garage.activate_row(steering_row) and not _garage.is_open and not paused and _study.is_running() and _study.lesson.id == "steering", "the steering row starts the lesson through the study and closes the door")
	_check(gate_before == _licence and _car.licence_gate == null and _licence.process_mode == Node.PROCESS_MODE_DISABLED and _missions.start_keys_locked, "the instructor's car: the licence gate is off, the licence manager's keys stand down, the mission keys are held")
	_check(_car.tcs_on and _car.automatic and _car.gearbox_mode == ArcadeCar.GearboxMode.SPORT, "the lesson's dashboard: the aids on, automatic, sport")
	_check(_hud.study_panel_visible() and _hud.get_node("StudyPanel/Caption").text == StudyLessons.lesson("steering").objective, "the input display is up with the objective as its first caption")
	_check(not _garage.can_open() and not _garage.open(), "the garage cannot open over a lesson")
	var seen := await _watch_lesson()
	var steering_pilot := StudyLessons.pilot_for(StudyLessons.lesson("steering"))
	_check(_study.state == Study.State.RESULT and seen.frames < MAX_LESSON_FRAMES, "the lesson ends by itself (%d frames)" % seen.frames)
	_check(seen.steer_max == 1.0 and seen.steer_min == -1.0 and seen.throttle_max > 0.0 and seen.brake_max > 0.0, "the display showed full left lock, full right lock, the throttle and the brake (steer %.1f .. %.1f, throttle %.2f, brake %.2f)" % [seen.steer_min, seen.steer_max, seen.throttle_max, seen.brake_max])
	_check(seen.captions.size() >= 4 and seen.captions.has(steering_pilot.steps[1].say) and seen.captions.has(steering_pilot.steps[5].say), "the captions followed the steps (%d different lines, the left-lock and the stop lines among them)" % seen.captions.size())
	_check(_banner.visible and _banner.text == "LESSON OVER  STEERING" and not _hud.study_panel_visible(), "LESSON OVER banner up, the input display down")
	_check(_car.licence_gate == _licence and _licence.process_mode == Node.PROCESS_MODE_INHERIT and not _missions.start_keys_locked, "the car is handed back: the gate, the licence manager's keys, the mission keys")
	_check(_car.driver_settings() == dashboard_before and not _car.tcs_on and not _car.automatic and _car.gearbox_mode == ArcadeCar.GearboxMode.ECO, "the dashboard is back as it was left: TCS off, manual, eco")
	_check(_all_released(), "every key a lesson may press is released")
	_check(_study.last_result.get("name", "") == "STEERING" and _study.last_result.get("passed", false), "a lesson pilot's verdict is only the time limit, and it is met")
	_study.dismiss_banner()
	_car.tcs_on = true
	_car.automatic = true
	_car.gearbox_mode = ArcadeCar.GearboxMode.SPORT
	_car.set_driver_profile(ArcadeCar.DRIVER_PROFILES[ArcadeCar.MODE_DRIVERS[_car.gearbox_mode]])

	# The stall lesson: STALL, then RUNNING AGAIN.
	await _fresh()
	_check(_study.start_lesson(StudyLessons.lesson("stall")) and _study.is_running() and not _car.automatic, "the stall lesson starts, in manual")
	seen = await _watch_lesson()
	_check(_study.state == Study.State.RESULT and seen.events.has("STALL") and seen.events.has("RUNNING AGAIN") and seen.stalled_text and _car.engine_running, "the engine stalled (STALL flashed, the gear line said STALLED), was cranked and caught (RUNNING AGAIN), and runs at the end (%d frames)" % seen.frames)
	_check(_car.automatic, "the automatic box is back after the manual lesson")
	_study.dismiss_banner()

	# The TCS lesson: the switch both ways, wheel spin without it.
	await _fresh()
	_check(_study.start_lesson(StudyLessons.lesson("tcs")), "the TCS lesson starts")
	seen = await _watch_lesson()
	_check(_study.state == Study.State.RESULT and seen.events.has("TCS OFF") and seen.events.has("TCS ON") and seen.events.has("WHEEL SPIN") and _car.tcs_on, "T flashed TCS OFF then TCS ON, the launch without it flashed WHEEL SPIN, and TCS is on at the end (%d frames)" % seen.frames)
	_study.dismiss_banner()

	# Esc ends a lesson: the donuts lesson, the aids off for it and back after.
	await _fresh()
	_check(_study.start_lesson(StudyLessons.lesson("donuts")) and not _car.tcs_on and not _car.sc_on, "the donuts lesson starts with TCS and SC off, as its dashboard says")
	await _step(ABORT_AFTER_FRAMES)
	await _tap(&"abort_mission")
	_check(_study.state == Study.State.RESULT and _banner.text.begins_with("LESSON ENDED") and _car.tcs_on and _car.sc_on and _car.licence_gate == _licence and _all_released(), "Esc ends it: LESSON ENDED, the aids back on, the gate back, every key released")
	_study.dismiss_banner()
	_check(not _study.start_lesson(StudyLessons.lesson("drifting")), "a coming-soon lesson is refused")
	_missions.start_mission(0)
	_check(_missions.is_running() and not _study.start_lesson(StudyLessons.lesson("steering")), "a lesson is refused over a running test")
	_missions.abort_mission()
	await _step(int(MissionManager.ABORT_BANNER_TIME * Engine.physics_ticks_per_second) + 5)

	# A walkthrough: the STOP BOX on the certified pilot, passing its own
	# checks as it does in the handling test.
	await _fresh()
	_check(_study.start_lesson(StudyLessons.lesson("stop_box")) and _study.run is HandlingTests and _study.run.scripted, "the STOP BOX walkthrough runs the handling test's own scripted driver")
	seen = await _watch_lesson()
	var outcome := _study.last_result
	for line in HandlingTests.format_result(outcome):
		print("  ", line)
	_check(_study.state == Study.State.RESULT and outcome.get("passed", false) and outcome.get("name", "") == "STOP_BOX" and seen.captions.size() >= 2, "the walkthrough passes the test's checks and captioned its two steps (%d frames)" % seen.frames)
	_study.dismiss_banner()
	await _step(2)


## Runs the lesson on to its end, noting what the input display showed.
func _watch_lesson() -> Dictionary:
	var seen := {"frames": 0, "steer_min": 0.0, "steer_max": 0.0, "throttle_max": 0.0, "brake_max": 0.0, "events": {}, "captions": {}, "stalled_text": false}
	while _study.is_running() and seen.frames < MAX_LESSON_FRAMES:
		await physics_frame
		seen.frames += 1
		var state := _hud.study_state()
		if state.is_empty():
			continue
		seen.steer_min = minf(seen.steer_min, state.steer)
		seen.steer_max = maxf(seen.steer_max, state.steer)
		seen.throttle_max = maxf(seen.throttle_max, state.throttle)
		seen.brake_max = maxf(seen.brake_max, state.brake)
		for event: String in state.events:
			seen.events[event] = true
		seen.captions[_hud.get_node("StudyPanel/Caption").text] = true
		seen.stalled_text = seen.stalled_text or state.gear_text.contains("STALLED")
	return seen


func _all_released() -> bool:
	for action in StudyLessons.LESSON_ACTIONS:
		if Input.is_action_pressed(action):
			return false
	return true


# =============================================================================
#  The input display
# =============================================================================

func _check_input_display() -> void:
	await _fresh()
	var delta := 1.0 / Engine.physics_ticks_per_second
	_hud.show_study_panel("display check")
	_car.set_driver_input(0.6, 0.0, -1.0)
	await _step(30)
	_hud.update_study_panel(_car, delta)
	var state := _hud.study_state()
	var marker: ColorRect = _hud.get_node("StudyPanel/SteerBarBack/Marker")
	var centre := (HUD.STUDY_STEER_BAR_WIDTH - HUD.STUDY_STEER_MARKER_WIDTH) * 0.5
	_check(
		state.steer == _car.steer and state.steer < -0.9 and marker.position.x > centre,
		"steering: the display reads the car's steer (%.2f, full right) and the marker sits right of centre (%.0f px of %.0f)" % [state.steer, marker.position.x, centre],
	)
	_check(state.throttle == _car.throttle_pedal and state.throttle > 0.5 and state.brake == 0.0 and state.clutch == 0.0, "pedals: the throttle bar reads the car's pedal (%.2f), the brake and the clutch bars are empty" % state.throttle)
	var throttle_bar: ColorRect = _hud.get_node("StudyPanel/ThrottleBarBack/ThrottleBar")
	var brake_bar: ColorRect = _hud.get_node("StudyPanel/BrakeBarBack/BrakeBar")
	_check(throttle_bar.visible and is_equal_approx(throttle_bar.scale.y, state.throttle) and not brake_bar.visible, "... the bars themselves: the throttle bar scaled to the pedal, the brake bar hidden")
	_check(state.gear_text.begins_with("GEAR G1   auto SPORT   engine running") and not state.handbrake and state.tcs_on, "the text line reads the gear, the program, the engine and the aids ('%s')" % state.gear_text.get_slice("\n", 0))
	_car.set_driver_input(0.0, 0.0, 0.0, true)
	await _step(5)
	_hud.update_study_panel(_car, delta)
	state = _hud.study_state()
	_check(state.handbrake and state.gear_text.contains("HANDBRAKE ON") and marker.position.x < centre + 1.0 + HUD.STUDY_STEER_BAR_WIDTH * 0.5, "the handbrake shows the tick it is pulled")
	_car.clear_driver_input()
	_hud.hide_study_panel()
	_check(not _hud.study_panel_visible(), "the display hides")

	# The events as pure functions of a snapshot.
	var base := HUD.study_snapshot(_car)
	var stalled := base.duplicate()
	stalled.engine_running = false
	var running := base.duplicate()
	var spinning := base.duplicate()
	spinning.rear_slip_ratio = HUD.STUDY_SPIN_SLIP + 0.1
	var locked := base.duplicate()
	locked.front_slip_ratio = -1.0
	locked.speed = 5.0
	var parked := locked.duplicate()
	parked.speed = 0.0
	var hot := base.duplicate()
	hot.coolant_temp = HUD.COOLANT_HOT_FRACTION
	hot.brake_temp = HUD.BRAKE_HOT_FRACTION
	hot.tyre_temp = HUD.TYRE_HOT_FRACTION
	var tcs_off := base.duplicate()
	tcs_off.tcs_on = false
	var shifted := base.duplicate()
	shifted.gear = 2
	var reversed := base.duplicate()
	reversed.reverse = true
	var events_ok := HUD.study_events(base, {}).is_empty() \
		and HUD.study_events(stalled, {}) == ["STALL"] \
		and HUD.study_events(running, stalled) == ["RUNNING AGAIN"] \
		and HUD.study_events(spinning, base) == ["WHEEL SPIN"] \
		and HUD.study_events(locked, base) == ["WHEELS LOCKED"] \
		and HUD.study_events(parked, base).is_empty() \
		and HUD.study_events(hot, base) == ["OVERHEAT", "BRAKE FADE", "TYRES HOT"] \
		and HUD.study_events(tcs_off, base) == ["TCS OFF"] \
		and HUD.study_events(base, tcs_off) == ["TCS ON"] \
		and HUD.study_events(shifted, base) == ["SHIFT G2"] \
		and HUD.study_events(reversed, base) == ["REVERSE"]
	_check(events_ok, "events: nothing on the fresh car; STALL; RUNNING AGAIN on the catch; WHEEL SPIN over %.2f slip; WHEELS LOCKED under -%.2f on the move and not parked; OVERHEAT, BRAKE FADE and TYRES HOT at the bars' lines; an aid off and on; SHIFT G2; REVERSE" % [HUD.STUDY_SPIN_SLIP, HUD.STUDY_SPIN_SLIP])
	var manual_stalled := stalled.duplicate()
	manual_stalled.automatic = false
	manual_stalled.handbrake = true
	manual_stalled.clutch = 1.0
	var text := HUD.study_gear_text(manual_stalled)
	_check(text.contains("manual") and text.contains("STALLED") and text.contains("HANDBRAKE ON") and text.contains("clutch pedal 100 %"), "the gear line for a stalled manual on the handbrake with the clutch down says so")


# =============================================================================
#  The CAR page
# =============================================================================

func _check_condition() -> void:
	var path := _tmp_dir.path_join("cars.json")
	var driver := {"tcs_on": false, "abs_on": true, "sc_on": true, "gearbox_mode": "eco", "automatic": false, "camera_view": 3}
	var battery := {"charge": 0.8, "capacity_wear": 0.1}
	var wear := {"clutch": 0.25, "brakes_front": 0.02, "brakes_rear": 0.01, "tyres_front": 0.1, "tyres_rear": 0.5, "engine": 0.003}
	OdometerStore.save_car(ArcadeCar.CAR_ID, 12345.6, 20.5, path, driver, battery, wear)
	OdometerStore.save_licence(ArcadeCar.CAR_ID, {"passed": [LicenceExams.EXAM_L0]}, path)
	var entry := Garage.stored_entry(ArcadeCar.CAR_ID, path)
	_check(
		entry.odometer_m == 12345.6 and entry.fuel_l == 20.5 and entry.driver == driver and entry.battery == battery and entry.wear == wear
		and entry.licence.level == LicenceExams.LICENCE_L0 and entry.licence.passed == [LicenceExams.EXAM_L0],
		"stored_entry reads a car's whole entry back from the store's file through the store's own loaders",
	)
	var text := Garage.condition_text(entry)
	_check(
		text.contains("ODOMETER  12.3 km") and text.contains("FUEL  20.5 L of 64  (32 %)") and text.contains("BATTERY  charge 80 %, health 90.0 %")
		and text.contains("clutch 25.000 %") and text.contains("rear 50.000 %") and text.contains("TCS OFF") and text.contains("MANUAL ECO") and text.contains("camera overhead")
		and text.contains("LICENCE  L0 CITIZEN") and text.contains(LicenceExams.EXAM_L0),
		"condition_text reads it out: the odometer in km, the tank in litres and %, the battery, every wear share, the dashboard by name, the licence",
	)
	var missing := Garage.stored_entry("no_such_car", path)
	_check(missing.odometer_m == 0.0 and missing.fuel_l == ArcadeCar.FUEL_TANK_CAPACITY_L and missing.wear == OdometerStore.WEAR_DEFAULTS and missing.licence.level == LicenceExams.LICENCE_NONE, "a car the file does not know is a new car: 0 km, a full tank, nothing worn, unlicensed")
	var live := Garage.car_entry(_car, _licence)
	_check(
		live.odometer_m == _car.odometer_m and live.fuel_l == _car.fuel_l and live.driver == _car.driver_settings() and live.battery == _car.battery_settings() and live.wear == _car.wear_settings()
		and live.licence.level == _licence.level() and live.keys() == entry.keys(),
		"car_entry reads the live car into the very same shape (odometer %.1f m, %.1f L)" % [live.odometer_m, live.fuel_l],
	)
	_garage.open()
	_garage.show_page(Garage.Page.CAR)
	var page := _garage.page_text()
	_check(
		page.contains("ODOMETER  %.1f km" % (_car.odometer_m / 1000.0)) and page.contains("Clutch:") and page.contains("Tyres Rear:") and page.contains("Battery health:")
		and page.contains("not kept in this run") and page.contains(Garage.car_name()) and _garage.page_rows().is_empty(),
		"the CAR page shows the live car's readout, a bar per component, the battery, and says the store is off in a headless run (%s)" % Garage.car_name(),
	)
	_garage.close()


# =============================================================================
#  The data folder
# =============================================================================

func _check_data_dir() -> void:
	var by_env := DataDir.resolve_root("/tmp/fd-env/", "/tmp/fd-boot")
	var by_bootstrap := DataDir.resolve_root("", "  /tmp/fd-boot\n")
	var by_default := DataDir.resolve_root("", "")
	var relative := DataDir.resolve_root("data/here", "/tmp/fd-boot")
	var godot_path := DataDir.resolve_root("", "user://elsewhere")
	_check(
		by_env.root == "/tmp/fd-env" and by_env.source == "env" and by_env.problem == ""
		and by_bootstrap.root == "/tmp/fd-boot" and by_bootstrap.source == "bootstrap" and by_bootstrap.problem == ""
		and by_default.root == "" and by_default.source == "default" and by_default.problem == "",
		"resolve_root: the variable wins (its trailing slash dropped), then the bootstrap file (trimmed), else the default",
	)
	_check(
		relative.root == "" and relative.source == "default" and relative.problem.contains("not an absolute path")
		and godot_path.root == "" and godot_path.problem.contains("Godot path"),
		"... a relative path and a user:// path are refused by name and the default is used, never a guess",
	)
	var root_before := DataDir.root()
	DataDir.apply_root("")
	var plain := DataDir.resolve("user://cars.json")
	DataDir.apply_root(_tmp_dir + "/")
	var mapped := DataDir.resolve("user://telemetry/index.json")
	var absolute := DataDir.resolve("/tmp/elsewhere/file.jsonl")
	var resource := DataDir.resolve("res://configs/cars/boxster_986.json")
	var on_disk := DataDir.root_on_disk()
	DataDir.apply_root(root_before)
	_check(
		plain == "user://cars.json" and mapped == _tmp_dir.path_join("telemetry/index.json") and absolute == "/tmp/elsewhere/file.jsonl" and resource == "res://configs/cars/boxster_986.json" and on_disk == _tmp_dir,
		"resolve: user:// is itself with no custom root, goes under the root with one, and an absolute or res:// path is always itself",
	)
	var bootstrap := _tmp_dir.path_join("data_dir.txt")
	var written := DataDir.set_bootstrap("/tmp/fd-chosen/", bootstrap)
	var read_back := DataDir.read_bootstrap(bootstrap)
	var refused := DataDir.set_bootstrap("relative/folder", bootstrap)
	var still := DataDir.read_bootstrap(bootstrap)
	var cleared := DataDir.set_bootstrap("", bootstrap)
	var gone := not FileAccess.file_exists(bootstrap) and DataDir.read_bootstrap(bootstrap) == ""
	_check(written == "" and read_back == "/tmp/fd-chosen" and refused != "" and still == "/tmp/fd-chosen" and cleared == "" and gone, "the bootstrap file: written with the chosen folder, a relative one refused and the file untouched, cleared for the default")

	# The one-time seed.
	var old_dir := _tmp_dir.path_join("old")
	var new_dir := _tmp_dir.path_join("new")
	DirAccess.make_dir_recursive_absolute(old_dir.path_join("telemetry/2026-01-01"))
	_write(old_dir.path_join("cars.json"), '{"version": 1, "cars": {}}')
	_write(old_dir.path_join("telemetry/index.json"), '{"next_session_id": 3}')
	_write(old_dir.path_join("telemetry/2026-01-01/0001_000000_free.jsonl"), '{"event": "session_start"}')
	var first := DataDir.seed_folder(new_dir, [_tmp_dir.path_join("nowhere"), old_dir])
	var copied: PackedStringArray = first.copied
	copied.sort()
	var contents_match := _read(new_dir.path_join("cars.json")) == _read(old_dir.path_join("cars.json")) \
		and _read(new_dir.path_join("telemetry/index.json")) == _read(old_dir.path_join("telemetry/index.json")) \
		and _read(new_dir.path_join("telemetry/2026-01-01/0001_000000_free.jsonl")) == _read(old_dir.path_join("telemetry/2026-01-01/0001_000000_free.jsonl"))
	_check(
		first.seeded and first.source == old_dir and copied == PackedStringArray(["cars.json", "telemetry/2026-01-01/0001_000000_free.jsonl", "telemetry/index.json"]) and contents_match and FileAccess.file_exists(new_dir.path_join(DataDir.MARKER_FILE)),
		"seed: a new folder gets a copy of cars.json and telemetry/ from the first source that has them (a source that is not there is passed over), byte for byte, and the marker",
	)
	var old_intact := FileAccess.file_exists(old_dir.path_join("cars.json")) and FileAccess.file_exists(old_dir.path_join("telemetry/index.json")) and FileAccess.file_exists(old_dir.path_join("telemetry/2026-01-01/0001_000000_free.jsonl")) and not FileAccess.file_exists(old_dir.path_join(DataDir.MARKER_FILE))
	_check(old_intact, "... the source is untouched: nothing moved, nothing deleted, no marker in it")
	_write(old_dir.path_join("cars.json"), '{"version": 1, "cars": {"changed": {}}}')
	var second := DataDir.seed_folder(new_dir, [old_dir])
	_check(not second.seeded and second.reason == "already seeded" and _read(new_dir.path_join("cars.json")) == '{"version": 1, "cars": {}}', "... and once seeded a folder is never seeded again, whatever the source now holds")
	var kept_dir := _tmp_dir.path_join("kept")
	DirAccess.make_dir_recursive_absolute(kept_dir)
	_write(kept_dir.path_join("cars.json"), '{"mine": true}')
	var third := DataDir.seed_folder(kept_dir, [old_dir])
	var third_copied: PackedStringArray = third.copied
	_check(third.seeded and not third_copied.has("cars.json") and third_copied.size() == 2 and _read(kept_dir.path_join("cars.json")) == '{"mine": true}', "... a file the new folder already has is never written over: the rest is copied round it")
	var empty_dir := _tmp_dir.path_join("empty")
	var fourth := DataDir.seed_folder(empty_dir, [_tmp_dir.path_join("nowhere")])
	_check(not fourth.seeded and fourth.reason == "nothing to copy" and FileAccess.file_exists(empty_dir.path_join(DataDir.MARKER_FILE)), "... with nothing to copy from the folder is marked fresh and left empty")
	var bootstrap_node := root.get_node_or_null("DataBootstrap")
	_check(bootstrap_node != null and bootstrap_node.seeded.is_empty() and not OdometerStore.enabled(), "the DataBootstrap autoload ran before the scene and seeded nothing with no window (the store is off)")
	_check(ProjectSettings.get_setting("application/config/use_custom_user_dir") == true and ProjectSettings.get_setting("application/config/custom_user_dir_name") == "factory-driver", "the project keeps user:// in a folder of its own, factory-driver")


func _write(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _read(path: String) -> String:
	return FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""


# =============================================================================
#  The bar legend and the keys
# =============================================================================

func _check_legend_and_keys() -> void:
	var legend := HUD.bar_legend()
	var names := ["THROTTLE", "BRAKE", "FUEL", "BATTERY", "COOLANT", "TYRES", "BRAKES", "TCS / ABS / SC", "ODO", "STEERING", "CLU", "WEAR", "STALL", "WHEEL SPIN"]
	var named := true
	for bar_name: String in names:
		named = named and legend.contains(bar_name)
	_check(named and legend.contains("%.0f %%" % (HUD.FUEL_RESERVE_FRACTION * 100.0)) and legend.contains("110 C") and legend.contains("250 C"), "the bar legend names every bar and lamp of the HUD, the study's display and the CAR page, with the lines their colours turn at")
	_garage.open()
	_garage.show_page(Garage.Page.SETTINGS)
	var page := _garage.page_text()
	var rows := _garage.page_rows()
	_check(page.contains(legend) and page.contains(Garage.CONTROLS_TEXT) and page.contains("This run:") and page.contains(DataDir.BOOTSTRAP_PATH), "the SETTINGS page shows the data location, the legend and the controls")
	_check(rows.size() == 2 and rows[0].kind == "choose_folder" and rows[1].kind == "default_folder" and not _garage.folder_dialog_opened(), "its two rows choose a folder and go back to the default; no folder dialog has been made")
	_garage.close()
	var mapped := true
	for action in LISTED_ACTIONS:
		mapped = mapped and InputMap.has_action(action)
	var tab := false
	for event in InputMap.action_get_events(Garage.ACTION_OPEN):
		tab = tab or (event is InputEventKey and (event as InputEventKey).physical_keycode == KEY_TAB)
	_check(mapped and tab, "every key the controls text names is in the InputMap, and the garage's is Tab")
	var pages := PackedStringArray()
	for title in Garage.PAGE_TITLES:
		pages.append(title)
	_check(pages == PackedStringArray(["DRIVE", "THE STUDY", "CAR", "LICENCE", "SETTINGS"]), "the five pages, in order")


# =============================================================================
#  The LICENCE page
# =============================================================================

func _check_licence_panel() -> void:
	var text := _garage.licence_text()
	_check(text.contains("LICENCE HELD:  %s" % LicenceExams.licence_title(_licence.level())) and text.contains("UNLICENSED") and text.contains("NEXT, L0 CITIZEN") and text.contains("PASSED:  nothing yet"), "unlicensed: the panel says so, nothing passed, the L0 sitting next")
	_garage.open()
	_garage.show_page(Garage.Page.LICENCE)
	_check(_garage.page_text().contains(_licence.book_text()) and _garage.page_text().contains(text), "the LICENCE page carries the rank panel and the licence book's own text")
	_garage.close()
	_licence.record_pass(LicenceExams.EXAM_L0)
	text = _garage.licence_text()
	var lists_all := true
	for exam in LicenceExams.L1_HANDLING_TESTS:
		lists_all = lists_all and text.contains(exam)
	_check(_licence.level() == LicenceExams.LICENCE_L0 and text.contains("LICENCE HELD:  L0 CITIZEN") and text.contains("NEXT, L1 FACTORY ENTRY") and lists_all and text.contains(LicenceExams.EXAM_SKID_PAD), "L0 recorded: the panel says L0 CITIZEN and lists the six passes L1 still takes")
	for exam in LicenceExams.L1_HANDLING_TESTS:
		_licence.record_pass(exam)
	_licence.record_pass(LicenceExams.EXAM_SKID_PAD)
	text = _garage.licence_text()
	_check(_licence.level() == LicenceExams.LICENCE_L1 and text.contains("LICENCE HELD:  L1 FACTORY ENTRY") and text.contains("RANK:  TEST DRIVER") and text.contains("RACE DRIVER"), "all seven recorded: L1 FACTORY ENTRY, the TEST DRIVER rank, the next rank named as not yet playable")


# =============================================================================
#  Harness
# =============================================================================

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
	for action in StudyLessons.LESSON_ACTIONS:
		Input.action_release(action)
	if _tmp_dir != "" and DirAccess.dir_exists_absolute(_tmp_dir):
		_remove_tree(_tmp_dir)
	if _failures == 0:
		print("MENU TEST PASSED")
	else:
		print("MENU TEST FAILED: %d check(s) failed" % _failures)
	quit(1 if _failures > 0 else 0)


## Removes the test's own folder, files first, folders after, deepest first.
## Hidden files included: the seed's marker is a dotfile, which the static
## listing skips, and a folder with one left in it never goes.
func _remove_tree(dir: String) -> void:
	var listing := DirAccess.open(dir)
	if listing == null:
		return
	listing.include_hidden = true
	for file_name in listing.get_files():
		DirAccess.remove_absolute(dir.path_join(file_name))
	for dir_name in listing.get_directories():
		_remove_tree(dir.path_join(dir_name))
	DirAccess.remove_absolute(dir)
