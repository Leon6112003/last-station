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

	var titles := {"oxygen": "VALVE CONTROLS", "comms": "FREQUENCY TUNER", "cooling": "COOLANT CONTROL"}
	column.add_child(_make_label(titles[_kind], 28, Rules.COLOR_CYAN))

	if _kind == "oxygen":
		for i in 3:
			column.add_child(_valve_row(i))
		column.add_child(_make_button("CONFIRM SETTINGS", _on_confirm_oxygen))
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
