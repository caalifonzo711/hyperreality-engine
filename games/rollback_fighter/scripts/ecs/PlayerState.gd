extends Node
class_name PlayerState

var position: Vector2 = Vector2.ZERO
var rotation: float = 0.0
var is_touching_wall: bool = false
var lean_direction: int = 0

var vel: Vector2 = Vector2.ZERO
var ground_velocity_x: float = 0.0
var ground_friction: float = 900.0
var max_knock_speed: float = 1100.0

var max_hp: int = 100
var hp: int = 100
var move_speed: float = 320.0

const GROUND_ACCELERATION: float = 14400.0
const GROUND_BRAKING: float = 19200.0
const REVERSAL_ACCELERATION: float = 28800.0

var atk_l_pressed: bool = false
var atk_h_pressed: bool = false
var lean_l: bool = false
var lean_r: bool = false

enum MoveState { IDLE, STARTUP, ACTIVE, RECOVERY, BLOCK, DODGE, HURT, DEAD }
enum AttackKind { NONE, LIGHT, HEAVY }

var state: int = MoveState.IDLE
var frames_left: int = 0

var attack_kind: int = AttackKind.NONE
var attack_active: bool = false

var attack_id: int = 0
var hit_confirmed: bool = false

var hurt_frames: int = 0
const HURT_DURATION: int = 6

var facing: int = 1

var blocking: bool = false
var dodge_requested: bool = false
var invulnerable: bool = false
var dodge_cooldown_frames: int = 0

const DODGE_TOTAL: int = 16
const DODGE_INVULN_START: int = 2
const DODGE_INVULN_END: int = 6
const DODGE_COOLDOWN_FRAMES: int = 24

const JAB_STARTUP: int = 3
const JAB_ACTIVE: int = 2
const JAB_RECOVERY: int = 8

const HEAVY_STARTUP: int = 6
const HEAVY_ACTIVE: int = 2
const HEAVY_RECOVERY: int = 14

var generated_light_move: Dictionary = {
	"name": "Default Light",
	"startup": JAB_STARTUP,
	"active": JAB_ACTIVE,
	"recovery": JAB_RECOVERY,
	"on_hit": 0,
	"on_block": 0
}

var generated_heavy_move: Dictionary = {
	"name": "Default Heavy",
	"startup": HEAVY_STARTUP,
	"active": HEAVY_ACTIVE,
	"recovery": HEAVY_RECOVERY,
	"on_hit": 0,
	"on_block": 0
}


func _ready() -> void:
	load_generated_moves_from_disk()


func load_generated_moves_from_disk() -> void:
	_try_load_light_move("res://games/rollback_fighter/moves/move_light_punch.json")
	_try_load_heavy_move("res://games/rollback_fighter/moves/move_strong_kick.json")


func _try_load_light_move(path: String) -> void:
	var data := _load_move_json(path)
	if data.is_empty():
		return
	set_generated_light_move(data)
	print("[GeminiMove] Auto-loaded LIGHT from disk: ", path)


func _try_load_heavy_move(path: String) -> void:
	var data := _load_move_json(path)
	if data.is_empty():
		return
	set_generated_heavy_move(data)
	print("[GeminiMove] Auto-loaded HEAVY from disk: ", path)


func _load_move_json(path: String) -> Dictionary:
	print("[GeminiMove] Checking move path: ", path)

	if not FileAccess.file_exists(path):
		print("[GeminiMove] No move file found at: ", path)
		return {}

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		print("[GeminiMove] Failed to open move file: ", path)
		return {}

	var text := file.get_as_text()
	file.close()

	var parsed = JSON.parse_string(text)
	if parsed == null or not (parsed is Dictionary):
		print("[GeminiMove] Failed to parse move JSON: ", path)
		return {}

	return parsed


func set_generated_light_move(move_data: Dictionary) -> void:
	generated_light_move = {
		"name": str(move_data.get("name", "Gemini Light")),
		"startup": _safe_frame_int(move_data.get("startup", JAB_STARTUP), JAB_STARTUP),
		"active": _safe_frame_int(move_data.get("active", JAB_ACTIVE), JAB_ACTIVE),
		"recovery": _safe_frame_int(move_data.get("recovery", JAB_RECOVERY), JAB_RECOVERY),
		"on_hit": int(move_data.get("on_hit", 0)),
		"on_block": int(move_data.get("on_block", 0))
	}

	print("[GeminiMove] Loaded generated LIGHT move: ", generated_light_move)


func set_generated_heavy_move(move_data: Dictionary) -> void:
	generated_heavy_move = {
		"name": str(move_data.get("name", "Gemini Heavy")),
		"startup": _safe_frame_int(move_data.get("startup", HEAVY_STARTUP), HEAVY_STARTUP),
		"active": _safe_frame_int(move_data.get("active", HEAVY_ACTIVE), HEAVY_ACTIVE),
		"recovery": _safe_frame_int(move_data.get("recovery", HEAVY_RECOVERY), HEAVY_RECOVERY),
		"on_hit": int(move_data.get("on_hit", 0)),
		"on_block": int(move_data.get("on_block", 0))
	}

	print("[GeminiMove] Loaded generated HEAVY move: ", generated_heavy_move)


func _safe_frame_int(value: Variant, fallback: int) -> int:
	var v := fallback

	if value is int:
		v = value
	elif value is float:
		v = int(value)
	elif value is String and String(value).is_valid_int():
		v = int(String(value))

	return clampi(v, 1, 120)


func take_damage(
	amount: int,
	hitstun_frames: int = HURT_DURATION
) -> void:
	hp = maxi(hp - amount, 0)

	if hp <= 0:
		hp = 0
		state = MoveState.DEAD
		hurt_frames = 0
		attack_active = false
		attack_kind = AttackKind.NONE
		vel = Vector2.ZERO
		ground_velocity_x = 0.0
	else:
		state = MoveState.HURT
		hurt_frames = hitstun_frames
		attack_active = false
		attack_kind = AttackKind.NONE


func apply_input(input_data: Dictionary, delta: float) -> void:
	var move: Vector2 = input_data.get("move", Vector2.ZERO)

	if state == MoveState.DEAD:
		vel = Vector2.ZERO
		ground_velocity_x = 0.0
		return

	dodge_cooldown_frames = maxi(
		dodge_cooldown_frames - 1,
		0
	)

	var input_axis: float = clampf(move.x, -1.0, 1.0)
	var target_speed: float = input_axis * move_speed

	if absf(input_axis) < 0.001:
		ground_velocity_x = move_toward(
			ground_velocity_x,
			0.0,
			GROUND_BRAKING * delta
		)
	elif (
		absf(ground_velocity_x) >= 0.001
		and signf(ground_velocity_x) != signf(target_speed)
	):
		ground_velocity_x = move_toward(
			ground_velocity_x,
			target_speed,
			REVERSAL_ACCELERATION * delta
		)
	else:
		ground_velocity_x = move_toward(
			ground_velocity_x,
			target_speed,
			GROUND_ACCELERATION * delta
		)

	vel.x = move_toward(vel.x, 0.0, ground_friction * delta)
	position.x += (ground_velocity_x + vel.x) * delta
	position.y += vel.y * delta
	vel.x = clampf(vel.x, -max_knock_speed, max_knock_speed)

	if move.x > 0.0:
		facing = 1
	elif move.x < 0.0:
		facing = -1

	lean_l = bool(input_data.get("lean_l", false))
	lean_r = bool(input_data.get("lean_r", false))

	var ld: int = 0
	if lean_l:
		ld -= 1
	if lean_r:
		ld += 1
	lean_direction = ld

	blocking = bool(input_data.get("block", false))
	dodge_requested = bool(input_data.get("dodge", false))

	if (
		dodge_requested
		and state == MoveState.IDLE
		and dodge_cooldown_frames == 0
	):
		state = MoveState.DODGE
		frames_left = DODGE_TOTAL
		attack_active = false
		attack_kind = AttackKind.NONE
		hit_confirmed = false

	if blocking and state == MoveState.IDLE:
		state = MoveState.BLOCK

	var wants_light: bool = bool(input_data.get("atk_l", false))
	var wants_heavy: bool = bool(input_data.get("atk_h", false))

	if state != MoveState.BLOCK and state != MoveState.DODGE and state != MoveState.HURT and state != MoveState.DEAD:
		if wants_light:
			try_start_attack(AttackKind.LIGHT)
		if wants_heavy:
			try_start_attack(AttackKind.HEAVY)

	step_state_machine()

	atk_l_pressed = attack_active and (attack_kind == AttackKind.LIGHT)
	atk_h_pressed = attack_active and (attack_kind == AttackKind.HEAVY)


func try_start_attack(kind: int) -> void:
	if state != MoveState.IDLE:
		return

	attack_kind = kind
	attack_active = false
	attack_id += 1
	hit_confirmed = false

	match kind:
		AttackKind.LIGHT:
			state = MoveState.STARTUP
			frames_left = int(generated_light_move.get("startup", JAB_STARTUP))
			print("[GeminiMove] Starting LIGHT: ", generated_light_move)

		AttackKind.HEAVY:
			state = MoveState.STARTUP
			frames_left = int(generated_heavy_move.get("startup", HEAVY_STARTUP))
			print("[GeminiMove] Starting HEAVY: ", generated_heavy_move)

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
						frames_left = int(generated_light_move.get("active", JAB_ACTIVE))
					AttackKind.HEAVY:
						frames_left = int(generated_heavy_move.get("active", HEAVY_ACTIVE))
					_:
						frames_left = 0

				attack_active = true

		MoveState.ACTIVE:
			frames_left -= 1
			if frames_left <= 0:
				state = MoveState.RECOVERY

				match attack_kind:
					AttackKind.LIGHT:
						frames_left = int(generated_light_move.get("recovery", JAB_RECOVERY))
					AttackKind.HEAVY:
						frames_left = int(generated_heavy_move.get("recovery", HEAVY_RECOVERY))
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
				dodge_cooldown_frames = DODGE_COOLDOWN_FRAMES

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
			ground_velocity_x = 0.0

		_:
			pass


func set_touching_wall(t: bool) -> void:
	if is_touching_wall != t:
		is_touching_wall = t
		print("[WallDetector] Now touching wall." if t else "[WallDetector] Left wall.")
