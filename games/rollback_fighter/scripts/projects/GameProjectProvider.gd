extends RefCounted
class_name RollbackFighterGameProjectProvider

const ProjectStoreScript = preload("res://games/rollback_fighter/scripts/projects/GameProjectStore.gd")
const ReadinessScript = preload("res://games/rollback_fighter/scripts/projects/GameProjectReadiness.gd")
const GAMES_ROOT := "user://games"

func list_projects() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var dir := DirAccess.open(GAMES_ROOT)
	if dir == null:
		return result
	var ids: Array[String] = []
	dir.list_dir_begin()
	var entry := dir.get_next()
	while not entry.is_empty():
		if dir.current_is_dir() and RollbackFighterGameProjectDefinition.is_safe_id(entry):
			ids.append(entry)
		entry = dir.get_next()
	dir.list_dir_end()
	ids.sort()
	var store := ProjectStoreScript.new()
	var readiness_service := ReadinessScript.new()
	for project_id in ids:
		var loaded := store.load_project(project_id)
		if not bool(loaded.get("ok", false)):
			continue
		var project: RollbackFighterGameProjectDefinition = loaded["project"]
		var readiness := readiness_service.evaluate(project_id)
		result.append({
			"project": project,
			"project_id": project.project_id,
			"display_name": project.display_name,
			"style_preset": project.style_preset,
			"version": project.version,
			"project_status": project.status,
			"fighter_count": project.fighter_ids.size(),
			"readiness": readiness,
		})
	return result
