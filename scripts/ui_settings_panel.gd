class_name SettingsPanel
extends PanelContainer
## The Settings window: music and effects volume, mouse speed, rebinding the keys, and the
## accessibility options (text beside colours, captions for sounds). It edits the SaveManager's
## settings, saves them, and tells the game through `changed`. It never touches game rules.

signal changed
signal closed
signal preview_sound   ## play a short sound so the effects volume can be judged

var _save: SaveManager
var _capturing: String = ""              # the action waiting for a key, "" when none
var _key_buttons: Dictionary = {}         # action id -> Button
var _message: Label
var _value_labels: Dictionary = {}        # name -> Label showing a slider's value


static func create(save: SaveManager) -> SettingsPanel:
	var panel := SettingsPanel.new()
	panel._save = save
	panel._build()
	return panel


func is_capturing() -> bool:
	return _capturing != ""


func _build() -> void:
	add_theme_stylebox_override("panel", UiStyle.panel_style())
	custom_minimum_size = Vector2(600, 0)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 18)
	add_child(margin)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 10)
	margin.add_child(outer)
	outer.add_child(_label("SETTINGS", 30, Rules.COLOR_CYAN))

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(560, 150)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(scroll)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(column)

	column.add_child(_section("AUDIO"))
	column.add_child(_slider_row("music", "Music volume", 0.0, 100.0, 5.0, _save.music_volume * 100.0, _on_music_volume))
	column.add_child(_slider_row("sfx", "Effects volume", 0.0, 100.0, 5.0, _save.sfx_volume * 100.0, _on_sfx_volume))

	column.add_child(_section("CONTROLS"))
	column.add_child(_slider_row("sens", "Mouse speed", SaveManager.SENS_MIN * 100.0, SaveManager.SENS_MAX * 100.0, 5.0, _save.mouse_sens * 100.0, _on_sensitivity))
	column.add_child(_label("Click a key, then press the new one. Esc cancels.", 16, Color(1, 1, 1, 0.65)))
	for entry in KeyBindings.ACTIONS:
		column.add_child(_key_row(entry["id"], entry["label"]))
	var reset := _button("Reset keys to default", _on_reset_keys)
	column.add_child(reset)

	column.add_child(_section("GAMEPLAY"))
	column.add_child(_check("Adaptive difficulty (the next shift gets harder or easier depending on how you did)", _save.adaptive, _on_adaptive))
	column.add_child(_section("ACCESSIBILITY"))
	column.add_child(_check("Colour-blind cues (a word beside each red / cyan signal)", _save.cues, _on_cues))
	column.add_child(_check("Sound captions (a line of text when an alarm or hazard sounds)", _save.captions, _on_captions))
	column.add_child(_label("Captions also show whenever sound is muted (N).", 16, Color(1, 1, 1, 0.65)))

	_message = _label("", 18, Rules.COLOR_GOLD)
	outer.add_child(_message)
	outer.add_child(_button("Close (Esc)", func() -> void: closed.emit()))


func _section(text: String) -> Label:
	return _label(text, 20, Rules.COLOR_GOLD)


func _slider_row(id: String, text: String, low: float, high: float, step: float, value: float, handler: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var name_label := _label(text, 20, Color.WHITE)
	name_label.custom_minimum_size = Vector2(170, 0)
	row.add_child(name_label)
	var slider := HSlider.new()
	slider.min_value = low
	slider.max_value = high
	slider.step = step
	slider.value = value
	slider.custom_minimum_size = Vector2(240, 28)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.name = "Slider_" + id
	row.add_child(slider)
	var value_label := _label("%d%%" % int(value), 20, Rules.COLOR_GOLD)
	value_label.custom_minimum_size = Vector2(60, 0)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_value_labels[id] = value_label
	row.add_child(value_label)
	slider.value_changed.connect(func(v: float) -> void:
		value_label.text = "%d%%" % int(v)
		handler.call(v))
	return row


func _key_row(action: String, text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var name_label := _label(text, 20, Color.WHITE)
	name_label.custom_minimum_size = Vector2(240, 0)
	row.add_child(name_label)
	var button := _button(KeyBindings.key_text(int(_save.bindings[action])), func() -> void: _start_capture(action), 150)
	button.name = "Key_" + action
	_key_buttons[action] = button
	row.add_child(button)
	return row


func _check(text: String, on: bool, handler: Callable) -> CheckButton:
	var box := CheckButton.new()
	box.text = text
	box.button_pressed = on
	box.add_theme_font_size_override("font_size", 18)
	box.toggled.connect(handler)
	return box


func _label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


func _button(text: String, action: Callable, min_width: int = 0) -> Button:
	var button := Button.new()
	button.text = text
	button.add_theme_font_size_override("font_size", 20)
	button.custom_minimum_size = Vector2(min_width, 40)
	button.pressed.connect(action)
	return button


# --- Handlers --------------------------------------------------------------

func _on_music_volume(value: float) -> void:
	_save.music_volume = value / 100.0
	_save.save_settings()
	changed.emit()


func _on_sfx_volume(value: float) -> void:
	_save.sfx_volume = value / 100.0
	_save.save_settings()
	changed.emit()
	preview_sound.emit()


func _on_sensitivity(value: float) -> void:
	_save.mouse_sens = value / 100.0
	_save.save_settings()
	changed.emit()


func _on_cues(on: bool) -> void:
	_save.cues = on
	_save.save_settings()
	changed.emit()


func _on_adaptive(on: bool) -> void:
	_save.adaptive = on
	_save.save_settings()
	changed.emit()


func _on_captions(on: bool) -> void:
	_save.captions = on
	_save.save_settings()
	changed.emit()


func _on_reset_keys() -> void:
	_cancel_capture()
	_save.reset_keys()
	for action in _key_buttons:
		(_key_buttons[action] as Button).text = KeyBindings.key_text(int(_save.bindings[action]))
	_message.text = "Keys reset to default."
	changed.emit()


func _start_capture(action: String) -> void:
	_cancel_capture()
	_capturing = action
	(_key_buttons[action] as Button).text = "Press a key..."
	_message.text = "Press the new key for \"%s\". Esc cancels." % KeyBindings.label_of(action)


func _cancel_capture() -> void:
	if _capturing != "":
		(_key_buttons[_capturing] as Button).text = KeyBindings.key_text(int(_save.bindings[_capturing]))
		_capturing = ""


## While a key is awaited, the next key press is the new binding (before anything else sees it).
func _input(event: InputEvent) -> void:
	if _capturing == "" or not (event is InputEventKey):
		return
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return
	get_viewport().set_input_as_handled()
	var code := int(key_event.physical_keycode)
	if code == KeyBindings.RESERVED_KEY:
		_cancel_capture()
		_message.text = "Cancelled."
		return
	var clash := KeyBindings.conflict(_save.bindings, _capturing, code)
	if clash != "":
		_message.text = "%s is already used for \"%s\". Pick another key." % [KeyBindings.key_text(code), KeyBindings.label_of(clash)]
		return
	_save.bindings[_capturing] = code
	_save.save_settings()
	(_key_buttons[_capturing] as Button).text = KeyBindings.key_text(code)
	_message.text = "\"%s\" is now %s." % [KeyBindings.label_of(_capturing), KeyBindings.key_text(code)]
	_capturing = ""
	changed.emit()
