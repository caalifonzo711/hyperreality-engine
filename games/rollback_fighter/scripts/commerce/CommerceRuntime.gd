extends Node
class_name RollbackFighterCommerceRuntime

const PRODUCT_CATALOG_PATH := "res://games/rollback_fighter/config/products.json"
const CODE_REGISTRY_PATH := (
	"res://games/rollback_fighter/config/development_redemption_codes.json"
)
const ProductCatalogScript = preload(
	"res://games/rollback_fighter/scripts/commerce/ProductCatalog.gd"
)
const RedemptionServiceScript = preload(
	"res://games/rollback_fighter/scripts/commerce/RedemptionService.gd"
)
const CommerceServiceScript = preload(
	"res://games/rollback_fighter/scripts/commerce/CommerceService.gd"
)
const PrototypeProviderScript = preload(
	"res://games/rollback_fighter/scripts/commerce/PrototypeCommerceProvider.gd"
)

var _catalog
var _entitlement_service: Node
var _redemption_service: Node
var _commerce_service: Node
var _provider
var _initialized: bool = false


func _ready() -> void:
	_entitlement_service = get_node_or_null("/root/EntitlementService")
	if _entitlement_service == null:
		push_error("[CommerceRuntime] EntitlementService is unavailable.")
		return
	_catalog = ProductCatalogScript.new()
	if not _catalog.load_catalog(PRODUCT_CATALOG_PATH):
		push_error("[CommerceRuntime] Product catalog could not be loaded.")
		return
	_provider = PrototypeProviderScript.new()
	_redemption_service = RedemptionServiceScript.new()
	_redemption_service.name = "RedemptionService"
	_redemption_service.configure(_catalog, _entitlement_service)
	if not _redemption_service.load_code_registry(CODE_REGISTRY_PATH):
		push_error("[CommerceRuntime] Redemption registry could not be loaded.")
		_redemption_service.free()
		_redemption_service = null
		return
	_commerce_service = CommerceServiceScript.new()
	_commerce_service.name = "CommerceService"
	_commerce_service.configure(_catalog, _entitlement_service, _provider)
	add_child(_redemption_service)
	add_child(_commerce_service)
	_initialized = true


func is_initialized() -> bool:
	return _initialized


func get_catalog():
	return _catalog


func get_entitlement_service() -> Node:
	return _entitlement_service


func get_redemption_service() -> Node:
	return _redemption_service


func get_commerce_service() -> Node:
	return _commerce_service


func get_provider():
	return _provider
