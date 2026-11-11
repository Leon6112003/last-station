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
