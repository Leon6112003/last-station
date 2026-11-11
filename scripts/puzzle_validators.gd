class_name PuzzleValidators
extends RefCounted
## Pure functions that decide whether a player's action is correct.
## Solutions are computed here, from the generated parameters; they are never
## stored in the knowledge base or given to the assistant.


## Breaker indices in the order they must be flipped.
## Protocol A: RESTORE = lowest rating first, SHED = highest first.
## Protocol B reverses both.
static func power_order(power: Dictionary) -> Array[int]:
	var ratings: Array = power["ratings"]
	var order: Array[int] = []
	for i in ratings.size():
		order.append(i)
	order.sort_custom(func(a: int, b: int) -> bool: return ratings[a] < ratings[b])
	var protocol: String = power.get("protocol", "A")
	if (power["mode"] == "SHED") != (protocol == "B"):
		order.reverse()
	return order


## True if `candidate` is the next breaker that should be flipped.
static func is_next_breaker(power: Dictionary, already_latched: Array, candidate: int) -> bool:
	var order := power_order(power)
	if already_latched.size() >= order.size():
		return false
	return order[already_latched.size()] == candidate


## Target valve settings for the current station mode.
static func oxygen_target(oxygen: Dictionary) -> Array:
	return Rules.OXYGEN_TABLES[oxygen.get("protocol", "A")][oxygen["mode"]]


static func oxygen_matches(oxygen: Dictionary, values: Array) -> bool:
	var target := oxygen_target(oxygen)
	if values.size() != target.size():
		return false
	for i in target.size():
		if values[i] != target[i]:
			return false
	return true


## Distress frequency in MHz: 100 + (20 on protocol A, 10 on B) per lit beacon.
static func comms_target(comms: Dictionary) -> int:
	var per_beacon: int = Rules.COMMS_PER_BEACON_MHZ[comms.get("protocol", "A")]
	return Rules.COMMS_BASE_MHZ + per_beacon * int(comms["lit"])


static func comms_matches(comms: Dictionary, mhz: int) -> bool:
	return mhz == comms_target(comms)
