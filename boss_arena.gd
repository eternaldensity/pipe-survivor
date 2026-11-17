# boss_arena.gd  (Phase 6 — dedicated arena chamber)
class_name BossArena
extends StraightPipeSection

func _ready() -> void:
	super._ready()
	if mesh_instance:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.5, 0.2, 0.2)
		mat.cull_mode = BaseMaterial3D.CULL_BACK
		mesh_instance.material_override = mat
	# Distinct geometry: interior pillars around the arena.
	_add_pillars()

func _add_pillars() -> void:
	var r := maxf(entry_radius, exit_radius) * 0.6
	var pillar_count := 6
	for i in range(pillar_count):
		var a := TAU * float(i) / float(pillar_count)
		var pillar := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 1.2
		cyl.bottom_radius = 1.2
		cyl.height = length * 0.9
		cyl.radial_segments = 12
		pillar.mesh = cyl
		pillar.position = Vector3(cos(a) * r, sin(a) * r, 0.0)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.35, 0.15, 0.15)
		mat.cull_mode = BaseMaterial3D.CULL_BACK
		pillar.material_override = mat
		add_child(pillar)
		# Collision.
		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 1
		var col := CollisionShape3D.new()
		var shape := CylinderShape3D.new()
		shape.radius = 1.2
		shape.height = length * 0.9
		col.shape = shape
		col.rotation = Vector3(PI * 0.5, 0.0, 0.0)
		body.add_child(col)
		pillar.add_child(body)