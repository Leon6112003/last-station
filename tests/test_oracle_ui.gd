extends SceneTree
## ORACLE in the real game: open with H, ask a question, pause behaviour,
## busy state, and closing. No network: a fake client stands in for Ollama.
## Run:  godot --headless --path . -s res://tests/test_oracle_ui.gd

const SAVE_PATH := "user://test_oracle_ui_save.cfg"

class FakeClient extends Node:
	signal reply(ok: bool, text: String)
	func ask(_messages: Array) -> bool:
		return true

var _failures: int = 0


func _initialize() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	SaveManager.new(SAVE_PATH).mark_intro_seen()

	var main: Node = load("res://scenes/main.tscn").instantiate()
	main.save_path = SAVE_PATH
	root.add_child(main)
	await process_frame
	var gm: GameManager = main.gm
	main.oracle.set_client(null)  # offline mode, fully deterministic
	main._start_new_game()
	await process_frame

	# Open with the H key.
	gm.begin_clock()
	_press_key(KEY_H)
	await process_frame
	await process_frame
	var panel: OraclePanel = main._oracle_panel
	_check(panel != null, "pressing H opens ORACLE")
	_check(paused and not main._input_free, "ORACLE pauses the game and takes player input")
	var reserve_before := gm.reserve
	for i in 10:
		await process_frame
	_check(is_equal_approx(gm.reserve, reserve_before), "the reserve is frozen while ORACLE is open")

	# Ask a question in Basic Manual Mode.
	var log_before := panel._log.get_child_count()
	_check(panel.submit_text("How do I fix the power breakers?"), "a question is accepted")
	await process_frame
	var texts: Array[String] = []
	for child in panel._log.get_children():
		texts.append((child as Label).text)
	var joined := "\n".join(texts)
	_check(panel._log.get_child_count() > log_before + 2, "the answer and its sources were added to the chat")
	_check(joined.contains("You: How do I fix the power breakers?"), "the question is shown")
	_check(joined.find("You: How do I fix the power breakers?") < joined.find("ORACLE: Protocol"), "the question is shown BEFORE its answer, even for instant exact answers")
	_check(joined.contains("[power_order]"), "the manual excerpt for power_order is shown with its id")
	_check(joined.contains("RESTORE"), "the excerpt text itself is shown")
	_check(panel._header.text == OracleLogic.HEADER_EXACT, "a rule question is labelled as an exact manual answer")
	_check(not panel._send.disabled, "Send is enabled again after an answer")

	# Markup typed by the player or returned by a model is shown literally.
	panel.submit_text("[b]bold[/b] [url=http://x]link[/url] power")
	await process_frame
	var found_literal := false
	for child in panel._log.get_children():
		if (child as Label).text.contains("[b]bold[/b]"):
			found_literal = true
	_check(found_literal, "BBCode in a question is shown as plain text")

	# Busy state with a model that is "thinking".
	var fake := FakeClient.new()
	root.add_child(fake)
	main.oracle.set_client(fake)
	panel.submit_text("how do I retry")
	_check(main.oracle.busy and panel._send.disabled, "Send is disabled while the model is thinking")
	_check(panel._status.text.contains("thinking"), "a thinking message is shown")
	_check(not panel.submit_text("another question"), "a second question is refused while busy")
	fake.reply.emit(true, "Hold R for one second to retry.")
	await process_frame
	_check(not main.oracle.busy and not panel._send.disabled and panel._status.text.is_empty(), "the UI recovers when the answer arrives")
	_check(panel._header.text == OracleLogic.HEADER_LOCAL, "the header says Local AI after a model answer")

	# While ORACLE is open the game keys do nothing.
	var retries := gm.retry_count
	Input.action_press("retry_level")
	await create_timer(1.3).timeout
	Input.action_release("retry_level")
	_check(gm.retry_count == retries, "holding R does nothing while ORACLE is open")
	_press_key(KEY_M)
	await process_frame
	_check(main._manuals == null, "M does not open the manuals while ORACLE is open")

	# Esc closes it (it also works while the text box has focus).
	_press_key(KEY_ESCAPE)
	await process_frame
	await process_frame
	_check(main._oracle_panel == null and not paused and main._input_free, "Esc closes ORACLE and resumes the game")
	_check(not main._paused, "closing ORACLE does not leave the pause menu open")

	# Reopen, then close with the button's signal.
	main._open_oracle()
	await process_frame
	main._oracle_panel.closed.emit()
	await process_frame
	_check(main._oracle_panel == null and not paused, "the Close button closes ORACLE")

	# Leaving for the menu closes it too.
	main._open_oracle()
	await process_frame
	main._go_to_menu()
	await process_frame
	_check(main._oracle_panel == null and not paused, "going to the Main Menu closes ORACLE")

	main.queue_free()
	fake.queue_free()
	await process_frame
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))

	print("")
	if _failures == 0:
		print("ALL PASS")
		quit(0)
	else:
		print("%d FAILURE(S)" % _failures)
		quit(1)


func _press_key(keycode: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.physical_keycode = keycode
		event.keycode = keycode
		event.pressed = pressed
		Input.parse_input_event(event)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS  ", label)
	else:
		print("FAIL  ", label)
		_failures += 1
