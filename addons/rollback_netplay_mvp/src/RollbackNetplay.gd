# res://addons/rollback_netplay_mvp/src/RollbackNetplay.gd
extends Node
class_name RollbackNetplay  # autoload-friendly

signal tick_advanced(frame_idx: int)
signal remote_input(frame_idx: int, payload: Dictionary)

var _cb_collect  : Callable
var _cb_simulate : Callable
var _cb_capture  : Callable
var _cb_restore  : Callable

var _timer: Timer = Timer.new()
var _running: bool = false
var _frame: int = 0
var _hz: int = 60
var _dt: float = 1.0 / 60.0
var _loopback_delay: int = 2

var _input_buffer: Dictionary = {}    # { int: Array }

func _ready() -> void:
	_timer.one_shot = false
	add_child(_timer)
	_timer.timeout.connect(_on_tick)

func set_callbacks(collect: Callable, simulate: Callable, capture: Callable, restore: Callable) -> void:
	_cb_collect  = collect
	_cb_simulate = simulate
	_cb_capture  = capture
	_cb_restore  = restore

func start(hz: int = 60, _mode: String = "fighter") -> void:
	_hz = max(1, hz)
	_dt = 1.0 / float(_hz)
	_frame = 0
	_running = true
	_input_buffer.clear()
	_timer.wait_time = _dt
	_timer.start()
	print("[RN] start hz=%d dt=%f" % [_hz, _dt])

func stop() -> void:
	_running = false
	_timer.stop()

func get_current_frame() -> int:
	return _frame

func push_input(frame_idx: int, payload: Dictionary) -> void:
	if not _input_buffer.has(frame_idx):
		_input_buffer[frame_idx] = []
	_input_buffer[frame_idx].append(payload)

func _on_tick() -> void:
	if not _running:
		return

	if _cb_collect and _cb_collect.is_valid():
		var collected: Dictionary = _cb_collect.call()
		if collected and not collected.is_empty():
			push_input(_frame, collected)

	var local_inputs: Array = []
	var remote_inputs: Array = []

	if _input_buffer.has(_frame):
		local_inputs = _input_buffer[_frame]

	var deliver_frame: int = _frame - _loopback_delay
	if _input_buffer.has(deliver_frame):
		remote_inputs = _input_buffer[deliver_frame]

	var local_payload: Dictionary = {}
	var remote_payload: Dictionary = {}

	if local_inputs.size() > 0:
		local_payload = local_inputs[0]

	if remote_inputs.size() > 0:
		remote_payload = remote_inputs[0]
		remote_input.emit(deliver_frame, remote_payload)

	if _cb_simulate and _cb_simulate.is_valid():
		_cb_simulate.call(local_payload, remote_payload, _dt)

	tick_advanced.emit(_frame)
	_frame += 1
