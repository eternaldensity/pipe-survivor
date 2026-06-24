# pipe_section.gd
class_name PipeSection
extends Node3D

@onready var entry : Marker3D = $Entry
@onready var exit  : Marker3D = $Exit

func get_tube_properties(world_pos: Vector3) -> Dictionary:
	push_error("get_tube_properties not implemented in " + name)
	return {}
