class_name ProcTextures
extends RefCounted
## Small textures drawn in code (no image files), so the walls, floor and ceiling are not flat
## colour. They are mostly light grey, so they darken the station's theme colour instead of
## replacing it; each repeats seamlessly. They are mapped in world space (triplanar), so one
## material covers boxes of any size with the same size of plate.

const SIZE := 64

static var _cache: Dictionary = {}


## Wall plating: a 2 m x 2 m plate (at the usual scale) with dark seams, rivets and a faint brushed grain.
static func plating() -> ImageTexture:
	return _cached("plating", func() -> Image:
		var image := Image.create(SIZE, SIZE, false, Image.FORMAT_RGB8)
		var rng := RandomNumberGenerator.new()
		rng.seed = 2024
		for y in SIZE:
			for x in SIZE:
				var level := 0.93 - rng.randf() * 0.03 - 0.02 * sin(float(y) * 0.9)   # grain along the plate
				if x < 2 or y < 2:
					level = 0.52   # the seam (wraps round, so every plate has one on two sides)
				elif x == 2 or y == 2:
					level = 1.0    # a lit edge beside the seam
				image.set_pixel(x, y, Color(level, level, level))
		# Rivets in the corners and mid-edges.
		for rivet in [Vector2i(8, 8), Vector2i(56, 8), Vector2i(8, 56), Vector2i(56, 56), Vector2i(32, 8), Vector2i(32, 56), Vector2i(8, 32), Vector2i(56, 32)]:
			_dot(image, rivet + Vector2i(1, 1), 2, 0.5)    # a little shadow below and to the right
			_dot(image, rivet, 2, 0.97)                   # the bright rivet head
		return image)


## Floor: diamond tread plate, the raised diamonds lighter than the base, with a dark border.
static func diamond_plate() -> ImageTexture:
	return _cached("diamond", func() -> Image:
		var image := Image.create(SIZE, SIZE, false, Image.FORMAT_RGB8)
		for y in SIZE:
			for x in SIZE:
				var cell := 16
				var dx := absi(posmod(x, cell) - cell / 2)
				var dy := absi(posmod(y, cell) - cell / 2)
				var level := 0.62
				if dx + dy < 6:
					level = 0.88
				elif dx + dy < 8:
					level = 0.74
				if x < 1 or y < 1:
					level = 0.4
				image.set_pixel(x, y, Color(level, level, level))
		return image)


## Ceiling: long ribs with a dark groove between them.
static func ribbed() -> ImageTexture:
	return _cached("ribbed", func() -> Image:
		var image := Image.create(SIZE, SIZE, false, Image.FORMAT_RGB8)
		for y in SIZE:
			for x in SIZE:
				var phase := posmod(y, 16)
				var level := 0.85
				if phase < 2:
					level = 0.45
				elif phase < 4:
					level = 0.95
				elif phase > 12:
					level = 0.78
				if x < 1:
					level = 0.6
				image.set_pixel(x, y, Color(level, level, level))
		return image)


## Screens: faint horizontal scan lines over a dark base (for the dark plates behind wall text).
static func scanlines() -> ImageTexture:
	return _cached("scanlines", func() -> Image:
		var image := Image.create(8, 8, false, Image.FORMAT_RGB8)
		for y in 8:
			var level := 1.0 if y % 2 == 0 else 0.78
			for x in 8:
				image.set_pixel(x, y, Color(level, level, level))
		return image)


## A material that shows `texture` in world space, `tiles_per_metre` times per metre, tinted by `color`.
static func material(color: Color, texture: Texture2D, tiles_per_metre: float, roughness: float = 0.85) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.albedo_texture = texture
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3(tiles_per_metre, tiles_per_metre, tiles_per_metre)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	m.roughness = roughness
	return m


static func _cached(key: String, build: Callable) -> ImageTexture:
	if _cache.has(key):
		return _cache[key]
	var image: Image = build.call()
	image.generate_mipmaps()
	var texture := ImageTexture.create_from_image(image)
	_cache[key] = texture
	return texture


static func _dot(image: Image, centre: Vector2i, radius: int, level: float) -> void:
	for y in range(-radius, radius + 1):
		for x in range(-radius, radius + 1):
			if x * x + y * y <= radius * radius:
				var px := posmod(centre.x + x, SIZE)
				var py := posmod(centre.y + y, SIZE)
				image.set_pixel(px, py, Color(level, level, level))
