extends Node
class_name PiperAdapter

signal motion_sent(command: Dictionary)
signal motion_blocked(reason: String)
signal emergency_stopped()

@export var enabled: bool = false
@export var bridge_host: String = "127.0.0.1"
@export var bridge_port: int = 8765
@export var safety_mode: bool = true

var connected: bool = false
var last_command: Dictionary = {}

func _ready() -> void:
	print("PiperAdapter ready. Enabled =", enabled)
	print("Bridge target: %s:%d" % [bridge_host, bridge_port])

func send_motion(command: Dictionary) -> void:
	if not enabled:
		print("PiperAdapter disabled. Sim-only command:", command)
		motion_blocked.emit("PiperAdapter disabled")
		return

	if safety_mode and not _is_safe_command(command):
		var reason := "Unsafe or invalid Piper command blocked"
		print(reason, command)
		motion_blocked.emit(reason)
		return

	last_command = command.duplicate(true)

	# Placeholder:
	# Later this sends JSON to Python Piper bridge.
	print("PIPER MOTION SENT:", JSON.stringify(last_command))
	motion_sent.emit(last_command)

func play_action(action_data: Dictionary) -> void:
	var command := {
		"type": "play_action",
		"action": action_data.get("name", "idle"),
		"profile": action_data.get("profile", "snappy"),
		"intensity": clamp(float(action_data.get("intensity", 1.0)), 0.1, 1.0),
		"motion_id": _action_to_motion_id(action_data.get("name", "idle"))
	}

	send_motion(command)

func finish_action(_action_data: Dictionary = {}) -> void:
	send_motion({
		"type": "return_idle",
		"action": "idle",
		"profile": "snappy",
		"intensity": 0.5,
		"motion_id": "idle_motion"
	})

func emergency_stop() -> void:
	print("PIPER EMERGENCY STOP REQUESTED")
	emergency_stopped.emit()

func _is_safe_command(command: Dictionary) -> bool:
	var action := str(command.get("action", "idle"))
	var intensity := float(command.get("intensity", 1.0))

	var allowed_actions := [
		"idle",
		"jab",
		"heavy",
		"block",
		"grab",
		"wave"
	]

	if not allowed_actions.has(action):
		return false

	if intensity < 0.0 or intensity > 1.0:
		return false

	return true

func _action_to_motion_id(action: String) -> String:
	match action:
		"jab":
			return "jab_motion"
		"heavy":
			return "heavy_motion"
		"block":
			return "block_motion"
		"grab":
			return "grab_motion"
		"wave":
			return "wave_motion"
		_:
			return "idle_motion"
