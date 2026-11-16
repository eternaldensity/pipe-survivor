# main_menu.gd  (Phase 7 — vertical slice)
class_name MainMenu
extends Control

var _seed_edit: LineEdit = null

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

	# Seed input.
	var seed_label := Label.new()
	seed_label.text = "Seed:"
	seed_label.position = Vector2(0, 260)
	seed_label.size = Vector2(80, 30)
	seed_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	seed_label.offset_left = -200
	seed_label.offset_top = 260
	seed_label.offset_right = -120
	seed_label.offset_bottom = 290
	add_child(seed_label)

	var _gs = get_node_or_null("/root/GameState")
	var default_seed := 12345
	if _gs:
		default_seed = _gs.seed

	_seed_edit = LineEdit.new()
	_seed_edit.text = str(default_seed)
	_seed_edit.position = Vector2(0, 260)
	_seed_edit.size = Vector2(120, 30)
	_seed_edit.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_seed_edit.offset_left = -100
	_seed_edit.offset_top = 260
	_seed_edit.offset_right = 20
	_seed_edit.offset_bottom = 290
	add_child(_seed_edit)

	var random_btn := Button.new()
	random_btn.text = "Random"
	random_btn.size = Vector2(80, 30)
	random_btn.set_anchors_preset(Control.PRESET_CENTER_TOP)
	random_btn.offset_left = 30
	random_btn.offset_top = 260
	random_btn.offset_right = 110
	random_btn.offset_bottom = 290
	random_btn.pressed.connect(func():
		_seed_edit.text = str(randi())
	)
	add_child(random_btn)

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
	var _gs = get_node_or_null("/root/GameState")
	if _seed_edit and _gs:
		var val := _seed_edit.text.to_int()
		if val != 0:
			_gs.seed = val
	get_tree().change_scene_to_file("res://main.tscn")

func _on_quit_pressed() -> void:
	get_tree().quit()