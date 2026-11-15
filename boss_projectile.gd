# boss_projectile.gd  (Phase 6 — boss attacks)
class_name BossProjectile
extends CharacterBody3D

@export var speed: float = 30.0
@export var damage: float = 15.0
@export var lifetime: float = 5.0

var tube_axis := Vector3(0.0, 0.0, 1.0)
var network: PipeNetwork = null
var _time_alive: float = 0.0
var _target: Node3D = null

func _ready() -> void:
	# Visual: small red sphere.
	var mesh_inst := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	mesh_inst.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.2, 0.2)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.2, 0.2)
	mat.emission_energy_multiplier = 2.0
	mesh_inst.material_override = mat
	add_child(mesh_inst)

	# Collision shape.
	var col := CollisionShape3D.new()
	var sphere_shape := SphereShape3D.new()
	sphere_shape.radius = 0.5
	col.shape = sphere_shape
	add_child(col)

func _physics_process(delta: float) -> void:
	_time_alive += delta
	if _time_alive >= lifetime:
		queue_free()
		return

	if network:
		var section := network.get_section_at(global_position)
		if section:
			var props := section.get_tube_properties(global_position)
			tube_axis = props["axis"]

	# Move forward.
	velocity = -global_transform.basis.z * speed
	move_and_slide()

	# Check for player hit.
	if _target and global_position.distance_to(_target.global_position) < 2.0:
		if _target.has_method("take_damage"):
			_target.take_damage(damage)
		queue_free()