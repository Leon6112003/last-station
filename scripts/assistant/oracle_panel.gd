class_name OraclePanel
extends PanelContainer
## The ORACLE chat window (press H). Plain Labels only, so nothing the player
## types and nothing the model writes can be interpreted as markup.
## Every answer is followed by the exact manual excerpts it was based on.

signal closed
signal hint_requested
signal question_sent   ## a question was accepted (the game charges its reserve cost)

var controller: OracleController

var _header: Label
var _scroll: ScrollContainer
var _log: VBoxContainer
var _status: Label
var _input: LineEdit
var _send: Button
var _hint_button: Button


static func create(oracle: OracleController) -> OraclePanel:
	var panel := OraclePanel.new()
	panel.controller = oracle
	panel._build()
	oracle.answered.connect(panel._on_answered)
	oracle.busy_changed.connect(panel._on_busy_changed)
	return panel


## Sends a question as if the player typed it. Returns true if accepted.
func submit_text(text: String) -> bool:
	if controller.busy:
		return false
	var shown := OracleLogic.sanitize_question(text)
	if shown.is_empty():
		return false
	# Add the question first: exact answers arrive instantly, inside ask().
	_add_line("You: %s" % shown, Color.WHITE, 20)
	_input.clear()
	question_sent.emit()
	return controller.ask(text)


func _build() -> void:
	custom_minimum_size = Vector2(880, 0)
	add_theme_stylebox_override("panel", UiStyle.panel_style())
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)

	_header = Label.new()
	_header.text = OracleLogic.HEADER_BASIC
	_header.add_theme_font_size_override("font_size", 28)
	_header.add_theme_color_override("font_color", Rules.COLOR_CYAN)
	column.add_child(_header)

	_scroll = ScrollContainer.new()
	_scroll.custom_minimum_size = Vector2(0, 340)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(_scroll)

	_log = VBoxContainer.new()
	_log.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_log.add_theme_constant_override("separation", 8)
	_scroll.add_child(_log)
	_add_line("I am ORACLE. Ask me how the station's systems work: the rules for Power, Oxygen and Comms under each protocol, the controls, or scoring. I answer from the manuals. Every question costs 5 seconds of oxygen reserve, so the manuals (M) are the free way. I cannot see your rooms, so tell me what you read on the panels, for example: \"protocol B, power room, restore mode\". For rules and numbers I quote the manual exactly. For other questions I can write a short answer if Ollama is running.", Rules.COLOR_VIOLET, 20)

	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 18)
	_status.add_theme_color_override("font_color", Rules.COLOR_GOLD)
	_status.custom_minimum_size = Vector2(0, 24)
	column.add_child(_status)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	column.add_child(row)

	_input = LineEdit.new()
	_input.max_length = OracleLogic.MAX_QUESTION
	_input.placeholder_text = "Type a question and press Enter"
	_input.add_theme_font_size_override("font_size", 22)
	_input.custom_minimum_size = Vector2(0, 48)
	_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_input.text_submitted.connect(func(text: String) -> void: submit_text(text))
	_input.gui_input.connect(_on_input_gui_input)
	row.add_child(_input)

	_send = Button.new()
	_send.text = "Send"
	_send.add_theme_font_size_override("font_size", 22)
	_send.custom_minimum_size = Vector2(110, 48)
	_send.pressed.connect(func() -> void: submit_text(_input.text))
	row.add_child(_send)

	_hint_button = Button.new()
	_hint_button.text = "Get a hint  (-%d s of oxygen reserve)" % Rules.HINT_COST_SECONDS
	_hint_button.add_theme_font_size_override("font_size", 20)
	_hint_button.custom_minimum_size = Vector2(0, 44)
	_hint_button.pressed.connect(func() -> void: hint_requested.emit())
	column.add_child(_hint_button)

	var close := Button.new()
	close.text = "Close (Esc)"
	close.add_theme_font_size_override("font_size", 22)
	close.custom_minimum_size = Vector2(0, 48)
	close.pressed.connect(func() -> void: closed.emit())
	column.add_child(close)


func _ready() -> void:
	# On a small window the chat area shrinks so the whole panel stays on screen.
	var window_height := get_viewport().get_visible_rect().size.y
	_scroll.custom_minimum_size.y = clampf(window_height - 360.0, 120.0, 340.0)


## Shows the result of a hint request (the game, not the AI, computes the hint).
## result = {ok: bool, text: String, cost: int}
func show_hint(result: Dictionary) -> void:
	var prefix := "HINT (-%d s)" % result["cost"] if int(result["cost"]) > 0 else "HINT"
	if not result["ok"]:
		prefix = "NO HINT"
	var label := _add_line("%s: %s" % [prefix, result["text"]], Rules.COLOR_GOLD, 22)
	_scroll_to_label.call_deferred(label)


## Shows what the question cost, in the chat.
func add_cost_line(seconds: int) -> void:
	if seconds > 0:
		_add_line("(asking ORACLE cost %d s of oxygen reserve; the manuals are free)" % seconds, Rules.COLOR_FAULT, 16)


func focus_input() -> void:
	_input.grab_focus()


# A focused LineEdit would swallow Esc, so handle it here.
func _on_input_gui_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause_game"):
		_input.accept_event()
		closed.emit()


func _on_busy_changed(is_busy: bool) -> void:
	_send.disabled = is_busy
	_status.text = "ORACLE is thinking..." if is_busy else ""


func _on_answered(result: Dictionary) -> void:
	_header.text = result["header"]
	var answer_label := _add_line("ORACLE: %s" % result["answer"], Rules.COLOR_CYAN, 22)
	var sources: Array = result["sources"]
	if not sources.is_empty():
		_add_line("Full manual entries:", Rules.COLOR_GOLD, 18)
		for source in sources:
			_add_line("[%s] %s" % [source["id"], source["text"]], Color(1, 1, 1, 0.75), 18)
	_scroll_to_label.call_deferred(answer_label)


func _add_line(text: String, color: Color, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(800, 0)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	_log.add_child(label)
	_scroll_to_end.call_deferred()
	return label


## Shows the top of a new answer (the sources below it can be scrolled to).
func _scroll_to_label(label: Label) -> void:
	await get_tree().process_frame
	if is_instance_valid(_scroll) and is_instance_valid(label):
		_scroll.scroll_vertical = maxi(0, int(label.position.y) - 6)


func _scroll_to_end() -> void:
	if is_instance_valid(_scroll):
		_scroll.scroll_vertical = int(_scroll.get_v_scroll_bar().max_value)
