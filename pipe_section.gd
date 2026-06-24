# pipe_section.gd
class_name PipeSection
extends Node3D

@onready var entry : Marker3D = $Entry
@onready var exit  : Marker3D = $Exit


func get_tube_properties(world_pos: Vector3) -> Dictionary:
	## Returns {axis, origin} in world space for the vehicle's gravity calc.
	## Straight section: axis is our forward, origin is nearest point on centreline.
	## Override this in curved subclasses.
	var fwd    := global_transform.basis.z
	var to_pos := world_pos - global_position
	var along  := to_pos.dot(fwd)
	return {
		"axis":   fwd,
		"origin": global_position + fwd * along
	}
