extends RefCounted
class_name RollbackFighterGameProjectDefinition


const CURRENT_VERSION := 1
const STATUS_DRAFT := "draft"
const STATUS_BUILT := "built"
const STYLE_PRESETS := ["platform_fighter", "footsies", "anime_fighter", "custom"]

var project_id: String = ""
var display_name: String = ""
var style_preset: String = "platform_fighter"
var version: int = CURRENT_VERSION
var status: String = STATUS_DRAFT
var created_at: int = 0
var updated_at: int = 0
var fighter_ids: Array[String] = []
var rules_reference: String = "builtin:platform_fighter_rules_v1"
var presentation_policy_reference: String = ""
var presentation_reference: String = "presentation.json"
var background_reference: String = ""
var audio_reference: String = ""


func configure(name: String, requested_id: String, requested_style: String) -> void:
	display_name = name.strip_edges()
	project_id = requested_id.strip_edges()
	style_preset = requested_style
	presentation_policy_reference = presentation_policy_for_style(style_preset)
	var now: int = int(Time.get_unix_time_from_system())
	if created_at <= 0:
		created_at = now
	updated_at = now


func validate() -> Array[Dictionary]:
	var errors: Array[Dictionary] = []
	if not is_safe_id(project_id):
		errors.append(_error("PROJECT_ID_INVALID", "project_id", project_id, "must match [a-z0-9_]+"))
	if display_name.is_empty():
		errors.append(_error("PROJECT_NAME_REQUIRED", "display_name", display_name, "must not be empty"))
	if style_preset not in STYLE_PRESETS:
		errors.append(_error("PROJECT_STYLE_INVALID", "style_preset", style_preset, "must be a known style preset"))
	var expected_policy: String = presentation_policy_for_style(style_preset)
	if presentation_policy_reference != expected_policy:
		errors.append(_error("PROJECT_PRESENTATION_POLICY_INVALID", "presentation_policy_reference", presentation_policy_reference, "must match the selected style's versioned presentation policy"))
	if presentation_reference != "presentation.json":
		errors.append(_error("PROJECT_PRESENTATION_REFERENCE_INVALID", "presentation_reference", presentation_reference, "must be the project-local presentation.json reference"))
	if version <= 0:
		errors.append(_error("PROJECT_VERSION_INVALID", "version", version, "must be present and positive"))
	if status not in [STATUS_DRAFT, STATUS_BUILT]:
		errors.append(_error("PROJECT_STATUS_INVALID", "status", status, "must be draft or built"))
	for fighter_id in fighter_ids:
		if not is_safe_id(fighter_id):
			errors.append(_error("PROJECT_FIGHTER_ID_INVALID", "fighter_ids", fighter_id, "all roster IDs must match [a-z0-9_]+"))
	return errors


func add_fighter(fighter_id: String) -> bool:
	if not is_safe_id(fighter_id):
		return false
	if not fighter_ids.has(fighter_id):
		fighter_ids.append(fighter_id)
		updated_at = int(Time.get_unix_time_from_system())
	return true


func to_dictionary() -> Dictionary:
	return {
		"project_id": project_id,
		"display_name": display_name,
		"style_preset": style_preset,
		"version": version,
		"status": status,
		"created_at": created_at,
		"updated_at": updated_at,
		"fighter_ids": fighter_ids.duplicate(),
		"rules_reference": rules_reference,
		"presentation_policy_reference": presentation_policy_reference,
		"presentation_reference": presentation_reference,
		"background_reference": background_reference,
		"audio_reference": audio_reference,
	}


static func from_dictionary(document: Dictionary) -> Dictionary:
	var project := RollbackFighterGameProjectDefinition.new()
	project.project_id = str(document.get("project_id", "")).strip_edges()
	project.display_name = str(document.get("display_name", "")).strip_edges()
	project.style_preset = str(document.get("style_preset", ""))
	project.version = int(document.get("version", 0))
	project.status = str(document.get("status", ""))
	project.created_at = int(document.get("created_at", 0))
	project.updated_at = int(document.get("updated_at", 0))
	var roster: Variant = document.get("fighter_ids", [])
	if roster is Array:
		for value in roster:
			project.fighter_ids.append(str(value))
	else:
		return {"ok": false, "project": null, "errors": [project._error("PROJECT_ROSTER_INVALID", "fighter_ids", roster, "must be an array")]}
	project.rules_reference = str(document.get("rules_reference", ""))
	project.presentation_policy_reference = str(document.get("presentation_policy_reference", ""))
	if project.presentation_policy_reference.is_empty():
		project.presentation_policy_reference = presentation_policy_for_style(project.style_preset)
	project.presentation_reference = str(document.get("presentation_reference", "presentation.json"))
	project.background_reference = str(document.get("background_reference", ""))
	project.audio_reference = str(document.get("audio_reference", ""))
	var errors: Array[Dictionary] = project.validate()
	return {"ok": errors.is_empty(), "project": project if errors.is_empty() else null, "errors": errors}


static func is_safe_id(value: String) -> bool:
	if value.is_empty():
		return false
	for index in value.length():
		var code: int = value.unicode_at(index)
		if not ((code >= 97 and code <= 122) or (code >= 48 and code <= 57) or code == 95):
			return false
	return true


static func presentation_policy_for_style(style: String) -> String:
	if style not in STYLE_PRESETS:
		return ""
	return "fighter_presentation:%s:v1" % style


func _error(code: String, field: String, value: Variant, rule: String) -> Dictionary:
	return {"code": code, "file": "project.json", "field": field, "invalid_value": value, "expected_rule": rule}
