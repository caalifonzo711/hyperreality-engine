extends RollbackFighterConnectionProvider
class_name NatTraversalConnectionProvider


func get_provider_id() -> String:
	return NAT_TRAVERSAL_PROVIDER_ID


func get_connection_method_ids() -> Array[String]:
	return ["room_code_p2p"]


func is_runtime_available() -> bool:
	return true


func get_existing_runtime_components() -> Array[String]:
	return [
		"res://games/rollback_fighter/scripts/signaling/SignalingClient.gd",
		"res://games/rollback_fighter/scripts/net/NatTraversalCoordinator.gd",
		"res://games/rollback_fighter/scripts/net/ENetTransport.gd",
	]
