# pause_menu.gd  (Phase 7)
class_name PauseMenu
extends CanvasLayer

var _paused: bool = false
var _panel: PanelContainer = null

func _ready() -> void:
	_panel = PanelContainer.new()
	_panel.visible = false
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.offset_left = -150
	_panel.offset_top = -100
	_panel.offset_right = 150
	_panel.offset_bottom = 100
	add_child(_panel)

	var vbox := VBoxContainer.new()
	_panel.add_child(vbox)

	var title := Label.new()
	title.text = "PAUSED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 32)
	vbox.add_child(title)

	var resume_btn := Button.new()
	resume_btn.text = "Resume"
	resume_btn.pressed.connect(_on_resume)
	vbox.add_child(resume_btn)

	var quit_btn := Button.new()
	quit_btn.text = "Quit to Menu"
	quit_btn.pressed.connect(_on_quit)
	vbox.add_child(quit_btn)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_toggle_pause()

func _toggle_pause() -> void:
	_paused = not _paused
	_panel.visible = _paused
	get_tree().paused = _paused

func _on_resume() -> void:
	_toggle_pause()

func _on_quit() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://MainMenu.tscn")