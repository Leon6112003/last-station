class_name MenuScreen
extends Control
## The main menu: an animated survival-style title screen drawn entirely in code
## (drifting stars, a dark planet with a glowing rim, a pulsing emergency vignette,
## a flickering title, and a failing life-support readout). It also plays a short
## typed "wake-up" intro the first time the game opens (any key or click skips it).
## It only shows things and calls the callables it was given; it never touches rules.

const STAR_COUNT := 140
const INTRO_LINES := [
	"DAY 412",
	"A SYSTEM FAILURE HAS HIT THE STATION.",
	"THE CREW ARE IN CRYO-SLEEP.",
	"THE OXYGEN RESERVE IS FALLING.",
	"YOU ARE THE LAST ONE AWAKE.",
]
const INTRO_CHARS_PER_SECOND := 38.0
const INTRO_LINE_PAUSE := 0.55
const INTRO_END_PAUSE := 0.6
const FLICKER_MIN_SECONDS := 2.5
const FLICKER_MAX_SECONDS := 6.0

## Shown under the title; set by main.gd each time the menu opens.
var best_label: Label

var _stars: Array[Dictionary] = []
var _time: float = 0.0
var _column: VBoxContainer
var _title: Label
var _status_panel: PanelContainer
var _status_title: Label
var _oxygen_bar: ProgressBar
var _warning_label: Label
var _vignette: TextureRect
var _intro_label: Label
var _intro_hint: Label
var _intro_active: bool = false
var _intro_time: float = 0.0
var _flicker_timer: float = 3.0
var _flicker_left: int = 0
var _level_buttons: Array[Button] = []
var _level_blurb: Label


## Builds the menu. `play_intro` is true only in a real window on launch.
## With `on_level` (a callable taking the chosen level number) the menu also shows the
## difficulty selector, starting on `level`.
static func create(on_play: Callable, on_how_to_play: Callable, on_quit: Callable, play_intro: bool, on_level: Callable = Callable(), level: int = Rules.LEVEL_ENGINEER) -> MenuScreen:
	var screen := MenuScreen.new()
	screen._build(on_play, on_how_to_play, on_quit, play_intro, on_level, level)
	return screen


## Shows which level is in use. The buttons are not highlighted when the menu opens; a
## button lights up only once the player clicks it (`highlight`). The line under the buttons
## always names the level in use.
func set_level(level: int, highlight: bool = false) -> void:
	if _level_buttons.is_empty():
		return
	var index := clampi(level, 0, Rules.LEVEL_NAMES.size() - 1)
	for i in _level_buttons.size():
		_level_buttons[i].set_pressed_no_signal(highlight and i == index)
	_level_blurb.text = "%s: %s" % [Rules.LEVEL_NAMES[index], Rules.LEVEL_BLURBS[index]]


func _build(on_play: Callable, on_how_to_play: Callable, on_quit: Callable, play_intro: bool, on_level: Callable, level: int) -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var rng := RandomNumberGenerator.new()
	rng.seed = 412
	for i in STAR_COUNT:
		_stars.append({
			"x": rng.randf(), "y": rng.randf() * 0.8, "size": rng.randf_range(1.0, 2.6),
			"speed": rng.randf_range(0.002, 0.012), "phase": rng.randf() * TAU,
		})

	# Emergency vignette: red screen edges that pulse slowly.
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.45, 1.0])
	gradient.colors = PackedColorArray([Color(Rules.COLOR_FAULT, 0.0), Color(Rules.COLOR_FAULT, 0.55)])
	var vignette_texture := GradientTexture2D.new()
	vignette_texture.gradient = gradient
	vignette_texture.fill = GradientTexture2D.FILL_RADIAL
	vignette_texture.fill_from = Vector2(0.5, 0.5)
	vignette_texture.fill_to = Vector2(1.0, 0.5)
	vignette_texture.width = 256
	vignette_texture.height = 256
	_vignette = TextureRect.new()
	_vignette.texture = vignette_texture
	_vignette.stretch_mode = TextureRect.STRETCH_SCALE
	_vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_vignette)

	# Blinking warning at the top.
	_warning_label = _make_label("LIFE SUPPORT FAILING", 22, Rules.COLOR_FAULT)
	_warning_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_warning_label.anchor_left = 0.0
	_warning_label.anchor_right = 1.0
	_warning_label.offset_top = 28
	_warning_label.offset_bottom = 64
	add_child(_warning_label)

	# Centre column: title, subtitle, best scores, buttons.
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	_column = VBoxContainer.new()
	_column.add_theme_constant_override("separation", 10)
	center.add_child(_column)

	_title = _make_label("LAST STATION", 92, Rules.COLOR_CYAN)
	_title.add_theme_color_override("font_outline_color", Color(Rules.COLOR_CYAN, 0.28))
	_title.add_theme_constant_override("outline_size", 14)
	_column.add_child(_title)

	var subtitle := _make_label("The crew are asleep. Only you can repair the station.", 24, Rules.COLOR_VIOLET.lightened(0.25))
	_column.add_child(subtitle)
	var tagline := _make_label("Fix it before the air runs out.", 20, Color(1, 1, 1, 0.7))
	_column.add_child(tagline)

	best_label = _make_label("", 22, Rules.COLOR_GOLD)
	_column.add_child(best_label)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 2)
	_column.add_child(gap)

	if on_level.is_valid():
		_build_level_selector(on_level, level)
	var play := _make_button("Play", on_play, true)
	_column.add_child(play)
	_column.add_child(_make_button("How to Play", on_how_to_play, false))
	_column.add_child(_make_button("Quit", on_quit, false))

	_build_status_panel()

	# Intro: typed lines over a dark screen; the menu appears afterwards.
	_intro_label = _make_label("", 30, Rules.COLOR_CYAN)
	_intro_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_intro_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_intro_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_intro_label)
	_intro_hint = _make_label("press any key to skip", 18, Color(1, 1, 1, 0.45))
	_intro_hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_intro_hint.anchor_left = 0.0
	_intro_hint.anchor_right = 1.0
	_intro_hint.offset_top = -56
	_intro_hint.offset_bottom = -20
	add_child(_intro_hint)
	_set_menu_visible(not play_intro)
	_intro_active = play_intro
	_intro_label.visible = play_intro
	_intro_hint.visible = play_intro


func _build_status_panel() -> void:
	_status_panel = PanelContainer.new()
	_status_panel.anchor_left = 0.0
	_status_panel.anchor_right = 0.0
	_status_panel.anchor_top = 1.0
	_status_panel.anchor_bottom = 1.0
	_status_panel.offset_left = 32
	_status_panel.offset_right = 312
	_status_panel.offset_top = -176
	_status_panel.offset_bottom = -32
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.03, 0.04, 0.09, 0.8)
	style.border_color = Color(Rules.COLOR_FAULT, 0.7)
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(14)
	_status_panel.add_theme_stylebox_override("panel", style)
	_status_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_status_panel)

	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 6)
	_status_panel.add_child(rows)
	_status_title = _make_label("STATION STATUS: CRITICAL", 18, Rules.COLOR_FAULT)
	_status_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	rows.add_child(_status_title)
	rows.add_child(_make_gauge("POWER", 4.0, Rules.COLOR_FAULT, false))
	var oxygen_row := _make_gauge("OXYGEN", 22.0, Rules.COLOR_GOLD, true)
	_oxygen_bar = oxygen_row.get_child(1) as ProgressBar
	rows.add_child(oxygen_row)
	rows.add_child(_make_gauge("COMMS", 0.0, Rules.COLOR_FAULT, false))


## One labelled gauge row (a name and a bar; the bar is child 1 of the row).
func _make_gauge(label_text: String, value: float, color: Color, _drains: bool) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var name_label := _make_label(label_text, 16, Color(1, 1, 1, 0.85))
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	name_label.custom_minimum_size = Vector2(70, 0)
	row.add_child(name_label)
	var bar := ProgressBar.new()
	bar.min_value = 0.0
	bar.max_value = 100.0
	bar.value = value
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(156, 16)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	fill.set_corner_radius_all(2)
	var back := StyleBoxFlat.new()
	back.bg_color = Color(1, 1, 1, 0.08)
	back.set_corner_radius_all(2)
	bar.add_theme_stylebox_override("fill", fill)
	bar.add_theme_stylebox_override("background", back)
	row.add_child(bar)
	return row


func _make_label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


## Three level choices side by side (Rookie, Engineer, Survivor) and a one-line
## description of the chosen level.
func _build_level_selector(on_level: Callable, level: int) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	_column.add_child(row)
	var group := ButtonGroup.new()
	for i in Rules.LEVEL_NAMES.size():
		var button := _make_button(Rules.LEVEL_NAMES[i], func() -> void: pass, false)
		button.custom_minimum_size = Vector2(150, 42)
		button.add_theme_font_size_override("font_size", 20)
		button.toggle_mode = true
		button.button_group = group
		var chosen := _button_style(Color(Rules.COLOR_GOLD, 0.35), Rules.COLOR_GOLD)
		button.add_theme_stylebox_override("pressed", chosen)
		button.add_theme_stylebox_override("hover_pressed", chosen)
		button.focus_mode = Control.FOCUS_NONE   # only the chosen level lights up, not the focused one
		button.add_theme_color_override("font_pressed_color", Rules.COLOR_GOLD)
		button.pressed.connect(func() -> void:
			on_level.call(i)
			set_level(i, true))
		row.add_child(button)
		_level_buttons.append(button)
	_level_blurb = _make_label("", 18, Color(1, 1, 1, 0.7))
	_column.add_child(_level_blurb)
	set_level(level)


func _make_button(text: String, action: Callable, primary: bool) -> Button:
	var button := Button.new()
	button.text = text
	button.add_theme_font_size_override("font_size", 24)
	button.custom_minimum_size = Vector2(320, 56)
	var accent: Color = Rules.COLOR_GOLD if primary else Rules.COLOR_CYAN
	button.add_theme_stylebox_override("normal", _button_style(Color(0.05, 0.07, 0.16, 0.88), Color(accent, 0.55)))
	button.add_theme_stylebox_override("hover", _button_style(Color(accent, 0.2), accent))
	button.add_theme_stylebox_override("pressed", _button_style(Color(accent, 0.35), accent))
	button.add_theme_stylebox_override("focus", _button_style(Color(accent, 0.12), Rules.COLOR_GOLD))
	button.add_theme_color_override("font_hover_color", accent)
	button.add_theme_color_override("font_focus_color", Color.WHITE)
	button.pressed.connect(action)
	return button


func _button_style(fill: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(8)
	return style


func _set_menu_visible(shown: bool) -> void:
	_column.visible = shown
	_status_panel.visible = shown
	_warning_label.visible = shown


## Ends the intro at once and shows the menu.
func skip_intro() -> void:
	if not _intro_active:
		return
	_intro_active = false
	_intro_label.visible = false
	_intro_hint.visible = false
	_set_menu_visible(true)
	_column.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(_column, "modulate:a", 1.0, 0.6)


func is_intro_active() -> bool:
	return _intro_active


func _input(event: InputEvent) -> void:
	if not _intro_active or not is_visible_in_tree():
		return
	var pressed := false
	if event is InputEventKey:
		pressed = (event as InputEventKey).pressed and not (event as InputEventKey).echo
	elif event is InputEventMouseButton:
		pressed = (event as InputEventMouseButton).pressed
	if pressed:
		skip_intro()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_time += delta
	queue_redraw()
	# The red vignette breathes; the warning blinks.
	_vignette.modulate.a = 0.12 + 0.22 * (0.5 + 0.5 * sin(_time * 1.6))
	_warning_label.modulate.a = 1.0 if fmod(_time, 1.2) < 0.8 else 0.25
	_status_title.modulate.a = 1.0 if fmod(_time, 1.6) < 1.1 else 0.55
	# Oxygen slowly drains, then the gauge resets (decoration only).
	_oxygen_bar.value = 24.0 - fmod(_time, 14.0) * 1.2 + sin(_time * 7.0) * 0.6
	_update_flicker(delta)
	if _intro_active:
		_update_intro(delta)


## The title occasionally stutters like a failing neon sign.
func _update_flicker(delta: float) -> void:
	_flicker_timer -= delta
	if _flicker_timer <= 0.0 and _flicker_left == 0:
		_flicker_left = 6
		_flicker_timer = 0.06
	if _flicker_left > 0:
		if _flicker_timer <= 0.0:
			_flicker_left -= 1
			_flicker_timer = 0.05
			_title.modulate.a = 0.25 if _flicker_left % 2 == 1 else 1.0
			if _flicker_left == 0:
				_title.modulate.a = 1.0
				_flicker_timer = randf_range(FLICKER_MIN_SECONDS, FLICKER_MAX_SECONDS)


## Types the intro lines one after another, then reveals the menu.
func _update_intro(delta: float) -> void:
	_intro_time += delta
	var shown := ""
	var cursor := 0.0
	var finished := true
	for line in INTRO_LINES:
		var typing_time: float = float(String(line).length()) / INTRO_CHARS_PER_SECOND
		var local := _intro_time - cursor
		if local <= 0.0:
			finished = false
			break
		if local < typing_time:
			shown += String(line).substr(0, int(local * INTRO_CHARS_PER_SECOND)) + "_"
			finished = false
			break
		shown += String(line) + "\n\n"
		cursor += typing_time + INTRO_LINE_PAUSE
	_intro_label.text = shown
	if finished and _intro_time >= cursor + INTRO_END_PAUSE:
		skip_intro()


func _draw() -> void:
	var size_now := size
	# Background gradient: near-black navy at the top to a deep violet at the horizon.
	var top := Color8(6, 8, 22)
	var bottom := Color8(30, 18, 58)
	draw_polygon(
		PackedVector2Array([Vector2.ZERO, Vector2(size_now.x, 0.0), size_now, Vector2(0.0, size_now.y)]),
		PackedColorArray([top, top, bottom, bottom]))
	# Stars drift left and twinkle.
	for star in _stars:
		var x := fposmod(float(star["x"]) - _time * float(star["speed"]), 1.0) * size_now.x
		var y: float = float(star["y"]) * size_now.y
		var twinkle := 0.55 + 0.45 * sin(_time * 2.0 + float(star["phase"]))
		draw_circle(Vector2(x, y), float(star["size"]), Color(0.85, 0.92, 1.0, twinkle * 0.9))
	# A dark planet rising from below, with a glowing atmosphere rim.
	var planet_center := Vector2(size_now.x * 0.5, size_now.y * 2.05)
	var planet_radius := size_now.y * 1.28
	draw_circle(planet_center, planet_radius, Color8(12, 14, 34))
	for i in 5:
		var spread := float(i) * 3.0
		draw_arc(planet_center, planet_radius + spread, deg_to_rad(215.0), deg_to_rad(325.0), 120,
			Color(Rules.COLOR_CYAN, 0.32 - float(i) * 0.06), 3.0 + spread * 0.5, true)
	# A tiny drifting satellite crossing the sky: a reminder that nobody is coming.
	var sat_x := fposmod(_time * 0.012, 1.2) * size_now.x - size_now.x * 0.1
	var sat_y := size_now.y * 0.22 + sin(_time * 0.4) * 6.0
	draw_rect(Rect2(Vector2(sat_x - 5.0, sat_y - 2.0), Vector2(10.0, 4.0)), Color(0.7, 0.75, 0.9, 0.8))
	draw_rect(Rect2(Vector2(sat_x - 14.0, sat_y - 1.0), Vector2(8.0, 2.0)), Color(Rules.COLOR_CYAN, 0.6))
	draw_rect(Rect2(Vector2(sat_x + 6.0, sat_y - 1.0), Vector2(8.0, 2.0)), Color(Rules.COLOR_CYAN, 0.6))
	# Faint scan lines.
	var y_line := 0.0
	while y_line < size_now.y:
		draw_line(Vector2(0.0, y_line), Vector2(size_now.x, y_line), Color(0.0, 0.0, 0.0, 0.12), 1.0)
		y_line += 4.0
