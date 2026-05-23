extends Node2D

@export var player_id: int = 1
@export var arm_length: float = 120.0
@export var forearm_length: float = 90.0
@export var line_width: float = 8.0

var current_action: String = "idle"
var current_profile: String = "snappy"
var phase: String = "idle"

var shoulder_angle: float = -35.0
var elbow_angle: float = 45.0
var target_shoulder_angle: float = -35.0
var target_elbow_angle: float = 45.0

var base_color := Color.WHITE
var action_flash_timer: float = 0.0

func _ready() -> void:
	if player_id == 1:
		base_color = Color(0.4, 0.8, 1.0)
	else:
		base_color = Color(1.0, 0.45, 0.45)

	queue_redraw()

func _process(delta: float) -> void:
	shoulder_angle = lerp(shoulder_angle, target_shoulder_angle, delta * _profile_speed())
	elbow_angle = lerp(elbow_angle, target_elbow_angle, delta * _profile_speed())

	if action_flash_timer > 0.0:
		action_flash_timer -= delta

	queue_redraw()

func play_action(action_data: Dictionary) -> void:
	current_action = action_data.get("name", "idle")
	current_profile = action_data.get("profile", "snappy")
	phase = "startup"

	_set_target_pose(current_action)
	action_flash_timer = 0.25

	print("SimRobotAdapter P%d playing: %s" % [player_id, current_action])

func finish_action(_action_data: Dictionary = {}) -> void:
	current_action = "idle"
	phase = "idle"
	_set_idle_pose()

func set_phase(new_phase: String) -> void:
	phase = new_phase

	match phase:
		"startup":
			_set_target_pose(current_action)
		"active":
			_set_active_pose(current_action)
		"recovery":
			_set_idle_pose()
		_:
			_set_idle_pose()

func _set_target_pose(action: String) -> void:
	match action:
		"jab":
			target_shoulder_angle = -20.0
			target_elbow_angle = 20.0
		"heavy":
			target_shoulder_angle = -65.0
			target_elbow_angle = 95.0
		"block":
			target_shoulder_angle = -90.0
			target_elbow_angle = 70.0
		"grab":
			target_shoulder_angle = -10.0
			target_elbow_angle = 55.0
		"wave":
			target_shoulder_angle = -120.0
			target_elbow_angle = 35.0
		_:
			_set_idle_pose()

func _set_active_pose(action: String) -> void:
	match action:
		"jab":
			target_shoulder_angle = 0.0
			target_elbow_angle = 0.0
		"heavy":
			target_shoulder_angle = 15.0
			target_elbow_angle = -10.0
		"block":
			target_shoulder_angle = -100.0
			target_elbow_angle = 45.0
		"grab":
			target_shoulder_angle = 10.0
			target_elbow_angle = 10.0
		"wave":
			target_shoulder_angle = -145.0
			target_elbow_angle = 70.0
		_:
			_set_idle_pose()

func _set_idle_pose() -> void:
	target_shoulder_angle = -35.0
	target_elbow_angle = 45.0

func _profile_speed() -> float:
	match current_profile:
		"snappy":
			return 14.0
		"heavy":
			return 7.0
		"defensive":
			return 10.0
		"dramatic":
			return 5.0
		_:
			return 10.0

func _draw() -> void:
	var shoulder := Vector2.ZERO

	var shoulder_rad := deg_to_rad(shoulder_angle)
	var elbow := shoulder + Vector2(cos(shoulder_rad), sin(shoulder_rad)) * arm_length

	var elbow_rad := deg_to_rad(shoulder_angle + elbow_angle)
	var hand := elbow + Vector2(cos(elbow_rad), sin(elbow_rad)) * forearm_length

	var draw_color := base_color
	if action_flash_timer > 0.0:
		draw_color = Color.WHITE

	draw_circle(shoulder, 14.0, draw_color)
	draw_line(shoulder, elbow, draw_color, line_width)
	draw_circle(elbow, 10.0, draw_color)
	draw_line(elbow, hand, draw_color, line_width)
	draw_circle(hand, 12.0, draw_color)

	draw_string(
		ThemeDB.fallback_font,
		Vector2(-80, -140),
		"P%d %s | %s" % [player_id, current_action, phase],
		HORIZONTAL_ALIGNMENT_LEFT,
		220,
		16,
		draw_color
	)
