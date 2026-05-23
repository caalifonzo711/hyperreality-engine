extends Node2D

@onready var debug_ui = $CanvasLayer/RobotDebugUI

@onready var sim_arm_p1 = $ArenaRoot/SimArmP1
@onready var sim_arm_p2 = $ArenaRoot/SimArmP2

var robot_state_machine

func _ready() -> void:
	print("RobotCombatDemo ready")

	_setup_state_machine()

	debug_ui.robot_command.connect(_on_robot_command)

	print("UI connected to RobotCombatDemo")

func _setup_state_machine() -> void:
	robot_state_machine = preload(
		"res://games/rollback_robotics/scripts/core/RobotStateMachine.gd"
	).new()

	add_child(robot_state_machine)

	robot_state_machine.action_started.connect(_on_action_started)
	robot_state_machine.action_finished.connect(_on_action_finished)

	print("RobotStateMachine initialized")

func _on_robot_command(command: Dictionary) -> void:
	print("RobotCombatDemo received command: ", command)

	robot_state_machine.receive_command(command)

func _on_action_started(action_data: Dictionary) -> void:
	print("ACTION STARTED: ", action_data)

	sim_arm_p1.current_profile = robot_state_machine.current_profile

	sim_arm_p1.play_action({
		"name": action_data["name"],
		"profile": robot_state_machine.current_profile
	})

func _on_action_finished(action_data: Dictionary) -> void:
	print("ACTION FINISHED: ", action_data)

	sim_arm_p1.finish_action(action_data)

func _process(_delta: float) -> void:
	if robot_state_machine == null:
		return

	match robot_state_machine.current_state:
		"startup":
			sim_arm_p1.set_phase("startup")

		"active":
			sim_arm_p1.set_phase("active")

		"recovery":
			sim_arm_p1.set_phase("recovery")

		"idle":
			sim_arm_p1.set_phase("idle")
