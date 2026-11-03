extends RefCounted
class_name RollbackFighterImportedFighterProvider

const BUILTIN_REGISTRY := "res://games/rollback_fighter/config/builtin_fighters.json"
const IMPORTED_ROOT := "user://characters"
const LoaderScript = preload("res://games/rollback_fighter/scripts/config/CharacterDefinitionLoader.gd")

var _loader: RollbackFighterCharacterDefinitionLoader = LoaderScript.new()


func load_fighter(fighter_id: String) -> Dictionary:
	if not _safe_id(fighter_id):
		return _failure("FIGHTER_ID_INVALID", fighter_id, "must match [a-z0-9_]+")
	if _is_builtin_id(fighter_id):
		var builtin: Dictionary = _loader.load_builtin_fighter(BUILTIN_REGISTRY, fighter_id)
		return builtin
	var root: String = "%s/%s" % [IMPORTED_ROOT, fighter_id]
	var manifest: Dictionary = _read_json(root + "/creator_manifest.json")
	if manifest.is_empty() or str(manifest.get("fighter_id", "")) != fighter_id or not bool(manifest.get("playable", false)) or str(manifest.get("status", "")) != "built":
		return _failure("IMPORTED_FIGHTER_UNAVAILABLE", fighter_id, "fighter must have a valid built creator manifest")
	return _loader.load_character(root, fighter_id)


func list_fighters() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var registry: Dictionary = _read_json(BUILTIN_REGISTRY)
	var builtin_ids: Array[String] = []
	var fighters_value: Variant = registry.get("fighters", {})
	if fighters_value is Dictionary:
		for key in Dictionary(fighters_value).keys():
			builtin_ids.append(str(key))
	builtin_ids.sort()
	for fighter_id in builtin_ids:
		var loaded: Dictionary = load_fighter(fighter_id)
		if bool(loaded.get("ok", false)):
			result.append({"id": fighter_id, "definition": loaded["definition"], "source": "built_in"})

	var dir: DirAccess = DirAccess.open(IMPORTED_ROOT)
	if dir == null:
		return result
	var imported_ids: Array[String] = []
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while not entry.is_empty():
		if dir.current_is_dir() and _safe_id(entry):
			imported_ids.append(entry)
		entry = dir.get_next()
	dir.list_dir_end()
	imported_ids.sort()
	for fighter_id in imported_ids:
		if builtin_ids.has(fighter_id):
			continue
		var loaded: Dictionary = load_fighter(fighter_id)
		if bool(loaded.get("ok", false)):
			result.append({"id": fighter_id, "definition": loaded["definition"], "source": "imported"})
	return result


func list_fighters_for_ids(fighter_ids: Array[String]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for fighter_id in fighter_ids:
		var loaded := load_fighter(fighter_id)
		if bool(loaded.get("ok", false)):
			result.append({"id": fighter_id, "definition": loaded["definition"], "source": "project"})
	return result


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var value: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	return value if value is Dictionary else {}


func _is_builtin_id(fighter_id: String) -> bool:
	var registry: Dictionary = _read_json(BUILTIN_REGISTRY)
	var fighters_value: Variant = registry.get("fighters", {})
	return fighters_value is Dictionary and Dictionary(fighters_value).has(fighter_id)


func _safe_id(value: String) -> bool:
	if value.is_empty():
		return false
	for index in value.length():
		var code: int = value.unicode_at(index)
		if not ((code >= 97 and code <= 122) or (code >= 48 and code <= 57) or code == 95):
			return false
	return true


func _failure(code: String, value: Variant, rule: String) -> Dictionary:
	return {"ok": false, "definition": null, "errors": [{"code": code, "file": IMPORTED_ROOT, "field": "fighter_id", "invalid_value": value, "expected_rule": rule}]}
