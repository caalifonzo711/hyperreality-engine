extends Node2D
# ArenaScene.gd — split-controls local dev; optional rollback netplay loopback

@export var use_netplay: bool = false

# --- ECS / State ---
@onready var player_state    := PlayerState.new()
@onready var opponent_state  := PlayerState.new()
@onready var input_system    := InputSystem.new()
@onready var lean_system     := LeanSystem.new()
@onready var combat_system   := CombatSystem.new()

# --- Net adapter ---
@onready var adapter: FighterRollbackAdapter = preload(
	"res://games/rollback_fighter/scripts/net/FighterRollbackAdapter.gd"
).new()

# --- Scene refs ---
@onready var cam: Camera2D          = get_node_or_null("Camera2D")
@onready var p1_placeholder: Node2D = get_node_or_null("PlayerPlaceholder")
@onready var p2_placeholder: Node2D = get_node_or_null("OpponentPlaceholder")
@onready var hud: Node              = get_node_or_null("HUD")

# Debug HUD (Tick / Pos / Input / Replay labels)
@onready var debug_hud_root: Control = get_node_or_null("DebugHUD/Control")
@onready var debug_tick_label: Label = (
	debug_hud_root.get_node("MarginContainer/VBoxContainer/TickLabel")
	if debug_hud_root != null else null
)
@onready var debug_pos_label: Label = (
	debug_hud_root.get_node("MarginContainer/VBoxContainer/PosLabel")
	if debug_hud_root != null else null
)
@onready var debug_input_label: Label = (
	debug_hud_root.get_node("MarginContainer/VBoxContainer/InputLabel")
	if debug_hud_root != null else null
)
@onready var debug_replay_label: Label = (
	debug_hud_root.get_node("MarginContainer/VBoxContainer/ReplayLabel")
	if debug_hud_root != null else null
)

# Optional UI (debug buttons / label)
@onready var attack_button: Button = get_node_or_null("AttackButton")
@onready var dodge_button: Button  = get_node_or_null("DodgeButton")
@onready var tick_label: Label     = get_node_or_null("FighterTickLabel")
var _tick: int = 0

# --- simulated latency test harness ---
@export var simulated_remote_delay_frames: int = 6   # 6=~100ms, 9=~150ms, 12=~200ms
var _remote_input_delay_queue: Array[Dictionary] = []

# Rollback self-test config
const TEST_TOTAL_FRAMES := 10
const TEST_ROLLBACK_AT  := 5
const TEST_EPSILON      := 0.001

# Camera lean feel
const LEAN_OFFSET := 14.0
const LEAN_LERP_SPEED := 10.0
var _lean_vis_x: float = 0.0

var _using_net: bool = false
const PHYS_DT := 1.0 / 60.0

func _empty_input_payload() -> Dictionary:
	return {
		"mx": 0.0,
		"lean_l": false,
		"lean_r": false,
		"atk_l": false,
		"atk_h": false,
		"block": false,
		"dodge": false,
	}

func _find_bindable_sprite(root: Node) -> Node:
	if root == null:
		return null

	# Find ANY node under this placeholder that implements bind_state()
	var stack: Array[Node] = [root]
	while stack.size() > 0:
		var n: Node = stack.pop_back()
		if n != null and n.has_method("bind_state"):
			return n
		for c in n.get_children():
			if c is Node:
				stack.append(c)

	return null


func _bind_placeholder_to_state(placeholder: Node, state: Node, label: String) -> void:
	if placeholder == null or state == null:
		return

	var spr := _find_bindable_sprite(placeholder)
	if spr == null:
		push_warning("[Arena] Could not find a bindable sprite under %s" % placeholder.name)
		return

	# set label if the property exists
	if spr.get("debug_label") != null:
		spr.set("debug_label", label)

	spr.call("bind_state", state)
	print("[Arena] Bound %s sprite=%s to state=%s" % [label, spr.get_instance_id(), state.get_instance_id()])


# ------------------------------------------------------------------
# Sprite binding (Option A)
# We bind PlayerSpriteDebug under each placeholder to the correct PlayerState.
# PlayerSpriteDebug must implement:
#   func bind_state(state: Node) -> void
# ------------------------------------------------------------------
func _bind_sprite_to_state(placeholder: Node, state: Node, label: String) -> void:
	if placeholder == null or state == null:
		push_warning("[Arena] Missing placeholder/state for %s binding." % label)
		return

	# Find node named PlayerSpriteDebug anywhere under the placeholder
	var sprite: Node = placeholder.find_child("PlayerSpriteDebug", true, false)

	# Fallback: find first child in subtree that has bind_state()
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
		push_warning("[Arena] Could not find PlayerSpriteDebug (or bind_state) under %s" % placeholder.name)
		return

	# Optional debug label if script exposes it
	var maybe_label: Variant = sprite.get("debug_label")
	if maybe_label != null:
		sprite.set("debug_label", label)

	sprite.call("bind_state", state)
	print("[Arena] Bound %s sprite=%s to state=%s" % [label, str(sprite.get_instance_id()), str(state.get_instance_id())])


func _ensure_opponent_placeholder() -> void:
	# Only duplicate if the scene truly does NOT have OpponentPlaceholder
	if p2_placeholder == null and p1_placeholder != null:
		p2_placeholder = p1_placeholder.duplicate()
		p2_placeholder.name = "OpponentPlaceholder"
		add_child(p2_placeholder)
		print("[Arena] OpponentPlaceholder missing; duplicated PlayerPlaceholder for dev.")


func _ready() -> void:
	print("[Arena] _ready, use_netplay =", use_netplay)

	# Mount ECS so _process hooks run
	add_child(player_state)
	add_child(opponent_state)
	add_child(input_system)
	add_child(lean_system)
	add_child(combat_system)

	# Spawn points
	player_state.position   = Vector2(200, 250)
	opponent_state.position = Vector2(600, 250)

	# Recommended: set ids if PlayerState supports it (safe even if absent)
	if player_state.get("player_id") != null:
		player_state.set("player_id", 1)
	if opponent_state.get("player_id") != null:
		opponent_state.set("player_id", 2)

	_ensure_opponent_placeholder()

	# Bind visuals to states (each sprite must read its own state, NOT global Input)
	_bind_sprite_to_state(p1_placeholder, player_state, "P1")
	_bind_sprite_to_state(p2_placeholder, opponent_state, "P2")

	# System wiring
	lean_system.player_state = player_state

	# --- FIX: CombatSystem wiring updated ---
	combat_system.p1_state = player_state
	combat_system.p2_state = opponent_state

	# Adapter
	add_child(adapter)
	adapter.setup(player_state, opponent_state, input_system, lean_system, combat_system)

	# HUD hookup
	if hud:
		hud.set("p1_state", player_state)
		hud.set("p2_state", opponent_state)

	# Optional debug UI signals


	# Mode selection
	if use_netplay:
		_setup_netplay()
	else:
		_using_net = false
		print("[Arena] Local split-controls mode (no networking).")
		print("[Arena] Ready. Using rollback plugin:", _using_net)


# --------------------------------------------------------
# Netplay setup (uses autoload RollbackNetplaySingleton)
# --------------------------------------------------------
func _setup_netplay() -> void:
	var rn = RollbackNetplaySingleton
	if rn == null:
		push_warning("RollbackNetplaySingleton autoload not found, falling back to local mode.")
		_using_net = false
		return

	rn.set_callbacks(
		Callable(self, "_rn_collect"),
		Callable(self, "_rn_simulate"),
		Callable(self, "_rn_capture"),
		Callable(self, "_rn_restore")
	)

	if debug_tick_label and not rn.tick_advanced.is_connected(_on_netplay_tick):
		rn.tick_advanced.connect(_on_netplay_tick)

	rn.start(60, "fighter")
	_using_net = true

	print("[Arena] RollbackNetplay loopback enabled.")
	print("[Arena] Simulation is now driven by RollbackNetplaySingleton, not _physics_process().")


func _physics_process(delta: float) -> void:
	# -----------------------------
	# LOCAL MODE (with fake latency)
	# -----------------------------
	if not _using_net:
		var local: Dictionary = _collect_p1_input()
		var remote_now: Dictionary = _collect_p2_input()

		# Add current remote input into queue
		_remote_input_delay_queue.append(remote_now)

		var remote_delayed: Dictionary

		# If queue is long enough, pop delayed input
		if _remote_input_delay_queue.size() > simulated_remote_delay_frames:
			remote_delayed = _remote_input_delay_queue.pop_front()
		else:
			# Not enough history yet → empty input
			remote_delayed = {
				"mx": 0.0,
				"lean_l": false,
				"lean_r": false,
				"atk_l": false,
				"atk_h": false,
				"block": false,
				"dodge": false,
			}

		# Run simulation
		adapter.simulate(local, remote_delayed, PHYS_DT)

	# -----------------------------
	# VISUAL SYNC (ALWAYS RUNS)
	# -----------------------------
	if p1_placeholder:
		p1_placeholder.position = player_state.position
	if p2_placeholder:
		p2_placeholder.position = opponent_state.position

	# -----------------------------
	# SIMPLE WALL CHECK
	# -----------------------------
	var px := player_state.position.x
	var py := player_state.position.y
	var touching := (px <= 0.0) or (px >= 800.0) or (py <= 0.0) or (py >= 400.0)
	player_state.set_touching_wall(touching)

	# -----------------------------
	# CAMERA LEAN
	# -----------------------------
	var target := float(player_state.lean_direction) * LEAN_OFFSET
	_lean_vis_x = lerp(_lean_vis_x, target, clamp(LEAN_LERP_SPEED * delta, 0.0, 1.0))
	if cam:
		cam.offset = Vector2(_lean_vis_x, 0.0)

	# -----------------------------
	# UI UPDATES
	# -----------------------------
	_update_health_tint()
	_update_combat_debug_hud()
# ------------------------------------------------------------------
# Netplay callbacks
# ------------------------------------------------------------------
func _rn_collect() -> Dictionary:
	return _collect_p1_input()

func _rn_simulate(local: Dictionary, remote: Dictionary, dt: float) -> void:
	adapter.simulate(local, remote, dt)

func _rn_capture() -> Dictionary:
	return adapter.capture()

func _rn_restore(snapshot: Dictionary) -> void:
	adapter.restore(snapshot)


# ------------------------------------------------------------------
# Debug HUD update when using netplay
# ------------------------------------------------------------------
func _on_netplay_tick(frame_idx: int) -> void:
	if debug_tick_label:
		debug_tick_label.text = "Tick: %d" % frame_idx

	if debug_pos_label:
		debug_pos_label.text = "P1=(%.1f, %.1f)  P2=(%.1f, %.1f)" % [
			player_state.position.x, player_state.position.y,
			opponent_state.position.x, opponent_state.position.y
		]

	if debug_input_label:
		var mx := Input.get_action_strength("p1_right") - Input.get_action_strength("p1_left")
		debug_input_label.text = "Input mx: %.2f" % mx

	if debug_replay_label:
		debug_replay_label.text = "Mode: Netplay loopback"


# ---------------- Input collectors ----------------
func _collect_p1_input() -> Dictionary:
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

func _collect_p2_input() -> Dictionary:
	var mx := Input.get_action_strength("p2_right") - Input.get_action_strength("p2_left")
	return {
		"mx": mx,
		"lean_l": Input.is_action_pressed("lean_left_2"),
		"lean_r": Input.is_action_pressed("lean_right_2"),
		"atk_l": Input.is_action_just_pressed("jab_2"),
		"atk_h": Input.is_action_just_pressed("attack_heavy_2"),
		"block": Input.is_action_pressed("block_2"),
		"dodge": Input.is_action_just_pressed("dodge_2"),
	}
# ---------------- Visual HP cue ----------------
func _update_health_tint() -> void:
	if p1_placeholder:
		var g1: float = clamp(float(player_state.hp) / float(player_state.max_hp), 0.0, 1.0)
		p1_placeholder.modulate = Color(1.0, g1, g1, 1.0)
	if p2_placeholder:
		var g2: float = clamp(float(opponent_state.hp) / float(opponent_state.max_hp), 0.0, 1.0)
		p2_placeholder.modulate = Color(1.0, g2, g2, 1.0)
# ---------------- Additional Helper Functions ----------------
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
			
# ---------------- debug HUD updater  ----------------			
# ---------------- Line 1: state/frames/attack/hp ----------------
# ---------------- Line 2: block/active/hit-confirm flag ----------------
func _update_combat_debug_hud() -> void:
	if debug_pos_label:
		debug_pos_label.text = "P1 state=%s  frames=%d  atk=%s  hp=%d\nP2 state=%s  frames=%d  atk=%s  hp=%d" % [
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
		debug_input_label.text = "P1 block=%s active=%s hit_confirm=%s | P2 block=%s active=%s hit_confirm=%s" % [
			str(player_state.blocking),
			str(player_state.attack_active),
			str(player_state.hit_confirmed),
			str(opponent_state.blocking),
			str(opponent_state.attack_active),
			str(opponent_state.hit_confirmed)
		]
