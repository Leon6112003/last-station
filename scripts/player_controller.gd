class_name PlayerController
extends CharacterBody3D
## First-person controller. Builds its own collider, camera and interaction ray.
## Movement and look only work while input_enabled is true.

signal target_changed(target: Interactable)
signal first_move
signal woke_up   ## the wake-up sequence has finished and the player has control
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
## The wake-up sequence: the player lies in the bunk looking up, blinks awake, sits up,
## turns toward the room and stands. Movement, looking and interacting are locked until it
## ends (any key press skips it after a few seconds).
var waking: bool = false
var wake_blink: float = 0.0            # 0 = eyes open, 1 = eyes shut (main.gd draws it as black)
var wake_bed_position: Vector3 = Vector3.INF   # where the eyes are while lying (world position)
var _wake_time: float = 0.0
var _wake_short: bool = false
var _lying_local: Vector3 = Vector3.ZERO   # where the eyes are while lying, relative to the body (facing north)
var _camera_base_y: float = 0.0
var third_person: bool = false
var zero_g: bool = false      # set by a failed gravity zone while the player is inside it
var front_view: bool = false   # third person only: the camera is in front, looking back at the face
var _avatar: Node3D
var _legs: Array[Node3D] = []
var _arms: Array[Node3D] = []

# Third person: a camera directly behind and a little above the avatar, so the reticle,
# the body and the walking direction are all on one line.
const THIRD_OFFSET := Vector3(0.0, 0.6, 2.7)   # right, up, back from the eye (before pitch)
const FRONT_OFFSET := Vector3(0.0, 0.15, -2.6)  # the front view: in front of the head, looking back at it
const THIRD_AIM_DISTANCE := 3.0                 # the camera turns to look at the point this far ahead of the eye
const CAMERA_WALL_MARGIN := 0.25                # keep the camera this far in front of a wall
const AVATAR_MIN_CAMERA_DISTANCE := 2.2   # closer than this and the body is hidden
const LEG_SWING := 0.6                          # radians
const BOB_HEIGHT := 0.03           # metres up and down while walking
const BOB_STRIDE := 3.2            # metres per full stride (two steps: left, then right)
const BOB_BLEND_SPEED := 8.0
const ZERO_G_SPEED_FACTOR := 0.5      # floating: half pace
const ZERO_G_RATE_FACTOR := 0.15      # and only a slow push to start or stop (you drift)
const ZERO_G_RISE_SPEED := 0.9        # m/s upward drift while weightless
const ZERO_G_MAX_CENTER_Y := 1.6      # the capsule centre stops rising here, below the 3 m ceiling
const ACCELERATION := 38.0         # m/s^2: speeding up to full pace takes about 0.13 s
const DECELERATION := 30.0         # m/s^2: and a short glide to a stop, instead of an instant halt
const WAKE_EYES_OPEN_AT := 0.7      # seconds: eyes start to open
const WAKE_EYES_OPEN_DONE := 1.7
const WAKE_BLINK_AT := 2.4          # a second, quick blink
const WAKE_SIT_START := 3.0
const WAKE_STAND_START := 4.6
const WAKE_TOTAL := 6.2
const WAKE_SKIP_AFTER := 2.0        # a key press skips the sequence after this many seconds
const WAKE_LYING_PITCH_DEGREES := 65.0
const WAKE_SITTING_PITCH_DEGREES := 15.0


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


## A classic astronaut, built from simple shapes: a bulky white pressure suit, a big round
## helmet with a gold reflective visor, a chest control box with hoses, flag and mission
## patches, grey cuffs and rings, thick gloves and chunky boots (no backpack). Drawn only
## in third person (no collision). Origin is the capsule centre; y values are metres up
## from the floor, and the figure is as tall as the player capsule (1.7 m).
func _build_avatar() -> void:
	_avatar = Node3D.new()
	_avatar.name = "Avatar"
	_avatar.position.y = -Rules.PLAYER_HEIGHT * 0.5
	add_child(_avatar)
	var suit := _avatar_material(Color8(238, 240, 247), 0.0)       # white pressure suit
	var grey := _avatar_material(Color8(160, 166, 182), 0.0)       # joints, cuffs, collar
	var dark_grey := _avatar_material(Color8(78, 84, 100), 0.0)    # control box, hoses, boots
	var helmet := _avatar_material(Color8(246, 247, 252), 0.0)
	var visor := _avatar_material(Color8(232, 170, 50), 0.4)       # gold reflective glass
	var visor_dark := _avatar_material(Color8(110, 70, 20), 0.0)   # the visor's darker lower edge
	var shine := _avatar_material(Color(1, 1, 1), 1.2)             # a reflection on the visor
	var red := _avatar_material(Color8(220, 50, 50), 0.4)
	var blue := _avatar_material(Color8(40, 80, 200), 0.3)
	var cyan := _avatar_material(Rules.COLOR_CYAN, 1.5)
	var gold := _avatar_material(Rules.COLOR_GOLD, 1.3)
	# A soft warm light travels with the figure so its colours read in the dim station.
	var glow := OmniLight3D.new()
	glow.position = Vector3(0.0, 2.4, 1.6)
	glow.light_color = Color(1.0, 0.95, 0.85)
	glow.light_energy = 1.1
	glow.omni_range = 4.0
	_avatar.add_child(glow)

	# Torso: a thick white suit with a belt ring, a chest control box with buttons and
	# hoses, a mission patch, and a plain panel on the back (no backpack).
	_avatar_shape(BoxMesh.new(), Vector3(0.0, 1.15, 0.0), Vector3(0.5, 0.6, 0.3), suit)
	_avatar_shape(BoxMesh.new(), Vector3(0.0, 0.88, 0.0), Vector3(0.52, 0.07, 0.32), grey)                       # belt ring
	_avatar_shape(BoxMesh.new(), Vector3(0.0, 1.27, -0.17), Vector3(0.28, 0.17, 0.06), dark_grey)                 # control box
	_avatar_shape(BoxMesh.new(), Vector3(0.0, 1.3, -0.205), Vector3(0.14, 0.05, 0.01), cyan)                      # its display
	for button_x in [-0.08, 0.0, 0.08]:
		var button: Material = [red, gold, blue][int(round(button_x / 0.08)) + 1]
		_avatar_shape(BoxMesh.new(), Vector3(button_x, 1.23, -0.205), Vector3(0.04, 0.03, 0.01), button)           # its buttons
	for side in [-1.0, 1.0]:
		_avatar_shape(CylinderMesh.new(), Vector3(side * 0.11, 1.02, -0.17), Vector3(0.035, 0.32, 0.035), dark_grey)   # hoses
	_avatar_shape(SphereMesh.new(), Vector3(0.15, 1.38, -0.17), Vector3(0.08, 0.08, 0.02), blue)                  # mission patch
	_avatar_shape(BoxMesh.new(), Vector3(0.0, 1.17, 0.17), Vector3(0.3, 0.36, 0.05), grey)                        # back panel
	_avatar_shape(BoxMesh.new(), Vector3(0.0, 1.2, 0.2), Vector3(0.1, 0.04, 0.02), cyan)                          # back status light
	# Collar ring and a big round helmet: a gold visor with a darker edge and a reflection.
	_avatar_shape(CylinderMesh.new(), Vector3(0.0, 1.44, 0.0), Vector3(0.24, 0.07, 0.24), grey)
	_avatar_shape(SphereMesh.new(), Vector3(0.0, 1.53, 0.0), Vector3(0.35, 0.34, 0.36), helmet)
	_avatar_shape(SphereMesh.new(), Vector3(0.0, 1.51, -0.1), Vector3(0.27, 0.21, 0.2), visor_dark)
	_avatar_shape(SphereMesh.new(), Vector3(0.0, 1.525, -0.105), Vector3(0.25, 0.19, 0.19), visor)
	_avatar_shape(SphereMesh.new(), Vector3(-0.06, 1.57, -0.2), Vector3(0.07, 0.035, 0.02), shine)
	# Arms (white, with a flag patch on the left shoulder) and legs (white, with knee rings).
	_avatar_shape(BoxMesh.new(), Vector3(-0.3, 1.31, -0.0), Vector3(0.02, 0.05, 0.09), red)
	_avatar_shape(BoxMesh.new(), Vector3(-0.3, 1.26, -0.0), Vector3(0.02, 0.03, 0.09), helmet)
	_avatar_shape(BoxMesh.new(), Vector3(-0.3, 1.22, -0.0), Vector3(0.02, 0.04, 0.09), blue)
	for side in [-1.0, 1.0]:
		_limb(Vector3(side * 0.32, 1.4, 0.0), 0.6, Vector3(0.15, 0.6, 0.15), suit, Vector3(0.15, 0.12, 0.16), grey, 0.0, _arms, grey, true)
		_limb(Vector3(side * 0.13, 0.9, 0.0), 0.8, Vector3(0.19, 0.8, 0.19), suit, Vector3(0.2, 0.14, 0.34), dark_grey, -0.07, _legs, grey, true)


## One limb: a capsule hanging from a pivot, with a box at the end (a glove or a boot,
## pushed forward by `cap_forward`) and optionally a trim: a band (sleeve) or a pad (knee). The pivot swings the limb.
func _limb(pivot_at: Vector3, length: float, size: Vector3, material: Material, cap_size: Vector3, cap_material: Material, cap_forward: float, group: Array[Node3D], trim_material: Material = null, trim_is_band: bool = false) -> void:
	var pivot := Node3D.new()
	pivot.position = pivot_at
	_avatar.add_child(pivot)
	var limb := _avatar_shape(CapsuleMesh.new(), Vector3(0.0, -length * 0.5, 0.0), size, material, pivot)
	limb.name = "Limb"
	_avatar_shape(BoxMesh.new(), Vector3(0.0, -length + cap_size.y * 0.3, cap_forward), cap_size, cap_material, pivot)
	if trim_material != null and trim_is_band:
		_avatar_shape(CylinderMesh.new(), Vector3(0.0, -length * 0.35, 0.0), Vector3(size.x * 1.06, 0.06, size.z * 1.06), trim_material, pivot)   # a band round the sleeve
	elif trim_material != null:
		_avatar_shape(BoxMesh.new(), Vector3(0.0, -length * 0.5, -size.z * 0.5), Vector3(size.x * 0.85, 0.13, 0.04), trim_material, pivot)        # a knee pad
	group.append(pivot)


func _avatar_material(color: Color, glow: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.85
	if glow > 0.0:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = glow
	return material


## Adds one part. `size` is its full width, height and depth; the stock meshes are made
## unit-sized and then scaled, so any shape can be squashed or stretched.
func _avatar_shape(mesh: Mesh, at: Vector3, size: Vector3, material: Material, parent: Node3D = null) -> MeshInstance3D:
	if mesh is SphereMesh:
		(mesh as SphereMesh).radius = 0.5
		(mesh as SphereMesh).height = 1.0
	elif mesh is CapsuleMesh:
		(mesh as CapsuleMesh).radius = 0.5
		(mesh as CapsuleMesh).height = 1.0
	elif mesh is CylinderMesh:
		(mesh as CylinderMesh).top_radius = 0.5
		(mesh as CylinderMesh).bottom_radius = 0.5
		(mesh as CylinderMesh).height = 1.0
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = at
	instance.scale = size
	(parent if parent != null else _avatar).add_child(instance)
	return instance


## Switches between first person (eye camera, body hidden) and third person
## (over-the-shoulder camera, body shown). Only the view changes; the body, its
## collider and the interaction reach are identical in both.
func set_third_person(enabled: bool, front: bool = false) -> void:
	third_person = enabled
	front_view = enabled and front
	_avatar.visible = enabled
	_ray.enabled = not front_view   # the front view looks back at the player, so nothing can be aimed at
	# The ray starts at the camera, so in third person it needs the extra distance
	# back to the eye; _update_target still rejects anything out of reach of the eye.
	var back := THIRD_OFFSET.length() if enabled else 0.0
	_ray.target_position = Vector3(0.0, 0.0, -(Rules.INTERACT_DISTANCE + back))
	_update_bob(0.0, 0.0)


## Starts waking up in bed. `full` = lie, blink, sit up, stand; otherwise (a retry or a later
## shift) the player starts sitting up. Body and collider never move; only the view does.
func play_wake_up(full: bool = true) -> void:
	waking = true
	_wake_short = not full
	_wake_time = 0.0 if full else WAKE_SIT_START
	rotation.y = 0.0   # lying with the head to the north
	_lying_local = Vector3(0.0, _camera_base_y, 0.0) + Vector3(-1.0, -0.8, -0.7)
	if wake_bed_position != Vector3.INF and is_inside_tree():
		_lying_local = wake_bed_position - global_position
	velocity = Vector3.ZERO
	_set_target(null)
	_avatar.visible = false
	_apply_wake()


## Ends the sequence now and gives control to the player, facing the bedroom door.
func skip_wake() -> void:
	if waking:
		_finish_wake()


func _finish_wake() -> void:
	waking = false
	wake_blink = 0.0
	_pitch = 0.0
	_camera.rotation.x = 0.0
	rotation.y = -PI   # facing south, toward the bedroom door
	set_third_person(third_person, front_view)
	_update_bob(0.0, 0.0)
	woke_up.emit()


func _advance_wake(delta: float) -> void:
	_wake_time += delta
	if _wake_time >= WAKE_TOTAL:
		_finish_wake()
	else:
		_apply_wake()


## Places the camera, pitch, yaw and eyelids for the current moment of the sequence.
func _apply_wake() -> void:
	var t := _wake_time
	var standing := Vector3(0.0, _camera_base_y, 0.0)
	var lying := _lying_local
	var sitting := standing + Vector3(-0.5, -0.5, -0.15)
	var sit := smoothstep(WAKE_SIT_START, WAKE_STAND_START, t)
	var stand := smoothstep(WAKE_STAND_START, WAKE_TOTAL, t)
	var place := lying.lerp(sitting, sit).lerp(standing, stand)
	# Gentle breathing while lying still.
	place.y += sin(t * 2.2) * 0.012 * (1.0 - sit)
	_camera.position = place
	_pitch = lerpf(lerpf(deg_to_rad(WAKE_LYING_PITCH_DEGREES), deg_to_rad(WAKE_SITTING_PITCH_DEGREES), sit), 0.0, stand)
	_camera.rotation.x = _pitch
	_camera.rotation.y = 0.0
	# Facing: head north in bed, turning east as they sit up, then south toward the door.
	rotation.y = lerpf(lerpf(0.0, -PI * 0.5, sit), -PI, stand)
	if _wake_short:
		wake_blink = clampf(1.0 - (t - WAKE_SIT_START) / 0.5, 0.0, 1.0)
	elif t < WAKE_EYES_OPEN_AT:
		wake_blink = 1.0
	elif t < WAKE_EYES_OPEN_DONE:
		wake_blink = 1.0 - smoothstep(WAKE_EYES_OPEN_AT, WAKE_EYES_OPEN_DONE, t)
	elif t < WAKE_BLINK_AT:
		wake_blink = 0.0
	elif t < WAKE_BLINK_AT + 0.15:
		wake_blink = (t - WAKE_BLINK_AT) / 0.15
	elif t < WAKE_BLINK_AT + 0.5:
		wake_blink = 1.0 - (t - WAKE_BLINK_AT - 0.15) / 0.35
	else:
		wake_blink = 0.0


func set_input_enabled(enabled: bool) -> void:
	input_enabled = enabled
	if not enabled:
		_set_target(null)


func _unhandled_input(event: InputEvent) -> void:
	if waking:
		# Everything is locked while waking; a key press skips the rest after a moment.
		if event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo and _wake_time >= WAKE_SKIP_AFTER:
			skip_wake()
		return
	if not input_enabled:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion := event as InputEventMouseMotion
		rotate_y(-motion.relative.x * mouse_sensitivity)
		var limit := deg_to_rad(Rules.MAX_PITCH_DEGREES)
		_pitch = clampf(_pitch - motion.relative.y * mouse_sensitivity, -limit, limit)
		_camera.rotation.x = _pitch - _third_person_tilt()   # same value the physics step uses, so no flicker
	elif event.is_action_pressed("interact") and _target != null:
		_target.interact(self)


func _physics_process(delta: float) -> void:
	if waking:
		_advance_wake(delta)
	var direction := Vector2.ZERO
	if input_enabled and not waking:
		direction = Input.get_vector("move_left", "move_right", "move_forward", "move_backward")

	var wish := transform.basis * Vector3(direction.x, 0.0, direction.y)
	# Ease towards the wanted velocity so starting and stopping feel smooth, not abrupt.
	var wanted := Vector2(wish.x, wish.z) * move_speed * (ZERO_G_SPEED_FACTOR if zero_g else 1.0)
	var horizontal := Vector2(velocity.x, velocity.z)
	var rate := ACCELERATION if wanted.length() > 0.01 else DECELERATION
	if zero_g:
		rate *= ZERO_G_RATE_FACTOR
	horizontal = horizontal.move_toward(wanted, rate * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.y
	if zero_g:
		# Weightless: drift gently upward instead of standing on the floor.
		var rise := ZERO_G_RISE_SPEED if position.y < ZERO_G_MAX_CENTER_Y else 0.0
		velocity.y = move_toward(velocity.y, rise, 3.0 * delta)
	elif not is_on_floor():
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
	if waking:
		return   # the wake-up sequence places the camera
	var swing := sin(_bob_phase * TAU) * _bob_amount
	for i in _legs.size():
		_legs[i].rotation.x = swing * LEG_SWING * (1.0 if i == 0 else -1.0)
	for i in _arms.size():
		_arms[i].rotation.x = swing * LEG_SWING * (-1.0 if i == 0 else 1.0)   # arms swing against the legs
	var eye := Vector3(0.0, _camera_base_y, 0.0)
	if front_view:
		# In front of the character, turned round to look back at the face.
		_camera.position = _third_person_position(eye, Basis(Vector3.RIGHT, -_pitch) * FRONT_OFFSET)
		_camera.rotation.y = PI
		_avatar.visible = _camera.position.distance_to(eye) > AVATAR_MIN_CAMERA_DISTANCE
	elif third_person:
		_camera.position = _third_person_position(eye, Basis(Vector3.RIGHT, _pitch) * THIRD_OFFSET)
		# Turn the camera a little toward the middle so the reticle (and the interaction
		# ray, which follows the camera) lands about where the character is facing.
		_camera.rotation.y = atan(THIRD_OFFSET.x / (THIRD_OFFSET.z + THIRD_AIM_DISTANCE))
		# The camera is above the eye, so tilt it down a little: the reticle then points where the eyes do.
		_camera.rotation.x = _pitch - _third_person_tilt()
		# With a wall right behind, the camera is squeezed close to the head: hide the
		# body then, so it does not fill the screen.
		_avatar.visible = _camera.position.distance_to(eye) > AVATAR_MIN_CAMERA_DISTANCE
	else:
		# The head dips at every foot landing (twice per stride), so the bob matches the steps.
		var dip := cos(_bob_phase * TAU * 2.0) * _bob_amount
		_camera.position = eye + Vector3(0.0, dip * BOB_HEIGHT, 0.0)
		_camera.rotation.y = 0.0


## How far the third-person camera is tilted down (it sits above the eye but aims where the eye does).
func _third_person_tilt() -> float:
	if third_person and not front_view:
		return atan(THIRD_OFFSET.y / (THIRD_OFFSET.z + THIRD_AIM_DISTANCE))
	return 0.0


## Camera spot for third person: behind and beside the head, turned by the pitch, and
## pulled in front of any wall between the head and that spot so it never clips.
func _third_person_position(eye_local: Vector3, offset: Vector3) -> Vector3:
	var wanted := eye_local + offset
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
