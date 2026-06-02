extends CharacterBody3D

const SPEED      := 5.0
const BACK_SPEED := 3.5
const JUMP_VEL   := 5.0
const GRAVITY    := 9.8
const ROT_LERP   := 12.0  # qué tan rápido el cuerpo se alinea con la cámara
const CAM_SENS   := 0.003
const CAM_MIN_X  := -0.6
const CAM_MAX_X  :=  0.3
const CAM_MIN_DIST := 0.3  # distancia mínima (primera persona)
const CAM_MAX_DIST := 8.0  # distancia máxima
const CAM_DEFAULT_DIST := 3.5
const CAM_SCROLL_SPEED := 0.5

const LOOPED_ANIMS := [
	"Happy Idle", "Walking", "Walking Backwards",
	"Left Turn", "Right Turn", "Climbing Up Wall",
]

# Yaw mundial de la cámara (independiente del player)
var _cam_yaw : float = 0.0

# --- Propiedades sincronizadas ---
var player_name   : String = "Jugador"
var avatar_gender : String = "male"
var anim_state    : String = "Happy Idle"

var _is_local      : bool            = false
var _anim_player   : AnimationPlayer = null
var _on_climbzone  : bool            = false
var _climbing      : bool            = false
var _near_climb    : bool            = false
var _hud_ref       : Node            = null
var _climb_normal  : Vector3         = Vector3.ZERO  # normal pared (apunta hacia el aire)
var _cam_distance  : float           = CAM_DEFAULT_DIST


func _ready() -> void:
	var id := str(name).to_int()
	set_multiplayer_authority(id)
	var my_id := 1 if multiplayer.multiplayer_peer == null else multiplayer.get_unique_id()
	_is_local = (my_id == id)

	$SpringArm3D/Camera3D.current = _is_local
	$SpringArm3D.add_excluded_object(get_rid())
	_cam_yaw = rotation.y

	if _is_local:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

	_load_avatar()
	$NameLabel.text = player_name
	$SpringArm3D.spring_length = _cam_distance

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
		_strip_root_motion()
		_force_loop_anims()
		_anim_player.play("Happy Idle")


func _force_loop_anims() -> void:
	for anim_name in _anim_player.get_animation_list():
		if anim_name in LOOPED_ANIMS:
			var a := _anim_player.get_animation(anim_name)
			if a != null:
				a.loop_mode = Animation.LOOP_LINEAR


func _strip_root_motion() -> void:
	# Desactiva tracks de posición del hueso raíz (Hips de Mixamo) para que
	# el desplazamiento lo controle la física y no la animación.
	for anim_name in _anim_player.get_animation_list():
		var a := _anim_player.get_animation(anim_name)
		if a == null:
			continue
		for i in a.get_track_count():
			if a.track_get_type(i) != Animation.TYPE_POSITION_3D:
				continue
			var path_str := str(a.track_get_path(i)).to_lower()
			if "hips" in path_str or "hip" in path_str or "root" in path_str:
				a.track_set_enabled(i, false)


func _physics_process(delta: float) -> void:
	if _is_local:
		_handle_local(delta)
		# Mantener yaw del SpringArm en espacio mundo, independiente del player
		$SpringArm3D.rotation.y = _cam_yaw - rotation.y
	else:
		_apply_remote_anim()


func _handle_local(delta: float) -> void:
	# Detección climbing
	_update_climb_prompt()
	if _climbing:
		_handle_climbing(delta)
		return
	if Input.is_action_just_pressed("climb") and _near_climb:
		_start_climbing()
		return

	# Gravedad
	if not is_on_floor():
		velocity.y -= GRAVITY * delta

	# Input
	var inp_fwd   := Input.get_action_strength("move_back") - Input.get_action_strength("move_forward")
	var inp_right := Input.get_action_strength("move_right") - Input.get_action_strength("move_left")

	# Direcciones cámara en plano XZ (yaw mundial)
	var cam_fwd   := Vector3(-sin(_cam_yaw), 0, -cos(_cam_yaw))
	var cam_right := Vector3( cos(_cam_yaw), 0, -sin(_cam_yaw))

	var move_dir := cam_fwd * -inp_fwd + cam_right * inp_right
	var has_move := move_dir.length() > 0.01
	if has_move:
		move_dir = move_dir.normalized()

	# Velocidad horizontal (back algo más lento solo si va atrás puro)
	var spd := SPEED
	if inp_fwd > 0.0 and abs(inp_right) < 0.01:
		spd = BACK_SPEED
	velocity.x = move_dir.x * spd
	velocity.z = move_dir.z * spd

	# Rotar cuerpo hacia la dirección de movimiento (asumiendo avatar mira +Z)
	if has_move:
		var target_yaw := atan2(move_dir.x, move_dir.z)
		rotation.y = lerp_angle(rotation.y, target_yaw, clamp(ROT_LERP * delta, 0.0, 1.0))

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
	elif fwd_p or left_p or right_p:
		next = "Walking"
	elif back_p:
		next = "Walking Backwards"
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
	if not is_inside_tree() or not _is_local:
		return
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		_cam_yaw -= event.relative.x * CAM_SENS
		$SpringArm3D.rotation.x -= event.relative.y * CAM_SENS
		$SpringArm3D.rotation.x  = clamp($SpringArm3D.rotation.x, CAM_MIN_X, CAM_MAX_X)
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_cam_distance = clamp(_cam_distance - CAM_SCROLL_SPEED, CAM_MIN_DIST, CAM_MAX_DIST)
			$SpringArm3D.spring_length = _cam_distance
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_cam_distance = clamp(_cam_distance + CAM_SCROLL_SPEED, CAM_MIN_DIST, CAM_MAX_DIST)
			$SpringArm3D.spring_length = _cam_distance
	elif event.is_action_pressed("ui_cancel"):
		var mode := Input.get_mouse_mode()
		Input.set_mouse_mode(
			Input.MOUSE_MODE_VISIBLE if mode == Input.MOUSE_MODE_CAPTURED
			else Input.MOUSE_MODE_CAPTURED
		)


func set_climb_zone(active: bool) -> void:
	_on_climbzone = active


func _handle_climbing(delta: float) -> void:
	# Verificar que sigue habiendo superficie escalable delante (margen vertical
	# para asomarse por arriba y por abajo)
	if not _has_climb_surface():
		_stop_climbing()
		return

	var up_in   := Input.get_action_strength("move_forward") - Input.get_action_strength("move_back")
	var side_in := Input.get_action_strength("move_right")   - Input.get_action_strength("move_left")

	# Vertical
	velocity = Vector3.ZERO
	velocity.y = up_in * 2.5

	# Lateral: proyectar cam_right sobre el plano de la pared (perpendicular a normal)
	var cam_right := Vector3(cos(_cam_yaw), 0, -sin(_cam_yaw))
	var lateral := cam_right - _climb_normal * cam_right.dot(_climb_normal)
	if lateral.length() > 0.001:
		lateral = lateral.normalized()
	velocity += lateral * side_in * 1.8

	# Empuje constante hacia la pared (el collider la frena → queda pegado)
	velocity += -_climb_normal * 1.8

	move_and_slide()
	_set_anim("Climbing Up Wall")

	if Input.is_action_just_pressed("ui_accept"):
		_stop_climbing()


func _start_climbing() -> void:
	# Raycast hacia delante para obtener la normal real de la cara
	var space := get_world_3d().direct_space_state
	var origin := global_position + Vector3(0, 1.0, 0)
	var fwd := Vector3(sin(rotation.y), 0, cos(rotation.y)).normalized()
	var params := PhysicsRayQueryParameters3D.create(origin, origin + fwd * 1.5)
	params.exclude = [get_rid()]
	var hit := space.intersect_ray(params)
	if hit.is_empty():
		return
	var col = hit.get("collider")
	if col == null or not (col.get_parent() is MeshInstance3D):
		return
	var lvl := get_tree().current_scene
	if lvl == null or not lvl.has_method("is_climbable") or not lvl.is_climbable(col.get_parent()):
		return

	var nrm: Vector3 = hit.get("normal", Vector3.ZERO)
	nrm.y = 0.0
	if nrm.length() < 0.01:
		return  # techos/suelos no son climbables aquí
	_climb_normal = nrm.normalized()
	# Alinear cuerpo: avatar mira -normal (de cara a la pared). +Z basis = -normal.
	rotation.y = atan2(-_climb_normal.x, -_climb_normal.z)
	_climbing = true
	velocity = Vector3.ZERO


func _stop_climbing() -> void:
	_climbing = false
	_climb_normal = Vector3.ZERO
	velocity = Vector3.ZERO
	velocity.y = JUMP_VEL  # salto completo al soltarse


func _has_climb_surface() -> bool:
	# Tres rayos hacia la pared (chest, head, waist) para dar margen al asomarse.
	var lvl := get_tree().current_scene
	if lvl == null or not lvl.has_method("is_climbable") or _climb_normal == Vector3.ZERO:
		return false
	var space := get_world_3d().direct_space_state
	var into_wall := -_climb_normal
	var ys := [0.4, 1.0, 1.6]
	for y in ys:
		var origin: Vector3 = global_position + Vector3(0, y, 0)
		var params := PhysicsRayQueryParameters3D.create(origin, origin + into_wall * 1.3)
		params.exclude = [get_rid()]
		var hit := space.intersect_ray(params)
		if hit.is_empty():
			continue
		var col = hit.get("collider")
		if col != null and col.get_parent() is MeshInstance3D and lvl.is_climbable(col.get_parent()):
			return true
	return false


func _update_climb_prompt() -> void:
	var near := _is_facing_climbable()
	if near != _near_climb:
		_near_climb = near
		_set_hud_prompt(near and not _climbing)


func _is_facing_climbable() -> bool:
	var lvl := get_tree().current_scene
	if lvl == null or not lvl.has_method("is_climbable"):
		return false
	var space := get_world_3d().direct_space_state
	var origin := global_position + Vector3(0, 1.0, 0)
	var fwd := Vector3(sin(rotation.y), 0, cos(rotation.y)).normalized()
	var params := PhysicsRayQueryParameters3D.create(origin, origin + fwd * 1.2)
	params.exclude = [get_rid()]
	var hit := space.intersect_ray(params)
	if hit.is_empty():
		return false
	var col = hit.get("collider")
	if col == null or not (col.get_parent() is MeshInstance3D):
		return false
	return lvl.is_climbable(col.get_parent())


func _set_hud_prompt(on: bool) -> void:
	if _hud_ref == null:
		var lvl := get_tree().current_scene
		if lvl != null:
			_hud_ref = lvl.get_node_or_null("HUD")
			if _hud_ref == null:
				# HUD se añade dinámicamente como hijo del nivel; busca por tipo
				for c in lvl.get_children():
					if c.has_method("show_climb_prompt"):
						_hud_ref = c
						break
	if _hud_ref != null and _hud_ref.has_method("show_climb_prompt"):
		_hud_ref.show_climb_prompt(on)


func _notification(what: int) -> void:
	if what == NOTIFICATION_EXIT_TREE and _is_local:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
