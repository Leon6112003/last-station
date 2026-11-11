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
	_check(headers.size() == 3, "there is a header above each of the three doorways (found %d)" % headers.size())
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
	var protocol_signs := world.find_children("*", "Label3D", true, false).filter(
		func(l: Label3D) -> bool: return l.text.begins_with("PROTOCOL"))
	var expected_sign := "PROTOCOL %s" % PuzzleGenerator.generate(1, 0)["protocol"]
	_check(protocol_signs.size() == 1 and (station["protocol_board"] as Label3D).text == expected_sign, "one protocol sign, showing the shift's protocol (%s)" % expected_sign)
	var breaker_labels := world.find_children("*", "Label3D", true, false).filter(
		func(l: Label3D) -> bool: return l.text.contains(" V") and l.position.y < 2.0)
	_check(breaker_labels.size() == 4, "each breaker has its rating printed on it (found %d)" % breaker_labels.size())
	_check(not (station["interactables"] as Array).any(func(i: Interactable) -> bool: return i.position.y < 0.0), "no terminal is below the floor")

	var player := PlayerController.new()
	player.position = station["spawn"]
	world.add_child(player)
	await process_frame  # let the player's _ready() run before inspecting it
	_check(player.get_child_count() >= 2, "player builds collider and camera")
	_check(player.collision_layer == Rules.LAYER_PLAYER, "player is on the player layer")

	var spawn: Vector3 = station["spawn"]
	_check(absf(spawn.x) < 6.0 and spawn.z > -3.0 and spawn.z < 3.0, "spawn is inside the hub")

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
