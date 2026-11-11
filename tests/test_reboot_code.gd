extends SceneTree
## The reboot code: a sequence of pads shown at the reboot terminal. Protocol A: the same
## order, protocol B: reversed. The rules, the generator, the game manager, the panel, ORACLE's
## exact answer, and the real game.
## Run:  godot --headless --path . -s res://tests/test_reboot_code.gd

const SAVE_PATH := "user://test_reboot_save.cfg"

var _failures: int = 0


func _initialize() -> void:
	_test_rules()
	_test_generation()
	_test_game_manager()
	await _test_panel()
	_test_oracle()
	await _test_real_game()
	_remove_save()
	print("")
	if _failures == 0:
		print("ALL PASS")
		quit(0)
	else:
		print("%d FAILURE(S)" % _failures)
		quit(1)


func _repair_all(gm: GameManager) -> void:
	for id in GameManager.SYSTEM_IDS:
		gm.repaired[id] = true


func _test_rules() -> void:
	_check(Rules.sequence_length(1) == 4 and Rules.sequence_length(2) == 4 and Rules.sequence_length(3) == 5 and Rules.sequence_length(5) == 6 and Rules.sequence_length(40) == 6, "the sequence is 4 long, one longer every second shift, and never over 6")
	_check(Rules.sequence_length(0) == 4, "shift 0 is treated as shift 1")
	Rules.level = Rules.LEVEL_ENGINEER
	_check(Rules.replay_cost() == 10, "showing it again costs half a hint (10 s on Engineer)")
	Rules.level = Rules.LEVEL_ROOKIE
	_check(Rules.replay_cost() == 5, "5 s on Rookie")
	Rules.level = Rules.LEVEL_SURVIVOR
	_check(Rules.replay_cost() == 20, "20 s on Survivor")
	Rules.level = Rules.LEVEL_ENGINEER
	_check(Rules.SEQ_PAD_COUNT == 4 and Rules.SEQ_PAD_NAMES == ["A", "B", "C", "D"], "four pads named A to D")


func _test_generation() -> void:
	var valid := true
	var seen_pads := {}
	for seed_value in 100:
		var p := PuzzleGenerator.generate(seed_value, 0)
		var sequence: Array = p["reboot"]["sequence"]
		valid = valid and sequence.size() == 4 and p["reboot"]["protocol"] == p["protocol"]
		for pad in sequence:
			valid = valid and int(pad) >= 0 and int(pad) < Rules.SEQ_PAD_COUNT
			seen_pads[int(pad)] = true
	_check(valid and seen_pads.size() == 4, "100 seeds give a valid 4-pad sequence that uses every pad")
	_check(PuzzleGenerator.generate(5, 0)["reboot"] == PuzzleGenerator.generate(5, 0)["reboot"], "the same seed gives the same sequence")
	var changed := 0
	for seed_value in 50:
		if PuzzleGenerator.generate(seed_value, 0)["reboot"]["sequence"] != PuzzleGenerator.generate(seed_value, 1)["reboot"]["sequence"]:
			changed += 1
	_check(changed >= 40, "a retry re-rolls the sequence (%d of 50)" % changed)
	_check((PuzzleGenerator.generate(9, 0, "", 5)["reboot"]["sequence"] as Array).size() == 6, "a later shift generates a longer sequence")
	var older := PuzzleGenerator.generate(11, 0)
	var with_run := PuzzleGenerator.generate(11, 0, "", 3)
	_check(older["power"] == with_run["power"] and older["oxygen"] == with_run["oxygen"] and older["comms"] == with_run["comms"] and older["cooling"] == with_run["cooling"], "the other four puzzles do not change for a seed")
	var a := PuzzleValidators.reboot_answer({"sequence": [0, 2, 1, 3], "protocol": "A"})
	var b := PuzzleValidators.reboot_answer({"sequence": [0, 2, 1, 3], "protocol": "B"})
	_check(a == [0, 2, 1, 3] and b == [3, 1, 2, 0], "protocol A repeats the sequence, protocol B reverses it")


func _test_game_manager() -> void:
	var gm := GameManager.new()
	root.add_child(gm)
	gm.start_shift(31, 1)
	var answer := PuzzleValidators.reboot_answer(gm.puzzles["reboot"])
	_check(gm.press_reboot_pad(answer[0]) == "ignored" and gm.reboot_progress.is_empty(), "the code cannot be entered before all four systems are repaired")
	_check(gm.request_sequence_view() == -1, "nor can the sequence be shown")
	_repair_all(gm)
	_check(not gm.try_reboot(), "rebooting needs the code even with every system repaired")
	_check(gm.press_reboot_pad(-1) == "ignored" and gm.press_reboot_pad(9) == "ignored", "a pad that does not exist is ignored")
	var wrong := (answer[0] + 1) % Rules.SEQ_PAD_COUNT
	var reserve_before := gm.reserve
	_check(gm.press_reboot_pad(wrong) == "wrong" and is_equal_approx(gm.reserve, reserve_before - float(Rules.confirm_penalty())) and gm.mistakes == 1, "a wrong pad costs the confirm penalty and counts as a mistake")
	_check(gm.press_reboot_pad(answer[0]) == "ok" and gm.reboot_progress.size() == 1, "a right pad is accepted")
	gm.press_reboot_pad((answer[1] + 1) % Rules.SEQ_PAD_COUNT)
	_check(gm.reboot_progress.is_empty() and gm.mistakes == 2, "a wrong pad later in the code starts it again")
	for i in answer.size() - 1:
		_check(gm.press_reboot_pad(answer[i]) == "ok", "pad %d of the code is accepted" % (i + 1))
	_check(not gm.reboot_code_done and not gm.try_reboot(), "one pad short is not enough")
	_check(gm.press_reboot_pad(answer[answer.size() - 1]) == "done" and gm.reboot_code_done, "the last pad completes the code")
	_check(gm.press_reboot_pad(0) == "ignored", "no more pads after the code is done")
	_check(gm.try_reboot() and gm.state == GameManager.State.WON, "now the station can reboot")
	# Showing the sequence.
	gm.start_shift(32, 1)
	_repair_all(gm)
	var before := gm.reserve
	_check(gm.request_sequence_view() == 0 and is_equal_approx(gm.reserve, before), "the first showing is free")
	_check(gm.request_sequence_view() == Rules.replay_cost() and is_equal_approx(gm.reserve, before - float(Rules.replay_cost())) and gm.reboot_paid_views == 1, "showing it again costs half a hint")
	gm.reserve = float(Rules.replay_cost())
	var kept := gm.reserve
	_check(gm.request_sequence_view() == -1 and gm.reserve == kept, "it is refused, and not charged, when the reserve is too low")
	gm.retry()
	_check(not gm.reboot_free_view_used and gm.reboot_progress.is_empty() and not gm.reboot_code_done and gm.reboot_paid_views == 0, "a retry resets the code, the free showing and the count")
	gm.free()


func _test_panel() -> void:
	var gm := GameManager.new()
	root.add_child(gm)
	gm.start_shift(33, 1)
	_repair_all(gm)
	var panel := PuzzlePanel.create("reboot", gm)
	panel.instant = false
	root.add_child(panel)
	await process_frame
	await process_frame
	_check(gm.reboot_free_view_used and panel.is_showing(), "opening the panel starts the free showing by itself")
	var pads := panel.find_children("*", "Button", true, false).filter(func(b: Node) -> bool: return (b as Button).text in Rules.SEQ_PAD_NAMES)
	_check(pads.size() == 4 and (pads[0] as Button).text == "A" and (pads[3] as Button).text == "D", "four pads labelled A to D (letters as well as colours)")
	_check((pads[0] as Button).disabled, "the pads cannot be pressed while the sequence is shown")
	var colours := {}
	for i in 4:
		colours[PuzzlePanel.PAD_COLORS[i]] = true
	_check(colours.size() == 4, "each pad has its own colour")
	panel._on_pad(0)
	_check(gm.reboot_progress.is_empty(), "a press during the showing is ignored")
	panel.finish_showing()
	_check(not panel.is_showing() and not (pads[0] as Button).disabled, "when the showing ends the pads can be pressed")
	var answer := PuzzleValidators.reboot_answer(gm.puzzles["reboot"])
	panel._on_pad((answer[0] + 1) % 4)
	_check(panel._message.text.begins_with("WRONG CODE") and panel.is_showing() and gm.mistakes == 1, "a wrong pad says WRONG CODE and shows the sequence again")
	panel.finish_showing()
	var show_button: Button = panel.find_children("*", "Button", true, false).filter(func(b: Node) -> bool: return (b as Button).text.begins_with("SHOW SEQUENCE"))[0]
	_check(show_button.text.contains("AGAIN") and show_button.text.contains("-%d s" % Rules.replay_cost()), "after the free showing the button names its price")
	var reserve_before := gm.reserve
	show_button.pressed.emit()
	_check(panel.is_showing() and is_equal_approx(gm.reserve, reserve_before - float(Rules.replay_cost())), "showing it again costs reserve")
	panel.finish_showing()
	var solved := [0]
	panel.solved.connect(func() -> void: solved[0] += 1)
	for pad in answer:
		panel._on_pad(pad)
	_check(solved[0] == 1 and gm.reboot_code_done, "entering the whole code emits solved once")
	_check(panel._progress_label.text == "ENTERED %d / %d" % [answer.size(), answer.size()], "the progress line counts the pads entered")
	panel.free()
	# Instant mode (used in tests) does not animate.
	var gm2 := GameManager.new()
	root.add_child(gm2)
	gm2.start_shift(34, 1)
	_repair_all(gm2)
	var fast := PuzzlePanel.create("reboot", gm2)
	fast.instant = true
	root.add_child(fast)
	await process_frame
	await process_frame
	_check(not fast.is_showing(), "in instant mode the sequence is over at once")
	fast.free()
	gm2.free()
	gm.free()
	await process_frame


func _test_oracle() -> void:
	var records := KnowledgeBase.load_records()
	var results: Array = KnowledgeRetriever.retrieve("how do I enter the reboot code sequence", records)
	_check(not results.is_empty() and results[0]["id"] == "reboot_code", "ORACLE finds the reboot code manual first")
	_check(OracleLogic.is_rule_question(results), "it is a rule question, answered in code")
	var exact: Dictionary = OracleLogic.compose_exact("reboot code sequence protocol B", KnowledgeRetriever.retrieve("reboot code sequence protocol B", records))
	_check(exact["mode"] == "exact" and String(exact["answer"]).contains("reverse"), "the exact answer for protocol B mentions reversing it")
	var gm := GameManager.new()
	root.add_child(gm)
	gm.start_shift(35, 1)
	_repair_all(gm)
	var hint: Dictionary = gm.use_hint()
	_check(String(hint["text"]).contains("sequence of pads") and String(hint["text"]).contains("same order"), "the free all-repaired hint explains the code rule for protocol A")
	var sequence: Array = gm.puzzles["reboot"]["sequence"]
	_check(not String(hint["text"]).contains(str(sequence)), "and never contains the sequence")
	gm.free()


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
	main._on_interacted(_item(main, "reboot_terminal"), null)
	_check(main._panel == null and main._notice_label.text.contains("MUST BE REPAIRED"), "before 4/4 the terminal only warns")
	_repair_all(gm)
	_check(main._coach_text().contains("code"), "the shift 1 guidance mentions the code")
	main._on_interacted(_item(main, "reboot_terminal"), null)
	await process_frame
	_check(main._panel != null and gm.state == GameManager.State.PLAYING, "at 4/4 the terminal opens the code panel, not the win screen")
	var reserve := gm.reserve
	main._close_panel()
	main._on_interacted(_item(main, "reboot_terminal"), null)
	await process_frame
	_check(is_equal_approx(gm.reserve, reserve) and gm.reboot_paid_views == 0, "closing and reopening the panel does not charge for another showing")
	main._panel.finish_showing()
	var mistakes_before := gm.mistakes
	var answer := PuzzleValidators.reboot_answer(gm.puzzles["reboot"])
	main._panel._on_pad((answer[0] + 1) % 4)
	_check(gm.mistakes == mistakes_before + 1 and main._notice_label.text.contains("WRONG CODE"), "a wrong pad shows a WRONG CODE notice")
	main._panel.finish_showing()
	for pad in answer:
		main._panel._on_pad(pad)
	await process_frame
	_check(gm.state == GameManager.State.WON and main._panel == null and main._modal_layer != null, "the right code closes the panel and wins the shift")
	main.queue_free()
	await process_frame


func _item(main: Node, id: String) -> Interactable:
	for item in main._station["interactables"]:
		if (item as Interactable).id == id:
			return item
	return null


func _remove_save() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS  " + label)
	else:
		print("FAIL  " + label)
		_failures += 1
