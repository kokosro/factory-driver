class_name HUD
extends CanvasLayer
## Minimal driving HUD: speed, plus a tach line (engine RPM and gear), the two
## pedal bars so the driving feel can be checked, the fuel bar with the battery
## bar under it and the coolant bar under that, to the left of those the tyre
## bar with the brake bar under it (the hotter axle each, labelled), and a lamp
## each for the three driver aids. The mission line and banner only show what
## they are handed (see scripts/mission_manager.gd); so do the licence card
## (the licence book and the theory quiz's question cards, one overlay,
## scripts/licence_manager.gd) and the gate hint beside the aid lamps (what
## a refused clutch key or aid switch says).
## The odometer's line sits over the aid lamps (see set_odometer).

## Tach text colour normally and from ArcadeCar.SHIFT_LIGHT_RPM up.
const TACH_COLOR := Color(1, 1, 1, 1)
const TACH_REDLINE_COLOR := Color(1.0, 0.3, 0.2, 1)

## Fuel bar colour: normally, amber with less than FUEL_RESERVE_FRACTION of the
## tank left (0..1), red with less than FUEL_LOW_FRACTION.
const FUEL_COLOR := Color(0.85, 0.85, 0.8, 1)
const FUEL_RESERVE_COLOR := Color(1.0, 0.7, 0.15, 1)
const FUEL_LOW_COLOR := Color(1.0, 0.25, 0.2, 1)
const FUEL_RESERVE_FRACTION := 0.15
const FUEL_LOW_FRACTION := 0.08

## Battery bar colour: normally, amber with the charge under
## BATTERY_LOW_FRACTION (0..1 of a new battery: the starter is getting slow,
## ArcadeCar.battery_cranking_strength 0.63 there), red under
## BATTERY_CRITICAL_FRACTION (two cranks from the deep-discharge line, ~13 %
## is where the engine no longer catches).
const BATTERY_COLOR := Color(0.55, 0.8, 0.95, 1)
const BATTERY_LOW_COLOR := Color(1.0, 0.7, 0.15, 1)
const BATTERY_CRITICAL_COLOR := Color(1.0, 0.25, 0.2, 1)
const BATTERY_LOW_FRACTION := 0.4
const BATTERY_CRITICAL_FRACTION := 0.2

## Coolant bar colour, on ArcadeCar.coolant_temp's scale (0 = the air at 15 C,
## 1 = the operating 90 C): blue while the engine is cold, under
## COOLANT_COLD_FRACTION (70 C, where the cold enrichment and the idle hunt end:
## ArcadeCar.COOLANT_WARM_C), the fuel bar's grey warm, red from
## COOLANT_HOT_FRACTION (110 C, where the power starts to fade:
## ArcadeCar.OVERHEAT_FADE_START_C), a brighter red from
## COOLANT_VERY_HOT_FRACTION (120 C, a fifth of the torque gone). The bar is
## full at COOLANT_BAR_FULL (127.5 C): the operating temperature sits two
## thirds along, as a gauge's 90 does. tests/thermal_test.gd holds the two
## lines to the car's own numbers.
const COOLANT_COLD_COLOR := Color(0.4, 0.6, 1.0, 1)
const COOLANT_COLOR := Color(0.85, 0.85, 0.8, 1)
const COOLANT_HOT_COLOR := Color(1.0, 0.25, 0.2, 1)
const COOLANT_VERY_HOT_COLOR := Color(1.0, 0.55, 0.45, 1)
const COOLANT_COLD_FRACTION := 55.0 / 75.0
const COOLANT_HOT_FRACTION := 95.0 / 75.0
const COOLANT_VERY_HOT_FRACTION := 105.0 / 75.0
const COOLANT_BAR_FULL := 1.5

## Tyre bar colour, on ArcadeCar.front_tyre_temp's scale (0 = the air at 15 C,
## 1 = the operating 75 C), the hotter axle: blue while the tyres are cold,
## under TYRE_COLD_FRACTION (45 C, the window's lower edge, under which the
## grip is down: ArcadeCar.TYRE_WINDOW_LOW_C), the fuel bar's grey in the
## window, red from TYRE_HOT_FRACTION (110 C, the upper edge, from which the
## grip fades: ArcadeCar.TYRE_WINDOW_HIGH_C), a brighter red from
## TYRE_VERY_HOT_FRACTION (135 C, an eighth of the grip gone). The bar is full
## at TYRE_BAR_FULL (165 C, where the model stops: ArcadeCar.TYRE_MAX_C).
## tests/tyre_brake_thermal_test.gd holds the lines to the car's own numbers.
const TYRE_COLD_COLOR := Color(0.4, 0.6, 1.0, 1)
const TYRE_COLOR := Color(0.85, 0.85, 0.8, 1)
const TYRE_HOT_COLOR := Color(1.0, 0.25, 0.2, 1)
const TYRE_VERY_HOT_COLOR := Color(1.0, 0.55, 0.45, 1)
const TYRE_COLD_FRACTION := 30.0 / 60.0
const TYRE_HOT_FRACTION := 95.0 / 60.0
const TYRE_VERY_HOT_FRACTION := 120.0 / 60.0
const TYRE_BAR_FULL := 150.0 / 60.0

## Brake bar colour, on ArcadeCar.front_brake_temp's scale (0 = the air at
## 15 C, 1 = the fade line at 250 C), the hotter axle: the fuel bar's grey
## under BRAKE_HOT_FRACTION (the fade line itself, ArcadeCar.BRAKE_FADE_START_C,
## from which the pedal gives less), red from it, a brighter red from
## BRAKE_VERY_HOT_FRACTION (400 C, red hot: ArcadeCar.BRAKE_RED_HOT_C, a
## third of the torque gone). The bar is full at BRAKE_BAR_FULL (600 C, where
## the model stops: ArcadeCar.BRAKE_MAX_C). No cold colour: a brake works
## from cold. tests/tyre_brake_thermal_test.gd holds the lines to the car's
## own numbers.
const BRAKE_HEAT_COLOR := Color(0.85, 0.85, 0.8, 1)
const BRAKE_HOT_COLOR := Color(1.0, 0.25, 0.2, 1)
const BRAKE_VERY_HOT_COLOR := Color(1.0, 0.55, 0.45, 1)
const BRAKE_HOT_FRACTION := 1.0
const BRAKE_VERY_HOT_FRACTION := 385.0 / 235.0
const BRAKE_BAR_FULL := 585.0 / 235.0

## The driver aids' lamps (SC, TCS, ABS): dim while the aid is on, which is how the
## car starts and nothing to look at; lit in the fuel bar's amber, with OFF
## behind the letters, once it has been switched off.
const AID_ON_COLOR := Color(1, 1, 1, 0.35)
const AID_OFF_COLOR := Color(1.0, 0.7, 0.15, 1)

@export var car: ArcadeCar

@onready var _speed_label: Label = $SpeedLabel
@onready var _rpm_label: Label = $RpmLabel
@onready var _mission_label: Label = $MissionLabel
@onready var _mission_banner: Label = $MissionBanner
@onready var _mission_banner_detail: Label = $MissionBannerDetail
@onready var _throttle_bar: ColorRect = $ThrottleBarBack/ThrottleBar
@onready var _brake_bar: ColorRect = $BrakeBarBack/BrakeBar
@onready var _fuel_bar: ColorRect = $FuelBarBack/FuelBar
@onready var _battery_bar: ColorRect = $BatteryBarBack/BatteryBar
@onready var _coolant_bar: ColorRect = $CoolantBarBack/CoolantBar
@onready var _tyre_bar: ColorRect = $TyreBarBack/TyreBar
@onready var _brake_heat_bar: ColorRect = $BrakeHeatBarBack/BrakeHeatBar
@onready var _tcs_lamp: Label = $TcsLamp
@onready var _abs_lamp: Label = $AbsLamp
@onready var _sc_lamp: Label = $ScLamp
@onready var _odometer_label: Label = $OdometerLabel
@onready var _gate_hint: Label = $GateHint
@onready var _licence_card_back: ColorRect = $LicenceCardBack
@onready var _licence_card: Label = $LicenceCard

## The odometer as last written on its label [tenths of a km]; the label's text
## is only made anew when this changes, every 100 m.
var _odometer_shown := -1


func _process(_delta: float) -> void:
	if not car:
		return
	var reversing := car.reverse_engaged
	var gear := "R  " if reversing else ""
	_speed_label.text = "%s%d km/h" % [gear, roundi(car.speed_kmh)]

	var gear_name := "R" if reversing else ("N" if car.gear == 0 else "G%d" % car.gear)
	if not car.automatic:
		gear_name += " M"
	elif car.gearbox_mode == ArcadeCar.GearboxMode.COMFORT:
		# SPORT is the program the car starts in and goes unmentioned.
		gear_name += " comfort"
	elif car.gearbox_mode == ArcadeCar.GearboxMode.ECO:
		gear_name += " eco"
	if car.cranking():
		gear_name += " | CRANKING"
	elif not car.engine_running:
		gear_name += " | STALL"
	# The engine's own speed (ArcadeCar.engine_omega, as rpm): it free-revs,
	# flares on a slipping clutch and bounces off the limiter, whatever the road
	# speed does. Rounded to 50 rpm so the readout does not flicker.
	_rpm_label.text = "%d rpm | %s" % [roundi(car.engine_rpm / 50.0) * 50, gear_name]
	var near_redline := car.engine_rpm >= ArcadeCar.SHIFT_LIGHT_RPM
	_rpm_label.add_theme_color_override("font_color", TACH_REDLINE_COLOR if near_redline else TACH_COLOR)
	set_aid_lamp(_tcs_lamp, "TCS", car.tcs_on)
	set_aid_lamp(_abs_lamp, "ABS", car.abs_on)
	set_aid_lamp(_sc_lamp, "SC", car.sc_on)
	set_odometer(car.odometer_m)


## The pedal bars follow the pedals tick by tick (ArcadeCar.throttle_pedal /
## brake_pedal, what the drivetrain is given): a dab at a key is a bar that
## never gets to the top. The fuel bar follows the tank (ArcadeCar.fuel_fraction),
## the battery bar the charge (ArcadeCar.battery_charge), tick by tick and
## unsmoothed: what a crank draws that tick is off the bar that tick. The
## coolant bar follows the temperature (ArcadeCar.coolant_temp) the same way,
## the tyre bar and the brake bar the hotter axle's (ArcadeCar.front_tyre_temp
## / rear_tyre_temp, front_brake_temp / rear_brake_temp).
func _physics_process(_delta: float) -> void:
	if not car:
		return
	set_throttle_bar(car.throttle_pedal)
	set_brake_bar(car.brake_pedal)
	set_fuel_bar(car.fuel_fraction())
	set_battery_bar(car.battery_charge)
	set_coolant_bar(car.coolant_temp)
	set_tyre_bar(maxf(car.front_tyre_temp, car.rear_tyre_temp))
	set_brake_heat_bar(maxf(car.front_brake_temp, car.rear_brake_temp))


## How full the two pedal bars by the speed are, 0 (empty) .. 1 (full); out of
## range is clamped, NaN is empty. Green = throttle, red = brake.
func set_throttle_bar(value: float) -> void:
	_fill_bar(_throttle_bar, value)


func set_brake_bar(value: float) -> void:
	_fill_bar(_brake_bar, value)


## How full the fuel bar under the pedal bars is, 0 (dry) .. 1 (full tank); out
## of range is clamped, NaN is empty. It lies flat and fills from the left, and
## turns amber, then red, as the tank runs low (FUEL_RESERVE_FRACTION,
## FUEL_LOW_FRACTION).
func set_fuel_bar(value: float) -> void:
	var fill := _fill_bar(_fuel_bar, value, true)
	if fill < FUEL_LOW_FRACTION:
		_fuel_bar.color = FUEL_LOW_COLOR
	elif fill < FUEL_RESERVE_FRACTION:
		_fuel_bar.color = FUEL_RESERVE_COLOR
	else:
		_fuel_bar.color = FUEL_COLOR


## How full the battery bar under the fuel bar is, 0 (flat) .. 1 (a new battery
## full; a worn one never gets there); out of range is clamped, NaN is empty.
## The fuel bar's idiom: flat, filling from the left, amber, then red, as the
## charge runs low (BATTERY_LOW_FRACTION, BATTERY_CRITICAL_FRACTION).
func set_battery_bar(value: float) -> void:
	var fill := _fill_bar(_battery_bar, value, true)
	if fill < BATTERY_CRITICAL_FRACTION:
		_battery_bar.color = BATTERY_CRITICAL_COLOR
	elif fill < BATTERY_LOW_FRACTION:
		_battery_bar.color = BATTERY_LOW_COLOR
	else:
		_battery_bar.color = BATTERY_COLOR


## How far along the coolant bar under the battery bar is: `temp` on
## ArcadeCar.coolant_temp's scale, the bar full at COOLANT_BAR_FULL; out of
## range is clamped, NaN is empty. The fuel bar's idiom, flat and filling from
## the left: blue cold, grey warm, red hot and brighter red hotter
## (COOLANT_COLD_FRACTION, COOLANT_HOT_FRACTION, COOLANT_VERY_HOT_FRACTION).
func set_coolant_bar(temp: float) -> void:
	_fill_bar(_coolant_bar, temp / COOLANT_BAR_FULL, true)
	if temp >= COOLANT_VERY_HOT_FRACTION:
		_coolant_bar.color = COOLANT_VERY_HOT_COLOR
	elif temp >= COOLANT_HOT_FRACTION:
		_coolant_bar.color = COOLANT_HOT_COLOR
	elif temp < COOLANT_COLD_FRACTION:
		_coolant_bar.color = COOLANT_COLD_COLOR
	else:
		_coolant_bar.color = COOLANT_COLOR


## How far along the tyre bar to the left of the battery bar is: `temp` on
## ArcadeCar.front_tyre_temp's scale (the hotter axle's, from
## _physics_process), the bar full at TYRE_BAR_FULL; out of range is clamped,
## NaN is empty. The coolant bar's idiom: blue cold, grey in the window, red
## over it and brighter red hotter (TYRE_COLD_FRACTION, TYRE_HOT_FRACTION,
## TYRE_VERY_HOT_FRACTION).
func set_tyre_bar(temp: float) -> void:
	_fill_bar(_tyre_bar, temp / TYRE_BAR_FULL, true)
	if temp >= TYRE_VERY_HOT_FRACTION:
		_tyre_bar.color = TYRE_VERY_HOT_COLOR
	elif temp >= TYRE_HOT_FRACTION:
		_tyre_bar.color = TYRE_HOT_COLOR
	elif temp < TYRE_COLD_FRACTION:
		_tyre_bar.color = TYRE_COLD_COLOR
	else:
		_tyre_bar.color = TYRE_COLOR


## How far along the brake bar under the tyre bar is: `temp` on
## ArcadeCar.front_brake_temp's scale (the hotter axle's, from
## _physics_process), the bar full at BRAKE_BAR_FULL; out of range is clamped,
## NaN is empty. Grey under the fade line, red from it, brighter red from red
## hot (BRAKE_HOT_FRACTION, BRAKE_VERY_HOT_FRACTION). Cold brakes are an
## empty bar: nothing to look at, as a cold brake is.
func set_brake_heat_bar(temp: float) -> void:
	_fill_bar(_brake_heat_bar, temp / BRAKE_BAR_FULL, true)
	if temp >= BRAKE_VERY_HOT_FRACTION:
		_brake_heat_bar.color = BRAKE_VERY_HOT_COLOR
	elif temp >= BRAKE_HOT_FRACTION:
		_brake_heat_bar.color = BRAKE_HOT_COLOR
	else:
		_brake_heat_bar.color = BRAKE_HEAT_COLOR


## The odometer line over the aid lamps, `metres` as "ODO 12.3 km": the tenths
## that are full (an odometer never shows a metre it has not driven; NaN and
## less than none read 0.0).
func set_odometer(metres: float) -> void:
	var tenths := 0 if is_nan(metres) else int(maxf(metres, 0.0) / 100.0)
	if tenths == _odometer_shown:
		return
	_odometer_shown = tenths
	_odometer_label.text = "ODO %d.%d km" % [tenths / 10, tenths % 10]


## A driver aid's lamp: its letters (`aid`), dim while it is `on`, amber and
## marked OFF once it is not.
func set_aid_lamp(lamp: Label, aid: String, on: bool) -> void:
	lamp.text = aid if on else aid + " OFF"
	lamp.add_theme_color_override("font_color", AID_ON_COLOR if on else AID_OFF_COLOR)


## A bar is a full-size rectangle scaled down from its foot (pivot_offset in
## hud.tscn), or, lying flat (`flat`), from its left end: no layout, no text.
## Empty it is hidden, never scaled to nothing. Returns how full it is, 0..1.
func _fill_bar(bar: ColorRect, value: float, flat := false) -> float:
	var fill := 0.0 if is_nan(value) else clampf(value, 0.0, 1.0)
	bar.visible = fill > 0.0
	if bar.visible and flat:
		bar.scale.x = fill
	elif bar.visible:
		bar.scale.y = fill
	return fill


## The gate hint on the aid lamps' line, to their left: `text`, or nothing
## for "". The licence manager puts it up when the clutch key or an aid
## switch is refused and takes it down again.
func set_gate_hint(text: String) -> void:
	_gate_hint.text = text
	_gate_hint.visible = text != ""


## The licence card: one overlay for the licence book and the theory quiz's
## question cards, `text` on a dark panel in the middle of the screen.
func show_licence_card(text: String) -> void:
	_licence_card.text = text
	_licence_card.visible = true
	_licence_card_back.visible = true


func hide_licence_card() -> void:
	_licence_card.visible = false
	_licence_card_back.visible = false


func licence_card_visible() -> bool:
	return _licence_card.visible


## The mission line under the controls text.
func set_mission_line(text: String, color: Color) -> void:
	_mission_label.text = text
	_mission_label.add_theme_color_override("font_color", color)


## The big banner across the screen (headline in `color`, small print under it).
func show_mission_banner(headline: String, detail: String, color: Color) -> void:
	_mission_banner.text = headline
	_mission_banner.add_theme_color_override("font_color", color)
	_mission_banner_detail.text = detail
	_mission_banner.visible = true
	_mission_banner_detail.visible = true


func hide_mission_banner() -> void:
	_mission_banner.visible = false
	_mission_banner_detail.visible = false
