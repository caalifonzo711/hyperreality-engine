extends Node

const ConfigScript = preload("res://games/rollback_fighter/scripts/ai_services/AIProviderConfig.gd")
const AIResult = preload("res://games/rollback_fighter/scripts/ai_services/AIResult.gd")

var structured_output: Dictionary = {
	"reason": "Balanced test proposal.",
	"values": {"move_speed": 250},
}
var failure_code: String = ""
var failure_message: String = ""


func get_provider_id() -> String:
	return "structured_mock"


func get_display_name() -> String:
	return "Structured Mock"


func get_capabilities(_config) -> Array[String]:
	return ["TEXT", "STRUCTURED_OUTPUT"]


func make_default_config():
	var config = ConfigScript.new()
	config.provider_id = get_provider_id()
	return config


func validate_configuration(_config) -> Dictionary:
	return AIResult.success(get_provider_id(), "")


func generate_structured(_request, _config) -> Dictionary:
	if not failure_code.is_empty():
		return AIResult.failure(get_provider_id(), "STRUCTURED_OUTPUT", failure_code, failure_message)
	return AIResult.success(
		get_provider_id(),
		"STRUCTURED_OUTPUT",
		JSON.stringify(structured_output),
		structured_output.duplicate(true)
	)
