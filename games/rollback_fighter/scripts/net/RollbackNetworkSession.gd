extends Node
class_name RollbackNetworkSession

const PHYS_DT := 1.0 / 60.0
const MAX_ROLLBACK_FRAMES := 60
const MAX_PREDICTION_FRAMES := 8
const INPUT_REDUNDANCY_FRAMES := 12
const REPAIR_REQUEST_RETRY_TICKS := 30
const SYNC_SAMPLE_WINDOW := 31
const SYNC_EWMA_ALPHA := 0.1
const SYNC_MAX_RTT_FRAMES := 60
const SYNC_MAX_ABS_OFFSET_FRAMES := 60.0
const SYNC_MAX_MEDIAN_DEVIATION_FRAMES := 12.0
const SOFT_SYNC_ENTER_ADVANTAGE := 2.0
const SOFT_SYNC_EXIT_ADVANTAGE := 1.0
const SOFT_SYNC_REQUIRED_SAMPLES := 5
const SOFT_SYNC_YIELD_INTERVAL := 10
const REPAIR_REQUEST_MAX_AGE := (
	MAX_ROLLBACK_FRAMES - MAX_PREDICTION_FRAMES - 1
)

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
# Compatibility frontier used by the existing prediction-lead behavior.
var last_remote_frame: int = -1
var last_remote_input_frame: int = -1
var last_remote_sim_frame: int = -1
var peer_confirmed_local_through: int = -1
var finalized_through: int = -1
var raw_estimated_frame_offset: float = 0.0
var filtered_estimated_frame_offset: float = 0.0
var last_sync_rtt_frames: int = -1
var last_sync_sample_age_frames: int = -1
var soft_sync_active: bool = false
var soft_sync_ahead_samples: int = 0
var soft_sync_yield_ticks: int = 0
var soft_sync_yield_cooldown: int = 0
var max_prediction_lead: int = 0
var lead_stalled: bool = false
var lead_stall_ticks: int = 0
var redundant_frames_received: int = 0
var recovered_missing_frames: int = 0
var duplicate_input_frames: int = 0
var history_exhausted: bool = false
var history_exhaustion_frame: int = -1
var input_mutation_error: bool = false
var input_mutation_error_frame: int = -1
var repair_requests_sent: int = 0
var repair_requests_received: int = 0
var repair_responses_sent: int = 0
var repair_responses_received: int = 0
var last_repair_requested_frame: int = -1
var last_repair_recovered_frame: int = -1
var repair_unavailable_error: bool = false
var repair_unavailable_count: int = 0
var match_started: bool = false

var adapter: FighterRollbackAdapter = null
var transport: Node = null
var _repair_tick: int = 0
var _pending_repair_frame: int = -1
var _next_repair_request_tick: int = 0
var _repair_unavailable_frame: int = -1
var _next_sync_sequence: int = 0
var _last_received_sync_sequence: int = -1
var _last_received_sync_receive_frame: int = -1
var _sync_sent_frames: Dictionary = {}
var _sync_offset_samples: Array[float] = []
var _has_filtered_sync_sample: bool = false


# =================================================
# Checksum state
# =================================================

var local_checksum: int = 0
var remote_checksum: int = 0

var checksum_mismatch: bool = false

# Checksums stored by simulation frame.
var local_checksums: Dictionary = {}
var remote_checksums: Dictionary = {}
var remote_confirmed_through: int = -1
var local_checksum_confirmed_through: int = -1
var _confirmation_history_error_frame: int = -1

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

	if transport and transport.has_signal("input_repair_request_received"):
		if not transport.input_repair_request_received.is_connected(
			_on_input_repair_request_received
		):
			transport.input_repair_request_received.connect(
				_on_input_repair_request_received
			)

	if transport and transport.has_signal("input_repair_response_received"):
		if not transport.input_repair_response_received.is_connected(
			_on_input_repair_response_received
		):
			transport.input_repair_response_received.connect(
				_on_input_repair_response_received
			)


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
	last_remote_input_frame = -1
	last_remote_sim_frame = -1
	peer_confirmed_local_through = -1
	finalized_through = -1
	raw_estimated_frame_offset = 0.0
	filtered_estimated_frame_offset = 0.0
	last_sync_rtt_frames = -1
	last_sync_sample_age_frames = -1
	soft_sync_active = false
	soft_sync_ahead_samples = 0
	soft_sync_yield_ticks = 0
	soft_sync_yield_cooldown = 0
	max_prediction_lead = 0
	lead_stalled = false
	lead_stall_ticks = 0
	redundant_frames_received = 0
	recovered_missing_frames = 0
	duplicate_input_frames = 0
	history_exhausted = false
	history_exhaustion_frame = -1
	input_mutation_error = false
	input_mutation_error_frame = -1
	repair_requests_sent = 0
	repair_requests_received = 0
	repair_responses_sent = 0
	repair_responses_received = 0
	last_repair_requested_frame = -1
	last_repair_recovered_frame = -1
	repair_unavailable_error = false
	repair_unavailable_count = 0
	_repair_tick = 0
	_pending_repair_frame = -1
	_next_repair_request_tick = 0
	_repair_unavailable_frame = -1
	_next_sync_sequence = 0
	_last_received_sync_sequence = -1
	_last_received_sync_receive_frame = -1
	_sync_sent_frames.clear()
	_sync_offset_samples.clear()
	_has_filtered_sync_sample = false

	local_checksum = 0
	remote_checksum = 0
	checksum_mismatch = false

	local_checksums.clear()
	remote_checksums.clear()
	remote_confirmed_through = maxi(input_delay_frames - 1, -1)
	local_checksum_confirmed_through = -1
	_confirmation_history_error_frame = -1
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


func get_prediction_lead() -> int:
	return maxi(
		current_frame - (last_remote_frame + 1),
		0
	)


func get_prediction_lead_limit() -> int:
	return MAX_PREDICTION_FRAMES


func get_local_frame_advantage() -> float:
	return -filtered_estimated_frame_offset


func get_confirmation_lag() -> int:
	return maxi(
		(current_frame - 1) - remote_confirmed_through,
		0
	)


func get_earliest_missing_remote_frame() -> int:
	var frame: int = remote_confirmed_through + 1

	if frame <= last_remote_frame and not remote_inputs.has(frame):
		return frame

	return -1


func get_oldest_retained_snapshot() -> int:
	var oldest: int = -1

	for frame_value: Variant in snapshots.keys():
		var frame: int = int(frame_value)
		if oldest < 0 or frame < oldest:
			oldest = frame

	return oldest


func _median(values: Array[float]) -> float:
	if values.is_empty():
		return 0.0

	var sorted_values: Array[float] = values.duplicate()
	sorted_values.sort()
	var middle: int = sorted_values.size() / 2

	if sorted_values.size() % 2 == 1:
		return sorted_values[middle]

	return (
		(sorted_values[middle - 1] + sorted_values[middle])
		* 0.5
	)


func _prune_sync_send_history(through_sequence: int) -> void:
	for sequence_value: Variant in _sync_sent_frames.keys():
		var sequence: int = int(sequence_value)
		if sequence <= through_sequence:
			_sync_sent_frames.erase(sequence)


func _update_finalized_through() -> void:
	var candidate: int = mini(
		remote_confirmed_through,
		mini(
			peer_confirmed_local_through,
			current_frame - 1
		)
	)
	finalized_through = maxi(finalized_through, candidate)


func _record_sync_sample(
	remote_sim_frame: int,
	echo_sequence: int,
	echo_receive_frame: int
) -> void:
	if not _sync_sent_frames.has(echo_sequence):
		return

	var local_send_frame: int = int(
		_sync_sent_frames[echo_sequence]
	)
	var local_receive_frame: int = current_frame
	var local_elapsed: int = local_receive_frame - local_send_frame
	var remote_hold: int = remote_sim_frame - echo_receive_frame

	last_sync_sample_age_frames = local_elapsed

	if local_elapsed < 0 or remote_hold < 0:
		return

	var rtt_frames: int = local_elapsed - remote_hold
	if rtt_frames < 0 or rtt_frames > SYNC_MAX_RTT_FRAMES:
		return

	var raw_offset: float = 0.5 * float(
		(echo_receive_frame - local_send_frame)
		+ (remote_sim_frame - local_receive_frame)
	)

	if absf(raw_offset) > SYNC_MAX_ABS_OFFSET_FRAMES:
		return

	if _sync_offset_samples.size() >= 5:
		var recent_median: float = _median(_sync_offset_samples)
		if absf(raw_offset - recent_median) > SYNC_MAX_MEDIAN_DEVIATION_FRAMES:
			return

	raw_estimated_frame_offset = raw_offset
	last_sync_rtt_frames = rtt_frames
	_sync_offset_samples.append(raw_offset)

	while _sync_offset_samples.size() > SYNC_SAMPLE_WINDOW:
		_sync_offset_samples.pop_front()

	var robust_offset: float = _median(_sync_offset_samples)
	if not _has_filtered_sync_sample:
		filtered_estimated_frame_offset = robust_offset
		_has_filtered_sync_sample = true
	else:
		filtered_estimated_frame_offset = lerpf(
			filtered_estimated_frame_offset,
			robust_offset,
			SYNC_EWMA_ALPHA
		)

	_update_soft_sync_state()
	_prune_sync_send_history(echo_sequence)


func _update_soft_sync_state() -> void:
	var local_advantage: float = get_local_frame_advantage()

	if soft_sync_active and local_advantage < SOFT_SYNC_EXIT_ADVANTAGE:
		soft_sync_active = false
		soft_sync_ahead_samples = 0
		return

	if local_advantage >= SOFT_SYNC_ENTER_ADVANTAGE:
		soft_sync_ahead_samples += 1
	else:
		soft_sync_ahead_samples = 0

	if (
		not soft_sync_active
		and soft_sync_ahead_samples >= SOFT_SYNC_REQUIRED_SAMPLES
	):
		soft_sync_active = true


func _advance_soft_sync_cooldown() -> void:
	if soft_sync_yield_cooldown > 0:
		soft_sync_yield_cooldown -= 1


func _should_soft_sync_yield() -> bool:
	return (
		soft_sync_active
		and soft_sync_ahead_samples >= SOFT_SYNC_REQUIRED_SAMPLES
		and soft_sync_yield_cooldown <= 0
	)


func _handle_sync_telemetry(packet: Dictionary) -> void:
	var sim_frame_value: Variant = packet.get("sim_frame", null)
	var sync_sequence_value: Variant = packet.get("sync_sequence", null)
	var echo_sequence_value: Variant = packet.get("echo_sync_sequence", null)
	var echo_receive_value: Variant = packet.get("echo_receive_frame", null)
	var confirmed_value: Variant = packet.get(
		"confirmed_remote_through",
		null
	)

	if (
		typeof(sim_frame_value) != TYPE_INT
		or typeof(sync_sequence_value) != TYPE_INT
		or typeof(echo_sequence_value) != TYPE_INT
		or typeof(echo_receive_value) != TYPE_INT
		or typeof(confirmed_value) != TYPE_INT
	):
		return

	var remote_sim_frame: int = int(sim_frame_value)
	var sync_sequence: int = int(sync_sequence_value)
	var echo_sequence: int = int(echo_sequence_value)
	var echo_receive_frame: int = int(echo_receive_value)
	var peer_confirmed: int = int(confirmed_value)

	if remote_sim_frame < 0 or sync_sequence < 0:
		return

	last_remote_sim_frame = maxi(
		last_remote_sim_frame,
		remote_sim_frame
	)

	if peer_confirmed >= -1:
		peer_confirmed_local_through = maxi(
			peer_confirmed_local_through,
			peer_confirmed
		)
		_update_finalized_through()

	if sync_sequence > _last_received_sync_sequence:
		_last_received_sync_sequence = sync_sequence
		_last_received_sync_receive_frame = current_frame

	if echo_sequence >= 0 and echo_receive_frame >= 0:
		_record_sync_sample(
			remote_sim_frame,
			echo_sequence,
			echo_receive_frame
		)


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


func _build_input_history(input_frame: int) -> Array[Dictionary]:
	var history: Array[Dictionary] = []

	for offset: int in range(1, INPUT_REDUNDANCY_FRAMES + 1):
		var history_frame: int = input_frame - offset

		if history_frame < 0:
			continue

		if not local_inputs.has(history_frame):
			continue

		history.append({
			"frame": history_frame,
			"input": local_inputs[history_frame].duplicate(true),
		})

	return history


func _erase_history_frame(frame: int) -> void:
	if snapshots.has(frame):
		snapshots.erase(frame)

	if local_inputs.has(frame):
		local_inputs.erase(frame)

	if remote_inputs.has(frame):
		remote_inputs.erase(frame)

	if predicted_remote_inputs.has(frame):
		predicted_remote_inputs.erase(frame)

	if local_checksums.has(frame):
		local_checksums.erase(frame)

	if remote_checksums.has(frame):
		remote_checksums.erase(frame)

	# Keep checksum_comparison_results for the whole
	# benchmark so final stats stay intact.


func _enter_history_exhaustion(frame: int) -> void:
	if history_exhausted:
		return

	history_exhausted = true
	history_exhaustion_frame = frame
	push_error(
		"[Rollback] HISTORY EXHAUSTED frame=%d current_frame=%d remote_confirmed_through=%d last_remote_frame=%d max_history=%d"
		% [
			frame,
			current_frame,
			remote_confirmed_through,
			last_remote_frame,
			MAX_ROLLBACK_FRAMES,
		]
	)


func _clear_resolved_repair_request() -> void:
	if _pending_repair_frame < 0:
		return

	if _pending_repair_frame <= remote_confirmed_through:
		_pending_repair_frame = -1
		_next_repair_request_tick = 0
		_repair_unavailable_frame = -1


func _maybe_request_missing_remote_input() -> void:
	_clear_resolved_repair_request()

	var missing_frame: int = get_earliest_missing_remote_frame()
	if missing_frame < 0:
		return

	if last_remote_frame - missing_frame < INPUT_REDUNDANCY_FRAMES:
		return

	var missing_age: int = current_frame - missing_frame
	if missing_age >= REPAIR_REQUEST_MAX_AGE:
		return

	if _repair_unavailable_frame == missing_frame:
		return

	if _pending_repair_frame != missing_frame:
		_pending_repair_frame = missing_frame
		_next_repair_request_tick = 0

	if _repair_tick < _next_repair_request_tick:
		return

	if transport == null:
		return

	if not transport.has_method("send_input_repair_request"):
		return

	transport.send_input_repair_request(missing_frame, player_id)
	repair_requests_sent += 1
	last_repair_requested_frame = missing_frame
	_next_repair_request_tick = _repair_tick + REPAIR_REQUEST_RETRY_TICKS


func _cleanup_old_history() -> bool:
	var old_frame: int = current_frame - MAX_ROLLBACK_FRAMES

	if old_frame < 0:
		return true

	if old_frame > remote_confirmed_through:
		_enter_history_exhaustion(old_frame)
		return false

	_erase_history_frame(old_frame)
	return true


# =================================================
# Checksum helpers
# =================================================

func _compute_checksum(snapshot: Dictionary) -> int:
	if adapter == null:
		return 0

	if not adapter.has_method("canonical_checksum"):
		return 0

	return int(adapter.canonical_checksum(snapshot))


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


func _record_local_checksum(frame: int) -> void:
	var snapshot: Dictionary = adapter.capture()
	local_checksum = _compute_checksum(snapshot)

	local_checksums[frame] = local_checksum


func _advance_remote_confirmed_through() -> void:
	var next_frame: int = remote_confirmed_through + 1

	while remote_inputs.has(next_frame):
		remote_confirmed_through = next_frame
		next_frame += 1

	_update_finalized_through()


func _send_newly_confirmed_checksums() -> void:
	var confirmed_limit: int = mini(
		remote_confirmed_through,
		current_frame - 1
	)

	while local_checksum_confirmed_through < confirmed_limit:
		var frame: int = local_checksum_confirmed_through + 1

		if not local_checksums.has(frame):
			_report_confirmation_history_error(frame)
			return

		local_checksum_confirmed_through = frame
		_send_checksum_packet(frame, int(local_checksums[frame]))
		_try_compare_checksum(frame)


func _report_confirmation_history_error(frame: int) -> void:
	if _confirmation_history_error_frame >= 0:
		return

	_confirmation_history_error_frame = frame
	push_error(
		"[Checksum] CONFIRMATION OUTSIDE HISTORY frame=%d current_frame=%d max_history=%d"
		% [frame, current_frame, MAX_ROLLBACK_FRAMES]
	)


func _try_compare_checksum(
	frame: int,
	state_is_current: bool = false,
	current_snapshot: Dictionary = {}
) -> void:
	if not local_checksums.has(frame):
		return

	if not remote_checksums.has(frame):
		return

	# Local checksums become comparable only after every
	# remote input through this frame has been confirmed.
	if frame > local_checksum_confirmed_through:
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
	remote_checksum = checksum
	remote_checksums[frame] = checksum

	# This may do nothing until the local frame is confirmed.
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

	_repair_tick += 1
	_maybe_request_missing_remote_input()

	var input_frame: int = (
		current_frame
		+ max(0, input_delay_frames)
	)

	if not local_inputs.has(input_frame):
		local_inputs[input_frame] = local_input.duplicate(true)

	var latched_local_input: Dictionary = (
		local_inputs[input_frame]
	)

	# =================================================
	# Send local input
	# =================================================

	if transport and transport.has_method("send_packet"):
		var sync_sequence: int = _next_sync_sequence
		_next_sync_sequence += 1
		_sync_sent_frames[sync_sequence] = current_frame
		_prune_sync_send_history(_next_sync_sequence - 257)

		transport.send_packet({
			"type": "input",
			"frame": input_frame,
			"player_id": player_id,
			"input": latched_local_input.duplicate(true),
			"history": _build_input_history(input_frame),
			"sim_frame": current_frame,
			"sync_sequence": sync_sequence,
			"echo_sync_sequence": _last_received_sync_sequence,
			"echo_receive_frame": _last_received_sync_receive_frame,
			"confirmed_remote_through": remote_confirmed_through,
		})

	var prediction_lead: int = get_prediction_lead()
	max_prediction_lead = maxi(
		max_prediction_lead,
		prediction_lead
	)

	lead_stalled = (
		prediction_lead >= MAX_PREDICTION_FRAMES
	)

	if history_exhausted:
		return

	if lead_stalled:
		lead_stall_ticks += 1
		return

	_advance_soft_sync_cooldown()

	if _should_soft_sync_yield():
		soft_sync_yield_ticks += 1
		soft_sync_yield_cooldown = SOFT_SYNC_YIELD_INTERVAL
		soft_sync_ahead_samples = 0
		return

	if not _cleanup_old_history():
		return

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
	# Simulate current frame
	# =================================================

	_simulate_frame(
		delayed_local_input,
		remote_input
	)

	# Checksum represents state AFTER this frame.
	_record_local_checksum(current_frame)

	current_frame += 1
	_update_finalized_through()
	_send_newly_confirmed_checksums()


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

func _is_valid_input_data(input_data: Dictionary) -> bool:
	if not input_data.has("mx"):
		return false

	var mx_type: int = typeof(input_data["mx"])
	if mx_type != TYPE_FLOAT and mx_type != TYPE_INT:
		return false

	for field: String in [
		"lean_l",
		"lean_r",
		"atk_l",
		"atk_h",
		"block",
		"dodge",
	]:
		if not input_data.has(field):
			return false

		if typeof(input_data[field]) != TYPE_BOOL:
			return false

	return true


func _inputs_equal(
	a: Dictionary,
	b: Dictionary
) -> bool:
	return (
		float(a.get("mx", 0.0)) == float(b.get("mx", 0.0))
		and bool(a.get("lean_l", false)) == bool(b.get("lean_l", false))
		and bool(a.get("lean_r", false)) == bool(b.get("lean_r", false))
		and bool(a.get("atk_l", false)) == bool(b.get("atk_l", false))
		and bool(a.get("atk_h", false)) == bool(b.get("atk_h", false))
		and bool(a.get("block", false)) == bool(b.get("block", false))
		and bool(a.get("dodge", false)) == bool(b.get("dodge", false))
	)


func _append_valid_input_record(
	records: Array[Dictionary],
	frame_value: Variant,
	input_value: Variant,
	is_redundant: bool
) -> void:
	if typeof(frame_value) != TYPE_INT:
		push_error("[Rollback] Invalid input frame type in packet.")
		return

	var frame: int = int(frame_value)
	if frame < 0:
		push_error("[Rollback] Invalid negative input frame in packet.")
		return

	if not input_value is Dictionary:
		push_error("[Rollback] Invalid input payload type for frame %d." % frame)
		return

	var input_data: Dictionary = input_value
	if not _is_valid_input_data(input_data):
		push_error("[Rollback] Invalid input payload for frame %d." % frame)
		return

	records.append({
		"frame": frame,
		"input": input_data.duplicate(true),
		"redundant": is_redundant,
	})


func _input_record_less(
	a: Dictionary,
	b: Dictionary
) -> bool:
	return int(a.get("frame", -1)) < int(b.get("frame", -1))


func _report_input_mutation(frame: int) -> void:
	if input_mutation_error:
		return

	input_mutation_error = true
	input_mutation_error_frame = frame

	push_error(
		"[Rollback] INPUT MUTATION player=%d frame=%d"
		% [3 - player_id, frame]
	)


func _merge_remote_input_records(records: Array[Dictionary]) -> void:
	if records.is_empty():
		return

	records.sort_custom(_input_record_less)

	var newest_valid_frame: int = -1
	var newly_inserted: Array[Dictionary] = []

	for record: Dictionary in records:
		var frame: int = int(record.get("frame", -1))
		var input_data: Dictionary = record.get("input", {})
		var is_redundant: bool = bool(
			record.get("redundant", false)
		)

		newest_valid_frame = maxi(newest_valid_frame, frame)

		if is_redundant:
			redundant_frames_received += 1

		if remote_inputs.has(frame):
			var existing_input: Dictionary = remote_inputs[frame]

			if _inputs_equal(existing_input, input_data):
				duplicate_input_frames += 1
			else:
				_report_input_mutation(frame)

			continue

		if frame <= remote_confirmed_through:
			duplicate_input_frames += 1
			continue

		remote_inputs[frame] = input_data.duplicate(true)
		newly_inserted.append({
			"frame": frame,
			"input": input_data.duplicate(true),
		})

		if is_redundant:
			recovered_missing_frames += 1

	last_remote_frame = maxi(
		last_remote_frame,
		newest_valid_frame
	)
	last_remote_input_frame = maxi(
		last_remote_input_frame,
		newest_valid_frame
	)

	_advance_remote_confirmed_through()
	_clear_resolved_repair_request()

	var earliest_mismatch: int = -1

	for record: Dictionary in newly_inserted:
		var frame: int = int(record.get("frame", -1))

		if frame >= current_frame:
			continue

		if not predicted_remote_inputs.has(frame):
			continue

		var predicted: Dictionary = predicted_remote_inputs[frame]
		var input_data: Dictionary = record.get("input", {})

		if not _inputs_equal(predicted, input_data):
			prediction_misses += 1

			if earliest_mismatch < 0 or frame < earliest_mismatch:
				earliest_mismatch = frame

	if earliest_mismatch >= 0:
		if not snapshots.has(earliest_mismatch):
			_enter_history_exhaustion(earliest_mismatch)
			return

		_rollback_and_replay(earliest_mismatch)

	_send_newly_confirmed_checksums()


func _on_input_repair_request_received(
	frame: int,
	requester_player_id: int
) -> void:
	if requester_player_id == player_id:
		return

	repair_requests_received += 1

	if frame < 0:
		push_error("[Rollback] Invalid negative repair request frame.")
		return

	if transport == null or not transport.has_method(
		"send_input_repair_response"
	):
		return

	if not local_inputs.has(frame):
		repair_unavailable_error = true
		repair_unavailable_count += 1
		push_error(
			"[Rollback] REPAIR UNAVAILABLE frame=%d current_frame=%d max_history=%d"
			% [frame, current_frame, MAX_ROLLBACK_FRAMES]
		)
		transport.send_input_repair_response(
			frame,
			player_id,
			{},
			false
		)
		repair_responses_sent += 1
		return

	transport.send_input_repair_response(
		frame,
		player_id,
		local_inputs[frame].duplicate(true),
		true
	)
	repair_responses_sent += 1


func _on_input_repair_response_received(
	frame: int,
	responder_player_id: int,
	input_data: Dictionary,
	available: bool
) -> void:
	if responder_player_id == player_id:
		return

	repair_responses_received += 1

	if frame < 0:
		push_error("[Rollback] Invalid negative repair response frame.")
		return

	if not available:
		repair_unavailable_error = true
		repair_unavailable_count += 1
		_repair_unavailable_frame = frame
		push_error(
			"[Rollback] REMOTE REPAIR UNAVAILABLE frame=%d current_frame=%d"
			% [frame, current_frame]
		)
		return

	var records: Array[Dictionary] = []
	_append_valid_input_record(records, frame, input_data, false)

	if records.is_empty():
		return

	_merge_remote_input_records(records)

	if remote_inputs.has(frame):
		var merged_input: Dictionary = remote_inputs[frame]
		if _inputs_equal(merged_input, input_data):
			last_repair_recovered_frame = frame


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

	_handle_sync_telemetry(packet)

	var records: Array[Dictionary] = []
	_append_valid_input_record(
		records,
		packet.get("frame", null),
		packet.get("input", null),
		false
	)

	var history_value: Variant = packet.get("history", [])
	if history_value is Array:
		for history_record_value: Variant in history_value:
			if not history_record_value is Dictionary:
				push_error("[Rollback] Invalid input history record type.")
				continue

			var history_record: Dictionary = history_record_value
			_append_valid_input_record(
				records,
				history_record.get("frame", null),
				history_record.get("input", null),
				true
			)
	else:
		push_error("[Rollback] Invalid input history array.")

	if records.is_empty():
		return

	packets_received += 1
	_merge_remote_input_records(records)


# =================================================
# Rollback + replay
# =================================================

func _rollback_and_replay(from_frame: int) -> void:
	if adapter == null:
		return

	if not snapshots.has(from_frame):
		_enter_history_exhaustion(from_frame)
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

		# Refresh the retained candidate because this historical
		# frame may now contain corrected state. Sending is deferred
		# until the frame is confirmed.
		_record_local_checksum(replay_frame)

		replay_frame += 1

	current_frame = original_current_frame
