extends SceneTree
## Developer tool: renders the station from several viewpoints and saves PNGs.
## Needs a real window (not --headless):
##   godot --path . -s res://tools/screenshot.gd -- /path/to/output/folder
## Optional second argument: "repaired" shows the station with all systems repaired.
## Optional fourth argument: a shift number, to see that shift's colour theme.
## Optional third argument: "third" renders from the third-person camera.

const SAVE_PATH := "user://screenshot_tool_save.cfg"

# name, player position, yaw in degrees (0 = looking north), pitch in degrees
const VIEWS := [
	["01_bedroom_wake", Vector3(0.0, 0.9, -5.0), 180.0, 0.0],
	["01b_bed", Vector3(0.9, 0.9, -4.6), 90.0, -10.0],
	["01c_bed_foot", Vector3(-1.6, 0.9, -2.6), 0.0, -5.0],
	["01d_window_space", Vector3(11.0, 0.9, -0.6), 160.0, 5.0],
	["02_corridor_east", Vector3(1.0, 0.9, 0.0), -90.0, 0.0],
	["03_gas_vent", Vector3(10.5, 0.9, 0.0), -90.0, 0.0],
	["04_power_room", Vector3(12.0, 0.9, -4.5), 0.0, 5.0],
	["05_oxygen_door_locked", Vector3(24.0, 0.9, 0.4), 0.0, 0.0],
	["06_laser_grid", Vector3(26.0, 0.9, 0.0), -90.0, 0.0],
	["06b_laser_switch", Vector3(28.0, 0.9, -0.2), 180.0, 0.0],
	["07_comms_room", Vector3(36.0, 0.9, -4.5), 0.0, 5.0],
	["07b_cooling_room", Vector3(48.0, 0.9, -4.0), 0.0, 5.0],
	["07c_cooling_reactor", Vector3(50.5, 0.9, -3.0), 90.0, 0.0],
	["07e_cryo_terminals", Vector3(60.0, 0.9, -3.2), 0.0, 3.0],
	["07f_cryo_pods_west", Vector3(61.0, 0.9, -4.5), 90.0, 8.0],
	["07g_cryo_doorway", Vector3(60.0, 0.9, 0.0), 0.0, 0.0],
	["07d_corridor_east_end", Vector3(44.0, 0.9, 0.0), -90.0, 0.0],
	["08_reboot_terminal", Vector3(-2.0, 0.9, 0.0), 90.0, 0.0],
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
	main.boot_intro = false
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

	if args.size() > 3:
		main.gm.run_number = int(args[3])   # pick the shift, to see its colour theme
		main._rebuild_world()
		await process_frame
	for zone in main._station["hazards"]:
		(zone as HazardZone)._time = 7.0   # show the gas active
	var player: PlayerController = main._player
	player.skip_wake()   # the wake-up sequence keeps the eyes shut
	player.set_input_enabled(false)
	if args.size() > 2 and args[2] == "third":
		player.set_third_person(true)
	for view in VIEWS:
		player.position = view[1]
		player.rotation.y = deg_to_rad(view[2])
		player._camera.rotation.x = deg_to_rad(view[3])
		for i in 6:
			await process_frame
		var image := root.get_texture().get_image()
		var path := "%s/%s%s.png" % [out_dir, view[0], ("_repaired" if repaired else "") + ("_third" if args.size() > 2 and args[2] == "third" else "")]
		image.save_png(path)
		print("saved ", path, "  ", image.get_size())

	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	quit(0)
