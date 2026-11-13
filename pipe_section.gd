@tool
# pipe_section.gd
class_name PipeSection
extends Node3D

@onready var entry : Marker3D = $Entry
@onready var exit  : Marker3D = $Exit

# Exit markers. Single-exit sections populate this with [exit] in _ready;
# junctions populate it with all of their exit markers.
var exits : Array[Marker3D] = []

# Set by PipeNetwork.add_section when this section is snapped onto a prior exit.
var attached_from : PipeSection = null
var attached_exit : int = -1

const RING_SEGMENTS := 32

func get_entry_radius() -> float:
	return 0.0

func get_exit_radius(_exit_index: int = 0) -> float:
	return 0.0

func get_tube_properties(world_pos: Vector3) -> Dictionary:
	push_error("get_tube_properties not implemented in " + name)
	return {}


func contains_point(world_pos: Vector3) -> bool:
	push_error("contains_point not implemented in " + name)
	return false
