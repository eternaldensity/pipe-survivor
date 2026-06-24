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
	
	var m := CylinderMesh.new()
	m.top_radius    = exit_radius
	m.bottom_radius = entry_radius
	m.height        = length
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
	var t:float   = clamp(along / length, 0.0, 1.0)
	
	# Radius at this point along the taper
	var r        := lerpf(entry_radius, exit_radius, t)
	
	# Nearest point on the centreline
	var origin   := entry.global_position + fwd * along
	
	return {
		"axis":   fwd,
		"origin": origin,
		"radius": r      # vehicle can use this later for e.g. FOV scaling
	}
