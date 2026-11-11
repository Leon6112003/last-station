extends SceneTree
## Developer tool: saves the theme song as a WAV file so it can be played outside the game.
##   godot --headless --path . -s res://tools/export_theme.gd -- /path/to/theme.wav

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var path := args[0] if args.size() > 0 else "/tmp/last_station_theme.wav"
	var error := ThemeMusic.build().save_to_wav(path)
	print("saved %s (error code %d)" % [path, error])
	quit(0 if error == OK else 1)
