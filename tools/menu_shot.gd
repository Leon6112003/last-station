extends SceneTree
## Developer tool: saves PNGs of the main menu and the intro (needs a real window).
##   godot --path . -s res://tools/menu_shot.gd -- /path/to/output/folder

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
	main.boot_intro = true
	root.add_child(main)
	await create_timer(3.2).timeout
	root.get_texture().get_image().save_png("%s/menu_intro_typing.png" % out_dir)
	await create_timer(1.8).timeout
	root.get_texture().get_image().save_png("%s/menu_intro_typing_2.png" % out_dir)
	main._menu_screen.skip_intro()
	await create_timer(1.5).timeout
	root.get_texture().get_image().save_png("%s/menu_final.png" % out_dir)
	print("saved to ", out_dir)
	quit(0)
