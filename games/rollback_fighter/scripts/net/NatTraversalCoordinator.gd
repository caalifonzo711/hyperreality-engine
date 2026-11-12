extends Node
class_name RollbackFighterNatTraversalCoordinator

signal state_changed(state: String, user_message: String)
signal traversal_completed(success: bool, result: Dictionary)

const ProbeScript = preload("res://games/rollback_fighter/scripts/net/NatTraversalProbe.gd")
const AttemptScript = preload("res://games/rollback_fighter/scripts/net/NatTraversalAttempt.gd")
const SignalingClientScript = preload("res://games/rollback_fighter/scripts/signaling/SignalingClient.gd")

const PROBE_INTERVAL_SECONDS := 0.2
const REGISTER_INTERVAL_SECONDS := 0.25
const ROOM_POLL_INTERVAL_SECONDS := 0.5
const KEEPALIVE_INTERVAL_SECONDS := 1.0
const TRAVERSAL_TIMEOUT_MSEC := 8000
const MAX_PROBE_COUNT := 128
const MAX_REGISTER_COUNT := 16

var _socket: PacketPeerUDP
var _attempt = AttemptScript.new()
var _context: Dictionary = {}
var _is_host := false
var _local_port := 0
var _signaling_udp_host := ""
var _signaling_udp_port := 0
var _peer_endpoint: Dictionary = {}
var _peer_candidates: Array[Dictionary] = []
var _successful_endpoint: Dictionary = {}
var _registration_nonce := ""
var _probe_nonce := ""
var _register_count := 0
var _registered := false
var _poll_active := false
var _candidate_submit_active := false
var _elapsed_register := 0.0
var _elapsed_probe := 0.0
var _elapsed_poll := 0.0
var _elapsed_keepalive := 0.0
var _client
var _crypto := Crypto.new()
var _completed_emitted := false


func start_traversal(context: Dictionary, requested_local_port: int, signaling_udp_host: String) -> bool:
	cancel()
	if not _valid_context(context) or requested_local_port < 0 or requested_local_port > 65535:
		return false
	_context = context.duplicate(true)
	_is_host = bool(_context.get("is_host", false))
	_signaling_udp_host = signaling_udp_host.strip_edges()
	_signaling_udp_port = int(_context.get("signaling_udp_port", 0))
	if _signaling_udp_host.is_empty() or _signaling_udp_port < 1 or _signaling_udp_port > 65535:
		return false
	_socket = PacketPeerUDP.new()
	var bind_error := _socket.bind(requested_local_port)
	if bind_error != OK:
		_socket = null
		return false
	_local_port = _socket.get_local_port()
	if _local_port < 1:
		cancel()
		return false
	_client = SignalingClientScript.new()
	add_child(_client)
	if not _client.configure(str(_context.get("server_url", ""))):
		cancel()
		return false
	_registration_nonce = _random_hex(8)
	_probe_nonce = _random_hex(8)
	_elapsed_register = 0.0
	_elapsed_probe = 0.0
	_elapsed_poll = 0.0
	_elapsed_keepalive = 0.0
	_completed_emitted = false
	_attempt.begin(Time.get_ticks_msec(), TRAVERSAL_TIMEOUT_MSEC, MAX_PROBE_COUNT)
	_emit_state(AttemptScript.STATE_REGISTERING, "Preparing direct connection...")
	_submit_local_candidates()
	_send_registration()
	return true


func cancel() -> void:
	if _socket != null:
		_socket.close()
	_socket = null
	if _client != null and is_instance_valid(_client):
		_client.queue_free()
	_client = null
	_context.clear()
	_peer_endpoint.clear()
	_peer_candidates.clear()
	_successful_endpoint.clear()
	_local_port = 0
	_registered = false
	_poll_active = false
	_candidate_submit_active = false
	_register_count = 0
	_completed_emitted = false
	_attempt = AttemptScript.new()


func release_for_enet() -> Dictionary:
	if _attempt.state != AttemptScript.STATE_DIRECT or _socket == null:
		return {}
	var result := get_result()
	_socket.close()
	_socket = null
	if _client != null and is_instance_valid(_client):
		_client.queue_free()
	_client = null
	return result


func get_state() -> String:
	return _attempt.state


func get_result() -> Dictionary:
	return {
		"connection_mode": "DIRECT" if _attempt.state == AttemptScript.STATE_DIRECT else "RELAY_REQUIRED",
		"local_port": _local_port,
		"peer_address": str(_successful_endpoint.get("address", _peer_endpoint.get("address", ""))),
		"peer_port": int(_successful_endpoint.get("port", _peer_endpoint.get("port", 0))),
		"probe_count": _attempt.probe_count,
		"duration_msec": maxi(0, Time.get_ticks_msec() - _attempt.started_msec),
	}


func get_diagnostics() -> Dictionary:
	var result := get_result()
	result["state"] = _attempt.state
	result["local_udp_port"] = _local_port
	result["observed_endpoint"] = _own_endpoint_from_context()
	result["peer_observed_endpoint"] = _peer_endpoint.duplicate(true)
	result["registered"] = _registered
	return result


func _process(delta: float) -> void:
	if _socket == null:
		return
	_receive_packets()
	if _attempt.state != AttemptScript.STATE_WAITING_PEER and _attempt.update_timeout(Time.get_ticks_msec()):
		_fail_traversal()
		return
	if _attempt.state == AttemptScript.STATE_REGISTERING:
		_elapsed_register += delta
		_elapsed_poll += delta
		if _elapsed_register >= REGISTER_INTERVAL_SECONDS and _register_count < MAX_REGISTER_COUNT:
			_elapsed_register = 0.0
			_send_registration()
		if _elapsed_poll >= ROOM_POLL_INTERVAL_SECONDS:
			_elapsed_poll = 0.0
			_poll_room()
	elif _attempt.state == AttemptScript.STATE_WAITING_PEER:
		_elapsed_poll += delta
		if _elapsed_poll >= ROOM_POLL_INTERVAL_SECONDS:
			_elapsed_poll = 0.0
			_poll_room()
	elif _attempt.state == AttemptScript.STATE_PUNCHING:
		_elapsed_probe += delta
		if _elapsed_probe >= PROBE_INTERVAL_SECONDS:
			_elapsed_probe = 0.0
			_send_probe()
	elif _attempt.state == AttemptScript.STATE_DIRECT:
		_elapsed_keepalive += delta
		if _elapsed_keepalive >= KEEPALIVE_INTERVAL_SECONDS:
			_elapsed_keepalive = 0.0
			_send_raw(ProbeScript.TYPE_PROBE, _probe_nonce, _successful_endpoint if not _successful_endpoint.is_empty() else _peer_endpoint)


func _send_registration() -> void:
	if _socket == null or _register_count >= MAX_REGISTER_COUNT:
		return
	_register_count += 1
	_send_raw(
		ProbeScript.TYPE_REGISTER,
		_registration_nonce,
		{"address": _signaling_udp_host, "port": _signaling_udp_port},
		str(_context.get("peer_id", ""))
	)


func _send_probe() -> void:
	for endpoint: Dictionary in _peer_candidates:
		if not _attempt.record_probe_sent():
			return
		_send_raw(ProbeScript.TYPE_PROBE, _probe_nonce, endpoint, str(_context.get("probe_id", "")))


func _send_raw(packet_type: int, nonce: String, endpoint: Dictionary, peer_id: String = "") -> void:
	if _socket == null:
		return
	var packet_peer_id := peer_id if not peer_id.is_empty() else str(_context.get("probe_id", ""))
	var packet := ProbeScript.encode(
		packet_type,
		str(_context.get("session_id", "")),
		packet_peer_id,
		str(_context.get("traversal_token", "")),
		nonce
	)
	if packet.is_empty():
		return
	_socket.set_dest_address(str(endpoint.get("address", "")), int(endpoint.get("port", 0)))
	_socket.put_packet(packet)


func _receive_packets() -> void:
	var received := 0
	while _socket.get_available_packet_count() > 0 and received < 32:
		received += 1
		var packet := _socket.get_packet()
		if packet.size() > ProbeScript.PACKET_SIZE:
			continue
		var decoded: Dictionary = ProbeScript.decode(
			packet,
			str(_context.get("session_id", "")),
			str(_context.get("traversal_token", ""))
		)
		if not bool(decoded.get("ok", false)):
			continue
		var packet_type := int(decoded.get("type", 0))
		if packet_type == ProbeScript.TYPE_REGISTER_ACK:
			if not _registered and str(decoded.get("peer_id", "")) == str(_context.get("peer_id", "")) and str(decoded.get("nonce", "")) == _registration_nonce:
				_registered = true
				_attempt.wait_for_peer()
				_emit_state(AttemptScript.STATE_WAITING_PEER, "Waiting for opponent...")
				_poll_room()
			continue
		if str(decoded.get("peer_id", "")) != str(_context.get("opponent_probe_id", "")):
			continue
		var source := {"address": _socket.get_packet_ip(), "port": _socket.get_packet_port()}
		if packet_type == ProbeScript.TYPE_PROBE:
			_successful_endpoint = source
			_attempt.record_valid_probe()
			_send_raw(ProbeScript.TYPE_ACK, str(decoded.get("nonce", "")), source)
		elif packet_type == ProbeScript.TYPE_ACK and str(decoded.get("nonce", "")) == _probe_nonce:
			_successful_endpoint = source
			_attempt.record_valid_ack()
		if _attempt.state == AttemptScript.STATE_DIRECT:
			_complete_direct()


func _poll_room() -> void:
	if _poll_active or _client == null:
		return
	_submit_local_candidates()
	_poll_active = true
	var response: Dictionary = await _client.get_room(
		str(_context.get("room_code", "")),
		str(_context.get("session_id", "")),
		str(_context.get("peer_id", ""))
	)
	_poll_active = false
	if not bool(response.get("ok", false)):
		if str(response.get("error_code", "")) in ["ROOM_EXPIRED", "ROOM_NOT_FOUND", "NOT_AUTHORIZED"]:
			_fail_traversal()
		return
	if _socket == null:
		return
	var room: Dictionary = response.get("data", {})
	_context["opponent_probe_id"] = str(room.get("opponent_probe_id", ""))
	_context["host_endpoint"] = Dictionary(room.get("host_endpoint", {})).duplicate(true)
	_context["guest_endpoint"] = Dictionary(room.get("guest_endpoint", {})).duplicate(true)
	_context["host_udp_registered"] = bool(room.get("host_udp_registered", false))
	_context["guest_udp_registered"] = bool(room.get("guest_udp_registered", false))
	_context["host_local_candidates"] = Array(room.get("host_local_candidates", [])).duplicate(true)
	_context["guest_local_candidates"] = Array(room.get("guest_local_candidates", [])).duplicate(true)
	_context["host_candidates_submitted"] = bool(room.get("host_candidates_submitted", false))
	_context["guest_candidates_submitted"] = bool(room.get("guest_candidates_submitted", false))
	if not _registered or str(_context.get("opponent_probe_id", "")).is_empty():
		return
	if not bool(_context.get("host_udp_registered", false)) or not bool(_context.get("guest_udp_registered", false)):
		return
	if not bool(_context.get("host_candidates_submitted", false)) or not bool(_context.get("guest_candidates_submitted", false)):
		return
	_peer_endpoint = Dictionary(
		_context.get("guest_endpoint", {}) if _is_host else _context.get("host_endpoint", {})
	).duplicate(true)
	if str(_peer_endpoint.get("address", "")).is_empty() or int(_peer_endpoint.get("port", 0)) < 1:
		return
	_peer_candidates = [_peer_endpoint]
	var local_values: Array = _context.get("guest_local_candidates", []) if _is_host else _context.get("host_local_candidates", [])
	for candidate_value in local_values:
		if not candidate_value is Dictionary:
			continue
		var candidate: Dictionary = candidate_value
		var duplicate := false
		for existing: Dictionary in _peer_candidates:
			if str(existing.get("address", "")) == str(candidate.get("address", "")) and int(existing.get("port", 0)) == int(candidate.get("port", 0)):
				duplicate = true
				break
		if not duplicate:
			_peer_candidates.append(candidate.duplicate(true))
	_attempt.begin_punching(Time.get_ticks_msec())
	_emit_state(AttemptScript.STATE_PUNCHING, "Connecting directly...")
	_send_probe()


func _submit_local_candidates() -> void:
	if _candidate_submit_active or _client == null:
		return
	_candidate_submit_active = true
	var candidates: Array[Dictionary] = []
	for address: String in IP.get_local_addresses():
		if address.begins_with("127.") or address == "::1" or address.begins_with("fe80:"):
			continue
		if not address.is_valid_ip_address():
			continue
		candidates.append({"address": address, "port": _local_port})
		if candidates.size() >= 4:
			break
	await _client.update_local_candidates(
		str(_context.get("room_code", "")),
		str(_context.get("session_id", "")),
		str(_context.get("peer_id", "")),
		candidates
	)
	_candidate_submit_active = false


func _complete_direct() -> void:
	if _completed_emitted:
		return
	_completed_emitted = true
	_emit_state(AttemptScript.STATE_DIRECT, "Connected")
	traversal_completed.emit(true, get_result())


func _fail_traversal() -> void:
	if _completed_emitted:
		return
	_completed_emitted = true
	_attempt.fail()
	if _socket != null:
		_socket.close()
	_socket = null
	if _client != null and is_instance_valid(_client):
		_client.queue_free()
	_client = null
	_emit_state(AttemptScript.STATE_RELAY_REQUIRED, "Direct connection unavailable. Relay required.")
	traversal_completed.emit(false, get_result())


func _emit_state(state_value: String, message: String) -> void:
	state_changed.emit(state_value, message)
	if OS.is_debug_build():
		print("[NatTraversal] %s | %s | %s" % [state_value, message, get_diagnostics()])


func _own_endpoint_from_context() -> Dictionary:
	return Dictionary(
		_context.get("host_endpoint", {}) if _is_host else _context.get("guest_endpoint", {})
	).duplicate(true)


func _valid_context(context: Dictionary) -> bool:
	for field in ["room_code", "session_id", "peer_id", "probe_id", "traversal_token", "server_url"]:
		if typeof(context.get(field)) != TYPE_STRING or str(context.get(field, "")).is_empty():
			return false
	return typeof(context.get("is_host")) == TYPE_BOOL and typeof(context.get("signaling_udp_port")) == TYPE_INT


func _random_hex(byte_count: int) -> String:
	return _crypto.generate_random_bytes(byte_count).hex_encode()
