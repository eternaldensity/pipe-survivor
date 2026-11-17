# junction_mesh_builder.gd  (P2-11 — extracted CSG junction mesh generation)
class_name JunctionMeshBuilder
extends RefCounted

static var _cache: Dictionary = {}

# Build (or fetch from cache) the junction's stripped, colored mesh.
static func build(tube_radius: float, trunk_length: float, branch_angle: float,
		branch_length: float, decision_offset: float, blend_length: float,
		has_trunk: bool, left_branch: bool, right_branch: bool) -> ArrayMesh:
	var key := _cache_key(tube_radius, trunk_length, branch_angle, branch_length,
		decision_offset, blend_length, has_trunk, left_branch, right_branch)
	if _cache.has(key):
		var cached := _cache[key] as ArrayMesh
		if cached != null:
			return cached
	var mesh := await _build(tube_radius, trunk_length, branch_angle, branch_length,
		decision_offset, blend_length, has_trunk, left_branch, right_branch)
	_cache[key] = mesh
	var disk_path := "user://junction_mesh_v6_%s.res" % key.md5_text()
	ResourceSaver.save(mesh, disk_path)
	return mesh

static func _cache_key(tube_radius: float, trunk_length: float, branch_angle: float,
		branch_length: float, decision_offset: float, blend_length: float,
		has_trunk: bool, left_branch: bool, right_branch: bool) -> String:
	return "v6|%s|%s|%s|%s|%s|%s|%s|%s|%s" % [
		tube_radius, trunk_length, branch_angle, branch_length,
		decision_offset, blend_length, has_trunk, left_branch, right_branch]

static func _build(tube_radius: float, trunk_length: float, branch_angle: float,
		branch_length: float, decision_offset: float, blend_length: float,
		has_trunk: bool, left_branch: bool, right_branch: bool) -> ArrayMesh:
	# Build curves.
	var curves: Array[Curve3D] = _build_curves(tube_radius, trunk_length, branch_angle,
		branch_length, decision_offset, blend_length, has_trunk, left_branch, right_branch)

	# Build CSG union.
	var combiner := CSGCombiner3D.new()
	combiner.operation = CSGShape3D.OPERATION_UNION
	combiner.visible = false

	var ang := deg_to_rad(branch_angle)
	var dirs := [Vector3(-sin(ang), 0.0, cos(ang)), Vector3(sin(ang), 0.0, cos(ang))]

	if has_trunk:
		var trunk := CSGCylinder3D.new()
		trunk.radius = tube_radius
		trunk.height = trunk_length
		trunk.sides = PipeSection.RING_SEGMENTS
		trunk.rotation = Vector3(PI * 0.5, 0.0, 0.0)
		trunk.position = Vector3(0.0, 0.0, trunk_length * 0.5)
		combiner.add_child(trunk)

	var decision := Vector3(0.0, 0.0, decision_offset if has_trunk else 0.0)
	var extra := _branch_extra(tube_radius, branch_angle, decision_offset, blend_length, has_trunk)
	for i in range(2):
		if (i == 0 and not left_branch) or (i == 1 and not right_branch):
			continue
		var d: Vector3 = dirs[i]
		var end: Vector3 = decision + d * branch_length
		var height: float = branch_length + extra
		var b := CSGCylinder3D.new()
		b.radius = tube_radius
		b.height = height
		b.sides = PipeSection.RING_SEGMENTS
		var y := d
		var x := Vector3.UP.cross(y)
		if x.length() < 1e-4:
			x = Vector3.RIGHT.cross(y)
		x = x.normalized()
		var z := x.cross(y).normalized()
		b.basis = Basis(x, y, z)
		b.position = end - d * (height * 0.5)
		combiner.add_child(b)

	# Need a scene tree to build CSG. Create a temporary root in the tree.
	var tree := Engine.get_main_loop() as SceneTree
	var root := Node3D.new()
	if tree and tree.root:
		tree.root.add_child(root)
	root.add_child(combiner)
	# CSG needs two frames to bake.
	if tree:
		await tree.process_frame
		await tree.process_frame

	var union: ArrayMesh = null
	for m in combiner.get_meshes():
		if m is ArrayMesh:
			union = m
			break
	if root.get_parent():
		root.get_parent().remove_child(root)
	root.queue_free()
	combiner.free()

	if union == null:
		return null

	var planes := _opening_planes(curves, has_trunk, left_branch, right_branch, branch_angle, decision_offset, trunk_length)
	var stripped := _strip_caps_and_color(union, planes, curves, tube_radius)
	return stripped

static func _build_curves(tube_radius: float, trunk_length: float, branch_angle: float,
		branch_length: float, decision_offset: float, blend_length: float,
		has_trunk: bool, left_branch: bool, right_branch: bool) -> Array[Curve3D]:
	var curves: Array[Curve3D] = []
	var decision := Vector3(0.0, 0.0, decision_offset if has_trunk else 0.0)
	if has_trunk:
		var trunk := Curve3D.new()
		trunk.add_point(Vector3.ZERO, Vector3.ZERO, Vector3(0.0, 0.0, trunk_length * 0.4))
		trunk.add_point(Vector3(0.0, 0.0, trunk_length), Vector3(0.0, 0.0, -trunk_length * 0.4), Vector3.ZERO)
		curves.append(trunk)
	var ang := deg_to_rad(branch_angle)
	var dirs := [Vector3(-sin(ang), 0.0, cos(ang)), Vector3(sin(ang), 0.0, cos(ang))]
	var extra := _branch_extra(tube_radius, branch_angle, decision_offset, blend_length, has_trunk)
	for i in range(2):
		if (i == 0 and not left_branch) or (i == 1 and not right_branch):
			continue
		var d: Vector3 = dirs[i]
		var end: Vector3 = decision + d * branch_length
		var start: Vector3 = end - d * (branch_length + extra)
		var c := Curve3D.new()
		var l := start.distance_to(end)
		c.add_point(start, Vector3.ZERO, d * (l * 0.4))
		c.add_point(end, -d * (l * 0.4), Vector3.ZERO)
		curves.append(c)
	return curves

static func _branch_extra(tube_radius: float, branch_angle: float, decision_offset: float, blend_length: float, has_trunk: bool) -> float:
	if not has_trunk:
		return 0.0
	var ang := deg_to_rad(branch_angle)
	var max_side := tube_radius * 0.8 / maxf(sin(ang), 0.02)
	var max_z := decision_offset * 0.95 / maxf(cos(ang), 0.02)
	return maxf(0.5, minf(blend_length + tube_radius, minf(max_side, max_z)))

static func _opening_planes(curves: Array[Curve3D], has_trunk: bool, left_branch: bool, right_branch: bool, branch_angle: float, decision_offset: float, trunk_length: float) -> Array:
	var planes: Array = []
	if has_trunk:
		var t0 := curves[0].sample_baked_with_rotation(0.0)
		planes.append([t0.origin, t0.basis.z])
		var t1 := curves[0].sample_baked_with_rotation(curves[0].get_baked_length())
		planes.append([t1.origin, -t1.basis.z])
	var idx := 1 if has_trunk else 0
	for i in range(2):
		if (i == 0 and not left_branch) or (i == 1 and not right_branch):
			continue
		var c := curves[idx]
		var ts := c.sample_baked_with_rotation(0.0)
		planes.append([ts.origin, ts.basis.z])
		var te := c.sample_baked_with_rotation(c.get_baked_length())
		planes.append([te.origin, -te.basis.z])
		idx += 1
	return planes

static func _strip_caps_and_color(src: ArrayMesh, planes: Array, curves: Array[Curve3D], tube_radius: float) -> ArrayMesh:
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

			var best_c := 0
			var best_d := INF
			var best_cp := centroid
			for i in range(curves.size()):
				var off: float = curves[i].get_closest_offset(centroid)
				var cp: Vector3 = curves[i].sample_baked(off)
				var d := centroid.distance_to(cp)
				if d < best_d:
					best_d = d
					best_c = i
					best_cp = cp

			var inward := -face_n
			var radial := centroid - best_cp
			if radial.length_squared() > 1e-8:
				inward = -radial.normalized()
			var flip_winding := face_n.dot(inward) > 0.0
			var order := [i0, i2, i1] if flip_winding else [i0, i1, i2]
			for k in order:
				out_idx.append(out_verts.size())
				out_verts.append(verts[k])
				var nrm: Vector3 = norms[k] if k < norms.size() else face_n
				var out_n := -nrm
				if out_n.length_squared() < 1e-12 or out_n.dot(inward) < 0.2:
					out_n = inward
				out_norms.append(out_n.normalized())
				out_uvs.append(uvs[k] if k < uvs.size() else Vector2.ZERO)
				out_cols.append(colors[best_c] if best_c < colors.size() else Color.WHITE)

	# Final consistency pass.
	for t in range(out_idx.size() / 3):
		var a := out_idx[t * 3]
		var b := out_idx[t * 3 + 1]
		var c := out_idx[t * 3 + 2]
		var fn := (out_verts[b] - out_verts[a]).cross(out_verts[c] - out_verts[a])
		if fn.length_squared() < 1e-12:
			continue
		var an := out_norms[a] + out_norms[b] + out_norms[c]
		if an.length_squared() < 1e-12 or fn.dot(an) > 0.0:
			out_idx[t * 3 + 1] = c
			out_idx[t * 3 + 2] = b

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