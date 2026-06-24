extends CharacterBody3D

const GRAVITY        := 25.0
const SPEED          := 14.0
const ACCELERATION   := 60.0
const FRICTION       := 40.0

# Prototype: tube runs along Z through the world origin.
# Later this will come from the current tube segment.
var tube_origin := Vector3.ZERO
var tube_axis   := Vector3(0.0, 0.0, 1.0)


func _get_outward() -> Vector3:
	## Direction from the tube axis toward this vehicle.
	## This is our gravity direction — it presses us into the wall.
	var to_self := global_position - tube_origin
	var along   := to_self.dot(tube_axis) * tube_axis
	var radial  := to_self - along
	if radial.length_squared() < 1e-4:
		# Exactly on axis — pick an arbitrary perpendicular as fallback
		return tube_axis.cross(Vector3.UP).normalized()
	return radial.normalized()


func _physics_process(delta: float) -> void:
	var outward := _get_outward()
	var inward  := -outward          # toward tube centre = our "up"
	
	# Tell move_and_slide() which direction counts as floor
	up_direction = inward
	
	# Gravity pulls us toward the wall when airborne
	if not is_on_floor():
		velocity += outward * GRAVITY * delta
	
	# ── Input ─────────────────────────────────────────────────────────────
	# Forward / back  → along the tube axis
	# Left / right    → tangent around the tube surface
	var tangent := outward.cross(tube_axis).normalized()
	
	var wish := Vector3.ZERO
	if Input.is_action_pressed("ui_up"):    wish += tube_axis
	if Input.is_action_pressed("ui_down"):  wish -= tube_axis
	if Input.is_action_pressed("ui_right"): wish += tangent
	if Input.is_action_pressed("ui_left"):  wish -= tangent
	if wish.length_squared() > 0.0:
		wish = wish.normalized()
	
	# ── Velocity on the tube surface ──────────────────────────────────────
	# Split velocity into surface component and radial component.
	# We only steer the surface component; gravity owns the radial one.
	var radial_vel  := velocity.dot(outward) * outward
	var surface_vel := velocity - radial_vel
	
	if wish.length_squared() > 0.0:
		surface_vel = surface_vel.move_toward(wish * SPEED, ACCELERATION * delta)
	else:
		surface_vel = surface_vel.move_toward(Vector3.ZERO, FRICTION * delta)
	
	velocity = surface_vel + radial_vel
	
	# ── Orient vehicle ────────────────────────────────────────────────────
	_orient_to_surface(inward, delta)
	
	move_and_slide()


func _orient_to_surface(up: Vector3, delta: float) -> void:
	## Keep vehicle's local Y pointing toward tube centre.
	## Forward stays projected onto the tube surface.
	var fwd := -global_transform.basis.z
	fwd = fwd - fwd.dot(up) * up         # project onto surface plane
	if fwd.length_squared() < 1e-4:
		fwd = tube_axis
	else:
		fwd = fwd.normalized()
	
	var target_basis := Basis.looking_at(fwd, up)
	# Smooth reorientation so sudden wall-sticking doesn't snap the view
	global_transform.basis = global_transform.basis.slerp(target_basis, delta * 12.0)
