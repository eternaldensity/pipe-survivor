# pipe_network.gd
class_name PipeNetwork
extends Node3D

var sections : Array[PipeSection] = []


func add_section(packed: PackedScene, props: Dictionary = {}) -> PipeSection:
	var section := packed.instantiate() as PipeSection
	
	# Apply overrides before _ready runs positioning
	for key in props:
		section.set(key, props[key])
	add_child(section)

	if sections.is_empty():
		# First section — place at world origin, no alignment needed
		section.global_transform = Transform3D.IDENTITY
	else:
		# Align new section's Entry onto previous section's Exit.
		# We want: new_section.entry.global_transform == prev.exit.global_transform
		# So:      new_section.global_transform = exit_T * entry_local_T.inverse()
		var prev:PipeSection = sections.back()
		var exit_T     := prev.exit.global_transform
		var entry_local := section.entry.transform   # local to the section
		section.global_transform = exit_T * entry_local.affine_inverse()

	sections.append(section)
	return section


# In PipeNetwork
var current_section : PipeSection = null

func get_section_at(world_pos: Vector3) -> PipeSection:
	# Stick with current section until we're clearly outside it
	if current_section != null and current_section.contains_point(world_pos):
		return current_section
	# Then look for a new one
	for s in sections:
		if s.contains_point(world_pos):
			current_section = s
			return s
	# Fall back to nearest midpoint
	var best      : PipeSection = null
	var best_dist := INF
	for s in sections:
		var mid  := (s.entry.global_position + s.exit.global_position) * 0.5
		var dist := world_pos.distance_squared_to(mid)
		if dist < best_dist:
			best_dist = dist
			best      = s
	current_section = best
	return best
