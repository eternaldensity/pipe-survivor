extends CharacterBody3D

@export var gravity      := 25.0
@export var speed        := 20.0
@export var acceleration := 50.0
@export var friction     := 35.0
@export var turn_speed   := 2.0   # radians per second
@export var steer_accel  := 6.0   # steering rate ramp (units/sec)

var tube_origin     := Vector3.ZERO
var tube_axis       := Vector3(0.0, 0.0, 1.0)
var tube_radius     := 10.0
var steering_amount := 0.0

@export var network : PipeNetwork


func _outward_from(props: Dictionary) -> Vector3:
	var axis: Vector3 = props["axis"]
	var origin: Vector3 = props["origin"]
	var to_self: Vector3 = global_position - origin
	var radial: Vector3 = to_self - to_self.dot(axis) * axis
	if radial.length_squared() < 1e-4:
		return axis.cross(Vector3.UP).normalized()
	return radial.normalized()


func _physics_process(delta: float) -> void:
	var section := network.get_section_at(global_position)
	if section == null:
		return
	var props   := section.get_tube_properties(global_position)
	tube_axis   = props["axis"]
	tube_origin = props["origin"]
	tube_radius = props["radius"]

	var outward := _outward_from(props)
	var inward  := -outward
	up_direction = inward

	# ── Steering: rotate heading around the surface normal ────────────────
	# This is pure yaw relative to the tube surface — left/right turns the
	# vehicle, and from then on forward always means "where I'm pointing"
	# Steering input ramps smoothly instead of being all-or-nothing.
	var target_turn := Input.get_axis("ui_left", "ui_right")
	steering_amount = move_toward(steering_amount, target_turn, steer_accel * delta)
	if abs(steering_amount) > 0.001:
		var steer := Basis(inward, -steering_amount * turn_speed * delta)
		global_transform.basis = steer * global_transform.basis

	# ── Gravity ───────────────────────────────────────────────────────────
	if not is_on_floor():
		velocity += outward * gravity * delta

	# ── Centripetal force ─────────────────────────────────────────────────
	# When spiraling, circumferential velocity requires centripetal
	# acceleration to maintain the curved path — this manifests as
	# increased force pressing the vehicle into the wall, exactly like
	# banking hard in a real vehicle. The faster the spiral, the heavier
	# you feel. Forward progress along the tube axis slows automatically
	# because your velocity vector is pointing more sideways.
	var circ_vel    := velocity - velocity.dot(tube_axis) * tube_axis \
								- velocity.dot(outward)   * outward
	var to_self     := global_position - tube_origin
	var radial_dist := (to_self - tube_axis * to_self.dot(tube_axis)).length()
	var centripetal:float = circ_vel.length_squared() / max(radial_dist, 0.1)
	velocity += outward * centripetal * delta

	# ── Drive in the direction the vehicle is facing ──────────────────────
	var vehicle_fwd := -global_transform.basis.z
	vehicle_fwd = vehicle_fwd - vehicle_fwd.dot(outward) * outward
	if vehicle_fwd.length_squared() > 1e-4:
		vehicle_fwd = vehicle_fwd.normalized()
	else:
		vehicle_fwd = tube_axis

	var throttle    := Input.get_axis("ui_down", "ui_up")
	var radial_vel  := velocity.dot(outward) * outward
	var surface_vel := velocity - radial_vel

	if abs(throttle) > 0.001:
		surface_vel = surface_vel.move_toward(
				vehicle_fwd * throttle * speed, acceleration * delta)
	else:
		surface_vel = surface_vel.move_toward(Vector3.ZERO, friction * delta)

	velocity = surface_vel + radial_vel

	# ── Keep vehicle flat on the tube surface ─────────────────────────────
	_flatten_to_surface(inward, delta)

	move_and_slide()


func _flatten_to_surface(up: Vector3, delta: float) -> void:
	var fwd := -global_transform.basis.z
	fwd = fwd - fwd.dot(up) * up
	if fwd.length_squared() < 1e-4:
		fwd = tube_axis
	else:
		fwd = fwd.normalized()
	var target := Basis.looking_at(fwd, up)
	global_transform.basis = global_transform.basis.slerp(target, delta * 14.0)