extends SceneTree
## Developer tool: saves a PNG of the results screen after a quick, clean clear, showing the adaptive
## difficulty text. Needs a real window (not --headless):
##   godot --path . -s res://tools/win_shot.gd -- /path/to/output/folder

const SAVE_PATH := "user://win_shot_save.cfg"


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
	for i in 20:
		await process_frame
	var gm: GameManager = main.gm
	for id in GameManager.SYSTEM_IDS:
		gm.repaired[id] = true
	gm.reserve = 290.0
	for pad in PuzzleValidators.reboot_answer(gm.puzzles["reboot"]):
		gm.press_reboot_pad(pad)
	gm.try_reboot()
	for i in 30:
		await process_frame
	root.get_texture().get_image().save_png("%s/win_adaptive.png" % out_dir)
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	quit(0)
