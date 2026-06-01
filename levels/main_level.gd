extends Node3D

const PLAYER_SCENE := preload("res://characters/player.tscn")

# Posiciones de spawn distribuidas
const SPAWN_POINTS := [
	Vector3( 0, 0.1,  0),
	Vector3( 3, 0.1,  0),
	Vector3(-3, 0.1,  0),
	Vector3( 0, 0.1,  3),
	Vector3( 3, 0.1,  3),
	Vector3(-3, 0.1,  3),
]


func _ready() -> void:
	NetworkManager.player_disconnected.connect(_on_player_disconnected)

	if multiplayer.is_server():
		NetworkManager.player_connected.connect(_on_player_connected_server)
		# Spawnear jugadores que ya están conectados (incluyendo el servidor)
		for id in NetworkManager.players:
			_spawn_player(id)

	# HUD
	var hud_scene : PackedScene = load("res://ui/hud.tscn")
	var hud := hud_scene.instantiate()
	add_child(hud)


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
