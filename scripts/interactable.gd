class_name Interactable
extends StaticBody3D
## A solid, glowing box the player can aim at and activate with E.
## It only reports that it was activated; game rules live elsewhere.

signal interacted(interactable: Interactable, player: Node)

@export var id: String = ""
@export var prompt: String = "INTERACT"

var enabled: bool = true

var _mesh: MeshInstance3D
var _material: StandardMaterial3D
var _highlighted: bool = false
var _pulse_time: float = 0.0

const GLOW_IDLE := 0.3
const GLOW_HIGHLIGHT := 1.6
const GLOW_EASE_SPEED := 12.0
const PRESS_DEPTH := 0.08      # metres the box moves away from the player when pressed
const PRESS_SECONDS := 0.22


func setup(box_size: Vector3, color: Color) -> void:
	# Layer 1 so the player collides with it, layer 4 so the interaction ray hits it.
	collision_layer = Rules.LAYER_WORLD | Rules.LAYER_INTERACT
	collision_mask = 0

	_material = StandardMaterial3D.new()
	_material.albedo_color = color
	_material.emission_enabled = true
	_material.emission = color
	_material.emission_energy_multiplier = GLOW_IDLE

	var box := BoxMesh.new()
	box.size = box_size
	_mesh = MeshInstance3D.new()
	_mesh.mesh = box
	_mesh.material_override = _material
	add_child(_mesh)

	var shape := BoxShape3D.new()
	shape.size = box_size
	var collider := CollisionShape3D.new()
	collider.shape = shape
	add_child(collider)


func set_color(color: Color) -> void:
	if _material:
		_material.albedo_color = color
		_material.emission = color


func set_highlight(on: bool) -> void:
	_highlighted = on


## The glow eases toward its target instead of snapping, with a gentle pulse while aimed at.
func _process(delta: float) -> void:
	if _material == null:
		return
	_pulse_time += delta
	var target := GLOW_IDLE
	if _highlighted:
		target = GLOW_HIGHLIGHT + 0.25 * sin(_pulse_time * 6.0)
	var current := _material.emission_energy_multiplier
	_material.emission_energy_multiplier = lerpf(current, target, clampf(delta * GLOW_EASE_SPEED, 0.0, 1.0))


## A short press animation: the box pushes in and springs back.
func play_press() -> void:
	if _mesh == null:
		return
	var rest := _mesh.position
	var tween := create_tween()
	tween.tween_property(_mesh, "position", rest + Vector3(0.0, 0.0, PRESS_DEPTH), PRESS_SECONDS * 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(_mesh, "position", rest, PRESS_SECONDS * 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func interact(player: Node) -> void:
	if enabled:
		interacted.emit(self, player)
