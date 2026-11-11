class_name ThemeMusic
extends RefCounted
## The game's theme song, composed and synthesised in code (no audio files).
## Survival mood: slow, dark and tense. Detuned pads that shimmer and beat against each
## other, harmony full of semitone clashes (D minor, B-flat, G minor with a flat sixth,
## then an A7 with a flat ninth that never quite resolves), a muted pulse like a nervous
## heartbeat, a sonar ping with long echoes, a thin haunting bell melody that leans on
## the semitone, and a hiss that swells before each turn of the loop. It stays in the
## middle and upper register on purpose: there is no low drone or sub-bass, because a
## constant low tone is tiring. Eight bars at 66 BPM, about 29 seconds, looping without a
## seam (every note rings over the end of the loop and wraps to the start).

const SAMPLE_RATE := 16000
const BEAT_SAMPLES := 14545                 # 66 BPM at 16000 Hz (about 0.91 s)
const BEATS_PER_BAR := 4
const BAR_COUNT := 8
const A3_HZ := 220.0

# Chords as semitones above A3: Dm(add9) with a clash, Bbmaj7, Gm(b6), A7(b9).
const CHORDS := [
	[0, 5, 7, 8],
	[1, 5, 8, 12],
	[-2, 1, 5, 6],
	[0, 4, 7, 13],
]
# The pulse: one entry per eighth note of a bar. 0 = rest, otherwise a gain; a nervous,
# off-beat heartbeat. The pitch alternates between the chord's first two tones.
const PULSE := [1.0, 0.0, 0.0, 0.55, 0.0, 0.8, 0.0, 0.0]
# Melody bells: [bar, beat within the bar, semitones above A3]. Sparse, leaning on semitones.
const MELODY := [
	[0, 0.0, 12], [0, 3.0, 13], [1, 0.0, 12], [1, 2.0, 8],
	[2, 0.0, 10], [2, 3.0, 8], [3, 0.0, 13], [3, 2.0, 12],
	[4, 1.0, 19], [5, 2.0, 20], [6, 0.0, 17], [7, 0.0, 16],
]
# Sonar pings: [bar, semitones above A3].
const PINGS := [[2, 24], [6, 22]]

const PAD_GAIN := 0.1
const PULSE_GAIN := 0.2
const MELODY_GAIN := 0.3
const PING_GAIN := 0.22
const ECHO_DELAY_BEATS := 1.5               # a slow echo for the ping and bells
const RISER_GAIN := 0.1
const PEAK := 0.7                           # the finished loop is scaled to this peak


static func total_samples() -> int:
	return BEAT_SAMPLES * BEATS_PER_BAR * BAR_COUNT


static func hz(semitones: int) -> float:
	return A3_HZ * pow(2.0, float(semitones) / 12.0)


## Renders the whole loop. Takes a second or two, so the game does it after the first frame.
static func build() -> AudioStreamWAV:
	var total := total_samples()
	var mix := PackedFloat32Array()
	mix.resize(total)
	var cache := {}
	var bar_samples := BEAT_SAMPLES * BEATS_PER_BAR
	var eighth := BEAT_SAMPLES / 2

	for bar in BAR_COUNT:
		var chord: Array = CHORDS[bar % CHORDS.size()]
		var bar_start := bar * bar_samples
		# Pad: each chord tone swells in and out over the bar, shimmering against itself.
		for semitone in chord:
			_add_pad(mix, bar_start, bar_samples, int(semitone), cache)
		# Pulse: muted plucks on the chord's first two tones.
		for step in PULSE.size():
			var gain: float = PULSE[step]
			if gain > 0.0:
				var tone: int = int(chord[0 if step % 4 < 2 else 1])
				_add_wave(mix, bar_start + step * eighth, _muted_pluck(tone, cache), PULSE_GAIN * gain)
	for note in MELODY:
		var start := int(note[0]) * bar_samples + int(float(note[1]) * BEAT_SAMPLES)
		var echo := int(ECHO_DELAY_BEATS * BEAT_SAMPLES)
		_add_wave(mix, start, _bell(int(note[2]), cache), MELODY_GAIN)
		_add_wave(mix, start + echo, _bell(int(note[2]), cache), MELODY_GAIN * 0.3)
	for ping in PINGS:
		var start := int(ping[0]) * bar_samples
		var echo := int(ECHO_DELAY_BEATS * BEAT_SAMPLES)
		_add_wave(mix, start, _ping(int(ping[1]), cache), PING_GAIN)
		_add_wave(mix, start + echo, _ping(int(ping[1]), cache), PING_GAIN * 0.5)
		_add_wave(mix, start + 2 * echo, _ping(int(ping[1]), cache), PING_GAIN * 0.25)
	# A hiss swells through the last bar, then drops away just before the loop restarts.
	_add_riser(mix, (BAR_COUNT - 1) * bar_samples, bar_samples)
	# A smaller one before the halfway point.
	_add_riser(mix, 3 * bar_samples, bar_samples)

	return _to_stream(mix, total)


## A plucked note: a sine with a quick-decaying second harmonic.
static func _pluck(semitone: int, cache: Dictionary) -> PackedFloat32Array:
	var key := "p%d" % semitone
	if cache.has(key):
		return cache[key]
	var f := hz(semitone)
	var count := int(1.4 * SAMPLE_RATE)
	var wave := PackedFloat32Array()
	wave.resize(count)
	for i in count:
		var t := float(i) / SAMPLE_RATE
		var attack := minf(1.0, t * 400.0)
		wave[i] = (sin(TAU * f * t) * exp(-t * 3.2) + 0.35 * sin(TAU * 2.0 * f * t) * exp(-t * 7.0)) * attack
	cache[key] = wave
	return wave


## A bell: a sine plus a slightly inharmonic overtone, ringing longer than a pluck.
static func _bell(semitone: int, cache: Dictionary) -> PackedFloat32Array:
	var key := "b%d" % semitone
	if cache.has(key):
		return cache[key]
	var f := hz(semitone)
	var count := int(2.6 * SAMPLE_RATE)
	var wave := PackedFloat32Array()
	wave.resize(count)
	for i in count:
		var t := float(i) / SAMPLE_RATE
		var attack := minf(1.0, t * 250.0)
		wave[i] = (sin(TAU * f * t) * exp(-t * 1.7) + 0.3 * sin(TAU * 2.01 * f * t) * exp(-t * 3.5)) * attack
	cache[key] = wave
	return wave


## A muted, short pluck: the pulse. Low in loudness, with almost no ring.
static func _muted_pluck(semitone: int, cache: Dictionary) -> PackedFloat32Array:
	var key := "m%d" % semitone
	if cache.has(key):
		return cache[key]
	var f := hz(semitone)
	var count := int(0.45 * SAMPLE_RATE)
	var wave := PackedFloat32Array()
	wave.resize(count)
	for i in count:
		var t := float(i) / SAMPLE_RATE
		wave[i] = (sin(TAU * f * t) + 0.3 * sin(TAU * 2.0 * f * t)) * exp(-t * 11.0) * minf(1.0, t * 300.0)
	cache[key] = wave
	return wave


## A sonar ping: a clean sine with a slow decay, meant to be echoed.
static func _ping(semitone: int, cache: Dictionary) -> PackedFloat32Array:
	var key := "g%d" % semitone
	if cache.has(key):
		return cache[key]
	var f := hz(semitone)
	var count := int(1.8 * SAMPLE_RATE)
	var wave := PackedFloat32Array()
	wave.resize(count)
	for i in count:
		var t := float(i) / SAMPLE_RATE
		wave[i] = sin(TAU * f * t) * exp(-t * 2.4) * minf(1.0, t * 120.0)
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


## One pad tone across a bar. A one-second cycle of the tone is rendered once (the pitch
## is rounded to a whole number of hertz so the cycle repeats cleanly) and then tiled
## under a slow swell envelope that overlaps into the next bar.
static func _add_pad(mix: PackedFloat32Array, bar_start: int, bar_samples: int, semitone: int, cache: Dictionary) -> void:
	var f := roundf(hz(semitone))
	var key := "pad%d" % int(f)
	if not cache.has(key):
		var cycle := PackedFloat32Array()
		cycle.resize(SAMPLE_RATE)
		for i in SAMPLE_RATE:
			var t := float(i) / SAMPLE_RATE
			# A second oscillator one hertz higher beats against the first: an eerie shimmer.
			cycle[i] = sin(TAU * f * t) * 0.5 + sin(TAU * (f + 1.0) * t) * 0.4 + sin(TAU * 2.0 * f * t) * 0.12
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


static func _to_stream(mix: PackedFloat32Array, total: int) -> AudioStreamWAV:
	var peak := 0.0001
	for i in total:
		peak = maxf(peak, absf(mix[i]))
	var scale := PEAK / peak
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
	stream.loop_begin = 0
	stream.loop_end = total
	return stream
