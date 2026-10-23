extends Node
class_name CombatSystem


# =================================================
# Player refs
# =================================================

var p1_state: PlayerState = null
var p2_state: PlayerState = null


# =================================================
# Hitbox profiles
# =================================================

const JAB_HITBOX_PATH := \
	"res://games/rollback_fighter/characters/example_fighter/hitboxes/jab.json"

const HEAVY_HITBOX_PATH := \
	"res://games/rollback_fighter/characters/example_fighter/hitboxes/heavy.json"

var _jab_profile: HitboxProfile = HitboxProfile.new()
var _heavy_profile: HitboxProfile = HitboxProfile.new()

var _jab_loaded: bool = false
var _heavy_loaded: bool = false


# =================================================
# Damage / tuning
# =================================================

const LIGHT_DMG: int = 7
const HEAVY_DMG: int = 14


# =================================================
# Temporary fallback combat ranges
#
# Heavy can continue using the old range test until
# you author a heavy.json.
# =================================================

const HURTBOX_HALF: float = 8.0
const LIGHT_REACH: float = 24.0
const HEAVY_REACH: float = 56.0


# =================================================
# Default deterministic body hurtbox
#
# Temporary until you make idle/walk/block/etc
# hurtbox profiles.
#
# Coordinates are relative to PlayerState.position.
# =================================================

const BODY_HURTBOX_X: int = -10
const BODY_HURTBOX_Y: int = -48
const BODY_HURTBOX_W: int = 20
const BODY_HURTBOX_H: int = 48


# =================================================
# Cooldowns
# =================================================

const LIGHT_COOLDOWN_FRAMES: int = 6
const HEAVY_COOLDOWN_FRAMES: int = 12


# =================================================
# Knockback
# =================================================

const KNOCK_X_LIGHT: float = 220.0
const KNOCK_X_HEAVY: float = 600.0


# =================================================
# Hitstop
# =================================================

const HITSTOP_LIGHT: int = 3
const HITSTOP_HEAVY: int = 7

const HITSTUN_LIGHT: int = 9
const HITSTUN_HEAVY: int = 12

const HITSTUN_SCALE_PERCENT := [100, 85, 70, 55]
const KNOCKBACK_SCALE_PERCENT := [100, 115, 135, 160]

const GUARD_MAX_UNITS: int = 300
const GUARD_HOLD_DRAIN_UNITS: int = 1
const GUARD_REGEN_UNITS: int = 1
const GUARD_DAMAGE_LIGHT_UNITS: int = 30
const GUARD_DAMAGE_HEAVY_UNITS: int = 90
const GUARD_BREAK_REFILL_UNITS: int = 150
const GUARD_BREAK_HURT_FRAMES: int = 24


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
	1: GUARD_MAX_UNITS,
	2: GUARD_MAX_UNITS,
}


# =================================================
# Startup
# =================================================

func _ready() -> void:
	_load_hitbox_profiles()


func _load_hitbox_profiles() -> void:
	_jab_loaded = _jab_profile.load_from_file(
		JAB_HITBOX_PATH
	)

	# Heavy profile is optional for now.
	# If heavy.json doesn't exist, heavy uses the old
	# deterministic 1-D range check.
	_heavy_loaded = _heavy_profile.load_from_file(
		HEAVY_HITBOX_PATH
	)

	print(
		"[Combat] jab_hitboxes=",
		_jab_loaded,
		" heavy_hitboxes=",
		_heavy_loaded
	)


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

	var dmg: int = LIGHT_DMG
	var knock_impulse: float = KNOCK_X_LIGHT
	var hitstop: int = HITSTOP_LIGHT
	var hitstun: int = HITSTUN_LIGHT


	# -----------------------------------------
	# LIGHT
	# -----------------------------------------

	if attacker.attack_kind == PlayerState.AttackKind.LIGHT:
		if _light_cd_frames[attacker_id] > 0:
			return

		dmg = LIGHT_DMG
		knock_impulse = KNOCK_X_LIGHT
		hitstop = HITSTOP_LIGHT
		hitstun = HITSTUN_LIGHT


	# -----------------------------------------
	# HEAVY
	# -----------------------------------------

	elif attacker.attack_kind == PlayerState.AttackKind.HEAVY:
		if _heavy_cd_frames[attacker_id] > 0:
			return

		dmg = HEAVY_DMG
		knock_impulse = KNOCK_X_HEAVY
		hitstop = HITSTOP_HEAVY
		hitstun = HITSTUN_HEAVY

	else:
		return


	# -----------------------------------------
	# Actual collision test
	# -----------------------------------------

	if not _attack_connects(attacker, defender):
		return


	_do_damage(
		attacker,
		defender,
		dmg,
		knock_impulse,
		hitstop,
		hitstun
	)


	# -----------------------------------------
	# Cooldown after successful contact
	# -----------------------------------------

	if attacker.attack_kind == PlayerState.AttackKind.LIGHT:
		_light_cd_frames[attacker_id] = (
			LIGHT_COOLDOWN_FRAMES
		)

	elif attacker.attack_kind == PlayerState.AttackKind.HEAVY:
		_heavy_cd_frames[attacker_id] = (
			HEAVY_COOLDOWN_FRAMES
		)


# =================================================
# Collision selection
# =================================================

func _attack_connects(
	attacker: PlayerState,
	defender: PlayerState
) -> bool:

	# -----------------------------------------
	# Authored LIGHT hitbox
	# -----------------------------------------

	if (
		attacker.attack_kind
		== PlayerState.AttackKind.LIGHT
		and _jab_loaded
	):
		return _profile_attack_connects(
			attacker,
			defender,
			_jab_profile
		)


	# -----------------------------------------
	# Authored HEAVY hitbox
	# -----------------------------------------

	if (
		attacker.attack_kind
		== PlayerState.AttackKind.HEAVY
		and _heavy_loaded
	):
		return _profile_attack_connects(
			attacker,
			defender,
			_heavy_profile
		)


	# -----------------------------------------
	# Fallback old deterministic range check
	#
	# This keeps heavy working even before you
	# author heavy.json.
	# -----------------------------------------

	var reach := LIGHT_REACH

	if attacker.attack_kind == PlayerState.AttackKind.HEAVY:
		reach = HEAVY_REACH

	return _legacy_in_range(
		attacker,
		defender,
		reach
	)


# =================================================
# Frame-authored hitbox collision
# =================================================

func _profile_attack_connects(
	attacker: PlayerState,
	defender: PlayerState,
	profile: HitboxProfile
) -> bool:

	var active_frame := _get_active_frame(attacker)

	if active_frame < 0:
		return false

	var hitboxes: Array = profile.get_hitboxes(
		active_frame
	)

	# If you authored no hitbox on this active frame,
	# the move cannot hit on this frame.
	if hitboxes.is_empty():
		return false

	var defender_box := _get_default_body_hurtbox(
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

	var total_active: int = 1

	match attacker.attack_kind:
		PlayerState.AttackKind.LIGHT:
			total_active = int(
				attacker.generated_light_move.get(
					"active",
					1
				)
			)

		PlayerState.AttackKind.HEAVY:
			total_active = int(
				attacker.generated_heavy_move.get(
					"active",
					1
				)
			)

		_:
			return -1

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

	var x := int(local_box.get("x", 0))
	var y := int(local_box.get("y", 0))
	var w := int(local_box.get("w", 1))
	var h := int(local_box.get("h", 1))

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
# Temporary body hurtbox
# =================================================

func _get_default_body_hurtbox(
	fighter: PlayerState
) -> Dictionary:

	return {
		"x": (
			roundi(fighter.position.x)
			+ BODY_HURTBOX_X
		),

		"y": (
			roundi(fighter.position.y)
			+ BODY_HURTBOX_Y
		),

		"w": BODY_HURTBOX_W,
		"h": BODY_HURTBOX_H
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

	var box: Dictionary = _get_default_body_hurtbox(fighter)
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

	if fighter == null or not _jab_loaded:
		return world_rects

	if (
		not fighter.attack_active
		or fighter.attack_kind != PlayerState.AttackKind.LIGHT
	):
		return world_rects

	var active_frame: int = _get_active_frame(fighter)
	if active_frame < 0:
		return world_rects

	for local_box_variant in _jab_profile.get_hitboxes(active_frame):
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
	atk_reach: float
) -> bool:

	var dx := absf(
		defender.position.x
		- attacker.position.x
	)

	var max_dist := (
		HURTBOX_HALF
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
	hitstun_frames: int
) -> void:

	# -----------------------------------------
	# Dodge / invulnerability
	# -----------------------------------------

	if defender.invulnerable:
		print("[Combat] DODGED!")

		attacker.hit_confirmed = true

		_hitstop_frames = 1

		return


	# Prevent ACTIVE window from hitting repeatedly.
	attacker.hit_confirmed = true


	# -----------------------------------------
	# Block
	# -----------------------------------------

	var blocked: bool = _is_blocking_front_attack(attacker, defender)
	if blocked:
		dmg = int(dmg * 0.2)

		defender.take_damage(dmg)
		_hitstop_frames = hitstop_frames
		_apply_blocked_guard_damage(attacker, defender)

		print("[Combat] BLOCKED!")

	else:
		var defender_id: int = _get_pid(defender)
		var combo_hit: int = int(_combo_hits.get(defender_id, 0)) + 1
		_combo_hits[defender_id] = combo_hit

		var scale_index: int = mini(combo_hit - 1, 3)
		var scaled_hitstun: int = _scale_percent_nearest(
			hitstun_frames,
			int(HITSTUN_SCALE_PERCENT[scale_index])
		)
		var scaled_knockback: int = _scale_percent_nearest(
			roundi(knock_impulse),
			int(KNOCKBACK_SCALE_PERCENT[scale_index])
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


# =================================================
# Guard resource
# =================================================

func _tick_guard(defender: PlayerState) -> void:
	var defender_id: int = _get_pid(defender)
	var guard_units: int = int(
		_guard_units.get(defender_id, GUARD_MAX_UNITS)
	)

	if defender.state == PlayerState.MoveState.BLOCK:
		guard_units = maxi(
			guard_units - GUARD_HOLD_DRAIN_UNITS,
			0
		)
		_guard_units[defender_id] = guard_units

		if guard_units <= 0:
			_trigger_guard_break(defender)

	elif not defender.blocking:
		_guard_units[defender_id] = mini(
			guard_units + GUARD_REGEN_UNITS,
			GUARD_MAX_UNITS
		)


func _apply_blocked_guard_damage(
	attacker: PlayerState,
	defender: PlayerState
) -> void:
	var guard_damage: int = GUARD_DAMAGE_LIGHT_UNITS
	if attacker.attack_kind == PlayerState.AttackKind.HEAVY:
		guard_damage = GUARD_DAMAGE_HEAVY_UNITS

	var defender_id: int = _get_pid(defender)
	_guard_units[defender_id] = maxi(
		int(_guard_units.get(defender_id, GUARD_MAX_UNITS))
		- guard_damage,
		0
	)

	if int(_guard_units[defender_id]) <= 0:
		_trigger_guard_break(defender)


func _trigger_guard_break(defender: PlayerState) -> void:
	var defender_id: int = _get_pid(defender)
	_combo_hits[defender_id] = 0
	_guard_units[defender_id] = GUARD_BREAK_REFILL_UNITS
	defender.take_damage(0, GUARD_BREAK_HURT_FRAMES)


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
		"guard_units_1": int(_guard_units.get(1, GUARD_MAX_UNITS)),
		"guard_units_2": int(_guard_units.get(2, GUARD_MAX_UNITS)),

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
	_guard_units[1] = int(s.get("guard_units_1", GUARD_MAX_UNITS))
	_guard_units[2] = int(s.get("guard_units_2", GUARD_MAX_UNITS))

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
