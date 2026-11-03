extends RefCounted
class_name RollbackFighterPresentationManifest


const KNOWN_GROUPS := ["idle", "jab", "heavy", "block", "dodge", "hit", "dead"]
const KNOWN_PHASES := ["", "startup", "active", "recovery"]
const KNOWN_STYLES := ["platform_fighter", "footsies", "anime_fighter", "custom"]

var manifest_id: String = ""
var manifest_version: int = 0
var style_preset: String = ""
var display_name: String = ""
var help_text: String = ""
var groups: Array[Dictionary] = []


func configure(document: Dictionary) -> void:
	manifest_id = str(document.get("manifest_id", ""))
	manifest_version = int(document.get("manifest_version", 0))
	style_preset = str(document.get("style_preset", ""))
	display_name = str(document.get("display_name", ""))
	help_text = str(document.get("help_text", ""))
	groups.clear()
	var group_values: Variant = document.get("groups", [])
	if group_values is Array:
		for value in group_values:
			if value is Dictionary:
				groups.append(Dictionary(value).duplicate(true))


func validate() -> Array[Dictionary]:
	var errors: Array[Dictionary] = []
	if not is_safe_id(manifest_id):
		_add_error(errors, "PRESENTATION_MANIFEST_ID_INVALID", "manifest_id", manifest_id, "must match [a-z0-9_]+")
	if manifest_version <= 0:
		_add_error(errors, "PRESENTATION_MANIFEST_VERSION_INVALID", "manifest_version", manifest_version, "must be positive")
	if display_name.is_empty() or style_preset not in KNOWN_STYLES:
		_add_error(errors, "PRESENTATION_MANIFEST_METADATA_MISSING", "display_name", display_name, "display name and style preset are required")
	var group_ids := PackedStringArray()
	var slot_ids := PackedStringArray()
	var fallback_slots := PackedStringArray()
	var fallback_groups := PackedStringArray()
	for group in groups:
		var group_id: String = str(group.get("group_id", ""))
		if group_id not in KNOWN_GROUPS or group_ids.has(group_id):
			_add_error(errors, "PRESENTATION_GROUP_INVALID", "group_id", group_id, "must be a unique supported animation group")
		else:
			group_ids.append(group_id)
		if str(group.get("display_name", "")).is_empty() or int(group.get("ordering", -1)) < 0:
			_add_error(errors, "PRESENTATION_GROUP_METADATA_MISSING", group_id, group, "display_name and non-negative ordering are required")
		var recommended: int = int(group.get("recommended_drawing_count", -1))
		var slots_value: Variant = group.get("slots", [])
		if recommended <= 0 or not slots_value is Array or recommended != Array(slots_value).size():
			_add_error(errors, "PRESENTATION_GROUP_COUNT_INVALID", group_id, recommended, "recommended count must equal the positive slot count")
			continue
		var fallback_group: String = str(group.get("fallback_group", ""))
		if not fallback_group.is_empty():
			fallback_groups.append(fallback_group)
		var seen_phases := PackedStringArray()
		for slot_value in slots_value:
			if not slot_value is Dictionary:
				_add_error(errors, "PRESENTATION_SLOT_INVALID", group_id, slot_value, "every slot must be an object")
				continue
			var slot: Dictionary = slot_value
			var slot_id: String = str(slot.get("slot_id", ""))
			if not is_safe_id(slot_id) or slot_ids.has(slot_id):
				_add_error(errors, "PRESENTATION_SLOT_ID_INVALID", "slot_id", slot_id, "must be a unique [a-z0-9_]+ ID")
			else:
				slot_ids.append(slot_id)
			if str(slot.get("group_id", "")) != group_id or str(slot.get("display_name", "")).is_empty():
				_add_error(errors, "PRESENTATION_SLOT_METADATA_MISSING", slot_id, slot, "group_id and display_name must match the containing group")
			var phase: String = str(slot.get("phase", ""))
			if not phase.is_empty() and not seen_phases.has(phase):
				seen_phases.append(phase)
			if phase not in KNOWN_PHASES or (group_id in ["jab", "heavy"] and phase.is_empty()) or (group_id not in ["jab", "heavy"] and not phase.is_empty()):
				_add_error(errors, "PRESENTATION_SLOT_PHASE_INVALID", slot_id, phase, "phase must match the group type")
			if typeof(slot.get("required", null)) != TYPE_BOOL or int(slot.get("ordering", -1)) < 0 or int(slot.get("recommended_drawing_count", -1)) <= 0:
				_add_error(errors, "PRESENTATION_SLOT_METADATA_INVALID", slot_id, slot, "required, ordering, and non-negative recommendation metadata are required")
			var fallback_slot: String = str(slot.get("fallback_slot", ""))
			if not fallback_slot.is_empty():
				fallback_slots.append(fallback_slot)
		if group_id in ["jab", "heavy"]:
			for required_phase in ["startup", "active", "recovery"]:
				if not seen_phases.has(required_phase):
					_add_error(errors, "PRESENTATION_PHASE_MISSING", group_id, required_phase, "attack groups require startup, active, and recovery slots")
	for expected_group in KNOWN_GROUPS:
		if not group_ids.has(expected_group):
			_add_error(errors, "PRESENTATION_GROUP_MISSING", "group_id", expected_group, "every supported presentation group is required")
	for fallback_group in fallback_groups:
		if not group_ids.has(fallback_group):
			_add_error(errors, "PRESENTATION_FALLBACK_GROUP_INVALID", "fallback_group", fallback_group, "must reference an existing group")
	for fallback_slot in fallback_slots:
		if not slot_ids.has(fallback_slot):
			_add_error(errors, "PRESENTATION_FALLBACK_SLOT_INVALID", "fallback_slot", fallback_slot, "must reference an existing slot")
	return errors


func required_count() -> int:
	var count: int = 0
	for group in groups:
		for slot in Array(group.get("slots", [])):
			if slot is Dictionary and bool(slot.get("required", false)):
				count += 1
	return count


func optional_count() -> int:
	var count: int = 0
	for group in groups:
		count += Array(group.get("slots", [])).size()
	return count - required_count()


func get_slot_ids() -> PackedStringArray:
	var result := PackedStringArray()
	for group in groups:
		for slot in Array(group.get("slots", [])):
			if slot is Dictionary:
				result.append(str(slot.get("slot_id", "")))
	return result


func to_slot_manifest(move_documents: Dictionary, previous: Dictionary = {}) -> Dictionary:
	if not validate().is_empty():
		return {}
	var animations: Dictionary = {}
	var group_order := PackedStringArray()
	var group_metadata: Dictionary = {}
	for group in groups:
		var group_id: String = str(group["group_id"])
		group_order.append(group_id)
		group_metadata[group_id] = {
			"display_name": str(group["display_name"]),
			"ordering": int(group["ordering"]),
			"recommended_drawing_count": int(group["recommended_drawing_count"]),
			"fallback_group": str(group.get("fallback_group", "")),
			"help_text": str(group.get("help_text", "")),
		}
		if group_id in ["jab", "heavy"]:
			var phases: Dictionary = {}
			var move_slot: String = "light" if group_id == "jab" else "heavy"
			var move: Dictionary = move_documents.get(move_slot, {})
			for phase in ["startup", "active", "recovery"]:
				var phase_slots: Array = []
				for slot in Array(group["slots"]):
					if str(slot.get("phase", "")) == phase:
						phase_slots.append(_runtime_slot(slot, previous))
				phases[phase] = {
					"simulation_frames": int(move.get(phase, 0)),
					"recommended_drawings": phase_slots.size(),
					"slots": phase_slots,
				}
			animations[group_id] = phases
		else:
			var simple_slots: Array = []
			for slot in Array(group["slots"]):
				simple_slots.append(_runtime_slot(slot, previous))
			animations[group_id] = simple_slots
	return {
		"manifest_id": manifest_id,
		"manifest_version": manifest_version,
		"style_preset": style_preset,
		"display_name": display_name,
		"help_text": help_text,
		"group_order": group_order,
		"group_metadata": group_metadata,
		"animations": animations,
	}


static func validate_slot_manifest(document: Dictionary) -> Array[Dictionary]:
	var errors: Array[Dictionary] = []
	var is_legacy: bool = not document.has("manifest_id")
	if not is_legacy:
		if not is_safe_id(str(document.get("manifest_id", ""))) or int(document.get("manifest_version", 0)) <= 0 or str(document.get("style_preset", "")).is_empty():
			errors.append(_static_error("PRESENTATION_MANIFEST_IDENTITY_INVALID", "manifest_id", document.get("manifest_id"), "new manifests require safe identity, style, and positive version"))
	var animations_value: Variant = document.get("animations", {})
	if not animations_value is Dictionary:
		return [{"code": "PRESENTATION_ANIMATIONS_INVALID", "file": "slot_manifest.json", "field": "animations", "invalid_value": animations_value, "expected_rule": "must be an object"}]
	var animations: Dictionary = animations_value
	var slot_ids := PackedStringArray()
	var fallback_slots := PackedStringArray()
	var group_ids := PackedStringArray()
	for group_id in animations:
		var group: String = str(group_id)
		if group not in KNOWN_GROUPS:
			errors.append(_static_error("PRESENTATION_GROUP_INVALID", "group_id", group, "must be supported"))
		else:
			group_ids.append(group)
		var value: Variant = animations[group_id]
		if (group in ["jab", "heavy"] and not value is Dictionary) or (group not in ["jab", "heavy"] and not value is Array):
			errors.append(_static_error("PRESENTATION_GROUP_SHAPE_INVALID", group, value, "attack groups require phases and pose groups require slot arrays"))
			continue
		if value is Array:
			_validate_runtime_slots(value, group, "", is_legacy, slot_ids, fallback_slots, errors)
		elif value is Dictionary:
			var seen_phases := PackedStringArray()
			for phase in value:
				if str(phase) not in ["startup", "active", "recovery"] or not value[phase] is Dictionary:
					errors.append(_static_error("PRESENTATION_PHASE_INVALID", group, phase, "must be startup, active, or recovery metadata"))
					continue
				var phase_data: Dictionary = value[phase]
				seen_phases.append(str(phase))
				if int(phase_data.get("recommended_drawings", -1)) < 0 or not phase_data.get("slots", []) is Array or int(phase_data.get("recommended_drawings", -1)) != Array(phase_data.get("slots", [])).size():
					errors.append(_static_error("PRESENTATION_PHASE_COUNT_INVALID", str(phase), phase_data, "requires non-negative recommendation and slots"))
					continue
				_validate_runtime_slots(phase_data["slots"], group, str(phase), is_legacy, slot_ids, fallback_slots, errors)
			for required_phase in ["startup", "active", "recovery"]:
				if not seen_phases.has(required_phase):
					errors.append(_static_error("PRESENTATION_PHASE_MISSING", group, required_phase, "attack groups require all phases"))
		else:
			errors.append(_static_error("PRESENTATION_GROUP_INVALID", group, value, "must contain slots or phases"))
	for fallback_slot in fallback_slots:
		if not slot_ids.has(fallback_slot):
			errors.append(_static_error("PRESENTATION_FALLBACK_SLOT_INVALID", "fallback_slot", fallback_slot, "must reference an existing slot"))
	for expected_group in KNOWN_GROUPS:
		if not group_ids.has(expected_group):
			errors.append(_static_error("PRESENTATION_GROUP_MISSING", "group_id", expected_group, "every supported presentation group is required"))
	if not is_legacy:
		var metadata_value: Variant = document.get("group_metadata", {})
		if not metadata_value is Dictionary:
			errors.append(_static_error("PRESENTATION_GROUP_METADATA_INVALID", "group_metadata", metadata_value, "must be an object"))
		else:
			for group_id in group_ids:
				var metadata: Dictionary = Dictionary(metadata_value).get(group_id, {})
				if metadata.is_empty() or str(metadata.get("display_name", "")).is_empty() or int(metadata.get("recommended_drawing_count", -1)) < 0:
					errors.append(_static_error("PRESENTATION_GROUP_METADATA_INVALID", group_id, metadata, "new manifests require group display and recommendation metadata"))
				var fallback_group: String = str(metadata.get("fallback_group", ""))
				if not fallback_group.is_empty() and not group_ids.has(fallback_group):
					errors.append(_static_error("PRESENTATION_FALLBACK_GROUP_INVALID", group_id, fallback_group, "must reference an existing group"))
	return errors


static func manifest_identity(document: Dictionary) -> Dictionary:
	if not document.has("manifest_id"):
		return {"manifest_id": "platform_fighter_v1", "manifest_version": 1, "style_preset": "platform_fighter", "legacy": true}
	return {"manifest_id": str(document.get("manifest_id", "")), "manifest_version": int(document.get("manifest_version", 0)), "style_preset": str(document.get("style_preset", "")), "legacy": false}


func _runtime_slot(slot: Dictionary, previous: Dictionary) -> Dictionary:
	var slot_id: String = str(slot["slot_id"])
	var result: Dictionary = {
		"slot": slot_id,
		"slot_id": slot_id,
		"group_id": str(slot["group_id"]),
		"display_name": str(slot["display_name"]),
		"required": bool(slot["required"]),
		"optional": not bool(slot["required"]),
		"phase": str(slot.get("phase", "")),
		"recommended_drawing_count": int(slot.get("recommended_drawing_count", 1)),
		"fallback_slot": str(slot.get("fallback_slot", "")),
		"ordering": int(slot["ordering"]),
		"help_text": str(slot.get("help_text", "")),
		"assigned": false,
	}
	var old: Dictionary = _find_runtime_slot(previous, slot_id)
	for key in ["assigned", "path", "display_filename", "width", "height"]:
		if old.has(key):
			result[key] = old[key]
	return result


static func _find_runtime_slot(value: Variant, slot_id: String) -> Dictionary:
	if value is Dictionary:
		if str(value.get("slot", "")) == slot_id:
			return value
		for child in value.values():
			var found: Dictionary = _find_runtime_slot(child, slot_id)
			if not found.is_empty():
				return found
	elif value is Array:
		for child in value:
			var found: Dictionary = _find_runtime_slot(child, slot_id)
			if not found.is_empty():
				return found
	return {}


static func _validate_runtime_slots(values: Array, group: String, phase: String, legacy: bool, ids: PackedStringArray, fallbacks: PackedStringArray, errors: Array[Dictionary]) -> void:
	for value in values:
		if not value is Dictionary:
			errors.append(_static_error("PRESENTATION_SLOT_INVALID", group, value, "must be an object"))
			continue
		var slot: Dictionary = value
		var slot_id: String = str(slot.get("slot", ""))
		if not is_safe_id(slot_id) or ids.has(slot_id):
			errors.append(_static_error("PRESENTATION_SLOT_ID_INVALID", "slot", slot_id, "must be unique and safe"))
		else:
			ids.append(slot_id)
		if typeof(slot.get("required", null)) != TYPE_BOOL:
			errors.append(_static_error("PRESENTATION_SLOT_REQUIRED_INVALID", slot_id, slot.get("required"), "must be boolean"))
		if not legacy and (str(slot.get("group_id", "")) != group or str(slot.get("phase", "")) != phase or str(slot.get("display_name", "")).is_empty()):
			errors.append(_static_error("PRESENTATION_SLOT_METADATA_MISSING", slot_id, slot, "new manifests require group, phase, and display metadata"))
		var fallback: String = str(slot.get("fallback_slot", ""))
		if not fallback.is_empty():
			fallbacks.append(fallback)


static func is_safe_id(value: String) -> bool:
	if value.is_empty():
		return false
	for index in value.length():
		var code: int = value.unicode_at(index)
		if not ((code >= 97 and code <= 122) or (code >= 48 and code <= 57) or code == 95):
			return false
	return true


func _add_error(errors: Array[Dictionary], code: String, field: String, value: Variant, rule: String) -> void:
	errors.append(_static_error(code, field, value, rule))


static func _static_error(code: String, field: String, value: Variant, rule: String) -> Dictionary:
	return {"code": code, "file": "fighter_presentation_manifest", "field": field, "invalid_value": value, "expected_rule": rule}
