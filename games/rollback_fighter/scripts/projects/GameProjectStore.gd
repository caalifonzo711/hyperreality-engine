extends RefCounted
class_name RollbackFighterGameProjectStore


const ProjectDefinitionScript = preload("res://games/rollback_fighter/scripts/projects/GameProjectDefinition.gd")
const GAMES_ROOT := "user://games"


func create(project: RollbackFighterGameProjectDefinition) -> Dictionary:
	var errors: Array[Dictionary] = project.validate()
	if not errors.is_empty():
		return {"ok": false, "errors": errors}
	var root: String = get_project_root(project.project_id)
	if root.is_empty():
		return _failure("PROJECT_PATH_INVALID", "project_id", project.project_id, "must produce a safe user://games path")
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(root)) or FileAccess.file_exists(root + "/project.json"):
		return _failure("PROJECT_ID_DUPLICATE", "project_id", project.project_id, "a project with this ID already exists")
	for folder in [
		root,
		root + "/fighters",
		root + "/drafts",
		root + "/assets/backgrounds",
		root + "/assets/branding",
		root + "/assets/audio",
	]:
		var error: Error = DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
		if error != OK:
			return _failure("PROJECT_DIRECTORY_FAILED", "project_id", folder, "project folders must be writable under user://games")
	return _save(project)


func load_project(project_id: String) -> Dictionary:
	var root: String = get_project_root(project_id)
	if root.is_empty():
		return _failure("PROJECT_ID_INVALID", "project_id", project_id, "must match [a-z0-9_]+")
	var path: String = root + "/project.json"
	if not FileAccess.file_exists(path):
		return _failure("PROJECT_NOT_FOUND", "project_id", project_id, "project.json must exist")
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _failure("PROJECT_READ_FAILED", "project_id", project_id, "project.json must be readable")
	var text: String = file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary:
		return _failure("PROJECT_JSON_CORRUPT", "project.json", project_id, "must contain a valid JSON object")
	var decoded: Dictionary = ProjectDefinitionScript.from_dictionary(parsed)
	if not bool(decoded.get("ok", false)):
		return decoded
	var project: RollbackFighterGameProjectDefinition = decoded["project"]
	if project.project_id != project_id:
		return _failure("PROJECT_ID_MISMATCH", "project_id", project.project_id, "must match its containing folder")
	return {"ok": true, "project": project, "errors": []}


func add_fighter(project_id: String, fighter_id: String) -> Dictionary:
	var loaded: Dictionary = load_project(project_id)
	if not bool(loaded.get("ok", false)):
		return loaded
	var project: RollbackFighterGameProjectDefinition = loaded["project"]
	if not project.add_fighter(fighter_id):
		return _failure("PROJECT_FIGHTER_ID_INVALID", "fighter_ids", fighter_id, "must match [a-z0-9_]+")
	return _save(project)


func get_project_root(project_id: String) -> String:
	if not ProjectDefinitionScript.is_safe_id(project_id):
		return ""
	return "%s/%s" % [GAMES_ROOT, project_id]


func save(project: RollbackFighterGameProjectDefinition) -> Dictionary:
	var errors: Array[Dictionary] = project.validate()
	if not errors.is_empty():
		return {"ok": false, "errors": errors}
	return _save(project)


func _save(project: RollbackFighterGameProjectDefinition) -> Dictionary:
	var root: String = get_project_root(project.project_id)
	if root.is_empty():
		return _failure("PROJECT_PATH_INVALID", "project_id", project.project_id, "must remain under user://games")
	var path: String = root + "/project.json"
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return _failure("PROJECT_WRITE_FAILED", "project.json", FileAccess.get_open_error(), "must be writable under user://games")
	file.store_string(JSON.stringify(project.to_dictionary(), "\t", false) + "\n")
	file.flush()
	var error: Error = file.get_error()
	file.close()
	if error != OK:
		return _failure("PROJECT_WRITE_FAILED", "project.json", error, "must be writable under user://games")
	return {"ok": true, "project": project, "path": path, "errors": []}


func _failure(code: String, field: String, value: Variant, rule: String) -> Dictionary:
	return {"ok": false, "errors": [{"code": code, "file": "project.json", "field": field, "invalid_value": value, "expected_rule": rule}]}
