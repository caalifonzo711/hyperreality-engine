extends RefCounted
class_name RollbackFighterCanonicalConfigWriter


const MAGIC := "HRF-AUTH-V1"
const MATCH_MAGIC := "HRF-MATCH-AUTH-V1"
const MOVE_SLOTS := ["light", "heavy"]
const MOVE_INT_FIELDS := [
	"startup",
	"active",
	"recovery",
	"damage",
	"hitstun",
	"knockback_x",
	"hitstop",
	"contact_cooldown",
	"guard_damage",
]

var _bytes := PackedByteArray()


func character_bytes(
	rules: RollbackFighterGameRulesDefinition,
	character: RollbackFighterCharacterDefinition
) -> PackedByteArray:
	_bytes = PackedByteArray()
	_write_string(MAGIC)
	_write_rules(rules.get_authoritative_data())
	_write_character(character)
	return _bytes.duplicate()


func match_bytes(
	rules: RollbackFighterGameRulesDefinition,
	p1: RollbackFighterCharacterDefinition,
	p2: RollbackFighterCharacterDefinition
) -> PackedByteArray:
	# Preserve the established canonical stream when both slots use identical
	# authoritative fighter definitions. Distinct definitions are serialized
	# explicitly in player-slot order.
	var p1_bytes: PackedByteArray = character_bytes(rules, p1)
	var p2_bytes: PackedByteArray = character_bytes(rules, p2)
	if p1_bytes == p2_bytes:
		return p1_bytes

	_bytes = PackedByteArray()
	_write_string(MATCH_MAGIC)
	_write_rules(rules.get_authoritative_data())
	_write_u32(2)
	_write_string("p1")
	_write_character(p1)
	_write_string("p2")
	_write_character(p2)
	return _bytes.duplicate()


func sha256_hex(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	var start_error := context.start(HashingContext.HASH_SHA256)
	if start_error != OK:
		return ""
	context.update(bytes)
	return context.finish().hex_encode()


func normalized_dump(
	rules: RollbackFighterGameRulesDefinition,
	character: RollbackFighterCharacterDefinition
) -> String:
	var output := PackedStringArray()
	var rule_data := rules.get_authoritative_data()
	var character_data := character.get_authoritative_data()
	output.append("rules.config_version=%d" % int(rule_data["config_version"]))
	output.append("rules.simulation_hz=%d" % int(rule_data["simulation_hz"]))
	output.append("rules.input_buffers=%d,%d" % [
		int(rule_data["light_input_buffer_frames"]),
		int(rule_data["heavy_input_buffer_frames"]),
	])
	output.append("rules.combo_hitstun=%s" % _join_ints(rule_data["combo_hitstun_percent"]))
	output.append("rules.combo_knockback=%s" % _join_ints(rule_data["combo_knockback_percent"]))
	output.append("rules.block=%d,%d dodge_hitstop=%d" % [
		int(rule_data["blocked_chip_percent"]),
		int(rule_data["blocked_hit_stun_frames"]),
		int(rule_data["dodge_contact_hitstop"]),
	])
	output.append("fighter.config_version=%d" % int(character_data["config_version"]))
	output.append("fighter.id=%s" % str(character_data["id"]))
	output.append("fighter.max_hp=%d" % int(character_data["max_hp"]))
	output.append("fighter.movement=%d,%d,%d,%d,%d,%d" % [
		int(character_data["move_speed"]),
		int(character_data["acceleration"]),
		int(character_data["braking"]),
		int(character_data["reversal_acceleration"]),
		int(character_data["knockback_friction"]),
		int(character_data["max_knockback_speed"]),
	])
	output.append("fighter.hurtbox=%d,%d,%d,%d" % [
		int(character_data["hurtbox_x"]),
		int(character_data["hurtbox_y"]),
		int(character_data["hurtbox_width"]),
		int(character_data["hurtbox_height"]),
	])
	output.append("fighter.guard=%d,%d,%d,%d,%d" % [
		int(character_data["guard_max_units"]),
		int(character_data["guard_held_drain_per_frame"]),
		int(character_data["guard_regen_per_frame"]),
		int(character_data["guard_break_refill_units"]),
		int(character_data["guard_break_stun_frames"]),
	])
	output.append("fighter.dodge=%d,%d,%d,%d" % [
		int(character_data["dodge_total_frames"]),
		int(character_data["dodge_invuln_start"]),
		int(character_data["dodge_invuln_end"]),
		int(character_data["dodge_cooldown_frames"]),
	])
	for slot in MOVE_SLOTS:
		var move := character.get_move_for_slot(slot)
		var move_data := move.get_authoritative_data()
		output.append("move.%s.id=%s" % [slot, move.get_id()])
		output.append("move.%s.values=%d,%d,%d,%d,%d,%d,%d,%d,%d" % [
			slot,
			int(move_data["startup"]), int(move_data["active"]),
			int(move_data["recovery"]), int(move_data["damage"]),
			int(move_data["hitstun"]), int(move_data["knockback_x"]),
			int(move_data["hitstop"]), int(move_data["contact_cooldown"]),
			int(move_data["guard_damage"]),
		])
		output.append("move.%s.hitboxes=%s" % [slot, _profile_dump(move.get_hitbox_profile())])
	return "\n".join(output)


func _write_rules(data: Dictionary) -> void:
	_write_i64(int(data["config_version"]))
	_write_i64(int(data["simulation_hz"]))
	_write_i64(int(data["light_input_buffer_frames"]))
	_write_i64(int(data["heavy_input_buffer_frames"]))
	_write_int_array(data["combo_hitstun_percent"])
	_write_int_array(data["combo_knockback_percent"])
	_write_i64(int(data["blocked_chip_percent"]))
	_write_i64(int(data["blocked_hit_stun_frames"]))
	_write_i64(int(data["dodge_contact_hitstop"]))
	var spawns: Dictionary = data["spawn_positions"]
	for player in ["p1", "p2"]:
		var spawn: Dictionary = spawns[player]
		_write_i64(int(spawn["x"]))
		_write_i64(int(spawn["y"]))
	_write_string(str(data["fallback_policy"]))
	var bounds: Dictionary = data["world_contact_bounds"]
	_write_bool(bool(bounds["enabled"]))
	_write_i64(int(bounds["left"]))
	_write_i64(int(bounds["right"]))
	_write_i64(int(bounds["top"]))
	_write_i64(int(bounds["bottom"]))


func _write_character(character: RollbackFighterCharacterDefinition) -> void:
	var data := character.get_authoritative_data()
	_write_i64(int(data["config_version"]))
	_write_string(str(data["id"]))
	for field in [
		"max_hp", "move_speed", "acceleration", "braking",
		"reversal_acceleration", "knockback_friction",
		"max_knockback_speed", "hurtbox_x", "hurtbox_y",
		"hurtbox_width", "hurtbox_height", "guard_max_units",
		"guard_held_drain_per_frame", "guard_regen_per_frame",
		"guard_break_refill_units", "guard_break_stun_frames",
		"dodge_total_frames", "dodge_invuln_start", "dodge_invuln_end",
		"dodge_cooldown_frames",
	]:
		_write_i64(int(data[field]))

	_write_u32(MOVE_SLOTS.size())
	for slot in MOVE_SLOTS:
		_write_string(slot)
		_write_move(character.get_move_for_slot(slot))


func _write_move(move: RollbackFighterMoveDefinition) -> void:
	var data := move.get_authoritative_data()
	_write_i64(int(data["config_version"]))
	_write_string(str(data["id"]))
	for field in MOVE_INT_FIELDS:
		_write_i64(int(data[field]))
	_write_hitbox_profile(move.get_hitbox_profile())


func _write_hitbox_profile(profile: Dictionary) -> void:
	_write_i64(int(profile["config_version"]))
	_write_string(str(profile["move_id"]))
	var kind := str(profile["kind"])
	_write_string(kind)
	if kind == "legacy_horizontal_range":
		_write_i64(int(profile["reach"]))
		_write_i64(int(profile["defender_half_extent"]))
		return
	var frames: Array = profile["frames"]
	_write_u32(frames.size())
	for frame_variant in frames:
		var frame: Dictionary = frame_variant
		_write_i64(int(frame["active_frame"]))
		var hitboxes: Array = frame["hitboxes"]
		_write_u32(hitboxes.size())
		for box_variant in hitboxes:
			var box: Dictionary = box_variant
			_write_i64(int(box["x"]))
			_write_i64(int(box["y"]))
			_write_i64(int(box["width"]))
			_write_i64(int(box["height"]))


func _write_int_array(values: Array) -> void:
	_write_u32(values.size())
	for value in values:
		_write_i64(int(value))


func _write_bool(value: bool) -> void:
	_bytes.append(1 if value else 0)


func _write_u32(value: int) -> void:
	for shift in [24, 16, 8, 0]:
		_bytes.append((value >> shift) & 0xff)


func _write_i64(value: int) -> void:
	for shift in [56, 48, 40, 32, 24, 16, 8, 0]:
		_bytes.append((value >> shift) & 0xff)


func _write_string(value: String) -> void:
	var encoded := value.to_utf8_buffer()
	_write_u32(encoded.size())
	_bytes.append_array(encoded)


func _join_ints(values: Array) -> String:
	var parts := PackedStringArray()
	for value in values:
		parts.append(str(int(value)))
	return ",".join(parts)


func _profile_dump(profile: Dictionary) -> String:
	if str(profile["kind"]) == "legacy_horizontal_range":
		return "legacy_horizontal_range(%d,%d)" % [
			int(profile["reach"]), int(profile["defender_half_extent"]),
		]
	var parts := PackedStringArray()
	for frame_variant in profile["frames"]:
		var frame: Dictionary = frame_variant
		for box_variant in frame["hitboxes"]:
			var box: Dictionary = box_variant
			parts.append("%d:%d,%d,%d,%d" % [
				int(frame["active_frame"]), int(box["x"]), int(box["y"]),
				int(box["width"]), int(box["height"]),
			])
	return "|".join(parts)
