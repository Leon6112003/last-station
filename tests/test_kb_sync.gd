extends SceneTree
## The manuals must say exactly what the code does. Every number in rules.gd
## that a player might rely on has to appear in the matching manual entry.
## Run:  godot --headless --path . -s res://tests/test_kb_sync.gd

const REQUIRED_IDS := [
	"objective", "protocols", "help_topics", "first_steps", "hints", "controls", "reserve_timer", "scoring", "retry_rules",
	"power_overview", "power_order", "oxygen_overview", "oxygen_table",
	"comms_overview", "comms_formula", "cooling_overview", "cooling_formula", "reboot_code", "hazard_links", "adaptive_difficulty", "cryo_bay", "hazards_grow", "modifiers", "settings", "mistake_penalties", "reboot_terminal",
	"oracle_limits", "offline_setup", "privacy",
]

var _failures: int = 0
var _by_id: Dictionary = {}


func _initialize() -> void:
	var records := KnowledgeBase.load_records()
	_check(records.size() >= 14, "at least 14 records (found %d)" % records.size())

	var seen := {}
	var all_valid := true
	var all_short := true
	for record in records:
		if seen.has(record["id"]):
			all_valid = false
		seen[record["id"]] = true
		_by_id[record["id"]] = record
		if (record["text"] as String).length() > KnowledgeBase.MAX_TEXT_LENGTH:
			all_short = false
			print("      too long: ", record["id"], " (", (record["text"] as String).length(), ")")
		if (record["keywords"] as Array).is_empty():
			all_valid = false
	_check(all_valid, "ids are unique and every record has keywords")
	_check(all_short, "every text fits the %d character excerpt limit" % KnowledgeBase.MAX_TEXT_LENGTH)

	for id in REQUIRED_IDS:
		_check(_by_id.has(id), "required record '%s' exists" % id)

	# The loader must survive bad input.
	_check(KnowledgeBase.load_records("res://data/does_not_exist.json").is_empty(), "a missing file gives an empty list")
	_check(not KnowledgeBase.is_valid_record({"id": "x"}), "a record without text is rejected")
	_check(not KnowledgeBase.is_valid_record("nope"), "a non-dictionary record is rejected")

	# Numbers from rules.gd must appear in the matching entries.
	var max_score := Rules.BASE_POINTS + Rules.RESERVE_START_SECONDS / Rules.TIME_BONUS_DIVISOR
	_has("reserve_timer", str(Rules.RESERVE_START_SECONDS))
	_has("reserve_timer", str(Rules.RESERVE_STEP_SECONDS))
	_has("reserve_timer", str(Rules.RESERVE_MIN_SECONDS))
	_has("hints", str(Rules.HINT_COST_SECONDS))
	for level in Rules.LEVELS.size():
		# The levels entry lists every non-standard level's numbers; they must match rules.gd.
		if level == Rules.LEVEL_ENGINEER:
			continue
		var values: Dictionary = Rules.LEVELS[level]
		_has("difficulty", "%d s reserve" % int(values["reserve"]))
		_has("difficulty", "x%s" % str(values["score"]))
		_has("difficulty", "hint %d s" % int(values["hint"]))
	_has("protocols", "Shift 1 always uses Protocol A")
	_has("scoring", str(Rules.BASE_POINTS))
	_has("scoring", str(Rules.RETRY_PENALTY_STEP))
	_has("scoring", str(Rules.RETRY_PENALTY_MAX))
	_has("scoring", str(max_score))
	_has("retry_rules", str(Rules.RETRY_PENALTY_STEP))
	_has("retry_rules", str(Rules.RESERVE_START_SECONDS))
	_has("mistake_penalties", str(Rules.SURGE_PENALTY_SECONDS))
	_has("mistake_penalties", str(Rules.WRONG_CONFIRM_PENALTY_SECONDS))
	_has("power_order", str(Rules.SURGE_PENALTY_SECONDS))
	_has("cooling_formula", str(Rules.COOLING_BASE_K))
	_has("reboot_code", "reverse order")
	_has("hazard_links", "first laser grid")
	_has("adaptive_difficulty", "more than %d%%" % int(round(AdaptiveDifficulty.RATIO_EASIER * 100.0)))
	_has("adaptive_difficulty", "%d retries" % AdaptiveDifficulty.RETRIES_EASIER)
	_has("adaptive_difficulty", "%d mistakes" % AdaptiveDifficulty.MISTAKES_EASIER)
	_has("adaptive_difficulty", "under %d%%" % int(round(AdaptiveDifficulty.RATIO_HARDER * 100.0)))
	_has("adaptive_difficulty", "at most %d retry" % AdaptiveDifficulty.RETRIES_HARDER)
	_has("adaptive_difficulty", "%d mistakes" % AdaptiveDifficulty.MISTAKES_HARDER)
	_has("adaptive_difficulty", "%d seconds of reserve" % Rules.RESERVE_STEP_SECONDS)
	_has("adaptive_difficulty", "up to %d steps easier or %d harder" % [-AdaptiveDifficulty.STEPS_MIN, AdaptiveDifficulty.STEPS_MAX])
	_has("hazard_links", "SURGE")
	_has("reboot_code", "half a hint (%d seconds" % Rules.replay_cost())
	_has("reboot_code", "penalty (%d seconds" % Rules.WRONG_CONFIRM_PENALTY_SECONDS)
	_has("modifiers", "x%s" % str(Rules.MOD_SCORE[Rules.MOD_BLACKOUT]))
	_has("modifiers", "x%s" % str(Rules.MOD_SCORE[Rules.MOD_HARDCORE]))
	_has("modifiers", "%d points plus %d per second" % [Rules.SPEED_BONUS_FLAT, Rules.SPEED_BONUS_PER_SECOND])
	_has("modifiers", "half the shift")
	_has("hazards_grow", "%s seconds less (down to %s)" % [str(Rules.GAS_OFF_STEP), str(Rules.GAS_OFF_MIN)])
	_has("hazards_grow", "%s seconds longer (up to %d)" % [str(Rules.GAS_ON_STEP), int(Rules.GAS_ON_MAX)])
	_has("hazards_grow", "(up to %d)" % int(Rules.GAS_LENGTH_MAX))
	_has("hazards_grow", "From shift %d" % Rules.SECOND_LASER_FROM_SHIFT)
	_has("cooling_formula", "divided by %d" % int(Rules.COOLING_DIVISOR["A"]))
	_has("cooling_formula", "divided by %d" % int(Rules.COOLING_DIVISOR["B"]))
	_has("cooling_formula", "add %d" % Rules.COOLING_SURGE_BONUS)
	_has("cooling_formula", str(Rules.WRONG_CONFIRM_PENALTY_SECONDS))
	_has("cooling_overview", "0 to %d L/s" % Rules.COOLING_FLOW_MAX)
	_has("power_order", "RESTORE")
	_has("power_order", "SHED")
	for rating in Rules.BREAKER_RATINGS:
		_has("power_overview", str(rating))
	_has("oxygen_table", str(Rules.WRONG_CONFIRM_PENALTY_SECONDS))
	for mode in Rules.OXYGEN_MODES:
		_has("oxygen_overview", mode)
	for protocol in Rules.PROTOCOLS:
		_has("oxygen_table", "Protocol %s" % protocol)
		_has("power_order", "Protocol %s, RESTORE" % protocol)
		_has("power_order", "Protocol %s, SHED" % protocol)
		_has("comms_formula", "Protocol %s" % protocol)
		_has("comms_formula", str(Rules.COMMS_PER_BEACON_MHZ[protocol]))
		_has("comms_formula", str(Rules.COMMS_BASE_MHZ + 3 * Rules.COMMS_PER_BEACON_MHZ[protocol]))
		var table: Dictionary = Rules.OXYGEN_TABLES[protocol]
		for mode in table:
			# "Protocol A, NIGHT: 30, 40, 50." must appear exactly as the table says.
			var values := ", ".join((table[mode] as Array).map(func(v: int) -> String: return str(v)))
			_has("oxygen_table", "Protocol %s, %s: %s." % [protocol, mode, values])
	_has("oxygen_table", str(Rules.WRONG_CONFIRM_PENALTY_SECONDS))
	_has("oxygen_overview", str(Rules.OXYGEN_STEP))
	_has("comms_formula", str(Rules.COMMS_BASE_MHZ))
	_has("comms_formula", str(Rules.WRONG_CONFIRM_PENALTY_SECONDS))
	_has("protocols", "PROTOCOL A or B")
	_has("retry_rules", "protocol")
	_has("comms_overview", str(Rules.COMMS_MIN_MHZ))
	_has("comms_overview", str(Rules.COMMS_MAX_MHZ))
	_has("comms_overview", str(Rules.COMMS_STEP_MHZ))
	_has("comms_overview", "six")

	# Manuals must never contain a live puzzle answer: no per-run values exist
	# in the file, only rules and the public table.
	var combined := ""
	for record in records:
		combined += " " + record["text"]
	_check(not combined.contains("B1 is") and not combined.contains("lit beacons are"), "manuals contain no run-specific values")

	print("")
	if _failures == 0:
		print("ALL PASS")
		quit(0)
	else:
		print("%d FAILURE(S)" % _failures)
		quit(1)


func _has(id: String, needle: String) -> void:
	var text: String = _by_id[id]["text"] if _by_id.has(id) else ""
	_check(text.contains(needle), "'%s' mentions '%s'" % [id, needle])


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS  ", label)
	else:
		print("FAIL  ", label)
		_failures += 1
