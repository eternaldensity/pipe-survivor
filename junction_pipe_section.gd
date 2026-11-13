@tool
# junction_pipe_section.gd  (skeleton — Phase 2 in progress)
class_name JunctionPipeSection
extends PipeSection

@export var tube_radius   : float = 10.0
@export var trunk_length  : float = 50.0
@export var branch_angle  : float = 30.0   # degrees, half-spread of the two branches
@export var branch_length : float = 80.0

@onready var mesh_instance : MeshInstance3D = $MeshInstance3D

func _ready() -> void:
	# Entry at origin; trunk continues straight; two branches peel off symmetrically.
	entry.position    = Vector3(0.0, 0.0, 0.0)
	# Primary exit = trunk (straight ahead)
	exit.position     = Vector3(0.0, 0.0, trunk_length)
	# Extra exits
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

	# Build trunk + branch cylinder meshes for visibility/collision.
	_build_meshes()

	if Engine.is_editor_hint():
		notify_property_list_changed()
		return

	await _build_collisions()

# Centreline segments (local space). Each is [start, end].
var _paths: Array = []

func _build_meshes() -> void:
	# Clear any previously generated branch mesh instances (editor re-runs).
	for c in get_children():
		if c is MeshInstance3D and c.name.begins_with("BranchMesh"):
			c.queue_free()

	# Helper: basis with Y axis along dir.
	var make_basis := func(dir: Vector3) -> Basis:
		var y := dir.normalized()
		var x := Vector3.UP.cross(y)
		if x.length() < 1e-4:
			x = Vector3.RIGHT.cross(y)
		x = x.normalized()
		var z := x.cross(y).normalized()
		return Basis(x, y, z)

	# Trunk
	if mesh_instance:
		var m := CylinderMesh.new()
		m.top_radius = tube_radius
		m.bottom_radius = tube_radius
		m.height = trunk_length
		m.radial_segments = PipeSection.RING_SEGMENTS
		m.cap_top = false
		m.cap_bottom = false
		mesh_instance.mesh = m
		mesh_instance.position = Vector3(0.0, 0.0, trunk_length * 0.5)
		mesh_instance.basis = make_basis.call(Vector3(0.0, 0.0, 1.0))

	# Branches
	var a := deg_to_rad(branch_angle)
	var branch_dirs := [Vector3(-sin(a), 0.0, cos(a)), Vector3(sin(a), 0.0, cos(a))]
	var branch_names := ["BranchMeshLeft", "BranchMeshRight"]
	for i in range(2):
		var dir: Vector3 = branch_dirs[i]
		var bmi := MeshInstance3D.new()
		bmi.name = branch_names[i]
		var bm := CylinderMesh.new()
		bm.top_radius = tube_radius
		bm.bottom_radius = tube_radius
		bm.height = branch_length
		bm.radial_segments = PipeSection.RING_SEGMENTS
		bm.cap_top = false
		bm.cap_bottom = false
		bmi.mesh = bm
		bmi.position = dir * (branch_length * 0.5)
		bmi.basis = make_basis.call(dir)
		add_child(bmi)

func _build_collisions() -> void:
	for mi in [mesh_instance] + _branch_meshes():
		if mi == null or mi.mesh == null:
			continue
		if mi.get_child_count() == 0:
			mi.create_trimesh_collision()
	await get_tree().process_frame
	for mi in [mesh_instance] + _branch_meshes():
		if mi == null or mi.get_child_count() == 0:
			continue
		var body := mi.get_child(0) as StaticBody3D
		if body and body.get_child_count() > 0:
			var shape := body.get_child(0) as CollisionShape3D
			if shape and shape.shape is ConcavePolygonShape3D:
				(shape.shape as ConcavePolygonShape3D).backface_collision = true

func _branch_meshes() -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for c in get_children():
		if c is MeshInstance3D and c.name.begins_with("BranchMesh"):
			out.append(c)
	return out

func _build_paths() -> void:
	_paths.clear()
	# Trunk
	_paths.append([Vector3.ZERO, Vector3(0.0, 0.0, trunk_length)])
	# Branches
	var a := deg_to_rad(branch_angle)
	_paths.append([Vector3.ZERO, Vector3(-sin(a) * branch_length, 0.0, cos(a) * branch_length)])
	_paths.append([Vector3.ZERO, Vector3( sin(a) * branch_length, 0.0, cos(a) * branch_length)])

func _nearest_path_point(local_pos: Vector3) -> Dictionary:
	# Returns {"path_idx", "point", "tangent"} for the closest centreline.
	var best_dist := INF
	var best_point := Vector3.ZERO
	var best_tan := Vector3(0.0, 0.0, 1.0)
	for p in _paths:
		var s: Vector3 = p[0]
		var e: Vector3 = p[1]
		var seg := e - s
		var seg_len := seg.length()
		if seg_len < 1e-6:
			continue
		var t := clampf((local_pos - s).dot(seg) / (seg_len * seg_len), 0.0, 1.0)
		var pt := s + seg * t
		var d := local_pos.distance_to(pt)
		if d < best_dist:
			best_dist = d
			best_point = pt
			best_tan = seg.normalized()
	return {"point": best_point, "tangent": best_tan, "dist": best_dist}

func get_tube_properties(world_pos: Vector3) -> Dictionary:
	var local_pos := to_local(world_pos)
	_build_paths()
	var info := _nearest_path_point(local_pos)
	return {
		"axis":   (global_transform.basis * info["tangent"]).normalized(),
		"origin": to_global(info["point"]),
		"radius": tube_radius,
	}

func contains_point(world_pos: Vector3) -> bool:
	var local_pos := to_local(world_pos)
	_build_paths()
	var info := _nearest_path_point(local_pos)
	return info["dist"] < tube_radius + 3.0