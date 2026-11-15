# audio_manager.gd  (Phase 7 — basic audio)
class_name AudioManager
extends Node

var engine_player: AudioStreamPlayer = null
var collision_player: AudioStreamPlayer = null
var spell_player: AudioStreamPlayer = null

func _ready() -> void:
	# Engine sound (continuous, pitch varies with speed).
	engine_player = AudioStreamPlayer.new()
	engine_player.volume_db = -10.0
	add_child(engine_player)

	# Collision sound.
	collision_player = AudioStreamPlayer.new()
	collision_player.volume_db = -5.0
	add_child(collision_player)

	# Spell cast sound.
	spell_player = AudioStreamPlayer.new()
	spell_player.volume_db = -5.0
	add_child(spell_player)

func play_engine(speed: float) -> void:
	if engine_player and engine_player.playing:
		engine_player.pitch_scale = 1.0 + speed * 0.02

func play_collision() -> void:
	if collision_player:
		collision_player.play()

func play_spell() -> void:
	if spell_player:
		spell_player.play()