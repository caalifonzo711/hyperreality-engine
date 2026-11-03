extends Node
class_name RollbackFighterCreatorLaunchContext


const ProjectDefinitionScript = preload("res://games/rollback_fighter/scripts/projects/GameProjectDefinition.gd")
const ProjectStoreScript = preload("res://games/rollback_fighter/scripts/projects/GameProjectStore.gd")
const PresentationResolverScript = preload("res://games/rollback_fighter/scripts/projects/ProjectPresentationResolver.gd")

var _project_id: String = ""


func launch_global() -> void:
	_project_id = ""


func launch_for_project(project_id: String) -> bool:
	if not ProjectDefinitionScript.is_safe_id(project_id):
		return false
	var store: RollbackFighterGameProjectStore = ProjectStoreScript.new()
	if not bool(store.load_project(project_id).get("ok", false)):
		return false
	_project_id = project_id
	return true


func get_project_id() -> String:
	return _project_id


func get_runtime_presentation() -> Dictionary:
	return PresentationResolverScript.new().resolve(_project_id)


func get_presentation_config() -> Dictionary:
	if not has_project():
		return {"style_preset": "platform_fighter", "presentation_policy_reference": "", "legacy": true}
	var store: RollbackFighterGameProjectStore = ProjectStoreScript.new()
	var loaded: Dictionary = store.load_project(_project_id)
	if not bool(loaded.get("ok", false)):
		return {"style_preset": "platform_fighter", "presentation_policy_reference": "", "legacy": true}
	var project: RollbackFighterGameProjectDefinition = loaded["project"]
	return {"style_preset": project.style_preset, "presentation_policy_reference": project.presentation_policy_reference, "legacy": false}


func has_project() -> bool:
	return not _project_id.is_empty()


func record_successful_build(fighter_id: String) -> Dictionary:
	if not has_project():
		return {"ok": true, "legacy": true, "errors": []}
	var store: RollbackFighterGameProjectStore = ProjectStoreScript.new()
	return store.add_fighter(_project_id, fighter_id)
