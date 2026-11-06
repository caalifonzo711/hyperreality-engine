extends Control
class_name MainMenuBackgroundPlayer

const PLAYLIST_PATH := "res://games/rollback_fighter/fighter_assets/main_menu/generated/playlist.json"
const STATIC_FALLBACK_PATH := "res://games/rollback_fighter/fighter_assets/main_menu/Screenshot 2026-04-29 200632.png"
const STATIC_HOLD_SECONDS := 3.0
const GLITCH_DURATION_SECONDS := 0.08
const MINIMUM_FRAME_SECONDS := 0.02

var _background: TextureRect
var _glitch: ColorRect
var _timestamp: Label
var _clips: Array[Dictionary] = []
var _static_texture: Texture2D
var _clip_index: int = -1
var _frame_index: int = 0
var _remaining_seconds: float = 0.0
var _pending_mode: String = ""
var _mode: String = "fallback"


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_layers()
	_load_playlist()
	_show_static()
	set_process(true)


func _process(delta: float) -> void:
	_update_timestamp()
	if _mode == "fallback":
		return
	_remaining_seconds -= delta
	while _remaining_seconds <= 0.0:
		var overshoot: float = -_remaining_seconds
		match _mode:
			"static":
				_begin_transition("clip")
			"clip":
				_advance_frame()
			"glitch":
				_finish_transition()
			_:
				return
		_remaining_seconds -= overshoot


func _build_layers() -> void:
	_background = TextureRect.new()
	_background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_background)

	var shade: ColorRect = ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.0, 0.0, 0.0, 0.12)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)

	_glitch = ColorRect.new()
	_glitch.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_glitch.color = Color(0.82, 0.88, 0.86, 0.25)
	_glitch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_glitch.visible = false
	add_child(_glitch)

	var rec: Label = Label.new()
	rec.position = Vector2(22.0, 18.0)
	rec.text = "● REC"
	rec.modulate = Color(1.0, 0.25, 0.22, 0.9)
	rec.add_theme_font_size_override("font_size", 16)
	rec.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(rec)

	_timestamp = Label.new()
	_timestamp.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_timestamp.position = Vector2(-235.0, -46.0)
	_timestamp.size = Vector2(215.0, 28.0)
	_timestamp.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_timestamp.add_theme_font_size_override("font_size", 14)
	_timestamp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_timestamp)


func _load_playlist() -> void:
	_static_texture = _load_texture(STATIC_FALLBACK_PATH)
	var file: FileAccess = FileAccess.open(PLAYLIST_PATH, FileAccess.READ)
	if file == null:
		push_warning("[MainMenuBackgroundPlayer] Playlist is unavailable; using the static fallback.")
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary:
		push_warning("[MainMenuBackgroundPlayer] Playlist is corrupt; using the static fallback.")
		return
	var manifest: Dictionary = parsed
	var manifest_static: Texture2D = _load_texture(str(manifest.get("static_image", "")))
	if manifest_static != null:
		_static_texture = manifest_static
	var clips_value: Variant = manifest.get("clips", [])
	if clips_value is Array:
		for clip_value: Variant in clips_value:
			var clip: Dictionary = _validated_clip(clip_value)
			if not clip.is_empty():
				_clips.append(clip)


func _validated_clip(value: Variant) -> Dictionary:
	if not value is Dictionary:
		return {}
	var source: Dictionary = value
	var valid_frames: Array[Dictionary] = []
	var frames_value: Variant = source.get("frames", [])
	if frames_value is Array:
		for frame_value: Variant in frames_value:
			if not frame_value is Dictionary:
				continue
			var path: String = str(frame_value.get("path", ""))
			var texture: Texture2D = _load_texture(path)
			if texture == null:
				continue
			valid_frames.append({
				"texture": texture,
				"duration_seconds": maxf(float(frame_value.get("duration_seconds", 0.1)), MINIMUM_FRAME_SECONDS),
			})
	if valid_frames.is_empty():
		push_warning("[MainMenuBackgroundPlayer] Skipping unusable clip: %s" % str(source.get("source_filename", "unknown")))
		return {}
	return {
		"clip_id": str(source.get("clip_id", "")),
		"source_filename": str(source.get("source_filename", "")),
		"frames": valid_frames,
	}


func _load_texture(path: String) -> Texture2D:
	if not path.begins_with("res://games/rollback_fighter/fighter_assets/main_menu/"):
		return null
	if not ResourceLoader.exists(path):
		return null
	var resource: Resource = load(path)
	return resource as Texture2D


func _show_static() -> void:
	_glitch.visible = false
	if _static_texture != null:
		_background.texture = _static_texture
	_mode = "static" if not _clips.is_empty() else "fallback"
	_remaining_seconds = STATIC_HOLD_SECONDS
	_clip_index = -1
	_frame_index = 0


func _begin_transition(next_mode: String) -> void:
	_pending_mode = next_mode
	_mode = "glitch"
	_remaining_seconds = GLITCH_DURATION_SECONDS
	_glitch.visible = true


func _finish_transition() -> void:
	_glitch.visible = false
	if _pending_mode == "static":
		_show_static()
		return
	_start_next_clip()


func _start_next_clip() -> void:
	if _clips.is_empty():
		_show_static()
		return
	_clip_index += 1
	if _clip_index >= _clips.size():
		_show_static()
		return
	_frame_index = 0
	_show_current_frame()


func _show_current_frame() -> void:
	var clip: Dictionary = _clips[_clip_index]
	var frames: Array = clip.get("frames", [])
	if frames.is_empty():
		_start_next_clip()
		return
	var frame: Dictionary = frames[_frame_index]
	_background.texture = frame.get("texture")
	_remaining_seconds = float(frame.get("duration_seconds", 0.1))
	_mode = "clip"


func _advance_frame() -> void:
	var clip: Dictionary = _clips[_clip_index]
	var frames: Array = clip.get("frames", [])
	_frame_index += 1
	if _frame_index >= frames.size():
		_begin_transition("static" if _clip_index + 1 >= _clips.size() else "clip")
		return
	_show_current_frame()


func _update_timestamp() -> void:
	var now: Dictionary = Time.get_datetime_dict_from_system()
	_timestamp.text = "%04d-%02d-%02d  %02d:%02d:%02d" % [
		int(now.get("year", 0)), int(now.get("month", 0)), int(now.get("day", 0)),
		int(now.get("hour", 0)), int(now.get("minute", 0)), int(now.get("second", 0)),
	]
