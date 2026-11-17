# boss_vehicle.gd  (Phase 6)
class_name BossVehicle
extends CharacterBody3D

@export var network: PipeNetwork
@export var arena_center: Vector3 = Vector3.ZERO
@export var target: Node3D = null

var attractor: Attractor = Attractor.new()
var health: float = 80.0
var max_health: float = 80.0
var speed: float = 6.0
var arena_radius: float = 40.0

var tube_origin := Vector3.ZERO
var tube_axis := Vector3(0.0, 0.0, 1.0)
var tube_radius := 10.0

var _attractor_pos: Vector3 = Vector3(0.1, 0.1, 0.1)
var _attractor_scale: float = 0.5

# Attack state.
var _attack_cooldown: float = 3.0
var _attack_timer: float = 0.0
var _attack_pattern: int = 0  # 0=single, 1=burst, 2=charge, 3=spiral, 4=area_denial
var _phase: int = 1  # 1 = normal, 2 = enraged (health < 50%)

# Health bar.
var _health_bar: Label3D = null

var _projectile_scene: PackedScene = null

func _ready() -> void:
	_projectile_scene = load("res://BossProjectile.tscn")
	_build_mesh()
	_attractor_pos = Vector3(0.1, 0.1, 0.1)
	# Health bar above boss.
	_health_bar = Label3D.new()
	_health_bar.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_health_bar.font_size = 48
	_health_bar.position = Vector3(0.0, 3.0, 0.0)
	_health_bar.modulate = Color(1.0, 0.3, 0.3)
	add_child(_health_bar)
	_update_health_bar()

func _update_health_bar() -> void:
	if _health_bar:
		_health_bar.text = "BOSS %.0f/%.0f" % [health, max_health]

var _current_section: PipeSection = null

func _physics_process(delta: float) -> void:
	if network == null:
		return
	if _current_section == null or not is_instance_valid(_current_section) or not _current_section.contains_point(global_position):
		_current_section = network.get_section_at(global_position)
	var section := _current_section
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

	# Attractor-driven movement.
	_attractor_pos = attractor.step(_attractor_pos, delta * 2.0)
	var target_pos := arena_center + _attractor_pos * _attractor_scale
	var to_target := target_pos - global_position
	var desired := to_target.normalized() * speed
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
		_attack_pattern = (_attack_pattern + 1) % 3
		_execute_attack()

func _build_mesh() -> void:
	var mi := get_node_or_null("MeshInstance3D") as MeshInstance3D
	if mi:
		mi.visible = false
	# Core sphere.
	_add_part("Core", SphereMesh.new(), Vector3(2.0, 2.0, 2.0), Vector3.ZERO, Color(0.8, 0.15, 0.15), true)
	# Spikes.
	for i in range(8):
		var a := TAU * float(i) / 8.0
		var spike := MeshInstance3D.new()
		spike.name = "Spike%d" % i
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.0
		cyl.bottom_radius = 0.6
		cyl.height = 2.5
		spike.mesh = cyl
		spike.position = Vector3(cos(a) * 1.5, sin(a) * 1.5, 0.0)
		spike.rotation = Vector3(0, 0, a + PI * 0.5)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(1.0, 0.3, 0.2)
		mat.emission_enabled = true
		mat.emission = Color(1.0, 0.2, 0.1)
		mat.emission_energy_multiplier = 2.0
		spike.material_override = mat
		add_child(spike)

func _add_part(name: String, mesh: Mesh, size: Vector3, pos: Vector3, color: Color, metallic: bool) -> void:
	var mi := MeshInstance3D.new()
	mi.name = name
	if mesh is SphereMesh:
		(mesh as SphereMesh).radius = size.x
		(mesh as SphereMesh).height = size.x * 2.0
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	if metallic:
		mat.metallic = 0.6
		mat.roughness = 0.4
	mi.material_override = mat
	mi.position = pos
	add_child(mi)

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

func apply_threat_scale(mult: float) -> void:
	health *= mult
	max_health *= mult
	speed *= sqrt(mult)
	_update_health_bar()
	# Phase transition at 50% health.
	if _phase == 1 and health <= max_health * 0.5:
		_phase = 2
		_attack_cooldown = 1.5
		speed = 12.0
		_attractor_scale = 0.8
		if _health_bar:
			_health_bar.modulate = Color(1.0, 0.1, 0.1)
	if health <= 0.0:
		_health_bar.visible = false
		queue_free()

func _execute_attack() -> void:
	match _attack_pattern:
		0:
			_fire_single()
		1:
			_fire_burst()
		2:
			_fire_charge()
		3:
			_fire_spiral()
		4:
			_fire_area_denial()

func _fire_single() -> void:
	if target == null:
		return
	_spawn_projectile(target.global_position)

func _fire_burst() -> void:
	if target == null:
		return
	# Fire 3 projectiles in a spread.
	for i in range(3):
		var offset_angle := (i - 1) * 15.0  # -15, 0, +15 degrees
		var dir := (target.global_position - global_position).normalized()
		var right := dir.cross(Vector3.UP).normalized()
		var spread_dir := dir.rotated(Vector3.UP, deg_to_rad(offset_angle))
		_spawn_projectile(global_position + spread_dir * 20.0, spread_dir)

func _fire_charge() -> void:
	if target == null:
		return
	# Boss charges toward the player: boost speed briefly.
	speed = 20.0
	# Reset speed after a short delay.
	var timer := get_tree().create_timer(1.0)
	timer.timeout.connect(func(): speed = 8.0)
	_spawn_projectile(target.global_position)

func _spawn_projectile(aim_pos: Vector3, aim_dir: Vector3 = Vector3.ZERO) -> void:
	if _projectile_scene == null:
		_projectile_scene = load("res://BossProjectile.tscn")
	var proj = _projectile_scene.instantiate() as BossProjectile
	if proj == null:
		return
	proj.network = network
	proj._target = target
	var dir := aim_dir if aim_dir.length_squared() > 1e-4 else (aim_pos - global_position).normalized()
	proj.damage = 8.0
	var parent := get_parent()
	if parent:
		parent.add_child(proj)
		proj.global_position = global_position
		if dir.length_squared() > 1e-4:
			var up := Vector3.UP
			if absf(dir.dot(up)) > 0.99:
				up = Vector3.RIGHT
			var basis := Basis.looking_at(dir, up)
			proj.global_transform = Transform3D(basis, proj.global_position)

func _fire_spiral() -> void:
	if target == null:
		return
	# Fire 5 projectiles in a spiral pattern.
	for i in range(5):
		var angle := i * 72.0  # 72 degrees apart
		var dir := (target.global_position - global_position).normalized()
		var spread_dir := dir.rotated(Vector3.UP, deg_to_rad(angle))
		_spawn_projectile(global_position + spread_dir * 20.0, spread_dir)

func _fire_area_denial() -> void:
	if target == null:
		return
	# Fire 4 projectiles in a cross pattern around the boss.
	for i in range(4):
		var angle := i * 90.0
		var dir := (Vector3.FORWARD).rotated(Vector3.UP, deg_to_rad(angle))
		_spawn_projectile(global_position + dir * 15.0, dir)