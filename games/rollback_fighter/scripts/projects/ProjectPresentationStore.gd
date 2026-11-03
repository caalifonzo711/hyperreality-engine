extends RefCounted
class_name RollbackFighterProjectPresentationStore


const DefinitionScript = preload("res://games/rollback_fighter/scripts/projects/ProjectPresentationDefinition.gd")
const ProjectStoreScript = preload("res://games/rollback_fighter/scripts/projects/GameProjectStore.gd")


func save(definition: RollbackFighterProjectPresentationDefinition) -> Dictionary:
	var errors := definition.validate()
	if not errors.is_empty():
		return {"ok": false, "errors": errors}
	var root: String = ProjectStoreScript.new().get_project_root(definition.project_id)
	if root.is_empty() or not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(root)):
		return _failure("PRESENTATION_PROJECT_NOT_FOUND", "project_id", definition.project_id, "project directory must already exist")
	var path := root + "/presentation.json"
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return _failure("PRESENTATION_WRITE_FAILED", "presentation.json", FileAccess.get_open_error(), "must be writable under user://games")
	file.store_string(JSON.stringify(definition.to_dictionary(), "\t", false) + "\n")
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK:
		return _failure("PRESENTATION_WRITE_FAILED", "presentation.json", error, "must be writable under user://games")
	return {"ok": true, "presentation": definition, "path": path, "errors": []}


func load_presentation(project_id: String) -> Dictionary:
	var root: String = ProjectStoreScript.new().get_project_root(project_id)
	if root.is_empty():
		return _failure("PRESENTATION_PROJECT_ID_INVALID", "project_id", project_id, "must match [a-z0-9_]+")
	var path := root + "/presentation.json"
	if not FileAccess.file_exists(path):
		return _failure("PRESENTATION_NOT_FOUND", "presentation.json", project_id, "presentation file is optional for older projects")
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _failure("PRESENTATION_READ_FAILED", "presentation.json", project_id, "must be readable")
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary:
		return _failure("PRESENTATION_JSON_CORRUPT", "presentation.json", project_id, "must contain a valid JSON object")
	var decoded: Dictionary = DefinitionScript.from_dictionary(parsed)
	if not bool(decoded.get("ok", false)):
		return decoded
	var definition: RollbackFighterProjectPresentationDefinition = decoded["presentation"]
	if definition.project_id != project_id:
		return _failure("PRESENTATION_PROJECT_ID_MISMATCH", "project_id", definition.project_id, "must match its containing project")
	return decoded


func load_or_default(project_id: String, display_name: String = "") -> RollbackFighterProjectPresentationDefinition:
	var loaded := load_presentation(project_id)
	if bool(loaded.get("ok", false)):
		return loaded["presentation"]
	var fallback := DefinitionScript.new()
	fallback.configure(project_id, display_name if not display_name.is_empty() else project_id)
	return fallback


func _failure(code: String, field: String, value: Variant, rule: String) -> Dictionary:
	return {"ok": false, "errors": [{"code": code, "file": "presentation.json", "field": field, "invalid_value": value, "expected_rule": rule}]}
