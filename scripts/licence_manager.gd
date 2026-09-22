class_name LicenceManager
extends Node
## The licence ladder with a human at the wheel: the LICENCE BOOK (key L), the
## exams it starts (1 sits the L0 exam, 2 the skid pad test while the book is
## open), the gate the licence opens, and the licence record itself.
##
## The exams (elements, checks, the scripted driver) are the data in
## scripts/licence_exams.gd, run with the scripted driver switched off: the
## human's driving through the same checks. This node only picks an exam,
## moves it through idle -> running -> result shown -> idle, one element after
## the other (any element failed ends the sitting at once: the rigor rule;
## the elements passed before it are kept, see THE RECORD), and hands the
## HUD its strings: the mission line for the live element, the banner for
## PASSED / FAILED, the licence card for the book and for the theory's
## question cards. It never presses or releases an input action
## (MissionManager's pattern; the theory's digit keys are read by the run).
##
## THE GATE (the keystone: the licence gives the clutch key and the aid
## switches a purpose in the world): the car asks this node, allows(action),
## before the clutch pedal key and the TCS / ABS / SC switches do anything
## (ArcadeCar.licence_gate, wired up in _ready). Without L0 they are refused
## and the HUD shows a hint by the aid lamps; during a sitting they are
## allowed (the instructor's dual-control car, so the hill start can be sat);
## from L0 on they are allowed for good. Honest and reversible: a car without
## a gate (null) allows everything, which is every test scene and every
## certified run.
##
## THE RECORD: per car, riding the car's entry in cars.json beside the
## odometer, the fuel, the dashboard, the battery and the wear
## (OdometerStore, "licence": the level, the exams passed and the L0
## elements passed), behind the same switch as the rest of the store: the
## running game keeps it, the headless suite writes nothing. THE L0 SITTING
## REMEMBERS: every element passed is put in the record the moment it is
## (record_element, saved at once), so it survives a failed later element,
## an abort and the process ending; the next sitting begins at the first
## element not yet passed, in the sitting's order (a passed theory is never
## retaken), and the seventh element passed grants L0 and records the sitting
## itself (EXAM_L0). A complete record sits the whole exam again from the
## theory as a PRACTICE RUN: nothing a practice run does changes the record
## (a pass is recorded once and never removed). L1 is granted the moment the
## record holds every one of its requirements: L0, a PASSED on each of the
## five handling tests (heard from the MissionManager's mission_finished:
## free training on keys 1-5 is exactly what counts) and the skid pad test.
# was one sitting, all or nothing, a retake from the theory -> per element:
# the user's verdict, 2026-09-22 14:56 + 15:02 ("it's annoying that if i
# fail any of the L0 tests i need to get back to theory and not retry the
# test i failed, it's like nothing remembers i took the tests"). The
# all-or-nothing rule dated from L0 being two exams, theory and practice,
# each with its own retake; fused into one sitting it dragged a passed
# theory under every failed practice element.

signal sitting_started(exam: String)
signal sitting_finished(exam: String, passed: bool)
signal sitting_aborted(exam: String)
signal licence_changed(level: int)

enum State { IDLE, RUNNING, RESULT }

## The book's key, and the two exam keys while it is open (the mission keys,
## taken over: MissionManager.start_keys_locked).
const ACTION_BOOK := &"licence_book"
const ACTION_SIT_L0 := &"test_1"
const ACTION_SIT_SKID_PAD := &"test_2"

## How long the PASSED / FAILED banner stays up unless dismissed [s], the
## shorter ABORTED one, and the gate's hint by the aid lamps.
const RESULT_BANNER_TIME := 8.0
const ABORT_BANNER_TIME := 2.0
const GATE_HINT_TIME := 1.5

## What a refused clutch key or aid switch says, by the aid lamps.
const GATE_HINT := "LICENSED ONLY — L  licence book"

const LINE_COLOR_RUNNING := Color(0.55, 0.85, 1.0, 1)
const BANNER_COLOR_PASSED := Color(0.35, 1.0, 0.45, 1)
const BANNER_COLOR_FAILED := Color(1.0, 0.3, 0.2, 1)
const BANNER_COLOR_ABORTED := Color(1.0, 0.75, 0.25, 1)

@export var car: ArcadeCar
@export var pad: TestPad
@export var hud: HUD
@export var missions: MissionManager

var state := State.IDLE
var book_open := false

## The exam being sat, or the last one: LicenceExams.EXAM_L0 or EXAM_SKID_PAD.
var exam := ""

## The elements of the exam being sat, in order, and which one is on.
var elements: Array[Dictionary] = []
var element_index := -1

## The element's run in progress, or the last one. Null before the first start.
var run: LicenceExams

## Verdict of the last element that ended ({ name, passed, metrics, checks }):
## the failing one of a failed sitting, the last one of a passed sitting.
## Empty while a sitting is on and after an abort.
var last_result: Dictionary = {}

## Whether the last sitting that ended passed.
var last_sitting_passed := false

## Whether the sitting on (or the last one) is a practice run: the L0 exam
## sat again on a complete record. Nothing a practice run does changes the
## record.
var practice := false

## The licence record: {"level": int, "passed": Array[String], "elements":
## Array[String]} (the store's shape, OdometerStore.LICENCE_DEFAULTS: the
## level held, the exams passed, the L0 sitting's elements passed). Loaded
## once, saved on every change where the store is on.
var licence: Dictionary = {}

var _store_kept := false

## The file the record rides in: the store's (OdometerStore.PATH); a test
## hands one of its own, with _store_kept, to see a record survive a process.
var _store_path := OdometerStore.PATH
var _banner_left := 0.0
var _hint_left := 0.0


func _ready() -> void:
	_store_kept = OdometerStore.enabled()
	licence = OdometerStore.LICENCE_DEFAULTS.duplicate(true)
	if _store_kept:
		_load_licence()
	if car:
		car.licence_gate = self
	if missions:
		missions.mission_finished.connect(_on_mission_finished)
	if hud:
		hud.set_gate_hint("")


## The record as the store has it for this car in _store_path (see
## OdometerStore.load_licence); a field in there that is none of its own is
## reported and read as its default, one that is not there is its default.
func _load_licence() -> void:
	var stored := OdometerStore.load_licence(ArcadeCar.CAR_ID, _store_path)
	for problem: String in stored.problems:
		push_error(problem)
	licence = {"level": stored.level, "passed": stored.passed, "elements": stored.elements}


func _physics_process(delta: float) -> void:
	if _hint_left > 0.0:
		_hint_left -= delta
		if _hint_left <= 0.0 and hud:
			hud.set_gate_hint("")

	if state == State.RUNNING:
		# R also resets the car (the car sees to that itself).
		if Input.is_action_just_pressed("abort_mission") or Input.is_action_just_pressed("reset_car"):
			abort_sitting()
			_sync_key_lock()
			return
		run.tick(delta)
		if run.finished:
			_element_done()
		else:
			_show_progress()
		_sync_key_lock()
		return

	# The book: L opens and closes it, never over a mission's run.
	if Input.is_action_just_pressed(ACTION_BOOK) and not (missions and missions.is_running()):
		if book_open:
			close_book()
		else:
			open_book()
	if book_open:
		if Input.is_action_just_pressed(ACTION_SIT_L0):
			start_l0_sitting()
		elif Input.is_action_just_pressed(ACTION_SIT_SKID_PAD):
			start_skid_pad_test()
		elif Input.is_action_just_pressed("abort_mission"):
			close_book()
	elif state == State.RESULT:
		_banner_left -= delta
		if Input.is_action_just_pressed(ACTION_SIT_L0):
			dismiss_banner()
			if exam == LicenceExams.EXAM_L0:
				start_l0_sitting()
			else:
				start_skid_pad_test()
		elif _banner_left <= 0.0 or Input.is_action_just_pressed("abort_mission"):
			dismiss_banner()
	_sync_key_lock()


## The mission keys are this node's while the book is open or an exam is on
## or its verdict is up.
func _sync_key_lock() -> void:
	if missions:
		missions.start_keys_locked = book_open or state != State.IDLE


# =============================================================================
#  The gate
# =============================================================================

## Whether the driver may work `action` (the clutch pedal key or an aid
## switch) right now: yes with L0 or better, yes during a sitting (the
## instructor's dual controls), no otherwise - and the HUD says so.
func allows(_action: StringName) -> bool:
	if level() >= LicenceExams.LICENCE_L0 or state == State.RUNNING:
		return true
	_hint_left = GATE_HINT_TIME
	if hud:
		hud.set_gate_hint(GATE_HINT)
	return false


## The licence held: LicenceExams.LICENCE_NONE, LICENCE_L0 or LICENCE_L1.
func level() -> int:
	return licence.get("level", LicenceExams.LICENCE_NONE)


## Whether `exam` (an exam name: LicenceExams.EXAM_L0, EXAM_SKID_PAD, a
## handling test's name) is in the record.
func has_passed(exam_name: String) -> bool:
	return (licence.get("passed", []) as Array).has(exam_name)


## Whether the L0 sitting's element `element_name` (LicenceExams.l0_sitting()
## names) is in the record.
func has_passed_element(element_name: String) -> bool:
	return (licence.get("elements", []) as Array).has(element_name)


# =============================================================================
#  Run state
# =============================================================================

## Sits the L0 exam from the first element the record does not hold yet
## (the theory, then the six practical elements, in the sitting's order;
## LicenceExams.l0_resume_index): a passed element is never sat again. With
## every element in the record it is a practice run from the theory.
## Returns false while a sitting is on or a mission runs.
# was every sitting from the theory, all or nothing -> resumed: the user's
# verdict, 2026-09-22 14:56 + 15:02.
func start_l0_sitting() -> bool:
	var elements_passed: Array = licence.get("elements", [])
	var complete := LicenceExams.sitting_complete(elements_passed)
	return _start_exam(LicenceExams.EXAM_L0, LicenceExams.l0_sitting(), LicenceExams.l0_resume_index(elements_passed), complete)


## Sits the skid pad test (one element).
func start_skid_pad_test() -> bool:
	return _start_exam(LicenceExams.EXAM_SKID_PAD, [LicenceExams.skid_pad_test()])


func _start_exam(exam_name: String, exam_elements: Array[Dictionary], first := 0, as_practice := false) -> bool:
	if state == State.RUNNING or (missions and missions.is_running()) or exam_elements.is_empty():
		return false
	if state == State.RESULT:
		dismiss_banner()
	if book_open:
		close_book()
	exam = exam_name
	elements = exam_elements
	practice = as_practice
	last_result = {}
	last_sitting_passed = false
	state = State.RUNNING
	_start_element(first)
	sitting_started.emit(exam)
	return true


func _start_element(index: int) -> void:
	element_index = index
	run = LicenceExams.begin(elements[index], car, pad, false)
	_show_progress()


## Cancels the sitting. There is no verdict for an abandoned sitting.
func abort_sitting() -> void:
	if state != State.RUNNING:
		return
	run.abort()
	state = State.RESULT
	_banner_left = ABORT_BANNER_TIME
	if hud:
		hud.hide_licence_card()
		hud.set_mission_line("", LINE_COLOR_RUNNING)
		hud.show_mission_banner("ABORTED  %s" % _exam_title(), _keys_hint(), BANNER_COLOR_ABORTED)
	sitting_aborted.emit(exam)


## Takes the banner down early and returns to idle.
func dismiss_banner() -> void:
	if state != State.RESULT:
		return
	state = State.IDLE
	if hud:
		hud.hide_mission_banner()
		hud.set_mission_line("", LINE_COLOR_RUNNING)


func is_running() -> bool:
	return state == State.RUNNING


## An element's run has ended: failed, the sitting is failed at once (what
## was passed before it stays passed); passed, it goes in the record there
## and then (an L0 element, not on a practice run), and the next element
## begins, or the sitting has passed after the last.
func _element_done() -> void:
	last_result = run.result()
	if not last_result.passed:
		_finish_sitting(false)
		return
	if exam == LicenceExams.EXAM_L0 and not practice:
		record_element(str(last_result.name))
	if element_index + 1 >= elements.size():
		_finish_sitting(true)
		return
	_start_element(element_index + 1)


func _finish_sitting(passed: bool) -> void:
	last_sitting_passed = passed
	state = State.RESULT
	_banner_left = RESULT_BANNER_TIME
	if passed and not practice:
		record_pass(exam)
	if hud:
		hud.hide_licence_card()
		hud.set_mission_line("", LINE_COLOR_RUNNING)
	_show_result(passed)
	sitting_finished.emit(exam, passed)


## A handling test PASSED in mission mode counts towards L1.
func _on_mission_finished(_index: int, outcome: Dictionary) -> void:
	if outcome.get("passed", false):
		record_pass(str(outcome.get("name", "")))


## Puts `exam_name` in the record (once), re-derives the level, saves where
## the store is on, and says so where the level changed.
func record_pass(exam_name: String) -> void:
	if exam_name == "":
		return
	var passed: Array = licence.get("passed", [])
	if not passed.has(exam_name):
		passed.append(exam_name)
	licence["passed"] = passed
	_record_changed()


## Puts the L0 element `element_name` in the record (once, never taken out
## again), re-derives the level - the seventh is L0 - and saves where the
## store is on.
func record_element(element_name: String) -> void:
	if element_name == "":
		return
	var elements_passed: Array = licence.get("elements", [])
	if not elements_passed.has(element_name):
		elements_passed.append(element_name)
	licence["elements"] = elements_passed
	_record_changed()


func _record_changed() -> void:
	var was := level()
	licence["level"] = LicenceExams.level_for(licence.get("passed", []), licence.get("elements", []))
	if _store_kept:
		OdometerStore.save_licence(ArcadeCar.CAR_ID, licence, _store_path)
	if licence["level"] != was:
		licence_changed.emit(licence["level"])
	if book_open:
		_show_book()


# =============================================================================
#  The book
# =============================================================================

## Opens the licence book: the ladder, the record, the rules, the keys.
func open_book() -> void:
	if book_open or state == State.RUNNING:
		return
	book_open = true
	_show_book()


func close_book() -> void:
	if not book_open:
		return
	book_open = false
	if hud:
		hud.hide_licence_card()


func _show_book() -> void:
	if hud:
		hud.show_licence_card(book_text())


## The book's text: the licence held, L0 and its seven elements with a tick
## each, L1 and its seven requirements with a tick each, the ranks, the gate
## and the keys.
# was "one sitting, all or nothing ... retake from the theory" -> the
# elements kept and the sitting resumed: the user's verdict, 2026-09-22
# 14:56 + 15:02.
func book_text() -> String:
	var lines := PackedStringArray()
	lines.append("LICENCE BOOK                                                     held:  %s" % LicenceExams.licence_title(level()))
	lines.append("")
	lines.append("L0 CITIZEN  %s— seven elements, each kept once passed: theory (%d questions), parallel park, bay park, hill start," % [_tick(LicenceExams.EXAM_L0), LicenceExams.quiz_questions().size()])
	lines.append("     three-point turn, reversing course, emergency stop. An element failed ends the sitting; the next sitting resumes at it.")
	var checklist := checklist(licence.get("elements", []))
	lines.append("     %s" % "   ".join(checklist.slice(0, 4)))
	lines.append("     %s" % "   ".join(checklist.slice(4)))
	lines.append("     1   sit the L0 exam (from the first element not yet passed; all passed, a practice run from the theory)")
	lines.append("")
	var l1 := PackedStringArray()
	for test in HandlingTests.all_tests():
		l1.append("%s %s" % [test.title, _tick(test.name)])
	l1.append("SKID PAD %s" % _tick(LicenceExams.EXAM_SKID_PAD))
	lines.append("L1 FACTORY ENTRY  — L0, a PASSED on each handling test (keys 1-5, free training) and the skid pad test:")
	lines.append("     %s" % "     ".join(l1))
	lines.append("     2   skid pad test: two laps between the cone rings, no wheel over a ring, no cone down, inside %.0f s" % LicenceExams.SKID_PAD_TIME_LIMIT)
	lines.append("")
	var ranks := PackedStringArray()
	for rank in LicenceExams.RANKS:
		ranks.append("%s%s" % [rank.title, "" if rank.playable else " (not yet playable)"])
	lines.append("RANKS:  %s  — Porsche ownership is the North Star." % "  ->  ".join(ranks))
	lines.append("")
	lines.append("THE GATE:  unlicensed, the clutch key (Shift) and the aid switches (T, G, K) do nothing. L0 unlocks them for good;")
	lines.append("     in a sitting the instructor's dual controls allow them. The parks and the hill start are sat in manual (the element")
	lines.append("     selects it); from the three-point turn on the instructor's car is automatic.")
	lines.append("")
	lines.append("Esc / R abort a sitting.      L  close")
	return "\n".join(lines)


func _tick(exam_name: String) -> String:
	return "[PASSED]" if has_passed(exam_name) else "[ - ]"


## The L0 sitting's checklist from `elements_passed` (a record's "elements"):
## "Theory: PASSED" or "Theory: —", then each practical element's title with
## a tick, [PASSED], or a dash, [ - ], in the sitting's order. Seven entries;
## the book and the garage's LICENCE panel both show it.
static func checklist(elements_passed: Array) -> PackedStringArray:
	var entries := PackedStringArray()
	for element in LicenceExams.l0_sitting():
		var passed: bool = elements_passed.has(element.name)
		if element.kind == LicenceExams.KIND_QUIZ:
			entries.append("Theory: %s" % ("PASSED" if passed else "—"))
		else:
			entries.append("%s %s" % [element.title, "[PASSED]" if passed else "[ - ]"])
	return entries


# =============================================================================
#  Presentation
# =============================================================================

func _show_progress() -> void:
	if not hud:
		return
	var element: Dictionary = run.test
	var progress := run.progress()
	if progress.kind == LicenceExams.KIND_QUIZ:
		hud.show_licence_card(progress.card)
	else:
		hud.hide_licence_card()
	hud.set_mission_line(
		"%s  ELEMENT %d/%d  %s — %s      %.1f s\n%s   Esc / R  abort" % [
			_exam_title(), element_index + 1, elements.size(), element.title, progress.text, run.elapsed, element.objective,
		],
		LINE_COLOR_RUNNING,
	)


## PASSED / FAILED banner: the licence granted, or the element that failed
## and its failed checks (HandlingTests.format_result's line, split as the
## mission banner splits it).
func _show_result(passed: bool) -> void:
	if not hud:
		return
	var headline: String
	var detail: String
	if passed:
		headline = "PASSED  %s" % _exam_title()
		detail = "%s\nlicence held: %s" % [last_result.name, LicenceExams.licence_title(level())]
	else:
		var element: Dictionary = elements[element_index]
		headline = "FAILED  %s" % _exam_title()
		detail = "element %d/%d %s" % [element_index + 1, elements.size(), element.title]
	var summary := HandlingTests.format_result(last_result)[1].strip_edges().split(" | failed: ")
	detail += "\n" + summary[0]
	if summary.size() > 1:
		detail += "\nfailed: " + summary[1]
	detail += "\n" + _keys_hint()
	hud.show_mission_banner(headline, detail, BANNER_COLOR_PASSED if passed else BANNER_COLOR_FAILED)


func _exam_title() -> String:
	return "L0 EXAM" if exam == LicenceExams.EXAM_L0 else "SKID PAD TEST"


func _keys_hint() -> String:
	return "1  retake      L  licence book      Esc  close"
