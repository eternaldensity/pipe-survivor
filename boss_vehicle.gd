# boss_vehicle.gd  (Phase 6 — first pass)
class_name BossVehicle
extends CharacterBody3D

@export var network: PipeNetwork
var attractor: Attractor = Attractor.new()
@export var health: float = 50.0
@export var speed: float = 8.0
@export var arena_radius: float = 40.0
@export var arena_center: Vector3 = Vector3.ZERO

var tube_origin := Vector3.ZERO
var tube_axis := Vector3(0.0, 0.0, 1.0)
var tube_radius := 10.0

var _attractor_pos: Vector3 = Vector3(0.1, 0.1, 0.1)
var _attractor_timer: float = 0.0
var _attractor_scale: float = 0.5

# Attack state.
var _attack_cooldown: float = 3.0
var _attack_timer: float = 0.0
@export var target: Node3D = null

func _ready() -> void:
	_attractor_pos = Vector3(0.1, 0.1, 0.1)

func _physics_process(delta: float) -> void:
	if network == null:
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
		velocity += outward * 25.0 * delta

	# Attractor-driven movement: advance the attractor position, then steer
	# toward the corresponding point in the arena.
	_attractor_pos = attractor.step(_attractor_pos, delta * 2.0)
	# Map attractor coords to arena position (scale + offset).
	var target := arena_center + _attractor_pos * _attractor_scale
	# Project target onto the tube wall.
	var to_target := target - global_position
	var desired := to_target.normalized() * speed
	# Keep on the tube surface: remove radial component.
	var radial_vel := velocity.dot(outward) * outward
	var surface_vel := velocity - radial_vel
	surface_vel = surface_vel.move_toward(desired, 20.0 * delta)
	velocity = surface_vel + radial_vel

	_flatten(delta, inward)
	move_and_slide()

	# Attack: fire projectile toward player.
	_attack_timer += delta
	if _attack_timer >= _attack_cooldown and target != null:
		_attack_timer = 0.0
		_fire_projectile()

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
	var target_basis := Basis.looking_at(fwd, up)
	global_transform.basis = global_transform.basis.slerp(target_basis, delta * 14.0)

func take_damage(amount: float) -> void:
	health -= amount
	if health <= 0.0:
		queue_free()

func _fire_projectile() -> void:
	if target == null:
		return
	var proj = load("res://BossProjectile.tscn").instantiate() as BossProjectile
	if proj == null:
		return
	proj.network = network
	proj._target = target
	var dir := (target.global_position - global_position).normalized()
	var parent := get_parent()
	if parent:
		parent.add_child(proj)
		proj.global_position = global_position
		# Orient toward target.
		if dir.length_squared() > 1e-4:
			var up := Vector3.UP
			if absf(dir.dot(up)) > 0.99:
				up = Vector3.RIGHT
			proj.look_at(target.global_position, up)