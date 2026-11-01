extends RefCounted
class_name RollbackFighterProductDefinition


var product_id: String
var display_name: String
var product_type: String
var content_id: String
var display_price: String


func _init(
	product_id_value: String,
	display_name_value: String,
	product_type_value: String,
	content_id_value: String,
	display_price_value: String
) -> void:
	product_id = product_id_value
	display_name = display_name_value
	product_type = product_type_value
	content_id = content_id_value
	display_price = display_price_value


func is_valid() -> bool:
	return (
		not product_id.is_empty()
		and not display_name.is_empty()
		and not product_type.is_empty()
		and not content_id.is_empty()
		and not display_price.is_empty()
	)
