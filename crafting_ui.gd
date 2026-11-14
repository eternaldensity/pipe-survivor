# crafting_ui.gd  (Phase 3 — placeholder)
class_name CraftingUI
extends CanvasLayer

@onready var panel: PanelContainer = $PanelContainer
@onready var title: Label = $PanelContainer/VBoxContainer/Title
@onready var info: Label = $PanelContainer/VBoxContainer/Info
@onready var preset_list: VBoxContainer = $PanelContainer/VBoxContainer/PresetList

var vehicle: Vehicle = null
var presets: Array[PresetSigil] = []
var selected_preset: PresetSigil = null

func _ready() -> void:
	panel.visible = false
	title.text = "REST ZONE — Crafting"
	info.text = "Select a preset sigil to craft."
	presets = PresetSigil.default_presets()
	_build_preset_list()

func _build_preset_list() -> void:
	if preset_list == null:
		return
	for child in preset_list.get_children():
		child.queue_free()
	for p in presets:
		var btn := Button.new()
		btn.text = p.name
		btn.pressed.connect(_on_preset_selected.bind(p))
		preset_list.add_child(btn)

func _on_preset_selected(p: PresetSigil) -> void:
	selected_preset = p
	info.text = "%s\n%s\nFamily: %s" % [p.name, p.description, p.attractor_family]

func bind_vehicle(v: Vehicle) -> void:
	vehicle = v

func _process(_delta: float) -> void:
	if vehicle:
		panel.visible = vehicle.rest_zone_inside