extends TextureRect
class_name MainMenuCrestPlayer

const PLAYLIST_PATH := "res://games/rollback_fighter/fighter_assets/main_menu/generated/playlist.json"
const OVERLAY_SIZE := 168.0
const EDGE_MARGIN := 20.0
const MINIMUM_FRAME_SECONDS := 0.02

var _frames: Array[Dictionary] = []
var _frame_index: int = 0
var _remaining_seconds: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	anchor_left = 1.0
	anchor_right = 1.0
	anchor_top = 0.0
	anchor_bottom = 0.0
	offset_left = -OVERLAY_SIZE - EDGE_MARGIN
	offset_right = -EDGE_MARGIN
	offset_top = EDGE_MARGIN
	offset_bottom = OVERLAY_SIZE + EDGE_MARGIN
	_load_frames()
	if _frames.is_empty():
		visible = false
		set_process(false)
		return
	visible = true
	_show_frame(0)
	set_process(true)


func _process(delta: float) -> void:
	_remaining_seconds -= delta
	while _remaining_seconds <= 0.0 and not _frames.is_empty():
		var overshoot: float = -_remaining_seconds
		_frame_index = (_frame_index + 1) % _frames.size()
		_show_frame(_frame_index)
		_remaining_seconds -= overshoot


func _load_frames() -> void:
	var file: FileAccess = FileAccess.open(PLAYLIST_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary:
		return
	var manifest: Dictionary = parsed
	var crest_value: Variant = manifest.get("crest", null)
	if not crest_value is Dictionary:
		return
	var crest: Dictionary = crest_value
	var frames_value: Variant = crest.get("frames", [])
	if not frames_value is Array:
		return
	for frame_value: Variant in frames_value:
		if not frame_value is Dictionary:
			continue
		var path: String = str(frame_value.get("path", ""))
		if not path.begins_with("res://games/rollback_fighter/fighter_assets/main_menu/generated/"):
			continue
		if not ResourceLoader.exists(path):
			continue
		var resource: Resource = load(path)
		var frame_texture: Texture2D = resource as Texture2D
		if frame_texture == null:
			continue
		_frames.append({
			"texture": frame_texture,
			"duration_seconds": maxf(float(frame_value.get("duration_seconds", 0.1)), MINIMUM_FRAME_SECONDS),
		})


func _show_frame(index: int) -> void:
	var frame: Dictionary = _frames[index]
	texture = frame.get("texture")
	_remaining_seconds = float(frame.get("duration_seconds", 0.1))
