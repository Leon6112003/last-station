class_name KeyBindings
extends RefCounted
## The rebindable keys. Each action has one main key the player can change in Settings; the
## movement actions also keep their arrow key as a second key (unless another action uses it).
## Escape (pause, close a window) is fixed and cannot be rebound. This class only edits Godot's
## InputMap and describes the keys; it holds no game rules.

const ACTIONS: Array[Dictionary] = [
	{"id": "move_forward", "label": "Move forward", "key": KEY_W, "extra": [KEY_UP]},
	{"id": "move_backward", "label": "Move backward", "key": KEY_S, "extra": [KEY_DOWN]},
	{"id": "move_left", "label": "Move left", "key": KEY_A, "extra": [KEY_LEFT]},
	{"id": "move_right", "label": "Move right", "key": KEY_D, "extra": [KEY_RIGHT]},
	{"id": "interact", "label": "Interact", "key": KEY_E, "extra": []},
	{"id": "retry_level", "label": "Retry (hold)", "key": KEY_R, "extra": []},
	{"id": "toggle_manuals", "label": "Manuals", "key": KEY_M, "extra": []},
	{"id": "toggle_oracle", "label": "ORACLE", "key": KEY_H, "extra": []},
	{"id": "toggle_view", "label": "First / third person", "key": KEY_V, "extra": []},
	{"id": "flip_view", "label": "Front view", "key": KEY_C, "extra": []},
	{"id": "toggle_music", "label": "Music on / off", "key": KEY_B, "extra": []},
	{"id": "toggle_sound", "label": "All sound on / off", "key": KEY_N, "extra": []},
]
const RESERVED_KEY := KEY_ESCAPE
const PAUSE_ACTION := "pause_game"


## The default key for every action: {action id: keycode}.
static func default_keys() -> Dictionary:
	var keys := {}
	for entry in ACTIONS:
		keys[entry["id"]] = int(entry["key"])
	return keys


static func label_of(action: String) -> String:
	for entry in ACTIONS:
		if entry["id"] == action:
			return entry["label"]
	return action


## Writes the bindings into the InputMap (and registers Escape for pausing). Missing or
## invalid entries fall back to the default key.
static func apply(bindings: Dictionary) -> void:
	var keys := normalized(bindings)
	_register(PAUSE_ACTION, [RESERVED_KEY])
	var taken: Array[int] = []
	for action in keys:
		taken.append(int(keys[action]))
	for entry in ACTIONS:
		var key_list: Array[int] = [int(keys[entry["id"]])]
		for extra in entry["extra"]:
			if not taken.has(int(extra)):
				key_list.append(int(extra))
		_register(entry["id"], key_list)


## The bindings with every action present, no duplicate keys and Escape never used. A bad
## entry is replaced by that action's default key.
static func normalized(bindings: Dictionary) -> Dictionary:
	var defaults := default_keys()
	var result := {}
	var used: Array[int] = []
	for entry in ACTIONS:
		var id: String = entry["id"]
		var key := int(bindings.get(id, defaults[id]))
		if key <= 0 or key == RESERVED_KEY or used.has(key):
			key = int(defaults[id])
		if used.has(key):
			key = 0   # the default is taken too: leave unbound rather than clash
		result[id] = key
		if key != 0:
			used.append(key)
	return result


## The action that already uses `keycode` (other than `action`), "" if it is free, or
## PAUSE_ACTION for Escape.
static func conflict(bindings: Dictionary, action: String, keycode: int) -> String:
	if keycode == RESERVED_KEY:
		return PAUSE_ACTION
	var keys := normalized(bindings)
	for other in keys:
		if other != action and int(keys[other]) == keycode:
			return other
	return ""


static func key_text(keycode: int) -> String:
	return OS.get_keycode_string(keycode) if keycode > 0 else "-"


## The one-line key reminder at the bottom of the screen, built from the current bindings.
static func help_text(bindings: Dictionary) -> String:
	var keys := normalized(bindings)
	var move := "%s%s%s%s" % [key_text(keys["move_forward"]), key_text(keys["move_left"]), key_text(keys["move_backward"]), key_text(keys["move_right"])]
	return "%s Move  ·  %s Interact  ·  %s View  ·  %s Front  ·  %s Manuals  ·  %s ORACLE  ·  Esc Pause  ·  Hold %s Retry" % [
		move, key_text(keys["interact"]), key_text(keys["toggle_view"]), key_text(keys["flip_view"]),
		key_text(keys["toggle_manuals"]), key_text(keys["toggle_oracle"]), key_text(keys["retry_level"])]


static func _register(action: String, key_list: Array[int]) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	InputMap.action_erase_events(action)
	for key in key_list:
		if key <= 0:
			continue
		var event := InputEventKey.new()
		event.physical_keycode = key as Key
		InputMap.action_add_event(action, event)
