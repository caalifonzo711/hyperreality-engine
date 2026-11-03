extends RefCounted
class_name RollbackFighterProjectPresentationDefinition


const CURRENT_VERSION := 1
const AUDIO_SLOT_IDS := [
	"menu_confirm",
	"menu_cancel",
	"jab_swing",
	"heavy_swing",
	"hit_light",
	"hit_heavy",
	"block",
	"dodge",
	"ko",
	"round_start",
	"round_end",
	"bgm",
]

var project_id: String = ""
var display_name: String = ""
var version: int = CURRENT_VERSION
var background_image: String = ""
var logo_image: String = ""
var music_track: String = ""
var floor_y_normalized: float = 0.80
var audio_slots: Dictionary = {}


func configure(requested_project_id: String, requested_display_name: String) -> void:
	project_id = requested_project_id
	display_name = requested_display_name.strip_edges()


func set_audio_slot(slot_id: String, asset_path: String) -> bool:
	if slot_id not in AUDIO_SLOT_IDS or not _is_safe_asset_path(asset_path, "audio"):
		return false
	if asset_path.is_empty():
		audio_slots.erase(slot_id)
	else:
		audio_slots[slot_id] = asset_path
	if slot_id == "bgm":
		music_track = asset_path
	return true


func validate() -> Array[Dictionary]:
	var errors: Array[Dictionary] = []
	if not RollbackFighterGameProjectDefinition.is_safe_id(project_id):
		errors.append(_error("PRESENTATION_PROJECT_ID_INVALID", "project_id", project_id, "must match [a-z0-9_]+"))
	if display_name.is_empty():
		errors.append(_error("PRESENTATION_NAME_REQUIRED", "display_name", display_name, "must not be empty"))
	if version <= 0:
		errors.append(_error("PRESENTATION_VERSION_INVALID", "version", version, "must be positive"))
	if floor_y_normalized < 0.0 or floor_y_normalized > 1.0:
		errors.append(_error("PRESENTATION_FLOOR_INVALID", "floor_y_normalized", floor_y_normalized, "must be between 0 and 1"))
	if not _is_safe_asset_path(background_image, "backgrounds"):
		errors.append(_error("PRESENTATION_BACKGROUND_PATH_INVALID", "background_image", background_image, "must remain inside this project's backgrounds folder"))
	if not _is_safe_asset_path(logo_image, "branding"):
		errors.append(_error("PRESENTATION_LOGO_PATH_INVALID", "logo_image", logo_image, "must remain inside this project's branding folder"))
	for value in audio_slots:
		var slot_id := str(value)
		if slot_id not in AUDIO_SLOT_IDS:
			errors.append(_error("PRESENTATION_AUDIO_SLOT_INVALID", "audio_slots", slot_id, "must be a known audio slot"))
		elif not _is_safe_asset_path(str(audio_slots[slot_id]), "audio"):
			errors.append(_error("PRESENTATION_AUDIO_PATH_INVALID", slot_id, audio_slots[slot_id], "must remain inside this project's audio folder"))
	if not music_track.is_empty() and music_track != str(audio_slots.get("bgm", "")):
		errors.append(_error("PRESENTATION_BGM_MISMATCH", "music_track", music_track, "must match the bgm audio mapping"))
	return errors


func to_dictionary() -> Dictionary:
	return {
		"project_id": project_id,
		"display_name": display_name,
		"version": version,
		"background_image": background_image,
		"logo_image": logo_image,
		"music_track": music_track,
		"floor_y_normalized": floor_y_normalized,
		"audio_slots": audio_slots.duplicate(true),
	}


static func from_dictionary(document: Dictionary) -> Dictionary:
	var definition := RollbackFighterProjectPresentationDefinition.new()
	definition.project_id = str(document.get("project_id", ""))
	definition.display_name = str(document.get("display_name", "")).strip_edges()
	definition.version = int(document.get("version", 0))
	definition.background_image = str(document.get("background_image", ""))
	definition.logo_image = str(document.get("logo_image", ""))
	definition.floor_y_normalized = float(document.get("floor_y_normalized", 0.80))
	var mappings: Variant = document.get("audio_slots", {})
	if not mappings is Dictionary:
		return {"ok": false, "presentation": null, "errors": [definition._error("PRESENTATION_AUDIO_MAP_INVALID", "audio_slots", mappings, "must be an object")]}
	definition.audio_slots = Dictionary(mappings).duplicate(true)
	definition.music_track = str(document.get("music_track", definition.audio_slots.get("bgm", "")))
	var errors := definition.validate()
	return {"ok": errors.is_empty(), "presentation": definition if errors.is_empty() else null, "errors": errors}


func _is_safe_asset_path(path: String, folder: String) -> bool:
	if path.is_empty():
		return true
	var prefix := "user://games/%s/assets/%s/" % [project_id, folder]
	return path.begins_with(prefix) and not path.contains("..") and not path.contains("\\")


func _error(code: String, field: String, value: Variant, rule: String) -> Dictionary:
	return {"code": code, "file": "presentation.json", "field": field, "invalid_value": value, "expected_rule": rule}
