extends RefCounted
class_name RollbackFighterConnectionProvider

# Provider IDs identify connection setup/runtime adapters. Discovery (for example,
# a LAN address or room code) remains separate from the match topology.
const DIRECT_IP_PROVIDER_ID := "direct_ip"
const NAT_TRAVERSAL_PROVIDER_ID := "nat_traversal"

# Reserved metadata IDs only. No runtime implementation exists for these providers.
const RELAY_PROVIDER_ID := "relay"
const BLUETOOTH_PROVIDER_ID := "bluetooth"
const STEAM_PROVIDER_ID := "steam"
const MANAGED_ONLINE_PROVIDER_ID := "managed_online"
const DEDICATED_SERVER_PROVIDER_ID := "dedicated_server"

const RELAY_PROVIDER_TYPE := "RelayConnectionProvider"
const BLUETOOTH_PROVIDER_TYPE := "BluetoothConnectionProvider"
const STEAM_PROVIDER_TYPE := "SteamConnectionProvider"


func get_provider_id() -> String:
	return ""


func get_connection_method_ids() -> Array[String]:
	return []


func is_runtime_available() -> bool:
	return false


func get_existing_runtime_components() -> Array[String]:
	return []
