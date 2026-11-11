class_name PlayerController
extends CharacterBody3D
## First-person controller. Builds its own collider, camera and interaction ray.
## Movement and look only work while input_enabled is true.

signal target_changed(target: Interactable)
signal first_move

@export var move_speed: float = Rules.PLAYER_SPEED
@export var mouse_sensitivity: float = Rules.MOUSE_SENSITIVITY
@export var gravity: float = Rules.PLAYER_GRAVITY

var input_enabled: bool = false

var _camera: Camera3D
var _ray: RayCast3D
var _pitch: float = 0.0
var _target: Interactable = null
var _has_moved: bool = false


func _ready() -> void:
	collision_layer = Rules.LAYER_PLAYER
	collision_mask = Rules.LAYER_WORLD

	var capsule := CapsuleShape3D.new()
	capsule.radius = Rules.PLAYER_RADIUS
	capsule.height = Rules.PLAYER_HEIGHT
	var collider := CollisionShape3D.new()
	collider.shape = capsule
	add_child(collider)

	# The body origin is the capsule centre, so the eye sits this far above it.
	_camera = Camera3D.new()
	_camera.position = Vector3(0.0, Rules.EYE_HEIGHT - Rules.PLAYER_HEIGHT * 0.5, 0.0)
	add_child(_camera)
	_camera.current = true

	_ray = RayCast3D.new()
	_ray.target_position = Vector3(0.0, 0.0, -Rules.INTERACT_DISTANCE)
	_ray.collision_mask = Rules.LAYER_WORLD | Rules.LAYER_INTERACT
	_ray.collide_with_areas = false
	_ray.collide_with_bodies = true
	_ray.enabled = true
	_camera.add_child(_ray)


func set_input_enabled(enabled: bool) -> void:
	input_enabled = enabled
	if not enabled:
		_set_target(null)


func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion := event as InputEventMouseMotion
		rotate_y(-motion.relative.x * mouse_sensitivity)
		var limit := deg_to_rad(Rules.MAX_PITCH_DEGREES)
		_pitch = clampf(_pitch - motion.relative.y * mouse_sensitivity, -limit, limit)
		_camera.rotation.x = _pitch
	elif event.is_action_pressed("interact") and _target != null:
		_target.interact(self)


func _physics_process(delta: float) -> void:
	var direction := Vector2.ZERO
	if input_enabled:
		direction = Input.get_vector("move_left", "move_right", "move_forward", "move_backward")

	var wish := transform.basis * Vector3(direction.x, 0.0, direction.y)
	velocity.x = wish.x * move_speed
	velocity.z = wish.z * move_speed
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0.0
	move_and_slide()

	if direction.length() > 0.01 and not _has_moved:
		_has_moved = true
		first_move.emit()

	_update_target()


func reset_first_move() -> void:
	_has_moved = false


func _update_target() -> void:
	var found: Interactable = null
	if input_enabled and _ray.is_colliding():
		var hit := _ray.get_collider()
		if hit is Interactable and (hit as Interactable).enabled:
			found = hit as Interactable
	_set_target(found)


func _set_target(new_target: Interactable) -> void:
	if new_target == _target:
		return
	if is_instance_valid(_target):
		_target.set_highlight(false)
	_target = new_target
	if _target != null:
		_target.set_highlight(true)
	target_changed.emit(_target)
