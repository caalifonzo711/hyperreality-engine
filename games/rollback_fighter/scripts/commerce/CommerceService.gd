extends Node
class_name RollbackFighterCommerceService

const STATUS_SUCCESS := "SUCCESS"
const STATUS_PRODUCT_NOT_FOUND := "PRODUCT_NOT_FOUND"
const STATUS_PURCHASE_FAILED := "PURCHASE_FAILED"
const STATUS_ALREADY_OWNED := "ALREADY_OWNED"
const STATUS_PROVIDER_UNAVAILABLE := "PROVIDER_UNAVAILABLE"
const STATUS_RESTORE_UNSUPPORTED := "RESTORE_UNSUPPORTED"
const PRODUCT_CATALOG_PATH := "res://games/rollback_fighter/config/products.json"
const ProductCatalogScript = preload(
	"res://games/rollback_fighter/scripts/commerce/ProductCatalog.gd"
)
const PrototypeProviderScript = preload(
	"res://games/rollback_fighter/scripts/commerce/PrototypeCommerceProvider.gd"
)

var _catalog
var _entitlement_service
var _provider
var _transaction_history: Array[Dictionary] = []
var _reconciled_transaction_ids: Dictionary = {}


func _ready() -> void:
	if _catalog == null:
		_catalog = ProductCatalogScript.new()
		_catalog.load_catalog(PRODUCT_CATALOG_PATH)
	if _entitlement_service == null:
		_entitlement_service = get_node_or_null("/root/EntitlementService")
	if _provider == null:
		_provider = PrototypeProviderScript.new()


func configure(catalog, entitlement_service, provider) -> void:
	_catalog = catalog
	_entitlement_service = entitlement_service
	_provider = provider


func set_provider(provider) -> bool:
	if provider == null or not provider.has_method("purchase"):
		return false
	_provider = provider
	return true


func get_provider_id() -> String:
	if _provider == null or not _provider.has_method("get_provider_id"):
		return ""
	return str(_provider.call("get_provider_id"))


func set_provider_test_mode(mode: String) -> bool:
	return (
		_provider != null
		and _provider.has_method("set_mode")
		and bool(_provider.call("set_mode", mode))
	)


func purchase(product_id: String) -> Dictionary:
	var provider_id: String = get_provider_id()
	if _catalog == null or _catalog.get_product(product_id) == null:
		return _result(false, STATUS_PRODUCT_NOT_FOUND, product_id, provider_id, "")
	if (
		_entitlement_service == null
		or not _entitlement_service.has_method("has_entitlement")
		or not _entitlement_service.has_method("grant_entitlement")
	):
		return _result(false, STATUS_PURCHASE_FAILED, product_id, provider_id, "")
	if bool(_entitlement_service.call("has_entitlement", product_id)):
		return _result(false, STATUS_ALREADY_OWNED, product_id, provider_id, "")
	if _provider == null or not _provider.has_method("purchase"):
		return _result(
			false, STATUS_PROVIDER_UNAVAILABLE, product_id, provider_id, ""
		)
	var provider_result_value: Variant = _provider.call("purchase", product_id)
	if not provider_result_value is Dictionary:
		return _result(false, STATUS_PURCHASE_FAILED, product_id, provider_id, "")
	var provider_result: Dictionary = provider_result_value
	var success: bool = bool(provider_result.get("success", false))
	var status: String = str(provider_result.get("status", STATUS_PURCHASE_FAILED))
	provider_id = str(provider_result.get("provider_id", provider_id))
	var transaction_id: String = str(provider_result.get("transaction_id", ""))
	if not success:
		return _result(false, status, product_id, provider_id, transaction_id)
	if status != STATUS_SUCCESS or provider_id.is_empty() or transaction_id.is_empty():
		return _result(
			false, STATUS_PURCHASE_FAILED, product_id, provider_id, transaction_id
		)
	if not bool(_entitlement_service.call("grant_entitlement", product_id)):
		return _result(
			false, STATUS_PURCHASE_FAILED, product_id, provider_id, transaction_id
		)
	var result: Dictionary = _result(
		true, STATUS_SUCCESS, product_id, provider_id, transaction_id
	)
	_reconciled_transaction_ids[transaction_id] = true
	_transaction_history.append(result.duplicate(true))
	return result


func get_transaction_history() -> Array[Dictionary]:
	return _transaction_history.duplicate(true)


func reconcile_purchases() -> Dictionary:
	var provider_id: String = get_provider_id()
	if (
		_provider == null
		or not _provider.has_method("supports_restore")
		or not bool(_provider.call("supports_restore"))
		or not _provider.has_method("restore_purchases")
	):
		return _reconciliation_result(
			false, STATUS_RESTORE_UNSUPPORTED, provider_id, [], 0, 0
		)
	var restored_value: Variant = _provider.call("restore_purchases")
	if not restored_value is Array:
		return _reconciliation_result(
			false, STATUS_PURCHASE_FAILED, provider_id, [], 0, 0
		)
	var restored_product_ids: Array[String] = []
	var ignored_count: int = 0
	var duplicate_count: int = 0
	for purchase_value: Variant in restored_value:
		if not purchase_value is Dictionary:
			ignored_count += 1
			continue
		var restored: Dictionary = purchase_value
		var product_id: String = str(restored.get("product_id", ""))
		var restored_provider_id: String = str(restored.get("provider_id", ""))
		var transaction_id: String = str(restored.get("transaction_id", ""))
		if (
			not bool(restored.get("success", false))
			or str(restored.get("status", "")) != STATUS_SUCCESS
			or restored_provider_id != provider_id
			or transaction_id.is_empty()
			or _catalog == null
			or _catalog.get_product(product_id) == null
		):
			ignored_count += 1
			continue
		if _reconciled_transaction_ids.has(transaction_id):
			duplicate_count += 1
			continue
		if (
			_entitlement_service == null
			or not _entitlement_service.has_method("grant_entitlement")
			or not bool(_entitlement_service.call("grant_entitlement", product_id))
		):
			ignored_count += 1
			continue
		_reconciled_transaction_ids[transaction_id] = true
		if not restored_product_ids.has(product_id):
			restored_product_ids.append(product_id)
		_transaction_history.append(restored.duplicate(true))
	return _reconciliation_result(
		true,
		STATUS_SUCCESS,
		provider_id,
		restored_product_ids,
		ignored_count,
		duplicate_count
	)


func _reconciliation_result(
	success: bool,
	status: String,
	provider_id: String,
	restored_product_ids: Array[String],
	ignored_count: int,
	duplicate_count: int
) -> Dictionary:
	return {
		"success": success,
		"status": status,
		"provider_id": provider_id,
		"restored_product_ids": restored_product_ids.duplicate(),
		"ignored_count": ignored_count,
		"duplicate_count": duplicate_count,
	}


func _result(
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
