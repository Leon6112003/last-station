class_name DoorGate
extends StaticBody3D
## A sliding door that stays locked until a system is repaired. The Oxygen room opens once
## Power is repaired, the Comms room once Oxygen is repaired. It only reads the repaired
## flags it is given; the rules live in GameManager.

const SLIDE_SECONDS := 0.9

var requires: String = ""
var locked: bool = true

var _slab: MeshInstance3D
var _label: Label3D
var _material: StandardMaterial3D
var _height: float = 2.3
var _label_locked: String = ""


## `door_size` is the doorway (width, height, thickness). `needs` is the system to repair first.
static func create(door_size: Vector3, needs: String, at: Vector3, label_text: String) -> DoorGate:
	var gate := DoorGate.new()
	gate.name = "Door_%s" % needs
	gate.requires = needs
	gate.position = at
	gate._height = door_size.y
	gate._label_locked = label_text
	gate._build(door_size)
	return gate


func _build(door_size: Vector3) -> void:
	collision_layer = Rules.LAYER_WORLD
	collision_mask = 0
	_material = StandardMaterial3D.new()
	_material.albedo_color = Color(0.16, 0.17, 0.22)
	_material.emission_enabled = true
	_material.emission = Rules.COLOR_FAULT
	_material.emission_energy_multiplier = 0.25
	var box := BoxMesh.new()
	box.size = door_size
	_slab = MeshInstance3D.new()
	_slab.mesh = box
	_slab.material_override = _material
	add_child(_slab)
	var shape := BoxShape3D.new()
	shape.size = door_size
	var collider := CollisionShape3D.new()
	collider.shape = shape
	add_child(collider)

	# The notice on the corridor side of the door.
	_label = Label3D.new()
	_label.text = _label_locked
	_label.font_size = 30
	_label.pixel_size = 0.006
	_label.modulate = Rules.COLOR_FAULT
	_label.outline_size = 8
	_label.position = Vector3(0.0, 0.0, door_size.z * 0.5 + 0.02)
	add_child(_label)


## Opens the door if the system it needs has been repaired.
func refresh(repaired: Dictionary) -> void:
	if locked and bool(repaired.get(requires, false)):
		unlock()


func unlock() -> void:
	if not locked:
		return
	locked = false
	collision_layer = 0   # walkable straight away; the slab slides up out of the way
	_material.emission = Rules.COLOR_CYAN
	_label.text = "OPEN"
	_label.modulate = Rules.COLOR_CYAN
	if is_inside_tree():
		var tween := create_tween()
		tween.tween_property(_slab, "position:y", _height + 0.1, SLIDE_SECONDS).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tween.parallel().tween_property(_label, "position:y", _height + 0.1, SLIDE_SECONDS)
	else:
		_slab.position.y = _height + 0.1
