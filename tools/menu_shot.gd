extends SceneTree
## Developer tool: saves PNGs of the main menu and the intro (needs a real window).
##   godot --path . -s res://tools/menu_shot.gd -- /path/to/output/folder [plain]

const SAVE_PATH := "user://menu_shot_save.cfg"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out_dir := args[0] if args.size() > 0 else "/tmp/last_station_shots"
	DirAccess.make_dir_recursive_absolute(out_dir)
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	var save := SaveManager.new(SAVE_PATH)
	save.mark_intro_seen()
	save.best_score = 517
	save.best_run = 987
	save.save_data()

	var main: Node = load("res://scenes/main.tscn").instantiate()
	main.save_path = SAVE_PATH
	var plain := args.size() > 1 and args[1] == "plain"   # "plain": no intro, just the finished menu
	main.boot_intro = not plain
	root.add_child(main)
	for i in (60 if plain else 190):
		await process_frame
	root.get_texture().get_image().save_png("%s/menu_intro_typing.png" % out_dir)
	for i in 110:
		await process_frame
	root.get_texture().get_image().save_png("%s/menu_intro_typing_2.png" % out_dir)
	main._menu_screen.skip_intro()
	for i in 90:
		await process_frame
	root.get_texture().get_image().save_png("%s/menu_final.png" % out_dir)
	print("saved to ", out_dir)
	quit(0)
