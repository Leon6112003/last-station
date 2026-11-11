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
# The zero-gravity zone makes the player float and drains reserve until a wall switch restores gravity for a while.
const GRAVITY_OFF_SECONDS := 10.0       # how long a switch keeps gravity on
const GRAVITY_WARN_SECONDS := 2.0       # it flickers this long before gravity fails again
const GRAVITY_TOUCH_PENALTY_SECONDS := 10.0   # base hazard penalty; a floating second costs 20% of it
const GRAVITY_TOUCH_COOLDOWN_SECONDS := 1.5

# --- Hazards that grow with the shift -------------------------------------------
# Shift 1 uses the base numbers above. Each later shift makes the corridor a little worse:
# the vents are quiet for less time and vent for longer and over a wider stretch, the gravity
# switches keep the grid off for less time, and from shift 3 a second gravity zone guards the
# Cooling door. All the growth stops at the caps below, so the game stays fair.
const GAS_OFF_STEP := 0.5
const GAS_OFF_MIN := 1.5
const GAS_ON_STEP := 0.5
const GAS_ON_MAX := 9.0
const GAS_LENGTH_STEP := 1.0
const GAS_LENGTH_MAX := 10.0
const GRAVITY_OFF_STEP := 1.0
const GRAVITY_OFF_MIN_FRACTION := 0.5   # never less than half of the level's switch-off time
const SECOND_GRAVITY_FROM_SHIFT := 3


## How far along the difficulty curve a shift is: one step per shift, moved by the adaptation
## (`adapt`: steps the game has made the next shifts easier or harder, see AdaptiveDifficulty).
static func _growth(run: int) -> int:
	return maxi(maxi(run, 1) - 1 + adapt, 0)


static func gas_off_seconds(run: int = 1) -> float:
	return maxf(GAS_OFF_MIN, GAS_OFF_SECONDS - GAS_OFF_STEP * _growth(run))


static func gas_on_seconds(run: int = 1) -> float:
	return minf(GAS_ON_MAX, GAS_ON_SECONDS + GAS_ON_STEP * _growth(run))


static func gas_length(run: int = 1) -> float:
	return minf(GAS_LENGTH_MAX, 6.0 + GAS_LENGTH_STEP * _growth(run))


## How long a wall switch keeps gravity on on this shift (the level's time, shortened).
static func gravity_off_for(run: int = 1) -> float:
	return maxf(gravity_off() * GRAVITY_OFF_MIN_FRACTION, gravity_off() - GRAVITY_OFF_STEP * _growth(run))


## The length of the reboot sequence on a shift: 4, growing by one every second shift, up to 6.
static func sequence_length(run: int = 1) -> int:
	return mini(SEQ_LENGTH_MAX, SEQ_LENGTH_BASE + _growth(run) / 2)


## What it costs to have the reboot sequence shown again (half a hint; the first showing is free).
static func replay_cost() -> int:
	return maxi(1, hint_cost() / 2)


static func gravity_count(run: int = 1) -> int:
	return 2 if _growth(run) >= SECOND_GRAVITY_FROM_SHIFT - 1 else 1


# --- Difficulty levels -----------------------------------------------------
# The player picks a level on the main menu. ENGINEER is the standard game and uses the
# values above; ROOKIE is gentler and SURVIVOR is harsher. Everything that depends on the
# level is read through the functions below, so no other script holds a level number.
const LEVEL_ROOKIE := 0
const LEVEL_ENGINEER := 1
const LEVEL_SURVIVOR := 2
const LEVEL_NAMES: Array[String] = ["Rookie", "Engineer", "Survivor"]
const LEVEL_BLURBS: Array[String] = [
	"More time, weaker gas and gravity, free ORACLE questions.",
	"The standard game.",
	"Less time, deadly gas and gravity, costly help.",
]
const RESERVE_MAX_SECONDS := 480      # the largest starting reserve of any level
const LEVELS: Array[Dictionary] = [
	{"reserve": 480, "min": 240, "gas": 6.0, "gravity_penalty": 5.0, "gravity_off": 15.0,
		"oracle": 0, "hint": 10, "surge": 8, "confirm": 5, "score": 0.6},
	{"reserve": RESERVE_START_SECONDS, "min": RESERVE_MIN_SECONDS, "gas": GAS_DRAIN_PER_SECOND,
		"gravity_penalty": GRAVITY_TOUCH_PENALTY_SECONDS, "gravity_off": GRAVITY_OFF_SECONDS,
		"oracle": ORACLE_QUESTION_COST_SECONDS, "hint": HINT_COST_SECONDS,
		"surge": SURGE_PENALTY_SECONDS, "confirm": WRONG_CONFIRM_PENALTY_SECONDS, "score": 1.0},
	{"reserve": 270, "min": 150, "gas": 20.0, "gravity_penalty": 20.0, "gravity_off": 6.0,
		"oracle": 10, "hint": 40, "surge": 30, "confirm": 20, "score": 1.4},
]
## The selected level (set from the menu or the save file). Defaults to ENGINEER.
static var level: int = LEVEL_ENGINEER


static func _value(key: String) -> Variant:
	return LEVELS[clampi(level, LEVEL_ROOKIE, LEVEL_SURVIVOR)][key]


static func level_name() -> String:
	return LEVEL_NAMES[clampi(level, LEVEL_ROOKIE, LEVEL_SURVIVOR)]


## The adaptation in force for the current shift, in steps (negative = easier, positive = harder).
## Set by GameManager when a shift starts; 0 means the normal curve.
static var adapt: int = 0
## Adaptive difficulty switched on (the Settings option).
static var adaptive: bool = true


## Oxygen reserve at the start of a shift: the level's starting reserve (Engineer: 360 s),
## 45 s less each shift, never below the level's floor (Engineer: 180 s).
static func reserve_for_shift(run: int) -> int:
	return reserve_for(run, adapt)


## The same for a given adaptation, so the results screen can show the next shift's reserve.
static func reserve_for(run: int, steps: int) -> int:
	return maxi(int(_value("min")), reserve_start() - RESERVE_STEP_SECONDS * maxi(maxi(run, 1) - 1 + steps, 0))


static func reserve_start() -> int:
	return int(_value("reserve"))


static func gas_drain() -> float:
	return float(_value("gas"))


static func gravity_penalty() -> float:
	return float(_value("gravity_penalty"))


static func gravity_off() -> float:
	return float(_value("gravity_off"))


static func oracle_cost() -> int:
	return int(_value("oracle"))


static func hint_cost() -> int:
	return int(_value("hint"))


static func surge_penalty() -> int:
	return int(_value("surge"))


static func confirm_penalty() -> int:
	return int(_value("confirm"))


## Multiplies the shift score, so a harder level (and a harder set of modifiers) is worth more.
static func score_multiplier() -> float:
	var multiplier := float(_value("score"))
	for flag in MOD_FLAGS:
		if has_mod(flag):
			multiplier *= float(MOD_SCORE[flag])
	return multiplier


# --- Modifiers (optional extras chosen on the main menu, in any combination) -----------
# BLACKOUT: the corridor lights flicker and the gas vents start at a different point of their
#   cycle every shift. HARDCORE: one failed shift ends the run and clears the run score; there
#   is no retry. SPEEDRUN: a visible par time and a bonus for beating it.
const MOD_BLACKOUT := 1
const MOD_HARDCORE := 2
const MOD_SPEEDRUN := 4
const MOD_FLAGS: Array[int] = [MOD_BLACKOUT, MOD_HARDCORE, MOD_SPEEDRUN]
const MOD_NAMES := {1: "Blackout", 2: "Hardcore", 4: "Speedrun"}
const MOD_BLURBS := {
	1: "Flickering corridor lights; gas timing changes every shift.",
	2: "One failed shift ends the run. No retries.",
	4: "A par time to beat, with a bonus for beating it.",
}
const MOD_SCORE := {1: 1.15, 2: 1.25, 4: 1.0}
const MODS_ALL := 7
const SPEED_PAR_FRACTION := 0.5      # par = this share of the shift's starting reserve
const SPEED_BONUS_FLAT := 100        # for finishing within par...
const SPEED_BONUS_PER_SECOND := 1    # ...plus this for every second under it
const BLACKOUT_DIP_SECONDS := 0.35   # a corridor light cuts out this long, now and then
const BLACKOUT_DIP_EVERY_SECONDS := 7.0
const BLACKOUT_MIN_LEVEL := 0.35     # the flicker never takes a light below this share of its energy
const BLACKOUT_PHASE_STEP := 3.1     # seconds the vents' cycle is shifted by per shift

## The modifiers in use (a sum of the MOD_ flags). Set from the menu or the save file.
static var mods: int = 0


static func has_mod(flag: int) -> bool:
	return mods & flag != 0


static func set_mod(flag: int, on: bool) -> void:
	mods = (mods | flag) if on else (mods & ~flag)
	mods &= MODS_ALL


## "Blackout + Hardcore", or "" when there are none.
static func mods_text() -> String:
	var names: Array[String] = []
	for flag in MOD_FLAGS:
		if has_mod(flag):
			names.append(MOD_NAMES[flag])
	return " + ".join(names)


## Par time for a shift, in reserve seconds spent: half of the shift's starting reserve.
static func par_seconds(run: int) -> float:
	return float(reserve_for_shift(run)) * SPEED_PAR_FRACTION


## Speedrun bonus for finishing a shift having spent `spent` reserve seconds against `par`.
static func speed_bonus(spent: float, par: float) -> int:
	if not has_mod(MOD_SPEEDRUN) or spent > par:
		return 0
	return SPEED_BONUS_FLAT + int(floor(par - spent)) * SPEED_BONUS_PER_SECOND


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
# Cooling (the fourth system): set the coolant flow from the reactor's core temperature.
# flow = (core temperature - COOLING_BASE_K) / divisor for the protocol, plus a bonus when the
# reactor state is SURGE.
const COOLING_BASE_K := 400
const COOLING_DIVISOR := {"A": 20, "B": 10}
const COOLING_SURGE_BONUS := 5
const COOLING_TEMPS: Array[int] = [440, 480, 520, 560, 600, 640]
const COOLING_STATES: Array[String] = ["NORMAL", "SURGE"]
const COOLING_FLOW_MAX := 40
const COOLING_FLOW_STEP := 1
# The reboot code: once all four systems are repaired, the reboot terminal flashes a sequence of
# pads. Protocol A: repeat it in the same order. Protocol B: repeat it in reverse. A wrong pad costs
# the usual confirm penalty and replays the sequence; showing it again on request costs reserve.
const SEQ_PAD_COUNT := 4
const SEQ_PAD_NAMES: Array[String] = ["A", "B", "C", "D"]
const SEQ_LENGTH_BASE := 4
const SEQ_LENGTH_MAX := 6
const SEQ_RETRY_PAUSE_SECONDS := 1.5   # pause between a wrong code and the replay
const SEQ_STEP_SECONDS := 1.0       # how long each pad lights up when the sequence is shown
const SYSTEMS_TOTAL := 4

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
