# speed_hud.gd  (P3-17 — extracted from vehicle.gd)
class_name SpeedHUD
extends CanvasLayer

@onready var label: Label = $Panel/Label

var vehicle: Vehicle = null

func _ready() -> void:
	if label:
		label.text = "Speed: 0.0"

func _process(_delta: float) -> void:
	if label and vehicle:
		var spd := vehicle.velocity.length()
		label.text = "Speed: %.1f%s" % [spd, "  [REST]" if vehicle.rest_zone_inside else ""]