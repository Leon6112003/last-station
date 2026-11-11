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
signal hazard_hit(kind: String, seconds: float)
signal oracle_charged(seconds: int)

const SYSTEM_IDS: Array[String] = ["power", "oxygen", "comms", "cooling"]

var state: State = State.MENU
var seed_value: int = 0
var run_number: int = 1
var attempt: int = 0
var retry_count: int = 0
var reserve: float = float(Rules.reserve_start())
var mistakes: int = 0
var hints_used: int = 0
var hazard_seconds: float = 0.0   # reserve lost to corridor hazards this attempt
var oracle_questions: int = 0     # questions asked to ORACLE this attempt (each costs reserve)
var run_score: int = 0
var clock_running: bool = false
var repaired: Dictionary = {}
var puzzles: Dictionary = {}

# Live puzzle input state.
var breakers_latched: Array[int] = []
var oxygen_values: Array[int] = [0, 0, 0]
var tuner_mhz: int = Rules.COMMS_MIN_MHZ
var coolant_flow: int = 0
var reboot_progress: Array[int] = []   # the pads pressed so far for the reboot code
var reboot_code_done: bool = false     # the reboot code was entered correctly
## Adaptive difficulty (see AdaptiveDifficulty): the steps in force this shift, the steps decided for
## the next shift once this one is cleared, and the previous shift's ratio for smoothing.
var adapt_steps: int = 0
var pending_adapt: int = 0
var previous_ratio: float = -1.0
var second_gravity_new: bool = false   # this shift is the first with a second gravity zone
var _gravity_count_seen: int = 1
var reboot_free_view_used: bool = false   # the one free showing of the sequence has been used
var reboot_paid_views: int = 0         # times the sequence was shown again on request (each costs reserve)


# --- Shift lifecycle ----------------------------------------------------

## Leaves the current shift (Main Menu). Nothing counts while in the menu.
func enter_menu() -> void:
	state = State.MENU
	clock_running = false
	adapt_steps = 0   # the adaptation belongs to a run: the menu starts clean
	pending_adapt = 0
	previous_ratio = -1.0
	Rules.adapt = 0


## Starts a brand new shift: new seed, attempt 0, retries cleared.
func start_shift(new_seed: int, run: int) -> void:
	seed_value = new_seed
	run_number = run
	attempt = 0
	retry_count = 0
	if run <= 1:
		run_score = 0  # a new run starts from zero
		adapt_steps = 0
		pending_adapt = 0
		previous_ratio = -1.0
		_gravity_count_seen = 1
	else:
		adapt_steps = pending_adapt   # what the last cleared shift decided
	Rules.adapt = adapt_steps
	var gravitys := Rules.gravity_count(run)
	second_gravity_new = run > 1 and gravitys > _gravity_count_seen
	_gravity_count_seen = gravitys
	_reset_attempt()


## Retry: same seed and layout, puzzle values re-rolled, reserve restored.
func retry() -> void:
	attempt += 1
	retry_count += 1
	_reset_attempt()


func _reset_attempt() -> void:
	# Shift 1 is the guided shift: it always runs under protocol A.
	puzzles = PuzzleGenerator.generate(seed_value, attempt, "A" if run_number <= 1 else "", run_number)
	reserve = float(Rules.reserve_for_shift(run_number))
	mistakes = 0
	hints_used = 0
	hazard_seconds = 0.0
	oracle_questions = 0
	clock_running = false
	repaired = {"power": false, "oxygen": false, "comms": false, "cooling": false}
	breakers_latched.clear()
	oxygen_values = [0, 0, 0]
	tuner_mhz = Rules.COMMS_MIN_MHZ
	coolant_flow = 0
	reboot_progress.clear()
	reboot_code_done = false
	reboot_free_view_used = false
	reboot_paid_views = 0
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
	_penalize("power", Rules.surge_penalty())
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
	_penalize("oxygen", Rules.confirm_penalty())
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
	_penalize("comms", Rules.confirm_penalty())
	return false


# --- Cooling: coolant flow --------------------------------------------------

func adjust_coolant(steps: int) -> void:
	if state != State.PLAYING or repaired["cooling"]:
		return
	coolant_flow = clampi(coolant_flow + steps * Rules.COOLING_FLOW_STEP, 0, Rules.COOLING_FLOW_MAX)


func engage_cooling() -> bool:
	if state != State.PLAYING or repaired["cooling"]:
		return false
	if PuzzleValidators.cooling_matches(puzzles["cooling"], coolant_flow):
		_mark_repaired("cooling")
		return true
	_penalize("cooling", Rules.confirm_penalty())
	return false


# --- Reboot code: a sequence of pads ----------------------------------------------

## A pad was pressed. Returns "ignored", "ok", "wrong" or "done". Needs all systems repaired.
## A wrong pad costs the confirm penalty and starts the code again.
func press_reboot_pad(index: int) -> String:
	if state != State.PLAYING or reboot_code_done or repaired_count() < Rules.SYSTEMS_TOTAL or index < 0 or index >= Rules.SEQ_PAD_COUNT:
		return "ignored"
	var answer := PuzzleValidators.reboot_answer(puzzles["reboot"])
	if answer[reboot_progress.size()] != index:
		reboot_progress.clear()
		_penalize("reboot", Rules.confirm_penalty())
		return "wrong"
	reboot_progress.append(index)
	if reboot_progress.size() == answer.size():
		reboot_code_done = true
		return "done"
	return "ok"


## Asks for the sequence to be shown. The first showing of a shift is free, later ones cost
## Rules.replay_cost() of reserve. Returns the seconds charged, or -1 if refused (too little reserve).
func request_sequence_view() -> int:
	if state != State.PLAYING or repaired_count() < Rules.SYSTEMS_TOTAL or reboot_code_done:
		return -1
	if not reboot_free_view_used:
		reboot_free_view_used = true
		return 0
	var cost := Rules.replay_cost()
	if reserve <= float(cost):
		return -1
	reserve -= float(cost)
	reboot_paid_views += 1
	reserve_changed.emit(reserve)
	return cost


# --- Reboot / win --------------------------------------------------------

## Succeeds only with all systems repaired and the reboot code entered. Freezes the clock and computes the score.
func try_reboot() -> bool:
	if state != State.PLAYING or repaired_count() < Rules.SYSTEMS_TOTAL or not reboot_code_done:
		return false
	state = State.WON
	clock_running = false
	var spent := float(Rules.reserve_for_shift(run_number)) - reserve   # reserve used, penalties included
	var par := Rules.par_seconds(run_number)
	var result := ScoreManager.breakdown(reserve, retry_count, spent, par)
	result["par"] = par
	result["spent"] = spent
	run_score += int(result["final"])
	result["run_total"] = run_score
	result["hints"] = hints_used
	var adaptation := AdaptiveDifficulty.evaluate(spent, float(Rules.reserve_for_shift(run_number)), mistakes, retry_count, previous_ratio, adapt_steps, Rules.adaptive)
	pending_adapt = int(adaptation["steps"])
	previous_ratio = float(adaptation["ratio"])
	result["adaptation"] = adaptation
	result["next_reserve"] = Rules.reserve_for(run_number + 1, pending_adapt)
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
		var how := "in the same order" if puzzles.get("protocol", "A") == "A" else "in reverse order"
		return {"ok": true, "text": "All systems are repaired. Walk back west along the corridor and press E on the reboot terminal. It flashes a sequence of pads: on protocol %s repeat it %s." % [puzzles.get("protocol", "A"), how], "cost": 0}
	if reserve <= float(Rules.hint_cost()):
		return {"ok": false, "text": "Not enough oxygen reserve left for a hint.", "cost": 0}
	reserve -= float(Rules.hint_cost())
	hints_used += 1
	reserve_changed.emit(reserve)
	hint_used.emit(Rules.hint_cost())
	return {"ok": true, "text": _hint_text(next), "cost": Rules.hint_cost()}


func _hint_text(system_id: String) -> String:
	var protocol: String = puzzles.get("protocol", "A")
	match system_id:
		"power":
			var restore_first := "lowest" if protocol == "A" else "highest"
			var shed_first := "highest" if protocol == "A" else "lowest"
			return "Next: POWER (the first room along the corridor). Protocol %s: in RESTORE mode flip the %s voltage first; in SHED mode flip the %s first. Read the LOAD MODE and the breaker voltages." % [protocol, restore_first, shed_first]
		"oxygen":
			var table: Dictionary = Rules.OXYGEN_TABLES[protocol]
			var rows: Array[String] = []
			for mode in Rules.OXYGEN_MODES:
				rows.append("%s %s" % [mode, ", ".join((table[mode] as Array).map(func(v: int) -> String: return str(v)))])
			return "Next: OXYGEN (the second room; its door opens once Power is repaired). Protocol %s valve table: %s. Read the STATION MODE on the wall." % [protocol, ". ".join(rows)]
		"comms":
			return "Next: COMMS (the third room; its door opens once Oxygen is repaired). Protocol %s: 100 MHz plus %d MHz for every lit beacon. Count the lit beacons." % [protocol, Rules.COMMS_PER_BEACON_MHZ[protocol]]
		_:
			return "Next: COOLING (the fourth room; its door opens once Comms is repaired). Protocol %s: coolant flow is the core temperature minus %d K, divided by %d, plus %d if the reactor state is SURGE. Read the CORE TEMP and the REACTOR state." % [protocol, Rules.COOLING_BASE_K, Rules.COOLING_DIVISOR[protocol], Rules.COOLING_SURGE_BONUS]


# --- Internals -----------------------------------------------------------

## Every question asked to ORACLE costs reserve time (the manuals are free). It can never be
## the thing that ends a shift: at least one second is always left. Returns the seconds charged.
func charge_oracle_question() -> int:
	if state != State.PLAYING:
		return 0
	var cost := mini(Rules.oracle_cost(), maxi(0, int(floor(reserve)) - 1))
	if cost <= 0:
		return 0
	reserve -= float(cost)
	oracle_questions += 1
	reserve_changed.emit(reserve)
	oracle_charged.emit(cost)
	return cost


## A corridor hazard (gas or gravity) took reserve time. Not a puzzle mistake: it does not
## count in `mistakes`. Only counts while a shift is running.
func hazard_damage(kind: String, seconds: float) -> void:
	if state != State.PLAYING or seconds <= 0.0:
		return
	hazard_seconds += seconds
	reserve = maxf(0.0, reserve - seconds)
	hazard_hit.emit(kind, seconds)
	reserve_changed.emit(reserve)
	if reserve <= 0.0:
		_fail()


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
