extends Control

signal robot_command(command: Dictionary)

var current_profile: String = "snappy"
var frame: int = 0
var last_action_frame: int = -999
var input_cooldown_frames: int = 12

@onready var state_label: Label = $Panel/VBoxContainer/StateLabel
@onready var profile_label: Label = $Panel/VBoxContainer/ProfileLabel
@onready var frame_label: Label = $Panel/VBoxContainer/FrameLabel
@onready var command_input: LineEdit = $Panel/VBoxContainer/CommandInput
@onready var log_box: RichTextLabel = $Panel/VBoxContainer/Log

func _ready() -> void:
	_connect_action_buttons()
	_connect_profile_buttons()

	command_input.text_submitted.connect(_on_text_command_submitted)

	state_label.text = "State: Idle"
	profile_label.text = "Profile: Snappy"
	frame_label.text = "Frame: 0"

	add_log("[b]Rollback Robotics UI Ready[/b]")
	add_log("Keyboard: Q=Jab, W=Heavy, E=Block, R=Wave, T=Grab")

func _process(_delta: float) -> void:
	frame += 1
	frame_label.text = "Frame: %d" % frame
	_handle_keyboard_input()

func _connect_action_buttons() -> void:
	$Panel/VBoxContainer/ButtonRow/JabButton.pressed.connect(func(): send_action("jab"))
	$Panel/VBoxContainer/ButtonRow/HeavyButton.pressed.connect(func(): send_action("heavy"))
	$Panel/VBoxContainer/ButtonRow/BlockButton.pressed.connect(func(): send_action("block"))
	$Panel/VBoxContainer/ButtonRow/WaveButton.pressed.connect(func(): send_action("wave"))
	$Panel/VBoxContainer/ButtonRow/GrabButton.pressed.connect(func(): send_action("grab"))

func _connect_profile_buttons() -> void:
	$Panel/VBoxContainer/ProfileRow/SnappyButton.pressed.connect(func(): set_profile("snappy"))
	$Panel/VBoxContainer/ProfileRow/HeavyProfileButton.pressed.connect(func(): set_profile("heavy"))
	$Panel/VBoxContainer/ProfileRow/DefensiveButton.pressed.connect(func(): set_profile("defensive"))
	$Panel/VBoxContainer/ProfileRow/DramaticButton.pressed.connect(func(): set_profile("dramatic"))

func _handle_keyboard_input() -> void:
	if frame - last_action_frame < input_cooldown_frames:
		return

	if Input.is_key_pressed(KEY_Q):
		send_action("jab")
	elif Input.is_key_pressed(KEY_W):
		send_action("heavy")
	elif Input.is_key_pressed(KEY_E):
		send_action("block")
	elif Input.is_key_pressed(KEY_R):
		send_action("wave")
	elif Input.is_key_pressed(KEY_T):
		send_action("grab")

func set_profile(profile: String) -> void:
	current_profile = profile
	profile_label.text = "Profile: %s" % profile.capitalize()
	add_log("Profile changed → %s" % profile)

func send_action(action: String) -> void:
	last_action_frame = frame

	var command: Dictionary = {
		"type": "play_action",
		"frame": frame,
		"player_id": 1,
		"action": action,
		"profile": current_profile,
		"intensity": 1.0,
		"motion_id": "%s_motion" % action,
		"source": "ui"
	}

	state_label.text = "State: %s" % action.capitalize()
	add_log("Command → %s" % JSON.stringify(command))
	print("ROBOT_JSON:", JSON.stringify(command))

	robot_command.emit(command)
func _on_text_command_submitted(text: String) -> void:
	var command := _parse_text_command(text)
	set_profile(command["profile"])
	send_action(command["action"])
	command_input.clear()

func _parse_text_command(text: String) -> Dictionary:
	var lower := text.to_lower()

	var action := "wave"
	var profile := current_profile

	if "jab" in lower or "punch" in lower or "strike" in lower:
		action = "jab"
	elif "heavy" in lower or "strong" in lower:
		action = "heavy"
	elif "block" in lower or "guard" in lower or "defend" in lower:
		action = "block"
	elif "grab" in lower or "clamp" in lower:
		action = "grab"
	elif "wave" in lower or "hello" in lower:
		action = "wave"

	if "dramatic" in lower or "theatrical" in lower:
		profile = "dramatic"
	elif "defensive" in lower or "safe" in lower or "careful" in lower:
		profile = "defensive"
	elif "heavy" in lower or "strong" in lower:
		profile = "heavy"
	elif "snappy" in lower or "fast" in lower or "quick" in lower:
		profile = "snappy"

	return {
		"action": action,
		"profile": profile
	}
func add_log(message: String) -> void:
	if log_box == null:
		return

	log_box.append_text("\n" + message)
	log_box.scroll_to_line(log_box.get_line_count())
	
func log(message: String) -> void:
	if log_box == null:
		return

	log_box.append_text("\n" + message)
	log_box.scroll_to_line(log_box.get_line_count())
	
