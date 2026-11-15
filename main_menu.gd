# main_menu.gd  (Phase 7 — vertical slice)
class_name MainMenu
extends Control

func _ready() -> void:
	# Full-screen dark background.
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.05, 0.1, 1.0)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# Title.
	var title := Label.new()
	title.text = "PIPE SURVIVOR"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 64)
	title.position = Vector2(0, 100)
	title.size = Vector2(800, 80)
	title.set_anchors_preset(Control.PRESET_CENTER_TOP)
	title.offset_left = -400
	title.offset_top = 100
	title.offset_right = 400
	title.offset_bottom = 180
	add_child(title)

	# Subtitle.
	var subtitle := Label.new()
	subtitle.text = "A high-speed vehicle game inside tubes"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 20)
	subtitle.position = Vector2(0, 200)
	subtitle.size = Vector2(800, 40)
	subtitle.set_anchors_preset(Control.PRESET_CENTER_TOP)
	subtitle.offset_left = -400
	subtitle.offset_top = 200
	subtitle.offset_right = 400
	subtitle.offset_bottom = 240
	add_child(subtitle)

	# Start button.
	var start_btn := Button.new()
	start_btn.text = "Start Game"
	start_btn.position = Vector2(0, 320)
	start_btn.size = Vector2(200, 50)
	start_btn.set_anchors_preset(Control.PRESET_CENTER_TOP)
	start_btn.offset_left = -100
	start_btn.offset_top = 320
	start_btn.offset_right = 100
	start_btn.offset_bottom = 370
	start_btn.pressed.connect(_on_start_pressed)
	add_child(start_btn)

	# Quit button.
	var quit_btn := Button.new()
	quit_btn.text = "Quit"
	quit_btn.position = Vector2(0, 400)
	quit_btn.size = Vector2(200, 50)
	quit_btn.set_anchors_preset(Control.PRESET_CENTER_TOP)
	quit_btn.offset_left = -100
	quit_btn.offset_top = 400
	quit_btn.offset_right = 100
	quit_btn.offset_bottom = 450
	quit_btn.pressed.connect(_on_quit_pressed)
	add_child(quit_btn)

func _on_start_pressed() -> void:
	get_tree().change_scene_to_file("res://main.tscn")

func _on_quit_pressed() -> void:
	get_tree().quit()