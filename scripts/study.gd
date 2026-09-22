class_name Study
extends Node
## THE STUDY: the driving school's lessons, run one at a time on the real
## car by the scripted driver of the test the lesson reuses or of the
## lesson's own pilot (scripts/study_lessons.gd), with every input on show
## (HUD.update_study_panel) and a caption for the step the driver is on.
## Optional, any lesson any time nothing else is running, as often as
## wanted; nothing is judged, recorded or unlocked by it.
##
## The instructor's car: for the length of a lesson the licence gate is
## taken off the car (ArcadeCar.licence_gate = null: everything allowed, as
## in a sitting), the dashboard is set to what the lesson wants (the aids
## on, sport, automatic - LESSON_DASHBOARD - then the lesson's own
## `dashboard`), and the licence manager's keys are stood down
## (process_mode: L and the digits do nothing) while the mission keys are
## held (MissionManager.start_keys_locked). When the lesson ends, by itself,
## on Esc or on R, all of it goes back as it was: the gate, the switches,
## the program and its driver, automatic or manual; every key the pilot may
## have pressed is released. The car stays where the pilot left it (R puts
## it back on the start line, as ever); the tank, the heat and the wear are
## whatever the lesson's drive made of them - a handling test's start hands
## out the fresh car as it does for a mission, an exam element's and a
## lesson pilot's start does not.
##
## The lesson's own run is ticked here, from this node's _physics_process,
## exactly as the mission manager ticks a run: the pilot works the input
## actions (Input.action_press) and the car reads them the next tick, so a
## lesson is the same drive as the headless test of the same script.
## This node never presses a key of its own.

signal lesson_started(lesson: Dictionary)
signal lesson_finished(lesson: Dictionary, outcome: Dictionary)
signal lesson_aborted(lesson: Dictionary)

enum State { IDLE, RUNNING, RESULT }

## How long the LESSON OVER banner stays up unless dismissed [s], and the
## shorter one for an abandoned lesson [s].
const RESULT_BANNER_TIME := 6.0
const ABORT_BANNER_TIME := 2.0

## The dashboard every lesson starts on unless its own `dashboard` says
## otherwise: the certified car's (OdometerStore.DRIVER_DEFAULTS, but the
## camera view, which is the driver's and not touched).
const LESSON_DASHBOARD := {"tcs_on": true, "abs_on": true, "sc_on": true, "gearbox_mode": "sport", "automatic": true}

const BANNER_COLOR := Color(0.55, 0.85, 1.0, 1)
const BANNER_COLOR_ABORTED := Color(1.0, 0.75, 0.25, 1)

@export var car: ArcadeCar
@export var pad: TestPad
@export var hud: HUD
@export var missions: MissionManager
@export var licence: LicenceManager

var state := State.IDLE

## The lesson on, or the last one (StudyLessons' entry); its pilot's
## definition; the run (a HandlingTests or a LicenceExams). Empty / null
## before the first lesson.
var lesson: Dictionary = {}
var definition: Dictionary = {}
var run: RefCounted

## The last run's verdict (the runner's result(): for a lesson pilot only
## the time limit is in it); empty while a lesson is on and after an abort.
var last_result: Dictionary = {}

## What the car was before the lesson, put back after it: the dashboard
## (ArcadeCar.driver_settings()) and the gate.
var _saved_dashboard: Dictionary = {}
var _saved_gate: Object = null
var _banner_left := 0.0


func _physics_process(delta: float) -> void:
	match state:
		State.RUNNING:
			# R also resets the car (the car sees to that itself): the lesson
			# is over either way.
			if Input.is_action_just_pressed("abort_mission") or Input.is_action_just_pressed("reset_car"):
				abort_lesson()
				return
			run.tick(delta)
			if hud:
				hud.update_study_panel(car, delta)
				hud.set_study_caption(StudyLessons.caption_for(lesson, definition, run.step_index()))
			if run.finished:
				_complete()
		State.RESULT:
			_banner_left -= delta
			if _banner_left <= 0.0 or Input.is_action_just_pressed("abort_mission"):
				dismiss_banner()


# =============================================================================
#  Run state
# =============================================================================

## Starts `entry` (a StudyLessons catalogue entry). Returns false for a
## coming-soon lesson, one whose pilot cannot be found, or while a lesson,
## a mission or a sitting is on.
func start_lesson(entry: Dictionary) -> bool:
	if state == State.RUNNING or (missions and missions.is_running()) or (licence and licence.is_running()):
		return false
	var pilot := StudyLessons.pilot_for(entry)
	if pilot.is_empty():
		return false
	if state == State.RESULT:
		dismiss_banner()
	if missions:
		missions.dismiss_banner()
	if licence:
		licence.dismiss_banner()
		licence.close_book()
	lesson = entry
	definition = pilot
	last_result = {}
	_take_the_car()
	if entry.get("source", &"") == StudyLessons.SOURCE_HANDLING:
		run = HandlingTests.begin(pilot, car, pad, true)
	else:
		run = LicenceExams.begin(pilot, car, pad, true)
	state = State.RUNNING
	if hud:
		hud.show_study_panel(String(entry.get("title", "")))
		hud.set_study_caption(StudyLessons.caption_for(entry, pilot, 0))
	lesson_started.emit(entry)
	return true


## Ends the lesson early: no verdict, a brief banner, the car handed back.
func abort_lesson() -> void:
	if state != State.RUNNING:
		return
	run.abort()
	_hand_back_the_car()
	state = State.RESULT
	_banner_left = ABORT_BANNER_TIME
	if hud:
		hud.hide_study_panel()
		hud.show_mission_banner("LESSON ENDED  %s" % lesson.get("title", ""), _keys_hint(), BANNER_COLOR_ABORTED)
	lesson_aborted.emit(lesson)


## Takes the banner down early and returns to idle.
func dismiss_banner() -> void:
	if state != State.RESULT:
		return
	state = State.IDLE
	if hud:
		hud.hide_mission_banner()


func is_running() -> bool:
	return state == State.RUNNING


func _complete() -> void:
	last_result = run.result()
	_hand_back_the_car()
	state = State.RESULT
	_banner_left = RESULT_BANNER_TIME
	if hud:
		hud.hide_study_panel()
		hud.show_mission_banner("LESSON OVER  %s" % lesson.get("title", ""), "%s\n%s" % [lesson.get("objective", ""), _keys_hint()], BANNER_COLOR)
	lesson_finished.emit(lesson, last_result)


# =============================================================================
#  The instructor's car
# =============================================================================

## Notes the dashboard and the gate, takes the gate off, sets the lesson's
## dashboard, holds the mission keys and stands the licence manager's down.
func _take_the_car() -> void:
	_saved_dashboard = car.driver_settings()
	_saved_gate = car.licence_gate
	car.licence_gate = null
	var wanted := LESSON_DASHBOARD.duplicate()
	for field: String in lesson.get("dashboard", {}):
		wanted[field] = lesson.dashboard[field]
	_set_dashboard(wanted)
	if missions:
		missions.start_keys_locked = true
	if licence:
		licence.process_mode = Node.PROCESS_MODE_DISABLED
		if hud:
			hud.set_gate_hint("")


## Releases every key the pilot may hold, puts the dashboard and the gate
## back and gives the managers their keys.
func _hand_back_the_car() -> void:
	for action in StudyLessons.LESSON_ACTIONS:
		Input.action_release(action)
	_set_dashboard(_saved_dashboard)
	car.licence_gate = _saved_gate
	if licence:
		licence.process_mode = Node.PROCESS_MODE_INHERIT
	if missions:
		missions.start_keys_locked = false


## The switches, the program (its driver with it, as the store's load and
## the N key seat one) and automatic or manual, from a dictionary in the
## store's "driver" shape; fields it does not have are left alone.
func _set_dashboard(fields: Dictionary) -> void:
	if fields.has("tcs_on"):
		car.tcs_on = fields.tcs_on
	if fields.has("abs_on"):
		car.abs_on = fields.abs_on
	if fields.has("sc_on"):
		car.sc_on = fields.sc_on
	if fields.has("gearbox_mode"):
		var mode := OdometerStore.GEARBOX_MODES.find(String(fields.gearbox_mode))
		if mode >= 0 and mode != car.gearbox_mode:
			car.gearbox_mode = mode as ArcadeCar.GearboxMode
			car.set_driver_profile(ArcadeCar.DRIVER_PROFILES[ArcadeCar.MODE_DRIVERS[car.gearbox_mode]])
	if fields.has("automatic"):
		car.automatic = fields.automatic


func _keys_hint() -> String:
	return "Tab  garage (THE STUDY: watch it again or pick another)      Esc  close"
