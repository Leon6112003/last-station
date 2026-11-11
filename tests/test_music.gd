extends SceneTree
## The generated theme song: it renders, loops, stays quiet enough, has no sub-bass drone,
## and the bank starts and stops it correctly. How it sounds needs a person with speakers.
## Run:  godot --headless --path . -s res://tests/test_music.gd

var _failures: int = 0


func _initialize() -> void:
	var started := Time.get_ticks_msec()
	var stream := ThemeMusic.build()
	var seconds_to_render := float(Time.get_ticks_msec() - started) / 1000.0
	var total := ThemeMusic.total_samples()
	_check(stream.data.size() == total * 2, "the song has the expected length (%d samples)" % total)
	var length_seconds := float(total) / ThemeMusic.SAMPLE_RATE
	_check(length_seconds > 20.0 and length_seconds < 35.0, "the loop is about 29 seconds (%.1f s)" % length_seconds)
	_check(stream.loop_mode == AudioStreamWAV.LOOP_FORWARD and stream.loop_end == total, "it loops over its whole length")
	_check(seconds_to_render < 4.0, "it renders quickly enough to do at startup (%.2f s)" % seconds_to_render)

	var peak := 0
	var energy := 0.0
	for i in range(0, stream.data.size(), 2):
		var sample := stream.data.decode_s16(i)
		peak = maxi(peak, absi(sample))
		energy += float(sample) * float(sample)
	var rms := sqrt(energy / total) / 32767.0
	_check(peak > 16000 and peak < 28000, "it is audible and does not clip (peak %d)" % peak)
	_check(rms > 0.03 and rms < 0.3, "its average loudness is moderate (rms %.3f)" % rms)

	# Seamless loop: the end and the start are both near silence or at least continuous.
	var first := stream.data.decode_s16(0)
	var last := stream.data.decode_s16(stream.data.size() - 2)
	_check(absi(first - last) < 4000, "the loop seam has no jump (%d to %d)" % [last, first])

	# No sub-bass: every pitch used is at or above 150 Hz.
	var lowest := 1.0e9
	for chord in ThemeMusic.CHORDS:
		for semitone in chord:
			lowest = minf(lowest, ThemeMusic.hz(int(semitone)))
	_check(lowest >= 150.0, "no tone is below 150 Hz, so there is no low drone (lowest %.0f Hz)" % lowest)

	# Deterministic: building twice gives the same song.
	_check(ThemeMusic.build().data == stream.data, "the song is identical every time it is built")

	# The two layers: same length, in sync, and together they are the full song.
	var layers := ThemeMusic.build_layers()
	_check(layers.size() == 2 and layers[0].data.size() == stream.data.size() and layers[1].data.size() == stream.data.size(), "the calm and tense layers are as long as the song")
	var sum_ok := true
	for i in range(0, stream.data.size(), 2 * 997):
		var together: int = layers[0].data.decode_s16(i) + layers[1].data.decode_s16(i)
		sum_ok = sum_ok and absi(together - stream.data.decode_s16(i)) <= 2
	_check(sum_ok, "the two layers add up to the full song")
	var tense_energy := 0.0
	var calm_energy := 0.0
	for i in range(0, stream.data.size(), 2):
		tense_energy += absf(float(layers[1].data.decode_s16(i)))
		calm_energy += absf(float(layers[0].data.decode_s16(i)))
	_check(tense_energy > 0.0 and calm_energy > 0.0, "both layers have sound in them")

	# The bank: the music only plays while a shift runs, and the switches work.
	var bank := SoundBank.new()
	bank.load_music = true
	root.add_child(bank)
	for i in 3:
		await process_frame
	_check(not bank.is_music_playing(), "the music is silent until a shift starts")
	bank.set_music_active(true)
	_check(bank.is_music_playing(), "the music plays while a shift is running")
	bank.set_music_enabled(false)
	_check(not bank.is_music_playing(), "the music switch turns it off")
	bank.set_music_enabled(true)
	_check(bank.is_music_playing(), "the music switch turns it back on")
	# The tense layer plays with the calm one and follows the danger.
	bank.set_music_danger(0.0)
	for i in 120:
		await process_frame
	var quiet_db: float = bank._music_tense.volume_db
	bank.set_music_danger(1.0)
	for i in 300:
		await process_frame
	_check(bank._music_tense.playing and bank._music_tense.volume_db > quiet_db + 20.0, "the tense layer plays with the calm one and swells as the danger rises (%.0f dB to %.0f dB)" % [quiet_db, bank._music_tense.volume_db])
	bank.set_music_danger(0.0)
	bank.set_muted(true)
	_check(not bank.is_music_playing(), "mute silences the music too")
	bank.set_muted(false)
	bank.set_music_active(false)
	_check(not bank.is_music_playing(), "the music stops when the shift is paused or over")
	bank.set_music_active(true)
	bank.free()
	await process_frame

	print("")
	if _failures == 0:
		print("ALL PASS")
		quit(0)
	else:
		print("%d FAILURE(S)" % _failures)
		quit(1)


func _check(ok: bool, message: String) -> void:
	if ok:
		print("PASS  " + message)
	else:
		print("FAIL  " + message)
		_failures += 1
