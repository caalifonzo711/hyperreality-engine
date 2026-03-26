extends Node
class_name FighterRollbackAdapter

# Player state refs (wired by ArenaScene)
var p1_state: PlayerState
var p2_state: PlayerState
var input_sys: Node
var lean_sys: Node
var combat_sys: Node

# ----------------------------
# Deterministic input buffering
# ----------------------------
const LIGHT_BUFFER_FRAMES: int = 3
const HEAVY_BUFFER_FRAMES: int = 3

var _p1_light_buf: int = 0
var _p1_heavy_buf: int = 0
var _p2_light_buf: int = 0
var _p2_heavy_buf: int = 0


func setup(_p1: PlayerState, _p2: PlayerState, _input: Node, _lean: Node, _combat: Node) -> void:
	p1_state = _p1
	p2_state = _p2
	input_sys = _input
	lean_sys  = _lean
	combat_sys = _combat


func simulate(local: Dictionary, remote: Dictionary, dt: float) -> void:
	# Update buffers first (deterministic tick-based)
	_update_buffers(local, remote)

	_apply(p1_state, local, dt, true)
	_apply(p2_state, remote, dt, false)

	if lean_sys and lean_sys.has_method("tick"):
		lean_sys.tick()
	if combat_sys and combat_sys.has_method("tick"):
		combat_sys.tick()


func _update_buffers(local: Dictionary, remote: Dictionary) -> void:
	# If input says "atk_l/atk_h" this frame, prime the buffer
	if bool(local.get("atk_l", false)):
		_p1_light_buf = LIGHT_BUFFER_FRAMES
	if bool(local.get("atk_h", false)):
		_p1_heavy_buf = HEAVY_BUFFER_FRAMES

	if bool(remote.get("atk_l", false)):
		_p2_light_buf = LIGHT_BUFFER_FRAMES
	if bool(remote.get("atk_h", false)):
		_p2_heavy_buf = HEAVY_BUFFER_FRAMES


func _consume_buffer(is_p1: bool) -> Dictionary:
	var wants_light: bool = false
	var wants_heavy: bool = false

	if is_p1:
		if _p1_light_buf > 0:
			wants_light = true
			_p1_light_buf -= 1
		if _p1_heavy_buf > 0:
			wants_heavy = true
			_p1_heavy_buf -= 1
	else:
		if _p2_light_buf > 0:
			wants_light = true
			_p2_light_buf -= 1
		if _p2_heavy_buf > 0:
			wants_heavy = true
			_p2_heavy_buf -= 1

	return {"atk_l": wants_light, "atk_h": wants_heavy}


func _apply(ps: PlayerState, inp: Dictionary, dt: float, is_p1: bool) -> void:
	if ps == null:
		return

	# Normalize to what PlayerState.apply_input() expects
	var move_vec: Vector2 = Vector2.ZERO
	if inp.has("move") and inp["move"] is Vector2:
		move_vec = inp["move"]
	elif inp.has("mx"):
		move_vec = Vector2(float(inp["mx"]), 0.0)

	# Deterministic buffered attacks (Option A stays in adapter)
	var wants: Dictionary = _consume_buffer(is_p1)

	var payload := {
		"move":   move_vec,
		"atk_l":  bool(wants["atk_l"]),
		"atk_h":  bool(wants["atk_h"]),
		"block":  bool(inp.get("block", false)),
		"dodge":  bool(inp.get("dodge", false)),
		"lean_l": bool(inp.get("lean_l", false)),
		"lean_r": bool(inp.get("lean_r", false)),
	}

	ps.apply_input(payload, dt)


# --- rollback snapshots ---
func capture() -> Dictionary:
	return {
		"p1": _snap(p1_state),
		"p2": _snap(p2_state),

		"buf": {
			"p1_l": _p1_light_buf,
			"p1_h": _p1_heavy_buf,
			"p2_l": _p2_light_buf,
			"p2_h": _p2_heavy_buf,
		},

		"combat": combat_sys.capture_state() if combat_sys and combat_sys.has_method("capture_state") else {}
	}


func restore(s: Dictionary) -> void:
	_restore(p1_state, s.get("p1", {}))
	_restore(p2_state, s.get("p2", {}))

	var b: Dictionary = s.get("buf", {})
	_p1_light_buf = int(b.get("p1_l", 0))
	_p1_heavy_buf = int(b.get("p1_h", 0))
	_p2_light_buf = int(b.get("p2_l", 0))
	_p2_heavy_buf = int(b.get("p2_h", 0))

	if combat_sys and combat_sys.has_method("restore_state"):
		combat_sys.restore_state(s.get("combat", {}))


func _snap(ps: PlayerState) -> Dictionary:
	if ps == null:
		return {}

	return {
		# core kinematics
		"x":  ps.position.x,
		"y":  ps.position.y,
		"vx": ps.vel.x,
		"vy": ps.vel.y,

		# gameplay state
		"lean": ps.lean_direction,
		"hp":   ps.hp,

		# state machine fields
		"st":  ps.state,
		"stf": ps.frames_left,
		"ak":  ps.attack_kind,
		"aid": ps.attack_id,
		"hc":  ps.hit_confirmed,
		"fa":  ps.facing,
		
		# blocking
		"blk": ps.blocking,
		
		# dodging
		"inv": ps.invulnerable,
		"dreq": ps.dodge_requested,
		
		# hurt ouchie
		"hurt": ps.hurt_frames,
	}


func _restore(ps: PlayerState, d: Dictionary) -> void:
	if ps == null or d.is_empty():
		return

	ps.position = Vector2(float(d.get("x", 0.0)), float(d.get("y", 0.0)))
	ps.vel      = Vector2(float(d.get("vx", 0.0)), float(d.get("vy", 0.0)))

	ps.lean_direction = int(d.get("lean", 0))
	ps.hp             = int(d.get("hp", ps.hp))

	ps.state        = int(d.get("st", ps.state))
	ps.frames_left  = int(d.get("stf", ps.frames_left))
	ps.attack_kind  = int(d.get("ak", ps.attack_kind))
	ps.attack_id    = int(d.get("aid", ps.attack_id))
	ps.hit_confirmed = bool(d.get("hc", ps.hit_confirmed))
	ps.facing       = int(d.get("fa", ps.facing))
	
	#blocking bool
	ps.blocking = bool(d.get("blk", false))
	
	# dodging
	ps.blocking       = bool(d.get("blk", false))
	ps.invulnerable   = bool(d.get("inv", false))
	ps.dodge_requested = bool(d.get("dreq", false))
	
	#hurt owie
	ps.hurt_frames    = int(d.get("hurt", 0))
