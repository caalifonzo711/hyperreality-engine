extends RefCounted
class_name RollbackFighterCreatorDraft


const LoaderScript = preload("res://games/rollback_fighter/scripts/config/CharacterDefinitionLoader.gd")
const PresentationResolverScript = preload("res://games/rollback_fighter/scripts/config/FighterPresentationManifestResolver.gd")
const REGISTRY_PATH := "res://games/rollback_fighter/config/builtin_fighters.json"
const MOVE_KEYS := ["startup", "active", "recovery", "damage", "hitstun", "knockback_x", "hitstop", "contact_cooldown", "guard_damage"]
const JAB_HITBOX := {
	"config_version": 1,
	"move_id": "jab",
	"boxes": [{"frame": 1, "type": "hit", "x": 30, "y": -40, "w": 40, "h": 20}],
}
const HEAVY_HITBOX := {
	"config_version": 1,
	"move_id": "heavy",
	"legacy_horizontal_range": {"reach": 56, "defender_half_extent": 8},
}
const PRESET_IDS := ["platform_fighter", "footsies", "anime_fighter", "custom"]
const PRESET_LABELS := ["Platform Fighter", "Footsies", "Anime Fighter", "Custom"]

# Every endpoint is a curated, validated integer profile. The feel control only
# interpolates between these endpoints; it never edits the active match data.
const PRESET_PROFILES := {
	"platform_fighter": {
		"fast": {"movement": [380, 18000, 21000, 35000], "guard": [300, 1, 1], "dodge": [16, 2, 6, 22], "light": [2, 2, 4, 7, 9, 220, 3, 6, 30], "heavy": [6, 2, 14, 14, 12, 600, 7, 12, 90]},
		"committed": {"movement": [320, 14400, 19200, 28800], "guard": [300, 1, 1], "dodge": [16, 2, 6, 26], "light": [2, 2, 5, 7, 9, 220, 3, 6, 30], "heavy": [7, 2, 16, 15, 13, 650, 8, 14, 100]},
	},
	"footsies": {
		"fast": {"movement": [330, 14000, 23000, 28000], "guard": [320, 1, 1], "dodge": [16, 2, 6, 24], "light": [2, 2, 4, 7, 9, 220, 3, 6, 30], "heavy": [6, 2, 14, 14, 12, 600, 7, 12, 90]},
		"committed": {"movement": [280, 11000, 19000, 24000], "guard": [320, 1, 1], "dodge": [18, 3, 7, 30], "light": [3, 2, 5, 7, 10, 210, 3, 7, 35], "heavy": [8, 2, 16, 17, 14, 650, 8, 14, 105]},
	},
	"anime_fighter": {
		"fast": {"movement": [360, 17000, 21000, 32000], "guard": [280, 1, 1], "dodge": [16, 2, 6, 22], "light": [2, 2, 4, 6, 8, 210, 3, 6, 28], "heavy": [7, 2, 14, 15, 12, 620, 7, 12, 95]},
		"committed": {"movement": [310, 13000, 18000, 26000], "guard": [280, 1, 1], "dodge": [18, 3, 7, 28], "light": [3, 2, 6, 7, 10, 220, 4, 7, 32], "heavy": [9, 2, 18, 18, 15, 700, 9, 15, 110]},
	},
	"custom": {
		"fast": {"movement": [340, 15000, 20000, 29000], "guard": [300, 1, 1], "dodge": [16, 2, 6, 24], "light": [2, 2, 4, 7, 9, 220, 3, 6, 30], "heavy": [6, 2, 14, 14, 12, 600, 7, 12, 90]},
		"committed": {"movement": [300, 12500, 18000, 25000], "guard": [300, 1, 1], "dodge": [18, 3, 7, 30], "light": [3, 2, 5, 7, 10, 220, 3, 7, 32], "heavy": [8, 2, 16, 16, 14, 650, 8, 14, 100]},
	},
}

var fighter_name: String = ""
var fighter_id: String = ""
var visual_description: String = ""
var project_id: String = ""
var presentation_style_id: String = "platform_fighter"
var presentation_policy_reference: String = ""
var presentation_manifest_id: String = "platform_fighter_v1"
var presentation_manifest_version: int = 1
var preset_id: String = "platform_fighter"
var feel_percent: int = 0
var character_document: Dictionary = {}
var move_documents: Dictionary = {}
var hitbox_documents: Dictionary = {}
var slot_manifest: Dictionary = {}
var last_errors: Array[Dictionary] = []
var draft_created: bool = false
var assigned_art_slots: int = 0
var aligned_art_slots: int = 0

var _loader: RollbackFighterCharacterDefinitionLoader


func _init() -> void:
	_loader = LoaderScript.new()
	_apply_profile()


func set_identity(display_name: String, requested_id: String) -> void:
	fighter_name = display_name.strip_edges()
	fighter_id = requested_id.strip_edges()
	_apply_identity()


func set_visual_description(value: String) -> void:
	visual_description = value.strip_edges().left(2000)


func set_project_context(requested_project_id: String) -> bool:
	if requested_project_id.is_empty():
		project_id = ""
		return true
	if not _is_safe_id(requested_project_id):
		return false
	project_id = requested_project_id
	return true


func set_presentation_policy(style_id: String, policy_reference: String = "") -> bool:
	var resolved: Dictionary = PresentationResolverScript.resolve(style_id, policy_reference)
	if not bool(resolved.get("ok", false)):
		last_errors = resolved.get("errors", [])
		return false
	var manifest: RollbackFighterPresentationManifest = resolved["manifest"]
	presentation_style_id = manifest.style_preset
	presentation_policy_reference = policy_reference
	presentation_manifest_id = manifest.manifest_id
	presentation_manifest_version = manifest.manifest_version
	_rebuild_slot_manifest()
	return true


static func id_from_display_name(display_name: String) -> String:
	var regex: RegEx = RegEx.new()
	regex.compile("[^a-z0-9]+")
	var result: String = regex.sub(display_name.to_lower(), "_", true)
	while result.begins_with("_"):
		result = result.trim_prefix("_")
	while result.ends_with("_"):
		result = result.trim_suffix("_")
	return result


func set_preset(requested_preset_id: String) -> void:
	if PRESET_PROFILES.has(requested_preset_id):
		preset_id = requested_preset_id
	_apply_profile()


func set_feel(value: int) -> void:
	feel_percent = clampi(value, 0, 100)
	_apply_profile()


func get_preset_labels() -> PackedStringArray:
	return PackedStringArray(PRESET_LABELS)


func get_preset_ids() -> PackedStringArray:
	return PackedStringArray(PRESET_IDS)


func get_character_value(section: String, key: String) -> int:
	var group: Dictionary = character_document.get(section, {})
	return int(group.get(key, 0))


func get_move_value(slot: String, key: String) -> int:
	var move: Dictionary = move_documents.get(slot, {})
	return int(move.get(key, 0))


func refresh_after_tuning() -> void:
	# Presentation frame metadata follows the authoritative move timings, while
	# the assigned art itself remains untouched.
	_rebuild_slot_manifest()


func get_art_slot_total() -> int:
	var total: int = 0
	for animation_value in slot_manifest.get("animations", {}).values():
		if animation_value is Array:
			total += animation_value.size()
		elif animation_value is Dictionary:
			for phase_value in animation_value.values():
				if phase_value is Dictionary:
					total += Array(phase_value.get("slots", [])).size()
	return total


func get_required_art_slot_total() -> int:
	return _count_slots(slot_manifest, true, false)


func get_optional_art_slot_total() -> int:
	return _count_slots(slot_manifest, false, false) - get_required_art_slot_total()


func get_completed_required_art_slots() -> int:
	return _count_slots(slot_manifest, true, true)


func get_completed_optional_art_slots() -> int:
	return _count_slots(slot_manifest, false, true) - get_completed_required_art_slots()


func get_missing_required_art_slots() -> PackedStringArray:
	var missing: PackedStringArray = PackedStringArray()
	_collect_missing_slots(slot_manifest, missing)
	return missing


func set_alignment_progress(assigned: int, aligned: int) -> void:
	assigned_art_slots = maxi(assigned, 0)
	aligned_art_slots = clampi(aligned, 0, assigned_art_slots)


func get_creator_status() -> String:
	return str(_build_creator_manifest().get("status", "draft"))


func apply_slot_assignment(slot_id: String, assignment: Dictionary) -> bool:
	return _set_slot_assignment(slot_manifest, slot_id, assignment)


func save_art_manifests() -> Dictionary:
	var user_root: String = get_user_draft_path()
	if not draft_created:
		return {"ok": false, "errors": [{"code": "CREATOR_DRAFT_NOT_CREATED", "file": "<creator-draft>", "field": "draft", "invalid_value": fighter_id, "expected_rule": "create the draft before saving art assignments"}]}
	var slot_error: Error = _write_json(user_root + "/slot_manifest.json", slot_manifest)
	if slot_error != OK:
		return {"ok": false, "errors": [_make_error("CREATOR_WRITE_FAILED", user_root + "/slot_manifest.json", slot_error, "slot manifest must be writable")]}
	var creator_error: Error = _write_json(user_root + "/creator_manifest.json", _build_creator_manifest())
	if creator_error != OK:
		return {"ok": false, "errors": [_make_error("CREATOR_WRITE_FAILED", user_root + "/creator_manifest.json", creator_error, "creator manifest must be writable")]}
	return {"ok": true, "errors": []}


func get_user_draft_path() -> String:
	return "user://characters/%s" % fighter_id


func validate_identity() -> Array[Dictionary]:
	var errors: Array[Dictionary] = []
	if fighter_name.is_empty():
		_add_local_error(errors, "CREATOR_NAME_REQUIRED", "display_name", fighter_name, "name must not be empty")
	if not _is_safe_id(fighter_id):
		_add_local_error(errors, "CREATOR_ID_INVALID", "id", fighter_id, "must match [a-z0-9_]+ and contain no path separators")
		return errors
	var registry_errors: Array[Dictionary] = []
	var registry: Dictionary = _loader._load_json(REGISTRY_PATH, registry_errors)
	var fighters_value: Variant = registry.get("fighters")
	if fighters_value is Dictionary and Dictionary(fighters_value).has(fighter_id):
		_add_local_error(errors, "CREATOR_ID_DUPLICATE", "id", fighter_id, "must not duplicate a registered built-in fighter")
	var user_root: String = get_user_draft_path()
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(user_root)):
		_add_local_error(errors, "CREATOR_ID_DUPLICATE", "id", fighter_id, "a user://characters folder already exists for this ID")
	if not registry_errors.is_empty():
		errors.append_array(registry_errors)
	return errors


func validate() -> Array[Dictionary]:
	last_errors = validate_identity()
	if not last_errors.is_empty():
		return last_errors.duplicate(true)
	return validate_documents()


func validate_documents() -> Array[Dictionary]:
	last_errors = _loader.validate_creator_draft(
		character_document,
		{"light": move_documents.get("light", {}), "heavy": move_documents.get("heavy", {})},
		hitbox_documents
	)
	return last_errors.duplicate(true)


func save_config_documents() -> Dictionary:
	if not draft_created:
		return {"ok": false, "errors": [{"code": "CREATOR_DRAFT_NOT_CREATED", "file": "<creator-draft>", "field": "draft", "invalid_value": fighter_id, "expected_rule": "create the draft before saving configuration documents"}]}
	var validation_errors: Array[Dictionary] = validate_documents()
	if not validation_errors.is_empty():
		return {"ok": false, "errors": validation_errors}
	var root: String = get_user_draft_path()
	var documents: Dictionary = {
		"character.json": character_document,
		"moves/jab.json": move_documents.get("light", {}),
		"moves/heavy.json": move_documents.get("heavy", {}),
		"hitboxes/jab.json": hitbox_documents.get("light", {}),
		"hitboxes/heavy.json": hitbox_documents.get("heavy", {}),
	}
	for relative_path in ["character.json", "moves/jab.json", "moves/heavy.json", "hitboxes/jab.json", "hitboxes/heavy.json"]:
		var error: Error = _write_json(root + "/" + relative_path, documents[relative_path])
		if error != OK:
			return {"ok": false, "errors": [_make_error("CREATOR_WRITE_FAILED", root + "/" + relative_path, error, "configuration file must be writable under user://")]}
	return {"ok": true, "errors": []}


func create_user_draft() -> Dictionary:
	if draft_created:
		var config_persisted: Dictionary = save_config_documents()
		if not bool(config_persisted.get("ok", false)):
			return config_persisted
		var persisted: Dictionary = save_art_manifests()
		persisted["path"] = get_user_draft_path()
		return persisted
	var errors: Array[Dictionary] = validate()
	if not errors.is_empty():
		return {"ok": false, "errors": errors}
	var user_root: String = get_user_draft_path()
	var absolute_root: String = ProjectSettings.globalize_path(user_root)
	if DirAccess.dir_exists_absolute(absolute_root):
		last_errors = []
		_add_local_error(last_errors, "CREATOR_ID_DUPLICATE", "id", fighter_id, "draft folder already exists; choose a new ID")
		return {"ok": false, "errors": last_errors.duplicate(true)}
	for folder: String in [user_root, user_root + "/moves", user_root + "/hitboxes", user_root + "/sprites"]:
		var mkdir_error: Error = DirAccess.make_dir_recursive_absolute(
			ProjectSettings.globalize_path(folder)
		)
		if mkdir_error != OK:
			last_errors = []
			_add_local_error(last_errors, "CREATOR_DIRECTORY_FAILED", folder, mkdir_error, "directory must be writable under user://")
			return {"ok": false, "errors": last_errors.duplicate(true)}
	var files: Dictionary = {
		"character.json": character_document,
		"moves/jab.json": move_documents["light"],
		"moves/heavy.json": move_documents["heavy"],
		"hitboxes/jab.json": hitbox_documents["light"],
		"hitboxes/heavy.json": hitbox_documents["heavy"],
	}
	for relative_path in files:
		var file_path: String = "%s/%s" % [user_root, str(relative_path)]
		var file: FileAccess = FileAccess.open(file_path, FileAccess.WRITE)
		if file == null:
			last_errors = []
			_add_local_error(last_errors, "CREATOR_WRITE_FAILED", file_path, FileAccess.get_open_error(), "file must be writable under user://")
			return {"ok": false, "errors": last_errors.duplicate(true)}
		file.store_string(JSON.stringify(files[relative_path], "\t", false) + "\n")
		file.flush()
		file.close()
	draft_created = true
	var manifest_result: Dictionary = save_art_manifests()
	if not bool(manifest_result.get("ok", false)):
		return manifest_result
	last_errors.clear()
	return {"ok": true, "path": user_root, "errors": []}


func get_review_summary() -> Dictionary:
	return {
		"name": fighter_name,
		"id": fighter_id,
		"preset": _preset_label(preset_id),
		"hp": get_character_value("health", "max_hp"),
		"move_speed": get_character_value("movement", "move_speed"),
		"jab_timing": _timing_text("light"),
		"jab_damage": get_move_value("light", "damage"),
		"heavy_timing": _timing_text("heavy"),
		"heavy_damage": get_move_value("heavy", "damage"),
		"art_slots": get_art_slot_total(),
		"required_art_slots": get_required_art_slot_total(),
		"completed_required_art_slots": get_completed_required_art_slots(),
		"optional_art_slots": get_optional_art_slot_total(),
		"completed_optional_art_slots": get_completed_optional_art_slots(),
		"missing_required_art_slots": get_missing_required_art_slots(),
		"assigned_art_slots": assigned_art_slots,
		"aligned_art_slots": aligned_art_slots,
		"missing_alignment_slots": _missing_alignment_slots(),
	}


func _apply_profile() -> void:
	var profile: Dictionary = PRESET_PROFILES[preset_id]
	var fast: Dictionary = profile["fast"]
	var committed: Dictionary = profile["committed"]
	var movement_values: Array = _interpolate_array(fast["movement"], committed["movement"])
	var guard_values: Array = _interpolate_array(fast["guard"], committed["guard"])
	var dodge_values: Array = _interpolate_array(fast["dodge"], committed["dodge"])
	var light_values: Array = _interpolate_array(fast["light"], committed["light"])
	var heavy_values: Array = _interpolate_array(fast["heavy"], committed["heavy"])
	character_document = {
		"config_version": 1,
		"identity": {"id": fighter_id, "display_name": fighter_name},
		"health": {"max_hp": 100},
		"movement": {
			"move_speed": movement_values[0],
			"acceleration": movement_values[1],
			"braking": movement_values[2],
			"reversal_acceleration": movement_values[3],
			"knockback_friction": 900,
			"max_knockback_speed": 1100,
		},
		"hurtbox": {"x": -10, "y": -48, "width": 20, "height": 48},
		"guard": {
			"max_units": guard_values[0],
			"held_drain_per_frame": guard_values[1],
			"regen_per_frame": guard_values[2],
			"break_refill_units": int(int(guard_values[0]) / 2),
			"break_stun_frames": 24,
		},
		"dodge": {
			"total_frames": dodge_values[0],
			"invuln_start": dodge_values[1],
			"invuln_end": dodge_values[2],
			"cooldown_frames": dodge_values[3],
		},
		"moves": {"light": "moves/jab.json", "heavy": "moves/heavy.json"},
	}
	move_documents = {
		"light": _make_move_document("jab", "Jab", light_values, "hitboxes/jab.json"),
		"heavy": _make_move_document("heavy", "Heavy", heavy_values, "hitboxes/heavy.json"),
	}
	hitbox_documents = {
		"light": JAB_HITBOX.duplicate(true),
		"heavy": HEAVY_HITBOX.duplicate(true),
	}
	_apply_identity()
	_rebuild_slot_manifest()


func _apply_identity() -> void:
	if character_document.is_empty():
		return
	var identity: Dictionary = character_document.get("identity", {})
	identity["id"] = fighter_id
	identity["display_name"] = fighter_name
	character_document["identity"] = identity


func _make_move_document(move_id: String, display_name: String, values: Array, hitbox_path: String) -> Dictionary:
	var result: Dictionary = {
		"config_version": 1,
		"id": move_id,
		"display_name": display_name,
		"hitbox_profile": hitbox_path,
		"animation_id": move_id,
	}
	for index in MOVE_KEYS.size():
		result[MOVE_KEYS[index]] = values[index]
	return result


func _interpolate_array(start_values: Array, end_values: Array) -> Array:
	var output: Array = []
	for index in start_values.size():
		output.append(_interpolate_integer(int(start_values[index]), int(end_values[index]), feel_percent))
	return output


func _interpolate_integer(start_value: int, end_value: int, percent: int) -> int:
	var numerator: int = (end_value - start_value) * percent
	var rounded_delta: int
	if numerator >= 0:
		rounded_delta = int((numerator + 50) / 100)
	else:
		rounded_delta = -int((-numerator + 50) / 100)
	return start_value + rounded_delta


func _rebuild_slot_manifest() -> void:
	var resolved: Dictionary = PresentationResolverScript.resolve(presentation_style_id, presentation_policy_reference)
	if not bool(resolved.get("ok", false)):
		last_errors = resolved.get("errors", [])
		return
	var manifest: RollbackFighterPresentationManifest = resolved["manifest"]
	presentation_manifest_id = manifest.manifest_id
	presentation_manifest_version = manifest.manifest_version
	slot_manifest = manifest.to_slot_manifest(move_documents, slot_manifest)


func _build_creator_manifest() -> Dictionary:
	var completed: int = get_completed_required_art_slots()
	var required: int = get_required_art_slot_total()
	var status: String = "art_incomplete"
	if completed == required:
		if assigned_art_slots <= 0:
			status = "art_complete"
		elif aligned_art_slots < assigned_art_slots:
			status = "alignment_incomplete"
		else:
			status = "alignment_complete"
	return {
		"manifest_version": 1,
		"draft_kind": "fighter_creator_draft",
		"fighter_id": fighter_id,
		"project_id": project_id,
		"presentation_style_id": presentation_style_id,
		"presentation_policy_reference": presentation_policy_reference,
		"presentation_manifest_id": presentation_manifest_id,
		"presentation_manifest_version": presentation_manifest_version,
		"display_name": fighter_name,
		"visual_description": visual_description,
		"selected_preset": preset_id,
		"feel_percent": feel_percent,
		"playable": false,
		"status": status,
		"blocked_reason": "presentation setup and C3/C4 validation are still required",
		"required_art_slots": required,
		"completed_required_art_slots": completed,
		"missing_required_art_slots": get_missing_required_art_slots(),
		"assigned_art_slots": assigned_art_slots,
		"aligned_art_slots": aligned_art_slots,
		"missing_alignment_slots": _missing_alignment_slots(),
	}


func _missing_alignment_slots() -> PackedStringArray:
	var missing: PackedStringArray = PackedStringArray()
	if assigned_art_slots > aligned_art_slots:
		missing.append("%d assigned sprite(s) need alignment" % (assigned_art_slots - aligned_art_slots))
	return missing


func _count_slots(value: Variant, required_only: bool, assigned_only: bool) -> int:
	var count: int = 0
	if value is Dictionary:
		var item: Dictionary = value
		if item.has("slot"):
			if (not required_only or bool(item.get("required", false))) and (not assigned_only or bool(item.get("assigned", false))):
				return 1
		for child in item.values():
			count += _count_slots(child, required_only, assigned_only)
	elif value is Array:
		for child in value:
			count += _count_slots(child, required_only, assigned_only)
	return count


func _collect_missing_slots(value: Variant, output: PackedStringArray) -> void:
	if value is Dictionary:
		var item: Dictionary = value
		if item.has("slot") and bool(item.get("required", false)) and not bool(item.get("assigned", false)):
			output.append(str(item.get("slot", "")))
		for child in item.values():
			_collect_missing_slots(child, output)
	elif value is Array:
		for child in value:
			_collect_missing_slots(child, output)


func _set_slot_assignment(value: Variant, slot_id: String, assignment: Dictionary) -> bool:
	if value is Dictionary:
		var item: Dictionary = value
		if str(item.get("slot", "")) == slot_id:
			for key in ["assigned", "path", "display_filename", "width", "height"]:
				item.erase(key)
			for key in assignment:
				item[key] = assignment[key]
			return true
		for child in item.values():
			if _set_slot_assignment(child, slot_id, assignment):
				return true
	elif value is Array:
		for child in value:
			if _set_slot_assignment(child, slot_id, assignment):
				return true
	return false


func _write_json(path: String, document: Dictionary) -> Error:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(document, "\t", false) + "\n")
	file.flush()
	var error: Error = file.get_error()
	file.close()
	return error


func _make_error(code: String, path: String, value: Variant, rule: String) -> Dictionary:
	return {"code": code, "file": path, "field": "file", "invalid_value": value, "expected_rule": rule}


func _timing_text(slot: String) -> String:
	var move: Dictionary = move_documents.get(slot, {})
	return "%d / %d / %d" % [int(move.get("startup", 0)), int(move.get("active", 0)), int(move.get("recovery", 0))]


func _preset_label(id: String) -> String:
	var index: int = PRESET_IDS.find(id)
	return PRESET_LABELS[index] if index >= 0 else "Custom"


func _is_safe_id(value: String) -> bool:
	if value.is_empty():
		return false
	for index in value.length():
		var code: int = value.unicode_at(index)
		if not ((code >= 97 and code <= 122) or (code >= 48 and code <= 57) or code == 95):
			return false
	return true


func _add_local_error(errors: Array[Dictionary], code: String, field: String, value: Variant, rule: String) -> void:
	errors.append({
		"code": code,
		"file": "<creator-draft>",
		"field": field,
		"invalid_value": value,
		"expected_rule": rule,
	})
