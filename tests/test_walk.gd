extends SceneTree
## Physics test: the player wakes in the crew quarters, walks out into the corridor, is
## stopped by walls and by a locked door, can aim at consoles, and the third-person camera
## and the corridor hazards work through real physics.
## Run:  godot --headless --path . -s res://tests/test_walk.gd

const FRAMES := 240

var _failures: int = 0


func _initialize() -> void:
	for action in ["move_forward", "move_backward", "move_left", "move_right", "interact"]:
		if not InputMap.has_action(action):
			InputMap.add_action(action)

	await _walk_out_of_the_bedroom()
	await _locked_door_blocks_then_opens()
	await _walk_into_west_wall()
	await _third_person_view()
	await _hazard_hits_the_player()

	print("")
	if _failures == 0:
		print("ALL PASS")
		quit(0)
	else:
		print("%d FAILURE(S)" % _failures)
		quit(1)


## Returns [world, player, station]. Defaults to the spawn position and facing.
func _make_player(position: Vector3 = Vector3.INF, yaw_degrees: float = INF) -> Array:
	var world := Node3D.new()
	root.add_child(world)
	var station := StationBuilder.build(world, PuzzleGenerator.generate(1, 0))
	var player := PlayerController.new()
	player.position = station["spawn"] if position == Vector3.INF else position
	player.rotation.y = deg_to_rad(float(station["spawn_yaw"]) if yaw_degrees == INF else yaw_degrees)
	world.add_child(player)
	await process_frame
	player.set_input_enabled(true)
	return [world, player, station]


func _hold(action: String, frames: int) -> void:
	Input.action_press(action)
	for i in frames:
		await physics_frame
	Input.action_release(action)
	await physics_frame


## Wake up in the crew quarters facing the door, walk out into the corridor and stop at its wall.
func _walk_out_of_the_bedroom() -> void:
	var made := await _make_player()
	var world: Node3D = made[0]
	var player: PlayerController = made[1]

	var steps := [0]
	var landing_swing := []   # how wide the legs were at each footstep (1.0 = widest)
	player.stepped.connect(func() -> void:
		steps[0] += 1
		landing_swing.append(absf(sin(player._bob_phase * TAU))))
	var camera: Camera3D = player.find_children("*", "Camera3D", false, false)[0]
	var base_y := camera.position.y
	var min_y := base_y
	var max_y := base_y
	Input.action_press("move_forward")
	for i in FRAMES:
		await physics_frame
		min_y = minf(min_y, camera.position.y)
		max_y = maxf(max_y, camera.position.y)
	Input.action_release("move_forward")
	await physics_frame
	_check(steps[0] >= 2, "walking produces footsteps (%d)" % steps[0])
	var matched := true
	for swing_at_landing in landing_swing:
		matched = matched and swing_at_landing > 0.9
	_check(matched, "every footstep sound lands when the legs are at their widest (the foot touching down)")
	_check(max_y - min_y > 0.01 and max_y - min_y < 0.15, "the camera bobs a little while walking (%.3f m range)" % (max_y - min_y))

	var p := player.global_position
	_check(p.z > StationBuilder.HUB_BACK_Z + 0.5, "walked out of the bedroom door into the corridor (z=%.2f)" % p.z)
	_check(p.z < StationBuilder.HUB_FRONT_Z, "did not pass through the corridor's south wall (z=%.2f)" % p.z)
	_check(absf(p.x - StationBuilder.BEDROOM_X) < 1.0, "stayed centred in the doorway column (x=%.2f)" % p.x)
	_check(p.y > 0.7 and p.y < 1.2, "stayed on the floor (y=%.2f)" % p.y)

	world.queue_free()
	await process_frame


## A locked door stops the player at the doorway; once unlocked they can walk into the room.
func _locked_door_blocks_then_opens() -> void:
	var oxygen_x: float = StationBuilder.ROOM_CENTERS_X["oxygen"]
	var made := await _make_player(Vector3(oxygen_x, 0.9, 0.0), 0.0)   # in the corridor, facing north
	var world: Node3D = made[0]
	var player: PlayerController = made[1]
	var station: Dictionary = made[2]
	var gate: DoorGate = station["doors"]["oxygen"]

	await _hold("move_forward", 90)
	var p := player.global_position
	_check(p.z > StationBuilder.HUB_BACK_Z, "the locked Oxygen door stops the player in the corridor (z=%.2f)" % p.z)

	gate.refresh({"power": true})
	_check(not gate.locked, "repairing Power unlocks the Oxygen door")
	await physics_frame
	await _hold("move_forward", 150)
	p = player.global_position
	_check(p.z < StationBuilder.HUB_BACK_Z - 1.0, "once unlocked the player can walk into the Oxygen room (z=%.2f)" % p.z)
	_check(p.z > StationBuilder.ROOM_BACK_Z, "did not pass through the room's back wall (z=%.2f)" % p.z)

	# Aiming at the console from inside works.
	await physics_frame
	var target: Interactable = player._target
	_check(target != null and target.id == "oxygen_console", "aiming at the console selects it as the target")

	world.queue_free()
	await process_frame


func _walk_into_west_wall() -> void:
	# In the crew quarters, beside the door, walking west ends at the room's west wall.
	var made := await _make_player(Vector3(0.0, 0.9, -2.5), 0.0)
	var world: Node3D = made[0]
	var player: PlayerController = made[1]

	await _hold("move_left", FRAMES)

	var p := player.global_position
	var wall_x := StationBuilder.BEDROOM_X - StationBuilder.ROOM_HALF_WIDTH
	_check(p.x > wall_x - 0.2, "the west wall stops the player (x=%.2f)" % p.x)
	_check(p.x < wall_x + 1.0, "the player did reach the west wall (x=%.2f)" % p.x)

	world.queue_free()
	await process_frame


func _third_person_view() -> void:
	var made := await _make_player(Vector3(10.0, 0.9, 0.0), 90.0)   # in the corridor, facing west
	var world: Node3D = made[0]
	var player: PlayerController = made[1]
	var avatar: Node3D = player.get_node("Avatar")
	var camera: Camera3D = player.find_children("*", "Camera3D", false, false)[0]
	_check(not avatar.visible and not player.third_person, "first person is the default and hides the body")

	player.set_third_person(true)
	await physics_frame
	await physics_frame
	_check(avatar.visible and player.third_person, "third person shows the body")
	_check(camera.position.z > 1.5, "the third-person camera sits behind the head (z=%.2f)" % camera.position.z)

	# Backed against the west end wall, the camera must stay inside the station.
	player.position = Vector3(StationBuilder.X_WEST + 1.2, 0.9, 1.0)
	player.rotation.y = deg_to_rad(-90.0)   # facing east, so the camera sits behind, to the west
	await physics_frame
	await physics_frame
	_check(camera.global_position.x > StationBuilder.X_WEST, "the camera never goes through a wall (x=%.2f)" % camera.global_position.x)
	_check(not avatar.visible, "the body is hidden when a wall squeezes the camera against it")

	# Interaction still works from the third-person camera, and reach is measured from the body.
	var oxygen_x: float = StationBuilder.ROOM_CENTERS_X["oxygen"]
	player.position = Vector3(oxygen_x, 0.9, -3.5)
	player.rotation.y = 0.0
	await physics_frame
	await _hold("move_forward", 90)
	await physics_frame
	var target: Interactable = player._target
	_check(target != null and target.id == "oxygen_console", "aiming at the console works in third person")

	player.set_third_person(false)
	await physics_frame
	_check(not avatar.visible and absf(camera.position.z) < 0.01, "switching back restores the first-person view")

	world.queue_free()
	await process_frame


## Standing in an active gas cloud reaches the hazard through real physics.
func _hazard_hits_the_player() -> void:
	var made := await _make_player(Vector3(StationBuilder.GAS_X, 0.9, 0.0), 0.0)
	var world: Node3D = made[0]
	var station: Dictionary = made[2]
	var gas: HazardZone = station["hazards"][0]
	gas._time = Rules.GAS_OFF_SECONDS + Rules.GAS_WARN_SECONDS + 0.1   # active
	var damage := [0.0]
	gas.hit.connect(func(_kind: String, seconds: float, _first: bool) -> void: damage[0] += seconds)
	for i in 30:
		await physics_frame
	_check(damage[0] > 0.0, "the player standing in venting gas takes damage through real physics (%.1f s)" % damage[0])

	# Quiet phase: no damage.
	var before: float = damage[0]
	gas._time = 0.5
	for i in 5:
		await physics_frame
	_check(is_equal_approx(damage[0], before), "no damage while the vent is quiet")

	world.queue_free()
	await process_frame


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS  " + label)
	else:
		print("FAIL  " + label)
		_failures += 1
