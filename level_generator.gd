# level_generator.gd  (Phase 7 — level generation)
class_name LevelGenerator
extends Node

# ── Configuration ─────────────────────────────────────────────────────────
@export var seed: int = 12345
@export var min_radius: float = 10.0
@export var max_radius: float = 24.0
@export var debug_dump: bool = false

var network: PipeNetwork = null
var rng: RandomNumberGenerator = null
var _macro: MacroGraph = null
var _realizer: LevelRealizer = null

func _ready() -> void:
	rng = RandomNumberGenerator.new()
	rng.seed = seed

func generate(net: PipeNetwork) -> void:
	network = net
	rng.seed = seed

	# Clean up stale junction mesh caches from older code versions.
	_cleanup_junction_caches()

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
		"max_radius": max_radius,
		"min_radius": min_radius,
	}
	var macro: MacroGraph = MacroGraph.generate(config, rng)
	_macro = macro
	var v := macro.validate(config)
	if not bool(v["ok"]):
		push_warning("v2 macro validation failed: %s" % str(v["errors"]))
		return

	_realizer = LevelRealizer.new()
	_realizer.debug_dump = debug_dump
	_realizer.seed = seed
	await _realizer.realize(macro, network, self)

	_place_content_v2(_realizer.node_sections, macro)

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
	var pause_menu = load("res://PauseMenu.tscn")
	if pause_menu:
		var pm = pause_menu.instantiate()
		if pm:
			add_child(pm)

	# Crafting UI.
	var crafting_scene = load("res://CraftingUI.tscn")
	if crafting_scene:
		var crafting_ui = crafting_scene.instantiate()
		if crafting_ui:
			add_child(crafting_ui)
			var vehicle = get_node_or_null("Vehicle")
			if vehicle:
				crafting_ui.bind_vehicle(vehicle)

	# Debug dump.
	if debug_dump:
		var summary := _macro.hash_summary() if _macro != null else ""
		var _gs = get_node_or_null("/root/GameState")
		if _gs:
			_gs.last_graph_summary = summary
		var f := FileAccess.open("user://level_graph_%d.txt" % seed, FileAccess.WRITE)
		if f:
			f.store_string(summary)
			f.close()