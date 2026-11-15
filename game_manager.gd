# game_manager.gd  (Phase 6 — win/lose)
class_name GameManager
extends Node

var boss: BossVehicle = null
var player: Vehicle = null
var game_over: bool = false
var victory: bool = false

signal game_over_signal
signal victory_signal

func _ready() -> void:
	# Find boss and player in the scene.
	for child in get_parent().get_children():
		if child is BossVehicle:
			boss = child
		elif child is Vehicle:
			player = child

func _process(_delta: float) -> void:
	if game_over or victory:
		return
	if player and player.health <= 0.0:
		game_over = true
		game_over_signal.emit()
		print("GAME OVER")
		# Stop player movement.
		if player:
			player.set_physics_process(false)
	if boss and not is_instance_valid(boss):
		victory = true
		victory_signal.emit()
		print("VICTORY")
		# Stop player movement.
		if player:
			player.set_physics_process(false)