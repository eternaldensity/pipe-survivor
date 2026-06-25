@tool
# pipe_section.gd
class_name PipeSection
extends Node3D

@onready var entry : Marker3D = $Entry
@onready var exit  : Marker3D = $Exit

const RING_SEGMENTS := 32

func get_tube_properties(world_pos: Vector3) -> Dictionary:
	push_error("get_tube_properties not implemented in " + name)
	return {}


func contains_point(world_pos: Vector3) -> bool:
	push_error("contains_point not implemented in " + name)
	return false
