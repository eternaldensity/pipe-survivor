# enemy_spawner.gd  (Phase 5 — archetypes + topology ambushes)
class_name EnemySpawner
extends Node3D

@export var chaser_scene: PackedScene
@export var ambusher_scene: PackedScene
@export var network: PipeNetwork
@export var target: Node3D
@export var spawn_interval: float = 3.0
@export var max_enemies: int = 10
@export var ambush_distance: float = 50.0  # how far behind a junction to spawn ambushers

var _timer: float = 0.0
var _enemies: Array[Node3D] = []
var _visited: Array[PipeSection] = []
var _ambush_junctions: Array[JunctionPipeSection] = []
var _last_section: PipeSection = null

func _process(delta: float) -> void:
	_timer += delta
	if _timer >= spawn_interval:
		_timer = 0.0
		_spawn_if_possible()
	_update_visited()

func _update_visited() -> void:
	if network == null or target == null:
		return
	var current := network.get_section_at(target.global_position)
	if current == null:
		return
	if current != _last_section:
		_last_section = current
		if not _visited.has(current):
			_visited.append(current)
			# If the player passed a junction, queue ambushes at untraveled exits.
			if current is JunctionPipeSection:
				var j := current as JunctionPipeSection
				if not _ambush_junctions.has(j):
					_ambush_junctions.append(j)
					_spawn_ambushes_at_junction(j)

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

	# Spawn a chaser from a section behind the player.
	_spawn_chaser()

func _spawn_chaser() -> void:
	if chaser_scene == null:
		return
	var spawn_pos := _find_spawn_position_behind()
	if spawn_pos == Vector3.ZERO:
		return
	var enemy := chaser_scene.instantiate() as EnemyVehicle
	if enemy == null:
		return
	enemy.enemy_type = EnemyVehicle.EnemyType.CHASER
	enemy.network = network
	enemy.target = target
	# Chasers are weak to volatile (high-rho) sigils with high lobe count.
	enemy.weakness_family = "Lorenz"
	enemy.weakness_multiplier = 1.5
	enemy.weakness_rho_above = 30.0  # weak when spell rho > 30
	enemy.weakness_feature = "high_lobe"
	enemy.weakness_feature_threshold = 3.0
	var parent := get_parent()
	if parent:
		parent.add_child(enemy)
		enemy.global_position = spawn_pos
	_enemies.append(enemy)

func _spawn_ambushes_at_junction(j: JunctionPipeSection) -> void:
	if ambusher_scene == null:
		return
	# Spawn an ambusher at each exit the player did NOT take.
	for i in range(j.exits.size()):
		var exit_marker := j.exits[i]
		# Skip the exit the player is heading toward (the one they came from
		# or are going to). We approximate by checking which exit is closest
		# to the player's current position.
		var dist_to_exit := target.global_position.distance_to(exit_marker.global_position)
		# If the exit is far from the player, it's an untraveled branch.
		if dist_to_exit > ambush_distance:
			var spawn_pos := exit_marker.global_position
			# Offset slightly into the branch.
			var axis := (exit_marker.global_position - j.global_position).normalized()
			if axis.length_squared() < 1e-4:
				axis = Vector3(0, 0, 1)
			spawn_pos += axis * 5.0
			var enemy := ambusher_scene.instantiate() as EnemyVehicle
			if enemy == null:
				continue
			enemy.enemy_type = EnemyVehicle.EnemyType.AMBUSHER
			enemy.network = network
			enemy.target = target
			# Ambushers are resistant but weak to stable (low-rho) sigils.
			enemy.weakness_family = "Lorenz"
			enemy.weakness_multiplier = 2.0
			enemy.resistance = 0.5
			enemy.weakness_rho_below = 20.0  # weak when spell rho < 20 (stable sigils)
			enemy.weakness_feature = "high_symmetry"
			enemy.weakness_feature_threshold = 0.7
			var parent := get_parent()
			if parent:
				parent.add_child(enemy)
				enemy.global_position = spawn_pos
			_enemies.append(enemy)

func _find_spawn_position_behind() -> Vector3:
	# Find a section the player has already passed (behind them).
	if _visited.is_empty():
		return Vector3.ZERO
	# Pick a random visited section that's not the current one.
	var target_section := network.get_section_at(target.global_position)
	var candidates: Array[PipeSection] = []
	for s in _visited:
		if s != target_section:
			candidates.append(s)
	if candidates.is_empty():
		return Vector3.ZERO
	var pick := candidates[randi() % candidates.size()]
	var origin := pick.entry.global_position
	var axis := pick.exit.global_position - pick.entry.global_position
	if axis.length_squared() < 1e-4:
		axis = Vector3(0, 0, 1)
	axis = axis.normalized()
	var perp := axis.cross(Vector3.UP).normalized()
	if perp.length_squared() < 0.5:
		perp = axis.cross(Vector3.RIGHT).normalized()
	var mid := (pick.entry.global_position + pick.exit.global_position) * 0.5
	return mid + perp * (pick.get_entry_radius() * 0.8)