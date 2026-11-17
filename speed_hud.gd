# speed_hud.gd  (P3-17 — extracted from vehicle.gd)
class_name SpeedHUD
extends CanvasLayer

@onready var speed_label: Label = $Panel/VBox/SpeedLabel
@onready var spell_label: Label = $Panel/VBox/SpellLabel

var vehicle: Vehicle = null

func _ready() -> void:
	if speed_label:
		speed_label.text = "Speed: 0.0"
	if spell_label:
		spell_label.text = "Spell: ready"

func _process(_delta: float) -> void:
	if speed_label and vehicle:
		var spd := vehicle.velocity.length()
		speed_label.text = "Speed: %.1f%s" % [spd, "  [REST]" if vehicle.rest_zone_inside else ""]
	if spell_label and vehicle:
		if vehicle._spell_cooldown > 0.0:
			spell_label.text = "Spell: %.1fs" % vehicle._spell_cooldown
		else:
			var preset_name := "Custom"
			if vehicle.selected_preset_index >= 0 and vehicle.selected_preset_index < vehicle._presets.size():
				preset_name = vehicle._presets[vehicle.selected_preset_index].name
			spell_label.text = "Spell: ready (%s)" % preset_name