extends SceneTree
## Score formula tests (REQUIREMENTS.md section E / J1).
## Run:  godot --headless --path . -s res://tests/test_score.gd

var _failures: int = 0


func _initialize() -> void:
	_expect(ScoreManager.final_score(300.0, 0), 450, "reserve 300 s, 0 retries = 450")
	_expect(ScoreManager.final_score(120.0, 1), 310, "reserve 120 s, 1 retry = 310")
	_expect(ScoreManager.final_score(1.0, 3), 150, "reserve 1 s, 3 retries = 150")
	_expect(ScoreManager.final_score(480.0, 0), 540, "reserve 480 s, 0 retries = 540 (maximum)")

	_expect(ScoreManager.retry_penalty(0), 0, "no retries, no penalty")
	_expect(ScoreManager.retry_penalty(3), 150, "3 retries = 150 penalty")
	_expect(ScoreManager.retry_penalty(10), 150, "retry penalty caps at 150")
	_expect(ScoreManager.time_bonus(0.0), 0, "no reserve = no time bonus")
	_expect(ScoreManager.time_bonus(299.9), 149, "time bonus uses floor(reserve / 2)")
	_expect(ScoreManager.time_bonus(-5.0), 0, "time bonus never negative")

	var worst := ScoreManager.final_score(0.0, 99)
	_check(worst >= 0, "score is never negative (got %d)" % worst)

	var parts := ScoreManager.breakdown(300.0, 1)
	_expect(parts["base"], 300, "breakdown base")
	_expect(parts["time_bonus"], 150, "breakdown time bonus")
	_expect(parts["retry_penalty"], 50, "breakdown retry penalty")
	_expect(parts["final"], 400, "breakdown final")

	print("")
	if _failures == 0:
		print("ALL PASS")
		quit(0)
	else:
		print("%d FAILURE(S)" % _failures)
		quit(1)


func _expect(actual: int, expected: int, label: String) -> void:
	_check(actual == expected, "%s (got %d)" % [label, actual])


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS  ", label)
	else:
		print("FAIL  ", label)
		_failures += 1
