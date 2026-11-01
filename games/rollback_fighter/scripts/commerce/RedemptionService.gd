extends Node
class_name RollbackFighterRedemptionService

const STATUS_SUCCESS := "SUCCESS"
const STATUS_INVALID_CODE := "INVALID_CODE"
const STATUS_ALREADY_REDEEMED := "ALREADY_REDEEMED"
const STATUS_UNKNOWN_PRODUCT := "UNKNOWN_PRODUCT"
const STATUS_EMPTY_CODE := "EMPTY_CODE"
const STATUS_ENTITLEMENT_GRANT_FAILED := "ENTITLEMENT_GRANT_FAILED"
const CANONICAL_URI_PREFIX := "hyperreality://redeem?"
const PRODUCT_CATALOG_PATH := "res://games/rollback_fighter/config/products.json"
const CODE_REGISTRY_PATH := (
	"res://games/rollback_fighter/config/development_redemption_codes.json"
)
const ProductCatalogScript = preload(
	"res://games/rollback_fighter/scripts/commerce/ProductCatalog.gd"
)

var _catalog
var _entitlement_service
var _codes: Dictionary = {}
var _redeemed_codes: Dictionary = {}


func _ready() -> void:
	if _catalog == null:
		_catalog = ProductCatalogScript.new()
		_catalog.load_catalog(PRODUCT_CATALOG_PATH)
	if _entitlement_service == null:
		_entitlement_service = get_node_or_null("/root/EntitlementService")
	if _codes.is_empty():
		load_code_registry(CODE_REGISTRY_PATH)


func configure(catalog, entitlement_service) -> void:
	_catalog = catalog
	_entitlement_service = entitlement_service


func load_code_registry(path: String) -> bool:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return false
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary:
		return false
	var entries: Variant = Dictionary(parsed).get("codes", [])
	if not entries is Array:
		return false
	var loaded: Dictionary = {}
	for entry_value: Variant in entries:
		if not entry_value is Dictionary:
			return false
		var entry: Dictionary = entry_value
		var code: String = normalize_input(str(entry.get("code", "")))
		var product_id: String = str(entry.get("product_id", "")).strip_edges()
		if code.is_empty() or product_id.is_empty() or loaded.has(code):
			return false
		loaded[code] = product_id
	_codes = loaded
	return true


func redeem(input: String) -> Dictionary:
	var code: String = normalize_input(input)
	if code.is_empty():
		return _result(false, STATUS_EMPTY_CODE, "")
	if not _codes.has(code):
		return _result(false, STATUS_INVALID_CODE, "")
	var product_id: String = str(_codes[code])
	if _redeemed_codes.has(code):
		return _result(false, STATUS_ALREADY_REDEEMED, product_id)
	if _catalog == null or _catalog.get_product(product_id) == null:
		return _result(false, STATUS_UNKNOWN_PRODUCT, product_id)
	if (
		_entitlement_service == null
		or not _entitlement_service.has_method("grant_entitlement")
		or not bool(_entitlement_service.call("grant_entitlement", product_id))
	):
		return _result(false, STATUS_ENTITLEMENT_GRANT_FAILED, product_id)
	_redeemed_codes[code] = true
	return _result(true, STATUS_SUCCESS, product_id)


func normalize_input(input: String) -> String:
	var value: String = input.strip_edges()
	if value.is_empty():
		return ""
	if value.to_lower().begins_with(CANONICAL_URI_PREFIX):
		var query: String = value.substr(CANONICAL_URI_PREFIX.length())
		for pair: String in query.split("&", false):
			var parts: PackedStringArray = pair.split("=", true, 1)
			if parts.size() == 2 and parts[0].uri_decode().to_lower() == "code":
				return parts[1].uri_decode().strip_edges().to_upper()
		return ""
	return value.to_upper()


func _result(success: bool, status: String, product_id: String) -> Dictionary:
	return {
		"success": success,
		"status": status,
		"product_id": product_id,
	}


# This local static registry is prototype data, not a security boundary. Production
# redemption requires issuance and validation by a server or equivalent trusted authority.
