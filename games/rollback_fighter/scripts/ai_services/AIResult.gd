extends RefCounted
class_name RollbackFighterAIResult

const Contracts = preload("res://games/rollback_fighter/scripts/ai_services/AIContracts.gd")


static func success(
	provider_id: String,
	capability: String,
	text_output: String = "",
	json_output: Variant = null,
	image_output: Variant = null,
	user_message: String = ""
) -> Dictionary:
	return {
		"success": true,
		"provider_id": provider_id,
		"capability": capability,
		"text_output": text_output,
		"json_output": json_output,
		"image_output": _sanitize_image_output(image_output),
		"error_code": "",
		"user_message": user_message,
		"provider_message": "",
	}


static func failure(
	provider_id: String,
	capability: String,
	error_code: String,
	user_message: String,
	provider_message: String = ""
) -> Dictionary:
	var safe_code: String = error_code
	if safe_code not in Contracts.ERROR_CODES:
		safe_code = Contracts.ERROR_PROVIDER_ERROR
	return {
		"success": false,
		"provider_id": provider_id,
		"capability": capability,
		"text_output": "",
		"json_output": null,
		"image_output": null,
		"error_code": safe_code,
		"user_message": user_message,
		"provider_message": _sanitize_message(provider_message),
	}


static func sanitize(value: Variant, provider_id: String, capability: String) -> Dictionary:
	if not value is Dictionary:
		return failure(provider_id, capability, Contracts.ERROR_INVALID_RESPONSE, "The AI provider returned an invalid response.")
	var source: Dictionary = value
	if bool(source.get("success", false)):
		return success(
			provider_id,
			capability,
			str(source.get("text_output", "")),
			source.get("json_output", null),
			source.get("image_output", null),
			str(source.get("user_message", ""))
		)
	return failure(
		provider_id,
		capability,
		str(source.get("error_code", Contracts.ERROR_PROVIDER_ERROR)),
		str(source.get("user_message", "The AI provider request failed.")),
		str(source.get("provider_message", ""))
	)


static func _sanitize_message(message: String) -> String:
	var clean: String = message.strip_edges().replace("\n", " ").replace("\r", " ")
	if clean.length() > 160:
		clean = clean.left(160)
	return clean


static func _sanitize_image_output(value: Variant) -> Variant:
	if value == null:
		return null
	if not value is Dictionary:
		return null
	var source: Dictionary = value
	var bytes_value: Variant = source.get("bytes", PackedByteArray())
	if not bytes_value is PackedByteArray:
		return null
	var image_bytes: PackedByteArray = bytes_value
	return {
		"bytes": image_bytes.duplicate(),
		"mime_type": str(source.get("mime_type", "")),
		"model_id": str(source.get("model_id", "")),
		"width": int(source.get("width", 0)),
		"height": int(source.get("height", 0)),
	}
