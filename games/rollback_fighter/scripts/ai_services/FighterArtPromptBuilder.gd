extends RefCounted
class_name RollbackFighterArtPromptBuilder

const ImageRequestScript = preload("res://games/rollback_fighter/scripts/ai_services/AIImageRequest.gd")
const ArtImporter = preload("res://games/rollback_fighter/scripts/config/CreatorArtImporter.gd")


func build_request(draft, slot_id: String):
	var slot_context: Dictionary = find_slot_context(draft.slot_manifest, slot_id)
	if slot_context.is_empty():
		return null
	var slot: Dictionary = slot_context.slot
	var group_id: String = str(slot.get("group_id", slot_context.get("group_id", "")))
	var phase: String = str(slot.get("phase", slot_context.get("phase", "")))
	var all_group_metadata: Dictionary = draft.slot_manifest.get("group_metadata", {})
	var group_metadata: Dictionary = all_group_metadata.get(group_id, {})
	var prompt_parts := PackedStringArray([
		"Create exactly one full-body 2D fighting-game character sprite drawing.",
		"Fighter name: %s." % draft.fighter_name,
		"Character appearance: %s." % (draft.visual_description if not draft.visual_description.strip_edges().is_empty() else "Use a consistent, readable original fighter design"),
		"Game presentation style: %s." % str(draft.presentation_style_id).replace("_", " ").capitalize(),
		"Manifest slot: %s (%s)." % [slot_id, str(slot.get("display_name", slot_id))],
		"Animation group: %s. %s" % [group_id, str(group_metadata.get("help_text", ""))],
		"Pose direction: %s" % _pose_direction(group_id, phase),
		"Keep the entire fighter visible, centered, with consistent costume, proportions, facing direction, and camera angle.",
		"No scenery, floor, text, UI, border, extra characters, duplicated limbs, or sprite sheet.",
		"Prefer a transparent background. Return one isolated pose only.",
	])
	var slot_help: String = str(slot.get("help_text", "")).strip_edges()
	if not slot_help.is_empty():
		prompt_parts.append("Slot guidance: %s" % slot_help)
	var request = ImageRequestScript.new()
	request.prompt = "\n".join(prompt_parts)
	request.width = 1024
	request.height = 1024
	request.aspect_ratio = "1:1"
	request.transparent_background = true
	request.output_count = 1
	var reference: Dictionary = _load_reference_image(draft)
	if not reference.is_empty():
		request.reference_images.append(reference)
	return request


func find_slot_context(slot_manifest: Dictionary, slot_id: String) -> Dictionary:
	var animations: Dictionary = slot_manifest.get("animations", {})
	for group_value: Variant in slot_manifest.get("group_order", animations.keys()):
		var group_id: String = str(group_value)
		if not animations.has(group_id):
			continue
		var group: Variant = animations[group_id]
		if group is Array:
			for slot_value: Variant in group:
				if slot_value is Dictionary and str(slot_value.get("slot", "")) == slot_id:
					return {"slot": slot_value, "group_id": group_id, "phase": ""}
		elif group is Dictionary:
			for phase: String in ["startup", "active", "recovery"]:
				var phase_data: Variant = group.get(phase, {})
				if not phase_data is Dictionary:
					continue
				for slot_value: Variant in phase_data.get("slots", []):
					if slot_value is Dictionary and str(slot_value.get("slot", "")) == slot_id:
						return {"slot": slot_value, "group_id": group_id, "phase": phase}
	return {}


func _pose_direction(group_id: String, phase: String) -> String:
	if group_id == "idle":
		return "a neutral ready fighting stance"
	if group_id == "block":
		return "a clear defensive blocking pose"
	if group_id == "dodge":
		return "an evasive movement pose with a readable silhouette"
	if group_id == "hit":
		return "a readable reaction to taking damage"
	if group_id == "dead":
		return "a defeated or knockout pose"
	if phase == "startup":
		return "anticipation or wind-up before the %s connects" % group_id
	if phase == "active":
		return "the %s fully extended at its strongest impact moment" % group_id
	if phase == "recovery":
		return "the follow-through and recovery after the %s" % group_id
	return "a readable %s animation pose" % group_id


func _load_reference_image(draft) -> Dictionary:
	var preferred: PackedStringArray = PackedStringArray(["idle_0"])
	for context in _ordered_slot_contexts(draft.slot_manifest):
		var candidate: Dictionary = context.slot
		var candidate_id: String = str(candidate.get("slot", ""))
		if bool(candidate.get("assigned", false)) and not preferred.has(candidate_id):
			preferred.append(candidate_id)
	for slot_id: String in preferred:
		var context: Dictionary = find_slot_context(draft.slot_manifest, slot_id)
		if context.is_empty() or not bool(context.slot.get("assigned", false)):
			continue
		var path: String = "%s/sprites/%s.png" % [draft.get_user_draft_path(), slot_id]
		var file: FileAccess = FileAccess.open(path, FileAccess.READ)
		if file == null:
			continue
		var size: int = file.get_length()
		if size <= 0 or size > ArtImporter.MAX_FILE_BYTES:
			file.close()
			continue
		var bytes: PackedByteArray = file.get_buffer(size)
		file.close()
		var image := Image.new()
		if image.load_png_from_buffer(bytes) == OK and not image.is_empty():
			return {"bytes": bytes, "mime_type": "image/png", "source_slot_id": slot_id}
	return {}


func _ordered_slot_contexts(slot_manifest: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var animations: Dictionary = slot_manifest.get("animations", {})
	for group_value: Variant in slot_manifest.get("group_order", animations.keys()):
		var group_id: String = str(group_value)
		var group: Variant = animations.get(group_id, [])
		if group is Array:
			for slot_value: Variant in group:
				if slot_value is Dictionary:
					result.append({"slot": slot_value, "group_id": group_id, "phase": ""})
		elif group is Dictionary:
			var phase_groups: Dictionary = group
			for phase: String in ["startup", "active", "recovery"]:
				var phase_data: Dictionary = phase_groups.get(phase, {})
				for slot_value: Variant in phase_data.get("slots", []):
					if slot_value is Dictionary:
						result.append({"slot": slot_value, "group_id": group_id, "phase": phase})
	return result
