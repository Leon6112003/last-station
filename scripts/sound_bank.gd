class_name SoundBank
extends Node
## Small generated sound effects. No audio files: every sound is synthesised in code
## when the game starts, so the game stays offline, free and asset-free.
## Sounds are feedback only. Nothing in the game rules depends on them, and if audio
## is unavailable (muted, or a headless run) play() does nothing harmful.

const SAMPLE_RATE := 22050
const POOL_SIZE := 6
const NAMES := ["click", "chime", "buzz", "hiss", "win", "fail", "tick", "tock", "step"]

# Loudness in dB per sound (0 = full scale). Every effect is short. The only looping sound
# is the theme song (see ThemeMusic), which has no low drone and can be switched off with B.
const VOLUME_DB := {
	"click": -8.0, "chime": -6.0, "buzz": -9.0, "hiss": -14.0,
	"win": -5.0, "fail": -6.0, "tick": -14.0, "tock": -15.0, "step": -20.0,
}

const MUSIC_DB := -16.0
const MUSIC_FADE_SECONDS := 2.0

var muted: bool = false
var music_enabled: bool = true       # the player's music switch (B)
## Set before adding to the tree. Off in headless runs so tests do not render the song.
var load_music: bool = false

var _music: AudioStreamPlayer
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
	if _music != null:
		_music.stop()
		_music.stream = null
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
	_music = AudioStreamPlayer.new()
	_music.stream = ThemeMusic.build()
	_music.volume_db = MUSIC_DB
	add_child(_music)
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
			_music.stream_paused = false
			_music_fade = create_tween()
			_music_fade.tween_property(_music, "volume_db", MUSIC_DB, MUSIC_FADE_SECONDS)
	elif _music.playing:
		_music.stream_paused = true


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
