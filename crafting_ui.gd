# crafting_ui.gd  (Phase 3/4 — crafting shell)
class_name CraftingUI
extends CanvasLayer

@onready var panel: PanelContainer = $PanelContainer
@onready var title: Label = $PanelContainer/VBoxContainer/Title
@onready var info: Label = $PanelContainer/VBoxContainer/Info
@onready var preset_list: VBoxContainer = $PanelContainer/VBoxContainer/PresetList
@onready var param_box: VBoxContainer = $PanelContainer/VBoxContainer/ParamBox
@onready var preview_container: SubViewportContainer = $PanelContainer/VBoxContainer/PreviewContainer

var vehicle: Vehicle = null
var presets: Array[PresetSigil] = []
var selected_preset: PresetSigil = null
var attractor: Attractor = Attractor.new()
var preview: AttractorPreview = null

# Parameter sliders.
var slider_sigma: HSlider = null
var slider_rho: HSlider = null
var slider_beta: HSlider = null
var label_sigma: Label = null
var label_rho: Label = null
var label_beta: Label = null

func _ready() -> void:
	panel.visible = false
	title.text = "REST ZONE — Crafting"
	info.text = "Select a preset sigil to craft."
	presets = PresetSigil.default_presets()
	_build_preset_list()
	_build_param_sliders()
	_build_preview()

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

func _build_param_sliders() -> void:
	if param_box == null:
		return
	for child in param_box.get_children():
		child.queue_free()

	label_sigma = Label.new()
	label_sigma.text = "Sigma: 10.0"
	param_box.add_child(label_sigma)
	slider_sigma = HSlider.new()
	slider_sigma.min_value = 1.0
	slider_sigma.max_value = 20.0
	slider_sigma.value = 10.0
	slider_sigma.step = 0.1
	slider_sigma.value_changed.connect(_on_sigma_changed)
	param_box.add_child(slider_sigma)

	label_rho = Label.new()
	label_rho.text = "Rho: 28.0"
	param_box.add_child(label_rho)
	slider_rho = HSlider.new()
	slider_rho.min_value = 1.0
	slider_rho.max_value = 50.0
	slider_rho.value = 28.0
	slider_rho.step = 0.1
	slider_rho.value_changed.connect(_on_rho_changed)
	param_box.add_child(slider_rho)

	label_beta = Label.new()
	label_beta.text = "Beta: 2.67"
	param_box.add_child(label_beta)
	slider_beta = HSlider.new()
	slider_beta.min_value = 0.1
	slider_beta.max_value = 10.0
	slider_beta.value = 2.667
	slider_beta.step = 0.01
	slider_beta.value_changed.connect(_on_beta_changed)
	param_box.add_child(slider_beta)

func _build_preview() -> void:
	if preview_container == null:
		return
	preview = AttractorPreview.new()
	preview.position = Vector3.ZERO
	# Add to the container's viewport if it's a SubViewportContainer.
	# For simplicity, add as a child of the panel.
	panel.add_child(preview)
	preview.position = Vector3(0, 0, 0)
	preview.scale = Vector3(0.3, 0.3, 0.3)

func _on_preset_selected(p: PresetSigil) -> void:
	selected_preset = p
	info.text = "%s\n%s\nFamily: %s" % [p.name, p.description, p.attractor_family]
	if p.params.has("sigma"):
		slider_sigma.value = p.params["sigma"]
	if p.params.has("rho"):
		slider_rho.value = p.params["rho"]
	if p.params.has("beta"):
		slider_beta.value = p.params["beta"]
	_update_attractor()

func _on_sigma_changed(val: float) -> void:
	attractor.sigma = val
	label_sigma.text = "Sigma: %.1f" % val
	_update_attractor()

func _on_rho_changed(val: float) -> void:
	attractor.rho = val
	label_rho.text = "Rho: %.1f" % val
	_update_attractor()

func _on_beta_changed(val: float) -> void:
	attractor.beta = val
	label_beta.text = "Beta: %.2f" % val
	_update_attractor()

func _update_attractor() -> void:
	if preview:
		preview.attractor = attractor
		preview.update_preview()

func bind_vehicle(v: Vehicle) -> void:
	vehicle = v

func _process(_delta: float) -> void:
	if vehicle:
		panel.visible = vehicle.rest_zone_inside
		if panel.visible and preview:
			preview.visible = true
		elif preview:
			preview.visible = false