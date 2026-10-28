extends SceneTree


const DraftScript = preload("res://games/rollback_fighter/scripts/config/CreatorFighterDraft.gd")
const PresentationDraftScript = preload("res://games/rollback_fighter/scripts/config/CreatorPresentationDraft.gd")
const Importer = preload("res://games/rollback_fighter/scripts/config/CreatorArtImporter.gd")
const LoaderScript = preload("res://games/rollback_fighter/scripts/config/CharacterDefinitionLoader.gd")
const CanonicalWriterScript = preload("res://games/rollback_fighter/scripts/config/CanonicalConfigWriter.gd")
const TEST_ID := "creator_presentation_test"
const RULES_PATH := "res://games/rollback_fighter/config/game_rules.json"
const REGISTRY_PATH := "res://games/rollback_fighter/config/builtin_fighters.json"


func _initialize() -> void:
	var failures: PackedStringArray = PackedStringArray()
	var draft: RollbackFighterCreatorDraft = DraftScript.new()
	draft.set_identity("Creator Presentation Test", TEST_ID)
	var create_result: Dictionary = draft.create_user_draft()
	_expect(bool(create_result.get("ok", false)), "isolated creator draft is writable", failures)
	if not bool(create_result.get("ok", false)):
		_finish(failures)
		return

	var source_path: String = "user://creator_presentation_source.png"
	var image: Image = Image.create(20, 30, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.2, 0.7, 0.3, 0.5))
	var source_bytes: PackedByteArray = image.save_png_to_buffer()
	var source_file: FileAccess = FileAccess.open(source_path, FileAccess.WRITE)
	if source_file != null:
		source_file.store_buffer(source_bytes)
		source_file.close()
	var root: String = draft.get_user_draft_path()
	var slot_ids: PackedStringArray = PackedStringArray(["idle_0", "idle_1", "jab_startup_0", "jab_active_0"])
	for slot_id in slot_ids:
		var import_result: Dictionary = Importer.import_png(root, TEST_ID, draft.slot_manifest, slot_id, source_path)
		_expect(bool(import_result.get("ok", false)), "test art assigned to %s" % slot_id, failures)

	var alignment: RollbackFighterCreatorPresentationDraft = PresentationDraftScript.new()
	_expect(alignment.configure(TEST_ID), "presentation draft configures", failures)
	var idle_group: Array = draft.slot_manifest["animations"]["idle"]
	idle_group[0]["width"] = 9999
	idle_group[0]["height"] = 9999
	alignment.synchronize_slots(draft.slot_manifest)
	var first: Dictionary = alignment.get_slot("idle_0")
	_expect(first.get("feet_anchor", []) == [10, 30], "new sprite defaults to bottom-center anchor", failures)
	_expect(int(first.get("scale_milli", 0)) == 1000, "new sprite defaults to 100% scale", failures)
	_expect(str(first.get("status", "")) == "aligned", "valid imported sprite defaults count as aligned", failures)
	_expect(alignment.get_aligned_count(draft.slot_manifest) == 4, "valid defaults are build-ready without UI visits", failures)
	for slot_id in slot_ids:
		_expect(FileAccess.get_file_as_bytes(root + "/sprites/%s.png" % slot_id) == source_bytes, "duplicate source art is allowed for %s" % slot_id, failures)
	_expect(not str(first.get("path", "")).begins_with("res://") and str(first.get("path", "")).begins_with("sprites/"), "presentation path is draft-relative", failures)
	_expect(PresentationDraftScript.calculate_auto_fit_scale(100.0, 100) == 1000, "same visible height auto-fits to 1000", failures)
	_expect(PresentationDraftScript.calculate_auto_fit_scale(100.0, 200) == 500, "2x taller art auto-fits to 500", failures)
	_expect(PresentationDraftScript.calculate_auto_fit_scale(100.0, 50) == 2000, "half-height art auto-fits to 2000", failures)
	_expect(PresentationDraftScript.calculate_auto_fit_scale(100.0, 10000) == 50, "below-minimum calculation clamps to 50", failures)
	_expect(PresentationDraftScript.calculate_auto_fit_scale(100.0, 1) == 4000, "above-maximum calculation clamps to 4000", failures)
	_expect(PresentationDraftScript.calculate_auto_fit_scale(48.06, 483) == 100, "Red Girl-sized alpha bounds auto-fit to approximately 100 without special-casing", failures)
	var padded_image: Image = Image.create(12, 20, false, Image.FORMAT_RGBA8)
	padded_image.fill(Color.TRANSPARENT)
	padded_image.fill_rect(Rect2i(2, 5, 8, 10), Color.WHITE)
	_expect(PresentationDraftScript.visible_alpha_height(padded_image) == 10, "transparent padding is excluded from visible height", failures)
	var transparent_image: Image = Image.create(12, 20, false, Image.FORMAT_RGBA8)
	transparent_image.fill(Color.TRANSPARENT)
	_expect(PresentationDraftScript.visible_alpha_height(transparent_image) == 0, "fully transparent image is handled safely", failures)

	var invalid_anchor: Dictionary = alignment.save_alignment("idle_0", 999999, 30, 1000)
	_expect(not bool(invalid_anchor.get("ok", false)), "absurd anchor is rejected", failures)
	_expect(not alignment.is_slot_alignment_valid("idle_0"), "invalid anchor marks the slot not aligned", failures)
	_expect(bool(alignment.save_alignment("idle_0", 10, 30, 50).get("ok", false)), "scale 50 is valid", failures)
	_expect(alignment.is_slot_alignment_valid("idle_0"), "fixing the anchor restores alignment readiness", failures)
	_expect(bool(alignment.save_alignment("idle_0", 10, 30, 100).get("ok", false)), "scale 100 is valid", failures)
	_expect(bool(alignment.save_alignment("idle_0", 10, 30, 4000).get("ok", false)), "scale 4000 is valid", failures)
	_expect(not bool(alignment.save_alignment("idle_0", 10, 30, 49).get("ok", false)), "scale below 50 is rejected", failures)
	_expect(not alignment.is_slot_alignment_valid("idle_0"), "invalid scale marks the slot not aligned", failures)
	_expect(not bool(alignment.save_alignment("idle_0", 10, 30, 4001).get("ok", false)), "scale above 4000 is rejected", failures)
	var save_result: Dictionary = alignment.save_alignment("idle_0", 9, 28, 1250)
	_expect(bool(save_result.get("ok", false)), "valid anchor and scale save", failures)
	_expect(bool(alignment.save().get("ok", false)), "presentation draft persists", failures)
	var reloaded: RollbackFighterCreatorPresentationDraft = PresentationDraftScript.new()
	_expect(reloaded.configure(TEST_ID), "saved presentation draft reloads", failures)
	_expect(reloaded.get_slot("idle_0").get("feet_anchor", []) == [9, 28], "anchor persists", failures)
	_expect(int(reloaded.get_slot("idle_0").get("scale_milli", 0)) == 1250, "scale persists", failures)
	reloaded.synchronize_slots(draft.slot_manifest)
	_expect(int(reloaded.get_slot("idle_0").get("scale_milli", 0)) == 1250, "synchronization preserves a manual scale override", failures)

	var group_result: Dictionary = reloaded.apply_to_animation(draft.slot_manifest, "idle_0")
	_expect(bool(group_result.get("ok", false)) and int(group_result.get("count", 0)) == 1, "apply-to-animation affects idle siblings only", failures)
	_expect(reloaded.get_slot("idle_1").get("feet_anchor", []) == [9, 28], "idle sibling receives anchor", failures)
	_expect(reloaded.get_slot("jab_startup_0").get("feet_anchor", []) != [9, 28], "jab phase remains unrelated", failures)
	_expect(bool(reloaded.save_alignment("idle_0", 9, 28, 1500).get("ok", false)), "current scale can be changed", failures)
	var before_global_anchor: Array = reloaded.get_slot("jab_startup_0").get("feet_anchor", [])
	var scale_result: Dictionary = reloaded.apply_scale_to_all(draft.slot_manifest, "idle_0")
	_expect(bool(scale_result.get("ok", false)), "global scale apply succeeds", failures)
	_expect(int(reloaded.get_slot("jab_startup_0").get("scale_milli", 0)) == 1500, "global apply copies scale", failures)
	_expect(reloaded.get_slot("jab_startup_0").get("feet_anchor", []) == before_global_anchor, "global scale apply does not copy anchor", failures)
	var anchors_before_auto_fit: Dictionary = {}
	for slot_id in slot_ids:
		anchors_before_auto_fit[slot_id] = reloaded.get_slot(slot_id).get("feet_anchor", []).duplicate()
	var auto_fit_result: Dictionary = reloaded.auto_fit(draft.slot_manifest)
	_expect(bool(auto_fit_result.get("ok", false)), "explicit Auto Fit succeeds", failures)
	_expect(bool(auto_fit_result.get("alpha_bounds_used", false)), "Auto Fit reports alpha-bound measurement", failures)
	_expect(int(auto_fit_result.get("reference_visible_height", 0)) == 356, "built-in idle_0 alpha bounds provide the canonical visible height", failures)
	_expect(int(auto_fit_result.get("reference_scale_milli", 0)) == 135, "built-in idle_0 presentation scale remains unchanged", failures)
	_expect(is_equal_approx(float(auto_fit_result.get("reference_rendered_height", 0.0)), 48.06), "built-in idle_0 scale produces the canonical rendered height", failures)
	_expect(int(auto_fit_result.get("scale_milli", 0)) == 1602, "30px imported visible height uses the canonical rendered-height formula", failures)
	for slot_id in slot_ids:
		_expect(reloaded.get_slot(slot_id).get("feet_anchor", []) == anchors_before_auto_fit[slot_id], "Auto Fit preserves %s feet anchor" % slot_id, failures)
		_expect(int(reloaded.get_slot(slot_id).get("scale_milli", 0)) == int(auto_fit_result.get("scale_milli", 0)), "Auto Fit applies one fighter-wide scale to %s" % slot_id, failures)
		_expect(str(reloaded.get_slot(slot_id).get("status", "")) == "aligned", "Auto Fit marks valid %s build-ready" % slot_id, failures)
	var scale_before_transparent_fit: int = int(reloaded.get_slot("idle_0").get("scale_milli", 0))
	transparent_image.save_png(root + "/sprites/idle_0.png")
	var transparent_fit: Dictionary = reloaded.auto_fit(draft.slot_manifest)
	_expect(not bool(transparent_fit.get("ok", false)), "fully transparent Auto Fit source fails safely", failures)
	_expect(int(reloaded.get_slot("idle_0").get("scale_milli", 0)) == scale_before_transparent_fit, "failed Auto Fit does not mutate existing scales", failures)
	_expect(bool(Importer.import_png(root, TEST_ID, draft.slot_manifest, "idle_0", source_path).get("ok", false)), "opaque idle_0 test art restores after transparent Auto Fit check", failures)
	_expect(reloaded.get_aligned_count(draft.slot_manifest) == 4, "all valid assigned slots count as aligned without confirmation history", failures)
	_expect(reloaded.get_missing_alignment_ids(draft.slot_manifest).is_empty(), "valid presentation data has no missing alignment", failures)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(root + "/sprites/jab_active_0.png"))
	_expect(not bool(reloaded.load_slot_image("jab_active_0").get("ok", false)), "assigned slot with missing image cannot be aligned", failures)
	_expect(reloaded.get_aligned_count(draft.slot_manifest) == 3 and reloaded.get_missing_alignment_ids(draft.slot_manifest) == PackedStringArray(["jab_active_0"]), "missing assigned art still blocks readiness", failures)

	var replacement: Dictionary = Importer.import_png(root, TEST_ID, draft.slot_manifest, "idle_0", source_path)
	_expect(bool(replacement.get("ok", false)), "replacement image imported", failures)
	_expect(reloaded.mark_replaced("idle_0", "sprites/idle_0.png", 20, 30), "replacement metadata updates", failures)
	_expect(str(reloaded.get_slot("idle_0").get("status", "")) == "aligned", "replacement with valid inherited metadata remains aligned", failures)
	var remove_result: Dictionary = Importer.remove_slot(root, TEST_ID, draft.slot_manifest, "idle_1")
	_expect(bool(remove_result.get("ok", false)), "assigned sibling can be removed", failures)
	reloaded.remove_slot("idle_1")
	_expect(reloaded.get_slot("idle_1").is_empty(), "removal clears alignment metadata", failures)
	var missing_image: Dictionary = reloaded.load_slot_image("idle_1")
	_expect(not bool(missing_image.get("ok", false)), "missing image cannot be aligned", failures)
	_expect(reloaded.get_manifest_assigned_count(draft.slot_manifest) == 3, "progress denominator follows assigned manifest slots", failures)
	_expect(reloaded.save().get("path", "").begins_with("user://characters/"), "no res:// write path is used", failures)

	var loader: RollbackFighterCharacterDefinitionLoader = LoaderScript.new()
	var rules_result: Dictionary = loader.load_game_rules(RULES_PATH)
	var char_result: Dictionary = loader.load_builtin_fighter(REGISTRY_PATH, "example_fighter")
	if bool(rules_result.get("ok", false)) and bool(char_result.get("ok", false)):
		var writer: RollbackFighterCanonicalConfigWriter = CanonicalWriterScript.new()
		var before_digest: String = writer.sha256_hex(writer.character_bytes(rules_result["definition"], char_result["definition"]))
		reloaded.save()
		var after_digest: String = writer.sha256_hex(writer.character_bytes(rules_result["definition"], char_result["definition"]))
		_expect(before_digest == after_digest, "creator presentation metadata does not affect authoritative digest", failures)
	else:
		_expect(false, "built-in definitions load for digest-isolation assertion", failures)

	_cleanup(root, source_path)
	_finish(failures)


func _cleanup(root: String, source_path: String) -> void:
	if FileAccess.file_exists(source_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(source_path))
	var sprite_dir: DirAccess = DirAccess.open(root + "/sprites")
	if sprite_dir != null:
		sprite_dir.list_dir_begin()
		var name: String = sprite_dir.get_next()
		while not name.is_empty():
			if not sprite_dir.current_is_dir():
				DirAccess.remove_absolute(ProjectSettings.globalize_path(root + "/sprites/" + name))
			name = sprite_dir.get_next()
		sprite_dir.list_dir_end()
	for file_path in [root + "/character.json", root + "/creator_manifest.json", root + "/slot_manifest.json", root + "/presentation_draft.json", root + "/moves/jab.json", root + "/moves/heavy.json", root + "/hitboxes/jab.json", root + "/hitboxes/heavy.json"]:
		if FileAccess.file_exists(file_path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(file_path))
	for folder in [root + "/sprites", root + "/moves", root + "/hitboxes", root]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(folder))


func _expect(condition: bool, message: String, failures: PackedStringArray) -> void:
	if not condition:
		failures.append(message)


func _finish(failures: PackedStringArray) -> void:
	if failures.is_empty():
		print("[CreatorPresentationDraftTests] PASS")
		quit(0)
		return
	for failure in failures:
		printerr("[CreatorPresentationDraftTests] FAIL: %s" % failure)
	quit(1)
