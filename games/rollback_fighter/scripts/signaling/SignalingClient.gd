extends Node
class_name RollbackFighterSignalingClient

const RoomStoreScript = preload("res://games/rollback_fighter/scripts/signaling/SignalingRoomStore.gd")
const DEFAULT_BASE_URL := "http://127.0.0.1:8787"
const DEFAULT_TIMEOUT_SECONDS := 8.0
const MAX_RESPONSE_BYTES := 16384

var base_url: String = DEFAULT_BASE_URL
var timeout_seconds: float = DEFAULT_TIMEOUT_SECONDS


func configure(server_base_url: String, request_timeout_seconds: float = DEFAULT_TIMEOUT_SECONDS) -> bool:
	var normalized := server_base_url.strip_edges().trim_suffix("/")
	if not (normalized.begins_with("http://") or normalized.begins_with("https://")):
		return false
	base_url = normalized
	timeout_seconds = clampf(request_timeout_seconds, 1.0, 30.0)
	return true


func create_room(endpoint: Dictionary, identity: Dictionary) -> Dictionary:
	return await _request_json(HTTPClient.METHOD_POST, "/rooms", {
		"protocol_version": identity.get("protocol_version", 0),
		"game_id": identity.get("game_id", ""),
		"endpoint": endpoint,
	})


func join_room(room_code: String, endpoint: Dictionary, identity: Dictionary) -> Dictionary:
	var code := RoomStoreScript.normalize_room_code(room_code)
	return await _request_json(HTTPClient.METHOD_POST, "/rooms/%s/join" % code, {
		"protocol_version": identity.get("protocol_version", 0),
		"game_id": identity.get("game_id", ""),
		"endpoint": endpoint,
	})


func get_room(room_code: String, session_id: String, peer_id: String) -> Dictionary:
	return await _request_json(
		HTTPClient.METHOD_GET,
		"/rooms/%s" % RoomStoreScript.normalize_room_code(room_code),
		{},
		_auth_headers(session_id, peer_id)
	)


func update_peer(room_code: String, session_id: String, peer_id: String, endpoint: Dictionary) -> Dictionary:
	return await _request_json(
		HTTPClient.METHOD_POST,
		"/rooms/%s/peer" % RoomStoreScript.normalize_room_code(room_code),
		{"endpoint": endpoint},
		_auth_headers(session_id, peer_id)
	)


func update_local_candidates(room_code: String, session_id: String, peer_id: String, candidates: Array[Dictionary]) -> Dictionary:
	return await _request_json(
		HTTPClient.METHOD_POST,
		"/rooms/%s/candidates" % RoomStoreScript.normalize_room_code(room_code),
		{"candidates": candidates},
		_auth_headers(session_id, peer_id)
	)


func close_room(room_code: String, session_id: String, peer_id: String) -> Dictionary:
	return await _request_json(
		HTTPClient.METHOD_DELETE,
		"/rooms/%s" % RoomStoreScript.normalize_room_code(room_code),
		{},
		_auth_headers(session_id, peer_id)
	)


func _request_json(method: int, path: String, body: Dictionary, extra_headers: PackedStringArray = PackedStringArray()) -> Dictionary:
	if not is_inside_tree():
		return _error("SIGNALING_UNAVAILABLE", "Signaling client is not active.")
	var request := HTTPRequest.new()
	request.timeout = timeout_seconds
	request.download_chunk_size = MAX_RESPONSE_BYTES
	add_child(request)
	var headers := PackedStringArray(["Accept: application/json", "Content-Type: application/json"])
	for header in extra_headers:
		headers.append(header)
	var request_body := "" if method in [HTTPClient.METHOD_GET, HTTPClient.METHOD_DELETE] else JSON.stringify(body)
	var start_error := request.request(base_url + path, headers, method, request_body)
	if start_error != OK:
		request.queue_free()
		return _error("SIGNALING_UNAVAILABLE", "Could not contact the signaling server.")
	var response: Array = await request.request_completed
	request.queue_free()
	if response.size() != 4:
		return _error("INVALID_RESPONSE", "The signaling server returned an invalid response.")
	var result_code := int(response[0])
	var http_code := int(response[1])
	var response_body: PackedByteArray = response[3]
	if result_code == HTTPRequest.RESULT_TIMEOUT:
		return _error("TIMEOUT", "The signaling request timed out.")
	if result_code != HTTPRequest.RESULT_SUCCESS:
		return _error("SIGNALING_UNAVAILABLE", "The signaling server is unavailable.")
	if response_body.size() > MAX_RESPONSE_BYTES:
		return _error("INVALID_RESPONSE", "The signaling response was too large.")
	var parsed: Variant = JSON.parse_string(response_body.get_string_from_utf8())
	if not parsed is Dictionary:
		return _error("INVALID_RESPONSE", "The signaling server returned an invalid response.")
	var result: Dictionary = parsed
	if http_code >= 200 and http_code < 300 and bool(result.get("ok", false)):
		return result
	return _error(
		str(result.get("error_code", "SIGNALING_UNAVAILABLE")),
		str(result.get("user_message", "The signaling request failed."))
	)


func _auth_headers(session_id: String, peer_id: String) -> PackedStringArray:
	return PackedStringArray(["X-Session-Id: %s" % session_id, "X-Peer-Id: %s" % peer_id])


func _error(code: String, message: String) -> Dictionary:
	return {"ok": false, "error_code": code, "user_message": message}
