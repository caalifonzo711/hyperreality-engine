extends RefCounted
class_name RollbackFighterTuningDraft


const MOVE_SLOTS := ["light", "heavy"]
const DOCUMENT_NAMES := ["character", "jab", "heavy"]

var _loader: RollbackFighterCharacterDefinitionLoader
var _registry_path: String = ""
var fighter_id: String = ""
var fighter_root: String = ""
var character_document: Dictionary = {}
var move_documents: Dictionary = {}
var _baseline_character: Dictionary = {}
var _baseline_moves: Dictionary = {}
var _document_paths: Dictionary = {}
var last_errors: Array[Dictionary] = []


func configure(
	loader: RollbackFighterCharacterDefinitionLoader,
	registry_path: String
) -> void:
	_loader = loader
	_registry_path = registry_path


func get_registered_fighter_ids() -> PackedStringArray:
	var errors: Array[Dictionary] = []
	var registry: Dictionary = _loader._load_json(_registry_path, errors)
	if not errors.is_empty():
		last_errors = errors
		return PackedStringArray()
	var fighters_value: Variant = registry.get("fighters")
	if not fighters_value is Dictionary:
		return PackedStringArray()
	var ids := PackedStringArray()
	for fighter_key in fighters_value.keys():
		ids.append(str(fighter_key))
	ids.sort()
	return ids


func load_fighter(requested_id: String) -> bool:
	last_errors.clear()
	var registry: Dictionary = _loader._load_json(_registry_path, last_errors)
	if not last_errors.is_empty():
		return false
	var fighters_value: Variant = registry.get("fighters")
	if not fighters_value is Dictionary:
		last_errors.append({
			"code": "CFG_REGISTRY_FIGHTERS_INVALID",
			"file": _registry_path,
			"field": "fighters",
			"invalid_value": fighters_value,
			"expected_rule": "must be an object",
		})
		return false
	var fighters: Dictionary = fighters_value
	if not fighters.has(requested_id):
		last_errors.append({
			"code": "CFG_FIGHTER_NOT_REGISTERED",
			"file": _registry_path,
			"field": "fighters.%s" % requested_id,
			"invalid_value": "<missing>",
			"expected_rule": "must name an explicit built-in fighter root",
		})
		return false
	var root_value: Variant = fighters[requested_id]
	if not root_value is String:
		last_errors.append({
			"code": "CFG_REGISTRY_ROOT_INVALID",
			"file": _registry_path,
			"field": "fighters.%s" % requested_id,
			"invalid_value": root_value,
			"expected_rule": "must be a res:// string",
		})
		return false
	fighter_root = _loader._normalize_builtin_root(
		str(root_value),
		_registry_path,
		last_errors
	)
	if not last_errors.is_empty():
		return false
	var read_errors: Array[Dictionary] = []
	fighter_id = requested_id
	_document_paths.clear()
	_document_paths["character"] = fighter_root + "/character.json"
	var parsed_character: Dictionary = _read_document(
		str(_document_paths["character"]),
		read_errors
	)
	if parsed_character.is_empty():
		last_errors = read_errors
		return false
	character_document = parsed_character
	var identity: Dictionary = character_document.get("identity", {})
	if str(identity.get("id", "")) != fighter_id:
		read_errors.append({
			"code": "CFG_FIGHTER_ID_MISMATCH",
			"file": str(_document_paths["character"]),
			"field": "identity.id",
			"invalid_value": identity.get("id", "<missing>"),
			"expected_rule": "must match registry id %s" % fighter_id,
		})
	move_documents.clear()
	var move_refs: Dictionary = character_document.get("moves", {})
	for slot in MOVE_SLOTS:
		var move_relative: String = str(move_refs.get(slot, ""))
		var resolved_path: String = _loader._resolve_reference(
			fighter_root,
			move_relative,
			str(_document_paths["character"]),
			"moves.%s" % slot,
			read_errors
		)
		if resolved_path.is_empty():
			continue
		var move_doc: Dictionary = _read_document(resolved_path, read_errors)
		var move_doc_name: String = "jab" if slot == "light" else "heavy"
		move_documents[move_doc_name] = move_doc
		_document_paths[move_doc_name] = resolved_path
	if not read_errors.is_empty():
		last_errors = read_errors
		return false
	_baseline_character = character_document.duplicate(true)
	_baseline_moves = move_documents.duplicate(true)
	return true


func is_dirty() -> bool:
	if character_document.is_empty() or move_documents.size() != 2:
		return false
	return (
		JSON.stringify(character_document) != JSON.stringify(_baseline_character)
		or JSON.stringify(move_documents) != JSON.stringify(_baseline_moves)
	)


func set_integer(document_name: String, section: String, field: String, value: int) -> void:
	var document: Dictionary = _get_document(document_name)
	if document_name == "character":
		var subsection: Dictionary = document.get(section, {})
		subsection[field] = value
		document[section] = subsection
	else:
		document[field] = value


func get_integer(document_name: String, section: String, field: String) -> int:
	var document: Dictionary = _get_document(document_name)
	if document_name == "character":
		var subsection: Dictionary = document.get(section, {})
		return int(subsection.get(field, 0))
	return int(document.get(field, 0))


func validate() -> Array[Dictionary]:
	if _loader == null:
		last_errors = []
		last_errors.append({
			"code": "TUNING_DRAFT_NOT_CONFIGURED",
			"file": "<tuning-draft>",
			"field": "loader",
			"invalid_value": "<missing>",
			"expected_rule": "draft must be configured with the CharacterDefinitionLoader",
		})
		return last_errors.duplicate(true)
	var raw_moves: Dictionary = {
		"light": move_documents.get("jab", {}),
		"heavy": move_documents.get("heavy", {}),
	}
	last_errors = _loader.validate_tuning_draft(
		fighter_root,
		character_document,
		raw_moves
	)
	return last_errors.duplicate(true)


func serialize_document(document_name: String) -> String:
	var document: Dictionary = _get_document(document_name)
	return JSON.stringify(document, "\t", false) + "\n"


func save() -> Dictionary:
	var errors: Array[Dictionary] = validate()
	if not errors.is_empty():
		return {"ok": false, "errors": errors}

	for document_name in DOCUMENT_NAMES:
		var path: String = str(_document_paths.get(document_name, ""))
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file == null:
			var write_error: Dictionary = {
				"code": "TUNING_SAVE_FAILED",
				"file": path,
				"field": "<file>",
				"invalid_value": FileAccess.get_open_error(),
				"expected_rule": "development project config file must be writable",
			}
			last_errors = [write_error]
			return {"ok": false, "errors": last_errors.duplicate(true)}
		file.store_string(serialize_document(document_name))
		file.flush()
		file.close()

	_baseline_character = character_document.duplicate(true)
	_baseline_moves = move_documents.duplicate(true)
	last_errors.clear()
	return {"ok": true, "errors": []}


func revert() -> bool:
	return load_fighter(fighter_id)


func get_display_name() -> String:
	var identity: Dictionary = character_document.get("identity", {})
	return str(identity.get("display_name", fighter_id))


func get_updated_file_names() -> PackedStringArray:
	return PackedStringArray(["character.json", "jab.json", "heavy.json"])


func _get_document(document_name: String) -> Dictionary:
	if document_name == "character":
		return character_document
	return move_documents.get(document_name, {})


func _read_document(path: String, errors: Array[Dictionary]) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		errors.append({
			"code": "CFG_FILE_OPEN_FAILED",
			"file": path,
			"field": "<file>",
			"invalid_value": FileAccess.get_open_error(),
			"expected_rule": "file must be readable",
		})
		return {}
	var parser := JSON.new()
	var parse_error: Error = parser.parse(file.get_as_text())
	file.close()
	if parse_error != OK or not parser.data is Dictionary:
		errors.append({
			"code": "CFG_JSON_INVALID",
			"file": path,
			"field": "<root>",
			"invalid_value": parser.get_error_message(),
			"expected_rule": "file must contain a valid JSON object",
		})
		return {}
	return Dictionary(parser.data)
