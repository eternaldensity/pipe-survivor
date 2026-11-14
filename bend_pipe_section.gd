@tool
class_name BendPipeSection
extends PipeSection

@export var tube_radius : float = 10.0
@export var length : float = 100.0
@export var bend_angle  : float = 90.0
@export var roll_angle : float = 0.0  # degrees, rotation around entry Z axis

@onready var mesh_instance : MeshInstance3D = $MeshInstance3D

# Computed in _ready, used by get_tube_properties
var _bend_radius : float
var _angle_rad   : float


func _ready() -> void:
	_angle_rad   = deg_to_rad(bend_angle)
	_bend_radius = length / _angle_rad
	
	assert(_bend_radius > tube_radius,
		"tube_length too short for bend_angle — tube would self-intersect")

	
	_build_mesh()
	_place_markers()
	exits = [exit]
	if Engine.is_editor_hint():
		notify_property_list_changed()
		return
	_build_collision()


func _place_markers() -> void:
	entry.transform = Transform3D.IDENTITY
	
	var roll := deg_to_rad(roll_angle)
	
	# Arc centre is at +X from the entry point
	# Exit position is where the arc ends
		# Rotate the exit position around Z by roll_angle
	var exit_pos := Vector3(
		_bend_radius - _bend_radius * cos(_angle_rad),
		0.0,
		_bend_radius * sin(_angle_rad)
	)

	var roll_basis := Basis(Vector3(0, 0, 1), roll)
	exit.position = roll_basis * exit_pos
	exit.rotation = (roll_basis * Basis(Vector3(0, 1, 0), _angle_rad)).get_euler()


func _build_mesh() -> void:
	# Clear previous mesh
	mesh_instance.mesh = null
	
	var arc_steps  :int= max(16, int(bend_angle / 5.0))  # one step per 5 degrees minimum
	var ring_steps := PipeSection.RING_SEGMENTS
	
	var verts    := PackedVector3Array()
	var normals  := PackedVector3Array()
	var uvs      := PackedVector2Array()
	var indices  := PackedInt32Array()
	
	# Arc centre sits at (bend_radius, 0, 0) in local space
	var roll       := deg_to_rad(roll_angle)
	var roll_basis := Basis(Vector3(0, 0, 1), roll)
	var arc_centre := roll_basis * Vector3(_bend_radius, 0.0, 0.0)
	
	for i in range(arc_steps + 1):
		var u     := float(i) / float(arc_steps)
		var arc_a := u * _angle_rad   # angle along the arc
		
		# Centre of the cross-section ring at this arc position
		# Unrolled ring centre, then apply roll
		var ring_centre_local := Vector3(
			_bend_radius * (1.0 - cos(arc_a)),
			0.0,
			_bend_radius * sin(arc_a)
		)
		var ring_centre := roll_basis * ring_centre_local
		
		# Tangent along the arc at this point
		# Tangent and radial also get rolled
		var tangent_local := Vector3(sin(arc_a), 0.0, cos(arc_a)).normalized()
		var tangent       := roll_basis * tangent_local
		var radial        := (ring_centre - arc_centre).normalized()
		var up            := tangent.cross(radial).normalized()
				
		for j in range(ring_steps + 1):
			var v       := float(j) / float(ring_steps)
			var ring_a  := v * TAU
			
			# Point on the cross-section ring, expressed in the
			# local frame of (radial, up, tangent)
			# cross-section in the plane perpendicular to the tangent
			var offset := (radial * cos(ring_a) + up * sin(ring_a)) * tube_radius
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
			
			# Winding order: flipped so the inside surface is the front face
			# (matches inward normals with CULL_BACK).
			indices.append_array([a, c, b, a, d, c])
	
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX]  = indices
	
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh_instance.mesh = mesh

	# Use back-face culling so only the inside (inward normals) renders.
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.6462178, 0.9540631, 0.9395212, 1)
	mat.cull_mode = BaseMaterial3D.CULL_BACK
	mesh_instance.material_override = mat


func _build_collision() -> void:
	# Remove any previously generated collision children
	for child in mesh_instance.get_children():
		child.queue_free()
		
	mesh_instance.create_trimesh_collision()
	await get_tree().process_frame
	# create_trimesh_collision makes a StaticBody3D child of mesh_instance
	if mesh_instance.get_child_count() == 0:
		return
	var body  := mesh_instance.get_child(0) as StaticBody3D
	if body == null or body.get_child_count() == 0:
		return
	var shape := body.get_child(0) as CollisionShape3D
	if shape and shape.shape is ConcavePolygonShape3D:
		(shape.shape as ConcavePolygonShape3D).backface_collision = true
	
	
func _get_arc_angle(unrolled_local: Vector3) -> float:
	var arc_centre := Vector3(_bend_radius, 0.0, 0.0)
	var to_vehicle := unrolled_local - arc_centre
	to_vehicle.y   = 0.0
	
	# atan2 is unstable when to_vehicle is nearly parallel to the arc radius
	# Use dot products against known entry/exit directions instead
	# Entry tangent is (0,0,1), exit tangent is (sin(_angle_rad), 0, cos(_angle_rad))
	# Project to_vehicle onto a more stable basis
	
	# The arc sweeps from angle 0 to _angle_rad
	# Instead of atan2, find closest point by iterating a few Newton steps
	var angle := atan2(to_vehicle.z, -to_vehicle.x)
	angle = clampf(angle, 0.0, _angle_rad)
	
	# Refine with a few Newton-Raphson steps
	for i in range(4):
		var arc_pt := Vector3(
			-cos(angle) * _bend_radius,
			0.0,
			 sin(angle) * _bend_radius
		)
		var tangent := Vector3(sin(angle), 0.0, cos(angle))
		var diff    := (unrolled_local - arc_centre) - arc_pt
		diff.y      = 0.0
		var step    := diff.dot(tangent)
		angle       = clampf(angle + step / _bend_radius, 0.0, _angle_rad)
	
	return angle


func get_entry_radius() -> float:
	return tube_radius

func get_exit_radius(_exit_index: int = 0) -> float:
	return tube_radius

func get_tube_properties(world_pos: Vector3) -> Dictionary:
	var local_pos  := to_local(world_pos)	
	var roll       := deg_to_rad(roll_angle)
	var roll_basis := Basis(Vector3(0, 0, 1), roll)
	
	# Unroll the local position before doing the arc calculation
	var unrolled   := roll_basis.inverse() * local_pos
	
	var angle      := _get_arc_angle(unrolled)
	
	var arc_point_local := Vector3(
		_bend_radius * (1.0 - cos(angle)),
		0.0,
		_bend_radius * sin(angle)
	)
	
	# Tangent to the arc at this angle (analytic, avoids finite-difference
	# degeneracy at the endpoints / for very small bend angles).
	var tangent_local := roll_basis * Vector3(sin(angle), 0.0, cos(angle))

	return {
		"axis":   (global_transform.basis * tangent_local).normalized(),
		"origin": to_global(roll_basis * arc_point_local),
		"radius": tube_radius
	}

func contains_point(world_pos: Vector3) -> bool:
	var local_pos  := to_local(world_pos)
	var roll       := deg_to_rad(roll_angle)
	var roll_basis := Basis(Vector3(0, 0, 1), roll)
	var unrolled   := roll_basis.inverse() * local_pos
	
	var arc_centre := Vector3(_bend_radius, 0.0, 0.0)
	var to_vehicle := unrolled - arc_centre
	to_vehicle.y   = 0.0
	# Raw (unclamped) angle so we can reject points beyond the arc ends
	var raw_angle  := atan2(to_vehicle.z, -to_vehicle.x)
	if raw_angle < -0.1 or raw_angle > _angle_rad + 0.1:
		return false
	
	var angle      : float = clampf(raw_angle, 0.0, _angle_rad)
	var arc_point  := Vector3(
		_bend_radius * (1.0 - cos(angle)),
		0.0,
		_bend_radius * sin(angle)
	)
	return unrolled.distance_to(arc_point) < tube_radius + 2.0
