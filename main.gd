extends Node3D
@onready var network : PipeNetwork = $PipeNetwork
@export var straight_section : PackedScene
@export var bend_section : PackedScene

var junction_section : PackedScene
var rest_zone_scene  : PackedScene
var sign_scene       : PackedScene
var crafting_ui_scene: PackedScene
var level_generator   : LevelGenerator

func _ready() -> void:
	junction_section   = load("res://JunctionPipeSection.tscn")
	rest_zone_scene    = load("res://RestZone.tscn")
	sign_scene         = load("res://Sign.tscn")
	crafting_ui_scene  = load("res://CraftingUI.tscn")

	# Phase 7: Procedural level generation.
	var _gs = get_node_or_null("/root/GameState")
	level_generator = LevelGenerator.new()
	level_generator.seed = _gs.seed if _gs else 12345
	level_generator.target_depth = 10
	add_child(level_generator)
	await level_generator.generate(network)

	# Phase 7: Game manager (win/lose).
	var gm = GameManager.new()
	add_child(gm)

	# Phase 7: Game HUD.
	var hud = load("res://GameHUD.tscn").instantiate()
	add_child(hud)

	# Phase 7: Audio manager.
	var audio = AudioManager.new()
	add_child(audio)

	# Phase 7: Pause menu.
	var pause_menu = load("res://PauseMenu.tscn").instantiate()
	add_child(pause_menu)

	# Phase 7: Crafting UI overlay.
	var crafting_ui = crafting_ui_scene.instantiate()
	add_child(crafting_ui)
	crafting_ui.bind_vehicle($Vehicle)