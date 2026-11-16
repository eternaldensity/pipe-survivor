# macro_graph.gd  (Phase A — topology data model + generation)
class_name MacroGraph
extends RefCounted

enum NodeKind { ENTRY, CHAMBER, JUNCTION, REST, REWARD, BOSS }
enum EdgeKind { MAIN, LOOP, SIDE }
enum Realization { CHAIN, CONNECTOR }

class Port:
	var position: Vector3 = Vector3.ZERO
	var forward: Vector3 = Vector3.FORWARD
	var up: Vector3 = Vector3.UP
	var radius: float = 10.0
	var node_id: int = -1
	var edge_id: int = -1

class MacroNode:
	var id: int = -1
	var kind: int = NodeKind.CHAMBER
	var main_index: int = -1
	var zone: int = 1
	var position: Vector3 = Vector3.ZERO
	var ports: Array[Port] = []
	var metadata: Dictionary = {}

class MacroEdge:
	var id: int = -1
	var from_node: int = -1
	var from_port: int = -1
	var to_node: int = -1
	var to_port: int = -1
	var kind: int = EdgeKind.MAIN
	var length_hint: float = 0.0
	var radius: float = 10.0
	var realization: int = Realization.CHAIN

var nodes: Array[MacroNode] = []
var edges: Array[MacroEdge] = []
var _node_count: int = 0
var _edge_count: int = 0

# ── basic builders ──────────────────────────────────────────────────────────

func add_node(kind: int, position: Vector3, main_index: int = -1) -> int:
	var n := MacroNode.new()
	n.id = _node_count
	n.kind = kind
	n.position = position
	n.main_index = main_index
	n.ports = []
	nodes.append(n)
	_node_count += 1
	return n.id

func add_port(node_id: int, position: Vector3, forward: Vector3, up: Vector3, radius: float) -> int:
	if node_id < 0 or node_id >= nodes.size():
		return -1
	var p := Port.new()
	p.position = position
	p.forward = forward.normalized() if forward.length_squared() > 1e-8 else Vector3.FORWARD
	p.up = up.normalized() if up.length_squared() > 1e-8 else Vector3.UP
	p.radius = radius
	p.node_id = node_id
	p.edge_id = -1
	nodes[node_id].ports.append(p)
	return nodes[node_id].ports.size() - 1

func add_edge(from_node: int, from_port: int, to_node: int, to_port: int,
		kind: int, length_hint: float, radius: float, realization: int) -> int:
	var e := MacroEdge.new()
	e.id = _edge_count
	e.from_node = from_node
	e.from_port = from_port
	e.to_node = to_node
	e.to_port = to_port
	e.kind = kind
	e.length_hint = length_hint
	e.radius = radius
	e.realization = realization
	edges.append(e)
	# link ports
	if from_node >= 0 and from_node < nodes.size() and from_port >= 0 and from_port < nodes[from_node].ports.size():
		nodes[from_node].ports[from_port].edge_id = e.id
	if to_node >= 0 and to_node < nodes.size() and to_port >= 0 and to_port < nodes[to_node].ports.size():
		nodes[to_node].ports[to_port].edge_id = e.id
	_edge_count += 1
	return e.id

# ── queries ────────────────────────────────────────────────────────────────

func node(id: int) -> MacroNode:
	if id < 0 or id >= nodes.size():
		return null
	return nodes[id]

func degree(id: int) -> int:
	var d := 0
	for e in edges:
		if e.from_node == id or e.to_node == id:
			d += 1
	return d

func edges_of(id: int) -> Array[MacroEdge]:
	var out: Array[MacroEdge] = []
	for e in edges:
		if e.from_node == id or e.to_node == id:
			out.append(e)
	return out

func is_graph_connected() -> bool:
	if nodes.is_empty():
		return true
	var visited := {}
	var stack := [0]
	while not stack.is_empty():
		var id: int = stack.pop_back()
		if visited.has(id):
			continue
		visited[id] = true
		for e in edges:
			var other := -1
			if e.from_node == id:
				other = e.to_node
			elif e.to_node == id:
				other = e.from_node
			if other >= 0 and not visited.has(other):
				stack.append(other)
	return visited.size() == nodes.size()

func boss_reachable() -> bool:
	var boss_id := -1
	for n in nodes:
		if n.kind == NodeKind.BOSS:
			boss_id = n.id
			break
	if boss_id < 0:
		return false
	var visited := {}
	var stack := [0]
	while not stack.is_empty():
		var id: int = stack.pop_back()
		if id == boss_id:
			return true
		if visited.has(id):
			continue
		visited[id] = true
		for e in edges:
			var other := -1
			if e.from_node == id:
				other = e.to_node
			elif e.to_node == id:
				other = e.from_node
			if other >= 0 and not visited.has(other):
				stack.append(other)
	return false

func loop_count() -> int:
	# Cyclomatic number of the connected graph.
	if nodes.is_empty():
		return 0
	var components := 0
	var visited := {}
	for n in nodes:
		if visited.has(n.id):
			continue
		components += 1
		var stack := [n.id]
		while not stack.is_empty():
			var id: int = stack.pop_back()
			if visited.has(id):
				continue
			visited[id] = true
			for e in edges:
				var other := -1
				if e.from_node == id:
					other = e.to_node
				elif e.to_node == id:
					other = e.from_node
				if other >= 0 and not visited.has(other):
					stack.append(other)
	return edges.size() - nodes.size() + components

func side_path_count() -> int:
	var c := 0
	for e in edges:
		if e.kind == EdgeKind.SIDE:
			c += 1
	return c

func main_path_length_nodes() -> int:
	var c := 0
	for n in nodes:
		if n.main_index >= 0:
			c += 1
	return c

func main_path_section_estimate() -> int:
	# Rough: main nodes * average sections per edge.
	return main_path_length_nodes()

func hash_summary() -> String:
	var parts: Array[String] = []
	for n in nodes:
		parts.append("%d:%d:%d:%d:%s" % [n.id, n.kind, n.zone, n.main_index,
			"%d,%d,%d" % [roundi(n.position.x), roundi(n.position.y), roundi(n.position.z)]])
	for e in edges:
		parts.append("E%d:%d-%d:%d:%d" % [e.id, e.from_node, e.to_node, e.kind, e.realization])
	return "|".join(parts)

func validate(config: Dictionary) -> Dictionary:
	var errors: Array[String] = []
	if nodes.is_empty():
		errors.append("empty graph")
		return {"ok": false, "errors": errors}
	if not is_graph_connected():
		errors.append("graph not connected")
	if not boss_reachable():
		errors.append("boss not reachable")
	var lc := loop_count()
	var min_loops := int(config.get("min_loops", 2))
	var max_loops := int(config.get("max_loops", 4))
	if lc < min_loops:
		errors.append("too few loops: %d < %d" % [lc, min_loops])
	if lc > max_loops:
		errors.append("too many loops: %d > %d" % [lc, max_loops])
	var spc := side_path_count()
	var min_side := int(config.get("side_paths_min", 3))
	var max_side := int(config.get("side_paths_max", 6))
	if spc < min_side:
		errors.append("too few side paths: %d < %d" % [spc, min_side])
	if spc > max_side:
		errors.append("too many side paths: %d > %d" % [spc, max_side])
	for n in nodes:
		if degree(n.id) > 4:
			errors.append("node %d degree %d > 4" % [n.id, degree(n.id)])
		if n.id == 0 and degree(n.id) != 1:
			errors.append("entry degree %d != 1" % degree(0))
	var boss_id := -1
	for n in nodes:
		if n.kind == NodeKind.BOSS:
			boss_id = n.id
			break
	if boss_id >= 0 and degree(boss_id) != 1:
		errors.append("boss degree %d != 1" % degree(boss_id))
	# main path length
	var mpl := main_path_length_nodes()
	var min_main := int(config.get("min_main_nodes", 8))
	var max_main := int(config.get("max_main_nodes", 18))
	if mpl < min_main:
		errors.append("main path too short: %d < %d" % [mpl, min_main])
	if mpl > max_main:
		errors.append("main path too long: %d > %d" % [mpl, max_main])
	# side paths must end in REWARD nodes
	for e in edges:
		if e.kind != EdgeKind.SIDE:
			continue
		var end_node := nodes[e.to_node] if e.to_node < nodes.size() else null
		if end_node == null or end_node.kind != NodeKind.REWARD:
			errors.append("side path %d does not end in a reward" % e.id)
	return {"ok": errors.is_empty(), "errors": errors}

# ── generation ─────────────────────────────────────────────────────────────

static func generate(config: Dictionary, rng: RandomNumberGenerator) -> MacroGraph:
	var g := MacroGraph.new()
	var main_anchors := int(config.get("main_anchors", 12))
	var anchor_spacing_min := float(config.get("anchor_spacing_min", 60.0))
	var anchor_spacing_max := float(config.get("anchor_spacing_max", 130.0))
	var clearance_radius := float(config.get("clearance_radius", 40.0))
	var max_loops := int(config.get("max_loops", 4))
	var min_loops := int(config.get("min_loops", 2))
	var side_paths := int(config.get("side_paths", 4))
	var max_loop_span := int(config.get("max_loop_span", 8))

	# 1. Meandering main route.
	var anchors: Array[Vector3] = []
	var heading := Vector3(0.0, 0.0, 1.0)
	var pos := Vector3.ZERO
	anchors.append(pos)
	var occupied: Array[Vector3] = [pos]
	for i in range(main_anchors - 1):
		var chosen := Vector3.ZERO
		var found := false
		var turn_options := [-45.0, 0.0, 0.0, 45.0]
		if rng.randf() < 0.15:
			turn_options.append(90.0)
		if rng.randf() < 0.15:
			turn_options.append(-90.0)
		for attempt in range(12):
			var turn: float = turn_options[rng.randi() % turn_options.size()]
			var new_heading := heading.rotated(Vector3.UP, deg_to_rad(turn))
			# keep forward progress
			if new_heading.z < 0.15:
				continue
			var step := rng.randf_range(anchor_spacing_min, anchor_spacing_max)
			var candidate := pos + new_heading * step
			# light 3D variation
			candidate.y += rng.randf_range(-8.0, 8.0)
			if _clearance(candidate, occupied, clearance_radius):
				chosen = candidate
				heading = new_heading
				found = true
				break
		if not found:
			# fall back to straight forward progress
			chosen = pos + Vector3(0.0, rng.randf_range(-4.0, 4.0), anchor_spacing_min)
			heading = Vector3(0.0, 0.0, 1.0)
		pos = chosen
		anchors.append(pos)
		occupied.append(pos)

	# 2. Main nodes + zones.
	var n := anchors.size()
	for i in range(n):
		var kind := NodeKind.CHAMBER
		if i == 0:
			kind = NodeKind.ENTRY
		elif i == n - 1:
			kind = NodeKind.BOSS
		var zone := _zone_for_index(i, n)
		g.add_node(kind, anchors[i], i)
		g.nodes[g.nodes.size() - 1].zone = zone

	# 3. Main edges + ports (in/out per node).
	for i in range(n - 1):
		var a := g.nodes[i]
		var b := g.nodes[i + 1]
		var dir := (b.position - a.position)
		if dir.length_squared() < 1e-4:
			dir = Vector3.FORWARD
		dir = dir.normalized()
		var radius := _zone_radius(a.zone, config)
		# out port on a
		var out_port := g.add_port(a.id, a.position + dir * 4.0, dir, Vector3.UP, radius)
		# in port on b
		var in_port := g.add_port(b.id, b.position - dir * 4.0, -dir, Vector3.UP, radius)
		g.add_edge(a.id, out_port, b.id, in_port, EdgeKind.MAIN,
			a.position.distance_to(b.position), radius, Realization.CHAIN)

	# 4. Loops.
	# Candidate pairs.
	var candidates: Array = []
	for i in range(n):
		for j in range(i + 2, min(i + max_loop_span + 1, n)):
			if i == 0 or j == n - 1:
				continue
			candidates.append([i, j])
	# Score: prefer mid-distance, reward anchors with spare ports.
	var scored: Array = []
	for c in candidates:
		var i: int = c[0]
		var j: int = c[1]
		var span: int = j - i
		var score := 10.0 - absf(float(span) - 5.0) + rng.randf() * 2.0
		scored.append([score, i, j])
	scored.sort_custom(func(a, b): return a[0] > b[0])

	var loops_added := 0
	for item in scored:
		if loops_added >= max_loops:
			break
		var i: int = item[1]
		var j: int = item[2]
		var node_i := g.nodes[i]
		var node_j := g.nodes[j]
		# port availability: each node needs an extra port; cap degree at 4
		if g.degree(node_i.id) >= 4 or g.degree(node_j.id) >= 4:
			continue
		# mark junctions
		if node_i.kind == NodeKind.CHAMBER:
			node_i.kind = NodeKind.JUNCTION
		if node_j.kind == NodeKind.CHAMBER:
			node_j.kind = NodeKind.JUNCTION
		var radius := _zone_radius(node_i.zone, config)
		var dir_i := Vector3.RIGHT.rotated(Vector3.UP, rng.randf_range(0.0, TAU))
		var dir_j := -dir_i
		var p_i := g.add_port(node_i.id, node_i.position + dir_i * 4.0, dir_i, Vector3.UP, radius)
		var p_j := g.add_port(node_j.id, node_j.position + dir_j * 4.0, dir_j, Vector3.UP, radius)
		var dist := node_i.position.distance_to(node_j.position)
		g.add_edge(node_i.id, p_i, node_j.id, p_j, EdgeKind.LOOP, dist, radius, Realization.CONNECTOR)
		loops_added += 1

	# 5. Side paths.
	var side_anchors: Array[int] = []
	for i in range(1, n - 1):
		if g.degree(g.nodes[i].id) >= 4:
			continue
		if g.nodes[i].zone < 2 or g.nodes[i].zone > 4:
			continue
		side_anchors.append(i)
	# spread selection
	var chosen_side: Array[int] = []
	var last_idx := -3
	for idx in side_anchors:
		if chosen_side.size() >= side_paths:
			break
		if idx - last_idx < 2:
			continue
		chosen_side.append(idx)
		last_idx = idx
	# if not enough, relax
	if chosen_side.size() < side_paths:
		for idx in side_anchors:
			if chosen_side.size() >= side_paths:
				break
			if not chosen_side.has(idx):
				chosen_side.append(idx)

	for idx in chosen_side:
		var anchor := g.nodes[idx]
		if g.degree(anchor.id) >= 4:
			continue
		anchor.kind = NodeKind.JUNCTION if anchor.kind == NodeKind.CHAMBER else anchor.kind
		var reward_pos := anchor.position + Vector3(
			rng.randf_range(-30.0, 30.0), rng.randf_range(-10.0, 10.0), rng.randf_range(20.0, 50.0))
		var reward_id := g.add_node(NodeKind.REWARD, reward_pos, -1)
		g.nodes[reward_id].zone = anchor.zone
		var radius := _zone_radius(anchor.zone, config)
		var dir := (reward_pos - anchor.position).normalized()
		if dir.length_squared() < 1e-4:
			dir = Vector3.FORWARD
		var p_a := g.add_port(anchor.id, anchor.position + dir * 4.0, dir, Vector3.UP, radius)
		var p_r := g.add_port(reward_id, reward_pos - dir * 4.0, -dir, Vector3.UP, radius)
		g.add_edge(anchor.id, p_a, reward_id, p_r, EdgeKind.SIDE,
			anchor.position.distance_to(reward_pos), radius, Realization.CHAIN)

	# 6. Zone assignment already done; rest nodes at zone boundaries.
	# Mark one rest node per zone boundary on the main path.
	var boundaries: Array[int] = []
	var prev_zone := 1
	for i in range(1, n - 1):
		var z := g.nodes[i].zone
		if z != prev_zone:
			boundaries.append(i)
			prev_zone = z
	for bi in boundaries:
		if g.nodes[bi].kind == NodeKind.BOSS:
			continue
		g.nodes[bi].kind = NodeKind.REST

	return g

static func _clearance(candidate: Vector3, occupied: Array[Vector3], clearance: float) -> bool:
	for p in occupied:
		if candidate.distance_to(p) < clearance:
			return false
	return true

static func _zone_for_index(i: int, n: int) -> int:
	if n <= 1:
		return 1
	var t := float(i) / float(n - 1)
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

static func _zone_radius(zone: int, config: Dictionary) -> float:
	var max_r := float(config.get("max_radius", 16.0))
	var min_r := float(config.get("min_radius", 6.0))
	var t := float(zone - 1) / 4.0
	return lerpf(max_r, min_r, t)