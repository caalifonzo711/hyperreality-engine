extends RefCounted
class_name RollbackFighterProductCatalog

const ProductDefinitionScript = preload(
	"res://games/rollback_fighter/scripts/commerce/ProductDefinition.gd"
)

var _products: Dictionary = {}


func load_catalog(path: String) -> bool:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return false
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary:
		return false
	var entries: Variant = Dictionary(parsed).get("products", [])
	if not entries is Array:
		return false
	var loaded: Dictionary = {}
	for entry_value: Variant in entries:
		if not entry_value is Dictionary:
			return false
		var entry: Dictionary = entry_value
		var product = ProductDefinitionScript.new(
			str(entry.get("product_id", "")),
			str(entry.get("display_name", "")),
			str(entry.get("product_type", "")),
			str(entry.get("content_id", "")),
			str(entry.get("display_price", ""))
		)
		if not product.is_valid() or loaded.has(product.product_id):
			return false
		loaded[product.product_id] = product
	_products = loaded
	return true


func register_product(product) -> bool:
	if product == null or not product.is_valid() or _products.has(product.product_id):
		return false
	_products[product.product_id] = product
	return true


func get_product(product_id: String):
	return _products.get(product_id)


func get_product_for_content(content_id: String):
	var product_ids: Array = _products.keys()
	product_ids.sort()
	for product_id: Variant in product_ids:
		var product = _products[product_id]
		if product.content_id == content_id:
			return product
	return null
