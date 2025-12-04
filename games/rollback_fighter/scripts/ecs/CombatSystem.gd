extends Node
class_name CombatSystem

# Wired by ArenaScene
var player_state : PlayerState = null
var target_state : PlayerState = null

# --- damage / tuning ---
const LIGHT_DMG       : int   = 5
const HEAVY_DMG       : int   = 12

# 1-D hitbox / hurtbox extents (all along X only)
# Think of these as "half widths" of rectangles centered on the players.
const HURTBOX_HALF    : float = 8.0    # target's body half-width
const LIGHT_REACH     : float = 24.0   # extra reach of light attack
const HEAVY_REACH     : float = 36.0   # extra reach of heavy attack

const LIGHT_COOLDOWN  : float = 0.18
const HEAVY_COOLDOWN  : float = 0.45
const KNOCK_X_LIGHT   : float = 28.0
const KNOCK_X_HEAVY   : float = 46.0
const HITSTOP_LIGHT   : int   = 2      # frames
const HITSTOP_HEAVY   : int   = 4

var _light_cd       : float = 0.0
var _heavy_cd       : float = 0.0
var _hitstop_frames : int   = 0

func _process(delta: float) -> void:
	# timers tick even if tick() isn't called
	_light_cd = max(_light_cd - delta, 0.0)
	_heavy_cd = max(_heavy_cd - delta, 0.0)
	if _hitstop_frames > 0:
		_hitstop_frames -= 1

func tick() -> void:
	if player_state == null or target_state == null:
		return
	if _hitstop_frames > 0:
		return

	# LIGHT
	if _pressed(player_state, "atk_l_pressed") and _light_cd <= 0.0:
		if _in_range(LIGHT_REACH):
			_do_damage(LIGHT_DMG, KNOCK_X_LIGHT, HITSTOP_LIGHT)
			print("[Combat] LIGHT HIT! -", LIGHT_DMG, " HP  | target:", target_state.hp)
		else:
			print("[Combat] Light whiff.")
		_light_cd = LIGHT_COOLDOWN

	# HEAVY
	if _pressed(player_state, "atk_h_pressed") and _heavy_cd <= 0.0:
		if _in_range(HEAVY_REACH):
			_do_damage(HEAVY_DMG, KNOCK_X_HEAVY, HITSTOP_HEAVY)
			print("[Combat] HEAVY HIT! -", HEAVY_DMG, " HP  | target:", target_state.hp)
		else:
			print("[Combat] Heavy whiff.")
		_heavy_cd = HEAVY_COOLDOWN

# --- 1-D hitbox check ---
func _in_range(atk_reach: float) -> bool:
	# distance between centers on X
	var dx: float = abs(float(target_state.position.x - player_state.position.x))
	# max allowed distance = target hurtbox half + attack reach
	var max_dist: float = HURTBOX_HALF + atk_reach
	return dx <= max_dist

func _do_damage(dmg: int, knock_px: float, hitstop_frames: int) -> void:
	target_state.take_damage(dmg)

	# knockback (push target away from attacker)
	var dir: float = signf(target_state.position.x - player_state.position.x)
	if dir == 0.0:
		dir = 1.0
	target_state.position.x += dir * knock_px

	# tiny hitstop for chunkiness
	_hitstop_frames = hitstop_frames

# Prefer PlayerState boolean flags; fall back to raw Input names
func _pressed(ps: Node, field: String) -> bool:
	var val: Variant = null

	if ps != null:
		# Node.get(name) in Godot 4 takes a single arg
		val = ps.get(field)

	if typeof(val) == TYPE_BOOL:
		return bool(val)

	# fallback: translate to input action names
	var action: String = field.replace("_pressed", "") \
		.replace("atk_l", "light_attack") \
		.replace("atk_h", "heavy_attack")
	return Input.is_action_just_pressed(action)
