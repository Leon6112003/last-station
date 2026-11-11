extends SceneTree
## Hazards and puzzles that affect each other: repairing a system switches off the laser grid just
## beyond its room, seals a corridor vent, and stops the gas leak at its own console.
## Run:  godot --headless --path . -s res://tests/test_hazard_links.gd

const SAVE_PATH := "user://test_links_save.cfg"

var _failures: int = 0


func _initialize() -> void:
	Rules.level = Rules.LEVEL_ENGINEER
	Rules.mods = 0
	await _test_zone()
	await _test_laser()
	await _test_station()
	await _test_real_game()
	_remove_save()
	print("")
	if _failures == 0:
		print("ALL PASS")
		quit(0)
	else:
		print("%d FAILURE(S)" % _failures)
		quit(1)


func _test_zone() -> void:
	var corridor := HazardZone.create(Vector3(6, 2.8, 3), Vector3.ZERO, 0.0, 1)
	var leak := HazardZone.create(Vector3(4.5, 2.8, 4), Vector3.ZERO, 0.0, 1, 3.0, 0.6)
	root.add_child(corridor)
	root.add_child(leak)
	_check(is_equal_approx(leak.cycle_seconds(), (Rules.gas_off_seconds(1) + 3.0) + Rules.GAS_WARN_SECONDS + Rules.gas_on_seconds(1) * 0.6), "a room leak has a longer quiet spell and a shorter venting time")
	_check(leak._venting_seconds() < corridor._venting_seconds() and leak._quiet_seconds() > corridor._quiet_seconds(), "so it is kinder than a corridor vent")
	var hits := [0.0]
	leak.hit.connect(func(_kind: String, seconds: float, _first: bool) -> void: hits[0] += seconds)
	leak._time = leak._quiet_seconds() + Rules.GAS_WARN_SECONDS + 0.1
	leak.tick(0.5, true)
	_check(leak.is_active() and hits[0] > 0.0, "an active leak drains reserve from someone standing in it")
	var before: float = hits[0]
	leak.seal()
	leak.tick(1.0, true)
	_check(leak.sealed and not leak.is_active() and is_equal_approx(hits[0], before), "a sealed leak never drains again")
	leak._time = 0.0
	for i in 40:
		leak.tick(0.5, true)
	_check(not leak.is_active() and is_equal_approx(hits[0], before), "not even after a whole cycle")
	_check(leak._phase_label.text == "GAS: SEALED", "its word says SEALED (a cue that does not rely on colour)")
	corridor.free()
	leak.free()
	await process_frame


func _test_laser() -> void:
	var grid := LaserGrid.create(Vector3.ZERO, 3.0, 3.0, 1)
	root.add_child(grid)
	await process_frame
	var changes: Array[bool] = []
	grid.state_changed.connect(func(armed: bool) -> void: changes.append(armed))
	_check(grid.armed and not grid.offline, "a grid starts on")
	grid.go_offline()
	_check(grid.offline and not grid.armed and changes.size() == 1 and not changes[0], "going offline switches it off and says so once")
	_check(grid._barrier.collision_layer == 0, "an offline grid is no longer a wall")
	for i in 100:
		grid.tick(1.0, false)
	_check(not grid.armed and changes.size() == 1, "it never switches itself on again")
	grid.switch_off()
	grid.tick(0.1, false)
	_check(not grid.armed and grid.off_seconds_left() == 0.0, "a wall switch does nothing to an offline grid")
	_check(grid._label.text == "LASER OFFLINE", "its label says OFFLINE")
	var touches := [0]
	grid.touched.connect(func(_s: float) -> void: touches[0] += 1)
	grid.tick(0.1, true)
	_check(touches[0] == 0, "standing where the beams were is not a touch")
	grid.free()
	await process_frame


func _test_station() -> void:
	var surge_seed := -1
	var normal_seed := -1
	for seed_value in 200:
		var state: String = PuzzleGenerator.generate(seed_value, 0)["cooling"]["state"]
		if state == "SURGE" and surge_seed < 0:
			surge_seed = seed_value
		if state == "NORMAL" and normal_seed < 0:
			normal_seed = seed_value
	var world := Node3D.new()
	root.add_child(world)
	var surge := StationBuilder.build(world, PuzzleGenerator.generate(surge_seed, 0))
	var leaks: Dictionary = surge["room_leaks"]
	_check(leaks.has("oxygen") and leaks.has("cooling"), "in a SURGE shift both the Oxygen and the Cooling rooms leak")
	var oxygen_console: Interactable
	for item in surge["interactables"]:
		if (item as Interactable).id == "oxygen_console":
			oxygen_console = item
	var leak: HazardZone = leaks["oxygen"]
	var offset: Vector3 = oxygen_console.position - leak.position
	_check(absf(offset.x) < leak.size.x * 0.5 and absf(offset.z) < leak.size.z * 0.5 + 0.8, "the Oxygen leak covers the spot in front of its console")
	var texts: Array[String] = []
	for label in world.find_children("*", "Label3D", true, false):
		texts.append((label as Label3D).text)
	_check(texts.filter(func(t: String) -> bool: return t.begins_with("GAS LEAK")).size() == 2, "each leak has a warning sign")
	world.free()
	await process_frame
	var calm_world := Node3D.new()
	root.add_child(calm_world)
	var calm := StationBuilder.build(calm_world, PuzzleGenerator.generate(normal_seed, 0))
	_check((calm["room_leaks"] as Dictionary).has("oxygen") and not (calm["room_leaks"] as Dictionary).has("cooling"), "with the reactor NORMAL only the Oxygen room leaks")
	_check((calm["hazards"] as Array).size() == 2, "the two corridor vents are unchanged")
	calm_world.free()
	await process_frame


func _new_main() -> Node:
	_remove_save()
	SaveManager.new(SAVE_PATH).mark_intro_seen()
	var main: Node = load("res://scenes/main.tscn").instantiate()
	main.save_path = SAVE_PATH
	root.add_child(main)
	await process_frame
	return main


func _test_real_game() -> void:
	var main := await _new_main()
	Rules.mods = 0
	main._start_new_game()
	main.gm.run_number = 3
	main.gm.start_shift(7, 3)
	main._rebuild_world()
	await process_frame
	var gm: GameManager = main.gm
	var lasers: Array = main._station["lasers"]
	var vents: Array = main._station["hazards"]
	var leaks: Dictionary = main._station["room_leaks"]
	_check(lasers.size() == 2 and (lasers[0] as LaserGrid).armed and (lasers[1] as LaserGrid).armed, "shift 3 starts with both laser grids on")
	# Oxygen: seals the vent between Power and Oxygen, and its own room's leak.
	gm.repaired["oxygen"] = true
	main._on_system_repaired("oxygen")
	_check((vents[1] as HazardZone).sealed and not (vents[0] as HazardZone).sealed, "repairing Oxygen seals the vent between Power and Oxygen, not the first one")
	_check((leaks["oxygen"] as HazardZone).sealed, "and the leak in the Oxygen room")
	_check(main._notice_label.text.contains("GAS VENT 2 SEALED") and main._notice_label.text.contains("GAS LEAK SEALED"), "a notice says what was sealed")
	_check(not (lasers[0] as LaserGrid).offline, "the first laser grid is still on (Comms is not repaired)")
	# Comms: the first grid goes offline (and the Cooling door unlocks in the same notice).
	gm.repaired["comms"] = true
	main._on_system_repaired("comms")
	_check((lasers[0] as LaserGrid).offline and not (lasers[0] as LaserGrid).armed and not (lasers[1] as LaserGrid).offline, "repairing Comms switches off the first grid for good, not the second")
	_check(main._notice_label.text.contains("COOLING DOOR UNLOCKED") and main._notice_label.text.contains("LASER GRID 1 OFFLINE"), "one notice names the unlocked door and the grid")
	# Using an offline grid's switch.
	var switch: Interactable
	for item in main._station["laser_switches"]:
		if (item as Interactable).get_meta("laser_grid") == lasers[0]:
			switch = item
	main._on_interacted(switch, null)
	_check(main._notice_label.text.contains("ALREADY OFFLINE") and (lasers[0] as LaserGrid).offline, "a wall switch on an offline grid says so")
	# Cooling: the second grid and the cooling leak.
	gm.repaired["cooling"] = true
	main._on_system_repaired("cooling")
	_check((lasers[1] as LaserGrid).offline, "repairing Cooling switches off the second grid")
	if leaks.has("cooling"):
		_check((leaks["cooling"] as HazardZone).sealed, "and seals the Cooling room's leak")
	# Danger music and sounds look at the leaks too.
	_check(main._gas_zones().size() == vents.size() + leaks.size(), "the game counts the room leaks among its gas zones")
	# A retry builds everything fresh.
	gm.retry()
	main._rebuild_world()
	await process_frame
	var fresh_lasers: Array = main._station["lasers"]
	_check((fresh_lasers[0] as LaserGrid).armed and not (fresh_lasers[0] as LaserGrid).offline and not ((main._station["hazards"] as Array)[1] as HazardZone).sealed, "a retry puts the grids and vents back")
	# Shift 1 has a single grid: Cooling does not break.
	gm.start_shift(8, 1)
	main._rebuild_world()
	await process_frame
	gm.repaired["cooling"] = true
	main._on_system_repaired("cooling")
	_check(main._station["lasers"].size() == 1 and main._notice_label != null, "on shift 1 repairing Cooling has no second grid to switch off, and does not crash")
	main.queue_free()
	await process_frame


func _remove_save() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS  " + label)
	else:
		print("FAIL  " + label)
		_failures += 1
