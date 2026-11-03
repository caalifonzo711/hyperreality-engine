extends RefCounted
class_name RollbackFighterGameProjectBuilder

const ProjectStoreScript = preload("res://games/rollback_fighter/scripts/projects/GameProjectStore.gd")
const ReadinessScript = preload("res://games/rollback_fighter/scripts/projects/GameProjectReadiness.gd")
const MultiplayerIdentityScript = preload("res://games/rollback_fighter/scripts/projects/GameProjectMultiplayerIdentity.gd")
const BUILD_VERSION := 2

func build(project_id: String) -> Dictionary:
	var readiness_service := ReadinessScript.new()
	var readiness := readiness_service.evaluate(project_id)
	if not bool(readiness.get("can_build", false)):
		return {"ok": false, "errors": readiness.get("messages", []), "readiness": readiness}
	var project: RollbackFighterGameProjectDefinition = readiness["project"]
	project.status = RollbackFighterGameProjectDefinition.STATUS_BUILT
	project.updated_at = int(Time.get_unix_time_from_system())
	var saved := ProjectStoreScript.new().save(project)
	if not bool(saved.get("ok", false)):
		return {"ok": false, "errors": saved.get("errors", []), "readiness": readiness}
	readiness = readiness_service.evaluate(project_id)
	var build_root := "user://games/%s/build" % project_id
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(build_root)) != OK:
		return {"ok": false, "errors": ["Could not create the project build directory."], "readiness": readiness}
	var manifest := {
		"schema_version": 1,
		"build_version": BUILD_VERSION,
		"status": "built",
		"project_id": project.project_id,
		"display_name": project.display_name,
		"project_version": project.version,
		"style_preset": project.style_preset,
		"rules_reference": project.rules_reference,
		"presentation_policy_reference": project.presentation_policy_reference,
		"presentation_reference": project.presentation_reference,
		"fighter_ids": project.fighter_ids.duplicate(),
		"source_signature": str(readiness.get("source_signature", "")),
		"built_at": int(Time.get_unix_time_from_system()),
	}
	var multiplayer_result := MultiplayerIdentityScript.new().build(project_id, false)
	if not bool(multiplayer_result.get("ok", false)):
		return {"ok": false, "errors": multiplayer_result.get("errors", ["Could not build multiplayer project identity."]), "readiness": readiness}
	manifest["multiplayer_identity"] = multiplayer_result["identity"]
	manifest["multiplayer_project_digest"] = str(multiplayer_result["identity"].get("digest", ""))
	var path := build_root + "/game_manifest.json"
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "errors": ["Could not write game_manifest.json."], "readiness": readiness}
	file.store_string(JSON.stringify(manifest, "\t", false) + "\n")
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK:
		return {"ok": false, "errors": ["Could not finish game_manifest.json."], "readiness": readiness}
	return {"ok": true, "path": path, "manifest": manifest, "readiness": readiness_service.evaluate(project_id), "errors": []}
