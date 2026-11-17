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

	# Centered vertical layout.
	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_CENTER)
	vbox.offset_left = -200
	vbox.offset_top = -200
	vbox.offset_right = 200
	vbox.offset_bottom = 200
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 16)
	add_child(vbox)

	var title := Label.new()
	title.text = "PIPE SURVIVOR"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 64)
	vbox.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "A high-speed vehicle game inside tubes"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 20)
	vbox.add_child(subtitle)

	# Seed row.
	var seed_row := HBoxContainer.new()
	seed_row.alignment = BoxContainer.ALIGNMENT_CENTER
	seed_row.add_theme_constant_override("separation", 8)
	vbox.add_child(seed_row)

	var seed_label := Label.new()
	seed_label.text = "Seed:"
	seed_row.add_child(seed_label)

	_seed_edit = LineEdit.new()
	_seed_edit.text = str(_default_seed())
	_seed_edit.custom_minimum_size = Vector2(120, 30)
	seed_row.add_child(_seed_edit)

	var random_btn := Button.new()
	random_btn.text = "Random"
	random_btn.pressed.connect(func():
		_seed_edit.text = str(randi())
	)
	seed_row.add_child(random_btn)

	var start_btn := Button.new()
	start_btn.text = "Start Game"
	start_btn.custom_minimum_size = Vector2(200, 50)
	start_btn.pressed.connect(_on_start_pressed)
	vbox.add_child(start_btn)

	var quit_btn := Button.new()
	quit_btn.text = "Quit"
	quit_btn.custom_minimum_size = Vector2(200, 50)
	quit_btn.pressed.connect(_on_quit_pressed)
	vbox.add_child(quit_btn)

func _default_seed() -> int:
	var _gs = get_node_or_null("/root/GameState")
	if _gs:
		return _gs.seed
	return 12345

func _on_start_pressed() -> void:
	var _gs = get_node_or_null("/root/GameState")
	if _seed_edit and _gs:
		var val := _seed_edit.text.to_int()
		if val != 0:
			_gs.seed = val
	get_tree().change_scene_to_file("res://main.tscn")

func _on_quit_pressed() -> void:
	get_tree().quit()