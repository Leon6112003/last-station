class_name PuzzleGenerator
extends RefCounted
## Pure, seeded generation of the four puzzles. No nodes, no rendering.
##
## The same (seed_value, attempt) always gives identical parameters, so tests
## are reproducible. A retry bumps `attempt`, which re-rolls the values so a
## memorised answer from the previous attempt is useless.
##
## Returns:
## {
##   "protocol": "A" | "B"   (also copied into each puzzle below),
##   "power":  {"ratings": Array[int] (one volt rating per breaker), "mode": "RESTORE" | "SHED", "protocol": ...},
##   "oxygen": {"mode": "NIGHT" | "DAY" | "EMERGENCY", "protocol": ...},
##   "comms":  {"lit": int (number of lit beacons), "protocol": ...},
##   "cooling": {"temp": int (core temperature in K), "state": "NORMAL" | "SURGE", "protocol": ...}
## }


## `force_protocol` ("A" or "B") overrides the random protocol. The guided first
## shift uses it so new players always start on protocol A.
static func generate(seed_value: int, attempt: int, force_protocol: String = "") -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%d:%d" % [seed_value, attempt])

	# Fisher-Yates shuffle with the seeded generator (Array.shuffle() would use
	# the global, unseeded generator and break determinism).
	var pool: Array[int] = []
	pool.assign(Rules.BREAKER_RATINGS)
	for i in range(pool.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var swap := pool[i]
		pool[i] = pool[j]
		pool[j] = swap

	var ratings: Array[int] = []
	for i in Rules.BREAKER_COUNT:
		ratings.append(pool[i])

	var power_mode := "RESTORE" if rng.randi_range(0, 1) == 0 else "SHED"

	var oxygen_mode: String = Rules.OXYGEN_MODES[rng.randi_range(0, Rules.OXYGEN_MODES.size() - 1)]

	var lit := rng.randi_range(Rules.BEACON_LIT_MIN, Rules.BEACON_LIT_MAX)

	# Drawn last so the earlier values for a given seed stay the same.
	var protocol: String = Rules.PROTOCOLS[rng.randi_range(0, Rules.PROTOCOLS.size() - 1)]
	if Rules.PROTOCOLS.has(force_protocol):
		protocol = force_protocol

	# Drawn after the protocol, so every value above stays the same for a given seed.
	var cooling_temp: int = Rules.COOLING_TEMPS[rng.randi_range(0, Rules.COOLING_TEMPS.size() - 1)]
	var cooling_state: String = Rules.COOLING_STATES[rng.randi_range(0, Rules.COOLING_STATES.size() - 1)]

	return {
		"protocol": protocol,
		"power": {"ratings": ratings, "mode": power_mode, "protocol": protocol},
		"oxygen": {"mode": oxygen_mode, "protocol": protocol},
		"comms": {"lit": lit, "protocol": protocol},
		"cooling": {"temp": cooling_temp, "state": cooling_state, "protocol": protocol},
	}
