extends SceneTree
## Puzzle generation, validators, penalties and win/fail rules (REQUIREMENTS.md J1).
## Run:  godot --headless --path . -s res://tests/test_puzzles.gd

var _failures: int = 0


func _initialize() -> void:
	_test_generation_is_valid()
	_test_each_puzzle_has_one_answer()
	_test_determinism_and_reroll()
	_test_penalties()
	_test_full_solve_and_reboot()
	_test_fail_state()
	_test_retry_rules()

	print("")
	if _failures == 0:
		print("ALL PASS")
		quit(0)
	else:
		print("%d FAILURE(S)" % _failures)
		quit(1)


func _test_generation_is_valid() -> void:
	var ok := true
	for seed_value in 100:
		for attempt in 3:
			var p := PuzzleGenerator.generate(seed_value, attempt)
			var ratings: Array = p["power"]["ratings"]
			var distinct := {}
			for r in ratings:
				distinct[r] = true
				if not Rules.BREAKER_RATINGS.has(r):
					ok = false
			if ratings.size() != Rules.BREAKER_COUNT or distinct.size() != Rules.BREAKER_COUNT:
				ok = false
			if not ["RESTORE", "SHED"].has(p["power"]["mode"]):
				ok = false
			if not Rules.OXYGEN_MODES.has(p["oxygen"]["mode"]):
				ok = false
			if not Rules.PROTOCOLS.has(p["protocol"]) or p["power"]["protocol"] != p["protocol"] \
					or p["oxygen"]["protocol"] != p["protocol"] or p["comms"]["protocol"] != p["protocol"]:
				ok = false
			var lit: int = p["comms"]["lit"]
			if lit < Rules.BEACON_LIT_MIN or lit > Rules.BEACON_LIT_MAX:
				ok = false
	_check(ok, "100 seeds x 3 attempts generate valid parameters")
	var seen_protocols := {}
	for seed_value in 100:
		seen_protocols[PuzzleGenerator.generate(seed_value, 0)["protocol"]] = true
	_check(seen_protocols.has("A") and seen_protocols.has("B"), "both protocols occur across 100 seeds")


func _test_each_puzzle_has_one_answer() -> void:
	var ok_power := true
	var ok_oxygen := true
	var ok_comms := true
	var permutations := _permutations([0, 1, 2, 3])

	for seed_value in 30:
		var p := PuzzleGenerator.generate(seed_value, 0)

		# Power: exactly one breaker order is accepted.
		var accepted := 0
		for perm in permutations:
			var latched: Array = []
			var all_good := true
			for index in perm:
				if PuzzleValidators.is_next_breaker(p["power"], latched, index):
					latched.append(index)
				else:
					all_good = false
					break
			if all_good:
				accepted += 1
		if accepted != 1:
			ok_power = false

		# Oxygen: exactly one of the 11^3 valve combinations is accepted.
		var oxygen_hits := 0
		for a in range(0, 101, Rules.OXYGEN_STEP):
			for b in range(0, 101, Rules.OXYGEN_STEP):
				for c in range(0, 101, Rules.OXYGEN_STEP):
					if PuzzleValidators.oxygen_matches(p["oxygen"], [a, b, c]):
						oxygen_hits += 1
		if oxygen_hits != 1:
			ok_oxygen = false

		# Comms: exactly one reachable frequency is accepted.
		var comms_hits := 0
		for mhz in range(Rules.COMMS_MIN_MHZ, Rules.COMMS_MAX_MHZ + 1, Rules.COMMS_STEP_MHZ):
			if PuzzleValidators.comms_matches(p["comms"], mhz):
				comms_hits += 1
		if comms_hits != 1:
			ok_comms = false

	_check(ok_power, "power: exactly one accepted breaker order (30 seeds)")
	_check(ok_oxygen, "oxygen: exactly one accepted valve setting (30 seeds)")
	_check(ok_comms, "comms: exactly one accepted frequency (30 seeds)")

	# Spot-check the rules against hand-built cases.
	var restore := {"ratings": [240, 120, 480, 208], "mode": "RESTORE"}
	var shed := {"ratings": [240, 120, 480, 208], "mode": "SHED"}
	_check(PuzzleValidators.power_order(restore) == [1, 3, 0, 2], "RESTORE flips lowest to highest rating")
	_check(PuzzleValidators.power_order(shed) == [2, 0, 3, 1], "SHED flips highest to lowest rating")
	_check(PuzzleValidators.comms_target({"lit": 3}) == 160, "3 lit beacons -> 160 MHz")
	_check(PuzzleValidators.oxygen_target({"mode": "DAY"}) == [50, 60, 70], "DAY valve table is 50/60/70")

	# Protocol B changes all three rules.
	var restore_b := {"ratings": [240, 120, 480, 208], "mode": "RESTORE", "protocol": "B"}
	var shed_b := {"ratings": [240, 120, 480, 208], "mode": "SHED", "protocol": "B"}
	_check(PuzzleValidators.power_order(restore_b) == [2, 0, 3, 1], "protocol B RESTORE flips highest first")
	_check(PuzzleValidators.power_order(shed_b) == [1, 3, 0, 2], "protocol B SHED flips lowest first")
	_check(PuzzleValidators.oxygen_target({"mode": "DAY", "protocol": "B"}) == [60, 70, 80], "protocol B DAY valve table is 60/70/80")
	_check(PuzzleValidators.oxygen_target({"mode": "EMERGENCY", "protocol": "B"}) == [80, 90, 100], "protocol B EMERGENCY reaches 100")
	_check(PuzzleValidators.comms_target({"lit": 3, "protocol": "B"}) == 130, "protocol B: 3 lit beacons -> 130 MHz")
	_check(PuzzleValidators.comms_target({"lit": 5, "protocol": "B"}) == 150, "protocol B: 5 lit beacons -> 150 MHz")


func _test_determinism_and_reroll() -> void:
	var same := true
	var changed := 0
	for seed_value in 100:
		var a := PuzzleGenerator.generate(seed_value, 0)
		var b := PuzzleGenerator.generate(seed_value, 0)
		if a != b:
			same = false
		if PuzzleGenerator.generate(seed_value, 1) != a:
			changed += 1
	_check(same, "same (seed, attempt) gives identical parameters")
	_check(changed >= 90, "a different attempt changes the parameters for >= 90 of 100 seeds (%d)" % changed)


func _test_penalties() -> void:
	var gm := GameManager.new()
	gm.start_shift(7, 1)
	var order := PuzzleValidators.power_order(gm.puzzles["power"])
	var wrong: int = order[1]  # not the first breaker that must be flipped

	var result := gm.flip_breaker(wrong)
	_check(result == "surge", "wrong breaker causes a surge")
	_check(gm.mistakes == 1, "surge counts one mistake")
	_check(is_equal_approx(gm.reserve, 360.0 - 15.0), "surge costs 15 s of reserve (got %.1f)" % gm.reserve)
	_check(gm.breakers_latched.is_empty(), "surge resets the breakers")

	var before := gm.reserve
	_check(not gm.confirm_oxygen(), "wrong oxygen settings are rejected")
	_check(is_equal_approx(gm.reserve, before - 10.0), "wrong oxygen confirm costs 10 s")
	before = gm.reserve
	_check(not gm.transmit(), "wrong frequency is rejected")
	_check(is_equal_approx(gm.reserve, before - 10.0), "wrong transmit costs 10 s")
	_check(gm.mistakes == 3, "three mistakes counted")

	# Reserve never goes below zero.
	gm.reserve = 5.0
	gm.confirm_oxygen()
	_check(gm.reserve == 0.0, "reserve clamps at 0 (got %.1f)" % gm.reserve)
	_check(gm.state == GameManager.State.FAILED, "reserve reaching 0 fails the shift")
	gm.free()


func _test_full_solve_and_reboot() -> void:
	var gm := GameManager.new()
	gm.start_shift(11, 1)
	var results := {"won": false, "score": -1}
	gm.shift_won.connect(func(r: Dictionary) -> void:
		results["won"] = true
		results["score"] = r["final"])

	_check(not gm.try_reboot(), "reboot refused at 0/3 systems")

	for index in PuzzleValidators.power_order(gm.puzzles["power"]):
		gm.flip_breaker(index)
	_check(gm.repaired["power"], "correct breaker order repairs power")

	_check(not gm.try_reboot(), "reboot refused at 1/3 systems")

	var target: Array = PuzzleValidators.oxygen_target(gm.puzzles["oxygen"])
	for i in 3:
		gm.adjust_valve(i, int(target[i]) / Rules.OXYGEN_STEP)
	_check(gm.confirm_oxygen(), "correct valve settings repair oxygen")
	_check(not gm.try_reboot(), "reboot refused with systems still broken")

	var steps := (PuzzleValidators.comms_target(gm.puzzles["comms"]) - Rules.COMMS_MIN_MHZ) / Rules.COMMS_STEP_MHZ
	gm.adjust_tuner(steps)
	_check(gm.transmit(), "correct frequency repairs comms")
	_check(not gm.try_reboot(), "reboot refused at 3/4 systems")
	gm.adjust_coolant(PuzzleValidators.cooling_target(gm.puzzles["cooling"]))
	_check(gm.engage_cooling(), "correct coolant flow repairs cooling")
	_check(gm.mistakes == 0, "no mistakes in a clean solve")

	_check(gm.try_reboot(), "reboot works at 4/4 systems")
	_check(gm.state == GameManager.State.WON, "state is WON after reboot")
	_check(results["won"] and results["score"] == 480, "clean instant solve scores 480 (got %d)" % results["score"])
	_check(not gm.try_reboot(), "a second reboot is ignored")
	gm.free()


func _test_fail_state() -> void:
	var gm := GameManager.new()
	gm.start_shift(3, 1)
	var failed := {"count": 0}
	gm.shift_failed.connect(func() -> void: failed["count"] += 1)

	gm._process(1000.0)
	_check(gm.state == GameManager.State.PLAYING, "reserve does not run before the first movement")

	gm.begin_clock()
	gm._process(359.0)
	_check(gm.state == GameManager.State.PLAYING and gm.reserve > 0.0, "still playing with 1 s left")
	gm._process(2.0)
	_check(gm.state == GameManager.State.FAILED, "reserve at 0 fails the shift")
	_check(failed["count"] == 1, "fail signal fires exactly once")
	gm._process(5.0)
	_check(failed["count"] == 1, "no repeated fail signals")
	gm.free()


func _test_retry_rules() -> void:
	var gm := GameManager.new()
	gm.start_shift(21, 2)
	var first := gm.puzzles.duplicate(true)
	gm.begin_clock()
	gm._process(100.0)
	gm.flip_breaker(PuzzleValidators.power_order(gm.puzzles["power"])[0])

	gm.retry()
	_check(gm.seed_value == 21, "retry keeps the seed")
	_check(gm.retry_count == 1 and gm.attempt == 1, "retry increments retry count and attempt")
	_check(is_equal_approx(gm.reserve, float(Rules.reserve_for_shift(2))), "retry restores that shift's full reserve")
	_check(gm.repaired_count() == 0 and gm.mistakes == 0 and gm.breakers_latched.is_empty(), "retry resets progress")
	_check(not gm.clock_running, "retry waits for the first movement again")
	_check(gm.puzzles != first, "retry re-rolls the puzzle values")

	gm.retry()
	gm.start_shift(99, 3)
	_check(gm.retry_count == 0 and gm.attempt == 0 and gm.run_number == 3, "a new shift clears retries and bumps the run")
	gm.free()


func _permutations(items: Array) -> Array:
	if items.size() <= 1:
		return [items.duplicate()]
	var out: Array = []
	for i in items.size():
		var rest := items.duplicate()
		var head = rest.pop_at(i)
		for tail in _permutations(rest):
			out.append([head] + tail)
	return out


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS  ", label)
	else:
		print("FAIL  ", label)
		_failures += 1
