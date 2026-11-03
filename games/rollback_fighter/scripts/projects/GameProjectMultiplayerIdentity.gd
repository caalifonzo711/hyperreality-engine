extends RefCounted
class_name RollbackFighterGameProjectMultiplayerIdentity

const ProjectStoreScript = preload("res://games/rollback_fighter/scripts/projects/GameProjectStore.gd")
const ReadinessScript = preload("res://games/rollback_fighter/scripts/projects/GameProjectReadiness.gd")
const ProjectWriterScript = preload("res://games/rollback_fighter/scripts/projects/CanonicalProjectWriter.gd")
const ConfigWriterScript = preload("res://games/rollback_fighter/scripts/config/CanonicalConfigWriter.gd")
const LoaderScript = preload("res://games/rollback_fighter/scripts/config/CharacterDefinitionLoader.gd")
const FighterProviderScript = preload("res://games/rollback_fighter/scripts/config/ImportedFighterProvider.gd")
const RULES_PATH := "res://games/rollback_fighter/config/game_rules.json"
const SUPPORTED_RULES_REFERENCE := "builtin:platform_fighter_rules_v1"

func build(project_id: String, require_built: bool = true) -> Dictionary:
	var loaded := ProjectStoreScript.new().load_project(project_id)
	if not bool(loaded.get("ok", false)):
		return _failure("PROJECT_NOT_INSTALLED", "Game project not installed")
	var project: RollbackFighterGameProjectDefinition = loaded["project"]
	if require_built:
		var readiness := ReadinessScript.new().evaluate(project_id)
		if not bool(readiness.get("can_play", false)):
			return _failure("PROJECT_NOT_BUILT", "Project changed — rebuild before hosting.")
	if project.rules_reference != SUPPORTED_RULES_REFERENCE:
		return _failure("PROJECT_RULES_UNSUPPORTED", "Game project version/configuration mismatch")
	var rules_result := LoaderScript.new().load_game_rules(RULES_PATH)
	if not bool(rules_result.get("ok", false)):
		return _failure("PROJECT_RULES_INVALID", "Game project rules could not be loaded.")
	var rules: RollbackFighterGameRulesDefinition = rules_result["definition"]
	var config_writer := ConfigWriterScript.new()
	var rules_bytes: PackedByteArray = config_writer.rules_bytes(rules)
	var rules_digest := config_writer.sha256_hex(rules_bytes)
	var fighter_provider := FighterProviderScript.new()
	var roster: Array[Dictionary] = []
	for fighter_id in project.fighter_ids:
		var fighter_result := fighter_provider.load_fighter(fighter_id)
		if not bool(fighter_result.get("ok", false)):
			return _failure("FIGHTER_MISSING", "Fighter not installed on both devices")
		var fighter: RollbackFighterCharacterDefinition = fighter_result["definition"]
		var fighter_bytes: PackedByteArray = config_writer.character_bytes(rules, fighter)
		roster.append({
			"fighter_id": fighter_id,
			"config_version": fighter.get_config_version(),
			"digest": config_writer.sha256_hex(fighter_bytes),
		})
	var components := {
		"protocol_version": ProjectWriterScript.PROTOCOL_VERSION,
		"game_id": "rollback_fighter",
		"project_id": project.project_id,
		"project_version": project.version,
		"rules_reference": project.rules_reference,
		"rules_digest": rules_digest,
		"roster": roster,
	}
	var project_writer := ProjectWriterScript.new()
	var canonical_bytes: PackedByteArray = project_writer.canonical_bytes(components)
	var identity := {
		"protocol_version": ProjectWriterScript.PROTOCOL_VERSION,
		"game_id": "rollback_fighter",
		"project_id": project.project_id,
		"project_version": project.version,
		"style_preset": project.style_preset,
		"rules_reference": project.rules_reference,
		"rules_digest": rules_digest,
		"presentation_policy_reference": project.presentation_policy_reference,
		"roster": roster,
		"canonical_byte_length": canonical_bytes.size(),
		"digest": project_writer.sha256_hex(canonical_bytes),
	}
	var validation := ProjectWriterScript.validate_identity(identity)
	if not bool(validation.get("ok", false)):
		return validation
	return {"ok": true, "identity": identity, "canonical_bytes": canonical_bytes, "errors": []}

func verify_remote(candidate: Dictionary) -> Dictionary:
	var validation := ProjectWriterScript.new().verify_identity(candidate)
	if not bool(validation.get("ok", false)):
		return validation
	var project_id := str(candidate["project_id"])
	var loaded := ProjectStoreScript.new().load_project(project_id)
	if not bool(loaded.get("ok", false)):
		return _failure("PROJECT_NOT_INSTALLED", "Game project not installed")
	var fighter_provider := FighterProviderScript.new()
	for entry_value in candidate["roster"]:
		var fighter_id := str(entry_value.get("fighter_id", ""))
		if not bool(fighter_provider.load_fighter(fighter_id).get("ok", false)):
			return _failure("FIGHTER_MISSING", "Fighter not installed on both devices")
	# Hosting requires a current C10 build. A client may use a valid project whose
	# local build is stale only because presentation assets changed; its freshly
	# computed authoritative digest must still match the host.
	var readiness := ReadinessScript.new().evaluate(project_id)
	if not bool(readiness.get("can_build", false)):
		return _failure("PROJECT_MISMATCH", "Game project version/configuration mismatch")
	var local := build(project_id, false)
	if not bool(local.get("ok", false)):
		return local
	var local_identity: Dictionary = local["identity"]
	if int(candidate["project_version"]) != int(local_identity["project_version"]):
		return _failure("PROJECT_MISMATCH", "Game project version/configuration mismatch")
	if str(candidate["digest"]) != str(local_identity["digest"]):
		return _failure("PROJECT_MISMATCH", "Game project version/configuration mismatch")
	return {"ok": true, "code": "", "message": "PROJECT CONFIG VERIFIED", "identity": local_identity}

func _failure(code: String, message: String) -> Dictionary:
	return {"ok": false, "code": code, "message": message, "errors": [message]}
