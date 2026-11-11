extends SceneTree
## Per-shift colour themes: they exist for every shift, are distinct, readable, repeat
## in a cycle, and a retry keeps the shift's theme.
## Run:  godot --headless --path . -s res://tests/test_theme.gd

const KEYS := ["name", "wall", "floor", "ceiling", "ambient", "fog", "background", "hub_light"]

var _failures: int = 0


func _initialize() -> void:
	var names := {}
	for shift in range(1, ShiftTheme.THEMES.size() + 1):
		var theme := ShiftTheme.for_shift(shift)
		var complete := true
		for key in KEYS:
			complete = complete and theme.has(key)
		_check(complete, "theme for shift %d has every field (%s)" % [shift, theme["name"]])
		names[theme["name"]] = true
		var wall: Color = theme["wall"]
		_check(wall.get_luminance() > 0.1 and wall.get_luminance() < 0.55, "'%s' walls are neither too dark nor too bright (%.2f)" % [theme["name"], wall.get_luminance()])
		_check((theme["floor"] as Color).get_luminance() < wall.get_luminance(), "'%s' floor is darker than its walls" % theme["name"])
	_check(names.size() == ShiftTheme.THEMES.size(), "every theme has its own name")

	_check(ShiftTheme.for_shift(1)["name"] == "MIDNIGHT", "shift 1 is MIDNIGHT")
	_check(ShiftTheme.for_shift(ShiftTheme.THEMES.size() + 1)["name"] == "MIDNIGHT", "themes repeat after the last one")
	_check(ShiftTheme.for_shift(0)["name"] == ShiftTheme.for_shift(ShiftTheme.THEMES.size())["name"], "an out-of-range shift number still gives a theme")
	_check(ShiftTheme.for_shift(2) == ShiftTheme.for_shift(2), "a shift always gets the same theme")

	# The builder uses the theme's colours.
	var world := Node3D.new()
	root.add_child(world)
	var theme := ShiftTheme.for_shift(3)
	StationBuilder.build(world, PuzzleGenerator.generate(1, 0), theme)
	var floor_body: StaticBody3D = world.get_node("CorridorFloor")
	var floor_color := ((floor_body.get_child(0) as MeshInstance3D).material_override as StandardMaterial3D).albedo_color
	_check(floor_color == theme["floor"], "the station floor uses the shift's theme colour")
	world.queue_free()

	# Through the real main scene: a retry keeps the theme, the next shift changes it.
	var save_path := "user://test_theme_save.cfg"
	SaveManager.new(save_path).mark_intro_seen()
	var main: Node = load("res://scenes/main.tscn").instantiate()
	main.save_path = save_path
	root.add_child(main)
	await process_frame
	main._start_new_game()
	await process_frame
	_check(main._theme["name"] == "MIDNIGHT", "the first shift is MIDNIGHT in the game")
	main._retry()
	await process_frame
	_check(main._theme["name"] == "MIDNIGHT", "a retry keeps the same theme")
	main._next_shift()
	await process_frame
	_check(main._theme["name"] == ShiftTheme.for_shift(2)["name"], "the next shift switches to its own theme")
	main.queue_free()
	await process_frame

	DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
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
