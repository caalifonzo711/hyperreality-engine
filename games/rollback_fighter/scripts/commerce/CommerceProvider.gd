extends RefCounted
class_name RollbackFighterCommerceProvider

const STATUS_SUCCESS := "SUCCESS"
const STATUS_PRODUCT_NOT_FOUND := "PRODUCT_NOT_FOUND"
const STATUS_PURCHASE_CANCELLED := "PURCHASE_CANCELLED"
const STATUS_PURCHASE_FAILED := "PURCHASE_FAILED"
const STATUS_ALREADY_OWNED := "ALREADY_OWNED"
const STATUS_PROVIDER_UNAVAILABLE := "PROVIDER_UNAVAILABLE"


func get_provider_id() -> String:
	return "unavailable"


func purchase(product_id: String) -> Dictionary:
	return make_result(
		false,
		STATUS_PROVIDER_UNAVAILABLE,
		product_id,
		get_provider_id(),
		""
	)


func supports_restore() -> bool:
	return false


func restore_purchases() -> Array[Dictionary]:
	return []


func make_result(
	success: bool,
	status: String,
	product_id: String,
	provider_id: String,
	transaction_id: String
) -> Dictionary:
	return {
		"success": success,
		"status": status,
		"product_id": product_id,
		"provider_id": provider_id,
		"transaction_id": transaction_id,
	}
