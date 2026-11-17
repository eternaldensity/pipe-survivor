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

	# _build_meshes is a coroutine when the CSG union has to be built (it
	# awaits frames). Await it, otherwise _build_collisions sees a null mesh
	# on the first run and silently creates no collision body.
	await _build_meshes()

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
	var decision := Vector3(0.0, 0.0, decision_offset if has_trunk else 0.0)

	# Trunk curve.
	if has_trunk:
		var trunk := Curve3D.new()
		trunk.add_point(Vector3.ZERO, Vector3.ZERO, Vector3(0.0, 0.0, trunk_length * 0.4))
		trunk.add_point(Vector3(0.0, 0.0, trunk_length), Vector3(0.0, 0.0, -trunk_length * 0.4), Vector3.ZERO)
		_curves.append(trunk)

	# Branch curves run along the same axis as the CSG tube, from inside the
	# trunk to the exit marker, so the mesh, the curve and the marker agree.
	var ang := deg_to_rad(branch_angle)
	var dirs := [Vector3(-sin(ang), 0.0, cos(ang)), Vector3(sin(ang), 0.0, cos(ang))]
	var extra := _branch_extra()
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
		_curves.append(c)

## How far a branch tube extends back into the trunk before its exit. The
## cylinder/curve must stay inside the trunk volume so the union carves a clean
## opening instead of poking out through the entry or the side wall.
func _branch_extra() -> float:
	if not has_trunk:
		return 0.0
	var ang := deg_to_rad(branch_angle)
	var max_side := tube_radius * 0.8 / maxf(sin(ang), 0.02)
	var max_z := decision_offset * 0.95 / maxf(cos(ang), 0.02)
	return maxf(0.5, minf(blend_length + tube_radius, minf(max_side, max_z)))

func _nearest_curve_point(local_pos: Vector3) -> Dictionary:
	var best_dist := INF
	var best_point := Vector3.ZERO
	var best_tan := Vector3(0.0, 0.0, 1.0)
	var best_idx := -1
	for i in range(_curves.size()):
		var c := _curves[i]
		var off := c.get_closest_offset(local_pos)
		var tr := c.sample_baked_with_rotation(off)
		var pt := tr.origin
		var d := local_pos.distance_to(pt)
		# Prefer the trunk (first curve) on ties to avoid switching to a
		# branch when the vehicle is going straight through the junction.
		if best_idx < 0 or d < best_dist - 0.5 or (absf(d - best_dist) <= 0.5 and i < best_idx):
			best_dist = d
			best_point = pt
			best_tan = -tr.basis.z
			best_idx = i
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

	var mesh := await JunctionMeshBuilder.build(
		tube_radius, trunk_length, branch_angle, branch_length,
		decision_offset, blend_length, has_trunk, left_branch, right_branch)
	if mesh == null:
		push_error("Junction CSG union produced no mesh")
		if mesh_instance:
			mesh_instance.mesh = null
		return
	if mesh_instance:
		mesh_instance.mesh = mesh
		mesh_instance.position = Vector3.ZERO
		mesh_instance.basis = Basis.IDENTITY
		# Wall-colour shader: per-fragment nearest-branch colouring.
		var shader := load("res://junction_color.gdshader") as Shader
		if shader:
			var mat := ShaderMaterial.new()
			mat.shader = shader
			mat.set_shader_parameter("tube_radius", tube_radius)
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
			var colors := [Color(0.7, 0.7, 0.75), Color(0.3, 0.6, 1.0), Color(1.0, 0.5, 0.3)]
			mat.set_shader_parameter("branch_start", starts)
			mat.set_shader_parameter("branch_dir", dirs2)
			mat.set_shader_parameter("branch_color", colors)
			mat.set_shader_parameter("blend", 2.0)
			mesh_instance.material_override = mat

func _build_collisions() -> void:
	await build_trimesh_collision_async(mesh_instance)
