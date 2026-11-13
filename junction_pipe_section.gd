@tool
# junction_pipe_section.gd  (Phase 2 in progress)
class_name JunctionPipeSection
extends PipeSection

@export var tube_radius   : float = 10.0
@export var trunk_length  : float = 50.0
@export var branch_angle  : float = 30.0   # degrees, half-spread of the two branches
@export var branch_length : float = 80.0

@onready var mesh_instance : MeshInstance3D = $MeshInstance3D

# Centreline curves (local space).
var _curves: Array[Curve3D] = []
var _curve_key := Vector3(-1.0, -1.0, -1.0)  # trunk_length, branch_length, branch_angle

func _ensure_curves() -> void:
	var key := Vector3(trunk_length, branch_length, branch_angle)
	if _curves.size() == 3 and key == _curve_key:
		return
	_curve_key = key
	_build_curves()

func _ready() -> void:
	# Entry at origin; trunk continues straight; two branches peel off symmetrically.
	entry.position    = Vector3(0.0, 0.0, 0.0)
	exit.position     = Vector3(0.0, 0.0, trunk_length)
	var left  := get_node_or_null("ExitLeft")  as Marker3D
	var right := get_node_or_null("ExitRight") as Marker3D
	var a := deg_to_rad(branch_angle)
	if left:
		left.position = Vector3(-sin(a) * branch_length, 0.0, cos(a) * branch_length)
		left.rotation = Vector3(0.0, -a, 0.0)
	if right:
		right.position = Vector3(sin(a) * branch_length, 0.0, cos(a) * branch_length)
		right.rotation = Vector3(0.0, a, 0.0)

	exits = [exit]
	if left:  exits.append(left)
	if right: exits.append(right)

	_build_meshes()

	if Engine.is_editor_hint():
		notify_property_list_changed()
		return

	await _build_collisions()

func _build_curves() -> void:
	_curves.clear()
	# Trunk: straight along +Z (with slight handles for a consistent tangent).
	var trunk := Curve3D.new()
	trunk.add_point(Vector3.ZERO, Vector3.ZERO, Vector3(0.0, 0.0, trunk_length * 0.4))
	trunk.add_point(Vector3(0.0, 0.0, trunk_length), Vector3(0.0, 0.0, -trunk_length * 0.4), Vector3.ZERO)
	_curves.append(trunk)

	# Branches: cubic bezier peeling off from +Z to branch direction.
	var ang := deg_to_rad(branch_angle)
	var dirs := [Vector3(-sin(ang), 0.0, cos(ang)), Vector3(sin(ang), 0.0, cos(ang))]
	for dir in dirs:
		var d: Vector3 = dir
		var end := d * branch_length
		var c := Curve3D.new()
		c.add_point(Vector3.ZERO, Vector3.ZERO, Vector3(0.0, 0.0, branch_length * 0.4))
		c.add_point(end, -d * (branch_length * 0.4), Vector3.ZERO)
		_curves.append(c)

func _nearest_curve_point(local_pos: Vector3) -> Dictionary:
	var best_dist := INF
	var best_point := Vector3.ZERO
	var best_tan := Vector3(0.0, 0.0, 1.0)
	for c in _curves:
		var off := c.get_closest_offset(local_pos)
		var tr := c.sample_baked_with_rotation(off)
		var pt := tr.origin
		var d := local_pos.distance_to(pt)
		if d < best_dist:
			best_dist = d
			best_point = pt
			best_tan = -tr.basis.z
	return {"point": best_point, "tangent": best_tan, "dist": best_dist}

func get_tube_properties(world_pos: Vector3) -> Dictionary:
	var local_pos := to_local(world_pos)
	_ensure_curves()
	var info := _nearest_curve_point(local_pos)
	return {
		"axis":   (global_transform.basis * info["tangent"]).normalized(),
		"origin": to_global(info["point"]),
		"radius": tube_radius,
	}

func contains_point(world_pos: Vector3) -> bool:
	var local_pos := to_local(world_pos)
	_ensure_curves()
	var info := _nearest_curve_point(local_pos)
	return info["dist"] < tube_radius + 3.0

func _build_meshes() -> void:
	# Clear previously generated branch mesh instances immediately, otherwise
	# editor re-runs can briefly duplicate names/geometry.
	for c in get_children():
		if c is MeshInstance3D and c.name.begins_with("BranchMesh"):
			remove_child(c)
			c.free()

	_ensure_curves()

	# Trunk: swept along its curve.
	if mesh_instance:
		mesh_instance.mesh = _build_tube_mesh(_curves[0], tube_radius)
		mesh_instance.position = Vector3.ZERO
		mesh_instance.basis = Basis.IDENTITY
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.7, 0.7, 0.75)
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mesh_instance.material_override = mat

	# Branches: swept along their curves.
	var branch_names := ["BranchMeshLeft", "BranchMeshRight"]
	for i in range(2):
		var bmi := MeshInstance3D.new()
		bmi.name = branch_names[i]
		bmi.mesh = _build_tube_mesh(_curves[i + 1], tube_radius)
		var bmat := StandardMaterial3D.new()
		bmat.albedo_color = (Color(0.3, 0.6, 1.0) if i == 0 else Color(1.0, 0.5, 0.3))
		bmat.cull_mode = BaseMaterial3D.CULL_DISABLED
		bmi.material_override = bmat
		add_child(bmi)

func _build_tube_mesh(curve: Curve3D, radius: float) -> ArrayMesh:
	var baked_len := curve.get_baked_length()
	var steps: int = max(8, int(baked_len / 5.0))
	var ring_steps := PipeSection.RING_SEGMENTS
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()

	for i in range(steps + 1):
		var u := float(i) / float(steps)
		var tr := curve.sample_baked_with_rotation(u * baked_len)
		var centre := tr.origin
		var bx := tr.basis.x
		var by := tr.basis.y
		for j in range(ring_steps + 1):
			var v := float(j) / float(ring_steps)
			var ring_a := v * TAU
			var offset := (bx * cos(ring_a) + by * sin(ring_a))
			verts.append(centre + offset * radius)
			normals.append(-offset.normalized())
			uvs.append(Vector2(u, v))

	for i in range(steps):
		for j in range(ring_steps):
			var a := i * (ring_steps + 1) + j
			var b := (i + 1) * (ring_steps + 1) + j
			var c := (i + 1) * (ring_steps + 1) + j + 1
			var d := i * (ring_steps + 1) + j + 1
			indices.append_array([a, b, c, a, c, d])

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

func _build_collisions() -> void:
	var meshes: Array[MeshInstance3D] = [mesh_instance]
	for c in get_children():
		if c is MeshInstance3D and c.name.begins_with("BranchMesh"):
			meshes.append(c)
	for mi in meshes:
		if mi == null or mi.mesh == null:
			continue
		if mi.get_child_count() == 0:
			mi.create_trimesh_collision()
	await get_tree().process_frame
	for mi in meshes:
		if mi == null or mi.get_child_count() == 0:
			continue
		var body := mi.get_child(0) as StaticBody3D
		if body and body.get_child_count() > 0:
			var shape := body.get_child(0) as CollisionShape3D
			if shape and shape.shape is ConcavePolygonShape3D:
				(shape.shape as ConcavePolygonShape3D).backface_collision = true
