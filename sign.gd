@tool
class_name Sign
extends Node3D

@export var text: String = "SIGN"
@export var color: Color = Color(1.0, 1.0, 1.0)
@export var branch_color: Color = Color(0.7, 0.7, 0.75)

@onready var label: Label3D = $Label3D
@onready var indicator: MeshInstance3D = $Indicator

func _ready() -> void:
	if label:
		label.text = text
		label.modulate = color
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	if indicator:
		var mat := StandardMaterial3D.new()
		# Iconography: colour the indicator by sign purpose.
		var c := branch_color
		var lower := text.to_lower()
		if lower.contains("boss"):
			c = Color(1.0, 0.3, 0.3)
		elif lower.contains("rest"):
			c = Color(0.3, 0.9, 0.4)
		elif lower.contains("zone"):
			c = Color(0.4, 0.7, 1.0)
		elif lower.contains("junction"):
			c = Color(1.0, 0.85, 0.3)
		mat.albedo_color = c
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		indicator.material_override = mat