class_name StraightPipeSection
extends PipeSection

@export var entry_radius : float = 10.0
@export var exit_radius  : float = 10.0
@export var length       : float = 100.0

@onready var mesh_instance : MeshInstance3D = $MeshInstance3D

func _ready() -> void:
	# Position markers to match actual length
	entry.position = Vector3(0.0, 0.0, -length / 2.0)
	exit.position  = Vector3(0.0, 0.0,  length / 2.0)
	exits = [exit]
	
	var m := CylinderMesh.new()
	m.top_radius    = exit_radius
	m.bottom_radius = entry_radius
	m.height        = length
	m.radial_segments = PipeSection.RING_SEGMENTS
	m.cap_top       = false
	m.cap_bottom    = false

	# CylinderMesh normals point outward; the vehicle views the pipe from the
	# inside, so negate them for correct interior lighting. Using ArrayMesh
	# avoids the SurfaceTool.generate_normals smoothing that broke an earlier
	# attempt.
	var arrays := m.surface_get_arrays(0)
	var normals := arrays[Mesh.ARRAY_NORMAL] as PackedVector3Array
	for i in range(normals.size()):
		normals[i] = -normals[i]
	arrays[Mesh.ARRAY_NORMAL] = normals
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh_instance.mesh = am

	# Use back-face culling so only the inside (inward normals) renders.
	# This prevents the outside faces from showing through and causing
	# the half-lit effect.
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.6462178, 0.9540631, 0.9395212, 1)
	mat.cull_mode = BaseMaterial3D.CULL_BACK
	mesh_instance.material_override = mat

	mesh_instance.create_trimesh_collision()
	# this auto-generates a StaticBody3D with correct collision as a child
	await get_tree().process_frame  # let the child node appear
	if mesh_instance.get_child_count() == 0:
		return
	var body  := mesh_instance.get_child(0) as StaticBody3D
	if body == null or body.get_child_count() == 0:
		return
	var shape := body.get_child(0) as CollisionShape3D
	if shape and shape.shape is ConcavePolygonShape3D:
		(shape.shape as ConcavePolygonShape3D).backface_collision = true

func get_entry_radius() -> float:
	return entry_radius

func get_exit_radius(_exit_index: int = 0) -> float:
	return exit_radius

func get_tube_properties(world_pos: Vector3) -> Dictionary:
	# Project world_pos onto the section's central axis
	var fwd      := global_transform.basis.z
	var to_pos   := world_pos - entry.global_position
	var along    := to_pos.dot(fwd)
	var along_c  : float = clampf(along, 0.0, length)
	var t: float = along_c / length
	
	# Radius at this point along the taper
	var r        := lerpf(entry_radius, exit_radius, t)
	
	# Nearest point on the centreline
	var origin   : Vector3 = entry.global_position + fwd * along_c
	
	return {
		"axis":   fwd,
		"origin": origin,
		"radius": r      # vehicle can use this later for e.g. FOV scaling
	}

func contains_point(world_pos: Vector3) -> bool:
	var local_pos := to_local(world_pos)
	var half      := length / 2.0
	if abs(local_pos.z) > half + 2.0:
		return false
	var radial := Vector2(local_pos.x, local_pos.y).length()
	return radial < max(entry_radius, exit_radius) + 2.0
