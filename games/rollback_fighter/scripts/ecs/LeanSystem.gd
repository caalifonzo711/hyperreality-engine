class_name LeanSystem
extends Node

var player_state: PlayerState = null  # ArenaScene will set this

func tick() -> void:
	if player_state == null:
		return

	if not player_state.is_touching_wall:
		player_state.lean_direction = 0
		return

	var ld := 0
	if player_state.lean_l:
		ld -= 1
	if player_state.lean_r:
		ld += 1

	player_state.lean_direction = ld
