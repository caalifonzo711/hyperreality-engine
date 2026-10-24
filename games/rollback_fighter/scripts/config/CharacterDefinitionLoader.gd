extends RefCounted
class_name RollbackFighterCharacterDefinitionLoader


const CharacterDefinitionScript = preload(
	"res://games/rollback_fighter/scripts/config/CharacterDefinition.gd"
)
const MoveDefinitionScript = preload(
	"res://games/rollback_fighter/scripts/config/MoveDefinition.gd"
)
const GameRulesDefinitionScript = preload(
	"res://games/rollback_fighter/scripts/config/GameRulesDefinition.gd"
)
const PresentationDefinitionScript = preload(
	"res://games/rollback_fighter/scripts/config/PresentationDefinition.gd"
)

const SUPPORTED_VERSION := 1
const MIN_INT := -2147483648
const MAX_INT := 2147483647
const MOVE_SLOTS := ["light", "heavy"]
const REQUIRED_PRESENTATION_STATES := ["idle", "block", "dodge", "hurt", "dead"]


func load_game_rules(path: String) -> Dictionary:
	var errors: Array[Dictionary] = []
	var raw := _load_json(path, errors)
	if raw.is_empty():
		return _failure(errors)
	var normalized := _normalize_game_rules(raw, path, errors)
	if not errors.is_empty():
		return _failure(errors)
	return {
		"ok": true,
		"definition": GameRulesDefinitionScript.new(normalized),
		"errors": [],
	}


func load_builtin_fighter(registry_path: String, fighter_id: String) -> Dictionary:
	var errors: Array[Dictionary] = []
	var registry := _load_json(registry_path, errors)
	if registry.is_empty():
		return _failure(errors)
	_reject_unknown_keys(
		registry, ["config_version", "fighters"], registry_path, "", errors
	)
	var version := _required_int(registry, "config_version", registry_path, errors)
	if version != SUPPORTED_VERSION:
		_add_error(errors, "CFG_VERSION_UNSUPPORTED", registry_path, "config_version", version, "must equal 1")
	var fighters_value: Variant = registry.get("fighters")
	if not fighters_value is Dictionary:
		_add_error(errors, "CFG_REGISTRY_FIGHTERS_INVALID", registry_path, "fighters", fighters_value, "must be an object")
		return _failure(errors)
	var fighters: Dictionary = fighters_value
	if not fighters.has(fighter_id):
		_add_error(errors, "CFG_FIGHTER_NOT_REGISTERED", registry_path, "fighters.%s" % fighter_id, "<missing>", "must name an explicit built-in fighter root")
		return _failure(errors)
	var root_value: Variant = fighters[fighter_id]
	if not root_value is String:
		_add_error(errors, "CFG_REGISTRY_ROOT_INVALID", registry_path, "fighters.%s" % fighter_id, root_value, "must be a res:// string")
		return _failure(errors)
	var root := _normalize_builtin_root(str(root_value), registry_path, errors)
	if not errors.is_empty():
		return _failure(errors)
	return load_character(root, fighter_id)


func load_character(root: String, expected_id: String = "") -> Dictionary:
	var errors: Array[Dictionary] = []
	var normalized_root := _normalize_builtin_root(root, "<character-root>", errors)
	if not errors.is_empty():
		return _failure(errors)

	var character_path := normalized_root + "/character.json"
	var presentation_path := normalized_root + "/presentation.json"
	var character_raw := _load_json(character_path, errors)
	if character_raw.is_empty():
		return _failure(errors)

	var character_data := _normalize_character(character_raw, character_path, errors)
	if not expected_id.is_empty() and str(character_data.get("id", "")) != expected_id:
		_add_error(errors, "CFG_FIGHTER_ID_MISMATCH", character_path, "identity.id", character_data.get("id", ""), "must match registry id %s" % expected_id)

	var move_refs: Dictionary = character_data.get("move_refs", {})
	var move_slots: Dictionary = {}
	var seen_move_ids: Dictionary = {}
	for slot in MOVE_SLOTS:
		if not move_refs.has(slot):
			continue
		var move_path := _resolve_reference(normalized_root, str(move_refs[slot]), character_path, "moves.%s" % slot, errors)
		if move_path.is_empty():
			continue
		var move_raw := _load_json(move_path, errors)
		if move_raw.is_empty():
			continue
		var move_data := _normalize_move(move_raw, move_path, errors)
		var move_id := str(move_data.get("id", ""))
		if seen_move_ids.has(move_id):
			_add_error(errors, "CFG_MOVE_ID_DUPLICATE", move_path, "id", move_id, "move IDs referenced by slots must be unique")
		else:
			seen_move_ids[move_id] = true
		var hitbox_ref := str(move_data.get("hitbox_profile", ""))
		var hitbox_path := _resolve_reference(normalized_root, hitbox_ref, move_path, "hitbox_profile", errors)
		var profile: Dictionary = {}
		if not hitbox_path.is_empty():
			var hitbox_raw := _load_json(hitbox_path, errors)
			if not hitbox_raw.is_empty():
				profile = _normalize_hitbox_profile(hitbox_raw, hitbox_path, move_data, errors)
		if not move_data.is_empty() and not profile.is_empty():
			move_slots[slot] = MoveDefinitionScript.new(move_data, profile)

	var presentation_raw := _load_json(presentation_path, errors)
	var presentation_data: Dictionary = {}
	if not presentation_raw.is_empty():
		presentation_data = _normalize_presentation(
			presentation_raw,
			presentation_path,
			normalized_root,
			move_slots,
			errors
		)
		if str(presentation_data.get("fighter_id", "")) != str(character_data.get("id", "")):
			_add_error(errors, "CFG_PRESENTATION_FIGHTER_ID_MISMATCH", presentation_path, "fighter_id", presentation_data.get("fighter_id", ""), "must match character identity.id")

	for slot in MOVE_SLOTS:
		if not move_slots.has(slot):
			_add_error(errors, "CFG_MOVE_REQUIRED_MISSING", character_path, "moves.%s" % slot, move_refs.get(slot, "<missing>"), "required move must resolve and validate")

	if not errors.is_empty():
		return _failure(errors)

	character_data.erase("move_refs")
	var presentation = PresentationDefinitionScript.new(presentation_data)
	var definition = CharacterDefinitionScript.new(character_data, move_slots, presentation)
	return {"ok": true, "definition": definition, "errors": []}


func format_error(error: Dictionary) -> String:
	return "[%s] file=%s field=%s value=%s rule=%s" % [
		str(error.get("code", "CFG_UNKNOWN")),
		str(error.get("file", "<unknown>")),
		str(error.get("field", "<unknown>")),
		str(error.get("invalid_value", "<unknown>")),
		str(error.get("expected_rule", "<unknown>")),
	]


func _normalize_character(raw: Dictionary, file: String, errors: Array[Dictionary]) -> Dictionary:
	_reject_unknown_keys(raw, ["config_version", "identity", "health", "movement", "hurtbox", "guard", "dodge", "moves"], file, "", errors)
	var version := _version(raw, file, errors)
	var identity := _required_object(raw, "identity", file, errors)
	var health := _required_object(raw, "health", file, errors)
	var movement := _required_object(raw, "movement", file, errors)
	var hurtbox := _required_object(raw, "hurtbox", file, errors)
	var guard := _required_object(raw, "guard", file, errors)
	var dodge := _required_object(raw, "dodge", file, errors)
	var moves := _required_object(raw, "moves", file, errors)
	_reject_unknown_keys(identity, ["id", "display_name"], file, "identity", errors)
	_reject_unknown_keys(health, ["max_hp"], file, "health", errors)
	_reject_unknown_keys(movement, ["move_speed", "acceleration", "braking", "reversal_acceleration", "knockback_friction", "max_knockback_speed"], file, "movement", errors)
	_reject_unknown_keys(hurtbox, ["x", "y", "width", "height"], file, "hurtbox", errors)
	_reject_unknown_keys(guard, ["max_units", "held_drain_per_frame", "regen_per_frame", "break_refill_units", "break_stun_frames"], file, "guard", errors)
	_reject_unknown_keys(dodge, ["total_frames", "invuln_start", "invuln_end", "cooldown_frames"], file, "dodge", errors)
	_reject_unknown_keys(moves, MOVE_SLOTS, file, "moves", errors)

	var fighter_id := _required_string(identity, "id", file, "identity.id", errors)
	if not _is_valid_id(fighter_id):
		_add_error(errors, "CFG_FIGHTER_ID_INVALID", file, "identity.id", fighter_id, "must match [a-z0-9_]+")
	var display_name := _required_string(identity, "display_name", file, "identity.display_name", errors)
	var max_hp := _nonnegative_int(health, "max_hp", file, "health.max_hp", errors)
	if max_hp <= 0:
		_add_error(errors, "CFG_HP_INVALID", file, "health.max_hp", max_hp, "must be greater than 0")

	var normalized := {
		"config_version": version,
		"id": fighter_id,
		"display_name": display_name,
		"max_hp": max_hp,
		"move_speed": _nonnegative_int(movement, "move_speed", file, "movement.move_speed", errors),
		"acceleration": _nonnegative_int(movement, "acceleration", file, "movement.acceleration", errors),
		"braking": _nonnegative_int(movement, "braking", file, "movement.braking", errors),
		"reversal_acceleration": _nonnegative_int(movement, "reversal_acceleration", file, "movement.reversal_acceleration", errors),
		"knockback_friction": _nonnegative_int(movement, "knockback_friction", file, "movement.knockback_friction", errors),
		"max_knockback_speed": _nonnegative_int(movement, "max_knockback_speed", file, "movement.max_knockback_speed", errors),
		"hurtbox_x": _required_int(hurtbox, "x", file, errors, "hurtbox.x"),
		"hurtbox_y": _required_int(hurtbox, "y", file, errors, "hurtbox.y"),
		"hurtbox_width": _required_int(hurtbox, "width", file, errors, "hurtbox.width"),
		"hurtbox_height": _required_int(hurtbox, "height", file, errors, "hurtbox.height"),
		"guard_max_units": _nonnegative_int(guard, "max_units", file, "guard.max_units", errors),
		"guard_held_drain_per_frame": _nonnegative_int(guard, "held_drain_per_frame", file, "guard.held_drain_per_frame", errors),
		"guard_regen_per_frame": _nonnegative_int(guard, "regen_per_frame", file, "guard.regen_per_frame", errors),
		"guard_break_refill_units": _nonnegative_int(guard, "break_refill_units", file, "guard.break_refill_units", errors),
		"guard_break_stun_frames": _nonnegative_int(guard, "break_stun_frames", file, "guard.break_stun_frames", errors),
		"dodge_total_frames": _required_int(dodge, "total_frames", file, errors, "dodge.total_frames"),
		"dodge_invuln_start": _required_int(dodge, "invuln_start", file, errors, "dodge.invuln_start"),
		"dodge_invuln_end": _required_int(dodge, "invuln_end", file, errors, "dodge.invuln_end"),
		"dodge_cooldown_frames": _nonnegative_int(dodge, "cooldown_frames", file, "dodge.cooldown_frames", errors),
		"move_refs": {},
	}
	if int(normalized["hurtbox_width"]) <= 0 or int(normalized["hurtbox_height"]) <= 0:
		_add_error(errors, "CFG_HURTBOX_SIZE_INVALID", file, "hurtbox", "%sx%s" % [normalized["hurtbox_width"], normalized["hurtbox_height"]], "width and height must be greater than 0")
	if int(normalized["guard_break_refill_units"]) > int(normalized["guard_max_units"]):
		_add_error(errors, "CFG_GUARD_REFILL_INVALID", file, "guard.break_refill_units", normalized["guard_break_refill_units"], "must be less than or equal to guard.max_units")
	var total := int(normalized["dodge_total_frames"])
	var inv_start := int(normalized["dodge_invuln_start"])
	var inv_end := int(normalized["dodge_invuln_end"])
	if total <= 0:
		_add_error(errors, "CFG_DODGE_TOTAL_INVALID", file, "dodge.total_frames", total, "must be greater than 0")
	if inv_start < 0 or inv_end < inv_start or inv_end >= total:
		_add_error(errors, "CFG_DODGE_WINDOW_INVALID", file, "dodge.invuln_start..invuln_end", "%d..%d" % [inv_start, inv_end], "must satisfy 0 <= start <= end < total_frames")
	for slot in MOVE_SLOTS:
		var ref := _required_string(moves, slot, file, "moves.%s" % slot, errors)
		normalized["move_refs"][slot] = ref
	return normalized


func _normalize_move(raw: Dictionary, file: String, errors: Array[Dictionary]) -> Dictionary:
	var allowed := ["config_version", "id", "display_name", "startup", "active", "recovery", "damage", "hitstun", "knockback_x", "hitstop", "contact_cooldown", "guard_damage", "hitbox_profile", "animation_id"]
	_reject_unknown_keys(raw, allowed, file, "", errors)
	var data := {
		"config_version": _version(raw, file, errors),
		"id": _required_string(raw, "id", file, "id", errors),
		"display_name": _required_string(raw, "display_name", file, "display_name", errors),
		"startup": _nonnegative_int(raw, "startup", file, "startup", errors),
		"active": _required_int(raw, "active", file, errors),
		"recovery": _nonnegative_int(raw, "recovery", file, "recovery", errors),
		"damage": _nonnegative_int(raw, "damage", file, "damage", errors),
		"hitstun": _nonnegative_int(raw, "hitstun", file, "hitstun", errors),
		"knockback_x": _nonnegative_int(raw, "knockback_x", file, "knockback_x", errors),
		"hitstop": _nonnegative_int(raw, "hitstop", file, "hitstop", errors),
		"contact_cooldown": _nonnegative_int(raw, "contact_cooldown", file, "contact_cooldown", errors),
		"guard_damage": _nonnegative_int(raw, "guard_damage", file, "guard_damage", errors),
		"hitbox_profile": _required_string(raw, "hitbox_profile", file, "hitbox_profile", errors),
		"animation_id": _required_string(raw, "animation_id", file, "animation_id", errors),
	}
	if not _is_valid_id(str(data["id"])):
		_add_error(errors, "CFG_MOVE_ID_INVALID", file, "id", data["id"], "must match [a-z0-9_]+")
	if int(data["active"]) <= 0:
		_add_error(errors, "CFG_MOVE_ACTIVE_INVALID", file, "active", data["active"], "must be greater than 0")
	return data


func _normalize_hitbox_profile(raw: Dictionary, file: String, move: Dictionary, errors: Array[Dictionary]) -> Dictionary:
	var version := _version(raw, file, errors)
	var move_id := _required_string(raw, "move_id", file, "move_id", errors)
	if move_id != str(move.get("id", "")):
		_add_error(errors, "CFG_HITBOX_MOVE_ID_MISMATCH", file, "move_id", move_id, "must match referencing move id %s" % str(move.get("id", "")))

	if raw.has("legacy_horizontal_range"):
		_reject_unknown_keys(raw, ["config_version", "move_id", "legacy_horizontal_range"], file, "", errors)
		var legacy := _required_object(raw, "legacy_horizontal_range", file, errors)
		_reject_unknown_keys(legacy, ["reach", "defender_half_extent"], file, "legacy_horizontal_range", errors)
		return {
			"config_version": version,
			"move_id": move_id,
			"kind": "legacy_horizontal_range",
			"reach": _nonnegative_int(legacy, "reach", file, "legacy_horizontal_range.reach", errors),
			"defender_half_extent": _nonnegative_int(legacy, "defender_half_extent", file, "legacy_horizontal_range.defender_half_extent", errors),
		}

	var frames_by_index: Dictionary = {}
	if raw.has("boxes"):
		_reject_unknown_keys(raw, ["config_version", "move_id", "boxes"], file, "", errors)
		var boxes_value: Variant = raw["boxes"]
		if not boxes_value is Array:
			_add_error(errors, "CFG_HITBOX_BOXES_INVALID", file, "boxes", boxes_value, "must be an array")
		else:
			for index in boxes_value.size():
				var box_value: Variant = boxes_value[index]
				if not box_value is Dictionary:
					_add_error(errors, "CFG_HITBOX_BOX_INVALID", file, "boxes[%d]" % index, box_value, "must be an object")
					continue
				var box: Dictionary = box_value
				_reject_unknown_keys(box, ["frame", "type", "x", "y", "w", "h"], file, "boxes[%d]" % index, errors)
				if str(box.get("type", "hit")) != "hit":
					_add_error(errors, "CFG_HITBOX_TYPE_INVALID", file, "boxes[%d].type" % index, box.get("type"), "version 1 move profiles contain hit boxes only")
				var frame := _required_int(box, "frame", file, errors, "boxes[%d].frame" % index)
				var normalized_box := _normalize_box(box, "x", "y", "w", "h", file, "boxes[%d]" % index, errors)
				_append_box(frames_by_index, frame, normalized_box)
	elif raw.has("frames"):
		_reject_unknown_keys(raw, ["config_version", "move_id", "frames"], file, "", errors)
		var frames_value: Variant = raw["frames"]
		if not frames_value is Array:
			_add_error(errors, "CFG_HITBOX_FRAMES_INVALID", file, "frames", frames_value, "must be an array")
		else:
			for index in frames_value.size():
				var frame_value: Variant = frames_value[index]
				if not frame_value is Dictionary:
					_add_error(errors, "CFG_HITBOX_FRAME_INVALID", file, "frames[%d]" % index, frame_value, "must be an object")
					continue
				var frame_data: Dictionary = frame_value
				_reject_unknown_keys(frame_data, ["active_frame", "hitboxes"], file, "frames[%d]" % index, errors)
				var active_frame := _required_int(frame_data, "active_frame", file, errors, "frames[%d].active_frame" % index)
				if frames_by_index.has(active_frame):
					_add_error(errors, "CFG_HITBOX_FRAME_DUPLICATE", file, "frames[%d].active_frame" % index, active_frame, "active frame declarations must be unique")
				var hitboxes_value: Variant = frame_data.get("hitboxes")
				if not hitboxes_value is Array:
					_add_error(errors, "CFG_HITBOX_BOXES_INVALID", file, "frames[%d].hitboxes" % index, hitboxes_value, "must be an array")
					continue
				frames_by_index[active_frame] = []
				for box_index in hitboxes_value.size():
					var box_value: Variant = hitboxes_value[box_index]
					if not box_value is Dictionary:
						_add_error(errors, "CFG_HITBOX_BOX_INVALID", file, "frames[%d].hitboxes[%d]" % [index, box_index], box_value, "must be an object")
						continue
					var box: Dictionary = box_value
					_reject_unknown_keys(box, ["x", "y", "width", "height"], file, "frames[%d].hitboxes[%d]" % [index, box_index], errors)
					frames_by_index[active_frame].append(_normalize_box(box, "x", "y", "width", "height", file, "frames[%d].hitboxes[%d]" % [index, box_index], errors))
	else:
		_add_error(errors, "CFG_HITBOX_FORMAT_INVALID", file, "frames", "<missing>", "must provide frames, legacy boxes, or legacy_horizontal_range")

	var frame_indices: Array = frames_by_index.keys()
	frame_indices.sort()
	var normalized_frames: Array = []
	for frame_variant in frame_indices:
		var frame := int(frame_variant)
		if frame < 0 or frame >= int(move.get("active", 0)):
			_add_error(errors, "CFG_HITBOX_FRAME_OUT_OF_RANGE", file, "active_frame", frame, "must satisfy 0 <= active_frame < move.active")
		normalized_frames.append({"active_frame": frame, "hitboxes": Array(frames_by_index[frame]).duplicate(true)})
	return {"config_version": version, "move_id": move_id, "kind": "boxes", "frames": normalized_frames}


func _normalize_box(raw: Dictionary, x_key: String, y_key: String, width_key: String, height_key: String, file: String, prefix: String, errors: Array[Dictionary]) -> Dictionary:
	var box := {
		"x": _required_int(raw, x_key, file, errors, "%s.%s" % [prefix, x_key]),
		"y": _required_int(raw, y_key, file, errors, "%s.%s" % [prefix, y_key]),
		"width": _required_int(raw, width_key, file, errors, "%s.%s" % [prefix, width_key]),
		"height": _required_int(raw, height_key, file, errors, "%s.%s" % [prefix, height_key]),
	}
	if int(box["width"]) <= 0 or int(box["height"]) <= 0:
		_add_error(errors, "CFG_HITBOX_SIZE_INVALID", file, prefix, "%sx%s" % [box["width"], box["height"]], "width and height must be greater than 0")
	return box


func _normalize_game_rules(raw: Dictionary, file: String, errors: Array[Dictionary]) -> Dictionary:
	var allowed := ["config_version", "simulation_hz", "light_input_buffer_frames", "heavy_input_buffer_frames", "combo_hitstun_percent", "combo_knockback_percent", "blocked_chip_percent", "blocked_hit_stun_frames", "dodge_contact_hitstop", "spawn_positions", "fallback_policy", "world_contact_bounds"]
	_reject_unknown_keys(raw, allowed, file, "", errors)
	var simulation_hz := _required_int(raw, "simulation_hz", file, errors)
	if simulation_hz != 60:
		_add_error(errors, "CFG_SIMULATION_HZ_INVALID", file, "simulation_hz", simulation_hz, "version 1 requires exactly 60")
	var hitstun_scales := _positive_int_array(raw, "combo_hitstun_percent", file, errors)
	var knockback_scales := _positive_int_array(raw, "combo_knockback_percent", file, errors)
	if hitstun_scales.is_empty() or hitstun_scales.size() != knockback_scales.size():
		_add_error(errors, "CFG_COMBO_ARRAYS_INVALID", file, "combo_*_percent", "%d/%d" % [hitstun_scales.size(), knockback_scales.size()], "arrays must be nonempty and have equal length")
	var chip := _required_int(raw, "blocked_chip_percent", file, errors)
	if chip < 0 or chip > 100:
		_add_error(errors, "CFG_BLOCK_CHIP_INVALID", file, "blocked_chip_percent", chip, "must be between 0 and 100")
	var fallback := _required_string(raw, "fallback_policy", file, "fallback_policy", errors)
	if fallback != "reject":
		_add_error(errors, "CFG_FALLBACK_POLICY_INVALID", file, "fallback_policy", fallback, "version 1 supports only reject")
	var spawns := _required_object(raw, "spawn_positions", file, errors)
	_reject_unknown_keys(spawns, ["p1", "p2"], file, "spawn_positions", errors)
	var normalized_spawns: Dictionary = {}
	for player in ["p1", "p2"]:
		var spawn := _required_object(spawns, player, file, errors)
		_reject_unknown_keys(spawn, ["x", "y"], file, "spawn_positions.%s" % player, errors)
		normalized_spawns[player] = {
			"x": _required_int(spawn, "x", file, errors, "spawn_positions.%s.x" % player),
			"y": _required_int(spawn, "y", file, errors, "spawn_positions.%s.y" % player),
		}
	var bounds := _required_object(raw, "world_contact_bounds", file, errors)
	_reject_unknown_keys(bounds, ["enabled", "left", "right", "top", "bottom"], file, "world_contact_bounds", errors)
	var enabled_value: Variant = bounds.get("enabled")
	if not enabled_value is bool:
		_add_error(errors, "CFG_BOOLEAN_INVALID", file, "world_contact_bounds.enabled", enabled_value, "must be a boolean")
	var normalized_bounds := {
		"enabled": bool(enabled_value) if enabled_value is bool else false,
		"left": _required_int(bounds, "left", file, errors, "world_contact_bounds.left"),
		"right": _required_int(bounds, "right", file, errors, "world_contact_bounds.right"),
		"top": _required_int(bounds, "top", file, errors, "world_contact_bounds.top"),
		"bottom": _required_int(bounds, "bottom", file, errors, "world_contact_bounds.bottom"),
	}
	return {
		"config_version": _version(raw, file, errors),
		"simulation_hz": simulation_hz,
		"light_input_buffer_frames": _nonnegative_int(raw, "light_input_buffer_frames", file, "light_input_buffer_frames", errors),
		"heavy_input_buffer_frames": _nonnegative_int(raw, "heavy_input_buffer_frames", file, "heavy_input_buffer_frames", errors),
		"combo_hitstun_percent": hitstun_scales,
		"combo_knockback_percent": knockback_scales,
		"blocked_chip_percent": chip,
		"blocked_hit_stun_frames": _nonnegative_int(raw, "blocked_hit_stun_frames", file, "blocked_hit_stun_frames", errors),
		"dodge_contact_hitstop": _nonnegative_int(raw, "dodge_contact_hitstop", file, "dodge_contact_hitstop", errors),
		"spawn_positions": normalized_spawns,
		"fallback_policy": fallback,
		"world_contact_bounds": normalized_bounds,
	}


func _normalize_presentation(raw: Dictionary, file: String, root: String, move_slots: Dictionary, errors: Array[Dictionary]) -> Dictionary:
	_reject_unknown_keys(raw, ["config_version", "fighter_id", "source_art_faces", "animations", "state_to_animation", "attack_phase_to_frames"], file, "", errors)
	var version := _version(raw, file, errors)
	var fighter_id := _required_string(raw, "fighter_id", file, "fighter_id", errors)
	var facing := _required_string(raw, "source_art_faces", file, "source_art_faces", errors)
	if facing != "left" and facing != "right":
		_add_error(errors, "CFG_PRESENTATION_FACING_INVALID", file, "source_art_faces", facing, "must be left or right")
	var animations_raw := _required_object(raw, "animations", file, errors)
	var animations: Dictionary = {}
	var animation_ids: Array = animations_raw.keys()
	animation_ids.sort()
	for animation_id_variant in animation_ids:
		var animation_id: String = str(animation_id_variant)
		if not _is_valid_id(animation_id):
			_add_error(errors, "CFG_ANIMATION_ID_INVALID", file, "animations.%s" % animation_id, animation_id, "must match [a-z0-9_]+")
		var animation_value: Variant = animations_raw[animation_id]
		if not animation_value is Dictionary:
			_add_error(errors, "CFG_ANIMATION_INVALID", file, "animations.%s" % animation_id, animation_value, "must be an object")
			continue
		var animation: Dictionary = animation_value
		_reject_unknown_keys(animation, ["playback", "fps_milli", "frames"], file, "animations.%s" % animation_id, errors)
		var playback := _required_string(animation, "playback", file, "animations.%s.playback" % animation_id, errors)
		if playback not in ["loop_fps", "hold", "state_stretched", "attack_phase_map"]:
			_add_error(errors, "CFG_PLAYBACK_INVALID", file, "animations.%s.playback" % animation_id, playback, "must be loop_fps, hold, state_stretched, or attack_phase_map")
		var fps := _required_int(animation, "fps_milli", file, errors, "animations.%s.fps_milli" % animation_id)
		if fps <= 0:
			_add_error(errors, "CFG_PRESENTATION_FPS_INVALID", file, "animations.%s.fps_milli" % animation_id, fps, "must be greater than 0")
		var frames_value: Variant = animation.get("frames")
		var frames: Array = []
		if not frames_value is Array or frames_value.is_empty():
			_add_error(errors, "CFG_PRESENTATION_FRAMES_MISSING", file, "animations.%s.frames" % animation_id, frames_value, "must be a nonempty array")
		else:
			for frame_index in frames_value.size():
				var frame_value: Variant = frames_value[frame_index]
				if not frame_value is Dictionary:
					_add_error(errors, "CFG_PRESENTATION_FRAME_INVALID", file, "animations.%s.frames[%d]" % [animation_id, frame_index], frame_value, "must be an object")
					continue
				var frame: Dictionary = frame_value
				var prefix := "animations.%s.frames[%d]" % [animation_id, frame_index]
				_reject_unknown_keys(frame, ["sprite", "feet_anchor", "scale_milli"], file, prefix, errors)
				var sprite_ref := _required_string(frame, "sprite", file, "%s.sprite" % prefix, errors)
				var sprite_path := _resolve_reference(root, sprite_ref, file, "%s.sprite" % prefix, errors)
				if not sprite_path.is_empty():
					if not ResourceLoader.exists(sprite_path):
						_add_error(errors, "CFG_SPRITE_MISSING", file, "%s.sprite" % prefix, sprite_ref, "resource must exist and load as Texture2D")
					else:
						var resource := ResourceLoader.load(sprite_path)
						if not resource is Texture2D:
							_add_error(errors, "CFG_SPRITE_TYPE_INVALID", file, "%s.sprite" % prefix, sprite_ref, "resource must load as Texture2D")
				var feet := _required_object(frame, "feet_anchor", file, errors, "%s.feet_anchor" % prefix)
				_reject_unknown_keys(feet, ["x", "y"], file, "%s.feet_anchor" % prefix, errors)
				var scale := _required_int(frame, "scale_milli", file, errors, "%s.scale_milli" % prefix)
				if scale <= 0:
					_add_error(errors, "CFG_PRESENTATION_SCALE_INVALID", file, "%s.scale_milli" % prefix, scale, "must be greater than 0")
				frames.append({
					"sprite": sprite_path,
					"feet_anchor": {
						"x": _required_int(feet, "x", file, errors, "%s.feet_anchor.x" % prefix),
						"y": _required_int(feet, "y", file, errors, "%s.feet_anchor.y" % prefix),
					},
					"scale_milli": scale,
				})
		animations[animation_id] = {"playback": playback, "fps_milli": fps, "frames": frames}

	var states_raw := _required_object(raw, "state_to_animation", file, errors)
	_reject_unknown_keys(states_raw, REQUIRED_PRESENTATION_STATES, file, "state_to_animation", errors)
	var state_map: Dictionary = {}
	for state in REQUIRED_PRESENTATION_STATES:
		var animation_id: String = _required_string(
			states_raw,
			state,
			file,
			"state_to_animation.%s" % state,
			errors
		)
		state_map[state] = animation_id
		if not animations.has(animation_id):
			_add_error(errors, "CFG_PRESENTATION_ANIMATION_MISSING", file, "state_to_animation.%s" % state, animation_id, "must reference a defined animation")

	var phase_maps_raw := _required_object(raw, "attack_phase_to_frames", file, errors)
	var phase_maps: Dictionary = {}
	for slot in MOVE_SLOTS:
		if not move_slots.has(slot):
			continue
		var move: RollbackFighterMoveDefinition = move_slots[slot]
		var animation_id: String = move.get_animation_id()
		if not animations.has(animation_id):
			_add_error(errors, "CFG_MOVE_ANIMATION_MISSING", file, "animations.%s" % animation_id, animation_id, "move animation_id must reference a defined animation")
			continue
		if not phase_maps_raw.has(animation_id) or not phase_maps_raw[animation_id] is Dictionary:
			_add_error(errors, "CFG_PHASE_MAP_MISSING", file, "attack_phase_to_frames.%s" % animation_id, phase_maps_raw.get(animation_id, "<missing>"), "attack animation requires a phase map")
			continue
		var phase_raw: Dictionary = phase_maps_raw[animation_id]
		_reject_unknown_keys(phase_raw, ["startup", "active", "recovery"], file, "attack_phase_to_frames.%s" % animation_id, errors)
		var normalized_phase: Dictionary = {}
		var animation_data: Dictionary = animations[animation_id]
		var animation_frames: Array = animation_data["frames"]
		var frame_count := animation_frames.size()
		for phase in ["startup", "active", "recovery"]:
			var indices := _nonnegative_int_array(phase_raw, phase, file, "attack_phase_to_frames.%s.%s" % [animation_id, phase], errors)
			if indices.is_empty():
				_add_error(errors, "CFG_PHASE_FRAMES_MISSING", file, "attack_phase_to_frames.%s.%s" % [animation_id, phase], indices, "must contain at least one frame index")
			for frame_index in indices:
				if int(frame_index) >= frame_count:
					_add_error(errors, "CFG_PHASE_FRAME_INVALID", file, "attack_phase_to_frames.%s.%s" % [animation_id, phase], frame_index, "must reference an existing animation frame")
			normalized_phase[phase] = indices
		phase_maps[animation_id] = normalized_phase

	return {
		"config_version": version,
		"fighter_id": fighter_id,
		"source_art_faces": facing,
		"animations": animations,
		"state_to_animation": state_map,
		"attack_phase_to_frames": phase_maps,
	}


func _load_json(path: String, errors: Array[Dictionary]) -> Dictionary:
	if not FileAccess.file_exists(path):
		_add_error(errors, "CFG_FILE_MISSING", path, "<file>", path, "file must exist in packaged project resources")
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_add_error(errors, "CFG_FILE_OPEN_FAILED", path, "<file>", FileAccess.get_open_error(), "file must be readable")
		return {}
	var parser := JSON.new()
	var parse_error := parser.parse(file.get_as_text())
	if parse_error != OK:
		_add_error(errors, "CFG_JSON_INVALID", path, "line_%d" % parser.get_error_line(), parser.get_error_message(), "must be valid JSON")
		return {}
	if not parser.data is Dictionary:
		_add_error(errors, "CFG_ROOT_INVALID", path, "<root>", parser.data, "JSON root must be an object")
		return {}
	return Dictionary(parser.data)


func _normalize_builtin_root(root: String, file: String, errors: Array[Dictionary]) -> String:
	var root_tail := root.trim_prefix("res://")
	if (
		not root.begins_with("res://")
		or root.contains("\\")
		or root.contains("..")
		or root_tail.contains(":")
		or root_tail.contains("//")
		or root_tail.is_empty()
	):
		_add_error(errors, "CFG_BUILTIN_ROOT_INVALID", file, "character_root", root, "must be a normalized res:// directory without backslashes or ..")
		return ""
	var normalized := root.trim_suffix("/")
	return normalized


func _resolve_reference(root: String, reference: String, file: String, field: String, errors: Array[Dictionary]) -> String:
	var invalid := (
		reference.is_empty()
		or reference.contains("\\")
		or reference.contains("//")
		or reference.begins_with("/")
		or reference.ends_with("/")
		or reference.contains(":")
	)
	var parts := reference.split("/", false)
	for part in parts:
		if part == ".." or part == "." or part.is_empty():
			invalid = true
	if invalid:
		_add_error(errors, "CFG_RESOURCE_REFERENCE_INVALID", file, field, reference, "must be a nonempty character-root-relative path using forward slashes with no scheme, drive, leading slash, dot segment, or root escape")
		return ""
	var resolved := (root + "/" + reference).simplify_path()
	if not resolved.begins_with(root + "/"):
		_add_error(errors, "CFG_RESOURCE_ROOT_ESCAPE", file, field, reference, "resolved path must remain inside the character root")
		return ""
	return resolved


func _version(raw: Dictionary, file: String, errors: Array[Dictionary]) -> int:
	var version := _required_int(raw, "config_version", file, errors)
	if version != SUPPORTED_VERSION:
		_add_error(errors, "CFG_VERSION_UNSUPPORTED", file, "config_version", version, "must equal 1")
	return version


func _required_int(raw: Dictionary, key: String, file: String, errors: Array[Dictionary], field: String = "") -> int:
	var full_field := field if not field.is_empty() else key
	if not raw.has(key):
		_add_error(errors, "CFG_FIELD_MISSING", file, full_field, "<missing>", "required authoritative integer")
		return 0
	var value: Variant = raw[key]
	if value is bool or (not value is int and not value is float):
		_add_error(errors, "CFG_NUMBER_TYPE_INVALID", file, full_field, value, "must be a numeric JSON value that is exactly integral")
		return 0
	var float_value := float(value)
	if is_nan(float_value) or is_inf(float_value):
		_add_error(errors, "CFG_NUMBER_NONFINITE", file, full_field, value, "must be finite")
		return 0
	if float_value != floor(float_value):
		_add_error(errors, "CFG_NUMBER_FRACTIONAL", file, full_field, value, "must be exactly integral")
		return 0
	if float_value < MIN_INT or float_value > MAX_INT:
		_add_error(errors, "CFG_NUMBER_OUT_OF_RANGE", file, full_field, value, "must fit signed 32-bit range")
		return 0
	return int(float_value)


func _nonnegative_int(raw: Dictionary, key: String, file: String, field: String, errors: Array[Dictionary]) -> int:
	var value := _required_int(raw, key, file, errors, field)
	if value < 0:
		_add_error(errors, "CFG_NUMBER_NEGATIVE", file, field, value, "must be greater than or equal to 0")
	return value


func _required_string(raw: Dictionary, key: String, file: String, field: String, errors: Array[Dictionary]) -> String:
	if not raw.has(key):
		_add_error(errors, "CFG_FIELD_MISSING", file, field, "<missing>", "required string")
		return ""
	var value: Variant = raw[key]
	if not value is String or str(value).is_empty():
		_add_error(errors, "CFG_STRING_INVALID", file, field, value, "must be a nonempty string")
		return ""
	return str(value)


func _required_object(raw: Dictionary, key: String, file: String, errors: Array[Dictionary], field: String = "") -> Dictionary:
	var full_field := field if not field.is_empty() else key
	var value: Variant = raw.get(key)
	if not value is Dictionary:
		_add_error(errors, "CFG_OBJECT_INVALID", file, full_field, value if raw.has(key) else "<missing>", "must be an object")
		return {}
	return value


func _positive_int_array(raw: Dictionary, key: String, file: String, errors: Array[Dictionary]) -> Array:
	var values := _nonnegative_int_array(raw, key, file, key, errors)
	for index in values.size():
		if int(values[index]) <= 0:
			_add_error(errors, "CFG_PERCENT_INVALID", file, "%s[%d]" % [key, index], values[index], "must be greater than 0")
	return values


func _nonnegative_int_array(raw: Dictionary, key: String, file: String, field: String, errors: Array[Dictionary]) -> Array:
	var value: Variant = raw.get(key)
	if not value is Array:
		_add_error(errors, "CFG_ARRAY_INVALID", file, field, value if raw.has(key) else "<missing>", "must be an array")
		return []
	var result: Array = []
	for index in value.size():
		var wrapper := {"value": value[index]}
		result.append(_nonnegative_int(wrapper, "value", file, "%s[%d]" % [field, index], errors))
	return result


func _reject_unknown_keys(raw: Dictionary, allowed: Array, file: String, prefix: String, errors: Array[Dictionary]) -> void:
	var keys: Array = raw.keys()
	keys.sort()
	for key_variant in keys:
		var key := str(key_variant)
		if key not in allowed:
			var field := key if prefix.is_empty() else "%s.%s" % [prefix, key]
			_add_error(errors, "CFG_FIELD_UNKNOWN", file, field, raw[key_variant], "field is not supported by config version 1")


func _append_box(frames: Dictionary, frame: int, box: Dictionary) -> void:
	if not frames.has(frame):
		frames[frame] = []
	frames[frame].append(box)


func _is_valid_id(value: String) -> bool:
	if value.is_empty():
		return false
	for index in value.length():
		var code := value.unicode_at(index)
		var is_lower := code >= 97 and code <= 122
		var is_digit := code >= 48 and code <= 57
		if not is_lower and not is_digit and code != 95:
			return false
	return true


func _add_error(errors: Array[Dictionary], code: String, file: String, field: String, invalid_value: Variant, expected_rule: String) -> void:
	errors.append({
		"code": code,
		"file": file,
		"field": field,
		"invalid_value": str(invalid_value),
		"expected_rule": expected_rule,
	})


func _failure(errors: Array[Dictionary]) -> Dictionary:
	return {"ok": false, "definition": null, "errors": errors.duplicate(true)}
