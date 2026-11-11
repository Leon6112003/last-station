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
	difficulty = clampi(int(config.get_value(SECTION, "difficulty", Rules.LEVEL_ENGINEER)), Rules.LEVEL_ROOKIE, Rules.LEVEL_SURVIVOR)


func save_data() -> bool:
	var config := ConfigFile.new()
	config.set_value(SECTION, "best_score", best_score)
	config.set_value(SECTION, "best_run", best_run)
	config.set_value(SECTION, "intro_seen", intro_seen)
	config.set_value(SECTION, "difficulty", difficulty)
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


func mark_intro_seen() -> void:
	intro_seen = true
	save_data()
