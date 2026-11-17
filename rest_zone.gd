@tool
# rest_zone.gd  (Phase 3/Phase E — chamber as a pipe section with reward type)
class_name RestZone
extends StraightPipeSection

enum RewardType { HEAL, UPGRADE, SIGIL }

@export var slow_factor: float = 0.5
@export var reward_type: RewardType = RewardType.UPGRADE

@onready var area: Area3D = $Area3D

var _reward_claimed: bool = false

func _ready() -> void:
	super._ready()
	if mesh_instance:
		var mat := StandardMaterial3D.new()
		match reward_type:
			RewardType.HEAL:
				mat.albedo_color = Color(0.9, 0.4, 0.4)
			RewardType.SIGIL:
				mat.albedo_color = Color(0.7, 0.4, 1.0)
			_:
				mat.albedo_color = Color(0.3, 0.8, 0.4)
		mat.cull_mode = BaseMaterial3D.CULL_BACK
		mesh_instance.material_override = mat

	if area:
		area.body_entered.connect(_on_body_entered)
		area.body_exited.connect(_on_body_exited)
		var col := area.get_node_or_null("CollisionShape3D") as CollisionShape3D
		if col:
			var cs := CylinderShape3D.new()
			cs.radius = maxf(entry_radius, exit_radius)
			cs.height = length
			col.shape = cs
			col.position = Vector3(0.0, 0.0, 0.0)
			col.rotation = Vector3(PI * 0.5, 0.0, 0.0)

func _on_body_entered(body: Node3D) -> void:
	if body is Vehicle:
		var v := body as Vehicle
		if v:
			v.rest_zone_inside = true
			if not _reward_claimed:
				_reward_claimed = true
				match reward_type:
					RewardType.HEAL:
						v.health = minf(v.max_health, v.health + 60.0)
					RewardType.SIGIL:
						v.health = minf(v.max_health, v.health + 25.0)
						v.speed *= 1.05
					_:
						pass  # UPGRADE: crafting UI handles it

func _on_body_exited(body: Node3D) -> void:
	if body is Vehicle:
		var v := body as Vehicle
		if v:
			v.rest_zone_inside = false

func contains_point(world_pos: Vector3) -> bool:
	return super.contains_point(world_pos)