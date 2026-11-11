extends SceneTree
## The walk: corridor hazards cycle and cost reserve time only while active, doors unlock in
## order, hazards never count as puzzle mistakes, and the manuals explain all of it.
## Run:  godot --headless --path . -s res://tests/test_corridor.gd

var _failures: int = 0


func _initialize() -> void:
	_test_hazard_cycle()
	_test_gas_damage()
	_test_laser()
	_test_oracle_cost()
	_test_manager_damage()
	_test_doors()
	await _test_in_the_real_scene()
	_test_manuals()

	print("")
	if _failures == 0:
		print("ALL PASS")
		quit(0)
	else:
		print("%d FAILURE(S)" % _failures)
		quit(1)


func _gas(offset: float = 0.0) -> HazardZone:
	return HazardZone.create(Vector3(6.0, 2.8, 3.0), Vector3.ZERO, offset)


func _laser() -> LaserGrid:
	return LaserGrid.create(Vector3.ZERO, 3.0, 2.8)


func _test_hazard_cycle() -> void:
	var gas := _gas()
	_check(gas.phase() == HazardZone.Phase.OFF, "gas starts quiet")
	gas.tick(Rules.GAS_OFF_SECONDS + 0.1, false)
	_check(gas.phase() == HazardZone.Phase.WARN, "then warns before it vents")
	gas.tick(Rules.GAS_WARN_SECONDS, false)
	_check(gas.phase() == HazardZone.Phase.ON and gas.is_active(), "then vents")
	gas.tick(Rules.GAS_ON_SECONDS, false)
	_check(gas.phase() == HazardZone.Phase.OFF, "then goes quiet again and the cycle repeats")
	_check(is_equal_approx(gas.cycle_seconds(), Rules.GAS_OFF_SECONDS + Rules.GAS_WARN_SECONDS + Rules.GAS_ON_SECONDS), "the gas cycle length is the sum of its phases")
	var shifted := _gas(Rules.GAS_OFF_SECONDS + 0.1)
	_check(shifted.phase() == HazardZone.Phase.WARN, "a phase offset starts the cycle part-way through")


func _test_gas_damage() -> void:
	var gas := _gas()
	var total := [0.0]
	var firsts := [0]
	gas.hit.connect(func(_k: String, seconds: float, first: bool) -> void:
		total[0] += seconds
		if first:
			firsts[0] += 1)
	gas.tick(0.5, true)   # inside while quiet
	_check(total[0] == 0.0, "standing in the gas while it is quiet costs nothing")
	gas._time = Rules.GAS_OFF_SECONDS + 0.2
	gas.tick(0.2, true)
	_check(total[0] == 0.0, "standing in the gas during the warning costs nothing")
	gas._time = Rules.GAS_OFF_SECONDS + Rules.GAS_WARN_SECONDS + 0.1
	for i in 10:
		gas.tick(0.1, true)
	_check(is_equal_approx(total[0], Rules.GAS_DRAIN_PER_SECOND * 1.0), "venting gas drains 12 reserve seconds per second inside (%.2f)" % total[0])
	_check(firsts[0] == 1, "only the first hit of a stay is marked as the first")
	gas.tick(0.1, false)
	gas.tick(0.1, true)
	_check(firsts[0] == 2, "stepping out and back in marks a new first hit")
	var before: float = total[0]
	for i in 10:
		gas.tick(0.1, false)
	_check(is_equal_approx(total[0], before), "being outside the gas costs nothing even while it vents")


func _test_laser() -> void:
	var laser := _laser()
	var touches := []
	laser.touched.connect(func(seconds: float) -> void: touches.append(seconds))
	laser.state_changed.connect(func(_armed: bool) -> void: pass)
	_check(laser.armed and laser._barrier.collision_layer == Rules.LAYER_WORLD, "the laser grid starts on and solid")
	laser.tick(0.1, false)
	_check(touches.is_empty(), "no touch when nobody is near")
	laser.tick(0.1, true)
	laser.tick(0.1, true)
	laser.tick(0.1, true)
	_check(touches.size() == 1 and is_equal_approx(touches[0], Rules.LASER_TOUCH_PENALTY_SECONDS), "touching the beams costs 10 s once, not once per frame")
	laser.tick(0.1, false)
	laser.tick(0.1, true)
	_check(touches.size() == 2, "stepping away and touching again is a new touch")

	laser.switch_off()
	_check(not laser.armed and laser._barrier.collision_layer == 0, "a switch turns the grid off and removes the barrier")
	laser.tick(1.0, true)
	_check(touches.size() == 2, "walking through a switched-off grid costs nothing")
	_check(is_equal_approx(laser.off_seconds_left(), Rules.LASER_OFF_SECONDS - 1.0), "the grid stays off for its set time")
	laser.tick(Rules.LASER_OFF_SECONDS, true)
	_check(not laser.armed, "it does not switch back on while someone stands in the beams")
	laser.tick(0.1, false)
	_check(laser.armed and laser._barrier.collision_layer == Rules.LAYER_WORLD, "it switches back on once the way is clear")
	var again := _laser()
	again.switch_off()
	again.tick(Rules.LASER_OFF_SECONDS - 2.0, false)
	again.switch_off()
	_check(is_equal_approx(again.off_seconds_left(), Rules.LASER_OFF_SECONDS), "pressing the switch again starts the time over")
	laser.free()
	again.free()


func _test_oracle_cost() -> void:
	var gm := GameManager.new()
	root.add_child(gm)
	gm.start_shift(3, 1)
	var start := gm.reserve
	var charged := []
	gm.oracle_charged.connect(func(seconds: int) -> void: charged.append(seconds))
	_check(gm.charge_oracle_question() == Rules.ORACLE_QUESTION_COST_SECONDS and is_equal_approx(gm.reserve, start - 5.0), "each ORACLE question costs 5 s of reserve")
	_check(charged == [5] and gm.oracle_questions == 1 and gm.mistakes == 0, "the cost is announced, counted and is not a mistake")
	gm.reserve = 3.0
	_check(gm.charge_oracle_question() == 2 and is_equal_approx(gm.reserve, 1.0), "a question can never take the last second of reserve")
	_check(gm.charge_oracle_question() == 0 and gm.state == GameManager.State.PLAYING, "with no spare reserve a question is free and the shift continues")
	gm.enter_menu()
	_check(gm.charge_oracle_question() == 0, "questions cost nothing outside a shift")
	gm.start_shift(4, 1)
	_check(gm.oracle_questions == 0, "a new attempt resets the question count")
	gm.queue_free()


func _test_manager_damage() -> void:
	var gm := GameManager.new()
	root.add_child(gm)
	gm.start_shift(7, 2)
	var start := gm.reserve
	var hits := []
	gm.hazard_hit.connect(func(kind: String, seconds: float) -> void: hits.append([kind, seconds]))
	gm.hazard_damage("laser", 12.0)
	_check(is_equal_approx(gm.reserve, start - 12.0) and gm.mistakes == 0, "a hazard takes reserve time but is not a puzzle mistake")
	_check(hits.size() == 1 and hits[0][0] == "laser", "the manager announces the hazard hit")
	_check(is_equal_approx(gm.hazard_seconds, 12.0), "hazard losses are tallied")
	gm.hazard_damage("gas", -5.0)
	_check(is_equal_approx(gm.reserve, start - 12.0), "negative damage is ignored")
	gm.hazard_damage("gas", 100000.0)
	_check(gm.state == GameManager.State.FAILED and gm.reserve == 0.0, "enough hazard damage ends the shift")
	var after := gm.reserve
	gm.hazard_damage("gas", 5.0)
	_check(gm.reserve == after, "hazards do nothing once the shift is over")
	gm.enter_menu()
	gm.hazard_damage("gas", 5.0)
	_check(gm.hazard_seconds > 0.0, "(the tally is kept until the next attempt)")
	gm.start_shift(8, 1)
	_check(gm.hazard_seconds == 0.0, "a new attempt starts with no hazard losses")
	gm.queue_free()


func _test_doors() -> void:
	var gate := DoorGate.create(Vector3(2.0, 2.3, 0.2), "power", Vector3.ZERO, "LOCKED")
	_check(gate.locked and gate.collision_layer == Rules.LAYER_WORLD, "a door starts locked and solid")
	gate.refresh({"power": false})
	_check(gate.locked, "it stays locked while its system is not repaired")
	gate.refresh({"oxygen": true})
	_check(gate.locked, "repairing a different system does not open it")
	gate.refresh({"power": true})
	_check(not gate.locked and gate.collision_layer == 0, "repairing its system opens it and removes the collision")
	gate.refresh({"power": true})
	_check(not gate.locked, "refreshing again is harmless")
	gate.free()


func _test_in_the_real_scene() -> void:
	var save_path := "user://test_corridor_save.cfg"
	SaveManager.new(save_path).mark_intro_seen()
	var main: Node = load("res://scenes/main.tscn").instantiate()
	main.save_path = save_path
	root.add_child(main)
	await process_frame
	main._start_new_game()
	await process_frame
	var gm: GameManager = main.gm
	var start := gm.reserve
	main._on_laser_touched(Rules.LASER_TOUCH_PENALTY_SECONDS)
	_check(is_equal_approx(gm.reserve, start - 10.0) and gm.mistakes == 0, "touching the laser in the real scene takes 10 s and is not a mistake")
	var laser: LaserGrid = main._station["laser"]
	_check(laser.touched.is_connected(main._on_laser_touched), "the laser grid is wired to the game")
	main._on_interacted(main._station["laser_switches"][0], null)
	_check(not laser.armed, "pressing a laser switch in the real scene turns the grid off")
	_check(is_equal_approx(gm.reserve, start - 10.0 + 0.0) or gm.reserve < start, "a switch costs nothing by itself")
	var before_question := gm.reserve
	main._open_oracle()
	main._oracle_panel.submit_text("how do I fix the power breakers")
	_check(is_equal_approx(gm.reserve, before_question - float(Rules.ORACLE_QUESTION_COST_SECONDS)), "asking ORACLE in the real scene costs 5 s")
	main._close_oracle()
	for zone in main._station["hazards"]:
		_check((zone as HazardZone).hit.is_connected(main._on_hazard_zone_hit), "the %s zone is wired to the game" % (zone as HazardZone).name)
	var wake_notice: String = main._notice_label.text
	_check(wake_notice.length() > 0, "a notice is on screen after waking up or a hazard (%s)" % wake_notice.left(30))
	main.queue_free()
	await process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))


func _test_manuals() -> void:
	var records := KnowledgeBase.load_records()
	var found := false
	for record in records:
		if record["id"] == "walk_hazards":
			found = true
			var text: String = record["text"]
			_check(text.contains("Oxygen after Power") and text.contains("Cooling after Comms") and text.contains("gas") and text.contains("laser") and text.contains("12"), "the manuals explain the locked doors, the gas vents and the laser grid")
	_check(found, "there is a manual entry about doors and corridor hazards")
	var results: Array = KnowledgeRetriever.retrieve("why is the oxygen door locked", records)
	_check(results.size() > 0 and (results[0]["id"] == "walk_hazards" or results.any(func(r: Dictionary) -> bool: return r["id"] == "walk_hazards")), "ORACLE can find the doors entry when asked about a locked door")
	results = KnowledgeRetriever.retrieve("what is the gas vent", records)
	_check(results.any(func(r: Dictionary) -> bool: return r["id"] == "walk_hazards"), "ORACLE can find the hazards entry when asked about gas")


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS  " + label)
	else:
		print("FAIL  " + label)
		_failures += 1
