extends SceneTree
## Milestone 2 integration test: loads the real main scene and plays a whole
## shift through the same interactables the player would use.
## Run:  godot --headless --path . -s res://tests/test_flow.gd

const SAVE_PATH := "user://test_flow_save.cfg"

var _failures: int = 0


func _initialize() -> void:
	_remove_save()
	SaveManager.new(SAVE_PATH).mark_intro_seen()  # skip the first-launch card

	var main: Node = load("res://scenes/main.tscn").instantiate()
	main.save_path = SAVE_PATH
	root.add_child(main)
	await process_frame
	main._start_new_game()
	await process_frame

	var gm: GameManager = main.gm
	_check(gm.state == GameManager.State.PLAYING, "main scene starts a shift in PLAYING state")
	var text: String = main._checklist_text()
	_check(text.contains("[ ] Power") and text.contains("[ ] Oxygen") and text.contains("[ ] Comms") and text.contains("Reboot (needs 3/3)"), "the checklist starts with nothing repaired")
	_check(main._player != null and main._player.input_enabled, "player input is enabled at the start")

	# Reboot too early.
	_interact(main, "reboot_terminal")
	_check(gm.state == GameManager.State.PLAYING, "early reboot does nothing")

	# Wrong breaker -> surge.
	var order := PuzzleValidators.power_order(gm.puzzles["power"])
	_interact(main, "breaker_%d" % order[1])
	_check(gm.mistakes == 1 and is_equal_approx(gm.reserve, 465.0), "wrong breaker applies the surge penalty in the real scene")

	# Power: correct order through the real interactables.
	for index in order:
		_interact(main, "breaker_%d" % index)
	_check(gm.repaired["power"], "breakers repair power via interactables")
	_check(main._checklist_text().contains("[x] Power") and main._checklist_text().contains("[ ] Oxygen"), "the checklist ticks Power once it is repaired")
	var power_light: OmniLight3D = main._station["room_lights"]["power"]
	_check(power_light.light_color == Rules.COLOR_CYAN, "power room light turns cyan when repaired")
	var strip: StandardMaterial3D = main._station["room_strips"]["power"]
	_check(strip.albedo_color == Rules.COLOR_CYAN and strip.emission_energy_multiplier > StationBuilder.STRIP_ENERGY_OFF, "power room ceiling strip turns bright cyan when repaired")
	var other_strip: StandardMaterial3D = main._station["room_strips"]["oxygen"]
	_check(other_strip.albedo_color == Rules.COLOR_FAULT, "an unrepaired room keeps its dim red strip")
	var floor_patch: StandardMaterial3D = main._station["room_floors"]["power"]
	_check(is_equal_approx(floor_patch.emission_energy_multiplier, StationBuilder.FLOOR_ENERGY_ON), "power room floor brightens when repaired")
	# Low reserve: the mood code pulses the hub light and shows the red vignette; it never touches the rules.
	gm.reserve = 20.0
	main._update_mood(0.5)
	_check(main._low_vignette.modulate.a > 0.0 and (main._station["hub_light"] as OmniLight3D).light_energy > 0.0, "low reserve shows the red vignette and pulses the hub light")
	gm.reserve = 300.0
	main._update_mood(0.5)
	_check(main._low_vignette.modulate.a == 0.0, "the vignette is off with plenty of reserve")

	# Oxygen: open the real panel, set values through its buttons' logic, confirm.
	_interact(main, "oxygen_console")
	_check(main._panel != null and not main._player.input_enabled, "oxygen panel opens and freezes player input")
	var target: Array = PuzzleValidators.oxygen_target(gm.puzzles["oxygen"])
	for i in 3:
		gm.adjust_valve(i, int(target[i]) / Rules.OXYGEN_STEP)
	main._panel.refresh()
	main._panel._on_confirm_oxygen()
	await process_frame
	_check(gm.repaired["oxygen"], "valve settings repair oxygen through the panel")
	_check(main._panel == null, "panel closes after solving")

	# Comms.
	_interact(main, "comms_console")
	_check(main._panel != null, "comms panel opens")
	gm.adjust_tuner((PuzzleValidators.comms_target(gm.puzzles["comms"]) - Rules.COMMS_MIN_MHZ) / Rules.COMMS_STEP_MHZ)
	main._panel._on_transmit()
	await process_frame
	_check(gm.repaired["comms"], "frequency repairs comms through the panel")
	_check(main._checklist_text().contains("-> REBOOT"), "the checklist points to the reboot terminal at 3/3")

	# Win.
	_interact(main, "reboot_terminal")
	await process_frame
	_check(gm.state == GameManager.State.WON, "reboot wins the shift at 3/3")
	_check(main._modal_layer != null, "win screen is shown")
	_check(main.save.best_score > 0 and SaveManager.new(SAVE_PATH).best_score == main.save.best_score, "the winning score is saved as the best score")
	_check(not main._player.input_enabled and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "win screen frees the mouse and freezes the player")

	# Next shift: new seed, fresh state, one world.
	var old_seed := gm.seed_value
	main._next_shift()
	await process_frame
	_check(gm.seed_value != old_seed and gm.run_number == 2, "Next Shift uses a new seed and bumps the run number")
	_check(gm.retry_count == 0 and gm.repaired_count() == 0 and gm.mistakes == 0, "Next Shift resets run state")
	_check(main._modal_layer == null and main._player.input_enabled, "Next Shift closes the win screen and re-enables input")
	_check(main.get_children().filter(func(n: Node) -> bool: return n.name.begins_with("World")).size() == 1, "exactly one World node exists after a rebuild")

	# Retry from a failed shift.
	gm.begin_clock()
	gm._process(1000.0)
	await process_frame
	_check(gm.state == GameManager.State.FAILED and main._modal_layer != null, "reserve reaching 0 shows the fail screen")
	var seed_before := gm.seed_value
	main._retry()
	await process_frame
	_check(gm.seed_value == seed_before and gm.retry_count == 1, "Retry keeps the seed and counts a retry")
	_check(gm.state == GameManager.State.PLAYING and main._modal_layer == null, "Retry returns to PLAYING with no modal")

	# Pause and resume.
	main._set_paused(true)
	_check(paused and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE and not main._player.input_enabled, "pause freezes the tree, frees the mouse and disables input")
	main._set_paused(false)
	# Mouse capture itself cannot be tested headless (the headless display server
	# ignores MOUSE_MODE_CAPTURED); verify that one manually in a real window.
	_check(not paused and not main._paused and main._player.input_enabled, "resume unfreezes the tree and re-enables player input")

	# The reserve must not run while paused.
	gm.begin_clock()
	var reserve_before := gm.reserve
	main._set_paused(true)
	for i in 10:
		await process_frame
	_check(is_equal_approx(gm.reserve, reserve_before), "reserve is frozen while paused")
	main._set_paused(false)

	_remove_save()
	print("")
	if _failures == 0:
		print("ALL PASS")
		quit(0)
	else:
		print("%d FAILURE(S)" % _failures)
		quit(1)


func _remove_save() -> void:
	var absolute := ProjectSettings.globalize_path(SAVE_PATH)
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(absolute)


func _interact(main: Node, id: String) -> void:
	for item in main._station["interactables"]:
		if (item as Interactable).id == id:
			(item as Interactable).interact(main._player)
			return
	push_error("no interactable " + id)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS  ", label)
	else:
		print("FAIL  ", label)
		_failures += 1
