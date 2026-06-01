extends Node

const GAME_PORT    := 4433
const MAX_PLAYERS  := 6

signal player_connected(id: int, info: Dictionary)
signal player_disconnected(id: int)
signal connection_failed
signal server_disconnected
signal connected_to_server  ## solo para clientes: conexión establecida

## id → {name, avatar}
var players: Dictionary = {}
var my_info: Dictionary = {name = "Jugador", avatar = "male"}


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func host() -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(GAME_PORT, MAX_PLAYERS)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	players[1] = my_info
	player_connected.emit(1, my_info)
	return OK


func join(ip: String) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, GAME_PORT)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	return OK


func disconnect_game() -> void:
	multiplayer.multiplayer_peer = null
	players.clear()


# --- Señales de ENet ---

func _on_peer_connected(id: int) -> void:
	if multiplayer.is_server():
		# Enviar al recién llegado todos los jugadores ya conectados
		for pid in players:
			_sync_player.rpc_id(id, pid, players[pid])
		# Enviar nuestra propia info al recién llegado
		_sync_player.rpc_id(id, 1, my_info)


func _on_peer_disconnected(id: int) -> void:
	players.erase(id)
	player_disconnected.emit(id)


func _on_connected_to_server() -> void:
	_announce_self.rpc_id(1, my_info)
	connected_to_server.emit()


func _on_connection_failed() -> void:
	connection_failed.emit()


func _on_server_disconnected() -> void:
	players.clear()
	server_disconnected.emit()


# --- RPCs ---

## Clientes → Servidor: "aquí estoy"
@rpc("any_peer", "reliable", "call_remote")
func _announce_self(info: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	players[sender] = info
	player_connected.emit(sender, info)
	# Distribuir a todos los demás pares
	for pid in multiplayer.get_peers():
		if pid != sender:
			_sync_player.rpc_id(pid, sender, info)


## Servidor → Clientes: "este jugador existe"
@rpc("authority", "reliable", "call_remote")
func _sync_player(id: int, info: Dictionary) -> void:
	players[id] = info
	player_connected.emit(id, info)
