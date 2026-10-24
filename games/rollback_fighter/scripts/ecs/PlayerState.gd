extends Node
class_name PlayerState

var position: Vector2 = Vector2.ZERO
var rotation: float = 0.0
var is_touching_wall: bool = false
var lean_direction: int = 0

var vel: Vector2 = Vector2.ZERO
var ground_velocity_x: float = 0.0
var ground_friction: float = 0.0
var max_knock_speed: float = 0.0

var max_hp: int = 0
var hp: int = 0
var move_speed: float = 0.0
var ground_acceleration: float = 0.0
var ground_braking: float = 0.0
var reversal_acceleration: float = 0.0

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

var facing: int = 1

var blocking: bool = false
var dodge_requested: bool = false
var invulnerable: bool = false
var dodge_cooldown_frames: int = 0

var dodge_total_frames: int = 0
var dodge_invuln_start: int = 0
var dodge_invuln_end: int = 0
var dodge_cooldown_duration: int = 0

var _character_definition: RollbackFighterCharacterDefinition = null
var _light_move_definition: RollbackFighterMoveDefinition = null
var _heavy_move_definition: RollbackFighterMoveDefinition = null


func configure_character_definition(
	character_definition: RollbackFighterCharacterDefinition
) -> void:
	_character_definition = character_definition
	max_hp = character_definition.get_int("max_hp")
	hp = max_hp
	move_speed = float(character_definition.get_int("move_speed"))
	ground_acceleration = float(character_definition.get_int("acceleration"))
	ground_braking = float(character_definition.get_int("braking"))
	reversal_acceleration = float(
		character_definition.get_int("reversal_acceleration")
	)
	ground_friction = float(
		character_definition.get_int("knockback_friction")
	)
	max_knock_speed = float(
		character_definition.get_int("max_knockback_speed")
	)
	dodge_total_frames = character_definition.get_int("dodge_total_frames")
	dodge_invuln_start = character_definition.get_int("dodge_invuln_start")
	dodge_invuln_end = character_definition.get_int("dodge_invuln_end")
	dodge_cooldown_duration = character_definition.get_int(
		"dodge_cooldown_frames"
	)
	_light_move_definition = character_definition.get_move_for_slot("light")
	_heavy_move_definition = character_definition.get_move_for_slot("heavy")


func get_attack_move(kind: int) -> RollbackFighterMoveDefinition:
	match kind:
		AttackKind.LIGHT:
			return _light_move_definition
		AttackKind.HEAVY:
			return _heavy_move_definition
		_:
			return null


func take_damage(
	amount: int,
	hitstun_frames: int
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
			ground_braking * delta
		)
	elif (
		absf(ground_velocity_x) >= 0.001
		and signf(ground_velocity_x) != signf(target_speed)
	):
		ground_velocity_x = move_toward(
			ground_velocity_x,
			target_speed,
			reversal_acceleration * delta
		)
	else:
		ground_velocity_x = move_toward(
			ground_velocity_x,
			target_speed,
			ground_acceleration * delta
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
		frames_left = dodge_total_frames
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
			frames_left = _light_move_definition.get_int("startup")

		AttackKind.HEAVY:
			state = MoveState.STARTUP
			frames_left = _heavy_move_definition.get_int("startup")

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
						frames_left = _light_move_definition.get_int("active")
					AttackKind.HEAVY:
						frames_left = _heavy_move_definition.get_int("active")
					_:
						frames_left = 0

				attack_active = true

		MoveState.ACTIVE:
			frames_left -= 1
			if frames_left <= 0:
				state = MoveState.RECOVERY

				match attack_kind:
					AttackKind.LIGHT:
						frames_left = _light_move_definition.get_int("recovery")
					AttackKind.HEAVY:
						frames_left = _heavy_move_definition.get_int("recovery")
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

			var elapsed: int = dodge_total_frames - frames_left
			invulnerable = (
				elapsed >= dodge_invuln_start
				and elapsed <= dodge_invuln_end
			)

			frames_left -= 1
			if frames_left <= 0:
				invulnerable = false
				state = MoveState.IDLE
				dodge_cooldown_frames = dodge_cooldown_duration

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
