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
# Settings (the Settings window): volumes, mouse speed, accessibility options and the keys.
var music_volume: float = 1.0        # 0 to 1
var sfx_volume: float = 1.0          # 0 to 1
var mouse_sens: float = 1.0          # a multiplier on the normal mouse speed, 0.25 to 3
var cues: bool = true                # text beside colours (for colour-blind players)
var captions: bool = false           # a caption when an alarm or hazard sounds
var bindings: Dictionary = KeyBindings.default_keys()
const SENS_MIN := 0.25
const SENS_MAX := 3.0
var modifiers: int = 0               # the modifiers picked on the menu (Rules.MOD_ flags)
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
	music_volume = clampf(float(config.get_value(SECTION, "music_volume", 1.0)), 0.0, 1.0)
	sfx_volume = clampf(float(config.get_value(SECTION, "sfx_volume", 1.0)), 0.0, 1.0)
	mouse_sens = clampf(float(config.get_value(SECTION, "mouse_sens", 1.0)), SENS_MIN, SENS_MAX)
	cues = bool(config.get_value(SECTION, "cues", true))
	captions = bool(config.get_value(SECTION, "captions", false))
	var loaded := {}
	for entry in KeyBindings.ACTIONS:
		loaded[entry["id"]] = int(config.get_value(SECTION, "key_" + String(entry["id"]), entry["key"]))
	bindings = KeyBindings.normalized(loaded)
	modifiers = clampi(int(config.get_value(SECTION, "modifiers", 0)), 0, Rules.MODS_ALL)
	difficulty = clampi(int(config.get_value(SECTION, "difficulty", Rules.LEVEL_ENGINEER)), Rules.LEVEL_ROOKIE, Rules.LEVEL_SURVIVOR)


func save_data() -> bool:
	var config := ConfigFile.new()
	config.set_value(SECTION, "best_score", best_score)
	config.set_value(SECTION, "best_run", best_run)
	config.set_value(SECTION, "intro_seen", intro_seen)
	config.set_value(SECTION, "difficulty", difficulty)
	config.set_value(SECTION, "modifiers", modifiers)
	config.set_value(SECTION, "music_volume", music_volume)
	config.set_value(SECTION, "sfx_volume", sfx_volume)
	config.set_value(SECTION, "mouse_sens", mouse_sens)
	config.set_value(SECTION, "cues", cues)
	config.set_value(SECTION, "captions", captions)
	for action in bindings:
		config.set_value(SECTION, "key_" + String(action), int(bindings[action]))
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


## Saves the Settings window's values (call after changing any of them).
func save_settings() -> void:
	music_volume = clampf(music_volume, 0.0, 1.0)
	sfx_volume = clampf(sfx_volume, 0.0, 1.0)
	mouse_sens = clampf(mouse_sens, SENS_MIN, SENS_MAX)
	bindings = KeyBindings.normalized(bindings)
	save_data()


## Back to the default keys.
func reset_keys() -> void:
	bindings = KeyBindings.default_keys()
	save_data()


## Remembers the modifiers picked on the menu.
func set_modifiers(value: int) -> void:
	modifiers = clampi(value, 0, Rules.MODS_ALL)
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
