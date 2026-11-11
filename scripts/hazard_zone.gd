class_name HazardZone
extends Area3D
## A corridor hazard: a gas vent or a spark gap. It cycles through quiet, warning and
## active. Crossing it while it is ACTIVE costs reserve time; crossing it while quiet or
## in warning is safe, so the player can wait for the right moment.
## The zone only reports damage with a signal; GameManager decides what it costs.
##   gas:   drains Rules.GAS_DRAIN_PER_SECOND reserve seconds for every second inside.
##   spark: costs Rules.SPARK_PENALTY_SECONDS once per activation.

signal hit(kind: String, seconds: float, first: bool)

enum Phase { OFF, WARN, ON }

const KIND_GAS := "gas"
const KIND_SPARK := "spark"

var kind: String = KIND_GAS
var size: Vector3 = Vector3(6.0, 2.8, 3.0)

var _time: float = 0.0
var _exposed: bool = false           # already reported damage during this stay or activation
var _was_inside: bool = false
var _was_on: bool = false
var _cloud: MeshInstance3D
var _cloud_material: StandardMaterial3D
var _lamp_material: StandardMaterial3D
var _arc: MeshInstance3D
var _arc_material: StandardMaterial3D
var _light: OmniLight3D
var _rng := RandomNumberGenerator.new()


## `phase_offset` shifts where in its cycle the hazard starts, in seconds.
static func create(hazard_kind: String, zone_size: Vector3, at: Vector3, phase_offset: float) -> HazardZone:
	var zone := HazardZone.new()
	zone.kind = hazard_kind
	zone.size = zone_size
	zone.position = at
	zone._time = phase_offset
	zone.name = "Gas" if hazard_kind == KIND_GAS else "Sparks"
	zone._build()
	return zone


func cycle_seconds() -> float:
	if kind == KIND_GAS:
		return Rules.GAS_OFF_SECONDS + Rules.GAS_WARN_SECONDS + Rules.GAS_ON_SECONDS
	return Rules.SPARK_OFF_SECONDS + Rules.SPARK_WARN_SECONDS + Rules.SPARK_ON_SECONDS


func phase() -> Phase:
	var t := fposmod(_time, cycle_seconds())
	var off := Rules.GAS_OFF_SECONDS if kind == KIND_GAS else Rules.SPARK_OFF_SECONDS
	var warn := Rules.GAS_WARN_SECONDS if kind == KIND_GAS else Rules.SPARK_WARN_SECONDS
	if t < off:
		return Phase.OFF
	if t < off + warn:
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
	_rng.seed = 41

	# A status lamp on the ceiling above the zone: grey (quiet), amber (warning), red (active).
	_lamp_material = StandardMaterial3D.new()
	_lamp_material.emission_enabled = true
	var lamp := BoxMesh.new()
	lamp.size = Vector3(0.5, 0.18, 0.5)
	var lamp_mesh := MeshInstance3D.new()
	lamp_mesh.mesh = lamp
	lamp_mesh.material_override = _lamp_material
	lamp_mesh.position = Vector3(0.0, size.y * 0.5 - 0.15, 0.0)
	add_child(lamp_mesh)

	if kind == KIND_GAS:
		# A translucent cloud filling the corridor section, and a vent on the ceiling.
		_cloud_material = StandardMaterial3D.new()
		_cloud_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_cloud_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_cloud_material.cull_mode = BaseMaterial3D.CULL_DISABLED
		var cloud := BoxMesh.new()
		cloud.size = size * Vector3(1.0, 0.96, 0.96)
		_cloud = MeshInstance3D.new()
		_cloud.mesh = cloud
		_cloud.material_override = _cloud_material
		add_child(_cloud)
	else:
		# Two electrodes on the side walls with a bright arc between them while active.
		var electrode_material := StandardMaterial3D.new()
		electrode_material.albedo_color = Color(0.2, 0.22, 0.28)
		for side in [-1.0, 1.0]:
			var post := BoxMesh.new()
			post.size = Vector3(0.3, 0.4, 0.3)
			var post_mesh := MeshInstance3D.new()
			post_mesh.mesh = post
			post_mesh.material_override = electrode_material
			post_mesh.position = Vector3(0.0, -0.2, side * (size.z * 0.5 - 0.15))
			add_child(post_mesh)
		_arc_material = StandardMaterial3D.new()
		_arc_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_arc_material.albedo_color = Color(0.8, 0.95, 1.0)
		var arc := BoxMesh.new()
		arc.size = Vector3(0.08, 0.08, size.z - 0.4)
		_arc = MeshInstance3D.new()
		_arc.mesh = arc
		_arc.material_override = _arc_material
		_arc.position = Vector3(0.0, -0.2, 0.0)
		add_child(_arc)
	_light = OmniLight3D.new()
	_light.omni_range = 6.0
	_light.position = Vector3(0.0, 0.0, 0.0)
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
	var on := is_active()
	if not player_inside:
		_exposed = false
	if on and not _was_on:
		_exposed = false   # a new activation can hit again
	_was_on = on
	_was_inside = player_inside
	if player_inside and on:
		if kind == KIND_GAS:
			hit.emit(kind, Rules.GAS_DRAIN_PER_SECOND * delta, not _exposed)
			_exposed = true
		elif not _exposed:
			_exposed = true
			hit.emit(kind, Rules.SPARK_PENALTY_SECONDS, true)
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
	if kind == KIND_GAS:
		match current:
			Phase.OFF:
				_cloud_material.albedo_color = Color(0.3, 1.0, 0.45, 0.0)
			Phase.WARN:
				_cloud_material.albedo_color = Color(1.0, 0.8, 0.2, 0.06 + 0.08 * pulse)
			Phase.ON:
				_cloud_material.albedo_color = Color(0.3, 1.0, 0.45, 0.32 + 0.1 * pulse)
		_light.light_color = Color(0.3, 1.0, 0.45)
		_light.light_energy = 0.9 if current == Phase.ON else 0.0
	else:
		var flicker := _rng.randf() < 0.6
		_arc.visible = current == Phase.ON or (current == Phase.WARN and flicker and pulse > 0.7)
		_light.light_color = Color(0.7, 0.9, 1.0)
		_light.light_energy = 2.5 if current == Phase.ON else (0.8 if _arc.visible else 0.0)
