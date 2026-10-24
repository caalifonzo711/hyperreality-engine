extends RefCounted
class_name RollbackFighterMoveDefinition


var _authoritative: Dictionary
var _hitbox_profile: Dictionary


func _init(authoritative: Dictionary, hitbox_profile: Dictionary) -> void:
	_authoritative = authoritative.duplicate(true)
	_hitbox_profile = hitbox_profile.duplicate(true)


func get_id() -> String:
	return str(_authoritative["id"])


func get_display_name() -> String:
	return str(_authoritative["display_name"])


func get_int(field: String) -> int:
	return int(_authoritative[field])


func get_animation_id() -> String:
	return str(_authoritative["animation_id"])


func get_authoritative_data() -> Dictionary:
	return _authoritative.duplicate(true)


func get_hitbox_profile() -> Dictionary:
	return _hitbox_profile.duplicate(true)
