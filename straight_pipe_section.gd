class_name StraightPipeSection
extends PipeSection

@export var entry_radius : float = 10.0
@export var exit_radius  : float = 10.0
@export var length       : float = 100.0

@onready var mesh_instance : MeshInstance3D = $MeshInstance3D

func _ready() -> void:
	# Position markers to match actual length
	entry.position = Vector3(0.0, 0.0, -length / 2.0)
	exit.position  = Vector3(0.0, 0.0,  length / 2.0)
	exits = [exit]

	# Build the cylinder/frustum mesh explicitly. Doing this by hand (rather
	# than using CylinderMesh) guarantees a complete surface, inward normals,
	# and correct winding for interior rendering.
	mesh_instance.mesh = _build_mesh()
	mesh_instance.basis = Basis.IDENTITY
	mesh_instance.position = Vector3.ZERO

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.6462178, 0.9540631, 0.9395212, 1)
	mat.cull_mode = BaseMaterial3D.CULL_BACK
	mesh_instance.material_override = mat

	mesh_instance.create_trimesh_collision()
	await get_tree().process_frame  # let the child node appear
	if mesh_instance.get_child_count() == 0:
		return
	var body  := mesh_instance.get_child(0) as StaticBody3D
	if body == null or body.get_child_count() == 0:
		return
	var shape := body.get_child(0) as CollisionShape3D
	if shape and shape.shape is ConcavePolygonShape3D:
		(shape.shape as ConcavePolygonShape3D).backface_collision = true

func _build_mesh() -> ArrayMesh:
	var ring_steps := PipeSection.RING_SEGMENTS
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()

	var z0 := -length / 2.0
	var z1 :=  length / 2.0
	var r0 := entry_radius
	var r1 := exit_radius
	var drdz := (r1 - r0) / length

	# Two rings (entry and exit), each with ring_steps vertices.
	for ring in range(2):
		var z := z0 if ring == 0 else z1
		var r := r0 if ring == 0 else r1
		for j in range(ring_steps):
			var a := TAU * float(j) / float(ring_steps)
			var c := cos(a)
			var s := sin(a)
			verts.append(Vector3(r * c, r * s, z))
			# Inward normal for a (possibly tapered) cylinder.
			var n := Vector3(-c, -s, drdz).normalized()
			normals.append(n)
			uvs.append(Vector2(float(j) / float(ring_steps), float(ring)))

	var ring_n := ring_steps
	for j in range(ring_steps):
		var j2 := (j + 1) % ring_steps
		var a := j
		var b := ring_n + j
		var c := ring_n + j2
		var d := j2
		# Godot uses clockwise winding for front faces, so the cross product
		# points to the back side. This order makes the inside the front face.
		indices.append_array([a, c, b, a, d, c])

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

func get_entry_radius() -> float:
	return entry_radius

func get_exit_radius(_exit_index: int = 0) -> float:
	return exit_radius

func get_tube_properties(world_pos: Vector3) -> Dictionary:
	# Project world_pos onto the section's central axis
	var fwd      := global_transform.basis.z
	var to_pos   := world_pos - entry.global_position
	var along    := to_pos.dot(fwd)
	var along_c  : float = clampf(along, 0.0, length)
	var t: float = along_c / length

	# Radius at this point along the taper
	var r        := lerpf(entry_radius, exit_radius, t)

	# Nearest point on the centreline
	var origin   : Vector3 = entry.global_position + fwd * along_c

	return {
		"axis":   fwd,
		"origin": origin,
		"radius": r      # vehicle can use this later for e.g. FOV scaling
	}

func contains_point(world_pos: Vector3) -> bool:
	var local_pos := to_local(world_pos)
	var half      := length / 2.0
	if abs(local_pos.z) > half + 2.0:
		return false
	var radial := Vector2(local_pos.x, local_pos.y).length()
	return radial < max(entry_radius, exit_radius) + 2.0