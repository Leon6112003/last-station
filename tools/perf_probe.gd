extends SceneTree
## Developer tool: measures the station's cost in a real window: node and mesh counts, draw calls
## and the time per frame (the window is v-synced, so the frame time shows headroom only when it
## is below 16.7 ms). Needs a real window (not --headless):
##   godot --path . -s res://tools/perf_probe.gd

const SAVE_PATH := "user://perf_probe_save.cfg"

var _views := [
	["bedroom", Vector3(0.0, 0.9, -5.0), 180.0],
	["corridor east", Vector3(1.0, 0.9, 0.0), -90.0],
	["power room", Vector3(12.0, 0.9, -4.5), 0.0],
	["cooling room", Vector3(48.0, 0.9, -4.5), 0.0],
	["cryo bay", Vector3(-10.0, 0.9, -3.2), 0.0],
]


func _initialize() -> void:
	SaveManager.new(SAVE_PATH).mark_intro_seen()
	var main: Node = load("res://scenes/main.tscn").instantiate()
	main.save_path = SAVE_PATH
	main.boot_intro = false
	main.play_wake_sequence = false
	root.add_child(main)
	await process_frame
	main._start_new_game()
	for i in 60:
		await process_frame
	var player: PlayerController = main._player
	player.skip_wake()
	player.set_input_enabled(false)
	var meshes: int = main._world.find_children("*", "MeshInstance3D", true, false).size()
	var lights: int = main._world.find_children("*", "Light3D", true, false).size()
	var bodies: int = main._world.find_children("*", "CollisionObject3D", true, false).size()
	print("world: %d meshes, %d lights, %d collision objects, %d nodes" % [meshes, lights, bodies, int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))])
	for view in _views:
		player.position = view[1]
		player.rotation.y = deg_to_rad(view[2])
		for i in 20:
			await process_frame
		var total := 0.0
		var frames := 90
		for i in frames:
			var started := Time.get_ticks_usec()
			await process_frame
			total += float(Time.get_ticks_usec() - started) / 1000.0
		print("%-14s draw calls %4d, objects %4d, frame %.1f ms" % [view[0], int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)), int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)), total / frames])
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	quit(0)
