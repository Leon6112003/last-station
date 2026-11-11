class_name AdaptiveDifficulty
extends RefCounted
## Rule-based adaptive difficulty. After each shift the player clears, a fixed rule looks at how it
## went and decides whether the next shift is harder, easier or the same. It is NOT machine
## learning: there is no training, no model and no randomness, only the thresholds below, so the
## same inputs always give the same decision. Pure functions (no nodes), so every case is tested.
##
## The inputs are the share of the shift's reserve that was used (smoothed over the last two
## shifts so one lucky or unlucky shift does not swing the game), the mistakes and the retries.
## Each "step" of adaptation moves the next shift one shift's worth along the difficulty curve
## (45 s less reserve and harsher hazards for a harder step, the opposite for an easier one).
## These numbers are estimates chosen by reasoning; they have not been tuned by play.

const SAME := 0
const HARDER := 1
const EASIER := -1

const RATIO_EASIER := 0.80      # used more than this share of the reserve: too hard
const RATIO_HARDER := 0.40      # used less than this share ...
const RETRIES_EASIER := 3       # this many retries or more: too hard
const RETRIES_HARDER := 1       # ... with at most this many retries ...
const MISTAKES_EASIER := 6      # this many mistakes or more: too hard
const MISTAKES_HARDER := 2      # ... and at most this many mistakes: too easy
const STEPS_MIN := -2           # never more than 2 steps easier than the normal curve
const STEPS_MAX := 3            # never more than 3 steps harder


## The decision for one shift. Strict priority: the "easier" rule is checked first.
static func decide(ratio: float, mistakes: int, retries: int) -> int:
	if ratio > RATIO_EASIER or retries >= RETRIES_EASIER or mistakes >= MISTAKES_EASIER:
		return EASIER
	if ratio < RATIO_HARDER and retries <= RETRIES_HARDER and mistakes <= MISTAKES_HARDER:
		return HARDER
	return SAME


## The ratio the rule uses: this shift's, averaged with the previous shift's when there is one
## (a negative `previous` means there was none).
static func averaged(ratio: float, previous: float) -> float:
	return ratio if previous < 0.0 else (ratio + previous) * 0.5


static func next_steps(current: int, decision: int) -> int:
	return clampi(current + decision, STEPS_MIN, STEPS_MAX)


## One plain sentence for the results screen.
static func reason(decision: int, enabled: bool = true) -> String:
	if not enabled:
		return "Adaptive difficulty is switched off in Settings, so the next shift follows the normal curve."
	match decision:
		HARDER:
			return "You cleared that shift quickly with few mistakes and retries, so the next one will be harder."
		EASIER:
			return "That shift was a struggle, so the next one will be gentler."
		_:
			return "The next shift will stay balanced."


static func label(decision: int) -> String:
	match decision:
		HARDER:
			return "HARDER"
		EASIER:
			return "EASIER"
		_:
			return "BALANCED"


## Everything about one cleared shift, as a dictionary for the results screen and the tests:
## ratio (this shift), average (smoothed), decision, steps (the adaptation for the next shift),
## changed (whether the steps moved) and reason. `enabled` false keeps the steps at 0.
static func evaluate(spent: float, start_reserve: float, mistakes: int, retries: int, previous_ratio: float, current_steps: int, enabled: bool = true) -> Dictionary:
	var ratio := clampf(spent / maxf(start_reserve, 1.0), 0.0, 1.0)
	var average := averaged(ratio, previous_ratio)
	var decision := decide(average, mistakes, retries) if enabled else SAME
	var steps := next_steps(current_steps, decision) if enabled else 0
	return {
		"ratio": ratio,
		"average": average,
		"decision": decision,
		"steps": steps,
		"changed": steps != current_steps,
		"reason": reason(decision, enabled),
		"enabled": enabled,
	}
