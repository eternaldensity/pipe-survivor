@tool
# rest_zone.gd  (Phase 3 — first pass)
class_name RestZone
extends Node3D

@export var radius: float = 15.0
@export var length: float = 60.0

@onready var mesh_instance : MeshInstance3D = $MeshInstance3D
@onready var area : Area3D = $Area3D

func _ready() -> void:
	add_to_group("rest_zones")
	# Wide chamber visual.
	var m := CylinderMesh.new()
	m.top_radius = radius
	m.bottom_radius = radius
	m.height = length
	m.radial_segments = PipeSection.RING_SEGMENTS
	m.cap_top = false
	m.cap_bottom = false
	mesh_instance.mesh = m
	mesh_instance.position = Vector3(0.0, 0.0, length * 0.5)
	mesh_instance.basis = Basis(Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(0, -1, 0))

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 0.8, 0.4)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh_instance.material_override = mat

	# Trigger collision shape.
	var col := $Area3D/CollisionShape3D as CollisionShape3D
	if col:
		var cs := CylinderShape3D.new()
		cs.radius = radius
		cs.height = length
		col.shape = cs
		col.position = Vector3(0.0, 0.0, length * 0.5)
		col.rotation = Vector3(PI * 0.5, 0.0, 0.0)

	area.body_entered.connect(_on_body_entered)
	area.body_exited.connect(_on_body_exited)

func _on_body_entered(body: Node3D) -> void:
	if body is CharacterBody3D:
		var v := body as Vehicle
		if v:
			v.rest_zone_inside = true

func _on_body_exited(body: Node3D) -> void:
	if body is CharacterBody3D:
		var v := body as Vehicle
		if v:
			v.rest_zone_inside = false