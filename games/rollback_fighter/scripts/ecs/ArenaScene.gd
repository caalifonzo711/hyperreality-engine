extends Node2D

# ArenaScene.gd — ENet-ready rollback fighter arena

const USE_ENET := true
const ENET_HOST := true # DESKTOP: true | LAPTOP: false
const ENET_IP := "127.0.0.1" # LAPTOP: replace with desktop local IP
const ENET_PORT := 7777

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
		transport.delay_frames = 6
		add_child(transport)
		local_player_id = 1
		print("[Arena] LatencyHarness mode | player_id=1")

	rollback_session = RollbackNetworkSessionScene.new()
	add_child(rollback_session)
	rollback_session.setup(adapter, transport, local_player_id)

	if hud:
		hud.set("p1_state", player_state)
		hud.set("p2_state", opponent_state)


func _physics_process(delta: float) -> void:
	_update_wall_state()

	if rollback_session:
		var local_input: Dictionary = _collect_local_input()
		rollback_session.tick(local_input)

	_update_visuals()
	_update_camera(delta)
	_update_health_tint()
	_update_combat_debug_hud()
	_update_rollback_debug_hud()


func _collect_local_input() -> Dictionary:
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
		debug_tick_label.text = "Frame: %d | Player ID: %d" % [
			int(rollback_session.current_frame),
			local_player_id
		]

	var mode_text := "ENet"
	if not USE_ENET:
		mode_text = "LatencyHarness"

	if debug_replay_label:
		debug_replay_label.text = (
			"Mode=%s | Connected=%s\nRollback count=%d | Max depth=%d | Misses=%d"
		) % [
			mode_text,
			str(transport.get("is_connected") if transport != null and transport.get("is_connected") != null else false),
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
