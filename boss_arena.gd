# boss_arena.gd  (Phase 6 — dedicated arena chamber)
class_name BossArena
extends StraightPipeSection

func _ready() -> void:
	entry_radius = 35.0
	exit_radius = 35.0
	length = 150.0
	super._ready()
	if mesh_instance:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.5, 0.2, 0.2)
		mat.cull_mode = BaseMaterial3D.CULL_BACK
		mesh_instance.material_override = mat