extends Node
class_name RollbackFighterAIService

const Contracts = preload("res://games/rollback_fighter/scripts/ai_services/AIContracts.gd")
const AIResult = preload("res://games/rollback_fighter/scripts/ai_services/AIResult.gd")
const RegistryScript = preload("res://games/rollback_fighter/scripts/ai_services/AIProviderRegistry.gd")
const SettingsStoreScript = preload("res://games/rollback_fighter/scripts/ai_services/AISettingsStore.gd")
const GeminiProviderScript = preload("res://games/rollback_fighter/scripts/ai_services/GeminiAIProvider.gd")

var enabled: bool = false
var _registry
var _store
var _configurations: Dictionary = {}
var _initialized: bool = false


func _ready() -> void:
	initialize()


func initialize(settings_store = null, register_defaults: bool = true) -> void:
	if _initialized:
		return
	_registry = RegistryScript.new()
	_store = settings_store if settings_store != null else SettingsStoreScript.new()
	if register_defaults:
		register_provider(GeminiProviderScript.new())
	var stored: Dictionary = _store.load_settings()
	enabled = bool(stored.get("enabled", false))
	var stored_configs: Variant = stored.get("configurations", {})
	if stored_configs is Dictionary:
		for provider_id: Variant in stored_configs:
			_configurations[str(provider_id)] = stored_configs[provider_id]
	var selected: String = str(stored.get("selected_provider", ""))
	if not selected.is_empty():
		_registry.select_provider(selected)
	_initialized = true


func register_provider(provider: Node) -> bool:
	if provider == null or not _registry.register_provider(provider):
		return false
	add_child(provider)
	var provider_id: String = str(provider.call("get_provider_id"))
	if not _configurations.has(provider_id) and provider.has_method("make_default_config"):
		_configurations[provider_id] = provider.call("make_default_config")
	return true


func list_providers() -> Array[Dictionary]:
	initialize()
	var providers: Array[Dictionary] = []
	for provider_id: String in _registry.list_provider_ids():
		var provider: Node = _registry.get_provider(provider_id)
		providers.append({
			"provider_id": provider_id,
			"display_name": str(provider.call("get_display_name")),
		})
	return providers


func select_provider(provider_id: String) -> bool:
	initialize()
	return _registry.select_provider(provider_id)


func get_selected_provider_id() -> String:
	initialize()
	return _registry.get_selected_provider_id()


func get_provider_config(provider_id: String = ""):
	initialize()
	var resolved_id: String = provider_id if not provider_id.is_empty() else get_selected_provider_id()
	var config: Variant = _configurations.get(resolved_id)
	return config.duplicate_config() if config != null and config.has_method("duplicate_config") else config


func set_provider_config(config) -> bool:
	initialize()
	if config == null:
		return false
	var provider_id: String = str(config.provider_id)
	if _registry.get_provider(provider_id) == null:
		return false
	_configurations[provider_id] = config.duplicate_config()
	return true


func supports(capability: String) -> bool:
	initialize()
	if capability not in Contracts.CAPABILITIES:
		return false
	var provider: Node = _registry.get_selected_provider()
	if provider == null:
		return false
	var capabilities: Variant = provider.call("get_capabilities", _configurations.get(get_selected_provider_id()))
	return capabilities is Array and capability in capabilities


func save_settings() -> Error:
	initialize()
	return _store.save_settings(enabled, get_selected_provider_id(), _configurations)


func clear_credentials(provider_id: String = "") -> Error:
	initialize()
	var resolved_id: String = provider_id if not provider_id.is_empty() else get_selected_provider_id()
	var config: Variant = _configurations.get(resolved_id)
	if config != null:
		config.api_key = ""
	return _store.clear_credentials(resolved_id)


func validate_configuration() -> Dictionary:
	initialize()
	var preflight: Dictionary = _preflight("")
	if not preflight.is_empty():
		return preflight
	var provider: Node = _registry.get_selected_provider()
	return _sanitize_result(AIResult.sanitize(
		provider.call("validate_configuration", _configurations.get(get_selected_provider_id())),
		get_selected_provider_id(),
		""
	))


func test_connection() -> Dictionary:
	initialize()
	var preflight: Dictionary = _preflight(Contracts.CAPABILITY_TEXT)
	if not preflight.is_empty():
		return preflight
	var provider: Node = _registry.get_selected_provider()
	var value: Variant = await provider.call("test_connection", _configurations.get(get_selected_provider_id()))
	return _sanitize_result(AIResult.sanitize(value, get_selected_provider_id(), Contracts.CAPABILITY_TEXT))


func generate_text(request) -> Dictionary:
	return await _dispatch("generate_text", Contracts.CAPABILITY_TEXT, request)


func generate_structured(request) -> Dictionary:
	return await _dispatch("generate_structured", Contracts.CAPABILITY_STRUCTURED_OUTPUT, request)


func generate_image(request) -> Dictionary:
	return await _dispatch("generate_image", Contracts.CAPABILITY_IMAGE_GENERATION, request)


func _dispatch(method: String, capability: String, request) -> Dictionary:
	initialize()
	var preflight: Dictionary = _preflight(capability)
	if not preflight.is_empty():
		return preflight
	var provider: Node = _registry.get_selected_provider()
	var value: Variant = await provider.call(method, request, _configurations.get(get_selected_provider_id()))
	return _sanitize_result(AIResult.sanitize(value, get_selected_provider_id(), capability))


func _preflight(capability: String) -> Dictionary:
	if not enabled:
		return AIResult.failure(get_selected_provider_id(), capability, Contracts.ERROR_NOT_CONFIGURED, "AI assistance is disabled.")
	var provider: Node = _registry.get_selected_provider()
	if provider == null:
		return AIResult.failure("", capability, Contracts.ERROR_NOT_CONFIGURED, "Select an AI provider.")
	if not capability.is_empty() and not supports(capability):
		return AIResult.failure(get_selected_provider_id(), capability, Contracts.ERROR_UNSUPPORTED_CAPABILITY, "The selected provider does not support this feature.")
	return {}


func _sanitize_result(result: Dictionary) -> Dictionary:
	var config: Variant = _configurations.get(get_selected_provider_id())
	var credential: String = str(config.api_key) if config != null else ""
	if credential.is_empty():
		return result
	for field: String in ["text_output", "user_message", "provider_message"]:
		result[field] = str(result.get(field, "")).replace(credential, "[redacted]")
	return result
