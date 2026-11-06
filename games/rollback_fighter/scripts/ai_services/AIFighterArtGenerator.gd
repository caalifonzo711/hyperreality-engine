extends RefCounted
class_name RollbackFighterAIFighterArtGenerator

const Contracts = preload("res://games/rollback_fighter/scripts/ai_services/AIContracts.gd")
const PromptBuilderScript = preload("res://games/rollback_fighter/scripts/ai_services/FighterArtPromptBuilder.gd")
const ArtImporter = preload("res://games/rollback_fighter/scripts/config/CreatorArtImporter.gd")


func generate_slot(ai_service: Node, draft, alignment_draft, slot_id: String) -> Dictionary:
	if ai_service == null:
		return _failure(Contracts.ERROR_NOT_CONFIGURED, "AI assistance is unavailable.")
	if not bool(ai_service.call("supports", Contracts.CAPABILITY_IMAGE_GENERATION)):
		return _failure(Contracts.ERROR_UNSUPPORTED_CAPABILITY, "Current AI provider does not support image generation.")
	var prompt_builder = PromptBuilderScript.new()
	var request = prompt_builder.build_request(draft, slot_id)
	if request == null:
		return _failure(Contracts.ERROR_INVALID_RESPONSE, "The selected fighter art slot is invalid.")
	var ai_value: Variant = await ai_service.call("generate_image", request)
	if not ai_value is Dictionary:
		return _failure(Contracts.ERROR_INVALID_RESPONSE, "The AI provider returned an invalid image response.")
	var ai_result: Dictionary = ai_value
	if not bool(ai_result.get("success", false)):
		return ai_result
	var image_result: Dictionary = _decode_image(ai_result.get("image_output", null))
	if not bool(image_result.get("ok", false)):
		return image_result
	var create_result: Dictionary = draft.create_user_draft()
	if not bool(create_result.get("ok", false)):
		return {"success": false, "error_code": "DRAFT_WRITE_FAILED", "user_message": "The fighter draft could not be prepared for generated art.", "errors": create_result.get("errors", [])}
	var temp_path: String = "%s/.ai_temp/%s_%d.png" % [draft.get_user_draft_path(), slot_id, Time.get_ticks_usec()]
	var directory_error: Error = DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(temp_path.get_base_dir()))
	if directory_error != OK:
		return _failure("IMAGE_WRITE_FAILED", "The generated image could not be staged safely.")
	var image: Image = image_result.image
	var save_error: Error = image.save_png(temp_path)
	if save_error != OK:
		return _failure("IMAGE_WRITE_FAILED", "The generated image could not be staged safely.")
	var import_result: Dictionary = ArtImporter.import_png(
		draft.get_user_draft_path(), draft.fighter_id, draft.slot_manifest, slot_id, temp_path
	)
	_remove_temp(temp_path)
	if not bool(import_result.get("ok", false)):
		return {"success": false, "error_code": "INVALID_RESPONSE", "user_message": "The generated image did not pass creator image validation.", "errors": import_result.get("errors", [])}
	var relative_path: String = "sprites/%s.png" % slot_id
	if not alignment_draft.mark_replaced(slot_id, relative_path, int(import_result.width), int(import_result.height)):
		return _failure("ALIGNMENT_FAILED", "The generated image could not receive default alignment.")
	var slot: Dictionary = prompt_builder.find_slot_context(draft.slot_manifest, slot_id).get("slot", {})
	slot["generation_provenance"] = {
		"generated_by_ai": true,
		"provider_id": str(ai_result.get("provider_id", "")),
		"model_id": str(Dictionary(ai_result.get("image_output", {})).get("model_id", "")),
		"generated_at": int(Time.get_unix_time_from_system()),
	}
	var manifest_result: Dictionary = draft.save_art_manifests()
	if not bool(manifest_result.get("ok", false)):
		return _failure("DRAFT_WRITE_FAILED", "Generated art was imported, but creator metadata could not be saved.")
	var alignment_result: Dictionary = alignment_draft.save()
	if not bool(alignment_result.get("ok", false)):
		return _failure("ALIGNMENT_FAILED", "Generated art was imported, but its default alignment could not be saved.")
	return {
		"success": true,
		"error_code": "",
		"user_message": "%s generated and imported." % slot_id,
		"path": str(import_result.path),
		"width": int(import_result.width),
		"height": int(import_result.height),
		"reference_count": request.reference_images.size(),
	}


func _decode_image(output_value: Variant) -> Dictionary:
	if not output_value is Dictionary:
		return _failure(Contracts.ERROR_INVALID_RESPONSE, "The AI provider returned no image data.")
	var output: Dictionary = output_value
	var bytes_value: Variant = output.get("bytes", PackedByteArray())
	if not bytes_value is PackedByteArray:
		return _failure(Contracts.ERROR_INVALID_RESPONSE, "The AI provider returned malformed image data.")
	var bytes: PackedByteArray = bytes_value
	if bytes.is_empty() or bytes.size() > ArtImporter.MAX_FILE_BYTES:
		return _failure(Contracts.ERROR_INVALID_RESPONSE, "The generated image has an invalid file size.")
	var mime_type: String = str(output.get("mime_type", ""))
	var image := Image.new()
	var decode_error: Error = ERR_FILE_UNRECOGNIZED
	match mime_type:
		"image/png":
			decode_error = image.load_png_from_buffer(bytes)
		"image/jpeg":
			decode_error = image.load_jpg_from_buffer(bytes)
		"image/webp":
			decode_error = image.load_webp_from_buffer(bytes)
		_:
			return _failure(Contracts.ERROR_INVALID_RESPONSE, "The AI provider returned an unsupported image type.")
	if decode_error != OK or image.is_empty():
		return _failure(Contracts.ERROR_INVALID_RESPONSE, "The generated image could not be decoded.")
	var width: int = image.get_width()
	var height: int = image.get_height()
	if width <= 0 or height <= 0 or width > ArtImporter.MAX_DIMENSION or height > ArtImporter.MAX_DIMENSION or width * height > ArtImporter.MAX_PIXELS:
		return _failure(Contracts.ERROR_INVALID_RESPONSE, "The generated image dimensions are outside creator limits.")
	return {"ok": true, "success": true, "image": image, "width": width, "height": height}


func _remove_temp(path: String) -> void:
	if path.begins_with("user://characters/") and path.contains("/.ai_temp/") and FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _failure(code: String, message: String) -> Dictionary:
	return {"ok": false, "success": false, "error_code": code, "user_message": message, "errors": [message]}
