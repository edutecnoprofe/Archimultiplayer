extends Node3D

const PLAYER_SCENE := preload("res://characters/player.tscn")

# Posiciones de spawn (altura amplia para caer sobre cualquier modelo)
const SPAWN_HEIGHT := 2.0
const SPAWN_POINTS := [
	Vector3( 0, SPAWN_HEIGHT,  0),
	Vector3( 1.5, SPAWN_HEIGHT,  0),
	Vector3(-1.5, SPAWN_HEIGHT,  0),
	Vector3( 0, SPAWN_HEIGHT,  1.5),
	Vector3( 1.5, SPAWN_HEIGHT,  1.5),
	Vector3(-1.5, SPAWN_HEIGHT,  1.5),
]

# Casa cargada (offset al lado del jugador para tener referencia de tamaño)
const HOUSE_OFFSET := Vector3(4, 0, 0)

var _house: Node3D = null

# Sistema de selección de superficies escalables
var _climbable_meshes : Dictionary = {}  # MeshInstance3D -> true
var _hovered_mesh     : MeshInstance3D = null
var _hover_mat        : StandardMaterial3D
var _climb_mat        : StandardMaterial3D


func _ready() -> void:
	NetworkManager.player_disconnected.connect(_on_player_disconnected)

	_ensure_environment()
	_build_highlight_materials()
	_add_perimeter_walls()
	_load_house()

	var is_authority := multiplayer.multiplayer_peer == null or multiplayer.is_server()
	if is_authority:
		NetworkManager.player_connected.connect(_on_player_connected_server)
		for id in NetworkManager.players:
			_spawn_player(id)
	else:
		NetworkManager.server_disconnected.connect(_on_server_dropped)

	var hud_scene : PackedScene = load("res://ui/hud.tscn")
	var hud := hud_scene.instantiate()
	add_child(hud)


func _build_highlight_materials() -> void:
	_hover_mat = StandardMaterial3D.new()
	_hover_mat.albedo_color = Color(0.70, 0.35, 1.0, 0.45)
	_hover_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_hover_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_hover_mat.cull_mode    = BaseMaterial3D.CULL_DISABLED
	_hover_mat.render_priority = 1
	_climb_mat = StandardMaterial3D.new()
	_climb_mat.albedo_color = Color(0.35, 1.0, 0.45, 0.35)
	_climb_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_climb_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_climb_mat.cull_mode    = BaseMaterial3D.CULL_DISABLED
	_climb_mat.render_priority = 1


func _process(_delta: float) -> void:
	var is_authority := multiplayer.multiplayer_peer == null or multiplayer.is_server()
	if not is_authority or _house == null:
		_clear_all_overlays()
		return
	if Input.get_mouse_mode() == Input.MOUSE_MODE_VISIBLE:
		_update_hover_from_cursor()
	else:
		_clear_all_overlays()


func _update_hover_from_cursor() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var mp := get_viewport().get_mouse_position()
	var from := cam.project_ray_origin(mp)
	var to := from + cam.project_ray_normal(mp) * 200.0
	var space := get_world_3d().direct_space_state
	var params := PhysicsRayQueryParameters3D.create(from, to)
	var hit := space.intersect_ray(params)
	var found: MeshInstance3D = null
	if not hit.is_empty():
		var col = hit.get("collider")
		if col != null and col.get_parent() is MeshInstance3D:
			found = col.get_parent()
	_set_hover(found)


func _set_hover(mesh: MeshInstance3D) -> void:
	if mesh == _hovered_mesh:
		return
	if _hovered_mesh != null and not _climbable_meshes.has(_hovered_mesh):
		_hovered_mesh.material_overlay = null
	_hovered_mesh = mesh
	_refresh_overlays()


func _clear_all_overlays() -> void:
	# En modo juego: ningún overlay visible.
	for m in _climbable_meshes.keys():
		if is_instance_valid(m):
			m.material_overlay = null
	if _hovered_mesh != null and is_instance_valid(_hovered_mesh):
		_hovered_mesh.material_overlay = null
	_hovered_mesh = null


func _refresh_overlays() -> void:
	# Solo se llama en modo edición (mouse visible).
	for m in _climbable_meshes.keys():
		if not is_instance_valid(m):
			continue
		m.material_overlay = _hover_mat if m == _hovered_mesh else _climb_mat
	if _hovered_mesh != null and is_instance_valid(_hovered_mesh) and not _climbable_meshes.has(_hovered_mesh):
		_hovered_mesh.material_overlay = _hover_mat


func _input(event: InputEvent) -> void:
	if Input.get_mouse_mode() != Input.MOUSE_MODE_VISIBLE:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _hovered_mesh != null:
			_toggle_climbable(_hovered_mesh)
			get_viewport().set_input_as_handled()


func _toggle_climbable(mesh: MeshInstance3D) -> void:
	if _climbable_meshes.has(mesh):
		_climbable_meshes.erase(mesh)
		mesh.material_overlay = null  # restaurar materiales originales
	else:
		_climbable_meshes[mesh] = true
	_refresh_overlays()


func is_climbable(mesh: MeshInstance3D) -> bool:
	return _climbable_meshes.has(mesh)


func _add_perimeter_walls() -> void:
	# Suelo es 40x40 centrado en origen (-20..+20). Muros invisibles altos.
	var half := 20.0
	var height := 6.0
	var thick := 0.5
	var defs := [
		[Vector3(0, height * 0.5, -half), Vector3(half * 2.0 + thick, height, thick)],
		[Vector3(0, height * 0.5,  half), Vector3(half * 2.0 + thick, height, thick)],
		[Vector3(-half, height * 0.5, 0), Vector3(thick, height, half * 2.0 + thick)],
		[Vector3( half, height * 0.5, 0), Vector3(thick, height, half * 2.0 + thick)],
	]
	for d in defs:
		var body := StaticBody3D.new()
		body.position = d[0]
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = d[1]
		cs.shape = bs
		body.add_child(cs)
		add_child(body)


func _ensure_environment() -> void:
	if $WorldEnvironment.environment != null:
		return
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color      = Color(0.45, 0.65, 0.95)
	sky_mat.sky_horizon_color  = Color(0.80, 0.85, 0.90)
	sky_mat.ground_bottom_color = Color(0.20, 0.20, 0.22)
	sky_mat.ground_horizon_color = Color(0.55, 0.55, 0.55)
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	$WorldEnvironment.environment = env


func _on_player_connected_server(id: int, _info: Dictionary) -> void:
	_spawn_player(id)


func _spawn_player(id: int) -> void:
	if $Players.has_node(str(id)):
		return
	var player := PLAYER_SCENE.instantiate()
	player.name = str(id)
	var info : Dictionary = NetworkManager.players.get(id, {})
	player.player_name   = info.get("name",   "Jugador")
	player.avatar_gender = info.get("avatar", "male")
	var idx := NetworkManager.players.keys().find(id)
	player.position = SPAWN_POINTS[idx % SPAWN_POINTS.size()]
	$Players.add_child(player, true)


func _on_player_disconnected(id: int) -> void:
	if $Players.has_node(str(id)):
		$Players.get_node(str(id)).queue_free()


func _on_server_dropped() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	get_tree().change_scene_to_file("res://ui/lobby.tscn")


func _load_house() -> void:
	var path := NetworkManager.house_path
	if path == "":
		return
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err := doc.append_from_file(path, state)
	if err != OK:
		push_error("No se pudo cargar el modelo: %s (err %d)" % [path, err])
		return
	var house := doc.generate_scene(state)
	if house == null:
		push_error("Modelo vacío: %s" % path)
		return
	house.name = "House"
	house.position = HOUSE_OFFSET
	add_child(house)
	_house = house

	# Colisión trimesh sobre todas las mallas cargadas
	_add_static_colliders(house)

	# Ocultar caja de prueba; suelo se mantiene como fallback
	$Crate.visible = false
	$Crate/CollisionShape3D.disabled = true


func get_house() -> Node3D:
	return _house


func set_house_scale(factor: float) -> void:
	if _house == null:
		return
	_house.scale = Vector3.ONE * max(factor, 0.0001)


func _add_static_colliders(node: Node) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh != null and mi.mesh.get_surface_count() > 0:
			var trimesh := mi.mesh.create_trimesh_shape()
			if trimesh != null:
				var body := StaticBody3D.new()
				mi.add_child(body)
				var shape := CollisionShape3D.new()
				shape.shape = trimesh
				body.add_child(shape)
	for c in node.get_children():
		_add_static_colliders(c)
