extends RefCounted
class_name RollbackFighterAISettingsStore

const DEFAULT_PATH := "user://settings/ai_settings.cfg"
const ConfigScript = preload("res://games/rollback_fighter/scripts/ai_services/AIProviderConfig.gd")

var settings_path: String = DEFAULT_PATH


func _init(path: String = DEFAULT_PATH) -> void:
	settings_path = path


func load_settings() -> Dictionary:
	var result := {
		"enabled": false,
		"selected_provider": "gemini",
		"configurations": {},
	}
	var file := ConfigFile.new()
	var error: Error = file.load(settings_path)
	if error == ERR_FILE_NOT_FOUND:
		return result
	if error != OK:
		return result
	result.enabled = bool(file.get_value("general", "enabled", false))
	result.selected_provider = str(file.get_value("general", "selected_provider", "gemini"))
	var configurations: Dictionary = {}
	for section: String in file.get_sections():
		if not section.begins_with("provider/"):
			continue
		var provider_id: String = section.trim_prefix("provider/")
		if not _is_safe_id(provider_id):
			continue
		var config = ConfigScript.new()
		config.provider_id = provider_id
		config.api_key = str(file.get_value(section, "api_key", ""))
		config.text_model = str(file.get_value(section, "text_model", ""))
		config.image_model = str(file.get_value(section, "image_model", ""))
		config.endpoint_override = str(file.get_value(section, "endpoint_override", ""))
		config.enabled = bool(file.get_value(section, "enabled", true))
		var extras_value: Variant = file.get_value(section, "extras", {})
		config.extras = extras_value.duplicate(true) if extras_value is Dictionary else {}
		configurations[provider_id] = config
	result.configurations = configurations
	return result


func save_settings(enabled: bool, selected_provider: String, configurations: Dictionary) -> Error:
	if not settings_path.begins_with("user://") or not _is_safe_id(selected_provider):
		return ERR_INVALID_PARAMETER
	var absolute_directory: String = ProjectSettings.globalize_path(settings_path.get_base_dir())
	var directory_error: Error = DirAccess.make_dir_recursive_absolute(absolute_directory)
	if directory_error != OK:
		return directory_error
	var file := ConfigFile.new()
	file.set_value("general", "enabled", enabled)
	file.set_value("general", "selected_provider", selected_provider)
	var provider_ids: Array[String] = []
	for value: Variant in configurations.keys():
		provider_ids.append(str(value))
	provider_ids.sort()
	for provider_id: String in provider_ids:
		if not _is_safe_id(provider_id):
			continue
		var config: Variant = configurations.get(provider_id)
		if config == null:
			continue
		var section := "provider/%s" % provider_id
		file.set_value(section, "api_key", str(config.api_key))
		file.set_value(section, "text_model", str(config.text_model))
		file.set_value(section, "image_model", str(config.image_model))
		file.set_value(section, "endpoint_override", str(config.endpoint_override))
		file.set_value(section, "enabled", bool(config.enabled))
		file.set_value(section, "extras", config.extras.duplicate(true))
	return file.save(settings_path)


func clear_credentials(provider_id: String) -> Error:
	if not _is_safe_id(provider_id):
		return ERR_INVALID_PARAMETER
	var loaded: Dictionary = load_settings()
	var configurations: Dictionary = loaded.configurations
	if configurations.has(provider_id):
		configurations[provider_id].api_key = ""
	return save_settings(bool(loaded.enabled), str(loaded.selected_provider), configurations)


func _is_safe_id(value: String) -> bool:
	if value.is_empty():
		return false
	for index in value.length():
		var code: int = value.unicode_at(index)
		if not ((code >= 97 and code <= 122) or (code >= 48 and code <= 57) or code == 95):
			return false
	return true
