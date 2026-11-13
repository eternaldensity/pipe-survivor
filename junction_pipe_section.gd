@tool
# junction_pipe_section.gd  (Phase 2 in progress)
class_name JunctionPipeSection
extends PipeSection

@export var tube_radius    : float = 10.0
@export var trunk_length   : float = 50.0
@export var branch_angle   : float = 30.0   # degrees, half-spread of the two branches
@export var branch_length  : float = 80.0
@export var decision_offset: float = 20.0   # distance along trunk before branches diverge

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
	var decision := Vector3(0.0, 0.0, decision_offset)
	if left:
		left.position = decision + Vector3(-sin(a), 0.0, cos(a)) * branch_length
		left.rotation = Vector3(0.0, -a, 0.0)
	if right:
		right.position = decision + Vector3(sin(a), 0.0, cos(a)) * branch_length
		right.rotation = Vector3(0.0, a, 0.0)

	exits = [exit]
	if left:  exits.append(left)
	if right: exits.append(right)

	await _build_meshes()

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

	# Branches: cubic bezier peeling off from the decision point on the trunk.
	var ang := deg_to_rad(branch_angle)
	var decision := Vector3(0.0, 0.0, decision_offset)
	var dirs := [Vector3(-sin(ang), 0.0, cos(ang)), Vector3(sin(ang), 0.0, cos(ang))]
	for dir in dirs:
		var d: Vector3 = dir
		var end := decision + d * branch_length
		var c := Curve3D.new()
		c.add_point(decision, Vector3.ZERO, Vector3(0.0, 0.0, branch_length * 0.4))
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

func get_entry_radius() -> float:
	return tube_radius

func get_exit_radius(_exit_index: int = 0) -> float:
	return tube_radius

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
	# Clear previously generated branch meshes/collision so editor re-runs and
	# property changes rebuild cleanly.
	for c in get_children():
		if c is MeshInstance3D and c.name.begins_with("BranchMesh"):
			remove_child(c)
			c.free()
	if mesh_instance:
		for c in mesh_instance.get_children():
			mesh_instance.remove_child(c)
			c.free()

	_ensure_curves()
	var union := await _build_union_mesh()
	if union == null:
		return
	if mesh_instance:
		mesh_instance.mesh = union
		mesh_instance.position = Vector3.ZERO
		mesh_instance.basis = Basis.IDENTITY
		var mat := StandardMaterial3D.new()
		mat.vertex_color_use_as_albedo = true
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mesh_instance.material_override = mat

func _build_union_mesh() -> ArrayMesh:
	# Build closed capped tubes and let CSG compute the true union surface. This
	# removes internal walls and produces smooth intersection curves instead of
	# the jagged, tunnelled result of filtering overlapping swept meshes.
	var combiner := CSGCombiner3D.new()
	combiner.name = "CSGUnion"
	combiner.visible = false
	combiner.operation = CSGShape3D.OPERATION_UNION
	for c in _curves:
		var cm := CSGMesh3D.new()
		cm.mesh = _build_tube_mesh(c, tube_radius)
		combiner.add_child(cm)
	add_child(combiner)
	await get_tree().process_frame
	await get_tree().process_frame
	var union: ArrayMesh = null
	for m in combiner.get_meshes():
		if m is ArrayMesh:
			union = m
			break
	remove_child(combiner)
	combiner.free()
	if union == null:
		push_error("Junction CSG union produced no mesh")
		return null
	return _strip_caps_and_color(union)

func _opening_planes() -> Array:
	# [point, outward tangent] for every mouth of the junction.
	var planes: Array = []
	var t0 := _curves[0].sample_baked_with_rotation(0.0)
	planes.append([t0.origin, t0.basis.z])  # entry: outward is -tangent
	var t1 := _curves[0].sample_baked_with_rotation(_curves[0].get_baked_length())
	planes.append([t1.origin, -t1.basis.z])
	for i in range(1, 3):
		var c := _curves[i]
		var te := c.sample_baked_with_rotation(c.get_baked_length())
		planes.append([te.origin, -te.basis.z])
	return planes

func _strip_caps_and_color(src: ArrayMesh) -> ArrayMesh:
	var planes := _opening_planes()
	var colors := [Color(0.7, 0.7, 0.75), Color(0.3, 0.6, 1.0), Color(1.0, 0.5, 0.3)]
	var out_verts := PackedVector3Array()
	var out_norms := PackedVector3Array()
	var out_uvs := PackedVector2Array()
	var out_cols := PackedColorArray()
	var out_idx := PackedInt32Array()

	for surf in range(src.get_surface_count()):
		var arr := src.surface_get_arrays(surf)
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL] if arr[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
		var uvs: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV] if arr[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
		var raw_idx = arr[Mesh.ARRAY_INDEX]
		var idx: PackedInt32Array = raw_idx if raw_idx != null else PackedInt32Array()
		if idx.is_empty():
			idx.resize(verts.size())
			for i in range(verts.size()): idx[i] = i

		for t in range(idx.size() / 3):
			var i0 := idx[t * 3]
			var i1 := idx[t * 3 + 1]
			var i2 := idx[t * 3 + 2]
			var p0 := verts[i0]
			var p1 := verts[i1]
			var p2 := verts[i2]
			var face_n := (p1 - p0).cross(p2 - p0)
			if face_n.length_squared() < 1e-12:
				continue
			face_n = face_n.normalized()
			var centroid := (p0 + p1 + p2) / 3.0

			# Drop the flat cap at each mouth; the attached pipe provides the
			# opening there.
			var is_cap := false
			for pl in planes:
				var pp: Vector3 = pl[0]
				var pn: Vector3 = pl[1]
				if absf((p0 - pp).dot(pn)) < 1.0 \
					and absf((p1 - pp).dot(pn)) < 1.0 \
					and absf((p2 - pp).dot(pn)) < 1.0 \
					and absf(face_n.dot(pn)) > 0.7:
					is_cap = true
					break
			if is_cap:
				continue

			# Colour by nearest branch centreline.
			var best_c := 0
			var best_d := INF
			for i in range(3):
				var off: float = _curves[i].get_closest_offset(centroid)
				var cp: Vector3 = _curves[i].sample_baked(off)
				var d := centroid.distance_to(cp)
				if d < best_d:
					best_d = d
					best_c = i

			for k in [i0, i1, i2]:
				out_idx.append(out_verts.size())
				out_verts.append(verts[k])
				var n: Vector3 = norms[k] if k < norms.size() else face_n
				out_norms.append(n)
				out_uvs.append(uvs[k] if k < uvs.size() else Vector2.ZERO)
				out_cols.append(colors[best_c])

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = out_verts
	arrays[Mesh.ARRAY_NORMAL] = out_norms
	arrays[Mesh.ARRAY_TEX_UV] = out_uvs
	arrays[Mesh.ARRAY_COLOR] = out_cols
	arrays[Mesh.ARRAY_INDEX] = out_idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

func _build_tube_mesh(curve: Curve3D, radius: float) -> ArrayMesh:
	# Closed capped tube with outward-facing normals, suitable for a CSG union.
	var baked_len := curve.get_baked_length()
	var steps: int = max(8, int(baked_len / 5.0))
	var ring_steps := PipeSection.RING_SEGMENTS
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()

	# One ring of shared vertices per step (no duplicated seam vertex), so the
	# surface is a closed manifold and can be used for CSG booleans.
	for i in range(steps + 1):
		var u := float(i) / float(steps)
		var tr := curve.sample_baked_with_rotation(u * baked_len)
		var centre := tr.origin
		var bx := tr.basis.x
		var by := tr.basis.y
		for j in range(ring_steps):
			var v := float(j) / float(ring_steps)
			var ring_a := v * TAU
			var offset := (bx * cos(ring_a) + by * sin(ring_a))
			verts.append(centre + offset * radius)
			normals.append(offset.normalized())
			uvs.append(Vector2(u, v))

	for i in range(steps):
		for j in range(ring_steps):
			var j2 := (j + 1) % ring_steps
			var a := i * ring_steps + j
			var b := (i + 1) * ring_steps + j
			var c := (i + 1) * ring_steps + j2
			var d := i * ring_steps + j2
			indices.append_array([a, b, c, a, c, d])

	# Flat fan caps at both ends so the volume is closed for CSG.
	var tr0 := curve.sample_baked_with_rotation(0.0)
	var tr1 := curve.sample_baked_with_rotation(baked_len)
	var start_ci := verts.size()
	verts.append(tr0.origin)
	normals.append(tr0.basis.z)
	uvs.append(Vector2(0.5, 0.5))
	var end_ci := verts.size()
	verts.append(tr1.origin)
	normals.append(-tr1.basis.z)
	uvs.append(Vector2(0.5, 0.5))
	for j in range(ring_steps):
		var j2 := (j + 1) % ring_steps
		var e0 := steps * ring_steps + j
		var e1 := steps * ring_steps + j2
		indices.append_array([start_ci, j, j2])
		indices.append_array([end_ci, e1, e0])

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
