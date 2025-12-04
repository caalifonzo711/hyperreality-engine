extends Node2D

# --- UI on the scene (auto-found by name under FighterArena) ---
var attack_button: Button
var dodge_button: Button
var tick_label: Label

# --- Runtime-created states (spawned by ArenaScene.gd) ---
var p1_state: PlayerState
var p2_state: PlayerState

# --- Round control ---
@export var round_time_sec := 60
@export var p1_spawn := Vector2(200, 250)
@export var p2_spawn := Vector2(600, 250)

var _time_left := 0.0
var _round_active := false
var _tick := 0

func _ready() -> void:
	# Find UI nodes that already exist in the FighterArena scene
	var root := get_parent() # FighterArena
	attack_button = root.get_node_or_null("AttackButton")
	dodge_button  = root.get_node_or_null("DodgeButton")
	tick_label    = root.get_node_or_null("FighterTickLabel")

	if attack_button: attack_button.pressed.connect(_on_attack)
	if dodge_button:  dodge_button.pressed.connect(_on_dodge)
	_update_tick_label()

	# Wait until ArenaScene has created P1State/P2State this frame
	await get_tree().process_frame
	# Poll a few frames in case ordering flips on reload
	for i in 4:
		p1_state = root.get_node_or_null("P1State")
		p2_state = root.get_node_or_null("P2State")
		if p1_state and p2_state:
			break
		await get_tree().process_frame

	if not (p1_state and p2_state):
		push_warning("FighterGameManager: could not find P1State/P2State. Did you set names in ArenaScene.gd?")
		return

	_start_round()

func _process(delta: float) -> void:
	if not _round_active:
		return
	_time_left -= delta
	if _time_left <= 0.0 or p1_state.hp <= 0 or p2_state.hp <= 0:
		_end_round()

# ----------------- Round helpers -----------------
func _start_round() -> void:
	_round_active = true
	_time_left = float(round_time_sec)

	# Reset/respawn
	if p1_state:
		p1_state.hp = p1_state.max_hp
		p1_state.position = p1_spawn
	if p2_state:
		p2_state.hp = p2_state.max_hp
		p2_state.position = p2_spawn

func _end_round() -> void:
	_round_active = false
	# brief pause, then restart
	get_tree().create_timer(1.0).timeout.connect(_start_round)

# ----------------- Buttons / ticks -----------------
func _on_attack() -> void:
	_tick += 1
	print("Attack pressed at Tick %d" % _tick)
	_update_tick_label()

func _on_dodge() -> void:
	_tick += 1
	print("Dodge pressed at Tick %d" % _tick)
	_update_tick_label()

func _update_tick_label() -> void:
	if tick_label:
		tick_label.text = "Tick: %d" % _tick
