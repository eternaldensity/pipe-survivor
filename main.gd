extends Node3D
@onready var network : PipeNetwork = $PipeNetwork
@export var straight_section : PackedScene
@export var bend_section : PackedScene

func _ready() -> void:
	network.add_section(straight_section, {})
	network.add_section(bend_section, {"bend_angle": 10.0, "roll_angle": 180.0, "length": 300.0})
	network.add_section(straight_section, { "exit_radius": 6.0 })   # tapers down
	network.add_section(straight_section, { "entry_radius": 6.0, "exit_radius": 6.0, "length": 60.0 })
	network.add_section(straight_section, { "entry_radius": 6.0 })   # widens back out
	network.add_section(straight_section, {})
	network.add_section(bend_section, {"bend_angle": 45.0})
	network.add_section(straight_section, { "exit_radius": 10.0, "length": 40.0 })   # rapidly widens
	network.add_section(straight_section, { "entry_radius": 10.0, "exit_radius": 20.0, "length": 200.0 })
