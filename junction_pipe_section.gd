@tool
# junction_pipe_section.gd  (skeleton — Phase 2 in progress)
class_name JunctionPipeSection
extends PipeSection

@export var tube_radius   : float = 10.0
@export var trunk_length  : float = 50.0
@export var branch_angle  : float = 30.0   # degrees, half-spread of the two branches
@export var branch_length : float = 80.0

@onready var mesh_instance : MeshInstance3D = $MeshInstance3D

func _ready() -> void:
	# Entry at origin; trunk continues straight; two branches peel off symmetrically.
	entry.position    = Vector3(0.0, 0.0, 0.0)
	# Primary exit = trunk (straight ahead)
	exit.position     = Vector3(0.0, 0.0, trunk_length)
	# Extra exits
	var left  := get_node_or_null("ExitLeft")  as Marker3D
	var right := get_node_or_null("ExitRight") as Marker3D
	var a := deg_to_rad(branch_angle)
	if left:
		left.position = Vector3(-sin(a) * branch_length, 0.0, cos(a) * branch_length)
		left.rotation = Vector3(0.0, -a, 0.0)
	if right:
		right.position = Vector3(sin(a) * branch_length, 0.0, cos(a) * branch_length)
		right.rotation = Vector3(0.0, a, 0.0)

	exits = [exit]
	if left:  exits.append(left)
	if right: exits.append(right)

	if Engine.is_editor_hint():
		notify_property_list_changed()
		return

func get_tube_properties(world_pos: Vector3) -> Dictionary:
	# Placeholder: treat the whole junction as a straight trunk.
	var fwd := global_transform.basis.z
	var to_pos := world_pos - entry.global_position
	var along := clampf(to_pos.dot(fwd), 0.0, trunk_length)
	return {
		"axis":   fwd,
		"origin": entry.global_position + fwd * along,
		"radius": tube_radius,
	}

func contains_point(world_pos: Vector3) -> bool:
	var local := to_local(world_pos)
	return abs(local.z) < (trunk_length + branch_length) * 0.5 + 5.0 \
		and Vector2(local.x, local.y).length() < tube_radius + 5.0