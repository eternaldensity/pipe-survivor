# audio_manager.gd  (Phase 7 — basic audio with generated tones)
class_name AudioManager
extends Node

var engine_player: AudioStreamPlayer = null
var collision_player: AudioStreamPlayer = null
var spell_player: AudioStreamPlayer = null
var engine_generator: AudioStreamGenerator = null
var engine_playback: AudioStreamGeneratorPlayback = null

var _engine_phase: float = 0.0
var _engine_freq: float = 220.0

func _ready() -> void:
	# Engine sound (continuous tone, pitch varies with speed).
	engine_generator = AudioStreamGenerator.new()
	engine_generator.mix_rate = 22050
	engine_generator.buffer_length = 0.1
	engine_player = AudioStreamPlayer.new()
	engine_player.stream = engine_generator
	engine_player.volume_db = -15.0
	add_child(engine_player)
	engine_player.play()
	engine_playback = engine_player.get_stream_playback()

	# Collision sound (short beep).
	collision_player = AudioStreamPlayer.new()
	collision_player.stream = _make_beep(440.0, 0.1)
	collision_player.volume_db = -8.0
	add_child(collision_player)

	# Spell cast sound (higher beep).
	spell_player = AudioStreamPlayer.new()
	spell_player.stream = _make_beep(660.0, 0.15)
	spell_player.volume_db = -8.0
	add_child(spell_player)

func _make_beep(freq: float, dur: float) -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	var samples := int(22050 * dur)
	var data := PackedByteArray()
	data.resize(samples * 2)  # 16-bit
	for i in range(samples):
		var t := float(i) / 22050.0
		var env := 1.0 - (float(i) / float(samples))
		var val := sin(t * freq * TAU) * env * 0.5
		var int_val := int(val * 32767.0)
		data[i * 2] = int_val & 0xFF
		data[i * 2 + 1] = (int_val >> 8) & 0xFF
	wav.data = data
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = 22050
	wav.stereo = false
	return wav

func _process(delta: float) -> void:
	# Fill engine sound buffer.
	if engine_playback:
		var frames := engine_playback.get_frames_available()
		for i in range(frames):
			var t := _engine_phase
			var val := sin(t * _engine_freq * TAU) * 0.15
			engine_playback.push_frame(Vector2(val, val))
			_engine_phase += 1.0 / 22050.0

func play_engine(speed: float) -> void:
	_engine_freq = 220.0 + speed * 5.0

func play_collision() -> void:
	if collision_player:
		collision_player.play()

func play_spell() -> void:
	if spell_player:
		spell_player.play()