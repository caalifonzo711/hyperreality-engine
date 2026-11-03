extends SceneTree


const DraftScript = preload("res://games/rollback_fighter/scripts/config/CreatorFighterDraft.gd")
const LoaderScript = preload("res://games/rollback_fighter/scripts/config/CharacterDefinitionLoader.gd")
const RegistryPath := "res://games/rollback_fighter/config/builtin_fighters.json"


func _initialize() -> void:
	var failures: PackedStringArray = PackedStringArray()
	var draft: RollbackFighterCreatorDraft = DraftScript.new()
	_expect(DraftScript.id_from_display_name("Red Girl") == "red_girl", "display name generates safe ID", failures)
	draft.set_identity("Red Girl", "red_girl_c1_test")
	_expect(draft.fighter_id == "red_girl_c1_test", "identity draft stores normalized safe ID", failures)
	_expect(draft.validate_identity().is_empty(), "nonduplicate valid ID accepted", failures)
	draft.set_identity("Duplicate", "example_fighter")
	_expect(not draft.validate_identity().is_empty(), "built-in duplicate ID rejected", failures)
	draft.set_identity("Red Girl", "red_girl_c1_test")
	draft.set_identity("Red Girl", "bad/../id")
	_expect(not draft.validate_identity().is_empty(), "path traversal ID rejected", failures)
	draft.set_identity("Red Girl", "red_girl_c1_test")
	_expect(draft.get_user_draft_path() == "user://characters/red_girl_c1_test", "draft path remains under user://characters", failures)

	var loader: RollbackFighterCharacterDefinitionLoader = LoaderScript.new()
	var baseline_result: Dictionary = loader.load_builtin_fighter(RegistryPath, "example_fighter")
	_expect(bool(baseline_result.get("ok", false)), "existing live fighter loads", failures)
	var live_definition: RollbackFighterCharacterDefinition = baseline_result.get("definition")
	var original_speed: int = live_definition.get_int("move_speed") if live_definition != null else -1
	for preset_id in draft.get_preset_ids():
		draft.set_preset(preset_id)
		for feel_value in [0, 1, 25, 50, 75, 99, 100]:
			draft.set_feel(int(feel_value))
			_expect(draft.validate().is_empty(), "preset/feel profile validates: %s/%d" % [preset_id, feel_value], failures)
		var char_doc: Dictionary = draft.character_document
		var movement: Dictionary = char_doc.get("movement", {})
		_expect(int(movement.get("move_speed", -1)) >= 0, "preset maps movement to integer config", failures)
		_expect(draft.get_art_slot_total() > 0, "preset produces an art-slot plan", failures)
	var previous_slots: int = draft.get_art_slot_total()
	_expect(draft.set_presentation_policy("anime_fighter", "fighter_presentation:anime_fighter:v1"), "anime presentation policy resolves", failures)
	var anime_slots: int = draft.get_art_slot_total()
	_expect(anime_slots > previous_slots, "art recommendations vary predictably by presentation policy", failures)
	draft.set_preset("platform_fighter")
	draft.set_presentation_policy("platform_fighter")
	draft.set_feel(100)
	var animations: Dictionary = draft.slot_manifest.get("animations", {})
	_expect(draft.get_required_art_slot_total() == 9, "minimum built-in-mirror art footprint is nine required images", failures)
	_expect(draft.get_optional_art_slot_total() > 0, "extra presentation drawings are optional", failures)
	var heavy_phases: Dictionary = animations.get("heavy", {})
	var startup: Dictionary = heavy_phases.get("startup", {})
	var jab_phases: Dictionary = animations.get("jab", {})
	var jab_recovery: Dictionary = jab_phases.get("recovery", {})
	var jab_recovery_slots: Array = jab_recovery.get("slots", [])
	_expect(not jab_recovery_slots.is_empty() and not bool(jab_recovery_slots[0].get("required", true)), "jab recovery art is optional because recovery reuses frame zero", failures)
	var heavy_startup_slots: Array = startup.get("slots", [])
	_expect(not heavy_startup_slots.is_empty() and not bool(heavy_startup_slots[0].get("required", true)), "dedicated heavy art is optional", failures)
	_expect(int(startup.get("simulation_frames", 0)) > int(startup.get("recommended_drawings", 0)), "art count is distinguished from simulation frames", failures)

	if live_definition != null:
		_expect(live_definition.get_int("move_speed") == original_speed, "draft edits do not mutate active CharacterDefinition", failures)
	_expect(draft.validate_identity().is_empty(), "draft remains identity-valid", failures)

	if failures.is_empty():
		print("[CreatorDraftTests] PASS")
		quit(0)
		return
	for failure in failures:
		printerr("[CreatorDraftTests] FAIL: %s" % failure)
	quit(1)


func _expect(condition: bool, message: String, failures: PackedStringArray) -> void:
	if not condition:
		failures.append(message)
