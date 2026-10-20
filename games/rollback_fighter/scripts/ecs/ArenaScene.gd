extends Node2D

# ArenaScene.gd — ENet rollback fighter arena + deterministic QA bot benchmark

# -------------------------------------------------
# Machine config
# DESKTOP:
#   ENET_HOST := true
#   ENET_IP := "xxx.x.x.x"
#
# LAPTOP:
#   ENET_HOST := false
#   ENET_IP := "DESKTOP_IPV4_HERE"
# -------------------------------------------------


const USE_ENET := true #check #back to laptop
const ENET_HOST := true #check 
const ENET_IP := "127.0.0.1" #check
const ENET_PORT := 7777

# -------------------------------------------------
# Benchmark config
# false = normal manual play
# true  = controlled deterministic QA bot benchmark
# -------------------------------------------------
const QA_BOT_BENCHMARK_ENABLED := false
const BENCHMARK_DURATION_FRAMES := 3600 # 60 seconds at 60fps

# Separate stress benchmark. Keep QA_BOT_BENCHMARK_ENABLED false when enabled.
# Natural stress: QA_STRESS_BENCHMARK_ENABLED=true, FORCE_LOSS=false.
# Loss stress:    QA_STRESS_BENCHMARK_ENABLED=true, FORCE_LOSS=true.
const QA_STRESS_BENCHMARK_ENABLED := false
const QA_STRESS_FORCE_PACKET_LOSS := false
const STRESS_SCHEDULE_FRAMES := 7200
const STRESS_DRAIN_FRAMES := 120
const STRESS_TOTAL_FRAMES := STRESS_SCHEDULE_FRAMES + STRESS_DRAIN_FRAMES
const STRESS_CYCLE_FRAMES := 1200

# Set these on BOTH computers before each test:
# 0  = baseline LAN
# 6  = ~100ms
# 9  = ~150ms
# 12 = ~200ms
const BENCHMARK_DELAY_FRAMES := 0
const BENCHMARK_JITTER_FRAMES := 0
const BENCHMARK_INPUT_DELAY_FRAMES := 0 #for tuning test 3, 4, 6

@onready var player_state := PlayerState.new()
@onready var opponent_state := PlayerState.new()
@onready var input_system := InputSystem.new()
@onready var lean_system := LeanSystem.new()
@onready var combat_system := CombatSystem.new()

@onready var adapter: FighterRollbackAdapter = preload(
	"res://games/rollback_fighter/scripts/net/FighterRollbackAdapter.gd"
).new()

const LatencyHarnessTransportScene = preload("res://games/rollback_fighter/scripts/net/LatencyHarnessTransport.gd")
const RollbackNetworkSessionScene = preload("res://games/rollback_fighter/scripts/net/RollbackNetworkSession.gd")
const ENetTransportScene = preload("res://games/rollback_fighter/scripts/net/ENetTransport.gd")


var rollback_session: Node = null
var transport: Node = null
var local_player_id: int = 1

var benchmark_running: bool = false
var benchmark_complete: bool = false
var benchmark_start_frame: int = 0
var p1_sprite_debug: Node = null
var p2_sprite_debug: Node = null
var _physics_ticks_since_last_render: int = 0
var _last_render_physics_ticks: int = 0


@onready var cam: Camera2D = get_node_or_null("Camera2D")
@onready var p1_placeholder: Node2D = get_node_or_null("PlayerPlaceholder")
@onready var p2_placeholder: Node2D = get_node_or_null("OpponentPlaceholder")
@onready var hud: Node = get_node_or_null("HUD")
@onready var play_status_label: Label = get_node_or_null("HUD/StatusLabel")

@onready var debug_hud_root: Control = get_node_or_null("DebugHUD/Control")
@onready var debug_tick_label: Label = debug_hud_root.get_node("MarginContainer/VBoxContainer/TickLabel") if debug_hud_root else null
@onready var debug_pos_label: Label = debug_hud_root.get_node("MarginContainer/VBoxContainer/PosLabel") if debug_hud_root else null
@onready var debug_input_label: Label = debug_hud_root.get_node("MarginContainer/VBoxContainer/InputLabel") if debug_hud_root else null
@onready var debug_replay_label: Label = debug_hud_root.get_node("MarginContainer/VBoxContainer/ReplayLabel") if debug_hud_root else null

const LEAN_OFFSET := 14.0
const LEAN_LERP_SPEED := 10.0
const HURTBOX_FILL_COLOR := Color(0.15, 0.45, 1.0, 0.22)
const HURTBOX_LINE_COLOR := Color(0.25, 0.65, 1.0, 0.95)
const HITBOX_FILL_COLOR := Color(1.0, 0.1, 0.1, 0.28)
const HITBOX_LINE_COLOR := Color(1.0, 0.2, 0.2, 1.0)
const RENDER_CORRECTION_MAX_DISTANCE := 18.0
const RENDER_CORRECTION_FRAMES := 3
const PRESENTATION_STEP_SAMPLE_CAPACITY := 4096
const PRESENTATION_LARGE_STEP_THRESHOLD := 10.0

@export var show_runtime_combat_boxes: bool = true

var _lean_vis_x: float = 0.0
var _combat_box_overlay: Node2D = null
var _remote_render_correction_active: bool = false
var _remote_render_correction_initial_error: Vector2 = Vector2.ZERO
var _remote_render_correction_error: Vector2 = Vector2.ZERO
var _remote_render_correction_frames_remaining: int = 0
var _remote_render_correction_snap_count: int = 0
var _remote_render_correction_smooth_count: int = 0

# Presentation Gate P1 diagnostics. These observe actual pre-draw samples and
# never feed back into simulation or rendering.
var _presentation_render_frame_count: int = 0
var _presentation_max_physics_ticks_since_last_render: int = 0
var _presentation_fps_sum: float = 0.0
var _presentation_authoritative_x: float = 0.0
var _presentation_rendered_x: float = 0.0
var _presentation_render_visual_error_x: float = 0.0
var _presentation_max_abs_render_visual_error_x: float = 0.0
var _presentation_render_step_x: float = 0.0
var _presentation_abs_render_step_x: float = 0.0
var _presentation_authoritative_step_x: float = 0.0
var _presentation_max_abs_render_step_x: float = 0.0
var _presentation_max_abs_authoritative_step_x: float = 0.0
var _presentation_render_step_count: int = 0
var _presentation_abs_render_step_sum: float = 0.0
var _presentation_cached_p95_abs_render_step: float = 0.0
var _presentation_steps_over_8_px: int = 0
var _presentation_steps_over_10_px: int = 0
var _presentation_steps_over_16_px: int = 0
var _presentation_large_step_with_multi_physics_tick: int = 0
var _presentation_large_step_with_rollback: int = 0
var _presentation_large_step_with_render_correction: int = 0
var _presentation_large_step_with_prediction_lead_cap: int = 0
var _presentation_large_step_with_soft_sync_yield: int = 0
var _presentation_large_step_unclassified: int = 0
var _presentation_rollback_this_render: bool = false
var _presentation_soft_sync_yield_this_render: bool = false
var _presentation_render_correction_this_render: bool = false
var _presentation_has_previous_sample: bool = false
var _presentation_previous_rendered_x: float = 0.0
var _presentation_previous_authoritative_x: float = 0.0
var _presentation_abs_render_step_samples: Array[float] = []
var _presentation_step_sample_write_index: int = 0
var _presentation_baseline_rollback_count: int = 0
var _presentation_baseline_correction_smooth_count: int = 0
var _presentation_baseline_correction_snap_count: int = 0
var _presentation_last_rollback_count: int = 0
var _presentation_last_soft_sync_yield_ticks: int = 0
var _presentation_last_correction_smooth_count: int = 0
var _presentation_last_correction_snap_count: int = 0
var _presentation_max_prediction_lead: int = 0


func _ready() -> void:
	print("[Arena] _ready")

	add_child(player_state)
	add_child(opponent_state)
	add_child(input_system)
	add_child(lean_system)
	add_child(combat_system)

	_combat_box_overlay = Node2D.new()
	_combat_box_overlay.name = "RuntimeCombatBoxOverlay"
	_combat_box_overlay.z_index = 100
	add_child(_combat_box_overlay)
	_combat_box_overlay.draw.connect(_draw_runtime_combat_boxes)

	player_state.position = Vector2(200, 250)
	opponent_state.position = Vector2(600, 250)

	_ensure_opponent_placeholder()
	p1_sprite_debug = _bind_sprite_to_state(p1_placeholder, player_state, "P1")
	p2_sprite_debug = _bind_sprite_to_state(p2_placeholder, opponent_state, "P2")

	if not RenderingServer.frame_pre_draw.is_connected(_on_frame_pre_draw):
		RenderingServer.frame_pre_draw.connect(_on_frame_pre_draw)

	lean_system.player_state = player_state
	combat_system.p1_state = player_state
	combat_system.p2_state = opponent_state

	add_child(adapter)
	adapter.setup(player_state, opponent_state, input_system, lean_system, combat_system)

	if USE_ENET:
		transport = ENetTransportScene.new()
		transport.name = "ENetTransport"
		transport.artificial_delay_frames = BENCHMARK_DELAY_FRAMES
		transport.artificial_jitter_frames = BENCHMARK_JITTER_FRAMES
		transport.deterministic_stress_input_loss_enabled = (
			QA_STRESS_BENCHMARK_ENABLED
			and QA_STRESS_FORCE_PACKET_LOSS
		)
		add_child(transport)

		if ENET_HOST:
			local_player_id = 1
			transport.host(ENET_PORT)
			print("[Arena] ENet HOST mode | player_id=1 | port=%d" % ENET_PORT)
		else:
			local_player_id = 2
			transport.join(ENET_IP, ENET_PORT)
			print("[Arena] ENet CLIENT mode | player_id=2 | joining %s:%d" % [ENET_IP, ENET_PORT])
	else:
		transport = LatencyHarnessTransportScene.new()
		transport.delay_frames = BENCHMARK_DELAY_FRAMES
		add_child(transport)
		local_player_id = 1
		print("[Arena] LatencyHarness mode | player_id=1")

	rollback_session = RollbackNetworkSessionScene.new()
	add_child(rollback_session)
	rollback_session.setup(adapter, transport, local_player_id)
	rollback_session.input_delay_frames = BENCHMARK_INPUT_DELAY_FRAMES
	if rollback_session.has_signal("rollback_correction_applied"):
		rollback_session.rollback_correction_applied.connect(
			_on_rollback_correction_applied
		)
	
	if hud:
		hud.set("p1_state", player_state)
		hud.set("p2_state", opponent_state)

	if transport != null and transport.has_signal("start_match_received"):
		if not transport.start_match_received.is_connected(_on_start_match_received):
			transport.start_match_received.connect(_on_start_match_received)

	if QA_BOT_BENCHMARK_ENABLED and QA_STRESS_BENCHMARK_ENABLED:
		push_error("[Arena] Enable only one QA benchmark mode at a time.")

	print("[Arena] Benchmark config | mode=%s delay=%d jitter=%d duration=%d" % [
		_benchmark_mode_name(),
		BENCHMARK_DELAY_FRAMES,
		BENCHMARK_JITTER_FRAMES,
		_benchmark_duration_frames()
	])
	_reset_presentation_measurement(false)


func _physics_process(delta: float) -> void:
	_physics_ticks_since_last_render += 1
	_update_play_hud()

	if rollback_session and not bool(rollback_session.match_started):
		_update_visuals()
		_update_camera(delta)
		_update_health_tint()
		_update_combat_debug_hud()
		_update_rollback_debug_hud()
		return

	if rollback_session:
		if transport != null and transport.get("is_connected") != null:
			if not bool(transport.get("is_connected")):
				_update_visuals()
				_update_camera(delta)
				_update_health_tint()
				_update_combat_debug_hud()
				_update_rollback_debug_hud()
				return

		if benchmark_complete:
			_update_visuals()
			_update_camera(delta)
			_update_health_tint()
			_update_combat_debug_hud()
			_update_rollback_debug_hud()
			return

		var local_input: Dictionary = _collect_local_input()
		rollback_session.tick(local_input)

		if benchmark_running:
			_check_benchmark_complete()

	_update_visuals()
	_update_camera(delta)
	_update_health_tint()
	_update_combat_debug_hud()
	_update_rollback_debug_hud()


func _on_frame_pre_draw() -> void:
	_last_render_physics_ticks = _physics_ticks_since_last_render
	var correction_was_active: bool = _remote_render_correction_active
	_advance_remote_render_correction()
	_record_presentation_measurement(correction_was_active)
	_physics_ticks_since_last_render = 0
	_update_visual_diagnostic_hud()


func _collect_local_input() -> Dictionary:
	if QA_STRESS_BENCHMARK_ENABLED:
		return _collect_stress_bot_input()

	if QA_BOT_BENCHMARK_ENABLED:
		return _collect_bot_input()

	var mx := Input.get_action_strength("p1_right") - Input.get_action_strength("p1_left")

	return {
		"mx": mx,
		"lean_l": Input.is_action_pressed("lean_left"),
		"lean_r": Input.is_action_pressed("lean_right"),
		"atk_l": Input.is_action_just_pressed("jab"),
		"atk_h": Input.is_action_just_pressed("heavy_attack"),
		"block": Input.is_action_pressed("block"),
		"dodge": Input.is_action_just_pressed("dodge"),
	}


func _collect_bot_input() -> Dictionary:
	var f: int = 0
	if rollback_session != null:
		f = int(rollback_session.current_frame)

	var mx: float = 0.0

	# Gate 6: approach once, settle, then P1 performs one light jab.
	if f <= 64:
		mx = 1.0 if local_player_id == 1 else -1.0

	return {
		"mx": mx,
		"lean_l": false,
		"lean_r": false,
		"atk_l": local_player_id == 1 and f == 90,
		"atk_h": false,
		"block": false,
		"dodge": false,
	}


func _stress_neutral_input() -> Dictionary:
	return {
		"mx": 0.0,
		"lean_l": false,
		"lean_r": false,
		"atk_l": false,
		"atk_h": false,
		"block": false,
		"dodge": false,
	}


func _stress_frame_inclusive(frame: int, first: int, last: int) -> bool:
	return frame >= first and frame <= last


func _stress_local_toward_axis() -> float:
	return 1.0 if local_player_id == 1 else -1.0


func _stress_reversal_axis(
	cycle_frame: int,
	first_frame: int,
	segment_frames: int,
	starts_toward: bool
) -> float:
	var segment: int = int(
		(cycle_frame - first_frame) / segment_frames
	)
	var use_toward: bool = (segment % 2 == 0) == starts_toward
	var toward: float = _stress_local_toward_axis()
	return toward if use_toward else -toward


func _collect_stress_bot_input() -> Dictionary:
	var f: int = 0
	if rollback_session != null:
		f = int(rollback_session.current_frame)

	if f >= STRESS_SCHEDULE_FRAMES:
		return _stress_neutral_input()

	var cycle: int = int(f / STRESS_CYCLE_FRAMES)
	var t: int = f % STRESS_CYCLE_FRAMES
	var aggressor_id: int = 1 if cycle % 2 == 0 else 2
	var is_aggressor: bool = local_player_id == aggressor_id
	var toward: float = _stress_local_toward_axis()
	var mx: float = 0.0

	if _stress_frame_inclusive(t, 0, 33):
		mx = toward
	elif _stress_frame_inclusive(t, 34, 81):
		mx = _stress_reversal_axis(t, 34, 4, false)
	elif _stress_frame_inclusive(t, 228, 235):
		mx = toward
	elif _stress_frame_inclusive(t, 320, 359):
		mx = -toward
	elif _stress_frame_inclusive(t, 360, 407):
		mx = toward
	elif _stress_frame_inclusive(t, 408, 455):
		mx = _stress_reversal_axis(t, 408, 3, false)
	elif _stress_frame_inclusive(t, 660, 719):
		mx = _stress_reversal_axis(t, 660, 5, true)
	elif _stress_frame_inclusive(t, 720, 779):
		mx = 1.0 if aggressor_id == 1 else -1.0
	elif _stress_frame_inclusive(t, 780, 809):
		mx = 1.0
	elif _stress_frame_inclusive(t, 810, 839):
		mx = -1.0
	elif _stress_frame_inclusive(t, 1020, 1079):
		mx = _stress_reversal_axis(t, 1020, 4, true)

	var atk_l: bool = false
	var atk_h: bool = false
	var block: bool = false
	var dodge: bool = false

	if is_aggressor:
		atk_l = t in [136, 216, 678, 708, 770, 882, 1040]
		atk_h = t in [179, 248, 742, 1053]
		block = (
			_stress_frame_inclusive(t, 282, 299)
			or _stress_frame_inclusive(t, 844, 868)
		)
	else:
		atk_l = t == 286
		atk_h = t == 850
		block = (
			_stress_frame_inclusive(t, 132, 150)
			or _stress_frame_inclusive(t, 244, 265)
			or _stress_frame_inclusive(t, 674, 690)
			or _stress_frame_inclusive(t, 764, 780)
			or _stress_frame_inclusive(t, 1036, 1046)
		)
		dodge = t in [176, 704, 738, 878, 1050]

	return {
		"mx": mx,
		"lean_l": false,
		"lean_r": false,
		"atk_l": atk_l,
		"atk_h": atk_h,
		"block": block,
		"dodge": dodge,
	}


func _benchmark_enabled() -> bool:
	return QA_BOT_BENCHMARK_ENABLED or QA_STRESS_BENCHMARK_ENABLED


func _benchmark_duration_frames() -> int:
	if QA_STRESS_BENCHMARK_ENABLED:
		return STRESS_TOTAL_FRAMES

	return BENCHMARK_DURATION_FRAMES


func _benchmark_mode_name() -> String:
	if QA_STRESS_BENCHMARK_ENABLED:
		return "STRESS_LOSS" if QA_STRESS_FORCE_PACKET_LOSS else "STRESS_NATURAL"

	if QA_BOT_BENCHMARK_ENABLED:
		return "CONTROLLED_SINGLE_JAB"

	return "MANUAL"


func _start_benchmark_timer() -> void:
	benchmark_running = true
	benchmark_complete = false
	benchmark_start_frame = int(rollback_session.current_frame) if rollback_session != null else 0

	print("[Benchmark] START | player_id=%d delay=%d jitter=%d mode=%s duration=%d" % [
		local_player_id,
		BENCHMARK_DELAY_FRAMES,
		BENCHMARK_JITTER_FRAMES,
		_benchmark_mode_name(),
		_benchmark_duration_frames()
	])


func _check_benchmark_complete() -> void:
	if rollback_session == null:
		return

	var elapsed_frames: int = int(rollback_session.current_frame) - benchmark_start_frame

	if elapsed_frames >= _benchmark_duration_frames():
		benchmark_running = false
		benchmark_complete = true
		_print_benchmark_results()


func _frame_gap() -> int:
	if rollback_session == null:
		return 0

	return int(rollback_session.get_diagnostics().get("frame_gap", 0))


func _print_benchmark_results() -> void:
	if rollback_session == null:
		return
	var diagnostics: Dictionary = rollback_session.get_diagnostics()

	print("")
	print("========== ROLLBACK BENCHMARK RESULT ==========")
	print("PlayerID: %d" % local_player_id)
	print("Mode: %s" % ("ENet" if USE_ENET else "LatencyHarness"))
	print("BenchmarkMode: %s" % _benchmark_mode_name())
	print("DelayFrames: %d" % BENCHMARK_DELAY_FRAMES)
	print("JitterFrames: %d" % BENCHMARK_JITTER_FRAMES)
	print("DurationFrames: %d" % _benchmark_duration_frames())
	if QA_STRESS_BENCHMARK_ENABLED:
		print("StressScheduleFrames: %d" % STRESS_SCHEDULE_FRAMES)
		print("StressDrainFrames: %d" % STRESS_DRAIN_FRAMES)
	print("Packets: %d" % int(diagnostics["packets_received"]))
	print("LastRemoteFrame: %d" % int(diagnostics["last_remote_frame"]))
	print("LocalFrame: %d" % int(diagnostics["current_frame"]))
	print("FrameGap: %d" % int(diagnostics["frame_gap"]))
	print("PredictionLead: %d" % int(diagnostics["prediction_lead"]))
	print("MaxPredictionLead: %d" % int(diagnostics["max_prediction_lead"]))
	print("LeadLimit: %d" % int(diagnostics["prediction_lead_limit"]))
	print("LeadStalled: %s" % str(diagnostics["lead_stalled"]))
	print("LeadStallTicks: %d" % int(diagnostics["lead_stall_ticks"]))
	print("SoftSyncActive: %s" % str(diagnostics["soft_sync_active"]))
	print("SoftSyncAheadSamples: %d" % int(diagnostics["soft_sync_ahead_samples"]))
	print("SoftSyncYieldTicks: %d" % int(diagnostics["soft_sync_yield_ticks"]))
	print("SoftSyncYieldCooldown: %d" % int(diagnostics["soft_sync_yield_cooldown"]))
	print("LocalFrameAdvantage: %.2f" % float(diagnostics["local_frame_advantage"]))
	print("RenderCorrectionActive: %s" % str(_remote_render_correction_active))
	print("RenderCorrectionErrorX: %.2f" % _remote_render_correction_error.x)
	print("RenderCorrectionFramesRemaining: %d" % _remote_render_correction_frames_remaining)
	print("CorrectionSnapCount: %d" % _remote_render_correction_snap_count)
	print("CorrectionSmoothCount: %d" % _remote_render_correction_smooth_count)
	print("RedundantFramesReceived: %d" % int(diagnostics["redundant_frames_received"]))
	print("RecoveredMissingFrames: %d" % int(diagnostics["recovered_missing_frames"]))
	print("DuplicateInputFrames: %d" % int(diagnostics["duplicate_input_frames"]))
	print("RepairRequestsSent: %d" % int(diagnostics["repair_requests_sent"]))
	print("RepairRequestsReceived: %d" % int(diagnostics["repair_requests_received"]))
	print("RepairResponsesSent: %d" % int(diagnostics["repair_responses_sent"]))
	print("RepairResponsesReceived: %d" % int(diagnostics["repair_responses_received"]))
	print("LastRepairRequestedFrame: %d" % int(diagnostics["last_repair_requested_frame"]))
	print("LastRepairRecoveredFrame: %d" % int(diagnostics["last_repair_recovered_frame"]))
	print("RepairUnavailable: %s" % str(diagnostics["repair_unavailable_error"]))
	print("RepairUnavailableCount: %d" % int(diagnostics["repair_unavailable_count"]))
	print("RemoteConfirmedThrough: %d" % int(diagnostics["remote_confirmed_through"]))
	print("ConfirmationLag: %d" % int(diagnostics["confirmation_lag"]))
	print("EarliestMissingRemoteFrame: %d" % int(diagnostics["earliest_missing_remote_frame"]))
	print("OldestRetainedSnapshot: %d" % int(diagnostics["oldest_retained_snapshot"]))
	print("HistoryExhausted: %s" % str(diagnostics["history_exhausted"]))
	print("HistoryExhaustionFrame: %d" % int(diagnostics["history_exhaustion_frame"]))
	print("RollbackCount: %d" % int(diagnostics["rollback_count"]))
	print("MaxRollbackDepth: %d" % int(diagnostics["max_rollback_depth"]))
	print("PredictionMisses: %d" % int(diagnostics["prediction_misses"]))
	print("InputMutationError: %s" % str(diagnostics["input_mutation_error"]))
	print("InputMutationErrorFrame: %d" % int(diagnostics["input_mutation_error_frame"]))

	print("ChecksumFramesCompared: %d" % int(diagnostics["checksum_frames_compared"]))
	print("ChecksumMismatchCount: %d" % int(diagnostics["checksum_mismatch_count"]))
	print("ChecksumMismatch: %s" % str(diagnostics["checksum_mismatch"]))
	print("FirstChecksumMismatchFrame: %d" % int(diagnostics["first_checksum_mismatch_frame"]))
	print("FirstStateDivergenceFrame: %d" % int(diagnostics["first_state_divergence_frame"]))
	print("FirstStateDivergenceField: %s" % diagnostics["first_state_divergence_field"])
	print("FirstStateDivergenceLocal: %s" % diagnostics["first_state_divergence_local"])
	print("FirstStateDivergenceRemote: %s" % diagnostics["first_state_divergence_remote"])
	print("P1HP: %d" % int(player_state.hp))
	print("P2HP: %d" % int(opponent_state.hp))
	print("P1State: %d" % int(player_state.state))
	print("P2State: %d" % int(opponent_state.state))
	print("P1FramesLeft: %d" % int(player_state.frames_left))
	print("P2FramesLeft: %d" % int(opponent_state.frames_left))
	print("P1AttackID: %d" % int(player_state.attack_id))
	print("P2AttackID: %d" % int(opponent_state.attack_id))
	print("P1HitConfirmed: %s" % str(player_state.hit_confirmed))
	print("P2HitConfirmed: %s" % str(opponent_state.hit_confirmed))

	if QA_STRESS_BENCHMARK_ENABLED and USE_ENET and transport != null:
		print("ForcedInputPacketsDropped: %d" % int(transport.get(
			"deterministic_stress_input_packets_dropped"
		)))

	if QA_STRESS_BENCHMARK_ENABLED:
		_print_stress_verdict(diagnostics)

	print("InputDelayFrames: %d" % BENCHMARK_INPUT_DELAY_FRAMES)
	print("===============================================")
	print("")


func _print_stress_verdict(diagnostics: Dictionary) -> void:
	var failures: Array[String] = []
	var required_confirmed_frame: int = STRESS_SCHEDULE_FRAMES - 1

	if int(diagnostics["current_frame"]) < STRESS_TOTAL_FRAMES:
		failures.append("benchmark did not reach the full stress duration")
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
	if int(diagnostics["max_prediction_lead"]) > int(diagnostics["prediction_lead_limit"]):
		failures.append("prediction lead exceeded its configured limit")
	if int(diagnostics["remote_confirmed_through"]) < required_confirmed_frame:
		failures.append("stress schedule inputs were not fully confirmed")
	if int(diagnostics["local_checksum_confirmed_through"]) < required_confirmed_frame:
		failures.append("stress schedule checksums were not fully confirmed")
	if int(player_state.hp) <= 0 or int(opponent_state.hp) <= 0:
		failures.append("a fighter died before the stress benchmark completed")

	if QA_STRESS_FORCE_PACKET_LOSS:
		var expected_repair_frame: int = 4260 if local_player_id == 1 else 1860
		if int(diagnostics["repair_requests_sent"]) < 1:
			failures.append("forced persistent hole sent no repair request")
		if int(diagnostics["repair_responses_received"]) < 1:
			failures.append("forced persistent hole received no repair response")
		if int(diagnostics["last_repair_recovered_frame"]) < expected_repair_frame:
			failures.append("forced persistent hole was not repaired")

	print("StressVerdict: %s" % ("PASS" if failures.is_empty() else "FAIL"))
	print("StressFailureCount: %d" % failures.size())
	for failure: String in failures:
		print("StressFailure: %s" % failure)


func _update_visuals() -> void:
	_apply_fighter_render_positions()
	if _combat_box_overlay:
		_combat_box_overlay.queue_redraw()


func _get_remote_fighter_state() -> PlayerState:
	return opponent_state if local_player_id == 1 else player_state


func _get_remote_fighter_placeholder() -> Node2D:
	return p2_placeholder if local_player_id == 1 else p1_placeholder


func _get_remote_snapshot_key() -> String:
	return "p2" if local_player_id == 1 else "p1"


func _apply_fighter_render_positions() -> void:
	if p1_placeholder:
		p1_placeholder.position = player_state.position
	if p2_placeholder:
		p2_placeholder.position = opponent_state.position

	if not _remote_render_correction_active:
		return

	var remote_state: PlayerState = _get_remote_fighter_state()
	var remote_placeholder: Node2D = _get_remote_fighter_placeholder()
	if remote_state != null and remote_placeholder != null:
		remote_placeholder.position = (
			remote_state.position
			+ _remote_render_correction_error
		)


func _snapshot_position(fighter_snapshot: Dictionary) -> Vector2:
	return Vector2(
		float(fighter_snapshot.get("x", 0.0)),
		float(fighter_snapshot.get("y", 0.0))
	)


func _is_attack_state(state: int) -> bool:
	return state in [
		PlayerState.MoveState.STARTUP,
		PlayerState.MoveState.ACTIVE,
		PlayerState.MoveState.RECOVERY,
	]


func _rollback_correction_requires_snap(
	before_fighter: Dictionary,
	after_fighter: Dictionary,
	before_snapshot: Dictionary,
	after_snapshot: Dictionary
) -> bool:
	var before_state: int = int(before_fighter.get("st", PlayerState.MoveState.IDLE))
	var after_state: int = int(after_fighter.get("st", PlayerState.MoveState.IDLE))

	var attack_transition: bool = (
		before_state != after_state
		and (_is_attack_state(before_state) or _is_attack_state(after_state))
	)
	attack_transition = attack_transition or (
		int(before_fighter.get("ak", PlayerState.AttackKind.NONE))
		!= int(after_fighter.get("ak", PlayerState.AttackKind.NONE))
	) or (
		int(before_fighter.get("aid", 0))
		!= int(after_fighter.get("aid", 0))
	)

	var involves_block: bool = (
		before_state == PlayerState.MoveState.BLOCK
		or after_state == PlayerState.MoveState.BLOCK
		or bool(before_fighter.get("blk", false))
		or bool(after_fighter.get("blk", false))
	)
	var involves_dodge: bool = (
		before_state == PlayerState.MoveState.DODGE
		or after_state == PlayerState.MoveState.DODGE
		or bool(before_fighter.get("inv", false))
		or bool(after_fighter.get("inv", false))
	)
	var involves_hurt_or_death: bool = (
		before_state == PlayerState.MoveState.HURT
		or after_state == PlayerState.MoveState.HURT
		or before_state == PlayerState.MoveState.DEAD
		or after_state == PlayerState.MoveState.DEAD
	)
	var facing_changed: bool = (
		int(before_fighter.get("fa", 1))
		!= int(after_fighter.get("fa", 1))
	)
	var hit_changed: bool = (
		bool(before_fighter.get("hc", false))
		!= bool(after_fighter.get("hc", false))
	) or (
		int(before_fighter.get("hp", 0))
		!= int(after_fighter.get("hp", 0))
	) or (
		int(before_fighter.get("hurt", 0))
		!= int(after_fighter.get("hurt", 0))
	)

	var before_combat: Dictionary = before_snapshot.get("combat", {})
	var after_combat: Dictionary = after_snapshot.get("combat", {})
	var hitstop_changed: bool = (
		int(before_combat.get("hitstop", 0))
		!= int(after_combat.get("hitstop", 0))
	)

	return (
		attack_transition
		or involves_block
		or involves_dodge
		or involves_hurt_or_death
		or facing_changed
		or hit_changed
		or hitstop_changed
	)


func _clear_remote_render_correction() -> void:
	_remote_render_correction_active = false
	_remote_render_correction_initial_error = Vector2.ZERO
	_remote_render_correction_error = Vector2.ZERO
	_remote_render_correction_frames_remaining = 0


func _on_rollback_correction_applied(
	_from_frame: int,
	_rollback_depth: int,
	before_snapshot: Dictionary,
	after_snapshot: Dictionary
) -> void:
	# The overlay redraws from authoritative CombatSystem queries and never
	# receives the sprite-only correction offset.
	if _combat_box_overlay != null:
		_combat_box_overlay.queue_redraw()

	var remote_key: String = _get_remote_snapshot_key()
	var before_fighter: Dictionary = before_snapshot.get(remote_key, {})
	var after_fighter: Dictionary = after_snapshot.get(remote_key, {})
	if before_fighter.is_empty() or after_fighter.is_empty():
		return

	var before_authoritative: Vector2 = _snapshot_position(before_fighter)
	var corrected_authoritative: Vector2 = _snapshot_position(after_fighter)
	if before_authoritative.is_equal_approx(corrected_authoritative):
		return

	var remote_placeholder: Node2D = _get_remote_fighter_placeholder()
	if remote_placeholder == null:
		return

	var visual_error: Vector2 = (
		remote_placeholder.position
		- corrected_authoritative
	)
	var must_snap: bool = (
		visual_error.length() > RENDER_CORRECTION_MAX_DISTANCE
		or _rollback_correction_requires_snap(
			before_fighter,
			after_fighter,
			before_snapshot,
			after_snapshot
		)
	)

	if must_snap:
		_remote_render_correction_snap_count += 1
		_clear_remote_render_correction()
		remote_placeholder.position = corrected_authoritative
		return

	if visual_error.is_zero_approx():
		_clear_remote_render_correction()
		remote_placeholder.position = corrected_authoritative
		return

	_remote_render_correction_smooth_count += 1
	_remote_render_correction_active = true
	_remote_render_correction_initial_error = visual_error
	_remote_render_correction_error = visual_error
	_remote_render_correction_frames_remaining = RENDER_CORRECTION_FRAMES
	remote_placeholder.position = corrected_authoritative + visual_error


func _advance_remote_render_correction() -> void:
	if not _remote_render_correction_active:
		return

	_remote_render_correction_frames_remaining = maxi(
		_remote_render_correction_frames_remaining - 1,
		0
	)
	var weight: float = (
		float(_remote_render_correction_frames_remaining)
		/ float(RENDER_CORRECTION_FRAMES)
	)
	_remote_render_correction_error = (
		_remote_render_correction_initial_error
		* weight
	)

	if _remote_render_correction_frames_remaining <= 0:
		_clear_remote_render_correction()

	_apply_fighter_render_positions()


func _store_presentation_step_sample(abs_step: float) -> void:
	if _presentation_abs_render_step_samples.size() < PRESENTATION_STEP_SAMPLE_CAPACITY:
		_presentation_abs_render_step_samples.append(abs_step)
		return

	_presentation_abs_render_step_samples[
		_presentation_step_sample_write_index
	] = abs_step
	_presentation_step_sample_write_index = (
		(_presentation_step_sample_write_index + 1)
		% PRESENTATION_STEP_SAMPLE_CAPACITY
	)


func _presentation_mean_abs_render_step() -> float:
	if _presentation_render_step_count <= 0:
		return 0.0

	return (
		_presentation_abs_render_step_sum
		/ float(_presentation_render_step_count)
	)


func _presentation_p95_abs_render_step() -> float:
	if _presentation_abs_render_step_samples.is_empty():
		return 0.0

	var sorted_samples: Array[float] = (
		_presentation_abs_render_step_samples.duplicate()
	)
	sorted_samples.sort()
	var percentile_index: int = clampi(
		int(ceil(0.95 * float(sorted_samples.size()))) - 1,
		0,
		sorted_samples.size() - 1
	)
	return sorted_samples[percentile_index]


func _reset_presentation_measurement(print_confirmation: bool = true) -> void:
	var diagnostics: Dictionary = {}
	if rollback_session != null:
		diagnostics = rollback_session.get_diagnostics()

	_presentation_render_frame_count = 0
	_presentation_max_physics_ticks_since_last_render = 0
	_presentation_fps_sum = 0.0
	_presentation_render_step_x = 0.0
	_presentation_abs_render_step_x = 0.0
	_presentation_authoritative_step_x = 0.0
	_presentation_max_abs_render_step_x = 0.0
	_presentation_max_abs_authoritative_step_x = 0.0
	_presentation_render_step_count = 0
	_presentation_abs_render_step_sum = 0.0
	_presentation_cached_p95_abs_render_step = 0.0
	_presentation_steps_over_8_px = 0
	_presentation_steps_over_10_px = 0
	_presentation_steps_over_16_px = 0
	_presentation_large_step_with_multi_physics_tick = 0
	_presentation_large_step_with_rollback = 0
	_presentation_large_step_with_render_correction = 0
	_presentation_large_step_with_prediction_lead_cap = 0
	_presentation_large_step_with_soft_sync_yield = 0
	_presentation_large_step_unclassified = 0
	_presentation_rollback_this_render = false
	_presentation_soft_sync_yield_this_render = false
	_presentation_render_correction_this_render = false
	_presentation_abs_render_step_samples.clear()
	_presentation_step_sample_write_index = 0

	var remote_state: PlayerState = _get_remote_fighter_state()
	var remote_placeholder: Node2D = _get_remote_fighter_placeholder()
	_presentation_has_previous_sample = (
		remote_state != null and remote_placeholder != null
	)
	if _presentation_has_previous_sample:
		_presentation_authoritative_x = remote_state.position.x
		_presentation_rendered_x = remote_placeholder.position.x
		_presentation_render_visual_error_x = (
			_presentation_rendered_x - _presentation_authoritative_x
		)
		_presentation_previous_authoritative_x = _presentation_authoritative_x
		_presentation_previous_rendered_x = _presentation_rendered_x
	else:
		_presentation_authoritative_x = 0.0
		_presentation_rendered_x = 0.0
		_presentation_render_visual_error_x = 0.0
		_presentation_previous_authoritative_x = 0.0
		_presentation_previous_rendered_x = 0.0

	_presentation_max_abs_render_visual_error_x = absf(
		_presentation_render_visual_error_x
	)
	_presentation_baseline_rollback_count = int(
		diagnostics.get("rollback_count", 0)
	)
	_presentation_baseline_correction_smooth_count = (
		_remote_render_correction_smooth_count
	)
	_presentation_baseline_correction_snap_count = (
		_remote_render_correction_snap_count
	)
	_presentation_last_rollback_count = _presentation_baseline_rollback_count
	_presentation_last_soft_sync_yield_ticks = int(
		diagnostics.get("soft_sync_yield_ticks", 0)
	)
	_presentation_last_correction_smooth_count = (
		_remote_render_correction_smooth_count
	)
	_presentation_last_correction_snap_count = (
		_remote_render_correction_snap_count
	)
	_presentation_max_prediction_lead = int(
		diagnostics.get("prediction_lead", 0)
	)

	if print_confirmation:
		print("[PresentationP1] Measurement reset.")


func _record_presentation_measurement(correction_was_active: bool) -> void:
	var remote_state: PlayerState = _get_remote_fighter_state()
	var remote_placeholder: Node2D = _get_remote_fighter_placeholder()
	if remote_state == null or remote_placeholder == null:
		return

	var diagnostics: Dictionary = {}
	if rollback_session != null:
		diagnostics = rollback_session.get_diagnostics()

	var rollback_count: int = int(diagnostics.get("rollback_count", 0))
	var soft_sync_yield_ticks: int = int(
		diagnostics.get("soft_sync_yield_ticks", 0)
	)
	var prediction_lead: int = int(diagnostics.get("prediction_lead", 0))
	var prediction_lead_limit: int = int(
		diagnostics.get("prediction_lead_limit", 0)
	)

	_presentation_render_frame_count += 1
	_presentation_fps_sum += float(Engine.get_frames_per_second())
	_presentation_max_physics_ticks_since_last_render = maxi(
		_presentation_max_physics_ticks_since_last_render,
		_last_render_physics_ticks
	)
	_presentation_max_prediction_lead = maxi(
		_presentation_max_prediction_lead,
		prediction_lead
	)

	_presentation_rollback_this_render = (
		rollback_count > _presentation_last_rollback_count
	)
	_presentation_soft_sync_yield_this_render = (
		soft_sync_yield_ticks > _presentation_last_soft_sync_yield_ticks
	)
	_presentation_render_correction_this_render = (
		correction_was_active
		or _remote_render_correction_active
		or _remote_render_correction_smooth_count
			> _presentation_last_correction_smooth_count
		or _remote_render_correction_snap_count
			> _presentation_last_correction_snap_count
	)

	_presentation_authoritative_x = remote_state.position.x
	_presentation_rendered_x = remote_placeholder.position.x
	_presentation_render_visual_error_x = (
		_presentation_rendered_x - _presentation_authoritative_x
	)
	_presentation_max_abs_render_visual_error_x = maxf(
		_presentation_max_abs_render_visual_error_x,
		absf(_presentation_render_visual_error_x)
	)

	if _presentation_has_previous_sample:
		_presentation_render_step_x = (
			_presentation_rendered_x - _presentation_previous_rendered_x
		)
		_presentation_authoritative_step_x = (
			_presentation_authoritative_x
			- _presentation_previous_authoritative_x
		)
		var abs_render_step: float = absf(_presentation_render_step_x)
		_presentation_abs_render_step_x = abs_render_step
		var abs_authoritative_step: float = absf(
			_presentation_authoritative_step_x
		)
		_presentation_render_step_count += 1
		_presentation_abs_render_step_sum += abs_render_step
		_presentation_max_abs_render_step_x = maxf(
			_presentation_max_abs_render_step_x,
			abs_render_step
		)
		_presentation_max_abs_authoritative_step_x = maxf(
			_presentation_max_abs_authoritative_step_x,
			abs_authoritative_step
		)
		_store_presentation_step_sample(abs_render_step)
		if _presentation_render_step_count % 60 == 0:
			_presentation_cached_p95_abs_render_step = (
				_presentation_p95_abs_render_step()
			)

		if abs_render_step > 8.0:
			_presentation_steps_over_8_px += 1
		if abs_render_step > PRESENTATION_LARGE_STEP_THRESHOLD:
			_presentation_steps_over_10_px += 1
		if abs_render_step > 16.0:
			_presentation_steps_over_16_px += 1

		if abs_render_step > PRESENTATION_LARGE_STEP_THRESHOLD:
			var correlated: bool = false
			if _last_render_physics_ticks > 1:
				_presentation_large_step_with_multi_physics_tick += 1
				correlated = true
			if _presentation_rollback_this_render:
				_presentation_large_step_with_rollback += 1
				correlated = true
			if _presentation_render_correction_this_render:
				_presentation_large_step_with_render_correction += 1
				correlated = true
			if (
				prediction_lead_limit > 0
				and prediction_lead >= prediction_lead_limit - 1
			):
				_presentation_large_step_with_prediction_lead_cap += 1
				correlated = true
			if _presentation_soft_sync_yield_this_render:
				_presentation_large_step_with_soft_sync_yield += 1
				correlated = true
			if not correlated:
				_presentation_large_step_unclassified += 1

	_presentation_has_previous_sample = true
	_presentation_previous_rendered_x = _presentation_rendered_x
	_presentation_previous_authoritative_x = _presentation_authoritative_x
	_presentation_last_rollback_count = rollback_count
	_presentation_last_soft_sync_yield_ticks = soft_sync_yield_ticks
	_presentation_last_correction_smooth_count = (
		_remote_render_correction_smooth_count
	)
	_presentation_last_correction_snap_count = (
		_remote_render_correction_snap_count
	)


func _print_presentation_measurement_report() -> void:
	var diagnostics: Dictionary = {}
	if rollback_session != null:
		diagnostics = rollback_session.get_diagnostics()

	var average_fps: float = 0.0
	if _presentation_render_frame_count > 0:
		average_fps = (
			_presentation_fps_sum
			/ float(_presentation_render_frame_count)
		)

	print("")
	print("========== PRESENTATION GATE P1 REPORT ==========")
	print("PlayerID: %d" % local_player_id)
	print("RenderedSampleCount: %d" % _presentation_render_frame_count)
	print("AverageFPS: %.2f" % average_fps)
	print("MaxPhysicsTicksSinceLastRender: %d" % _presentation_max_physics_ticks_since_last_render)
	print("MeanAbsRenderStepX: %.2f" % _presentation_mean_abs_render_step())
	print("P95AbsRenderStepX: %.2f" % _presentation_p95_abs_render_step())
	print("MaxAbsRenderStepX: %.2f" % _presentation_max_abs_render_step_x)
	print("RenderStepsOver8px: %d" % _presentation_steps_over_8_px)
	print("RenderStepsOver10px: %d" % _presentation_steps_over_10_px)
	print("RenderStepsOver16px: %d" % _presentation_steps_over_16_px)
	print("MaxAbsAuthoritativeStepX: %.2f" % _presentation_max_abs_authoritative_step_x)
	print("MaxAbsRenderVisualErrorX: %.2f" % _presentation_max_abs_render_visual_error_x)
	print("LargeStepWithMultiPhysicsTick: %d" % _presentation_large_step_with_multi_physics_tick)
	print("LargeStepWithRollback: %d" % _presentation_large_step_with_rollback)
	print("LargeStepWithRenderCorrection: %d" % _presentation_large_step_with_render_correction)
	print("LargeStepWithPredictionLeadCap: %d" % _presentation_large_step_with_prediction_lead_cap)
	print("LargeStepWithSoftSyncYield: %d" % _presentation_large_step_with_soft_sync_yield)
	print("LargeStepUnclassified: %d" % _presentation_large_step_unclassified)
	print("RollbackCountDelta: %d" % (
		int(diagnostics.get("rollback_count", 0))
		- _presentation_baseline_rollback_count
	))
	print("CorrectionSmoothCountDelta: %d" % (
		_remote_render_correction_smooth_count
		- _presentation_baseline_correction_smooth_count
	))
	print("CorrectionSnapCountDelta: %d" % (
		_remote_render_correction_snap_count
		- _presentation_baseline_correction_snap_count
	))
	print("MaxPredictionLeadDuringMeasurement: %d" % maxi(
		_presentation_max_prediction_lead,
		int(diagnostics.get("prediction_lead", 0))
	))
	print("ChecksumMismatchCount: %d" % int(
		diagnostics.get("checksum_mismatch_count", 0)
	))
	print("FirstChecksumMismatchFrame: %d" % int(
		diagnostics.get("first_checksum_mismatch_frame", -1)
	))
	print("=================================================")
	print("")


func _draw_runtime_combat_boxes() -> void:
	if not show_runtime_combat_boxes or _combat_box_overlay == null:
		return

	for fighter: PlayerState in [player_state, opponent_state]:
		var hurtbox: Rect2 = combat_system.get_debug_hurtbox_rect(fighter)
		_combat_box_overlay.draw_rect(hurtbox, HURTBOX_FILL_COLOR, true)
		_combat_box_overlay.draw_rect(hurtbox, HURTBOX_LINE_COLOR, false, 1.5)

		var hitboxes: Array[Rect2] = (
			combat_system.get_debug_active_light_hitbox_rects(fighter)
		)
		for hitbox: Rect2 in hitboxes:
			_combat_box_overlay.draw_rect(hitbox, HITBOX_FILL_COLOR, true)
			_combat_box_overlay.draw_rect(hitbox, HITBOX_LINE_COLOR, false, 1.5)


func _update_play_hud() -> void:
	if play_status_label == null:
		return

	if rollback_session != null and bool(rollback_session.match_started):
		play_status_label.text = (
			_benchmark_mode_name()
			if _benchmark_enabled()
			else "FIGHT!"
		)
		return

	if transport == null:
		play_status_label.text = "STARTING NETWORK..."
		return

	if ENET_HOST:
		var remote_peer_id: int = int(transport.get("remote_peer_id"))
		if remote_peer_id > 0:
			play_status_label.text = "CONNECTED — PRESS SPACE TO START"
		else:
			play_status_label.text = "WAITING FOR OPPONENT..."
	else:
		var connected: bool = bool(transport.get("is_connected"))
		play_status_label.text = (
			"CONNECTED — WAITING FOR HOST"
			if connected
			else "CONNECTING TO HOST..."
		)


func _update_camera(delta: float) -> void:
	var target := float(player_state.lean_direction) * LEAN_OFFSET
	_lean_vis_x = lerp(_lean_vis_x, target, clamp(LEAN_LERP_SPEED * delta, 0.0, 1.0))
	if cam:
		cam.offset = Vector2(_lean_vis_x, 0.0)


func _update_health_tint() -> void:
	if p1_placeholder:
		var g1: float = clamp(float(player_state.hp) / float(player_state.max_hp), 0.0, 1.0)
		p1_placeholder.modulate = Color(1.0, g1, g1, 1.0)

	if p2_placeholder:
		var g2: float = clamp(float(opponent_state.hp) / float(opponent_state.max_hp), 0.0, 1.0)
		p2_placeholder.modulate = Color(1.0, g2, g2, 1.0)


func _update_rollback_debug_hud() -> void:
	if rollback_session == null:
		return
	var diagnostics: Dictionary = rollback_session.get_diagnostics()

	if debug_tick_label:
		debug_tick_label.text = "LocalFrame=%d | PlayerID=%d | PredictionLead=%d | RollbackCount=%d" % [
			int(diagnostics["current_frame"]),
			local_player_id,
			int(diagnostics["prediction_lead"]),
			int(diagnostics["rollback_count"])
		]

	var mode_text := "ENet"
	if not USE_ENET:
		mode_text = "LatencyHarness"

	var connected := false
	if transport != null and transport.get("is_connected") != null:
		connected = bool(transport.get("is_connected"))

	if debug_replay_label:
		debug_replay_label.text = (
			"Mode=%s | Connected=%s | Bot=%s\n" +
			"Delay=%d | Jitter=%d | BenchmarkDone=%s\n" +
			"Packets=%d | LastRemoteInputFrame=%d | LastRemoteSimFrame=%d\n" +
			"RemoteConfirmedThrough=%d | PeerConfirmedLocalThrough=%d | FinalizedThrough=%d\n" +
			"RawFrameOffset=%.2f | FilteredFrameOffset=%.2f | SyncRTTFrames=%d | SyncSampleAgeFrames=%d\n" +
			"LocalFrameAdvantage=%.2f | SoftSyncActive=%s | AheadSamples=%d\n" +
			"SoftSyncYieldTicks=%d | SoftSyncYieldCooldown=%d\n" +
			"PredictionLead=%d | Max=%d | Limit=%d\n" +
			"LeadStalled=%s | StallTicks=%d\n" +
			"Redundant=%d | Recovered=%d | Duplicates=%d\n" +
			"Repair Req S/R=%d/%d | Resp S/R=%d/%d\n" +
			"Last Repair Requested=%d | Recovered=%d\n" +
			"ConfirmedThrough=%d | ConfirmationLag=%d | Missing=%d\n" +
			"OldestSnapshot=%d | HistoryExhausted=%s | Frame=%d\n" +
			"Rollback count=%d | Max depth=%d | Misses=%d\n" +
			"Checksum compared=%d | Mismatches=%d | First=%d"
		) % [
			mode_text,
			str(connected),
			str(QA_BOT_BENCHMARK_ENABLED),
			BENCHMARK_DELAY_FRAMES,
			BENCHMARK_JITTER_FRAMES,
			str(benchmark_complete),
			int(diagnostics["packets_received"]),
			int(diagnostics["last_remote_input_frame"]),
			int(diagnostics["last_remote_sim_frame"]),
			int(diagnostics["remote_confirmed_through"]),
			int(diagnostics["peer_confirmed_local_through"]),
			int(diagnostics["finalized_through"]),
			float(diagnostics["raw_estimated_frame_offset"]),
			float(diagnostics["filtered_estimated_frame_offset"]),
			int(diagnostics["last_sync_rtt_frames"]),
			int(diagnostics["last_sync_sample_age_frames"]),
			float(diagnostics["local_frame_advantage"]),
			str(diagnostics["soft_sync_active"]),
			int(diagnostics["soft_sync_ahead_samples"]),
			int(diagnostics["soft_sync_yield_ticks"]),
			int(diagnostics["soft_sync_yield_cooldown"]),
			int(diagnostics["prediction_lead"]),
			int(diagnostics["max_prediction_lead"]),
			int(diagnostics["prediction_lead_limit"]),
			str(diagnostics["lead_stalled"]),
			int(diagnostics["lead_stall_ticks"]),
			int(diagnostics["redundant_frames_received"]),
			int(diagnostics["recovered_missing_frames"]),
			int(diagnostics["duplicate_input_frames"]),
			int(diagnostics["repair_requests_sent"]),
			int(diagnostics["repair_requests_received"]),
			int(diagnostics["repair_responses_sent"]),
			int(diagnostics["repair_responses_received"]),
			int(diagnostics["last_repair_requested_frame"]),
			int(diagnostics["last_repair_recovered_frame"]),
			int(diagnostics["remote_confirmed_through"]),
			int(diagnostics["confirmation_lag"]),
			int(diagnostics["earliest_missing_remote_frame"]),
			int(diagnostics["oldest_retained_snapshot"]),
			str(diagnostics["history_exhausted"]),
			int(diagnostics["history_exhaustion_frame"]),
			int(diagnostics["rollback_count"]),
			int(diagnostics["max_rollback_depth"]),
			int(diagnostics["prediction_misses"]),
			int(diagnostics["checksum_frames_compared"]),
			int(diagnostics["checksum_mismatch_count"]),
			int(diagnostics["first_checksum_mismatch_frame"])
		]


func _update_combat_debug_hud() -> void:
	if debug_input_label:
		debug_input_label.text = "P1 block=%s active=%s hit=%s | P2 block=%s active=%s hit=%s" % [
			str(player_state.blocking),
			str(player_state.attack_active),
			str(player_state.hit_confirmed),
			str(opponent_state.blocking),
			str(opponent_state.attack_active),
			str(opponent_state.hit_confirmed)
		]


func _sprite_visual_debug(sprite: Node) -> Dictionary:
	if sprite != null and sprite.has_method("get_debug_visual_state"):
		return sprite.call("get_debug_visual_state")

	return {
		"mode": "unavailable",
		"frame": -1,
		"texture_size": Vector2.ZERO,
	}


func _update_visual_diagnostic_hud() -> void:
	if debug_pos_label == null:
		return

	var simulation_frame: int = -1
	var rollback_count: int = 0
	var prediction_lead: int = 0

	if rollback_session != null:
		var diagnostics: Dictionary = rollback_session.get_diagnostics()
		simulation_frame = int(diagnostics["current_frame"])
		rollback_count = int(diagnostics["rollback_count"])
		prediction_lead = int(diagnostics["prediction_lead"])

	var p1_rendered := (
		p1_placeholder.position
		if p1_placeholder != null
		else Vector2.ZERO
	)
	var p2_rendered := (
		p2_placeholder.position
		if p2_placeholder != null
		else Vector2.ZERO
	)
	var p1_visual: Dictionary = _sprite_visual_debug(p1_sprite_debug)
	var p2_visual: Dictionary = _sprite_visual_debug(p2_sprite_debug)
	var p1_texture_size: Vector2 = p1_visual.get("texture_size", Vector2.ZERO)
	var p2_texture_size: Vector2 = p2_visual.get("texture_size", Vector2.ZERO)
	var remote_state: PlayerState = _get_remote_fighter_state()
	var remote_placeholder: Node2D = _get_remote_fighter_placeholder()
	var remote_authoritative: Vector2 = (
		remote_state.position
		if remote_state != null
		else Vector2.ZERO
	)
	var remote_rendered: Vector2 = (
		remote_placeholder.position
		if remote_placeholder != null
		else Vector2.ZERO
	)

	debug_pos_label.text = (
		"SimulationFrame=%d | RenderFrameCount=%d | FPS=%d\n" +
		"PhysicsTicksSinceLastRender=%d | MaxPhysicsTicksSinceLastRender=%d\n" +
		"RollbackCount=%d | PredictionLead=%d\n" +
		"P1 Auth=(%.2f, %.2f) Node=(%.2f, %.2f) Delta=(%.2f, %.2f)\n" +
		"P1 Anim=%s Frame=%d Texture=(%.0f, %.0f)\n" +
		"P2 Auth=(%.2f, %.2f) Node=(%.2f, %.2f) Delta=(%.2f, %.2f)\n" +
		"P2 Anim=%s Frame=%d Texture=(%.0f, %.0f)\n" +
		"RenderCorrectionActive=%s | RenderCorrectionErrorX=%.2f | RenderCorrectionFramesRemaining=%d\n" +
		"RenderedPosition=(%.2f, %.2f) | AuthoritativePosition=(%.2f, %.2f)\n" +
		"CorrectionSnapCount=%d | CorrectionSmoothCount=%d\n" +
		"[Presentation Gate P1 Remote] AuthoritativeX=%.2f | RenderedX=%.2f | VisualErrorX=%.2f | MaxVisualErrorX=%.2f\n" +
		"RenderStepX=%.2f | AbsRenderStepX=%.2f | MaxRenderStepX=%.2f | P95RenderStepX=%.2f | Steps>10px=%d\n" +
		"AuthoritativeStepX=%.2f | MaxAuthoritativeStepX=%.2f\n" +
		"ThisRender Rollback=%s | Correction=%s | SoftYield=%s\n" +
		"LargeStep MultiTick=%d | Rollback=%d | Correction=%d | SoftYield=%d | Unclassified=%d"
	) % [
		simulation_frame,
		_presentation_render_frame_count,
		int(Engine.get_frames_per_second()),
		_last_render_physics_ticks,
		_presentation_max_physics_ticks_since_last_render,
		rollback_count,
		prediction_lead,
		player_state.position.x,
		player_state.position.y,
		p1_rendered.x,
		p1_rendered.y,
		player_state.position.x - p1_rendered.x,
		player_state.position.y - p1_rendered.y,
		str(p1_visual.get("mode", "unavailable")),
		int(p1_visual.get("frame", -1)),
		p1_texture_size.x,
		p1_texture_size.y,
		opponent_state.position.x,
		opponent_state.position.y,
		p2_rendered.x,
		p2_rendered.y,
		opponent_state.position.x - p2_rendered.x,
		opponent_state.position.y - p2_rendered.y,
		str(p2_visual.get("mode", "unavailable")),
		int(p2_visual.get("frame", -1)),
		p2_texture_size.x,
		p2_texture_size.y,
		str(_remote_render_correction_active),
		_remote_render_correction_error.x,
		_remote_render_correction_frames_remaining,
		remote_rendered.x,
		remote_rendered.y,
		remote_authoritative.x,
		remote_authoritative.y,
		_remote_render_correction_snap_count,
		_remote_render_correction_smooth_count,
		_presentation_authoritative_x,
		_presentation_rendered_x,
		_presentation_render_visual_error_x,
		_presentation_max_abs_render_visual_error_x,
		_presentation_render_step_x,
		_presentation_abs_render_step_x,
		_presentation_max_abs_render_step_x,
		_presentation_cached_p95_abs_render_step,
		_presentation_steps_over_10_px,
		_presentation_authoritative_step_x,
		_presentation_max_abs_authoritative_step_x,
		str(_presentation_rollback_this_render),
		str(_presentation_render_correction_this_render),
		str(_presentation_soft_sync_yield_this_render),
		_presentation_large_step_with_multi_physics_tick,
		_presentation_large_step_with_rollback,
		_presentation_large_step_with_render_correction,
		_presentation_large_step_with_soft_sync_yield,
		_presentation_large_step_unclassified,
	]


func _state_name(state: int) -> String:
	match state:
		PlayerState.MoveState.IDLE:
			return "IDLE"
		PlayerState.MoveState.STARTUP:
			return "STARTUP"
		PlayerState.MoveState.ACTIVE:
			return "ACTIVE"
		PlayerState.MoveState.RECOVERY:
			return "RECOVERY"
		PlayerState.MoveState.BLOCK:
			return "BLOCK"
		PlayerState.MoveState.DODGE:
			return "DODGE"
		PlayerState.MoveState.HURT:
			return "HURT"
		PlayerState.MoveState.DEAD:
			return "DEAD"
		_:
			return "UNKNOWN"


func _attack_name(kind: int) -> String:
	match kind:
		PlayerState.AttackKind.NONE:
			return "NONE"
		PlayerState.AttackKind.LIGHT:
			return "LIGHT"
		PlayerState.AttackKind.HEAVY:
			return "HEAVY"
		_:
			return "UNKNOWN"


func _ensure_opponent_placeholder() -> void:
	if p2_placeholder == null and p1_placeholder != null:
		p2_placeholder = p1_placeholder.duplicate()
		p2_placeholder.name = "OpponentPlaceholder"
		add_child(p2_placeholder)


func _bind_sprite_to_state(placeholder: Node, state: Node, label: String) -> Node:
	if placeholder == null or state == null:
		return null

	var sprite: Node = placeholder.find_child("PlayerSpriteDebug", true, false)

	if sprite == null:
		var stack: Array[Node] = [placeholder]

		while stack.size() > 0 and sprite == null:
			var n: Node = stack.pop_back()

			if n != null and n.has_method("bind_state"):
				sprite = n
				break

			for c in n.get_children():
				if c is Node:
					stack.append(c)

	if sprite == null:
		return null

	if sprite.get("debug_label") != null:
		sprite.set("debug_label", label)

	sprite.call("bind_state", state)
	return sprite


func _on_start_match_received() -> void:
	if rollback_session == null:
		return

	if bool(rollback_session.match_started):
		print("[Arena] Duplicate start_match ignored.")
		return

	print("[Arena] start_match received. Starting rollback session.")
	_clear_remote_render_correction()
	_remote_render_correction_snap_count = 0
	_remote_render_correction_smooth_count = 0
	rollback_session.start_session()
	if _benchmark_enabled():
		_start_benchmark_timer()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key_event: InputEventKey = event
		if key_event.pressed and not key_event.echo:
			if key_event.keycode == KEY_F2:
				_reset_presentation_measurement()
				get_viewport().set_input_as_handled()
				return
			if key_event.keycode == KEY_F3:
				_print_presentation_measurement_report()
				get_viewport().set_input_as_handled()
				return

	if event.is_action_pressed("ui_accept"):
		if transport != null and transport.has_method("send_start_match"):
			if not bool(transport.get("is_host")):
				return

			if rollback_session != null and bool(rollback_session.match_started):
				return

			print("[Arena] Host requesting start_match.")
			transport.send_start_match()
