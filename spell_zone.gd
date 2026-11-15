# spell_zone.gd  (Phase 4 — first pass)
class_name SpellZone
extends Area3D

@export var duration: float = 5.0
@export var strength: float = 0.5
@export var zone_radius: float = 15.0
@export var attractor_family: String = "Lorenz"

var attractor: Attractor = Attractor.new()
var zone_centre: Vector3 = Vector3.ZERO
var time_alive: float = 0.0

func _ready() -> void:
	# Monitor all collision layers.
	collision_mask = 0xFFFFFFFF
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

	var col := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = zone_radius
	col.shape = sphere
	add_child(col)

	# Visual: a translucent sphere.
	var mesh_inst := MeshInstance3D.new()
	var sphere_mesh := SphereMesh.new()
	sphere_mesh.radius = zone_radius
	sphere_mesh.height = zone_radius * 2.0
	mesh_inst.mesh = sphere_mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.5, 0.3, 1.0, 0.3)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh_inst.material_override = mat
	add_child(mesh_inst)

func _on_body_entered(_body: Node3D) -> void:
	pass

func _on_body_exited(_body: Node3D) -> void:
	pass

func _physics_process(delta: float) -> void:
	time_alive += delta
	if time_alive >= duration:
		queue_free()
		return

	# Apply velocity nudge and damage to bodies inside the zone.
	for body in get_overlapping_bodies():
		if body is EnemyVehicle or body is BossVehicle:
			var offset := body.global_position - zone_centre
			var derivative := attractor.derivative(offset)
			body.velocity += derivative * strength * delta
			if body.has_method("take_damage"):
				body.take_damage(strength * delta * 2.0, attractor_family)
		elif body is CharacterBody3D:
			var offset := body.global_position - zone_centre
			var derivative := attractor.derivative(offset)
			body.velocity += derivative * strength * delta