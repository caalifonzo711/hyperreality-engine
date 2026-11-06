extends SceneTree

const Contracts = preload("res://games/rollback_fighter/scripts/ai_services/AIContracts.gd")
const ServiceScript = preload("res://games/rollback_fighter/scripts/ai_services/AIService.gd")
const StoreScript = preload("res://games/rollback_fighter/scripts/ai_services/AISettingsStore.gd")
const AssistantScript = preload("res://games/rollback_fighter/scripts/ai_services/AIFighterTuningAssistant.gd")
const TextOnlyProviderScript = preload("res://games/rollback_fighter/scripts/ai_services/tests/MockAIProvider.gd")
const StructuredProviderScript = preload("res://games/rollback_fighter/scripts/ai_services/tests/MockStructuredAIProvider.gd")
const DraftScript = preload("res://games/rollback_fighter/scripts/config/CreatorFighterDraft.gd")
const ProposalScript = preload("res://games/rollback_fighter/scripts/config/AIFighterTuningProposal.gd")
const Catalog = preload("res://games/rollback_fighter/scripts/config/CreatorTuningCatalog.gd")
const LoaderScript = preload("res://games/rollback_fighter/scripts/config/CharacterDefinitionLoader.gd")
const CharacterScript = preload("res://games/rollback_fighter/scripts/config/CharacterDefinition.gd")
const MoveScript = preload("res://games/rollback_fighter/scripts/config/MoveDefinition.gd")
const PresentationScript = preload("res://games/rollback_fighter/scripts/config/PresentationDefinition.gd")
const WriterScript = preload("res://games/rollback_fighter/scripts/config/CanonicalConfigWriter.gd")

const TEST_SETTINGS_PATH := "user://settings/ai2_tuning_test.cfg"
const RULES_PATH := "res://games/rollback_fighter/config/game_rules.json"


func _initialize() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	var failures := PackedStringArray()
	_remove_test_settings()
	var draft = _make_draft("ai2_test")
	await _test_capability_and_request_context(draft, failures)
	_test_proposal_validation(draft, failures)
	await _test_service_flow(draft, failures)
	_test_apply_cancel_and_digest(failures)
	_remove_test_settings()
	_finish(failures)


func _test_capability_and_request_context(draft, failures: PackedStringArray) -> void:
	var service = ServiceScript.new()
	service.initialize(StoreScript.new(TEST_SETTINGS_PATH), false)
	service.register_provider(TextOnlyProviderScript.new())
	service.enabled = true
	var assistant = AssistantScript.new()
	var unsupported: Dictionary = await assistant.request_proposal(service, draft, "fast glass cannon", "platform_fighter")
	_expect(str(unsupported.get("error_code", "")) == Contracts.ERROR_UNSUPPORTED_CAPABILITY, "natural-language tuning requires structured output capability", failures)
	var request = assistant.build_request(draft, "slow defensive tank", "footsies")
	var request_text: String = str(request.prompt)
	_expect(request_text.contains("footsies") and request_text.contains("current_values") and request_text.contains("supported_fields_and_ranges"), "request includes style, current values, fields, and ranges", failures)
	_expect(not request_text.contains("api_key") and not request_text.contains("provider_id"), "request excludes credentials and provider identity", failures)
	_expect(draft.presentation_style_id == "platform_fighter", "style context does not change the draft style", failures)
	service.free()


func _test_proposal_validation(draft, failures: PackedStringArray) -> void:
	var valid: Dictionary = ProposalScript.from_dictionary({
		"reason": "Make movement slower and the heavy more committed.",
		"values": {"move_speed": 220, "heavy_damage": 24, "heavy_recovery": 25},
	}, draft)
	_expect(bool(valid.get("ok", false)), "valid supported fields parse", failures)
	if bool(valid.get("ok", false)):
		_expect(valid.proposal.differences().size() == 3, "preview contains only changed values", failures)
	var unknown: Dictionary = ProposalScript.from_dictionary({
		"reason": "Approximate unsupported mechanics.",
		"values": {"move_speed": 300, "fireball_damage": 999, "script_path": "res://attack.gd"},
	}, draft)
	_expect(bool(unknown.get("ok", false)), "unknown fields are ignored when supported values remain", failures)
	if bool(unknown.get("ok", false)):
		_expect(not unknown.proposal.values.has("fireball_damage") and not unknown.proposal.values.has("script_path"), "unsupported mechanics and path fields never enter the proposal", failures)
		_expect(not str(unknown.proposal.unsupported_note).is_empty(), "unsupported fields produce a normalized note", failures)
	var clamped: Dictionary = ProposalScript.from_dictionary({
		"reason": "Extreme request.",
		"values": {"max_hp": 999999999, "jab_damage": -50},
	}, draft)
	_expect(bool(clamped.get("ok", false)), "out-of-range integers are handled safely", failures)
	if bool(clamped.get("ok", false)):
		_expect(int(clamped.proposal.values.max_hp) == 500 and int(clamped.proposal.values.jab_damage) == 0, "out-of-range values clamp to shared creator limits", failures)
	var invalid_type: Dictionary = ProposalScript.from_dictionary({"reason": "Bad type.", "values": {"move_speed": "very fast"}}, draft)
	_expect(not bool(invalid_type.get("ok", false)), "invalid value types fail safely", failures)
	var invalid_number: Dictionary = ProposalScript.from_dictionary({"reason": "Bad number.", "values": {"move_speed": INF}}, draft)
	_expect(not bool(invalid_number.get("ok", false)), "infinite values fail safely", failures)


func _test_service_flow(draft, failures: PackedStringArray) -> void:
	var provider = StructuredProviderScript.new()
	provider.structured_output = {
		"reason": "Readable poke-focused tuning.",
		"values": {"jab_damage": 5, "jab_recovery": 3},
	}
	var service = ServiceScript.new()
	service.initialize(StoreScript.new(TEST_SETTINGS_PATH), false)
	service.register_provider(provider)
	service.enabled = true
	var assistant = AssistantScript.new()
	var result: Dictionary = await assistant.request_proposal(service, draft, "quick annoying poke character", "platform_fighter")
	_expect(bool(result.get("success", false)) and result.get("proposal") != null, "structured provider result becomes a proposal", failures)
	provider.failure_code = Contracts.ERROR_RATE_LIMITED
	provider.failure_message = "The provider is busy."
	var failed: Dictionary = await assistant.request_proposal(service, draft, "try again", "platform_fighter")
	_expect(str(failed.get("error_code", "")) == Contracts.ERROR_RATE_LIMITED and str(failed.get("user_message", "")) == "The provider is busy.", "provider errors surface normalized friendly messages", failures)
	service.enabled = false
	var disabled: Dictionary = await assistant.request_proposal(service, draft, "still manual", "platform_fighter")
	_expect(str(disabled.get("error_code", "")) == Contracts.ERROR_NOT_CONFIGURED, "AI disabled leaves the assistant safely unavailable", failures)
	_expect(draft.validate_documents().is_empty(), "AI disabled leaves the creator draft usable", failures)
	service.free()


func _test_apply_cancel_and_digest(failures: PackedStringArray) -> void:
	var ai_draft = _make_draft("digest_fighter")
	var manual_draft = _make_draft("digest_fighter")
	var before: String = JSON.stringify(ai_draft.character_document) + JSON.stringify(ai_draft.move_documents)
	var document := {
		"reason": "Deterministic supported changes.",
		"values": {"move_speed": 275, "max_hp": 130, "jab_damage": 6, "heavy_damage": 22},
	}
	var parsed: Dictionary = ProposalScript.from_dictionary(document, ai_draft)
	_expect(bool(parsed.get("ok", false)), "digest proposal parses", failures)
	if not bool(parsed.get("ok", false)):
		return
	_expect(before == JSON.stringify(ai_draft.character_document) + JSON.stringify(ai_draft.move_documents), "Cancel/preview leaves draft unchanged", failures)
	var applied: Dictionary = parsed.proposal.apply_to_draft(ai_draft)
	_expect(bool(applied.get("ok", false)), "Apply updates the existing creator tuning model", failures)
	var manual_values: Dictionary = document["values"]
	for field_id: String in manual_values:
		Catalog.set_value(manual_draft, field_id, int(manual_values[field_id]))
	_expect(int(Catalog.get_current_values(ai_draft).move_speed) == 275, "manual control model reflects applied values", failures)
	_expect(ai_draft.character_document == manual_draft.character_document and ai_draft.move_documents == manual_draft.move_documents, "AI and manual paths produce identical creator documents", failures)
	var ai_digest: String = _digest_for(ai_draft)
	var manual_digest: String = _digest_for(manual_draft)
	_expect(not ai_digest.is_empty() and ai_digest == manual_digest, "same final tuning produces the same authoritative fighter digest", failures)
	var serialized: String = JSON.stringify(ai_draft.character_document) + JSON.stringify(ai_draft.move_documents)
	_expect(not serialized.contains("structured_mock") and not serialized.contains("provider") and not serialized.contains("prompt"), "provider, model, and prompt metadata never enter fighter config", failures)


func _digest_for(draft) -> String:
	var loader = LoaderScript.new()
	var errors: Array[Dictionary] = []
	var character_data: Dictionary = loader._normalize_character(draft.character_document, "<digest>/character.json", errors)
	var moves: Dictionary = {}
	for slot: String in ["light", "heavy"]:
		var move_data: Dictionary = loader._normalize_move(draft.move_documents[slot], "<digest>/%s.json" % slot, errors)
		var profile: Dictionary = loader._normalize_hitbox_profile(draft.hitbox_documents[slot], "<digest>/%s_hitbox.json" % slot, move_data, errors)
		moves[slot] = MoveScript.new(move_data, profile)
	if not errors.is_empty():
		return ""
	character_data.erase("move_refs")
	var presentation = PresentationScript.new({})
	var definition = CharacterScript.new(character_data, moves, presentation)
	var rules_result: Dictionary = loader.load_game_rules(RULES_PATH)
	if not bool(rules_result.get("ok", false)):
		return ""
	var writer = WriterScript.new()
	return writer.sha256_hex(writer.character_bytes(rules_result.definition, definition))


func _make_draft(fighter_id: String):
	var draft = DraftScript.new()
	draft.set_identity("AI2 Test Fighter", fighter_id)
	draft.set_preset("platform_fighter")
	draft.set_feel(0)
	return draft


func _remove_test_settings() -> void:
	if FileAccess.file_exists(TEST_SETTINGS_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SETTINGS_PATH))


func _expect(condition: bool, message: String, failures: PackedStringArray) -> void:
	if not condition:
		failures.append(message)


func _finish(failures: PackedStringArray) -> void:
	if failures.is_empty():
		print("[AIFighterTuningTests] PASS")
		quit(0)
		return
	for failure: String in failures:
		printerr("[AIFighterTuningTests] FAIL: %s" % failure)
	quit(1)
