extends Node
class_name LatencyHarnessTransport

signal packet_received(packet: Dictionary)

@export var delay_frames: int = 6
@export var jitter_frames: int = 0
@export var drop_rate: float = 0.0

var current_frame: int = 0
var _queue: Array[Dictionary] = []

func reset() -> void:
	current_frame = 0
	_queue.clear()

func set_delay_frames(frames: int) -> void:
	delay_frames = max(0, frames)

func send_packet(packet: Dictionary) -> void:
	if drop_rate > 0.0 and randf() < drop_rate:
		return

	var jitter: int = 0
	if jitter_frames > 0:
		jitter = randi_range(-jitter_frames, jitter_frames)

	var deliver_frame: int = current_frame + max(0, delay_frames + jitter)

	_queue.append({
		"deliver_frame": deliver_frame,
		"packet": packet.duplicate(true),
	})

func tick() -> void:
	current_frame += 1

	var ready: Array[Dictionary] = []

	for item: Dictionary in _queue:
		if int(item.get("deliver_frame", 0)) <= current_frame:
			ready.append(item)

	for item: Dictionary in ready:
		_queue.erase(item)
		var packet: Dictionary = item.get("packet", {})
		packet_received.emit(packet)

func pending_count() -> int:
	return _queue.size()

func latency_ms_at_60fps() -> float:
	return float(delay_frames) * (1000.0 / 60.0)
