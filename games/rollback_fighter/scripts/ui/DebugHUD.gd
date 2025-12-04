extends CanvasLayer

@onready var tick_l   : Label = $Control/MarginContainer/VBoxContainer/TickLabel
@onready var pos_l    : Label = $Control/MarginContainer/VBoxContainer/PosLabel
@onready var input_l  : Label = $Control/MarginContainer/VBoxContainer/InputLabel
@onready var replay_l : Label = $Control/MarginContainer/VBoxContainer/ReplayLabel

var shown := true

func set_tick(t: int) -> void:
	if tick_l: tick_l.text = "Tick: %d" % t

func set_pos(p: Vector2, lean_dir: int) -> void:
	if pos_l: pos_l.text = "Pos: (%.1f, %.1f) | lean=%d" % [p.x, p.y, lean_dir]

func set_input(move: Vector2) -> void:
	if input_l: input_l.text = "Move: (%.2f, %.2f)" % [move.x, move.y]

func set_replay(msg: String) -> void:
	if replay_l: replay_l.text = msg

func _unhandled_input(e):
	if e.is_action_pressed("ui_toggle_hud"):
		shown = !shown
		visible = shown
