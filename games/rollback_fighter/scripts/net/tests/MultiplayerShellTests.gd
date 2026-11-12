extends SceneTree

const Registry = preload("res://games/rollback_fighter/scripts/net/multiplayer/ConnectionMethodRegistry.gd")
const Definition = preload("res://games/rollback_fighter/scripts/net/multiplayer/ConnectionMethodDefinition.gd")
const ProfileRegistry = preload("res://games/rollback_fighter/scripts/net/multiplayer/GameNetworkingProfileRegistry.gd")
const Session = preload("res://games/rollback_fighter/scripts/net/multiplayer/MultiplayerSession.gd")
const SessionPlayer = preload("res://games/rollback_fighter/scripts/net/multiplayer/SessionPlayer.gd")
const Topology = preload("res://games/rollback_fighter/scripts/net/multiplayer/NetworkTopology.gd")
const OceanFightAdapter = preload("res://games/rollback_fighter/scripts/net/multiplayer/OceanFightSessionAdapter.gd")


func _initialize() -> void:
	var registry = Registry.create_default()
	assert(registry.get_definitions().size() == 8)
	assert(registry.get_definition(Registry.LAN).availability == Definition.AVAILABLE)
	assert(registry.get_definition(Registry.DIRECT_IP_VPN).is_launchable())
	assert(registry.get_definition(Registry.ROOM_CODE_P2P).availability == Definition.EXPERIMENTAL)
	for method_id: String in [Registry.RELAY, Registry.BLUETOOTH, Registry.STEAM, Registry.MANAGED_ONLINE, Registry.DEDICATED_SERVER]:
		assert(not registry.get_definition(method_id).is_launchable())

	var profile_registry = ProfileRegistry.create_default()
	var ocean_fight = profile_registry.get_profile("rollback_fighter")
	assert(ocean_fight.validate().is_empty())
	assert(ocean_fight.min_players == 2)
	assert(ocean_fight.max_players == 2)
	assert(ocean_fight.supported_topologies == [Topology.P2P])
	assert(ocean_fight.supported_connection_methods == [Registry.LAN, Registry.DIRECT_IP_VPN, Registry.ROOM_CODE_P2P])
	var current_match = OceanFightAdapter.from_legacy_launch({
		"mode": "host",
		"address": "",
		"port": 7777,
		"connection_mode": "DIRECT_IP",
	})
	assert(current_match.players.size() == 2)
	assert(current_match.max_players == 2)
	assert(current_match.network_topology == Topology.P2P)
	assert(current_match.validate().is_empty())

	var future_session = Session.new()
	future_session.session_id = "four-player-structure-test"
	future_session.local_player_id = "player_1"
	future_session.host_player_id = "player_1"
	future_session.connection_method_id = Registry.LAN
	future_session.network_topology = Topology.P2P_MESH
	future_session.game_id = "future_game"
	future_session.game_mode_id = "default"
	future_session.ruleset_id = "default"
	future_session.min_players = 2
	future_session.max_players = 4
	for slot: int in 4:
		assert(future_session.add_player(SessionPlayer.new().configure(
			"player_%d" % (slot + 1), slot + 1, slot, "Player %d" % (slot + 1)
		)))
	assert(future_session.players.size() == 4)
	assert(future_session.validate().is_empty())

	print("[MultiplayerShellTests] PASS")
	quit(0)
