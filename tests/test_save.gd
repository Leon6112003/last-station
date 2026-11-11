extends SceneTree
## Save file behaviour: best score, intro flag, corrupt and unwritable files.
## Run:  godot --headless --path . -s res://tests/test_save.gd

const PATH := "user://test_save_unit.cfg"

var _failures: int = 0


func _initialize() -> void:
	_remove(PATH)

	var fresh := SaveManager.new(PATH)
	_check(fresh.best_score == 0 and not fresh.intro_seen, "a missing save file gives defaults")

	_check(fresh.record_score(300), "a first score is a new best")
	_check(not fresh.record_score(250), "a lower score is not a new best")
	_check(not fresh.record_score(300), "an equal score is not a new best")
	_check(fresh.record_score(450), "a higher score is a new best")
	_check(fresh.best_score == 450, "best score is the maximum (got %d)" % fresh.best_score)

	fresh.mark_intro_seen()
	var reloaded := SaveManager.new(PATH)
	_check(reloaded.best_score == 450, "best score persists across loads")
	_check(reloaded.intro_seen, "intro_seen persists across loads")

	# A corrupt file must not crash and must fall back to defaults.
	var file := FileAccess.open(PATH, FileAccess.WRITE)
	file.store_string("this is [not a valid\nconfig = = file")
	file.close()
	var corrupt := SaveManager.new(PATH)
	_check(corrupt.best_score == 0 and not corrupt.intro_seen, "a corrupt save file falls back to defaults")

	# An unwritable location must not crash; the score still counts in memory.
	var unwritable := SaveManager.new("user://no_such_folder_xyz/save.cfg")
	var counted := unwritable.record_score(100)
	_check(counted and unwritable.best_score == 100, "an unwritable save path does not crash")

	_remove(PATH)
	print("")
	if _failures == 0:
		print("ALL PASS")
		quit(0)
	else:
		print("%d FAILURE(S)" % _failures)
		quit(1)


func _remove(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS  ", label)
	else:
		print("FAIL  ", label)
		_failures += 1
