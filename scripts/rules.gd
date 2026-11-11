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

## Oxygen reserve at the start of a shift: 360 s on shift 1, 45 s less each shift, never below 180 s.
static func reserve_for_shift(run: int) -> int:
	return maxi(RESERVE_MIN_SECONDS, RESERVE_START_SECONDS - RESERVE_STEP_SECONDS * (maxi(run, 1) - 1))


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
