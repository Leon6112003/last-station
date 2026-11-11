extends Node
## Entry point. Registers input, owns the GameManager, builds the world, HUD,
## menus and overlays from code, and reacts to GameManager signals.
## Milestone 3: Main Menu, how-to-play card, hold-R retry, Manuals panel and a
## saved best score. ORACLE (the chatbot) arrives in Milestone 4.

const AMBIENT_MIN_SECONDS := 9.0         # distant groans and bangs come this far apart
const AMBIENT_MAX_SECONDS := 21.0
const ALARM_INTERVAL_SECONDS := 14.0
const SPARK_HEARING_METRES := 7.0
const HEARTBEAT_BELOW_SECONDS := 45.0
const HEARTBEAT_INTERVAL_SECONDS := 1.05
const BREATH_CALM_SPACING_SECONDS := 2.2   # helmet breathing: time between inhale and exhale
const BREATH_PANIC_SPACING_SECONDS := 0.85
const FAN_MIN_SECONDS := 18.0
const FAN_MAX_SECONDS := 32.0
const DOOR_BUMP_DEPTH_METRES := 1.1      # how close to a locked door the clunk plays
const DOOR_CLUNK_COOLDOWN_SECONDS := 2.5
const GAS_HEARING_METRES := 6.0
const GAS_HISS_INTERVAL_SECONDS := 0.45
const DANGER_RESERVE_SECONDS := 120.0     # a low reserve alone makes the music fully tense by 0 s
const DANGER_AT_START := 0.2              # the music is already a little tense when a shift begins
const HIT_DANGER_DECAY_PER_SECOND := 0.2
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
station. Walk the corridor to Power, Oxygen, Comms and Cooling and repair
each one, then walk back and press E on the reboot terminal at the
west end, before the reserve reaches zero.

THE WALK
The doors open in order: Oxygen after Power, Comms after Oxygen,
Cooling after Comms. West of the crew quarters, on the way to the
reboot terminal, an optional CRYO BAY holds the sleeping crew and
their logs. In the corridor, GAS VENTS drain your
reserve fast while they vent (red lamp): wait for a grey lamp. Gas also
leaks at the Oxygen console (and the Cooling console in a SURGE) until
that system is repaired. A ZERO-GRAVITY
ZONE makes you float: you move slowly, drift off the floor and lose
reserve time every second you are inside. Press E on a wall switch
beside it to restore gravity for a short time. Later shifts are worse:
wider, longer gas vents, a shorter gravity-on time, and from shift 3 a
second zero-gravity zone before the Cooling room. Repairing Comms or
Cooling restores gravity beyond it for good.

COSTS
Every question to ORACLE (H) costs some reserve time (none on Rookie,
5 s on Engineer, 10 s on Survivor). The manuals (M) are free.

HOW
There are no instructions in the rooms. Read the panels, then ask
ORACLE (H) or open the Manuals (M) to learn the rule. The rules
change with the station PROTOCOL shown at the top left.

CONTROLS
WASD move  ·  Mouse look  ·  E interact  ·  M manuals
H ask ORACLE  ·  Esc pause  ·  Hold R for 1 second to retry
(These are the default keys. Volume, mouse speed, key changes and
colour-blind options are in Settings: the main menu, top right, or
the pause menu.)"""

const MISTAKE_TEXT := {
	"power": "POWER SURGE",
	"oxygen": "PRESSURE MISMATCH",
	"comms": "NO SIGNAL",
	"cooling": "PUMP OVERLOAD",
	"reboot": "WRONG CODE",
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
var _front_view: bool = false
var _hit_danger: float = 0.0   # music only: jumps to 1 when the player is hurt, then fades
var _fade_tween: Tween
var _ambience_rng := RandomNumberGenerator.new()   # sound timing only; never used for game rules
var _creak_timer: float = 8.0
var _alarm_timer: float = 4.0
var _spark_timer: float = 0.0
var _heartbeat_timer: float = 0.0
var _breath_timer: float = 3.0
var _breath_in_next: bool = true
var _fan_timer: float = 12.0
var _door_clunk_timer: float = 0.0
var _gas_hiss_timer: float = 0.0
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
var _help_label: Label
var _settings_layer: CanvasLayer
var _settings_panel: SettingsPanel
var _par_label: Label
var _caption_label: Label
var _captions: Array[Dictionary] = []   # {text, until}: the sound captions on screen
var _pause_retry_button: Button
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
## The shift a new game starts on. Always 1, except for the developer launch option --shift=N.
var dev_start_shift: int = 1
## Plays the typed wake-up intro when the game first opens. Off in headless runs (tests).
var boot_intro: bool = DisplayServer.get_name() != "headless"
## Plays the wake-up-in-bed sequence at the start of a shift. Off in headless runs (tests).
var play_wake_sequence: bool = DisplayServer.get_name() != "headless"
var _panel_center: CenterContainer
var _panel: PuzzlePanel = null
var _manuals: ManualsPanel = null
var _log_panel: LogPanel = null
var _oracle_panel: OraclePanel = null
var _modal_layer: CanvasLayer = null
var _paused: bool = false
var _input_free: bool = false
var _retry_hold: float = 0.0
var _retry_locked: bool = false


func _ready() -> void:
	_ambience_rng.randomize()
	# Developer launch option (after "--"): --shift=3 starts a new game on shift 3, to try the
	# later, harder shifts without winning the earlier ones. Not shown anywhere in the game.
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--shift="):
			dev_start_shift = clampi(int(argument.substr("--shift=".length())), 1, 99)
	# Main keeps running while the tree is paused so Esc can resume.
	# The world and the GameManager are explicitly pausable.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.randomize()
	save = SaveManager.new(save_path)
	_setup_input()
	Rules.level = save.difficulty
	Rules.mods = 0   # modifiers always start switched off; they are not remembered between launches
	Rules.adaptive = save.adaptive
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
	sound.music_volume = save.music_volume
	sound.sfx_volume = save.sfx_volume
	add_child(sound)
	sound.played.connect(_on_sound_played)

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
## Blackout: the corridor lights flicker unevenly and, now and then, one cuts out for a moment.
## The flicker never takes a light below a share of its energy except in those short dips, so
## the corridor stays walkable. Looks only.
func _flicker_corridor_lights() -> void:
	var lights: Array = _station.get("corridor_lights", [])
	for i in lights.size():
		var light := lights[i] as OmniLight3D
		var wave := 0.5 + 0.5 * sin(_mood_time * 6.7 + float(i) * 1.9) * sin(_mood_time * 2.9 + float(i) * 0.7)
		var level := Rules.BLACKOUT_MIN_LEVEL + (1.0 - Rules.BLACKOUT_MIN_LEVEL) * wave
		if fposmod(_mood_time + float(i) * 2.3, Rules.BLACKOUT_DIP_EVERY_SECONDS) < Rules.BLACKOUT_DIP_SECONDS:
			level = 0.05
		light.light_energy = float(light.get_meta("base_energy")) * level


func _update_mood(delta: float) -> void:
	var running := gm.state == GameManager.State.PLAYING and not _paused
	# The theme song plays over the opening intro and the menu, and carries on into the
	# shift without restarting. It is silent while paused and on the win and lose screens.
	sound.set_music_active(gm.state == GameManager.State.MENU or (running and not _station.is_empty()))
	sound.set_music_danger(_danger_level(delta))
	if _environment == null or _station.is_empty():
		return
	_mood_time += delta
	if Rules.has_mod(Rules.MOD_BLACKOUT):
		_flicker_corridor_lights()
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
	if running:
		_update_ambience(delta)


## Survival atmosphere, played now and then (never a constant drone): the station groans
## and bangs in the distance, an alarm sounds until the first system is repaired, the gravity
## grid crackles when you are near it, and a heartbeat starts when the reserve is nearly gone.
## This only plays sounds; it has no effect on the rules.
func _update_ambience(delta: float) -> void:
	_creak_timer -= delta
	if _creak_timer <= 0.0:
		_creak_timer = _ambience_rng.randf_range(AMBIENT_MIN_SECONDS, AMBIENT_MAX_SECONDS)
		sound.play("creak" if _ambience_rng.randf() < 0.55 else "thud")
	if gm.repaired_count() == 0:
		_alarm_timer -= delta
		if _alarm_timer <= 0.0:
			_alarm_timer = ALARM_INTERVAL_SECONDS
			sound.play("alarm")
	var near_live_gravity := false
	for gravity in _station["gravity_zones"]:
		if (gravity as GravityZone).armed and is_instance_valid(_player) and absf(_player.global_position.x - (gravity as GravityZone).position.x) < SPARK_HEARING_METRES:
			near_live_gravity = true
	if near_live_gravity:
		_spark_timer -= delta
		if _spark_timer <= 0.0:
			_spark_timer = _ambience_rng.randf_range(0.8, 2.2)
			sound.play("spark")
	_update_station_sounds(delta)
	if gm.reserve < HEARTBEAT_BELOW_SECONDS:
		_heartbeat_timer -= delta
		if _heartbeat_timer <= 0.0:
			_heartbeat_timer = HEARTBEAT_INTERVAL_SECONDS
			sound.play("heartbeat")
	else:
		_heartbeat_timer = 0.0


## More station sounds, also only played, never affecting the rules: breathing inside the
## helmet (faster as the reserve runs low), the ventilation fans dying while the station is
## broken and whooshing once it is repaired, a heavy clunk when you walk up to a locked
## door, and a steady hiss while a gas vent is open near you.
func _update_station_sounds(delta: float) -> void:
	if not is_instance_valid(_player) or _player.waking:
		return
	var panic := clampf(1.0 - gm.reserve / LOW_RESERVE_SECONDS, 0.0, 1.0)
	_breath_timer -= delta
	if _breath_timer <= 0.0:
		_breath_timer = BREATH_CALM_SPACING_SECONDS - (BREATH_CALM_SPACING_SECONDS - BREATH_PANIC_SPACING_SECONDS) * panic
		sound.play("breath_in" if _breath_in_next else "breath_out")
		_breath_in_next = not _breath_in_next
	_fan_timer -= delta
	if _fan_timer <= 0.0:
		_fan_timer = _ambience_rng.randf_range(FAN_MIN_SECONDS, FAN_MAX_SECONDS)
		sound.play("fan_down" if gm.repaired_count() == 0 else "vent")
	_door_clunk_timer -= delta
	var player_x := _player.global_position.x
	if _door_clunk_timer <= 0.0 and _player.global_position.z < StationBuilder.HUB_BACK_Z + DOOR_BUMP_DEPTH_METRES:
		for room_id in _station["doors"]:
			var gate: DoorGate = _station["doors"][room_id]
			if gate.locked and absf(player_x - gate.global_position.x) < StationBuilder.DOOR_HALF_WIDTH:
				_door_clunk_timer = DOOR_CLUNK_COOLDOWN_SECONDS
				sound.play("door_lock")
				break
	_gas_hiss_timer -= delta
	if _gas_hiss_timer <= 0.0:
		for zone in _gas_zones():
			if (zone as HazardZone).is_active() and absf(player_x - (zone as HazardZone).global_position.x) < GAS_HEARING_METRES:
				_gas_hiss_timer = GAS_HISS_INTERVAL_SECONDS
				sound.play("gasleak")
				break


## How much danger the player is in, 0 to 1, for the music: the shift wearing on, a low reserve, a vent that is
## open nearby, the gravity zone close by, or a hit that just happened. Sound only.
func _danger_level(delta: float) -> float:
	_hit_danger = maxf(0.0, _hit_danger - HIT_DANGER_DECAY_PER_SECOND * delta)
	if gm.state != GameManager.State.PLAYING or _station.is_empty() or not is_instance_valid(_player) or _player.waking:
		return 0.0
	# Tension builds with the shift: some from the very start, rising steadily as the reserve
	# drains, and always at least what a low reserve alone would give.
	var start_reserve := float(Rules.reserve_for_shift(gm.run_number))
	var danger := DANGER_AT_START + (1.0 - DANGER_AT_START) * clampf(1.0 - gm.reserve / start_reserve, 0.0, 1.0)
	danger = maxf(danger, clampf(1.0 - gm.reserve / DANGER_RESERVE_SECONDS, 0.0, 1.0))
	var player_x := _player.global_position.x
	for zone in _gas_zones():
		if (zone as HazardZone).is_active():
			var distance := absf(player_x - (zone as HazardZone).global_position.x)
			danger = maxf(danger, 0.85 if distance < 3.5 else (0.5 if distance < 7.0 else 0.0))
	for gravity in _station["gravity_zones"]:
		if (gravity as GravityZone).armed:
			danger = maxf(danger, 0.65 if absf(player_x - (gravity as GravityZone).position.x) < 5.0 else 0.0)
	return maxf(danger, _hit_danger)


## Speedrun: "PAR 03:00" under the reserve while the shift runs. Gold while you are inside par
## (the reserve you have spent is at most half the shift's start), red once it is missed.
## Which sounds get a caption, and the words for each.
const SOUND_CAPTIONS := {
	"alarm": "ALARM: the station is failing",
	"gasleak": "GAS VENTING nearby",
	"spark": "WEIGHTLESS: a zero-gravity zone is near",
	"creak": "(metal groans)",
	"thud": "(a distant bang)",
	"heartbeat": "(your heartbeat)",
	"door_slide": "(a door slides open)",
	"door_lock": "(a locked door clunks)",
	"fan_down": "(the fans slow down)",
	"fan_up": "(the fans spin up)",
	"buzz": "(error buzz)",
	"chime": "(a system is repaired)",
}
const CAPTION_SECONDS := 2.6
const CAPTION_LINES := 3


## A caption for a sound, when captions are on, or sound is muted or the effects volume is 0.
func _on_sound_played(sound_name: String) -> void:
	var wanted := save.captions or sound.muted or sound.sfx_volume <= 0.001
	if not wanted or not SOUND_CAPTIONS.has(sound_name) or gm.state != GameManager.State.PLAYING:
		return
	var text: String = SOUND_CAPTIONS[sound_name]
	var until := Time.get_ticks_msec() / 1000.0 + CAPTION_SECONDS
	for line in _captions:
		if line["text"] == text:
			line["until"] = until   # the same sound again just keeps its line alive
			return
	_captions.append({"text": text, "until": until})
	while _captions.size() > CAPTION_LINES:
		_captions.pop_front()


func _update_captions() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	_captions = _captions.filter(func(line: Dictionary) -> bool: return float(line["until"]) > now)
	var lines: Array[String] = []
	for line in _captions:
		lines.append(line["text"])
	_caption_label.text = "\n".join(lines)


func _update_par_label() -> void:
	var show := Rules.has_mod(Rules.MOD_SPEEDRUN) and gm.state == GameManager.State.PLAYING
	_par_label.visible = show
	if not show:
		return
	var par := Rules.par_seconds(gm.run_number)
	var spent := float(Rules.reserve_for_shift(gm.run_number)) - gm.reserve
	var left := maxi(0, int(ceil(par - spent)))
	if spent <= par:
		_par_label.text = "PAR %s  ·  %s TO BEAT IT" % [_clock(int(par)), _clock(left)]
		_par_label.add_theme_color_override("font_color", Rules.COLOR_GOLD)
	else:
		_par_label.text = "PAR %s  ·  MISSED" % _clock(int(par))
		_par_label.add_theme_color_override("font_color", Rules.COLOR_FAULT)


func _clock(seconds: int) -> String:
	return "%02d:%02d" % [seconds / 60, seconds % 60]


func _process(delta: float) -> void:
	# While waking up in bed, the player's eyelids drive the black overlay.
	if is_instance_valid(_player) and _player.waking:
		_fade.color.a = _player.wake_blink
	var seconds_left := int(ceil(gm.reserve))
	_reserve_label.text = "RESERVE %02d:%02d%s" % [floori(seconds_left / 60.0), seconds_left % 60, "  LOW" if save.cues and gm.reserve < 60.0 else ""]
	_reserve_label.add_theme_color_override(
		"font_color", Rules.COLOR_FAULT if gm.reserve < 60.0 else Color.WHITE)
	_update_par_label()
	_update_captions()
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
	if event.is_action_pressed("pause_game") and _settings_panel != null:
		_close_settings()   # (a key being rebound is handled by the panel first, and Esc cancels it)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("pause_game"):
		if gm.state == GameManager.State.MENU or _modal_layer != null:
			return
		if _oracle_panel != null:
			_close_oracle()
		elif _manuals != null:
			_close_manuals()
		elif _log_panel != null:
			_close_log()
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
			_front_view = false
			_player.set_third_person(_third_person, _front_view)
			_show_notice("THIRD PERSON VIEW" if _third_person else "FIRST PERSON VIEW")
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("flip_view"):
		# C swings the camera round to the front, to see the character's face (and back again).
		if gm.state == GameManager.State.PLAYING and _player != null and not _paused and _modal_layer == null:
			_front_view = not (_third_person and _front_view)
			_third_person = true
			_player.set_third_person(_third_person, _front_view)
			_show_notice("FRONT VIEW: PRESS %s TO GO BACK" % KeyBindings.key_text(int(save.bindings["flip_view"])) if _front_view else "THIRD PERSON VIEW")
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


## Repairing a system shuts down the hazard it was feeding: the gravity zone just beyond the room
## (Comms switches off the first grid, Cooling the second), the corridor vent between Power and
## Oxygen (when Oxygen is repaired) and the gas leaks in the Oxygen and Cooling rooms. Returns
## the messages to show. The hazards stay off for the rest of the shift.
func _seal_hazards_for(system_id: String) -> Array[String]:
	var notes: Array[String] = []
	var gravity_zones: Array = _station["gravity_zones"]
	match system_id:
		"comms":
			if gravity_zones.size() > 0 and not (gravity_zones[0] as GravityZone).offline:
				(gravity_zones[0] as GravityZone).go_offline()
				_remove_gravity_switches(gravity_zones[0] as GravityZone)
				notes.append("GRAVITY ZONE 1 STABILISED")
		"cooling":
			if gravity_zones.size() > 1 and not (gravity_zones[1] as GravityZone).offline:
				(gravity_zones[1] as GravityZone).go_offline()
				_remove_gravity_switches(gravity_zones[1] as GravityZone)
				notes.append("GRAVITY ZONE 2 STABILISED")
	if system_id == "oxygen":
		var vents: Array = _station["hazards"]
		if vents.size() > 1:
			(vents[1] as HazardZone).seal()
			notes.append("GAS VENT 2 SEALED")
	var leaks: Dictionary = _station["room_leaks"]
	if leaks.has(system_id):
		(leaks[system_id] as HazardZone).seal()
		notes.append("GAS LEAK SEALED")
	return notes


## Every gas zone: the two corridor vents and any room leaks.
func _gas_zones() -> Array:
	var zones: Array = (_station["hazards"] as Array).duplicate()
	for leak in (_station["room_leaks"] as Dictionary).values():
		zones.append(leak)
	return zones


## The player's current key for an action, as text (for messages).
func _key(action: String) -> String:
	return KeyBindings.key_text(int(save.bindings[action]))


## Shift 1 is a guided shift: one line says what to do next. Empty on later shifts.
func _coach_text() -> String:
	if gm.run_number != 1 or gm.state != GameManager.State.PLAYING:
		return ""
	if gm.repaired_count() == Rules.SYSTEMS_TOTAL:
		return "All systems repaired! Walk back west along the corridor and press %s on the reboot terminal. It asks for a code: watch the lights, then press %s and ask ORACLE how to enter it." % [_key("interact"), _key("toggle_oracle")]
	for id in GameManager.SYSTEM_IDS:
		if gm.repaired.get(id, false):
			continue
		match id:
			"power":
				return "NEXT: leave the crew quarters and go east to the POWER room (first door). Read LOAD MODE and the breaker voltages, then press %s and ask ORACLE which breaker first." % _key("toggle_oracle")
			"oxygen":
				return "NEXT: the OXYGEN room (second door, now unlocked). Mind the gas vent on the way. Read STATION MODE, then press %s and ask ORACLE for the valve settings." % _key("toggle_oracle")
			"comms":
				return "NEXT: the COMMS room (third door, now unlocked). Mind the zero-gravity zone on the way (use a wall switch to restore gravity). Count the lit beacons, then press %s and ask ORACLE for the frequency." % _key("toggle_oracle")
			_:
				return "NEXT: the COOLING room (fourth door, now unlocked). Read the CORE TEMP and the REACTOR state, then press %s and ask ORACLE for the coolant flow." % _key("toggle_oracle")
	return ""


## The on-screen objective list: which systems are repaired and what is next.
func _checklist_text() -> String:
	var rooms := {"power": "1st room", "oxygen": "2nd room", "comms": "3rd room", "cooling": "4th room"}
	var protocol: String = gm.puzzles.get("protocol", "A")
	var lines: Array[String] = ["REPAIR THE STATION  ·  PROTOCOL %s  ·  %s%s" % [protocol, Rules.level_name().to_upper(), ("  ·  " + Rules.mods_text().to_upper()) if Rules.mods != 0 else ""]]
	for id in GameManager.SYSTEM_IDS:
		var mark := "[x]" if gm.repaired.get(id, false) else "[ ]"
		lines.append("%s %s (%s)" % [mark, id.capitalize(), rooms[id]])
	if gm.repaired_count() == Rules.SYSTEMS_TOTAL:
		lines.append("-> REBOOT: terminal at the west end")
	else:
		lines.append("[ ] Reboot (needs %d/%d)" % [Rules.SYSTEMS_TOTAL, Rules.SYSTEMS_TOTAL])
	return "\n".join(lines)


func _new_seed() -> int:
	return _rng.randi()


func _can_open_overlay() -> bool:
	return (gm.state == GameManager.State.PLAYING and not _paused
		and _panel == null and _manuals == null and _log_panel == null and _oracle_panel == null and _modal_layer == null)


# --- Input map ----------------------------------------------------------

## Registers every key (the player's own bindings from the save file, Escape fixed).
func _setup_input() -> void:
	KeyBindings.apply(save.bindings)


func _add_action(action: StringName, keys: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for key in keys:
		var event := InputEventKey.new()
		event.physical_keycode = key
		InputMap.action_add_event(action, event)


# --- Game flow ------------------------------------------------------------

## The level picked on the menu: used from the next Play, and remembered in the save file.
func _set_level(level: int) -> void:
	Rules.level = clampi(level, Rules.LEVEL_ROOKIE, Rules.LEVEL_SURVIVOR)
	save.set_difficulty(Rules.level)


## A modifier switched on or off on the menu: used from the next Play (not saved).
func _set_modifier(flag: int, on: bool) -> void:
	Rules.set_mod(flag, on)


## Main Menu > Play: a brand new run with a new seed. The intro card is shown
## once, the first time the game is played.
func _start_new_game() -> void:
	_menu_layer.visible = false
	_hud_layer.visible = true
	gm.start_shift(_new_seed(), dev_start_shift)
	_rebuild_world()
	if not save.intro_seen:
		_show_how_to_play(true)


## Leaves the current shift completely: frees the world, clears every overlay,
## and shows the Main Menu.
func _go_to_menu() -> void:
	_close_panel()
	_close_manuals()
	_close_log()
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
	_menu_screen.set_level(Rules.level)
	_menu_screen.set_modifiers(Rules.mods)
	_menu_layer.visible = true
	_refresh_input_state()


func _free_world() -> void:
	if _world != null:
		remove_child(_world)
		_world.queue_free()
		_world = null
	_player = null
	_station = {}
	if _fade_tween != null:
		_fade_tween.kill()   # a running fade-in would bring the black back
	_fade.color.a = 0.0   # never leave the screen black if the player was still waking up


func _retry() -> void:
	if Rules.has_mod(Rules.MOD_HARDCORE):
		_show_notice("NO RETRIES IN HARDCORE")   # the one-life rule: a lost shift ends the run
		return
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
	_close_log()
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
	# A soft bloom on the emissive lights and a filmic tone curve smooth the harsh edges.
	environment.glow_enabled = true
	environment.glow_intensity = 0.7
	environment.glow_bloom = 0.1
	environment.glow_hdr_threshold = 0.9
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_white = 6.0
	_environment = environment
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	_world.add_child(world_environment)

	_station = StationBuilder.build(_world, gm.puzzles, _theme, gm.run_number)
	_update_pods()
	_update_cues()

	_player = PlayerController.new()
	_player.name = "Player"
	_player.position = _station["spawn"]
	_player.rotation.y = deg_to_rad(float(_station["spawn_yaw"]))
	for zone in _gas_zones():
		(zone as HazardZone).hit.connect(_on_hazard_zone_hit)
	for gravity in _station["gravity_zones"]:
		(gravity as GravityZone).touched.connect(_on_gravity_touched)
		(gravity as GravityZone).state_changed.connect(_on_gravity_state_changed.bind(gravity))
	_player.mouse_sensitivity = Rules.MOUSE_SENSITIVITY * save.mouse_sens
	_world.add_child(_player)
	_player.target_changed.connect(_on_target_changed)
	_player.first_move.connect(gm.begin_clock)
	_player.stepped.connect(sound.play.bind("step"))
	_player.set_third_person(_third_person, _front_view)
	_player.wake_bed_position = _station["bed_position"]
	_player.woke_up.connect(_on_player_woke_up)
	if play_wake_sequence and gm.run_number == 1 and gm.retry_count == 0:
		# Only the very first shift of a run wakes you up in bed. After that you are already
		# awake, so retries and later shifts simply fade in with you standing by the bunk.
		_player.play_wake_up(true)
	else:
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
		var growth := ""
		if gm.second_gravity_new:
			growth = "  ·  A SECOND ZERO-GRAVITY ZONE"
		elif gm.run_number > 1:
			growth = "  ·  HAZARDS GROW"
		if gm.adapt_steps > 0:
			growth += "  ·  ADAPTED: HARDER"
		elif gm.adapt_steps < 0:
			growth += "  ·  ADAPTED: EASIER"
		_show_notice("SHIFT %02d  ·  %s WING%s" % [gm.run_number, _theme["name"], growth])
	_refresh_input_state()


## Player input and mouse capture follow the UI state in exactly one place.
func _refresh_input_state() -> void:
	_input_free = (gm.state == GameManager.State.PLAYING and not _paused
		and _panel == null and _manuals == null and _log_panel == null and _oracle_panel == null and _modal_layer == null)
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
	# Speedrun: the par time, shown under the reserve.
	_par_label = _make_label("", 17, 0.075, 0.115, Rules.COLOR_GOLD, HORIZONTAL_ALIGNMENT_RIGHT)
	_par_label.offset_right = -24
	_par_label.visible = false
	_hud_layer.add_child(_par_label)
	# Sound captions: short lines of text for the sounds that warn of something.
	_caption_label = _make_label("", 18, 0.50, 0.78, Color(1, 1, 1, 0.92), HORIZONTAL_ALIGNMENT_LEFT)
	_caption_label.offset_left = 24
	_caption_label.anchor_right = 0.5
	_caption_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_hud_layer.add_child(_caption_label)

	_prompt_label = _make_label("", 22, 0.56, 0.62, Rules.COLOR_GOLD)
	_hud_layer.add_child(_prompt_label)

	_notice_label = _make_label("", 22, 0.09, 0.15, Rules.COLOR_CYAN)
	_hud_layer.add_child(_notice_label)

	_help_label = _make_label(KeyBindings.help_text(save.bindings), 15, 0.94, 0.99, Color(1, 1, 1, 0.75))
	_hud_layer.add_child(_help_label)

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
		boot_intro,
		_set_level,
		save.difficulty,
		_set_modifier,
		save.modifiers)
	_menu_screen.name = "MenuScreen"
	_menu_screen.settings_requested.connect(_open_settings)
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
	_pause_retry_button = _make_menu_button("Retry Shift", _retry)
	column.add_child(_pause_retry_button)
	column.add_child(_make_menu_button("Settings", _open_settings))
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
		# Hardcore has no retries: the pause menu's Retry button is greyed out.
		_pause_retry_button.disabled = Rules.has_mod(Rules.MOD_HARDCORE)
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
	if kind != "reboot" and gm.repaired[kind]:
		_show_notice("%s ALREADY REPAIRED" % kind.to_upper())
		return
	if _panel != null:
		return
	_panel = PuzzlePanel.create(kind, gm)
	_panel.closed.connect(_close_panel)
	_panel.solved.connect(_close_panel)
	if kind == "reboot":
		_panel.solved.connect(func() -> void: gm.try_reboot())   # the code was right: reboot the station
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


## The Settings window, on top of the menu or the pause menu. Changes are saved at once.
func _open_settings() -> void:
	if _settings_panel != null:
		return
	_settings_layer = CanvasLayer.new()
	_settings_layer.name = "SettingsLayer"
	_settings_layer.layer = 25
	add_child(_settings_layer)
	var root_control := Control.new()
	root_control.set_anchors_preset(Control.PRESET_FULL_RECT)
	_settings_layer.add_child(root_control)
	var dim := ColorRect.new()
	dim.color = Color(Rules.COLOR_NAVY, 0.92)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	root_control.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root_control.add_child(center)
	_settings_panel = SettingsPanel.create(save)
	# The list scrolls, so the window always fits: leave room for the title, message and Close.
	var window_height := get_viewport().get_visible_rect().size.y
	(_settings_panel.find_children("*", "ScrollContainer", true, false)[0] as ScrollContainer).custom_minimum_size.y = clampf(window_height - 230.0, 150.0, 560.0)
	_settings_panel.changed.connect(_apply_settings)
	_settings_panel.closed.connect(_close_settings)
	_settings_panel.preview_sound.connect(func() -> void: sound.play("click"))
	center.add_child(_settings_panel)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _close_settings() -> void:
	if _settings_panel != null:
		_settings_layer.queue_free()
		_settings_layer = null
		_settings_panel = null
		_apply_settings()
		_refresh_input_state()


## The colour-blind cues: a cross or a tick beside each room's name (shown or hidden by the
## setting), and the words beside the gas lamps. Looks only.
func _update_cues() -> void:
	if _station.is_empty():
		return
	for room_id in _station["door_icons"]:
		var icons: Dictionary = _station["door_icons"][room_id]
		var fixed: bool = gm.repaired.get(room_id, false)
		(icons["fault"] as Node3D).visible = save.cues and not fixed
		(icons["ok"] as Node3D).visible = save.cues and fixed
	for zone in _gas_zones():
		(zone as HazardZone).cues = save.cues


## Pushes the saved settings into the running game: volumes, mouse speed, keys and the help line.
func _apply_settings() -> void:
	Rules.adaptive = save.adaptive
	sound.music_volume = save.music_volume
	sound.sfx_volume = save.sfx_volume
	KeyBindings.apply(save.bindings)
	if _help_label != null:
		_help_label.text = KeyBindings.help_text(save.bindings)
	if is_instance_valid(_player):
		_player.mouse_sensitivity = Rules.MOUSE_SENSITIVITY * save.mouse_sens
	_update_cues()


## A crew log from the Cryo Bay. Like the manuals it pauses the game, so reading is free.
func _open_log(number: int) -> void:
	if gm.state != GameManager.State.PLAYING or _log_panel != null or number < 1 or number > CrewLogs.count():
		return
	save.mark_log_read(number)
	var footer := "Logs read: %d/%d   (nothing here changes the game)" % [save.logs_read_count(), CrewLogs.count()]
	_log_panel = LogPanel.create(CrewLogs.title(number - 1), CrewLogs.text(number - 1), footer)
	_log_panel.closed.connect(_close_log)
	_panel_center.add_child(_log_panel)
	_prompt_label.text = ""
	get_tree().paused = true
	_refresh_input_state()


func _close_log() -> void:
	if _log_panel != null:
		_log_panel.queue_free()
		_log_panel = null
		get_tree().paused = _paused
	_refresh_input_state()


## The sleeping crew's pods glow red while the station is broken and turn cyan as it is
## repaired. Looks only; it reads the repair count and changes nothing.
func _update_pods() -> void:
	if _station.is_empty() or not _station.has("pods"):
		return
	var repaired_share := float(gm.repaired_count()) / float(Rules.SYSTEMS_TOTAL)
	for glow in _station["pods"]:
		var color := Rules.COLOR_FAULT.lerp(Rules.COLOR_CYAN, repaired_share)
		(glow as StandardMaterial3D).albedo_color = color
		(glow as StandardMaterial3D).emission = color
		(glow as StandardMaterial3D).emission_energy_multiplier = 0.8 + 0.8 * repaired_share


## ORACLE pauses the whole game (and so the reserve) while open.
func _open_oracle() -> void:
	if _oracle_panel != null:
		return
	_oracle_panel = OraclePanel.create(oracle)
	_oracle_panel.closed.connect(_close_oracle)
	_oracle_panel.hint_requested.connect(_on_hint_requested)
	_oracle_panel.question_sent.connect(_on_oracle_question_sent)
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
## A grid that is offline for good no longer needs its wall switches: hide them and make
## them impossible to aim at, so no "turn gravity zone off" prompt appears any more.
func _remove_gravity_switches(grid: GravityZone) -> void:
	for gravity_switch in _station["gravity_switches"]:
		var switch_node := gravity_switch as Interactable
		if switch_node.get_meta("gravity_zone") == grid:
			switch_node.enabled = false
			switch_node.visible = false
			switch_node.collision_layer = 0


## The player touched the gravity zone while it was on.
func _on_gravity_touched(seconds: float) -> void:
	gm.hazard_damage("gravity", seconds)
	_hit_danger = 1.0
	_flash_fault()
	sound.play("buzz")
	_show_notice("ZERO GRAVITY  -%d s. Use a wall switch to restore gravity." % int(seconds))


func _on_gravity_state_changed(armed: bool, grid: GravityZone) -> void:
	for gravity_switch in _station["gravity_switches"]:
		if (gravity_switch as Interactable).get_meta("gravity_zone") == grid:
			(gravity_switch as Interactable).set_color(Rules.COLOR_VIOLET if armed else Rules.COLOR_CYAN)
	if armed:
		sound.play("tick")


func _on_oracle_question_sent() -> void:
	var cost := gm.charge_oracle_question()
	if is_instance_valid(_oracle_panel):
		_oracle_panel.add_cost_line(cost)


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


func _on_player_woke_up() -> void:
	_fade.color.a = 0.0


## Fades the screen in from black when a shift (or a retry) begins.
func _fade_in() -> void:
	_fade.color.a = 1.0
	if _fade_tween != null:
		_fade_tween.kill()
	_fade_tween = create_tween()
	_fade_tween.tween_property(_fade, "color:a", 0.0, FADE_IN_SECONDS)


# --- Signals from the world -------------------------------------------------

func _on_target_changed(target: Interactable) -> void:
	_prompt_label.text = "%s — %s" % [KeyBindings.key_text(int(save.bindings["interact"])), target.prompt] if target != null else ""


func _on_interacted(item: Interactable, _player_node: Node) -> void:
	if gm.state != GameManager.State.PLAYING:
		return
	var id := item.id
	item.play_press()
	if id.begins_with("breaker_"):
		_handle_breaker(int(id.substr("breaker_".length())))
	elif id.begins_with("gravity_switch"):
		sound.play("click")
		var grid: GravityZone = item.get_meta("gravity_zone")
		if grid.offline:
			_show_notice("GRAVITY IS ALREADY STABLE HERE", 2.5)
			return
		grid.switch_off()
		_show_notice("GRAVITY RESTORED FOR %d s. Walk through now." % int(grid.off_seconds), 3.0)
	elif id == "oxygen_console":
		sound.play("hiss")
		_open_panel("oxygen")
	elif id == "comms_console":
		sound.play("hiss")
		_open_panel("comms")
	elif id == "cooling_console":
		sound.play("hiss")
		_open_panel("cooling")
	elif id.begins_with("crew_log_"):
		sound.play("click")
		_open_log(int(id.substr("crew_log_".length())))
	elif id == "reboot_terminal":
		if gm.repaired_count() < Rules.SYSTEMS_TOTAL:
			sound.play("buzz")
			_show_notice("ALL %d SYSTEMS MUST BE REPAIRED" % Rules.SYSTEMS_TOTAL)
		else:
			sound.play("hiss")
			_open_panel("reboot")


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
	_update_pods()
	sound.play("fan_up")   # the ventilation spins back up
	# Doors that were waiting for this system slide open.
	var notes: Array[String] = []
	for room_id in _station["doors"]:
		var gate: DoorGate = _station["doors"][room_id]
		var was_locked := gate.locked
		gate.refresh(gm.repaired)
		if was_locked and not gate.locked:
			notes.append("%s DOOR UNLOCKED" % String(room_id).to_upper())
			sound.play("door_slide")
	notes.append_array(_seal_hazards_for(system_id))
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
	_update_cues()
	# The door frame and light turn from red to cyan.
	var status: StandardMaterial3D = _station["door_status"][system_id]
	status.albedo_color = Rules.COLOR_CYAN
	status.emission = Rules.COLOR_CYAN
	if system_id == "cooling":
		# The reactor core cools from hot orange to cyan.
		var reactor: StandardMaterial3D = _station["reactor"]
		reactor.albedo_color = Rules.COLOR_CYAN
		reactor.emission = Rules.COLOR_CYAN
	if system_id == "power":
		for breaker in _station["breakers"]:
			(breaker as Interactable).set_color(Rules.COLOR_CYAN)
	else:
		(_station["consoles"][system_id] as Interactable).set_color(Rules.COLOR_CYAN)
	# One notice: the repair, then anything it unlocked, switched off or sealed.
	var headline := "%s SYSTEM REPAIRED" % system_id.to_upper()
	if gm.repaired_count() == Rules.SYSTEMS_TOTAL:
		headline = "ALL SYSTEMS REPAIRED — REBOOT THE STATION"
		# The reboot terminal changes colour so it is easy to spot in the hub.
		(_station["reboot"] as Interactable).set_color(Rules.COLOR_CYAN)
	notes.push_front(headline)
	_show_notice("  ·  ".join(notes), NOTICE_SECONDS + 1.0)


## A hazard zone saw the player inside while active. GameManager applies the cost.
func _on_hazard_zone_hit(kind: String, seconds: float, first: bool) -> void:
	gm.hazard_damage(kind, seconds)
	_hit_danger = 1.0
	if first:
		_flash_fault()
		sound.play("hiss")
		_show_notice("GAS LEAK!  Reserve is draining fast. Get out, or wait for the lamp to turn grey.")


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
	var speed_line := ""
	if Rules.has_mod(Rules.MOD_SPEEDRUN):
		speed_line = "\nSpeed bonus: +%d  (par %s, you used %s)" % [result["speed_bonus"], _clock(int(result["par"])), _clock(int(result["spent"]))]
	var body := "Reserve remaining: %d s\nSystems repaired: %d/%d\nMistakes: %d     Retries: %d     Hints: %d\n\nBase points: %d\nTime bonus: +%d\nRetry penalty: -%d%s\nLevel: %s%s (score x%.2f)\n\nSHIFT SCORE: %d\n%s\n%s\n\nNext shift: %d s of reserve     Seed: %d" % [
		result["reserve_remaining"], Rules.SYSTEMS_TOTAL, Rules.SYSTEMS_TOTAL, result["mistakes"], result["retries"], result["hints"],
		result["base"], result["time_bonus"], result["retry_penalty"],
		speed_line, Rules.level_name(), (" + " + Rules.mods_text()) if Rules.mods != 0 else "", result["multiplier"],
		result["final"], best_line, run_line, result["next_reserve"], result["seed"]]
	# The adaptation goes first: it is what the player most wants to know about the next shift.
	var adaptation: Dictionary = result["adaptation"]
	if adaptation["enabled"]:
		body = "ADAPTIVE DIFFICULTY: next shift %s\nYou used %d%% of the reserve (%d%% averaged with your last shift), with %d mistakes and %d retries.\n%s\n\n%s" % [
			AdaptiveDifficulty.label(int(adaptation["decision"])), int(round(float(adaptation["ratio"]) * 100.0)), int(round(float(adaptation["average"]) * 100.0)),
			result["mistakes"], result["retries"], adaptation["reason"], body]
	else:
		body = "%s\n\n%s" % [adaptation["reason"], body]
	_show_modal("STATION REBOOTED", Rules.COLOR_CYAN, body, [
		{"label": "Next Shift", "action": _next_shift},
		{"label": "Main Menu", "action": _go_to_menu},
		{"label": "Quit", "action": func() -> void: get_tree().quit()},
	])


func _on_shift_failed() -> void:
	sound.play("fail")
	_close_panel()
	_close_manuals()
	_close_log()
	_close_oracle()
	if Rules.has_mod(Rules.MOD_HARDCORE):
		# One life: the run is over and its score is cleared (the best run already saved stays).
		var lost := gm.run_score
		gm.run_score = 0
		_show_modal("RUN OVER", Rules.COLOR_FAULT,
			"The station is lost, and Hardcore allows no second chance.\nRun score cleared (it was %d). Your best run is kept." % lost, [
			{"label": "New Run", "action": _start_new_game},
			{"label": "Main Menu", "action": _go_to_menu},
			{"label": "Quit", "action": func() -> void: get_tree().quit()},
		])
		return
	_show_modal("OXYGEN RESERVE DEPLETED", Rules.COLOR_FAULT,
		"The station is lost.\nRetrying restarts this shift with new puzzle values.", [
		{"label": "Retry Shift", "action": _retry},
		{"label": "Main Menu", "action": _go_to_menu},
		{"label": "Quit", "action": func() -> void: get_tree().quit()},
	])
