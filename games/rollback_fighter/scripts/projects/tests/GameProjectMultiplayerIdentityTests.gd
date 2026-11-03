extends SceneTree

const ProjectDefinitionScript = preload("res://games/rollback_fighter/scripts/projects/GameProjectDefinition.gd")
const ProjectStoreScript = preload("res://games/rollback_fighter/scripts/projects/GameProjectStore.gd")
const ProjectBuilderScript = preload("res://games/rollback_fighter/scripts/projects/GameProjectBuilder.gd")
const ProjectIdentityScript = preload("res://games/rollback_fighter/scripts/projects/GameProjectMultiplayerIdentity.gd")
const ProjectWriterScript = preload("res://games/rollback_fighter/scripts/projects/CanonicalProjectWriter.gd")
const MatchHandshakeScript = preload("res://games/rollback_fighter/scripts/config/MatchConfigHandshake.gd")
const ConfigLoaderScript = preload("res://games/rollback_fighter/scripts/config/CharacterDefinitionLoader.gd")
const FighterProviderScript = preload("res://games/rollback_fighter/scripts/config/ImportedFighterProvider.gd")

const PROJECT_ID := "c10_identity_test"
const RULES_PATH := "res://games/rollback_fighter/config/game_rules.json"

func _initialize() -> void:
	var failures := PackedStringArray()
	_cleanup_tree("user://games/%s" % PROJECT_ID)
	var project := ProjectDefinitionScript.new()
	project.configure("C10 Identity Test", PROJECT_ID, "platform_fighter")
	project.add_fighter("example_fighter")
	project.add_fighter("example_fighter_alt")
	_expect(bool(ProjectStoreScript.new().create(project).get("ok", false)), "fixture project saves", failures)
	var build := ProjectBuilderScript.new().build(PROJECT_ID)
	_expect(bool(build.get("ok", false)), "fixture project builds", failures)

	var identity_service := ProjectIdentityScript.new()
	var first := identity_service.build(PROJECT_ID, true)
	var second := identity_service.build(PROJECT_ID, true)
	_expect(bool(first.get("ok", false)) and bool(second.get("ok", false)), "built project identity resolves", failures)
	if bool(first.get("ok", false)) and bool(second.get("ok", false)):
		var identity: Dictionary = first["identity"]
		_expect(str(identity["digest"]) == str(second["identity"]["digest"]), "identical projects produce the same digest", failures)
		_expect(Array(identity["roster"]).size() == 2, "identity contains the ordered fighter roster", failures)
		_expect(str(build.get("manifest", {}).get("multiplayer_project_digest", "")) == str(identity["digest"]), "build persists multiplayer digest separately", failures)
		_run_writer_tests(identity, failures)
		_run_verification_tests(identity_service, identity, failures)
		_expect(not JSON.stringify(identity).contains("user://") and not JSON.stringify(identity).contains("res://"), "wire identity contains no local paths", failures)

	_run_start_gate_tests(failures)
	_cleanup_tree("user://games/%s" % PROJECT_ID)
	_finish(failures)

func _run_writer_tests(identity: Dictionary, failures: PackedStringArray) -> void:
	var writer := ProjectWriterScript.new()
	var reordered := {
		"roster": identity["roster"],
		"rules_digest": identity["rules_digest"],
		"project_version": identity["project_version"],
		"project_id": identity["project_id"],
		"game_id": identity["game_id"],
		"rules_reference": identity["rules_reference"],
		"protocol_version": identity["protocol_version"],
		"local_path": "C:/machine-specific/location",
	}
	var canonical := writer.canonical_bytes(identity)
	_expect(canonical == writer.canonical_bytes(reordered), "dictionary order and local paths do not alter canonical bytes", failures)
	var presentation_a := reordered.duplicate(true)
	presentation_a["background_image"] = "user://games/a/assets/blue.png"
	presentation_a["logo_image"] = "user://games/a/assets/logo.png"
	presentation_a["audio_slots"] = {"bgm": "user://games/a/assets/music.ogg"}
	var presentation_b := reordered.duplicate(true)
	presentation_b["background_image"] = "user://games/b/assets/red.png"
	presentation_b["logo_image"] = ""
	presentation_b["audio_slots"] = {}
	_expect(writer.sha256_hex(writer.canonical_bytes(presentation_a)) == writer.sha256_hex(writer.canonical_bytes(presentation_b)), "presentation-only background/audio/logo differences do not alter digest", failures)
	var changed_rules := reordered.duplicate(true)
	changed_rules["rules_digest"] = "a".repeat(64)
	_expect(writer.sha256_hex(canonical) != writer.sha256_hex(writer.canonical_bytes(changed_rules)), "authoritative rules difference alters digest", failures)
	var changed_fighter := reordered.duplicate(true)
	changed_fighter["roster"] = Array(identity["roster"]).duplicate(true)
	changed_fighter["roster"][0]["digest"] = "b".repeat(64)
	_expect(writer.sha256_hex(canonical) != writer.sha256_hex(writer.canonical_bytes(changed_fighter)), "authoritative fighter difference alters digest", failures)
	var changed_roster := reordered.duplicate(true)
	changed_roster["roster"] = [Array(identity["roster"])[0]]
	_expect(writer.sha256_hex(canonical) != writer.sha256_hex(writer.canonical_bytes(changed_roster)), "roster difference alters digest", failures)

func _run_verification_tests(service, identity: Dictionary, failures: PackedStringArray) -> void:
	var identical := service.verify_remote(identity)
	_expect(bool(identical.get("ok", false)) and str(identical.get("message", "")) == "PROJECT CONFIG VERIFIED", "identical custom project handshake succeeds", failures)
	var cosmetic_difference := identity.duplicate(true)
	cosmetic_difference["style_preset"] = "anime_fighter"
	cosmetic_difference["presentation_policy_reference"] = "fighter_presentation:anime_fighter:v1"
	_expect(bool(service.verify_remote(cosmetic_difference).get("ok", false)), "presentation-only policy differences remain compatible", failures)
	var path_injection := identity.duplicate(true)
	path_injection["file_path"] = "user://untrusted/file"
	_expect(not bool(ProjectWriterScript.validate_identity(path_injection).get("ok", false)), "wire identity rejects arbitrary path fields", failures)
	var missing := identity.duplicate(true)
	missing["project_id"] = "c10_missing_project"
	_resign(missing)
	var missing_result := service.verify_remote(missing)
	_expect(str(missing_result.get("code", "")) == "PROJECT_NOT_INSTALLED", "missing project rejects cleanly", failures)
	var mismatch := identity.duplicate(true)
	mismatch["project_version"] = int(mismatch["project_version"]) + 1
	_resign(mismatch)
	var mismatch_result := service.verify_remote(mismatch)
	_expect(str(mismatch_result.get("code", "")) == "PROJECT_MISMATCH", "project digest/version mismatch rejects cleanly", failures)
	var missing_fighter := identity.duplicate(true)
	missing_fighter["roster"] = Array(missing_fighter["roster"]).duplicate(true)
	missing_fighter["roster"].append({"fighter_id": "missing_c10_fighter", "config_version": 1, "digest": "c".repeat(64)})
	_resign(missing_fighter)
	var fighter_result := service.verify_remote(missing_fighter)
	_expect(str(fighter_result.get("code", "")) == "FIGHTER_MISSING", "missing fighter rejects cleanly", failures)

func _run_start_gate_tests(failures: PackedStringArray) -> void:
	var loader := ConfigLoaderScript.new()
	var rules_result := loader.load_game_rules(RULES_PATH)
	var provider := FighterProviderScript.new()
	var p1_result := provider.load_fighter("example_fighter")
	var p2_result := provider.load_fighter("example_fighter_alt")
	_expect(bool(rules_result.get("ok", false)) and bool(p1_result.get("ok", false)) and bool(p2_result.get("ok", false)), "handshake fixtures load", failures)
	if not bool(rules_result.get("ok", false)) or not bool(p1_result.get("ok", false)) or not bool(p2_result.get("ok", false)):
		return
	var handshake := MatchHandshakeScript.new()
	var match_identity := handshake.build_local_identity(rules_result["definition"], p1_result["definition"], p2_result["definition"])
	_expect(bool(handshake.accept_remote_identity(match_identity).get("ok", false)), "existing fighter/config handshake verifies", failures)
	_expect(handshake.can_start_network_match(), "default built-in multiplayer remains ungated by a project", failures)
	handshake.set_project_verification(true, false)
	_expect(not handshake.can_start_network_match(), "START remains gated until project verification", failures)
	handshake.project_verified = true
	_expect(handshake.can_start_network_match(), "START is permitted after project and fighter verification", failures)

func _resign(identity: Dictionary) -> void:
	var writer := ProjectWriterScript.new()
	var bytes := writer.canonical_bytes(identity)
	identity["canonical_byte_length"] = bytes.size()
	identity["digest"] = writer.sha256_hex(bytes)

func _cleanup_tree(path: String) -> void:
	var absolute := ProjectSettings.globalize_path(path)
	if not DirAccess.dir_exists_absolute(absolute):
		return
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while not name.is_empty():
		var child := path + "/" + name
		if dir.current_is_dir():
			_cleanup_tree(child)
		else:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(child))
		name = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(absolute)

func _expect(condition: bool, message: String, failures: PackedStringArray) -> void:
	if not condition:
		failures.append(message)

func _finish(failures: PackedStringArray) -> void:
	if failures.is_empty():
		print("[GameProjectMultiplayerIdentityTests] PASS")
		quit(0)
		return
	for failure in failures:
		printerr("[GameProjectMultiplayerIdentityTests] FAIL: %s" % failure)
	quit(1)
