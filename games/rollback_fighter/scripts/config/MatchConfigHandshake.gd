extends RefCounted
class_name RollbackFighterMatchConfigHandshake


const PROTOCOL_VERSION: int = 1
const MAX_CANONICAL_BYTE_LENGTH: int = 1048576
const MAX_FIGHTER_ID_LENGTH: int = 64

var local_identity: Dictionary = {}
var remote_identity: Dictionary = {}
var verified: bool = false
var failed: bool = false
var failure_message: String = ""


func build_local_identity(
	writer: RollbackFighterCanonicalConfigWriter,
	rules: RollbackFighterGameRulesDefinition,
	p1: RollbackFighterCharacterDefinition,
	p2: RollbackFighterCharacterDefinition
) -> Dictionary:
	var canonical_bytes: PackedByteArray = writer.match_bytes(rules, p1, p2)
	return {
		"protocol_version": PROTOCOL_VERSION,
		"rules_config_version": rules.get_int("config_version"),
		"p1_id": p1.get_id(),
		"p1_config_version": p1.get_config_version(),
		"p2_id": p2.get_id(),
		"p2_config_version": p2.get_config_version(),
		"canonical_byte_length": canonical_bytes.size(),
		"digest": writer.sha256_hex(canonical_bytes),
	}


func accept_remote_identity(candidate: Dictionary) -> Dictionary:
	remote_identity = candidate.duplicate(true)
	verified = false
	failed = false
	failure_message = ""

	var validation: Dictionary = _validate_identity(candidate)
	if not bool(validation.get("ok", false)):
		return _fail(str(validation.get("message", "Invalid config handshake.")))
	if local_identity.is_empty():
		return _fail("Local config identity is unavailable.")
	var local_validation: Dictionary = _validate_identity(local_identity)
	if not bool(local_validation.get("ok", false)):
		return _fail("Local config identity is invalid.")

	if int(candidate["protocol_version"]) != int(local_identity["protocol_version"]):
		return _fail("CONFIG HANDSHAKE VERSION MISMATCH")
	if int(candidate["rules_config_version"]) != int(local_identity["rules_config_version"]):
		return _fail("Game rules config version mismatch.")
	if (
		str(candidate["p1_id"]) != str(local_identity["p1_id"])
		or str(candidate["p2_id"]) != str(local_identity["p2_id"])
	):
		return _fail(
			"Fighter ID mismatch: local P1=%s P2=%s; remote P1=%s P2=%s."
			% [
				str(local_identity["p1_id"]),
				str(local_identity["p2_id"]),
				str(candidate["p1_id"]),
				str(candidate["p2_id"]),
			]
		)
	if (
		int(candidate["p1_config_version"])
		!= int(local_identity["p1_config_version"])
		or int(candidate["p2_config_version"])
		!= int(local_identity["p2_config_version"])
	):
		return _fail("Character config version mismatch.")
	if int(candidate["canonical_byte_length"]) != int(local_identity["canonical_byte_length"]):
		return _fail("Canonical config byte length mismatch.")
	if str(candidate["digest"]) != str(local_identity["digest"]):
		return _fail("CONFIG MISMATCH")

	verified = true
	return {"ok": true, "message": "MATCH CONFIG VERIFIED"}


func can_start_network_match() -> bool:
	return verified and not failed


func may_start_match(networked: bool) -> bool:
	return not networked or can_start_network_match()


func _validate_identity(identity: Dictionary) -> Dictionary:
	var required_fields: Array[String] = [
		"protocol_version",
		"rules_config_version",
		"p1_id",
		"p1_config_version",
		"p2_id",
		"p2_config_version",
		"canonical_byte_length",
		"digest",
	]
	if identity.size() != required_fields.size():
		return {"ok": false, "message": "Handshake contains unexpected fields."}
	for field in required_fields:
		if not identity.has(field):
			return {"ok": false, "message": "Handshake field missing: %s." % field}

	for field in [
		"protocol_version",
		"rules_config_version",
		"p1_config_version",
		"p2_config_version",
		"canonical_byte_length",
	]:
		if typeof(identity[field]) != TYPE_INT:
			return {"ok": false, "message": "Handshake field has invalid type: %s." % field}

	if int(identity["protocol_version"]) <= 0:
		return {"ok": false, "message": "Handshake protocol version must be positive."}
	for field in ["rules_config_version", "p1_config_version", "p2_config_version"]:
		if int(identity[field]) <= 0 or int(identity[field]) > 65535:
			return {"ok": false, "message": "Handshake config version is out of range: %s." % field}

	var byte_length: int = int(identity["canonical_byte_length"])
	if byte_length <= 0 or byte_length > MAX_CANONICAL_BYTE_LENGTH:
		return {"ok": false, "message": "Handshake canonical byte length is out of range."}

	for field in ["p1_id", "p2_id"]:
		if typeof(identity[field]) != TYPE_STRING:
			return {"ok": false, "message": "Handshake fighter ID has invalid type: %s." % field}
		if not _is_valid_fighter_id(str(identity[field])):
			return {"ok": false, "message": "Handshake fighter ID is invalid: %s." % field}

	if typeof(identity["digest"]) != TYPE_STRING:
		return {"ok": false, "message": "Handshake digest has invalid type."}
	var digest: String = str(identity["digest"])
	if digest.length() != 64:
		return {"ok": false, "message": "Handshake digest must contain exactly 64 lowercase hexadecimal characters."}
	for index in digest.length():
		var code: int = digest.unicode_at(index)
		if not ((code >= 48 and code <= 57) or (code >= 97 and code <= 102)):
			return {"ok": false, "message": "Handshake digest must contain exactly 64 lowercase hexadecimal characters."}

	return {"ok": true, "message": ""}


func _is_valid_fighter_id(value: String) -> bool:
	if value.is_empty() or value.length() > MAX_FIGHTER_ID_LENGTH:
		return false
	for index in value.length():
		var code: int = value.unicode_at(index)
		if not ((code >= 97 and code <= 122) or (code >= 48 and code <= 57) or code == 95):
			return false
	return true


func _fail(message: String) -> Dictionary:
	failed = true
	verified = false
	failure_message = message
	return {"ok": false, "message": message}
