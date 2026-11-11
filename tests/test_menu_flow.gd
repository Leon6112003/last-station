extends SceneTree
## Milestone 3 integration test: Main Menu, repeated runs with no leaked nodes,
## hold-R retry, Manuals, real key events, best score and the intro card.
## Run:  godot --headless --path . -s res://tests/test_menu_flow.gd

const SAVE_PATH := "user://test_menu_save.cfg"

var _failures: int = 0


func _initialize() -> void:
	await _test_main_flow_and_leaks()
	await _test_hold_retry()
	await _test_manuals_and_keys()
	await _test_intro_card()
	_remove_save()

	print("")
	if _failures == 0:
		print("ALL PASS")
		quit(0)
	else:
		print("%d FAILURE(S)" % _failures)
		quit(1)


func _new_main(intro_seen: bool) -> Node:
	_remove_save()
	if intro_seen:
		SaveManager.new(SAVE_PATH).mark_intro_seen()
	var main: Node = load("res://scenes/main.tscn").instantiate()
	main.save_path = SAVE_PATH
	root.add_child(main)
	await process_frame
	return main


func _drop(main: Node) -> void:
	main.queue_free()
	await process_frame
	await process_frame


func _solve_all(gm: GameManager) -> void:
	for index in PuzzleValidators.power_order(gm.puzzles["power"]):
		gm.flip_breaker(index)
	var target: Array = PuzzleValidators.oxygen_target(gm.puzzles["oxygen"])
	for i in 3:
		gm.adjust_valve(i, int(target[i]) / Rules.OXYGEN_STEP)
	gm.confirm_oxygen()
	gm.adjust_tuner((PuzzleValidators.comms_target(gm.puzzles["comms"]) - Rules.COMMS_MIN_MHZ) / Rules.COMMS_STEP_MHZ)
	gm.transmit()


func _test_main_flow_and_leaks() -> void:
	var main := await _new_main(true)
	var gm: GameManager = main.gm

	_check(gm.state == GameManager.State.MENU, "the game starts in the Main Menu")
	_check(main._menu_layer.visible and not main._hud_layer.visible and main._world == null, "menu shows; HUD and world are not built yet")
	_check(not main._input_free and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "the menu has no player input and a visible mouse")

	main._update_mood(0.0)
	_check(main.sound._music_active, "the theme song is on at the opening and the menu")

	main._show_how_to_play(false)
	await process_frame
	_check(main._modal_layer != null, "How to Play opens from the menu")
	main._close_modal()
	_check(main._modal_layer == null and main._menu_layer.visible, "How to Play closes back to the menu")

	var node_counts: Array[int] = []
	var orphan_counts: Array[int] = []
	for cycle in 3:
		var label := "cycle %d" % (cycle + 1)
		main._start_new_game()
		await process_frame
		_check(gm.state == GameManager.State.PLAYING and main._world != null and not main._menu_layer.visible, "%s: Play starts a shift" % label)
		_check(gm.run_number == 1 and gm.retry_count == 0, "%s: a new game starts at shift 1 with no retries" % label)

		_solve_all(gm)
		_check(gm.try_reboot() and main._modal_layer != null, "%s: solving and rebooting shows the win screen" % label)

		main._next_shift()
		await process_frame
		_check(gm.run_number == 2 and gm.state == GameManager.State.PLAYING, "%s: Next Shift continues the run" % label)

		gm.begin_clock()
		gm._process(1000.0)
		await process_frame
		_check(gm.state == GameManager.State.FAILED and main._modal_layer != null, "%s: running out of reserve shows the fail screen" % label)

		main._retry()
		await process_frame
		_check(gm.state == GameManager.State.PLAYING and gm.retry_count == 1, "%s: Retry returns to play" % label)

		main._set_paused(true)
		_check(main._pause_overlay.visible and paused, "%s: pausing shows the pause menu" % label)
		main._go_to_menu()
		await process_frame
		await process_frame
		_check(gm.state == GameManager.State.MENU and main._world == null and not paused, "%s: Main Menu frees the world and unpauses" % label)
		_check(main._menu_layer.visible and not main._pause_overlay.visible and main._modal_layer == null, "%s: only the menu is showing" % label)

		node_counts.append(int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)))
		orphan_counts.append(int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)))

	print("      node counts at the menu: ", node_counts, "  orphans: ", orphan_counts)
	_check(node_counts[0] == node_counts[1] and node_counts[1] == node_counts[2], "node count at the menu is identical after every run (no leaked nodes)")
	_check(orphan_counts[2] <= orphan_counts[0], "orphan node count does not grow across runs")

	_check(main.save.best_score > 0, "a best score was saved during the runs")
	_check(main._menu_best_label.text.contains("Best shift score: %d" % main.save.best_score) and main._menu_best_label.text.contains("Best run: %d" % main.save.best_run), "the menu shows the best shift score and the best run")
	await _drop(main)


func _test_hold_retry() -> void:
	var main := await _new_main(true)
	var gm: GameManager = main.gm
	main._start_new_game()
	await process_frame
	_check(main._input_free, "hold-R test: the player is free to act")

	# A short press does nothing.
	Input.action_press("retry_level")
	await create_timer(0.4).timeout
	_check(main._retry_box.visible, "the retry progress bar shows while R is held")
	Input.action_release("retry_level")
	await create_timer(0.15).timeout
	_check(gm.retry_count == 0 and not main._retry_box.visible, "releasing R early cancels the retry")

	# A full hold retries exactly once, even if R stays down.
	Input.action_press("retry_level")
	await create_timer(1.4).timeout
	_check(gm.retry_count == 1, "holding R for 1 s retries (retries = %d)" % gm.retry_count)
	await create_timer(1.4).timeout
	_check(gm.retry_count == 1, "one long press retries only once (retries = %d)" % gm.retry_count)
	Input.action_release("retry_level")
	await create_timer(0.15).timeout

	# Holding R is ignored while a panel is open.
	main._open_panel("oxygen")
	await process_frame
	Input.action_press("retry_level")
	await create_timer(1.3).timeout
	Input.action_release("retry_level")
	_check(gm.retry_count == 1, "holding R is ignored while a puzzle panel is open")
	await _drop(main)


func _test_manuals_and_keys() -> void:
	var main := await _new_main(true)
	var gm: GameManager = main.gm
	main._start_new_game()
	await process_frame

	gm.begin_clock()
	main._open_manuals()
	await process_frame
	_check(main._manuals != null and paused, "opening the manuals pauses the game")
	_check(not main._input_free, "player input is disabled while the manuals are open")
	var before := gm.reserve
	for i in 10:
		await process_frame
	_check(is_equal_approx(gm.reserve, before), "the reserve is frozen while the manuals are open")
	main._close_manuals()
	_check(main._manuals == null and not paused and main._input_free, "closing the manuals resumes the game")

	# Real key events: M toggles the manuals, Esc closes them, Esc pauses.
	_press_key(KEY_M)
	await process_frame
	_check(main._manuals != null, "pressing M opens the manuals")
	_press_key(KEY_M)
	await process_frame
	_check(main._manuals == null, "pressing M again closes them")
	_press_key(KEY_M)
	await process_frame
	_press_key(KEY_ESCAPE)
	await process_frame
	_check(main._manuals == null and not main._paused, "Esc closes the manuals without pausing")
	_press_key(KEY_ESCAPE)
	await process_frame
	_check(main._paused and paused, "Esc pauses the game")
	_press_key(KEY_M)
	await process_frame
	_check(main._manuals == null, "M does nothing while the pause menu is open")
	_press_key(KEY_ESCAPE)
	await process_frame
	_check(not main._paused and not paused, "Esc resumes the game")
	await _drop(main)


func _test_intro_card() -> void:
	var main := await _new_main(false)
	main._start_new_game()
	await process_frame
	_check(main._modal_layer != null and not main._input_free, "the intro card shows on the first launch and blocks input")

	var buttons: Array = main._modal_layer.find_children("*", "Button", true, false)
	_check(buttons.size() == 1 and (buttons[0] as Button).text == "Start", "the intro card has a Start button")
	(buttons[0] as Button).pressed.emit()
	await process_frame
	_check(main._modal_layer == null and main._input_free, "dismissing the intro card gives control to the player")
	_check(SaveManager.new(SAVE_PATH).intro_seen, "the intro card is remembered on disk")

	main._go_to_menu()
	main._start_new_game()
	await process_frame
	_check(main._modal_layer == null, "the intro card does not show again")
	await _drop(main)


func _press_key(keycode: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.physical_keycode = keycode
		event.keycode = keycode
		event.pressed = pressed
		Input.parse_input_event(event)


func _remove_save() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS  ", label)
	else:
		print("FAIL  ", label)
		_failures += 1
