extends Node
class_name FighterRollbackAdapter

# --- Input buffering config ---
const INPUT_BUFFER_FRAMES : int = 3  # tweak to 2/3/4 frames if you want

# Player state refs (wired by ArenaScene)
var p1_state
var p2_state
var input_sys: Node
var lean_sys: Node
var combat_sys: Node

# Small per-player attack buffers
var _p1_atk_l_buffer : int = 0
var _p1_atk_h_buffer : int = 0
var _p2_atk_l_buffer : int = 0
var _p2_atk_h_buffer : int = 0


func setup(_p1, _p2, _input, _lean, _combat) -> void:
	p1_state = _p1
	p2_state = _p2
	input_sys = _input
	lean_sys  = _lean
	combat_sys = _combat


# Optional local collector (unused in ArenaScene right now, but kept for dev)
func collect_input() -> Dictionary:
	var mx: float = Input.get_action_strength("ui_right") - Input.get_action_strength("ui_left")
	return {
		"move":   Vector2(mx, 0.0),
		"lean_l": Input.is_action_pressed("lean_left"),
		"lean_r": Input.is_action_pressed("lean_right"),
		"atk_l":  Input.is_action_just_pressed("light_attack"),
		"atk_h":  Input.is_action_just_pressed("heavy_attack"),
	}


func simulate(local: Dictionary, remote: Dictionary, dt: float) -> void:
	# Apply per-player input buffering first
	var local_buf  : Dictionary = _apply_attack_buffer(local,  true)
	var remote_buf : Dictionary = _apply_attack_buffer(remote, false)

	# Then feed the buffered inputs into PlayerState
	_apply(p1_state, local_buf, dt)
	_apply(p2_state, remote_buf, dt)

	if lean_sys:
		lean_sys.tick()
	if combat_sys:
		combat_sys.tick()


# Apply movement + buttons to a PlayerState
func _apply(ps, inp: Dictionary, dt: float) -> void:
	if not inp:
		return

	# Normalize to what PlayerState.apply_input() expects
	var move_vec: Vector2 = Vector2.ZERO
	if inp.has("move"):
		var mv: Variant = inp["move"]
		if mv is Vector2:
			move_vec = mv
		else:
			move_vec = Vector2(float(mv), 0.0)
	elif inp.has("mx"):
		move_vec = Vector2(float(inp["mx"]), 0.0)

	var payload := {
		"move":   move_vec,
		"atk_l":  inp.get("atk_l", false),
		"atk_h":  inp.get("atk_h", false),
		"lean_l": inp.get("lean_l", false),
		"lean_r": inp.get("lean_r", false),
	}

	var before_x: float = float(ps.position.x)

	if ps.has_method("apply_input"):
		ps.apply_input(payload, dt)

	# Visual fallback (so you SEE motion even if PlayerState ignores input)
	if abs(float(ps.position.x) - before_x) < 0.0001:
		var SPEED: float = 180.0
		ps.position.x = float(ps.position.x) + move_vec.x * SPEED * dt


# --- Attack input buffering -----------------------------------

func _apply_attack_buffer(inp: Dictionary, is_p1: bool) -> Dictionary:
	# Start from the incoming dictionary
	var out: Dictionary = inp.duplicate()

	# Current frame raw button presses
	var atk_l_now: bool = bool(inp.get("atk_l", false))
	var atk_h_now: bool = bool(inp.get("atk_h", false))

	if is_p1:
		# Load / update P1 counters
		if atk_l_now:
			_p1_atk_l_buffer = INPUT_BUFFER_FRAMES
		if atk_h_now:
			_p1_atk_h_buffer = INPUT_BUFFER_FRAMES

		var use_atk_l: bool = _p1_atk_l_buffer > 0
		var use_atk_h: bool = _p1_atk_h_buffer > 0

		if _p1_atk_l_buffer > 0:
			_p1_atk_l_buffer -= 1
		if _p1_atk_h_buffer > 0:
			_p1_atk_h_buffer -= 1

		out["atk_l"] = use_atk_l
		out["atk_h"] = use_atk_h
	else:
		# P2 side
		if atk_l_now:
			_p2_atk_l_buffer = INPUT_BUFFER_FRAMES
		if atk_h_now:
			_p2_atk_h_buffer = INPUT_BUFFER_FRAMES

		var use_atk_l2: bool = _p2_atk_l_buffer > 0
		var use_atk_h2: bool = _p2_atk_h_buffer > 0

		if _p2_atk_l_buffer > 0:
			_p2_atk_l_buffer -= 1
		if _p2_atk_h_buffer > 0:
			_p2_atk_h_buffer -= 1

		out["atk_l"] = use_atk_l2
		out["atk_h"] = use_atk_h2

	return out


# --- rollback snapshots (now also store buffer state) ---------

func capture() -> Dictionary:
	return {
		"p1": _snap(p1_state),
		"p2": _snap(p2_state),
		"buf": {
			"p1_atk_l": _p1_atk_l_buffer,
			"p1_atk_h": _p1_atk_h_buffer,
			"p2_atk_l": _p2_atk_l_buffer,
			"p2_atk_h": _p2_atk_h_buffer,
		}
	}


func restore(s: Dictionary) -> void:
	_restore(p1_state, s.get("p1", {}))
	_restore(p2_state, s.get("p2", {}))

	var buf: Dictionary = s.get("buf", {})
	_p1_atk_l_buffer = int(buf.get("p1_atk_l", 0))
	_p1_atk_h_buffer = int(buf.get("p1_atk_h", 0))
	_p2_atk_l_buffer = int(buf.get("p2_atk_l", 0))
	_p2_atk_h_buffer = int(buf.get("p2_atk_h", 0))


func _snap(ps) -> Dictionary:
	return {
		"x":    ps.position.x,
		"y":    ps.position.y,
		"lean": ps.lean_direction,
		"hp":   ps.hp,
	}


func _restore(ps, d: Dictionary) -> void:
	if d.is_empty():
		return
	ps.position       = Vector2(d["x"], d["y"])
	ps.lean_direction = d["lean"]
	ps.hp             = d["hp"]
