extends Node
class_name RollbackNetworkSession

const PHYS_DT := 1.0 / 60.0
const MAX_ROLLBACK_FRAMES := 60

var player_id: int = 1

# -----------------------------
# Core timeline state
# -----------------------------
var current_frame: int = 0

# frame -> input
var local_inputs: Dictionary = {}
var remote_inputs: Dictionary = {}
var predicted_remote_inputs: Dictionary = {}

# frame -> snapshot
var snapshots: Dictionary = {}

# -----------------------------
# Metrics
# -----------------------------
var rollback_count: int = 0
var max_rollback_depth: int = 0
var prediction_misses: int = 0

#timemachine
var match_started: bool = false
# -----------------------------
# Dependencies
# -----------------------------
var adapter: FighterRollbackAdapter = null
var transport: Node = null

# -----------------------------
# Prediction cache
# -----------------------------
var _last_remote_input: Dictionary = {
	"mx": 0.0,
	"lean_l": false,
	"lean_r": false,
	"atk_l": false,
	"atk_h": false,
	"block": false,
	"dodge": false,
}
var packets_received: int = 0
var last_remote_frame: int = -1

func reset_session() -> void:
	current_frame = 0
	local_inputs.clear()
	remote_inputs.clear()
	predicted_remote_inputs.clear()
	snapshots.clear()
	rollback_count = 0
	max_rollback_depth = 0
	prediction_misses = 0
	packets_received = 0
	last_remote_frame = -1
	match_started = false

func start_session() -> void:
	reset_session()
	match_started = true
	
	
func setup(_adapter: FighterRollbackAdapter, _transport: Node, _player_id: int = 1) -> void:
	adapter = _adapter
	transport = _transport
	player_id = _player_id

	if transport and transport.has_signal("packet_received"):
		if not transport.packet_received.is_connected(_on_packet_received):
			transport.packet_received.connect(_on_packet_received)


func _simulate_frame(local_input: Dictionary, remote_input: Dictionary) -> void:
	if player_id == 1:
		adapter.simulate(local_input, remote_input, PHYS_DT)
	else:
		adapter.simulate(remote_input, local_input, PHYS_DT)


func tick(local_input: Dictionary) -> void:
	if adapter == null:
		return
	if not match_started:
		return
	if transport and transport.has_method("tick"):
		transport.tick()

	local_inputs[current_frame] = local_input.duplicate(true)

	if transport and transport.has_method("send_packet"):
		transport.send_packet({
			"type": "input",
			"frame": current_frame,
			"player_id": player_id,
			"input": local_input.duplicate(true)
		})

	var remote_input: Dictionary = {}

	if remote_inputs.has(current_frame):
		remote_input = remote_inputs[current_frame]
		_last_remote_input = remote_input.duplicate(true)
	else:
		remote_input = _predict_remote_input(current_frame)

	snapshots[current_frame] = adapter.capture()

	var old_frame: int = current_frame - MAX_ROLLBACK_FRAMES

	if snapshots.has(old_frame):
		snapshots.erase(old_frame)

	if local_inputs.has(old_frame):
		local_inputs.erase(old_frame)

	if remote_inputs.has(old_frame):
		remote_inputs.erase(old_frame)

	if predicted_remote_inputs.has(old_frame):
		predicted_remote_inputs.erase(old_frame)

	_simulate_frame(local_input, remote_input)

	current_frame += 1


func _predict_remote_input(frame: int) -> Dictionary:
	var predicted: Dictionary = _last_remote_input.duplicate(true)
	predicted_remote_inputs[frame] = predicted
	return predicted


#func _on_packet_received(packet: Dictionary) -> void:
#	if packet.get("type", "") != "input":
	#	return

#	if int(packet.get("player_id", -1)) == player_id:
	#	return

	#var frame: int = int(packet.get("frame", -1))
#	var input_data: Dictionary = packet.get("input", {})

#	if frame < 0:
#		return

	#remote_inputs[frame] = input_data.duplicate(true)

#	if frame >= current_frame:
	#	return

	#if predicted_remote_inputs.has(frame):
	#	var predicted: Dictionary = predicted_remote_inputs[frame]

	#	if predicted.hash() != input_data.hash():
	#		prediction_misses += 1
	#		_rollback_and_replay(frame)
func _on_packet_received(packet: Dictionary) -> void:
	if packet.get("type", "") != "input":
		return

	# Ignore our own echoed packets
	if int(packet.get("player_id", -1)) == player_id:
		return

	var frame: int = int(packet.get("frame", -1))
	var input_data: Dictionary = packet.get("input", {})

	if frame < 0:
		return

	# -----------------------------
	# Packet metrics
	# -----------------------------
	packets_received += 1
	last_remote_frame = frame

	# -----------------------------
	# Store remote input
	# -----------------------------
	remote_inputs[frame] = input_data.duplicate(true)

	# If packet is for current/future frame,
	# no rollback required yet.
	if frame >= current_frame:
		return

	# -----------------------------
	# Prediction miss detection
	# -----------------------------
	if predicted_remote_inputs.has(frame):
		var predicted: Dictionary = predicted_remote_inputs[frame]

		if predicted.hash() != input_data.hash():
			prediction_misses += 1
			_rollback_and_replay(frame)


func _rollback_and_replay(from_frame: int) -> void:
	if adapter == null:
		return

	if not snapshots.has(from_frame):
		return

	var original_current_frame: int = current_frame
	var rollback_depth: int = original_current_frame - from_frame

	rollback_count += 1
	max_rollback_depth = max(max_rollback_depth, rollback_depth)

	adapter.restore(snapshots[from_frame])

	var replay_frame: int = from_frame

	while replay_frame < original_current_frame:
		var local_input: Dictionary = local_inputs.get(replay_frame, {})
		var remote_input: Dictionary = {}

		if remote_inputs.has(replay_frame):
			remote_input = remote_inputs[replay_frame]
			_last_remote_input = remote_input.duplicate(true)
		else:
			remote_input = _predict_remote_input(replay_frame)

		snapshots[replay_frame] = adapter.capture()

		_simulate_frame(local_input, remote_input)

		replay_frame += 1

	current_frame = original_current_frame
