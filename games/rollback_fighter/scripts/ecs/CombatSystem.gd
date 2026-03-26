extends Node
class_name CombatSystem

# Wired by ArenaScene
var p1_state: PlayerState = null
var p2_state: PlayerState = null

# --- damage / tuning ---
const LIGHT_DMG       : int   = 5
const HEAVY_DMG       : int   = 12

# 1-D hitbox / hurtbox extents (all along X only)
const HURTBOX_HALF    : float = 8.0
const LIGHT_REACH     : float = 24.0
const HEAVY_REACH     : float = 36.0

# Deterministic cooldowns (frames)
const LIGHT_COOLDOWN_FRAMES : int = 11
const HEAVY_COOLDOWN_FRAMES : int = 27

# NOTE: These are now *impulse strengths* (vel.x += impulse), not teleport pixels
const KNOCK_X_LIGHT   : float = 280.0
const KNOCK_X_HEAVY   : float = 460.0

const HITSTOP_LIGHT   : int   = 2
const HITSTOP_HEAVY   : int   = 4

# Per-attacker cooldowns (so P1/P2 don't share one timer)
var _light_cd_frames := { 1: 0, 2: 0 }
var _heavy_cd_frames := { 1: 0, 2: 0 }

# Shared hitstop freezes the whole fight (both players)
var _hitstop_frames: int = 0


func tick() -> void:
	if p1_state == null or p2_state == null:
		return

	_tick_timers()

	if _hitstop_frames > 0:
		return

	# Evaluate BOTH directions every tick
	_eval_attacks(p1_state, p2_state)
	_eval_attacks(p2_state, p1_state)


func _tick_timers() -> void:
	# hitstop
	if _hitstop_frames > 0:
		_hitstop_frames -= 1

	# cooldown frames per attacker
	for id in _light_cd_frames.keys():
		_light_cd_frames[id] = maxi(_light_cd_frames[id] - 1, 0)
	for id in _heavy_cd_frames.keys():
		_heavy_cd_frames[id] = maxi(_heavy_cd_frames[id] - 1, 0)


func _eval_attacks(attacker: PlayerState, defender: PlayerState) -> void:
	var attacker_id: int = _get_pid(attacker)

	# Only hit during ACTIVE frames
	if not attacker.attack_active:
		return

	# Prevent multi-hit during ACTIVE window
	if attacker.hit_confirmed:
		return

	# Choose stats from attack_kind
	var reach: float = LIGHT_REACH
	var dmg: int = LIGHT_DMG
	var knock_impulse: float = KNOCK_X_LIGHT
	var hitstop: int = HITSTOP_LIGHT

	if attacker.attack_kind == PlayerState.AttackKind.HEAVY:
		reach = HEAVY_REACH
		dmg = HEAVY_DMG
		knock_impulse = KNOCK_X_HEAVY
		hitstop = HITSTOP_HEAVY

	# Optional per-attack cooldown gates
	if attacker.attack_kind == PlayerState.AttackKind.LIGHT:
		if _light_cd_frames[attacker_id] > 0:
			return
	elif attacker.attack_kind == PlayerState.AttackKind.HEAVY:
		if _heavy_cd_frames[attacker_id] > 0:
			return

	if _in_range(attacker, defender, reach):
		_do_damage(attacker, defender, dmg, knock_impulse, hitstop)

		# Start cooldown AFTER a successful hit (you can change to "on whiff too" later)
		if attacker.attack_kind == PlayerState.AttackKind.LIGHT:
			_light_cd_frames[attacker_id] = LIGHT_COOLDOWN_FRAMES
		elif attacker.attack_kind == PlayerState.AttackKind.HEAVY:
			_heavy_cd_frames[attacker_id] = HEAVY_COOLDOWN_FRAMES


# --- 1-D hitbox check ---
func _in_range(attacker: PlayerState, defender: PlayerState, atk_reach: float) -> bool:
	var dx: float = absf(defender.position.x - attacker.position.x)
	var max_dist: float = HURTBOX_HALF + atk_reach
	return dx <= max_dist


func _do_damage(attacker: PlayerState, defender: PlayerState, dmg: int, knock_impulse: float, hitstop_frames: int) -> void:
	# Dodge / invulnerability check
	if defender.invulnerable:
		print("[Combat] DODGED!")
		attacker.hit_confirmed = true
		_hitstop_frames = 1
		return

	# Mark hit confirmed so ACTIVE doesn't hit every frame
	attacker.hit_confirmed = true

	# BLOCK handling
	if defender.state == PlayerState.MoveState.BLOCK:
		dmg = int(dmg * 0.2)
		defender.take_damage(dmg)
		print("[Combat] BLOCKED!")
	else:
		defender.take_damage(dmg)

		var dir: float = signf(defender.position.x - attacker.position.x)
		if dir == 0.0:
			dir = 1.0

		defender.vel.x += dir * knock_impulse
		defender.vel.x = clampf(defender.vel.x, -defender.max_knock_speed, defender.max_knock_speed)

	_hitstop_frames = hitstop_frames

	var attacker_id: int = _get_pid(attacker)
	print("[Combat] P", attacker_id, " HIT! dmg=", dmg, "  target_hp=", defender.hp)

func _get_pid(ps: PlayerState) -> int:
	# Prefer a real typed field if you add one later; fallback to reference equality.
	# Avoids Variant inference warnings.
	if ps.get("player_id") != null:
		var v: Variant = ps.get("player_id")
		if typeof(v) == TYPE_INT and int(v) != 0:
			return int(v)
	return 1 if ps == p1_state else 2


# --- rollback snapshot support for combat internals ---
func capture_state() -> Dictionary:
	return {
		"hitstop": _hitstop_frames,
		"light_cd_1": int(_light_cd_frames.get(1, 0)),
		"light_cd_2": int(_light_cd_frames.get(2, 0)),
		"heavy_cd_1": int(_heavy_cd_frames.get(1, 0)),
		"heavy_cd_2": int(_heavy_cd_frames.get(2, 0)),
	}

func restore_state(s: Dictionary) -> void:
	_hitstop_frames = int(s.get("hitstop", 0))

	_light_cd_frames[1] = int(s.get("light_cd_1", 0))
	_light_cd_frames[2] = int(s.get("light_cd_2", 0))
	_heavy_cd_frames[1] = int(s.get("heavy_cd_1", 0))
	_heavy_cd_frames[2] = int(s.get("heavy_cd_2", 0))
