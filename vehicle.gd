extends CharacterBody3D

class_name Vehicle

@export var gravity      := 25.0
@export var speed        := 20.0
@export var acceleration := 50.0
@export var friction     := 35.0
@export var turn_speed   := 2.0   # radians per second
@export var steer_accel  := 6.0   # steering rate ramp (units/sec)

var tube_origin     := Vector3.ZERO
var tube_axis       := Vector3(0.0, 0.0, 1.0)
var tube_radius     := 10.0
var steering_amount := 0.0
var rest_zone_inside := false
var health := 100.0
var max_health := 100.0
var _spell_cooldown := 0.0
const SPELL_COOLDOWN := 2.0

var _camera        : Camera3D = null
var _cam_pos       := Vector3(0.0, 1.5, 2.5)
var _cam_basis     := Basis.IDENTITY
var _cam_ready     := false
var _speed_label   : Label = null
var _rest_label    : Label3D = null
var _attractor_preview : AttractorPreview = null

var selected_preset_index := 0
var _presets: Array[PresetSigil] = []
var _spell_zone_scene: PackedScene = null
var _audio_manager: AudioManager = null
var _audio_searched: bool = false
# Live spell parameters (updated by crafting UI).
var _prev_speed := 0.0
var _sudden_stop_cooldown := 0.0
var spell_sigma: float = 10.0
var spell_rho: float = 28.0
var spell_beta: float = 8.0 / 3.0

@export var network : PipeNetwork

func _ready() -> void:
	_camera = get_node_or_null("Camera3D")
	safe_margin = 0.05
	# Speed HUD (extracted to SpeedHUD.tscn).
	var hud_scene := load("res://SpeedHUD.tscn")
	if hud_scene:
		var hud := hud_scene.instantiate() as SpeedHUD
		if hud:
			hud.vehicle = self
			add_child(hud)
	_speed_label = null  # no longer used; SpeedHUD handles display

	_rest_label = Label3D.new()
	_rest_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_rest_label.font_size = 48
	_rest_label.modulate = Color(0.3, 1.0, 0.4)
	_rest_label.position = Vector3(0.0, 3.0, 0.0)
	_rest_label.text = "REST ZONE"
	_rest_label.visible = false
	add_child(_rest_label)

	_attractor_preview = AttractorPreview.new()
	_attractor_preview.visible = false
	_attractor_preview.position = Vector3(0.0, 0.0, -5.0)
	add_child(_attractor_preview)

func _build_mesh() -> void:
	var mi := get_node_or_null("MeshInstance3D") as MeshInstance3D
	if mi:
		mi.visible = false  # replaced by composite
	# Body (elongated dart).
	_add_part("Body", BoxMesh.new(), Vector3(0.3, 0.25, 1.6), Vector3(0, 0, 0), Color(0.15, 0.35, 0.7), true)
	# Cockpit.
	_add_part("Cockpit", BoxMesh.new(), Vector3(0.22, 0.18, 0.5), Vector3(0, 0.15, -0.3), Color(0.3, 0.6, 1.0), false)
	# Wings.
	_add_part("WingL", BoxMesh.new(), Vector3(1.2, 0.04, 0.6), Vector3(-0.7, -0.05, 0.1), Color(0.1, 0.25, 0.55), true)
	_add_part("WingR", BoxMesh.new(), Vector3(1.2, 0.04, 0.6), Vector3(0.7, -0.05, 0.1), Color(0.1, 0.25, 0.55), true)
	# Engine glow.
	_add_part("Engine", CylinderMesh.new(), Vector3(0.15, 0.15, 0.4), Vector3(0, 0, 0.9), Color(0.2, 0.8, 1.0), false, true)

func _add_part(name: String, mesh: Mesh, size: Vector3, pos: Vector3, color: Color, metallic: bool, emissive: bool = false) -> void:
	var mi := MeshInstance3D.new()
	mi.name = name
	if mesh is BoxMesh:
		(mesh as BoxMesh).size = size
	elif mesh is CylinderMesh:
		(mesh as CylinderMesh).top_radius = size.x
		(mesh as CylinderMesh).bottom_radius = size.x
		(mesh as CylinderMesh).height = size.z
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	if metallic:
		mat.metallic = 0.7
		mat.roughness = 0.3
	if emissive:
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = 3.0
	mi.material_override = mat
	mi.position = pos
	add_child(mi)
	_presets = PresetSigil.default_presets()
	_build_mesh()
	add_to_group("vehicles")
	if not _presets.is_empty():
		var p := _presets[0]
		if p.params.has("sigma"): spell_sigma = p.params["sigma"]
		if p.params.has("rho"): spell_rho = p.params["rho"]
		if p.params.has("beta"): spell_beta = p.params["beta"]

func _process(delta: float) -> void:
	# Engine sound.
	var audio := _find_audio_manager()
	if audio:
		audio.play_engine(velocity.length())
	if _rest_label:
		_rest_label.visible = rest_zone_inside
	if _attractor_preview:
		_attractor_preview.visible = rest_zone_inside
		if rest_zone_inside:
			_attractor_preview.update_preview()
	if _camera == null:
		return
	var base_offset := Vector3(0.0, 1.5, 2.5)
	# Camera stays behind and above the vehicle. No position look-ahead —
	# look-ahead was moving the camera in front of the vehicle.
	var target_pos := base_offset
	var target_basis := Basis.IDENTITY
	if not _cam_ready:
		_cam_pos = target_pos
		_cam_basis = target_basis
		_cam_ready = true
	else:
		_cam_pos = _cam_pos.lerp(target_pos, clampf(delta * 6.0, 0.0, 1.0))
		_cam_basis = _cam_basis.slerp(target_basis, clampf(delta * 6.0, 0.0, 1.0))
	_camera.transform = Transform3D(_cam_basis, _cam_pos)

func _outward_from(props: Dictionary) -> Vector3:
	var axis: Vector3 = props["axis"]
	var origin: Vector3 = props["origin"]
	var to_self: Vector3 = global_position - origin
	var radial: Vector3 = to_self - to_self.dot(axis) * axis
	if radial.length_squared() < 1e-4:
		return axis.cross(Vector3.UP).normalized()
	return radial.normalized()

func _physics_process(delta: float) -> void:
	var section := network.get_section_at(global_position)
	if section == null:
		return
	var props   := section.get_tube_properties(global_position)
	tube_axis   = props["axis"]
	tube_origin = props["origin"]
	tube_radius = props["radius"]

	var outward := _outward_from(props)
	var inward  := -outward
	up_direction = inward

	# ── Spell casting ─────────────────────────────────────────────────────
	_spell_cooldown = maxf(0.0, _spell_cooldown - delta)
	# Preset selection via number keys.
	if Input.is_key_pressed(KEY_1):
		selected_preset_index = 0
	if Input.is_key_pressed(KEY_2):
		selected_preset_index = 1
	if Input.is_key_pressed(KEY_3):
		selected_preset_index = 2
	if Input.is_action_just_pressed("ui_accept") and _spell_cooldown <= 0.0:
		_spell_cooldown = SPELL_COOLDOWN
		if _spell_zone_scene == null:
			_spell_zone_scene = load("res://SpellZone.tscn")
		var zone := _spell_zone_scene.instantiate() as SpellZone
		if zone == null:
			return
		# Configure attractor from live spell params (updated by crafting UI).
		zone.attractor.sigma = spell_sigma
		zone.attractor.rho = spell_rho
		zone.attractor.beta = spell_beta
		# Set attractor family from selected preset.
		if selected_preset_index >= 0 and selected_preset_index < _presets.size():
			zone.attractor_family = _presets[selected_preset_index].attractor_family
		zone.spell_rho = spell_rho
		var fwd := -global_transform.basis.z
		fwd = fwd - fwd.dot(outward) * outward
		if fwd.length_squared() > 1e-4:
			fwd = fwd.normalized()
		else:
			fwd = tube_axis
		zone.zone_centre = global_position + fwd * 20.0
		var parent := get_parent()
		if parent:
			parent.add_child(zone)
			zone.global_position = zone.zone_centre
			# Play spell sound.
			var audio := _find_audio_manager()
			if audio:
				audio.play_spell()

	# ── Rest zone detection ───────────────────────────────────────────────
	var in_rest := false
	var tree := get_tree()
	if tree:
		for node in tree.get_nodes_in_group("rest_zones"):
			if node is RestZone:
				var rz := node as RestZone
				var local: Vector3 = rz.to_local(global_position)
				var half: float = rz.length * 0.5
				if absf(local.z - half) < half + 2.0 \
					and Vector2(local.x, local.y).length() < rz.radius + 2.0:
					in_rest = true
					break
	rest_zone_inside = in_rest

	# ── Steering: rotate heading around the surface normal ────────────────
	# This is pure yaw relative to the tube surface — left/right turns the
	# vehicle, and from then on forward always means "where I'm pointing"
	# Steering input ramps smoothly instead of being all-or-nothing.
	var target_turn := Input.get_axis("ui_left", "ui_right")
	steering_amount = move_toward(steering_amount, target_turn, steer_accel * delta)
	if abs(steering_amount) > 0.001:
		var steer := Basis(inward, -steering_amount * turn_speed * delta)
		global_transform.basis = steer * global_transform.basis

	# ── Gravity ───────────────────────────────────────────────────────────
	if not is_on_floor():
		velocity += outward * gravity * delta

	# ── Centripetal force ─────────────────────────────────────────────────
	# When spiraling, circumferential velocity requires centripetal
	# acceleration to maintain the curved path — this manifests as
	# increased force pressing the vehicle into the wall, exactly like
	# banking hard in a real vehicle. The faster the spiral, the heavier
	# you feel. Forward progress along the tube axis slows automatically
	# because your velocity vector is pointing more sideways.
	var circ_vel    := velocity - velocity.dot(tube_axis) * tube_axis \
								- velocity.dot(outward)   * outward
	var to_self     := global_position - tube_origin
	var radial_dist := (to_self - tube_axis * to_self.dot(tube_axis)).length()
	var centripetal:float = circ_vel.length_squared() / max(radial_dist, 0.1)
	velocity += outward * centripetal * delta

	# ── Drive in the direction the vehicle is facing ──────────────────────
	var vehicle_fwd := -global_transform.basis.z
	vehicle_fwd = vehicle_fwd - vehicle_fwd.dot(outward) * outward
	if vehicle_fwd.length_squared() > 1e-4:
		vehicle_fwd = vehicle_fwd.normalized()
	else:
		vehicle_fwd = tube_axis

	var throttle    := Input.get_axis("ui_down", "ui_up")
	var radial_vel  := velocity.dot(outward) * outward
	var surface_vel := velocity - radial_vel

	var effective_speed := speed
	if rest_zone_inside:
		effective_speed = speed * 0.5

	if abs(throttle) > 0.001:
		surface_vel = surface_vel.move_toward(
				vehicle_fwd * throttle * effective_speed, acceleration * delta)
	else:
		surface_vel = surface_vel.move_toward(Vector3.ZERO, friction * delta)

	velocity = surface_vel + radial_vel

	# ── Keep vehicle flat on the tube surface ─────────────────────────────
	_flatten_to_surface(inward, delta)

	move_and_slide()

	# ── Sudden-stop detector (debug) ─────────────────────────────────────
	# If the player is accelerating forward but the speed drops sharply, the
	# vehicle likely hit unseen geometry. Log position + tube info for diagnosis.
	_sudden_stop_cooldown = maxf(0.0, _sudden_stop_cooldown - delta)
	var cur_speed := velocity.length()
	var throttle_input := Input.get_axis("ui_down", "ui_up")
	if throttle_input > 0.3 and _prev_speed > 5.0 and cur_speed < _prev_speed - 4.0 \
			and _sudden_stop_cooldown <= 0.0:
		_sudden_stop_cooldown = 1.0
		var sec := network.get_section_at(global_position) if network else null
		var to := Vector3.ZERO
		var ax := Vector3.ZERO
		var rad := 0.0
		var origin := global_position
		if sec:
			var stop_props := sec.get_tube_properties(global_position)
			ax = stop_props["axis"]
			origin = stop_props["origin"]
			rad = stop_props["radius"]
		print("SUDDEN STOP at ", global_position,
			" speed ", _prev_speed, " -> ", cur_speed,
			" throttle=", throttle_input,
			" section=", (sec.name if sec else "none"),
			" tube_origin=", origin,
			" tube_axis=", ax,
			" tube_radius=", rad,
			" radial_dist=", (global_position - origin).length())
	_prev_speed = cur_speed

	# Clamp to pipe wall to prevent high-speed tunneling through thin walls.
	# This supplements move_and_slide's collision, which can miss fast-moving
	# bodies against curved trimesh surfaces.
	var clamp_props: Dictionary = {}
	if network:
		var clamp_section := network.get_section_at(global_position)
		if clamp_section:
			clamp_props = clamp_section.get_tube_properties(global_position)
	if clamp_props:
		var clamp_axis: Vector3 = clamp_props["axis"]
		var clamp_origin: Vector3 = clamp_props["origin"]
		var clamp_radius: float = clamp_props["radius"]
		var to_center := global_position - clamp_origin
		var radial := to_center - to_center.dot(clamp_axis) * clamp_axis
		var radial_len := radial.length()
		if radial_len > clamp_radius - 0.3 and radial_len > 0.001:
			var clamped := clamp_origin + radial.normalized() * (clamp_radius - 0.3) + clamp_axis * to_center.dot(clamp_axis)
			global_position = clamped

func _find_audio_manager() -> AudioManager:
	if _audio_manager != null and is_instance_valid(_audio_manager):
		return _audio_manager
	if _audio_searched:
		return null
	_audio_searched = true
	var tree := get_tree()
	if tree == null:
		return null
	# Search autoloads / root children first.
	for child in tree.root.get_children():
		if child is AudioManager:
			_audio_manager = child as AudioManager
			return _audio_manager
	# Fall back to current scene children.
	if tree.current_scene:
		for child in tree.current_scene.get_children():
			if child is AudioManager:
				_audio_manager = child as AudioManager
				return _audio_manager
	return null

func _flatten_to_surface(up: Vector3, delta: float) -> void:
	var fwd := -global_transform.basis.z
	fwd = fwd - fwd.dot(up) * up
	if fwd.length_squared() < 1e-4:
		fwd = tube_axis
	else:
		fwd = fwd.normalized()
	var target := Basis.looking_at(fwd, up)
	global_transform.basis = global_transform.basis.slerp(target, delta * 14.0)

func take_damage(amount: float) -> void:
	health = maxf(0.0, health - amount)
	if health <= 0.0:
		print("PLAYER DEFEATED")