extends SceneTree
## The optional Cryo Bay: the room, the six pods, the four log terminals, the pods' glow, the
## log panel (it pauses and frees the player's input again), the saved "logs read" progress,
## and that none of it touches the rules.
## Run:  godot --headless --path . -s res://tests/test_cryo.gd

const SAVE_PATH := "user://test_cryo_save.cfg"

var _failures: int = 0


func _initialize() -> void:
	_remove_save()
	_test_logs()
	_test_save()
	await _test_station()
	await _test_real_game()
	_remove_save()
	print("")
	if _failures == 0:
		print("ALL PASS")
		quit(0)
	else:
		print("%d FAILURE(S)" % _failures)
		quit(1)


func _test_logs() -> void:
	_check(CrewLogs.count() == 4 and CrewLogs.CREW.size() == 6, "four logs and six crew")
	var clean := true
	var fits := true
	for n in CrewLogs.count():
		var body := CrewLogs.text(n)
		fits = fits and body.length() > 150 and body.length() < 700 and CrewLogs.title(n).begins_with("LOG %d" % (n + 1))
		# A log is story only: no puzzle numbers, no formula, no answer.
		clean = clean and not body.contains(" MHz") and not body.contains("L/s") and not body.contains(" V ") and not body.contains("breaker") and body.find("400") == -1
	_check(fits, "every log has a numbered title and a readable length")
	_check(clean, "no log contains a puzzle number, formula or answer")
	var names := {}
	for crew in CrewLogs.CREW:
		names[crew["name"]] = true
	_check(names.size() == 6, "the six crew have different names")
	_check(CrewLogs.title(-5) == CrewLogs.title(0) and CrewLogs.text(99) == CrewLogs.text(3), "an out-of-range log number is clamped, never a crash")


func _test_save() -> void:
	var save := SaveManager.new(SAVE_PATH)
	_check(save.logs_read_count() == 0, "a new save has read no logs")
	save.mark_log_read(2)
	save.mark_log_read(2)
	save.mark_log_read(4)
	save.mark_log_read(0)
	save.mark_log_read(5)
	_check(save.logs_read_count() == 2, "reading a log twice counts once, and invalid numbers are ignored")
	_check(SaveManager.new(SAVE_PATH).logs_read_count() == 2, "the logs read are remembered")
	_remove_save()


func _test_station() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var station := StationBuilder.build(world, PuzzleGenerator.generate(3, 0))
	var reboot_x := StationBuilder.X_WEST + 0.6
	_check(StationBuilder.CRYO_X < StationBuilder.BEDROOM_X - StationBuilder.ROOM_HALF_WIDTH and StationBuilder.CRYO_X - StationBuilder.ROOM_HALF_WIDTH > StationBuilder.X_WEST, "the Cryo Bay is west of the crew quarters, inside the corridor's west end")
	_check(reboot_x < StationBuilder.CRYO_X - StationBuilder.ROOM_HALF_WIDTH, "the reboot terminal is beyond the Cryo Bay, so you pass its door on the way to reboot")
	_check(not (station["doors"] as Dictionary).has("cryo"), "the Cryo Bay has no door: it is never locked")
	var ids := (station["interactables"] as Array).map(func(i: Interactable) -> String: return i.id)
	var logs := ids.filter(func(id: String) -> bool: return id.begins_with("crew_log_"))
	_check(logs.size() == 4 and ids.has("crew_log_1") and ids.has("crew_log_4"), "four crew log terminals exist")
	_check((station["pods"] as Array).size() == 6, "six pods with a glow each")
	var all_red := true
	for glow in station["pods"]:
		all_red = all_red and (glow as StandardMaterial3D).albedo_color == Rules.COLOR_FAULT
	_check(all_red, "the pods start red while the station is broken")
	var texts: Array[String] = []
	for label in world.find_children("*", "Label3D", true, false):
		texts.append((label as Label3D).text)
	_check(texts.has("CRYO BAY") and texts.any(func(t: String) -> bool: return t.contains("CAPT. MARA OKAFOR")), "the doorway sign and the name plates are there")
	# The pods are solid: nobody walks through them.
	var solid := world.find_children("*", "StaticBody3D", true, false).filter(func(b: StaticBody3D) -> bool:
		if not (b.get_child(0) is MeshInstance3D):
			return false
		var mesh := (b.get_child(0) as MeshInstance3D).mesh as BoxMesh
		return mesh != null and mesh.size.is_equal_approx(Vector3(0.9, 0.6, 1.25)))
	_check(solid.size() == 6, "each pod has a solid base")
	var terminals_clear := true
	for id in logs:
		for item in station["interactables"]:
			if (item as Interactable).id == id:
				var tx := (item as Node3D).position.x
				terminals_clear = terminals_clear and absf(tx - StationBuilder.CRYO_X) < StationBuilder.ROOM_HALF_WIDTH - 0.5
	_check(terminals_clear, "the terminals are inside the room")
	world.free()
	await process_frame


func _test_real_game() -> void:
	SaveManager.new(SAVE_PATH).mark_intro_seen()
	var main: Node = load("res://scenes/main.tscn").instantiate()
	main.save_path = SAVE_PATH
	root.add_child(main)
	await process_frame
	main._start_new_game()
	await process_frame
	var gm: GameManager = main.gm
	# Reading a log pauses and then frees the input again.
	var reserve_before := gm.reserve
	for item in main._station["interactables"]:
		if (item as Interactable).id == "crew_log_3":
			main._on_interacted(item, null)
	_check(main._log_panel != null and paused and not main._player.input_enabled, "a log opens, pauses the game and freezes the player")
	_check(main.save.logs_read_count() == 1, "reading it is remembered")
	var shown := false
	for label in main._log_panel.find_children("*", "Label", true, false):
		if (label as Label).text.begins_with("LOG 3"):
			shown = true
	_check(shown, "the panel shows log 3")
	var escape := InputEventAction.new()
	escape.action = "pause_game"
	escape.pressed = true
	main._unhandled_input(escape)
	_check(main._log_panel == null and not paused and main._player.input_enabled, "Esc closes the log and returns control, not the pause menu")
	_check(is_equal_approx(gm.reserve, reserve_before) and gm.mistakes == 0 and gm.repaired_count() == 0, "reading a log changes nothing in the game")
	# Opening a log never stacks, and an invalid number is ignored.
	main._open_log(1)
	main._open_log(2)
	_check(main.save.logs_read_count() == 2 and main._log_panel != null, "a second log cannot open on top of the first (log 2 stays unread)")
	main._close_log()
	main._open_log(9)
	_check(main._log_panel == null, "an invalid log number opens nothing")
	# Closing paths: Retry and the menu clear an open log.
	main._open_log(1)
	main._retry()
	await process_frame
	_check(main._log_panel == null and not paused, "a retry closes an open log")
	# The pods follow the repairs.
	var pods: Array = main._station["pods"]
	_check((pods[0] as StandardMaterial3D).albedo_color == Rules.COLOR_FAULT, "after the retry the pods are red again")
	gm.repaired["power"] = true
	main._update_pods()
	var halfway := Rules.COLOR_FAULT.lerp(Rules.COLOR_CYAN, 0.25)
	_check((pods[0] as StandardMaterial3D).albedo_color.is_equal_approx(halfway), "one repair in four moves the pods a quarter of the way to cyan")
	for id in ["oxygen", "comms", "cooling"]:
		gm.repaired[id] = true
	main._update_pods()
	_check((pods[5] as StandardMaterial3D).albedo_color.is_equal_approx(Rules.COLOR_CYAN), "all four repaired: the pods are cyan")
	main._go_to_menu()
	main._open_log(1)
	_check(main._log_panel == null, "no log opens from the menu")
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
