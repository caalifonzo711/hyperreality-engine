extends SceneTree


const ManifestScript = preload("res://games/rollback_fighter/scripts/config/FighterPresentationManifest.gd")
const ResolverScript = preload("res://games/rollback_fighter/scripts/config/FighterPresentationManifestResolver.gd")
const DraftScript = preload("res://games/rollback_fighter/scripts/config/CreatorFighterDraft.gd")
const ImporterScript = preload("res://games/rollback_fighter/scripts/config/CreatorArtImporter.gd")
const AlignmentScript = preload("res://games/rollback_fighter/scripts/config/CreatorPresentationDraft.gd")
const BuilderScript = preload("res://games/rollback_fighter/scripts/config/CreatorFighterBuilder.gd")
const ProjectScript = preload("res://games/rollback_fighter/scripts/projects/GameProjectDefinition.gd")
const ProjectStoreScript = preload("res://games/rollback_fighter/scripts/projects/GameProjectStore.gd")
const LoaderScript = preload("res://games/rollback_fighter/scripts/config/CharacterDefinitionLoader.gd")
const WriterScript = preload("res://games/rollback_fighter/scripts/config/CanonicalConfigWriter.gd")
const FIGHTER_ID := "c7_manifest_test_fighter"
const PROJECT_ID := "c7_manifest_test_project"
const REGISTRY_PATH := "res://games/rollback_fighter/config/builtin_fighters.json"
const RULES_PATH := "res://games/rollback_fighter/config/game_rules.json"


func _initialize() -> void:
	var failures := PackedStringArray()
	_cleanup_tree("user://characters/%s" % FIGHTER_ID)
	_cleanup_tree("user://games/%s" % PROJECT_ID)
	var platform: RollbackFighterPresentationManifest = _resolved("platform_fighter", failures)
	var footsies: RollbackFighterPresentationManifest = _resolved("footsies", failures)
	var anime: RollbackFighterPresentationManifest = _resolved("anime_fighter", failures)
	var custom: RollbackFighterPresentationManifest = _resolved("custom", failures)
	if platform == null or footsies == null or anime == null or custom == null:
		_finish(failures)
		return

	var expected_platform := PackedStringArray(["idle_0", "idle_1", "jab_startup_0", "jab_active_0", "block_0", "dodge_0", "dodge_1", "hit_0", "dead_0"])
	var platform_required := _required_ids(platform)
	_expect(platform.required_count() == 9, "Platform Fighter retains nine required drawings", failures)
	_expect(platform_required == expected_platform, "Platform Fighter retains the exact legacy required slot IDs", failures)
	_expect(footsies.required_count() == 12 and footsies.optional_count() == 5, "Footsies resolves a distinct 12/5 manifest", failures)
	_expect(anime.required_count() == 13 and anime.optional_count() == 12, "Anime Fighter resolves a richer 13/12 manifest", failures)
	_expect(custom.required_count() == 9 and custom.optional_count() == 9, "Custom starts from Platform Fighter counts", failures)

	var draft: RollbackFighterCreatorDraft = DraftScript.new()
	_expect(draft.get_required_art_slot_total() == platform.required_count(), "legacy Required Art count derives from Platform manifest", failures)
	var authoritative_before: Array = [draft.character_document.duplicate(true), draft.move_documents.duplicate(true), draft.hitbox_documents.duplicate(true)]
	_expect(draft.set_presentation_policy("anime_fighter", ResolverScript.policy_reference("anime_fighter")), "draft accepts resolved Anime policy", failures)
	_expect(draft.get_required_art_slot_total() == anime.required_count() and draft.get_optional_art_slot_total() == anime.optional_count(), "Required Art model derives dynamic Anime counts", failures)
	var authoritative_after: Array = [draft.character_document.duplicate(true), draft.move_documents.duplicate(true), draft.hitbox_documents.duplicate(true)]
	_expect(authoritative_before == authoritative_after, "presentation manifest changes do not alter authoritative gameplay documents", failures)
	var loader: RollbackFighterCharacterDefinitionLoader = LoaderScript.new()
	var rules_result: Dictionary = loader.load_game_rules(RULES_PATH)
	var fighter_result: Dictionary = loader.load_builtin_fighter(REGISTRY_PATH, "example_fighter")
	if bool(rules_result.get("ok", false)) and bool(fighter_result.get("ok", false)):
		var writer: RollbackFighterCanonicalConfigWriter = WriterScript.new()
		var digest_before: String = writer.sha256_hex(writer.character_bytes(rules_result["definition"], fighter_result["definition"]))
		ResolverScript.resolve("footsies", ResolverScript.policy_reference("footsies"))
		ResolverScript.resolve("anime_fighter", ResolverScript.policy_reference("anime_fighter"))
		var digest_after: String = writer.sha256_hex(writer.character_bytes(rules_result["definition"], fighter_result["definition"]))
		_expect(digest_before == digest_after and not digest_before.is_empty(), "presentation manifest resolution is excluded from the authoritative digest", failures)
	else:
		_expect(false, "authoritative digest fixtures load", failures)

	var anime_slot_manifest: Dictionary = anime.to_slot_manifest(draft.move_documents)
	var anime_identity: Dictionary = ManifestScript.manifest_identity(anime_slot_manifest)
	_expect(str(anime_identity.get("manifest_id", "")) == "anime_fighter_v1", "fighter slot manifest retains manifest identity and version", failures)
	var legacy_manifest: Dictionary = {"manifest_version": 1, "animations": {}}
	var legacy_identity: Dictionary = ManifestScript.manifest_identity(legacy_manifest)
	_expect(bool(legacy_identity.get("legacy", false)) and str(legacy_identity.get("manifest_id", "")) == "platform_fighter_v1", "pre-C7 manifest identity migrates to Platform defaults", failures)

	var platform_slot_manifest: Dictionary = platform.to_slot_manifest(draft.move_documents)
	var heavy_meta: Dictionary = Dictionary(platform_slot_manifest.get("group_metadata", {})).get("heavy", {})
	_expect(str(heavy_meta.get("fallback_group", "")) == "jab", "Platform heavy presentation retains jab fallback", failures)
	var anime_heavy: Dictionary = anime_slot_manifest["animations"]["heavy"]
	for phase in ["startup", "active", "recovery"]:
		var phase_slots: Array = Dictionary(anime_heavy[phase]).get("slots", [])
		_expect(not phase_slots.is_empty() and bool(phase_slots[0].get("required", false)), "Anime requires dedicated heavy %s art" % phase, failures)

	var corrupt_document := {
		"manifest_id": platform.manifest_id,
		"manifest_version": platform.manifest_version,
		"style_preset": platform.style_preset,
		"display_name": platform.display_name,
		"help_text": platform.help_text,
		"groups": platform.groups.duplicate(true),
	}
	var corrupt_groups: Array = corrupt_document["groups"]
	var first_slots: Array = corrupt_groups[0]["slots"]
	first_slots[1]["slot_id"] = first_slots[0]["slot_id"]
	var corrupt: RollbackFighterPresentationManifest = ManifestScript.new()
	corrupt.configure(corrupt_document)
	_expect(not corrupt.validate().is_empty(), "duplicate manifest slot IDs fail validation safely", failures)
	var bad_fallback_document: Dictionary = corrupt_document.duplicate(true)
	bad_fallback_document["groups"][0]["slots"][1]["slot_id"] = "idle_1"
	bad_fallback_document["groups"][0]["slots"][1]["fallback_slot"] = "missing_slot"
	var bad_fallback: RollbackFighterPresentationManifest = ManifestScript.new()
	bad_fallback.configure(bad_fallback_document)
	_expect(not bad_fallback.validate().is_empty(), "invalid manifest fallback references fail validation safely", failures)
	var bad_count_document: Dictionary = bad_fallback_document.duplicate(true)
	bad_count_document["groups"][0]["slots"][1]["fallback_slot"] = ""
	bad_count_document["groups"][0]["recommended_drawing_count"] = -1
	var bad_count: RollbackFighterPresentationManifest = ManifestScript.new()
	bad_count.configure(bad_count_document)
	_expect(not bad_count.validate().is_empty(), "negative manifest counts fail validation safely", failures)

	draft.set_identity("C7 Manifest Test", FIGHTER_ID)
	var created: Dictionary = draft.create_user_draft()
	_expect(bool(created.get("ok", false)), "Anime manifest fighter draft saves", failures)
	var builder: RollbackFighterCreatorBuilder = BuilderScript.new()
	_expect(not bool(builder.build(FIGHTER_ID).get("ok", false)), "missing required manifest art blocks build", failures)
	var required_complete: Dictionary = draft.slot_manifest.duplicate(true)
	_mark_required_assigned(required_complete)
	_expect(builder._missing_required(required_complete).is_empty(), "unassigned optional manifest art does not block required-art readiness", failures)

	var source_path := "user://c7_manifest_source.png"
	var image := Image.create(12, 18, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.3, 0.6, 0.9, 0.8))
	var source := FileAccess.open(source_path, FileAccess.WRITE)
	if source != null:
		source.store_buffer(image.save_png_to_buffer())
		source.close()
	var imported: Dictionary = ImporterScript.import_png(draft.get_user_draft_path(), FIGHTER_ID, draft.slot_manifest, "heavy_startup_1", source_path)
	_expect(bool(imported.get("ok", false)) and str(imported.get("path", "")).ends_with("/heavy_startup_1.png"), "importer maps PNG to a manifest-defined slot ID", failures)
	var alignment: RollbackFighterCreatorPresentationDraft = AlignmentScript.new()
	_expect(alignment.configure(FIGHTER_ID), "alignment opens variable-count manifest draft", failures)
	alignment.synchronize_slots(draft.slot_manifest)
	_expect(alignment.get_manifest_assigned_count(draft.slot_manifest) == 1 and alignment.get_aligned_count(draft.slot_manifest) == 1, "alignment derives its variable slot set from assigned manifest art", failures)

	var project: RollbackFighterGameProjectDefinition = ProjectScript.new()
	project.configure("C7 Manifest Project", PROJECT_ID, "anime_fighter")
	var store: RollbackFighterGameProjectStore = ProjectStoreScript.new()
	_expect(bool(store.create(project).get("ok", false)), "project with versioned presentation policy saves", failures)
	var loaded: Dictionary = store.load_project(PROJECT_ID)
	if bool(loaded.get("ok", false)):
		var reloaded: RollbackFighterGameProjectDefinition = loaded["project"]
		var restarted_resolution: Dictionary = ResolverScript.resolve(reloaded.style_preset, reloaded.presentation_policy_reference)
		var restarted_manifest: RollbackFighterPresentationManifest = restarted_resolution.get("manifest")
		_expect(bool(restarted_resolution.get("ok", false)) and restarted_manifest != null and restarted_manifest.manifest_id == anime.manifest_id, "persisted project style resolves the same manifest after restart", failures)
	else:
		_expect(false, "C7 project reloads", failures)

	if FileAccess.file_exists(source_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(source_path))
	_cleanup_tree("user://characters/%s" % FIGHTER_ID)
	_cleanup_tree("user://games/%s" % PROJECT_ID)
	_finish(failures)


func _resolved(style: String, failures: PackedStringArray) -> RollbackFighterPresentationManifest:
	var result: Dictionary = ResolverScript.resolve(style, ResolverScript.policy_reference(style))
	_expect(bool(result.get("ok", false)), "%s manifest validates" % style, failures)
	return result.get("manifest")


func _required_ids(manifest: RollbackFighterPresentationManifest) -> PackedStringArray:
	var result := PackedStringArray()
	for group in manifest.groups:
		for slot in Array(group.get("slots", [])):
			if bool(slot.get("required", false)):
				result.append(str(slot.get("slot_id", "")))
	return result


func _mark_required_assigned(value: Variant) -> void:
	if value is Dictionary:
		if value.has("slot") and bool(value.get("required", false)):
			value["assigned"] = true
		for child in value.values():
			_mark_required_assigned(child)
	elif value is Array:
		for child in value:
			_mark_required_assigned(child)


func _cleanup_tree(root: String) -> void:
	var absolute_root: String = ProjectSettings.globalize_path(root)
	if not DirAccess.dir_exists_absolute(absolute_root):
		return
	_remove_contents(root)
	DirAccess.remove_absolute(absolute_root)


func _remove_contents(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while not name.is_empty():
		var child := path + "/" + name
		if dir.current_is_dir():
			_remove_contents(child)
		DirAccess.remove_absolute(ProjectSettings.globalize_path(child))
		name = dir.get_next()
	dir.list_dir_end()


func _expect(condition: bool, message: String, failures: PackedStringArray) -> void:
	if not condition:
		failures.append(message)


func _finish(failures: PackedStringArray) -> void:
	if failures.is_empty():
		print("[FighterPresentationManifestTests] PASS")
		quit(0)
		return
	for failure in failures:
		printerr("[FighterPresentationManifestTests] FAIL: %s" % failure)
	quit(1)
