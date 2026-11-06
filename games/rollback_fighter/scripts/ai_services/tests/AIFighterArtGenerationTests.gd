extends SceneTree

const TEST_FIGHTER_ID := "ai3_asset_test"
const TEST_SETTINGS_PATH := "user://settings/ai3_asset_test.cfg"
const TEST_SOURCE_PATH := "user://ai3_manual_source.png"
const Contracts = preload("res://games/rollback_fighter/scripts/ai_services/AIContracts.gd")
const ServiceScript = preload("res://games/rollback_fighter/scripts/ai_services/AIService.gd")
const StoreScript = preload("res://games/rollback_fighter/scripts/ai_services/AISettingsStore.gd")
const GeneratorScript = preload("res://games/rollback_fighter/scripts/ai_services/AIFighterArtGenerator.gd")
const PromptBuilderScript = preload("res://games/rollback_fighter/scripts/ai_services/FighterArtPromptBuilder.gd")
const GeminiProviderScript = preload("res://games/rollback_fighter/scripts/ai_services/GeminiAIProvider.gd")
const ImageProviderScript = preload("res://games/rollback_fighter/scripts/ai_services/tests/MockImageAIProvider.gd")
const TextProviderScript = preload("res://games/rollback_fighter/scripts/ai_services/tests/MockAIProvider.gd")
const DraftScript = preload("res://games/rollback_fighter/scripts/config/CreatorFighterDraft.gd")
const AlignmentScript = preload("res://games/rollback_fighter/scripts/config/CreatorPresentationDraft.gd")
const ArtImporter = preload("res://games/rollback_fighter/scripts/config/CreatorArtImporter.gd")
const LoaderScript = preload("res://games/rollback_fighter/scripts/config/CharacterDefinitionLoader.gd")
const CharacterScript = preload("res://games/rollback_fighter/scripts/config/CharacterDefinition.gd")
const MoveScript = preload("res://games/rollback_fighter/scripts/config/MoveDefinition.gd")
const PresentationScript = preload("res://games/rollback_fighter/scripts/config/PresentationDefinition.gd")
const WriterScript = preload("res://games/rollback_fighter/scripts/config/CanonicalConfigWriter.gd")
const RULES_PATH := "res://games/rollback_fighter/config/game_rules.json"


func _initialize() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	var failures := PackedStringArray()
	_cleanup()
	var draft = DraftScript.new()
	draft.set_identity("AI3 Asset Test", TEST_FIGHTER_ID)
	draft.set_visual_description("Masked red-haired luchadora with oversized gloves")
	var alignment = AlignmentScript.new()
	_expect(alignment.configure(TEST_FIGHTER_ID), "alignment fixture configures", failures)
	await _test_capability_gate(draft, alignment, failures)
	_test_prompt_builder(draft, failures)
	_test_gemini_image_adapter(failures)
	await _test_generation_pipeline(draft, alignment, failures)
	_cleanup()
	_finish(failures)


func _test_capability_gate(draft, alignment, failures: PackedStringArray) -> void:
	var service = ServiceScript.new()
	service.initialize(StoreScript.new(TEST_SETTINGS_PATH), false)
	service.register_provider(TextProviderScript.new())
	service.enabled = true
	var generator = GeneratorScript.new()
	var unsupported: Dictionary = await generator.generate_slot(service, draft, alignment, "idle_0")
	_expect(str(unsupported.get("error_code", "")) == Contracts.ERROR_UNSUPPORTED_CAPABILITY, "image generation requires IMAGE_GENERATION capability", failures)
	_expect(str(unsupported.get("user_message", "")) == "Current AI provider does not support image generation.", "unsupported provider returns friendly message", failures)
	var source: String = FileAccess.get_file_as_string("res://games/rollback_fighter/scripts/ai_services/AIFighterArtGenerator.gd")
	var wizard_source: String = FileAccess.get_file_as_string("res://games/rollback_fighter/scripts/ui/CreatorWizard.gd")
	_expect(not source.contains("Gemini") and not wizard_source.contains("Gemini") and source.contains("generate_image"), "creator generation code calls only the provider-agnostic service", failures)
	service.free()


func _test_prompt_builder(draft, failures: PackedStringArray) -> void:
	var builder = PromptBuilderScript.new()
	var request = builder.build_request(draft, "heavy_active_0")
	_expect(request != null, "manifest slot resolves for prompting", failures)
	if request != null:
		var prompt: String = str(request.prompt)
		_expect(prompt.contains("heavy_active_0") and prompt.contains("Animation group: heavy") and prompt.contains("strongest impact"), "slot prompt includes manifest group and active-phase context", failures)
		_expect(prompt.contains("Platform Fighter") and prompt.contains("Masked red-haired luchadora"), "slot prompt includes project style and visual description", failures)
		_expect(bool(request.transparent_background) and int(request.output_count) == 1, "request prefers transparency and one output", failures)


func _test_gemini_image_adapter(failures: PackedStringArray) -> void:
	var provider = GeminiProviderScript.new()
	var config = provider.make_default_config()
	_expect(Contracts.CAPABILITY_IMAGE_GENERATION in provider.get_capabilities(config), "Gemini advertises image generation when an image model is configured", failures)
	config.image_model = ""
	_expect(Contracts.CAPABILITY_IMAGE_GENERATION not in provider.get_capabilities(config), "Gemini does not advertise image generation without an image model", failures)
	var expected_bytes: PackedByteArray = PackedByteArray([1, 2, 3, 4])
	var extracted: Dictionary = provider._extract_image({
		"candidates": [{"content": {"parts": [{"inlineData": {
			"mimeType": "image/png",
			"data": Marshalls.raw_to_base64(expected_bytes),
		}}]}}],
	})
	_expect(extracted.get("bytes", PackedByteArray()) == expected_bytes and str(extracted.get("mime_type", "")) == "image/png", "Gemini inline image data normalizes to the generic image result", failures)
	provider.free()


func _test_generation_pipeline(draft, alignment, failures: PackedStringArray) -> void:
	var provider = ImageProviderScript.new()
	provider.set_test_png(Color(1.0, 0.0, 0.0, 1.0))
	var service = ServiceScript.new()
	service.initialize(StoreScript.new(TEST_SETTINGS_PATH), false)
	service.register_provider(provider)
	service.enabled = true
	var generator = GeneratorScript.new()
	var before_config: String = JSON.stringify(draft.character_document) + JSON.stringify(draft.move_documents)
	var before_digest: String = _digest_for(draft)
	var first: Dictionary = await generator.generate_slot(service, draft, alignment, "idle_0")
	_expect(bool(first.get("success", false)), "valid generated image routes through CreatorArtImporter", failures)
	var final_path: String = "%s/sprites/idle_0.png" % draft.get_user_draft_path()
	_expect(FileAccess.file_exists(final_path), "generated image uses the normal deterministic slot path", failures)
	_expect(alignment.is_slot_alignment_valid("idle_0"), "generated art receives normal valid default alignment", failures)
	var slot: Dictionary = PromptBuilderScript.new().find_slot_context(draft.slot_manifest, "idle_0").get("slot", {})
	var provenance: Dictionary = slot.get("generation_provenance", {})
	_expect(bool(provenance.get("generated_by_ai", false)) and str(provenance.get("provider_id", "")) == "image_mock" and str(provenance.get("model_id", "")) == "mock-image-v1", "lightweight provenance is stored in creator metadata", failures)
	_expect(provenance.keys().size() == 4 and provenance.has("generated_at"), "provenance stores only the non-authoritative provider/model/timestamp fields", failures)
	var creator_manifest: Dictionary = _read_json(draft.get_user_draft_path() + "/creator_manifest.json")
	_expect(str(creator_manifest.get("visual_description", "")) == draft.visual_description, "fighter visual description persists as creator metadata", failures)
	_expect(before_config == JSON.stringify(draft.character_document) + JSON.stringify(draft.move_documents), "image generation does not alter authoritative fighter configuration", failures)
	var first_bytes: PackedByteArray = _read_bytes(final_path)

	provider.output_bytes = PackedByteArray([1, 2, 3, 4])
	provider.output_mime_type = "image/png"
	var invalid: Dictionary = await generator.generate_slot(service, draft, alignment, "idle_0")
	_expect(not bool(invalid.get("success", false)), "invalid generated image rejects safely", failures)
	_expect(_read_bytes(final_path) == first_bytes, "failed regeneration does not overwrite existing art", failures)

	provider.set_test_png(Color(0.0, 0.0, 1.0, 1.0))
	var regenerated: Dictionary = await generator.generate_slot(service, draft, alignment, "idle_0")
	_expect(bool(regenerated.get("success", false)) and _read_bytes(final_path) != first_bytes, "successful regeneration replaces the slot", failures)
	_expect(int(regenerated.get("reference_count", 0)) == 1, "regeneration uses idle_0 as the preferred reference image", failures)
	var auto_fit: Dictionary = alignment.auto_fit(draft.slot_manifest)
	_expect(bool(auto_fit.get("ok", false)), "Auto Fit remains usable for generated art", failures)

	var manual_image := Image.create(24, 48, false, Image.FORMAT_RGBA8)
	manual_image.fill(Color(0.0, 1.0, 0.0, 1.0))
	_expect(manual_image.save_png(TEST_SOURCE_PATH) == OK, "manual fixture saves", failures)
	var manual: Dictionary = ArtImporter.import_png(draft.get_user_draft_path(), draft.fighter_id, draft.slot_manifest, "idle_1", TEST_SOURCE_PATH)
	_expect(bool(manual.get("ok", false)), "manual art import still works through the original importer", failures)
	var manual_slot: Dictionary = PromptBuilderScript.new().find_slot_context(draft.slot_manifest, "idle_1").get("slot", {})
	_expect(not manual_slot.has("generation_provenance"), "manual import contains no AI provenance", failures)

	var optional_slot: Dictionary = PromptBuilderScript.new().find_slot_context(draft.slot_manifest, "heavy_active_0").get("slot", {})
	_expect(not bool(optional_slot.get("required", true)) and not bool(optional_slot.get("assigned", false)), "optional slots remain optional and are not generated automatically", failures)
	var after_config: String = JSON.stringify(draft.character_document) + JSON.stringify(draft.move_documents)
	_expect(before_config == after_config, "different presentation art remains authoritative-compatible", failures)
	var after_digest: String = _digest_for(draft)
	_expect(not before_digest.is_empty() and before_digest == after_digest, "art bytes and AI provenance do not affect the canonical fighter digest", failures)

	service.enabled = false
	var disabled: Dictionary = await generator.generate_slot(service, draft, alignment, "block_0")
	_expect(str(disabled.get("error_code", "")) == Contracts.ERROR_NOT_CONFIGURED, "AI disabled leaves generation unavailable without affecting manual creation", failures)
	service.free()


func _digest_for(draft) -> String:
	var loader = LoaderScript.new()
	var errors: Array[Dictionary] = []
	var character_data: Dictionary = loader._normalize_character(draft.character_document, "<ai3-digest>/character.json", errors)
	var moves: Dictionary = {}
	for slot: String in ["light", "heavy"]:
		var move_data: Dictionary = loader._normalize_move(draft.move_documents[slot], "<ai3-digest>/%s.json" % slot, errors)
		var profile: Dictionary = loader._normalize_hitbox_profile(draft.hitbox_documents[slot], "<ai3-digest>/%s_hitbox.json" % slot, move_data, errors)
		moves[slot] = MoveScript.new(move_data, profile)
	if not errors.is_empty():
		return ""
	character_data.erase("move_refs")
	var definition = CharacterScript.new(character_data, moves, PresentationScript.new({}))
	var rules_result: Dictionary = loader.load_game_rules(RULES_PATH)
	if not bool(rules_result.get("ok", false)):
		return ""
	var writer = WriterScript.new()
	return writer.sha256_hex(writer.character_bytes(rules_result.definition, definition))


func _read_bytes(path: String) -> PackedByteArray:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return PackedByteArray()
	var bytes: PackedByteArray = file.get_buffer(file.get_length())
	file.close()
	return bytes


func _read_json(path: String) -> Dictionary:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed if parsed is Dictionary else {}


func _cleanup() -> void:
	_cleanup_tree("user://characters/%s" % TEST_FIGHTER_ID)
	for path: String in [TEST_SETTINGS_PATH, TEST_SOURCE_PATH]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _cleanup_tree(path: String) -> void:
	var absolute: String = ProjectSettings.globalize_path(path)
	if not DirAccess.dir_exists_absolute(absolute):
		return
	var directory: DirAccess = DirAccess.open(path)
	if directory == null:
		return
	directory.list_dir_begin()
	var name: String = directory.get_next()
	while not name.is_empty():
		var child: String = path.path_join(name)
		if directory.current_is_dir():
			_cleanup_tree(child)
		else:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(child))
		name = directory.get_next()
	directory.list_dir_end()
	DirAccess.remove_absolute(absolute)


func _expect(condition: bool, message: String, failures: PackedStringArray) -> void:
	if not condition:
		failures.append(message)


func _finish(failures: PackedStringArray) -> void:
	if failures.is_empty():
		print("[AIFighterArtGenerationTests] PASS")
		quit(0)
		return
	for failure: String in failures:
		printerr("[AIFighterArtGenerationTests] FAIL: %s" % failure)
	quit(1)
