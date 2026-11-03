extends RefCounted
class_name RollbackFighterCanonicalProjectWriter

const MAGIC := "HRF-PROJECT-AUTH-V1"
const PROTOCOL_VERSION := 1
const MAX_ROSTER_SIZE := 64
const MAX_CANONICAL_BYTE_LENGTH := 1048576

var _bytes := PackedByteArray()

# Multiplayer compatibility identity only. Presentation policy, style presentation,
# timestamps, local paths, branding, backgrounds, and audio are deliberately absent.
func canonical_bytes(components: Dictionary) -> PackedByteArray:
	_bytes = PackedByteArray()
	_write_string(MAGIC)
	_write_u32(int(components.get("protocol_version", PROTOCOL_VERSION)))
	_write_string(str(components.get("game_id", "rollback_fighter")))
	_write_string(str(components.get("project_id", "")))
	_write_u32(int(components.get("project_version", 0)))
	_write_string(str(components.get("rules_reference", "")))
	_write_string(str(components.get("rules_digest", "")))
	var roster: Array = components.get("roster", [])
	_write_u32(roster.size())
	for entry_value in roster:
		var entry: Dictionary = entry_value
		_write_string(str(entry.get("fighter_id", "")))
		_write_u32(int(entry.get("config_version", 0)))
		_write_string(str(entry.get("digest", "")))
	return _bytes.duplicate()

func sha256_hex(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK:
		return ""
	context.update(bytes)
	return context.finish().hex_encode()

static func validate_identity(identity: Dictionary) -> Dictionary:
	var fields := [
		"protocol_version", "game_id", "project_id", "project_version",
		"style_preset", "rules_reference", "rules_digest",
		"presentation_policy_reference", "roster", "canonical_byte_length",
		"digest",
	]
	if identity.size() != fields.size():
		return _failure("PROJECT_IDENTITY_INVALID", "Project identity contains unexpected fields.")
	for field in fields:
		if not identity.has(field):
			return _failure("PROJECT_IDENTITY_INVALID", "Project identity field is missing: %s." % field)
	for field in ["protocol_version", "project_version", "canonical_byte_length"]:
		if typeof(identity[field]) != TYPE_INT:
			return _failure("PROJECT_IDENTITY_INVALID", "Project identity field has invalid type: %s." % field)
	if (
		int(identity["protocol_version"]) != PROTOCOL_VERSION
		or int(identity["project_version"]) <= 0
		or int(identity["project_version"]) > 0xffffffff
	):
		return _failure("PROJECT_IDENTITY_INVALID", "Project identity version is invalid.")
	var byte_length := int(identity["canonical_byte_length"])
	if byte_length <= 0 or byte_length > MAX_CANONICAL_BYTE_LENGTH:
		return _failure("PROJECT_IDENTITY_INVALID", "Project canonical byte length is invalid.")
	for field in ["game_id", "project_id", "style_preset", "rules_reference", "presentation_policy_reference"]:
		if typeof(identity[field]) != TYPE_STRING or str(identity[field]).length() > 128:
			return _failure("PROJECT_IDENTITY_INVALID", "Project identity string is invalid: %s." % field)
	if str(identity["game_id"]) != "rollback_fighter" or not RollbackFighterGameProjectDefinition.is_safe_id(str(identity["project_id"])):
		return _failure("PROJECT_IDENTITY_INVALID", "Project game or project ID is invalid.")
	if str(identity["style_preset"]) not in RollbackFighterGameProjectDefinition.STYLE_PRESETS:
		return _failure("PROJECT_IDENTITY_INVALID", "Project style preset is invalid.")
	if str(identity["presentation_policy_reference"]) != RollbackFighterGameProjectDefinition.presentation_policy_for_style(str(identity["style_preset"])):
		return _failure("PROJECT_IDENTITY_INVALID", "Project presentation policy identity is invalid.")
	for field in ["rules_digest", "digest"]:
		if not _is_digest(str(identity[field])):
			return _failure("PROJECT_IDENTITY_INVALID", "Project identity digest is invalid: %s." % field)
	var roster_value: Variant = identity["roster"]
	if not roster_value is Array or roster_value.is_empty() or roster_value.size() > MAX_ROSTER_SIZE:
		return _failure("PROJECT_IDENTITY_INVALID", "Project roster is invalid or oversized.")
	var seen: Dictionary = {}
	for entry_value in roster_value:
		if not entry_value is Dictionary:
			return _failure("PROJECT_IDENTITY_INVALID", "Project roster entry must be an object.")
		var entry: Dictionary = entry_value
		if entry.size() != 3 or not entry.has("fighter_id") or not entry.has("config_version") or not entry.has("digest"):
			return _failure("PROJECT_IDENTITY_INVALID", "Project roster entry has unexpected fields.")
		var fighter_id := str(entry.get("fighter_id", ""))
		if fighter_id.length() > 64 or not RollbackFighterGameProjectDefinition.is_safe_id(fighter_id) or seen.has(fighter_id):
			return _failure("PROJECT_IDENTITY_INVALID", "Project roster fighter ID is invalid or duplicated.")
		if typeof(entry["config_version"]) != TYPE_INT or int(entry["config_version"]) <= 0:
			return _failure("PROJECT_IDENTITY_INVALID", "Project fighter config version is invalid.")
		if not _is_digest(str(entry["digest"])):
			return _failure("PROJECT_IDENTITY_INVALID", "Project fighter digest is invalid.")
		seen[fighter_id] = true
	return {"ok": true, "code": "", "message": ""}

func verify_identity(identity: Dictionary) -> Dictionary:
	var validation := validate_identity(identity)
	if not bool(validation.get("ok", false)):
		return validation
	var bytes := canonical_bytes(identity)
	if bytes.size() != int(identity["canonical_byte_length"]):
		return _failure("PROJECT_IDENTITY_INVALID", "Project canonical byte length does not match its identity.")
	if sha256_hex(bytes) != str(identity["digest"]):
		return _failure("PROJECT_IDENTITY_INVALID", "Project canonical digest does not match its identity.")
	return {"ok": true, "code": "", "message": ""}

static func _is_digest(value: String) -> bool:
	if value.length() != 64:
		return false
	for index in value.length():
		var code := value.unicode_at(index)
		if not ((code >= 48 and code <= 57) or (code >= 97 and code <= 102)):
			return false
	return true

static func _failure(code: String, message: String) -> Dictionary:
	return {"ok": false, "code": code, "message": message}

func _write_u32(value: int) -> void:
	for shift in [24, 16, 8, 0]:
		_bytes.append((value >> shift) & 0xff)

func _write_string(value: String) -> void:
	var encoded := value.to_utf8_buffer()
	_write_u32(encoded.size())
	_bytes.append_array(encoded)
