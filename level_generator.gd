# level_generator.gd  (Phase 7 — level generation)
class_name LevelGenerator
extends Node

# ── Configuration ─────────────────────────────────────────────────────────
@export var seed: int = 12345
@export var target_depth: int = 10
@export var debug_dump: bool = false
@export var rest_interval: int = 4
@export var junction_prob_base: float = 0.25
@export var dead_end_prob: float = 0.3
@export var generation_version: int = 2
@export var min_radius: float = 6.0
@export var max_radius: float = 20.0

var network: PipeNetwork = null
var rng: RandomNumberGenerator = null
var _graph: Array = []  # Array of SectionNode dicts
var _macro: MacroGraph = null
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

	# Clean up stale junction mesh caches from older code versions.
	_cleanup_junction_caches()

	if generation_version >= 2:
		await _generate_v2()
		return

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

	# Seal the start and every dead end / unused junction mouth.
	network.cap_open_ends()

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
	# Annotate main-path progress for the threat director.
	for node in _graph:
		var section: PipeSection = section_map.get(node["id"], null)
		if section == null:
			continue
		var depth: int = node["depth"]
		var p: float = clampf(float(depth) / float(maxi(1, target_depth)), 0.0, 1.0)
		if node["type"] == SectionType.BOSS_ARENA:
			p = 1.0
		section.main_progress = p
	_place_content(section_map)
	# Let async section _ready calls (junction CSG) settle.
	await get_tree().process_frame
	await get_tree().process_frame

func _generate_v2() -> void:
	# Build the macro topology.
	var config := {
		"main_anchors": 12,
		"anchor_spacing_min": 60.0,
		"anchor_spacing_max": 130.0,
		"clearance_radius": 40.0,
		"min_loops": 2,
		"max_loops": 4,
		"side_paths": 4,
		"side_paths_min": 3,
		"side_paths_max": 6,
		"max_loop_span": 8,
		"min_main_nodes": 8,
		"max_main_nodes": 18,
		"max_radius": 16.0,
		"min_radius": 6.0,
	}
	var macro: MacroGraph = MacroGraph.generate(config, rng)
	_macro = macro
	var v := macro.validate(config)
	if not bool(v["ok"]):
		push_warning("v2 macro validation failed: %s — falling back to v1" % str(v["errors"]))
		generation_version = 1
		await generate(network)
		return

	var zone_radius := func(zone: int) -> float:
		var max_r := 16.0
		var min_r := 6.0
		var t := float(zone - 1) / 4.0
		return lerpf(max_r, min_r, t)

	# 1. Create macro node sections.
	var node_sections: Array = []
	node_sections.resize(macro.nodes.size())
	for node in macro.nodes:
		var radius: float = zone_radius.call(node.zone)
		var is_junction := macro.degree(node.id) >= 3
		var side_count := 0
		for e in macro.edges:
			if e.from_node == node.id or e.to_node == node.id:
				if e.kind != MacroGraph.EdgeKind.MAIN:
					side_count += 1
		var packed: PackedScene
		var props: Dictionary
		if node.kind == MacroGraph.NodeKind.BOSS:
			packed = load("res://BossArena.tscn")
			props = {"entry_radius": radius + 2.0, "exit_radius": radius + 2.0, "length": 120.0}
		elif node.kind == MacroGraph.NodeKind.ENTRY:
			packed = load("res://StraightPipeSection.tscn")
			props = {"entry_radius": radius, "exit_radius": radius, "length": 100.0}
		elif node.kind == MacroGraph.NodeKind.REST or node.kind == MacroGraph.NodeKind.REWARD:
			packed = load("res://RestZone.tscn")
			props = {"entry_radius": radius + 4.0, "exit_radius": radius + 4.0, "length": 60.0}
		elif is_junction:
			packed = load("res://JunctionPipeSection.tscn")
			var has_left := side_count >= 1
			var has_right := side_count >= 2
			props = {
				"tube_radius": radius,
				"trunk_length": 40.0,
				"branch_angle": 25.0,
				"branch_length": 60.0,
				"decision_offset": 15.0,
				"blend_length": 0.0,
				"has_trunk": true,
				"left_branch": has_left,
				"right_branch": has_right,
			}
		else:
			packed = load("res://StraightPipeSection.tscn")
			props = {"entry_radius": radius, "exit_radius": radius, "length": 40.0}
		if packed == null:
			push_error("v2: failed to load scene for node %d" % node.id)
			continue
		var section: PipeSection = packed.instantiate() as PipeSection
		if section == null:
			push_error("v2: failed to instantiate section for node %d" % node.id)
			continue
		for key in props:
			section.set(key, props[key])
		section.global_transform = Transform3D(Basis.IDENTITY, node.position)
		network.add_child(section)
		network.sections.append(section)
		# Build port list: entry(0), exit(1), then side ports.
		var ports: Array[Marker3D] = []
		ports.append(section.entry)
		ports.append(section.exit)
		if section is JunctionPipeSection:
			var j := section as JunctionPipeSection
			for m in j.exits:
				if m != null and m != j.exit:
					ports.append(m)
		# ensure at least side slots exist as null placeholders handled by size
		section.exits = ports.duplicate()
		node_sections[node.id] = section

	# Annotate main-path progress for the threat director.
	var main_count := 0
	for node in macro.nodes:
		if node.main_index >= 0:
			main_count += 1
	for node in macro.nodes:
		var section: PipeSection = node_sections[node.id]
		if section == null:
			continue
		if node.main_index >= 0 and main_count > 1:
			section.main_progress = clampf(float(node.main_index) / float(main_count - 1), 0.0, 1.0)
		else:
			# side/reward: inherit nearest main node's progress
			var best := 0.0
			var best_d := INF
			for m in macro.nodes:
				if m.main_index < 0:
					continue
				var d := m.position.distance_to(node.position)
				if d < best_d:
					best_d = d
					if main_count > 1:
						best = clampf(float(m.main_index) / float(main_count - 1), 0.0, 1.0)
			section.main_progress = best
		if node.kind == MacroGraph.NodeKind.BOSS:
			section.main_progress = 1.0

	# Let junction CSG meshes build before computing ring centers.
	for i in range(15):
		await get_tree().process_frame

	# Align junction exit markers to their actual mesh mouth centres, so
	# attached connectors and the seam harness agree with the geometry.
	for node in macro.nodes:
		var section: PipeSection = node_sections[node.id]
		if not (section is JunctionPipeSection):
			continue
		var j := section as JunctionPipeSection
		for i in range(j.exits.size()):
			var marker: Marker3D = j.exits[i]
			var radius := j.get_exit_radius(i)
			var center := _mesh_ring_center(j, marker, radius)
			marker.global_position = center

	# 2. Reassign port indices for each macro edge.
	var side_counter: Dictionary = {}
	for node in macro.nodes:
		side_counter[node.id] = 2
	for e in macro.edges:
		if e.kind == MacroGraph.EdgeKind.MAIN:
			e.from_port = 1
			e.to_port = 0
		elif e.kind == MacroGraph.EdgeKind.SIDE:
			e.from_port = side_counter[e.from_node]
			side_counter[e.from_node] += 1
			e.to_port = 0
		else:  # LOOP
			e.from_port = side_counter[e.from_node]
			side_counter[e.from_node] += 1
			if macro.degree(e.to_node) >= 3:
				e.to_port = side_counter[e.to_node]
				side_counter[e.to_node] += 1
			else:
				e.to_port = 1

	# 3. Create connectors for each macro edge.
	var connector_packed := load("res://ConnectorPipeSection.tscn")
	for e in macro.edges:
		var from_sec: PipeSection = node_sections[e.from_node]
		var to_sec: PipeSection = node_sections[e.to_node]
		if from_sec == null or to_sec == null:
			continue
		var from_port_idx: int = e.from_port
		var to_port_idx: int = e.to_port
		if from_port_idx < 0 or from_port_idx >= from_sec.exits.size():
			from_port_idx = clampi(from_port_idx, 0, from_sec.exits.size() - 1)
		if to_port_idx < 0 or to_port_idx >= to_sec.exits.size():
			to_port_idx = clampi(to_port_idx, 0, to_sec.exits.size() - 1)
		var from_marker: Marker3D = from_sec.exits[from_port_idx]
		var to_marker: Marker3D = to_sec.exits[to_port_idx]
		var radius := from_sec.get_exit_radius(from_port_idx)
		# Match the actual mesh boundary rings, not just the markers, so seams
		# close without gaps even when CSG/connector rings are slightly offset.
		var from_center := _mesh_ring_center(from_sec, from_marker, radius)
		var to_center := _mesh_ring_center(to_sec, to_marker, radius)
		var start_transform := Transform3D(from_marker.global_transform.basis, from_center)
		var end_pos := to_center
		var end_tangent := to_marker.global_transform.basis.z
		var end_point_local := start_transform.affine_inverse() * end_pos
		var end_tangent_local := start_transform.basis.inverse() * end_tangent
		var props := {
			"end_point": end_point_local,
			"end_tangent": end_tangent_local,
			"tube_radius": radius,
		}
		if connector_packed == null:
			continue
		var conn := connector_packed.instantiate() as PipeSection
		if conn == null:
			continue
		for key in props:
			conn.set(key, props[key])
		conn.global_transform = start_transform
		network.add_child(conn)
		network.sections.append(conn)
		conn.attached_from = from_sec
		conn.attached_exit = from_port_idx

	# 4. Place content.
	_place_content_v2(node_sections, macro)

	# Let async section _ready calls settle.
	for i in range(10):
		await get_tree().process_frame

	if debug_dump:
		var summary := _macro.hash_summary() if _macro != null else ""
		var _gs = get_node_or_null("/root/GameState")
		if _gs:
			_gs.last_graph_summary = summary
		var f := FileAccess.open("user://level_graph_%d.txt" % seed, FileAccess.WRITE)
		if f:
			f.store_string(summary)
			f.close()

	# Seal the start and every dead end / unused mouth.
	network.cap_open_ends()

func _mesh_ring_center(section: PipeSection, marker: Marker3D, radius: float) -> Vector3:
	# Average the boundary vertices near a marker to find the actual mesh mouth
	# centre (CSG seams are rarely perfect circles centred on the marker).
	var mi: MeshInstance3D = section.mesh_instance
	if mi == null or mi.mesh == null:
		return marker.global_position
	var center := marker.global_position
	var axis := marker.global_transform.basis.z.normalized()
	var sum := Vector3.ZERO
	var count := 0
	var edges := PipeSection.welded_boundary_edges(mi)
	for e in edges:
		for p in e:
			var rel: Vector3 = p - center
			var along := rel.dot(axis)
			var radial := (rel - axis * along).length()
			if absf(along) < 1.0 and radial > radius * 0.35 and radial < radius * 1.65:
				sum += p
				count += 1
	if count < 6:
		return marker.global_position
	return sum / float(count)

func _place_content_v2(node_sections: Array, macro: MacroGraph) -> void:
	# Boss.
	for node in macro.nodes:
		if node.kind != MacroGraph.NodeKind.BOSS:
			continue
		var section: PipeSection = node_sections[node.id]
		if section == null:
			continue
		var boss_scene = load("res://BossVehicle.tscn")
		if boss_scene == null:
			continue
		var boss = boss_scene.instantiate()
		if boss == null:
			continue
		boss.network = network
		boss.target = get_node_or_null("Vehicle")
		var sec_len: float = section.get("length") if section.get("length") != null else 100.0
		boss.arena_center = section.global_position
		add_child(boss)
		boss.global_position = boss.arena_center

	# Signs at junctions.
	for node in macro.nodes:
		if macro.degree(node.id) < 3:
			continue
		var section: PipeSection = node_sections[node.id]
		if section == null:
			continue
		var sign_scene = load("res://Sign.tscn")
		if sign_scene == null:
			continue
		var sign = sign_scene.instantiate()
		if sign == null:
			continue
		sign.text = "JUNCTION"
		sign.position = section.global_position + Vector3(0.0, 8.0, 0.0)
		add_child(sign)

	# Enemy spawner.
	# Zone boundary signs.
	var prev_zone := 1
	for node in macro.nodes:
		if node.main_index < 0:
			continue
		if node.zone != prev_zone:
			prev_zone = node.zone
			var zsection: PipeSection = node_sections[node.id]
			if zsection == null:
				continue
			var zsign_scene = load("res://Sign.tscn")
			if zsign_scene == null:
				continue
			var zsign = zsign_scene.instantiate()
			if zsign == null:
				continue
			zsign.text = "ZONE %d" % node.zone
			zsign.position = zsection.global_position + Vector3(0.0, 8.0, 0.0)
			add_child(zsign)

	# Threat director.
	var td = ThreatDirector.new()
	td.chaser_scene = load("res://ChaserEnemy.tscn")
	td.ambusher_scene = load("res://AmbusherEnemy.tscn")
	td.tank_scene = load("res://TankEnemy.tscn")
	td.network = network
	td.target = get_node_or_null("Vehicle")
	td.base_spawn_interval = 3.0
	td.min_spawn_interval = 0.6
	td.base_max_alive = 8
	td.max_alive_cap = 50
	td.elite_start_progress = 0.45
	td.champion_start_progress = 0.8
	add_child(td)

	# Game manager.
	var gm = GameManager.new()
	add_child(gm)

	# Game HUD.
	var hud_scene = load("res://GameHUD.tscn")
	if hud_scene:
		var hud = hud_scene.instantiate()
		if hud:
			add_child(hud)

	# Audio manager.
	var audio = AudioManager.new()
	add_child(audio)

	# Pause menu.
	var pause_menu = load("res://PauseMenu.tscn").instantiate()
	add_child(pause_menu)

	# Crafting UI.
	var crafting_scene = load("res://CraftingUI.tscn")
	if crafting_scene:
		var crafting_ui = crafting_scene.instantiate()
		if crafting_ui:
			add_child(crafting_ui)
			var vehicle = get_node_or_null("Vehicle")
			if vehicle:
				crafting_ui.bind_vehicle(vehicle)
func _cleanup_junction_caches() -> void:
	var dir := DirAccess.open("user://")
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if not dir.current_is_dir() and name.begins_with("junction_mesh_") and name.ends_with(".res") and not name.begins_with("junction_mesh_v6_"):
			dir.remove(name)
		name = dir.get_next()
	dir.list_dir_end()

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
		var sign_scene = load("res://Sign.tscn")
		if sign_scene:
			var sign = sign_scene.instantiate()
			if sign:
				sign.text = "JUNCTION"
				sign.position = section.entry.global_position - section.global_transform.basis.z * 15.0 + Vector3(0.0, 8.0, 0.0)
				add_child(sign)

	# Place boss.
	for node in _graph:
		if node["type"] != SectionType.BOSS_ARENA:
			continue
		var section: PipeSection = section_map[node["id"]]
		var boss_scene = load("res://BossVehicle.tscn")
		if boss_scene:
			var boss = boss_scene.instantiate()
			if boss:
				boss.network = network
				boss.target = get_node_or_null("Vehicle")
				var sec_len: float = section.get("length") if section.get("length") != null else 100.0
				boss.arena_center = section.entry.global_position + section.global_transform.basis.z * (sec_len * 0.5)
				add_child(boss)
				boss.global_position = boss.arena_center

	# Place threat director.
	var td = ThreatDirector.new()
	td.chaser_scene = load("res://ChaserEnemy.tscn")
	td.ambusher_scene = load("res://AmbusherEnemy.tscn")
	td.tank_scene = load("res://TankEnemy.tscn")
	td.network = network
	td.target = get_node_or_null("Vehicle")
	td.base_spawn_interval = 3.0
	td.min_spawn_interval = 0.6
	td.base_max_alive = 8
	td.max_alive_cap = 50
	td.elite_start_progress = 0.45
	td.champion_start_progress = 0.8
	add_child(td)

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