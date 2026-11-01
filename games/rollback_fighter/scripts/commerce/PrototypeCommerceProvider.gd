extends "res://games/rollback_fighter/scripts/commerce/CommerceProvider.gd"
class_name RollbackFighterPrototypeCommerceProvider

const PROVIDER_ID := "prototype"
const MODE_SUCCESS := "success"
const MODE_CANCELLED := "cancelled"
const MODE_FAILURE := "failure"
const MODE_UNAVAILABLE := "unavailable"

var _mode: String = MODE_SUCCESS
var _transaction_counter: int = 0
var _simulated_restore_results: Array[Dictionary] = []


func get_provider_id() -> String:
	return PROVIDER_ID


func set_mode(mode: String) -> bool:
	if mode not in [MODE_SUCCESS, MODE_CANCELLED, MODE_FAILURE, MODE_UNAVAILABLE]:
		return false
	_mode = mode
	return true


func get_mode() -> String:
	return _mode


func purchase(product_id: String) -> Dictionary:
	match _mode:
		MODE_CANCELLED:
			return make_result(
				false, STATUS_PURCHASE_CANCELLED, product_id, PROVIDER_ID, ""
			)
		MODE_FAILURE:
			return make_result(
				false, STATUS_PURCHASE_FAILED, product_id, PROVIDER_ID, ""
			)
		MODE_UNAVAILABLE:
			return make_result(
				false, STATUS_PROVIDER_UNAVAILABLE, product_id, PROVIDER_ID, ""
			)
		_:
			_transaction_counter += 1
			var transaction_id := "prototype-%d-%04d" % [
				int(Time.get_unix_time_from_system()),
				_transaction_counter,
			]
			return make_result(
				true, STATUS_SUCCESS, product_id, PROVIDER_ID, transaction_id
			)


func supports_restore() -> bool:
	return true


func restore_purchases() -> Array[Dictionary]:
	return _simulated_restore_results.duplicate(true)


func set_simulated_restore_results(results: Array[Dictionary]) -> void:
	_simulated_restore_results = results.duplicate(true)


# This provider simulates outcomes only. It does not charge money or represent a
# production payment processor, and its transaction IDs have no security guarantees.
# Restore fixtures are development-only. A production provider must return purchases
# verified by its platform or another trusted transaction authority.
