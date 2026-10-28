extends RefCounted
class_name SimpleFighterCPU

const PREFERRED_DISTANCE := 78.0
const JAB_DISTANCE := 98.0
const HEAVY_DISTANCE := 70.0
const DEFENSE_DISTANCE := 145.0
const DODGE_DISTANCE := 130.0
const CADENCE_FRAMES := 180


func input_for_frame(
	frame: int,
	cpu_state: PlayerState,
	opponent_state: PlayerState,
	match_over: bool = false
) -> Dictionary:
	var result: Dictionary = _neutral_input()
	if match_over or cpu_state == null or opponent_state == null:
		return result
	if cpu_state.state == PlayerState.MoveState.DEAD:
		return result
	if cpu_state.state != PlayerState.MoveState.IDLE and cpu_state.state != PlayerState.MoveState.BLOCK:
		return result

	var delta_x: float = opponent_state.position.x - cpu_state.position.x
	var distance: float = absf(delta_x)
	var approach_direction: float = signf(delta_x)
	var phase: int = posmod(frame, CADENCE_FRAMES)
	var opponent_attacking: bool = (
		opponent_state.state == PlayerState.MoveState.STARTUP
		or opponent_state.state == PlayerState.MoveState.ACTIVE
	)
	var periodic_block: bool = phase >= 90 and phase < 100
	var defensive_block: bool = phase >= 100 and phase < 120 and opponent_attacking
	var wants_block: bool = (
		distance <= DEFENSE_DISTANCE
		and (periodic_block or defensive_block)
	)

	if cpu_state.state == PlayerState.MoveState.BLOCK:
		result["block"] = wants_block
		return result

	if wants_block:
		result["block"] = true
		return result

	if (
		phase == 165
		and distance <= DODGE_DISTANCE
		and (opponent_attacking or distance <= PREFERRED_DISTANCE)
	):
		result["dodge"] = true
		return result

	if phase == 150 and distance <= HEAVY_DISTANCE:
		result["atk_h"] = true
		return result

	if (phase == 35 or phase == 120) and distance <= JAB_DISTANCE:
		result["atk_l"] = true
		return result

	# Approach from either side, with a small repeating pause once in range.
	var should_pause: bool = (
		phase >= 30
		and phase < 55
		and distance <= PREFERRED_DISTANCE + 24.0
	)
	if distance > PREFERRED_DISTANCE and not should_pause:
		result["mx"] = approach_direction
	return result


func _neutral_input() -> Dictionary:
	return {
		"mx": 0.0,
		"lean_l": false,
		"lean_r": false,
		"atk_l": false,
		"atk_h": false,
		"block": false,
		"dodge": false,
	}
