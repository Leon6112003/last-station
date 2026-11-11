class_name LogPanel
extends PanelContainer
## A small reading panel for one crew log. Like the manuals it pauses the game while it is
## open, so reading never costs reserve. It only shows text.

signal closed

var _title: String = ""
var _body: String = ""
var _footer: String = ""


static func create(title: String, body: String, footer: String) -> LogPanel:
	var panel := LogPanel.new()
	panel._title = title
	panel._body = body
	panel._footer = footer
	panel._build()
	return panel


func _build() -> void:
	custom_minimum_size = Vector2(620, 0)
	add_theme_stylebox_override("panel", UiStyle.panel_style())
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 22)
	add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	margin.add_child(column)
	column.add_child(_label(_title, 24, Rules.COLOR_CYAN))
	var body := _label(_body, 21, Color.WHITE)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size = Vector2(570, 0)
	column.add_child(body)
	column.add_child(_label(_footer, 18, Rules.COLOR_GOLD))
	var close := Button.new()
	close.text = "Close (Esc)"
	close.add_theme_font_size_override("font_size", 22)
	close.custom_minimum_size = Vector2(0, 48)
	close.pressed.connect(func() -> void: closed.emit())
	column.add_child(close)


func _label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label
