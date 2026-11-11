extends SceneTree
## The generated textures and the scenery: the textures tile and are light enough to tint, the walls,
## floor and ceiling use them in world space, and the rooms have their props without blocking the
## consoles or the doorways.
## Run:  godot --headless --path . -s res://tests/test_visuals.gd

var _failures: int = 0


func _initialize() -> void:
	_test_textures()
	await _test_station()
	print("")
	if _failures == 0:
		print("ALL PASS")
		quit(0)
	else:
		print("%d FAILURE(S)" % _failures)
		quit(1)


func _average(texture: Texture2D) -> float:
	var image := texture.get_image()
	var total := 0.0
	for y in image.get_height():
		for x in image.get_width():
			total += image.get_pixel(x, y).r
	return total / float(image.get_width() * image.get_height())


func _test_textures() -> void:
	for pair in [["plating", ProcTextures.plating()], ["diamond plate", ProcTextures.diamond_plate()], ["ribbed", ProcTextures.ribbed()], ["scan lines", ProcTextures.scanlines()]]:
		var texture: ImageTexture = pair[1]
		var image := texture.get_image()
		var average := _average(texture)
		_check(texture.get_width() >= 8 and average > 0.5 and average < 0.98, "the %s texture exists and is light enough to tint the theme colour without hiding it (average %.2f)" % [pair[0], average])
		_check(image.has_mipmaps(), "the %s texture has mipmaps, so it does not shimmer in the distance" % pair[0])
	_check(ProcTextures.plating() == ProcTextures.plating(), "a texture is built once and reused")
	var plating := ProcTextures.plating().get_image()
	var darkest := 1.0
	var lightest := 0.0
	for y in plating.get_height():
		for x in plating.get_width():
			darkest = minf(darkest, plating.get_pixel(x, y).r)
			lightest = maxf(lightest, plating.get_pixel(x, y).r)
	_check(darkest < 0.6 and lightest > 0.95, "the plating has dark seams and bright rivet heads")
	var material := ProcTextures.material(Color(0.5, 0.2, 0.2), ProcTextures.plating(), 0.5)
	_check(material.uv1_triplanar and material.uv1_world_triplanar and is_equal_approx(material.uv1_scale.x, 0.5) and material.albedo_color == Color(0.5, 0.2, 0.2), "the material maps in world space and keeps the tint")


func _test_station() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var station := StationBuilder.build(world, PuzzleGenerator.generate(6, 0))
	var textured := 0
	for body in world.find_children("*", "StaticBody3D", true, false):
		if body.get_child_count() > 0 and body.get_child(0) is MeshInstance3D:
			var material := (body.get_child(0) as MeshInstance3D).material_override as StandardMaterial3D
			if material != null and material.albedo_texture != null and material.uv1_world_triplanar:
				textured += 1
	_check(textured >= 20, "the walls, floors and ceilings use the textured materials (%d bodies)" % textured)
	# Props (duplicate node names get renamed by Godot, so they are found by their shape).
	var cabinets: Array = []
	var tanks: Array = []
	var racks: Array = []
	for body in world.find_children("*", "StaticBody3D", true, false):
		if body.get_child_count() == 0 or not (body.get_child(0) is MeshInstance3D):
			continue
		var mesh := (body.get_child(0) as MeshInstance3D).mesh
		if mesh is BoxMesh and (mesh as BoxMesh).size.is_equal_approx(Vector3(0.6, 2.1, 0.9)):
			cabinets.append(body)
		elif mesh is BoxMesh and (mesh as BoxMesh).size.is_equal_approx(Vector3(0.6, 2.0, 0.8)):
			racks.append(body)
		elif mesh is CylinderMesh and is_equal_approx((mesh as CylinderMesh).height, 2.3):
			tanks.append(body)
	var dishes := world.find_children("Dish", "MeshInstance3D", true, false)
	_check(cabinets.size() == 4 and tanks.size() == 4 and racks.size() == 4 and dishes.size() == 1, "Power has 4 cabinets, Oxygen 4 tanks, Comms 4 racks and a dish (%d, %d, %d, %d)" % [cabinets.size(), tanks.size(), racks.size(), dishes.size()])
	# Props never block a console, a breaker or the doorway.
	var clear := true
	for prop in cabinets + tanks + racks:
		var a: Vector3 = (prop as Node3D).position
		for item in station["interactables"]:
			var b: Vector3 = (item as Node3D).position
			if absf(a.x - b.x) < 1.2 and absf(a.z - b.z) < 1.0:
				clear = false
		for room_x in [12.0, 24.0, 36.0]:
			if absf(a.x - room_x) < 1.6 and a.z > StationBuilder.HUB_BACK_Z - 2.0:
				clear = false
	_check(clear, "no prop stands within reach of a console or breaker, or in a doorway")
	# Lamp housings.
	var lamps := world.find_children("*", "MeshInstance3D", true, false).filter(func(m: Node) -> bool: return (m as MeshInstance3D).mesh is BoxMesh and ((m as MeshInstance3D).mesh as BoxMesh).size.is_equal_approx(Vector3(0.7, 0.04, 0.26)))
	_check(lamps.size() == (station["corridor_lights"] as Array).size(), "every corridor light has a lamp fixture under it")
	# The reactor rings share the reactor's glow, so they turn cyan with the repair.
	var reactor: StandardMaterial3D = station["reactor"]
	var rings := world.find_children("*", "MeshInstance3D", true, false).filter(func(m: Node) -> bool: return (m as MeshInstance3D).material_override == reactor and (m as MeshInstance3D).mesh is CylinderMesh and ((m as MeshInstance3D).mesh as CylinderMesh).height < 0.1)
	_check(rings.size() == 3, "three rings round the reactor share its glow")
	world.free()
	await process_frame


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS  " + label)
	else:
		print("FAIL  " + label)
		_failures += 1
