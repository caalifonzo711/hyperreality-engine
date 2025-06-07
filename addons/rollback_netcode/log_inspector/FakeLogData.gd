extends Resource
class_name FakeLogData

# Fake rollback log simulator

var frames := {}
var total_frames := 60
var start_time := 0
var end_time := total_frames

func generate_fake_log():
	frames.clear()
	var peer_id = 0
	frames[peer_id] = []

	for i in range(total_frames):
		var frame_info = {
			"frame": i,
			"input": null,
			"rollback_triggered": false,
			"start_time": i  # needed for UI comparison
		}

		if i % 10 == 0:
			frame_info.input = "PAGE_TURN"

		if i % 15 == 0 and i != 0:
			frame_info.rollback_triggered = true

		frames[peer_id].append(frame_info)

func get_frame_count(peer_id: int) -> int:
	if frames.has(peer_id):
		return frames[peer_id].size()
	return 0

func get_frame(peer_id: int, frame_id: int) -> Dictionary:
	if frames.has(peer_id) and frame_id < frames[peer_id].size():
		return frames[peer_id][frame_id]
	return {}

func is_loading() -> bool:
	return false
