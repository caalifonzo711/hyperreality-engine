class_name InputSystem
extends Node


signal input_collected(input_data)

func collect_input() -> Dictionary:
	var data = {}
	data["move"] = Vector2(
		Input.get_action_strength("move_right") - Input.get_action_strength("move_left"),
		Input.get_action_strength("move_down")  - Input.get_action_strength("move_up")
	)
	emit_signal("input_collected", data)
	return data
