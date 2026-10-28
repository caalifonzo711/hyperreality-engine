extends RefCounted
class_name RollbackFighterCreatorBuilder

const LoaderScript = preload("res://games/rollback_fighter/scripts/config/CharacterDefinitionLoader.gd")
const AlignmentScript = preload("res://games/rollback_fighter/scripts/config/CreatorPresentationDraft.gd")
const ANIMATIONS := ["idle", "jab", "heavy", "block", "dodge", "hit", "dead"]
const PHASES := ["startup", "active", "recovery"]
const FPS := {"idle": 8000, "jab": 12000, "heavy": 10000, "block": 8000, "dodge": 12000, "hit": 12000, "dead": 1000}

var _loader: RollbackFighterCharacterDefinitionLoader = LoaderScript.new()


func build(fighter_id: String) -> Dictionary:
	if not _safe_id(fighter_id):
		return _fail("Invalid fighter ID.")
	var root: String = "user://characters/%s" % fighter_id
	var creator: Dictionary = _read_json(root + "/creator_manifest.json")
	var slot_manifest: Dictionary = _read_json(root + "/slot_manifest.json")
	var character: Dictionary = _read_json(root + "/character.json")
	var jab: Dictionary = _read_json(root + "/moves/jab.json")
	var heavy: Dictionary = _read_json(root + "/moves/heavy.json")
	var jab_hitbox: Dictionary = _read_json(root + "/hitboxes/jab.json")
	var heavy_hitbox: Dictionary = _read_json(root + "/hitboxes/heavy.json")
	if creator.is_empty() or str(creator.get("fighter_id", "")) != fighter_id:
		return _fail("Creator draft is missing or has a mismatched identity.")
	creator["playable"] = false
	creator["status"] = "building"
	creator["blocked_reason"] = "runtime package validation is in progress"
	if not _write_json(root + "/creator_manifest.json", creator):
		return _fail("Could not update the creator manifest.")
	var alignment: RollbackFighterCreatorPresentationDraft = AlignmentScript.new()
	if not alignment.configure(fighter_id):
		return _fail("Could not read sprite alignment data.")
	var sync: Dictionary = alignment.synchronize_slots(slot_manifest)
	if not bool(sync.get("ok", false)):
		return _fail("Some assigned sprite files are missing or invalid.")
	var required_missing: Array[String] = _missing_required(slot_manifest)
	if not required_missing.is_empty():
		return _fail("Missing required art: %s" % ", ".join(required_missing))
	var missing_alignment: PackedStringArray = alignment.get_missing_alignment_ids(slot_manifest)
	if not missing_alignment.is_empty():
		return _fail("Sprite alignment incomplete: %s" % ", ".join(missing_alignment))
	var move_errors: Array[Dictionary] = _loader.validate_creator_draft(
		character,
		{"light": jab, "heavy": heavy},
		{"light": jab_hitbox, "heavy": heavy_hitbox}
	)
	if not move_errors.is_empty():
		return _fail("Invalid fighter gameplay configuration.", move_errors)
	var presentation: Dictionary = _compile_presentation(fighter_id, slot_manifest, alignment)
	if presentation.is_empty():
		return _fail("Could not compile presentation data from the art slots.")
	var presentation_path: String = root + "/presentation.json"
	var old_presentation: String = _read_text(presentation_path)
	if not _write_json(presentation_path, presentation):
		return _fail("Could not write runtime presentation data.")
	var loaded: Dictionary = _loader.load_character(root, fighter_id)
	if not bool(loaded.get("ok", false)):
		if old_presentation.is_empty():
			DirAccess.remove_absolute(ProjectSettings.globalize_path(presentation_path))
		else:
			_write_text(presentation_path, old_presentation)
		return _fail("Generated fighter package failed runtime validation.", loaded.get("errors", []))
	creator["playable"] = true
	creator["status"] = "built"
	creator["blocked_reason"] = ""
	creator["built_package_version"] = 1
	if not _write_json(root + "/creator_manifest.json", creator):
		creator["playable"] = false
		creator["status"] = "alignment_complete"
		creator["blocked_reason"] = "could not commit built status"
		_write_json(root + "/creator_manifest.json", creator)
		return _fail("Could not finalize playable status.")
	return {"ok": true, "fighter_id": fighter_id, "definition": loaded["definition"], "presentation": presentation, "errors": []}


func _compile_presentation(fighter_id: String, manifest: Dictionary, alignment: RollbackFighterCreatorPresentationDraft) -> Dictionary:
	var animations_manifest: Dictionary = manifest.get("animations", {})
	var animations: Dictionary = {}
	var phase_mapping: Dictionary = {}
	for animation_id in ANIMATIONS:
		if not animations_manifest.has(animation_id):
			return {}
		if animation_id in ["jab", "heavy"]:
			continue
		var simple_frames: Array = _compile_simple_frames(animations_manifest[animation_id], alignment)
		if simple_frames.is_empty():
			return {}
		animations[animation_id] = {
			"playback": _simple_playback(animation_id, simple_frames.size()),
			"fps_milli": int(FPS[animation_id]),
			"frames": simple_frames,
		}

	var jab_result: Dictionary = _compile_attack_frames(animations_manifest["jab"], alignment)
	if jab_result.is_empty():
		return {}
	animations["jab"] = {
		"playback": "attack_phase_map",
		"fps_milli": int(FPS["jab"]),
		"frames": jab_result["frames"],
	}
	phase_mapping["jab"] = jab_result["phase_frames"]

	var heavy_result: Dictionary = _compile_heavy_frames(
		animations_manifest["heavy"], alignment, jab_result
	)
	if heavy_result.is_empty():
		return {}
	animations["heavy"] = {
		"playback": "attack_phase_map",
		"fps_milli": int(FPS["heavy"]),
		"frames": heavy_result["frames"],
	}
	phase_mapping["heavy"] = heavy_result["phase_frames"]
	return {
		"config_version": 1,
		"fighter_id": fighter_id,
		"source_art_faces": "left",
		"animations": animations,
		"state_to_animation": {"idle": "idle", "block": "block", "dodge": "dodge", "hurt": "hit", "dead": "dead"},
		"attack_phase_to_frames": phase_mapping,
	}


func _simple_playback(animation_id: String, frame_count: int) -> String:
	if animation_id == "idle":
		return "loop_fps"
	if animation_id == "dodge":
		return "state_stretched"
	return "loop_fps" if frame_count > 1 else "hold"


func _compile_simple_frames(value: Variant, alignment: RollbackFighterCreatorPresentationDraft) -> Array:
	var frames: Array = []
	if not value is Array:
		return frames
	for slot_value in value:
		if not slot_value is Dictionary:
			return []
		var slot: Dictionary = slot_value
		if not bool(slot.get("assigned", false)):
			continue
		var frame: Dictionary = _runtime_frame(str(slot.get("slot", "")), alignment)
		if frame.is_empty():
			return []
		frames.append(frame)
	return frames


func _compile_attack_frames(value: Variant, alignment: RollbackFighterCreatorPresentationDraft) -> Dictionary:
	if not value is Dictionary:
		return {}
	var frames: Array = []
	var phase_frames: Dictionary = {}
	for phase in PHASES:
		var phase_value: Variant = value.get(phase, {})
		if not phase_value is Dictionary:
			return {}
		var slots_value: Variant = Dictionary(phase_value).get("slots", [])
		if not slots_value is Array:
			return {}
		var indices: Array[int] = []
		for slot_value in slots_value:
			if not slot_value is Dictionary:
				return {}
			var slot: Dictionary = slot_value
			if not bool(slot.get("assigned", false)):
				continue
			var frame: Dictionary = _runtime_frame(str(slot.get("slot", "")), alignment)
			if frame.is_empty():
				return {}
			indices.append(frames.size())
			frames.append(frame)
		phase_frames[phase] = indices
	if frames.is_empty() or Array(phase_frames.get("startup", [])).is_empty() or Array(phase_frames.get("active", [])).is_empty():
		return {}
	if Array(phase_frames["recovery"]).is_empty():
		phase_frames["recovery"] = Array(phase_frames["startup"]).duplicate()
	return {"frames": frames, "phase_frames": phase_frames}


func _compile_heavy_frames(
	value: Variant,
	alignment: RollbackFighterCreatorPresentationDraft,
	jab_result: Dictionary
) -> Dictionary:
	if not value is Dictionary:
		return {}
	var has_assigned_heavy_art: bool = _contains_assigned_slot(value)
	if not has_assigned_heavy_art:
		return {
			"frames": Array(jab_result["frames"]).duplicate(true),
			"phase_frames": Dictionary(jab_result["phase_frames"]).duplicate(true),
		}
	var frames: Array = []
	var phase_frames: Dictionary = {}
	var jab_frames: Array = jab_result["frames"]
	var jab_phase_frames: Dictionary = jab_result["phase_frames"]
	for phase in PHASES:
		var phase_value: Variant = value.get(phase, {})
		if not phase_value is Dictionary:
			return {}
		var slots_value: Variant = Dictionary(phase_value).get("slots", [])
		if not slots_value is Array:
			return {}
		var indices: Array[int] = []
		for slot_value in slots_value:
			if not slot_value is Dictionary:
				return {}
			var slot: Dictionary = slot_value
			if not bool(slot.get("assigned", false)):
				continue
			var frame: Dictionary = _runtime_frame(str(slot.get("slot", "")), alignment)
			if frame.is_empty():
				return {}
			indices.append(frames.size())
			frames.append(frame)
		if indices.is_empty():
			for jab_index_value in Array(jab_phase_frames.get(phase, [])):
				var jab_index: int = int(jab_index_value)
				if jab_index < 0 or jab_index >= jab_frames.size():
					return {}
				indices.append(frames.size())
				frames.append(Dictionary(jab_frames[jab_index]).duplicate(true))
		if indices.is_empty():
			return {}
		phase_frames[phase] = indices
	return {"frames": frames, "phase_frames": phase_frames}


func _contains_assigned_slot(value: Variant) -> bool:
	if value is Dictionary:
		var item: Dictionary = value
		if item.has("slot") and bool(item.get("assigned", false)):
			return true
		for child in item.values():
			if _contains_assigned_slot(child):
				return true
	elif value is Array:
		for child in value:
			if _contains_assigned_slot(child):
				return true
	return false


func _runtime_frame(slot_id: String, alignment: RollbackFighterCreatorPresentationDraft) -> Dictionary:
	if not alignment.slots.has(slot_id):
		return {}
	var entry: Dictionary = alignment.slots[slot_id]
	if str(entry.get("status", "")) != "aligned":
		return {}
	var path: String = str(entry.get("path", ""))
	if path != "sprites/%s.png" % slot_id:
		return {}
	var anchor: Array = entry.get("feet_anchor", [])
	var scale_milli: int = int(entry.get("scale_milli", 0))
	if anchor.size() != 2 or scale_milli < AlignmentScript.SCALE_MIN or scale_milli > AlignmentScript.SCALE_MAX:
		return {}
	return {
		"sprite": path,
		"feet_anchor": {"x": int(anchor[0]), "y": int(anchor[1])},
		"scale_milli": scale_milli,
	}


func _missing_required(value: Variant) -> Array[String]:
	var result: Array[String] = []
	_collect_missing(value, result)
	return result


func _collect_missing(value: Variant, output: Array[String]) -> void:
	if value is Dictionary:
		var item: Dictionary = value
		if item.has("slot") and bool(item.get("required", false)) and not bool(item.get("assigned", false)):
			output.append(str(item.get("slot", "")))
		for child in item.values():
			_collect_missing(child, output)
	elif value is Array:
		for child in value:
			_collect_missing(child, output)


func _read_json(path: String) -> Dictionary:
	var text: String = _read_text(path)
	var parsed: Variant = JSON.parse_string(text) if not text.is_empty() else null
	return parsed if parsed is Dictionary else {}


func _read_text(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var value: String = file.get_as_text()
	file.close()
	return value


func _write_json(path: String, value: Dictionary) -> bool:
	return _write_text(path, JSON.stringify(value, "\t", false) + "\n")


func _write_text(path: String, value: String) -> bool:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(value)
	file.flush()
	file.close()
	return true


func _safe_id(value: String) -> bool:
	if value.is_empty():
		return false
	for index in value.length():
		var code: int = value.unicode_at(index)
		if not ((code >= 97 and code <= 122) or (code >= 48 and code <= 57) or code == 95):
			return false
	return true


func _fail(message: String, details: Variant = []) -> Dictionary:
	if OS.is_debug_build() and details is Array:
		for error in details:
			push_warning("[CreatorBuild] %s" % str(error))
	return {"ok": false, "message": message, "errors": details}
