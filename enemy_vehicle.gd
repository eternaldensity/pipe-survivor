# enemy_vehicle.gd  (Phase 5 — first pass)
class_name EnemyVehicle
extends CharacterBody3D

@export var gravity: float = 25.0
@export var speed: float = 12.0
@export var health: float = 3.0

var tube_origin := Vector3.ZERO
var tube_axis := Vector3(0.0, 0.0, 1.0)
var tube_radius := 10.0

@export var network: PipeNetwork
@export var target: Node3D  # the player vehicle

func _physics_process(delta: float) -> void:
	if network == null or target == null:
		return
	var section := network.get_section_at(global_position)
	if section == null:
		return
	var props := section.get_tube_properties(global_position)
	tube_axis = props["axis"]
	tube_origin = props["origin"]
	tube_radius = props["radius"]

	var outward := _outward_from(props)
	var inward := -outward
	up_direction = inward

	# Gravity toward wall.
	if not is_on_floor():
		velocity += outward * gravity * delta

	# Chase the player: move toward target along the tube.
	var to_target := target.global_position - global_position
	var along_axis := to_target.dot(tube_axis)
	var dir := tube_axis if along_axis > 0.0 else -tube_axis
	# Blend toward target direction.
	var desired := dir * speed
	# Add some circumferential steering toward target.
	var to_target_perp := to_target - to_target.dot(tube_axis) * tube_axis
	if to_target_perp.length_squared() > 1e-4:
		var circ_dir := to_target_perp.normalized()
		desired += circ_dir * speed * 0.3

	var radial_vel := velocity.dot(outward) * outward
	var surface_vel := velocity - radial_vel
	surface_vel = surface_vel.move_toward(desired, 30.0 * delta)
	velocity = surface_vel + radial_vel

	_flatten(delta, inward)
	move_and_slide()

func _outward_from(props: Dictionary) -> Vector3:
	var axis: Vector3 = props["axis"]
	var origin: Vector3 = props["origin"]
	var to_self: Vector3 = global_position - origin
	var radial: Vector3 = to_self - to_self.dot(axis) * axis
	if radial.length_squared() < 1e-4:
		return axis.cross(Vector3.UP).normalized()
	return radial.normalized()

func _flatten(delta: float, up: Vector3) -> void:
	var fwd := -global_transform.basis.z
	fwd = fwd - fwd.dot(up) * up
	if fwd.length_squared() < 1e-4:
		fwd = tube_axis
	else:
		fwd = fwd.normalized()
	var target := Basis.looking_at(fwd, up)
	global_transform.basis = global_transform.basis.slerp(target, delta * 14.0)

func take_damage(amount: float) -> void:
	health -= amount
	if health <= 0.0:
		queue_free()