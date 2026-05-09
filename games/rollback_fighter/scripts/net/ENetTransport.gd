extends Node
class_name ENetTransport

signal packet_received(packet: Dictionary)
signal connected()
signal disconnected()
signal connection_failed(reason: String)

@export var port: int = 7777
@export var max_clients: int = 1

var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
var is_host: bool = false
var is_connected: bool = false

func host(host_port: int = 7777) -> void:
	port = host_port
	is_host = true

	var err := peer.create_server(port, max_clients)
	if err != OK:
		connection_failed.emit("Failed to host on port %d. Error=%d" % [port, err])
		return

	multiplayer.multiplayer_peer = peer
	_wire_signals()

	is_connected = true
	connected.emit()
	print("[ENetTransport] Hosting on port %d" % port)

func join(ip: String, host_port: int = 7777) -> void:
	port = host_port
	is_host = false

	var err := peer.create_client(ip, port)
	if err != OK:
		connection_failed.emit("Failed to join %s:%d. Error=%d" % [ip, port, err])
		return

	multiplayer.multiplayer_peer = peer
	_wire_signals()

	print("[ENetTransport] Joining %s:%d" % [ip, port])

func _wire_signals() -> void:
	if not multiplayer.peer_connected.is_connected(_on_peer_connected):
		multiplayer.peer_connected.connect(_on_peer_connected)

	if not multiplayer.peer_disconnected.is_connected(_on_peer_disconnected):
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)

	if not multiplayer.connected_to_server.is_connected(_on_connected_to_server):
		multiplayer.connected_to_server.connect(_on_connected_to_server)

	if not multiplayer.connection_failed.is_connected(_on_connection_failed):
		multiplayer.connection_failed.connect(_on_connection_failed)

	if not multiplayer.server_disconnected.is_connected(_on_server_disconnected):
		multiplayer.server_disconnected.connect(_on_server_disconnected)

func _process(_delta: float) -> void:
	if multiplayer.multiplayer_peer:
		multiplayer.poll()

func send_packet(packet: Dictionary) -> void:
	if multiplayer.multiplayer_peer == null:
		return

	if is_host:
		_rpc_receive_packet.rpc(packet)
	else:
		_rpc_receive_packet.rpc_id(1, packet)

@rpc("any_peer", "call_remote", "unreliable_ordered")
func _rpc_receive_packet(packet: Dictionary) -> void:
	packet_received.emit(packet)

func _on_peer_connected(id: int) -> void:
	print("[ENetTransport] Peer connected: %d" % id)
	is_connected = true
	connected.emit()

func _on_peer_disconnected(id: int) -> void:
	print("[ENetTransport] Peer disconnected: %d" % id)
	is_connected = false
	disconnected.emit()

func _on_connected_to_server() -> void:
	print("[ENetTransport] Connected to server")
	is_connected = true
	connected.emit()

func _on_connection_failed() -> void:
	is_connected = false
	connection_failed.emit("Connection failed")

func _on_server_disconnected() -> void:
	is_connected = false
	disconnected.emit()
