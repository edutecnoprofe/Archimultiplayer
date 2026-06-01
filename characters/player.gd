extends CharacterBody3D

const SPEED      := 5.0
const BACK_SPEED := 3.5
const JUMP_VEL   := 5.0
const GRAVITY    := 9.8
const ROT_SPEED  := 2.2
const CAM_SENS   := 0.003
const CAM_MIN_X  := -0.6
const CAM_MAX_X  :=  0.3

# --- Propiedades sincronizadas ---
var player_name   : String = "Jugador"
var avatar_gender : String = "male"
var anim_state    : String = "Happy Idle"

var _is_local      : bool            = false
var _anim_player   : AnimationPlayer = null
var _on_climbzone  : bool            = false


func _ready() -> void:
	var id := str(name).to_int()
	set_multiplayer_authority(id)
	_is_local = (multiplayer.get_unique_id() == id)

	$SpringArm3D/Camera3D.current = _is_local

	if _is_local:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

	_load_avatar()
	$NameLabel.text = player_name

	# Sincronizador: solo la autoridad envía; los demás reciben
	$MultiplayerSynchronizer.set_multiplayer_authority(id)


func _load_avatar() -> void:
	for c in $AvatarRoot.get_children():
		c.queue_free()
	var fname := "Male" if avatar_gender == "male" else "Female"
	var scene : PackedScene = load("res://Assets/" + fname + ".glb")
	if not scene:
		push_error("Avatar no encontrado: " + fname)
		return
	var inst := scene.instantiate()
	$AvatarRoot.add_child(inst)
	_anim_player = inst.find_child("AnimationPlayer", true, false)
	if _anim_player:
		_anim_player.play("Happy Idle")


func _physics_process(delta: float) -> void:
	if _is_local:
		_handle_local(delta)
	else:
		_apply_remote_anim()


func _handle_local(delta: float) -> void:
	# Gravedad
	if not is_on_floor():
		velocity.y -= GRAVITY * delta

	# Rotación (A/D)
	if Input.is_action_pressed("move_left"):
		rotate_y(ROT_SPEED * delta)
	if Input.is_action_pressed("move_right"):
		rotate_y(-ROT_SPEED * delta)

	# Traslación (W/S)
	var fwd   := -global_transform.basis.z
	var speed := 0.0
	if Input.is_action_pressed("move_forward"):
		speed = SPEED
	elif Input.is_action_pressed("move_back"):
		speed = -BACK_SPEED

	velocity.x = fwd.x * speed
	velocity.z = fwd.z * speed

	# Salto
	if Input.is_action_just_pressed("ui_accept") and is_on_floor():
		velocity.y = JUMP_VEL

	move_and_slide()
	_update_local_anim()


func _update_local_anim() -> void:
	var fwd_p  := Input.is_action_pressed("move_forward")
	var back_p := Input.is_action_pressed("move_back")
	var left_p := Input.is_action_pressed("move_left")
	var right_p:= Input.is_action_pressed("move_right")
	var air    := not is_on_floor()

	var next : String
	if air and velocity.y > 0.2:
		next = "Jump"
	elif _on_climbzone and fwd_p:
		next = "Climbing Up Wall"
	elif fwd_p:
		next = "Walking"
	elif back_p:
		next = "Walking Backwards"
	elif left_p:
		next = "Left Turn"
	elif right_p:
		next = "Right Turn"
	else:
		next = "Happy Idle"

	_set_anim(next)


func _set_anim(anim: String) -> void:
	if anim_state == anim:
		return
	anim_state = anim
	if _anim_player and _anim_player.has_animation(anim):
		_anim_player.play(anim, 0.2)


func _apply_remote_anim() -> void:
	if _anim_player == null:
		return
	if _anim_player.current_animation != anim_state:
		if _anim_player.has_animation(anim_state):
			_anim_player.play(anim_state, 0.2)


func _unhandled_input(event: InputEvent) -> void:
	if not _is_local:
		return
	if event is InputEventMouseMotion:
		$SpringArm3D.rotation.y -= event.relative.x * CAM_SENS
		$SpringArm3D.rotation.x -= event.relative.y * CAM_SENS
		$SpringArm3D.rotation.x  = clamp($SpringArm3D.rotation.x, CAM_MIN_X, CAM_MAX_X)
	elif event.is_action_pressed("ui_cancel"):
		var mode := Input.get_mouse_mode()
		Input.set_mouse_mode(
			Input.MOUSE_MODE_VISIBLE if mode == Input.MOUSE_MODE_CAPTURED
			else Input.MOUSE_MODE_CAPTURED
		)


func set_climb_zone(active: bool) -> void:
	_on_climbzone = active


func _notification(what: int) -> void:
	if what == NOTIFICATION_EXIT_TREE and _is_local:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
