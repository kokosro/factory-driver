extends SceneTree
## Headless battery test. Run via tests/run_tests.sh, or:
##
##   godot --headless --path . --import
##   godot --headless --fixed-fps 60 --path . --script res://tests/battery_test.gd
##
## Loads the main scene and puts the car's electrical system (ArcadeCar,
## "Electrical") through what a battery does: the starter draws on it (a crank
## takes measurably more off it than the key-on drain over the same ticks), the
## alternator puts it back while the engine runs (faster at speed than at idle,
## the curve's own numbers), a weak battery cranks measurably slower and
## catches later (the crank rpm and the catch time both, from the starter's
## torque line alone), one under the catch line turns the engine and never
## starts it, an empty one turns nothing, a worn one full is slower than a new
## one; a deep discharge ages the capacity (once per discharge, and on for
## every second left flat), the capacity read follows the wear, a worn battery
## fills to less, and the wear is bounded. Then the HUD's bar: it follows the
## charge tick by tick, amber then red as it runs low, and sags tick by tick
## through a crank. Then the store: the suite reads none of it (the store off,
## the car out of _ready full and healthy whatever user://cars.json holds),
## both numbers go through a file of the test's own and come back to the bit in
## the one entry beside the odometer, the fuel and the dashboard, in the one
## write; what is no share of a battery is refused with the reason, naming the
## car and the field; a car that loads a flat, worn battery starts with it, its
## charge held under what the wear leaves; and a reset is a new battery in
## memory, the file untold. Last, nothing of it is ever NaN.
## Exits 0 on success, 1 on any failed check.

const MAIN_SCENE := "res://scenes/main.tscn"

## Physics frames to let the car settle on the ground at the start.
const SETTLE_FRAMES := 60

## Ticks a dry tank is given to run the engine down and stop it (4 s; the
## smoke test's FUEL_DRY_RUN_DOWN_FRAMES): how a stalled engine is made here.
## Refuelled afterwards, it stays stopped until the starter turns it.
const RUN_DOWN_FRAMES := 240

## The most ticks a crank is watched for (2 s): over the 0.8 s cycle by a wide
## margin, so a crank that never catches is seen through to the starter letting
## go.
const CRANK_WATCH_FRAMES := 120

## Ticks after the press the crank rpm of a full and a weak battery are
## compared at: 5 ticks in, ~0.08 s, a full battery has the engine at ~300 rpm.
const CRANK_EARLY_TICK := 5

## The charges the weak cranks are tried from (0..1 of a new battery): a third,
## where the catch takes ~0.46 s to the full battery's ~0.19 s; a twentieth,
## under the ~13 % the catch needs, where the engine turns and never catches;
## and none. And the wear of the worn battery (0..1): half, so full it holds
## half and cranks as a half-charged new one does.
const WEAK_CHARGE := 0.3
const DEAD_CHARGE := 0.05
const WORN_WEAR := 0.5

## The alternator is watched charging for this many ticks (1 s) at idle and at
## the limiter, from this charge (under the taper: the battery takes all it is
## given), and the rate has to be within this share of the curve's own number
## (the idle wobbles by a few rpm, the limiter bounces above the rated rpm).
const CHARGE_WATCH_FRAMES := 60
const CHARGE_FROM := 0.5
const CHARGE_RATE_TOLERANCE := 0.05

## Ticks a stalled car free-revs in neutral before the limiter's charging is
## measured (1 s: from idle to the limiter takes ~0.8 s).
const FREE_REV_FRAMES := 60

## A charge a hair over the deep-discharge line (0..1): one tick of the key-on
## drain (0.5 J of 2.16 MJ, 2.3e-7) takes it under.
const OVER_THE_LINE := 1.0e-7

## Ticks a battery is left deeply discharged for the flat wear to show (10 s:
## 2.78e-5 at 1 % an hour).
const FLAT_FRAMES := 600

## How far a wear read may be from the sum it should be (0..1): the flat wear
## of a tick or two either side of the event.
const WEAR_TOLERANCE := 1.0e-6

## Where the store is tried out: a file of the test's own, in a tmp dir of the
## run's own, never the game's user://cars.json.
const TMP_DIR_PREFIX := "/tmp/fd-3T-battery-"
var _store_dir := TMP_DIR_PREFIX + str(OS.get_process_id())
var _store_file := _store_dir + "/cars.json"

## Battery store: a battery that has to come back to the bit, and the flat,
## worn one a car is started with.
const STORE_HARD_BATTERY := {"charge": 0.123456789012345, "capacity_wear": 0.0123456789012345}
const STORE_FLAT_BATTERY := {"charge": 0.15, "capacity_wear": 0.25}

## The dashboard the one-write check saves beside the battery.
const STORE_DRIVER := {"tcs_on": false, "abs_on": true, "sc_on": false, "gearbox_mode": "eco", "automatic": false, "camera_view": 2}

var _failures := 0

## The battery as _ready left it, before a tick could touch it: full and
## healthy, whatever the game's own file holds.
var _charge_at_start := -1.0
var _wear_at_start := -1.0


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
		_charge_at_start = car_at_ready.battery_charge
		_wear_at_start = car_at_ready.battery_wear
	await _step(SETTLE_FRAMES)

	var car := main.get_node_or_null("Car") as ArcadeCar
	var hud := main.get_node_or_null("HUD") as HUD
	var bar := main.get_node_or_null("HUD/BatteryBarBack/BatteryBar") as ColorRect
	if not _check(car != null and hud != null and bar != null, "car, HUD and the HUD's battery bar exist"):
		_finish()
		return

	_check_model_numbers()
	_check_suite_gate(car)
	await _check_alternator(car)
	await _check_crank_draw_and_sag(car, bar)
	await _check_weak_battery(car)
	await _check_deep_discharge(car)
	await _check_hud_bar(car, hud, bar)
	await _check_store(car, bar)
	await _check_no_nan(car)

	car.reset_to_spawn()
	await _step(5)
	_finish()


## The model's own numbers: the capacity in joules from the amp hours, the
## alternator's curve at its anchors, and where the starter gives up - the
## ~13 % the catch needs, worked out from the starter's line against the
## engine's friction at ENGINE_CATCH_RPM, is over the deep-discharge line.
func _check_model_numbers() -> void:
	var capacity := ArcadeCar.BATTERY_CAPACITY_AH * 3600.0 * ArcadeCar.BATTERY_NOMINAL_VOLTAGE
	_check(ArcadeCar.BATTERY_CAPACITY_J == capacity and capacity > 1.0e6 and capacity < 1.0e7, "model: the battery holds %.2f MJ, %.0f Ah at %.0f V" % [capacity / 1.0e6, ArcadeCar.BATTERY_CAPACITY_AH, ArcadeCar.BATTERY_NOMINAL_VOLTAGE])
	var cut_in := ArcadeCar.ALTERNATOR_CUT_IN_RPM
	var rated := ArcadeCar.ALTERNATOR_RATED_RPM
	var halfway := (cut_in + rated) / 2.0
	var curve_ok := ArcadeCar.alternator_power(0.0) == 0.0 and ArcadeCar.alternator_power(cut_in) == 0.0 \
		and is_equal_approx(ArcadeCar.alternator_power(halfway), ArcadeCar.ALTERNATOR_POWER / 2.0) \
		and ArcadeCar.alternator_power(rated) == ArcadeCar.ALTERNATOR_POWER and ArcadeCar.alternator_power(ArcadeCar.REDLINE_RPM) == ArcadeCar.ALTERNATOR_POWER \
		and ArcadeCar.alternator_power(ArcadeCar.IDLE_RPM) > 0.0 and ArcadeCar.alternator_power(ArcadeCar.IDLE_RPM) < ArcadeCar.ALTERNATOR_POWER / 2.0
	_check(curve_ok, "model: the alternator makes nothing to %.0f rpm, half at %.0f, its %.0f W from %.0f rpm up, and %.0f W at the %.0f rpm idle - little at idle, more at speed" % [cut_in, halfway, ArcadeCar.ALTERNATOR_POWER, rated, ArcadeCar.alternator_power(ArcadeCar.IDLE_RPM), ArcadeCar.IDLE_RPM])
	var idle_net := ArcadeCar.alternator_power(ArcadeCar.IDLE_RPM) - ArcadeCar.BATTERY_RUNNING_LOAD
	_check(idle_net > 0.0 and idle_net < ArcadeCar.ALTERNATOR_POWER - ArcadeCar.BATTERY_RUNNING_LOAD, "model: at idle the alternator has %.0f W left for the battery after the ignition's %.0f W, at speed %.0f W" % [idle_net, ArcadeCar.BATTERY_RUNNING_LOAD, ArcadeCar.ALTERNATOR_POWER - ArcadeCar.BATTERY_RUNNING_LOAD])
	# The starter's torque at the catch speed on a full battery, and the
	# friction it has to beat there: the strength the catch needs is their
	# ratio, the charge its square.
	var catch_line := 1.0 - ArcadeCar.ENGINE_CATCH_RPM / ArcadeCar.STARTER_FREE_RPM
	var friction_at_catch := ArcadeCar.ENGINE_FRICTION_TORQUE + ArcadeCar.ENGINE_FRICTION_TORQUE_PER_RPM * ArcadeCar.ENGINE_CATCH_RPM
	var strength_needed := friction_at_catch / (ArcadeCar.CRANKING_TORQUE * catch_line)
	var charge_needed := strength_needed * strength_needed
	_check(charge_needed > ArcadeCar.BATTERY_DEEP_DISCHARGE_CHARGE and charge_needed < 0.2 and DEAD_CHARGE < charge_needed and WEAK_CHARGE > charge_needed, "model: the catch needs a cranking strength of %.2f, a charge of %.1f %% - over the deep-discharge line at %.0f %%, under the %.0f %% the weak crank is tried from" % [strength_needed, charge_needed * 100.0, ArcadeCar.BATTERY_DEEP_DISCHARGE_CHARGE * 100.0, WEAK_CHARGE * 100.0])


## Nothing read: the store is off (the odometer's switch, the one gate) and the
## car came out of _ready with a full, healthy battery, whatever the game's
## file holds for it.
func _check_suite_gate(car: ArcadeCar) -> void:
	_check(
		not OdometerStore.enabled() and OdometerStore.enabled() == TelemetryRecorder.should_record() and not car._odometer_kept
			and _charge_at_start == 1.0 and _wear_at_start == 0.0 and car.battery_cranking_strength() == 1.0,
		"suite: the headless suite reads no battery - the store is off, the car came out of _ready with a full, healthy battery (charge %.3f, wear %.3f, cranking strength 1) whatever %s holds" % [_charge_at_start, _wear_at_start, OdometerStore.PATH],
	)


## The alternator recharges while the engine runs: at idle at the curve's idle
## rate, at the limiter at its rated one, the second several times the first.
## Full, the battery takes nothing more: the charge stays exactly 1.
func _check_alternator(car: ArcadeCar) -> void:
	var tick := 1.0 / Engine.physics_ticks_per_second
	var capacity := ArcadeCar.BATTERY_CAPACITY_J
	car.reset_to_spawn()
	await _step(SETTLE_FRAMES)
	var full_stays := car.battery_charge == 1.0 and car.engine_running
	car.battery_charge = CHARGE_FROM
	var lowest_rpm := INF
	var highest_rpm := 0.0
	for frame in CHARGE_WATCH_FRAMES:
		await physics_frame
		lowest_rpm = minf(lowest_rpm, car.engine_rpm)
		highest_rpm = maxf(highest_rpm, car.engine_rpm)
	var idle_gain := car.battery_charge - CHARGE_FROM
	var idle_expected := (ArcadeCar.alternator_power(ArcadeCar.IDLE_RPM) - ArcadeCar.BATTERY_RUNNING_LOAD) * ArcadeCar.BATTERY_CHARGE_EFFICIENCY * CHARGE_WATCH_FRAMES * tick / capacity
	_check(
		full_stays and idle_gain > 0.0 and absf(idle_gain / idle_expected - 1.0) < CHARGE_RATE_TOLERANCE and highest_rpm - lowest_rpm < 50.0,
		"alternator: full, the battery stays at exactly 1; from %.0f %% it charges at idle (%.0f..%.0f rpm) by %.1f J in %.0f s - the curve's %.1f J, %.0f W net" % [CHARGE_FROM * 100.0, lowest_rpm, highest_rpm, idle_gain * capacity, CHARGE_WATCH_FRAMES * tick, idle_expected * capacity, idle_expected * capacity / (CHARGE_WATCH_FRAMES * tick)],
	)

	# Neutral, full throttle: the engine free-revs to the limiter and bounces
	# there, over the rated rpm the whole second.
	car.automatic = false
	car.shift_down()
	car.set_driver_input(1.0, 0.0, 0.0)
	await _step(FREE_REV_FRAMES)
	car.battery_charge = CHARGE_FROM
	lowest_rpm = INF
	for frame in CHARGE_WATCH_FRAMES:
		await physics_frame
		lowest_rpm = minf(lowest_rpm, car.engine_rpm)
	var fast_gain := car.battery_charge - CHARGE_FROM
	var fast_expected := (ArcadeCar.ALTERNATOR_POWER - ArcadeCar.BATTERY_RUNNING_LOAD) * ArcadeCar.BATTERY_CHARGE_EFFICIENCY * CHARGE_WATCH_FRAMES * tick / capacity
	car.clear_driver_input()
	_check(
		car.gear == 0 and lowest_rpm >= ArcadeCar.ALTERNATOR_RATED_RPM and absf(fast_gain / fast_expected - 1.0) < CHARGE_RATE_TOLERANCE and fast_gain > 4.0 * idle_gain,
		"alternator: at the limiter in neutral (never under %.0f rpm) it charges by %.1f J in the same second - the rated %.1f J, %.1f times the idle's: little at idle, more at speed" % [lowest_rpm, fast_gain * capacity, fast_expected * capacity, fast_gain / idle_gain],
	)
	car.reset_to_spawn()
	await _step(5)


## Cranking draws charge, much more than the key-on drain over the same ticks,
## and the HUD's bar sags with it tick by tick, unsmoothed.
func _check_crank_draw_and_sag(car: ArcadeCar, bar: ColorRect) -> void:
	var tick := 1.0 / Engine.physics_ticks_per_second
	var stalled := await _stall(car)
	# The key-on drain first: the engine off, nothing cranking.
	var before_drain := car.battery_charge
	await _step(CRANK_WATCH_FRAMES)
	var drain_per_tick := (before_drain - car.battery_charge) / CRANK_WATCH_FRAMES
	var drain_expected := ArcadeCar.BATTERY_KEY_ON_LOAD * tick / ArcadeCar.BATTERY_CAPACITY_J
	_check(stalled and drain_per_tick > 0.0 and is_equal_approx(drain_per_tick, drain_expected), "drain: with the engine off the key-on load takes %.3f J a tick off the charge (%.0f W over a tick: %.3f J)" % [drain_per_tick * ArcadeCar.BATTERY_CAPACITY_J, ArcadeCar.BATTERY_KEY_ON_LOAD, drain_expected * ArcadeCar.BATTERY_CAPACITY_J])

	car.battery_charge = 1.0
	# One tick: the bar shows the charge the tick's key-on drain leaves.
	await _step(1)
	var bar_before: float = bar.scale.x
	var samples: Array[float] = []
	var charge_samples: Array[float] = []
	var crank := await _crank(car, samples, charge_samples)
	var drawn: float = 1.0 - crank.charge_at_catch
	var drain_over_crank: float = drain_expected * crank.ticks
	_check(
		crank.caught and drawn > 0.0 and drawn > 10.0 * drain_over_crank and crank.energy_j > 100.0 and crank.energy_j < 1000.0,
		"crank: a full battery starts the engine in %d ticks (%.2f s) and the crank takes %.4f %% off the charge, %.0f J - %.0f times the key-on drain over the same ticks" % [crank.ticks, crank.ticks * tick, drawn * 100.0, crank.energy_j, drawn / drain_over_crank],
	)
	var sagging := samples.size() >= 3 and bar_before > 0.999
	var strictly_down := true
	for i in samples.size():
		if i > 0 and not samples[i] < samples[i - 1]:
			strictly_down = false
		# What the bar shows is the car's charge of this tick or the one before:
		# nothing smoothed, nothing scaled.
		var matches_a_tick: bool = is_equal_approx(samples[i], charge_samples[i]) or (i > 0 and is_equal_approx(samples[i], charge_samples[i - 1]))
		sagging = sagging and matches_a_tick
	_check(
		sagging and strictly_down and samples[samples.size() - 1] < bar_before,
		"HUD: through the crank the battery bar sags tick by tick, every tick lower than the last (%d ticks sampled, %.6f down to %.6f), each the car's own charge" % [samples.size(), bar_before, samples[samples.size() - 1]],
	)
	car.reset_to_spawn()
	await _step(5)


## A weak battery cranks measurably slower: the crank rpm lower at the same
## tick, the catch later - from the starter's torque line alone; under the
## catch line the engine turns and never starts; empty, nothing turns; worn, a
## full battery is slower than a new one.
func _check_weak_battery(car: ArcadeCar) -> void:
	var tick := 1.0 / Engine.physics_ticks_per_second
	await _stall(car)
	car.battery_charge = 1.0
	var full := await _crank(car)
	await _stall(car)
	car.battery_charge = WEAK_CHARGE
	var weak := await _crank(car)
	_check(
		full.caught and weak.caught and weak.ticks > full.ticks + 5 and weak.early_rpm < full.early_rpm * 0.8 and weak.early_rpm > 0.0
			and car.battery_cranking_strength() < 1.0 and is_equal_approx(sqrt(car.battery_charge), car.battery_cranking_strength()),
		"weak: from %.0f %% the starter has the engine at %.0f rpm %d ticks in and catches after %d ticks (%.2f s); from full %.0f rpm and %d ticks (%.2f s) - slower, later, from the torque line alone" % [WEAK_CHARGE * 100.0, weak.early_rpm, CRANK_EARLY_TICK, weak.ticks, weak.ticks * tick, full.early_rpm, full.ticks, full.ticks * tick],
	)

	await _stall(car)
	car.battery_charge = DEAD_CHARGE
	var dead := await _crank(car)
	_check(
		not dead.caught and dead.peak_rpm > 0.0 and dead.peak_rpm < ArcadeCar.ENGINE_CATCH_RPM and not car.engine_running and car.battery_charge < DEAD_CHARGE,
		"dead: from %.0f %% the starter turns the engine (to %.0f rpm) and never starts it - under the ~13 %% the catch needs (%d ticks cranked, the charge drawn down to %.4f)" % [DEAD_CHARGE * 100.0, dead.peak_rpm, dead.ticks, car.battery_charge],
	)

	await _stall(car)
	car.battery_charge = 0.0
	var empty := await _crank(car)
	_check(
		not empty.caught and empty.peak_rpm == 0.0 and empty.cranked and car.engine_rpm == 0.0 and car.battery_charge == 0.0 and car.battery_cranking_strength() == 0.0,
		"empty: the starter is on for its cycle (%d ticks) and turns nothing - no strength, no draw, the charge stays 0" % empty.ticks,
	)

	await _stall(car)
	car.battery_wear = WORN_WEAR
	car.battery_charge = 1.0
	var worn_full := car.battery_charge
	var worn := await _crank(car)
	_check(
		worn.caught and worn_full == 1.0 - WORN_WEAR and worn.ticks > full.ticks + 3 and worn.early_rpm < full.early_rpm,
		"worn: a battery that has lost %.0f %% fills to %.0f %% and, full, cranks slower than a new one (%.0f rpm %d ticks in, caught after %d ticks; new %.0f rpm, %d ticks)" % [WORN_WEAR * 100.0, worn_full * 100.0, worn.early_rpm, CRANK_EARLY_TICK, worn.ticks, full.early_rpm, full.ticks],
	)
	car.reset_to_spawn()
	await _step(5)


## A deep discharge ages the capacity: the tick the charge goes under the line
## costs the wear once, every tick down there a little more, back over and
## under again costs it again; the capacity read follows the wear, a worn
## battery fills to less, and the wear stops at its limit.
func _check_deep_discharge(car: ArcadeCar) -> void:
	var tick := 1.0 / Engine.physics_ticks_per_second
	var line := ArcadeCar.BATTERY_DEEP_DISCHARGE_CHARGE
	var per_event := ArcadeCar.BATTERY_DEEP_DISCHARGE_WEAR
	var stalled := await _stall(car)
	var wear_new := car.battery_wear
	var capacity_new := car.battery_capacity_j()
	car.battery_charge = line + OVER_THE_LINE
	await _step(1)
	var crossed := car.battery_charge < line
	var wear_after_event := car.battery_wear
	_check(
		stalled and wear_new == 0.0 and capacity_new == ArcadeCar.BATTERY_CAPACITY_J and crossed and absf(wear_after_event - per_event) < WEAR_TOLERANCE,
		"wear: the key-on drain takes a battery from just over the %.0f %% line under it, and that tick costs %.1f %% of its capacity (wear %.6f)" % [line * 100.0, per_event * 100.0, wear_after_event],
	)
	await _step(FLAT_FRAMES)
	var flat_wear := car.battery_wear - wear_after_event
	var flat_expected := ArcadeCar.BATTERY_FLAT_WEAR_RATE * FLAT_FRAMES * tick
	_check(
		flat_wear > 0.0 and absf(flat_wear / flat_expected - 1.0) < 0.05 and car.battery_charge < line,
		"wear: left flat for %.0f s it loses %.1f ppm more (%.1f ppm at %.0f %% an hour), still under the line" % [FLAT_FRAMES * tick, flat_wear * 1.0e6, flat_expected * 1.0e6, ArcadeCar.BATTERY_FLAT_WEAR_RATE * 3600.0 * 100.0],
	)
	var wear_before_second := car.battery_wear
	car.battery_charge = CHARGE_FROM
	await _step(1)
	var back_over := car.battery_wear == wear_before_second and not car._battery_deep
	car.battery_charge = line + OVER_THE_LINE
	await _step(1)
	var second_event := car.battery_wear - wear_before_second
	var capacity := car.battery_capacity_j()
	car.battery_charge = 1.0
	var fills_to := car.battery_charge
	_check(
		back_over and absf(second_event - per_event) < WEAR_TOLERANCE and capacity == ArcadeCar.BATTERY_CAPACITY_J * (1.0 - car.battery_wear) and capacity < capacity_new
			and fills_to == 1.0 - car.battery_wear and car.battery_cranking_strength() < 1.0,
		"wear: charged back over the line nothing more is taken; under it again another %.1f %% is (wear %.6f); the capacity reads %.0f J of the new %.0f, and full is %.4f now" % [per_event * 100.0, car.battery_wear, capacity, capacity_new, fills_to],
	)
	car.battery_wear = 5.0
	var bounded := car.battery_wear == ArcadeCar.BATTERY_WEAR_LIMIT and car.battery_charge <= 1.0 - ArcadeCar.BATTERY_WEAR_LIMIT
	car.battery_charge = 1.0
	_check(bounded and car.battery_charge == 1.0 - ArcadeCar.BATTERY_WEAR_LIMIT and car.battery_capacity_j() > 0.0, "wear: bounded at %.0f %% - a battery that far gone fills to %.0f %% and still has a capacity to hold it against (%.0f J)" % [ArcadeCar.BATTERY_WEAR_LIMIT * 100.0, car.battery_charge * 100.0, car.battery_capacity_j()])
	car.reset_to_spawn()
	await _step(5)


## The HUD's battery bar follows the charge, from the left, in the fuel bar's
## idiom: its own colour, amber under BATTERY_LOW_FRACTION, red under
## BATTERY_CRITICAL_FRACTION, hidden at 0 and for NaN, and the fuel bar is left
## alone. The engine runs throughout, so every level set is charged up from,
## never down: none of them goes under the deep-discharge line (the red one is
## set halfway between it and the red threshold), and the battery is the new
## one at the end.
func _check_hud_bar(car: ArcadeCar, hud: HUD, bar: ColorRect) -> void:
	var fuel_bar := hud.get_node("FuelBarBack/FuelBar") as ColorRect
	await _step(2)
	var full_ok := bar.visible and is_equal_approx(bar.scale.x, 1.0) and bar.color == HUD.BATTERY_COLOR and car.battery_charge == 1.0 and car.engine_running
	var levels := {
		"normal": (HUD.BATTERY_LOW_FRACTION + 1.0) / 2.0,
		"low": (HUD.BATTERY_CRITICAL_FRACTION + HUD.BATTERY_LOW_FRACTION) / 2.0,
		"critical": (ArcadeCar.BATTERY_DEEP_DISCHARGE_CHARGE + HUD.BATTERY_CRITICAL_FRACTION) / 2.0,
	}
	var colours := {"normal": HUD.BATTERY_COLOR, "low": HUD.BATTERY_LOW_COLOR, "critical": HUD.BATTERY_CRITICAL_COLOR}
	var followed := 0
	for level: String in levels:
		car.battery_charge = levels[level]
		await _step(2)
		if bar.visible and is_equal_approx(bar.scale.x, car.battery_charge) and bar.color == colours[level] and fuel_bar.color == HUD.FUEL_COLOR and is_equal_approx(fuel_bar.scale.x, car.fuel_fraction()):
			followed += 1
	hud.set_battery_bar(0.0)
	var hidden := not bar.visible
	hud.set_battery_bar(NAN)
	hidden = hidden and not bar.visible
	hud.set_battery_bar(7.0)
	var clamped := bar.visible and bar.scale.x == 1.0
	car.battery_charge = 1.0
	await _step(2)
	_check(
		full_ok and followed == levels.size() and hidden and clamped and bar.visible and is_equal_approx(bar.scale.x, 1.0) and bar.color == HUD.BATTERY_COLOR
			and car.battery_charge == 1.0 and car.battery_wear == 0.0
			and HUD.BATTERY_CRITICAL_FRACTION < HUD.BATTERY_LOW_FRACTION and HUD.BATTERY_LOW_FRACTION < 1.0 and HUD.BATTERY_CRITICAL_FRACTION > ArcadeCar.BATTERY_DEEP_DISCHARGE_CHARGE,
		"HUD: the battery bar follows the charge (%d of %d levels to the bit), its own colour over %.0f %%, amber under, red under %.0f %%, hidden at 0 and for NaN, clamped at 1, the fuel bar untouched; and it is the car's again the next tick" % [followed, levels.size(), HUD.BATTERY_LOW_FRACTION * 100.0, HUD.BATTERY_CRITICAL_FRACTION * 100.0],
	)


## The battery kept from one session to the next, beside the odometer, the fuel
## and the dashboard: through the store to the bit, never a number that is
## none, and the car that loads one starts with it.
func _check_store(car: ArcadeCar, bar: ColorRect) -> void:
	# (1) The store itself, on a file of the test's own: both numbers come back
	# as they went in, in the one entry beside the rest and in the one write; a
	# car, a file or an entry with no battery is a car that has not been driven
	# - full, healthy, nothing wrong; a save with a NaN charge writes the
	# default, a save of the metres alone leaves the battery as it was.
	DirAccess.make_dir_recursive_absolute(_store_dir)
	if FileAccess.file_exists(_store_file):
		DirAccess.remove_absolute(_store_file)
	var new_car := OdometerStore.load_battery(ArcadeCar.CAR_ID, _store_file)
	OdometerStore.save_car(ArcadeCar.CAR_ID, 4321.5, 12.5, _store_file, STORE_DRIVER, STORE_HARD_BATTERY)
	OdometerStore.save_car("some_other_car", NAN, NAN, _store_file, {}, {"charge": NAN})
	OdometerStore.save_car(ArcadeCar.CAR_ID, 4400.0, NAN, _store_file)
	var written: Variant = JSON.parse_string(FileAccess.get_file_as_string(_store_file))
	var entry: Dictionary = written["cars"][ArcadeCar.CAR_ID] if written is Dictionary else {}
	var back := OdometerStore.load_battery(ArcadeCar.CAR_ID, _store_file)
	var other := OdometerStore.load_battery("some_other_car", _store_file)
	var unknown := OdometerStore.load_battery("no_such_car", _store_file)
	var defaults_back := true
	for battery: Dictionary in [new_car, unknown, other]:
		for field: String in OdometerStore.BATTERY_DEFAULTS:
			defaults_back = defaults_back and battery[field] == OdometerStore.BATTERY_DEFAULTS[field]
		defaults_back = defaults_back and (battery.problems as Array).is_empty()
	_check(
		back.charge == STORE_HARD_BATTERY.charge and back.capacity_wear == STORE_HARD_BATTERY.capacity_wear and (back.problems as Array).is_empty()
			and entry.get("odometer_m") == 4400.0 and entry.get("fuel_l") == 12.5 and entry.get("driver", {}).get("gearbox_mode") == "eco" and entry.get("battery", {}).get("charge") == STORE_HARD_BATTERY.charge
			and defaults_back and written["cars"]["some_other_car"].get("battery", {}).get("charge") == 1.0 and not written["cars"]["some_other_car"].has("odometer_m")
			and typeof(back.charge) == TYPE_FLOAT and typeof(back.capacity_wear) == TYPE_FLOAT,
		"store: both numbers come back to the bit (charge %.15f, wear %.16f) in the one entry beside the odometer, the fuel and the dashboard, in the one write; a save of the metres alone leaves them; a NaN charge goes in as the full default; a car, a file or an entry with no battery is full, healthy and nothing wrong" % [back.charge, back.capacity_wear],
	)

	# (2) A number that is no share of a battery: its default and the reason,
	# as text - the car that asks makes the error of it (push_error; not here,
	# the suite's output has none). NaN and inf never get through a JSON file,
	# so they go to the check itself.
	var not_shares: Array = [NAN, INF, -INF, -0.001, 1.001, 2, "full", "", null, true, false, [0.5], {"charge": 0.5}]
	var refused := 0
	var tried := 0
	for field: String in OdometerStore.BATTERY_DEFAULTS:
		for value: Variant in not_shares:
			tried += 1
			if OdometerStore.battery_problem(field, value) != "":
				refused += 1
	var shares_ok := true
	for value: Variant in [0, 1, 0.0, 1.0, 0.5, 0.999]:
		shares_ok = shares_ok and OdometerStore.battery_problem("charge", value) == "" and OdometerStore.battery_problem("capacity_wear", value) == ""
	var no_field := OdometerStore.battery_problem("voltage", 12.0) != ""
	var garage_file := FileAccess.open(_store_file, FileAccess.WRITE)
	garage_file.store_string('{"version": 1, "cars": {"bad_car": {"odometer_m": 7.5, "battery": {"charge": "full", "capacity_wear": -0.1}}, "part_bad": {"battery": {"charge": 0.4, "capacity_wear": 2}}, "whole": {"battery": {"charge": 1, "capacity_wear": 0}}}}')
	garage_file.close()
	var bad := OdometerStore.load_battery("bad_car", _store_file)
	var said := 0
	for field: String in OdometerStore.BATTERY_DEFAULTS:
		for problem: String in bad.problems:
			if problem.contains("bad_car's battery " + field):
				said += 1
	var part_bad := OdometerStore.load_battery("part_bad", _store_file)
	var whole := OdometerStore.load_battery("whole", _store_file)
	_check(
		refused == tried and shares_ok and no_field and said == 2 and bad.charge == 1.0 and bad.capacity_wear == 0.0
			and part_bad.charge == 0.4 and part_bad.capacity_wear == 0.0 and (part_bad.problems as Array).size() == 1
			and whole.charge == 1.0 and whole.capacity_wear == 0.0 and typeof(whole.charge) == TYPE_FLOAT and (whole.problems as Array).is_empty()
			and OdometerStore.load_odometer("bad_car", _store_file) == 7.5,
		"store: NaN, inf, under 0, over 1, words, null, a bool, a list and an object are no share of a battery (%d of %d refused, both of a bad entry read as their default with the reason, naming the car and the field); the number beside a bad one still loads, and the car's metres with them; a whole 1 and 0 are floats" % [refused, tried],
	)

	# (3) The car that loads a battery starts with it, not full: flat and worn,
	# the charge held under what the wear leaves, the bar red. And a reset is a
	# new battery - the debug verb it always was - without a word to the file.
	OdometerStore.save_car(ArcadeCar.CAR_ID, 1000.0, 30.0, _store_file, {}, STORE_FLAT_BATTERY)
	car.reset_to_spawn()
	car._load_stored_battery(_store_file)
	var loaded_charge := car.battery_charge
	var loaded_wear := car.battery_wear
	var loaded_deep := car._battery_deep
	await _step(2)
	var red := bar.visible and bar.color == HUD.BATTERY_CRITICAL_COLOR and is_equal_approx(bar.scale.x, car.battery_charge)
	var charging := car.battery_charge > loaded_charge and car.engine_running
	OdometerStore.save_car(ArcadeCar.CAR_ID, NAN, NAN, _store_file, {}, {"charge": 1.0, "capacity_wear": 0.25})
	var file_before := FileAccess.get_file_as_string(_store_file)
	car._load_stored_battery(_store_file)
	var trimmed := car.battery_charge == 0.75 and car.battery_wear == 0.25
	car.reset_to_spawn()
	await _step(5)
	_check(
		loaded_charge == STORE_FLAT_BATTERY.charge and loaded_wear == STORE_FLAT_BATTERY.capacity_wear and not loaded_deep and red and charging and trimmed
			and car.battery_charge == 1.0 and car.battery_wear == 0.0 and not car._battery_deep
			and FileAccess.get_file_as_string(_store_file) == file_before and not car._odometer_kept,
		"store: a car that loads a battery at %.0f %% with %.0f %% worn starts exactly so, the bar red, the alternator charging it; one saved fuller than its wear leaves is trimmed to %.2f; a reset is a new battery (charge 1, wear 0) and the file is not told" % [STORE_FLAT_BATTERY.charge * 100.0, STORE_FLAT_BATTERY.capacity_wear * 100.0, 0.75],
	)
	DirAccess.remove_absolute(_store_file)
	DirAccess.remove_absolute(_store_dir)


## Nothing of it is ever NaN: a NaN charge is flat, a NaN wear is none, the
## strength and the capacity read are finite with them, and after everything
## above the state is finite.
func _check_no_nan(car: ArcadeCar) -> void:
	car.battery_charge = NAN
	var nan_charge := car.battery_charge == 0.0 and car.battery_cranking_strength() == 0.0
	car.battery_wear = NAN
	var nan_wear := car.battery_wear == 0.0 and car.battery_capacity_j() == ArcadeCar.BATTERY_CAPACITY_J
	car.battery_charge = INF
	var inf_charge := car.battery_charge == 1.0
	car.battery_charge = -INF
	var neg_inf_charge := car.battery_charge == 0.0
	car.reset_to_spawn()
	await _step(2)
	var finite := is_finite(car.battery_charge) and is_finite(car.battery_wear) and is_finite(car.battery_cranking_strength()) and is_finite(car.battery_capacity_j()) and is_finite(ArcadeCar.alternator_power(car.engine_rpm))
	_check(nan_charge and nan_wear and inf_charge and neg_inf_charge and finite, "no NaN: a NaN charge is flat, a NaN wear is none, inf is full and -inf flat, and the whole state is finite after the run (charge %.3f, wear %.3f)" % [car.battery_charge, car.battery_wear])


## Stops the engine the way a dry tank does (reset, the tank emptied, the engine
## run down), then refuels: a stopped engine with fuel, which only the starter
## turns. Returns whether it stands at 0 rpm, not running, not cranking.
func _stall(car: ArcadeCar) -> bool:
	car.reset_to_spawn()
	await _step(5)
	car.fuel_l = 0.0
	await _step(RUN_DOWN_FRAMES)
	car.fuel_l = ArcadeCar.FUEL_TANK_CAPACITY_L
	await _step(2)
	return not car.engine_running and car.engine_rpm == 0.0 and not car.cranking()


## One tap of the starter key, watched to the catch or to the starter letting
## go (CRANK_WATCH_FRAMES at most):
##   {"caught": whether the engine runs, "ticks": ticks from the press to the
##    catch (or cranked, if it never caught), "early_rpm": the engine's speed
##    CRANK_EARLY_TICK ticks after the press, "peak_rpm": the fastest it turned,
##    "cranked": whether the starter was ever on, "charge_at_catch": the charge
##    the tick it caught (or the last cranking tick), "energy_j": what the
##    crank took [J]}
## `bar_samples` / `charge_samples`, if handed, get the HUD bar's fill and the
## car's charge on every cranking tick.
func _crank(car: ArcadeCar, bar_samples: Array[float] = [], charge_samples: Array[float] = []) -> Dictionary:
	var bar := root.get_node_or_null("Main/HUD/BatteryBarBack/BatteryBar") as ColorRect
	var charge_before := car.battery_charge
	var seen := {"caught": false, "ticks": 0, "early_rpm": 0.0, "peak_rpm": 0.0, "cranked": false, "charge_at_catch": charge_before, "energy_j": 0.0}
	Input.action_press("starter")
	for frame in CRANK_WATCH_FRAMES:
		await physics_frame
		if frame == 0:
			Input.action_release("starter")
		var ticks := frame + 1
		seen.peak_rpm = maxf(seen.peak_rpm, car.engine_rpm)
		if ticks == CRANK_EARLY_TICK:
			seen.early_rpm = car.engine_rpm
		if car.engine_running:
			seen.caught = true
			seen.ticks = ticks
			seen.charge_at_catch = car.battery_charge
			break
		if car.cranking():
			seen.cranked = true
			seen.ticks = ticks
			seen.charge_at_catch = car.battery_charge
			if bar != null:
				bar_samples.append(bar.scale.x)
				charge_samples.append(car.battery_charge)
		elif seen.cranked:
			break
	seen.energy_j = (charge_before - seen.charge_at_catch) * ArcadeCar.BATTERY_CAPACITY_J
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
	if FileAccess.file_exists(_store_file):
		DirAccess.remove_absolute(_store_file)
	if DirAccess.dir_exists_absolute(_store_dir):
		DirAccess.remove_absolute(_store_dir)
	if _failures == 0:
		print("BATTERY TEST PASSED")
	else:
		printerr("BATTERY TEST FAILED: %d check(s) failed" % _failures)
	quit(1 if _failures > 0 else 0)
