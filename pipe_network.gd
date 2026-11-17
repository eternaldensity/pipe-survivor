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
		section.attached_from = prev
		section.attached_exit = from_exit

	sections.append(section)
	return section


## Seal every mouth that has no section attached. This covers the level start,
## dead-end branches, unused junction exits and the far end of the arena, so the
## player never sees an open pipe end leading to the void.
func cap_open_ends() -> void:
	var used := {}
	for s in sections:
		if s.attached_from != null:
			used["%d:%d" % [s.attached_from.get_instance_id(), s.attached_exit]] = true

	for s in sections:
		if s.attached_from == null:
			_add_cap(s, s.entry, s.get_entry_radius(), 1.0)
		for i in range(s.exits.size()):
			var key := "%d:%d" % [s.get_instance_id(), i]
			if used.has(key):
				continue
			_add_cap(s, s.exits[i], s.get_exit_radius(i), -1.0)

func _add_cap(section: PipeSection, marker: Marker3D, radius: float, facing: float) -> void:
	if marker == null or radius <= 0.0:
		return
	var cap := MeshInstance3D.new()
	cap.name = "EndCap"
	cap.mesh = _build_cap_mesh(radius, facing)
	# Marker transforms are local to the section; the cap is a sibling of the
	# marker, so copy the local transform directly.
	cap.transform = marker.transform
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.36, 0.43, 0.45)
	mat.cull_mode = BaseMaterial3D.CULL_BACK
	cap.material_override = mat
	section.add_child(cap)

	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 1
	var col := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = 1.0
	col.shape = shape
	# CylinderShape3D's axis is local Y; rotate it onto the mouth's Z axis.
	col.rotation = Vector3(PI * 0.5, 0.0, 0.0)
	body.add_child(col)
	cap.add_child(body)

func _build_cap_mesh(radius: float, facing: float) -> ArrayMesh:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	var n := Vector3(0.0, 0.0, facing)
	verts.append(Vector3.ZERO)
	normals.append(n)
	var steps := PipeSection.RING_SEGMENTS
	for j in range(steps):
		var a := TAU * float(j) / float(steps)
		verts.append(Vector3(cos(a) * radius, sin(a) * radius, 0.0))
		normals.append(n)
	for j in range(steps):
		var j2 := (j + 1) % steps
		# Godot treats clockwise winding as the front face: [0, j, j2] makes
		# the -Z side front, [0, j2, j] the +Z side.
		if facing < 0.0:
			indices.append_array([0, 1 + j, 1 + j2])
		else:
			indices.append_array([0, 1 + j2, 1 + j])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func get_section_at(world_pos: Vector3) -> PipeSection:
	if sections.is_empty():
		return null
	# Hand off out of a junction when the vehicle is near one of its exit
	# markers AND the downstream section actually contains the point.
	if current_section != null and current_section is JunctionPipeSection:
		var j := current_section as JunctionPipeSection
		for s in sections:
			if s == current_section or not (s is PipeSection):
				continue
			var ps := s as PipeSection
			if ps.attached_from != j:
				continue
			if s.entry.global_position.distance_to(world_pos) < 15.0 and s.contains_point(world_pos):
				current_section = s
				return s
	# Stick with current section until we're clearly outside it
	if current_section != null and current_section is PipeSection and current_section.contains_point(world_pos):
		return current_section
	# Then look for a new one
	for s in sections:
		if not (s is PipeSection):
			continue
		if s.contains_point(world_pos):
			current_section = s
			return s
	# Fall back to the section with the nearest entry/exit marker.
	var best      : PipeSection = null
	var best_dist := INF
	for s in sections:
		if not (s is PipeSection):
			continue
		var ps := s as PipeSection
		var d := world_pos.distance_squared_to(ps.entry.global_position)
		for e in ps.exits:
			d = minf(d, world_pos.distance_squared_to(e.global_position))
		d = minf(d, world_pos.distance_squared_to(ps.exit.global_position))
		if d < best_dist:
			best_dist = d
			best      = ps
	if best == null:
		current_section = best
		return best
	current_section = best
	return best