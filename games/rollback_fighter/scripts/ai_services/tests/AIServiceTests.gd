extends SceneTree

const TEST_SETTINGS_PATH := "user://settings/ai1_service_test.cfg"
const SECRET := "ai1-test-secret-value"
const Contracts = preload("res://games/rollback_fighter/scripts/ai_services/AIContracts.gd")
const ConfigScript = preload("res://games/rollback_fighter/scripts/ai_services/AIProviderConfig.gd")
const RegistryScript = preload("res://games/rollback_fighter/scripts/ai_services/AIProviderRegistry.gd")
const StoreScript = preload("res://games/rollback_fighter/scripts/ai_services/AISettingsStore.gd")
const ServiceScript = preload("res://games/rollback_fighter/scripts/ai_services/AIService.gd")
const GeminiScript = preload("res://games/rollback_fighter/scripts/ai_services/GeminiAIProvider.gd")
const ProjectDefinitionScript = preload("res://games/rollback_fighter/scripts/projects/GameProjectDefinition.gd")
const ProjectWriterScript = preload("res://games/rollback_fighter/scripts/projects/CanonicalProjectWriter.gd")
const LegacyGateScript = preload("res://games/rollback_fighter/scripts/GeminiReleaseGate.gd")
const MockProviderScript = preload("res://games/rollback_fighter/scripts/ai_services/tests/MockAIProvider.gd")


func _initialize() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	var failures := PackedStringArray()
	_remove_test_settings()
	_test_registry_and_capabilities(failures)
	_test_persistence_and_credentials(failures)
	_test_optional_service_and_result_contract(failures)
	_test_digest_and_data_isolation(failures)
	_test_legacy_gate_and_error_mapping(failures)
	_remove_test_settings()
	_finish(failures)


func _test_registry_and_capabilities(failures: PackedStringArray) -> void:
	var registry = RegistryScript.new()
	var mock: Node = MockProviderScript.new()
	_expect(registry.register_provider(mock), "provider registry registers a provider", failures)
	_expect(not registry.register_provider(mock), "duplicate provider registration fails safely", failures)
	_expect(registry.select_provider("mock"), "registered provider can be selected", failures)
	_expect(not registry.select_provider("missing"), "unsupported provider selection fails safely", failures)
	var service = ServiceScript.new()
	service.initialize(StoreScript.new(TEST_SETTINGS_PATH), false)
	_expect(service.register_provider(MockProviderScript.new()), "service registers provider", failures)
	service.enabled = true
	_expect(service.supports(Contracts.CAPABILITY_TEXT), "declared capability is supported", failures)
	_expect(not service.supports(Contracts.CAPABILITY_IMAGE_GENERATION), "undeclared capability is not supported", failures)
	service.free()
	mock.free()


func _test_persistence_and_credentials(failures: PackedStringArray) -> void:
	var store = StoreScript.new(TEST_SETTINGS_PATH)
	var config = ConfigScript.new()
	config.provider_id = "gemini"
	config.api_key = SECRET
	config.text_model = "test-model"
	var other_config = ConfigScript.new()
	other_config.provider_id = "mock"
	other_config.api_key = "other-provider-secret"
	var configurations := {"gemini": config, "mock": other_config}
	_expect(store.save_settings(true, "gemini", configurations) == OK, "AI settings save under user://", failures)
	var loaded: Dictionary = store.load_settings()
	_expect(bool(loaded.enabled), "AI enabled state persists", failures)
	_expect(str(loaded.selected_provider) == "gemini", "provider selection persists", failures)
	_expect(str(loaded.configurations.gemini.api_key) == SECRET, "credential persists in dedicated AI settings", failures)
	_expect(str(loaded.configurations.gemini.text_model) == "test-model", "model selection persists", failures)
	_expect(store.clear_credentials("gemini") == OK, "Clear Credentials succeeds", failures)
	loaded = store.load_settings()
	_expect(str(loaded.configurations.gemini.api_key).is_empty(), "Clear Credentials removes the stored key", failures)
	_expect(str(loaded.configurations.mock.api_key) == "other-provider-secret", "clearing one provider preserves another provider's configuration", failures)
	var unsafe_store = StoreScript.new("res://ai_settings_should_not_write.cfg")
	_expect(unsafe_store.save_settings(true, "gemini", configurations) == ERR_INVALID_PARAMETER, "AI settings refuse res:// writes", failures)


func _test_optional_service_and_result_contract(failures: PackedStringArray) -> void:
	var service = ServiceScript.new()
	service.initialize(StoreScript.new(TEST_SETTINGS_PATH), false)
	service.register_provider(MockProviderScript.new())
	var config: Variant = service.get_provider_config("mock")
	config.api_key = SECRET
	service.set_provider_config(config)
	var disabled: Dictionary = await service.generate_text(null)
	_expect(str(disabled.error_code) == Contracts.ERROR_NOT_CONFIGURED, "disabled AI fails without affecting startup", failures)
	service.enabled = true
	var connected: Dictionary = await service.test_connection()
	_expect(bool(connected.success) and str(connected.user_message) == "Connected", "connection test uses the selected provider", failures)
	var unsupported: Dictionary = await service.generate_image(null)
	_expect(str(unsupported.error_code) == Contracts.ERROR_UNSUPPORTED_CAPABILITY, "unsupported capability fails safely", failures)
	var result: Dictionary = await service.generate_text(null)
	_expect(str(result.error_code) == Contracts.ERROR_PROVIDER_ERROR, "unknown provider errors normalize", failures)
	_expect(not result.has("raw_body") and not result.has("api_key"), "raw provider response fields do not leak", failures)
	_expect(not JSON.stringify(result).contains(SECRET), "generic UI result contains no credential", failures)
	service.free()


func _test_digest_and_data_isolation(failures: PackedStringArray) -> void:
	var project = ProjectDefinitionScript.new()
	project.configure("AI Isolation", "ai_isolation", "platform_fighter")
	_expect(not JSON.stringify(project.to_dictionary()).contains(SECRET), "project data contains no AI credential", failures)
	var writer = ProjectWriterScript.new()
	var identity := {
		"protocol_version": 1,
		"game_id": "rollback_fighter",
		"project_id": "ai_isolation",
		"project_version": 1,
		"rules_reference": "builtin:platform_fighter_rules_v1",
		"rules_digest": "a".repeat(64),
		"roster": [],
	}
	var before: PackedByteArray = writer.canonical_bytes(identity)
	var store = StoreScript.new(TEST_SETTINGS_PATH)
	var config = ConfigScript.new()
	config.provider_id = "gemini"
	config.api_key = SECRET
	config.text_model = "another-model"
	store.save_settings(true, "gemini", {"gemini": config})
	var after: PackedByteArray = writer.canonical_bytes(identity)
	_expect(before == after, "AI settings do not change authoritative canonical bytes", failures)


func _test_legacy_gate_and_error_mapping(failures: PackedStringArray) -> void:
	var gemini = GeminiScript.new()
	var missing_config = gemini.make_default_config()
	var missing: Dictionary = gemini.validate_configuration(missing_config)
	_expect(str(missing.error_code) == Contracts.ERROR_NOT_CONFIGURED, "missing credentials fail validation cleanly", failures)
	_expect(str(gemini._http_failure(401, "TEXT").error_code) == Contracts.ERROR_AUTH_FAILED, "authentication errors normalize", failures)
	_expect(str(gemini._http_failure(404, "TEXT").error_code) == Contracts.ERROR_MODEL_UNAVAILABLE, "model errors normalize", failures)
	_expect(str(gemini._http_failure(429, "TEXT").error_code) == Contracts.ERROR_RATE_LIMITED, "rate limits normalize", failures)
	_expect(str(gemini._transport_failure({"error": "json_parse_error", "status_code": 200}, "TEXT").error_code) == Contracts.ERROR_INVALID_RESPONSE, "invalid provider payloads normalize", failures)
	var legacy = LegacyGateScript.new()
	_expect(legacy.has_method("generate_json_for_schema"), "legacy Gemini facade remains available", failures)
	legacy.free()
	gemini.free()


func _remove_test_settings() -> void:
	var absolute: String = ProjectSettings.globalize_path(TEST_SETTINGS_PATH)
	if FileAccess.file_exists(TEST_SETTINGS_PATH):
		DirAccess.remove_absolute(absolute)


func _expect(condition: bool, message: String, failures: PackedStringArray) -> void:
	if not condition:
		failures.append(message)


func _finish(failures: PackedStringArray) -> void:
	if failures.is_empty():
		print("[AIServiceTests] PASS")
		quit(0)
		return
	for failure: String in failures:
		printerr("[AIServiceTests] FAIL: %s" % failure)
	quit(1)
