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


func set_host(port: int) -> bool:
	if not _valid_port(port):
		clear()
		return false
	_mode = MODE_HOST
	_address = ""
	_port = port
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
	_reset_fighter_selection()
	return true


func set_single_player() -> void:
	_mode = MODE_SINGLE_PLAYER
	_address = ""
	_port = 0
	_reset_fighter_selection()


func set_fighter_selection(p1_id: String, p2_id: String) -> bool:
	if not _valid_fighter_id(p1_id) or not _valid_fighter_id(p2_id):
		return false
	_p1_fighter_id = p1_id
	_p2_fighter_id = p2_id
	return true


func get_pending_launch() -> Dictionary:
	if _mode.is_empty():
		return {}
	return {
		"mode": _mode,
		"address": _address,
		"port": _port,
		"p1_fighter_id": _p1_fighter_id,
		"p2_fighter_id": _p2_fighter_id,
	}


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
	}
	clear()
	return result


func clear() -> void:
	_mode = ""
	_address = ""
	_port = 0
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
