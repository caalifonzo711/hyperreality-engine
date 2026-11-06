extends "res://games/rollback_fighter/scripts/ai_services/AIProvider.gd"
class_name RollbackFighterGeminiAIProvider

const ConfigScript = preload("res://games/rollback_fighter/scripts/ai_services/AIProviderConfig.gd")
const TextRequestScript = preload("res://games/rollback_fighter/scripts/ai_services/AITextRequest.gd")
const HttpClientScript = preload("res://addons/gemini_integration/src/GeminiHttpClient.gd")

const PROVIDER_ID := "gemini"
const DEFAULT_TEXT_MODEL := "gemini-3.8-flash"
const DEFAULT_ENDPOINT := "https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent"
const DEFAULT_IMAGE_MODEL := "gemini-3.1-flash-image"
const DEFAULT_IMAGE_ENDPOINT := "https://generativelanguage.googleapis.com/v1/models/{model}:generateContent"

var _http_client: Node


func get_provider_id() -> String:
	return PROVIDER_ID


func get_display_name() -> String:
	return "Google Gemini"


func get_capabilities(config) -> Array[String]:
	var capabilities: Array[String] = [Contracts.CAPABILITY_TEXT, Contracts.CAPABILITY_STRUCTURED_OUTPUT]
	if config != null and not str(config.image_model).strip_edges().is_empty():
		capabilities.append(Contracts.CAPABILITY_IMAGE_GENERATION)
	return capabilities


func make_default_config():
	var config = ConfigScript.new()
	config.provider_id = PROVIDER_ID
	config.text_model = DEFAULT_TEXT_MODEL
	config.image_model = DEFAULT_IMAGE_MODEL
	return config


func validate_configuration(config) -> Dictionary:
	if config == null or str(config.provider_id) != PROVIDER_ID:
		return AIResult.failure(PROVIDER_ID, "", Contracts.ERROR_NOT_CONFIGURED, "Select Gemini before using AI features.")
	if not bool(config.enabled):
		return AIResult.failure(PROVIDER_ID, "", Contracts.ERROR_NOT_CONFIGURED, "Gemini is disabled in its provider configuration.")
	if str(config.api_key).strip_edges().is_empty():
		return AIResult.failure(PROVIDER_ID, "", Contracts.ERROR_NOT_CONFIGURED, "Enter a Gemini API key.")
	if str(config.text_model).strip_edges().is_empty():
		return AIResult.failure(PROVIDER_ID, "", Contracts.ERROR_NOT_CONFIGURED, "Enter a Gemini text model.")
	return AIResult.success(PROVIDER_ID, "", "", null, null, "Configuration is valid.")


func test_connection(config) -> Dictionary:
	var validation: Dictionary = validate_configuration(config)
	if not validation.success:
		return validation
	var request = TextRequestScript.new()
	request.prompt = "Reply with OK."
	request.temperature = 0.0
	request.max_output_tokens = 8
	var result: Dictionary = await generate_text(request, config)
	if result.success:
		result.user_message = "Connected"
	return result


func generate_text(request, config) -> Dictionary:
	return await _generate(request, config, false)


func generate_structured(request, config) -> Dictionary:
	return await _generate(request, config, true)


func generate_image(request, config) -> Dictionary:
	var capability: String = Contracts.CAPABILITY_IMAGE_GENERATION
	var validation: Dictionary = _validate_image_configuration(config)
	if not validation.success:
		return validation
	if request == null or not request.has_method("to_dictionary"):
		return AIResult.failure(PROVIDER_ID, capability, Contracts.ERROR_INVALID_RESPONSE, "The image request is invalid.")
	var request_data: Dictionary = request.to_dictionary()
	var prompt: String = str(request_data.get("prompt", "")).strip_edges()
	if prompt.is_empty():
		return AIResult.failure(PROVIDER_ID, capability, Contracts.ERROR_INVALID_RESPONSE, "Enter an image prompt before sending the request.")
	var parts: Array[Dictionary] = [{"text": prompt}]
	var references_value: Variant = request_data.get("reference_images", [])
	if references_value is Array:
		for reference_value: Variant in references_value:
			if not reference_value is Dictionary:
				continue
			var reference: Dictionary = reference_value
			var reference_bytes: Variant = reference.get("bytes", PackedByteArray())
			var mime_type: String = str(reference.get("mime_type", ""))
			if reference_bytes is PackedByteArray:
				var image_bytes: PackedByteArray = reference_bytes
				if not image_bytes.is_empty() and mime_type in ["image/png", "image/jpeg", "image/webp"]:
					parts.append({"inlineData": {"mimeType": mime_type, "data": Marshalls.raw_to_base64(image_bytes)}})
	var aspect_ratio: String = str(request_data.get("aspect_ratio", "1:1"))
	if aspect_ratio not in ["1:1", "2:3", "3:2", "3:4", "4:3", "4:5", "5:4", "9:16", "16:9", "21:9"]:
		aspect_ratio = "1:1"
	var body: Dictionary = {
		"contents": [{"role": "user", "parts": parts}],
		"generationConfig": {
			"responseModalities": ["IMAGE"],
			"responseFormat": {"image": {"aspectRatio": aspect_ratio, "imageSize": "1K"}},
		},
	}
	var endpoint: String = str(config.extras.get("image_endpoint_override", "")).strip_edges()
	if endpoint.is_empty():
		endpoint = DEFAULT_IMAGE_ENDPOINT
	endpoint = endpoint.replace("{model}", str(config.image_model).uri_encode())
	if not endpoint.begins_with("https://"):
		return AIResult.failure(PROVIDER_ID, capability, Contracts.ERROR_NOT_CONFIGURED, "The image endpoint override must use HTTPS.")
	var headers := PackedStringArray([
		"Content-Type: application/json",
		"x-goog-api-key: %s" % str(config.api_key),
	])
	var response_value: Variant = await _get_http_client().call("send_request", endpoint, headers, body, 120.0)
	if not response_value is Dictionary:
		return AIResult.failure(PROVIDER_ID, capability, Contracts.ERROR_INVALID_RESPONSE, "Gemini returned an invalid image response.")
	var response: Dictionary = response_value
	if not bool(response.get("ok", false)):
		return _transport_failure(response, capability)
	var status_code: int = int(response.get("status_code", 0))
	if status_code < 200 or status_code >= 300:
		return _http_failure(status_code, capability)
	var image: Dictionary = _extract_image(response.get("data", null))
	if image.is_empty():
		return AIResult.failure(PROVIDER_ID, capability, Contracts.ERROR_INVALID_RESPONSE, "Gemini returned no usable image.")
	image["model_id"] = str(config.image_model)
	return AIResult.success(PROVIDER_ID, capability, "", null, image)


func _generate(request, config, structured: bool) -> Dictionary:
	var capability: String = Contracts.CAPABILITY_STRUCTURED_OUTPUT if structured else Contracts.CAPABILITY_TEXT
	var validation: Dictionary = validate_configuration(config)
	if not validation.success:
		validation.capability = capability
		return validation
	if request == null or not request.has_method("to_dictionary"):
		return AIResult.failure(PROVIDER_ID, capability, Contracts.ERROR_INVALID_RESPONSE, "The AI request is invalid.")
	var request_data: Dictionary = request.to_dictionary()
	if str(request_data.get("prompt", "")).strip_edges().is_empty():
		return AIResult.failure(PROVIDER_ID, capability, Contracts.ERROR_INVALID_RESPONSE, "Enter a prompt before sending the request.")
	var body: Dictionary = {
		"contents": [{"role": "user", "parts": [{"text": str(request_data.prompt)}]}],
		"generationConfig": {
			"maxOutputTokens": int(request_data.get("max_output_tokens", 1024)),
		},
	}
	# Current Gemini 3 models reject legacy sampling knobs. Providers are free to
	# omit generic optional controls when their selected model does not accept them.
	if bool(config.extras.get("send_temperature", false)):
		body.generationConfig.temperature = float(request_data.get("temperature", 0.2))
	var instruction: String = str(request_data.get("instruction", "")).strip_edges()
	if not instruction.is_empty():
		body.systemInstruction = {"parts": [{"text": instruction}]}
	if structured:
		body.generationConfig.responseMimeType = "application/json"
		var schema_value: Variant = request_data.get("schema", {})
		if schema_value is Dictionary and not schema_value.is_empty():
			body.generationConfig.responseJsonSchema = schema_value.duplicate(true)
	var endpoint: String = str(config.endpoint_override).strip_edges()
	if endpoint.is_empty():
		endpoint = DEFAULT_ENDPOINT
	endpoint = endpoint.replace("{model}", str(config.text_model).uri_encode())
	if not endpoint.begins_with("https://"):
		return AIResult.failure(PROVIDER_ID, capability, Contracts.ERROR_NOT_CONFIGURED, "The endpoint override must use HTTPS.")
	var headers := PackedStringArray([
		"Content-Type: application/json",
		"x-goog-api-key: %s" % str(config.api_key),
	])
	var http: Node = _get_http_client()
	var response_value: Variant = await http.call("send_request", endpoint, headers, body)
	if not response_value is Dictionary:
		return AIResult.failure(PROVIDER_ID, capability, Contracts.ERROR_INVALID_RESPONSE, "Gemini returned an invalid response.")
	var response: Dictionary = response_value
	if not bool(response.get("ok", false)):
		return _transport_failure(response, capability)
	var status_code: int = int(response.get("status_code", 0))
	if status_code < 200 or status_code >= 300:
		return _http_failure(status_code, capability)
	var text: String = _extract_text(response.get("data", null))
	if text.is_empty():
		return AIResult.failure(PROVIDER_ID, capability, Contracts.ERROR_INVALID_RESPONSE, "Gemini returned no usable content.")
	if not structured:
		return AIResult.success(PROVIDER_ID, capability, text)
	var json := JSON.new()
	if json.parse(text) != OK:
		return AIResult.failure(PROVIDER_ID, capability, Contracts.ERROR_INVALID_RESPONSE, "Gemini returned invalid structured output.")
	return AIResult.success(PROVIDER_ID, capability, text, json.get_data())


func _get_http_client() -> Node:
	if _http_client == null:
		_http_client = HttpClientScript.new()
		add_child(_http_client)
	return _http_client


func _validate_image_configuration(config) -> Dictionary:
	if config == null or str(config.provider_id) != PROVIDER_ID or not bool(config.enabled):
		return AIResult.failure(PROVIDER_ID, Contracts.CAPABILITY_IMAGE_GENERATION, Contracts.ERROR_NOT_CONFIGURED, "Gemini image generation is not configured.")
	if str(config.api_key).strip_edges().is_empty():
		return AIResult.failure(PROVIDER_ID, Contracts.CAPABILITY_IMAGE_GENERATION, Contracts.ERROR_NOT_CONFIGURED, "Enter a Gemini API key.")
	if str(config.image_model).strip_edges().is_empty():
		return AIResult.failure(PROVIDER_ID, Contracts.CAPABILITY_IMAGE_GENERATION, Contracts.ERROR_MODEL_UNAVAILABLE, "Select a Gemini image model.")
	return AIResult.success(PROVIDER_ID, Contracts.CAPABILITY_IMAGE_GENERATION)


func _extract_image(data: Variant) -> Dictionary:
	if not data is Dictionary:
		return {}
	var candidates: Variant = data.get("candidates", [])
	if not candidates is Array or candidates.is_empty() or not candidates[0] is Dictionary:
		return {}
	var content: Variant = candidates[0].get("content", {})
	if not content is Dictionary:
		return {}
	var parts: Variant = content.get("parts", [])
	if not parts is Array:
		return {}
	for part_value: Variant in parts:
		if not part_value is Dictionary:
			continue
		var part: Dictionary = part_value
		var inline_value: Variant = part.get("inlineData", part.get("inline_data", null))
		if not inline_value is Dictionary:
			continue
		var mime_type: String = str(inline_value.get("mimeType", inline_value.get("mime_type", "")))
		if mime_type not in ["image/png", "image/jpeg", "image/webp"]:
			continue
		var encoded: String = str(inline_value.get("data", ""))
		if encoded.is_empty():
			continue
		var bytes: PackedByteArray = Marshalls.base64_to_raw(encoded)
		if not bytes.is_empty():
			return {"bytes": bytes, "mime_type": mime_type}
	return {}


func _extract_text(data: Variant) -> String:
	if not data is Dictionary:
		return ""
	var candidates: Variant = data.get("candidates", [])
	if not candidates is Array or candidates.is_empty() or not candidates[0] is Dictionary:
		return ""
	var content: Variant = candidates[0].get("content", {})
	if not content is Dictionary:
		return ""
	var parts: Variant = content.get("parts", [])
	if not parts is Array:
		return ""
	var output := ""
	for part: Variant in parts:
		if part is Dictionary:
			output += str(part.get("text", ""))
	return output.strip_edges()


func _transport_failure(response: Dictionary, capability: String) -> Dictionary:
	var status_code: int = int(response.get("status_code", 0))
	if status_code > 0 and (status_code < 200 or status_code >= 300):
		return _http_failure(status_code, capability)
	if str(response.get("error", "")) == "json_parse_error":
		return AIResult.failure(PROVIDER_ID, capability, Contracts.ERROR_INVALID_RESPONSE, "Gemini returned an invalid response.")
	var code: int = int(response.get("code", -1))
	if code == HTTPRequest.RESULT_TIMEOUT:
		return AIResult.failure(PROVIDER_ID, capability, Contracts.ERROR_TIMEOUT, "The Gemini request timed out.")
	return AIResult.failure(PROVIDER_ID, capability, Contracts.ERROR_NETWORK_ERROR, "Could not reach Gemini.")


func _http_failure(status_code: int, capability: String) -> Dictionary:
	if status_code == 401 or status_code == 403:
		return AIResult.failure(PROVIDER_ID, capability, Contracts.ERROR_AUTH_FAILED, "Authentication failed.", "HTTP %d" % status_code)
	if status_code == 404:
		return AIResult.failure(PROVIDER_ID, capability, Contracts.ERROR_MODEL_UNAVAILABLE, "The selected model is not available.", "HTTP 404")
	if status_code == 408 or status_code == 504:
		return AIResult.failure(PROVIDER_ID, capability, Contracts.ERROR_TIMEOUT, "The Gemini request timed out.", "HTTP %d" % status_code)
	if status_code == 429:
		return AIResult.failure(PROVIDER_ID, capability, Contracts.ERROR_RATE_LIMITED, "Gemini is rate limited. Try again later.", "HTTP 429")
	return AIResult.failure(PROVIDER_ID, capability, Contracts.ERROR_PROVIDER_ERROR, "Gemini could not complete the request.", "HTTP %d" % status_code)
