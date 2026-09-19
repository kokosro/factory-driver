extends CanvasLayer
## Minimal driving HUD: a speed readout so the driving feel can be checked.

@export var car: ArcadeCar

@onready var _speed_label: Label = $SpeedLabel


func _process(_delta: float) -> void:
	if not car:
		return
	var gear := "R  " if car.forward_speed < -ArcadeCar.STANDSTILL_SPEED else ""
	_speed_label.text = "%s%d km/h" % [gear, roundi(car.speed_kmh)]
