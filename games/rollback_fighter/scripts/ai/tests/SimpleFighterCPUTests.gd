extends SceneTree

const CPU_SCRIPT = preload(
	"res://games/rollback_fighter/scripts/ai/SimpleFighterCPU.gd"
)
const PLAYER_STATE_SCRIPT = preload(
	"res://games/rollback_fighter/scripts/ecs/PlayerState.gd"
)


func _initialize() -> void:
	var policy: Variant = CPU_SCRIPT.new()
	var cpu: PlayerState = PLAYER_STATE_SCRIPT.new()
	var opponent: PlayerState = PLAYER_STATE_SCRIPT.new()
	cpu.position = Vector2(600.0, 250.0)
	opponent.position = Vector2(200.0, 250.0)
	assert(policy.input_for_frame(1, cpu, opponent)["mx"] == -1.0)
	cpu.position = Vector2(200.0, 250.0)
	opponent.position = Vector2(600.0, 250.0)
	assert(policy.input_for_frame(1, cpu, opponent)["mx"] == 1.0)

	cpu.position = Vector2(200.0, 250.0)
	opponent.position = Vector2(290.0, 250.0)
	assert(bool(policy.input_for_frame(35, cpu, opponent)["atk_l"]))
	opponent.position.x = 260.0
	assert(bool(policy.input_for_frame(150, cpu, opponent)["atk_h"]))
	opponent.position.x = 300.0
	assert(bool(policy.input_for_frame(90, cpu, opponent)["block"]))
	opponent.position.x = 260.0
	assert(bool(policy.input_for_frame(165, cpu, opponent)["dodge"]))

	opponent.state = PlayerState.MoveState.ACTIVE
	var sequence_a: Array[Dictionary] = []
	var sequence_b: Array[Dictionary] = []
	for frame: int in range(360):
		sequence_a.append(policy.input_for_frame(frame, cpu, opponent))
		sequence_b.append(policy.input_for_frame(frame, cpu, opponent))
	assert(sequence_a == sequence_b)

	var old_position: Vector2 = cpu.position
	var old_hp: int = cpu.hp
	var old_state: int = cpu.state
	policy.input_for_frame(35, cpu, opponent)
	assert(cpu.position == old_position)
	assert(cpu.hp == old_hp)
	assert(cpu.state == old_state)
	assert(policy.input_for_frame(35, cpu, opponent, true)["atk_l"] == false)

	cpu.free()
	opponent.free()
	print("[SimpleFighterCPUTests] PASS")
	quit(0)
