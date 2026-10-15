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

var local_checksum: int = 0
var remote_checksum: int = 0

var checksum_mismatch: bool = false

# Checksums stored by simulation frame.
var local_checksums: Dictionary = {}
var remote_checksums: Dictionary = {}
var local_checksum_revisions: Dictionary = {}
var remote_checksum_revisions: Dictionary = {}
var _checksum_resend_cursor: int = 0

# Comparison result stored by frame.
# true  = matching
# false = mismatch
var checksum_comparison_results: Dictionary = {}

# Benchmark/debug metrics.
var checksum_frames_compared: int = 0
var checksum_mismatch_count: int = 0
var first_checksum_mismatch_frame: int = -1

# -1 until player 1 selects the single frame to inspect.
var _first_state_debug_frame: int = -1


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

	local_checksum = 0
	remote_checksum = 0
	checksum_mismatch = false

	local_checksums.clear()
	remote_checksums.clear()
	local_checksum_revisions.clear()
	remote_checksum_revisions.clear()
	_checksum_resend_cursor = 0
	checksum_comparison_results.clear()

	checksum_frames_compared = 0
	checksum_mismatch_count = 0
	first_checksum_mismatch_frame = -1
	_first_state_debug_frame = -1

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

func _compute_checksum(snapshot: Dictionary) -> int:
	if adapter == null:
		return 0

	if not adapter.has_method("canonical_checksum"):
		return 0

	return int(adapter.canonical_checksum(snapshot))


func _send_checksum_packet(frame: int, checksum: int, revision: int) -> void:
	if transport == null:
		return

	if not transport.has_method("send_packet"):
		return

	transport.send_packet({
		"type": "checksum",
		"frame": frame,
		"player_id": player_id,
		"checksum": checksum,
		"revision": revision,
	})


func begin_checksum_resend() -> int:
	_checksum_resend_cursor = 0
	return local_checksums.size()


func resend_next_retained_checksum() -> bool:
	var frames: Array = local_checksums.keys()
	frames.sort()

	if frames.is_empty():
		return false

	if _checksum_resend_cursor >= frames.size():
		_checksum_resend_cursor = 0

	var frame: int = int(frames[_checksum_resend_cursor])
	_checksum_resend_cursor += 1

	_send_checksum_packet(
		frame,
		int(local_checksums[frame]),
		int(local_checksum_revisions.get(frame, 0))
	)
	return true


func _record_local_checksum(frame: int, send_to_peer: bool = true) -> void:
	var snapshot: Dictionary = adapter.capture()
	local_checksum = _compute_checksum(snapshot)
	var revision: int = int(local_checksum_revisions.get(frame, 0)) + 1

	local_checksums[frame] = local_checksum
	local_checksum_revisions[frame] = revision

	# If the remote checksum already exists, try comparing.
	# This is safe because _try_compare_checksum also checks
	# whether the real remote input exists.
	_try_compare_checksum(frame, true, snapshot)

	if send_to_peer:
		_send_checksum_packet(frame, local_checksum, revision)


func _try_compare_checksum(
	frame: int,
	state_is_current: bool = false,
	current_snapshot: Dictionary = {}
) -> void:
	if not local_checksums.has(frame):
		return

	if not remote_checksums.has(frame):
		return

	# Do not compare a frame while we are still missing
	# the real remote input for that frame.
	if not remote_inputs.has(frame):
		return

	var local_value: int = int(local_checksums[frame])
	var remote_value: int = int(remote_checksums[frame])

	var matches: bool = (local_value == remote_value)

	# First comparison for this frame.
	if not checksum_comparison_results.has(frame):
		checksum_comparison_results[frame] = matches
		checksum_frames_compared += 1

		if not matches:
			checksum_mismatch_count += 1

	else:
		# Frame may have been corrected by rollback after
		# an earlier comparison. Update the existing result
		# instead of counting the same frame twice.
		var previous_match: bool = bool(
			checksum_comparison_results[frame]
		)

		if previous_match != matches:
			checksum_comparison_results[frame] = matches

			if matches:
				checksum_mismatch_count = maxi(
					checksum_mismatch_count - 1,
					0
				)
			else:
				checksum_mismatch_count += 1

	_refresh_checksum_status()

	# Follow the earliest mismatch that remains unresolved after replay.
	if (
		player_id == 1
		and _first_state_debug_frame != first_checksum_mismatch_frame
	):
		_first_state_debug_frame = first_checksum_mismatch_frame

		if _first_state_debug_frame >= 0:
			var debug_snapshot: Dictionary = {}
			if state_is_current and _first_state_debug_frame == frame:
				debug_snapshot = current_snapshot
			_send_first_state_debug(
				_first_state_debug_frame,
				false,
				debug_snapshot
			)


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
	# Ignore checksum packets claiming to be ours.
	if int(packet.get("player_id", -1)) == player_id:
		return

	var frame: int = int(packet.get("frame", -1))

	if frame < 0:
		return

	var checksum: int = int(packet.get("checksum", 0))
	var revision: int = int(packet.get("revision", 0))
	var highest_revision: int = int(
		remote_checksum_revisions.get(frame, -1)
	)

	if revision < highest_revision:
		return

	remote_checksum = checksum
	remote_checksums[frame] = checksum
	remote_checksum_revisions[frame] = revision

	# This may do nothing if the real input/state for
	# the matching frame is not ready yet.
	_try_compare_checksum(frame)


# Single debug send path. Player 1 sends the probe; player 2 sends the reply.
func _send_first_state_debug(
	frame: int,
	is_reply: bool,
	snapshot_override: Dictionary = {}
) -> void:
	var snapshot: Dictionary = snapshot_override
	if snapshot.is_empty():
		snapshot = snapshots.get(frame + 1, {})

	if (
		snapshot.is_empty()
		and (current_frame == frame or current_frame == frame + 1)
	):
		snapshot = adapter.capture()

	if snapshot.is_empty():
		print("[StateDebug] State unavailable for frame %d" % frame)
		return

	transport.send_packet({
		"type": "first_state_debug",
		"frame": frame,
		"player_id": player_id,
		"reply": is_reply,
		"values": adapter.canonical_debug_values(snapshot),
	})


# Single debug receive path.
func _handle_first_state_debug(packet: Dictionary) -> void:
	if int(packet.get("player_id", -1)) == player_id:
		return

	var frame: int = int(packet.get("frame", -1))
	var is_reply: bool = bool(packet.get("reply", false))

	if frame < 0:
		return

	if player_id == 1:
		if not is_reply or frame != _first_state_debug_frame:
			return
	else:
		if is_reply:
			return
		_first_state_debug_frame = frame

	var snapshot: Dictionary = snapshots.get(frame + 1, {})

	if (
		snapshot.is_empty()
		and (current_frame == frame or current_frame == frame + 1)
	):
		snapshot = adapter.capture()

	if snapshot.is_empty():
		print("[StateDebug] State unavailable for frame %d" % frame)
		return

	adapter.report_first_debug_difference(
		frame,
		snapshot,
		packet.get("values", [])
	)

	if player_id == 2:
		_send_first_state_debug(frame, true, snapshot)


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
	# Send local input
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

	if local_checksum_revisions.has(old_frame):
		local_checksum_revisions.erase(old_frame)

	if remote_checksum_revisions.has(old_frame):
		remote_checksum_revisions.erase(old_frame)

	# Keep checksum_comparison_results for the whole
	# benchmark so final stats stay intact.

	# =================================================
	# Simulate current frame
	# =================================================

	_simulate_frame(
		delayed_local_input,
		remote_input
	)

	# Checksum represents state AFTER this frame.
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

	if packet_type == "first_state_debug":
		_handle_first_state_debug(packet)
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

	# =================================================
	# IMPORTANT FIX:
	#
	# Do NOT compare checksum here yet.
	#
	# First determine whether this newly received real
	# input invalidates a prediction.
	#
	# If so, rollback/replay must finish BEFORE we
	# compare the checksum for this frame.
	# =================================================

	if frame < current_frame:
		if predicted_remote_inputs.has(frame):
			var predicted: Dictionary = (
				predicted_remote_inputs[frame]
			)

			if predicted.hash() != input_data.hash():
				prediction_misses += 1

				# Correct the simulation FIRST.
				_rollback_and_replay(frame)

	# =================================================
	# NOW compare.
	#
	# At this point, if rollback was required, the
	# historical state/checksum has already been
	# recomputed using the real remote input.
	# =================================================

	_try_compare_checksum(frame)


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

	# Restore PRE-SIM state for first incorrect frame.
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

		# Corrected PRE-SIM snapshot.
		snapshots[replay_frame] = adapter.capture()

		# Replay this historical frame.
		_simulate_frame(
			local_input,
			remote_input
		)

		# Recompute + resend the checksum because this
		# historical frame may now contain corrected state.
		_record_local_checksum(
			replay_frame,
			true
		)

		replay_frame += 1

	current_frame = original_current_frame
