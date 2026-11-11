extends SceneTree
## Layout: every full-screen window must keep its buttons on screen, and the
## How to Play page must hide the menu behind it. A bug once pushed the Back
## button off the bottom of a 1280x720 window. Headless Godot ignores window
## size, so the game runs inside a SubViewport of the size being tested.
## Run:  godot --headless --path . -s res://tests/test_layout.gd

const SAVE_PATH := "user://test_layout_save.cfg"
const SIZES := [Vector2i(1280, 720), Vector2i(1024, 576), Vector2i(1920, 1080)]

var _failures: int = 0


func _initialize() -> void:
	for size in SIZES:
		await _test_size(size)
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))

	print("")
	if _failures == 0:
		print("ALL PASS")
		quit(0)
	else:
		print("%d FAILURE(S)" % _failures)
		quit(1)


func _test_size(size: Vector2i) -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	SaveManager.new(SAVE_PATH).mark_intro_seen()

	var viewport := SubViewport.new()
	viewport.size = size
	root.add_child(viewport)
	var main: Node = load("res://scenes/main.tscn").instantiate()
	main.save_path = SAVE_PATH
	viewport.add_child(main)
	await process_frame
	var gm: GameManager = main.gm
	var tag := "%dx%d" % [size.x, size.y]

	# How to Play, opened from the menu.
	main._show_how_to_play(false)
	await _settle()
	_buttons_inside(main, size, "%s: How to Play" % tag)
	_check(_modal_dim_alpha(main) >= 0.99, "%s: How to Play fully hides the menu behind it" % tag)
	main._close_modal()

	# First-launch intro card over the game.
	main._start_new_game()
	await process_frame
	main._show_how_to_play(true)
	await _settle()
	_buttons_inside(main, size, "%s: intro card" % tag)
	main._close_modal()

	# Pause menu.
	main._set_paused(true)
	await _settle()
	_buttons_inside_node(main._pause_overlay, size, "%s: pause menu" % tag)
	main._set_paused(false)

	# Win screen (the tallest one: 3 buttons and 12 lines of text).
	for index in PuzzleValidators.power_order(gm.puzzles["power"]):
		gm.flip_breaker(index)
	var target: Array = PuzzleValidators.oxygen_target(gm.puzzles["oxygen"])
	for i in 3:
		gm.adjust_valve(i, int(target[i]) / Rules.OXYGEN_STEP)
	gm.confirm_oxygen()
	gm.adjust_tuner((PuzzleValidators.comms_target(gm.puzzles["comms"]) - Rules.COMMS_MIN_MHZ) / Rules.COMMS_STEP_MHZ)
	gm.transmit()
	gm.try_reboot()
	await _settle()
	_buttons_inside(main, size, "%s: win screen" % tag)

	# Fail screen.
	main._next_shift()
	await process_frame
	gm.begin_clock()
	gm._process(1000.0)
	await _settle()
	_buttons_inside(main, size, "%s: fail screen" % tag)

	# Manuals and ORACLE panels.
	main._retry()
	await process_frame
	main._open_manuals()
	await _settle()
	_panel_inside(main._manuals, size, "%s: manuals panel" % tag)
	main._close_manuals()
	main._open_oracle()
	await _settle()
	_panel_inside(main._oracle_panel, size, "%s: ORACLE panel" % tag)
	main._close_oracle()

	# Main menu.
	main._go_to_menu()
	await _settle()
	_buttons_inside_node(main._menu_layer, size, "%s: main menu" % tag)

	viewport.queue_free()
	await process_frame


func _settle() -> void:
	await process_frame
	await process_frame
	await process_frame


func _buttons_inside(main: Node, size: Vector2i, label: String) -> void:
	if main._modal_layer == null:
		_check(false, "%s: a window is showing" % label)
		return
	_buttons_inside_node(main._modal_layer, size, label)


func _buttons_inside_node(node: Node, size: Vector2i, label: String) -> void:
	var buttons: Array = node.find_children("*", "Button", true, false)
	var ok := not buttons.is_empty()
	for button in buttons:
		var rect := (button as Button).get_global_rect()
		if rect.position.y < 0.0 or rect.end.y > size.y or rect.position.x < 0.0 or rect.end.x > size.x:
			ok = false
			print("      button '%s' is off screen: %s in %s" % [(button as Button).text, rect, size])
	_check(ok, "%s: every button is inside the window" % label)


func _panel_inside(panel: Control, size: Vector2i, label: String) -> void:
	var rect := panel.get_global_rect()
	var ok := rect.position.y >= 0.0 and rect.end.y <= size.y and rect.position.x >= 0.0 and rect.end.x <= size.x
	if not ok:
		print("      %s is %s in a window of %s" % [label, rect, size])
	_check(ok, "%s: the whole panel is inside the window" % label)


func _modal_dim_alpha(main: Node) -> float:
	var rects: Array = main._modal_layer.find_children("*", "ColorRect", true, false)
	return (rects[0] as ColorRect).color.a if not rects.is_empty() else 0.0


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS  ", label)
	else:
		print("FAIL  ", label)
		_failures += 1
