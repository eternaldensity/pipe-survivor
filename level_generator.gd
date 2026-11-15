# level_generator.gd  (Phase 7 — level generation)
class_name LevelGenerator
extends Node

# ── Configuration ─────────────────────────────────────────────────────────
@export var seed: int = 12345
@export var target_depth: int = 10
@export var rest_interval: int = 4
@export var junction_prob_base: float = 0.25
@export var dead_end_prob: float = 0.3
@export var min_radius: float = 6.0
@export var max_radius: float = 20.0

var network: PipeNetwork = null
var rng: RandomNumberGenerator = null
var _graph: Array = []  # Array of SectionNode dicts
var _node_count: int = 0

# Section types.
enum SectionType { STRAIGHT, BEND, JUNCTION, REST_ZONE, BOSS_ARENA }

func _ready() -> void:
	rng = RandomNumberGenerator.new()
	rng.seed = seed

func generate(net: PipeNetwork) -> void:
	network = net
	_graph.clear()
	_node_count = 0
	rng.seed = seed

	# Entry: straight pipe matching the vehicle's starting radius.
	var entry := _add_node(SectionType.STRAIGHT, 1, {
		"entry_radius": 10.0, "exit_radius": 10.0, "length": 100.0
	})
	_graph[entry]["parent"] = -1

	# Generate the trunk path.
	var current := entry
	var depth := 0
	while depth < target_depth:
		var tier := _tier_for_depth(depth, target_depth)
		var next_node: int
		if depth > 0 and depth % rest_interval == 0:
			next_node = _add_rest_zone(current, tier)
		elif rng.randf() < _junction_prob(tier) and depth < target_depth - 2:
			next_node = _add_junction(current, tier)
			# _add_junction already calls _generate_branches internally.
			# If the junction has a trunk, add a trunk continuation immediately
			# so the main path follows the trunk, not a branch.
			if _get_param(_graph[next_node]["params"], "has_trunk", true):
				var trunk_cont := _add_continuation(next_node, tier)
				next_node = trunk_cont
		else:
			next_node = _add_continuation(current, tier)
		current = next_node
		depth += 1

	# Terminal: boss arena.
	var boss := _add_boss_arena(current, 5)
	_graph[boss]["parent"] = current

	# Validate and build.
	var valid := _validate()
	if not valid:
		push_warning("Level validation failed, using fallback")
		return
	await _build_network()

func _tier_for_depth(depth: int, max_depth: int) -> int:
	var t := float(depth) / float(max_depth)
	if t < 0.2:
		return 1
	elif t < 0.4:
		return 2
	elif t < 0.6:
		return 3
	elif t < 0.8:
		return 4
	else:
		return 5

func _junction_prob(tier: int) -> float:
	return junction_prob_base + tier * 0.05

func _get_param(d: Dictionary, key: String, default_val: Variant) -> Variant:
	if d.has(key):
		return d[key]
	return default_val

func _add_node(type: SectionType, tier: int, params: Dictionary) -> int:
	var node := {
		"id": _node_count,
		"type": type,
		"tier": tier,
		"params": params,
		"exits": [],
		"parent": -1,
		"depth": 0,
		"metadata": {},
	}
	_graph.append(node)
	_node_count += 1
	return _node_count - 1

func _add_continuation(parent_id: int, tier: int) -> int:
	var parent: Dictionary = _graph[parent_id]
	var parent_exit_r: float = _get_param(parent["params"], "exit_radius", _get_param(parent["params"], "tube_radius", 10.0))
	# Compute entry radius from parent with small variation.
	# Match the parent's exit radius exactly for seam continuity.
	var entry_r: float = clampf(parent_exit_r, min_radius, max_radius)
	var exit_r: float = clampf(entry_r + rng.randf_range(-1.0, 1.0), min_radius, max_radius)
	var length: float = rng.randf_range(60.0, 150.0)

	var params := {
		"entry_radius": entry_r,
		"exit_radius": exit_r,
		"length": length,
	}

	# Maybe make it a bend.
	if rng.randf() < 0.3 + tier * 0.1:
		var angle := rng.randf_range(8.0 + tier * 2.0, 15.0 + tier * 3.0)
		var roll := rng.randf_range(0.0, 360.0)
		params = {
			"tube_radius": (entry_r + exit_r) * 0.5,
			"bend_angle": angle,
			"roll_angle": roll,
			"length": length,
		}
		var node_id := _add_node(SectionType.BEND, tier, params)
		_graph[node_id]["parent"] = parent_id
		_graph[node_id]["depth"] = _graph[parent_id]["depth"] + 1
		_attach_child(parent, node_id)
		return node_id

	var node_id := _add_node(SectionType.STRAIGHT, tier, params)
	_graph[node_id]["parent"] = parent_id
	_graph[node_id]["depth"] = _graph[parent_id]["depth"] + 1
	_attach_child(parent, node_id)
	return node_id

func _attach_child(parent: Dictionary, node_id: int) -> void:
	# If parent is a junction, attach to the first null exit slot (trunk) if
	# available, otherwise append.
	if parent["type"] == SectionType.JUNCTION:
		var slot := -1
		for i in range(parent["exits"].size()):
			if parent["exits"][i] == null:
				slot = i
				break
		if slot >= 0:
			parent["exits"][slot] = node_id
		else:
			parent["exits"].append(node_id)
	else:
		parent["exits"].append(node_id)

func _add_junction(parent_id: int, tier: int) -> int:
	var parent: Dictionary = _graph[parent_id]
	var r: float = _get_param(parent["params"], "exit_radius", _get_param(parent["params"], "tube_radius", 10.0))
	r = clampf(r, min_radius, max_radius)

	var has_trunk := true  # main path always has a trunk
	var left := rng.randf() < 0.75
	var right := rng.randf() < 0.75
	if not left and not right:
		left = true  # ensure at least one branch

	var params := {
		"tube_radius": r,
		"trunk_length": rng.randf_range(80.0, 120.0),
		"branch_angle": rng.randf_range(15.0, 25.0),
		"branch_length": rng.randf_range(60.0, 100.0),
		"decision_offset": rng.randf_range(15.0, 25.0),
		"blend_length": rng.randf_range(0.0, 10.0),
		"has_trunk": has_trunk,
		"left_branch": left,
		"right_branch": right,
	}
	var node_id := _add_node(SectionType.JUNCTION, tier, params)
	_graph[node_id]["parent"] = parent_id
	_graph[node_id]["depth"] = _graph[parent_id]["depth"] + 1
	_attach_child(parent, node_id)
	_generate_branches(node_id, tier, rng)
	return node_id

func _generate_branches(junction_id: int, tier: int, r: RandomNumberGenerator) -> void:
	var junction: Dictionary = _graph[junction_id]
	var num_exits: int = (1 if junction["params"]["has_trunk"] else 0) + \
		(1 if junction["params"]["left_branch"] else 0) + \
		(1 if junction["params"]["right_branch"] else 0)
	var budget := rng.randi_range(2, 4)
	# Generate a short chain for each non-trunk exit.
	var exit_idx := 0
	if junction["params"]["has_trunk"]:
		exit_idx = 1  # skip trunk (trunk continues as main path)
	var branch_idx := 0
	for i in range(num_exits):
		if i < exit_idx:
			continue
		# Generate a sub-branch.
		var current := junction_id
		var current_exit := i
		var branch_depth := 0
		while branch_depth < budget:
			var next_node := _add_continuation_branch(current, current_exit, tier + 1)
			if next_node < 0:
				break
			current = next_node
			current_exit = 0
			branch_depth += 1
			if rng.randf() < dead_end_prob:
				break

func _add_continuation_branch(parent_id: int, exit_idx: int, tier: int) -> int:
	var parent: Dictionary = _graph[parent_id]
	var parent_exit_r: float
	if parent["type"] == SectionType.JUNCTION:
		parent_exit_r = _get_param(parent["params"], "tube_radius", 10.0)
	else:
		parent_exit_r = _get_param(parent["params"], "exit_radius", _get_param(parent["params"], "tube_radius", 10.0))
	parent_exit_r = clampf(parent_exit_r, min_radius, max_radius)

	var entry_r: float = parent_exit_r
	var exit_r: float = entry_r
	var length: float = rng.randf_range(40.0, 80.0)

	var is_bend := rng.randf() < 0.4
	var params: Dictionary
	if is_bend:
		params = {
			"tube_radius": (entry_r + exit_r) * 0.5,
			"bend_angle": rng.randf_range(8.0, 20.0),
			"roll_angle": rng.randf_range(0.0, 360.0),
			"length": length,
		}
	else:
		params = {
			"entry_radius": entry_r,
			"exit_radius": exit_r,
			"length": length,
		}

	var node_type := SectionType.BEND if is_bend else SectionType.STRAIGHT
	var node_id := _add_node(node_type, tier, params)
	_graph[node_id]["parent"] = parent_id
	_graph[node_id]["depth"] = _graph[parent_id]["depth"] + 1
	# Attach to the parent's exit.
	if parent["exits"].size() <= exit_idx:
		parent["exits"].resize(exit_idx + 1)
	parent["exits"][exit_idx] = node_id
	return node_id

func _add_rest_zone(parent_id: int, tier: int) -> int:
	var parent: Dictionary = _graph[parent_id]
	var r: float = _get_param(parent["params"], "exit_radius", _get_param(parent["params"], "tube_radius", 10.0))
	r = clampf(r, min_radius, max_radius)
	var params := {
		"entry_radius": r,
		"exit_radius": r,
		"length": 60.0,
	}
	var node_id := _add_node(SectionType.REST_ZONE, tier, params)
	_graph[node_id]["parent"] = parent_id
	_graph[node_id]["depth"] = _graph[parent_id]["depth"] + 1
	_attach_child(parent, node_id)
	return node_id

func _add_boss_arena(parent_id: int, tier: int) -> int:
	var parent: Dictionary = _graph[parent_id]
	var r: float = _get_param(parent["params"], "exit_radius", _get_param(parent["params"], "tube_radius", 10.0))
	r = clampf(r, min_radius, max_radius)
	var params := {
		"entry_radius": r,
		"exit_radius": r,
		"length": 120.0,
	}
	var node_id := _add_node(SectionType.BOSS_ARENA, tier, params)
	_graph[node_id]["parent"] = parent_id
	_graph[node_id]["depth"] = _graph[parent_id]["depth"] + 1
	_attach_child(parent, node_id)
	return node_id

func _validate() -> bool:
	# Check reachability from entry.
	var visited := {}
	var stack := [0]
	while not stack.is_empty():
		var node_id: int = stack.pop_back()
		if visited.has(node_id):
			continue
		visited[node_id] = true
		for exit_id in _graph[node_id]["exits"]:
			if exit_id != null and exit_id >= 0 and exit_id < _graph.size():
				stack.append(exit_id)
	# All nodes should be reachable.
	if visited.size() != _graph.size():
		return false
	# Check boss arena exists.
	var has_boss := false
	for node in _graph:
		if node["type"] == SectionType.BOSS_ARENA:
			has_boss = true
			break
	if not has_boss:
		return false
	# Check radius continuity.
	for node in _graph:
		if node["parent"] < 0:
			continue
		var parent: Dictionary = _graph[node["parent"]]
		var parent_r: float = _get_param(parent["params"], "exit_radius", _get_param(parent["params"], "tube_radius", 10.0))
		var child_r: float = _get_param(node["params"], "entry_radius", _get_param(node["params"], "tube_radius", 10.0))
		if absf(parent_r - child_r) > 1.0:
			return false
	return true

func _build_network() -> void:
	# Convert graph to PipeNetwork calls.
	# First pass: create all sections.
	var section_map: Dictionary = {}
	for node in _graph:
		var packed: PackedScene = _scene_for_type(node["type"])
		if packed == null:
			continue
		var props: Dictionary = node["params"].duplicate()
		var section: PipeSection
		if node["parent"] < 0:
			section = network.add_section(packed, props)
		else:
			var parent_section: PipeSection = section_map[node["parent"]]
			var exit_idx: int = 0
			# Find which exit this node is attached to.
			var parent_node: Dictionary = _graph[node["parent"]]
			for i in range(parent_node["exits"].size()):
				if parent_node["exits"][i] == node["id"]:
					exit_idx = i
					break
			if parent_section == null:
				print("NULL PARENT for node", node["id"], "parent", node["parent"])
			section = network.add_section(packed, props, parent_section, exit_idx)
		section_map[node["id"]] = section

	# Second pass: place content (rest zones, signs, enemies, boss).
	_place_content(section_map)
	# Let async section _ready calls (junction CSG) settle.
	await get_tree().process_frame
	await get_tree().process_frame
	# Seal the start and every dead end / unused junction mouth.
	network.cap_open_ends()

func _scene_for_type(type: SectionType) -> PackedScene:
	match type:
		SectionType.STRAIGHT:
			return load("res://StraightPipeSection.tscn")
		SectionType.BEND:
			return load("res://BendPipeSection.tscn")
		SectionType.JUNCTION:
			return load("res://JunctionPipeSection.tscn")
		SectionType.REST_ZONE:
			return load("res://RestZone.tscn")
		SectionType.BOSS_ARENA:
			return load("res://BossArena.tscn")
	return null

func _place_content(section_map: Dictionary) -> void:
	# Place signs before junctions.
	for node in _graph:
		if node["type"] != SectionType.JUNCTION:
			continue
		var section: PipeSection = section_map[node["id"]]
		var sign = load("res://Sign.tscn").instantiate()
		sign.text = "JUNCTION"
		sign.position = section.entry.global_position - section.global_transform.basis.z * 15.0 + Vector3(0.0, 8.0, 0.0)
		add_child(sign)

	# Place boss.
	for node in _graph:
		if node["type"] != SectionType.BOSS_ARENA:
			continue
		var section: PipeSection = section_map[node["id"]]
		var boss = load("res://BossVehicle.tscn").instantiate()
		boss.network = network
		boss.target = get_node_or_null("Vehicle")
		var sec_len: float = section.get("length") if section.get("length") != null else 100.0
		boss.arena_center = section.entry.global_position + section.global_transform.basis.z * (sec_len * 0.5)
		add_child(boss)
		boss.global_position = boss.arena_center

	# Place enemy spawner.
	var spawner = EnemySpawner.new()
	spawner.chaser_scene = load("res://ChaserEnemy.tscn")
	spawner.ambusher_scene = load("res://AmbusherEnemy.tscn")
	spawner.tank_scene = load("res://TankEnemy.tscn")
	spawner.network = network
	spawner.target = get_node_or_null("Vehicle")
	spawner.spawn_interval = 4.0
	spawner.max_enemies = 6
	add_child(spawner)

	# Place game manager.
	var gm = GameManager.new()
	add_child(gm)

	# Place game HUD.
	var hud = load("res://GameHUD.tscn").instantiate()
	add_child(hud)

	# Place audio manager.
	var audio = AudioManager.new()
	add_child(audio)

	# Place pause menu.
	var pause_menu = load("res://PauseMenu.tscn").instantiate()
	add_child(pause_menu)

	# Place crafting UI.
	var crafting_ui = load("res://CraftingUI.tscn").instantiate()
	add_child(crafting_ui)
	var vehicle = get_node_or_null("Vehicle")
	if vehicle:
		crafting_ui.bind_vehicle(vehicle)