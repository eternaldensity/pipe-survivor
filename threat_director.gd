# threat_director.gd  (Phase D — VS-like spawn director)
class_name ThreatDirector
extends Node

@export var chaser_scene: PackedScene
@export var ambusher_scene: PackedScene
@export var tank_scene: PackedScene
@export var network: PipeNetwork
@export var target: Node3D

# Tunables.
@export var base_spawn_interval: float = 3.0
@export var min_spawn_interval: float = 0.6
@export var base_max_alive: int = 8
@export var max_alive_cap: int = 50
@export var min_spawn_distance: float = 25.0
@export var max_spawn_distance: float = 80.0
@export var elite_start_progress: float = 0.45
@export var champion_start_progress: float = 0.8
@export var ambush_distance: float = 50.0

var progress: float = 0.0  # furthest main-path progress reached (monotonic)
var _timer: float = 0.0
var _enemies: Array[Node3D] = []
var _visited: Array[PipeSection] = []
var _ambush_junctions: Array[JunctionPipeSection] = []
var _last_section: PipeSection = null
var _breather_timer: float = 0.0
var _wave_timer: float = 0.0
var _next_wave: float = 60.0
var _boss: BossVehicle = null
var _boss_scaled: bool = false

enum State { AMBIENT, PRESSURE, WAVE, BREATHER, BOSS }
var _state: int = State.AMBIENT

func _ready() -> void:
	# Find boss in the scene (may be added later; re-check in _process).
	pass

func _process(delta: float) -> void:
	# Update progress from the player's current section.
	if network != null and target != null:
		var cur := network.get_section_at(target.global_position)
		if cur != null:
			if cur.main_progress > progress:
				progress = cur.main_progress
			if cur != _last_section:
				_last_section = cur
				if not _visited.has(cur):
					_visited.append(cur)
					if cur is JunctionPipeSection:
						var j := cur as JunctionPipeSection
						if not _ambush_junctions.has(j):
							_ambush_junctions.append(j)
							_spawn_ambushes_at_junction(j)
					if cur is RestZone:
						_breather_timer = 10.0

	# Find boss if not yet.
	if _boss == null:
		for c in get_parent().get_children():
			if c is BossVehicle:
				_boss = c
				break

	# Scale boss once when the player is near the end.
	if _boss != null and not _boss_scaled and progress >= 0.9:
		_boss_scaled = true
		if _boss.has_method("apply_threat_scale"):
			_boss.apply_threat_scale(_stat_scale())

	# State machine.
	if _boss != null and is_instance_valid(_boss) and target != null:
		var boss_section := network.get_section_at(_boss.global_position) if network else null
		var player_section := network.get_section_at(target.global_position) if network else null
		if boss_section != null and player_section == boss_section:
			_state = State.BOSS
		elif _breather_timer > 0.0:
			_state = State.BREATHER
		elif _wave_timer >= _next_wave:
			_state = State.WAVE
		else:
			_state = State.AMBIENT
	else:
		if _breather_timer > 0.0:
			_state = State.BREATHER
		elif _wave_timer >= _next_wave:
			_state = State.WAVE
		else:
			_state = State.AMBIENT

	if _breather_timer > 0.0:
		_breather_timer -= delta
	if _wave_timer < _next_wave:
		_wave_timer += delta

	# Cleanup dead enemies.
	var alive: Array[Node3D] = []
	for e in _enemies:
		if is_instance_valid(e):
			alive.append(e)
	_enemies = alive

	# Spawn timer.
	_timer += delta
	var interval := _spawn_interval()
	if _state == State.BREATHER:
		interval *= 2.0
	if _timer >= interval:
		_timer = 0.0
		_spawn_batch()

	if _state == State.WAVE:
		_spawn_wave()
		_wave_timer = 0.0
		_next_wave = randf_range(45.0, 75.0)

func _stat_scale() -> float:
	return 1.0 + 0.12 * (progress * 4.0)  # 1.0..1.48

func _density_factor() -> float:
	# 0..1 density ramp, plateaus after 0.6.
	return clampf(progress / 0.6, 0.0, 1.0)

func _quality_factor() -> float:
	return clampf((progress - 0.4) / 0.6, 0.0, 1.0)

func _spawn_interval() -> float:
	return lerpf(base_spawn_interval, min_spawn_interval, _density_factor())

func _max_alive() -> int:
	var v := int(lerpf(float(base_max_alive), float(max_alive_cap), _density_factor()))
	return clampi(v, base_max_alive, max_alive_cap)

func _elite_chance() -> float:
	if progress < elite_start_progress:
		return 0.0
	var t := (progress - elite_start_progress) / (1.0 - elite_start_progress)
	return t * t * 0.25

func _batch_size() -> int:
	return 1 + int(progress * 4.0)

func _spawn_batch() -> void:
	if _enemies.size() >= _max_alive():
		return
	if network == null or target == null:
		return
	if _state == State.BOSS:
		return
	var n := _batch_size()
	for i in range(n):
		if _enemies.size() >= _max_alive():
			break
		_spawn_one(false)

func _spawn_one(elite: bool) -> void:
	if network == null or target == null:
		return
	var spawn_pos := _find_spawn_position()
	if spawn_pos == Vector3.ZERO:
		return
	# Pick archetype by progress.
	var roll := randf()
	var scene: PackedScene = chaser_scene
	var etype := EnemyVehicle.EnemyType.CHASER
	if progress < 0.2:
		scene = chaser_scene
		etype = EnemyVehicle.EnemyType.CHASER
	elif progress < 0.4:
		if roll < 0.25 and ambusher_scene:
			scene = ambusher_scene
			etype = EnemyVehicle.EnemyType.AMBUSHER
		else:
			scene = chaser_scene
			etype = EnemyVehicle.EnemyType.CHASER
	elif progress < 0.6:
		if roll < 0.2 and tank_scene:
			scene = tank_scene
			etype = EnemyVehicle.EnemyType.TANK
		elif roll < 0.45 and ambusher_scene:
			scene = ambusher_scene
			etype = EnemyVehicle.EnemyType.AMBUSHER
		else:
			scene = chaser_scene
			etype = EnemyVehicle.EnemyType.CHASER
	else:
		if roll < 0.25 and tank_scene:
			scene = tank_scene
			etype = EnemyVehicle.EnemyType.TANK
		elif roll < 0.5 and ambusher_scene:
			scene = ambusher_scene
			etype = EnemyVehicle.EnemyType.AMBUSHER
		else:
			scene = chaser_scene
			etype = EnemyVehicle.EnemyType.CHASER

	if scene == null:
		return
	var enemy := scene.instantiate() as EnemyVehicle
	if enemy == null:
		return
	enemy.enemy_type = etype
	enemy.network = network
	enemy.target = target
	# Stat scaling.
	var scale := _stat_scale()
	enemy.speed *= sqrt(scale)
	enemy.health *= scale
	# Elite.
	if elite or randf() < _elite_chance():
		enemy.health *= 3.0
		enemy.speed *= 1.3
		# Tint via a label marker.
		var lbl := Label3D.new()
		lbl.text = "ELITE"
		lbl.modulate = Color(1.0, 0.85, 0.2)
		lbl.position = Vector3(0.0, 2.2, 0.0)
		enemy.add_child(lbl)
	var parent := get_parent()
	if parent:
		parent.add_child(enemy)
		enemy.global_position = spawn_pos
	_enemies.append(enemy)

func _spawn_wave() -> void:
	# Coordinated pack from a loop/side port or behind.
	if network == null or target == null:
		return
	var n := 3 + int(progress * 2.0)
	for i in range(n):
		if _enemies.size() >= _max_alive():
			break
		_spawn_one(i == 0 and progress >= champion_start_progress)

func _find_spawn_position() -> Vector3:
	if _visited.is_empty():
		return Vector3.ZERO
	var target_section := network.get_section_at(target.global_position)
	var candidates: Array[PipeSection] = []
	for s in _visited:
		if s != target_section:
			candidates.append(s)
	if candidates.is_empty():
		return Vector3.ZERO
	# Prefer sections behind the player (lower main_progress).
	candidates.sort_custom(func(a, b): return a.main_progress < b.main_progress)
	var pick: PipeSection
	if candidates.size() > 3 and randf() < 0.6:
		pick = candidates[randi() % mini(3, candidates.size())]
	else:
		pick = candidates[randi() % candidates.size()]
	var axis := pick.exit.global_position - pick.entry.global_position
	if axis.length_squared() < 1e-4:
		axis = Vector3(0, 0, 1)
	axis = axis.normalized()
	var perp := axis.cross(Vector3.UP).normalized()
	if perp.length_squared() < 0.5:
		perp = axis.cross(Vector3.RIGHT).normalized()
	var mid := (pick.entry.global_position + pick.exit.global_position) * 0.5
	var pos := mid + perp * (pick.get_entry_radius() * 0.8)
	# Distance check.
	if target != null:
		var d := pos.distance_to(target.global_position)
		if d < min_spawn_distance or d > max_spawn_distance:
			# try center instead
			pos = mid
			d = pos.distance_to(target.global_position)
			if d < min_spawn_distance or d > max_spawn_distance:
				return Vector3.ZERO
	return pos

func _spawn_ambushes_at_junction(j: JunctionPipeSection) -> void:
	if ambusher_scene == null:
		return
	for i in range(j.exits.size()):
		var exit_marker := j.exits[i]
		var dist_to_exit := target.global_position.distance_to(exit_marker.global_position) if target else 0.0
		if dist_to_exit > ambush_distance:
			var spawn_pos := exit_marker.global_position
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
			var parent := get_parent()
			if parent:
				parent.add_child(enemy)
				enemy.global_position = spawn_pos
				_enemies.append(enemy)