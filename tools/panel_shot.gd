extends SceneTree
## Developer tool: saves a PNG of the reboot code panel while it flashes the sequence.
##   godot --path . -s res://tools/panel_shot.gd -- /path/to/output/folder

const SAVE_PATH := "user://panel_shot_save.cfg"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out_dir := args[0] if args.size() > 0 else "/tmp/last_station_shots"
	DirAccess.make_dir_recursive_absolute(out_dir)
	SaveManager.new(SAVE_PATH).mark_intro_seen()
	var main: Node = load("res://scenes/main.tscn").instantiate()
	main.save_path = SAVE_PATH
	main.boot_intro = false
	main.play_wake_sequence = false
	root.add_child(main)
	await process_frame
	main._start_new_game()
	for i in 30:
		await process_frame
	for id in GameManager.SYSTEM_IDS:
		main.gm.repaired[id] = true
	main._open_panel("reboot")
	for i in 38:
		await process_frame
	root.get_texture().get_image().save_png("%s/reboot_panel_flash.png" % out_dir)
	main._panel.finish_showing()
	for i in 10:
		await process_frame
	root.get_texture().get_image().save_png("%s/reboot_panel_ready.png" % out_dir)
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	quit(0)
