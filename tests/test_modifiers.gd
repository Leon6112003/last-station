extends SceneTree
## The three optional modifiers: Blackout, Hardcore and Speedrun. Their rules, the score, the
## saved choice, the menu switches, and that the real game applies them.
## Run:  godot --headless --path . -s res://tests/test_modifiers.gd

const SAVE_PATH := "user://test_modifiers_save.cfg"

var _failures: int = 0
var _toggled: Array = []


func _initialize() -> void:
	_remove_save()
	_test_rules()
	_test_score()
	_test_save()
	await _test_menu()
	await _test_blackout()
	await _test_speedrun()
	await _test_hardcore()
	Rules.mods = 0
	_remove_save()
	print("")
	if _failures == 0:
		print("ALL PASS")
		quit(0)
	else:
		print("%d FAILURE(S)" % _failures)
		quit(1)


func _test_rules() -> void:
	Rules.mods = 0
	_check(Rules.mods_text() == "" and not Rules.has_mod(Rules.MOD_HARDCORE), "no modifier is on by default")
	Rules.set_mod(Rules.MOD_BLACKOUT, true)
	Rules.set_mod(Rules.MOD_SPEEDRUN, true)
	_check(Rules.has_mod(Rules.MOD_BLACKOUT) and Rules.has_mod(Rules.MOD_SPEEDRUN) and not Rules.has_mod(Rules.MOD_HARDCORE), "modifiers can be combined")
	_check(Rules.mods_text() == "Blackout + Speedrun", "the names are listed in order")
	Rules.set_mod(Rules.MOD_BLACKOUT, false)
	_check(Rules.mods_text() == "Speedrun", "a modifier can be switched off again")
	Rules.mods = 99
	Rules.set_mod(Rules.MOD_HARDCORE, true)
	_check(Rules.mods <= Rules.MODS_ALL, "stray bits are dropped")
	Rules.mods = 0
	_check(Rules.MOD_FLAGS.size() == 3 and Rules.MOD_NAMES.size() == 3 and Rules.MOD_BLURBS.size() == 3 and Rules.MOD_SCORE.size() == 3, "every modifier has a name, a blurb and a score factor")
	# Speedrun par and bonus.
	_check(is_equal_approx(Rules.par_seconds(1), 180.0), "par is half the shift's starting reserve (180 s on shift 1 of Engineer)")
	_check(Rules.speed_bonus(100.0, 180.0) == 0, "no speed bonus unless Speedrun is on")
	Rules.set_mod(Rules.MOD_SPEEDRUN, true)
	_check(Rules.speed_bonus(100.0, 180.0) == 180, "within par: 100 + 80 seconds under = 180")
	_check(Rules.speed_bonus(180.0, 180.0) == 100, "exactly on par still gets the flat 100")
	_check(Rules.speed_bonus(181.0, 180.0) == 0, "a second over par gets nothing")
	Rules.mods = 0


func _test_score() -> void:
	Rules.level = Rules.LEVEL_ENGINEER
	Rules.mods = 0
	var plain := ScoreManager.final_score(100.0, 0, 80.0, 180.0)
	_check(plain == 350, "with no modifiers the score is as before (350)")
	Rules.set_mod(Rules.MOD_BLACKOUT, true)
	_check(ScoreManager.final_score(100.0, 0) == int(round(350.0 * 1.15)), "Blackout multiplies the score by 1.15")
	Rules.set_mod(Rules.MOD_HARDCORE, true)
	_check(is_equal_approx(Rules.score_multiplier(), 1.15 * 1.25), "Blackout and Hardcore multiply together")
	Rules.mods = 0
	Rules.set_mod(Rules.MOD_SPEEDRUN, true)
	_check(ScoreManager.final_score(100.0, 0, 80.0, 180.0) == 350 + 200, "Speedrun adds its bonus before the multipliers (350 + 100 + 100)")
	_check(ScoreManager.final_score(100.0, 0, 200.0, 180.0) == 350, "missing par adds nothing")
	var parts := ScoreManager.breakdown(100.0, 0, 80.0, 180.0)
	_check(parts["speed_bonus"] == 200 and parts["final"] == 550, "the breakdown reports the speed bonus")
	Rules.level = Rules.LEVEL_SURVIVOR
	Rules.set_mod(Rules.MOD_HARDCORE, true)
	_check(is_equal_approx(Rules.score_multiplier(), 1.4 * 1.25), "a level and a modifier multiply together")
	Rules.level = Rules.LEVEL_ENGINEER
	Rules.mods = 0


func _test_save() -> void:
	var save := SaveManager.new(SAVE_PATH)
	_check(save.modifiers == 0, "a new save has no modifiers on")
	save.set_modifiers(Rules.MOD_BLACKOUT | Rules.MOD_HARDCORE)
	_check(SaveManager.new(SAVE_PATH).modifiers == 3, "the chosen modifiers are remembered")
	save.set_modifiers(999)
	_check(SaveManager.new(SAVE_PATH).modifiers == Rules.MODS_ALL, "an invalid value is clamped when saved")
	_remove_save()


func _test_menu() -> void:
	var menu := MenuScreen.create(func() -> void: pass, func() -> void: pass, func() -> void: pass, false,
		func(_level: int) -> void: pass, Rules.LEVEL_ENGINEER,
		func(flag: int, on: bool) -> void: _toggled.append([flag, on]), Rules.MOD_HARDCORE)
	root.add_child(menu)
	await process_frame
	var names: Array[String] = []
	for button in menu.find_children("*", "Button", true, false):
		names.append((button as Button).text)
	_check(names == ["Rookie", "Engineer", "Survivor", "Blackout", "Hardcore", "Speedrun", "Play", "How to Play", "Quit", "Settings"], "the menu shows the three modifier switches under the levels")
	var buttons := menu.find_children("*", "Button", true, false)
	_check(not (buttons[3] as Button).button_pressed and (buttons[4] as Button).button_pressed and not (buttons[5] as Button).button_pressed, "only the saved modifier is on when the menu opens")
	(buttons[3] as Button).button_pressed = true
	_check(_toggled == [[Rules.MOD_BLACKOUT, true]] and (buttons[3] as Button).button_pressed, "switching one on reports it and highlights it")
	(buttons[4] as Button).button_pressed = false
	_check(_toggled.size() == 2 and _toggled[1] == [Rules.MOD_HARDCORE, false], "switching one off reports it")
	menu.set_modifiers(0)
	var any_on := false
	for i in range(3, 6):
		any_on = any_on or (buttons[i] as Button).button_pressed
	_check(not any_on, "reopening the menu with none on clears every switch")
	var line := menu.find_children("*", "Label", true, false).filter(func(l: Node) -> bool: return (l as Label).text.begins_with("Optional extras"))
	_check(not line.is_empty() and (line[0] as Label).text.ends_with("none"), "a line names the modifiers that are on")
	menu.queue_free()
	await process_frame


func _new_main() -> Node:
	_remove_save()
	SaveManager.new(SAVE_PATH).mark_intro_seen()
	var main: Node = load("res://scenes/main.tscn").instantiate()
	main.save_path = SAVE_PATH
	root.add_child(main)
	await process_frame
	return main


func _vent_offsets(run: int) -> Array[float]:
	# Read straight after building, before any frame has moved the vents on.
	var world := Node3D.new()
	root.add_child(world)
	var station := StationBuilder.build(world, PuzzleGenerator.generate(8, 0), {}, run)
	var offsets: Array[float] = []
	for zone in station["hazards"]:
		offsets.append((zone as HazardZone)._time)
	world.free()
	return offsets


func _test_blackout() -> void:
	Rules.mods = 0
	var plain1 := _vent_offsets(1)
	_check(plain1 == _vent_offsets(3) and plain1 == _vent_offsets(7), "without Blackout the vents start at the same point every shift")
	Rules.set_mod(Rules.MOD_BLACKOUT, true)
	var shift1 := _vent_offsets(1)
	var shift3 := _vent_offsets(3)
	_check(shift1 == plain1 and shift3 != shift1 and _vent_offsets(2) != shift3, "with Blackout shift 1 is as before and every later shift starts the vents elsewhere")
	_check(_vent_offsets(3) == shift3, "the same shift always gets the same vent timing, so a retry plays the same walk")
	var main := await _new_main()
	Rules.mods = 0
	Rules.set_mod(Rules.MOD_BLACKOUT, true)   # (starting the game read the empty save)
	main._start_new_game()
	await process_frame
	# The lights flicker: over a few seconds their energy varies, stays under the base, and dips.
	var lights: Array = main._station["corridor_lights"]
	var lowest := 10.0
	var highest := 0.0
	var step := 0.0
	main._mood_time = 0.0
	for i in 900:
		main._mood_time += 0.02
		main._flicker_corridor_lights()
		for light in lights:
			lowest = minf(lowest, (light as OmniLight3D).light_energy)
			highest = maxf(highest, (light as OmniLight3D).light_energy)
	_check(lights.size() == 8 and highest <= StationBuilder.HUB_LIGHT_ENERGY + 0.0001 and lowest < StationBuilder.HUB_LIGHT_ENERGY * 0.1 and highest > StationBuilder.HUB_LIGHT_ENERGY * 0.8, "the corridor lights flicker, dip out briefly, and never go above their normal energy")
	var calm_floor := 10.0
	for t in range(0, 600):
		main._mood_time = 0.5 + float(t) * 0.01   # stay clear of the dips (each light dips on its own schedule)
		main._flicker_corridor_lights()
		var lit_count := 0
		for light in lights:
			if (light as OmniLight3D).light_energy >= StationBuilder.HUB_LIGHT_ENERGY * Rules.BLACKOUT_MIN_LEVEL - 0.0001:
				lit_count += 1
		calm_floor = minf(calm_floor, float(lit_count))
	_check(calm_floor >= 5.0, "at any moment most corridor lights are still on, so it stays walkable (at least %d of 8)" % int(calm_floor))
	main.queue_free()
	await process_frame
	Rules.mods = 0


func _test_speedrun() -> void:
	var main := await _new_main()
	Rules.mods = 0
	main._start_new_game()
	await process_frame
	main._update_par_label()
	_check(not main._par_label.visible, "no par readout without Speedrun")
	Rules.set_mod(Rules.MOD_SPEEDRUN, true)
	main._update_par_label()
	_check(main._par_label.visible and main._par_label.text.begins_with("PAR 03:00"), "Speedrun shows the par time (03:00 on shift 1 of Engineer)")
	main.gm.reserve = float(Rules.reserve_for_shift(1)) - 100.0
	main._update_par_label()
	_check(main._par_label.text.contains("01:20 TO BEAT IT"), "it counts down the time left to beat par (01:20 after 100 s)")
	main.gm.reserve = float(Rules.reserve_for_shift(1)) - 200.0
	main._update_par_label()
	_check(main._par_label.text.contains("MISSED"), "it says MISSED once par is gone")
	# A win inside par shows the bonus.
	main.gm.reserve = 300.0
	for index in PuzzleValidators.power_order(main.gm.puzzles["power"]):
		main.gm.flip_breaker(index)
	var target: Array = PuzzleValidators.oxygen_target(main.gm.puzzles["oxygen"])
	for i in 3:
		main.gm.adjust_valve(i, int(target[i]) / Rules.OXYGEN_STEP)
	main.gm.confirm_oxygen()
	main.gm.adjust_tuner((PuzzleValidators.comms_target(main.gm.puzzles["comms"]) - Rules.COMMS_MIN_MHZ) / Rules.COMMS_STEP_MHZ)
	main.gm.transmit()
	main.gm.adjust_coolant(PuzzleValidators.cooling_target(main.gm.puzzles["cooling"]))
	main.gm.engage_cooling()
	for pad in PuzzleValidators.reboot_answer(main.gm.puzzles["reboot"]):
		main.gm.press_reboot_pad(pad)
	main.gm.try_reboot()
	await process_frame
	var text := ""
	for label in main._modal_layer.find_children("*", "Label", true, false):
		text += (label as Label).text + "\n"
	_check(text.contains("Speed bonus: +") and text.contains("par 03:00") and text.contains("Speedrun"), "the win screen shows the speed bonus and the modifier")
	main.queue_free()
	await process_frame
	Rules.mods = 0


func _test_hardcore() -> void:
	var main := await _new_main()
	Rules.mods = 0
	Rules.set_mod(Rules.MOD_HARDCORE, true)   # (creating the game read the empty save)
	main._start_new_game()
	await process_frame
	var gm: GameManager = main.gm
	_check(main._checklist_text().contains("HARDCORE"), "the objectives name the modifier")
	var seed_before := gm.seed_value
	main._retry()
	await process_frame
	_check(gm.retry_count == 0 and gm.seed_value == seed_before and main._notice_label.text.contains("NO RETRIES"), "Hardcore refuses a retry and says why")
	main._set_paused(true)
	_check(main._pause_retry_button.disabled, "the pause menu's Retry button is greyed out")
	main._set_paused(false)
	gm.run_score = 420
	gm.begin_clock()
	gm._process(1000.0)
	await process_frame
	_check(gm.state == GameManager.State.FAILED and gm.run_score == 0, "a failed shift clears the run score")
	var labels := ""
	var buttons: Array[String] = []
	for node in main._modal_layer.find_children("*", "Label", true, false):
		labels += (node as Label).text + "\n"
	for node in main._modal_layer.find_children("*", "Button", true, false):
		buttons.append((node as Button).text)
	_check(labels.contains("RUN OVER") and labels.contains("420"), "the fail screen says RUN OVER and shows the score that was lost")
	_check(buttons == ["New Run", "Main Menu", "Quit"], "it offers a new run, not a retry")
	main._start_new_game()
	await process_frame
	_check(gm.run_number == 1 and gm.state == GameManager.State.PLAYING and gm.run_score == 0, "New Run starts again from shift 1 with no score")
	Rules.mods = 0
	main._set_paused(true)
	_check(not main._pause_retry_button.disabled, "with Hardcore off the Retry button works again")
	main._set_paused(false)
	main._retry()
	await process_frame
	_check(gm.retry_count == 1, "and a retry works")
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
