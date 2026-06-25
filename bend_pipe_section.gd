@tool
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
	print("entry tangent: ", Vector3(sin(0.0), 0.0, cos(0.0)))
	print("exit tangent: ", Vector3(sin(_angle_rad), 0.0, cos(_angle_rad)))
	print("bend basis: ", global_transform.basis)
	
	_build_mesh()
	_place_markers()
	if Engine.is_editor_hint():
		notify_property_list_changed()
		return
	_build_collision()


func _place_markers() -> void:
	entry.transform = Transform3D.IDENTITY
	
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
	# Clear previous mesh
	mesh_instance.mesh = null
	
	var arc_steps  :int= max(16, int(bend_angle / 5.0))  # one step per 5 degrees minimum
	var ring_steps := 24
	
	var verts    := PackedVector3Array()
	var normals  := PackedVector3Array()
	var uvs      := PackedVector2Array()
	var indices  := PackedInt32Array()
	
	
	for i in range(arc_steps + 1):
		var u     := float(i) / float(arc_steps)
		var arc_a := u * _angle_rad   # angle along the arc
		
		# Centre of the cross-section ring at this arc position
		var ring_centre := Vector3(
			_bend_radius * (1.0 - cos(arc_a)),
			0.0,
			_bend_radius * sin(arc_a)
		)

		var tangent := Vector3(sin(arc_a), 0.0, cos(arc_a)).normalized()

		var radial := (ring_centre - Vector3(_bend_radius, 0.0, 0.0)).normalized()
				
		for j in range(ring_steps + 1):
			var v       := float(j) / float(ring_steps)
			var ring_a  := v * TAU
			
			# Point on the cross-section ring, expressed in the
			# local frame of (radial, up, tangent)
			# cross-section in the plane perpendicular to the tangent
			var up := Vector3.UP  # just use global Y, it's constant for a horizontal bend
			var offset := (radial * cos(ring_a) + up * sin(ring_a)) * tube_radius
			var pos    := ring_centre + offset
			
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
	# Remove any previously generated collision children
	for child in mesh_instance.get_children():
		child.queue_free()
		
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
	
	# Vector from arc centre to vehicle, flattened to XZ plane
	# (Y is the up axis of the tube cross-section, not the arc plane)
	var to_vehicle := local_pos - arc_centre
	to_vehicle.y   = 0.0
	
	# At entry (Z=0 end), to_vehicle points in -X direction
	# At exit (end of arc), to_vehicle points in -Z direction for 90 deg bend
	# atan2(z, x) gives angle from +X axis
	# We want angle from -X axis (entry) sweeping toward -Z (exit)
	var angle := atan2(to_vehicle.z, -to_vehicle.x)
	angle      = clamp(angle, 0.0, _angle_rad)
	
	# Nearest point on arc centreline
	var arc_point := arc_centre + Vector3(
		-cos(angle) * _bend_radius,
		0.0,
		 sin(angle) * _bend_radius
	)
	
	# Tangent: derivative of arc_point with respect to angle
	# d/dangle (-cos(angle), 0, sin(angle)) = (sin(angle), 0, cos(angle))
	var tangent := Vector3(sin(angle), 0.0, cos(angle)).normalized()
	
	# Verify: at angle=0 tangent should be (0,0,1) matching straight pipe exit
	# At angle=PI/2 tangent should be (1,0,0)
	
	return {
		"axis":   global_transform.basis * tangent,
		"origin": to_global(arc_point),
		"radius": tube_radius
	}

func contains_point(world_pos: Vector3) -> bool:
	var local_pos  := to_local(world_pos)
	var arc_centre := Vector3(_bend_radius, 0.0, 0.0)
	var to_vehicle := local_pos - arc_centre
	to_vehicle.y   = 0.0
	var angle      := atan2(to_vehicle.z, -to_vehicle.x)
	if angle < -0.1 or angle > _angle_rad + 0.1:
		return false
	var arc_point  := arc_centre + Vector3(
		-cos(angle) * _bend_radius,
		0.0,
		 sin(angle) * _bend_radius
	)
	var dist := local_pos.distance_to(arc_point)
	return dist < tube_radius + 2.0
