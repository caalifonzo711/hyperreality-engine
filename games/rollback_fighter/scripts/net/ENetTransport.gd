extends Node
class_name ENetTransport

signal packet_received(packet: Dictionary)
signal input_repair_request_received(frame: int, player_id: int)
signal input_repair_response_received(
	frame: int,
	player_id: int,
	input_data: Dictionary,
	available: bool
)
signal connected()
signal disconnected()
signal connection_failed(reason: String)
signal start_match_received()
signal match_config_received(identity: Dictionary)

@export var port: int = 7777
@export var max_clients: int = 1

# Benchmark controls
# 0 = baseline LAN
# 6 = ~100ms
# 9 = ~150ms
# 12 = ~200ms
@export var artificial_delay_frames: int = 0
@export var artificial_jitter_frames: int = 0
@export var deterministic_stress_input_loss_enabled: bool = false

var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
var is_host: bool = false
var is_connected: bool = false
var remote_peer_id: int = 0

var _delayed_packets: Array[Dictionary] = []
var _start_match_sent: bool = false
var deterministic_stress_input_packets_dropped: int = 0


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

	if _should_drop_stress_input_packet(packet):
		deterministic_stress_input_packets_dropped += 1
		return

	if is_host:
		if remote_peer_id == 0:
			return
		_rpc_receive_packet.rpc_id(remote_peer_id, packet)
	else:
		_rpc_receive_packet.rpc_id(1, packet)


func send_match_config(identity: Dictionary) -> void:
	if multiplayer.multiplayer_peer == null or not is_connected:
		return
	if is_host:
		if remote_peer_id == 0:
			return
		_rpc_receive_match_config.rpc_id(remote_peer_id, identity.duplicate(true))
	else:
		_rpc_receive_match_config.rpc_id(1, identity.duplicate(true))


func _should_drop_stress_input_packet(packet: Dictionary) -> bool:
	if not deterministic_stress_input_loss_enabled:
		return false

	if str(packet.get("type", "")) != "input":
		return false

	var packet_player_id: int = int(packet.get("player_id", -1))
	var frame: int = int(packet.get("frame", -1))

	if packet_player_id == 1:
		return (
			(frame >= 600 and frame <= 605)
			or (frame >= 1860 and frame <= 1872)
		)

	if packet_player_id == 2:
		return (
			(frame >= 3000 and frame <= 3005)
			or (frame >= 4260 and frame <= 4272)
		)

	return false


func send_input_repair_request(frame: int, player_id: int) -> void:
	if multiplayer.multiplayer_peer == null or not is_connected:
		return

	if is_host:
		if remote_peer_id == 0:
			return
		_rpc_receive_input_repair_request.rpc_id(
			remote_peer_id,
			frame,
			player_id
		)
	else:
		_rpc_receive_input_repair_request.rpc_id(1, frame, player_id)


func send_input_repair_response(
	frame: int,
	player_id: int,
	input_data: Dictionary,
	available: bool
) -> void:
	if multiplayer.multiplayer_peer == null or not is_connected:
		return

	if is_host:
		if remote_peer_id == 0:
			return
		_rpc_receive_input_repair_response.rpc_id(
			remote_peer_id,
			frame,
			player_id,
			input_data,
			available
		)
	else:
		_rpc_receive_input_repair_response.rpc_id(
			1,
			frame,
			player_id,
			input_data,
			available
		)


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _rpc_receive_packet(packet: Dictionary) -> void:
	_queue_or_emit_packet(packet)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_receive_match_config(identity: Dictionary) -> void:
	var sender_id: int = multiplayer.get_remote_sender_id()
	if sender_id <= 0:
		push_error("[ENetTransport] Ignored config handshake without a remote sender.")
		return
	var expected_sender_id: int = remote_peer_id if is_host else 1
	if sender_id != expected_sender_id:
		push_error("[ENetTransport] Ignored config handshake from unexpected peer %d." % sender_id)
		return
	if not _is_bounded_match_config(identity):
		push_error("[ENetTransport] Ignored malformed or oversized config handshake.")
		return
	match_config_received.emit(identity.duplicate(true))


func _is_bounded_match_config(identity: Dictionary) -> bool:
	if identity.size() != 8:
		return false
	for field in ["protocol_version", "rules_config_version", "p1_config_version", "p2_config_version", "canonical_byte_length"]:
		if not identity.has(field) or typeof(identity[field]) != TYPE_INT:
			return false
	for field in ["p1_id", "p2_id"]:
		if not identity.has(field) or typeof(identity[field]) != TYPE_STRING:
			return false
		if str(identity[field]).length() > 64:
			return false
	if not identity.has("digest") or typeof(identity["digest"]) != TYPE_STRING:
		return false
	if str(identity["digest"]).length() > 64:
		return false
	return true


@rpc("any_peer", "call_remote", "reliable")
func _rpc_receive_input_repair_request(
	frame: int,
	player_id: int
) -> void:
	input_repair_request_received.emit(frame, player_id)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_receive_input_repair_response(
	frame: int,
	player_id: int,
	input_data: Dictionary,
	available: bool
) -> void:
	input_repair_response_received.emit(
		frame,
		player_id,
		input_data,
		available
	)


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

	if not is_host or remote_peer_id == 0 or _start_match_sent:
		return

	_start_match_sent = true
	_rpc_start_match.rpc()


@rpc("authority", "call_local", "reliable")
func _rpc_start_match() -> void:
	start_match_received.emit()
