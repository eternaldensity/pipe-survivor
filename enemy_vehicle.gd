# enemy_vehicle.gd  (Phase 5 — archetypes)
class_name EnemyVehicle
extends CharacterBody3D

enum EnemyType { CHASER, AMBUSHER }

@export var enemy_type: EnemyType = EnemyType.CHASER
@export var network: PipeNetwork
@export var target: Node3D  # the player vehicle

var tube_origin := Vector3.ZERO
var tube_axis := Vector3(0.0, 0.0, 1.0)
var tube_radius := 10.0

# Type-specific stats.
var speed: float = 12.0
var health: float = 3.0
var gravity: float = 25.0

# Ambusher state.
var _ambush_active: bool = false
var _activation_distance: float = 40.0

# Sigil weakness (Phase 4/5 integration).
@export var weakness_family: String = ""  # attractor family this enemy is weak to (empty = none)
@export var weakness_multiplier: float = 2.0  # damage multiplier when hit by matching family
@export var resistance: float = 1.0  # base damage resistance (lower = tougher)
# Shape-based weakness: enemy is weak to spells whose rho is above/below threshold.
@export var weakness_rho_above: float = -1.0  # if >= 0, weak when spell rho > this value
@export var weakness_rho_below: float = -1.0  # if >= 0, weak when spell rho < this value
# Geometric feature weakness (Phase 5 refinement).
@export var weakness_feature: String = ""  # "high_lobe", "high_symmetry", "elongated", ""
@export var weakness_feature_threshold: float = 0.5

func _ready() -> void:
	match enemy_type:
		EnemyType.CHASER:
			speed = 15.0
			health = 2.0
		EnemyType.AMBUSHER:
			speed = 8.0
			health = 4.0

func _physics_process(delta: float) -> void:
	if network == null or target == null:
		return
	var section := network.get_section_at(global_position)
	if section == null:
		return
	var props := section.get_tube_properties(global_position)
	tube_axis = props["axis"]
	tube_origin = props["origin"]
	tube_radius = props["radius"]

	var outward := _outward_from(props)
	var inward := -outward
	up_direction = inward

	# Gravity toward wall.
	if not is_on_floor():
		velocity += outward * gravity * delta

	# Determine effective speed based on type and state.
	var effective_speed := speed
	if enemy_type == EnemyType.AMBUSHER and not _ambush_active:
		# Ambushers wait until the player is close.
		var dist_to_player := global_position.distance_to(target.global_position)
		if dist_to_player < _activation_distance:
			_ambush_active = true
		else:
			effective_speed = 0.0

	# Chase the player: move toward target along the tube.
	var to_target := target.global_position - global_position
	var along_axis := to_target.dot(tube_axis)
	var dir := tube_axis if along_axis > 0.0 else -tube_axis
	var desired := dir * effective_speed
	# Add circumferential steering toward target.
	var to_target_perp := to_target - to_target.dot(tube_axis) * tube_axis
	if to_target_perp.length_squared() > 1e-4:
		var circ_dir := to_target_perp.normalized()
		desired += circ_dir * effective_speed * 0.3

	var radial_vel := velocity.dot(outward) * outward
	var surface_vel := velocity - radial_vel
	surface_vel = surface_vel.move_toward(desired, 30.0 * delta)
	velocity = surface_vel + radial_vel

	_flatten(delta, inward)
	move_and_slide()

	# Contact damage to the player.
	if target and global_position.distance_to(target.global_position) < 2.0:
		if target.has_method("take_damage"):
			target.take_damage(10.0 * delta)

func _outward_from(props: Dictionary) -> Vector3:
	var axis: Vector3 = props["axis"]
	var origin: Vector3 = props["origin"]
	var to_self: Vector3 = global_position - origin
	var radial: Vector3 = to_self - to_self.dot(axis) * axis
	if radial.length_squared() < 1e-4:
		return axis.cross(Vector3.UP).normalized()
	return radial.normalized()

func _flatten(delta: float, up: Vector3) -> void:
	var fwd := -global_transform.basis.z
	fwd = fwd - fwd.dot(up) * up
	if fwd.length_squared() < 1e-4:
		fwd = tube_axis
	else:
		fwd = fwd.normalized()
	var target := Basis.looking_at(fwd, up)
	global_transform.basis = global_transform.basis.slerp(target, delta * 14.0)

func take_damage(amount: float, spell_family: String = "", spell_rho: float = 0.0, shape_features: Dictionary = {}) -> void:
	var dmg := amount * resistance
	var weak := false
	if weakness_family != "" and spell_family == weakness_family:
		weak = true
	if weakness_rho_above >= 0.0 and spell_rho > weakness_rho_above:
		weak = true
	if weakness_rho_below >= 0.0 and spell_rho < weakness_rho_below:
		weak = true
	# Geometric feature weakness.
	if weakness_feature != "" and shape_features.size() > 0:
		match weakness_feature:
			"high_lobe":
				if shape_features.get("lobe_count", 0) >= weakness_feature_threshold:
					weak = true
			"high_symmetry":
				var sym: float = shape_features.get("symmetry_x", 0.0)
				if sym > weakness_feature_threshold:
					weak = true
			"elongated":
				var ar: float = shape_features.get("aspect_ratio", 1.0)
				if ar > weakness_feature_threshold:
					weak = true
	if weak:
		dmg *= weakness_multiplier
	health -= dmg
	if health <= 0.0:
		queue_free()