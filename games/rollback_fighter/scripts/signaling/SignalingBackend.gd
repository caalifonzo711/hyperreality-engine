extends SceneTree

const RoomStoreScript = preload("res://games/rollback_fighter/scripts/signaling/SignalingRoomStore.gd")
const ProbeScript = preload("res://games/rollback_fighter/scripts/net/NatTraversalProbe.gd")
const DEFAULT_PORT := 8787
const DEFAULT_UDP_PORT := 8788
const DEFAULT_BIND_ADDRESS := "127.0.0.1"
const MAX_HEADER_BYTES := 8192
const MAX_BODY_BYTES := 4096
const CONNECTION_TIMEOUT_MSEC := 10000

var _server := TCPServer.new()
var _udp_server := PacketPeerUDP.new()
var _store = RoomStoreScript.new()
var _connections: Array[Dictionary] = []
var _udp_port := DEFAULT_UDP_PORT


func _initialize() -> void:
	var port := DEFAULT_PORT
	var bind_address := DEFAULT_BIND_ADDRESS
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--port="):
			port = int(argument.trim_prefix("--port="))
		elif argument.begins_with("--bind="):
			bind_address = argument.trim_prefix("--bind=")
		elif argument.begins_with("--udp-port="):
			_udp_port = int(argument.trim_prefix("--udp-port="))
	if port < 1 or port > 65535 or _udp_port < 1 or _udp_port > 65535:
		push_error("[SignalingBackend] TCP and UDP ports must be between 1 and 65535.")
		quit(2)
		return
	var error := _server.listen(port, bind_address)
	if error != OK:
		push_error("[SignalingBackend] Could not listen on %s:%d (error %d)." % [bind_address, port, error])
		quit(2)
		return
	var udp_error := _udp_server.bind(_udp_port, bind_address)
	if udp_error != OK:
		push_error("[SignalingBackend] Could not bind UDP observer on %s:%d (error %d)." % [bind_address, _udp_port, udp_error])
		quit(2)
		return
	print("[SignalingBackend] HTTP %s:%d | UDP observation %s:%d" % [bind_address, port, bind_address, _udp_port])


func _process(_delta: float) -> bool:
	_poll_udp_observer()
	while _server.is_connection_available():
		var peer := _server.take_connection()
		if peer != null:
			_connections.append({"peer": peer, "buffer": PackedByteArray(), "opened_at": Time.get_ticks_msec()})
	for index in range(_connections.size() - 1, -1, -1):
		if _poll_connection(_connections[index]):
			_connections.remove_at(index)
	_store.prune_expired()
	return false


func _poll_udp_observer() -> void:
	var processed := 0
	while _udp_server.get_available_packet_count() > 0 and processed < 64:
		processed += 1
		var packet := _udp_server.get_packet()
		if packet.size() != ProbeScript.PACKET_SIZE:
			continue
		var decoded: Dictionary = ProbeScript.decode(packet)
		if not bool(decoded.get("ok", false)) or int(decoded.get("type", 0)) != ProbeScript.TYPE_REGISTER:
			continue
		var source_address := _udp_server.get_packet_ip()
		var source_port := _udp_server.get_packet_port()
		var registration: Dictionary = _store.register_udp_endpoint(
			str(decoded.get("session_id", "")),
			str(decoded.get("peer_id", "")),
			str(decoded.get("token", "")),
			source_address,
			source_port
		)
		if not bool(registration.get("ok", false)):
			continue
		var acknowledgement := ProbeScript.encode(
			ProbeScript.TYPE_REGISTER_ACK,
			str(decoded.get("session_id", "")),
			str(decoded.get("peer_id", "")),
			str(decoded.get("token", "")),
			str(decoded.get("nonce", ""))
		)
		_udp_server.set_dest_address(source_address, source_port)
		_udp_server.put_packet(acknowledgement)


func _poll_connection(connection: Dictionary) -> bool:
	var peer: StreamPeerTCP = connection["peer"]
	peer.poll()
	if Time.get_ticks_msec() - int(connection["opened_at"]) > CONNECTION_TIMEOUT_MSEC:
		_send_response(peer, 408, {"ok": false, "error_code": "TIMEOUT", "user_message": "Request timed out."})
		return true
	var status := peer.get_status()
	if status in [StreamPeerTCP.STATUS_NONE, StreamPeerTCP.STATUS_ERROR]:
		return true
	var available := peer.get_available_bytes()
	if available > 0:
		var read_result := peer.get_data(available)
		if int(read_result[0]) != OK:
			return true
		var buffer: PackedByteArray = connection["buffer"]
		buffer.append_array(read_result[1])
		connection["buffer"] = buffer
		if buffer.size() > MAX_HEADER_BYTES + MAX_BODY_BYTES:
			_send_response(peer, 413, {"ok": false, "error_code": "INVALID_PAYLOAD", "user_message": "Request is too large."})
			return true
	var request := _parse_request(connection["buffer"])
	if bool(request.get("waiting", false)):
		return false
	if not bool(request.get("ok", false)):
		_send_response(peer, int(request.get("status", 400)), request.get("response", {}))
		return true
	var routed := _route_request(request, peer.get_connected_host())
	_send_response(peer, int(routed.get("status", 500)), routed.get("response", {}))
	return true


func _parse_request(buffer: PackedByteArray) -> Dictionary:
	var text := buffer.get_string_from_utf8()
	var header_end := text.find("\r\n\r\n")
	if header_end < 0:
		return {"waiting": buffer.size() <= MAX_HEADER_BYTES}
	if header_end > MAX_HEADER_BYTES:
		return _bad_request(413, "INVALID_PAYLOAD", "Request headers are too large.")
	var header_lines := text.substr(0, header_end).split("\r\n")
	if header_lines.is_empty():
		return _bad_request(400, "INVALID_PAYLOAD", "Malformed HTTP request.")
	var request_parts := str(header_lines[0]).split(" ")
	if request_parts.size() != 3:
		return _bad_request(400, "INVALID_PAYLOAD", "Malformed HTTP request.")
	var headers := {}
	for line_index in range(1, header_lines.size()):
		var line := str(header_lines[line_index])
		var separator := line.find(":")
		if separator <= 0:
			return _bad_request(400, "INVALID_PAYLOAD", "Malformed HTTP headers.")
		headers[line.substr(0, separator).strip_edges().to_lower()] = line.substr(separator + 1).strip_edges()
	var content_length := int(headers.get("content-length", "0"))
	if content_length < 0 or content_length > MAX_BODY_BYTES:
		return _bad_request(413, "INVALID_PAYLOAD", "Request body is too large.")
	var body_offset := header_end + 4
	if buffer.size() < body_offset + content_length:
		return {"waiting": true}
	var body := {}
	if content_length > 0:
		var body_text := text.substr(body_offset, content_length)
		var parsed: Variant = JSON.parse_string(body_text)
		if not parsed is Dictionary:
			return _bad_request(400, "INVALID_PAYLOAD", "Request body must be a JSON object.")
		body = parsed
	return {
		"ok": true,
		"method": str(request_parts[0]),
		"path": str(request_parts[1]).split("?", true, 1)[0],
		"headers": headers,
		"body": body,
	}


func _route_request(request: Dictionary, observed_address: String) -> Dictionary:
	var method := str(request["method"])
	var path := str(request["path"]).trim_prefix("/").trim_suffix("/")
	var parts := path.split("/", false)
	var headers: Dictionary = request["headers"]
	var body: Dictionary = request["body"]
	var result: Dictionary
	if method == "POST" and parts.size() == 1 and parts[0] == "rooms":
		result = _store.create_room(body, observed_address)
	elif method == "POST" and parts.size() == 3 and parts[0] == "rooms" and parts[2] == "join":
		result = _store.join_room(parts[1], body, observed_address)
	elif method == "GET" and parts.size() == 2 and parts[0] == "rooms":
		result = _store.get_room(parts[1], str(headers.get("x-session-id", "")), str(headers.get("x-peer-id", "")))
	elif method == "POST" and parts.size() == 3 and parts[0] == "rooms" and parts[2] == "peer":
		result = _store.update_peer(parts[1], str(headers.get("x-session-id", "")), str(headers.get("x-peer-id", "")), body.get("endpoint", {}), observed_address)
	elif method == "POST" and parts.size() == 3 and parts[0] == "rooms" and parts[2] == "candidates":
		result = _store.set_local_candidates(parts[1], str(headers.get("x-session-id", "")), str(headers.get("x-peer-id", "")), body.get("candidates", []))
	elif method == "DELETE" and parts.size() == 2 and parts[0] == "rooms":
		result = _store.close_room(parts[1], str(headers.get("x-session-id", "")), str(headers.get("x-peer-id", "")))
	else:
		return {"status": 404, "response": {"ok": false, "error_code": "ROOM_NOT_FOUND", "user_message": "Endpoint not found."}}
	if bool(result.get("ok", false)):
		var data_value: Variant = result.get("data", {})
		if data_value is Dictionary:
			var data: Dictionary = data_value
			data["signaling_udp_port"] = _udp_port
	return {"status": 200 if bool(result.get("ok", false)) else _status_for_error(str(result.get("error_code", ""))), "response": result}


func _status_for_error(error_code: String) -> int:
	match error_code:
		"ROOM_NOT_FOUND":
			return 404
		"ROOM_EXPIRED":
			return 410
		"ROOM_FULL":
			return 409
		"INCOMPATIBLE_PROTOCOL":
			return 409
		"NOT_AUTHORIZED":
			return 403
		"INVALID_ROOM_CODE", "INVALID_PAYLOAD":
			return 400
		_:
			return 500


func _bad_request(status: int, code: String, message: String) -> Dictionary:
	return {"ok": false, "status": status, "response": {"ok": false, "error_code": code, "user_message": message}}


func _send_response(peer: StreamPeerTCP, status: int, response: Dictionary) -> void:
	var body := JSON.stringify(response)
	var reason := {200: "OK", 400: "Bad Request", 403: "Forbidden", 404: "Not Found", 408: "Request Timeout", 409: "Conflict", 410: "Gone", 413: "Payload Too Large", 500: "Internal Server Error"}.get(status, "Error")
	var message := "HTTP/1.1 %d %s\r\nContent-Type: application/json\r\nContent-Length: %d\r\nConnection: close\r\nCache-Control: no-store\r\n\r\n%s" % [status, reason, body.to_utf8_buffer().size(), body]
	peer.put_data(message.to_utf8_buffer())
	peer.disconnect_from_host()
