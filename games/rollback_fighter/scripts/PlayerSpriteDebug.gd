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

# Presentation-only metadata. Each feet anchor is expressed in source-image
# pixels. The scale normalizes the visible fighter body to roughly the same
# 48-pixel gameplay height without modifying the source PNGs.
const FRAME_PRESENTATION := {
	"res://games/rollback_fighter/characters/example_fighter/sprites/idle_0.png": {
		"feet": Vector2(288.0, 416.0),
		"scale": 0.135,
	},
	"res://games/rollback_fighter/characters/example_fighter/sprites/idle_1.png": {
		"feet": Vector2(288.0, 416.0),
		"scale": 0.135,
	},
	"res://games/rollback_fighter/characters/example_fighter/sprites/jab_0.png": {
		"feet": Vector2(646.0, 589.0),
		"scale": 0.108,
	},
	"res://games/rollback_fighter/characters/example_fighter/sprites/jab_1.png": {
		"feet": Vector2(647.0, 589.0),
		"scale": 0.108,
	},
	"res://games/rollback_fighter/characters/example_fighter/sprites/hero_block_0.png": {
		"feet": Vector2(279.0, 416.0),
		"scale": 0.135,
	},
	"res://games/rollback_fighter/characters/example_fighter/sprites/hero_jump_1.png": {
		"feet": Vector2(254.0, 348.0),
		"scale": 0.172,
	},
	"res://games/rollback_fighter/characters/example_fighter/sprites/hero_hit_0.png": {
		"feet": Vector2(284.0, 402.0),
		"scale": 0.138,
	},
	"res://games/rollback_fighter/characters/example_fighter/sprites/hero_dead_0.png": {
		"feet": Vector2(252.0, 471.0),
		"scale": 0.118,
	},
}

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


func get_debug_visual_state() -> Dictionary:
	var texture_size := Vector2.ZERO
	if texture != null:
		texture_size = texture.get_size()

	return {
		"mode": _mode,
		"frame": _frame,
		"texture_size": texture_size,
		"offset": offset,
		"scale": scale,
	}


func _process(delta: float) -> void:
	if _ps == null:
		return

	var wanted_mode: String = _choose_mode()

	if wanted_mode != _mode:
		_set_mode(wanted_mode)

	if _mode == "idle":
		_advance_idle_animation(delta)
	else:
		_frame = _get_authoritative_visual_frame()

	# The source artwork faces left, so positive gameplay facing must flip it.
	var facing_val: Variant = _ps.get("facing")
	if typeof(facing_val) == TYPE_INT:
		flip_h = int(facing_val) > 0

	_apply_frame()


func _advance_idle_animation(delta: float) -> void:
	_t += delta

	var frames: Array[String] = _get_frames_for_mode("idle")
	if frames.is_empty():
		_frame = 0
		return

	var frame_time: float = 1.0 / maxf(idle_fps, 0.001)
	while _t >= frame_time:
		_t -= frame_time
		_frame = (_frame + 1) % frames.size()


func _get_authoritative_visual_frame() -> int:
	if _ps == null:
		return 0

	if _mode != "jab" and _mode != "heavy":
		return 0

	var state_val: Variant = _ps.get("state")
	if typeof(state_val) != TYPE_INT:
		return 0

	# Startup and recovery use pose 0. The extended pose is shown only while
	# the deterministic simulation says the attack is active.
	if int(state_val) == PlayerState.MoveState.ACTIVE:
		var frames: Array[String] = _get_frames_for_mode(_mode)
		return mini(1, maxi(frames.size() - 1, 0))

	return 0


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
			_apply_presentation(path, tex)
	else:
		if not _warned_missing.has(path):
			_warned_missing[path] = true
			push_warning("[PlayerSpriteDebug %s] missing texture: %s" % [debug_label, path])


func _apply_presentation(path: String, tex: Texture2D) -> void:
	centered = true

	var texture_size: Vector2 = tex.get_size()
	var presentation: Dictionary = FRAME_PRESENTATION.get(path, {})
	var feet: Vector2 = presentation.get(
		"feet",
		texture_size * 0.5
	)
	var visual_scale: float = float(presentation.get("scale", 1.0))

	# With a centered Sprite2D, source pixel P is drawn at P - size/2.
	# Offset the authored feet pixel to the parent origin. Sprite2D flips the
	# texture inside its draw rectangle, so the horizontal offset must mirror
	# with the artwork to keep the same feet point anchored in both facings.
	var anchor_offset: Vector2 = texture_size * 0.5 - feet
	if flip_h:
		anchor_offset.x = -anchor_offset.x
	offset = anchor_offset
	scale = Vector2.ONE * visual_scale
