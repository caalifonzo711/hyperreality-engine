extends Node
class_name RollbackFighterAIProvider

const Contracts = preload("res://games/rollback_fighter/scripts/ai_services/AIContracts.gd")
const AIResult = preload("res://games/rollback_fighter/scripts/ai_services/AIResult.gd")


func get_provider_id() -> String:
	return ""


func get_display_name() -> String:
	return ""


func get_capabilities(_config) -> Array[String]:
	return []


func make_default_config():
	return null


func validate_configuration(_config) -> Dictionary:
	return AIResult.failure(get_provider_id(), "", Contracts.ERROR_NOT_CONFIGURED, "The AI provider is not configured.")


func test_connection(_config) -> Dictionary:
	return AIResult.failure(get_provider_id(), Contracts.CAPABILITY_TEXT, Contracts.ERROR_UNSUPPORTED_CAPABILITY, "Connection testing is not supported.")


func generate_text(_request, _config) -> Dictionary:
	return AIResult.failure(get_provider_id(), Contracts.CAPABILITY_TEXT, Contracts.ERROR_UNSUPPORTED_CAPABILITY, "Text generation is not supported.")


func generate_structured(_request, _config) -> Dictionary:
	return AIResult.failure(get_provider_id(), Contracts.CAPABILITY_STRUCTURED_OUTPUT, Contracts.ERROR_UNSUPPORTED_CAPABILITY, "Structured output is not supported.")


func generate_image(_request, _config) -> Dictionary:
	return AIResult.failure(get_provider_id(), Contracts.CAPABILITY_IMAGE_GENERATION, Contracts.ERROR_UNSUPPORTED_CAPABILITY, "Image generation is not supported by this provider configuration.")
