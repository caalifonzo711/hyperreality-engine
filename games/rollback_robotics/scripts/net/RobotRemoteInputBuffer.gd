extends Node
class_name RobotRemoteInputBuffer

var inputs_by_frame: Dictionary = {}
var last_known_command: Dictionary = {
	"action": "idle",
	"profile": "snappy",
	"intensity": 1.0,
	"source": "predicted"
}

func store_remote_command(frame: int, command: Dictionary) -> void:
	inputs_by_frame[frame] = command.duplicate(true)
	last_known_command = command.duplicate(true)

func has_command(frame: int) -> bool:
	return inputs_by_frame.has(frame)

func get_command(frame: int) -> Dictionary:
	if inputs_by_frame.has(frame):
		return inputs_by_frame[frame].duplicate(true)

	var predicted := last_known_command.duplicate(true)
	predicted["frame"] = frame
	predicted["source"] = "predicted_remote"
	return predicted

func clear_before(frame: int) -> void:
	var frames_to_remove: Array = []

	for stored_frame in inputs_by_frame.keys():
		if int(stored_frame) < frame:
			frames_to_remove.append(stored_frame)

	for stored_frame in frames_to_remove:
		inputs_by_frame.erase(stored_frame)

func reset() -> void:
	inputs_by_frame.clear()
	last_known_command = {
		"action": "idle",
		"profile": "snappy",
		"intensity": 1.0,
		"source": "predicted"
	}
