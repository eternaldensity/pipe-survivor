# level_config.gd  (Phase E/P2 — typed configuration resource)
class_name LevelConfig
extends Resource

@export var seed: int = 12345
@export var generation_version: int = 2
@export var target_run_minutes: float = 15.0
@export var main_anchors: int = 12
@export var anchor_spacing_min: float = 60.0
@export var anchor_spacing_max: float = 130.0
@export var clearance_radius: float = 40.0
@export var min_loops: int = 2
@export var max_loops: int = 4
@export var max_loop_span: int = 8
@export var side_paths: int = 4
@export var side_paths_min: int = 3
@export var side_paths_max: int = 6
@export var min_main_nodes: int = 8
@export var max_main_nodes: int = 18
@export var max_radius: float = 16.0
@export var min_radius: float = 6.0
@export var rest_interval: int = 4
@export var dead_end_prob: float = 0.3
@export var junction_prob_base: float = 0.25
@export var target_depth: int = 10
@export var min_spawn_distance: float = 25.0
@export var max_spawn_distance: float = 80.0
@export var elite_start_progress: float = 0.45
@export var champion_start_progress: float = 0.8

func to_dict() -> Dictionary:
	return {
		"main_anchors": main_anchors,
		"anchor_spacing_min": anchor_spacing_min,
		"anchor_spacing_max": anchor_spacing_max,
		"clearance_radius": clearance_radius,
		"min_loops": min_loops,
		"max_loops": max_loops,
		"side_paths": side_paths,
		"side_paths_min": side_paths_min,
		"side_paths_max": side_paths_max,
		"max_loop_span": max_loop_span,
		"min_main_nodes": min_main_nodes,
		"max_main_nodes": max_main_nodes,
		"max_radius": max_radius,
		"min_radius": min_radius,
	}