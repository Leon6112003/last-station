class_name GravityZone
extends Node3D
## A stretch of corridor where the gravity generator has failed. While the zone is ACTIVE the
## player floats: slower, drifting up off the floor, and every second inside costs reserve
## time. Two wall switches (one on each side) bring gravity back for a while; the zone flickers
## before it fails again, and it will not fail around someone standing in it.
## It only reports the drain with a signal; GameManager decides what it costs.

signal touched(seconds: float)          ## reserve drain, sent once per DRAIN_INTERVAL while someone floats here
signal state_changed(armed: bool)       ## armed = gravity is OFF (the hazard is active)

const ZONE_LENGTH := 6.0                ## metres along the corridor
const DRAIN_INTERVAL := 1.0             ## seconds between drains while the player floats here
const DRAIN_FRACTION := 0.2             ## of the level's hazard penalty, per second spent floating
const MOTE_COUNT := 14                  ## little floating cubes that show the zone is weightless

var armed: bool = true                  ## true = gravity is off here (active hazard)
var corridor_width: float = 3.0
var height: float = 2.8

var _off_left: float = 0.0
var _drain_clock: float = 0.0
var _flicker_time: float = 0.0
## How long a wall switch keeps gravity on (shorter on later shifts).
var off_seconds: float = Rules.gravity_off()
## Fixed for good: the system it belongs to was repaired. Gravity never fails again this shift.
var offline: bool = false
var _sensor: Area3D
var _volume: MeshInstance3D
var _volume_material: StandardMaterial3D
var _motes: Array[MeshInstance3D] = []
var _light: OmniLight3D
var _label: Label3D
var _floater: PlayerController = null   ## the player currently inside, if any


static func create(at: Vector3, width: float, wall_height: float, shift: int = 1) -> GravityZone:
	var zone := GravityZone.new()
	zone.off_seconds = Rules.gravity_off_for(shift)
	zone.name = "GravityZone"
	zone.position = at
	zone.corridor_width = width
	zone.height = wall_height
	zone._build()
	return zone


func _build() -> void:
	# A sensor over the whole stretch: no solid barrier, the player can always walk in.
	_sensor = Area3D.new()
	_sensor.name = "Sensor"
	_sensor.collision_layer = 0
	_sensor.collision_mask = Rules.LAYER_PLAYER
	_sensor.monitorable = false
	var sensor_shape := BoxShape3D.new()
	sensor_shape.size = Vector3(ZONE_LENGTH, height, corridor_width)
	var sensor_collider := CollisionShape3D.new()
	sensor_collider.shape = sensor_shape
	sensor_collider.position.y = height * 0.5
	_sensor.add_child(sensor_collider)
	add_child(_sensor)

	# A faint violet haze over the stretch so it reads as a different kind of space.
	_volume_material = StandardMaterial3D.new()
	_volume_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_volume_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_volume_material.albedo_color = Color(Rules.COLOR_VIOLET, 0.12)
	_volume_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var box := BoxMesh.new()
	box.size = Vector3(ZONE_LENGTH - 0.2, height - 0.2, corridor_width - 0.2)
	_volume = MeshInstance3D.new()
	_volume.mesh = box
	_volume.material_override = _volume_material
	_volume.position.y = height * 0.5
	add_child(_volume)

	# Small cubes that hang and drift in the air.
	var mote_material := StandardMaterial3D.new()
	mote_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mote_material.albedo_color = Rules.COLOR_CYAN
	for i in MOTE_COUNT:
		var mote_mesh := BoxMesh.new()
		mote_mesh.size = Vector3.ONE * 0.12
		var mote := MeshInstance3D.new()
		mote.mesh = mote_mesh
		mote.material_override = mote_material
		var fraction := float(i) / float(MOTE_COUNT)
		mote.position = Vector3(
			(fraction - 0.5) * (ZONE_LENGTH - 0.8),
			0.4 + fmod(float(i) * 0.73, 1.0) * (height - 0.8),
			sin(float(i) * 2.1) * (corridor_width * 0.4))
		add_child(mote)
		_motes.append(mote)

	_light = OmniLight3D.new()
	_light.omni_range = 6.0
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


## Brings gravity back for `off_seconds` (pressing the switch again starts the time over).
func switch_off() -> void:
	if offline:
		return
	var was_armed := armed
	armed = false
	_off_left = off_seconds
	_release_floater()
	if was_armed:
		state_changed.emit(false)
	_refresh_visuals()


## Fixes the generator for good (nothing can make it fail again this shift).
func go_offline() -> void:
	var was_armed := armed
	offline = true
	armed = false
	_off_left = 0.0
	_release_floater()
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
			_floater = body as PlayerController
	if not near:
		_release_floater()
	tick(delta, near)
	if near and armed and _floater != null:
		_floater.zero_g = true


func _process(delta: float) -> void:
	# The motes drift lazily; purely visual.
	if _volume == null or not armed:
		return
	for i in _motes.size():
		var mote := _motes[i]
		mote.position.y += sin(_flicker_time * 0.8 + float(i)) * 0.15 * delta
		mote.rotation += Vector3(0.3, 0.5, 0.2) * delta


func _exit_tree() -> void:
	_release_floater()


func _release_floater() -> void:
	if _floater != null and is_instance_valid(_floater):
		_floater.zero_g = false
	_floater = null


## Advances the zone. Separate from _physics_process so it can be tested without physics.
func tick(delta: float, player_near: bool) -> void:
	_flicker_time += delta
	if offline:
		_refresh_visuals()
		return
	if armed:
		if player_near:
			_drain_clock += delta
			while _drain_clock >= DRAIN_INTERVAL:
				_drain_clock -= DRAIN_INTERVAL
				touched.emit(Rules.gravity_penalty() * DRAIN_FRACTION)
		else:
			_drain_clock = 0.0
	else:
		# It stays working while someone stands in it, rather than failing around them.
		if _off_left > 0.0:
			_off_left = maxf(0.0, _off_left - delta)
		if _off_left <= 0.0 and not player_near:
			armed = true
			_drain_clock = 0.0
			state_changed.emit(true)
	_refresh_visuals()


func _refresh_visuals() -> void:
	var warning := not armed and _off_left > 0.0 and _off_left <= Rules.GRAVITY_WARN_SECONDS
	var flicker_on := fmod(_flicker_time, 0.3) < 0.15
	var shown := armed or (warning and flicker_on)
	_volume.visible = shown
	for mote in _motes:
		mote.visible = shown
	_light.light_color = Rules.COLOR_VIOLET if armed else Rules.COLOR_CYAN
	_light.light_energy = 1.4 if armed else 0.4
	if offline:
		_label.text = "GRAVITY STABLE"
		_label.modulate = Rules.COLOR_CYAN
	elif armed:
		_label.text = "ZERO GRAVITY"
		_label.modulate = Rules.COLOR_VIOLET
	else:
		_label.text = "GRAVITY ON  %d s" % int(ceil(_off_left))
		_label.modulate = Rules.COLOR_CYAN
