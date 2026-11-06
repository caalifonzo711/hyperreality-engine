extends Node

const SECRET_MARKER := "ai1-test-secret-value"
const ConfigScript = preload("res://games/rollback_fighter/scripts/ai_services/AIProviderConfig.gd")
const AIResult = preload("res://games/rollback_fighter/scripts/ai_services/AIResult.gd")


func get_provider_id() -> String:
	return "mock"


func get_display_name() -> String:
	return "Mock Provider"


func get_capabilities(_config) -> Array[String]:
	return ["TEXT"]


func make_default_config():
	var config = ConfigScript.new()
	config.provider_id = "mock"
	return config


func validate_configuration(_config) -> Dictionary:
	return AIResult.success("mock", "")


func test_connection(_config) -> Dictionary:
	return AIResult.success("mock", "TEXT", "OK", null, null, "Connected")


func generate_text(_request, _config) -> Dictionary:
	return {
		"success": false,
		"error_code": "UNKNOWN_RAW_ERROR",
		"user_message": "Safe failure",
		"provider_message": "provider accidentally echoed %s" % SECRET_MARKER,
		"raw_body": "must not escape",
		"api_key": SECRET_MARKER,
	}
