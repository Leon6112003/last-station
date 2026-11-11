class_name StationBuilder
extends RefCounted
## Builds the fixed station layout and this attempt's puzzle props from boxes.
## No scene files needed. Called again for every attempt, so retries show the
## re-rolled puzzle values.
##
## Plan view (metres, -Z is north, the player spawns in the hub facing north):
##
##   z=-9  +--------+--------+--------+
##         | POWER  | OXYGEN | COMMS  |   rooms, 4 m wide, 6 m deep
##   z=-3  +--[  ]---+--[  ]--+--[  ]--+   doorways 2 m wide at x = -4, 0, 4
##         |            HUB            |   12 m wide, 6 m deep
##   z= 3  +---------------------------+
##        x=-6      x=-2   x=2        x=6

const HUB_HALF_WIDTH := 6.0
const HUB_FRONT_Z := 3.0     # south wall of the hub
const HUB_BACK_Z := -3.0     # wall between hub and rooms
const ROOM_BACK_Z := -9.0    # north wall of the rooms
const DOOR_HALF_WIDTH := 1.0
const ROOM_CENTERS_X := {"power": -4.0, "oxygen": 0.0, "comms": 4.0}
const ROOM_LABELS := {"power": "POWER", "oxygen": "OXYGEN", "comms": "COMMS"}
const SPAWN_POSITION := Vector3(0.0, 0.9, 1.2)
# Terminals must be taller than the eye line (1.55 m) so the interaction ray,
# which starts at the eyes, hits them without the player having to look down.
const TERMINAL_HEIGHT := 1.8
const BREAKER_SPACING := 0.95
const BEACON_SPACING := 0.55
const WALL_FACE_Z := ROOM_BACK_Z + 0.2   # just in front of the north wall's inner face


## Builds the station under `parent` for the given puzzles (from PuzzleGenerator).
## Returns:
## {
##   "spawn": Vector3,
##   "interactables": Array[Interactable],
##   "breakers": Array[Interactable],            # B1..B4 in index order
##   "consoles": {"oxygen": Interactable, "comms": Interactable},
##   "reboot": Interactable,
##   "room_lights": {room_id: OmniLight3D},
##   "door_labels": {room_id: Label3D},
##   "protocol_board": Label3D,                  # big "PROTOCOL A/B" sign in the hub
## }
static func build(parent: Node3D, puzzles: Dictionary) -> Dictionary:
	var wall_material := _solid_material(Rules.COLOR_INDIGO)
	var floor_material := _solid_material(Rules.COLOR_NAVY.lightened(0.12))
	var ceiling_material := _solid_material(Rules.COLOR_NAVY.lightened(0.05))

	var depth := HUB_FRONT_Z - ROOM_BACK_Z                 # 12 m
	var center_z := (HUB_FRONT_Z + ROOM_BACK_Z) * 0.5      # -3 m
	var span_x := HUB_HALF_WIDTH * 2.0 + Rules.WALL_THICKNESS
	var h := Rules.WALL_HEIGHT
	var t := Rules.WALL_THICKNESS

	# Floor and ceiling over the whole footprint.
	_add_box(parent, "Floor", Vector3(0.0, -0.1, center_z), Vector3(span_x, 0.2, depth + t), floor_material)
	_add_box(parent, "Ceiling", Vector3(0.0, h + 0.1, center_z), Vector3(span_x, 0.2, depth + t), ceiling_material)

	# Outer walls.
	_add_box(parent, "WallWest", Vector3(-HUB_HALF_WIDTH, h * 0.5, center_z), Vector3(t, h, depth + t), wall_material)
	_add_box(parent, "WallEast", Vector3(HUB_HALF_WIDTH, h * 0.5, center_z), Vector3(t, h, depth + t), wall_material)
	_add_box(parent, "WallSouth", Vector3(0.0, h * 0.5, HUB_FRONT_Z), Vector3(span_x, h, t), wall_material)
	_add_box(parent, "WallNorth", Vector3(0.0, h * 0.5, ROOM_BACK_Z), Vector3(span_x, h, t), wall_material)

	# Dividers between the three rooms.
	var room_depth := HUB_BACK_Z - ROOM_BACK_Z             # 6 m
	var room_center_z := (HUB_BACK_Z + ROOM_BACK_Z) * 0.5  # -6 m
	for divider_x in [-2.0, 2.0]:
		_add_box(parent, "Divider", Vector3(divider_x, h * 0.5, room_center_z), Vector3(t, h, room_depth), wall_material)

	# Hub/room wall with three doorways, built from the solid segments between them.
	var door_xs: Array = ROOM_CENTERS_X.values()
	door_xs.sort()
	var cursor := -HUB_HALF_WIDTH
	for door_x in door_xs:
		_add_wall_segment(parent, cursor, door_x - DOOR_HALF_WIDTH, wall_material)
		cursor = door_x + DOOR_HALF_WIDTH
	_add_wall_segment(parent, cursor, HUB_HALF_WIDTH, wall_material)

	# Lighting: one cool hub light, one red (faulted) light per room, and a red
	# door label per room. Main turns them cyan when the system is repaired.
	var room_lights := {}
	var door_labels := {}
	_add_light(parent, Vector3(0.0, 2.6, 0.0), Color(0.8, 0.86, 1.0), 1.3, 9.0)
	for room_id in ROOM_CENTERS_X:
		var x: float = ROOM_CENTERS_X[room_id]
		room_lights[room_id] = _add_light(parent, Vector3(x, 2.6, room_center_z), Rules.COLOR_FAULT, 1.5, 6.5)
		door_labels[room_id] = _add_label(parent, ROOM_LABELS[room_id], Vector3(x, 2.6, HUB_BACK_Z + 0.2), 40, Rules.COLOR_FAULT)

	var interactables: Array[Interactable] = []

	# The protocol board: a big sign on the hub wall, in view when you spawn.
	var protocol: String = puzzles.get("protocol", "A")
	_add_screen(parent, Vector3(2.0, 1.75, HUB_BACK_Z + 0.17), Vector2(1.8, 1.25))
	var protocol_board := _add_label(parent, "PROTOCOL %s" % protocol, Vector3(2.0, 2.15, HUB_BACK_Z + 0.2), 46, Rules.COLOR_GOLD)
	_add_label(parent, "The rules depend on\nthe protocol. Ask ORACLE (H)\nor read the manuals (M).", Vector3(2.0, 1.55, HUB_BACK_Z + 0.2), 22, Color(1, 1, 1, 0.9))

	# Dark glowing display plates behind the wall text, so it reads clearly.
	var power_center_x: float = ROOM_CENTERS_X["power"]
	var oxygen_center_x: float = ROOM_CENTERS_X["oxygen"]
	var comms_center_x: float = ROOM_CENTERS_X["comms"]
	_add_screen(parent, Vector3(power_center_x, 2.4, ROOM_BACK_Z + 0.17), Vector2(3.6, 1.2))
	_add_screen(parent, Vector3(oxygen_center_x, 2.4, ROOM_BACK_Z + 0.17), Vector2(3.4, 0.55))
	_add_screen(parent, Vector3(comms_center_x, 2.55, ROOM_BACK_Z + 0.17), Vector2(3.6, 0.9))

	# Power room: four breakers with printed ratings, and the load-mode display.
	var power: Dictionary = puzzles["power"]
	var power_x: float = ROOM_CENTERS_X["power"]
	var breakers: Array[Interactable] = []
	for i in Rules.BREAKER_COUNT:
		var x := power_x + (float(i) - (Rules.BREAKER_COUNT - 1) * 0.5) * BREAKER_SPACING
		var breaker := _add_interactable(
			parent, "breaker_%d" % i, "FLIP BREAKER B%d" % (i + 1),
			Vector3(x, TERMINAL_HEIGHT * 0.5, ROOM_BACK_Z + 0.4), Vector3(0.6, TERMINAL_HEIGHT, 0.4), Rules.COLOR_VIOLET)
		breakers.append(breaker)
		interactables.append(breaker)
		_add_label(parent, "B%d\n%d V" % [i + 1, power["ratings"][i]], Vector3(x, 2.05, WALL_FACE_Z), 36, Rules.COLOR_GOLD)
	_add_label(parent, "LOAD MODE: %s" % power["mode"], Vector3(power_x, 2.88, WALL_FACE_Z), 38, Rules.COLOR_CYAN)

	# Oxygen room: station-mode display and the valve console.
	var oxygen_x: float = ROOM_CENTERS_X["oxygen"]
	_add_label(parent, "STATION MODE: %s" % puzzles["oxygen"]["mode"], Vector3(oxygen_x, 2.4, WALL_FACE_Z), 40, Rules.COLOR_CYAN)
	var oxygen_console := _add_interactable(
		parent, "oxygen_console", "OPEN VALVE CONTROLS",
		Vector3(oxygen_x, TERMINAL_HEIGHT * 0.5, ROOM_BACK_Z + 0.5), Vector3(1.2, TERMINAL_HEIGHT, 0.6), Rules.COLOR_VIOLET)
	interactables.append(oxygen_console)

	# Comms room: a row of beacons (some lit) and the tuner console.
	var comms_x: float = ROOM_CENTERS_X["comms"]
	_add_beacons(parent, comms_x, int(puzzles["comms"]["lit"]))
	_add_label(parent, "BEACON ARRAY", Vector3(comms_x, 2.8, WALL_FACE_Z), 34, Rules.COLOR_CYAN)
	var comms_console := _add_interactable(
		parent, "comms_console", "OPEN FREQUENCY TUNER",
		Vector3(comms_x, TERMINAL_HEIGHT * 0.5, ROOM_BACK_Z + 0.5), Vector3(1.2, TERMINAL_HEIGHT, 0.6), Rules.COLOR_VIOLET)
	interactables.append(comms_console)

	# Hub: the reboot terminal on the south wall.
	var reboot := _add_interactable(
		parent, "reboot_terminal", "REBOOT STATION",
		Vector3(0.0, TERMINAL_HEIGHT * 0.5, HUB_FRONT_Z - 0.6), Vector3(1.4, TERMINAL_HEIGHT, 0.5), Rules.COLOR_GOLD)
	interactables.append(reboot)

	return {
		"spawn": SPAWN_POSITION,
		"interactables": interactables,
		"breakers": breakers,
		"consoles": {"oxygen": oxygen_console, "comms": comms_console},
		"reboot": reboot,
		"room_lights": room_lights,
		"door_labels": door_labels,
		"protocol_board": protocol_board,
	}


## A thin, dark plate with a faint cyan glow. No collision: purely visual.
static func _add_screen(parent: Node3D, center: Vector3, size: Vector2) -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.03, 0.04, 0.09)
	material.emission_enabled = true
	material.emission = Rules.COLOR_CYAN
	material.emission_energy_multiplier = 0.12
	var box := BoxMesh.new()
	box.size = Vector3(size.x, size.y, 0.04)
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = box
	mesh_instance.material_override = material
	mesh_instance.position = center
	mesh_instance.name = "Screen"
	parent.add_child(mesh_instance)


static func _add_beacons(parent: Node3D, center_x: float, lit_count: int) -> void:
	# Which beacons are lit is a fixed pattern (the first `lit_count`); only the
	# count matters to the puzzle.
	for i in Rules.BEACON_COUNT:
		var lit := i < lit_count
		# Unshaded so the red room light cannot wash the colour out to white.
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color = Rules.COLOR_CYAN if lit else Color(0.1, 0.11, 0.15)

		var sphere := SphereMesh.new()
		sphere.radius = 0.18
		sphere.height = 0.36
		var mesh_instance := MeshInstance3D.new()
		mesh_instance.mesh = sphere
		mesh_instance.material_override = material
		mesh_instance.position = Vector3(
			center_x + (float(i) - (Rules.BEACON_COUNT - 1) * 0.5) * BEACON_SPACING, 2.3, ROOM_BACK_Z + 0.35)
		mesh_instance.name = "Beacon%d" % i
		parent.add_child(mesh_instance)


static func _add_wall_segment(parent: Node3D, x_from: float, x_to: float, material: Material) -> void:
	if x_to - x_from <= 0.01:
		return
	var width := x_to - x_from
	_add_box(parent, "WallSegment", Vector3((x_from + x_to) * 0.5, Rules.WALL_HEIGHT * 0.5, HUB_BACK_Z),
		Vector3(width, Rules.WALL_HEIGHT, Rules.WALL_THICKNESS), material)


static func _solid_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.9
	return material


static func _add_box(parent: Node3D, node_name: String, center: Vector3, size: Vector3, material: Material) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = node_name
	body.position = center
	body.collision_layer = Rules.LAYER_WORLD
	body.collision_mask = 0

	var box := BoxMesh.new()
	box.size = size
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = box
	mesh_instance.material_override = material
	body.add_child(mesh_instance)

	var shape := BoxShape3D.new()
	shape.size = size
	var collider := CollisionShape3D.new()
	collider.shape = shape
	body.add_child(collider)

	parent.add_child(body)
	return body


static func _add_light(parent: Node3D, position: Vector3, color: Color, energy: float, light_range: float) -> OmniLight3D:
	var light := OmniLight3D.new()
	light.position = position
	light.light_color = color
	light.light_energy = energy
	light.omni_range = light_range
	parent.add_child(light)
	return light


static func _add_label(parent: Node3D, text: String, position: Vector3, font_size: int, color: Color) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.position = position
	label.font_size = font_size
	label.pixel_size = 0.006
	label.modulate = color
	label.outline_size = 8
	parent.add_child(label)
	return label


static func _add_interactable(parent: Node3D, id: String, prompt: String, position: Vector3, size: Vector3, color: Color) -> Interactable:
	var item := Interactable.new()
	item.name = id
	item.id = id
	item.prompt = prompt
	item.position = position
	item.setup(size, color)
	parent.add_child(item)
	return item
