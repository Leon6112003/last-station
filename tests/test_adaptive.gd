extends SceneTree
## Rule-based adaptive difficulty: the pure rule and its boundaries, the smoothing, the steps and their
## limits, how an adaptation changes the next shift's reserve and hazards, and how it works in the real game.
## Run:  godot --headless --path . -s res://tests/test_adaptive.gd

const SAVE_PATH := "user://test_adaptive_save.cfg"

var _failures: int = 0


func _initialize() -> void:
	Rules.level = Rules.LEVEL_ENGINEER
	Rules.mods = 0
	Rules.adaptive = true
	Rules.adapt = 0
	_test_rule()
	_test_smoothing_and_steps()
	_test_effects()
	_test_game_manager()
	await _test_real_game()
	Rules.adapt = 0
	_remove_save()
	print("")
	if _failures == 0:
		print("ALL PASS")
		quit(0)
	else:
		print("%d FAILURE(S)" % _failures)
		quit(1)


func _test_rule() -> void:
	var A := AdaptiveDifficulty
	_check(A.decide(0.30, 0, 0) == A.HARDER, "a fast, clean shift (30% of the reserve, no mistakes, no retries) makes the next harder")
	_check(A.decide(0.60, 1, 0) == A.SAME, "a middling shift stays balanced")
	_check(A.decide(0.90, 0, 0) == A.EASIER, "using 90% of the reserve makes the next easier")
	_check(A.decide(0.30, 0, 3) == A.EASIER and A.decide(0.30, 0, 4) == A.EASIER, "3 or more retries make it easier even if it was fast (the easier rule has priority)")
	_check(A.decide(0.30, 6, 0) == A.EASIER and A.decide(0.30, 9, 0) == A.EASIER, "6 or more mistakes make it easier even if it was fast")
	_check(A.decide(0.30, 2, 1) == A.HARDER, "2 mistakes and 1 retry is still clean enough to go harder")
	_check(A.decide(0.30, 3, 0) == A.SAME, "3 mistakes is too many to go harder, but not enough to go easier")
	_check(A.decide(0.30, 0, 2) == A.SAME, "2 retries is too many to go harder, but not enough to go easier")
	# Boundaries are strict: exactly on a threshold does not trigger it.
	_check(A.decide(A.RATIO_EASIER, 0, 0) == A.SAME, "exactly 80% is not 'more than 80%'")
	_check(A.decide(A.RATIO_EASIER + 0.001, 0, 0) == A.EASIER, "just over 80% is easier")
	_check(A.decide(A.RATIO_HARDER, 0, 0) == A.SAME, "exactly 40% is not 'under 40%'")
	_check(A.decide(A.RATIO_HARDER - 0.001, 0, 0) == A.HARDER, "just under 40% is harder")
	_check(A.decide(0.30, A.MISTAKES_HARDER, A.RETRIES_HARDER) == A.HARDER and A.decide(0.30, A.MISTAKES_HARDER + 1, 0) == A.SAME, "at most 2 mistakes and 1 retry, inclusive")
	# Same inputs, same decision: no randomness.
	var same := true
	for i in 20:
		same = same and A.decide(0.35, 1, 1) == A.HARDER
	_check(same, "the rule is deterministic")
	_check(A.reason(A.HARDER).contains("harder") and A.reason(A.EASIER).contains("gentler") and A.reason(A.SAME).contains("balanced"), "each decision has a plain sentence")
	_check(A.reason(A.HARDER, false).contains("switched off"), "and a different one when the option is off")
	_check(A.label(A.HARDER) == "HARDER" and A.label(A.EASIER) == "EASIER" and A.label(A.SAME) == "BALANCED", "and a short label")


func _test_smoothing_and_steps() -> void:
	var A := AdaptiveDifficulty
	_check(is_equal_approx(A.averaged(0.30, -1.0), 0.30), "the first shift of a run uses its own ratio")
	_check(is_equal_approx(A.averaged(0.30, 0.90), 0.60), "later shifts average with the previous one")
	# One unlucky shift after a brilliant one does not swing straight to easier.
	var info := A.evaluate(290.0, 360.0, 0, 0, 0.20, 0)   # used 81% but the last shift used 20%
	_check(info["decision"] == A.SAME and not info["changed"], "one slow shift after a fast one stays balanced (the average is 50%)")
	info = A.evaluate(290.0, 360.0, 0, 0, -1.0, 0)
	_check(info["decision"] == A.EASIER and info["steps"] == -1 and info["changed"], "the same slow shift with no history is easier")
	_check(A.next_steps(0, A.HARDER) == 1 and A.next_steps(1, A.EASIER) == 0 and A.next_steps(1, A.SAME) == 1, "steps move by one")
	_check(A.next_steps(A.STEPS_MAX, A.HARDER) == A.STEPS_MAX and A.next_steps(A.STEPS_MIN, A.EASIER) == A.STEPS_MIN, "steps stop at their limits")
	info = A.evaluate(50.0, 360.0, 0, 0, -1.0, 0, false)
	_check(info["decision"] == A.SAME and info["steps"] == 0 and not info["enabled"], "with the option off nothing adapts, and the steps stay 0")
	info = A.evaluate(50.0, 360.0, 0, 0, -1.0, 2, false)
	_check(info["steps"] == 0, "switching it off puts an earlier adaptation back to 0")
	info = A.evaluate(1000.0, 360.0, 0, 0, -1.0, 0)
	_check(is_equal_approx(info["ratio"], 1.0), "a ratio never goes over 100%")
	info = A.evaluate(10.0, 0.0, 0, 0, -1.0, 0)
	_check(info["ratio"] >= 0.0 and info["ratio"] <= 1.0, "a zero reserve does not divide by zero")


func _test_effects() -> void:
	Rules.adapt = 0
	_check(Rules.reserve_for_shift(1) == 360 and Rules.reserve_for_shift(3) == 270, "no adaptation: the normal curve (360 s on shift 1, 270 s on shift 3)")
	_check(Rules.reserve_for(3, 1) == 225 and Rules.reserve_for(3, -1) == 315, "one step harder is 45 s less, one step easier 45 s more")
	_check(Rules.reserve_for(1, 3) == 225 and Rules.reserve_for(1, -2) == 360, "a harder step cuts shift 1's reserve, an easier one never goes above the level's start (360 s): easier only undoes the growth")
	_check(Rules.reserve_for(30, 3) == Rules.RESERVE_MIN_SECONDS, "the reserve never goes below the level's floor")
	Rules.adapt = 1
	_check(is_equal_approx(Rules.gas_length(1), 7.0), "one step harder makes shift 1's gas as long as a normal shift 2's (7 m)")
	_check(Rules.laser_count(1) == 1 and Rules.laser_count(2) == 2, "the second laser grid comes one shift earlier")
	_check(Rules.sequence_length(2) == 5 and Rules.sequence_length(1) == 4, "the reboot code grows one step sooner (5 pads on shift 2 instead of 4)")
	Rules.adapt = -2
	_check(Rules.gas_length(1) == 6.0 and Rules.gas_length(3) == 6.0 and Rules.gas_off_seconds(3) == Rules.GAS_OFF_SECONDS, "easier steps never go below the base hazards")
	_check(Rules.laser_count(5) == 2 and Rules.laser_count(4) == 1, "two steps easier delays the second grid by two shifts")
	Rules.adapt = 0
	Rules.level = Rules.LEVEL_ROOKIE
	_check(Rules.reserve_for(1, 0) == 480 and Rules.reserve_for(2, 1) == 390, "it works on the other levels too (Rookie 480 s, then one step harder at shift 2)")
	Rules.level = Rules.LEVEL_ENGINEER


func _clear(gm: GameManager, spend: float, mistakes_to_make: int = 0) -> Dictionary:
	var captured := {}
	var handler := func(result: Dictionary) -> void: captured.merge(result, true)
	gm.shift_won.connect(handler)
	for id in GameManager.SYSTEM_IDS:
		gm.repaired[id] = true
	var answer := PuzzleValidators.reboot_answer(gm.puzzles["reboot"])
	for i in mistakes_to_make:
		gm.press_reboot_pad((answer[0] + 1) % Rules.SEQ_PAD_COUNT)
	gm.reserve = float(Rules.reserve_for_shift(gm.run_number)) - spend - float(mistakes_to_make * Rules.confirm_penalty())
	for pad in answer:
		gm.press_reboot_pad(pad)
	gm.try_reboot()
	gm.shift_won.disconnect(handler)
	return captured


func _test_game_manager() -> void:
	var gm := GameManager.new()
	root.add_child(gm)
	gm.start_shift(40, 1)
	_check(gm.adapt_steps == 0 and Rules.adapt == 0 and gm.reserve == 360.0, "a new run starts on the normal curve")
	var result := _clear(gm, 100.0)   # 28% of 360 s
	_check(result["adaptation"]["decision"] == AdaptiveDifficulty.HARDER and gm.pending_adapt == 1, "a quick clean clear makes the next shift harder")
	_check(result["next_reserve"] == 270, "the result names the adapted reserve (315 s minus one step = 270 s)")
	gm.start_shift(41, 2)
	_check(gm.adapt_steps == 1 and Rules.adapt == 1 and is_equal_approx(gm.reserve, 270.0), "the next shift starts with that adaptation in force and the reduced reserve")
	_check(Rules.laser_count(2) == 2 and gm.second_laser_new, "and the second laser grid arrives on shift 2, announced as new")
	# A retry keeps the adaptation, and the retries then count.
	gm.retry()
	_check(gm.adapt_steps == 1 and Rules.adapt == 1 and is_equal_approx(gm.reserve, 270.0), "a retry keeps the same adaptation and the same reserve")
	gm.retry()
	gm.retry()
	_check(gm.retry_count == 3, "three retries")
	var struggled := _clear(gm, 200.0)
	_check(struggled["adaptation"]["decision"] == AdaptiveDifficulty.EASIER and gm.pending_adapt == 0, "three retries make the next shift easier: back to the normal curve")
	gm.start_shift(42, 3)
	_check(gm.adapt_steps == 0 and Rules.adapt == 0 and is_equal_approx(gm.reserve, 270.0) and not gm.second_laser_new, "shift 3 is on the normal curve again (270 s) and the grid is not new")
	# A middling shift keeps things as they are.
	var middling := _clear(gm, 190.0, 1)
	_check(middling["adaptation"]["decision"] == AdaptiveDifficulty.SAME and gm.pending_adapt == 0, "a middling shift stays balanced")
	# Back to the menu and a new run forget everything.
	gm.start_shift(43, 4)
	_clear(gm, 5.0)
	_check(gm.pending_adapt == 1, "another fast shift")
	gm.enter_menu()
	_check(gm.adapt_steps == 0 and gm.pending_adapt == 0 and gm.previous_ratio < 0.0 and Rules.adapt == 0, "going to the menu clears the adaptation")
	gm.start_shift(44, 1)
	_check(gm.adapt_steps == 0 and gm.pending_adapt == 0 and Rules.adapt == 0, "and so does a new run")
	# Switched off.
	Rules.adaptive = false
	var off := _clear(gm, 20.0)
	_check(off["adaptation"]["decision"] == AdaptiveDifficulty.SAME and gm.pending_adapt == 0 and off["next_reserve"] == 315, "with the option off a fast shift changes nothing (next reserve 315 s)")
	Rules.adaptive = true
	gm.free()


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
	await process_frame
	var gm: GameManager = main.gm
	_check(Rules.adaptive == main.save.adaptive and main.save.adaptive, "the option is on by default and the game uses it")
	# Win quickly through the real flow.
	for id in GameManager.SYSTEM_IDS:
		gm.repaired[id] = true
	gm.reserve = 300.0
	for pad in PuzzleValidators.reboot_answer(gm.puzzles["reboot"]):
		gm.press_reboot_pad(pad)
	gm.try_reboot()
	await process_frame
	var text := ""
	for label in main._modal_layer.find_children("*", "Label", true, false):
		text += (label as Label).text + "\n"
	_check(text.contains("ADAPTIVE DIFFICULTY: next shift HARDER") and text.contains("17% of the reserve") and text.contains("Next shift: 270 s"), "the win screen says the next shift will be harder, with the numbers behind it")
	_check(text.contains("harder") and text.contains("0 mistakes and 0 retries"), "and a plain sentence")
	main._next_shift()
	await process_frame
	_check(main._notice_label.text.contains("ADAPTED: HARDER") and main._notice_label.text.contains("A SECOND LASER GRID"), "the new shift's notice says it was adapted and that a second grid has arrived")
	_check((main._station["lasers"] as Array).size() == 2 and is_equal_approx(gm.reserve, 270.0), "and the station is built with it (two grids, 270 s)")
	# Settings: switching it off.
	main.save.adaptive = false
	main._apply_settings()
	_check(not Rules.adaptive, "switching it off in Settings reaches the rule")
	main.queue_free()
	await process_frame
	var again := await _new_main()
	again.save.adaptive = false
	again.save.save_settings()
	_check(not SaveManager.new(SAVE_PATH).adaptive, "the choice is saved")
	again.queue_free()
	await process_frame
	Rules.adaptive = true


func _remove_save() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS  " + label)
	else:
		print("FAIL  " + label)
		_failures += 1
