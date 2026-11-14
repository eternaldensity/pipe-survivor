extends Node3D
@onready var network : PipeNetwork = $PipeNetwork
@export var straight_section : PackedScene
@export var bend_section : PackedScene

var junction_section : PackedScene
var rest_zone_scene  : PackedScene
var sign_scene       : PackedScene
var crafting_ui_scene: PackedScene

func _ready() -> void:
	junction_section   = load("res://JunctionPipeSection.tscn")
	rest_zone_scene    = load("res://RestZone.tscn")
	sign_scene         = load("res://Sign.tscn")
	crafting_ui_scene  = load("res://CraftingUI.tscn")

	# ── Opening: wide chamber that tapers down ────────────────────────────
	network.add_section(straight_section, { "entry_radius": 20.0, "exit_radius": 10.0, "length": 120.0 })

	# ── First bend (gentle, 10°) ──────────────────────────────────────────
	network.add_section(bend_section, { "bend_angle": 10.0, "roll_angle": 180.0, "length": 300.0 })

	# ── Narrow challenge section (radius 6) ────────────────────────────────
	network.add_section(straight_section, { "exit_radius": 6.0 })   # tapers 10 -> 6
	network.add_section(straight_section, { "entry_radius": 6.0, "exit_radius": 6.0, "length": 60.0 })
	network.add_section(straight_section, { "entry_radius": 6.0 })   # widens 6 -> 10

	# ── Mid straight with a rest zone ─────────────────────────────────────
	var mid_straight := network.add_section(straight_section, { "length": 100.0 })
	# Rest zone placed at the end of the mid straight.
	var rest_zone = rest_zone_scene.instantiate()
	rest_zone.position = mid_straight.exit.global_position
	rest_zone.rotation = mid_straight.exit.global_rotation
	add_child(rest_zone)

	# ── Second bend (45°) then a wide section ─────────────────────────────
	network.add_section(bend_section, { "bend_angle": 45.0, "length": 100.0, "tube_radius": 10.0 })
	network.add_section(straight_section, { "exit_radius": 20.0, "length": 40.0 })   # widens 10 -> 20
	network.add_section(straight_section, { "entry_radius": 20.0, "exit_radius": 10.0, "length": 200.0 })  # tapers to 10

	# ── Trident junction ──────────────────────────────────────────────────
	var j := network.add_section(junction_section, { "trunk_length": 60.0, "branch_angle": 30.0, "tube_radius": 10.0 })

	# Signage before the junction.
	var sign = sign_scene.instantiate()
	sign.text = "JUNCTION AHEAD"
	sign.branch_color = Color(0.3, 0.6, 1.0)
	sign.position = j.entry.global_position - j.global_transform.basis.z * 15.0 + Vector3(0.0, 8.0, 0.0)
	add_child(sign)

	# ── Three paths, each with a continuation ─────────────────────────────
	var trunk := network.add_section(straight_section, { "length": 80.0, "entry_radius": 10.0, "exit_radius": 10.0 }, j, 0)
	var left  := network.add_section(straight_section, { "length": 80.0, "entry_radius": 10.0, "exit_radius": 10.0 }, j, 1)
	var right := network.add_section(straight_section, { "length": 80.0, "entry_radius": 10.0, "exit_radius": 10.0 }, j, 2)

	# Trunk path: gentle bend then a long straight.
	network.add_section(bend_section, { "bend_angle": 25.0, "length": 150.0, "tube_radius": 10.0 }, trunk, 0)
	network.add_section(straight_section, { "length": 200.0, "entry_radius": 10.0, "exit_radius": 10.0 })

	# Left branch path.
	network.add_section(bend_section, { "bend_angle": 20.0, "length": 120.0, "tube_radius": 10.0 }, left, 0)
	network.add_section(straight_section, { "length": 150.0, "entry_radius": 10.0, "exit_radius": 10.0 })

	# Right branch path (mirrored bend).
	network.add_section(bend_section, { "bend_angle": 20.0, "length": 120.0, "tube_radius": 10.0, "roll_angle": 180.0 }, right, 0)
	network.add_section(straight_section, { "length": 150.0, "entry_radius": 10.0, "exit_radius": 10.0 })

	# ── Crafting UI overlay ───────────────────────────────────────────────
	var crafting_ui = crafting_ui_scene.instantiate()
	add_child(crafting_ui)
	crafting_ui.bind_vehicle($Vehicle)

	# Phase 5: Enemy spawner.
	var spawner = EnemySpawner.new()
	spawner.enemy_scene = load("res://EnemyVehicle.tscn")
	spawner.network = network
	spawner.target = $Vehicle
	spawner.spawn_interval = 4.0
	spawner.max_enemies = 6
	add_child(spawner)