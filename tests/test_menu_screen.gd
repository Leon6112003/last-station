extends SceneTree
## The animated main menu and its typed intro: the intro hides the buttons until it ends or is
## skipped, the buttons call what they were given, and nothing here touches game rules.
## Run:  godot --headless --path . -s res://tests/test_menu_screen.gd

var _failures: int = 0
var _calls: Array[String] = []


func _initialize() -> void:
	# Without the intro (tests, headless runs) the menu is usable at once.
	var plain := MenuScreen.create(func() -> void: _calls.append("play"), func() -> void: _calls.append("how"), func() -> void: _calls.append("quit"), false)
	root.add_child(plain)
	await process_frame
	_check(not plain.is_intro_active(), "no intro when it is switched off")
	var buttons := plain.find_children("*", "Button", true, false)
	_check(buttons.size() == 3 and (buttons[0] as Button).text == "Play" and (buttons[1] as Button).text == "How to Play" and (buttons[2] as Button).text == "Quit", "the menu has Play, How to Play and Quit")
	for button in buttons:
		(button as Button).pressed.emit()
	_check(_calls == ["play", "how", "quit"], "each button calls its own action")
	_check(plain.best_label != null, "there is a label for the best scores")
	plain.queue_free()
	await process_frame

	# With the intro: buttons hidden and the typed text runs; skipping shows the menu.
	var intro := MenuScreen.create(func() -> void: pass, func() -> void: pass, func() -> void: pass, true)
	root.add_child(intro)
	await process_frame
	var intro_buttons := intro.find_children("*", "Button", true, false)
	_check(intro.is_intro_active() and not (intro_buttons[0] as Button).is_visible_in_tree(), "during the intro the buttons are hidden")
	for i in 40:
		await process_frame
	var typed: Label = null
	for label in intro.find_children("*", "Label", true, false):
		if (label as Label).text.begins_with("DAY 412"):
			typed = label
	_check(typed != null, "the intro types its first line")
	intro.skip_intro()
	await process_frame
	_check(not intro.is_intro_active() and (intro_buttons[0] as Button).is_visible_in_tree(), "skipping the intro shows the menu")
	var key := InputEventKey.new()
	key.pressed = true
	key.keycode = KEY_SPACE
	intro._input(key)
	_check(not intro.is_intro_active(), "a key press after the intro does nothing harmful")
	intro.queue_free()

	# A second intro ends by itself.
	var timed := MenuScreen.create(func() -> void: pass, func() -> void: pass, func() -> void: pass, true)
	root.add_child(timed)
	await process_frame
	var key_press := InputEventKey.new()
	key_press.pressed = true
	key_press.keycode = KEY_A
	timed._input(key_press)
	_check(not timed.is_intro_active(), "any key skips the intro")
	timed.queue_free()
	await process_frame

	print("")
	if _failures == 0:
		print("ALL PASS")
		quit(0)
	else:
		print("%d FAILURE(S)" % _failures)
		quit(1)


func _check(ok: bool, message: String) -> void:
	if ok:
		print("PASS  " + message)
	else:
		print("FAIL  " + message)
		_failures += 1
