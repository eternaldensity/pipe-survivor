@tool
# junction_pipe_section.gd  (Phase 2 refinements)
class_name JunctionPipeSection
extends PipeSection

@export var tube_radius    : float = 10.0
@export var trunk_length   : float = 60.0
@export var branch_angle   : float = 30.0   # degrees, half-spread of the two branches
@export var branch_length  : float = 80.0
@export var decision_offset: float = 20.0   # distance along trunk before branches diverge
@export var blend_length: float = 0.0       # length of the transition zone before the decision point (0 = abrupt)
@export var has_trunk      : bool = true    # include a straight-ahead trunk
@export var left_branch    : bool = true    # include a left-side branch
@export var right_branch   : bool = true    # include a right-side branch

@onready var mesh_instance : MeshInstance3D = $MeshInstance3D

# Centreline curves (local space).
var _curves: Array[Curve3D] = []
var _curve_key := Vector3(-1.0, -1.0, -1.0)  # trunk_length, branch_length, branch_angle + flags packed into z via sign
var _flags_key := Vector3i(0, 0, 0)

# Static mesh cache keyed by junction parameters.
static var _mesh_cache: Dictionary = {}

func _ensure_curves() -> void:
	var key := Vector3(trunk_length, branch_length, branch_angle)
	var fkey := Vector3i(int(has_trunk), int(left_branch), int(right_branch))
	if _curves.size() > 0 and key == _curve_key and fkey == _flags_key:
		return
	_curve_key = key
	_flags_key = fkey
	_build_curves()

func _ready() -> void:
	# Clear any stale generated collision children (editor re-runs).
	if mesh_instance:
		for c in mesh_instance.get_children():
			mesh_instance.remove_child(c)
			c.free()

	_update_markers()
	_ensure_curves()

	_build_meshes()

	if Engine.is_editor_hint():
		notify_property_list_changed()
		return

	await _build_collisions()

func _update_markers() -> void:

	var has_branch := left_branch or right_branch
	var start_z: float = decision_offset if has_trunk else 0.0
	var start := Vector3(0.0, 0.0, start_z)

	# Primary exit = trunk (if present) else first enabled branch.
	if has_trunk:
		entry.position = Vector3.ZERO
		exit.position = Vector3(0.0, 0.0, trunk_length)
		exit.rotation = Vector3.ZERO
	else:
		entry.position = Vector3.ZERO
		exit.position = Vector3.ZERO
		exit.rotation = Vector3.ZERO

	var left := get_node_or_null("ExitLeft") as Marker3D
	var right := get_node_or_null("ExitRight") as Marker3D
	var a := deg_to_rad(branch_angle)
	var dirs := [Vector3(-sin(a), 0.0, cos(a)), Vector3(sin(a), 0.0, cos(a))]
	if left:
		if left_branch:
			left.position = start + dirs[0] * branch_length
			left.rotation = Vector3(0.0, -a, 0.0)
			left.visible = true
		else:
			left.visible = false
	if right:
		if right_branch:
			right.position = start + dirs[1] * branch_length
			right.rotation = Vector3(0.0, a, 0.0)
			right.visible = true
		else:
			right.visible = false

	# Rebuild exits array for enabled paths.
	exits.clear()
	if has_trunk:
		exits.append(exit)
	if left_branch and left:
		exits.append(left)
	if right_branch and right:
		exits.append(right)
	# Fallback: if no exits enabled, keep the trunk exit.
	if exits.is_empty() and exit:
		exits.append(exit)


func _build_curves() -> void:
	_curves.clear()
	var has_branch := left_branch or right_branch
	var start_z: float = decision_offset if has_trunk else 0.0
	var start := Vector3(0.0, 0.0, start_z)

	# Trunk curve.
	if has_trunk:
		var trunk := Curve3D.new()
		trunk.add_point(Vector3.ZERO, Vector3.ZERO, Vector3(0.0, 0.0, trunk_length * 0.4))
		trunk.add_point(Vector3(0.0, 0.0, trunk_length), Vector3(0.0, 0.0, -trunk_length * 0.4), Vector3.ZERO)
		_curves.append(trunk)

	# Branch curves. Start inside the trunk (decision_offset - half radius) so
	# the union carves a clean hole; leave at the branch angle immediately.
	var ang := deg_to_rad(branch_angle)
	var decision := Vector3(0.0, 0.0, decision_offset)
	var dirs := [Vector3(-sin(ang), 0.0, cos(ang)), Vector3(sin(ang), 0.0, cos(ang))]
	var blend_start_z: float = maxf(0.0, decision_offset - blend_length) if has_trunk else 0.0
	var branch_origin: Vector3 = Vector3(0.0, 0.0, blend_start_z) if has_trunk else Vector3.ZERO
	if left_branch:
		var end: Vector3 = decision + dirs[0] * branch_length
		var c := Curve3D.new()
		c.add_point(branch_origin, Vector3.ZERO, dirs[0] * (branch_length * 0.4))
		c.add_point(end, -dirs[0] * (branch_length * 0.4), Vector3.ZERO)
		_curves.append(c)
	if right_branch:
		var end: Vector3 = decision + dirs[1] * branch_length
		var c := Curve3D.new()
		c.add_point(branch_origin, Vector3.ZERO, dirs[1] * (branch_length * 0.4))
		c.add_point(end, -dirs[1] * (branch_length * 0.4), Vector3.ZERO)
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
	if _curves.is_empty():
		return {"axis": global_transform.basis.z, "origin": global_position, "radius": tube_radius}
	var info := _nearest_curve_point(local_pos)
	return {
		"axis":   (global_transform.basis * info["tangent"]).normalized(),
		"origin": to_global(info["point"]),
		"radius": tube_radius,
	}

func contains_point(world_pos: Vector3) -> bool:
	var local_pos := to_local(world_pos)
	_ensure_curves()
	if _curves.is_empty():
		return false
	var best_dist := INF
	var best_curve: Curve3D = null
	var best_off := 0.0
	for c in _curves:
		var off := c.get_closest_offset(local_pos)
		var tr := c.sample_baked_with_rotation(off)
		var d := local_pos.distance_to(tr.origin)
		if d < best_dist:
			best_dist = d
			best_curve = c
			best_off = off
	if best_curve == null:
		return false
	if best_dist > tube_radius + 3.0:
		return false
	# Reject points that have clearly passed the end of the nearest curve so
	# the vehicle hands off to the attached section at the exit.
	var end_pt := best_curve.sample_baked(best_curve.get_baked_length())
	var tangent := -best_curve.sample_baked_with_rotation(best_curve.get_baked_length()).basis.z
	if best_off >= best_curve.get_baked_length() - 0.5 \
		and (local_pos - end_pt).dot(tangent) > 1.0:
		return false
	return true

func _opening_planes() -> Array:
	var planes: Array = []
	# Trunk caps.
	if has_trunk:
		var t0 := _curves[0].sample_baked_with_rotation(0.0)
		planes.append([t0.origin, t0.basis.z])
		var t1 := _curves[0].sample_baked_with_rotation(_curves[0].get_baked_length())
		planes.append([t1.origin, -t1.basis.z])
	# Branch caps + branch-start caps.
	var idx := 1 if has_trunk else 0
	for i in range(2):
		if (i == 0 and not left_branch) or (i == 1 and not right_branch):
			continue
		var c := _curves[idx]
		var ts := c.sample_baked_with_rotation(0.0)
		planes.append([ts.origin, ts.basis.z])
		var te := c.sample_baked_with_rotation(c.get_baked_length())
		planes.append([te.origin, -te.basis.z])
		idx += 1
	return planes

func _cache_key() -> String:
	return "%s|%s|%s|%s|%s|%s|%s|%s|%s" % [
		tube_radius, trunk_length, branch_angle, branch_length,
		decision_offset, blend_length, has_trunk, left_branch, right_branch]

func _build_meshes() -> void:
	# Clear previously generated collision children.
	if mesh_instance:
		for c in mesh_instance.get_children():
			mesh_instance.remove_child(c)
			c.free()

	_ensure_curves()

	# If no paths are enabled, nothing to build.
	if _curves.is_empty():
		if mesh_instance:
			mesh_instance.mesh = null
		return

	# Check cache.
	var key := _cache_key()
	if _mesh_cache.has(key):
		if mesh_instance:
			mesh_instance.mesh = _mesh_cache[key]
			mesh_instance.position = Vector3.ZERO
			mesh_instance.basis = Basis.IDENTITY
		return

	# Build one CSG cylinder per enabled path.
	var combiner := CSGCombiner3D.new()
	combiner.name = "CSGUnion"
	combiner.visible = false
	combiner.operation = CSGShape3D.OPERATION_UNION

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

	var decision := Vector3(0.0, 0.0, decision_offset)
	var blend_start_z: float = maxf(0.0, decision_offset - blend_length) if has_trunk else 0.0
	var start := Vector3(0.0, 0.0, blend_start_z)
	for i in range(2):
		if (i == 0 and not left_branch) or (i == 1 and not right_branch):
			continue
		var d: Vector3 = dirs[i]
		var origin: Vector3 = start
		var end: Vector3 = decision + d * branch_length
		var length: float = (end - origin).length()
		var b := CSGCylinder3D.new()
		b.radius = tube_radius
		b.height = length
		b.sides = PipeSection.RING_SEGMENTS
		var y := d
		var x := Vector3.UP.cross(y)
		if x.length() < 1e-4:
			x = Vector3.RIGHT.cross(y)
		x = x.normalized()
		var z := x.cross(y).normalized()
		b.basis = Basis(x, y, z)
		b.position = (origin + end) * 0.5
		combiner.add_child(b)

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
		if mesh_instance:
			mesh_instance.mesh = null
		return
	var stripped := _strip_caps_and_color(union)
	_mesh_cache[key] = stripped
	if mesh_instance:
		mesh_instance.mesh = stripped
		mesh_instance.position = Vector3.ZERO
		mesh_instance.basis = Basis.IDENTITY
		# Wall-colour shader: per-fragment nearest-branch colouring.
		var shader := load("res://junction_color.gdshader") as Shader
		var mat := ShaderMaterial.new()
		mat.shader = shader
		mat.set_shader_parameter("tube_radius", tube_radius)
		# Branch starts and directions (local space). Disabled branches are
		# pushed far away so they never win the nearest test.
		var ang2 := deg_to_rad(branch_angle)
		var decision2 := Vector3(0.0, 0.0, decision_offset)
		var far := Vector3(0.0, 0.0, 10000.0)
		var starts := []
		var dirs2 := []
		if has_trunk:
			starts.append(Vector3.ZERO)
			dirs2.append(Vector3(0.0, 0.0, 1.0))
		else:
			starts.append(far)
			dirs2.append(Vector3(0.0, 0.0, 1.0))
		if left_branch:
			starts.append(decision2)
			dirs2.append(Vector3(-sin(ang2), 0.0, cos(ang2)))
		else:
			starts.append(far)
			dirs2.append(Vector3(-sin(ang2), 0.0, cos(ang2)))
		if right_branch:
			starts.append(decision2)
			dirs2.append(Vector3(sin(ang2), 0.0, cos(ang2)))
		else:
			starts.append(far)
			dirs2.append(Vector3(sin(ang2), 0.0, cos(ang2)))
		mat.set_shader_parameter("branch_start", starts)
		mat.set_shader_parameter("branch_dir", dirs2)
		var colors := [Color(0.7, 0.7, 0.75), Color(0.3, 0.6, 1.0), Color(1.0, 0.5, 0.3)]
		mat.set_shader_parameter("branch_color", colors)
		mat.set_shader_parameter("blend", 2.0)
		mesh_instance.material_override = mat

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
			for i in range(_curves.size()):
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
				out_norms.append(-n)
				out_uvs.append(uvs[k] if k < uvs.size() else Vector2.ZERO)
				out_cols.append(colors[best_c] if best_c < colors.size() else Color.WHITE)

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