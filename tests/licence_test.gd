extends SceneTree
## Headless licence ladder test. Run via tests/run_tests.sh, or:
##
##   godot --headless --path . --import
##   godot --headless --fixed-fps 60 --path . --script res://tests/licence_test.gd
##
## Loads the main scene and sits the L0 exam through the LicenceManager the
## way a player would: the book opened with its key, the sitting started with
## key 1, and every element driven by a "pilot" - the same element begun a
## second time with the scripted driver on - working the input actions, the
## theory answered with the digit keys, exactly like the keyboard would. The
## manager's own run, the human one, judges: every element must come out
## PASSED on its measured checks (the parallel park's clearance from the
## car's footprint to the lines, the hill start's roll-back and no stall, the
## turn inside the lane, the reversing between the lines, the emergency stop
## inside the zone from the speed), the HUD must have shown the element line
## and the theory's cards, and the sitting grants L0.
##
## Around it, the gate in its three states: before L0 the clutch pedal key
## leaves the pedal on the floor of nothing (0) and the aid switches do not
## flip (the hint shows); during the sitting the pedal moves (the hill start
## is driven on it); after L0 the pedal moves and the switches flip. Then the
## honest failures, each a practice run on the complete record L0 left (the
## exam sat again from the theory; nothing it does changes the record): one
## that stalls on the hill (the clutch dumped on the locked axle with the
## throttle open) fails the sitting at once at element 4/7, one with a wrong
## theory answer fails at 1/7 before a wheel turns, and a hill start with the
## handbrake let go before the bite rolls back past the tolerance. The rigor
## rule, from the physics.
# was "a retake that stalls ... a retake with one wrong theory answer" (a
# retake a new sitting from the theory, all or nothing) -> practice runs on
# the complete record: the user's verdict, 2026-09-22 14:56 + 15:02 (each
# element passed is kept, a sitting resumes at the first not yet passed; a
# complete record sits the exam again from the theory as practice).
##
## Then L1: the skid pad test sat through the manager (two laps between the
## rings), the five handling tests' passes heard from the MissionManager's
## signal (a FAILED one is not recorded), and the level only once all seven
## are in. Then the record itself on a file of the test's own: it comes back
## to the bit, rides beside the wear and the rest through a car's save, a
## level the passes do not earn is brought down, and what is no field of its
## own is refused with the reason. Last, the per-element memory (the user's
## verdict, 2026-09-22 14:56 + 15:02): the elements passed as the record's
## third field, the level they earn, a sitting resumed at the first element
## not yet passed on a seeded record with the theory skipped, the
## instructor's car manual through the parks and the hill start and
## automatic from the turn, a failed element leaving the passed ones in the
## record and on the file with the retake resuming at it, and a practice run
## on a complete record changing nothing.
##
## The road's ramp too: linear between the ground lattice's points along its
## axis (the mesh is the ramp there), its gradient 8 % on the rise and exactly
## zero everywhere certified.
## Exits 0 on success, 1 on any failed check.

const MAIN_SCENE := "res://scenes/main.tscn"

## Physics frames to let the car settle on the ground at the start.
const SETTLE_FRAMES := 20

## Give up on an element after this many physics frames (70 s).
const MAX_ELEMENT_FRAMES := 4200

## Frames the clutch key is held for the gate's checks: 0.5 s, the pedal is
## on the floor in 0.2 (ArcadeCar.CLUTCH_PEDAL_SPEED).
const CLUTCH_HOLD_FRAMES := 30

## Where the store round-trip writes: one directory per process, removed at
## the end (tests/README.md).
const TMP_DIR_PREFIX := "/tmp/fd-3K-licence-"

## Every certified point the ramp must be exactly zero at: the start line,
## the stop box, the skid pad's centre and ring, the slalom's cones, the
## 360's goal, the reverse 180's, the test dip.
const CERTIFIED_POINTS: Array[Vector2] = [
	Vector2(0.0, -4.0), Vector2(0.0, 0.0), Vector2(0.0, -150.0), Vector2(-70.0, -90.0), Vector2(-42.0, -90.0),
	Vector2(20.0, -60.0), Vector2(20.0, -306.0), Vector2(0.0, -404.0), Vector2(0.0, -104.0), Vector2(25.0, -450.0),
	Vector2(0.0, 20.0), Vector2(-30.0, 20.0), Vector2(-30.0, 100.0),
]

var _failures := 0
var _manager: LicenceManager
var _missions: MissionManager
var _car: ArcadeCar
var _pad: TestPad
var _hud: HUD
var _mission_label: Label
var _banner: Label
var _card: Label
var _hint: Label
var _finished_signals := 0
var _levels_announced: Array[int] = []
var _store_dir := ""
var _store_file := ""


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_store_dir = "%s%d" % [TMP_DIR_PREFIX, OS.get_process_id()]
	_store_file = _store_dir + "/cars.json"
	var packed: PackedScene = load(MAIN_SCENE)
	if not _check(packed != null, "main scene loads"):
		_finish()
		return
	var main := packed.instantiate()
	root.add_child(main)
	await _step(SETTLE_FRAMES)

	_manager = main.get_node_or_null("LicenceManager") as LicenceManager
	_missions = main.get_node_or_null("MissionManager") as MissionManager
	_car = main.get_node_or_null("Car") as ArcadeCar
	_pad = main.get_node_or_null("TestPad") as TestPad
	_hud = main.get_node_or_null("HUD") as HUD
	_mission_label = main.get_node_or_null("HUD/MissionLabel") as Label
	_banner = main.get_node_or_null("HUD/MissionBanner") as Label
	_card = main.get_node_or_null("HUD/LicenceCard") as Label
	_hint = main.get_node_or_null("HUD/GateHint") as Label
	if not _check(_manager != null and _missions != null and _car != null and _pad != null and _hud != null, "LicenceManager, MissionManager, Car, TestPad and HUD exist"):
		_finish()
		return
	if not _check(_mission_label != null and _banner != null and _card != null and _hint != null, "HUD has a mission line, a banner, a licence card and a gate hint"):
		_finish()
		return
	_manager.sitting_finished.connect(func(_exam: String, _passed: bool) -> void: _finished_signals += 1)
	_manager.licence_changed.connect(func(level: int) -> void: _levels_announced.append(level))

	_check_data()
	_check_ramp()
	_check(
		not OdometerStore.enabled() and not _manager._store_kept and _manager.level() == LicenceExams.LICENCE_NONE and not _manager.has_passed(LicenceExams.EXAM_L0),
		"suite: the store is off headless, the manager keeps nothing and the driver starts unlicensed (%s)" % LicenceExams.licence_title(_manager.level()),
	)
	_check(_car.licence_gate == _manager, "the car's licence gate is the manager (wired in main.tscn)")
	_check(InputMap.has_action(LicenceManager.ACTION_BOOK) and InputMap.action_get_events(LicenceManager.ACTION_BOOK)[0].physical_keycode == KEY_L, "the licence book has its key, L")

	await _check_gate("unlicensed", false)
	await _check_book_and_keys()
	await _sit_l0()
	await _check_gate("licensed", true)
	await _sit_stalling_retake()
	await _sit_wrong_answer()
	await _check_roll_back_failure()
	await _sit_skid_pad()
	_check_l1_grant()
	_check_store()

	if DirAccess.dir_exists_absolute(_store_dir):
		if FileAccess.file_exists(_store_file):
			DirAccess.remove_absolute(_store_file)
		DirAccess.remove_absolute(_store_dir)
	_car.reset_to_spawn()
	_pad.reset_cones()
	_finish()


# =============================================================================
#  Data
# =============================================================================

## The ladder as data: the levels the passes earn, the L1 set, the ranks
## marked not playable beyond the first, the quiz well formed and fixed.
func _check_data() -> void:
	var five := LicenceExams.L1_HANDLING_TESTS
	var names := PackedStringArray()
	for test in HandlingTests.all_tests():
		names.append(test.name)
	_check(five.size() == 5 and Array(names) == Array(five), "L1's five handling tests are HandlingTests.all_tests() by name (%s)" % ", ".join(five))
	var requirements := LicenceExams.l1_requirements()
	_check(requirements.size() == 7 and requirements[0] == LicenceExams.EXAM_L0 and requirements[6] == LicenceExams.EXAM_SKID_PAD, "L1 takes seven passes: the L0 sitting, the five, the skid pad")
	var without_l0: Array = five.duplicate()
	without_l0.append(LicenceExams.EXAM_SKID_PAD)
	var all_but_one: Array = requirements.duplicate()
	all_but_one.erase("STOP_BOX")
	_check(
		LicenceExams.level_for([]) == LicenceExams.LICENCE_NONE
		and LicenceExams.level_for([LicenceExams.EXAM_L0]) == LicenceExams.LICENCE_L0
		and LicenceExams.level_for(without_l0) == LicenceExams.LICENCE_NONE
		and LicenceExams.level_for(all_but_one) == LicenceExams.LICENCE_L0
		and LicenceExams.level_for(requirements) == LicenceExams.LICENCE_L1
		and LicenceExams.level_for(requirements + ["SOMETHING_ELSE"]) == LicenceExams.LICENCE_L1,
		"level_for: nothing is unlicensed, the sitting is L0, the six without the sitting are nothing, six of seven are L0, all seven are L1",
	)
	var ranks := LicenceExams.RANKS
	_check(
		ranks.size() == 3 and ranks[0].title == "TEST DRIVER" and ranks[0].playable and ranks[0].requires.licence == LicenceExams.LICENCE_L1
		and not ranks[1].playable and not ranks[2].playable and ranks[2].has("reward"),
		"ranks: test driver (= L1, playable) -> race driver -> chief test driver, the last two marked not playable, the reward a note",
	)
	var questions := LicenceExams.quiz_questions()
	var well_formed := questions.size() >= 5 and questions.size() <= 8
	var corrects := PackedInt32Array()
	for question in questions:
		var answers: Array = question.answers
		well_formed = well_formed and answers.size() >= 2 and answers.size() <= LicenceExams.ANSWER_ACTIONS.size() and question.correct >= 1 and question.correct <= answers.size() and question.question != ""
		corrects.append(question.correct)
	var again := LicenceExams.quiz_questions()
	var fixed := again.size() == questions.size()
	for i in questions.size():
		fixed = fixed and again[i].question == questions[i].question and again[i].correct == questions[i].correct
	var spread := {}
	for correct in corrects:
		spread[correct] = true
	_check(well_formed and fixed and spread.size() >= 2, "quiz: %d questions, each with 2-4 answers and one right one, the same order every time, the right digit not always the same" % questions.size())
	var sitting := LicenceExams.l0_sitting()
	var order := PackedStringArray()
	for element in sitting:
		order.append(element.name)
	_check(sitting.size() == 7 and sitting[0].kind == LicenceExams.KIND_QUIZ and order[3] == "HILL_START" and order[6] == "EMERGENCY_STOP", "the sitting is seven elements, the theory first, in a fixed order (%s)" % ", ".join(order))


# =============================================================================
#  The ramp
# =============================================================================

## The road's licence ramp: 8 % on the rise, level on top, nothing off it,
## and linear between the ground lattice's points along its axis, so the
## mesh the pad builds from those points is the ramp exactly there.
func _check_ramp() -> void:
	var road: RoadProfile = _pad.road_profile
	var hill := TestPad.hill_start()
	var x: float = hill.axis_x
	var rise := road.ramp_gradient(x, (RoadProfile.RAMP_FOOT_Z + RoadProfile.RAMP_CREST_Z) * 0.5)
	var top := road.ramp_gradient(x, (RoadProfile.RAMP_CREST_Z + RoadProfile.RAMP_TOP_END_Z) * 0.5)
	var fall := road.ramp_gradient(x, (RoadProfile.RAMP_TOP_END_Z + RoadProfile.RAMP_TAIL_Z) * 0.5)
	var grade := RoadProfile.RAMP_HEIGHT / (RoadProfile.RAMP_FOOT_Z - RoadProfile.RAMP_CREST_Z)
	_check(
		is_equal_approx(rise.y, -grade) and rise.x == 0.0 and top == Vector2.ZERO and is_equal_approx(fall.y, grade) and is_equal_approx(grade, 0.08),
		"ramp: %.0f %% up the rise (towards -z), level on top, %.0f %% down the fall" % [grade * 100.0, grade * 100.0],
	)
	var zero_everywhere_certified := true
	for point in CERTIFIED_POINTS:
		zero_everywhere_certified = zero_everywhere_certified and road.ramp_height_at(point.x, point.y) == 0.0 and road.ramp_gradient(point.x, point.y) == Vector2.ZERO
	_check(zero_everywhere_certified, "ramp: exactly zero height and gradient at every certified point (%d checked)" % CERTIFIED_POINTS.size())
	# Along the axis, between lattice points 5 m apart, the elevation is the
	# straight line between them (to rounding): what the mesh shows.
	var worst := 0.0
	var step := TestPad.GROUND_FINE_STEP
	var z := RoadProfile.RAMP_TAIL_Z - step
	while z < RoadProfile.RAMP_FOOT_Z + step:
		var low := road.elevation_height(x, z)
		var high := road.elevation_height(x, z + step)
		for i in range(1, 10):
			var between := z + step * i / 10.0
			worst = maxf(worst, absf(road.elevation_height(x, between) - lerpf(low, high, i / 10.0)))
		z += step
	_check(worst < 0.0005, "ramp: along its axis the elevation is straight between the ground mesh's %.0f m points (largest deviation %.2f mm), the swell under the yard is within a centimetre" % [step, worst * 1000.0])
	var crest := road.elevation_height(x, (RoadProfile.RAMP_CREST_Z + RoadProfile.RAMP_TOP_END_Z) * 0.5)
	_check(absf(crest - RoadProfile.RAMP_HEIGHT) < 0.01, "ramp: the top stands %.2f m up (%.2f m of ramp on the yard's swell)" % [crest, RoadProfile.RAMP_HEIGHT])
	# The yard's cones stand on the ground, in their groups.
	var groups := {
		TestPad.GROUP_PARALLEL_BAY: 2, TestPad.GROUP_PARKING_BAY: 2, TestPad.GROUP_REVERSING: 4, TestPad.GROUP_EMERGENCY_STOP: 2,
	}
	var placed := true
	for group: StringName in groups:
		var cones := _pad.get_cone_positions(group)
		placed = placed and cones.size() == groups[group]
		for home in cones:
			placed = placed and absf(home.y - _pad.elevation_height(home.x, home.z)) < 0.001
	_check(placed, "yard: the bays', gates' and zone's cones stand on the ground in their groups (2, 2, 4, 2)")


# =============================================================================
#  The gate
# =============================================================================

## The clutch key and the three aid switches, `licensed` or not: held for
## CLUTCH_HOLD_FRAMES in manual, the pedal moves or stays at 0; tapped, a
## switch flips or stays, and the hint shows when refused.
func _check_gate(label: String, licensed: bool) -> void:
	_fresh_fuel(_car)
	_car.reset_to_spawn()
	await _step(5)
	_car.automatic = false
	Input.action_press("clutch_pedal")
	await _step(CLUTCH_HOLD_FRAMES)
	var pedal := _car.clutch_pedal
	var hint_while_held := _hint.visible and _hint.text == LicenceManager.GATE_HINT
	Input.action_release("clutch_pedal")
	await _step(CLUTCH_HOLD_FRAMES)
	var pedal_after := _car.clutch_pedal
	if licensed:
		_check(pedal >= 0.99 and pedal_after == 0.0 and not hint_while_held, "%s: the clutch key moves the pedal (%.2f held, %.2f let go), no hint" % [label, pedal, pedal_after])
	else:
		_check(pedal == 0.0 and pedal_after == 0.0 and hint_while_held, "%s: the clutch key does nothing (%.2f held) and the hint says '%s'" % [label, pedal, _hint.text])
	_car.automatic = true

	var before := [_car.tcs_on, _car.abs_on, _car.sc_on]
	await _tap("tcs_toggle")
	await _tap("abs_toggle")
	await _tap("sc_toggle")
	var after := [_car.tcs_on, _car.abs_on, _car.sc_on]
	var flipped: bool = after[0] != before[0] and after[1] != before[1] and after[2] != before[2]
	var stayed: bool = after == before
	if licensed:
		_check(flipped, "%s: T, G and K flip the aids (%s -> %s)" % [label, before, after])
		# Back on: the certified state.
		await _tap("tcs_toggle")
		await _tap("abs_toggle")
		await _tap("sc_toggle")
		_check(_car.tcs_on and _car.abs_on and _car.sc_on, "%s: ... and back on" % label)
	else:
		_check(stayed, "%s: T, G and K are refused, the aids stay (%s)" % [label, after])
	await _step(int(LicenceManager.GATE_HINT_TIME * Engine.physics_ticks_per_second) + 5)
	_check(not _hint.visible, "%s: the hint is down again %.1f s later" % [label, LicenceManager.GATE_HINT_TIME])


# =============================================================================
#  The book and the keys
# =============================================================================

## L opens the book (the card, listing the ladder), the number keys are the
## book's while it is open (3 starts no handling test), L closes it and the
## keys are the missions' again (3 starts one; Esc aborts it).
func _check_book_and_keys() -> void:
	await _tap(LicenceManager.ACTION_BOOK)
	_check(_manager.book_open and _card.visible and _card.text.begins_with("LICENCE BOOK") and _card.text.contains("UNLICENSED"), "L opens the licence book on the card ('%s')" % _card.text.get_slice("\n", 0))
	_check(_card.text.contains("L0 CITIZEN") and _card.text.contains("L1 FACTORY ENTRY") and _card.text.contains("RANKS") and _card.text.contains("THE GATE") and _card.text.contains("SKID PAD [ - ]"), "the book lists the ladder, the record, the ranks and the gate")
	_check(_missions.start_keys_locked, "the book holds the number keys")
	await _tap(&"test_3")
	_check(not _missions.is_running() and _missions.state == MissionManager.State.IDLE and not _manager.is_running(), "3 starts no handling test while the book is open")
	await _tap(LicenceManager.ACTION_BOOK)
	_check(not _manager.book_open and not _card.visible and not _missions.start_keys_locked, "L closes the book and frees the keys")
	await _tap(&"test_3")
	_check(_missions.is_running() and _missions.selected_index == 2, "3 starts the 360 with the book closed, as ever")
	await _tap(LicenceManager.ACTION_BOOK)
	_check(not _manager.book_open, "L does not open the book over a running mission")
	await _tap(&"abort_mission")
	_check(not _missions.is_running(), "Esc aborts it")
	await _step(int(MissionManager.ABORT_BANNER_TIME * Engine.physics_ticks_per_second) + 5)
	_check(_missions.state == MissionManager.State.IDLE, "the mission's banner times out")


# =============================================================================
#  The sitting
# =============================================================================

## Drives the manager's sitting with pilots, one per element as the manager
## moves on, until the manager is out of RUNNING. Returns the verdicts the
## manager recorded, by element name, and what was seen on the way.
func _drive_sitting(pilot_for: Callable) -> Dictionary:
	var verdicts := {}
	var seen := {"card_up_for_quiz": false, "clutch_moved_on_hill": false, "manual_on_hill": false, "line_ok": true, "card_down_off_quiz": true, "bad_line": ""}
	var pilot: LicenceExams = null
	var pilot_index := -1
	var frames := 0
	var element_frames := 0
	var delta := 1.0 / Engine.physics_ticks_per_second
	while _manager.is_running() and frames < MAX_ELEMENT_FRAMES * 7:
		if _manager.element_index != pilot_index:
			if pilot != null:
				# Hands off the keys for a frame between elements, as a driver
				# has them: a key held over from the last element is no fresh
				# press on the next (reverse is a fresh press of the brake key).
				pilot.abort()
				await physics_frame
				frames += 1
				var previous: Dictionary = _manager.last_result
				verdicts[previous.name] = previous
			pilot_index = _manager.element_index
			element_frames = 0
			var element: Dictionary = _manager.elements[pilot_index]
			var scripted: Dictionary = pilot_for.call(element)
			pilot = LicenceExams.begin(scripted, _car, _pad, true, false)
		pilot.tick(delta)
		await physics_frame
		frames += 1
		element_frames += 1
		if element_frames > MAX_ELEMENT_FRAMES:
			break
		if not _manager.is_running():
			break
		# The line is the manager's current element's (it may have moved on
		# this frame; the pilot follows next frame).
		var element: Dictionary = _manager.elements[_manager.element_index]
		var line := _mission_label.text
		if not (line.contains("ELEMENT %d/%d" % [_manager.element_index + 1, _manager.elements.size()]) and line.contains(element.title)):
			seen.line_ok = false
			seen.bad_line = "%s (element %d)" % [line.get_slice("\n", 0), _manager.element_index + 1]
		if element.kind == LicenceExams.KIND_QUIZ:
			seen.card_up_for_quiz = seen.card_up_for_quiz or (_card.visible and _card.text.begins_with("THEORY"))
		else:
			seen.card_down_off_quiz = seen.card_down_off_quiz and not _card.visible
		if element.kind == LicenceExams.KIND_HILL_START:
			seen.clutch_moved_on_hill = seen.clutch_moved_on_hill or _car.clutch_pedal > 0.5
			seen.manual_on_hill = seen.manual_on_hill or not _car.automatic
	if pilot != null:
		pilot.abort()
	if not _manager.last_result.is_empty():
		verdicts[_manager.last_result.name] = _manager.last_result
	seen["frames"] = frames
	seen["verdicts"] = verdicts
	return seen


func _sit_l0() -> void:
	print("-- the L0 sitting")
	await _tap(LicenceManager.ACTION_BOOK)
	# The sitting is sat on the debug car's full tank, handed by the test
	# before the key: an element's start resets the car and the reset keeps
	# the fuel (the user's report, 2026-09-22 12:55), so the elements after
	# the first run on what the ones before them left - a sitting does not
	# refuel between elements, that is the game's rule; the hill start's
	# numbers are read on that tank.
	_fresh_fuel(_car)
	await _tap(LicenceManager.ACTION_SIT_L0)
	_check(_manager.is_running() and _manager.exam == LicenceExams.EXAM_L0 and _manager.element_index == 0 and not _manager.book_open, "1 in the book starts the L0 sitting at the theory, the book closes")
	_check(_missions.start_keys_locked and not _missions.is_running(), "the number keys are the sitting's (the theory's answers), no handling test starts")
	_check(_card.visible and _card.text.begins_with("THEORY  1/%d" % LicenceExams.quiz_questions().size()), "the first question card is up ('%s')" % _card.text.get_slice("\n", 0))
	_check(not _manager.run.scripted, "the manager's run is a human run")
	var seen := await _drive_sitting(func(element: Dictionary) -> Dictionary: return element)
	var verdicts: Dictionary = seen.verdicts
	for name: String in verdicts:
		for line in HandlingTests.format_result(verdicts[name]):
			print("  ", line)
	_check(not _manager.is_running() and _manager.state == LicenceManager.State.RESULT, "the sitting ends (%d frames)" % seen.frames)
	_check(verdicts.size() == 7 and _manager.last_sitting_passed and _finished_signals == 1, "all seven elements were sat and judged, the sitting PASSED, sitting_finished fired once (%d verdicts)" % verdicts.size())
	var all_passed := verdicts.size() == 7
	for name: String in verdicts:
		all_passed = all_passed and verdicts[name].passed
	_check(all_passed, "every element PASSED on its own checks")
	_check(seen.line_ok, "the HUD showed 'ELEMENT n/7' and the element's title throughout%s" % ("" if seen.line_ok else " (saw '%s')" % seen.bad_line))
	_check(seen.card_up_for_quiz and seen.card_down_off_quiz, "the theory's cards were up, and no card on the practical elements")
	_check(seen.manual_on_hill and seen.clutch_moved_on_hill, "during the sitting the gate allowed the clutch: the hill start was sat in manual on the pedal (dual controls)")
	_check(_banner.visible and _banner.text == "PASSED  L0 EXAM", "banner says PASSED ('%s')" % _banner.text)
	_check(_manager.level() == LicenceExams.LICENCE_L0 and _manager.has_passed(LicenceExams.EXAM_L0) and _levels_announced == [LicenceExams.LICENCE_L0], "L0 is granted and announced (%s)" % LicenceExams.licence_title(_manager.level()))

	# The measured verdicts, element by element.
	if verdicts.size() == 7:
		var park: Dictionary = verdicts["PARALLEL_PARK"].metrics
		_check(park.margin_m >= 0.0 and park.side_clearance_m >= 0.0 and park.end_clearance_m >= 0.0 and park.reversed_m >= LicenceExams.PARALLEL_MIN_REVERSE_M and park.cones_hit == 0 and park.heading_error_deg <= LicenceExams.PARK_HEADING_TOLERANCE_DEG,
			"parallel park: the footprint is inside the lines, %.2f m to the sides, %.2f m to the ends, %.1f deg off, reversed %.1f m, no cone down" % [park.side_clearance_m, park.end_clearance_m, park.heading_error_deg, park.reversed_m])
		var bay: Dictionary = verdicts["BAY_PARK"].metrics
		_check(bay.margin_m >= 0.0 and bay.cones_hit == 0 and bay.heading_error_deg <= LicenceExams.PARK_HEADING_TOLERANCE_DEG, "bay park: inside the lines by %.2f m, %.1f deg off, no cone down" % [bay.margin_m, bay.heading_error_deg])
		var hill: Dictionary = verdicts["HILL_START"].metrics
		_check(hill.roll_back_m >= 0.0 and hill.roll_back_m <= LicenceExams.HILL_ROLL_BACK_TOLERANCE and not hill.stalled and hill.crest_speed_ms >= LicenceExams.HILL_MIN_CREST_SPEED,
			"hill start: rolled back %.1f cm of the %.0f allowed, no stall, over the crest at %.1f m/s" % [hill.roll_back_m * 100.0, LicenceExams.HILL_ROLL_BACK_TOLERANCE * 100.0, hill.crest_speed_ms])
		var turn: Dictionary = verdicts["TURN_IN_ROAD"].metrics
		_check(turn.direction_changes >= 2 and turn.direction_changes <= 4 and turn.worst_excursion_m == 0.0 and turn.reversed_m >= LicenceExams.TURN_MIN_REVERSE_M and turn.heading_error_deg <= LicenceExams.TURN_HEADING_TOLERANCE_DEG,
			"turn in the road: %d direction changes, never outside the lane, %.1f m reversed, %.1f deg from facing back" % [turn.direction_changes, turn.reversed_m, turn.heading_error_deg])
		var reversing: Dictionary = verdicts["REVERSING_COURSE"].metrics
		_check(reversing.reversed_m >= LicenceExams.REVERSE_COURSE_MIN_DISTANCE and reversing.worst_excursion_m == 0.0 and reversing.cones_hit == 0 and reversing.end_box_margin_m >= 0.0,
			"reversing course: %.1f m between the lines, no cone down, inside the end box by %.2f m" % [reversing.reversed_m, reversing.end_box_margin_m])
		var stop: Dictionary = verdicts["EMERGENCY_STOP"].metrics
		_check(stop.cue_speed_kmh >= LicenceExams.EMERGENCY_MIN_SPEED * 3.6 and stop.zone_margin_m >= 0.0 and stop.cones_hit == 0,
			"emergency stop: %.1f km/h at the bar, stopped %.1f m on, inside the zone by %.2f m" % [stop.cue_speed_kmh, stop.stop_distance_m, stop.zone_margin_m])
		var quiz: Dictionary = verdicts["THEORY_QUIZ"].metrics
		_check(quiz.answered == "%d/%d" % [LicenceExams.quiz_questions().size(), LicenceExams.quiz_questions().size()], "theory: every question answered (%s)" % quiz.answered)
	await _tap(&"abort_mission")
	_check(_manager.state == LicenceManager.State.IDLE and not _banner.visible and not _missions.start_keys_locked, "Esc closes the banner, the keys are free again")


## A re-sit that stalls on the hill: the pilot dumps the clutch on the locked
## rear axle with the throttle open. The record is complete (L0 was just
## granted), so this is a practice run from the theory; the sitting fails at
## once at element 4/7, the three before it passed, the licence stays.
func _sit_stalling_retake() -> void:
	print("-- a retake that stalls on the hill")
	await _tap(LicenceManager.ACTION_BOOK)
	_fresh_fuel(_car)
	await _tap(LicenceManager.ACTION_SIT_L0)
	# was -> "a retake is a new sitting from the theory": the user's verdict,
	# 2026-09-22 14:56 + 15:02 - a sitting resumes at the first element not
	# yet passed; only a complete record sits again from the theory.
	_check(_manager.is_running() and _manager.element_index == 0 and _manager.practice, "with a complete record the re-sit is a practice run from the theory")
	var seen := await _drive_sitting(func(element: Dictionary) -> Dictionary:
		if element.kind != LicenceExams.KIND_HILL_START:
			return element
		var stalling := element.duplicate(true)
		# The same procedure up to the revs, then the clutch key alone let go:
		# the pedal comes up on the handbrake's locked axle.
		var steps: Array = stalling.steps
		steps[5] = {"when": {"after": LicenceExams.HILL_REV_TIME}, "release": [&"clutch_pedal"]}
		steps[6] = {"when": {"after": 3.0}, "release": [&"accelerate", &"handbrake"]}
		return stalling
	)
	var verdicts: Dictionary = seen.verdicts
	for name: String in verdicts:
		for line in HandlingTests.format_result(verdicts[name]):
			print("  ", line)
	var hill: Dictionary = verdicts.get("HILL_START", {"passed": true, "metrics": {}, "checks": []})
	var stall_check_failed := false
	for check: Dictionary in hill.checks:
		if check.label == "no stall" and not check.passed:
			stall_check_failed = true
	_check(_manager.state == LicenceManager.State.RESULT and not _manager.last_sitting_passed and _manager.element_index == 3, "the sitting FAILED at element 4/7 (index %d)" % _manager.element_index)
	_check(verdicts.size() == 4 and verdicts["THEORY_QUIZ"].passed and verdicts["PARALLEL_PARK"].passed and verdicts["BAY_PARK"].passed and not hill.passed, "the three elements before it passed, the hill start did not, nothing after it was sat")
	_check(stall_check_failed and hill.metrics.get("stalled", false) and not _car.engine_running, "the hill start failed through the stall check: the engine stalled (%s)" % str(hill.metrics.get("stalled")))
	_check(_banner.visible and _banner.text == "FAILED  L0 EXAM" and _manager.level() == LicenceExams.LICENCE_L0, "banner says FAILED, the licence held stays L0")
	await _tap(&"abort_mission")


## A retake with the first question answered wrong: failed at once, at the
## theory, no element driven.
func _sit_wrong_answer() -> void:
	print("-- a retake with a wrong answer")
	await _tap(LicenceManager.ACTION_BOOK)
	_fresh_fuel(_car)
	await _tap(LicenceManager.ACTION_SIT_L0)
	var first: Dictionary = LicenceExams.quiz_questions()[0]
	var wrong: int = 1 if first.correct != 1 else 2
	var start := _car.global_position
	await _tap(LicenceExams.ANSWER_ACTIONS[wrong - 1])
	await _step(int(0.5 * Engine.physics_ticks_per_second) + 5)
	var verdict := _manager.last_result
	_check(_manager.state == LicenceManager.State.RESULT and not _manager.last_sitting_passed and _manager.element_index == 0 and verdict.get("name", "") == "THEORY_QUIZ" and not verdict.get("passed", true),
		"answering %d to question 1 (the answer is %d) fails the sitting at once at 1/7" % [wrong, first.correct])
	_check(_car.global_position.distance_to(start) < 0.01 and _banner.text == "FAILED  L0 EXAM" and not _card.visible, "no wheel turned, the banner says FAILED, the card is down")
	await _tap(&"abort_mission")


## A hill start with the handbrake let go before the clutch bites (the pedal
## still on the floor, the revs up): the car rolls back down the 8 % freely,
## past the tolerance in about a second, no stall (the clutch is open). Sat
## directly (the element alone, scripted, the driver licensed by now): the
## roll-back check fails on the measured number, and the element ends the
## moment it does.
func _check_roll_back_failure() -> void:
	print("-- a hill start with the handbrake let go before the bite")
	var element := LicenceExams.hill_start_element()
	var steps: Array = element.steps
	steps[5] = {"when": {"after": LicenceExams.HILL_REV_TIME}, "release": [&"handbrake"]}
	steps[6] = {"when": {"after": 2.0}, "release": [&"accelerate", &"clutch_pedal"]}
	var outcome := await _play_element(element)
	for line in HandlingTests.format_result(outcome):
		print("  ", line)
	var roll_back: float = outcome.metrics.roll_back_m
	var roll_check_failed := false
	for check: Dictionary in outcome.checks:
		if check.label.begins_with("rolled back") and not check.passed:
			roll_check_failed = true
	_check(
		not outcome.passed and roll_check_failed and roll_back > LicenceExams.HILL_ROLL_BACK_TOLERANCE and not outcome.metrics.stalled and outcome.metrics.time_s < 12.0,
		"rolled back %.1f cm, past the %.0f allowed: FAILED through the roll-back check, no stall, the element over the moment it rolled too far (%.1f s)" % [roll_back * 100.0, LicenceExams.HILL_ROLL_BACK_TOLERANCE * 100.0, outcome.metrics.time_s],
	)


## One element on its own, scripted, to its verdict - on the full tank, handed
## before the element's own reset (which keeps the tank it finds).
func _play_element(element: Dictionary) -> Dictionary:
	_fresh_fuel(_car)
	var run := LicenceExams.begin(element, _car, _pad, true)
	var delta := 1.0 / Engine.physics_ticks_per_second
	var frames := 0
	while not run.finished and frames < MAX_ELEMENT_FRAMES:
		run.tick(delta)
		await physics_frame
		frames += 1
	if not run.finished:
		run.abort()
	return run.result()


# =============================================================================
#  L1
# =============================================================================

func _sit_skid_pad() -> void:
	print("-- the skid pad test")
	await _tap(LicenceManager.ACTION_BOOK)
	_fresh_fuel(_car)
	await _tap(LicenceManager.ACTION_SIT_SKID_PAD)
	_check(_manager.is_running() and _manager.exam == LicenceExams.EXAM_SKID_PAD and _manager.elements.size() == 1, "2 in the book starts the skid pad test")
	var seen := await _drive_sitting(func(element: Dictionary) -> Dictionary: return element)
	var verdicts: Dictionary = seen.verdicts
	for name: String in verdicts:
		for line in HandlingTests.format_result(verdicts[name]):
			print("  ", line)
	var verdict: Dictionary = verdicts.get(LicenceExams.EXAM_SKID_PAD, {"passed": false, "metrics": {}})
	_check(_manager.state == LicenceManager.State.RESULT and _manager.last_sitting_passed and verdict.passed, "the skid pad test PASSED (%d frames)" % seen.frames)
	if not verdict.metrics.is_empty():
		var metrics: Dictionary = verdict.metrics
		_check(metrics.laps >= LicenceExams.SKID_PAD_LAPS and metrics.worst_excursion_m == 0.0 and metrics.cones_hit == 0 and metrics.laps_time_s > 0.0 and metrics.laps_time_s <= LicenceExams.SKID_PAD_TIME_LIMIT,
			"skid pad: %.2f laps in %.1f s, every wheel between the rings, no cone down, %.0f km/h at most" % [metrics.laps, metrics.laps_time_s, metrics.peak_speed_kmh])
	_check(_manager.has_passed(LicenceExams.EXAM_SKID_PAD) and _manager.level() == LicenceExams.LICENCE_L0 and _banner.text == "PASSED  SKID PAD TEST", "the pass is recorded; without the five handling tests the licence is still L0")
	await _tap(&"abort_mission")


## The five handling tests' passes come in from the MissionManager's signal,
## a FAILED one is not recorded, and L1 is granted on the last of the seven.
func _check_l1_grant() -> void:
	_missions.mission_finished.emit(0, {"name": "SLALOM_TEST", "passed": false, "metrics": {}, "checks": []})
	_check(not _manager.has_passed("SLALOM_TEST") and _manager.level() == LicenceExams.LICENCE_L0, "a FAILED handling test is not recorded")
	var five := LicenceExams.L1_HANDLING_TESTS
	var levels_before_last: Array[int] = []
	for i in five.size():
		_missions.mission_finished.emit(i, {"name": five[i], "passed": true, "metrics": {}, "checks": []})
		if i < five.size() - 1:
			levels_before_last.append(_manager.level())
	_check(levels_before_last == [0, 0, 0, 0], "four of the five recorded, still L0")
	_check(_manager.level() == LicenceExams.LICENCE_L1 and _levels_announced == [LicenceExams.LICENCE_L0, LicenceExams.LICENCE_L1], "the fifth makes seven of seven: L1 FACTORY ENTRY, announced once")
	await _tap(LicenceManager.ACTION_BOOK)
	_check(_card.text.contains("held:  L1 FACTORY ENTRY") and _card.text.contains("SKID PAD [PASSED]") and _card.text.contains("SLALOM [PASSED]"), "the book shows L1 held and the passes ticked")
	await _tap(LicenceManager.ACTION_BOOK)


# =============================================================================
#  The store
# =============================================================================

## The record on a file of the test's own: to the bit, beside the rest, a
## level the passes do not earn brought down, an old file untouched, and the
## refusals.
func _check_store() -> void:
	DirAccess.make_dir_recursive_absolute(_store_dir)
	if FileAccess.file_exists(_store_file):
		DirAccess.remove_absolute(_store_file)
	var car_id := ArcadeCar.CAR_ID
	var new_car := OdometerStore.load_licence(car_id, _store_file)
	# An old file: an entry with everything but the licence.
	OdometerStore.save_car(car_id, 4321.5, 12.5, _store_file, {"gearbox_mode": "eco"}, {"charge": 0.5}, {"engine": 0.25})
	var old_text := FileAccess.get_file_as_string(_store_file)
	var old_car := OdometerStore.load_licence(car_id, _store_file)
	var record := {"level": LicenceExams.LICENCE_L0, "passed": [LicenceExams.EXAM_L0, "SPIN_180", "SPIN_180"]}
	OdometerStore.save_licence(car_id, record, _store_file)
	var after_licence := FileAccess.get_file_as_string(_store_file)
	# A car's save (the metres) after it leaves the licence where it is.
	OdometerStore.save_car(car_id, 4400.0, NAN, _store_file)
	var written: Variant = JSON.parse_string(FileAccess.get_file_as_string(_store_file))
	var entry: Dictionary = written["cars"][car_id] if written is Dictionary else {}
	var back := OdometerStore.load_licence(car_id, _store_file)
	var unknown := OdometerStore.load_licence("no_such_car", _store_file)
	var to_the_bit: bool = back.level == LicenceExams.LICENCE_L0 and back.passed == [LicenceExams.EXAM_L0, "SPIN_180"] and (back.problems as Array).is_empty() and typeof(back.level) == TYPE_INT
	var beside: bool = entry.get("odometer_m") == 4400.0 and entry.get("fuel_l") == 12.5 and entry.get("wear", {}).get("engine") == 0.25 and entry.get("licence", {}).get("level") == 0 and written.get("version") == OdometerStore.VERSION and OdometerStore.VERSION == 1
	var defaults_back := true
	# was -> the passes alone: the elements passed are the record's third
	# field (the user's verdict, 2026-09-22 14:56 + 15:02), empty for a new car.
	for licence: Dictionary in [new_car, old_car, unknown]:
		defaults_back = defaults_back and licence.level == LicenceExams.LICENCE_NONE and (licence.passed as Array).is_empty() and (licence.elements as Array).is_empty() and (licence.problems as Array).is_empty()
	var old_had_no_licence: bool = not (JSON.parse_string(old_text) as Dictionary)["cars"][car_id].has("licence")
	_check(
		to_the_bit and beside and defaults_back and old_had_no_licence and after_licence != old_text,
		"store: the record comes back to the bit (level %d, %s, a duplicate pass dropped) beside the odometer, the fuel and the wear, version still %d; a save of the metres leaves it; a car, a file and an old file's entry are unlicensed, nothing wrong; the old file had no licence object until it was handed one" % [back.level, back.passed, OdometerStore.VERSION],
	)
	# A level the passes do not earn is brought down, in and out.
	OdometerStore.save_licence(car_id, {"level": LicenceExams.LICENCE_L1, "passed": [LicenceExams.EXAM_L0]}, _store_file)
	var brought_down := OdometerStore.load_licence(car_id, _store_file)
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(_store_file))
	_check(brought_down.level == LicenceExams.LICENCE_L0 and raw["cars"][car_id]["licence"]["level"] == 0, "store: the level written and read is what the passes earn, whatever it was handed (L1 with the sitting alone -> L0)")
	# The whole L1 record round-trips too, and the manager's own record
	# (the one it holds now, L1) does.
	OdometerStore.save_licence(car_id, _manager.licence, _store_file)
	var manager_back := OdometerStore.load_licence(car_id, _store_file)
	_check(manager_back.level == LicenceExams.LICENCE_L1 and manager_back.passed.size() == 7 and (manager_back.problems as Array).is_empty(), "store: the manager's L1 record survives a save and a load (%d passes)" % manager_back.passed.size())
	# Refusals: what is no level or no list of names, and a bad field beside a
	# good one.
	var not_levels: Array = [NAN, INF, -2, 2, 0.5, "L0", null, true, [0]]
	var refused := 0
	for value: Variant in not_levels:
		if OdometerStore.licence_problem("level", value) != "":
			refused += 1
	var not_lists: Array = ["L0_CITIZEN", 0, null, [1, 2], ["L0_CITIZEN", 3]]
	for value: Variant in not_lists:
		if OdometerStore.licence_problem("passed", value) != "":
			refused += 1
	var accepted := OdometerStore.licence_problem("level", -1) == "" and OdometerStore.licence_problem("level", 1.0) == "" and OdometerStore.licence_problem("passed", []) == "" and OdometerStore.licence_problem("passed", ["X"]) == "" and OdometerStore.licence_problem("rank", 0) != ""
	var stored := JSON.parse_string(FileAccess.get_file_as_string(_store_file)) as Dictionary
	stored["cars"]["part_bad"] = {"licence": {"level": 7, "passed": [LicenceExams.EXAM_L0]}}
	var file := FileAccess.open(_store_file, FileAccess.WRITE)
	file.store_string(JSON.stringify(stored))
	file.close()
	var part_bad := OdometerStore.load_licence("part_bad", _store_file)
	_check(
		refused == not_levels.size() + not_lists.size() and accepted and part_bad.level == LicenceExams.LICENCE_L0 and part_bad.passed == [LicenceExams.EXAM_L0] and (part_bad.problems as Array).size() == 1 and (part_bad.problems as Array)[0].contains("part_bad") and (part_bad.problems as Array)[0].contains("level"),
		# was -> "no third field": the elements are the third (the user's
		# verdict, 2026-09-22 14:56 + 15:02); a rank is no fourth.
		"store: %d non-levels and non-lists refused with a reason, the levels -1 .. 1 and lists of names accepted, no fourth field; a level of 7 beside a good list reads as the list's L0 with one problem naming the car and the field" % refused,
	)


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
	for action in LicenceExams.ACTIONS:
		Input.action_release(action)
	if _failures == 0:
		print("LICENCE TEST PASSED")
	else:
		print("LICENCE TEST FAILED: %d check(s) failed" % _failures)
	quit(1 if _failures > 0 else 0)


## And the certified fresh car's tank: full, its mass with it.
# was the reset's own (reset_to filled the tank until 3Y) -> set by hand: a
# reset keeps the fuel (the user's report, 2026-09-22 12:55: "resetting the
# car MUST NOT refuel ... tests must not affect the game"), and every check
# here was measured on the full tank - the kerb mass everything was tuned
# with. What reset_to set until then, and what HandlingTests._start sets for
# a certified run. Called before every reset here: the reset stands the car
# on its springs by its mass (_settle_suspension reads total_mass()) and
# keeps the tank it finds. A check that wants a dry tank empties it after.
func _fresh_fuel(car: ArcadeCar) -> void:
	car.fuel_l = ArcadeCar.FUEL_TANK_CAPACITY_L
	car.fuel_mass = car.fuel_l * ArcadeCar.FUEL_DENSITY
