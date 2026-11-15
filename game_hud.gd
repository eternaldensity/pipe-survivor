# game_hud.gd  (Phase 6/7 — integrated HUD)
class_name GameHUD
extends CanvasLayer

var player_health_bar: ProgressBar = null
var boss_health_bar: ProgressBar = null
var boss_label: Label = null
var status_label: Label = null

var player: Vehicle = null
var boss: BossVehicle = null
var game_manager: GameManager = null

func _ready() -> void:
	# Player health bar (top-left).
	player_health_bar = ProgressBar.new()
	player_health_bar.position = Vector2(10, 10)
	player_health_bar.size = Vector2(200, 20)
	player_health_bar.max_value = 100.0
	player_health_bar.value = 100.0
	player_health_bar.show_percentage = false
	add_child(player_health_bar)

	# Boss health bar (top-right, hidden until boss found).
	boss_health_bar = ProgressBar.new()
	boss_health_bar.position = Vector2(0, 10)  # will be repositioned in _process
	boss_health_bar.size = Vector2(200, 20)
	boss_health_bar.max_value = 50.0
	boss_health_bar.value = 50.0
	boss_health_bar.show_percentage = false
	boss_health_bar.visible = false
	add_child(boss_health_bar)

	boss_label = Label.new()
	boss_label.text = "BOSS"
	boss_label.position = Vector2(0, -20)
	boss_label.visible = false
	add_child(boss_label)

	# Status label (center, for win/lose).
	status_label = Label.new()
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	status_label.position = Vector2(0, 0)
	status_label.size = Vector2(400, 100)
	status_label.visible = false
	status_label.add_theme_font_size_override("font_size", 48)
	add_child(status_label)

func _process(_delta: float) -> void:
	# Find player and boss if not yet found.
	if player == null:
		for child in get_parent().get_children():
			if child is Vehicle:
				player = child
	if boss == null:
		for child in get_parent().get_children():
			if child is BossVehicle:
				boss = child
	if game_manager == null:
		for child in get_parent().get_children():
			if child is GameManager:
				game_manager = child

	# Update player health bar.
	if player:
		player_health_bar.max_value = player.max_health
		player_health_bar.value = player.health

	# Update boss health bar.
	if boss and is_instance_valid(boss):
		boss_health_bar.visible = true
		boss_label.visible = true
		boss_health_bar.max_value = boss.health  # use current as max for simplicity
		boss_health_bar.value = boss.health
		# Position boss bar top-right.
		var vp := get_viewport().get_visible_rect().size
		boss_health_bar.position = Vector2(vp.x - 210, 10)
		boss_label.position = Vector2(vp.x - 210, -15)
	else:
		boss_health_bar.visible = false
		boss_label.visible = false

	# Win/lose status.
	if game_manager:
		if game_manager.victory and not status_label.visible:
			status_label.text = "VICTORY\nPress R to restart"
			status_label.modulate = Color(0.3, 1.0, 0.4)
			status_label.visible = true
			status_label.position = (get_viewport().get_visible_rect().size - status_label.size) * 0.5
		elif game_manager.game_over and not status_label.visible:
			status_label.text = "GAME OVER\nPress R to restart"
			status_label.modulate = Color(1.0, 0.3, 0.3)
			status_label.visible = true
			status_label.position = (get_viewport().get_visible_rect().size - status_label.size) * 0.5

	# Restart on R.
	if status_label.visible and Input.is_action_just_pressed("ui_text_completion_accept"):
		pass
	if status_label.visible and Input.is_key_pressed(KEY_R):
		get_tree().reload_current_scene()