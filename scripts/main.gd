extends Node
## Entry point. Registers input, owns the GameManager, builds the world, HUD,
## menus and overlays from code, and reacts to GameManager signals.
## Milestone 3: Main Menu, how-to-play card, hold-R retry, Manuals panel and a
## saved best score. ORACLE (the chatbot) arrives in Milestone 4.

const HELP_TEXT := "WASD Move  ·  E Interact  ·  M Manuals  ·  H ORACLE  ·  Esc Pause  ·  Hold R Retry"
const NOTICE_SECONDS := 2.5
const MODAL_WIDTH := 860.0

const HOW_TO_PLAY_TEXT := """MISSION
The Last Station has lost power. The crew are asleep in hibernation
and the oxygen reserve is running out. The station's old help
system, ORACLE, remembers how every system works. You are the
only one awake who can repair them.

GOAL
Repair Power, Oxygen and Comms, then press E on the reboot
terminal in the hub, before the reserve reaches zero.

HOW
There are no instructions in the rooms. Read the panels, then ask
ORACLE (H) or open the Manuals (M) to learn the rule. The rules
change with the station PROTOCOL shown at the top left.

CONTROLS
WASD move  ·  Mouse look  ·  E interact  ·  M manuals
H ask ORACLE  ·  Esc pause  ·  Hold R for 1 second to retry"""

const MISTAKE_TEXT := {
	"power": "POWER SURGE",
	"oxygen": "PRESSURE MISMATCH",
	"comms": "NO SIGNAL",
}

## Where the best score is saved. Tests change this before the node is added.
var save_path: String = "user://last_station.cfg"

var gm: GameManager
var save: SaveManager
var oracle: OracleController

var _rng := RandomNumberGenerator.new()
var _records: Array = []
var _world: Node3D
var _player: PlayerController
var _station: Dictionary = {}

var _hud_layer: CanvasLayer
var _shift_label: Label
var _systems_label: Label
var _checklist_label: Label
var _coach_label: Label
var _reserve_label: Label
var _prompt_label: Label
var _notice_label: Label
var _flash: ColorRect
var _notice_timer: Timer
var _retry_box: Control
var _retry_bar: ProgressBar
var _pause_overlay: Control
var _menu_layer: CanvasLayer
var _menu_best_label: Label
var _panel_center: CenterContainer
var _panel: PuzzlePanel = null
var _manuals: ManualsPanel = null
var _oracle_panel: OraclePanel = null
var _modal_layer: CanvasLayer = null
var _paused: bool = false
var _input_free: bool = false
var _retry_hold: float = 0.0
var _retry_locked: bool = false


func _ready() -> void:
	# Main keeps running while the tree is paused so Esc can resume.
	# The world and the GameManager are explicitly pausable.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.randomize()
	_setup_input()
	save = SaveManager.new(save_path)
	_records = KnowledgeBase.load_records()

	gm = GameManager.new()
	gm.name = "GameManager"
	gm.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(gm)
	gm.system_repaired.connect(_on_system_repaired)
	gm.mistake_made.connect(_on_mistake_made)
	gm.shift_won.connect(_on_shift_won)
	gm.shift_failed.connect(_on_shift_failed)

	# ORACLE: read-only help. It sees only the sanitized snapshot below.
	oracle = OracleController.new()
	oracle.name = "OracleController"
	oracle.records = _records
	oracle.snapshot_provider = _oracle_snapshot
	add_child(oracle)
	var ollama := OllamaClient.new()
	ollama.name = "OllamaClient"
	add_child(ollama)
	oracle.set_client(ollama)

	_build_hud()
	_build_pause_overlay()
	_build_panel_layer()
	_build_menu()
	_go_to_menu()


func _process(delta: float) -> void:
	var seconds_left := int(ceil(gm.reserve))
	_reserve_label.text = "RESERVE %02d:%02d" % [floori(seconds_left / 60.0), seconds_left % 60]
	_reserve_label.add_theme_color_override(
		"font_color", Rules.COLOR_FAULT if gm.reserve < 60.0 else Color.WHITE)
	_systems_label.text = "SYSTEMS %d/%d" % [gm.repaired_count(), Rules.SYSTEMS_TOTAL]
	_shift_label.text = "SHIFT %02d" % gm.run_number
	var checklist := _checklist_text()
	if checklist != _checklist_label.text:
		_checklist_label.text = checklist
	var coach := _coach_text()
	if coach != _coach_label.text:
		_coach_label.text = coach
	_update_retry_hold(delta)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause_game"):
		if gm.state == GameManager.State.MENU or _modal_layer != null:
			return
		if _oracle_panel != null:
			_close_oracle()
		elif _manuals != null:
			_close_manuals()
		elif _panel != null:
			_close_panel()
		else:
			_set_paused(not _paused)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("toggle_oracle"):
		if _oracle_panel != null:
			_close_oracle()
			get_viewport().set_input_as_handled()
		elif _can_open_overlay():
			_open_oracle()
			get_viewport().set_input_as_handled()
	elif event.is_action_pressed("toggle_manuals"):
		if _manuals != null:
			_close_manuals()
			get_viewport().set_input_as_handled()
		elif _can_open_overlay():
			_open_manuals()
			get_viewport().set_input_as_handled()


## Shift 1 is a guided shift: one line says what to do next. Empty on later shifts.
func _coach_text() -> String:
	if gm.run_number != 1 or gm.state != GameManager.State.PLAYING:
		return ""
	if gm.repaired_count() == Rules.SYSTEMS_TOTAL:
		return "All systems repaired! Go back to the hub and press E on the reboot terminal."
	for id in GameManager.SYSTEM_IDS:
		if gm.repaired.get(id, false):
			continue
		match id:
			"power":
				return "NEXT: POWER room (left door). Read LOAD MODE and the breaker voltages, then press H and ask ORACLE which breaker first."
			"oxygen":
				return "NEXT: OXYGEN room (middle door). Read STATION MODE, then press H and ask ORACLE for the valve settings."
			_:
				return "NEXT: COMMS room (right door). Count the lit beacons, then press H and ask ORACLE for the frequency."
	return ""


## The on-screen objective list: which systems are repaired and what is next.
func _checklist_text() -> String:
	var rooms := {"power": "left room", "oxygen": "middle room", "comms": "right room"}
	var protocol: String = gm.puzzles.get("protocol", "A")
	var lines: Array[String] = ["REPAIR THE STATION  ·  PROTOCOL %s" % protocol]
	for id in GameManager.SYSTEM_IDS:
		var mark := "[x]" if gm.repaired.get(id, false) else "[ ]"
		lines.append("%s %s (%s)" % [mark, id.capitalize(), rooms[id]])
	if gm.repaired_count() == Rules.SYSTEMS_TOTAL:
		lines.append("-> REBOOT: terminal in the hub")
	else:
		lines.append("[ ] Reboot (needs 3/3)")
	return "\n".join(lines)


func _new_seed() -> int:
	return _rng.randi()


func _can_open_overlay() -> bool:
	return (gm.state == GameManager.State.PLAYING and not _paused
		and _panel == null and _manuals == null and _oracle_panel == null and _modal_layer == null)


# --- Input map ----------------------------------------------------------

func _setup_input() -> void:
	_add_action("move_forward", [KEY_W, KEY_UP])
	_add_action("move_backward", [KEY_S, KEY_DOWN])
	_add_action("move_left", [KEY_A, KEY_LEFT])
	_add_action("move_right", [KEY_D, KEY_RIGHT])
	_add_action("interact", [KEY_E])
	_add_action("pause_game", [KEY_ESCAPE])
	_add_action("retry_level", [KEY_R])
	_add_action("toggle_manuals", [KEY_M])
	_add_action("toggle_oracle", [KEY_H])     # used from Milestone 4


func _add_action(action: StringName, keys: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for key in keys:
		var event := InputEventKey.new()
		event.physical_keycode = key
		InputMap.action_add_event(action, event)


# --- Game flow ------------------------------------------------------------

## Main Menu > Play: a brand new run with a new seed. The intro card is shown
## once, the first time the game is played.
func _start_new_game() -> void:
	_menu_layer.visible = false
	_hud_layer.visible = true
	gm.start_shift(_new_seed(), 1)
	_rebuild_world()
	if not save.intro_seen:
		_show_how_to_play(true)


## Leaves the current shift completely: frees the world, clears every overlay,
## and shows the Main Menu.
func _go_to_menu() -> void:
	_close_panel()
	_close_manuals()
	_close_oracle()
	_close_modal()
	_free_world()
	_paused = false
	get_tree().paused = false
	_pause_overlay.visible = false
	_hud_layer.visible = false
	gm.enter_menu()
	var best_parts: Array[String] = []
	if save.best_score > 0:
		best_parts.append("Best shift score: %d" % save.best_score)
	if save.best_run > 0:
		best_parts.append("Best run: %d" % save.best_run)
	_menu_best_label.text = "   ·   ".join(best_parts)
	_menu_layer.visible = true
	_refresh_input_state()


func _free_world() -> void:
	if _world != null:
		remove_child(_world)
		_world.queue_free()
		_world = null
	_player = null
	_station = {}


func _retry() -> void:
	gm.retry()
	_rebuild_world()


func _next_shift() -> void:
	gm.start_shift(_new_seed(), gm.run_number + 1)
	_rebuild_world()


## Frees the old world completely and builds a fresh one for the current
## attempt (so retries show the re-rolled puzzle values).
func _rebuild_world() -> void:
	_close_panel()
	_close_manuals()
	_close_oracle()
	_close_modal()
	_free_world()

	_world = Node3D.new()
	_world.name = "World"
	_world.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(_world)

	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Rules.COLOR_NAVY
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Rules.COLOR_INDIGO
	environment.ambient_light_energy = 0.8
	# A light navy haze gives the corridors depth without hiding the labels.
	environment.fog_enabled = true
	environment.fog_light_color = Rules.COLOR_NAVY.lightened(0.1)
	environment.fog_density = 0.012
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	_world.add_child(world_environment)

	_station = StationBuilder.build(_world, gm.puzzles)

	_player = PlayerController.new()
	_player.name = "Player"
	_player.position = _station["spawn"]
	_world.add_child(_player)
	_player.target_changed.connect(_on_target_changed)
	_player.first_move.connect(gm.begin_clock)

	for item in _station["interactables"]:
		(item as Interactable).interacted.connect(_on_interacted)

	_paused = false
	get_tree().paused = false
	_pause_overlay.visible = false
	_prompt_label.text = ""
	_notice_label.text = ""
	_refresh_input_state()


## Player input and mouse capture follow the UI state in exactly one place.
func _refresh_input_state() -> void:
	_input_free = (gm.state == GameManager.State.PLAYING and not _paused
		and _panel == null and _manuals == null and _oracle_panel == null and _modal_layer == null)
	if is_instance_valid(_player):
		_player.set_input_enabled(_input_free)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if _input_free else Input.MOUSE_MODE_VISIBLE


# --- Hold R to retry --------------------------------------------------------

func _update_retry_hold(delta: float) -> void:
	var holding := Input.is_action_pressed("retry_level")
	if not holding:
		_retry_locked = false
	if _input_free and holding and not _retry_locked:
		_retry_hold += delta
		_retry_bar.value = clampf(_retry_hold / Rules.RETRY_HOLD_SECONDS, 0.0, 1.0)
		_retry_box.visible = true
		if _retry_hold >= Rules.RETRY_HOLD_SECONDS:
			# Lock until R is released so one long press cannot retry twice.
			_retry_locked = true
			_retry_hold = 0.0
			_retry_box.visible = false
			_retry()
	else:
		_retry_hold = 0.0
		_retry_box.visible = false


# --- HUD ----------------------------------------------------------------

func _build_hud() -> void:
	_hud_layer = CanvasLayer.new()
	_hud_layer.name = "Hud"
	add_child(_hud_layer)

	_flash = ColorRect.new()
	_flash.color = Color(Rules.COLOR_FAULT, 0.0)
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_layer.add_child(_flash)

	_hud_layer.add_child(_make_label("+", 28, 0.47, 0.53, Color(1, 1, 1, 0.8)))

	_shift_label = _make_label("SHIFT 01", 22, 0.02, 0.07, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT)
	_shift_label.offset_left = 24
	_hud_layer.add_child(_shift_label)

	_systems_label = _make_label("SYSTEMS 0/3", 24, 0.02, 0.07, Rules.COLOR_CYAN)
	_hud_layer.add_child(_systems_label)

	# Guided first shift: one line saying what to do next (shift 1 only).
	_coach_label = _make_label("", 22, 0.82, 0.93, Rules.COLOR_GOLD)
	_coach_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_coach_label.offset_left = 160
	_coach_label.offset_right = -160
	_hud_layer.add_child(_coach_label)

	_checklist_label = _make_label("", 18, 0.075, 0.26, Color(1, 1, 1, 0.92), HORIZONTAL_ALIGNMENT_LEFT)
	_checklist_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_checklist_label.offset_left = 24
	_hud_layer.add_child(_checklist_label)

	_reserve_label = _make_label("RESERVE 08:00", 22, 0.02, 0.07, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT)
	_reserve_label.offset_right = -24
	_hud_layer.add_child(_reserve_label)

	_prompt_label = _make_label("", 26, 0.56, 0.62, Rules.COLOR_GOLD)
	_hud_layer.add_child(_prompt_label)

	_notice_label = _make_label("", 26, 0.09, 0.15, Rules.COLOR_CYAN)
	_hud_layer.add_child(_notice_label)

	_hud_layer.add_child(_make_label(HELP_TEXT, 18, 0.94, 0.99, Color(1, 1, 1, 0.75)))

	# Hold-R progress indicator, shown only while R is held.
	_retry_box = CenterContainer.new()
	_retry_box.anchor_left = 0.0
	_retry_box.anchor_right = 1.0
	_retry_box.anchor_top = 0.80
	_retry_box.anchor_bottom = 0.90
	_retry_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_retry_box.visible = false
	var retry_column := VBoxContainer.new()
	retry_column.add_theme_constant_override("separation", 6)
	_retry_box.add_child(retry_column)
	var retry_label := _make_label("HOLD R TO RETRY", 20, 0.0, 1.0, Rules.COLOR_GOLD)
	retry_label.custom_minimum_size = Vector2(300, 28)
	retry_column.add_child(retry_label)
	_retry_bar = ProgressBar.new()
	_retry_bar.min_value = 0.0
	_retry_bar.max_value = 1.0
	_retry_bar.show_percentage = false
	_retry_bar.custom_minimum_size = Vector2(300, 16)
	retry_column.add_child(_retry_bar)
	_hud_layer.add_child(_retry_box)

	_notice_timer = Timer.new()
	_notice_timer.one_shot = true
	_notice_timer.wait_time = NOTICE_SECONDS
	_notice_timer.timeout.connect(func() -> void: _notice_label.text = "")
	add_child(_notice_timer)


func _make_label(text: String, font_size: int, anchor_top: float, anchor_bottom: float, color: Color,
		alignment: HorizontalAlignment = HORIZONTAL_ALIGNMENT_CENTER) -> Label:
	var label := Label.new()
	label.text = text
	label.anchor_left = 0.0
	label.anchor_right = 1.0
	label.anchor_top = anchor_top
	label.anchor_bottom = anchor_bottom
	label.horizontal_alignment = alignment
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	label.add_theme_constant_override("outline_size", 6)
	return label


func _show_notice(text: String) -> void:
	_notice_label.text = text
	_notice_timer.start()


func _flash_fault() -> void:
	_flash.color = Color(Rules.COLOR_FAULT, 0.35)
	var tween := create_tween()
	tween.tween_property(_flash, "color:a", 0.0, 0.45)


# --- Main Menu --------------------------------------------------------------

func _build_menu() -> void:
	# Layer 15: above the HUD, pause overlay and panels, below modals (20), so
	# How to Play can open on top of the menu.
	_menu_layer = CanvasLayer.new()
	_menu_layer.name = "MenuLayer"
	_menu_layer.layer = 15
	add_child(_menu_layer)

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_menu_layer.add_child(root)

	var background := ColorRect.new()
	background.color = Rules.COLOR_NAVY
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(background)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 16)
	center.add_child(column)

	var title := Label.new()
	title.text = "LAST STATION"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 72)
	title.add_theme_color_override("font_color", Rules.COLOR_CYAN)
	column.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "The crew are asleep. Only you can repair the station."
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 24)
	subtitle.add_theme_color_override("font_color", Rules.COLOR_VIOLET)
	column.add_child(subtitle)

	_menu_best_label = Label.new()
	_menu_best_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_menu_best_label.add_theme_font_size_override("font_size", 22)
	_menu_best_label.add_theme_color_override("font_color", Rules.COLOR_GOLD)
	column.add_child(_menu_best_label)

	column.add_child(_make_menu_button("Play", _start_new_game))
	column.add_child(_make_menu_button("How to Play", func() -> void: _show_how_to_play(false)))
	column.add_child(_make_menu_button("Quit", func() -> void: get_tree().quit()))


func _show_how_to_play(first_time: bool) -> void:
	var label := "Start" if first_time else "Back"
	_show_modal("HOW TO PLAY", Rules.COLOR_CYAN, HOW_TO_PLAY_TEXT, [
		{"label": label, "action": func() -> void:
			if first_time:
				save.mark_intro_seen()
			_close_modal()},
	], true)


# --- Pause overlay --------------------------------------------------------

func _build_pause_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.name = "PauseLayer"
	layer.layer = 10
	add_child(layer)

	_pause_overlay = Control.new()
	_pause_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(_pause_overlay)

	var dim := ColorRect.new()
	dim.color = Color(Rules.COLOR_NAVY, 0.8)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pause_overlay.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pause_overlay.add_child(center)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	center.add_child(column)

	var title := Label.new()
	title.text = "PAUSED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 40)
	title.add_theme_color_override("font_color", Rules.COLOR_CYAN)
	column.add_child(title)

	column.add_child(_make_menu_button("Resume", func() -> void: _set_paused(false)))
	column.add_child(_make_menu_button("Retry Shift", _retry))
	column.add_child(_make_menu_button("Main Menu", _go_to_menu))
	column.add_child(_make_menu_button("Quit", func() -> void: get_tree().quit()))


func _make_menu_button(text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.add_theme_font_size_override("font_size", 22)
	button.custom_minimum_size = Vector2(260, 52)
	button.pressed.connect(action)
	return button


func _set_paused(paused: bool) -> void:
	if paused and not _can_open_overlay():
		return
	_paused = paused
	get_tree().paused = paused
	_pause_overlay.visible = paused
	if paused:
		_prompt_label.text = ""
	_refresh_input_state()


# --- Puzzle panels and manuals ----------------------------------------------

func _build_panel_layer() -> void:
	var layer := CanvasLayer.new()
	layer.name = "PanelLayer"
	layer.layer = 5
	add_child(layer)
	_panel_center = CenterContainer.new()
	_panel_center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_panel_center)


func _open_panel(kind: String) -> void:
	if gm.repaired[kind]:
		_show_notice("%s ALREADY REPAIRED" % kind.to_upper())
		return
	if _panel != null:
		return
	_panel = PuzzlePanel.create(kind, gm)
	_panel.closed.connect(_close_panel)
	_panel.solved.connect(_close_panel)
	_panel_center.add_child(_panel)
	_prompt_label.text = ""
	_refresh_input_state()


func _close_panel() -> void:
	if _panel != null:
		_panel.queue_free()
		_panel = null
	_refresh_input_state()


## The manuals pause the whole game (and so the reserve) while open.
func _open_manuals() -> void:
	if _manuals != null:
		return
	_manuals = ManualsPanel.create(_records)
	_manuals.closed.connect(_close_manuals)
	_panel_center.add_child(_manuals)
	_prompt_label.text = ""
	get_tree().paused = true
	_refresh_input_state()


func _close_manuals() -> void:
	if _manuals != null:
		_manuals.queue_free()
		_manuals = null
		get_tree().paused = _paused
	_refresh_input_state()


## ORACLE pauses the whole game (and so the reserve) while open.
func _open_oracle() -> void:
	if _oracle_panel != null:
		return
	_oracle_panel = OraclePanel.create(oracle)
	_oracle_panel.closed.connect(_close_oracle)
	_oracle_panel.hint_requested.connect(_on_hint_requested)
	_panel_center.add_child(_oracle_panel)
	_prompt_label.text = ""
	get_tree().paused = true
	oracle.warm_up()
	_oracle_panel.focus_input.call_deferred()
	_refresh_input_state()


func _close_oracle() -> void:
	if _oracle_panel != null:
		_oracle_panel.queue_free()
		_oracle_panel = null
		get_tree().paused = _paused
	_refresh_input_state()


## The hint button is handled here, in game code. The language model is never involved,
## and nothing ORACLE (or the player) types can trigger a hint.
func _on_hint_requested() -> void:
	var result := gm.use_hint()
	if is_instance_valid(_oracle_panel):
		_oracle_panel.show_hint(result)


## The only game information ORACLE can see (REQUIREMENTS.md G5). It never
## includes puzzle values, modes, ratings or beacon counts.
func _oracle_snapshot() -> Dictionary:
	return {
		"systems_repaired": gm.repaired_count(),
		"systems_total": Rules.SYSTEMS_TOTAL,
		"reserve_seconds": int(gm.reserve),
		"mistakes": gm.mistakes,
		"retry_count": gm.retry_count,
		"run_number": gm.run_number,
		"best_score": save.best_score,
	}


# --- Modal screens ------------------------------------------------------------

## Shows a centred modal with a title, body text and buttons.
## `buttons` is an Array of {"label": String, "action": Callable}.
func _show_modal(title: String, title_color: Color, body: String, buttons: Array, opaque: bool = false) -> void:
	_close_modal()
	_modal_layer = CanvasLayer.new()
	_modal_layer.name = "ModalLayer"
	_modal_layer.layer = 20
	add_child(_modal_layer)

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_modal_layer.add_child(root)

	var dim := ColorRect.new()
	dim.color = Color(Rules.COLOR_NAVY, 1.0 if opaque else 0.92)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 16)
	center.add_child(column)

	var title_label := Label.new()
	title_label.text = title
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", 42)
	title_label.add_theme_color_override("font_color", title_color)
	column.add_child(title_label)

	var body_label := Label.new()
	body_label.text = body
	body_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body_label.custom_minimum_size = Vector2(MODAL_WIDTH, 0)
	body_label.add_theme_font_size_override("font_size", 22)

	# The body scrolls if it is taller than the window, so the buttons below it
	# are always on screen. Room is left for the title, the buttons and a margin.
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.add_child(body_label)
	var window_height := get_viewport().get_visible_rect().size.y
	var reserved := 96.0 + buttons.size() * 68.0 + 48.0
	var max_height := maxf(window_height - reserved, 120.0)
	scroll.custom_minimum_size = Vector2(MODAL_WIDTH, clampf(_estimate_text_height(body), 40.0, max_height))
	column.add_child(scroll)

	var first_button: Button = null
	for entry in buttons:
		var button := _make_menu_button(entry["label"], entry["action"])
		column.add_child(button)
		if first_button == null:
			first_button = button
	if first_button != null:
		first_button.grab_focus.call_deferred()  # so Enter or Space presses it

	_prompt_label.text = ""
	_refresh_input_state()


## Rough height of centred 22 px text wrapped at MODAL_WIDTH (about 70 characters a line).
func _estimate_text_height(text: String) -> float:
	var lines := 0
	for line in text.split("\n"):
		lines += maxi(1, ceili(line.length() / 70.0))
	return lines * 34.0


func _close_modal() -> void:
	if _modal_layer != null:
		_modal_layer.queue_free()
		_modal_layer = null
	_refresh_input_state()


# --- Signals from the world -------------------------------------------------

func _on_target_changed(target: Interactable) -> void:
	_prompt_label.text = "E — %s" % target.prompt if target != null else ""


func _on_interacted(item: Interactable, _player_node: Node) -> void:
	if gm.state != GameManager.State.PLAYING:
		return
	var id := item.id
	if id.begins_with("breaker_"):
		_handle_breaker(int(id.substr("breaker_".length())))
	elif id == "oxygen_console":
		_open_panel("oxygen")
	elif id == "comms_console":
		_open_panel("comms")
	elif id == "reboot_terminal":
		if not gm.try_reboot():
			_show_notice("ALL 3 SYSTEMS MUST BE REPAIRED")


func _handle_breaker(index: int) -> void:
	if gm.repaired["power"]:
		_show_notice("POWER ALREADY REPAIRED")
		return
	var breakers: Array = _station["breakers"]
	match gm.flip_breaker(index):
		"ok", "repaired":
			(breakers[index] as Interactable).set_color(Rules.COLOR_CYAN)
		"surge":
			for breaker in breakers:
				(breaker as Interactable).set_color(Rules.COLOR_VIOLET)


func _on_system_repaired(system_id: String) -> void:
	var light: OmniLight3D = _station["room_lights"][system_id]
	light.light_color = Rules.COLOR_CYAN
	var label: Label3D = _station["door_labels"][system_id]
	label.modulate = Rules.COLOR_CYAN
	# The door frame and light turn from red to cyan.
	var status: StandardMaterial3D = _station["door_status"][system_id]
	status.albedo_color = Rules.COLOR_CYAN
	status.emission = Rules.COLOR_CYAN
	if system_id == "power":
		for breaker in _station["breakers"]:
			(breaker as Interactable).set_color(Rules.COLOR_CYAN)
	else:
		(_station["consoles"][system_id] as Interactable).set_color(Rules.COLOR_CYAN)
	_show_notice("%s SYSTEM REPAIRED" % system_id.to_upper())
	if gm.repaired_count() == Rules.SYSTEMS_TOTAL:
		_show_notice("ALL SYSTEMS REPAIRED — REBOOT THE STATION")
		# The reboot terminal changes colour so it is easy to spot in the hub.
		(_station["reboot"] as Interactable).set_color(Rules.COLOR_CYAN)


func _on_mistake_made(system_id: String, penalty_seconds: int) -> void:
	_flash_fault()
	_show_notice("%s  -%d s" % [MISTAKE_TEXT[system_id], penalty_seconds])


func _on_shift_won(result: Dictionary) -> void:
	var is_new_best := save.record_score(result["final"])
	var is_new_run_best := save.record_run(result["run_total"])
	var best_line := "Best shift score: %d%s" % [save.best_score, "   NEW BEST!" if is_new_best else ""]
	var run_line := "Run total after shift %d: %d     Best run: %d%s" % [
		result["run_number"], result["run_total"], save.best_run, "   NEW BEST!" if is_new_run_best else ""]
	var body := "Reserve remaining: %d s\nSystems repaired: 3/3\nMistakes: %d     Retries: %d     Hints: %d\n\nBase points: %d\nTime bonus: +%d\nRetry penalty: -%d\n\nSHIFT SCORE: %d\n%s\n%s\n\nNext shift: %d s of reserve     Seed: %d" % [
		result["reserve_remaining"], result["mistakes"], result["retries"], result["hints"],
		result["base"], result["time_bonus"], result["retry_penalty"],
		result["final"], best_line, run_line, result["next_reserve"], result["seed"]]
	_show_modal("STATION REBOOTED", Rules.COLOR_CYAN, body, [
		{"label": "Next Shift", "action": _next_shift},
		{"label": "Main Menu", "action": _go_to_menu},
		{"label": "Quit", "action": func() -> void: get_tree().quit()},
	])


func _on_shift_failed() -> void:
	_close_panel()
	_close_manuals()
	_close_oracle()
	_show_modal("OXYGEN RESERVE DEPLETED", Rules.COLOR_FAULT,
		"The station is lost.\nRetrying restarts this shift with new puzzle values.", [
		{"label": "Retry Shift", "action": _retry},
		{"label": "Main Menu", "action": _go_to_menu},
		{"label": "Quit", "action": func() -> void: get_tree().quit()},
	])
