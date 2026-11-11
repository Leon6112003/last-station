class_name LaserGrid
extends Node3D
## A laser barrier across the corridor. While it is ON it is a solid wall you cannot walk
## through, and touching it costs reserve time. Two wall switches (one on each side) turn it
## off for a while; it flickers before it switches back on, and it will not switch back on
## while someone is standing in the beams.
## It only reports touches with a signal; GameManager decides what they cost.

signal touched(seconds: float)
signal state_changed(armed: bool)

const BEAM_HEIGHTS := [0.35, 0.8, 1.25, 1.7, 2.15, 2.6]

var armed: bool = true
var corridor_width: float = 3.0
var height: float = 2.8

var _off_left: float = 0.0
var _touch_latched: bool = false      # the player is still against the beams after a touch
var _flicker_time: float = 0.0
## How long a wall switch keeps this grid off (shorter on later shifts).
var off_seconds: float = Rules.laser_off()
var _barrier: StaticBody3D
var _sensor: Area3D
var _beams: Array[MeshInstance3D] = []
var _beam_material: StandardMaterial3D
var _emitter_material: StandardMaterial3D
var _light: OmniLight3D
var _label: Label3D


static func create(at: Vector3, width: float, wall_height: float, shift: int = 1) -> LaserGrid:
	var grid := LaserGrid.new()
	grid.off_seconds = Rules.laser_off_for(shift)
	grid.name = "LaserGrid"
	grid.position = at
	grid.corridor_width = width
	grid.height = wall_height
	grid._build()
	return grid


func _build() -> void:
	# The solid barrier: thin along the corridor, spanning its whole width.
	_barrier = StaticBody3D.new()
	_barrier.name = "Barrier"
	_barrier.collision_layer = Rules.LAYER_WORLD
	_barrier.collision_mask = 0
	var barrier_shape := BoxShape3D.new()
	barrier_shape.size = Vector3(0.2, height, corridor_width)
	var barrier_collider := CollisionShape3D.new()
	barrier_collider.shape = barrier_shape
	barrier_collider.position.y = height * 0.5
	_barrier.add_child(barrier_collider)
	add_child(_barrier)

	# A slightly thicker sensor, so touching the beams (or standing against them) is noticed.
	_sensor = Area3D.new()
	_sensor.name = "Sensor"
	_sensor.collision_layer = 0
	_sensor.collision_mask = Rules.LAYER_PLAYER
	_sensor.monitorable = false
	var sensor_shape := BoxShape3D.new()
	sensor_shape.size = Vector3(1.1, height, corridor_width)
	var sensor_collider := CollisionShape3D.new()
	sensor_collider.shape = sensor_shape
	sensor_collider.position.y = height * 0.5
	_sensor.add_child(sensor_collider)
	add_child(_sensor)

	_beam_material = StandardMaterial3D.new()
	_beam_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_beam_material.albedo_color = Color(1.0, 0.25, 0.3)
	for beam_y in BEAM_HEIGHTS:
		var box := BoxMesh.new()
		box.size = Vector3(0.06, 0.07, corridor_width - 0.2)
		var beam := MeshInstance3D.new()
		beam.mesh = box
		beam.material_override = _beam_material
		beam.position = Vector3(0.0, float(beam_y), 0.0)
		add_child(beam)
		_beams.append(beam)

	# Emitter posts at both ends of the grid.
	_emitter_material = StandardMaterial3D.new()
	_emitter_material.emission_enabled = true
	_emitter_material.albedo_color = Color(0.15, 0.16, 0.2)
	for side in [-1.0, 1.0]:
		var post := BoxMesh.new()
		post.size = Vector3(0.3, height, 0.3)
		var post_mesh := MeshInstance3D.new()
		post_mesh.mesh = post
		post_mesh.material_override = _emitter_material
		post_mesh.position = Vector3(0.0, height * 0.5, side * (corridor_width * 0.5 - 0.15))
		add_child(post_mesh)

	_light = OmniLight3D.new()
	_light.omni_range = 5.0
	_light.position = Vector3(0.0, 1.5, 0.0)
	add_child(_light)

	_label = Label3D.new()
	_label.font_size = 30
	_label.pixel_size = 0.006
	_label.outline_size = 8
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.position = Vector3(0.0, height + 0.3, 0.0)
	add_child(_label)
	_refresh_visuals()


## Turns the grid off for `off_seconds` (pressing the switch again starts the time over).
func switch_off() -> void:
	var was_armed := armed
	armed = false
	_off_left = off_seconds
	_barrier.collision_layer = 0
	if was_armed:
		state_changed.emit(false)
	_refresh_visuals()


func off_seconds_left() -> float:
	return _off_left if not armed else 0.0


func _physics_process(delta: float) -> void:
	var near := false
	for body in _sensor.get_overlapping_bodies():
		if body is PlayerController:
			near = true
	tick(delta, near)


## Advances the grid. Separate from _physics_process so it can be tested without physics.
func tick(delta: float, player_near: bool) -> void:
	_flicker_time += delta
	if armed:
		if not player_near:
			_touch_latched = false
		elif not _touch_latched:
			_touch_latched = true
			touched.emit(Rules.laser_penalty())
	else:
		# It stays off while someone stands in the beams, rather than switching on around them.
		if _off_left > 0.0:
			_off_left = maxf(0.0, _off_left - delta)
		if _off_left <= 0.0 and not player_near:
			armed = true
			_touch_latched = false
			_barrier.collision_layer = Rules.LAYER_WORLD
			state_changed.emit(true)
	_refresh_visuals()


func _refresh_visuals() -> void:
	var warning := not armed and _off_left > 0.0 and _off_left <= Rules.LASER_WARN_SECONDS
	var flicker_on := fmod(_flicker_time, 0.3) < 0.15
	for beam in _beams:
		beam.visible = armed or (warning and flicker_on)
	var emitter_color := Rules.COLOR_FAULT if armed else Rules.COLOR_CYAN
	_emitter_material.emission = emitter_color
	_emitter_material.emission_energy_multiplier = 1.4
	_light.light_color = Rules.COLOR_FAULT if armed else Rules.COLOR_CYAN
	_light.light_energy = 1.6 if armed else 0.5
	if armed:
		_label.text = "LASER GRID ON"
		_label.modulate = Rules.COLOR_FAULT
	else:
		_label.text = "LASER OFF  %d s" % int(ceil(_off_left))
		_label.modulate = Rules.COLOR_CYAN
