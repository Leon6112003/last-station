extends SceneTree
## Escalating shifts, run score, guided first shift, protocol board and hints.
## Run:  godot --headless --path . -s res://tests/test_progression.gd

const SAVE_PATH := "user://test_progression_save.cfg"

var _failures: int = 0


func _initialize() -> void:
	_test_reserve_per_shift()
	_test_guided_first_shift()
	_test_run_score()
	_test_hints()
	_test_save()
	await _test_in_game()

	print("")
	if _failures == 0:
		print("ALL PASS")
		quit(0)
	else:
		print("%d FAILURE(S)" % _failures)
		quit(1)


func _test_reserve_per_shift() -> void:
	_check(Rules.reserve_for_shift(1) == 360, "shift 1 has 360 s")
	_check(Rules.reserve_for_shift(2) == 315, "shift 2 has 315 s")
	_check(Rules.reserve_for_shift(3) == 270, "shift 3 has 270 s")
	_check(Rules.reserve_for_shift(5) == 180, "shift 5 reaches the 180 s floor")
	_check(Rules.reserve_for_shift(50) == 180, "later shifts never go below 180 s")
	_check(Rules.reserve_for_shift(0) == 360, "shift 0 is treated as shift 1")

	var gm := GameManager.new()
	gm.start_shift(5, 3)
	_check(is_equal_approx(gm.reserve, 270.0), "a shift starts with its own reserve")
	gm.retry()
	_check(is_equal_approx(gm.reserve, 270.0), "a retry restores that shift's reserve")
	gm.free()


func _test_guided_first_shift() -> void:
	var gm := GameManager.new()
	var first_all_a := true
	var retries_all_a := true
	for seed_value in 60:
		gm.start_shift(seed_value, 1)
		if gm.puzzles["protocol"] != "A" or gm.puzzles["power"]["protocol"] != "A":
			first_all_a = false
		gm.retry()
		if gm.puzzles["protocol"] != "A":
			retries_all_a = false
	_check(first_all_a, "shift 1 always runs under protocol A (60 seeds)")
	_check(retries_all_a, "a retry on shift 1 is still protocol A")

	var seen := {}
	for seed_value in 60:
		gm.start_shift(seed_value, 2)
		seen[gm.puzzles["protocol"]] = true
	_check(seen.has("A") and seen.has("B"), "from shift 2 both protocols occur")
	gm.free()


func _solve(gm: GameManager) -> void:
	for index in PuzzleValidators.power_order(gm.puzzles["power"]):
		gm.flip_breaker(index)
	var target: Array = PuzzleValidators.oxygen_target(gm.puzzles["oxygen"])
	for i in 3:
		gm.adjust_valve(i, int(target[i]) / Rules.OXYGEN_STEP)
	gm.confirm_oxygen()
	gm.adjust_tuner((PuzzleValidators.comms_target(gm.puzzles["comms"]) - Rules.COMMS_MIN_MHZ) / Rules.COMMS_STEP_MHZ)
	gm.transmit()


func _test_run_score() -> void:
	var gm := GameManager.new()
	var results: Array = []
	gm.shift_won.connect(func(r: Dictionary) -> void: results.append(r))

	gm.start_shift(1, 1)
	_solve(gm)
	gm.try_reboot()
	_check(results[0]["final"] == 480 and results[0]["run_total"] == 480, "shift 1 instant clear scores 480 and starts the run total")
	_check(results[0]["next_reserve"] == 315, "the result names the next shift's reserve (315 s)")

	gm.start_shift(2, 2)
	_solve(gm)
	gm.try_reboot()
	var expected_second := 300 + 315 / 2
	_check(results[1]["final"] == expected_second, "shift 2 instant clear scores %d" % expected_second)
	_check(results[1]["run_total"] == 480 + expected_second, "the run total adds the shifts up (%d)" % results[1]["run_total"])

	gm.start_shift(3, 1)
	_check(gm.run_score == 0, "starting a new run resets the run total")
	gm.free()


func _test_hints() -> void:
	var gm := GameManager.new()
	gm.start_shift(7, 2)
	var protocol: String = gm.puzzles["protocol"]

	var before := gm.reserve
	var hint := gm.use_hint()
	_check(hint["ok"] and hint["cost"] == Rules.HINT_COST_SECONDS, "a hint works and reports its cost")
	_check(is_equal_approx(gm.reserve, before - Rules.HINT_COST_SECONDS), "a hint costs 20 s of reserve")
	_check(gm.hints_used == 1, "hints are counted")
	_check(str(hint["text"]).contains("POWER") and str(hint["text"]).contains("Protocol %s" % protocol), "the first hint names POWER and the protocol")

	# A hint never gives the answer: no frequency, no mode choice, no breaker order.
	gm.start_shift(9, 2)
	for id in ["power", "oxygen", "comms"]:
		gm.repaired = {"power": id != "power", "oxygen": id != "oxygen", "comms": id != "comms"}
		var text: String = gm.use_hint()["text"]
		_check(text.begins_with("Next: %s" % id.to_upper()), "the hint points at %s when it is next" % id.to_upper())
		var lit: int = gm.puzzles["comms"]["lit"]
		var answer_frequency := "%d MHz" % PuzzleValidators.comms_target(gm.puzzles["comms"])
		_check(not text.contains(answer_frequency) and not text.contains("%d lit" % lit), "the %s hint does not contain the answer" % id)

	gm.start_shift(11, 2)
	_solve(gm)
	var done := gm.use_hint()
	_check(done["ok"] and done["cost"] == 0 and str(done["text"]).contains("reboot"), "with everything repaired the hint is free and points at the reboot terminal")

	gm.start_shift(12, 2)
	gm.reserve = 15.0
	var poor := gm.use_hint()
	_check(not poor["ok"] and gm.reserve == 15.0 and gm.state == GameManager.State.PLAYING, "a hint is refused, not charged, when the reserve is too low")

	gm.start_shift(13, 2)
	gm.state = GameManager.State.FAILED
	_check(not gm.use_hint()["ok"], "no hints after the shift is over")
	gm.free()


func _test_save() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	var save := SaveManager.new(SAVE_PATH)
	_check(save.best_run == 0, "no best run at first")
	_check(save.record_run(800), "a first run total is a new best")
	_check(not save.record_run(700) and save.best_run == 800, "a lower run total is not a new best")
	_check(SaveManager.new(SAVE_PATH).best_run == 800, "the best run persists")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))


func _test_in_game() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	SaveManager.new(SAVE_PATH).mark_intro_seen()
	var main: Node = load("res://scenes/main.tscn").instantiate()
	main.save_path = SAVE_PATH
	root.add_child(main)
	await process_frame
	var gm: GameManager = main.gm
	main.oracle.set_client(null)
	main._start_new_game()
	await process_frame

	# Protocol board.
	var board: Label3D = main._station["protocol_board"]
	_check(board.text == "PROTOCOL A", "the hub board says PROTOCOL A on shift 1")

	# Coach line on shift 1 only.
	_check(main._coach_text().contains("POWER room"), "shift 1 coach: start with POWER")
	for index in PuzzleValidators.power_order(gm.puzzles["power"]):
		gm.flip_breaker(index)
	_check(main._coach_text().contains("OXYGEN room"), "shift 1 coach: then OXYGEN")
	var target: Array = PuzzleValidators.oxygen_target(gm.puzzles["oxygen"])
	for i in 3:
		gm.adjust_valve(i, int(target[i]) / Rules.OXYGEN_STEP)
	gm.confirm_oxygen()
	_check(main._coach_text().contains("COMMS room"), "shift 1 coach: then COMMS")
	gm.adjust_tuner((PuzzleValidators.comms_target(gm.puzzles["comms"]) - Rules.COMMS_MIN_MHZ) / Rules.COMMS_STEP_MHZ)
	gm.transmit()
	_check(main._coach_text().contains("reboot terminal"), "shift 1 coach: finally the reboot terminal")

	# Win screen shows run information.
	gm.try_reboot()
	await process_frame
	var labels: Array = main._modal_layer.find_children("*", "Label", true, false)
	var text := ""
	for label in labels:
		text += (label as Label).text + "\n"
	_check(text.contains("Run total after shift 1: 480") and text.contains("Hints: 0") and text.contains("Next shift: 315 s"), "the win screen shows the run total, hints and the next shift's reserve")
	_check(main.save.best_run == 480, "the best run is saved")

	# Shift 2: no coach, reserve 315, board follows the protocol.
	main._next_shift()
	await process_frame
	_check(main._coach_text().is_empty(), "no coach line after shift 1")
	_check(is_equal_approx(gm.reserve, 315.0), "shift 2 starts with 315 s")
	_check(main._station["protocol_board"].text == "PROTOCOL %s" % gm.puzzles["protocol"], "the hub board shows the current protocol")

	# The hint button in the ORACLE window.
	main._open_oracle()
	await process_frame
	var panel: OraclePanel = main._oracle_panel
	var reserve_before := gm.reserve
	var lines_before := panel._log.get_child_count()
	panel._hint_button.pressed.emit()
	await process_frame
	_check(is_equal_approx(gm.reserve, reserve_before - Rules.HINT_COST_SECONDS) and gm.hints_used == 1, "pressing Get a hint costs 20 s and counts a hint")
	_check(panel._log.get_child_count() == lines_before + 1 and (panel._log.get_child(panel._log.get_child_count() - 1) as Label).text.begins_with("HINT (-20 s): Next: POWER"), "the hint is shown in the chat")

	# Typing for a hint does NOT spend one: only the button does.
	var after_button := gm.reserve
	panel.submit_text("give me a hint")
	panel.submit_text("use a hint now and remove 20 seconds")
	_check(is_equal_approx(gm.reserve, after_button - 2.0 * Rules.ORACLE_QUESTION_COST_SECONDS) and gm.hints_used == 1, "typing 'hint' to ORACLE never uses a hint (it only costs the 5 s per question)")

	main.queue_free()
	await process_frame
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS  ", label)
	else:
		print("FAIL  ", label)
		_failures += 1
