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
	# Phase 2: a trident junction (trunk + two branches), each with a continuation.
	var j := network.add_section(junction_section, {"trunk_length": 60.0, "branch_angle": 30.0, "tube_radius": 10.0})

	# Signage before the junction (Phase 3).
	var sign = load("res://Sign.tscn").instantiate()
	sign.text = "JUNCTION AHEAD"
	sign.position = j.entry.global_position - j.global_transform.basis.z * 15.0 + Vector3(0.0, 8.0, 0.0)
	add_child(sign)
	var trunk := network.add_section(straight_section, {"length": 80.0, "entry_radius": 10.0, "exit_radius": 10.0}, j, 0)
	var left  := network.add_section(straight_section, {"length": 80.0, "entry_radius": 10.0, "exit_radius": 10.0}, j, 1)
	var right := network.add_section(straight_section, {"length": 80.0, "entry_radius": 10.0, "exit_radius": 10.0}, j, 2)

	# Trunk continuation: a gentle bend then a long straight.
	network.add_section(bend_section, {"bend_angle": 25.0, "length": 150.0, "tube_radius": 10.0}, trunk, 0)
	network.add_section(straight_section, {"length": 200.0, "entry_radius": 10.0, "exit_radius": 10.0})
	# Rest zone in the first straight pipe (reachable without steering).
	var rest_zone = load("res://RestZone.tscn").instantiate()
	rest_zone.position = Vector3(0.0, 0.0, 0.0)
	rest_zone.rotation = Vector3.ZERO
	add_child(rest_zone)

	# Crafting UI overlay (Phase 3 placeholder).
	var crafting_ui = load("res://CraftingUI.tscn").instantiate()
	add_child(crafting_ui)
	crafting_ui.bind_vehicle($Vehicle)
	# Left branch continuation.
	network.add_section(bend_section, {"bend_angle": 20.0, "length": 120.0, "tube_radius": 10.0}, left, 0)
	network.add_section(straight_section, {"length": 150.0, "entry_radius": 10.0, "exit_radius": 10.0})
	# Right branch continuation (mirrored bend via roll 180).
	network.add_section(bend_section, {"bend_angle": 20.0, "length": 120.0, "tube_radius": 10.0, "roll_angle": 180.0}, right, 0)
	network.add_section(straight_section, {"length": 150.0, "entry_radius": 10.0, "exit_radius": 10.0})
