extends Node2D

@onready var debug_ui = $CanvasLayer/RobotDebugUI
@onready var sim_arm_p1 = $ArenaRoot/SimArmP1
@onready var sim_arm_p2 = $ArenaRoot/SimArmP2
@onready var http_request: HTTPRequest = $HTTPRequest

var robot_state_machine

func _ready() -> void:
	print("RobotCombatDemo ready")

	_setup_state_machine()

	debug_ui.robot_command.connect(_on_robot_command)

	http_request.request_completed.connect(_on_bridge_response)

	print("UI connected to RobotCombatDemo")
	print("HTTP bridge ready: http://127.0.0.1:8765/motion")

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

	send_to_robot_bridge(command)

func send_to_robot_bridge(command: Dictionary) -> void:
	if http_request == null:
		print("ERROR: HTTPRequest node missing")
		return

	var json: String = JSON.stringify(command)

	print("Sending to robot bridge: ", json)

	var err: Error = http_request.request(
		"http://127.0.0.1:8765/motion",
		["Content-Type: application/json"],
		HTTPClient.METHOD_POST,
		json
	)

	if err != OK:
		print("Bridge request failed to start. Error code: ", err)

func _on_bridge_response(
	result: int,
	response_code: int,
	headers: PackedStringArray,
	body: PackedByteArray
) -> void:
	print("Bridge response code: ", response_code)

	var text: String = body.get_string_from_utf8()
	if text != "":
		print("Bridge response body: ", text)

func _on_action_started(action_data: Dictionary) -> void:
	print("ACTION STARTED: ", action_data)

	sim_arm_p1.current_profile = robot_state_machine.current_profile

	sim_arm_p1.play_action({
		"name": action_data["name"],
		"profile": robot_state_machine.current_profile,
		"intensity": action_data.get("intensity", 1.0)
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
