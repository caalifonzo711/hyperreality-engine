extends RefCounted
class_name RollbackFighterProjectPresentationResolver


const ProjectStoreScript = preload("res://games/rollback_fighter/scripts/projects/GameProjectStore.gd")
const PresentationStoreScript = preload("res://games/rollback_fighter/scripts/projects/ProjectPresentationStore.gd")
const AssetImporterScript = preload("res://games/rollback_fighter/scripts/projects/ProjectAssetImporter.gd")
const AudioImporterScript = preload("res://games/rollback_fighter/scripts/projects/ProjectAudioImporter.gd")


func resolve(project_id: String) -> Dictionary:
	if project_id.is_empty():
		return _builtin_result(true)
	var loaded_project := ProjectStoreScript.new().load_project(project_id)
	if not bool(loaded_project.get("ok", false)):
		return _builtin_result(false)
	var project: RollbackFighterGameProjectDefinition = loaded_project["project"]
	var definition := PresentationStoreScript.new().load_or_default(project_id, project.display_name)
	var image_importer := AssetImporterScript.new()
	var audio_importer := AudioImporterScript.new()
	var background := definition.background_image if image_importer.load_texture(definition.background_image) != null else ""
	var logo := definition.logo_image if image_importer.load_texture(definition.logo_image) != null else ""
	var audio: Dictionary = {}
	for slot_id in definition.audio_slots:
		var path := str(definition.audio_slots[slot_id])
		if audio_importer.load_stream(path) != null:
			audio[slot_id] = path
	return {
		"project": true,
		"legacy": false,
		"display_name": project.display_name,
		"background_image": background,
		"logo_image": logo,
		"floor_y_normalized": definition.floor_y_normalized,
		"audio_slots": audio,
		"fallback_background": background.is_empty(),
	}


func _builtin_result(legacy: bool) -> Dictionary:
	return {
		"project": false,
		"legacy": legacy,
		"display_name": "Hyperreality",
		"background_image": "",
		"logo_image": "",
		"floor_y_normalized": 0.80,
		"audio_slots": {},
		"fallback_background": true,
	}
