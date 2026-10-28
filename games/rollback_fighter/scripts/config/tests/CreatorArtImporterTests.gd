extends SceneTree


const DraftScript = preload("res://games/rollback_fighter/scripts/config/CreatorFighterDraft.gd")
const Importer = preload("res://games/rollback_fighter/scripts/config/CreatorArtImporter.gd")
const TEST_ID := "creator_art_import_test"


func _initialize() -> void:
	var failures: PackedStringArray = PackedStringArray()
	var draft: RollbackFighterCreatorDraft = DraftScript.new()
	draft.set_identity("Creator Art Import Test", TEST_ID)
	var created: Dictionary = draft.create_user_draft()
	_expect(bool(created.get("ok", false)), "test draft can be created", failures)
	if not bool(created.get("ok", false)):
		_finish(failures)
		return

	var source_path: String = "user://creator_art_source.png"
	var source_two: String = "user://creator_art_source_two.png"
	var invalid_path: String = "user://creator_art_invalid.txt"
	var corrupt_png_path: String = "user://creator_art_corrupt.png"
	var oversized_path: String = "user://creator_art_oversized.png"
	var oversized_file_path: String = "user://creator_art_oversized_file.png"
	var first_bytes: PackedByteArray = _write_test_png(source_path, Color(0.2, 0.4, 0.8, 0.0), Vector2i(8, 8))
	var second_bytes: PackedByteArray = _write_test_png(source_two, Color(0.8, 0.2, 0.1, 1.0), Vector2i(8, 8))
	FileAccess.open(invalid_path, FileAccess.WRITE).store_string("not an image")
	FileAccess.open(corrupt_png_path, FileAccess.WRITE).store_string("not a PNG")
	_write_test_png(oversized_path, Color.WHITE, Vector2i(4097, 1))
	var oversized_file: FileAccess = FileAccess.open(oversized_file_path, FileAccess.WRITE)
	if oversized_file != null:
		var oversized_bytes: PackedByteArray = PackedByteArray()
		oversized_bytes.resize(16 * 1024 * 1024 + 1)
		oversized_file.store_buffer(oversized_bytes)
		oversized_file.close()

	var slots: Dictionary = draft.slot_manifest
	var root: String = draft.get_user_draft_path()
	var valid_result: Dictionary = Importer.import_png(root, TEST_ID, slots, "idle_0", source_path)
	_expect(bool(valid_result.get("ok", false)), "valid PNG imports", failures)
	_expect(str(valid_result.get("path", "")).ends_with("/sprites/idle_0.png"), "slot ID determines safe filename", failures)
	_expect(FileAccess.get_file_as_bytes(source_path) == first_bytes, "external source remains untouched", failures)
	_expect(FileAccess.file_exists(root + "/sprites/idle_0.png"), "copy remains inside draft-owned sprites directory", failures)
	var imported_image: Image = Image.new()
	var imported_image_bytes: PackedByteArray = FileAccess.get_file_as_bytes(root + "/sprites/idle_0.png")
	_expect(imported_image.load_png_from_buffer(imported_image_bytes) == OK and is_zero_approx(imported_image.get_pixel(0, 0).a), "PNG transparency is preserved", failures)
	_expect(draft.get_completed_required_art_slots() == 1, "required-slot progress increments", failures)
	var saved_result: Dictionary = draft.save_art_manifests()
	_expect(bool(saved_result.get("ok", false)), "assignment manifest persists", failures)
	var saved_json: JSON = JSON.new()
	var saved_file: FileAccess = FileAccess.open(root + "/slot_manifest.json", FileAccess.READ)
	if saved_file != null:
		var saved_text: String = saved_file.get_as_text()
		_expect(saved_json.parse(saved_text) == OK, "saved manifest is valid JSON", failures)
		_expect(saved_text.contains("sprites/idle_0.png"), "manifest stores draft-relative assigned path", failures)
		saved_file.close()
	else:
		_expect(false, "saved manifest can be read", failures)

	var bad_extension: Dictionary = Importer.import_png(root, TEST_ID, slots, "idle_1", invalid_path)
	_expect(not bool(bad_extension.get("ok", false)), "non-PNG extension is rejected", failures)
	var corrupt: Dictionary = Importer.import_png(root, TEST_ID, slots, "idle_1", corrupt_png_path)
	_expect(not bool(corrupt.get("ok", false)), "corrupt PNG is rejected", failures)
	var oversized: Dictionary = Importer.import_png(root, TEST_ID, slots, "idle_1", oversized_path)
	_expect(not bool(oversized.get("ok", false)), "oversized dimensions are rejected", failures)
	var oversized_file_result: Dictionary = Importer.import_png(root, TEST_ID, slots, "idle_1", oversized_file_path)
	_expect(not bool(oversized_file_result.get("ok", false)), "oversized file is rejected before decode", failures)
	var traversal: Dictionary = Importer.import_png(root, TEST_ID, slots, "../idle_1", source_path)
	_expect(not bool(traversal.get("ok", false)), "slot path traversal is rejected", failures)
	var invalid_root: Dictionary = Importer.import_png("user://characters/other", TEST_ID, slots, "idle_1", source_path)
	_expect(not bool(invalid_root.get("ok", false)), "destination override is rejected", failures)

	var replace_result: Dictionary = Importer.import_png(root, TEST_ID, slots, "idle_0", source_two)
	_expect(bool(replace_result.get("ok", false)), "replacement succeeds", failures)
	_expect(FileAccess.get_file_as_bytes(root + "/sprites/idle_0.png") == second_bytes, "replacement affects target slot only", failures)
	_expect(FileAccess.get_file_as_bytes(source_path) == first_bytes, "replacement leaves original source untouched", failures)
	var second_slot: Dictionary = Importer.import_png(root, TEST_ID, slots, "idle_1", source_path)
	_expect(bool(second_slot.get("ok", false)), "second slot can be independently assigned", failures)
	var all_slot_ids: PackedStringArray = PackedStringArray()
	_collect_slot_ids(draft.slot_manifest, all_slot_ids)
	for slot_id in all_slot_ids:
		if not bool(Importer._find_slot(draft.slot_manifest, slot_id).get("assigned", false)):
			var fill_result: Dictionary = Importer.import_png(root, TEST_ID, slots, slot_id, source_path)
			_expect(bool(fill_result.get("ok", false)), "required slot can be filled: %s" % slot_id, failures)
	_expect(draft.get_completed_required_art_slots() == draft.get_required_art_slot_total(), "progress reaches all required slots", failures)
	_expect(bool(draft.save_art_manifests().get("ok", false)), "complete art status persists", failures)
	var complete_manifest: String = FileAccess.get_file_as_string(root + "/creator_manifest.json")
	_expect(complete_manifest.contains("art_complete") and complete_manifest.contains("\"playable\": false"), "all-art-complete draft remains non-playable", failures)
	var remove_result: Dictionary = Importer.remove_slot(root, TEST_ID, slots, "idle_0")
	_expect(bool(remove_result.get("ok", false)), "assigned slot can be removed", failures)
	_expect(not FileAccess.file_exists(root + "/sprites/idle_0.png"), "remove deletes only target draft asset", failures)
	_expect(FileAccess.file_exists(root + "/sprites/idle_1.png"), "remove preserves other assigned slot", failures)
	_expect(
		draft.get_completed_required_art_slots() == draft.get_required_art_slot_total() - 1,
		"progress reflects removal as eight of nine required slots",
		failures
	)
	_expect(bool(draft.save_art_manifests().get("ok", false)), "removal state persists", failures)
	var manifest_text: String = FileAccess.get_file_as_string(root + "/creator_manifest.json")
	_expect(
		manifest_text.contains("art_incomplete")
		and manifest_text.contains("\"completed_required_art_slots\": 8")
		and manifest_text.contains("\"required_art_slots\": 9")
		and manifest_text.contains("\"playable\": false"),
		"creator status remains non-playable and reports eight of nine required slots",
		failures
	)

	_cleanup(root, [source_path, source_two, invalid_path, corrupt_png_path, oversized_path, oversized_file_path])
	_finish(failures)


func _write_test_png(path: String, color: Color, dimensions: Vector2i) -> PackedByteArray:
	var image: Image = Image.create(dimensions.x, dimensions.y, false, Image.FORMAT_RGBA8)
	image.fill(color)
	var bytes: PackedByteArray = image.save_png_to_buffer()
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_buffer(bytes)
		file.close()
	return bytes


func _cleanup(root: String, files: Array[String]) -> void:
	for file_path in files:
		if FileAccess.file_exists(file_path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(file_path))
	var sprite_dir: DirAccess = DirAccess.open(root + "/sprites")
	if sprite_dir != null:
		sprite_dir.list_dir_begin()
		var sprite_name: String = sprite_dir.get_next()
		while not sprite_name.is_empty():
			if not sprite_dir.current_is_dir():
				DirAccess.remove_absolute(ProjectSettings.globalize_path(root + "/sprites/" + sprite_name))
			sprite_name = sprite_dir.get_next()
		sprite_dir.list_dir_end()
	for file_path in [root + "/character.json", root + "/creator_manifest.json", root + "/slot_manifest.json", root + "/moves/jab.json", root + "/moves/heavy.json", root + "/hitboxes/jab.json", root + "/hitboxes/heavy.json"]:
		if FileAccess.file_exists(file_path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(file_path))
	for folder_path in [root + "/sprites", root + "/moves", root + "/hitboxes", root]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(folder_path))


func _expect(condition: bool, message: String, failures: PackedStringArray) -> void:
	if not condition:
		failures.append(message)


func _finish(failures: PackedStringArray) -> void:
	if failures.is_empty():
		print("[CreatorArtImporterTests] PASS")
		quit(0)
		return
	for failure in failures:
		printerr("[CreatorArtImporterTests] FAIL: %s" % failure)
	quit(1)


func _collect_slot_ids(value: Variant, output: PackedStringArray) -> void:
	if value is Dictionary:
		var item: Dictionary = value
		if item.has("slot"):
			output.append(str(item.get("slot", "")))
		else:
			for child in item.values():
				_collect_slot_ids(child, output)
	elif value is Array:
		for child in value:
			_collect_slot_ids(child, output)
