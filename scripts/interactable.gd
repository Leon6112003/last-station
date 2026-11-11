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

const GLOW_IDLE := 0.3
const GLOW_HIGHLIGHT := 1.6


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
	if _material:
		_material.emission_energy_multiplier = GLOW_HIGHLIGHT if on else GLOW_IDLE


func interact(player: Node) -> void:
	if enabled:
		interacted.emit(self, player)
