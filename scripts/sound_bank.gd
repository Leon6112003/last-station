class_name SoundBank
extends Node
## Small generated sound effects. No audio files: every sound is synthesised in code
## when the game starts, so the game stays offline, free and asset-free.
## Sounds are feedback only. Nothing in the game rules depends on them, and if audio
## is unavailable (muted, or a headless run) play() does nothing harmful.

const SAMPLE_RATE := 22050
const POOL_SIZE := 6
const NAMES := ["click", "chime", "buzz", "hiss", "win", "fail", "tick", "tock", "step", "creak", "thud", "alarm", "spark", "heartbeat",
	"breath_in", "breath_out", "fan_down", "fan_up", "vent", "door_slide", "door_lock", "gasleak"]

# Loudness in dB per sound (0 = full scale). Every effect is short. The only looping sound
# is the theme song (see ThemeMusic), which has no low drone and can be switched off with B.
const VOLUME_DB := {
	"click": -6.0, "chime": -4.0, "buzz": -7.0, "hiss": -10.0,
	"win": -3.0, "fail": -4.0, "tick": -10.0, "tock": -11.0, "step": -16.0,
	# Survival atmosphere, played now and then (never as a constant drone).
	"creak": -11.0, "thud": -7.0, "alarm": -13.0, "spark": -11.0, "heartbeat": -7.0,
	"breath_in": -17.0, "breath_out": -18.0, "fan_down": -13.0, "fan_up": -12.0, "vent": -18.0,
	"door_slide": -9.0, "door_lock": -6.0, "gasleak": -11.0,
}

const MUSIC_DB := -11.0              # the calm layer
const TENSE_MUSIC_DB := -4.0         # the tense layer at full danger (louder than the calm layer)
const TENSE_SILENT_DB := -40.0       # ... and with no danger
const DANGER_BLEND_SPEED := 1.5      # danger moves this much per second, so the music swells instead of jumping
const MUSIC_FADE_SECONDS := 2.0

var muted: bool = false
var music_enabled: bool = true       # the player's music switch (B)
## Set before adding to the tree. Off in headless runs so tests do not render the song.
var load_music: bool = false

var _music: AudioStreamPlayer
var _music_tense: AudioStreamPlayer
var _danger: float = 0.0              # 0 safe .. 1 in great danger (set by the game)
var _danger_shown: float = 0.0
var _music_active: bool = false
var _music_fade: Tween

var _streams: Dictionary = {}
var _pool: Array[AudioStreamPlayer] = []
var _next: int = 0


func _ready() -> void:
	for sound_name in NAMES:
		_streams[sound_name] = build_stream(sound_name)
	for i in POOL_SIZE:
		var player := AudioStreamPlayer.new()
		add_child(player)
		_pool.append(player)
	if load_music:
		# Rendering the song takes about half a second: do it after the first frame.
		_load_music.call_deferred()


func _exit_tree() -> void:
	# Release every playback so none outlives the game at exit.
	for player in _pool:
		player.stop()
		player.stream = null
	for layer in [_music, _music_tense]:
		if layer != null:
			layer.stop()
			layer.stream = null
	_streams.clear()


## Plays a sound once. Unknown names and a muted bank are ignored.
func play(sound_name: String) -> void:
	if muted or not _streams.has(sound_name) or _pool.is_empty():
		return
	var player := _pool[_next]
	_next = (_next + 1) % _pool.size()
	player.stream = _streams[sound_name]
	player.volume_db = VOLUME_DB[sound_name]
	player.play()


func set_muted(value: bool) -> void:
	muted = value
	if muted:
		for player in _pool:
			player.stop()
	_apply_music_state()


func _load_music() -> void:
	if _music != null or not is_inside_tree():
		return
	var layers := ThemeMusic.build_layers()
	_music = AudioStreamPlayer.new()
	_music.stream = layers[0]
	_music.volume_db = MUSIC_DB
	add_child(_music)
	_music_tense = AudioStreamPlayer.new()
	_music_tense.stream = layers[1]
	_music_tense.volume_db = TENSE_SILENT_DB
	add_child(_music_tense)
	_apply_music_state()


## The theme song plays while a shift is running (not in menus, pause or results).
func set_music_active(active: bool) -> void:
	if active == _music_active:
		return
	_music_active = active
	_apply_music_state()


## The player's music switch. Returns the new state.
func set_music_enabled(value: bool) -> void:
	music_enabled = value
	_apply_music_state()


## How much danger the player is in, 0 to 1. The tense layer of the music swells with it.
func set_music_danger(level: float) -> void:
	_danger = clampf(level, 0.0, 1.0)


func _process(delta: float) -> void:
	_danger_shown = move_toward(_danger_shown, _danger, DANGER_BLEND_SPEED * delta)
	if _music_tense != null:
		# The tense layer follows the danger, and the same fade-in offset as the calm layer.
		var fade_offset := _music.volume_db - MUSIC_DB
		_music_tense.volume_db = lerpf(TENSE_SILENT_DB, TENSE_MUSIC_DB, pow(_danger_shown, 0.5)) + minf(fade_offset, 0.0)


func is_music_playing() -> bool:
	return _music != null and _music.playing and not _music.stream_paused


func _apply_music_state() -> void:
	if _music == null:
		return
	var should_play := _music_active and music_enabled and not muted
	if should_play:
		if not _music.playing or _music.stream_paused:
			# Start or resume with a fade-in rather than at full volume.
			if _music_fade != null:
				_music_fade.kill()
			_music.volume_db = -40.0
			if not _music.playing:
				_music.play()
				_music_tense.play()   # both layers start together, so they stay in sync
			_music.stream_paused = false
			_music_tense.stream_paused = false
			_music_fade = create_tween()
			_music_fade.tween_property(_music, "volume_db", MUSIC_DB, MUSIC_FADE_SECONDS)
	elif _music.playing:
		_music.stream_paused = true
		_music_tense.stream_paused = true


## Builds one sound as a 16-bit mono stream. Deterministic (a fixed noise seed).
static func build_stream(sound_name: String) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var samples := PackedFloat32Array()
	match sound_name:
		"click":
			samples = _render(0.07, func(t: float) -> float:
				return (rng.randf_range(-1.0, 1.0) * 0.5 + sin(TAU * 1300.0 * t) * 0.5) * exp(-t * 55.0))
		"chime":
			samples = _render(0.8, func(t: float) -> float:
				var late := maxf(0.0, t - 0.12)
				return (sin(TAU * 659.0 * t) * exp(-t * 5.0) + sin(TAU * 988.0 * late) * exp(-late * 5.0) * float(t > 0.12)) * 0.5)
		"buzz":
			samples = _render(0.4, func(t: float) -> float:
				var wave := 1.0 if sin(TAU * 110.0 * t) > 0.0 else -1.0
				return wave * 0.35 * exp(-t * 4.0) * minf(1.0, t * 200.0))
		"hiss":
			var smooth := [0.0]
			samples = _render(0.25, func(t: float) -> float:
				smooth[0] = smooth[0] * 0.75 + rng.randf_range(-1.0, 1.0) * 0.25
				return smooth[0] * sin(PI * t / 0.25))
		"win":
			samples = _render(1.0, func(t: float) -> float:
				var notes := [523.0, 659.0, 784.0, 1047.0]
				var value := 0.0
				for i in notes.size():
					var start := 0.14 * i
					if t >= start:
						value += sin(TAU * notes[i] * (t - start)) * exp(-(t - start) * 4.0)
				return value * 0.3)
		"fail":
			samples = _render(0.9, func(t: float) -> float:
				# A falling sweep from 440 Hz to 100 Hz (phase is the integral of the frequency).
				var phase := TAU * (440.0 * t - 340.0 * t * t / 1.8)
				return sin(phase) * 0.45 * (1.0 - t / 0.9))
		"tick":
			# A soft clock tick: a short, dry click with a little body. "tock" is the lower twin.
			samples = _render(0.06, func(t: float) -> float:
				return (sin(TAU * 1900.0 * t) * 0.6 + rng.randf_range(-1.0, 1.0) * 0.15) * exp(-t * 85.0))
		"tock":
			samples = _render(0.07, func(t: float) -> float:
				return (sin(TAU * 1250.0 * t) * 0.6 + rng.randf_range(-1.0, 1.0) * 0.15) * exp(-t * 75.0))
		"step":
			var smooth := [0.0]
			samples = _render(0.09, func(t: float) -> float:
				smooth[0] = smooth[0] * 0.8 + rng.randf_range(-1.0, 1.0) * 0.2
				return (smooth[0] * 0.8 + sin(TAU * 80.0 * t) * 0.4) * exp(-t * 45.0))
		"creak":
			# A long metal groan: a slowly falling, rasping note with a wobble, like a
			# stressed hull plate, fading in and out.
			samples = _render(1.7, func(t: float) -> float:
				var phase := TAU * (230.0 * t - 80.0 * t * t / 3.4)
				var body := sin(phase) + 0.5 * sin(2.0 * phase) + 0.3 * sin(3.0 * phase)
				var wobble := 1.0 + 0.4 * sin(TAU * 17.0 * t)
				var envelope := pow(sin(PI * t / 1.7), 1.5)
				return (body * wobble * 0.3 + rng.randf_range(-1.0, 1.0) * 0.05) * envelope)
		"thud":
			# A distant bang somewhere in the station: a deep thump and a metallic ring.
			samples = _render(1.0, func(t: float) -> float:
				var thump := sin(TAU * (60.0 + 40.0 * exp(-t * 20.0)) * t) * exp(-t * 6.0) * 0.7
				var knock := rng.randf_range(-1.0, 1.0) * exp(-t * 35.0) * 0.3
				var ring := (sin(TAU * 410.0 * t) + 0.6 * sin(TAU * 1130.0 * t)) * exp(-t * 6.0) * 0.12
				return thump + knock + ring)
		"alarm":
			# A station alarm: two short harsh beeps.
			samples = _render(0.95, func(t: float) -> float:
				var local := fmod(t, 0.45)
				if local > 0.26 or t > 0.9:
					return 0.0
				var wave := 1.0 if sin(TAU * 760.0 * t) > 0.0 else -1.0
				return wave * 0.3 * minf(1.0, local * 120.0) * minf(1.0, (0.26 - local) * 120.0))
		"spark":
			# Electric crackle: sparse, sharp clicks of noise.
			var previous := [0.0]
			samples = _render(0.4, func(t: float) -> float:
				var noise := rng.randf_range(-1.0, 1.0)
				var crackle: float = (noise - float(previous[0])) if rng.randf() > 0.82 else 0.0
				previous[0] = noise
				return crackle * exp(-t * 7.0) * 0.9)
		"heartbeat":
			# A frightened heartbeat: lub-dub.
			samples = _render(0.7, func(t: float) -> float:
				var lub := sin(TAU * (58.0 + 30.0 * exp(-t * 25.0)) * t) * exp(-t * 14.0)
				var late := maxf(0.0, t - 0.26)
				var dub := sin(TAU * (52.0 + 25.0 * exp(-late * 25.0)) * late) * exp(-late * 14.0) * float(t > 0.26) * 0.7
				return (lub + dub) * 0.8)
		"breath_in":
			# Breathing inside the helmet: a soft, airy inhale.
			var smooth := [0.0]
			samples = _render(1.1, func(t: float) -> float:
				smooth[0] = smooth[0] * 0.55 + rng.randf_range(-1.0, 1.0) * 0.45
				return smooth[0] * pow(sin(PI * t / 1.1), 1.4) * (0.4 + 0.6 * t / 1.1) * 0.7)
		"breath_out":
			var smooth := [0.0]
			samples = _render(1.4, func(t: float) -> float:
				smooth[0] = smooth[0] * 0.7 + rng.randf_range(-1.0, 1.0) * 0.3
				return smooth[0] * pow(sin(PI * t / 1.4), 1.2) * (1.0 - 0.5 * t / 1.4) * 0.8)
		"fan_down":
			# A ventilation fan winding down as the power fails: a whirr that falls in pitch.
			samples = _render(2.0, func(t: float) -> float:
				var phase := TAU * (190.0 * t - 70.0 * t * t / 4.0)
				var whirr := (sin(phase) + 0.4 * sin(2.0 * phase)) * (1.0 + 0.5 * sin(TAU * (16.0 - 5.0 * t) * t))
				return (whirr * 0.22 + rng.randf_range(-1.0, 1.0) * 0.06) * pow(sin(PI * t / 2.0), 0.8))
		"fan_up":
			# ... and spinning back up when a system is repaired: the same whirr rising.
			samples = _render(1.8, func(t: float) -> float:
				var phase := TAU * (110.0 * t + 80.0 * t * t / 3.6)
				var whirr := (sin(phase) + 0.4 * sin(2.0 * phase)) * (1.0 + 0.4 * sin(TAU * (8.0 + 6.0 * t) * t))
				return (whirr * 0.22 + rng.randf_range(-1.0, 1.0) * 0.05) * pow(sin(PI * t / 1.8), 0.8))
		"vent":
			# Air moving through the ducts: a slow airy whoosh.
			var smooth := [0.0]
			samples = _render(2.0, func(t: float) -> float:
				smooth[0] = smooth[0] * 0.8 + rng.randf_range(-1.0, 1.0) * 0.2
				return smooth[0] * pow(sin(PI * t / 2.0), 2.0) * 1.2)
		"door_slide":
			# A heavy door sliding: a small motor rising in pitch, a rush of air, a final clunk.
			samples = _render(0.9, func(t: float) -> float:
				var motor := sin(TAU * (160.0 * t + 90.0 * t * t)) * 0.25 * minf(1.0, t * 12.0) * (1.0 if t < 0.75 else 0.0)
				var air := rng.randf_range(-1.0, 1.0) * 0.12 * sin(PI * minf(t / 0.75, 1.0))
				var late := maxf(0.0, t - 0.75)
				var clunk := (sin(TAU * 85.0 * late) * exp(-late * 30.0) * 0.6 + rng.randf_range(-1.0, 1.0) * exp(-late * 90.0) * 0.3) * float(t >= 0.75)
				return motor + air + clunk)
		"door_lock":
			# The "denied" clunk of a locked door: a dull thump with a metallic click.
			samples = _render(0.45, func(t: float) -> float:
				return sin(TAU * 90.0 * t) * exp(-t * 16.0) * 0.7 + rng.randf_range(-1.0, 1.0) * exp(-t * 90.0) * 0.4 + sin(TAU * 520.0 * t) * exp(-t * 22.0) * 0.2)
		"gasleak":
			# A leaking gas vent: a harsh, steady hiss.
			var previous := [0.0]
			samples = _render(0.55, func(t: float) -> float:
				var noise := rng.randf_range(-1.0, 1.0)
				var sharp: float = noise * 0.75 - float(previous[0]) * 0.35
				previous[0] = noise
				return sharp * pow(sin(PI * t / 0.55), 0.5) * 0.6)
	return _to_stream(samples)


static func _render(duration: float, sample_at: Callable) -> PackedFloat32Array:
	var count := int(duration * SAMPLE_RATE)
	var samples := PackedFloat32Array()
	samples.resize(count)
	for i in count:
		samples[i] = clampf(sample_at.call(float(i) / SAMPLE_RATE), -1.0, 1.0)
	return samples


static func _to_stream(samples: PackedFloat32Array) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		bytes.encode_s16(i * 2, int(samples[i] * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = false
	stream.data = bytes
	return stream
