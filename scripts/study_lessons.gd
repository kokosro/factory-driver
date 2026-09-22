class_name StudyLessons
extends RefCounted
## THE STUDY's catalogue: the driving school's lessons, every one a live
## demonstration by a scripted driver on the real car with every input on
## show (scripts/study.gd runs them, scripts/hud.gd shows the inputs). A
## lesson is plain data:
##   id, title, objective   what the garage's STUDY page lists,
##   group                  which heading it sits under (GROUPS),
##   source, pilot          where its scripted drive comes from and its name:
##     SOURCE_HANDLING  a handling test's own scripted driver
##                      (HandlingTests.all_tests(), by test name),
##     SOURCE_EXAM      a licence exam element's own scripted driver
##                      (LicenceExams.l0_sitting() / skid_pad_test(), by
##                      element name),
##     SOURCE_STUDY     a pilot of this file's own (lesson_pilots(), by
##                      name), written in LicenceExams' tests-as-data idiom
##                      with KIND_LESSON: a scripted drive with nothing to
##                      judge, whose steps carry a "say" line each,
##   captions               for a reused pilot: {step: the index of the step
##                          that fired, say: the line} - a caption overlay on
##                          the test's own data, which is used as it is and
##                          never copied or changed,
##   dashboard              optional, what the instructor sets the car's
##                          switches to before the drive (the keys of
##                          OdometerStore.DRIVER_DEFAULTS but the camera view;
##                          the aids on, sport, automatic where unsaid),
##   coming_soon            true for a lesson that has no honest demonstration
##                          yet: listed, greyed, not startable. The reason is
##                          in `objective`.
## The handling tests' and the exam elements' definitions ARE lesson scripts:
## pilot_for() hands them back as they are, so a walkthrough of the 180 is
## the certified 180 driven in front of you, and a change to a test is a
## change to its lesson. Every lesson can be watched any time, as often as
## wanted; nothing here records or judges anything.

const SOURCE_HANDLING := &"handling"
const SOURCE_EXAM := &"exam"
const SOURCE_STUDY := &"study"

## The headings the STUDY page groups the lessons under, in order.
const GROUPS: Array[String] = ["BASICS", "AIDS ON AND OFF", "MANOEUVRES", "TEST WALKTHROUGHS", "THE WORLD"]

## Every key a lesson pilot may press, released when a lesson ends: the
## exam runner's own (LicenceExams.ACTIONS) plus the dashboard keys the
## lessons here work - the gearbox, the aid switches, the starter.
const LESSON_ACTIONS: Array[StringName] = [
	&"accelerate", &"brake", &"steer_left", &"steer_right", &"handbrake", &"clutch_pedal",
	&"shift_up", &"shift_down", &"toggle_gearbox", &"gearbox_mode",
	&"tcs_toggle", &"abs_toggle", &"sc_toggle", &"starter",
]

## A tap of a dashboard key [s]: pressed, and let go this much later (the
## car reads its keys on the press).
const TAP_TIME := 0.1

## Steering lesson: how long each way is held and how long the wheel is
## left to come back [s], at a walk [m/s]. Measured at the walk (the cruise
## holds it): let go at full lock, the caster has the wheel at 15 degrees
## after the 1.5 s and at centre in 2.1 s (ArcadeCar CASTER_RETURN_RATE_MAX
## at 0.58 of its rate at 5 m/s); the stop comes with 7 degrees still on
## the wheel, which stay there standing.
const STEERING_HOLD_TIME := 2.5
const STEERING_RETURN_TIME := 1.5
const STEERING_WALK_SPEED := 5.0

## Manual gears lesson: the road speeds the driver changes up at in 1st and
## 2nd [m/s]: the shift light (ArcadeCar.SHIFT_LIGHT_RPM, 6500 rpm) comes on
## at 14.8 m/s in 1st and 26.1 in 2nd on the certified ratios (measured:
## 6356 rpm at 14.5 m/s in 1st, 5135 at 20.6 in 2nd); how long the car is
## left on the overrun in 3rd before the brake [s]; and the speed the box is
## taken back down a gear at on the way to the stop [m/s] (2340 rpm in 3rd,
## ~3700 in 2nd).
const GEARS_SHIFT_1_2_SPEED := 14.8
const GEARS_SHIFT_2_3_SPEED := 26.0
const GEARS_OVERRUN_TIME := 2.0
const GEARS_DOWNSHIFT_SPEED := 14.0

## Stall lesson: how long the engine idles with the clutch on the floor [s]
## before the stall (the smoke test's recipe: the pedal let go as the
## throttle goes down, so the clutch is home before the revs are up and the
## car's own load drags the engine under STALL_RPM); how long the stall is
## left to be seen [s]; how long the revs are raised before the pull-away
## (the hill start's HILL_REV_TIME) [s]; and how long it drives before the
## stop [s].
const STALL_IDLE_TIME := 1.5
const STALL_SHOW_TIME := 2.0
const STALL_REV_TIME := 0.35
const STALL_PULL_AWAY_TIME := 3.0

## Drive modes lesson: the speed each program is shown to [m/s] (72 km/h:
## sport has changed up twice by then, comfort three times).
const MODES_SHOW_SPEED := 20.0

## TCS lesson: the speed each launch is taken to [m/s].
const TCS_LAUNCH_SPEED := 15.0

## ABS lesson: the speed each stop is made from [m/s] (80 km/h).
const ABS_STOP_SPEED := 22.0

## SC lesson: the speed the flick is made at [m/s] (60 km/h), and how long
## the lock and the handbrake are held [s].
const SC_FLICK_SPEED := 16.5
const SC_FLICK_TIME := 0.5

## Tyre wear lesson: how long the rears are spun on full lock [s] (the wear
## test's donut has them over the window's 110 C in ~18 s).
const TYRE_WEAR_SPIN_TIME := 22.0

## Donut lesson: how long the car is spun round its nose [s].
const DONUT_SPIN_TIME := 9.0


# =============================================================================
#  The catalogue
# =============================================================================

## Every lesson, in the order the STUDY page lists them, grouped by `group`
## in GROUPS' order.
static func catalogue() -> Array[Dictionary]:
	return [
		# --- BASICS ------------------------------------------------------------
		{
			"id": "steering", "group": "BASICS", "title": "STEERING",
			# was "... let go it comes back to centre" -> the caster's, on the
			# move (the user's verdict, 15:24).
			"objective": "The 900-degree wheel: a held key winds it on at hand speed; let go on the move, the caster brings it back to centre - standing still it stays put. The nose follows the front tyres.",
			"source": SOURCE_STUDY, "pilot": "STEERING",
		},
		{
			"id": "manual_gears", "group": "BASICS", "title": "MANUAL GEAR CHANGES",
			"objective": "E and Q move the box a gear at a time; the clutch opens for the change and catches the next gear, up at the shift light, down on the way to a stop.",
			"source": SOURCE_STUDY, "pilot": "MANUAL_GEARS",
		},
		{
			"id": "stall", "group": "BASICS", "title": "STALL AND RECOVERY",
			"objective": "The clutch let up as the throttle goes down drags the engine under 450 rpm and stalls it; clutch down, starter, revs up first, then the clutch, and away.",
			"source": SOURCE_STUDY, "pilot": "STALL_RECOVERY",
		},
		{
			"id": "drive_modes", "group": "BASICS", "title": "DRIVE MODES: SPORT, COMFORT, ECO",
			"objective": "The same full throttle three times: sport holds a gear to 6800 rpm, comfort changes up at 2800, eco at 2000 and caps the throttle.",
			"source": SOURCE_STUDY, "pilot": "DRIVE_MODES",
		},
		{
			"id": "tyre_wear", "group": "BASICS", "title": "HOW TYRES WEAR",
			"objective": "Tyre wear is the heat put into the rubber, three times over past 110 C: spinning rears on full lock cook themselves; watch TYRES and the wear readout.",
			"source": SOURCE_STUDY, "pilot": "TYRE_WEAR", "dashboard": {"tcs_on": false, "sc_on": false},
		},
		# --- AIDS ON AND OFF ----------------------------------------------------
		{
			"id": "tcs", "group": "AIDS ON AND OFF", "title": "TCS ON / OFF",
			"objective": "Full throttle from rest twice: with TCS the clutch feathers and the rears are held at 25 % slip; without it the clutch is dumped and they spin.",
			"source": SOURCE_STUDY, "pilot": "TCS_ON_OFF",
		},
		{
			"id": "abs", "group": "AIDS ON AND OFF", "title": "ABS ON / OFF",
			"objective": "A full pedal from 80 km/h twice: with ABS the fronts are held just short of locking; without it they lock, the stop is longer and the car does not steer.",
			"source": SOURCE_STUDY, "pilot": "ABS_ON_OFF",
		},
		{
			"id": "sc", "group": "AIDS ON AND OFF", "title": "SC ON / OFF",
			"objective": "The same flick of lock and handbrake at 60 km/h twice: with SC the slide is damped and the car straightens after 79 degrees; without it the slide hangs on, 153 degrees, and the car ends up backwards.",
			"source": SOURCE_STUDY, "pilot": "SC_ON_OFF",
		},
		# --- MANOEUVRES ----------------------------------------------------------
		{
			"id": "slalom", "group": "MANOEUVRES", "title": "SLALOM",
			"objective": "The 14 cones at 36 km/h: turn in 9 m before each cone, hold the lock until the nose points 19 degrees across, straight to the next.",
			"source": SOURCE_HANDLING, "pilot": "SLALOM_TEST",
			"captions": [
				{"step": 0, "say": "Turn in before the first cone: full lock, held until the nose points 19 degrees across the line."},
				{"step": 1, "say": "Lock off: the yaw momentum carries the nose the rest of the way. Straight to the next turn-in."},
				{"step": 2, "say": "The other way. Every swing is timed by distance: 9 m before drawing level with the cone."},
			],
		},
		{
			"id": "parallel_park", "group": "MANOEUVRES", "title": "PARALLEL PARKING",
			"objective": "Past the bay on the right, full right lock wound on standing, tail-first in until the car has swung 37 degrees, full left lock until straight, stop.",
			"source": SOURCE_EXAM, "pilot": "PARALLEL_PARK",
			"captions": [
				{"step": 1, "say": "Drive past the bay at a walk and stop alongside it."},
				{"step": 3, "say": "Reverse: a fresh press of the brake key at the standstill selects it. Full right lock wound on before moving."},
				{"step": 4, "say": "Tail-first at 2 m/s: the tail swings into the bay."},
				{"step": 5, "say": "At 37 degrees: full left lock brings the nose in after it."},
				{"step": 6, "say": "Nearly straight: lock off, and the accelerate key is the brake in reverse."},
			],
		},
		{
			"id": "bay_park", "group": "MANOEUVRES", "title": "BAY PARKING",
			"objective": "Along the aisle at a walk, full right lock at the turn-in point, let the wheel go 7 degrees short of square, brake at depth: whole car inside the lines.",
			"source": SOURCE_EXAM, "pilot": "BAY_PARK",
			"captions": [
				{"step": 1, "say": "Along the aisle at 3 m/s."},
				{"step": 2, "say": "Turn-in: full right lock 4.5 m before the bay's axis - the car ends that far past where the lock goes on."},
				{"step": 3, "say": "Lock off 7 degrees short of square: the returning wheel finishes the turn."},
				{"step": 4, "say": "Brake at depth: it stops 0.6 m on, inside the lines."},
			],
		},
		{
			"id": "hill_start", "group": "MANOEUVRES", "title": "HILL START",
			"objective": "Stop in the box on the 8 % ramp, handbrake on before the foot leaves the brake, clutch to the floor, revs up, lever and clutch let go together: no roll-back, no stall.",
			"source": SOURCE_EXAM, "pilot": "HILL_START",
			"captions": [
				{"step": 1, "say": "Up the ramp at 5 m/s, brake for the hold box."},
				{"step": 2, "say": "Stopped: the handbrake goes on BEFORE the foot comes off the brake (a fresh brake press standing would be reverse)."},
				{"step": 3, "say": "Foot off the brake, clutch to the floor: the lever holds the car."},
				{"step": 4, "say": "Revs up on the clutch."},
				{"step": 5, "say": "Lever and clutch let go together: the pedal comes up through the bite as the rears are freed. Roll-back under a centimetre."},
				{"step": 6, "say": "Over the crest, and a stop."},
			],
		},
		{
			"id": "three_point_turn", "group": "MANOEUVRES", "title": "THREE-POINT TURN",
			"objective": "Full left lock forward to 80 degrees, full right lock backwards to 145, full left forward to 172: facing back the way you came inside the lane.",
			"source": SOURCE_EXAM, "pilot": "TURN_IN_ROAD",
			"captions": [
				{"step": 0, "say": "Full left lock, forward at 3 m/s."},
				{"step": 1, "say": "80 degrees round: stop before the lane's edge."},
				{"step": 3, "say": "Reverse, full right lock: the second point."},
				{"step": 4, "say": "145 degrees: stop again."},
				{"step": 6, "say": "Forward on full left lock: the third point, to 172 degrees, and stop facing back."},
			],
		},
		{
			"id": "reversing", "group": "MANOEUVRES", "title": "REVERSING A LANE",
			"objective": "Tail-first up the 3.2 m lane at 3 m/s through the two cone gates into the end box: every corner between the lines the whole way.",
			"source": SOURCE_EXAM, "pilot": "REVERSING_COURSE",
			"captions": [
				{"step": 0, "say": "A moment with nothing pressed, then a fresh brake press: reverse. The brake key is the throttle now."},
				{"step": 1, "say": "At the end box: the accelerate key is the brake in reverse."},
				{"step": 2, "say": "Standing - the key comes off at once, or held it would select forward and drive off."},
			],
		},
		{
			"id": "emergency_stop", "group": "MANOEUVRES", "title": "EMERGENCY STOP",
			"objective": "54 km/h at the red bar, then the pedal to the floor: with ABS the fronts stay just short of locking and the car stops 13 m on, inside the zone.",
			"source": SOURCE_EXAM, "pilot": "EMERGENCY_STOP",
			"captions": [
				{"step": 0, "say": "Down the lane at 54 km/h towards the red bar."},
				{"step": 1, "say": "STOP: full pedal at the bar. ABS holds the fronts at 15 % slip; 13 m to a standstill."},
			],
		},
		{
			"id": "skid_pad", "group": "MANOEUVRES", "title": "SKID PAD CIRCLE",
			"objective": "Two laps between the cone rings at 43 km/h holding a 28 m radius: the wheel angle the radius takes, plus a correction on the radius error.",
			"source": SOURCE_EXAM, "pilot": "SKID_PAD",
			"captions": [
				{"step": 0, "say": "Up to 12 m/s and round: the steering keys are tapped so the wheel hovers at the angle a 28 m circle takes."},
				{"step": 1, "say": "Two laps done: lock off, brake."},
			],
		},
		{
			"id": "donuts", "group": "MANOEUVRES", "title": "DONUTS",
			"objective": "TCS and SC off, full left lock, full throttle from rest: the rears spin, the tail comes round and the car circles its own nose.",
			"source": SOURCE_STUDY, "pilot": "DONUTS", "dashboard": {"tcs_on": false, "sc_on": false},
		},
		{
			"id": "drifting", "group": "MANOEUVRES", "title": "DRIFTING",
			"objective": "Coming soon: a held powerslide with countersteer needs a pilot that reads the slide and answers it tick by tick; the on / off keys of the tests-as-data idiom are not enough yet.",
			"source": SOURCE_STUDY, "pilot": "", "coming_soon": true,
		},
		{
			"id": "quick_turn", "group": "MANOEUVRES", "title": "QUICK TURN",
			"objective": "Coming soon: which manoeuvre a quick turn is (an evasive swerve, a U-turn under power) is not settled yet, so there is no honest demonstration to give.",
			"source": SOURCE_STUDY, "pilot": "", "coming_soon": true,
		},
		# --- TEST WALKTHROUGHS ------------------------------------------------------
		{
			"id": "spin_180", "group": "TEST WALKTHROUGHS", "title": "180 SPIN",
			"objective": "Handling test 2 as the certified driver drives it: 90 km/h, lock and handbrake together, lock off at 155 degrees, brake, and back to the start.",
			"source": SOURCE_HANDLING, "pilot": "SPIN_180",
			"captions": [
				{"step": 0, "say": "Full throttle down the straight to 90 km/h."},
				{"step": 1, "say": "Off the throttle, full left lock and the handbrake together: the locked rears let the tail step out."},
				{"step": 2, "say": "155 degrees round: lock off. The car rolls backwards, the locked rears leading like the head of a dart."},
				{"step": 3, "say": "Half a second to settle, then the brake."},
				{"step": 4, "say": "Stopped, facing the start: handbrake and brake off, throttle, and back up the road."},
				{"step": 5, "say": "A dab of right lock points the nose at the start."},
				{"step": 7, "say": "36 m out: on the brakes, to pull up on the start point."},
			],
		},
		{
			"id": "spin_360", "group": "TEST WALKTHROUGHS", "title": "360 SPIN",
			"objective": "Handling test 3 as the certified driver drives it: 125 km/h, lock and handbrake, opposite lock through the back half, handbrake off past half way, on to the 400 m board.",
			"source": SOURCE_HANDLING, "pilot": "SPIN_360",
			"captions": [
				{"step": 0, "say": "Full throttle to 125 km/h."},
				{"step": 1, "say": "Off the throttle, full left lock and the handbrake: the tail steps out."},
				{"step": 2, "say": "120 degrees: opposite lock while the car travels backwards."},
				{"step": 3, "say": "160 degrees: handbrake off, so the rears stop fighting the rotation."},
				{"step": 4, "say": "270 degrees: steer back in as the nose comes round."},
				{"step": 5, "say": "350 degrees: lock off."},
				{"step": 6, "say": "Nose-first again: back on the power, a dab of right lock at the goal, and over the 400 m line."},
			],
		},
		{
			"id": "stop_box", "group": "TEST WALKTHROUGHS", "title": "STOP BOX",
			"objective": "Handling test 4 as the certified driver drives it: hold 90 km/h to the braking point 36 m before the box's centre, then the full pedal to a standstill inside it.",
			"source": SOURCE_HANDLING, "pilot": "STOP_BOX",
			"captions": [
				{"step": 0, "say": "36 m before the box's centre: the full pedal. The front tyres stop at their limit under ABS; 8.7 m/s^2 all in."},
				{"step": 1, "say": "Standing, inside the box: the run is watched a moment more, then judged."},
			],
		},
		{
			"id": "reverse_180", "group": "TEST WALKTHROUGHS", "title": "REVERSE 180: THE J-TURN",
			"objective": "Handling test 5 as the certified driver drives it: reverse to 41 km/h, lift and flick, select forward as the nose comes round, catch it with opposite lock, on to the 100 m board.",
			"source": SOURCE_HANDLING, "pilot": "REVERSE_180",
			"captions": [
				{"step": 0, "say": "A fresh brake press standing: reverse. The brake key is the throttle, tail-first down the straight."},
				{"step": 1, "say": "41 km/h: lift and full left lock. The front of a reversing car trails, so once it steps out it swings all the way round."},
				{"step": 2, "say": "140 degrees: opposite lock against the rotation, and the accelerate key selects forward as the car rolls nose-first."},
				{"step": 3, "say": "170 degrees: lock off."},
				{"step": 4, "say": "Up to speed: a dab of left lock points the nose at the goal, over the 100 m line on the power."},
			],
		},
		# --- THE WORLD -----------------------------------------------------------------
		{
			"id": "traffic_rules", "group": "THE WORLD", "title": "TRAFFIC RULES",
			"objective": "Coming soon: needs roads, junctions and other traffic (the 4C world); the test pad has none.",
			"source": SOURCE_STUDY, "pilot": "", "coming_soon": true,
		},
		{
			"id": "traffic_lights", "group": "THE WORLD", "title": "TRAFFIC LIGHTS",
			"objective": "Coming soon: needs junctions with lights (the 4C world); the test pad has none.",
			"source": SOURCE_STUDY, "pilot": "", "coming_soon": true,
		},
	]


## The lesson with `id`, or empty.
static func lesson(id: String) -> Dictionary:
	for entry in catalogue():
		if entry.id == id:
			return entry
	return {}


## The scripted drive `entry` runs: the test's, the element's or this file's
## own definition, as it is (never a copy). Empty for a coming-soon lesson or
## a name nothing has.
static func pilot_for(entry: Dictionary) -> Dictionary:
	if entry.get("coming_soon", false):
		return {}
	var name := String(entry.get("pilot", ""))
	match entry.get("source", &""):
		SOURCE_HANDLING:
			for test in HandlingTests.all_tests():
				if test.name == name:
					return test
		SOURCE_EXAM:
			var elements := LicenceExams.l0_sitting()
			elements.append(LicenceExams.skid_pad_test())
			for element in elements:
				if element.name == name:
					return element
		SOURCE_STUDY:
			for pilot in lesson_pilots():
				if pilot.name == name:
					return pilot
	return {}


## The caption for a run that has fired `steps_fired` steps: the "say" of
## the last step fired that has one (a lesson pilot's own steps), or the
## caption overlay's line for the last step at or before it (a reused
## pilot); a step nobody says anything for keeps the line before it. Before
## any step fires, the lesson's objective.
static func caption_for(entry: Dictionary, definition: Dictionary, steps_fired: int) -> String:
	if steps_fired <= 0:
		return String(entry.get("objective", ""))
	var last := steps_fired - 1
	var steps: Array = definition.get("steps", [])
	for index in range(mini(last, steps.size() - 1), -1, -1):
		if steps[index].has("say"):
			return String(steps[index].say)
	var said := String(entry.get("objective", ""))
	for caption: Dictionary in entry.get("captions", []):
		if int(caption.step) <= last:
			said = String(caption.say)
	return said


# =============================================================================
#  The pilots of this file's own
# =============================================================================

## Every lesson pilot written here, LicenceExams' KIND_LESSON. The car
## starts on its spawn point facing down the straight unless a pilot says
## otherwise; the instructor's dashboard (the aids on, sport, automatic) is
## the study's to set before the run, and a pilot that wants the manual box
## says "manual": true as the hill start does.
static func lesson_pilots() -> Array[Dictionary]:
	return [steering_pilot(), manual_gears_pilot(), stall_recovery_pilot(), drive_modes_pilot(), tyre_wear_pilot(), tcs_pilot(), abs_pilot(), sc_pilot(), donuts_pilot()]


static func _lesson(name: String, title: String, steps: Array[Dictionary], time_limit: float, manual := false) -> Dictionary:
	var pilot := {
		"name": name,
		"kind": LicenceExams.KIND_LESSON,
		"title": title,
		"objective": "",
		"start_offset": Vector3.ZERO,
		"start_heading_deg": 0.0,
		"steps": steps,
		"settle": 1.0,
		"time_limit": time_limit,
	}
	if manual:
		pilot["manual"] = true
	return pilot


## Steering: at a walk, full left lock held, let go (the caster brings it
## back), full right lock held, let go, and a stop (what is left on the
## wheel stays there).
# was "Let go: the hands bring the wheel back to centre the same way" ->
# the hands let go bring nothing back: the caster does, on the move, at
# its own rate for the speed, and standing still nothing does (the user's
# verdict, 15:24: "while standing still in a real car the wheel doesn't
# center by itself, it only happens when the car moves"). The steps are the
# same six, the keys let go as before: the lesson is what letting go does.
static func steering_pilot() -> Dictionary:
	return _lesson("STEERING", "STEERING", [
		{"when": {}, "cruise_forward": STEERING_WALK_SPEED, "say": "A walk down the straight. Nothing turns the wheels but the driver's hands on the 900-degree wheel - and, rolling, the caster."},
		{"when": {"after": STEERING_RETURN_TIME}, "press": [&"steer_left"], "say": "Left key held: the hands wind the wheel on at 1300 degrees a second, centre to full lock in 0.35 s. The nose follows the front tyres."},
		{"when": {"after": STEERING_HOLD_TIME}, "release": [&"steer_left"], "say": "Let go: hands off. The rolling front tyres pull the wheel straight - the caster - slowly at a walk, quicker with speed, never standing still."},
		{"when": {"after": STEERING_RETURN_TIME}, "press": [&"steer_right"], "say": "Right key held: full lock the other way. A held key at speed winds on more lock than the tyres can use; short presses ask for less."},
		{"when": {"after": STEERING_HOLD_TIME}, "release": [&"steer_right"], "say": "Let go again: the caster brings it back. To straighten up quickly, steer back yourself - the hands are faster."},
		{"when": {"after": STEERING_RETURN_TIME}, "cruise_off": true, "press": [&"brake"], "say": "And a stop. What is still on the wheel stays there: standing still, nothing centres it."},
		{"when": {"stopped": 1.0}},
	], 30.0)


## Manual gear changes: 1st to 3rd on the shift light, off the throttle,
## on the brake, a gear back down on the way to the stop.
static func manual_gears_pilot() -> Dictionary:
	return _lesson("MANUAL_GEARS", "MANUAL GEAR CHANGES", [
		{"when": {}, "press": [&"accelerate"], "say": "Manual, 1st: full throttle, the revs climb. Change up at the shift light (6500 rpm, the tach turns red)."},
		{"when": {"speed_above": GEARS_SHIFT_1_2_SPEED}, "press": [&"shift_up"], "say": "E: up into 2nd. The clutch opens for the change, the revs drop, the clutch catches the gear."},
		{"when": {"after": TAP_TIME}, "release": [&"shift_up"]},
		{"when": {"speed_above": GEARS_SHIFT_2_3_SPEED}, "press": [&"shift_up"], "say": "E: up into 3rd, the same way."},
		{"when": {"after": TAP_TIME}, "release": [&"shift_up"]},
		{"when": {"after": TAP_TIME}, "release": [&"accelerate"], "say": "Off the throttle: engine braking, harder the lower the gear."},
		{"when": {"after": GEARS_OVERRUN_TIME}, "press": [&"brake"], "say": "On the brake in 3rd."},
		{"when": {"speed_below": GEARS_DOWNSHIFT_SPEED}, "press": [&"shift_down"], "say": "Q: down into 2nd on the way to the stop. The driver blips the throttle so the revs match the gear."},
		{"when": {"after": TAP_TIME}, "release": [&"shift_down"], "say": "And to a stop; the box stays where it was left."},
		{"when": {"stopped": 1.0}},
	], 40.0, true)


## Stall and recovery: manual, 1st, the clutch let up on an idling engine as
## the throttle goes down - the stall - then the clutch down, the starter,
## revs up, and the pull-away.
static func stall_recovery_pilot() -> Dictionary:
	return _lesson("STALL_RECOVERY", "STALL AND RECOVERY", [
		{"when": {}, "press": [&"clutch_pedal"], "say": "Manual, 1st, clutch (Shift) to the floor: the engine idles free of the wheels."},
		{"when": {"after": STALL_IDLE_TIME}, "release": [&"clutch_pedal"], "press": [&"accelerate"], "say": "Clutch let up as the throttle goes down: the clutch is home before the revs are up, the car's load drags the engine under 450 rpm - STALL. It lurches and dies."},
		{"when": {"after": STALL_SHOW_TIME}, "release": [&"accelerate"], "press": [&"clutch_pedal"], "say": "Recovery: throttle off, clutch back to the floor - a stalled engine is cranked free of the wheels."},
		{"when": {"after": 0.5}, "press": [&"starter"], "say": "Starter (I): a tap cranks it for a cycle, and it catches."},
		{"when": {"after": TAP_TIME}, "release": [&"starter"]},
		{"when": {"after": STALL_SHOW_TIME * 0.5}, "press": [&"accelerate"], "say": "Running again. Revs up on the clutch first ..."},
		{"when": {"after": STALL_REV_TIME}, "release": [&"clutch_pedal"], "say": "... then the clutch let up: the pedal comes up through the bite with the revs there to meet it, and the car is away."},
		{"when": {"after": STALL_PULL_AWAY_TIME}, "release": [&"accelerate"], "press": [&"brake"], "say": "And a stop."},
		{"when": {"stopped": 1.0}},
	], 40.0, true)


## Drive modes: full throttle to 72 km/h in sport, comfort and eco, the
## program changed with the N key between the runs, and sport put back.
static func drive_modes_pilot() -> Dictionary:
	return _lesson("DRIVE_MODES", "DRIVE MODES", [
		{"when": {}, "press": [&"accelerate"], "say": "SPORT: full throttle. The box holds every gear to 6800 rpm, the end of the power."},
		{"when": {"speed_above": MODES_SHOW_SPEED}, "release": [&"accelerate"], "press": [&"brake"], "say": "72 km/h: brake."},
		{"when": {"stopped": 1.0}, "release": [&"brake"]},
		{"when": {"after": 0.3}, "press": [&"gearbox_mode"], "say": "N: COMFORT. Its own driver takes the seat, with a slower foot."},
		{"when": {"after": TAP_TIME}, "release": [&"gearbox_mode"]},
		{"when": {"after": 0.5}, "press": [&"accelerate"], "say": "COMFORT: the same full throttle, but the box changes up at 2800 rpm - the upper half of the rev range is never used. No kickdown."},
		{"when": {"speed_above": MODES_SHOW_SPEED}, "release": [&"accelerate"], "press": [&"brake"], "say": "72 km/h: brake."},
		{"when": {"stopped": 1.0}, "release": [&"brake"]},
		{"when": {"after": 0.3}, "press": [&"gearbox_mode"], "say": "N: ECO."},
		{"when": {"after": TAP_TIME}, "release": [&"gearbox_mode"]},
		{"when": {"after": 0.5}, "press": [&"accelerate"], "say": "ECO: changes up at ~2000 rpm, where the engine turns fuel into work best, and caps the throttle. The least fuel, the slowest."},
		{"when": {"speed_above": MODES_SHOW_SPEED}, "release": [&"accelerate"], "press": [&"brake"], "say": "72 km/h: brake."},
		{"when": {"stopped": 1.0}, "release": [&"brake"]},
		{"when": {"after": 0.3}, "press": [&"gearbox_mode"], "say": "N once more: round to SPORT."},
		{"when": {"after": TAP_TIME}, "release": [&"gearbox_mode"]},
	], 60.0)


## Tyre wear: the wear test's donut - full lock, full throttle, the aids
## off - long enough for the rears to go over the window.
static func tyre_wear_pilot() -> Dictionary:
	return _lesson("TYRE_WEAR", "HOW TYRES WEAR", [
		{"when": {}, "press": [&"accelerate", &"steer_left"], "say": "TCS and SC off, full lock, full throttle: the rears spin, and every joule of that slip heats them. Wear is the rate times the heat."},
		{"when": {"after": TYRE_WEAR_SPIN_TIME * 0.5}, "say": "Watch TYRES on the HUD climb, and the rear wear readout with it. Cornering on tyres that grip wears almost nothing."},
		{"when": {"after": TYRE_WEAR_SPIN_TIME * 0.5}, "release": [&"accelerate", &"steer_left"], "press": [&"brake"], "say": "Over 110 C the rubber wears three times as fast: the window is where a tyre lives, and this is what a burnout costs."},
		{"when": {"stopped": 1.0}},
	], 40.0)


## TCS: the same launch twice, T pressed between them.
static func tcs_pilot() -> Dictionary:
	return _lesson("TCS_ON_OFF", "TCS ON / OFF", [
		{"when": {}, "press": [&"accelerate"], "say": "TCS ON: full throttle from rest. The clutch feathers against wheelspin and the rears are held at 25 % slip."},
		{"when": {"speed_above": TCS_LAUNCH_SPEED}, "release": [&"accelerate"], "press": [&"brake"], "say": "Brake."},
		{"when": {"stopped": 1.0}, "release": [&"brake"]},
		{"when": {"after": 0.3}, "press": [&"tcs_toggle"], "say": "T: TCS OFF (the lamp lights)."},
		{"when": {"after": TAP_TIME}, "release": [&"tcs_toggle"]},
		{"when": {"after": 0.5}, "press": [&"accelerate"], "say": "TCS OFF: the clutch is dumped once the revs are up and the rears spin - WHEEL SPIN, two black lines."},
		{"when": {"speed_above": TCS_LAUNCH_SPEED}, "release": [&"accelerate"], "press": [&"brake"], "say": "Brake."},
		{"when": {"stopped": 1.0}, "release": [&"brake"]},
		{"when": {"after": 0.3}, "press": [&"tcs_toggle"], "say": "T: TCS back on."},
		{"when": {"after": TAP_TIME}, "release": [&"tcs_toggle"]},
	], 40.0)


## ABS: the same full stop from 80 km/h twice, G pressed between them.
static func abs_pilot() -> Dictionary:
	return _lesson("ABS_ON_OFF", "ABS ON / OFF", [
		{"when": {}, "cruise_forward": ABS_STOP_SPEED, "say": "ABS ON: up to 80 km/h."},
		{"when": {"speed_above": ABS_STOP_SPEED - 0.5}, "cruise_off": true, "press": [&"brake"], "say": "Full pedal: ABS holds the fronts just short of locking, at 15 % slip. The stop is short and the car still steers."},
		{"when": {"stopped": 1.0}, "release": [&"brake"]},
		{"when": {"after": 0.3}, "press": [&"abs_toggle"], "say": "G: ABS OFF (the lamp lights)."},
		{"when": {"after": TAP_TIME}, "release": [&"abs_toggle"]},
		{"when": {"after": 0.5}, "cruise_forward": ABS_STOP_SPEED, "say": "ABS OFF: up to 80 km/h again."},
		{"when": {"speed_above": ABS_STOP_SPEED - 0.5}, "cruise_off": true, "press": [&"brake"], "say": "Full pedal without ABS: the fronts LOCK, the stop is longer and a locked wheel cannot steer."},
		{"when": {"stopped": 1.0}, "release": [&"brake"]},
		{"when": {"after": 0.3}, "press": [&"abs_toggle"], "say": "G: ABS back on."},
		{"when": {"after": TAP_TIME}, "release": [&"abs_toggle"]},
	], 60.0)


## SC: the same flick of lock and handbrake at 60 km/h twice, K pressed
## between them.
static func sc_pilot() -> Dictionary:
	return _lesson("SC_ON_OFF", "SC ON / OFF", [
		{"when": {}, "cruise_forward": SC_FLICK_SPEED, "say": "SC ON: up to 60 km/h."},
		{"when": {"speed_above": SC_FLICK_SPEED - 0.5}, "cruise_off": true, "press": [&"steer_left", &"handbrake"], "say": "A flick: full left lock and the handbrake for half a second."},
		# was 79 degrees -> 76: the hands let go leave the wheel to the caster
		# (1.5 s back to centre as the car rolls on; the user's verdict, 15:24).
		{"when": {"after": SC_FLICK_TIME}, "release": [&"steer_left", &"handbrake"], "say": "Let go: with SC the slide is damped - the car swings 76 degrees, straightens itself and rolls on nose-first, the caster centring the wheel."},
		{"when": {"after": 3.0}, "press": [&"brake"]},
		{"when": {"stopped": 1.0}, "release": [&"brake"]},
		{"when": {"after": 0.3}, "press": [&"sc_toggle"], "say": "K: SC OFF (the lamp lights)."},
		{"when": {"after": TAP_TIME}, "release": [&"sc_toggle"]},
		{"when": {"after": 0.5}, "cruise_forward": SC_FLICK_SPEED, "say": "SC OFF: up to 60 km/h again."},
		{"when": {"speed_above": SC_FLICK_SPEED - 0.5}, "cruise_off": true, "press": [&"steer_left", &"handbrake"], "say": "The same flick."},
		# was 153 degrees -> 152 (the caster; the user's verdict, 15:24).
		{"when": {"after": SC_FLICK_TIME}, "release": [&"steer_left", &"handbrake"], "say": "Let go: nothing damps the slide now. It hangs on for as long as the tyres let it - the car swings 152 degrees and ends up rolling backwards. The spin is yours to catch."},
		{"when": {"after": 3.0}, "press": [&"brake"]},
		{"when": {"stopped": 1.0}, "release": [&"brake"]},
		{"when": {"after": 0.3}, "press": [&"sc_toggle"], "say": "K: SC back on."},
		{"when": {"after": TAP_TIME}, "release": [&"sc_toggle"]},
	], 60.0)


## Donuts: TCS and SC off, full left lock and full throttle from rest.
static func donuts_pilot() -> Dictionary:
	return _lesson("DONUTS", "DONUTS", [
		{"when": {}, "press": [&"accelerate", &"steer_left"], "say": "TCS and SC off, full left lock, full throttle from rest: the rears spin up, the tail comes round, and the car circles its own nose."},
		# was "lock off" -> hands off: the caster takes the lock off as the car
		# rolls (the user's verdict, 15:24).
		{"when": {"after": DONUT_SPIN_TIME}, "release": [&"accelerate", &"steer_left"], "press": [&"brake"], "say": "Throttle off, hands off, brake: the caster straightens the wheel as the car rolls. It costs the rears their rubber (see HOW TYRES WEAR)."},
		{"when": {"stopped": 1.0}},
	], 30.0)
