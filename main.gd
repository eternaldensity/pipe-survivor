extends Node3D
@onready var network : PipeNetwork = $PipeNetwork
@export var straight_section : PackedScene

func _ready() -> void:
	network.add_section(straight_section, {})
	network.add_section(straight_section, { "exit_radius": 6.0 })   # tapers down
	network.add_section(straight_section, { "entry_radius": 6.0, "exit_radius": 6.0, "length": 80.0 })
	network.add_section(straight_section, { "entry_radius": 6.0 })   # widens back out
