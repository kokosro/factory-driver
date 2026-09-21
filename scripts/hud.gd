class_name HUD
extends CanvasLayer
## Minimal driving HUD: speed, plus a tach line (engine RPM and gear), the two
## pedal bars so the driving feel can be checked, the fuel bar, and a lamp each
## for the three driver aids. The mission line and
## banner only show what they are handed (see scripts/mission_manager.gd).

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
@onready var _tcs_lamp: Label = $TcsLamp
@onready var _abs_lamp: Label = $AbsLamp
@onready var _sc_lamp: Label = $ScLamp


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
	if not car.engine_running:
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


## The pedal bars follow the pedals tick by tick (ArcadeCar.throttle_pedal /
## brake_pedal, what the drivetrain is given): a dab at a key is a bar that
## never gets to the top. The fuel bar follows the tank (ArcadeCar.fuel_fraction).
func _physics_process(_delta: float) -> void:
	if not car:
		return
	set_throttle_bar(car.throttle_pedal)
	set_brake_bar(car.brake_pedal)
	set_fuel_bar(car.fuel_fraction())


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
