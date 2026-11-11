extends SceneTree
## The fourth system, Cooling: puzzle values, the formula for both protocols and both reactor
## states, the game rules (clamp, penalty, repair), the hint, ORACLE's exact answer, the manuals,
## and the room itself.
## Run:  godot --headless --path . -s res://tests/test_cooling.gd

var _failures: int = 0


func _initialize() -> void:
	_test_generation()
	_test_formula()
	_test_game_rules()
	_test_oracle()
	await _test_station()
	await _test_panel()
	print("")
	if _failures == 0:
		print("ALL PASS")
		quit(0)
	else:
		print("%d FAILURE(S)" % _failures)
		quit(1)


func _test_generation() -> void:
	var temps := {}
	var states := {}
	var valid := true
	var same_protocol := true
	for seed_value in 200:
		var p := PuzzleGenerator.generate(seed_value, 0)
		var cooling: Dictionary = p["cooling"]
		temps[cooling["temp"]] = true
		states[cooling["state"]] = true
		valid = valid and Rules.COOLING_TEMPS.has(int(cooling["temp"])) and Rules.COOLING_STATES.has(String(cooling["state"]))
		same_protocol = same_protocol and cooling["protocol"] == p["protocol"]
		var target := PuzzleValidators.cooling_target(cooling)
		valid = valid and target >= 0 and target <= Rules.COOLING_FLOW_MAX
	_check(valid, "200 seeds give a valid core temperature and reactor state, and a flow the panel can reach")
	_check(temps.size() == Rules.COOLING_TEMPS.size() and states.size() == 2, "every temperature and both reactor states occur")
	_check(same_protocol, "the cooling puzzle uses the shift's protocol")
	_check(PuzzleGenerator.generate(7, 0)["cooling"] == PuzzleGenerator.generate(7, 0)["cooling"], "the same seed gives the same cooling values")
	# The four older puzzles must not change for a given seed.
	var a := PuzzleGenerator.generate(3, 0)
	_check(a["power"]["ratings"].size() == 4 and Rules.PROTOCOLS.has(a["protocol"]), "the older puzzles are still generated as before")


func _test_formula() -> void:
	_check(PuzzleValidators.cooling_target({"temp": 560, "state": "NORMAL", "protocol": "A"}) == 8, "protocol A, 560 K, NORMAL: 8 L/s")
	_check(PuzzleValidators.cooling_target({"temp": 560, "state": "NORMAL", "protocol": "B"}) == 16, "protocol B, 560 K, NORMAL: 16 L/s")
	_check(PuzzleValidators.cooling_target({"temp": 560, "state": "SURGE", "protocol": "A"}) == 13, "protocol A, 560 K, SURGE: 13 L/s")
	_check(PuzzleValidators.cooling_target({"temp": 640, "state": "SURGE", "protocol": "B"}) == 29, "protocol B, 640 K, SURGE: 29 L/s (the largest)")
	_check(PuzzleValidators.cooling_target({"temp": 440, "state": "NORMAL", "protocol": "A"}) == 2, "protocol A, 440 K, NORMAL: 2 L/s (the smallest)")
	_check(Rules.COOLING_FLOW_MAX >= 29, "the panel can reach the largest flow")
	_check(PuzzleValidators.cooling_matches({"temp": 560, "state": "NORMAL", "protocol": "A"}, 8) and not PuzzleValidators.cooling_matches({"temp": 560, "state": "NORMAL", "protocol": "A"}, 9), "only the exact flow matches")


func _test_game_rules() -> void:
	var gm := GameManager.new()
	root.add_child(gm)
	gm.start_shift(21, 1)
	_check(Rules.SYSTEMS_TOTAL == 4 and GameManager.SYSTEM_IDS == ["power", "oxygen", "comms", "cooling"], "there are four systems, Cooling last")
	_check(gm.coolant_flow == 0 and not gm.repaired["cooling"], "a shift starts with the coolant flow at 0 and cooling broken")
	gm.adjust_coolant(-5)
	_check(gm.coolant_flow == 0, "the flow cannot go below 0")
	gm.adjust_coolant(500)
	_check(gm.coolant_flow == Rules.COOLING_FLOW_MAX, "the flow cannot go above %d" % Rules.COOLING_FLOW_MAX)
	var before := gm.reserve
	_check(not gm.engage_cooling() and is_equal_approx(gm.reserve, before - float(Rules.confirm_penalty())) and gm.mistakes == 1, "a wrong flow costs the confirm penalty and is counted as a mistake")
	gm.coolant_flow = 0
	gm.adjust_coolant(PuzzleValidators.cooling_target(gm.puzzles["cooling"]))
	_check(gm.engage_cooling() and gm.repaired["cooling"], "the right flow repairs cooling")
	gm.adjust_coolant(3)
	var flow_after := gm.coolant_flow
	_check(not gm.engage_cooling() and gm.coolant_flow == flow_after, "once repaired the panel does nothing more")
	_check(gm.repaired_count() == 1, "one system is repaired")
	gm.retry()
	_check(gm.coolant_flow == 0 and not gm.repaired["cooling"], "a retry resets the coolant flow and breaks cooling again")
	# Hints.
	gm.repaired = {"power": true, "oxygen": true, "comms": true, "cooling": false}
	var hint: Dictionary = gm.use_hint()
	var text := String(hint["text"])
	var protocol: String = gm.puzzles["protocol"]
	_check(hint["ok"] and text.begins_with("Next: COOLING") and text.contains("Protocol %s" % protocol), "the hint points at Cooling when it is next")
	var answer := PuzzleValidators.cooling_target(gm.puzzles["cooling"])
	_check(not text.contains("%d L/s" % answer) and not text.contains(str(gm.puzzles["cooling"]["temp"])), "the Cooling hint never contains the answer or the temperature")
	gm.free()


func _test_oracle() -> void:
	var records := KnowledgeBase.load_records()
	var results: Array = KnowledgeRetriever.retrieve("How do I set the coolant flow?", records)
	_check(not results.is_empty() and results[0]["id"] == "cooling_formula", "the coolant flow question finds the Cooling formula first")
	results = KnowledgeRetriever.retrieve("what does the cooling room do", records)
	_check(results.any(func(r: Dictionary) -> bool: return r["id"] in ["cooling_overview", "cooling_formula"]), "a question about the Cooling room finds its manuals")
	_check(OracleLogic.is_rule_question(KnowledgeRetriever.retrieve("what coolant flow do I set", records)), "the coolant flow is a rule question, answered in code")
	var question := "core temp 560 protocol B surge, what coolant flow?"
	var exact: Dictionary = OracleLogic.compose_exact(question, KnowledgeRetriever.retrieve(question, records))
	_check(exact["mode"] == "exact" and String(exact["answer"]).contains("21 L/s"), "ORACLE calculates the flow from the temperature you read (560 K, B, SURGE = 21)")
	question = "core temp 560 protocol A normal coolant flow"
	exact = OracleLogic.compose_exact(question, KnowledgeRetriever.retrieve(question, records))
	_check(String(exact["answer"]).contains("8 L/s") and not String(exact["answer"]).contains("Protocol B"), "it names only the protocol you gave (A, 560 K, NORMAL = 8)")
	question = "core temp 480 cooling flow"
	exact = OracleLogic.compose_exact(question, KnowledgeRetriever.retrieve(question, records))
	_check(String(exact["answer"]).contains("Protocol A") and String(exact["answer"]).contains("Protocol B"), "with no protocol named it shows both")
	var snapshot := OracleLogic.sanitize_snapshot({"systems_repaired": 4, "systems_total": 4, "reserve_seconds": 100, "mistakes": 0, "retry_count": 0, "run_number": 1, "best_score": 0})
	_check(snapshot["systems_total"] == 4 and snapshot["systems_repaired"] == 4, "the snapshot allows four systems")


func _test_station() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var station := StationBuilder.build(world, PuzzleGenerator.generate(5, 0))
	var doors: Dictionary = station["doors"]
	_check(doors.has("cooling") and (doors["cooling"] as DoorGate).locked and (doors["cooling"] as DoorGate).requires == "comms", "the Cooling door starts locked and needs Comms")
	_check(StationBuilder.ROOM_CENTERS_X["cooling"] > StationBuilder.ROOM_CENTERS_X["comms"] and StationBuilder.X_EAST > StationBuilder.ROOM_CENTERS_X["cooling"] + StationBuilder.ROOM_HALF_WIDTH, "the Cooling room is past Comms and inside the corridor's end wall")
	_check(station["consoles"].has("cooling") and (station["consoles"]["cooling"] as Interactable).id == "cooling_console", "the coolant console exists")
	var texts: Array[String] = []
	for label in world.find_children("*", "Label3D", true, false):
		texts.append((label as Label3D).text)
	var puzzle: Dictionary = PuzzleGenerator.generate(5, 0)["cooling"]
	_check(texts.has("CORE TEMP: %d K" % int(puzzle["temp"])) and texts.has("REACTOR: %s" % puzzle["state"]), "the room shows the core temperature and reactor state")
	_check((station["reactor"] as StandardMaterial3D).albedo_color != Rules.COLOR_CYAN, "the reactor core starts hot, not cyan")
	world.free()
	await process_frame


## The panel repeats the core temperature and reactor state, because it covers the wall display.
func _test_panel() -> void:
	var gm := GameManager.new()
	root.add_child(gm)
	gm.start_shift(21, 1)
	var panel := PuzzlePanel.create("cooling", gm)
	root.add_child(panel)
	await process_frame
	var cooling: Dictionary = gm.puzzles["cooling"]
	var found := false
	for label in panel.find_children("*", "Label", true, false):
		if (label as Label).text == "CORE TEMP %d K     REACTOR %s" % [int(cooling["temp"]), cooling["state"]]:
			found = true
	_check(found, "the coolant panel shows the core temperature and the reactor state")
	var buttons := panel.find_children("*", "Button", true, false).filter(func(b: Node) -> bool: return (b as Button).text == "ENGAGE COOLING")
	gm.coolant_flow = (PuzzleValidators.cooling_target(cooling) + 1) % (Rules.COOLING_FLOW_MAX + 1)
	(buttons[0] as Button).pressed.emit()
	var message := ""
	for label in panel.find_children("*", "Label", true, false):
		if (label as Label).text.begins_with("PUMP OVERLOAD"):
			message = (label as Label).text
	_check(message.contains("reactor state"), "a wrong flow tells the player to check the protocol and the reactor state")
	panel.free()
	gm.free()
	await process_frame


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS  " + label)
	else:
		print("FAIL  " + label)
		_failures += 1
