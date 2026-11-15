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

	_check_seams(net)
	_check_open_ends(net, space, vehicle)

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
				# Godot front faces are clockwise: the cross product points to
				# the back side. Interior visibility needs it to point away from
				# the inward normals (dot < 0); dot >= 0 means the interior is
				# the back face and gets culled.
				if face_n.dot(vn) >= 0.0:
					bad += 1
					mesh_desc = "%s/surf%d" % [mi.name, surf]
	_assert(checked > 0, "no mesh triangles sampled: %s" % sec.name)
	_assert(bad == 0, "%s: %d/%d triangles render their back side to the inside (invisible) [mesh=%s]"
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

## ---------------------------------------------------------------- seams ---

func _check_seams(net) -> void:
	for s in net.sections:
		var sec: PipeSection = s
		if sec.attached_from == null:
			continue
		var parent: PipeSection = sec.attached_from
		var idx: int = sec.attached_exit
		if idx < 0 or idx >= parent.exits.size():
			_fail("seam: %s has invalid exit %d on %s" % [sec.name, idx, parent.name])
			continue
		var exit_marker: Marker3D = parent.exits[idx]
		var r_parent := parent.get_exit_radius(idx)
		var r_child := sec.get_entry_radius()
		_assert(absf(r_parent - r_child) < 0.5,
			"seam radius: %s exit %d r=%.2f -> %s entry r=%.2f"
			% [parent.name, idx, r_parent, sec.name, r_child])

		var ps := _ring_stats(_ring_near(parent, exit_marker, r_parent))
		var cs := _ring_stats(_ring_near(sec, sec.entry, r_child))
		if ps.is_empty():
			_fail("seam: no open ring at %s exit %d (marker %s)"
				% [parent.name, idx, exit_marker.global_position.snapped(Vector3(0.1, 0.1, 0.1))])
			continue
		if cs.is_empty():
			_fail("seam: no open ring at %s entry (marker %s)"
				% [sec.name, sec.entry.global_position.snapped(Vector3(0.1, 0.1, 0.1))])
			continue

		var gap: float = (ps["center"] as Vector3).distance_to(cs["center"] as Vector3)
		_assert(gap < 0.75,
			"seam gap %.2f at %s exit %d -> %s (rings %s / %s)"
			% [gap, parent.name, idx, sec.name,
				(ps["center"] as Vector3).snapped(Vector3(0.1, 0.1, 0.1)),
				(cs["center"] as Vector3).snapped(Vector3(0.1, 0.1, 0.1))])

		var axis_dot := absf((ps["normal"] as Vector3).dot(cs["normal"] as Vector3))
		var angle := rad_to_deg(acos(clampf(axis_dot, -1.0, 1.0)))
		_assert(angle < 5.0,
			"seam plane misalignment %.1f deg at %s exit %d -> %s"
			% [angle, parent.name, idx, sec.name])

		var rdiff := absf(float(ps["radius"]) - float(cs["radius"]))
		_assert(rdiff < 0.75,
			"seam ring radius mismatch %.2f at %s exit %d -> %s (%.2f vs %.2f)"
			% [rdiff, parent.name, idx, sec.name, ps["radius"], cs["radius"]])

## ------------------------------------------------------------ open ends ---

func _check_open_ends(net, space: PhysicsDirectSpaceState3D, vehicle: Vehicle) -> void:
	var used := {}
	for s in net.sections:
		if s.attached_from != null:
			used["%d:%d" % [s.attached_from.get_instance_id(), s.attached_exit]] = true

	for s in net.sections:
		var sec: PipeSection = s
		if sec.attached_from == null:
			_cast_end_probe(space, sec, sec.entry, sec.get_entry_radius(), -1.0, vehicle)
		for i in range(sec.exits.size()):
			var key := "%d:%d" % [sec.get_instance_id(), i]
			if used.has(key):
				continue
			_cast_end_probe(space, sec, sec.exits[i], sec.get_exit_radius(i), 1.0, vehicle)

func _cast_end_probe(space: PhysicsDirectSpaceState3D, sec: PipeSection, marker: Marker3D,
		radius: float, outward_sign: float, vehicle: Vehicle) -> void:
	# Cast from just inside the mouth toward the outside. A capped end hits its
	# cap within a couple of units; an open end lets the ray escape.
	var axis: Vector3 = marker.global_transform.basis.z.normalized() * outward_sign
	var from: Vector3 = marker.global_position - axis * 1.0
	var to: Vector3 = marker.global_position + axis * 2.5
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 1
	query.collide_with_areas = false
	query.exclude = [vehicle.get_rid()]
	var hit := space.intersect_ray(query)
	_assert(not hit.is_empty(),
		"open end: %s at %s (r=%.1f) has no cap"
		% [sec.name, marker.global_position.snapped(Vector3(0.1, 0.1, 0.1)), radius])

## ------------------------------------------------------- mesh utilities ---

## Returns the world-space boundary edges of every surface in a mesh.
## Vertices are spatially welded because junction meshes are emitted with
## per-triangle vertex copies.
func _mesh_boundary_edges(mi: MeshInstance3D) -> Array:
	var edges: Array = []
	var xf := mi.global_transform
	for surf in range(mi.mesh.get_surface_count()):
		var arr := mi.mesh.surface_get_arrays(surf)
		if arr == null:
			continue
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var raw_idx = arr[Mesh.ARRAY_INDEX]
		var idx: PackedInt32Array = raw_idx if raw_idx != null else PackedInt32Array()
		if verts.is_empty():
			continue
		# Weld vertices by position (1/100 unit).
		var weld := {}
		var positions: Array[Vector3] = []
		var remap := PackedInt32Array()
		remap.resize(verts.size())
		for vi in range(verts.size()):
			var p: Vector3 = verts[vi]
			var key := "%d:%d:%d" % [roundi(p.x * 100.0), roundi(p.y * 100.0), roundi(p.z * 100.0)]
			if weld.has(key):
				remap[vi] = weld[key]
			else:
				remap[vi] = positions.size()
				weld[key] = positions.size()
				positions.append(p)

		var tri_count := idx.size() / 3 if idx.size() > 0 else verts.size() / 3
		var counts := {}
		for t in range(tri_count):
			var i0: int
			var i1: int
			var i2: int
			if idx.size() > 0:
				i0 = remap[idx[t * 3]]
				i1 = remap[idx[t * 3 + 1]]
				i2 = remap[idx[t * 3 + 2]]
			else:
				i0 = remap[t * 3]
				i1 = remap[t * 3 + 1]
				i2 = remap[t * 3 + 2]
			for pair in [[i0, i1], [i1, i2], [i2, i0]]:
				var lo: int = mini(pair[0], pair[1])
				var hi: int = maxi(pair[0], pair[1])
				var ekey := "%d:%d" % [lo, hi]
				if counts.has(ekey):
					counts[ekey] += 1
				else:
					counts[ekey] = 1

		for ekey in counts:
			if counts[ekey] != 1:
				continue
			var parts: PackedStringArray = (ekey as String).split(":")
			var a: Vector3 = positions[int(parts[0])]
			var b: Vector3 = positions[int(parts[1])]
			edges.append([xf * a, xf * b])
	return edges

## Boundary vertices that sit on the mouth ring around a marker.
func _ring_near(sec: PipeSection, marker: Marker3D, radius: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	var center := marker.global_position
	var axis := marker.global_transform.basis.z.normalized()
	for child in _all_children(sec):
		if not (child is MeshInstance3D):
			continue
		var mi := child as MeshInstance3D
		if mi.mesh == null or mi.mesh.get_surface_count() == 0:
			continue
		for e in _mesh_boundary_edges(mi):
			for p in e:
				var rel: Vector3 = p - center
				var along := rel.dot(axis)
				var radial := (rel - axis * along).length()
				if absf(along) < 2.5 and radial > radius * 0.35 and radial < radius * 1.65:
					out.append(p)
	return out

## Fit a plane/circle to a ring of points.
func _ring_stats(pts: PackedVector3Array) -> Dictionary:
	if pts.size() < 6:
		return {}
	var c := Vector3.ZERO
	for p in pts:
		c += p
	c /= float(pts.size())

	var farthest := Vector3.ZERO
	var best := -1.0
	for p in pts:
		var d := p.distance_squared_to(c)
		if d > best:
			best = d
			farthest = p - c
	var second := Vector3.ZERO
	var best_cross := 0.0
	for p in pts:
		var v := p - c
		var cr := farthest.cross(v).length()
		if cr > best_cross:
			best_cross = cr
			second = v
	var n := farthest.cross(second)
	if n.length_squared() < 1e-8:
		return {}
	n = n.normalized()

	var rsum := 0.0
	for p in pts:
		rsum += p.distance_to(c)
	return {"center": c, "normal": n, "radius": rsum / float(pts.size())}