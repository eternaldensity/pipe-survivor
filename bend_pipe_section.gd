class_name BendPipeSection
extends PipeSection

@export var tube_radius : float = 10.0
@export var tube_length : float = 100.0
@export var bend_angle  : float = 90.0

@onready var mesh_instance : MeshInstance3D = $MeshInstance3D

# Computed in _ready, used by get_tube_properties
var _bend_radius : float
var _angle_rad   : float


func _ready() -> void:
	_angle_rad   = deg_to_rad(bend_angle)
	_bend_radius = tube_length / _angle_rad
	
	assert(_bend_radius > tube_radius,
		"tube_length too short for bend_angle — tube would self-intersect")
	
	_build_mesh()
	_build_collision()
	_place_markers()


func _place_markers() -> void:
	entry.position = Vector3.ZERO
	entry.rotation = Vector3.ZERO
	
	# Arc centre is at +X from the entry point
	# Exit position is where the arc ends
	exit.position = Vector3(
		_bend_radius - _bend_radius * cos(_angle_rad),
		0.0,
		_bend_radius * sin(_angle_rad)
	)
	# Exit faces the tangent direction at the end of the arc
	exit.rotation = Vector3(0.0, -_angle_rad, 0.0)


func _build_mesh() -> void:
	var arc_steps  :int= max(16, int(bend_angle / 5.0))  # one step per 5 degrees minimum
	var ring_steps := 24
	
	var verts    := PackedVector3Array()
	var normals  := PackedVector3Array()
	var uvs      := PackedVector2Array()
	var indices  := PackedInt32Array()
	
	# Arc centre sits at (bend_radius, 0, 0) in local space
	var arc_centre := Vector3(_bend_radius, 0.0, 0.0)
	
	for i in range(arc_steps + 1):
		var u     := float(i) / float(arc_steps)
		var arc_a := u * _angle_rad   # angle along the arc
		
		# Centre of the cross-section ring at this arc position
		var ring_centre := arc_centre + Vector3(
			-cos(arc_a) * _bend_radius,
			0.0,
			 sin(arc_a) * _bend_radius
		)
		
		# Tangent along the arc at this point
		var tangent := Vector3(sin(arc_a), 0.0, cos(arc_a)).normalized()
		
		# Outward radial from arc centre to ring centre — 
		# this is the "away from bend centre" direction
		var radial  := (ring_centre - arc_centre).normalized()
		
		# Up is just Y — the tube doesn't roll around the bend
		var up      := Vector3.UP
		
		for j in range(ring_steps + 1):
			var v       := float(j) / float(ring_steps)
			var ring_a  := v * TAU
			
			# Point on the cross-section ring, expressed in the
			# local frame of (radial, up, tangent)
			var offset  := (radial * cos(ring_a) + up * sin(ring_a)) * tube_radius
			var pos     := ring_centre + offset
			
			# Normal points inward (toward tube centre) for inside surface
			var normal  := -offset.normalized()
			
			verts.append(pos)
			normals.append(normal)
			uvs.append(Vector2(u, v))
	
	# Build index buffer — two triangles per quad between adjacent rings
	for i in range(arc_steps):
		for j in range(ring_steps):
			var a := i       * (ring_steps + 1) + j
			var b := (i + 1) * (ring_steps + 1) + j
			var c := (i + 1) * (ring_steps + 1) + j + 1
			var d := i       * (ring_steps + 1) + j + 1
			
			# Winding order: inward-facing normals need CW winding
			indices.append_array([a, b, c, a, c, d])
	
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX]  = indices
	
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh_instance.mesh = mesh


func _build_collision() -> void:
	mesh_instance.create_trimesh_collision()
	await get_tree().process_frame
	# create_trimesh_collision makes a StaticBody3D sibling of mesh_instance
	var body  := mesh_instance.get_child(0) as StaticBody3D
	var shape := body.get_child(0) as CollisionShape3D
	var poly  := shape.shape as ConcavePolygonShape3D
	poly.backface_collision = true


func get_tube_properties(world_pos: Vector3) -> Dictionary:
	var local_pos  := to_local(world_pos)
	var arc_centre := Vector3(_bend_radius, 0.0, 0.0)
	
	# Project onto arc plane and find angle
	var to_vehicle := local_pos - arc_centre
	to_vehicle.y   = 0.0
	var angle      := atan2(to_vehicle.z, -to_vehicle.x)
	angle          = clamp(angle, 0.0, _angle_rad)
	
	# Nearest point on arc centreline
	var arc_point  := arc_centre + Vector3(
		-cos(angle) * _bend_radius,
		0.0,
		 sin(angle) * _bend_radius
	)
	
	# Tangent at that point
	var tangent    := Vector3(sin(angle), 0.0, cos(angle)).normalized()
	
	return {
		"axis":   global_transform.basis * tangent,
		"origin": to_global(arc_point),
		"radius": tube_radius
	}
