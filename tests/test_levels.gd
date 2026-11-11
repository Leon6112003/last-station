extends SceneTree
## The three difficulty levels (Rookie, Engineer, Survivor): the numbers they change, the
## score multiplier, the saved choice, the menu selector, and that a level reaches the real game.
## Run:  godot --headless --path . -s res://tests/test_levels.gd

const SAVE_PATH := "user://test_levels_save.cfg"

var _failures: int = 0
var _picked: Array[int] = []


func _initialize() -> void:
	_remove_save()
	_test_numbers()
	_test_score()
	_test_save()
	await _test_menu_selector()
	await _test_real_game()
	Rules.level = Rules.LEVEL_ENGINEER
	_remove_save()
	print("")
	if _failures == 0:
		print("ALL PASS")
		quit(0)
	else:
		print("%d FAILURE(S)" % _failures)
		quit(1)


func _test_numbers() -> void:
	Rules.level = Rules.LEVEL_ENGINEER
	_check(Rules.level_name() == "Engineer" and Rules.reserve_for_shift(1) == 360 and Rules.gas_drain() == 12.0 and Rules.gravity_penalty() == 10.0 and Rules.gravity_off() == 10.0 and Rules.oracle_cost() == 5 and Rules.hint_cost() == 20 and Rules.surge_penalty() == 15 and Rules.confirm_penalty() == 10, "Engineer is the standard game with the original numbers")
	Rules.level = Rules.LEVEL_ROOKIE
	_check(Rules.level_name() == "Rookie" and Rules.reserve_for_shift(1) == 480 and Rules.reserve_for_shift(2) == 435 and Rules.reserve_for_shift(50) == 240, "Rookie has 480 s, 45 s less each shift, never under 240 s")
	_check(Rules.gas_drain() == 6.0 and Rules.gravity_penalty() == 5.0 and Rules.gravity_off() == 15.0 and Rules.oracle_cost() == 0 and Rules.hint_cost() == 10 and Rules.surge_penalty() == 8 and Rules.confirm_penalty() == 5, "Rookie hazards, help and penalties are gentler")
	Rules.level = Rules.LEVEL_SURVIVOR
	_check(Rules.level_name() == "Survivor" and Rules.reserve_for_shift(1) == 270 and Rules.reserve_for_shift(50) == 150, "Survivor has 270 s and never under 150 s")
	_check(Rules.gas_drain() == 20.0 and Rules.gravity_penalty() == 20.0 and Rules.gravity_off() == 6.0 and Rules.oracle_cost() == 10 and Rules.hint_cost() == 40 and Rules.surge_penalty() == 30 and Rules.confirm_penalty() == 20, "Survivor hazards, help and penalties are harsher")
	var ordered := true
	for key in ["gas", "gravity_penalty", "oracle", "hint", "surge", "confirm", "score"]:
		ordered = ordered and Rules.LEVELS[0][key] <= Rules.LEVELS[1][key] and Rules.LEVELS[1][key] <= Rules.LEVELS[2][key]
	_check(ordered and Rules.LEVELS[0]["reserve"] >= Rules.LEVELS[1]["reserve"] and Rules.LEVELS[1]["reserve"] >= Rules.LEVELS[2]["reserve"] and Rules.LEVELS[0]["gravity_off"] >= Rules.LEVELS[1]["gravity_off"], "every number gets harder from Rookie to Engineer to Survivor")
	_check(Rules.RESERVE_MAX_SECONDS == Rules.LEVELS[0]["reserve"], "the clamp for the reserve is the largest starting reserve")
	Rules.level = 99
	_check(Rules.level_name() == "Survivor", "an out-of-range level is clamped, never a crash")
	Rules.level = -5
	_check(Rules.level_name() == "Rookie", "a negative level is clamped too")


func _test_score() -> void:
	Rules.level = Rules.LEVEL_ENGINEER
	_check(ScoreManager.final_score(100.0, 0) == 350, "Engineer: 300 + 50 = 350")
	Rules.level = Rules.LEVEL_ROOKIE
	_check(ScoreManager.final_score(100.0, 0) == 210 and is_equal_approx(float(ScoreManager.breakdown(100.0, 0)["multiplier"]), 0.6), "Rookie scores are multiplied by 0.6")
	Rules.level = Rules.LEVEL_SURVIVOR
	_check(ScoreManager.final_score(100.0, 0) == 490, "Survivor scores are multiplied by 1.4")
	Rules.level = Rules.LEVEL_ENGINEER


func _test_save() -> void:
	var save := SaveManager.new(SAVE_PATH)
	_check(save.difficulty == Rules.LEVEL_ENGINEER, "a new save starts on Engineer")
	save.set_difficulty(Rules.LEVEL_SURVIVOR)
	_check(SaveManager.new(SAVE_PATH).difficulty == Rules.LEVEL_SURVIVOR, "the chosen level is remembered")
	save.set_difficulty(42)
	_check(SaveManager.new(SAVE_PATH).difficulty == Rules.LEVEL_SURVIVOR, "an invalid level is clamped when saved")
	_remove_save()


func _test_menu_selector() -> void:
	var menu := MenuScreen.create(func() -> void: pass, func() -> void: pass, func() -> void: pass, false, func(level: int) -> void: _picked.append(level), Rules.LEVEL_SURVIVOR)
	root.add_child(menu)
	await process_frame
	var buttons := menu.find_children("*", "Button", true, false)
	var names: Array[String] = []
	for button in buttons:
		names.append((button as Button).text)
	_check(names == ["Rookie", "Engineer", "Survivor", "Play", "How to Play", "Quit", "Settings"], "the menu shows the three levels above Play")
	var any_lit := false
	for i in 3:
		any_lit = any_lit or (buttons[i] as Button).button_pressed
	_check(not any_lit, "no level button is highlighted when the menu opens")
	var blurb := menu.find_children("*", "Label", true, false).filter(func(l: Node) -> bool: return (l as Label).text.begins_with("Survivor:"))
	_check(not blurb.is_empty(), "a line under the buttons names the level in use")
	(buttons[0] as Button).pressed.emit()
	_check(_picked == [0] and (buttons[0] as Button).button_pressed and not (buttons[2] as Button).button_pressed, "clicking a level reports it and highlights only that level")
	menu.set_level(Rules.LEVEL_SURVIVOR)
	any_lit = false
	for i in 3:
		any_lit = any_lit or (buttons[i] as Button).button_pressed
	_check(not any_lit, "reopening the menu clears the highlight again")
	menu.queue_free()
	await process_frame


func _test_real_game() -> void:
	SaveManager.new(SAVE_PATH).mark_intro_seen()
	var main: Node = load("res://scenes/main.tscn").instantiate()
	main.save_path = SAVE_PATH
	root.add_child(main)
	await process_frame
	main._set_level(Rules.LEVEL_SURVIVOR)
	_check(SaveManager.new(SAVE_PATH).difficulty == Rules.LEVEL_SURVIVOR, "the menu choice is written to the save file")
	main._start_new_game()
	await process_frame
	var gm: GameManager = main.gm
	_check(is_equal_approx(gm.reserve, 270.0), "a Survivor shift starts with 270 s (%.0f)" % gm.reserve)
	_check(main._checklist_text().contains("SURVIVOR"), "the level is named at the top of the objectives")
	gm.reserve = 100.0
	var charged := gm.charge_oracle_question()
	_check(charged == 10 and is_equal_approx(gm.reserve, 90.0), "a Survivor ORACLE question costs 10 s")
	gm.hazard_damage("gas", 6.0)
	_check(is_equal_approx(gm.reserve, 84.0), "hazard damage is taken as given")
	main._go_to_menu()
	await process_frame
	main._set_level(Rules.LEVEL_ROOKIE)
	main._start_new_game()
	await process_frame
	_check(is_equal_approx(gm.reserve, 480.0), "a Rookie shift starts with 480 s (%.0f)" % gm.reserve)
	var before := gm.reserve
	_check(gm.charge_oracle_question() == 0 and is_equal_approx(gm.reserve, before), "Rookie ORACLE questions are free")
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
