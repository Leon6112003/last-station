extends SceneTree
## Developer tool: renders the player's cartoon avatar from the front, the side and the back.
## Needs a real window (not --headless):
##   godot --path . -s res://tools/avatar_shot.gd -- /path/to/output/folder

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out_dir := args[0] if args.size() > 0 else "/tmp/last_station_shots"
	DirAccess.make_dir_recursive_absolute(out_dir)
	var world := Node3D.new()
	root.add_child(world)
	var environment := Environment.new()
	environment.background_color = Color(0.12, 0.14, 0.3)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.7, 0.72, 0.9)
	environment.ambient_light_energy = 0.8
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	world.add_child(world_environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-40, 30, 0)
	world.add_child(light)
	var floor_body := MeshInstance3D.new()
	var plane := BoxMesh.new()
	plane.size = Vector3(6, 0.1, 6)
	floor_body.mesh = plane
	floor_body.position.y = -0.05
	world.add_child(floor_body)
	var player := PlayerController.new()
	player.position = Vector3(0, 0.9, 0)
	world.add_child(player)
	await process_frame
	player.set_third_person(true)
	player._avatar.visible = true
	player.set_physics_process(false)
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.current = true
	var views := [["front", Vector3(0.0, 1.1, -3.2), 180.0], ["side", Vector3(3.2, 1.1, 0.0), 90.0], ["back", Vector3(0.0, 1.1, 3.2), 0.0]]
	for view in views:
		camera.position = view[1]
		camera.rotation_degrees = Vector3(-4, view[2], 0)
		for i in 5:
			await process_frame
		var path := "%s/avatar_%s.png" % [out_dir, view[0]]
		root.get_texture().get_image().save_png(path)
		print("saved ", path)
	quit(0)
