extends RefCounted
class_name RollbackFighterAIProviderConfig

var provider_id: String = ""
var api_key: String = ""
var text_model: String = ""
var image_model: String = ""
var endpoint_override: String = ""
var enabled: bool = true
var extras: Dictionary = {}


func duplicate_config() -> RollbackFighterAIProviderConfig:
	var copy := RollbackFighterAIProviderConfig.new()
	copy.provider_id = provider_id
	copy.api_key = api_key
	copy.text_model = text_model
	copy.image_model = image_model
	copy.endpoint_override = endpoint_override
	copy.enabled = enabled
	copy.extras = extras.duplicate(true)
	return copy


func public_dictionary() -> Dictionary:
	return {
		"provider_id": provider_id,
		"text_model": text_model,
		"image_model": image_model,
		"endpoint_override": endpoint_override,
		"enabled": enabled,
		"extras": extras.duplicate(true),
	}
