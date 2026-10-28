extends Node

## Keeps the editor integration API available while avoiding any Gemini client,
## HTTP node, environment-key lookup, or network request in release builds.

var _client: Node = null


func _ready() -> void:
	if not OS.is_debug_build():
		return
	var client_script: Script = load(
		"res://addons/gemini_integration/src/GeminiClient.gd"
	) as Script
	if client_script == null:
		push_warning("[Gemini] Development client could not be loaded.")
		return
	_client = client_script.new() as Node
	add_child(_client)


func generate_json_for_schema(
	schema_id: String,
	prompt: String,
	context: Dictionary = {}
) -> Dictionary:
	if _client == null:
		return {"ok": false, "error": "gemini_disabled_in_release"}
	var result: Variant = await _client.call(
		"generate_json_for_schema", schema_id, prompt, context
	)
	if typeof(result) == TYPE_DICTIONARY:
		return result
	return {"ok": false, "error": "invalid_gemini_response"}


func suggest_geometry_for_schema(
	schema_id: String,
	prompt: String,
	context: Dictionary = {}
) -> Dictionary:
	if _client == null:
		return {"ok": false, "error": "gemini_disabled_in_release"}
	var result: Variant = await _client.call(
		"suggest_geometry_for_schema", schema_id, prompt, context
	)
	if typeof(result) == TYPE_DICTIONARY:
		return result
	return {"ok": false, "error": "invalid_gemini_response"}
