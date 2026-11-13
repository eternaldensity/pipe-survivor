extends Node3D
@onready var network : PipeNetwork = $PipeNetwork
@export var straight_section : PackedScene
@export var bend_section : PackedScene

var junction_section : PackedScene

func _ready() -> void:
	junction_section = load("res://JunctionPipeSection.tscn")
	network.add_section(straight_section, {})
	network.add_section(bend_section, {"bend_angle": 10.0, "roll_angle": 180.0, "length": 300.0})
	network.add_section(straight_section, { "exit_radius": 6.0 })   # tapers down
	network.add_section(straight_section, { "entry_radius": 6.0, "exit_radius": 6.0, "length": 60.0 })
	network.add_section(straight_section, { "entry_radius": 6.0 })   # widens back out
	network.add_section(straight_section, {})
	network.add_section(bend_section, {"bend_angle": 45.0})
	network.add_section(straight_section, { "exit_radius": 20.0, "length": 40.0 })   # rapidly widens
	network.add_section(straight_section, { "entry_radius": 20.0, "exit_radius": 10.0, "length": 200.0 })   # tapers back to junction radius
	# Phase 2: a junction with a side branch (trunk continues straight).
	var j := network.add_section(junction_section, {"trunk_length": 60.0, "branch_angle": 30.0, "tube_radius": 10.0})
	network.add_section(straight_section, {"length": 80.0, "entry_radius": 10.0, "exit_radius": 10.0}, j, 0)   # trunk continuation
	network.add_section(straight_section, {"length": 80.0, "entry_radius": 10.0, "exit_radius": 10.0}, j, 1)   # left branch
