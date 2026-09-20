extends SceneTree
## Headless smoke test for the main scene. Run via tests/run_tests.sh, or:
##
##   godot --headless --path . --import
##   godot --headless --path . --script res://tests/smoke_test.gd
##
## Loads the main scene, checks the key nodes exist, then drives the car with
## simulated input and checks it accelerates, steers, brakes, holds, reverses,
## slides under the handbrake, turns in less on the brakes, shifts gears and
## moves load between the axles, that it goes by its tyre forces (power against
## coasting in a corner, the path bending only as fast as the tyres can bend
## it, rear / front / all-wheel drive, brake bias, downforce, the low-speed
## blend), and checks the pad's ground texture, course queries and
## drive-through cones, and the road: the profile is pure, mean-neutral, gentle
## and level where it has to be, the wheels feel it (bumps at speed, the test
## dip's crest), and what the pad places stands on it.
## Exits 0 on success, 1 on any failed check. Later phases extend this file.

const MAIN_SCENE := "res://scenes/main.tscn"

## How long the handbrake corner holds the handbrake [physics frames], 0.4 s:
## a tap that kicks the tail out and lets the car catch it again. Was 60 (1 s):
## with tyre forces and yaw inertia, a full second at full lock from 60 km/h
## is a committed handbrake turn that ends up facing backwards (what SPIN_180
## is for), not a slide to recover from.
const HANDBRAKE_TAP_FRAMES := 24

## How long after the stop the held-accelerate exit from reverse gets to be
## under way [physics frames], 0.75 s: FORWARD_ENGAGE_GRACE (12 frames) plus
## margin to pick up speed.
const FORWARD_ENGAGE_FRAMES := 45

## Power against coasting through the same corner: least difference in heading
## gained over POWER_CORNER_FRAMES [rad], ~6 degrees. Measured: ~0.35 rad (the
## powered car runs wider: it gains speed, and load moves off the steered
## axle). A car whose throttle does not reach its tyres shows 0.
const POWER_COAST_MIN_YAW_DIFFERENCE := 0.1

## ... and least distance between where the two runs end up [m]. Measured: ~9.
const POWER_COAST_MIN_POSITION_DIFFERENCE := 2.0

## Speed the 2nd gear corners start from [m/s], ~65 km/h, and the 1st gear
## ones, ~32 km/h.
const CORNER_ENTRY_SPEED := 18.0
const LOW_GEAR_ENTRY_SPEED := 9.0

## How long the power / coast corners last [physics frames], 2 s; the 1st gear
## ones 1 s, so the automatic stays in 1st throughout.
const POWER_CORNER_FRAMES := 120
const LOW_GEAR_CORNER_FRAMES := 60

## Turn-in: sideways acceleration on the first tick of steering must stay under
## this share of the peak it builds to ...
const TURN_IN_FIRST_TICK_SHARE := 0.1

## ... and take at least this many ticks to get to half of it (0.1 s): the
## steering ramps, the tyres build slip, the mass answers. A body rotated by
## fiat shows its full sideways acceleration on the first tick.
const TURN_IN_MIN_BUILD_TICKS := 6

## No tick may accelerate the car harder than the tyres and the air can push
## [g]: TYRE_MU x the better axle's grip factor plus downforce and drag come
## to ~1.1 at these speeds.
const MAX_PLAUSIBLE_ACCEL_G := 1.2

## Parking pace for the low-speed blend checks [m/s], inside the blend
## (LOW_SPEED_BLEND_START .. LOW_SPEED_BLEND_END).
const CRAWL_SPEED := 2.0

## Downforce check: how long the carried load is averaged [physics frames],
## 0.5 s, and how close the average has to come to weight + downforce [N]. Was
## 1.0 N on the instantaneous loads - pre-2G flat-ground exactness; the road now
## adds a mean-neutral ripple to the four wheel loads (up to ~1300 N at once at
## 160 km/h, all four together) and a few hundred N of real crest / dip load
## where the swell curves. Measured: the 30-frame average is 61 N off, with
## ~670 N of downforce to find; a car without downforce is 670 N off.
const DOWNFORCE_AVERAGE_FRAMES := 30
const DOWNFORCE_TOLERANCE := 150.0

## Micro-bumps: most their mean may be off 0 over the 200 m lane strip x = 0,
## z = 0 .. -200 in 5 cm steps [m], and least RMS they must show there [m].
## Measured: mean 0.06 mm, RMS 3.8 mm.
const MICRO_MEAN_TOLERANCE := 0.0005
const MICRO_MIN_RMS := 0.001

## The lane's elevation has to be worth the name: least height between its
## lowest and highest point along x = 0 [m]. Measured: 2.2 m.
const LANE_MIN_ELEVATION_RANGE := 1.0

## Bumps at speed: the flat-out run gets this long to build speed, then the
## wheel loads are sampled for this long [physics frames], 5 s and 10 s.
const ROAD_FEEL_RUN_UP_FRAMES := 300
const ROAD_FEEL_SAMPLE_FRAMES := 600

## ... every wheel's load must swing at least this much about its baseline
## (half its axle's static + transfer + aero share) [RMS, share of the wheel's
## static load]. Measured: 0.070 - 0.073. A car that does not feel the road
## shows 0.
const ROAD_FEEL_MIN_RIPPLE := 0.02

## ... and each axle's load, averaged over the run, must stay this close to its
## baseline [N]: the road moves load around, it does not add any. Measured:
## front +13 N, rear +22 N (of ~5000 N and ~8200 N; the run ends on the way up
## the first swell, whose hollow presses the car down a little).
const ROAD_FEEL_MEAN_TOLERANCE := 60.0

## ... and the run has to get onto the swell: least elevation it must reach
## [m]. Measured: 0.43 m, at z = -428.
const ROAD_FEEL_MIN_CLIMB := 0.25

## ... while the body rides the elevation: most the car's height may be off the
## ground's under it [m]. Measured: 0.
const BODY_ON_GROUND_TOLERANCE := 0.001

## Crest test: a standing start this far before the road's test dip [m], flat
## out, crosses it at ~25 m/s (90 km/h), where the dip's 10 m come by at 2.5 Hz:
## close above the ride frequency, the suspension cannot follow it down.
const CREST_RUN_UP := 75.0

## Going in, every wheel's load must dip at least this far below its baseline,
## and at the bottom of the dip rise at least this far above it [share of the
## baseline]. Measured: dips 0.33 - 0.43, rises 0.53 - 0.72.
const CREST_MIN_DIP := 0.2
const CREST_MIN_RISE := 0.25

## A wheel counts as in the dip within this far of its centre [m] (the dip is
## 10 m long), and as past it from CREST_SETTLED_FROM to CREST_SETTLED_TO past
## the centre [m]: there its load must average back to the baseline to within
## CREST_SETTLED_TOLERANCE [share of the baseline]. Measured: 0.012.
const CREST_WINDOW := 7.0
const CREST_SETTLED_FROM := 25.0
const CREST_SETTLED_TO := 45.0
const CREST_SETTLED_TOLERANCE := 0.03

## Placed objects: most the foot of a cone, board post or pylon may be off the
## ground under it [m]. Measured: 0 (they are placed on the same function).
const PLACED_ON_GROUND_TOLERANCE := 0.01

var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var packed: PackedScene = load(MAIN_SCENE)
	if not _check(packed != null, "main scene loads"):
		_finish()
		return
	var main := packed.instantiate()
	root.add_child(main)
	await _step(60)

	var car := main.get_node_or_null("Car") as ArcadeCar
	var hud := main.get_node_or_null("HUD")
	var speed_label := main.get_node_or_null("HUD/SpeedLabel") as Label
	var camera := main.get_node_or_null("ChaseCamera") as Camera3D
	_check(car != null, "car node exists and is an ArcadeCar")
	_check(hud != null and speed_label != null, "HUD with speed label exists")
	_check(camera != null and camera.current, "chase camera exists and is current")
	_check(main.get_node_or_null("Sun") is DirectionalLight3D, "sun light exists")
	_check(main.get_node_or_null("WorldEnvironment") is WorldEnvironment, "world environment exists")
	_check(main.get_node("TestPad").get_child_count() > 1, "test pad generated its markers")
	if car == null or speed_label == null or camera == null:
		_finish()
		return

	_check(car.is_on_floor(), "car rests on the ground")
	_check(absf(car.forward_speed) < 0.01, "car is stationary without input (%.3f m/s)" % car.forward_speed)
	_check(speed_label.text == "0 km/h", "HUD reads 0 km/h at rest ('%s')" % speed_label.text)

	# Accelerate: moves along -Z, HUD follows, camera keeps up.
	Input.action_press("accelerate")
	await _step(120)
	_check(car.forward_speed > 10.0, "accelerates forward (%.1f m/s after 2 s)" % car.forward_speed)
	_check(car.global_position.z < -10.0, "travels along -Z (z = %.1f)" % car.global_position.z)
	_check(absf(car.global_position.x) < 0.01, "tracks straight without steering (x = %.3f)" % car.global_position.x)
	_check(speed_label.text == "%d km/h" % roundi(car.speed_kmh), "HUD shows current speed ('%s')" % speed_label.text)
	var camera_gap := camera.global_position.distance_to(car.global_position)
	_check(camera_gap > 3.0 and camera_gap < 15.0, "camera follows the car (%.1f m away)" % camera_gap)

	# Steer left: heading yaws positive, car drifts towards -X.
	var yaw_before := car.global_rotation.y
	Input.action_press("steer_left")
	await _step(45)
	Input.action_release("steer_left")
	_check(angle_difference(yaw_before, car.global_rotation.y) > 0.2, "steers left (yaw %.2f -> %.2f)" % [yaw_before, car.global_rotation.y])
	_check(car.global_position.x < -0.5, "turning left moves the car towards -X (x = %.1f)" % car.global_position.x)

	# Steer right turns the other way (once the steering has re-centred).
	await _step(15)
	yaw_before = car.global_rotation.y
	Input.action_press("steer_right")
	await _step(45)
	Input.action_release("steer_right")
	_check(angle_difference(yaw_before, car.global_rotation.y) < -0.2, "steers right (yaw %.2f -> %.2f)" % [yaw_before, car.global_rotation.y])
	Input.action_release("accelerate")
	await _step(30)
	_check(absf(car.lateral_speed) < 0.5, "lateral slip settles after steering (%.2f m/s)" % car.lateral_speed)

	# Coast, then brake to a stop: the held brake holds the car, it never turns
	# into reverse by itself.
	var speed_before := car.forward_speed
	await _step(30)
	_check(car.forward_speed < speed_before and car.forward_speed > 0.0, "coasts down gently (%.1f -> %.1f m/s)" % [speed_before, car.forward_speed])
	speed_before = car.forward_speed
	Input.action_press("brake")
	await _step(20)
	# 20 frames on the brakes: what the tyres can hold, no more (drag adds a
	# little). Lower bound was 0.95 -> 0.85 of the all-tyres-at-the-limit figure:
	# the brake force is now split by BRAKE_BIAS_FRONT, the fronts run at their
	# limit under ABS and the rears stay under theirs, so a real stop comes out
	# at ~0.9 of it. The upper bound is the one that matters: never more than
	# the tyres have.
	var brake_drop := speed_before - car.forward_speed
	var grip_drop := ArcadeCar.BRAKE_DECEL * 20.0 / 60.0
	_check(brake_drop > grip_drop * 0.85 and brake_drop < grip_drop * 1.0, "brakes hard, at the tyres' limit (%.1f -> %.1f m/s, all four at the limit would give %.1f)" % [speed_before, car.forward_speed, grip_drop])
	var z_stopped := 0.0
	var lowest_speed := 0.0
	for frame in 240:
		await physics_frame
		lowest_speed = minf(lowest_speed, car.forward_speed)
		if frame == 119:
			z_stopped = car.global_position.z
	_check(absf(car.forward_speed) < 0.01 and lowest_speed > -0.01, "held brake stops the car and never reverses (%.2f m/s, lowest %.2f)" % [car.forward_speed, lowest_speed])
	_check(absf(car.global_position.z - z_stopped) < 0.01 and not car.reverse_engaged, "held brake holds the car still (moved %.3f m in 2 s)" % absf(car.global_position.z - z_stopped))
	_check(not speed_label.text.begins_with("R"), "HUD does not flag reverse under a held brake ('%s')" % speed_label.text)

	# A fresh press of the brake key at a standstill engages reverse.
	Input.action_release("brake")
	await _step(5)
	Input.action_press("brake")
	await _step(240)
	_check(car.reverse_engaged and car.forward_speed < -1.0, "a fresh brake press at a standstill reverses (%.1f m/s)" % car.forward_speed)
	_check(car.forward_speed >= -ArcadeCar.MAX_REVERSE_SPEED - 0.01, "reverse speed is capped (%.1f m/s)" % car.forward_speed)
	_check(speed_label.text.begins_with("R"), "HUD flags reverse ('%s')" % speed_label.text)
	Input.action_release("brake")

	# In reverse the accelerate key is the brake: it stops the car. Held through
	# the stop it engages forward after FORWARD_ENGAGE_GRACE and drives away, the
	# key never released (the J-turn exit in one motion).
	Input.action_press("accelerate")
	var stop_frame := -1
	var engage_frame := -1
	var rolling_back_at_press := car.forward_speed
	for frame in 240:
		await physics_frame
		if stop_frame < 0 and car.reverse_engaged and absf(car.forward_speed) < 0.01:
			stop_frame = frame
		if stop_frame >= 0 and engage_frame < 0 and not car.reverse_engaged:
			engage_frame = frame
		if stop_frame >= 0 and frame == stop_frame + FORWARD_ENGAGE_FRAMES:
			break
	_check(rolling_back_at_press < -1.0 and stop_frame > 0, "held accelerate stops the reversing car, still in reverse (from %.1f m/s, stopped at frame %d)" % [rolling_back_at_press, stop_frame])
	_check(engage_frame > stop_frame and engage_frame - stop_frame <= FORWARD_ENGAGE_FRAMES, "accelerate held through the stop engages forward within the grace (%d frames after the stop)" % (engage_frame - stop_frame))
	_check(not car.reverse_engaged and car.forward_speed > 1.0, "the same held accelerate drives away in one motion (%.1f m/s, %d frames after the stop)" % [car.forward_speed, FORWARD_ENGAGE_FRAMES])
	_check(not speed_label.text.begins_with("R"), "HUD stops flagging reverse after the held exit ('%s')" % speed_label.text)
	Input.action_release("accelerate")

	# Both keys held at a standstill in reverse cancel out: forward never engages.
	Input.action_press("brake")
	await _step(120)
	Input.action_release("brake")
	await _step(5)
	Input.action_press("brake")
	await _step(1)
	Input.action_release("brake")
	await _step(2)
	var in_reverse_before := car.reverse_engaged
	Input.action_press("accelerate")
	Input.action_press("brake")
	var highest_speed := car.forward_speed
	for frame in 180:
		await physics_frame
		highest_speed = maxf(highest_speed, car.forward_speed)
	_check(in_reverse_before and car.reverse_engaged, "both keys held at a standstill in reverse never engage forward (reverse %s -> %s)" % [in_reverse_before, car.reverse_engaged])
	_check(absf(car.forward_speed) < 0.01 and highest_speed < 0.01, "both keys held hold the car (%.2f m/s, highest %.2f)" % [car.forward_speed, highest_speed])
	Input.action_release("accelerate")
	Input.action_release("brake")

	# A fresh press-and-hold of accelerate at a standstill engages forward and
	# drives in one motion too, without waiting for the grace.
	await _step(5)
	Input.action_press("accelerate")
	await _step(2)
	_check(not car.reverse_engaged and car.forward_speed > 0.0, "a fresh accelerate press at a standstill engages forward at once (%.2f m/s after 2 frames)" % car.forward_speed)
	await _step(58)
	_check(not car.reverse_engaged and car.forward_speed > 1.0, "a fresh accelerate press at a standstill drives forward again (%.1f m/s)" % car.forward_speed)
	Input.action_release("accelerate")

	# Reset puts the car back on the start line.
	car.reset_to_spawn()
	await _step(5)
	_check(car.global_position.length() < 0.1, "reset returns the car to spawn")

	# Handbrake in a straight line: slows the car more than coasting, stays
	# straight.
	await _get_up_to_speed(car)
	var speed_start := car.forward_speed
	Input.action_press("handbrake")
	await _step(60)
	Input.action_release("handbrake")
	var drop := speed_start - car.forward_speed
	var coast_drop := ArcadeCar.COAST_DECEL * 1.0
	_check(car.forward_speed > 0.0 and drop > coast_drop + 3.0, "handbrake slows the car without throttle (%.1f -> %.1f m/s)" % [speed_start, car.forward_speed])
	_check(drop < ArcadeCar.BRAKE_DECEL * 0.75, "handbrake is gentler than the brake (lost %.1f m/s in 1 s, the brake takes %.1f)" % [drop, ArcadeCar.BRAKE_DECEL])
	_check(absf(car.global_position.x) < 0.01 and absf(car.lateral_speed) < 0.01, "handbrake in a straight line stays straight (x = %.3f)" % car.global_position.x)

	# Same corner twice, without and with a tap of the handbrake: steer left off
	# the throttle for 2.5 s, the handbrake on for the first HANDBRAKE_TAP_FRAMES.
	var grip := await _corner(car, false)
	var slide := await _corner(car, true)
	_check(slide.peak_slip > grip.peak_slip * 1.5 and slide.peak_slip > grip.peak_slip + 1.5, "handbrake corner slides more (peak slip %.2f vs %.2f m/s)" % [slide.peak_slip, grip.peak_slip])
	_check(slide.peak_yaw > grip.peak_yaw * 1.3, "handbrake corner rotates more (peak yaw %.2f vs %.2f rad/s)" % [slide.peak_yaw, grip.peak_yaw])
	_check(slide.speed_drop > grip.speed_drop, "handbrake corner scrubs more speed (%.1f vs %.1f m/s)" % [slide.speed_drop, grip.speed_drop])
	_check(absf(slide.end_slip) < absf(grip.end_slip) + 0.75, "slip recovers after releasing the handbrake (%.2f vs %.2f m/s)" % [slide.end_slip, grip.end_slip])
	# slide_yaw_rate is now the nose swinging relative to the direction of travel
	# (was: yaw beyond the steering's aim). In this left corner positive = the
	# tail still stepping out, negative = the slide coming back, which is what a
	# caught tail does with the steering still held; it must not be snapping back
	# either.
	_check(slide.end_slide_yaw < 0.1 and slide.end_slide_yaw > -0.3, "tail catches after releasing the handbrake (slide yaw %.3f rad/s, negative = coming back)" % slide.end_slide_yaw)
	_check(grip.finite and slide.finite, "no NaN / inf in speeds or position while cornering")
	_check(maxf(grip.max_step, slide.max_step) < 1.5, "no teleporting while cornering (largest step %.2f m)" % maxf(grip.max_step, slide.max_step))

	# Friction ellipse: grip spent on braking is not there for turning. The same
	# turn-in on the brakes turns the car less, but still turns it.
	var free_turn := await _turn_in(car, false)
	var braked_turn := await _turn_in(car, true)
	_check(braked_turn < free_turn * 0.8, "braking while turning costs turn-in (%.2f vs %.2f rad in 0.75 s)" % [braked_turn, free_turn])
	_check(braked_turn > free_turn * 0.2, "the car still steers on the brakes (%.2f vs %.2f rad in 0.75 s)" % [braked_turn, free_turn])

	car.reset_to_spawn()
	await _step(5)
	_check(car.global_position.length() < 0.1 and car.slide_yaw_rate == 0.0, "reset also clears the slide")

	await _check_drivetrain(car, main.get_node_or_null("HUD/RpmLabel") as Label)
	await _check_force_dynamics(car)
	await _check_low_speed_blend(car)
	await _check_high_speed_stability(car)
	await _check_course(main.get_node("TestPad") as TestPad, car)
	_check_road_profile(main.get_node("TestPad") as TestPad, car)
	await _check_road_feel(main.get_node("TestPad") as TestPad, car)
	await _check_crest(car)
	_check_placed_on_ground(main.get_node("TestPad") as TestPad)

	_finish()


## Gears, RPM, manual shifting and weight transfer.
func _check_drivetrain(car: ArcadeCar, rpm_label: Label) -> void:
	var static_rear := ArcadeCar.REAR_WEIGHT_FRACTION
	var static_front := 1.0 - static_rear
	var stats := _new_stats()

	car.reset_to_spawn()
	await _step(10)
	_check(rpm_label != null, "HUD with tach label exists")
	if rpm_label == null:
		return
	_check(car.gear == 1 and car.automatic, "resting car sits in 1st, automatic (G%d)" % car.gear)
	_check(rpm_label.text.contains("rpm") and rpm_label.text.ends_with("G1"), "HUD tach shows rpm and gear ('%s')" % rpm_label.text)

	# Full throttle from rest in automatic: 1st gear pulls, load moves rearward,
	# RPM climbs with speed, then an upshift drops it.
	Input.action_press("accelerate")
	await _drive(car, 60, stats)
	_check(car.rear_load_fraction > static_rear + 0.05, "acceleration shifts load rearward (rear %.2f, static %.2f)" % [car.rear_load_fraction, static_rear])
	var gear_early := car.gear
	var rpm_early := car.engine_rpm
	await _drive(car, 30, stats)
	_check(car.gear == gear_early and car.engine_rpm > rpm_early + 500.0, "RPM rises with speed in a fixed gear (G%d: %d -> %d rpm)" % [car.gear, rpm_early, car.engine_rpm])
	var rpm_before_shift := car.engine_rpm
	var tach_red := false
	for frame in 300:
		if car.gear != gear_early:
			break
		rpm_before_shift = car.engine_rpm
		tach_red = rpm_label.get_theme_color("font_color") == rpm_label.get_parent().TACH_REDLINE_COLOR
		await _drive(car, 1, stats)
	_check(car.gear == gear_early + 1, "automatic shifts up under throttle (G%d -> G%d)" % [gear_early, car.gear])
	_check(stats.peak_traction_use > 0.999, "rear traction limit caps the drive force in 1st (use %.3f)" % stats.peak_traction_use)
	_check(tach_red, "HUD tach turns the warning colour near redline")
	await _drive(car, roundi(ArcadeCar.SHIFT_TIME * 60.0) + 6, stats)
	_check(car.engine_rpm < rpm_before_shift - 1500.0, "RPM drops on the upshift (%d -> %d rpm)" % [rpm_before_shift, car.engine_rpm])

	# Keep the throttle pinned: the gears keep coming and the car keeps pulling
	# far past what 1st gear alone could reach.
	var first_gear_top := car.speed_at_rpm(1, ArcadeCar.REDLINE_RPM)
	await _drive(car, 1200, stats)
	_check(car.gear >= 4, "gears advance under sustained throttle (G%d after 20 s)" % car.gear)
	_check(car.forward_speed > first_gear_top * 2.0, "speed keeps rising through the gears (%.1f m/s, 1st tops out at %.1f)" % [car.forward_speed, first_gear_top])
	Input.action_release("accelerate")

	# Braking at speed pitches the load onto the front axle.
	Input.action_press("brake")
	await _drive(car, 20, stats)
	Input.action_release("brake")
	_check(car.front_load_fraction > static_front + 0.1, "braking shifts load forward (front %.2f, static %.2f)" % [car.front_load_fraction, static_front])

	# The skidpad complaint: ~60 km/h in 4th has no pull; dropping to 2nd
	# brings the revs and the acceleration back.
	car.reset_to_spawn()
	await _step(10)
	Input.action_press("accelerate")
	for frame in 600:
		if car.forward_speed >= 16.7:
			break
		await _drive(car, 1, stats)
	Input.action_release("accelerate")
	while car.gear < 4:
		var gear_was := car.gear
		await _tap("shift_up")
		await _drive(car, 15, stats)
		if car.gear == gear_was:
			break
	_check(car.gear == 4 and not car.automatic, "shift-up key selects 4th and switches to manual (G%d)" % car.gear)
	_check(rpm_label.text.ends_with("G4 M"), "HUD flags manual mode ('%s')" % rpm_label.text)
	var accel_4th := await _measure_pull(car, stats)
	var rpm_4th := car.engine_rpm
	_check(car.gear == 4, "manual mode holds the gear at low revs (G%d, %d rpm)" % [car.gear, rpm_4th])
	await _tap("shift_down")
	await _drive(car, 15, stats)
	await _tap("shift_down")
	await _drive(car, 15, stats)
	var accel_2nd := await _measure_pull(car, stats)
	var rpm_2nd := car.engine_rpm
	_check(car.gear == 2, "shift-down key drops to 2nd (G%d)" % car.gear)
	_check(rpm_2nd > rpm_4th * 1.5, "downshift raises the revs (%d -> %d rpm)" % [rpm_4th, rpm_2nd])
	_check(accel_2nd > accel_4th * 1.5, "downshift restores the pull (%.2f -> %.2f m/s^2 at ~60 km/h)" % [accel_4th, accel_2nd])
	await _tap("toggle_gearbox")
	_check(car.automatic, "toggle key returns to the automatic")

	_check(stats.finite, "no NaN / inf in speeds, RPM or axle loads while driving the gears")
	_check(stats.max_step < 1.5, "no teleporting while driving the gears (largest step %.2f m)" % stats.max_step)
	_check(stats.min_rpm >= ArcadeCar.IDLE_RPM - 1.0 and stats.max_rpm <= ArcadeCar.REDLINE_RPM + 100.0, "RPM stays between idle and the limiter (%d..%d rpm)" % [stats.min_rpm, stats.max_rpm])
	_check(stats.min_load > 0.1 and stats.max_load < 0.9, "axle loads stay sane (%.2f..%.2f)" % [stats.min_load, stats.max_load])
	car.reset_to_spawn()
	await _step(5)


## The floor under the spin tuning: flat out in a straight line the car must
## not wander, and a steering jab at speed must settle at once, never getting
## near the slip angle where the stability assist lets go.
func _check_high_speed_stability(car: ArcadeCar) -> void:
	car.reset_to_spawn()
	await _step(10)
	Input.action_press("accelerate")
	await _step(900)
	_check(car.forward_speed > 40.0, "reaches high speed for the stability checks (%.1f m/s)" % car.forward_speed)
	_check(absf(car.global_position.x) < 0.01 and absf(car.global_rotation.y) < 0.001, "tracks dead straight flat out (x = %.4f m)" % car.global_position.x)

	var peak_slip_angle := 0.0
	Input.action_press("steer_left")
	for frame in 40:
		await physics_frame
		peak_slip_angle = maxf(peak_slip_angle, absf(atan2(car.lateral_speed, car.forward_speed)))
	Input.action_release("steer_left")
	var swings := 0
	var last_sign := 0.0
	for frame in 90:
		await physics_frame
		peak_slip_angle = maxf(peak_slip_angle, absf(atan2(car.lateral_speed, car.forward_speed)))
		if absf(car.yaw_rate) > 0.02:
			if last_sign != 0.0 and signf(car.yaw_rate) != last_sign:
				swings += 1
			last_sign = signf(car.yaw_rate)
	Input.action_release("accelerate")
	_check(peak_slip_angle < ArcadeCar.SPIN_COMMIT_ANGLE * 0.5, "a steering jab at speed stays far from a spin (peak slip angle %.1f deg)" % rad_to_deg(peak_slip_angle))
	_check(swings == 0, "no yaw oscillation after the jab (%d swings)" % swings)
	_check(absf(car.yaw_rate) < 0.01 and absf(car.lateral_speed) < 0.1, "the car settles within 1.5 s of the jab (yaw %.3f rad/s, slip %.2f m/s)" % [car.yaw_rate, car.lateral_speed])
	var heading := car.global_rotation.y
	await _step(60)
	_check(absf(angle_difference(heading, car.global_rotation.y)) < 0.001, "holds its new heading afterwards")


## The car goes by its tyres: what the throttle does in a corner, how a corner
## builds up, what the driven wheels and the brake bias change, and downforce.
func _check_force_dynamics(car: ArcadeCar) -> void:
	var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

	# (a) The same corner, same entry speed, same steering: coasting against
	# wide-open throttle. The user's complaint was that the two felt the same.
	var coast := await _steady_corner(car, CORNER_ENTRY_SPEED, POWER_CORNER_FRAMES, false, ArcadeCar.DrivenWheels.RWD)
	var power := await _steady_corner(car, CORNER_ENTRY_SPEED, POWER_CORNER_FRAMES, true, ArcadeCar.DrivenWheels.RWD)
	var yaw_difference := absf(power.yaw - coast.yaw)
	var position_difference: float = power.end_position.distance_to(coast.end_position)
	_check(absf(power.entry_speed - coast.entry_speed) < 0.5, "power / coast corners start from the same speed (%.1f vs %.1f m/s)" % [power.entry_speed, coast.entry_speed])
	_check(yaw_difference > POWER_COAST_MIN_YAW_DIFFERENCE, "throttle changes the corner: heading gained %.2f rad on power vs %.2f coasting (differs by %.2f, margin %.2f)" % [power.yaw, coast.yaw, yaw_difference, POWER_COAST_MIN_YAW_DIFFERENCE])
	_check(position_difference > POWER_COAST_MIN_POSITION_DIFFERENCE, "throttle changes the line: the two runs end %.1f m apart (margin %.1f)" % [position_difference, POWER_COAST_MIN_POSITION_DIFFERENCE])
	_check(power.radius > coast.radius * 1.15, "on power the car runs a wider line than coasting (radius %.1f vs %.1f m)" % [power.radius, coast.radius])
	var again := await _steady_corner(car, CORNER_ENTRY_SPEED, POWER_CORNER_FRAMES, true, ArcadeCar.DrivenWheels.RWD)
	_check(again.end_position == power.end_position and again.yaw == power.yaw, "the same corner driven twice ends in the same place, to the bit")

	# (b) Heading and velocity only meet through the tyres. Turning in, the
	# sideways acceleration has to BUILD: steering ramps, slip angles grow, the
	# mass answers; the nose leads and the direction of travel follows.
	var turn_in := await _turn_in_trace(car, CORNER_ENTRY_SPEED)
	var peak: float = turn_in.peak_accel
	_check(peak > 0.5 * gravity, "turning in builds real cornering force (peak %.1f m/s^2)" % peak)
	_check(turn_in.first_tick_accel < peak * TURN_IN_FIRST_TICK_SHARE, "no sideways jolt on the first tick of steering (%.2f m/s^2, peak %.1f)" % [turn_in.first_tick_accel, peak])
	_check(turn_in.ticks_to_half >= TURN_IN_MIN_BUILD_TICKS, "sideways acceleration builds over several ticks (%d ticks to half the peak, at least %d)" % [turn_in.ticks_to_half, TURN_IN_MIN_BUILD_TICKS])
	_check(turn_in.largest_rise < peak * 0.25, "it builds smoothly, no single tick adds a quarter of it (largest rise %.2f m/s^2)" % turn_in.largest_rise)
	_check(turn_in.heading_lead > 0.01, "the nose turns first and the direction of travel follows (nose leads by up to %.3f rad)" % turn_in.heading_lead)
	_check(turn_in.travel_turned > 0.1, "the direction of travel does follow (turned %.2f rad in 1 s)" % turn_in.travel_turned)
	_check(turn_in.peak_world_accel < MAX_PLAUSIBLE_ACCEL_G * gravity, "the velocity never changes faster than tyres and air can push (peak %.2f g, limit %.2f)" % [turn_in.peak_world_accel / gravity, MAX_PLAUSIBLE_ACCEL_G])

	# (e) The driven wheels give the car its character. 1st gear, moderate
	# speed, wide open in a corner: rear drive spends the rear tyres' grip and
	# the tail steps out; front drive spends the fronts' and the nose pushes
	# wide; all-wheel drive sits in between.
	var low_coast := await _steady_corner(car, LOW_GEAR_ENTRY_SPEED, LOW_GEAR_CORNER_FRAMES, false, ArcadeCar.DrivenWheels.RWD)
	var rwd := await _steady_corner(car, LOW_GEAR_ENTRY_SPEED, LOW_GEAR_CORNER_FRAMES, true, ArcadeCar.DrivenWheels.RWD)
	var fwd := await _steady_corner(car, LOW_GEAR_ENTRY_SPEED, LOW_GEAR_CORNER_FRAMES, true, ArcadeCar.DrivenWheels.FWD)
	var awd := await _steady_corner(car, LOW_GEAR_ENTRY_SPEED, LOW_GEAR_CORNER_FRAMES, true, ArcadeCar.DrivenWheels.AWD)
	_check(rwd.peak_rear_slip > low_coast.peak_rear_slip * 1.5 and rwd.peak_rear_slip > low_coast.peak_rear_slip + 0.03, "RWD: power in a low gear steps the tail out (peak rear slip angle %.3f rad vs %.3f coasting)" % [rwd.peak_rear_slip, low_coast.peak_rear_slip])
	_check(rwd.peak_rear_use > 0.999 and rwd.peak_front_use < 0.01, "RWD: the drive goes through the rear tyres only (grip use rear %.2f, front %.2f)" % [rwd.peak_rear_use, rwd.peak_front_use])
	_check(fwd.peak_front_use > 0.999 and fwd.peak_rear_use < 0.01, "FWD: the drive goes through the front tyres only (grip use front %.2f, rear %.2f)" % [fwd.peak_front_use, fwd.peak_rear_use])
	_check(fwd.yaw < low_coast.yaw * 0.9 and fwd.yaw < rwd.yaw * 0.9, "FWD: power pushes the nose wide (heading gained %.2f rad vs %.2f coasting, %.2f RWD)" % [fwd.yaw, low_coast.yaw, rwd.yaw])
	_check(fwd.peak_rear_slip < rwd.peak_rear_slip * 0.7, "FWD: the tail stays planted on power (peak rear slip angle %.3f rad vs %.3f RWD)" % [fwd.peak_rear_slip, rwd.peak_rear_slip])
	_check(awd.peak_front_use > 0.1 and awd.peak_rear_use > 0.1, "AWD: both axles drive (grip use front %.2f, rear %.2f)" % [awd.peak_front_use, awd.peak_rear_use])
	_check(awd.peak_rear_slip < rwd.peak_rear_slip * 0.7, "AWD: with the torque shared the tail stays in line (peak rear slip angle %.3f rad vs %.3f RWD)" % [awd.peak_rear_slip, rwd.peak_rear_slip])
	# In 1st all three have more torque than tyre. One gear up, where the tyres
	# can take it, the balance lines up: FWD pushes widest, RWD turns most.
	var fwd_second := await _steady_corner(car, CORNER_ENTRY_SPEED, POWER_CORNER_FRAMES, true, ArcadeCar.DrivenWheels.FWD)
	var awd_second := await _steady_corner(car, CORNER_ENTRY_SPEED, POWER_CORNER_FRAMES, true, ArcadeCar.DrivenWheels.AWD)
	_check(fwd_second.yaw < awd_second.yaw and awd_second.yaw < power.yaw, "in 2nd AWD sits between the two (heading gained: FWD %.2f, AWD %.2f, RWD %.2f rad)" % [fwd_second.yaw, awd_second.yaw, power.yaw])
	_check(awd.speed_gain > rwd.speed_gain and awd.speed_gain > fwd.speed_gain, "AWD puts the most power down out of the corner (+%.1f m/s vs RWD +%.1f, FWD +%.1f)" % [awd.speed_gain, rwd.speed_gain, fwd.speed_gain])
	var rwd_launch := await _launch(car, ArcadeCar.DrivenWheels.RWD)
	var fwd_launch := await _launch(car, ArcadeCar.DrivenWheels.FWD)
	_check(fwd_launch.speed < rwd_launch.speed * 0.8, "FWD launch is traction-limited: load moves off the driven axle (%.1f m/s after 2 s vs %.1f RWD)" % [fwd_launch.speed, rwd_launch.speed])
	_check(fwd_launch.driven_load < rwd_launch.driven_load, "... the driven axle carries %.0f N launching FWD, %.0f N RWD" % [fwd_launch.driven_load, rwd_launch.driven_load])
	for run: Dictionary in [coast, power, low_coast, rwd, fwd, awd, fwd_second, awd_second]:
		_check(run.finite and run.max_step < 1.5, "no NaN / inf / teleporting in the %s corner (largest step %.2f m)" % [run.label, run.max_step])
	_check(car.driven_wheels == ArcadeCar.DRIVEN_WHEELS, "the car is back on its own driven wheels")

	# Brake bias: a full stop in a straight line has the fronts at their limit
	# (ABS) and the rears under theirs.
	await _get_up_to_speed(car)
	Input.action_press("brake")
	await _step(30)
	_check(car.front_traction_use > 0.999 and car.rear_traction_use < 0.95 and car.rear_traction_use > 0.3, "brake bias: fronts at the limit, rears working under theirs (grip use front %.2f, rear %.2f)" % [car.front_traction_use, car.rear_traction_use])
	_check(is_equal_approx(car.front_slip_ratio, -ArcadeCar.ABS_SLIP_RATIO) and car.rear_slip_ratio > -ArcadeCar.PEAK_SLIP_RATIO, "ABS holds the front wheels, the rears never reach their peak (slip ratio front %.3f, rear %.3f)" % [car.front_slip_ratio, car.rear_slip_ratio])
	Input.action_release("brake")

	# Downforce: at speed the axles carry more than the car weighs, the rear
	# more so than the front.
	car.reset_to_spawn()
	await _step(10)
	Input.action_press("accelerate")
	await _step(900)
	Input.action_release("accelerate")
	await _step(30)
	var weight := ArcadeCar.CAR_MASS * gravity
	# The road moves load in and out of the wheels tick by tick, so what the
	# axles carry and what downforce should add are both averaged over
	# DOWNFORCE_AVERAGE_FRAMES before they are compared.
	var carried := 0.0
	var expected := 0.0
	for frame in DOWNFORCE_AVERAGE_FRAMES:
		await physics_frame
		carried += (car.front_axle_load + car.rear_axle_load) / DOWNFORCE_AVERAGE_FRAMES
		expected += ArcadeCar.DOWNFORCE_COEFF * car.forward_speed * car.forward_speed / DOWNFORCE_AVERAGE_FRAMES
	_check(absf(carried - weight - expected) < DOWNFORCE_TOLERANCE and expected > 0.04 * weight, "downforce adds to the axle loads at speed (+%.0f N at %.0f km/h, the car weighs %.0f N)" % [carried - weight, car.speed_kmh, weight])
	car.reset_to_spawn()
	await _step(5)


## (c) The low-speed blend: parking stays precise, the car stands still on the
## brake with the wheels turned, reverse still takes a fresh press, and there
## is no step in the steering on the way up through the blend.
func _check_low_speed_blend(car: ArcadeCar) -> void:
	car.reset_to_spawn()
	await _step(10)
	Input.action_press("accelerate")
	for frame in 120:
		if car.forward_speed >= CRAWL_SPEED:
			break
		await physics_frame
	Input.action_release("accelerate")
	Input.action_press("steer_left")
	await _step(60)
	# Rolling round at full lock: the turning circle of the wheel angle, no slip.
	var turning_radius := car.forward_speed / car.yaw_rate
	var geometric_radius := 2.0 * ArcadeCar.AXLE_DISTANCE / tan(ArcadeCar.MAX_STEER_LOCK)
	_check(car.forward_speed > ArcadeCar.LOW_SPEED_BLEND_START and car.forward_speed < ArcadeCar.LOW_SPEED_BLEND_END, "crawling inside the low-speed blend (%.1f m/s)" % car.forward_speed)
	_check(is_equal_approx(car.wheel_angle, ArcadeCar.MAX_STEER_LOCK), "full lock reaches the wheels at parking pace (%.2f rad)" % car.wheel_angle)
	_check(absf(turning_radius - geometric_radius) < geometric_radius * 0.1, "crawl steering rolls round the turning circle (radius %.2f m, geometry says %.2f)" % [turning_radius, geometric_radius])
	_check(absf(car.rear_slip_angle) < 0.02, "... with no slip at the rear axle (%.3f rad)" % car.rear_slip_angle)

	# Brake to a stop with the wheels still turned, and hold: no creep, no yaw.
	Input.action_press("brake")
	await _step(60)
	var held_position := car.global_position
	var held_yaw := car.global_rotation.y
	await _step(120)
	_check(car.global_position.distance_to(held_position) < 0.005 and absf(angle_difference(held_yaw, car.global_rotation.y)) < 0.001, "holds still on the brake with the wheels turned (moved %.4f m, turned %.5f rad in 2 s)" % [car.global_position.distance_to(held_position), absf(angle_difference(held_yaw, car.global_rotation.y))])
	_check(not car.reverse_engaged, "the held brake still never engages reverse")
	Input.action_release("brake")
	await _step(5)
	Input.action_press("brake")
	await _step(60)
	_check(car.reverse_engaged and car.forward_speed < -1.0, "a fresh brake press at the stop still reverses, steering held (%.1f m/s)" % car.forward_speed)
	_check(car.yaw_rate < -0.05, "... and the same lock swings the nose the other way in reverse (yaw %.2f rad/s)" % car.yaw_rate)
	Input.action_release("brake")
	Input.action_release("steer_left")

	# Up through the blend with the steering held: geometry hands over to the
	# tyres without a step in the yaw rate.
	car.reset_to_spawn()
	await _step(10)
	Input.action_press("steer_left")
	Input.action_press("accelerate")
	var largest_yaw_step := 0.0
	var yaw_rate_before := 0.0
	var finite := true
	for frame in 150:
		await physics_frame
		largest_yaw_step = maxf(largest_yaw_step, absf(car.yaw_rate - yaw_rate_before))
		yaw_rate_before = car.yaw_rate
		finite = finite and is_finite(car.yaw_rate) and is_finite(car.lateral_speed) and car.global_position.is_finite()
	Input.action_release("accelerate")
	Input.action_release("steer_left")
	_check(car.forward_speed > ArcadeCar.LOW_SPEED_BLEND_END + 2.0, "accelerated up through the blend and out of it (%.1f m/s)" % car.forward_speed)
	_check(largest_yaw_step < 0.06 and finite, "no step in the yaw rate on the way through the blend (largest change %.3f rad/s in a tick)" % largest_yaw_step)
	car.reset_to_spawn()
	await _step(5)


## Ground texture, course queries and drive-through cones.
func _check_course(pad: TestPad, car: ArcadeCar) -> void:
	_check(pad != null, "test pad is a TestPad")
	if pad == null:
		return

	# The asphalt: a real texture on the ground, visibly non-uniform, and the
	# same pixels every time.
	var material := pad.get_ground_material()
	var ground_mesh := pad.get_node_or_null("Ground/MeshInstance3D") as MeshInstance3D
	_check(material != null and material.albedo_texture != null, "ground material has an albedo texture")
	_check(ground_mesh != null and ground_mesh.material_override == material, "ground mesh uses the asphalt material")
	var image := pad.get_ground_image()
	_check(image != null and image.get_width() == TestPad.GROUND_TEXTURE_SIZE, "ground texture image exists (%d px)" % (image.get_width() if image != null else 0))
	if image != null:
		var distinct := {}
		var darkest := 1.0
		var brightest := 0.0
		for i in 64:
			var pixel := image.get_pixel((i * 37) % image.get_width(), (i * 101) % image.get_height())
			distinct[pixel.to_rgba32()] = true
			darkest = minf(darkest, pixel.get_luminance())
			brightest = maxf(brightest, pixel.get_luminance())
		_check(distinct.size() >= 16, "ground texture is non-uniform (%d distinct colours in 64 samples)" % distinct.size())
		_check(brightest - darkest > 0.1, "ground texture has visible contrast (luminance %.2f..%.2f)" % [darkest, brightest])
		var again := AsphaltTexture.build_image(TestPad.GROUND_TEXTURE_SIZE, TestPad.GROUND_TEXTURE_SEED)
		_check(again.get_data() == image.get_data(), "ground texture is deterministic (same seed, same pixels)")
	var ticks := pad.get_node_or_null("MotionTicks") as MultiMeshInstance3D
	_check(ticks != null and ticks.multimesh.instance_count > 1000, "motion ticks cover the ground")

	# What the missions ask the pad.
	var slalom := pad.get_cone_positions(TestPad.GROUP_SLALOM)
	_check(slalom.size() == TestPad.SLALOM_CONE_COUNT and slalom == TestPad.slalom_cone_positions(), "pad reports its %d slalom cones" % slalom.size())
	_check(root.get_tree().get_nodes_in_group(TestPad.GROUP_SLALOM).size() == slalom.size(), "slalom cones are in their node group")
	var circle := TestPad.skid_circle()
	var inner := pad.get_cone_positions(TestPad.GROUP_SKID_INNER)
	var outer := pad.get_cone_positions(TestPad.GROUP_SKID_OUTER)
	var on_circle := not inner.is_empty() and not outer.is_empty()
	for cone in inner:
		on_circle = on_circle and is_equal_approx(cone.distance_to(circle.centre), circle.inner_radius)
	for cone in outer:
		on_circle = on_circle and is_equal_approx(cone.distance_to(circle.centre), circle.outer_radius)
	_check(on_circle, "pad reports the skid circle cones (%d inner, %d outer)" % [inner.size(), outer.size()])
	_check(pad.get_cone_positions(TestPad.GROUP_STOP_BOX).size() == 4, "stop box has its four corner cones")

	# Cones never block: drive straight over the first slalom cone.
	var cone := slalom[0]
	var spawn := car.get_spawn_transform()
	car.reset_to(Transform3D(spawn.basis, Vector3(cone.x, spawn.origin.y, cone.z + 40.0)))
	pad.reset_cones()
	await _step(10)
	Input.action_press("accelerate")
	var speed_at_cone := 0.0
	var slowed := false
	for frame in 300:
		var speed_before := car.forward_speed
		await physics_frame
		if car.forward_speed < speed_before - 0.05:
			slowed = true
		if speed_at_cone == 0.0 and car.global_position.z <= cone.z:
			speed_at_cone = car.forward_speed
		if car.global_position.z < cone.z - 10.0:
			break
	Input.action_release("accelerate")
	_check(car.global_position.z < cone.z - 10.0 and speed_at_cone > 5.0, "car drives through a cone (%.1f m/s at the cone)" % speed_at_cone)
	_check(not slowed and absf(car.global_position.x - cone.x) < 0.01, "the cone does not slow or deflect the car (x off by %.3f m)" % absf(car.global_position.x - cone.x))
	_check(pad.is_cone_toppled(TestPad.GROUP_SLALOM, cone) and pad.get_toppled_count(TestPad.GROUP_SLALOM) == 1, "the cone it hit topples (and only that one)")
	pad.reset_cones()
	_check(pad.get_toppled_count(TestPad.GROUP_SLALOM) == 0, "resetting stands the cones back up")
	car.reset_to_spawn()
	await _step(5)


## The road profile by itself: pure, mean-neutral, gentle, level where the
## certifications run, and one road shared by pad and car.
func _check_road_profile(pad: TestPad, car: ArcadeCar) -> void:
	var road := pad.road_profile
	_check(road != null and road == car.road_profile, "pad and car drive on the same road profile")
	if road == null:
		return

	# Pure: the same point twice, and from a second road built from the same
	# constants, gives the same height to the last bit.
	var twin := RoadProfile.new()
	var pure := true
	for i in 200:
		var x := -300.0 + 7.3 * i
		var z := 140.0 - 6.1 * i
		var height := road.sample_height(x, z)
		pure = pure and height == road.sample_height(x, z) and height == twin.sample_height(x, z) and height == pad.sample_height(x, z)
		pure = pure and road.elevation_height(x, z) == pad.elevation_height(x, z)
	_check(pure, "road height is a pure function of (x, z): same point, same height, on every instance")

	# Micro-bumps: no DC part, but really there, and inside their bound.
	var micro_sum := 0.0
	var micro_squares := 0.0
	var micro_peak := 0.0
	var samples := 4000
	for i in samples:
		var micro := road.micro_height(0.0, -0.05 * i)
		micro_sum += micro
		micro_squares += micro * micro
		micro_peak = maxf(micro_peak, absf(micro))
	var micro_mean := micro_sum / samples
	_check(absf(micro_mean) < MICRO_MEAN_TOLERANCE, "micro-bumps are mean-neutral over a 200 m lane strip (mean %.3f mm, limit %.1f mm)" % [micro_mean * 1000.0, MICRO_MEAN_TOLERANCE * 1000.0])
	_check(sqrt(micro_squares / samples) > MICRO_MIN_RMS and micro_peak <= RoadProfile.MICRO_AMPLITUDE, "micro-bumps are there and bounded (RMS %.1f mm, peak %.1f mm of at most %.0f mm)" % [sqrt(micro_squares / samples) * 1000.0, micro_peak * 1000.0, RoadProfile.MICRO_AMPLITUDE * 1000.0])

	# Elevation along the lane: gentle, worth the name, and a function of z
	# only across the lane band.
	var steepest := 0.0
	var lowest := 0.0
	var highest := 0.0
	var side_pull := 0.0
	for i in 1451:
		var z := 150.0 - i
		var height := road.elevation_height(0.0, z)
		steepest = maxf(steepest, road.elevation_slope(0.0, z))
		lowest = minf(lowest, height)
		highest = maxf(highest, height)
		for x: float in [-RoadProfile.LANE_BAND_HALF_WIDTH, -2.5, 2.5, RoadProfile.LANE_BAND_HALF_WIDTH]:
			side_pull = maxf(side_pull, absf(road.elevation_height(x, z) - height))
	_check(steepest <= RoadProfile.MAX_SLOPE, "the lane's elevation stays gentle (steepest %.2f %%, limit %.1f %%)" % [steepest * 100.0, RoadProfile.MAX_SLOPE * 100.0])
	_check(highest - lowest > LANE_MIN_ELEVATION_RANGE and highest <= 1.5 and lowest >= -1.5, "the lane rises and falls (%.2f m .. %.2f m)" % [lowest, highest])
	_check(side_pull == 0.0, "across the lane band the elevation depends on z only (largest difference %.6f m)" % side_pull)

	# The four flat zones: exactly level, sampled out to a centimetre short of
	# their radius (on the radius itself rounding decides).
	var circle := TestPad.skid_circle()
	var box := TestPad.stop_box()
	var start_zone := 0.0
	var stop_zone := 0.0
	var skid_zone := 0.0
	var slalom_zone := 0.0
	for i in 64:
		var around := Vector3(cos(i * 0.7), 0.0, sin(i * 0.7))
		var reach := (i % 8 + 1) / 8.0
		var at_start := Vector3(0.0, 0.0, TestPad.START_LINE_Z) + around * (RoadProfile.START_ZONE_RADIUS - 0.01) * reach
		var at_stop: Vector3 = box.centre + around * (RoadProfile.STOP_ZONE_RADIUS - 0.01) * reach
		var at_skid: Vector3 = circle.centre + around * (RoadProfile.SKID_ZONE_RADIUS - 0.01) * reach
		start_zone = maxf(start_zone, absf(road.elevation_height(at_start.x, at_start.z)))
		stop_zone = maxf(stop_zone, absf(road.elevation_height(at_stop.x, at_stop.z)))
		skid_zone = maxf(skid_zone, absf(road.elevation_height(at_skid.x, at_skid.z)))
	for cone in TestPad.slalom_cone_positions():
		for side: float in [-1.0, -0.5, 0.0, 0.5, 1.0]:
			slalom_zone = maxf(slalom_zone, absf(road.elevation_height(cone.x + side * (RoadProfile.SLALOM_ZONE_BUFFER - 0.01), cone.z)))
	_check(start_zone == 0.0, "the start zone is level (largest elevation %.6f m within %.0f m of the line)" % [start_zone, RoadProfile.START_ZONE_RADIUS])
	_check(stop_zone == 0.0, "the stop box zone is level (largest elevation %.6f m within %.0f m of the box)" % [stop_zone, RoadProfile.STOP_ZONE_RADIUS])
	_check(slalom_zone == 0.0, "the slalom line is level (largest elevation %.6f m within %.0f m of the cones)" % [slalom_zone, RoadProfile.SLALOM_ZONE_BUFFER])
	_check(skid_zone == 0.0, "the skid pad is level (largest elevation %.6f m within %.0f m of its centre)" % [skid_zone, RoadProfile.SKID_ZONE_RADIUS])


## Half of what each axle carries before the road has its say [N]: static
## split, load transfer and downforce, front then rear. A wheel's baseline.
func _wheel_baselines(car: ArcadeCar) -> Array[float]:
	var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
	var weight := ArcadeCar.CAR_MASS * gravity
	var downforce := ArcadeCar.DOWNFORCE_COEFF * car.forward_speed * car.forward_speed
	return [
		(weight * car.front_load_fraction + downforce * ArcadeCar.AERO_BALANCE_FRONT) * 0.5,
		(weight * car.rear_load_fraction + downforce * (1.0 - ArcadeCar.AERO_BALANCE_FRONT)) * 0.5,
	]


## The car over bumps at speed: at rest the springs are at rest; flat out down
## the straight every wheel load swings with the road, the axle loads keep
## their mean, the body rides the elevation with the floor under it.
func _check_road_feel(pad: TestPad, car: ArcadeCar) -> void:
	var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
	var weight := ArcadeCar.CAR_MASS * gravity
	var static_loads: Array[float] = [weight * (1.0 - ArcadeCar.REAR_WEIGHT_FRACTION) * 0.5, weight * ArcadeCar.REAR_WEIGHT_FRACTION * 0.5]
	car.reset_to_spawn()
	await _step(10)
	var at_rest := car.wheel_loads.size() == 4
	for i in car.wheel_loads.size():
		at_rest = at_rest and absf(car.wheel_loads[i] - static_loads[i / 2]) < 0.01
	_check(at_rest, "standing still every wheel carries its static share (front %.1f N, rear %.1f N)" % [car.wheel_loads[0], car.wheel_loads[2]])

	var stats := _new_stats()
	Input.action_press("accelerate")
	await _drive(car, ROAD_FEEL_RUN_UP_FRAMES, stats)
	var deviation_sum: Array[float] = [0.0, 0.0, 0.0, 0.0]
	var deviation_squares: Array[float] = [0.0, 0.0, 0.0, 0.0]
	var loads_finite := true
	var on_floor := true
	var ground_gap := 0.0
	var highest := 0.0
	for frame in ROAD_FEEL_SAMPLE_FRAMES:
		await _drive(car, 1, stats)
		var baselines := _wheel_baselines(car)
		for i in 4:
			var deviation := car.wheel_loads[i] - baselines[i / 2]
			deviation_sum[i] += deviation
			deviation_squares[i] += deviation * deviation
			loads_finite = loads_finite and is_finite(car.wheel_loads[i]) and car.wheel_loads[i] >= 0.0
		on_floor = on_floor and car.is_on_floor()
		var ground := pad.elevation_height(car.global_position.x, car.global_position.z)
		ground_gap = maxf(ground_gap, absf(car.global_position.y - ground))
		highest = maxf(highest, ground)
	Input.action_release("accelerate")

	var least_ripple := INF
	var most_ripple := 0.0
	for i in 4:
		var ripple := sqrt(deviation_squares[i] / ROAD_FEEL_SAMPLE_FRAMES) / static_loads[i / 2]
		least_ripple = minf(least_ripple, ripple)
		most_ripple = maxf(most_ripple, ripple)
	var front_mean := (deviation_sum[0] + deviation_sum[1]) / ROAD_FEEL_SAMPLE_FRAMES
	var rear_mean := (deviation_sum[2] + deviation_sum[3]) / ROAD_FEEL_SAMPLE_FRAMES
	_check(car.forward_speed > 40.0 and highest > ROAD_FEEL_MIN_CLIMB, "flat-out run gets up to speed and onto the swell (%.1f m/s, %.2f m up)" % [car.forward_speed, highest])
	_check(least_ripple > ROAD_FEEL_MIN_RIPPLE, "every wheel's load swings with the road at speed (RMS %.3f .. %.3f of its static load, floor %.2f)" % [least_ripple, most_ripple, ROAD_FEEL_MIN_RIPPLE])
	_check(absf(front_mean) < ROAD_FEEL_MEAN_TOLERANCE and absf(rear_mean) < ROAD_FEEL_MEAN_TOLERANCE, "the road moves load around, it adds none: mean axle loads stay on their baseline (front %+.1f N, rear %+.1f N)" % [front_mean, rear_mean])
	_check(stats.finite and loads_finite, "no NaN / inf / negative wheel loads over the bumps")
	_check(stats.max_step < 1.5, "no teleporting over the bumps (largest step %.2f m)" % stats.max_step)
	_check(on_floor and ground_gap < BODY_ON_GROUND_TOLERANCE, "the body rides the elevation with the floor under it (largest gap %.4f m)" % ground_gap)
	_check(absf(car.global_position.x) < 0.01 and absf(car.global_rotation.y) < 0.001, "bumps and swell do not pull the car off line (x = %.4f m)" % car.global_position.x)

	car.reset_to_spawn()
	var reset_clean := true
	for i in 4:
		reset_clean = reset_clean and car.wheel_loads[i] == static_loads[i / 2]
	await _step(2)
	for i in 4:
		reset_clean = reset_clean and absf(car.wheel_loads[i] - static_loads[i / 2]) < 0.01
	_check(reset_clean, "reset puts the suspension at rest (front %.1f N, rear %.1f N a tick later)" % [car.wheel_loads[0], car.wheel_loads[2]])
	await _step(5)


## The crest test: drive over the road's test dip. Going in, the road drops
## away under each wheel faster than the car can follow: the load dips. At the
## bottom it comes back up: the load peaks. Past it the load settles again.
## Everything is timed by where each wheel is, not by frames.
func _check_crest(car: ArcadeCar) -> void:
	var dip := RoadProfile.TEST_DIP_CENTRE
	var spawn := car.get_spawn_transform()
	car.reset_to(Transform3D(spawn.basis, Vector3(dip.x, spawn.origin.y, dip.y + CREST_RUN_UP)))
	await _step(10)
	var stats := _new_stats()
	var lowest: Array[float] = [INF, INF, INF, INF]
	var lowest_at: Array[float] = [0.0, 0.0, 0.0, 0.0]
	var highest: Array[float] = [0.0, 0.0, 0.0, 0.0]
	var highest_at: Array[float] = [0.0, 0.0, 0.0, 0.0]
	var settled_sum: Array[float] = [0.0, 0.0, 0.0, 0.0]
	var settled_count: Array[int] = [0, 0, 0, 0]
	var crossing_speed := 0.0
	Input.action_press("accelerate")
	for frame in 900:
		await _drive(car, 1, stats)
		var baselines := _wheel_baselines(car)
		for i in 4:
			# How far this wheel is past the middle of the dip [m].
			var past := dip.y - (car.global_transform * ArcadeCar.WHEEL_CONTACT_POINTS[i]).z
			var load_ratio := car.wheel_loads[i] / baselines[i / 2]
			if absf(past) < CREST_WINDOW:
				if load_ratio < lowest[i]:
					lowest[i] = load_ratio
					lowest_at[i] = past
				if load_ratio > highest[i]:
					highest[i] = load_ratio
					highest_at[i] = past
			elif past > CREST_SETTLED_FROM and past < CREST_SETTLED_TO:
				settled_sum[i] += load_ratio
				settled_count[i] += 1
		if crossing_speed == 0.0 and car.global_position.z <= dip.y:
			crossing_speed = car.forward_speed
		if car.global_position.z < dip.y - CREST_SETTLED_TO - 5.0:
			break
	Input.action_release("accelerate")

	var least_dip := INF
	var least_rise := INF
	var dip_first := true
	var worst_settled := 0.0
	for i in 4:
		least_dip = minf(least_dip, 1.0 - lowest[i])
		least_rise = minf(least_rise, highest[i] - 1.0)
		dip_first = dip_first and lowest_at[i] < highest_at[i]
		worst_settled = maxf(worst_settled, absf(settled_sum[i] / maxi(settled_count[i], 1) - 1.0) if settled_count[i] > 0 else INF)
	_check(crossing_speed > 20.0 and crossing_speed < 30.0, "crest run crosses the test dip at speed (%.1f m/s)" % crossing_speed)
	_check(least_dip > CREST_MIN_DIP, "the road dropping away unloads every wheel (front left down to %.2f of its baseline %.1f m before the middle; least dip %.2f, floor %.2f)" % [lowest[0], -lowest_at[0], least_dip, CREST_MIN_DIP])
	_check(least_rise > CREST_MIN_RISE and dip_first, "the bottom of the dip loads every wheel up again, after the dip in load (front left up to %.2f, %.1f m past the middle; least rise %.2f, floor %.2f)" % [highest[0], highest_at[0], least_rise, CREST_MIN_RISE])
	_check(worst_settled < CREST_SETTLED_TOLERANCE, "past the dip the wheel loads settle back on their baseline (mean off by %.3f at most, limit %.2f)" % [worst_settled, CREST_SETTLED_TOLERANCE])
	_check(stats.finite and stats.max_step < 1.5, "no NaN / inf / teleporting through the dip (largest step %.2f m)" % stats.max_step)
	car.reset_to_spawn()
	await _step(5)


## What the pad places stands on the ground it shows: cones (their homes),
## the straight's distance board posts and the perimeter pylons.
func _check_placed_on_ground(pad: TestPad) -> void:
	var cone_gap := 0.0
	var cone_count := 0
	for group: StringName in [TestPad.GROUP_SLALOM, TestPad.GROUP_SKID_INNER, TestPad.GROUP_SKID_OUTER, TestPad.GROUP_STOP_BOX]:
		for home in pad.get_cone_positions(group):
			cone_gap = maxf(cone_gap, absf(home.y - pad.elevation_height(home.x, home.z)))
			cone_count += 1
	_check(cone_count > 0 and cone_gap <= PLACED_ON_GROUND_TOLERANCE, "all %d cones stand on the ground (largest gap %.4f m)" % [cone_count, cone_gap])

	# Boxes stand with their middle half their height above the ground.
	var box_gap := 0.0
	var box_count := 0
	var highest_foot := 0.0
	var lowest_foot := 0.0
	for path: String in ["Straight", "Pylons"]:
		var group := pad.get_node_or_null(path)
		if group == null:
			continue
		for child in group.get_children():
			var instance := child as MeshInstance3D
			if instance == null or not instance.mesh is BoxMesh:
				continue
			var size := (instance.mesh as BoxMesh).size
			# Uprights only: board posts and pylon shafts, not paint or caps.
			if size.y < 2.0 or size.y < size.x * 2.0:
				continue
			var foot := instance.position.y - size.y * 0.5
			var ground := pad.elevation_height(instance.position.x, instance.position.z)
			box_gap = maxf(box_gap, absf(foot - ground))
			highest_foot = maxf(highest_foot, foot)
			lowest_foot = minf(lowest_foot, foot)
			box_count += 1
	_check(box_count >= 40 and box_gap <= PLACED_ON_GROUND_TOLERANCE, "all %d board posts and pylons stand on the ground (largest gap %.4f m)" % [box_count, box_gap])
	_check(highest_foot > 0.5 and lowest_foot < -0.5, "... up and down the swell (feet from %.2f m to %.2f m)" % [lowest_foot, highest_foot])


## Resets the car and accelerates it in a straight line for 3 s, to ~60 km/h.
func _get_up_to_speed(car: ArcadeCar) -> void:
	car.reset_to_spawn()
	await _step(10)
	Input.action_press("accelerate")
	await _step(180)
	Input.action_release("accelerate")


## Drives one left corner (optionally with a tap of the handbrake going in) and
## returns peak slip / yaw, the end state and per-frame sanity stats.
func _corner(car: ArcadeCar, handbrake: bool) -> Dictionary:
	await _get_up_to_speed(car)
	var stats := {
		"peak_slip": 0.0, "peak_yaw": 0.0, "speed_drop": 0.0,
		"end_slip": 0.0, "end_slide_yaw": 0.0, "finite": true, "max_step": 0.0,
	}
	var speed_start := car.forward_speed
	Input.action_press("steer_left")
	if handbrake:
		Input.action_press("handbrake")
	for frame in 150:
		if frame == HANDBRAKE_TAP_FRAMES:
			Input.action_release("handbrake")
		if frame == 60:
			stats.speed_drop = speed_start - car.forward_speed
		var before := car.global_position
		await physics_frame
		var moved := car.global_position.distance_to(before)
		stats.max_step = maxf(stats.max_step, moved)
		if not (is_finite(car.forward_speed) and is_finite(car.lateral_speed) and is_finite(car.yaw_rate) and car.global_position.is_finite()):
			stats.finite = false
		if frame < 60:
			stats.peak_slip = maxf(stats.peak_slip, absf(car.lateral_speed))
			stats.peak_yaw = maxf(stats.peak_yaw, absf(car.yaw_rate))
	Input.action_release("steer_left")
	# Slip where the tyres are: the rear axle's sideways speed. (lateral_speed is
	# taken at the middle of the wheelbase, where a car rolling round a corner
	# with no slip at all still shows yaw rate x AXLE_DISTANCE of it, more the
	# slower and tighter it turns.)
	stats.end_slip = tan(car.rear_slip_angle) * absf(car.forward_speed)
	stats.end_slide_yaw = car.slide_yaw_rate
	return stats


## Accelerates to `entry_speed` on the car's own drivetrain, then holds full
## left steering for `frames` with the throttle wide open or closed on
## `layout`. Returns the heading gained [rad], the mean radius of the line [m],
## where it ended, peak slip angles / grip use, the speed gained and per-frame
## sanity stats.
func _steady_corner(car: ArcadeCar, entry_speed: float, frames: int, on_power: bool, layout: ArcadeCar.DrivenWheels) -> Dictionary:
	await _reach_speed(car, entry_speed)
	var run := {
		"label": "%s %s" % [ArcadeCar.DrivenWheels.keys()[layout], "power" if on_power else "coast"],
		"entry_speed": car.forward_speed, "yaw": 0.0, "radius": 0.0, "end_position": Vector3.ZERO, "speed_gain": 0.0,
		"peak_front_slip": 0.0, "peak_rear_slip": 0.0, "peak_front_use": 0.0, "peak_rear_use": 0.0,
		"finite": true, "max_step": 0.0,
	}
	var yaw_before := car.global_rotation.y
	var travelled := 0.0
	car.driven_wheels = layout
	Input.action_press("steer_left")
	if on_power:
		Input.action_press("accelerate")
	for frame in frames:
		var before := car.global_position
		await physics_frame
		var moved := car.global_position.distance_to(before)
		travelled += moved
		run.max_step = maxf(run.max_step, moved)
		run.yaw += angle_difference(yaw_before, car.global_rotation.y)
		yaw_before = car.global_rotation.y
		run.peak_front_slip = maxf(run.peak_front_slip, absf(car.front_slip_angle))
		run.peak_rear_slip = maxf(run.peak_rear_slip, absf(car.rear_slip_angle))
		if on_power:
			run.peak_front_use = maxf(run.peak_front_use, car.front_traction_use)
			run.peak_rear_use = maxf(run.peak_rear_use, car.rear_traction_use)
		if not (is_finite(car.forward_speed) and is_finite(car.lateral_speed) and is_finite(car.yaw_rate) and car.global_position.is_finite()):
			run.finite = false
	Input.action_release("steer_left")
	Input.action_release("accelerate")
	car.driven_wheels = ArcadeCar.DRIVEN_WHEELS
	run.radius = travelled / maxf(absf(run.yaw), 0.001)
	run.end_position = car.global_position
	run.speed_gain = car.forward_speed - run.entry_speed
	return run


## Coasts straight at `entry_speed`, then holds full left steering for 1 s and
## follows, tick by tick, the sideways acceleration the tyres make, the change
## of the world velocity, and how far the nose and the direction of travel
## have each turned.
func _turn_in_trace(car: ArcadeCar, entry_speed: float) -> Dictionary:
	await _reach_speed(car, entry_speed)
	var trace := {
		"first_tick_accel": 0.0, "peak_accel": 0.0, "ticks_to_half": 0, "largest_rise": 0.0,
		"heading_lead": 0.0, "travel_turned": 0.0, "peak_world_accel": 0.0,
	}
	var accels: Array[float] = []
	var heading_start := car.global_rotation.y
	var travel_start := atan2(-car.velocity.x, -car.velocity.z)
	var velocity_before := car.velocity
	Input.action_press("steer_left")
	for frame in 60:
		await physics_frame
		accels.append(car.lateral_accel)
		var horizontal_change := Vector2(car.velocity.x - velocity_before.x, car.velocity.z - velocity_before.z)
		trace.peak_world_accel = maxf(trace.peak_world_accel, horizontal_change.length() * 60.0)
		velocity_before = car.velocity
		var heading_turned := angle_difference(heading_start, car.global_rotation.y)
		trace.travel_turned = angle_difference(travel_start, atan2(-car.velocity.x, -car.velocity.z))
		trace.heading_lead = maxf(trace.heading_lead, heading_turned - trace.travel_turned)
	Input.action_release("steer_left")
	trace.first_tick_accel = absf(accels[0])
	for accel in accels:
		trace.peak_accel = maxf(trace.peak_accel, accel)
	for i in accels.size():
		if i > 0:
			trace.largest_rise = maxf(trace.largest_rise, accels[i] - accels[i - 1])
		if trace.ticks_to_half == 0 and accels[i] >= trace.peak_accel * 0.5:
			trace.ticks_to_half = i + 1
	return trace


## Full throttle from rest for 2 s on `layout`; returns the speed reached and
## the load on the driven axle at the end.
func _launch(car: ArcadeCar, layout: ArcadeCar.DrivenWheels) -> Dictionary:
	car.reset_to_spawn()
	await _step(10)
	car.driven_wheels = layout
	Input.action_press("accelerate")
	await _step(120)
	Input.action_release("accelerate")
	var launch := {
		"speed": car.forward_speed,
		"driven_load": car.front_axle_load if layout == ArcadeCar.DrivenWheels.FWD else car.rear_axle_load,
	}
	car.driven_wheels = ArcadeCar.DRIVEN_WHEELS
	return launch


## Resets the car and accelerates it in a straight line to `speed`, then lifts.
func _reach_speed(car: ArcadeCar, speed: float) -> void:
	car.reset_to_spawn()
	await _step(10)
	Input.action_press("accelerate")
	for frame in 600:
		if car.forward_speed >= speed:
			break
		await physics_frame
	Input.action_release("accelerate")


## Turns in to the left for 0.75 s from ~60 km/h, off the throttle, optionally
## hard on the brakes; returns how far the car turned [rad].
func _turn_in(car: ArcadeCar, braking: bool) -> float:
	await _get_up_to_speed(car)
	var yaw_before := car.global_rotation.y
	Input.action_press("steer_left")
	if braking:
		Input.action_press("brake")
	await _step(45)
	Input.action_release("steer_left")
	Input.action_release("brake")
	return angle_difference(yaw_before, car.global_rotation.y)


## Full throttle for 0.5 s; returns the average acceleration [m/s^2].
func _measure_pull(car: ArcadeCar, stats: Dictionary) -> float:
	var speed_start := car.forward_speed
	Input.action_press("accelerate")
	await _drive(car, 30, stats)
	Input.action_release("accelerate")
	return (car.forward_speed - speed_start) / 0.5


## Presses and releases an action over two physics frames.
func _tap(action: String) -> void:
	Input.action_press(action)
	await physics_frame
	Input.action_release(action)
	await physics_frame


func _new_stats() -> Dictionary:
	return {
		"finite": true, "max_step": 0.0, "peak_traction_use": 0.0,
		"min_rpm": INF, "max_rpm": 0.0, "min_load": 1.0, "max_load": 0.0,
	}


## Steps `frames` physics frames, folding per-frame sanity stats into `stats`.
func _drive(car: ArcadeCar, frames: int, stats: Dictionary) -> void:
	for frame in frames:
		var before := car.global_position
		await physics_frame
		stats.max_step = maxf(stats.max_step, car.global_position.distance_to(before))
		var values := [car.forward_speed, car.lateral_speed, car.yaw_rate, car.engine_rpm, car.front_load_fraction, car.rear_load_fraction]
		for value: float in values:
			if not is_finite(value):
				stats.finite = false
		if not car.global_position.is_finite():
			stats.finite = false
		stats.peak_traction_use = maxf(stats.peak_traction_use, car.rear_traction_use)
		stats.min_rpm = minf(stats.min_rpm, car.engine_rpm)
		stats.max_rpm = maxf(stats.max_rpm, car.engine_rpm)
		stats.min_load = minf(stats.min_load, minf(car.front_load_fraction, car.rear_load_fraction))
		stats.max_load = maxf(stats.max_load, maxf(car.front_load_fraction, car.rear_load_fraction))


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
	if _failures == 0:
		print("SMOKE TEST PASSED")
	else:
		printerr("SMOKE TEST FAILED: %d check(s) failed" % _failures)
	quit(1 if _failures > 0 else 0)
