extends Node

const ConfigScript = preload("res://games/rollback_fighter/scripts/ai_services/AIProviderConfig.gd")
const AIResult = preload("res://games/rollback_fighter/scripts/ai_services/AIResult.gd")

var fail_code: String = ""
var fail_message: String = ""
var output_bytes: PackedByteArray = PackedByteArray()
var output_mime_type: String = "image/png"
var model_id: String = "mock-image-v1"
var last_request: Dictionary = {}


func get_provider_id() -> String:
	return "image_mock"


func get_display_name() -> String:
	return "Image Mock"


func get_capabilities(_config) -> Array[String]:
	return ["IMAGE_GENERATION"]


func make_default_config():
	var config = ConfigScript.new()
	config.provider_id = get_provider_id()
	config.image_model = model_id
	return config


func validate_configuration(_config) -> Dictionary:
	return AIResult.success(get_provider_id(), "")


func generate_image(request, _config) -> Dictionary:
	last_request = request.to_dictionary() if request != null and request.has_method("to_dictionary") else {}
	if not fail_code.is_empty():
		return AIResult.failure(get_provider_id(), "IMAGE_GENERATION", fail_code, fail_message)
	return AIResult.success(
		get_provider_id(),
		"IMAGE_GENERATION",
		"",
		null,
		{"bytes": output_bytes, "mime_type": output_mime_type, "model_id": model_id}
	)


func set_test_png(color: Color, width: int = 32, height: int = 64) -> void:
	var image := Image.create(width, height, false, Image.FORMAT_RGBA8)
	image.fill(color)
	output_bytes = image.save_png_to_buffer()
	output_mime_type = "image/png"
