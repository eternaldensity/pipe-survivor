extends Node3D
@onready var network : PipeNetwork = $PipeNetwork
@export var straight_section : PackedScene

func _ready() -> void:
	network.add_section(straight_section)
	network.add_section(straight_section)
	network.add_section(straight_section)
