# connector_pipe_section.gd  (Phase B — spline tube between two ports)
class_name ConnectorPipeSection
extends PipeSection

@export var end_point: Vector3 = Vector3(0.0, 0.0, 100.0)
@export var end_tangent: Vector3 = Vector3(0.0, 0.0, 1.0)
@export var tube_radius: float = 10.0
@export var samples: int = 24

@onready var mesh_instance: MeshInstance3D = $MeshInstance3D

var _curve: Curve3D = null
var _entry_radius: float = 10.0
var _exit_radius: float = 10.0

func _ready() -> void:
	_entry_radius = tube_radius
	_exit_radius = tube_radius
	_build_curve()
	_build_mesh()
	_place_markers()
	exits = [exit]
	if not Engine.is_editor_hint():
		_build_collision()

func _build_curve() -> void:
	_curve = Curve3D.new()
	var t0 := Vector3(0.0, 0.0, 1.0)
	var t1 := end_tangent
	if t1.length_squared() < 1e-6:
		t1 = Vector3(0.0, 0.0, 1.0)
	t1 = t1.normalized()
	var length := end_point.length()
	if length < 1e-3:
		length = 1.0
	_curve.add_point(Vector3.ZERO, Vector3.ZERO, t0 * (length * 0.4))
	_curve.add_point(end_point, -t1 * (length * 0.4), Vector3.ZERO)

func _build_mesh() -> void:
	if mesh_instance == null:
		return
	if _curve == null:
		return
	var baked_len := _curve.get_baked_length()
	if baked_len < 1e-3:
		return
	var n := maxi(2, samples)
	var frames: Array[Transform3D] = []
	var origins: Array[Vector3] = []
	for i in range(n + 1):
		var off := baked_len * float(i) / float(n)
		var tr := _curve.sample_baked_with_rotation(off)
		frames.append(tr)
		origins.append(tr.origin)

	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for i in range(n + 1):
		var tr: Transform3D = frames[i]
		var xa: Vector3 = tr.basis.x
		var ya: Vector3 = tr.basis.y
		for j in range(PipeSection.RING_SEGMENTS):
			var a := TAU * float(j) / float(PipeSection.RING_SEGMENTS)
			var radial := (xa * cos(a) + ya * sin(a)) * tube_radius
			verts.append(origins[i] + radial)
			norms.append(-radial.normalized())
			uvs.append(Vector2(float(i) / float(n), float(j) / float(PipeSection.RING_SEGMENTS)))

	for i in range(n):
		for j in range(PipeSection.RING_SEGMENTS):
			var j2 := (j + 1) % PipeSection.RING_SEGMENTS
			var a := i * PipeSection.RING_SEGMENTS + j
			var b := i * PipeSection.RING_SEGMENTS + j2
			var c := (i + 1) * PipeSection.RING_SEGMENTS + j
			var d := (i + 1) * PipeSection.RING_SEGMENTS + j2
			# Godot uses clockwise winding for front faces; this order makes the
			# inside (inward normals) the visible front face.
			indices.append_array([a, c, b, a, d, c])

	# Consistency pass: the parallel-transport frame can flip the handedness of
	# a ring, so re-check every triangle and flip any whose geometric normal
	# points the same way as its inward normals (interior would be back-faced).
	for t in range(indices.size() / 3):
		var a := indices[t * 3]
		var b := indices[t * 3 + 1]
		var c := indices[t * 3 + 2]
		var fn := (verts[b] - verts[a]).cross(verts[c] - verts[a])
		if fn.length_squared() < 1e-12:
			continue
		var an := norms[a] + norms[b] + norms[c]
		if an.length_squared() < 1e-12:
			continue
		if fn.dot(an) > 0.0:
			indices[t * 3 + 1] = c
			indices[t * 3 + 2] = b

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh_instance.mesh = mesh

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.6, 0.7, 0.8)
	mat.cull_mode = BaseMaterial3D.CULL_BACK
	mesh_instance.material_override = mat

func _place_markers() -> void:
	if entry == null:
		entry = Marker3D.new()
		entry.name = "Entry"
		add_child(entry)
	if exit == null:
		exit = Marker3D.new()
		exit.name = "Exit"
		add_child(exit)
	entry.transform = Transform3D.IDENTITY
	var flow := end_tangent
	if flow.length_squared() < 1e-6:
		flow = Vector3(0.0, 0.0, 1.0)
	flow = flow.normalized()
	var x := Vector3.UP.cross(flow)
	if x.length_squared() < 1e-4:
		x = Vector3.RIGHT.cross(flow)
	x = x.normalized()
	var y := flow.cross(x).normalized()
	exit.transform = Transform3D(Basis(x, y, flow), end_point)

func _build_collision() -> void:
	if mesh_instance == null or mesh_instance.mesh == null:
		return
	if mesh_instance.get_child_count() == 0:
		mesh_instance.create_trimesh_collision()
	await get_tree().process_frame
	if mesh_instance.get_child_count() == 0:
		return
	var body := mesh_instance.get_child(0) as StaticBody3D
	if body == null or body.get_child_count() == 0:
		return
	var shape := body.get_child(0) as CollisionShape3D
	if shape and shape.shape is ConcavePolygonShape3D:
		(shape.shape as ConcavePolygonShape3D).backface_collision = true

func get_entry_radius() -> float:
	return _entry_radius

func get_exit_radius(_exit_index: int = 0) -> float:
	return _exit_radius

func get_tube_properties(world_pos: Vector3) -> Dictionary:
	if _curve == null:
		return {"axis": global_transform.basis.z, "origin": global_position, "radius": tube_radius}
	var local_pos := to_local(world_pos)
	var off := _curve.get_closest_offset(local_pos)
	var tr := _curve.sample_baked_with_rotation(off)
	var axis := (global_transform.basis * tr.basis.z).normalized()
	var origin := to_global(tr.origin)
	return {"axis": axis, "origin": origin, "radius": tube_radius}

func contains_point(world_pos: Vector3) -> bool:
	if _curve == null:
		return false
	var local_pos := to_local(world_pos)
	var off := _curve.get_closest_offset(local_pos)
	var tr := _curve.sample_baked_with_rotation(off)
	var len := _curve.get_baked_length()
	if off < -2.0 or off > len + 2.0:
		return false
	return local_pos.distance_to(tr.origin) < tube_radius + 2.0