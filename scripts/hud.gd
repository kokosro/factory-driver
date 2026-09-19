class_name HUD
extends CanvasLayer
## Minimal driving HUD: speed, plus a tach line (engine RPM and gear) so the
## driving feel can be checked. The mission line and banner only show what
## they are handed (see scripts/mission_manager.gd).

## Tach text colour normally and from ArcadeCar.SHIFT_LIGHT_RPM up.
const TACH_COLOR := Color(1, 1, 1, 1)
const TACH_REDLINE_COLOR := Color(1.0, 0.3, 0.2, 1)

@export var car: ArcadeCar

@onready var _speed_label: Label = $SpeedLabel
@onready var _rpm_label: Label = $RpmLabel
@onready var _mission_label: Label = $MissionLabel
@onready var _mission_banner: Label = $MissionBanner
@onready var _mission_banner_detail: Label = $MissionBannerDetail


func _process(_delta: float) -> void:
	if not car:
		return
	var reversing := car.forward_speed < -ArcadeCar.STANDSTILL_SPEED
	var gear := "R  " if reversing else ""
	_speed_label.text = "%s%d km/h" % [gear, roundi(car.speed_kmh)]

	var gear_name := "R" if reversing else ("N" if car.gear == 0 else "G%d" % car.gear)
	if not car.automatic:
		gear_name += " M"
	# Rounded to 50 rpm so the readout does not flicker.
	_rpm_label.text = "%d rpm | %s" % [roundi(car.engine_rpm / 50.0) * 50, gear_name]
	var near_redline := car.engine_rpm >= ArcadeCar.SHIFT_LIGHT_RPM
	_rpm_label.add_theme_color_override("font_color", TACH_REDLINE_COLOR if near_redline else TACH_COLOR)


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
