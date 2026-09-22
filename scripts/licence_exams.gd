class_name LicenceExams
extends RefCounted
## The licence ladder: its exams as data, and the runner for one exam element
## on the real car. The user's licence design (2026-09-22 23:20): rigorous,
## real-licence-shaped certifications - cartoon world, serious rules.
##
##   LICENCE 0, CITIZEN: seven elements in a fixed order (l0_sitting()), the
##   theory quiz first, then six practical elements: parallel park, bay park,
##   hill start, turn in the road, reversing course, emergency stop. Each
##   element passed is kept in the car's record the moment it is (the
##   manager's record_element); an element failed ends the sitting at once
##   and the next sitting resumes at the first element not yet passed - a
##   passed theory is never retaken. The seventh grants L0. With every
##   element in the record the exam is sat again from the theory as a
##   practice run, which changes nothing. The first three practical elements
##   are sat in manual, from the fourth the instructor's car is automatic
##   (the "manual" flag; see hill_start_element).
# was one sitting, all or nothing, a retake a new sitting from the quiz ->
# per element: the user's verdict, 2026-09-22 14:56 + 15:02 ("it's annoying
# that if i fail any of the L0 tests i need to get back to theory and not
# retry the test i failed, it's like nothing remembers i took the tests").
# The all-or-nothing rule dated from L0 being two exams, theory and practice,
# each with its own retake; fused into one sitting it dragged the passed
# theory under every failed practice element.
##   LICENCE 1, FACTORY ENTRY: L0, a recorded PASSED on each of the five
##   handling tests (HandlingTests.all_tests(), free training on keys 1-5 as
##   ever) and the skid pad discipline test (skid_pad_test(), 2A's circle).
##   RANKS (RANKS, data only, not yet playable): test driver = an L1 holder,
##   then race driver, then chief test driver; each rank a certification set;
##   Porsche ownership stays the North Star's reward.
##
## An element is plain data (a Dictionary, the *_element() functions), in the
## shape of HandlingTests' tests: name, kind (KIND_*, which checks judge it),
## title, objective, start_offset / start_heading_deg (from the car's spawn
## point), the course it is judged on (a bay, a box, a lane ... TestPad's
## course queries), steps (the scripted driver), settle, time_limit. The
## scripted driver's step conditions are HandlingTests' (after, speed_above /
## below, travelled, rotation_deg / _below) plus what a yard needs:
##   "z_below" / "z_above" / "x_below" / "x_above"  the car's position [m],
##   "stopped"       standing (under STOPPED_SPEED),
##   "reversed"      distance covered tail-first so far [m],
##   "swept_deg"     angle swept round the skid pad's centre [degrees],
## and a step can, besides pressing and releasing keys, set the cruise
## ("cruise_forward": v [m/s] on the accelerate key, "cruise_reverse": v on
## the brake key, which is the throttle in reverse, "cruise_off"), hold the
## clutch pedal near a point ("clutch_hold": 0..1, -1 to let go: the key
## tapped so the pedal hovers there, the way a foot finds the bite) or hold
## the steering wheel near an angle ("steer_deg", left positive, the keys
## tapped the same way; "steer_free" to let go). The skid pad's driver steers
## by a radius (hold_radius) instead: see _drive_skid_pad.
##
## The verdicts are measured, never assumed (the economy cannot lie): the car's
## footprint (TestPad.CAR_HALF_SIZE, 1.8 x 4.2 m) against painted lines, real
## cones toppled (the pad's), real roll-back, a real stall (engine_running),
## the real handbrake and clutch pedal, the real speed at the cue.
##
## One instance is one run of one element on the real car:
##   var run := LicenceExams.begin(element, car, pad, scripted)
##   ... every physics frame:  run.tick(delta)  until run.finished
##   var result := run.result()   # { name, passed, metrics, checks }
## With `scripted` false a human drives and the same checks apply: that is
## how the licence manager sits the exam (scripts/licence_manager.gd). The
## headless test is tests/licence_test.gd.

const KIND_QUIZ := &"quiz"
const KIND_PARK := &"park"
const KIND_HILL_START := &"hill_start"
const KIND_TURN := &"turn_in_road"
const KIND_REVERSE_COURSE := &"reverse_course"
const KIND_EMERGENCY_STOP := &"emergency_stop"
const KIND_SKID_PAD := &"skid_pad"

## A lesson of THE STUDY (scripts/study_lessons.gd): a scripted drive on
## this runner with nothing to judge - no course, no checks but the time
## limit - so a lesson's steps can carry a "say" line each (the caption the
## study shows as the step fires). Nothing of the exams changes for it: the
## kind has no branch in any tracker or verdict, and no exam is of it.
const KIND_LESSON := &"lesson"

# --- Licences, exams and ranks (data) --------------------------------------------

## The licence levels: none, L0 citizen, L1 factory entry.
const LICENCE_NONE := -1
const LICENCE_L0 := 0
const LICENCE_L1 := 1
const LICENCE_TITLES := {LICENCE_NONE: "UNLICENSED", LICENCE_L0: "L0 CITIZEN", LICENCE_L1: "L1 FACTORY ENTRY"}

## The exams as they are recorded in the car's licence record (the store's
## "passed" list): the L0 sitting as one pass, the skid pad test as one, and
## the five handling tests by their own names (HandlingTests test.name).
const EXAM_L0 := "L0_CITIZEN"
const EXAM_SKID_PAD := "SKID_PAD"
const L1_HANDLING_TESTS: Array[String] = ["SLALOM_TEST", "SPIN_180", "SPIN_360", "STOP_BOX", "REVERSE_180"]

## The rank ladder: data only, marked as such. A rank is a certification set;
## "requires" names what is recorded (licence levels and exams). Rank 0 is
## playable (it is L1); ranks 1 and 2 are the North Star's, their sets to be
## written when their content is (nothing here builds them).
const RANKS: Array[Dictionary] = [
	{"rank": 0, "title": "TEST DRIVER", "requires": {"licence": LICENCE_L1}, "playable": true},
	{"rank": 1, "title": "RACE DRIVER", "requires": {"licence": LICENCE_L1, "certifications": "race certification set (not yet written)"}, "playable": false},
	{"rank": 2, "title": "CHIEF TEST DRIVER", "requires": {"rank": 1, "certifications": "chief certification set (not yet written)"}, "playable": false, "reward": "Porsche ownership (North Star)"},
]

# --- Pass / fail tolerances -------------------------------------------------------

## Standing still: under this [m/s] (HandlingTests.STOPPED_SPEED).
const STOPPED_SPEED := 0.3

## Parking, both bays: the car must stand within this of the bay's axis
## [degrees] on top of every corner being inside the lines.
const PARK_HEADING_TOLERANCE_DEG := 10.0

## Parallel park: it is a reversing manoeuvre - at least this far covered
## tail-first during the element [m].
const PARALLEL_MIN_REVERSE_M := 3.0

## Hill start: how far the car may roll back down the hill from where it
## stopped, ever, until it is over the crest [m].
# was "a few cm" (the user's design) -> 0.15: measured on the 8 % ramp, the
# handbrake itself lets the locked rears creep 7 mm/s (3.5 cm in 5 s; the
# tyre model's locked wheel at a standstill), so a driver ten seconds on the
# lever has 7 cm before the clutch has done anything; the clean pull-away
# (handbrake and clutch key let go together, the revs up) rolls back 0.7 -
# 1.1 cm, the clutch let in too far on the locked axle rolls back 39 cm and
# stalls (tests/licence_test.gd shows both). 0.15 is a hand's width: a real
# examiner's "no significant roll-back".
const HILL_ROLL_BACK_TOLERANCE := 0.15

## Hill start: the clutch pedal counts as on the floor from here (0..1).
const HILL_CLUTCH_FLOOR := 0.99

## Hill start: the car pulls away to over the crest line at this speed or
## more [m/s] (a walk: it must be driving, not creeping).
const HILL_MIN_CREST_SPEED := 1.5

## Turn in the road: from a three-point turn to a five-point one (direction
## changes: forward, back, forward is 2), at least this much of it reversed
## [m], ending within this of facing back [degrees].
const TURN_MIN_DIRECTION_CHANGES := 2
const TURN_MAX_DIRECTION_CHANGES := 4
const TURN_MIN_REVERSE_M := 1.0
const TURN_HEADING_TOLERANCE_DEG := 20.0

## Reversing course: at least this far reversed up the lane [m] (the lane is
## 34 m, the end box's middle 31 m from the start).
const REVERSE_COURSE_MIN_DISTANCE := 25.0

## Emergency stop: the speed the car must be doing at the cue bar [m/s]
## (50 km/h) ...
const EMERGENCY_MIN_SPEED := 50.0 / 3.6

## Skid pad: two full laps between the rings ...
const SKID_PAD_LAPS := 2.0

## ... inside this [s] from the start (the car starts on the ring, standing):
## 352 m of ring at the scripted driver's 12 m/s is 29 s plus getting there.
const SKID_PAD_TIME_LIMIT := 50.0

## Skid pad: the radius the scripted driver holds [m], mid ring (22 .. 34) ...
const SKID_PAD_HOLD_RADIUS := 28.0

## ... at this speed [m/s] (43 km/h: 5.1 m/s^2 across, well inside the grip) ...
const SKID_PAD_SPEED := 12.0

## ... with this much steering wheel per metre of radius error [degrees / m]
## and per m/s of radius rate [degrees / (m/s)] on top of the geometric angle
## for the radius (see _drive_skid_pad).
const SKID_PAD_STEER_GAIN := 12.0
const SKID_PAD_STEER_DAMPING := 30.0

# --- Scripted driver ----------------------------------------------------------------

## Every key the scripted driver may press (released at the end of a run).
const ACTIONS: Array[StringName] = [
	&"accelerate", &"brake", &"steer_left", &"steer_right", &"handbrake", &"clutch_pedal",
	&"test_1", &"test_2", &"test_3", &"test_4",
]

## The answer keys of the quiz, in answer order: digits 1 .. 4 (the mission
## keys, taken over for the sitting).
const ANSWER_ACTIONS: Array[StringName] = [&"test_1", &"test_2", &"test_3", &"test_4"]

## Quiz: a question is failed unanswered after this [s].
const QUIZ_QUESTION_TIME := 20.0

## Quiz, scripted: the pilot answers this long after a card comes up [s],
## with a tap this long [s].
const QUIZ_ANSWER_DELAY := 0.4
const QUIZ_TAP_TIME := 0.1

## Yard speeds for the scripted driver [m/s]: the drive up to a manoeuvre,
## the manoeuvre itself tail-first, the hill (a walk up to the box).
const YARD_APPROACH_SPEED := 4.0
const YARD_REVERSE_SPEED := 2.0
const HILL_APPROACH_SPEED := 5.0

## Hill start, scripted: where the driver brakes for the hold box (car z, the
## box is z 81 .. 89) [m]. Measured: from 5 m/s the car stops 1.9 m on, at
## z = 85.6, 3.4 m of box either side.
const HILL_BRAKE_Z := 87.5

## Hill start, scripted: how long the revs are raised with the clutch on the
## floor before the handbrake and the clutch key are let go together [s].
## Measured: 0.33 s of throttle has the engine at ~3000 rpm and the pull-away
## rolls back 0.65 cm; 1 s at the limiter (7080 rpm) 1.1 cm.
const HILL_REV_TIME := 0.35

## Parallel park, scripted: where the driver stops alongside the bay before
## reversing in (car z) [m], the lock wound on at the standstill for this long
## before reversing [s] (0.35 s is centre to lock), and the two lock changes
## at the rotations these name [degrees]: full right lock tail-first until the
## car has swung this far, then full left lock until it is this close to
## straight, then the brakes.
# Measured (the S is stretched: the wheel takes 0.7 s from lock to lock, 1.4 m
# of reversing at 2 m/s with little lock on, so two 45-degree arcs of the
# 5.0 m rear-axle circle are too much): stop 44.0 / swing 37.5 / straight 4
# ends the car at (11.98, 50.19), 1.1 degrees off, 0.24 m inside the side
# lines, 1.19 m inside the ends; swing 36 and 39 are 0.10 and 0.08 m inside;
# stop 42.5 (a length further forward) puts the tail under the front cone.
const PARALLEL_STOP_Z := 44.0
const PARALLEL_PREWIND_TIME := 0.5
const PARALLEL_SWING_DEG := 37.5
const PARALLEL_STRAIGHT_DEG := 4.0

## Bay park, scripted: the driver turns in for the bay when this far along
## the aisle (car x) [m] ...
# Measured at 3 m/s: the car ends 4.5 m past where the lock goes on (a 5.0 m
# rear-axle circle less the wheel's 0.35 s of winding on), so 26.5 for the
# bay's axis at x = 22: ends at x = 22.06, 0.31 m inside the side lines; 26.0
# and 27.0 are 0.06 and -0.19.
const BAY_TURN_IN_X := 26.5
## ... lets the wheel go this far short of square [degrees] (the car finishes
## the turn on its own as the wheel returns: 83 ends 0.8 degrees off, 85 -0.9,
## 87 -3.2) and brakes at this depth (car z) [m]: it stops 0.6 m on.
const BAY_STRAIGHTEN_DEG := 83.0
const BAY_STOP_Z := 80.4

## Turn in the road, scripted: full left lock forward to here [degrees], full
## right lock backwards to here, full left lock forward to here.
const TURN_FIRST_LEG_DEG := 80.0
const TURN_SECOND_LEG_DEG := 145.0
const TURN_THIRD_LEG_DEG := 172.0
const TURN_SPEED := 3.0
const TURN_REVERSE_SPEED := 2.5

## Reversing course, scripted: reversing speed [m/s] and where to stop (car
## z; the end box is z 63 .. 71) [m].
const REVERSE_COURSE_SPEED := 3.0
const REVERSE_COURSE_STOP_Z := 66.0

## Emergency stop, scripted: cruise speed on the run-up [m/s], 54 km/h.
const EMERGENCY_APPROACH_SPEED := 15.0

var test: Dictionary
var car: ArcadeCar
var pad: Node
var scripted := true
var finished := false
var elapsed := 0.0

var _step_index := 0
var _since_step := 0.0
var _all_steps_done_at := -1.0
var _pressed: Dictionary[StringName, bool] = {}
var _cruise_forward := -1.0  # [m/s], negative = off.
var _cruise_reverse := -1.0
var _clutch_hold := -1.0  # Pedal position to hover at, negative = the key is the script's.
var _steer_hold := false
var _steer_target_deg := 0.0

var _start_position: Vector3
var _start_forward: Vector3
var _start_yaw := 0.0
var _previous_yaw := 0.0
var _rotation := 0.0  # Unwrapped yaw since the start [rad], left positive.
var _previous_position: Vector3
var _reversed := 0.0  # Distance covered tail-first [m].
var _forward_travel := 0.0  # Distance covered nose-first [m].
var _timed_out := false
var _peak_speed := 0.0

# Direction changes (the turn in the road).
var _leg_direction := 0  # +1 nose-first, -1 tail-first, 0 not yet moved.
var _direction_changes := 0

# Bounds (the turn's stretch, the reversing lane, the skid ring).
var _left_bounds := false
var _worst_excursion := 0.0  # How far the worst corner got outside [m].

# Hill start.
var _hill_stopped := false  # Stopped inside the hold box.
var _hill_stop_z := 0.0
var _hill_roll_back := 0.0
var _hill_handbrake_held := false  # Held on the lever, the brake pedal off.
var _hill_clutch_floored := false
var _hill_stalled := false
var _hill_crested := false
var _hill_crest_speed := 0.0

# Emergency stop.
var _cue_given := false
var _cue_speed := 0.0

# Skid pad.
var _swept := 0.0  # Angle swept round the centre [rad], unsigned.
var _previous_bearing := 0.0
var _previous_radius := 0.0
var _laps_done_at := -1.0

# Quiz.
var _question_index := 0
var _answers: Array[int] = []  # What was answered, per question (1-based digit).
var _question_time := 0.0
var _quiz_failed := false


# =============================================================================
#  Licences, exams and ranks
# =============================================================================

## The licence level a record earns - `passed`, the exam names passed, and
## `elements`, the L0 sitting's element names passed: L0 with every one of
## the sitting's seven elements in `elements` OR the sitting itself (EXAM_L0)
## in `passed` - the exam-level pass of a record written before there were
## elements entails the whole sitting, so an old record keeps its licence;
## L1 with L0 and the rest of l1_requirements() (the five handling tests, the
## skid pad) in `passed`; none otherwise. The store keeps the passes and the
## elements; the level is always this function of them.
# was level_for(passed) on EXAM_L0 alone -> the elements beside it: the
# user's verdict, 2026-09-22 14:56 + 15:02 (each element passed is kept, the
# sitting resumes at the first not yet passed). The one-argument call is the
# old one, still: no elements, the exam-level pass alone decides L0.
static func level_for(passed: Array, elements: Array = []) -> int:
	if not (passed.has(EXAM_L0) or sitting_complete(elements)):
		return LICENCE_NONE
	for exam in l1_requirements():
		if exam != EXAM_L0 and not passed.has(exam):
			return LICENCE_L0
	return LICENCE_L1


## What L1 takes: the L0 sitting, the five handling tests, the skid pad.
static func l1_requirements() -> Array[String]:
	var exams: Array[String] = [EXAM_L0]
	exams.append_array(L1_HANDLING_TESTS)
	exams.append(EXAM_SKID_PAD)
	return exams


## The L0 sitting's seven element names, in the order they are sat.
static func l0_element_names() -> Array[String]:
	var names: Array[String] = []
	for element in l0_sitting():
		names.append(element.name)
	return names


## Whether `elements` (element names passed) holds every one of the sitting's.
static func sitting_complete(elements: Array) -> bool:
	for name in l0_element_names():
		if not elements.has(name):
			return false
	return true


## Where a sitting with `elements` already passed begins: the index in
## l0_sitting() of the first element not in it, in the sitting's order (a
## passed theory is never retaken: the scan walks past it); 0 for a complete
## record, the sitting sat again from the theory as a practice run.
static func l0_resume_index(elements: Array) -> int:
	var names := l0_element_names()
	for index in names.size():
		if not elements.has(names[index]):
			return index
	return 0


## The name of a licence level.
static func licence_title(level: int) -> String:
	return LICENCE_TITLES.get(level, LICENCE_TITLES[LICENCE_NONE])


## The L0 sitting's seven elements, in the order they are sat.
static func l0_sitting() -> Array[Dictionary]:
	return [
		theory_quiz_element(), parallel_park_element(), bay_park_element(), hill_start_element(),
		turn_in_road_element(), reversing_course_element(), emergency_stop_element(),
	]


## The theory quiz: questions the sim itself answers (each one is a rule of
## scripts/car.gd or scripts/handling_tests.gd, cited), three answers each,
## the right one's number in "correct" (1-based, the digit key). Fixed order.
static func quiz_questions() -> Array[Dictionary]:
	return [
		{
			"question": "TCS switched off, full throttle from rest in 1st: the rear tyres ...",
			"answers": ["grip as they always do", "spin up: the clutch is let in for good with no slip limit", "lock"],
			"correct": 2,  # ArcadeCar DRIVE_SLIP_RATIO: TCS off, the clutch is dumped once the revs are up.
		},
		{
			"question": "ABS, braking hard: the fronts are held ...",
			"answers": ["just short of locking, so the car still steers", "locked, for the shortest stop", "off the brakes"],
			"correct": 1,  # ArcadeCar ABS_SLIP_RATIO.
		},
		{
			"question": "The handbrake locks ...",
			"answers": ["all four wheels", "the front wheels", "the rear wheels"],
			"correct": 3,  # ArcadeCar: the handbrake is on the rear brakes.
		},
		{
			"question": "Handbrake on, throttle open, the clutch pedal let up to the floor: the engine ...",
			"answers": ["is dragged under 450 rpm and stalls", "revs on", "declutches itself"],
			"correct": 1,  # ArcadeCar STALL_RPM 450, the driver's clutch may lock under idle.
		},
		{
			"question": "The run clock of a handling test starts ...",
			"answers": ["the moment the test begins", "when the car crosses the test's painted start line", "at the first cone"],
			"correct": 2,  # HandlingTests, "The run clock".
		},
		{
			"question": "SC (the stability assist) switched off, the car slides: the slide ...",
			"answers": ["is caught by the car", "cannot happen", "hangs on as long as the tyres let it; the spin is yours to catch"],
			"correct": 3,  # ArcadeCar sc_on: _slide_yaw_damping 0 on every branch.
		},
		{
			"question": "R (reset) and the wear of the clutch, brakes, tyres and engine: R ...",
			"answers": ["makes them new", "refuels, it does not un-wear", "wears them a little more"],
			"correct": 2,  # ArcadeCar reset_to: the six shares stay.
		},
		{
			"question": "A fresh press of the brake key at a standstill ...",
			"answers": ["selects reverse", "holds the car", "does nothing"],
			"correct": 1,  # ArcadeCar _update_direction.
		},
	]


static func theory_quiz_element() -> Dictionary:
	var questions := quiz_questions()
	# The pilot answers every question right, one tap each, after the card
	# has been up a moment.
	var steps: Array[Dictionary] = []
	for question in questions:
		var key: StringName = ANSWER_ACTIONS[question.correct - 1]
		steps.append({"when": {"after": QUIZ_ANSWER_DELAY}, "press": [key]})
		steps.append({"when": {"after": QUIZ_TAP_TIME}, "release": [key]})
	return {
		"name": "THEORY_QUIZ",
		"kind": KIND_QUIZ,
		"title": "THEORY",
		"objective": "%d questions, one wrong answer fails the sitting. Digits 1-3 answer." % questions.size(),
		"questions": questions,
		"start_offset": Vector3.ZERO,
		"start_heading_deg": 0.0,
		"steps": steps,
		"settle": 0.5,
		"time_limit": QUIZ_QUESTION_TIME * questions.size(),
	}


## Parallel park: drive past the bay on the right, reverse in tail-first
## between the two cones, stop straight inside the lines.
static func parallel_park_element() -> Dictionary:
	var bay := TestPad.parallel_bay()
	var centre: Vector3 = bay.centre
	return {
		"name": "PARALLEL_PARK",
		"kind": KIND_PARK,
		"title": "PARALLEL PARK",
		"objective": "Drive past the bay on your right, reverse in between the cones, stop straight inside the lines.",
		"bay": bay,
		"min_reverse_m": PARALLEL_MIN_REVERSE_M,
		# Sat in manual (the user's verdict, 2026-09-22: the first three
		# practical elements are; see hill_start_element).
		"manual": true,
		"start_offset": Vector3(centre.x - 3.0, 0.0, centre.z + 12.0),
		"start_heading_deg": 0.0,
		"steps": [
			{"when": {}, "cruise_forward": YARD_APPROACH_SPEED},
			{"when": {"z_below": PARALLEL_STOP_Z}, "cruise_off": true, "press": [&"brake"]},
			{"when": {"stopped": 1.0}, "release": [&"brake"]},
			# Reverse: a fresh press of the brake key at a standstill; then the
			# brake key is the throttle. Full right lock wound on standing, then
			# tail-first it swings the tail into the bay, full left lock brings
			# the nose in after it.
			{"when": {"after": 0.2}, "press": [&"brake", &"steer_right"]},
			{"when": {"after": PARALLEL_PREWIND_TIME}, "cruise_reverse": YARD_REVERSE_SPEED},
			{"when": {"rotation_deg": PARALLEL_SWING_DEG}, "release": [&"steer_right"], "press": [&"steer_left"]},
			{"when": {"rotation_deg_below": PARALLEL_STRAIGHT_DEG}, "release": [&"steer_left"], "cruise_off": true, "press": [&"accelerate"]},
			{"when": {"stopped": 1.0}, "release": [&"accelerate"]},
		],
		"settle": 1.0,
		"time_limit": 60.0,
	}


## Bay park: from the aisle, nose-first into the bay, stop inside the lines
## square to them.
static func bay_park_element() -> Dictionary:
	var bay := TestPad.parking_bay()
	var centre: Vector3 = bay.centre
	return {
		"name": "BAY_PARK",
		"kind": KIND_PARK,
		"title": "BAY PARK",
		"objective": "Along the aisle and nose-first into the marked bay: stop with the whole car inside its lines, square.",
		"bay": bay,
		"min_reverse_m": 0.0,
		# Sat in manual (the user's verdict, 2026-09-22: the first three
		# practical elements are; see hill_start_element).
		"manual": true,
		# The aisle runs along x at aisle_z; the car starts at its far end
		# facing -X (heading 90) and turns right into the bay.
		"start_offset": Vector3(centre.x + 12.0, 0.0, bay.aisle_z),
		"start_heading_deg": 90.0,
		"steps": [
			{"when": {}, "cruise_forward": YARD_APPROACH_SPEED - 1.0},
			{"when": {"x_below": BAY_TURN_IN_X}, "press": [&"steer_right"]},
			{"when": {"rotation_deg_below": -BAY_STRAIGHTEN_DEG}, "release": [&"steer_right"]},
			{"when": {"z_below": BAY_STOP_Z}, "cruise_off": true, "press": [&"brake"]},
			{"when": {"stopped": 1.0}},
		],
		"settle": 1.0,
		"time_limit": 60.0,
	}


## Hill start: up the ramp, stop in the hold box on the rise, hold on the
## handbrake, clutch to the floor, revs up, bite and away over the crest
## without rolling back or stalling.
##   THE INSTRUCTOR'S CAR (the user's verdict, 2026-09-22): the first three
## practical elements - the parallel park, the bay park and this - are sat in
## manual; from the fourth, the turn in the road, on it is automatic, "now
## they've proven they can drive an auto". An element with "manual": true
## puts the gearbox in manual as it starts (_start; the clutch key works,
## and so does M to undo it - here there is then no pedal to floor and the
## element fails); every element's start resets the car, and the reset
## re-arms automatic (ArcadeCar.reset_to), so an element without the flag is
## sat in automatic. The parks' scripted drivers never touch the clutch key:
## the car's own feathering works the clutch until the driver's foot does.
static func hill_start_element() -> Dictionary:
	var hill := TestPad.hill_start()
	return {
		"name": "HILL_START",
		"kind": KIND_HILL_START,
		"title": "HILL START",
		"objective": "Stop in the box on the hill, handbrake on, clutch (Shift) to the floor, revs up, bite and away over the crest: no roll-back, no stall.",
		"hill": hill,
		"manual": true,
		"start_offset": Vector3(hill.axis_x, 0.0, hill.start_z),
		"start_heading_deg": 0.0,
		"steps": [
			{"when": {}, "cruise_forward": HILL_APPROACH_SPEED},
			{"when": {"z_below": HILL_BRAKE_Z}, "cruise_off": true, "press": [&"brake"]},
			# Stopped on the brake: the lever on before the foot comes off it
			# (a fresh press of the brake at a standstill would be reverse).
			{"when": {"stopped": 1.0}, "press": [&"handbrake"]},
			{"when": {"after": 0.3}, "release": [&"brake"], "press": [&"clutch_pedal"]},
			{"when": {"after": 0.5}, "press": [&"accelerate"]},
			# The lever and the clutch key let go together: the pedal comes up
			# through the bite over 0.2 s (CLUTCH_PEDAL_SPEED) as the rears
			# are freed, and the car is away.
			{"when": {"after": HILL_REV_TIME}, "release": [&"handbrake", &"clutch_pedal"]},
			{"when": {"z_below": hill.crest_z}, "release": [&"accelerate"], "press": [&"brake"]},
			{"when": {"stopped": 1.0}},
		],
		"settle": 1.0,
		"time_limit": 60.0,
	}


## Turn in the road: on the straight between the two bars, turn the car to
## face back the way it came in three (to five) points, every wheel inside
## the lane's edge lines the whole time.
static func turn_in_road_element() -> Dictionary:
	var stretch := TestPad.turn_stretch()
	return {
		"name": "TURN_IN_ROAD",
		"kind": KIND_TURN,
		"title": "THREE-POINT TURN",
		"objective": "Turn to face back the way you came, between the bars, inside the lane lines: forward, back, forward.",
		"stretch": stretch,
		# From the right-hand side of the lane, as a driver would.
		"start_offset": Vector3(3.0, 0.0, stretch.centre_z),
		"start_heading_deg": 0.0,
		"steps": [
			{"when": {}, "press": [&"steer_left"], "cruise_forward": TURN_SPEED},
			{"when": {"rotation_deg": TURN_FIRST_LEG_DEG}, "cruise_off": true, "release": [&"steer_left"], "press": [&"brake"]},
			{"when": {"stopped": 1.0}, "release": [&"brake"]},
			{"when": {"after": 0.2}, "press": [&"brake", &"steer_right"], "cruise_reverse": TURN_REVERSE_SPEED},
			{"when": {"rotation_deg": TURN_SECOND_LEG_DEG}, "cruise_off": true, "release": [&"steer_right"], "press": [&"accelerate"]},
			{"when": {"stopped": 1.0}, "release": [&"accelerate"]},
			{"when": {"after": 0.2}, "press": [&"accelerate", &"steer_left"], "cruise_forward": TURN_SPEED},
			{"when": {"rotation_deg": TURN_THIRD_LEG_DEG}, "cruise_off": true, "release": [&"steer_left"], "press": [&"brake"]},
			{"when": {"stopped": 1.0}},
		],
		"settle": 1.0,
		"time_limit": 60.0,
	}


## Reversing course: tail-first up the lane between its lines and through the
## cone gates into the end box, without a wheel over a line or a cone down.
static func reversing_course_element() -> Dictionary:
	var course := TestPad.reversing_course()
	var lane: Dictionary = course.lane
	return {
		"name": "REVERSING_COURSE",
		"kind": KIND_REVERSE_COURSE,
		"title": "REVERSING",
		"objective": "Reverse up the lane between the lines and through the gates, stop inside the end box.",
		"course": course,
		"start_offset": Vector3(lane.centre.x, 0.0, course.start_z),
		"start_heading_deg": 0.0,
		"steps": [
			# A moment with nothing pressed first (a fresh press of the brake key
			# at the standstill is reverse; a key held over from before is not).
			{"when": {"after": 0.1}, "press": [&"brake"], "cruise_reverse": REVERSE_COURSE_SPEED},
			# The accelerate key is the brake in reverse - and held through the
			# stop it selects forward (FORWARD_ENGAGE_GRACE) and drives off, so
			# it comes off the moment the car stands.
			{"when": {"z_above": REVERSE_COURSE_STOP_Z}, "cruise_off": true, "press": [&"accelerate"]},
			{"when": {"stopped": 1.0}, "release": [&"accelerate"]},
		],
		"settle": 1.0,
		"time_limit": 60.0,
	}


## Emergency stop: build speed down the lane; at the red bar (the line says
## STOP) stop as hard as the car will, with the whole car inside the zone.
static func emergency_stop_element() -> Dictionary:
	var course := TestPad.emergency_stop()
	return {
		"name": "EMERGENCY_STOP",
		"kind": KIND_EMERGENCY_STOP,
		"title": "EMERGENCY STOP",
		"objective": "%.0f km/h or more at the red bar, then STOP: brake hard and stop with the whole car inside the zone." % (EMERGENCY_MIN_SPEED * 3.6),
		"course": course,
		"start_offset": Vector3(0.0, 0.0, course.start_z),
		"start_heading_deg": 0.0,
		"steps": [
			{"when": {}, "cruise_forward": EMERGENCY_APPROACH_SPEED},
			{"when": {"z_below": course.cue_z}, "cruise_off": true, "press": [&"brake"]},
			{"when": {"stopped": 1.0}},
		],
		"settle": 1.0,
		"time_limit": 40.0,
	}


## Skid pad discipline (L1): two laps of the skid pad between its two cone
## rings, every wheel between the rings the whole way, no cone down, inside
## the time. The car starts standing on the ring's east side, facing -Z: a
## left-hand circle.
static func skid_pad_test() -> Dictionary:
	var circle := TestPad.skid_circle()
	var centre: Vector3 = circle.centre
	return {
		"name": EXAM_SKID_PAD,
		"kind": KIND_SKID_PAD,
		"title": "SKID PAD",
		"objective": "Two laps between the cone rings, every wheel inside them, no cone down, inside %.0f s." % SKID_PAD_TIME_LIMIT,
		"circle": circle,
		"laps": SKID_PAD_LAPS,
		"start_offset": Vector3(centre.x + SKID_PAD_HOLD_RADIUS, 0.0, centre.z),
		"start_heading_deg": 0.0,
		"hold_radius": SKID_PAD_HOLD_RADIUS,
		"steps": [
			{"when": {}, "cruise_forward": SKID_PAD_SPEED},
			{"when": {"swept_deg": 360.0 * SKID_PAD_LAPS}, "cruise_off": true, "steer_free": true, "press": [&"brake"]},
			{"when": {"stopped": 1.0}},
		],
		"settle": 1.0,
		"time_limit": SKID_PAD_TIME_LIMIT,
	}


# =============================================================================
#  Running one element
# =============================================================================

## Puts the car on the element's start point (unless `place` is false: a
## pilot alongside a run that already did), stands the cones back up and
## returns the run. Call tick() once per physics frame until `finished`.
static func begin(definition: Dictionary, target_car: ArcadeCar, test_pad: Node, use_script := true, place := true) -> LicenceExams:
	var run := LicenceExams.new()
	run.test = definition
	run.car = target_car
	run.pad = test_pad
	run.scripted = use_script
	run._start(place)
	return run


func _start(place: bool) -> void:
	_release_all()
	if place:
		var spawn := car.get_spawn_transform()
		var offset: Vector3 = test.get("start_offset", Vector3.ZERO)
		var heading := deg_to_rad(test.get("start_heading_deg", 0.0))
		car.reset_to(Transform3D(spawn.basis.rotated(Vector3.UP, heading), spawn.origin + offset))
		if test.get("manual", false):
			car.automatic = false
		if pad != null and pad.has_method("reset_cones"):
			pad.reset_cones()
	_start_position = car.global_position
	_previous_position = _start_position
	_start_forward = -car.global_basis.z
	_start_yaw = car.global_rotation.y
	_previous_yaw = _start_yaw
	if test.kind == KIND_SKID_PAD:
		_previous_bearing = _bearing()
		_previous_radius = _radius()
	if test.kind == KIND_QUIZ:
		_question_time = 0.0


## Advances the run by one physics frame: tracks the car, judges what is
## judged tick by tick, then lets the scripted driver work the controls.
func tick(delta: float) -> void:
	if finished:
		return
	elapsed += delta
	_since_step += delta
	_track(delta)
	if test.kind == KIND_QUIZ:
		_track_quiz(delta)
	if scripted:
		_drive(delta)
	var steps: Array = test.steps
	if _all_steps_done_at < 0.0 and (_step_index >= steps.size() or not scripted) and _is_complete():
		_all_steps_done_at = elapsed
	if _all_steps_done_at >= 0.0 and elapsed - _all_steps_done_at >= test.get("settle", 1.0):
		_finish()
	elif _failed_already():
		_finish()
	elif elapsed >= test.time_limit:
		_timed_out = true
		_finish()


## Stops the run early (the sitting was abandoned) and frees the controls.
func abort() -> void:
	_finish()


## How many of the script's steps have fired so far (the next to fire is
## steps[step_index()]); read-only, for THE STUDY's captions.
func step_index() -> int:
	return _step_index


## One line on where the run stands, for tracing an element while tuning it.
func describe_state() -> String:
	return "t=%5.2f step=%d pos=(%7.2f, %7.2f) fwd=%6.2f rot=%7.1f rev=%5.1f changes=%d bounds=%s" % [
		elapsed, _step_index, car.global_position.x, car.global_position.z, car.forward_speed,
		rad_to_deg(_rotation), _reversed, _direction_changes, "out" if _left_bounds else "in",
	]


## Where the run stands, for the HUD: always `kind` and `text`, one short
## line of the live objective; the quiz adds `question` (1-based), `total`
## and `card` (the card's text: question and numbered answers).
func progress() -> Dictionary:
	var state := {"kind": test.kind, "text": _progress_text()}
	if test.kind == KIND_QUIZ:
		var questions: Array = test.questions
		state["question"] = _question_index + 1
		state["total"] = questions.size()
		state["card"] = card_text()
	return state


## The quiz card: "THEORY 3/8", the question, the numbered answers.
func card_text() -> String:
	var questions: Array = test.questions
	if _question_index >= questions.size():
		return "THEORY  %d/%d\nall answered" % [questions.size(), questions.size()]
	var question: Dictionary = questions[_question_index]
	var lines := PackedStringArray()
	lines.append("THEORY  %d/%d      %.0f s" % [_question_index + 1, questions.size(), maxf(QUIZ_QUESTION_TIME - _question_time, 0.0)])
	lines.append(question.question)
	var answers: Array = question.answers
	for i in answers.size():
		lines.append("  %d)  %s" % [i + 1, answers[i]])
	return "\n".join(lines)


func _progress_text() -> String:
	match test.kind:
		KIND_LESSON:
			var steps: Array = test.steps
			return "STEP %d/%d" % [mini(_step_index, steps.size()), steps.size()]
		KIND_QUIZ:
			var questions: Array = test.questions
			return "QUESTION %d/%d — digits answer" % [mini(_question_index + 1, questions.size()), questions.size()]
		KIND_PARK:
			var margin := _box_margin(test.bay)
			if _speed() < STOPPED_SPEED and margin >= 0.0:
				return "INSIDE — margin %.2f m, %.0f° off" % [margin, _bay_heading_error_deg()]
			if margin >= 0.0:
				return "IN THE BAY — stop straight"
			return "%.1f m outside the lines" % -margin
		KIND_HILL_START:
			if not _hill_stopped:
				return "STOP IN THE BOX (%.0f m)" % (car.global_position.z - test.hill.hold_box.centre.z)
			if not _hill_handbrake_held:
				return "HANDBRAKE ON, foot off the brake"
			if not _hill_clutch_floored:
				return "CLUTCH TO THE FLOOR, revs up"
			return "BITE AND AWAY — rolled back %.0f cm, crest %.0f m" % [_hill_roll_back * 100.0, car.global_position.z - test.hill.crest_z]
		KIND_TURN:
			return "%d direction change(s), facing %.0f° — %s" % [_direction_changes, rad_to_deg(absf(_rotation)), "OUTSIDE THE LANE" if _left_bounds else "inside"]
		KIND_REVERSE_COURSE:
			return "REVERSED %.0f m — %s" % [_reversed, "OVER A LINE" if _left_bounds else "between the lines"]
		KIND_EMERGENCY_STOP:
			if not _cue_given:
				return "BUILD SPEED %d/%d km/h  %d m to the bar" % [roundi(car.speed_kmh), roundi(EMERGENCY_MIN_SPEED * 3.6), roundi(car.global_position.z - test.course.cue_z)]
			return "STOP!"
		_:
			return "LAP %.1f/%.0f  r %.0f m — %s" % [rad_to_deg(_swept) / 360.0, test.laps, _radius(), "OFF THE RING" if _left_bounds else "on the ring"]


## The verdict: { name, passed, metrics, checks }, HandlingTests.result()'s
## shape (format_result there prints it).
func result() -> Dictionary:
	var checks: Array[Dictionary] = []
	var metrics := {}
	match test.kind:
		KIND_QUIZ:
			_judge_quiz(checks, metrics)
		KIND_PARK:
			_judge_park(checks, metrics)
		KIND_HILL_START:
			_judge_hill_start(checks, metrics)
		KIND_TURN:
			_judge_turn(checks, metrics)
		KIND_REVERSE_COURSE:
			_judge_reverse_course(checks, metrics)
		KIND_EMERGENCY_STOP:
			_judge_emergency_stop(checks, metrics)
		KIND_SKID_PAD:
			_judge_skid_pad(checks, metrics)
	checks.append({"label": "finished inside the time limit", "passed": not _timed_out})
	metrics["time_s"] = snappedf(elapsed, 0.01)
	var passed := true
	for check in checks:
		passed = passed and check.passed
	return {"name": test.name, "passed": passed, "metrics": metrics, "checks": checks}


# --- Scripted driver ---------------------------------------------------------------

func _drive(delta: float) -> void:
	var steps: Array = test.steps
	while _step_index < steps.size() and _conditions_met(steps[_step_index].get("when", {})):
		var step: Dictionary = steps[_step_index]
		for action: StringName in step.get("release", []):
			_set_action(action, false)
			if action == &"steer_left" or action == &"steer_right":
				_steer_hold = false
		for action: StringName in step.get("press", []):
			_set_action(action, true)
			if action == &"steer_left" or action == &"steer_right":
				_steer_hold = false
		if step.has("cruise_forward"):
			_cruise_forward = step.cruise_forward
			_cruise_reverse = -1.0
		if step.has("cruise_reverse"):
			_cruise_reverse = step.cruise_reverse
			_cruise_forward = -1.0
		if step.get("cruise_off", false):
			# The cruise's key comes off with it (unless this step presses it).
			if _cruise_forward >= 0.0 and not step.get("press", []).has(&"accelerate"):
				_set_action(&"accelerate", false)
			if _cruise_reverse >= 0.0 and not step.get("press", []).has(&"brake"):
				_set_action(&"brake", false)
			_cruise_forward = -1.0
			_cruise_reverse = -1.0
		if step.has("clutch_hold"):
			_clutch_hold = step.clutch_hold
		if step.has("steer_deg"):
			_steer_hold = true
			_steer_target_deg = step.steer_deg
		if step.get("steer_free", false):
			_steer_hold = false
			_set_action(&"steer_left", false)
			_set_action(&"steer_right", false)
		_step_index += 1
		_since_step = 0.0

	if _step_index >= steps.size():
		return
	# Cruise control: the accelerate key nose-first, the brake key (the
	# throttle in reverse) tail-first.
	if _cruise_forward >= 0.0:
		_set_action(&"accelerate", car.forward_speed < _cruise_forward)
	elif _cruise_reverse >= 0.0:
		_set_action(&"brake", -car.forward_speed < _cruise_reverse)
	# The clutch foot hovering at a point: the key tapped as the pedal passes it.
	if _clutch_hold >= 0.0:
		_set_action(&"clutch_pedal", car.clutch_pedal <= _clutch_hold)
	if test.kind == KIND_SKID_PAD and test.has("hold_radius") and _all_steps_done_at < 0.0:
		_drive_skid_pad(delta)
	if _steer_hold:
		_hold_steering()


## The skid pad's driver: holds the ring's radius. The wheel angle a circle
## of hold_radius takes at a walk (the rolling geometry, atan(wheelbase /
## radius), as steering wheel degrees through the rack) plus a correction
## for the radius error and its rate, then the keys tapped so the wheel
## hovers there (_hold_steering). A left-hand circle: positive.
func _drive_skid_pad(delta: float) -> void:
	var radius := _radius()
	var rate := (radius - _previous_radius) / delta
	var wanted: float = test.hold_radius
	var geometric_deg := rad_to_deg(atan(2.0 * ArcadeCar.AXLE_DISTANCE / wanted)) * ArcadeCar.STEERING_RATIO
	_steer_hold = true
	_steer_target_deg = clampf(geometric_deg + SKID_PAD_STEER_GAIN * (radius - wanted) + SKID_PAD_STEER_DAMPING * rate, 0.0, ArcadeCar.STEERING_WHEEL_LOCK_DEG)


## Taps the steering keys so the wheel hovers at _steer_target_deg: the left
## key while the wheel is short of a positive target (it returns to centre on
## its own when let go), the right key for a negative one.
func _hold_steering() -> void:
	var wheel := car.steering_wheel_deg
	if _steer_target_deg > 0.0:
		_set_action(&"steer_right", false)
		_set_action(&"steer_left", wheel < _steer_target_deg)
	elif _steer_target_deg < 0.0:
		_set_action(&"steer_left", false)
		_set_action(&"steer_right", wheel > _steer_target_deg)
	else:
		_set_action(&"steer_left", false)
		_set_action(&"steer_right", false)


func _conditions_met(when: Dictionary) -> bool:
	for key: String in when:
		var value: float = when[key]
		match key:
			"after":
				if _since_step < value:
					return false
			"speed_above":
				if _speed() < value:
					return false
			"speed_below":
				if _speed() > value:
					return false
			"travelled":
				if _travelled() < value:
					return false
			"rotation_deg":
				if rad_to_deg(_rotation) < value:
					return false
			"rotation_deg_below":
				if rad_to_deg(_rotation) > value:
					return false
			"z_below":
				if car.global_position.z > value:
					return false
			"z_above":
				if car.global_position.z < value:
					return false
			"x_below":
				if car.global_position.x > value:
					return false
			"x_above":
				if car.global_position.x < value:
					return false
			"stopped":
				if _speed() >= STOPPED_SPEED:
					return false
			"reversed":
				if _reversed < value:
					return false
			"swept_deg":
				if rad_to_deg(_swept) < value:
					return false
			_:
				push_error("LicenceExams: unknown step condition '%s'" % key)
				return false
	return true


func _set_action(action: StringName, pressed: bool) -> void:
	if _pressed.get(action, false) == pressed:
		return
	_pressed[action] = pressed
	if pressed:
		Input.action_press(action)
	else:
		Input.action_release(action)


func _release_all() -> void:
	for action in ACTIONS:
		Input.action_release(action)
	_pressed.clear()
	_cruise_forward = -1.0
	_cruise_reverse = -1.0
	_clutch_hold = -1.0
	_steer_hold = false


func _finish() -> void:
	finished = true
	if scripted:
		_release_all()


# --- Tracking ---------------------------------------------------------------------------

func _speed() -> float:
	return Vector2(car.velocity.x, car.velocity.z).length()


## Distance covered along the start heading [m].
func _travelled() -> float:
	return (car.global_position - _start_position).dot(_start_forward)


## The car's footprint's four corners on the ground (x and z; y is the car's).
func _corners() -> Array[Vector3]:
	var corners: Array[Vector3] = []
	for corner_x: float in [-1.0, 1.0]:
		for corner_z: float in [-1.0, 1.0]:
			corners.append(car.global_transform * Vector3(corner_x * TestPad.CAR_HALF_SIZE.x, 0.0, corner_z * TestPad.CAR_HALF_SIZE.y))
	return corners


## How far the worst corner of the car is inside an axis-aligned box
## {centre, size (x, z)} [m]; negative = that corner is outside.
func _box_margin(box: Dictionary) -> float:
	var half: Vector2 = box.size * 0.5
	var margin := INF
	for corner in _corners():
		var local: Vector3 = corner - box.centre
		margin = minf(margin, minf(half.x - absf(local.x), half.y - absf(local.z)))
	return margin


## The car's heading against the bay's axis, either way round [degrees].
func _bay_heading_error_deg() -> float:
	var axis := deg_to_rad(test.bay.get("heading_deg", 0.0))
	var error := rad_to_deg(angle_difference(axis, car.global_rotation.y))
	return minf(absf(error), absf(180.0 - absf(error)))


## Horizontal distance from the skid pad's centre [m] and the bearing of the
## car round it [rad].
func _radius() -> float:
	var centre: Vector3 = test.circle.centre
	return Vector2(car.global_position.x - centre.x, car.global_position.z - centre.z).length()


func _bearing() -> float:
	var centre: Vector3 = test.circle.centre
	return atan2(car.global_position.z - centre.z, car.global_position.x - centre.x)


## The tick's bookkeeping: rotation, distances nose- and tail-first,
## direction changes, and the bounds of the course.
func _track(delta: float) -> void:
	var yaw := car.global_rotation.y
	_rotation += angle_difference(_previous_yaw, yaw)
	_previous_yaw = yaw
	var moved := car.global_position - _previous_position
	var way := Vector2(moved.x, moved.z).length()
	_previous_position = car.global_position
	if car.forward_speed < 0.0:
		_reversed += way
	else:
		_forward_travel += way
	_peak_speed = maxf(_peak_speed, _speed())
	var speed := car.forward_speed
	if absf(speed) > STOPPED_SPEED:
		var direction := 1 if speed > 0.0 else -1
		if _leg_direction != 0 and direction != _leg_direction:
			_direction_changes += 1
		_leg_direction = direction
	match test.kind:
		KIND_HILL_START:
			_track_hill_start()
		KIND_TURN:
			_track_bounds_turn()
		KIND_REVERSE_COURSE:
			_track_bounds_reverse_course()
		KIND_EMERGENCY_STOP:
			if not _cue_given and car.global_position.z <= test.course.cue_z:
				_cue_given = true
				_cue_speed = _speed()
		KIND_SKID_PAD:
			_track_skid_pad(delta)


func _track_hill_start() -> void:
	var hill: Dictionary = test.hill
	if not car.engine_running:
		_hill_stalled = true
	if not _hill_stopped:
		if _speed() < STOPPED_SPEED and _box_margin(hill.hold_box) >= 0.0:
			_hill_stopped = true
			_hill_stop_z = car.global_position.z
		return
	# Rolled back: down the hill is +z (the ramp climbs towards -z).
	_hill_roll_back = maxf(_hill_roll_back, car.global_position.z - _hill_stop_z)
	var standing := _speed() < STOPPED_SPEED
	if standing and car._handbrake_amount > 0.0 and car.brake_pedal <= 0.0:
		_hill_handbrake_held = true
	if standing and _hill_handbrake_held and car.clutch_pedal >= HILL_CLUTCH_FLOOR:
		_hill_clutch_floored = true
	if not _hill_crested and car.global_position.z <= hill.crest_z:
		_hill_crested = true
		_hill_crest_speed = car.forward_speed


## The turn's stretch: every corner between the lane's edge lines and the
## two bars, every tick.
func _track_bounds_turn() -> void:
	var stretch: Dictionary = test.stretch
	var half_length: float = stretch.length * 0.5
	for corner in _corners():
		var out := maxf(absf(corner.x) - stretch.lane_half_width, absf(corner.z - stretch.centre_z) - half_length)
		if out > 0.0:
			_left_bounds = true
			_worst_excursion = maxf(_worst_excursion, out)


## The reversing lane: while a corner is between the lane's ends it must be
## between its lines.
func _track_bounds_reverse_course() -> void:
	var lane: Dictionary = test.course.lane
	var half: Vector2 = lane.size * 0.5
	for corner in _corners():
		var local: Vector3 = corner - lane.centre
		if absf(local.z) > half.y:
			continue
		var out := absf(local.x) - half.x
		if out > 0.0:
			_left_bounds = true
			_worst_excursion = maxf(_worst_excursion, out)


## The skid ring: the angle swept round the centre, and every corner between
## the two rings every tick.
func _track_skid_pad(_delta: float) -> void:
	var bearing := _bearing()
	_swept += absf(angle_difference(_previous_bearing, bearing))
	_previous_bearing = bearing
	_previous_radius = _radius()
	var circle: Dictionary = test.circle
	var centre: Vector3 = circle.centre
	for corner in _corners():
		var r := Vector2(corner.x - centre.x, corner.z - centre.z).length()
		var out := maxf(circle.inner_radius - r, r - circle.outer_radius)
		if out > 0.0:
			_left_bounds = true
			_worst_excursion = maxf(_worst_excursion, out)
	if _laps_done_at < 0.0 and rad_to_deg(_swept) >= 360.0 * test.laps:
		_laps_done_at = elapsed


## The quiz: the digit keys answer the card up; a wrong answer or a question
## timed out fails the element at once.
func _track_quiz(delta: float) -> void:
	var questions: Array = test.questions
	if _question_index >= questions.size() or _quiz_failed:
		return
	_question_time += delta
	var answered := 0
	for i in ANSWER_ACTIONS.size():
		if Input.is_action_just_pressed(ANSWER_ACTIONS[i]):
			answered = i + 1
			break
	if answered == 0:
		if _question_time >= QUIZ_QUESTION_TIME:
			_answers.append(0)
			_quiz_failed = true
		return
	_answers.append(answered)
	var question: Dictionary = questions[_question_index]
	if answered != question.correct:
		_quiz_failed = true
		return
	_question_index += 1
	_question_time = 0.0


## A human run is complete when its kind says so; a scripted one when the
## script has run out (the steps end at the finish).
func _is_complete() -> bool:
	if scripted:
		return true
	match test.kind:
		KIND_QUIZ:
			var questions: Array = test.questions
			return _question_index >= questions.size()
		KIND_PARK:
			return _speed() < STOPPED_SPEED and _box_margin(test.bay) >= 0.0 and _forward_travel + _reversed > 1.0
		KIND_HILL_START:
			return _hill_crested and _speed() < STOPPED_SPEED
		KIND_TURN:
			return _direction_changes >= TURN_MIN_DIRECTION_CHANGES and _speed() < STOPPED_SPEED and absf(rad_to_deg(angle_difference(_start_yaw + PI, car.global_rotation.y))) <= TURN_HEADING_TOLERANCE_DEG
		KIND_REVERSE_COURSE:
			return _reversed >= REVERSE_COURSE_MIN_DISTANCE and _speed() < STOPPED_SPEED
		KIND_EMERGENCY_STOP:
			return _cue_given and _speed() < STOPPED_SPEED
		_:
			return _laps_done_at >= 0.0


## What ends a run before its finish: a verdict that is already in (a wrong
## answer, a stall, a cone down, a line crossed): the sitting is failed at
## once (the rigor rule), no point driving on.
func _failed_already() -> bool:
	match test.kind:
		KIND_QUIZ:
			return _quiz_failed
		KIND_HILL_START:
			return _hill_stalled or _hill_roll_back > HILL_ROLL_BACK_TOLERANCE
		KIND_TURN, KIND_REVERSE_COURSE, KIND_SKID_PAD:
			return _left_bounds or _cones_hit() > 0
		KIND_PARK, KIND_EMERGENCY_STOP:
			return _cones_hit() > 0
	return false


## Cones of the element's group the car has knocked over.
func _cones_hit() -> int:
	if pad == null:
		return 0
	var group: StringName = &""
	match test.kind:
		KIND_PARK:
			group = test.bay.group
		KIND_REVERSE_COURSE, KIND_EMERGENCY_STOP:
			group = test.course.group
		KIND_SKID_PAD:
			return pad.get_toppled_count(test.circle.inner_group) + pad.get_toppled_count(test.circle.outer_group)
	if group == &"":
		return 0
	return pad.get_toppled_count(group)


# --- Verdicts ---------------------------------------------------------------------------

func _judge_quiz(checks: Array[Dictionary], metrics: Dictionary) -> void:
	var questions: Array = test.questions
	metrics["answered"] = "%d/%d" % [_question_index, questions.size()]
	var wrong := ""
	if _quiz_failed and _question_index < questions.size():
		var question: Dictionary = questions[_question_index]
		var given: int = _answers[_question_index] if _question_index < _answers.size() else 0
		wrong = "question %d answered %s, the answer is %d" % [_question_index + 1, str(given) if given > 0 else "nothing in time", question.correct]
	checks.append({"label": "every question answered right%s" % ("" if wrong == "" else " (%s)" % wrong), "passed": not _quiz_failed and _question_index >= questions.size()})


func _judge_park(checks: Array[Dictionary], metrics: Dictionary) -> void:
	var bay: Dictionary = test.bay
	var margin := _box_margin(bay)
	var heading_error := _bay_heading_error_deg()
	var speed := _speed()
	var cones := _cones_hit()
	# The clearances, from the car's footprint to the lines: the ends and the
	# sides of the bay (the kerb is the right side of the parallel bay).
	var half: Vector2 = bay.size * 0.5
	var end_clearance := INF
	var side_clearance := INF
	for corner in _corners():
		var local: Vector3 = corner - bay.centre
		end_clearance = minf(end_clearance, half.y - absf(local.z))
		side_clearance = minf(side_clearance, half.x - absf(local.x))
	metrics["margin_m"] = snappedf(margin, 0.01)
	metrics["end_clearance_m"] = snappedf(end_clearance, 0.01)
	metrics["side_clearance_m"] = snappedf(side_clearance, 0.01)
	metrics["heading_error_deg"] = snappedf(heading_error, 0.1)
	metrics["reversed_m"] = snappedf(_reversed, 0.1)
	metrics["cones_hit"] = cones
	checks.append({"label": "stopped (%.2f m/s)" % speed, "passed": speed < STOPPED_SPEED})
	checks.append({"label": "whole car inside the bay's lines (margin %.2f m)" % margin, "passed": margin >= 0.0})
	checks.append({"label": "straight in the bay, within %.0f deg (%.1f)" % [PARK_HEADING_TOLERANCE_DEG, heading_error], "passed": heading_error <= PARK_HEADING_TOLERANCE_DEG})
	checks.append({"label": "no cone knocked over (%d)" % cones, "passed": cones == 0})
	var min_reverse: float = test.get("min_reverse_m", 0.0)
	if min_reverse > 0.0:
		checks.append({"label": "reversed into it, %.0f m or more tail-first (%.1f)" % [min_reverse, _reversed], "passed": _reversed >= min_reverse})


func _judge_hill_start(checks: Array[Dictionary], metrics: Dictionary) -> void:
	metrics["roll_back_m"] = snappedf(_hill_roll_back, 0.001)
	metrics["stop_z_m"] = snappedf(_hill_stop_z, 0.01)
	metrics["crest_speed_ms"] = snappedf(_hill_crest_speed, 0.1)
	metrics["stalled"] = _hill_stalled
	checks.append({"label": "stopped inside the hold box on the hill", "passed": _hill_stopped})
	checks.append({"label": "held on the handbrake, foot off the brake", "passed": _hill_handbrake_held})
	checks.append({"label": "clutch pedal to the floor while held", "passed": _hill_clutch_floored})
	checks.append({"label": "rolled back no more than %.0f cm (%.1f cm)" % [HILL_ROLL_BACK_TOLERANCE * 100.0, _hill_roll_back * 100.0], "passed": _hill_roll_back <= HILL_ROLL_BACK_TOLERANCE})
	checks.append({"label": "no stall", "passed": not _hill_stalled})
	checks.append({"label": "over the crest at %.1f m/s or more (%.1f)" % [HILL_MIN_CREST_SPEED, _hill_crest_speed], "passed": _hill_crested and _hill_crest_speed >= HILL_MIN_CREST_SPEED})


func _judge_turn(checks: Array[Dictionary], metrics: Dictionary) -> void:
	var heading_error := absf(rad_to_deg(angle_difference(_start_yaw + PI, car.global_rotation.y)))
	var speed := _speed()
	metrics["direction_changes"] = _direction_changes
	metrics["reversed_m"] = snappedf(_reversed, 0.1)
	metrics["heading_error_deg"] = snappedf(heading_error, 0.1)
	metrics["worst_excursion_m"] = snappedf(_worst_excursion, 0.01)
	checks.append({"label": "every wheel inside the lane and between the bars throughout (worst %.2f m out)" % _worst_excursion, "passed": not _left_bounds})
	checks.append({"label": "%d to %d direction changes (%d)" % [TURN_MIN_DIRECTION_CHANGES, TURN_MAX_DIRECTION_CHANGES, _direction_changes], "passed": _direction_changes >= TURN_MIN_DIRECTION_CHANGES and _direction_changes <= TURN_MAX_DIRECTION_CHANGES})
	checks.append({"label": "reversed %.0f m or more (%.1f)" % [TURN_MIN_REVERSE_M, _reversed], "passed": _reversed >= TURN_MIN_REVERSE_M})
	checks.append({"label": "facing back the way it came, within %.0f deg (%.1f)" % [TURN_HEADING_TOLERANCE_DEG, heading_error], "passed": heading_error <= TURN_HEADING_TOLERANCE_DEG})
	checks.append({"label": "stopped (%.2f m/s)" % speed, "passed": speed < STOPPED_SPEED})


func _judge_reverse_course(checks: Array[Dictionary], metrics: Dictionary) -> void:
	var margin := _box_margin(test.course.end_box)
	var speed := _speed()
	var cones := _cones_hit()
	metrics["reversed_m"] = snappedf(_reversed, 0.1)
	metrics["end_box_margin_m"] = snappedf(margin, 0.01)
	metrics["worst_excursion_m"] = snappedf(_worst_excursion, 0.01)
	metrics["cones_hit"] = cones
	checks.append({"label": "every wheel between the lines all the way (worst %.2f m over)" % _worst_excursion, "passed": not _left_bounds})
	checks.append({"label": "no cone knocked over (%d)" % cones, "passed": cones == 0})
	checks.append({"label": "reversed %.0f m or more (%.1f)" % [REVERSE_COURSE_MIN_DISTANCE, _reversed], "passed": _reversed >= REVERSE_COURSE_MIN_DISTANCE})
	checks.append({"label": "whole car inside the end box (margin %.2f m)" % margin, "passed": margin >= 0.0})
	checks.append({"label": "stopped (%.2f m/s)" % speed, "passed": speed < STOPPED_SPEED})


func _judge_emergency_stop(checks: Array[Dictionary], metrics: Dictionary) -> void:
	var zone: Dictionary = test.course.zone
	var margin := _box_margin(zone)
	var speed := _speed()
	var cones := _cones_hit()
	var stop_distance: float = car.global_position.z - test.course.cue_z
	metrics["cue_speed_kmh"] = snappedf(_cue_speed * 3.6, 0.1)
	metrics["zone_margin_m"] = snappedf(margin, 0.01)
	metrics["stop_distance_m"] = snappedf(-stop_distance, 0.1)
	metrics["cones_hit"] = cones
	checks.append({"label": "%.0f km/h or more at the bar (%.1f)" % [EMERGENCY_MIN_SPEED * 3.6, _cue_speed * 3.6], "passed": _cue_given and _cue_speed >= EMERGENCY_MIN_SPEED})
	checks.append({"label": "stopped (%.2f m/s)" % speed, "passed": speed < STOPPED_SPEED})
	checks.append({"label": "whole car inside the zone (margin %.2f m)" % margin, "passed": margin >= 0.0})
	checks.append({"label": "no cone knocked over (%d)" % cones, "passed": cones == 0})


func _judge_skid_pad(checks: Array[Dictionary], metrics: Dictionary) -> void:
	var cones := _cones_hit()
	metrics["laps"] = snappedf(rad_to_deg(_swept) / 360.0, 0.01)
	metrics["laps_time_s"] = snappedf(_laps_done_at, 0.01) if _laps_done_at >= 0.0 else -1.0
	metrics["worst_excursion_m"] = snappedf(_worst_excursion, 0.01)
	metrics["peak_speed_kmh"] = snappedf(_peak_speed * 3.6, 0.1)
	metrics["cones_hit"] = cones
	checks.append({"label": "%.0f laps between the rings (%.2f)" % [test.laps, rad_to_deg(_swept) / 360.0], "passed": _laps_done_at >= 0.0})
	checks.append({"label": "every wheel between the rings throughout (worst %.2f m out)" % _worst_excursion, "passed": not _left_bounds})
	checks.append({"label": "no cone knocked over (%d)" % cones, "passed": cones == 0})
	checks.append({"label": "laps done inside %.0f s (%.1f)" % [SKID_PAD_TIME_LIMIT, _laps_done_at], "passed": _laps_done_at >= 0.0 and _laps_done_at <= SKID_PAD_TIME_LIMIT})
