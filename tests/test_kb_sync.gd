extends SceneTree
## The manuals must say exactly what the code does. Every number in rules.gd
## that a player might rely on has to appear in the matching manual entry.
## Run:  godot --headless --path . -s res://tests/test_kb_sync.gd

const REQUIRED_IDS := [
	"objective", "protocols", "help_topics", "first_steps", "hints", "controls", "reserve_timer", "scoring", "retry_rules",
	"power_overview", "power_order", "oxygen_overview", "oxygen_table",
	"comms_overview", "comms_formula", "mistake_penalties", "reboot_terminal",
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
