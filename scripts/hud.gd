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
## THE STUDY's input display (the StudyPanel, bottom left, built in code by
## _build_study_panel): while a lesson runs, every input the scripted driver
## works, live off the car - the steering wheel as a marker on a bar, the
## throttle, brake and clutch pedals as three of the pedal bars above
## (_fill_bar, the same idiom), the gear and the program, the handbrake, the
## clutch pedal's depth, the three aids - the wear readout, the lesson's
## caption, and the event flashes (study_events: a stall, wheel spin, locked
## wheels, the heat, an aid switched, a gear changed). Shown and fed by
## scripts/study.gd; hidden it costs nothing.
## THE ISSUE FLAG (scripts/issue_flagger.gd, made here in _ready: the HUD is
## the one node in both scenes, the pad's and the Ring's, that holds the
## car): the line over the odometer while a session records, and the
## overlay that asks what is wrong once it stops - a caption and a LineEdit
## in the middle of the screen, the tree paused while the driver types (the
## garage's own mechanism: SceneTree.paused, the overlay alone kept
## processing, PROCESS_MODE_ALWAYS in hud.tscn, so its keys reach it), Enter
## files the text, Esc files what is typed so far ("" for nothing), and the
## tree runs on. See _start_flagger for the garage's part in it.
## THE GPS GUIDER (scripts/gps_minimap.gd, made here in _ready too:
## _start_minimap): the minimap in the top-right corner, its key its own.

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

## The mission banner's letters [px]: their size, and the smallest they
## shrink to for a headline too wide for the screen (see show_mission_banner).
const BANNER_FONT_SIZE := 64
const BANNER_MIN_FONT_SIZE := 40

## The driver aids' lamps (SC, TCS, ABS): dim while the aid is on, which is how the
## car starts and nothing to look at; lit in the fuel bar's amber, with OFF
## behind the letters, once it has been switched off.
const AID_ON_COLOR := Color(1, 1, 1, 0.35)
const AID_OFF_COLOR := Color(1.0, 0.7, 0.15, 1)

# --- THE STUDY's input display ------------------------------------------------

## How long an event flash stays up after the last tick it was seen [s].
const STUDY_FLASH_TIME := 1.2

## Slip ratio from which a driven axle reads as spinning, and under which
## (negative: the wheel turns slower than the road) an axle reads as locked:
## the tyre marks' own threshold (TyreMarks.MARK_SLIP_RATIO, 0.35), the slip
## at which a tyre lays rubber - over everything the aids hold a tyre at
## (TCS 0.25, ABS 0.15), so a launch with TCS and a stop with ABS flash
## nothing.
const STUDY_SPIN_SLIP := TyreMarks.MARK_SLIP_RATIO

## Under this road speed a locked wheel is a parked one, not a lockup [m/s].
const STUDY_LOCKUP_MIN_SPEED := 1.0

## The steering bar: how wide [px], and the marker's width [px]; the pedal
## bars: how tall [px] and wide [px].
const STUDY_STEER_BAR_WIDTH := 240.0
const STUDY_STEER_MARKER_WIDTH := 8.0
const STUDY_PEDAL_BAR_HEIGHT := 80.0
const STUDY_PEDAL_BAR_WIDTH := 14.0

const STUDY_PANEL_COLOR := Color(0, 0, 0, 0.55)
const STUDY_TITLE_COLOR := Color(1.0, 0.9, 0.35, 1)
const STUDY_TEXT_COLOR := Color(1, 1, 1, 1)
const STUDY_DIM_TEXT_COLOR := Color(1, 1, 1, 0.6)
const STUDY_BAR_BACK_COLOR := Color(0, 0, 0, 0.45)
const STUDY_STEER_COLOR := Color(1.0, 0.9, 0.35, 1)
const STUDY_THROTTLE_COLOR := Color(0.25, 0.9, 0.35, 1)
const STUDY_BRAKE_COLOR := Color(1, 0.25, 0.2, 1)
const STUDY_CLUTCH_COLOR := Color(0.55, 0.8, 0.95, 1)
const STUDY_EVENT_COLOR := Color(1.0, 0.55, 0.2, 1)

# --- THE ISSUE FLAG ------------------------------------------------------------

## The recording line's text, the id in it; the overlay's caption, the id in
## it; what the caption says on the pad (a recorder recording: the range is
## in a session file) and on the Ring (none: the odometer and the clock).
const ISSUE_LINE_TEXT := "ISSUE %s  recording  -  V stops it and asks what is wrong"
const ISSUE_CAPTION_TEXT := "ISSUE %s  -  what is wrong?   Enter files it, Esc files it as typed   (%s)"
const ISSUE_BOUND_TEXT := "bound to telemetry session %d, %.1f - %.1f s"
const ISSUE_UNBOUND_TEXT := "no telemetry recording here: bound to the odometer, %.1f - %.1f m, and the clock"

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
@onready var _issue_label: Label = $IssueLabel
@onready var _issue_overlay: Control = $IssueOverlay
@onready var _issue_caption: Label = $IssueOverlay/Caption
@onready var _issue_description: LineEdit = $IssueOverlay/Description

## THE ISSUE FLAG's node, made in _ready (_start_flagger); the tests reach it.
var flagger: IssueFlagger

## THE GPS GUIDER's node (scripts/gps_minimap.gd), made in _ready
## (_start_minimap); the tests reach it.
var minimap: GpsMinimap

## The odometer as last written on its label [tenths of a km]; the label's text
## is only made anew when this changes, every 100 m.
var _odometer_shown := -1

# THE STUDY's input display: the nodes _build_study_panel makes, the last
# snapshot the events were judged against, and the flashes up with the
# seconds each has left.
@onready var _study_panel: Control = $StudyPanel
var _study_title: Label
var _study_caption: Label
var _study_steer_marker: ColorRect
var _study_throttle_bar: ColorRect
var _study_brake_bar: ColorRect
var _study_clutch_bar: ColorRect
var _study_gear_label: Label
var _study_event_label: Label
var _study_wear_label: Label
var _study_before: Dictionary = {}
var _study_flashes: Dictionary = {}
var _study_state: Dictionary = {}


func _ready() -> void:
	_build_study_panel()
	_start_flagger()
	_start_minimap()


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
## question cards, `text` on a dark panel in the middle of the screen. In
## hud.tscn: was 20 px letters on a 480 px card (the book's lines wrapped to
## 741 px, off the top and the bottom of a 720 px screen) -> 16 px letters
## on a 600 px card, the book 491 px (the user's report, 2026-09-22 16:15).
func show_licence_card(text: String) -> void:
	_licence_card.text = text
	_licence_card.visible = true
	_licence_card_back.visible = true


func hide_licence_card() -> void:
	_licence_card.visible = false
	_licence_card_back.visible = false


func licence_card_visible() -> bool:
	return _licence_card.visible


## The mission line under the controls text. In hud.tscn it spans the
## screen's width and wraps: was one line as wide as its text, 1273 px
## from x = 24 on a 1280 px screen, its start 7 px under the controls
## text's last line -> wrapped inside the screen, 12 px lower, clear of the
## controls (the user's report, 2026-09-22 16:15).
func set_mission_line(text: String, color: Color) -> void:
	_mission_label.text = text
	_mission_label.add_theme_color_override("font_color", color)


## The big banner across the screen (headline in `color`, small print under it).
func show_mission_banner(headline: String, detail: String, color: Color) -> void:
	_mission_banner.text = headline
	# was: 64 px letters whatever the headline ("LESSON ENDED  DRIVE MODES:
	# SPORT, COMFORT, ECO" 1675 px wide on a 1280 px screen, off both edges)
	# -> the letters shrink until the headline fits the banner's width, never
	# under BANNER_MIN_FONT_SIZE (the user's report, 2026-09-22 16:15).
	_mission_banner.add_theme_font_size_override("font_size", banner_font_size(headline, _mission_banner))
	_mission_banner.add_theme_color_override("font_color", color)
	_mission_banner_detail.text = detail
	_mission_banner.visible = true
	_mission_banner_detail.visible = true


func hide_mission_banner() -> void:
	_mission_banner.visible = false
	_mission_banner_detail.visible = false


## The largest letters, BANNER_FONT_SIZE down to BANNER_MIN_FONT_SIZE two
## pixels at a time, at which `headline` and its outline fit `banner`'s
## width: the banner's own font, measured the way the label lays it out.
static func banner_font_size(headline: String, banner: Label) -> int:
	var font := banner.get_theme_font("font")
	var room := banner.size.x - 2.0 * banner.get_theme_constant("outline_size")
	var size := BANNER_FONT_SIZE
	while size > BANNER_MIN_FONT_SIZE and font.get_string_size(headline, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > room:
		size -= 2
	return size


# =============================================================================
#  THE STUDY's input display
# =============================================================================

## The panel's nodes, under the StudyPanel of hud.tscn: the title and the
## caption on top, the steering bar and the three pedal bars in the middle,
## the gear / handbrake / aids text beside them, the event flash and the
## wear readout at the bottom. Controls only, no assets.
func _build_study_panel() -> void:
	var back := ColorRect.new()
	back.name = "Back"
	back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	back.color = STUDY_PANEL_COLOR
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_study_panel.add_child(back)

	_study_title = _study_label("Title", Vector2(12, 6), Vector2(616, 26), 18, STUDY_TITLE_COLOR)
	# was: 62 px for the caption, two lines - the longest objective (SC ON /
	# OFF's, three lines, 72 px) grew over the steering label -> 72 px, and
	# everything under it 10 px lower, the panel 10 px taller (hud.tscn:
	# 250 px; the user's report, 2026-09-22 16:15).
	_study_caption = _study_label("Caption", Vector2(12, 34), Vector2(616, 72), 15, STUDY_TEXT_COLOR)
	_study_caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	_study_label("SteerLabel", Vector2(12, 114), Vector2(120, 16), 11, STUDY_DIM_TEXT_COLOR).text = "STEERING  left <  > right"
	var steer_back := ColorRect.new()
	steer_back.name = "SteerBarBack"
	steer_back.position = Vector2(12, 132)
	steer_back.size = Vector2(STUDY_STEER_BAR_WIDTH, 12)
	steer_back.color = STUDY_BAR_BACK_COLOR
	steer_back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_study_panel.add_child(steer_back)
	var centre := ColorRect.new()
	centre.name = "Centre"
	centre.position = Vector2(STUDY_STEER_BAR_WIDTH * 0.5 - 1.0, -2)
	centre.size = Vector2(2, 16)
	centre.color = STUDY_DIM_TEXT_COLOR
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	steer_back.add_child(centre)
	_study_steer_marker = ColorRect.new()
	_study_steer_marker.name = "Marker"
	_study_steer_marker.size = Vector2(STUDY_STEER_MARKER_WIDTH, 16)
	_study_steer_marker.position = Vector2((STUDY_STEER_BAR_WIDTH - STUDY_STEER_MARKER_WIDTH) * 0.5, -2)
	_study_steer_marker.color = STUDY_STEER_COLOR
	_study_steer_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	steer_back.add_child(_study_steer_marker)

	_study_throttle_bar = _study_pedal_bar("Throttle", 280.0, "THR", STUDY_THROTTLE_COLOR)
	_study_brake_bar = _study_pedal_bar("Brake", 306.0, "BRK", STUDY_BRAKE_COLOR)
	_study_clutch_bar = _study_pedal_bar("Clutch", 332.0, "CLU", STUDY_CLUTCH_COLOR)

	_study_gear_label = _study_label("GearLabel", Vector2(370, 110), Vector2(260, 90), 15, STUDY_TEXT_COLOR)
	_study_event_label = _study_label("EventLabel", Vector2(12, 206), Vector2(616, 26), 20, STUDY_EVENT_COLOR)
	_study_wear_label = _study_label("WearLabel", Vector2(12, 232), Vector2(616, 16), 11, STUDY_DIM_TEXT_COLOR)


func _study_label(label_name: String, at: Vector2, size: Vector2, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.name = label_name
	label.position = at
	label.size = size
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 4)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_study_panel.add_child(label)
	return label


## One of the study's pedal bars at `x`: the HUD's pedal-bar idiom, a full
## rectangle scaled from its foot (_fill_bar), with its letters under it.
func _study_pedal_bar(bar_name: String, x: float, letters: String, color: Color) -> ColorRect:
	var back := ColorRect.new()
	back.name = bar_name + "BarBack"
	back.position = Vector2(x, 110)
	back.size = Vector2(STUDY_PEDAL_BAR_WIDTH, STUDY_PEDAL_BAR_HEIGHT)
	back.color = STUDY_BAR_BACK_COLOR
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_study_panel.add_child(back)
	var bar := ColorRect.new()
	bar.name = bar_name + "Bar"
	bar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bar.pivot_offset = Vector2(0, STUDY_PEDAL_BAR_HEIGHT)
	bar.color = color
	bar.visible = false
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	back.add_child(bar)
	var label := _study_label(bar_name + "Letters", Vector2(x - 6, 192), Vector2(STUDY_PEDAL_BAR_WIDTH + 12, 14), 10, STUDY_DIM_TEXT_COLOR)
	label.text = letters
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return bar


## Puts the study panel up for a lesson called `title`, everything on it at
## rest and no flash pending.
func show_study_panel(title: String) -> void:
	_study_title.text = "THE STUDY  —  %s" % title
	_study_caption.text = ""
	_study_event_label.text = ""
	_study_before = {}
	_study_flashes = {}
	_study_state = {}
	_study_panel.visible = true


func hide_study_panel() -> void:
	_study_panel.visible = false


func study_panel_visible() -> bool:
	return _study_panel.visible


## The lesson's caption: what the scripted driver is doing right now.
func set_study_caption(text: String) -> void:
	_study_caption.text = text


## One tick of the input display off `target_car`: the bars and the text
## from the car's state, the event flashes from study_events against the
## tick before, each flash kept up STUDY_FLASH_TIME after it was last seen.
func update_study_panel(target_car: ArcadeCar, delta: float) -> void:
	var now := study_snapshot(target_car)
	# The steering marker: +1 (full left lock) at the bar's left end, -1 at
	# its right, centre for straight ahead.
	var travel := (STUDY_STEER_BAR_WIDTH - STUDY_STEER_MARKER_WIDTH) * 0.5
	_study_steer_marker.position.x = travel - clampf(now.steer, -1.0, 1.0) * travel
	_fill_bar(_study_throttle_bar, now.throttle)
	_fill_bar(_study_brake_bar, now.brake)
	_fill_bar(_study_clutch_bar, now.clutch)
	var gear_text := study_gear_text(now)
	_study_gear_label.text = gear_text
	_study_wear_label.text = "wear   clutch %.3f %%   brakes F %.3f R %.3f %%   tyres F %.3f R %.3f %%   engine %.3f %%" % [
		now.clutch_wear * 100.0, now.front_brake_wear * 100.0, now.rear_brake_wear * 100.0,
		now.front_tyre_wear * 100.0, now.rear_tyre_wear * 100.0, now.engine_wear * 100.0,
	]
	for event in study_events(now, _study_before):
		_study_flashes[event] = STUDY_FLASH_TIME
	var shown := PackedStringArray()
	for event: String in _study_flashes.keys():
		_study_flashes[event] -= delta
		if _study_flashes[event] <= 0.0:
			_study_flashes.erase(event)
		else:
			shown.append(event)
	_study_event_label.text = "   ".join(shown)
	_study_before = now
	_study_state = {
		"steer": now.steer, "throttle": now.throttle, "brake": now.brake, "clutch": now.clutch,
		"handbrake": now.handbrake, "gear_text": gear_text, "events": shown,
		"tcs_on": now.tcs_on, "abs_on": now.abs_on, "sc_on": now.sc_on,
	}


## What the panel shows right now (after update_study_panel): steer -1..1,
## the three pedals 0..1, handbrake, the gear text, the flashes up, the aids.
## Empty before the first update.
func study_state() -> Dictionary:
	return _study_state


## The car's state the display and the events are read from, as plain
## numbers: pure, so the events can be judged on any snapshot.
static func study_snapshot(target_car: ArcadeCar) -> Dictionary:
	return {
		"steer": target_car.steer,
		"throttle": target_car.throttle_pedal,
		"brake": target_car.brake_pedal,
		"clutch": target_car.clutch_pedal,
		"handbrake": target_car._handbrake_amount > 0.0,
		"gear": target_car.gear,
		"reverse": target_car.reverse_engaged,
		"automatic": target_car.automatic,
		"gearbox_mode": OdometerStore.GEARBOX_MODES[target_car.gearbox_mode],
		"engine_running": target_car.engine_running,
		"cranking": target_car.cranking(),
		"speed": absf(target_car.forward_speed),
		"front_slip_ratio": target_car.front_slip_ratio,
		"rear_slip_ratio": target_car.rear_slip_ratio,
		"coolant_temp": target_car.coolant_temp,
		"tyre_temp": maxf(target_car.front_tyre_temp, target_car.rear_tyre_temp),
		"brake_temp": maxf(target_car.front_brake_temp, target_car.rear_brake_temp),
		"tcs_on": target_car.tcs_on,
		"abs_on": target_car.abs_on,
		"sc_on": target_car.sc_on,
		"clutch_wear": target_car.clutch_wear,
		"front_brake_wear": target_car.front_brake_wear,
		"rear_brake_wear": target_car.rear_brake_wear,
		"front_tyre_wear": target_car.front_tyre_wear,
		"rear_tyre_wear": target_car.rear_tyre_wear,
		"engine_wear": target_car.engine_wear,
	}


## The gear / handbrake / aids text for a snapshot, three lines.
static func study_gear_text(now: Dictionary) -> String:
	var gear := "R" if now.reverse else ("N" if now.gear == 0 else "G%d" % now.gear)
	var box := "manual" if not now.automatic else "auto %s" % String(now.gearbox_mode).to_upper()
	var engine := "CRANKING" if now.cranking else ("running" if now.engine_running else "STALLED")
	return "GEAR %s   %s   engine %s\nHANDBRAKE %s   clutch pedal %.0f %%\nTCS %s   ABS %s   SC %s" % [
		gear, box, engine, "ON" if now.handbrake else "off", now.clutch * 100.0,
		"on" if now.tcs_on else "OFF", "on" if now.abs_on else "OFF", "on" if now.sc_on else "OFF",
	]


## The events to flash for the snapshot `now`, judged against `before` (the
## tick before; empty for the first tick): pure.
##   STALL          the engine is not running (and not being cranked),
##   RUNNING AGAIN  it caught, having been stopped the tick before,
##   WHEEL SPIN     a driven axle over STUDY_SPIN_SLIP,
##   WHEELS LOCKED  an axle under -STUDY_SPIN_SLIP with the car moving,
##   OVERHEAT       the coolant from the fade line (COOLANT_HOT_FRACTION),
##   BRAKE FADE     a brake from its fade line (BRAKE_HOT_FRACTION),
##   TYRES HOT      a tyre over its window (TYRE_HOT_FRACTION),
##   TCS ON / TCS OFF, ABS ..., SC ...   an aid switched since `before`,
##   SHIFT <gear>   the gear changed since `before`, REVERSE selected.
static func study_events(now: Dictionary, before: Dictionary) -> Array[String]:
	var events: Array[String] = []
	if not now.engine_running and not now.cranking:
		events.append("STALL")
	if now.engine_running and not before.is_empty() and not before.engine_running:
		events.append("RUNNING AGAIN")
	if maxf(now.front_slip_ratio, now.rear_slip_ratio) > STUDY_SPIN_SLIP:
		events.append("WHEEL SPIN")
	if minf(now.front_slip_ratio, now.rear_slip_ratio) < -STUDY_SPIN_SLIP and now.speed > STUDY_LOCKUP_MIN_SPEED:
		events.append("WHEELS LOCKED")
	if now.coolant_temp >= COOLANT_HOT_FRACTION:
		events.append("OVERHEAT")
	if now.brake_temp >= BRAKE_HOT_FRACTION:
		events.append("BRAKE FADE")
	if now.tyre_temp >= TYRE_HOT_FRACTION:
		events.append("TYRES HOT")
	if not before.is_empty():
		for aid: String in ["tcs", "abs", "sc"]:
			var key := aid + "_on"
			if now[key] != before[key]:
				events.append("%s %s" % [aid.to_upper(), "ON" if now[key] else "OFF"])
		if now.reverse != before.reverse and now.reverse:
			events.append("REVERSE")
		elif now.gear != before.gear:
			events.append("SHIFT %s" % ("N" if now.gear == 0 else "G%d" % now.gear))
	return events


# =============================================================================
#  THE ISSUE FLAG
# =============================================================================

## Makes the flagger (the mission manager's idiom for the recorder: new,
## named, a child, the car handed over) and wires the two ends: its start
## puts the line up, its stop takes the line down and puts the overlay up.
## The overlay's LineEdit files on Enter (text_submitted) and on Esc
## (gui_input, the key spent there). THE GARAGE'S PART: the garage polls its
## keys, Tab and Esc, through a pause (it is PROCESS_MODE_ALWAYS, as the
## overlay is), and a key the LineEdit has taken cannot be taken back from
## Input - is_action_just_pressed holds for the frame whatever accept_event
## says - so Esc, and Tab, open the garage over the typing as they do over
## anything idle. The garage is found by name beside the HUD (both scenes
## name it Garage, and the HUD may reach for no node path in a frozen
## scene) and its `opened` files what is typed so far and takes the overlay
## down, the garage holding the pause from then on; no garage (a bare HUD),
## nothing to wire. Esc's own filing happens first, in the LineEdit; the
## garage then comes up on the same key, and Tab or Esc closes it again.
# chosen for the flagging tool: HUD LineEdit overlay (garage row blocked by
# frozen menu_test); Esc files as typed rather than discarding - the garage
# opens on that same Esc, and text typed for a minute is not thrown away for
# a key the overlay cannot keep to itself.
func _start_flagger() -> void:
	flagger = IssueFlagger.new()
	flagger.name = "IssueFlagger"
	flagger.car = car
	add_child(flagger)
	flagger.started.connect(_on_issue_started)
	flagger.stopped.connect(_on_issue_stopped)
	_issue_description.text_submitted.connect(func(text: String) -> void: commit_issue_description(text))
	_issue_description.gui_input.connect(_on_issue_description_input)
	var beside := get_parent()
	var garage: Node = beside.get_node_or_null("Garage") if beside != null else null
	if garage is Garage:
		(garage as Garage).opened.connect(_on_garage_opened_over_issue)


## Makes the minimap (the flagger's idiom: new, named, a child, the car
## handed over); it finds the Ring's RoadBuilder beside the HUD by itself
## in its _ready, and shows its "no map data" line where there is none
## (the pad). The key is its own (GpsMinimap.ACTION, P).
func _start_minimap() -> void:
	minimap = GpsMinimap.new()
	minimap.name = "GpsMinimap"
	minimap.car = car
	add_child(minimap)


func _on_issue_started(id: String) -> void:
	_issue_label.text = ISSUE_LINE_TEXT % id
	_issue_label.visible = true


## The stop: the line down, the overlay up with the record's binding spelt
## out, the box empty and focused, the tree paused for the typing.
func _on_issue_stopped(issue: Dictionary) -> void:
	_issue_label.visible = false
	var bound: String
	if issue.get("binding") == IssueStore.BINDING_TELEMETRY:
		bound = ISSUE_BOUND_TEXT % [int(issue.get("session_id", 0)), float(issue.get("t_start_s", 0.0)), float(issue.get("t_stop_s", 0.0))]
	else:
		bound = ISSUE_UNBOUND_TEXT % [float(issue.get("odometer_start_m", 0.0)), float(issue.get("odometer_stop_m", 0.0))]
	_issue_caption.text = ISSUE_CAPTION_TEXT % [String(issue.get("id", "")), bound]
	_issue_description.text = ""
	_issue_overlay.visible = true
	get_tree().paused = true
	_issue_description.grab_focus()


## Files `text` as the stopped record's description and takes the overlay
## down; the tree runs on unless `keep_paused` (the garage has opened over
## it and holds the pause itself). Nothing with no overlay up.
func commit_issue_description(text: String, keep_paused := false) -> void:
	if not _issue_overlay.visible:
		return
	_issue_overlay.visible = false
	_issue_description.release_focus()
	if not keep_paused:
		get_tree().paused = false
	flagger.describe(text)


## Esc in the box: filed as typed, the key spent here (accept_event: the
## LineEdit's own handling never sees it).
func _on_issue_description_input(event: InputEvent) -> void:
	if event is InputEventKey and (event as InputEventKey).pressed and (event as InputEventKey).keycode == KEY_ESCAPE:
		_issue_description.accept_event()
		commit_issue_description(_issue_description.text)


func _on_garage_opened_over_issue() -> void:
	commit_issue_description(_issue_description.text, true)


func issue_line_visible() -> bool:
	return _issue_label.visible


func issue_line_text() -> String:
	return _issue_label.text


func issue_overlay_visible() -> bool:
	return _issue_overlay.visible


func issue_caption_text() -> String:
	return _issue_caption.text


# =============================================================================
#  The bar legend
# =============================================================================

## What every bar on the HUD, on the study's input display and on the
## garage's CAR page means, with the thresholds its colours turn at (the
## constants above, spelt out): the garage's SETTINGS page shows it.
static func bar_legend() -> String:
	var lines := PackedStringArray()
	lines.append("HUD BARS, bottom right, by the speed:")
	lines.append("  THROTTLE (green, upright) and BRAKE (red, upright): how far the driver's feet really have the two pedals, 0 at the foot")
	lines.append("    to full at the top; a tap is a partial press, a held key gets to the top. In reverse the throttle bar is the brake key's pedal.")
	lines.append("  FUEL (flat, under the pedal bars): the tank, empty to full; amber under %.0f %% of it (reserve), red under %.0f %%." % [FUEL_RESERVE_FRACTION * 100.0, FUEL_LOW_FRACTION * 100.0])
	lines.append("  BATTERY (flat, under FUEL): the charge, flat to a new battery's full; amber under %.0f %% (the starter is getting slow), red under %.0f %%" % [BATTERY_LOW_FRACTION * 100.0, BATTERY_CRITICAL_FRACTION * 100.0])
	lines.append("    (two cranks from the deep-discharge line). A worn battery never fills the bar.")
	lines.append("  COOLANT (flat, under BATTERY): the engine's temperature, 15 C at the left, the operating 90 C two thirds along, full at %.0f C;" % ArcadeCar.coolant_c_of(COOLANT_BAR_FULL))
	lines.append("    blue while cold (under %.0f C: enrichment, the idle hunts), grey warm, red from %.0f C (the power fades), brighter red from %.0f C." % [ArcadeCar.coolant_c_of(COOLANT_COLD_FRACTION), ArcadeCar.coolant_c_of(COOLANT_HOT_FRACTION), ArcadeCar.coolant_c_of(COOLANT_VERY_HOT_FRACTION)])
	lines.append("  TYRES (flat, left of BATTERY, labelled): the hotter axle's tyre temperature, 15 C at the left, full at %.0f C; blue under %.0f C (cold, less grip)," % [ArcadeCar.tyre_c_of(TYRE_BAR_FULL), ArcadeCar.tyre_c_of(TYRE_COLD_FRACTION)])
	lines.append("    grey in the window, red from %.0f C (the grip fades, the rubber wears three times as fast), brighter red from %.0f C." % [ArcadeCar.tyre_c_of(TYRE_HOT_FRACTION), ArcadeCar.tyre_c_of(TYRE_VERY_HOT_FRACTION)])
	lines.append("  BRAKES (flat, under TYRES, labelled): the hotter axle's disc temperature, 15 C at the left, full at %.0f C; grey under the fade line," % ArcadeCar.brake_c_of(BRAKE_BAR_FULL))
	lines.append("    red from %.0f C (the pedal gives less, the pads wear three times as fast), brighter red from %.0f C (red hot). Cold brakes are an empty bar." % [ArcadeCar.brake_c_of(BRAKE_HOT_FRACTION), ArcadeCar.brake_c_of(BRAKE_VERY_HOT_FRACTION)])
	lines.append("  TCS / ABS / SC lamps (over the bars): dim while the aid is on, amber with OFF once it is switched off. ODO over them: the odometer, km.")
	lines.append("")
	lines.append("THE STUDY's input display, bottom left, while a lesson runs:")
	lines.append("  STEERING: a marker on a bar, centre for straight ahead, the left end for full left lock, the right end for full right - the steering wheel's")
	lines.append("    share of its 450 degrees each way, as the driver's hands have it.")
	lines.append("  THR / BRK / CLU: the throttle, brake and clutch pedals, the HUD's pedal bars again, plus the clutch (blue): 0 at the foot, full at the top.")
	lines.append("  GEAR line: the gear (N, G1-G5, R), automatic with its program or manual, the engine running / STALLED / CRANKING; HANDBRAKE on or off,")
	lines.append("    the clutch pedal's depth in %; TCS / ABS / SC on or OFF. The wear line: each component's share of its life used, in %.")
	lines.append("  Flashes: STALL, RUNNING AGAIN, WHEEL SPIN (an axle over %.2f slip, where a tyre lays rubber), WHEELS LOCKED, OVERHEAT, BRAKE FADE, TYRES HOT," % STUDY_SPIN_SLIP)
	lines.append("    an aid switched (TCS OFF ...), SHIFT G2 ..., REVERSE; each stays %.1f s after it was last true." % STUDY_FLASH_TIME)
	lines.append("")
	lines.append("THE GARAGE's CAR page: WEAR bars, one per component (clutch, front and rear brakes, front and rear tyres, engine), empty for new, full for worn out;")
	lines.append("  a component under 1 % of wear is as new to the physics, and the effect steps once a percent from there. FUEL and BATTERY bars there read as the HUD's.")
	return "\n".join(lines)
