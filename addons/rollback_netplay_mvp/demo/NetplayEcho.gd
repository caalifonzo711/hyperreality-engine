# res://addons/rollback_netplay_mvp/demo/NetplayEcho.gd
#NetplayEcho.gd
extends Node2D

@onready var local_cube  : ColorRect = $LocalCube
@onready var remote_cube : ColorRect = $RemoteCube

var _speed   := 280.0
var _local_x := 80.0
var _remote_x := 260.0

var _rn : Node = null       # Autoload instance of RollbackNetplay
var _frame := 0             # simple local frame counter (demo)

func _ready() -> void:
	# Find the autoload by absolute path so we don't collide with the class_name
	_rn = get_node_or_null("/root/RollbackNetplaySingleton")
	if _rn:
		# Start the rollback loop at 60 Hz
		_rn.start(60)
		# Hook signals (these exist in your Rollback* scripts)
		if _rn.has_signal("remote_input"):
			_rn.connect("remote_input", Callable(self, "_on_remote_input"))
		if _rn.has_signal("tick_advanced"):
			_rn.connect("tick_advanced", Callable(self, "_on_tick"))
	else:
		push_warning("RollbackNetplay autoload not found. Is the plugin enabled?")

	# Initial placement
	local_cube.position.x  = _local_x
	remote_cube.position.x = _remote_x
	
	print_tree_pretty()
	print("Has RN autoload? ", is_instance_valid(_rn))


func _process(delta: float) -> void:
	# ---------- INPUT HERE ----------
	# Use ui_right/ui_left or swap to your custom actions.
	var dir := Input.get_action_strength("ui_right") - Input.get_action_strength("ui_left")
	# var dir := Input.get_action_strength("move_right") - Input.get_action_strength("move_left")
	# --------------------------------
	_local_x += dir * _speed * delta
	local_cube.position.x = _local_x

	# Push the intention into rollback each frame (with a monotonically increasing frame index)
	if _rn:
		_rn.push_input(_frame, {"x": _local_x})
		_frame += 1

# Called once per rollback tick if you connected tick_advanced
func _on_tick(_frame_idx:int) -> void:
	# For the Echo demo we already moved local in _process.
	# In a real game: apply both local and buffered remote *deterministically* here.
	pass

# Receives inputs coming from the remote peer / buffer
func _on_remote_input(frame:int, payload:Dictionary) -> void:
	if payload.has("x"):
		_remote_x = float(payload["x"])
		remote_cube.position.x = _remote_x
