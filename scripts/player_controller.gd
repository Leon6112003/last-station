class_name PlayerController
extends CharacterBody3D
## First-person controller. Builds its own collider, camera and interaction ray.
## Movement and look only work while input_enabled is true.

signal target_changed(target: Interactable)
signal first_move
signal stepped  ## a footstep landed (for the sound effect)

@export var move_speed: float = Rules.PLAYER_SPEED
@export var mouse_sensitivity: float = Rules.MOUSE_SENSITIVITY
@export var gravity: float = Rules.PLAYER_GRAVITY

var input_enabled: bool = false

var _camera: Camera3D
var _ray: RayCast3D
var _pitch: float = 0.0
var _target: Interactable = null
var _has_moved: bool = false
var _bob_phase: float = 0.0
var _bob_amount: float = 0.0       # 0 standing still, 1 walking: smooths the bob in and out
var _wake_offset: float = 0.0      # the camera starts low and rises when a shift begins
var _camera_base_y: float = 0.0
var third_person: bool = false
var _avatar: Node3D
var _legs: Array[Node3D] = []
var _arms: Array[Node3D] = []

# Third person: an over-the-shoulder camera behind the avatar.
const THIRD_OFFSET := Vector3(0.7, 0.1, 2.7)   # right, up, back from the eye (before pitch)
const THIRD_AIM_DISTANCE := 3.0                 # the camera turns to look at the point this far ahead of the eye
const CAMERA_WALL_MARGIN := 0.25                # keep the camera this far in front of a wall
const AVATAR_MIN_CAMERA_DISTANCE := 2.2   # closer than this and the body is hidden
const LEG_SWING := 0.6                          # radians
const BOB_HEIGHT := 0.03           # metres up and down while walking
const BOB_STRIDE := 3.2            # metres per full stride (two steps: left, then right)
const BOB_BLEND_SPEED := 8.0
const WAKE_DEPTH := 0.95           # how far below eye height the camera starts
const WAKE_SECONDS := 2.4


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
	_camera_base_y = Rules.EYE_HEIGHT - Rules.PLAYER_HEIGHT * 0.5
	_camera.position = Vector3(0.0, _camera_base_y, 0.0)
	add_child(_camera)
	_camera.current = true

	_ray = RayCast3D.new()
	_ray.target_position = Vector3(0.0, 0.0, -Rules.INTERACT_DISTANCE)
	_ray.collision_mask = Rules.LAYER_WORLD | Rules.LAYER_INTERACT
	_ray.collide_with_areas = false
	_ray.collide_with_bodies = true
	_ray.enabled = true
	_camera.add_child(_ray)
	_build_avatar()
	set_third_person(false)


## A space station worker built from simple shapes: white helmet with a glowing visor,
## orange work suit with a chest panel, gloves and boots.
## Drawn only in third person (no collision). Origin is the capsule centre; y values are
## measured up from the floor. The figure is as tall as the player capsule.
func _build_avatar() -> void:
	_avatar = Node3D.new()
	_avatar.name = "Avatar"
	_avatar.position.y = -Rules.PLAYER_HEIGHT * 0.5
	add_child(_avatar)
	var u := Rules.PLAYER_HEIGHT / 5.0   # one unit; the figure is 5 units tall
	var suit := _avatar_material(Color8(236, 112, 34), 0.0)     # work-suit orange
	var helmet := _avatar_material(Color8(236, 238, 245), 0.0)  # white helmet
	var visor := _avatar_material(Rules.COLOR_CYAN, 1.3)
	var dark := _avatar_material(Color8(38, 40, 52), 0.0)       # gloves and boots
	var stripe := _avatar_material(Rules.COLOR_GOLD, 0.5)       # reflective trim
	# A soft warm light travels with the figure so its colours read in the dim station.
	var glow := OmniLight3D.new()
	glow.position = Vector3(0.0, 2.4, 1.6)
	glow.light_color = Color(1.0, 0.95, 0.85)
	glow.light_energy = 1.1
	glow.omni_range = 4.0
	_avatar.add_child(glow)

	# Torso with a chest panel and a belt stripe.
	_avatar_box(Vector3(1.5 * u, 2.0 * u, 0.85 * u), Vector3(0.0, 3.0 * u, 0.0), suit)
	_avatar_box(Vector3(0.6 * u, 0.4 * u, 0.06 * u), Vector3(0.0, 3.45 * u, -0.45 * u), visor)   # chest panel
	_avatar_box(Vector3(1.56 * u, 0.12 * u, 0.9 * u), Vector3(0.0, 2.25 * u, 0.0), stripe)       # belt
	# Helmet: a white sphere with a glowing visor on the front (-Z).
	var dome := SphereMesh.new()
	dome.radius = 0.68 * u
	dome.height = 1.36 * u
	_avatar_part(dome, Vector3(0.0, 4.5 * u, 0.0), helmet)
	_avatar_box(Vector3(0.9 * u, 0.46 * u, 0.12 * u), Vector3(0.0, 4.52 * u, -0.57 * u), visor)
	_avatar_box(Vector3(0.5 * u, 0.2 * u, 0.5 * u), Vector3(0.0, 4.0 * u, 0.0), helmet)         # collar
	# Arms (suit, glove at the end) and legs (suit, boot at the end) hang from pivots.
	for side in [-1.0, 1.0]:
		_limb(Vector3(side * 1.05 * u, 4.0 * u, 0.0), 2.0 * u, 0.58 * u, suit, dark, _arms)
		_limb(Vector3(side * 0.38 * u, 2.0 * u, 0.0), 2.0 * u, 0.7 * u, suit, dark, _legs)


## One limb: a box hanging from a pivot, with a dark cap (glove or boot) at the end and a
## reflective band above it.
func _limb(pivot_at: Vector3, length: float, width: float, material: Material, cap_material: Material, group: Array[Node3D]) -> void:
	var pivot := Node3D.new()
	pivot.position = pivot_at
	_avatar.add_child(pivot)
	var segment := BoxMesh.new()
	segment.size = Vector3(width, length, width)
	var segment_mesh := MeshInstance3D.new()
	segment_mesh.mesh = segment
	segment_mesh.material_override = material
	segment_mesh.position.y = -length * 0.5
	pivot.add_child(segment_mesh)
	var cap := BoxMesh.new()
	cap.size = Vector3(width + 0.03, length * 0.22, width + 0.03)
	var cap_mesh := MeshInstance3D.new()
	cap_mesh.mesh = cap
	cap_mesh.material_override = cap_material
	cap_mesh.position.y = -length + cap.size.y * 0.5
	pivot.add_child(cap_mesh)
	group.append(pivot)


func _avatar_box(size: Vector3, at: Vector3, material: Material) -> void:
	var box := BoxMesh.new()
	box.size = size
	_avatar_part(box, at, material)


func _avatar_material(color: Color, glow: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.8
	if glow > 0.0:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = glow
	return material


func _avatar_part(mesh: Mesh, at: Vector3, material: Material) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = at
	_avatar.add_child(instance)
	return instance


## Switches between first person (eye camera, body hidden) and third person
## (over-the-shoulder camera, body shown). Only the view changes; the body, its
## collider and the interaction reach are identical in both.
func set_third_person(enabled: bool) -> void:
	third_person = enabled
	_avatar.visible = enabled
	# The ray starts at the camera, so in third person it needs the extra distance
	# back to the eye; _update_target still rejects anything out of reach of the eye.
	var back := THIRD_OFFSET.length() if enabled else 0.0
	_ray.target_position = Vector3(0.0, 0.0, -(Rules.INTERACT_DISTANCE + back))
	_update_bob(0.0, 0.0)


## The camera rises from a low start to eye height, like waking up.
func play_wake_up() -> void:
	_wake_offset = -WAKE_DEPTH
	var tween := create_tween()
	tween.tween_property(self, "_wake_offset", 0.0, WAKE_SECONDS).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


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

	_update_bob(delta, Vector2(velocity.x, velocity.z).length())
	_update_target()


## Head bob while walking, plus a footstep every BOB_STRIDE metres. Camera only: the
## body, the collider and the interaction ray's origin on the floor never move.
func _update_bob(delta: float, horizontal_speed: float) -> void:
	var walking := horizontal_speed > 0.5 and is_on_floor()
	_bob_amount = move_toward(_bob_amount, 1.0 if walking else 0.0, BOB_BLEND_SPEED * delta)
	if walking:
		# One phase unit is one full stride. A foot lands when the legs are at their
		# widest (phase 0.25 and 0.75), so the sound is sent exactly then.
		var previous_step := floorf(_bob_phase * 2.0 - 0.5)
		_bob_phase += horizontal_speed * delta / BOB_STRIDE
		if floorf(_bob_phase * 2.0 - 0.5) > previous_step:
			stepped.emit()
	var swing := sin(_bob_phase * TAU) * _bob_amount
	for i in _legs.size():
		_legs[i].rotation.x = swing * LEG_SWING * (1.0 if i == 0 else -1.0)
	for i in _arms.size():
		_arms[i].rotation.x = swing * LEG_SWING * (-1.0 if i == 0 else 1.0)   # arms swing against the legs
	var eye := Vector3(0.0, _camera_base_y + _wake_offset, 0.0)
	if third_person:
		_camera.position = _third_person_position(eye)
		# Turn the camera a little toward the middle so the reticle (and the interaction
		# ray, which follows the camera) lands about where the character is facing.
		_camera.rotation.y = atan(THIRD_OFFSET.x / (THIRD_OFFSET.z + THIRD_AIM_DISTANCE))
		# With a wall right behind, the camera is squeezed close to the head: hide the
		# body then, so it does not fill the screen.
		_avatar.visible = _camera.position.distance_to(eye) > AVATAR_MIN_CAMERA_DISTANCE
	else:
		# The head dips at every foot landing (twice per stride), so the bob matches the steps.
		var dip := cos(_bob_phase * TAU * 2.0) * _bob_amount
		_camera.position = eye + Vector3(0.0, dip * BOB_HEIGHT, 0.0)
		_camera.rotation.y = 0.0


## Camera spot for third person: behind and beside the head, turned by the pitch, and
## pulled in front of any wall between the head and that spot so it never clips.
func _third_person_position(eye_local: Vector3) -> Vector3:
	var wanted := eye_local + Basis(Vector3.RIGHT, _pitch) * THIRD_OFFSET
	if not is_inside_tree():
		return wanted
	var space := get_world_3d().direct_space_state
	var from := to_global(eye_local)
	var query := PhysicsRayQueryParameters3D.create(from, to_global(wanted), Rules.LAYER_WORLD)
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return wanted
	var hit_point: Vector3 = hit["position"]
	var toward_head := (from - hit_point).normalized()
	return to_local(hit_point + toward_head * CAMERA_WALL_MARGIN)


func reset_first_move() -> void:
	_has_moved = false


func _update_target() -> void:
	var found: Interactable = null
	if input_enabled and _ray.is_colliding():
		var hit := _ray.get_collider()
		var eye_distance := _ray.get_collision_point().distance_to(to_global(Vector3(0.0, _camera_base_y, 0.0)))
		if hit is Interactable and (hit as Interactable).enabled and eye_distance <= Rules.INTERACT_DISTANCE + 0.2:
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
