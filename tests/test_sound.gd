extends SceneTree
## Sound effects are generated in code. These checks cover the synthesis and the bank
## logic (not how it sounds: that needs a person with speakers).
## Run:  godot --headless --path . -s res://tests/test_sound.gd

var _failures: int = 0


func _initialize() -> void:
	for sound_name in SoundBank.NAMES:
		var stream := SoundBank.build_stream(sound_name)
		var bytes := stream.data
		_check(bytes.size() > 1000, "'%s' has audio data (%d bytes)" % [sound_name, bytes.size()])
		var peak := 0
		for i in range(0, bytes.size(), 2):
			peak = maxi(peak, absi(bytes.decode_s16(i)))
		_check(peak > 1500 and peak <= 32767, "'%s' is audible and does not clip (peak %d)" % [sound_name, peak])
		_check(SoundBank.build_stream(sound_name).data == bytes, "'%s' is identical every time it is built" % sound_name)
		_check(SoundBank.VOLUME_DB.has(sound_name), "'%s' has a volume setting" % sound_name)

	# No sound loops and none is long: nothing plays continuously.
	for sound_name in SoundBank.NAMES:
		var stream := SoundBank.build_stream(sound_name)
		var seconds := float(stream.data.size() / 2) / SoundBank.SAMPLE_RATE
		_check(stream.loop_mode == AudioStreamWAV.LOOP_DISABLED and seconds <= 1.1, "'%s' is a short one-shot (%.2f s), not a loop" % [sound_name, seconds])

	var bank := SoundBank.new()
	root.add_child(bank)
	await process_frame
	bank.play("no_such_sound")
	bank.play("click")
	_check(true, "playing unknown and known sounds does not fail")
	bank.set_muted(true)
	bank.play("chime")
	_check(bank.muted, "mute is remembered")
	bank.set_muted(false)
	_check(not bank.muted, "sound can be switched back on")

	bank.set_muted(true)  # stops everything that is playing
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
