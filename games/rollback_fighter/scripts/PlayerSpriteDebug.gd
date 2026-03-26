extends Sprite2D
class_name PlayerSpriteDebug

# Keep the ones that already work
@export var idle_frames: Array[String] = [
	"res://games/rollback_fighter/characters/example_fighter/sprites/idle_0.png",
	"res://games/rollback_fighter/characters/example_fighter/sprites/idle_1.png",
]

@export var jab_frames: Array[String] = [
	"res://games/rollback_fighter/characters/example_fighter/sprites/jab_0.png",
	"res://games/rollback_fighter/characters/example_fighter/sprites/jab_1.png",
]

# New ones: prefilled defaults, but you can still override in Inspector
@export var heavy_frames: Array[String] = [
	"res://games/rollback_fighter/characters/example_fighter/sprites/jab_0.png",
	"res://games/rollback_fighter/characters/example_fighter/sprites/jab_1.png",
]

@export var block_frames: Array[String] = [
	"res://games/rollback_fighter/characters/example_fighter/sprites/hero_block_0.png",
]

@export var dodge_frames: Array[String] = [
	"res://games/rollback_fighter/characters/example_fighter/sprites/hero_jump_1.png",
]

@export var hit_frames: Array[String] = [
	"res://games/rollback_fighter/characters/example_fighter/sprites/hero_hit_0.png",
]

@export var dead_frames: Array[String] = [
	"res://games/rollback_fighter/characters/example_fighter/sprites/hero_dead_0.png",
]

@export var idle_fps: float = 8.0
@export var jab_fps: float = 12.0
@export var heavy_fps: float = 10.0
@export var block_fps: float = 8.0
@export var dodge_fps: float = 12.0

@export var debug_label: String = "P?"

var _ps: Node = null

# Modes: idle / jab / heavy / block / dodge / hit / dead
var _mode: String = "idle"
var _t: float = 0.0
var _frame: int = 0
var _warned_missing: Dictionary = {}


func _ready() -> void:
	_apply_frame()


func bind_state(state: Node) -> void:
	_ps = state
	_set_mode("idle")
	print("[PlayerSpriteDebug %s] bound to state id=%s" % [debug_label, str(_ps.get_instance_id())])


func _process(delta: float) -> void:
	if _ps == null:
		return

	var wanted_mode: String = _choose_mode()

	if wanted_mode != _mode:
		_set_mode(wanted_mode)

	_t += delta

	var fps: float = _get_fps_for_mode(_mode)
	var frames: Array[String] = _get_frames_for_mode(_mode)
	var frame_time: float = 1.0 / maxf(fps, 0.001)

	while _t >= frame_time:
		_t -= frame_time
		_frame += 1

		var should_loop: bool = (_mode == "idle" or _mode == "block")

		if should_loop:
			if frames.size() > 0:
				_frame = _frame % frames.size()
		else:
			# hold on last frame until state changes
			if _frame >= frames.size():
				_frame = maxi(frames.size() - 1, 0)

	_apply_frame()

	# Optional facing flip if PlayerState has facing
	var facing_val: Variant = _ps.get("facing")
	if typeof(facing_val) == TYPE_INT:
		flip_h = int(facing_val) < 0


func _choose_mode() -> String:
	if _ps == null:
		return "idle"

	var state_val: Variant = _ps.get("state")
	var atk_kind_val: Variant = _ps.get("attack_kind")

	if typeof(state_val) != TYPE_INT:
		return "idle"

	var state_i: int = int(state_val)

	match state_i:
		PlayerState.MoveState.DEAD:
			return "dead"

		PlayerState.MoveState.HURT:
			return "hit"

		PlayerState.MoveState.BLOCK:
			return "block"

		PlayerState.MoveState.DODGE:
			return "dodge"

		PlayerState.MoveState.STARTUP, PlayerState.MoveState.ACTIVE, PlayerState.MoveState.RECOVERY:
			if typeof(atk_kind_val) == TYPE_INT:
				var atk_kind_i: int = int(atk_kind_val)
				match atk_kind_i:
					PlayerState.AttackKind.LIGHT:
						return "jab"
					PlayerState.AttackKind.HEAVY:
						if heavy_frames.is_empty():
							return "jab"
						return "heavy"
			return "idle"

		PlayerState.MoveState.IDLE:
			return "idle"

		_:
			return "idle"


func _get_frames_for_mode(mode: String) -> Array[String]:
	match mode:
		"idle":
			return idle_frames
		"jab":
			return jab_frames
		"heavy":
			return heavy_frames
		"block":
			return block_frames
		"dodge":
			return dodge_frames
		"hit":
			return hit_frames
		"dead":
			return dead_frames
		_:
			return idle_frames


func _get_fps_for_mode(mode: String) -> float:
	match mode:
		"idle":
			return idle_fps
		"jab":
			return jab_fps
		"heavy":
			return heavy_fps
		"block":
			return block_fps
		"dodge":
			return dodge_fps
		"hit":
			return 12.0
		"dead":
			return 1.0
		_:
			return idle_fps


func _set_mode(m: String) -> void:
	_mode = m
	_t = 0.0
	_frame = 0
	print("[PlayerSpriteDebug %s] mode -> %s" % [debug_label, _mode])
	_apply_frame()


func _apply_frame() -> void:
	var frames: Array[String] = _get_frames_for_mode(_mode)

	# Fallbacks so missing arrays don't break visuals
	if frames.is_empty():
		if _mode == "heavy":
			frames = jab_frames
		elif _mode == "hit":
			frames = hit_frames if not hit_frames.is_empty() else idle_frames
		elif _mode == "dead":
			frames = dead_frames if not dead_frames.is_empty() else idle_frames
		else:
			frames = idle_frames

	if frames.is_empty():
		return

	var idx: int = clampi(_frame, 0, frames.size() - 1)
	var path: String = frames[idx]

	if ResourceLoader.exists(path):
		var tex: Texture2D = load(path)
		if tex != null:
			texture = tex
	else:
		if not _warned_missing.has(path):
			_warned_missing[path] = true
			push_warning("[PlayerSpriteDebug %s] missing texture: %s" % [debug_label, path])
