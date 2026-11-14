# crafting_ui.gd  (Phase 3 — placeholder)
class_name CraftingUI
extends CanvasLayer

@onready var panel: PanelContainer = $PanelContainer
@onready var title: Label = $PanelContainer/VBoxContainer/Title
@onready var info: Label = $PanelContainer/VBoxContainer/Info

var vehicle: Vehicle = null

func _ready() -> void:
	panel.visible = false
	title.text = "REST ZONE — Crafting"
	info.text = "Spellcrafting placeholder.\nPresets, tuning, and sigil preview will appear here."

func bind_vehicle(v: Vehicle) -> void:
	vehicle = v

func _process(_delta: float) -> void:
	if vehicle:
		panel.visible = vehicle.rest_zone_inside