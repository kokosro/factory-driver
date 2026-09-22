extends SceneTree
## Headless thermal test. Run via tests/run_tests.sh, or:
##
##   godot --headless --path . --import
##   godot --headless --fixed-fps 60 --path . --script res://tests/thermal_test.gd
##
## Loads the main scene and puts the car's engine and coolant (ArcadeCar,
## "Thermal") through what a temperature does. First the gate: the car comes
## out of _ready at the operating temperature, the fan off, where the richness
## is exactly 1, the fade exactly 1 and the idle target exactly IDLE_RPM - the
## combustion torque and the idle burn are the pre-thermal numbers to the bit,
## and the warm idle stands where it always stood. Then the cold engine: a
## cold start burns measurably more fuel than a warm one for the same work
## (the same flat-out ticks, the same speed at the end, more litres gone), and
## its idle hunts within the documented band where the warm idle does not.
## Then the warm-up, on the model alone at the cruise the car's own numbers
## give (72 km/h in 5th: the drag, the rolling resistance and the engine's
## friction): the curve rises tick by tick and never falls, is over the warm
## line and at the thermostat in minutes (the calibration, stated in the
## output), and settles under the operating temperature where the thermostat
## holds it; and in the scene, a cold car driven flat out warms by exactly the
## heat its burn put in. Then the thermostat: shut under its temperature, the
## cooling switches on there and the climb slows. Then the overheat: over the
## fade line the torque is measurably less at the same rpm and throttle, the
## fade never goes under its floor, the coolant never over its ceiling, and an
## engine at the ceiling idles on - nothing dies. Then the fan: at a standstill
## it is the only cooling there is, it adds nothing at speed, and it switches
## on and off where documented. Then the HUD's bar: it follows the temperature,
## blue cold, grey warm, red hot, brighter red hotter, its two lines the car's
## own. Last, nothing of it is ever NaN, after the limiter, a stall and resets.
## Exits 0 on success, 1 on any failed check.

const MAIN_SCENE := "res://scenes/main.tscn"

## Physics frames to let the car settle on the ground at the start.
const SETTLE_FRAMES := 60

## Ticks of flat-out driving from rest the cold and the warm burn are compared
## over (5 s): the throttle saturated the whole way, so the idle controller
## and its cold hunt have no say in the work.
const BURN_FRAMES := 300

## How much of COOLANT_RICH_FACTOR's extra the cold run has to show at least:
## the engine warms a little over the 5 s, so it shows a hair less than the
## whole factor.
const RICH_SHARE_SEEN := 0.8

## The cruise the warm-up is calibrated at [m/s]: 20 m/s, 72 km/h, in 5th.
const CRUISE_SPEED := 20.0
const CRUISE_GEAR := 5

## The warm-up has to be over the warm line and at the thermostat within this
## many minutes of that cruise, and not before this many (a 986 warms up in 5
## to 10 min of mixed driving).
const WARM_UP_MIN_MINUTES := 4.0
const WARM_UP_MAX_MINUTES := 10.0

## The most ticks the warm-up is watched for (30 min).
const WARM_UP_WATCH_FRAMES := 108000

## Ticks the cold car is driven flat out in the scene for the warming check
## (5 s), and ticks the cold idle is left to settle (2 s) and then sampled
## (5 s: three of the 0.6 Hz hunt's cycles).
const WARMING_FRAMES := 300
const IDLE_SETTLE_FRAMES := 120
const IDLE_SAMPLE_FRAMES := 300

## The least the cold idle has to swing over the samples [rpm], and the most
## the rpm may be from IDLE_RPM [rpm] on top of IDLE_WOBBLE_RPM (the
## controller overshoots the moving target by a few rpm).
const IDLE_HUNT_MIN_SWING := 40.0
const IDLE_HUNT_SLACK := 15.0

## The most a warm idle may swing over the same samples [rpm]: it stands.
const WARM_IDLE_MAX_SWING := 1.0

## How hot the overheat checks put the coolant [C]: ten degrees over the fade
## line, a fifth of the torque gone.
const HOT_C := 120.0

## Ticks an engine at the ceiling idles for the no-death check (2 s), and
## ticks of flat-out driving the hot car and the warm one are compared over
## (2 s).
const CEILING_IDLE_FRAMES := 120
const FADE_DRIVE_FRAMES := 120

## Ticks a dry tank is given to run the engine down and stop it (4 s, the
## battery test's), and ticks the limiter is held in neutral (2 s).
const RUN_DOWN_FRAMES := 240
const LIMITER_FRAMES := 120

var _failures := 0

## The coolant as _ready left it, before a tick could touch it.
var _temp_at_start := -1.0
var _fan_at_start := true


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var packed: PackedScene = load(MAIN_SCENE)
	if not _check(packed != null, "main scene loads"):
		_finish()
		return
	var main := packed.instantiate()
	root.add_child(main)
	var car_at_ready := main.get_node_or_null("Car") as ArcadeCar
	if car_at_ready:
		_temp_at_start = car_at_ready.coolant_temp
		_fan_at_start = car_at_ready.coolant_fan_on
	await _step(SETTLE_FRAMES)

	var car := main.get_node_or_null("Car") as ArcadeCar
	var hud := main.get_node_or_null("HUD") as HUD
	var bar := main.get_node_or_null("HUD/CoolantBarBack/CoolantBar") as ColorRect
	if not _check(car != null and hud != null and bar != null, "car, HUD and the HUD's coolant bar exist"):
		_finish()
		return

	_check_model_numbers()
	_check_suite_gate(car)
	await _check_certified_untouched(car)
	await _check_cold_burn(car)
	_check_warm_up(car)
	await _check_warming_in_the_scene(car)
	_check_thermostat(car)
	await _check_overheat(car)
	await _check_fan(car)
	await _check_cold_idle(car)
	await _check_hud_bar(car, hud, bar)
	await _check_no_nan(car)

	car.reset_to_spawn()
	await _step(5)
	_finish()


## The model's own numbers: the scale (0 the air, 1 the operating
## temperature), and the lines in their order - warm under the thermostat
## (a warm engine, held over the thermostat, never runs rich again), the
## thermostat under operating, the fan's off line under its on line, both
## under the fade line, the fade line under the ceiling.
func _check_model_numbers() -> void:
	var scale_ok := ArcadeCar.coolant_c_of(0.0) == ArcadeCar.COOLANT_AMBIENT_C and ArcadeCar.coolant_c_of(1.0) == ArcadeCar.COOLANT_OPERATING_C \
		and ArcadeCar.coolant_temp_of_c(ArcadeCar.COOLANT_AMBIENT_C) == 0.0 and ArcadeCar.coolant_temp_of_c(ArcadeCar.COOLANT_OPERATING_C) == 1.0 \
		and is_equal_approx(ArcadeCar.COOLANT_MAX_TEMP, ArcadeCar.coolant_temp_of_c(ArcadeCar.COOLANT_MAX_C)) and ArcadeCar.COOLANT_SPAN_K > 0.0
	_check(scale_ok, "model: coolant_temp runs from 0 at the air's %.0f C to 1 at the operating %.0f C (%.0f K to the unit) and stops at %.3f, the %.0f C ceiling" % [ArcadeCar.COOLANT_AMBIENT_C, ArcadeCar.COOLANT_OPERATING_C, ArcadeCar.COOLANT_SPAN_K, ArcadeCar.COOLANT_MAX_TEMP, ArcadeCar.COOLANT_MAX_C])
	var order_ok := ArcadeCar.COOLANT_AMBIENT_C < ArcadeCar.COOLANT_WARM_C and ArcadeCar.COOLANT_WARM_C < ArcadeCar.THERMOSTAT_C \
		and ArcadeCar.THERMOSTAT_C < ArcadeCar.COOLANT_OPERATING_C and ArcadeCar.COOLANT_OPERATING_C <= ArcadeCar.COOLANT_FAN_OFF_C \
		and ArcadeCar.COOLANT_FAN_OFF_C < ArcadeCar.COOLANT_FAN_ON_C and ArcadeCar.COOLANT_FAN_ON_C < ArcadeCar.OVERHEAT_FADE_START_C \
		and ArcadeCar.OVERHEAT_FADE_START_C < ArcadeCar.COOLANT_MAX_C \
		and ArcadeCar.COOLANT_RICH_FACTOR > 1.0 and ArcadeCar.IDLE_WOBBLE_RPM > 0.0 and ArcadeCar.OVERHEAT_FADE_RATE > 0.0 \
		and ArcadeCar.OVERHEAT_FADE_FLOOR > 0.0 and ArcadeCar.OVERHEAT_FADE_FLOOR < 1.0
	_check(order_ok, "model: the lines stand in order - warm %.0f C under the thermostat's %.0f, operating %.0f, the fan off under %.0f and on over %.0f, the fade from %.0f, the ceiling %.0f: a warm engine never runs rich again, a fading one is well over the fan" % [ArcadeCar.COOLANT_WARM_C, ArcadeCar.THERMOSTAT_C, ArcadeCar.COOLANT_OPERATING_C, ArcadeCar.COOLANT_FAN_OFF_C, ArcadeCar.COOLANT_FAN_ON_C, ArcadeCar.OVERHEAT_FADE_START_C, ArcadeCar.COOLANT_MAX_C])


## The suite starts warm: the car came out of _ready at exactly the operating
## temperature with the fan off, and there the richness is exactly 1, the fade
## exactly 1, the cold share exactly 0 and the idle target exactly IDLE_RPM.
func _check_suite_gate(car: ArcadeCar) -> void:
	_check(
		_temp_at_start == 1.0 and not _fan_at_start and car.fuel_richness() == 1.0 and car.overheat_fade() == 1.0
			and car.coolant_cold_share() == 0.0 and car.idle_target_rpm() == ArcadeCar.IDLE_RPM,
		"suite: the car came out of _ready at the operating temperature (coolant_temp %.3f, %.0f C, the fan off) - the richness exactly 1, the fade exactly 1, the idle target exactly %.0f rpm: the certified path" % [_temp_at_start, ArcadeCar.coolant_c_of(_temp_at_start), ArcadeCar.IDLE_RPM],
	)


## The certified path untouched: at the operating temperature the combustion
## torque is the pre-thermal sum to the bit (the curve plus the friction, times
## the throttle) at every anchor of the curve, the idle burn over a second is
## what the pre-thermal burn line gives, and the warm idle stands at IDLE_RPM.
func _check_certified_untouched(car: ArcadeCar) -> void:
	var tick := 1.0 / Engine.physics_ticks_per_second
	car.reset_to_spawn()
	await _step(SETTLE_FRAMES)
	var to_the_bit := 0
	for anchor: Vector2 in ArcadeCar.TORQUE_CURVE:
		var rpm := anchor.x
		var pre_thermal := (ArcadeCar.engine_torque(rpm) + ArcadeCar.ENGINE_FRICTION_TORQUE + ArcadeCar.ENGINE_FRICTION_TORQUE_PER_RPM * rpm) * 1.0
		if car._combustion_torque(rpm, 1.0, 0.0) == pre_thermal and car._curve_torque(rpm) == ArcadeCar.engine_torque(rpm):
			to_the_bit += 1
	var fuel_before := car.fuel_l
	var lowest_rpm := INF
	var highest_rpm := 0.0
	var heat_seen := 0.0
	for frame in IDLE_SETTLE_FRAMES:
		await physics_frame
		lowest_rpm = minf(lowest_rpm, car.engine_rpm)
		highest_rpm = maxf(highest_rpm, car.engine_rpm)
		heat_seen += car._combustion_heat_w
	var burnt_l := fuel_before - car.fuel_l
	# The pre-thermal burn line at the idle the engine stood at.
	var idle_omega := ArcadeCar.IDLE_RPM * TAU / 60.0
	var idle_combustion := car._combustion_torque(ArcadeCar.IDLE_RPM, 0.0, 0.0)
	var expected_l := idle_combustion * idle_omega / ArcadeCar.FUEL_BURN_EFFICIENCY / ArcadeCar.FUEL_LHV / ArcadeCar.FUEL_DENSITY * tick * IDLE_SETTLE_FRAMES
	_check(
		to_the_bit == ArcadeCar.TORQUE_CURVE.size() and car.coolant_temp >= 1.0 and burnt_l > 0.0 and absf(burnt_l / expected_l - 1.0) < 0.01
			and highest_rpm - lowest_rpm < WARM_IDLE_MAX_SWING and absf(highest_rpm - ArcadeCar.IDLE_RPM) < WARM_IDLE_MAX_SWING and heat_seen > 0.0,
		"certified: warm, the combustion torque is the pre-thermal sum to the bit at all %d anchors of the curve, the idle burn over %.0f s is the pre-thermal line's (%.4f mL, the line %.4f mL), and the idle stands at %.1f..%.1f rpm" % [to_the_bit, IDLE_SETTLE_FRAMES * tick, burnt_l * 1000.0, expected_l * 1000.0, lowest_rpm, highest_rpm],
	)


## A cold start burns more fuel than a warm one for the same work: the same
## flat-out ticks from rest, the same speed at the end to a hair (the torque
## has not changed, the tank is a few grams lighter), more litres gone - a
## share of COOLANT_RICH_FACTOR's extra, the engine warming a little as it
## goes. And the richness itself: the factor at the air's temperature, 1 at
## the warm line and above, between the two between.
func _check_cold_burn(car: ArcadeCar) -> void:
	var tick := 1.0 / Engine.physics_ticks_per_second
	var warm := await _flat_out(car, 1.0)
	var cold := await _flat_out(car, 0.0)
	var ratio: float = cold.burnt_l / warm.burnt_l
	var same_work: bool = absf(cold.speed / warm.speed - 1.0) < 0.005
	car.coolant_temp = 0.0
	var at_air := car.fuel_richness()
	car.coolant_temp = ArcadeCar.coolant_temp_of_c(ArcadeCar.COOLANT_WARM_C)
	var at_warm := car.fuel_richness()
	car.coolant_temp = ArcadeCar.coolant_temp_of_c((ArcadeCar.COOLANT_WARM_C + ArcadeCar.COOLANT_AMBIENT_C) / 2.0)
	var halfway := car.fuel_richness()
	car.reset_to_spawn()
	await _step(5)
	_check(
		same_work and ratio > 1.0 + (ArcadeCar.COOLANT_RICH_FACTOR - 1.0) * RICH_SHARE_SEEN and ratio <= ArcadeCar.COOLANT_RICH_FACTOR + 1.0e-9
			and at_air == ArcadeCar.COOLANT_RICH_FACTOR and at_warm == 1.0 and is_equal_approx(halfway, 1.0 + (ArcadeCar.COOLANT_RICH_FACTOR - 1.0) / 2.0),
		"cold burn: %.0f s flat out from rest burns %.1f mL warm and %.1f mL from the air's temperature - %.3f times as much for the same work (%.2f and %.2f m/s at the end); the richness is %.2f cold, 1 at %.0f C, %.3f halfway" % [BURN_FRAMES * tick, warm.burnt_l * 1000.0, cold.burnt_l * 1000.0, ratio, warm.speed, cold.speed, at_air, ArcadeCar.COOLANT_WARM_C, halfway],
	)


## The warm-up, on the model alone (_advance_coolant, tick by tick at the
## suite's tick) at the cruise the car's own numbers give: the combustion
## power of a steady CRUISE_SPEED in CRUISE_GEAR - the air drag, the rolling
## resistance through the driveline and the engine's friction at that rpm -
## and COOLANT_HEAT_SHARE of the fuel's heat that makes into the coolant. The
## curve never falls, crosses the warm line and the thermostat in minutes,
## and settles between the thermostat and operating, where the thermostat
## holds a cruise.
func _check_warm_up(car: ArcadeCar) -> void:
	var tick := 1.0 / Engine.physics_ticks_per_second
	var cruise := _cruise_combustion_w(car)
	var heat_w: float = cruise.power_w / ArcadeCar.FUEL_BURN_EFFICIENCY * ArcadeCar.COOLANT_HEAT_SHARE
	var warm_line := ArcadeCar.coolant_temp_of_c(ArcadeCar.COOLANT_WARM_C)
	var thermostat := ArcadeCar.coolant_temp_of_c(ArcadeCar.THERMOSTAT_C)
	car.reset_to_spawn()
	car.coolant_temp = 0.0
	car.coolant_fan_on = false
	var monotonic := true
	var warm_tick := -1
	var thermostat_tick := -1
	var last := car.coolant_temp
	var a_minute_ago := 0.0
	var ticks_in_a_minute := int(60.0 / tick)
	for frame in WARM_UP_WATCH_FRAMES:
		car._advance_coolant(heat_w, CRUISE_SPEED, tick)
		if car.coolant_temp < last:
			monotonic = false
		last = car.coolant_temp
		if warm_tick < 0 and car.coolant_temp >= warm_line:
			warm_tick = frame + 1
		if thermostat_tick < 0 and car.coolant_temp >= thermostat:
			thermostat_tick = frame + 1
		if frame == WARM_UP_WATCH_FRAMES - ticks_in_a_minute - 1:
			a_minute_ago = car.coolant_temp
	var settled := car.coolant_temp
	var settled_c := ArcadeCar.coolant_c_of(settled)
	var warm_minutes := warm_tick * tick / 60.0
	var thermostat_minutes := thermostat_tick * tick / 60.0
	car.reset_to_spawn()
	_check(
		monotonic and warm_tick > 0 and thermostat_tick > warm_tick
			and thermostat_minutes >= WARM_UP_MIN_MINUTES and thermostat_minutes <= WARM_UP_MAX_MINUTES
			and settled > thermostat and settled < 1.0 and absf(settled - a_minute_ago) < 1.0e-4 and car.coolant_temp == 1.0,
		"warm-up: at a steady %.0f m/s in %dth (%.1f kW of combustion: %.0f N of drag and rolling resistance at %.0f rpm, %.1f kW of it into the coolant) the coolant climbs from %.0f C without a dip, is over the %.0f C warm line after %.1f min and at the %.0f C thermostat after %.1f min (calibrated to %.0f..%.0f), and settles at %.1f C - under operating, where the thermostat holds a cruise; a reset is the warm car again" % [CRUISE_SPEED, CRUISE_GEAR, cruise.power_w / 1000.0, cruise.road_force_n, cruise.rpm, heat_w / 1000.0, ArcadeCar.COOLANT_AMBIENT_C, ArcadeCar.COOLANT_WARM_C, warm_minutes, ArcadeCar.THERMOSTAT_C, thermostat_minutes, WARM_UP_MIN_MINUTES, WARM_UP_MAX_MINUTES, settled_c],
	)


## In the scene: a cold car driven flat out warms tick by tick, never cools
## (the thermostat is shut), and the rise is exactly the heat its burn put in
## over the lump's capacity - the model is wired to the engine.
func _check_warming_in_the_scene(car: ArcadeCar) -> void:
	var tick := 1.0 / Engine.physics_ticks_per_second
	car.reset_to_spawn()
	await _step(SETTLE_FRAMES)
	car.coolant_temp = 0.0
	car.set_driver_input(1.0, 0.0, 0.0)
	var never_cools := true
	var heat_j := 0.0
	var last := car.coolant_temp
	var fan_stayed_off := true
	for frame in WARMING_FRAMES:
		await physics_frame
		if car.coolant_temp < last:
			never_cools = false
		last = car.coolant_temp
		heat_j += car._combustion_heat_w * tick
		fan_stayed_off = fan_stayed_off and not car.coolant_fan_on
	car.clear_driver_input()
	var rise := car.coolant_temp
	var expected := heat_j / (ArcadeCar.COOLANT_HEAT_CAPACITY * ArcadeCar.COOLANT_SPAN_K)
	_check(
		never_cools and rise > 0.0 and is_equal_approx(rise, expected) and fan_stayed_off and car.speed_kmh > 50.0,
		"scene: driven flat out from the air's temperature for %.0f s the coolant warms by %.1f K without a dip (%.0f kJ into the lump, %.1f K by the capacity), the thermostat shut, the fan off, %.0f km/h at the end" % [WARMING_FRAMES * tick, rise * ArcadeCar.COOLANT_SPAN_K, heat_j / 1000.0, expected * ArcadeCar.COOLANT_SPAN_K, car.speed_kmh],
	)
	car.reset_to_spawn()
	await _step(5)


## The thermostat: shut up to its temperature (no cooling however fast the car
## goes), half open halfway to operating, fully open there; and the climb
## slows the tick it opens - the same heat in, less of it kept.
func _check_thermostat(car: ArcadeCar) -> void:
	var tick := 1.0 / Engine.physics_ticks_per_second
	var start := ArcadeCar.coolant_temp_of_c(ArcadeCar.THERMOSTAT_C)
	var halfway := (start + 1.0) / 2.0
	var shut := ArcadeCar.thermostat_open(0.0) == 0.0 and ArcadeCar.thermostat_open(start) == 0.0 and ArcadeCar.coolant_cooling_w(start, 40.0, true) == 0.0
	var opening := is_equal_approx(ArcadeCar.thermostat_open(halfway), 0.5) and ArcadeCar.thermostat_open(1.0) == 1.0 and ArcadeCar.thermostat_open(ArcadeCar.COOLANT_MAX_TEMP) == 1.0
	var cooling_on := ArcadeCar.coolant_cooling_w(start + 0.01, CRUISE_SPEED, false) > 0.0 and ArcadeCar.coolant_cooling_w(1.0, CRUISE_SPEED, false) > ArcadeCar.coolant_cooling_w(halfway, CRUISE_SPEED, false)
	var heat_w := 10000.0
	car.coolant_temp = start - 0.001
	car.coolant_fan_on = false
	car._advance_coolant(heat_w, CRUISE_SPEED, tick)
	var rise_under := car.coolant_temp - (start - 0.001)
	car.coolant_temp = start + 0.02
	car._advance_coolant(heat_w, CRUISE_SPEED, tick)
	var rise_over := car.coolant_temp - (start + 0.02)
	var full_open_w := ArcadeCar.coolant_cooling_w(1.0, 30.0, false)
	car.coolant_temp = 1.0
	_check(
		shut and opening and cooling_on and rise_under > 0.0 and rise_over < rise_under and rise_over > 0.0
			and is_equal_approx(rise_under, heat_w * tick / (ArcadeCar.COOLANT_HEAT_CAPACITY * ArcadeCar.COOLANT_SPAN_K)),
		"thermostat: shut to %.0f C (no cooling at 40 m/s with the fan on), half open at %.0f C, open at %.0f C; on %.0f kW at %.0f m/s a tick warms the coolant %.4f K just under it and %.4f K just over - the radiator is on from there (%.0f kW at 30 m/s, %.0f K over the air, open)" % [ArcadeCar.THERMOSTAT_C, ArcadeCar.coolant_c_of(halfway), ArcadeCar.COOLANT_OPERATING_C, heat_w / 1000.0, CRUISE_SPEED, rise_under * ArcadeCar.COOLANT_SPAN_K, rise_over * ArcadeCar.COOLANT_SPAN_K, full_open_w / 1000.0, ArcadeCar.COOLANT_SPAN_K],
	)


## The overheat: over the fade line the combustion torque is measurably less
## at the same rpm and throttle - the curve times the fade, the friction as it
## was - never under the floor's share, the coolant never over the ceiling,
## and an engine at the ceiling idles on and drives on, slower: nothing dies.
func _check_overheat(car: ArcadeCar) -> void:
	var tick := 1.0 / Engine.physics_ticks_per_second
	var rpm := ArcadeCar.TORQUE_CURVE[3].x
	var friction := ArcadeCar.ENGINE_FRICTION_TORQUE + ArcadeCar.ENGINE_FRICTION_TORQUE_PER_RPM * rpm
	car.reset_to_spawn()
	await _step(5)
	var warm_torque := car._combustion_torque(rpm, 1.0, 0.0)
	car.coolant_temp = ArcadeCar.coolant_temp_of_c(HOT_C)
	var hot_fade := car.overheat_fade()
	var hot_torque := car._combustion_torque(rpm, 1.0, 0.0)
	var fade_expected := 1.0 - ArcadeCar.OVERHEAT_FADE_RATE * (HOT_C - ArcadeCar.OVERHEAT_FADE_START_C)
	var hot_ok := hot_torque < warm_torque and is_equal_approx(hot_fade, fade_expected) and is_equal_approx(hot_torque, ArcadeCar.engine_torque(rpm) * hot_fade + friction)
	car.coolant_temp = ArcadeCar.coolant_temp_of_c(ArcadeCar.OVERHEAT_FADE_START_C)
	var at_the_line := car.overheat_fade() == 1.0 and car._combustion_torque(rpm, 1.0, 0.0) == warm_torque
	car.coolant_temp = 1000.0
	var ceiling := car.coolant_temp == ArcadeCar.COOLANT_MAX_TEMP
	var floor_fade := car.overheat_fade()
	var floored := floor_fade >= ArcadeCar.OVERHEAT_FADE_FLOOR and floor_fade < 1.0 and car._combustion_torque(rpm, 1.0, 0.0) >= ArcadeCar.engine_torque(rpm) * ArcadeCar.OVERHEAT_FADE_FLOOR + friction
	# Idling at the ceiling: the engine runs on, the coolant stays at the
	# ceiling at most, and the fan is on.
	var runs_on := true
	var over_the_ceiling := false
	for frame in CEILING_IDLE_FRAMES:
		await physics_frame
		runs_on = runs_on and car.engine_running and car.engine_rpm > ArcadeCar.STALL_RPM
		over_the_ceiling = over_the_ceiling or car.coolant_temp > ArcadeCar.COOLANT_MAX_TEMP
	var fan_on := car.coolant_fan_on
	# And driven: the hot car is slower off the line than the warm one.
	var warm_drive := await _flat_out(car, 1.0, FADE_DRIVE_FRAMES)
	var hot_drive := await _flat_out(car, ArcadeCar.coolant_temp_of_c(HOT_C), FADE_DRIVE_FRAMES)
	car.reset_to_spawn()
	await _step(5)
	_check(
		hot_ok and at_the_line and ceiling and floored and runs_on and not over_the_ceiling and fan_on and hot_drive.speed < warm_drive.speed and hot_drive.speed > 0.5 * warm_drive.speed,
		"overheat: at %.0f C the fade is %.2f and the full-throttle torque at %.0f rpm %.1f Nm to the warm %.1f (the curve faded, the friction as it was), exactly the warm number at the %.0f C line; the coolant stops at the %.0f C ceiling where the fade is %.2f (floor %.2f), the engine idles on there for %.0f s with the fan running, and off the line the hot car makes %.2f m/s in %.0f s to the warm car's %.2f - slower, never dead" % [HOT_C, hot_fade, rpm, hot_torque, warm_torque, ArcadeCar.OVERHEAT_FADE_START_C, ArcadeCar.COOLANT_MAX_C, floor_fade, ArcadeCar.OVERHEAT_FADE_FLOOR, CEILING_IDLE_FRAMES * tick, hot_drive.speed, FADE_DRIVE_FRAMES * tick, warm_drive.speed],
	)


## The fan: at a standstill with the thermostat open it is the only cooling
## there is (none with it off, some with it on), it adds nothing at speed
## (the airflow is the larger of the two), and it switches on over
## COOLANT_FAN_ON_C and off again under COOLANT_FAN_OFF_C, holding between.
func _check_fan(car: ArcadeCar) -> void:
	var hot := ArcadeCar.coolant_temp_of_c(ArcadeCar.COOLANT_FAN_ON_C)
	var still_off := ArcadeCar.coolant_cooling_w(hot, 0.0, false)
	var still_on := ArcadeCar.coolant_cooling_w(hot, 0.0, true)
	var at_speed_off := ArcadeCar.coolant_cooling_w(hot, CRUISE_SPEED, false)
	var at_speed_on := ArcadeCar.coolant_cooling_w(hot, CRUISE_SPEED, true)
	var fan_expected := ArcadeCar.COOLANT_RADIATOR_COOLING * ArcadeCar.COOLANT_FAN_AIRFLOW * ArcadeCar.COOLANT_FAN_AIRFLOW * (ArcadeCar.COOLANT_FAN_ON_C - ArcadeCar.COOLANT_AMBIENT_C)
	car.reset_to_spawn()
	await _step(SETTLE_FRAMES)
	# Between the two lines from below: off, and the idle's heat warms it.
	car.coolant_temp = ArcadeCar.coolant_temp_of_c((ArcadeCar.COOLANT_FAN_OFF_C + ArcadeCar.COOLANT_FAN_ON_C) / 2.0)
	var between := car.coolant_temp
	await _step(60)
	var stays_off := not car.coolant_fan_on and car.coolant_temp > between
	# Over the on line: on the next tick, and the coolant falls at a standstill.
	car.coolant_temp = hot + 0.01
	await _step(1)
	var came_on := car.coolant_fan_on
	var before_fall := car.coolant_temp
	await _step(60)
	var falls := car.coolant_fan_on and car.coolant_temp < before_fall
	# Back between the lines from above: still on; under the off line: off.
	car.coolant_temp = between
	await _step(1)
	var holds_on := car.coolant_fan_on
	car.coolant_temp = ArcadeCar.coolant_temp_of_c(ArcadeCar.COOLANT_FAN_OFF_C) - 0.01
	await _step(1)
	var went_off := not car.coolant_fan_on
	car.reset_to_spawn()
	await _step(5)
	_check(
		still_off == 0.0 and still_on > 0.0 and is_equal_approx(still_on, fan_expected) and at_speed_on == at_speed_off and at_speed_off > still_on
			and stays_off and came_on and falls and holds_on and went_off and car.speed_kmh < 1.0,
		"fan: standing at %.0f C the radiator sheds nothing with the fan off and %.1f kW with it on (%.0f m/s of airflow), at %.0f m/s the fan adds nothing (%.1f kW either way); between %.0f and %.0f C it stays off and the idle warms the coolant, over %.0f C it comes on the next tick and the coolant falls at a standstill, it holds on back between the lines and goes off under %.0f C" % [ArcadeCar.COOLANT_FAN_ON_C, still_on / 1000.0, ArcadeCar.COOLANT_FAN_AIRFLOW, CRUISE_SPEED, at_speed_off / 1000.0, ArcadeCar.COOLANT_FAN_OFF_C, ArcadeCar.COOLANT_FAN_ON_C, ArcadeCar.COOLANT_FAN_ON_C, ArcadeCar.COOLANT_FAN_OFF_C],
	)


## The cold idle hunts: the target wobbles within IDLE_WOBBLE_RPM of IDLE_RPM
## and the engine follows it, swinging measurably over three cycles and never
## further than the band and the controller's slack; the warm idle stands at
## IDLE_RPM, its target exactly IDLE_RPM on every tick.
func _check_cold_idle(car: ArcadeCar) -> void:
	var tick := 1.0 / Engine.physics_ticks_per_second
	car.reset_to_spawn()
	await _step(SETTLE_FRAMES)
	var warm_low := INF
	var warm_high := 0.0
	var warm_target_exact := true
	for frame in IDLE_SAMPLE_FRAMES:
		await physics_frame
		warm_low = minf(warm_low, car.engine_rpm)
		warm_high = maxf(warm_high, car.engine_rpm)
		warm_target_exact = warm_target_exact and car.idle_target_rpm() == ArcadeCar.IDLE_RPM
	car.coolant_temp = 0.0
	await _step(IDLE_SETTLE_FRAMES)
	var cold_low := INF
	var cold_high := 0.0
	var target_low := INF
	var target_high := 0.0
	var runs := true
	for frame in IDLE_SAMPLE_FRAMES:
		await physics_frame
		cold_low = minf(cold_low, car.engine_rpm)
		cold_high = maxf(cold_high, car.engine_rpm)
		target_low = minf(target_low, car.idle_target_rpm())
		target_high = maxf(target_high, car.idle_target_rpm())
		runs = runs and car.engine_running
	var band := ArcadeCar.IDLE_WOBBLE_RPM
	var in_band := cold_low >= ArcadeCar.IDLE_RPM - band - IDLE_HUNT_SLACK and cold_high <= ArcadeCar.IDLE_RPM + band + IDLE_HUNT_SLACK \
		and target_low >= ArcadeCar.IDLE_RPM - band and target_high <= ArcadeCar.IDLE_RPM + band and target_low < ArcadeCar.IDLE_RPM and target_high > ArcadeCar.IDLE_RPM
	car.reset_to_spawn()
	await _step(5)
	_check(
		warm_target_exact and warm_high - warm_low < WARM_IDLE_MAX_SWING and runs and in_band and cold_high - cold_low >= IDLE_HUNT_MIN_SWING,
		"cold idle: warm, the idle stands at %.1f..%.1f rpm over %.0f s, its target exactly %.0f every tick; from the air's temperature the target hunts %.0f..%.0f rpm (the documented %.0f either side, a %.1f Hz wobble) and the engine follows it, %.0f..%.0f rpm, running throughout" % [warm_low, warm_high, IDLE_SAMPLE_FRAMES * tick, ArcadeCar.IDLE_RPM, target_low, target_high, band, ArcadeCar.IDLE_WOBBLE_HZ, cold_low, cold_high],
	)


## The HUD's coolant bar follows the temperature, from the left, in the fuel
## bar's idiom: blue cold, grey warm, red over the fade line, brighter red ten
## degrees further, hidden at 0 and for NaN, clamped at the bar's end; its cold
## and hot lines are the car's own warm line and fade line; and the fuel and
## battery bars are left alone.
func _check_hud_bar(car: ArcadeCar, hud: HUD, bar: ColorRect) -> void:
	var fuel_bar := hud.get_node("FuelBarBack/FuelBar") as ColorRect
	var battery_bar := hud.get_node("BatteryBarBack/BatteryBar") as ColorRect
	car.reset_to_spawn()
	await _step(2)
	var warm_ok := bar.visible and is_equal_approx(bar.scale.x, car.coolant_temp / HUD.COOLANT_BAR_FULL) and bar.color == HUD.COOLANT_COLOR
	var levels := {
		"cold": ArcadeCar.coolant_temp_of_c(40.0),
		"hot": ArcadeCar.coolant_temp_of_c(ArcadeCar.OVERHEAT_FADE_START_C + 2.0),
		"very hot": ArcadeCar.coolant_temp_of_c(HOT_C + 1.0),
	}
	var colours := {"cold": HUD.COOLANT_COLD_COLOR, "hot": HUD.COOLANT_HOT_COLOR, "very hot": HUD.COOLANT_VERY_HOT_COLOR}
	var followed := 0
	for level: String in levels:
		car.coolant_temp = levels[level]
		await _step(2)
		if bar.visible and is_equal_approx(bar.scale.x, car.coolant_temp / HUD.COOLANT_BAR_FULL) and bar.color == colours[level] \
				and fuel_bar.color == HUD.FUEL_COLOR and is_equal_approx(fuel_bar.scale.x, car.fuel_fraction()) and battery_bar.color == HUD.BATTERY_COLOR:
			followed += 1
	hud.set_coolant_bar(0.0)
	var hidden := not bar.visible
	hud.set_coolant_bar(NAN)
	hidden = hidden and not bar.visible
	hud.set_coolant_bar(9.0)
	var clamped := bar.visible and bar.scale.x == 1.0
	var lines_ok := is_equal_approx(HUD.COOLANT_COLD_FRACTION, ArcadeCar.coolant_temp_of_c(ArcadeCar.COOLANT_WARM_C)) \
		and is_equal_approx(HUD.COOLANT_HOT_FRACTION, ArcadeCar.coolant_temp_of_c(ArcadeCar.OVERHEAT_FADE_START_C)) \
		and HUD.COOLANT_HOT_FRACTION < HUD.COOLANT_VERY_HOT_FRACTION and HUD.COOLANT_VERY_HOT_FRACTION < HUD.COOLANT_BAR_FULL \
		and HUD.COOLANT_BAR_FULL <= ArcadeCar.COOLANT_MAX_TEMP
	car.reset_to_spawn()
	await _step(2)
	_check(
		warm_ok and followed == levels.size() and hidden and clamped and lines_ok and bar.visible and bar.color == HUD.COOLANT_COLOR,
		"HUD: the coolant bar follows the temperature (%d of %d levels to the bit: blue at 40 C, red at %.0f, brighter red at %.0f), grey warm, hidden at 0 and for NaN, clamped at its end (%.1f C), the fuel and battery bars untouched; its cold line is the car's %.0f C warm line and its hot line the car's %.0f C fade line; and it is the car's again after a reset" % [followed, levels.size(), ArcadeCar.OVERHEAT_FADE_START_C + 2.0, HOT_C + 1.0, ArcadeCar.coolant_c_of(HUD.COOLANT_BAR_FULL), ArcadeCar.COOLANT_WARM_C, ArcadeCar.OVERHEAT_FADE_START_C],
	)


## Nothing of it is ever NaN: a NaN temperature is operating, inf the ceiling
## and -inf the air, NaN heat into a tick leaves the coolant at operating; and
## after the limiter, a stall with the coolant cold, and resets, the whole
## state is finite.
func _check_no_nan(car: ArcadeCar) -> void:
	var tick := 1.0 / Engine.physics_ticks_per_second
	car.coolant_temp = NAN
	var nan_temp := car.coolant_temp == 1.0
	car.coolant_temp = INF
	var inf_temp := car.coolant_temp == ArcadeCar.COOLANT_MAX_TEMP
	car.coolant_temp = -INF
	var neg_inf_temp := car.coolant_temp == 0.0
	car._advance_coolant(NAN, 0.0, tick)
	var nan_heat := car.coolant_temp == 1.0
	# The limiter in neutral, flat out.
	car.reset_to_spawn()
	await _step(5)
	car.automatic = false
	car.shift_down()
	car.set_driver_input(1.0, 0.0, 0.0)
	var limited := false
	for frame in LIMITER_FRAMES:
		await physics_frame
		# The revs bounce between the cut and the resume line: the cut is seen
		# on some tick of the two seconds, not on any one of them.
		limited = limited or car.limiter_cutting
	car.clear_driver_input()
	# A stall on a dry tank, the coolant cold: no burn, no heat, no hunt.
	car.reset_to_spawn()
	await _step(5)
	car.coolant_temp = 0.0
	car.fuel_l = 0.0
	await _step(RUN_DOWN_FRAMES)
	var stalled := not car.engine_running and car.engine_rpm == 0.0 and car._combustion_heat_w == 0.0
	car.reset_to_spawn()
	await _step(2)
	var finite := is_finite(car.coolant_temp) and is_finite(car.coolant_c()) and is_finite(car.fuel_richness()) and is_finite(car.overheat_fade()) \
		and is_finite(car.idle_target_rpm()) and is_finite(car.coolant_cold_share()) and is_finite(car._combustion_heat_w) and is_finite(car._idle_wobble_phase) \
		and is_finite(ArcadeCar.coolant_cooling_w(car.coolant_temp, car.forward_speed, car.coolant_fan_on)) and is_finite(car.fuel_l) and is_finite(car.engine_rpm)
	_check(
		# Two ticks of idle at a standstill, no airflow: a hair over operating.
		nan_temp and inf_temp and neg_inf_temp and nan_heat and limited and stalled and finite and car.coolant_temp >= 1.0 and car.coolant_temp < 1.001 and car.engine_running,
		"no NaN: a NaN temperature is operating, inf the ceiling, -inf the air, NaN heat leaves it at operating; after %.0f s on the limiter, a dry-tank stall from cold and resets the whole state is finite and the car is warm and running (coolant %.3f, %.0f rpm)" % [LIMITER_FRAMES * tick, car.coolant_temp, car.engine_rpm],
	)


## The combustion power of a steady CRUISE_SPEED in CRUISE_GEAR from the car's
## own numbers [W]: the air drag and the rolling resistance (what the model
## puts on the car, see ArcadeCar._physics_process) back through the driveline
## to the crankshaft, plus the engine's own friction at that rpm - the
## combustion torque times the engine speed. { power_w, rpm, road_force_n }.
func _cruise_combustion_w(car: ArcadeCar) -> Dictionary:
	var rpm := CRUISE_SPEED / car.speed_at_rpm(CRUISE_GEAR, 1.0)
	var omega := rpm * TAU / 60.0
	var air_drag := 0.5 * ArcadeCar.AIR_DENSITY * ArcadeCar.DRAG_COEFF * ArcadeCar.FRONTAL_AREA * CRUISE_SPEED * CRUISE_SPEED
	var rolling := ArcadeCar.COAST_DECEL * car.total_mass()
	var road_force := air_drag + rolling
	var ratio: float = ArcadeCar.GEAR_RATIOS[CRUISE_GEAR] * ArcadeCar.FINAL_DRIVE
	var crank_torque := road_force * ArcadeCar.WHEEL_RADIUS / ratio / ArcadeCar.DRIVETRAIN_EFFICIENCY
	var friction := ArcadeCar.ENGINE_FRICTION_TORQUE + ArcadeCar.ENGINE_FRICTION_TORQUE_PER_RPM * rpm
	return {"power_w": (crank_torque + friction) * omega, "rpm": rpm, "road_force_n": road_force}


## A reset, the coolant set to `temp`, and `frames` ticks flat out from rest in
## the automatic: { burnt_l: the litres gone, speed: the road speed at the end
## [m/s] }.
func _flat_out(car: ArcadeCar, temp: float, frames := BURN_FRAMES) -> Dictionary:
	car.reset_to_spawn()
	await _step(SETTLE_FRAMES)
	car.coolant_temp = temp
	var fuel_before := car.fuel_l
	car.set_driver_input(1.0, 0.0, 0.0)
	await _step(frames)
	car.clear_driver_input()
	var seen := {"burnt_l": fuel_before - car.fuel_l, "speed": car.forward_speed}
	car.reset_to_spawn()
	await _step(5)
	return seen


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
		print("THERMAL TEST PASSED")
	else:
		printerr("THERMAL TEST FAILED: %d check(s) failed" % _failures)
	quit(1 if _failures > 0 else 0)
