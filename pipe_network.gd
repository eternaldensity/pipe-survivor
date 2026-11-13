# pipe_network.gd
class_name PipeNetwork
extends Node3D

var sections : Array[PipeSection] = []
var current_section : PipeSection = null

func add_section(packed: PackedScene, props: Dictionary = {}, from_section: PipeSection = null, from_exit: int = 0) -> PipeSection:
	var section := packed.instantiate() as PipeSection
	
	# Apply overrides before _ready runs positioning
	for key in props:
		section.set(key, props[key])
	add_child(section)

	if sections.is_empty() and from_section == null:
		# First section — place at world origin, no alignment needed
		section.global_transform = Transform3D.IDENTITY
	else:
		var prev: PipeSection = from_section if from_section != null else sections.back()
		# Align new section's Entry onto the chosen exit of the previous section.
		var exit_marker: Marker3D = prev.exits[from_exit] if from_exit < prev.exits.size() else prev.exit
		var exit_T     := exit_marker.global_transform
		var entry_local := section.entry.transform   # local to the section
		section.global_transform = exit_T * entry_local.affine_inverse()

	sections.append(section)
	return section


func get_section_at(world_pos: Vector3) -> PipeSection:
	if sections.is_empty():
		return null
	# Stick with current section until we're clearly outside it
	if current_section != null and current_section.contains_point(world_pos):
		return current_section
	# Then look for a new one
	for s in sections:
		if s.contains_point(world_pos):
			current_section = s
			return s
	# Fall back to the section with the nearest entry/exit marker.
	var best      : PipeSection = null
	var best_dist := INF
	for s in sections:
		var d := world_pos.distance_squared_to(s.entry.global_position)
		for e in s.exits:
			d = minf(d, world_pos.distance_squared_to(e.global_position))
		d = minf(d, world_pos.distance_squared_to(s.exit.global_position))
		if d < best_dist:
			best_dist = d
			best      = s
	current_section = best
	return best
