class_name SaveManager
extends RefCounted
## Tiny local save file: best score and whether the intro card was seen.
## Failures to read or write never crash the game.

const SECTION := "last_station"

var path: String
var best_score: int = 0
var best_run: int = 0
var intro_seen: bool = false
var difficulty: int = Rules.LEVEL_ENGINEER   # the level picked on the menu
var logs_read: int = 0               # a bit for each crew log read (bit 0 = log 1)


func _init(save_path: String = "user://last_station.cfg") -> void:
	path = save_path
	load_data()


func load_data() -> void:
	var config := ConfigFile.new()
	if config.load(path) != OK:
		return  # no save yet, or unreadable: start fresh
	best_score = maxi(0, int(config.get_value(SECTION, "best_score", 0)))
	best_run = maxi(0, int(config.get_value(SECTION, "best_run", 0)))
	intro_seen = bool(config.get_value(SECTION, "intro_seen", false))
	logs_read = clampi(int(config.get_value(SECTION, "logs_read", 0)), 0, (1 << CrewLogs.count()) - 1)
	difficulty = clampi(int(config.get_value(SECTION, "difficulty", Rules.LEVEL_ENGINEER)), Rules.LEVEL_ROOKIE, Rules.LEVEL_SURVIVOR)


func save_data() -> bool:
	var config := ConfigFile.new()
	config.set_value(SECTION, "best_score", best_score)
	config.set_value(SECTION, "best_run", best_run)
	config.set_value(SECTION, "intro_seen", intro_seen)
	config.set_value(SECTION, "difficulty", difficulty)
	config.set_value(SECTION, "logs_read", logs_read)
	var error := config.save(path)
	if error != OK:
		push_warning("Could not save %s (error %d)" % [path, error])
		return false
	return true


## Records a finished score. Returns true if it is a new best.
func record_score(score: int) -> bool:
	if score <= best_score:
		return false
	best_score = score
	save_data()
	return true


## Records a run total (the sum of the shifts cleared in one run). Returns true if it is a new best.
func record_run(total: int) -> bool:
	if total <= best_run:
		return false
	best_run = total
	save_data()
	return true


## Remembers the level picked on the menu.
func set_difficulty(level: int) -> void:
	difficulty = clampi(level, Rules.LEVEL_ROOKIE, Rules.LEVEL_SURVIVOR)
	save_data()


## Remembers that crew log `number` (1 to 4) was read.
func mark_log_read(number: int) -> void:
	if number < 1 or number > CrewLogs.count():
		return
	var bit := 1 << (number - 1)
	if logs_read & bit == 0:
		logs_read |= bit
		save_data()


func logs_read_count() -> int:
	var count := 0
	for n in CrewLogs.count():
		if logs_read & (1 << n) != 0:
			count += 1
	return count


func mark_intro_seen() -> void:
	intro_seen = true
	save_data()
