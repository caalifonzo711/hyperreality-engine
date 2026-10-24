extends Node
class_name CombatSystem


# =================================================
# Player refs
# =================================================

var p1_state: PlayerState = null
var p2_state: PlayerState = null
var _p1_character_definition: RollbackFighterCharacterDefinition = null
var _p2_character_definition: RollbackFighterCharacterDefinition = null
var _game_rules_definition: RollbackFighterGameRulesDefinition = null
var _hitstun_scale_percent: Array = []
var _knockback_scale_percent: Array = []


# =================================================
# Internal rollback-critical state
# =================================================

var _light_cd_frames := {
	1: 0,
	2: 0
}

var _heavy_cd_frames := {
	1: 0,
	2: 0
}

var _hitstop_frames: int = 0
var match_over: bool = false
var winner_id: int = 0

var _combo_hits := {
	1: 0,
	2: 0,
}

var _guard_units := {
	1: 0,
	2: 0,
}


# =================================================
# Character definition injection
# =================================================

func configure_character_definitions(
	p1_definition: RollbackFighterCharacterDefinition,
	p2_definition: RollbackFighterCharacterDefinition,
	game_rules_definition: RollbackFighterGameRulesDefinition
) -> void:
	_p1_character_definition = p1_definition
	_p2_character_definition = p2_definition
	_game_rules_definition = game_rules_definition
	_hitstun_scale_percent = game_rules_definition.get_int_array(
		"combo_hitstun_percent"
	)
	_knockback_scale_percent = game_rules_definition.get_int_array(
		"combo_knockback_percent"
	)
	_guard_units[1] = p1_definition.get_int("guard_max_units")
	_guard_units[2] = p2_definition.get_int("guard_max_units")


# =================================================
# Main simulation tick
# =================================================

func tick() -> void:
	if p1_state == null or p2_state == null:
		return

	_reset_combo_if_recovered(p1_state)
	_reset_combo_if_recovered(p2_state)

	if match_over:
		return

	_tick_guard(p1_state)
	_tick_guard(p2_state)

	_tick_timers()

	if _hitstop_frames > 0:
		return

	# Always use canonical P1 then P2 order.
	_eval_attacks(p1_state, p2_state)
	_eval_attacks(p2_state, p1_state)


func _tick_timers() -> void:
	if _hitstop_frames > 0:
		_hitstop_frames -= 1

	for id in _light_cd_frames.keys():
		_light_cd_frames[id] = maxi(
			int(_light_cd_frames[id]) - 1,
			0
		)

	for id in _heavy_cd_frames.keys():
		_heavy_cd_frames[id] = maxi(
			int(_heavy_cd_frames[id]) - 1,
			0
		)


# =================================================
# Attack evaluation
# =================================================

func _eval_attacks(
	attacker: PlayerState,
	defender: PlayerState
) -> void:

	var attacker_id: int = _get_pid(attacker)

	# Only attacks in ACTIVE state can produce hits.
	if not attacker.attack_active:
		return

	# One successful hit maximum per attack.
	if attacker.hit_confirmed:
		return

	var move_definition: RollbackFighterMoveDefinition = (
		_get_move_definition(attacker)
	)
	if move_definition == null:
		return

	if attacker.attack_kind == PlayerState.AttackKind.LIGHT:
		if _light_cd_frames[attacker_id] > 0:
			return
	elif attacker.attack_kind == PlayerState.AttackKind.HEAVY:
		if _heavy_cd_frames[attacker_id] > 0:
			return
	else:
		return

	if not _attack_connects(attacker, defender, move_definition):
		return

	_do_damage(
		attacker,
		defender,
		move_definition.get_int("damage"),
		float(move_definition.get_int("knockback_x")),
		move_definition.get_int("hitstop"),
		move_definition.get_int("hitstun"),
		move_definition
	)

	if attacker.attack_kind == PlayerState.AttackKind.LIGHT:
		_light_cd_frames[attacker_id] = move_definition.get_int(
			"contact_cooldown"
		)
	elif attacker.attack_kind == PlayerState.AttackKind.HEAVY:
		_heavy_cd_frames[attacker_id] = move_definition.get_int(
			"contact_cooldown"
		)


# =================================================
# Collision selection
# =================================================

func _attack_connects(
	attacker: PlayerState,
	defender: PlayerState,
	move_definition: RollbackFighterMoveDefinition
) -> bool:
	var profile: Dictionary = move_definition.get_hitbox_profile()
	var profile_kind: String = str(profile.get("kind", ""))

	if profile_kind == "boxes":
		return _profile_attack_connects(
			attacker,
			defender,
			profile
		)

	if profile_kind == "legacy_horizontal_range":
		return _legacy_in_range(
			attacker,
			defender,
			float(int(profile.get("reach", 0))),
			float(int(profile.get("defender_half_extent", 0)))
		)

	return false


# =================================================
# Frame-authored hitbox collision
# =================================================

func _get_character_definition(
	fighter: PlayerState
) -> RollbackFighterCharacterDefinition:
	return (
		_p1_character_definition
		if fighter == p1_state
		else _p2_character_definition
	)


func _get_move_definition(
	attacker: PlayerState
) -> RollbackFighterMoveDefinition:
	var character_definition: RollbackFighterCharacterDefinition = (
		_get_character_definition(attacker)
	)
	if character_definition == null:
		return null

	match attacker.attack_kind:
		PlayerState.AttackKind.LIGHT:
			return character_definition.get_move_for_slot("light")
		PlayerState.AttackKind.HEAVY:
			return character_definition.get_move_for_slot("heavy")
		_:
			return null


func _get_profile_hitboxes(
	profile: Dictionary,
	active_frame: int
) -> Array:
	var frames_value: Variant = profile.get("frames", [])
	if not (frames_value is Array):
		return []
	var frames: Array = frames_value
	for frame_variant in frames:
		if not (frame_variant is Dictionary):
			continue

		var frame_data: Dictionary = frame_variant
		if int(frame_data.get("active_frame", -1)) == active_frame:
			var hitboxes_value: Variant = frame_data.get("hitboxes", [])
			if hitboxes_value is Array:
				return hitboxes_value
			return []

	return []


func _profile_attack_connects(
	attacker: PlayerState,
	defender: PlayerState,
	profile: Dictionary
) -> bool:
	var active_frame: int = _get_active_frame(attacker)

	if active_frame < 0:
		return false

	var hitboxes: Array = _get_profile_hitboxes(profile, active_frame)

	# If you authored no hitbox on this active frame,
	# the move cannot hit on this frame.
	if hitboxes.is_empty():
		return false

	var defender_box := _get_body_hurtbox(
		defender
	)

	for local_box_variant in hitboxes:
		if not (local_box_variant is Dictionary):
			continue

		var local_box: Dictionary = local_box_variant

		var attack_box := _make_world_box(
			attacker,
			local_box
		)

		if _boxes_overlap(
			attack_box,
			defender_box
		):
			return true

	return false


# =================================================
# Active-frame index
# =================================================

func _get_active_frame(
	attacker: PlayerState
) -> int:

	if attacker.state != PlayerState.MoveState.ACTIVE:
		return -1

	var move_definition: RollbackFighterMoveDefinition = (
		_get_move_definition(attacker)
	)
	if move_definition == null:
		return -1

	var total_active: int = move_definition.get_int("active")

	# On first ACTIVE frame:
	#
	# frames_left == total_active
	#
	# Therefore:
	#
	# total_active - frames_left == 0

	var frame_index := (
		total_active
		- attacker.frames_left
	)

	return maxi(frame_index, 0)


# =================================================
# Local box -> world box
# =================================================

func _make_world_box(
	fighter: PlayerState,
	local_box: Dictionary
) -> Dictionary:

	var x: int = int(local_box.get("x", 0))
	var y: int = int(local_box.get("y", 0))
	var w: int = int(local_box.get("width", 1))
	var h: int = int(local_box.get("height", 1))

	# Mirror around fighter origin if facing left.
	if fighter.facing < 0:
		x = -x - w

	return {
		"x": roundi(fighter.position.x) + x,
		"y": roundi(fighter.position.y) + y,
		"w": w,
		"h": h
	}


# =================================================
# Definition-driven body hurtbox
# =================================================

func _get_body_hurtbox(
	fighter: PlayerState
) -> Dictionary:
	var definition: RollbackFighterCharacterDefinition = (
		_get_character_definition(fighter)
	)

	return {
		"x": (
			roundi(fighter.position.x)
			+ definition.get_int("hurtbox_x")
		),

		"y": (
			roundi(fighter.position.y)
			+ definition.get_int("hurtbox_y")
		),

		"w": definition.get_int("hurtbox_width"),
		"h": definition.get_int("hurtbox_height")
	}


# =================================================
# Read-only runtime presentation queries
#
# These intentionally reuse the same profile lookup and world-box conversion
# as collision. They do not participate in combat resolution.
# =================================================

func get_debug_hurtbox_rect(fighter: PlayerState) -> Rect2:
	if fighter == null:
		return Rect2()

	var box: Dictionary = _get_body_hurtbox(fighter)
	return Rect2(
		float(box.get("x", 0)),
		float(box.get("y", 0)),
		float(box.get("w", 0)),
		float(box.get("h", 0))
	)


func get_debug_active_light_hitbox_rects(
	fighter: PlayerState
) -> Array[Rect2]:
	var world_rects: Array[Rect2] = []

	if fighter == null:
		return world_rects

	if (
		not fighter.attack_active
		or fighter.attack_kind != PlayerState.AttackKind.LIGHT
	):
		return world_rects

	var active_frame: int = _get_active_frame(fighter)
	if active_frame < 0:
		return world_rects

	var move_definition: RollbackFighterMoveDefinition = (
		_get_move_definition(fighter)
	)
	if move_definition == null:
		return world_rects

	var profile: Dictionary = move_definition.get_hitbox_profile()
	if str(profile.get("kind", "")) != "boxes":
		return world_rects

	for local_box_variant in _get_profile_hitboxes(profile, active_frame):
		if not (local_box_variant is Dictionary):
			continue

		var world_box: Dictionary = _make_world_box(
			fighter,
			local_box_variant
		)
		world_rects.append(Rect2(
			float(world_box.get("x", 0)),
			float(world_box.get("y", 0)),
			float(world_box.get("w", 0)),
			float(world_box.get("h", 0))
		))

	return world_rects


# =================================================
# Integer rectangle overlap
# =================================================

func _boxes_overlap(
	a: Dictionary,
	b: Dictionary
) -> bool:

	var ax := int(a["x"])
	var ay := int(a["y"])
	var aw := int(a["w"])
	var ah := int(a["h"])

	var bx := int(b["x"])
	var by := int(b["y"])
	var bw := int(b["w"])
	var bh := int(b["h"])

	return (
		ax < bx + bw
		and ax + aw > bx
		and ay < by + bh
		and ay + ah > by
	)


# =================================================
# Legacy fallback
# =================================================

func _legacy_in_range(
	attacker: PlayerState,
	defender: PlayerState,
	atk_reach: float,
	defender_half_extent: float
) -> bool:

	var dx := absf(
		defender.position.x
		- attacker.position.x
	)

	var max_dist := (
		defender_half_extent
		+ atk_reach
	)

	return dx <= max_dist


# =================================================
# Damage
# =================================================

func _do_damage(
	attacker: PlayerState,
	defender: PlayerState,
	dmg: int,
	knock_impulse: float,
	hitstop_frames: int,
	hitstun_frames: int,
	move_definition: RollbackFighterMoveDefinition
) -> void:

	# -----------------------------------------
	# Dodge / invulnerability
	# -----------------------------------------

	if defender.invulnerable:
		print("[Combat] DODGED!")

		attacker.hit_confirmed = true

		_hitstop_frames = _game_rules_definition.get_int(
			"dodge_contact_hitstop"
		)

		return


	# Prevent ACTIVE window from hitting repeatedly.
	attacker.hit_confirmed = true


	# -----------------------------------------
	# Block
	# -----------------------------------------

	var blocked: bool = _is_blocking_front_attack(attacker, defender)
	if blocked:
		dmg = _scale_percent_truncate(
			dmg,
			_game_rules_definition.get_int("blocked_chip_percent")
		)

		defender.take_damage(
			dmg,
			_game_rules_definition.get_int("blocked_hit_stun_frames")
		)
		_hitstop_frames = hitstop_frames
		_apply_blocked_guard_damage(move_definition, defender)

		print("[Combat] BLOCKED!")

	else:
		var defender_id: int = _get_pid(defender)
		var combo_hit: int = int(_combo_hits.get(defender_id, 0)) + 1
		_combo_hits[defender_id] = combo_hit

		var scale_index: int = mini(
			combo_hit - 1,
			_hitstun_scale_percent.size() - 1
		)
		var scaled_hitstun: int = _scale_percent_nearest(
			hitstun_frames,
			int(_hitstun_scale_percent[scale_index])
		)
		var scaled_knockback: int = _scale_percent_nearest(
			roundi(knock_impulse),
			int(_knockback_scale_percent[scale_index])
		)

		defender.take_damage(dmg, scaled_hitstun)

		var dir := signf(
			defender.position.x
			- attacker.position.x
		)

		if dir == 0.0:
			dir = 1.0

		defender.vel.x += (
			dir
			* float(scaled_knockback)
		)

		defender.vel.x = clampf(
			defender.vel.x,
			-defender.max_knock_speed,
			defender.max_knock_speed
		)

		if defender.state != PlayerState.MoveState.HURT:
			_combo_hits[defender_id] = 0

	if defender.hp <= 0:
		match_over = true
		winner_id = _get_pid(attacker)


	if not blocked:
		_hitstop_frames = hitstop_frames

	var attacker_id: int = _get_pid(attacker)

	print(
		"[Combat] P",
		attacker_id,
		" HIT! dmg=",
		dmg,
		" target_hp=",
		defender.hp
	)


# =================================================
# Combo scaling
# =================================================

func _reset_combo_if_recovered(defender: PlayerState) -> void:
	if defender.state == PlayerState.MoveState.HURT:
		return

	_combo_hits[_get_pid(defender)] = 0


func _scale_percent_nearest(base_value: int, percent: int) -> int:
	@warning_ignore("integer_division")
	return maxi(1, (base_value * percent + 50) / 100)


func _scale_percent_truncate(base_value: int, percent: int) -> int:
	@warning_ignore("integer_division")
	return (base_value * percent) / 100


# =================================================
# Guard resource
# =================================================

func _tick_guard(defender: PlayerState) -> void:
	var defender_id: int = _get_pid(defender)
	var definition: RollbackFighterCharacterDefinition = (
		_get_character_definition(defender)
	)
	var guard_units: int = int(_guard_units[defender_id])

	if defender.state == PlayerState.MoveState.BLOCK:
		guard_units = maxi(
			guard_units - definition.get_int("guard_held_drain_per_frame"),
			0
		)
		_guard_units[defender_id] = guard_units

		if guard_units <= 0:
			_trigger_guard_break(defender)

	elif not defender.blocking:
		_guard_units[defender_id] = mini(
			guard_units + definition.get_int("guard_regen_per_frame"),
			definition.get_int("guard_max_units")
		)


func _apply_blocked_guard_damage(
	move_definition: RollbackFighterMoveDefinition,
	defender: PlayerState
) -> void:
	var guard_damage: int = move_definition.get_int("guard_damage")

	var defender_id: int = _get_pid(defender)
	_guard_units[defender_id] = maxi(
		int(_guard_units[defender_id])
		- guard_damage,
		0
	)

	if int(_guard_units[defender_id]) <= 0:
		_trigger_guard_break(defender)


func _trigger_guard_break(defender: PlayerState) -> void:
	var defender_id: int = _get_pid(defender)
	var definition: RollbackFighterCharacterDefinition = (
		_get_character_definition(defender)
	)
	_combo_hits[defender_id] = 0
	_guard_units[defender_id] = definition.get_int("guard_break_refill_units")
	defender.take_damage(0, definition.get_int("guard_break_stun_frames"))


# =================================================
# Directional block
# =================================================

func _is_blocking_front_attack(
	attacker: PlayerState,
	defender: PlayerState
) -> bool:
	if defender.state != PlayerState.MoveState.BLOCK:
		return false

	var attack_side: float = signf(
		attacker.position.x - defender.position.x
	)
	if attack_side == 0.0:
		return true

	return int(attack_side) == defender.facing


# =================================================
# Player ID helper
# =================================================

func _get_pid(ps: PlayerState) -> int:
	if ps.get("player_id") != null:
		var v: Variant = ps.get("player_id")

		if (
			typeof(v) == TYPE_INT
			and int(v) != 0
		):
			return int(v)

	return 1 if ps == p1_state else 2


# =================================================
# Rollback snapshot support
# =================================================

func capture_state() -> Dictionary:
	return {
		"hitstop": _hitstop_frames,
		"match_over": match_over,
		"winner_id": winner_id,
		"combo_hits_1": int(_combo_hits.get(1, 0)),
		"combo_hits_2": int(_combo_hits.get(2, 0)),
		"guard_units_1": int(_guard_units[1]),
		"guard_units_2": int(_guard_units[2]),

		"light_cd_1": int(
			_light_cd_frames.get(1, 0)
		),

		"light_cd_2": int(
			_light_cd_frames.get(2, 0)
		),

		"heavy_cd_1": int(
			_heavy_cd_frames.get(1, 0)
		),

		"heavy_cd_2": int(
			_heavy_cd_frames.get(2, 0)
		),
	}


func restore_state(s: Dictionary) -> void:
	_hitstop_frames = int(
		s.get("hitstop", 0)
	)
	match_over = bool(s.get("match_over", false))
	winner_id = int(s.get("winner_id", 0))
	_combo_hits[1] = int(s.get("combo_hits_1", 0))
	_combo_hits[2] = int(s.get("combo_hits_2", 0))
	_guard_units[1] = int(s.get("guard_units_1", _guard_units[1]))
	_guard_units[2] = int(s.get("guard_units_2", _guard_units[2]))

	_light_cd_frames[1] = int(
		s.get("light_cd_1", 0)
	)

	_light_cd_frames[2] = int(
		s.get("light_cd_2", 0)
	)

	_heavy_cd_frames[1] = int(
		s.get("heavy_cd_1", 0)
	)

	_heavy_cd_frames[2] = int(
		s.get("heavy_cd_2", 0)
	)
