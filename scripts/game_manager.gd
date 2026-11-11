class_name GameManager
extends Node
## Authoritative game state for one shift: puzzles, reserve countdown,
## mistakes, repairs, win and fail. Only this class mutates that state.
## Nothing here touches rendering or UI; the world reacts to its signals.

enum State { MENU, PLAYING, WON, FAILED }

signal shift_started
signal reserve_changed(seconds: float)
signal system_repaired(system_id: String)
signal mistake_made(system_id: String, penalty_seconds: int)
signal shift_won(result: Dictionary)
signal shift_failed
signal hint_used(cost_seconds: int)

const SYSTEM_IDS: Array[String] = ["power", "oxygen", "comms"]

var state: State = State.MENU
var seed_value: int = 0
var run_number: int = 1
var attempt: int = 0
var retry_count: int = 0
var reserve: float = float(Rules.RESERVE_START_SECONDS)
var mistakes: int = 0
var hints_used: int = 0
var run_score: int = 0
var clock_running: bool = false
var repaired: Dictionary = {}
var puzzles: Dictionary = {}

# Live puzzle input state.
var breakers_latched: Array[int] = []
var oxygen_values: Array[int] = [0, 0, 0]
var tuner_mhz: int = Rules.COMMS_MIN_MHZ


# --- Shift lifecycle ----------------------------------------------------

## Leaves the current shift (Main Menu). Nothing counts while in the menu.
func enter_menu() -> void:
	state = State.MENU
	clock_running = false


## Starts a brand new shift: new seed, attempt 0, retries cleared.
func start_shift(new_seed: int, run: int) -> void:
	seed_value = new_seed
	run_number = run
	attempt = 0
	retry_count = 0
	if run <= 1:
		run_score = 0  # a new run starts from zero
	_reset_attempt()


## Retry: same seed and layout, puzzle values re-rolled, reserve restored.
func retry() -> void:
	attempt += 1
	retry_count += 1
	_reset_attempt()


func _reset_attempt() -> void:
	# Shift 1 is the guided shift: it always runs under protocol A.
	puzzles = PuzzleGenerator.generate(seed_value, attempt, "A" if run_number <= 1 else "")
	reserve = float(Rules.reserve_for_shift(run_number))
	mistakes = 0
	hints_used = 0
	clock_running = false
	repaired = {"power": false, "oxygen": false, "comms": false}
	breakers_latched.clear()
	oxygen_values = [0, 0, 0]
	tuner_mhz = Rules.COMMS_MIN_MHZ
	state = State.PLAYING
	shift_started.emit()
	reserve_changed.emit(reserve)


## The countdown starts on the first movement input.
func begin_clock() -> void:
	if state == State.PLAYING:
		clock_running = true


func _process(delta: float) -> void:
	if state != State.PLAYING or not clock_running:
		return
	reserve -= delta
	if reserve <= 0.0:
		_fail()
	else:
		reserve_changed.emit(reserve)


func repaired_count() -> int:
	var count := 0
	for id in SYSTEM_IDS:
		if repaired.get(id, false):
			count += 1
	return count


# --- Power: breakers -----------------------------------------------------

## Returns "ignored", "ok", "surge" or "repaired".
func flip_breaker(index: int) -> String:
	if state != State.PLAYING or repaired["power"] or breakers_latched.has(index):
		return "ignored"
	if PuzzleValidators.is_next_breaker(puzzles["power"], breakers_latched, index):
		breakers_latched.append(index)
		if breakers_latched.size() == Rules.BREAKER_COUNT:
			_mark_repaired("power")
			return "repaired"
		return "ok"
	breakers_latched.clear()
	_penalize("power", Rules.SURGE_PENALTY_SECONDS)
	return "surge"


# --- Oxygen: valves ------------------------------------------------------

func adjust_valve(index: int, steps: int) -> void:
	if state != State.PLAYING or repaired["oxygen"] or index < 0 or index >= oxygen_values.size():
		return
	oxygen_values[index] = clampi(oxygen_values[index] + steps * Rules.OXYGEN_STEP, 0, 100)


func confirm_oxygen() -> bool:
	if state != State.PLAYING or repaired["oxygen"]:
		return false
	if PuzzleValidators.oxygen_matches(puzzles["oxygen"], oxygen_values):
		_mark_repaired("oxygen")
		return true
	_penalize("oxygen", Rules.WRONG_CONFIRM_PENALTY_SECONDS)
	return false


# --- Comms: tuner --------------------------------------------------------

func adjust_tuner(steps: int) -> void:
	if state != State.PLAYING or repaired["comms"]:
		return
	tuner_mhz = clampi(tuner_mhz + steps * Rules.COMMS_STEP_MHZ, Rules.COMMS_MIN_MHZ, Rules.COMMS_MAX_MHZ)


func transmit() -> bool:
	if state != State.PLAYING or repaired["comms"]:
		return false
	if PuzzleValidators.comms_matches(puzzles["comms"], tuner_mhz):
		_mark_repaired("comms")
		return true
	_penalize("comms", Rules.WRONG_CONFIRM_PENALTY_SECONDS)
	return false


# --- Reboot / win --------------------------------------------------------

## Succeeds only at 3/3 systems. Freezes the clock and computes the score.
func try_reboot() -> bool:
	if state != State.PLAYING or repaired_count() < Rules.SYSTEMS_TOTAL:
		return false
	state = State.WON
	clock_running = false
	var result := ScoreManager.breakdown(reserve, retry_count)
	run_score += int(result["final"])
	result["run_total"] = run_score
	result["hints"] = hints_used
	result["next_reserve"] = Rules.reserve_for_shift(run_number + 1)
	result["reserve_remaining"] = int(floor(reserve))
	result["mistakes"] = mistakes
	result["retries"] = retry_count
	result["seed"] = seed_value
	result["run_number"] = run_number
	shift_won.emit(result)
	return true


# --- Hint (a code-computed diagnostic, never the model) -----------------------

## ORACLE's "Get a hint" button. Costs reserve time. It names the next system to
## repair and the rule version (protocol) that applies this shift. It does not give
## the answer: the player still has to read the room's panel. Returns
## {ok: bool, text: String, cost: int}.
func use_hint() -> Dictionary:
	if state != State.PLAYING:
		return {"ok": false, "text": "No hint is available right now.", "cost": 0}
	var next := ""
	for id in SYSTEM_IDS:
		if not repaired.get(id, false):
			next = id
			break
	if next.is_empty():
		return {"ok": true, "text": "All systems are repaired. Go to the hub and press E on the reboot terminal.", "cost": 0}
	if reserve <= float(Rules.HINT_COST_SECONDS):
		return {"ok": false, "text": "Not enough oxygen reserve left for a hint.", "cost": 0}
	reserve -= float(Rules.HINT_COST_SECONDS)
	hints_used += 1
	reserve_changed.emit(reserve)
	hint_used.emit(Rules.HINT_COST_SECONDS)
	return {"ok": true, "text": _hint_text(next), "cost": Rules.HINT_COST_SECONDS}


func _hint_text(system_id: String) -> String:
	var protocol: String = puzzles.get("protocol", "A")
	match system_id:
		"power":
			var restore_first := "lowest" if protocol == "A" else "highest"
			var shed_first := "highest" if protocol == "A" else "lowest"
			return "Next: POWER (left room). Protocol %s: in RESTORE mode flip the %s voltage first; in SHED mode flip the %s first. Read the LOAD MODE and the breaker voltages." % [protocol, restore_first, shed_first]
		"oxygen":
			var table: Dictionary = Rules.OXYGEN_TABLES[protocol]
			var rows: Array[String] = []
			for mode in Rules.OXYGEN_MODES:
				rows.append("%s %s" % [mode, ", ".join((table[mode] as Array).map(func(v: int) -> String: return str(v)))])
			return "Next: OXYGEN (middle room). Protocol %s valve table: %s. Read the STATION MODE on the wall." % [protocol, ". ".join(rows)]
		_:
			return "Next: COMMS (right room). Protocol %s: 100 MHz plus %d MHz for every lit beacon. Count the lit beacons." % [protocol, Rules.COMMS_PER_BEACON_MHZ[protocol]]


# --- Internals -----------------------------------------------------------

func _mark_repaired(system_id: String) -> void:
	repaired[system_id] = true
	system_repaired.emit(system_id)


func _penalize(system_id: String, seconds: int) -> void:
	mistakes += 1
	reserve = maxf(0.0, reserve - float(seconds))
	mistake_made.emit(system_id, seconds)
	reserve_changed.emit(reserve)
	if reserve <= 0.0:
		_fail()


func _fail() -> void:
	if state != State.PLAYING:
		return
	reserve = 0.0
	state = State.FAILED
	clock_running = false
	reserve_changed.emit(reserve)
	shift_failed.emit()
