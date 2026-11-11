extends SceneTree
## Developer tool: renders the station from several viewpoints and saves PNGs.
## Needs a real window (not --headless):
##   godot --path . -s res://tools/screenshot.gd -- /path/to/output/folder
## Optional second argument: "repaired" shows the station with all systems repaired.

const SAVE_PATH := "user://screenshot_tool_save.cfg"

# name, player position, yaw in degrees (0 = looking north), pitch in degrees
const VIEWS := [
	["01_spawn_hub", Vector3(0.0, 0.9, 1.2), 0.0, 0.0],
	["02_hub_left", Vector3(-1.5, 0.9, 0.8), 25.0, 0.0],
	["03_hub_right", Vector3(1.5, 0.9, 0.8), -25.0, 0.0],
	["04_power_room", Vector3(-4.0, 0.9, -5.2), 0.0, 5.0],
	["05_oxygen_room", Vector3(0.0, 0.9, -5.2), 0.0, 5.0],
	["06_comms_room", Vector3(4.0, 0.9, -5.2), 0.0, 5.0],
	["07_hub_back", Vector3(0.0, 0.9, -1.5), 180.0, 0.0],
]


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out_dir := args[0] if args.size() > 0 else "/tmp/last_station_shots"
	var repaired := args.size() > 1 and args[1] == "repaired"
	DirAccess.make_dir_recursive_absolute(out_dir)

	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	SaveManager.new(SAVE_PATH).mark_intro_seen()

	var main: Node = load("res://scenes/main.tscn").instantiate()
	main.save_path = SAVE_PATH
	root.add_child(main)
	await process_frame
	main._start_new_game()
	await process_frame

	if repaired:
		var gm: GameManager = main.gm
		for index in PuzzleValidators.power_order(gm.puzzles["power"]):
			gm.flip_breaker(index)
		var target: Array = PuzzleValidators.oxygen_target(gm.puzzles["oxygen"])
		for i in 3:
			gm.adjust_valve(i, int(target[i]) / Rules.OXYGEN_STEP)
		gm.confirm_oxygen()
		gm.adjust_tuner((PuzzleValidators.comms_target(gm.puzzles["comms"]) - Rules.COMMS_MIN_MHZ) / Rules.COMMS_STEP_MHZ)
		gm.transmit()
		main._close_modal()

	var player: PlayerController = main._player
	player.set_input_enabled(false)
	for view in VIEWS:
		player.position = view[1]
		player.rotation.y = deg_to_rad(view[2])
		player._camera.rotation.x = deg_to_rad(view[3])
		for i in 6:
			await process_frame
		var image := root.get_texture().get_image()
		var path := "%s/%s%s.png" % [out_dir, view[0], "_repaired" if repaired else ""]
		image.save_png(path)
		print("saved ", path, "  ", image.get_size())

	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	quit(0)
