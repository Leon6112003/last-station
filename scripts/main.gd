extends Node
## Entry point. Registers input, owns the GameManager, builds the world, HUD,
## menus and overlays from code, and reacts to GameManager signals.
## Milestone 3: Main Menu, how-to-play card, hold-R retry, Manuals panel and a
## saved best score. ORACLE (the chatbot) arrives in Milestone 4.

const HELP_TEXT := "WASD Move  ·  E Interact  ·  V View  ·  M Manuals  ·  H ORACLE  ·  Esc Pause  ·  Hold R Retry"
const NOTICE_SECONDS := 2.5
const AMBIENT_ENERGY := 0.65        # a little darker than before, for mood
const TICK_INTERVAL_SECONDS := 1.0       # clock tick spacing when reserve is low
const TICK_FAST_BELOW_SECONDS := 20.0    # ... and it doubles in speed below this
const TICK_FAST_INTERVAL_SECONDS := 0.5
const FADE_IN_SECONDS := 0.7
const LOW_RESERVE_SECONDS := 60.0   # below this the station pulses red
const MODAL_WIDTH := 860.0

const HOW_TO_PLAY_TEXT := """MISSION
The Last Station has lost power. The crew are asleep in hibernation
and the oxygen reserve is running out. The station's old help
system, ORACLE, remembers how every system works. You are the
only one awake who can repair them.

GOAL
You wake up in the crew quarters. Something is wrong with the
station. Walk the corridor to Power, Oxygen and Comms and repair
each one, then walk back and press E on the reboot terminal at the
west end, before the reserve reaches zero.

THE WALK
The Oxygen door stays locked until Power is repaired, and the Comms
door until Oxygen is repaired. In the corridor, a GAS VENT drains
your reserve fast while it is venting (red lamp), and LIVE WIRES cost
12 seconds if they spark as you cross (red lamp). Wait for a grey lamp.

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
var _environment: Environment
var _theme: Dictionary = ShiftTheme.for_shift(1)
var sound: SoundBank
var _third_person: bool = false   # kept across shifts until changed
var _tick_timer: float = 0.0
var _tick_is_tock: bool = false
var _fade: ColorRect
var _mood_time: float = 0.0
var _low_vignette: TextureRect

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
var _menu_screen: MenuScreen
## Plays the typed wake-up intro when the game first opens. Off in headless runs (tests).
var boot_intro: bool = DisplayServer.get_name() != "headless"
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

	sound = SoundBank.new()
	sound.name = "SoundBank"
	sound.load_music = DisplayServer.get_name() != "headless"
	add_child(sound)

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


## Atmosphere. The hub light flickers a little; under a minute of reserve the whole
## station pulses red and a red vignette fades in. Visual only: no rules are touched.
func _update_mood(delta: float) -> void:
	var running := gm.state == GameManager.State.PLAYING and not _paused
	# The theme song plays over the opening intro and the menu, and carries on into the
	# shift without restarting. It is silent while paused and on the win and lose screens.
	sound.set_music_active(gm.state == GameManager.State.MENU or (running and not _station.is_empty()))
	if _environment == null or _station.is_empty():
		return
	_mood_time += delta
	var low := gm.state == GameManager.State.PLAYING and gm.reserve < LOW_RESERVE_SECONDS
	# 0 when comfortable, up to 1 as the reserve runs out.
	var urgency := clampf(1.0 - gm.reserve / LOW_RESERVE_SECONDS, 0.0, 1.0) if low else 0.0
	var pulse := 0.5 + 0.5 * sin(_mood_time * (3.0 + 3.0 * urgency))
	# The bedroom alarm pulses red until the first system is repaired, then settles.
	var alarm_light: OmniLight3D = _station["alarm_light"]
	alarm_light.light_energy = (0.5 + 1.3 * (0.5 + 0.5 * sin(_mood_time * 4.0))) if gm.repaired_count() == 0 else 0.4
	var hub_light: OmniLight3D = _station["hub_light"]
	if low:
		hub_light.light_energy = (0.6 + 1.6 * pulse) * (0.5 + 0.5 * urgency)
		_environment.ambient_light_energy = AMBIENT_ENERGY * (1.0 - 0.3 * urgency * pulse)
		_environment.fog_light_color = (_theme["fog"] as Color).lerp(Rules.COLOR_FAULT.darkened(0.6), urgency * 0.6)
	else:
		# A slow, uneven flicker on the emergency light (never fully off, never harsh).
		var flicker := 0.5 + 0.5 * sin(_mood_time * 1.7) * sin(_mood_time * 5.3)
		hub_light.light_energy = 0.25 * flicker if gm.repaired_count() < Rules.SYSTEMS_TOTAL else 0.0
		_environment.ambient_light_energy = AMBIENT_ENERGY
		_environment.fog_light_color = _theme["fog"]
	# A clock ticks and tocks while the reserve is low, faster in the last seconds.
	if low and running:
		_tick_timer -= delta
		if _tick_timer <= 0.0:
			_tick_timer = TICK_FAST_INTERVAL_SECONDS if gm.reserve < TICK_FAST_BELOW_SECONDS else TICK_INTERVAL_SECONDS
			sound.play("tock" if _tick_is_tock else "tick")
			_tick_is_tock = not _tick_is_tock
	else:
		_tick_timer = 0.0
	if _low_vignette != null:
		_low_vignette.modulate.a = urgency * (0.55 + 0.35 * pulse)


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
	_update_mood(delta)


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
	elif event.is_action_pressed("toggle_view"):
		if gm.state == GameManager.State.PLAYING and _player != null and not _paused and _modal_layer == null:
			_third_person = not _third_person
			_player.set_third_person(_third_person)
			_show_notice("THIRD PERSON VIEW" if _third_person else "FIRST PERSON VIEW")
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("toggle_music"):
		sound.set_music_enabled(not sound.music_enabled)
		if _hud_layer.visible:
			_show_notice("MUSIC ON" if sound.music_enabled else "MUSIC OFF")
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("toggle_sound"):
		sound.set_muted(not sound.muted)
		if _hud_layer.visible:
			_show_notice("SOUND OFF" if sound.muted else "SOUND ON")
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
		return "All systems repaired! Walk back west along the corridor and press E on the reboot terminal."
	for id in GameManager.SYSTEM_IDS:
		if gm.repaired.get(id, false):
			continue
		match id:
			"power":
				return "NEXT: leave the crew quarters and go east to the POWER room (first door). Read LOAD MODE and the breaker voltages, then press H and ask ORACLE which breaker first."
			"oxygen":
				return "NEXT: the OXYGEN room (second door, now unlocked). Mind the gas vent on the way. Read STATION MODE, then press H and ask ORACLE for the valve settings."
			_:
				return "NEXT: the COMMS room (third door, now unlocked). Mind the live wires on the way. Count the lit beacons, then press H and ask ORACLE for the frequency."
	return ""


## The on-screen objective list: which systems are repaired and what is next.
func _checklist_text() -> String:
	var rooms := {"power": "1st room", "oxygen": "2nd room", "comms": "3rd room"}
	var protocol: String = gm.puzzles.get("protocol", "A")
	var lines: Array[String] = ["REPAIR THE STATION  ·  PROTOCOL %s" % protocol]
	for id in GameManager.SYSTEM_IDS:
		var mark := "[x]" if gm.repaired.get(id, false) else "[ ]"
		lines.append("%s %s (%s)" % [mark, id.capitalize(), rooms[id]])
	if gm.repaired_count() == Rules.SYSTEMS_TOTAL:
		lines.append("-> REBOOT: terminal at the west end")
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
	_add_action("toggle_view", [KEY_V])       # first / third person camera
	_add_action("toggle_music", [KEY_B])      # theme song on / off
	_add_action("toggle_sound", [KEY_N])      # mute / unmute sound effects


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
	_theme = ShiftTheme.for_shift(gm.run_number)
	environment.background_color = _theme["background"]
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = _theme["ambient"]
	environment.ambient_light_energy = AMBIENT_ENERGY
	# A light navy haze gives the corridors depth without hiding the labels.
	environment.fog_enabled = true
	environment.fog_light_color = _theme["fog"]
	environment.fog_density = 0.012
	_environment = environment
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	_world.add_child(world_environment)

	_station = StationBuilder.build(_world, gm.puzzles, _theme)

	_player = PlayerController.new()
	_player.name = "Player"
	_player.position = _station["spawn"]
	_player.rotation.y = deg_to_rad(float(_station["spawn_yaw"]))
	for zone in _station["hazards"]:
		(zone as HazardZone).hit.connect(_on_hazard_zone_hit)
	_world.add_child(_player)
	_player.target_changed.connect(_on_target_changed)
	_player.first_move.connect(gm.begin_clock)
	_player.stepped.connect(sound.play.bind("step"))
	_player.set_third_person(_third_person)
	_player.play_wake_up()
	_fade_in()

	for item in _station["interactables"]:
		(item as Interactable).interacted.connect(_on_interacted)

	_paused = false
	get_tree().paused = false
	_pause_overlay.visible = false
	_prompt_label.text = ""
	_notice_label.text = ""
	if gm.run_number == 1 and gm.retry_count == 0:
		_show_notice("YOU WAKE UP. SOMETHING IS WRONG WITH THE STATION.", 4.0)
	else:
		_show_notice("SHIFT %02d  ·  %s WING" % [gm.run_number, _theme["name"]])
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

	# Black cover used to fade the world in when a shift starts.
	_fade = ColorRect.new()
	_fade.color = Color(0.0, 0.0, 0.0, 0.0)
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_layer.add_child(_fade)

	# Red edge vignette that fades in when the reserve runs low (centre stays clear).
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.55, 1.0])
	gradient.colors = PackedColorArray([Color(Rules.COLOR_FAULT, 0.0), Color(Rules.COLOR_FAULT, 0.7)])
	var vignette := GradientTexture2D.new()
	vignette.gradient = gradient
	vignette.fill = GradientTexture2D.FILL_RADIAL
	vignette.fill_from = Vector2(0.5, 0.5)
	vignette.fill_to = Vector2(1.0, 0.5)
	vignette.width = 256
	vignette.height = 256
	_low_vignette = TextureRect.new()
	_low_vignette.texture = vignette
	_low_vignette.stretch_mode = TextureRect.STRETCH_SCALE
	_low_vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	_low_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_low_vignette.modulate.a = 0.0
	_hud_layer.add_child(_low_vignette)

	_hud_layer.add_child(_make_label("+", 24, 0.47, 0.53, Color(1, 1, 1, 0.8)))

	_shift_label = _make_label("SHIFT 01", 19, 0.02, 0.07, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT)
	_shift_label.offset_left = 24
	_hud_layer.add_child(_shift_label)

	_systems_label = _make_label("SYSTEMS 0/3", 21, 0.02, 0.07, Rules.COLOR_CYAN)
	_hud_layer.add_child(_systems_label)

	# Guided first shift: one line saying what to do next (shift 1 only).
	_coach_label = _make_label("", 19, 0.82, 0.93, Rules.COLOR_GOLD)
	_coach_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_coach_label.offset_left = 160
	_coach_label.offset_right = -160
	_hud_layer.add_child(_coach_label)

	_checklist_label = _make_label("", 16, 0.075, 0.26, Color(1, 1, 1, 0.92), HORIZONTAL_ALIGNMENT_LEFT)
	_checklist_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_checklist_label.offset_left = 24
	_hud_layer.add_child(_checklist_label)

	_reserve_label = _make_label("RESERVE 08:00", 19, 0.02, 0.07, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT)
	_reserve_label.offset_right = -24
	_hud_layer.add_child(_reserve_label)

	_prompt_label = _make_label("", 22, 0.56, 0.62, Rules.COLOR_GOLD)
	_hud_layer.add_child(_prompt_label)

	_notice_label = _make_label("", 22, 0.09, 0.15, Rules.COLOR_CYAN)
	_hud_layer.add_child(_notice_label)

	_hud_layer.add_child(_make_label(HELP_TEXT, 15, 0.94, 0.99, Color(1, 1, 1, 0.75)))

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
	var retry_label := _make_label("HOLD R TO RETRY", 18, 0.0, 1.0, Rules.COLOR_GOLD)
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


func _show_notice(text: String, seconds: float = NOTICE_SECONDS) -> void:
	_notice_label.text = text
	_notice_timer.start(seconds)


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

	_menu_screen = MenuScreen.create(
		_start_new_game,
		func() -> void: _show_how_to_play(false),
		func() -> void: get_tree().quit(),
		boot_intro)
	_menu_screen.name = "MenuScreen"
	_menu_layer.add_child(_menu_screen)
	_menu_best_label = _menu_screen.best_label


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


## Fades the screen in from black when a shift (or a retry) begins.
func _fade_in() -> void:
	_fade.color.a = 1.0
	var tween := create_tween()
	tween.tween_property(_fade, "color:a", 0.0, FADE_IN_SECONDS)


# --- Signals from the world -------------------------------------------------

func _on_target_changed(target: Interactable) -> void:
	_prompt_label.text = "E — %s" % target.prompt if target != null else ""


func _on_interacted(item: Interactable, _player_node: Node) -> void:
	if gm.state != GameManager.State.PLAYING:
		return
	var id := item.id
	item.play_press()
	if id.begins_with("breaker_"):
		_handle_breaker(int(id.substr("breaker_".length())))
	elif id == "oxygen_console":
		sound.play("hiss")
		_open_panel("oxygen")
	elif id == "comms_console":
		sound.play("hiss")
		_open_panel("comms")
	elif id == "reboot_terminal":
		if not gm.try_reboot():
			sound.play("buzz")
			_show_notice("ALL 3 SYSTEMS MUST BE REPAIRED")


func _handle_breaker(index: int) -> void:
	if gm.repaired["power"]:
		_show_notice("POWER ALREADY REPAIRED")
		return
	var breakers: Array = _station["breakers"]
	match gm.flip_breaker(index):
		"ok", "repaired":
			sound.play("click")
			(breakers[index] as Interactable).set_color(Rules.COLOR_CYAN)
		"surge":
			for breaker in breakers:
				(breaker as Interactable).set_color(Rules.COLOR_VIOLET)


func _on_system_repaired(system_id: String) -> void:
	sound.play("chime")
	# Doors that were waiting for this system slide open.
	for room_id in _station["doors"]:
		var gate: DoorGate = _station["doors"][room_id]
		var was_locked := gate.locked
		gate.refresh(gm.repaired)
		if was_locked and not gate.locked:
			_show_notice("%s DOOR UNLOCKED" % String(room_id).to_upper(), 3.0)
	var light: OmniLight3D = _station["room_lights"][system_id]
	light.light_color = Rules.COLOR_CYAN
	light.light_energy = StationBuilder.ROOM_LIGHT_ENERGY_ON
	# The room itself wakes up: bright cyan ceiling strip, and a brighter floor patch.
	var strip: StandardMaterial3D = _station["room_strips"][system_id]
	strip.albedo_color = Rules.COLOR_CYAN
	strip.emission = Rules.COLOR_CYAN
	strip.emission_energy_multiplier = StationBuilder.STRIP_ENERGY_ON
	(_station["room_floors"][system_id] as StandardMaterial3D).emission_energy_multiplier = StationBuilder.FLOOR_ENERGY_ON
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


## A hazard zone saw the player inside while active. GameManager applies the cost.
func _on_hazard_zone_hit(kind: String, seconds: float, first: bool) -> void:
	gm.hazard_damage(kind, seconds)
	if first:
		_flash_fault()
		if kind == HazardZone.KIND_GAS:
			sound.play("hiss")
			_show_notice("GAS LEAK!  Reserve is draining. Get out or wait for the lamp to turn grey.")
		else:
			sound.play("buzz")
			_show_notice("SPARKS!  -%d s" % int(seconds))


func _on_mistake_made(system_id: String, penalty_seconds: int) -> void:
	sound.play("buzz")
	_flash_fault()
	_show_notice("%s  -%d s" % [MISTAKE_TEXT[system_id], penalty_seconds])


func _on_shift_won(result: Dictionary) -> void:
	sound.play("win")
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
	sound.play("fail")
	_close_panel()
	_close_manuals()
	_close_oracle()
	_show_modal("OXYGEN RESERVE DEPLETED", Rules.COLOR_FAULT,
		"The station is lost.\nRetrying restarts this shift with new puzzle values.", [
		{"label": "Retry Shift", "action": _retry},
		{"label": "Main Menu", "action": _go_to_menu},
		{"label": "Quit", "action": func() -> void: get_tree().quit()},
	])
