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
		mat.albedo_color = branch_color
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		indicator.material_override = mat