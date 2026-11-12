extends RefCounted
class_name RollbackFighterConnectionMethodRegistry

const Definition = preload("res://games/rollback_fighter/scripts/net/multiplayer/ConnectionMethodDefinition.gd")
const Provider = preload("res://games/rollback_fighter/scripts/net/multiplayer/ConnectionProvider.gd")
const Topology = preload("res://games/rollback_fighter/scripts/net/multiplayer/NetworkTopology.gd")

const LAN := "lan"
const DIRECT_IP_VPN := "direct_ip_vpn"
const ROOM_CODE_P2P := "room_code_p2p"
const RELAY := "relay"
const BLUETOOTH := "bluetooth"
const STEAM := "steam"
const MANAGED_ONLINE := "managed_online"
const DEDICATED_SERVER := "dedicated_server"

var _definitions: Dictionary = {}


static func create_default() -> RollbackFighterConnectionMethodRegistry:
	var registry := RollbackFighterConnectionMethodRegistry.new()
	registry._register_defaults()
	return registry


func register_definition(definition: RollbackFighterConnectionMethodDefinition) -> bool:
	if definition == null or not definition.validate().is_empty() or _definitions.has(definition.id):
		return false
	_definitions[definition.id] = definition
	return true


func get_definition(method_id: String) -> RollbackFighterConnectionMethodDefinition:
	return _definitions.get(method_id)


func get_definitions() -> Array[RollbackFighterConnectionMethodDefinition]:
	var result: Array[RollbackFighterConnectionMethodDefinition] = []
	for value: Variant in _definitions.values():
		result.append(value)
	result.sort_custom(func(a, b): return a.sort_order < b.sort_order)
	return result


func _register_defaults() -> void:
	register_definition(_definition(LAN, "SAME WIFI / LAN", "Local network play", Definition.AVAILABLE, Provider.DIRECT_IP_PROVIDER_ID, [Topology.P2P], 2, 10))
	register_definition(_definition(DIRECT_IP_VPN, "DIRECT IP / VPN", "Examples: LAN IP, Tailscale, ZeroTier", Definition.AVAILABLE, Provider.DIRECT_IP_PROVIDER_ID, [Topology.P2P], 2, 20))
	register_definition(_definition(ROOM_CODE_P2P, "ROOM CODE", "Automatic internet P2P / NAT traversal", Definition.EXPERIMENTAL, Provider.NAT_TRAVERSAL_PROVIDER_ID, [Topology.P2P], 2, 30))
	register_definition(_definition(RELAY, "RELAY", "Relay-assisted connectivity", Definition.COMING_SOON, Provider.RELAY_PROVIDER_ID, [Topology.RELAY], 4, 40))
	register_definition(_definition(BLUETOOTH, "BLUETOOTH / LOCAL WIRELESS", "Nearby device connectivity", Definition.COMING_SOON, Provider.BLUETOOTH_PROVIDER_ID, [Topology.P2P, Topology.P2P_MESH], 4, 50))
	register_definition(_definition(STEAM, "STEAM", "Steam connectivity", Definition.COMING_SOON, Provider.STEAM_PROVIDER_ID, [Topology.P2P, Topology.RELAY], 4, 60))
	register_definition(_definition(MANAGED_ONLINE, "MANAGED ONLINE", "Nakama / Hyperworld / other provider", Definition.COMING_SOON, Provider.MANAGED_ONLINE_PROVIDER_ID, [Topology.HOST_AUTHORITY, Topology.RELAY], 4, 70))
	register_definition(_definition(DEDICATED_SERVER, "DEDICATED SERVER", "Server-hosted matches", Definition.COMING_SOON, Provider.DEDICATED_SERVER_PROVIDER_ID, [Topology.DEDICATED_SERVER], 32, 80))


func _definition(
	method_id: String,
	display_name: String,
	description: String,
	availability: String,
	provider_id: String,
	topologies: Array[String],
	max_players_hint: int,
	sort_order: int
) -> RollbackFighterConnectionMethodDefinition:
	return Definition.new().configure(
		method_id,
		display_name,
		description,
		availability,
		provider_id,
		topologies,
		max_players_hint,
		sort_order
	)
