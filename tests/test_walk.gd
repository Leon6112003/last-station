extends SceneTree
## Milestone 1 physics test: the player walks through a doorway into a room,
## is stopped by walls (no clipping), and the interaction ray finds the console.
## Run:  godot --headless --path . -s res://tests/test_walk.gd

const FRAMES := 240

var _failures: int = 0


func _initialize() -> void:
	for action in ["move_forward", "move_backward", "move_left", "move_right", "interact"]:
		if not InputMap.has_action(action):
			InputMap.add_action(action)

	await _walk_north_into_oxygen_room()
	await _walk_into_west_wall()

	print("")
	if _failures == 0:
		print("ALL PASS")
		quit(0)
	else:
		print("%d FAILURE(S)" % _failures)
		quit(1)


func _make_player() -> Array:
	var world := Node3D.new()
	root.add_child(world)
	var station := StationBuilder.build(world, PuzzleGenerator.generate(1, 0))
	var player := PlayerController.new()
	player.position = station["spawn"]
	world.add_child(player)
	await process_frame
	player.set_input_enabled(true)
	return [world, player]


func _hold(action: String, frames: int) -> void:
	Input.action_press(action)
	for i in frames:
		await physics_frame
	Input.action_release(action)
	await physics_frame


func _walk_north_into_oxygen_room() -> void:
	var made := await _make_player()
	var world: Node3D = made[0]
	var player: PlayerController = made[1]

	await _hold("move_forward", FRAMES)

	var p := player.global_position
	_check(p.z < -3.5, "walked through the doorway into the room (z=%.2f)" % p.z)
	_check(p.z > -9.0, "did not pass through the north wall (z=%.2f)" % p.z)
	_check(absf(p.x) < 1.0, "stayed centred in the doorway column (x=%.2f)" % p.x)
	_check(p.y > 0.7 and p.y < 1.2, "stayed on the floor (y=%.2f)" % p.y)

	# Let one more physics frame pass so the ray refreshes, then look at the target.
	await physics_frame
	var target: Interactable = player._target
	_check(target != null and target.id == "oxygen_console", "aiming at the console selects it as the target")

	world.queue_free()
	await process_frame


func _walk_into_west_wall() -> void:
	var made := await _make_player()
	var world: Node3D = made[0]
	var player: PlayerController = made[1]

	await _hold("move_left", FRAMES)

	var p := player.global_position
	_check(p.x > -6.0, "west wall stops the player (x=%.2f)" % p.x)
	_check(p.x < -4.5, "player did reach the west wall (x=%.2f)" % p.x)

	world.queue_free()
	await process_frame


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS  ", label)
	else:
		print("FAIL  ", label)
		_failures += 1
