extends RefCounted
class_name RollbackFighterGameProjectReadiness

const ProjectStoreScript = preload("res://games/rollback_fighter/scripts/projects/GameProjectStore.gd")
const PresentationStoreScript = preload("res://games/rollback_fighter/scripts/projects/ProjectPresentationStore.gd")
const AssetImporterScript = preload("res://games/rollback_fighter/scripts/projects/ProjectAssetImporter.gd")
const AudioImporterScript = preload("res://games/rollback_fighter/scripts/projects/ProjectAudioImporter.gd")
const FighterProviderScript = preload("res://games/rollback_fighter/scripts/config/ImportedFighterProvider.gd")
const ManifestResolverScript = preload("res://games/rollback_fighter/scripts/config/FighterPresentationManifestResolver.gd")

const STATE_DRAFT := "draft"
const STATE_INCOMPLETE := "incomplete"
const STATE_READY := "ready_to_build"
const STATE_BUILT := "built"
const STATE_INVALID := "invalid"
const MINIMUM_FIGHTERS := 2
const BUILD_VERSION := 2

func evaluate(project_id: String) -> Dictionary:
	var loaded := ProjectStoreScript.new().load_project(project_id)
	if not bool(loaded.get("ok", false)):
		return _result(STATE_INVALID, ["Project definition is missing or invalid."], null, null, [], "")
	var project: RollbackFighterGameProjectDefinition = loaded["project"]
	var policy := ManifestResolverScript.resolve(project.style_preset, project.presentation_policy_reference)
	if not bool(policy.get("ok", false)):
		return _result(STATE_INVALID, ["Style presentation policy is invalid."], project, null, [], "")

	var presentation = null
	var presentation_store := PresentationStoreScript.new()
	var presentation_result := presentation_store.load_presentation(project_id)
	if bool(presentation_result.get("ok", false)):
		presentation = presentation_result["presentation"]
		var asset_problem := _validate_assigned_assets(presentation)
		if not asset_problem.is_empty():
			return _result(STATE_INVALID, [asset_problem], project, presentation, [], "")
	elif not _is_missing_presentation(presentation_result):
		return _result(STATE_INVALID, ["Project presentation definition is corrupt or invalid."], project, null, [], "")
	else:
		presentation = presentation_store.load_or_default(project_id, project.display_name)

	if project.fighter_ids.is_empty():
		return _result(STATE_DRAFT, ["Add at least %d playable fighters." % MINIMUM_FIGHTERS], project, presentation, [], _source_signature(project))
	var fighter_provider := FighterProviderScript.new()
	var playable_ids: Array[String] = []
	var fighter_messages: Array[String] = []
	for fighter_id in project.fighter_ids:
		var fighter := fighter_provider.load_fighter(fighter_id)
		if bool(fighter.get("ok", false)):
			playable_ids.append(fighter_id)
		else:
			fighter_messages.append("Fighter \"%s\" is missing required art or is not playable." % fighter_id)
	if not fighter_messages.is_empty():
		return _result(STATE_INCOMPLETE, fighter_messages, project, presentation, playable_ids, _source_signature(project))
	if playable_ids.size() < MINIMUM_FIGHTERS:
		return _result(STATE_INCOMPLETE, ["Need at least %d playable fighters; currently %d." % [MINIMUM_FIGHTERS, playable_ids.size()]], project, presentation, playable_ids, _source_signature(project))

	var signature := _source_signature(project)
	var build := _read_json("user://games/%s/build/game_manifest.json" % project_id)
	if (
		str(build.get("project_id", "")) == project_id
		and int(build.get("build_version", 0)) == BUILD_VERSION
		and str(build.get("source_signature", "")) == signature
		and Array(build.get("fighter_ids", [])) == project.fighter_ids
	):
		return _result(STATE_BUILT, ["Built and ready to play."], project, presentation, playable_ids, signature)
	var messages: Array[String] = ["Ready to build."]
	if not build.is_empty():
		messages = ["Build is stale; rebuild after project changes."]
	return _result(STATE_READY, messages, project, presentation, playable_ids, signature)

func _validate_assigned_assets(presentation) -> String:
	var image_importer := AssetImporterScript.new()
	if not presentation.background_image.is_empty() and image_importer.load_texture(presentation.background_image) == null:
		return "Assigned project background is missing or invalid."
	if not presentation.logo_image.is_empty() and image_importer.load_texture(presentation.logo_image) == null:
		return "Assigned project logo is missing or invalid."
	var audio_importer := AudioImporterScript.new()
	for slot_id in presentation.audio_slots:
		if audio_importer.load_stream(str(presentation.audio_slots[slot_id])) == null:
			return "Assigned audio slot \"%s\" is missing or invalid." % slot_id
	return ""

func _is_missing_presentation(result: Dictionary) -> bool:
	var errors: Variant = result.get("errors", [])
	return errors is Array and not errors.is_empty() and str(errors[0].get("code", "")) == "PRESENTATION_NOT_FOUND"

func _source_signature(project: RollbackFighterGameProjectDefinition) -> String:
	# Local build freshness intentionally includes local paths and presentation assets.
	# It is not exchanged with peers and is separate from the multiplayer digest.
	var paths: Array[String] = [
		"res://games/rollback_fighter/config/game_rules.json",
		"res://games/rollback_fighter/config/builtin_fighters.json",
		"user://games/%s/project.json" % project.project_id,
		"user://games/%s/presentation.json" % project.project_id,
	]
	_collect_files("user://games/%s/assets" % project.project_id, paths)
	for fighter_id in project.fighter_ids:
		_collect_files("user://characters/%s" % fighter_id, paths)
	paths.sort()
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	for path in paths:
		context.update(path.to_utf8_buffer())
		if not FileAccess.file_exists(path):
			continue
		var file := FileAccess.open(path, FileAccess.READ)
		if file != null:
			context.update(file.get_buffer(file.get_length()))
			file.close()
	return context.finish().hex_encode()

func _collect_files(root: String, output: Array[String]) -> void:
	var dir := DirAccess.open(root)
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while not name.is_empty():
		var path := root + "/" + name
		if dir.current_is_dir():
			_collect_files(path, output)
		else:
			output.append(path)
		name = dir.get_next()
	dir.list_dir_end()

func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed if parsed is Dictionary else {}

func _result(state: String, messages: Array[String], project, presentation, fighter_ids: Array[String], signature: String) -> Dictionary:
	return {
		"status": state,
		"messages": messages,
		"project": project,
		"presentation": presentation,
		"fighter_ids": fighter_ids,
		"source_signature": signature,
		"can_build": state in [STATE_READY, STATE_BUILT],
		"can_play": state == STATE_BUILT,
	}
