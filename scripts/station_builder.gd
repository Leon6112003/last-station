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
##   z=-3  +--[##]---+--[##]--+--[##]--+   doorways 2 m wide at x = -4, 0, 4,
##         |  [A]   guide   [B]        |   with a header sign above each one;
##         |           HUB             |   a board flanks the middle door;
##   z= 3  +---------------------------+   coloured floor lines lead to each door
##        x=-6      x=-2   x=2        x=6
##
## Design rules: every sign sits ON a surface (a header, a plate, a breaker or a
## console), never floating; text of one kind uses one size.

const HUB_HALF_WIDTH := 6.0
const HUB_FRONT_Z := 3.0     # south wall of the hub
const HUB_BACK_Z := -3.0     # wall between hub and rooms
const ROOM_BACK_Z := -9.0    # north wall of the rooms
const DOOR_HALF_WIDTH := 1.0
const DOOR_HEIGHT := 2.3     # the header above a doorway starts here
const ROOM_CENTERS_X := {"power": -4.0, "oxygen": 0.0, "comms": 4.0}
const ROOM_LABELS := {"power": "POWER", "oxygen": "OXYGEN", "comms": "COMMS"}
const ROOM_FLOOR_TINT := {
	"power": Color(0.20, 0.12, 0.36),
	"oxygen": Color(0.07, 0.24, 0.28),
	"comms": Color(0.30, 0.24, 0.10),
}
const SPAWN_POSITION := Vector3(0.0, 0.9, 1.2)
# Terminals must be taller than the eye line (1.55 m) so the interaction ray,
# which starts at the eyes, hits them without the player having to look down.
const TERMINAL_HEIGHT := 1.8
const BREAKER_WIDTH := 0.7
const BREAKER_SPACING := 0.95
const BEACON_SPACING := 0.55
const HUB_FACE_Z := HUB_BACK_Z + 0.2        # text on the hub side of the dividing wall
const ROOM_FACE_Z := ROOM_BACK_Z + 0.2      # text on a room's back wall
const PLATE_OFFSET := 0.03                  # plates sit this far behind their text

const STRIP_ENERGY_OFF := 0.5     # ceiling strip while the system is down
const STRIP_ENERGY_ON := 1.1     # ... and once repaired
const FLOOR_ENERGY_OFF := 0.25    # tinted floor patch while the system is down
const FLOOR_ENERGY_ON := 0.9      # ... and once repaired
const ROOM_LIGHT_ENERGY_ON := 2.0    # room light once repaired (was 1.5 while down)
const HUB_LIGHT_ENERGY := 1.0     # main hub light (a little dimmer than before for mood)

const FONT_TITLE := 40
const FONT_MAIN := 38
const FONT_SMALL := 22


## Builds the station under `parent` for the given puzzles (from PuzzleGenerator).
## Returns:
## {
##   "spawn": Vector3,
##   "interactables": Array[Interactable],
##   "breakers": Array[Interactable],            # B1..B4 in index order
##   "consoles": {"oxygen": Interactable, "comms": Interactable},
##   "reboot": Interactable,
##   "room_lights": {room_id: OmniLight3D},
##   "door_labels": {room_id: Label3D},          # the room name on its header sign
##   "door_status": {room_id: StandardMaterial3D}, # frame and light: red, then cyan when repaired
##   "protocol_board": Label3D,                  # big "PROTOCOL A/B" sign in the hub
##   "room_floors": {room_id: StandardMaterial3D}, # tinted floor patch; brightens when repaired
##   "room_strips": {room_id: StandardMaterial3D}, # ceiling light strip: dim red, then bright cyan
##   "hub_light": OmniLight3D,                   # hub emergency light; main.gd flickers/pulses it
## }
static func build(parent: Node3D, puzzles: Dictionary) -> Dictionary:
	var wall_material := _solid_material(Rules.COLOR_INDIGO)
	var header_material := _solid_material(Rules.COLOR_INDIGO.darkened(0.35))
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

	# --- Doors: a header above each doorway carrying the room's sign, and a
	# frame and light that are red until the system is repaired.
	var room_lights := {}
	var door_labels := {}
	var door_status := {}
	var room_floors := {}
	var room_strips := {}
	var header_height := h - DOOR_HEIGHT
	_add_light(parent, Vector3(0.0, 2.6, 0.0), Color(0.8, 0.86, 1.0), HUB_LIGHT_ENERGY, 9.0)
	# A dim violet accent over the reboot terminal gives the hub a second light source.
	_add_light(parent, Vector3(0.0, 2.2, HUB_FRONT_Z - 1.2), Rules.COLOR_VIOLET, 0.9, 5.0)
	var hub_light := _add_light(parent, Vector3(0.0, 2.9, 1.5), Rules.COLOR_FAULT, 0.0, 7.0)
	for room_id in ROOM_CENTERS_X:
		var x: float = ROOM_CENTERS_X[room_id]
		room_lights[room_id] = _add_light(parent, Vector3(x, 2.6, room_center_z), Rules.COLOR_FAULT, 1.5, 6.5)

		_add_box(parent, "Header", Vector3(x, DOOR_HEIGHT + header_height * 0.5, HUB_BACK_Z),
			Vector3(DOOR_HALF_WIDTH * 2.0, header_height, t), header_material)

		var status := _glow_material(Rules.COLOR_FAULT, 1.4)
		door_status[room_id] = status
		var face_z := HUB_BACK_Z + t * 0.5 + 0.01          # just in front of the wall
		# Light strip under the sign, and a post on each side of the doorway.
		_add_glow_box(parent, Vector3(x, DOOR_HEIGHT + 0.06, face_z), Vector3(DOOR_HALF_WIDTH * 2.0 - 0.1, 0.05, 0.02), status)
		for side in [-1.0, 1.0]:
			_add_glow_box(parent, Vector3(x + side * (DOOR_HALF_WIDTH - 0.04), DOOR_HEIGHT * 0.5, face_z), Vector3(0.06, DOOR_HEIGHT, 0.02), status)
		# The sign: a dark plate on the header with the room name on it.
		_add_screen(parent, Vector3(x, DOOR_HEIGHT + header_height * 0.55, HUB_FACE_Z - PLATE_OFFSET), Vector2(1.7, 0.46))
		door_labels[room_id] = _add_label(parent, ROOM_LABELS[room_id], Vector3(x, DOOR_HEIGHT + header_height * 0.55, HUB_FACE_Z), FONT_TITLE, Rules.COLOR_FAULT)

		# Each room's floor is tinted so rooms are easy to tell apart.
		room_floors[room_id] = _add_flat(parent, "RoomFloor", Vector3(x, 0.011, room_center_z), Vector2(3.7, 5.7), ROOM_FLOOR_TINT[room_id])

		# A ceiling light strip: dim red while the system is down, bright cyan once repaired.
		var strip := _glow_material(Rules.COLOR_FAULT, STRIP_ENERGY_OFF)
		room_strips[room_id] = strip
		_add_glow_box(parent, Vector3(x, h - 0.04, room_center_z), Vector3(0.25, 0.05, room_depth - 1.0), strip)

	var interactables: Array[Interactable] = []

	# --- Hub boards flanking the middle doorway, in view from the spawn.
	var protocol: String = puzzles.get("protocol", "A")
	_add_screen(parent, Vector3(-2.0, 1.75, HUB_FACE_Z - PLATE_OFFSET), Vector2(1.8, 1.5))
	var protocol_board := _add_label(parent, "PROTOCOL %s" % protocol, Vector3(-2.0, 2.2, HUB_FACE_Z), FONT_TITLE, Rules.COLOR_GOLD)
	_add_label(parent, "The rules change\nwith the protocol.\nCheck it every shift.", Vector3(-2.0, 1.5, HUB_FACE_Z), FONT_SMALL, Color(1, 1, 1, 0.9))
	_add_screen(parent, Vector3(2.0, 1.75, HUB_FACE_Z - PLATE_OFFSET), Vector2(1.8, 1.5))
	_add_label(parent, "NEED HELP?", Vector3(2.0, 2.2, HUB_FACE_Z), FONT_TITLE, Rules.COLOR_CYAN)
	_add_label(parent, "Press H: ask ORACLE\nPress M: read the manuals", Vector3(2.0, 1.5, HUB_FACE_Z), FONT_SMALL, Color(1, 1, 1, 0.9))

	# --- Power room: a display above four breakers, each with its own rating.
	var power: Dictionary = puzzles["power"]
	var power_x: float = ROOM_CENTERS_X["power"]
	_add_screen(parent, Vector3(power_x, 2.5, ROOM_FACE_Z - PLATE_OFFSET), Vector2(3.6, 0.6))
	_add_label(parent, "LOAD MODE: %s" % power["mode"], Vector3(power_x, 2.5, ROOM_FACE_Z), FONT_MAIN, Rules.COLOR_CYAN)
	var breakers: Array[Interactable] = []
	for i in Rules.BREAKER_COUNT:
		var x := power_x + (float(i) - (Rules.BREAKER_COUNT - 1) * 0.5) * BREAKER_SPACING
		var breaker := _add_interactable(
			parent, "breaker_%d" % i, "FLIP BREAKER B%d" % (i + 1),
			Vector3(x, TERMINAL_HEIGHT * 0.5, ROOM_BACK_Z + 0.4), Vector3(BREAKER_WIDTH, TERMINAL_HEIGHT, 0.4), Rules.COLOR_VIOLET)
		breakers.append(breaker)
		interactables.append(breaker)
		# The name and rating are printed on the breaker itself (its front face).
		_add_label(parent, "B%d\n%d V" % [i + 1, power["ratings"][i]],
			Vector3(x, 1.4, ROOM_BACK_Z + 0.4 + 0.2 + 0.01), 30, Rules.COLOR_GOLD)

	# --- Oxygen room: a display above the valve console.
	var oxygen_x: float = ROOM_CENTERS_X["oxygen"]
	_add_screen(parent, Vector3(oxygen_x, 2.5, ROOM_FACE_Z - PLATE_OFFSET), Vector2(3.5, 0.6))
	_add_label(parent, "STATION MODE: %s" % puzzles["oxygen"]["mode"], Vector3(oxygen_x, 2.5, ROOM_FACE_Z), FONT_MAIN, Rules.COLOR_CYAN)
	var oxygen_console := _add_interactable(
		parent, "oxygen_console", "OPEN VALVE CONTROLS",
		Vector3(oxygen_x, TERMINAL_HEIGHT * 0.5, ROOM_BACK_Z + 0.5), Vector3(1.2, TERMINAL_HEIGHT, 0.6), Rules.COLOR_VIOLET)
	interactables.append(oxygen_console)
	_add_label(parent, "VALVE\nCONTROLS", Vector3(oxygen_x, 1.35, ROOM_BACK_Z + 0.5 + 0.3 + 0.01), 30, Rules.COLOR_GOLD)

	# --- Comms room: a display holding the beacons, above the tuner console.
	var comms_x: float = ROOM_CENTERS_X["comms"]
	_add_screen(parent, Vector3(comms_x, 2.45, ROOM_FACE_Z - PLATE_OFFSET), Vector2(3.6, 0.95))
	_add_label(parent, "BEACON ARRAY", Vector3(comms_x, 2.75, ROOM_FACE_Z), 30, Rules.COLOR_CYAN)
	_add_beacons(parent, comms_x, int(puzzles["comms"]["lit"]))
	var comms_console := _add_interactable(
		parent, "comms_console", "OPEN FREQUENCY TUNER",
		Vector3(comms_x, TERMINAL_HEIGHT * 0.5, ROOM_BACK_Z + 0.5), Vector3(1.2, TERMINAL_HEIGHT, 0.6), Rules.COLOR_VIOLET)
	interactables.append(comms_console)
	_add_label(parent, "FREQUENCY\nTUNER", Vector3(comms_x, 1.35, ROOM_BACK_Z + 0.5 + 0.3 + 0.01), 30, Rules.COLOR_GOLD)

	# --- Hub: the reboot terminal on the south wall.
	var reboot := _add_interactable(
		parent, "reboot_terminal", "REBOOT STATION",
		Vector3(0.0, TERMINAL_HEIGHT * 0.5, HUB_FRONT_Z - 0.6), Vector3(1.4, TERMINAL_HEIGHT, 0.5), Rules.COLOR_GOLD)
	interactables.append(reboot)
	var reboot_face_z := HUB_FRONT_Z - 0.6 - 0.25 - 0.01
	# Dark text, no outline: the terminal is light (gold, then cyan once ready).
	_add_label(parent, "REBOOT\nSTATION", Vector3(0.0, 1.2, reboot_face_z), 36, Color(0.06, 0.05, 0.12), 180.0, 0)

	return {
		"spawn": SPAWN_POSITION,
		"interactables": interactables,
		"breakers": breakers,
		"consoles": {"oxygen": oxygen_console, "comms": comms_console},
		"reboot": reboot,
		"room_lights": room_lights,
		"door_labels": door_labels,
		"door_status": door_status,
		"protocol_board": protocol_board,
		"room_floors": room_floors,
		"room_strips": room_strips,
		"hub_light": hub_light,
	}


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
		sphere.radius = 0.16
		sphere.height = 0.32
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


static func _glow_material(color: Color, energy: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = energy
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


## A box that is only drawn (no collision).
static func _add_glow_box(parent: Node3D, center: Vector3, size: Vector3, material: Material) -> void:
	var box := BoxMesh.new()
	box.size = size
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = box
	mesh_instance.material_override = material
	mesh_instance.position = center
	mesh_instance.name = "Glow"
	parent.add_child(mesh_instance)


## A thin coloured patch lying on the floor (no collision).
static func _add_flat(parent: Node3D, node_name: String, center: Vector3, size_xz: Vector2, color: Color) -> StandardMaterial3D:
	var material := _glow_material(color, FLOOR_ENERGY_OFF)
	_add_glow_box(parent, center, Vector3(size_xz.x, 0.02, size_xz.y), material)
	(parent.get_child(parent.get_child_count() - 1) as Node).name = node_name
	return material


## A dark plate with a faint glow, drawn behind wall text so it reads clearly.
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


static func _add_light(parent: Node3D, position: Vector3, color: Color, energy: float, light_range: float) -> OmniLight3D:
	var light := OmniLight3D.new()
	light.position = position
	light.light_color = color
	light.light_energy = energy
	light.omni_range = light_range
	parent.add_child(light)
	return light


static func _add_label(parent: Node3D, text: String, position: Vector3, font_size: int, color: Color, yaw_degrees: float = 0.0, outline: int = 8) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.position = position
	label.rotation.y = deg_to_rad(yaw_degrees)
	label.font_size = font_size
	label.pixel_size = 0.006
	label.modulate = color
	label.outline_size = outline
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
