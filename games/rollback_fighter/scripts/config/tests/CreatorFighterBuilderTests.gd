extends SceneTree

const DraftScript = preload("res://games/rollback_fighter/scripts/config/CreatorFighterDraft.gd")
const ImporterScript = preload("res://games/rollback_fighter/scripts/config/CreatorArtImporter.gd")
const AlignmentScript = preload("res://games/rollback_fighter/scripts/config/CreatorPresentationDraft.gd")
const BuilderScript = preload("res://games/rollback_fighter/scripts/config/CreatorFighterBuilder.gd")
const ProviderScript = preload("res://games/rollback_fighter/scripts/config/ImportedFighterProvider.gd")
const LoaderScript = preload("res://games/rollback_fighter/scripts/config/CharacterDefinitionLoader.gd")
const WriterScript = preload("res://games/rollback_fighter/scripts/config/CanonicalConfigWriter.gd")
const TEST_ID := "creator_c4_builder_test"
const RULES_PATH := "res://games/rollback_fighter/config/game_rules.json"


func _initialize() -> void:
	var failures: PackedStringArray = PackedStringArray()
	var draft: RollbackFighterCreatorDraft = DraftScript.new()
	draft.set_identity("Creator C4 Builder Test", TEST_ID)
	var created: Dictionary = draft.create_user_draft()
	_expect(bool(created.get("ok", false)), "test draft created", failures)
	if not bool(created.get("ok", false)):
		_finish(failures)
		return
	var builder: RollbackFighterCreatorBuilder = BuilderScript.new()
	_expect(not bool(builder.build(TEST_ID).get("ok", false)), "incomplete draft cannot build", failures)
	var provider: RollbackFighterImportedFighterProvider = ProviderScript.new()
	_expect(not bool(provider.load_fighter(TEST_ID).get("ok", false)), "incomplete draft is not playable through provider", failures)
	_expect(draft.get_required_art_slot_total() == 9, "minimum built-in-mirror art set contains nine required images", failures)
	_expect(draft.get_optional_art_slot_total() > 0, "additional phase art is available as optional slots", failures)
	var source_path: String = "user://creator_c4_builder_source.png"
	var image: Image = Image.create(16, 24, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.8, 0.2, 0.25, 0.7))
	var source: FileAccess = FileAccess.open(source_path, FileAccess.WRITE)
	if source != null:
		source.store_buffer(image.save_png_to_buffer())
		source.close()
	var required_slot_ids: Array[String] = []
	var optional_slot_ids: Array[String] = []
	_collect_slot_ids(draft.slot_manifest, required_slot_ids, optional_slot_ids)
	for expected_required_id in ["idle_0", "idle_1", "jab_startup_0", "jab_active_0", "block_0", "dodge_0", "dodge_1", "hit_0", "dead_0"]:
		_expect(required_slot_ids.has(expected_required_id), "built-in minimum includes %s" % expected_required_id, failures)
	for heavy_slot_id in required_slot_ids:
		_expect(not heavy_slot_id.begins_with("heavy_"), "dedicated heavy art is never required", failures)
	for slot_id in required_slot_ids:
		var imported: Dictionary = ImporterScript.import_png(
			draft.get_user_draft_path(), TEST_ID, draft.slot_manifest, slot_id, source_path
		)
		_expect(bool(imported.get("ok", false)), "art imported for %s" % slot_id, failures)
	draft.save_art_manifests()
	var alignment: RollbackFighterCreatorPresentationDraft = AlignmentScript.new()
	_expect(alignment.configure(TEST_ID), "alignment metadata loads", failures)
	alignment.synchronize_slots(draft.slot_manifest)
	_expect(alignment.get_aligned_count(draft.slot_manifest) == required_slot_ids.size(), "all required imports are aligned from valid defaults without UI visits", failures)
	draft.set_alignment_progress(
		alignment.get_manifest_assigned_count(draft.slot_manifest),
		alignment.get_aligned_count(draft.slot_manifest)
	)
	alignment.save()
	draft.save_art_manifests()
	var ready_creator: Dictionary = _read_json(draft.get_user_draft_path() + "/creator_manifest.json")
	_expect(str(ready_creator.get("status", "")) == "alignment_complete", "valid data reaches alignment_complete without manual confirmation", failures)
	var built: Dictionary = builder.build(TEST_ID)
	_expect(bool(built.get("ok", false)), "minimum required default-aligned draft builds without alignment UI history", failures)
	_expect(draft.get_completed_required_art_slots() == 9, "minimum required progress completes at nine of nine", failures)
	_expect(draft.get_completed_optional_art_slots() == 0, "unassigned optional art does not count as incomplete required art", failures)
	var root: String = draft.get_user_draft_path()
	var creator: Dictionary = _read_json(root + "/creator_manifest.json")
	_expect(bool(creator.get("playable", false)) and str(creator.get("status", "")) == "built", "playable status is committed after successful validation", failures)
	var definition_result: Dictionary = provider.load_fighter(TEST_ID)
	_expect(bool(definition_result.get("ok", false)), "built imported fighter is provided to runtime", failures)
	var listed_ids: Array[String] = []
	for entry: Dictionary in provider.list_fighters():
		listed_ids.append(str(entry.get("id", "")))
	_expect(listed_ids.has("example_fighter"), "built-ins remain listed", failures)
	_expect(listed_ids.has(TEST_ID), "playable imported fighter is listed", failures)
	var presentation_path: String = root + "/presentation.json"
	var first_presentation_text: String = _read_text(presentation_path)
	_expect(not first_presentation_text.is_empty(), "runtime presentation.json generated", failures)
	var minimum_presentation: Dictionary = _read_json(presentation_path)
	var minimum_animations: Dictionary = minimum_presentation.get("animations", {})
	var minimum_idle_frames: Array = Dictionary(minimum_animations.get("idle", {})).get("frames", [])
	_expect(minimum_idle_frames.size() >= 2 and int(minimum_idle_frames[0].get("scale_milli", 0)) == 1000 and int(minimum_idle_frames[1].get("scale_milli", 0)) == 1000, "builder preserves valid default presentation scale", failures)
	var minimum_jab: Dictionary = minimum_animations.get("jab", {})
	var minimum_heavy: Dictionary = minimum_animations.get("heavy", {})
	var minimum_jab_frames: Array = minimum_jab.get("frames", [])
	var minimum_heavy_frames: Array = minimum_heavy.get("frames", [])
	_expect(minimum_jab_frames == minimum_heavy_frames, "heavy falls back to the exact jab/light presentation when no heavy art is assigned", failures)
	var minimum_phase_map: Dictionary = minimum_presentation.get("attack_phase_to_frames", {})
	_expect(minimum_phase_map.get("jab", {}) == minimum_phase_map.get("heavy", {}), "heavy fallback mirrors light attack phase-frame mapping", failures)
	var jab_phase_map: Dictionary = minimum_phase_map.get("jab", {})
	_expect(
		_phase_has_frame(jab_phase_map, "startup", 0)
		and _phase_has_frame(jab_phase_map, "active", 1)
		and _phase_has_frame(jab_phase_map, "recovery", 0),
		"minimum jab presentation mirrors built-in startup/active/recovery frame mapping",
		failures
	)
	_expect(not minimum_jab_frames.is_empty(), "minimum presentation contains loadable attack texture frames", failures)
	var corrupt_file: FileAccess = FileAccess.open(presentation_path, FileAccess.WRITE)
	if corrupt_file != null:
		corrupt_file.store_string("{broken")
		corrupt_file.close()
	_expect(not bool(provider.load_fighter(TEST_ID).get("ok", false)), "corrupt imported fighter fails validation safely", failures)
	var after_corrupt_ids: Array[String] = []
	for entry: Dictionary in provider.list_fighters():
		after_corrupt_ids.append(str(entry.get("id", "")))
	_expect(not after_corrupt_ids.has(TEST_ID), "corrupt imported fighter is skipped in select enumeration", failures)
	var restored_presentation: FileAccess = FileAccess.open(presentation_path, FileAccess.WRITE)
	if restored_presentation != null:
		restored_presentation.store_string(first_presentation_text)
		restored_presentation.close()
	_expect(bool(builder.build(TEST_ID).get("ok", false)), "rebuilding the same draft succeeds", failures)
	_expect(first_presentation_text == _read_text(presentation_path), "rebuild output is deterministic", failures)
	var optional_heavy_slot: String = ""
	for slot_id in optional_slot_ids:
		if slot_id.begins_with("heavy_"):
			optional_heavy_slot = slot_id
			break
	_expect(not optional_heavy_slot.is_empty(), "optional dedicated heavy slot exists", failures)
	if not optional_heavy_slot.is_empty():
		var optional_import: Dictionary = ImporterScript.import_png(
			draft.get_user_draft_path(), TEST_ID, draft.slot_manifest, optional_heavy_slot, source_path
		)
		_expect(bool(optional_import.get("ok", false)), "optional heavy art imports", failures)
		_expect(bool(draft.save_art_manifests().get("ok", false)), "optional art assignment persists before runtime build", failures)
		alignment.synchronize_slots(draft.slot_manifest)
		_expect(alignment.is_slot_alignment_valid(optional_heavy_slot), "assigned optional art with valid defaults is aligned automatically", failures)
		alignment.slots[optional_heavy_slot]["scale_milli"] = 49
		alignment.slots[optional_heavy_slot]["status"] = "aligned"
		alignment.save()
		var invalid_scale_build: Dictionary = builder.build(TEST_ID)
		_expect(not bool(invalid_scale_build.get("ok", false)), "assigned optional art with invalid scale blocks build", failures)
		_expect(bool(alignment.save_alignment(optional_heavy_slot, 8, 24, 1000).get("ok", false)), "fixing optional scale restores valid metadata", failures)
		var invalid_anchor: Dictionary = alignment.save_alignment(optional_heavy_slot, 99999, 24, 1000)
		_expect(not bool(invalid_anchor.get("ok", false)), "invalid optional anchor is rejected", failures)
		alignment.save()
		var invalid_anchor_build: Dictionary = builder.build(TEST_ID)
		_expect(not bool(invalid_anchor_build.get("ok", false)), "assigned optional art with invalid anchor blocks build", failures)
		_expect(bool(alignment.save_alignment(optional_heavy_slot, 8, 24, 1000).get("ok", false)), "fixing optional anchor restores build readiness", failures)
		alignment.save()
		draft.set_alignment_progress(
			alignment.get_manifest_assigned_count(draft.slot_manifest),
			alignment.get_aligned_count(draft.slot_manifest)
		)
		draft.save_art_manifests()
		var optional_built: Dictionary = builder.build(TEST_ID)
		_expect(bool(optional_built.get("ok", false)), "required art plus aligned assigned optional art builds", failures)
		var optional_presentation: Dictionary = _read_json(presentation_path)
		var optional_anims: Dictionary = optional_presentation.get("animations", {})
		var optional_heavy: Dictionary = optional_anims.get("heavy", {})
		var optional_frames: Array = optional_heavy.get("frames", [])
		var found_dedicated_heavy: bool = false
		for frame_value in optional_frames:
			if frame_value is Dictionary and str(frame_value.get("sprite", "")).ends_with("/%s.png" % optional_heavy_slot):
				found_dedicated_heavy = true
		_expect(found_dedicated_heavy, "assigned optional heavy art overrides the light-art fallback", failures)
	if bool(definition_result.get("ok", false)):
		var loader: RollbackFighterCharacterDefinitionLoader = LoaderScript.new()
		var rules_result: Dictionary = loader.load_game_rules(RULES_PATH)
		if bool(rules_result.get("ok", false)):
			var writer: RollbackFighterCanonicalConfigWriter = WriterScript.new()
			var before: String = writer.sha256_hex(writer.character_bytes(rules_result["definition"], definition_result["definition"]))
			var generated: Dictionary = _read_json(presentation_path)
			var idle: Dictionary = generated["animations"]["idle"]
			var first_frame: Dictionary = idle["frames"][0]
			first_frame["scale_milli"] = 1250
			_write_json(presentation_path, generated)
			var after_result: Dictionary = provider.load_fighter(TEST_ID)
			if bool(after_result.get("ok", false)):
				var after: String = writer.sha256_hex(writer.character_bytes(rules_result["definition"], after_result["definition"]))
				_expect(before == after, "presentation changes stay outside authoritative digest", failures)
			else:
				_expect(false, "fighter reloads after presentation-only edit", failures)
		else:
			_expect(false, "shared game rules load for digest check", failures)
	_cleanup(root, source_path)
	_finish(failures)


func _collect_slot_ids(value: Variant, required: Array[String], optional: Array[String]) -> void:
	if value is Dictionary:
		var item: Dictionary = value
		if item.has("slot"):
			if bool(item.get("required", false)):
				required.append(str(item["slot"]))
			else:
				optional.append(str(item["slot"]))
		for child in item.values():
			_collect_slot_ids(child, required, optional)
	elif value is Array:
		for child in value:
			_collect_slot_ids(child, required, optional)


func _phase_has_frame(phase_map: Dictionary, phase: String, expected_frame: int) -> bool:
	var frames: Variant = phase_map.get(phase, [])
	return frames is Array and frames.size() == 1 and typeof(frames[0]) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(frames[0])) and float(frames[0]) == float(expected_frame)


func _read_json(path: String) -> Dictionary:
	var text: String = _read_text(path)
	var parsed: Variant = JSON.parse_string(text) if not text.is_empty() else null
	return parsed if parsed is Dictionary else {}


func _read_text(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var text: String = file.get_as_text()
	file.close()
	return text


func _write_json(path: String, document: Dictionary) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(document, "\t", false) + "\n")
		file.close()


func _cleanup(root: String, source_path: String) -> void:
	if FileAccess.file_exists(source_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(source_path))
	for path in [root + "/sprites", root + "/moves", root + "/hitboxes"]:
		var dir: DirAccess = DirAccess.open(path)
		if dir == null:
			continue
		dir.list_dir_begin()
		var name: String = dir.get_next()
		while not name.is_empty():
			if not dir.current_is_dir():
				DirAccess.remove_absolute(ProjectSettings.globalize_path(path + "/" + name))
			name = dir.get_next()
		dir.list_dir_end()
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	for name in ["character.json", "creator_manifest.json", "slot_manifest.json", "presentation_draft.json", "presentation.json"]:
		var path: String = root + "/" + name
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(root))


func _expect(condition: bool, message: String, failures: PackedStringArray) -> void:
	if not condition:
		failures.append(message)


func _finish(failures: PackedStringArray) -> void:
	if failures.is_empty():
		print("[CreatorFighterBuilderTests] PASS")
		quit(0)
		return
	for failure in failures:
		printerr("[CreatorFighterBuilderTests] FAIL: %s" % failure)
	quit(1)
