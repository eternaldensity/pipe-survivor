@tool
class_name Sign
extends Node3D

@export var text: String = "SIGN"
@export var color: Color = Color(1.0, 1.0, 1.0)

@onready var label: Label3D = $Label3D

func _ready() -> void:
	if label:
		label.text = text
		label.modulate = color
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED