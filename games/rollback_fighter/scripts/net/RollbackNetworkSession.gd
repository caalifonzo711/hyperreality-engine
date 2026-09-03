extends Node
class_name RollbackNetworkSession

const PHYS_DT := 1.0 / 60.0
const MAX_ROLLBACK_FRAMES := 60

var player_id: int = 1
var input_delay_frames: int = 0

var current_frame: int = 0

var local_inputs: Dictionary = {}
var remote_inputs: Dictionary = {}
var predicted_remote_inputs: Dictionary = {}
var snapshots: Dictionary = {}

var rollback_count: int = 0
var max_rollback_depth: int = 0
var prediction_misses: int = 0
var packets_received: int = 0
var last_remote_frame: int = -1
var match_started: bool = false

var adapter: FighterRollbackAdapter = null
var transport: Node = null


# =================================================
# Checksum state
# =================================================

# Most recently generated / received values.
# Kept for simple HUD/debugging compatibility.
var local_checksum: int = 0
var remote_checksum: int = 0

# True if there are currently any unresolved
# frame-aligned checksum mismatches.
var checksum_mismatch: bool = false

# Checksums stored by simulation frame.
var local_checksums: Dictionary = {}
var remote_checksums: Dictionary = {}

# Comparison result stored by frame.
# true  = matching
# false = mismatch
var checksum_comparison_results: Dictionary = {}

# Benchmark/debug metrics.
var checksum_frames_compared: int = 0
var checksum_mismatch_count: int = 0
var first_checksum_mismatch_frame: int = -1


# =================================================
# Prediction cache
# =================================================

var _last_remote_input: Dictionary = {
	"mx": 0.0,
	"lean_l": false,
	"lean_r": false,
	"atk_l": false,
	"atk_h": false,
	"block": false,
	"dodge": false,
}


func setup(
	_adapter: FighterRollbackAdapter,
	_transport: Node,
	_player_id: int = 1
) -> void:
	adapter = _adapter
	transport = _transport
	player_id = _player_id

	if transport and transport.has_signal("packet_received"):
		if not transport.packet_received.is_connected(_on_packet_received):
			transport.packet_received.connect(_on_packet_received)


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

	# -----------------------------
	# Reset checksum state
	# -----------------------------
	local_checksum = 0
	remote_checksum = 0
	checksum_mismatch = false

	local_checksums.clear()
	remote_checksums.clear()
	checksum_comparison_results.clear()

	checksum_frames_compared = 0
	checksum_mismatch_count = 0
	first_checksum_mismatch_frame = -1

	_last_remote_input = _empty_input()

	match_started = false


func start_session() -> void:
	reset_session()
	match_started = true


func frame_gap() -> int:
	if last_remote_frame < 0:
		return 0

	return current_frame - last_remote_frame


func _empty_input() -> Dictionary:
	return {
		"mx": 0.0,
		"lean_l": false,
		"lean_r": false,
		"atk_l": false,
		"atk_h": false,
		"block": false,
		"dodge": false,
	}


# =================================================
# Checksum helpers
# =================================================

func _compute_checksum() -> int:
	if adapter == null:
		return 0

	if not adapter.has_method("capture"):
		return 0

	var snapshot: Dictionary = adapter.capture()

	# First-pass implementation:
	# use Godot's hash of our rollback snapshot.
	#
	# If Windows <-> Android later produces suspicious
	# platform-specific mismatches, this is the function
	# we can replace with explicit canonical serialization.
	return snapshot.hash()


func _send_checksum_packet(frame: int, checksum: int) -> void:
	if transport == null:
		return

	if not transport.has_method("send_packet"):
		return

	transport.send_packet({
		"type": "checksum",
		"frame": frame,
		"player_id": player_id,
		"checksum": checksum,
	})


func _record_local_checksum(frame: int, send_to_peer: bool = true) -> void:
	local_checksum = _compute_checksum()

	local_checksums[frame] = local_checksum

	# If the remote checksum already arrived,
	# compare the same simulation frame now.
	_try_compare_checksum(frame)

	if send_to_peer:
		_send_checksum_packet(frame, local_checksum)


func _try_compare_checksum(frame: int) -> void:
	if not local_checksums.has(frame):
		return

	if not remote_checksums.has(frame):
		return

	# Do not treat a frame as authoritative until
	# we have received the real remote input for it.
	#
	# Before that, our state may legitimately contain
	# prediction and temporarily differ from the peer.
	if not remote_inputs.has(frame):
		return

	var local_value: int = int(local_checksums[frame])
	var remote_value: int = int(remote_checksums[frame])

	var matches: bool = (local_value == remote_value)

	# -----------------------------------------
	# First comparison for this frame
	# -----------------------------------------
	if not checksum_comparison_results.has(frame):
		checksum_comparison_results[frame] = matches
		checksum_frames_compared += 1

		if not matches:
			checksum_mismatch_count += 1

	# -----------------------------------------
	# Frame was compared before, but rollback
	# may have changed its final checksum.
	# Update the existing result instead of
	# counting the frame twice.
	# -----------------------------------------
	else:
		var previous_match: bool = bool(
			checksum_comparison_results[frame]
		)

		if previous_match != matches:
			checksum_comparison_results[frame] = matches

			if matches:
				# A temporary mismatch was corrected
				# after rollback/replay.
				checksum_mismatch_count = maxi(
					checksum_mismatch_count - 1,
					0
				)
			else:
				# A frame that previously matched
				# now disagrees after correction.
				checksum_mismatch_count += 1

	_refresh_checksum_status()


func _refresh_checksum_status() -> void:
	checksum_mismatch = checksum_mismatch_count > 0

	first_checksum_mismatch_frame = -1

	if checksum_mismatch_count <= 0:
		return

	var frames: Array = checksum_comparison_results.keys()
	frames.sort()

	for frame_variant in frames:
		var frame: int = int(frame_variant)

		if not bool(checksum_comparison_results[frame]):
			first_checksum_mismatch_frame = frame
			return


func _handle_checksum_packet(packet: Dictionary) -> void:
	# Ignore a checksum packet claiming to be ours.
	if int(packet.get("player_id", -1)) == player_id:
		return

	var frame: int = int(packet.get("frame", -1))

	if frame < 0:
		return

	var checksum: int = int(packet.get("checksum", 0))

	remote_checksum = checksum
	remote_checksums[frame] = checksum

	# Compare only against OUR checksum for
	# the exact same simulation frame.
	_try_compare_checksum(frame)


# =================================================
# Simulation
# =================================================

func _simulate_frame(
	local_input: Dictionary,
	remote_input: Dictionary
) -> void:
	if adapter == null:
		return

	if player_id == 1:
		adapter.simulate(
			local_input,
			remote_input,
			PHYS_DT
		)
	else:
		adapter.simulate(
			remote_input,
			local_input,
			PHYS_DT
		)


func tick(local_input: Dictionary) -> void:
	if adapter == null:
		return

	if not match_started:
		return

	if transport and transport.has_method("tick"):
		transport.tick()

	var input_frame: int = (
		current_frame
		+ max(0, input_delay_frames)
	)

	local_inputs[input_frame] = local_input.duplicate(true)

	# =================================================
	# Send input packet
	# =================================================

	if transport and transport.has_method("send_packet"):
		transport.send_packet({
			"type": "input",
			"frame": input_frame,
			"player_id": player_id,
			"input": local_input.duplicate(true),
		})

	var delayed_local_input: Dictionary = local_inputs.get(
		current_frame,
		_empty_input()
	)

	var remote_input: Dictionary = {}

	if remote_inputs.has(current_frame):
		remote_input = remote_inputs[current_frame]
		_last_remote_input = remote_input.duplicate(true)
	else:
		remote_input = _predict_remote_input(current_frame)

	# Save PRE-SIMULATION snapshot.
	# This is the state we restore if this frame
	# later needs to be replayed.
	snapshots[current_frame] = adapter.capture()

	# =================================================
	# Cleanup old rollback history
	# =================================================

	var old_frame: int = (
		current_frame
		- MAX_ROLLBACK_FRAMES
	)

	if snapshots.has(old_frame):
		snapshots.erase(old_frame)

	if local_inputs.has(old_frame):
		local_inputs.erase(old_frame)

	if remote_inputs.has(old_frame):
		remote_inputs.erase(old_frame)

	if predicted_remote_inputs.has(old_frame):
		predicted_remote_inputs.erase(old_frame)

	if local_checksums.has(old_frame):
		local_checksums.erase(old_frame)

	if remote_checksums.has(old_frame):
		remote_checksums.erase(old_frame)

	# NOTE:
	# checksum_comparison_results is intentionally NOT
	# erased here. It is tiny (~3600 entries for a
	# 60-second benchmark) and preserves benchmark-wide
	# checksum statistics.

	# =================================================
	# Simulate frame
	# =================================================

	_simulate_frame(
		delayed_local_input,
		remote_input
	)

	# =================================================
	# Compute + send checksum AFTER simulation.
	#
	# This checksum represents the resulting state
	# after current_frame has been simulated.
	# =================================================

	_record_local_checksum(
		current_frame,
		true
	)

	current_frame += 1


# =================================================
# Prediction
# =================================================

func _predict_remote_input(frame: int) -> Dictionary:
	var predicted: Dictionary = (
		_last_remote_input.duplicate(true)
	)

	predicted_remote_inputs[frame] = predicted

	return predicted


# =================================================
# Network receive
# =================================================

func _on_packet_received(packet: Dictionary) -> void:
	var packet_type: String = str(
		packet.get("type", "")
	)

	# =================================================
	# Checksum packet
	# =================================================

	if packet_type == "checksum":
		_handle_checksum_packet(packet)
		return

	# =================================================
	# Ignore non-input packets
	# =================================================

	if packet_type != "input":
		return

	# Ignore echoed local packets.
	if int(packet.get("player_id", -1)) == player_id:
		return

	var frame: int = int(
		packet.get("frame", -1)
	)

	var input_data: Dictionary = packet.get(
		"input",
		{}
	)

	if frame < 0:
		return

	packets_received += 1
	last_remote_frame = frame

	remote_inputs[frame] = input_data.duplicate(true)

	# Now that the real remote input exists,
	# a checksum for this frame may be eligible
	# for comparison.
	_try_compare_checksum(frame)

	# Future/current packet:
	# no rollback needed yet.
	if frame >= current_frame:
		return

	# =================================================
	# Prediction correction
	# =================================================

	if predicted_remote_inputs.has(frame):
		var predicted: Dictionary = (
			predicted_remote_inputs[frame]
		)

		if predicted.hash() != input_data.hash():
			prediction_misses += 1
			_rollback_and_replay(frame)


# =================================================
# Rollback + replay
# =================================================

func _rollback_and_replay(from_frame: int) -> void:
	if adapter == null:
		return

	if not snapshots.has(from_frame):
		return

	var original_current_frame: int = current_frame

	var rollback_depth: int = (
		original_current_frame
		- from_frame
	)

	rollback_count += 1

	max_rollback_depth = max(
		max_rollback_depth,
		rollback_depth
	)

	# Restore the PRE-SIMULATION state
	# for the first incorrect frame.
	adapter.restore(
		snapshots[from_frame]
	)

	var replay_frame: int = from_frame

	while replay_frame < original_current_frame:
		var local_input: Dictionary = local_inputs.get(
			replay_frame,
			_empty_input()
		)

		var remote_input: Dictionary = {}

		if remote_inputs.has(replay_frame):
			remote_input = remote_inputs[replay_frame]
			_last_remote_input = (
				remote_input.duplicate(true)
			)
		else:
			remote_input = _predict_remote_input(
				replay_frame
			)

		# Save corrected PRE-SIM snapshot.
		snapshots[replay_frame] = adapter.capture()

		# Re-simulate the frame.
		_simulate_frame(
			local_input,
			remote_input
		)

		# =================================================
		# IMPORTANT:
		# Rollback may have changed the state produced
		# by this historical frame.
		#
		# Recompute its checksum AND resend it so the
		# peer can replace an earlier checksum that may
		# have represented predicted state.
		# =================================================

		_record_local_checksum(
			replay_frame,
			true
		)

		replay_frame += 1

	current_frame = original_current_frame
