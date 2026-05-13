extends Node2D

# ArenaScene.gd — ENet rollback fighter arena + deterministic QA bot benchmark

# -------------------------------------------------
# Machine config
# DESKTOP:
#   ENET_HOST := true
#   ENET_IP := "127.0.0.1"
#
# LAPTOP:
#   ENET_HOST := false
#   ENET_IP := "DESKTOP_IPV4_HERE"
# -------------------------------------------------
const USE_ENET := true
const ENET_HOST := true
const ENET_IP := "127.0.0.1"
const ENET_PORT := 7777

# -------------------------------------------------
# Benchmark config
# false = human keyboard play
# true  = deterministic bot benchmark
# -------------------------------------------------
const USE_BOT_INPUT := true
const BENCHMARK_DURATION_FRAMES := 3600 # 60 seconds at 60fps

# Set these on BOTH computers before each test:
# 0  = baseline LAN
# 6  = ~100ms
# 9  = ~150ms
# 12 = ~200ms
const BENCHMARK_DELAY_FRAMES := 12
const BENCHMARK_JITTER_FRAMES := 0

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

@onready var cam: Camera2D = get_node_or_null("Camera2D")
@onready var p1_placeholder: Node2D = get_node_or_null("PlayerPlaceholder")
@onready var p2_placeholder: Node2D = get_node_or_null("OpponentPlaceholder")
@onready var hud: Node = get_node_or_null("HUD")

@onready var debug_hud_root: Control = get_node_or_null("DebugHUD/Control")
@onready var debug_tick_label: Label = debug_hud_root.get_node("MarginContainer/VBoxContainer/TickLabel") if debug_hud_root else null
@onready var debug_pos_label: Label = debug_hud_root.get_node("MarginContainer/VBoxContainer/PosLabel") if debug_hud_root else null
@onready var debug_input_label: Label = debug_hud_root.get_node("MarginContainer/VBoxContainer/InputLabel") if debug_hud_root else null
@onready var debug_replay_label: Label = debug_hud_root.get_node("MarginContainer/VBoxContainer/ReplayLabel") if debug_hud_root else null

const LEAN_OFFSET := 14.0
const LEAN_LERP_SPEED := 10.0
var _lean_vis_x: float = 0.0


func _ready() -> void:
	print("[Arena] _ready")

	add_child(player_state)
	add_child(opponent_state)
	add_child(input_system)
	add_child(lean_system)
	add_child(combat_system)

	player_state.position = Vector2(200, 250)
	opponent_state.position = Vector2(600, 250)

	_ensure_opponent_placeholder()
	_bind_sprite_to_state(p1_placeholder, player_state, "P1")
	_bind_sprite_to_state(p2_placeholder, opponent_state, "P2")

	lean_system.player_state = player_state
	combat_system.p1_state = player_state
	combat_system.p2_state = opponent_state

	add_child(adapter)
	adapter.setup(player_state, opponent_state, input_system, lean_system, combat_system)

	if USE_ENET:
		transport = ENetTransportScene.new()
		transport.artificial_delay_frames = BENCHMARK_DELAY_FRAMES
		transport.artificial_jitter_frames = BENCHMARK_JITTER_FRAMES
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

	if hud:
		hud.set("p1_state", player_state)
		hud.set("p2_state", opponent_state)

	if transport != null and transport.has_signal("start_match_received"):
		if not transport.start_match_received.is_connected(_on_start_match_received):
			transport.start_match_received.connect(_on_start_match_received)

	print("[Arena] Benchmark config | bot=%s delay=%d jitter=%d duration=%d" % [
		str(USE_BOT_INPUT),
		BENCHMARK_DELAY_FRAMES,
		BENCHMARK_JITTER_FRAMES,
		BENCHMARK_DURATION_FRAMES
	])


func _physics_process(delta: float) -> void:
	_update_wall_state()

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


func _collect_local_input() -> Dictionary:
	if USE_BOT_INPUT:
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

	var phase_60: int = int(f / 60) % 4
	var mx: float = 0.0

	# P1 and P2 use mirrored patterns so they approach/retreat from each other.
	if local_player_id == 1:
		match phase_60:
			0:
				mx = 1.0
			1:
				mx = -1.0
			2:
				mx = 1.0
			_:
				mx = 0.0
	else:
		match phase_60:
			0:
				mx = -1.0
			1:
				mx = 1.0
			2:
				mx = -1.0
			_:
				mx = 0.0

	return {
		"mx": mx,
		"lean_l": false,
		"lean_r": false,
		"atk_l": f % 45 == 0,
		"atk_h": f % 120 == 0,
		"block": f % 90 < 20,
		"dodge": f % 150 == 0,
	}


func _start_benchmark_timer() -> void:
	benchmark_running = true
	benchmark_complete = false
	benchmark_start_frame = int(rollback_session.current_frame) if rollback_session != null else 0

	print("[Benchmark] START | player_id=%d delay=%d jitter=%d bot=%s duration=%d" % [
		local_player_id,
		BENCHMARK_DELAY_FRAMES,
		BENCHMARK_JITTER_FRAMES,
		str(USE_BOT_INPUT),
		BENCHMARK_DURATION_FRAMES
	])


func _check_benchmark_complete() -> void:
	if rollback_session == null:
		return

	var elapsed_frames: int = int(rollback_session.current_frame) - benchmark_start_frame

	if elapsed_frames >= BENCHMARK_DURATION_FRAMES:
		benchmark_running = false
		benchmark_complete = true
		_print_benchmark_results()


func _frame_gap() -> int:
	if rollback_session == null:
		return 0

	var last_remote := int(rollback_session.last_remote_frame)
	if last_remote < 0:
		return 0

	return int(rollback_session.current_frame) - last_remote


func _print_benchmark_results() -> void:
	if rollback_session == null:
		return

	print("")
	print("========== ROLLBACK BENCHMARK RESULT ==========")
	print("PlayerID: %d" % local_player_id)
	print("Mode: %s" % ("ENet" if USE_ENET else "LatencyHarness"))
	print("BotInput: %s" % str(USE_BOT_INPUT))
	print("DelayFrames: %d" % BENCHMARK_DELAY_FRAMES)
	print("JitterFrames: %d" % BENCHMARK_JITTER_FRAMES)
	print("DurationFrames: %d" % BENCHMARK_DURATION_FRAMES)
	print("Packets: %d" % int(rollback_session.packets_received))
	print("LastRemoteFrame: %d" % int(rollback_session.last_remote_frame))
	print("LocalFrame: %d" % int(rollback_session.current_frame))
	print("FrameGap: %d" % _frame_gap())
	print("RollbackCount: %d" % int(rollback_session.rollback_count))
	print("MaxRollbackDepth: %d" % int(rollback_session.max_rollback_depth))
	print("PredictionMisses: %d" % int(rollback_session.prediction_misses))
	print("ChecksumMismatch: NOT_IMPLEMENTED")
	print("===============================================")
	print("")


func _update_wall_state() -> void:
	player_state.set_touching_wall(
		player_state.position.x <= 0.0
		or player_state.position.x >= 800.0
		or player_state.position.y <= 0.0
		or player_state.position.y >= 400.0
	)

	opponent_state.set_touching_wall(
		opponent_state.position.x <= 0.0
		or opponent_state.position.x >= 800.0
		or opponent_state.position.y <= 0.0
		or opponent_state.position.y >= 400.0
	)


func _update_visuals() -> void:
	if p1_placeholder:
		p1_placeholder.position = player_state.position
	if p2_placeholder:
		p2_placeholder.position = opponent_state.position


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

	if debug_tick_label:
		debug_tick_label.text = "Frame: %d | Player ID: %d | Gap: %d" % [
			int(rollback_session.current_frame),
			local_player_id,
			_frame_gap()
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
			"Packets=%d | LastRemoteFrame=%d | Gap=%d\n" +
			"Rollback count=%d | Max depth=%d | Misses=%d"
		) % [
			mode_text,
			str(connected),
			str(USE_BOT_INPUT),
			BENCHMARK_DELAY_FRAMES,
			BENCHMARK_JITTER_FRAMES,
			str(benchmark_complete),
			int(rollback_session.packets_received),
			int(rollback_session.last_remote_frame),
			_frame_gap(),
			int(rollback_session.rollback_count),
			int(rollback_session.max_rollback_depth),
			int(rollback_session.prediction_misses)
		]


func _update_combat_debug_hud() -> void:
	if debug_pos_label:
		debug_pos_label.text = "P1 state=%s frames=%d atk=%s hp=%d\nP2 state=%s frames=%d atk=%s hp=%d" % [
			_state_name(player_state.state),
			player_state.frames_left,
			_attack_name(player_state.attack_kind),
			player_state.hp,
			_state_name(opponent_state.state),
			opponent_state.frames_left,
			_attack_name(opponent_state.attack_kind),
			opponent_state.hp
		]

	if debug_input_label:
		debug_input_label.text = "P1 block=%s active=%s hit=%s | P2 block=%s active=%s hit=%s" % [
			str(player_state.blocking),
			str(player_state.attack_active),
			str(player_state.hit_confirmed),
			str(opponent_state.blocking),
			str(opponent_state.attack_active),
			str(opponent_state.hit_confirmed)
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


func _bind_sprite_to_state(placeholder: Node, state: Node, label: String) -> void:
	if placeholder == null or state == null:
		return

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
		return

	if sprite.get("debug_label") != null:
		sprite.set("debug_label", label)

	sprite.call("bind_state", state)


func _on_start_match_received() -> void:
	print("[Arena] start_match received. Starting rollback session.")

	if rollback_session != null:
		rollback_session.start_session()
		_start_benchmark_timer()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept"):
		if transport != null and transport.has_method("send_start_match"):
			print("[Arena] Host sending start_match.")

			if rollback_session != null:
				rollback_session.start_session()
				_start_benchmark_timer()

			transport.send_start_match()
