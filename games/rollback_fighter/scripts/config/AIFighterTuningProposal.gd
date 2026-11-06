extends RefCounted
class_name RollbackFighterAIFighterTuningProposal

const Catalog = preload("res://games/rollback_fighter/scripts/config/CreatorTuningCatalog.gd")
const LoaderScript = preload("res://games/rollback_fighter/scripts/config/CharacterDefinitionLoader.gd")

var values: Dictionary = {}
var original_values: Dictionary = {}
var reason: String = ""
var unsupported_note: String = ""
var clamped_fields: PackedStringArray = PackedStringArray()
var ignored_fields: PackedStringArray = PackedStringArray()


static func from_dictionary(document: Variant, draft) -> Dictionary:
	if not document is Dictionary:
		return _failure("AI_TUNING_INVALID_RESPONSE", "The AI tuning response was not an object.")
	var source: Dictionary = document
	if not source.get("reason", null) is String:
		return _failure("AI_TUNING_REASON_REQUIRED", "The AI tuning response did not contain a valid reason.")
	if source.has("unsupported_note") and not source.unsupported_note is String:
		return _failure("AI_TUNING_NOTE_INVALID", "The AI tuning response contained an invalid support note.")
	var proposal := RollbackFighterAIFighterTuningProposal.new()
	proposal.reason = str(source.get("reason", "")).strip_edges()
	proposal.unsupported_note = str(source.get("unsupported_note", "")).strip_edges()
	if proposal.reason.is_empty():
		return _failure("AI_TUNING_REASON_REQUIRED", "The AI tuning response did not explain its intent.")
	var values_value: Variant = source.get("values", null)
	if not values_value is Dictionary:
		return _failure("AI_TUNING_VALUES_REQUIRED", "The AI tuning response did not contain tuning values.")
	var requested: Dictionary = values_value
	proposal.original_values = Catalog.get_current_values(draft)
	for field_value: Variant in requested.keys():
		var field_id: String = str(field_value)
		var spec: Dictionary = Catalog.get_spec(field_id)
		if spec.is_empty():
			proposal.ignored_fields.append(field_id)
			continue
		var raw_value: Variant = requested[field_value]
		if not _is_integer_number(raw_value):
			return _failure("AI_TUNING_VALUE_INVALID", "%s must be a finite integer." % str(spec.label))
		var allowed: Vector2i = Catalog.get_range(draft, spec)
		var parsed: int = int(raw_value)
		var safe_value: int = clampi(parsed, allowed.x, allowed.y)
		if safe_value != parsed:
			proposal.clamped_fields.append(field_id)
		proposal.values[field_id] = safe_value
	if proposal.values.is_empty():
		return _failure("AI_TUNING_NO_SUPPORTED_FIELDS", "The AI response did not contain any supported tuning fields.")
	if not proposal.ignored_fields.is_empty() and proposal.unsupported_note.is_empty():
		proposal.unsupported_note = "Some requested mechanics are not currently supported. The suggestion approximates the requested feel using available fighter tuning."
	var validation: Dictionary = proposal._validate_candidate(draft)
	if not bool(validation.ok):
		return validation
	return {"ok": true, "proposal": proposal, "code": "", "message": ""}


func differences() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for spec: Dictionary in Catalog.get_specs():
		var field_id: String = str(spec.id)
		if not values.has(field_id):
			continue
		var before: int = int(original_values.get(field_id, 0))
		var after: int = int(values[field_id])
		if before != after:
			result.append({
				"field_id": field_id,
				"label": str(spec.label),
				"before": before,
				"after": after,
			})
	return result


func apply_to_draft(draft) -> Dictionary:
	var before_character: Dictionary = draft.character_document.duplicate(true)
	var before_moves: Dictionary = draft.move_documents.duplicate(true)
	for field_id: String in values:
		if not Catalog.set_value(draft, field_id, int(values[field_id])):
			draft.character_document = before_character
			draft.move_documents = before_moves
			draft.refresh_after_tuning()
			return _failure("AI_TUNING_FIELD_UNSUPPORTED", "The tuning proposal contained an unsupported field.")
	draft.refresh_after_tuning()
	var errors: Array[Dictionary] = draft.validate_documents()
	if not errors.is_empty():
		draft.character_document = before_character
		draft.move_documents = before_moves
		draft.refresh_after_tuning()
		return _failure("AI_TUNING_VALIDATION_FAILED", "The tuning proposal did not pass fighter validation.")
	return {"ok": true, "code": "", "message": "Tuning applied.", "errors": []}


func _validate_candidate(draft) -> Dictionary:
	var character: Dictionary = draft.character_document.duplicate(true)
	var moves: Dictionary = draft.move_documents.duplicate(true)
	var proxy = _DocumentProxy.new(character, moves)
	for field_id: String in values:
		Catalog.set_value(proxy, field_id, int(values[field_id]))
	var loader = LoaderScript.new()
	var errors: Array[Dictionary] = loader.validate_creator_draft(
		proxy.character_document,
		{"light": proxy.move_documents.get("light", {}), "heavy": proxy.move_documents.get("heavy", {})},
		draft.hitbox_documents
	)
	if not errors.is_empty():
		return _failure("AI_TUNING_VALIDATION_FAILED", "The tuning proposal did not pass fighter validation.")
	return {"ok": true, "code": "", "message": ""}


static func _is_integer_number(value: Variant) -> bool:
	if value is int:
		return true
	if value is float:
		var number: float = float(value)
		return not is_nan(number) and not is_inf(number) and number == floor(number)
	return false


static func _failure(code: String, message: String) -> Dictionary:
	return {"ok": false, "proposal": null, "code": code, "message": message, "errors": [message]}


class _DocumentProxy:
	var character_document: Dictionary
	var move_documents: Dictionary

	func _init(character: Dictionary, moves: Dictionary) -> void:
		character_document = character
		move_documents = moves

	func get_character_value(section: String, key: String) -> int:
		return int(Dictionary(character_document.get(section, {})).get(key, 0))

	func get_move_value(slot: String, key: String) -> int:
		return int(Dictionary(move_documents.get(slot, {})).get(key, 0))
