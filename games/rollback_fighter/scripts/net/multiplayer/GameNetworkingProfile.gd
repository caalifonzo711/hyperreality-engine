extends RefCounted
class_name RollbackFighterGameNetworkingProfile

var game_id: String = ""
var min_players: int = 2
var max_players: int = 2
var supported_connection_methods: Array[String] = []
var supported_topologies: Array[String] = []
var default_connection_method: String = ""
var default_topology: String = ""


func supports_connection_method(method_id: String) -> bool:
	return method_id in supported_connection_methods


func supports_topology(topology_id: String) -> bool:
	return topology_id in supported_topologies


func validate() -> Array[String]:
	var errors: Array[String] = []
	if game_id.is_empty():
		errors.append("game_id is required")
	if min_players < 2 or max_players < min_players:
		errors.append("player limits are invalid")
	if not supports_connection_method(default_connection_method):
		errors.append("default_connection_method must be supported")
	if not supports_topology(default_topology):
		errors.append("default_topology must be supported")
	for topology_id: String in supported_topologies:
		if not RollbackFighterNetworkTopology.is_valid(topology_id):
			errors.append("unknown topology: %s" % topology_id)
	return errors


static func ocean_fight() -> RollbackFighterGameNetworkingProfile:
	var profile := RollbackFighterGameNetworkingProfile.new()
	profile.game_id = "rollback_fighter"
	profile.min_players = 2
	profile.max_players = 2
	profile.supported_connection_methods = ["lan", "direct_ip_vpn", "room_code_p2p"]
	profile.supported_topologies = [RollbackFighterNetworkTopology.P2P]
	profile.default_connection_method = "lan"
	profile.default_topology = RollbackFighterNetworkTopology.P2P
	return profile
