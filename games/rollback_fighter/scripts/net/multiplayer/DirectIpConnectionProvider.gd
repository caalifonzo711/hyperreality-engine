extends RollbackFighterConnectionProvider
class_name DirectIpConnectionProvider


func get_provider_id() -> String:
	return DIRECT_IP_PROVIDER_ID


func get_connection_method_ids() -> Array[String]:
	return ["lan", "direct_ip_vpn"]


func is_runtime_available() -> bool:
	return true


func get_existing_runtime_components() -> Array[String]:
	return [
		"res://games/rollback_fighter/scripts/net/NetworkLaunchConfig.gd",
		"res://games/rollback_fighter/scripts/net/ENetTransport.gd",
	]
