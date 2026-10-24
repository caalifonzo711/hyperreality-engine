extends SceneTree


const LoaderScript = preload(
	"res://games/rollback_fighter/scripts/config/CharacterDefinitionLoader.gd"
)
const WriterScript = preload(
	"res://games/rollback_fighter/scripts/config/CanonicalConfigWriter.gd"
)
const PlayerStateScript = preload(
	"res://games/rollback_fighter/scripts/ecs/PlayerState.gd"
)
const CombatSystemScript = preload(
	"res://games/rollback_fighter/scripts/ecs/CombatSystem.gd"
)
const AdapterScript = preload(
	"res://games/rollback_fighter/scripts/net/FighterRollbackAdapter.gd"
)
const MatchConfigHandshakeScript = preload(
	"res://games/rollback_fighter/scripts/config/MatchConfigHandshake.gd"
)

const RULES_PATH := "res://games/rollback_fighter/config/game_rules.json"
const REGISTRY_PATH := "res://games/rollback_fighter/config/builtin_fighters.json"
const CHARACTER_PATH := "res://games/rollback_fighter/characters/example_fighter/character.json"
const PRESENTATION_PATH := "res://games/rollback_fighter/characters/example_fighter/presentation.json"
const CHARACTER_ROOT := "res://games/rollback_fighter/characters/example_fighter"
const EXPECTED_CANONICAL_BYTE_LENGTH := 735
const EXPECTED_AUTH_DIGEST := \
	"2cc92852ed7d9e0a7217209b2e31c129205e74bbe5efe5571619207afb55e23b"


func _initialize() -> void:
	var failures := PackedStringArray()
	var loader = LoaderScript.new()
	var rules_result: Dictionary = loader.load_game_rules(RULES_PATH)
	var first_result: Dictionary = loader.load_builtin_fighter(REGISTRY_PATH, "example_fighter")
	var second_result: Dictionary = loader.load_builtin_fighter(REGISTRY_PATH, "example_fighter")
	_expect(bool(rules_result.get("ok", false)), "valid game rules load", failures)
	_expect(bool(first_result.get("ok", false)), "valid example fighter loads", failures)
	_expect(bool(second_result.get("ok", false)), "repeated example fighter load succeeds", failures)

	if failures.is_empty():
		var writer = WriterScript.new()
		var first_bytes: PackedByteArray = writer.character_bytes(rules_result["definition"], first_result["definition"])
		var first_digest: String = writer.sha256_hex(first_bytes)
		var second_bytes: PackedByteArray = writer.character_bytes(rules_result["definition"], second_result["definition"])
		var second_digest: String = writer.sha256_hex(second_bytes)
		_expect(first_bytes == second_bytes, "repeated loads produce identical canonical bytes", failures)
		_expect(first_digest == second_digest, "repeated loads produce identical SHA-256", failures)
		_expect(first_bytes.size() == EXPECTED_CANONICAL_BYTE_LENGTH, "canonical byte length remains unchanged", failures)
		_expect(first_digest == EXPECTED_AUTH_DIGEST, "authoritative config digest remains unchanged", failures)
		_test_definition_driven_attacks(
			first_result["definition"],
			rules_result["definition"],
			failures
		)
		_test_definition_driven_fighter_stats(
			first_result["definition"],
			rules_result["definition"],
			failures
		)
		_test_definition_driven_game_rules(
			rules_result["definition"],
			first_result["definition"],
			failures
		)
		_test_presentation_definition(
			loader,
			writer,
			rules_result["definition"],
			first_result["definition"],
			first_bytes,
			failures
		)
		_test_match_config_handshake(
			writer,
			rules_result["definition"],
			first_result["definition"],
			failures
		)

	_test_fractional_number(loader, failures)
	_test_invalid_path(loader, failures)
	_test_invalid_dodge_window(loader, failures)
	_test_invalid_hitbox_frame(loader, failures)
	_test_invalid_game_rules(loader, failures)

	if failures.is_empty():
		print("[CharacterDefinitionTests] PASS")
		quit(0)
		return

	for failure in failures:
		printerr("[CharacterDefinitionTests] FAIL: %s" % failure)
	quit(1)


func _test_fractional_number(loader, failures: PackedStringArray) -> void:
	var errors: Array[Dictionary] = []
	loader._required_int({"value": 1.5}, "value", "<test>", errors)
	_expect(_has_code(errors, "CFG_NUMBER_FRACTIONAL"), "fractional authoritative value rejected", failures)


func _test_invalid_path(loader, failures: PackedStringArray) -> void:
	var errors: Array[Dictionary] = []
	loader._resolve_reference("res://fighter", "../escape.json", "<test>", "path", errors)
	_expect(_has_code(errors, "CFG_RESOURCE_REFERENCE_INVALID"), "invalid root-relative path rejected", failures)


func _test_invalid_dodge_window(loader, failures: PackedStringArray) -> void:
	var errors: Array[Dictionary] = []
	var raw: Dictionary = loader._load_json(CHARACTER_PATH, errors)
	if not raw.is_empty():
		var dodge: Dictionary = raw["dodge"]
		dodge["invuln_end"] = int(dodge["total_frames"])
		loader._normalize_character(raw, CHARACTER_PATH, errors)
	_expect(_has_code(errors, "CFG_DODGE_WINDOW_INVALID"), "invalid dodge window rejected", failures)


func _test_invalid_hitbox_frame(loader, failures: PackedStringArray) -> void:
	var errors: Array[Dictionary] = []
	var move := {"id": "jab", "active": 2}
	var profile := {
		"config_version": 1,
		"move_id": "jab",
		"frames": [
			{
				"active_frame": 2,
				"hitboxes": [
					{"x": 0, "y": 0, "width": 1, "height": 1},
				],
			},
		],
	}
	loader._normalize_hitbox_profile(profile, "<test>", move, errors)
	_expect(_has_code(errors, "CFG_HITBOX_FRAME_OUT_OF_RANGE"), "invalid hitbox active frame rejected", failures)


func _test_invalid_game_rules(loader, failures: PackedStringArray) -> void:
	var errors: Array[Dictionary] = []
	var raw: Dictionary = loader._load_json(RULES_PATH, errors)
	if not raw.is_empty():
		raw["simulation_hz"] = 59
		loader._normalize_game_rules(raw, RULES_PATH, errors)
	_expect(
		_has_code(errors, "CFG_SIMULATION_HZ_INVALID"),
		"invalid GameRulesDefinition prevents definition-mode setup",
		failures
	)


func _test_presentation_definition(
	loader,
	writer,
	rules_definition: RollbackFighterGameRulesDefinition,
	character_definition: RollbackFighterCharacterDefinition,
	authoritative_bytes: PackedByteArray,
	failures: PackedStringArray
) -> void:
	var presentation: RollbackFighterPresentationDefinition = (
		character_definition.get_presentation()
	)
	_expect(
		presentation.get_animation_ids()
		== PackedStringArray(["block", "dead", "dodge", "heavy", "hit", "idle", "jab"]),
		"PresentationDefinition loads every expected animation",
		failures
	)
	_expect(
		presentation.get_source_art_faces() == "left",
		"source-art facing resolves from PresentationDefinition",
		failures
	)
	_expect(
		presentation.get_state_animation_id("idle") == "idle"
		and presentation.get_state_animation_id("block") == "block"
		and presentation.get_state_animation_id("dodge") == "dodge"
		and presentation.get_state_animation_id("hurt") == "hit"
		and presentation.get_state_animation_id("dead") == "dead",
		"state-to-animation mappings resolve from PresentationDefinition",
		failures
	)
	_expect(
		presentation.get_attack_phase_frames("jab", "startup") == [0]
		and presentation.get_attack_phase_frames("jab", "active") == [1]
		and presentation.get_attack_phase_frames("jab", "recovery") == [0]
		and presentation.get_attack_phase_frames("heavy", "startup") == [0]
		and presentation.get_attack_phase_frames("heavy", "active") == [1]
		and presentation.get_attack_phase_frames("heavy", "recovery") == [0],
		"attack phase-to-frame mappings resolve from PresentationDefinition",
		failures
	)

	var idle: Dictionary = presentation.get_animation("idle")
	var idle_frames: Array = idle["frames"]
	var idle_zero: Dictionary = idle_frames[0]
	var idle_anchor: Dictionary = idle_zero["feet_anchor"]
	_expect(
		int(idle["fps_milli"]) == 8000
		and str(idle_zero["sprite"]) == "%s/sprites/idle_0.png" % CHARACTER_ROOT
		and int(idle_anchor["x"]) == 288
		and int(idle_anchor["y"]) == 416
		and int(idle_zero["scale_milli"]) == 135,
		"sprite, FPS, feet anchor, and scale resolve per presentation frame",
		failures
	)
	for animation_id in presentation.get_animation_ids():
		var animation: Dictionary = presentation.get_animation(animation_id)
		for frame_variant in animation["frames"]:
			var frame: Dictionary = frame_variant
			_expect(
				ResourceLoader.exists(str(frame["sprite"])),
				"presentation sprite resolves: %s" % str(frame["sprite"]),
				failures
			)

	var jab: Dictionary = presentation.get_animation("jab")
	var heavy: Dictionary = presentation.get_animation("heavy")
	var jab_frames: Array = jab["frames"]
	var heavy_frames: Array = heavy["frames"]
	var jab_zero: Dictionary = jab_frames[0]
	var jab_one: Dictionary = jab_frames[1]
	var heavy_zero: Dictionary = heavy_frames[0]
	var heavy_one: Dictionary = heavy_frames[1]
	_expect(
		str(heavy_zero["sprite"]) == str(jab_zero["sprite"])
		and str(heavy_one["sprite"]) == str(jab_one["sprite"]),
		"heavy presentation explicitly uses the jab placeholder art",
		failures
	)

	var changed_presentation_data: Dictionary = presentation.get_data()
	var animations: Dictionary = changed_presentation_data["animations"]
	var changed_idle: Dictionary = animations["idle"]
	var changed_frames: Array = changed_idle["frames"]
	var changed_frame: Dictionary = changed_frames[0]
	changed_frame["scale_milli"] = 999
	var changed_definition: RollbackFighterCharacterDefinition = (
		RollbackFighterCharacterDefinition.new(
		character_definition.get_authoritative_data(),
		{
			"light": character_definition.get_move_for_slot("light"),
			"heavy": character_definition.get_move_for_slot("heavy"),
		},
		RollbackFighterPresentationDefinition.new(changed_presentation_data)
		)
	)
	_expect(
		writer.character_bytes(rules_definition, changed_definition)
		== authoritative_bytes,
		"presentation values do not affect authoritative canonical bytes",
		failures
	)

	_test_invalid_presentation_sprite(loader, character_definition, failures)
	_test_invalid_presentation_mapping(loader, character_definition, failures)
	_test_invalid_presentation_anchor(loader, character_definition, failures)


func _test_invalid_presentation_sprite(
	loader,
	character_definition: RollbackFighterCharacterDefinition,
	failures: PackedStringArray
) -> void:
	var errors: Array[Dictionary] = []
	var raw: Dictionary = loader._load_json(PRESENTATION_PATH, errors)
	var animations: Dictionary = raw["animations"]
	var idle: Dictionary = animations["idle"]
	var frames: Array = idle["frames"]
	var frame: Dictionary = frames[0]
	frame["sprite"] = "sprites/does_not_exist.png"
	loader._normalize_presentation(
		raw,
		PRESENTATION_PATH,
		CHARACTER_ROOT,
		_move_slots(character_definition),
		errors
	)
	_expect(_has_code(errors, "CFG_SPRITE_MISSING"), "invalid sprite path is rejected", failures)


func _test_invalid_presentation_mapping(
	loader,
	character_definition: RollbackFighterCharacterDefinition,
	failures: PackedStringArray
) -> void:
	var errors: Array[Dictionary] = []
	var raw: Dictionary = loader._load_json(PRESENTATION_PATH, errors)
	var state_map: Dictionary = raw["state_to_animation"]
	state_map["idle"] = "missing_animation"
	loader._normalize_presentation(
		raw,
		PRESENTATION_PATH,
		CHARACTER_ROOT,
		_move_slots(character_definition),
		errors
	)
	_expect(
		_has_code(errors, "CFG_PRESENTATION_ANIMATION_MISSING"),
		"invalid animation mapping is rejected",
		failures
	)


func _test_invalid_presentation_anchor(
	loader,
	character_definition: RollbackFighterCharacterDefinition,
	failures: PackedStringArray
) -> void:
	var errors: Array[Dictionary] = []
	var raw: Dictionary = loader._load_json(PRESENTATION_PATH, errors)
	var animations: Dictionary = raw["animations"]
	var idle: Dictionary = animations["idle"]
	var frames: Array = idle["frames"]
	var frame: Dictionary = frames[0]
	frame.erase("feet_anchor")
	loader._normalize_presentation(
		raw,
		PRESENTATION_PATH,
		CHARACTER_ROOT,
		_move_slots(character_definition),
		errors
	)
	_expect(_has_code(errors, "CFG_OBJECT_INVALID"), "missing feet anchor is rejected", failures)


func _move_slots(
	character_definition: RollbackFighterCharacterDefinition
) -> Dictionary:
	return {
		"light": character_definition.get_move_for_slot("light"),
		"heavy": character_definition.get_move_for_slot("heavy"),
	}


func _test_match_config_handshake(
	writer: RollbackFighterCanonicalConfigWriter,
	rules: RollbackFighterGameRulesDefinition,
	base: RollbackFighterCharacterDefinition,
	failures: PackedStringArray
) -> void:
	var handshake: RollbackFighterMatchConfigHandshake = (
		MatchConfigHandshakeScript.new()
	)
	var local_identity: Dictionary = handshake.build_local_identity(
		writer,
		rules,
		base,
		base
	)
	handshake.local_identity = local_identity.duplicate(true)
	_expect(
		int(local_identity["canonical_byte_length"])
		== EXPECTED_CANONICAL_BYTE_LENGTH
		and str(local_identity["digest"]) == EXPECTED_AUTH_DIGEST,
		"identical P1/P2 definitions preserve the established digest and length",
		failures
	)
	_expect(
		not handshake.may_start_match(true),
		"network match cannot start before config verification",
		failures
	)
	_expect(
		handshake.may_start_match(false),
		"offline match does not require a remote identity",
		failures
	)
	var identical_result: Dictionary = handshake.accept_remote_identity(
		local_identity.duplicate(true)
	)
	_expect(
		bool(identical_result["ok"])
		and handshake.can_start_network_match(),
		"identical local and remote config identities pass",
		failures
	)

	var bad_digest_identity: Dictionary = local_identity.duplicate(true)
	bad_digest_identity["digest"] = "not-a-digest"
	var malformed_result: Dictionary = handshake.accept_remote_identity(
		bad_digest_identity
	)
	_expect(
		not bool(malformed_result["ok"])
		and not handshake.can_start_network_match(),
		"malformed digest is rejected and keeps network start gated",
		failures
	)

	var version_identity: Dictionary = local_identity.duplicate(true)
	version_identity["protocol_version"] = 2
	var version_result: Dictionary = handshake.accept_remote_identity(
		version_identity
	)
	_expect(
		str(version_result["message"]) == "CONFIG HANDSHAKE VERSION MISMATCH",
		"handshake protocol version mismatch is rejected clearly",
		failures
	)

	var fighter_identity: Dictionary = local_identity.duplicate(true)
	fighter_identity["p1_id"] = "alternate_fighter"
	var fighter_result: Dictionary = handshake.accept_remote_identity(
		fighter_identity
	)
	_expect(
		str(fighter_result["message"]).contains("Fighter ID mismatch"),
		"fighter ID mismatch is diagnosed explicitly",
		failures
	)

	var changed_move_auth: Dictionary = (
		base.get_move_for_slot("light").get_authoritative_data()
	)
	changed_move_auth["damage"] = int(changed_move_auth["damage"]) + 1
	var changed_move: RollbackFighterMoveDefinition = (
		RollbackFighterMoveDefinition.new(
			changed_move_auth,
			base.get_move_for_slot("light").get_hitbox_profile()
		)
	)
	var changed_move_character: RollbackFighterCharacterDefinition = (
		RollbackFighterCharacterDefinition.new(
			base.get_authoritative_data(),
			{
				"light": changed_move,
				"heavy": base.get_move_for_slot("heavy"),
			},
			base.get_presentation()
		)
	)
	var changed_move_identity: Dictionary = _identity_for(
		writer,
		rules,
		changed_move_character,
		base
	)
	_expect(
		str(changed_move_identity["digest"]) != str(local_identity["digest"])
		and _identity_is_rejected(local_identity, changed_move_identity),
		"changed move value fails config compatibility",
		failures
	)

	var changed_character_auth: Dictionary = base.get_authoritative_data()
	changed_character_auth["max_hp"] = int(changed_character_auth["max_hp"]) + 1
	var changed_character: RollbackFighterCharacterDefinition = (
		RollbackFighterCharacterDefinition.new(
			changed_character_auth,
			_move_slots(base),
			base.get_presentation()
		)
	)
	var changed_character_identity: Dictionary = _identity_for(
		writer,
		rules,
		changed_character,
		base
	)
	_expect(
		str(changed_character_identity["digest"]) != str(local_identity["digest"])
		and _identity_is_rejected(local_identity, changed_character_identity),
		"changed character value fails config compatibility",
		failures
	)
	var changed_p2_identity: Dictionary = _identity_for(
		writer,
		rules,
		base,
		changed_character
	)
	_expect(
		str(changed_p2_identity["digest"]) != str(local_identity["digest"])
		and str(changed_p2_identity["digest"])
		!= str(changed_character_identity["digest"]),
		"P2 config is included in slot order in the match digest",
		failures
	)

	var changed_rules_auth: Dictionary = rules.get_authoritative_data()
	changed_rules_auth["light_input_buffer_frames"] = int(
		changed_rules_auth["light_input_buffer_frames"]
	) + 1
	var changed_rules: RollbackFighterGameRulesDefinition = (
		RollbackFighterGameRulesDefinition.new(changed_rules_auth)
	)
	var changed_rules_identity: Dictionary = _identity_for(
		writer,
		changed_rules,
		base,
		base
	)
	_expect(
		str(changed_rules_identity["digest"]) != str(local_identity["digest"])
		and _identity_is_rejected(local_identity, changed_rules_identity),
		"changed GameRules value fails config compatibility",
		failures
	)

	var changed_presentation_data: Dictionary = base.get_presentation().get_data()
	var animations: Dictionary = changed_presentation_data["animations"]
	var idle: Dictionary = animations["idle"]
	var frames: Array = idle["frames"]
	var idle_frame: Dictionary = frames[0]
	idle_frame["scale_milli"] = int(idle_frame["scale_milli"]) + 1
	var presentation_only_character: RollbackFighterCharacterDefinition = (
		RollbackFighterCharacterDefinition.new(
			base.get_authoritative_data(),
			_move_slots(base),
			RollbackFighterPresentationDefinition.new(changed_presentation_data)
		)
	)
	_expect(
		str(_identity_for(writer, rules, presentation_only_character, base)["digest"])
		== str(local_identity["digest"])
		and not _identity_is_rejected(
			local_identity,
			_identity_for(writer, rules, presentation_only_character, base)
		),
		"presentation-only change leaves match digest unchanged",
		failures
	)


func _identity_for(
	writer: RollbackFighterCanonicalConfigWriter,
	rules: RollbackFighterGameRulesDefinition,
	p1: RollbackFighterCharacterDefinition,
	p2: RollbackFighterCharacterDefinition
) -> Dictionary:
	var handshake: RollbackFighterMatchConfigHandshake = (
		MatchConfigHandshakeScript.new()
	)
	return handshake.build_local_identity(writer, rules, p1, p2)


func _identity_is_rejected(local_identity: Dictionary, candidate: Dictionary) -> bool:
	var handshake: RollbackFighterMatchConfigHandshake = (
		MatchConfigHandshakeScript.new()
	)
	handshake.local_identity = local_identity.duplicate(true)
	var result: Dictionary = handshake.accept_remote_identity(candidate)
	return not bool(result.get("ok", false)) and not handshake.can_start_network_match()


func _test_definition_driven_attacks(
	character_definition: RollbackFighterCharacterDefinition,
	rules_definition: RollbackFighterGameRulesDefinition,
	failures: PackedStringArray
) -> void:
	var p1: PlayerState = PlayerStateScript.new()
	var p2: PlayerState = PlayerStateScript.new()
	var combat: CombatSystem = CombatSystemScript.new()
	p1.configure_character_definition(character_definition)
	p2.configure_character_definition(character_definition)
	combat.p1_state = p1
	combat.p2_state = p2
	combat.configure_character_definitions(
		character_definition,
		character_definition,
		rules_definition
	)

	p1.try_start_attack(PlayerState.AttackKind.LIGHT)
	_expect(p1.frames_left == 2, "light startup resolves from MoveDefinition", failures)
	p1.state = PlayerState.MoveState.IDLE
	p1.try_start_attack(PlayerState.AttackKind.HEAVY)
	_expect(p1.frames_left == 6, "heavy startup resolves from MoveDefinition", failures)

	var light: RollbackFighterMoveDefinition = (
		character_definition.get_move_for_slot("light")
	)
	var heavy: RollbackFighterMoveDefinition = (
		character_definition.get_move_for_slot("heavy")
	)
	_expect(light.get_int("damage") == 7, "light damage resolves from MoveDefinition", failures)
	_expect(light.get_int("guard_damage") == 30, "light guard damage resolves from MoveDefinition", failures)
	_expect(heavy.get_int("damage") == 14, "heavy damage resolves from MoveDefinition", failures)
	_expect(heavy.get_int("guard_damage") == 90, "heavy guard damage resolves from MoveDefinition", failures)

	p1.position = Vector2(200.0, 250.0)
	p2.position = Vector2(260.0, 250.0)
	p1.attack_kind = PlayerState.AttackKind.LIGHT
	p1.state = PlayerState.MoveState.ACTIVE
	p1.attack_active = true
	p1.frames_left = 2
	_expect(not combat._attack_connects(p1, p2, light), "jab has no frame-zero hitbox", failures)
	p1.frames_left = 1
	_expect(combat._attack_connects(p1, p2, light), "jab frame-one hitbox connects", failures)
	var jab_rects: Array[Rect2] = combat.get_debug_active_light_hitbox_rects(p1)
	_expect(jab_rects.size() == 1, "jab exposes one authored hitbox on frame one", failures)
	if jab_rects.size() == 1:
		_expect(jab_rects[0] == Rect2(230.0, 210.0, 40.0, 20.0), "jab authored geometry remains 30,-40,40,20", failures)

	p1.hit_confirmed = false
	p2.state = PlayerState.MoveState.IDLE
	combat.tick()
	var combat_state: Dictionary = combat.capture_state()
	_expect(p2.hp == 93, "live light damage resolves from MoveDefinition", failures)
	_expect(p2.hurt_frames == 9, "live light hitstun resolves from MoveDefinition", failures)
	_expect(p2.vel.x == 220.0, "live light knockback resolves from MoveDefinition", failures)
	_expect(int(combat_state["hitstop"]) == 3, "live light hitstop resolves from MoveDefinition", failures)
	_expect(int(combat_state["light_cd_1"]) == 6, "live light cooldown resolves from MoveDefinition", failures)
	_expect(
		[
			combat._scale_percent_nearest(9, 100),
			combat._scale_percent_nearest(9, 85),
			combat._scale_percent_nearest(9, 70),
			combat._scale_percent_nearest(9, 55),
		] == [9, 8, 6, 5],
		"jab hitstun scaling remains unchanged",
		failures
	)
	_expect(
		[
			combat._scale_percent_nearest(220, 100),
			combat._scale_percent_nearest(220, 115),
			combat._scale_percent_nearest(220, 135),
			combat._scale_percent_nearest(220, 160),
		] == [220, 253, 297, 352],
		"jab knockback scaling remains unchanged",
		failures
	)
	_expect(
		[
			combat._scale_percent_nearest(12, 100),
			combat._scale_percent_nearest(12, 85),
			combat._scale_percent_nearest(12, 70),
			combat._scale_percent_nearest(12, 55),
		] == [12, 10, 8, 7],
		"heavy hitstun scaling remains unchanged",
		failures
	)
	_expect(
		[
			combat._scale_percent_nearest(600, 100),
			combat._scale_percent_nearest(600, 115),
			combat._scale_percent_nearest(600, 135),
			combat._scale_percent_nearest(600, 160),
		] == [600, 690, 810, 960],
		"heavy knockback scaling remains unchanged",
		failures
	)

	combat.restore_state({
		"hitstop": 0,
		"guard_units_1": 300,
		"guard_units_2": 300,
	})
	combat._apply_blocked_guard_damage(heavy, p2)
	combat_state = combat.capture_state()
	_expect(int(combat_state["guard_units_2"]) == 210, "live heavy guard damage resolves from MoveDefinition", failures)

	p1.position = Vector2.ZERO
	p2.position = Vector2(64.0, 0.0)
	p1.attack_kind = PlayerState.AttackKind.HEAVY
	_expect(combat._attack_connects(p1, p2, heavy), "heavy legacy range includes 64 pixels", failures)
	p2.position.x = 64.01
	_expect(not combat._attack_connects(p1, p2, heavy), "heavy legacy range excludes beyond 64 pixels", failures)

	p1.free()
	p2.free()
	combat.free()


func _test_definition_driven_fighter_stats(
	base_definition: RollbackFighterCharacterDefinition,
	rules_definition: RollbackFighterGameRulesDefinition,
	failures: PackedStringArray
) -> void:
	var alternate_data: Dictionary = base_definition.get_authoritative_data()
	alternate_data["max_hp"] = 137
	alternate_data["move_speed"] = 280
	alternate_data["acceleration"] = 7200
	alternate_data["braking"] = 9600
	alternate_data["reversal_acceleration"] = 10800
	alternate_data["knockback_friction"] = 450
	alternate_data["max_knockback_speed"] = 900
	alternate_data["hurtbox_x"] = -20
	alternate_data["hurtbox_y"] = -60
	alternate_data["hurtbox_width"] = 30
	alternate_data["hurtbox_height"] = 60
	alternate_data["guard_max_units"] = 420
	alternate_data["guard_held_drain_per_frame"] = 3
	alternate_data["guard_regen_per_frame"] = 5
	alternate_data["guard_break_refill_units"] = 222
	alternate_data["guard_break_stun_frames"] = 33
	alternate_data["dodge_total_frames"] = 20
	alternate_data["dodge_invuln_start"] = 3
	alternate_data["dodge_invuln_end"] = 8
	alternate_data["dodge_cooldown_frames"] = 31
	var alternate_definition: RollbackFighterCharacterDefinition = (
		RollbackFighterCharacterDefinition.new(
			alternate_data,
			{
				"light": base_definition.get_move_for_slot("light"),
				"heavy": base_definition.get_move_for_slot("heavy"),
			},
			base_definition.get_presentation()
		)
	)

	var p1: PlayerState = PlayerStateScript.new()
	var p2: PlayerState = PlayerStateScript.new()
	var combat: CombatSystem = CombatSystemScript.new()
	p1.configure_character_definition(base_definition)
	p2.configure_character_definition(alternate_definition)
	combat.p1_state = p1
	combat.p2_state = p2
	combat.configure_character_definitions(
		base_definition,
		alternate_definition,
		rules_definition
	)

	_expect(p1.hp == 100 and p1.max_hp == 100, "P1 HP initializes from CharacterDefinition", failures)
	_expect(p2.hp == 137 and p2.max_hp == 137, "P2 HP initializes from its own CharacterDefinition", failures)
	_expect(p1.move_speed == 320.0 and p2.move_speed == 280.0, "movement speed remains fighter-specific", failures)
	_expect(
		p1.ground_acceleration == 14400.0
		and p1.ground_braking == 19200.0
		and p1.reversal_acceleration == 28800.0,
		"P1 acceleration, braking, and reversal resolve from CharacterDefinition",
		failures
	)
	_expect(
		p2.ground_acceleration == 7200.0
		and p2.ground_braking == 9600.0
		and p2.reversal_acceleration == 10800.0,
		"P2 movement rates do not cross-wire from P1",
		failures
	)
	_expect(
		p1.ground_friction == 900.0
		and p1.max_knock_speed == 1100.0
		and p2.ground_friction == 450.0
		and p2.max_knock_speed == 900.0,
		"knockback friction and cap remain fighter-specific",
		failures
	)
	_expect(
		p1.dodge_total_frames == 16
		and p1.dodge_invuln_start == 2
		and p1.dodge_invuln_end == 6
		and p1.dodge_cooldown_duration == 24,
		"P1 dodge values resolve from CharacterDefinition",
		failures
	)
	_expect(
		p2.dodge_total_frames == 20
		and p2.dodge_invuln_start == 3
		and p2.dodge_invuln_end == 8
		and p2.dodge_cooldown_duration == 31,
		"P2 dodge values do not cross-wire from P1",
		failures
	)

	p1.position = Vector2(100.0, 100.0)
	p2.position = Vector2(200.0, 100.0)
	_expect(
		combat.get_debug_hurtbox_rect(p1) == Rect2(90.0, 52.0, 20.0, 48.0),
		"P1 hurtbox uses P1 CharacterDefinition",
		failures
	)
	_expect(
		combat.get_debug_hurtbox_rect(p2) == Rect2(180.0, 40.0, 30.0, 60.0),
		"P2 hurtbox uses P2 CharacterDefinition",
		failures
	)

	var combat_state: Dictionary = combat.capture_state()
	_expect(
		int(combat_state["guard_units_1"]) == 300
		and int(combat_state["guard_units_2"]) == 420,
		"guard initializes from each fighter definition",
		failures
	)
	p1.state = PlayerState.MoveState.BLOCK
	p2.state = PlayerState.MoveState.BLOCK
	combat.tick()
	combat_state = combat.capture_state()
	_expect(
		int(combat_state["guard_units_1"]) == 299
		and int(combat_state["guard_units_2"]) == 417,
		"guard held drain remains fighter-specific",
		failures
	)
	p1.state = PlayerState.MoveState.IDLE
	p2.state = PlayerState.MoveState.IDLE
	p1.blocking = false
	p2.blocking = false
	combat.tick()
	combat_state = combat.capture_state()
	_expect(
		int(combat_state["guard_units_1"]) == 300
		and int(combat_state["guard_units_2"]) == 420,
		"guard regeneration and maximum remain fighter-specific",
		failures
	)
	combat.restore_state({
		"guard_units_1": 300,
		"guard_units_2": 3,
	})
	p2.state = PlayerState.MoveState.BLOCK
	combat.tick()
	combat_state = combat.capture_state()
	_expect(
		int(combat_state["guard_units_2"]) == 222
		and p2.state == PlayerState.MoveState.HURT
		and p2.hurt_frames == 33,
		"guard break refill and stun use the defender definition",
		failures
	)

	p1.state = PlayerState.MoveState.IDLE
	p1.apply_input({"move": Vector2.ZERO, "dodge": true}, 1.0 / 60.0)
	_expect(not p1.invulnerable, "dodge frame 0 remains startup", failures)
	p1.apply_input({"move": Vector2.ZERO}, 1.0 / 60.0)
	_expect(not p1.invulnerable, "dodge frame 1 remains startup", failures)
	p1.apply_input({"move": Vector2.ZERO}, 1.0 / 60.0)
	_expect(p1.invulnerable, "dodge frame 2 begins definition-driven invulnerability", failures)
	for _frame in 5:
		p1.apply_input({"move": Vector2.ZERO}, 1.0 / 60.0)
	_expect(not p1.invulnerable, "dodge frame 7 begins recovery", failures)
	for _frame in 8:
		p1.apply_input({"move": Vector2.ZERO}, 1.0 / 60.0)
	_expect(
		p1.state == PlayerState.MoveState.IDLE
		and p1.dodge_cooldown_frames == 24,
		"dodge completes at 16 frames with definition-driven cooldown",
		failures
	)

	p1.free()
	p2.free()
	combat.free()


func _test_definition_driven_game_rules(
	rules_definition: RollbackFighterGameRulesDefinition,
	character_definition: RollbackFighterCharacterDefinition,
	failures: PackedStringArray
) -> void:
	_expect(rules_definition.get_int("simulation_hz") == 60, "simulation rate resolves from GameRulesDefinition", failures)
	_expect(
		rules_definition.get_int("light_input_buffer_frames") == 3
		and rules_definition.get_int("heavy_input_buffer_frames") == 3,
		"input buffer durations resolve from GameRulesDefinition",
		failures
	)
	_expect(
		rules_definition.get_int_array("combo_hitstun_percent") == [100, 85, 70, 55]
		and rules_definition.get_int_array("combo_knockback_percent") == [100, 115, 135, 160],
		"combo scaling tiers resolve from GameRulesDefinition",
		failures
	)
	_expect(
		rules_definition.get_spawn_position("p1") == Vector2i(200, 250)
		and rules_definition.get_spawn_position("p2") == Vector2i(600, 250),
		"spawn positions resolve from GameRulesDefinition",
		failures
	)
	_expect(
		rules_definition.is_world_contact_enabled()
		and rules_definition.get_world_contact_bound("left") == 0
		and rules_definition.get_world_contact_bound("right") == 800
		and rules_definition.get_world_contact_bound("top") == 0
		and rules_definition.get_world_contact_bound("bottom") == 400
		and rules_definition.get_fallback_policy() == "reject",
		"legacy contact thresholds and reject policy resolve from GameRulesDefinition",
		failures
	)

	var p1: PlayerState = PlayerStateScript.new()
	var p2: PlayerState = PlayerStateScript.new()
	var combat: CombatSystem = CombatSystemScript.new()
	p1.configure_character_definition(character_definition)
	p2.configure_character_definition(character_definition)
	combat.p1_state = p1
	combat.p2_state = p2
	combat.configure_character_definitions(
		character_definition,
		character_definition,
		rules_definition
	)
	var light: RollbackFighterMoveDefinition = (
		character_definition.get_move_for_slot("light")
	)

	p1.position = Vector2(200.0, 250.0)
	p2.position = Vector2(260.0, 250.0)
	p1.attack_kind = PlayerState.AttackKind.LIGHT
	p1.state = PlayerState.MoveState.ACTIVE
	p1.attack_active = true
	p1.frames_left = 1
	p2.state = PlayerState.MoveState.BLOCK
	p2.blocking = true
	p2.facing = -1
	combat.tick()
	_expect(p2.hp == 99, "blocked jab uses integer 20-percent chip", failures)
	_expect(p2.hurt_frames == 6, "blocked-hit stun resolves from GameRulesDefinition", failures)
	_expect(
		combat._scale_percent_truncate(14, rules_definition.get_int("blocked_chip_percent")) == 2,
		"blocked heavy preserves integer truncation semantics",
		failures
	)

	combat.restore_state({
		"hitstop": 0,
		"guard_units_1": 300,
		"guard_units_2": 300,
	})
	p1.hit_confirmed = false
	p1.attack_kind = PlayerState.AttackKind.LIGHT
	p1.state = PlayerState.MoveState.ACTIVE
	p1.attack_active = true
	p1.frames_left = 1
	p2.hp = 100
	p2.state = PlayerState.MoveState.DODGE
	p2.blocking = false
	p2.invulnerable = true
	combat.tick()
	var combat_state: Dictionary = combat.capture_state()
	_expect(
		p2.hp == 100
		and int(combat_state["hitstop"]) == 1,
		"dodge-contact hitstop resolves from GameRulesDefinition",
		failures
	)

	var combo_combat: CombatSystem = CombatSystemScript.new()
	var combo_attacker: PlayerState = PlayerStateScript.new()
	var combo_defender: PlayerState = PlayerStateScript.new()
	combo_attacker.configure_character_definition(character_definition)
	combo_defender.configure_character_definition(character_definition)
	combo_combat.p1_state = combo_attacker
	combo_combat.p2_state = combo_defender
	combo_combat.configure_character_definitions(
		character_definition,
		character_definition,
		rules_definition
	)
	combo_attacker.position = Vector2.ZERO
	combo_defender.position = Vector2(1.0, 0.0)
	var expected_jab_hitstun := [9, 8, 6, 5]
	var expected_jab_knockback := [220.0, 253.0, 297.0, 352.0]
	for index in 4:
		combo_defender.vel = Vector2.ZERO
		combo_combat._do_damage(combo_attacker, combo_defender, 7, 220.0, 3, 9, light)
		_expect(
			combo_defender.hurt_frames == int(expected_jab_hitstun[index])
			and combo_defender.vel.x == float(expected_jab_knockback[index]),
			"jab combo tier %d resolves from GameRulesDefinition" % (index + 1),
			failures
		)

	combo_defender.state = PlayerState.MoveState.IDLE
	combo_combat._reset_combo_if_recovered(combo_defender)
	var heavy: RollbackFighterMoveDefinition = (
		character_definition.get_move_for_slot("heavy")
	)
	var expected_heavy_hitstun := [12, 10, 8, 7]
	var expected_heavy_knockback := [600.0, 690.0, 810.0, 960.0]
	for index in 4:
		combo_defender.vel = Vector2.ZERO
		combo_combat._do_damage(combo_attacker, combo_defender, 14, 600.0, 7, 12, heavy)
		_expect(
			combo_defender.hurt_frames == int(expected_heavy_hitstun[index])
			and combo_defender.vel.x == float(expected_heavy_knockback[index]),
			"heavy combo tier %d resolves from GameRulesDefinition" % (index + 1),
			failures
		)

	var alternate_rule_data: Dictionary = rules_definition.get_authoritative_data()
	alternate_rule_data["light_input_buffer_frames"] = 5
	alternate_rule_data["heavy_input_buffer_frames"] = 7
	alternate_rule_data["world_contact_bounds"] = {
		"enabled": true,
		"left": -100,
		"right": 100,
		"top": -50,
		"bottom": 50,
	}
	var alternate_rules: RollbackFighterGameRulesDefinition = (
		RollbackFighterGameRulesDefinition.new(alternate_rule_data)
	)
	var adapter: FighterRollbackAdapter = AdapterScript.new()
	adapter.setup(p1, p2, null, null, combat, alternate_rules)
	adapter._update_buffers(
		{"atk_l": true, "atk_h": false},
		{"atk_l": false, "atk_h": true}
	)
	var adapter_state: Dictionary = adapter.capture()
	var buffer_state: Dictionary = adapter_state["buf"]
	_expect(
		int(buffer_state["p1_l"]) == 5
		and int(buffer_state["p2_h"]) == 7,
		"adapter buffer durations consume the injected rules instance",
		failures
	)
	p1.position = Vector2.ZERO
	adapter._derive_wall_contact(p1)
	_expect(not p1.is_touching_wall, "configured contact bounds preserve interior state", failures)
	p1.position.x = 101.0
	adapter._derive_wall_contact(p1)
	_expect(p1.is_touching_wall, "configured contact bounds drive legacy wall contact", failures)

	adapter.free()
	combo_attacker.free()
	combo_defender.free()
	combo_combat.free()
	p1.free()
	p2.free()
	combat.free()


func _has_code(errors: Array[Dictionary], expected: String) -> bool:
	for error in errors:
		if str(error.get("code", "")) == expected:
			return true
	return false


func _expect(condition: bool, message: String, failures: PackedStringArray) -> void:
	if not condition:
		failures.append(message)
