extends Node2D
# ArenaScene.gd — split-controls local dev; optional rollback netplay loopback

const FORCE_SPLIT := true

@export var use_netplay: bool = false   # T3: toggle in Inspector

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

# Debug HUD (Tick / Pos / Input / Replay labels) for T5
@onready var debug_hud_root: Control      = get_node_or_null("DebugHUD/Control")
@onready var debug_tick_label: Label = \
	debug_hud_root.get_node("MarginContainer/VBoxContainer/TickLabel") \
	if debug_hud_root != null else null

@onready var debug_pos_label: Label = \
	debug_hud_root.get_node("MarginContainer/VBoxContainer/PosLabel") \
	if debug_hud_root != null else null

@onready var debug_input_label: Label = \
	debug_hud_root.get_node("MarginContainer/VBoxContainer/InputLabel") \
	if debug_hud_root != null else null

@onready var debug_replay_label: Label = \
	debug_hud_root.get_node("MarginContainer/VBoxContainer/ReplayLabel") \
	if debug_hud_root != null else null



# Optional UI (debug buttons / label)
@onready var attack_button: Button = get_node_or_null("AttackButton")
@onready var dodge_button: Button  = get_node_or_null("DodgeButton")
@onready var tick_label: Label     = get_node_or_null("FighterTickLabel")
var _tick: int = 0

# Rollback self-test config
const TEST_TOTAL_FRAMES := 10
const TEST_ROLLBACK_AT  := 5
const TEST_EPSILON      := 0.001

# Camera lean feel
const LEAN_OFFSET := 14.0
const LEAN_LERP_SPEED := 10.0
var _lean_vis_x := 0.0

var _using_net: bool = false
const PHYS_DT := 1.0 / 60.0


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

	# Mirror placeholder if needed
	if p2_placeholder == null and p1_placeholder:
		p2_placeholder = p1_placeholder.duplicate()
		p2_placeholder.name = "OpponentPlaceholder"
		add_child(p2_placeholder)

	# System wiring
	lean_system.player_state   = player_state
	combat_system.player_state = player_state
	combat_system.target_state = opponent_state

	# Adapter
	add_child(adapter)
	adapter.setup(player_state, opponent_state, input_system, lean_system, combat_system)

	# HUD hookup
	if hud:
		hud.set("p1_state", player_state)
		hud.set("p2_state", opponent_state)

	# Optional debug UI signals (avoid double-connecting)
	if attack_button and not attack_button.pressed.is_connected(_on_attack):
		attack_button.pressed.connect(_on_attack)
	if dodge_button and not dodge_button.pressed.is_connected(_on_dodge):
		dodge_button.pressed.connect(_on_dodge)

	# Mode selection
	if use_netplay:
		_setup_netplay()
	else:
		_using_net = false
		print("[Arena] Local split-controls mode (no networking).")
		print("[Arena] Ready. Using rollback plugin: ", _using_net)


# --------------------------------------------------------
# Netplay setup (uses autoload RollbackNetplaySingleton)
# --------------------------------------------------------
func _setup_netplay() -> void:
	# Autoload must be named "RollbackNetplaySingleton"
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

	# T5: hook debug HUD to netplay ticks
	if debug_tick_label and not rn.tick_advanced.is_connected(_on_netplay_tick):
		rn.tick_advanced.connect(_on_netplay_tick)

	rn.start(60, "fighter")
	_using_net = true

	print("[Arena] RollbackNetplay loopback enabled.")
	print("[Arena] Simulation is now driven by RollbackNetplaySingleton, not _physics_process().")


func _physics_process(delta: float) -> void:
	# When NOT using netplay, drive simulation locally.
	if not _using_net:
		var local:  Dictionary = _collect_p1_input()
		var remote: Dictionary = _collect_p2_input()
		adapter.simulate(local, remote, PHYS_DT)

	# Visual sync
	if p1_placeholder:
		p1_placeholder.position = player_state.position
	if p2_placeholder:
		p2_placeholder.position = opponent_state.position

	# Simple bounds/touching (visual-only)
	var px := player_state.position.x
	var py := player_state.position.y
	var touching := (px <= 0.0) or (px >= 800.0) or (py <= 0.0) or (py >= 400.0)
	player_state.set_touching_wall(touching)

	# Lean cam
	var target := float(player_state.lean_direction) * LEAN_OFFSET
	_lean_vis_x = lerp(_lean_vis_x, target, clamp(LEAN_LERP_SPEED * delta, 0.0, 1.0))
	if cam:
		cam.offset = Vector2(_lean_vis_x, 0.0)

	_update_health_tint()


# ------------------------------------------------------------------
# Netplay callbacks
# ------------------------------------------------------------------
func _rn_collect() -> Dictionary:
	# Treat P1 as local
	return _collect_p1_input()


func _rn_simulate(local: Dictionary, remote: Dictionary, dt: float) -> void:
	adapter.simulate(local, remote, dt)


func _rn_capture() -> Dictionary:
	return adapter.capture()


func _rn_restore(snapshot: Dictionary) -> void:
	adapter.restore(snapshot)


# ------------------------------------------------------------------
# Debug HUD update when using netplay (T5)
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
		# Very simple: just show last local mx value
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
		"atk_l": Input.is_action_just_pressed("light_attack"),
		"atk_h": Input.is_action_just_pressed("heavy_attack"),
	}


func _collect_p2_input() -> Dictionary:
	var mx := Input.get_action_strength("p2_right") - Input.get_action_strength("p2_left")
	return {
		"mx": mx,
		"lean_l": Input.is_action_pressed("lean_left_2"),
		"lean_r": Input.is_action_pressed("lean_right_2"),
		"atk_l": Input.is_action_just_pressed("attack_light_2"),
		"atk_h": Input.is_action_just_pressed("attack_heavy_2"),
	}


# ---------------- Visual HP cue ----------------
func _update_health_tint() -> void:
	if p1_placeholder:
		var g1: float = clamp(float(player_state.hp) / float(player_state.max_hp), 0.0, 1.0)
		p1_placeholder.modulate = Color(1.0, g1, g1, 1.0)
	if p2_placeholder:
		var g2: float = clamp(float(opponent_state.hp) / float(opponent_state.max_hp), 0.0, 1.0)
		p2_placeholder.modulate = Color(1.0, g2, g2, 1.0)


# --------------------------------------------------------
# Rollback correctness self-test (unchanged)
# --------------------------------------------------------
func _run_rollback_self_test() -> void:
	print("\n[RollbackTest] === Starting self-test ===")

	var start_snapshot: Dictionary = adapter.capture()

	var frame_inputs: Array = []
	var snapshot_at_rollback: Dictionary = {}
	var final_direct: Dictionary = {}

	for frame in range(TEST_TOTAL_FRAMES):
		var local_input:  Dictionary = _test_input_for_frame(frame, true)
		var remote_input: Dictionary = _test_input_for_frame(frame, false)

		var frame_dict: Dictionary = {
			"local": local_input,
			"remote": remote_input,
		}
		frame_inputs.append(frame_dict)

		adapter.simulate(local_input, remote_input, PHYS_DT)

		if frame == TEST_ROLLBACK_AT:
			snapshot_at_rollback = adapter.capture()

	final_direct = adapter.capture()
	print("[RollbackTest] Finished first pass. Snapshot at frame %d captured." % TEST_ROLLBACK_AT)

	adapter.restore(snapshot_at_rollback)

	for frame in range(TEST_ROLLBACK_AT + 1, TEST_TOTAL_FRAMES):
		var inputs_for_frame: Dictionary = frame_inputs[frame]
		var local2:  Dictionary = inputs_for_frame["local"]
		var remote2: Dictionary = inputs_for_frame["remote"]
		adapter.simulate(local2, remote2, PHYS_DT)

	var final_after_rollback: Dictionary = adapter.capture()

	var ok: bool = _compare_snapshots(final_direct, final_after_rollback)

	if ok:
		print("[RollbackTest] ✅ PASS — final state after rollback/resim matches direct run.")
	else:
		print("[RollbackTest] ❌ FAIL — mismatch after rollback/resim!")
		print("   Direct:   ", final_direct)
		print("   Resimmed: ", final_after_rollback)

	adapter.restore(start_snapshot)
	print("[RollbackTest] === Self-test complete ===\n")


func _test_input_for_frame(frame: int, is_local: bool) -> Dictionary:
	var mx: float = 0.0

	if is_local:
		if frame < TEST_TOTAL_FRAMES / 2:
			mx = 1.0
		else:
			mx = -1.0
	else:
		if frame >= 2 and frame < TEST_TOTAL_FRAMES - 1:
			mx = -1.0

	var press_light: bool = (frame == 3 and is_local)
	var press_heavy: bool = (frame == 7 and not is_local)

	return {
		"mx": mx,
		"lean_l": false,
		"lean_r": false,
		"atk_l": press_light,
		"atk_h": press_heavy,
	}


func _compare_snapshots(a: Dictionary, b: Dictionary) -> bool:
	for key in ["p1", "p2"]:
		var sa: Dictionary = a.get(key, {})
		var sb: Dictionary = b.get(key, {})

		if sa.is_empty() and sb.is_empty():
			continue

		if abs(float(sa.get("x", 0.0)) - float(sb.get("x", 0.0))) > TEST_EPSILON:
			return false
		if abs(float(sa.get("y", 0.0)) - float(sb.get("y", 0.0))) > TEST_EPSILON:
			return false
		if int(sa.get("lean", 0)) != int(sb.get("lean", 0)):
			return false
		if int(sa.get("hp", 0)) != int(sb.get("hp", 0)):
			return false

	return true


# ---------------- Optional debug buttons ----------------
func _on_attack() -> void:
	_tick += 1
	if tick_label:
		tick_label.text = "Tick: %d" % _tick


func _on_dodge() -> void:
	_tick += 1
	if tick_label:
		tick_label.text = "Tick: %d" % _tick


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("rollback_test"):
		_run_rollback_self_test()
