extends RefCounted
class_name OceanFightSessionAdapter

const Registry = preload("res://games/rollback_fighter/scripts/net/multiplayer/ConnectionMethodRegistry.gd")
const Profile = preload("res://games/rollback_fighter/scripts/net/multiplayer/GameNetworkingProfile.gd")
const Session = preload("res://games/rollback_fighter/scripts/net/multiplayer/MultiplayerSession.gd")
const SessionPlayer = preload("res://games/rollback_fighter/scripts/net/multiplayer/SessionPlayer.gd")
const Topology = preload("res://games/rollback_fighter/scripts/net/multiplayer/NetworkTopology.gd")


# Read-only adapter for representing the existing 1v1 launch as a generalized
# session. The gameplay and rollback paths continue consuming the legacy launch.
static func from_legacy_launch(launch: Dictionary) -> RollbackFighterMultiplayerSession:
	if str(launch.get("mode", "")) not in ["host", "client"]:
		return null
	var profile := Profile.ocean_fight()
	var signaling: Dictionary = launch.get("signaling", {})
	var session := Session.new()
	session.session_id = str(signaling.get("session_id", "direct_ip_pending"))
	session.connection_method_id = (
		Registry.ROOM_CODE_P2P if not signaling.is_empty() else Registry.DIRECT_IP_VPN
	)
	session.network_topology = Topology.P2P
	session.game_id = profile.game_id
	session.game_mode_id = "ocean_fight_1v1"
	session.ruleset_id = "current"
	session.min_players = profile.min_players
	session.max_players = profile.max_players
	session.host_player_id = "player_1"
	session.local_player_id = "player_1" if str(launch.get("mode")) == "host" else "player_2"
	session.add_player(SessionPlayer.new().configure("player_1", 1, 0, "Player 1"))
	session.add_player(SessionPlayer.new().configure("player_2", 0, 1, "Player 2"))
	return session
