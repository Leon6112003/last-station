class_name Rules
extends RefCounted
## Single source of truth for every number and colour in the game.
## The knowledge base (data/game_knowledge.json) must match these values;
## tests/test_kb_sync.gd enforces that from Milestone 4 onward.

# --- Palette -----------------------------------------------------------
const COLOR_NAVY := Color8(16, 20, 43)      # #10142B
const COLOR_INDIGO := Color8(53, 58, 121)   # #353A79
const COLOR_VIOLET := Color8(138, 101, 232) # #8A65E8
const COLOR_CYAN := Color8(107, 234, 217)   # #6BEAD9
const COLOR_GOLD := Color8(255, 215, 138)   # #FFD78A
const COLOR_FAULT := Color8(255, 90, 110)   # red for unrepaired systems

# --- Reserve and penalties (used from Milestone 2) ----------------------
const RESERVE_START_SECONDS := 360
const SURGE_PENALTY_SECONDS := 15
const WRONG_CONFIRM_PENALTY_SECONDS := 10

# Each later shift has less reserve, so the run gets harder.
const RESERVE_STEP_SECONDS := 45
const RESERVE_MIN_SECONDS := 180
# ORACLE's diagnostic hint costs reserve time.
const HINT_COST_SECONDS := 20
# Every question asked to ORACLE costs reserve time (the manuals, M, are free).
const ORACLE_QUESTION_COST_SECONDS := 5

# Corridor hazards. Gas vents and spark gaps cost reserve time if you cross them while
# they are active. Each one cycles: quiet, then a warning, then active.
const GAS_OFF_SECONDS := 3.0
const GAS_WARN_SECONDS := 1.0
const GAS_ON_SECONDS := 6.0
const GAS_DRAIN_PER_SECOND := 12.0    # reserve seconds lost per second inside venting gas
# The laser grid is a solid barrier that stays on until a wall switch turns it off for a while.
const LASER_OFF_SECONDS := 10.0       # how long a switch keeps the grid off
const LASER_WARN_SECONDS := 2.0       # it flickers this long before switching back on
const LASER_TOUCH_PENALTY_SECONDS := 10.0   # reserve seconds lost for touching the laser
const LASER_TOUCH_COOLDOWN_SECONDS := 1.5

# --- Difficulty levels -----------------------------------------------------
# The player picks a level on the main menu. ENGINEER is the standard game and uses the
# values above; ROOKIE is gentler and SURVIVOR is harsher. Everything that depends on the
# level is read through the functions below, so no other script holds a level number.
const LEVEL_ROOKIE := 0
const LEVEL_ENGINEER := 1
const LEVEL_SURVIVOR := 2
const LEVEL_NAMES: Array[String] = ["Rookie", "Engineer", "Survivor"]
const LEVEL_BLURBS: Array[String] = [
	"More time, weaker gas and laser, free ORACLE questions.",
	"The standard game.",
	"Less time, deadly gas and laser, costly help.",
]
const RESERVE_MAX_SECONDS := 480      # the largest starting reserve of any level
const LEVELS: Array[Dictionary] = [
	{"reserve": 480, "min": 240, "gas": 6.0, "laser_penalty": 5.0, "laser_off": 15.0,
		"oracle": 0, "hint": 10, "surge": 8, "confirm": 5, "score": 0.6},
	{"reserve": RESERVE_START_SECONDS, "min": RESERVE_MIN_SECONDS, "gas": GAS_DRAIN_PER_SECOND,
		"laser_penalty": LASER_TOUCH_PENALTY_SECONDS, "laser_off": LASER_OFF_SECONDS,
		"oracle": ORACLE_QUESTION_COST_SECONDS, "hint": HINT_COST_SECONDS,
		"surge": SURGE_PENALTY_SECONDS, "confirm": WRONG_CONFIRM_PENALTY_SECONDS, "score": 1.0},
	{"reserve": 270, "min": 150, "gas": 20.0, "laser_penalty": 20.0, "laser_off": 6.0,
		"oracle": 10, "hint": 40, "surge": 30, "confirm": 20, "score": 1.4},
]
## The selected level (set from the menu or the save file). Defaults to ENGINEER.
static var level: int = LEVEL_ENGINEER


static func _value(key: String) -> Variant:
	return LEVELS[clampi(level, LEVEL_ROOKIE, LEVEL_SURVIVOR)][key]


static func level_name() -> String:
	return LEVEL_NAMES[clampi(level, LEVEL_ROOKIE, LEVEL_SURVIVOR)]


## Oxygen reserve at the start of a shift: the level's starting reserve (Engineer: 360 s),
## 45 s less each shift, never below the level's floor (Engineer: 180 s).
static func reserve_for_shift(run: int) -> int:
	return maxi(int(_value("min")), reserve_start() - RESERVE_STEP_SECONDS * (maxi(run, 1) - 1))


static func reserve_start() -> int:
	return int(_value("reserve"))


static func gas_drain() -> float:
	return float(_value("gas"))


static func laser_penalty() -> float:
	return float(_value("laser_penalty"))


static func laser_off() -> float:
	return float(_value("laser_off"))


static func oracle_cost() -> int:
	return int(_value("oracle"))


static func hint_cost() -> int:
	return int(_value("hint"))


static func surge_penalty() -> int:
	return int(_value("surge"))


static func confirm_penalty() -> int:
	return int(_value("confirm"))


## Multiplies the shift score, so a score earned on a harder level is worth more.
static func score_multiplier() -> float:
	return float(_value("score"))


# --- Score (used from Milestone 2) --------------------------------------
const BASE_POINTS := 300
const TIME_BONUS_DIVISOR := 2
const RETRY_PENALTY_STEP := 50
const RETRY_PENALTY_MAX := 150

# --- Puzzle constants (used from Milestone 2) ---------------------------
const BREAKER_RATINGS: Array[int] = [120, 208, 240, 277, 400, 480]
const BREAKER_COUNT := 4
const OXYGEN_STEP := 10
# Every shift runs under PROTOCOL A or B. The protocol changes the Power order,
# the Oxygen valve table and the Comms formula, so the manuals are needed.
const PROTOCOLS: Array[String] = ["A", "B"]
const OXYGEN_MODES: Array[String] = ["NIGHT", "DAY", "EMERGENCY"]
const OXYGEN_TABLES := {
	"A": {"NIGHT": [30, 40, 50], "DAY": [50, 60, 70], "EMERGENCY": [70, 80, 90]},
	"B": {"NIGHT": [40, 50, 60], "DAY": [60, 70, 80], "EMERGENCY": [80, 90, 100]},
}
const COMMS_BASE_MHZ := 100
const COMMS_PER_BEACON_MHZ := {"A": 20, "B": 10}
const COMMS_MIN_MHZ := 100
const COMMS_MAX_MHZ := 200
const COMMS_STEP_MHZ := 5
const BEACON_COUNT := 6
const BEACON_LIT_MIN := 1
const BEACON_LIT_MAX := 5
const SYSTEMS_TOTAL := 3

# --- Retry -------------------------------------------------------------
const RETRY_HOLD_SECONDS := 1.0

# --- Player ------------------------------------------------------------
const PLAYER_SPEED := 5.0
const MOUSE_SENSITIVITY := 0.002
const PLAYER_GRAVITY := 20.0
const PLAYER_RADIUS := 0.35
const PLAYER_HEIGHT := 1.7
const EYE_HEIGHT := 1.55
const INTERACT_DISTANCE := 2.5
const MAX_PITCH_DEGREES := 85.0

# --- Collision layers (bit values) -------------------------------------
# Layer 1 = world solids, layer 2 = player, layer 3 = interactables.
const LAYER_WORLD := 1
const LAYER_PLAYER := 2
const LAYER_INTERACT := 4

# --- Station geometry (metres) -----------------------------------------
const WALL_HEIGHT := 3.0
const WALL_THICKNESS := 0.3
