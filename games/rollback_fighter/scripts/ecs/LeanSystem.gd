class_name LeanSystem
extends Node

var player_state: PlayerState = null  # ArenaScene will set this

func tick() -> void:
	if player_state == null:
		return

	# Optional: Remove this if you want leaning in mid-air / not touching wall
	if not player_state.is_touching_wall:
		return

	if Input.is_action_pressed("lean_left"):
		player_state.lean_direction = -1
	elif Input.is_action_pressed("lean_right"):
		player_state.lean_direction = 1
	else:
		player_state.lean_direction = 0

	print("lean_dir =", player_state.lean_direction)
