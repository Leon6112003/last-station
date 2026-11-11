extends SceneTree
## Settings: volumes, mouse speed, key rebinding, the saved values, and the accessibility
## options (shape cues beside colours, captions for sounds), in the Settings window and in the
## running game.
## Run:  godot --headless --path . -s res://tests/test_settings.gd

const SAVE_PATH := "user://test_settings_save.cfg"

var _failures: int = 0


func _initialize() -> void:
	_remove_save()
	_test_save()
	_test_key_bindings()
	await _test_sound_volume()
	await _test_panel()
	await _test_game()
	await _test_cues_and_captions()
	_remove_save()
	print("")
	if _failures == 0:
		print("ALL PASS")
		quit(0)
	else:
		print("%d FAILURE(S)" % _failures)
		quit(1)


func _test_save() -> void:
	var save := SaveManager.new(SAVE_PATH)
	_check(save.music_volume == 1.0 and save.sfx_volume == 1.0 and save.mouse_sens == 1.0 and save.cues and not save.captions, "a new save has default settings (full volume, normal mouse speed, cues on, captions off)")
	_check(save.bindings == KeyBindings.default_keys(), "and the default keys")
	save.music_volume = 0.4
	save.sfx_volume = 0.0
	save.mouse_sens = 1.75
	save.cues = false
	save.captions = true
	save.bindings["interact"] = KEY_F
	save.save_settings()
	var again := SaveManager.new(SAVE_PATH)
	_check(is_equal_approx(again.music_volume, 0.4) and again.sfx_volume == 0.0 and is_equal_approx(again.mouse_sens, 1.75) and not again.cues and again.captions and again.bindings["interact"] == KEY_F, "every setting is remembered")
	again.music_volume = 9.0
	again.mouse_sens = 0.0
	again.save_settings()
	var clamped := SaveManager.new(SAVE_PATH)
	_check(clamped.music_volume == 1.0 and clamped.mouse_sens == SaveManager.SENS_MIN, "out-of-range values are clamped")
	clamped.reset_keys()
	_check(SaveManager.new(SAVE_PATH).bindings == KeyBindings.default_keys(), "reset puts the keys back to default")
	_remove_save()


func _test_key_bindings() -> void:
	KeyBindings.apply({})
	_check(InputMap.has_action("move_forward") and InputMap.has_action("pause_game") and InputMap.has_action("toggle_sound"), "applying the defaults registers every action")
	var forward_keys := InputMap.action_get_events("move_forward").map(func(e: InputEvent) -> int: return int((e as InputEventKey).physical_keycode))
	_check(forward_keys.has(KEY_W) and forward_keys.has(KEY_UP), "movement keeps W and the arrow key by default")
	_check(KeyBindings.help_text({}) == "WASD Move  ·  E Interact  ·  V View  ·  C Front  ·  M Manuals  ·  H ORACLE  ·  Esc Pause  ·  Hold R Retry", "the help line is the same as before with the default keys")
	var custom := KeyBindings.default_keys()
	custom["interact"] = KEY_F
	custom["move_forward"] = KEY_UP   # takes the arrow key that forward used as its extra
	KeyBindings.apply(custom)
	var interact_keys := InputMap.action_get_events("interact").map(func(e: InputEvent) -> int: return int((e as InputEventKey).physical_keycode))
	_check(interact_keys == [KEY_F], "a rebound action uses only its new key")
	var up_users := 0
	for entry in KeyBindings.ACTIONS:
		for event in InputMap.action_get_events(entry["id"]):
			if (event as InputEventKey).physical_keycode == KEY_UP:
				up_users += 1
	_check(up_users == 1, "a key is never given to two actions (the arrow stays with the action that was bound to it)")
	_check(KeyBindings.help_text(custom).contains("F Interact"), "the help line shows the new key")
	_check(KeyBindings.conflict(custom, "interact", KEY_M) == "toggle_manuals", "a key already in use is reported with its action")
	_check(KeyBindings.conflict(custom, "interact", KEY_F) == "", "an action's own key is not a conflict")
	_check(KeyBindings.conflict(custom, "interact", KEY_ESCAPE) == KeyBindings.PAUSE_ACTION, "Escape is reserved")
	var broken := {"interact": KEY_M, "toggle_manuals": KEY_M, "retry_level": KEY_ESCAPE, "toggle_view": -5}
	var fixed := KeyBindings.normalized(broken)
	var seen := {}
	var unique := true
	for action in fixed:
		var key := int(fixed[action])
		unique = unique and not seen.has(key)
		if key != 0:
			seen[key] = true
	_check(unique and fixed["retry_level"] == KEY_R and fixed["toggle_view"] == KEY_V and fixed.size() == KeyBindings.ACTIONS.size(), "bad or clashing saved keys are repaired, never crash")
	KeyBindings.apply({})


func _test_sound_volume() -> void:
	_check(SoundBank.volume_offset_db(1.0) == 0.0 and absf(SoundBank.volume_offset_db(0.5) + 6.02) < 0.05 and SoundBank.volume_offset_db(0.0) == -80.0, "a volume of 100%, 50% and 0% is 0 dB, about -6 dB and silent")
	var bank := SoundBank.new()
	root.add_child(bank)
	await process_frame   # the bank builds its sounds when it is ready
	var heard: Array[String] = []
	bank.played.connect(func(sound_name: String) -> void: heard.append(sound_name))
	bank.sfx_volume = 0.0
	bank.play("alarm")
	bank.muted = true
	bank.sfx_volume = 1.0
	bank.play("click")
	_check(heard.size() == 2 and heard[0] == "alarm" and heard[1] == "click", "a sound is still announced when it is muted or at volume 0, so it can be captioned")
	bank.muted = false
	bank.music_volume = 0.5
	_check(absf(bank.music_db() - (SoundBank.MUSIC_DB - 6.02)) < 0.05, "the music volume lowers the music")
	bank.free()


func _test_panel() -> void:
	var save := SaveManager.new(SAVE_PATH)
	var panel := SettingsPanel.create(save)
	root.add_child(panel)
	await process_frame
	var changes := [0]
	var closed := [0]
	panel.changed.connect(func() -> void: changes[0] += 1)
	panel.closed.connect(func() -> void: closed[0] += 1)
	var music: HSlider = panel.find_child("Slider_music", true, false)
	var sens: HSlider = panel.find_child("Slider_sens", true, false)
	music.value = 30.0
	_check(is_equal_approx(save.music_volume, 0.3) and changes[0] == 1 and SaveManager.new(SAVE_PATH).music_volume == save.music_volume, "moving the music slider changes and saves the volume")
	sens.value = 200.0
	_check(is_equal_approx(save.mouse_sens, 2.0), "the mouse speed slider is a multiplier (200% = 2.0)")
	var previewed := [0]
	panel.preview_sound.connect(func() -> void: previewed[0] += 1)
	(panel.find_child("Slider_sfx", true, false) as HSlider).value = 40.0
	_check(is_equal_approx(save.sfx_volume, 0.4) and previewed[0] == 1, "the effects slider plays a preview sound")
	# Rebinding.
	var key_button: Button = panel.find_child("Key_interact", true, false)
	key_button.pressed.emit()
	_check(panel.is_capturing() and key_button.text == "Press a key...", "clicking a key waits for the next key")
	var clash := InputEventKey.new()
	clash.physical_keycode = KEY_M
	clash.pressed = true
	panel._input(clash)
	_check(panel.is_capturing() and save.bindings["interact"] == KEY_E and panel._message.text.contains("already used"), "a key that is already used is refused with a message, and the panel keeps waiting")
	var good := InputEventKey.new()
	good.physical_keycode = KEY_G
	good.pressed = true
	panel._input(good)
	_check(not panel.is_capturing() and save.bindings["interact"] == KEY_G and key_button.text == "G" and SaveManager.new(SAVE_PATH).bindings["interact"] == KEY_G, "a free key is bound, shown and saved")
	var other: Button = panel.find_child("Key_toggle_view", true, false)
	other.pressed.emit()
	var escape := InputEventKey.new()
	escape.physical_keycode = KEY_ESCAPE
	escape.pressed = true
	panel._input(escape)
	_check(not panel.is_capturing() and save.bindings["toggle_view"] == KEY_V and other.text == "V", "Esc cancels a rebind and keeps the old key")
	var release := InputEventKey.new()
	release.physical_keycode = KEY_G
	release.pressed = false
	other.pressed.emit()
	panel._input(release)
	_check(panel.is_capturing(), "releasing a key does not bind it")
	panel._cancel_capture()
	panel._on_reset_keys()
	_check(save.bindings == KeyBindings.default_keys() and key_button.text == "E", "Reset keys restores the defaults and the buttons")
	panel._on_cues(false)
	panel._on_captions(true)
	_check(not save.cues and save.captions, "the accessibility switches are saved")
	(panel.find_children("*", "Button", true, false).filter(func(b: Node) -> bool: return (b as Button).text.begins_with("Close"))[0] as Button).pressed.emit()
	_check(closed[0] == 1, "Close closes the window")
	panel.free()
	await process_frame
	_remove_save()


func _new_main() -> Node:
	_remove_save()
	SaveManager.new(SAVE_PATH).mark_intro_seen()
	var main: Node = load("res://scenes/main.tscn").instantiate()
	main.save_path = SAVE_PATH
	root.add_child(main)
	await process_frame
	return main


func _test_game() -> void:
	var main := await _new_main()
	_check(InputMap.has_action("interact") and main._help_label.text.contains("E Interact"), "the game registers the saved keys and shows them in the help line")
	main._start_new_game()
	await process_frame
	_check(is_equal_approx(main._player.mouse_sensitivity, Rules.MOUSE_SENSITIVITY), "the mouse speed starts at normal")
	main._open_settings()
	_check(main._settings_panel != null and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "Settings opens and frees the mouse")
	main.save.mouse_sens = 2.0
	main.save.music_volume = 0.25
	main.save.sfx_volume = 0.5
	main.save.bindings["interact"] = KEY_F
	main._settings_panel.changed.emit()
	_check(is_equal_approx(main._player.mouse_sensitivity, Rules.MOUSE_SENSITIVITY * 2.0) and is_equal_approx(main.sound.music_volume, 0.25) and is_equal_approx(main.sound.sfx_volume, 0.5), "changes reach the running player and sound")
	_check(main._help_label.text.contains("F Interact"), "the help line follows a rebound key")
	var f_events := InputMap.action_get_events("interact").map(func(e: InputEvent) -> int: return int((e as InputEventKey).physical_keycode))
	_check(f_events == [KEY_F], "the new key is live in the InputMap")
	var escape := InputEventAction.new()
	escape.action = "pause_game"
	escape.pressed = true
	main._unhandled_input(escape)
	_check(main._settings_panel == null and not main._paused, "Esc closes Settings, not the whole game state")
	main._set_paused(true)
	main._open_settings()
	_check(main._settings_panel != null and main._pause_overlay.visible, "Settings opens from the pause menu too")
	main._unhandled_input(escape)
	_check(main._settings_panel == null and main._paused, "closing it returns to the pause menu")
	main._set_paused(false)
	# From the main menu.
	main._go_to_menu()
	main._menu_screen.settings_requested.emit()
	_check(main._settings_panel != null, "the menu's Settings button opens it")
	main._close_settings()
	# The prompt shows the bound key.
	main.queue_free()
	await process_frame
	KeyBindings.apply({})


func _test_cues_and_captions() -> void:
	var main := await _new_main()
	main._start_new_game()
	await process_frame
	var icons: Dictionary = main._station["door_icons"]
	_check(icons.size() == 4, "each of the four rooms has a cross and a tick icon")
	_check((icons["power"]["fault"] as Node3D).visible and not (icons["power"]["ok"] as Node3D).visible, "with cues on, a faulted room shows a cross")
	var gas: HazardZone = main._station["hazards"][0]
	gas.tick(0.0, false)
	_check(gas._phase_label.visible and gas._phase_label.text.begins_with("GAS:"), "with cues on, the gas lamp has a word beside it")
	main.gm.repaired["power"] = true
	main._update_cues()
	_check(not (icons["power"]["fault"] as Node3D).visible and (icons["power"]["ok"] as Node3D).visible, "a repaired room shows a tick instead")
	main.save.cues = false
	main._apply_settings()
	gas.tick(0.0, false)
	_check(not (icons["power"]["ok"] as Node3D).visible and not (icons["oxygen"]["fault"] as Node3D).visible and not gas._phase_label.visible, "with cues off, no icon or gas word is shown")
	main.save.cues = true
	main.gm.reserve = 30.0
	main._process(0.016)
	_check(main._reserve_label.text.ends_with("LOW"), "with cues on a low reserve says LOW as well as turning red")
	main.save.cues = false
	main._process(0.016)
	_check(not main._reserve_label.text.contains("LOW"), "and not with cues off")
	main.gm.reserve = 300.0
	# Captions.
	main.save.captions = false
	main.sound.muted = false
	main.sound.play("alarm")
	_check(main._captions.is_empty(), "no caption when captions are off and sound is on")
	main.save.captions = true
	main.sound.play("alarm")
	_check(main._captions.size() == 1 and String(main._captions[0]["text"]).begins_with("ALARM"), "with captions on, the alarm is captioned")
	main.sound.play("alarm")
	_check(main._captions.size() == 1, "the same sound again keeps one line")
	main.sound.play("gasleak")
	main.sound.play("spark")
	main.sound.play("creak")
	_check(main._captions.size() == 3 and not main._captions.any(func(c: Dictionary) -> bool: return String(c["text"]).begins_with("ALARM")), "at most three lines show, the oldest drops off")
	main.sound.play("step")
	_check(main._captions.size() == 3, "ordinary sounds such as footsteps are not captioned")
	main._process(0.016)
	_check(main._caption_label.text.contains("GAS VENTING"), "the captions are drawn on the HUD")
	for line in main._captions:
		line["until"] = 0.0
	main._process(0.016)
	_check(main._captions.is_empty() and main._caption_label.text == "", "captions fade away after a few seconds")
	main.save.captions = false
	main.sound.muted = true
	main.sound.play("door_lock")
	_check(main._captions.size() == 1, "captions show whenever sound is muted, even if the option is off")
	main.sound.muted = false
	main.save.sfx_volume = 0.0
	main._captions.clear()
	main.sound.sfx_volume = 0.0
	main.sound.play("door_slide")
	_check(main._captions.size() == 1, "and when the effects volume is 0")
	main._captions.clear()
	main.sound.sfx_volume = 1.0
	main.save.sfx_volume = 1.0
	main.gm.state = GameManager.State.WON
	main.save.captions = true
	main.sound.play("alarm")
	_check(main._captions.is_empty(), "no captions on the win or lose screens")
	main.queue_free()
	await process_frame
	KeyBindings.apply({})


func _remove_save() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS  " + label)
	else:
		print("FAIL  " + label)
		_failures += 1
