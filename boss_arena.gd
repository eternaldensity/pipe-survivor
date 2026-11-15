# boss_arena.gd  (Phase 6 — dedicated arena chamber)
class_name BossArena
extends StraightPipeSection

@export var arena_radius: float = 30.0

func _ready() -> void:
	entry_radius = arena_radius
	exit_radius = arena_radius
	length = 120.0
	super._ready()
	if mesh_instance:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.6, 0.3, 0.3)
		mat.cull_mode = BaseMaterial3D.CULL_BACK
		mesh_instance.material_override = mat