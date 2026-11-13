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
	mesh_instance.mesh = m	
	mesh_instance.create_trimesh_collision()
	# this auto-generates a StaticBody3D with correct collision as a sibling
	await get_tree().process_frame  # let the child node appear
	var body  := mesh_instance.get_child(0) as StaticBody3D
	var shape := body.get_child(0) as CollisionShape3D
	var poly  := shape.shape as ConcavePolygonShape3D
	poly.backface_collision = true

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
