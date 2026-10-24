extends Sprite2D
class_name PlayerSpriteDebug

@export var debug_label: String = "P?"

var _ps: Node = null
var _presentation: RollbackFighterPresentationDefinition = null
var _dodge_total_frames: int = 0
var _animation_id: String = ""
var _animation_data: Dictionary = {}
var _t: float = 0.0
var _frame: int = 0
var _warned_missing: Dictionary = {}
var _texture_cache: Dictionary = {}


func bind_state(
	state: Node,
	presentation: RollbackFighterPresentationDefinition,
	dodge_total_frames: int
) -> void:
	_ps = state
	_presentation = presentation
	_dodge_total_frames = dodge_total_frames
	_set_animation(_presentation.get_state_animation_id("idle"))
	print("[PlayerSpriteDebug %s] bound to state id=%s" % [
		debug_label,
		str(_ps.get_instance_id()),
	])


func get_debug_visual_state() -> Dictionary:
	var texture_size := Vector2.ZERO
	if texture != null:
		texture_size = texture.get_size()

	return {
		"mode": _animation_id,
		"frame": _frame,
		"texture_size": texture_size,
		"offset": offset,
		"scale": scale,
	}


func _process(delta: float) -> void:
	if _ps == null or _presentation == null:
		return

	var wanted_animation: String = _choose_animation()
	if wanted_animation != _animation_id:
		_set_animation(wanted_animation)

	var state_val: Variant = _ps.get("state")
	if (
		typeof(state_val) == TYPE_INT
		and int(state_val) == PlayerState.MoveState.IDLE
		and str(_animation_data.get("playback", "")) == "loop_fps"
	):
		_advance_loop_animation(delta)
	else:
		_frame = _get_state_driven_frame()

	var facing_val: Variant = _ps.get("facing")
	if typeof(facing_val) == TYPE_INT:
		var faces_right: bool = int(facing_val) > 0
		flip_h = (
			faces_right
			if _presentation.get_source_art_faces() == "left"
			else not faces_right
		)

	_apply_frame()


func _advance_loop_animation(delta: float) -> void:
	var frames: Array = _animation_data.get("frames", [])
	if frames.is_empty():
		_frame = 0
		return

	_t += delta
	var fps: float = float(int(_animation_data.get("fps_milli", 1))) / 1000.0
	var frame_time: float = 1.0 / maxf(fps, 0.001)
	while _t >= frame_time:
		_t -= frame_time
		_frame = (_frame + 1) % frames.size()


func _get_state_driven_frame() -> int:
	var frames: Array = _animation_data.get("frames", [])
	if frames.is_empty() or _ps == null:
		return 0

	var playback: String = str(_animation_data.get("playback", ""))
	if playback == "state_stretched":
		return _get_stretched_state_frame(frames.size())
	if playback == "attack_phase_map":
		return _get_attack_phase_frame(frames.size())
	return 0


func _get_stretched_state_frame(frame_count: int) -> int:
	var frames_left_val: Variant = _ps.get("frames_left")
	if typeof(frames_left_val) != TYPE_INT or _dodge_total_frames <= 0:
		return 0
	var elapsed: int = maxi(_dodge_total_frames - int(frames_left_val), 0)
	var stretched_index: int = int(
		(elapsed * frame_count) / _dodge_total_frames
	)
	return clampi(stretched_index, 0, frame_count - 1)


func _get_attack_phase_frame(frame_count: int) -> int:
	var state_val: Variant = _ps.get("state")
	var attack_kind_val: Variant = _ps.get("attack_kind")
	var frames_left_val: Variant = _ps.get("frames_left")
	if (
		typeof(state_val) != TYPE_INT
		or typeof(attack_kind_val) != TYPE_INT
		or typeof(frames_left_val) != TYPE_INT
	):
		return 0

	var phase: String = _attack_phase_for_state(int(state_val))
	if phase.is_empty():
		return 0
	var phase_frames: Array[int] = _presentation.get_attack_phase_frames(
		_animation_id,
		phase
	)
	if phase_frames.is_empty():
		return 0

	var move_variant: Variant = _ps.call("get_attack_move", int(attack_kind_val))
	if not move_variant is RollbackFighterMoveDefinition:
		return clampi(phase_frames[0], 0, frame_count - 1)
	var move: RollbackFighterMoveDefinition = move_variant
	var phase_duration: int = maxi(move.get_int(phase), 1)
	var elapsed: int = maxi(phase_duration - int(frames_left_val), 0)
	var mapped_index: int = int(
		(elapsed * phase_frames.size()) / phase_duration
	)
	mapped_index = clampi(mapped_index, 0, phase_frames.size() - 1)
	return clampi(phase_frames[mapped_index], 0, frame_count - 1)


func _attack_phase_for_state(state: int) -> String:
	match state:
		PlayerState.MoveState.STARTUP:
			return "startup"
		PlayerState.MoveState.ACTIVE:
			return "active"
		PlayerState.MoveState.RECOVERY:
			return "recovery"
		_:
			return ""


func _choose_animation() -> String:
	var state_val: Variant = _ps.get("state")
	if typeof(state_val) != TYPE_INT:
		return _presentation.get_state_animation_id("idle")

	match int(state_val):
		PlayerState.MoveState.DEAD:
			return _presentation.get_state_animation_id("dead")
		PlayerState.MoveState.HURT:
			return _presentation.get_state_animation_id("hurt")
		PlayerState.MoveState.BLOCK:
			return _presentation.get_state_animation_id("block")
		PlayerState.MoveState.DODGE:
			return _presentation.get_state_animation_id("dodge")
		PlayerState.MoveState.STARTUP, PlayerState.MoveState.ACTIVE, PlayerState.MoveState.RECOVERY:
			var attack_kind_val: Variant = _ps.get("attack_kind")
			if typeof(attack_kind_val) == TYPE_INT:
				var move_variant: Variant = _ps.call(
					"get_attack_move",
					int(attack_kind_val)
				)
				if move_variant is RollbackFighterMoveDefinition:
					var move: RollbackFighterMoveDefinition = move_variant
					return move.get_animation_id()
			return ""
		_:
			return _presentation.get_state_animation_id("idle")


func _set_animation(animation_id: String) -> void:
	_animation_id = animation_id
	_animation_data = (
		_presentation.get_animation(animation_id)
		if _presentation != null
		else {}
	)
	_t = 0.0
	_frame = 0
	print("[PlayerSpriteDebug %s] mode -> %s" % [debug_label, _animation_id])
	_apply_frame()


func _apply_frame() -> void:
	var frames: Array = _animation_data.get("frames", [])
	if frames.is_empty():
		texture = null
		_warn_once("animation:%s" % _animation_id, "missing animation frames")
		return

	var idx: int = clampi(_frame, 0, frames.size() - 1)
	var frame_data: Dictionary = frames[idx]
	var path: String = str(frame_data.get("sprite", ""))
	var tex: Texture2D = _texture_cache.get(path) as Texture2D
	if tex == null and ResourceLoader.exists(path):
		tex = ResourceLoader.load(path) as Texture2D
		if tex != null:
			_texture_cache[path] = tex
	if tex == null:
		texture = null
		_warn_once(path, "missing texture: %s" % path)
		return

	texture = tex
	_apply_presentation(frame_data, tex)


func _apply_presentation(frame_data: Dictionary, tex: Texture2D) -> void:
	centered = true
	var texture_size: Vector2 = tex.get_size()
	var feet_data: Dictionary = frame_data["feet_anchor"]
	var feet := Vector2(
		float(int(feet_data["x"])),
		float(int(feet_data["y"]))
	)
	var visual_scale: float = float(int(frame_data["scale_milli"])) / 1000.0

	# With a centered Sprite2D, source pixel P is drawn at P - size/2.
	# Mirror the horizontal offset with the artwork so the authored feet point
	# remains anchored to the authoritative fighter origin in both facings.
	var anchor_offset: Vector2 = texture_size * 0.5 - feet
	if flip_h:
		anchor_offset.x = -anchor_offset.x
	offset = anchor_offset
	scale = Vector2.ONE * visual_scale


func _warn_once(key: String, message: String) -> void:
	if _warned_missing.has(key):
		return
	_warned_missing[key] = true
	push_warning("[PlayerSpriteDebug %s] %s" % [debug_label, message])
