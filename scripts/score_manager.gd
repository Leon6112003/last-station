class_name ScoreManager
extends RefCounted
## Score formula (REQUIREMENTS.md section E). Pure functions.
##   base          = 300
##   time_bonus    = floor(reserve_remaining / 2)
##   retry_penalty = min(150, 50 * retries)
##   final         = max(0, base + time_bonus - retry_penalty) x the level multiplier
##                   (Rookie 0.6, Engineer 1.0, Survivor 1.4, rounded)


static func time_bonus(reserve_seconds: float) -> int:
	return maxi(0, int(floor(reserve_seconds / float(Rules.TIME_BONUS_DIVISOR))))


static func retry_penalty(retries: int) -> int:
	return mini(Rules.RETRY_PENALTY_MAX, Rules.RETRY_PENALTY_STEP * maxi(0, retries))


static func final_score(reserve_seconds: float, retries: int) -> int:
	var points := maxi(0, Rules.BASE_POINTS + time_bonus(reserve_seconds) - retry_penalty(retries))
	return int(round(float(points) * Rules.score_multiplier()))


static func breakdown(reserve_seconds: float, retries: int) -> Dictionary:
	return {
		"base": Rules.BASE_POINTS,
		"time_bonus": time_bonus(reserve_seconds),
		"retry_penalty": retry_penalty(retries),
		"multiplier": Rules.score_multiplier(),
		"final": final_score(reserve_seconds, retries),
	}
