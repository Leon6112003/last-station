extends SceneTree
## Developer tool: plays the real game for a few seconds and prints how loud the master bus is
## with no danger and with full danger. Needs a real window (not --headless):
##   godot --path . -s res://tools/audio_probe.gd

const SAVE_PATH := "user://audio_probe_save.cfg"

func _initialize() -> void:
	SaveManager.new(SAVE_PATH).mark_intro_seen()
	var main: Node = load("res://scenes/main.tscn").instantiate()
	main.save_path = SAVE_PATH
	main.boot_intro = false
	main.play_wake_sequence = false
	root.add_child(main)
	for i in 120:
		await process_frame
	main._start_new_game()
	for i in 240:
		await process_frame
	var bank: SoundBank = main.sound
	print("music playing: ", bank.is_music_playing(), "  muted: ", bank.muted, "  music on: ", bank.music_enabled)
	print("calm layer db: ", bank._music.volume_db, "  tense layer db: ", bank._music_tense.volume_db)
	print("--- no danger: sampling master bus peak for 4 s")
	_sample(await _peaks(240))
	main._hit_danger = 1.0
	main.gm.reserve = 20.0
	print("--- full danger")
	for i in 240:
		await process_frame
	print("calm layer db: ", bank._music.volume_db, "  tense layer db: ", bank._music_tense.volume_db)
	_sample(await _peaks(240))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	quit(0)


func _peaks(frames: int) -> Array:
	var peaks := []
	for i in frames:
		await process_frame
		peaks.append(AudioServer.get_bus_peak_volume_left_db(0, 0))
	return peaks


func _sample(peaks: Array) -> void:
	var loudest := -200.0
	var total := 0.0
	for p in peaks:
		loudest = maxf(loudest, float(p))
		total += maxf(float(p), -80.0)
	print("master bus peak: loudest %.1f dB, average %.1f dB" % [loudest, total / peaks.size()])
