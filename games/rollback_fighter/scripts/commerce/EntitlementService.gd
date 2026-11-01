extends Node
class_name RollbackFighterEntitlementService

var _entitlements: Dictionary = {}


func has_entitlement(product_id: String) -> bool:
	return not product_id.is_empty() and _entitlements.has(product_id)


func grant_entitlement(product_id: String) -> bool:
	if product_id.is_empty():
		return false
	_entitlements[product_id] = true
	return true


func revoke_entitlement(product_id: String) -> bool:
	if product_id.is_empty():
		return false
	_entitlements.erase(product_id)
	return true
