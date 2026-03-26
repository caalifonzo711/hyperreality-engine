class_name InputSystem
extends Node

signal input_collected(input_data: Dictionary)

func collect_input() -> Dictionary:
	var data: Dictionary = {}

	data["move"] = Vector2(
		Input.get_action_strength("move_right") - Input.get_action_strength("move_left"),
		Input.get_action_strength("move_down")  - Input.get_action_strength("move_up")
	)

	# Map actions -> flags used by PlayerState/CombatSystem
	data["atk_l"] = Input.is_action_just_pressed("jab") or Input.is_action_just_pressed("light_attack")
	data["atk_h"] = Input.is_action_just_pressed("heavy_attack")

	# optional (only if you have these actions)
	data["lean_l"] = Input.is_action_pressed("lean_left")
	data["lean_r"] = Input.is_action_pressed("lean_right")

	emit_signal("input_collected", data)
	return data
