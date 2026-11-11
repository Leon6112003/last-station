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

const X_WEST := -17.0        # west end of the corridor (centre of the end wall), beside the reboot terminal
const X_EAST := 53.0         # east end of the corridor
const HUB_FRONT_Z := 1.5     # south wall of the corridor
const HUB_BACK_Z := -1.5     # wall between the corridor and the rooms
const ROOM_BACK_Z := -7.5    # north wall of the rooms
const ROOM_HALF_WIDTH := 3.0
const DOOR_HALF_WIDTH := 1.0
const DOOR_HEIGHT := 2.3     # the header above a doorway starts here
const BEDROOM_X := 0.0
const ROOM_CENTERS_X := {"power": 12.0, "oxygen": 24.0, "comms": 36.0, "cooling": 48.0}
const ROOM_LABELS := {"power": "POWER", "oxygen": "OXYGEN", "comms": "COMMS", "cooling": "COOLING"}
## Which system must be repaired before a room's door opens ("" = open from the start).
const DOOR_REQUIRES := {"power": "", "oxygen": "power", "comms": "oxygen", "cooling": "comms"}
const DOOR_LOCK_TEXT := {"oxygen": "LOCKED\nREPAIR POWER\nFIRST", "comms": "LOCKED\nREPAIR OXYGEN\nFIRST", "cooling": "LOCKED\nREPAIR COMMS\nFIRST"}
const ROOM_FLOOR_TINT := {
	"power": Color(0.20, 0.12, 0.36),
	"oxygen": Color(0.07, 0.24, 0.28),
	"comms": Color(0.30, 0.24, 0.10),
	"cooling": Color(0.16, 0.20, 0.42),
}
const CRYO_X := -10.0        # the optional Cryo Bay, on the way to the reboot terminal (never locked)
const BUNK_X := BEDROOM_X - 1.6
const BUNK_Z := (HUB_BACK_Z + ROOM_BACK_Z) * 0.5
const SPAWN_POSITION := Vector3(BEDROOM_X - 0.6, 0.9, BUNK_Z)   # beside the bunk, in line with the door
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
const GAS_XS := [6.0, 18.0]                 # gas vents: Bedroom-Power and Power-Oxygen
const GAS_PHASE_OFFSETS := [8.0, 4.5]       # seconds into each cycle when a shift starts
const GAS_LENGTH := 6.0
const LASER_X := 30.0                       # the first laser grid, between Oxygen and Comms
const LASER_XS := [30.0, 42.0]              # ...and the second, between Comms and Cooling (from shift 3)
const LASER_SWITCH_DISTANCE := 3.5          # the two off-switches stand this far either side

const WINDOW_XS := [12.0, 24.0, 36.0, 48.0]        # viewports onto space in the corridor's south wall
const WINDOW_HALF_WIDTH := 1.6
const WINDOW_SILL := 0.9
const WINDOW_TOP := 2.4
const STAR_COUNT := 500
const RIB_SPACING := 6.0                     # structural ribs along the corridor

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
##   "bed_position": Vector3,                    # the eyes of someone lying in the lower bunk
##   "interactables": Array[Interactable],
##   "breakers": Array[Interactable],            # B1..B4 in index order
##   "consoles": {"oxygen": Interactable, "comms": Interactable, "cooling": Interactable},
##   "pods": Array[StandardMaterial3D],         # the glow of each cryo pod (red while the station is broken)
##   "reactor": StandardMaterial3D,              # the cooling room's reactor core (orange until repaired)
##   "reboot": Interactable,
##   "room_lights": {room_id: OmniLight3D},
##   "door_labels": {room_id: Label3D},          # the room name on its header sign
##   "door_status": {room_id: StandardMaterial3D}, # frame and light: red, then cyan when repaired
##   "doors": {room_id: DoorGate},               # sliding doors (oxygen, comms) locked in order
##   "hazards": Array[HazardZone],               # the two gas vents in the corridor
##   "laser": LaserGrid,                         # the first laser barrier, between Oxygen and Comms
##   "lasers": Array[LaserGrid],                 # every laser barrier (a second one from shift 3)
##   "laser_switches": Array[Interactable],      # the two wall switches that turn it off
##   "protocol_board": Label3D,                  # big "PROTOCOL A/B" sign in the bedroom
##   "room_floors": {room_id: StandardMaterial3D}, # tinted floor patch; brightens when repaired
##   "room_strips": {room_id: StandardMaterial3D}, # ceiling light strip: dim red, then bright cyan
##   "hub_light": OmniLight3D,                   # corridor emergency light; main.gd flickers/pulses it
##   "alarm_light": OmniLight3D,                 # red alarm light in the bedroom
## }
static func build(parent: Node3D, puzzles: Dictionary, theme: Dictionary = {}, run_number: int = 1) -> Dictionary:
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
	var room_xs: Array = [BEDROOM_X] + ROOM_CENTERS_X.values() + [CRYO_X]
	room_xs.sort()   # the wall loops below walk the doorways from west to east

	# --- Shell: the corridor, then each room, built from boxes.
	_add_box(parent, "CorridorFloor", Vector3(corridor_center_x, -0.1, 0.0), Vector3(corridor_length + t, 0.2, corridor_depth + t), floor_material)
	_add_box(parent, "CorridorCeiling", Vector3(corridor_center_x, h + 0.1, 0.0), Vector3(corridor_length + t, 0.2, corridor_depth + t), ceiling_material)
	_add_box(parent, "WallWestEnd", Vector3(X_WEST, h * 0.5, 0.0), Vector3(t, h, corridor_depth + t), wall_material)
	_add_box(parent, "WallEastEnd", Vector3(X_EAST, h * 0.5, 0.0), Vector3(t, h, corridor_depth + t), wall_material)
	_add_south_wall(parent, wall_material, header_material)
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
	_add_station_details(parent, theme)

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
	for corridor_light_x in [-14.0, -6.0, 3.0, 6.0, 18.0, 30.0, 42.0, 51.0]:
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
	_add_screen(parent, Vector3(BEDROOM_X + 3.3, 1.9, south_face_z + PLATE_OFFSET), Vector2(3.2, 0.6))
	_add_label(parent, "<< POWER  OXYGEN  COMMS  COOLING", Vector3(BEDROOM_X + 3.3, 1.9, south_face_z), 18, Rules.COLOR_CYAN, 180.0)
	_add_screen(parent, Vector3(BEDROOM_X - 3.0, 1.9, south_face_z + PLATE_OFFSET), Vector2(3.0, 0.6))
	_add_label(parent, "CRYO BAY  ·  REBOOT >>", Vector3(BEDROOM_X - 3.0, 1.9, south_face_z), 20, Rules.COLOR_GOLD, 180.0)

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

	# --- Cooling room: a glowing reactor core, a display with the core temperature and the
	# reactor state, and the coolant console. The core is hot orange until cooling is repaired.
	var cooling: Dictionary = puzzles["cooling"]
	var cooling_x: float = ROOM_CENTERS_X["cooling"]
	_add_screen(parent, Vector3(cooling_x, 2.5, ROOM_FACE_Z - PLATE_OFFSET), Vector2(3.6, 0.9))
	_add_label(parent, "CORE TEMP: %d K" % int(cooling["temp"]), Vector3(cooling_x, 2.72, ROOM_FACE_Z), FONT_MAIN, Rules.COLOR_CYAN)
	_add_label(parent, "REACTOR: %s" % cooling["state"], Vector3(cooling_x, 2.28, ROOM_FACE_Z), FONT_MAIN, Rules.COLOR_GOLD)
	var reactor_material := _glow_material(Color(1.0, 0.45, 0.15), 1.6)
	var core := CylinderMesh.new()
	core.top_radius = 0.45
	core.bottom_radius = 0.45
	core.height = 2.6
	var core_instance := MeshInstance3D.new()
	core_instance.name = "ReactorCore"
	core_instance.mesh = core
	core_instance.material_override = reactor_material
	core_instance.position = Vector3(cooling_x - 2.0, 1.45, room_center_z)
	parent.add_child(core_instance)
	_add_box(parent, "ReactorBase", Vector3(cooling_x - 2.0, 0.15, room_center_z), Vector3(1.2, 0.3, 1.2), _solid_material(Color(0.2, 0.22, 0.3)))
	var cooling_console := _add_interactable(
		parent, "cooling_console", "OPEN COOLANT CONTROL",
		Vector3(cooling_x, TERMINAL_HEIGHT * 0.5, ROOM_BACK_Z + 0.5), Vector3(1.2, TERMINAL_HEIGHT, 0.6), Rules.COLOR_VIOLET)
	interactables.append(cooling_console)
	_add_label(parent, "COOLANT\nCONTROL", Vector3(cooling_x, 1.35, ROOM_BACK_Z + 0.5 + 0.3 + 0.01), 30, Rules.COLOR_GOLD)

	# --- The optional Cryo Bay at the west end, on the way to the reboot terminal: the sleeping crew
	# and four log terminals.
	var pods := _add_cryo_bay(parent, theme, interactables)

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

	# --- Corridor hazards: two gas vents, and a laser grid between Oxygen and Comms.
	var hazards: Array[HazardZone] = []
	for i in GAS_XS.size():
		var gas_x: float = GAS_XS[i]
		var gas := HazardZone.create(Vector3(Rules.gas_length(run_number), 2.8, 3.0), Vector3(gas_x, 1.4, 0.0), GAS_PHASE_OFFSETS[i], run_number)
		parent.add_child(gas)
		hazards.append(gas)
		# A warning sign on the wall beside the vent (readable from the corridor).
		_add_screen(parent, Vector3(gas_x, 1.9, HUB_FACE_Z - PLATE_OFFSET - 0.1), Vector2(2.2, 0.55))
		_add_label(parent, "GAS VENT\nWAIT FOR GREY LAMP", Vector3(gas_x, 1.9, HUB_FACE_Z - 0.1), 18, Color(0.5, 1.0, 0.6))

	# Laser grids (one, and a second from shift 3), each with two wall switches that turn it off for a while.
	var lasers: Array[LaserGrid] = []
	var laser_switches: Array[Interactable] = []
	for grid_index in Rules.laser_count(run_number):
		var grid_x: float = LASER_XS[grid_index]
		var laser := LaserGrid.create(Vector3(grid_x, 0.0, 0.0), HUB_FRONT_Z - HUB_BACK_Z, Rules.WALL_HEIGHT, run_number)
		parent.add_child(laser)
		lasers.append(laser)
		for side in [-1.0, 1.0]:
			var switch_x: float = grid_x + side * LASER_SWITCH_DISTANCE
			var switch_id := "laser_switch_%s%s" % ["" if grid_index == 0 else "%d_" % (grid_index + 1), "west" if side < 0.0 else "east"]
			var laser_switch := _add_interactable(
				parent, switch_id, "TURN LASER GRID OFF (%d s)" % int(laser.off_seconds),
				Vector3(switch_x, TERMINAL_HEIGHT * 0.5, HUB_FRONT_Z - 0.25), Vector3(0.9, TERMINAL_HEIGHT, 0.5), Rules.COLOR_VIOLET)
			laser_switch.set_meta("laser_grid", laser)
			laser_switches.append(laser_switch)
			interactables.append(laser_switch)
			_add_label(parent, "LASER\nGRID", Vector3(switch_x, 1.35, HUB_FRONT_Z - 0.25 - 0.25 - 0.01), 28, Rules.COLOR_GOLD, 180.0)

	return {
		"spawn": SPAWN_POSITION,
		"spawn_yaw": SPAWN_YAW_DEGREES,
		"bed_position": Vector3(BUNK_X, 0.8, BUNK_Z - 0.55),   # the eyes while lying in the lower bunk
		"interactables": interactables,
		"breakers": breakers,
		"consoles": {"oxygen": oxygen_console, "comms": comms_console, "cooling": cooling_console},
		"reactor": reactor_material,
		"pods": pods,
		"reboot": reboot,
		"room_lights": room_lights,
		"door_labels": door_labels,
		"door_status": door_status,
		"doors": door_gates,
		"hazards": hazards,
		"laser": lasers[0],
		"lasers": lasers,
		"laser_switches": laser_switches,
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
	var blanket := _solid_material(Color(0.36, 0.28, 0.62))
	var rail := _solid_material(Color(0.16, 0.18, 0.26))
	var bunk_x := BUNK_X
	var bunk_z := BUNK_Z
	# An open bunk bed (the lower bunk is the player's): four posts, a solid base for the
	# lower bed so nobody walks through it, a platform for the upper bunk, mattresses,
	# a pillow and blanket on each, a headboard at the north end and a ladder at the foot.
	for corner_x in [-0.5, 0.5]:
		for corner_z in [-1.05, 1.05]:
			_add_box(parent, "BunkPost", Vector3(bunk_x + corner_x, 0.95, bunk_z + corner_z), Vector3(0.1, 1.9, 0.1), frame)
	_add_box(parent, "BedBase", Vector3(bunk_x, 0.25, bunk_z), Vector3(1.0, 0.5, 2.1), frame)
	_add_box(parent, "UpperBunk", Vector3(bunk_x, 1.3, bunk_z), Vector3(1.0, 0.1, 2.1), frame)
	_add_box(parent, "Headboard", Vector3(bunk_x, 0.85, bunk_z - 1.07), Vector3(1.0, 1.7, 0.06), rail)
	for level_y in [0.57, 1.42]:
		_add_glow_box(parent, Vector3(bunk_x, level_y, bunk_z), Vector3(0.9, 0.14, 2.0), mattress)
		_add_glow_box(parent, Vector3(bunk_x, level_y + 0.1, bunk_z - 0.8), Vector3(0.6, 0.1, 0.35), pillow)
		_add_glow_box(parent, Vector3(bunk_x, level_y + 0.09, bunk_z + 0.35), Vector3(0.92, 0.06, 1.15), blanket)
	# A cyan trim along the head of the bed, so the bunk reads clearly in the dark.
	_add_glow_box(parent, Vector3(bunk_x, 1.78, bunk_z - 1.04), Vector3(0.9, 0.05, 0.04), _glow_material(Rules.COLOR_CYAN, 1.2))
	for side in [-0.38, 0.38]:
		_add_glow_box(parent, Vector3(bunk_x + side, 0.9, bunk_z + 1.14), Vector3(0.05, 1.8, 0.05), rail)
	for rung_y in [0.3, 0.65, 1.0, 1.35]:
		_add_glow_box(parent, Vector3(bunk_x, rung_y, bunk_z + 1.14), Vector3(0.76, 0.04, 0.04), rail)
	for i in 3:
		_add_box(parent, "Locker", Vector3(BEDROOM_X + 2.6, 0.95, bunk_z - 1.3 + float(i) * 1.0), Vector3(0.5, 1.9, 0.8), locker)
	_add_box(parent, "Table", Vector3(BEDROOM_X + 0.9, 0.4, ROOM_BACK_Z + 0.6), Vector3(1.0, 0.8, 0.6), frame)


## The corridor's south wall: solid, except for three big viewports looking out at space.
## Each viewport is a thin glass pane (solid, so nobody walks out) in a frame.
static func _add_south_wall(parent: Node3D, wall_material: Material, frame_material: Material) -> void:
	var h := Rules.WALL_HEIGHT
	var t := Rules.WALL_THICKNESS
	var cursor := X_WEST - t * 0.5
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.45, 0.75, 1.0, 0.1)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.roughness = 0.1
	var trim := _glow_material(Rules.COLOR_CYAN, 0.9)
	for window_x in WINDOW_XS:
		var x0: float = window_x - WINDOW_HALF_WIDTH
		var x1: float = window_x + WINDOW_HALF_WIDTH
		_add_box(parent, "WallSouth", Vector3((cursor + x0) * 0.5, h * 0.5, HUB_FRONT_Z), Vector3(x0 - cursor, h, t), wall_material)
		_add_box(parent, "WallSouth", Vector3(window_x, WINDOW_SILL * 0.5, HUB_FRONT_Z), Vector3(x1 - x0, WINDOW_SILL, t), wall_material)
		_add_box(parent, "WallSouth", Vector3(window_x, (WINDOW_TOP + h) * 0.5, HUB_FRONT_Z), Vector3(x1 - x0, h - WINDOW_TOP, t), wall_material)
		_add_box(parent, "WindowGlass", Vector3(window_x, (WINDOW_SILL + WINDOW_TOP) * 0.5, HUB_FRONT_Z), Vector3(x1 - x0, WINDOW_TOP - WINDOW_SILL, 0.06), glass)
		# A frame on the inside face, and a mullion down the middle.
		var face_z := HUB_FRONT_Z - t * 0.5 - 0.02
		var mid_y := (WINDOW_SILL + WINDOW_TOP) * 0.5
		_add_glow_box(parent, Vector3(window_x, WINDOW_SILL, face_z), Vector3(x1 - x0 + 0.2, 0.1, 0.06), frame_material)
		_add_glow_box(parent, Vector3(window_x, WINDOW_TOP, face_z), Vector3(x1 - x0 + 0.2, 0.1, 0.06), frame_material)
		for side in [-1.0, 1.0]:
			_add_glow_box(parent, Vector3(window_x + side * WINDOW_HALF_WIDTH, mid_y, face_z), Vector3(0.1, WINDOW_TOP - WINDOW_SILL + 0.1, 0.06), frame_material)
		_add_glow_box(parent, Vector3(window_x, mid_y, face_z), Vector3(0.06, WINDOW_TOP - WINDOW_SILL, 0.05), frame_material)
		_add_glow_box(parent, Vector3(window_x, WINDOW_SILL + 0.07, face_z - 0.02), Vector3(x1 - x0, 0.03, 0.03), trim)
		cursor = x1
	var east := X_EAST + t * 0.5
	_add_box(parent, "WallSouth", Vector3((cursor + east) * 0.5, h * 0.5, HUB_FRONT_Z), Vector3(east - cursor, h, t), wall_material)
	_add_space_outside(parent)


## What the windows look at: a field of stars and a big planet with a lit crescent and a
## thin atmosphere. All unshaded and fog-free, so it looks the same in every theme.
static func _add_space_outside(parent: Node3D) -> void:
	var star_material := StandardMaterial3D.new()
	star_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	star_material.vertex_color_use_as_albedo = true
	star_material.disable_fog = true
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.use_colors = true
	multi.mesh = BoxMesh.new()
	multi.instance_count = STAR_COUNT
	var rng := RandomNumberGenerator.new()
	rng.seed = 5150   # fixed, so every shift has the same sky
	for i in STAR_COUNT:
		var position := Vector3(rng.randf_range(-30.0, 80.0), rng.randf_range(-20.0, 45.0), rng.randf_range(25.0, 90.0))
		var size := rng.randf_range(0.12, 0.34) * position.z / 40.0
		multi.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3(size, size, size)), position))
		var tint := rng.randf()
		multi.set_instance_color(i, Color(1.0, 0.95, 0.85).lerp(Color(0.7, 0.85, 1.0), tint) * rng.randf_range(0.6, 1.0))
	var stars := MultiMeshInstance3D.new()
	stars.name = "Stars"
	stars.multimesh = multi
	stars.material_override = star_material
	parent.add_child(stars)

	var centre := Vector3(24.0, 14.0, 125.0)
	_add_space_sphere(parent, "Atmosphere", centre + Vector3(0.0, 0.0, 2.0), 44.0, Color(0.3, 0.8, 1.0, 0.35))
	_add_space_sphere(parent, "Planet", centre, 40.0, Color(0.2, 0.42, 0.85))
	# A second, darker sphere shifted towards the camera and away from the light leaves
	# only a bright crescent of the planet showing.
	_add_space_sphere(parent, "PlanetNight", centre + Vector3(13.0, -6.0, -5.0), 40.5, Color(0.015, 0.02, 0.07))


static func _add_space_sphere(parent: Node3D, node_name: String, center: Vector3, radius: float, color: Color) -> void:
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	sphere.radial_segments = 48
	sphere.rings = 24
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.disable_fog = true
	if color.a < 1.0:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = sphere
	instance.material_override = material
	instance.position = center
	parent.add_child(instance)


## Purely visual details that make the interior read as a space station: structural
## ribs, ceiling pipes and cable runs, hazard stripes and guide lights along the floor,
## panel seams in the walls and floor grating. None of it has collision.
static func _add_station_details(parent: Node3D, theme: Dictionary) -> void:
	var h := Rules.WALL_HEIGHT
	var t := Rules.WALL_THICKNESS
	var wall_color: Color = theme["wall"]
	var rib_material := _solid_material(wall_color.darkened(0.45))
	var pipe_material := _solid_material(Color(0.42, 0.46, 0.55))
	pipe_material.metallic = 0.6
	pipe_material.roughness = 0.45
	var cable_material := _solid_material(Color(0.07, 0.07, 0.1))
	var seam_material := _solid_material(wall_color.darkened(0.55))
	var north_face := HUB_BACK_Z + t * 0.5
	var south_face := HUB_FRONT_Z - t * 0.5
	var length := X_EAST - X_WEST
	var centre_x := (X_EAST + X_WEST) * 0.5

	# Structural ribs: a frame of two posts and a beam every few metres.
	var rib_x := X_WEST + RIB_SPACING * 0.5
	while rib_x < X_EAST:
		_add_glow_box(parent, Vector3(rib_x, h - 0.2, 0.0), Vector3(0.35, 0.4, HUB_FRONT_Z - HUB_BACK_Z), rib_material)
		for face in [north_face + 0.1, south_face - 0.1]:
			_add_glow_box(parent, Vector3(rib_x, h * 0.5, face), Vector3(0.35, h, 0.2), rib_material)
		rib_x += RIB_SPACING

	# Pipes and a cable bundle along the ceiling.
	for pipe_z in [-1.05, -0.8, 1.05]:
		var radius := 0.12 if pipe_z != -0.8 else 0.07
		_add_pipe(parent, Vector3(centre_x, h - 0.2, pipe_z), length, radius, pipe_material)
	_add_pipe(parent, Vector3(centre_x, h - 0.12, 0.8), length, 0.05, cable_material)
	_add_pipe(parent, Vector3(centre_x, h - 0.12, 0.65), length, 0.05, cable_material)

	# Guide lights along the foot of both walls, and a hazard-striped kerb beside them. On the
	# wall with the doors they stop at each doorway instead of running across the opening.
	var guide := _glow_material(Rules.COLOR_CYAN, 1.1)
	var door_xs: Array = [BEDROOM_X] + ROOM_CENTERS_X.values() + [CRYO_X]
	door_xs.sort()
	var runs: Array = []   # [from_x, to_x] stretches of that wall between the doorways
	var run_start := X_WEST
	for door_x in door_xs:
		runs.append([run_start, float(door_x) - DOOR_HALF_WIDTH - 0.1])
		run_start = float(door_x) + DOOR_HALF_WIDTH + 0.1
	runs.append([run_start, X_EAST])
	for run in runs:
		var run_length: float = float(run[1]) - float(run[0])
		var run_centre: float = (float(run[0]) + float(run[1])) * 0.5
		_add_glow_box(parent, Vector3(run_centre, 0.3, north_face + 0.02), Vector3(run_length, 0.04, 0.04), guide)
		_add_glow_box(parent, Vector3(run_centre, 0.012, HUB_BACK_Z + 0.4), Vector3(run_length, 0.02, 0.22), _hazard_material(run_length / 0.9))
	_add_glow_box(parent, Vector3(centre_x, 0.3, south_face - 0.02), Vector3(length, 0.04, 0.04), guide)
	_add_glow_box(parent, Vector3(centre_x, 0.012, HUB_FRONT_Z - 0.4), Vector3(length, 0.02, 0.22), _hazard_material(length / 0.9))

	# Panel seams down the corridor walls, like bolted plates.
	var seam_x := X_WEST + 3.0
	while seam_x < X_EAST:
		var near_door := false
		for door_x in [BEDROOM_X, 12.0, 24.0, 36.0, 48.0, CRYO_X]:
			near_door = near_door or absf(seam_x - door_x) < 1.4
		var near_window := false
		for window_x in WINDOW_XS:
			near_window = near_window or absf(seam_x - float(window_x)) < WINDOW_HALF_WIDTH + 0.2
		if not near_door:
			_add_glow_box(parent, Vector3(seam_x, h * 0.5, north_face + 0.01), Vector3(0.06, h, 0.02), seam_material)
		if not near_window:
			_add_glow_box(parent, Vector3(seam_x, h * 0.5, south_face - 0.01), Vector3(0.06, h, 0.02), seam_material)
		seam_x += 3.0

	# Rooms: ceiling beams and a pipe, so they match the corridor.
	var room_center_z := (HUB_BACK_Z + ROOM_BACK_Z) * 0.5
	var room_depth := HUB_BACK_Z - ROOM_BACK_Z
	var room_xs: Array = [BEDROOM_X] + ROOM_CENTERS_X.values() + [CRYO_X]
	for room_x in room_xs:
		for beam_z in [room_center_z - 0.5, room_center_z + 2.0]:   # none near the back wall, where the displays are
			_add_glow_box(parent, Vector3(room_x, h - 0.15, beam_z), Vector3(ROOM_HALF_WIDTH * 2.0, 0.3, 0.3), rib_material)
		_add_pipe(parent, Vector3(room_x + 2.4, h - 0.25, room_center_z), room_depth - 0.4, 0.1, pipe_material, true)
		_add_pipe(parent, Vector3(room_x - 2.4, h - 0.25, room_center_z), room_depth - 0.4, 0.07, cable_material, true)


## A cylinder lying along X (or along Z when `along_z`), centred on `center`.
static func _add_pipe(parent: Node3D, center: Vector3, length: float, radius: float, material: Material, along_z: bool = false) -> void:
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = radius
	cylinder.bottom_radius = radius
	cylinder.height = length
	cylinder.radial_segments = 10
	var instance := MeshInstance3D.new()
	instance.name = "Pipe"
	instance.mesh = cylinder
	instance.material_override = material
	instance.position = center
	instance.rotation.x = PI * 0.5 if along_z else 0.0
	instance.rotation.z = 0.0 if along_z else PI * 0.5
	parent.add_child(instance)


## Yellow-and-black warning stripes: a small generated texture repeated `repeats` times.
static func _hazard_material(repeats: float) -> StandardMaterial3D:
	var image := Image.create(16, 4, false, Image.FORMAT_RGB8)
	for x in 16:
		for y in 4:
			var yellow := ((x + y * 2) / 4) % 2 == 0
			image.set_pixel(x, y, Color(0.95, 0.72, 0.1) if yellow else Color(0.08, 0.08, 0.1))
	var material := StandardMaterial3D.new()
	material.albedo_texture = ImageTexture.create_from_image(image)
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	material.uv1_scale = Vector3(repeats, 1.0, 1.0)
	material.emission_enabled = true
	material.emission = Color(0.95, 0.72, 0.1)
	material.emission_energy_multiplier = 0.15
	return material


## The Cryo Bay, between the crew quarters and the reboot terminal: an open doorway (never locked), six pods with the sleeping crew, and four
## terminals that show the crew's logs. Optional: nothing in it affects the rules. The pods
## glow red while the station is broken and turn cyan as it is repaired (see main.gd).
## Returns the pods' glow materials.
static func _add_cryo_bay(parent: Node3D, theme: Dictionary, interactables: Array[Interactable]) -> Array[StandardMaterial3D]:
	var h := Rules.WALL_HEIGHT
	var t := Rules.WALL_THICKNESS
	var header_height := h - DOOR_HEIGHT
	var room_center_z := (HUB_BACK_Z + ROOM_BACK_Z) * 0.5
	var room_depth := HUB_BACK_Z - ROOM_BACK_Z
	var cx := CRYO_X
	# The doorway's header and sign, and a calm cyan frame (this door is never locked).
	_add_box(parent, "Header", Vector3(cx, DOOR_HEIGHT + header_height * 0.5, HUB_BACK_Z),
		Vector3(DOOR_HALF_WIDTH * 2.0, header_height, t), _solid_material((theme["wall"] as Color).darkened(0.35)))
	_add_screen(parent, Vector3(cx, DOOR_HEIGHT + header_height * 0.55, HUB_FACE_Z - PLATE_OFFSET), Vector2(1.7, 0.46))
	_add_label(parent, "CRYO BAY", Vector3(cx, DOOR_HEIGHT + header_height * 0.55, HUB_FACE_Z), 32, Rules.COLOR_CYAN)
	var frame := _glow_material(Rules.COLOR_CYAN, 1.1)
	var face_z := HUB_BACK_Z + t * 0.5 + 0.01
	_add_glow_box(parent, Vector3(cx, DOOR_HEIGHT + 0.06, face_z), Vector3(DOOR_HALF_WIDTH * 2.0 - 0.1, 0.05, 0.02), frame)
	for side in [-1.0, 1.0]:
		_add_glow_box(parent, Vector3(cx + side * (DOOR_HALF_WIDTH - 0.04), DOOR_HEIGHT * 0.5, face_z), Vector3(0.06, DOOR_HEIGHT, 0.02), frame)
	# Cold light, a pale floor patch and a ceiling strip.
	_add_light(parent, Vector3(cx, 2.6, room_center_z), Color(0.5, 0.75, 1.0), 1.3, 7.0)
	_add_flat(parent, "RoomFloor", Vector3(cx, 0.011, room_center_z), Vector2(ROOM_HALF_WIDTH * 2.0 - 0.3, room_depth - 0.3), Color(0.12, 0.2, 0.34))
	_add_glow_box(parent, Vector3(cx, h - 0.04, room_center_z), Vector3(0.25, 0.05, room_depth - 1.0), _glow_material(Color(0.5, 0.75, 1.0), 0.6))
	_add_label(parent, "THE CREW SLEEPS", Vector3(cx, 2.75, ROOM_FACE_Z), 36, Color(0.6, 0.85, 1.0))

	# Six pods, three along each side wall. Each has a solid base, a glass lid, a sleeper
	# in a coloured suit, and a name plate facing the middle of the room.
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.5, 0.8, 1.0, 0.16)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.roughness = 0.1
	var base_material := _solid_material(Color(0.22, 0.25, 0.34))
	var skin := _solid_material(Color(0.88, 0.7, 0.58))
	var pods: Array[StandardMaterial3D] = []
	for i in CrewLogs.CREW.size():
		var side := -1.0 if i < 3 else 1.0
		var pod_x := cx + side * 2.35
		var pod_z := ROOM_BACK_Z + 2.4 + float(i % 3) * 1.35
		_add_box(parent, "PodBase", Vector3(pod_x, 0.3, pod_z), Vector3(0.9, 0.6, 1.25), base_material)
		var glow := _glow_material(Rules.COLOR_FAULT, 1.0)
		pods.append(glow)
		_add_glow_box(parent, Vector3(pod_x - side * 0.38, 0.45, pod_z), Vector3(0.05, 0.08, 1.2), glow)   # a light strip on the inner side
		_add_glow_box(parent, Vector3(pod_x, 0.96, pod_z), Vector3(0.84, 0.5, 1.2), glass)
		# The sleeper: a capsule lying along the pod in a suit colour, with a head.
		var suit := _solid_material(CrewLogs.CREW[i]["suit"])
		var body := CapsuleMesh.new()
		body.radius = 0.15
		body.height = 0.95
		var body_instance := MeshInstance3D.new()
		body_instance.mesh = body
		body_instance.material_override = suit
		body_instance.position = Vector3(pod_x, 0.82, pod_z + 0.05)
		body_instance.rotation.x = PI * 0.5
		parent.add_child(body_instance)
		var head := SphereMesh.new()
		head.radius = 0.12
		head.height = 0.24
		var head_instance := MeshInstance3D.new()
		head_instance.mesh = head
		head_instance.material_override = skin
		head_instance.position = Vector3(pod_x, 0.84, pod_z - 0.5)
		parent.add_child(head_instance)
		_add_label(parent, "%s\n%s" % [CrewLogs.CREW[i]["pod"], CrewLogs.CREW[i]["name"]],
			Vector3(pod_x - side * 0.46, 1.4, pod_z), 16, Color(0.8, 0.92, 1.0), -90.0 * side)

	# Four log terminals along the back wall.
	for n in CrewLogs.count():
		var terminal_x := cx + (float(n) - 1.5) * 1.5
		var terminal := _add_interactable(
			parent, "crew_log_%d" % (n + 1), "READ CREW LOG %d" % (n + 1),
			Vector3(terminal_x, TERMINAL_HEIGHT * 0.5, ROOM_BACK_Z + 0.4), Vector3(0.9, TERMINAL_HEIGHT, 0.4), Rules.COLOR_CYAN)
		interactables.append(terminal)
		_add_label(parent, "CREW\nLOG %d" % (n + 1), Vector3(terminal_x, 1.35, ROOM_BACK_Z + 0.4 + 0.2 + 0.01), 28, Color(0.06, 0.05, 0.12), 0.0, 0)
	return pods


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
