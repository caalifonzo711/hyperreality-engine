extends Node
class_name PlayerState

# animation frames to death 

var position: Vector2 = Vector2.ZERO
var rotation: float = 0.0
var is_touching_wall: bool = false
var lean_direction: int = 0

# --- velocity system (for knockback feel) ---
var vel: Vector2 = Vector2.ZERO
var ground_friction: float = 900.0
var max_knock_speed: float = 900.0

var max_hp: int = 100
var hp: int = 100
var move_speed: float = 150.0

# --- transient flags (read by visuals / debug / combat) ---
var atk_l_pressed: bool = false
var atk_h_pressed: bool = false
var lean_l: bool = false
var lean_r: bool = false

# ----------------------------
# Minimal move state machine
# ----------------------------
enum MoveState { IDLE, STARTUP, ACTIVE, RECOVERY, BLOCK, DODGE, HURT, DEAD }
enum AttackKind { NONE, LIGHT, HEAVY }

var state: int = MoveState.IDLE
var frames_left: int = 0

var attack_kind: int = AttackKind.NONE
var attack_active: bool = false

# Prevent multi-hit during ACTIVE
var attack_id: int = 0
var hit_confirmed: bool = false

# hurt frames
var hurt_frames: int = 0
const HURT_DURATION: int = 6

# Deterministic facing (+1 right, -1 left)
var facing: int = 1

# Defensive state
var blocking: bool = false

# dodge 
var dodge_requested: bool = false
var invulnerable: bool = false

const DODGE_TOTAL: int = 20
const DODGE_INVULN_START: int = 1
const DODGE_INVULN_END: int = 15

# Frame data
const JAB_STARTUP: int = 3
const JAB_ACTIVE: int = 2
const JAB_RECOVERY: int = 8

const HEAVY_STARTUP: int = 6
const HEAVY_ACTIVE: int = 2
const HEAVY_RECOVERY: int = 14


#func take_damage(amount: int) -> void:
#	hp = maxi(hp - amount, 0)
func take_damage(amount: int) -> void:
	hp = maxi(hp - amount, 0)

	if hp <= 0:
		hp = 0
		state = MoveState.DEAD
		hurt_frames = 0
		attack_active = false
		attack_kind = AttackKind.NONE
		vel = Vector2.ZERO
	else:
		state = MoveState.HURT
		hurt_frames = HURT_DURATION
		attack_active = false
		attack_kind = AttackKind.NONE
func apply_input(input_data: Dictionary, delta: float) -> void:
	# -----------------
	# 1) Movement + Velocity (supports knockback impulses)
	# -----------------
	var move: Vector2 = input_data.get("move", Vector2.ZERO)

	# Stop movement when dead
	if state == MoveState.DEAD:
		vel = Vector2.ZERO
		return

	# If player is holding movement, override horizontal speed.
	# If not, preserve vel.x so knockback can carry, then decay with friction.
	if absf(move.x) >= 0.001:
		vel.x = move.x * move_speed
	else:
		vel.x = move_toward(vel.x, 0.0, ground_friction * delta)

	# Integrate position
	position += vel * delta

	# Clamp safety
	vel.x = clampf(vel.x, -max_knock_speed, max_knock_speed)

	# Facing from movement
	if move.x > 0.0:
		facing = 1
	elif move.x < 0.0:
		facing = -1

	# -----------------
	# 2) Lean samples
	# -----------------
	lean_l = bool(input_data.get("lean_l", false))
	lean_r = bool(input_data.get("lean_r", false))

	var ld: int = 0
	if lean_l:
		ld -= 1
	if lean_r:
		ld += 1
	lean_direction = ld

	# -----------------
	# 3) Defensive input
	# -----------------
	blocking = bool(input_data.get("block", false))
	dodge_requested = bool(input_data.get("dodge", false))

	# Enter dodge from idle
	if dodge_requested and state == MoveState.IDLE:
		state = MoveState.DODGE
		frames_left = DODGE_TOTAL
		attack_active = false
		attack_kind = AttackKind.NONE
		hit_confirmed = false

	# Enter block if holding block and currently idle
	if blocking and state == MoveState.IDLE:
		state = MoveState.BLOCK

	# -----------------
	# 4) Attack requests
	# -----------------
	var wants_light: bool = bool(input_data.get("atk_l", false))
	var wants_heavy: bool = bool(input_data.get("atk_h", false))

	# Do not allow attacks to start while blocking / dodging / hurt / dead
	if state != MoveState.BLOCK and state != MoveState.DODGE and state != MoveState.HURT and state != MoveState.DEAD:
		if wants_light:
			try_start_attack(AttackKind.LIGHT)
		if wants_heavy:
			try_start_attack(AttackKind.HEAVY)

	# -----------------
	# 5) Advance state machine (1 tick)
	# -----------------
	step_state_machine()

	# Compatibility flags
	atk_l_pressed = attack_active and (attack_kind == AttackKind.LIGHT)
	atk_h_pressed = attack_active and (attack_kind == AttackKind.HEAVY)
	

func try_start_attack(kind: int) -> void:
	# Only start a new move from IDLE
	if state != MoveState.IDLE:
		return

	attack_kind = kind
	attack_active = false

	attack_id += 1
	hit_confirmed = false

	match kind:
		AttackKind.LIGHT:
			state = MoveState.STARTUP
			frames_left = JAB_STARTUP
		AttackKind.HEAVY:
			state = MoveState.STARTUP
			frames_left = HEAVY_STARTUP
		_:
			state = MoveState.IDLE
			frames_left = 0
			attack_kind = AttackKind.NONE


func step_state_machine() -> void:
	match state:
		MoveState.IDLE:
			attack_active = false
			attack_kind = AttackKind.NONE
			frames_left = 0

		MoveState.BLOCK:
			attack_active = false
			attack_kind = AttackKind.NONE
			frames_left = 0

			if not blocking:
				state = MoveState.IDLE

		MoveState.STARTUP:
			frames_left -= 1
			if frames_left <= 0:
				state = MoveState.ACTIVE
				match attack_kind:
					AttackKind.LIGHT:
						frames_left = JAB_ACTIVE
					AttackKind.HEAVY:
						frames_left = HEAVY_ACTIVE
					_:
						frames_left = 0
				attack_active = true

		MoveState.ACTIVE:
			frames_left -= 1
			if frames_left <= 0:
				state = MoveState.RECOVERY
				match attack_kind:
					AttackKind.LIGHT:
						frames_left = JAB_RECOVERY
					AttackKind.HEAVY:
						frames_left = HEAVY_RECOVERY
					_:
						frames_left = 0
				attack_active = false

		MoveState.RECOVERY:
			frames_left -= 1
			if frames_left <= 0:
				state = MoveState.IDLE

		MoveState.DODGE:
			attack_active = false
			attack_kind = AttackKind.NONE

			var elapsed: int = DODGE_TOTAL - frames_left
			invulnerable = (elapsed >= DODGE_INVULN_START and elapsed <= DODGE_INVULN_END)

			frames_left -= 1
			if frames_left <= 0:
				invulnerable = false
				state = MoveState.IDLE

		MoveState.HURT:
			attack_active = false
			attack_kind = AttackKind.NONE
			invulnerable = false

			hurt_frames -= 1
			if hurt_frames <= 0:
				state = MoveState.IDLE

		MoveState.DEAD:
			attack_active = false
			attack_kind = AttackKind.NONE
			invulnerable = false
			vel = Vector2.ZERO

		_:
			pass

func set_touching_wall(t: bool) -> void:
	if is_touching_wall != t:
		is_touching_wall = t
		print("[WallDetector] Now touching wall." if t else "[WallDetector] Left wall.")
