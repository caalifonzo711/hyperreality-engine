# res://addons/rollback_netplay_mvp/src/RollbackSyncSystem.gd
extends Node
class_name RollbackSyncSystem

signal remote_input(frame:int, payload:Dictionary)
signal state_rewound(from_frame:int, to_frame:int)

const DEFAULT_TICK_RATE := 60
const LOOPBACK_DELAY_FRAMES := 3   # pretend network delay (tweak as needed)

var _tick_rate: int = DEFAULT_TICK_RATE
var _running: bool = false
var _timer := Timer.new()

# Frame clock
var _frame: int = 0

# Buffers
# local inputs pushed for *current* frame (frame -> [payloads])
var _local_inputs: Dictionary = {}
# schedule to echo back later as "remote" (deliver_at_frame -> [payloads])
var _pending_remote: Dictionary = {}

func _ready() -> void:
	_timer.one_shot = false
	add_child(_timer)
	_timer.timeout.connect(_on_tick)

func start(tick_rate:int = DEFAULT_TICK_RATE, adaptor:String = "dummy") -> void:
	_tick_rate = max(1, tick_rate)
	_timer.wait_time = 1.0 / float(_tick_rate)
	_timer.start()
	_running = true
	_frame = 0
	_local_inputs.clear()
	_pending_remote.clear()

func stop() -> void:
	_running = false
	_timer.stop()

func is_running() -> bool:
	return _running

func current_frame() -> int:
	return _frame

func push_input(frame:int, payload:Dictionary) -> void:
	# Accept inputs for any frame (usually caller uses current_frame()).
	if not _local_inputs.has(frame):
		_local_inputs[frame] = []
	_local_inputs[frame].append(payload)

func _on_tick() -> void:
	if not _running:
		return

	_frame += 1

	# 1) Schedule any local inputs from this frame to arrive later as "remote".
	if _local_inputs.has(_frame):
		var deliver_at := _frame + LOOPBACK_DELAY_FRAMES
		if not _pending_remote.has(deliver_at):
			_pending_remote[deliver_at] = []
		for p in _local_inputs[_frame]:
			_pending_remote[deliver_at].append(p)
		# Optional: clear after scheduling to keep memory tidy
		_local_inputs.erase(_frame)

	# 2) Deliver any remote packets due on this frame.
	if _pending_remote.has(_frame):
		for p in _pending_remote[_frame]:
			remote_input.emit(_frame, p)
		_pending_remote.erase(_frame)

	# 3) (Stub) Rewind detection would live here; emit state_rewound(...) when needed.
	# For the echo demo we don't actually rewind—this is purely to visualize the loop.
