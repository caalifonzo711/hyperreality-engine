extends Node
class_name ENetTransport

signal packet_received(packet: Dictionary)
signal connected()
signal disconnected()
signal connection_failed(reason: String)
signal start_match_received()

@export var port: int = 7777
@export var max_clients: int = 1

# Benchmark controls
# 0 = baseline LAN
# 6 = ~100ms
# 9 = ~150ms
# 12 = ~200ms
@export var artificial_delay_frames: int = 0
@export var artificial_jitter_frames: int = 0

var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
var is_host: bool = false
var is_connected: bool = false
var remote_peer_id: int = 0

var _delayed_packets: Array[Dictionary] = []


func host(host_port: int = 7777) -> void:
	port = host_port
	is_host = true

	var err: int = peer.create_server(port, max_clients)
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

	var err: int = peer.create_client(ip, port)
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

	_deliver_delayed_packets()


func send_packet(packet: Dictionary) -> void:
	if multiplayer.multiplayer_peer == null:
		return

	if not is_connected:
		return

	if is_host:
		if remote_peer_id == 0:
			return
		_rpc_receive_packet.rpc_id(remote_peer_id, packet)
	else:
		_rpc_receive_packet.rpc_id(1, packet)


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _rpc_receive_packet(packet: Dictionary) -> void:
	_queue_or_emit_packet(packet)


func _queue_or_emit_packet(packet: Dictionary) -> void:
	var delay: int = max(0, artificial_delay_frames)

	if artificial_jitter_frames > 0:
		delay += randi_range(0, artificial_jitter_frames)

	if delay <= 0:
		packet_received.emit(packet)
		return

	var deliver_frame: int = Engine.get_process_frames() + delay

	_delayed_packets.append({
		"deliver_frame": deliver_frame,
		"packet": packet.duplicate(true),
	})


func _deliver_delayed_packets() -> void:
	if _delayed_packets.is_empty():
		return

	var current_process_frame: int = Engine.get_process_frames()

	for i in range(_delayed_packets.size() - 1, -1, -1):
		var item: Dictionary = _delayed_packets[i]

		if current_process_frame >= int(item.get("deliver_frame", 0)):
			var packet: Dictionary = item.get("packet", {})
			_delayed_packets.remove_at(i)
			packet_received.emit(packet)


func pending_delayed_count() -> int:
	return _delayed_packets.size()


func _on_peer_connected(id: int) -> void:
	print("[ENetTransport] Peer connected: %d" % id)
	is_connected = true
	remote_peer_id = id
	connected.emit()


func _on_peer_disconnected(id: int) -> void:
	print("[ENetTransport] Peer disconnected: %d" % id)
	is_connected = false

	if remote_peer_id == id:
		remote_peer_id = 0

	_delayed_packets.clear()
	disconnected.emit()


func _on_connected_to_server() -> void:
	print("[ENetTransport] Connected to server")
	is_connected = true
	connected.emit()


func _on_connection_failed() -> void:
	is_connected = false
	_delayed_packets.clear()
	connection_failed.emit("Connection failed")


func _on_server_disconnected() -> void:
	is_connected = false
	remote_peer_id = 0
	_delayed_packets.clear()
	disconnected.emit()


func send_start_match() -> void:
	if multiplayer.multiplayer_peer == null:
		return

	if not is_connected:
		return

	if is_host:
		if remote_peer_id == 0:
			return
		_rpc_start_match.rpc_id(remote_peer_id)
	else:
		_rpc_start_match.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_start_match() -> void:
	start_match_received.emit()
