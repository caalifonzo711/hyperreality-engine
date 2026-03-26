extends Node
class_name GeminiClient

const GeminiHttpClient = preload("res://addons/gemini_integration/src/GeminiHttpClient.gd")
const GeminiSchemas    = preload("res://config/gemini_schemas.gd")

var _http_client: GeminiHttpClient
var _api_key: String = ""  # read from environment only

# Model + correct API VERSION from AI Studio
const GEMINI_MODEL_ID := "gemini-3-pro-preview"
const GEMINI_BASE_URL := "https://generativelanguage.googleapis.com/v1beta/models/%s:generateContent"

var _base_url: String = GEMINI_BASE_URL % GEMINI_MODEL_ID




func _ready() -> void:
	_http_client = GeminiHttpClient.new()
	add_child(_http_client)

	var env_key := OS.get_environment("GEMINI_API_KEY")
	if env_key != "":
		_api_key = env_key

	if _api_key == "":
		push_warning("GeminiClient: GEMINI_API_KEY is not set in environment. Calls will fail.")
	else:
		print("GeminiClient: API key detected (length = %d)" % _api_key.length())
		print("GeminiClient: Using model '%s' via '%s'" % [GEMINI_MODEL_ID, _base_url])


# --- PUBLIC API ---------------------------------------------------------

func generate_json_for_schema(schema_id: String, prompt: String, context: Dictionary = {}) -> Dictionary:
	if not GeminiSchemas.has_schema(schema_id):
		push_error("GeminiClient: Unknown schema_id '%s'" % schema_id)
		return { "ok": false, "error": "unknown_schema" }

	var schema: Dictionary = GeminiSchemas.get_schema(schema_id)
	_log_schema(schema_id, schema)

	var full_prompt: String = _build_schema_prompt(schema_id, schema, prompt, context)

	var response: Dictionary = await _call_gemini(full_prompt)
	if not response.get("ok", false):
		return response

	var parsed: Dictionary = _extract_json_from_response(response["data"])
	if not parsed.get("ok", false):
		return parsed

	var json_data: Dictionary = parsed["data"]
	var validated: Dictionary = _validate_required_fields(schema_id, schema, json_data)
	if not validated.get("ok", false):
		return validated

	return {
		"ok": true,
		"schema_id": schema_id,
		"data": json_data,
	}


func suggest_geometry_for_schema(schema_id: String, prompt: String, context: Dictionary = {}) -> Dictionary:
	return await generate_json_for_schema(schema_id, prompt, context)


# --- INTERNAL HELPERS --------------------------------------------------

func _build_schema_prompt(schema_id: String, schema: Dictionary, user_prompt: String, context: Dictionary) -> String:
	var description: String = str(schema.get("description", "JSON config"))
	var required_fields: Array = schema.get("required_fields", [])

	var base: String = "You are generating JSON data for schema '%s'.\n" % schema_id
	base += "Description: %s\n" % description
	base += "Return ONLY valid JSON. Do NOT include explanations.\n"
	base += "Required fields: %s\n\n" % str(required_fields)

	if context.size() > 0:
		base += "Context:\n%s\n\n" % JSON.stringify(context)

	base += "User request:\n%s\n" % user_prompt

	return base


func _call_gemini(full_prompt: String) -> Dictionary:
	if _api_key == "":
		return { "ok": false, "error": "missing_api_key" }

	var url: String = "%s?key=%s" % [_base_url, _api_key]

	var headers := PackedStringArray([
		"Content-Type: application/json"
	])

	var body: Dictionary = {
		"contents": [
			{
				"parts": [
					{ "text": full_prompt }
				]
			}
		]
	}

	var result: Dictionary = await _http_client.send_request(url, headers, body)

	var status_code := result.get("status_code", -1)
	print("GEMINI RESULT:", result)
	print("GEMINI STATUS_CODE:", status_code)

	if not result.get("ok", false):
		return {
			"ok": false,
			"error": result.get("error", "http_error"),
			"status_code": status_code,
			"raw": result,
		}

	if status_code != 200:
		return {
			"ok": false,
			"error": "http_%d" % status_code,
			"status_code": status_code,
			"raw": result.get("data"),
		}

	return result


func _extract_json_from_response(api_data: Dictionary) -> Dictionary:
	var candidates: Array = api_data.get("candidates", [])
	if candidates.is_empty():
		return { "ok": false, "error": "no_candidates", "data": api_data }

	var content: Dictionary = candidates[0].get("content", {})
	var parts: Array = content.get("parts", [])
	if parts.is_empty():
		return { "ok": false, "error": "no_parts", "data": api_data }

	var text: String = str(parts[0].get("text", ""))

	var json := JSON.new()
	var err: int = json.parse(text)
	if err != OK:
		push_error("GeminiClient: model did not return valid JSON")
		return {
			"ok": false,
			"error": "model_invalid_json",
			"raw": text,
		}

	return { "ok": true, "data": json.get_data() }


func _validate_required_fields(schema_id: String, schema: Dictionary, data: Dictionary) -> Dictionary:
	var required: Array = schema.get("required_fields", [])
	var missing: Array = []

	for field in required:
		if not data.has(field):
			missing.append(field)

	if not missing.is_empty():
		push_error("GeminiClient: schema '%s' missing fields: %s" % [schema_id, str(missing)])
		return {
			"ok": false,
			"error": "missing_fields",
			"missing": missing,
		}

	return { "ok": true, "data": data }


func _log_schema(schema_id: String, schema: Dictionary) -> void:
	print("GeminiClient: Using schema '%s' - %s" % [schema_id, schema.get("description", "")])
