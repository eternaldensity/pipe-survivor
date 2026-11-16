@tool
# rest_zone.gd  (Phase 3 — chamber as a pipe section)
class_name RestZone
extends StraightPipeSection

@export var slow_factor: float = 0.5

@onready var area: Area3D = $Area3D

var _vehicle_inside: bool = false

func _ready() -> void:
	# StraightPipeSection._ready sets up markers and mesh. Override mesh to a
	# distinct colour.
	super._ready()
	if mesh_instance:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.3, 0.8, 0.4)
		mat.cull_mode = BaseMaterial3D.CULL_BACK
		mesh_instance.material_override = mat

	# Area3D trigger for UI detection.
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
	if body is CharacterBody3D:
		var v := body as Vehicle
		if v:
			v.rest_zone_inside = true
			# Phase E: heal on entry.
			v.health = minf(v.max_health, v.health + 30.0)

func _on_body_exited(body: Node3D) -> void:
	if body is CharacterBody3D:
		var v := body as Vehicle
		if v:
			v.rest_zone_inside = false

# Override contains_point to use the wide radius.
func contains_point(world_pos: Vector3) -> bool:
	return super.contains_point(world_pos)