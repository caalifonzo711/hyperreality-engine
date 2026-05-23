extends Node
class_name RobotRollbackSession

signal local_command_ready(command: Dictionary)
signal remote_command_predicted(command: Dictionary)
signal rollback_requested(from_frame: int, to_frame: int)

@export var player_id: int = 1
@export var max_rollback_frames: int = 12

var current_frame: int = 0
var remote_buffer: RobotRemoteInputBuffer

var local_commands: Dictionary = {}
var snapshots: Dictionary = {}

func _ready() -> void:
	remote_buffer = RobotRemoteInputBuffer.new()
	add_child(remote_buffer)

func advance_frame(local_command: Dictionary = {}) -> Dictionary:
	current_frame += 1

	var normalized_local := _normalize_local_command(local_command)
	var remote_command := remote_buffer.get_command(current_frame)

	local_commands[current_frame] = normalized_local
	_save_snapshot(current_frame)

	local_command_ready.emit(normalized_local)

	if remote_command.get("source", "") == "predicted_remote":
		remote_command_predicted.emit(remote_command)

	return {
		"frame": current_frame,
		"local": normalized_local,
		"remote": remote_command
	}

func receive_remote_command(command: Dictionary) -> void:
	var frame := int(command.get("frame", current_frame))

	remote_buffer.store_remote_command(frame, command)

	if frame < current_frame:
		var diff := current_frame - frame

		if diff <= max_rollback_frames:
			rollback_requested.emit(frame, current_frame)
			print("Rollback requested from frame %d to %d" % [frame, current_frame])
		else:
			print("Late command ignored. Too old: ", command)

func get_snapshot(frame: int) -> Dictionary:
	if snapshots.has(frame):
		return snapshots[frame].duplicate(true)

	return {}

func _save_snapshot(frame: int) -> void:
	snapshots[frame] = {
		"frame": frame,
		"player_id": player_id,
		"local_command": local_commands.get(frame, {}),
		"remote_command": remote_buffer.get_command(frame)
	}

	_cleanup_old_snapshots()

func _cleanup_old_snapshots() -> void:
	var min_frame := current_frame - max_rollback_frames - 2
	var frames_to_remove: Array = []

	for frame in snapshots.keys():
		if int(frame) < min_frame:
			frames_to_remove.append(frame)

	for frame in frames_to_remove:
		snapshots.erase(frame)

func _normalize_local_command(command: Dictionary) -> Dictionary:
	if command.is_empty():
		return {
			"frame": current_frame,
			"player_id": player_id,
			"action": "idle",
			"profile": "snappy",
			"intensity": 1.0,
			"source": "local_idle"
		}

	var normalized := command.duplicate(true)
	normalized["frame"] = current_frame
	normalized["player_id"] = player_id
	normalized["source"] = normalized.get("source", "local")
	return normalized

func reset() -> void:
	current_frame = 0
	local_commands.clear()
	snapshots.clear()

	if remote_buffer != null:
		remote_buffer.reset()
