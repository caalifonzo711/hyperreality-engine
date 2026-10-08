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

const LIGHT_DMG: int = 5
const HEAVY_DMG: int = 12


# =================================================
# Temporary fallback combat ranges
#
# Heavy can continue using the old range test until
# you author a heavy.json.
# =================================================

const HURTBOX_HALF: float = 8.0
const LIGHT_REACH: float = 24.0
const HEAVY_REACH: float = 36.0


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

const LIGHT_COOLDOWN_FRAMES: int = 11
const HEAVY_COOLDOWN_FRAMES: int = 27


# =================================================
# Knockback
# =================================================

const KNOCK_X_LIGHT: float = 280.0
const KNOCK_X_HEAVY: float = 460.0


# =================================================
# Hitstop
# =================================================

const HITSTOP_LIGHT: int = 2
const HITSTOP_HEAVY: int = 4


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


	# -----------------------------------------
	# LIGHT
	# -----------------------------------------

	if attacker.attack_kind == PlayerState.AttackKind.LIGHT:
		if _light_cd_frames[attacker_id] > 0:
			return

		dmg = LIGHT_DMG
		knock_impulse = KNOCK_X_LIGHT
		hitstop = HITSTOP_LIGHT


	# -----------------------------------------
	# HEAVY
	# -----------------------------------------

	elif attacker.attack_kind == PlayerState.AttackKind.HEAVY:
		if _heavy_cd_frames[attacker_id] > 0:
			return

		dmg = HEAVY_DMG
		knock_impulse = KNOCK_X_HEAVY
		hitstop = HITSTOP_HEAVY

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
		hitstop
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
	hitstop_frames: int
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

	if defender.state == PlayerState.MoveState.BLOCK:
		dmg = int(dmg * 0.2)

		defender.take_damage(dmg)

		print("[Combat] BLOCKED!")

	else:
		defender.take_damage(dmg)

		var dir := signf(
			defender.position.x
			- attacker.position.x
		)

		if dir == 0.0:
			dir = 1.0

		defender.vel.x += (
			dir
			* knock_impulse
		)

		defender.vel.x = clampf(
			defender.vel.x,
			-defender.max_knock_speed,
			defender.max_knock_speed
		)


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
