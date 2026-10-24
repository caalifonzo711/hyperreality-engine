extends RefCounted
class_name RollbackFighterCharacterDefinition


var _authoritative: Dictionary
var _move_slots: Dictionary
var _moves_by_id: Dictionary
var _presentation: RollbackFighterPresentationDefinition


func _init(
	authoritative: Dictionary,
	move_slots: Dictionary,
	presentation: RollbackFighterPresentationDefinition
) -> void:
	_authoritative = authoritative.duplicate(true)
	_move_slots = move_slots.duplicate()
	_moves_by_id = {}
	for slot in ["light", "heavy"]:
		var move: RollbackFighterMoveDefinition = _move_slots[slot]
		_moves_by_id[move.get_id()] = move
	_presentation = presentation


func get_config_version() -> int:
	return int(_authoritative["config_version"])


func get_id() -> String:
	return str(_authoritative["id"])


func get_display_name() -> String:
	return str(_authoritative["display_name"])


func get_int(field: String) -> int:
	return int(_authoritative[field])


func get_move_for_slot(slot: String) -> RollbackFighterMoveDefinition:
	return _move_slots.get(slot) as RollbackFighterMoveDefinition


func get_move_by_id(move_id: String) -> RollbackFighterMoveDefinition:
	return _moves_by_id.get(move_id) as RollbackFighterMoveDefinition


func get_authoritative_data() -> Dictionary:
	return _authoritative.duplicate(true)


func get_presentation() -> RollbackFighterPresentationDefinition:
	return _presentation
