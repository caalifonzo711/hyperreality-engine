extends Node
class_name RollbackFighterGameProjectLaunchConfig

const ProjectStoreScript = preload("res://games/rollback_fighter/scripts/projects/GameProjectStore.gd")
const ReadinessScript = preload("res://games/rollback_fighter/scripts/projects/GameProjectReadiness.gd")

var _project_id := ""
var _fighter_ids: Array[String] = []
var _p1_fighter_id := ""
var _p2_fighter_id := ""
var _display_name := ""
var _style_preset := ""
var _presentation_reference := ""
var _presentation_policy_reference := ""
var _local_launch_active := false
var _network_launch_active := false
var _network_host := false

func open_project(project_id: String) -> bool:
	var loaded := ProjectStoreScript.new().load_project(project_id)
	if not bool(loaded.get("ok", false)):
		return false
	var project: RollbackFighterGameProjectDefinition = loaded["project"]
	_project_id = project_id
	_fighter_ids = project.fighter_ids.duplicate()
	_display_name = project.display_name
	_style_preset = project.style_preset
	_presentation_reference = project.presentation_reference
	_presentation_policy_reference = project.presentation_policy_reference
	_p1_fighter_id = ""
	_p2_fighter_id = ""
	_local_launch_active = false
	_network_launch_active = false
	_network_host = false
	return true

func begin_local(project_id: String) -> bool:
	var readiness := ReadinessScript.new().evaluate(project_id)
	if not bool(readiness.get("can_play", false)) or not open_project(project_id):
		return false
	_local_launch_active = true
	return true

func begin_network(project_id: String, as_host: bool) -> bool:
	var readiness := ReadinessScript.new().evaluate(project_id)
	var ready_for_role := bool(readiness.get("can_play", false)) if as_host else bool(readiness.get("can_build", false))
	if not ready_for_role or not open_project(project_id):
		return false
	_network_launch_active = true
	_network_host = as_host
	return true

func set_fighter_selection(p1_id: String, p2_id: String) -> bool:
	if p1_id not in _fighter_ids or p2_id not in _fighter_ids:
		return false
	_p1_fighter_id = p1_id
	_p2_fighter_id = p2_id
	return true

func get_context() -> Dictionary:
	return {
		"project_id": _project_id,
		"fighter_ids": _fighter_ids.duplicate(),
		"p1_fighter_id": _p1_fighter_id,
		"p2_fighter_id": _p2_fighter_id,
		"display_name": _display_name,
		"style_preset": _style_preset,
		"presentation_reference": _presentation_reference,
		"presentation_policy_reference": _presentation_policy_reference,
		"mode": "single_player" if is_local_launch() else ("host" if is_network_project() and _network_host else ("client" if is_network_project() else "")),
	}

func get_project_id() -> String:
	return _project_id

func get_fighter_ids() -> Array[String]:
	return _fighter_ids.duplicate()

func has_project() -> bool:
	return not _project_id.is_empty()

func is_local_launch() -> bool:
	return has_project() and _local_launch_active

func is_network_project() -> bool:
	return has_project() and _network_launch_active

func is_project_match() -> bool:
	return is_local_launch() or is_network_project()

func clear() -> void:
	_project_id = ""
	_fighter_ids.clear()
	_p1_fighter_id = ""
	_p2_fighter_id = ""
	_display_name = ""
	_style_preset = ""
	_presentation_reference = ""
	_presentation_policy_reference = ""
	_local_launch_active = false
	_network_launch_active = false
	_network_host = false
