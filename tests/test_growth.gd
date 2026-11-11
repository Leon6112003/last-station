extends SceneTree
## Hazards that grow with the shift: the numbers (and their caps), the second gravity zone
## from shift 3, and that the real game builds and uses them.
## Run:  godot --headless --path . -s res://tests/test_growth.gd

const SAVE_PATH := "user://test_growth_save.cfg"

var _failures: int = 0


func _initialize() -> void:
	Rules.level = Rules.LEVEL_ENGINEER
	_test_numbers()
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


func _test_numbers() -> void:
	_check(Rules.gas_off_seconds(1) == Rules.GAS_OFF_SECONDS and Rules.gas_on_seconds(1) == Rules.GAS_ON_SECONDS and Rules.gas_length(1) == 6.0, "shift 1 uses the base gas numbers")
	_check(is_equal_approx(Rules.gas_off_seconds(2), 2.5) and is_equal_approx(Rules.gas_on_seconds(2), 6.5) and is_equal_approx(Rules.gas_length(2), 7.0), "shift 2: 0.5 s less quiet, 0.5 s more venting, 1 m longer")
	_check(is_equal_approx(Rules.gas_off_seconds(50), Rules.GAS_OFF_MIN) and is_equal_approx(Rules.gas_on_seconds(50), Rules.GAS_ON_MAX) and is_equal_approx(Rules.gas_length(50), Rules.GAS_LENGTH_MAX), "the gas growth stops at its caps")
	var never_worse_than_cap := true
	for run in range(1, 30):
		never_worse_than_cap = never_worse_than_cap and Rules.gas_off_seconds(run) >= Rules.GAS_OFF_MIN and Rules.gas_on_seconds(run) <= Rules.GAS_ON_MAX and Rules.gas_length(run) <= Rules.GAS_LENGTH_MAX
	_check(never_worse_than_cap, "no shift goes past a cap")
	_check(Rules.gas_off_seconds(0) == Rules.gas_off_seconds(1) and Rules.gravity_off_for(0) == Rules.gravity_off_for(1), "shift 0 is treated as shift 1")
	_check(is_equal_approx(Rules.gravity_off_for(1), 10.0) and is_equal_approx(Rules.gravity_off_for(4), 7.0), "Engineer: the gravity stays off 10 s on shift 1 and 7 s on shift 4")
	_check(is_equal_approx(Rules.gravity_off_for(99), 5.0), "the gravity is never off for less than half of the level's time")
	_check(Rules.gravity_count(1) == 1 and Rules.gravity_count(2) == 1 and Rules.gravity_count(3) == 2 and Rules.gravity_count(9) == 2, "one gravity zone on shifts 1 and 2, two from shift 3")
	Rules.level = Rules.LEVEL_SURVIVOR
	_check(is_equal_approx(Rules.gravity_off_for(1), 6.0) and is_equal_approx(Rules.gravity_off_for(9), 3.0), "Survivor: 6 s on shift 1, never under 3 s")
	Rules.level = Rules.LEVEL_ENGINEER
	# The gas cycle itself.
	var gas := HazardZone.create(Vector3(7, 2.8, 3), Vector3.ZERO, 0.0, 3)
	root.add_child(gas)
	_check(is_equal_approx(gas.cycle_seconds(), Rules.gas_off_seconds(3) + Rules.GAS_WARN_SECONDS + Rules.gas_on_seconds(3)), "a shift 3 vent has a longer cycle than shift 1")
	gas.tick(Rules.gas_off_seconds(3) + 0.1, false)
	_check(gas.phase() == HazardZone.Phase.WARN, "a vent warns after its (shorter) quiet time")
	gas.tick(Rules.GAS_WARN_SECONDS, false)
	_check(gas.is_active(), "and then vents")
	gas.free()


func _test_station() -> void:
	for run in [1, 2, 3, 5]:
		var world := Node3D.new()
		root.add_child(world)
		var station := StationBuilder.build(world, PuzzleGenerator.generate(4, 0), {}, run)
		var gravity_zones: Array = station["gravity_zones"]
		var switches: Array = station["gravity_switches"]
		_check(gravity_zones.size() == Rules.gravity_count(run) and station["gravity"] == gravity_zones[0], "shift %d builds %d gravity zone(s)" % [run, Rules.gravity_count(run)])
		_check(switches.size() == 2 * gravity_zones.size(), "shift %d has two wall switches for each grid" % run)
		var ids := {}
		var all_linked := true
		for item in switches:
			ids[(item as Interactable).id] = true
			all_linked = all_linked and (item as Interactable).get_meta("gravity_zone") in gravity_zones
		_check(ids.size() == switches.size() and all_linked, "shift %d: every switch has its own id and belongs to a grid" % run)
		_check(is_equal_approx((gravity_zones[0] as GravityZone).off_seconds, Rules.gravity_off_for(run)), "shift %d: the grids stay off for %.0f s" % [run, Rules.gravity_off_for(run)])
		var vent: HazardZone = (station["hazards"] as Array)[0]
		_check(is_equal_approx(vent.size.x, Rules.gas_length(run)) and vent.run == run, "shift %d: the vents are %.0f m long" % [run, Rules.gas_length(run)])
		if run >= Rules.SECOND_GRAVITY_FROM_SHIFT:
			var second: GravityZone = gravity_zones[1]
			_check(second.position.x > StationBuilder.ROOM_CENTERS_X["comms"] and second.position.x < StationBuilder.ROOM_CENTERS_X["cooling"], "the second grid is between Comms and Cooling")
			var switch_clear := true
			for item in switches:
				for window_x in StationBuilder.WINDOW_XS:
					switch_clear = switch_clear and absf((item as Node3D).position.x - float(window_x)) > StationBuilder.WINDOW_HALF_WIDTH + 0.45
			_check(switch_clear, "no switch is on top of a window")
		world.free()
		await process_frame


func _test_real_game() -> void:
	_remove_save()
	SaveManager.new(SAVE_PATH).mark_intro_seen()
	var main: Node = load("res://scenes/main.tscn").instantiate()
	main.save_path = SAVE_PATH
	root.add_child(main)
	await process_frame
	main._start_new_game()
	await process_frame
	var gm: GameManager = main.gm
	_check((main._station["gravity_zones"] as Array).size() == 1, "the real game starts shift 1 with one gravity zone")
	gm.run_number = 3
	main._rebuild_world()
	await process_frame
	var gravity_zones: Array = main._station["gravity_zones"]
	_check(gravity_zones.size() == 2, "shift 3 in the real game has two gravity zones")
	# Using the second grid's switch turns off that grid only.
	var second_switch: Interactable = null
	for item in main._station["gravity_switches"]:
		if (item as Interactable).get_meta("gravity_zone") == gravity_zones[1]:
			second_switch = item
	main._on_interacted(second_switch, null)
	_check(not (gravity_zones[1] as GravityZone).armed and (gravity_zones[0] as GravityZone).armed, "a switch turns off its own grid and not the other")
	_check(second_switch.is_inside_tree() and main._notice_label.text.contains("%d s" % int((gravity_zones[1] as GravityZone).off_seconds)), "the notice shows that grid's switch-off time")
	_check(main._station["gravity_zones"].all(func(l: GravityZone) -> bool: return l.touched.get_connections().size() == 1), "each grid is connected to the game exactly once")
	# Danger music also notices the second grid.
	main._player.global_position.x = (gravity_zones[1] as GravityZone).position.x - 2.0
	(gravity_zones[1] as GravityZone)._off_left = 0.0
	(gravity_zones[1] as GravityZone).armed = true
	_check(main._danger_level(0.0) >= 0.65, "the music treats the second grid as danger too")
	gm.run_number = 2
	main._rebuild_world()
	await process_frame
	_check((main._station["gravity_zones"] as Array).size() == 1, "shift 2 has one gravity zone again")
	# The developer start option: a new game on a later shift.
	main._go_to_menu()
	main.dev_start_shift = 4
	main._start_new_game()
	await process_frame
	_check(gm.run_number == 4 and (main._station["gravity_zones"] as Array).size() == 2 and is_equal_approx(gm.reserve, float(Rules.reserve_for_shift(4))), "the --shift option starts a new game on that shift with its reserve and hazards")
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
