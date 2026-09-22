class_name HandlingTests
extends RefCounted
## Handling tests: the seed of the mission mode. If a test cannot be passed,
## either the driver or the car is not set up properly.
##
## A test is plain data (a Dictionary, see the *_test() functions):
##   name, kind             what it is and which checks judge it (KIND_*),
##   title, objective       what a human driver is shown: a short name and
##                          one line on what to do,
##   start_offset/heading   where the car starts, relative to its spawn point,
##   payload_kg             optional, what the car carries on the run [kg]
##                          (ArcadeCar.payload_mass): loaded at the start, gone
##                          with the next reset. None of the certified tests
##                          carries anything,
##   start_line_z           where the run clock starts: the pad z of the test's
##                          start line [m] (see "The run clock" below),
##   hold_speed             optional cruise control for the scripted driver
##                          (until it brakes),
##   goal_mode              optional, where the run goes once the manoeuvre is
##                          done (GOAL_*): back to the start point, or on down
##                          the line to a goal `goal_distance_m` from the start,
##   steps                  the scripted driver: an ordered list of
##                          { when, press, release, mark } entries,
##   settle, time_limit     how the run ends,
##   target_time_s          the run time the HUD shows the clock against [s],
##   gold_time_s, silver_time_s, bronze_time_s   the medal times [s]: a passed
##                          run this quick or quicker earns the medal (see
##                          medal_for()). Presentation only: pass is pass,
##                          nothing in the verdict looks at the medals.
## Steps fire strictly in order. `when` holds the conditions a step waits for
## (all must be true), measured the way a driver would judge them:
##   "after"        seconds since the previous step fired,
##   "speed_above"  / "speed_below"   road speed [m/s],
##   "travelled"    distance covered along the start heading [m],
##   "rotation_deg" how far the car has turned since the start (keeps counting
##                  past 180 / 360) [degrees, left positive]; at least this,
##   "rotation_deg_below"  the same, at most this (for turns to the right),
##   "goal_distance_below" distance left to the goal [m]; at most this.
## A step with `mark` is the start of the manoeuvre: spin metrics count from it.
## Besides pressing and releasing keys a step can hold the steering wheel near
## an angle ("steer_deg", left positive: the steering keys tapped so the wheel
## hovers within a tick of the hands of it, _hold_steering - "steer_deg": 0.0
## is the driver steering back to straight and holding it there) until a
## step presses or releases a steering key or lets go ("steer_free": the
## hands off the wheel, the caster's).
# was: a driver straightened up by letting the key go, the hands bringing
# the wheel back to centre by themselves -> the hands let go turn nothing
# (ArcadeCar CASTER_RETURN_RATE_MAX: the caster brings the wheel back, on the
# move only; the user's verdict, 15:24), so every driver steers back
# actively, the way LicenceExams' drivers hold an angle.
##
## The spins and the reverse 180 are a manoeuvre and a destination: do the 180
## and return to the start, do the 360 and drive on to the goal, do the J-turn
## and drive on to the goal. The run ends at the goal, not when the rotation
## does, and the verdict is rotation AND goal. The car keeps turning on the way
## to the goal (driving back adds up to another half turn), so the rotation is
## judged once, the moment the spin settles: the first frame it is within
## tolerance of the target with the yaw rate under SPIN_SETTLED_YAW_RATE_DEG,
## or the frame it spins on past the tolerance altogether. Rotation, heading
## and displacement are noted there and judged from the note; the goal only
## counts from then on.
##
## The run clock. The clock times the run, not the nerves: every test has a
## start line across the pad (`start_line_z`, 4 m down the pad from where the
## car is put: the pad's painted START / FINISH line, TestPad.START_LINE_Z, or
## for the slalom, which starts further down, a line of its own,
## TestPad.SLALOM_START_LINE_Z), and the clock starts on the first tick the
## car's position is over it having been short of it the tick before, going the
## way the run goes (down the pad; the reverse 180 crosses it tail-first). A
## position that crossed between two ticks moved, so the car is in motion by
## definition. Everything before the crossing - lining up, waiting, a run-up
## from further back - is free, and the scripted driver is timed the very same
## way. There is one timed window per run: driving back over the line and
## crossing it again does not start the clock anew. The clock stops at the
## finish: over the goal line or back at the start (tests with a goal_mode), at
## a standstill having been up to speed (stop box), level with the last cone
## (slalom). The `settle` seconds the run is watched for after that are not on
## it. The verdict's run_time_s is this clock, and so are the medals and the
## slalom's time check; a run that never crossed its start line before its
## finish fails. `elapsed`, the seconds since begin(), still paces the script
## and the `settle`, and the `time_limit` is still judged from it: a driver who
## never goes near the line times out just the same.
# was: one clock, `elapsed`, from the first tick after begin() to the end of the
# run, the settle included; it was the verdict's run_time_s and the medal input
# -> the run clock above - a human who got going a second late was a second
# slower on the clock ("the timer starts when the test starts, which made me do
# the j turn multiple times because i was starting late"), and the time on the
# banner had 1 - 2 s of being watched after the finish in it.
##
## One instance of this class is one run of one test on the real car:
##
##   var run := HandlingTests.begin(HandlingTests.spin_180_test(), car, pad)
##   ... every physics frame:  run.tick(delta)  until run.finished
##   var result := run.result()   # { name, passed, metrics, checks }
##
## With `scripted` false the steps are ignored and a human drives; the same
## tracking and checks apply. That is how gameplay missions reuse the tests.
## The SceneTree harness that runs them headless is tests/handling_test.gd.

const KIND_SLALOM := &"slalom"
const KIND_SPIN := &"spin"
const KIND_STOP_BOX := &"stop_box"
const KIND_REVERSE_SPIN := &"reverse_spin"

## Goal modes: drive back to the start point / drive on down the line (a spin:
## the start heading; the reverse 180: the way it reversed) to the goal.
const GOAL_RETURN_TO_START := &"return_to_start"
const GOAL_DRIVE_ON := &"drive_on"

## Medals, best first. A test's medal times are its "<medal>_time_s" fields.
const MEDALS: Array[String] = ["gold", "silver", "bronze"]

# --- Pass / fail tolerances ---------------------------------------------------

## Spins: the car must end within this of the target rotation, spun either
## way [degrees] ...
const SPIN_HEADING_TOLERANCE_DEG := 35.0

## ... having travelled further than this along its original heading since the
## manoeuvre started [m]. A spin is done on the move, not on the spot.
const SPIN_MIN_FORWARD_DISPLACEMENT := 0.0

## Spins and the reverse 180: the rotation counts as settled, and is judged,
## once it is within tolerance and the car turns slower than this [degrees/s].
const SPIN_SETTLED_YAW_RATE_DEG := 10.0

## Return to start: the car is back once it is within this of the start point
## [m]. Drive on: the car is there once it is over the goal line, no further
## than this to either side of the goal point [m] (the lane is 6 m either side).
const GOAL_RADIUS := 8.0

## The 360's goal, from the start along the start heading [m]: the pad's 400 m
## board (TestPad counts its boards from the start line, 4 m on). Getting to
## ~125 km/h takes 215 m and the spin another 90, so there are ~100 m to go.
const SPIN_360_GOAL_DISTANCE := 404.0

## The reverse 180's goal, from the start along the reversing line [m]: the
## 100 m board. The flick is over by ~40 m.
const REVERSE_180_GOAL_DISTANCE := 104.0

## Slalom: gates that may be missed (wrong side, too wide or cone knocked over).
const SLALOM_MAX_MISSED := 1

## Slalom: a pass further than this from the cone does not count [m].
const SLALOM_GATE_WIDTH := 6.0

## Slalom: generous time limit from the start line to the last cone [s], on
## the run clock. A steady 36 km/h run takes about 29 s.
# was 45.0, from begin() -> 43.0, from the start line - the check moved to the
# run clock, and the certified run is over the line 1.55 s after begin() (30.3 s
# then, 28.75 s now): 45.0 on the new clock would have been 1.55 s more than it
# was. 43.0 is 0.45 s less: the same check, a little stricter.
const SLALOM_TIME_LIMIT := 43.0

## Stop box: the car counts as stopped below this speed [m/s].
const STOPPED_SPEED := 0.3

## Stop box: the car must have been at least this fast before braking [m/s],
## so crawling up to the box does not count (72 km/h).
const STOP_BOX_MIN_ENTRY_SPEED := 20.0

## Reverse 180: the car must end within this of having turned half way round,
## either way [degrees] ...
const REVERSE_180_HEADING_TOLERANCE_DEG := 35.0

## ... driving away nose-first at this speed or more [m/s] (18 km/h) ...
const REVERSE_180_MIN_EXIT_SPEED := 5.0

## ... having got at least this fast in reverse first [m/s] (36 km/h) ...
const REVERSE_180_MIN_ENTRY_SPEED := 10.0

## ... and having kept moving the way it was reversing: further than this along
## that line since the manoeuvre started [m].
const REVERSE_180_MIN_DISPLACEMENT := 0.0

# --- Scripted driver ------------------------------------------------------------

const ACTIONS: Array[StringName] = [&"accelerate", &"brake", &"steer_left", &"steer_right", &"handbrake"]

## Slalom cruise speed [m/s], 36 km/h. The car can weave wider than the cones
## need at this speed, so there is margin either side.
# was 12.0 -> 10.0 - raw steering: the driver's key is the full 27.5 degrees of
# lock, which at 12 m/s scrubs the front tyres far past their peak; the car
# yawed ~32 deg/s where the eased lock gave ~40, each swing ran late and the
# weave drifted off the cones (5 of 14 gates). At 10 m/s the same full-lock
# swings fit the 18 m between cones again: 14 of 14, closest pass 2.1 m, and
# still 14 of 14 with SLALOM_SWING_DEG anywhere from 16 to 22 (11.0 made it at
# 19 but not at 22 - no margin).
const SLALOM_SPEED := 10.0

## The scripted slalom driver turns in this far before it draws level with a
## cone [m], to allow for the steering and the tyres taking a moment to
## answer ...
const SLALOM_STEER_LEAD := 9.0

## ... (a swing from one side to the other covers about twice this [m]; the
## turn-in is timed so the middle of the swing lands beside the cone) ...
# was 6.0 -> 7.0 - the yaw inertia takes longer to wind up and back down, so a
# swing covers more road (tyre-force model).
const SLALOM_HALF_SWING_DISTANCE := 7.0

## ... holds the lock until the nose points this far across the line [degrees] ...
# was 22.0 -> 19.0 - the car's yaw momentum carries the nose ~8 degrees on
# after the lock comes off; letting go earlier keeps the weave on the cones.
const SLALOM_SWING_DEG := 19.0

## ... and lines up this far to the right of the cones at the start [m].
const SLALOM_START_OFFSET := 3.0

## Entry speeds for the spins [m/s]: ~90 km/h and ~125 km/h.
const SPIN_180_ENTRY_SPEED := 25.0
const SPIN_360_ENTRY_SPEED := 35.0

## How far round the 180 driver holds the lock, handbrake on, before centring
## the steering [degrees] ...
# was SPIN_180_FEINT_TIME 0.6 s of steering right first, then the flick -> no
# feint - the feint was there to cancel the sideways drift of a car that spun
# round a body rotated for it. With the tyres bending the path themselves the
# flick alone keeps the car on its line (ends 9 degrees past 180); a feint now
# swings the path and the car settles along it, 25 - 30 degrees off.
# was 150.0 -> 155.0 - travelling backwards the held lock slows the rotation:
# held all the way, the spin tops out short of 180 and the car drags to a
# stop there. Let go just short of the top, the rotation is nearly spent and
# the car lines up along its path from there.
# 155.0 stays with raw steering, the reasoning is re-measured: the wheels no
# longer trail by themselves (was: "the steered wheels trail", topping out at
# ~165; 145 ended at 198, 155 at 189, 162 at 188). Now the lock stays on the
# wheels for as long as the key is held, and rolling backwards full lock
# works against the spin harder: held to 165 the rotation never gets there
# and the car stops at 138. 145 ends at 184, 155 at 180.
const SPIN_180_CATCH_DEG := 155.0

## ... and how long it then lets the car settle, rolling backwards with the
## locked rears leading like the head of a dart, before it brakes [s].
# was: brake at once -> wait 0.5 s - braked front tyres (brake bias puts most
# of the stop on them) have little left to line the car up with; on the brakes
# at once the rotation ran on to ~220.
const SPIN_180_SETTLE_TIME := 0.5

## 180, the drive back: the speed at which the driver lines the nose up on the
## start [m/s] ...
const SPIN_180_LINE_UP_SPEED := 8.0

## ... how long it holds the lock for [s]: a dab, the steering wheel is still
## winding on when it lets go. Measured: the nose comes round from 184.6 to
## 180.1 degrees and the car gets back 1.9 m to the side of the start point
## (0.15 s: 178.9 degrees, 4.4 m to the other side) ...
const SPIN_180_LINE_UP_TAP := 0.12

## ... and how far from the start it hits the brakes [m]: the 36 m a stop from
## 25 m/s takes (see STOP_BOX_BRAKE_DISTANCE).
const SPIN_180_RETURN_BRAKE_DISTANCE := 36.0

## 360, the drive on: how long the driver lets the car settle nose-first before
## getting back on the power, and then before lining up [s] ...
const SPIN_360_DRIVE_ON_DELAY := 0.5

## ... with a dab of lock this long [s]. Measured: the nose comes round from
## 361.7 to 356.2 degrees and the car crosses the goal line 0.8 m off the
## goal point (no dab: it drifts ~8.4 m wide of it, outside the goal).
const SPIN_360_LINE_UP_TAP := 0.15

## Reverse 180: reversing speed at which the scripted driver flicks the car
## round [m/s], ~41 km/h; reverse gear tops out at 43 ...
const REVERSE_180_FLICK_SPEED := 11.5

## ... how far round it lets the nose swing before steering against the
## rotation to stop it [degrees] ...
const REVERSE_180_CATCH_DEG := 140.0

## ... and the speed it drives away to [m/s] ...
# was "... before the run ends" -> the run goes on to the goal; this is where
# the driver lines up on it.
const REVERSE_180_DRIVE_AWAY_SPEED := 10.0

## ... where it lines the nose up on the goal, with a dab of lock this long
## [s]. Measured: the nose comes round from -185.9 to -176.9 degrees and the
## car crosses the goal line 1.9 m off the goal point (0.15 s: 4.6 m; no dab:
## it runs ~11 m wide of it, outside the goal).
const REVERSE_180_LINE_UP_TAP := 0.18

## Stop box: speed the scripted driver holds up to its braking point [m/s] ...
# was: build 25.0, lift, coast ~45 m (down to ~22 m/s) -> hold 25.0 to the
# braking point - so the stop is a full one from 90 km/h.
const STOP_BOX_APPROACH_SPEED := 25.0

## ... and how far before the centre of the box it hits the brakes [m].
# was 8.4 -> 30.6 - the brakes went from 26 m/s^2 to tyre-limited 9.3: from
# 25 m/s that is 25^2 / (2 * 9.3) = 33.6 m, less ~3 m that engine braking,
# drag and rolling resistance take off it.
# was 30.6 -> 36.0 - the brake force is now split front / rear (BRAKE_BIAS_FRONT
# 0.6): the fronts stop at their limit under ABS, the rears stay under theirs,
# and the stop comes out at ~8.7 m/s^2 all in: 25^2 / (2 * 8.7) = 35.9 m.
# Measured: stops 0.05 m from the centre of the box.
const STOP_BOX_BRAKE_DISTANCE := 36.0

var test: Dictionary
var car: ArcadeCar
var pad: Node
var scripted := true
var finished := false
var elapsed := 0.0  # Since begin() [s]: paces the script, the settle and the time limit.

# The run clock (see the top of the file).
var _run_started := false  # Over the start line, the clock is or was running.
var _run_stopped := false  # At the finish, the clock stands.
var _run_time := 0.0  # The run clock [s]: start line to finish.
var _line_side := 0.0  # How far past the start line the car was last tick [m]; negative = short of it.

var _step_index := 0
var _since_step := 0.0
var _all_steps_done_at := -1.0
var _pressed: Dictionary[StringName, bool] = {}
var _steer_hold := false  # A "steer_deg" step's hold is on (see _hold_steering).
var _steer_target_deg := 0.0  # ... at this steering wheel angle [degrees, left positive].

var _start_position: Vector3
var _start_forward: Vector3
var _start_yaw := 0.0  # Heading the run started on [rad].
var _previous_yaw := 0.0
var _rotation := 0.0  # Unwrapped yaw since the start [rad], left positive.
var _mark_position: Vector3
var _marked := false
var _peak_speed := 0.0
var _peak_reverse_speed := 0.0
var _timed_out := false

# Spin settled / goal tracking (tests with a goal_mode).
var _spin_settled := false
var _spin_overshot := false  # Settled by spinning on past the tolerance.
var _settled_rotation := 0.0  # _rotation when the spin settled [rad].
var _settled_yaw := 0.0  # Heading when the spin settled [rad].
var _settled_position: Vector3
var _goal_reached := false

# Slalom tracking.
var _gates: Array[Vector3] = []
var _gate_offsets: Array[float] = []  # Signed pass distance per gate; NAN = not reached.
var _gate_index := 0
var _slalom_time := -1.0


# =============================================================================
#  Test definitions
# =============================================================================

static func all_tests() -> Array[Dictionary]:
	return [slalom_test(), spin_180_test(), spin_360_test(), stop_box_test(), reverse_180_test()]


## Weave through the pad's slalom line: first cone on the car's left (pass to
## its right), then alternating. The scripted driver holds a steady speed and
## judges its turn-in points by distance.
static func slalom_test() -> Dictionary:
	var cones := TestPad.slalom_cone_positions()
	var run_in := 40.0
	var start := cones[0] + Vector3(SLALOM_START_OFFSET, 0.0, run_in)
	var spacing := cones[0].distance_to(cones[1])
	var steps: Array[Dictionary] = []
	# One swing per cone: turn in a little before drawing level with it, hold
	# the lock until the nose points SLALOM_SWING_DEG across the line, then run
	# straight to the next turn-in. Aiming for a heading every time, instead of
	# holding the lock for a set time, keeps the weave centred on the cones.
	for i in cones.size():
		var turn_at := run_in + i * spacing - SLALOM_STEER_LEAD
		if i == 0:
			# From straight ahead the first swing is only half a swing.
			turn_at += SLALOM_HALF_SWING_DISTANCE
		var left := i % 2 == 0
		var lock: StringName = &"steer_left" if left else &"steer_right"
		var heading_reached := {"rotation_deg": SLALOM_SWING_DEG} if left else {"rotation_deg_below": -SLALOM_SWING_DEG}
		steps.append({"when": {"travelled": turn_at}, "press": [lock]})
		# was "release": [lock], the hands bringing the wheel back by themselves
		# -> the driver steers back to straight and holds it (the caster alone
		# would take 1.4 s from full lock at this speed and the next turn-in
		# is 1.8 s on; the user's verdict, 15:24).
		steps.append({"when": heading_reached, "steer_deg": 0.0})
	# Past the last cone: straighten up.
	var last_left := (cones.size() - 1) % 2 == 0
	var straighten: StringName = &"steer_right" if last_left else &"steer_left"
	var straight := {"rotation_deg_below": 0.0} if last_left else {"rotation_deg": 0.0}
	steps.append({"when": {"travelled": run_in + cones.size() * spacing - SLALOM_STEER_LEAD}, "press": [straighten]})
	steps.append({"when": straight, "steer_deg": 0.0})
	return {
		"name": "SLALOM_TEST",
		"kind": KIND_SLALOM,
		"title": "SLALOM",
		"objective": "Weave through the cones: first cone on your left, then alternate. %d miss allowed, %.0f s." % [SLALOM_MAX_MISSED, SLALOM_TIME_LIMIT],
		"start_offset": start,
		"start_heading_deg": 0.0,
		# Where the run clock starts: pad z [m], crossed going down the pad (-Z).
		# The slalom starts at z = -20, 16 m past the pad's START / FINISH line, so
		# it has a line of its own 4 m on, the same 4 m every other test has to its
		# line: z = -24, a white bar painted across the slalom's lane. The run-in
		# to the first cone (36 m of it) is part of the timed run.
		"start_line_z": TestPad.SLALOM_START_LINE_Z,
		"hold_speed": SLALOM_SPEED,
		"steps": steps,
		"settle": 1.0,
		"time_limit": SLALOM_TIME_LIMIT + 10.0,
		# Target time for the whole run [s], run-in included: what the mission
		# HUD shows the clock against. Presentation only, nothing judges it.
		# target 30.0 s - certified run 27.3 s at HEAD (eed237f); the 24.7 s
		# slalom_time_s is first cone to last only.
		# was 30.0 -> 36.0 - the certified run is 32.4 s at SLALOM_SPEED 10.0 (raw
		# steering); slalom_time_s 29.6.
		# was 36.0 -> 31.0 - the run clock (start line to last cone): certified
		# run 28.75 s at HEAD (f4652eb), as a mission and as a handling test alike,
		# slalom_time_s the same number now. The gold time, as on the other tests.
		"target_time_s": 31.0,
		# Medal times [s]: gold / silver / bronze - the certified drive is 31.3 s
		# as a mission (the run ends 1 s after the last cone; 33.2 s as a handling
		# test, where the script straightens up first) at HEAD (c47aa3f): +7 %, +25 %,
		# +50 %. The last cone has to be reached inside SLALOM_TIME_LIMIT, so every
		# pass is inside bronze.
		# was 33.5 / 39.0 / 47.0 -> 31.0 / 36.0 / 43.0 - the run clock: certified
		# 28.75 s at HEAD (f4652eb), was 31.3 s from begin() to 1 s after the last
		# cone: +8 %, +25 %, +50 %. Bronze is SLALOM_TIME_LIMIT (43.0), so every
		# pass is still inside bronze.
		# 31.0 / 36.0 / 43.0 stay - the steering feel (the power assist, the
		# rack's play, the bushings; ArcadeCar STEERING_ASSIST_FULL_SPEED) moved
		# the certified run 28.77 -> 28.82 s at 3781c8a, +0.17 %: +8 % to gold.
		# 31.0 / 36.0 / 43.0 stay - the caster return and the driver steering
		# back actively (the user's verdict, 15:24) moved the certified run
		# 28.82 -> 28.65 s, -0.59 %: +8 % to gold.
		"gold_time_s": 31.0,
		"silver_time_s": 36.0,
		"bronze_time_s": 43.0,
	}


## Handbrake turn: from speed, flick in with the handbrake and let the tail come
## round. The handbrake stays on: with the loose rear leading, the car settles
## travelling backwards, and the brakes bring it to a stop facing the start.
## Then back up the road to the start point.
static func spin_180_test() -> Dictionary:
	return {
		"name": "SPIN_180",
		"kind": KIND_SPIN,
		"title": "180 SPIN",
		# was "... spin round to face the start and stop." -> the run ends back at the start.
		"objective": "Handbrake turn: build speed (~90 km/h), spin round to face the start and drive back to it.",
		"target_rotation_deg": 180.0,
		"goal_mode": GOAL_RETURN_TO_START,
		"start_offset": Vector3.ZERO,
		"start_heading_deg": 0.0,
		# Where the run clock starts: pad z [m], crossed going down the pad (-Z).
		# The pad's painted START / FINISH line, 4 m ahead of the start point: the
		# car is over it a moment after it pulls away, so the speed is built on
		# the clock. The goal is still the start point, not the line.
		"start_line_z": TestPad.START_LINE_Z,
		"steps": [
			{"when": {}, "press": [&"accelerate"]},
			{"when": {"speed_above": SPIN_180_ENTRY_SPEED}, "release": [&"accelerate"], "press": [&"steer_left", &"handbrake"], "mark": true},
			# Round and rolling backwards: steer back to straight (the car is
			# rolling backwards: the caster does nothing there, the hands have
			# to) and let the car line itself up, then hit the brakes. The
			# brake stops the car whichever way it rolls, and holds it.
			# was "release": [&"steer_left"] -> steered back (the user's verdict, 15:24).
			{"when": {"rotation_deg": SPIN_180_CATCH_DEG}, "steer_deg": 0.0},
			{"when": {"after": SPIN_180_SETTLE_TIME}, "press": [&"brake"]},
			# was the end of the script -> stopped, facing the start: off the brakes
			# and back up the road, a touch of lock to point the nose at the start
			# (the spin leaves it a few degrees to the left of it), and on the
			# brakes in time to pull up on the start point.
			{"when": {"speed_below": STOPPED_SPEED}, "release": [&"brake", &"handbrake"], "press": [&"accelerate"]},
			{"when": {"speed_above": SPIN_180_LINE_UP_SPEED}, "press": [&"steer_right"]},
			# was "release": [&"steer_right"] -> steered back (the user's verdict, 15:24).
			{"when": {"after": SPIN_180_LINE_UP_TAP}, "steer_deg": 0.0},
			{"when": {"goal_distance_below": SPIN_180_RETURN_BRAKE_DISTANCE}, "release": [&"accelerate"], "press": [&"brake"]},
			{"when": {"goal_distance_below": GOAL_RADIUS}},
		],
		"settle": 1.5,
		# was 30.0 -> 45.0 - the drive back to the start is part of the run.
		"time_limit": 45.0,
		# Target time for the whole run [s]; presentation only, nothing judges it.
		# target 11.5 s - certified run 10.2 s at HEAD (eed237f).
		# was 11.5 -> 20.5 - the run goes back to the start now: certified run
		# 18.9 s at HEAD (c47aa3f), 9.7 s of it the spin, to a stop. The gold time.
		# was 20.5 -> 17.0 - the run clock (start line to back within 8 m of the
		# start point): certified run 15.83 s at HEAD (f4652eb). The gold time.
		"target_time_s": 17.0,
		# Medal times [s]: gold / silver / bronze - certified 18.9 s at HEAD (c47aa3f):
		# +8 %, +24 %, +51 %.
		# was 20.5 / 23.5 / 28.5 -> 17.0 / 19.5 / 24.0 - the run clock: certified
		# 15.83 s at HEAD (f4652eb), the 1.57 s to the line and the 1.5 s settle no
		# longer on it: +7 %, +23 %, +52 %.
		# 17.0 / 19.5 / 24.0 stay - the steering feel moved the certified run
		# 15.92 -> 15.95 s at 3781c8a, +0.19 %: +7 % to gold.
		# 17.0 / 19.5 / 24.0 stay - the caster return and the driver steering
		# back actively (the user's verdict, 15:24) left the certified run at
		# 15.95 s (the spin settles at 182.2 degrees for 183.5): +7 % to gold.
		"gold_time_s": 17.0,
		"silver_time_s": 19.5,
		"bronze_time_s": 24.0,
	}


## Full spin: flick in with the handbrake, steer the other way while the car
## travels backwards, let go of the handbrake past half way so the rear stops
## fighting the rotation, and steer back in as the nose comes round. Then on
## down the straight to the goal line, at the 400 m board.
static func spin_360_test() -> Dictionary:
	return {
		"name": "SPIN_360",
		"kind": KIND_SPIN,
		"title": "360 SPIN",
		# was "... spin all the way round and stop." -> the run ends at the goal line.
		"objective": "Full spin: build speed (~125 km/h), spin all the way round and drive on to the 400 m board.",
		"target_rotation_deg": 360.0,
		"goal_mode": GOAL_DRIVE_ON,
		"goal_distance_m": SPIN_360_GOAL_DISTANCE,
		"start_offset": Vector3.ZERO,
		"start_heading_deg": 0.0,
		# Where the run clock starts: pad z [m], crossed going down the pad (-Z).
		# The pad's painted START / FINISH line, 4 m ahead of the start point; the
		# goal's 404 m are still counted from the start point (the 400 m board).
		"start_line_z": TestPad.START_LINE_Z,
		"steps": [
			{"when": {}, "press": [&"accelerate"]},
			{"when": {"speed_above": SPIN_360_ENTRY_SPEED}, "release": [&"accelerate"], "press": [&"steer_left", &"handbrake"], "mark": true},
			{"when": {"rotation_deg": 120.0}, "release": [&"steer_left"], "press": [&"steer_right"]},
			{"when": {"rotation_deg": 160.0}, "release": [&"handbrake"]},
			{"when": {"rotation_deg": 270.0}, "release": [&"steer_right"], "press": [&"steer_left"]},
			# was "release": [&"steer_left"] -> steered back (the user's verdict, 15:24).
			{"when": {"rotation_deg": 350.0}, "steer_deg": 0.0},
			# was the end of the script, the car left rolling -> nose-first again:
			# back on the power, a touch of lock to point the nose at the goal (the
			# spin leaves the car to the left of the line, heading further left),
			# and on the brakes over the goal line.
			{"when": {"after": SPIN_360_DRIVE_ON_DELAY}, "press": [&"accelerate"]},
			{"when": {"after": SPIN_360_DRIVE_ON_DELAY}, "press": [&"steer_right"]},
			# was "release": [&"steer_right"] -> steered back (the user's verdict, 15:24).
			{"when": {"after": SPIN_360_LINE_UP_TAP}, "steer_deg": 0.0},
			{"when": {"goal_distance_below": 0.0}, "release": [&"accelerate"], "press": [&"brake"]},
		],
		"settle": 2.0,
		# was 30.0 -> 40.0 - the drive on to the goal is part of the run.
		"time_limit": 40.0,
		# Target time for the whole run [s]; presentation only, nothing judges it.
		# target 16.5 s - certified run 14.6 s at HEAD (eed237f).
		# was 16.5 -> 23.5 - the run goes on to the 400 m board now: certified run
		# 21.8 s at HEAD (c47aa3f), over the goal line at 19.8 s. The gold time.
		# was 23.5 -> 19.5 - the run clock (start line to goal line): certified run
		# 18.23 s at HEAD (f4652eb). The gold time.
		"target_time_s": 19.5,
		# Medal times [s]: gold / silver / bronze - certified 21.8 s at HEAD (c47aa3f):
		# +8 %, +26 %, +49 %.
		# was 23.5 / 27.5 / 32.5 -> 19.5 / 23.0 / 27.0 - the run clock: certified
		# 18.23 s at HEAD (f4652eb), the 1.57 s to the line and the 2 s settle no
		# longer on it: +7 %, +26 %, +48 %.
		# 19.5 / 23.0 / 27.0 stay - the steering feel moved the certified run
		# 18.13 -> 18.07 s at 3781c8a, -0.33 %: +8 % to gold.
		# 19.5 / 23.0 / 27.0 stay - the caster return and the driver steering
		# back actively (the user's verdict, 15:24) left the certified run at
		# 18.07 s: +8 % to gold.
		"gold_time_s": 19.5,
		"silver_time_s": 23.0,
		"bronze_time_s": 27.0,
	}


## Brake from speed into the box painted on the straight and stop inside it.
static func stop_box_test() -> Dictionary:
	var box := TestPad.stop_box()
	var distance_to_box: float = -box.centre.z
	return {
		"name": "STOP_BOX",
		"kind": KIND_STOP_BOX,
		"title": "STOP BOX",
		"objective": "Reach %.0f km/h or more, then stop with the whole car inside the hatched box ahead." % (STOP_BOX_MIN_ENTRY_SPEED * 3.6),
		"start_offset": Vector3.ZERO,
		"start_heading_deg": 0.0,
		# Where the run clock starts: pad z [m], crossed going down the pad (-Z).
		# The pad's painted START / FINISH line, 4 m ahead of the start point.
		"start_line_z": TestPad.START_LINE_Z,
		"hold_speed": STOP_BOX_APPROACH_SPEED,
		"steps": [
			{"when": {"travelled": distance_to_box - STOP_BOX_BRAKE_DISTANCE}, "press": [&"brake"]},
			# Stay on the brake to a stop: a held brake holds the car, it never
			# turns into reverse.
			{"when": {"speed_below": STOPPED_SPEED}},
		],
		"settle": 1.5,
		"time_limit": 30.0,
		# Target time for the whole run [s]; presentation only, nothing judges it.
		# target 12.5 s - certified run 11.3 s at HEAD (eed237f).
		# was 12.5 -> 9.3 - the run clock (start line to a standstill): certified
		# run 8.67 s at HEAD (f4652eb). The gold time.
		"target_time_s": 9.3,
		# Medal times [s]: gold / silver / bronze - certified 11.7 s at HEAD (c47aa3f):
		# +7 %, +24 %, +49 %.
		# was 12.5 / 14.5 / 17.5 -> 9.3 / 10.8 / 13.0 - the run clock: certified
		# 8.67 s at HEAD (f4652eb), the 1.55 s to the line and the 1.5 s settle no
		# longer on it: +7 %, +25 %, +50 %.
		# 9.3 / 10.8 / 13.0 stay - the steering feel left the certified run at
		# 8.72 s at 3781c8a, no steering in it: +7 % to gold.
		# 9.3 / 10.8 / 13.0 stay - the caster return (the user's verdict,
		# 15:24) left it at 8.72 s, no steering in it: +7 % to gold.
		"gold_time_s": 9.3,
		"silver_time_s": 10.8,
		"bronze_time_s": 13.0,
	}


## J-turn: reverse down the straight, flick the steering so the nose swings
## round, and drive away forwards along the same line without stopping. The
## car starts facing back up the straight, so it reverses the usual way down
## it. Reverse is a fresh press of the brake key at a standstill; forward is a
## fresh press of the accelerate key once the car rolls nose-first. Then on
## down the line to the goal, at the 100 m board.
static func reverse_180_test() -> Dictionary:
	return {
		"name": "REVERSE_180",
		"kind": KIND_REVERSE_SPIN,
		"title": "REVERSE 180",
		# was "... and drive away forwards." -> the run ends at the goal line.
		"objective": "J-turn: reverse to %.0f km/h or more, flick the nose round and drive on to the 100 m board." % (REVERSE_180_MIN_ENTRY_SPEED * 3.6),
		"target_rotation_deg": 180.0,
		"goal_mode": GOAL_DRIVE_ON,
		"goal_distance_m": REVERSE_180_GOAL_DISTANCE,
		"start_offset": Vector3.ZERO,
		"start_heading_deg": 180.0,
		# Where the run clock starts: pad z [m], crossed going down the pad (-Z),
		# which this car does tail-first. The pad's painted START / FINISH line,
		# 4 m behind the car as it stands on the start point: line up and wait as
		# long as you like, the clock starts when you reverse over the line. A
		# run-up from further back is free too. The goal's 104 m are still
		# counted from the start point (the 100 m board).
		"start_line_z": TestPad.START_LINE_Z,
		"steps": [
			{"when": {}, "press": [&"brake"]},
			# Lift and flick: the front of a reversing car trails, so once it
			# steps out it swings all the way round.
			{"when": {"speed_above": REVERSE_180_FLICK_SPEED}, "release": [&"brake"], "press": [&"steer_left"], "mark": true},
			# Rolling nose-first now: select forward, and steer against the
			# rotation to stop it.
			{"when": {"rotation_deg_below": -REVERSE_180_CATCH_DEG}, "release": [&"steer_left"], "press": [&"steer_right", &"accelerate"]},
			# was "release": [&"steer_right"] -> steered back (the user's verdict, 15:24).
			{"when": {"rotation_deg_below": -170.0}, "steer_deg": 0.0},
			# was the end of the script -> up to speed: a touch of lock to point the
			# nose at the goal (the flick leaves the car to the right of the line,
			# heading further right), and over the goal line on the power.
			{"when": {"speed_above": REVERSE_180_DRIVE_AWAY_SPEED}, "press": [&"steer_left"]},
			# was "release": [&"steer_left"] -> steered back (the user's verdict, 15:24).
			{"when": {"after": REVERSE_180_LINE_UP_TAP}, "steer_deg": 0.0},
			{"when": {"goal_distance_below": 0.0}},
		],
		"settle": 1.0,
		"time_limit": 30.0,
		# Target time for the whole run [s]; presentation only, nothing judges it.
		# target 7.0 s - certified run 6.4 s at HEAD (eed237f).
		# was 7.0 -> 11.0 - the run goes on to the 100 m board now: certified run
		# 10.3 s at HEAD (c47aa3f), over the goal line at 9.3 s. The gold time.
		# was 11.0 -> 8.3 - the run clock (start line, reversing, to goal line):
		# certified run 7.70 s at HEAD (f4652eb). The gold time.
		"target_time_s": 8.3,
		# Medal times [s]: gold / silver / bronze - certified 10.3 s at HEAD (c47aa3f):
		# +7 %, +26 %, +50 %.
		# was 11.0 / 13.0 / 15.5 -> 8.3 / 9.7 / 11.5 - the run clock: certified
		# 7.70 s at HEAD (f4652eb), the 1.63 s to the line and the 1 s settle no
		# longer on it: +8 %, +26 %, +49 %.
		# 8.3 / 9.7 / 11.5 stay - the steering feel moved the certified run
		# 7.68 -> 7.72 s at 3781c8a, +0.52 %: +8 % to gold.
		# 8.3 / 9.7 / 11.5 stay - the caster return and the driver steering
		# back actively (the user's verdict, 15:24) left the certified run at
		# 7.72 s: +8 % to gold.
		"gold_time_s": 8.3,
		"silver_time_s": 9.7,
		"bronze_time_s": 11.5,
	}


## The medal a passed run of `test` earns with a run time of `run_time_s` (the
## verdict's run_time_s metric): "gold", "silver", "bronze", or "" for a run
## slower than bronze or a test without medal times. Says nothing about pass or
## fail: the caller only asks for a run that passed.
static func medal_for(test: Dictionary, run_time_s: float) -> String:
	for medal in MEDALS:
		var key := medal + "_time_s"
		if test.has(key) and run_time_s <= test[key]:
			return medal
	return ""


# =============================================================================
#  Running one test
# =============================================================================

## Puts the car on the test's start point, stands the cones back up and returns
## the run. Call tick() once per physics frame until `finished`.
static func begin(definition: Dictionary, target_car: ArcadeCar, test_pad: Node, use_script := true) -> HandlingTests:
	var run := HandlingTests.new()
	run.test = definition
	run.car = target_car
	run.pad = test_pad
	run.scripted = use_script
	run._start()
	return run


func _start() -> void:
	_release_all()
	var spawn := car.get_spawn_transform()
	var offset: Vector3 = test.get("start_offset", Vector3.ZERO)
	var heading := deg_to_rad(test.get("start_heading_deg", 0.0))
	# The certified fresh car's tank: full, its mass with it - the certified
	# runs are the debug car, deliberately full. A reset keeps the fuel (the
	# user's report, 2026-09-22 12:55: resetting is not refuelling, fuel comes
	# from a gas station or a canister, tests must not affect the game); the
	# test start hands out the fresh car's full tank here, before any physics
	# frame - and before the reset, which stands the car on its springs by its
	# mass (_settle_suspension reads total_mass()) and keeps the tank it finds:
	# exactly what reset_to set until then, so every certified run's physics
	# is the bit it was. The game's reset never refuels.
	car.fuel_l = ArcadeCar.FUEL_TANK_CAPACITY_L
	car.fuel_mass = car.fuel_l * ArcadeCar.FUEL_DENSITY
	car.reset_to(Transform3D(spawn.basis.rotated(Vector3.UP, heading), spawn.origin + offset))
	# The certified fresh car's temperatures: the coolant at operating with the
	# fan off, the tyres at operating, the brakes at the air's, the tick's heat
	# trackers and the idle hunt's phase at 0 - exactly what reset_to used to
	# set, so every certified run's physics is the bit it was. A reset keeps
	# the heat now (the user's report, 2026-09-22 morning: R must not turn
	# back time on temperature); a test starting is the one place that hands
	# out the fresh car, before any physics frame.
	car.coolant_temp = 1.0
	car.coolant_fan_on = false
	car._combustion_heat_w = 0.0
	car._idle_wobble_phase = 0.0
	car.front_tyre_temp = 1.0
	car.rear_tyre_temp = 1.0
	car.front_brake_temp = 0.0
	car.rear_brake_temp = 0.0
	car._front_tyre_heat_w = 0.0
	car._rear_tyre_heat_w = 0.0
	car._front_brake_heat_w = 0.0
	car._rear_brake_heat_w = 0.0
	# And the certified fresh car's components: new, nothing worn, the clutch's
	# slip tracker at 0 - a reset keeps the wear (R does not un-wear: the
	# user's wear-and-aging thought, 2026-09-22 07:55), a test
	# starting hands out the new car, before any physics frame.
	car.clutch_wear = 0.0
	car.front_brake_wear = 0.0
	car.rear_brake_wear = 0.0
	car.front_tyre_wear = 0.0
	car.rear_tyre_wear = 0.0
	car.engine_wear = 0.0
	car._clutch_slip_w = 0.0
	# The reset unloads the car; the test's payload goes on after it.
	car.payload_mass = float(test.get("payload_kg", 0.0))
	if pad != null and pad.has_method("reset_cones"):
		pad.reset_cones()

	_start_position = car.global_position
	_start_forward = -car.global_basis.z
	_mark_position = _start_position
	_start_yaw = car.global_rotation.y
	_previous_yaw = _start_yaw
	_line_side = _past_start_line()
	if test.kind == KIND_SLALOM:
		_gates = TestPad.slalom_cone_positions()
		_gate_offsets.resize(_gates.size())
		_gate_offsets.fill(NAN)


## Advances the run by one physics frame: tracks the car, then lets the
## scripted driver work the controls for the coming frame.
func tick(delta: float) -> void:
	if finished:
		return
	elapsed += delta
	_since_step += delta
	if _run_started and not _run_stopped:
		_run_time += delta
	_track_start_line()
	var yaw := car.global_rotation.y
	var turned := angle_difference(_previous_yaw, yaw)
	_rotation += turned
	_previous_yaw = yaw
	# The speed the manoeuvre was entered at: the drive to the goal is not part of it.
	if not _spin_settled:
		_peak_speed = maxf(_peak_speed, _speed())
	_peak_reverse_speed = maxf(_peak_reverse_speed, -car.forward_speed)
	if test.kind == KIND_SLALOM:
		_track_slalom()
	if test.has("goal_mode"):
		_track_goal(turned / delta)
	# The finish stops the clock, crossed or not: a start line crossed after the
	# finish starts nothing.
	if not _run_stopped and _at_finish():
		_run_stopped = true

	if scripted:
		_drive()
	var steps: Array = test.steps
	if _all_steps_done_at < 0.0 and (_step_index >= steps.size() or not scripted) and _is_complete():
		_all_steps_done_at = elapsed
	if _all_steps_done_at >= 0.0 and elapsed - _all_steps_done_at >= test.get("settle", 1.0):
		_finish()
	elif elapsed >= test.time_limit:
		_timed_out = true
		_finish()


## One line on where the run stands, for tracing a test while tuning it.
func describe_state() -> String:
	var state := "t=%5.2f run=%5.2f step=%d pos=(%7.2f, %7.2f) fwd=%6.2f lat=%6.2f rot=%7.1f" % [
		elapsed, _run_time, _step_index, car.global_position.x, car.global_position.z,
		car.forward_speed, car.lateral_speed, rad_to_deg(_rotation),
	]
	if test.has("goal_mode"):
		state += " goal=%6.1f bearing=%6.1f%s" % [_goal_distance(), _goal_bearing_deg(), " settled" if _spin_settled else ""]
	return state


## Where the run stands, for a HUD to show while a human drives. Always holds
## `kind`, and the run clock: run_started (over the start line) and run_time_s
## (0 until then, standing once at the finish); the rest depends on the kind:
##   slalom    gates_reached, gates_total
##   spin      rotation_deg (left positive), target_rotation_deg, spin_done
##             (the rotation has settled and been noted; the goal counts from
##             here), spin_overshot (it went on past the tolerance), goal_mode, goal_distance_m (left to the goal)
##   reverse spin  the same, plus reverse_speed_ms and up_to_speed (reversed
##             fast enough to count)
##   stop box  distance_to_box_m (along the start heading, to the centre of the
##             box; negative once past it), up_to_speed (fast enough to count)
func progress() -> Dictionary:
	var state := _kind_progress()
	state["run_started"] = _run_started
	state["run_time_s"] = _run_time
	return state


func _kind_progress() -> Dictionary:
	match test.kind:
		KIND_SLALOM:
			return {"kind": test.kind, "gates_reached": _gate_index, "gates_total": _gates.size()}
		KIND_SPIN, KIND_REVERSE_SPIN:
			var spin := {
				"kind": test.kind,
				"rotation_deg": rad_to_deg(_rotation),
				"target_rotation_deg": test.target_rotation_deg,
				"spin_done": _spin_settled,
				"spin_overshot": _spin_overshot,
				"goal_mode": test.get("goal_mode", &""),
				"goal_distance_m": maxf(_goal_distance(), 0.0) if test.has("goal_mode") else 0.0,
			}
			if test.kind == KIND_REVERSE_SPIN:
				spin["reverse_speed_ms"] = maxf(-car.forward_speed, 0.0)
				spin["up_to_speed"] = _peak_reverse_speed >= REVERSE_180_MIN_ENTRY_SPEED
			return spin
		_:
			var box := TestPad.stop_box()
			var to_box: Vector3 = box.centre - car.global_position
			return {
				"kind": test.kind,
				"distance_to_box_m": to_box.dot(_start_forward),
				"up_to_speed": _peak_speed >= STOP_BOX_MIN_ENTRY_SPEED,
			}


## Whether the car has crossed the start line: the run clock is running, or
## stands at the finish. Until then the run is not being timed.
func started() -> bool:
	return _run_started


## The run clock [s]: from the start line crossing to now, or to the finish once
## the car is there. 0 before the crossing.
func run_time() -> float:
	return _run_time


## Stops the run early (e.g. the mission was cancelled) and frees the controls.
func abort() -> void:
	_finish()


## How many of the script's steps have fired so far (the next to fire is
## steps[step_index()]); read-only, for THE STUDY's captions. Nothing in a
## run reads it.
func step_index() -> int:
	return _step_index


## Where the run is headed once the manoeuvre is done: the start point, or the
## goal point down the line. Vector3.INF for a test without a goal_mode.
func goal_position() -> Vector3:
	match test.get("goal_mode", &""):
		GOAL_RETURN_TO_START:
			return _start_position
		GOAL_DRIVE_ON:
			return _start_position + _goal_direction() * test.goal_distance_m
		_:
			return Vector3.INF


## The verdict: { name, passed, metrics, checks }. `checks` lists every
## criterion as { label, passed }; `metrics` holds the measured numbers.
func result() -> Dictionary:
	var checks: Array[Dictionary] = []
	var metrics := {}
	match test.kind:
		KIND_SLALOM:
			_judge_slalom(checks, metrics)
		KIND_SPIN:
			_judge_spin(checks, metrics)
		KIND_STOP_BOX:
			_judge_stop_box(checks, metrics)
		KIND_REVERSE_SPIN:
			_judge_reverse_spin(checks, metrics)
	if test.has("goal_mode"):
		_judge_goal(checks)
	# A finish with no start line crossed before it has no run time to show.
	checks.append({"label": "run clock started: crossed its start line before the finish", "passed": _run_started})
	checks.append({"label": "finished inside the time limit", "passed": not _timed_out})
	# was snappedf(elapsed, 0.01), begin() to the end of the run -> the run clock:
	# start line to finish (see the top of the file).
	metrics["run_time_s"] = snappedf(_run_time, 0.01)
	var passed := true
	for check in checks:
		passed = passed and check.passed
	return {"name": test.name, "passed": passed, "metrics": metrics, "checks": checks}


## Two printable lines for a result: "PASS name" / "FAIL name", then metrics.
static func format_result(outcome: Dictionary) -> PackedStringArray:
	var parts := PackedStringArray()
	var metrics: Dictionary = outcome.metrics
	for key: String in metrics:
		parts.append("%s=%s" % [key, str(metrics[key])])
	var failed := PackedStringArray()
	for check: Dictionary in outcome.checks:
		if not check.passed:
			failed.append(check.label)
	var lines := PackedStringArray()
	lines.append("%s %s" % ["PASS" if outcome.passed else "FAIL", outcome.name])
	var metrics_line := "  metrics: " + ", ".join(parts)
	if not failed.is_empty():
		metrics_line += " | failed: " + "; ".join(failed)
	lines.append(metrics_line)
	return lines


# --- Scripted driver -------------------------------------------------------------

func _drive() -> void:
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
		if step.has("steer_deg"):
			_steer_hold = true
			_steer_target_deg = step.steer_deg
		if step.get("steer_free", false):
			_steer_hold = false
			_set_action(&"steer_left", false)
			_set_action(&"steer_right", false)
		if step.get("mark", false):
			_mark_position = car.global_position
			_marked = true
		_step_index += 1
		_since_step = 0.0

	# Cruise control, while the script is still running and off the brake.
	if test.has("hold_speed") and _step_index < steps.size() and not _pressed.get(&"brake", false):
		_set_action(&"accelerate", car.forward_speed < test.hold_speed)
	elif test.has("hold_speed"):
		_set_action(&"accelerate", false)
	if _steer_hold:
		_hold_steering()


## Taps the steering keys so the wheel hovers at _steer_target_deg, within a
## tick of the driver's hands of it (21.7 degrees for the test driver's,
## 1.3 at the front wheels), where a held key would overshoot by more than
## the wheel is off: at centre, the key towards it while the wheel is more
## than a tick off either way; at an angle, the key towards it while the
## wheel is short of it and the key back once it is more than a tick past
## it. On the move the caster closes the rest towards centre, at a
## standstill or in reverse the wheel stays where the hands leave it.
func _hold_steering() -> void:
	var band: float = car.driver_profile.steering_hand_speed / Engine.physics_ticks_per_second
	var side := signf(_steer_target_deg)
	if side == 0.0:
		# Centre: the key towards it while the wheel is more than a tick off
		# it either way, none within - on the move the caster closes the rest.
		_set_action(&"steer_left", car.steering_wheel_deg < -band)
		_set_action(&"steer_right", car.steering_wheel_deg > band)
		return
	# An angle: the key towards it while the wheel is short of it (the caster
	# pulls the wheel back from it all the while), the key back only once the
	# wheel is more than a tick past it, none between - the caster eases it
	# back down to the angle on its own.
	var along := side * car.steering_wheel_deg
	var wanted := side * _steer_target_deg
	var outward: StringName = &"steer_left" if side > 0.0 else &"steer_right"
	var inward: StringName = &"steer_right" if side > 0.0 else &"steer_left"
	_set_action(outward, along < wanted)
	_set_action(inward, along > wanted + band)


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
			"goal_distance_below":
				if _goal_distance() > value:
					return false
			_:
				push_error("HandlingTests: unknown step condition '%s'" % key)
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
	_steer_hold = false


func _finish() -> void:
	finished = true
	if scripted:
		_release_all()


# --- Tracking --------------------------------------------------------------------

func _speed() -> float:
	return Vector2(car.velocity.x, car.velocity.z).length()


## Distance covered along the start heading [m].
func _travelled() -> float:
	return (car.global_position - _start_position).dot(_start_forward)


## How far past its start line the car is, along the way the run goes [m];
## negative = short of it. The line runs right across the pad at start_line_z.
func _past_start_line() -> float:
	var line_z: float = test.get("start_line_z", TestPad.START_LINE_Z)
	var on_line := Vector3(car.global_position.x, car.global_position.y, line_z)
	return (car.global_position - on_line).dot(_goal_direction())


## Starts the run clock the tick the car gets over the start line (see the top
## of the file). Once: a second crossing starts nothing, and neither does one
## after the finish.
func _track_start_line() -> void:
	var side := _past_start_line()
	if not _run_started and not _run_stopped and _line_side < 0.0 and side >= 0.0:
		_run_started = true
	_line_side = side


## Whether the car is at the test's finish, where the run clock stops: the same
## for a human and the scripted driver.
func _at_finish() -> bool:
	match test.kind:
		KIND_SLALOM:
			return _gate_index >= _gates.size()
		KIND_SPIN, KIND_REVERSE_SPIN:
			return _goal_reached
		_:
			return _peak_speed >= STOP_BOX_MIN_ENTRY_SPEED and _speed() < STOPPED_SPEED


## A human-driven run is complete when its kind says so; a scripted one when
## the script has run out.
# was, spin: turned more than 90 degrees and stopped; reverse 180: turned more
# than 90 degrees and rolling nose-first at REVERSE_180_MIN_EXIT_SPEED -> at
# the goal - the run ends where it is headed, not where the rotation does. A
# spin that went on past its tolerance has its verdict already, and ends there.
func _is_complete() -> bool:
	if scripted:
		return true
	return _at_finish() or _spin_overshot


## Notes the rotation the moment the spin settles (see the top of the file),
## and from then on whether the car has got to the goal. `yaw_rate` [rad/s].
func _track_goal(yaw_rate: float) -> void:
	if not _spin_settled:
		var target: float = test.target_rotation_deg
		var rotation_deg := absf(rad_to_deg(_rotation))
		var settled := absf(rotation_deg - target) <= _rotation_tolerance_deg() and absf(yaw_rate) < deg_to_rad(SPIN_SETTLED_YAW_RATE_DEG)
		_spin_overshot = rotation_deg > target + _rotation_tolerance_deg()
		if settled or _spin_overshot:
			_spin_settled = true
			_settled_rotation = _rotation
			_settled_yaw = car.global_rotation.y
			_settled_position = car.global_position
	elif not _goal_reached:
		var distance := _goal_distance()
		if test.goal_mode == GOAL_DRIVE_ON:
			_goal_reached = distance <= 0.0 and _goal_side_offset() <= GOAL_RADIUS
		else:
			_goal_reached = distance <= GOAL_RADIUS


func _rotation_tolerance_deg() -> float:
	return REVERSE_180_HEADING_TOLERANCE_DEG if test.kind == KIND_REVERSE_SPIN else SPIN_HEADING_TOLERANCE_DEG


## The way the run goes, over the start line and on to a drive-on goal: the
## start heading, or for the reverse 180 the way the car reverses.
func _goal_direction() -> Vector3:
	return -_start_forward if test.kind == KIND_REVERSE_SPIN else _start_forward


## Distance left to the goal [m]: to the start point, or along the line to the
## goal line (negative once over it).
func _goal_distance() -> float:
	var to_goal := goal_position() - car.global_position
	if test.goal_mode == GOAL_DRIVE_ON:
		return to_goal.dot(_goal_direction())
	return Vector2(to_goal.x, to_goal.z).length()


## How far to the side of a drive-on goal's line the car is [m].
func _goal_side_offset() -> float:
	var to_goal := goal_position() - car.global_position
	return absf(to_goal.dot(_goal_direction().cross(Vector3.UP)))


## Where the goal point lies off the nose [degrees, left positive].
func _goal_bearing_deg() -> float:
	var to_goal := car.global_basis.inverse() * (goal_position() - car.global_position)
	return rad_to_deg(atan2(-to_goal.x, -to_goal.z))


## Notes how far to the side the car is as it draws level with each cone.
func _track_slalom() -> void:
	var along := (_gates[-1] - _gates[0]).normalized()
	var right := along.cross(Vector3.UP)
	while _gate_index < _gates.size():
		var to_car := car.global_position - _gates[_gate_index]
		if to_car.dot(along) < 0.0:
			break
		_gate_offsets[_gate_index] = to_car.dot(right)
		_gate_index += 1
		if _gate_index == _gates.size():
			# was elapsed, since begin() -> the run clock, since the start line:
			# it is a run-time check. The last cone is the slalom's finish, so
			# this is the verdict's run_time_s too.
			_slalom_time = _run_time


# --- Verdicts --------------------------------------------------------------------

func _judge_slalom(checks: Array[Dictionary], metrics: Dictionary) -> void:
	var passed_gates := 0
	var toppled := 0
	var closest := INF
	var widest := 0.0
	for i in _gates.size():
		var offset := _gate_offsets[i]
		var knocked: bool = pad != null and pad.is_cone_toppled(TestPad.GROUP_SLALOM, _gates[i])
		if knocked:
			toppled += 1
		if is_nan(offset):
			continue
		closest = minf(closest, absf(offset))
		widest = maxf(widest, absf(offset))
		# First cone is passed on its right (+), the next on its left, and so on.
		var wanted_side := 1.0 if i % 2 == 0 else -1.0
		if signf(offset) == wanted_side and absf(offset) <= SLALOM_GATE_WIDTH and not knocked:
			passed_gates += 1
	var missed := _gates.size() - passed_gates
	metrics["gates_passed"] = "%d/%d" % [passed_gates, _gates.size()]
	metrics["cones_hit"] = toppled
	metrics["closest_pass_m"] = snappedf(closest, 0.01)
	metrics["widest_pass_m"] = snappedf(widest, 0.01)
	metrics["slalom_time_s"] = snappedf(_slalom_time, 0.01)
	checks.append({"label": "at most %d gate(s) missed (missed %d)" % [SLALOM_MAX_MISSED, missed], "passed": missed <= SLALOM_MAX_MISSED})
	checks.append({
		"label": "last cone reached within %.0f s" % SLALOM_TIME_LIMIT,
		"passed": _slalom_time >= 0.0 and _slalom_time <= SLALOM_TIME_LIMIT,
	})


func _judge_spin(checks: Array[Dictionary], metrics: Dictionary) -> void:
	var target: float = test.target_rotation_deg
	# was rotation, heading and displacement as they stand at the end of the run
	# -> as noted when the spin settled - the run now goes on to its goal, and
	# driving there turns the car and brings it back up the road. A spin that
	# never settled is judged as it stands.
	var rotation_deg := rad_to_deg(_settled_rotation if _spin_settled else _rotation)
	var yaw := _settled_yaw if _spin_settled else car.global_rotation.y
	var position := _settled_position if _spin_settled else car.global_position
	# was absf(rotation_deg - target), a signed comparison -> the size of the
	# rotation against the target - a clean 180 to the right (-183.4) read as
	# "off by 363.4" and failed; either direction is a spin.
	var rotation_error := absf(absf(rotation_deg) - target)
	# was the same absf(rotation_deg - target) -> where the nose actually points
	# against the target heading (the heading the run started on plus the target
	# rotation, left positive), wrapped to +-180 - the metric mixed rotation up
	# with heading: the same mirrored 180 now reads 3.4, not 363.4.
	var target_heading := _start_yaw + deg_to_rad(target)
	var heading_error := absf(rad_to_deg(angle_difference(target_heading, yaw)))
	var displacement := (position - _mark_position).dot(_start_forward)
	metrics["rotation_deg"] = snappedf(rotation_deg, 0.1)
	metrics["heading_error_deg"] = snappedf(heading_error, 0.1)
	metrics["net_forward_m"] = snappedf(displacement, 0.1)
	metrics["entry_speed_ms"] = snappedf(_peak_speed, 0.1)
	metrics["final_speed_ms"] = snappedf(car.forward_speed, 0.1)
	checks.append({
		"label": "rotation within %.0f deg of %.0f, either direction (off by %.1f)" % [SPIN_HEADING_TOLERANCE_DEG, target, rotation_error],
		"passed": rotation_error <= SPIN_HEADING_TOLERANCE_DEG,
	})
	checks.append({
		"label": "net forward displacement positive (%.1f m)" % displacement,
		"passed": (_marked or not scripted) and displacement > SPIN_MIN_FORWARD_DISPLACEMENT,
	})


func _judge_reverse_spin(checks: Array[Dictionary], metrics: Dictionary) -> void:
	var target: float = test.target_rotation_deg
	# The rotation as noted when the flick settled (see _judge_spin); the travel
	# and the exit speed as they stand at the end of the run, at the goal.
	var rotation_deg := rad_to_deg(_settled_rotation if _spin_settled else _rotation)
	var heading_error := absf(absf(rotation_deg) - target)
	# The car reverses against its start heading and keeps going that way.
	var displacement := (car.global_position - _mark_position).dot(-_start_forward)
	metrics["rotation_deg"] = snappedf(rotation_deg, 0.1)
	metrics["heading_error_deg"] = snappedf(heading_error, 0.1)
	metrics["net_travel_m"] = snappedf(displacement, 0.1)
	metrics["reverse_speed_ms"] = snappedf(_peak_reverse_speed, 0.1)
	metrics["exit_speed_ms"] = snappedf(car.forward_speed, 0.1)
	checks.append({
		"label": "rotation within %.0f deg of %.0f (off by %.1f)" % [REVERSE_180_HEADING_TOLERANCE_DEG, target, heading_error],
		"passed": heading_error <= REVERSE_180_HEADING_TOLERANCE_DEG,
	})
	checks.append({
		"label": "reversed at %.0f m/s or more (peak %.1f)" % [REVERSE_180_MIN_ENTRY_SPEED, _peak_reverse_speed],
		"passed": _peak_reverse_speed >= REVERSE_180_MIN_ENTRY_SPEED,
	})
	checks.append({
		"label": "drives away forwards at %.0f m/s or more (%.1f)" % [REVERSE_180_MIN_EXIT_SPEED, car.forward_speed],
		"passed": car.forward_speed >= REVERSE_180_MIN_EXIT_SPEED,
	})
	checks.append({
		"label": "net travel along the reversing line positive (%.1f m)" % displacement,
		"passed": (_marked or not scripted) and displacement > REVERSE_180_MIN_DISPLACEMENT,
	})


## The destination, on top of the manoeuvre's own checks.
func _judge_goal(checks: Array[Dictionary]) -> void:
	var left := maxf(_goal_distance(), 0.0)
	if test.goal_mode == GOAL_RETURN_TO_START:
		checks.append({"label": "returned to the start, within %.0f m (%.1f m away)" % [GOAL_RADIUS, left], "passed": _goal_reached})
	else:
		checks.append({"label": "drove to the goal (%.1f m to go)" % left, "passed": _goal_reached})


func _judge_stop_box(checks: Array[Dictionary], metrics: Dictionary) -> void:
	var box := TestPad.stop_box()
	var half: Vector2 = box.size * 0.5
	# Margin: how far the worst corner of the car is inside the box. Negative =
	# that corner is outside.
	var margin := INF
	for corner_x: float in [-1.0, 1.0]:
		for corner_z: float in [-1.0, 1.0]:
			var local := Vector3(corner_x * TestPad.CAR_HALF_SIZE.x, 0.0, corner_z * TestPad.CAR_HALF_SIZE.y)
			var corner: Vector3 = car.global_transform * local - box.centre
			margin = minf(margin, minf(half.x - absf(corner.x), half.y - absf(corner.z)))
	var speed := _speed()
	metrics["box_margin_m"] = snappedf(margin, 0.01)
	metrics["centre_error_m"] = snappedf(Vector2(car.global_position.x - box.centre.x, car.global_position.z - box.centre.z).length(), 0.01)
	metrics["entry_speed_ms"] = snappedf(_peak_speed, 0.1)
	metrics["final_speed_ms"] = snappedf(speed, 0.01)
	metrics["cones_hit"] = pad.get_toppled_count(TestPad.GROUP_STOP_BOX) if pad != null else 0
	checks.append({"label": "stopped (%.2f m/s)" % speed, "passed": speed < STOPPED_SPEED})
	checks.append({"label": "whole car inside the box (margin %.2f m)" % margin, "passed": margin >= 0.0})
	checks.append({
		"label": "braked from at least %.0f m/s (peak %.1f)" % [STOP_BOX_MIN_ENTRY_SPEED, _peak_speed],
		"passed": _peak_speed >= STOP_BOX_MIN_ENTRY_SPEED,
	})
