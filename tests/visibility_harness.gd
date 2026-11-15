extends SceneTree
## Headless pipe visibility harness.
## Verifies that every pipe section:
##   - has a non-empty mesh,
##   - has consistent triangle winding vs. its (inward) normals, so the wall is
##     actually rendered from inside under back-face culling, and
##   - encloses its centreline (radial rays hit the pipe wall).
## Run via: tests/run_visibility.sh

var failures: Array[String] = []
var check_count := 0
var ray_count := 0

const RAYS := 16

func _fail(msg: String) -> void:
	failures.append(msg)
	print("FAIL: ", msg)

func _assert(cond: bool, msg: String) -> void:
	check_count += 1
	if not cond:
		_fail(msg)

func _init() -> void:
	await _run_all()
	if failures.is_empty():
		print("RESULT: PASS (%d checks, %d rays)" % [check_count, ray_count])
		quit(0)
	else:
		print("RESULT: FAIL (%d failures, %d rays)" % [failures.size(), ray_count])
		for f in failures:
			print("  - ", f)
		quit(1)

func _run_all() -> void:
	var main = load("res://main.tscn").instantiate()
	root.add_child(main)
	for i in range(20): await process_frame

	var net = main.get_node("PipeNetwork")
	var vehicle = main.get_node("Vehicle")
	var space: PhysicsDirectSpaceState3D = main.get_world_3d().direct_space_state

	_assert(net.sections.size() > 0, "no sections generated")

	for s in net.sections:
		var sec: PipeSection = s
		_check_section_mesh(sec)
		_check_mesh_winding(sec)
		var samples := _sample_centreline(sec)
		_assert(samples.size() > 0, "no centreline samples for %s" % sec.name)
		for sample in samples:
			_cast_ring(space, sec, sample, vehicle)

	print("sections: %d" % net.sections.size())
	main.queue_free()
	await process_frame

func _check_section_mesh(sec: PipeSection) -> void:
	var found := false
	for child in _all_children(sec):
		if child is MeshInstance3D:
			var mi := child as MeshInstance3D
			if mi.mesh != null and mi.mesh.get_surface_count() > 0:
				found = true
				break
	_assert(found, "section has no visible mesh: %s (%s)" % [sec.name, sec.get_class()])

func _check_mesh_winding(sec: PipeSection) -> void:
	# Rendering visibility is decided by triangle winding (cull mode), not by
	# the vertex normals. A triangle whose geometric normal points opposite to
	# its vertex normals renders its unlit/back side toward the inside, i.e.
	# the pipe wall is invisible from inside. Check every distinct material
	# surface so a section cannot silently mix inward and outward geometry.
	var checked := 0
	var bad := 0
	var mesh_desc := ""
	for child in _all_children(sec):
		if not (child is MeshInstance3D):
			continue
		var mi := child as MeshInstance3D
		if mi.mesh == null:
			continue
		# Winding is a property of the mesh itself; a rigid transform cannot
		# change which side is culled. Check in local space to avoid losing
		# precision on tiny seam triangles once translated far from the origin.
		var mirrored := mi.global_transform.basis.determinant() < 0.0
		_assert(not mirrored, "%s: mesh has a mirrored transform" % sec.name)
		for surf in range(mi.mesh.get_surface_count()):
			var arr := mi.mesh.surface_get_arrays(surf)
			if arr == null:
				continue
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var normals = arr[Mesh.ARRAY_NORMAL]
			if normals == null or (normals as PackedVector3Array).is_empty():
				continue
			var raw_idx = arr[Mesh.ARRAY_INDEX]
			var idx: PackedInt32Array = raw_idx if raw_idx != null else PackedInt32Array()
			var tri_count := idx.size() / 3 if idx.size() > 0 else verts.size() / 3
			if tri_count == 0:
				continue
			# Sample up to 96 triangles per surface, always including the first.
			var step := maxi(1, tri_count / 96)
			for t in range(0, tri_count, step):
				var i0: int
				var i1: int
				var i2: int
				if idx.size() > 0:
					i0 = idx[t * 3]
					i1 = idx[t * 3 + 1]
					i2 = idx[t * 3 + 2]
				else:
					i0 = t * 3
					i1 = t * 3 + 1
					i2 = t * 3 + 2
				var a := verts[i0]
				var b := verts[i1]
				var c := verts[i2]
				var face_n := (b - a).cross(c - a)
				if face_n.length_squared() < 1e-10:
					continue
				face_n = face_n.normalized()
				var vn := (normals as PackedVector3Array)[i0] \
					+ (normals as PackedVector3Array)[i1] \
					+ (normals as PackedVector3Array)[i2]
				if vn.length_squared() < 1e-10:
					continue
				vn = vn.normalized()
				checked += 1
				if face_n.dot(vn) <= 0.0:
					bad += 1
					mesh_desc = "%s/surf%d" % [mi.name, surf]
	_assert(checked > 0, "no mesh triangles sampled: %s" % sec.name)
	_assert(bad == 0, "%s: %d/%d triangles wound opposite their normals (invisible from inside) [mesh=%s]"
		% [sec.name, bad, checked, mesh_desc])

func _all_children(node: Node) -> Array[Node]:
	var out: Array[Node] = []
	for c in node.get_children():
		out.append(c)
		out.append_array(_all_children(c))
	return out

func _sample_centreline(sec: PipeSection) -> Array:
	if sec is JunctionPipeSection:
		return _sample_junction(sec as JunctionPipeSection)
	if sec is BendPipeSection:
		return _sample_bend(sec as BendPipeSection)
	# Straight, RestZone, BossArena: lerp entry -> exit.
	var out := []
	var a := sec.entry.global_position
	var b := sec.exit.global_position
	# Skip the exact endpoints to avoid seam-edge raycast artifacts.
	for k in range(1, 6):
		out.append(a.lerp(b, float(k) / 6.0))
	return out

func _sample_bend(bs: BendPipeSection) -> Array:
	var out := []
	var r: float = bs._bend_radius
	var ang: float = bs._angle_rad
	var roll := deg_to_rad(bs.roll_angle)
	var roll_basis := Basis(Vector3(0, 0, 1), roll)
	for k in range(1, 6):
		var a: float = float(k) / 6.0 * ang
		var lp := roll_basis * Vector3(r * (1.0 - cos(a)), 0.0, r * sin(a))
		out.append(bs.to_global(lp))
	return out

func _sample_junction(js: JunctionPipeSection) -> Array:
	var out := []
	js._ensure_curves()
	for c in js._curves:
		var bl: float = c.get_baked_length()
		for k in range(1, 4):
			var off: float = bl * float(k) / 4.0
			var tr := c.sample_baked_with_rotation(off)
			out.append(js.to_global(tr.origin))
	return out

func _cast_ring(space: PhysicsDirectSpaceState3D, sec: PipeSection, origin: Vector3, vehicle: Vehicle) -> void:
	var props := sec.get_tube_properties(origin)
	var axis: Vector3 = props["axis"]
	var radius: float = props["radius"]
	if axis.length_squared() < 1e-4:
		_fail("degenerate axis in %s" % sec.name)
		return
	axis = axis.normalized()
	# Build a basis perpendicular to the axis.
	var up := Vector3.UP
	if absf(axis.dot(up)) > 0.99:
		up = Vector3.RIGHT
	var u := axis.cross(up).normalized()
	var v := axis.cross(u).normalized()

	# Junction tubes overlap; allow a looser hit distance there.
	var max_dist: float = radius + 3.0
	if sec is JunctionPipeSection:
		max_dist = radius + 40.0

	for i in range(RAYS):
		# Offset by half a ring segment so rays don't pass exactly through
		# shared vertices, which can miss both adjacent triangles.
		var angle := TAU * (float(i) + 0.5) / float(RAYS)
		var dir := (u * cos(angle) + v * sin(angle)).normalized()
		var from := origin
		var to := origin + dir * max_dist
		var query := PhysicsRayQueryParameters3D.create(from, to)
		query.collision_mask = 1
		query.collide_with_areas = false
		query.exclude = [vehicle.get_rid()]
		var hit := space.intersect_ray(query)
		ray_count += 1
		if hit.is_empty():
			# Junction holes may lead to a tube that only starts further out;
			# retry with a much longer ray before declaring a miss.
			if sec is JunctionPipeSection:
				var far := PhysicsRayQueryParameters3D.create(from, origin + dir * (radius + 120.0))
				far.collision_mask = 1
				far.collide_with_areas = false
				far.exclude = [vehicle.get_rid()]
				var far_hit := space.intersect_ray(far)
				if not far_hit.is_empty():
					continue
			_fail("ray miss in %s (%s, r=%.1f) at %s dir %s" % [sec.name, sec.get_class(), radius, origin.snapped(Vector3(0.1, 0.1, 0.1)), dir.snapped(Vector3(0.01, 0.01, 0.01))])
			return