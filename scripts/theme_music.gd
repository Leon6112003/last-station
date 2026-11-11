class_name ThemeMusic
extends RefCounted
## The game's theme song, composed and synthesised in code (no audio files). It is made of
## two layers that play in sync: a calm one, always on, and a tense one that the game fades
## in as danger rises (low reserve, gas, the gravity). Played together they are the full song.
## Survival mood: dread that turns to panic.
##   calm layer (12 bars at 100 BPM, about 29 seconds, looping): a slow heartbeat (lub-dub),
##              a rasping string pad on clashing chords, thin bells leaning on the semitone
##              and a metal impact with long echoes;
##   tense layer: a stalking eighth-note ostinato built on a flat second and a tritone
##              (A, Bb, Eb), a second heartbeat, ticking hi-hats, a distant two-tone alarm
##              (a tritone apart), and a hiss that swells and cuts out before the loop restarts.
## There is no sustained low tone or sub-bass (a constant low hum is tiring): every pitched
## note is at or above A3, and the heartbeat is a short thump, not a drone. Every note rings
## over the end of the loop and wraps to the start, so there is no seam.

const SAMPLE_RATE := 16000
const BEAT_SAMPLES := 9600                  # 100 BPM at 16000 Hz (0.6 s)
const BEATS_PER_BAR := 4
const BAR_COUNT := 12
const A3_HZ := 220.0

# Chords as semitones above A3, three bars each: Am(b9), Bb, A diminished 7, E7(b9).
const CHORDS := [
	[0, 3, 7, 13],
	[1, 5, 8, 13],
	[0, 3, 6, 9],
	[7, 11, 14, 20],
]
const BARS_PER_CHORD := 3
# The ostinato: one entry per eighth note of a bar, [semitones above the chord root, gain].
const OSTINATO := [
	[0, 1.0], [0, 0.5], [12, 0.7], [0, 0.5], [1, 0.9], [0, 0.5], [6, 0.8], [0, 0.6],
]
const OSTINATO_FIRST_BAR := 4
const PRESSURE_FIRST_BAR := 8
# Melody bells: [bar, beat within the bar, semitones above A3]. High, sparse, on the semitone.
const MELODY := [
	[1, 0.0, 24], [1, 2.5, 25], [3, 0.0, 24], [3, 3.0, 20],
	[5, 1.0, 25], [7, 0.0, 24], [7, 2.0, 22],
	[9, 0.0, 25], [11, 0.0, 24], [11, 2.0, 18],
]
# Metal impacts: [bar, beat, gain].
const IMPACTS := [[0, 0.0, 1.0], [6, 2.0, 0.7]]
const ALARM_SEMITONES := [12, 18]           # A4 then Eb5: a tritone apart

const PAD_GAIN := 0.06
const HEART_GAIN := 0.38
const OSTINATO_GAIN := 0.15
const TICK_GAIN := 0.07
const MELODY_GAIN := 0.2
const IMPACT_GAIN := 0.32
const ALARM_GAIN := 0.05
const ECHO_DELAY_BEATS := 1.5
const RISER_GAIN := 0.1
const PEAK := 0.7                           # the finished loop is scaled to this peak


static func total_samples() -> int:
	return BEAT_SAMPLES * BEATS_PER_BAR * BAR_COUNT


static func hz(semitones: int) -> float:
	return A3_HZ * pow(2.0, float(semitones) / 12.0)


## Renders the whole song as one stream. Takes a second or two, so the game does it after
## the first frame.
static func build() -> AudioStreamWAV:
	var layers := _render_layers()
	var total := total_samples()
	var mix := PackedFloat32Array()
	mix.resize(total)
	for i in total:
		mix[i] = layers[0][i] + layers[1][i]
	return _to_stream(mix, total, _scale_for(mix))


## Renders the song as two layers of the same length, so they can play in sync:
##   [0] the calm layer (always on): pad, slow heartbeat, bells and the metal impacts;
##   [1] the tense layer: the stalking ostinato, extra heartbeat, hi-hat ticks, the alarm
##       and the rising hiss. The game fades it in as the danger rises.
## Both use the loudness scale of the full mix, so together they sound like build().
static func build_layers() -> Array[AudioStreamWAV]:
	var layers := _render_layers()
	var total := total_samples()
	var mix := PackedFloat32Array()
	mix.resize(total)
	for i in total:
		mix[i] = layers[0][i] + layers[1][i]
	var scale := _scale_for(mix)
	var streams: Array[AudioStreamWAV] = []
	streams.append(_to_stream(layers[0], total, scale))
	streams.append(_to_stream(layers[1], total, scale))
	return streams


static func _render_layers() -> Array:
	var total := total_samples()
	var calm := PackedFloat32Array()
	calm.resize(total)
	var tense := PackedFloat32Array()
	tense.resize(total)
	var cache := {}
	var bar_samples := BEAT_SAMPLES * BEATS_PER_BAR
	var eighth := BEAT_SAMPLES / 2
	var echo := int(ECHO_DELAY_BEATS * BEAT_SAMPLES)

	for bar in BAR_COUNT:
		var chord: Array = CHORDS[(bar / BARS_PER_CHORD) % CHORDS.size()]
		var bar_start := bar * bar_samples
		for semitone in chord:
			_add_pad(calm, bar_start, bar_samples, int(semitone), cache)
		_add_heartbeat(calm, bar_start, [0.0, 2.0], cache)
		_add_heartbeat(tense, bar_start, [1.0, 3.0], cache)
		for step in OSTINATO.size():
			var tone: int = int(chord[0]) + int(OSTINATO[step][0])
			var gain: float = float(OSTINATO[step][1])
			_add_wave(tense, bar_start + step * eighth, _saw_pluck(tone, cache), OSTINATO_GAIN * gain)
		for step in range(1, 8, 2):   # hi-hat ticks on the off eighths
			_add_wave(tense, bar_start + step * eighth, _tick(cache), TICK_GAIN)
		for beat in 2:
			var note: int = ALARM_SEMITONES[beat]
			_add_wave(tense, bar_start + beat * BEAT_SAMPLES, _alarm(note, cache), ALARM_GAIN)
	for note in MELODY:
		var start := int(note[0]) * bar_samples + int(float(note[1]) * BEAT_SAMPLES)
		_add_wave(calm, start, _bell(int(note[2]), cache), MELODY_GAIN)
		_add_wave(calm, start + echo, _bell(int(note[2]), cache), MELODY_GAIN * 0.3)
	for hit in IMPACTS:
		var start := int(hit[0]) * bar_samples + int(float(hit[1]) * BEAT_SAMPLES)
		var gain: float = IMPACT_GAIN * float(hit[2])
		_add_wave(calm, start, _impact(cache), gain)
		_add_wave(calm, start + echo, _impact(cache), gain * 0.35)
		_add_wave(calm, start + 2 * echo, _impact(cache), gain * 0.12)
	# A hiss swells through the last bar of each half; the second drops away before the loop restarts.
	_add_riser(tense, 7 * bar_samples, bar_samples)
	_add_riser(tense, 11 * bar_samples, bar_samples)
	return [calm, tense]


## A "lub-dub" heartbeat on each of the given beats of a bar.
static func _add_heartbeat(mix: PackedFloat32Array, bar_start: int, beats: Array, cache: Dictionary) -> void:
	var dub_delay := int(0.42 * BEAT_SAMPLES)
	for beat in beats:
		var start := bar_start + int(float(beat) * BEAT_SAMPLES)
		_add_wave(mix, start, _thump(cache), HEART_GAIN)
		_add_wave(mix, start + dub_delay, _thump(cache), HEART_GAIN * 0.6)


## A thump: a short sine that falls quickly in pitch, so it is felt as a beat, not a tone.
static func _thump(cache: Dictionary) -> PackedFloat32Array:
	if cache.has("thump"):
		return cache["thump"]
	var count := int(0.35 * SAMPLE_RATE)
	var wave := PackedFloat32Array()
	wave.resize(count)
	var phase := 0.0
	for i in count:
		var t := float(i) / SAMPLE_RATE
		var f := 62.0 + 80.0 * exp(-t * 28.0)
		phase += TAU * f / SAMPLE_RATE
		wave[i] = sin(phase) * exp(-t * 11.0) * minf(1.0, t * 600.0)
	cache["thump"] = wave
	return wave


## A stalking note: a sawtooth-ish pluck (harmonics falling off at different speeds), so
## it sounds bowed and rasping, with a short decay.
static func _saw_pluck(semitone: int, cache: Dictionary) -> PackedFloat32Array:
	var key := "s%d" % semitone
	if cache.has(key):
		return cache[key]
	var f := hz(semitone)
	var count := int(0.3 * SAMPLE_RATE)
	var wave := PackedFloat32Array()
	wave.resize(count)
	for i in count:
		var t := float(i) / SAMPLE_RATE
		var sum := 0.0
		for h in range(1, 6):
			sum += sin(TAU * f * h * t) / h * exp(-t * (6.0 + 5.0 * h))
		wave[i] = sum * minf(1.0, t * 500.0)
	cache[key] = wave
	return wave


## A bell: a sine plus a slightly inharmonic overtone, ringing long.
static func _bell(semitone: int, cache: Dictionary) -> PackedFloat32Array:
	var key := "b%d" % semitone
	if cache.has(key):
		return cache[key]
	var f := hz(semitone)
	var count := int(2.2 * SAMPLE_RATE)
	var wave := PackedFloat32Array()
	wave.resize(count)
	for i in count:
		var t := float(i) / SAMPLE_RATE
		var attack := minf(1.0, t * 250.0)
		wave[i] = (sin(TAU * f * t) * exp(-t * 1.9) + 0.3 * sin(TAU * 2.01 * f * t) * exp(-t * 3.8)) * attack
	cache[key] = wave
	return wave


## A metallic impact: a burst of noise and inharmonic partials, like a pipe struck in a
## big dark room. Meant to be echoed.
static func _impact(cache: Dictionary) -> PackedFloat32Array:
	if cache.has("impact"):
		return cache["impact"]
	var rng := RandomNumberGenerator.new()
	rng.seed = 100
	var count := int(1.8 * SAMPLE_RATE)
	var wave := PackedFloat32Array()
	wave.resize(count)
	var base := 310.0
	var ratios := [1.0, 2.76, 5.4, 8.93]
	for i in count:
		var t := float(i) / SAMPLE_RATE
		var sum := rng.randf_range(-1.0, 1.0) * exp(-t * 60.0) * 0.8
		for k in ratios.size():
			sum += sin(TAU * base * float(ratios[k]) * t) * exp(-t * (2.2 + 1.6 * k)) / float(k + 1)
		wave[i] = sum * minf(1.0, t * 800.0)
	cache["impact"] = wave
	return wave


## A hi-hat tick: a very short burst of high-passed noise.
static func _tick(cache: Dictionary) -> PackedFloat32Array:
	if cache.has("tick"):
		return cache["tick"]
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var count := int(0.05 * SAMPLE_RATE)
	var wave := PackedFloat32Array()
	wave.resize(count)
	var previous := 0.0
	for i in count:
		var t := float(i) / SAMPLE_RATE
		var noise := rng.randf_range(-1.0, 1.0)
		wave[i] = (noise - previous) * exp(-t * 110.0)
		previous = noise
	cache["tick"] = wave
	return wave


## A distant alarm beep: a soft square-ish tone (odd harmonics) with a gentle shape.
static func _alarm(semitone: int, cache: Dictionary) -> PackedFloat32Array:
	var key := "a%d" % semitone
	if cache.has(key):
		return cache[key]
	var f := hz(semitone)
	var count := int(0.42 * SAMPLE_RATE)
	var wave := PackedFloat32Array()
	wave.resize(count)
	for i in count:
		var t := float(i) / SAMPLE_RATE
		var shape := minf(1.0, t * 80.0) * minf(1.0, (0.42 - t) * 40.0)
		wave[i] = (sin(TAU * f * t) + sin(TAU * 3.0 * f * t) / 3.0 + sin(TAU * 5.0 * f * t) / 5.0) * shape
	cache[key] = wave
	return wave


## A soft rising hiss (smoothed noise) that fades out in the last moments of its span, so
## the loop seam stays quiet.
static func _add_riser(mix: PackedFloat32Array, start: int, span: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 66
	var smooth := 0.0
	var total := mix.size()
	var release := int(0.35 * SAMPLE_RATE)
	for i in span:
		smooth = smooth * 0.6 + rng.randf_range(-1.0, 1.0) * 0.4
		var progress := float(i) / span
		var envelope := progress * progress
		if i > span - release:
			envelope *= float(span - i) / release
		mix[(start + i) % total] += smooth * envelope * RISER_GAIN


## One string-pad tone across a bar. A one-second cycle of the tone (a sawtooth built from a
## few harmonics, with a second copy one hertz higher beating against it) is rendered once,
## with the pitch rounded to a whole number of hertz so the cycle repeats cleanly, and then
## tiled under a swell envelope that overlaps into the next bar.
static func _add_pad(mix: PackedFloat32Array, bar_start: int, bar_samples: int, semitone: int, cache: Dictionary) -> void:
	var f := roundf(hz(semitone))
	var key := "pad%d" % int(f)
	if not cache.has(key):
		var cycle := PackedFloat32Array()
		cycle.resize(SAMPLE_RATE)
		for i in SAMPLE_RATE:
			var t := float(i) / SAMPLE_RATE
			var sum := 0.0
			for h in range(1, 5):
				sum += (sin(TAU * f * h * t) * 0.6 + sin(TAU * (f + 1.0) * h * t) * 0.4) / h
			cycle[i] = sum
		cache[key] = cycle
	var cycle: PackedFloat32Array = cache[key]
	var length := bar_samples + int(0.8 * SAMPLE_RATE)
	var swell := int(0.9 * SAMPLE_RATE)
	var total := mix.size()
	for i in length:
		var envelope := 1.0
		if i < swell:
			envelope = smoothstep(0.0, 1.0, float(i) / swell)
		elif i > length - swell:
			envelope = smoothstep(0.0, 1.0, float(length - i) / swell)
		var index := (bar_start + i) % total
		mix[index] += cycle[i % SAMPLE_RATE] * envelope * PAD_GAIN


## Adds a note's samples into the mix, wrapping round the end so the loop is seamless.
static func _add_wave(mix: PackedFloat32Array, start: int, wave: PackedFloat32Array, gain: float) -> void:
	var total := mix.size()
	for i in wave.size():
		mix[(start + i) % total] += wave[i] * gain


## The loudness scale that brings a mix to PEAK.
static func _scale_for(mix: PackedFloat32Array) -> float:
	var peak := 0.0001
	for i in mix.size():
		peak = maxf(peak, absf(mix[i]))
	return PEAK / peak


static func _to_stream(mix: PackedFloat32Array, total: int, scale: float) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(total * 2)
	for i in total:
		bytes.encode_s16(i * 2, int(clampf(mix[i] * scale, -1.0, 1.0) * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = false
	stream.data = bytes
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_end = total
	return stream
