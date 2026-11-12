extends RefCounted
class_name RollbackFighterMultiplayerSession

const STATE_FORMING := "FORMING"
const STATE_READY := "READY"
const STATE_ACTIVE := "ACTIVE"
const STATE_ENDED := "ENDED"

var session_id: String = ""
var players: Array[RollbackFighterSessionPlayer] = []
var local_player_id: String = ""
var host_player_id: String = ""
var connection_method_id: String = ""
var network_topology: String = ""
var game_id: String = ""
var game_mode_id: String = ""
var ruleset_id: String = ""
var min_players: int = 2
var max_players: int = 2
var state: String = STATE_FORMING


func add_player(player: RollbackFighterSessionPlayer) -> bool:
	if player == null or player.player_id.is_empty() or player.slot < 0 or players.size() >= max_players:
		return false
	for existing: RollbackFighterSessionPlayer in players:
		if existing.player_id == player.player_id or existing.slot == player.slot:
			return false
	players.append(player)
	return true


func get_player(player_id: String) -> RollbackFighterSessionPlayer:
	for player: RollbackFighterSessionPlayer in players:
		if player.player_id == player_id:
			return player
	return null


func validate() -> Array[String]:
	var errors: Array[String] = []
	if session_id.is_empty():
		errors.append("session_id is required")
	if min_players < 2 or max_players < min_players:
		errors.append("player limits are invalid")
	if players.size() > max_players:
		errors.append("session exceeds max_players")
	if get_player(local_player_id) == null:
		errors.append("local_player_id must identify a session player")
	if get_player(host_player_id) == null:
		errors.append("host_player_id must identify a session player")
	if not RollbackFighterNetworkTopology.is_valid(network_topology):
		errors.append("network_topology is invalid")
	return errors


func to_dictionary() -> Dictionary:
	var serialized_players: Array[Dictionary] = []
	for player: RollbackFighterSessionPlayer in players:
		serialized_players.append(player.to_dictionary())
	return {
		"session_id": session_id,
		"players": serialized_players,
		"local_player_id": local_player_id,
		"host_player_id": host_player_id,
		"connection_method_id": connection_method_id,
		"network_topology": network_topology,
		"game_id": game_id,
		"game_mode_id": game_mode_id,
		"ruleset_id": ruleset_id,
		"min_players": min_players,
		"max_players": max_players,
		"state": state,
	}
