extends Node2D

# ArenaScene.gd — ENet rollback fighter arena + deterministic QA bot benchmark

const DEFAULT_ENET_IP := "127.0.0.1"
const DEFAULT_ENET_PORT := 7777

# -------------------------------------------------
# Benchmark config
# -------------------------------------------------

# Controlled deterministic single-jab QA benchmark
const QA_BOT_BENCHMARK_ENABLED := false
const BENCHMARK_DURATION_FRAMES := 3600 # 60 seconds at 60fps

# Scripted stress benchmark
const QA_STRESS_BENCHMARK_ENABLED := false
const QA_STRESS_FORCE_PACKET_LOSS := false
const STRESS_SCHEDULE_FRAMES := 7200
const STRESS_DRAIN_FRAMES := 120


const STRESS_TOTAL_FRAMES := STRESS_SCHEDULE_FRAMES + STRESS_DRAIN_FRAMES
const STRESS_CYCLE_FRAMES := 1200

# Deterministic combat-fuzz benchmark
const QA_COMBAT_FUZZ_BENCHMARK_ENABLED := false
const QA_COMBAT_FUZZ_SEED := 0xC0FFEE
const QA_COMBAT_FUZZ_STOP_AFTER_FRAME := -1
const COMBAT_FUZZ_DURATION_FRAMES := 7200
const COMBAT_FUZZ_DRAIN_FRAMES := 120
const COMBAT_FUZZ_TOTAL_FRAMES := (
	COMBAT_FUZZ_DURATION_FRAMES + COMBAT_FUZZ_DRAIN_FRAMES
)
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
const CombatFuzzBenchmarkScript = preload(
	"res://games/rollback_fighter/scripts/qa/CombatFuzzBenchmark.gd"
)
const CharacterDefinitionLoaderScript = preload(
	"res://games/rollback_fighter/scripts/config/CharacterDefinitionLoader.gd"
)
const FighterProviderScript = preload(
	"res://games/rollback_fighter/scripts/config/ImportedFighterProvider.gd"
)
const CanonicalConfigWriterScript = preload(
	"res://games/rollback_fighter/scripts/config/CanonicalConfigWriter.gd"
)
const MatchConfigHandshakeScript = preload(
	"res://games/rollback_fighter/scripts/config/MatchConfigHandshake.gd"
)
const SimpleFighterCPUScript = preload(
	"res://games/rollback_fighter/scripts/ai/SimpleFighterCPU.gd"
)
const ProjectPresentationRuntimeScript = preload(
	"res://games/rollback_fighter/scripts/projects/ProjectPresentationRuntime.gd"
)
const ProjectPresentationResolverScript = preload(
	"res://games/rollback_fighter/scripts/projects/ProjectPresentationResolver.gd"
)
const ProjectMultiplayerIdentityScript = preload(
	"res://games/rollback_fighter/scripts/projects/GameProjectMultiplayerIdentity.gd"
)
const PROJECT_DETAIL_SCENE_PATH := "res://games/rollback_fighter/scenes/ProjectDetail.tscn"
const SINGLE_PLAYER_PHYS_DT := 1.0 / 60.0

const CHARACTER_REGISTRY_PATH := \
	"res://games/rollback_fighter/config/builtin_fighters.json"
const GAME_RULES_CONFIG_PATH := \
	"res://games/rollback_fighter/config/game_rules.json"
const P1_FIGHTER_ID := "example_fighter"
const P2_FIGHTER_ID := "example_fighter_alt"
enum MatchLifecycle { SETUP, WAITING_FOR_PEER, READY, PLAYING, FINISHED }


var rollback_session: Node = null
var transport: Node = null
var local_player_id: int = 1
var _game_rules_definition: RollbackFighterGameRulesDefinition = null
var _p1_character_definition: RollbackFighterCharacterDefinition = null
var _p2_character_definition: RollbackFighterCharacterDefinition = null
var _match_config_handshake: RollbackFighterMatchConfigHandshake = (
	MatchConfigHandshakeScript.new()
)
var _local_match_config_identity: Dictionary = {}
var _config_handshake_sent: bool = false
var _remote_config_identity_received: bool = false
var _pending_start_match_received: bool = false
var _use_enet: bool = true
var _is_host: bool = true
var _enet_address: String = DEFAULT_ENET_IP
var _enet_port: int = DEFAULT_ENET_PORT
var _connection_failure_message: String = ""
var _return_menu_button: Button = null
var _host_start_button: Button = null
var _mobile_controls: Control = null
var _touch_left_held: bool = false
var _touch_right_held: bool = false
var _touch_block_held: bool = false
var _touch_light_pending: bool = false
var _touch_heavy_pending: bool = false
var _touch_dodge_pending: bool = false
var _returning_to_menu: bool = false
var _single_player_mode: bool = false
var _single_player_started: bool = false
var _single_player_frame: int = 0
var _single_player_cpu: RefCounted = null
var _match_mode: String = ""
var _p1_fighter_id: String = P1_FIGHTER_ID
var _p2_fighter_id: String = P2_FIGHTER_ID
var _match_lifecycle: MatchLifecycle = MatchLifecycle.SETUP
var _fighter_selection_sent: bool = false
var _fighter_selection_received: bool = false
var _fighter_selection_acknowledged: bool = false
var _result_overlay: Control = null
var _result_title: Label = null
var _result_shown: bool = false
var _project_presentation_runtime: RollbackFighterProjectPresentationRuntime = null
var _local_project_identity: Dictionary = {}
var _project_identity_sent: bool = false
var _project_response_received: bool = false

var benchmark_running: bool = false
var benchmark_complete: bool = false
var benchmark_start_frame: int = 0
var p1_sprite_debug: Node = null
var p2_sprite_debug: Node = null
var _tuning_panel: Control = null
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

const CAMERA_FIXED_Y := 200.0
const CAMERA_FOLLOW_SPEED := 8.0
const CAMERA_FIXED_ZOOM := 1.25
const CAMERA_LEFT_SAFE_RATIO := 0.25
const CAMERA_RIGHT_SAFE_RATIO := 0.75
const HURTBOX_FILL_COLOR := Color(0.15, 0.45, 1.0, 0.22)
const HURTBOX_LINE_COLOR := Color(0.25, 0.65, 1.0, 0.95)
const HITBOX_FILL_COLOR := Color(1.0, 0.1, 0.1, 0.28)
const HITBOX_LINE_COLOR := Color(1.0, 0.2, 0.2, 1.0)
const RENDER_CORRECTION_MAX_DISTANCE := 18.0
const RENDER_CORRECTION_FRAMES := 3
const PRESENTATION_STEP_SAMPLE_CAPACITY := 4096
const PRESENTATION_LARGE_STEP_THRESHOLD := 10.0

@export var show_runtime_combat_boxes: bool = true

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
	if OS.is_debug_build():
		print("[Arena] _ready")
	_configure_network_launch()
	_setup_project_presentation()
	_create_return_menu_button()
	_create_host_start_button()
	_create_result_overlay()
	if not _connection_failure_message.is_empty():
		_set_connection_status(
			"Please launch from the Main Menu.\nPress Main Menu to return."
			if _connection_failure_message == "Please launch from the Main Menu."
			else "Connection settings are invalid.\nPress Main Menu to return."
		)
		set_physics_process(false)
		return
	_setup_tuning_panel()
	_setup_mobile_controls()
	if not _load_authoritative_fighter_definitions():
		push_error(
			"[CharacterDefinition] Match setup stopped: "
			+ "authoritative fighter definitions failed to load."
		)
		if play_status_label != null:
			play_status_label.text = (
				"Fighter not installed on both devices."
				if _has_imported_fighter_selection()
				else "CHARACTER CONFIG ERROR"
			)
		set_physics_process(false)
		return

	player_state.configure_character_definition(_p1_character_definition)
	opponent_state.configure_character_definition(_p2_character_definition)
	combat_system.configure_character_definitions(
		_p1_character_definition,
		_p2_character_definition,
		_game_rules_definition
	)

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

	player_state.position = Vector2(
		_game_rules_definition.get_spawn_position("p1")
	)
	opponent_state.position = Vector2(
		_game_rules_definition.get_spawn_position("p2")
	)

	_ensure_opponent_placeholder()
	p1_sprite_debug = _bind_sprite_to_state(
		p1_placeholder,
		player_state,
		_p1_character_definition,
		"P1"
	)
	p2_sprite_debug = _bind_sprite_to_state(
		p2_placeholder,
		opponent_state,
		_p2_character_definition,
		"P2"
	)

	if not RenderingServer.frame_pre_draw.is_connected(_on_frame_pre_draw):
		RenderingServer.frame_pre_draw.connect(_on_frame_pre_draw)

	lean_system.player_state = player_state
	combat_system.p1_state = player_state
	combat_system.p2_state = opponent_state

	add_child(adapter)
	adapter.setup(
		player_state,
		opponent_state,
		input_system,
		lean_system,
		combat_system,
		_game_rules_definition
	)

	if _single_player_mode:
		_single_player_cpu = SimpleFighterCPUScript.new()
		_single_player_frame = 0
		_single_player_started = true
		_match_lifecycle = MatchLifecycle.PLAYING
		local_player_id = 1
		_set_connection_status("P1 vs CPU")
		if OS.is_debug_build():
			print("[Arena] Single Player mode | P1=human | P2=deterministic CPU")
	else:
		if _use_enet:
			transport = ENetTransportScene.new()
			transport.name = "ENetTransport"
			transport.artificial_delay_frames = (
				BENCHMARK_DELAY_FRAMES if OS.is_debug_build() else 0
			)
			transport.artificial_jitter_frames = (
				BENCHMARK_JITTER_FRAMES if OS.is_debug_build() else 0
			)
			transport.deterministic_stress_input_loss_enabled = OS.is_debug_build() and (
				(QA_STRESS_BENCHMARK_ENABLED or QA_COMBAT_FUZZ_BENCHMARK_ENABLED)
				and QA_STRESS_FORCE_PACKET_LOSS
			)
			add_child(transport)
			_connect_transport_signals()
			if _is_host:
				local_player_id = 1
				transport.host(_enet_port)
				if OS.is_debug_build():
					print("[Arena] ENet HOST mode | player_id=1 | port=%d" % _enet_port)
			else:
				local_player_id = 2
				transport.join(_enet_address, _enet_port)
				if OS.is_debug_build():
					print("[Arena] ENet CLIENT mode | player_id=2 | joining %s:%d" % [_enet_address, _enet_port])
		else:
			_match_lifecycle = MatchLifecycle.WAITING_FOR_PEER
			transport = LatencyHarnessTransportScene.new()
			transport.delay_frames = BENCHMARK_DELAY_FRAMES
			add_child(transport)
			local_player_id = 1
			if OS.is_debug_build():
				print("[Arena] LatencyHarness mode | player_id=1")

		rollback_session = RollbackNetworkSessionScene.new()
		add_child(rollback_session)
		rollback_session.setup(adapter, transport, local_player_id)
		rollback_session.input_delay_frames = (
			BENCHMARK_INPUT_DELAY_FRAMES if OS.is_debug_build() else 0
		)
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
	if _use_enet and transport != null:
		if transport.has_signal("match_config_received"):
			if not transport.match_config_received.is_connected(
				_on_match_config_received
			):
				transport.match_config_received.connect(
					_on_match_config_received
				)
		_begin_config_handshake()

	var enabled_benchmark_count: int = (int(OS.is_debug_build()) * (
		int(QA_BOT_BENCHMARK_ENABLED)
		+ int(QA_STRESS_BENCHMARK_ENABLED)
		+ int(QA_COMBAT_FUZZ_BENCHMARK_ENABLED)
	))
	if enabled_benchmark_count > 1:
		push_error("[Arena] Enable only one QA benchmark mode at a time.")

	if OS.is_debug_build():
		print("[Arena] Benchmark config | mode=%s delay=%d jitter=%d duration=%d" % [
			_benchmark_mode_name(),
			BENCHMARK_DELAY_FRAMES,
			BENCHMARK_JITTER_FRAMES,
			_benchmark_duration_frames()
		])
		_reset_presentation_measurement(false)


func _setup_tuning_panel() -> void:
	if OS.get_name() == "Android" or not OS.is_debug_build():
		return
	var tuning_panel_script: Script = load(
		"res://games/rollback_fighter/scripts/ui/FighterTuningPanel.gd"
	) as Script
	if tuning_panel_script == null:
		push_warning("[TuningUI] Could not load the desktop tuning panel script.")
		return
	_tuning_panel = tuning_panel_script.new()
	_tuning_panel.name = "FighterTuningPanel"
	_tuning_panel.reload_requested.connect(_on_tuning_reload_requested)
	add_child(_tuning_panel)
	_tuning_panel.call("configure", CHARACTER_REGISTRY_PATH, _use_enet)


func _on_tuning_reload_requested() -> void:
	if _use_enet:
		return
	if _single_player_mode:
		var launch_config: Node = get_node_or_null("/root/NetworkLaunchConfig")
		if launch_config != null:
			launch_config.call("set_single_player")
	get_tree().root.set_meta("tuning_ui_reload_pending", true)
	get_tree().call_deferred("reload_current_scene")


func _load_authoritative_fighter_definitions() -> bool:
	var loader: RollbackFighterCharacterDefinitionLoader = CharacterDefinitionLoaderScript.new()
	var fighter_provider: RollbackFighterImportedFighterProvider = FighterProviderScript.new()
	var rules_result: Dictionary = loader.load_game_rules(
		GAME_RULES_CONFIG_PATH
	)
	var p1_result: Dictionary = fighter_provider.load_fighter(_p1_fighter_id)
	var p2_result: Dictionary = fighter_provider.load_fighter(_p2_fighter_id)

	var errors: Array = []
	if not bool(rules_result.get("ok", false)):
		errors.append_array(rules_result.get("errors", []))
	if not bool(p1_result.get("ok", false)):
		errors.append_array(p1_result.get("errors", []))
	if not bool(p2_result.get("ok", false)):
		errors.append_array(p2_result.get("errors", []))

	if not errors.is_empty():
		push_error(
			"[CharacterDefinition] AUTHORITATIVE FIGHTER LOAD FAILED "
			+ "(%d error(s))." % errors.size()
		)
		for error_variant in errors:
			if OS.is_debug_build():
				print(loader.format_error(error_variant))
		return false

	_game_rules_definition = rules_result["definition"]
	_p1_character_definition = p1_result["definition"]
	_p2_character_definition = p2_result["definition"]
	var writer: RollbackFighterCanonicalConfigWriter = (
		CanonicalConfigWriterScript.new()
	)
	_local_match_config_identity = _match_config_handshake.build_local_identity(
		writer,
		_game_rules_definition,
		_p1_character_definition,
		_p2_character_definition
	)
	_match_config_handshake.local_identity = (
		_local_match_config_identity.duplicate(true)
	)
	if _is_host and _match_config_handshake.project_required:
		var project_context: Node = get_node_or_null("/root/GameProjectLaunchConfig")
		var project_id := str(project_context.call("get_project_id")) if project_context != null else ""
		var project_identity_result := ProjectMultiplayerIdentityScript.new().build(project_id, true)
		if not bool(project_identity_result.get("ok", false)):
			_connection_failure_message = str(project_identity_result.get("message", "Project changed — rebuild before hosting."))
			return false
		_local_project_identity = project_identity_result["identity"]
	var canonical_byte_length: int = int(
		_local_match_config_identity["canonical_byte_length"]
	)
	var digest: String = str(_local_match_config_identity["digest"])
	if OS.is_debug_build():
		print("[ConfigHandshake] local digest ready")
		print("protocol_version=%d rules_config_version=%d p1_config_version=%d p2_config_version=%d" % [
			int(_local_match_config_identity["protocol_version"]),
			int(_local_match_config_identity["rules_config_version"]),
			int(_local_match_config_identity["p1_config_version"]),
			int(_local_match_config_identity["p2_config_version"]),
		])
		print("digest=%s" % digest)
		print("p1=%s" % str(_local_match_config_identity["p1_id"]))
		print("p2=%s" % str(_local_match_config_identity["p2_id"]))
		print("[CharacterDefinition] authoritative fighter mode active")
		_print_fighter_definition_summary("P1", _p1_character_definition)
		_print_fighter_definition_summary("P2", _p2_character_definition)
		_print_presentation_summary(_p1_character_definition)
		_print_presentation_summary(_p2_character_definition)
		_print_game_rules_summary(_game_rules_definition)
		_print_match_definitions_summary(
			_p1_character_definition,
			_p2_character_definition,
			canonical_byte_length,
			digest
		)
		print("attacks:")
		print("light=%s" % _attack_definition_summary(
			_p1_character_definition.get_move_for_slot("light")
		))
		print("heavy=%s" % _attack_definition_summary(
			_p1_character_definition.get_move_for_slot("heavy")
		))
		print("config_version=%d" % _p1_character_definition.get_config_version())
		print("canonical_byte_length=%d" % canonical_byte_length)
		print("auth_digest=%s" % digest)
		print("[ConfigParity]")
		print("platform=%s" % OS.get_name())
		print("p1=%s" % _p1_character_definition.get_id())
		print("p2=%s" % _p2_character_definition.get_id())
		print("canonical_byte_length=%d" % canonical_byte_length)
		print("auth_digest=%s" % digest)
		print("normalized_authoritative_config_p1:\n%s" % writer.normalized_dump(
			_game_rules_definition,
			_p1_character_definition
		))
		print("normalized_authoritative_config_p2:\n%s" % writer.normalized_dump(
			_game_rules_definition,
			_p2_character_definition
		))
	else:
		print("[Arena] Fighter and game configuration validated.")
	var root_window: Window = get_tree().root
	if root_window.has_meta("tuning_ui_reload_pending"):
		root_window.remove_meta("tuning_ui_reload_pending")
		print("[TuningUI] config reloaded")
		print("new_digest=%s" % digest)
	return true


func _on_transport_connected() -> void:
	_connection_failure_message = ""
	if _is_host and int(transport.get("remote_peer_id")) > 0:
		if _match_config_handshake.project_required:
			_set_connection_status("Player connected.\nVerifying game project...")
			_send_host_project_identity()
		else:
			_set_connection_status("Player connected.\nSending fighter selection...")
			_send_host_fighter_selection()
	elif not _is_host:
		_set_connection_status("Connected.\nWaiting for host fighter selection...")


func _has_imported_fighter_selection() -> bool:
	var registry_file: FileAccess = FileAccess.open(CHARACTER_REGISTRY_PATH, FileAccess.READ)
	if registry_file == null:
		return true
	var parsed: Variant = JSON.parse_string(registry_file.get_as_text())
	registry_file.close()
	if not parsed is Dictionary:
		return true
	var fighters_value: Variant = Dictionary(parsed).get("fighters", {})
	if not fighters_value is Dictionary:
		return true
	var fighters: Dictionary = fighters_value
	return not fighters.has(_p1_fighter_id) or not fighters.has(_p2_fighter_id)


func _configure_network_launch() -> void:
	var launch_config: Node = get_node_or_null("/root/NetworkLaunchConfig")
	var launch: Dictionary = {}
	if launch_config != null:
		launch = launch_config.call("consume")
	if not launch.is_empty():
		_use_enet = true
		var mode: String = str(launch.get("mode", ""))
		_p1_fighter_id = str(launch.get("p1_fighter_id", P1_FIGHTER_ID))
		_p2_fighter_id = str(launch.get("p2_fighter_id", P2_FIGHTER_ID))
		if mode == "single_player":
			_match_mode = mode
			_single_player_mode = true
			_use_enet = false
			_is_host = false
			_set_connection_status("P1 vs CPU")
			return
		if mode != "host" and mode != "client":
			_connection_failure_message = "Invalid network launch mode."
			return
		_is_host = mode == "host"
		_match_mode = mode
		_enet_address = str(launch.get("address", ""))
		_enet_port = int(launch.get("port", 0))
		var project_context: Node = get_node_or_null("/root/GameProjectLaunchConfig")
		var project_network_match := project_context != null and bool(project_context.call("is_network_project"))
		_match_config_handshake.set_project_verification(project_network_match, false)
		if _enet_port < 1 or _enet_port > 65535 or (not _is_host and _enet_address.is_empty()):
			_connection_failure_message = "Invalid network launch settings."
			_use_enet = false
			return
		_set_connection_status(
			"Hosting on port %d\nWaiting for player..." % _enet_port
			if _is_host
			else "Connecting to %s:%d..." % [_enet_address, _enet_port]
		)
		return
	_match_mode = "debug"
	_p1_fighter_id = P1_FIGHTER_ID
	_p2_fighter_id = P2_FIGHTER_ID
	# Running FighterArena.tscn directly is the legacy/default local game. Project
	# context is optional and must never be inherited by an unrelated direct run.
	var creator_context: Node = get_node_or_null("/root/CreatorLaunchContext")
	if creator_context != null:
		creator_context.call("launch_global")
	var project_context: Node = get_node_or_null("/root/GameProjectLaunchConfig")
	if project_context != null:
		project_context.call("clear")
	_match_mode = "single_player"
	_single_player_mode = true
	_use_enet = false
	_is_host = false
	_set_connection_status("P1 vs CPU")


func _connect_transport_signals() -> void:
	if transport == null:
		return
	if transport.has_signal("connected") and not transport.connected.is_connected(_on_transport_connected):
		transport.connected.connect(_on_transport_connected)
	if transport.has_signal("connection_failed") and not transport.connection_failed.is_connected(_on_transport_connection_failed):
		transport.connection_failed.connect(_on_transport_connection_failed)
	if transport.has_signal("disconnected") and not transport.disconnected.is_connected(_on_transport_disconnected):
		transport.disconnected.connect(_on_transport_disconnected)
	if transport.has_signal("match_config_received") and not transport.match_config_received.is_connected(_on_match_config_received):
		transport.match_config_received.connect(_on_match_config_received)
	if transport.has_signal("match_selection_received") and not transport.match_selection_received.is_connected(_on_match_selection_received):
		transport.match_selection_received.connect(_on_match_selection_received)
	if transport.has_signal("match_selection_ack_received") and not transport.match_selection_ack_received.is_connected(_on_match_selection_ack_received):
		transport.match_selection_ack_received.connect(_on_match_selection_ack_received)
	if transport.has_signal("project_config_received") and not transport.project_config_received.is_connected(_on_project_config_received):
		transport.project_config_received.connect(_on_project_config_received)
	if transport.has_signal("project_config_response_received") and not transport.project_config_response_received.is_connected(_on_project_config_response):
		transport.project_config_response_received.connect(_on_project_config_response)
	if transport.has_signal("start_match_received") and not transport.start_match_received.is_connected(_on_start_match_received):
		transport.start_match_received.connect(_on_start_match_received)


func _create_return_menu_button() -> void:
	if hud == null:
		return
	_return_menu_button = Button.new()
	_return_menu_button.name = "ReturnToMenuButton"
	_return_menu_button.text = "Back to Project" if _has_project_launch() else "Main Menu"
	_return_menu_button.custom_minimum_size = Vector2(120.0, 48.0)
	_return_menu_button.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_return_menu_button.offset_left = -136.0
	_return_menu_button.offset_top = -60.0
	_return_menu_button.offset_right = -16.0
	_return_menu_button.offset_bottom = -12.0
	_return_menu_button.pressed.connect(_return_to_main_menu)
	hud.add_child(_return_menu_button)


func _create_host_start_button() -> void:
	if hud == null:
		return
	_host_start_button = Button.new()
	_host_start_button.name = "HostStartMatchButton"
	_host_start_button.text = "START MATCH"
	_host_start_button.custom_minimum_size = Vector2(220.0, 56.0)
	_host_start_button.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_host_start_button.offset_left = -110.0
	_host_start_button.offset_top = 112.0
	_host_start_button.offset_right = 110.0
	_host_start_button.offset_bottom = 168.0
	_host_start_button.visible = false
	_host_start_button.pressed.connect(_request_network_match_start)
	hud.add_child(_host_start_button)


func _setup_mobile_controls() -> void:
	if hud == null or OS.get_name() != "Android":
		return
	_mobile_controls = Control.new()
	_mobile_controls.name = "MobileGameplayControls"
	_mobile_controls.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_mobile_controls.mouse_filter = Control.MOUSE_FILTER_PASS
	hud.add_child(_mobile_controls)
	var left_button: Button = _make_touch_button("LEFT", "left", 18, -106, 94, -30)
	var right_button: Button = _make_touch_button("RIGHT", "right", 102, -106, 178, -30)
	var jab_button: Button = _make_touch_button("JAB", "jab", -188, -190, -104, -112)
	var heavy_button: Button = _make_touch_button("HEAVY", "heavy", -98, -190, -14, -112)
	var block_button: Button = _make_touch_button("BLOCK", "block", -188, -102, -104, -24)
	var dodge_button: Button = _make_touch_button("DODGE", "dodge", -98, -102, -14, -24)
	for button: Button in [left_button, right_button, jab_button, heavy_button, block_button, dodge_button]:
		button.add_theme_font_size_override("font_size", 16)
	var controls_label: Label = hud.get_node_or_null("ControlsLabel") as Label
	if controls_label != null:
		controls_label.visible = false


func _make_touch_button(
	label_text: String,
	action: String,
	left: float,
	top: float,
	right: float,
	bottom: float
) -> Button:
	var button: Button = Button.new()
	button.text = label_text
	button.custom_minimum_size = Vector2(76.0, 76.0)
	button.set_anchors_and_offsets_preset(
		Control.PRESET_BOTTOM_RIGHT if left < 0.0 else Control.PRESET_BOTTOM_LEFT
	)
	button.offset_left = left
	button.offset_top = top
	button.offset_right = right
	button.offset_bottom = bottom
	button.button_down.connect(_on_touch_button_down.bind(action))
	button.button_up.connect(_on_touch_button_up.bind(action))
	_mobile_controls.add_child(button)
	return button


func _on_touch_button_down(action: String) -> void:
	if action == "left":
		_touch_left_held = true
	elif action == "right":
		_touch_right_held = true
	elif action == "block":
		_touch_block_held = true


func _on_touch_button_up(action: String) -> void:
	if action == "left":
		_touch_left_held = false
	elif action == "right":
		_touch_right_held = false
	elif action == "block":
		_touch_block_held = false
	elif action == "jab":
		_touch_light_pending = true
	elif action == "heavy":
		_touch_heavy_pending = true
	elif action == "dodge":
		_touch_dodge_pending = true


func _create_result_overlay() -> void:
	if hud == null:
		return
	_result_overlay = Control.new()
	_result_overlay.name = "MatchResultOverlay"
	_result_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_result_overlay.visible = false
	_result_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	hud.add_child(_result_overlay)
	var backdrop: ColorRect = ColorRect.new()
	backdrop.color = Color(0.0, 0.0, 0.0, 0.68)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_result_overlay.add_child(backdrop)
	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_result_overlay.add_child(center)
	var panel: PanelContainer = PanelContainer.new()
	panel.custom_minimum_size = Vector2(
		maxf(minf(get_viewport_rect().size.x - 32.0, 300.0), 240.0),
		220.0
	)
	center.add_child(panel)
	var content: VBoxContainer = VBoxContainer.new()
	content.add_theme_constant_override("separation", 14)
	panel.add_child(content)
	_result_title = Label.new()
	_result_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_title.add_theme_font_size_override("font_size", 28)
	content.add_child(_result_title)
	var rematch_button: Button = Button.new()
	rematch_button.name = "RematchButton"
	rematch_button.text = "Rematch"
	rematch_button.custom_minimum_size.y = 52.0
	rematch_button.pressed.connect(_on_rematch_pressed)
	content.add_child(rematch_button)
	var menu_button: Button = Button.new()
	menu_button.text = "Back to Project" if _has_project_launch() else "Main Menu"
	menu_button.custom_minimum_size.y = 52.0
	menu_button.pressed.connect(_return_to_main_menu)
	content.add_child(menu_button)
	if _match_mode != "single_player":
		rematch_button.disabled = true
		rematch_button.text = "Network rematch unavailable"


func _show_match_result() -> void:
	if _result_shown or _result_overlay == null or combat_system == null:
		return
	_result_shown = true
	_match_lifecycle = MatchLifecycle.FINISHED
	if _single_player_mode:
		_result_title.text = "YOU WIN" if combat_system.winner_id == 1 else "CPU WINS"
	else:
		_result_title.text = "PLAYER %d WINS" % combat_system.winner_id
	_result_overlay.visible = true
	if _return_menu_button != null:
		_return_menu_button.visible = false


func _on_rematch_pressed() -> void:
	if _match_mode != "single_player":
		return
	var launch_config: Node = get_node_or_null("/root/NetworkLaunchConfig")
	if launch_config == null:
		return
	launch_config.call("set_single_player")
	launch_config.call("set_fighter_selection", _p1_fighter_id, _p2_fighter_id)
	get_tree().reload_current_scene()


func _set_connection_status(message: String) -> void:
	if play_status_label != null:
		play_status_label.text = message


func _on_transport_connection_failed(reason: String) -> void:
	if OS.is_debug_build():
		push_warning("[Arena] Connection failed: %s" % reason)
	_connection_failure_message = reason if OS.is_debug_build() else "Connection failed"
	_set_connection_status("Connection failed.\nReturn to menu to try again.")


func _on_transport_disconnected() -> void:
	if not is_inside_tree():
		return
	_connection_failure_message = "Disconnected"
	_set_connection_status("Disconnected.\nReturn to the Main Menu to reconnect.")


func _return_to_main_menu() -> void:
	if _returning_to_menu:
		return
	_returning_to_menu = true
	var launch_config: Node = get_node_or_null("/root/NetworkLaunchConfig")
	if launch_config != null:
		launch_config.call("clear")
	if transport != null and transport.has_method("shutdown"):
		transport.call("shutdown")
	get_tree().change_scene_to_file(
		PROJECT_DETAIL_SCENE_PATH
		if _has_project_launch()
		else "res://games/rollback_fighter/scenes/MainMenu.tscn"
	)


func _has_project_launch() -> bool:
	var project_context: Node = get_node_or_null("/root/GameProjectLaunchConfig")
	return project_context != null and bool(project_context.call("is_project_match"))


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_return_to_main_menu()


func _begin_config_handshake() -> void:
	if not _use_enet or transport == null or _config_handshake_sent:
		return
	if _match_config_handshake.project_required and not _match_config_handshake.project_verified:
		return
	if _match_mode in ["host", "client", "debug"] and not _fighter_selection_exchange_complete():
		return
	if not bool(transport.get("is_connected")):
		return
	if bool(transport.get("is_host")) and int(transport.get("remote_peer_id")) <= 0:
		return
	if not transport.has_method("send_match_config"):
		_fail_config_handshake("Transport does not support config compatibility checks.")
		return
	_config_handshake_sent = true
	transport.send_match_config(_local_match_config_identity)
	if OS.is_debug_build():
		print("[ConfigHandshake] local identity sent to connected peer")


func _fighter_selection_exchange_complete() -> bool:
	return _fighter_selection_acknowledged if _is_host else _fighter_selection_received


func _send_host_fighter_selection() -> void:
	if not _is_host or _fighter_selection_sent or transport == null:
		return
	if _match_config_handshake.project_required and not _match_config_handshake.project_verified:
		return
	if not transport.has_method("send_match_selection"):
		_fail_config_handshake("Transport does not support fighter selection.")
		return
	if not bool(transport.call("send_match_selection", _p1_fighter_id, _p2_fighter_id)):
		return
	_fighter_selection_sent = true
	if OS.is_debug_build():
		print("[Arena] Host fighter selection sent: P1=%s P2=%s" % [
			_p1_fighter_id, _p2_fighter_id
		])


func _on_match_selection_received(p1_id: String, p2_id: String) -> void:
	if _is_host or rollback_session == null or bool(rollback_session.match_started):
		return
	if _fighter_selection_received:
		if p1_id != _p1_fighter_id or p2_id != _p2_fighter_id:
			_fail_config_handshake("Host changed fighter selection during startup.")
		return
	if not _apply_fighter_selection(p1_id, p2_id):
		_fail_config_handshake("Fighter not installed on both devices.")
		return
	var project_context: Node = get_node_or_null("/root/GameProjectLaunchConfig")
	if project_context != null and bool(project_context.call("is_network_project")):
		var roster: Array[String] = project_context.call("get_fighter_ids")
		if p1_id not in roster or p2_id not in roster:
			_fail_config_handshake("Host selected a fighter outside the verified project roster.")
			return
		if not bool(project_context.call("set_fighter_selection", p1_id, p2_id)):
			_fail_config_handshake("Could not preserve the verified project fighter assignments.")
			return
	_fighter_selection_received = true
	if transport != null and transport.has_method("send_match_selection_ack"):
		if not bool(transport.call("send_match_selection_ack", p1_id, p2_id)):
			_fail_config_handshake("Could not acknowledge host fighter selection.")
			return
	if OS.is_debug_build():
		print("[Arena] Host fighter selection applied: P1=%s P2=%s" % [p1_id, p2_id])
	_begin_config_handshake()


func _on_match_selection_ack_received(p1_id: String, p2_id: String) -> void:
	if not _is_host:
		return
	if p1_id != _p1_fighter_id or p2_id != _p2_fighter_id:
		_fail_config_handshake("Client acknowledged a different fighter assignment.")
		return
	_fighter_selection_acknowledged = true
	if OS.is_debug_build():
		print("[Arena] Client acknowledged fighter selection.")
	_begin_config_handshake()


func _send_host_project_identity() -> void:
	if not _is_host or _project_identity_sent or transport == null:
		return
	if _local_project_identity.is_empty() or not transport.has_method("send_project_config"):
		_fail_config_handshake("Project identity is unavailable.")
		return
	if not bool(transport.call("send_project_config", _local_project_identity)):
		return
	_project_identity_sent = true
	if OS.is_debug_build():
		print("[ProjectHandshake] project identity sent")


func _on_project_config_received(identity: Dictionary) -> void:
	if _is_host or _match_config_handshake.failed:
		return
	_match_config_handshake.set_project_verification(true, false)
	var verification := ProjectMultiplayerIdentityScript.new().verify_remote(identity)
	var accepted := bool(verification.get("ok", false))
	var project_context: Node = get_node_or_null("/root/GameProjectLaunchConfig")
	if accepted and (project_context == null or not bool(project_context.call("begin_network", str(identity["project_id"]), false))):
		accepted = false
		verification = {
			"ok": false,
			"code": "PROJECT_MISMATCH",
			"message": "Game project version/configuration mismatch",
		}
	var response := {
		"accepted": accepted,
		"code": str(verification.get("code", "")),
		"message": str(verification.get("message", "PROJECT CONFIG VERIFIED")),
		"project_id": str(identity.get("project_id", "")),
		"digest": str(identity.get("digest", "")),
	}
	if transport == null or not transport.has_method("send_project_config_response") or not bool(transport.call("send_project_config_response", response)):
		_fail_config_handshake("Could not acknowledge game project verification.")
		return
	if not accepted:
		_fail_config_handshake(str(response["message"]))
		return
	var creator_context: Node = get_node_or_null("/root/CreatorLaunchContext")
	if creator_context != null:
		creator_context.call("launch_for_project", str(identity["project_id"]))
	_match_config_handshake.project_verified = true
	_local_project_identity = verification["identity"]
	if _project_presentation_runtime == null:
		_setup_project_presentation()
	_set_connection_status("PROJECT CONFIG VERIFIED\nWaiting for fighter selection...")
	if OS.is_debug_build():
		print("[ProjectHandshake] PROJECT CONFIG VERIFIED")


func _on_project_config_response(response: Dictionary) -> void:
	if not _is_host or _project_response_received or _match_config_handshake.failed:
		return
	_project_response_received = true
	if not bool(response.get("accepted", false)):
		_fail_config_handshake(str(response.get("message", "Game project version/configuration mismatch")))
		return
	if (
		str(response.get("project_id", "")) != str(_local_project_identity.get("project_id", ""))
		or str(response.get("digest", "")) != str(_local_project_identity.get("digest", ""))
	):
		_fail_config_handshake("Game project version/configuration mismatch")
		return
	_match_config_handshake.project_verified = true
	_set_connection_status("PROJECT CONFIG VERIFIED\nSending fighter selection...")
	if OS.is_debug_build():
		print("[ProjectHandshake] PROJECT CONFIG VERIFIED")
	_send_host_fighter_selection()


func _apply_fighter_selection(p1_id: String, p2_id: String) -> bool:
	if p1_id == _p1_fighter_id and p2_id == _p2_fighter_id:
		return true
	if _match_config_handshake.verified or _config_handshake_sent:
		return false
	_p1_fighter_id = p1_id
	_p2_fighter_id = p2_id
	if not _load_authoritative_fighter_definitions():
		return false
	player_state.configure_character_definition(_p1_character_definition)
	opponent_state.configure_character_definition(_p2_character_definition)
	combat_system.configure_character_definitions(
		_p1_character_definition,
		_p2_character_definition,
		_game_rules_definition
	)
	adapter.setup(
		player_state, opponent_state, input_system, lean_system,
		combat_system, _game_rules_definition
	)
	player_state.position = Vector2(_game_rules_definition.get_spawn_position("p1"))
	opponent_state.position = Vector2(_game_rules_definition.get_spawn_position("p2"))
	p1_sprite_debug = _bind_sprite_to_state(
		p1_placeholder, player_state, _p1_character_definition, "P1"
	)
	p2_sprite_debug = _bind_sprite_to_state(
		p2_placeholder, opponent_state, _p2_character_definition, "P2"
	)
	return true


func _on_match_config_received(remote_identity: Dictionary) -> void:
	if _match_config_handshake.failed:
		return
	if _remote_config_identity_received:
		if remote_identity == _match_config_handshake.remote_identity:
			return
		_fail_config_handshake(
			"Peer sent conflicting config identities during one match startup."
		)
		return
	_remote_config_identity_received = true
	var remote_digest: String = str(remote_identity.get("digest", "<invalid>"))
	if OS.is_debug_build():
		print("[ConfigHandshake] remote digest received")
		print("digest=%s" % remote_digest)
	var result: Dictionary = _match_config_handshake.accept_remote_identity(
		remote_identity
	)
	if not bool(result.get("ok", false)):
		_fail_config_handshake(str(result.get("message", "CONFIG MISMATCH")))
		return
	_match_lifecycle = MatchLifecycle.READY
	if OS.is_debug_build():
		print("[ConfigHandshake] MATCH CONFIG VERIFIED")
	_set_connection_status(
		"Ready. Select Start Match."
		if _is_host
		else "Ready. Waiting for host to start."
	)
	if _pending_start_match_received:
		_pending_start_match_received = false
		call_deferred("_on_start_match_received")


func _fail_config_handshake(message: String) -> void:
	_match_config_handshake.failed = true
	_match_config_handshake.verified = false
	_match_config_handshake.failure_message = message
	var local_digest: String = str(_local_match_config_identity.get("digest", "<unavailable>"))
	var remote_digest: String = str(
		_match_config_handshake.remote_identity.get("digest", "<unavailable>")
	)
	var remote_p1: String = str(
		_match_config_handshake.remote_identity.get("p1_id", "<invalid>")
	)
	var remote_p2: String = str(
		_match_config_handshake.remote_identity.get("p2_id", "<invalid>")
	)
	var diagnostic: String = (
		("[Arena] CONFIG MISMATCH: %s\nlocal_digest=%s\nremote_digest=%s\n"
		+ "local_p1=%s\nlocal_p2=%s\nremote_p1=%s\nremote_p2=%s")
		% [
			message,
			local_digest,
			remote_digest,
			str(_local_match_config_identity.get("p1_id", "<unavailable>")),
			str(_local_match_config_identity.get("p2_id", "<unavailable>")),
			remote_p1,
			remote_p2,
		]
	)
	push_error(diagnostic if OS.is_debug_build() else "Configuration mismatch. Both players must use matching fighter/game versions.")
	_connection_failure_message = message
	_set_connection_status(_handshake_failure_status())


func _handshake_failure_status() -> String:
	var message := _match_config_handshake.failure_message
	if message.contains("Game project not installed"):
		return "Game project not installed.\nPress Main Menu to exit."
	if message.contains("Game project version/configuration mismatch"):
		return "Game project version/configuration mismatch.\nPress Main Menu to exit."
	if message.contains("Project changed"):
		return "Project changed — rebuild before hosting.\nPress Main Menu to exit."
	if message.contains("Fighter not installed"):
		return "Fighter not installed on both devices.\nPress Main Menu to exit."
	return "Configuration mismatch.\nBoth players must use matching fighter/game versions.\nPress Main Menu to exit."


func _print_presentation_summary(
	definition: RollbackFighterCharacterDefinition
) -> void:
	var presentation: RollbackFighterPresentationDefinition = (
		definition.get_presentation()
	)
	print("[PresentationDefinition] active")
	print("fighter=%s" % definition.get_id())
	print("source_art_faces=%s" % presentation.get_source_art_faces())
	for animation_id in ["idle", "jab", "heavy", "block", "dodge", "hit", "dead"]:
		var animation: Dictionary = presentation.get_animation(animation_id)
		var frames: Array = animation.get("frames", [])
		print("%s_frames=%d" % [animation_id, frames.size()])


func _print_game_rules_summary(
	rules: RollbackFighterGameRulesDefinition
) -> void:
	var p1_spawn: Vector2i = rules.get_spawn_position("p1")
	var p2_spawn: Vector2i = rules.get_spawn_position("p2")
	print("[GameRulesDefinition] authoritative rules mode active")
	print("simulation_hz=%d" % rules.get_int("simulation_hz"))
	print("input_buffers=%d,%d" % [
		rules.get_int("light_input_buffer_frames"),
		rules.get_int("heavy_input_buffer_frames"),
	])
	print("combo_hitstun=%s" % _join_rule_ints(
		rules.get_int_array("combo_hitstun_percent")
	))
	print("combo_knockback=%s" % _join_rule_ints(
		rules.get_int_array("combo_knockback_percent")
	))
	print("blocked_chip_percent=%d" % rules.get_int("blocked_chip_percent"))
	print("blocked_hit_stun_frames=%d" % rules.get_int(
		"blocked_hit_stun_frames"
	))
	print("dodge_contact_hitstop=%d" % rules.get_int(
		"dodge_contact_hitstop"
	))
	print("spawn_p1=%d,%d" % [p1_spawn.x, p1_spawn.y])
	print("spawn_p2=%d,%d" % [p2_spawn.x, p2_spawn.y])
	print("world_contact=%s,%d,%d,%d,%d" % [
		str(rules.is_world_contact_enabled()),
		rules.get_world_contact_bound("left"),
		rules.get_world_contact_bound("right"),
		rules.get_world_contact_bound("top"),
		rules.get_world_contact_bound("bottom"),
	])
	print("fallback_policy=%s" % rules.get_fallback_policy())


func _join_rule_ints(values: Array) -> String:
	var parts := PackedStringArray()
	for value in values:
		parts.append(str(int(value)))
	return ",".join(parts)


func _print_fighter_definition_summary(
	label: String,
	definition: RollbackFighterCharacterDefinition
) -> void:
	print("%s fighter=%s" % [label, definition.get_id()])
	print("hp=%d" % definition.get_int("max_hp"))
	print("movement=%d,%d,%d,%d,%d,%d" % [
		definition.get_int("move_speed"),
		definition.get_int("acceleration"),
		definition.get_int("braking"),
		definition.get_int("reversal_acceleration"),
		definition.get_int("knockback_friction"),
		definition.get_int("max_knockback_speed"),
	])
	print("hurtbox=%d,%d,%d,%d" % [
		definition.get_int("hurtbox_x"),
		definition.get_int("hurtbox_y"),
		definition.get_int("hurtbox_width"),
		definition.get_int("hurtbox_height"),
	])
	print("guard=%d,%d,%d,%d,%d" % [
		definition.get_int("guard_max_units"),
		definition.get_int("guard_held_drain_per_frame"),
		definition.get_int("guard_regen_per_frame"),
		definition.get_int("guard_break_refill_units"),
		definition.get_int("guard_break_stun_frames"),
	])
	print("dodge=%d,%d,%d,%d" % [
		definition.get_int("dodge_total_frames"),
		definition.get_int("dodge_invuln_start"),
		definition.get_int("dodge_invuln_end"),
		definition.get_int("dodge_cooldown_frames"),
	])


func _print_match_definitions_summary(
	p1: RollbackFighterCharacterDefinition,
	p2: RollbackFighterCharacterDefinition,
	canonical_byte_length: int,
	digest: String
) -> void:
	print("[MatchDefinitions]")
	_print_match_definition_player("P1", p1)
	_print_match_definition_player("P2", p2)
	print("canonical_byte_length=%d" % canonical_byte_length)
	print("match_digest=%s" % digest)


func _print_match_definition_player(
	label: String,
	definition: RollbackFighterCharacterDefinition
) -> void:
	print("%s:" % label)
	print("id=%s" % definition.get_id())
	print("hp=%d" % definition.get_int("max_hp"))
	print("move_speed=%d" % definition.get_int("move_speed"))
	print("guard=%d" % definition.get_int("guard_max_units"))
	print("dodge=%d,%d,%d,%d" % [
		definition.get_int("dodge_total_frames"),
		definition.get_int("dodge_invuln_start"),
		definition.get_int("dodge_invuln_end"),
		definition.get_int("dodge_cooldown_frames"),
	])
	print("jab_damage=%d" % definition.get_move_for_slot("light").get_int("damage"))
	print("heavy_damage=%d" % definition.get_move_for_slot("heavy").get_int("damage"))


func _attack_definition_summary(
	move_definition: RollbackFighterMoveDefinition
) -> String:
	return "%d,%d,%d,%d,%d,%d,%d,%d,%d" % [
		move_definition.get_int("startup"),
		move_definition.get_int("active"),
		move_definition.get_int("recovery"),
		move_definition.get_int("damage"),
		move_definition.get_int("hitstun"),
		move_definition.get_int("knockback_x"),
		move_definition.get_int("hitstop"),
		move_definition.get_int("contact_cooldown"),
		move_definition.get_int("guard_damage"),
	]


func _physics_process(delta: float) -> void:
	_physics_ticks_since_last_render += 1
	_update_play_hud()

	if _single_player_mode:
		if _single_player_started and not combat_system.match_over:
			var human_input: Dictionary = _collect_local_input()
			var cpu_input: Dictionary = _single_player_cpu.call(
				"input_for_frame",
				_single_player_frame,
				opponent_state,
				player_state,
				combat_system.match_over
			)
			adapter.simulate(human_input, cpu_input, SINGLE_PLAYER_PHYS_DT)
			_single_player_frame += 1
		_update_visuals()
		_update_camera(delta)
		_update_health_tint()
		_update_combat_debug_hud()
		_update_rollback_debug_hud()
		_observe_project_presentation()
		return

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

		var local_input: Dictionary = (
			_stress_neutral_input()
			if combat_system != null and combat_system.match_over
			else _collect_local_input()
		)
		rollback_session.tick(local_input)

		if benchmark_running:
			_check_benchmark_complete()

	_update_visuals()
	_update_camera(delta)
	_update_health_tint()
	_update_combat_debug_hud()
	_update_rollback_debug_hud()
	_observe_project_presentation()


func _setup_project_presentation() -> void:
	var project_context: Node = get_node_or_null("/root/GameProjectLaunchConfig")
	if project_context != null and bool(project_context.call("is_project_match")):
		_project_presentation_runtime = ProjectPresentationRuntimeScript.new()
		_project_presentation_runtime.name = "ProjectPresentationRuntime"
		add_child(_project_presentation_runtime)
		var project_id := str(project_context.call("get_project_id"))
		_project_presentation_runtime.configure(
			self,
			ProjectPresentationResolverScript.new().resolve(project_id)
		)
		return
	# A joining client does not know the host project until the project handshake.
	# Leave the built-in Arena presentation untouched until that identity verifies.
	if _use_enet and not _is_host:
		return
	var context: Node = get_node_or_null("/root/CreatorLaunchContext")
	if context == null:
		return
	_project_presentation_runtime = ProjectPresentationRuntimeScript.new()
	_project_presentation_runtime.name = "ProjectPresentationRuntime"
	add_child(_project_presentation_runtime)
	_project_presentation_runtime.configure(self, context.call("get_runtime_presentation"))


func _observe_project_presentation() -> void:
	if _project_presentation_runtime == null or combat_system == null:
		return
	var active := _single_player_started if _single_player_mode else (rollback_session != null and bool(rollback_session.match_started))
	_project_presentation_runtime.observe(player_state, opponent_state, active, combat_system.match_over)


func _on_frame_pre_draw() -> void:
	_last_render_physics_ticks = _physics_ticks_since_last_render
	var correction_was_active: bool = _remote_render_correction_active
	_advance_remote_render_correction()
	if OS.is_debug_build():
		_record_presentation_measurement(correction_was_active)
	_physics_ticks_since_last_render = 0
	if OS.is_debug_build():
		_update_visual_diagnostic_hud()


func _collect_local_input() -> Dictionary:
	if _tuning_panel != null and _tuning_panel.visible:
		return _stress_neutral_input()

	if OS.is_debug_build() and not _single_player_mode and QA_COMBAT_FUZZ_BENCHMARK_ENABLED:
		return _collect_combat_fuzz_input()

	if OS.is_debug_build() and not _single_player_mode and QA_STRESS_BENCHMARK_ENABLED:
		return _collect_stress_bot_input()

	if OS.is_debug_build() and not _single_player_mode and QA_BOT_BENCHMARK_ENABLED:
		return _collect_bot_input()

	var mx: float = Input.get_action_strength("p1_right") - Input.get_action_strength("p1_left")
	mx += float(int(_touch_right_held) - int(_touch_left_held))
	mx = clampf(mx, -1.0, 1.0)
	var light_pressed: bool = Input.is_action_just_pressed("jab") or _touch_light_pending
	var heavy_pressed: bool = Input.is_action_just_pressed("heavy_attack") or _touch_heavy_pending
	var dodge_pressed: bool = Input.is_action_just_pressed("dodge") or _touch_dodge_pending
	_touch_light_pending = false
	_touch_heavy_pending = false
	_touch_dodge_pending = false

	return {
		"mx": mx,
		"lean_l": Input.is_action_pressed("lean_left"),
		"lean_r": Input.is_action_pressed("lean_right"),
		"atk_l": light_pressed,
		"atk_h": heavy_pressed,
		"block": Input.is_action_pressed("block") or _touch_block_held,
		"dodge": dodge_pressed,
	}


func _collect_combat_fuzz_input() -> Dictionary:
	var benchmark_frame: int = 0
	if rollback_session != null:
		benchmark_frame = maxi(
			int(rollback_session.current_frame) - benchmark_start_frame,
			0
		)

	return CombatFuzzBenchmarkScript.input_for_frame(
		QA_COMBAT_FUZZ_SEED,
		benchmark_frame,
		local_player_id
	)


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
	return OS.is_debug_build() and (
		QA_BOT_BENCHMARK_ENABLED
		or QA_STRESS_BENCHMARK_ENABLED
		or QA_COMBAT_FUZZ_BENCHMARK_ENABLED
	)


func _benchmark_duration_frames() -> int:
	if QA_COMBAT_FUZZ_BENCHMARK_ENABLED:
		if QA_COMBAT_FUZZ_STOP_AFTER_FRAME >= 0:
			return clampi(
				QA_COMBAT_FUZZ_STOP_AFTER_FRAME + 1,
				1,
				COMBAT_FUZZ_TOTAL_FRAMES
			)
		return COMBAT_FUZZ_TOTAL_FRAMES

	if QA_STRESS_BENCHMARK_ENABLED:
		return STRESS_TOTAL_FRAMES

	return BENCHMARK_DURATION_FRAMES


func _benchmark_mode_name() -> String:
	if QA_COMBAT_FUZZ_BENCHMARK_ENABLED:
		return (
			"COMBAT_FUZZ_LOSS"
			if QA_STRESS_FORCE_PACKET_LOSS
			else "COMBAT_FUZZ_NATURAL"
		)

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
	print("Mode: %s" % ("ENet" if _use_enet else "LatencyHarness"))
	print("BenchmarkMode: %s" % _benchmark_mode_name())
	print("DelayFrames: %d" % BENCHMARK_DELAY_FRAMES)
	print("JitterFrames: %d" % BENCHMARK_JITTER_FRAMES)
	print("DurationFrames: %d" % _benchmark_duration_frames())
	if QA_STRESS_BENCHMARK_ENABLED:
		print("StressScheduleFrames: %d" % STRESS_SCHEDULE_FRAMES)
		print("StressDrainFrames: %d" % STRESS_DRAIN_FRAMES)
	if QA_COMBAT_FUZZ_BENCHMARK_ENABLED:
		print("CombatFuzzSeed: %d" % QA_COMBAT_FUZZ_SEED)
		print("CombatFuzzScheduleFrames: %d" % COMBAT_FUZZ_DURATION_FRAMES)
		print("CombatFuzzDrainFrames: %d" % COMBAT_FUZZ_DRAIN_FRAMES)
		print("CombatFuzzPhase1: 0-1199 MOVEMENT_REVERSAL")
		print("CombatFuzzPhase2: 1200-2399 LIGHT_EMPHASIS")
		print("CombatFuzzPhase3: 2400-3599 HEAVY_BLOCK")
		print("CombatFuzzPhase4: 3600-4799 DODGE_COUNTER")
		print("CombatFuzzPhase5: 4800-5999 MIXED_CHAOS")
		print("CombatFuzzPhase6: 6000-7199 HIGH_INTENSITY_IDLE_RESUME")
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

	if (
		(QA_STRESS_BENCHMARK_ENABLED or QA_COMBAT_FUZZ_BENCHMARK_ENABLED)
		and _use_enet
		and transport != null
	):
		print("ForcedInputPacketsDropped: %d" % int(transport.get(
			"deterministic_stress_input_packets_dropped"
		)))

	if QA_STRESS_BENCHMARK_ENABLED:
		_print_stress_verdict(diagnostics)
	elif QA_COMBAT_FUZZ_BENCHMARK_ENABLED:
		_print_combat_fuzz_results(diagnostics)

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


func _print_combat_fuzz_results(diagnostics: Dictionary) -> void:
	var snapshot: Dictionary = adapter.capture()
	CombatFuzzBenchmarkScript.print_results(
		QA_COMBAT_FUZZ_SEED,
		diagnostics,
		snapshot,
		adapter.canonical_checksum(snapshot),
		benchmark_start_frame,
		QA_COMBAT_FUZZ_STOP_AFTER_FRAME,
		COMBAT_FUZZ_DRAIN_FRAMES
	)


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
	if not OS.is_debug_build():
		return
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
	if not OS.is_debug_build():
		return
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
	if not OS.is_debug_build() or not show_runtime_combat_boxes or _combat_box_overlay == null:
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
	if _host_start_button != null:
		_host_start_button.visible = (
			_use_enet
			and _is_host
			and _match_mode != "debug"
			and _match_lifecycle == MatchLifecycle.READY
			and rollback_session != null
			and not bool(rollback_session.match_started)
			and not _result_shown
		)
	if not _connection_failure_message.is_empty():
		if _match_config_handshake.failed:
			play_status_label.text = _handshake_failure_status()
		else:
			play_status_label.text = "Connection failed.\nReturn to menu to try again."
		return

	if combat_system != null and combat_system.match_over:
		play_status_label.text = ""
		_show_match_result()
		return

	if _single_player_mode:
		play_status_label.text = "P1 vs CPU"
		return

	if rollback_session != null and bool(rollback_session.match_started):
		play_status_label.text = (
			_benchmark_mode_name()
			if _benchmark_enabled()
			else "FIGHT!"
		)
		return

	if transport == null:
		play_status_label.text = "Starting network..."
		return

	if not _use_enet:
		play_status_label.text = "Ready. Press Space to start."
		return

	if _is_host:
		var remote_peer_id: int = int(transport.get("remote_peer_id"))
		if remote_peer_id > 0:
			if _match_config_handshake.can_start_network_match():
				play_status_label.text = "Ready. Select Start Match."
			elif not _fighter_selection_acknowledged:
				play_status_label.text = "Player connected.\nConfirming fighter selection..."
			else:
				play_status_label.text = "Player connected.\nVerifying match configuration..."
		else:
			play_status_label.text = "Hosting...\nWaiting for player..."
	else:
		var connected: bool = bool(transport.get("is_connected"))
		if not connected:
			play_status_label.text = "Connecting..."
		elif not _fighter_selection_received:
			play_status_label.text = "Connected.\nWaiting for host fighter selection..."
		elif not _match_config_handshake.can_start_network_match():
			play_status_label.text = "Verifying match configuration..."
		else:
			play_status_label.text = "Ready. Waiting for host to start..."


func _update_camera(delta: float) -> void:
	if cam == null or p1_placeholder == null or p2_placeholder == null:
		return

	var p1_x: float = p1_placeholder.position.x
	var p2_x: float = p2_placeholder.position.x
	cam.position.y = CAMERA_FIXED_Y
	cam.offset = Vector2.ZERO
	cam.zoom = Vector2.ONE * CAMERA_FIXED_ZOOM

	var viewport_width: float = get_viewport_rect().size.x
	var visible_width: float = viewport_width / CAMERA_FIXED_ZOOM
	var visible_left: float = cam.position.x - visible_width * 0.5
	var visible_right: float = cam.position.x + visible_width * 0.5
	var left_safe_edge: float = lerpf(
		visible_left,
		visible_right,
		CAMERA_LEFT_SAFE_RATIO
	)
	var right_safe_edge: float = lerpf(
		visible_left,
		visible_right,
		CAMERA_RIGHT_SAFE_RATIO
	)
	var leftmost_fighter_x: float = minf(p1_x, p2_x)
	var rightmost_fighter_x: float = maxf(p1_x, p2_x)
	var target_camera_x: float = cam.position.x

	if rightmost_fighter_x > right_safe_edge:
		target_camera_x += rightmost_fighter_x - right_safe_edge
	elif leftmost_fighter_x < left_safe_edge:
		target_camera_x += leftmost_fighter_x - left_safe_edge

	var follow_weight: float = 1.0 - exp(-CAMERA_FOLLOW_SPEED * delta)
	cam.position.x = lerpf(cam.position.x, target_camera_x, follow_weight)


func _update_health_tint() -> void:
	if p1_placeholder:
		var g1: float = clamp(float(player_state.hp) / float(player_state.max_hp), 0.0, 1.0)
		p1_placeholder.modulate = Color(1.0, g1, g1, 1.0)

	if p2_placeholder:
		var g2: float = clamp(float(opponent_state.hp) / float(opponent_state.max_hp), 0.0, 1.0)
		p2_placeholder.modulate = Color(1.0, g2, g2, 1.0)


func _update_rollback_debug_hud() -> void:
	if not OS.is_debug_build():
		return
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
	if not _use_enet:
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
	if not OS.is_debug_build():
		return
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
	if not OS.is_debug_build():
		return
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


func _bind_sprite_to_state(
	placeholder: Node,
	state: Node,
	definition: RollbackFighterCharacterDefinition,
	label: String
) -> Node:
	if placeholder == null or state == null or definition == null:
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

	sprite.call(
		"bind_state",
		state,
		definition.get_presentation(),
		definition.get_int("dodge_total_frames")
	)
	return sprite


func _on_start_match_received() -> void:
	if rollback_session == null:
		return

	if bool(rollback_session.match_started):
		if OS.is_debug_build():
			print("[Arena] Duplicate start_match ignored.")
		return
	if not _match_config_handshake.may_start_match(_use_enet):
		if _match_config_handshake.failed:
			return
		_pending_start_match_received = true
		if OS.is_debug_build():
			print("[Arena] START received before config verification; waiting.")
		return

	if OS.is_debug_build():
		print("[Arena] start_match received. Starting rollback session.")
	_clear_remote_render_correction()
	_remote_render_correction_snap_count = 0
	_remote_render_correction_smooth_count = 0
	rollback_session.start_session()
	_match_lifecycle = MatchLifecycle.PLAYING
	_set_connection_status("Match started.\nPress Main Menu to exit.")
	if _benchmark_enabled():
		_start_benchmark_timer()
	if _host_start_button != null:
		_host_start_button.visible = false


func _request_network_match_start() -> void:
	if not _use_enet:
		if rollback_session != null and not bool(rollback_session.match_started):
			_on_start_match_received()
		return
	if transport == null or not transport.has_method("send_start_match"):
		return
	if not bool(transport.get("is_host")):
		return
	if rollback_session != null and bool(rollback_session.match_started):
		return
	if not _match_config_handshake.can_start_network_match():
		return
	transport.send_start_match()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_return_to_main_menu()
		get_viewport().set_input_as_handled()
		return

	if event is InputEventKey:
		var key_event: InputEventKey = event
		if key_event.pressed and not key_event.echo:
			if key_event.keycode == KEY_ESCAPE:
				_return_to_main_menu()
				get_viewport().set_input_as_handled()
				return
			if OS.is_debug_build() and key_event.keycode == KEY_F4 and _tuning_panel != null:
				_tuning_panel.call(
					"set_panel_open",
					not bool(_tuning_panel.visible)
				)
				get_viewport().set_input_as_handled()
				return
			if OS.is_debug_build() and key_event.keycode == KEY_F2:
				_reset_presentation_measurement()
				get_viewport().set_input_as_handled()
				return
			if OS.is_debug_build() and key_event.keycode == KEY_F3:
				_print_presentation_measurement_report()
				get_viewport().set_input_as_handled()
				return

	if event.is_action_pressed("ui_accept"):
		if OS.is_debug_build() and _match_mode == "debug":
			_request_network_match_start()
		elif _host_start_button != null and _host_start_button.visible:
			_request_network_match_start()
		get_viewport().set_input_as_handled()
		return
