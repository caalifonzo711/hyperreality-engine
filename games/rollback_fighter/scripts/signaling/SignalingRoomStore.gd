extends RefCounted
class_name RollbackFighterSignalingRoomStore

const ROOM_CODE_LENGTH := 6
const ROOM_CODE_ALPHABET := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
const DEFAULT_TTL_SECONDS := 600
const MAX_GAME_ID_LENGTH := 64
const MAX_ADDRESS_LENGTH := 255
const TRANSPORT_ID := "enet_udp"
const MAX_ROOMS := 4096

var room_ttl_seconds: int = DEFAULT_TTL_SECONDS
var _rooms: Dictionary = {}
var _session_rooms: Dictionary = {}
var _crypto := Crypto.new()


func create_room(payload: Dictionary, observed_address: String = "", now_unix: int = -1) -> Dictionary:
	var identity_result := _validate_identity(payload)
	if not bool(identity_result.get("ok", false)):
		return identity_result
	var endpoint_result := _validate_endpoint(payload.get("endpoint", {}), observed_address, true)
	if not bool(endpoint_result.get("ok", false)):
		return endpoint_result
	var now := _now(now_unix)
	prune_expired(now)
	if _rooms.size() >= MAX_ROOMS:
		return _error("SERVER_BUSY", "The signaling server has too many active rooms.")
	var room_code := _new_room_code()
	if room_code.is_empty():
		return _error("SERVER_ERROR", "Could not allocate a room code.")
	var room := {
		"room_code": room_code,
		"session_id": _random_hex(24),
		"host_peer_id": _random_hex(16),
		"guest_peer_id": "",
		"host_probe_id": _random_hex(16),
		"guest_probe_id": "",
		"traversal_token": _random_hex(32),
		"host_endpoint": endpoint_result["endpoint"],
		"guest_endpoint": {},
		"host_udp_registered": false,
		"guest_udp_registered": false,
		"host_local_candidates": [],
		"guest_local_candidates": [],
		"host_candidates_submitted": false,
		"guest_candidates_submitted": false,
		"protocol_version": int(payload["protocol_version"]),
		"game_id": str(payload["game_id"]),
		"created_at": now,
		"expires_at": now + room_ttl_seconds,
	}
	_rooms[room_code] = room
	_session_rooms[str(room["session_id"])] = room_code
	return _success(_public_room(room, str(room["host_peer_id"])))


func join_room(room_code: String, payload: Dictionary, observed_address: String = "", now_unix: int = -1) -> Dictionary:
	var code := normalize_room_code(room_code)
	var lookup := _lookup(code, now_unix)
	if not bool(lookup.get("ok", false)):
		return lookup
	var room: Dictionary = lookup["room"]
	if not str(room.get("guest_peer_id", "")).is_empty():
		return _error("ROOM_FULL", "This room already has an opponent.")
	var identity_result := _validate_identity(payload)
	if not bool(identity_result.get("ok", false)):
		return identity_result
	if (
		int(payload["protocol_version"]) != int(room["protocol_version"])
		or str(payload["game_id"]) != str(room["game_id"])
	):
		return _error("INCOMPATIBLE_PROTOCOL", "The room uses an incompatible game protocol.")
	var endpoint_result := _validate_endpoint(payload.get("endpoint", {}), observed_address, false)
	if not bool(endpoint_result.get("ok", false)):
		return endpoint_result
	room["guest_peer_id"] = _random_hex(16)
	room["guest_probe_id"] = _random_hex(16)
	room["guest_endpoint"] = endpoint_result["endpoint"]
	_rooms[code] = room
	return _success(_public_room(room, str(room["guest_peer_id"])))


func register_udp_endpoint(session_id: String, peer_id: String, token: String, address: String, port: int, now_unix: int = -1) -> Dictionary:
	if not _session_rooms.has(session_id):
		return _error("ROOM_NOT_FOUND", "Room not found.")
	var room_code := str(_session_rooms[session_id])
	var lookup := _lookup(room_code, now_unix)
	if not bool(lookup.get("ok", false)):
		return lookup
	var room: Dictionary = lookup["room"]
	if token != str(room.get("traversal_token", "")) or not _authorized(room, session_id, peer_id):
		return _error("NOT_AUTHORIZED", "Traversal credentials are invalid.")
	var endpoint_result := _validate_endpoint(
		{"transport": TRANSPORT_ID, "address": address, "port": port},
		address,
		true
	)
	if not bool(endpoint_result.get("ok", false)):
		return endpoint_result
	if peer_id == str(room["host_peer_id"]):
		room["host_endpoint"] = endpoint_result["endpoint"]
		room["host_udp_registered"] = true
	else:
		room["guest_endpoint"] = endpoint_result["endpoint"]
		room["guest_udp_registered"] = true
	_rooms[room_code] = room
	return _success(_public_room(room, peer_id))


func get_room(room_code: String, session_id: String, peer_id: String, now_unix: int = -1) -> Dictionary:
	var lookup := _lookup(normalize_room_code(room_code), now_unix)
	if not bool(lookup.get("ok", false)):
		return lookup
	var room: Dictionary = lookup["room"]
	if not _authorized(room, session_id, peer_id):
		return _error("NOT_AUTHORIZED", "Room credentials are invalid.")
	return _success(_public_room(room, peer_id))


func set_local_candidates(room_code: String, session_id: String, peer_id: String, candidates: Variant, now_unix: int = -1) -> Dictionary:
	var code := normalize_room_code(room_code)
	var lookup := _lookup(code, now_unix)
	if not bool(lookup.get("ok", false)):
		return lookup
	var room: Dictionary = lookup["room"]
	if not _authorized(room, session_id, peer_id):
		return _error("NOT_AUTHORIZED", "Room credentials are invalid.")
	var validation := _validate_local_candidates(candidates)
	if not bool(validation.get("ok", false)):
		return validation
	if peer_id == str(room["host_peer_id"]):
		room["host_local_candidates"] = validation["candidates"]
		room["host_candidates_submitted"] = true
	else:
		room["guest_local_candidates"] = validation["candidates"]
		room["guest_candidates_submitted"] = true
	_rooms[code] = room
	return _success(_public_room(room, peer_id))


func update_peer(room_code: String, session_id: String, peer_id: String, endpoint: Dictionary, observed_address: String = "", now_unix: int = -1) -> Dictionary:
	var code := normalize_room_code(room_code)
	var lookup := _lookup(code, now_unix)
	if not bool(lookup.get("ok", false)):
		return lookup
	var room: Dictionary = lookup["room"]
	if not _authorized(room, session_id, peer_id):
		return _error("NOT_AUTHORIZED", "Room credentials are invalid.")
	var endpoint_result := _validate_endpoint(endpoint, observed_address, peer_id == str(room["host_peer_id"]))
	if not bool(endpoint_result.get("ok", false)):
		return endpoint_result
	if peer_id == str(room["host_peer_id"]):
		room["host_endpoint"] = endpoint_result["endpoint"]
	else:
		room["guest_endpoint"] = endpoint_result["endpoint"]
	_rooms[code] = room
	return _success(_public_room(room, peer_id))


func close_room(room_code: String, session_id: String, peer_id: String, now_unix: int = -1) -> Dictionary:
	var code := normalize_room_code(room_code)
	var lookup := _lookup(code, now_unix)
	if not bool(lookup.get("ok", false)):
		return lookup
	var room: Dictionary = lookup["room"]
	if str(room["session_id"]) != session_id or str(room["host_peer_id"]) != peer_id:
		return _error("NOT_AUTHORIZED", "Only the room host can close this room.")
	_rooms.erase(code)
	_session_rooms.erase(session_id)
	return _success({"room_code": code, "closed": true})


func prune_expired(now_unix: int = -1) -> int:
	var now := _now(now_unix)
	var removed := 0
	for room_code: String in _rooms.keys():
		var room: Dictionary = _rooms[room_code]
		if now >= int(room.get("expires_at", 0)):
			_session_rooms.erase(str(room.get("session_id", "")))
			_rooms.erase(room_code)
			removed += 1
	return removed


func room_count() -> int:
	return _rooms.size()


static func normalize_room_code(value: String) -> String:
	return value.strip_edges().to_upper().replace("-", "").replace(" ", "")


static func is_valid_room_code(value: String) -> bool:
	var code := normalize_room_code(value)
	if code.length() != ROOM_CODE_LENGTH:
		return false
	for index in code.length():
		if ROOM_CODE_ALPHABET.find(code[index]) < 0:
			return false
	return true


func _lookup(room_code: String, now_unix: int) -> Dictionary:
	if not is_valid_room_code(room_code):
		return _error("INVALID_ROOM_CODE", "Enter a valid 6-character room code.")
	var now := _now(now_unix)
	if not _rooms.has(room_code):
		return _error("ROOM_NOT_FOUND", "Room not found.")
	var room: Dictionary = _rooms[room_code]
	if now >= int(room.get("expires_at", 0)):
		_rooms.erase(room_code)
		_session_rooms.erase(str(room.get("session_id", "")))
		return _error("ROOM_EXPIRED", "This room has expired.")
	return {"ok": true, "room": room}


func _validate_identity(payload: Dictionary) -> Dictionary:
	if typeof(payload.get("protocol_version")) != TYPE_INT or int(payload.get("protocol_version", 0)) <= 0:
		return _error("INVALID_PAYLOAD", "A positive protocol version is required.")
	if typeof(payload.get("game_id")) != TYPE_STRING:
		return _error("INVALID_PAYLOAD", "A game identity is required.")
	var game_id := str(payload.get("game_id", ""))
	if game_id.is_empty() or game_id.length() > MAX_GAME_ID_LENGTH:
		return _error("INVALID_PAYLOAD", "The game identity is invalid.")
	for index in game_id.length():
		var code := game_id.unicode_at(index)
		if not ((code >= 97 and code <= 122) or (code >= 48 and code <= 57) or code == 95):
			return _error("INVALID_PAYLOAD", "The game identity is invalid.")
	return {"ok": true}


func _validate_endpoint(value: Variant, observed_address: String, require_port: bool) -> Dictionary:
	if not value is Dictionary:
		return _error("INVALID_PAYLOAD", "Peer endpoint metadata is invalid.")
	var endpoint: Dictionary = value
	if endpoint.size() > 3 or str(endpoint.get("transport", "")) != TRANSPORT_ID:
		return _error("INVALID_PAYLOAD", "Only ENet UDP endpoint metadata is accepted.")
	if typeof(endpoint.get("port")) != TYPE_INT:
		return _error("INVALID_PAYLOAD", "Peer endpoint port is invalid.")
	var port := int(endpoint.get("port", -1))
	if port < (1 if require_port else 0) or port > 65535:
		return _error("INVALID_PAYLOAD", "Peer endpoint port is invalid.")
	var address := observed_address.strip_edges()
	if address.is_empty():
		address = str(endpoint.get("address", "")).strip_edges()
	if address.is_empty() or address.length() > MAX_ADDRESS_LENGTH or address.contains("/") or address.contains("\\"):
		return _error("INVALID_PAYLOAD", "Peer endpoint address is invalid.")
	return {"ok": true, "endpoint": {"transport": TRANSPORT_ID, "address": address, "port": port}}


func _validate_local_candidates(value: Variant) -> Dictionary:
	if not value is Array:
		return _error("INVALID_PAYLOAD", "Local endpoint candidates are invalid.")
	var values: Array = value
	if values.size() > 4:
		return _error("INVALID_PAYLOAD", "Local endpoint candidates are invalid.")
	var validated: Array[Dictionary] = []
	for candidate_value in values:
		if not candidate_value is Dictionary:
			return _error("INVALID_PAYLOAD", "Local endpoint candidates are invalid.")
		var candidate: Dictionary = candidate_value
		if candidate.size() != 2 or typeof(candidate.get("address")) != TYPE_STRING or typeof(candidate.get("port")) != TYPE_INT:
			return _error("INVALID_PAYLOAD", "Local endpoint candidates are invalid.")
		var address := str(candidate["address"]).strip_edges()
		var port := int(candidate["port"])
		if not address.is_valid_ip_address() or port < 1 or port > 65535:
			return _error("INVALID_PAYLOAD", "Local endpoint candidates are invalid.")
		validated.append({"address": address, "port": port})
	return {"ok": true, "candidates": validated}


func _authorized(room: Dictionary, session_id: String, peer_id: String) -> bool:
	return (
		not session_id.is_empty()
		and session_id == str(room.get("session_id", ""))
		and peer_id in [str(room.get("host_peer_id", "")), str(room.get("guest_peer_id", ""))]
	)


func _public_room(room: Dictionary, requesting_peer_id: String) -> Dictionary:
	var is_host := requesting_peer_id == str(room["host_peer_id"])
	return {
		"room_code": str(room["room_code"]),
		"session_id": str(room["session_id"]),
		"peer_id": requesting_peer_id,
		"probe_id": str(room["host_probe_id"] if is_host else room["guest_probe_id"]),
		"opponent_probe_id": str(room["guest_probe_id"] if is_host else room["host_probe_id"]),
		"traversal_token": str(room["traversal_token"]),
		"host_endpoint": Dictionary(room["host_endpoint"]).duplicate(true),
		"guest_endpoint": Dictionary(room["guest_endpoint"]).duplicate(true),
		"protocol_version": int(room["protocol_version"]),
		"game_id": str(room["game_id"]),
		"created_at": int(room["created_at"]),
		"expires_at": int(room["expires_at"]),
		"opponent_connected": not str(room["guest_peer_id"]).is_empty(),
		"host_udp_registered": bool(room.get("host_udp_registered", false)),
		"guest_udp_registered": bool(room.get("guest_udp_registered", false)),
		"host_local_candidates": Array(room.get("host_local_candidates", [])).duplicate(true),
		"guest_local_candidates": Array(room.get("guest_local_candidates", [])).duplicate(true),
		"host_candidates_submitted": bool(room.get("host_candidates_submitted", false)),
		"guest_candidates_submitted": bool(room.get("guest_candidates_submitted", false)),
	}


func _new_room_code() -> String:
	for _attempt in 64:
		var bytes := _crypto.generate_random_bytes(ROOM_CODE_LENGTH)
		var code := ""
		for byte in bytes:
			code += ROOM_CODE_ALPHABET[int(byte) % ROOM_CODE_ALPHABET.length()]
		if not _rooms.has(code):
			return code
	return ""


func _random_hex(byte_count: int) -> String:
	return _crypto.generate_random_bytes(byte_count).hex_encode()


func _now(override_value: int) -> int:
	return override_value if override_value >= 0 else int(Time.get_unix_time_from_system())


func _success(data: Dictionary) -> Dictionary:
	return {"ok": true, "data": data}


func _error(code: String, message: String) -> Dictionary:
	return {"ok": false, "error_code": code, "user_message": message}
