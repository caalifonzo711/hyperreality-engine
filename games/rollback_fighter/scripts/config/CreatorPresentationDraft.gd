extends RefCounted
class_name RollbackFighterCreatorPresentationDraft

const FILE_NAME := "presentation_draft.json"
const SCALE_MIN: int = 50
const SCALE_MAX: int = 4000
const AUTO_FIT_REFERENCE_PRESENTATION := "res://games/rollback_fighter/characters/example_fighter/presentation.json"
const AUTO_FIT_REFERENCE_ANIMATION := "idle"
const AUTO_FIT_SOURCE_SLOT := "idle_0"
const ANIMATION_ORDER := ["idle", "jab", "heavy", "block", "dodge", "hit", "dead"]
const PHASE_ORDER := ["startup", "active", "recovery"]

var fighter_id: String = ""
var draft_root: String = ""
var slots: Dictionary = {}
var last_error: String = ""


func configure(requested_id: String) -> bool:
	if not _is_safe_id(requested_id):
		last_error = "Invalid fighter ID."
		return false
	fighter_id = requested_id
	draft_root = "user://characters/%s" % fighter_id
	slots.clear()
	var path: String = draft_root + "/" + FILE_NAME
	if not FileAccess.file_exists(path):
		return true
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		last_error = "Could not read presentation draft."
		return false
	var parser: JSON = JSON.new()
	var parse_error: Error = parser.parse(file.get_as_text())
	file.close()
	if parse_error != OK or not parser.data is Dictionary:
		last_error = "Presentation draft is malformed."
		return false
	var document: Dictionary = parser.data
	var version_value: Variant = document.get("version", 0)
	var version_valid: bool = false
	if typeof(version_value) == TYPE_INT:
		version_valid = int(version_value) == 1
	elif typeof(version_value) == TYPE_FLOAT:
		version_valid = is_finite(float(version_value)) and float(version_value) == 1.0
	if not version_valid or not (document.get("slots", {}) is Dictionary):
		last_error = "Presentation draft has an unsupported format."
		return false
	var stored_slots: Dictionary = document["slots"]
	for slot_id_value in stored_slots:
		var slot_id: String = str(slot_id_value)
		var value: Variant = stored_slots[slot_id_value]
		if _is_safe_slot_id(slot_id) and value is Dictionary:
			var entry: Dictionary = value.duplicate(true)
			if _valid_relative_path(slot_id, str(entry.get("path", ""))):
				var scale_value: Variant = entry.get("scale_milli", 0)
				if _is_exact_integer(scale_value):
					entry["scale_milli"] = int(scale_value)
				var anchor_value: Variant = entry.get("feet_anchor", [])
				if anchor_value is Array and anchor_value.size() == 2 and _is_exact_integer(anchor_value[0]) and _is_exact_integer(anchor_value[1]):
					entry["feet_anchor"] = [int(anchor_value[0]), int(anchor_value[1])]
				entry["status"] = "needs_alignment"
				slots[slot_id] = entry
	return true


func ensure_slot(slot_id: String, relative_path: String, image_width: int, image_height: int) -> bool:
	if not _is_safe_slot_id(slot_id) or not _valid_relative_path(slot_id, relative_path):
		last_error = "Slot ID or relative sprite path is invalid."
		return false
	if image_width <= 0 or image_height <= 0:
		last_error = "The assigned image has invalid dimensions."
		return false
	var entry: Dictionary = slots.get(slot_id, {})
	if not entry.is_empty() and str(entry.get("path", "")) == relative_path:
		entry["status"] = "aligned" if _entry_is_valid_for_dimensions(entry, slot_id, image_width, image_height) else "needs_alignment"
		slots[slot_id] = entry
		return true
	slots[slot_id] = {
		"path": relative_path,
		"feet_anchor": [int(image_width / 2), image_height],
		"scale_milli": _creator_base_scale_milli(),
		"status": "aligned",
	}
	return true


func mark_replaced(slot_id: String, relative_path: String, image_width: int, image_height: int) -> bool:
	if not ensure_slot(slot_id, relative_path, image_width, image_height):
		return false
	var entry: Dictionary = slots[slot_id]
	if not _entry_is_valid_for_dimensions(entry, slot_id, image_width, image_height):
		entry["feet_anchor"] = [int(image_width / 2), image_height]
		entry["scale_milli"] = _creator_base_scale_milli()
	entry["status"] = "aligned"
	slots[slot_id] = entry
	return true


func remove_slot(slot_id: String) -> void:
	slots.erase(slot_id)


func synchronize_slots(slot_manifest: Dictionary) -> Dictionary:
	var found_ids: PackedStringArray = PackedStringArray()
	for slot in _manifest_slots_ordered(slot_manifest):
		if not bool(slot.get("assigned", false)):
			continue
		var slot_id: String = str(slot.get("slot", ""))
		var relative_path: String = str(slot.get("path", "sprites/%s.png" % slot_id))
		if not _valid_relative_path(slot_id, relative_path):
			continue
		var image_path: String = "%s/%s" % [draft_root, relative_path]
		var image: Image = Image.new()
		if not FileAccess.file_exists(image_path) or image.load(image_path) != OK or image.is_empty():
			continue
		if ensure_slot(slot_id, relative_path, image.get_width(), image.get_height()):
			found_ids.append(slot_id)
	for old_slot_id in slots.keys():
		if not found_ids.has(str(old_slot_id)):
			slots.erase(old_slot_id)
	return {"ok": true, "assigned_ids": found_ids, "errors": []}


func get_slot(slot_id: String) -> Dictionary:
	return Dictionary(slots.get(slot_id, {})).duplicate(true)


func save_alignment(slot_id: String, anchor_x: int, anchor_y: int, scale_milli: int) -> Dictionary:
	var entry: Dictionary = slots.get(slot_id, {})
	if entry.is_empty():
		return _failure("CREATOR_ALIGNMENT_MISSING", slot_id, "slot must have imported art")
	if not _valid_scale(scale_milli):
		entry["scale_milli"] = scale_milli
		entry["status"] = "needs_alignment"
		slots[slot_id] = entry
		return _failure(
			"CREATOR_ALIGNMENT_SCALE_INVALID",
			scale_milli,
			"scale_milli must be an integer from %d through %d" % [SCALE_MIN, SCALE_MAX]
		)
	var image_result: Dictionary = load_slot_image(slot_id)
	if not bool(image_result.get("ok", false)):
		return image_result
	var image: Image = image_result["image"]
	if not _anchor_is_valid(anchor_x, anchor_y, image.get_width(), image.get_height()):
		entry["feet_anchor"] = [anchor_x, anchor_y]
		entry["scale_milli"] = scale_milli
		entry["status"] = "needs_alignment"
		slots[slot_id] = entry
		return _failure("CREATOR_ALIGNMENT_ANCHOR_INVALID", "%d,%d" % [anchor_x, anchor_y], "anchor must be within -image size to 2x image size on each axis")
	entry["feet_anchor"] = [anchor_x, anchor_y]
	entry["scale_milli"] = scale_milli
	entry["status"] = "aligned"
	slots[slot_id] = entry
	return {"ok": true, "errors": []}


func load_slot_image(slot_id: String) -> Dictionary:
	if not _is_safe_slot_id(slot_id):
		return _failure("CREATOR_ALIGNMENT_SLOT_INVALID", slot_id, "slot ID must use [a-z0-9_]+")
	var entry: Dictionary = slots.get(slot_id, {})
	var relative_path: String = str(entry.get("path", ""))
	if entry.is_empty() or not _valid_relative_path(slot_id, relative_path):
		return _failure("CREATOR_ALIGNMENT_MISSING", slot_id, "slot must have a draft-owned sprite assignment")
	var image_path: String = "%s/%s" % [draft_root, relative_path]
	if not FileAccess.file_exists(image_path):
		return _failure("CREATOR_ALIGNMENT_IMAGE_MISSING", slot_id, "assigned image must exist in the draft")
	var image: Image = Image.new()
	var load_error: Error = image.load(image_path)
	if load_error != OK or image.is_empty():
		return _failure("CREATOR_ALIGNMENT_IMAGE_INVALID", slot_id, "assigned image must decode before alignment")
	return {"ok": true, "image": image, "width": image.get_width(), "height": image.get_height()}


func get_assigned_slot_ids(slot_manifest: Dictionary) -> PackedStringArray:
	var result: PackedStringArray = PackedStringArray()
	var animations: Dictionary = slot_manifest.get("animations", {})
	for animation_id in ANIMATION_ORDER:
		if not animations.has(animation_id):
			continue
		var value: Variant = animations[animation_id]
		if value is Array:
			_append_assigned_from_array(value, result)
		else:
			var phases: Dictionary = value
			for phase in PHASE_ORDER:
				if phases.has(phase):
					_append_assigned_from_array(Array(phases[phase].get("slots", [])), result)
	return result


func get_manifest_assigned_count(slot_manifest: Dictionary) -> int:
	var count: int = 0
	for slot in _manifest_slots_ordered(slot_manifest):
		if bool(slot.get("assigned", false)):
			count += 1
	return count


func get_aligned_count(slot_manifest: Dictionary) -> int:
	var count: int = 0
	for slot_id in get_assigned_slot_ids(slot_manifest):
		if is_slot_alignment_valid(slot_id):
			count += 1
	return count


func get_missing_alignment_ids(slot_manifest: Dictionary) -> PackedStringArray:
	var missing: PackedStringArray = PackedStringArray()
	for slot in _manifest_slots_ordered(slot_manifest):
		if not bool(slot.get("assigned", false)):
			continue
		var slot_id: String = str(slot.get("slot", ""))
		if not is_slot_alignment_valid(slot_id):
			missing.append(slot_id)
	return missing


func is_slot_alignment_valid(slot_id: String) -> bool:
	var entry: Dictionary = slots.get(slot_id, {})
	if entry.is_empty():
		return false
	var image_result: Dictionary = load_slot_image(slot_id)
	if not bool(image_result.get("ok", false)):
		entry["status"] = "needs_alignment"
		slots[slot_id] = entry
		return false
	var valid: bool = _entry_is_valid_for_dimensions(
		entry,
		slot_id,
		int(image_result["width"]),
		int(image_result["height"])
	)
	entry["status"] = "aligned" if valid else "needs_alignment"
	slots[slot_id] = entry
	return valid


func apply_to_animation(slot_manifest: Dictionary, source_slot_id: String) -> Dictionary:
	var source: Dictionary = slots.get(source_slot_id, {})
	if source.is_empty() or not is_slot_alignment_valid(source_slot_id):
		return _failure("CREATOR_ALIGNMENT_SOURCE_INVALID", source_slot_id, "save the current alignment before applying it")
	source = slots[source_slot_id]
	var group_prefix: String = _group_prefix(source_slot_id)
	var targets: PackedStringArray = PackedStringArray()
	for slot_id in get_assigned_slot_ids(slot_manifest):
		if slot_id != source_slot_id and _group_prefix(slot_id) == group_prefix:
			targets.append(slot_id)
	var validated: Array[Dictionary] = []
	for slot_id in targets:
		var image_result: Dictionary = load_slot_image(slot_id)
		if not bool(image_result.get("ok", false)):
			return image_result
		var image: Image = image_result["image"]
		var anchor: Array = source.get("feet_anchor", [])
		if not _anchor_is_valid(int(anchor[0]), int(anchor[1]), image.get_width(), image.get_height()):
			return _failure("CREATOR_ALIGNMENT_ANCHOR_INVALID", slot_id, "source anchor is outside this sibling image's permitted range")
		validated.append({"slot": slot_id, "width": image.get_width(), "height": image.get_height()})
	for target in validated:
		var entry: Dictionary = slots[target["slot"]]
		entry["feet_anchor"] = source["feet_anchor"].duplicate()
		entry["scale_milli"] = int(source["scale_milli"])
		entry["status"] = "aligned"
	return {"ok": true, "count": validated.size(), "errors": []}


func apply_scale_to_all(slot_manifest: Dictionary, source_slot_id: String) -> Dictionary:
	var source: Dictionary = slots.get(source_slot_id, {})
	if source.is_empty() or not _valid_scale(int(source.get("scale_milli", 0))):
		return _failure("CREATOR_ALIGNMENT_SOURCE_INVALID", source_slot_id, "current scale must be valid")
	var count: int = 0
	for slot_id in get_assigned_slot_ids(slot_manifest):
		var entry: Dictionary = slots.get(slot_id, {})
		if entry.is_empty():
			continue
		entry["scale_milli"] = int(source["scale_milli"])
		entry["status"] = "aligned" if is_slot_alignment_valid(slot_id) else "needs_alignment"
		count += 1
	return {"ok": true, "count": count, "errors": []}


func auto_fit(slot_manifest: Dictionary) -> Dictionary:
	var reference_result: Dictionary = _load_auto_fit_reference()
	if not bool(reference_result.get("ok", false)):
		return reference_result
	var source_slot_id: String = AUTO_FIT_SOURCE_SLOT
	if not slots.has(source_slot_id):
		var assigned_ids: PackedStringArray = get_assigned_slot_ids(slot_manifest)
		if assigned_ids.is_empty():
			return _failure("CREATOR_AUTO_FIT_SOURCE_MISSING", source_slot_id, "Auto Fit needs idle_0 or another assigned sprite")
		source_slot_id = assigned_ids[0]
	var source_result: Dictionary = load_slot_image(source_slot_id)
	if not bool(source_result.get("ok", false)):
		return source_result
	var source_visible_height: int = visible_alpha_height(source_result["image"])
	if source_visible_height <= 0:
		return _failure("CREATOR_AUTO_FIT_IMAGE_TRANSPARENT", source_slot_id, "Auto Fit needs at least one non-transparent pixel")
	var scale_milli: int = calculate_auto_fit_scale(
		float(reference_result["rendered_height"]), source_visible_height
	)
	var validated_ids: PackedStringArray = PackedStringArray()
	for slot in _manifest_slots_ordered(slot_manifest):
		if not bool(slot.get("assigned", false)):
			continue
		var slot_id: String = str(slot.get("slot", ""))
		var entry: Dictionary = slots.get(slot_id, {})
		if entry.is_empty():
			return _failure("CREATOR_ALIGNMENT_MISSING", slot_id, "every assigned slot needs presentation metadata")
		var image_result: Dictionary = load_slot_image(slot_id)
		if not bool(image_result.get("ok", false)):
			return image_result
		if not _entry_anchor_is_valid(entry, int(image_result["width"]), int(image_result["height"])):
			return _failure("CREATOR_ALIGNMENT_ANCHOR_INVALID", slot_id, "Auto Fit preserves only valid feet anchors")
		validated_ids.append(slot_id)
	for slot_id in validated_ids:
		var entry: Dictionary = slots[slot_id]
		entry["scale_milli"] = scale_milli
		entry["status"] = "aligned"
	return {
		"ok": true,
		"count": validated_ids.size(),
		"source_slot": source_slot_id,
		"source_visible_height": source_visible_height,
		"reference_frame": str(reference_result["frame"]),
		"reference_visible_height": int(reference_result["visible_height"]),
		"reference_scale_milli": int(reference_result["scale_milli"]),
		"reference_rendered_height": float(reference_result["rendered_height"]),
		"scale_milli": scale_milli,
		"alpha_bounds_used": true,
		"errors": [],
	}


static func visible_alpha_height(image: Image) -> int:
	if image == null or image.is_empty():
		return 0
	return image.get_used_rect().size.y


static func calculate_auto_fit_scale(reference_rendered_height: float, imported_visible_height: int) -> int:
	if not is_finite(reference_rendered_height) or reference_rendered_height <= 0.0 or imported_visible_height <= 0:
		return SCALE_MIN
	return clampi(int(round(reference_rendered_height * 1000.0 / float(imported_visible_height))), SCALE_MIN, SCALE_MAX)


func _load_auto_fit_reference() -> Dictionary:
	var file: FileAccess = FileAccess.open(AUTO_FIT_REFERENCE_PRESENTATION, FileAccess.READ)
	if file == null:
		return _failure("CREATOR_AUTO_FIT_REFERENCE_MISSING", AUTO_FIT_REFERENCE_PRESENTATION, "built-in Auto Fit reference must be readable")
	var document: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not document is Dictionary:
		return _failure("CREATOR_AUTO_FIT_REFERENCE_INVALID", AUTO_FIT_REFERENCE_PRESENTATION, "built-in Auto Fit reference must be valid JSON")
	var animations: Variant = document.get("animations", {})
	if not animations is Dictionary or not animations.has(AUTO_FIT_REFERENCE_ANIMATION):
		return _failure("CREATOR_AUTO_FIT_REFERENCE_INVALID", AUTO_FIT_REFERENCE_ANIMATION, "built-in Auto Fit reference must contain idle")
	var animation: Variant = animations[AUTO_FIT_REFERENCE_ANIMATION]
	var frames: Variant = animation.get("frames", []) if animation is Dictionary else []
	if not frames is Array or frames.is_empty() or not frames[0] is Dictionary:
		return _failure("CREATOR_AUTO_FIT_REFERENCE_INVALID", AUTO_FIT_REFERENCE_ANIMATION, "built-in Auto Fit reference must contain idle_0")
	var frame: Dictionary = frames[0]
	var sprite_path: String = str(frame.get("sprite", ""))
	var scale_milli: int = int(frame.get("scale_milli", 0))
	if sprite_path.is_empty() or scale_milli <= 0:
		return _failure("CREATOR_AUTO_FIT_REFERENCE_INVALID", frame, "built-in idle_0 must contain sprite and scale_milli")
	var image_path: String = AUTO_FIT_REFERENCE_PRESENTATION.get_base_dir().path_join(sprite_path)
	var texture: Texture2D = ResourceLoader.load(image_path, "Texture2D") as Texture2D
	var image: Image = texture.get_image() if texture != null else null
	if image == null or image.is_empty():
		return _failure("CREATOR_AUTO_FIT_REFERENCE_INVALID", image_path, "built-in idle_0 image must decode")
	var visible_height: int = visible_alpha_height(image)
	if visible_height <= 0:
		return _failure("CREATOR_AUTO_FIT_REFERENCE_TRANSPARENT", image_path, "built-in idle_0 must contain visible pixels")
	return {
		"ok": true,
		"frame": "%s/%s_0" % [AUTO_FIT_REFERENCE_PRESENTATION, AUTO_FIT_REFERENCE_ANIMATION],
		"visible_height": visible_height,
		"scale_milli": scale_milli,
		"rendered_height": float(visible_height * scale_milli) / 1000.0,
		"errors": [],
	}


func save() -> Dictionary:
	if not _is_safe_id(fighter_id) or draft_root != "user://characters/%s" % fighter_id:
		return _failure("CREATOR_ALIGNMENT_DESTINATION_INVALID", draft_root, "presentation draft must remain inside user://characters/<fighter_id>")
	var output: Dictionary = {"version": 1, "slots": slots.duplicate(true)}
	var file: FileAccess = FileAccess.open(draft_root + "/" + FILE_NAME, FileAccess.WRITE)
	if file == null:
		return _failure("CREATOR_ALIGNMENT_WRITE_FAILED", FileAccess.get_open_error(), "presentation draft must be writable under user://")
	file.store_string(JSON.stringify(output, "\t", false) + "\n")
	file.flush()
	var error: Error = file.get_error()
	file.close()
	if error != OK:
		return _failure("CREATOR_ALIGNMENT_WRITE_FAILED", error, "presentation draft must be fully written")
	return {"ok": true, "path": draft_root + "/" + FILE_NAME, "errors": []}


func _append_assigned_from_array(values: Array, output: PackedStringArray) -> void:
	for value in values:
		if value is Dictionary and bool(value.get("assigned", false)):
			var slot_id: String = str(value.get("slot", ""))
			var entry: Dictionary = slots.get(slot_id, {})
			if not entry.is_empty() and bool(load_slot_image(slot_id).get("ok", false)):
				output.append(slot_id)


func _manifest_slots_ordered(slot_manifest: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var animations: Dictionary = slot_manifest.get("animations", {})
	for animation_id in ANIMATION_ORDER:
		if not animations.has(animation_id):
			continue
		var animation_value: Variant = animations[animation_id]
		if animation_value is Array:
			_append_slot_dicts(animation_value, result)
		else:
			var phases: Dictionary = animation_value
			for phase in PHASE_ORDER:
				if phases.has(phase):
					_append_slot_dicts(Array(phases[phase].get("slots", [])), result)
	return result


func _append_slot_dicts(values: Array, output: Array[Dictionary]) -> void:
	for value in values:
		if value is Dictionary:
			output.append(value)


func _group_prefix(slot_id: String) -> String:
	var last_separator: int = slot_id.rfind("_")
	return slot_id.substr(0, last_separator) if last_separator > 0 else slot_id


func _valid_relative_path(slot_id: String, path: String) -> bool:
	return path == "sprites/%s.png" % slot_id and not path.contains("..") and not path.contains("\\") and not path.begins_with("/")


func _is_safe_id(value: String) -> bool:
	return _is_safe_slot_id(value)


func _is_safe_slot_id(value: String) -> bool:
	if value.is_empty():
		return false
	for index in value.length():
		var code: int = value.unicode_at(index)
		if not ((code >= 97 and code <= 122) or (code >= 48 and code <= 57) or code == 95):
			return false
	return true


func _creator_base_scale_milli() -> int:
	var preferred: Dictionary = slots.get(AUTO_FIT_SOURCE_SLOT, {})
	var preferred_scale: Variant = preferred.get("scale_milli", 0)
	if _is_exact_integer(preferred_scale) and _valid_scale(int(preferred_scale)):
		return int(preferred_scale)
	for entry_value in slots.values():
		if not entry_value is Dictionary:
			continue
		var scale_value: Variant = entry_value.get("scale_milli", 0)
		if _is_exact_integer(scale_value) and _valid_scale(int(scale_value)):
			return int(scale_value)
	return 1000


func _entry_is_valid_for_dimensions(entry: Dictionary, slot_id: String, width: int, height: int) -> bool:
	if str(entry.get("path", "")) != "sprites/%s.png" % slot_id:
		return false
	var scale_value: Variant = entry.get("scale_milli", 0)
	if not _is_exact_integer(scale_value) or not _valid_scale(int(scale_value)):
		return false
	return _entry_anchor_is_valid(entry, width, height)


func _entry_anchor_is_valid(entry: Dictionary, width: int, height: int) -> bool:
	var anchor_value: Variant = entry.get("feet_anchor", [])
	if not anchor_value is Array or anchor_value.size() != 2:
		return false
	if not _is_exact_integer(anchor_value[0]) or not _is_exact_integer(anchor_value[1]):
		return false
	return _anchor_is_valid(int(anchor_value[0]), int(anchor_value[1]), width, height)


func _valid_scale(value: int) -> bool:
	return value >= SCALE_MIN and value <= SCALE_MAX


func _is_exact_integer(value: Variant) -> bool:
	if typeof(value) == TYPE_INT:
		return true
	if typeof(value) == TYPE_FLOAT:
		var number: float = float(value)
		return is_finite(number) and floorf(number) == number
	return false


func _anchor_is_valid(x: int, y: int, width: int, height: int) -> bool:
	return x >= -width and x <= width * 2 and y >= -height and y <= height * 2


func _failure(code: String, value: Variant, rule: String) -> Dictionary:
	return {"ok": false, "errors": [{"code": code, "file": "user://characters/%s/%s" % [fighter_id, FILE_NAME], "field": "presentation_draft", "invalid_value": value, "expected_rule": rule}]}
