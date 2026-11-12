extends Node

const MODE_HOST := "host"
const MODE_CLIENT := "client"
const MODE_SINGLE_PLAYER := "single_player"
const DEFAULT_P1_FIGHTER_ID := "example_fighter"
const DEFAULT_P2_FIGHTER_ID := "example_fighter_alt"

var _mode: String = ""
var _address: String = ""
var _port: int = 0
var _p1_fighter_id: String = DEFAULT_P1_FIGHTER_ID
var _p2_fighter_id: String = DEFAULT_P2_FIGHTER_ID
var _signaling_room: Dictionary = {}
var _local_port: int = 0
var _connection_mode: String = ""


func set_host(port: int) -> bool:
	if not _valid_port(port):
		clear()
		return false
	_mode = MODE_HOST
	_address = ""
	_port = port
	_signaling_room.clear()
	_local_port = 0
	_connection_mode = "DIRECT_IP"
	_reset_fighter_selection()
	return true


func set_client(address: String, port: int) -> bool:
	var normalized_address: String = address.strip_edges()
	if normalized_address.is_empty() or not _valid_port(port):
		clear()
		return false
	_mode = MODE_CLIENT
	_address = normalized_address
	_port = port
	_signaling_room.clear()
	_local_port = 0
	_connection_mode = "DIRECT_IP"
	_reset_fighter_selection()
	return true


func set_single_player() -> void:
	_mode = MODE_SINGLE_PLAYER
	_address = ""
	_port = 0
	_signaling_room.clear()
	_local_port = 0
	_connection_mode = "LOCAL"
	_reset_fighter_selection()


func set_fighter_selection(p1_id: String, p2_id: String) -> bool:
	if not _valid_fighter_id(p1_id) or not _valid_fighter_id(p2_id):
		return false
	_p1_fighter_id = p1_id
	_p2_fighter_id = p2_id
	return true


func set_signaling_room(context: Dictionary) -> bool:
	if not _valid_signaling_context(context):
		_signaling_room.clear()
		return false
	_signaling_room = context.duplicate(true)
	return true


func get_signaling_room() -> Dictionary:
	return _signaling_room.duplicate(true)


func set_online_client(context: Dictionary) -> bool:
	if not _valid_signaling_context(context):
		clear()
		return false
	_mode = MODE_CLIENT
	_address = ""
	_port = 0
	_local_port = 0
	_connection_mode = "TRAVERSING"
	_signaling_room = context.duplicate(true)
	_reset_fighter_selection()
	return true


func set_online_host(port: int, context: Dictionary) -> bool:
	if not _valid_port(port) or not _valid_signaling_context(context):
		clear()
		return false
	_mode = MODE_HOST
	_address = ""
	_port = port
	_local_port = port
	_connection_mode = "TRAVERSING"
	_signaling_room = context.duplicate(true)
	_reset_fighter_selection()
	return true


func set_traversal_result(result: Dictionary) -> bool:
	if str(result.get("connection_mode", "")) != "DIRECT":
		return false
	var local_port := int(result.get("local_port", 0))
	var peer_address := str(result.get("peer_address", "")).strip_edges()
	var peer_port := int(result.get("peer_port", 0))
	if not _valid_port(local_port) or peer_address.is_empty() or not _valid_port(peer_port):
		return false
	_local_port = local_port
	_connection_mode = "DIRECT"
	if _mode == MODE_HOST:
		_port = local_port
		_address = ""
	elif _mode == MODE_CLIENT:
		_address = peer_address
		_port = peer_port
	else:
		return false
	return true


func get_pending_launch() -> Dictionary:
	if _mode.is_empty():
		return {}
	var result := {
		"mode": _mode,
		"address": _address,
		"port": _port,
		"p1_fighter_id": _p1_fighter_id,
		"p2_fighter_id": _p2_fighter_id,
		"local_port": _local_port,
		"connection_mode": _connection_mode,
	}
	if not _signaling_room.is_empty():
		result["signaling"] = _signaling_room.duplicate(true)
	return result


func consume() -> Dictionary:
	if _mode == MODE_SINGLE_PLAYER:
		var single_player_result: Dictionary = {
			"mode": _mode,
			"p1_fighter_id": _p1_fighter_id,
			"p2_fighter_id": _p2_fighter_id,
		}
		clear()
		return single_player_result
	if _mode.is_empty() or not _valid_port(_port):
		clear()
		return {}
	var result: Dictionary = {
		"mode": _mode,
		"address": _address,
		"port": _port,
		"p1_fighter_id": _p1_fighter_id,
		"p2_fighter_id": _p2_fighter_id,
		"local_port": _local_port,
		"connection_mode": _connection_mode,
	}
	if not _signaling_room.is_empty():
		result["signaling"] = _signaling_room.duplicate(true)
	clear()
	return result


func clear() -> void:
	_mode = ""
	_address = ""
	_port = 0
	_local_port = 0
	_connection_mode = ""
	_signaling_room.clear()
	_reset_fighter_selection()


func _valid_port(port: int) -> bool:
	return port >= 1 and port <= 65535


func _valid_fighter_id(fighter_id: String) -> bool:
	if fighter_id.is_empty() or fighter_id.length() > 64:
		return false
	var regex: RegEx = RegEx.new()
	regex.compile("^[a-z0-9_]+$")
	return regex.search(fighter_id) != null


func _reset_fighter_selection() -> void:
	_p1_fighter_id = DEFAULT_P1_FIGHTER_ID
	_p2_fighter_id = DEFAULT_P2_FIGHTER_ID


func _valid_signaling_context(context: Dictionary) -> bool:
	for field in ["room_code", "session_id", "peer_id", "server_url"]:
		if typeof(context.get(field)) != TYPE_STRING or str(context.get(field, "")).is_empty():
			return false
	var code := str(context.get("room_code", ""))
	if code.length() != 6:
		return false
	if typeof(context.get("is_host")) != TYPE_BOOL:
		return false
	return true
