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

# Diagnostic-only canonical order:
# [display name, snapshot section, snapshot key].
const DEBUG_STATE_FIELDS := [
	["p1.position.x", "p1", "x"], ["p1.position.y", "p1", "y"],
	["p1.velocity.x", "p1", "vx"], ["p1.velocity.y", "p1", "vy"],
	["p1.ground_velocity_x", "p1", "gvx"],
	["p1.lean_direction", "p1", "lean"], ["p1.hp", "p1", "hp"],
	["p1.state", "p1", "st"], ["p1.frames_left", "p1", "stf"],
	["p1.attack_kind", "p1", "ak"], ["p1.attack_id", "p1", "aid"],
	["p1.hit_confirmed", "p1", "hc"], ["p1.facing", "p1", "fa"],
	["p1.blocking", "p1", "blk"], ["p1.invulnerable", "p1", "inv"],
	["p1.dodge_requested", "p1", "dreq"], ["p1.hurt_frames", "p1", "hurt"],
	["p1.attack_active", "p1", "aa"], ["p1.is_touching_wall", "p1", "wall"],

	["p2.position.x", "p2", "x"], ["p2.position.y", "p2", "y"],
	["p2.velocity.x", "p2", "vx"], ["p2.velocity.y", "p2", "vy"],
	["p2.ground_velocity_x", "p2", "gvx"],
	["p2.lean_direction", "p2", "lean"], ["p2.hp", "p2", "hp"],
	["p2.state", "p2", "st"], ["p2.frames_left", "p2", "stf"],
	["p2.attack_kind", "p2", "ak"], ["p2.attack_id", "p2", "aid"],
	["p2.hit_confirmed", "p2", "hc"], ["p2.facing", "p2", "fa"],
	["p2.blocking", "p2", "blk"], ["p2.invulnerable", "p2", "inv"],
	["p2.dodge_requested", "p2", "dreq"], ["p2.hurt_frames", "p2", "hurt"],
	["p2.attack_active", "p2", "aa"], ["p2.is_touching_wall", "p2", "wall"],

	["buffer.p1.light", "buf", "p1_l"], ["buffer.p1.heavy", "buf", "p1_h"],
	["buffer.p2.light", "buf", "p2_l"], ["buffer.p2.heavy", "buf", "p2_h"],

	["combat.hitstop", "combat", "hitstop"],
	["combat.light_cooldown.p1", "combat", "light_cd_1"],
	["combat.light_cooldown.p2", "combat", "light_cd_2"],
	["combat.heavy_cooldown.p1", "combat", "heavy_cd_1"],
	["combat.heavy_cooldown.p2", "combat", "heavy_cd_2"],
]

var _p1_light_buf: int = 0
var _p1_heavy_buf: int = 0
var _p2_light_buf: int = 0
var _p2_heavy_buf: int = 0

# Non-authoritative first-mismatch report retained for the benchmark summary.
var first_debug_frame: int = -1
var first_debug_field: String = ""
var first_debug_local: String = ""
var first_debug_remote: String = ""


func setup(_p1: PlayerState, _p2: PlayerState, _input: Node, _lean: Node, _combat: Node) -> void:
	p1_state = _p1
	p2_state = _p2
	input_sys = _input
	lean_sys  = _lean
	combat_sys = _combat


func simulate(local: Dictionary, remote: Dictionary, dt: float) -> void:
	_derive_wall_contact(p1_state)
	_derive_wall_contact(p2_state)

	# Update buffers first (deterministic tick-based)
	_update_buffers(local, remote)

	_apply(p1_state, local, dt, true)
	_apply(p2_state, remote, dt, false)

	if lean_sys and lean_sys.has_method("tick"):
		lean_sys.tick()
	if combat_sys and combat_sys.has_method("tick"):
		combat_sys.tick()


func _derive_wall_contact(ps: PlayerState) -> void:
	if ps == null:
		return

	ps.is_touching_wall = (
		ps.position.x <= 0.0
		or ps.position.x >= 800.0
		or ps.position.y <= 0.0
		or ps.position.y >= 400.0
	)


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


func canonical_debug_values(snapshot: Dictionary) -> Array:
	var values: Array = []

	for field_spec in DEBUG_STATE_FIELDS:
		var section: Dictionary = snapshot.get(str(field_spec[1]), {})
		values.append(section.get(str(field_spec[2])))

	return values


func canonical_checksum(snapshot: Dictionary) -> int:
	var checksum_values: Array = []

	for value in canonical_debug_values(snapshot):
		checksum_values.append(typeof(value))
		checksum_values.append(value)

	return checksum_values.hash()


func report_first_debug_difference(
	frame: int,
	local_snapshot: Dictionary,
	remote_values: Array
) -> void:
	var local_values: Array = canonical_debug_values(local_snapshot)
	var count: int = mini(local_values.size(), remote_values.size())

	for index in range(count):
		var local_value: Variant = local_values[index]
		var remote_value: Variant = remote_values[index]

		if (
			typeof(local_value) != typeof(remote_value)
			or local_value != remote_value
		):
			_print_debug_difference(
				frame,
				str(DEBUG_STATE_FIELDS[index][0]),
				local_value,
				remote_value
			)
			return

	if local_values.size() != remote_values.size():
		_print_debug_difference(
			frame,
			"canonical_field_count",
			local_values.size(),
			remote_values.size()
		)
		return

	_print_debug_difference(
		frame,
		"<none: all canonical fields match>",
		"canonical fields match",
		"canonical fields match"
	)


func _print_debug_difference(
	frame: int,
	field: String,
	local_value: Variant,
	remote_value: Variant
) -> void:
	first_debug_frame = frame
	first_debug_field = field
	first_debug_local = var_to_str(local_value)
	first_debug_remote = var_to_str(remote_value)

	print("")
	print("FIRST STATE DIVERGENCE")
	print("frame=%d" % frame)
	print("field=%s" % field)
	print("local=%s" % var_to_str(local_value))
	print("remote=%s" % var_to_str(remote_value))
	print("")


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
		"gvx": ps.ground_velocity_x,

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

# rollback-critical transient flags
"aa": ps.attack_active,
"wall": ps.is_touching_wall,
	}


func _restore(ps: PlayerState, d: Dictionary) -> void:
	if ps == null or d.is_empty():
		return

	ps.position = Vector2(float(d.get("x", 0.0)), float(d.get("y", 0.0)))
	ps.vel      = Vector2(float(d.get("vx", 0.0)), float(d.get("vy", 0.0)))
	ps.ground_velocity_x = float(d.get("gvx", 0.0))

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
	ps.hurt_frames = int(d.get("hurt", 0))

	# rollback-critical transient flags
	ps.attack_active = bool(d.get("aa", false))
	ps.is_touching_wall = bool(d.get("wall", false))
