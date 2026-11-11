class_name PuzzlePanel
extends PanelContainer
## Small modal panels for the three puzzles that need numeric input:
## the oxygen valves, the comms frequency tuner and the cooling flow.
## The panel only forwards button presses to GameManager, which decides
## whether the settings are correct.

signal closed
signal solved

var _gm: GameManager
var _kind: String = ""
var _value_labels: Array[Label] = []
var _message: Label
var _pad_buttons: Array[Button] = []
var _progress_label: Label
var _show_button: Button
var _showing: bool = false
var _show_tween: Tween
var instant: bool = false            ## tests: show the sequence at once instead of animating it
const PAD_COLORS: Array[Color] = [Color(0.55, 0.4, 0.9), Color(1.0, 0.84, 0.54), Color(0.42, 0.92, 0.85), Color(0.95, 0.5, 0.45)]


static func create(kind: String, gm: GameManager) -> PuzzlePanel:
	var panel := PuzzlePanel.new()
	panel._gm = gm
	panel._kind = kind
	panel._build()
	return panel


func refresh() -> void:
	if _kind == "oxygen":
		for i in _value_labels.size():
			_value_labels[i].text = "%d" % _gm.oxygen_values[i]
	elif _kind == "reboot":
		_progress_label.text = "ENTERED %d / %d" % [_gm.reboot_progress.size(), (_gm.puzzles["reboot"]["sequence"] as Array).size()]
		_show_button.text = "SHOW SEQUENCE" if not _gm.reboot_free_view_used else "SHOW SEQUENCE AGAIN  (-%d s)" % Rules.replay_cost()
	elif _kind == "cooling":
		_value_labels[0].text = "%d L/s" % _gm.coolant_flow
	else:
		_value_labels[0].text = "%d MHz" % _gm.tuner_mhz


func _build() -> void:
	custom_minimum_size = Vector2(440, 0)
	add_theme_stylebox_override("panel", UiStyle.panel_style())
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	margin.add_child(column)

	var titles := {"oxygen": "VALVE CONTROLS", "comms": "FREQUENCY TUNER", "cooling": "COOLANT CONTROL", "reboot": "REBOOT CODE"}
	column.add_child(_make_label(titles[_kind], 28, Rules.COLOR_CYAN))

	if _kind == "oxygen":
		for i in 3:
			column.add_child(_valve_row(i))
		column.add_child(_make_button("CONFIRM SETTINGS", _on_confirm_oxygen))
	elif _kind == "reboot":
		column.add_child(_pad_row())
		_progress_label = _make_label("", 20, Rules.COLOR_GOLD)
		column.add_child(_progress_label)
		_show_button = _make_button("SHOW SEQUENCE", _on_show_pressed)
		column.add_child(_show_button)
	elif _kind == "cooling":
		# The same readings that are on the wall, repeated here because the panel hides the wall.
		var cooling: Dictionary = _gm.puzzles["cooling"]
		column.add_child(_make_label("CORE TEMP %d K  ·  REACTOR %s" % [int(cooling["temp"]), cooling["state"]], 20, Color.WHITE))
		column.add_child(_coolant_row())
		column.add_child(_make_button("ENGAGE COOLING", _on_engage_cooling))
	else:
		column.add_child(_tuner_row())
		column.add_child(_make_button("TRANSMIT", _on_transmit))

	_message = _make_label("", 20, Rules.COLOR_GOLD)
	_message.custom_minimum_size = Vector2(0, 28)
	column.add_child(_message)
	column.add_child(_make_button("Close (Esc)", func() -> void: closed.emit()))
	refresh()
	if _kind == "reboot":
		# The first showing of the sequence in a shift is free and starts by itself.
		call_deferred("_start_first_showing")


func _valve_row(index: int) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var name_label := _make_label("VALVE %s" % char(65 + index), 22, Color.WHITE)
	name_label.custom_minimum_size = Vector2(120, 0)
	row.add_child(name_label)
	row.add_child(_make_button("-", func() -> void: _adjust_valve(index, -1), 52))
	var value := _make_label("0", 24, Rules.COLOR_GOLD)
	value.custom_minimum_size = Vector2(80, 0)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_value_labels.append(value)
	row.add_child(value)
	row.add_child(_make_button("+", func() -> void: _adjust_valve(index, 1), 52))
	return row


func _tuner_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.add_child(_make_button("-20", func() -> void: _adjust_tuner(-4), 56))
	row.add_child(_make_button("-5", func() -> void: _adjust_tuner(-1), 56))
	var value := _make_label("100 MHz", 24, Rules.COLOR_GOLD)
	value.custom_minimum_size = Vector2(120, 0)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_value_labels.append(value)
	row.add_child(value)
	row.add_child(_make_button("+5", func() -> void: _adjust_tuner(1), 56))
	row.add_child(_make_button("+20", func() -> void: _adjust_tuner(4), 56))
	return row


## Four pads in a row, each with a letter and its own colour (so they never rely on colour alone).
func _pad_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	for i in Rules.SEQ_PAD_COUNT:
		var pad := Button.new()
		pad.text = Rules.SEQ_PAD_NAMES[i]
		pad.add_theme_font_size_override("font_size", 40)
		pad.custom_minimum_size = Vector2(90, 90)
		pad.add_theme_color_override("font_color", PAD_COLORS[i])
		pad.add_theme_stylebox_override("normal", _pad_style(PAD_COLORS[i], false))
		pad.add_theme_stylebox_override("hover", _pad_style(PAD_COLORS[i], true))
		pad.add_theme_stylebox_override("pressed", _pad_style(PAD_COLORS[i], true))
		pad.add_theme_stylebox_override("disabled", _pad_style(PAD_COLORS[i], false))
		pad.pressed.connect(func() -> void: _on_pad(i))
		_pad_buttons.append(pad)
		row.add_child(pad)
	return row


func _pad_style(color: Color, lit: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(color, 0.85) if lit else Color(color, 0.12)
	style.border_color = color
	style.set_border_width_all(3)
	style.set_corner_radius_all(8)
	return style


func _start_first_showing() -> void:
	if not _gm.reboot_free_view_used:
		_gm.request_sequence_view()   # free
		_show_sequence()
		refresh()


func _on_show_pressed() -> void:
	if _showing:
		return
	var cost := _gm.request_sequence_view()
	if cost < 0:
		_message.text = "Not enough reserve to show it again."
		return
	_message.text = ""
	_show_sequence()
	refresh()


## Lights the pads one at a time in the flashed order. The pads cannot be pressed meanwhile.
func _show_sequence() -> void:
	if _show_tween != null:
		_show_tween.kill()
	_showing = true
	_set_pads_enabled(false)
	_message.text = "Watch the lights..."
	var sequence: Array = _gm.puzzles["reboot"]["sequence"]
	if instant:
		finish_showing()
		return
	_show_tween = create_tween()
	for pad in sequence:
		var index := int(pad)
		_show_tween.tween_callback(_light_pad.bind(index, true))
		_show_tween.tween_interval(Rules.SEQ_STEP_SECONDS * 0.7)
		_show_tween.tween_callback(_light_pad.bind(index, false))
		_show_tween.tween_interval(Rules.SEQ_STEP_SECONDS * 0.3)
	_show_tween.tween_callback(finish_showing)


func finish_showing() -> void:
	if _show_tween != null:
		_show_tween.kill()
	for i in _pad_buttons.size():
		_light_pad(i, false)
	_showing = false
	_set_pads_enabled(true)
	_message.text = "Your turn."


func _light_pad(index: int, on: bool) -> void:
	_pad_buttons[index].add_theme_stylebox_override("disabled", _pad_style(PAD_COLORS[index], on))


func _set_pads_enabled(enabled: bool) -> void:
	for pad in _pad_buttons:
		pad.disabled = not enabled


func is_showing() -> bool:
	return _showing


func _on_pad(index: int) -> void:
	if _showing:
		return
	match _gm.press_reboot_pad(index):
		"done":
			refresh()
			solved.emit()
		"wrong":
			refresh()
			_show_sequence()   # the sequence is shown again, free, after a mistake
			_message.text = "WRONG CODE  -%d s" % Rules.confirm_penalty()
		"ok":
			_message.text = ""
			refresh()


func _coolant_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.add_child(_make_button("-5", func() -> void: _adjust_coolant(-5), 56))
	row.add_child(_make_button("-1", func() -> void: _adjust_coolant(-1), 56))
	var value := _make_label("0 L/s", 24, Rules.COLOR_GOLD)
	value.custom_minimum_size = Vector2(120, 0)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_value_labels.append(value)
	row.add_child(value)
	row.add_child(_make_button("+1", func() -> void: _adjust_coolant(1), 56))
	row.add_child(_make_button("+5", func() -> void: _adjust_coolant(5), 56))
	return row


func _adjust_coolant(steps: int) -> void:
	_gm.adjust_coolant(steps)
	_message.text = ""
	refresh()


func _on_engage_cooling() -> void:
	if _gm.engage_cooling():
		solved.emit()
	else:
		_message.text = "PUMP OVERLOAD  -%d s" % Rules.confirm_penalty()


func _adjust_valve(index: int, steps: int) -> void:
	_gm.adjust_valve(index, steps)
	_message.text = ""
	refresh()


func _adjust_tuner(steps: int) -> void:
	_gm.adjust_tuner(steps)
	_message.text = ""
	refresh()


func _on_confirm_oxygen() -> void:
	if _gm.confirm_oxygen():
		solved.emit()
	else:
		_message.text = "PRESSURE MISMATCH  -%d s" % Rules.confirm_penalty()


func _on_transmit() -> void:
	if _gm.transmit():
		solved.emit()
	else:
		_message.text = "NO SIGNAL  -%d s" % Rules.confirm_penalty()


func _make_label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


func _make_button(text: String, action: Callable, min_width: int = 0) -> Button:
	var button := Button.new()
	button.text = text
	button.add_theme_font_size_override("font_size", 22)
	button.custom_minimum_size = Vector2(min_width, 48)
	button.pressed.connect(action)
	return button
