extends SceneTree
## Waking up in bed: the player starts lying in the bunk looking up with eyes shut, opens
## their eyes, sits up, stands and ends facing the bedroom door. Everything is locked until
## it ends, a key press can skip it, and it never leaves the screen black.
## Run:  godot --headless --path . -s res://tests/test_wake.gd

var _failures: int = 0


func _initialize() -> void:
	for action in ["move_forward", "move_backward", "move_left", "move_right", "interact"]:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
	await _test_sequence()
	await _test_short_wake()
	await _test_real_scene()

	print("")
	if _failures == 0:
		print("ALL PASS")
		quit(0)
	else:
		print("%d FAILURE(S)" % _failures)
		quit(1)


func _make() -> Array:
	var world := Node3D.new()
	root.add_child(world)
	var station := StationBuilder.build(world, PuzzleGenerator.generate(1, 0))
	var player := PlayerController.new()
	player.position = station["spawn"]
	player.rotation.y = deg_to_rad(float(station["spawn_yaw"]))
	world.add_child(player)
	await process_frame
	player.set_input_enabled(true)
	player.wake_bed_position = station["bed_position"]
	return [world, player, station]


func _camera(player: PlayerController) -> Camera3D:
	return player.find_children("*", "Camera3D", false, false)[0]


func _test_sequence() -> void:
	var made := await _make()
	var world: Node3D = made[0]
	var player: PlayerController = made[1]
	var station: Dictionary = made[2]
	var camera := _camera(player)
	var woke := [0]
	player.woke_up.connect(func() -> void: woke[0] += 1)

	player.play_wake_up(true)
	_check(player.waking and is_equal_approx(player.wake_blink, 1.0), "waking starts with the eyes shut")
	var bed: Vector3 = station["bed_position"]
	_check(camera.global_position.distance_to(bed) < 0.05, "the eyes start in the lower bunk (%.2f m from it)" % camera.global_position.distance_to(bed))
	_check(camera.global_position.y < 1.0, "lying down the eyes are low (y=%.2f)" % camera.global_position.y)
	_check(_camera(player).rotation.x > deg_to_rad(50.0), "lying, the player looks up at the bunk above (%.0f degrees)" % rad_to_deg(camera.rotation.x))
	_check(not (player.get_node("Avatar") as Node3D).visible, "the body is hidden while waking")

	# Locked: pushing forward does nothing.
	Input.action_press("move_forward")
	var start := player.global_position
	for i in 30:
		await physics_frame
	Input.action_release("move_forward")
	_check(player.global_position.distance_to(start) < 0.05, "the player cannot walk while waking up")
	_check(player._wake_time > 0.4, "time passes while waking (%.2f s)" % player._wake_time)

	# Eyes open, sit up, stand.
	player._wake_time = PlayerController.WAKE_EYES_OPEN_DONE + 0.2
	player._apply_wake()
	_check(is_equal_approx(player.wake_blink, 0.0), "the eyes are open after the first moments")
	player._wake_time = (PlayerController.WAKE_SIT_START + PlayerController.WAKE_STAND_START) * 0.5
	player._apply_wake()
	var mid_y := camera.global_position.y
	_check(mid_y > 0.85 and mid_y < 1.5 and camera.rotation.x < deg_to_rad(60.0), "sitting up, the view rises and tilts down (y=%.2f)" % mid_y)

	# Too early for a key press to skip.
	player._wake_time = 0.5
	var early := InputEventKey.new()
	early.keycode = KEY_W
	early.pressed = true
	player._unhandled_input(early)
	_check(player.waking, "a key press right away does not skip the sequence")
	player._wake_time = PlayerController.WAKE_SKIP_AFTER + 0.1
	player._unhandled_input(early)
	_check(not player.waking and woke[0] == 1, "after a moment a key press skips it, and the player has control")
	_check(is_equal_approx(player.wake_blink, 0.0) and is_equal_approx(player.rotation.y, -PI), "afterwards the eyes are open and the player faces the door")
	_check(absf(camera.position.y - (Rules.EYE_HEIGHT - Rules.PLAYER_HEIGHT * 0.5)) < 0.05 and is_equal_approx(camera.rotation.x, 0.0), "the view is back at standing eye height and level")

	# Running it to the end by itself.
	player.play_wake_up(true)
	player._advance_wake(PlayerController.WAKE_TOTAL + 0.1)
	_check(not player.waking and woke[0] == 2, "the sequence ends by itself after its full length")

	# Control works afterwards.
	var after := player.global_position
	Input.action_press("move_forward")
	for i in 30:
		await physics_frame
	Input.action_release("move_forward")
	_check(player.global_position.distance_to(after) > 0.5, "the player can walk once awake")
	world.queue_free()
	await process_frame


func _test_short_wake() -> void:
	var made := await _make()
	var world: Node3D = made[0]
	var player: PlayerController = made[1]
	player.play_wake_up(false)
	_check(player.waking and player._wake_time >= PlayerController.WAKE_SIT_START, "a short wake (retry or later shift) starts at the sitting-up part")
	_check(PlayerController.WAKE_TOTAL - PlayerController.WAKE_SIT_START < 4.0, "the short wake takes under 4 seconds")
	player._advance_wake(10.0)
	_check(not player.waking, "the short wake also ends by itself")
	world.queue_free()
	await process_frame


func _test_real_scene() -> void:
	var save_path := "user://test_wake_save.cfg"
	SaveManager.new(save_path).mark_intro_seen()
	var main: Node = load("res://scenes/main.tscn").instantiate()
	main.save_path = save_path
	main.play_wake_sequence = true
	root.add_child(main)
	await process_frame
	main._start_new_game()
	await process_frame
	_check(main._player.waking, "a new run starts with the player waking up in bed")
	_check(main._fade.color.a > 0.9, "the screen starts black (eyes shut)")
	_check(not main._player._wake_short, "the first shift of a run gets the full wake-up")

	# Retrying while still waking must never leave the screen black, and a retry does not
	# wake you up again (you are already awake).
	main._retry()
	await process_frame
	_check(not main._player.waking, "a retry does not wake the player up again")
	await create_timer(main.FADE_IN_SECONDS + 0.4).timeout
	_check(main._fade.color.a < 0.01, "after the retry the screen is clear")
	# Next Shift: also no waking up.
	main.gm.run_number = 2
	main._rebuild_world()
	await process_frame
	_check(not main._player.waking and main._player.input_enabled, "a later shift starts with the player already awake and in control")
	main._go_to_menu()
	await process_frame
	_check(main._fade.color.a < 0.01, "going to the menu mid-wake leaves no black screen")
	main.queue_free()
	await process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS  " + label)
	else:
		print("FAIL  " + label)
		_failures += 1
