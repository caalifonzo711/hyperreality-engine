extends RefCounted
class_name RollbackFighterGameRulesDefinition


var _authoritative: Dictionary


func _init(authoritative: Dictionary) -> void:
	_authoritative = authoritative.duplicate(true)


func get_int(field: String) -> int:
	return int(_authoritative[field])


func get_int_array(field: String) -> Array:
	return Array(_authoritative[field]).duplicate()


func get_spawn_position(player: String) -> Vector2i:
	var positions: Dictionary = _authoritative["spawn_positions"]
	var position_data: Dictionary = positions[player]
	return Vector2i(int(position_data["x"]), int(position_data["y"]))


func is_world_contact_enabled() -> bool:
	var bounds: Dictionary = _authoritative["world_contact_bounds"]
	return bool(bounds["enabled"])


func get_world_contact_bound(field: String) -> int:
	var bounds: Dictionary = _authoritative["world_contact_bounds"]
	return int(bounds[field])


func get_fallback_policy() -> String:
	return str(_authoritative["fallback_policy"])


func get_authoritative_data() -> Dictionary:
	return _authoritative.duplicate(true)
