extends SceneTree
## Developer tool: saves PNGs of the Settings window and of the gas/door cues (needs a real window).
##   godot --path . -s res://tools/settings_shot.gd -- /path/to/output/folder

const SAVE_PATH := "user://settings_shot_save.cfg"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out_dir := args[0] if args.size() > 0 else "/tmp/last_station_shots"
	DirAccess.make_dir_recursive_absolute(out_dir)
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	SaveManager.new(SAVE_PATH).mark_intro_seen()
	var main: Node = load("res://scenes/main.tscn").instantiate()
	main.save_path = SAVE_PATH
	main.boot_intro = false
	main.play_wake_sequence = false
	root.add_child(main)
	for i in 40:
		await process_frame
	main._open_settings()
	for i in 40:
		await process_frame
	root.get_texture().get_image().save_png("%s/settings_menu.png" % out_dir)
	main._close_settings()
	main.save.captions = true
	main._start_new_game()
	for i in 60:
		await process_frame
	var player: PlayerController = main._player
	player.skip_wake()
	player.set_input_enabled(false)
	player.position = Vector3(9.0, 0.9, 0.0)
	player.rotation.y = deg_to_rad(-90.0)
	for zone in main._station["hazards"]:
		(zone as HazardZone)._time = 7.0
	main.sound.play("alarm")
	main.sound.play("gasleak")
	for i in 30:
		await process_frame
	root.get_texture().get_image().save_png("%s/cues_gas_and_captions.png" % out_dir)
	player.position = Vector3(11.0, 0.9, 1.0)
	player.rotation.y = deg_to_rad(-12.0)
	player._camera.rotation.x = deg_to_rad(18.0)
	for i in 30:
		await process_frame
	root.get_texture().get_image().save_png("%s/cues_door_icons.png" % out_dir)
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	print("saved to ", out_dir)
	quit(0)
