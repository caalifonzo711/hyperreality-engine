# res://games/rollback_fighter/scenes/Lobby.gd
extends CanvasLayer

@onready var room_field: LineEdit = $"Panel/RoomField"
@onready var host_btn: Button   = $"Panel/HBoxContainer/HostBtn"
@onready var join_btn: Button   = $"Panel/HBoxContainer/JoinBtn"
@onready var status_label: Label = $"Panel/StatusLabel"

func _ready() -> void:
	host_btn.pressed.connect(_on_host)
	join_btn.pressed.connect(_on_join)
	NetEvents.net_connected.connect(_on_connected)
	NetEvents.net_error.connect(_on_error)

func _on_host() -> void:
	status_label.text = "Hosting..."
	NetEvents.request_host.emit(room_field.text)

func _on_join() -> void:
	status_label.text = "Joining..."
	NetEvents.request_join.emit(room_field.text)

func _on_connected(peer_count: int) -> void:
	status_label.text = "Connected!"
	# Load your arena scene on success
	var arena = load("res://games/rollback_fighter/scenes/ArenaScene.tscn").instantiate()
	get_tree().current_scene.add_child(arena)
	queue_free() # remove lobby

func _on_error(msg: String) -> void:
	status_label.text = "Error: %s" % msg
