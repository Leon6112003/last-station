extends SceneTree
## Milestone 1 smoke test: the station builds, geometry exists, the player
## can be created, and interactables are wired.
## Run:  godot --headless --path . -s res://tests/test_smoke.gd

var _failures: int = 0


func _initialize() -> void:
	var world := Node3D.new()
	root.add_child(world)

	var station := StationBuilder.build(world, PuzzleGenerator.generate(1, 0))
	_check(station.has("spawn"), "station returns a spawn position")

	var items: Array = station["interactables"]
	_check(items.size() == 7, "station has 7 interactables (4 breakers, 2 consoles, reboot terminal), got %d" % items.size())

	var ids := items.map(func(i: Interactable) -> String: return i.id)
	for expected in ["breaker_0", "breaker_1", "breaker_2", "breaker_3", "oxygen_console", "comms_console", "reboot_terminal"]:
		_check(ids.has(expected), "interactable '%s' exists" % expected)

	_check((station["room_lights"] as Dictionary).size() == 3, "three room lights exist")

	var bodies := world.find_children("*", "StaticBody3D", true, false)
	_check(bodies.size() >= 12, "station contains solid bodies (found %d)" % bodies.size())

	# Layout: header and sign above each doorway, door status, boards, labels on breakers.
	# Headers are 2 m wide, about 0.7 m tall, and sit above the doorways (Godot renames
	# duplicate node names, so find them by their size and height instead).
	var headers := world.find_children("*", "StaticBody3D", true, false).filter(func(b: StaticBody3D) -> bool:
		var mesh := (b.get_child(0) as MeshInstance3D).mesh as BoxMesh
		return b.position.y > 2.3 and b.position.y < 2.9 and absf(mesh.size.x - 2.0) < 0.01 and mesh.size.y < 1.0)
	_check(headers.size() == 4, "there is a header above each of the four doorways: crew quarters and three systems (found %d)" % headers.size())
	var clear_height := true
	for header in headers:
		var box := ((header as StaticBody3D).get_child(0) as MeshInstance3D).mesh as BoxMesh
		if (header as Node3D).position.y - box.size.y * 0.5 < 2.0:
			clear_height = false
	_check(clear_height, "every doorway leaves at least 2 m of headroom")
	var statuses: Dictionary = station["door_status"]
	_check(statuses.size() == 3, "each door has a status material")
	var all_red := true
	for room in statuses:
		if (statuses[room] as StandardMaterial3D).albedo_color != Rules.COLOR_FAULT:
			all_red = false
	_check(all_red, "doors start red (faulted)")
	_check((station["room_strips"] as Dictionary).size() == 3 and (station["room_floors"] as Dictionary).size() == 3, "each room has a ceiling strip and a floor patch")
	_check(station["hub_light"] is OmniLight3D, "the hub has an emergency light for the atmosphere")
	var protocol_signs := world.find_children("*", "Label3D", true, false).filter(
		func(l: Label3D) -> bool: return l.text.begins_with("PROTOCOL"))
	var expected_sign := "PROTOCOL %s" % PuzzleGenerator.generate(1, 0)["protocol"]
	_check(protocol_signs.size() == 1 and (station["protocol_board"] as Label3D).text == expected_sign, "one protocol sign, showing the shift's protocol (%s)" % expected_sign)
	var breaker_labels := world.find_children("*", "Label3D", true, false).filter(
		func(l: Label3D) -> bool: return l.text.begins_with("B") and l.text.contains("\n") and l.text.ends_with(" V"))
	_check(breaker_labels.size() == 4, "each breaker has its rating printed on it (found %d)" % breaker_labels.size())
	_check(not (station["interactables"] as Array).any(func(i: Interactable) -> bool: return i.position.y < 0.0), "no terminal is below the floor")

	var player := PlayerController.new()
	player.position = station["spawn"]
	world.add_child(player)
	await process_frame  # let the player's _ready() run before inspecting it
	_check(player.get_child_count() >= 2, "player builds collider and camera")
	_check(player.collision_layer == Rules.LAYER_PLAYER, "player is on the player layer")

	var spawn: Vector3 = station["spawn"]
	_check(absf(spawn.x - StationBuilder.BEDROOM_X) < StationBuilder.ROOM_HALF_WIDTH and spawn.z > StationBuilder.ROOM_BACK_Z and spawn.z < StationBuilder.HUB_BACK_Z, "the player wakes up inside the crew quarters")
	_check(is_equal_approx(float(station["spawn_yaw"]), 180.0), "the player wakes up facing the bedroom door")

	# The walk: doors, hazards, and the reboot terminal at the far end.
	var doors: Dictionary = station["doors"]
	_check(doors.size() == 2 and doors.has("oxygen") and doors.has("comms") and not doors.has("power"), "Oxygen and Comms have doors; Power is open from the start")
	_check((doors["oxygen"] as DoorGate).locked and (doors["comms"] as DoorGate).locked, "the Oxygen and Comms doors start locked")
	_check((doors["oxygen"] as DoorGate).requires == "power" and (doors["comms"] as DoorGate).requires == "oxygen", "Oxygen needs Power, Comms needs Oxygen")
	var hazards: Array = station["hazards"]
	_check(hazards.size() == 2 and (hazards[0] as HazardZone).kind == "gas" and (hazards[1] as HazardZone).kind == "spark", "the corridor has a gas vent and a spark gap")
	var gas_x: float = (hazards[0] as HazardZone).position.x
	var spark_x: float = (hazards[1] as HazardZone).position.x
	_check(gas_x > StationBuilder.ROOM_CENTERS_X["power"] and gas_x < StationBuilder.ROOM_CENTERS_X["oxygen"] and spark_x > StationBuilder.ROOM_CENTERS_X["oxygen"] and spark_x < StationBuilder.ROOM_CENTERS_X["comms"], "gas lies between Power and Oxygen, sparks between Oxygen and Comms")
	var reboot_position: Vector3 = (station["reboot"] as Interactable).position
	_check(reboot_position.x < StationBuilder.BEDROOM_X - 3.0, "the reboot terminal is at the far west end of the corridor (x=%.1f)" % reboot_position.x)
	var far_room_x: float = StationBuilder.ROOM_CENTERS_X["comms"]
	_check(far_room_x - StationBuilder.BEDROOM_X >= 30.0, "the farthest room is a real walk from the bed (%.0f m)" % (far_room_x - StationBuilder.BEDROOM_X))

	print("")
	if _failures == 0:
		print("ALL PASS")
		quit(0)
	else:
		print("%d FAILURE(S)" % _failures)
		quit(1)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS  ", label)
	else:
		print("FAIL  ", label)
		_failures += 1
