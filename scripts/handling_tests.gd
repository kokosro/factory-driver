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
##   hold_speed             optional cruise control for the scripted driver,
##   steps                  the scripted driver: an ordered list of
##                          { when, press, release, mark } entries,
##   settle, time_limit     how the run ends.
## Steps fire strictly in order. `when` holds the conditions a step waits for
## (all must be true), measured the way a driver would judge them:
##   "after"        seconds since the previous step fired,
##   "speed_above"  / "speed_below"   road speed [m/s],
##   "travelled"    distance covered along the start heading [m],
##   "rotation_deg" how far the car has turned since the start (keeps counting
##                  past 180 / 360) [degrees, left positive]; at least this,
##   "rotation_deg_below"  the same, at most this (for turns to the right).
## A step with `mark` is the start of the manoeuvre: spin metrics count from it.
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

# --- Pass / fail tolerances ---------------------------------------------------

## Spins: the car must end within this of the target rotation [degrees] ...
const SPIN_HEADING_TOLERANCE_DEG := 35.0

## ... having travelled further than this along its original heading since the
## manoeuvre started [m]. A spin is done on the move, not on the spot.
const SPIN_MIN_FORWARD_DISPLACEMENT := 0.0

## Slalom: gates that may be missed (wrong side, too wide or cone knocked over).
const SLALOM_MAX_MISSED := 1

## Slalom: a pass further than this from the cone does not count [m].
const SLALOM_GATE_WIDTH := 6.0

## Slalom: generous time limit from the start to the last cone [s]. A steady
## 43 km/h run takes about 25 s.
const SLALOM_TIME_LIMIT := 45.0

## Stop box: the car counts as stopped below this speed [m/s].
const STOPPED_SPEED := 0.3

## Stop box: the car must have been at least this fast before braking [m/s],
## so crawling up to the box does not count (72 km/h).
const STOP_BOX_MIN_ENTRY_SPEED := 20.0

# --- Scripted driver ------------------------------------------------------------

const ACTIONS: Array[StringName] = [&"accelerate", &"brake", &"steer_left", &"steer_right", &"handbrake"]

## Slalom cruise speed [m/s], ~43 km/h. The car can weave wider than the cones
## need at this speed, so there is margin either side.
const SLALOM_SPEED := 12.0

## The scripted slalom driver turns in this far before it draws level with a
## cone [m], to allow for the steering and the tyres taking a moment to
## answer ...
const SLALOM_STEER_LEAD := 9.0

## ... (a swing from one side to the other covers about twice this [m]; the
## turn-in is timed so the middle of the swing lands beside the cone) ...
const SLALOM_HALF_SWING_DISTANCE := 6.0

## ... holds the lock until the nose points this far across the line [degrees] ...
const SLALOM_SWING_DEG := 22.0

## ... and lines up this far to the right of the cones at the start [m].
const SLALOM_START_OFFSET := 3.0

## Entry speeds for the spins [m/s]: ~90 km/h and ~125 km/h.
const SPIN_180_ENTRY_SPEED := 25.0
const SPIN_360_ENTRY_SPEED := 35.0

## How long the 180's opening feint to the right lasts [s].
const SPIN_180_FEINT_TIME := 1.0

## Stop box: speed the scripted driver builds before coasting in [m/s] ...
const STOP_BOX_APPROACH_SPEED := 25.0

## ... and how far before the centre of the box it hits the brakes [m].
const STOP_BOX_BRAKE_DISTANCE := 8.4

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

var _start_position: Vector3
var _start_forward: Vector3
var _previous_yaw := 0.0
var _rotation := 0.0  # Unwrapped yaw since the start [rad], left positive.
var _mark_position: Vector3
var _marked := false
var _peak_speed := 0.0
var _timed_out := false

# Slalom tracking.
var _gates: Array[Vector3] = []
var _gate_offsets: Array[float] = []  # Signed pass distance per gate; NAN = not reached.
var _gate_index := 0
var _slalom_time := -1.0


# =============================================================================
#  Test definitions
# =============================================================================

static func all_tests() -> Array[Dictionary]:
	return [slalom_test(), spin_180_test(), spin_360_test(), stop_box_test()]


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
		steps.append({"when": heading_reached, "release": [lock]})
	# Past the last cone: straighten up.
	var last_left := (cones.size() - 1) % 2 == 0
	var straighten: StringName = &"steer_right" if last_left else &"steer_left"
	var straight := {"rotation_deg_below": 0.0} if last_left else {"rotation_deg": 0.0}
	steps.append({"when": {"travelled": run_in + cones.size() * spacing - SLALOM_STEER_LEAD}, "press": [straighten]})
	steps.append({"when": straight, "release": [straighten]})
	return {
		"name": "SLALOM_TEST",
		"kind": KIND_SLALOM,
		"title": "SLALOM",
		"objective": "Weave through the cones: first cone on your left, then alternate. %d miss allowed, %.0f s." % [SLALOM_MAX_MISSED, SLALOM_TIME_LIMIT],
		"start_offset": start,
		"start_heading_deg": 0.0,
		"hold_speed": SLALOM_SPEED,
		"steps": steps,
		"settle": 1.0,
		"time_limit": SLALOM_TIME_LIMIT + 10.0,
	}


## Handbrake turn: from speed, flick in with the handbrake and let the tail come
## round. The handbrake stays on: with the loose rear leading, the car settles
## travelling backwards, and the brakes bring it to a stop facing the start.
static func spin_180_test() -> Dictionary:
	return {
		"name": "SPIN_180",
		"kind": KIND_SPIN,
		"title": "180 SPIN",
		"objective": "Handbrake turn: build speed (~90 km/h), spin round to face the start and stop.",
		"target_rotation_deg": 180.0,
		"start_offset": Vector3.ZERO,
		"start_heading_deg": 0.0,
		"steps": [
			{"when": {}, "press": [&"accelerate"]},
			# Feint right first: the slide carries the car off to the left, and the
			# feint cancels that so it ends up facing back down its own line.
			{"when": {"speed_above": SPIN_180_ENTRY_SPEED}, "press": [&"steer_right"]},
			{"when": {"after": SPIN_180_FEINT_TIME}, "release": [&"accelerate", &"steer_right"], "press": [&"steer_left", &"handbrake"], "mark": true},
			# Past 90 degrees the car rolls backwards, where the same lock steers the
			# other way: holding it now checks the swing instead of feeding it.
			{"when": {"rotation_deg": 150.0}},
			# Settled and rolling backwards: the accelerate key is the brake.
			{"when": {"after": 0.8}, "release": [&"steer_left"], "press": [&"accelerate"]},
			{"when": {"speed_below": 1.0}, "release": [&"accelerate"]},
		],
		"settle": 1.5,
		"time_limit": 30.0,
	}


## Full spin: flick in with the handbrake, steer the other way while the car
## travels backwards, let go of the handbrake past half way so the rear stops
## fighting the rotation, and steer back in as the nose comes round.
static func spin_360_test() -> Dictionary:
	return {
		"name": "SPIN_360",
		"kind": KIND_SPIN,
		"title": "360 SPIN",
		"objective": "Full spin: build speed (~125 km/h), spin all the way round and stop.",
		"target_rotation_deg": 360.0,
		"start_offset": Vector3.ZERO,
		"start_heading_deg": 0.0,
		"steps": [
			{"when": {}, "press": [&"accelerate"]},
			{"when": {"speed_above": SPIN_360_ENTRY_SPEED}, "release": [&"accelerate"], "press": [&"steer_left", &"handbrake"], "mark": true},
			{"when": {"rotation_deg": 120.0}, "release": [&"steer_left"], "press": [&"steer_right"]},
			{"when": {"rotation_deg": 160.0}, "release": [&"handbrake"]},
			{"when": {"rotation_deg": 270.0}, "release": [&"steer_right"], "press": [&"steer_left"]},
			{"when": {"rotation_deg": 350.0}, "release": [&"steer_left"]},
		],
		"settle": 2.0,
		"time_limit": 30.0,
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
		"steps": [
			{"when": {}, "press": [&"accelerate"]},
			{"when": {"speed_above": STOP_BOX_APPROACH_SPEED}, "release": [&"accelerate"]},
			{"when": {"travelled": distance_to_box - STOP_BOX_BRAKE_DISTANCE}, "press": [&"brake"]},
			# Stay on the brake to a stop: a held brake holds the car, it never
			# turns into reverse.
			{"when": {"speed_below": STOPPED_SPEED}},
		],
		"settle": 1.5,
		"time_limit": 30.0,
	}


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
	car.reset_to(Transform3D(spawn.basis.rotated(Vector3.UP, heading), spawn.origin + offset))
	if pad != null and pad.has_method("reset_cones"):
		pad.reset_cones()

	_start_position = car.global_position
	_start_forward = -car.global_basis.z
	_mark_position = _start_position
	_previous_yaw = car.global_rotation.y
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
	var yaw := car.global_rotation.y
	_rotation += angle_difference(_previous_yaw, yaw)
	_previous_yaw = yaw
	_peak_speed = maxf(_peak_speed, _speed())
	if test.kind == KIND_SLALOM:
		_track_slalom()

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
	return "t=%5.2f step=%d pos=(%7.2f, %7.2f) fwd=%6.2f lat=%6.2f rot=%7.1f" % [
		elapsed, _step_index, car.global_position.x, car.global_position.z,
		car.forward_speed, car.lateral_speed, rad_to_deg(_rotation),
	]


## Where the run stands, for a HUD to show while a human drives. Always holds
## `kind`; the rest depends on it:
##   slalom    gates_reached, gates_total
##   spin      rotation_deg (left positive), target_rotation_deg
##   stop box  distance_to_box_m (along the start heading, to the centre of the
##             box; negative once past it), up_to_speed (fast enough to count)
func progress() -> Dictionary:
	match test.kind:
		KIND_SLALOM:
			return {"kind": test.kind, "gates_reached": _gate_index, "gates_total": _gates.size()}
		KIND_SPIN:
			return {"kind": test.kind, "rotation_deg": rad_to_deg(_rotation), "target_rotation_deg": test.target_rotation_deg}
		_:
			var box := TestPad.stop_box()
			var to_box: Vector3 = box.centre - car.global_position
			return {
				"kind": test.kind,
				"distance_to_box_m": to_box.dot(_start_forward),
				"up_to_speed": _peak_speed >= STOP_BOX_MIN_ENTRY_SPEED,
			}


## Stops the run early (e.g. the mission was cancelled) and frees the controls.
func abort() -> void:
	_finish()


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
	checks.append({"label": "finished inside the time limit", "passed": not _timed_out})
	metrics["run_time_s"] = snappedf(elapsed, 0.01)
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
		for action: StringName in step.get("press", []):
			_set_action(action, true)
		if step.get("mark", false):
			_mark_position = car.global_position
			_marked = true
		_step_index += 1
		_since_step = 0.0

	# Cruise control, while the script is still running.
	if test.has("hold_speed") and _step_index < steps.size():
		_set_action(&"accelerate", car.forward_speed < test.hold_speed)
	elif test.has("hold_speed"):
		_set_action(&"accelerate", false)


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


## A human-driven run is complete when its kind says so; a scripted one when
## the script has run out.
func _is_complete() -> bool:
	if scripted:
		return true
	match test.kind:
		KIND_SLALOM:
			return _gate_index >= _gates.size()
		KIND_SPIN:
			return absf(rad_to_deg(_rotation)) > 90.0 and _speed() < STOPPED_SPEED
		_:
			return _peak_speed >= STOP_BOX_MIN_ENTRY_SPEED and _speed() < STOPPED_SPEED


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
			_slalom_time = elapsed


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
	var rotation_deg := rad_to_deg(_rotation)
	var heading_error := absf(rotation_deg - target)
	var displacement := (car.global_position - _mark_position).dot(_start_forward)
	metrics["rotation_deg"] = snappedf(rotation_deg, 0.1)
	metrics["heading_error_deg"] = snappedf(heading_error, 0.1)
	metrics["net_forward_m"] = snappedf(displacement, 0.1)
	metrics["entry_speed_ms"] = snappedf(_peak_speed, 0.1)
	metrics["final_speed_ms"] = snappedf(car.forward_speed, 0.1)
	checks.append({
		"label": "rotation within %.0f deg of %.0f (off by %.1f)" % [SPIN_HEADING_TOLERANCE_DEG, target, heading_error],
		"passed": heading_error <= SPIN_HEADING_TOLERANCE_DEG,
	})
	checks.append({
		"label": "net forward displacement positive (%.1f m)" % displacement,
		"passed": (_marked or not scripted) and displacement > SPIN_MIN_FORWARD_DISPLACEMENT,
	})


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
