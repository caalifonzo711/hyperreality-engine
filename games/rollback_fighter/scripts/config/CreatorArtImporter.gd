extends RefCounted
class_name RollbackFighterCreatorArtImporter

const MAX_FILE_BYTES: int = 16 * 1024 * 1024
const MAX_DIMENSION: int = 4096
const MAX_PIXELS: int = 16777216


static func import_png(draft_root: String, fighter_id: String, slot_manifest: Dictionary, slot_id: String, source_path: String) -> Dictionary:
	if not _is_safe_id(fighter_id) or not _is_safe_slot_id(slot_id):
		return _failure("CREATOR_ART_SLOT_INVALID", slot_id, "slot must be an existing canonical ID using [a-z0-9_]+")
	if draft_root != "user://characters/%s" % fighter_id:
		return _failure("CREATOR_ART_DESTINATION_INVALID", draft_root, "destination must remain inside this fighter's user://characters draft")
	var slot: Dictionary = _find_slot(slot_manifest, slot_id)
	if slot.is_empty():
		return _failure("CREATOR_ART_SLOT_UNKNOWN", slot_id, "slot ID must exist in slot_manifest.json")
	if not source_path.begins_with("content://"):
		var extension: String = source_path.get_extension().to_lower()
		if extension != "png":
			return _failure("CREATOR_ART_TYPE_INVALID", extension, "select a PNG image")
	var file: FileAccess = FileAccess.open(source_path, FileAccess.READ)
	if file == null:
		return _failure("CREATOR_ART_READ_FAILED", source_path, "selected image must be readable")
	var byte_count: int = file.get_length()
	if byte_count <= 0 or byte_count > MAX_FILE_BYTES:
		file.close()
		return _failure("CREATOR_ART_SIZE_INVALID", byte_count, "PNG must be between 1 byte and 16 MiB")
	var bytes: PackedByteArray = file.get_buffer(byte_count)
	file.close()
	var png_signature: PackedByteArray = PackedByteArray([137, 80, 78, 71, 13, 10, 26, 10])
	if bytes.size() != byte_count or bytes.size() < png_signature.size():
		return _failure("CREATOR_ART_READ_FAILED", bytes.size(), "selected PNG must be completely readable")
	for index in png_signature.size():
		if bytes[index] != png_signature[index]:
			return _failure("CREATOR_ART_TYPE_INVALID", source_path, "file contents must have the PNG signature")
	var image: Image = Image.new()
	var decode_error: Error = image.load_png_from_buffer(bytes)
	if decode_error != OK or image.is_empty():
		return _failure("CREATOR_ART_DECODE_FAILED", source_path, "selected file must decode as PNG")
	var width: int = image.get_width()
	var height: int = image.get_height()
	if width <= 0 or height <= 0 or width > MAX_DIMENSION or height > MAX_DIMENSION or width * height > MAX_PIXELS:
		return _failure("CREATOR_ART_DIMENSIONS_INVALID", "%dx%d" % [width, height], "dimensions must be positive, at most 4096x4096, and at most 16 megapixels")
	var destination: String = "%s/sprites/%s.png" % [draft_root, slot_id]
	var dir_error: Error = DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(draft_root + "/sprites"))
	if dir_error != OK:
		return _failure("CREATOR_ART_DIRECTORY_FAILED", dir_error, "draft sprites directory must be writable")
	var output: FileAccess = FileAccess.open(destination, FileAccess.WRITE)
	if output == null:
		return _failure("CREATOR_ART_WRITE_FAILED", FileAccess.get_open_error(), "draft-owned sprite path must be writable")
	output.store_buffer(bytes)
	output.flush()
	var write_error: Error = output.get_error()
	output.close()
	if write_error != OK:
		return _failure("CREATOR_ART_WRITE_FAILED", write_error, "PNG must be fully written to the draft")
	var display_name: String = source_path.get_file()
	if source_path.begins_with("content://"):
		display_name = "Selected PNG"
	slot["assigned"] = true
	slot["path"] = "sprites/%s.png" % slot_id
	slot["display_filename"] = display_name
	slot["width"] = width
	slot["height"] = height
	# Manual imports clear prior AI provenance. The AI generation coordinator
	# adds fresh provenance only after this same importer succeeds.
	slot.erase("generation_provenance")
	return {"ok": true, "path": destination, "width": width, "height": height, "bytes": byte_count}


static func remove_slot(draft_root: String, fighter_id: String, slot_manifest: Dictionary, slot_id: String) -> Dictionary:
	if not _is_safe_id(fighter_id) or not _is_safe_slot_id(slot_id):
		return _failure("CREATOR_ART_SLOT_INVALID", slot_id, "slot must be an existing canonical ID using [a-z0-9_]+")
	if draft_root != "user://characters/%s" % fighter_id:
		return _failure("CREATOR_ART_DESTINATION_INVALID", draft_root, "removal is restricted to this fighter's user:// draft")
	var slot: Dictionary = _find_slot(slot_manifest, slot_id)
	if slot.is_empty():
		return _failure("CREATOR_ART_SLOT_UNKNOWN", slot_id, "slot ID must exist in slot_manifest.json")
	var destination: String = "%s/sprites/%s.png" % [draft_root, slot_id]
	var absolute_destination: String = ProjectSettings.globalize_path(destination)
	if FileAccess.file_exists(destination):
		var remove_error: Error = DirAccess.remove_absolute(absolute_destination)
		if remove_error != OK:
			return _failure("CREATOR_ART_REMOVE_FAILED", remove_error, "only the selected slot's draft-owned PNG must be removable")
	slot["assigned"] = false
	slot.erase("path")
	slot.erase("display_filename")
	slot.erase("width")
	slot.erase("height")
	slot.erase("generation_provenance")
	return {"ok": true}


static func load_thumbnail(draft_root: String, slot_id: String, max_size: Vector2i = Vector2i(160, 160)) -> Texture2D:
	if not _is_safe_slot_id(slot_id):
		return null
	var image_path: String = "%s/sprites/%s.png" % [draft_root, slot_id]
	if not FileAccess.file_exists(image_path):
		return null
	var image: Image = Image.new()
	if image.load(image_path) != OK or image.is_empty():
		return null
	var preview: Image = image.duplicate()
	preview.resize(max_size.x, max_size.y, Image.INTERPOLATE_LANCZOS)
	return ImageTexture.create_from_image(preview)


static func _find_slot(value: Variant, slot_id: String) -> Dictionary:
	if value is Dictionary:
		var dictionary: Dictionary = value
		if str(dictionary.get("slot", "")) == slot_id:
			return dictionary
		for child in dictionary.values():
			var found: Dictionary = _find_slot(child, slot_id)
			if not found.is_empty():
				return found
	elif value is Array:
		for child in value:
			var found: Dictionary = _find_slot(child, slot_id)
			if not found.is_empty():
				return found
	return {}


static func _is_safe_id(value: String) -> bool:
	return _is_safe_slot_id(value)


static func _is_safe_slot_id(value: String) -> bool:
	if value.is_empty():
		return false
	for index in value.length():
		var code: int = value.unicode_at(index)
		if not ((code >= 97 and code <= 122) or (code >= 48 and code <= 57) or code == 95):
			return false
	return true


static func _failure(code: String, value: Variant, rule: String) -> Dictionary:
	return {"ok": false, "errors": [{"code": code, "file": "<selected-image>", "field": "image", "invalid_value": value, "expected_rule": rule}]}
