# enemy_spawner.gd  (Phase 5 — first pass)
class_name EnemySpawner
extends Node3D

@export var enemy_scene: PackedScene
@export var network: PipeNetwork
@export var target: Node3D
@export var spawn_interval: float = 3.0
@export var max_enemies: int = 10

var _timer: float = 0.0
var _enemies: Array[Node3D] = []

func _process(delta: float) -> void:
	_timer += delta
	if _timer >= spawn_interval:
		_timer = 0.0
		_spawn_if_possible()

func _spawn_if_possible() -> void:
	# Clean up dead enemies.
	var alive: Array[Node3D] = []
	for e in _enemies:
		if is_instance_valid(e):
			alive.append(e)
	_enemies = alive

	if _enemies.size() >= max_enemies:
		return
	if network == null or target == null:
		return
	if enemy_scene == null:
		return

	# Spawn at a section behind the player.
	var spawn_pos := _find_spawn_position()
	if spawn_pos == Vector3.ZERO:
		return

	var enemy := enemy_scene.instantiate() as EnemyVehicle
	if enemy == null:
		return
	enemy.network = network
	enemy.target = target
	var parent := get_parent()
	if parent:
		parent.add_child(enemy)
		enemy.global_position = spawn_pos
	_enemies.append(enemy)

func _find_spawn_position() -> Vector3:
	# Find a section behind the player (lower progress along the network).
	if network == null or target == null:
		return Vector3.ZERO
	var target_section := network.get_section_at(target.global_position)
	if target_section == null:
		return Vector3.ZERO

	# Find a section that's not the current one, preferably behind.
	var candidates: Array[PipeSection] = []
	for s in network.sections:
		if s != target_section:
			candidates.append(s)
	if candidates.is_empty():
		return Vector3.ZERO

	# Pick a random section behind the player.
	var pick := candidates[randi() % candidates.size()]
	# Place at the section's entry, on the wall.
	var origin := pick.entry.global_position
	var axis := pick.exit.global_position - pick.entry.global_position
	if axis.length_squared() < 1e-4:
		axis = Vector3(0, 0, 1)
	axis = axis.normalized()
	var perp := axis.cross(Vector3.UP).normalized()
	if perp.length_squared() < 0.5:
		perp = axis.cross(Vector3.RIGHT).normalized()
	return origin + perp * (pick.get_entry_radius() * 0.9) + axis * (pick.entry.global_position.distance_to(pick.exit.global_position) * 0.5)