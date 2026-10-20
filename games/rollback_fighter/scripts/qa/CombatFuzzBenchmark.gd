class_name CombatFuzzBenchmark
extends RefCounted

# Stable random channels. Existing numeric IDs must never be renumbered.
const CHANNEL_IDLE_ENABLE := 1
const CHANNEL_IDLE_START := 2
const CHANNEL_IDLE_DURATION := 3
const CHANNEL_MOVE_DURATION_CLASS := 4
const CHANNEL_MOVE_DURATION := 5
const CHANNEL_MOVE_DIRECTION := 6
const CHANNEL_MOVE_STYLE := 7
const CHANNEL_MOVE_NEUTRAL := 8
const CHANNEL_ACTION_OFFSET := 9
const CHANNEL_ACTION_CHOICE := 10
const CHANNEL_BLOCK_ENABLE := 11
const CHANNEL_BLOCK_START := 12
const CHANNEL_BLOCK_DURATION := 13
const CHANNEL_COUNTER_CHOICE := 14
const CHANNEL_RESUME_CHOICE := 15
const CHANNEL_REVERSAL_CHOICE := 16

const MASK_32 := 0xffffffff
const NONZERO_FALLBACK := 0x6d2b79f5
const PHASE_FRAMES := 1200
const SCHEDULE_FRAMES := 7200


static func random_for(
	seed: int,
	frame: int,
	player_id: int,
	channel: int
) -> int:
	var value: int = int(seed) & MASK_32
	value ^= (maxi(frame, 0) * 0x9e3779b9) & MASK_32
	value ^= (player_id * 0x85ebca6b) & MASK_32
	value ^= (channel * 0xc2b2ae35) & MASK_32
	value &= MASK_32

	if value == 0:
		value = NONZERO_FALLBACK

	value ^= (value << 13) & MASK_32
	value &= MASK_32
	value ^= value >> 17
	value &= MASK_32
	value ^= (value << 5) & MASK_32
	return value & MASK_32


static func phase_for_frame(frame: int) -> int:
	if frame < 0 or frame >= SCHEDULE_FRAMES:
		return 0
	return int(frame / PHASE_FRAMES) + 1


static func phase_name(phase: int) -> String:
	match phase:
		1:
			return "MOVEMENT_REVERSAL"
		2:
			return "LIGHT_EMPHASIS"
		3:
			return "HEAVY_BLOCK"
		4:
			return "DODGE_COUNTER"
		5:
			return "MIXED_CHAOS"
		6:
			return "HIGH_INTENSITY_IDLE_RESUME"
		_:
			return "DRAIN_OR_OUT_OF_RANGE"


static func neutral_input() -> Dictionary:
	return {
		"mx": 0.0,
		"lean_l": false,
		"lean_r": false,
		"atk_l": false,
		"atk_h": false,
		"block": false,
		"dodge": false,
	}


static func _cell_random(
	seed: int,
	cell: int,
	player_id: int,
	channel: int
) -> int:
	return random_for(seed, cell, player_id, channel)


static func _is_idle_frame(seed: int, frame: int, player_id: int) -> bool:
	if frame < 0 or frame >= SCHEDULE_FRAMES:
		return false

	var phase: int = phase_for_frame(frame)
	var cell_size: int = 240
	var cell: int = int(frame / cell_size)
	var local_frame: int = frame % cell_size
	var enable_roll: int = _cell_random(
		seed,
		cell,
		player_id,
		CHANNEL_IDLE_ENABLE
	) % 100
	var enable_threshold: int = 5
	if phase == 5:
		enable_threshold = 10
	elif phase == 6:
		enable_threshold = 35

	if enable_roll >= enable_threshold:
		return false

	var idle_start: int = 20 + int(
		_cell_random(seed, cell, player_id, CHANNEL_IDLE_START) % 80
	)
	var idle_duration: int = 30 + int(
		_cell_random(seed, cell, player_id, CHANNEL_IDLE_DURATION) % 91
	)
	return local_frame >= idle_start and local_frame < idle_start + idle_duration


static func _movement_duration(seed: int, frame: int, player_id: int) -> int:
	var macro_cell: int = int(frame / 120)
	var duration_class: int = int(
		_cell_random(
			seed,
			macro_cell,
			player_id,
			CHANNEL_MOVE_DURATION_CLASS
		) % 100
	)
	var duration_roll: int = _cell_random(
		seed,
		macro_cell,
		player_id,
		CHANNEL_MOVE_DURATION
	)

	if duration_class < 45:
		return 2 + int(duration_roll % 4)
	if duration_class < 80:
		return 6 + int(duration_roll % 15)
	return 21 + int(duration_roll % 40)


static func _movement_axis(seed: int, frame: int, player_id: int) -> float:
	if frame < 0 or frame >= SCHEDULE_FRAMES:
		return 0.0
	if _is_idle_frame(seed, frame, player_id):
		return 0.0

	var phase: int = phase_for_frame(frame)
	var macro_cell: int = int(frame / 120)
	var local_frame: int = frame % 120
	var duration: int = _movement_duration(seed, frame, player_id)
	var segment: int = int(local_frame / duration)
	var segment_key: int = macro_cell * 64 + segment
	var neutral_roll: int = int(
		_cell_random(
			seed,
			segment_key,
			player_id,
			CHANNEL_MOVE_NEUTRAL
		) % 100
	)
	var neutral_threshold: int = 20
	if phase == 1:
		neutral_threshold = 8
	elif phase == 6:
		neutral_threshold = 12

	if neutral_roll < neutral_threshold:
		return 0.0

	var toward: float = 1.0 if player_id == 1 else -1.0
	var style: int = int(
		_cell_random(seed, macro_cell, player_id, CHANNEL_MOVE_STYLE) % 100
	)
	var direction_roll: int = int(
		_cell_random(
			seed,
			segment_key,
			player_id,
			CHANNEL_MOVE_DIRECTION
		) % 100
	)

	if phase == 1 and style < 70:
		return toward if segment % 2 == 0 else -toward
	if style < 35:
		return toward
	if style < 50:
		return -toward
	return -1.0 if direction_roll < 50 else 1.0


static func _block_window_active(
	seed: int,
	frame: int,
	player_id: int,
	phase: int
) -> bool:
	var cell_size: int = 48
	var cell: int = int(frame / cell_size)
	var local_frame: int = frame % cell_size
	var threshold: int = 8
	match phase:
		3:
			threshold = 55
		4:
			threshold = 25
		5:
			threshold = 30
		6:
			threshold = 35

	if int(_cell_random(seed, cell, player_id, CHANNEL_BLOCK_ENABLE) % 100) >= threshold:
		return false

	var block_start: int = 3 + int(
		_cell_random(seed, cell, player_id, CHANNEL_BLOCK_START) % 18
	)
	var block_duration: int = 4 + int(
		_cell_random(seed, cell, player_id, CHANNEL_BLOCK_DURATION) % 13
	)
	return local_frame >= block_start and local_frame < block_start + block_duration


static func _just_released_block(
	seed: int,
	frame: int,
	player_id: int,
	phase: int
) -> bool:
	return (
		frame > 0
		and not _block_window_active(seed, frame, player_id, phase)
		and _block_window_active(seed, frame - 1, player_id, phase_for_frame(frame - 1))
	)


static func _action_slot_size(phase: int) -> int:
	match phase:
		1:
			return 54
		2:
			return 24
		3:
			return 30
		4:
			return 26
		5:
			return 22
		6:
			return 18
		_:
			return 60


static func _action_for_roll(phase: int, roll: int) -> int:
	# 0 none, 1 light, 2 heavy, 3 dodge.
	match phase:
		1:
			if roll < 18:
				return 1
			if roll < 25:
				return 2
			if roll < 31:
				return 3
		2:
			if roll < 62:
				return 1
			if roll < 72:
				return 2
			if roll < 82:
				return 3
		3:
			if roll < 18:
				return 1
			if roll < 58:
				return 2
			if roll < 68:
				return 3
		4:
			if roll < 30:
				return 1
			if roll < 43:
				return 2
			if roll < 78:
				return 3
		5:
			if roll < 34:
				return 1
			if roll < 58:
				return 2
			if roll < 80:
				return 3
		6:
			if roll < 38:
				return 1
			if roll < 66:
				return 2
			if roll < 88:
				return 3

	return 0


static func _action_for_frame(seed: int, frame: int, player_id: int, phase: int) -> int:
	var slot_size: int = _action_slot_size(phase)
	var slot: int = int(frame / slot_size)
	var local_frame: int = frame % slot_size
	var action_offset: int = int(
		_cell_random(seed, slot, player_id, CHANNEL_ACTION_OFFSET) % slot_size
	)
	var action: int = 0

	if local_frame == action_offset:
		var action_roll: int = int(
			_cell_random(seed, slot, player_id, CHANNEL_ACTION_CHOICE) % 100
		)
		action = _action_for_roll(phase, action_roll)

	if _just_released_block(seed, frame, player_id, phase):
		var counter_roll: int = int(
			random_for(seed, frame, player_id, CHANNEL_COUNTER_CHOICE) % 100
		)
		if counter_roll < 55:
			action = 1
		elif counter_roll < 85:
			action = 2

	if frame > 0 and not _is_idle_frame(seed, frame, player_id):
		if _is_idle_frame(seed, frame - 1, player_id):
			var resume_roll: int = int(
				random_for(seed, frame, player_id, CHANNEL_RESUME_CHOICE) % 100
			)
			if resume_roll < 45:
				action = 1
			elif resume_roll < 70:
				action = 2

	var current_axis: float = _movement_axis(seed, frame, player_id)
	var previous_axis: float = _movement_axis(seed, frame - 1, player_id)
	if current_axis != 0.0 and previous_axis != 0.0 and current_axis != previous_axis:
		var reversal_roll: int = int(
			random_for(seed, frame, player_id, CHANNEL_REVERSAL_CHOICE) % 100
		)
		if reversal_roll < 18:
			action = 1
		elif reversal_roll < 26:
			action = 2

	return action


static func input_for_frame(seed: int, frame: int, player_id: int) -> Dictionary:
	if frame < 0 or frame >= SCHEDULE_FRAMES:
		return neutral_input()

	if player_id != 1 and player_id != 2:
		return neutral_input()

	if _is_idle_frame(seed, frame, player_id):
		return neutral_input()

	var phase: int = phase_for_frame(frame)
	var result: Dictionary = neutral_input()
	result["mx"] = _movement_axis(seed, frame, player_id)

	var action: int = _action_for_frame(seed, frame, player_id, phase)
	var block_active: bool = _block_window_active(
		seed,
		frame,
		player_id,
		phase
	)

	# Mutually exclusive action priority: dodge > block > heavy > light.
	if action == 3:
		result["dodge"] = true
	elif block_active:
		result["block"] = true
	elif action == 2:
		result["atk_h"] = true
	elif action == 1:
		result["atk_l"] = true

	return result


static func generated_coverage(seed: int, player_id: int) -> Dictionary:
	var coverage: Dictionary = {
		"MoveLeftFrames": 0,
		"MoveRightFrames": 0,
		"NeutralFrames": 0,
		"LightAttempts": 0,
		"HeavyAttempts": 0,
		"BlockFrames": 0,
		"DodgeAttempts": 0,
		"ReversalCount": 0,
	}
	var previous_axis: float = 0.0

	for frame: int in range(SCHEDULE_FRAMES):
		var input_data: Dictionary = input_for_frame(seed, frame, player_id)
		var axis: float = float(input_data.get("mx", 0.0))

		if axis < 0.0:
			coverage["MoveLeftFrames"] += 1
		elif axis > 0.0:
			coverage["MoveRightFrames"] += 1
		else:
			coverage["NeutralFrames"] += 1

		if previous_axis != 0.0 and axis != 0.0 and previous_axis != axis:
			coverage["ReversalCount"] += 1
		if bool(input_data.get("atk_l", false)):
			coverage["LightAttempts"] += 1
		if bool(input_data.get("atk_h", false)):
			coverage["HeavyAttempts"] += 1
		if bool(input_data.get("block", false)):
			coverage["BlockFrames"] += 1
		if bool(input_data.get("dodge", false)):
			coverage["DodgeAttempts"] += 1

		previous_axis = axis

	return coverage


static func print_results(
	seed: int,
	diagnostics: Dictionary,
	snapshot: Dictionary,
	canonical_checksum: int,
	benchmark_start_frame: int,
	stop_after_frame: int,
	drain_frames: int
) -> void:
	_print_coverage("P1", generated_coverage(seed, 1))
	_print_coverage("P2", generated_coverage(seed, 2))

	var combat: Dictionary = snapshot.get("combat", {})
	_print_fighter_fingerprint("P1", snapshot.get("p1", {}), combat, 1)
	_print_fighter_fingerprint("P2", snapshot.get("p2", {}), combat, 2)
	print("CombatFuzzHitstop: %d" % int(combat.get("hitstop", 0)))
	print("CombatFuzzFinalCanonicalChecksum: %d" % canonical_checksum)

	_print_failure_context(
		"ChecksumMismatch",
		int(diagnostics["first_checksum_mismatch_frame"]),
		seed,
		benchmark_start_frame
	)
	_print_failure_context(
		"StateDivergence",
		int(diagnostics["first_state_divergence_frame"]),
		seed,
		benchmark_start_frame
	)

	if stop_after_frame >= 0:
		var stop_frame: int = clampi(
			stop_after_frame,
			0,
			SCHEDULE_FRAMES + drain_frames - 1
		)
		print("CombatFuzzStopped: true")
		print("CombatFuzzStopSeed: %d" % seed)
		print("CombatFuzzStopFrame: %d" % stop_frame)
		print("CombatFuzzStopP1Input: %s" % str(
			input_for_frame(seed, stop_frame, 1)
		))
		print("CombatFuzzStopP2Input: %s" % str(
			input_for_frame(seed, stop_frame, 2)
		))

	_print_verdict(
		diagnostics,
		benchmark_start_frame,
		stop_after_frame,
		drain_frames
	)


static func _print_coverage(label: String, coverage: Dictionary) -> void:
	for key: String in [
		"MoveLeftFrames",
		"MoveRightFrames",
		"NeutralFrames",
		"LightAttempts",
		"HeavyAttempts",
		"BlockFrames",
		"DodgeAttempts",
		"ReversalCount",
	]:
		print("CombatFuzz%s%s: %d" % [label, key, int(coverage[key])])


static func _print_fighter_fingerprint(
	label: String,
	fighter: Dictionary,
	combat: Dictionary,
	player_id: int
) -> void:
	print((
		"CombatFuzz%sCanonical: "
		+ "Position=(%s,%s) Velocity=(%s,%s) GroundVelocity=%s "
		+ "Facing=%d HP=%d State=%d StateFrames=%d "
		+ "AttackKind=%d AttackID=%d AttackActive=%s HitConfirmed=%s "
		+ "Blocking=%s Invulnerable=%s DodgeRequested=%s HurtFrames=%d "
		+ "LightCooldown=%d HeavyCooldown=%d"
	) % [
		label,
		str(fighter.get("x", 0.0)),
		str(fighter.get("y", 0.0)),
		str(fighter.get("vx", 0.0)),
		str(fighter.get("vy", 0.0)),
		str(fighter.get("gvx", 0.0)),
		int(fighter.get("fa", 0)),
		int(fighter.get("hp", 0)),
		int(fighter.get("st", 0)),
		int(fighter.get("stf", 0)),
		int(fighter.get("ak", 0)),
		int(fighter.get("aid", 0)),
		str(fighter.get("aa", false)),
		str(fighter.get("hc", false)),
		str(fighter.get("blk", false)),
		str(fighter.get("inv", false)),
		str(fighter.get("dreq", false)),
		int(fighter.get("hurt", 0)),
		int(combat.get("light_cd_%d" % player_id, 0)),
		int(combat.get("heavy_cd_%d" % player_id, 0)),
	])


static func _print_failure_context(
	label: String,
	session_frame: int,
	seed: int,
	benchmark_start_frame: int
) -> void:
	if session_frame < 0:
		return

	var benchmark_frame: int = session_frame - benchmark_start_frame
	var phase: int = phase_for_frame(benchmark_frame)
	print("CombatFuzz%sSeed: %d" % [label, seed])
	print("CombatFuzz%sSessionFrame: %d" % [label, session_frame])
	print("CombatFuzz%sFrame: %d" % [label, benchmark_frame])
	print("CombatFuzz%sPhase: %d %s" % [label, phase, phase_name(phase)])
	print("CombatFuzz%sP1Input: %s" % [
		label,
		str(input_for_frame(seed, benchmark_frame, 1)),
	])
	print("CombatFuzz%sP2Input: %s" % [
		label,
		str(input_for_frame(seed, benchmark_frame, 2)),
	])


static func _print_verdict(
	diagnostics: Dictionary,
	benchmark_start_frame: int,
	stop_after_frame: int,
	drain_frames: int
) -> void:
	var failures: Array[String] = []
	var required_confirmed_frame: int = benchmark_start_frame + SCHEDULE_FRAMES - 1
	var elapsed_frames: int = (
		int(diagnostics["current_frame"]) - benchmark_start_frame
	)

	if elapsed_frames < SCHEDULE_FRAMES + drain_frames:
		failures.append("benchmark did not complete the full schedule and drain")
	if stop_after_frame >= 0:
		failures.append("stop-after-frame reproduction mode was enabled")
	if int(diagnostics["checksum_mismatch_count"]) != 0:
		failures.append("checksum mismatches were recorded")
	if int(diagnostics["first_checksum_mismatch_frame"]) != -1:
		failures.append("a first checksum mismatch frame was recorded")
	if int(diagnostics["first_state_divergence_frame"]) != -1:
		failures.append("a first state divergence frame was recorded")
	if bool(diagnostics["history_exhausted"]):
		failures.append("rollback history was exhausted")
	if bool(diagnostics["input_mutation_error"]):
		failures.append("INPUT MUTATION was reported")
	if bool(diagnostics["repair_unavailable_error"]):
		failures.append("REPAIR UNAVAILABLE was reported")
	if int(diagnostics["max_prediction_lead"]) > int(
		diagnostics["prediction_lead_limit"]
	):
		failures.append("prediction lead exceeded its configured limit")
	if int(diagnostics["remote_confirmed_through"]) < required_confirmed_frame:
		failures.append("combat-fuzz schedule inputs were not fully confirmed")
	if int(diagnostics["local_checksum_confirmed_through"]) < required_confirmed_frame:
		failures.append("combat-fuzz schedule checksums were not fully confirmed")
	if int(diagnostics["finalized_through"]) < required_confirmed_frame:
		failures.append("combat-fuzz schedule did not reach the finalized frontier")

	print("CombatFuzzVerdict: %s" % ("PASS" if failures.is_empty() else "FAIL"))
	print("CombatFuzzFailureCount: %d" % failures.size())
	for failure: String in failures:
		print("CombatFuzzFailure: %s" % failure)
