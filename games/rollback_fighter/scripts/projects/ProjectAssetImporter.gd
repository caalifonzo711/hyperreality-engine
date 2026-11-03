extends RefCounted
class_name RollbackFighterProjectAssetImporter


const ProjectDefinitionScript = preload("res://games/rollback_fighter/scripts/projects/GameProjectDefinition.gd")
const IMAGE_EXTENSIONS := ["png", "jpg", "jpeg", "webp"]
const MAX_IMAGE_BYTES := 32 * 1024 * 1024
const MAX_IMAGE_DIMENSION := 8192


func import_image(project_id: String, kind: String, source_path: String) -> Dictionary:
	if not ProjectDefinitionScript.is_safe_id(project_id):
		return _failure("PROJECT_ASSET_PROJECT_INVALID", project_id, "project_id must match [a-z0-9_]+")
	if not FileAccess.file_exists("user://games/%s/project.json" % project_id):
		return _failure("PROJECT_ASSET_PROJECT_NOT_FOUND", project_id, "project must exist before importing assets")
	if kind not in ["background", "logo"]:
		return _failure("PROJECT_IMAGE_KIND_INVALID", kind, "kind must be background or logo")
	var extension := source_path.get_extension().to_lower()
	if extension not in IMAGE_EXTENSIONS:
		return _failure("PROJECT_IMAGE_TYPE_UNSUPPORTED", extension, "supported image types are PNG, JPG, and WebP")
	if not FileAccess.file_exists(source_path):
		return _failure("PROJECT_IMAGE_NOT_FOUND", source_path, "source image must exist")
	var source := FileAccess.open(source_path, FileAccess.READ)
	if source == null:
		return _failure("PROJECT_IMAGE_READ_FAILED", source_path, "source image must be readable")
	if source.get_length() <= 0 or source.get_length() > MAX_IMAGE_BYTES:
		source.close()
		return _failure("PROJECT_IMAGE_SIZE_INVALID", source_path, "image must be non-empty and no larger than 32 MiB")
	var image := Image.load_from_file(source_path)
	if image == null or image.is_empty() or image.get_width() > MAX_IMAGE_DIMENSION or image.get_height() > MAX_IMAGE_DIMENSION:
		source.close()
		return _failure("PROJECT_IMAGE_DECODE_FAILED", source_path, "image must decode and be at most 8192 pixels per side")
	var folder := "backgrounds" if kind == "background" else "branding"
	var basename := "background" if kind == "background" else "logo"
	var destination_folder := "user://games/%s/assets/%s" % [project_id, folder]
	var mkdir_error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(destination_folder))
	if mkdir_error != OK:
		return _failure("PROJECT_IMAGE_DIRECTORY_FAILED", destination_folder, "asset directory must be writable")
	_remove_variants(destination_folder, basename, IMAGE_EXTENSIONS)
	var destination := "%s/%s.%s" % [destination_folder, basename, extension]
	var bytes := source.get_buffer(source.get_length())
	source.close()
	var output := FileAccess.open(destination, FileAccess.WRITE)
	if output == null:
		return _failure("PROJECT_IMAGE_COPY_FAILED", destination, "destination must be writable under user://games")
	output.store_buffer(bytes)
	output.close()
	return {"ok": true, "path": destination, "image": image, "errors": []}


func remove_image(project_id: String, kind: String) -> bool:
	if not ProjectDefinitionScript.is_safe_id(project_id) or kind not in ["background", "logo"]:
		return false
	var folder := "backgrounds" if kind == "background" else "branding"
	var basename := "background" if kind == "background" else "logo"
	_remove_variants("user://games/%s/assets/%s" % [project_id, folder], basename, IMAGE_EXTENSIONS)
	return true


func load_texture(path: String) -> Texture2D:
	if path.is_empty() or not FileAccess.file_exists(path):
		return null
	var image := Image.load_from_file(path)
	if image == null or image.is_empty():
		return null
	return ImageTexture.create_from_image(image)


func _remove_variants(folder: String, basename: String, extensions: Array) -> void:
	for extension in extensions:
		var path := "%s/%s.%s" % [folder, basename, extension]
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _failure(code: String, value: Variant, rule: String) -> Dictionary:
	return {"ok": false, "errors": [{"code": code, "file": "presentation.json", "field": "asset", "invalid_value": value, "expected_rule": rule}]}
