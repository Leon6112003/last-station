class_name StationBuilder
extends RefCounted
## Builds the station layout and this attempt's puzzle props from boxes.
## No scene files needed. Called again for every attempt, so retries show the
## re-rolled puzzle values.
##
## Plan view (metres, -Z is north, +X is east). The player wakes in the crew quarters,
## walks out into one long corridor, and has to walk to each room along it.
##
##         CREW         POWER        OXYGEN        COMMS
##       +-------+     +-------+     +-------+     +-------+   z=-7.5
##       | bunk  |     |       |     |       |     |       |
##   +---+--[ ]--+-----+--[ ]--+-----+--[D]--+-----+--[D]--+---+   z=-1.5  (doors)
##   |R>  ----------------  gas  ----------------  sparks ----|   corridor, 3 m wide
##   +-----------------------------------------------------------+   z=+1.5
##  x=-5   0              12             24             36    41
##
##   R = reboot terminal at the west end. [D] = door that stays locked until the
##   system before it is repaired (Oxygen needs Power, Comms needs Oxygen).
##
## Design rules: every sign sits ON a surface (a header, a plate, a breaker or a
## console), never floating; text of one kind uses one size.

const X_WEST := -5.0         # west end of the corridor (centre of the end wall)
const X_EAST := 41.0         # east end of the corridor
const HUB_FRONT_Z := 1.5     # south wall of the corridor
const HUB_BACK_Z := -1.5     # wall between the corridor and the rooms
const ROOM_BACK_Z := -7.5    # north wall of the rooms
const ROOM_HALF_WIDTH := 3.0
const DOOR_HALF_WIDTH := 1.0
const DOOR_HEIGHT := 2.3     # the header above a doorway starts here
const BEDROOM_X := 0.0
const ROOM_CENTERS_X := {"power": 12.0, "oxygen": 24.0, "comms": 36.0}
const ROOM_LABELS := {"power": "POWER", "oxygen": "OXYGEN", "comms": "COMMS"}
## Which system must be repaired before a room's door opens ("" = open from the start).
const DOOR_REQUIRES := {"power": "", "oxygen": "power", "comms": "oxygen"}
const DOOR_LOCK_TEXT := {"oxygen": "LOCKED\nREPAIR POWER\nFIRST", "comms": "LOCKED\nREPAIR OXYGEN\nFIRST"}
const ROOM_FLOOR_TINT := {
	"power": Color(0.20, 0.12, 0.36),
	"oxygen": Color(0.07, 0.24, 0.28),
	"comms": Color(0.30, 0.24, 0.10),
}
const SPAWN_POSITION := Vector3(0.0, 0.9, -5.0)
const SPAWN_YAW_DEGREES := 180.0    # the player wakes facing south, toward the bedroom door
# Terminals must be taller than the eye line (1.55 m) so the interaction ray,
# which starts at the eyes, hits them without the player having to look down.
const TERMINAL_HEIGHT := 1.8
const BREAKER_WIDTH := 0.7
const BREAKER_SPACING := 0.95
const BEACON_SPACING := 0.55
const HUB_FACE_Z := HUB_BACK_Z + 0.2        # text on the corridor side of the rooms' wall
const BEDROOM_FACE_Z := HUB_BACK_Z - 0.2    # text on the bedroom side of that wall
const ROOM_FACE_Z := ROOM_BACK_Z + 0.2      # text on a room's back wall
const PLATE_OFFSET := 0.03                  # plates sit this far behind their text
const GAS_X := 18.0                         # gas vent between Power and Oxygen
const SPARK_X := 30.0                       # spark gap between Oxygen and Comms
const GAS_LENGTH := 6.0
const SPARK_LENGTH := 1.6
const GAS_PHASE_OFFSET := 4.5               # seconds into its cycle when a shift starts
const SPARK_PHASE_OFFSET := 1.0

const STRIP_ENERGY_OFF := 0.5     # ceiling strip while the system is down
const STRIP_ENERGY_ON := 1.1     # ... and once repaired
const FLOOR_ENERGY_OFF := 0.25    # tinted floor patch while the system is down
const FLOOR_ENERGY_ON := 0.9      # ... and once repaired
const ROOM_LIGHT_ENERGY_ON := 2.0    # room light once repaired (was 1.5 while down)
const HUB_LIGHT_ENERGY := 1.0     # corridor lights

const FONT_TITLE := 40
const FONT_MAIN := 38
const FONT_SMALL := 22


## Builds the station under `parent` for the given puzzles (from PuzzleGenerator).
## Returns:
## {
##   "spawn": Vector3, "spawn_yaw": float,        # where and which way the player wakes up
##   "interactables": Array[Interactable],
##   "breakers": Array[Interactable],            # B1..B4 in index order
##   "consoles": {"oxygen": Interactable, "comms": Interactable},
##   "reboot": Interactable,
##   "room_lights": {room_id: OmniLight3D},
##   "door_labels": {room_id: Label3D},          # the room name on its header sign
##   "door_status": {room_id: StandardMaterial3D}, # frame and light: red, then cyan when repaired
##   "doors": {room_id: DoorGate},               # sliding doors (oxygen, comms) locked in order
##   "hazards": Array[HazardZone],               # gas vent and spark gap in the corridor
##   "protocol_board": Label3D,                  # big "PROTOCOL A/B" sign in the bedroom
##   "room_floors": {room_id: StandardMaterial3D}, # tinted floor patch; brightens when repaired
##   "room_strips": {room_id: StandardMaterial3D}, # ceiling light strip: dim red, then bright cyan
##   "hub_light": OmniLight3D,                   # corridor emergency light; main.gd flickers/pulses it
##   "alarm_light": OmniLight3D,                 # red alarm light in the bedroom
## }
static func build(parent: Node3D, puzzles: Dictionary, theme: Dictionary = {}) -> Dictionary:
	if theme.is_empty():
		theme = ShiftTheme.for_shift(1)
	var wall_color: Color = theme["wall"]
	var wall_material := _solid_material(wall_color)
	var header_material := _solid_material(wall_color.darkened(0.35))
	var floor_material := _solid_material(theme["floor"])
	var ceiling_material := _solid_material(theme["ceiling"])

	var h := Rules.WALL_HEIGHT
	var t := Rules.WALL_THICKNESS
	var corridor_length := X_EAST - X_WEST
	var corridor_center_x := (X_EAST + X_WEST) * 0.5
	var corridor_depth := HUB_FRONT_Z - HUB_BACK_Z                  # 3 m
	var room_depth := HUB_BACK_Z - ROOM_BACK_Z                      # 6 m
	var room_center_z := (HUB_BACK_Z + ROOM_BACK_Z) * 0.5           # -4.5 m
	var room_xs: Array = [BEDROOM_X] + ROOM_CENTERS_X.values()

	# --- Shell: the corridor, then each room, built from boxes.
	_add_box(parent, "CorridorFloor", Vector3(corridor_center_x, -0.1, 0.0), Vector3(corridor_length + t, 0.2, corridor_depth + t), floor_material)
	_add_box(parent, "CorridorCeiling", Vector3(corridor_center_x, h + 0.1, 0.0), Vector3(corridor_length + t, 0.2, corridor_depth + t), ceiling_material)
	_add_box(parent, "WallWestEnd", Vector3(X_WEST, h * 0.5, 0.0), Vector3(t, h, corridor_depth + t), wall_material)
	_add_box(parent, "WallEastEnd", Vector3(X_EAST, h * 0.5, 0.0), Vector3(t, h, corridor_depth + t), wall_material)
	_add_box(parent, "WallSouth", Vector3(corridor_center_x, h * 0.5, HUB_FRONT_Z), Vector3(corridor_length + t, h, t), wall_material)
	for room_x in room_xs:
		_add_box(parent, "RoomFloor", Vector3(room_x, -0.1, room_center_z), Vector3(ROOM_HALF_WIDTH * 2.0 + t, 0.2, room_depth + t), floor_material)
		_add_box(parent, "RoomCeiling", Vector3(room_x, h + 0.1, room_center_z), Vector3(ROOM_HALF_WIDTH * 2.0 + t, 0.2, room_depth + t), ceiling_material)
		_add_box(parent, "RoomWallWest", Vector3(room_x - ROOM_HALF_WIDTH, h * 0.5, room_center_z), Vector3(t, h, room_depth + t), wall_material)
		_add_box(parent, "RoomWallEast", Vector3(room_x + ROOM_HALF_WIDTH, h * 0.5, room_center_z), Vector3(t, h, room_depth + t), wall_material)
		_add_box(parent, "RoomWallNorth", Vector3(room_x, h * 0.5, ROOM_BACK_Z), Vector3(ROOM_HALF_WIDTH * 2.0 + t, h, t), wall_material)

	# The wall between the corridor and the rooms, with a doorway for every room.
	var cursor := X_WEST
	for door_x in room_xs:
		_add_wall_segment(parent, cursor, door_x - DOOR_HALF_WIDTH, wall_material)
		cursor = door_x + DOOR_HALF_WIDTH
	_add_wall_segment(parent, cursor, X_EAST, wall_material)

	# --- Doors: a header above each doorway carrying the room's sign, and a frame and
	# light that are red until the system is repaired.
	var room_lights := {}
	var door_labels := {}
	var door_status := {}
	var door_gates := {}
	var room_floors := {}
	var room_strips := {}
	var header_height := h - DOOR_HEIGHT
	var hub_light := _add_light(parent, Vector3(BEDROOM_X, 2.9, 0.0), Rules.COLOR_FAULT, 0.0, 7.0)
	# Dim corridor lights, one between every pair of doors, so the walk is never pitch black.
	for corridor_light_x in [-2.5, 6.0, 18.0, 30.0, 38.5]:
		_add_light(parent, Vector3(corridor_light_x, 2.6, 0.0), theme["hub_light"], HUB_LIGHT_ENERGY, 8.0)

	for room_id in ROOM_CENTERS_X:
		var x: float = ROOM_CENTERS_X[room_id]
		room_lights[room_id] = _add_light(parent, Vector3(x, 2.6, room_center_z), Rules.COLOR_FAULT, 1.5, 6.5)

		_add_box(parent, "Header", Vector3(x, DOOR_HEIGHT + header_height * 0.5, HUB_BACK_Z),
			Vector3(DOOR_HALF_WIDTH * 2.0, header_height, t), header_material)

		var status := _glow_material(Rules.COLOR_FAULT, 1.4)
		door_status[room_id] = status
		var face_z := HUB_BACK_Z + t * 0.5 + 0.01          # just in front of the wall
		_add_glow_box(parent, Vector3(x, DOOR_HEIGHT + 0.06, face_z), Vector3(DOOR_HALF_WIDTH * 2.0 - 0.1, 0.05, 0.02), status)
		for side in [-1.0, 1.0]:
			_add_glow_box(parent, Vector3(x + side * (DOOR_HALF_WIDTH - 0.04), DOOR_HEIGHT * 0.5, face_z), Vector3(0.06, DOOR_HEIGHT, 0.02), status)
		_add_screen(parent, Vector3(x, DOOR_HEIGHT + header_height * 0.55, HUB_FACE_Z - PLATE_OFFSET), Vector2(1.7, 0.46))
		door_labels[room_id] = _add_label(parent, ROOM_LABELS[room_id], Vector3(x, DOOR_HEIGHT + header_height * 0.55, HUB_FACE_Z), FONT_TITLE, Rules.COLOR_FAULT)

		# A sliding door that stays locked until the system before this room is repaired.
		if DOOR_REQUIRES[room_id] != "":
			var gate := DoorGate.create(Vector3(DOOR_HALF_WIDTH * 2.0, DOOR_HEIGHT, 0.2), DOOR_REQUIRES[room_id],
				Vector3(x, DOOR_HEIGHT * 0.5, HUB_BACK_Z), DOOR_LOCK_TEXT[room_id])
			parent.add_child(gate)
			door_gates[room_id] = gate

		# Each room's floor is tinted so rooms are easy to tell apart.
		room_floors[room_id] = _add_flat(parent, "RoomFloor", Vector3(x, 0.011, room_center_z), Vector2(ROOM_HALF_WIDTH * 2.0 - 0.3, room_depth - 0.3), ROOM_FLOOR_TINT[room_id])

		# A ceiling light strip: dim red while the system is down, bright cyan once repaired.
		var strip := _glow_material(Rules.COLOR_FAULT, STRIP_ENERGY_OFF)
		room_strips[room_id] = strip
		_add_glow_box(parent, Vector3(x, h - 0.04, room_center_z), Vector3(0.25, 0.05, room_depth - 1.0), strip)

	var interactables: Array[Interactable] = []

	# --- Crew quarters (the start): a header sign, bunk, lockers, an alarm light, and the
	# two boards flanking the door in view from the bed.
	_add_box(parent, "Header", Vector3(BEDROOM_X, DOOR_HEIGHT + header_height * 0.5, HUB_BACK_Z),
		Vector3(DOOR_HALF_WIDTH * 2.0, header_height, t), header_material)
	_add_screen(parent, Vector3(BEDROOM_X, DOOR_HEIGHT + header_height * 0.55, HUB_FACE_Z - PLATE_OFFSET), Vector2(1.7, 0.46))
	_add_label(parent, "CREW QUARTERS", Vector3(BEDROOM_X, DOOR_HEIGHT + header_height * 0.55, HUB_FACE_Z), 28, Rules.COLOR_GOLD)
	var alarm_light := _add_light(parent, Vector3(BEDROOM_X, 2.7, room_center_z), Rules.COLOR_FAULT, 1.2, 7.0)
	_add_light(parent, Vector3(BEDROOM_X, 2.4, room_center_z + 1.0), Color(0.8, 0.86, 1.0), 0.5, 6.0)
	_add_flat(parent, "RoomFloor", Vector3(BEDROOM_X, 0.011, room_center_z), Vector2(ROOM_HALF_WIDTH * 2.0 - 0.3, room_depth - 0.3), Color(0.12, 0.14, 0.30))
	_add_bedroom_furniture(parent)

	var protocol: String = puzzles.get("protocol", "A")
	_add_screen(parent, Vector3(BEDROOM_X - 2.0, 1.75, BEDROOM_FACE_Z + PLATE_OFFSET), Vector2(1.6, 1.5))
	var protocol_board := _add_label(parent, "PROTOCOL %s" % protocol, Vector3(BEDROOM_X - 2.0, 2.2, BEDROOM_FACE_Z), 34, Rules.COLOR_GOLD, 180.0)
	_add_label(parent, "The rules change\nwith the protocol.\nCheck it every shift.", Vector3(BEDROOM_X - 2.0, 1.5, BEDROOM_FACE_Z), 20, Color(1, 1, 1, 0.9), 180.0)
	_add_screen(parent, Vector3(BEDROOM_X + 2.0, 1.75, BEDROOM_FACE_Z + PLATE_OFFSET), Vector2(1.6, 1.5))
	_add_label(parent, "NEED HELP?", Vector3(BEDROOM_X + 2.0, 2.2, BEDROOM_FACE_Z), 34, Rules.COLOR_CYAN, 180.0)
	_add_label(parent, "Press H: ask ORACLE\nPress M: read the manuals", Vector3(BEDROOM_X + 2.0, 1.5, BEDROOM_FACE_Z), 20, Color(1, 1, 1, 0.9), 180.0)

	# Direction signs on the corridor's south wall, read by someone who has just walked out
	# of the bedroom door and is facing south: east is on their left, west on their right.
	var south_face_z := HUB_FRONT_Z - 0.2
	_add_screen(parent, Vector3(BEDROOM_X + 3.3, 1.9, south_face_z + PLATE_OFFSET), Vector2(2.5, 0.6))
	_add_label(parent, "<< POWER  OXYGEN  COMMS", Vector3(BEDROOM_X + 3.3, 1.9, south_face_z), 22, Rules.COLOR_CYAN, 180.0)
	_add_screen(parent, Vector3(BEDROOM_X - 2.6, 1.9, south_face_z + PLATE_OFFSET), Vector2(2.0, 0.6))
	_add_label(parent, "REBOOT >>", Vector3(BEDROOM_X - 2.6, 1.9, south_face_z), 24, Rules.COLOR_GOLD, 180.0)

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

	# --- The reboot terminal at the west end of the corridor, facing east. The player has
	# to walk all the way back to it once everything is repaired.
	var reboot_x := X_WEST + 0.6
	var reboot := _add_interactable(
		parent, "reboot_terminal", "REBOOT STATION",
		Vector3(reboot_x, TERMINAL_HEIGHT * 0.5, 0.0), Vector3(0.5, TERMINAL_HEIGHT, 1.4), Rules.COLOR_GOLD)
	interactables.append(reboot)
	# Dark text, no outline: the terminal is light (gold, then cyan once ready). Its face
	# looks east (+X), so the label is turned 90 degrees.
	_add_label(parent, "REBOOT\nSTATION", Vector3(reboot_x + 0.25 + 0.01, 1.2, 0.0), 36, Color(0.06, 0.05, 0.12), 90.0, 0)

	# --- Corridor hazards: a gas vent between Power and Oxygen, sparks between Oxygen and Comms.
	var hazards: Array[HazardZone] = []
	var gas := HazardZone.create(HazardZone.KIND_GAS, Vector3(GAS_LENGTH, 2.8, 3.0), Vector3(GAS_X, 1.4, 0.0), GAS_PHASE_OFFSET)
	parent.add_child(gas)
	hazards.append(gas)
	var sparks := HazardZone.create(HazardZone.KIND_SPARK, Vector3(SPARK_LENGTH, 2.8, 3.0), Vector3(SPARK_X, 1.4, 0.0), SPARK_PHASE_OFFSET)
	parent.add_child(sparks)
	hazards.append(sparks)
	# Warning signs on the wall beside each hazard (readable from the corridor).
	_add_screen(parent, Vector3(GAS_X, 1.9, HUB_FACE_Z - PLATE_OFFSET - 0.1), Vector2(2.2, 0.55))
	_add_label(parent, "GAS VENT\nWAIT FOR GREEN", Vector3(GAS_X, 1.9, HUB_FACE_Z - 0.1), 20, Color(0.5, 1.0, 0.6))
	_add_screen(parent, Vector3(SPARK_X, 1.9, HUB_FACE_Z - PLATE_OFFSET - 0.1), Vector2(2.2, 0.55))
	_add_label(parent, "LIVE WIRES\nWAIT FOR GREY", Vector3(SPARK_X, 1.9, HUB_FACE_Z - 0.1), 20, Color(0.7, 0.9, 1.0))

	return {
		"spawn": SPAWN_POSITION,
		"spawn_yaw": SPAWN_YAW_DEGREES,
		"interactables": interactables,
		"breakers": breakers,
		"consoles": {"oxygen": oxygen_console, "comms": comms_console},
		"reboot": reboot,
		"room_lights": room_lights,
		"door_labels": door_labels,
		"door_status": door_status,
		"doors": door_gates,
		"hazards": hazards,
		"protocol_board": protocol_board,
		"room_floors": room_floors,
		"room_strips": room_strips,
		"hub_light": hub_light,
		"alarm_light": alarm_light,
	}


## A bunk bed, lockers and a small table in the crew quarters.
static func _add_bedroom_furniture(parent: Node3D) -> void:
	var frame := _solid_material(Color(0.28, 0.3, 0.38))
	var mattress := _solid_material(Color(0.55, 0.7, 0.85))
	var pillow := _solid_material(Color(0.92, 0.93, 0.96))
	var locker := _solid_material(Color(0.2, 0.24, 0.34))
	var bunk_x := BEDROOM_X - 2.1
	var bunk_z := (HUB_BACK_Z + ROOM_BACK_Z) * 0.5
	_add_box(parent, "BunkFrame", Vector3(bunk_x, 0.9, bunk_z), Vector3(1.0, 1.8, 2.1), frame)
	for level_y in [0.62, 1.42]:
		_add_glow_box(parent, Vector3(bunk_x + 0.02, level_y, bunk_z), Vector3(0.9, 0.14, 2.0), mattress)
		_add_glow_box(parent, Vector3(bunk_x, level_y + 0.12, bunk_z - 0.8), Vector3(0.6, 0.1, 0.35), pillow)
	for i in 3:
		_add_box(parent, "Locker", Vector3(BEDROOM_X + 2.6, 0.95, bunk_z - 1.3 + float(i) * 1.0), Vector3(0.5, 1.9, 0.8), locker)
	_add_box(parent, "Table", Vector3(BEDROOM_X + 0.9, 0.4, ROOM_BACK_Z + 0.6), Vector3(1.0, 0.8, 0.6), frame)


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
