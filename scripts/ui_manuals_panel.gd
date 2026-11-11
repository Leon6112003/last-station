class_name ManualsPanel
extends PanelContainer
## Browsable station manuals (no AI). Titles on the left, text on the right.
## Plain Labels only, so no markup in the manuals can ever be interpreted.

signal closed

var _records: Array = []
var _list: ItemList
var _title: Label
var _body: Label


static func create(records: Array) -> ManualsPanel:
	var panel := ManualsPanel.new()
	panel._records = records
	panel._build()
	return panel


func _build() -> void:
	custom_minimum_size = Vector2(860, 0)
	add_theme_stylebox_override("panel", UiStyle.panel_style())
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	margin.add_child(column)

	var heading := Label.new()
	heading.text = "STATION MANUALS"
	heading.add_theme_font_size_override("font_size", 30)
	heading.add_theme_color_override("font_color", Rules.COLOR_CYAN)
	column.add_child(heading)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	column.add_child(row)

	_list = ItemList.new()
	_list.custom_minimum_size = Vector2(290, 360)
	_list.add_theme_font_size_override("font_size", 20)
	for record in _records:
		_list.add_item(record["title"])
	_list.item_selected.connect(_show_record)
	row.add_child(_list)

	var text_column := VBoxContainer.new()
	text_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_column.add_theme_constant_override("separation", 10)
	row.add_child(text_column)

	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 26)
	_title.add_theme_color_override("font_color", Rules.COLOR_GOLD)
	text_column.add_child(_title)

	_body = Label.new()
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.custom_minimum_size = Vector2(480, 0)
	_body.add_theme_font_size_override("font_size", 22)
	text_column.add_child(_body)

	var close := Button.new()
	close.text = "Close (M or Esc)"
	close.add_theme_font_size_override("font_size", 22)
	close.custom_minimum_size = Vector2(0, 48)
	close.pressed.connect(func() -> void: closed.emit())
	column.add_child(close)

	if _records.is_empty():
		_title.text = "No manuals found"
		_body.text = "The manuals file could not be loaded."
	else:
		_list.select(0)
		_show_record(0)


func _show_record(index: int) -> void:
	if index < 0 or index >= _records.size():
		return
	var record: Dictionary = _records[index]
	_title.text = record["title"]
	_body.text = record["text"]
