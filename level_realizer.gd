# level_realizer.gd  (Phase P2-10 — macro graph -> PipeNetwork)
class_name LevelRealizer
extends Node

var network: PipeNetwork = null
var parent: Node = null  # the LevelGenerator (for add_child of content)
var debug_dump: bool = false
var seed: int = 12345
var _macro: MacroGraph = null

func realize(macro: MacroGraph, net: PipeNetwork, owner: Node) -> void:
	network = net
	parent = owner if owner != null else net
	_macro = macro
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
			props = {"entry_radius": radius + 12.0, "exit_radius": radius + 12.0, "length": 150.0}
		elif node.kind == MacroGraph.NodeKind.ENTRY:
			packed = load("res://StraightPipeSection.tscn")
			props = {"entry_radius": radius, "exit_radius": radius, "length": 120.0}
		elif node.kind == MacroGraph.NodeKind.REST or node.kind == MacroGraph.NodeKind.REWARD:
			packed = load("res://RestZone.tscn")
			props = {"entry_radius": radius + 8.0, "exit_radius": radius + 8.0, "length": 80.0}
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
			continue
		var section: PipeSection = packed.instantiate() as PipeSection
		if section == null:
			continue
		for key in props:
			section.set(key, props[key])
		section.global_transform = Transform3D(Basis.IDENTITY, node.position)
		network.add_child(section)
		network.sections.append(section)
		# Build port list.
		var ports: Array[Marker3D] = []
		ports.append(section.entry)
		ports.append(section.exit)
		if section is JunctionPipeSection:
			var j := section as JunctionPipeSection
			for m in j.ports:
				if m != null and m != j.exit:
					ports.append(m)
		section.ports = ports.duplicate()
		node_sections[node.id] = section

	# Annotate main-path progress.
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
		await parent.get_tree().process_frame

	# Align junction exit markers to their actual mesh mouth centres.
	for node in macro.nodes:
		var section: PipeSection = node_sections[node.id]
		if not (section is JunctionPipeSection):
			continue
		var j := section as JunctionPipeSection
		for i in range(j.ports.size()):
			var marker: Marker3D = j.ports[i]
			var radius := j.get_exit_radius(i)
			var center := _mesh_ring_center(j, marker, radius)
			marker.global_position = center

	# Reassign port indices for each macro edge.
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

	# Create connectors for each macro edge.
	var connector_packed := load("res://ConnectorPipeSection.tscn")
	if connector_packed != null:
		for e in macro.edges:
			var from_sec: PipeSection = node_sections[e.from_node]
			var to_sec: PipeSection = node_sections[e.to_node]
			if from_sec == null or to_sec == null:
				continue
			var from_port_idx: int = e.from_port
			var to_port_idx: int = e.to_port
			if from_port_idx < 0 or from_port_idx >= from_sec.ports.size():
				from_port_idx = clampi(from_port_idx, 0, from_sec.ports.size() - 1)
			if to_port_idx < 0 or to_port_idx >= to_sec.ports.size():
				to_port_idx = clampi(to_port_idx, 0, to_sec.ports.size() - 1)
			var from_marker: Marker3D = from_sec.ports[from_port_idx]
			var to_marker: Marker3D = to_sec.ports[to_port_idx]
			var radius := from_sec.get_exit_radius(from_port_idx)
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

	# Store node_sections for content placer.
	_node_sections = node_sections
	_macro = macro

	# Let async section _ready calls settle.
	for i in range(10):
		await parent.get_tree().process_frame

	if debug_dump:
		var summary := macro.hash_summary()
		var gs = parent.get_node_or_null("/root/GameState")
		if gs:
			gs.last_graph_summary = summary
		var f := FileAccess.open("user://level_graph_%d.txt" % seed, FileAccess.WRITE)
		if f:
			f.store_string(summary)
			f.close()

	# Seal the start and every dead end / unused mouth.
	network.cap_open_ends()

	# Per-section interior lighting.
	_add_interior_lights(network)

func _add_interior_lights(net: PipeNetwork) -> void:
	for s in net.sections:
		var sec: PipeSection = s
		var light := OmniLight3D.new()
		light.name = "InteriorLight"
		var r := maxf(sec.get_entry_radius(), sec.get_exit_radius())
		light.omni_range = maxf(r * 2.5, 8.0)
		light.light_energy = 0.8
		light.shadow_enabled = false
		if sec is RestZone:
			light.light_color = Color(0.6, 1.0, 0.7)
			light.light_energy = 1.2
		elif sec is BossArena:
			light.light_color = Color(1.0, 0.4, 0.3)
			light.light_energy = 1.0
		elif sec is JunctionPipeSection:
			light.light_color = Color(1.0, 0.85, 0.5)
			light.light_energy = 0.9
		elif sec is ConnectorPipeSection:
			light.light_color = Color(0.7, 0.75, 0.9)
			light.light_energy = 0.7
		else:
			light.light_color = Color(0.85, 0.9, 1.0)
			light.light_energy = 0.8
		var mid := (sec.entry.global_position + sec.exit.global_position) * 0.5
		light.global_position = mid
		net.add_child(light)

func _mesh_ring_center(section: PipeSection, marker: Marker3D, radius: float) -> Vector3:
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

# Exposed for the content placer.
var _node_sections: Array = []
var node_sections: Array:
	get:
		return _node_sections