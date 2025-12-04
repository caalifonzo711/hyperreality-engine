class_name PlayerState
extends Node

var position : Vector2 = Vector2.ZERO
var rotation : float = 0.0
var is_touching_wall : bool = false
var lean_direction : int = 0
var max_hp: int = 100
var hp:     int = 100
var move_speed := 150.0

# --- transient inputs (read by CombatSystem each tick) ---
var atk_l_pressed := false
var atk_h_pressed := false
var lean_l := false
var lean_r := false

# --- simple input buffering (how many frames a tap is kept) ---
const BUFFER_FRAMES : int = 3
var _atk_l_buffer : int = 0
var _atk_h_buffer : int = 0

func take_damage(amount: int) -> void:
	hp = max(hp - amount, 0)

func apply_input(input_data: Dictionary, delta: float) -> void:
	# -------------------------------------------------
	# 1) movement
	# -------------------------------------------------
	var move: Vector2 = input_data.get("move", Vector2.ZERO)
	position += move * move_speed * delta

	# -------------------------------------------------
	# 2) raw button samples from adapter
	# -------------------------------------------------
	var raw_l: bool = bool(input_data.get("atk_l", false))
	var raw_h: bool = bool(input_data.get("atk_h", false))
	lean_l = bool(input_data.get("lean_l", false))
	lean_r = bool(input_data.get("lean_r", false))

	# When we see a tap, (re)fill the buffer counters.
	if raw_l:
		_atk_l_buffer = BUFFER_FRAMES
	if raw_h:
		_atk_h_buffer = BUFFER_FRAMES

	# Each frame, if buffer > 0 → press is considered active.
	if _atk_l_buffer > 0:
		atk_l_pressed = true
		_atk_l_buffer -= 1
	else:
		atk_l_pressed = false

	if _atk_h_buffer > 0:
		atk_h_pressed = true
		_atk_h_buffer -= 1
	else:
		atk_h_pressed = false

	# -------------------------------------------------
	# 3) sample lean → convert to -1 / 0 / +1
	# -------------------------------------------------
	var ld := 0
	if lean_l: ld -= 1
	if lean_r: ld += 1
	lean_direction = ld

func set_touching_wall(t: bool) -> void:
	if is_touching_wall != t:
		is_touching_wall = t
		print("[WallDetector] Now touching wall." if t else "[WallDetector] Left wall.")
