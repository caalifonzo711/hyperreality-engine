extends Node
class_name RobotStateMachine

signal action_started(action_data: Dictionary)
signal action_phase_changed(action_name: String, phase: String)
signal action_finished(action_data: Dictionary)

var current_state: String = "idle"
var current_action: Dictionary = {}
var current_profile: String = "snappy"

var frame_in_state: int = 0
var buffered_command: Dictionary = {}
var active_command: Dictionary = {}

func _process(_delta: float) -> void:
	frame_in_state += 1
	_update_state()

func receive_command(command: Dictionary) -> void:
	print("RobotStateMachine received: ", command)

	if current_state == "idle":
		_start_action(command)
	elif current_state == "recovery":
		buffered_command = command.duplicate(true)
		print("Buffered command: ", buffered_command)

func _start_action(command: Dictionary) -> void:
	active_command = command.duplicate(true)
	current_action = _build_action_data(command)

	current_profile = str(command.get("profile", "snappy"))
	current_action["profile"] = current_profile
	current_action["intensity"] = float(command.get("intensity", 1.0))

	current_state = "startup"
	frame_in_state = 0

	print("ACTION STARTED: ", current_action["name"])

	action_started.emit(current_action)
	action_phase_changed.emit(str(current_action["name"]), current_state)

func _update_state() -> void:
	if current_state == "idle":
		return

	if current_state == "startup":
		if frame_in_state >= int(current_action.get("startup_frames", 1)):
			_transition_to_active()

	elif current_state == "active":
		if frame_in_state >= int(current_action.get("active_frames", 1)):
			_transition_to_recovery()

	elif current_state == "recovery":
		if frame_in_state >= int(current_action.get("recovery_frames", 1)):
			_finish_action()

func _transition_to_active() -> void:
	current_state = "active"
	frame_in_state = 0

	print("ACTIVE: ", current_action["name"])
	action_phase_changed.emit(str(current_action["name"]), current_state)

func _transition_to_recovery() -> void:
	current_state = "recovery"
	frame_in_state = 0

	print("RECOVERY: ", current_action["name"])
	action_phase_changed.emit(str(current_action["name"]), current_state)

func _finish_action() -> void:
	print("ACTION FINISHED: ", current_action["name"])

	action_finished.emit(current_action)

	current_state = "idle"
	frame_in_state = 0
	current_action = {}
	active_command = {}

	if not buffered_command.is_empty():
		var next_command: Dictionary = buffered_command.duplicate(true)
		buffered_command = {}
		_start_action(next_command)

func _build_action_data(command: Dictionary) -> Dictionary:
	var action: String = str(command.get("action", "wave"))

	match action:
		"jab":
			return {
				"name": "jab",
				"startup_frames": 4,
				"active_frames": 3,
				"recovery_frames": 10
			}

		"heavy":
			return {
				"name": "heavy",
				"startup_frames": 10,
				"active_frames": 5,
				"recovery_frames": 20
			}

		"block":
			return {
				"name": "block",
				"startup_frames": 2,
				"active_frames": 12,
				"recovery_frames": 4
			}

		"grab":
			return {
				"name": "grab",
				"startup_frames": 8,
				"active_frames": 6,
				"recovery_frames": 14
			}

		"idle":
			return {
				"name": "idle",
				"startup_frames": 1,
				"active_frames": 1,
				"recovery_frames": 1
			}

		_:
			return {
				"name": "wave",
				"startup_frames": 6,
				"active_frames": 12,
				"recovery_frames": 8
			}
