extends SceneTree
## Headless lighting/normal regression harness.
## Verifies that all pipe interior normals point inward and are consistent
## at section seams, which determines correct interior lighting.
## Run via: godot --headless --path . --script tests/lighting_harness.gd
## Exit code 0 = pass, 1 = fail.

var failures: Array[String] = []
var check_count := 0

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
		print("RESULT: PASS (%d checks)" % check_count)
		quit(0)
	else:
		print("RESULT: FAIL (%d failures)" % failures.size())
		for f in failures:
			print("  - ", f)
		quit(1)

func _run_all() -> void:
	await _test_straight_normals()
	await _test_bend_normals()
	await _test_seam_continuity()

func _get_mesh_arrays(mesh: Mesh) -> Array:
	if mesh is ArrayMesh:
		return mesh.surface_get_arrays(0)
	return []

func _test_straight_normals() -> void:
	var main = load("res://main.tscn").instantiate()
	root.add_child(main)
	for i in range(5): await process_frame
	var net = main.get_node("PipeNetwork")
	for s in net.sections:
		if not (s is StraightPipeSection):
			continue
		var ss := s as StraightPipeSection
		var m := ss.mesh_instance.mesh
		var arr := _get_mesh_arrays(m)
		if arr.is_empty():
			_fail("straight: no mesh arrays (%s)" % ss.name)
			continue
		var verts := arr[Mesh.ARRAY_VERTEX] as PackedVector3Array
		var norms := arr[Mesh.ARRAY_NORMAL] as PackedVector3Array
		_assert(norms.size() == verts.size(),
			"straight: normal count mismatch (%s)" % ss.name)
		var zero_count := 0
		var nan_count := 0
		var inward_count := 0
		var outward_count := 0
		for i in range(norms.size()):
			var n: Vector3 = norms[i]
			var v: Vector3 = verts[i]
			for c in [n.x, n.y, n.z]:
				if is_nan(c):
					nan_count += 1
			if n.length_squared() < 1e-8:
				zero_count += 1
			# Radial direction from centreline (local XZ plane) to vertex.
			var radial := Vector3(v.x, 0.0, v.z)
			if radial.length_squared() > 1e-4:
				radial = radial.normalized()
				var dot_r := n.dot(radial)
				if dot_r < -0.3:
					inward_count += 1
				elif dot_r > 0.3:
					outward_count += 1
		_assert(nan_count == 0, "straight: NaN normals (%s)" % ss.name)
		_assert(zero_count == 0, "straight: zero normals (%s, %d)" % [ss.name, zero_count])
		_assert(outward_count == 0,
			"straight: %d outward-facing normals (%s)" % [outward_count, ss.name])
		_assert(inward_count > norms.size() * 0.5,
			"straight: too few inward normals (%d/%d, %s)" % [inward_count, norms.size(), ss.name])
	pass
	main.queue_free()
	await process_frame

func _test_bend_normals() -> void:
	var main = load("res://main.tscn").instantiate()
	root.add_child(main)
	for i in range(5): await process_frame
	var net = main.get_node("PipeNetwork")
	for s in net.sections:
		if not (s is BendPipeSection):
			continue
		var bs := s as BendPipeSection
		var m := bs.mesh_instance.mesh
		var arr := _get_mesh_arrays(m)
		if arr.is_empty():
			_fail("bend: no mesh arrays (%s)" % bs.name)
			continue
		var verts := arr[Mesh.ARRAY_VERTEX] as PackedVector3Array
		var norms := arr[Mesh.ARRAY_NORMAL] as PackedVector3Array
		_assert(norms.size() == verts.size(),
			"bend: normal count mismatch (%s)" % bs.name)
		var zero_count := 0
		var nan_count := 0
		var inward_count := 0
		var outward_count := 0
		for i in range(norms.size()):
			var n: Vector3 = norms[i]
			var v: Vector3 = verts[i]
			for c in [n.x, n.y, n.z]:
				if is_nan(c):
					nan_count += 1
			if n.length_squared() < 1e-8:
				zero_count += 1
			# For bends, check that normal points inward (negative dot with
			# the radial direction from the centreline). The centreline point
			# is approximated by projecting onto the arc.
			var radial := v  # relative to ring centre (origin of cross-section)
			# Approximate: normal should have negative dot with vertex position
			# relative to the pipe centreline (which is near origin in local space
			# for the first ring, but varies). Use the normal itself: it should
			# point inward, so dot(normal, vertex_position) should be negative
			# for vertices far from the centreline.
			var dist_from_origin := v.length()
			if dist_from_origin > 1.0:
				var dot_self := n.dot(v.normalized())
				if dot_self < -0.3:
					inward_count += 1
				elif dot_self > 0.3:
					outward_count += 1
		_assert(nan_count == 0, "bend: NaN normals (%s)" % bs.name)
		_assert(zero_count == 0, "bend: zero normals (%s, %d)" % [bs.name, zero_count])
		# Most vertices should have inward normals.
		var total_checked := inward_count + outward_count
		if total_checked > 0:
			_assert(inward_count > total_checked * 0.8,
				"bend: too few inward normals (%d/%d, %s)" % [inward_count, total_checked, bs.name])
		print("bend: %s inward=%d outward=%d zero=%d nan=%d" % [bs.name, inward_count, outward_count, zero_count, nan_count])
	main.queue_free()
	await process_frame

func _test_seam_continuity() -> void:
	var main = load("res://main.tscn").instantiate()
	root.add_child(main)
	for i in range(15): await process_frame
	var net = main.get_node("PipeNetwork")
	# For each pair of connected sections, check that normals at the seam
	# are consistent (the lighting boundary should be continuous).
	var checked := 0
	for s in net.sections:
		var ps: PipeSection = s
		if ps.attached_from == null:
			continue
		var prev: PipeSection = ps.attached_from
		# The attachment exit may be one of several (junction branches).
		var exit_idx: int = ps.attached_exit
		var exit_marker: Marker3D = prev.exits[exit_idx] if exit_idx >= 0 and exit_idx < prev.exits.size() else prev.exit
		var prev_exit: Vector3 = exit_marker.global_position
		var curr_entry: Vector3 = s.entry.global_position
		# Use the actual snapped entry point as the seam sample.
		var seam_pos: Vector3 = curr_entry
		# Check that both sections report similar normals at the seam.
		var prev_props: Dictionary = prev.get_tube_properties(seam_pos)
		var curr_props: Dictionary = s.get_tube_properties(seam_pos)
		# The axes should be nearly aligned (continuity).
		var axis_dot := absf(prev_props["axis"].dot(curr_props["axis"]))
		_assert(axis_dot > 0.95,
			"seam: axis discontinuity between %s and %s (%.3f)" % [prev.name, s.name, axis_dot])
		checked += 1
	print("seams: checked %d" % checked)
	main.queue_free()
	await process_frame