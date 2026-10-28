extends Node
class_name RollbackSimulationAdapter

## Shared lifecycle contract consumed by RollbackNetworkSession. Gameplay state
## and input schemas remain owned by concrete game adapters.

var first_debug_frame: int = -1
var first_debug_field: String = ""
var first_debug_local: String = ""
var first_debug_remote: String = ""


func neutral_input() -> Dictionary:
	return {}


func validate_input_data(_input_data: Dictionary) -> bool:
	return false


func inputs_equal(a: Dictionary, b: Dictionary) -> bool:
	return a == b


func simulate(_local: Dictionary, _remote: Dictionary, _dt: float) -> void:
	pass


func capture() -> Dictionary:
	return {}


func restore(_snapshot: Dictionary) -> void:
	pass


func canonical_checksum(_snapshot: Dictionary) -> int:
	return 0


func canonical_debug_values(_snapshot: Dictionary) -> Array:
	return []


func report_first_debug_difference(
	_frame: int,
	_local_snapshot: Dictionary,
	_remote_values: Array,
	_remote_checksum: int = 0
) -> void:
	pass
