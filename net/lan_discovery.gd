extends Node

const DISCOVERY_PORT := 4434
const BROADCAST_ADDR := "255.255.255.255"
const BROADCAST_INTERVAL := 1.0

signal server_found(info: Dictionary)    # {name, ip, port, players, max_players}
signal server_lost(ip: String)

var _udp_server  := UDPServer.new()
var _broadcast   := PacketPeerUDP.new()
var _timer       := 0.0
var _is_hosting  := false
var _server_name := "Aula"
var _found_servers: Dictionary = {}  # ip → info
var _server_ttl: Dictionary = {}     # ip → time_remaining


func _ready() -> void:
	set_process(false)


func start_hosting(room_name: String = "Aula") -> void:
	_server_name = room_name
	_is_hosting = true
	_broadcast.set_broadcast_enabled(true)
	_broadcast.set_dest_address(BROADCAST_ADDR, DISCOVERY_PORT)
	set_process(true)


func stop_hosting() -> void:
	_is_hosting = false
	_broadcast.close()
	set_process(false)


func start_listening() -> void:
	_is_hosting = false
	_udp_server.listen(DISCOVERY_PORT)
	set_process(true)


func stop_listening() -> void:
	_udp_server.stop()
	_found_servers.clear()
	_server_ttl.clear()
	set_process(false)


func get_servers() -> Array:
	return _found_servers.values()


func _process(delta: float) -> void:
	if _is_hosting:
		_timer += delta
		if _timer >= BROADCAST_INTERVAL:
			_timer = 0.0
			_send_broadcast()
	else:
		_udp_server.poll()
		while _udp_server.is_connection_available():
			var peer := _udp_server.take_connection()
			while peer.get_available_packet_count() > 0:
				_handle_packet(peer.get_packet(), peer.get_packet_ip())
		# TTL de servidores
		for ip in _server_ttl.keys():
			_server_ttl[ip] -= delta
			if _server_ttl[ip] <= 0.0:
				var was = _found_servers.get(ip)
				_found_servers.erase(ip)
				_server_ttl.erase(ip)
				if was:
					server_lost.emit(ip)


func _send_broadcast() -> void:
	var info := {
		name     = _server_name,
		ip       = _get_local_ip(),
		port     = NetworkManager.GAME_PORT,
		players  = NetworkManager.players.size(),
		max_players = NetworkManager.MAX_PLAYERS,
	}
	var data := JSON.stringify(info).to_utf8_buffer()
	_broadcast.put_packet(data)


func _handle_packet(data: PackedByteArray, sender_ip: String) -> void:
	var txt := data.get_string_from_utf8()
	var parsed := JSON.parse_string(txt)
	if not parsed is Dictionary:
		return
	parsed["ip"] = sender_ip  # IP real del paquete recibido
	_found_servers[sender_ip] = parsed
	_server_ttl[sender_ip] = BROADCAST_INTERVAL * 3.0
	server_found.emit(parsed)


func _get_local_ip() -> String:
	for addr in IP.get_local_addresses():
		if addr.begins_with("192.168.") or addr.begins_with("10.") or addr.begins_with("172."):
			return addr
	return "127.0.0.1"
