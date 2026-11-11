class_name HazardZone
extends Area3D
## A corridor gas vent. It cycles through quiet, warning and venting. Standing in it while it
## is VENTING drains reserve time; being in it while quiet or in warning is safe, so the
## player can wait for the right moment. The zone only reports damage with a signal;
## GameManager decides what it costs.

signal hit(kind: String, seconds: float, first: bool)

enum Phase { OFF, WARN, ON }

const KIND_GAS := "gas"

var kind: String = KIND_GAS
var size: Vector3 = Vector3(6.0, 2.8, 3.0)

var _time: float = 0.0
var _exposed: bool = false           # already reported damage during this stay
var _cloud_material: StandardMaterial3D
var _lamp_material: StandardMaterial3D
var _light: OmniLight3D


## `phase_offset` shifts where in its cycle the vent starts, in seconds.
static func create(zone_size: Vector3, at: Vector3, phase_offset: float) -> HazardZone:
	var zone := HazardZone.new()
	zone.size = zone_size
	zone.position = at
	zone._time = phase_offset
	zone.name = "Gas"
	zone._build()
	return zone


func cycle_seconds() -> float:
	return Rules.GAS_OFF_SECONDS + Rules.GAS_WARN_SECONDS + Rules.GAS_ON_SECONDS


func phase() -> Phase:
	var t := fposmod(_time, cycle_seconds())
	if t < Rules.GAS_OFF_SECONDS:
		return Phase.OFF
	if t < Rules.GAS_OFF_SECONDS + Rules.GAS_WARN_SECONDS:
		return Phase.WARN
	return Phase.ON


func is_active() -> bool:
	return phase() == Phase.ON


func _build() -> void:
	collision_layer = 0
	collision_mask = Rules.LAYER_PLAYER
	monitoring = true
	monitorable = false
	var shape := BoxShape3D.new()
	shape.size = size
	var collider := CollisionShape3D.new()
	collider.shape = shape
	add_child(collider)

	# A status lamp on the ceiling above the zone: grey (quiet), amber (warning), red (venting).
	_lamp_material = StandardMaterial3D.new()
	_lamp_material.emission_enabled = true
	var lamp := BoxMesh.new()
	lamp.size = Vector3(0.5, 0.18, 0.5)
	var lamp_mesh := MeshInstance3D.new()
	lamp_mesh.mesh = lamp
	lamp_mesh.material_override = _lamp_material
	lamp_mesh.position = Vector3(0.0, size.y * 0.5 - 0.15, 0.0)
	add_child(lamp_mesh)

	# A translucent cloud filling the corridor section.
	_cloud_material = StandardMaterial3D.new()
	_cloud_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_cloud_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_cloud_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var cloud := BoxMesh.new()
	cloud.size = size * Vector3(1.0, 0.96, 0.96)
	var cloud_mesh := MeshInstance3D.new()
	cloud_mesh.mesh = cloud
	cloud_mesh.material_override = _cloud_material
	add_child(cloud_mesh)

	_light = OmniLight3D.new()
	_light.omni_range = 6.0
	_light.light_color = Color(0.3, 1.0, 0.45)
	add_child(_light)
	_update_visuals()


func _physics_process(delta: float) -> void:
	var inside := false
	for body in get_overlapping_bodies():
		if body is PlayerController:
			inside = true
	tick(delta, inside)


## Advances the cycle and applies damage. Separate from _physics_process so it can be tested
## without physics.
func tick(delta: float, player_inside: bool) -> void:
	_time += delta
	if not player_inside:
		_exposed = false
	if player_inside and is_active():
		hit.emit(kind, Rules.gas_drain() * delta, not _exposed)
		_exposed = true
	_update_visuals()


func _update_visuals() -> void:
	var current := phase()
	var pulse := 0.5 + 0.5 * sin(_time * 8.0)
	var lamp_color := Color(0.25, 0.27, 0.32)
	if current == Phase.WARN:
		lamp_color = Color(1.0, 0.7, 0.15)
	elif current == Phase.ON:
		lamp_color = Rules.COLOR_FAULT
	_lamp_material.albedo_color = lamp_color
	_lamp_material.emission = lamp_color
	_lamp_material.emission_energy_multiplier = 0.4 if current == Phase.OFF else 1.0 + pulse
	match current:
		Phase.OFF:
			_cloud_material.albedo_color = Color(0.3, 1.0, 0.45, 0.0)
		Phase.WARN:
			_cloud_material.albedo_color = Color(1.0, 0.8, 0.2, 0.06 + 0.08 * pulse)
		Phase.ON:
			_cloud_material.albedo_color = Color(0.3, 1.0, 0.45, 0.32 + 0.1 * pulse)
	_light.light_energy = 0.9 if current == Phase.ON else 0.0
